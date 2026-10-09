import verified_compiler.tests.direct_ir_decimal
import Lanius.Semantics.LocalPair
import Lanius.Semantics.LoopRun
import Lanius.Core.Bindings

namespace IRDecimalLoopProof

open Lanius Lanius.Core Lanius.Semantics IRDecimalProof

variable {base before after : State}

private def source := Extracted.«lowering::constant_expression».Functions.«decimal».core
private def accumulatorId := source.bindingId 0
private def cursorId := source.bindingId 1
private def traversal : Expr × Stmt := match source.body.getD .skip with
  | .sequence _ (.letLocal _ _ _ (.letLocal _ _ _ (.sequence (.whileLoop guard body) _))) => (guard, body)
  | _ => (.value .unit, .skip)
private def initializer : Expr := match traversal.2 with
  | .sequence (.expression (.assign _ _ expression)) _ => expression
  | _ => .value .unit
private def rejectCondition : Expr := match traversal.2 with
  | .sequence _ (.sequence (.ifThenElse condition _ _) _) => condition
  | _ => .value .unit
private def finishStmt : Stmt := match source.body.getD .skip with
  | .sequence _ (.letLocal _ _ _ (.letLocal _ _ _ (.sequence _ rest))) => rest
  | _ => .skip
private def stateType : Ty := match source.body.getD .skip with
  | .sequence _ (.letLocal _ type _ _) => type
  | _ => .unit
private def emptyInitializer : Expr := match source.body.getD .skip with
  | .sequence _ (.letLocal _ _ initializer _) => initializer
  | _ => .value .unit

def scan (bytes : Nat → Int) : Nat → Nat → Accumulator → Accumulator
  | 0, _, state => state
  | remaining + 1, index, state => scan bytes remaining (index + 1) (step state (bytes index))

theorem scan_rejected (bytes : Nat → Int) (remaining index : Nat) : scan bytes remaining index .rejected = .rejected := by
  induction remaining generalizing index with
  | zero => rfl
  | succ remaining ih => simp only [scan, rejected_absorbs]; exact ih _

theorem scan_bounded (bytes : Nat → Int) (remaining index : Nat) (state : Accumulator) (fits : bounded state) :
    bounded (scan bytes remaining index state) := by
  induction remaining generalizing index state with
  | zero => exact fits
  | succ remaining ih => exact ih _ _ (step_bounded state _ fits)

/-- Readable input bytes and ordinary bounds, not an assumed decoder result.
    Only the selected span needs readable backing storage. -/
structure Input (before : State) where
  address : Nat
  capacity : Nat
  count : Nat
  capacityBound : count ≤ capacity
  start : Nat
  length : Nat
  bytes : Nat → Int
  fits : count < 2 ^ 31
  inside : start + length ≤ count
  nonempty : 0 < length
  reads : ∀ index, index < length → readRawSliceIndex extractedProgram before
    (.scalar (.signed .i32)) address capacity (start + index) = .ok (.signed .i32 (bytes index))

private structure Context (base : State) extends Input base where
  formed : base.CellsWellFormed
  noViews : base.i32ArrayViews = []
  sourceFound : base.local? (source.argumentId 0) = some (.rawSlice (.scalar (.signed .i32)) address capacity)
  lengthFound : base.local? (source.argumentId 1) = some (.signed .i32 count)
  startFound : base.local? (source.argumentId 2) = some (.signed .i32 start)
  finishFound : base.local? (source.argumentId 3) = some (.signed .i32 (start + length))

variable {context : Context base}

private structure Frame (context : Context base) (current : State) (state : Accumulator) (index : Nat) : Prop extends
    LocalPair base current accumulatorId cursorId (stateValue state) (.signed .i32 (context.start + index)) where
  heap : current.heap = base.heap
  world : current.world = base.world
  views : current.i32ArrayViews = base.i32ArrayViews
  bounded : bounded state

private theorem Frame.transPure (frame : Frame context before state index) (pure : PureFrame before after) :
    Frame context after state index :=
  ⟨frame.toLocalPair.transCells pure.cells pure.locals, pure.heap.trans frame.heap,
    pure.world.trans frame.world, pure.views.trans frame.views, frame.bounded⟩

private theorem Frame.caller (frame : Frame context before state index) : CallerFrame base before :=
  ⟨context.formed, frame.cells, frame.heap, frame.world, frame.views⟩

