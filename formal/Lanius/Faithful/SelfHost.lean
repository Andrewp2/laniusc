import Lanius.Faithful.SelfCompiler

/-! # The verified compiler self-hosts (roadmap step F12)

The top theorem, `selfHost_fixpoint`, first. Let `self` be the self
program's source files (the driver `w` and the module closure of
`mini::selfhost`, which is `compiler.lani` followed by `frontend.lani`,
each with laniusc's parse tree, as `formal/tools/faithful_current.py`
lays them out). Two facts are
computed, not proved (TRUSTED_BASE.md section 5, "The self-built verified
compiler"):

- `read`: the front end reads `self` as `prog`, the program of the
  extraction certificates (`srcDump` prints it to `Gen/`);
- `compiled`: `compileText self = some B`, the binary `lake exe runAll`
  writes as the self-built verified compiler.

From these, and with no other assumption than `selfCompiler_outcome`'s:

1. `prog` is the one reading of `self`'s texts (`TextReading`, unique),
   so `B` is the verified compiler's compilation of what its own source
   text means;
2. the fixpoint: `B`'s machine code for `w`, entered with the words of
   `self` and `room` words of output view, faults (every run that stops,
   stops at a fault: out of stack, heap or output room), or returns,
   deterministically, the length of `B`'s own words, with those words in
   the output view: `B` compiles its own source text to `B`.

`selfHost_outcome` is the same for any other files: the self-built
verified compiler, built from its own text, gives `compileText`'s answer
for them (V7's `selfCompiler_outcome`, with its premise
`compileSource prog = some B` replaced by the two computed facts above,
which are about source text and the binary on disk). -/

namespace Lanius.Faithful.SelfHost

open Lanius.Mini
open Lanius.X86.Machine
open Lanius.Faithful
open Lanius.Faithful.Self
open Lanius.Faithful.SelfCompiler

/-- **The verified compiler self-hosts** (F12). For source files `self` that
the front end reads as the self program `prog` (`read`), and `B`, the
verified compiler's binary for them (`compiled`): `prog` is the files' one
reading, and `B`'s code for `w`, entered with the words of `self` and `room`
output words (premises as in `selfCompiler_outcome`), faults, or returns
deterministically with `B`'s own words in its output view. -/
theorem selfHost_fixpoint {self : List SourceFile} {B : Binary}
    (read : sourceProgramFiles self = some prog) (compiled : compileText self = some B)
    (fit : FilesFit self) (wordsLt : (filesWords self).length < 2 ^ 31) {room limit : Nat} (roomLt : room < 2 ^ 31)
    (enough : selfNext (filesWords self) room ≤ limit) (small : limit < 2 ^ 62)
    (s : State) (imageBase : BitVec 64) (window : Nat) (bounded : window ≤ 2 ^ 62)
    (loaded : CodeAt s.memory imageBase B.image)
    (apart : ∀ index, index < B.image.length →
      ¬Below (s.registers rspRegister) window (imageBase + BitVec.ofNat 64 index))
    (imageHeap : ∀ index, index < B.image.length → ¬s.InHeap (imageBase + BitVec.ofNat 64 index))
    (entry : s.rip = imageBase + BitVec.ofNat 64 (B.entries.getD 0 0))
    (params : ∀ k (bound : k < (selfBits (filesWords self) room).length),
      read64 s.memory (s.registers rspRegister - BitVec.ofNat 64 (8 * k + 16)) = (selfBits (filesWords self) room)[k])
    (heapAt : HeapAt window s (selfHeap (filesWords self) room limit)) (stack : StackAt B.guard window s) :
    TextReading (self.map SourceFile.source) prog ∧
    (∀ sp, TextReading (self.map SourceFile.source) sp → sp = prog) ∧
    (Faults s ∨
      ∃ n s' results after, Steps n s s' ∧ Det n s s' ∧ Returned window s s' results after ∧
        SelfOutput (some B) (filesWords self) s s') := by
  have reading := textBuilt_reading (sourceProgramFiles_built read)
  refine ⟨reading, fun _ r => textReading_unique r reading, ?_⟩
  have source : compileSource prog = some B := by
    unfold compileText at compiled
    rw [read] at compiled
    exact compiled
  have outcome := selfCompiler_outcome source fit wordsLt roomLt enough small
    s imageBase window bounded loaded apart imageHeap entry params heapAt stack
  rw [compiled] at outcome
  exact outcome

/-- The binary the verified compiler makes of text the front end reads as
`prog` is `compileSource prog`. -/
theorem compileSource_of_text {self : List SourceFile} {B : Binary}
    (read : sourceProgramFiles self = some prog) (compiled : compileText self = some B) :
    compileSource prog = some B := by
  unfold compileText at compiled
  rw [read] at compiled
  exact compiled

/-- The self-built verified compiler, built from its own source text, on any
source files: V7's `selfCompiler_outcome` with its premise
`compileSource prog = some B` given by `read` and `compiled`. -/
theorem selfHost_outcome {self : List SourceFile} {B : Binary}
    (read : sourceProgramFiles self = some prog) (compiled : compileText self = some B)
    {files : List SourceFile}
    (fit : FilesFit files) (wordsLt : (filesWords files).length < 2 ^ 31) {room limit : Nat} (roomLt : room < 2 ^ 31)
    (enough : selfNext (filesWords files) room ≤ limit) (small : limit < 2 ^ 62)
    (s : State) (imageBase : BitVec 64) (window : Nat) (bounded : window ≤ 2 ^ 62)
    (loaded : CodeAt s.memory imageBase B.image)
    (apart : ∀ index, index < B.image.length →
      ¬Below (s.registers rspRegister) window (imageBase + BitVec.ofNat 64 index))
    (imageHeap : ∀ index, index < B.image.length → ¬s.InHeap (imageBase + BitVec.ofNat 64 index))
    (entry : s.rip = imageBase + BitVec.ofNat 64 (B.entries.getD 0 0))
    (params : ∀ k (bound : k < (selfBits (filesWords files) room).length),
      read64 s.memory (s.registers rspRegister - BitVec.ofNat 64 (8 * k + 16)) = (selfBits (filesWords files) room)[k])
    (heapAt : HeapAt window s (selfHeap (filesWords files) room limit)) (stack : StackAt B.guard window s) :
    Faults s ∨
    ∃ n s' results after, Steps n s s' ∧ Det n s s' ∧ Returned window s s' results after ∧
      SelfOutput (compileText files) (filesWords files) s s' :=
  selfCompiler_outcome (compileSource_of_text read compiled) fit wordsLt roomLt enough small
    s imageBase window bounded loaded apart imageHeap entry params heapAt stack

#print axioms selfHost_fixpoint
#print axioms selfHost_outcome

end Lanius.Faithful.SelfHost
