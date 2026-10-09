import verified_compiler.tests.direct_ir_shape
import Lanius.Core.Bindings
import Lanius.Semantics.LocalPair
import Lanius.Semantics.ScalarAssignment
import Lanius.Semantics.LoopRun
import Lanius.Semantics.CallProof

namespace IRChildrenProof

open Lanius Lanius.Core Lanius.Semantics IRShapeProof

deriving instance DecidableEq for Extracted.«ir::body_tree».Types.«NodeKind»
private def source := Extracted.«ir::body_tree».Functions.«children_end».core
private def eventType : Ty := match ((source.parameters[0]?).map Prod.snd : Option Core.Ty) with
  | some (.slice element) => element
  | _ => .unit
private def cursorId := source.bindingId 0
private def childId := source.bindingId 1
private def loop : Expr × Stmt := match source.body.getD .skip with
  | .letLocal _ _ _ (.letLocal _ _ _ (.sequence (.whileLoop guard body) _)) => (guard, body)
  | _ => (.value (.boolean true), .skip)
private def preCheck : Expr := match loop.2 with
  | .sequence (.ifThenElse condition _ _) _ => condition
  | _ => .value .unit
private def advanceStmt : Stmt := match loop.2 with
  | .sequence _ rest => rest
  | _ => .skip
private def nextId := source.bindingId 2
private def nextInitializer : Expr := match advanceStmt with
  | .letLocal _ _ initializer _ => initializer
  | _ => .value .unit
private def nextCheck : Stmt := match advanceStmt with
  | .letLocal _ _ _ (.sequence check _) => check
  | _ => .skip
private def nextCondition : Expr := match nextCheck with
  | .ifThenElse condition _ _ => condition
  | _ => .value .unit

/-- A logical view of the input region, not emitted proof data. Read facts
    describe the actual heap; classification is the source-event relation,
    not an assumed execution of the classifier or walker. -/
structure Input (state : State) where
  count : Nat
  index : Nat
  arity : Nat
  eventsAddress : Nat
  eventsLength : Nat
  endsAddress : Nat
  fits : count < 2 ^ 31
  inside : index < count
  room : arity ≤ count - index - 1
  parentKind : Kind
  rule : Rule
  events : Nat → Value
  kinds : Nat → Kind
  eventArities : Nat → Int
  eventRules : Nat → Rule
  ends : Nat → Int
  eventReads : ∀ position, position < count →
    readRawSliceIndex extractedProgram state eventType eventsAddress eventsLength position = .ok (events position)
  endReads : ∀ position, position < count →
    readRawSliceIndex extractedProgram state (.scalar (.signed .i32)) endsAddress count position =
      .ok (.signed .i32 (ends position))
  classified : ∀ position, position < count → Classifies (events position)
    (shapeValue (kindValue (kinds position)) (eventArities position) (ruleValue (eventRules position)))

def walkChildren (count : Nat) (kinds : Nat → Kind) (rule : Rule)
    (arity : Nat) (ends : Nat → Int) : Nat → Nat → Nat → Int
  | 0, _, cursor => cursor
  | remaining + 1, child, cursor =>
      if count ≤ cursor ∨ kinds cursor ≠ expectedKind rule child arity ∨
          ends cursor ≤ cursor ∨ (count : Int) < ends cursor then -1
      else walkChildren count kinds rule arity ends remaining (child + 1) (ends cursor).toNat

abbrev Input.walk (input : Input state) :=
  walkChildren input.count input.kinds input.rule input.arity input.ends

theorem Input.walk_bounds (input : Input state) (remaining child cursor : Nat) (bounded : cursor ≤ input.count) :
    input.walk remaining child cursor = -1 ∨
      (cursor : Int) ≤ input.walk remaining child cursor ∧ input.walk remaining child cursor ≤ input.count := by
  induction remaining generalizing child cursor with
  | zero => exact Or.inr ⟨Int.le_refl _, by change (cursor : Int) ≤ input.count; omega⟩
  | succ remaining ih =>
      simp only [Input.walk, walkChildren]
      split
      · exact Or.inl rfl
      · rename_i good
        have next := ih (child := child + 1) (cursor := (input.ends cursor).toNat) (by omega)
        simp only [Input.walk] at next
        rcases next with rejected | ⟨advances, inside⟩
        · exact Or.inl rejected
        · exact Or.inr ⟨by omega, inside⟩

