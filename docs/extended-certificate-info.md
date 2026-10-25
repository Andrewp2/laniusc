# certificate-info

[`sample_programs/library/certificate_info.lani`](../sample_programs/library/certificate_info.lani)
reads one DER certificate from stdin and writes a bounded structural report.
The application uses the real [`ext::x509`](../extended/ext/x509.lani) parser
and [`core::sha256`](../stdlib/core/sha256.lani); Python and OpenSSL appear only
in the test driver.

Runtime admission **passed on 2026-10-24** for x86_64 Linux ELF output from the
GPU compiler, executed natively on the CPU. Three separately selected groups
passed **50 native cases using three compiled strict ELFs**. These results
cover the tested target and bounded inspection behavior, not other targets
or certificate authentication.

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
certificate_sha256=<64 lowercase hexadecimal digits>
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

The SHA-256 covers the exact DER bytes read, including the signature. The
serial field removes a DER integer's optional leading positive sign byte; it
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

| Test | Accepted evidence |
| --- | --- |
| `certificate_info_real_metadata_schema_and_usage` | Real OpenSSL Ed25519, RSA-2048, and P-256 certificates against an independent DER/metadata oracle; valid schema variants, malformed inputs, inspection-only behavior, and argument rejection before input |
| `certificate_info_owner_cleanup_partial_io_and_faults` | Every reached input allocation denial, matching owner release, successful short reads, acknowledged short-write progress, Interrupted retries, host errors, zero/invalid counts, EPIPE, signal setup failure, and a later write failure after a report prefix |
| `certificate_info_caps_eof_work_and_shared_call_budget` | Exact input and output caps, the actual excess/EOF probe, long valid fields, shared parser work exhaustion, and repeated interruptions reaching the shared call cap |

The test-only Python corpus builds independent DER structures and exact report
bytes. It generates real certificates with OpenSSL, decodes their field
structure independently, hashes their exact bytes with `hashlib`, and
cross-checks serials, UTC dates, and fingerprints using OpenSSL's metadata
command. Synthetic certificates exercise schema and limits without claiming
valid signatures. Expected report bytes are not obtained from the Lanius
parser or renderer.

The native trace checks `rt_sigaction`, `read`, `write`, `mmap`, `munmap`,
`mremap`, `brk`, `openat`, and `close`. It matches allocation addresses and
sizes to releases, requires all input owners to retire before the first
write, checks actual injected-fault reachability, preserves the input file,
and checks EOF before publication. All three groups passed these checks.
An injected successful short write tests the app's response to the reported
count: strace skips that actual kernel write, so the test expects only the
remaining suffix on captured stdout. It does not claim the skipped prefix
was delivered.

The initial cleanup group failed in 6.91 seconds because the common capture
helper replaced the test's closed pipe with its own stdout pipe. That run
observed a successful report, not EPIPE. The driver now uses bounded
`Command::output()` for that case so its explicitly supplied closed-reader
pipe survives. The application, corpus, and real-prefix/error control are
unchanged. The failed local log is
`target/stdlib-work/tls-auth-admission/certificate-info-cleanup.log`; target
logs are ignored local artifacts and are not checked in.

## Accepted runs and reproduction

All logs below are under `target/stdlib-work/tls-auth-admission/`. They are
local ignored artifacts, not checked-in evidence files.

| Exact test | Native cases | Time | Log |
| --- | ---: | ---: | --- |
| `certificate_info_real_metadata_schema_and_usage` | 25 | 7.33 s | `certificate-info-ordinary.log` |
| `certificate_info_owner_cleanup_partial_io_and_faults` | 17 | 7.27 s | `certificate-info-cleanup-corrected.log` |
| `certificate_info_caps_eof_work_and_shared_call_budget` | 8 | 18.86 s | `certificate-info-limits.log` |

Each accepted invocation compiled one app ELF and reused it for that group's
native cases. The initial failed cleanup invocation took 6.91 seconds and is
excluded from the three accepted ELFs and 50 accepted native cases. Only its
driver capture setup changed; the application and corpus remained frozen.

The initial joint Rust driver build with the TLS framing target took 1.39
seconds (`build-certificate-framing.log`). Refreshing the certificate driver
after the closed-pipe fix took 1.41 seconds
(`build-certificate-closed-pipe-fix.log`). The accepted driver binary was
`target/stdlib-build/debug/deps/extended_certificate_info_execution-b81e9ee3275c72f9`.
Build times are not application execution or parser throughput measurements.

From the repository root, the following function keeps each command bounded
and serializes GPU admission. OpenSSL, Python 3, strace, timeout, and flock are
test dependencies. The driver refresh used:

```sh
timeout --kill-after=2s 100s \
  flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s \
  env CARGO_TARGET_DIR="$PWD/target/stdlib-build" \
    CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
    cargo test --test extended_certificate_info_execution --no-run
```

The accepted runtime selections used this bounded form, one invocation per
test. The binary name is specific to this checkpoint:

```sh
certificate_info_gate() {
  timeout --kill-after=2s 100s \
    flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
    timeout --kill-after=2s 60s \
    env RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
      target/stdlib-build/debug/deps/extended_certificate_info_execution-b81e9ee3275c72f9 \
      --exact "$1" --nocapture --test-threads=1
}
certificate_info_gate certificate_info_real_metadata_schema_and_usage
certificate_info_gate certificate_info_owner_cleanup_partial_io_and_faults
certificate_info_gate certificate_info_caps_eof_work_and_shared_call_budget
```

The native fault/trace runs support the explicit ownership and bounded I/O
contracts above. They do not establish trust, signature correctness,
constant-time behavior, isolated throughput, or a wall-clock bound for an
arbitrary blocked host operation. No compiler, IR, ABI, or proof change is
part of this application.
