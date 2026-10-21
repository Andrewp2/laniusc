import verified_compiler.tests.direct_ir_lowered_tree
import verified_compiler.tests.direct_surface_expression_tree

namespace NegativeExtractionProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics Lanius.Extraction
open IRNegativeLoweringProof IRLoweredTreeProof IRBuilderNavigationProof
open SurfaceBooleanProof SurfaceDispatchProof SurfaceExpressionTreeProof

def expression (number : Nat) : Expression := .unary .negate (.integer number)
def spelling (number : Nat) : List UInt8 := (expression number).output

/-- The printer consumes the actual builder result. Its integer payload and
    unary structure follow from lowering's stores, not a new typing witness. -/
theorem actualWriter {before lowered built : State} (storage : Storage before) (number : Nat)
    (start : storage.head.position = 0) (written : effect storage number before.heap lowered.heap)
    (below : HeapBlocksBelowNext before.heap)
    (tree : Ready (region storage number start written below) built) (fits : number < 2 ^ 31) :
    Writer Context.expressionCall built.heap tree.value 0 (spelling number) := by
  have represented : (Int32.ofNat number).toBitVec.toInt = (number : Int) := by
    change (Int32.ofNat number).toInt = number
    rw [Int32.toInt_ofNat']
    change (number : Int).bmod 4294967296 = number
    apply Int.bmod_eq_of_le <;> omega
  apply SurfaceExpressionTreeProof.actualTreeWriter
    (tree.reheap (after := { heap := built.heap }) rfl) (expression number)
  refine ⟨by change (0 : Nat) < 2; decide, rfl,
    by change (1 : Nat) < 2; decide, ?_, ⟨by omega, by omega⟩, Or.inl (Int.natCast_nonneg _)⟩
  change IREventStoreProof.integer (Int32.ofNat number).toBitVec = SurfaceIntegerProof.integerEvent number
  simp only [IREventStoreProof.integer, SurfaceIntegerProof.integerEvent, represented]

/-- Source digits determine the exact Lean text through actual lowering,
    actual endpoint construction and the proved recursive printer. The writer
    contract quantifies over its ordinary protected input/output environment. -/
theorem actualNegativeExtraction (input : IRIntegerLoweringProof.Input before) (unused : List Value) (number : Nat)
    (decoded : IRDecimalLoopProof.scan input.bytes input.length 0 .empty = .number number)
    (storage : Storage before) (start : storage.head.position = 0)
    (formed : before.CellsWellFormed) (below : HeapBlocksBelowNext before.heap)
    (unique : HeapBlockBasesUnique before.heap) (noViews : before.i32ArrayViews = [])
    (budget : consumeBudget before.heap.remaining 8 ≠ none) :
    ∃ lowered, ∃ written : effect storage number before.heap lowered.heap, ∃ built,
      ∃ tree : Ready (region storage number start written below) built,
        RunsExpr extractedProgram before (call input unused storage.head.value 0) (.signed .i32 2) lowered ∧
        RunsExpr extractedProgram lowered (region storage number start written below).call tree.value built ∧
        FreshCellFrame before built ∧ Writer Context.expressionCall built.heap tree.value 0 (spelling number) := by
  obtain ⟨lowered, written, built, tree, lower, build, cells, _, _⟩ :=
    actualNegativeTree input unused number decoded storage start formed below unique noViews budget
  have fits : number < 2 ^ 31 := by
    have bound := IRDecimalLoopProof.scan_bounded input.bytes input.length 0 .empty trivial
    rw [decoded] at bound
    exact bound
  exact ⟨lowered, written, built, tree, lower, build, cells, actualWriter storage number start written below tree fits⟩

#print axioms actualNegativeExtraction

end NegativeExtractionProof
