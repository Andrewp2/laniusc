# Parser disambiguation in the readlink count guard

`cast_guard.lani` is the minimal failing reproduction. It imports no library
module. This condition is read as the start of a generic application:

```lani
if(received<0 || received>(requested as i64)) { return false; }
```

On the current compiler it fails before native emission with parser code 4,
detail 3, followed by LNC0016 at `||`: expected `>` or `,`. The semantically
equivalent `local_guard.lani` widens the requested count into an i64 local,
then compares against that identifier. It compiles and exits zero, checking
zero, exact capacity, negative and excessive results. No compiler source is
changed. This observation concerns this ambiguous source form, not ordinary
generic arguments, casts or numeric comparisons in general.

## Production resolution

The original FileOps source SHA-256
`46dbefa1be4e4478d30136e230edd152a92b3903e3f0fc56119a751bd871744f`
contained the same guard. Even unused `std::file_ops` or `std::temp_dir`
imports failed. In that larger import composition the host fallback diagnostic
instead pointed to an existing `Mapper<T,Option<U>>` bound in `core::iter`.
That label did not identify the failing construct. The minimal reproduction
above produces its own direct syntax diagnostic without any trait declaration.

The production fix is only:

```lani
let requested_wide:i64=requested as i64;
if(received<0 || received>requested_wide) { return Err(Error::InvalidCount); }
```

It preserves the API, syscall, error order, full-width comparison and validation
before copying. The resulting FileOps SHA-256 is
`21269e340801c09396a133a43ea5f5391307a59de861476605a140f953530ab6`.
An independent review reversed this hunk and recovered the original hash.
The full module with this single change compiles and its unused-import control
exits zero. Runtime API acceptance belongs to the dedicated filesystem tests,
not that return-zero control.

## Receipts and controls

The freshly built CLI has SHA-256
`394ed7df0dcac4a432fbbb392de87fa4c4fb98263bd92a2a725c91a183077153`.
Logs under `target/stdlib-work/` record:

- `filesystem-mktemp-behavior-first.log`: both selected app tests failed before
  ELF emission, 2.56 seconds; no application runtime acceptance.
- `filesystem-import-{temp_dir,file_ops}-fresh-cli.log`: original full-import
  failures, reproduced after a fresh 33.46-second CLI build.
- `filesystem-import-baseline-copy-first.log`: HEAD's earlier FileOps module
  admits in a copied stdlib root.
- `filesystem-import-{links,permissions}-first.log`: each corresponding added
  function group admits; `filesystem-import-read-first.log` fails.
- Prefix controls narrow the read function to its count-validation guard.
  `filesystem-cast_guard-first.log` then fails on the standalone reproduction;
  `filesystem-local_guard-first.log` compiles and its ELF exits zero.
- `filesystem-import-local-guard-first.log`: the complete new module with only
  the widened local admits; its ELF also exits zero.

The two `field_comparison` controls both compile and exit zero. The earlier
suspected inline record comparison was not causal. A full-module local-field
rewrite and a member-comparison rewrite also retained the original failure.
Those unsuccessful hypotheses do not justify changing other library code.
An initial symlink-based source-root control failed module discovery before
parsing; the copied-root retries above are the actual comparison evidence.
`temp_file.lani` is an additional unused-import entry, not an executed receipt.

Reproduce each compiler command serially under the repository lock and with an
outer deadline below two minutes:

```sh
timeout --kill-after=2s 100s flock target/stdlib-work/library-gpu.lock \
  env LANIUS_DEBUG_STAGE_ERRORS=1 target/stdlib-build/debug/laniusc \
  --stdlib-root stdlib --emit x86_64 \
  tests/fixtures/stdlib_compiler_state/filesystem_imports/cast_guard.lani \
  -o /tmp/readlink-cast-guard.elf

timeout --kill-after=2s 100s flock target/stdlib-work/library-gpu.lock \
  target/stdlib-build/debug/laniusc --stdlib-root stdlib --emit x86_64 \
  tests/fixtures/stdlib_compiler_state/filesystem_imports/local_guard.lani \
  -o /tmp/readlink-local-guard.elf && timeout 5s /tmp/readlink-local-guard.elf
```

The first command is expected to fail. The second requires both compilation
and native success. Production filesystem behavior still requires its own
semantic, ownership and fault gates.
