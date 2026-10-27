# CLI help nested error-pattern admission

Status: the complete public help smoke and the standalone pair below confirm a
target-generation dependency for these two nested `Result`/local-error patterns.
Explicitly typed error extraction compiles and executes. No compiler
implementation is changed and no general nested-pattern restriction is claimed.

## Confirmed complete consumer

`original_help_smoke.lani` preserves the exact consumer that failed target
generation with generic `LNC0057`, before producing an ELF. The diagnostic gives
no responsible compiler pass or more specific target failure. Its two nested
patterns are:

```lani
core::result::Err(ext::cli_commands::Error::OutputTooSmall(required))
core::result::Err(ext::cli_commands::Error::UnknownCommandId(id))
```

Changing only those two assertions to explicitly typed `Error` values obtained
with `core::result::unwrap_err`, then matching the inner variant, admits the same
consumer and its native execution exits zero. The checks still require errors
with exact `required == 113` and `id == 99` payloads. `unwrap_err` rejects an `Ok`,
and each inner wildcard still fails its assertion. All literal help comparisons,
inherited/local option checks, bounds and complete buffer canaries are unchanged.

Root supplied these receipts in `target/stdlib-work/`:

| Consumer | Result | Log |
| --- | --- | --- |
| Original nested assertions | `LNC0057`, no ELF/native execution | `cli-commands-help-smoke-first.log` |
| Explicit error extraction | Compilation exits zero | `cli-commands-help-smoke-explicit-errors.log` |
| Same explicit consumer | Native execution exits zero | `cli-commands-help-smoke-native-first.log` |

Exact SHA-256 references:

| Source | SHA-256 |
| --- | --- |
| Preserved `original_help_smoke.lani` | `10112a9aada094793deff6c7b9170b2c74dfbe7c797fbf71f886c7e2e2585a39` |
| Accepted `tests/fixtures/extended/cli_commands/help_smoke.lani` | `aada787fd286350063f316c37824f4f92b9a2f9b94e0e56bba1c254bde1315f2` |
| Unchanged `extended/ext/cli_help.lani` | `a7198a2a18f6dcac549fb08c5735af538689b76f53b0be4e942798227ec9f60a` |
| Unchanged `extended/ext/cli_commands.lani` | `6eb4db7ad6f63768a3fe96c6aee6dec55560f8d098efe7a5dbbbfff5e7cb536f` |
| Unchanged `extended/ext/cli.lani` | `9f11981f1292bea61c3c571ff86b0fcdba52259c8e626886e4e6b322557a17cd` |

`restore_nested_assertions.patch` is the exact two-assertion reverse patch from
the accepted consumer to the original. Its SHA-256 is
`d80b20fcc27123baf67a8a78261f946816b25221624e4185e0e474d777db6f2e`.
Applying it to a separate output file reconstructs the original SHA above;
the author checked that reconstruction without invoking the compiler:

```sh
patch --batch --output target/stdlib-work/cli-help-reconstructed-original.lani \
  tests/fixtures/extended/cli_commands/help_smoke.lani \
  < tests/fixtures/stdlib_compiler_state/cli_help_nested_error/restore_nested_assertions.patch
sha256sum target/stdlib-work/cli-help-reconstructed-original.lani
```

## Confirmed standalone pair

Both sources import only `core::result`, declare a local two-variant `Error`,
and assert the same two exact payloads. They import no CLI, command, help or
other production extension module and acquire no host resources.

- `nested_error.lani` uses the original nested `Result`/error patterns. SHA-256:
  `004dbce14b66274c505696a1dd22a41381157461159b60393612b1f8f4dee13c`.
- `typed_error.lani` changes only the two assertion spellings to the explicit
  typed-extraction control. SHA-256:
  `957a144131d96b34544cb90c0344aa5d097c17b544a678ab25352b664ada6459`.

Root ran the pair with the frozen compiler CLI whose reported SHA-256 prefix is
`e8ad`. The receipts under `target/stdlib-work/` are:

| Source/action | Result | Log |
| --- | --- | --- |
| `nested_error.lani` compilation | Exit 1, generic `LNC0057`, no ELF/native execution | `cli-help-nested-error-repro-first.log` |
| `typed_error.lani` compilation | Exit zero | `cli-help-typed-error-control-first.log` |
| Same typed control, native execution | Exit zero; both exact payload assertions pass | `cli-help-typed-error-control-native-first.log` |

The accepted typed-control ELF SHA-256 is
`e9012add7d26fbccf6cc60ccf94393842fe732e91d663c636864eea689643752`.
The minimal failure does not require the CLI/help implementation, routing,
metadata, output buffers or host services. Its generic diagnostic still does
not identify the compiler pass or internal cause. These two variants and two
assertions do not establish failure for other nested patterns or all generic
matches; the control does not establish arbitrary Result composition.

Reproduce from the repository root with these separately bounded commands.
Root serializes the separately bounded compile and native commands:

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --stdlib-root stdlib \
  tests/fixtures/stdlib_compiler_state/cli_help_nested_error/nested_error.lani \
  -o target/stdlib-work/cli-help-nested-error

timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --stdlib-root stdlib \
  tests/fixtures/stdlib_compiler_state/cli_help_nested_error/typed_error.lani \
  -o target/stdlib-work/cli-help-typed-error

timeout --kill-after=2s 2s target/stdlib-work/cli-help-typed-error
```

The nested source is expected to reject before an executable is produced.
The original complete consumer and reverse patch remain preserved alongside
the confirmed pair. The fixture author performed only source/static work;
the compile and native results above are root's receipts.

The earlier [HTTPS nested enum-pattern reduction](../../extended/https_batch/compiler_admission/README.md)
is related context, with a different `LNC0006` diagnostic. These observations do
not establish that both failures have the same compiler cause. The accepted
consumer targets Linux x86_64 CPU execution emitted by the GPU compiler; it
does not establish user-program GPU execution or another host target.
