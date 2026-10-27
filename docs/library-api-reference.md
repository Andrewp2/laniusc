# Generated declaration reference

The [module index](api/README.md) inventories source declarations in `stdlib/`
and `extended/`. Each module page retains public signatures, generic bounds,
enclosing impl/trait headers, types, fields, enum variants and constants, with
links to their exact source lines. Function bodies are omitted. Direct source
imports link to the corresponding module pages; item imports also link to the
exact declaration's source line.

This improves discovery. It does not complete the semantic API reference.
Linked guides own runtime behavior, target evidence, errors, ownership,
preconditions and numerical limits. A body, declaration, import or successful
source extraction does not establish execution. The generator performs no
compilation or runtime test, and its declared imports are not a resolved package
closure. Use the compiler's package resolver for source distribution.

## Generate and check

From the repository root, with Python 3.10 or newer:

```sh
timeout --kill-after=2s 100s python3 -B tools/generate_library_reference.py
timeout --kill-after=2s 100s python3 -B tools/generate_library_reference.py --check
timeout --kill-after=2s 100s python3 -B tools/test_generate_library_reference.py
```

These commands are CPU-only and require no compiler binary, shader build or
GPU. Generation uses relative paths, sorted module order and source order within
each declaration category. It includes no wall-clock timestamp or absolute
checkout path. `--check` compares expected output without writing anything;
new or removed modules and changed signatures/source line positions make it
fail until regeneration. Exit statuses are 0 for success, 1 for stale checked
output and 2 for invalid input or an I/O error.

The generator may replace or delete only pages carrying its exact generated
banner under `docs/api/`. It refuses to replace a handwritten file at an output
path, rejects symlinks and preserves unrelated files. Generated pages are not
edited by hand. The handwritten guide you are reading is outside that tree.

### Current generation receipt

At the nested-iteration source/API freeze, the bounded writer and `--check`
both exit zero for **251 pages from 250 source modules, with 8,295 lexical
public declaration markers**. Exactly six outputs change: the
[index](api/README.md), [core::iter](api/core/iter.md),
[core::format](api/core/format.md), [http_batch](api/ext/http_batch.md),
[https_batch](api/ext/https_batch.md) and [regex](api/ext/regex.md).

The new iterator declarations link the
[scan/nested contract](stdlib-nested-iteration.md) and
[real flatten_sum guide](stdlib-flatten-sum.md). Core source is `7256a394...`;
application source is `946043fe...`. Two direct public smoke programs, three
semantic/model Rust gates and all four application tests have finite native
receipts. All four strict owner oracle groups also pass directly on one
retained ELF: 156 group cases with overlapping baselines and 132 individually
reached OOMs. Those are not four passing Rust libtests. The selected increment
is accepted on its finite native profile; source generation itself establishes
no runtime behavior and does not complete the full library goal.

Final classification receipts are
`target/stdlib-work/nested-iteration-reference-final-writer.log` and
`nested-iteration-reference-final-check.log` in that same directory. The earlier
`nested-iteration-reference-writer-first.log`/`nested-iteration-reference-check-first.log`
recorded the same source/counts with strict owners still pending. This final
refresh changes only the core::iter status note; the six changed outputs above
are relative to the preceding filesystem source freeze. The
[overview](library-overview.md) records runtime scope separately. Public `pub`
spellings are counted lexically, including required public implementations of
private helper types; the count is not a number of externally usable APIs or
working functions.

A narrow scanner correction now excludes implementation blocks whose direct
receiver is a known local private struct/enum. That removes eight internal
blocks: `NestedIdentity`, format's `Output`, plain/HTTPS batch driver/factory
helpers, and regex's empty Parser/Builder blocks. Public, unknown, external,
primitive and generic-parameter receivers retain their existing inventory.
This is a source-visibility boundary, not a new compiler or type resolver.
The precise rule and retained checks are described below.

Three focused CPU controls pass in 0.002s (direct tool output). The full
supported CPU runner then passes **29 tests in 3.711 seconds** in
`target/stdlib-work/nested-iteration-reference-generator-tests-first.log`.
The new controls require private-owner suppression, positive public/external/
builtin/generic-shadow retention, and rejection of unsupported public syntax
inside a hidden owner's block. Existing import, source-span, marker-count,
output-ownership and stale-check controls also pass. These tests verify tooling,
not native library behavior; they were not repeated for later metadata edits.

The root `README.md`, `AI_POLICY.md` and `CONTRIBUTING.md` have matching SHA-256
hashes before generation and after the final check. The generator writes only
the reference tree. The preceding filesystem freeze had 251 pages, 250 modules
and 8,259 markers, updating FileOps/new TempDir and the index. The reusable-regex
freeze had 250 pages, 249 modules and 8,220 markers; the archive freeze had
250/249/8,197. The earlier language-adoption/AtomicFile inventory had 246 pages,
245 modules and 8,119 markers. Their receipts retain their guide-defined scope.

