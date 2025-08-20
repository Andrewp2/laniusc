# NOTE

I'm putting this project on-hold until I can figure out why it should exist. Compilers, even heavy compilers like gcc and rustc, are not too slow except when compiling many times to many different targets. Iterative builds take care of most of the issues of needing a fast compiler. Once you get below ~2 seconds, it starts being unclear if improving the compile time is actually valuable. Furthermore, many of the algorithms that one might want to spend compile time on are not GPU-friendly.

# The Lanius Programming Language

Lanius is a programming language that compiles "faster than light". It accomplishes this by performing all compilation tasks on the GPU: Lexing, parsing, typechecking, and code generation.

## Lanius Values

### 1) Iteration speed
Lanius compiles on the GPU, up to ten times faster than other languages.

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

Lanius is in an early alpha. Expect bugs, glitches, and nasal demons.

## Benchmarks

TBA

## Future

Lanius is looking to add capabilities, algebraic effects, graded modal types, tree borrows, mixin modules, row/rank polymorphism, first class property testing, compilation to x86, ARM, and RISC-V, polyhedral compilation, and more in the future.