import Lanius.Semantics.EffectProof
import Lanius.Semantics.CallProof
import Lanius.Semantics.RawStore
import Lanius.Memory.Read
import Lanius.Memory.Footprint

namespace Lanius.Semantics.EffectProofTests

open Lanius.Core Lanius.Memory

private def pointer : Value := .rawSlice (.scalar (.signed .i32)) 4 1
private def writer : Function := {
  id := 7
  parameters := [(10, .slice (.scalar (.signed .i32)))]
  returnType := .unit
  body := some (.returnValue (some
    (.assign .set (.index (.local 10) (.value (.signed .i32 0)))
      (.value (.signed .i32 13))))) }
private def pointerArgument : Function := {
  id := 8
  parameters := [(11, .slice (.scalar (.signed .i32)))]
  returnType := .slice (.scalar (.signed .i32))
  body := some (.letLocal 10 (.scalar .bool) (.value (.boolean false))
    (.returnValue (some (.local 11)))) }
private def multiWriter : Function := {
  id := 9
  parameters := [(10, .slice (.scalar (.signed .i32))), (12, .scalar (.signed .i32))]
  returnType := .unit
  body := some (.returnValue (some
    (.assign .set (.index (.local 10) (.value (.signed .i32 0))) (.local 12)))) }
private def program : Program := { functions := [writer, pointerArgument, multiWriter] }
private def writes (old heap : Heap) : Prop := BytesWrite old heap 4 (i32Bytes 13)
private def initial : State := {
  locals := [(10, 0)]
  cells := [{ id := 0, value := some (.boolean true) }]
  nextCell := 1
  heap := {
    blocks := [{ base := 4, size := 4, alignment := 4, bytes := [0, 0, 0, 0], owned := true }]
    nextAddress := 8 } }

-- The selected arm calls an actual native writer. Its contract is proved
-- from storage permissions, not supplied as an expected execution result.
private theorem actualWriter (state : State) (formed : state.CellsWellFormed)
    (room : state.heap.Readable 4 4) (unique : HeapBlockBasesUnique state.heap)
    (noViews : state.i32ArrayViews = []) :
    ∃ after, RunsExpr program state (.call 7 [.value pointer]) .unit after ∧
      MemoryEffect writes state after := by
  core_call_framed (RunsExpr.callEffect (MemoryEffect.scopeStable writes)) writer as callee
  have source : callee.local? 10 = some pointer := by core_bound_local
  obtain ⟨heap, run, written⟩ := RunsExpr.assignRawI32
    (program := program) (before := callee) (indexed := callee) (ready := callee)
    (position := 0) (value := 13) (indexExpression := .value (.signed .i32 0))
    (expression := .value (.signed .i32 13)) source (by core_run) (by decide)
    room unique noViews (by core_run)
  apply RunsStmt.returnEffect
  exact ⟨{ callee with heap }, run,
    ⟨⟨[], by simp only [List.append_nil]; rfl, Nat.le_refl _, by simp⟩,
      rfl, rfl, written⟩⟩

private def arms : List (Pattern × Expr) :=
  [(.enumVariant 8 0 [], .call 7 [.value pointer]),
   (.enumVariant 8 1 [.bind 10], .call 7 [.local 10]),
   (.wildcard, .call 999 [])]
private def expression (payload : Bool) : Expr :=
  .matchValue (.value (if payload then .enumeration 8 1 [pointer] else .enumeration 8 0 [])) arms

-- Both tags execute the writer. The payload shadows caller local 10;
-- the unselected missing callee is deliberately not given any contract.
theorem selectedMatchWrites (payload : Bool) :
    ∃ after, RunsExpr program initial (expression payload) .unit after ∧
      MemoryEffect writes initial after := by
  have formed : initial.CellsWellFormed := by simp [State.CellsWellFormed, initial]
  have room : initial.heap.Readable 4 4 :=
    Heap.Readable.of_loadBytes (show initial.heap.loadBytes 4 4 = .ok [0, 0, 0, 0] from rfl)
  have unique : HeapBlockBasesUnique initial.heap := by
    intro left hl right hr _
    simp only [initial, List.mem_singleton] at hl hr
    exact hl.trans hr.symm
  have noViews : initial.i32ArrayViews = [] := rfl
  cases payload
  · have branch := actualWriter initial formed room unique noViews
    simp only [expression, Bool.false_eq_true, ↓reduceIte]
    core_effect_expr
  · let bound := initial.bindLocals [(10, pointer)]
    have boundFormed : bound.CellsWellFormed := by core_formed
    have direct := actualWriter bound boundFormed room unique noViews
    have branch : ∃ after, RunsExpr program bound (.call 7 [.local 10]) .unit after ∧
        MemoryEffect writes bound after := by
      apply RunsExpr.argumentsEffect
      · core_arguments
      · exact direct
    simp only [expression, ↓reduceIte]
    core_effect_expr

