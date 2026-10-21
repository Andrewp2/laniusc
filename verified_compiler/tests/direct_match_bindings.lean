import verified_compiler.tests.direct_match_metadata
import verified_compiler.tests.direct_surface_name
import verified_compiler.tests.direct_surface_ir
import Lanius.Extraction.WriterCursor

namespace MatchBindingsProof

open Lanius Lanius.Core Lanius.Semantics Lanius.Extraction Lanius.Memory
open SurfaceBooleanProof SourceIdentifierProof IRBuilderNavigationProof MatchMetadataProof

def source := Extracted.«verified::lean_typed_body».Functions.«surface_match_output».core
private def cursorId := source.bindingId 3
private def parentId := source.bindingId 4
private def armId := source.bindingId 6
private def childId := source.bindingId 7
private def counterId := source.bindingId 8
private def referenceId := source.bindingId 9
attribute [simp] cursorId parentId armId childId counterId referenceId
theorem sourceBindings : (source.body.map Stmt.bindingIds).getD [] =
    [4255, 4265, 4284, 4309, 4370, 4531, 4547, 4651, 4671, 4687] := rfl
attribute [local simp] sourceBindings Function.bindingId
private def loop := source.whileLoop 1
def bindingLoop : Stmt := .whileLoop loop.1 loop.2
private def initializer : Expr := match loop.2 with
  | .letLocal _ _ initial _ => initial | _ => .value .unit
private def right (ordinal : Nat) : Expr := match source.effectExpression ordinal with
  | .assign _ _ expression => expression | _ => .value .unit
private def arguments (ordinal : Nat) : List Expr := match right ordinal with
  | .call _ expressions => expressions | _ => []

def chunk (name : Name reference) : List UInt8 := [32] ++ EscapedIdentifierProof.bytes name
def bytes (names : List (Name reference)) : List UInt8 := names.flatMap chunk
def bodyIndex (tree : Ready region { heap := reference }) : List (Name reference) → Nat → Nat
  | [], index => index
  | _ :: rest, index => bodyIndex tree rest (tree.ends index).toNat

/-- Native events and catalog facts, not successful reader or writer runs. -/
structure Input (base : State) (region : IRBuilderCallProof.Region original) where
  reference : Heap
  context : Context base
  inputMemory : Protected context reference
  tree : Ready region { heap := reference }
  representation : context.tree = tree.value
  parent : Nat
  armOrdinal : Nat
  variant : Int
  count : Nat
  fits : count < 2 ^ 31
  cursorCell : CellId
  parentCell : CellId
  ordinalCell : CellId
  armCell : CellId
  childCell : CellId
  counterCell : CellId
  ordered : cursorCell < parentCell ∧ parentCell < ordinalCell ∧ ordinalCell < armCell ∧
    armCell < childCell ∧ childCell < counterCell
  view : base.local? (source.bindingId 0) = some context.value
  events : base.local? (source.bindingId 1) = some (.rawSlice eventType region.eventsAddress region.eventsLength)
  views : base.local? (source.argumentId 0) = some context.views
  environment : WriterEnvironment base

def Input.scope (input : Input base region) : List (VarId × CellId) :=
  [(counterId, input.counterCell), (childId, input.childCell), (armId, input.armCell),
    (source.bindingId 5, input.ordinalCell), (parentId, input.parentCell)]
attribute [local simp] Input.scope
abbrev Cursor (input : Input base region) (current : State) (front : List UInt8)
    (temporary : List (VarId × CellId) := []) : Prop :=
  WriterCursor base current cursorId input.cursorCell (input.context.address + input.context.position)
    input.context.position front (scope := temporary ++ input.scope)
def Represents (tree : Ready region { heap := reference }) (catalog : Value) (unit : Int) :
    List (Name reference) → Nat → Prop
  | [], _ => True
  | name :: rest, index => index < region.count ∧ region.events index = bindingEvent name.tokenIndex ∧
      name.catalog.value = catalog ∧ name.unitIndex = unit ∧
      Represents tree catalog unit rest (tree.ends index).toNat

/-- The live state at the actual binding loop, with no execution premise. -/
structure LoopState (input : Input base region) (state : State) (front : List UInt8)
    (child ordinal : Nat) : Prop where
  cursor : Cursor input state front
  parent : state.local? parentId = some (.signed .i32 input.parent)
  armOrdinal : state.local? (source.bindingId 5) = some (.signed .i32 input.armOrdinal)
  arm : state.local? armId = some (IRShapeProof.armValue input.variant input.count)
  child : state.local? childId = some (.signed .i32 child)
  counter : state.local? counterId = some (.signed .i32 ordinal)

/-- One actual binding iteration, including metadata, both writes, sibling
    navigation, counter increment, and restoration of the record-local scope. -/
