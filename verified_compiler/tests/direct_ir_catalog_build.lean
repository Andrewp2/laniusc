import verified_compiler.tests.direct_ir_catalog_loop
import verified_compiler.tests.direct_ir_validator

namespace IRCatalogBuildProof
open Lanius Lanius.Core Lanius.Memory Lanius.Semantics
open IRCatalogCopyProof IREventStoreProof IRBuilderProof IRBuilderCallProof
open IRBuilderNavigationProof IRValidatorProof

variable {original before after state : State} {input : Input original}
  {budget : Option Nat} {value : Value}

/-- Legitimate stage-entry facts, independent of all future execution/results. -/
structure Entry (input : Input original) (budget : Option Nat) : Prop where
  positive : 0 < input.count
  fits : input.count * 56 < 2 ^ 31
  pointerFits : input.memory + input.count * 56 < 2 ^ 64
  sourceFound : original.local? (source.argumentId 2) = some input.value
  sourceEvents : original.local? (source.bindingId 2) = some (.rawSlice eventType input.eventsAddress input.eventsLength)
  countFound : original.local? (source.argumentId 3) = some (.signed .i32 input.count)
  available : consumeBudget original.heap.remaining (input.count * 56) = some budget
  formed : original.CellsWellFormed
  unique : HeapBlockBasesUnique original.heap
  noViews : original.i32ArrayViews = []

/-- Select only the real row/count continuation, not a replacement program. -/
def catalogWrites : Stmt := match tail with
  | .letLocal _ _ _ (.sequence _ writes) => writes
  | _ => .skip

def guardedContinuation (continuation : Stmt) : Stmt := match tail with
  | .letLocal id type initial (.sequence guard _) =>
      .letLocal id type initial (.sequence guard continuation)
  | _ => .skip

theorem actualGuardedDecomposition : guardedContinuation catalogWrites = tail := by rfl
theorem actualStageDecomposition :
    «prefix» (guardedContinuation catalogWrites) = source.bindingStatement 5 := by
  rw [actualGuardedDecomposition, actualDecomposition]

private def validator := Extracted.«ir::body_tree».Functions.«valid».core
private def treeType := ((validator.parameters[0]?).getD (0, .unit)).2
private def guard : Stmt := match tail with
  | .letLocal _ _ _ (.sequence guard _) => guard
  | _ => .skip

theorem actualGuard : guard = .ifThenElse
    (.unary .logicalNot (.call validator.id [.local (source.bindingId 12)]))
    (.returnValue (some (.unary .negate (.value (.signed .i32 1))))) .skip := by rfl
theorem actualGuardedShape : guardedContinuation continuation =
    .letLocal (source.bindingId 12) treeType (source.bindingInitializer 12)
      (.sequence guard continuation) := by rfl

/-- Retain the proved allocator result as well as the original caller cells.
    Its cut witness comes from actual copying, never an initial hypothesis. -/
structure Memory (input : Input original) (budget : Option Nat) (value : Value) (state : State) : Prop where
  cells : FreshCellFrame original state
  callerCells : ∀ id, id ∈ callerIds → state.cellId? id = original.cellId? id
  allocation : ∃ copied, ∃ cut : CutState input budget copied,
    BuildPost cut.region copied.world value state

theorem Memory.reads (memory : Memory input budget value state) : HeapReads original.heap state.heap := by
  obtain ⟨_, cut, post⟩ := memory.allocation
  exact cut.reads.trans post.1
theorem Memory.world (memory : Memory input budget value state) :
    state.world = World.record (World.record original.world .alloc) .alloc := by
  obtain ⟨_, cut, post⟩ := memory.allocation
  exact post.2.1.trans (congrArg (fun world => World.record world .alloc) cut.world)
theorem Memory.noViews (memory : Memory input budget value state) : state.i32ArrayViews = [] := by
  obtain ⟨_, _, post⟩ := memory.allocation
  exact post.2.2.1
theorem Memory.unique (memory : Memory input budget value state) : HeapBlockBasesUnique state.heap := by
  obtain ⟨_, _, post⟩ := memory.allocation
  exact post.2.2.2.1
theorem Memory.below (memory : Memory input budget value state) : HeapBlocksBelowNext state.heap := by
  obtain ⟨_, _, post⟩ := memory.allocation
  exact post.2.2.2.2.1
