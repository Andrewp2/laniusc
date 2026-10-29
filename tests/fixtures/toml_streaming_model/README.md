# TOML streaming byte and reader model

The Lanius producer runs the actual public TOML parser, `Document.encoded_len`,
`Document.encoding`, `Encoding.read` and owned `encode`. The reference starts
from ordered semantic trees. Recursive whole-value joins and a declarative
UTF-8 byte substitution table establish the complete canonical wire before
any read schedule runs. It does not mirror the production parent-link byte
machine or use the production encoder as its expected output.

Selected floats have explicit known canonical spellings: positive/negative
zero, 1.5, 100.0, infinities and signed NaNs. This adds no second shortest-float
formatter. Temporal tokens are decomposed by a whole-token regular expression;
the reference inserts missing seconds, normalizes T/Z and +00:00, preserves
-00:00, and strips only trailing fractional zeroes. Complete original tokens
and exact fraction strings are also checked through public value queries.
Fractions reach 257 digits, including 136 trailing zeroes. They are not reduced
to Python datetime precision.

## Finite corpus and observations

Seed `0x70a10261117` gives **280 cases** over 102 distinct ordered trees:

- Empty documents, empty strings/containers, all 32 ASCII controls, DEL,
  quote/backslash, all UTF-8 widths, unusual scalar boundaries and escaped keys.
- Integer limits and nondecimal source spellings; selected float types and
  signs; every temporal kind, omitted seconds, lowercase separators, explicit
  offsets, all-zero fractions and subnanosecond fractions.
- Ordered root members, arrays of inline tables, mixed nested values, 20
  nested containers, 24 seeded string/container trees and output lengths
  1,024/1,025/1,026 around the owned collector's chunk size.
- Every initial byte cut for three small wires containing escapes/UTF-8,
  containers and a trimmed temporal fraction, followed by mixed cursor pulls.
- Exact output caps, selected one-byte-short caps and public work boundaries.

Normal cases use public parse options with `u64::MAX` work. No Document fields
are forged or modified. Two escape-heavy literal-TAB inputs allow parsing
below the tested serializer budgets. The independent formula is

```text
W = wire bytes + nonroot nodes + original fraction digits + trimmed zeroes
```

The first witness has 103 output bytes and W=104. The second combines 64 TABs,
nested containers and a 257-digit fraction: 543 output bytes + 6 nonroot nodes
+ 257 scanned digits + 136 trimmed digits = W=942. Cases at W-1, W, 2W-1 and
2W distinguish measurement from replay admission; the first witness also has
a `u64::MAX` case. Parsing and serialization retain separate work budgets.
No parser-work algorithm is used as the serializer oracle.

Each admitted case uses two cursor copies plus an unchanged seed. Schedules
copy current state in both directions, restart either cursor, mix zero and
positive requests, and drain both using 1/7/13/31-byte requests. The second
cursor is called through a generic `Read` helper. Invalid negative and
overflowing logical ranges are observed before and after exhaustion, including
invalid zero requests. Valid zero requests at `i32::MAX` touch no backing.
Repeated positive EOF probes and copying an exhausted cursor check fusion.
The reference tracks only two offsets into the complete expected byte string.

Every request reports its result, both exact remaining counts and all 64
destination cells, including untouched prefix/tail guards. Actual native byte
arrays have stride -8; independently backed packed bytes have stride +1. Both
layouts run the main profiles; extra split/limit cases rotate layouts. Public
document snapshots before and after serialization include complete ordered
keys, values, node kinds/counts, canonical numeric text, integer/float values,
NaN/zero signs, original temporal text and exact fractions. Traversal checks
public member/element lookup against child/sibling iteration.

The producer overwrites input bytes after `parse_text` finishes, before the
first snapshot/serializer. It reads the final complete owned encoding after
destroying the actual Document. These witness independent ownership; neither
claims lifetime or alias enforcement. Physical identity, allocation failures,
caller-buffer precedence/atomicity and large backing/resource behavior belong
to the separate direct/resource gates.

## Protocol, limits and receipt

One native process consumes the whole raw binary batch. Metadata is unsigned
64-bit little-endian, actions use explicit 32-bit fields, and values/destinations
are complete bytes rather than hashes. No JSON transport or added production
dependency is used. The fixed corpus has at most 1,028 source bytes, 1,026
wire bytes and 22 nodes per case. Physical input/action/output staging bounds
are 8,192/384/4,096 bytes; read destinations contain 64 backed cells. Schedules
contain 24 supplied actions and bounded drains. The native child timeout is
75 seconds and the host driver timeout is 90 seconds.

The Rust driver uses the existing GPU compiler helper, verifies an x86_64 ELF,
and requires zero exit status, empty stderr, exact byte framing and the full
fixed summary. The first root-owned native run passed **1 test, 0 failures in
7.49 seconds**, after a separate 1.07-second Rust build. The accepted receipt is
`target/stdlib-work/toml-streaming-model.log`. No compiler, Cargo or native
command was run by the model author.

Accepted source SHA-256 values:

- Producer: `6e1da2198d5380c7acc3c6a60908ef19811e17e3e033e21bf63da8c9b00d2a91`
- Oracle: `c46e61d337966602b2ddc8054719e82606568723dff7c4c0a665a85ef6a1cb18`
- Driver: `b86e7c2afdff55f9d83dcf49208040940405dbab07345c3b31e9f90ae9ea16d0`

Selector:

```text
--test extended_toml_streaming_model_execution toml_streaming_matches_ordered_values_exact_work_and_reader_state --exact --nocapture
```

Observed complete summary:

```text
toml-streaming cases=280 layouts=2 measured=263 admitted=255 output_limit=13 work_limit=12 reads=8527 copies=2894 invalid=1275 zero_requests=975 eof=1733 wire_bytes=16410 seed=0x70a10261117
```

Separate host-only controls passed the 1,167,806-byte synthetic transcript and
rejected 19 deliberate corruptions. Ten damage framing, metadata, values or
read observations; nine coherent semantic mutations use short control escapes,
uppercase hex, truncated fractions, lost -00:00/negative-zero identities,
uncharged trimming/replay, reset-on-copy, or zero-before-bounds behavior.
Each semantic mutation must first have an actual distinguishing corpus witness.
Python 3.12 `tomllib` additionally checks the expected wire's recursive value
types and values, including signed floats. Its datetime precision and timezone
normalization are explicitly insufficient for the exact temporal comparison.

The accepted native receipt target is Linux x86_64 CPU execution of GPU-compiled
Lanius. This finite model does not establish GPU-device execution, other targets,
formal correctness, physical backing, disjointness or caller lifetime safety.
