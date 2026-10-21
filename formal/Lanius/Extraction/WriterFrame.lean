import Lanius.Memory.Output
import Lanius.Semantics.CallRun
import Lanius.Semantics.MatchRun

namespace Lanius.Extraction

open Lanius.Core Lanius.Semantics

variable {before middle after ready completed caller : State} {front suffix bytes : List UInt8} {id : VarId}

/-- The common execution environment required by bounded native writers.
    These are memory/cell assumptions, not an assumed successful writer run. -/
structure WriterEnvironment (state : State) : Prop where
  formed : state.CellsWellFormed
  noViews : state.i32ArrayViews = []
  below : Memory.HeapBlocksBelowNext state.heap
  unique : Memory.HeapBlockBasesUnique state.heap

theorem WriterEnvironment.reheap (environment : WriterEnvironment before)
    (heap : after.heap = before.heap) (views : after.i32ArrayViews = before.i32ArrayViews)
    (formed : after.CellsWellFormed) :
    WriterEnvironment after :=
  ⟨formed, views.trans environment.noViews,
    by simpa only [heap] using environment.below,
    by simpa only [heap] using environment.unique⟩

theorem WriterEnvironment.inScope (environment : WriterEnvironment before) (frame : CallerFrame before after) :
    WriterEnvironment after := environment.reheap frame.heap frame.views frame.currentFormed

theorem WriterEnvironment.afterPure (environment : WriterEnvironment before) (frame : PureFrame before after) :
    WriterEnvironment after := environment.inScope ((CallerFrame.refl environment.formed).transPure frame)

/-- Composable effects of a checked printer call. Caller scope is supplied by
    RunsExpr/RunsStmt, while this frame retains old cells and observable effects. -/
structure WriterFrame (before after : State) (address : Nat) (bytes : List UInt8) : Prop where
  output : Memory.OutputEffect before.heap after.heap address bytes
  cells : FreshCellFrame before after
  world : after.world = before.world
  views : after.i32ArrayViews = before.i32ArrayViews

theorem WriterFrame.append (first : WriterFrame before middle address front)
    (second : WriterFrame middle after (address + front.length) suffix) :
    WriterFrame before after address (front ++ suffix) :=
  ⟨first.output.append second.output, first.cells.trans second.cells,
    second.world.trans first.world, second.views.trans first.views⟩

theorem WriterFrame.prependPure (pure : CallerFrame before middle)
    (frame : WriterFrame middle after address bytes) : WriterFrame before after address bytes :=
  ⟨by simpa only [pure.heap] using frame.output, pure.cells.trans frame.cells,
    frame.world.trans pure.world, frame.views.trans pure.views⟩

theorem WriterFrame.restoreLocals (frame : WriterFrame before after address bytes) (caller : State) :
    WriterFrame before (restoreLocals caller after) address bytes :=
  ⟨frame.output, frame.cells.restoreLocals, frame.world, frame.views⟩

theorem WriterFrame.afterFormed (frame : WriterFrame before after address bytes)
    (formed : before.CellsWellFormed) : after.CellsWellFormed := frame.cells.after_cellsWellFormed formed

/-- A checked output effect supplies the next writer's environment. -/
theorem WriterEnvironment.afterWrite (environment : WriterEnvironment before)
    (frame : WriterFrame before after address bytes) : WriterEnvironment after :=
  ⟨frame.afterFormed environment.formed, frame.views.trans environment.noViews,
    frame.output.belowNext environment.below, frame.output.unique⟩

/-- A read-only scrutinee and a checked writer branch compose through payload
    binding and scope restoration without reopening the branch's body. -/
theorem RunsExpr.matchWriter
    (source : RunsExpr program before scrutinee value before)
    (selected : selectedArm value arms = some (bindings, body))
    (formed : before.CellsWellFormed)
    (branch : ∃ completed, RunsExpr program (before.bindLocals bindings) body result completed ∧
      WriterFrame (before.bindLocals bindings) completed address bytes) :
    ∃ after, RunsExpr program before (.matchValue scrutinee arms) result after ∧
      WriterFrame before after address bytes := by
  obtain ⟨completed, run, frame⟩ := branch
  exact ⟨restoreLocals before completed, RunsExpr.matchValue source selected run,
    (frame.prependPure ((CallerFrame.refl formed).bindLocals bindings)).restoreLocals before⟩

