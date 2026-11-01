# JSON Schema validation over JSON trees

`ext::json_schema` validates [`ext::json_tree`](extended-json-patch.md) documents against JSON Schema draft 2020-12. It covers:

- the core vocabulary: `$ref` within one document, `$defs` and `$schema`;
- the applicator vocabulary;
- the validation vocabulary.

`pattern` and `patternProperties` use [`ext::regex`](extended-regex.md). The module is in the `extended` source root.

[`ext::schema`](extended-schema.md) is the older profile over `ext::json` documents. It has no regular expressions, treats unknown keywords as errors, and reports the first failing keyword. This module follows the specification's handling of unknown keywords and returns only valid or invalid.

## API

```text
ext::json_schema::compile(tree: &ext::json_tree::Tree, limits: Limits) -> Result<Schema, Error>
ext::json_schema::default_limits() -> Limits      // max_depth 256, max_work 10,000,000
Schema.validate(instance: &ext::json_tree::Tree) -> Result<bool, Error>
Schema.validate_node(instance: &ext::json_tree::Tree, node: i32) -> Result<bool, Error>
Schema.destroy()
ext::json_schema::kind_name(kind: ErrorKind) -> Text
```

- **Borrowing:** a `Schema` borrows the schema tree, which must stay alive and unchanged until `destroy`.
- **Errors:** `Error` is `{ kind, schema_node }`. `kind` is one of:
  - `InvalidSchema`
  - `InvalidPattern`
  - `InvalidReference`
  - `Unsupported`
  - `UnsupportedDialect`
  - `DepthLimit`
  - `WorkLimit`
  - `AllocationFailed`

  An invalid instance is not an error: it is `Ok(false)`.
- **Compilation:**
  - It checks every keyword the root reaches, including unused `$defs` entries and branches that are never taken.
  - It compiles every pattern and resolves every `$ref` before it returns, then indexes each object schema's keywords in a fixed record.
  - Validation then does no keyword lookup.
  - A failed compilation frees everything it allocated.

## Keywords

