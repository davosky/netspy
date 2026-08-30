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
| `-target`    | `10.182.1.0/24`  | subnet to scan, CIDR notation |
| `-ports`     | `1-1024`         | TCP port range, `START-END` |
| `-timeout`   | `550`            | per-port connect timeout (ms) |
| `-discovery` | `true`           | skip hosts that give no sign of life before the full scan |
| `-table`     | `lanscans`       | destination PostgreSQL table |
| `-log-dir`   | `.`              | directory for the `scan_<timestamp>.log` file |
| `-no-log`    | `false`          | do not write a log file (stdout only) |
| `-run-id`    | `0`              | id of the `lanscan_runs` row to link results to (0 = none) |
| `-progress-file` | *(none)*     | file to write `"<done> <total>"` progress to |

## Speed

Two things keep a scan fast on a sparse subnet, where most of the time would
otherwise be spent waiting out the connect timeout on addresses that don't
exist:

1. **Discovery phase** (`-discovery`, on by default when the port range is wider
   than 64): each host is first probed on ~20 sampled ports; only hosts that
   answer (open port, or an immediate `connection refused`) go through the full
   scan. On a subnet where few addresses are live this cuts the work by an order
   of magnitude.
2. **Adaptive worker pool**: up to 2048 concurrent probes (bounded by a third of
   the process file-descriptor limit, which the binary raises to the hard limit
   at startup).

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