/-- Pure argument reads reuse a checked value-argument writer contract. -/
theorem RunsExpr.writerArguments
    (arguments : RunsExprs program before expressions values before)
    (contract : ∃ after, RunsExpr program before (.call functionId (values.map Expr.value)) value after ∧
      WriterFrame before after address bytes) :
    ∃ after, RunsExpr program before (.call functionId expressions) value after ∧
      WriterFrame before after address bytes := by
  obtain ⟨after, run, frame⟩ := contract
  exact ⟨after, RunsExpr.callArguments arguments run, frame⟩

/-- Read-only argument calls may allocate cells before the writer starts.
    Keep their frame instead of requiring state-identical argument evaluation. -/
theorem RunsExpr.writerFramedArguments
    (arguments : ∃ middle, RunsExprs program before expressions values middle ∧ PureFrame before middle)
    (contract : ∀ middle, PureFrame before middle →
      ∃ after, RunsExpr program middle (.call functionId (values.map Expr.value)) value after ∧
        WriterFrame middle after address bytes) :
    ∃ after, RunsExpr program before (.call functionId expressions) value after ∧
      WriterFrame before after address bytes := by
  obtain ⟨middle, arguments, first⟩ := arguments
  obtain ⟨after, run, rest⟩ := contract middle first
  exact ⟨after, RunsExpr.callArguments arguments run,
    rest.prependPure ((CallerFrame.refl first.beforeFormed).transPure first)⟩

theorem RunsStmt.returnWriter
    (contract : ∃ after, RunsExpr program before expression value after ∧ WriterFrame before after address bytes) :
    ∃ after, RunsStmt program before (.returnValue (some expression)) (.returned (some value)) after ∧
      WriterFrame before after address bytes := by
  obtain ⟨after, run, frame⟩ := contract
  exact ⟨after, .returnValue run, frame⟩

/-- A read-only initializer leaves only its fresh local scope to frame. -/
theorem RunsStmt.letPureWriter
    (initial : RunsExpr program before initializer value before) (formed : before.CellsWellFormed)
    (contract : ∃ completed, RunsStmt program (before.bindLocal id value) body completion completed ∧
      WriterFrame (before.bindLocal id value) completed address bytes) :
    ∃ after, RunsStmt program before (.letLocal id type initializer body) completion after ∧
      WriterFrame before after address bytes := by
  obtain ⟨completed, run, frame⟩ := contract
  exact ⟨restoreLocals before completed, .letLocal initial run,
    (frame.prependPure ((CallerFrame.refl formed).bindLocal id value)).restoreLocals before⟩

/-- A checked read-only guard may allocate parameter cells. Keep that frame
    when its returning branch writes; do not pretend the guard is state-free. -/
theorem RunsStmt.guardWriterTrue (notNext : completion ≠ .next)
    (condition : ∃ ready, RunsExpr program before conditionExpr (.boolean true) ready ∧ PureFrame before ready)
    (branch : ∀ ready, PureFrame before ready →
      ∃ after, RunsStmt program ready thenStmt completion after ∧ WriterFrame ready after address bytes) :
    ∃ after, RunsStmt program before
      (.sequence (.ifThenElse conditionExpr thenStmt .skip) restStmt) completion after ∧
      WriterFrame before after address bytes := by
  obtain ⟨ready, run, frame⟩ := condition
  obtain ⟨after, branch, written⟩ := branch ready frame
  exact ⟨after, RunsStmt.sequenceCompleted (RunsStmt.ifThenElseTrue run branch) notNext _,
    written.prependPure ((CallerFrame.refl frame.beforeFormed).transPure frame)⟩

/-- A read-only call guard can allocate cells even when it falls through.
    Carry those effects into the writer continuation. -/
theorem RunsStmt.guardWriterFalse
    (condition : ∃ ready, RunsExpr program before conditionExpr (.boolean false) ready ∧ PureFrame before ready)
    (rest : ∀ ready, PureFrame before ready →
      ∃ after, RunsStmt program ready restStmt completion after ∧ WriterFrame ready after address bytes) :
    ∃ after, RunsStmt program before
      (.sequence (.ifThenElse conditionExpr thenStmt .skip) restStmt) completion after ∧
      WriterFrame before after address bytes := by
  obtain ⟨ready, run, frame⟩ := condition
  obtain ⟨after, rest, written⟩ := rest ready frame
  exact ⟨after, .sequenceNext (.ifThenElseFalse run (.skip _ _)) rest,
    written.prependPure ((CallerFrame.refl frame.beforeFormed).transPure frame)⟩