/-- A child chain has exactly the required categories, strictly advancing
    endpoints, and no edge outside the input region. -/
inductive ChildChain (count : Nat) (kinds : Nat → Kind) (rule : Rule)
    (arity : Nat) (ends : Nat → Int) : Nat → Nat → Nat → Nat → Prop where
  | nil : ChildChain count kinds rule arity ends 0 child cursor cursor
  | cons {remaining child cursor endpoint : Nat} (inside : cursor < count)
      (kind : kinds cursor = expectedKind rule child arity)
      (advances : (cursor : Int) < ends cursor) (bounded : ends cursor ≤ count)
      (rest : ChildChain count kinds rule arity ends remaining (child + 1) (ends cursor).toNat endpoint) :
      ChildChain count kinds rule arity ends (remaining + 1) child cursor endpoint

abbrev Children (input : Input state) :=
  ChildChain input.count input.kinds input.rule input.arity input.ends

theorem ChildChain.advances (chain : ChildChain count kinds rule arity ends remaining child cursor endpoint) :
    cursor ≤ endpoint := by
  induction chain with
  | nil => omega
  | cons _ _ forward _ _ ih => omega

theorem ChildChain.bounded (chain : ChildChain count kinds rule arity ends remaining child cursor endpoint)
    (inside : cursor ≤ count) : endpoint ≤ count := by
  induction chain with
  | nil => exact inside
  | cons _ _ forward bound _ ih => exact ih (by omega)

theorem ChildChain.endpointUnique
    (left : ChildChain count kinds rule arity ends remaining child cursor endpoint)
    (right : ChildChain count kinds rule arity ends remaining child cursor other) : endpoint = other := by
  induction left generalizing other with
  | nil => cases right; rfl
  | cons _ _ _ _ _ ih => cases right with | cons _ _ _ _ tail => exact ih tail

/-- A parent store cannot invalidate child chains strictly after that parent. -/
theorem ChildChain.congrEnds
    (chain : ChildChain count kinds rule arity ends remaining child cursor endpoint)
    (lowerBound : lower ≤ cursor)
    (same : ∀ position, lower ≤ position → position < count → ends position = updated position) :
    ChildChain count kinds rule arity updated remaining child cursor endpoint := by
  induction chain with
  | nil => exact .nil
  | cons inside kind forward bounded rest ih =>
      have equal := same _ lowerBound inside
      apply ChildChain.cons inside kind (by rw [← equal]; exact forward) (by rw [← equal]; exact bounded)
      rw [← equal]
      exact ih (by omega)

theorem Input.walk_accepts (input : Input state) (remaining child cursor endpoint : Nat) :
    input.walk remaining child cursor = (endpoint : Int) ↔ Children input remaining child cursor endpoint := by
  induction remaining generalizing child cursor endpoint with
  | zero =>
      constructor
      · intro same; have : cursor = endpoint := by simpa only [Input.walk, walkChildren, Int.natCast_inj] using same
        subst endpoint; exact .nil
      · intro chain; cases chain; rfl
  | succ remaining ih =>
      simp only [Input.walk, walkChildren]
      split
      · rename_i bad
        constructor
        · intro impossible; omega
        · intro chain
          cases chain with
          | cons inside kind advances bounded rest =>
              exact False.elim (bad.elim (fun missing => by omega)
                (fun bad => bad.elim (fun wrong => wrong kind) (fun invalid => by omega)))
      · rename_i good
        constructor
        · intro accepted
          simp only [not_or] at good
          exact .cons (by omega) (Classical.byContradiction good.2.1) (by omega) (by omega)
            ((ih (child + 1) (input.ends cursor).toNat endpoint).mp accepted)
        · intro chain; cases chain with
          | cons _ _ _ _ rest => exact (ih _ _ _).mpr rest