private theorem iteration (input : Input base region) (state : LoopState input current front child ordinal)
    (name : Name input.reference) (rest : List (Name input.reference))
    (represented : Represents input.tree input.context.names input.context.unit (name :: rest) child)
    (children : input.tree.Children input.parent ordinal (rest.length + 2) child)
    (ordered : input.parent < child) (count : ordinal + (name :: rest).length = input.count)
    (room : input.context.position + (front ++ bytes (name :: rest)).length ≤ input.context.capacity) :
    ∃ after, RunsExpr extractedProgram current loop.1 (.boolean true) current ∧
      RunsStmt extractedProgram current loop.2 .next after ∧
      LoopState input after (front ++ chunk name) (input.tree.ends child).toNat (ordinal + 1) := by
  core_facts 1 [input, state]
  let cursor := state.cursor
  obtain ⟨cellOrder1, cellOrder2, cellOrder3, cellOrder4, cellOrder5⟩ := input.ordered
  have cursorArm := Nat.lt_trans cellOrder1 (Nat.lt_trans cellOrder2 cellOrder3)
  have cursorChild := Nat.lt_trans cursorArm cellOrder4
  have cursorCounter := Nat.lt_trans cursorChild cellOrder5
  have parentChild := Nat.lt_trans cellOrder2 (Nat.lt_trans cellOrder3 cellOrder4)
  have parentCounter := Nat.lt_trans parentChild cellOrder5
  have armCounter := Nat.lt_trans cellOrder4 cellOrder5
  obtain ⟨inside, event, catalog, unit, tail⟩ := represented
  have formed := input.environment.formed
  have nonnegativeEnd : 0 ≤ input.tree.ends child := by
    cases children with | cons _ _ forward _ _ => omega
  have less : (ordinal : Int) < input.count := by simp only [List.length_cons] at count; omega
  have guard : RunsExpr extractedProgram current loop.1 (.boolean true) current := by core_run
  have lengths : input.context.position + front.length + (EscapedIdentifierProof.bytes name).length + 1 ≤
      input.context.capacity := by simp only [bytes, List.flatMap_cons, chunk, List.length_append,
        List.length_cons, List.length_nil] at room; omega
  let liveInput := input.inputMemory.afterOutput cursor.frame.output (by omega)
  have eventRead := liveInput.memory.reads.rawSlice (input.tree.eventReads child inside)
  rw [event] at eventRead
  obtain ⟨ready, metadata, pure⟩ := actualBinding name.tokenIndex (state := current) (cursor.frame.afterFormed formed)
  have readyFormed := pure.afterFormed
  have initial : RunsExpr extractedProgram current initializer (bindingValue name.tokenIndex) ready := by
    exact RunsExpr.callArguments (by core_arguments) metadata
  let bound := ready.bindLocal referenceId (bindingValue name.tokenIndex)
  let bindingCursor : Cursor input bound front [(referenceId, ready.nextCell)] :=
    (cursor.afterPure pure).bindLocal formed referenceId _ (by decide)
  have reference0 : bound.local? referenceId = some (bindingValue name.tokenIndex) := by core_local
  obtain ⟨one, spaceRun, cursor1, keep1⟩ := bindingCursor.advanceArgumentsKeeping (suffix := [32]) formed
    (OutputWriterProof.byteAt input.context.toBuffer bindingCursor.frame ⟨32, by decide⟩
      (by simp only [List.length_append, List.length_cons, List.length_nil]; omega) input.environment)
    (expressions := arguments 10) (by core_arguments) rfl
  core_facts 1 [bindingCursor, cursor1]
  have reference1 := keep1 _ _ reference0 (by
    simp [State.cellId?, bindingCursor.locals]
    have bound := cursor.frame.afterFormed formed |>.localCellBound cursor.slot cursor.value
    have frontier := pure.cells.choose_spec.2.1
    exact Nat.ne_of_gt (Nat.lt_of_lt_of_le bound frontier))
  let nextContext := input.context.afterOutput input.inputMemory cursor1.frame.output (by simp; omega)
  let nextInput := input.inputMemory.afterOutput cursor1.frame.output (by simp; omega)
  have named := SurfaceNameProof.actualName nextContext nextInput name catalog.symm unit.symm
    (by simp [nextContext, Context.afterOutput]; omega) (input.environment.afterWrite cursor1.frame)
  obtain ⟨two, nameRun, cursor2, keep2⟩ := cursor1.advanceArgumentsKeeping
    (suffix := EscapedIdentifierProof.bytes name) formed
    (by simpa only [SurfaceNameProof.nameCall, nextContext, Context.afterOutput, Nat.add_assoc] using named)
    (expressions := arguments 11) (by core_arguments) (by simp; omega)
  core_facts 1 [cursor2]
  let tree := input.tree.ofReads (input.inputMemory.afterOutput cursor2.frame.output
    (by simp only [List.length_append, List.length_cons, List.length_nil]; omega)).memory.reads
  obtain ⟨navigationState, navigation, navigationFrame⟩ := tree.nextChild ordered children
    (cursor2.frame.afterFormed formed)
  simp only [show ¬ rest.length + 1 = 0 by omega, ↓reduceIte] at navigation
  change RunsExpr extractedProgram two (IRNavigationProof.siblingCall input.tree.value input.parent child)
    (.signed .i32 (input.tree.ends child)) navigationState at navigation
  have navigationRun : RunsExpr extractedProgram two (right 12)
      (.signed .i32 (input.tree.ends child)) navigationState := by
    simp only [IRNavigationProof.siblingCall] at navigation
    rw [← input.representation] at navigation
    exact RunsExpr.callArguments (by core_arguments) navigation
  have childSlot : two.cellId? childId = some input.childCell := by simp [State.cellId?, cursor2.locals, Input.scope]
  obtain ⟨three, childRun, cursor3, child3, keep3⟩ := cursor2.assignControl (previous := (child : Int))
    formed childSlot (by core_local)
    (Nat.le_trans cursor.fresh (Nat.le_of_lt cursorChild)) (Nat.ne_of_gt cursorChild) navigationRun navigationFrame
  core_facts 1 [cursor3]
  obtain ⟨last, increment, final, counter4, keep4⟩ := cursor3.incrementControl (program := extractedProgram) (index := ordinal) formed
    (control := counterId) (controlCell := input.counterCell) (by simp [State.cellId?, cursor3.locals, Input.scope]) (by core_local)
    (Nat.le_trans cursor.fresh (Nat.le_of_lt cursorCounter)) (Nat.ne_of_gt cursorCounter)
    (by have fits := input.fits; simp only [List.length_cons] at count; omega)
  have parent4 : last.local? parentId = some (.signed .i32 input.parent) := by core_local
  have ordinal4 : last.local? (source.bindingId 5) = some (.signed .i32 input.armOrdinal) := by core_local
  have arm4 : last.local? armId = some (IRShapeProof.armValue input.variant input.count) := by core_local
  have child4 : last.local? childId = some (.signed .i32 (input.tree.ends child)) := by core_local
  refine ⟨restoreLocals ready last, guard, by core_stmt, ⟨?_, ?_, ?_, ?_, ?_, ?_⟩⟩
  · simpa only [chunk, List.append_assoc] using final.restoreScope
      (by simpa only [pure.locals] using cursor.locals) (by simpa only [State.cellId?, pure.locals] using cursor.slot)
  all_goals change (ready.cellId? _).bind last.cell? = _
  all_goals simp [State.cellId?, pure.locals, cursor.locals, Input.scope]
  · simpa [State.local?, State.cellId?, final.locals, Input.scope] using parent4
  · simpa [State.local?, State.cellId?, final.locals, Input.scope] using ordinal4
  · simpa [State.local?, State.cellId?, final.locals, Input.scope] using arm4
  · simpa only [show max (input.tree.ends child) 0 = input.tree.ends child by omega] using
      (show last.cell? input.childCell =
      some (.signed .i32 (input.tree.ends child)) from by
        simpa [State.local?, State.cellId?, final.locals, Input.scope] using child4)
  · simpa [State.local?, State.cellId?, final.locals, Input.scope] using counter4

