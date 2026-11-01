# Trusted base of the verified compiler

Roadmap steps 14 and F13. This file lists every assumption the top theorems
rest on and do not prove, each as a specification: what is assumed, not how
the code is built. Evidence for the assumptions (tests against the CPU, the
difftests) is in section 9, and what is not trusted is in section 10.

Gate step `trusted` (`formal/tools/trusted_check.py`, quick tier) runs
`lake exe topAxioms` (`Lanius/Tools/TopAxioms.lean`) on the built modules
and fails
- when a top theorem depends on an axiom other than `propext`,
  `Classical.choice` and `Quot.sound` (section 1);
- when a top theorem's statement hash is not the one beside its entry below,
  or a theorem is listed here and not in `TopAxioms.lean`'s `tops`, or the
  other way round;
- when the hash of the trusted definitions is not the one given below
  (`definitions`);
- when the modules are not built from the current sources.

So a statement, or a definition it means, cannot change without this file
changing. The hashes are the kernel's structural hash of each statement
(`Expr.hash`, 32 bits, printed as 16 hex digits). When one changes, update the
entry (what the theorem says and assumes) and then the hash.

## Top theorems

Each entry: the theorem, its file, its statement hash, and what it says,
with its premises. The sections named are the ones it rests on. "The
caller's obligations" are the premises on the x86 state at entry (section
8): the image loaded at some base apart from the stack window and the heap,
`rip` at the function's entry, the arguments' slots below the return
address, `HeapAt` and `StackAt`. Every theorem's run is a run of the x86
model (section 6) and every Core run is Core's evaluator (section 3).

The trusted definitions: every constant of the project that these
statements reach, through types, definition bodies and constructors,
stopping at the computations the theorems are about (`compileSource`,
`compileText`, `compileProgram`, `compileOptimized`, `compileModules`,
`linkObjects`, `elfFile`, `sourceProgramFiles`, `compileWords`,
`frontEndWords` and the self program `Lanius.Faithful.Self.prog`, which are
not trusted, section 10), with each one's type and body:
definitions `0c187d1f00ec73fe` (4,230 constants). This covers Core's
semantics, the x86 model, the reading of source text, the Linux model and
the statements' own definitions (section 2). `trusted_check.py` writes each
constant's own hash to its work directory's `definitions.txt`, to find which
one changed.

### Processes (`Lanius/Mini/Process.lean`)

#### `Lanius.Mini.process_exits`

statement `000000006f650e63`. If `compileSource sp = some binary`,
`elfFile binary entry stack heap = some file`, and function `entry` of `sp`
has no parameters: whenever Core runs `entry()` from `startState given` to
a value `v` with the heap ending within `heap` bytes, then Core's final
standard output and error are what a write trace puts on fds 1 and 2
(`outputOf`), and from every state Linux may leave for `file` (`Loaded`)
whose streams are `given` (standard input, the clocks' readings and the
secure bytes, `s.io = given`), either some run reaches `exit`
(`Exits`) with that trace and the last of `v`'s slots as the status, every
run of that length agreeing but for flags (`Det`), or the stack is too
small for the call's depth and the process faults. Rests on sections 3, 6,
7 and 8 (Linux: `Loaded`, `Exits`, the kernel calls).

#### `Lanius.Mini.process_behaviour`

statement `0000000025d83224`. Same premises, for any run from a `Loaded`
state to a state with no step that is not a fault: Core's run of `entry()`
finishes within the heap and the run is at `exit` with the last result
slot, or Core's run reaches an undefined trap (`undefinedTrap`) within the
heap. Rests on the same sections.

#### `Lanius.Mini.textProcess_exits`

statement `00000000c0c13d4b`. `process_exits` from source text: if
`compileText files = some binary` and `elfFile` gives `file`, the files'
texts have a reading `sp` (`TextReading`, section 4), the only one, and
`process_exits`'s conclusion holds of `sp`. Adds section 4.

#### `Lanius.Mini.textProcess_behaviour`

statement `000000002cdd1cd1`. `process_behaviour` from source text, as
`textProcess_exits` is `process_exits`.

### Source text (`Lanius/Mini/TextCorrect.lean`)

#### `Lanius.Mini.compileText_correct`

statement `0000000023824272`. If `compileText files = some binary`, the
files' texts have exactly one reading `sp`, and `compileSource_correct`'s
conclusion holds of `sp` and `binary`, from the start state of the mini
heap's streams (standard input, the clocks' readings, the secure bytes). Rests on sections 3, 4, 6 and 8.

#### `Lanius.Mini.compileText_behaviour`

statement `000000003d3267c8`. If `compileText files = some binary`, the
texts have one reading `sp`, and `compileSource_behaviour`'s conclusion
holds of it.

#### `Lanius.Mini.textReading_unique`

statement `00000000d7c363fc`. Two readings of the same texts are equal.
Rests on section 4 only.

### Source programs (`Lanius/Mini/SourceCorrect.lean`, `SourceStops.lean`, `Determinism.lean`, `TypeSound.lean`)

#### `Lanius.Mini.compileSource_correct`

statement `000000009c74f811`. If `compileSource sp = some binary`, `f` is a
function of `sp`, and `args` are values of its parameter types held in
slots `bits` (`FieldsHold`), and Core runs `f(args)` from the start state
(`startState` of the heap's streams: standard input, the clocks' readings
and the secure bytes) to `v` with the heap ending within the limit: there are a
depth and result slots representing `v` (`HoldsAt`), with Core's final
standard output and error those of the mini heap's trace, such that from
every x86 state meeting the caller's obligations, with a stack window of at
least `binary.stackNeed depth` (and at most 2^62), a fresh heap (cursor 1,
zero bytes, limit below 2^62, an empty trace), some run returns those slots
(`Returned`), and every run of that length agrees with it but for flags.
Rests on sections 3, 6 and 8.

#### `Lanius.Mini.compileSource_correct_from`

statement `00000000e3b16b55`. The same from any Core state `st` with no
live cells (`State.Fresh`) whose heap and world the mini heap represents
(`HeapCorr`); the final heap and world are again represented.

#### `Lanius.Mini.compileSource_stops`

statement `000000006f45523e`. Same premises on the compiler and the
arguments, a fresh heap of limit at least 1 and the caller's obligations
(any window up to 2^62): if every fuel of Core's run of `f(args)` fails
(`Failing`: runs out, traps with a defined trap, or ends past the heap
limit), then every run of the code that stops, stops at a fault (`Faults`).

#### `Lanius.Mini.compileSource_behaviour`

statement `0000000066f9c1d3`. Same premises: a run to a state with no step
that is not a fault comes from a Core run of `f(args)` that finished within
the heap limit, or reached an undefined trap within it.

#### `Lanius.Mini.compileSource_deterministic`

statement `000000009882455b`. `compileSource_correct` (without the output
conjuncts) with: every run of the same length ends `DataEq` to the
returning one (registers, `rip` and memory equal; section 7).

#### `Lanius.Mini.compileSource_wellTyped`

