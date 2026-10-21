import verified_compiler.tests.direct_match_arm_tail
import verified_compiler.tests.direct_constructor_name
import Lanius.Semantics.LocalScope

namespace MatchArmProof

open Lanius Lanius.Core Lanius.Semantics Lanius.Extraction Lanius.Memory
open SurfaceBooleanProof SurfaceDispatchProof SurfaceExpressionTreeProof IRBuilderNavigationProof
open SourceIdentifierProof

private def source := MatchBindingsProof.source
private def cursorId := source.bindingId 3
private def parentId := source.bindingId 4
private def ordinalId := source.bindingId 5
private def armId := source.bindingId 6
private def childId := source.bindingId 7
private def counterId := source.bindingId 8
attribute [local simp] source cursorId parentId ordinalId armId childId counterId
attribute [local simp] MatchBindingsProof.sourceBindings Function.bindingId
def armBody : Stmt := (source.whileLoop 0).2
private def initializer : Expr := match armBody with
  | .letLocal _ _ expression _ => expression | _ => .value .unit
private def patternStatement : Stmt := match armBody with
  | .letLocal _ _ _ (.sequence _ (.sequence branch _)) => branch | _ => .skip
private def patternGuard : Expr := match patternStatement with
  | .ifThenElse guard _ _ => guard | _ => .value (.boolean false)
private def childInitializer : Expr := match armBody with
  | .letLocal _ _ _ (.sequence _ (.sequence _ (.letLocal _ _ expression _))) => expression
  | _ => .value .unit
private def right (index : Nat) : Expr := match source.effectExpression index with
  | .assign _ _ expression => expression | _ => .value .unit
private def arguments (index : Nat) : List Expr := match right index with
  | .call _ expressions => expressions | _ => []

/-- Native input and the three controls already owned by the outer match loop.
    Per-arm cells are deliberately absent: the execution must allocate them. -/
structure Input (base : State) (region : IRBuilderCallProof.Region original) where
  reference : Heap
  context : Context base
  inputMemory : Protected context reference
  tree : Ready region { heap := reference }
  representation : context.tree = tree.value
  matchIndex : Nat
  result : IRTypeRefProof.Reference
  typeId : Nat
  armCount : Nat
  cursorCell : CellId
  parentCell : CellId
  ordinalCell : CellId
  ordered : cursorCell < parentCell ∧ parentCell < ordinalCell
  view : base.local? (source.bindingId 0) = some context.value
  events : base.local? (source.bindingId 1) = some (.rawSlice eventType region.eventsAddress region.eventsLength)
  header : base.local? (source.bindingId 2) = some (IRShapeProof.matchHeaderValue result typeId armCount)
  views : base.local? (source.argumentId 0) = some context.views
  index : base.local? (source.argumentId 1) = some (.signed .i32 matchIndex)
  environment : WriterEnvironment base

def Input.scope (input : Input base region) : List (VarId × CellId) :=
  [(ordinalId, input.ordinalCell), (parentId, input.parentCell)]
attribute [local simp] Input.scope
abbrev Cursor (input : Input base region) (current : State) (front : List UInt8)
    (temporary : List (VarId × CellId) := []) : Prop :=
  WriterCursor base current cursorId input.cursorCell (input.context.address + input.context.position)
    input.context.position front (scope := temporary ++ input.scope)
structure LoopState (input : Input base region) (current : State) (front : List UInt8)
    (arm : Int) (ordinal : Nat) : Prop where
  cursor : Cursor input current front
  parent : current.local? parentId = some (.signed .i32 arm)
  ordinal : current.local? ordinalId = some (.signed .i32 ordinal)

/-- Existing native constructor metadata, or the wildcard. Not a second IR. -/
inductive Pattern (reference : Heap) where
  | wildcard
  | named (variant : ConstructorNameProof.Variant reference)
def Pattern.ordinal : Pattern reference → Int
  | .wildcard => -1 | .named variant => variant.ordinal
def Pattern.bytes : Pattern reference → List UInt8
  | .wildcard => [95] | .named variant => ConstructorNameProof.bytes variant
def Pattern.Matches (pattern : Pattern reference) (metadata : Metadata) (typeId : Nat) : Prop :=
  match pattern with
  | .wildcard => True
  | .named variant => metadata.types = variant.table.value ∧
      metadata.names = variant.name.catalog.value ∧ variant.typeIndex = typeId
