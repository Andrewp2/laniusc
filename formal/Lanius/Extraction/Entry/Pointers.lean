import Lanius.Extraction.Allocation.Sequence

namespace Lanius.Extraction.Entry.Pointers

open Lanius.Core Lanius.Semantics Lanius.Memory

/-- Pointer queries may synchronize heap bytes, but preserve all state used
to read the remaining pointer checks. -/
structure Frame (before after : State) : Prop where
  cells : after.cells = before.cells
  locals : after.locals = before.locals
  views : after.i32ArrayViews = before.i32ArrayViews
  next : after.nextCell = before.nextCell
  remaining : after.heap.remaining = before.heap.remaining
  world : after.world = before.world

theorem Frame.refl (state : State) : Frame state state := ⟨rfl, rfl, rfl, rfl, rfl, rfl⟩

theorem Frame.trans (first : Frame before middle) (second : Frame middle after) : Frame before after :=
  ⟨second.cells.trans first.cells, second.locals.trans first.locals, second.views.trans first.views,
    second.next.trans first.next, second.remaining.trans first.remaining, second.world.trans first.world⟩

theorem Frame.localRead (frame : Frame before after) (binding : Lanius.VarId) :
    after.local? binding = before.local? binding := by
  have sameCells : after.cell? = before.cell? := by
    funext cell
    simp only [State.cell?, State.cellEntry?, frame.cells]
  simp only [State.local?, State.cellId?, frame.locals, sameCells]

inductive Pointer where
  | localValue (binding : Lanius.VarId)
  | slice (binding : Lanius.VarId)

def Pointer.expression : Pointer → Expr
  | .localValue binding => .local binding
  | .slice binding => .i32SliceDataPtr (.local binding)

def Pointer.Ready (state : State) : Pointer → Prop
  | .localValue binding => ∃ address, state.local? binding = some (.pointer address) ∧ address ≠ null
  | .slice binding => ∃ view ∈ state.i32ArrayViews,
      state.local? binding = some (.slice (.scalar (.signed .i32)) view.root view.projections 0 view.length)

theorem Pointer.Ready.transport {pointer : Pointer} (ready : pointer.Ready before)
    (frame : Frame before after) : pointer.Ready after := by
  cases pointer <;> simpa only [Pointer.Ready, frame.views, frame.localRead] using ready

theorem Pointer.evaluates (pointer : Pointer) (program : Program) (registry : Allocation.Registry before)
    (ready : pointer.Ready before) :
    ∃ address after, Evaluates program before pointer.expression (.pointer address) after ∧
      address ≠ null ∧ Allocation.Registry after ∧ Frame before after := by
  cases pointer with
  | localValue binding =>
      obtain ⟨address, read, nonnull⟩ := ready
      exact ⟨address, before, ⟨1, evalLocal_of_local 0 program before binding _ read⟩,
        nonnull, registry, Frame.refl before⟩
  | slice binding =>
      obtain ⟨view, member, read⟩ := ready
      obtain ⟨after, evaluated, nonnull, valid, cells, locals, views, next, remaining, world⟩ :=
        registry.evaluatesPointer program member binding read
      exact ⟨view.address, after, evaluated, nonnull, valid, cells, locals, views, next, remaining, world⟩

inductive Check where
  | isNull (pointer : Pointer)
  | either (left right : Check)

def Check.expression : Check → Expr
  | .isNull pointer => .binary .equal pointer.expression (.value (.pointer null))
  | .either left right => .binary .logicalOr left.expression right.expression

def Check.Ready (state : State) : Check → Prop
  | .isNull pointer => pointer.Ready state
  | .either left right => left.Ready state ∧ right.Ready state

theorem Check.Ready.transport {check : Check} (ready : check.Ready before)
    (frame : Frame before after) : check.Ready after := by
  induction check with
  | isNull pointer => exact Pointer.Ready.transport ready frame
  | either left right leftIH rightIH => exact ⟨leftIH ready.1, rightIH ready.2⟩

