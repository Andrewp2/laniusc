import Lanius.Semantics.CellInventory
import Lanius.Semantics.InvariantAutomation

namespace Lanius.Semantics

open Lanius.Core

/-- The inventory law applies to normal returns, traps and host exits.
    Exhaustion does not expose a state. -/
def Outcome.PreservesInventory (before : CellInventory) : Outcome α → Prop
  | .done _ after | .trapped _ after | .exited _ after => before.Extends after.cellInventory
  | .outOfFuel => True

private def exceptInventory (before : CellInventory) : Except ε State → Prop
  | .ok after => before.Extends after.cellInventory
  | .error _ => True

private def optionInventory (before : CellInventory) : Option State → Prop
  | some after => before.Extends after.cellInventory
  | none => True

private theorem outcomeDone : (Outcome.done value after).PreservesInventory before =
    before.Extends after.cellInventory := rfl
private theorem outcomeTrapped : (Outcome.trapped reason after : Outcome α).PreservesInventory before =
    before.Extends after.cellInventory := rfl
private theorem outcomeExited : (Outcome.exited code after : Outcome α).PreservesInventory before =
    before.Extends after.cellInventory := rfl
private theorem outcomePending : (Outcome.outOfFuel : Outcome α).PreservesInventory before = True := rfl
private theorem exceptDone : exceptInventory before (.ok after : Except ε State) =
    before.Extends after.cellInventory := rfl
private theorem exceptError : exceptInventory before (.error reason : Except ε State) = True := rfl
private theorem optionDone : optionInventory before (some after) = before.Extends after.cellInventory := rfl
private theorem optionEmpty : optionInventory before none = True := rfl

open Lean Meta Elab Tactic in
/-- Follow known result-state edges backwards, rather than guessing intermediate
    inventories. Allocation steps and transitivity produce the final proof. -/
