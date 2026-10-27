# Native-provider probe match composition

Status: both preserved complete probes reject with `LNC0005` at the wildcard
arm expression. Both small controls below compile and execute; they do not
reproduce the failure and do not support a general None/wildcard limitation.
Hoisting a typed absent Option is not a confirmed fix. The responsible
expression, source interaction and compiler pass remain unidentified. No
compiler, library or active-probe implementation is changed by this folder.

## Preserved complete probe

`original_probe.lani` is the exact source rejected with `LNC0005` at line 101,
column 65, identifying `None()` in this typed match's wildcard arm:

```lani
let native:Option<ext::cli_response_files::Error> =match(failure.cause) {
    ext::cli_response::Cause::Provider(error)->Some(error), _ ->None()
};
```

The source already explicitly imports `core::option::Option`, `Some` and
`None`. `compile_original.log` preserves the actual diagnostic from
`target/stdlib-work/response-files-probe-compile-item-imports.log`. The gate
stopped before native cases; this is not a native file-provider failure.

| Artifact | SHA-256 |
| --- | --- |
| `original_probe.lani` | `604966b2ec0ef69f77868aba99e6c1a33a49a7a291be08618a8a3564ae554a19` |
| `compile_original.log` | `e8450e2d1325692aa94dd2dac88f71b4306851d9d914f3eef6e02550b0a68f02` |
| Preserved `typed_probe.lani` spelling | `7dc24dd769126aa0db76ae2525ef66a6370faaf21e029aca21b8111b08e5fc17` |
| `restore_none_arm.patch` | `1b55adc60f2476c05326894bb057bbf97df8ffd638025efbc2c39beae0f98e5e` |

`typed_probe.lani` adds a typed absent Option before the match and returns that
local in the wildcard arm. The reverse patch targets this preserved snapshot,
records exactly the source difference between these two failed probes, and
restores the original. Later changes to the active native fixture do not belong
to this expression pair.

Root separately compiled the preserved files at their new paths. Both failed
before producing an executable or running native cases:

| Source | Result | Log in `target/stdlib-work/` |
| --- | --- | --- |
| `original_probe.lani` | `LNC0005` at line 101, column 65, `None()` | `response-none-original-probe-compile-first.log` |
| `typed_probe.lani` | Same `LNC0005` at line 102, column 65, local `absent` | `response-none-typed-probe-compile-first.log` |

Both expressions are reported as unresolved identifiers despite their visible
item import or typed local declaration. This confirms the complete probe
composition remains rejected after the local spelling change and after
moving the entry source. It does not isolate a defect in `None`, infer a
general match limitation or establish that this expression alone is responsible.

## Working active consumer

The [active native-provider fixture](../../extended/cli_response/files_probe.lani),
SHA-256 `f8a564cb2152291f870e1fa8718227769d0591f3ecdadaf26285826b8e1ccd36`,
now consolidates the two `failure.cause` matches into one: its Provider arm
calls a report helper and returns the existing cause code. Metadata,
assertions and the reporting protocol are retained. Root compiled it
successfully in `response-files-probe-compile-single-match.log`, then passed
the [direct provider group](../../extended/cli_response/files_README.md#real-provider-cases)
with 39 process invocations in `response-files-provider-native-first.log`.
That count includes calibration and repeated setup, not 39 independent
properties. Both logs are under `target/stdlib-work/`; the accepted ELF SHA-256
is `81b3998977e5231132424f54f47a2d1509c78deeba28dc18fa23fcb6bc309d25`.
The production modules are unchanged. This broader consumer rewrite is not an
isolated expression fix and does not identify the compiler cause. Its current
source remains at the active path; no duplicate working copy is stored here.

## Successful small controls

Both sources import only the three `core::option` items above, define local
`Value { Payload(i32), Other }`, and use a typed `Option<i32>` match result.
The same two assertions require `Other` to produce None and `Payload(17)` to
preserve exactly 17.

- `none_arm.lani` returns `None()` directly from the wildcard arm. SHA-256:
  `abc6f0f602b1dcb12e964ab79f818f20a07c999fa0ce074d3adacdac5d84c161`.
- `typed_none_control.lani` introduces `let absent: Option<i32> = None();`
  before the match and returns `absent` from the wildcard arm. SHA-256:
  `12ac496bc04f780b4205515fdd660f6a9e74434afd847124dc450987e7381848`.

The author statically verified that reversing those two source changes makes
the control byte-identical to the direct-arm source. Neither source imports
CLI/response modules or touches a host service.

Root compiled and executed both successfully. Each native process exited zero,
checking both the absent and exact present-17 result. Receipts are in
`target/stdlib-work/`:

| Source | Compilation log | Native log | ELF SHA-256 |
| --- | --- | --- | --- |
| `none_arm.lani` | `response-none-arm-compile-first.log` | `response-none-arm-native-first.log` | `5e7078f015bbda119b41982725149f4b7d49be232a8b4172b5be4b2517449fa0` |
| `typed_none_control.lani` | `response-typed-none-control-compile-first.log` | `response-typed-none-control-native-first.log` | `372c6638d155c757694514c0aba03aea81a6f77ab122728551702d63c681be6d` |

Root serializes each compiler command separately:

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --stdlib-root stdlib \
  tests/fixtures/stdlib_compiler_state/response_none_match/none_arm.lani \
  -o target/stdlib-work/response-none-match-arm

timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --stdlib-root stdlib \
  tests/fixtures/stdlib_compiler_state/response_none_match/typed_none_control.lani \
  -o target/stdlib-work/response-typed-none-control
```

Root ran the two native controls separately under their bounded deadlines.
The author ran no compiler/native gates.
The successful small controls leave the complete probe as the observed
composition; they do not establish its responsible expression or compiler
pass. The full sources are test-only consumers; no public library API is
disabled or changed by this capture. No additional compiler isolation or
implementation repair is claimed.
