# NetSpy

NetSpy è lo strumento per monitorare e tenere sotto controllo le reti
aziendali: **LAN, WAN, WLAN e WiFi**.

- Versione corrente: **0.0.3** — nome in codice *Golubiro* (vedi [`VERSION`](VERSION)).
- Licenza: **MIT** (vedi [LICENCE.md](LICENCE.md)).

---

## 🏗️ Stack tecnico

| Ambito        | Tecnologia |
|---------------|------------|
| Linguaggio    | Ruby 4.0.1 |
| Framework     | Ruby on Rails ~> 8.1.3 |
| Database      | PostgreSQL |
| Frontend      | Hotwire (Turbo + Stimulus) |
| CSS           | Bootstrap 5.3 + Bootswatch (tema *Slate*) + Bootstrap Icons |
| Asset         | Propshaft, Yarn (`nodeLinker: node-modules`), esbuild + Dart Sass |
| Autenticazione| Devise (login via `username`), con `lockable` e cambio password self-service |
| Autorizzazione| Pundit (`ApplicationPolicy`: tutto agli `admin`, negato di default) |
| Admin         | Administrate, montato su `/admin` (solo `admin`) |
| Localizzazione| i18n, `default_locale = :it` (`:it`, `:en` disponibili) |
| Test          | RSpec + FactoryBot + Capybara |
| Deploy        | Alma Linux + Apache + Phusion Passenger |

---

## 🚀 Avvio del progetto

```bash
bin/setup   # setup iniziale (dipendenze Ruby/JS, creazione e migrazione DB)
bin/dev     # avvia Rails + watcher JS (esbuild) + watcher CSS (Sass)
```

L'applicazione legge le variabili d'ambiente da `.env` (gestite da
`dotenv-rails`):

| Variabile          | Descrizione |
|--------------------|-------------|
| `DATABASE_HOST`    | host PostgreSQL (es. `localhost`) |
| `DATABASE_USER`    | utente del database |
| `DATABASE_PASSWORD`| password del database |
| `SECRET_KEY_BASE`  | segreto Rails (`bin/rails secret`) |
| `ADMIN_*`          | dati dell'utente admin creato da `db/seeds.rb` (idempotente) |

> **Due utenti di database separati, mai le stesse credenziali:** uno per lo
> sviluppo (credenziali reali, mai versionate) e uno per test / `db/seeds.rb`
> (credenziali palesemente fittizie).

---

## 🔐 Autenticazione e accessi

- Login tramite **username** (l'email resta obbligatoria ma non è chiave di login);
  lookup e unicità dello username sono case-insensitive.
- **Autoregistrazione disabilitata**: non esiste la rotta di sign up. Gli utenti
  vengono creati da un `admin` tramite Administrate (`/admin/users`) o dai seed.
- Account **lockable**: 3 tentativi falliti bloccano l'account.
- Cambio password self-service da `/account/password/edit`.

---

## 🗺️ Rotte principali

| Percorso                 | Descrizione |
|--------------------------|-------------|
| `/`                      | landing page (richiede login) |
| `/users/sign_in`         | login (Devise) |
| `/account/password/edit` | cambio password dell'utente corrente |
| `/credits`               | pagina crediti |
| `/admin`                 | pannello Administrate (solo `admin`) |
| `/up`                    | health check Rails |

---

## 🧪 Test e qualità

```bash
bundle exec rspec            # suite di test (spec/)
bin/ci                       # pipeline completa: rubocop, bundler-audit,
                             # yarn audit, brakeman, rspec, seeds
bundle exec rubocop -A       # auto-fix stile
bundle exec brakeman         # analisi statica di sicurezza
```

Tutti i test girano **esclusivamente sul database di test**; il database di
sviluppo non va mai usato per i test.

---

## 📦 Aggiornare il grafo della conoscenza

Il progetto mantiene un knowledge graph in `graphify-out/`:

```bash
graphify update .                 # aggiorna il grafo dopo modifiche al codice (solo AST)
graphify query "<domanda>"        # interroga la codebase
```

---

## 📄 Licenza

Distribuito sotto licenza **MIT**. Vedi [LICENCE.md](LICENCE.md) (testo in
italiano e inglese).

_Codice sviluppato con l'apporto di intelligenza artificiale._
