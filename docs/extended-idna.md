# IDNA (UTS #46) for URL hosts

`ext::idna` converts an internationalized domain to its ASCII form:
`Bücher.example` becomes `xn--bcher-kva.example`. This is UTS #46 ToASCII
with RFC 3492 Punycode. [`ext::url`](extended-url.md) calls it for every
special-URL host.

The options are the ones the WHATWG URL Standard uses:

- nontransitional processing, so `ß`, `ς`, ZWJ and ZWNJ stay as they are
- CheckHyphens off
- CheckBidi and CheckJoiners on
- UseSTD3ASCIIRules off
- VerifyDnsLength off

Execution is verified on **Linux x86_64 CPU output from the GPU compiler**.

```lanius
let out: alloc::vec::Vec<u8> = alloc::vec::new();
let length = ext::idna::to_ascii(domain_bytes, out.borrow()).unwrap();   // "xn--bcher-kva.example"
```

## Data

The table is not a copy of `IdnaMappingTable.txt`. It is derived from the
vendored Unicode 17.0.0 UCD in `data/unicode/17.0.0/` by
[`tools/unicode17/generate_idna.py`](../tools/unicode17/generate_idna.py).
That script applies the derivation in UTS #46 section 6.

**Base mapping.** Each scalar maps to its `NFKC_Casefold`, with three
exceptions:

- U+FF0E, U+3002 and U+FF61 map to `.`.
- `Bidi_Control` scalars map to themselves.
- U+1E9E maps to `ß`.

**Base valid set.** It starts from the scalars that do not change under
`NFKC_Casefold`, then:

- adds `ß`
- removes general categories C\* and Z\*
- removes the IDS operators
- adds ASCII other than `.`

**Status.** The exclusion set (U+FFFC, U+FFFD and the tag characters) is
disallowed. ZWNJ, ZWJ, `ß` and `ς` are deviations. Every other scalar gets a
status from its mapping:

| Mapping | Status |
| --- | --- |
| Leaves the base valid set | Disallowed |
| Empty | Ignored |
| Itself | Valid |
| Anything else | Mapped |

A mapping that leaves the valid set is disallowed even when that happens
through a later step. `.` is a label separator, not a label character, so
U+2024, U+2488 and similar scalars are disallowed.

The generated [`ext::idna_data`](../extended/ext/idna_data.lani) holds 6,946
records, 3,159 pooled scalars and a 4,352-entry block index, about 160 KB of
source. Each record covers a range of scalars and gives:

- the status
- the Bidi_Class, from `UnicodeData.txt`
- the mapping, either as a single-scalar delta or as a pool slice

The result is 152,965 valid, 6,377 mapped, 294 ignored, 4 deviation and the
remaining scalars disallowed. `generate_idna.py --check` confirms that the
checked-in table is current.

Other data comes from existing modules:

- NFC from [`ext::unicode_normalize`](extended-unicode-normalize.md)
- General_Category and Canonical_Combining_Class from `core::unicode`

