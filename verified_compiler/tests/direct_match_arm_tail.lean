import verified_compiler.tests.direct_match_arm_layout
import verified_compiler.tests.direct_surface_expression_tree

namespace MatchArmTailProof

open Lanius Lanius.Core Lanius.Semantics Lanius.Extraction Lanius.Memory
open SurfaceBooleanProof SurfaceDispatchProof SurfaceExpressionTreeProof IRBuilderNavigationProof MatchBindingsProof

private def source := MatchBindingsProof.source
private def parentId := source.bindingId 4
private def ordinalId := source.bindingId 5
private def childId := source.bindingId 7
attribute [local simp] MatchBindingsProof.sourceBindings Function.bindingId source
attribute [local simp] Input.scope parentId ordinalId childId
private theorem arrowLength : (World.utf8Bytes " => ").length = 4 := rfl
attribute [local simp] arrowLength
private def right (index : Nat) : Expr := match source.effectExpression index with
  | .assign _ _ expression => expression | _ => .value .unit
private def arguments (index : Nat) : List Expr := match right index with
  | .call _ expressions => expressions | _ => []

/-- The actual continuation after the binding loop, including the failure
    guard and both outer-loop control updates. -/
def bindingBody : Stmt := match (source.whileLoop 0).2 with
  | .letLocal _ _ _ (.sequence _ (.sequence _
      (.letLocal _ _ _ (.letLocal _ _ _ rest)))) => rest
  | _ => .skip
def tail : Stmt := match bindingBody with
  | .sequence _ rest => rest
  | _ => .skip
private theorem connected : bindingBody = .sequence bindingLoop tail := rfl
def output (bodyBytes : List UInt8) : List UInt8 := World.utf8Bytes " => " ++ bodyBytes ++ [10]
def nextArm (input : Input base region) (remaining : Nat) : Int :=
  if remaining = 0 then -1 else input.tree.ends input.parent

/-- One continuation step. The final expression induction supplies the child
    writer; navigation and counters follow from the builder's existing chain. -/
theorem actualTailStep {matchIndex remaining : Nat} (input : Input base region)
    (initial : LoopState input current front body input.count)
    (bodyBytes : List UInt8) {scope : Scope}
    (writer : Writer Context.expressionCall input.reference input.tree.value body bodyBytes scope)
    (nameContext : scope.Matches input.context)
    (index : base.local? (source.argumentId 1) = some (.signed .i32 matchIndex))
    (children : input.tree.Children matchIndex (input.armOrdinal + 1) (remaining + 1) input.parent)
    (ordered : matchIndex < input.parent) (fits : input.armOrdinal + 1 < 2 ^ 31)
    (room : input.context.position + (front ++ output bodyBytes).length ≤ input.context.capacity) :
    ∃ after, RunsStmt extractedProgram current tail .next after ∧
      Cursor input after (front ++ output bodyBytes) ∧
      after.local? parentId = some (.signed .i32 (nextArm input remaining)) ∧
      after.local? ordinalId = some (.signed .i32 (input.armOrdinal + 1 : Nat)) := by
  core_facts 1 [input, initial]
  let cursor := initial.cursor
  obtain ⟨cursorParent, parentOrdinal, ordinalArm, armChild, childCounter⟩ := input.ordered
  have cursorOrdinal := Nat.lt_trans cursorParent parentOrdinal
  have cursorChild := Nat.lt_trans cursorOrdinal (Nat.lt_trans ordinalArm armChild)
  have formed := input.environment.formed
  have lengths : input.context.position + front.length + bodyBytes.length + 5 ≤ input.context.capacity := by
    simp only [output, List.length_append, List.length_cons, List.length_nil, arrowLength] at room
    omega
  obtain ⟨one, arrow, cursor1, keep1⟩ := cursor.advanceArgumentsKeeping formed
    (OutputWriterProof.textAt input.context.toBuffer cursor.frame " => " 4 rfl
      (by change input.context.position + (front ++ World.utf8Bytes " => ").length ≤ input.context.capacity
          simp; omega) input.environment)
    (expressions := arguments 14) (by core_arguments) rfl
  core_facts 1 [cursor, cursor1]
  let context := input.context.afterOutput input.inputMemory cursor1.frame.output (by simp; omega)
  let retained := input.inputMemory.afterOutput cursor1.frame.output (by simp; omega)
  obtain ⟨printed, bodyCall, bodyFrame⟩ := writer
    context retained input.representation nameContext (by simp [context, Context.afterOutput]; omega)
    (input.environment.afterWrite cursor1.frame)
  have position : context.position + bodyBytes.length =
      input.context.position + ((front ++ World.utf8Bytes " => ") ++ bodyBytes).length := by
    simp [context, Context.afterOutput, Nat.add_assoc]
  rw [position] at bodyCall
  have bodyRun : RunsExpr extractedProgram one (right 15)
      (.signed .i32 (input.context.position + ((front ++ World.utf8Bytes " => ") ++ bodyBytes).length : Nat))
      printed := RunsExpr.callArguments (by core_arguments) bodyCall
  obtain ⟨two, bodyAssignment, cursor2, keep2⟩ := cursor1.advanceKeeping formed bodyRun
    (by simpa [context, Context.afterOutput, Nat.add_assoc] using bodyFrame)
  core_facts 1 [cursor2]
  obtain ⟨three, newline, cursor3, keep3⟩ := cursor2.advanceArgumentsKeeping (suffix := [10]) formed
    (OutputWriterProof.byteAt input.context.toBuffer cursor2.frame ⟨10, by decide⟩
      (by simp; omega) input.environment)
    (expressions := arguments 16) (by core_arguments) rfl
  core_facts 1 [cursor3]
  let tree := input.tree.ofReads (input.inputMemory.afterOutput cursor3.frame.output (by simp; omega)).memory.reads
  obtain ⟨ready, navigation, pure⟩ := tree.nextChild ordered children (cursor3.frame.afterFormed formed)
  have next : RunsExpr extractedProgram three (right 17) (.signed .i32 (nextArm input remaining)) ready := by
    change RunsExpr extractedProgram three
      (IRNavigationProof.siblingCall input.tree.value matchIndex input.parent)
      (.signed .i32 (nextArm input remaining)) ready at navigation
    simp only [IRNavigationProof.siblingCall] at navigation
    rw [← input.representation] at navigation
    exact RunsExpr.callArguments (by core_arguments) navigation
  obtain ⟨four, navigationAssignment, cursor4, parent4, keep4⟩ := cursor3.assignControl
    (control := parentId) (controlCell := input.parentCell) (previous := (input.parent : Int)) formed
    (by simp [State.cellId?, cursor3.locals, Input.scope]) (by core_local)
    (Nat.le_trans cursor.fresh (Nat.le_of_lt cursorParent)) (Nat.ne_of_gt cursorParent) next pure
  core_facts 1 [cursor4]
  obtain ⟨after, increment, final, ordinalAfter, keep5⟩ := cursor4.incrementControl
    (program := extractedProgram) (control := ordinalId) (controlCell := input.ordinalCell)
    (index := input.armOrdinal) formed (by simp [State.cellId?, cursor4.locals, Input.scope]) (by core_local)
    (Nat.le_trans cursor.fresh (Nat.le_of_lt cursorOrdinal)) (Nat.ne_of_gt cursorOrdinal) fits
  have notBad : RunsExpr extractedProgram three
      (.binary .less (.local (source.bindingId 3)) (.value (.signed .i32 0))) (.boolean false) three := by core_run
  exact ⟨after, by core_stmt, by simpa only [output, List.append_assoc] using final,
    by core_local, ordinalAfter⟩

