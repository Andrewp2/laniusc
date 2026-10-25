# certificate-info

[`sample_programs/library/certificate_info.lani`](../sample_programs/library/certificate_info.lani)
reads one DER certificate from stdin and writes a bounded structural report.
The application uses the real [`ext::x509`](../extended/ext/x509.lani) parser;
Python and OpenSSL appear only in the test driver. It performs schema metadata
inspection without hashing or a certificate fingerprint field.

After fingerprint removal, all three focused groups pass on x86_64 Linux
through the GPU compiler. The report below contains no cryptographic digest
or verification decision.

## Invocation and report

```text
certificate-info < certificate.der
```

The program accepts no arguments, including options. It validates the complete
argument snapshot before signal setup, input allocation, or stdin reads. Input
must contain exactly one DER certificate followed by EOF; PEM, trailing bytes,
and concatenated certificates are not accepted. Stderr is unused.

The report contains these newline-terminated fields in this order:

```text
inspection=parse-schema-only
version=<1, 2, or 3>
serial_hex=<unsigned serial, lowercase hexadecimal>
not_before_utc=<YYYY-MM-DDTHH:MM:SSZ>
not_after_utc=<YYYY-MM-DDTHH:MM:SSZ>
signature_oid_encoded_content_hex=<lowercase hexadecimal>
spki_oid_encoded_content_hex=<lowercase hexadecimal>
issuer_rdns=<decimal count>
subject_rdns=<decimal count>
extensions=<decimal count>
unknown_critical_extensions=<decimal count>
```

The serial field removes a DER integer's optional leading positive sign byte; it
does not truncate a long otherwise-valid serial. Each OID field contains only
the OID's encoded content octets, excluding its DER tag and length. It is not
a dotted decimal OID or the complete AlgorithmIdentifier encoding. RDN counts
count relative distinguished names, including a multi-attribute RDN as one.

Status 0 means the certificate passed the parser's supported syntax and
schema checks and the complete report was written. It establishes no trust,
certificate path, hostname, usage authorization, signature validity, or
current-time validity. The application does not verify certificate signatures
or compare the validity interval to a clock. Structurally valid certificates
with modified signature bytes, past or reversed dates, or unknown critical
extensions can produce a successful inspection report. The unknown-critical
count describes the parser's recognized extension set; it is not a decision
to trust or accept those extensions in a connection.

## Limits and publication

The application reserves one owned input buffer with a **1,048,576-byte**
limit before reading. Reads request at most 1,024 bytes and never request more
than the remaining input allowance. Once the limit is full, an actual
one-byte read distinguishes EOF from excess input. A positive probe consumes
that extra byte, stores none of it, and returns 7. Short inputs also require
actual EOF before parsing begins.

One default X509 budget is shared by certificate parsing, the issuer and
subject RDN walks, and the extension walk:

| Bound | Value |
| --- | ---: |
| Input bytes | 1,048,576 |
| Successfully decoded DER items | 100,000 |
| Charged work | 16,777,216 |

The application never resets the budget between cursors. Work charges include
decode attempts, encoded lengths, and the parser's duplicate comparisons;
they are not a CPU time or wall-clock allowance. See the
[`ext::x509` guide](extended-x509.md) for its schema and budget contract.

The complete report is prepared in fixed caller storage with an
**8,192-byte** logical limit. An otherwise-valid certificate whose serial or
OID would exceed that limit returns 7 before any stdout call. Report fields
copy their bytes while the input remains alive. The application then destroys
the sole input owner before its first write; no borrowed certificate field
escapes inspection. Report preparation and publication allocate no additional
owned storage. Logical byte caps do not specify total physical stack usage,
RSS, or a View's physical element stride.

A shared **131,072-attempt** counter covers stdin reads, EOF/excess probes,
and stdout writes. Every attempt consumes one unit, including an Interrupted
retry. Argument services and signal setup are outside this counter. The
program installs SIGPIPE Ignore before allocating the input so EPIPE can
return through the normal failure path. It retries Interrupted reads and
writes, advances after valid short writes, and rejects invalid counts or a
zero-progress write. The `std::stream::Descriptor` adapter stages at most
1,024 bytes per host call, even when the application supplies the complete
remaining report. The later-write failure control observes a real 1,024-byte
prefix before its second call fails.

