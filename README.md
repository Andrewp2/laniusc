# The Lanius Programming Language

Lanius is a programming language being built around GPU-resident compilation:
lexing, parsing, typechecking, and code generation are intended to run as GPU
record pipelines. The current compiler is an early alpha, so bounded local
evidence matters more than the project slogan.

## Lanius Values

### 1) Iteration speed
Lanius is designed around GPU-resident compilation for fast iteration. The
current compiler is still early alpha; published benchmark claims need checked
local evidence before they should be treated as production numbers.

### 2) Embedadbility
Lanius is great for embedding into other projects, like a game compiled to WASM.

### 3) Honesty
Lanius is explicit, but more than that Lanius is honest. Lanius code does what it says it does. There is no operator overloading, all usages of typeclasses are explicit. Nothing is "auto-wired" or otherwise transforms the control flow graph in a way that you could not expect.

## Lanius Anti-values

### 1) Compiling to all possible targets
Lanius will likely never compile to your favorite microcontroller directly. This is due to purposefully not using LLVM to obtain fast compile times.

### 2) Turing complete type systems
Dependent types and other Turing complete type systems are mutually exclusive with writing the fastest possible compiler.

### 3) Producing the simplest possible language
Simplicity is a term that is not well understood by developers. I.e. C is "simple", but the Zen of Python says Python is also "simple". But they are clearly not simple in the same way!

### 4) Approachability for beginners
Lanius is not looking to be understood by beginners, although it may end up being that way regardless.

### 5) Maximizing performance to the detriment of developer UX
Performance is essential, but Lanius is not looking to be the fastest possible language.

## Stability

Lanius is in an early alpha. The only documented language edition accepted by
the compiler today is `unstable-alpha`; it is not a stable compatibility
promise yet. The policy is documented in `docs/LANGUAGE_SLICE.md`. Run
`laniusc --version` to see the compiler version, edition policy, supported emit
targets, target triples, formatter contract, LSP schema versions, Slang compiler
version, `wgpu` version, build profile, and shader artifact digest for the local
binary.
Run `laniusc doctor` for a no-run JSON toolchain report that checks whether
`slangc` is available on `PATH` and reports the same edition/target/build
metadata without compiling source or creating a GPU device.

The current emit targets are `wasm` and `x86_64`. The `x86_64` path supports a
bounded alpha slice: GPU HIR `main` returns, resolver-backed constants, direct
calls inside the current packed ABI width, selected scalar control flow,
bounded array/aggregate cases, and focused source-pack helper cases. Small
qualified-const arithmetic such as
`return core::numbers::LIMIT + core::numbers::STEP;` is covered; broad
source-pack expression graphs, runtime calls, general ABI support, and full
native linking are still outside the native backend slice. Unsupported source
shapes are expected to fail closed through compiler status instead of silently
falling back to another backend.

The accepted target triples are `wasm32-unknown-unknown` for `--emit wasm` and
`x86_64-unknown-linux-gnu` for `--emit x86_64`. Passing `--target` is optional,
but unsupported triples or triples that do not match `--emit` are rejected
before source loading.

Compiler diagnostics render as text by default. Passing
`--diagnostic-format=json` emits structured JSON for stable compiler
diagnostics, including payload schema version, registry schema version, and the
registry-backed primary-label policy for the diagnostic code.
`--diagnostic-format=lsp-json` emits one LSP Diagnostic-shaped object for stable
diagnostics, with a versioned Lanius `data` extension for registry-backed
metadata, and `laniusc lsp serve --stdio` provides the current minimal JSON-RPC
surface for editor experiments. Initialize/shutdown
requests do not compile source or create a GPU device; document changes are
full-document only, with ranged incremental changes rejected as invalid
parameters. Opened-document formatting requests return full-document edits from
the alpha lexical formatter without compiling source or creating a GPU device,
and opened-document diagnostic requests run the bounded GPU diagnostic path
without target codegen.
`laniusc fmt file.lani more.lani` rewrites one or more source files in place
with the same lexical formatter, and `laniusc fmt --check file.lani more.lani`
is the no-write form for hooks and CI.
`laniusc check` runs the same bounded GPU compile path for diagnostics but exits
without writing target bytes, so tools can validate a file without decoding
Wasm or native output from stdout.

## Local Build Setup

Builds require a Rust toolchain with 2024 edition support and the Slang compiler
available as `slangc`. `build.rs` locates Slang from `$SLANGC` first and then
from `PATH`; if the Slang runtime library is not on the platform loader path,
set `LD_LIBRARY_PATH` or the platform equivalent for your installation.
After building, `laniusc doctor` is the lightweight install check. It reports
toolchain metadata and missing local prerequisites as JSON, and it does not run
Pareas, generated workloads, or GPU compilation.

The checked-in Cargo config intentionally avoids workstation-local Slang paths
or linker rpaths. Local installations should use shell environment, a wrapper
script, or untracked per-machine config rather than committing absolute tool
paths.

## Standard Library

An initial source-level standard library lives in `stdlib/`. For the current
small source-pack path, `--source-root src` can load user module-path imports
and `--stdlib-root stdlib` can load stdlib module-path imports such as
`import core::i32;` into the source pack before GPU type-checking. A minimal
package manifest can be compiled with `--package-manifest`, locked with
`laniusc package lock --manifest lanius.package.json -o lanius.lock.json`, and
compiled later with `--package-lockfile`. Package names and paths are
control-plane loading metadata only; semantic module identity still comes from
GPU-parsed module/import records. This is not a full package system yet:
quoted imports are unsupported and rejected before lockfile write, broad
package discovery is incomplete, and most runtime-backed stdlib APIs are
contract-only rather than executable host APIs.

## Benchmarks

TBA. The production-readiness target is a checked-in 5k/10k/20k benchmark and
VRAM/readback report before making public speed claims.

## Future

Lanius is looking to add capabilities, algebraic effects, graded modal types, tree borrows, mixin modules, row/rank polymorphism, first class property testing, compilation to x86, ARM, and RISC-V, polyhedral compilation, and more in the future.
