# Fitupe

Fitupe è un'applicazione web per raccogliere e analizzare le iscrizioni al
sindacato, con l'obiettivo di costruire statistiche coerenti sul loro
andamento nel tempo. Il nome è l'acronimo di Fisher, Tukey e Pearson, tra
i più influenti statistici della storia (vedi [FITUPE.md](FITUPE.md) per
l'origine del nome e del logo).

## Stack tecnico

- Ruby on Rails 8, PostgreSQL
- Hotwire (Turbo + Stimulus), Bootstrap + Bootswatch Lumen
- Devise (autenticazione via username) e Pundit (autorizzazione)
- Administrate come pannello di amministrazione
- RSpec, FactoryBot e Capybara per i test

## Avvio del progetto

```bash
bin/setup   # setup iniziale (dipendenze, database)
bin/dev     # avvia Rails, il watcher JS (esbuild) e quello CSS (Sass)
```

L'applicazione richiede le variabili d'ambiente `DATABASE_HOST`,
`DATABASE_USER`, `DATABASE_PASSWORD` e `SECRET_KEY_BASE` (vedi `.env`,
gestite tramite `dotenv-rails`).

## Licenza

Distribuito sotto licenza MIT. Vedi [LICENCE.md](LICENCE.md).
