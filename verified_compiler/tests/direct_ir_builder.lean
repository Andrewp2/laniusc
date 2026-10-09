import verified_compiler.tests.direct_ir_children
import verified_compiler.tests.direct_ir_allocation
import Lanius.Semantics.CountedLocal
import Lanius.Semantics.NativeReadFrame

namespace IRBuilderProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRShapeProof IRChildrenProof

private def source := Extracted.«ir::body_tree».Functions.«build».core
private def emptySource := Extracted.«ir::body_tree».Functions.«empty».core
private def shapeSource := Extracted.«ir::body_tree».Functions.«shape».core
private def childSource := Extracted.«ir::body_tree».Functions.«children_end».core
private def eventType := ((shapeSource.parameters[0]?).getD (0, .unit)).2
private def referenceType := ((Extracted.«ir::type_ref».Functions.«is_invalid».core.parameters[0]?).getD (0, .unit)).2
private def endsId := source.bindingId 1
private def eventsId := source.bindingId 2
private def indexId := source.bindingId 3
private def parentId := source.bindingId 4
private def cursorId := source.bindingId 5
private def firstLoop : Stmt → Option (Expr × Stmt)
  | .whileLoop guard body => some (guard, body)
  | .letLocal _ _ _ body | .letUninitialized _ _ body => firstLoop body
  | .sequence first second => firstLoop first |>.or (firstLoop second)
  | _ => none
def loop : Expr × Stmt := (firstLoop (source.body.getD .skip)).getD (.value (.boolean false), .skip)
private def parentInitializer : Expr := match loop.2 with
  | .letLocal _ _ expression _ => expression
  | _ => .value .unit
private def parentGuard : Expr := match loop.2 with
  | .letLocal _ _ _ (.sequence (.ifThenElse guard _ _) _) => guard
  | _ => .value .unit
private def parentBody : Stmt := match loop.2 with
  | .letLocal _ _ _ body => body
  | _ => .skip
private def childInitializer : Expr := match loop.2 with
  | .letLocal _ _ _ (.sequence _ (.letLocal _ _ expression _)) => expression
  | _ => .value .unit
private def childBody : Stmt := match parentBody with
  | .sequence _ (.letLocal _ _ _ body) => body
  | _ => .skip

def emptyTree : Value := source_value Extracted.«ir::body_tree».Types.«Tree».mk
  [.rawSlice eventType 0 0, .rawSlice referenceType 0 0, .boolean false,
    .rawSlice (.scalar (.signed .i32)) 0 0, .signed .i32 0]

