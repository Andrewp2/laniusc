import Lanius.Std.VecPrograms
import Lanius.Std.VecSpec

/-! The specs at the two hand-transcribed programs: the `i32` layout and the
nominal (`Pair`, two words) layout both meet `ElemKind`. -/

namespace Lanius.Std

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory

theorem pairKind : ElemKind vecPairProgram (.structure 2) 16 :=
  ElemKind.structure (w := 2) rfl (by decide) (by decide)

theorem vecI32_getOr {caller : State} (formed : caller.CellsWellFormed) {v : Value} {xs : List Value}
    (rep : VecRep vecI32Program i32Ty 4 0 caller.heap v xs) (index : Int) (fallback : Value) :
    ∃ after, RunsExpr vecI32Program caller (.call 7 ([v, .signed .i32 index, fallback].map Expr.value))
      (if 0 ≤ index then (xs[index.toNat]?).getD fallback else fallback) after ∧ PureFrame caller after :=
  getOr_spec vecI32Program_instance ElemKind.i32 formed rep index fallback

theorem vecPair_trySet {caller : State} (formed : caller.CellsWellFormed) {v : Value} {xs : List Value}
    (rep : VecRep vecPairProgram (.structure 2) 16 0 caller.heap v xs) {i : Nat} (inside : i < xs.length)
    {x : Value} (store : ElemStore vecPairProgram (.structure 2) 16 x)
    (noViews : caller.i32ArrayViews = []) (unique : HeapBlockBasesUnique caller.heap) :
    ∃ after, RunsExpr vecPairProgram caller (.call 8 ([v, .signed .i32 i, x].map Expr.value)) v after ∧
      FreshCellFrame caller after ∧ VecRep vecPairProgram (.structure 2) 16 0 after.heap v (xs.set i x) := by
  obtain ⟨after, run, cells, _, _, rep', _⟩ :=
    trySet_spec vecPairProgram_instance pairKind formed rep inside store noViews unique
  exact ⟨after, run, cells, rep'⟩

#print axioms vecI32_getOr
#print axioms vecPair_trySet

end Lanius.Std
