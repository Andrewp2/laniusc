# Resolver configuration

`std::resolver_config` reads the system resolver configuration:
[resolv.conf(5)](https://man7.org/linux/man-pages/man5/resolv.conf.5.html)
nameservers, search list and options, and
[hosts(5)](https://man7.org/linux/man-pages/man5/hosts.5.html) lookups. It
parses bytes the caller supplies, so a test or sandbox can pass its own
files. The DNS lookup itself is in
[`ext::stub_resolver`](extended-stub-resolver.md), because the DNS message
codec and transport live in the extended library. Execution is verified on
**Linux x86_64 CPU output from the GPU compiler**.

## resolv.conf

`parse(content)` returns a `Config`. Parsing follows glibc: lines that cannot
be used are skipped and counted, and are never errors. The only errors are
`Bounds`, `TooLarge` (over `MAX_FILE_BYTES`, 1 MiB) and `AllocationFailed`.

| Line | Effect |
| --- | --- |
| `#...` or `;...` in the first column | Comment |
| `nameserver ADDRESS` | A numeric IPv4 or IPv6 server, port 53. A numeric `%scope` is kept; interface names are not resolved. Only the first `MAX_NAMESERVERS` (3) are kept; later ones count in `ignored_servers`. |
| `search DOMAIN...` / `domain DOMAIN` | Replace the search list; the last such line wins. One trailing dot is removed, `.` entries are dropped, and at most `MAX_SEARCH` (6) domains are kept. |
| `options ...` | `ndots:n` (capped at 15), `timeout:n` seconds (1 to 30), `attempts:n` (1 to 5), `rotate`, `edns0`, `use-vc`, `trust-ad`, `no-aaaa` |
| anything else | Counted in `ignored`, as are unusable addresses, extra search domains and unknown options |

Without a usable nameserver the config holds 127.0.0.1 and `defaulted` is
true. The defaults are `ndots` 1, `timeout_ms` 5000 and `attempts` 2, as in
glibc. `server_count()`, `server(i)`, `search_count()` and `search(i)` read
the lists; `destroy()` releases them. The `LOCALDOMAIN` and `RES_OPTIONS`
environment variables are not applied.

## hosts

`hosts_lookup(content, name, family, output)` finds every line whose name or
alias matches `name`. Matching ignores ASCII case and one trailing dot.
`Family::Ipv4` or `Ipv6` keeps one address family. `#` starts a comment
anywhere on a line, and lines with unparsable addresses never match. The
function returns the number of matches and writes the first `output.length`
of them as `HostEntry { address, canonical, line }`. `canonical` is the
line's first name (a view into the content) and `line` is 1-based.

## Reading files

`read_file(path, limit)` reads a whole file of at most `limit` bytes (1 to
`MAX_FILE_BYTES`) into an owned vector. A missing file is `Io(Host(2))` and a
longer one is `TooLarge`. glibc treats a missing resolv.conf as empty; callers
choose whether to do the same, as [stub-dig](extended-stub-resolver.md#application-stub-dig)
does for its default paths.

## Errors

| `Error` | Meaning |
| --- | --- |
| `Io(error)` | Opening, reading or closing the file failed |
| `Path` | The path is not a valid path (for example it contains NUL) |
| `TooLarge` | Content above the limit |
| `AllocationFailed` | A list or buffer could not grow |
| `Bounds` | Invalid views or limit |

## Evidence

`tests/stdlib_dns_stub_execution.rs` runs
`tests/fixtures/stdlib_dns_stub/contracts.lani`, which checks:

- UDP deadlines: a 30 ms `receive_from_until` timing out with `Host(110)`
  after at least 30 ms, a datagram between a nonblocking and a blocking socket
  with the sender's port, a timeout on the blocking socket, a zero-length
  datagram, and an expired deadline
- resolv.conf defaults
- a mixed file: three of four servers kept, a numeric IPv6 scope, the last
  search line winning, every ignored line counted, capped ndots, timeout and
  attempts, every flag, `.` entries dropped and the seventh search domain
  ignored
- hosts: comments, a match count above the output capacity, aliases with
  case and a trailing dot, family filters and unparsable lines
- `read_file`: an empty file, ENOENT, `TooLarge` and `Bounds`

Repeated direct runs exit 0. The [stub-dig](extended-stub-resolver.md#application-stub-dig)
oracle exercises both parsers end to end.
