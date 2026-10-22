import Lanius.Std.VecSearch
import Lanius.Memory.Allocated

/-! # Growth: allocation and `size_of`

The pieces `try_reserve` is built from: Core's `alloc` expression, the
buffer a successful allocation gives, what it keeps (other buffers, reads,
`VecRep`), and `core::mem::size_of<T>`. -/

namespace Lanius.Std

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory

variable {P : Program} {T : Ty} {size : Nat}

/-! ## The `alloc` expression -/

theorem StableExpr.alloc' {t1 t2 : Nat} {S S1 S2 : State} {sizeE alignE : Expr} {n a ptr : Nat}
    {h' : Heap} (sizeRun : StableExpr t1 P S sizeE (.unsigned .usize n) S1)
    (alignRun : StableExpr t2 P S1 alignE (.unsigned .usize a) S2)
    (allocated : S2.heap.allocate n a = .allocated ptr h') :
    StableExpr (max t1 t2 + 1) P S (.alloc sizeE alignE) (.pointer ptr) { S2 with heap := h' } := by
  intro fuel enough
  have r1 := sizeRun (fuel - 1) (by omega)
  have r2 := alignRun (fuel - 1) (by omega)
  rw [show fuel = (fuel - 1).succ by omega, evalExpr.eq_def]
  simp only [r1, r2, allocated]

theorem StableExpr.allocNull {t1 t2 : Nat} {S S1 S2 : State} {sizeE alignE : Expr} {n a : Nat}
    {h' : Heap} (sizeRun : StableExpr t1 P S sizeE (.unsigned .usize n) S1)
    (alignRun : StableExpr t2 P S1 alignE (.unsigned .usize a) S2)
    (exhausted : S2.heap.allocate n a = .exhausted h') :
    StableExpr (max t1 t2 + 1) P S (.alloc sizeE alignE) (.pointer null) { S2 with heap := h' } := by
  intro fuel enough
  have r1 := sizeRun (fuel - 1) (by omega)
  have r2 := alignRun (fuel - 1) (by omega)
  rw [show fuel = (fuel - 1).succ by omega, evalExpr.eq_def]
  simp only [r1, r2, exhausted]

/-- `alloc(n, 8)` with budget for `n` bytes gives the next aligned address
and the heap with one fresh zeroed block. -/
theorem RunsExpr.allocAt {S S1 S2 : State} {sizeE alignE : Expr} {n : Nat} {budget : Option Nat}
    (sizeRun : RunsExpr P S sizeE (.unsigned .usize n) S1)
    (alignRun : RunsExpr P S1 alignE (.unsigned .usize 8) S2)
    (available : consumeBudget S2.heap.remaining n = some budget) :
    RunsExpr P S (.alloc sizeE alignE) (.pointer (S2.heap.allocationAddress 8))
      { S2 with heap := S2.heap.allocatedBytes n 8 budget } := by
  obtain ⟨t1, r1, l1⟩ := sizeRun
  obtain ⟨t2, r2, l2⟩ := alignRun
  exact .ofStable (StableExpr.alloc' r1 r2 (Heap.allocate_of_budget (by decide) available))
    (l2.trans l1)

/-! ## What an allocation gives and keeps -/

theorem alloc_buffer {h : Heap} (below : HeapBlocksBelowNext h) {n : Nat} (positive : 0 < n)
    {budget : Option Nat} (fits : h.allocationAddress 8 + n < 2 ^ 64) :
    Buffer (h.allocatedBytes n 8 budget) (h.allocationAddress 8) n := by
  refine ⟨?_, fun i inside => ⟨0, Heap.allocatedBytes_read below (by decide) inside⟩,
    Heap.allocationAddress_aligned h, fits⟩
  have found := Heap.allocatedBytes_containing (budget := budget) below (by decide : 0 < 8) positive
    (offset := 0)
  rw [Nat.add_zero] at found
  rw [found]
  rfl

theorem loadBytes_afterAlloc {h : Heap} {n a pointer count : Nat} {budget : Option Nat}
    {bytes : List UInt8} (loaded : h.loadBytes pointer count = .ok bytes) :
    (h.allocatedBytes n a budget).loadBytes pointer count = .ok bytes := by
  apply Heap.loadBytes_congr loaded
  intro index inside
  have length := (loadBytesFrom_spec loaded).1
  have read := Heap.loadBytes_get loaded (List.getElem?_eq_getElem (by omega : index < bytes.length))
  rw [read, Heap.allocatedBytes_oldRead read]

theorem ReadsWithin.afterAlloc (h : Heap) (n a : Nat) (budget : Option Nat) (lo m : Nat) :
    ReadsWithin h (h.allocatedBytes n a budget) lo m :=
  fun _ _ _ _ _ loaded => loadBytes_afterAlloc loaded

theorem Buffer.afterAlloc {h : Heap} {p m n a : Nat} {budget : Option Nat} (buffer : Buffer h p m) :
    Buffer (h.allocatedBytes n a budget) p m := by
  obtain ⟨found, readable, aligned, bound⟩ := buffer
  refine ⟨?_, fun i inside => ?_, aligned, bound⟩
  · cases hb : h.containingBlock? p with
    | none => simp [hb] at found
    | some block =>
        have kept : (h.allocatedBytes n a budget).containingBlock? p = some block := by
          simp only [Heap.containingBlock?, Heap.allocatedBytes, List.find?_append] at hb ⊢
          rw [hb, Option.some_or]
        rw [kept]; rw [hb] at found; exact found
  · obtain ⟨byte, read⟩ := readable i inside
    exact ⟨byte, Heap.allocatedBytes_oldRead read⟩

/-- A vector's representation survives an allocation. -/
theorem VecRep.afterAlloc {vec : TypeId} {h : Heap} {v : Value} {xs : List Value} {n a : Nat}
    {budget : Option Nat} (rep : VecRep P T size vec h v xs) :
    VecRep P T size vec (h.allocatedBytes n a budget) v xs := by
  obtain ⟨p, cap, same, lenLe, capBound, buffer, reads⟩ := rep
  exact ⟨p, cap, same, lenLe, capBound, fun positive => (buffer positive).afterAlloc,
    fun i inside other within => reads i inside other
      (ReadsWithin.trans (ReadsWithin.afterAlloc h n a budget _ _) within)⟩

/-! ## `core::mem::size_of<T>` -/

/-- `pub fn size_of<T>() -> usize { let nowhere: ptr = 0; let probe: [T] =
slice_from_raw_parts(nowhere, 0); let stride: isize = slice_stride(probe);
if (stride < 0) { return (0 - stride) as usize; } return stride as usize; }` -/
def sizeOfFn (sizeOf : FunctionId) (T : Ty) : Function where
  id := sizeOf
  parameters := []
  returnType := usizeTy
  body := some <|
    .letLocal 0 ptrTy (.value (.pointer 0))
    (.letLocal 1 (.slice T) (rawView T (.local 0) (int 0))
    (.letLocal 2 isizeTy (.intrinsic .sliceStride (.local 1))
    (guardReturn (.binary .less (.local 2) (.cast (.signed .isize) (int 0)))
      (.cast (.unsigned .usize) (.binary .subtract (.cast (.signed .isize) (int 0)) (.local 2)))
      (.returnValue (some (.cast (.unsigned .usize) (.local 2)))))))

theorem eval_isize_lt (t : Target) (a b : Int) :
    evalBinaryValue t .less (.signed .isize a) (.signed .isize b) = .ok (.boolean (decide (a < b))) := by
  simp [evalBinaryValue, evalSignedBinary]

/-- `size_of<T>()` is the element size of the layout. -/
theorem size_of_spec (target : P.target = Target.x86_64) (kind : ElemKind P T size) {sizeOf : FunctionId}
    (found : P.function? sizeOf = some (sizeOfFn sizeOf T)) {caller : State}
    (formed : caller.CellsWellFormed) :
    ∃ after, RunsExpr P caller (.call sizeOf (([] : List Value).map Expr.value)) (.unsigned .usize size) after ∧
      PureFrame caller after := by
  refine PureRun.call found rfl rfl formed ?_
  let E : State := { caller with locals := [] }
  have fE : E.CellsWellFormed := formed
  change PureRun P E _ _
  refine PureRun.letPure fE (RunsExpr.value' (.pointer 0)) ?_
  let S0 := E.bindLocal 0 (.pointer 0)
  have f0 : S0.CellsWellFormed := fE.bindLocal _ _
  refine PureRun.letPure f0 (rawView_empty kind (RunsExpr.local' (local_bound fE 0 _)) (RunsExpr.value' _)) ?_
  let S1 := S0.bindLocal 1 (.rawSlice T 0 0)
  have f1 : S1.CellsWellFormed := f0.bindLocal _ _
  refine PureRun.letPure f1 (RunsExpr.sliceStride' (RunsExpr.local' (local_bound f0 1 _))
    (rawSliceStride_kind kind 0 0)) ?_
  let S2 := S1.bindLocal 2 (.signed .isize (strideOf T size))
  have f2 : S2.CellsWellFormed := f1.bindLocal _ _
  have l2 : S2.local? 2 = some (.signed .isize (strideOf T size)) := local_bound f1 2 _
  have zero : RunsExpr P S2 (.cast (.signed .isize) (int 0)) (.signed .isize 0) S2 :=
    RunsExpr.cast' (RunsExpr.value' _) (by rw [target]; exact cast_isize_zero)
  have cond := RunsExpr.binary (RunsExpr.local' l2) zero (by decide) (eval_isize_lt P.target _ _)
  have bound := kind.size_le
  by_cases scalar : T = i32Ty
  · have four := kind.i32_size scalar
    have stride : strideOf T size = 4 := if_pos scalar
    rw [stride] at cond l2
    rw [show decide ((4 : Int) < 0) = false by decide] at cond
    refine PureRun.guardSkip cond ?_
    refine PureRun.ret f2 (RunsExpr.cast' (RunsExpr.local' l2) ?_)
    rw [target, four]
    exact cast_usize_of_isize (n := 4) (by decide)
  · have stride : strideOf T size = -(size : Int) := if_neg scalar
    have positive := kind.size_pos
    rw [stride] at cond l2
    rw [show decide (-(size : Int) < 0) = true by simp; omega] at cond
    refine PureRun.guardTaken cond (PureRun.ret f2 (RunsExpr.cast'
      (RunsExpr.binary zero (RunsExpr.local' l2) (by decide)
        (by rw [target]; exact eval_isize_neg (by omega))) ?_)) nofun
    rw [target]
    exact cast_usize_of_isize (by omega)

#print axioms size_of_spec
#print axioms alloc_buffer
#print axioms VecRep.afterAlloc

end Lanius.Std