The vendored UCD has no Joining_Type data (`ArabicShaping.txt`); see
[the joiner gap](#gap-zero-width-non-joiner).

## Processing

`to_ascii(domain, out)` follows the same steps as Node.js's URL parser.

**An all-ASCII domain is only lowercased.** Its `xn--` labels are not decoded
or checked. Node does the same, so `http://xn--a/` parses.

**Any other domain** goes through these steps:

1. **Limit.** The UTF-8 must be valid and at most 16,384 bytes.
2. **Map.** Each scalar is mapped. Ignored scalars are dropped, deviations are
   kept, and a disallowed scalar fails with `Disallowed(scalar)`.
3. **Normalize.** The result is put in NFC.
4. **Split and convert.** The text is split at `.`. Empty labels are kept, so
   `a..b` and a trailing dot survive. Each label is then handled by its kind:

| Label | Handling |
| --- | --- |
| Starts with `xn--` | Must be ASCII. Its Punycode must decode to a non-ASCII label that is all valid or deviation scalars and unchanged by NFC. That decoded label must pass the label checks. Failures are `InvalidPunycode` and `InvalidAce`. The label is emitted as written. |
| Other ASCII | Emitted as is. |
| Non-ASCII | Must pass the label checks, then becomes `xn--` plus its Punycode. |

The label checks are:

- **No leading mark.** A label cannot start with general category M\*
  (`LeadingMark`).
- **CONTEXTJ.** ZWJ must follow a virama (combining class 9). ZWNJ must also
  follow a virama, or else pass the joining-type rule (`Joiner`).
- **Bidi** (`Bidi`). The rule is applied per label, as Node does:
  1. A label of nothing but NSM fails.
  2. A label without R, AL or AN passes.
  3. Otherwise, a label starting with L follows the RFC 5893 left-to-right
     rules (5 and 6).
  4. Any other label follows the right-to-left rules (1 to 4).

  The letter of UTS #46 instead applies RFC 5893 to every label of a domain
  that contains right-to-left text. Under that reading, `1a.א` would fail;
  Node accepts it.

`ext::url` then rejects an empty result or a forbidden domain code point, and
sends a result that ends in a number to the IPv4 parser. For example,
`１２３` becomes `0.0.0.123`.

`punycode_encode` and `punycode_decode` are the RFC 3492 codecs on their own.
`status(scalar)` reports the table status.

## Gap: ZERO WIDTH NON-JOINER

The ZWNJ rule needs Joining_Type: an L or D scalar before it and an R or D
scalar after it, skipping transparent scalars. That property is not in the
vendored data. Some cases need no Joining_Type:

- **Passes:** a ZWNJ after a virama.
- **Fails:** a ZWNJ at the start or end of the label.
- **Fails:** a ZWNJ next to an ASCII scalar, because ASCII never joins.

Any other ZWNJ returns `UnsupportedJoiner`. `ext::url` reports it as
`UnsupportedIdna`. Adding `DerivedJoiningType.txt` to the vendored UCD would
close the gap.

## Cost

Mapping searches the records between the ones covering the start of the
scalar's 256-scalar block and the next block, from a generated block index.
NFC runs only when the quick check is not `Yes`, and takes the normalized
scalars from `measure`'s scratch. Punycode, NFC and validation are linear in
practice; the normalizer's canonical ordering is O(n log n) on long
combining runs (see the [normalization guide](extended-unicode-normalize.md#work-and-space-bounds)).
Through url-parse, each of these 16 KB hosts parses in tens of milliseconds:

| Host | Time |
| --- | --- |
| `a` + 4,000 × U+0301 + 4,000 × U+0316 (reverse canonical order) | 45 ms |
| `a` + 4,000 × U+0316 + 4,000 × U+0301 (already in order) | 41 ms |
| 8,000 × `é` | 30 ms |
| 16,000 × `a` (ASCII, lowercased only) | 14 ms |

The reverse-order host took 4.7 s when ordering was an insertion sort.

## Verification

`tests/fixtures/extended_url/oracle.py` runs two groups for this module; the
[URL guide](extended-url.md#verification) lists all of them.

**table group.** [`idna_table.js`](../tests/fixtures/extended_url/idna_table.js)
probes Node's URL host parser with four hosts for every scalar in planes 0 to
3 and 14: `x`+c, c, `א`+c and `א`+c+`א`. The other planes have no assigned
scalars and must be disallowed. Every scalar must meet these conditions:

| Scalar | Required result |
| --- | --- |
| Disallowed | All four probes fail. |
| Maps to a forbidden code point | All four probes fail. |
| ZWJ or ZWNJ | All four probes fail. |
| Ignored | `x`+c yields `x`. |
| Mapped | The first successful probe's decoded hostname is the probe context around the mapping. |
| Valid or deviation | The same, around the scalar itself. |

NFC composes U+0307, U+0308 and U+0344 after `x`, and the check accounts for
that. For valid scalars, the four pass/fail flags must also equal those
predicted from the Unicode 17 Bidi_Class and General_Category.

**idna group.** Runs hosts through url-parse and Node, as described in the
[URL guide](extended-url.md#verification).

## Node.js divergences

Node v24.21.0 uses ada 4.0.0. Its IDNA mapping matches the derived table on
every scalar, but its other Unicode data is older.

- **Stale Bidi_Class and mark data.** Scalars assigned since about
  Unicode 14 behave in Node as Bidi_Class L non-marks: probe flags `1100`.
  U+1734 and U+1171E keep their pre-14 nonspacing-mark behaviour: flags
  `1011`. The table group allows exactly those shapes for at most 1,296
  scalars. The idna group counts a mismatching case as a divergence only
  when it contains such a scalar. There were 17 such cases.
- **Hangul composition.** Node's NFC does not compose a precomposed LV
  syllable with a following trailing jamo: U+AC00 U+11A8 stays two scalars
  instead of U+AC01. A result that differs from Node's only by those
  compositions counts as a divergence. There were 11 such cases.
- **Long ASCII hosts.** Node applies its 16,384-byte limit to an ASCII host
  containing `xn-` or an uppercase letter. `ext::idna` limits only non-ASCII
  domains. There was 1 such case.

Each kind is recognized by an exact rule in the oracle. Every other
difference fails the group.
