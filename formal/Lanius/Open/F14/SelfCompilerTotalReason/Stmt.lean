import Lanius.Faithful.SelfBounded

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.X86.Machine
open Lanius.Faithful
open Lanius.Faithful.Self
open Lanius.Faithful.SelfRep
open Lanius.Faithful.SelfDriver
open Lanius.Faithful.SelfCompiler
open Lanius.Faithful.SelfLive
open Lanius.Faithful.SelfPanics
open Lanius.Faithful.SelfAgree
open Lanius.Faithful.SelfShort
open Lanius.Faithful.Termination
open Lanius.Faithful.SelfBounded
open Lanius.Faithful.SelfTotal

/-- **F14's top theorem, `selfCompiler_total_reason`.** The self-built verified
compiler either faults for a reason or returns the compile's output, and the
reasons no longer include a `plus` or `times` panic: a fault because Core's
run of `w` fails at every fuel comes with the output room short, the heap
limit short of the self program's compile, or (when that compile has no cost)
the wrapped compile costing more than the heap limit. This is
`SelfTotal.selfCompiler_total_reason_of_bounds` without its premise
`CompileBounded T`, for a heap limit below `2 ^ 61` (the threshold the root
preconditions are stated at; `selfCompiler_reason` asks `limit < 2 ^ 62`). -/
def Lanius.Open.SelfCompilerTotalReason : Prop :=
  ∀ {B : Binary}, compileSource prog = some B →
    ∀ {files : List SourceFile}, FilesFit files → (filesWords files).length < 2 ^ 31 →
    ∀ {room limit : Nat}, room < 2 ^ 31 → selfNext (filesWords files) room ≤ limit → limit < 2 ^ 61 →
    ∀ (s : State) (imageBase : BitVec 64) (window : Nat), window ≤ 2 ^ 62 →
    CodeAt s.memory imageBase B.image →
    (∀ index, index < B.image.length →
      ¬Below (s.registers rspRegister) window (imageBase + BitVec.ofNat 64 index)) →
    (∀ index, index < B.image.length → ¬s.InHeap (imageBase + BitVec.ofNat 64 index)) →
    s.rip = imageBase + BitVec.ofNat 64 (B.entries.getD 0 0) →
    (∀ k (bound : k < (selfBits (filesWords files) room).length),
      read64 s.memory (s.registers rspRegister - BitVec.ofNat 64 (8 * k + 16)) = (selfBits (filesWords files) room)[k]) →
    HeapAt window s (selfHeap (filesWords files) room limit) → StackAt B.guard window s →
    SelfFaultReasonW files room limit window B s ∨
    ∃ n s' results after, Steps n s s' ∧ Det n s s' ∧ Returned window s s' results after ∧
      SelfOutput (compileText files) (filesWords files) s s'
