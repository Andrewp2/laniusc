import verified_compiler.tests.direct_surface_binary

namespace SurfaceBinaryDispatchProof

open Lanius Lanius.Core Lanius.Semantics Lanius.Extraction Lanius.Memory
open SurfaceBooleanProof SurfaceDispatchProof SurfaceOperationsProof SurfaceBinaryProof IRBuilderNavigationProof

/-- Derive the non-atom and binary-name decisions at the normal entry point.
    Final structural induction supplies the binary helper's child contracts. -/
theorem actualBinaryDispatch (operation : Binary) (context : Context state) (input : Protected context reference)
    (tree : Ready region { state with heap := reference })
    (representation : context.tree = tree.value) (inside : index < region.count)
    (parent : region.events index = operation.event)
    {scope : Scope} (binaryWriter : Writer Context.binaryCall reference tree.value index output scope)
    (nameContext : scope.Matches context)
    (room : context.position + output.length ≤ context.capacity)
    (environment : WriterEnvironment state) :
    ∃ after, RunsExpr extractedProgram state (context.expressionCall index)
      (.signed .i32 (context.position + output.length : Nat)) after ∧
      WriterFrame state after (context.address + context.position) output := by
  have formed := environment.formed
  have lengths := operation.lengthBounds
  core_call_framed Lanius.Extraction.RunsExpr.callWriter expression as callee
  let viewed := callee.bindLocal (expression.bindingId 0) context.value
  let current := viewed.bindLocal (expression.bindingId 1)
    (.rawSlice eventType region.eventsAddress region.eventsLength)
  have readEvent : readRawSliceIndex extractedProgram state eventType
      region.eventsAddress region.eventsLength index = .ok operation.event := by
    have read := input.memory.reads.rawSlice (tree.eventReads index inside)
    rw [parent] at read
    exact read
  apply actualViewEvents (context.reheap (after := callee) rfl) tree representation (by core_local) (by core_formed)
  apply RunsStmt.guardWriterFalse
  · have classify := actualBinaryClassifier operation tree inside (state := current) readEvent (by core_formed)
    rw [← representation] at classify
    core_pure_expr
  · intro nonAtom atomFrame
    have atomHeap : nonAtom.heap = state.heap := atomFrame.heap
    have atomRead : readRawSliceIndex extractedProgram nonAtom eventType
        region.eventsAddress region.eventsLength index = .ok operation.event := by
      simpa only [readRawSliceIndex, atomHeap] using readEvent
    apply RunsStmt.letReadWriter (value := operation.name)
    · have lookup := actualSymbol operation (state := nonAtom) (by core_formed)
      apply RunsExpr.callPureArguments (values := [operation.event])
      · core_arguments
      · exact lookup
    · intro binaryReady binaryFrame
      let final := binaryReady.bindLocal (expression.bindingId 2) operation.name
      have heap : final.heap = state.heap := binaryFrame.heap.trans atomFrame.heap
      have views : final.i32ArrayViews = state.i32ArrayViews := binaryFrame.views.trans atomFrame.views
      have writer := binaryWriter (context.reheap heap) (input.reheap heap) representation nameContext room
        (environment.reheap heap views (by core_formed))
      apply RunsStmt.guardPureWriter true
      · simp
      · core_run
      · core_writer

#print axioms actualBinaryDispatch

end SurfaceBinaryDispatchProof
