import Lanius.Semantics.MatchRun

namespace Lanius.Semantics

open Lanius.Core Lanius.Memory

variable {before middle after ready completed caller : State} {program : Program}
  {effect : State → State → Prop}

/-- Effect contracts may cross pure setup and lexical scope only when those
    two laws have been proved. No successful execution is a field of this law. -/
structure ScopeStable (effect : State → State → Prop) : Prop where
  prepend : ∀ {before middle after}, CallerFrame before middle → effect middle after → effect before after
  restore : ∀ {before after} (caller : State), effect before after → effect before (restoreLocals caller after)

/-- Native effects retain caller cells, world and views, together with a
    caller-chosen proved relation on heaps. The relation may describe several
    disjoint stores, snapshots, ownership changes or retained reads. -/
def MemoryEffect (relation : Heap → Heap → Prop) (before after : State) : Prop :=
  FreshCellFrame before after ∧ after.world = before.world ∧ after.i32ArrayViews = before.i32ArrayViews ∧
    relation before.heap after.heap

theorem MemoryEffect.scopeStable (relation : Heap → Heap → Prop) : ScopeStable (MemoryEffect relation) := by
  constructor
  · intro before middle after pure frame
    exact ⟨pure.cells.trans frame.1, frame.2.1.trans pure.world, frame.2.2.1.trans pure.views,
      by simpa only [pure.heap] using frame.2.2.2⟩
  · intro before after caller frame
    exact ⟨frame.1, frame.2.1, frame.2.2.1, frame.2.2.2⟩

theorem MemoryEffect.thenPure (effect : MemoryEffect relation before middle) (pure : PureFrame middle after) :
    MemoryEffect relation before after :=
  ⟨effect.1.trans pure.cells, pure.world.trans effect.2.1, pure.views.trans effect.2.2.1,
    by rw [pure.heap]; exact effect.2.2.2⟩

theorem MemoryEffect.thenCaller (effect : MemoryEffect relation before middle) (frame : CallerFrame middle after) :
    MemoryEffect relation before after :=
  ⟨effect.1.trans frame.cells, frame.world.trans effect.2.1, frame.views.trans effect.2.2.1,
    by rw [frame.heap]; exact effect.2.2.2⟩

theorem MemoryEffect.prependCaller (frame : CallerFrame before middle) (effect : MemoryEffect relation middle after) :
    MemoryEffect relation before after :=
  (MemoryEffect.scopeStable relation).prepend frame effect

theorem MemoryEffect.trans
    (compose : ∀ {a b c}, relation a b → relation b c → relation a c)
    (first : MemoryEffect relation before middle) (second : MemoryEffect relation middle after) :
    MemoryEffect relation before after :=
  ⟨first.1.trans second.1, second.2.1.trans first.2.1, second.2.2.1.trans first.2.2.1,
    compose first.2.2.2 second.2.2.2⟩

/-- A proved effectful argument followed by a pure value-call retains the
    argument's heap effect. Inference uses this for operand validation. -/
theorem RunsExpr.callMemoryArgument
    (argument : ∃ middle, RunsExpr program before expression value middle ∧ MemoryEffect relation before middle)
    (call : ∀ middle, MemoryEffect relation before middle → ∃ after,
      RunsExpr program middle (.call functionId [.value value]) result after ∧ PureFrame middle after) :
    ∃ after, RunsExpr program before (.call functionId [expression]) result after ∧
      MemoryEffect relation before after := by
  obtain ⟨middle, argument, effect⟩ := argument
  obtain ⟨after, run, pure⟩ := call middle effect
  exact ⟨after, RunsExpr.callArguments (.cons argument .nil) run, effect.thenPure pure⟩

theorem RunsExpr.callEffect (scopes : ScopeStable effect)
    {function : Function} {values : List Value} {bindings : List (Lanius.VarId × Value)}
    (found : program.function? functionId = some function)
    (bodyFound : function.body = some body)
    (parameters : bindParameters function.parameters values = some bindings)
    (formed : caller.CellsWellFormed)
    (contract : ∃ completed, RunsStmt program (({ caller with locals := [] }).bindLocals bindings)
      body (.returned (some value)) completed ∧ effect (({ caller with locals := [] }).bindLocals bindings) completed) :
    ∃ after, RunsExpr program caller (.call functionId (values.map Expr.value)) value after ∧ effect caller after := by
  obtain ⟨completed, run, frame⟩ := contract
  have entry : CallerFrame caller (({ caller with locals := [] }).bindLocals bindings) :=
    (show CallerFrame caller { caller with locals := [] } from
      ⟨formed, (CallerFrame.refl formed).cells, rfl, rfl, rfl⟩).bindLocals bindings
  exact ⟨restoreLocals caller completed, RunsExpr.call found bodyFound (RunsExprs.values _) parameters run,
    scopes.restore caller (scopes.prepend entry frame)⟩

