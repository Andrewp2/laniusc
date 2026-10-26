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

At the archive source/API freeze, the bounded writer and final `--check` both
exit zero for **250 pages from 249 source modules, with 8,197 public declaration
markers**. Across this increment seven outputs change: the [index](api/README.md),
four new pages for
[`archive_plan`](api/ext/archive_plan.md),
[`archive_profile`](api/ext/archive_profile.md),
[`archive_source`](api/ext/archive_source.md) and
[`archive_extract`](api/ext/archive_extract.md), plus
[`zip`](api/ext/zip.md) and [`file_ops`](api/std/file_ops.md).
They retain the current public signatures, raw ZIP creator field, checked
directory operations, exact source locations and reviewed contract links.
Declaration markers do not count working functions. Final receipts are
`target/stdlib-work/archive-reference-writer-note-correction.log` and
`archive-reference-check-note-correction.log` in that same directory. This
final repeat qualifies the materializer fixture's failure history; only its
generated page changes, and declaration totals stay unchanged.

The supported direct CPU test runner passes **26 tests in 3.129 seconds** in
`target/stdlib-work/archive-reference-generator-tests-first.log`. This includes
module/item imports, module precedence, public enum variants, private/missing
item rejection, no re-exports, and opaque bodies containing `?`/inferred locals.
It verifies documentation tooling, not compiled language or library behavior.

The root `README.md`, `AI_POLICY.md` and `CONTRIBUTING.md` have matching SHA-256
hashes before generation and after the final check. The generator writes only
the reference tree. The preceding first language-adoption and AtomicFile/KV
inventories had 246 pages, 245 modules and 8,119 markers; the former updated six
item-import source pages and the latter added
[`atomic_file`](api/std/atomic_file.md). Their finite receipt metadata and older
TempFile/server notes retain their guide-defined scope. The complete
library goal remains open in the [overview](library-overview.md). Generation
supplies no runtime acceptance for any API.

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
spelled `pub`; trait members are retained under their public trait. Fields and
variants appear under their declared public owner, without implying that
arbitrary construction or mutation satisfies that owner's invariants. Private
function bodies and private helper types are excluded.

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
