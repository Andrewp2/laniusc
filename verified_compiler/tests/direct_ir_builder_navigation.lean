import verified_compiler.tests.direct_ir_builder_call
import verified_compiler.tests.direct_ir_navigation
import Lanius.Semantics.ReadOnlyMemory

namespace IRBuilderNavigationProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRShapeProof IRChildrenProof IRBuilderProof
open IRBuilderCallProof IRNavigationProof

private def childCountSource := Extracted.«ir::body_tree».Functions.«child_count».core
private def firstChildSource := Extracted.«ir::body_tree».Functions.«first_child».core
private def eventType := ((Extracted.«ir::body_tree».Functions.«shape».core.parameters[0]?).getD (0, .unit)).2

theorem nodeBounds (input : Source original) (node : input.Node ends index) (inside : index < input.count) :
    (index : Int) < ends index ∧ ends index ≤ input.count := by
  obtain ⟨_, _, _, endpoint, value, chain⟩ := node
  have forward := chain.advances
  have bound := chain.bounded (by omega)
  omega

/-- A successful builder's existing postcondition, packaged for its consumers.
    This is a proof view of one physical tree, not another emitted tree. -/
structure Ready (region : Region original) (state : State) where
  address : Nat
  ends : Nat → Int
  suffix : region.toSource.Suffix ends 0
  root : ends 0 = (region.count : Int)
  eventReads : ∀ index, index < region.count →
    readRawSliceIndex extractedProgram state eventType region.eventsAddress region.eventsLength index =
      .ok (region.events index)
  contents : ∀ index, index < region.count →
    readRawSliceIndex extractedProgram state (.scalar (.signed .i32)) address region.count index =
      .ok (.signed .i32 (ends index))

def Ready.value (tree : Ready region state) : Value := region.tree tree.address

def Ready.reheap (tree : Ready region before) (heap : after.heap = before.heap) : Ready region after := {
  address := tree.address, ends := tree.ends, suffix := tree.suffix, root := tree.root
  eventReads := by
    intro index inside
    simpa only [readRawSliceIndex, heap] using tree.eventReads index inside
  contents := by
    intro index inside
    simpa only [readRawSliceIndex, heap] using tree.contents index inside }

/-- Transport only the tree's reads, not unrelated mutable output storage. -/
def Ready.ofReads (tree : Ready region before) (reads : HeapReads before.heap after.heap) : Ready region after := {
  address := tree.address, ends := tree.ends, suffix := tree.suffix, root := tree.root
  eventReads := fun index inside => reads.rawSlice (tree.eventReads index inside)
  contents := fun index inside => reads.rawSlice (tree.contents index inside) }

/-- Printing only changes the separated output range. Its borrowed string
    storage does not invalidate the already-built IR. -/
def Ready.afterOutput (tree : Ready region reference)
    {before after : State} {address capacity destination : Nat} {bytes : List UInt8}
    (separate : ReadOnlyMemory reference.heap before.heap address capacity)
    (effect : OutputEffect before.heap after.heap destination bytes)
    (lower : address ≤ destination) (upper : destination + bytes.length ≤ address + capacity) :
    Ready region after := tree.ofReads (separate.afterOutput effect lower upper).reads

def Ready.table (tree : Ready region state) : EndTable state := {
  address := tree.address, count := region.count, ends := tree.ends, fits := region.fits
  bounds := by
    intro index inside
    have bound := nodeBounds region.toSource (tree.suffix index (Nat.zero_le _) inside) inside
    exact ⟨by omega, bound.2⟩
  contents := tree.contents }

/-- Consume the proved builder result without rechecking, copying, or decoding
    its endpoints. Allocation and malformed-input failures remain explicit. -/
theorem BuildPost.ready (post : BuildPost region world value after) :
    value = emptyTree ∨ ∃ tree : Ready region after, value = tree.value := by
  obtain ⟨oldReads, _, _, _, _, failed | ⟨⟨ends, structural, _, contents⟩, _⟩⟩ := post
  · exact Or.inl failed.1
  · rcases structural with ⟨empty, _⟩ | ⟨rfl, suffix, root⟩
    · exact Or.inl empty
    · exact Or.inr ⟨⟨_, ends, suffix, root,
        fun index inside => oldReads.rawSlice (region.reads index inside), contents⟩, rfl⟩

