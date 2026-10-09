import verified_compiler.tests.direct_surface_dispatch
import Lanius.Extraction.WriterCursor

namespace SurfaceUnaryProof

open Lanius Lanius.Core Lanius.Semantics Lanius.Extraction Lanius.Memory
open SurfaceBooleanProof IRBuilderNavigationProof SurfaceDispatchProof

private def source := Extracted.«verified::lean_typed_body».Functions.«surface_unary_output».core
inductive Unary where | positive | negate | not
def Unary.event : Unary → Value
  | .positive => source_value Extracted.«ir::body_events».Types.«Event».«ExpressionUnaryPositive» []
  | .negate => source_value Extracted.«ir::body_events».Types.«Event».«ExpressionUnaryNegate» []
  | .not => source_value Extracted.«ir::body_events».Types.«Event».«ExpressionUnaryNot» []
def Unary.symbol : Unary → Fin 256
  | .positive => ⟨43, by decide⟩ | .negate => ⟨45, by decide⟩ | .not => ⟨33, by decide⟩
def Unary.wrap (operation : Unary) (output : List UInt8) : List UInt8 :=
  [40, UInt8.ofNat operation.symbol.val, 40] ++ output ++ [41, 41]
def _root_.SurfaceBooleanProof.Context.unaryCall (context : Context state) (index : Nat) : Expr :=
  .call source.id ([context.views, .signed .i32 index, .signed .i32 context.position].map Expr.value)
private def parts : Expr × Stmt := match source.body with
  | some (.letLocal _ _ _ (.letLocal _ _ _ (.letLocal _ _ symbol (.sequence _ body)))) => (symbol, body)
  | _ => (.value .unit, .skip)
private def right (ordinal : Nat) : Expr := match source.effectExpression ordinal with
  | .assign _ _ expression => expression | _ => .value .unit
private def arguments (ordinal : Nat) : List Expr := match right ordinal with
  | .call _ arguments => arguments | _ => []

private theorem childShape : right 2 = .call expression.id (arguments 2) := rfl
private theorem closingBytes : World.utf8Bytes "))" = [41, 41] := rfl

private theorem unaryArity (operation : Unary) (classified : IRShapeProof.Classifies operation.event
    (IRShapeProof.shapeValue (IRShapeProof.kindValue kind) arity (IRShapeProof.ruleValue rule))) :
    arity = 1 := by
  cases operation <;> cases classified with
  | fixed listed =>
      simp [IRShapeProof.fixedShapes, Unary.event, IRShapeProof.shapeValue] at listed
      simp_all
  | payload listed => simp [IRShapeProof.payloadShapes, Unary.event] at listed
  | counted listed => simp [IRShapeProof.countedShapes, Unary.event] at listed

/-- One actual recursive step. The final expression induction, rather than a
    supported-input assumption, must supply its child-writer contract. -/