private theorem Context.condition (context : Context base) (frame : Frame context before state index)
    (truth : Bool) (checked : decide (index < context.length) = truth) :
    RunsExpr extractedProgram before traversal.1 (.boolean truth) before := by
  core_facts [context, frame]
  have sub := eval_i32_subNat extractedProgram.target (context.start + context.length) 1 (by omega) (by omega)
  core_run

private theorem Context.replace (context : Context base) (frame : Frame context before state index)
    (inside : index < context.length) :
    ∃ after, RunsExpr extractedProgram before (.assign .set (.local accumulatorId) initializer) .unit after ∧
      Frame context after (step state (context.bytes index)) index := by
  core_facts [context, frame]
  have read : readRawSliceIndex extractedProgram before (.scalar (.signed .i32)) context.address context.capacity
      (context.start + index) = .ok (.signed .i32 (context.bytes index)) := by
    simpa only [readRawSliceIndex, frame.heap] using context.reads index inside
  obtain ⟨after, run, pair, heap, world, views⟩ := frame.toLocalPair.replaceFirst context.formed
    (frame.views.trans context.noViews) (replacement := stateValue (step state (context.bytes index)))
    (program := extractedProgram) (expression := initializer) (by core_pure_expr)
  exact ⟨after, run, ⟨pair, heap.trans frame.heap, world.trans frame.world,
    views.trans frame.views, step_bounded state _ frame.bounded⟩⟩

private theorem Context.runLoop (context : Context base) (frame : Frame context before state index)
    (remaining : Nat) (account : index + remaining = context.length) :
    ∃ completion after finalState finalIndex,
      RunsStmt extractedProgram before (.whileLoop traversal.1 traversal.2) completion after ∧
      Frame context after finalState finalIndex ∧
      ((completion = .next ∧ scan context.bytes remaining index state = finalState) ∨
        (completion = .returned (some (resultValue .rejected)) ∧ scan context.bytes remaining index state = .rejected)) := by
  induction remaining generalizing before index state with
  | zero =>
      have guard := context.condition frame false (by simp; omega)
      exact ⟨.next, before, state, index, .whileFalse guard, frame, Or.inl ⟨rfl, rfl⟩⟩
  | succ remaining ih =>
      have guard := context.condition frame true (by simp; omega)
      obtain ⟨updated, assigned, nextFrame⟩ := context.replace frame (by omega)
      core_facts [context, nextFrame]
      by_cases rejected : step state (context.bytes index) = .rejected
      · obtain ⟨after, rest, pure⟩ : ∃ after, RunsStmt extractedProgram updated
            (match traversal.2 with | .sequence _ rest => rest | _ => .skip)
            (.returned (some (resultValue .rejected))) after ∧ PureFrame updated after := by core_pure
        have iteration : RunsStmt extractedProgram before traversal.2 (.returned (some (resultValue .rejected))) after :=
          .sequenceNext (.expression assigned) rest
        have result : scan context.bytes (remaining + 1) index state = .rejected := by
          simp only [scan, rejected, scan_rejected]
        exact ⟨_, after, _, _, .whileReturn guard iteration, nextFrame.transPure pure, Or.inr ⟨rfl, result⟩⟩
      · obtain ⟨ready, condition, pure⟩ : ∃ ready, RunsExpr extractedProgram updated rejectCondition
            (.boolean false) ready ∧ PureFrame updated ready := by core_pure_guard
        let active := nextFrame.transPure pure
        obtain ⟨next, increment, pair, heap, world, views⟩ := active.toLocalPair.incrementSecond
          (program := extractedProgram) context.formed (by have := context.fits; have := context.inside; omega)
        have advanced : Frame context next (step state (context.bytes index)) (index + 1) :=
          ⟨by simpa only [Nat.add_assoc, Int.natCast_add, Int.natCast_one] using pair, heap.trans active.heap, world.trans active.world,
            views.trans active.views, active.bounded⟩
        have iteration : RunsStmt extractedProgram before traversal.2 .next next := by
          apply RunsStmt.sequenceNext (.expression assigned)
          apply RunsStmt.sequenceNext (.ifThenElseFalse condition (.skip _ _))
          exact .sequenceNext (.expression increment) (.skip _ _)
        obtain ⟨completion, after, finalState, finalIndex, rest, finalFrame, result⟩ := ih advanced (by omega)
        exact ⟨completion, after, finalState, finalIndex, .whileStep guard iteration (Or.inl rfl) rest,
          finalFrame, result⟩

