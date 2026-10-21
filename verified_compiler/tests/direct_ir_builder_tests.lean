import verified_compiler.tests.direct_ir_builder_navigation

namespace IRBuilderTests

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRShapeProof IRChildrenProof IRBuilderProof
open IRBuilderNavigationProof

private def builder := Extracted.«ir::body_tree».Functions.«build».core
private def leaf := source_value Extracted.«ir::body_events».Types.«Event».«ExpressionPointerNull» []
private def parent := source_value Extracted.«ir::body_events».Types.«Event».«ExpressionUnaryPositive» []
private def statement := source_value Extracted.«ir::body_events».Types.«Event».«StatementSkip» []
private def eventType : Ty := match leaf with | .enumeration id _ _ => .enumeration id | _ => .unit
private def referenceType := ((Extracted.«ir::type_ref».Functions.«is_invalid».core.parameters[0]?).getD (0, .unit)).2
private def bytes (event : Value) := match event with
  | .enumeration _ tag _ => encodeNatLE 4 tag ++ List.replicate 36 0
  | _ => []
private def sample : State := {
  heap := { blocks := [{ base := 16, size := 80, alignment := 8, bytes := bytes leaf ++ bytes leaf }], nextAddress := 96 } }
private theorem width : NativeLayout.valueWords? extractedProgram eventType = some 5 := by decide +kernel
private theorem below : HeapBlocksBelowNext sample.heap := by
  intro block member
  simp only [sample, List.mem_singleton] at member
  subst block
  decide
private def base : State := ({ sample with heap := sample.heap.appendI32 (List.replicate 4 0) false none })
  |>.bindLocal (builder.argumentId 1) (.signed .i32 1)
  |>.bindLocal (builder.bindingId 1) (.rawSlice (.scalar (.signed .i32)) 96 1)
  |>.bindLocal (builder.bindingId 2) (.rawSlice eventType 88 2)
private theorem countId : builder.argumentId 1 = 1886 := by decide +kernel
private theorem endsId : builder.bindingId 1 = 1942 := by decide +kernel
private theorem eventsId : builder.bindingId 2 = 1962 := by decide +kernel
private def context : Context sample base := {
  count := 1, eventsAddress := 88, eventsLength := 2, events := fun _ => leaf
  kinds := fun _ => .ExpressionNode, arities := fun _ => 0, rules := fun _ => .NoChildren
  fits := by decide, below := below
  reads := by
    intro position inside
    have : position = 0 := by omega
    subst position
    change readRawSliceIndex extractedProgram sample eventType 88 2 0 = .ok leaf
    have layout := width
    dsimp only [eventType, leaf] at layout ⊢
    simp only [readRawSliceIndex, rawSliceElementAddress?, layout]
    rfl
  classified := by intro position inside; exact .fixed List.mem_cons_self
  formed := by simp [State.CellsWellFormed, base, sample, State.bindLocal, State.bindCell]
  endsAddress := 96, fresh := by decide
  eventsFound := by
    change base.local? (builder.bindingId 2) = some (.rawSlice eventType 88 2)
    simp only [base, countId, endsId, eventsId]
    rfl
  endsFound := by
    change base.local? (builder.bindingId 1) = some (.rawSlice (.scalar (.signed .i32)) 96 1)
    simp only [base, countId, endsId, eventsId]
    rfl
  countFound := by
    change base.local? (builder.argumentId 1) = some (.signed .i32 1)
    simp only [base, countId, endsId, eventsId]
    rfl }

private def representedRegion : IRBuilderCallProof.Region sample := {
  toSource := context.toSource, capacity := 2, resultAddress := 0, resultLength := 0, hasResultTypes := false }

private def leafEnds (index : Nat) : Int := index + 1

private theorem leafStructure : representedRegion.toSource.Suffix leafEnds 0 := by
  intro index _ inside
  have same : index = 0 := by change index < 1 at inside; omega
  subst index
  exact ⟨by decide, by decide, by decide, 1, rfl, .nil⟩

