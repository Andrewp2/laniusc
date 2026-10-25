# Offline DNS wire messages

`ext::dns` reads and writes bounded DNS QUERY messages in portable Lanius. It exposes borrowed questions, records, binary labels and common typed RDATA. It has no host resolver or network transport. `sample_programs/library/dns_message.lani` is a complete offline query builder and packet inspector using stdin/stdout.

The implementation follows [RFC 1035 sections 3 and 4.1](https://www.rfc-editor.org/rfc/rfc1035.html), the pointer, length and count checks discussed in [RFC 9267](https://www.rfc-editor.org/rfc/rfc9267.html), [EDNS in RFC 6891](https://www.rfc-editor.org/rfc/rfc6891.html), [binary label comparison in RFC 4343](https://www.rfc-editor.org/rfc/rfc4343.html), and [opaque unknown RDATA in RFC 3597](https://www.rfc-editor.org/rfc/rfc3597.html). Dnspython's name/wire parser was consulted as a mature reference, and isolated dnspython 2.7.0 is an independent execution oracle. Production code uses no Python or host DNS parser.

## Borrowed API

| API | Contract |
| --- | --- |
| `default_limits()` | Explicit message, record, name, pointer, option, work and output budgets |
| `parse(packet, limits)` | Validates one complete DNS message and returns `Result<Message, Error>` |
| `parse_name(wire, limits)` | Validates one standalone uncompressed, root-terminated wire name with no trailing bytes |
| `Name.labels()` | Fused iterator over borrowed raw label bytes, excluding the root terminator |
| `Name.encoded()` | Original encoded span, including any terminating compression pointer |
| `Name.wire_len()` / `is_root()` | Expanded wire length including root / semantic root test |
| `equal_dns(a, b)` | Label-aware DNS equality, folding ASCII A–Z only |
| `expand_into(name, destination)` | Writes canonical uncompressed wire bytes; bounds/capacity errors leave destination unchanged |
| `Message.questions()` | Fused question iterator in wire order |
| `Message.records(section)` | Fused record iterator; 1 answer, 2 authority, 3 additional; other selectors are empty |
| `data(record)` | Typed common RDATA, or the original opaque RDATA view |
| `Message.rcode()` | Header RCODE combined with EDNS extended RCODE |

The header exposes ID, flags, and all four section counts as nonnegative `i32` values representing wire unsigned 16-bit fields. Questions contain a `Name`, QTYPE and QCLASS. Records contain owner name, type, class, full unsigned 32-bit wire TTL, raw RDATA, section and source offset. Flags are preserved, including AD/CD; the reserved Z bit is rejected. This profile accepts standard QUERY opcode 0 requests/responses and explicitly returns `Unsupported(2)` for other opcodes. It does not implement UPDATE, NOTIFY, caching, DNSSEC validation, query/response association, or transport policy. A truncated message is not accepted merely because its TC flag is set.

Labels are length-delimited bytes, never strings. NUL, dots, backslashes, bytes 128–255 and invalid UTF-8 are valid label data. Case-insensitive comparison changes only ASCII letters and preserves label boundaries; it performs no Unicode folding, IDNA conversion, escaping or hostname policy. Root is a single zero octet in an uncompressed name, and its label iterator is empty. Expanded names include the root in their 255-octet maximum; labels contain at most 63 data octets. Unknown/reserved extended label types return `Unsupported` instead of being mistaken for compression pointers or ordinary lengths.

`Message.raw`, names, labels, raw RDATA, TXT strings and EDNS options borrow the caller's packet. Keep the packet alive and unchanged until their last use. Public records/cursors must come from validated library results; forged fields or changed structural bytes are outside their contract. View metadata is checked for negative values and arithmetic overflow, but physical backing length and lifetime remain caller responsibilities. Native byte slices with different strides and nonzero starts are supported. Offsets are logical bytes from the first ID octet of the selected message, not physical storage indexes. A standalone `parse_name` uses offsets from its selected name view. Expansion destinations must be disjoint from source bytes.

## Compression and record bounds

The parser registers label-length, root and pointer positions only after a name validates completely. A pointer must address an earlier registered position, never the header, a label's payload, the current unfinished name, a future byte, or an out-of-packet offset. Pointer-to-pointer and pointer-to-root forms are supported within configured hop/work budgets. The parser checks the exact two-bit pointer tag and rejects reserved label tags. This prevents self/prefix loops and prevents payload bytes that resemble labels from becoming pointer targets.

Direct encoded bytes are bounded by their enclosing field. In RDATA, a pointer's two source octets must fit RDLENGTH, while its target can refer to a validated prior name elsewhere in the packet. A decoded suffix never expands the encoded RDATA consumption count. CNAME/NS/PTR require exactly one encoded name; MX requires its preference plus one name; SOA requires two names plus exactly five unsigned 32-bit values. RDATA cannot borrow missing bytes from a following record. All sections and RDLENGTH fields must fit, and trailing bytes after the declared message are rejected.

The registry recognizes question and owner names, the common name-bearing RDATA listed below, and obsolete RFC 1035 MD/MF/MB/MG/MR/MINFO name positions. It does not guess at names inside opaque unknown RDATA. Consequently a later pointer into a name hidden inside an otherwise unknown record type is rejected with `Pointer`, even if a type-aware implementation could recognize that target. Unknown RDATA itself is preserved and is not searched for pointer-looking bytes.

## Typed RDATA and EDNS

`Data` variants are `A`, `Aaaa`, `Domain`, `Mail`, `Authority`, `Text`, `Opt`, and `Unknown`. A/AAAA validate 4/16 bytes for Internet class 1 and return borrowed address bytes. Other classes for these two types remain opaque. NS/CNAME/PTR return a `Name`. MX returns preference and exchange; SOA returns primary, mailbox, serial, refresh, retry, expire and minimum, retaining all 32-bit numeric values. TXT exposes a fused `Strings` iterator over one or more character strings, including empty strings and arbitrary binary contents. An empty TXT RDATA or a string crossing RDLENGTH is an error.

OPT is recognized only in the additional section, once per packet, and its owner must be the semantic root. A valid compressed root is accepted. `Edns` exposes raw UDP size, extended RCODE, version, flags and separate raw options. `effective_udp_size()` applies the RFC 6891 minimum of 512; `dnssec_ok()` tests DO; `option_iter()` yields code/data pairs in order, preserving unknown and repeated options. Every TLV must fit the OPT RDLENGTH. Unknown EDNS versions and flag bits are retained for inspection; this library does not negotiate or execute them. Query construction emits version 0. A raw TTL is metadata here: resolver TTL/caching rules are outside this wire layer.

## Checked writing

```text
OutQuestion { name: View<u8>, qtype: i32, qclass: i32 }
OutRecord { name: View<u8>, rrtype: i32, rrclass: i32, ttl: u32, data: View<u8> }
encode(id, flags, questions, answers, authorities, additionals, limits)
    -> Result<alloc::vec::Vec<u8>, Error>
query(id, qtype, qclass, canonical_name, udp_size, dnssec, limits)
    -> Result<alloc::vec::Vec<u8>, Error>
```

Both writers stage and validate the complete result before returning any output. The full encoder writes every section without compression. Owner/question names and names inside known RDATA must be canonical uncompressed wire names; supplied compression pointers are rejected. Unknown RDATA is copied opaquely. Type/class/ID/flag/count fields must fit unsigned 16-bit wire values. Unknown RR types and options retain their bytes. The returned vector has one active owner and must be destroyed once; errors destroy all staging owners.

`query` emits one question with RD set. `udp_size=0` omits OPT; a nonzero value emits one OPT record, optionally with DO. Asking for DO with no OPT is a bounds error. The query ID is explicit and deterministic. This API does not select a server, send packets, retry, or match responses.

## Limits and errors

Defaults are 65,535 packet bytes, 4,096 questions plus records, 255 expanded name bytes, 128 pointer hops per name, 1,024 EDNS options across the packet, 1,048,576 work units, and 65,535 emitted wire bytes. Message/output caps may be 0–65,535; the name cap is 1–255; other budgets are nonnegative `i32` values. Work charges header/question/record fields, raw RDATA and visited name bytes/pointers; repeated suffix traversal is charged again. Scratch initialization and subsequent accessor calls are separate from this parse budget, but remain bounded by packet/name/record/output limits.

Parsing owns one zeroed bitmap byte per input byte and frees it before returning. Names use bounded stack metadata; accessors allocate no memory. Writing grows one output vector and uses the same bounded parser scratch for final validation. Vector growth can temporarily hold both old and new storage, so logical caps are not aggregate peak-memory promises. No owner survives an error.

Errors distinguish `Bounds`, `Truncated(offset)`, `Malformed(offset)`, `Unsupported(offset)`, `Pointer(offset)`, `NameLimit(offset)`, `Limit(offset)`, `WorkLimit(offset)`, `OutputLimit(offset)`, `Capacity`, and `AllocationFailed`. Truncated means bytes are missing within a packet or declared field; a short declared RDATA is not permission to consume the next record. Offsets identify the offending byte or bounded construct. No partially validated message is returned. Because DNS messages are supplied as complete datagrams here, TCP's two-byte length prefix must be removed/added by the caller; it is not part of these bytes.

## Offline program

```sh
laniusc --stdlib-root stdlib --source-root extended \
  sample_programs/library/dns_message.lani -o dns-message
./dns-message query --id 1234 --type 28 --udp-size 1232 --dnssec Example.COM > query.dns
./dns-message inspect < query.dns
printf '\003a\000b\000' | ./dns-message query --wire-name --type 16 > binary-query.dns
```

`query NAME` splits the raw argument bytes at dots, accepts an optional final dot, and treats `.` or an empty argument as root. It does not interpret backslash escapes or perform IDNA/UTF-8 conversion. To use dots, NUL or any other byte inside a label, `query --wire-name` reads a canonical binary name from stdin. `--type`, `--class`, `--id`, and `--udp-size` are decimal 0–65,535; type/class default to 1, ID to 0 and OPT to absent. `--dnssec` requires nonzero `--udp-size`. Query-only options are rejected for `inspect`.

Inspection emits one header line, question lines, and all record lines in section order. Expanded names and raw RDATA are lowercase hex, so binary labels and string boundaries are lossless. Typed details add addresses, expanded domain data, MX/SOA fields, separate TXT values and EDNS TLVs. The raw RDATA column retains compression bytes; expanded typed name columns show their decoded meaning.

All stdout is staged. Malformed/unsupported data and resource failures produce no stdout; an operating-system output failure can expose a prefix already accepted by the host. Exit statuses are 0 success/help, 2 arguments or invalid DNS, 3 limits, 4 allocation, and 5 I/O. DNS errors include a deterministic reason and byte offset on stderr; argument/read/output-stage failures use the status. Interrupted reads/writes are retried. All argument/input/output owners are released on every path; stdin/stdout are borrowed.

Limits flags are `--max-input` (0–65,535), `--max-output` (0–1,048,576; default 262,144 report bytes), `--max-work` (0–16,777,216), and `--max-records` (0–262,140). Query wire output remains bounded by the protocol's 65,535-byte cap; its message/input cap also bounds the resulting query. The command captures at most 32 arguments and 8,192 argument bytes.

## Execution evidence

`tests/extended_dns_execution.rs` and its native fixtures cover binary labels, exact names/root, case equality, native strides and nonzero message views, pointer chains, RDATA bounds, all sections, canonical full-message writing, unsigned fields, TXT, EDNS and opaque unknowns. `dns_oracle.py` independently compares names, headers, sections and all common typed RDATA with dnspython, builds/inspects queries, exercises malformed/truncated records and resource caps, and checks a 1,600-record compressed packet. Allocation denial visits every reached encoder/query/inspection allocation; syscall tests exercise interrupted/failed reads and writes, partial write progress, cleanup, and absence of network syscalls.

The pinned oracle is deliberately isolated in ignored build storage:

```sh
python3 -m venv target/stdlib-work/dns-oracle-venv
target/stdlib-work/dns-oracle-venv/bin/python -m pip install dnspython==2.7.0
```

It is a test dependency only. Production builds need the Lanius standard and extended source roots.
