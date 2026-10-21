import SelfCore
import Lanius.Core.Bindings
import Lanius.Semantics.CallProof
import Lanius.Semantics.CallRun
import Lanius.Semantics.PureProof
import Lanius.Extraction.OutputPacking.Byte

namespace IRNavigationProof

open Lanius Lanius.Core Lanius.Semantics Lanius.Extraction.OutputPacking

private def subtree := Extracted.«ir::body_tree».Functions.«subtree_end».core
private def sibling := Extracted.«ir::body_tree».Functions.«next_sibling».core
private def siblingExpressions : Expr × Expr × Expr := match sibling.body with
  | some (.sequence _ (.letLocal _ _ _ (.letLocal _ _ candidate
      (.sequence (.ifThenElse guard _ _) (.returnValue (some result)))))) => (candidate, guard, result)
  | _ => (.value .unit, .value .unit, .value .unit)
private def treeType : TypeId :=
  match ((subtree.parameters[0]?).map (fun entry => entry.2) : Option Core.Ty) with
  | some (Core.Ty.structure id) => id
  | _ => 0

/-- A logical view of the existing IR end-offset slice, not another syntax or
    typing tree. The builder supplies these reads directly. -/
structure EndTable (state : State) where
  address : Nat
  count : Nat
  ends : Nat → Int
  fits : count < 2 ^ 31
  bounds : ∀ index, index < count → 0 ≤ ends index ∧ ends index ≤ count
  contents : ∀ index, index < count →
    readRawSliceIndex extractedProgram state (.scalar (.signed .i32)) address count index =
      .ok (.signed .i32 (ends index))

def EndTable.value (table : EndTable state) (events annotations : Value) (hasAnnotations : Bool) : Value :=
  .structure treeType [events, annotations, .boolean hasAnnotations,
    .rawSlice (.scalar (.signed .i32)) table.address table.count, .signed .i32 table.count]

def subtreeCall (tree : Value) (index : Int) : Expr :=
  .call subtree.id ([tree, .signed .i32 index].map Expr.value)
def siblingCall (tree : Value) (parent current : Int) : Expr :=
  .call sibling.id ([tree, .signed .i32 parent, .signed .i32 current].map Expr.value)

/-- Bounds rejection reads no backing storage, even for an invalid descriptor. -/
theorem subtree_rejects (tree : Value) (count index : Int)
    (shape : tree = .structure treeType [events, annotations, .boolean hasAnnotations, storage, .signed .i32 count])
    (bad : index < 0 ∨ count ≤ index) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (subtreeCall tree index) (.signed .i32 (-1)) after ∧
      PureFrame state after := by
  subst tree
  core_call subtree
  core_stmt

