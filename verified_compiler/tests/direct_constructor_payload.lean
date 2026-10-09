import verified_compiler.tests.direct_type_name
import verified_compiler.tests.direct_surface_fallback
import Lanius.Extraction.WriterCursor

namespace ConstructorPayloadProof

open Lanius Lanius.Core Lanius.Semantics Lanius.Extraction Lanius.Memory
open SurfaceBooleanProof SurfaceDispatchProof IRBuilderNavigationProof

private def source := Extracted.«verified::lean_typed_body».Functions.«surface_constructor_output».core
private def metadataSource := Extracted.«ir::body_events».Functions.«enumeration_fields».core
private def cursorId := source.bindingId 3
private def childId := source.bindingId 4
private def ordinalId := source.bindingId 5
private def loop : Expr × Stmt := match source.body with
  | some (.letLocal _ _ _ (.letLocal _ _ _ (.letLocal _ _ _ (.letLocal _ _ _
      (.sequence _ (.letLocal _ _ _ (.letLocal _ _ _ (.sequence (.whileLoop guard body) _)))))))) => (guard, body)
  | _ => (.value (.boolean true), .skip)
private def right (index : Nat) : Expr := match source.effectExpression index with
  | .assign _ _ expression => expression | _ => .value .unit
private def arguments (index : Nat) : List Expr := match right index with
  | .call _ args => args | _ => []
private def body : Stmt := match source.body with
  | some (.letLocal _ _ _ (.letLocal _ _ _ (.letLocal _ _ _ body))) => body
  | _ => .skip
private def ending : Stmt := match body with
  | .letLocal _ _ _ (.sequence _ (.letLocal _ _ _ (.letLocal _ _ _
      (.sequence _ (.sequence _ (.sequence _ last)))))) => last
  | _ => .skip

def chunk (output : List UInt8) : List UInt8 := [32, 40] ++ output ++ [41]
def bytes (outputs : List (List UInt8)) : List UInt8 := outputs.flatMap chunk
-- Open recursive obligations are internal to the constructor step. The
-- complete expression induction, not a native-input predicate, closes them.
def ChildWriters (tree : Ready region { heap := reference }) (scope : Scope) : List (List UInt8) → Nat → Prop
  | [], _ => True
  | output :: rest, child => Writer Context.expressionCall reference tree.value child output scope ∧
      ChildWriters tree scope rest (tree.ends child).toNat
private def childValue (expressions : List (List UInt8)) (child : Nat) : Int :=
  if expressions.isEmpty then -1 else child
private def enumeration (typeId variant count : Nat) : Value :=
  source_value Extracted.«ir::body_events».Types.«EnumVariant».mk
    [.signed .i32 typeId, .signed .i32 variant, .signed .i32 count]

/-- The loop's immutable caller bindings and fresh controls. These are native
    input/storage facts, not successful navigation or printing executions. -/
private structure Input (base : State) (region : IRBuilderCallProof.Region original) where
  reference : Heap
  context : Context base
  inputMemory : Protected context reference
  tree : Ready region { heap := reference }
  representation : context.tree = tree.value
  scope : Scope
  nameContext : scope.Matches context
  parent : Nat
  count : Nat
  typeId : Nat
  variant : Nat
  fits : count < 2 ^ 31
  cursorCell : CellId
  childCell : CellId
  ordinalCell : CellId
  childFresh : base.nextCell ≤ childCell
  ordinalFresh : base.nextCell ≤ ordinalCell
  childCursor : childCell ≠ cursorCell
  ordinalCursor : ordinalCell ≠ cursorCell
  controlsDifferent : childCell ≠ ordinalCell
  view : base.local? (source.bindingId 0) = some context.value
  constructor : base.local? (source.bindingId 2) = some (enumeration typeId variant count)
  views : base.local? (source.argumentId 0) = some context.views
  index : base.local? (source.argumentId 1) = some (.signed .i32 parent)
  environment : WriterEnvironment base

private abbrev Cursor (input : Input base region) (current : State) (front : List UInt8) : Prop :=
  WriterCursor base current cursorId input.cursorCell (input.context.address + input.context.position)
    input.context.position front (scope := [(ordinalId, input.ordinalCell), (childId, input.childCell)])

