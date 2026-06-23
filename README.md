# The Lanius Programming Language

Lanius is a systems programming language that compiles on the GPU. That is, it compiles on the GPU and targets the CPU.

## Lanius Values

### 1) Iteration speed
Lanius is designed around GPU-resident compilation for fast iteration. The
current compiler is still early alpha; published benchmark claims need checked
local evidence before they should be treated as production numbers.

### 2) Embedadbility
Lanius is intended to be embeddable, including future web/Wasm-style hosts, but
the current production backend work is focused on native x86_64.

### 3) Honesty
Lanius is explicit, but more than that Lanius is honest. Lanius code does what it says it does. There is no operator overloading, all usages of typeclasses are explicit. Nothing is "auto-wired" or otherwise transforms the control flow graph in a way that you could not expect.

## Lanius Anti-values

### 1) Compiling to all possible targets
Lanius will likely never compile to your favorite microcontroller directly. This is due to purposefully not using LLVM so that we can have fast compile times.

### 2) Turing complete type systems
Dependent types and other Turing complete type systems are mutually exclusive with writing the fastest possible compiler.

### 3) Producing the simplest possible language
Simplicity is a term that is not well understood by developers. I.e. C is "simple", but the Zen of Python says Python is also "simple". But they are clearly not simple in the same way!

### 4) Approachability for beginners
Lanius is not looking to be understood by beginners, although it may end up being that way regardless.

### 5) Maximizing performance to the detriment of developer UX
Performance is essential, but Lanius is not looking to be the fastest possible language.

## Stability

Lanius is in an extremely early alpha. I would not recommend using it for any purpose.

`laniusc --version` outputs the compiler version.
`laniusc doctor` will output a JSON report whether laniusc can run or not.
There are only two targets, `x86_64` and `wasm`. `x86_64` is the default.
Those correspond to `x86_64-unknown-linux-gnu` and `wasm32-unknown-unknown`.

You can control the diagnostics output using `--diagnostic-format=<json|lsp-json>`
`laniusc lsp serve --stdio` starts an LSP server (work in progress).
`laniusc fmt [--check] <file> [<file> ...]` runs a formatter on the given files, and edits them. `--check` only checks without editing the file.
`laniusc check` runs frontend checks like lexing, parsing, and typechecking, but it doesn't validate whether the backend accepts that code yet.

## Benchmarks

The goal is a checked-in 5k/10k/20k benchmark before we make any compilation or runtime speed claims.

## Future

Lanius is looking to add capabilities, algebraic effects, graded modal types, tree borrows, mixin modules, row/rank polymorphism, first class property testing, compilation to x86, ARM, and RISC-V, polyhedral compilation, formally verified semantics, and more in the future.
