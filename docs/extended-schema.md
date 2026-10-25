# JSON Schema validation

`ext::schema` executes a documented subset of JSON Schema 2020-12 over owned
`ext::json::Document` trees. This is a supported profile, not a claim of full
2020-12 implementation. It performs no filesystem, network, clock or regex
operations. The implementation is Lanius; Python is only an independent test
reference.

## Supported profile

| Family | Keywords and behavior |
| --- | --- |
| Schema values | Object and boolean schemas; `true` accepts and `false` rejects. |
| Types | `type`, including arrays of distinct type names and mathematical `integer`. Booleans are distinct from numbers. |
| Equality | `const`, `enum`: exact numeric values, ordered arrays, unordered objects, exact Unicode strings. Empty and duplicate enum entries are accepted: the specification makes nonempty, distinct entries recommendations; an empty enum matches nothing. |
| Numbers | `minimum`, `maximum`, `exclusiveMinimum`, `exclusiveMaximum`, strictly positive `multipleOf`. No float rounding, finite machine integer restriction or exponent-sized expansion. |
| Strings | `minLength`, `maxLength` count Unicode scalar values, including NUL. They do not count UTF-8 bytes or grapheme clusters. |
| Arrays | `prefixItems`, `items`, `contains`, `minContains`, `maxContains`, `uniqueItems`, `minItems`, `maxItems`. `items` starts after adjacent `prefixItems`. Default `minContains` is one; explicit zero works. Contains bounds without `contains` have no effect. |
| Objects | `properties`, `additionalProperties`, `required`, `dependentRequired`, `dependentSchemas`, `propertyNames`, `minProperties`, `maxProperties`. Additional properties are determined only by `properties` in the same schema object. |
| Composition | Nonempty `allOf`, `anyOf`, `oneOf`; `not`; `if`, `then`, `else`. `then` and `else` have no effect without an adjacent `if`, but their schemas are still checked during compilation. |
| Local references | `$defs`, `$ref`, including siblings of `$ref`. Empty references and `#` select the root. URI fragment JSON Pointers support percent decoding, `~0`, `~1`, empty tokens and strict array indices. |
| Dialect marker | Root `$schema` may be exactly `https://json-schema.org/draft/2020-12/schema`. Other dialects and nested dialect declarations return `UnsupportedDialect`. |
| Annotations | Correctly typed `title`, `description`, `default`, `examples`, `deprecated`, `readOnly`, `writeOnly`, and string `$comment` are accepted. They do not constrain instances and are not collected in reports. |

Nonnegative integer bounds can be arbitrarily large decimal numbers, including
exponent notation. They must have an exact integral value; negative zero is
zero. `type` arrays, composition arrays and explicit `prefixItems` arrays must
be nonempty. `required` and each `dependentRequired` list must contain distinct
strings; empty lists are allowed. Object property names compare exactly without
Unicode normalization. `propertyNames` applies its schema to each key as a
virtual string, independently of the corresponding value's type.

### Explicitly unsupported

`pattern`, `patternProperties`, `format`, `contentEncoding`, `contentMediaType`,
`contentSchema`, `unevaluatedItems`, `unevaluatedProperties`, `$id`, `$anchor`,
`$dynamicRef`, `$dynamicAnchor`, `$vocabulary`, legacy `definitions`,
`dependencies`, and `additionalItems` return `UnsupportedKeyword`. Every other
unknown keyword also returns that error. This is deliberately stricter than the
standard's recommendation to treat unknown keywords as annotations: a misspelled
or unimplemented validation rule must not silently pass.

Remote, relative-document and named-anchor `$ref` values return
`InvalidReference`. References may target only recognized schema locations:
root, values of `$defs`/`properties`/`dependentSchemas`, schema array entries, and
individual schema keywords. References into `const`, `enum`, annotations, or
schema-container objects themselves are rejected. JSON Schema core §9.4.2 does
not define references into arbitrary data or unknown-keyword structures.

References follow RFC 3986 URI fragment grammar: raw non-ASCII, spaces and invalid
percent escapes are rejected. Encode Unicode key bytes with percent escapes.
Percent decoding precedes splitting the pointer on `/`; tilde decoding occurs
exactly once inside each token, so `~01` selects a key spelled `~1`. Array indices
must be `0` or positive decimal without leading zeros; `-` is not an existing
schema. `$id` is unsupported, so references cannot change the document base.

## API and ownership