/-- Reuse a checked read-only initializer before entering a writer's scope. -/
theorem RunsStmt.letReadWriter
    (initial : ∃ ready, RunsExpr program before initializer value ready ∧ PureFrame before ready)
    (body : ∀ ready, PureFrame before ready →
      ∃ after, RunsStmt program (ready.bindLocal id value) bodyStmt completion after ∧
        WriterFrame (ready.bindLocal id value) after address bytes) :
    ∃ after, RunsStmt program before (.letLocal id type initializer bodyStmt) completion after ∧
      WriterFrame before after address bytes := by
  obtain ⟨ready, initial, frame⟩ := initial
  obtain ⟨after, run, written⟩ := body ready frame
  exact ⟨restoreLocals ready after, .letLocal initial run,
    (written.prependPure (((CallerFrame.refl frame.beforeFormed).transPure frame).bindLocal id value)).restoreLocals ready⟩

/-- A state-identical guard can skip the unused branch without introducing
    an unnecessary continuation state into ordinary writer proofs. -/
theorem RunsStmt.guardPureWriter (truth : Bool) (notNext : truth = true → completion ≠ .next)
    (condition : RunsExpr program before conditionExpr (.boolean truth) before)
    (branch : ∃ after, RunsStmt program before (if truth then thenStmt else restStmt) completion after ∧
      WriterFrame before after address bytes) :
    ∃ after, RunsStmt program before
      (.sequence (.ifThenElse conditionExpr thenStmt .skip) restStmt) completion after ∧
      WriterFrame before after address bytes := by
  obtain ⟨after, run, frame⟩ := branch
  cases truth with
  | false => exact ⟨after, .sequenceNext (.ifThenElseFalse condition (.skip _ _)) run, frame⟩
  | true => exact ⟨after, .sequenceCompleted (.ifThenElseTrue condition run) (notNext rfl) _, frame⟩

/-- Compose an effectful initializer and its local scope without repeating
    allocation or caller framing. Neither intermediate run is assumed by users:
    clients discharge these obligations with the checked constituent contracts. -/
theorem RunsStmt.letWriter (initial : RunsExpr program before initializer value ready)
    (first : WriterFrame before ready address front) (formed : before.CellsWellFormed)
    (body : RunsStmt program (ready.bindLocal id value) statement result completed)
    (second : WriterFrame (ready.bindLocal id value) completed (address + front.length) suffix) :
    ∃ after, RunsStmt program before (.letLocal id type initializer statement) result after ∧
      WriterFrame before after address (front ++ suffix) :=
  ⟨restoreLocals ready completed, .letLocal initial body,
    (first.append (second.prependPure ((CallerFrame.refl (first.afterFormed formed)).bindLocal id value))).restoreLocals ready⟩

/-- Parameter cells and caller restoration belong to call composition, not to
    every program-specific printer theorem. The body remains an explicit proof. -/
theorem RunsExpr.callWriter
    (found : program.function? functionId = some function)
    (bodyFound : function.body = some body)
    (parameters : bindParameters function.parameters values = some bindings)
    (formed : caller.CellsWellFormed)
    (bodyContract : ∃ completed, RunsStmt program
      (({ caller with locals := [] }).bindLocals bindings) body (.returned (some value)) completed ∧
      WriterFrame (({ caller with locals := [] }).bindLocals bindings) completed address bytes) :
    ∃ after, RunsExpr program caller (.call functionId (values.map Expr.value)) value after ∧
      WriterFrame caller after address bytes := by
  obtain ⟨completed, bodyRun, frame⟩ := bodyContract
  have scope : CallerFrame caller { caller with locals := [] } :=
    ⟨formed, (CallerFrame.refl formed).cells, rfl, rfl, rfl⟩
  exact ⟨restoreLocals caller completed,
    RunsExpr.call found bodyFound (RunsExprs.values _) parameters bodyRun,
    (frame.prependPure (scope.bindLocals bindings)).restoreLocals caller⟩

end Lanius.Extraction