private theorem kindComparison (left right : Kind) :
    evalBinaryValue extractedProgram.target .notEqual (kindValue left) (kindValue right) =
      .ok (.boolean (decide (left ≠ right))) := by
  cases left <;> cases right <;> rfl

private structure Context (base : State) extends Input base where
  formed : base.CellsWellFormed
  eventsFound : base.local? (source.argumentId 0) = some (.rawSlice eventType eventsAddress eventsLength)
  endsFound : base.local? (source.argumentId 1) = some (.rawSlice (.scalar (.signed .i32)) endsAddress count)
  countFound : base.local? (source.argumentId 2) = some (.signed .i32 count)
  indexFound : base.local? (source.argumentId 3) = some (.signed .i32 index)
  parentFound : base.local? (source.argumentId 4) =
    some (shapeValue (kindValue parentKind) arity (ruleValue rule))

private structure Frame (base current : State) (cursor child : Nat) : Prop extends
    LocalPair base current cursorId childId (.signed .i32 cursor) (.signed .i32 child) where
  heap : current.heap = base.heap
  world : current.world = base.world
  views : current.i32ArrayViews = base.i32ArrayViews

private theorem Frame.transPure (frame : Frame base before cursor child) (pure : PureFrame before after) :
    Frame base after cursor child :=
  ⟨frame.toLocalPair.transCells pure.cells pure.locals, pure.heap.trans frame.heap,
    pure.world.trans frame.world, pure.views.trans frame.views⟩

private theorem Context.eventRead (context : Context base) (frame : Frame base current cursor child)
    (inside : cursor < context.count) :
    readRawSliceIndex extractedProgram current eventType context.eventsAddress context.eventsLength cursor =
      .ok (context.events cursor) := by
  simpa only [readRawSliceIndex, frame.heap] using context.eventReads cursor inside

private theorem Context.endRead (context : Context base) (frame : Frame base current cursor child)
    (inside : cursor < context.count) :
    readRawSliceIndex extractedProgram current (.scalar (.signed .i32)) context.endsAddress context.count cursor =
      .ok (.signed .i32 (context.ends cursor)) := by
  simpa only [readRawSliceIndex, frame.heap] using context.endReads cursor inside

attribute [core_pure_rule] IRShapeProof.actualExpected

private theorem Context.preCheck (context : Context base) (frame : Frame base before cursor child)
    (truth : Bool) (checked : decide (context.count ≤ cursor ∨
      context.kinds cursor ≠ expectedKind context.rule child context.arity) = truth) :
    ∃ after, RunsExpr extractedProgram before preCheck (.boolean truth) after ∧ PureFrame before after := by
  core_facts [context, frame]
  have arityFits : context.arity < 2 ^ 31 := by have := context.room; have := context.fits; omega
  by_cases missing : context.count ≤ cursor
  · cases truth
    · exact False.elim ((of_decide_eq_false checked) (Or.inl missing))
    · core_pure_guard
  · have inside : cursor < context.count := by omega
    have read := context.eventRead frame inside
    have classified := context.classified cursor inside
    have comparison := kindComparison (context.kinds cursor) (expectedKind context.rule child context.arity)
    cases truth <;> core_pure_guard

