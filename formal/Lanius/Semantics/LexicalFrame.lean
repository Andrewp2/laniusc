import Lanius.Semantics
import Lanius.Semantics.InvariantAutomation

namespace Lanius.Semantics

open Lanius.Core

/-- Every observable state retains these lexical bindings. Values in the
    referenced cells, the allocation frontier, heap and world may change. -/
def Outcome.PreservesLocals (locals : List (VarId × CellId)) : Outcome α → Prop
  | .done _ after | .trapped _ after | .exited _ after => after.locals = locals
  | .outOfFuel => True

private def exceptLocals (locals : List (VarId × CellId)) : Except ε State → Prop
  | .ok after => after.locals = locals
  | .error _ => True

private def optionLocals (locals : List (VarId × CellId)) : Option State → Prop
  | some after => after.locals = locals
  | none => True

private theorem outcomeDone : (Outcome.done value after).PreservesLocals locals =
    (after.locals = locals) := rfl
private theorem outcomeTrapped : (Outcome.trapped reason after : Outcome α).PreservesLocals locals =
    (after.locals = locals) := rfl
private theorem outcomeExited : (Outcome.exited code after : Outcome α).PreservesLocals locals =
    (after.locals = locals) := rfl
private theorem outcomePending : (Outcome.outOfFuel : Outcome α).PreservesLocals locals = True := rfl
private theorem exceptDone : exceptLocals locals (.ok after : Except ε State) =
    (after.locals = locals) := rfl
private theorem exceptError : exceptLocals locals (.error reason : Except ε State) = True := rfl
private theorem optionDone : optionLocals locals (some after) = (after.locals = locals) := rfl
private theorem optionEmpty : optionLocals locals none = True := rfl

private theorem outcomeRestore (caller : State) (result : Outcome α)
    (same : caller.locals = locals) :
    (restoreOutcomeLocals caller result).PreservesLocals locals := by
  subst locals
  cases result <;> first | rfl | trivial

open Lean Meta Elab Tactic in
private def solveLocals (contracts : Array Syntax) : TacticM Unit := do
  let normalize ← `(tactic| try simp_all only [outcomeDone, outcomeTrapped,
    outcomeExited, outcomePending, exceptDone, exceptError, optionDone, optionEmpty,
    outcomeRestore, restoreLocals, State.allocateTemporary,
    Nat.succ.injEq, Nat.add_one, Outcome.done.injEq, Outcome.trapped.injEq,
    Outcome.exited.injEq, Except.ok.injEq, Except.error.injEq, Option.some.injEq,
    reduceCtorEq, Bind.bind, Pure.pure, Except.bind, Except.pure])
  Automation.solveInvariant #[``Outcome.PreservesLocals, ``exceptLocals, ``optionLocals]
    normalize (← `(tactic| skip)) contracts

open Lean Meta Elab Tactic in
elab "locals_result" "[" contracts:term,* "]" : tactic => withMainContext do
  solveLocals (contracts.getElems.map (fun term => term.raw))

private theorem assignCellLocals (state : State) (id : CellId) (value : Value) :
    optionLocals state.locals (state.assignCell id value) := by
  unfold State.assignCell
  locals_result []

private theorem writePlaceLocals (state : State) (place : ResolvedPlace) (value : Value) :
    exceptLocals state.locals (writeResolvedPlace state place value) := by
  unfold writeResolvedPlace
  locals_result [assignCellLocals]

private theorem writeNativePlaceLocals (program : Program) (state : State)
    (place : ResolvedPlace) (value : Value) :
    exceptLocals state.locals (writeResolvedPlaceNative program state place value) := by
  unfold writeResolvedPlaceNative
  locals_result [writePlaceLocals]

private theorem syncToLocals (views : List I32ArrayView) (state : State) :
    exceptLocals state.locals (syncI32ViewsToHeapFrom views state) := by
  induction views generalizing state with
  | nil => rfl
  | cons view views ih =>
    rw [syncI32ViewsToHeapFrom]
    locals_result [ih]

private theorem syncFromLocals (views : List I32ArrayView) (state : State) :
    exceptLocals state.locals (syncI32ViewsFromHeapFrom views state) := by
  induction views generalizing state with
  | nil => rfl
  | cons view views ih =>
    rw [syncI32ViewsFromHeapFrom]
    locals_result [writePlaceLocals, ih]

private theorem syncTo (state : State) :
    exceptLocals state.locals (syncI32ViewsToHeap state) := syncToLocals _ _

private theorem syncFrom (state : State) :
    exceptLocals state.locals (syncI32ViewsFromHeap state) := syncFromLocals _ _

private theorem arrayViewLocals (state : State) (root : CellId)
    (projections : List ValueProjection) (elements : List Value) :
    (mapI32ArrayView state root projections elements).PreservesLocals state.locals := by
  unfold mapI32ArrayView
  locals_result [syncTo]

private theorem rawSliceLocals (state : State) (address : Address) (length : Int) :
    (mapRawI32Slice state address length).PreservesLocals state.locals := by
  unfold mapRawI32Slice
  locals_result []

private theorem nominalSliceLocals (program : Program) (state : State)
    (element : Ty) (address : Address) (length : Int) :
    (mapRawNominalSlice program state element address length).PreservesLocals state.locals := by
  unfold mapRawNominalSlice
  locals_result []