/-- The actual complete call establishes the consumer view; success is not
    a premise, and rejection is not silently discarded. -/
theorem actualReadyCall (region : Region original) (formed : original.CellsWellFormed)
    (unique : HeapBlockBasesUnique original.heap) (views : original.i32ArrayViews = []) :
    ∃ value after, RunsExpr extractedProgram original region.call value after ∧ FreshCellFrame original after ∧
      (value = emptyTree ∨ ∃ tree : Ready region after, value = tree.value) := by
  obtain ⟨value, after, run, cells, rejected | post⟩ := actualCall region formed unique views
  · exact ⟨value, after, run, cells, Or.inl rejected.1⟩
  · exact ⟨value, after, run, cells, BuildPost.ready post⟩

/-- A well-shaped native input produces the exact endpoint table. Bounds and
    allocation budget are input/resource facts; no successful call is assumed. -/
theorem actualCompleteCall (region : Region original) {canonical : Nat → Int}
    (valid : region.toSource.Suffix canonical 0) (root : canonical 0 = (region.count : Int))
    (positive : 0 < region.count) (capacity : (region.count : Int) ≤ region.capacity)
    (bounded : region.count ≤ 536870911)
    (budget : consumeBudget original.heap.remaining (region.count * 4) ≠ none)
    (formed : original.CellsWellFormed) (unique : HeapBlockBasesUnique original.heap)
    (views : original.i32ArrayViews = []) :
    ∃ after, ∃ tree : Ready region after,
      RunsExpr extractedProgram original region.call tree.value after ∧ FreshCellFrame original after ∧
      tree.address = original.heap.borrowedAddress ∧
      (∀ index, index < region.count → tree.ends index = canonical index) ∧
      BuildPost region original.world tree.value after := by
  obtain ⟨value, after, run, cells, post⟩ :=
    actualBuild region positive capacity bounded formed unique views
  have reads := post.1
  rcases post.2.2.2.2.2 with ⟨_, failed, _⟩ | ⟨⟨ends, structural, _, contents⟩, _⟩
  · cases consumed : consumeBudget original.heap.remaining (region.count * 4) with
    | none => exact False.elim (budget consumed)
    | some rest =>
        simp only [IRAllocationProof.allocation, consumed] at failed
        exact False.elim ((Nat.ne_of_gt original.heap.borrowedAddress_pos) failed)
  · rcases structural with ⟨_, bad⟩ | ⟨rfl, suffix, single⟩
    · rcases bad with ⟨index, inside, later, bad⟩ | ⟨suffix, notSingle⟩
      · exact False.elim (region.toSource.noBadNode valid later inside bad)
      · exact False.elim (notSingle ((region.toSource.equalEndpoints suffix valid 0
          (Nat.zero_le _) positive).trans root))
    · let tree : Ready region after := {
        address := original.heap.borrowedAddress, ends, suffix, root := single,
        eventReads := fun index inside => reads.rawSlice (region.reads index inside), contents }
      exact ⟨after, tree, run, cells, rfl,
        (fun index inside => region.toSource.equalEndpoints suffix valid index (Nat.zero_le _) inside), post⟩

def Ready.childCountCall (tree : Ready region state) (index : Int) : Expr :=
  .call childCountSource.id [.value tree.value, .value (.signed .i32 index)]
def Ready.firstChildCall (tree : Ready region state) (index : Int) : Expr :=
  .call firstChildSource.id [.value tree.value, .value (.signed .i32 index)]

