import verified_compiler.tests.direct_surface_operations
import Lanius.Extraction.WriterCursor

namespace SurfaceBinaryProof

open Lanius Lanius.Core Lanius.Semantics Lanius.Extraction Lanius.Memory
open SurfaceBooleanProof SurfaceDispatchProof SurfaceOperationsProof IRBuilderNavigationProof IRNavigationProof

private def source := Extracted.«verified::lean_typed_body».Functions.«surface_binary_output».core
def _root_.SurfaceBooleanProof.Context.binaryCall (context : Context state) (index : Nat) : Expr :=
  .call source.id ([context.views, .signed .i32 index, .signed .i32 context.position].map Expr.value)
def binaryBytes (operation : Binary) (left right : List UInt8) : List UInt8 :=
  [40] ++ left ++ [32] ++ World.utf8Bytes operation.spelling ++ [32] ++ right ++ [41]
private def body : Stmt := match source.body with
  | some (.letLocal _ _ _ (.sequence _ (.letLocal _ _ _ (.letLocal _ _ _ (.sequence _ body))))) => body
  | _ => .skip
private def right (ordinal : Nat) : Expr := match source.effectExpression ordinal with
  | .assign _ _ expression => expression | _ => .value .unit
private def arguments (ordinal : Nat) : List Expr := match right ordinal with
  | .call _ arguments => arguments | _ => []
private theorem symbolLength (operation : Binary) : (World.utf8Bytes operation.spelling).length = operation.length := rfl

/-- Compose both recursive children through the actual binary helper. The
    expression induction must discharge the child contracts in its final theorem. -/
