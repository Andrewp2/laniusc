# Trusted base of the verified compiler

Roadmap step 14. This is every assumption that the two top-level theorems rest
on but do not prove:

- `Lanius.Mini.compileSource_correct` (`Lanius/Mini/SourceCorrect.lean`). If
  `compileSource sp = some binary` and Core evaluates `f(args)` to `v`, then
  the code for `f`, entered by a near call in a suitable x86 state, returns
  slots that represent `v`.
- `Lanius.Mini.compileProgram_correct` (`Lanius/Mini/Correct.lean`). The same
  for a mini IR program against the mini big-step semantics.

The list was found by reading the theorem statements, the definitions they
mention, the extractor, and the x86 model. Each item gives what it is, where
it lives, how it is checked today, and what would shrink it. Last updated
2026-10-21, at the commit that adds this file.

## 1. Lean

- **What.** The Lean 4 kernel (toolchain `leanprover/lean4:v4.33.1`, pinned in
  `lean-toolchain`; the project has no package dependencies) and three
  axioms:

  ```text
  #print axioms Lanius.Mini.compileSource_correct
  'Lanius.Mini.compileSource_correct' depends on axioms: [propext, Classical.choice, Quot.sound]
  #print axioms Lanius.Mini.compileProgram_correct
  'Lanius.Mini.compileProgram_correct' depends on axioms: [propext, Classical.choice, Quot.sound]
  ```

  These are Lean's standard axioms. There is no `sorryAx`, and there is no
  `Lean.ofReduceBool`, so nothing relies on `native_decide`, `bv_decide` or
  compiled code. Elaboration and tactics (`omega`, `bv_omega`, `simp`,
  `decide`) are not trusted, because the kernel rechecks every term they
  produce.
- **Checked by.** `lake build LaniusMini`, and `#print axioms` as above, run
  from a file that imports `Lanius.Mini.SourceCorrect`, with
  `lake env lean`.
- **To shrink it.** Recheck the exported environment with an independent
  kernel, for example lean4lean (`leanchecker`, which ships with the
  toolchain, replays the same kernel).

## 2. The statement: definitions the reader must accept

A theorem only means what its definitions say. These definitions are part of
the statement, so a reader has to agree that each one says what is intended:

| definition | file | says |
|---|---|---|
| `SrcProgram.toCore` and the `toCore` of each construct | `Mini/Source.lean` | which Core program a source program *is*: each construct is the Core construct of the same name, and functions are numbered by position |
| `FieldsHold`, `SrcType.HoldsAt` | `Mini/Source.lean` | how a Core value sits in 64-bit slots: an `i32` is zero-extended, a `bool` is 1/0, a struct is its fields in order, an enum is a tag then its payload, a pointer is its address |
| `Returned`, `HeapAt`, `Contract`, `Scratch`, `InHeap` | `Mini/Simulation.lean` | the calling convention and what "returns" means (below) |
| `Below`, `Binary.stackNeed` | `Mini/Frame.lean`, `Mini/Bytes.lean` | the stack window |
| `CodeAt`, `Steps`, `Step` | `X86/Machine/State.lean`, `X86/Machine/Scalar.lean` | the image is loaded, and the machine runs (see section 6) |

`compileSource` and `compileProgram` themselves are not trusted. The theorem
is about whatever they compute.

## 3. Core semantics as the meaning of Lanius

- **What.** `compileSource_correct` states correctness against Core's
  fuel-indexed evaluator `Lanius.Semantics.evalExpr` (`Lanius/Semantics.lean`,
  1,822 lines) and Core's heap (`Lanius/Memory.lean`; the allocator is
  unbounded and `nextAddress` starts at 1). We assume that this evaluator is
  what Lanius programs mean. No other formal semantics exists to compare it
  with, and laniusc, the GPU compiler, is not proved against it.
- **Coverage.** The theorem covers only Core runs that finish
  (`= .done v final`) on programs that `compileSource` accepts. It does not
  cover divergence, Core traps, or programs outside the subset (`compileSource`
  returns `none` for those). Core's allocator never fails. On x86 the heap
  limit is enforced (the bump allocator executes `ud2` past it), and the
  theorem assumes that Core's run fits:
  `final.heap.nextAddress ≤ heap.limit`.
