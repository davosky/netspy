package main

import (
	"bufio"
	"database/sql"
	"flag"
	"fmt"
	"io"
	"net"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/joho/godotenv"
	"github.com/lib/pq"
)

// maxConcurrentProbes limita il numero totale di connessioni TCP aperte in
// parallelo sull'intera scansione (non per-host). Con un pool di worker di
// dimensione fissa il consumo di goroutine/descrittori resta costante qualunque
// sia l'ampiezza della subnet: senza questo limite una subnet molto grande
// (es. /8) farebbe esplodere memoria e file descriptor del processo.
const maxConcurrentProbes = 512

// hostCeiling è un tetto di sicurezza sul numero di indirizzi enumerati: oltre
// questa soglia il programma rifiuta di partire. L'app NetSpy applica un limite
// molto più stretto a monte (LanscanRunner); questo protegge l'uso stand-alone.
const hostCeiling = 65536

// tableNamePattern limita il valore di -table a un identificatore SQL semplice
// (niente schema-qualified, niente virgolette): l'unico modo sicuro di
// interpolare un nome di tabella in una query, dato che non può essere un
// placeholder. Il valore viene comunque passato a pq.QuoteIdentifier.
var tableNamePattern = regexp.MustCompile(`^[a-z_][a-z0-9_]*$`)

type result struct {
	host string
	port int
}

func hostsInCIDR(cidr string) ([]string, error) {
	_, ipnet, err := net.ParseCIDR(cidr)
	if err != nil {
		return nil, err
	}
	var ips []string
	for ip := ipnet.IP.Mask(ipnet.Mask); ipnet.Contains(ip); incIP(ip) {
		ips = append(ips, ip.String())
	}
	return ips, nil
}

func incIP(ip net.IP) {
	for i := len(ip) - 1; i >= 0; i-- {
		ip[i]++
		if ip[i] != 0 {
			break
		}
	}
}

func scanPort(host string, port int, timeout time.Duration) bool {
	address := net.JoinHostPort(host, strconv.Itoa(port))
	conn, err := net.DialTimeout("tcp", address, timeout)
	if err != nil {
		return false
	}
	conn.Close()
	return true
}

func parsePortRange(s string) (int, int, error) {
	parts := strings.Split(s, "-")
	if len(parts) != 2 {
		return 0, 0, fmt.Errorf("formato range porte non valido, usa START-END (es. 1-1024)")
	}
	startPort, err := strconv.Atoi(parts[0])
	if err != nil {
		return 0, 0, fmt.Errorf("porta iniziale non valida: %v", err)
	}
	endPort, err := strconv.Atoi(parts[1])
	if err != nil {
		return 0, 0, fmt.Errorf("porta finale non valida: %v", err)
	}
	if startPort < 1 || endPort > 65535 || startPort > endPort {
		return 0, 0, fmt.Errorf("range porte non valido: %d-%d", startPort, endPort)
	}
	return startPort, endPort, nil
}

// scanWorker consuma coppie (host, porta) dal canale jobs, prova la connessione
// e inoltra le porte aperte su results. Il numero di worker è fisso
// (maxConcurrentProbes), quindi il parallelismo totale non dipende dalla
// dimensione della subnet.
func scanWorker(jobs <-chan result, results chan<- result, timeout time.Duration, completed *int64, wg *sync.WaitGroup) {
	defer wg.Done()
	for j := range jobs {
		if scanPort(j.host, j.port, timeout) {
			results <- j
		}
		atomic.AddInt64(completed, 1)
	}
}