/-- One real payload iteration, reused by the final expression induction. -/
private theorem iteration (input : Input base region) (cursor : Cursor input current front)
    (expression : List UInt8) (rest : List (List UInt8))
    (writer : Writer Context.expressionCall input.reference input.tree.value child expression input.scope)
    (children : input.tree.Children input.parent ordinal (rest.length + 1) child)
    (ordered : input.parent < child) (count : ordinal + (expression :: rest).length = input.count)
    (childLocal : current.local? childId = some (.signed .i32 child))
    (ordinalLocal : current.local? ordinalId = some (.signed .i32 ordinal))
    (room : input.context.position + (front ++ chunk expression ++ bytes rest).length ≤ input.context.capacity) :
    ∃ after, RunsExpr extractedProgram current loop.1 (.boolean true) current ∧
      RunsStmt extractedProgram current loop.2 .next after ∧
      Cursor input after (front ++ chunk expression) ∧
      after.local? childId = some (.signed .i32 (childValue rest (input.tree.ends child).toNat)) ∧
      after.local? ordinalId = some (.signed .i32 (ordinal + 1 : Nat)) := by
  core_facts 1 [input]
  have formed := input.environment.formed
  have differentIds : ordinalId ≠ childId := by decide
  have guard : RunsExpr extractedProgram current loop.1 (.boolean true) current := by
    have less : (ordinal : Int) < input.count := by simp only [List.length_cons] at count; omega
    core_run
  have lengths : input.context.position + front.length + expression.length + 3 ≤ input.context.capacity := by
    simp only [chunk, List.length_append, List.length_cons, List.length_nil] at room
    omega
  have childSafe {state : State} {output : List UInt8} (c : Cursor input state output) : state.cellId? childId ≠ some input.cursorCell := by
    simp [State.cellId?, c.locals, differentIds, input.childCursor]
  have ordinalSafe {state : State} {output : List UInt8} (c : Cursor input state output) : state.cellId? ordinalId ≠ some input.cursorCell := by
    simp [State.cellId?, c.locals, input.ordinalCursor]
  obtain ⟨one, opening, cursor1, keep1⟩ := cursor.advanceArgumentsKeeping (suffix := [32, 40]) formed
    (OutputWriterProof.textAt input.context.toBuffer cursor.frame " (" 2 rfl
      (by change input.context.position + (front ++ [32, 40]).length ≤ input.context.capacity; simp; omega) input.environment)
    (expressions := arguments 1) (by core_arguments) rfl
  have child1 := keep1 _ _ childLocal (childSafe cursor)
  have ordinal1 := keep1 _ _ ordinalLocal (ordinalSafe cursor)
  let context := input.context.afterOutput input.inputMemory cursor1.frame.output (by
    simp only [List.length_append, List.length_cons, List.length_nil]; omega)
  have retained := input.inputMemory.afterOutput cursor1.frame.output (by
    simp only [List.length_append, List.length_cons, List.length_nil]; omega)
  obtain ⟨printed, expressionRun, expressionFrame⟩ := writer context retained input.representation input.nameContext
    (by simp [context, Context.afterOutput]; omega) (input.environment.afterWrite cursor1.frame)
  have printedRun : RunsExpr extractedProgram one (right 2)
      (.signed .i32 (input.context.position + ((front ++ [32, 40]) ++ expression).length : Nat)) printed := by
    have position : context.position + expression.length =
        input.context.position + ((front ++ [32, 40]) ++ expression).length := by
      simp only [context, Context.afterOutput, List.length_append, List.length_cons, List.length_nil]
      omega
    rw [position] at expressionRun
    exact RunsExpr.callArguments (by core_arguments) expressionRun
  obtain ⟨two, expressionAssignment, cursor2, keep2⟩ := cursor1.advanceKeeping formed printedRun
    (by simpa [context, Context.afterOutput, Nat.add_assoc] using expressionFrame)
  have child2 := keep2 _ _ child1 (childSafe cursor1)
  have ordinal2 := keep2 _ _ ordinal1 (ordinalSafe cursor1)
  obtain ⟨three, closing, cursor3, keep3⟩ := cursor2.advanceArgumentsKeeping (suffix := [41]) formed
    (OutputWriterProof.byteAt input.context.toBuffer cursor2.frame ⟨41, by decide⟩
      (by simp only [List.length_append, List.length_cons, List.length_nil]; omega) input.environment)
    (expressions := arguments 3) (by core_arguments) rfl
  have child3 := keep3 _ _ child2 (childSafe cursor2)
  have ordinal3 := keep3 _ _ ordinal2 (ordinalSafe cursor2)
  let live := input.tree.ofReads
    (input.inputMemory.afterOutput cursor3.frame.output (by
      simp only [List.length_append, List.length_cons, List.length_nil]; omega)).memory.reads
  obtain ⟨ready, nextChild, pure⟩ := live.nextChild ordered children (cursor3.frame.afterFormed formed)
  change RunsExpr extractedProgram three (IRNavigationProof.siblingCall input.tree.value input.parent child)
    (.signed .i32 (if rest.length = 0 then -1 else input.tree.ends child)) ready at nextChild
  have next : (if rest.length = 0 then -1 else input.tree.ends child) =
      childValue rest (input.tree.ends child).toNat := by
    cases rest with
    | nil => rfl
    | cons head tail =>
      have forward : (child : Int) < input.tree.ends child := by
        cases children with | cons _ _ forward _ _ => exact forward
      simp [childValue, Int.toNat_of_nonneg (by omega : 0 ≤ input.tree.ends child)]
  rw [next] at nextChild
  have navigation : RunsExpr extractedProgram three (right 4)
      (.signed .i32 (childValue rest (input.tree.ends child).toNat)) ready := by
    simp only [IRNavigationProof.siblingCall] at nextChild
    rw [← input.representation] at nextChild
    exact RunsExpr.callArguments (by core_arguments) nextChild
  obtain ⟨four, navigationAssignment, cursor4, child4, keep4⟩ := cursor3.assignControl formed
    (control := childId) (controlCell := input.childCell) (by simp [State.cellId?, cursor3.locals, differentIds]) child3
    input.childFresh input.childCursor navigation pure
  have ordinal4 := keep4 _ _ ordinal3 (by simp [State.cellId?, cursor3.locals, Ne.symm input.controlsDifferent])
  obtain ⟨after, increment, final, ordinalAfter, keep5⟩ := cursor4.incrementControl (program := extractedProgram) formed
    (control := ordinalId) (controlCell := input.ordinalCell) (by simp [State.cellId?, cursor4.locals]) ordinal4
    input.ordinalFresh input.ordinalCursor (by have fits := input.fits; simp only [List.length_cons] at count; omega)
  have childAfter := keep5 _ _ child4 (by simp [State.cellId?, cursor4.locals, differentIds, input.controlsDifferent])
  refine ⟨after, guard, ?_, ?_, childAfter, ordinalAfter⟩
  · core_stmt
  · simpa only [chunk, List.append_assoc] using final

