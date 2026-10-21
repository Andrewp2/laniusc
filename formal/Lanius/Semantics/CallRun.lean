import Lanius.Semantics.StmtList
import Lanius.Semantics.CallerFrame

namespace Lanius.Semantics

open Lanius.Core

/-- Argument evaluation may change memory; only the lexical scope is framed. -/
def RunsExprs (program : Program) (before : State) (arguments : List Expr)
    (values : List Value) (after : State) : Prop :=
  ∃ threshold, (∀ fuel, threshold ≤ fuel →
    evalExprs fuel program before arguments = .done values after) ∧
    after.locals = before.locals

/-- Argument evaluation also inherits the evaluator-wide allocation law. -/
theorem RunsExprs.cellsWellFormed (run : RunsExprs program before arguments values after)
    (formed : before.CellsWellFormed) : after.CellsWellFormed := by
  obtain ⟨fuel, evaluated, _⟩ := run
  have inventory := evalExprs_preservesInventory (fuel := fuel) (program := program)
    (state := before) (expressions := arguments)
  rw [evaluated fuel (Nat.le_refl _)] at inventory
  exact inventory.cellsWellFormed formed

theorem RunsExprs.nil : RunsExprs program state [] [] state := by
  refine ⟨1, ?_, rfl⟩
  intro fuel enough
  cases fuel with
  | zero => omega
  | succ fuel => rw [evalExprs.eq_def]

theorem RunsExprs.cons
    (head : RunsExpr program before expression value middle)
    (tail : RunsExprs program middle expressions values after) :
    RunsExprs program before (expression :: expressions) (value :: values) after := by
  obtain ⟨headFuel, headRun, headLocals⟩ := head
  obtain ⟨tailFuel, tailRun, tailLocals⟩ := tail
  refine ⟨max headFuel tailFuel + 1, ?_, tailLocals.trans headLocals⟩
  intro fuel enough
  have first := headRun (fuel - 1) (by omega)
  have rest := tailRun (fuel - 1) (by omega)
  rw [show fuel = (fuel - 1).succ by omega, evalExprs.eq_def]
  simp only [first, rest]

theorem RunsExprs.values (values : List Value) :
    RunsExprs program state (values.map Expr.value) values state := by
  induction values with
  | nil => exact .nil
  | cons value values rest => exact .cons (.ofStable .value rfl) rest

/-- Reuse a function's value-argument contract at an expression call site.
    Argument effects are proved first; the function body is not reopened. -/
theorem RunsExpr.callArguments
    (argumentsRun : RunsExprs program before arguments values middle)
    (callRun : RunsExpr program middle (.call functionId (values.map Expr.value)) result after) :
    RunsExpr program before (.call functionId arguments) result after := by
  obtain ⟨argumentFuel, argumentsRun, argumentLocals⟩ := argumentsRun
  obtain ⟨valueFuel, valuesRun, _⟩ := RunsExprs.values (program := program) (state := middle) values
  obtain ⟨callFuel, callRun, callLocals⟩ := callRun
  refine ⟨max callFuel (max argumentFuel valueFuel + 1), ?_, callLocals.trans argumentLocals⟩
  intro fuel enough
  have resultRun := callRun fuel (by omega)
  have argumentsEval := argumentsRun (fuel - 1) (by omega)
  have valuesEval := valuesRun (fuel - 1) (by omega)
  rw [show fuel = (fuel - 1).succ by omega, evalExpr.eq_def] at resultRun ⊢
  simpa only [argumentsEval, valuesEval] using resultRun

/-- Carry the proved body effects through a call without imposing purity.
    Argument effects precede parameter binding; the caller's scope is restored. -/
theorem RunsExpr.call
    (found : program.function? functionId = some function)
    (bodyFound : function.body = some body)
    (argumentsRun : RunsExprs program caller arguments values afterArguments)
    (parameters : bindParameters function.parameters values = some bindings)
    (bodyRun : RunsStmt program
      (({ afterArguments with locals := [] }).bindLocals bindings)
      body (.returned (some value)) completed) :
    RunsExpr program caller (.call functionId arguments) value
      (restoreLocals caller completed) := by
  obtain ⟨argumentsFuel, argumentsRun, locals⟩ := argumentsRun
  obtain ⟨bodyFuel, bodyRun, _⟩ := bodyRun
  refine ⟨max argumentsFuel bodyFuel + 1, ?_, rfl⟩
  intro fuel enough
  simpa only [show (fuel - 1).succ = fuel by omega, restoreLocals, locals] using
    evalExpr_call_internal (fuel - 1) program caller functionId arguments
      function body values bindings afterArguments completed value found bodyFound
      (argumentsRun (fuel - 1) (by omega)) parameters (bodyRun (fuel - 1) (by omega))