private theorem Context.advance (context : Context base) (frame : Frame base before cursor child)
    (inside : cursor < context.count) (childInside : child < context.arity)
    (good : (cursor : Int) < context.ends cursor ∧ context.ends cursor ≤ context.count) :
    ∃ after, RunsStmt extractedProgram before advanceStmt .next after ∧
      Frame base after (context.ends cursor).toNat (child + 1) := by
  core_facts [context, frame]
  have read := context.endRead frame inside
  have childFits : child + 1 < 2 ^ 31 := by have := context.room; have := context.fits; omega
  have initial : RunsExpr extractedProgram before nextInitializer (.signed .i32 (context.ends cursor)) before := by
    core_run
  have beforeFormed := frame.cells.after_cellsWellFormed context.formed
  have readyFormed := beforeFormed.bindLocal nextId (.signed .i32 (context.ends cursor))
  have nextFound := beforeFormed.bindLocal_local nextId (.signed .i32 (context.ends cursor))
  have cursorFound := State.bindLocal_local?_of_ne before beforeFormed cursorId nextId _
    (.signed .i32 (context.ends cursor)) (by decide) frame.first
  have condition : RunsExpr extractedProgram (before.bindLocal nextId (.signed .i32 (context.ends cursor)))
      nextCondition (.boolean false) (before.bindLocal nextId (.signed .i32 (context.ends cursor))) := by core_run
  have check : RunsStmt extractedProgram (before.bindLocal nextId (.signed .i32 (context.ends cursor)))
      nextCheck .next (before.bindLocal nextId (.signed .i32 (context.ends cursor))) :=
    RunsStmt.ifThenElseFalse condition (RunsStmt.skip _ _)
  obtain ⟨after, run, pair, heap, world, views⟩ := LocalPair.scopedAdvance frame.toLocalPair context.formed
    (temporary := nextId) (expression := .local nextId) (nextCursor := context.ends cursor)
    (by decide) (by decide) childFits initial check (by core_run)
  refine ⟨after, run, ⟨?_, heap.trans frame.heap, world.trans frame.world, views.trans frame.views⟩⟩
  simpa only [Int.toNat_of_nonneg (by omega : 0 ≤ context.ends cursor)] using pair

private theorem Context.rejectEnd (context : Context base) (frame : Frame base before cursor child)
    (inside : cursor < context.count)
    (bad : context.ends cursor ≤ cursor ∨ (context.count : Int) < context.ends cursor) :
    ∃ after, RunsStmt extractedProgram before advanceStmt (.returned (some (.signed .i32 (-1)))) after ∧
      Frame base after cursor child := by
  core_facts [context, frame]
  have read := context.endRead frame inside
  obtain ⟨after, run, pure⟩ : ∃ after, RunsStmt extractedProgram before advanceStmt
      (.returned (some (.signed .i32 (-1)))) after ∧ PureFrame before after := by core_pure
  exact ⟨after, run, frame.transPure pure⟩

private theorem Context.step (context : Context base) (frame : Frame base before cursor child)
    (childInside : child < context.arity) :
    (∃ after, RunsStmt extractedProgram before loop.2 (.returned (some (.signed .i32 (-1)))) after ∧
      Frame base after cursor child ∧
      (context.count ≤ cursor ∨ context.kinds cursor ≠ expectedKind context.rule child context.arity ∨
        context.ends cursor ≤ cursor ∨ (context.count : Int) < context.ends cursor)) ∨
    (∃ after, RunsStmt extractedProgram before loop.2 .next after ∧
      Frame base after (context.ends cursor).toNat (child + 1) ∧
      ¬(context.count ≤ cursor ∨ context.kinds cursor ≠ expectedKind context.rule child context.arity ∨
        context.ends cursor ≤ cursor ∨ (context.count : Int) < context.ends cursor)) := by
  by_cases bad : context.count ≤ cursor ∨ context.kinds cursor ≠ expectedKind context.rule child context.arity
  · obtain ⟨after, condition, pure⟩ := context.preCheck frame true (by simp [bad])
    have returned : RunsStmt extractedProgram after
        (.returnValue (some (.unary .negate (.value (.signed .i32 1)))))
        (.returned (some (.signed .i32 (-1)))) after := by core_stmt
    exact Or.inl ⟨after, RunsStmt.sequenceCompleted (RunsStmt.ifThenElseTrue condition returned)
      (by simp) _, frame.transPure pure, bad.elim Or.inl (fun wrong => Or.inr (Or.inl wrong))⟩
  · obtain ⟨middle, condition, pure⟩ := context.preCheck frame false (by simp [bad])
    have nextFrame := frame.transPure pure
    have inside : cursor < context.count := by omega
    by_cases badEnd : context.ends cursor ≤ cursor ∨ (context.count : Int) < context.ends cursor
    · obtain ⟨after, run, framed⟩ := context.rejectEnd nextFrame inside badEnd
      exact Or.inl ⟨after, RunsStmt.sequenceNext
        (RunsStmt.ifThenElseFalse condition (RunsStmt.skip _ _)) run, framed, Or.inr (Or.inr badEnd)⟩
    · obtain ⟨after, run, framed⟩ := context.advance nextFrame inside childInside (by omega)
      exact Or.inr ⟨after, RunsStmt.sequenceNext
        (RunsStmt.ifThenElseFalse condition (RunsStmt.skip _ _)) run, framed, by
          simp only [not_or] at bad badEnd ⊢; exact ⟨bad.1, bad.2, badEnd.1, badEnd.2⟩⟩