theorem restoresShadowAndReadsBack (payload : Bool) :
    ∃ after, RunsExpr program initial (expression payload) .unit after ∧
      after.local? 10 = some (.boolean true) ∧
      after.heap.loadBytes 4 4 = .ok (i32Bytes 13) ∧ after.heap ≠ initial.heap := by
  obtain ⟨after, run, effect⟩ := selectedMatchWrites payload
  have read : after.heap.loadBytes 4 4 = .ok (i32Bytes 13) := by
    simpa only [i32Bytes, List.length_map, List.length_range] using effect.2.2.2.loadBytes
  refine ⟨after, run, effect.1.localFound run.choose_spec.2 10 (.boolean true) rfl, read, ?_⟩
  intro same
  rw [same] at read
  have old : initial.heap.loadBytes 4 4 = .ok [0, 0, 0, 0] := rfl
  rw [old] at read
  exact (show [0, 0, 0, 0] ≠ i32Bytes 13 by decide) (Except.ok.inj read)

@[core_pure_rule] private theorem actualPointerArgument (state : State)
    (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr program state (.call 8 [.value pointer]) pointer after ∧ PureFrame state after := by
  core_call_pure pointerArgument as callee
  core_pure

private theorem actualMultiWriter (state : State) (formed : state.CellsWellFormed)
    (room : state.heap.Readable 4 4) (unique : HeapBlockBasesUnique state.heap)
    (noViews : state.i32ArrayViews = []) :
    ∃ after, RunsExpr program state (.call 9 [.value pointer, .value (.signed .i32 13)]) .unit after ∧
      MemoryEffect writes state after := by
  core_call_framed (RunsExpr.callEffect (MemoryEffect.scopeStable writes)) multiWriter as callee
  have source : callee.local? 10 = some pointer := by core_bound_local
  obtain ⟨heap, run, written⟩ := RunsExpr.assignRawI32
    (program := program) (before := callee) (indexed := callee) (ready := callee)
    (position := 0) (value := 13) (indexExpression := .value (.signed .i32 0))
    (expression := .local 12) source (by core_run) (by decide)
    room unique noViews (by core_run)
  apply RunsStmt.returnEffect
  exact ⟨{ callee with heap }, run,
    ⟨⟨[], by simp only [List.append_nil]; rfl, Nat.le_refl _, by simp⟩,
      rfl, rfl, written⟩⟩

private def multiExpression : Expr :=
  .call 9 [.call 8 [.value pointer], .value (.signed .i32 13)]

-- The first argument performs a real read-only call with fresh parameter and
-- shadow cells. Its state cannot be identified with the caller's state.
theorem framedArgumentsWriteAndRestore :
    ∃ after, RunsExpr program initial multiExpression .unit after ∧
      MemoryEffect writes initial after ∧ after.locals = initial.locals ∧
      after.local? 10 = some (.boolean true) ∧
      after.heap.loadBytes 4 4 = .ok (i32Bytes 13) := by
  have formed : initial.CellsWellFormed := by simp [State.CellsWellFormed, initial]
  have room : initial.heap.Readable 4 4 :=
    Heap.Readable.of_loadBytes (show initial.heap.loadBytes 4 4 = .ok [0, 0, 0, 0] from rfl)
  have unique : HeapBlockBasesUnique initial.heap := by
    intro left hl right hr _
    simp only [initial, List.mem_singleton] at hl hr
    exact hl.trans hr.symm
  have noViews : initial.i32ArrayViews = [] := rfl
  have call (state : State) (same : state.heap = initial.heap)
      (formed : state.CellsWellFormed) (noViews : state.i32ArrayViews = []) :=
    actualMultiWriter state formed (by rw [same]; exact room) (by rw [same]; exact unique) noViews
  obtain ⟨after, run, effect⟩ : ∃ after, RunsExpr program initial multiExpression .unit after ∧
      MemoryEffect writes initial after := by
    unfold multiExpression
    core_effect_expr
  exact ⟨after, run, effect, run.choose_spec.2,
    effect.1.localFound run.choose_spec.2 10 (.boolean true) rfl,
    by simpa only [i32Bytes, List.length_map, List.length_range] using effect.2.2.2.loadBytes⟩

-- A wrong tag would enter the missing function; automation must not invent
-- its execution, or erase the actual native effect into heap equality.
example : True := by
  have formed : initial.CellsWellFormed := by simp [State.CellsWellFormed, initial]
  fail_if_success
    suffices wrong : ∃ after, RunsExpr program initial
        (.matchValue (.value (.enumeration 8 2 [])) arms) .unit after ∧
        MemoryEffect writes initial after by trivial
    core_effect_expr
  trivial

private def selectedStatement : Stmt :=
  .ifThenElse (.local 10) (.returnValue (some (.call 7 [.value pointer])))
    (.returnValue (some (.call 999 [])))
private def footprint (old heap : Heap) : Prop :=
  HeapWritesOn old heap (fun address => 4 ≤ address ∧ address < 8)

-- This is a proved statement cut, including a required local lookup. The
-- unselected arm is unavailable, so traversing it cannot establish the cut.
private theorem actualSelectedStatement (state : State) (same : state.heap = initial.heap)
    (formed : state.CellsWellFormed) (noViews : state.i32ArrayViews = [])
    (selected : state.local? 10 = some (.boolean true)) :
    ∃ after, RunsStmt program state selectedStatement (.returned (some .unit)) after ∧
      MemoryEffect footprint state after := by
  have room : state.heap.Readable 4 4 := by
    rw [same]
    exact Heap.Readable.of_loadBytes (show initial.heap.loadBytes 4 4 = .ok [0, 0, 0, 0] from rfl)
  have unique : HeapBlockBasesUnique state.heap := by
    rw [same]
    intro left hl right hr _
    simp only [initial, List.mem_singleton] at hl hr
    exact hl.trans hr.symm
  obtain ⟨after, run, effect⟩ := actualWriter state formed room unique noViews
  refine ⟨after, RunsStmt.ifThenElseTrue (by core_run) (RunsStmt.returnValue run),
    effect.1, effect.2.1, effect.2.2.1, ?_⟩
  simpa only [footprint, writes, i32Bytes, List.length_map, List.length_range] using
    effect.2.2.2.footprint

theorem forallStatementCutWrites :
    ∃ after, RunsStmt program initial selectedStatement (.returned (some .unit)) after ∧
      MemoryEffect footprint initial after := by
  have formed : initial.CellsWellFormed := by simp [State.CellsWellFormed, initial]
  have noViews : initial.i32ArrayViews = [] := rfl
  have selected : initial.local? 10 = some (.boolean true) := rfl
  have cut (state : State) (same : state.heap = initial.heap)
      (formed : state.CellsWellFormed) (views : state.i32ArrayViews = [])
      (selected : state.local? 10 = some (.boolean true)) :=
    actualSelectedStatement state same formed views selected
  fail_if_success
    suffices wrong : ∃ after, RunsStmt program initial selectedStatement
        (.returned (some (.signed .i32 0))) after ∧ MemoryEffect footprint initial after by trivial
    core_effect HeapWritesOn.trans
  fail_if_success
    suffices wrong : ∃ after, RunsStmt program { initial with heap := {} } selectedStatement
        (.returned (some .unit)) after ∧ MemoryEffect footprint { initial with heap := {} } after by trivial
    core_effect HeapWritesOn.trans
  core_effect HeapWritesOn.trans

#print axioms selectedMatchWrites
#print axioms restoresShadowAndReadsBack
#print axioms framedArgumentsWriteAndRestore
#print axioms forallStatementCutWrites

#eval do
  for payload in [false, true] do
    match evalExpr 100 program initial (expression payload) with
    | .done .unit after =>
      unless after.locals == initial.locals do throw (IO.userError "match leaked lexical payload binding")
      match after.local? 10, after.heap.loadBytes 4 4 with
      | some (.boolean true), .ok bytes =>
        unless bytes == i32Bytes 13 do throw (IO.userError "selected match did not retain native write")
      | _, _ => throw (IO.userError "selected match lost caller cell or native read-back")
    | _ => throw (IO.userError "selected match evaluated an unavailable arm")
  IO.println "actual match-effect fixtures: both tags, native write and shadow restoration passed"

#eval do
  let .done value middle := evalExpr 100 program initial (.call 8 [.value pointer])
    | throw (IO.userError "read-only argument call failed")
  unless value == pointer && (middle.heap.loadBytes 4 4).toOption == some [0, 0, 0, 0] &&
      middle.heap.nextAddress == initial.heap.nextAddress && middle.nextCell > initial.nextCell &&
      middle.locals == initial.locals && middle.local? 10 == some (Value.boolean true) do
    throw (IO.userError "argument call failed to create fresh cells and restore the caller")
  let .done .unit after := evalExpr 100 program initial multiExpression
    | throw (IO.userError "framed multi-argument native write failed")
  unless after.locals == initial.locals && after.local? 10 == some (Value.boolean true) &&
      after.nextCell > middle.nextCell && (after.heap.loadBytes 4 4).toOption == some (i32Bytes 13) do
    throw (IO.userError "framed arguments lost the heap effect or original caller cell")
  IO.println "actual framed-effect argument fixtures: fresh argument cells, native write and caller restoration passed"

end Lanius.Semantics.EffectProofTests