private theorem Context.body (context : Context base) :
    ∃ after, RunsStmt extractedProgram base (source.body.getD .skip)
      (.returned (some (resultValue (scan context.bytes context.length 0 .empty)))) after ∧ PureFrame base after := by
  core_facts [context]
  apply RunsStmt.guardPureFalse
  · core_run
  · let ready := (base.bindLocal accumulatorId (stateValue .empty)).bindLocal cursorId (.signed .i32 context.start)
    have initial : Frame context ready .empty 0 := ⟨LocalPair.start context.formed (by decide), rfl, rfl, rfl, trivial⟩
    obtain ⟨completion, after, finalState, finalIndex, run, finalFrame, result⟩ :=
      context.runLoop initial context.length (by omega)
    obtain ⟨finished, tail, pure⟩ : ∃ finished, RunsStmt extractedProgram ready
        (.sequence (.whileLoop traversal.1 traversal.2) finishStmt)
        (.returned (some (resultValue (scan context.bytes context.length 0 .empty)))) finished ∧
        CallerFrame base finished := by
      rcases result with ⟨rfl, value⟩ | ⟨rfl, value⟩
      · rw [value]
        core_facts [context, finalFrame]
        obtain ⟨finished, tail, pure⟩ : ∃ finished, RunsStmt extractedProgram after finishStmt
            (.returned (some (resultValue finalState))) finished ∧ PureFrame after finished := by core_pure
        exact ⟨finished, .sequenceNext run tail, finalFrame.caller.transPure pure⟩
      · rw [value]
        exact ⟨after, .sequenceCompleted run (by simp) _, finalFrame.caller⟩
    have emptyRun : RunsExpr extractedProgram base emptyInitializer (stateValue .empty) base := by core_run
    have startRun : RunsExpr extractedProgram (base.bindLocal accumulatorId (stateValue .empty))
        (.local (source.argumentId 2)) (.signed .i32 context.start) (base.bindLocal accumulatorId (stateValue .empty)) := by core_run
    have initialized := RunsStmt.letLocal (type := stateType) (id := accumulatorId) emptyRun
      (RunsStmt.letLocal (type := .scalar (.signed .i32)) (id := cursorId) startRun tail)
    refine ⟨restoreLocals base finished, ?_, pure.restoreLocals⟩
    change RunsStmt extractedProgram base
      (.letLocal accumulatorId stateType emptyInitializer
        (.letLocal cursorId (.scalar (.signed .i32)) (.local (source.argumentId 2))
          (.sequence (.whileLoop traversal.1 traversal.2) finishStmt))) _ _
    simpa only [restoreLocals] using initialized

def Input.call (input : Input before) : Expr := .call source.id
  [.value (.rawSlice (.scalar (.signed .i32)) input.address input.capacity), .value (.signed .i32 input.count),
    .value (.signed .i32 input.start), .value (.signed .i32 (input.start + input.length))]

/-- Total execution, exact numeric result (including rejection), and a caller/
    memory frame for every nonempty readable, bounded span. -/
theorem actualDecimal (input : Input before) (formed : before.CellsWellFormed) (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before input.call
      (resultValue (scan input.bytes input.length 0 .empty)) after ∧ PureFrame before after := by
  core_call_pure source as callee
  let context : Context callee := {
    toInput := { input with reads := by intro index inside; exact input.reads index inside }
    formed := by core_formed
    noViews := noViews
    sourceFound := by core_local
    lengthFound := by core_local
    startFound := by core_local
    finishFound := by core_local }
  exact context.body

/-- Bounds rejection does not read the source, even if its descriptor is invalid. -/
theorem actualReject (length start finish : Int) (sourceValue : Value)
    (bad : start < 0 ∨ finish ≤ start ∨ length < finish) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call source.id [.value sourceValue,
      .value (.signed .i32 length), .value (.signed .i32 start), .value (.signed .i32 finish)])
      (resultValue .rejected) after ∧ PureFrame before after := by
  core_call_pure source as callee
  core_pure

#print axioms actualDecimal
#print axioms actualReject

end IRDecimalLoopProof