private theorem Context.runLoop (context : Context base) (frame : Frame base before cursor child)
    (bounded : cursor ≤ context.count) (remaining : Nat) (left : remaining + child = context.arity) :
    ∃ completion after finalCursor finalChild,
      RunsStmt extractedProgram before (.whileLoop loop.1 loop.2) completion after ∧
      Frame base after finalCursor finalChild ∧
      ((completion = .next ∧ context.toInput.walk remaining child cursor = finalCursor) ∨
        (completion = .returned (some (.signed .i32 (-1))) ∧ context.toInput.walk remaining child cursor = -1)) := by
  induction remaining generalizing before cursor child with
  | zero =>
      core_facts [context, frame]
      have done : child = context.arity := by omega
      have condition : RunsExpr extractedProgram before loop.1 (.boolean false) before := by core_run
      exact ⟨.next, before, cursor, child, RunsStmt.whileFalse condition, frame, Or.inl ⟨rfl, rfl⟩⟩
  | succ remaining ih =>
      core_facts [context, frame]
      have childInside : child < context.arity := by omega
      have condition : RunsExpr extractedProgram before loop.1 (.boolean true) before := by core_run
      rcases context.step frame childInside with ⟨after, run, framed, bad⟩ | ⟨middle, run, framed, good⟩
      · exact ⟨_, after, cursor, child, RunsStmt.whileReturn condition run, framed,
          Or.inr ⟨rfl, by simp only [Input.walk, walkChildren, if_pos bad]⟩⟩
      · have nextBound : (context.ends cursor).toNat ≤ context.count := by omega
        obtain ⟨completion, after, finalCursor, finalChild, rest, finalFrame, result⟩ :=
          ih framed nextBound (by omega)
        refine ⟨completion, after, finalCursor, finalChild,
          RunsStmt.whileStep condition run (Or.inl rfl) rest, finalFrame, ?_⟩
        simpa only [Input.walk, walkChildren, if_neg good] using result

