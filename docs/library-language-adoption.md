# Library adoption of language ergonomics

The `codex/stdlib` branch was rebased onto `origin/lang`
`0d2e4a07aa5b0f0dda6a2bcbd0d1c9d3de4a0eca`. Six library modules and the
[range-dot program](stdlib-range-dot.md) now use item imports, initializer type
inference and direct propagation where executable checks support it. This is
an initial cleanup, not a rewrite of every module or completion of the library
goal. The root README remains human-maintained.

## Source contract

The syntax is `import core::result::Result;`; constructors such as `Ok` and
`Err` are imported separately. See [language ergonomics](language-ergonomics.md)
and the [library conventions](library-api-conventions.md#imports-inference-and-propagation).

| Module | Adopted features |
| --- | --- |
| `core::decimal` | Item imports, concrete locals and nine Result propagation sites; exact parse errors and widths retained |
| `core::decimal_number` | Item imports, concrete locals and two Result propagation sites; work/scratch/error precedence retained |
| `core::path` | Item imports, inferred borrowed values and four Option propagation sites; physical backing remains a caller precondition |
| `core::wide_u64_checked` | Item imports, concrete locals and checked-power propagation |
| `core::wide_i64_checked` | Item imports, concrete locals and checked-power propagation |
| `std::file_ops` | Item imports, concrete locals and 23 Result propagation sites; descriptor ownership, syscall order and error translation remain explicit |

All six public type/signature contracts are unchanged after expanding imports.
Numeric literal widths, raw storage sizes and necessary casts remain explicit.
`?` never substitutes for releasing an owner, preserving progress, or translating
an error type. Range-dot retains explicit argument-owner destruction while its
borrowed iterator chain uses bound-directed inference.

Package-lock discovery now applies the source loader's existing rule: prefer
the whole module, otherwise try the direct module prefix for an item import.
Locks retain the written import and the declaring module identity; distant
ancestors and inconsistent identities reject. This small source-pack integration
change adds no lock schema, compiler IR, ABI or proof change. The declaration
reference generator now links item imports to their owning module/declaration;
it remains documentation tooling rather than a semantic resolver.

## Executable evidence

All acceptance below used a freshly built compiler and the frozen production
sources at rebased HEAD `21764809` plus this migration. The target is **Linux
x86_64 ELF emitted by the GPU compiler**. These are native executable tests,
not execution of the library as GPU compute kernels. No new target or compiler
throughput claim follows.

Receipts live under `target/stdlib-work/`. Each command had an outer 100-second
deadline, with native oracle/process deadlines inside it. Compilation jobs ran
serially under `library-gpu.lock`.

| Gate | Passing scope | Receipt | Seconds |
| --- | --- | --- | --- |
| Decimal contracts | Formatting, both input representations, exact errors | `lang-decimal-contracts.log` | 4.91 |
| Decimal parser model | All ten width/sign profiles, boundary/random/padded values, malformed and overflow locations | `lang-decimal-parse-model.log` | 7.45 |
| Exact decimal numbers | Contracts, errors, views and exact work budgets without allocation/I/O | `lang-decimal-number-contracts.log` | 4.45 |
| Borrowed paths | Two groups: allocation/filesystem exclusion and independent component/name/prefix/normalization models | `lang-borrowed-paths.log` | 11.91 |
| Two-word unsigned checked arithmetic | Existing executable operations and power boundaries | `lang-wide-u64-checked.log` | 4.16 |
| Two-word signed checked arithmetic | Existing executable operations and power boundaries | `lang-wide-i64-checked.log` | 4.11 |
| File operations | Five groups: native identity/flags/large positions, exact syscall errors/close policy, preflight atomicity and independent statx oracle | `lang-file-operations.log` | 16.00 |
| Descriptor-relative primitives | 27 native oracle cases using the retained freshly compiled primitive/bounds ELFs | `lang-temp-primitives-oracle-retry.log` | No separate timing claim |
| Range-dot | All 67 unchanged application cases, including million-item selections, exact errors and cleanup faults | `lang-range-dot.log` | 7.22 |
| Package-lock CLI | Generate/reload/check item-import edges and reject tampered ancestor edges | `lang-package-item-cli.log` | 2.94 |
| Relocated source bundle | Selective bundle moved, original source deleted, fresh lock generated, real expression program compiled and run | `lang-item-bundle-relocation.log` | 8.34 |

Five focused package-metadata tests also pass in 0.02 seconds, including whole
module precedence, direct item edges, replay and tamper rejection
(`lang-package-metadata-tests.log`). The direct reference-generator runner passes
26 CPU tests in 3.078 seconds (`lang-reference-generator-tests-direct.log`). An
initial unittest invocation used an unsupported module path and failed to import
the generator; that launcher error is kept separately in
`lang-reference-generator-tests.log`.

The bounded reference writer and `--check` pass for 246 pages, 245 modules and
8,119 declaration markers. Six module pages change; the counts are unchanged.
These are inventory counts, not executable API counts.

### Allocation-oracle integration

The initial TempFile primitive Rust gate compiled both fixtures, then rejected
the executable before any native behavior check: its exact allocation-runtime
pattern still required `MAP_32BIT` (`lang-temp-primitives.log`). Upstream now
emits `MAP_PRIVATE|MAP_ANONYMOUS` rather than adding `MAP_32BIT`.

The harness admits the two exact helper profiles, retaining executable ELF
bounds, instruction checks and a separate flags authority for each verified
syscall address. The TempFile mapping ledger checks full-width pointers and
original requested sizes at those addresses, rejects unverified source sites,
and requires matching release. Synthetic high-address/foreign-site/flag/size
mutations are CPU controls, not native allocation claims.

The changed emitter is
[`runtime_abi.slang`](../shaders/codegen/lir/x86/runtime_abi.slang#L169).
CPU checks pass with 41 TempFile oracle controls, 34 scale-ledger controls and
two focused Atomic-profile rejection controls (both final and live checkpoint).
Their receipts were direct tool output, not saved logfiles. The first two
supported runners are:

```sh
timeout --kill-after=2s 100s python3 -B tests/fixtures/stdlib_execution/temp_file/oracle.py controls
timeout --kill-after=2s 100s python3 -B tests/fixtures/extended/server_concurrency/scale_controls.py
```

After that harness-only change, the direct primitive oracle passes 27 native
cases against the same `/tmp/laniusc_temp_file_primitives_lani_310372_0` and
`/tmp/laniusc_temp_file_bounds_lani_310372_2` ELFs. No fixture/product bytes or
compiler runtime changed for the retry. The Rust libtest was not rerun. Broader
TempFile owner/fault, AtomicFile and network receipts retain their historical
scope; the two older checkpoint ledgers explicitly reject a new full-width
profile until their accounting is migrated. A successful primitive retry does
not revalidate those suites.

### Remaining compiler dependencies

The attempted generic `Option.flatten` rewrite compiles but receives SIGSEGV.
Both minimal try/match pairs reproduce this with identical payload checks;
the match controls exit 0. Production `core::option` is unchanged. The
[reproduction guide](../tests/fixtures/stdlib_compiler_state/try_generic_flatten/README.md)
records exact sources, hashes, bounded commands and the larger parent control.
This cleanup does not absorb the compiler repair.

The later [reusable regex increment](library-regex-workspace-plan.md) uses item
imports and inferred locals, but ten proposed `?` expressions in the complete
module fail SSA-dominance validation. Equivalent explicit checks execute all
selected workspace and consumer gates. Six small reductions pass, so the
[retained module-level reproduction](../tests/fixtures/stdlib_compiler_state/regex_workspace_admission/README.md)
does not establish a general propagation or aggregate restriction. The working
question-mark sites in the six modules above retain their independent evidence.

### Frozen source hashes

| Source | SHA-256 |
| --- | --- |
| `stdlib/core/decimal.lani` | `96d524982a586b359df79ab0a86154a5e8a720125a18582a029ed40f46ff69f4` |
| `stdlib/core/decimal_number.lani` | `14ca62aec13924142bb3461ff53bc1c7028cb22a684f5851de09b69534288dc1` |
| `stdlib/core/path.lani` | `543d3090bfa5de92ad59f0e78343b777594eeb9600e0e69355882031052de860` |
| `stdlib/core/wide_i64_checked.lani` | `d4bc5f823625e312eb73a557e42d0d728305dbf1beca2930c87281427b508493` |
| `stdlib/core/wide_u64_checked.lani` | `2e0d5f78ccad3ccf61c283726dc0b0120ca424ef71f9291f89ce655c304feb4f` |
| `stdlib/std/file_ops.lani` | `4194308a8d731971335d8b94b664fb5935cd3303aec80ccfd888f34a01b7831a` |

The range-dot guide separately records its application/test/ELF hashes. The
[roadmap](library-roadmap.md) retains the broader uncompleted library scope.
