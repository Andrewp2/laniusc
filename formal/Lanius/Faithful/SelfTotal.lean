import Lanius.Faithful.SelfShort
import Lanius.Faithful.SelfAgree

/-! # Why Core's run of `w` fails, without the panic reason (F14)

`SelfShort`'s first reason is that `plus` or `times` panics. This file
replaces it by a reason about the heap, under one premise left open
(`CompileBounded`): when `progW`'s compile (`plus` and `times` wrapping) costs
less than `2 ^ 62`, its guarded run (`pcallG progW prims safeW`, no `plus`
or `times` wraps) has a value. Then the self program's compile has a value
and a cost (`SelfAgree.qcall_of_safe`), so when it has no cost, `progW`'s
compile, which always has one (`costW_total`), costs at least `2 ^ 62`,
past any heap limit `failing_short` allows (`SelfShortW`,
`failing_short_of`). -/

namespace Lanius.Faithful.SelfTotal

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

/-- `selfCost` of `progW`: the heap cost of the wrapped compile. -/
def costW (N : Nat) (W : List (BitVec 32)) : Option Nat :=
  (qcall progW prims (boxCost prog) N 8 []).bind fun g =>
  (qcall progW prims (boxCost prog) N 7 [g.1, listVal W]).bind fun fe =>
  (qcall progW prims (boxCost prog) N 6 [fe.1]).bind fun cw =>
  some (W.length * consCost + g.2 + fe.2 + cw.2)

/-- `compileW` with no `plus` or `times` wrapping. -/
noncomputable def compileG (N : Nat) (W : List (BitVec 32)) : Option Value :=
  (pcallG progW prims safeW N 8 []).bind fun g =>
  (pcallG progW prims safeW N 7 [g, listVal W]).bind fun fe =>
  pcallG progW prims safeW N 6 [fe]

/-- The premise left open: a wrapped compile that costs less than `2 ^ 62`
wraps no `plus` or `times`. -/
def CompileBounded (W : List (BitVec 32)) : Prop :=
  ∀ N k, costW N W = some k → k < 2 ^ 62 → ∃ N' v, compileG N' W = some v

/-- The wrapped compile has a cost. -/
theorem costW_total (W : List (BitVec 32)) : ∃ N k, costW N W = some k := by
  obtain ⟨N, v, hv⟩ := compileW_total W
  simp only [compileW] at hv
  cases h8 : pcall progW prims N 8 [] with
  | none => rw [h8] at hv; cases hv
  | some g =>
    rw [h8] at hv
    simp only [Option.bind_some] at hv
    cases h7 : pcall progW prims N 7 [g, listVal W] with
    | none => rw [h7] at hv; cases hv
    | some fe =>
      rw [h7] at hv
      simp only [Option.bind_some] at hv
      obtain ⟨k8, q8⟩ := qcall_of_pcall (boxCost prog) h8
      obtain ⟨k7, q7⟩ := qcall_of_pcall (boxCost prog) h7
      obtain ⟨k6, q6⟩ := qcall_of_pcall (boxCost prog) hv
      exact ⟨N, W.length * consCost + k8 + k7 + k6, by simp [costW, q8, q7, q6]⟩

/-- A guarded compile with a value gives the self program's compile a cost. -/
theorem selfCost_of_compileG {N : Nat} {W : List (BitVec 32)} {v : Value} (h : compileG N W = some v) :
    ∃ k, selfCost N W = some k := by
  simp only [compileG] at h
  cases h8 : pcallG progW prims safeW N 8 [] with
  | none => rw [h8] at h; cases h
  | some g =>
    rw [h8] at h
    simp only [Option.bind_some] at h
    cases h7 : pcallG progW prims safeW N 7 [g, listVal W] with
    | none => rw [h7] at h; cases h
    | some fe =>
      rw [h7] at h
      simp only [Option.bind_some] at h
      obtain ⟨k8, q8, -⟩ := qcall_of_safe (boxCost prog) h8
      obtain ⟨k7, q7, -⟩ := qcall_of_safe (boxCost prog) h7
      obtain ⟨k6, q6, -⟩ := qcall_of_safe (boxCost prog) h
      exact ⟨W.length * consCost + k8 + k7 + k6, by simp [selfCost, q8, q7, q6]⟩