/-- The actual short-circuit expression evaluates false, threading heap
synchronization through every operand without losing subsequent local reads. -/
theorem Check.evaluatesFalse (check : Check) (program : Program) (before : State)
    (registry : Allocation.Registry before) (ready : check.Ready before) :
    ∃ after, Evaluates program before check.expression (.boolean false) after ∧
      Allocation.Registry after ∧ Frame before after := by
  induction check generalizing before with
  | isNull pointer =>
      obtain ⟨address, after, evaluated, nonnull, valid, frame⟩ := pointer.evaluates program registry ready
      refine ⟨after, ?_, valid, frame⟩
      apply evaluatesEagerBinary (by decide) (by decide) evaluated
        (show Evaluates program after (.value (.pointer null)) (.pointer null) after from ⟨1, rfl⟩)
      simp [evalBinaryValue, scalarEqual, nonnull]
  | either left right leftIH rightIH =>
      obtain ⟨middle, leftResult, middleValid, first⟩ := leftIH before registry ready.1
      obtain ⟨after, rightResult, valid, second⟩ := rightIH middle middleValid (ready.2.transport first)
      exact ⟨after, evaluatesLogicalOrFalse leftResult rightResult, valid, first.trans second⟩

structure Guard where
  check : Check
  continuation : Stmt

def Guard.statement (guard : Guard) : Stmt :=
  .sequence (.ifThenElse guard.check.expression
    (.sequence (.returnValue (some (.value (.signed .i32 3)))) .skip) .skip) guard.continuation

theorem Guard.executes (guard : Guard) (program : Program) (before : State)
    (completion : Completion) (post : Lanius.World.State → Prop)
    (registry : Allocation.Registry before) (ready : guard.check.Ready before)
    (continuationRun : ∀ after, Allocation.Registry after → Frame before after →
      ∃ finalState, Executes program after guard.continuation completion finalState ∧ post finalState.world) :
    ∃ after, Executes program before guard.statement completion after ∧ post after.world := by
  obtain ⟨middle, evaluated, valid, frame⟩ := guard.check.evaluatesFalse program before registry ready
  obtain ⟨after, continued, satisfied⟩ := continuationRun middle valid frame
  exact ⟨after, executesSequence (executesIfFalse evaluated (executesSkip program middle)) continued, satisfied⟩

structure CheckedCheck (expression : Expr) where
  check : Check
  exactExpression : expression = check.expression

def checkCondition? : (expression : Expr) → Option (CheckedCheck expression)
  | .binary .equal (.local binding) (.value (.pointer 0)) =>
      some ⟨.isNull (.localValue binding), rfl⟩
  | .binary .equal (.i32SliceDataPtr (.local binding)) (.value (.pointer 0)) =>
      some ⟨.isNull (.slice binding), rfl⟩
  | .binary .logicalOr left right => do
      let leftChecked ← checkCondition? left
      let rightChecked ← checkCondition? right
      pure ⟨.either leftChecked.check rightChecked.check,
        (congrArg (fun expression => Expr.binary .logicalOr expression right) leftChecked.exactExpression).trans
          (congrArg (Expr.binary .logicalOr leftChecked.check.expression) rightChecked.exactExpression)⟩
  | _ => none

def checkGuard? : (source : Stmt) → Option (Source.CheckedStatement Guard.statement source)
  | .sequence (.ifThenElse condition
      (.sequence (.returnValue (some (.value (.signed .i32 3)))) .skip) .skip) continuation => do
      let checked ← checkCondition? condition
      pure ⟨⟨checked.check, continuation⟩,
        congrArg (fun expression => Stmt.sequence (.ifThenElse expression
          (.sequence (.returnValue (some (.value (.signed .i32 3)))) .skip) .skip) continuation)
          checked.exactExpression⟩
  | _ => none

def findGuard? := Source.findStatement? Guard.statement checkGuard?

end Lanius.Extraction.Entry.Pointers