statement `000000001f1f2c4c`. If `compileSource sp = some binary`, then
`sp.toCore` is well typed (`Typing.ProgramWellTyped`, Core's type system).
Rests on section 3.

### Mini IR programs (`Lanius/Mini/Correct.lean`, `StopsCorrect.lean`, `Validate.lean`, `Determinism.lean`)

#### `Lanius.Mini.compileProgram_correct`

statement `00000000bbd77b6e`. If `compileProgram prog = some binary` and
the mini big-step semantics returns `value` and heap `after` for `f(args)`
at a depth (`Program.Returns`), then from every state meeting the caller's
obligations with a window of at least `binary.stackNeed depth`, some run
returns `value` (`Returned`), deterministically (`Det`). Rests on the mini
semantics (section 2), sections 6 and 8.

#### `Lanius.Mini.compileProgram_stops`

statement `0000000047f291ee`. If for every `n` the mini run of `f(args)` is
still running after `n` ticks or stopped at a checked fault
(`Program.Stops`), every run of the code that stops, stops at a fault.

#### `Lanius.Mini.compileOptimized_correct`

statement `000000007e57d6d7`. `compileProgram_correct` for
`compileOptimized`, whose optimizer's output is kept only when the
validator accepts it.

#### `Lanius.Mini.compileProgram_deterministic`

statement `0000000041d7b047`. `compileProgram_correct` with every run of
the same length `DataEq` to the returning one.

### Linking (`Lanius/Mini/Link.lean`)

#### `Lanius.Mini.link_eq`

statement `000000007181c690`. Compiling modules one at a time and linking
the objects (`compileModules`, `linkObjects`) gives the executable part
(`Binary.executable`) of compiling the linked program
(`linkProgram`, `compileProgram`).

#### `Lanius.Mini.linked_correct`

statement `00000000960e6c54`. `compileProgram_correct` for an executable
from `compileModules` and `linkObjects`, with the program `linkProgram ms`.

#### `Lanius.Mini.linked_deterministic`

statement `00000000a7365b5d`. `linked_correct` with every run of the same
length `DataEq` to the returning one.

### The self program (`Lanius/Faithful/SelfDriver.lean`, `SafeDriver.lean`)

`prog` is the self program, `Lanius.Faithful.Self.prog`: the front end's
reading of the driver and the verified compiler's sources (section 5).
Function 0 is the driver `w(input, words, output, room)`.

#### `Lanius.Faithful.SelfDriver.driver_faithful`

statement `00000000cc70d93c`. If Core runs `w` from a state satisfying the
invariant `Inv` (no live `i32` array views, block bases unique), with an
input view reading words `W` (`Reads`), fewer than 2^31 of them and of
output room, `room * 4` readable bytes at the output, and ends within 2^64
bytes of heap: it returns -1 when `compileWords (frontEndWords grammar W)`
is `none`, and otherwise the result's length, with the output view reading
the result (`Result`). Rests on section 3.

#### `Lanius.Faithful.SelfDriver.driver_files`

statement `00000000faae0dee`. `driver_faithful` for the words of source
files (`filesWords`, each file's bytes, productions and parents, within
`FilesFit`'s bounds): the result is `binaryWords (compileText files)`.
Rests on sections 3 and 4 (`compileText`'s meaning, through
`compileText_correct`).

#### `Lanius.Faithful.SelfDriver.driver_safe`

statement `00000000370c8fc9`. Under `driver_faithful`'s premises on the
state and views, with the input and output ranges checked in Core's heap,
Core's run of `w` never reaches an undefined trap, at any fuel (`SafeE`).

### The self-built verified compiler (`Lanius/Faithful/SelfCompiler.lean`, `SelfHost.lean`)

#### `Lanius.Faithful.SelfCompiler.selfCompiler_outcome`

statement `00000000141f9894`. If `compileSource prog = some B` (section 5):
for files within `FilesFit`, fewer than 2^31 words and output room, a heap
laid out as `selfHeap` (the words, then the output room, then the bump
heap up to a limit at least `selfNext` and below 2^62), argument slots
`selfBits`, and the caller's obligations for `B` with entry 0, the run
faults, or some run returns, deterministically, with rax's low 32 bits -1
when `compileText files` is `none` and otherwise the number of words of its
binary, which are in the output view (`SelfOutput`). Rests on sections 3,
4, 5, 6 and 8.

#### `Lanius.Faithful.SelfHost.selfHost_fixpoint`

statement `00000000c83c8720`. For source files `self` that the front end
reads as `prog` (`read : sourceProgramFiles self = some prog`) and `B` with
`compileText self = some B` (`compiled`), both computed (section 5): `prog`
is the files' one reading (`TextReading`), and `B`'s code for `w`, entered
as in `selfCompiler_outcome` with the words of `self`, faults or returns
`B`'s own words: the verified compiler compiles its own text to itself.
Rests on sections 3, 4, 5, 6 and 8.

#### `Lanius.Faithful.SelfHost.selfHost_outcome`

statement `00000000ca89d21d`. `selfCompiler_outcome` for any files, with
`read` and `compiled` in place of `compileSource prog = some B`.

## 1. Lean

- **What.** The Lean 4 kernel (toolchain `leanprover/lean4:v4.33.1`, pinned
  in `lean-toolchain`; the project has no package dependencies) and three
  axioms, `propext`, `Classical.choice` and `Quot.sound`. Every top theorem
  depends on exactly these (`link_eq` on `propext` and `Quot.sound`), as
  `#print axioms` gives; gate step `trusted` prints them. There is no
  `sorryAx` and no `Lean.ofReduceBool`, so nothing relies on
  `native_decide`, `bv_decide` or compiled code. Elaboration and tactics
  are not trusted, because the kernel rechecks every term they produce.
  Modules hide definition bodies from each other (the module system); that
  changes what the elaborator may unfold, not what the kernel checks.

## 2. The statements' definitions

A theorem only means what its definitions say. These definitions are part of
the statements, so a reader has to agree that each one says what is intended:

| definition | file | says |
|---|---|---|
| `SrcProgram.toCore` and the `toCore` of each construct | `Mini/Source.lean` | which Core program a source program *is*: each construct is the Core construct of the same name (`Null` is Core's literal `.pointer 0`), and functions are numbered by position, then the host functions (`hostFuncs`, ids 2^32 up). A literal (`EStruct`, `LetStruct`) means `SrcType.literal`: Core's array value `.array T vs` at an array type `[T; N]`, and a struct value otherwise |
| `FieldsHold`, `SrcType.HoldsAt` | `Mini/Source.lean` | how a Core value sits in 64-bit slots: an `i32` is zero-extended, a `bool` is 1/0, a struct is its fields in order, an enum is a tag then its payload, a pointer is its address, an array `[T; N]` is its N elements in order, as a struct of N fields of type T, a float is its bits |
| `startState`, `State.Fresh`, `HeapCorr`, `outputOf` | `Mini/SourceCorrect.lean`, `Mini/HeapCorr.lean` | Core's start state for a standard input (empty heap, the world with that input); a state with no live cells; the mini heap representing Core's heap and world (standard output and error are `outputOf 1` and `outputOf 2` of the mini heap's trace, the bytes its writes put on fds 1 and 2, no open files, the same standard input) |
| `Returned`, `HeapAt`, `StackAt`, `Contract`, `Scratch`, `InHeap` | `Mini/Simulation.lean` | the calling convention and what "returns" means (section 8) |
| `Below`, `Binary.stackNeed`, `Binary.guard` | `Mini/Frame.lean`, `Mini/Bytes.lean` | the stack window |
| `Det`, `DataEq`, `Live`, `Faults`, `Fault` | `Mini/StepDet.lean`, `X86/Machine/Scalar.lean` | every run agrees but for flags and does not stop early; a run that stops, stops at an architectural fault (`ud2`, `#DE`) |
| `undefinedTrap`, `Failing` | `Mini/Fails.lean` | a Core run fails at a fuel when it runs out of fuel, stops at a trap that is not undefined, or completes with the heap past the mini heap's limit; the undefined traps are the raw memory errors and `typeMismatch` |
| `Program.Returns`, `Exec` | `Mini/Semantics.lean` | the mini IR's big-step semantics, at a call depth |
| `Stops`, `Program.Stops` | `Mini/Stops.lean`, `Mini/StopsCorrect.lean` | a mini run that, within `n` ticks (loop iterations and calls), has not finished or has stopped at an allocation past the limit from a cursor within it, or at a division by zero or of the least value by -1 |
| `Typing.ProgramWellTyped` | `Lanius/Typing.lean` | Core's type system on programs |
| `CodeAt`, `Steps`, `Step` | `X86/Machine/State.lean`, `X86/Machine/Scalar.lean` | the image is loaded, and the machine runs (section 6) |
| `Loaded`, `Exits` | `Mini/Process.lean` | what Linux does at `execve` and at `exit` (section 8) |
| `linkProgram`, `Stmt.rename`, `Binary.executable`, `Executable.stackNeed` | `Mini/Compiler.lean`, `Mini/Link.lean` | which mini program a list of modules *is* (their functions in link order, each callee renamed to its program index, imports checked for owner, function and arity), and what of a binary a linked executable keeps |
| `TextReading`, `SourceFile` | `Mini/TextCorrect.lean`, `Mini/FrontLex.lean`, `Mini/Reading/` | the reading of source text (section 4); a file is its bytes with laniusc's tree (production ids in preorder, each node's parent), and the theorems mention no tree |
| `filesWords`, `FilesFit` | `Mini/TextWords.lean` | the driver's input format: per file its byte count, bytes, production count, productions and parents, one 32-bit word each, after a file count; the bounds within which each count fits a word |
| `binaryWords`, `imageWords`, `packRounds` | `Mini/Compiler/P/packRound.lean` | the driver's output format: the entry count, the entries, the image's length in bytes, then its bytes four to a word, the first in the low byte, the last word padded with zeros |
| `Inv`, `Reads`, `Result`, `Readable` | `Faithful/Sim/State.lean`, `Faithful/SelfDriver.lean`, `Memory/Read.lean` | the Core state invariant (no live `i32` array views, block bases unique); an input view reading words; the driver's result (-1, or the length with the output view reading the words); readable bytes of Core's heap |
| `SafeE` | `Faithful/Safe/Run.lean` | no fuel of Core's run reaches an undefined trap |
| `SelfOutput`, `selfHeap`, `selfBits`, `selfNext` | `Faithful/SelfCompiler.lean` | what the self-built compiler's `w` returned in x86 memory; the heap layout and argument slots its caller sets up (the input words, then the output room, then the bump heap) |

The computations the theorems are about are not trusted (section 10):
whatever `compileSource`, `compileText`, `compileProgram`, the optimizer,
`compileModules`, `linkObjects`, `elfFile` and the front end's code compute,
the theorems say what it means.

## 3. Core semantics as the meaning of Lanius

- **What.** The theorems are stated against Core's fuel-indexed evaluator
  `Lanius.Semantics.evalExpr` (`Lanius/Semantics.lean`, `Lanius/Semantics/`),
  Core's heap (`Lanius/Memory.lean`, `Lanius/Memory/`; the allocator is
  unbounded and `nextAddress` starts at 1) and Core's world
  (`Lanius/World.lean`: standard input, output and error, files and clocks,
  with `World.call` the meaning of each host service, such as `write_byte`,
  `write_stdout`, `read_stdin` and `sleep_ms_i32`). It is assumed that these
  are what Lanius programs mean. No other formal semantics exists to compare
  them with, and laniusc, the GPU compiler, is not proved against them.
- **Coverage.** `compileSource_correct` is about Core runs that finish
  (`= .done v final`) within the heap; `compileSource_stops` and
  `compileSource_behaviour` about the others: when every fuel runs out or
  traps definedly, the code never returns, and a run that stops other than
  at a fault comes from a Core run that finished or reached an undefined
  trap (`undefinedTrap`). Programs outside the subset (`compileSource`
  returns `none`) are not covered. Core's allocator never fails; on x86 the
  heap limit is enforced (the bump allocator executes `ud2` past it), and
  the theorems assume that Core's run fits: `final.heap.nextAddress ≤
  heap.limit`.
- **Raw views.** `i32_slice_from_raw_parts` and the raw
  slices of structs and enums (`Heap.checkRange`) check that the range is
  nonempty, aligned, and inside one live block whose alignment is enough,
  and leave the heap as it was. A view may cover any aligned range inside a
  block (a prefix, a middle), and the block stays owned: `dealloc` after a view
  succeeds, and a read through the view after that traps
  (`invalidPointer`), so use-after-free still traps. Arrays and strings
  that the language itself lends (`mapBorrowed`) still make borrowed blocks.
  This is the meaning `Vec` needs: its buffer is one block and its
  elements are a view of a prefix of it.
- **Writes through references (F5).** Core's places gain
  `Place.deref reference` (`Lanius/Core.lean`): `evalPlace` evaluates the
  reference, and the place is its cell at its projection path, with the
  value there read (`readCellProjection`). An assignment to it, or to a
  field or element of it, writes the referenced cell, as an assignment to
  a local's field does. Core's type checker
  (`checkPlaceAnyFuel`) has no rule for it yet and rejects it.
- **Shift amounts.** A shift of a signed or unsigned
  integer may take an amount of another such type (`x << n` with `x: i64`,
  `n: u32`), as laniusc allows: typing `BinaryOpHasType.shiftLeftBy` and
  `shiftRightBy` (`ShiftTy` on both sides, the result the left operand's
  type), evaluation `Semantics.evalShiftBy`, which checks the amount's
  number against the left operand's width, as a shift by its own type does
  (`u8` by a `u32` amount of 256 traps).
- **Floats (F9).** Core's `f32` and `f64` values are their
  IEEE 754 binary32 and binary64 bit patterns (`.f32Bits`, `.f64Bits`), and
  every float operation is defined on exact integers in `Lanius/IEEE.lean`
  (234 lines; no Lean `Float` anywhere, so the kernel can evaluate and
  reason about it). The specification:
  - A finite pattern's value is `(-1)^s * significand * 2^unitExp`: a normal
    one has the hidden bit, a subnormal one the unit `2^(1 - bias - f)`.
  - `roundRatio` rounds an exact rational `num / den * 2^exp` to nearest,
    ties to even, with gradual underflow (no flush to zero) and overflow to
    infinity. `+ - * /` compute the exact result and round it once
    (`add`, `sub`, `mul`, `div`); an exact zero sum is `+0` unless both
    operands are `-0`; a zero product or quotient has the sign of the
    signs' xor.
  - NaN results follow x86 SSE: an operation with a NaN operand returns the
    first NaN operand with its quiet bit set (sign and payload kept); an
    invalid operation on non-NaNs (`inf - inf`, `0 * inf`, `0 / 0`,
    `inf / inf`) returns the default NaN (sign set, exponent all ones, only
    the quiet bit), and `x / 0` is a signed infinity.
  - `==`, `<`, `<=` are false when either operand is a NaN, and `-0 == +0`;
    `!=` is the negation of `==`, `>` and `>=` swap the operands.
  - Negation flips the sign bit, NaNs included (`neg`), as `xorps` does.
  - Integer to float (`ofInt`) rounds the exact integer; `f32 -> f64` is
    exact, `f64 -> f32` rounds; a NaN converts with its sign and the top bits
    of its payload, quieted (`convert`), as `cvtss2sd`/`cvtsd2ss` do.
  - Float to integer (`truncSat`, added: Core had no such cast) truncates
    toward zero and saturates to the target's range, NaN to 0, as Rust's
    and laniusc's `as` do.
  - A decimal literal `m * 10^e` is rounded once to the nearest pattern
    (`ofDecimal`, used by elaboration); past `10^400` it is infinity and
    below `10^-400` zero, only to avoid huge powers.
  This specification is also the meaning of the SSE instructions in the
  x86 model (section 6), under Linux's default MXCSR (section 6).
- **`slice_stride`.** `Intrinsic.sliceStride` gives a raw
  view's signed byte stride as an `isize` (`rawSliceStride?`): 4 for `i32`
  views, and `-8 × words` for views of structs and enums. On these views
  laniusc gives the same values. Core gives
  a view of a language array no stride (it traps), while laniusc gives that
  array's own layout. Programs that ask for one are outside the theorem.
- **Native layout.** Core reads and writes values in memory
  with laniusc's layout (`docs/wasm-memory-layout.md`). A value's address is
  its word 0, its highest word; word k is 8k bytes below it. A struct's field
  j has its word 0 at 8·W_j bytes below the struct's, W_j being the words of
  the fields before it. An enum's tag is word 0, and its payload starts one
  word below. Element i of a raw view of a w-word type is 8wi bytes below
  element 0. `str` is 2 words (data, then length) and a slice is 3 (data,
  length, stride). Each scalar is one word, so `u8`, `u16`, `u32`, `i8`,
  `i16`, `i64`, `u64` and `isize` have a native layout too. A raw field
  place `s[i].f` is the element's address less the field's offset, and it
  traps (`rawMemoryBounds`) when that would go below 0. One difference from
  laniusc remains. Core writes `i32`, `bool`,
  `i8`, `i16`, `u8`, `u16`, `u32` and enum tags as 4 bytes and the 64-bit
  kinds as 8, while laniusc writes every scalar as a whole 8-byte word,
  zero-extended. The 4-byte writes are needed because the same writer
  stores packed `i32` view elements, which are 4 bytes apart. Both read the
  32-bit kinds with 4-byte loads. So the two differ only in the upper half
  of such a word, which only an aliasing 8-byte read sees. Core traps when a
  4-byte `u8`, `u16`, `i8` or `i16` read is out of the type's range; laniusc
  does not mask.

## 4. Source text: the reading

The theorems from source text are stated with `TextReading`
(`Mini/TextCorrect.lean`): an inductive relation between the files' texts
and a `SrcProgram`, through the lexer and the grammar below. It is trusted
to give each text the program Lanius means by it.

Not trusted: laniusc's lexer and parser, and the parse trees they give.
`compileText` takes each file's bytes with laniusc's tree (`SourceFile`:
the production ids in preorder and each node's parent), but the theorems
mention no tree: they are about the one reading of the texts. A wrong tree
is rejected, or it is still the parse tree of the same tokens, which is
unique. Trusted:

- **The lexer.** `Lanius.Compiler.Lexer.lexCanonical`
  (`Lanius/Compiler/LexerCanonical.lean`) is the meaning of Lanius's lexical
  syntax. The self program's own lexer, `lex_source` in `frontend.lani`, is
  proved equal to it (`lexSource_eq`, `Mini/LexCorrect.lean`), so it is not
  trusted. `lexTokens` adds one keyword that `keywordRules` lacks: `as` is
  token code 195, as in laniusc. Token kinds are laniusc's codes
  (`TokenKind.gpuCode`). `requires` is a keyword (F10); `ensures` and the
  contextual `distinct` have no rule, so a file that uses them lexes them as
  identifiers and its tree is rejected.
- **The grammar.** The table `grammar` in `frontend.lani` is
  `grammar/lanius.bnf` as laniusc built its parse tables
  (`tables/parse_tables.meta.json`). Production `k` is entry `k`, a terminal
  is the token code of its lexer kind, and parser retags map back through
  `canonical_lexer_kind` (`crates/laniusc-compiler/src/lexer/tables/tokens.rs`).
  One mapping is added: `MatchArrow` becomes `Arrow`, because the lexer emits
  `->` in match arms as `Arrow`. `formal/tools/grammar_table.py` writes the
  table mechanically, and `--check` confirms that it is current. The grammar
  is trusted to say what Lanius's concrete syntax is, including precedence
  and associativity, which it encodes in its levels.
- **One reading (V4, proved).** The grammar is not unambiguous on the
  subset, as this file used to claim: `a < b > (c)` is both a comparison chain
  and a call of a generic path `a<b>`, and `f(a < b, c > (d))` likewise.
  `picks` (`frontend.lani`, checked by the validator at every node) is part of
  the syntax's definition: a path segment `x<...>` in an expression is read
  as type arguments exactly when `generic_path_at` holds of the tokens from
  `x` on (the matching `>`, counted outside brackets with `>>` closing two,
  comes before a bracket closes or a `;`, with no `||`, `==`, `!=`, `<=` or
  `>=` before it, and is followed by `(`, `::` or `{`), which is laniusc's
  rule without its 64-token limit; a statement that begins with `{` is a
  block statement (production 84), never an expression statement (85), as
  in Rust, since `{ a } - b;` has both trees; and a method's type arguments
  (production 298), which the subset does not use and which are ambiguous
  too (`x.f < a > (b)`), are not allowed.
  `grammar_unique` (`Mini/ParseUnique.lean`, standard axioms) proves that at
  most one parse tree for `file` is `Picked` for given tokens, from a
  certificate of first and follow sets (two token kinds deep, `>>` read
  either way) that the kernel checks (`grammarCert_ok`,
  `Mini/GrammarCert.lean`, written by `formal/tools/grammar_cert.py`), and
  `Cert.parse_unique` (`Mini/Unique.lean`). So `validate_unique`: the tree the
  validator accepts is the only one, and `sourceProgram_determined` and
  `sourceProgramFiles_determined`: the front end's program depends on the
  source text alone, not on the tree laniusc gives. What stays trusted is
  that `picks` says what the syntax means where it decides.
- **The reading.** `Reading roots sp` (`Mini/Reading/`, V8) is the meaning of
  the subset's concrete syntax, as `toCore` is the meaning of `SrcProgram`
  (section 2): an inductive relation on the files' parse trees, with lookups
  and choices said declaratively, and small total helpers of the builder
  (expected-type and literal-typing helpers such as `intAt`, `operandWant`,
  `knownExpr`, and the wide-literal check `wideLeftFuncs`) as its
  vocabulary. `buildFiles_sound` (standard axioms) proves that what `build`
  returns is a reading, so `build`'s code is no longer the specification.
  The builder's choices are ones the relation states exactly
  (SEMANTIC_DECISIONS.md, "The reading is one reading"), and the relation
  is deterministic (`reading_unique`, F1, `Mini/Reading/Det/`), so a text
  has at most one reading and the theorems are about it alone. The reading
  makes these choices:
  - each file is a module, named by its `module` item (the empty path
    without one); `m::x` names `x` of the module `m`, a bare `x` names `x`
    of the current module; `import m;` only adds m's variants to those a
    bare variant name may mean, and trait declarations, type aliases with
    a `where` clause and extern functions are skipped (a trait impl's
    methods are functions, and the impl itself is kept for the bounds,
    `Decls.impls`), except that an `extern
    "lanius_std" fn` named `write_byte`, `write_stdout` or `write_stderr`
    (`hostExtern`) is a function whose instance returns the call of that
    host service on its parameters, `ECall(2^32 + k, params)` (`ReadExtern`;
    Core's meaning of that id is the host function, section 2);
  - `type A<P..> = T;` is an alias: a type path that names no type
    parameter, primitive or declared type names the alias of that module,
    and means T read in the alias's module with its parameters standing for
    the arguments (a cycle runs out of fuel and rejects); a cast may name an
    alias of a scalar type;
  - generic declarations are monomorphized (`mono`): an instance is a
    declaration with its type arguments, and a function or type id is a
    position in the instance tables. The first file's functions without type
    parameters come first, in order; every other function instance follows
    in the order it is first called. Types: the first file's non-generic
    types in order, then each instance as the functions' types (parameters,
    result, then the body's lets) first need it. A program without generics
    keeps the numbering of the next two lines;
  - a function is its position among the functions;
  - a struct or enum is its position among the type declarations;
  - a call's type arguments are written, or inferred by matching the
    callee's result type with the type its value is stored at, then its
    parameter types with the argument types in order, each argument read at
    its parameter's type once all are bound; an integer literal argument
    binds nothing unless a parameter is left unbound, when it counts as
    `i32`; a conflict or an unbound parameter rejects;
  - `x.m(args)` (`x` any value) and `T::m(args)` (`T` a type parameter, or
    a primitive type as in `i32::hash(v)`) call
    the method `m` of the one `impl` whose type matches the receiver's type,
    with `self` (by value) the receiver;
  - a `match` has one arm per variant of its scrutinee's enum, in any order,
    and its arms are listed in variant order (only one runs, so their order
    has no effect);
  - (F11) a match expression with a nested arm (`Ok(Some(x))`) is read as
    nested matches (`MatchOrder`, `NestedOrder`, `Reading/Nested.lean`):
    variant V's arm is `V(b, .., h, ..) -> match (h) { p -> value, .. }`,
    the arms naming V in order matched on the first arm's first column j
    that is not a binder, every other column a binder spelled as the first
    arm's, a binder at j in the last arm read as `_` when its value spells
    no token as its name (`Mentions`), then the outer wildcard unless no
    value of V reaches it (an inner `_`, or `Covers`) and only when its
    value spells none of the first arm's other binders (`ColsQuiet`); h is
    the binder spelled `[0]`, which no source can spell. No arm's value is
    a block (`BlockValue`). A match statement's nested arms are read the
    same way (`StmtOrder`, arms may be blocks), the inner match read as a
    match statement on h (`ArmsStmtR.inner`), and so are a let's match's
    (`LetArmsR.inner`; a value arm's value is not that bare match node).
    SEMANTIC_DECISIONS "Nested patterns";
  - (F11b) a payload pattern binds a name only when no enum of the program
    has a variant so spelled (`BindersR`'s `NoVariant`): laniusc reads one
    that resolves to a variant as a check. SEMANTIC_DECISIONS "Payload
    names that are variants";
  - `x.f` is `Field` when `x` is a local, and otherwise the call of the
    projection `fn(v: T) -> F { return v.f; }` on `x`, an instance numbered
    like any other;
  - bounds and `where` clauses (F7) are checked on each function
    instance (`FnBound`, `Implements`, `Reading/Bounds.lean`; a method's
    impl's too): the type a bounded type parameter stands for must have an
    impl of the bound's trait at its arguments, an `impl<P..> Tr<..> for S`
    whose trait and type read as the bound's for some P.., with its own
    bounds holding there. A trait is the module and spelling its path
    resolves to (as a type path's) with its type arguments; there are no
    implicit impls. This decides which programs are read, not what a read
    program means. A struct, enum or alias with a `where` clause or a
    bounded type parameter is not read (`FreeParams`);
  - a type parameter that no field or payload uses (a phantom) still makes
    distinct instances, but they lower to the same field types;
  - a constant is replaced by its value, which must be a literal of its
    declared type: `Int` for `i32`, `Unsigned` (range-checked) for the
    unsigned types, `Cast(Isize, Int(n))` for `isize`, `Boolean` for `bool`;
    a value whose tokens are `n` or `-` `n` with n of 2^31 or more is the
    type's literal of that value (`Int` of -2^31 for `i32`, `Unsigned` up to
    the type's largest value, the cast of the `u64` literal of its bits for
    `isize`);
  - a char literal (`CharLiteral`) is the code of the one
    Unicode scalar value (`ScalarValue`: below 0x110000, not a surrogate)
    whose UTF-8 encoding (`utf8Encode`) its text holds between the quotes,
    other than the quote, backslash and newline, or of one of the escapes
    `\n \r \t \0 \' \" \\` (`Escape`). laniusc's `parse_char_token` decodes
    these the same way; it also takes texts this reading rejects (`'ab'`,
    `\x` for other `x`, a malformed encoding as code 0). A constant of type
    `char` is its literal. `char` is the primitive type `SrcType.char`,
    held as its code (`UInt32`), which Core's `Value.character` is;
  - `f32` and `f64` (F9) are `SrcType.float .f32/.f64`, held
    as their IEEE bit patterns as Core's `.f32Bits`/`.f64Bits` are. A float
    literal (`floatParts`, `Reading/Exprs.lean`) is decimal digits with an
    optional `.` and fraction and an optional `e`/`E` exponent with a sign,
    read as the exact `m * 10^e`; underscores are rejected, and so is an
    exponent of more than 99999 (only so that the powers stay small). Its
    value is `ofDecimal` of `m` and `e` at the expected type when that is a
    float type, and at `f32` (Core's `literalDefaultType`) otherwise.
    `flDecimal_eq` (`Reading/FloatBits.lean`) proves that the front end's
    bignum rounding equals `Lanius.IEEE.Format.ofDecimal`, so the rounding
    is not trusted; only `ofDecimal` itself is (section 3). A constant of a
    float type is its literal, or the negation of its literal;
  - `[T; N]` (F6) is `SrcType.array T N`, Core's array type,
    when N is written as a decimal integer literal (`ArrayLen`; a constant
    name as the length is not read). An array literal is read only where an
    array type is expected (a `let`'s type, a parameter, a field):
    `[a, b, ..]` must have exactly N elements, each read at T, and `[x; n]`
    needs a pure x and n written as the decimal N; it is read as N copies
    of x (`EffR.array`, `EffR.arrayRepeat`). Both are the struct literal
    node `EStruct`/`LetStruct` at the array type, whose meaning is Core's
    array value (section 2). Copies of a pure x have the value Core's
    `[x; n]` gives, which evaluates x once; `a[i]` of an array local is
    read as `a[i]` of a slice local is (`EffTy.indexArray`), and so is
    `a[i] = v`, with v read at the element type (`indexElem`);
  - a local is the byte offset of its binding (a parameter, `let` or match
    binder) from the start of its function's name (so that an
    edit to one function renumbers the locals of no other);
  - a use names the innermost binding with the same spelling, and locals may
    not be spelled like a type, type alias, variant or constant of their
    module (a function is only named by a call, so a local may share its
    spelling);
  - `let` scopes over the rest of its block;
  - `if` without `else` has an empty else;
  - binary operators fold to the left;
  - an integer literal below 2^31 is `Int`, and `-` before it is `negate`;
    one from 2^31 to 2^64 - 1 takes the type its context expects (decided by
    `lit_funcs`, below): `Unsigned(u, n)` when n fits u, for `isize` below
    2^63 the cast of the `u64` literal n, `-2147483648` at `i32` (or with no
    expectation) `Int` of -2^31, and `-n` at `isize` (n at most 2^63) the
    cast of the `u64` literal of its two's complement bits; any other
    rejects the program;
  - a bare literal operand of a shift takes the shifted
    value's type, or else the shift's expected type, and a bare amount the
    value's (`amountWant`), as a shift's type is its left operand's;
  - `&self` is read as `self`: the method takes the impl's
    type by value (`PatternOf.selfRef`, `paramToken`). laniusc's `&self`
    may write the caller's value (`self.n = ..` reaches the caller), so a
    method that writes `self` is not read (`writesLocal`,
    `refChecked`, `ReadFn`); while nothing writes through it, the reference
    and the value read the same, as no other code runs during the call;
  - `S::m(args)` (F7), where
    S names, as a type path resolved like any other (the current module's,
    an item import's, or `p::S`), a struct, or an enum with no variant
    spelled m, is read as `T::m` is for a type parameter bound to S: the
    one method spelled m of an impl whose type matches S read without type
    arguments (`TypeOwner`, `BareTy`); `E::V(args)` for a variant V of E
    still names the variant;
  - `0` where a `ptr` is expected (a `let`, a parameter, an operand beside a
    `ptr`, a `ptr` constant) is `Null`, Core's null pointer;
  - a match arm whose value calls a `-> !` function g, in a match of value
    type t, calls g's instance at t: a function with g's parameters, result
    t and body `g(params); return self(params);`. Core traps in g (each
    `-> !` function in the stdlib is `assert(false)`), so the return, which
    only gives every path a value of type t, is not reached; if g returned,
    the instance would recurse until Core's fuel ran out, and the theorem
    covers only runs that return;
  - the path `alloc::allocator::alloc(size, align)`, in a `let` of type
    `ptr`, is Core's `alloc`, and the statement
    `alloc::allocator::dealloc(p, size, align);` is Core's `dealloc`; the
    alignment must be a literal `2^k` (`8` or `(8 as usize)`), read as the
    shift `k`. `slice_from_raw_parts(p, n)`, in a `let` of type `[T]`, is
    Core's raw view of `T`. These spellings are fixed: build does not look
    at the extern declarations in `alloc::allocator`, and these paths,
    `slice_stride` and `assert` are never read as a function or variant
    (`builtinPaths`);
  - `x op= e` is `x = x op e`, and `x.f op= e` is `x.f = x.f op e`, for
    `op` one of `+ - * & | ^`. Core has the compound form itself
    (`assign .add` and so on, `evalAssignValue`), which evaluates `e` before
    it reads `x`; for the subset's expressions, which neither trap nor have
    effects, the two orders give the same value and state;
  - an expression that calls a function, indexes a slice, divides (`/`,
    `%`), or is a struct literal, variant or `match` is a `SrcEff`, and its
    statement the effectful form (`LetEval`, `SetEval`, `SetFieldEval`,
    `IfEval`, `WhileEval`, `ReturnEval`, `SetIndexEval`, `Discard` for
    `f(x);`).
    Operators, casts and negations of pure operands are `EPure`, and a
    statement with a form of its own keeps it (`LetCall`, `SetCall`,
    `LetStruct`, `LetEnum`, `LetMatch` on a local, `LetIndex`, when their
    parts are pure). `x op= e` with `e` effectful, and `x /= e`, `x %= e`,
    are `SetEval(x, x op e)`, and `x.f op= e` is `SetFieldEval(x, f, x.f op
    e)`: `x` is read before `e` is evaluated, which is Core's order too
    since reading a local has no effect. A struct
    literal's or variant's type arguments come from the type its value is
    stored at when that is known (a `let`, the assigned local, the result
    type for `return`, a parameter of a callee whose type arguments are
    known), else from its fields' or payload's types; a match's result type
    is the stored-at type or its first arm's.

  - a function without `-> T`, or with `-> !`, returns `Unit`; `return;`
    is `ReturnUnit`; `assert(c);` (that spelling, one argument) is
    `Assert(c)`, Core's assert intrinsic. So `core::panic::panic()`, whose
    body in `stdlib/core/panic.lani` is `assert(false);`, traps.

  - `isize` is `Isize`. An integer literal whose expected type is `isize`
    is `Cast(Isize, Int(n))`, and one whose expected type is unsigned is
    `Unsigned(u, n)`, decided after monomorphization by `lit_funcs` from the
    types of locals, fields, parameters, callees and results; an operator's
    operands expect the type of whichever operand has one.

  - `slice_stride(x)` of a slice local x is `EStride(x)`;
  - `return slice_from_raw_parts(p, n);` in a function whose result is a
    slice is a slice local (named by the offset of `slice_from_raw_parts`)
    and its return;
  - a bare variant name is the one variant of that spelling among the
    current module's enums, else among its imported modules' enums;
    `E::V` and `m::E::V` name enum E's variant V, `m::V` module m's one V;
  - a function's `requires c;` clauses (F10) are `assert(c)`s, in
    order, before its body (`ContractsR`), so a false one is Core's assert
    trap.

  A text outside the subset has no reading, and the theorems say nothing
  of it (`compileText` returns `none`).
- **Core**, as in section 3. `build`, the front end's code, is not trusted:
  `buildFiles_sound` proves that what it returns is a reading.

## 5. Premises computed by Lean's compiled code, and how the compiler is run

The theorems are about the Lean definitions (`compileSource`, `compileText`
and the rest), whatever they compute. Which code is run as the compiler,
and how, adds these assumptions.

### The self-built verified compiler

The verified compiler that is run is `B`, the self program compiled by
itself. `selfHost_fixpoint` and `selfHost_outcome` take two facts about the
self program's files `self` (the driver `w` and the module closure of
`mini::selfhost`: the driver, `compiler.lani`, `frontend.lani` and the
stdlib modules they import, each with laniusc's parse tree, laid out as
`self_host.py` and `faithful_current.py` lay them out) as premises, and
`selfCompiler_outcome` takes one. The kernel cannot evaluate the front end
on the self text (about 800 KB) or `compileSource` on `prog` (an image of
about 15 MB), so each is computed by Lean's compiled code, and trusted:

- **`read : sourceProgramFiles self = some prog`.** `lake exe srcDump`
  (`Lanius/Tools/SrcDump.lean`) runs the front end on the files and prints
  its program with `repr`, and the generators (`faithful_dump.py`,
  `faithful_certs.py`) write it to `Faithful/Gen/` as `prog`. Assumed: the
  term `prog` that elaborates from `Gen/` is the value the front end's
  compiled code computed for the current sources.
- **`compiled : compileText self = some B`**, and for `selfCompiler_outcome`
  `compileSource prog = some B`. `lake exe runAll` (manifest line `compile
  self ...`) computes it and writes `B`'s image and entries. Assumed: the
  image and entries files are `B`'s, as `compileText` defines them.
- **The native run.** `self_host.py`'s ctypes stub (`Native`) maps the
  image and sets up the x86 state for `w`. Assumed: the state it sets up
  meets `selfCompiler_outcome`'s premises: the caller's obligations of
  section 8 for `B` with entry 0, the heap laid out as `selfHeap` with the
  input words, the argument slots `selfBits`, and a heap limit within the
  bounds. The theorem then says what the run returns; that the stub reads
  the output view back as `SelfOutput` describes it is assumed too.

### Lean's compiled code

Wherever a premise is computed by Lean's compiled code (`srcDump`, `runAll`,
`#eval`, any `lake exe`), Lean's code generator and runtime are trusted on
that run: GMP `Nat`, and the `@[extern]` and `implemented_by`
implementations of `BitVec`, `UInt8`, `List` and `Array`. The kernel sees
none of this code.

### The laniusc build

laniusc can also compile `formal/lani/mini/compiler.lani` itself (the
difftests do). A binary built that way is not covered by any top theorem
unless these are assumed:

- **The extractor.** `Lanius/Mini/Compiler.lean` and `Frontend.lean` are
  extracted from the `.lani` sources by the extractor in Lanius
  (`formal/lani/mini/extract.lani`, run by `lake exe extract` on laniusc's
  tree once the front end's validator accepts it; `formal/tools/extract.py`
  for the programs the front end does not read yet). Assumed: each
  construct it accepts has the Lean meaning Lanius gives it. Types map one
  to one (`i32` and `u32` to `BitVec 32`, `u64` to `BitVec 64`, `usize` to
  `Nat`, `u8` to `UInt8`, `List<T>` to `List T`, `Box<T>` to `T`).
- **The prelude table** (`PRELUDE_FNS`, `PRELUDE_TYPES` in `extract.py`,
  and the same table in `extract.lani`). Assumed: `boxed` and `unbox` are
  the identity, `plus`/`times`/`minus` are `Nat` `+`/`*`/`-` on every run
  that returns (they panic instead of wrapping, and `minus` panics when
  `b > a`), and `max_of` is `max`. The prelude bodies are the only code
  that touches raw memory (`alloc`, `typed_slice_from_storage`).
- **laniusc and the Lanius runtime** (allocation, panics, stack depth) on
  this program.

None of these is on the path from the self text to `B`: `B` is
`compileText self`, and `selfHost_fixpoint` is about it, whatever the
extractor wrote. The list operations (`SPEC_FNS`) are extracted with spec
theorems the kernel checks, so they are not trusted either way.

## 6. The x86 model

- **What.** The x86 semantics that `Steps` uses:
  - `Lanius/X86/Machine/State.lean`: user-mode state, meaning sixteen 64-bit
    registers, `rip`, RFLAGS as one 64-bit word, and memory as a total function
    from 64-bit addresses to bytes;
  - `Machine/Scalar.lean`: `decode`, `execute`, `Step`, `Steps` and `Fault`;
  - `Machine/Flags.lean` and `Machine/Alu.lean`: flag results and condition
    codes;
  - `Machine/Memory.lean`: little-endian reads and writes;
  - `Control/Decode.lean`, `Register.lean` (REX) and `Word.lean`;
  - `Machine/Sse.lean` (F9): the low 64 bits of xmm0-xmm15
    (`State.xmm`) and the scalar SSE instructions the compiler emits.

  These were written by hand from the Intel SDM. Here is what the model does
  not contain, so each of the following is assumed:
  - **Faults.** Pages are mapped and have the right permissions, addresses are
    canonical, alignment checking is off (AC), and nothing raises #GP or #PF.
    Model addresses wrap modulo 2^64. Every address the code touches must be
    mapped, and then it is also canonical.
  - **Concurrency.** There are no interrupts or signals that change state, no
    other thread or process writes to the image, stack or heap, and memory
    ordering is irrelevant because the program is single-threaded.
  - **Code fetch.** One byte map serves both code and data. The proofs keep
    the image apart from every write, so self-modifying code never comes up.
  - **Not modeled at all.** Segment bases, CET shadow stacks (the compiled code
    pairs every `call` with a `ret`), and the CPU being in 64-bit mode with
    default operand sizes.
  - **SSE (F9).** The meaning of each SSE instruction is `Lanius.IEEE`'s
    operation on the bits (section 3); that the CPU computes it is trusted:
    - `movd xmm, r32` and `movq xmm, r64` (66 [REX.W] 0F 6E /r) put the
      zero-extended register in the low 64 bits; `movd r32, xmm` writes the
      low 32 bits zero-extended, `movq r64, xmm` the low 64 (66 [REX.W] 0F
      7E /r);
    - `addss subss mulss divss` (F3 0F 58/5C/59/5E /r) replace the
      destination's low 32 bits by binary32 `add sub mul div` of the two low
      32-bit fields (destination first) and keep bits 32-63; the `sd` forms
      (F2) replace all 64 low bits by the binary64 operation;
    - `cmpss`/`cmpsd` (F3/F2 0F C2 /r ib) with predicates 0 (EQ_OQ), 1
      (LT_OS) and 2 (LE_OS) write all ones in the low 32 (single) or 64
      (double) bits when `eq`, `lt` or `le` holds, else zeros (false on a
      NaN); only these three predicates decode;
    - `cvtsi2ss`/`cvtsi2sd` (F3/F2 [REX.W] 0F 2A /r) round the signed 32-
      or 64-bit register (`ofInt`); `cvtss2sd` (F3 0F 5A) widens and
      `cvtsd2ss` (F2 0F 5A) rounds (`convert`);
    - the high 64 bits of each xmm register are not modeled: no modeled
      instruction reads them into the low half, so they cannot change a
      result;
    - MXCSR is not modeled. It is assumed to hold Linux's default at exec,
      0x1F80 (round to nearest, every exception masked, no flush to zero,
      no denormals as zero), which no compiled code changes; its sticky
      exception flags are set by the CPU and never read.
- **Encoders are proved, not trusted.** The literal bytes in `Compiler.lean`
  are proved equal to the `X86/Machine` encoders (`Instr.encode_eq`,
  `prologue_eq`). Those encoders are proved to decode to the intended
  instruction for every tail of following bytes. `decode` and `execute` remain
  trusted: they are the model's claim about what the CPU does.

## 7. One model run versus the CPU's run

- **What.** `compileSource_correct` and `compileProgram_correct` are
  existential: *some* model run `Steps n s s'` returns. `Step` is a relation,
  and it leaves these choices free:
  - AF after AND, OR, XOR and TEST;
  - every flag after IMUL, NEG and shifts;
  - the byte list it decodes, which may be any list loaded at `rip`.

  The CPU's run is generally a different model run from the one the
  proofs build: the CPU's free flags differ from `execute`'s choice.
- **Proved.** Every model run of the same length ends the same way:

  ```text
  compileProgram_deterministic (Mini/Determinism.lean), same premises as
  compileProgram_correct:
    ∃ n s', Steps n s s' ∧ Returned window s s' value after ∧
      ∀ t, Steps n s t → DataEq s' t ∧ Returned window s t value after
  ```

  `DataEq` is equality of registers, rip and memory, so only RFLAGS may
  differ. `compileSource_deterministic` and `linked_deterministic` are the
  same for `compileSource_correct` and `linked_correct`, and the process
  theorems carry `Det`.
- **Still assumed.** That the CPU's run is one of the model's runs (section
  6). The theorem covers runs of exactly `n` steps, the length of the run to
  the return; after `n` steps the code is back in the caller, and no shorter
  run stops (`Live`). It says nothing about longer runs.

## 8. Linux, and what the caller must provide

### A process: the loader, the start state and the system calls

For an executable from `elfFile`, the process theorems discharge every
obligation on the x86 state below from what Linux does. Trusted about Linux:

- **`Loaded` (`Mini/Process.lean`).** For a file with one program header, a
  loadable segment from file offset 0, `execve` leaves the segment's
  `p_filesz` file bytes (header offset 96) at `p_vaddr` (80), zeros after
  them up to `p_memsz` (104), and rip at `e_entry` (24). It reads those
  fields from the file's own bytes (`fieldAt`), so a wrong header could not
  make the theorem easier. Registers, flags and the rest of memory are
  arbitrary. `elfFile`'s segment is at 2^32, readable, writable and
  executable, and its `p_memsz` covers the stack and the heap.
- **`Exits`.** A `syscall` with rax 60 ends the process with status rdi, of
  which the parent sees the low byte. The model's `Kernel` has no exit
  case, so the theorems' runs stop there (`Exits.stuck`).
- **The kernel's `write` (`Kernel` in `X86/Machine/Scalar.lean`, roadmap
  F8).** The x86 model's only other `syscall` step (`Step.syscalled`) is
  this trusted meaning of Linux's `write`: with rax 1, rdi 1 or 2, and rdx at
  most `maxTransfer` (2,147,479,552, Linux's `MAX_RW_COUNT`), the call
  - writes all rdx bytes read from memory at rsi, recorded as the event
    `.write rdi bytes` appended to the state's trace (`State.io`,
    `X86/Machine/Io.lean`), and changes no memory;
  - returns rdx in rax, leaves the next instruction's address in rcx and
    rip, an unknown value in r11 (where Linux saves RFLAGS), and every other
    register and RFLAGS as they were.

  So it is trusted that fds 1 and 2 are open for writing when the process
  starts, that a write to them never fails, blocks forever or is partial
  (a pipe whose reader has gone raises SIGPIPE, a full disk gives ENOSPC,
  and a write to a terminal or pipe may in principle return short; none of
  these is modeled), and that no signal handler runs. Any other rax, fd or
  count has no step, so a run that reaches it stops, and the theorems say
  nothing past it. `Loaded` starts the trace empty, and `process_exits`
  says the trace at the exit is the compiled mini program's write trace,
  whose bytes on fds 1 and 2 (`outputOf`) are what Core's world gained on
  its standard output and error. Core's `write_byte`, `write_stdout` and
  `write_stderr` are lowered to this `write` (SEMANTIC_DECISIONS.md,
  "Externs and the runtime"); their Core meaning is `World.call`, part of
  Core's semantics (section 3).
- **The kernel's `read` (`Kernel.read`, roadmap F8).** The state's
  `io` also holds `input`, the bytes not yet read from standard input.
  With rax 0, rdi 0 and rdx at most `maxTransfer`, the call
  - delivers the first rdx bytes of `input`, or all of it when fewer are
    left, written to memory from rsi on (`writeBytes`; no other byte
    changes), and drops rdx bytes from `input`;
  - returns how many it delivered in rax (0 at the end of the input),
    with rcx, rip, r11 and the other registers and RFLAGS as for `write`.

  So it is trusted that fd 0 is open for reading when the process starts
  and that it delivers like a regular file: every read returns as many
  bytes as were asked for until the input ends, never fails, never blocks
  forever and is never interrupted. A terminal or a pipe can return fewer
  bytes than asked for before its end (a short read), which the model does
  not have; the compiled code would still be right on one (it reads again
  only after a full read), but the theorems do not cover it. Linux checks
  the buffer with `access_ok` before reading, and could return EFAULT for
  a range outside user space even when the file has no bytes left; the
  model assumes the call does not fault, and the verified compiler's
  buffers are inside its heap, whose end is below 2^62 (`HeapAt`). Core's
  `read_stdin` is lowered to this `read` (SEMANTIC_DECISIONS.md, "Host
  reads"). `Loaded` leaves `io` as the process was given it:
  `process_exits` takes it as a premise (`s.io = given`), with Core's world
  starting from the same streams (`startState given`).
- **The clocks' readings and the secure bytes are streams.** The
  state's `io` also holds `monotonic` and `realtime`, the readings
  (seconds, nanoseconds) the two clocks will give, one a read, and
  `entropy`, the random bytes `getrandom` will deliver. They are fixed
  when the process starts, like `input`, so a run's behaviour is a
  function of them; what Linux's clocks and random source actually give is
  some such stream, and the theorems hold for every one. Core's world
  starts from the same streams (`startState`: `monotonicReadings`,
  `systemReadings`, `secureByteStream`), and a Core run that reads past
  their end traps (`clockExhausted`, `entropyExhausted`), a trap the
  theorems say nothing about (`undefinedTrap`), since the kernel's streams
  do not end. `clock_gettime` and `getrandom` read them (below).
- **The kernel's `poll` with no fds (`Kernel.poll`, roadmap F8).**
  With rax 7, rdi 0 (no array), rsi 0 (no fds) and an rdx below 2^31 (a
  nonnegative `int` timeout in milliseconds), the call returns 0 in rax,
  changes no memory and no trace, and leaves rcx, rip, r11 and the other
  registers and RFLAGS as for `write`. Linux reads the timeout from the low
  32 bits of rdx; the compiled code passes a nonnegative `i32` held
  zero-extended, so the whole register is that value. So it is trusted that
  such a poll only waits (Linux's `do_sys_poll` with `nfds` 0 touches no
  user memory) and that no signal interrupts it (an interrupted poll
  returns EINTR, which the model does not have; the stdlib's sleep checks
  for 0 and would report failure, but the theorems do not cover it). How
  long it waits is not modeled: the x86 model has no clock. Core's
  `sleep_ms_i32` is lowered to this `poll` (SEMANTIC_DECISIONS.md, "Host
  sleep"); Core's world advances only its whole-second compatibility clock
  by the count, which no modeled call reads.
- **The kernel's `clock_gettime` (`Kernel.clock`, roadmap F8, 10-31).**
  With rax 228 and rdi 0 (`CLOCK_REALTIME`) or 1 (`CLOCK_MONOTONIC`), the
  call stores the next reading of that clock's stream (`Io.readings`:
  `monotonic` for 1, `realtime` for 0) from rsi on as a `struct timespec`,
  16 bytes, `tv_sec` then `tv_nsec`, each a little-endian 64-bit word
  (`timespecLE`), drops the reading (`Io.afterReading`), returns 0 in rax,
  and leaves rcx, rip, r11, the other registers and RFLAGS as for `write`.
  The compiled code passes a heap address with 16 bytes inside the heap
  (`add rsi, r12`). So it is trusted that `clock_gettime` of these two
  clocks into writable memory always succeeds (Linux returns EFAULT only
  for an address it cannot write, and EINVAL only for other clocks), that
  the seconds and nanoseconds it gives are some stream of readings fixed
  for the run (the code makes the system call itself, not the vDSO
  call). When the stream has no
  reading left the model has no step: such runs are outside the theorems,
  as Core's `clockExhausted` is.
- **The kernel's `getrandom` (`Kernel.getrandom`, roadmap F8, 10-31).**
  With rax 318, rsi (the count) at most 256, rdx 0 (no flags) and at
  least that many bytes left in `entropy`, the call stores the next count
  of them from rdi on, drops them, returns the count in rax, and leaves
  the other registers as for `write`. The compiled code asks for at most
  256 bytes at a time, to a heap address inside the heap (`add rdi,
  r12`). So it is trusted that such a `getrandom` returns every byte asked
  for and is not interrupted (Linux's documented guarantee for requests of
  at most 256 bytes once the entropy pool is initialized; before that the
  call blocks, which the model does not see), that it never fails on
  writable memory, and that the bytes it gives are some stream fixed for
  the run.
  No other system call is modeled (SEMANTIC_DECISIONS.md, "Externs and the
  runtime").
- The startup code sets rsp, r12 to r15, r10 (the heap's top) and rbx (the
  frame pointer, at the heap's top) and calls `entry` (the driver's
  convention is function 0, `main`), and `mov rdi, rax; mov eax, 60;
  syscall` follows the call. Its 85 bytes are proved, not trusted. The
  program header maps frame memory, as many bytes as the stack, above the
  heap: the heap's top is `heap + stack`. `entry` must take
  no parameters.
- **Linux's start state.** Registers other than those the startup code
  sets, flags and memory outside the segment are arbitrary (`Loaded`); fds
  0, 1 and 2 are open as above; MXCSR holds its default 0x1F80 (section 6);
  the operating system is as in "Operating system" below.

### Code entered another way: the caller's obligations

For code entered some other way (the theorems on `compileSource`,
`compileText`, `compileProgram` and the self-built compiler), the premises
are obligations on whatever sets up the x86 state. `compileSource_stops`
and `compileSource_behaviour` have them without `stackNeed depth ≤ window`,
and with a heap limit of at least 1.

- **Image.** `CodeAt s.memory imageBase binary.image`: the image is loaded
  byte for byte at any base and is executable. Its bytes are apart from the
  stack window and from the heap. The proofs then show that nothing writes to
  them.
- **Entry.** `s.rip = imageBase + entries[f]`. The function is entered by a
  near call, so the return address is at `[rsp]`.
- **Arguments.** Argument `k` is the 64-bit word at `rsp - (8k + 16)`, just
  below the return address. The results come back in the same slots, and the
  last one is also in rax. This is not the SysV convention, so a stub has to
  translate between the two.
- **Stack.**
  - r15 holds the stack limit, and the window is the stack from
    `binary.guard` bytes below r15 up to the return address (`StackAt`:
    `r15 + window = rsp + guard`, r15 above 4 GiB and at most 8 bytes above
    rsp). Its bytes must be mapped and writable, and they must be apart from
    the image. `binary.guard` is one frame plus 8 bytes: what a call writes
    (arguments, return address) before the callee's check.
  - Each prologue ends with `cmp r15, rsp; jbe +2; ud2`, so a frame that
    would end below r15 faults before it writes a slot. The contract of
    every function is therefore "returns, or the window is short of
    `binary.stackNeed depth` and the run stops at a fault"; with
    `binary.stackNeed depth ≤ window ≤ 2^62` it returns.
  - `depth` is existential in `compileSource_correct`, so nobody can compute
    the needed stack before the run.
- **Heap (`HeapAt`).**
  - The base is in r12, the cursor (an offset) in r13, the limit in r14 and
    the heap's top in r10, with `top < 2^62` (`HeapAt.small`).
  - The bytes at `r12 + a` for `a < top` are the heap: the bump heap below
    the limit, then frame memory. They are mapped,
    writable, and apart from the stack window, the return address and the
    image.
  - `compileSource_correct` also requires `r13 = 1` and zero bytes from
    offset 1 up, which a fresh anonymous mapping provides, and an empty
    write trace (`silent`: the state's trace, which `HeapAt` makes the mini
    heap's, has no events yet), so that the output it concludes equal to
    Core's world's is the code's own.
  - `compileProgram_correct` accepts any cursor.
  - rbx holds the frame pointer `fsp`, an offset from r12 like the cursor
    (`HeapAt.fsp`), at most the heap's top (`HeapAt.fspLe`). Frame memory
    is the bytes from `limit` up to the top in r10 (`HeapAt.top`); the
    startup code sets r10 and rbx to `heap + stack`.
- **Registers after the call.**
  - rsp is restored to `rsp + 8` and rbp is restored.
  - rax, rbx, rcx, rdx, rsi, rdi, r11 and r13 may change (the code writes rdx,
    rsi and rdi only for a `Sys` statement). Each call saves rbx in the
    caller's first result slot and loads it back after the return, so a
    callee need not keep it. r10 is kept (`Returned.top`: the callee's
    heap ends at the same top). rbx and r13 are callee-saved under SysV, so a
    SysV caller's stub has to save them. The stubs also save r12, r14 and
    r15, which they set, and must set r10 to the top of the region they hand
    over (r10 is caller-saved under SysV).
  - RFLAGS is unspecified. DF is never changed, and the code has no string
    instructions.
- **Memory.** Only the window and the heap change.
- **Operating system.** Linux maps memory as requested, saves and restores
  the full register state and RFLAGS across preemption and signal delivery,
  and no debugger or second thread changes the process. Linux enables CET
  shadow stacks only for programs that opt in. They are compatible with the
  compiled code anyway, because every `call` is paired with a `ret`.

## 9. Evidence

These test the assumptions above; none of them is part of the trusted base,
and a passing test proves nothing beyond its cases.

- **The x86 model against the CPU** (`formal/tools/x86_model_test.py`, gate
  step `x86-model`). Every instruction form the compiler emits (the Lean
  side prints `Instr.encode` for every constructor, `prologue` and
  `epilogue`; the tool fails on a byte it cannot place in its form table, so
  a new emitted form cannot go untested), on random registers, flags, DF,
  memory and immediates, with the SSE forms on edge float patterns under
  MXCSR 0x1F80. A stub runs the bytes natively with a landing pad at every
  possible next `rip`; Lean runs `decode` and `execute` on the same states.
  Compared: exact on the sixteen registers, `rip`, the xmm registers' low
  64 bits and the memory region; on the flag bits `Step` fixes; `decode`
  must return exactly the instruction's length, decode no shorter prefix,
  ignore a random tail and not decode as a division. On 10-31 (AMD Ryzen 9
  5900HX): 10,603 cases, 0 disagree. A deliberately wrong model is caught
  (CF flipped after `cmp`, ZF after `add`, rbx changed by `pop rbp`). It
  once found `88 /r` without REX decoded as a store of SPL..DIL, where the
  CPU stores AH..BH; `decode` now rejects it, and `--probes` checks that.
- **Core's IEEE operations against the CPU** (`formal/tools/float_test.py`,
  gate step `float`): `Lanius.IEEE`, compiled, against `addss`...`divsd`,
  `cmpss`/`cmpsd`, `xorps`, the conversions, libc's `strtof`/`strtod` and
  exact integer truncation, on edge patterns, ties, near operands and random
  bits: 79,214 cases, 0 differ.
- **Processes** (`formal/tools/elf_test.py`, gate step `elf`): executables
  from `elfFile` run natively: exit statuses, a division by zero
  (SIGFPE) and a stack too small for the recursion (SIGILL).
- **The compiler and the front end against laniusc**: `mini_difftest.py`
  (images from `#eval compileProgram` and the laniusc build, byte for
  byte), `fn_difftest.py` (each extracted function in Lean and natively),
  `oracle_difftest.py`, `frontend_difftest.py` (the front end against the
  generator's programs and the cases), `stdlib_oracle.py` and
  `programs_oracle.py` (compiled code against laniusc's on the stdlib and
  test programs).
- **The extraction** (gate step `extract`, `lani_extract.py --check`): the
  extracted Lean files are what the extractor in Lanius writes from
  laniusc's trees.
- **The self program and `B`**: gate step `self-current`
  (`faithful_current.py`) regenerates `Gen/` from the current sources and
  fails unless it is what is checked in, so `prog` is never stale; the
  certificates hold of every function of `prog` reachable from the driver's
  roots, so a reachable function printed with another meaning fails to
  check. Gate step `self-host-fixpoint` runs `B` natively on `self`: it
  returns exactly runAll's words for `self`, `B`'s own image byte for byte,
  so an error in Lean's compiled code for `compileText` would have to be one
  `B` itself reproduces.
- **This file** (gate step `trusted`): the axioms, statements and trusted
  definitions are the ones listed.

## 10. Not trusted

- The computations the theorems are about: `compileSource`, `compileText`,
  `compileProgram`, the optimizer inside them (its output is kept only when
  the proved validator accepts it), `compileModules`, `linkObjects`,
  `elfFile`, `sourceProgramFiles` and the front end's `build`,
  `compileWords`, `frontEndWords`, and the self program `prog`. The
  theorems say what their results mean, whatever they are.
- laniusc's lexer and parser, and the parse trees they give (section 4).
- The encoders, the startup code's bytes and every proof file: the kernel
  checks them.
- The certificate generators (`faithful_certs.py`, `faithful_pure.py`) and
  the tests of section 9.
- The native harness stubs, except as the loader of section 5 when they are
  used that way.

Outside the verified compiler's theorems: the `&mut` pilot
(`Lanius/Mini/MutPilot.lean`, `MutPilotCorrect.lean`) and the state-machine
theorems (`Lanius/Machines/`) are about programs extracted by `extract.py`,
so they rest on its extraction (section 5) and, for the pilot, on laniusc's
exclusivity check of `&mut` arguments and their passing by address. No top
theorem depends on them.
