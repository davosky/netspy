package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
)

// maxWorkers è il tetto massimo di connessioni TCP aperte in parallelo
// sull'intera scansione (non per-host). Un pool di worker di dimensione fissa
// mantiene costante il consumo di goroutine/descrittori qualunque sia
// l'ampiezza della subnet. Il numero effettivo di worker viene poi ridotto in
// base al limite di file descriptor del processo (vedi workerCount).
const maxWorkers = 2048

// discoveryPorts è il numero di porte campionate per host nella fase di
// discovery/liveness.
const discoveryPorts = 20

// hostCeiling è un tetto di sicurezza sul numero di indirizzi enumerati: oltre
// questa soglia il programma rifiuta di partire. L'app NetSpy applica un limite
// molto più stretto a monte (LanscanRunner); questo protegge l'uso stand-alone.
const hostCeiling = 65536

type result struct {
	host string
	port int
}

// hostReport è una device rilevata sulla rete: IP, MAC (se ricavabile dalla
// cache ARP) e porte TCP aperte trovate.
type hostReport struct {
	IP        string `json:"ip"`
	MAC       string `json:"mac,omitempty"`
	OpenPorts []int  `json:"open_ports"`
}

// scanReport è il documento emesso su stdout in modalità -format json: è NetSpy
// (LanscanRunner + LanscanJob) a salvarlo nel database dell'applicazione.
type scanReport struct {
	Target     string       `json:"target"`
	Ports      string       `json:"ports"`
	StartedAt  string       `json:"started_at"`
	FinishedAt string       `json:"finished_at"`
	HostsAlive int          `json:"hosts_alive"`
	Hosts      []hostReport `json:"hosts"`
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
// e inoltra le porte aperte su results. Il numero di worker è fisso, quindi il
// parallelismo totale non dipende dalla dimensione della subnet.
func scanWorker(jobs <-chan result, results chan<- result, timeout time.Duration, completed *int64, wg *sync.WaitGroup) {
	defer wg.Done()
	for j := range jobs {
		if scanPort(j.host, j.port, timeout) {
			results <- j
		}
		atomic.AddInt64(completed, 1)
	}
}

// raiseFileLimit alza (best-effort) il limite soft di file descriptor a quello
// hard, così il pool di worker può tenere aperte molte connessioni in parallelo.
func raiseFileLimit() {
	var lim syscall.Rlimit
	if syscall.Getrlimit(syscall.RLIMIT_NOFILE, &lim) != nil {
		return
	}
	lim.Cur = lim.Max
	_ = syscall.Setrlimit(syscall.RLIMIT_NOFILE, &lim)
}

// workerCount sceglie quanti worker usare: al più maxWorkers, e comunque non
// più di un terzo dei file descriptor disponibili, per lasciarne al resto del
// processo (log, DNS...).
func workerCount() int {
	workers := maxWorkers
	var lim syscall.Rlimit
	if syscall.Getrlimit(syscall.RLIMIT_NOFILE, &lim) == nil {
		if budget := int(lim.Cur / 3); budget < workers {
			workers = budget
		}
	}
	if workers < 64 {
		workers = 64
	}
	return workers
}

// samplePorts restituisce fino a n porte del range [start, end], distribuite in
// modo uniforme (estremi inclusi). Usato dalla fase di discovery.
func samplePorts(start, end, n int) []int {
	count := end - start + 1
	if count <= n {
		ports := make([]int, count)
		for i := range ports {
			ports[i] = start + i
		}
		return ports
	}
	step := count / n
	if step < 1 {
		step = 1
	}
	seen := make(map[int]bool, n+1)
	ports := make([]int, 0, n+1)
	for p := start; p <= end && len(ports) < n; p += step {
		seen[p] = true
		ports = append(ports, p)
	}
	if !seen[end] {
		ports = append(ports, end)
	}
	return ports
}

// probeAlive considera un host "vivo" se una connessione TCP riesce (porta
// aperta) oppure viene rifiutata subito (RST: host acceso, porta chiusa). Un
// timeout non è un segnale di presenza.
func probeAlive(host string, port int, timeout time.Duration) bool {
	conn, err := net.DialTimeout("tcp", net.JoinHostPort(host, strconv.Itoa(port)), timeout)
	if err == nil {
		conn.Close()
		return true
	}
	return errors.Is(err, syscall.ECONNREFUSED)
}

// discoverHosts campiona alcune porte per ogni host e restituisce (nell'ordine
// originale) solo quelli che danno un segnale di presenza. Riduce drasticamente
// il lavoro della scansione completa su subnet sparse e individua gli host vivi
// di cui provare a ricavare il MAC anche se non hanno porte aperte.
func discoverHosts(ips []string, ports []int, timeout time.Duration, workers int) []string {
	jobs := make(chan result, workers)
	hits := make(chan string, workers)
	var wg sync.WaitGroup
	for i := 0; i < workers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for j := range jobs {
				if probeAlive(j.host, j.port, timeout) {
					hits <- j.host
				}
			}
		}()
	}
	go func() {
		for _, host := range ips {
			for _, port := range ports {
				jobs <- result{host: host, port: port}
			}
		}
		close(jobs)
	}()
	go func() { wg.Wait(); close(hits) }()

	alive := make(map[string]struct{})
	for host := range hits {
		alive[host] = struct{}{}
	}
	live := make([]string, 0, len(alive))
	for _, host := range ips {
		if _, ok := alive[host]; ok {
			live = append(live, host)
		}
	}
	return live
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

