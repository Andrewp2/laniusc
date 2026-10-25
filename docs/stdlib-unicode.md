# Unicode 17.0.0 properties and scalar mappings

`core::unicode` implements the selected Unicode Character Database properties
for the fixed version **17.0.0**. It covers the entire code point range,
including supplementary planes, unassigned code points, private use,
noncharacters and surrogates. This is a versioned data contract; it does not
claim to follow the most recently published Unicode version.

The production lookup and mapping code is Lanius. It requires no allocator,
locale service, host Unicode library, runtime data files, or Python. The native
execution evidence currently covers x86_64 Linux; GPU kernel execution is not
established by these tests.

## Character properties

`properties(value: u32) -> Properties` performs one binary search and returns:

| Field | Meaning |
| --- | --- |
| `category` | One of the thirty `GC_*` general categories, or `GC_INVALID`. |
| `combining_class` | Numeric Canonical_Combining_Class. |
| `flags` | Bitset of the binary properties below. |
| `decimal_digit` | Decimal_Digit_Value 0–9, or 10 when absent. |

The general category constants use the UCD two-letter abbreviations:
`GC_CN`, `GC_LU`, `GC_LL`, `GC_LT`, `GC_LM`, `GC_LO`, `GC_MN`, `GC_MC`,
`GC_ME`, `GC_ND`, `GC_NL`, `GC_NO`, `GC_PC`, `GC_PD`, `GC_PS`, `GC_PE`,
`GC_PI`, `GC_PF`, `GC_PO`, `GC_SM`, `GC_SC`, `GC_SK`, `GC_SO`, `GC_ZS`,
`GC_ZL`, `GC_ZP`, `GC_CC`, `GC_CF`, `GC_CS`, and `GC_CO`. Their values are
0 through 29 in that order. `GC_INVALID` is 30 and is outside the UCD categories.

`general_category`, `canonical_combining_class`, and `decimal_digit_value_or`
query individual fields. The last returns its caller-supplied fallback if the
code point has no decimal digit value, including numeric characters whose
Numeric_Type is not Decimal.

| Flag | Query | Authoritative property |
| --- | --- | --- |
| `ALPHABETIC` | `is_alphabetic` | Alphabetic |
| `LOWERCASE` | `is_lowercase` | Lowercase |
| `UPPERCASE` | `is_uppercase` | Uppercase |
| `CASED` | `is_cased` | Cased |
| `CASE_IGNORABLE` | `is_case_ignorable` | Case_Ignorable |
| `WHITE_SPACE` | `is_white_space` | White_Space |
| `XID_START` | `is_xid_start` | XID_Start |
| `XID_CONTINUE` | `is_xid_continue` | XID_Continue |
| `DEFAULT_IGNORABLE` | `is_default_ignorable` | Default_Ignorable_Code_Point |

`has_property(value, mask)` tests whether **any** recognized bit in the mask is
present; an empty mask and unknown bits do not match. Lowercase, Uppercase and
Alphabetic use the derived properties, which include characters outside the
corresponding letter categories. XID properties describe Unicode identifier
syntax; callers still choose their language's treatment of underscore,
keywords, normalization and security policy.

`is_code_point(value)` accepts 0 through U+10FFFF, including the surrogate
range. `is_scalar(value)` additionally excludes U+D800 through U+DFFF.
Property queries give surrogate code points their UCD category Cs. An integer
above U+10FFFF returns category `GC_INVALID`, combining class 0, flags 0 and
absent decimal digit value. It is distinguishable from an unassigned valid
code point, whose category is Cn. Noncharacters remain valid scalar values.

## Simple scalar mappings and full scalar folding

Ordinary mapping APIs return `core::result::Result<T, core::unicode::Error>`.
`Error::InvalidScalar` rejects surrogates and integers above U+10FFFF. Valid
unassigned scalars map to themselves.

| Function | Successful value |
| --- | --- |
| `simple_mappings(value)` | `SimpleMappings { lowercase, uppercase, titlecase, case_fold }`, queried together. |
| `simple_lowercase(value)` | One scalar from Simple_Lowercase_Mapping. |
| `simple_uppercase(value)` | One scalar from Simple_Uppercase_Mapping. |
| `simple_titlecase(value)` | One scalar from Simple_Titlecase_Mapping. |
| `simple_case_fold(value, turkic)` | One scalar from CaseFolding C+S, optionally overridden by T. |
| `case_folding(value, turkic)` | `CaseFolding { length, first, second, third }` from C+F, optionally overridden by T. |
| `case_fold_len(value, turkic)` | Full folding length, 1 through 3. |

