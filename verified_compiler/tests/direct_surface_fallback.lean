import verified_compiler.tests.direct_surface_operations

namespace SurfaceFallbackProof

open Lanius Lanius.Core Lanius.Semantics Lanius.Extraction Lanius.Memory
open SurfaceBooleanProof SurfaceDispatchProof SurfaceOperationsProof IRBuilderNavigationProof

private def intrinsic := Extracted.«verified::lean_operations».Functions.«intrinsic_name».core
private def unknown := Extracted.«verified::lean_operations».Functions.«unknown».core
private def finalArms : Stmt → List (Pattern × Expr)
  | .returnValue (some (.matchValue _ arms)) => arms
  | .letLocal _ _ _ body => finalArms body
  | .sequence _ rest => finalArms rest
  | _ => []
private def arms (function : Function) := finalArms (function.body.getD .skip)
def binding (index : Nat) : VarId := match (arms expression)[index]? with
  | some (.enumVariant _ _ [.bind id], _) => id
  | _ => 0
def arguments : List Expr := (List.range 3).map (fun i => .local (expression.argumentId i))
def entry (target : FunctionId) (literalArguments : List Value) (context : Context state) (index : Nat) : Expr :=
  .call target (([context.views, .signed .i32 index, .signed .i32 context.position] ++ literalArguments).map Expr.value)

/-- Source-syntax decisions, not execution assumptions. These facts are
    computed for each event; the final public theorem closes its helper writer. -/
structure Route (value : Value) where
  target : FunctionId
  literalArguments : List Value
  bindings : List (VarId × Value)
  nonAtom : selectedArm value nonAtomArms = some ([], .value (.boolean false))
  binary : selectedArm value (arms binarySymbol) = some ([], .call unknown.id [])
  intrinsic : selectedArm value (arms SurfaceFallbackProof.intrinsic) = some ([], .call unknown.id [])
  selected : selectedArm value (arms expression) = some (bindings, .call target (arguments ++ literalArguments.map Expr.value))
  noShadow : ∀ binding ∈ bindings, ∀ i, i < 3 → binding.1 ≠ expression.argumentId i

private theorem binaryUnknown (route : Route value) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (.call binarySymbol.id [.value value]) emptyName after ∧ PureFrame state after := by
  core_call_pure binarySymbol as callee
  apply RunsStmt.returnPure
  apply RunsExpr.matchPure (value := value) (bindings := []) (body := .call unknown.id [])
  · core_run
  · exact route.binary
  · core_formed
  · exact actualUnknown (by core_formed)

private theorem intrinsicUnknown (route : Route value) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (.call intrinsic.id [.value value]) emptyName after ∧ PureFrame state after := by
  core_call_pure intrinsic as callee
  apply RunsStmt.returnPure
  apply RunsExpr.matchPure (value := value) (bindings := []) (body := .call unknown.id [])
  · core_run
  · exact route.intrinsic
  · core_formed
  · exact actualUnknown (by core_formed)

/-- Reuse the actual non-atom/non-operator prefix for every fallback arm.
    Payload bindings cannot shadow the three forwarding parameters. -/