theorem Ready.childCount (tree : Ready region state) (inside : index < region.count)
    (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (tree.childCountCall index)
      (.signed .i32 (region.arities index)) after ∧ PureFrame state after := by
  have classified := region.classified index inside
  have read := tree.eventReads index inside
  core_call_pure childCountSource as callee
  core_pure

theorem Ready.childCountRejects (tree : Ready region state)
    (bad : index < 0 ∨ (region.count : Int) ≤ index) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (tree.childCountCall index)
      (.signed .i32 (-1)) after ∧ PureFrame state after := by
  core_call_pure childCountSource as callee
  core_pure

def Ready.firstIndex (_tree : Ready region state) (index : Nat) : Int :=
  if region.arities index ≤ 0 then -1 else index + 1

theorem Ready.firstChild (tree : Ready region state) (inside : index < region.count)
    (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (tree.firstChildCall index)
      (.signed .i32 (tree.firstIndex index)) after ∧ PureFrame state after := by
  have addition := eval_i32_addNat extractedProgram.target index 1 (by have fits := region.fits; omega)
  unfold Ready.firstIndex
  split
  all_goals
    core_call_pure firstChildSource as callee
    have countRun := (tree.reheap (after := callee) rfl).childCount inside (by core_formed)
    core_pure

theorem Ready.firstChildRejects (tree : Ready region state)
    (bad : index < 0 ∨ (region.count : Int) ≤ index) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (tree.firstChildCall index)
      (.signed .i32 (-1)) after ∧ PureFrame state after := by
  core_call_pure firstChildSource as callee
  have countRun := (tree.reheap (after := callee) rfl).childCountRejects bad (by core_formed)
  core_pure

theorem Ready.subtree (tree : Ready region state) (inside : index < region.count)
    (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (subtreeCall tree.value index)
      (.signed .i32 (tree.ends index)) after ∧ PureFrame state after := by
  exact subtree_reads tree.table index inside formed

theorem Ready.nextSibling (tree : Ready region state) (ordered : parent < current)
    (inside : current < region.count) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (siblingCall tree.value parent current)
      (.signed .i32 (siblingResult tree.ends parent current)) after ∧ PureFrame state after := by
  exact sibling_reads tree.table parent current ordered inside formed

def Ready.Children (tree : Ready region state) (parent ordinal remaining cursor : Nat) : Prop :=
  ChildChain region.count region.kinds (region.rules parent) (region.arities parent).toNat
    tree.ends remaining ordinal cursor (tree.ends parent).toNat

theorem Ready.childrenStart (tree : Ready region state) (inside : parent < region.count) :
    tree.Children parent 0 (region.arities parent).toNat (parent + 1) := by
  obtain ⟨_, _, _, endpoint, value, chain⟩ := tree.suffix parent (Nat.zero_le _) inside
  simpa only [Ready.Children, value, Int.toNat_natCast] using chain

private theorem chainStrict (chain : ChildChain count kinds rule arity ends remaining child cursor endpoint)
    (positive : 0 < remaining) : cursor < endpoint := by
  cases chain with
  | nil => omega
  | cons _ _ forward _ rest => have advances := rest.advances; omega

private theorem chainStep (chain : ChildChain count kinds rule arity ends (remaining + 1) child cursor endpoint)
    (parentEnd : ends parent = (endpoint : Int)) :
    siblingResult ends parent cursor = if remaining = 0 then -1 else ends cursor := by
  cases chain with
  | cons _ _ forward _ rest =>
      by_cases done : remaining = 0
      · subst remaining
        cases rest
        have last : ¬((cursor : Int) < ends cursor ∧ ends cursor < ends parent) := by omega
        simp only [siblingResult, if_neg last, ↓reduceIte]
      · have next := chainStrict rest (by omega)
        have beforeEnd : ends cursor < ends parent := by omega
        have advance : (cursor : Int) < ends cursor ∧ ends cursor < ends parent := ⟨forward, beforeEnd⟩
        simp only [siblingResult, if_neg done, if_pos advance]

/-- Exactly the next child, or -1 after the last child. The chain came from
    the builder, not from a second validator or a successful navigation run. -/
theorem Ready.nextChild (tree : Ready region state) (ordered : parent < current)
    (children : tree.Children parent ordinal (remaining + 1) current) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (siblingCall tree.value parent current)
      (.signed .i32 (if remaining = 0 then -1 else tree.ends current)) after ∧ PureFrame state after := by
  have inside : current < region.count := by cases children with | cons bound _ _ _ _ => exact bound
  have bound := nodeBounds region.toSource (tree.suffix parent (Nat.zero_le _) (by omega)) (by omega)
  have step := chainStep children (show tree.ends parent = ((tree.ends parent).toNat : Int) by omega)
  rw [← step]
  exact tree.nextSibling ordered inside formed

#print axioms BuildPost.ready
#print axioms actualReadyCall
#print axioms actualCompleteCall
#print axioms Ready.childCount
#print axioms Ready.firstChild
#print axioms Ready.firstChildRejects
#print axioms Ready.subtree
#print axioms Ready.nextSibling
#print axioms Ready.childrenStart
#print axioms Ready.nextChild

end IRBuilderNavigationProof
