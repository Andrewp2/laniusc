# The Lanius Programming Language

Lanius is a systems programming language with a GPU-resident compiler and a formally verified compiler. Lanius's GPU compiler lexes, parses,
typechecks, and emits bytecode with massive parallelism on the GPU.

## Lanius Values

### 1) Compilation speed
Lanius has a GPU compiler for extremely fast iteration times. Lanius is 5 times faster in debug mode than other compilers, and anywhere from 10 to 1000 times faster in release mode.

### 2) Correctness
Lanius comes with a formally verified compiler which allows developers to move with confidence. (WIP) Lanius has both a comprehensive standard library and even larger extended standard library with formally verified properties. (WIP) This includes features like webservers, parsers for different file formats like XML and JSON, math libraries for games and scientific applications, CLI parsing, logging, and operations on media like image and audio codecs.

### 3) Performance
Lanius values compiled performance as well as iteration speeds. (WIP) Lanius uses the incredible computing power of the GPU to run advanced optimizers that no other language currently can. 

## Stability

Lanius is in an extremely early alpha. I would not recommend using it for any purpose.

`laniusc --version` outputs the compiler version.
`laniusc doctor` will output a JSON report whether laniusc can run or not.
There are only two targets currently, `x86_64` and `wasm`. `x86_64` is the default.
Those correspond to `x86_64-unknown-linux-gnu` and `wasm32-unknown-unknown`.

You can control the diagnostics output using `--diagnostic-format=<json|lsp-json>`
`laniusc lsp serve --stdio` starts an LSP server (work in progress).
`laniusc fmt [--check] <file> [<file> ...]` runs a formatter on the given files, and edits them. `--check` only checks without editing the file.
`laniusc check` runs frontend checks like lexing, parsing, and typechecking, but it doesn't validate whether the backend accepts that code yet.

## Standard library

[Standard and extended library overview](docs/library-overview.md)

## Benchmarks

TODO

## Performance viewer

```bash
python3 tools/lanius_perf.py serve
```

## Future

Besides the things listed "WIP" in the values, Lanius is looking to add support for targets like ARM, RISC-V, and even SPIR-V and Verilog.