- **Checked by.** Reading, and Core's own Lean tests (`Lanius/Semantics/*Tests.lean`).
  Core is not tested against laniusc-built binaries.
- **To shrink it.** Run a differential test of `#eval evalExpr` against
  laniusc's output on the subset; this is roadmap step 12 run the other way.
  Extend the theorem to divergence and traps.

## 4. The front end

- **What.** The input is a `SrcProgram` value, not source text. Nothing in
  the chain parses Lanius. Whatever builds the `SrcProgram` (today the
  difftest generators) is trusted to build the program that was meant. The
  only premise about argument types is `FieldsHold (paramTypes func.params)
  args ...`. The source type checker is roadmap step 7, and translation
  validation of the parser is step 8.
- **To shrink it.** Steps 7 and 8.

## 5. Extraction, and how the compiler is run

The theorem is about the Lean definitions in `Lanius/Mini/Compiler.lean`. A
compiler that someone actually runs is one of these two:

1. **The Lanius build.** laniusc compiles `formal/lani/mini/compiler.lani`.
   Two things are trusted here:
   - **The extractor.** `formal/tools/extract.py` (1,227 lines of Python) is
     trusted to give each construct it accepts the Lean meaning that Lanius
     gives it. It maps types one to one (`i32` and `u32` to `BitVec 32`,
     `u64` to `BitVec 64`, `usize` to `Nat`, `u8` to `UInt8`, `List<T>` to
     `List T`, `Box<T>` to `T`) and rejects anything outside the subset.
   - **The prelude table.** `PRELUDE_FNS` and `PRELUDE_TYPES` in
     `extract.py` are trusted. `boxed` and `unbox` are the identity,
     `plus`/`times`/`minus` are `Nat` `+`/`*`/`-` on every run that returns
     (they panic instead of wrapping, and `minus` panics when `b > a`), and
     `max_of` is `max`. The prelude bodies are the only code that touches
     raw memory (`alloc`, `typed_slice_from_storage`).

   The list operations (`SPEC_FNS`) are *not* trusted. Each is extracted with
   a spec theorem that Lean checks. The trust also covers laniusc itself and
   the Lanius runtime (allocation, panics, stack depth) on this one program.

   Checked by:
   - `extract.py --check`, which confirms that `Compiler.lean` is not stale
     (it passes at this commit; CI does not run it);
   - `mini_difftest.py`, which compares images from `#eval compileProgram`
     and from the Lanius build byte for byte (3,006 programs, 757,000 bytes,
     no differences);
   - `fn_difftest.py`, which calls each extracted function in Lean and
     natively (8,200 calls on the back end and 3,140 on the front pass, no
     differences).

   To shrink it: a Lean semantics for the pure subset and a proof that
   extraction preserves it (roadmap steps 2 and 6), and self-hosting
   (step 11).
2. **The Lean build.** Run `#eval compileSource` or a compiled Lean
   executable. Extraction is then irrelevant, but Lean's code generator and
   runtime are trusted: GMP `Nat`, and the `@[extern]` and `implemented_by`
   implementations of `BitVec`, `UInt8` and `List`. The kernel does not see
   any of this code.

## 6. The x86 model

- **What.** The x86 semantics that `Steps` uses:
  - `Lanius/X86/Machine/State.lean`: user-mode state, meaning sixteen 64-bit
    registers, `rip`, RFLAGS as one 64-bit word, and memory as a total function
    from 64-bit addresses to bytes;
  - `Machine/Scalar.lean`: `decode`, `execute`, `Step`, `Steps` and `Fault`;
  - `Machine/Flags.lean` and `Machine/Alu.lean`: flag results and condition
    codes;
  - `Machine/Memory.lean`: little-endian reads and writes;
  - `Control/Decode.lean`, `Register.lean` (REX) and `Word.lean`.

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
- **Encoders are proved, not trusted.** The literal bytes in `Compiler.lean`
  are proved equal to the `X86/Machine` encoders (`Instr.encode_eq`,
  `prologue_eq`). Those encoders are proved to decode to the intended
  instruction for every tail of following bytes. `decode` and `execute` remain
  trusted: they are the model's claim about what the CPU does.
