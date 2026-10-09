import verified_compiler.tests.direct_surface_dispatch
import verified_compiler.tests.direct_surface_name

namespace SurfaceLocalProof

open Lanius Lanius.Core Lanius.Semantics Lanius.Extraction Lanius.Memory
open SurfaceBooleanProof SurfaceDispatchProof IRBuilderNavigationProof SourceIdentifierProof

private def localId := Extracted.«verified::lean_body_shape».Functions.«expression_local_id».core
private def localReference := Extracted.«ir::body_events».Functions.«local_reference».core
def localValue (token : Int) : Value :=
  source_value Extracted.«ir::body_events».Types.«LocalReference».mk [.signed .i32 token]
def localEvent (token : Int) : Value :=
  source_value Extracted.«ir::body_events».Types.«Event».«ExpressionLocal» [localValue token]

/-- Read the existing local token ID through both actual payload helpers. -/
theorem actualId (token : Int) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (.call localId.id [.value (localEvent token)])
      (.signed .i32 token) after ∧ PureFrame state after := by
  core_call_pure localId as callee
  have reference : ∃ after, RunsExpr extractedProgram callee
      (.call localReference.id [.value (localEvent token)]) (localValue token) after ∧ PureFrame callee after := by
    core_call_pure localReference as inner
    core_pure
  core_pure

private def classifierArms : List (Pattern × Expr) := match classifier.body with
  | some (.sequence _ (.letLocal _ _ _ (.returnValue (some (.matchValue _ arms))))) => arms
  | _ => []
private def classifierBinding : VarId := match classifierArms[6]? with
  | some (Pattern.enumVariant _ _ [Pattern.bind id], _) => id | _ => 0

theorem actualClassifier (tree : Ready region state) (token : Nat)
    (inside : index < region.count) (event : region.events index = localEvent token)
    (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state
      (.call classifier.id [.value tree.value, .value (.signed .i32 index)])
      (.boolean true) after ∧ PureFrame state after := by
  core_call_pure classifier as callee
  let events := callee.bindLocal (classifier.bindingId 0)
    (.rawSlice eventType region.eventsAddress region.eventsLength)
  let branch := events.bindLocal classifierBinding (localValue token)
  have read := (tree.reheap (after := callee) rfl).eventReads index inside
  rw [event] at read
  have identifier := actualId token (state := branch) (by core_formed)
  have accepted : ∃ after, RunsExpr extractedProgram branch
      ((classifierArms[6]?).getD (.wildcard, .value .unit)).2 (.boolean true) after ∧ PureFrame branch after := by
    apply RunsExpr.binaryPure
    · apply RunsExpr.callPureArguments
      · core_arguments
      · exact identifier
    · intro current frame
      exact ⟨current, .ofStable .value rfl, PureFrame.refl frame.afterFormed⟩
    · simp
    · core_scalar
  apply RunsStmt.guardPureFalse
  · core_run
  · apply RunsStmt.letPure
    · core_run
    · core_formed
    · apply RunsStmt.returnPure
      apply RunsExpr.matchPure (value := localEvent token)
        (bindings := [(classifierBinding, localValue token)])
        (body := ((classifierArms[6]?).getD (.wildcard, .value .unit)).2)
      · core_run
      · rfl
      · core_formed
      · exact accepted

theorem actualAtom (context : Context state) (input : Protected context reference)
    (tree : Ready region state) (name : Name reference)
    (representation : context.tree = tree.value) (inside : index < region.count)
    (event : region.events index = localEvent name.tokenIndex)
    (catalog : context.names = name.catalog.value) (unit : context.unit = name.unitIndex)
    (room : context.position + (EscapedIdentifierProof.bytes name).length ≤ context.capacity)
    (environment : WriterEnvironment state) :
    ∃ after, RunsExpr extractedProgram state (context.atomCall index)
      (.signed .i32 (context.position + (EscapedIdentifierProof.bytes name).length : Nat)) after ∧
      WriterFrame state after (context.address + context.position) (EscapedIdentifierProof.bytes name) := by
  have formed := environment.formed
  apply actualSelectedAtom context tree (localEvent name.tokenIndex) representation inside event
    (bindings := [(armBinding 6, localValue name.tokenIndex)]) (by rfl) formed
  let branch := (context.atomScope tree index).bindLocals [(armBinding 6, localValue name.tokenIndex)]
  have read := (tree.reheap (after := branch) rfl).eventReads index inside
  rw [event] at read
  obtain ⟨readState, identifier, retained⟩ := actualId name.tokenIndex (state := branch) (by core_formed)
  have position := retained.localFound
    (show branch.local? (atom.argumentId 2) = some (.signed .i32 context.position) by core_local)
  apply RunsExpr.writerFramedArguments
    (values := [context.views, .signed .i32 name.tokenIndex, .signed .i32 context.position])
  · refine ⟨readState, ?_, retained⟩
    apply RunsExprs.cons (middle := branch)
    · core_run
    · apply RunsExprs.cons (middle := readState)
      · exact RunsExpr.callArguments (by core_arguments) identifier
      · core_arguments
  · intro current frame
    let live := context.reheap (after := current) frame.heap
    have writer := SurfaceNameProof.actualName live (input.reheap frame.heap) name catalog unit room
      (environment.reheap frame.heap frame.views (by core_formed))
    exact writer

/-- Normal expression routing derives the classifier and selected atom call;
    it does not assume that a local name has already been printed. -/
theorem actualExpression (context : Context state) (input : Protected context reference)
    (tree : Ready region state) (name : Name reference)
    (representation : context.tree = tree.value) (inside : index < region.count)
    (event : region.events index = localEvent name.tokenIndex)
    (catalog : context.names = name.catalog.value) (unit : context.unit = name.unitIndex)
    (room : context.position + (EscapedIdentifierProof.bytes name).length ≤ context.capacity)
    (environment : WriterEnvironment state) :
    ∃ after, RunsExpr extractedProgram state (context.expressionCall index)
      (.signed .i32 (context.position + (EscapedIdentifierProof.bytes name).length : Nat)) after ∧
      WriterFrame state after (context.address + context.position) (EscapedIdentifierProof.bytes name) := by
  apply actualDispatch context tree index representation environment.formed
  · intro caller heap callerFormed
    exact actualClassifier (tree.reheap heap) name.tokenIndex inside event callerFormed
  · intro caller heap views callerFormed
    exact actualAtom (context.reheap heap) (input.reheap heap) (tree.reheap heap) name
      representation inside event catalog unit room (environment.reheap heap views callerFormed)

#print axioms actualId
#print axioms actualClassifier
#print axioms actualAtom
#print axioms actualExpression

end SurfaceLocalProof
