module

public import Lanius.Faithful.SelfHost
public import Lanius.Faithful.SelfLive
public import Lanius.Faithful.SelfPanics
public import Lanius.Faithful.SelfAgree

@[expose] public section

/-! # Why Core's run of `w` fails (review #5, piece (c))

`selfCompiler_outcome` lets the self-built verified compiler fault when
Core's run of `w` fails at every fuel. `failing_short` says why that
happens: the cost semantics gives the pure compile no value at any fuel,
which with `plus` and `times` wrapping has one (`SelfPanics`), or
the output room is shorter than the binary's words, or the heap limit is
short, `limit < selfNext W room + h` for every cost `h` that `selfCost`
gives (`SelfShort`).

The top theorems `selfCompiler_reason`, `selfHost_fixpoint_reason` and
`selfHost_outcome_reason` are `selfCompiler_outcome`, `selfHost_fixpoint` and
`selfHost_outcome` with `SelfFaults` replaced by `SelfFaultReason`, which
adds that reason to the branch where Core's run fails at every fuel. -/

namespace Lanius.Faithful.SelfShort

open Lanius.Mini
open Lanius.X86.Machine
open Lanius.Faithful
open Lanius.Faithful.Self
open Lanius.Faithful.SelfDriver
open Lanius.Faithful.SelfCompiler
open Lanius.Faithful.SelfLive
open Lanius.Faithful.SelfHost

/-- Why Core's run of `w` on the words `W` of `files`, with `room` output
words and heap limit `limit`, may fail at every fuel: the pure compile has no
cost at any fuel (`selfCost`: `oracle_read`'s `cons` calls, `grammar()`,
`front_end_words` and `compile_words`) because `plus` or `times` panics
(`SelfPanics`: with the two wrapping, it has a value), or `compileText files`'s binary has
more words than `room`, or it has a cost and the heap limit is short, below
`selfNext W room + h` for every cost `h` it has. -/
def SelfShort (files : List SourceFile) (room limit : Nat) : Prop :=
  SelfPanics.SelfPanics (filesWords files) ∨
  (∃ ws, binaryWords (compileText files) = some ws ∧ room < ws.length) ∨
  ((∃ N h, selfCost N (filesWords files) = some h) ∧
    ∀ N h, selfCost N (filesWords files) = some h → limit < selfNext (filesWords files) room + h)

/-- **Core's run of `w` fails only for a reason.** When Core's run of `w`
on `selfStart` fails at every fuel (it diverges, stops at a trap, or ends
with the heap past `limit`), one of `SelfShort`'s reasons holds. -/
theorem failing_short {files : List SourceFile} (fit : FilesFit files)
    (wordsLt : (filesWords files).length < 2 ^ 31) {room limit : Nat} (roomLt : room < 2 ^ 31)
    (small : limit < 2 ^ 62) (fails : ∀ fuel, Failing limit (selfRun (filesWords files) room fuel)) :
    SelfShort files room limit := by
  have nonempty := filesWords_pos files
  by_cases costs : ∃ N h, selfCost N (filesWords files) = some h
  · by_cases fits : ∀ ws, binaryWords (compileText files) = some ws → ws.length ≤ room
    · by_cases short : ∀ N h, selfCost N (filesWords files) = some h →
          limit < selfNext (filesWords files) room + h
      · exact .inr (.inr ⟨costs, short⟩)
      · exfalso
        obtain ⟨N, h, cost, within⟩ : ∃ N h, selfCost N (filesWords files) = some h ∧
            selfNext (filesWords files) room + h ≤ limit := by
          refine Classical.byContradiction fun none => short fun N h cost => ?_
          exact Nat.lt_of_not_le fun le => none ⟨N, h, cost, le⟩
        obtain ⟨v, st', ⟨K, run⟩, next⟩ := driver_live (st := selfStart (filesWords files) room)
          (inp := selfInput) (outp := selfOutput (filesWords files)) (N := N) (h := h)
          (start_inv nonempty) wordsLt roomLt (start_reads wordsLt) start_readable
          (.inr (start_range_input nonempty))
          (if h : room = 0 then .inl h else .inr (start_range_output (Nat.pos_of_ne_zero h)))
          rfl cost (by show selfNext (filesWords files) room + h ≤ 2 ^ 64; omega)
          (fun ws words => fits ws (by rw [← compileWords_files fit]; exact words))
        have fail := fails K
        rw [show selfRun (filesWords files) room K = .done v st' from run K (Nat.le_refl K)] at fail
        have start : (selfStart (filesWords files) room).heap.nextAddress = selfNext (filesWords files) room := rfl
        rw [start] at next
        simp only [Failing] at fail
        exact Nat.lt_irrefl _ (Nat.lt_of_lt_of_le fail (Nat.le_trans next within))
    · refine .inr (.inl ?_)
      refine Classical.byContradiction fun none => fits fun ws words => ?_
      exact Nat.le_of_not_lt fun lt => none ⟨ws, words, lt⟩
  · refine .inl (SelfPanics.selfPanics fun N => ?_)
    cases cost : selfCost N (filesWords files) with
    | none => rfl
    | some h => exact absurd ⟨N, h, cost⟩ costs

#print axioms failing_short

/-- How the self-built verified compiler's run of `w` on `files` may fault,
with the reason: it faults, and either Core's run of `w` fails at every fuel
for one of `SelfShort`'s reasons (no pure cost, because `plus` or `times`
panics; the room short; or the heap limit below `selfNext W room + h` for
every cost `h`), or Core's run completes
within `limit` and the stack `window` is below what the compiled run needs. -/
def SelfFaultReason (files : List SourceFile) (room limit window : Nat) (B : Binary) (s : State) : Prop :=
  ((∀ fuel, Failing limit (selfRun (filesWords files) room fuel)) ∧ SelfShort files room limit ∧ Faults s) ∨
  ∃ fuel v final depth, selfRun (filesWords files) room fuel = .done v final ∧
    final.heap.nextAddress ≤ limit ∧ window < B.stackNeed depth ∧ Faults s