/-- Unit-returning bodies may fall through. Argument and body effects are
    retained, and only the caller's lexical scope is restored. -/
theorem RunsExpr.callUnit
    (found : program.function? functionId = some function)
    (bodyFound : function.body = some body) (returnsUnit : function.returnType = .unit)
    (argumentsRun : RunsExprs program caller arguments values afterArguments)
    (parameters : bindParameters function.parameters values = some bindings)
    (bodyRun : RunsStmt program (({ afterArguments with locals := [] }).bindLocals bindings)
      body .next completed) :
    RunsExpr program caller (.call functionId arguments) .unit (restoreLocals caller completed) := by
  obtain ⟨argumentsFuel, argumentsRun, locals⟩ := argumentsRun
  obtain ⟨bodyFuel, bodyRun, _⟩ := bodyRun
  refine ⟨max argumentsFuel bodyFuel + 1, ?_, rfl⟩
  intro fuel enough
  rw [show fuel = (fuel - 1).succ by omega, evalExpr.eq_def]
  simp only [argumentsRun (fuel - 1) (by omega), found, bodyFound, parameters,
    bodyRun (fuel - 1) (by omega), returnsUnit, ↓reduceIte, restoreLocals, locals]

/-- Carry a proved effectful body postcondition out of parameter scope.
    Scope invariance is proved by the client; heap/world effects are not erased. -/
theorem RunsExpr.callPost {post : Value → State → Prop}
    (found : program.function? functionId = some function)
    (bodyFound : function.body = some body)
    (parameters : bindParameters function.parameters values = some bindings)
    (bodyContract : ∃ value completed, RunsStmt program
      (({ caller with locals := [] }).bindLocals bindings) body (.returned (some value)) completed ∧
      FreshCellFrame (({ caller with locals := [] }).bindLocals bindings) completed ∧ post value completed)
    (scope : ∀ value completed, post value completed → post value (restoreLocals caller completed)) :
    ∃ value after, RunsExpr program caller (.call functionId (values.map Expr.value)) value after ∧
      FreshCellFrame caller after ∧ post value after := by
  obtain ⟨value, completed, run, cells, result⟩ := bodyContract
  have entry : FreshCellFrame caller (({ caller with locals := [] }).bindLocals bindings) :=
    (show FreshCellFrame caller { caller with locals := [] } from ⟨[], by simp, Nat.le_refl _, by simp⟩).trans
      (FreshCellFrame.bindLocals _ bindings)
  exact ⟨value, restoreLocals caller completed,
    RunsExpr.call found bodyFound (RunsExprs.values _) parameters run,
    (entry.trans cells).restoreLocals, scope value completed result⟩

/-- Heap/world/view postconditions survive lexical restoration automatically.
    The body must prove its actual effects and caller-cell frame. -/
theorem RunsExpr.callStores (post : Memory.Heap → World.State → List I32ArrayView → Prop)
    (found : program.function? functionId = some function)
    (bodyFound : function.body = some body)
    (parameters : bindParameters function.parameters values = some bindings)
    (contract : ∃ completed, RunsStmt program (({ caller with locals := [] }).bindLocals bindings)
      body (.returned (some value)) completed ∧
      FreshCellFrame (({ caller with locals := [] }).bindLocals bindings) completed ∧
      post completed.heap completed.world completed.i32ArrayViews) :
    ∃ after, RunsExpr program caller (.call functionId (values.map Expr.value)) value after ∧
      FreshCellFrame caller after ∧ post after.heap after.world after.i32ArrayViews := by
  obtain ⟨completed, run, cells, result⟩ := contract
  obtain ⟨returned, after, run, cells, same, result⟩ := RunsExpr.callPost found bodyFound parameters
    ⟨value, completed, run, cells, rfl, result⟩ (post := fun returned after =>
      returned = value ∧ post after.heap after.world after.i32ArrayViews) (fun _ _ result => result)
  subst returned
  exact ⟨after, run, cells, result⟩