attribute [local simp] Pattern.ordinal Pattern.bytes
def bytes (pattern : Pattern reference) (names : List (Name reference)) (bodyBytes : List UInt8) : List UInt8 :=
  World.utf8Bytes "      | " ++ pattern.bytes ++ MatchBindingsProof.bytes names ++ MatchArmTailProof.output bodyBytes
private theorem prefixLength : (World.utf8Bytes "      | ").length = 8 := rfl
attribute [local simp] prefixLength

/-- Both real pattern branches reuse checked writers. The result includes the
    existing retention contract so later setup need not reconstruct controls. -/
private theorem actualPattern (input : Input base region) (pattern : Pattern input.reference)
    (naming : pattern.Matches input.context.metadata input.typeId) (cursor : Cursor input current front [(armId, armCell)])
    (arm : current.local? armId = some (IRShapeProof.armValue pattern.ordinal count))
    (room : input.context.position + (front ++ pattern.bytes).length ≤ input.context.capacity) :
    ∃ after, RunsStmt extractedProgram current patternStatement .next after ∧
      Cursor input after (front ++ pattern.bytes) [(armId, armCell)] ∧
      (∀ key value, current.local? key = some value → current.cellId? key ≠ some input.cursorCell →
        after.local? key = some value) := by
  have formed := input.environment.formed
  core_facts 1 [input, cursor]
  cases pattern with
  | wildcard =>
      obtain ⟨after, write, next, kept⟩ := cursor.advanceArgumentsKeeping (suffix := [95]) formed
        (OutputWriterProof.byteAt input.context.toBuffer cursor.frame ⟨95, by decide⟩ room input.environment)
        (expressions := arguments 8) (by core_arguments) rfl
      have guard : RunsExpr extractedProgram current patternGuard (.boolean true) current := by core_run
      exact ⟨after, by core_stmt, next, kept⟩
  | named variant =>
      obtain ⟨types, names, typeId⟩ := naming
      have header : current.local? (source.bindingId 2) =
          some (IRShapeProof.matchHeaderValue input.result variant.typeIndex input.armCount) := by
        have original : current.local? (source.bindingId 2) =
            some (IRShapeProof.matchHeaderValue input.result input.typeId input.armCount) := by core_local
        simpa only [typeId] using original
      let context := input.context.afterOutput input.inputMemory cursor.frame.output (by simp only [List.length_append] at room ⊢; omega)
      let retained := input.inputMemory.afterOutput cursor.frame.output (by simp only [List.length_append] at room ⊢; omega)
      have printed := ConstructorNameProof.actualBody context retained variant types names
        (by simpa only [context, Context.afterOutput, Pattern.bytes, List.length_append, Nat.add_assoc] using room)
        (input.environment.afterWrite cursor.frame)
      obtain ⟨after, write, next, kept⟩ := cursor.advanceArgumentsKeeping (suffix := ConstructorNameProof.bytes variant) formed
        (by simpa only [ConstructorNameProof.bodyCall, context, Context.afterOutput, Nat.add_assoc] using printed)
        (expressions := arguments 9) (by core_arguments) (by simp)
      have nonnegative : (0 : Int) ≤ variant.ordinal := by omega
      have guard : RunsExpr extractedProgram current patternGuard (.boolean false) current := by core_run
      exact ⟨after, by core_stmt, next, kept⟩

/-- One real outer-loop iteration. All local setup, naming and navigation are
    derived here; the final expression induction supplies the body writer. -/