#print axioms iteration

/-- Total traversal of any finite payload list. The actual loop terminates,
    emits each represented child once in order, and retains its caller frame. -/
private theorem traversal (input : Input base region) (expressions : List (List UInt8))
    (cursor : Cursor input current front) (represented : ChildWriters input.tree input.scope expressions child)
    (children : input.tree.Children input.parent ordinal expressions.length child)
    (ordered : input.parent < child) (count : ordinal + expressions.length = input.count)
    (childLocal : current.local? childId = some (.signed .i32 (childValue expressions child)))
    (ordinalLocal : current.local? ordinalId = some (.signed .i32 ordinal))
    (room : input.context.position + (front ++ bytes expressions).length ≤ input.context.capacity) :
    ∃ after, RunsStmt extractedProgram current (.whileLoop loop.1 loop.2) .next after ∧
      Cursor input after (front ++ bytes expressions) := by
  core_facts 1 [input]
  induction expressions generalizing child ordinal current front with
  | nil =>
      have condition : RunsExpr extractedProgram current loop.1 (.boolean false) current := by
        have equal : ordinal = input.count := by simpa using count
        core_run
      exact ⟨current, .whileFalse condition, by simpa [bytes] using cursor⟩
  | cons expression rest recurse =>
      obtain ⟨childInput, restInput⟩ := represented
      have childNow : current.local? childId = some (.signed .i32 child) := by
        simpa [childValue] using childLocal
      have roomNow : input.context.position + (front ++ chunk expression ++ bytes rest).length ≤ input.context.capacity := by
        simpa only [bytes, List.flatMap_cons, List.append_assoc] using room
      obtain ⟨next, guard, body, advanced, nextChild, nextOrdinal⟩ :=
        iteration input cursor expression rest childInput children ordered count childNow ordinalLocal roomNow
      have tail : input.tree.Children input.parent (ordinal + 1) rest.length (input.tree.ends child).toNat := by
        cases children with | cons _ _ _ _ tail => exact tail
      have forward : input.parent < (input.tree.ends child).toNat := by
        have step : (child : Int) < input.tree.ends child := by
          cases children with | cons _ _ step _ _ => exact step
        omega
      obtain ⟨after, run, final⟩ := recurse advanced restInput tail forward
        (by simp only [List.length_cons] at count; omega) nextChild nextOrdinal
        (by simpa only [List.append_assoc] using roomNow)
      exact ⟨after, .whileStep guard body (Or.inl rfl) run,
        by simpa only [bytes, List.flatMap_cons, List.append_assoc] using final⟩