/-- `SelfShort` with the panic reason replaced: the output room is short, or
the heap limit is short of the self program's compile, or the self program's
compile has no cost and the wrapped one costs at least `2 ^ 62`. -/
def SelfShortW (files : List SourceFile) (room limit : Nat) : Prop :=
  (∃ ws, binaryWords (compileText files) = some ws ∧ room < ws.length) ∨
  ((∃ N h, selfCost N (filesWords files) = some h) ∧
    ∀ N h, selfCost N (filesWords files) = some h → limit < selfNext (filesWords files) room + h) ∨
  ((∀ N, selfCost N (filesWords files) = none) ∧ (∃ N k, costW N (filesWords files) = some k) ∧
    ∀ N k, costW N (filesWords files) = some k → 2 ^ 62 ≤ k)

/-- **Core's run of `w` fails only for a reason, the panic reason replaced by
the wrapped compile's cost**, under `CompileBounded`. -/
theorem failing_short_of {files : List SourceFile} (safe : CompileBounded (filesWords files)) (fit : FilesFit files)
    (wordsLt : (filesWords files).length < 2 ^ 31) {room limit : Nat} (roomLt : room < 2 ^ 31)
    (small : limit < 2 ^ 62) (fails : ∀ fuel, Failing limit (selfRun (filesWords files) room fuel)) :
    SelfShortW files room limit := by
  rcases failing_short fit wordsLt roomLt small fails with panics | room | heap
  · refine .inr (.inr ⟨panics.1, costW_total _, fun N k hk => ?_⟩)
    refine Nat.le_of_not_lt fun lt => ?_
    obtain ⟨N', v, hv⟩ := safe N k hk lt
    obtain ⟨c, hc⟩ := selfCost_of_compileG hv
    rw [panics.1 N'] at hc
    cases hc
  · exact .inl room
  · exact .inr (.inl heap)

#print axioms failing_short_of

/-- `SelfFaultReason` with `SelfShortW` for `SelfShort`. -/
def SelfFaultReasonW (files : List SourceFile) (room limit window : Nat) (B : Binary) (s : State) : Prop :=
  ((∀ fuel, Failing limit (selfRun (filesWords files) room fuel)) ∧ SelfShortW files room limit ∧ Faults s) ∨
  ∃ fuel v final depth, selfRun (filesWords files) room fuel = .done v final ∧
    final.heap.nextAddress ≤ limit ∧ window < B.stackNeed depth ∧ Faults s

/-- **The self-built verified compiler, with why it faults, no panic reason
among them, under `CompileBounded`.** `selfCompiler_reason` with `SelfShortW`:
a fault because Core's run of `w` fails at every fuel comes with the room
short, the heap limit short of the compile's cost, or the compile's `plus` or
`times` wrapping only in a compile that costs at least `2 ^ 62`. Conditional:
`CompileBounded` is the open part of F14. -/
theorem selfCompiler_total_reason_of_bounds {B : Binary} (compiled : compileSource prog = some B)
    {files : List SourceFile} (bounds : CompileBounded (filesWords files))
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
    SelfFaultReasonW files room limit window B s ∨
    ∃ n s' results after, Steps n s s' ∧ Det n s s' ∧ Returned window s s' results after ∧
      SelfOutput (compileText files) (filesWords files) s s' :=
  (selfCompiler_outcome compiled fit wordsLt roomLt enough small s imageBase window bounded loaded apart imageHeap
    entry params heapAt stack).imp_left fun
    | .inl ⟨fails, faults⟩ => .inl ⟨fails, failing_short_of bounds fit wordsLt roomLt small fails, faults⟩
    | .inr stack => .inr stack

#print axioms selfCompiler_total_reason_of_bounds

end Lanius.Faithful.SelfTotal