`SimpleMappings.case_fold` always uses the default C+S mapping. A missing
Simple_Titlecase_Mapping defaults to Simple_Uppercase_Mapping, as specified in
UAX #44. Scalar simple uppercasing leaves U+00DF unchanged, while its full
case folding produces two `s` scalars.

For `CaseFolding`, only the first `length` scalar fields are meaningful;
unused fields are zero. `turkic=false` selects Default Case Folding. Setting
`turkic=true` applies the CaseFolding.txt T overrides for Turkish/Azerbaijani
I. Full default folding of U+0130 is U+0069 U+0307; its Turkic folding is
U+0069. Folding need not produce lowercase (Cherokee is one example) and
does not preserve normalization forms.

`case_fold_at_or(value, index, turkic, fallback)` is the explicit fallback
query: an invalid scalar or index returns the supplied fallback.

`case_fold_into(value, turkic, output: core::slice::View<u32>)` writes the full
folding of one input scalar. It returns the number written or one of:

- `InvalidScalar` for an invalid input scalar.
- `Bounds` for negative logical start/length or overflow of start plus length.
- `Capacity(required)` when the output view is too short.

All recoverable errors occur before any output mutation. Bounds validation
precedes scalar validation, which precedes capacity validation. The caller
must back the declared view with real storage; an overstated physical backing
can trap. The output respects native and raw view strides and only changes
the selected output elements. No heap allocation occurs.

These scalar mappings do not implement full string uppercasing, lowercasing
or titlecasing, context rules such as Final_Sigma, locale-sensitive full case
conversion, normalization, or Unicode caseless string matching. In particular,
concatenating simple lowercase results does not implement Default Case
Conversion. Full string casing requires SpecialCasing data and contextual
algorithms described in the core specification.

## Sources and generation

The sources are the fixed
[Unicode 17.0.0 UCD](https://www.unicode.org/Public/17.0.0/ucd/),
[UAX #44 revision 36](https://www.unicode.org/reports/tr44/tr44-36.html), and
[Unicode 17.0.0 section 3.13](https://www.unicode.org/versions/Unicode17.0.0/core-spec/chapter-3/#G33992).
The selected files are UnicodeData.txt (category, CCC, decimal value and simple
mappings), DerivedCoreProperties.txt (derived binary properties), PropList.txt
(White_Space), and CaseFolding.txt (simple/default/Turkic folding).
SpecialCasing.txt is preserved alongside these sources for the separately
scoped full string casing rules; it is not used to replace simple scalar
mappings.

The originals are stored with deterministic gzip compression under
`data/unicode/17.0.0/`. That directory's manifest records the upstream URLs,
SHA-256 hashes and lengths. Its `LICENSE.txt` contains the Unicode License v3;
generated tables preserve the version, attribution, source URL and license
reference.

Run `python3 tools/unicode17/generate_properties.py` from the repository to
regenerate the four `unicode_*_data.lani` files, or add `--check` to verify
reproduction. The generator translates UCD records and never imports a host
Unicode database. It expands UnicodeData First/Last ranges, fills UCD
defaults, then compresses equal property runs into start/payload records.
Simple mappings and full folding use separate sorted point records.

Each table is immutable printable ASCII hex in static string storage, split
into literals of at most 4,000 bytes. A balanced chunk dispatch obtains a
borrowed byte view. Binary searches decode fixed-width keys and payloads.
There are no per-lookup array initializations, unbounded startup data scans,
or allocations. A property lookup is O(log R) for R property runs; scalar
mapping lookup is O(log M) for M mapped scalars. Table data and generated
source size stay bounded by the selected UCD version.

## Verification

`tests/stdlib_unicode_execution.rs` compiles the Lanius functions to native
code and compares 17 exact binary fields for every one of the 1,114,112 code
points against an independent Rust parser of the original UCD files. This
covers all valid scalars, all surrogate code points, default/unassigned
ranges, supplementary planes, every selected property, all simple mappings,
and every default/Turkic full folding expansion. The reference uses direct
per-code-point arrays rather than the generator's compression, encoded
strings or binary searches.

A separate native fixture checks explicit out-of-range errors, fallback
queries, output capacity and failure atomicity, selected subviews, both
native and raw output strides, and supplementary characters. It executes
under `strace` with allocation failure injection and requires no allocation,
file, socket or connection syscalls. A generation test reproduces all four
tables from the checked-in data.
