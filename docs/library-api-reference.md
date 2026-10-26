# Generated declaration reference

The [module index](api/README.md) inventories source declarations in `stdlib/`
and `extended/`. Each module page retains public signatures, generic bounds,
enclosing impl/trait headers, types, fields, enum variants and constants, with
links to their exact source lines. Function bodies are omitted. Direct source
imports link to the corresponding module pages.

This improves discovery. It does not complete the semantic API reference.
Linked guides own runtime behavior, target evidence, errors, ownership,
preconditions and numerical limits. A body, declaration, import or successful
source extraction does not establish execution. The generator performs no
compilation or runtime test, and its declared imports are not a resolved package
closure. Use the compiler's package resolver for source distribution.

## Generate and check

From the repository root, with Python 3.10 or newer:

```sh
timeout --kill-after=2s 100s python3 tools/generate_library_reference.py
timeout --kill-after=2s 100s python3 tools/generate_library_reference.py --check
timeout --kill-after=2s 100s python3 -m unittest discover -s tools -p test_generate_library_reference.py
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

At the AtomicFile/KV, TempFile/FileOps and server public-interface freeze, the
bounded writer and final `--check` both exit zero for **246 pages from 245 source
modules, with 8,119 public declaration markers**. The inventory adds
[`atomic_file`](api/std/atomic_file.md) and refreshes the module index,
[`kv`](api/ext/kv.md), [`file_ops`](api/std/file_ops.md) and
[`temp_file`](api/std/temp_file.md): five generated output pages change at this
checkpoint. The existing server reference pages remain included. The preceding
TempFile/FileOps/server check was 245 pages, 244 modules and 8,090 markers.
These are declaration markers, not a count of working functions.

The root `README.md`, `AI_POLICY.md` and `CONTRIBUTING.md` have matching SHA-256
hashes before generation and after the final check. The generator writes only
the reference tree. Metadata includes AtomicFile's 66 process invocations across
four groups and the migrated KV application's 64 across two, with preliminary
overlap and CPU/build admission kept separate. It preserves finite
TempFile/FileOps, server/application, scale, teardown and scheduler receipts.
The complete library goal remains open, server coverage gaps stay explicit in
the [overview](library-overview.md), and archive extraction is proposed work.
Generation supplies no runtime acceptance for any API.

## Source boundaries

`tools/generate_library_reference.py` is documentation tooling. Declaration
boundaries follow the current [language grammar](../grammar/lanius.bnf), while
the original source spellings remain authoritative. It skips comments and
opaque string/character literals before recognizing declaration boundaries.
It balances delimiters to skip bodies and retain nested type arguments, array
counts and enum payloads. Unknown public declaration shapes stop generation
with a source path and line instead of silently disappearing from the index.

The scanner does not validate the language grammar, infer types, resolve trait
calls, decide semantic visibility or act as a compiler fallback. A public
method is retained with its complete impl header, including an impl not itself
spelled `pub`; trait members are retained under their public trait. Fields and
variants appear under their declared public owner, without implying that
arbitrary construction or mutation satisfies that owner's invariants. Private
function bodies and private helper types are excluded.

All `.lani` sources in the two roots are scanned, including newly added modules.
Module paths must match their root-relative source paths and declared imports
must name an inventoried source. This checks the inventory's links; it does not
replace compiler module resolution. Limits are 4,096 files, 4 MiB per source
file, one million documentation tokens per file and 64 MiB total source bytes.
Opened files must be regular UTF-8 files.

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