/-- Read-only arguments can introduce fresh cells before an effectful call.
    Their proved caller frame composes with the callee's actual effect. -/
theorem RunsExpr.callFramedEffectArguments (scopes : ScopeStable effect)
    (arguments : ∃ middle, RunsExprs program before expressions values middle ∧ PureFrame before middle)
    (contract : ∀ middle, PureFrame before middle → ∃ after,
      RunsExpr program middle (.call functionId (values.map Expr.value)) value after ∧ effect middle after) :
    ∃ after, RunsExpr program before (.call functionId expressions) value after ∧ effect before after := by
  obtain ⟨middle, arguments, pure⟩ := arguments
  obtain ⟨after, run, frame⟩ := contract middle pure
  exact ⟨after, RunsExpr.callArguments arguments run,
    scopes.prepend ((CallerFrame.refl pure.beforeFormed).transPure pure) frame⟩

theorem RunsExpr.argumentsEffect
    (arguments : RunsExprs program before expressions values before)
    (call : ∃ after, RunsExpr program before (.call functionId (values.map Expr.value)) value after ∧ effect before after) :
    ∃ after, RunsExpr program before (.call functionId expressions) value after ∧ effect before after := by
  obtain ⟨after, run, frame⟩ := call
  exact ⟨after, RunsExpr.callArguments arguments run, frame⟩

theorem RunsStmt.returnEffect
    (expression : ∃ after, RunsExpr program before argument value after ∧ effect before after) :
    ∃ after, RunsStmt program before (.returnValue (some argument)) (.returned (some value)) after ∧ effect before after := by
  obtain ⟨after, run, frame⟩ := expression
  exact ⟨after, RunsStmt.returnValue run, frame⟩

theorem RunsStmt.letEffect (scopes : ScopeStable effect) {id : Lanius.VarId}
    (initial : RunsExpr program before initializer value before) (formed : before.CellsWellFormed)
    (body : ∃ completed, RunsStmt program (before.bindLocal id value) bodyStmt completion completed ∧
      effect (before.bindLocal id value) completed) :
    ∃ after, RunsStmt program before (.letLocal id type initializer bodyStmt) completion after ∧ effect before after := by
  obtain ⟨completed, run, frame⟩ := body
  exact ⟨restoreLocals before completed, RunsStmt.letLocal initial run,
    scopes.restore before (scopes.prepend ((CallerFrame.refl formed).bindLocal id value) frame)⟩

/-- A read-only initializer may allocate fresh call cells. Its frame is
    retained when the body subsequently performs a proved memory effect. -/
theorem RunsStmt.letFramedEffect (scopes : ScopeStable effect) {id : Lanius.VarId}
    (initial : ∃ ready, RunsExpr program before initializer value ready ∧ PureFrame before ready)
    (body : ∀ ready, PureFrame before ready → ∃ completed,
      RunsStmt program (ready.bindLocal id value) bodyStmt completion completed ∧ effect (ready.bindLocal id value) completed) :
    ∃ after, RunsStmt program before (.letLocal id type initializer bodyStmt) completion after ∧ effect before after := by
  obtain ⟨ready, initial, pure⟩ := initial
  obtain ⟨completed, run, frame⟩ := body ready pure
  have entry := ((CallerFrame.refl pure.beforeFormed).transPure pure).bindLocal id value
  exact ⟨restoreLocals ready completed, RunsStmt.letLocal initial run,
    scopes.restore ready (scopes.prepend entry frame)⟩

/-- An effectful initializer followed by a read-only continuation retains its
    heap relation, including any fresh cells introduced by the continuation. -/
theorem RunsStmt.letMemoryEffect {id : Lanius.VarId} {relation : Heap → Heap → Prop}
    (initial : ∃ ready, RunsExpr program before initializer value ready ∧ MemoryEffect relation before ready)
    (body : ∀ ready, RunsExpr program before initializer value ready → MemoryEffect relation before ready → ∃ completed,
      RunsStmt program (ready.bindLocal id value) bodyStmt completion completed ∧
      PureFrame (ready.bindLocal id value) completed) :
    ∃ after, RunsStmt program before (.letLocal id type initializer bodyStmt) completion after ∧
      MemoryEffect relation before after := by
  obtain ⟨ready, initial, frame⟩ := initial
  obtain ⟨completed, run, pure⟩ := body ready initial frame
  exact ⟨restoreLocals ready completed, RunsStmt.letLocal initial run,
    (frame.1.trans (FreshCellFrame.bindLocal ready id value)).trans pure.cells,
    pure.world.trans frame.2.1, pure.views.trans frame.2.2.1,
    by change relation before.heap completed.heap; rw [pure.heap]; exact frame.2.2.2⟩