private theorem Context.body (context : Context base) :
    ∃ after, RunsStmt extractedProgram base (source.body.getD .skip)
      (.returned (some (.signed .i32 (context.toInput.walk context.arity 0 (context.index + 1))))) after ∧
      PureFrame base after := by
  core_facts [context]
  let first := base.bindLocal cursorId (.signed .i32 (context.index + 1 : Nat))
  let ready := first.bindLocal childId (.signed .i32 0)
  have frame : Frame base ready (context.index + 1) 0 :=
    ⟨LocalPair.start context.formed (by decide), rfl, rfl, rfl⟩
  obtain ⟨completion, after, finalCursor, finalChild, run, finalFrame, result⟩ :=
    context.runLoop frame (by omega) context.arity (by omega)
  have tailRun : RunsStmt extractedProgram ready
      (.sequence (.whileLoop loop.1 loop.2) (.returnValue (some (.local cursorId))))
      (.returned (some (.signed .i32 (context.toInput.walk context.arity 0 (context.index + 1))))) after := by
    rcases result with ⟨rfl, value⟩ | ⟨rfl, value⟩
    · rw [value]; exact RunsStmt.sequenceNext run (RunsStmt.returnValue (.ofStable (.local finalFrame.first) rfl))
    · rw [value]; exact RunsStmt.sequenceCompleted run (by simp) _
  have cursorFits : context.index + 1 < 2 ^ 31 := by omega
  have initial : RunsExpr extractedProgram base
      (.binary .add (.local (source.argumentId 3)) (.value (.signed .i32 1)))
      (.signed .i32 (context.index + 1 : Nat)) base := by core_run
  have full := RunsStmt.letLocal (type := .scalar (.signed .i32)) initial
    (RunsStmt.letLocal (type := .scalar (.signed .i32)) (id := childId) (.ofStable .value rfl) tailRun)
  have bodyShape : source.body.getD .skip =
      .letLocal cursorId (.scalar (.signed .i32))
        (.binary .add (.local (source.argumentId 3)) (.value (.signed .i32 1)))
        (.letLocal childId (.scalar (.signed .i32)) (.value (.signed .i32 0))
          (.sequence (.whileLoop loop.1 loop.2) (.returnValue (some (.local cursorId))))) := by rfl
  refine ⟨restoreLocals base after, ?_, ?_⟩
  · rw [bodyShape]; simpa only [restoreLocals] using full
  · exact (CallerFrame.mk context.formed finalFrame.cells finalFrame.heap finalFrame.world finalFrame.views).restoreLocals

def Input.call (input : Input state) : Expr :=
  .call source.id [.value (.rawSlice eventType input.eventsAddress input.eventsLength),
        .value (.rawSlice (.scalar (.signed .i32)) input.endsAddress input.count),
        .value (.signed .i32 input.count), .value (.signed .i32 input.index),
        .value (shapeValue (kindValue input.parentKind) input.arity (ruleValue input.rule))]

/-- The actual self-extracted helper terminates, returns the logical child
    endpoint (or -1 for a bad child), and preserves the caller and input heap. -/
theorem actualChildren (input : Input caller) (formed : caller.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram caller input.call
      (.signed .i32 (input.walk input.arity 0 (input.index + 1))) after ∧ PureFrame caller after := by
  core_call_pure source as callee
  let context : Context callee := {
    toInput := { input with
      eventReads := by intro position inside; exact input.eventReads position inside
      endReads := by intro position inside; exact input.endReads position inside }
    formed := by core_formed
    eventsFound := by core_local
    endsFound := by core_local
    countFound := by core_local
    indexFound := by core_local
    parentFound := by core_local }
  exact context.body

def EndpointCorrect (input : Input state) (result : Int) : Prop :=
  (∃ endpoint : Nat, result = endpoint ∧ Children input input.arity 0 (input.index + 1) endpoint) ∨
  (result = -1 ∧ ¬∃ endpoint, Children input input.arity 0 (input.index + 1) endpoint)

theorem actualChildrenCorrect (input : Input caller) (formed : caller.CellsWellFormed) :
    ∃ result after, RunsExpr extractedProgram caller input.call (.signed .i32 result) after ∧
      PureFrame caller after ∧ EndpointCorrect input result := by
  obtain ⟨after, run, frame⟩ := actualChildren input formed
  refine ⟨_, after, run, frame, ?_⟩
  have inside := input.inside
  rcases input.walk_bounds input.arity 0 (input.index + 1) (by omega) with rejected | ⟨nonnegative, _⟩
  · exact Or.inr ⟨rejected, by
      rintro ⟨endpoint, chain⟩
      have accepted := (input.walk_accepts _ _ _ _).mpr chain
      omega⟩
  · have represented : input.walk input.arity 0 (input.index + 1) =
        (input.walk input.arity 0 (input.index + 1)).toNat := by omega
    exact Or.inl ⟨_, represented, (input.walk_accepts _ _ _ _).mp represented⟩

#print axioms Input.walk_bounds
#print axioms Input.walk_accepts
#print axioms Context.preCheck
#print axioms Context.step
#print axioms Context.runLoop
#print axioms actualChildren
#print axioms actualChildrenCorrect

end IRChildrenProof