## Source boundaries

`tools/generate_library_reference.py` is documentation tooling. Declaration
boundaries follow the current [language grammar](../grammar/lanius.bnf), while
the original source spellings remain authoritative. It skips comments and
opaque string/character literals before recognizing declaration boundaries.
It balances delimiters to skip bodies and retain nested type arguments, array
counts and enum payloads. Unknown public declaration shapes stop generation
with a source path and line instead of silently disappearing from the index.

The scanner does not validate the language grammar, infer types, resolve trait
calls or act as a compiler fallback. Import-link checks use declared public
ownership in the source, not compiler visibility analysis. A public
method is retained with its complete impl header, including an impl not itself
spelled `pub`; trait members are retained under their public trait. A complete
module scan first records local struct/enum visibility. An impl whose direct
nominal receiver is one of those known private local types is excluded together
with its methods, even if the impl must be spelled `pub`. Later type declarations
and same-module-qualified receivers are recognized; generic binders shadowing
a local type name remain generic receivers. Public/unknown/external/primitive
receivers retain their existing treatment. The scanner does not resolve aliases,
imports, generic bounds or arbitrary composite types to infer additional private
owners. Unsupported public shapes are still rejected during the complete scan
before this filter; all lexical `pub` markers remain counted.

Fields and variants appear under their declared public owner, without implying
that arbitrary construction or mutation satisfies that owner's invariants.
Private function bodies and private helper types are excluded.

All `.lani` sources in the two roots are scanned, including newly added modules.
Module paths must match their root-relative source paths. Import links follow
the [item-import contract](language-ergonomics.md#item-imports):

- An inventoried module matching the entire path wins, even if the prefix
  module contains a public item with that same final name.
- Otherwise, the prefix must be an inventoried module and the last segment
  must identify exactly one public declaration there. Variants of public enums
  have module-level names, including `core::result::Ok`; their declaration links
  point to the variant's own source line.
- Private, missing or ambiguous items fail with the importing file/line.
  Struct fields, impl methods and private-enum variants are not module items.
  Imported names are not re-exported. Aliases, globs and `use` are unsupported.

An item link preserves the full written import path, identifies its declaration
kind, links the owning module page and the exact declaration, and retains a
separate link to the import line. Existing module links keep their format.
This static inventory lookup does not replace compiler package/name resolution,
type checking or runtime verification. Short public signatures keep their
original source spelling; the generator does not expand imported type names.
Limits are 4,096 files, 4 MiB per source file, one million documentation tokens
per file and 64 MiB total source bytes. Opened files must be regular UTF-8 files.

## Reviewed guide mappings and status notes

`tools/library_reference_metadata.json` contains reviewed guide links and
exceptional role/status notes. Source paths, signatures and counts are derived
from source; they are not repeated in this metadata. Guide links are validated
against regular files in `docs/`. A newly added module without a mapping gets
the default **Source inventory** profile and an explicit **No contract guide
registered** notice. The index lists these gaps without inventing support.

Generated Unicode/terminal data, the distribution erfc helper and command
syscall support remain discoverable in a separate support section. Their
public source spelling does not make them independent application workflows.
The curated exceptions distinguish:

- Unbound `std::net`, `std::thread` and `std::gpu` host declarations. Working
  sockets use `std::socket` over the Linux binding separately.
- Metadata-only `std::host` and `test::harness`, distinct from working explicit
  source suites.
- Mixed `std::time` bindings: counted reads and i32 sleep execute, while the
  three listed legacy i64 host declarations remain unbound.
- Real `core::panic` traps beside unavailable hook metadata.
- The protected legacy `std::vec` identity and its different ownership/failure
  policies, with canonical `alloc::vec` migration guidance.

These notes are reviewed documentation, not automatically derived capability
claims. Review a mapping when the owning API or guide changes. A linked guide
does not imply that it documents every inventoried declaration individually.
Remaining semantic documentation and behavior work stays on the
[library roadmap](library-roadmap.md).

## Verification scope

Focused CPU tests check exact retained source spelling and locations, multiline
bounds, const generics, methods with repeated names under distinct owners,
trait members, nested fields/variants, externs, comments and escaped literals,
unsupported declarations, source/import identity, deterministic rendering and
output ownership. Whole-tree extraction and generated-output checking cover
the current source inventory. These are documentation extraction checks, not
per-function synthetic execution tests or a new library acceptance gate.
