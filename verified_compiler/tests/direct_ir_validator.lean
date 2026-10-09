import verified_compiler.tests.direct_ir_builder_navigation

namespace IRValidatorProof
open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRShapeProof IRChildrenProof
open IRBuilderProof IRBuilderCallProof IRBuilderNavigationProof

private def source := Extracted.«ir::body_tree».Functions.«valid».core
private def eventType := ((Extracted.«ir::body_tree».Functions.«shape».core.parameters[0]?).getD (0, .unit)).2
private def counter := source.bindingId 2
private def loop := source.whileLoop 0
def validCall (tree : Value) : Expr := .call source.id [.value tree]
def treeValue (events results : Value) (hasResults : Bool) (ends : Value) (count : Int) : Value :=
  source_value Extracted.«ir::body_tree».Types.«Tree».mk [events, results, .boolean hasResults, ends, .signed .i32 count]

@[core_pure_rule] theorem actualNonpositive (events results ends : Value) (hasResults : Bool) (count : Int)
    (represented : -(2 ^ 31) ≤ count) (nonpositive : count ≤ 0) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (validCall (treeValue events results hasResults ends count))
      (.boolean false) after ∧ PureFrame state after := by
  core_call_pure source as callee
  core_pure

theorem _root_.IRBuilderNavigationProof.Ready.valid (tree : Ready region state) (positive : 0 < region.count) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (validCall tree.value) (.boolean true) after ∧ PureFrame state after := by
  core_call_pure source as callee
  let base := (callee.bindLocal (source.bindingId 0) (.rawSlice eventType region.eventsAddress region.eventsLength)).bindLocal
    (source.bindingId 1) (.rawSlice (.scalar (.signed .i32)) tree.address region.count)
  have baseFormed : base.CellsWellFormed := by core_formed
  have walk : ∀ remaining before, remaining ≤ region.count →
      CountedLocal base before counter ((remaining : Int) - 1) → CallerFrame base before →
      ∃ after, RunsStmt extractedProgram before (.whileLoop loop.1 loop.2) .next after ∧
        CountedLocal base after counter (-1) ∧ CallerFrame base after := by
    intro remaining
    induction remaining with
    | zero =>
        intro before bounded counted framed
        core_facts [counted, framed]
        exact ⟨before, RunsStmt.whileFalse (by core_run), counted, framed⟩
    | succ remaining ih =>
        intro before bounded counted framed
        simp only [Int.natCast_add, Int.natCast_one, Int.add_sub_cancel] at counted
        core_facts [counted, framed]
        obtain ⟨nonnegative, room, kind, endpoint, stored, chain⟩ := tree.suffix remaining (by omega) (by omega)
        have eventRead := (tree.reheap framed.heap).eventReads remaining (by omega)
        have classified := region.classified remaining (by omega)
        have subtraction := eval_i32_subNat extractedProgram.target region.count remaining (by omega) region.fits
        have predecessor := eval_i32_subNat extractedProgram.target (region.count - remaining) 1 (by omega) (Nat.lt_of_le_of_lt (Nat.sub_le _ _) region.fits)
        have kindTest : evalBinaryValue extractedProgram.target .equal (kindValue (region.kinds remaining))
            (kindValue .InvalidNode) = .ok (.boolean false) := by cases choice : region.kinds remaining <;> simp_all [kindValue, evalBinaryValue, scalarEqual]
        obtain ⟨parentAfter, parentRun, parentPure⟩ : ∃ after, RunsExpr extractedProgram before
            (source.bindingInitializer 3) (shapeValue (kindValue (region.kinds remaining))
              (region.arities remaining) (ruleValue (region.rules remaining))) after ∧ PureFrame before after := by core_pure_expr
        let parentReady := parentAfter.bindLocal (source.bindingId 3)
          (shapeValue (kindValue (region.kinds remaining)) (region.arities remaining) (ruleValue (region.rules remaining)))
        let child : IRChildrenProof.Input parentReady := {
          count := region.count, index := remaining, arity := (region.arities remaining).toNat
          eventsAddress := region.eventsAddress, eventsLength := region.eventsLength, endsAddress := tree.address
          fits := region.fits, inside := by omega, room := by omega, parentKind := region.kinds remaining, rule := region.rules remaining
          events := region.events, kinds := region.kinds, eventArities := region.arities, eventRules := region.rules, ends := tree.ends
          eventReads := (tree.reheap (after := parentReady) (parentPure.heap.trans framed.heap)).eventReads
          endReads := (tree.reheap (after := parentReady) (parentPure.heap.trans framed.heap)).contents
          classified := region.classified }
        have arity : ((region.arities remaining).toNat : Int) = region.arities remaining := Int.toNat_of_nonneg nonnegative
        have walked := (child.walk_accepts _ _ _ endpoint).mpr chain
        obtain ⟨childAfter, childRun, childPure⟩ : ∃ after, RunsExpr extractedProgram parentReady
            (source.bindingInitializer 4) (.signed .i32 (tree.ends remaining)) after ∧ PureFrame parentReady after := by
          apply RunsExpr.callPureArguments (by core_arguments)
          simpa only [Input.call, child, arity, walked, ← stored, List.map_cons, List.map_nil] using! actualChildren child (by core_formed)
        have endRead := (tree.reheap (childPure.heap.trans (parentPure.heap.trans framed.heap))).contents remaining (by omega)
        simp only [Ready.reheap] at endRead
        have different : source.bindingId 4 ≠ counter ∧ source.bindingId 3 ≠ counter := by decide +kernel
        let scope := (((framed.transPure parentPure).bindLocal (source.bindingId 3) _).transPure childPure).bindLocal
          (source.bindingId 4) (.signed .i32 (tree.ends remaining))
        obtain ⟨next, decrement, nextCounter, heap, world, views⟩ := counted.decrementScoped (program := extractedProgram) baseFormed scope.cells
          (by simp [State.cellId?, State.bindLocal, State.bindCell, parentReady, childPure.locals, parentPure.locals, counted.locals, different.1, different.2])
          (by core_local) (Nat.lt_trans (by omega) region.fits)
        have iteration : RunsStmt extractedProgram before loop.2 .next (restoreLocals before next) := by
          have run : RunsStmt extractedProgram before loop.2 .next (restoreLocals parentAfter next) := by core_stmt_forward
          simpa only [restoreLocals, parentPure.locals] using run
        have nextFrame : CallerFrame base (restoreLocals before next) :=
          ⟨baseFormed, nextCounter.cells, heap.trans scope.heap, world.trans scope.world, views.trans scope.views⟩
        obtain ⟨after, rest, finalCounter, finalFrame⟩ := ih _ (by omega) nextCounter nextFrame
        exact ⟨after, RunsStmt.whileStep (by core_run) iteration (Or.inl rfl) rest, finalCounter, finalFrame⟩
  have counterScope : ∃ after, RunsStmt extractedProgram base (source.bindingStatement 2)
      (.returned (some (.boolean true))) after ∧ PureFrame base after := by
    obtain ⟨after, loopRun, counted, framed⟩ := walk region.count _ (Nat.le_refl _)
      (CountedLocal.start baseFormed counter ((region.count : Int) - 1)) ((CallerFrame.refl baseFormed).bindLocal counter _)
    core_facts [counted, framed]
    have root := (tree.reheap framed.heap).contents 0 positive
    simp only [Ready.reheap, tree.root] at root
    have initial := eval_i32_predecessor extractedProgram.target region.count region.fits
    exact ⟨restoreLocals base after, RunsStmt.letLocal (value := .signed .i32 ((region.count : Int) - 1)) (by core_run) (RunsStmt.sequenceNext loopRun (by core_stmt)), framed.restoreLocals⟩
  core_pure

