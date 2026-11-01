# Stub resolver

`ext::stub_resolver` resolves a host name to IPv4 and IPv6 addresses the way a
libc stub resolver does, in Lanius and without libc:

1. A numeric address answers directly.
2. [`std::resolver_config`](stdlib-resolver-config.md) hosts content is
   searched next, unless `options.hosts` is false.
3. A and AAAA queries go to the configured nameservers through
   [`ext::dns_client`](extended-dns-client.md). Each response must match the
   transaction ID, the question and the server address. A truncated UDP
   reply is retried over TCP on the same server.

Execution is verified on **Linux x86_64 CPU output from the GPU compiler**.

```lanius
let answer = ext::stub_resolver::lookup(name, config.borrow(), hosts.as_view(),
    ext::stub_resolver::default_options(), deadline);
```

## Names and candidates

A name with a trailing dot is absolute and is the only candidate. Otherwise,
a name with at least `ndots` dots is tried as given before the search list;
one with fewer is tried after it. That is glibc's order. Names must be 1 to
253 bytes of printable ASCII, with labels of 1 to 63 bytes; anything else is
`InvalidName`. A candidate that would exceed the 255-byte wire limit is
skipped. `candidate_count()` and `candidate(i)` list the names in the order
they were built.

## Queries and servers

For `Family::Any` the resolver asks A, then AAAA (only A with `no-aaaa`), and
NXDOMAIN on A skips AAAA. `Ipv4` asks only A and `Ipv6` only AAAA. Each query
goes through `attempts` rounds over the nameservers in order. With `rotate`,
each query starts one server later. Every query to one server is one
`Exchange`, ending in one of these outcomes:

| `Outcome` | Next step |
| --- | --- |
| `Records(n)` | Done for this type: n addresses of the type, owned by the end of the CNAME chain |
| `NoData` | Done for this type: the name exists without such records |
| `NoSuchName` | NXDOMAIN: move to the next candidate |
| `Rcode(n)` | SERVFAIL (2), REFUSED (5) and others: try the next server |
| `Transport(cause)` | No usable response, for example `Timeout`, `Io(Host(111))` from an ICMP refusal, `Dns(...)` malformed, `Correlation`, `UnexpectedEof` or `FrameLength` over TCP: try the next server |

Each exchange waits up to `timeout_ms` (from the config or `options`) for a
UDP reply, and the whole exchange is bounded by twice that and by the caller's
deadline. Datagrams with a wrong ID or question are discarded and counted in
`discarded`. Those from another source are filtered by the connected socket.
`use-vc` sends every query over TCP and `edns0` adds an OPT record offering
1232 bytes. `max_exchanges` (default 64) caps the total.

Answers follow CNAMEs from the question name within the answer section, up
to `MAX_CNAME` (16) links. Only class-IN records owned by the chain's end
count, so unrelated records in a response are ignored.

## Answer

| Field | Meaning |
| --- | --- |
| `status` | `Found`, `NoSuchName` (every candidate NXDOMAIN), `NoData` (some candidate exists without the family) or `Failed` (no server answered for some candidate and none found) |
| `source` | `Numeric`, `Hosts` or `Dns` |
| `addresses` | A addresses then AAAA, in response order; hosts addresses in file order without duplicates |
| `name` | The candidate that answered, without a trailing dot |
| `canonical` | The end of its CNAME chain, or the hosts line's first name |
| `ttl` | The smallest TTL among the CNAME and address records used; 0 for hosts and numeric answers |
| `exchanges` | Every exchange in order |

`destroy()` releases the answer. `Error` is reserved for `InvalidName`,
`InvalidOptions` (timeouts above 60000 ms, attempts above 8, no servers),
`AllocationFailed` and `Clock`; every DNS outcome is part of the `Answer`.
Results are not cached, and resolv.conf and hosts are re-read only when the
caller does so.

## Application: stub-dig

[`sample_programs/library/stub_dig.lani`](../sample_programs/library/stub_dig.lani)
prints every exchange and the result:

```sh
laniusc --stdlib-root stdlib --source-root extended sample_programs/library/stub_dig.lani -o stub-dig
./stub-dig www.example.com
./stub-dig --resolv-conf ./resolv.conf --port 5353 --no-hosts --family ipv6 host.lan
```

```
;; exchange	www.example.test	A	127.0.0.1:5353	udp	answer 1	discarded=0
;; exchange	www.example.test	AAAA	127.0.0.1:5353	udp	answer 1	discarded=0
;; status	found	source=dns
;; name	www.example.test
;; canonical	www.example.test
www.example.test.	200	IN	A	192.0.2.1
www.example.test.	200	IN	AAAA	2001:db8::1
```

Options, each at most once:

| Option | Meaning |
| --- | --- |
| `--resolv-conf PATH` | Default `/etc/resolv.conf` |
| `--hosts PATH` / `--no-hosts` | Default `/etc/hosts` |
| `--port N` | Use port N on every nameserver (resolv.conf has no ports) |
| `--family any\|ipv4\|ipv6` | Default `any` |
| `--timeout-ms N` | 1 to 60000; overrides the config |
| `--attempts N` | 1 to 8; overrides the config |
| `--deadline-ms N` | Total deadline, 1 to 600000; default 30000 |

Exchange outcomes print as:

- `answer N`, `nodata`, `nxdomain`, `rcode N`
- `timeout`, `mismatch`, `truncated`, `malformed`, `eof`, `frame-length`, `io ERRNO`

A missing default file counts as empty; an explicitly named file must be
readable. The exit status is 0 when found, 1 for NXDOMAIN or no data, 2 for
invalid arguments or an invalid name, 3 when no server answered, 4 for an
unreadable file and 5 for other failures.

## Evidence

`tests/stdlib_dns_stub_execution.rs` runs the
[resolver-config contracts](stdlib-resolver-config.md#evidence) and two
groups of `tests/fixtures/stdlib_dns_stub/oracle.py`. That script writes the
expected output of every lookup independently. Both groups pass on repeated
direct runs:

- **cli** (30 cases):
  - exact help and thirteen malformed argument lists
  - six invalid names
  - unreadable explicit files
  - numeric IPv4, IPv6 and absolute answers, and a family mismatch
  - hosts lookups with comments, aliases, case, trailing dots, family filters
    and duplicate removal
- **dns** (42 cases): Python fake servers answer UDP and TCP on 127.0.0.1,
  127.0.0.2 and ::1 on one free port, and log every query. The group checks:
  - direct, CNAME and two-link CNAME answers, with TTL minimums
  - NODATA for one family, and unrelated answer records ignored
  - search-list order with ndots 1 and 3, absolute names, and NXDOMAIN across
    every candidate, with the server-side query order
  - a truncated UDP reply completed over TCP with 40 records
  - failover from the first server to the second for each type after
    SERVFAIL, REFUSED, silence, a malformed record, a TCP frame cut short,
    a TCP reply with a wrong ID and a TCP length below the header size
  - a wrong-ID datagram and a wrong-question datagram discarded before the
    real answer
  - every attempt timing out with status `failed`, and a total deadline
  - ECONNREFUSED from a server without a listener reported as `io 111`
    before the next server
  - `use-vc`, `edns0` (OPT seen by the server), `rotate` and `no-aaaa`
  - a resolv.conf with malformed lines, four servers and `domain` replacing
    `search`
  - an IPv6 nameserver
  - a hosts entry answering without any DNS query
