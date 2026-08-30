# vendor/lanscan

Concurrent LAN port scanner (Go), adapted from the standalone `port_scanner`
toolset for NetSpy. It scans a CIDR subnet over a TCP port range and writes one
row per host with open ports into the `lanscans` table of the NetSpy database.

NetSpy drives it through `LanscanRunner` (`app/services/lanscan_runner.rb`),
which validates the parameters and passes the DB connection via `PG*`
environment variables. It can also be run by hand.

## Build

```bash
bin/build-lanscan          # → vendor/lanscan/bin/lanscan (committed)
```

The compiled `linux/amd64` binary is committed so deploys with no Go toolchain
work out of the box. Rebuild after editing `main.go`, or for another platform:

```bash
cd vendor/lanscan && GOOS=darwin GOARCH=arm64 go build -o bin/lanscan-darwin .
```

## Flags

| Flag       | Default          | Meaning |
|------------|------------------|---------|
| `-target`  | `10.182.1.0/24`  | subnet to scan, CIDR notation |
| `-ports`   | `1-1024`         | TCP port range, `START-END` |
| `-timeout` | `700`            | per-port connect timeout (ms) |
| `-table`   | `lanscans`       | destination PostgreSQL table |
| `-log-dir` | `.`              | directory for the `scan_<timestamp>.log` file |
| `-no-log`  | `false`          | do not write a log file (stdout only) |

## Database connection

Resolved in this order:

1. `LANSCAN_DATABASE_URL` — full PostgreSQL connection string (used by NetSpy).
2. `DATABASE_URL` — same format.
3. Legacy `.env` file with `DATABASEHOST` / `DATABASENAME` / `DATABASEUSER` /
   `DATABASEPASSWORD` (stand-alone CLI use), `sslmode=prefer`.
4. Otherwise `lib/pq` reads the standard `PGHOST`, `PGPORT`, `PGUSER`,
   `PGPASSWORD`, `PGDATABASE`, `PGSSLMODE` variables — this is how
   `LanscanRunner` passes NetSpy's credentials.

Needs no root: it uses a TCP connect scan, not raw sockets. MAC addresses are
read from `/proc/net/arp` (Linux only); the column stays `NULL` elsewhere.