@[core_pure_rule] theorem actualEmpty (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (.call emptySource.id []) emptyTree after ∧ PureFrame state after := by
  have eventLayout : NativeLayout.valueWords? extractedProgram eventType = some 5 := by decide +kernel
  have referenceLayout : NativeLayout.valueWords? extractedProgram referenceType = some 2 := by decide +kernel
  core_call_pure emptySource as callee
  let ready := callee.bindLocal (emptySource.bindingId 0) (.pointer 0)
  have calleeFormed : callee.CellsWellFormed := by core_formed
  have pointer : ready.local? (emptySource.bindingId 0) = some (.pointer 0) := by core_local
  have eventSlice : RunsExpr extractedProgram ready
      (.typedSliceFromRawParts eventType (.local (emptySource.bindingId 0)) (.value (.signed .i32 0)))
      (.rawSlice eventType 0 0) ready := RunsExpr.ofStable
        (StableExpr.emptyRawNominalSlice (.local pointer) .value rfl eventLayout (by decide)) rfl
  have referenceSlice : RunsExpr extractedProgram ready
      (.typedSliceFromRawParts referenceType (.local (emptySource.bindingId 0)) (.value (.signed .i32 0)))
      (.rawSlice referenceType 0 0) ready := RunsExpr.ofStable
        (StableExpr.emptyRawNominalSlice (.local pointer) .value rfl referenceLayout (by decide)) rfl
  refine ⟨restoreLocals callee ready, ?_, (CallerFrame.refl calleeFormed).bindLocal _ _ |>.restoreLocals⟩
  core_stmt

/-- The logical event sequence is read from the original heap, before fresh
    endpoint storage is added. No classifier or builder run is assumed. -/
structure Source (original : State) where
  count : Nat
  eventsAddress : Nat
  eventsLength : Nat
  events : Nat → Value
  kinds : Nat → Kind
  arities : Nat → Int
  rules : Nat → Rule
  fits : count < 2 ^ 31
  below : HeapBlocksBelowNext original.heap
  reads : ∀ position, position < count →
    readRawSliceIndex extractedProgram original eventType eventsAddress eventsLength position = .ok (events position)
  classified : ∀ position, position < count →
    Classifies (events position) (shapeValue (kindValue (kinds position)) (arities position) (ruleValue (rules position)))

def Source.Node (input : Source original) (ends : Nat → Int) (index : Nat) : Prop :=
  0 ≤ input.arities index ∧ input.arities index ≤ (input.count - index - 1 : Nat) ∧
  input.kinds index ≠ .InvalidNode ∧ ∃ endpoint : Nat, ends index = endpoint ∧
    ChildChain input.count input.kinds (input.rules index) (input.arities index).toNat ends
      (input.arities index).toNat 0 (index + 1) endpoint

def Source.Suffix (input : Source original) (ends : Nat → Int) (first : Nat) : Prop :=
  ∀ index, first ≤ index → index < input.count → input.Node ends index

/-- The preorder shape determines its endpoints uniquely. Consumers do not
    need an independent endpoint validator or a supplied execution result. -/
theorem Source.equalEndpoints (input : Source original)
    (left : input.Suffix ends first) (right : input.Suffix other first) :
    ∀ index, first ≤ index → index < input.count → ends index = other index := by
  have unique : ∀ distance index, input.count - index = distance →
      first ≤ index → index < input.count → ends index = other index := by
    intro distance
    induction distance using Nat.strongRecOn with
    | ind distance ih =>
        intro index measure later inside
        obtain ⟨_, _, _, endpoint, found, chain⟩ := left index later inside
        obtain ⟨_, _, _, otherEndpoint, otherFound, otherChain⟩ := right index later inside
        have transported := chain.congrEnds (lower := index + 1) (Nat.le_refl _) (by
          intro child after bounded
          exact ih (input.count - child) (by omega) child rfl (by omega) bounded)
        rw [found, otherFound, transported.endpointUnique otherChain]
  intro index later inside
  exact unique (input.count - index) index rfl later inside

theorem Source.extendSuffix (input : Source original) (suffix : input.Suffix ends (index + 1))
    (good : 0 ≤ input.arities index ∧ input.arities index ≤ (input.count - index - 1 : Nat) ∧
      input.kinds index ≠ .InvalidNode)
    (chain : ChildChain input.count input.kinds (input.rules index) (input.arities index).toNat ends
      (input.arities index).toNat 0 (index + 1) endpoint) :
    input.Suffix (fun position => if position = index then (endpoint : Int) else ends position) index := by
  intro position lower inside
  by_cases same : position = index
  · subst position
    refine ⟨good.1, good.2.1, good.2.2, endpoint, by simp,
      chain.congrEnds (lower := index + 1) (by omega) ?_⟩
    intro child later _; simp [show child ≠ index by omega]
  · obtain ⟨nonnegative, room, kind, endpoint, value, children⟩ := suffix position (by omega) inside
    refine ⟨nonnegative, room, kind, endpoint, by simp [same, value],
      children.congrEnds (lower := index + 1) (by omega) ?_⟩
    intro child later _; simp [show child ≠ index by omega]

structure Context (original base : State) extends Source original where
  formed : base.CellsWellFormed
  endsAddress : Nat
  fresh : original.heap.nextAddress ≤ endsAddress
  eventsFound : base.local? eventsId = some (.rawSlice eventType eventsAddress eventsLength)
  endsFound : base.local? endsId = some (.rawSlice (.scalar (.signed .i32)) endsAddress count)
  countFound : base.local? (source.argumentId 1) = some (.signed .i32 count)

structure Table (context : Context original base) (state : State) (ends : Nat → Int) : Prop where
  oldReads : HeapReads original.heap state.heap
  readable : state.heap.Readable context.endsAddress (context.count * 4)
  unique : HeapBlockBasesUnique state.heap
  views : state.i32ArrayViews = []
  below : HeapBlocksBelowNext state.heap
  endReads : ∀ position, position < context.count →
    readRawSliceIndex extractedProgram state (.scalar (.signed .i32)) context.endsAddress context.count position =
      .ok (.signed .i32 (ends position))
  writes : HeapRegionWrite base.heap state.heap context.endsAddress (context.count * 4)

theorem Table.transPure (table : Table context before ends) (pure : PureFrame before after) :
    Table context after ends := by
  rcases table with ⟨old, readable, unique, views, below, endReads, writes⟩
  refine ⟨by rw [pure.heap]; exact old, by rw [pure.heap]; exact readable,
    by rw [pure.heap]; exact unique, pure.views.trans views,
    by rw [pure.heap]; exact below, ?_, by rw [pure.heap]; exact writes⟩
  intro position inside
  simpa only [readRawSliceIndex, pure.heap] using endReads position inside

theorem Table.restoreLocals (table : Table context state ends) (scope : State) :
    Table context (restoreLocals scope state) ends :=
  ⟨table.oldReads, table.readable, table.unique, table.views, table.below, table.endReads, table.writes⟩

private theorem Table.bindLocal {id : VarId} (table : Table context state ends) :
    Table context (state.bindLocal id value) ends :=
  ⟨table.oldReads, table.readable, table.unique, table.views, table.below, table.endReads, table.writes⟩

/-- The real allocator's zeroed storage establishes all endpoint reads.
    The initial table is not assumed to contain prevalidated endpoints. -/
theorem Table.allocated (context : Context original base)
    (heap : base.heap = original.heap.appendI32 (List.replicate (context.count * 4) 0) false budget)
    (address : context.endsAddress = original.heap.borrowedAddress)
    (unique : HeapBlockBasesUnique original.heap) (views : base.i32ArrayViews = []) :
    Table context base (fun _ => 0) := by
  refine ⟨by rw [heap]; exact HeapReads.appendI32,
    ?_, by rw [heap]; exact Heap.appendI32_unique context.below unique, views,
    by rw [heap]; exact Heap.appendI32_below context.below, ?_,
    HeapRegionWrite.refl _ (by rw [heap]; exact Heap.appendI32_unique context.below unique)⟩
  · rw [heap, address]
    simpa only [List.length_replicate] using
      Heap.appendI32_readable (bytes := List.replicate (context.count * 4) 0) context.below
  · intro position inside
    apply Extraction.OutputPacking.readRawSliceIndex_i32Nat extractedProgram base 0 (by decide) inside
    rw [heap, address]
    exact Heap.appendI32_zeroWord context.below inside

private def Context.childInput (context : Context original base) (table : Table context state ends)
    (inside : index < context.count) (nonnegative : 0 ≤ context.arities index)
    (room : context.arities index ≤ (context.count - index - 1 : Nat)) : Input state := {
  count := context.count, index := index, arity := (context.arities index).toNat
  eventsAddress := context.eventsAddress, eventsLength := context.eventsLength, endsAddress := context.endsAddress
  fits := context.fits, inside := inside, room := by omega
  parentKind := context.kinds index, rule := context.rules index
  events := context.events, kinds := context.kinds
  eventArities := context.arities, eventRules := context.rules, ends := ends
  eventReads := fun position bound => table.oldReads.rawSlice (context.reads position bound)
  endReads := table.endReads, classified := context.classified }

private theorem kindInvalid (kind : Kind) :
    evalBinaryValue extractedProgram.target .equal (kindValue kind) (kindValue .InvalidNode) =
      .ok (.boolean (decide (kind = .InvalidNode))) := by cases kind <;> rfl

private theorem Context.parentCondition (context : Context original base)
    (formed : state.CellsWellFormed) (inside : index < context.count)
    (countFound : state.local? (source.argumentId 1) = some (.signed .i32 context.count))
    (indexFound : state.local? indexId = some (.signed .i32 index))
    (parentFound : state.local? parentId = some
      (shapeValue (kindValue (context.kinds index)) (context.arities index) (ruleValue (context.rules index))))
    (truth : Bool) (checked : decide (context.arities index < 0 ∨
      (context.count - index - 1 : Nat) < context.arities index ∨ context.kinds index = .InvalidNode) = truth) :
    RunsExpr extractedProgram state parentGuard (.boolean truth) state := by
  have countFits := context.fits
  have subtraction := eval_i32_subNat extractedProgram.target context.count index (by omega) countFits
  have predecessor := eval_i32_subNat extractedProgram.target (context.count - index) 1 (by omega) (by omega)
  have comparison := kindInvalid (context.kinds index)
  cases truth <;> core_run

private theorem Table.store {index endpoint : Nat} (context : Context original base) (table : Table context before ends)
    (inside : index < context.count) (fits : endpoint < 2 ^ 31)
    (endsFound : before.local? endsId = some (.rawSlice (.scalar (.signed .i32)) context.endsAddress context.count))
    (indexFound : before.local? indexId = some (.signed .i32 index))
    (cursorFound : before.local? cursorId = some (.signed .i32 endpoint)) :
    ∃ heap, RunsExpr extractedProgram before (source.effectExpression 0) .unit { before with heap } ∧
      Table context { before with heap } (fun position => if position = index then (endpoint : Int) else ends position) := by
  obtain ⟨heap, run, written, readable, entry, _⟩ := IRAllocationProof.actualEndpointStore
    context.count index endpoint context.endsAddress inside fits endsFound indexFound cursorFound
    table.readable table.unique table.views
  refine ⟨heap, run, ⟨table.oldReads.writeFresh context.below (by
    have fresh := context.fresh; dsimp only [Address] at *; omega) written,
    readable, written.unique, table.views, written.below table.below, ?_,
    table.writes.trans ((HeapRegionWrite.ofBytes written).enlarge (by omega) (by
      simp only [i32Bytes, List.length_map, List.length_range]; omega))⟩⟩
  intro position bound
  by_cases same : position = index
  · subst position; simpa using entry
  · simp only [if_neg same]
    apply readRawSliceIndex_i32_disjoint written bound (table.readable.subrange (by omega)) _ (table.endReads position bound)
    have length : (i32Bytes (endpoint : Int)).length = 4 := by simp [i32Bytes]
    rw [length]; dsimp only [Address]; omega

structure Frame (context : Context original base) (state : State) (ends : Nat → Int) (remaining : Nat) : Prop extends
    CountedLocal base state indexId ((remaining : Int) - 1) where
  table : Table context state ends
  suffix : context.toSource.Suffix ends remaining
  world : state.world = base.world

private theorem Frame.transPure (frame : Frame context before ends remaining) (pure : PureFrame before after) :
    Frame context after ends remaining :=
  ⟨frame.toCountedLocal.transCells pure.cells pure.locals, frame.table.transPure pure,
    frame.suffix, pure.world.trans frame.world⟩

def BadNode (input : Source original) (ends : Nat → Int) (index : Nat) : Prop :=
  input.arities index < 0 ∨ (input.count - index - 1 : Nat) < input.arities index ∨
  input.kinds index = .InvalidNode ∨ ¬∃ endpoint, ChildChain input.count input.kinds
    (input.rules index) (input.arities index).toNat ends (input.arities index).toNat 0 (index + 1) endpoint

/-- Valid source structure cannot fail at the next node once the actual
    reverse traversal has established its later suffix. -/
theorem Source.noBadNode (input : Source original) {canonical : Nat → Int} (valid : input.Suffix canonical 0)
    (later : input.Suffix ends (index + 1)) (inside : index < input.count) :
    ¬ BadNode input ends index := by
  obtain ⟨nonnegative, room, kind, endpoint, _, chain⟩ := valid index (Nat.zero_le _) inside
  have same := input.equalEndpoints
    (fun position _ bounded => valid position (Nat.zero_le _) bounded) later
  have children := chain.congrEnds (Nat.le_refl _) same
  rintro (negative | short | invalid | absent)
  · omega
  · omega
  · exact kind invalid
  · exact absent ⟨endpoint, children⟩

/-- The actual loop body either rejects a structurally bad node, or writes
    exactly one endpoint and extends the proved suffix by one node. -/
theorem actualIteration (context : Context original base) (frame : Frame context before ends (index + 1))
    (inside : index < context.count) :
    (∃ after, RunsStmt extractedProgram before loop.2 (.returned (some emptyTree)) after ∧
      Frame context after ends (index + 1) ∧ BadNode context.toSource ends index) ∨
    (∃ (endpoint : Nat) (after : State), RunsStmt extractedProgram before loop.2 .next after ∧
      Frame context after (fun position => if position = index then (endpoint : Int) else ends position) index) := by
  core_facts [context, frame]
  have beforeFormed := frame.cells.after_cellsWellFormed context.formed
  have indexFound : before.local? indexId = some (.signed .i32 index) := by
    simpa only [Int.natCast_add, Int.natCast_one, Int.add_sub_cancel] using frame.counter
  have eventsFound : before.local? eventsId = some (.rawSlice eventType context.eventsAddress context.eventsLength) := by core_local
  have eventRead := frame.table.oldReads.rawSlice (context.reads index inside)
  have classified := context.classified index inside
  obtain ⟨middle, parentRun, parentPure⟩ : ∃ middle,
      RunsExpr extractedProgram before parentInitializer
        (shapeValue (kindValue (context.kinds index)) (context.arities index) (ruleValue (context.rules index))) middle ∧
      PureFrame before middle := by core_pure_expr
  let parentValue := shapeValue (kindValue (context.kinds index)) (context.arities index) (ruleValue (context.rules index))
  let ready := middle.bindLocal parentId parentValue
  have readyFormed : ready.CellsWellFormed := by core_formed
  have parentFound : ready.local? parentId = some parentValue := by core_local
  have readyCount : ready.local? (source.argumentId 1) = some (.signed .i32 context.count) := by core_local
  have readyIndex : ready.local? indexId = some (.signed .i32 index) := by core_local
  have readyTable : Table context ready ends := (frame.table.transPure parentPure).bindLocal
  by_cases bad : context.arities index < 0 ∨
      (context.count - index - 1 : Nat) < context.arities index ∨ context.kinds index = .InvalidNode
  · have condition := context.parentCondition readyFormed inside readyCount readyIndex parentFound true (by simp [bad])
    obtain ⟨completed, bodyRun, bodyPure⟩ : ∃ after, RunsStmt extractedProgram ready parentBody
        (.returned (some emptyTree)) after ∧ PureFrame ready after := by core_pure
    obtain ⟨after, run, pure⟩ := RunsStmt.letLocalPure parentRun parentPure bodyRun bodyPure
    exact Or.inl ⟨after, run, frame.transPure pure, by
      rcases bad with bad | bad | bad
      · exact Or.inl bad
      · exact Or.inr (Or.inl bad)
      · exact Or.inr (Or.inr (Or.inl bad))⟩
  · have good : 0 ≤ context.arities index ∧ context.arities index ≤ (context.count - index - 1 : Nat) ∧
        context.kinds index ≠ .InvalidNode := by
      simp only [not_or] at bad
      exact ⟨by omega, by omega, bad.2.2⟩
    have condition := context.parentCondition readyFormed inside readyCount readyIndex parentFound false (by simp [bad])
    let input := context.childInput readyTable inside good.1 good.2.1
    obtain ⟨result, prepared, called, pure, correct⟩ := actualChildrenCorrect input readyFormed
    have readyEvents : ready.local? eventsId = some (.rawSlice eventType context.eventsAddress context.eventsLength) := by core_local
    have readyEnds : ready.local? endsId = some (.rawSlice (.scalar (.signed .i32)) context.endsAddress context.count) := by core_local
    have arity : ((context.arities index).toNat : Int) = context.arities index := Int.toNat_of_nonneg good.1
    have childRun : RunsExpr extractedProgram ready childInitializer (.signed .i32 result) prepared := by
      apply RunsExpr.callArguments (values := [.rawSlice eventType context.eventsAddress context.eventsLength,
        .rawSlice (.scalar (.signed .i32)) context.endsAddress context.count, .signed .i32 context.count,
        .signed .i32 index, parentValue]) (by core_arguments)
      have same : Expr.call childSource.id ([.rawSlice eventType context.eventsAddress context.eventsLength,
          .rawSlice (.scalar (.signed .i32)) context.endsAddress context.count, .signed .i32 context.count,
          .signed .i32 index, parentValue].map Expr.value) = input.call := by
        simp only [Input.call, input, Context.childInput, arity, parentValue, List.map_cons, List.map_nil]
        rfl
      change RunsExpr extractedProgram ready (.call childSource.id _) (.signed .i32 result) prepared
      rw [same]
      exact called
    let current := prepared.bindLocal cursorId (.signed .i32 result)
    have currentFormed : current.CellsWellFormed := by core_formed
    have cursorFound : current.local? cursorId = some (.signed .i32 result) := by core_local
    rcases correct with ⟨endpoint, accepted, chain⟩ | ⟨rejected, noChain⟩
    · have bounded : endpoint ≤ context.count := chain.bounded (by change index + 1 ≤ context.count; omega)
      have fits : endpoint < 2 ^ 31 := by have := context.fits; omega
      have currentTable : Table context current ends := (readyTable.transPure pure).bindLocal
      have currentEnds : current.local? endsId = some (.rawSlice (.scalar (.signed .i32)) context.endsAddress context.count) := by core_local
      have currentIndex : current.local? indexId = some (.signed .i32 index) := by core_local
      obtain ⟨heap, stored, table⟩ := currentTable.store context inside fits currentEnds currentIndex
        (by simpa only [accepted] using cursorFound)
      let written := { current with heap }
      have cells : FreshCellFrame base written := ((frame.cells.trans parentPure.cells).trans
        (FreshCellFrame.bindLocal middle parentId parentValue)).trans
        (pure.cells.trans (FreshCellFrame.bindLocal prepared cursorId (.signed .i32 result)))
      have counterCell : written.cellId? indexId = some base.nextCell := by
        change (prepared.bindLocal cursorId (.signed .i32 result)).cellId? indexId = _
        rw [State.bindLocal_cellId_of_ne _ _ _ (by decide : cursorId ≠ indexId)]
        have readyCell : prepared.cellId? indexId = ready.cellId? indexId := by
          simp only [State.cellId?, pure.locals]
        rw [readyCell]
        change (middle.bindLocal parentId parentValue).cellId? indexId = _
        rw [State.bindLocal_cellId_of_ne _ _ _ (by decide : parentId ≠ indexId)]
        simp only [State.cellId?, parentPure.locals, frame.locals]
        simp
      have counter : CountedLocal base before indexId index := by
        simpa only [Int.natCast_add, Int.natCast_one, Int.add_sub_cancel] using frame.toCountedLocal
      obtain ⟨after, decremented, nextCounter, heapSame, worldSame, viewsSame⟩ :=
        counter.decrementScoped (program := extractedProgram) context.formed cells counterCell currentIndex
          (by have := context.fits; omega)
      have run : RunsStmt extractedProgram before loop.2 .next (restoreLocals before after) := by
        have nonnegative : 0 ≤ result := by omega
        have bodyRun : RunsStmt extractedProgram current childBody .next after := by core_stmt
        have cursorRun := RunsStmt.letLocal (id := cursorId) (type := .scalar (.signed .i32)) childRun bodyRun
        have tailRun : RunsStmt extractedProgram ready parentBody .next (restoreLocals prepared after) :=
          RunsStmt.sequenceNext (RunsStmt.ifThenElseFalse condition (RunsStmt.skip _ _)) cursorRun
        let parentType : Ty := match loop.2 with | .letLocal _ type _ _ => type | _ => .unit
        have full := RunsStmt.letLocal (id := parentId) (type := parentType) parentRun tailRun
        have bodyShape : loop.2 = .letLocal parentId parentType parentInitializer parentBody := by rfl
        rw [bodyShape]
        simpa only [restoreLocals, parentPure.locals] using full
      refine Or.inr ⟨endpoint, restoreLocals before after, run, ⟨nextCounter, ?_,
        context.toSource.extendSuffix frame.suffix good chain, ?_⟩⟩
      · rcases table with ⟨old, readable, unique, views, below, endReads, writes⟩
        refine ⟨by simpa only [restoreLocals, heapSame] using old,
          by simpa only [restoreLocals, heapSame] using readable,
          by simpa only [restoreLocals, heapSame] using unique, viewsSame.trans views,
          by simpa only [restoreLocals, heapSame] using below, ?_,
          by simpa only [restoreLocals, heapSame] using writes⟩
        intro position bound
        simpa only [readRawSliceIndex, restoreLocals, heapSame] using endReads position bound
      · exact worldSame.trans (pure.world.trans (parentPure.world.trans frame.world))
    · have negative : result < 0 := by omega
      obtain ⟨completed, bodyRun, bodyPure⟩ : ∃ after, RunsStmt extractedProgram current childBody
          (.returned (some emptyTree)) after ∧ PureFrame current after := by core_pure
      obtain ⟨restored, childStmtRun, childPure⟩ := RunsStmt.letLocalPure
        (id := cursorId) (type := .scalar (.signed .i32)) childRun pure bodyRun bodyPure
      have parentStmtRun : RunsStmt extractedProgram ready parentBody (.returned (some emptyTree)) restored :=
        RunsStmt.sequenceNext (RunsStmt.ifThenElseFalse condition (RunsStmt.skip _ _)) childStmtRun
      obtain ⟨after, run, framed⟩ := RunsStmt.letLocalPure parentRun parentPure parentStmtRun childPure
      exact Or.inl ⟨after, run, frame.transPure framed, Or.inr (Or.inr (Or.inr noChain))⟩

/-- Run every remaining parent, including early rejection. The natural
    induction measure decreases while the actual signed local reaches -1. -/
theorem actualLoop (context : Context original base) (frame : Frame context before ends remaining)
    (bounded : remaining ≤ context.count) :
    ∃ completion after finalEnds finalRemaining,
      RunsStmt extractedProgram before (.whileLoop loop.1 loop.2) completion after ∧
      Frame context after finalEnds finalRemaining ∧
      ((completion = .next ∧ finalRemaining = 0) ∨
        (completion = .returned (some emptyTree) ∧ ∃ index,
          finalRemaining = index + 1 ∧ index < context.count ∧ BadNode context.toSource finalEnds index)) := by
  induction remaining generalizing before ends with
  | zero =>
      core_facts [context, frame]
      have condition : RunsExpr extractedProgram before loop.1 (.boolean false) before := by core_run
      exact ⟨.next, before, ends, 0, RunsStmt.whileFalse condition, frame, Or.inl ⟨rfl, rfl⟩⟩
  | succ remaining ih =>
      core_facts [context, frame]
      have condition : RunsExpr extractedProgram before loop.1 (.boolean true) before := by core_run
      rcases actualIteration context frame (by omega) with ⟨after, run, framed, rejected⟩ |
          ⟨endpoint, middle, run, framed⟩
      · exact ⟨_, after, ends, remaining + 1, RunsStmt.whileReturn condition run, framed,
          Or.inr ⟨rfl, remaining, rfl, by omega, rejected⟩⟩
      · obtain ⟨completion, after, finalEnds, finalRemaining, rest, finalFrame, result⟩ := ih framed (by omega)
        exact ⟨completion, after, finalEnds, finalRemaining,
          RunsStmt.whileStep condition run (Or.inl rfl) rest, finalFrame, result⟩

/-- A fresh builder starts with no completed nodes. No prevalidated suffix
    or successful validator execution is required. -/
theorem Frame.start (context : Context original base) (table : Table context base ends) :
    Frame context (base.bindLocal indexId (.signed .i32 ((context.count : Int) - 1))) ends context.count :=
  ⟨CountedLocal.start context.formed _ _, table.bindLocal,
    by intro index lower inside; omega, rfl⟩

#print axioms actualEmpty
#print axioms Source.extendSuffix
#print axioms Source.equalEndpoints
#print axioms Source.noBadNode
#print axioms actualIteration
#print axioms actualLoop

end IRBuilderProof