private theorem slicePointerLocals (state : State) (cell : CellId)
    (projections : List ValueProjection) (start length : Nat) :
    (mapI32SliceDataPtr state cell projections start length).PreservesLocals state.locals := by
  unfold mapI32SliceDataPtr
  locals_result [arrayViewLocals]

private theorem stringPointerLocals (state : State) (value : String) :
    (mapStringDataPtr state value).PreservesLocals state.locals := by
  unfold mapStringDataPtr
  locals_result []

private theorem worldOutcomeLocals (id : FunctionId) (state : State) (result : Lanius.World.EffectResult) :
    (worldCallOutcome id state result).PreservesLocals state.locals := by
  unfold worldCallOutcome
  locals_result [syncFrom]

private theorem opaqueOutcomeLocals (id : ExternId) (state : State) (result : Lanius.World.OpaqueCallResult) :
    (opaqueCallOutcome id state result).PreservesLocals state.locals := by
  unfold opaqueCallOutcome
  locals_result [syncFrom]

private structure LexicalInvariant (fuel : Nat) : Prop where
  expression : ∀ program state expression,
    (evalExpr fuel program state expression).PreservesLocals state.locals
  expressions : ∀ program state expressions,
    (evalExprs fuel program state expressions).PreservesLocals state.locals
  matching : ∀ program state value arms,
    (evalMatchArms fuel program state value arms).PreservesLocals state.locals
  place : ∀ program state access place,
    (evalPlace fuel program state access place).PreservesLocals state.locals
  valuesLoop : ∀ program state id values body,
    (execForValues fuel program state id values body).PreservesLocals state.locals
  rangeLoop : ∀ program state id current stop inclusive body,
    (execForRange fuel program state id current stop inclusive body).PreservesLocals state.locals
  statement : ∀ program state statement,
    (execStmt fuel program state statement).PreservesLocals state.locals

private theorem lexicalInvariant (fuel : Nat) : LexicalInvariant fuel := by
  induction fuel with
  | zero => constructor <;> intros <;> exact True.intro
  | succ fuel ih =>
    constructor
    all_goals intros
    all_goals simp only [Nat.add_one]
    all_goals first
      | rw [evalExpr.eq_def]
      | rw [evalExprs.eq_def]
      | rw [evalMatchArms.eq_def]
      | rw [evalPlace.eq_def]
      | rw [execForValues.eq_def]
      | rw [execForRange.eq_def]
      | rw [execStmt.eq_def]
    all_goals locals_result [ih.expression, ih.expressions, ih.matching, ih.place,
      ih.valuesLoop, ih.rangeLoop, ih.statement, writeNativePlaceLocals, syncTo,
      syncFrom, arrayViewLocals, rawSliceLocals, nominalSliceLocals,
      slicePointerLocals, stringPointerLocals, worldOutcomeLocals, opaqueOutcomeLocals]

theorem evalExpr_preservesLocals :
    (evalExpr fuel program state expression).PreservesLocals state.locals :=
  (lexicalInvariant fuel).expression _ _ _

theorem evalExprs_preservesLocals :
    (evalExprs fuel program state expressions).PreservesLocals state.locals :=
  (lexicalInvariant fuel).expressions _ _ _

theorem evalMatchArms_preservesLocals :
    (evalMatchArms fuel program state value arms).PreservesLocals state.locals :=
  (lexicalInvariant fuel).matching _ _ _ _

theorem evalPlace_preservesLocals :
    (evalPlace fuel program state access place).PreservesLocals state.locals :=
  (lexicalInvariant fuel).place _ _ _ _

theorem execForValues_preservesLocals {id : VarId} :
    (execForValues fuel program state id values body).PreservesLocals state.locals :=
  (lexicalInvariant fuel).valuesLoop _ _ _ _ _

theorem execForRange_preservesLocals {id : VarId} :
    (execForRange fuel program state id current stop inclusive body).PreservesLocals state.locals :=
  (lexicalInvariant fuel).rangeLoop _ _ _ _ _ _ _

theorem execStmt_preservesLocals :
    (execStmt fuel program state statement).PreservesLocals state.locals :=
  (lexicalInvariant fuel).statement _ _ _

theorem evalExpr_locals (run : evalExpr fuel program state expression = .done value after) :
    after.locals = state.locals := by
  simpa only [run, Outcome.PreservesLocals] using
    (evalExpr_preservesLocals (fuel := fuel) (program := program) (state := state) (expression := expression))

theorem execStmt_locals (run : execStmt fuel program state statement = .done completion after) :
    after.locals = state.locals := by
  simpa only [run, Outcome.PreservesLocals] using
    (execStmt_preservesLocals (fuel := fuel) (program := program) (state := state) (statement := statement))

theorem Evaluates.locals (run : Evaluates program state expression value after) :
    after.locals = state.locals := by
  obtain ⟨_, run⟩ := run
  exact evalExpr_locals run

theorem Executes.locals (run : Executes program state statement completion after) :
    after.locals = state.locals := by
  obtain ⟨_, run⟩ := run
  exact execStmt_locals run

#print axioms evalExpr_preservesLocals
#print axioms execStmt_preservesLocals
#print axioms Evaluates.locals

end Lanius.Semantics
