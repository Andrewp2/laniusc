# Independent ordered form byte model

This fixture checks `ext::form` and `ext::form_owned` in one bounded native
process. The Python oracle is test-only. Production format and storage work
remain in Lanius.

## Reference and policy

The [WHATWG form rules](https://url.spec.whatwg.org/#application/x-www-form-urlencoded)
define the byte-level split and escaping policy. The oracle uses Python byte
`split`/`partition`, then
[`unquote_to_bytes`](https://docs.python.org/3/library/urllib.parse.html#urllib.parse.unquote_to_bytes)
after replacing original plus bytes. It never uses a dictionary for ordinary
form parsing, converts arbitrary data to a Python string, or copies the native
parser/cursor state machine.

Encoding uses `quote_from_bytes` with `*-._` safe, then explicitly escapes
Python's always-safe tilde and changes encoded spaces to pluses. A separate
declarative 256-byte table checks this adaptation. Complete expected wire
strings determine read results by offsets. The model preserves ordered
duplicates and arbitrary decoded bytes. Checked UTF-8 projections use strict
Python decoding and its first malformed-sequence offset; invalid bytes are
not replaced and BOM bytes are retained. These are the library's explicit
byte and checked-text profiles, rather than WHATWG's replacement-string layer.

## Finite corpus

Seed: `0xf04a0261112`. The **607 cases** contain:

- All 156 strings of length 0–3 over `&=+%a`, explicit empty/duplicate/raw
  delimiter/first-equals/semicolon/question-mark cases, and 40 seeded longer
  mixtures. Both borrowed and owned parsing use the same four-field Limits.
- Exact-fit and selected one-short input/pair/component/decoded limits,
  negative limits and selected simultaneous failures. There are **487 parse
  admissions** and **70 parse rejections**.
- Aggregated all-byte, mixed-case escaped-byte and all 256 possibilities in
  each percent-escape position, malformed tails, NUL, UTF-8 boundaries,
  malformed UTF-8 and BOMs. The direct component API performs **120 calls**,
  including short-capacity atomic failures and exact-size output.
- Selected short wires at every initial read cut, plus irregular, zero and
  invalid requests, copied and restored cursors, complete drains and repeated
  EOF. There are **832 stream exercises**, **21,889 valid reads**, **3,328
  copy/reset operations** and **4,160 invalid reads**.
- Owned sequences with **142 successful appends**, **148 rejected appends**,
  **32 clears** and **20 destroys followed by continued use**. Rejections
  cover invalid input metadata and pair/component/total limits. Snapshots
  observe **1,827 pairs**, including exact iterator remaining counts, missing
  index results and fused exhaustion. Negative constructor limits are separate.

The actual source/destination byte layouts are native arrays with stride
`-8` and packed raw storage with stride `+1`. Nonzero source and destination
offsets are exercised. Views and Packed sources produce the same complete
wire; selected Packed spans share and reorder ranges. Full selected source
metadata and bytes are captured before and after serialization. Every read
captures all 64 destination cells, cursor remainders and status. Whole source
backings and component guards are checked; owned ASCII output is compared
before being destroyed.

The append reference is only an ordered list of byte pairs. Every attempt is
followed by complete content and serialization observations, so logical
failure atomicity, retained order and reuse are visible. It does not model
allocation growth. Reached allocation failures, owner/source independence,
physical lifetime/nonaliasing obligations and allocation ledgers are separate
resource-test/caller concerns. No automatic ownership or formal proof follows.

## Protocol and verification

Input and output are strict little-endian raw binary, with no JSON transport.
Cases contain at most 2,048 input bytes, 32 live pairs and 32 append operations;
native input backing has 2,080 logical bytes. Output staging is 4,096 bytes.
Encoding drains have explicit finite bounds. The one child process has a
75-second deadline inside the Rust reference harness's 90-second deadline;
root bounds each outer gate to 100 seconds.

Host-only controls passed: **20 deliberate corruptions rejected**, including
eight coherent semantic mutations (tilde/asterisk policy, lowercase escapes,
plus ordering, double decoding, percent loss, duplicate collapse and pair
reordering), plus damaged statuses/data/metadata and truncated/trailing output.
The accepted synthetic output is **5,203,022 bytes**. These are verifier
controls, not native runtime evidence.

The first native gate stopped during Lanius compilation: **0 passed / 1 failed
in 4.62 seconds**, with a separate **1.83-second Rust build**. The original
producer (`97d842c6`) reported `LNC0047` at a nested error-payload match in
test reporting. No native model execution or production failure was observed.
The revised producer factors that match into an explicitly typed helper;
the corpus, oracle, expected bytes and Rust driver are unchanged. See the
[reproduction and passing control](compiler_dependency/README.md). The reduced
original also failed with `LNC0047`; the typed-helper control compiled and
executed all six assertions with exit 0 and empty stdout/stderr.

The revised native model passed **1/1 in 9.02 seconds**, with a separate
**0.22-second Rust build**, exit 0, and this exact summary in
`target/stdlib-work/form-model-revised.log`:

```text
form-model cases=607 parse_admissions=487 parse_rejections=70 append_successes=142 append_errors=148 clears=32 destroys=20 component_calls=120 streams=832 reads=21889 copies=3328 invalid_reads=4160 pairs_observed=1827 layouts=2 seed=0xf04a0261112
```

Tested SHA-256 sources:

- Producer: `beb7b40094ccd1fcb8b1579e6597a00aa6c3e4dc8acb47d7a52c93d8de2cd117`
- Oracle: `3489d08a439e82dd3670c38542de315e494d032b6af82b64c73e6ed6f8c456c8`
- Driver: `d38decd1b183fa929abaad5b1acf308afd5f70aa3bd4ed937765500f4fe82fc3`

Focused selector:

```text
cargo test --test extended_form_model_execution form_bytes_match_ordered_pair_wire_stream_and_owned_operation_reference -- --exact --nocapture
```

The recorded runtime target is Linux x86_64 CPU execution of an ELF emitted
by the GPU compiler. Device execution and other platforms remain unverified
by this gate.