theorem faults_reason {files : List SourceFile} {B : Binary} {s : State} (fit : FilesFit files)
    (wordsLt : (filesWords files).length < 2 ^ 31) {room limit window : Nat} (roomLt : room < 2 ^ 31)
    (small : limit < 2 ^ 62) (faults : SelfFaults files room limit window B s) :
    SelfFaultReason files room limit window B s := by
  rcases faults with ⟨fails, faults⟩ | stack
  · exact .inl ⟨fails, failing_short fit wordsLt roomLt small fails, faults⟩
  · exact .inr stack

/-- **The self-built verified compiler, with why it faults.**
`selfCompiler_outcome`, where a fault because Core's run of `w` fails at
every fuel comes with `SelfShort`'s reason: the pure compile has no cost
because `plus` or `times` panics, or the output room is short, or the heap limit is short,
`limit < selfNext W room + h` for every cost `h` of `selfCost`. -/
theorem selfCompiler_reason {B : Binary} (compiled : compileSource prog = some B) {files : List SourceFile}
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
    SelfFaultReason files room limit window B s ∨
    ∃ n s' results after, Steps n s s' ∧ Det n s s' ∧ Returned window s s' results after ∧
      SelfOutput (compileText files) (filesWords files) s s' :=
  (selfCompiler_outcome compiled fit wordsLt roomLt enough small s imageBase window bounded loaded apart imageHeap
    entry params heapAt stack).imp_left (faults_reason fit wordsLt roomLt small)

/-- **The verified compiler self-hosts, with why it faults.**
`selfHost_fixpoint`, with `SelfFaults` replaced by `SelfFaultReason`. -/
theorem selfHost_fixpoint_reason {self : List SourceFile} {B : Binary}
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
    (SelfFaultReason self room limit window B s ∨
      ∃ n s' results after, Steps n s s' ∧ Det n s s' ∧ Returned window s s' results after ∧
        SelfOutput (some B) (filesWords self) s s') := by
  obtain ⟨reading, unique, outcome⟩ := selfHost_fixpoint read compiled fit wordsLt roomLt enough small
    s imageBase window bounded loaded apart imageHeap entry params heapAt stack
  exact ⟨reading, unique, outcome.imp_left (faults_reason fit wordsLt roomLt small)⟩

/-- The self-built verified compiler, built from its own source text, on any
source files, with why it faults: `selfHost_outcome`, with `SelfFaults`
replaced by `SelfFaultReason`. -/
theorem selfHost_outcome_reason {self : List SourceFile} {B : Binary}
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
    SelfFaultReason files room limit window B s ∨
    ∃ n s' results after, Steps n s s' ∧ Det n s s' ∧ Returned window s s' results after ∧
      SelfOutput (compileText files) (filesWords files) s s' :=
  selfCompiler_reason (compileSource_of_text read compiled) fit wordsLt roomLt enough small
    s imageBase window bounded loaded apart imageHeap entry params heapAt stack

#print axioms selfCompiler_reason
#print axioms selfHost_fixpoint_reason
#print axioms selfHost_outcome_reason

end Lanius.Faithful.SelfShort