theorem actualBuilderValidation (region : Region original) (positive : 0 < region.count)
    (formed : original.CellsWellFormed) (unique : HeapBlockBasesUnique original.heap) (views : original.i32ArrayViews = []) :
    ∃ value built after truth, RunsExpr extractedProgram original region.call value built ∧
      RunsExpr extractedProgram built (validCall value) (.boolean truth) after ∧ FreshCellFrame original after ∧ PureFrame built after ∧
      ((value = emptyTree ∧ truth = false) ∨ ∃ tree : Ready region after, value = tree.value ∧ truth = true) := by
  obtain ⟨value, built, buildRun, cells, rejected | ⟨tree, accepted⟩⟩ := actualReadyCall region formed unique views
  · subst value
    obtain ⟨after, run, pure⟩ : ∃ after, RunsExpr extractedProgram built (validCall emptyTree) (.boolean false) after ∧ PureFrame built after := by core_pure_expr
    exact ⟨emptyTree, built, after, false, buildRun, run, cells.trans pure.cells, pure, Or.inl ⟨rfl, rfl⟩⟩
  · obtain ⟨after, run, pure⟩ := tree.valid positive (cells.after_cellsWellFormed formed)
    exact ⟨value, built, after, true, buildRun, accepted ▸ run, cells.trans pure.cells, pure, Or.inr ⟨tree.reheap pure.heap, accepted, rfl⟩⟩

#print axioms actualNonpositive
#print axioms IRBuilderNavigationProof.Ready.valid
#print axioms actualBuilderValidation

end IRValidatorProof