theorem actualBinaryStep (operation : Binary) (context : Context state) (input : Protected context reference)
    (tree : Ready region { state with heap := reference })
    (representation : context.tree = tree.value) (inside : index < region.count)
    (scalar : NonPointerInput operation tree index)
    (parent : region.events index = operation.event)
    {scope : Scope} (leftWriter : Writer Context.expressionCall reference tree.value (index + 1) leftOutput scope)
    (rightWriter : Writer Context.expressionCall reference tree.value (tree.ends (index + 1)).toNat rightOutput scope)
    (nameContext : scope.Matches context)
    (room : context.position + (binaryBytes operation leftOutput rightOutput).length ≤ context.capacity)
    (environment : WriterEnvironment state) :
    ∃ after, RunsExpr extractedProgram state (context.binaryCall index)
      (.signed .i32 (context.position + (binaryBytes operation leftOutput rightOutput).length : Nat)) after ∧
      WriterFrame state after (context.address + context.position) (binaryBytes operation leftOutput rightOutput) := by
  have formed := environment.formed
  have lengths := operation.lengthBounds
  have arity := binaryArity operation (show IRShapeProof.Classifies operation.event
    (IRShapeProof.shapeValue (IRShapeProof.kindValue (region.kinds index)) (region.arities index)
      (IRShapeProof.ruleValue (region.rules index))) from by rw [← parent]; exact region.classified index inside)
  have coordinates := IRPairNavigationProof.coordinates tree inside arity
  have space : context.position + leftOutput.length + rightOutput.length + operation.length + 4 ≤ context.capacity := by
    have measured := room
    simp only [binaryBytes, List.length_append, List.length_cons, List.length_nil, symbolLength] at measured
    omega
  core_call_framed Lanius.Extraction.RunsExpr.callWriter source as callee
  let viewed := callee.bindLocal (source.bindingId 0) context.value
  have readView : readRawSliceIndex extractedProgram callee viewType context.viewAddress 1 0 =
      .ok context.value := context.readView
  have treeRead : StableExpr 2 extractedProgram viewed (.field (.local (source.bindingId 0)) 0)
      context.tree viewed := by core_expr
  have eventRead : readRawSliceIndex extractedProgram state eventType
      region.eventsAddress region.eventsLength index = .ok operation.event := by
    have read := input.memory.reads.rawSlice (tree.eventReads index inside)
    rw [parent] at read
    exact read
  apply RunsStmt.letPureWriter
  · core_run
  · core_formed
  · apply RunsStmt.guardWriterFalse
    · let retained : Ready region viewed :=
        (tree.reheap (after := { viewed with heap := reference }) rfl).ofReads input.memory.reads
      have currentScalar : NonPointerInput operation retained index := by
        intro pointerOperation
        obtain ⟨annotations, kind, read⟩ := scalar pointerOperation
        exact ⟨annotations, kind, input.memory.reads.rawSlice read⟩
      have guard := actualNonPointer operation retained inside currentScalar parent (by core_formed)
      apply RunsExpr.callPureArguments (values := [context.tree, .signed .i32 index])
      · core_arguments
      · rw [representation]
        exact guard
    · intro readReady readFrame
      let events := readReady.bindLocal (source.bindingId 1)
        (.rawSlice eventType region.eventsAddress region.eventsLength)
      have eventsRead : StableExpr 3 extractedProgram readReady
          (.field (.field (.local (source.bindingId 0)) 0) 0)
          (.rawSlice eventType region.eventsAddress region.eventsLength) readReady := by
        have kept := readFrame.localFound (show viewed.local? (source.bindingId 0) = some context.value by core_local)
        have currentTree : StableExpr 2 extractedProgram readReady (.field (.local (source.bindingId 0)) 0)
            context.tree readReady := by core_expr
        rw [representation] at currentTree
        exact StableExpr.field currentTree rfl
      have currentRead : readRawSliceIndex extractedProgram events eventType
          region.eventsAddress region.eventsLength index = .ok operation.event := by
        have rawHeap : events.heap = state.heap := readFrame.heap
        simpa only [readRawSliceIndex, rawHeap] using eventRead
      apply RunsStmt.letPureWriter (value := .rawSlice eventType region.eventsAddress region.eventsLength)
      · core_run
      · core_formed
      · apply RunsStmt.letReadWriter (value := operation.name)
        · have symbol := actualSymbol operation (state := events) (by core_formed)
          apply RunsExpr.callPureArguments (values := [operation.event])
          · core_arguments
          · exact symbol
        · intro symbolReady symbolFrame
          let base := symbolReady.bindLocal (source.bindingId 2) operation.name
          have heap : base.heap = state.heap := symbolFrame.heap.trans readFrame.heap
          let start : Context base := context.reheap heap
          have baseEnvironment := environment.reheap heap (symbolFrame.views.trans readFrame.views) (by core_formed)
          have startInput := input.reheap heap
          have baseView : base.local? (source.bindingId 0) = some context.value := by core_local
          have baseViews : base.local? ((source.parameters[0]?).getD (0, .unit)).1 = some context.views := by core_local
          have baseIndex : base.local? ((source.parameters[1]?).getD (0, .unit)).1 = some (.signed .i32 index) := by core_local
          have written : ∃ after, RunsStmt extractedProgram base body
              (.returned (some (.signed .i32 (context.position + (binaryBytes operation leftOutput rightOutput).length : Nat)))) after ∧
              WriterFrame base after (context.address + context.position) (binaryBytes operation leftOutput rightOutput) := by
            obtain ⟨first, firstCall, firstFrame⟩ := OutputWriterProof.byte start.toBuffer ⟨40, by decide⟩
              (by change context.position + 1 ≤ context.capacity; omega) baseEnvironment
            let bound := first.bindLocal (source.bindingId 3) (.signed .i32 (context.position + 1 : Nat))
            have cursor1 : WriterCursor base bound (source.bindingId 3) first.nextCell
                (context.address + context.position) context.position [40] :=
              WriterCursor.start firstFrame baseEnvironment.formed firstCall.choose_spec.2 _
            let ctx1 := start.afterOutput startInput cursor1.frame.output (by change context.position + 1 ≤ context.capacity; omega)
            have env1 := baseEnvironment.afterWrite cursor1.frame
            let live := tree.afterOutput startInput.memory cursor1.frame.output
              (by change context.address ≤ context.address + context.position; omega)
              (by change context.address + context.position + 1 ≤ context.address + context.words * 4
                  have storage := context.storage; omega)
            have firstChild := live.firstChild inside env1.formed
            simp only [Ready.firstIndex, arity, show ¬(2 : Int) ≤ 0 by decide, ↓reduceIte] at firstChild
            obtain ⟨leftReady, leftCall, leftFrame⟩ := firstChild
            let leftBound := leftReady.bindLocal (source.bindingId 4) (.signed .i32 (index + 1 : Nat))
            have cursorLeft := (cursor1.afterPure leftFrame).bindLocal baseEnvironment.formed
              (source.bindingId 4) (.signed .i32 (index + 1 : Nat)) (by decide)
            have children := tree.childrenStart inside
            have sibling := (live.reheap (after := leftBound) leftFrame.heap).nextChild
              (parent := index) (current := index + 1) (ordinal := 0) (remaining := 1) (by omega)
              (by simpa [Ready.Children, Ready.reheap, Ready.afterOutput, Ready.ofReads, live, arity] using children)
              (cursorLeft.frame.afterFormed baseEnvironment.formed)
            simp only [show ¬(1 : Nat) = 0 by decide, ↓reduceIte] at sibling
            obtain ⟨rightReady, rightCall, rightFrame⟩ := sibling
            let ready := rightReady.bindLocal (source.bindingId 5) (.signed .i32 (tree.ends (index + 1)))
            have cursor := (cursorLeft.afterPure rightFrame).bindLocal baseEnvironment.formed
              (source.bindingId 5) (.signed .i32 (tree.ends (index + 1))) (by decide)
            have rightSafe : ∀ {current front}, WriterCursor base current (source.bindingId 3) first.nextCell
                (context.address + context.position) context.position front
                (scope := [(source.bindingId 5, rightReady.nextCell), (source.bindingId 4, leftReady.nextCell)]) →
                current.cellId? (source.bindingId 5) ≠ some first.nextCell := by
              intro current front currentCursor
              have slot : current.cellId? (source.bindingId 5) = some rightReady.nextCell := by
                simp [State.cellId?, currentCursor.locals]
              rw [slot]
              have freshLeft := leftFrame.cells.choose_spec.2.1
              have freshRight := rightFrame.cells.choose_spec.2.1
              change first.nextCell + 1 ≤ leftReady.nextCell at freshLeft
              change leftReady.nextCell + 1 ≤ rightReady.nextCell at freshRight
              have leftStep := Nat.lt_of_lt_of_le (Nat.lt_succ_self first.nextCell) freshLeft
              have rightStep := Nat.le_trans (Nat.le_succ leftReady.nextCell) freshRight
              exact fun equal => (Nat.ne_of_lt (Nat.lt_of_lt_of_le leftStep rightStep)) (Option.some.inj equal).symm
            have leftRead : ready.local? (source.bindingId 4) = some (.signed .i32 (index + 1 : Nat)) := by core_local
            have rightRead : ready.local? (source.bindingId 5) = some (.signed .i32 (tree.ends (index + 1))) := by core_local
            have firstRun : RunsExpr extractedProgram base
                (match body with | .letLocal _ _ initial _ => initial | _ => .value .unit)
                (.signed .i32 (context.position + 1 : Nat)) first := by
              exact RunsExpr.callArguments (by core_arguments) firstCall
            have leftInitializer : RunsExpr extractedProgram bound
                (.call Extracted.«ir::body_tree».Functions.«first_child».core.id
                  [.field (.local (source.bindingId 0)) 0, .local ((source.parameters[1]?).getD (0, .unit)).1])
                (.signed .i32 (index + 1 : Nat)) leftReady := by
              have canonical := leftCall
              simp only [Ready.firstChildCall] at canonical
              rw [show (index : Int) + 1 = ((index + 1 : Nat) : Int) by omega,
                show live.value = context.tree from representation.symm] at canonical
              exact RunsExpr.callArguments (by core_arguments) canonical
            have rightInitializer : RunsExpr extractedProgram leftBound
                (.call Extracted.«ir::body_tree».Functions.«next_sibling».core.id
                  [.field (.local (source.bindingId 0)) 0, .local ((source.parameters[1]?).getD (0, .unit)).1,
                    .local (source.bindingId 4)]) (.signed .i32 (tree.ends (index + 1))) rightReady := by
              have canonical := rightCall
              simp only [siblingCall] at canonical
              rw [show (live.reheap (after := leftBound) leftFrame.heap).value = context.tree from representation.symm] at canonical
              exact RunsExpr.callArguments (by core_arguments) canonical
            let ctx : Context ready := ctx1.reheap (rightFrame.heap.trans leftFrame.heap)
            have ctxInput : Protected ctx reference :=
              (startInput.afterOutput cursor1.frame.output (by change context.position + 1 ≤ context.capacity; omega)).reheap
                (after := ready) (rightFrame.heap.trans leftFrame.heap)
            obtain ⟨printedLeft, leftExpression, leftWritten⟩ := leftWriter ctx ctxInput representation nameContext
              (by change (context.position + 1) + leftOutput.length ≤ context.capacity; omega)
              (baseEnvironment.afterWrite cursor.frame)
            have leftRun : RunsExpr extractedProgram ready (right 0)
                (.signed .i32 (context.position + ([40] ++ leftOutput).length : Nat)) printedLeft := by
              have endEquals : ctx.position + leftOutput.length = context.position + ([40] ++ leftOutput).length := by
                change (context.position + 1) + leftOutput.length = _
                simp only [List.length_append, List.length_cons, List.length_nil]; omega
              rw [endEquals] at leftExpression
              exact RunsExpr.callArguments (by core_arguments) leftExpression
            obtain ⟨two, run2, cursor2, keep2⟩ := cursor.advanceKeeping baseEnvironment.formed leftRun
              (by simpa [ctx, Context.reheap, ctx1, Context.afterOutput, start, Nat.add_assoc] using leftWritten)
            have rightRead2 := keep2 _ _ rightRead (rightSafe cursor)
            obtain ⟨three, run3, cursor3, keep3⟩ := cursor2.advanceArgumentsKeeping baseEnvironment.formed
              (OutputWriterProof.byteAt start.toBuffer cursor2.frame ⟨32, by decide⟩ (by
                simp [start, Context.reheap]; omega) baseEnvironment)
              (expressions := arguments 1) (by core_arguments) rfl
            have rightRead3 := keep3 _ _ rightRead2 (rightSafe cursor2)
            obtain ⟨four, run4, cursor4, keep4⟩ := cursor3.advanceArgumentsKeeping baseEnvironment.formed
              (OutputWriterProof.textAt start.toBuffer cursor3.frame operation.spelling operation.length (symbolLength operation)
                (by simp [start, Context.reheap, symbolLength]; omega) baseEnvironment)
              (expressions := arguments 2) (by core_arguments) rfl
            have rightRead4 := keep4 _ _ rightRead3 (rightSafe cursor3)
            obtain ⟨five, run5, cursor5, keep5⟩ := cursor4.advanceArgumentsKeeping baseEnvironment.formed
              (OutputWriterProof.byteAt start.toBuffer cursor4.frame ⟨32, by decide⟩
                (by simp [start, Context.reheap, symbolLength]; omega) baseEnvironment)
              (expressions := arguments 3) (by core_arguments) rfl
            have rightRead5 := keep5 _ _ rightRead4 (rightSafe cursor4)
            let ctx5 := start.afterOutput startInput cursor5.frame.output (by simp [start, Context.reheap, symbolLength] at room ⊢; omega)
            have env5 := baseEnvironment.afterWrite cursor5.frame
            obtain ⟨printedRight, rightExpression, rightWritten⟩ := rightWriter ctx5
              (startInput.afterOutput cursor5.frame.output (by simp [Context.reheap, symbolLength] at room ⊢; omega)) representation nameContext
              (by simp [ctx5, Context.afterOutput, start, Context.reheap, symbolLength]; omega) env5
            have rightRun : RunsExpr extractedProgram five (right 4)
                (.signed .i32 (context.position + ((((([40] ++ leftOutput) ++ [32]) ++ World.utf8Bytes operation.spelling) ++ [32]) ++ rightOutput).length : Nat)) printedRight := by
              have endEquals : ctx5.position + rightOutput.length =
                  context.position + ((((([40] ++ leftOutput) ++ [32]) ++ World.utf8Bytes operation.spelling) ++ [32]) ++ rightOutput).length := by
                simp [ctx5, Context.afterOutput, start, Context.reheap, Nat.add_assoc, Nat.add_left_comm, Nat.add_comm]
              rw [endEquals] at rightExpression
              apply RunsExpr.callArguments (values := [ctx5.views, .signed .i32 (tree.ends (index + 1)),
                .signed .i32 ctx5.position])
              · core_arguments
              · have adjusted := rightExpression
                change RunsExpr extractedProgram five
                  (.call expression.id ([ctx5.views, .signed .i32 ((tree.ends (index + 1)).toNat : Nat),
                    .signed .i32 ctx5.position].map Expr.value)) _ printedRight at adjusted
                rw [coordinates.2.2.2] at adjusted
                exact adjusted
            obtain ⟨six, run6, cursor6⟩ := cursor5.advance baseEnvironment.formed rightRun
              (by simpa [ctx5, Context.afterOutput, start, Context.reheap, Nat.add_assoc] using rightWritten)
            obtain ⟨last, closingRun, finalFrame⟩ := cursor6.finishArguments
              (OutputWriterProof.byteAt start.toBuffer cursor6.frame ⟨41, by decide⟩
                (by simp [start, Context.reheap, symbolLength]; omega) baseEnvironment)
              (expressions := [.field (.local (source.bindingId 0)) 6, .field (.local (source.bindingId 0)) 7,
                .local (source.bindingId 3), .value (.signed .i32 41)]) (by core_arguments) rfl
            have tailRun : RunsStmt extractedProgram bound
                (match body with | .letLocal _ _ _ tail => tail | _ => .skip)
                (.returned (some (.signed .i32 (context.position + (binaryBytes operation leftOutput rightOutput).length : Nat))))
                (restoreLocals leftReady (restoreLocals rightReady last)) := by
              apply RunsStmt.letLocal leftInitializer
              apply RunsStmt.letLocal rightInitializer
              have joined :=
                RunsStmt.sequenceNext (RunsStmt.expression run2)
                  (RunsStmt.sequenceNext (RunsStmt.expression run3)
                    (RunsStmt.sequenceNext (RunsStmt.expression run4)
                      (RunsStmt.sequenceNext (RunsStmt.expression run5)
                        (RunsStmt.sequenceNext (RunsStmt.expression run6) closingRun))))
              simp only [binaryBytes, List.append_assoc] at joined ⊢
              exact joined
            exact ⟨restoreLocals first (restoreLocals leftReady (restoreLocals rightReady last)),
              .letLocal firstRun tailRun,
              by simpa [binaryBytes, List.append_assoc] using
                ((finalFrame.restoreLocals rightReady).restoreLocals leftReady).restoreLocals first⟩
          apply RunsStmt.guardPureWriter false
          · simp
          · core_run
          · exact written

#print axioms actualBinaryStep

end SurfaceBinaryProof