theorem actualDispatch (route : Route value) (context : Context state) (input : Protected context reference)
    (tree : Ready region { heap := reference })
    (representation : context.tree = tree.value) (inside : index < region.count)
    (parent : region.events index = value)
    (writer : Writer (entry route.target route.literalArguments) reference tree.value index output scope)
    (nameContext : scope.Matches context) (room : context.position + output.length ≤ context.capacity)
    (environment : WriterEnvironment state) :
    ∃ after, RunsExpr extractedProgram state (context.expressionCall index)
      (.signed .i32 (context.position + output.length : Nat)) after ∧
      WriterFrame state after (context.address + context.position) output := by
  have formed := environment.formed
  core_call_framed Lanius.Extraction.RunsExpr.callWriter expression as callee
  let viewed := callee.bindLocal (expression.bindingId 0) context.value
  let current := viewed.bindLocal (expression.bindingId 1)
    (.rawSlice eventType region.eventsAddress region.eventsLength)
  have readEvent : readRawSliceIndex extractedProgram state eventType
      region.eventsAddress region.eventsLength index = .ok value := by
    have read := input.memory.reads.rawSlice (tree.eventReads index inside)
    rw [parent] at read
    exact read
  apply actualViewEvents (context.reheap (after := callee) rfl) tree representation (by core_local) (by core_formed)
  apply RunsStmt.guardWriterFalse
  · have classify := actualNonAtom value tree inside (state := current) readEvent route.nonAtom (by core_formed)
    rw [← representation] at classify
    core_pure_expr
  · intro nonAtom atomFrame
    have atomHeap : nonAtom.heap = state.heap := atomFrame.heap
    have atomRead : readRawSliceIndex extractedProgram nonAtom eventType
        region.eventsAddress region.eventsLength index = .ok value := by
      simpa only [readRawSliceIndex, atomHeap] using readEvent
    apply RunsStmt.letReadWriter (value := emptyName)
    · apply RunsExpr.callPureArguments (values := [value])
      · core_arguments
      · exact binaryUnknown route (by core_formed)
    · intro binaryReady binaryFrame
      apply RunsStmt.guardPureWriter false
      · simp
      · core_run
      · apply RunsStmt.letReadWriter (value := emptyName)
        · have intrinsicRead : readRawSliceIndex extractedProgram
              (binaryReady.bindLocal (expression.bindingId 2) emptyName) eventType
              region.eventsAddress region.eventsLength index = .ok value := by
            simpa only [readRawSliceIndex, State.bindLocal, State.bindCell, binaryFrame.heap, atomHeap] using readEvent
          apply RunsExpr.callPureArguments (values := [value])
          · core_arguments
          · exact intrinsicUnknown route (by core_formed)
        · intro intrinsicReady intrinsicFrame
          let final := intrinsicReady.bindLocal (expression.bindingId 3) emptyName
          have heap : final.heap = state.heap := intrinsicFrame.heap.trans (binaryFrame.heap.trans atomHeap)
          have views : final.i32ArrayViews = state.i32ArrayViews :=
            intrinsicFrame.views.trans (binaryFrame.views.trans atomFrame.views)
          have finalRead : readRawSliceIndex extractedProgram final eventType
              region.eventsAddress region.eventsLength index = .ok value := by
            simpa only [readRawSliceIndex, heap] using readEvent
          apply RunsStmt.guardPureWriter false
          · simp
          · core_run
          · apply RunsStmt.returnWriter
            apply RunsExpr.matchWriter (value := value) (bindings := route.bindings)
              (body := .call route.target (arguments ++ route.literalArguments.map Expr.value))
            · core_run
            · exact route.selected
            · core_formed
            · have finalFormed : final.CellsWellFormed := by core_formed
              have kept {i : Nat} (bound : i < 3) {v : Value}
                  (found : final.local? (expression.argumentId i) = some v) :
                  (final.bindLocals route.bindings).local? (expression.argumentId i) = some v :=
                State.bindLocals_preservesLocal final route.bindings finalFormed _ _
                  (fun binding member => route.noShadow binding member i bound) found
              have arg0 := kept (i := 0) (by decide) (show final.local? (expression.argumentId 0) = some context.views by core_local)
              have arg1 := kept (i := 1) (by decide) (show final.local? (expression.argumentId 1) = some (.signed .i32 index) by core_local)
              have arg2 := kept (i := 2) (by decide) (show final.local? (expression.argumentId 2) = some (.signed .i32 context.position) by core_local)
              have boundFrame := (CallerFrame.refl finalFormed).bindLocals route.bindings
              have boundHeap := boundFrame.heap.trans heap
              have boundViews := boundFrame.views.trans views
              have checked := writer (context.reheap (after := final.bindLocals route.bindings) boundHeap)
                (input.reheap boundHeap) representation nameContext room
                (environment.reheap boundHeap boundViews boundFrame.currentFormed)
              apply RunsExpr.writerArguments
                (values := [context.views, .signed .i32 index, .signed .i32 context.position] ++ route.literalArguments)
              · apply RunsExprs.cons (RunsExpr.ofStable (StableExpr.local arg0) rfl)
                apply RunsExprs.cons (RunsExpr.ofStable (StableExpr.local arg1) rfl)
                apply RunsExprs.cons (RunsExpr.ofStable (StableExpr.local arg2) rfl)
                exact RunsExprs.values route.literalArguments
              · exact checked

#print axioms actualDispatch

end SurfaceFallbackProof
