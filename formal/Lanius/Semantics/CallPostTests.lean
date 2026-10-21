import Lanius.Semantics.CallRun
import Lanius.Semantics.RawSlice

namespace Lanius.Semantics.CallPostTests

open Lanius Lanius.Core Lanius.Memory

private def before : State := { heap := { blocks := [
  { base := 4, size := 4, alignment := 4, bytes := [0, 0, 0, 0], owned := true }], nextAddress := 8 } }
private def borrowed : State := { before with heap := { before.heap with blocks := [
  { base := 4, size := 4, alignment := 4, bytes := [0, 0, 0, 0], owned := false }] } }
private def pointer : Value := .rawSlice (.scalar (.signed .i32)) 4 1
private def initializer : Expr := .i32SliceFromRawParts (.value (.pointer 4)) (.value (.signed .i32 1))
private def declaration : Function := {
  id := 7, parameters := [], returnType := .slice (.scalar (.signed .i32))
  body := some (.letLocal 17 (.slice (.scalar (.signed .i32))) initializer (.returnValue (some (.local 17)))) }
private def program : Program := { functions := [declaration] }

-- The initializer changes ownership in the heap. A pure-call rule would be
-- wrong; effectful composition must retain that change and restore scope.
theorem retainsBorrow : ∃ value after,
    RunsExpr program before (.call 7 []) value after ∧ FreshCellFrame before after ∧
    value = pointer ∧ after.heap = borrowed.heap := by
  apply RunsExpr.callPost (function := declaration) (values := []) (bindings := []) rfl rfl rfl
  · have construct : mapRawI32Slice before 4 1 = .done pointer borrowed :=
      mapRawI32Slice_of_block (state := before) (address := 4) 1 (by decide) rfl rfl rfl rfl
    have initial := RunsExpr.rawSliceFromParts (program := program)
      (RunsExpr.ofStable StableExpr.value rfl) (RunsExpr.ofStable StableExpr.value rfl) construct rfl
    apply RunsStmt.letLocalPost (ready := borrowed) initial
      (show FreshCellFrame before borrowed from ⟨[], by simp [borrowed], Nat.le_refl _, by simp⟩)
    · refine ⟨pointer, borrowed.bindLocal 17 pointer, RunsStmt.returnValue ?_,
        ⟨[], by simp, Nat.le_refl _, by simp⟩, rfl, rfl⟩
      exact RunsExpr.ofStable (StableExpr.local (by rfl)) rfl
    · intro value completed result; exact result
  · intro value completed result; exact result

#print axioms retainsBorrow

end Lanius.Semantics.CallPostTests
