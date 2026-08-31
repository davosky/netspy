# NetSpy

**🇮🇹 [Italiano](#italiano) · 🇬🇧 [English](#english)**

- Versione / Version: **0.0.3** — nome in codice / codename _Golubiro_ (vedi / see [`VERSION`](VERSION)).
- Licenza / License: **MIT** (vedi / see [LICENCE.md](LICENCE.md)).

---

## Italiano

NetSpy è lo strumento per monitorare e tenere sotto controllo le reti
aziendali: **LAN, WAN, WLAN e WiFi**.

### 🏗️ Stack tecnico

| Ambito         | Tecnologia                                                                   |
| -------------- | ---------------------------------------------------------------------------- |
| Linguaggio     | Ruby 4.0.1                                                                   |
| Framework      | Ruby on Rails ~> 8.1.3                                                       |
| Database       | PostgreSQL                                                                   |
| Frontend       | Hotwire (Turbo + Stimulus)                                                   |
| CSS            | Bootstrap 5.3 + Bootswatch (tema _Slate_) + Bootstrap Icons                  |
| Asset          | Propshaft, Yarn (`nodeLinker: node-modules`), esbuild + Dart Sass            |
| Autenticazione | Devise (login via `username`), con `lockable` e cambio password self-service |
| Autorizzazione | Pundit (`ApplicationPolicy`: tutto agli `admin`, negato di default)          |
| Admin          | Administrate, montato su `/admin` (solo `admin`)                             |
| Localizzazione | i18n, `default_locale = :it` (`:it`, `:en` disponibili)                      |
| Test           | RSpec + FactoryBot + Capybara                                                |
| Deploy         | Alma Linux + Apache + Phusion Passenger                                      |

### 🚀 Avvio del progetto

```bash
bin/setup   # setup iniziale (dipendenze Ruby/JS, creazione e migrazione DB)
bin/dev     # avvia Rails + watcher JS (esbuild) + watcher CSS (Sass)
```

L'applicazione legge le variabili d'ambiente da `.env` (gestite da
`dotenv-rails`):

| Variabile           | Descrizione                                                  |
| ------------------- | ------------------------------------------------------------ |
| `DATABASE_HOST`     | host PostgreSQL (es. `localhost`)                            |
| `DATABASE_USER`     | utente del database                                          |
| `DATABASE_PASSWORD` | password del database                                        |
| `SECRET_KEY_BASE`   | segreto Rails (`bin/rails secret`)                           |
| `ADMIN_*`           | dati dell'utente admin creato da `db/seeds.rb` (idempotente) |
| `LANSCAN_SSH_KEY`      | _opzionale_ — chiave privata SSH dedicata per le LAN secondarie (default: config SSH di sistema) |
| `LANSCAN_KNOWN_HOSTS`  | _opzionale_ — `known_hosts` dedicato (default: `~/.ssh/known_hosts` dell'utente) |
| `LANSCAN_REMOTE_BIN`   | _opzionale_ — comando `lanscan` sul client remoto (default: `lanscan` sul PATH) |

> **Due utenti di database separati, mai le stesse credenziali:** uno per lo
> sviluppo (credenziali reali, mai versionate) e uno per test / `db/seeds.rb`
> (credenziali palesemente fittizie).

### 🔐 Autenticazione e accessi

- Login tramite **username** (l'email resta obbligatoria ma non è chiave di login);
  lookup e unicità dello username sono case-insensitive.
- **Autoregistrazione disabilitata**: non esiste la rotta di sign up. Gli utenti
  vengono creati da un `admin` tramite Administrate (`/admin/users`) o dai seed.
- Account **lockable**: 3 tentativi falliti bloccano l'account.
- Cambio password self-service da `/account/password/edit`.

### 📡 Scansione LAN (`lanscan`) — architettura client‑server

Port + MAC scanner concorrente scritto in Go (`vendor/lanscan/`), compilato in
`vendor/lanscan/bin/lanscan` (binario `linux/amd64` statico e versionato,
ricompilabile con `bin/build-lanscan`; incluso anche in `bin/setup`). Emette un
report **JSON su stdout**: è NetSpy a salvarlo nel database.

Le sottoreti da scansionare sono record del modello **`Lan`**, gestiti da un
`admin` in `/admin/lans`:

| Campo              | Significato                                                    |
| ------------------ | ------------------------------------------------------------- |
| `lan`              | sottorete da scansionare (CIDR)                              |
| `ports`            | intervallo porte (default `1-1024`)                         |
| `timeout`          | timeout di connessione in ms (default `600`)                |
| `primary`          | LAN primaria: dove risiede il server, scansione **locale**  |
| `secondary`        | LAN secondaria: scansione via **client remoto**             |
| `remote_client_ip` | IP del client Linux dentro la LAN secondaria                |
| `remote_user`      | utente SSH sul client remoto                                 |
| `binpath`          | percorso dell'eseguibile `lanscan` (locale o sul client)    |

- Su `/lanscans` (voce di navbar «Scansioni LAN») si sceglie una `Lan` dal menù
  e si mette in coda un `LanscanJob`.
- Per una LAN **primaria** `LanscanRunner` esegue il binario in locale. Per una
  LAN **secondaria** esegue `ssh <remote_user>@<remote_client_ip> lanscan …`,
  così l'ARP di quella LAN — e quindi i MAC address — è visibile. Di default si
  appoggia alla **config SSH dell'utente che esegue Rails** (`~/.ssh/config`,
  chiave/agent, `known_hosts`): è sufficiente che `ssh <utente>@<ip>` funzioni a
  mano. `LANSCAN_SSH_KEY` / `LANSCAN_KNOWN_HOSTS` servono solo per forzare una
  chiave o un `known_hosts` dedicati. WAN / VLAN / WiFi sono semplicemente LAN
  secondarie con un client al loro interno.
- `LanscanJob` interpreta il JSON e scrive una riga per host (porte aperte e/o
  MAC) nella tabella `lanscans`. Barra di avanzamento live anche per le
  scansioni remote (righe `PROGRESS` sullo stream SSH).
- Installazione del client: `rake lanscan:package` crea
  `tmp/lanscan-client.tar.gz` (binario + `INSTALL.md`); `rake 'lanscan:deploy[ID]'`
  copia il binario sul client di quella LAN via `scp`. La chiave pubblica va
  autorizzata a mano sul client (`~/.ssh/authorized_keys`).
- I risultati sono su `/lanscans` (raggruppati per esecuzione) e nel pannello
  Administrate `/admin/lanscans`.
- Non richiede root (connect scan TCP). Il MAC address è letto da
  `/proc/net/arp` (solo Linux); altrove resta vuoto.

### 🗺️ Rotte principali

| Percorso                 | Descrizione                          |
| ------------------------ | ------------------------------------ |
| `/`                      | landing page (richiede login)        |
| `/users/sign_in`         | login (Devise)                       |
| `/account/password/edit` | cambio password dell'utente corrente |
| `/credits`               | pagina crediti                       |
| `/admin`                 | pannello Administrate (solo `admin`) |
| `/up`                    | health check Rails                   |

### 🧪 Test e qualità

```bash
bundle exec rspec            # suite di test (spec/)
bin/ci                       # pipeline completa: rubocop, bundler-audit,
                             # yarn audit, brakeman, rspec, seeds
bundle exec rubocop -A       # auto-fix stile
bundle exec brakeman         # analisi statica di sicurezza
```

Tutti i test girano **esclusivamente sul database di test**; il database di
sviluppo non va mai usato per i test.

### 📄 Licenza

Distribuito sotto licenza **MIT**. Vedi [LICENCE.md](LICENCE.md) (testo in
italiano e inglese).

_Codice sviluppato con l'apporto della intelligenza artificiale._

---

## English

NetSpy is the tool for monitoring and keeping corporate networks under
control: **LAN, WAN, WLAN and WiFi**.

### 🏗️ Tech stack

| Area           | Technology                                                                      |
| -------------- | ------------------------------------------------------------------------------- |
| Language       | Ruby 4.0.1                                                                      |
| Framework      | Ruby on Rails ~> 8.1.3                                                          |
| Database       | PostgreSQL                                                                      |
| Frontend       | Hotwire (Turbo + Stimulus)                                                      |
| CSS            | Bootstrap 5.3 + Bootswatch (_Slate_ theme) + Bootstrap Icons                    |
| Assets         | Propshaft, Yarn (`nodeLinker: node-modules`), esbuild + Dart Sass               |
| Authentication | Devise (login via `username`), with `lockable` and self-service password change |
| Authorization  | Pundit (`ApplicationPolicy`: everything for `admin`, denied by default)         |
| Admin          | Administrate, mounted at `/admin` (`admin` only)                                |
| Localization   | i18n, `default_locale = :it` (`:it`, `:en` available)                           |
| Testing        | RSpec + FactoryBot + Capybara                                                   |
| Deployment     | Alma Linux + Apache + Phusion Passenger                                         |

### 🚀 Getting started

```bash
bin/setup   # initial setup (Ruby/JS dependencies, database creation and migration)
bin/dev     # starts Rails + JS watcher (esbuild) + CSS watcher (Sass)
```

The application reads environment variables from `.env` (managed by
`dotenv-rails`):

| Variable            | Description                                                   |
| ------------------- | ------------------------------------------------------------- |
| `DATABASE_HOST`     | PostgreSQL host (e.g. `localhost`)                            |
| `DATABASE_USER`     | database user                                                 |
| `DATABASE_PASSWORD` | database password                                             |
| `SECRET_KEY_BASE`   | Rails secret (`bin/rails secret`)                             |
| `ADMIN_*`           | data for the admin user created by `db/seeds.rb` (idempotent) |
| `LANSCAN_SSH_KEY`      | _optional_ — dedicated SSH private key for secondary LANs (default: system SSH config) |
| `LANSCAN_KNOWN_HOSTS`  | _optional_ — dedicated `known_hosts` file (default: the user's `~/.ssh/known_hosts`) |
| `LANSCAN_REMOTE_BIN`   | _optional_ — `lanscan` command on the remote client (default: `lanscan` on PATH) |

> **Two separate database users, never the same credentials:** one for
> development (real credentials, never committed) and one for tests /
> `db/seeds.rb` (obviously fake credentials).

### 🔐 Authentication and access

- Login by **username** (email is still required but is not the login key);
  username lookup and uniqueness are case-insensitive.
- **Self-registration disabled**: there is no sign-up route. Users are created
  by an `admin` via Administrate (`/admin/users`) or by the seeds.
- **Lockable** accounts: 3 failed attempts lock the account.
- Self-service password change at `/account/password/edit`.

### 📡 LAN scan (`lanscan`) — client‑server architecture

Concurrent port + MAC scanner written in Go (`vendor/lanscan/`), compiled to
`vendor/lanscan/bin/lanscan` (a committed, static `linux/amd64` binary, rebuilt
with `bin/build-lanscan`; also run from `bin/setup`). It prints a **JSON report
on stdout**; NetSpy is what stores it.

Subnets to scan are `Lan` records, managed by an `admin` at `/admin/lans`:
`lan` (CIDR), `ports`, `timeout`, `primary` / `secondary`, `remote_client_ip`,
`remote_user`, `binpath`.

- On `/lanscans` (navbar «Scansioni LAN») you pick a `Lan` and enqueue a
  `LanscanJob`.
- A **primary** LAN is scanned locally; a **secondary** LAN is scanned by
  running `ssh <remote_user>@<remote_client_ip> lanscan …` on its dedicated
  client, so that LAN's ARP table — and its MAC addresses — are visible. By
  default it relies on the SSH config of the user running Rails (`~/.ssh/config`,
  key/agent, `known_hosts`): it just needs `ssh <user>@<ip>` to work by hand.
  `LANSCAN_SSH_KEY` / `LANSCAN_KNOWN_HOSTS` only pin a dedicated key / known_hosts
  file. WAN / VLAN / WiFi are just secondary LANs with a client inside them.
- `LanscanJob` parses the JSON and writes one row per host (open ports and/or a
  MAC) into the `lanscans` table. The live progress bar works for remote scans
  too (`PROGRESS` lines over the SSH stream).
- Client install: `rake lanscan:package` builds `tmp/lanscan-client.tar.gz`
  (binary + `INSTALL.md`); `rake 'lanscan:deploy[ID]'` `scp`s the binary onto
  that LAN's client. The public key is authorised on the client by hand.
- Results are at `/lanscans` (grouped by run) and in the Administrate panel at
  `/admin/lanscans`.
- No root needed (TCP connect scan). The MAC address is read from
  `/proc/net/arp` (Linux only); elsewhere it stays empty.

### 🗺️ Main routes

| Path                     | Description                       |
| ------------------------ | --------------------------------- |
| `/`                      | landing page (login required)     |
| `/users/sign_in`         | login (Devise)                    |
| `/account/password/edit` | current user's password change    |
| `/credits`               | credits page                      |
| `/admin`                 | Administrate panel (`admin` only) |
| `/up`                    | Rails health check                |

### 🧪 Testing and quality

```bash
bundle exec rspec            # test suite (spec/)
bin/ci                       # full pipeline: rubocop, bundler-audit,
                             # yarn audit, brakeman, rspec, seeds
bundle exec rubocop -A       # style auto-fix
bundle exec brakeman         # static security analysis
```

All tests run **exclusively against the test database**; the development
database must never be used for tests.

### 📄 License

Distributed under the **MIT** license. See [LICENCE.md](LICENCE.md) (text in
Italian and English).

_Software developed with the contribution of AI._