-- The public theorem runs from original event bytes, not a prepared or
-- prevalidated endpoint table. This also witnesses spare backing capacity.
theorem leafBuilderCompletes : ∃ after, ∃ tree : Ready representedRegion after,
    RunsExpr extractedProgram sample representedRegion.call tree.value after ∧
    tree.address = 96 ∧ after.CellsWellFormed := by
  obtain ⟨after, tree, run, cells, address, _⟩ :=
    actualCompleteCall representedRegion leafStructure (by decide)
      (by decide) (by decide) (by decide) (by decide)
      (by simp [State.CellsWellFormed, sample])
      (by
        intro left leftMem right rightMem same
        simp only [sample, List.mem_singleton] at leftMem rightMem
        exact leftMem.trans rightMem.symm) rfl
  have borrowed : sample.heap.borrowedAddress = 96 := by decide
  exact ⟨after, tree, run, address.trans borrowed,
    cells.after_cellsWellFormed (by simp [State.CellsWellFormed, sample])⟩

-- The returned tree is consumed immediately by the actual navigator. No
-- prepared endpoint model or assumed validation is supplied between calls.
theorem leafBuilderTraversal : ∃ built after, ∃ tree : Ready representedRegion built,
    RunsExpr extractedProgram sample representedRegion.call tree.value built ∧
    RunsExpr extractedProgram built (tree.firstChildCall 0) (.signed .i32 (-1)) after ∧
    PureFrame built after ∧
    readRawSliceIndex extractedProgram after (.scalar (.signed .i32)) 96 1 0 = .ok (.signed .i32 1) ∧
    readRawSliceIndex extractedProgram after eventType 88 2 0 = .ok leaf := by
  obtain ⟨built, tree, buildRun, address, formed⟩ := leafBuilderCompletes
  obtain ⟨after, firstRun, frame⟩ := tree.firstChild (index := 0) (by decide) formed
  have endpoint := tree.contents 0 (by decide)
  rw [address, tree.root] at endpoint
  have event := tree.eventReads 0 (by decide)
  change readRawSliceIndex extractedProgram built (.scalar (.signed .i32)) 96 1 0 = .ok (.signed .i32 1) at endpoint
  change readRawSliceIndex extractedProgram built eventType 88 2 0 = .ok leaf at event
  exact ⟨built, after, tree, buildRun, firstRun, frame,
    by simpa only [readRawSliceIndex, frame.heap] using endpoint,
    by simpa only [readRawSliceIndex, frame.heap] using event⟩

-- Concrete native storage proves the loop's domain is inhabited. The zeroed
-- table comes from allocation, not a successful-validation assumption.
theorem leafLoopCompletes : ∃ after,
    RunsStmt extractedProgram (base.bindLocal (builder.bindingId 3) (.signed .i32 0))
      (.whileLoop IRBuilderProof.loop.1 IRBuilderProof.loop.2) .next after ∧
    readRawSliceIndex extractedProgram after (.scalar (.signed .i32)) 96 1 0 = .ok (.signed .i32 1) ∧
    after.local? (builder.bindingId 3) = some (.signed .i32 (-1)) ∧
    readRawSliceIndex extractedProgram after eventType 88 2 0 = .ok leaf := by
  have table : Table context base (fun _ => 0) := Table.allocated context rfl rfl
    (by
      intro left leftMem right rightMem same
      simp only [sample, List.mem_singleton] at leftMem rightMem
      exact leftMem.trans rightMem.symm) rfl
  obtain ⟨completion, after, ends, remaining, run, frame, result⟩ :=
    actualLoop context (Frame.start context table) (Nat.le_refl 1)
  rcases result with ⟨rfl, rfl⟩ | ⟨_, index, _, _, bad⟩
  · obtain ⟨_, _, _, endpoint, value, chain⟩ := frame.suffix 0 (by omega) (by decide)
    cases chain
    refine ⟨after, run, ?_, frame.counter, frame.table.oldReads.rawSlice (context.reads 0 (by decide))⟩
    simpa only [value, context, Nat.zero_add, Int.natCast_one] using frame.table.endReads 0 (by decide)
  · change BadNode context.toSource ends index at bad
    simp only [BadNode, context] at bad
    rcases bad with impossible | impossible | impossible | missing
    · contradiction
    · have nonnegative : (0 : Int) ≤ (1 - index - 1 : Nat) := Int.natCast_nonneg _
      exact False.elim (by omega)
    · contradiction
    · exact False.elim (missing ⟨index + 1, .nil⟩)