private partial def extensionProof (before after : Lean.Expr)
    (edges : Array (Lean.Expr × Lean.Expr))
    (visited : Array Lean.Expr := #[]) : MetaM (Option Lean.Expr) := do
  let before ← whnf before
  let after ← whnf after
  if ← withTransparency .reducible (isDefEq before after) then
    return some (← mkAppM ``CellInventory.Extends.refl #[before])
  if visited.contains after then return none
  let visited := visited.push after
  let follow (proof : Lean.Expr) : MetaM (Option Lean.Expr) := do
    let type := (← inferType proof).consumeMData
    unless type.isAppOfArity ``CellInventory.Extends 2 do return none
    let args := type.getAppArgs
    let final ← whnf args[1]!
    unless ← withTransparency .reducible (isDefEq final after) do return none
    let some initialProof ← extensionProof before args[0]! edges visited | return none
    return some (← mkAppM ``CellInventory.Extends.trans #[initialProof, proof])
  for (proof, final) in edges do
    if ← withTransparency .reducible (isDefEq final after) then
      if let some proof ← follow proof then return some proof
  for (operation, theoremName, arity) in
      [( ``State.bindLocal, ``State.cellInventory_bindLocal, 3),
       ( ``State.bindUninitialized, ``State.cellInventory_bindUninitialized, 2),
       ( ``State.bindLocals, ``State.cellInventory_bindLocals, 2),
       ( ``State.allocateTemporary, ``State.cellInventory_allocateTemporary, 2)] do
    if let some call := after.find? (fun e => !e.hasLooseBVars && e.isAppOfArity operation arity) then
      if let some proof ← follow (← mkAppM theoremName call.getAppArgs) then return some proof
  if after.isAppOfArity ``CellInventory.mk 2 then
    let ids := after.getAppArgs[0]!.consumeMData
    if ids.isAppOfArity ``List.append 3 || ids.isAppOfArity ``HAppend.hAppend 6 then
      let args := ids.getAppArgs
      let suffix ← whnf args.back!
      if suffix.isAppOfArity ``List.cons 3 then
        let initial ← mkAppM ``CellInventory.mk #[args[args.size - 2]!, suffix.getAppArgs[1]!]
        if let some proof ← follow (← mkAppM ``CellInventory.Extends.append #[initial]) then return some proof
  return none

open Lean Meta Elab Tactic in
private def closeExtension : TacticM Unit := withMainContext do
  let goal ← getMainGoal
  let target := (← instantiateMVars (← goal.getType)).consumeMData
  unless target.isAppOfArity ``CellInventory.Extends 2 do throwError "not an inventory goal"
  let mut edges := #[]
  for declaration in ← getLCtx do
    let type := declaration.type.consumeMData
    if type.isAppOfArity ``CellInventory.Extends 2 then
      let args := type.getAppArgs
      edges := edges.push (declaration.toExpr, ← whnf args[1]!)
  let some proof ← extensionProof target.getAppArgs[0]! target.getAppArgs[1]! edges |
    throwError "no directed allocation chain:\n{MessageData.ofGoal goal}"
  goal.assign proof
  replaceMainGoal []

open Lean Meta Elab Tactic in
elab "inventory_chain" : tactic => closeExtension

open Lean Meta Elab Tactic in
elab "inventory_result" "[" contracts:term,* "]" : tactic => do
  let normalize ← `(tactic| try simp_all only [outcomeDone, outcomeTrapped,
    outcomeExited, outcomePending, exceptDone, exceptError, optionDone, optionEmpty,
    restoreOutcomeLocals, restoreLocals, replaceCell_ids,
    List.map_append, List.map_cons, List.map_nil,
    Nat.succ.injEq, Nat.add_one, Outcome.done.injEq, Outcome.trapped.injEq,
    Outcome.exited.injEq, Except.ok.injEq, Except.error.injEq, Option.some.injEq,
    reduceCtorEq, Bind.bind, Pure.pure, Except.bind, Except.pure])
  let finish ← `(tactic| try inventory_chain)
  Automation.solveInvariant #[``Outcome.PreservesInventory, ``exceptInventory, ``optionInventory]
    normalize finish (contracts.getElems.map (fun term => term.raw))

private theorem assignCellInventory (state : State) (id : CellId) (value : Value) :
    optionInventory state.cellInventory (state.assignCell id value) := by
  unfold State.assignCell
  split
  · simpa only [optionInventory, State.cellInventory, replaceCell_ids] using
      CellInventory.Extends.refl state.cellInventory
  · trivial

private theorem writePlaceInventory (state : State) (place : ResolvedPlace) (value : Value) :
    exceptInventory state.cellInventory (writeResolvedPlace state place value) := by
  unfold writeResolvedPlace
  inventory_result [assignCellInventory]

private theorem writeNativePlaceInventory (program : Program) (state : State)
    (place : ResolvedPlace) (value : Value) :
    exceptInventory state.cellInventory (writeResolvedPlaceNative program state place value) := by
  unfold writeResolvedPlaceNative
  inventory_result [writePlaceInventory]

private theorem syncToInventory (views : List I32ArrayView) (state : State) :
    exceptInventory state.cellInventory (syncI32ViewsToHeapFrom views state) := by
  induction views generalizing state with
  | nil => exact CellInventory.Extends.refl _
  | cons view views ih =>
    rw [syncI32ViewsToHeapFrom]
    inventory_result [ih]

private theorem syncFromInventory (views : List I32ArrayView) (state : State) :
    exceptInventory state.cellInventory (syncI32ViewsFromHeapFrom views state) := by
  induction views generalizing state with
  | nil => exact CellInventory.Extends.refl _
  | cons view views ih =>
    rw [syncI32ViewsFromHeapFrom]
    inventory_result [writePlaceInventory, ih]

private theorem syncTo (state : State) :
    exceptInventory state.cellInventory (syncI32ViewsToHeap state) := syncToInventory _ _

private theorem syncFrom (state : State) :
    exceptInventory state.cellInventory (syncI32ViewsFromHeap state) := syncFromInventory _ _

private theorem arrayViewInventory (state : State) (root : CellId)
    (projections : List ValueProjection) (elements : List Value) :
    (mapI32ArrayView state root projections elements).PreservesInventory state.cellInventory := by
  unfold mapI32ArrayView
  inventory_result [syncTo]

private theorem rawSliceInventory (state : State) (address : Address) (length : Int) :
    (mapRawI32Slice state address length).PreservesInventory state.cellInventory := by
  unfold mapRawI32Slice
  inventory_result []

private theorem nominalSliceInventory (program : Program) (state : State)
    (element : Ty) (address : Address) (length : Int) :
    (mapRawNominalSlice program state element address length).PreservesInventory state.cellInventory := by
  unfold mapRawNominalSlice
  inventory_result []

private theorem slicePointerInventory (state : State) (cell : CellId)
    (projections : List ValueProjection) (start length : Nat) :
    (mapI32SliceDataPtr state cell projections start length).PreservesInventory state.cellInventory := by
  unfold mapI32SliceDataPtr
  inventory_result [arrayViewInventory]

private theorem stringPointerInventory (state : State) (value : String) :
    (mapStringDataPtr state value).PreservesInventory state.cellInventory := by
  unfold mapStringDataPtr
  inventory_result []

private theorem worldOutcomeInventory (id : FunctionId) (state : State) (result : Lanius.World.EffectResult) :
    (worldCallOutcome id state result).PreservesInventory state.cellInventory := by
  unfold worldCallOutcome
  inventory_result [syncFrom]

private theorem opaqueOutcomeInventory (id : ExternId) (state : State) (result : Lanius.World.OpaqueCallResult) :
    (opaqueCallOutcome id state result).PreservesInventory state.cellInventory := by
  unfold opaqueCallOutcome
  inventory_result [syncFrom]

private structure AllocationInvariant (fuel : Nat) : Prop where
  expression : ∀ program state expression,
    (evalExpr fuel program state expression).PreservesInventory state.cellInventory
  expressions : ∀ program state expressions,
    (evalExprs fuel program state expressions).PreservesInventory state.cellInventory
  matching : ∀ program state value arms,
    (evalMatchArms fuel program state value arms).PreservesInventory state.cellInventory
  place : ∀ program state access place,
    (evalPlace fuel program state access place).PreservesInventory state.cellInventory
  valuesLoop : ∀ program state id values body,
    (execForValues fuel program state id values body).PreservesInventory state.cellInventory
  rangeLoop : ∀ program state id current stop inclusive body,
    (execForRange fuel program state id current stop inclusive body).PreservesInventory state.cellInventory
  statement : ∀ program state statement,
    (execStmt fuel program state statement).PreservesInventory state.cellInventory

private theorem allocationInvariant (fuel : Nat) : AllocationInvariant fuel := by
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
    all_goals inventory_result [ih.expression, ih.expressions, ih.matching, ih.place,
      ih.valuesLoop, ih.rangeLoop, ih.statement, writeNativePlaceInventory, syncTo,
      syncFrom, arrayViewInventory, rawSliceInventory, nominalSliceInventory,
      slicePointerInventory, stringPointerInventory, worldOutcomeInventory, opaqueOutcomeInventory]

theorem evalExpr_preservesInventory :
    (evalExpr fuel program state expression).PreservesInventory state.cellInventory :=
  (allocationInvariant fuel).expression _ _ _

theorem evalExprs_preservesInventory :
    (evalExprs fuel program state expressions).PreservesInventory state.cellInventory :=
  (allocationInvariant fuel).expressions _ _ _

theorem evalMatchArms_preservesInventory :
    (evalMatchArms fuel program state value arms).PreservesInventory state.cellInventory :=
  (allocationInvariant fuel).matching _ _ _ _

theorem evalPlace_preservesInventory :
    (evalPlace fuel program state access place).PreservesInventory state.cellInventory :=
  (allocationInvariant fuel).place _ _ _ _

theorem execForValues_preservesInventory {id : VarId} :
    (execForValues fuel program state id values body).PreservesInventory state.cellInventory :=
  (allocationInvariant fuel).valuesLoop _ _ _ _ _

theorem execForRange_preservesInventory {id : VarId} :
    (execForRange fuel program state id current stop inclusive body).PreservesInventory state.cellInventory :=
  (allocationInvariant fuel).rangeLoop _ _ _ _ _ _ _

theorem execStmt_preservesInventory :
    (execStmt fuel program state statement).PreservesInventory state.cellInventory :=
  (allocationInvariant fuel).statement _ _ _

theorem evalExpr_inventory (run : evalExpr fuel program state expression = .done value after) :
    state.cellInventory.Extends after.cellInventory := by
  simpa only [run, Outcome.PreservesInventory] using
    (evalExpr_preservesInventory (fuel := fuel) (program := program) (state := state) (expression := expression))

theorem execStmt_inventory (run : execStmt fuel program state statement = .done completion after) :
    state.cellInventory.Extends after.cellInventory := by
  simpa only [run, Outcome.PreservesInventory] using
    (execStmt_preservesInventory (fuel := fuel) (program := program) (state := state) (statement := statement))

theorem Evaluates.inventory (run : Evaluates program state expression value after) :
    state.cellInventory.Extends after.cellInventory := by
  obtain ⟨_, run⟩ := run
  exact evalExpr_inventory run

theorem Executes.inventory (run : Executes program state statement completion after) :
    state.cellInventory.Extends after.cellInventory := by
  obtain ⟨_, run⟩ := run
  exact execStmt_inventory run

theorem Evaluates.cellsWellFormed (run : Evaluates program state expression value after)
    (formed : state.CellsWellFormed) : after.CellsWellFormed :=
  run.inventory.cellsWellFormed formed

theorem Executes.cellsWellFormed (run : Executes program state statement completion after)
    (formed : state.CellsWellFormed) : after.CellsWellFormed :=
  run.inventory.cellsWellFormed formed

#print axioms evalExpr_preservesInventory
#print axioms execStmt_preservesInventory
#print axioms Evaluates.cellsWellFormed

end Lanius.Semantics