#print axioms traversal

def output (variant : ConstructorNameProof.Variant reference) (name : TypeNameProof.Named reference)
    (expressions : List (List UInt8)) : List UInt8 :=
  [40] ++ ConstructorNameProof.bytes variant ++ bytes expressions ++ [32, 58, 32] ++ TypeNameProof.bytes name ++ [41]
def call (context : Context state) (index : Nat) : Expr :=
  .call source.id ([context.views, .signed .i32 index, .signed .i32 context.position].map Expr.value)
def event (typeId variant count : Nat) : Value :=
  source_value Extracted.«ir::body_events».Types.«Event».«ExpressionEnumeration» [enumeration typeId variant count]

private theorem arityFromEvent (typeId variant count : Nat)
    (classified : IRShapeProof.Classifies (event typeId variant count)
      (IRShapeProof.shapeValue (IRShapeProof.kindValue kind) arity (IRShapeProof.ruleValue rule))) :
    arity = (count : Int) := by
  cases classified with
  | fixed listed => simp [IRShapeProof.fixedShapes, event, enumeration, IRShapeProof.shapeValue] at listed
  | payload listed => simp [IRShapeProof.payloadShapes, event, enumeration, IRShapeProof.shapeValue] at listed
  | counted listed =>
      simp [IRShapeProof.countedShapes, event, enumeration, IRShapeProof.shapeValue] at listed
      simp_all

private theorem actualMetadata (typeId variant count : Nat) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (.call metadataSource.id [.value (event typeId variant count)])
      (enumeration typeId variant count) after ∧ PureFrame state after := by
  core_call_pure metadataSource as caller
  core_pure

/-- Constructor step for arbitrary child outputs. Recursive writer obligations
    are discharged by the closed expression theorem, not by native validation. -/