/-- Consecutive effectful computations retain both heap updates. The caller
    proves composition for its relation; no computation is assumed pure. -/
theorem RunsStmt.letMemoryThen {id : Lanius.VarId} {relation : Heap → Heap → Prop}
    (compose : ∀ {a b c}, relation a b → relation b c → relation a c)
    (initial : ∃ ready, RunsExpr program before initializer value ready ∧ MemoryEffect relation before ready)
    (body : ∀ ready, RunsExpr program before initializer value ready → MemoryEffect relation before ready →
      ∃ completed, RunsStmt program (ready.bindLocal id value) bodyStmt completion completed ∧
        MemoryEffect relation (ready.bindLocal id value) completed) :
    ∃ after, RunsStmt program before (.letLocal id type initializer bodyStmt) completion after ∧
      MemoryEffect relation before after := by
  obtain ⟨ready, initial, frame⟩ := initial
  obtain ⟨completed, run, rest⟩ := body ready initial frame
  exact ⟨restoreLocals ready completed, RunsStmt.letLocal initial run,
    (frame.1.trans (FreshCellFrame.bindLocal ready id value)).trans rest.1,
    rest.2.1.trans frame.2.1, rest.2.2.1.trans frame.2.2.1, compose frame.2.2.2 rest.2.2.2⟩

/-- Evaluate a guard once, keep its pure setup, and enter only the selected
    continuation. The continuation must prove its own actual effect. -/
theorem RunsStmt.guardEffectFalse (scopes : ScopeStable effect)
    (guard : ∃ ready, RunsExpr program before condition (.boolean false) ready ∧ PureFrame before ready)
    (rest : ∀ ready, PureFrame before ready →
      ∃ after, RunsStmt program ready restStmt completion after ∧ effect ready after) :
    ∃ after, RunsStmt program before (.sequence (.ifThenElse condition thenStmt .skip) restStmt) completion after ∧
      effect before after := by
  obtain ⟨ready, guard, pure⟩ := guard
  obtain ⟨after, run, frame⟩ := rest ready pure
  exact ⟨after, RunsStmt.sequenceNext (RunsStmt.ifThenElseFalse guard (RunsStmt.skip _ _)) run,
    scopes.prepend ((CallerFrame.refl pure.beforeFormed).transPure pure) frame⟩

theorem RunsStmt.guardEffectTrue (scopes : ScopeStable effect) (notNext : completion ≠ .next)
    (guard : ∃ ready, RunsExpr program before condition (.boolean true) ready ∧ PureFrame before ready)
    (branch : ∀ ready, PureFrame before ready →
      ∃ after, RunsStmt program ready thenStmt completion after ∧ effect ready after) :
    ∃ after, RunsStmt program before (.sequence (.ifThenElse condition thenStmt .skip) restStmt) completion after ∧
      effect before after := by
  obtain ⟨ready, guard, pure⟩ := guard
  obtain ⟨after, run, frame⟩ := branch ready pure
  exact ⟨after, RunsStmt.sequenceCompleted (RunsStmt.ifThenElseTrue guard run) notNext _,
    scopes.prepend ((CallerFrame.refl pure.beforeFormed).transPure pure) frame⟩

theorem RunsExpr.matchEffect (scopes : ScopeStable effect)
    (source : RunsExpr program before scrutinee value before)
    (selected : selectedArm value arms = some (bindings, body))
    (formed : before.CellsWellFormed)
    (branch : ∃ completed, RunsExpr program (before.bindLocals bindings) body result completed ∧
      effect (before.bindLocals bindings) completed) :
    ∃ after, RunsExpr program before (.matchValue scrutinee arms) result after ∧ effect before after := by
  obtain ⟨completed, run, frame⟩ := branch
  exact ⟨restoreLocals before completed, RunsExpr.matchValue source selected run,
    scopes.restore before (scopes.prepend ((CallerFrame.refl formed).bindLocals bindings) frame)⟩

#print axioms RunsExpr.callFramedEffectArguments

end Lanius.Semantics
