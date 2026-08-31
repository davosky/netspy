# vendor/lanscan

Concurrent LAN port + MAC scanner (Go), adapted from the standalone
`port_scanner` toolset for NetSpy. It scans a CIDR subnet over a TCP port range,
reads the MAC address of every host it finds alive from the kernel ARP cache,
and **prints a JSON report on stdout**. It does **not** touch any database:
NetSpy (`LanscanJob`) is what persists the rows.

The same binary runs in two places:

* on the NetSpy server, for the **primary** LAN (scanned locally);
* on a dedicated Linux client inside each **secondary** LAN, reached over SSH, so
  that LAN's ARP table — and therefore its MAC addresses — is visible.

NetSpy drives it through `LanscanRunner` (`app/services/lanscan_runner.rb`),
which validates every parameter and passes it as an argv array. It can also be
run by hand (`-format text`, the default).

## Build

```bash
bin/build-lanscan          # → vendor/lanscan/bin/lanscan (committed)
```

The compiled, statically linked `linux/amd64` binary is committed so deploys
with no Go toolchain work out of the box; it is also the binary you ship to the
secondary-LAN clients (`rake lanscan:package`). Rebuild after editing `main.go`,
or for another platform:

```bash
cd vendor/lanscan && GOOS=linux GOARCH=arm64 go build -o bin/lanscan-arm64 .
```

Standard library only — no module dependencies.

## Flags

| Flag         | Default          | Meaning |
|--------------|------------------|---------|
| `-target`    | `10.182.1.0/24`  | subnet to scan, CIDR notation |
| `-ports`     | `1-1024`         | TCP port range, `START-END` |
| `-timeout`   | `550`            | per-port connect timeout (ms) |
| `-format`    | `text`           | `text` (human log + progress bar on stdout) or `json` (one JSON report on stdout, `PROGRESS <done> <total>` lines on stderr) |
| `-discovery` | `true`           | find live hosts first (also the set whose MAC is collected) |
| `-log-dir`   | `.`              | directory for the `scan_<timestamp>.log` file (`-format text` only) |
| `-no-log`    | `false`          | do not write a log file (`-format text` only) |
| `-progress-file` | *(none)*     | file to atomically write `"<done> <total>"` progress to |

## JSON report (`-format json`)

```json
{
  "target": "192.168.1.0/24",
  "ports": "1-1024",
  "started_at": "2026-08-31T10:00:00Z",
  "finished_at": "2026-08-31T10:00:12Z",
  "hosts_alive": 7,
  "hosts": [
    {"ip": "192.168.1.10", "mac": "aa:bb:cc:dd:ee:ff", "open_ports": [22, 80]},
    {"ip": "192.168.1.20", "mac": "11:22:33:44:55:66", "open_ports": []}
  ]
}
```

A host is reported if it has open ports **or** a resolvable MAC address (`mac` is
omitted when unknown). On a fatal error the process prints `{"error": "..."}` on
stdout and exits non-zero.

## Speed

1. **Discovery / liveness phase** (`-discovery`): each host is first probed on
   ~20 sampled ports; only hosts that answer (open port, or an immediate
   `connection refused`) go through the full scan. On a sparse subnet this cuts
   the work by an order of magnitude. It also defines the set of hosts whose MAC
   is looked up, so a live host with no open ports still shows up with its MAC.
2. **Adaptive worker pool**: up to 2048 concurrent probes, bounded by a third of
   the process file-descriptor limit (raised to the hard limit at startup) and
   by a `hostCeiling` on the number of enumerated addresses.

Needs no root: TCP connect scan, not raw sockets. MAC addresses come from
`/proc/net/arp` (Linux only); the field stays empty elsewhere.