```lanius
pub struct Options {
    max_schema_nodes: i32,
    max_schema_depth: i32,
    max_validation_depth: i32,
    max_work: u64,
}
pub fn default_options() -> Options;
pub fn compile(document: &ext::json::Document, options: Options)
    -> Result<Schema, Error>;

pub impl Schema {
    pub fn borrow(&self) -> &Schema;
    pub fn scratch_len(&self) -> i32;
    pub fn validate(&self, instance: &ext::json::Document, scratch: View<u8>)
        -> Result<Report, Error>;
    pub fn destroy(&self);
}

pub struct Report { valid: bool, issue: Option<Issue>, work: u64 }
pub struct Issue {
    keyword: Keyword,
    schema_node: i32,
    instance_node: i32,
    property_name: bool,
}
pub struct Error { kind: ErrorKind, schema_node: i32, instance_node: i32 }
```

Compilation owns two `Vec<i32>` indexes, each with one slot per schema document
node. It borrows the schema document; the caller must retain its actual owner
alive and completely unchanged until the plan is destroyed. This includes
backing strings, keys, node links and public fields. `Schema` and document copies
are shallow aliases, not independent owners. Destroy exactly one owning plan;
`destroy` is idempotent on that actual owner and frees only its indexes. It never
destroys the document. After destruction `scratch_len` is zero and `validate`
returns `Destroyed`. The node-count guard detects append/destroy changes as
`ChangedDocument`; it does not make arbitrary mutations or forged records safe.

The instance must be a live, unmodified, valid JSON document throughout
validation. Returned node IDs borrow their respective document owners. The
engine rejects duplicate keys anywhere in either document, including constants,
annotations and unreachable definitions. Decoded equivalent names such as `a`
and `\u0061` are duplicates. This check does not depend on the JSON parser's
`reject_duplicate_keys` setting.

`scratch_len` is a byte count: the maximum exact decimal remainder space needed
by any recognized `multipleOf` rule, including unused definitions. Supply a
logical view at least this long for every validation, even when the current
instance makes numeric rules inapplicable. Zero scratch is valid if the plan
requires none. Packed, offset and native signed-stride views work. Physical
backing, lifetime and disjointness from schema and instance storage are caller
preconditions; counted view metadata cannot prove them. A malformed logical
start/length returns `Bounds`. Insufficient scratch returns `ScratchTooSmall`.
Those entry checks occur before scratch writes. Later numeric operations may
modify the selected scratch prefix, including on operational failure; bytes
outside the selected view are unchanged. Scratch contents are not output.
Validation allocates nothing and does not mutate either document.

## Errors and limits

Compilation checks every schema location up front, including unused `$defs`,
untaken branches and ignored `then`/`else` schemas. It also resolves every local
reference before returning a plan. Limits or allocation failure can stop that
check; an unsuccessful compilation never returns a usable partial plan and
frees any indexes it allocated.

`ErrorKind` is `Bounds`, `InvalidOptions`, `InvalidSchema`,
`UnsupportedKeyword`, `UnsupportedDialect`, `InvalidReference`, `DuplicateKey`,
`SchemaNodeLimit`, `DepthLimit`, `WorkLimit`, `Cycle`, `ScratchTooSmall`,
`CapacityOverflow`, `AllocationFailed`, `Destroyed`, or `ChangedDocument`.
Locations use `-1` when unavailable. Schema shape/type errors use
`InvalidSchema`; invalid reference syntax or targets use `InvalidReference`.

Defaults are 100,000 total schema document nodes, schema depth 64, validation
depth 64 and 10,000,000 work units. Total schema node count includes constants
and annotations. Root schema/evaluation depth is zero. Schema and validation
depth must be between zero and 128 inclusive; negative counts or larger depths
are `InvalidOptions`. Zero node or work limits are meaningful, not unlimited.
The JSON parser has separate input/node/string/depth limits; configure it too.

Compilation and each validation receive separate fresh `max_work` budgets.
Units bound semantic work rather than elapsed time: node walks, pair comparisons,
key/reference bytes, scalar-length scans and active-frame checks are charged.
Decimal parsing, integer tests and comparisons conservatively charge
`256 * (sum of input byte lengths + 1)` before their scans. Count comparisons
also use exact decimals. `multipleOf` receives the remaining shared budget and
debits the counted digit work it reports. Long coefficient or exponent tokens
therefore cannot bypass the limit. Object duplicate detection and unordered
lookup are quadratic in key count; uniqueness can be quadratic in item count.
Increase the explicit budget for workloads requiring those comparisons.