theorem actualCallStep (context : Context state) (inputMemory : Protected context reference)
    (tree : Ready region { heap := reference }) (variant : ConstructorNameProof.Variant reference)
    (name : TypeNameProof.Named reference) (expressions : List (List UInt8))
    (representation : context.tree = tree.value) (inside : index < region.count)
    (parent : region.events index = event variant.typeIndex variant.ordinal expressions.length)
    (payloads : ChildWriters tree scope expressions (index + 1)) (nameContext : scope.Matches context)
    (types : context.types = variant.table.value) (names : context.names = variant.name.catalog.value)
    (typeNames : context.names = name.path.name.catalog.value) (sameType : name.index = variant.typeIndex)
    (room : context.position + (output variant name expressions).length ≤ context.capacity)
    (environment : WriterEnvironment state) :
    ∃ after, RunsExpr extractedProgram state (call context index)
      (.signed .i32 (context.position + (output variant name expressions).length : Nat)) after ∧
      WriterFrame state after (context.address + context.position) (output variant name expressions) := by
  have formed := environment.formed
  have arity := region.classified index inside
  rw [parent] at arity
  have arity := arityFromEvent _ _ _ arity
  have countFits : expressions.length < 2 ^ 31 := by
    have bound := (tree.suffix index (Nat.zero_le _) inside).2.1
    rw [arity] at bound
    have fits := region.fits
    omega
  have space : context.position + (ConstructorNameProof.bytes variant).length + (bytes expressions).length +
      (TypeNameProof.bytes name).length + 5 ≤ context.capacity := by
    simp only [output, List.length_append, List.length_cons, List.length_nil] at room
    omega
  core_call_framed Lanius.Extraction.RunsExpr.callWriter source as callee
  let viewed := callee.bindLocal (source.bindingId 0) context.value
  let events := viewed.bindLocal (source.bindingId 1) (.rawSlice eventType region.eventsAddress region.eventsLength)
  have read := inputMemory.memory.reads.rawSlice (tree.eventReads index inside)
  rw [parent] at read
  have metadata := actualMetadata variant.typeIndex variant.ordinal expressions.length
    (state := events) (by core_formed)
  apply actualViewEvents (context.reheap (after := callee) rfl) tree representation (by core_local) (by core_formed)
  apply RunsStmt.letReadWriter
  · apply RunsExpr.callPureArguments
    · core_arguments
    · exact metadata
  · intro metadataReady pure
    let base := metadataReady.bindLocal (source.bindingId 2) (enumeration variant.typeIndex variant.ordinal expressions.length)
    let start := context.reheap (after := base) pure.heap
    have input := inputMemory.reheap (after := base) pure.heap
    have env := environment.reheap (after := base) pure.heap pure.views (by core_formed)
    have baseView : base.local? (source.bindingId 0) = some context.value := by core_local
    have baseViews : base.local? (source.argumentId 0) = some context.views := by core_local
    have baseIndex : base.local? (source.argumentId 1) = some (.signed .i32 index) := by core_local
    have baseConstructor : base.local? (source.bindingId 2) =
        some (enumeration variant.typeIndex variant.ordinal expressions.length) := by core_local
    obtain ⟨first, openingCall, openingFrame⟩ := OutputWriterProof.byte start.toBuffer ⟨40, by decide⟩
      (by change context.position + 1 ≤ context.capacity; omega) env
    let bound := first.bindLocal cursorId (.signed .i32 (context.position + 1 : Nat))
    have initial : WriterCursor base bound cursorId first.nextCell
        (context.address + context.position) context.position [40] :=
      WriterCursor.start openingFrame env.formed openingCall.choose_spec.2 _
    let ctx1 := start.afterOutput input initial.frame.output (by change context.position + 1 ≤ context.capacity; omega)
    have named := ConstructorNameProof.actualBody ctx1
      (input.afterOutput initial.frame.output (by change context.position + 1 ≤ context.capacity; omega)) variant types names
      (by change (context.position + 1) + (ConstructorNameProof.bytes variant).length ≤ context.capacity; omega)
      (env.afterWrite initial.frame)
    obtain ⟨two, naming, namedCursor⟩ := initial.advanceArguments env.formed named
      (expressions := arguments 0) (by core_arguments)
      (by simp [ctx1, Context.afterOutput, start, Context.reheap]; omega)
    let treeNow := tree.ofReads
      (input.afterOutput namedCursor.frame.output (by
        change context.position + ([40] ++ ConstructorNameProof.bytes variant).length ≤ context.capacity; simp; omega)).memory.reads
    obtain ⟨childReady, childCall, childFrame⟩ := treeNow.firstChild inside (namedCursor.frame.afterFormed env.formed)
    have firstIndex : treeNow.firstIndex index = childValue expressions (index + 1) := by
      cases expressions <;> simp [Ready.firstIndex, arity, childValue, Int.natCast_add] <;> omega
    rw [firstIndex] at childCall
    let childBound := childReady.bindLocal childId (.signed .i32 (childValue expressions (index + 1)))
    let ready := childBound.bindLocal ordinalId (.signed .i32 0)
    have cursorChild := (namedCursor.afterPure childFrame).bindLocal env.formed childId
      (.signed .i32 (childValue expressions (index + 1))) (by decide)
    have cursor := cursorChild.bindLocal env.formed ordinalId (.signed .i32 0) (by decide)
    have childFresh := childFrame.cells.choose_spec.2.1
    have firstFresh := openingFrame.cells.choose_spec.2.1
    have cursorBound : first.nextCell < two.nextCell :=
      (namedCursor.frame.afterFormed env.formed).localCellBound namedCursor.slot namedCursor.value
    have childGreater : first.nextCell < childReady.nextCell := Nat.lt_of_lt_of_le cursorBound childFresh
    let traversalInput : Input base region := {
      reference, context := start, inputMemory := input, tree, representation, scope, nameContext,
      parent := index, count := expressions.length, typeId := variant.typeIndex, variant := variant.ordinal,
      fits := countFits, cursorCell := first.nextCell, childCell := childReady.nextCell,
      ordinalCell := childReady.nextCell + 1,
      childFresh := Nat.le_trans firstFresh (Nat.le_of_lt childGreater),
      ordinalFresh := Nat.le_trans (Nat.le_trans firstFresh (Nat.le_of_lt childGreater)) (Nat.le_succ _),
      childCursor := Nat.ne_of_gt childGreater,
      ordinalCursor := Nat.ne_of_gt (Nat.lt_trans childGreater (Nat.lt_succ_self _)),
      controlsDifferent := Nat.ne_of_lt (Nat.lt_succ_self _),
      view := baseView, constructor := baseConstructor, views := baseViews, index := baseIndex, environment := env }
    have current : Cursor traversalInput ready ([40] ++ ConstructorNameProof.bytes variant) := cursor
    have readyFormed := cursor.frame.afterFormed env.formed
    have childFound : ready.local? childId = some (.signed .i32 (childValue expressions (index + 1))) := by core_local
    have ordinalFound : ready.local? ordinalId = some (.signed .i32 0) := by core_local
    obtain ⟨loopAfter, loopRun, loopCursor⟩ := traversal (child := index + 1) (ordinal := 0)
      traversalInput expressions current payloads
      (by simpa only [traversalInput, Ready.Children, arity, Int.toNat_natCast] using tree.childrenStart inside)
      (Nat.lt_succ_self index) (by change 0 + expressions.length = expressions.length; exact Nat.zero_add _) childFound ordinalFound
      (by change context.position + (([40] ++ ConstructorNameProof.bytes variant) ++ bytes expressions).length ≤ context.capacity; simp; omega)
    obtain ⟨three, separator, separatorCursor⟩ := loopCursor.advanceArguments (suffix := [32, 58, 32]) env.formed
      (OutputWriterProof.textAt start.toBuffer loopCursor.frame " : " 3 rfl
        (by change context.position + ((([40] ++ ConstructorNameProof.bytes variant) ++ bytes expressions) ++ [32, 58, 32]).length ≤ context.capacity; simp; omega) env)
      (expressions := arguments 6) (by core_arguments) rfl
    have separatorAtSource : RunsExpr extractedProgram loopAfter (source.effectExpression 6) .unit three := separator
    let ctx3 := start.afterOutput input separatorCursor.frame.output (by
      change context.position + ((([40] ++ ConstructorNameProof.bytes variant) ++ bytes expressions) ++ [32, 58, 32]).length ≤ context.capacity; simp; omega)
    have typename := TypeNameProof.actualBody ctx3
      (input.afterOutput separatorCursor.frame.output (by
        change context.position + ((([40] ++ ConstructorNameProof.bytes variant) ++ bytes expressions) ++ [32, 58, 32]).length ≤ context.capacity; simp; omega)) name typeNames
      (by simp [ctx3, Context.afterOutput, start, Context.reheap]; omega) (env.afterWrite separatorCursor.frame)
    rw [sameType] at typename
    obtain ⟨four, typed, typedCursor⟩ := separatorCursor.advanceArguments
      (program := extractedProgram) (suffix := TypeNameProof.bytes name)
      (next := (ctx3.position + (TypeNameProof.bytes name).length : Nat)) env.formed
      (by simpa only [ctx3, Context.afterOutput, start, Context.reheap, traversalInput, Nat.add_assoc] using typename)
      (expressions := arguments 7) (by core_arguments)
      (by simp only [ctx3, Context.afterOutput, start, Context.reheap, traversalInput, List.length_append, Nat.add_assoc])
    have typedAtSource : RunsExpr extractedProgram three (source.effectExpression 7) .unit four := typed
    obtain ⟨last, closing, final⟩ := typedCursor.finishArguments (suffix := [41])
      (OutputWriterProof.byteAt start.toBuffer typedCursor.frame ⟨41, by decide⟩
        (by simp [start, Context.reheap]; omega) env)
      (expressions := [.field (.local (source.bindingId 0)) 6, .field (.local (source.bindingId 0)) 7,
        .local cursorId, .value (.signed .i32 41)]) (by core_arguments) rfl
    have closingAtSource : RunsStmt extractedProgram four ending
        (.returned (some (.signed .i32 (context.position + (output variant name expressions).length : Nat)))) last := by
      change RunsStmt extractedProgram four
        (.returnValue (some (.call Extracted.«verified::lean_output».Functions.byte.core.id
          [.field (.local (source.bindingId 0)) 6, .field (.local (source.bindingId 0)) 7,
            .local cursorId, .value (.signed .i32 41)]))) _ last
      simpa [output, List.append_assoc, traversalInput, start, Context.reheap,
        Nat.add_assoc, Nat.add_left_comm, Nat.add_comm, Int.add_assoc, Int.add_left_comm, Int.add_comm] using closing
    have openRun : RunsExpr extractedProgram base
        (match body with | .letLocal _ _ initial _ => initial | _ => .value .unit)
        (.signed .i32 (context.position + 1 : Nat)) first := RunsExpr.callArguments (by core_arguments) openingCall
    have childRun : RunsExpr extractedProgram two
        (.call Extracted.«ir::body_tree».Functions.«first_child».core.id
          [.field (.local (source.bindingId 0)) 0, .local (source.argumentId 1)])
        (.signed .i32 (childValue expressions (index + 1))) childReady := by
      change RunsExpr extractedProgram two
        (.call Extracted.«ir::body_tree».Functions.«first_child».core.id
          [.value tree.value, .value (.signed .i32 index)]) _ childReady at childCall
      rw [← representation] at childCall
      exact RunsExpr.callArguments (by core_arguments) childCall
    refine ⟨restoreLocals first (restoreLocals childReady (restoreLocals childBound last)), ?_, ?_⟩
    · core_stmt
    · have framed := ((final.restoreLocals childBound).restoreLocals childReady).restoreLocals first
      dsimp [base, source, Extracted.«verified::lean_typed_body».Functions.«surface_constructor_output»,
        Function.bindingId, Stmt.bindingIds] at framed
      simp only [List.getElem?_cons_zero, Option.getD_some] at framed
      simpa [output, List.append_assoc, traversalInput, start, Context.reheap] using framed

