# CLI match-result binding reproduction

On 2026-10-23, the full `original.lani` source failed with LNC0005 at line 139:
`at` is unresolved immediately after a `let at = match ...` whose payload
bindings are also named `at`. `control.lani` changes only the outer local name to
`location` and compiles successfully. This pair was checked once in the isolated
source root below, with the same outcomes as the original application location.

**Root cause is unestablished.** The six-line `tiny-original.lani` reduction and
its renamed `tiny-control.lani` both compile. The evidence establishes a
source-composition-sensitive compiler failure; it does not establish a general
match-shadowing defect or a regex execution defect. No compiler fix is included.

Run from the repository root:

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --stdlib-root stdlib \
  --source-root tests/fixtures/stdlib_compiler_state/cli_match_shadow/extended \
  tests/fixtures/stdlib_compiler_state/cli_match_shadow/original.lani \
  -o /tmp/lanius_cli_shadow_original
# Observed: exit 1, LNC0005 unresolved identifier at original.lani:139:35.

timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --stdlib-root stdlib \
  --source-root tests/fixtures/stdlib_compiler_state/cli_match_shadow/extended \
  tests/fixtures/stdlib_compiler_state/cli_match_shadow/control.lani \
  -o /tmp/lanius_cli_shadow_control
# Observed: exit 0, native executable emitted.
timeout --kill-after=2s 10s /tmp/lanius_cli_shadow_control --help
# Observed: exit 0, usage; native selection also returns the expected bytes.
```

The isolated user source root snapshots `ext::cli` and finalized `ext::regex`.
All standard-library imports resolve through the repository `stdlib` root.
`imports.sha256` records every transitive import at observation time; the
repository commit containing this fixture preserves those referenced bytes.
The application itself originally resolved user modules through `extended`.
Using both the fixture and repository `extended` roots together is ambiguous
because they each provide `ext::cli` and `ext::regex`.

The base repository HEAD at observation was
`98166628aa2d194ba5e0f27bbbd2caf535acfc20`. The compiler executable SHA256 was
`662b2ffeeb8b773bcfc57942ca4abc20f1533c856e0c466d3ed2a2953e32d9af`.

The production application uses the passing outer-local spelling. Its focused
functional and independent Python-regex differential groups then compiled and
executed successfully: 2 passed, 1 allocation-fault group intentionally skipped.
The differential workload includes nullable repetition `^(?:a?|é)*$` over
newline, CRLF, Unicode, NUL, empty, and unterminated records in plain, numbered,
inverted, and count modes.
