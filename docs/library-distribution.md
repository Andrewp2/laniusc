# Distributing Lanius library sources

Use `--stdlib-root` for standard modules and `--source-root` for optional
extended modules during development. A repository checkout does not require a
package server or a library bridge. The compiler resolves ordinary Lanius
`module` and `import` declarations.

`tools/vendor_lanius.py` creates a self-contained source package containing
exactly the sources reachable from an existing compiler package manifest. It
uses `laniusc package lock` for resolution, copies sources without rewriting
them, and verifies that the relocated package resolves the same closure.
This Python command is build/distribution tooling; compiled programs execute
the copied Lanius implementations.

## Create a selective bundle

The existing compiler manifest format is:

```json
{
  "package": "example.calculator",
  "roots": ["src", "extended"],
  "stdlib_root": "stdlib",
  "entry": "src/app/main.lani"
}
```

Paths are relative to the manifest directory. The entry above must declare
`module app::main;`. User and extended roots are separate directories; standard
modules retain their standard-library classification. Package roots must obey
the compiler's existing path and module-identity checks. External package
dependencies and registry resolution are not implemented by this command.

For a fresh example from this repository, prepare sources under an ignored
directory. These commands copy the calculator entry and make both library trees
available to the compiler; the bundle later keeps only reachable files:

```sh
mkdir -p target/stdlib-work/distribution-demo/src/app
timeout --kill-after=2s 20s cp -R stdlib extended target/stdlib-work/distribution-demo/
cp sample_programs/library/expr_calc.lani target/stdlib-work/distribution-demo/src/app/main.lani
cat > target/stdlib-work/distribution-demo/lanius.package.json <<'EOF'
{
  "package": "example.calculator",
  "roots": ["src", "extended"],
  "stdlib_root": "stdlib",
  "entry": "src/app/main.lani"
}
EOF
timeout --kill-after=2s 100s python3 tools/vendor_lanius.py \
  --compiler "$PWD/target/stdlib-build/debug/laniusc" \
  --manifest target/stdlib-work/distribution-demo/lanius.package.json \
  --out target/stdlib-work/calculator-bundle
timeout --kill-after=2s 100s python3 tools/vendor_lanius.py \
  --verify target/stdlib-work/calculator-bundle
```

`--out` must name a new directory whose parent exists. The command refuses
existing files, directories and symlinks. It never merges or replaces a prior
bundle. Keep that new directory exclusively owned by the command until it
returns. A failed creation removes only the directory it just created. A
forced process kill can leave an incomplete directory; absence of a complete,
valid `SHA256SUMS` identifies it as unfinished.

The default compiler is `LANIUSC`, or `laniusc` from PATH. `--compiler` overrides
it. Paths are passed as distinct subprocess arguments, including paths with
spaces or shell metacharacters.

## Relocate and compile

The bundle contains:

| Path | Contents |
| --- | --- |
| `lanius.package.json` | Relocatable manifest with relative source roots and entry |
| `stdlib/` | Reachable standard-library sources, if configured |
| `sources/NNNN/` | Reachable files under each original user/extended root |
| `notices/` | Repository license notices and explicit additional notices |
| `BUNDLE.txt` | Package, compiler/edition and source-size metadata |
| `SHA256SUMS` | Sorted SHA-256 inventory of every payload file |

Source files retain embedded copyright and license notices. Repository MIT,
Apache, Unicode and float-conversion notices are included. Use repeatable
`--notice PATH` arguments for additional application/dependency notices. Each
notice must resolve to a regular file, at most 1 MiB; at most 64 notices total
are admitted. The tool rejects FIFOs/devices/directories before reading from
their opened descriptors.

Move or copy the entire completed bundle, then compile with its manifest:

```sh
mv target/stdlib-work/calculator-bundle target/stdlib-work/calculator-relocated
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --package-manifest target/stdlib-work/calculator-relocated/lanius.package.json \
  -o target/stdlib-work/calculator
printf '1+2*3\n-(5+6)\n' | timeout --kill-after=2s 10s target/stdlib-work/calculator
```

Expected stdout is `7` and `-11`, each followed by LF. No original source-tree
path is required by the relocated manifest. Compiler lockfiles contain absolute
paths, so the bundle does not ship the temporary locks used during creation.
Generate a fresh lock at its final location if desired:

```sh
timeout --kill-after=2s 30s target/stdlib-build/debug/laniusc package lock \
  --manifest target/stdlib-work/calculator-relocated/lanius.package.json \
  -o target/stdlib-work/calculator.lock.json
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --package-lockfile target/stdlib-work/calculator.lock.json \
  -o target/stdlib-work/calculator-locked
```

Keep generated binaries and new lockfiles outside the immutable bundle so its
inventory continues to verify. Editing a vendored source produces a new package
snapshot and invalidates the old inventory.

## Integrity, limits and evidence

The original compiler lock records source lengths and FNV digests. Copying
checks those exact bytes, detecting sources changed since resolution. The final
SHA-256 inventory detects changed, missing, additional or symlinked payloads.
It is an integrity inventory, not a signature or proof of origin. Supply and
verify a trusted external digest/signature when publishing an authenticated
release.

Source limits default to 4,096 files and 64 MiB. `--max-files` and `--max-bytes`
can lower those limits; larger values are rejected. Each compiler metadata call
has a 30-second limit; the CLI has a 90-second overall deadline. Verification
also bounds inventory size, payload count and total bytes. The examples use an
outer timeout below two minutes. There is no GPU compilation during vendoring
or inventory verification.

Focused tests are `tools/test_vendor_lanius.py` and
`tests/library_distribution_execution.rs`. They cover exact-byte mutations,
missing/extra sources, symlinks, unsafe inventory paths, limits, existing-output
preservation, failure cleanup, regular-file notices and deterministic ordering
when a module has both `app.lani` and `app/main.lani`. The native integration
moves a selective calculator bundle, deletes its original input package,
generates a new lock and executes the emitted ELF against exact output. It also
checks identical bundle content at different output paths.

Verified tooling/execution target is Linux x86_64 with Python 3 and the current
compiler. This is source distribution, so users still need a working compiler
and the host bindings their program uses. User GPU execution, a package registry,
binary SDK installation and a complete generated API reference remain separate
completion work.