Active `(schema node, instance node, property-name flag)` pairs detect evaluation
cycles and return `Cycle`, rather than accepting or silently dropping the rule.
Recursive schemas that descend to different instance nodes work. Distinct-node
reference chains and structural equality also obey validation depth. Recursion
uses bounded stack storage, including three fixed 129-entry active-frame arrays;
there is no unbounded heap growth. Fixed stack cost is independent of input
size, while call stack use is bounded by the configured depth.

Validation is fail-fast. Ordinary invalidity is `Ok` with `valid=false` and one
`Issue`; operational limits, cycles, invalid metadata and duplicate keys are
`Err` and never converted into a failed branch. `anyOf` may stop at its first
successful branch and `oneOf` at its second success. `if`, `not` and `contains`
discard ordinary child issues appropriately; operational errors propagate.
A `$ref` is evaluated before siblings; other rules follow schema member order.
Skipped branches need not encounter their runtime cycles, though their schema
structure and reference targets were checked at compilation.

Issues identify the failing keyword's value node, or the boolean node for a
false schema. Child issues survive properties/items/references/allOf and selected
conditional branches. Thus `additionalProperties:false` reports keyword `false`
at that boolean schema and the additional member value node. `anyOf`, `oneOf`
and `not` can report their aggregate keyword. A key failure has
`property_name=true` and uses that member's value node as its stable location;
the actual key is available through `Document.key_view`. This output is not
claimed to implement the standard's Basic/Detailed output formats or JSON
Pointer diagnostics.

`keyword_name`, `keyword_name_len`, `keyword_text`, and `error_kind_text` expose
static counted diagnostic text without allocation or NUL scanning.

## Executable evidence and targets

Native x86_64 Linux is tested using real ELF programs compiled by the GPU
compiler. No GPU-device execution or other target support is claimed. Plan
compilation requires the existing allocation runtime; validation itself needs
no host service or heap calls. The `json-check` application uses the public
engine for file-schema/stdin-instance validation; its implementation and tests
are owned separately.

`tests/extended_schema_execution.rs` covers all supported keyword families
against Python `jsonschema` 4.23, with exact Decimal/Fraction numeric controls,
plus 1,500 deterministic generated schema/instance combinations. Further native
tests cover arbitrary-width/exponent numeric values, unordered nested equality,
numeric-equal uniqueness, percent/tilde/empty pointer tokens, property-name
references, recursive schemas, full upfront invalid/unsupported checks,
duplicate keys, exact work boundaries, scratch bounds, depth and cycle limits.
A 12,000-item workload validates type/integer/multiple rules; 301 nested objects
exercise a late numeric-equal duplicate. `strace` verifies 2,000 validations on
strided scratch allocate nothing, and each of the four observed allocation
failure points returns without leaked mappings, including both index failures.
All six focused groups passed in 14.06 seconds on 2026-10-23.

Run only this focused suite:

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR=/home/andrew-peterson/code/laniusc/target/stdlib-build \
  CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --test extended_schema_execution -- --test-threads=1
```

### Remaining dependencies

Full regex semantics, remote/dynamic schema resources, unevaluated annotation
tracking, extra vocabularies and format/content assertions remain unimplemented
and are explicitly rejected. They are future library work, not hidden no-ops.

An existing direct malformed generic View literal dependency has an additional
explicit-specialization reproduction in
`tests/fixtures/extended_library/schema_view_literal_repro.lani`: on base
`bface65d` it compiles but prints `77,77` rather than requested `-1,2`.
`schema_view_factory_control.lani` constructs with the slice factory then assigns
the invalid start and prints `-1,2`. These are compiler investigation fixtures,
not passing schema support claims. The engine uses established constructors;
its invalid-metadata tests construct then assign, so this dependency does not
block the supported schema profile. No compiler/runtime source was changed.

## Primary contracts

- [JSON Schema 2020-12 core](https://json-schema.org/draft/2020-12/json-schema-core),
  especially JSON equality, schema locations, references and applicators.
- [JSON Schema 2020-12 validation](https://json-schema.org/draft/2020-12/json-schema-validation),
  for assertion and annotation keyword contracts.
- [RFC 6901](https://www.rfc-editor.org/rfc/rfc6901), for JSON Pointer and URI
  fragment decoding.