// getMACAddress cerca il MAC address di un IP nella cache ARP del sistema
// (/proc/net/arp, Linux). Se non lo trova non blocca: ritorna ok=false.
func getMACAddress(ip string) (string, bool) {
	file, err := os.Open("/proc/net/arp")
	if err != nil {
		return "", false
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	scanner.Scan() // salta l'header
	for scanner.Scan() {
		fields := strings.Fields(scanner.Text())
		if len(fields) < 4 || fields[0] != ip {
			continue
		}
		mac := fields[3]
		if mac == "00:00:00:00:00:00" {
			return "", false
		}
		return mac, true
	}
	return "", false
}

// connectDatabase apre la connessione al database PostgreSQL dei risultati.
//
// Ordine di precedenza per determinare come connettersi:
//  1. LANSCAN_DATABASE_URL — usato dall'app NetSpy quando lancia il binario:
//     una connection string PostgreSQL completa.
//  2. DATABASE_URL — stesso formato, fallback generico.
//  3. Variabili discrete legacy dal file .env (DATABASEHOST/NAME/USER/PASSWORD),
//     con sslmode=prefer, per l'uso stand-alone da riga di comando.
//  4. Nessun DSN: lib/pq legge da sé le variabili libpq standard
//     (PGHOST, PGPORT, PGUSER, PGPASSWORD, PGDATABASE, PGSSLMODE...).
func connectDatabase() (*sql.DB, error) {
	_ = godotenv.Load() // .env opzionale: se manca si prosegue con l'ambiente

	dsn := firstNonEmpty(
		os.Getenv("LANSCAN_DATABASE_URL"),
		os.Getenv("DATABASE_URL"),
	)

	if dsn == "" && os.Getenv("DATABASEHOST") != "" {
		// Costruita come URL (non con fmt.Sprintf "key=value") perché net/url
		// percent-encoda correttamente ogni carattere speciale in host/user/
		// password: un valore con spazi o "=" incorporati in una stringa
		// key=value costruita a mano potrebbe iniettare parametri di
		// connessione aggiuntivi non previsti.
		dsn = (&url.URL{
			Scheme:   "postgres",
			User:     url.UserPassword(os.Getenv("DATABASEUSER"), os.Getenv("DATABASEPASSWORD")),
			Host:     os.Getenv("DATABASEHOST"),
			Path:     "/" + os.Getenv("DATABASENAME"),
			RawQuery: "sslmode=prefer",
		}).String()
	}

	db, err := sql.Open("postgres", dsn)
	if err != nil {
		return nil, err
	}
	if err := db.Ping(); err != nil {
		db.Close()
		return nil, err
	}
	return db, nil
}

func firstNonEmpty(values ...string) string {
	for _, v := range values {
		if v != "" {
			return v
		}
	}
	return ""
}

func printProgressBar(current, total int) {
	const width = 40
	if total == 0 {
		total = 1
	}
	percent := float64(current) / float64(total)
	filled := int(percent * width)
	bar := strings.Repeat("=", filled) + strings.Repeat(" ", width-filled)
	fmt.Printf("\r[%s] %3.0f%% (%d/%d)", bar, percent*100, current, total)
}

func main() {
	target := flag.String("target", "10.182.1.0/24", "subnet da scansionare (CIDR)")
	ports := flag.String("ports", "1-1024", "range di porte da scansionare (es. 1-1024)")
	timeoutMs := flag.Int("timeout", 700, "timeout di connessione in millisecondi")
	table := flag.String("table", "lanscans", "tabella PostgreSQL in cui salvare i risultati")
	logDir := flag.String("log-dir", ".", "cartella in cui salvare il file di log della scansione")
	noLog := flag.Bool("no-log", false, "non scrivere alcun file di log (solo stdout)")
	flag.Parse()

	if !tableNamePattern.MatchString(*table) {
		fmt.Println("errore: nome tabella non valido:", *table)
		os.Exit(1)
	}

	timeout := time.Duration(*timeoutMs) * time.Millisecond

	ips, err := hostsInCIDR(*target)
	if err != nil {
		fmt.Println("errore parsing CIDR:", err)
		os.Exit(1)
	}
	if len(ips) > hostCeiling {
		fmt.Printf("errore: subnet troppo ampia (%d indirizzi, max %d)\n", len(ips), hostCeiling)
		os.Exit(1)
	}

	startPort, endPort, err := parsePortRange(*ports)
	if err != nil {
		fmt.Println("errore parsing range porte:", err)
		os.Exit(1)
	}

	start := time.Now()

	out := io.Writer(os.Stdout)
	if !*noLog {
		logFilename := filepath.Join(*logDir, fmt.Sprintf("scan_%s.log", start.Format("20060102_150405")))
		logFile, err := os.Create(logFilename)
		if err != nil {
			fmt.Println("errore creazione file di log:", err)
			os.Exit(1)
		}
		defer logFile.Close()
		out = io.MultiWriter(os.Stdout, logFile)
		defer fmt.Fprintln(out, "Log salvato in:", logFilename)
	}

	fmt.Fprintln(out, "Subnet:", *target)
	fmt.Fprintln(out, "Indirizzi IP da scansionare:", len(ips))
	fmt.Fprintln(out, "Inizio scansione:", start.Format("2006-01-02 15:04:05"))

	portCount := endPort - startPort + 1
	totalProbes := len(ips) * portCount

	var completed int64
	jobs := make(chan result, maxConcurrentProbes)
	results := make(chan result, maxConcurrentProbes)

	var wg sync.WaitGroup
	for i := 0; i < maxConcurrentProbes; i++ {
		wg.Add(1)
		go scanWorker(jobs, results, timeout, &completed, &wg)
	}

	// Un solo produttore alimenta il pool: le coppie (host, porta) sono create
	// una alla volta, non pre-allocate come goroutine.
	go func() {
		for _, host := range ips {
			for port := startPort; port <= endPort; port++ {
				jobs <- result{host: host, port: port}
			}
		}
		close(jobs)
	}()

	done := make(chan struct{})
	go func() {
		wg.Wait()
		close(done)
		close(results)
	}()

	progressDone := make(chan struct{})
	go func() {
		defer close(progressDone)
		ticker := time.NewTicker(150 * time.Millisecond)
		defer ticker.Stop()
		for {
			select {
			case <-done:
				printProgressBar(totalProbes, totalProbes)
				fmt.Println()
				return
			case <-ticker.C:
				printProgressBar(int(atomic.LoadInt64(&completed)), totalProbes)
			}
		}
	}()

	openPorts := make(map[string][]int)
	for r := range results {
		openPorts[r.host] = append(openPorts[r.host], r.port)
	}
	<-progressDone

	db, err := connectDatabase()
	if err != nil {
		fmt.Println("errore connessione al database:", err)
		os.Exit(1)
	}
	defer db.Close()

	insertStmt, err := db.Prepare(fmt.Sprintf(
		`INSERT INTO %s (scanned_at, target, ip_address, mac_address, open_ports) VALUES ($1, $2, $3, $4, $5)`,
		pq.QuoteIdentifier(*table),
	))
	if err != nil {
		fmt.Println("errore preparazione query database:", err)
		os.Exit(1)
	}
	defer insertStmt.Close()

	first := true
	hostsWithOpenPorts := 0
	saveErrors := 0
	for _, host := range ips {
		ports := openPorts[host]
		if len(ports) == 0 {
			continue
		}
		hostsWithOpenPorts++
		if !first {
			fmt.Fprintln(out, "-------------------")
		}
		first = false

		mac, macFound := getMACAddress(host)
		if macFound {
			fmt.Fprintf(out, "%s (MAC: %s)\n", host, mac)
		} else {
			fmt.Fprintf(out, "%s\n", host)
		}

		sort.Ints(ports)
		portStrs := make([]string, len(ports))
		for i, port := range ports {
			fmt.Fprintf(out, "  %d APERTA\n", port)
			portStrs[i] = strconv.Itoa(port)
		}

		var macValue interface{}
		if macFound {
			macValue = mac
		}
		if _, err := insertStmt.Exec(start, *target, host, macValue, strings.Join(portStrs, " ")); err != nil {
			fmt.Fprintf(out, "  errore salvataggio su database: %v\n", err)
			saveErrors++
		}
	}

	end := time.Now()
	fmt.Fprintf(out, "\nHost con porte aperte trovati: %d\n", hostsWithOpenPorts)
	fmt.Fprintln(out, "Fine scansione:", end.Format("2006-01-02 15:04:05"))
	fmt.Fprintln(out, "Durata:", end.Sub(start))
	fmt.Fprintf(out, "Risultati salvati nel database PostgreSQL (tabella %q).\n", *table)
	if saveErrors > 0 {
		fmt.Fprintf(out, "Attenzione: %d righe non salvate per errori database.\n", saveErrors)
		os.Exit(1)
	}
	fmt.Fprintln(out, "Scansione completata con successo.")
}