theorem actualUnaryStep (operation : Unary) (context : Context state) (input : Protected context reference)
    (tree : Ready region { state with heap := reference })
    (representation : context.tree = tree.value) (inside : index + 1 < region.count)
    (parent : region.events index = operation.event)
    {scope : Scope} (childWriter : Writer Context.expressionCall reference tree.value (index + 1) output scope)
    (nameContext : scope.Matches context)
    (room : context.position + (operation.wrap output).length ≤ context.capacity)
    (environment : WriterEnvironment state) :
    ∃ after, RunsExpr extractedProgram state (context.unaryCall index)
      (.signed .i32 (context.position + (operation.wrap output).length : Nat)) after ∧
      WriterFrame state after (context.address + context.position) (operation.wrap output) := by
  have formed := environment.formed
  have glyphFits := operation.symbol.isLt
  have oneChild := unaryArity operation (show IRShapeProof.Classifies operation.event
    (IRShapeProof.shapeValue (IRShapeProof.kindValue (region.kinds index)) (region.arities index)
      (IRShapeProof.ruleValue (region.rules index))) from by
    rw [← parent]
    exact region.classified index (by omega))
  have space : context.position + 5 + output.length ≤ context.capacity := by
    have measured := room
    simp only [Unary.wrap, List.length_append, List.length_cons, List.length_nil] at measured
    omega
  core_call_framed Lanius.Extraction.RunsExpr.callWriter source as callee
  let viewed := callee.bindLocal (source.bindingId 0) context.value
  let events := viewed.bindLocal (source.bindingId 1) (.rawSlice eventType region.eventsAddress region.eventsLength)
  let base := events.bindLocal (source.bindingId 2) (.signed .i32 operation.symbol.val)
  let start : Context base := context.reheap rfl
  have baseEnvironment := environment.reheap (after := base) rfl rfl (by core_formed)
  have startInput : Protected start reference := ⟨input.memory, by
    simpa only [readRawSliceIndex, start, Context.reheap, Context.value] using input.viewRead⟩
  have readEvent := input.memory.reads.rawSlice (tree.eventReads index (by omega))
  rw [parent] at readEvent
  have symbol : RunsExpr extractedProgram events parts.1 (.signed .i32 operation.symbol.val) events := by
    apply RunsExpr.matchValue (value := operation.event) (bindings := [])
      (body := .value (.signed .i32 operation.symbol.val)) (before := events) (middle := events) (after := events)
    · core_run
    · cases operation <;> rfl
    · core_run
  have body : ∃ after, RunsStmt extractedProgram base parts.2
      (.returned (some (.signed .i32 (context.position + (operation.wrap output).length : Nat)))) after ∧
      WriterFrame base after (context.address + context.position) (operation.wrap output) := by
    have firstRoom : start.position + 1 ≤ start.capacity := by
      change context.position + 1 ≤ context.capacity
      omega
    obtain ⟨first, firstCall, firstFrame⟩ := OutputWriterProof.byte start.toBuffer ⟨40, by decide⟩ firstRoom baseEnvironment
    let bound := first.bindLocal (source.bindingId 3) (.signed .i32 (context.position + 1 : Nat))
    have cursor1 : WriterCursor base bound (source.bindingId 3) first.nextCell
        (context.address + context.position) context.position [40] :=
      WriterCursor.start firstFrame baseEnvironment.formed firstCall.choose_spec.2 _
    have firstRun : RunsExpr extractedProgram base
        (match parts.2 with | .letLocal _ _ initial _ => initial | _ => .value .unit)
        (.signed .i32 (context.position + 1 : Nat)) first := by
      exact RunsExpr.callArguments (by core_arguments) firstCall
    obtain ⟨two, run2, cursor2⟩ := cursor1.advanceArguments baseEnvironment.formed
      (OutputWriterProof.byteAt start.toBuffer cursor1.frame operation.symbol
        (by simp [start, Context.reheap]; omega) baseEnvironment)
      (expressions := arguments 0) (by core_arguments) rfl
    obtain ⟨three, run3, cursor3⟩ := cursor2.advanceArguments baseEnvironment.formed
      (OutputWriterProof.byteAt start.toBuffer cursor2.frame ⟨40, by decide⟩
        (by simp [start, Context.reheap]; omega) baseEnvironment)
      (expressions := arguments 1) (by core_arguments) rfl
    let ctx3 := start.afterOutput startInput cursor3.frame.output (by change context.position + 3 ≤ context.capacity; omega)
    have env3 := baseEnvironment.afterWrite cursor3.frame
    have formed3 := env3.formed
    let live := tree.afterOutput startInput.memory cursor3.frame.output (by change context.address ≤ context.address + context.position; omega)
      (by change context.address + context.position + 3 ≤ context.address + context.words * 4
          have storage := context.storage; omega)
    have navigate : ∃ after, RunsExpr extractedProgram three
        (.call Extracted.«ir::body_tree».Functions.«first_child».core.id
          [.value context.tree, .value (.signed .i32 index)])
        (.signed .i32 (index + 1 : Nat)) after ∧ PureFrame three after := by
      have navigation := live.firstChild (by omega : index < region.count) formed3
      simp only [Ready.firstIndex, oneChild, show ¬(1 : Int) ≤ 0 by decide, ↓reduceIte,
      Ready.firstChildCall, show live.value = context.tree from representation.symm] at navigation
      exact navigation
    obtain ⟨argumentsState, navigationRun, argumentsFrame⟩ := navigate
    have argumentsRun : RunsExprs extractedProgram three (arguments 2)
        [ctx3.views, .signed .i32 (index + 1 : Nat), .signed .i32 ctx3.position] argumentsState := by
      refine RunsExprs.cons (by core_run) (RunsExprs.cons ?_ (RunsExprs.cons (by core_run) RunsExprs.nil))
      exact RunsExpr.callArguments (by core_arguments) navigationRun
    let childContext := ctx3.reheap argumentsFrame.heap
    have protected3 := startInput.afterOutput cursor3.frame.output (by change context.position + 3 ≤ context.capacity; omega)
    obtain ⟨printed, childCall, childFrame⟩ := childWriter childContext
      (protected3.reheap argumentsFrame.heap) representation nameContext
      (by change (context.position + 3) + output.length ≤ context.capacity; omega)
      (env3.reheap argumentsFrame.heap argumentsFrame.views argumentsFrame.afterFormed)
    have childRun : RunsExpr extractedProgram three (right 2)
        (.signed .i32 (context.position + ([40, UInt8.ofNat operation.symbol.val, 40] ++ output).length : Nat)) printed := by
      rw [childShape]
      have endEquals : childContext.position + output.length =
          context.position + ([40, UInt8.ofNat operation.symbol.val, 40] ++ output).length := by
        change (context.position + 3) + output.length = _
        simp only [List.length_append, List.length_cons, List.length_nil]
        omega
      rw [endEquals] at childCall
      exact RunsExpr.callArguments argumentsRun childCall
    have childWritten := childFrame.prependPure ((CallerFrame.refl formed3).transPure argumentsFrame)
    obtain ⟨four, run4, cursor4⟩ := cursor3.advance baseEnvironment.formed childRun childWritten
    obtain ⟨last, closingRun, finalFrame⟩ := cursor4.finishArguments
      (OutputWriterProof.textAt start.toBuffer cursor4.frame "))" 2 rfl
        (by simp [start, Context.reheap, closingBytes, Unary.wrap] at room ⊢; omega) baseEnvironment)
      (expressions := [.field (.local (source.bindingId 0)) 6, .field (.local (source.bindingId 0)) 7,
        .local (source.bindingId 3), .value (.string "))"), .value (.signed .i32 2)])
      (by core_arguments) rfl
    have tailRun : RunsStmt extractedProgram bound
        (match parts.2 with | .letLocal _ _ _ body => body | _ => .skip)
        (.returned (some (.signed .i32 (context.position + (operation.wrap output).length : Nat)))) last := by
      simp only [closingBytes, List.append_assoc] at closingRun
      core_stmt
    exact ⟨restoreLocals first last, .letLocal firstRun tailRun,
      by simpa [closingBytes, Unary.wrap] using finalFrame.restoreLocals first⟩
  apply actualViewEvents (context.reheap (after := callee) rfl)
    tree representation (by core_local) (by core_formed)
  core_writer

#print axioms actualUnaryStep

end SurfaceUnaryProof