theorem Memory.eventReads (memory : Memory input budget value state) (index : Nat) (inside : index < input.count) :
    readRawSliceIndex extractedProgram state eventType input.eventPointer input.count index =
      .ok (input.events index) := by
  obtain ⟨_, cut, post⟩ := memory.allocation
  exact post.1.rawSlice (cut.eventReads index inside)
theorem Memory.typeReads (memory : Memory input budget value state) (index : Nat) (inside : index < input.count) :
    readRawSliceIndex extractedProgram state referenceType input.typePointer input.count index =
      .ok (input.annotation index) := by
  obtain ⟨_, cut, post⟩ := memory.allocation
  exact post.1.rawSlice (cut.typeReads index inside)

private theorem postPure (post : BuildPost region world value before) (pure : PureFrame before after) :
    BuildPost region world value after := by
  simpa only [BuildPost, Stored, readRawSliceIndex, pure.heap, pure.world, pure.views] using post

theorem Memory.transPure (memory : Memory input budget value before) (pure : PureFrame before after) :
    Memory input budget value after := by
  obtain ⟨copied, cut, post⟩ := memory.allocation
  refine ⟨memory.cells.trans pure.cells, ?_, copied, cut, postPure post pure⟩
  intro id member
  simpa only [State.cellId?, pure.locals] using memory.callerCells id member
theorem Memory.bindLocal (memory : Memory input budget value before) (id : VarId) (bound : Value) :
    id ∉ callerIds → Memory input budget value (before.bindLocal id bound) := by
  intro excluded
  obtain ⟨copied, cut, post⟩ := memory.allocation
  refine ⟨memory.cells.trans (FreshCellFrame.bindLocal before id bound), ?_, copied, cut, post⟩
  intro caller member
  have different : caller ≠ id := fun equal => excluded (equal ▸ member)
  rw [State.bindLocal_cellId_of_ne _ _ _ (Ne.symm different)]
  exact memory.callerCells caller member
theorem Memory.restoreLocals (memory : Memory input budget value state) :
    Memory input budget value (restoreLocals original state) := by
  obtain ⟨copied, cut, post⟩ := memory.allocation
  exact ⟨memory.cells, fun _ _ => rfl, copied, cut, post⟩

/-- The same copied descriptors, now read from the post-build heap. -/
def Memory.region (memory : Memory input budget value state) : Region state := {
  count := input.count, capacity := input.count
  eventsAddress := input.eventPointer, eventsLength := input.count, events := input.events
  resultAddress := input.typePointer, resultLength := input.count, hasResultTypes := true
  kinds := input.kinds, arities := input.arities, rules := input.rules
  fits := input.fits, below := memory.below, reads := memory.eventReads
  classified := input.classified }

/-- Entry to the catalog-write continuation, before real lexical restoration. -/
structure Live (input : Input original) (budget : Option Nat) (state : State) where
  value : Value
  memory : Memory input budget value state
  tree : Ready memory.region state
  represented : value = tree.value
  found : state.local? (source.bindingId 12) = some value

theorem Memory.callerFound (memory : Memory input budget value state) {id : VarId} {prior : Value}
    (member : id ∈ callerIds)
    (found : original.local? id = some prior) : state.local? id = some prior :=
  memory.cells.localFoundAt (memory.callerCells id member) prior found