CLI, input, schema, work, and report-preparation failures publish nothing.
Once publication begins, a later host error or exhausted call budget can
leave a report prefix. There is no transactional output, flush, durability,
or blocked-operation deadline guarantee. Stdin and stdout are borrowed and
are never closed by the application. All owned input storage is explicitly
released on success and failure.

| Status | Meaning |
| --- | --- |
| 0 | Schema inspection completed and the full report was written |
| 2 | Unexpected argument or invalid argument snapshot bounds |
| 3 | Argument host access, signal setup, stdin, or stdout failure |
| 4 | Argument or input-buffer allocation failed |
| 5 | Malformed DER or unsupported/invalid certificate schema |
| 7 | Input, report, parser item/work, or shared I/O call limit exceeded |

## Focused verification driver

[`tests/extended_certificate_info_execution.rs`](../tests/extended_certificate_info_execution.rs)
compiles the real app with the stdlib and extended source roots. The unchanged
shared strict ELF/jump checker checks the emitted executable before native
execution. A `OnceLock` shares one compiled app across all groups selected in
one driver process; selecting groups in separate processes compiles one app
per selection.

The three groups are:

| Test | Retained coverage |
| --- | --- |
| `certificate_info_real_metadata_schema_and_usage` | Real OpenSSL Ed25519, RSA-2048, and P-256 certificates against an independent DER/metadata oracle; valid schema variants, malformed inputs, inspection-only behavior, and argument rejection before input |
| `certificate_info_owner_cleanup_partial_io_and_faults` | Every reached input allocation denial, matching owner release, successful short reads, acknowledged short-write progress, Interrupted retries, host errors, zero/invalid counts, EPIPE, signal setup failure, and a later write failure after a report prefix |
| `certificate_info_caps_eof_work_and_shared_call_budget` | Exact input and output caps, the actual excess/EOF probe, long valid fields, shared parser work exhaustion, and repeated interruptions reaching the shared call cap |

The test-only Python corpus builds independent DER structures and exact report
bytes. It generates real certificates with OpenSSL, decodes their field
structure independently and cross-checks serials and UTC dates using
OpenSSL's metadata command. Synthetic certificates exercise schema and limits without claiming
valid signatures. Expected report bytes are not obtained from the Lanius
parser or renderer.

The native trace checks `rt_sigaction`, `read`, `write`, `mmap`, `munmap`,
`mremap`, `brk`, `openat`, and `close`. It matches allocation addresses and
sizes to releases, requires all input owners to retire before the first
write, checks actual injected-fault reachability, preserves the input file,
and checks EOF before publication. These controls pass in the adapted driver.
An injected successful short write tests the app's response to the reported
count: strace skips that actual kernel write, so the test expects only the
remaining suffix on captured stdout. It does not claim the skipped prefix
was delivered.

## Current execution receipt

On 2026-10-25, all three groups passed together in **15.57 seconds**:
25 metadata/schema/usage cases, 17 ownership/I/O cases and eight limit cases,
for **50 native cases** using one shared strict ELF. The program contains
no hash implementation or fingerprint output.

The local runtime log is
`target/stdlib-work/remove-crypto-certificate-info.log`. The affected Rust
drivers built together in 86 seconds; build time is separate from native
execution. Reproduce from the repository root with a freshly built test
binary (the suffix is specific to this checkout):

```sh
timeout --kill-after=2s 100s \
  flock target/stdlib-work/library-gpu.lock \
  target/stdlib-build/debug/deps/extended_certificate_info_execution-c34056dacabe942d \
  --test-threads=1 --nocapture
```

OpenSSL, Python 3 and strace are test dependencies. Production metadata
inspection uses the Lanius DER/X.509 parsers. No compiler, IR, ABI or proof
source changed.