/-- Compose an effectful initializer and a framed return through local scope.
    The postcondition must explicitly survive restoring locals. -/
theorem RunsStmt.letLocalPost {id : Lanius.VarId} {post : Value → State → Prop}
    (initial : RunsExpr program before initializer value ready)
    (initialCells : FreshCellFrame before ready)
    (bodyContract : ∃ result completed, RunsStmt program (ready.bindLocal id value)
      body (.returned (some result)) completed ∧ FreshCellFrame (ready.bindLocal id value) completed ∧ post result completed)
    (scope : ∀ result completed, post result completed → post result (restoreLocals ready completed)) :
    ∃ result after, RunsStmt program before (.letLocal id type initializer body) (.returned (some result)) after ∧
      FreshCellFrame before after ∧ post result after := by
  obtain ⟨result, completed, run, cells, resultPost⟩ := bodyContract
  exact ⟨result, restoreLocals ready completed, RunsStmt.letLocal initial run,
    ((initialCells.trans (FreshCellFrame.bindLocal ready id value)).trans cells).restoreLocals,
    scope result completed resultPost⟩

/-- Pure internal bodies may allocate temporary locals. Their proved frame,
    rather than exact equality to the entry state, is composed with call setup. -/
theorem RunsExpr.callPure
    (found : program.function? functionId = some function)
    (bodyFound : function.body = some body)
    (parameters : bindParameters function.parameters values = some bindings)
    (formed : caller.CellsWellFormed)
    (bodyContract : ∃ completed, RunsStmt program
      (({ caller with locals := [] }).bindLocals bindings) body (.returned (some value)) completed ∧
      PureFrame (({ caller with locals := [] }).bindLocals bindings) completed) :
    ∃ after, RunsExpr program caller (.call functionId (values.map Expr.value)) value after ∧
      PureFrame caller after := by
  obtain ⟨completed, bodyRun, pure⟩ := bodyContract
  have scope : CallerFrame caller { caller with locals := [] } :=
    ⟨formed, (CallerFrame.refl formed).cells, rfl, rfl, rfl⟩
  exact ⟨restoreLocals caller completed,
    RunsExpr.call found bodyFound (RunsExprs.values _) parameters bodyRun,
    ((scope.bindLocals bindings).transPure pure).restoreLocals⟩

/-- Local scope, initializer effects, and body effects compose at one boundary. -/
theorem RunsStmt.letLocalPure
    {id : Lanius.VarId}
    (initial : RunsExpr program before initializer value ready)
    (initialFrame : PureFrame before ready)
    (bodyRun : RunsStmt program (ready.bindLocal id value) body completion completed)
    (bodyFrame : PureFrame (ready.bindLocal id value) completed) :
    ∃ after, RunsStmt program before (.letLocal id type initializer body) completion after ∧
      PureFrame before after := by
  have frame := ((CallerFrame.refl initialFrame.beforeFormed).transPure initialFrame).bindLocal id value
  refine ⟨restoreLocals ready completed, RunsStmt.letLocal initial bodyRun, ?_⟩
  have framed := (frame.transPure bodyFrame).restoreLocals
  simpa only [restoreLocals, initialFrame.locals] using framed

/-- A body which leaves its entry state unchanged yields a pure call. The
    fresh parameter cells and restoration of caller locals are handled here. -/
theorem RunsExpr.callUnchanged
    (found : program.function? functionId = some function)
    (bodyFound : function.body = some body)
    (parameters : bindParameters function.parameters values = some bindings)
    (formed : caller.CellsWellFormed)
    (bodyRun : RunsStmt program (({ caller with locals := [] }).bindLocals bindings)
      body (.returned (some value)) (({ caller with locals := [] }).bindLocals bindings)) :
    ∃ after, RunsExpr program caller (.call functionId (values.map Expr.value)) value after ∧
      PureFrame caller after := by
  let callee := ({ caller with locals := [] }).bindLocals bindings
  have scope : CallerFrame caller { caller with locals := [] } :=
    ⟨formed, (CallerFrame.refl formed).cells, rfl, rfl, rfl⟩
  exact RunsExpr.callPure found bodyFound parameters formed
    ⟨callee, bodyRun, PureFrame.refl (scope.bindLocals bindings).currentFormed⟩

#print axioms RunsExpr.callStores

end Lanius.Semantics