private theorem guardedFromBuild (input : Input original) (budget : Option Nat)
    (cut : CutState input budget copied) (formed : original.CellsWellFormed)
    (positive : 0 < input.count) (value : Value) (built : State)
    (buildRun : RunsExpr extractedProgram copied cut.region.call value built)
    (cells : FreshCellFrame copied built) (post : BuildPost cut.region copied.world value built)
    (continuation : Stmt) (Q : Completion → State → Prop)
    (reject : value = emptyTree → ∀ state, Memory input budget emptyTree state →
      Q (.returned (some (.signed .i32 (-1)))) (restoreLocals original state))
    (success : ∀ state, Live input budget state → ∃ completion after,
      RunsStmt extractedProgram state continuation completion after ∧ Q completion (restoreLocals original after)) :
    ∃ completion after, RunsStmt extractedProgram copied (guardedContinuation continuation)
      completion after ∧ Q completion (restoreLocals original after) := by
  have ownedFound := cut.owned
  have countFound := cut.countFound
  have initial : RunsExpr extractedProgram copied (source.bindingInitializer 12) value built := by
    apply RunsExpr.callArguments (values := [cut.region.value, .signed .i32 input.count])
    · core_arguments
    · exact buildRun
  have memory : Memory input budget value built := ⟨cut.cells.trans cells,
    fun id member => by simpa only [State.cellId?, buildRun.choose_spec.2] using cut.callerCells id member,
    copied, cut, post⟩
  have builtFormed := memory.cells.after_cellsWellFormed formed
  let ready := built.bindLocal (source.bindingId 12) value
  have readyMemory : Memory input budget value ready := memory.bindLocal _ _ (by decide +kernel)
  have readyFormed := readyMemory.cells.after_cellsWellFormed formed
  have found : ready.local? (source.bindingId 12) = some value := by core_local
  rcases BuildPost.ready post with rejected | ⟨tree, represented⟩
  · subst value
    obtain ⟨checked, validation, pure⟩ : ∃ after,
        RunsExpr extractedProgram ready (validCall emptyTree) (.boolean false) after ∧
        PureFrame ready after := by core_pure_expr
    have test : RunsExpr extractedProgram ready
        (.unary .logicalNot (.call validator.id [.local (source.bindingId 12)])) (.boolean true) checked := by core_run
    have body : RunsStmt extractedProgram ready (.sequence guard continuation)
        (.returned (some (.signed .i32 (-1)))) checked := by rw [actualGuard]; core_stmt
    refine ⟨.returned (some (.signed .i32 (-1))), restoreLocals built checked, ?_, ?_⟩
    · rw [actualGuardedShape]; exact RunsStmt.letLocal initial body
    · simpa only [restoreLocals] using reject rfl checked (readyMemory.transPure pure)
  · obtain ⟨checked, validation, pure⟩ :=
      (tree.reheap (after := ready) rfl).valid positive readyFormed
    have validationValue : RunsExpr extractedProgram ready (validCall value) (.boolean true) checked :=
      represented ▸ validation
    have test : RunsExpr extractedProgram ready
        (.unary .logicalNot (.call validator.id [.local (source.bindingId 12)])) (.boolean false) checked := by core_run
    let checkedMemory := readyMemory.transPure pure
    let live : Live input budget checked := {
      value, memory := checkedMemory
      tree := {
        address := tree.address, ends := tree.ends, suffix := tree.suffix, root := tree.root
        eventReads := checkedMemory.eventReads
        contents := (tree.reheap (after := checked) pure.heap).contents }
      represented := represented
      found := pure.cells.localFound pure.locals _ _ found }
    obtain ⟨completion, after, run, done⟩ := success checked live
    have body : RunsStmt extractedProgram ready (.sequence guard continuation) completion after := by
      rw [actualGuard]
      exact RunsStmt.sequenceNext (RunsStmt.ifThenElseFalse test (RunsStmt.skip _ _)) run
    refine ⟨completion, restoreLocals built after, ?_, ?_⟩
    · rw [actualGuardedShape]; exact RunsStmt.letLocal initial body
    · simpa only [restoreLocals] using done

/-- Allocation, exact copying and the actual guarded continuation compose.
    Substituting catalogWrites reconnects this theorem to real binding 5. -/
theorem actualAllocationCopyBuild (entry : Entry input budget)
    (continuation : Stmt) (Q : Completion → State → Prop)
    (reject : ∀ state, Memory input budget emptyTree state →
      Q (.returned (some (.signed .i32 (-1)))) (restoreLocals original state))
    (success : ∀ state, Live input budget state → ∃ completion after,
      RunsStmt extractedProgram state continuation completion after ∧ Q completion (restoreLocals original after)) :
    ∃ completion after, RunsStmt extractedProgram original («prefix» (guardedContinuation continuation))
      completion after ∧ Q completion after := by
  apply actualAllocationCopy input budget (guardedContinuation continuation) entry.positive entry.fits entry.pointerFits
    entry.sourceFound entry.sourceEvents entry.countFound entry.available entry.formed entry.unique entry.noViews Q
  intro copied cut
  obtain ⟨value, built, run, cells, post⟩ := actualBuild cut.region entry.positive
    (by change (input.count : Int) ≤ input.count; omega)
    (by have fits := entry.fits; change input.count ≤ 536870911; omega)
    (cut.cells.after_cellsWellFormed entry.formed) cut.writes.unique (cut.views.trans entry.noViews)
  exact guardedFromBuild input budget cut entry.formed entry.positive value built run cells post continuation Q
    (fun _ => reject) success