/-- Total execution of the extracted binding loop. Builder-derived children
    leave one final node for the body printer; the loop emits exactly the binding
    names and terminates there. This is not the full match printer contract. -/
theorem actualBindings (input : Input base region) (names : List (Name input.reference))
    (initial : LoopState input current front child ordinal)
    (represented : Represents input.tree input.context.names input.context.unit names child)
    (children : input.tree.Children input.parent ordinal (names.length + 1) child)
    (ordered : input.parent < child) (count : ordinal + names.length = input.count)
    (room : input.context.position + (front ++ bytes names).length ≤ input.context.capacity) :
    ∃ after, RunsStmt extractedProgram current bindingLoop .next after ∧
      LoopState input after (front ++ bytes names) (bodyIndex input.tree names child) input.count := by
  induction names generalizing current front child ordinal with
  | nil =>
      have ordinalIs : ordinal = input.count := by simpa using count
      have armLocal := initial.arm
      have counterLocal := initial.counter
      have guard : RunsExpr extractedProgram current loop.1 (.boolean false) current := by
        subst ordinal
        core_run
      exact ⟨current, .whileFalse guard, by
        simpa only [bytes, List.flatMap_nil, List.append_nil, bodyIndex, ordinalIs] using initial⟩
  | cons name rest ih =>
      obtain ⟨middle, guard, body, next⟩ := iteration input initial name rest represented children ordered count room
      obtain ⟨inside, event, catalog, unit, representedRest⟩ := represented
      cases children with
      | cons insideChild legal forward endpoint remaining =>
        obtain ⟨after, run, final⟩ := ih next representedRest remaining (by omega)
          (by simp only [List.length_cons] at count; omega)
          (by simpa only [bytes, List.flatMap_cons, List.append_assoc] using room)
        exact ⟨after, .whileStep guard body (Or.inl rfl) run,
          by simpa only [bytes, List.flatMap_cons, List.append_assoc, bodyIndex] using final⟩

#print axioms actualBindings

end MatchBindingsProof