#print axioms actualCallStep

private def route (typeId variant count : Nat) : SurfaceFallbackProof.Route (event typeId variant count) := {
  target := source.id, literalArguments := [],
  bindings := [(SurfaceFallbackProof.binding 6, enumeration typeId variant count)],
  nonAtom := by rfl, binary := by rfl, intrinsic := by rfl, selected := by rfl,
  noShadow := by
    intro binding member i bound
    simp only [List.mem_singleton] at member
    subst binding
    change SurfaceFallbackProof.binding 6 ≠ expression.argumentId i
    have cases : i = 0 ∨ i = 1 ∨ i = 2 := by omega
    rcases cases with rfl | rfl | rfl <;> decide }

/-- Reuse the constructor step through the actual expression dispatcher.
    The final induction supplies every recursive child writer. -/
theorem actualExpressionStep (context : Context state) (inputMemory : Protected context reference)
    (tree : Ready region { heap := reference }) (variant : ConstructorNameProof.Variant reference)
    (name : TypeNameProof.Named reference) (expressions : List (List UInt8))
    (representation : context.tree = tree.value) (inside : index < region.count)
    (parent : region.events index = event variant.typeIndex variant.ordinal expressions.length)
    (payloads : ChildWriters tree scope expressions (index + 1)) (nameContext : scope.Matches context)
    (types : context.types = variant.table.value) (names : context.names = variant.name.catalog.value)
    (typeNames : context.names = name.path.name.catalog.value) (sameType : name.index = variant.typeIndex)
    (room : context.position + (output variant name expressions).length ≤ context.capacity)
    (environment : WriterEnvironment state) :
    ∃ after, RunsExpr extractedProgram state (context.expressionCall index)
      (.signed .i32 (context.position + (output variant name expressions).length : Nat)) after ∧
      WriterFrame state after (context.address + context.position) (output variant name expressions) := by
  have helper : Writer (SurfaceFallbackProof.entry source.id []) reference tree.value index
      (output variant name expressions) (.fixed context.metadata) := by
    intro current c input represented metadata space env
    have typesNow := (congrArg Metadata.types metadata).trans types
    have namesNow := (congrArg Metadata.names metadata).trans names
    have typeNamesNow := (congrArg Metadata.names metadata).trans typeNames
    have scopeNow : scope.Matches c := by cases scope <;> simp_all [Scope.Matches]
    exact actualCallStep c input tree variant name expressions represented inside parent payloads scopeNow
      typesNow namesNow typeNamesNow sameType space env
  exact SurfaceFallbackProof.actualDispatch (route variant.typeIndex variant.ordinal expressions.length)
    context inputMemory tree representation inside parent helper rfl room environment

#print axioms actualExpressionStep

end ConstructorPayloadProof