private def region (count : Nat) := source_value Extracted.«ir::body_events».Types.«Region».mk
  [.rawSlice eventType (16 + count * 40 - 8) count, .rawSlice referenceType 0 0,
    .boolean false, .signed .i32 count]

-- Whole-function execution regressions supplement the general loop proof.
-- They cover root rejection, a bad parent, a wrong child category, and OOM.
#eval (do
  for (events, active, expected, budget) in [([parent, leaf], 2, 2, none), ([leaf, leaf], 2, 0, none),
      ([parent], 1, 0, none), ([parent, statement], 2, 0, none), ([leaf], 1, 0, some 0),
      ([leaf, statement], 1, 1, none)] do
    let storage := (events.reverse.flatMap bytes)
    let before : State := { heap := {
      blocks := [{ base := 16, size := storage.length, alignment := 8, bytes := storage }]
      nextAddress := 16 + storage.length, remaining := budget } }
    match evalExpr 200 extractedProgram before (.call builder.id [.value (region events.length),
        .value (.signed .i32 active)]) with
    | .done value after =>
        if expected == 0 then
          unless value == emptyTree do throw (IO.userError "malformed/exhausted builder did not reject")
        else
          match value with
          | .structure _ fields =>
              unless fields[4]? == some (.signed .i32 expected) do throw (IO.userError "builder count changed")
              match (fields[3]? : Option Value) with
              | some (.rawSlice _ address count) =>
                  for index in List.range count do
                    match readRawSliceIndex extractedProgram after (.scalar (.signed .i32)) address count index with
                    | .ok value =>
                        unless value == .signed .i32 expected do throw (IO.userError "builder endpoint changed")
                    | .error _ => throw (IO.userError "builder endpoint became unreadable")
              | _ => throw (IO.userError "builder lost its endpoint slice")
          | _ => throw (IO.userError "builder did not return a tree")
    | _ => throw (IO.userError "actual builder trapped or exhausted fuel") : IO Unit)

-- Two children of different subtree sizes: the second child contains a leaf.
-- This checks first-child success, subtree skipping, last-child termination,
-- leaf termination, and bounds rejection on the builder's actual result.
#eval (do
  let binary := source_value Extracted.«ir::body_events».Types.«Event».«ExpressionBinaryAdd» []
  let events := [binary, leaf, parent, leaf]
  let storage := events.reverse.flatMap bytes
  let before : State := { heap := {
    blocks := [{ base := 16, size := storage.length, alignment := 8, bytes := storage }]
    nextAddress := 16 + storage.length } }
  let .done tree built := evalExpr 500 extractedProgram before
    (.call builder.id [.value (region 4), .value (.signed .i32 4)])
    | throw (IO.userError "branching builder trapped")
  unless tree != emptyTree do throw (IO.userError "branching builder rejected")
  let first := Extracted.«ir::body_tree».Functions.«first_child».core.id
  let count := Extracted.«ir::body_tree».Functions.«child_count».core.id
  let subtree := Extracted.«ir::body_tree».Functions.«subtree_end».core.id
  let sibling := Extracted.«ir::body_tree».Functions.«next_sibling».core.id
  for (id, indices, expected) in [(first, [0], 1), (count, [0], 2), (sibling, [0, 1], 2),
      (sibling, [0, 2], -1), (subtree, [2], 4), (first, [2], 3), (sibling, [2, 3], -1),
      (first, [3], -1), (first, [-1], -1), (first, [4], -1)] do
    let .done result after := evalExpr 100 extractedProgram built
      (.call id (.value tree :: indices.map (fun index => .value (.signed .i32 index))))
      | throw (IO.userError "built-tree navigation trapped")
    unless result == .signed .i32 expected do throw (IO.userError "built-tree navigation returned the wrong child")
    for (index, endpoint) in (List.range 4).zip [4, 2, 4, 4] do
      match readRawSliceIndex extractedProgram after (.scalar (.signed .i32)) before.heap.borrowedAddress 4 index with
      | .ok value => unless value == .signed .i32 endpoint do throw (IO.userError "navigation changed an endpoint")
      | .error _ => throw (IO.userError "navigation lost the endpoint table") : IO Unit)

#print axioms leafLoopCompletes
#print axioms leafBuilderCompletes
#print axioms leafBuilderTraversal

end IRBuilderTests