/-- The exact real binding-5 statement, with only its following catalog
    writes supplied as a separately proved consumer of the derived Live tree. -/
theorem actualSourceContinuation (entry : Entry input budget) (Q : Completion → State → Prop)
    (reject : ∀ state, Memory input budget emptyTree state →
      Q (.returned (some (.signed .i32 (-1)))) (restoreLocals original state))
    (success : ∀ state, Live input budget state → ∃ completion after,
      RunsStmt extractedProgram state catalogWrites completion after ∧ Q completion (restoreLocals original after)) :
    ∃ completion after, RunsStmt extractedProgram original (source.bindingStatement 5)
      completion after ∧ Q completion after := by
  simpa only [actualStageDecomposition] using actualAllocationCopyBuild entry catalogWrites Q reject success

def StagePost (input : Input original) (budget : Option Nat) (completion : Completion) (after : State) : Prop :=
  ∃ value, Memory input budget value after ∧ after.locals = original.locals ∧
    ((completion = .returned (some (.signed .i32 (-1))) ∧ value = emptyTree) ∨
      (completion = .next ∧ ∃ liveState, ∃ live : Live input budget liveState,
        value = live.value ∧ after = restoreLocals original liveState))

/-- A closed, non-vacuous stage theorem: rejection is -1; success supplies the
    live Ready tree while the observable poststate has restored caller locals. -/
theorem actualStage (entry : Entry input budget) :
    ∃ completion after, RunsStmt extractedProgram original («prefix» (guardedContinuation .skip)) completion after ∧
      StagePost input budget completion after := by
  apply actualAllocationCopyBuild entry .skip (StagePost input budget)
  · intro state memory
    exact ⟨emptyTree, memory.restoreLocals, rfl, Or.inl ⟨rfl, rfl⟩⟩
  · intro state live
    exact ⟨.next, state, RunsStmt.skip _ _, live.value, live.memory.restoreLocals,
      rfl, Or.inr ⟨rfl, state, live, rfl, rfl⟩⟩

/-- Independent canonical shape and remaining resources force the success
    branch. Neither a successful call nor validator acceptance is a premise. -/
theorem actualSuccessStage (entry : Entry input budget) {canonical : Nat → Int}
    (shape : input.toRegion.toSource.Suffix canonical 0) (root : canonical 0 = (input.count : Int))
    (second : consumeBudget budget (input.count * 4) ≠ none) :
    ∃ after, RunsStmt extractedProgram original («prefix» (guardedContinuation .skip)) .next after ∧
      StagePost input budget .next after := by
  let Q := fun completion after => completion = .next ∧ StagePost input budget completion after
  obtain ⟨completion, after, run, next, result⟩ := actualAllocationCopy input budget
    (guardedContinuation .skip) entry.positive entry.fits entry.pointerFits entry.sourceFound entry.sourceEvents
    entry.countFound entry.available entry.formed entry.unique entry.noViews Q (by
      intro copied cut
      have remaining : copied.heap.remaining = budget := cut.writes.budget
      have resource : consumeBudget copied.heap.remaining (cut.region.count * 4) ≠ none := by
        simpa only [remaining, CutState.region] using second
      obtain ⟨built, tree, run, cells, _, _, post⟩ := actualCompleteCall cut.region shape root entry.positive
        (by change (input.count : Int) ≤ input.count; omega)
        (by have fits := entry.fits; change input.count ≤ 536870911; omega) resource
        (cut.cells.after_cellsWellFormed entry.formed) cut.writes.unique (cut.views.trans entry.noViews)
      apply guardedFromBuild input budget cut entry.formed entry.positive tree.value built run cells post .skip Q
      · intro empty
        have counts := congrArg (fun value => match value with
          | .structure _ fields => fields[4]?
          | _ => none) empty
        have zero : input.count = 0 := by
          simpa [Ready.value, Region.tree, emptyTree, CutState.region] using counts
        have positive := entry.positive
        omega
      · intro state live
        exact ⟨.next, state, RunsStmt.skip _ _, rfl, live.value, live.memory.restoreLocals,
          rfl, Or.inr ⟨rfl, state, live, rfl, rfl⟩⟩)
  subst completion
  exact ⟨after, run, result⟩

#print axioms actualStageDecomposition
#print axioms actualAllocationCopyBuild
#print axioms actualSourceContinuation
#print axioms actualStage
#print axioms actualSuccessStage
end IRCatalogBuildProof