| Family | Keywords | Rules |
| --- | --- | --- |
| Schemas | `true`, `false`, objects | Any other value where a schema is expected is `InvalidSchema`. |
| Types | `type` | A type name, or a nonempty array of distinct names. `integer` matches any number with an integral value (`1.0`, `1e2`). Booleans are not numbers. |
| Equality | `enum`, `const` | Exact JSON equality, as in `ext::json_tree::equal`. Numbers compare by value, arrays in order and objects in any order. An empty `enum` matches nothing. |
| Numbers | `multipleOf`, `maximum`, `exclusiveMaximum`, `minimum`, `exclusiveMinimum` | Exact decimal arithmetic on the number spellings, with no floating point. `multipleOf` must be positive. A divisor with more than 18 significant digits is `Unsupported`. |
| Strings | `minLength`, `maxLength`, `pattern` | Lengths count Unicode scalar values. `pattern` is an unanchored search. |
| Arrays | `prefixItems`, `items`, `contains`, `minContains`, `maxContains`, `minItems`, `maxItems`, `uniqueItems` | `items` applies after `prefixItems`. `minContains` defaults to 1, and without `contains` both contains bounds have no effect. |
| Objects | `properties`, `patternProperties`, `additionalProperties`, `propertyNames`, `required`, `dependentRequired`, `dependentSchemas`, `minProperties`, `maxProperties` | `additionalProperties` applies to members matched by neither `properties` nor `patternProperties` of the same schema object. `propertyNames` validates each key as a string. |
| Composition | `allOf`, `anyOf`, `oneOf`, `not`, `if`, `then`, `else` | The arrays must be nonempty. `then` and `else` have no effect without `if`, but they are still compiled. |
| References | `$ref`, `$defs` | See [References](#references). |
| Dialect | `$schema`, `$id` | `$schema` must be exactly `https://json-schema.org/draft/2020-12/schema`, otherwise `UnsupportedDialect`. A string `$id` is accepted on the root only. |

- **Counts:** count keywords take any nonnegative number with an integral value (`2.0`, `1e1`). Values above 2^31-1 saturate.
- **Distinct strings:** `required` and each `dependentRequired` list must hold distinct strings.
- **Ignored keywords:** annotations (`title`, `description`, `default`, `examples`, `deprecated`, `readOnly`, `writeOnly`, `$comment`) and `format` (an annotation by default in 2020-12) are ignored, as the specification requires for unknown keywords. Keywords from earlier drafts such as `definitions`, `dependencies` and `additionalItems` are also unknown keywords and are ignored.
- **Unsupported keywords:** `$anchor`, `$dynamicRef`, `$dynamicAnchor`, `$vocabulary`, `unevaluatedItems`, `unevaluatedProperties` and a nested `$id` return `Unsupported`, because ignoring them would change results.

### References

- **Form:** a reference must be `#` followed by a JSON Pointer, so `#`, `#/$defs/a` and `#/prefixItems/0` all work.
- **Decoding:** `%XX` escapes are decoded first and the pointer's `~0` and `~1` second, so `#/$defs/e%25f` names the key `e%f` and `%C3%A9` names `é`.
- **Lenient characters:** characters that RFC 3986 would require to be percent-encoded are accepted as they are.
- **Rejected forms:** relative or remote references, anchor fragments (`#foo`), malformed escapes, and pointers that miss or select a value that is not a schema all return `InvalidReference`.
- **Any location:** the target can be anywhere in the document, including inside an unknown keyword such as `definitions`, and it is compiled as a schema when it is reached.

### Evaluation

Each object schema is evaluated in this order, stopping at the first failure:

1. `$ref`
2. `type`, `enum`, `const`
3. The number, string, array or object keywords for the instance's type
4. `allOf`, `anyOf` (stopping at the first success) and `oneOf` (stopping at a second success)
5. `not`
6. `if` with `then` or `else`

Within an object instance, the keywords run in this order:

1. The counts, `required` and `dependentRequired`
2. `properties`, in schema order
3. `patternProperties` and `additionalProperties`, in instance member order
4. `propertyNames`
5. `dependentSchemas`

**Limits:**
- Every subschema evaluation, including through `$ref`, counts one unit of work and one level of depth.
- A reference cycle that never consumes the instance, such as `{"$ref":"#"}`, reaches `DepthLimit`. Recursive schemas that walk down the instance work up to the depth limit.
- Going over `max_work` is `WorkLimit`. Regex search work is limited separately by `ext::regex`.

**Pattern matching:** patterns use the lazy DFA when `ext::regex` can build one, and the Pike VM otherwise (for lookbehind). One shared workspace serves every pattern.

## Speed

On a 3.1 MB array of 50,000 objects, each checked for type, `required`, four `properties`, `pattern`, an `enum`, `uniqueItems`, `multipleOf` and `additionalProperties: false`, the batch driver takes 0.76 s end to end. Parsing alone is 0.40 s.

| Part | Time |
| --- | --- |
| Validation without `pattern` | 0.22 s |
| The 50,000 `pattern` searches | 0.14 s |

## Execution evidence

The official JSON-Schema-Test-Suite is not on this machine, so the cases are written by hand from the 2020-12 core and validation specifications.

[`tests/fixtures/extended/json_schema/oracle.py`](../tests/fixtures/extended/json_schema/oracle.py) is a Python model of the profile above. It uses the same compile checks, evaluation order and depth and work counting. Numbers use `Decimal` and `Fraction`, and patterns use `re` with `re.ASCII` and `$` mapped to `\Z`. Patterns are restricted to the syntax `ext::regex` and Python share.

**Checks:**
- The model must first reproduce the expected result of every hand-written case.
- Then [`batch.lani`](../tests/fixtures/extended/json_schema/batch.lani), compiled with `lcc`, runs all cases in one process, and its outputs must match the model's.

**Generated cases:**
- Schemas nest up to four levels and use every keyword above.
- Each schema has `$defs` names that need `~0`/`~1` escapes, and references into them, including cycles.
- Each schema is paired with five random instances.

| Group | Cases | Agree |
| --- | --- | --- |
| Specification cases (86 schemas) | 246 | 246 |
| Error kinds and compile checks | 80 | 80 |
| Depth and work limits | 12 | 12 |
| Generated schema/instance pairs | 10,000 | 10,000 |

**Outcomes:**
- The default seed gives 6,713 valid and 3,466 invalid results, plus every error kind except `AllocationFailed`.
- Seeds 9 and 31 with `--cases 10000` (50,000 pairs each) also agree.

**Mutation checks:** five single-line changes to the model each contradict a hand-written expectation:
- `items` ignoring `prefixItems`
- `patternProperties` not covering members for `additionalProperties`
- `minContains` defaulting to 0
- `integer` excluding `1.0`
- `oneOf` accepting two matches

```text
lcc -o batch tests/fixtures/extended/json_schema/batch.lani --stdlib-root stdlib --source-root extended
python3 -I tests/fixtures/extended/json_schema/oracle.py ./batch [--seed N] [--cases N]
```