#print axioms actualTailStep

/-- Compose bindings with the continuation step. The enclosing expression
    induction discharges the body-writer obligation. -/
theorem actualBindingsAndTailStep {matchIndex remaining : Nat} (input : Input base region)
    (names : List (SourceIdentifierProof.Name input.reference))
    (initial : LoopState input current front (input.parent + 1) 0)
    (inside : input.parent < region.count)
    (event : region.events input.parent = IRShapeProof.armEvent input.variant input.count)
    (count : names.length = input.count)
    (bindings : MatchBindingsProof.Represents input.tree input.context.names input.context.unit names (input.parent + 1))
    (bodyBytes : List UInt8) {scope : Scope}
    (writer : Writer Context.expressionCall input.reference input.tree.value
      (bodyIndex input.tree names (input.parent + 1)) bodyBytes scope)
    (nameContext : scope.Matches input.context)
    (index : base.local? (source.argumentId 1) = some (.signed .i32 matchIndex))
    (children : input.tree.Children matchIndex (input.armOrdinal + 1) (remaining + 1) input.parent)
    (ordered : matchIndex < input.parent) (fits : input.armOrdinal + 1 < 2 ^ 31)
    (room : input.context.position + (front ++ bytes names ++ output bodyBytes).length ≤ input.context.capacity) :
    ∃ after, RunsStmt extractedProgram current bindingBody .next after ∧
      Cursor input after (front ++ bytes names ++ output bodyBytes) ∧
      after.local? parentId = some (.signed .i32 (nextArm input remaining)) ∧
      after.local? ordinalId = some (.signed .i32 (input.armOrdinal + 1 : Nat)) := by
  obtain ⟨bound, bindingRun, ready, _, _⟩ := MatchArmLayoutProof.actualArmBindings
    input names initial inside event count bindings (by simp only [List.length_append] at room ⊢; omega)
  obtain ⟨after, tailRun, final⟩ := actualTailStep input ready bodyBytes writer nameContext index children ordered fits room
  exact ⟨after, connected ▸ RunsStmt.sequenceNext bindingRun tailRun, final⟩

#print axioms actualBindingsAndTailStep

end MatchArmTailProof