theorem subtree_reads (table : EndTable state) (index : Nat) (inside : index < table.count)
    (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (subtreeCall (table.value events annotations hasAnnotations) index)
      (.signed .i32 (table.ends index)) after ∧ PureFrame state after := by
  have read := table.contents index inside
  core_call_pure subtree as callee
  core_pure

def siblingResult (ends : Nat → Int) (parent current : Nat) : Int :=
  if (current : Int) < ends current ∧ ends current < ends parent
  then ends current else -1

theorem sibling_rejects (tree : Value) (count parent current : Int)
    (shape : tree = .structure treeType [events, annotations, .boolean hasAnnotations, storage, .signed .i32 count])
    (bad : parent < 0 ∨ count ≤ parent ∨ current ≤ parent ∨ count ≤ current) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (siblingCall tree parent current) (.signed .i32 (-1)) after ∧
      PureFrame state after := by
  subst tree
  core_call sibling
  core_stmt

theorem sibling_reads (table : EndTable state) (parent current : Nat)
    (ordered : parent < current) (inside : current < table.count) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state (siblingCall (table.value events annotations hasAnnotations) parent current)
      (.signed .i32 (siblingResult table.ends parent current)) after ∧ PureFrame state after := by
  -- Fail before branch search if the implementation's cursor step changed.
  -- This check proves nothing; the actual call/body proof still follows.
  guard_expr siblingExpressions =~ (
    Expr.index (.local (sibling.bindingId 0)) (.local (sibling.argumentId 2)),
    Expr.binary .logicalOr
      (.binary .lessEqual (.local (sibling.bindingId 1)) (.local (sibling.argumentId 2)))
      (.binary .greaterEqual (.local (sibling.bindingId 1))
        (.index (.local (sibling.bindingId 0)) (.local (sibling.argumentId 1)))),
    Expr.local (sibling.bindingId 1))
  have currentRead := table.contents current inside
  have parentRead := table.contents parent (Nat.lt_trans ordered inside)
  core_call_pure sibling as callee
  unfold siblingResult
  split <;> core_pure

/-- A successful sibling is a strict subtree step. The count-minus-index
    measure decreases, so this API can support both recursive emitters. -/
theorem sibling_progress (table : EndTable state) (ordered : parent < current) (inside : current < table.count)
    (success : siblingResult table.ends parent current ≠ -1) :
    ∃ next : Nat, siblingResult table.ends parent current = next ∧ current < next ∧
      (next : Int) < table.ends parent ∧ next < table.count ∧
      table.count - next < table.count - current := by
  unfold siblingResult at success ⊢
  split <;> rename_i advance
  · have bounds := table.bounds parent (Nat.lt_trans ordered inside)
    exact ⟨(table.ends current).toNat, by omega, by omega, by omega, by omega, by omega⟩
  · simp only [if_neg advance, ne_self_iff_false] at success

#print axioms subtree_rejects
#print axioms subtree_reads
#print axioms sibling_rejects
#print axioms sibling_reads
#print axioms sibling_progress

-- A real packed endpoint table for `return 2 + 3 * 4`: [6, 6, 3, 6, 5, 6].
-- Navigation never needs to touch the separate event/annotation storage.
private def sampleEnds : List (BitVec 32) := [6, 6, 3, 6, 5, 6]
private def sample : State :=
  ({ heap := {
      blocks := [{
        base := 16
        size := 24
        alignment := 4
        bytes := sampleEnds.flatMap (fun word => i32Bytes word.toInt) }]
      nextAddress := 40 } } : State).bindLocal
    (sibling.argumentId 0) (.signed .i32 91)
private def sampleTable : EndTable sample := {
  address := 16
  count := 6
  ends := fun index => (sampleEnds[index]?.getD 0).toInt
  fits := by decide
  bounds := by
    intro index inside
    have cases : index = 0 ∨ index = 1 ∨ index = 2 ∨ index = 3 ∨ index = 4 ∨ index = 5 := by
      change index < 6 at inside
      omega
    rcases cases with rfl | rfl | rfl | rfl | rfl | rfl <;> decide
  contents := by
    intro index inside
    have bytes : sample.heap.loadBytes (16 + index * 4) 4 =
        .ok (i32Bytes (sampleEnds[index]?.getD 0).toInt) := by
      have cases : index = 0 ∨ index = 1 ∨ index = 2 ∨ index = 3 ∨ index = 4 ∨ index = 5 := by omega
      rcases cases with rfl | rfl | rfl | rfl | rfl | rfl <;> rfl
    exact readRawSliceIndex_i32Bytes extractedProgram sample inside bytes }

example : ∃ after, RunsExpr extractedProgram sample
    (siblingCall (sampleTable.value .unit .unit false) 1 2) (.signed .i32 3) after ∧
    after.heap = sample.heap ∧ after.local? (sibling.argumentId 0) = some (.signed .i32 91) := by
  obtain ⟨after, run, frame⟩ := sibling_reads sampleTable 1 2 (by decide) (by decide)
    (by simp [sample, State.CellsWellFormed, State.bindLocal, State.bindCell])
  exact ⟨after, run, frame.heap, frame.localFound (by
    apply State.bindLocal_local?
    simp [State.CellsWellFormed])⟩

example : ∃ after, RunsExpr extractedProgram sample
    (siblingCall (sampleTable.value .unit .unit false) 1 3) (.signed .i32 (-1)) after ∧ PureFrame sample after :=
  sibling_reads sampleTable 1 3 (by decide) (by decide)
    (by simp [sample, State.CellsWellFormed, State.bindLocal, State.bindCell])

example (parent current : Int) : ∃ after, RunsExpr extractedProgram {}
    (siblingCall (.structure treeType [.unit, .unit, .boolean false,
      .rawSlice (.scalar (.signed .i32)) 0 0, .signed .i32 0]) parent current)
    (.signed .i32 (-1)) after ∧ PureFrame {} after :=
  sibling_rejects _ 0 _ _ rfl (by omega) (by simp [State.CellsWellFormed])

end IRNavigationProof