// collectMAC restituisce il MAC di host leggendo la cache ARP. Se non c'è (host
// vivo ma mai contattato), tenta un dial veloce su una porta campione per far
// popolare la neighbour table al kernel, poi rilegge una volta. Best-effort:
// qualunque fallimento significa semplicemente "MAC non disponibile".
func collectMAC(host string, primePort int, timeout time.Duration) string {
	if mac, ok := getMACAddress(host); ok {
		return mac
	}
	if conn, err := net.DialTimeout("tcp", net.JoinHostPort(host, strconv.Itoa(primePort)), timeout); err == nil {
		conn.Close()
	}
	if mac, ok := getMACAddress(host); ok {
		return mac
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

// writeProgressFile scrive "<fatti> <totale>" nel file indicato in modo atomico
// (scrittura su file temporaneo + rename), così l'app NetSpy può leggerlo da un
// altro processo senza rischiare letture parziali. Se path è vuoto non fa nulla;
// gli errori sono ignorati (l'avanzamento è best-effort, non deve mai bloccare
// la scansione).
func writeProgressFile(path string, current, total int) {
	if path == "" {
		return
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, []byte(fmt.Sprintf("%d %d\n", current, total)), 0o644); err != nil {
		return
	}
	_ = os.Rename(tmp, path)
}

// fatal riporta un errore irreversibile e termina con exit code 1. In modalità
// json l'errore è un documento {"error": "..."} su stdout, così NetSpy lo può
// distinguere da un output valido; altrimenti è testo semplice.
func fatal(jsonMode bool, format string, args ...any) {
	msg := fmt.Sprintf(format, args...)
	if jsonMode {
		_ = json.NewEncoder(os.Stdout).Encode(struct {
			Error string `json:"error"`
		}{Error: msg})
	} else {
		fmt.Println(msg)
	}
	os.Exit(1)
}

func main() {
	target := flag.String("target", "10.182.1.0/24", "subnet da scansionare (CIDR)")
	ports := flag.String("ports", "1-1024", "range di porte da scansionare (es. 1-1024)")
	timeoutMs := flag.Int("timeout", 550, "timeout di connessione in millisecondi")
	format := flag.String("format", "text", "formato di output: text (CLI) o json (NetSpy)")
	logDir := flag.String("log-dir", ".", "cartella in cui salvare il file di log della scansione (solo -format text)")
	noLog := flag.Bool("no-log", false, "non scrivere alcun file di log (solo -format text)")
	progressFile := flag.String("progress-file", "", "file in cui scrivere l'avanzamento come \"<fatti> <totale>\"")
	discovery := flag.Bool("discovery", true, "individua gli host vivi prima della scansione completa (e per la raccolta dei MAC)")
	flag.Parse()

	jsonMode := *format == "json"
	if *format != "text" && *format != "json" {
		fatal(false, "errore: formato non valido: %s (usa text o json)", *format)
	}

	raiseFileLimit()
	workers := workerCount()

	timeout := time.Duration(*timeoutMs) * time.Millisecond

	ips, err := hostsInCIDR(*target)
	if err != nil {
		fatal(jsonMode, "errore parsing CIDR: %v", err)
	}
	if len(ips) > hostCeiling {
		fatal(jsonMode, "errore: subnet troppo ampia (%d indirizzi, max %d)", len(ips), hostCeiling)
	}

	startPort, endPort, err := parsePortRange(*ports)
	if err != nil {
		fatal(jsonMode, "errore parsing range porte: %v", err)
	}

	start := time.Now()

	// In modalità json stdout è riservato al documento finale: nessun rumore.
	out := io.Writer(io.Discard)
	if !jsonMode {
		out = io.Writer(os.Stdout)
		if !*noLog {
			logFilename := filepath.Join(*logDir, fmt.Sprintf("scan_%s.log", start.Format("20060102_150405")))
			logFile, err := os.Create(logFilename)
			if err != nil {
				fatal(false, "errore creazione file di log: %v", err)
			}
			defer logFile.Close()
			out = io.MultiWriter(os.Stdout, logFile)
			defer fmt.Fprintln(out, "Log salvato in:", logFilename)
		}
	}

	portCount := endPort - startPort + 1

	fmt.Fprintln(out, "Subnet:", *target)
	fmt.Fprintln(out, "Indirizzi IP nella subnet:", len(ips))
	fmt.Fprintln(out, "Inizio scansione:", start.Format("2006-01-02 15:04:05"))

	// Fase di discovery/liveness: su una subnet sparsa la maggior parte del
	// tempo se ne va in timeout su indirizzi che non esistono. Campionando poche
	// porte per host si scartano subito quelli senza segnali di presenza. Serve
	// anche a sapere quali host sono vivi per ricavarne il MAC dalla cache ARP
	// anche quando non hanno porte aperte nel range richiesto.
	hosts := ips
	if *discovery {
		fmt.Fprintf(out, "Discovery su %d indirizzi (%d porte campione)...\n", len(ips), discoveryPorts)
		hosts = discoverHosts(ips, samplePorts(startPort, endPort, discoveryPorts), timeout, workers)
		fmt.Fprintf(out, "Host che rispondono: %d/%d\n", len(hosts), len(ips))
	}

	totalProbes := len(hosts) * portCount

	var completed int64
	jobs := make(chan result, workers)
	results := make(chan result, workers)

	var wg sync.WaitGroup
	for i := 0; i < workers; i++ {
		wg.Add(1)
		go scanWorker(jobs, results, timeout, &completed, &wg)
	}

	// Un solo produttore alimenta il pool: le coppie (host, porta) sono create
	// una alla volta, non pre-allocate come goroutine.
	go func() {
		for _, host := range hosts {
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

	// Avanzamento: barra su stdout in modalità text, righe "PROGRESS f t" su
	// stderr in modalità json (NetSpy le legge dallo stream SSH). In entrambi i
	// casi si aggiorna anche -progress-file se richiesto.
	emitProgress := func(current, total int) {
		if jsonMode {
			fmt.Fprintf(os.Stderr, "PROGRESS %d %d\n", current, total)
		} else {
			printProgressBar(current, total)
		}
		writeProgressFile(*progressFile, current, total)
	}

	progressDone := make(chan struct{})
	go func() {
		defer close(progressDone)
		ticker := time.NewTicker(150 * time.Millisecond)
		defer ticker.Stop()
		for {
			select {
			case <-done:
				emitProgress(totalProbes, totalProbes)
				if !jsonMode {
					fmt.Println()
				}
				return
			case <-ticker.C:
				emitProgress(int(atomic.LoadInt64(&completed)), totalProbes)
			}
		}
	}()

	openPorts := make(map[string][]int)
	for r := range results {
		openPorts[r.host] = append(openPorts[r.host], r.port)
	}
	<-progressDone

	// Raccolta risultati: un record per ogni host vivo che ha porte aperte
	// OPPURE un MAC ricavabile dalla cache ARP.
	primePort := startPort
	reports := make([]hostReport, 0, len(hosts))
	first := true
	hostsWithOpenPorts := 0
	for _, host := range hosts {
		hostPorts := openPorts[host]
		sort.Ints(hostPorts)
		mac := collectMAC(host, primePort, timeout)

		if len(hostPorts) == 0 && mac == "" {
			continue
		}
		if len(hostPorts) > 0 {
			hostsWithOpenPorts++
		}

		if !first {
			fmt.Fprintln(out, "-------------------")
		}
		first = false
		if mac != "" {
			fmt.Fprintf(out, "%s (MAC: %s)\n", host, mac)
		} else {
			fmt.Fprintf(out, "%s\n", host)
		}
		for _, port := range hostPorts {
			fmt.Fprintf(out, "  %d APERTA\n", port)
		}

		reports = append(reports, hostReport{IP: host, MAC: mac, OpenPorts: hostPorts})
	}

	end := time.Now()

	if jsonMode {
		enc := json.NewEncoder(os.Stdout)
		enc.SetEscapeHTML(false)
		if err := enc.Encode(scanReport{
			Target:     *target,
			Ports:      *ports,
			StartedAt:  start.UTC().Format(time.RFC3339),
			FinishedAt: end.UTC().Format(time.RFC3339),
			HostsAlive: len(hosts),
			Hosts:      reports,
		}); err != nil {
			fatal(true, "errore serializzazione risultati: %v", err)
		}
		return
	}

	fmt.Fprintf(out, "\nHost con porte aperte trovati: %d\n", hostsWithOpenPorts)
	fmt.Fprintf(out, "Host con MAC rilevato: %d\n", countWithMAC(reports))
	fmt.Fprintln(out, "Fine scansione:", end.Format("2006-01-02 15:04:05"))
	fmt.Fprintln(out, "Durata:", end.Sub(start))
	fmt.Fprintln(out, "Scansione completata con successo.")
}

func countWithMAC(reports []hostReport) int {
	n := 0
	for _, r := range reports {
		if r.MAC != "" {
			n++
		}
	}
	return n
}