- **Checked by.** `formal/tools/x86_model_test.py` (step 14), described in
  section 9. On this CPU it found no disagreement on any form the compiler
  emits. It did find one decoder defect outside those forms (section 9).
- **To shrink it.**
  - Run the same test on an Intel CPU.
  - Use a decoder oracle such as Intel XED for `decode`.
  - Compare against an independent formal ISA (Sail x86 or ACL2 X86isa) for
    the subset.
  - Make `decode` reject byte forms that the compiler does not emit.

## 7. One model run versus the CPU's run

- **What.** Both theorems are existential: *some* model run
  `Steps n s s'` returns. `Step` is a relation, and it leaves these choices
  free:
  - AF after AND, OR, XOR and TEST;
  - every flag after IMUL, NEG and shifts;
  - the byte list it decodes, which may be any list loaded at `rip`.

  The proofs choose `AF = false` for the logical operations and keep the old
  flags after IMUL (`BinOp.final_step`). The CPU does neither. In the step 14
  test, the CPU's free flags differed from `execute`'s choice in about 3,200
  of 28,000 cases per seed.

  So the CPU's run is generally a *different* model run from the one the
  proof builds. The theorem transfers to the CPU only if every model run from
  `s` behaves the same up to those free flags. That holds if compiled code
  never reads a free flag before a `cmp` or `test` overwrites it: `setcc`
  follows `cmp`, `je` follows `test` and reads only ZF, and `jbe` follows
  `cmp`. `MINI_COMPILER.md` argues this ("deterministic on everything the
  theorem observes"), but Lean does not prove it.
- **Partly checked.**
  - Every encoder has a Lean theorem that decoding does not depend on the
    bytes after the instruction.
  - The step 14 test checks, for every emitted form, that every shorter
    prefix decodes to nothing, so `decode` sees only one instruction at each
    `rip`.
- **To shrink it.** Prove that `Step` is deterministic on the compiled bytes up
  to the free flags, and state the theorems for all runs. Or prove that each
  instruction after a free-flag writer overwrites the flags before any read.

## 8. What the caller and the loader must provide

The premises of `compileProgram_correct` (also inside
`compileSource_correct`) are obligations on whatever sets up the x86 state.
Today no verified loader exists. The images run natively only from a
hand-written ctypes stub, which checks the mini difftest's image and is kept
outside the repository with the scratch work. The ELF startup and exit wrapper (`X86/StartupExitCheck.lean`) has
not been composed with the theorem yet.

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
  - The window must satisfy `binary.stackNeed depth ≤ window ≤ 2^62`. Its
    bytes must be mapped and writable, and they must be apart from the image.
  - `depth` is existential in `compileSource_correct`, so nobody can compute
    the needed stack before the run.
  - The compiled code has no stack check. Overflow has to be caught by the
    runtime, for example with a guard page that turns it into a fault, and
    that case is outside the theorem.
- **Heap (`HeapAt`).**
  - The base is in r12, the cursor (an offset) in r13, and the limit in r14,
    with `limit < 2^62`.
  - The bytes at `r12 + a` for `a < limit` are the heap. They are mapped,
    writable, and apart from the stack window, the return address and the
    image.
  - `compileSource_correct` also requires `r13 = 1` and zero bytes from
    offset 1 up, which a fresh anonymous mapping provides.
  - `compileProgram_correct` accepts any cursor.
- **Registers after the call.**
  - rsp is restored to `rsp + 8` and rbp is restored.
  - rax, rcx, r11 and r13 may change. r13 is callee-saved under SysV, so a
    SysV caller's stub has to save it.
  - RFLAGS is unspecified. DF is never changed, and the code has no string
    instructions.
- **Memory.** Only the window and the heap change.
- **Operating system.** Linux maps memory as requested, saves and restores
  the full register state and RFLAGS across preemption and signal delivery,
  and no debugger or second thread changes the process. Linux enables CET
  shadow stacks only for programs that opt in. They are compatible with the
  compiled code anyway, because every `call` is paired with a `ret`.

## 9. Testing the x86 model against the CPU

```bash
python3 -I formal/tools/x86_model_test.py target/claude-work/step14/seed1 --per-form 500 --seed 1 --probes
python3 -I formal/tools/x86_model_test.py target/claude-work/step14/seed2 --per-form 500 --seed 2
```

**The forms.** The tool tests every instruction form the mini compiler emits:
57 forms. The Lean side prints `Instr.encode` for every `Instr` constructor
(every `BinOp` and `CmpOp` at both words), plus `prologue` and `epilogue`.
The tool splits those bytes into the form table and fails on any byte it
cannot place, so a new emitted form cannot go untested. The 57 forms are:
- `mov` with an imm64 or imm32 operand;
- the frame-slot load and store through `[rbp+disp32]`;
- the heap byte load and store;
- seven register moves;
- `neg`;
- add, sub, and, or, xor and imul at 32 and 64 bits;
- the bump allocator's 64-bit add and and;
- `sub rsp, r11`;
- three `cmp`s and `test`;
- ten `setcc`s and `movzx`;
- `jmp`, `je`, `jbe` and `call` (rel32);
- `push` and `pop rbp`, `ret`, and `ud2`.

**Each case.** The tool draws random registers (with special values and
equal operands mixed in), random status flags and DF, a random 256-byte
memory region, and a random displacement or immediate. Each memory form's
base register is set so that the access lands in the region.

**Native run.** A stub in an RWX mapping loads RFLAGS and all sixteen
registers and executes the bytes. Every possible next `rip` (fall-through,
branch target, call target, or return address) holds a landing pad that
records which one was reached, along with the registers and RFLAGS. `ud2`
runs in a forked child, which must die of SIGILL.

**Lean run.** The tool generates `ModelTest.lean` and runs it with
`lake env lean`. It applies `decode` and `execute` to the same states with
`#eval`.

**The comparison.**
- Exact on the sixteen registers, `rip` and the region. The rest of the page
  must be unchanged.
- On the flag bits that `Step` fixes: CF, PF, AF, ZF, SF, OF and DF. AF is
  left out for AND, OR, XOR and TEST, and every flag is left out for IMUL
  and NEG.
- `decode` must return exactly the instruction's length, every shorter prefix
  must decode to nothing, a random tail must not change the result, and the
  instruction must not decode as a division.

**Results** (2026-10-21, AMD Ryzen 9 5900HX, Zen 3).

| run | compiler forms | cases | disagreements |
|---|---:|---:|---:|
| seed 1 | 57 | 28,003 | 0 |
| seed 2 | 57 | 28,003 | 0 |

Each run took about 4 s natively and 35 s in Lean. A deliberately wrong
model was caught on every case of the mutated forms: CF flipped after `cmp`,
ZF flipped after `add`, and rbx changed by `pop rbp`.

**Disagreement found (outside the compiler's forms).** `decode` accepts the
byte store `88 /r` with no REX prefix and reg field 4-7 as a store of SPL,
BPL, SIL or DIL. Without REX, the CPU stores AH, CH, DH or BH. For example,
`88 a1 00 00 00 00` (`mov [rcx], ah`):

- input: rax = 0xbbc8298e, so AH = 0x29; rsp = 0x2b;
- the model writes 0x2b, the low byte of rsp;
- the CPU writes 0x29.

The `--probes` forms `mov [rcx+disp32], ah` and `bh` disagree on 950 of
1,000 cases. The other 50 are cases where the two bytes happen to be equal.
With a 0x40 prefix (SPL, DIL), the model and the CPU agree.

The compiler emits only `88 81` (AL), and the encoder `byteMemoryBytes`
forces a REX prefix for registers 4-7, so the theorems are not affected.
But `Step` would accept the wrong successor for those bytes. The fix belongs
in `memoryForm` in `Machine/Scalar.lean`: reject opcode 136 without REX when
the reg field is 4-7, as `byteRegister?` already does for SETcc and MOVZX.
It has not been changed here.

## 10. Not trusted

These are evidence, not part of the trusted base:
- the difftests (`mini_difftest.py`, `fn_difftest.py`, `x86_model_test.py`);
- the native harness stubs (except as the loader in section 8, when they are
  used that way);
- `compileSource` and `compileProgram`;
- the encoders and every proof file.