theorem actualArmStep {armIndex armOrdinal remaining : Nat} (input : Input base region)
    (initial : LoopState input current front armIndex armOrdinal)
    (pattern : Pattern input.reference) (naming : pattern.Matches input.context.metadata input.typeId)
    (names : List (Name input.reference)) (bodyBytes : List UInt8) {scope : Scope}
    (inside : armIndex < region.count)
    (event : region.events armIndex = IRShapeProof.armEvent pattern.ordinal names.length)
    (bindings : MatchBindingsProof.Represents input.tree input.context.names input.context.unit names (armIndex + 1))
    (writer : Writer Context.expressionCall input.reference input.tree.value
      (MatchBindingsProof.bodyIndex input.tree names (armIndex + 1)) bodyBytes scope)
    (nameContext : scope.Matches input.context)
    (children : input.tree.Children input.matchIndex (armOrdinal + 1) (remaining + 1) armIndex)
    (ordered : input.matchIndex < armIndex) (countFits : names.length < 2 ^ 31)
    (ordinalFits : armOrdinal + 1 < 2 ^ 31)
    (room : input.context.position + (front ++ bytes pattern names bodyBytes).length ≤ input.context.capacity) :
    ∃ after, RunsStmt extractedProgram current armBody .next after ∧
      LoopState input after (front ++ bytes pattern names bodyBytes)
        (if remaining = 0 then -1 else input.tree.ends armIndex) (armOrdinal + 1) := by
  core_facts 1 [input, initial]
  let cursor := initial.cursor
  have formed := input.environment.formed
  have currentFormed := cursor.frame.afterFormed formed
  obtain ⟨cursorParent, parentOrdinal⟩ := input.ordered
  have cursorOrdinal := Nat.lt_trans cursorParent parentOrdinal
  have ordinalSlot : current.cellId? ordinalId = some input.ordinalCell := by
    simp [State.cellId?, cursor.locals, Input.scope]
  let live := input.inputMemory.afterOutput cursor.frame.output (by
    simp only [bytes, List.length_append] at room; omega)
  have eventRead := live.memory.reads.rawSlice (input.tree.eventReads armIndex inside)
  rw [event] at eventRead
  obtain ⟨armReady, metadata, metadataPure⟩ := MatchMetadataProof.actualArm pattern.ordinal names.length currentFormed
  have read : RunsExpr extractedProgram current initializer (IRShapeProof.armValue pattern.ordinal names.length) armReady :=
    RunsExpr.callArguments (by core_arguments) metadata
  have ordinalArm := Nat.lt_of_lt_of_le (currentFormed.localCellBound ordinalSlot initial.ordinal)
    metadataPure.cells.choose_spec.2.1
  have cursorArm := Nat.lt_trans cursorOrdinal ordinalArm
  let armBound := armReady.bindLocal armId (IRShapeProof.armValue pattern.ordinal names.length)
  let armCursor : Cursor input armBound front [(armId, armReady.nextCell)] :=
    (cursor.afterPure metadataPure).bindLocal formed armId _ (by decide)
  have armFormed := armCursor.frame.afterFormed formed
  have armLocal : armBound.local? armId = some (IRShapeProof.armValue pattern.ordinal names.length) := by core_local
  obtain ⟨prefixed, prefixRun, prefixCursor, keepPrefix⟩ := armCursor.advanceArgumentsKeeping formed
    (OutputWriterProof.textAt input.context.toBuffer armCursor.frame "      | " 8 rfl
      (by change input.context.position + (front ++ World.utf8Bytes "      | ").length ≤ input.context.capacity
          simp only [bytes, List.length_append, prefixLength] at room ⊢; omega) input.environment)
    (expressions := arguments 7) (by core_arguments) rfl
  core_facts 1 [armCursor, prefixCursor]
  obtain ⟨named, patternRun, patternCursor, keepPattern⟩ := actualPattern (count := (names.length : Int))
    input pattern naming prefixCursor
    (by core_local) (by simp only [bytes, List.length_append] at room ⊢; omega)
  core_facts 1 [patternCursor]
  have patternFormed := patternCursor.frame.afterFormed formed
  let readyTree := input.tree.ofReads (input.inputMemory.afterOutput patternCursor.frame.output
    (by simp only [bytes, List.length_append] at room ⊢; omega)).memory.reads
  obtain ⟨bodyReady, firstChild, childPure⟩ := MatchArmLayoutProof.actualFirstArmChild readyTree inside event countFits patternFormed
  have parentNamed : named.local? parentId = some (.signed .i32 armIndex) := by core_local
  have firstRun : RunsExpr extractedProgram named childInitializer (.signed .i32 (armIndex + 1 : Nat)) bodyReady := by
    change RunsExpr extractedProgram named (input.tree.firstChildCall armIndex)
      (.signed .i32 (armIndex + 1 : Nat)) bodyReady at firstChild
    simp only [Ready.firstChildCall] at firstChild
    rw [← input.representation] at firstChild
    exact RunsExpr.callArguments (by core_arguments) firstChild
  have armSlot : named.cellId? armId = some armReady.nextCell := by
    simp [State.cellId?, patternCursor.locals, Input.scope]
  have armRetained : named.local? armId = some (IRShapeProof.armValue pattern.ordinal names.length) := by core_local
  have armChild := Nat.lt_of_lt_of_le (patternFormed.localCellBound armSlot armRetained)
    childPure.cells.choose_spec.2.1
  let bodyBound := bodyReady.bindLocal childId (.signed .i32 (armIndex + 1 : Nat))
  let bodyCursor := (patternCursor.afterPure childPure).bindLocal formed childId
    (.signed .i32 (armIndex + 1 : Nat)) (by decide)
  have bodyFormed := bodyCursor.frame.afterFormed formed
  let bound := bodyBound.bindLocal counterId (.signed .i32 0)
  let bindingCursor := bodyCursor.bindLocal formed counterId (.signed .i32 0) (by decide)
  have counterCell : bodyBound.nextCell = bodyReady.nextCell + 1 := rfl
  let inner : MatchBindingsProof.Input base region := {
    reference := input.reference, context := input.context, inputMemory := input.inputMemory,
    tree := input.tree, representation := input.representation, parent := armIndex, armOrdinal := armOrdinal,
    variant := pattern.ordinal, count := names.length, fits := countFits,
    cursorCell := input.cursorCell, parentCell := input.parentCell, ordinalCell := input.ordinalCell,
    armCell := armReady.nextCell, childCell := bodyReady.nextCell, counterCell := bodyBound.nextCell,
    ordered := ⟨cursorParent, parentOrdinal, ordinalArm, armChild, by rw [counterCell]; exact Nat.lt_succ_self _⟩,
    view := input.view, events := input.events, views := input.views, environment := input.environment }
  have ready : MatchBindingsProof.LoopState inner bound
      ((front ++ World.utf8Bytes "      | ") ++ pattern.bytes) (armIndex + 1) 0 := by
    refine ⟨?_, ?_, ?_, ?_, ?_, ?_⟩
    · simpa [MatchBindingsProof.Cursor, MatchBindingsProof.Input.scope, inner,
        Input.scope, bound, bodyBound, State.bindLocal, State.bindCell, List.append_assoc] using bindingCursor
    all_goals core_local
  obtain ⟨last, continuation, final, nextParent, nextOrdinal⟩ := MatchArmTailProof.actualBindingsAndTailStep
    inner names ready inside event rfl bindings bodyBytes writer nameContext input.index children ordered ordinalFits
    (by simpa only [inner, bytes, List.append_assoc] using room)
  have restored : Cursor input (restoreLocals armReady last) (front ++ bytes pattern names bodyBytes) := by
    simpa [Cursor, MatchBindingsProof.Cursor, inner, bytes, List.append_assoc] using final.restoreScope
      (by simpa [inner, metadataPure.locals] using cursor.locals)
      (by simpa [inner, State.cellId?, metadataPure.locals] using cursor.slot)
  have run : RunsStmt extractedProgram current armBody .next
      (restoreLocals armReady (restoreLocals bodyReady (restoreLocals bodyBound last))) :=
    RunsStmt.letLocal read (RunsStmt.sequenceNext (.expression prefixRun)
      (RunsStmt.sequenceNext patternRun (RunsStmt.letLocal firstRun
        (RunsStmt.letLocal (RunsExpr.ofStable StableExpr.value rfl) continuation))))
  refine ⟨restoreLocals armReady last, run, restored, ?_, ?_⟩
  · exact restoreLocals_local?_of_same_cell (cell := input.parentCell)
      (by simp [State.cellId?, metadataPure.locals, cursor.locals, Input.scope])
      (by simp [State.cellId?, final.locals, MatchBindingsProof.Input.scope, inner]) nextParent
  · exact restoreLocals_local?_of_same_cell (cell := input.ordinalCell)
      (by simp [State.cellId?, metadataPure.locals, cursor.locals, Input.scope])
      (by simp [State.cellId?, final.locals, MatchBindingsProof.Input.scope, inner]) nextOrdinal

#print axioms actualArmStep

end MatchArmProof
