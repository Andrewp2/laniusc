import Lanius.Std.VecRep

/-! # `core::mem::typed_slice_from_storage` and `slots`

`fromStorage_spec`: on storage `p` of `cap` elements (a `Buffer` when
`cap > 0`), `typed_slice_from_storage<T>(p, cap)` returns the raw view
`viewAddr T size p cap` of length `cap` and leaves the heap as it was.
`slots_spec` lifts it to `slots(v)`. -/

namespace Lanius.Std

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory

/-! ## Machine arithmetic in range -/

theorem wrap_i32 {n : Int} (lo : -2147483648 ≤ n) (hi : n < 2147483648) :
    wrapSigned Target.x86_64 .i32 n = n := by
  change (if n % 4294967296 ≥ 2147483648 then n % 4294967296 - 4294967296 else n % 4294967296) = n
  split <;> omega

theorem wrap_isize {n : Int} (lo : 0 ≤ n) (hi : n < 9223372036854775808) :
    wrapSigned Target.x86_64 .isize n = n := by
  change (if n % 18446744073709551616 ≥ 9223372036854775808 then n % 18446744073709551616 - 18446744073709551616
    else n % 18446744073709551616) = n
  split <;> omega

theorem wrap_usizeInt {n : Nat} (hi : n < 18446744073709551616) :
    wrapUnsignedInt Target.x86_64 .usize (n : Int) = n := by
  change Int.toNat ((n : Int) % 18446744073709551616) = n
  rw [Int.emod_eq_of_lt (by omega) (by omega)]
  exact Int.toNat_natCast n

theorem wrap_usize {n : Nat} (hi : n < 18446744073709551616) :
    wrapUnsigned Target.x86_64 .usize n = n := by
  change n % 18446744073709551616 = n
  omega

theorem pointerOffset_add {a b : Nat} (hi : a + b < 18446744073709551616) :
    pointerOffset Target.x86_64 false a (b : Int) = .pointer (a + b) := by
  change Value.pointer (Int.toNat (((a : Int) + (b : Int)) % 18446744073709551616)) = _
  rw [Int.emod_eq_of_lt (by omega) (by omega)]
  congr 1

/-! ## Views of the storage -/

/-- `slice_stride` of a view of `T`. -/
def strideOf (T : Ty) (size : Nat) : Int := if T = i32Ty then 4 else -(size : Int)

theorem rawSliceStride_kind {P : Program} {T : Ty} {size : Nat} (kind : ElemKind P T size) (a n : Nat) :
    rawSliceStride? P (.rawSlice T a n) = some (strideOf T size) := by
  cases kind with
  | i32 => rfl
  | «structure» layout _ _ =>
      simp [rawSliceStride?, NativeLayout.elementStride?, layout, strideOf, i32Ty, NativeLayout.wordBytes]
  | enumeration layout _ _ =>
      simp [rawSliceStride?, NativeLayout.elementStride?, layout, strideOf, i32Ty, NativeLayout.wordBytes]

/-- The empty probe view `slice_from_raw_parts(pointer, 0)`. -/
theorem rawView_empty {P : Program} {S : State} {T : Ty} {size a : Nat} {pe le : Expr}
    (kind : ElemKind P T size) (pointer : RunsExpr P S pe (.pointer a) S)
    (length : RunsExpr P S le (.signed .i32 0) S) :
    RunsExpr P S (rawView T pe le) (.rawSlice T a 0) S := by
  cases kind with
  | i32 =>
      rw [show rawView i32Ty pe le = .i32SliceFromRawParts pe le from if_pos rfl]
      exact RunsExpr.i32View pointer length (mapRawI32Slice_empty S a)
  | «structure» layout positive _ =>
      simp only [rawView, i32Ty, reduceCtorEq, if_false]
      exact RunsExpr.nominalView pointer length (by
        simp [mapRawNominalSlice, layout, Nat.ne_of_gt positive])
  | enumeration layout positive _ =>
      simp only [rawView, i32Ty, reduceCtorEq, if_false]
      exact RunsExpr.nominalView pointer length (by
        simp [mapRawNominalSlice, layout, Nat.ne_of_gt positive])

private theorem rawView_storage_nominal {P : Program} {S : State} {T : Ty} {w p cap : Nat}
    {pe le : Expr} {block : Block}
    (nominal : (match T with | .structure _ | .enumeration _ => true | _ => false) = true)
    (notI32 : T ≠ i32Ty) (layout : NativeLayout.valueWords? P T = some w) (wpos : 0 < w)
    (positive : 0 < cap) (hb : S.heap.containingBlock? p = some block) (aligned : p % 8 = 0)
    (base : block.base = p) (bsize : block.size = 8 * w * cap) (balign : block.alignment = 8)
    (pointer : RunsExpr P S pe (.pointer (viewAddr T (8 * w) p cap)) S)
    (length : RunsExpr P S le (.signed .i32 cap) S) :
    RunsExpr P S (rawView T pe le) (.rawSlice T (viewAddr T (8 * w) p cap) cap) S := by
  simp only [rawView, if_neg notI32]
  have view : viewAddr T (8 * w) p cap = p + 8 * w * cap - 8 := by
    simp [viewAddr, notI32, Nat.ne_of_gt positive]
  have big : 8 * w ≤ 8 * w * cap := Nat.le_mul_of_pos_right _ positive
  have low : p + 8 * w * cap - 8 + 8 - cap * w * 8 = p := by
    rw [Nat.mul_comm cap w, Nat.mul_comm (w * cap) 8, ← Nat.mul_assoc]; omega
  rw [view] at pointer ⊢
  refine RunsExpr.nominalView pointer length
    (mapRawNominalSlice_of_block (block := block) cap positive nominal layout wpos ?_ ?_ ?_ ?_ ?_)
  all_goals simp only [NativeLayout.wordBytes]
  · rw [Nat.mul_comm cap w, Nat.mul_comm (w * cap) 8, ← Nat.mul_assoc]; omega
  · rw [low]; exact hb
  · rw [low]; exact aligned
  · omega
  · rw [base, bsize]; omega

/-- The view of `cap > 0` elements of a buffer. -/
theorem rawView_storage {P : Program} {S : State} {T : Ty} {size p cap : Nat} {pe le : Expr}
    (kind : ElemKind P T size) (buffer : Buffer S.heap p (size * cap)) (positive : 0 < cap)
    (pointer : RunsExpr P S pe (.pointer (viewAddr T size p cap)) S)
    (length : RunsExpr P S le (.signed .i32 cap) S) :
    RunsExpr P S (rawView T pe le) (.rawSlice T (viewAddr T size p cap) cap) S := by
  obtain ⟨found, _, aligned, _⟩ := buffer
  cases hb : S.heap.containingBlock? p with
  | none => simp [hb] at found
  | some block =>
    simp only [hb, Option.map_some, Option.some.injEq, Block.shape] at found
    have base : block.base = p := congrArg Block.base found
    have bsize : block.size = size * cap := congrArg Block.size found
    have balign : block.alignment = 8 := congrArg Block.alignment found
    cases kind with
    | i32 =>
        rw [show rawView i32Ty pe le = .i32SliceFromRawParts pe le from if_pos rfl]
        have view : viewAddr i32Ty 4 p cap = p := if_pos (Or.inl rfl)
        rw [view] at pointer ⊢
        exact RunsExpr.i32View pointer length (mapRawI32Slice_of_block cap positive hb (by omega)
          (by omega) (by rw [base, bsize]; omega))
    | «structure» layout wpos _ =>
        exact rawView_storage_nominal rfl (by simp [i32Ty]) layout wpos positive hb aligned base bsize
          balign pointer length
    | enumeration layout wpos _ =>
        exact rawView_storage_nominal rfl (by simp [i32Ty]) layout wpos positive hb aligned base bsize
          balign pointer length

/-! ## Operator results in range -/

theorem eval_i32_ge (t : Target) (a b : Int) :
    evalBinaryValue t .greaterEqual (.signed .i32 a) (.signed .i32 b) = .ok (.boolean (decide (a ≥ b))) := by
  simp [evalBinaryValue, evalSignedBinary]

theorem eval_i32_lt (t : Target) (a b : Int) :
    evalBinaryValue t .less (.signed .i32 a) (.signed .i32 b) = .ok (.boolean (decide (a < b))) := by
  simp [evalBinaryValue, evalSignedBinary]

theorem eval_i32_eq (t : Target) (a b : Int) :
    evalBinaryValue t .equal (.signed .i32 a) (.signed .i32 b) = .ok (.boolean (a == b)) := by
  simp [evalBinaryValue, scalarEqual]

theorem eval_isize_ge (t : Target) (a b : Int) :
    evalBinaryValue t .greaterEqual (.signed .isize a) (.signed .isize b) = .ok (.boolean (decide (a ≥ b))) := by
  simp [evalBinaryValue, evalSignedBinary]

theorem eval_isize_neg {n : Nat} (hi : n < 9223372036854775808) :
    evalBinaryValue Target.x86_64 .subtract (.signed .isize 0) (.signed .isize (-(n : Int))) =
      .ok (.signed .isize n) := by
  simp only [evalBinaryValue, evalSignedBinary, beq_self_eq_true, if_true]
  rw [show (0 : Int) - -(n : Int) = n by omega, wrap_isize (by omega) (by omega)]

theorem eval_i32_sub {a b : Int} (lo : -2147483648 ≤ a - b) (hi : a - b < 2147483648) :
    evalBinaryValue Target.x86_64 .subtract (.signed .i32 a) (.signed .i32 b) = .ok (.signed .i32 (a - b)) := by
  simp only [evalBinaryValue, evalSignedBinary, beq_self_eq_true, if_true]
  rw [wrap_i32 lo hi]

theorem eval_usize_mul {a b : Nat} (hi : a * b < 18446744073709551616) :
    evalBinaryValue Target.x86_64 .multiply (.unsigned .usize a) (.unsigned .usize b) =
      .ok (.unsigned .usize (a * b)) := by
  simp only [evalBinaryValue, evalUnsignedBinary, beq_self_eq_true, if_true]
  rw [wrap_usize hi]

theorem eval_usize_sub {a b : Nat} (le : b ≤ a) (hi : a < 18446744073709551616) :
    evalBinaryValue Target.x86_64 .subtract (.unsigned .usize a) (.unsigned .usize b) =
      .ok (.unsigned .usize (a - b)) := by
  simp only [evalBinaryValue, evalUnsignedBinary, beq_self_eq_true, if_true]
  change Except.ok (Value.unsigned .usize ((a + 18446744073709551616 - b % 18446744073709551616) %
    18446744073709551616)) = _
  congr 3
  omega

theorem eval_ptr_add {a b : Nat} (hi : a + b < 18446744073709551616) :
    evalBinaryValue Target.x86_64 .add (.pointer a) (.unsigned .usize b) = .ok (.pointer (a + b)) := by
  simp only [evalBinaryValue]
  rw [show Int.ofNat b = (b : Int) from rfl, pointerOffset_add hi]

theorem cast_isize_zero :
    evalScalarCast Target.x86_64 (.signed .isize) (.signed .i32 0) = .ok (.signed .isize 0) := by
  simp only [evalScalarCast]
  rw [wrap_isize (by omega) (by omega)]

theorem cast_usize_of_isize {n : Nat} (hi : n < 18446744073709551616) :
    evalScalarCast Target.x86_64 (.unsigned .usize) (.signed .isize n) = .ok (.unsigned .usize n) := by
  simp only [evalScalarCast]
  rw [wrap_usizeInt hi]

theorem cast_usize_of_i32 {n : Nat} (hi : n < 18446744073709551616) :
    evalScalarCast Target.x86_64 (.unsigned .usize) (.signed .i32 n) = .ok (.unsigned .usize n) := by
  simp only [evalScalarCast]
  rw [wrap_usizeInt hi]

/-! ## `typed_slice_from_storage` -/

theorem fromStorage_spec {P : Program} {T : Ty} {ids : VecIds} {size : Nat}
    (inst : VecInstance P T ids) (kind : ElemKind P T size)
    {caller : State} (formed : caller.CellsWellFormed) {p cap : Nat} (capBound : cap < 2 ^ 31)
    (buffer : 0 < cap → Buffer caller.heap p (size * cap)) :
    ∃ after, RunsExpr P caller (.call ids.fromStorage ([Value.pointer p, .signed .i32 cap].map Expr.value))
      (.rawSlice T (viewAddr T size p cap) cap) after ∧ PureFrame caller after := by
  refine PureRun.call inst.fromStorage rfl rfl formed ?_
  have target := inst.target
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  have f1 := f0.bindLocal 0 (.pointer p)
  let E : State := (E0.bindLocal 0 (.pointer p)).bindLocal 1 (.signed .i32 cap)
  change PureRun P E _ _
  have fE : E.CellsWellFormed := f1.bindLocal _ _
  have l1 : E.local? 1 = some (.signed .i32 cap) := local_bound f1 1 _
  have l0 : E.local? 0 = some (.pointer p) := local_kept f1 _ (by decide) (local_bound f0 0 _)
  refine PureRun.assert (RunsExpr.binary (RunsExpr.local' l1) (RunsExpr.value' _) (by decide)
    (by rw [eval_i32_ge]; simp)) ?_
  refine PureRun.letPure fE (RunsExpr.value' (.pointer 0)) ?_
  let S2 := E.bindLocal 2 (.pointer 0)
  have f2 : S2.CellsWellFormed := fE.bindLocal _ _
  have l2_2 : S2.local? 2 = some (.pointer 0) := local_bound fE 2 _
  have l2_1 : S2.local? 1 = some (.signed .i32 cap) := local_kept fE _ (by decide) l1
  have l2_0 : S2.local? 0 = some (.pointer p) := local_kept fE _ (by decide) l0
  refine PureRun.letPure f2 (rawView_empty kind (RunsExpr.local' l2_2) (RunsExpr.value' _)) ?_
  let S3 := S2.bindLocal 3 (.rawSlice T 0 0)
  have f3 : S3.CellsWellFormed := f2.bindLocal _ _
  have l3_3 : S3.local? 3 = some (.rawSlice T 0 0) := local_bound f2 3 _
  have l3_1 : S3.local? 1 = some (.signed .i32 cap) := local_kept f2 _ (by decide) l2_1
  have l3_0 : S3.local? 0 = some (.pointer p) := local_kept f2 _ (by decide) l2_0
  refine PureRun.letPure f3 (RunsExpr.sliceStride' (RunsExpr.local' l3_3) (rawSliceStride_kind kind 0 0)) ?_
  let S4 := S3.bindLocal 4 (.signed .isize (strideOf T size))
  have f4 : S4.CellsWellFormed := f3.bindLocal _ _
  have l4_4 : S4.local? 4 = some (.signed .isize (strideOf T size)) := local_bound f3 4 _
  have l4_1 : S4.local? 1 = some (.signed .i32 cap) := local_kept f3 _ (by decide) l3_1
  have l4_0 : S4.local? 0 = some (.pointer p) := local_kept f3 _ (by decide) l3_0
  have zero : RunsExpr P S4 (.cast (.signed .isize) (int 0)) (.signed .isize 0) S4 :=
    RunsExpr.cast' (RunsExpr.value' _) (by rw [target]; exact cast_isize_zero)
  have cond : RunsExpr P S4 (.binary .logicalOr
      (.binary .greaterEqual (.local 4) (.cast (.signed .isize) (int 0))) (.binary .equal (.local 1) (int 0)))
      (.boolean (decide (strideOf T size ≥ 0) || ((cap : Int) == 0))) S4 := RunsExpr.logicalOrBool
    (RunsExpr.binary (RunsExpr.local' l4_4) zero (by decide) (eval_isize_ge _ _ _))
    (RunsExpr.binary (RunsExpr.local' l4_1) (RunsExpr.value' (.signed .i32 0)) (by decide)
      (eval_i32_eq _ _ _))
  by_cases taken : T = i32Ty ∨ cap = 0
  · have isTrue : (decide (strideOf T size ≥ 0) || ((cap : Int) == 0)) = true := by
      rcases taken with i32 | zero
      · simp [strideOf, i32]
      · simp [zero]
    rw [isTrue] at cond
    refine PureRun.guardTaken cond ?_ nofun
    have view : RunsExpr P S4 (rawView T (.local 0) (.local 1))
        (.rawSlice T (viewAddr T size p cap) cap) S4 := by
      by_cases empty : cap = 0
      · have at0 : viewAddr T size p cap = p := if_pos (Or.inr empty)
        rw [at0]
        subst empty
        exact rawView_empty kind (RunsExpr.local' l4_0) (RunsExpr.local' l4_1)
      · have i32 : T = i32Ty := taken.resolve_right empty
        have atP : viewAddr T size p cap = p := if_pos (Or.inl i32)
        exact rawView_storage kind (buffer (by omega)) (by omega)
          (by rw [atP]; exact RunsExpr.local' l4_0) (RunsExpr.local' l4_1)
    refine PureRun.letPure f4 view ?_
    exact PureRun.ret (f4.bindLocal _ _) (RunsExpr.local' (local_bound f4 5 _))
  · have notI32 : T ≠ i32Ty := fun h => taken (Or.inl h)
    have positive : 0 < cap := by omega
    have eight := kind.size_eight notI32
    have small := kind.size_le
    have buf := buffer positive
    have room : p + size * cap < 18446744073709551616 := buf.2.2.2
    have big : 8 ≤ size * cap := Nat.le_trans eight (Nat.le_mul_of_pos_right _ positive)
    have isFalse : (decide (strideOf T size ≥ 0) || ((cap : Int) == 0)) = false := by
      have : ¬ (-(size : Int) ≥ 0) := by omega
      simp [strideOf, notI32, Nat.ne_of_gt positive, show size ≠ 0 by omega]
    rw [isFalse] at cond
    refine PureRun.guardSkip cond ?_
    have stride : strideOf T size = -(size : Int) := if_neg notI32
    rw [stride] at l4_4
    have magnitude : RunsExpr P S4
        (.cast (.unsigned .usize) (.binary .subtract (.cast (.signed .isize) (int 0)) (.local 4)))
        (.unsigned .usize size) S4 :=
      RunsExpr.cast' (RunsExpr.binary zero (RunsExpr.local' l4_4) (by decide)
        (by rw [target]; exact eval_isize_neg (by omega))) (by rw [target]; exact cast_usize_of_isize (by omega))
    have count : RunsExpr P S4 (.cast (.unsigned .usize) (.local 1)) (.unsigned .usize cap) S4 :=
      RunsExpr.cast' (RunsExpr.local' l4_1) (by rw [target]; exact cast_usize_of_i32 (by omega))
    have top : RunsExpr P S4 (.binary .subtract (.binary .multiply
        (.cast (.unsigned .usize) (.binary .subtract (.cast (.signed .isize) (int 0)) (.local 4)))
        (.cast (.unsigned .usize) (.local 1))) (.value (.unsigned .usize 8)))
        (.unsigned .usize (size * cap - 8)) S4 :=
      RunsExpr.binary (RunsExpr.binary magnitude count (by decide)
        (by rw [target]; exact eval_usize_mul (by omega)))
        (RunsExpr.value' (.unsigned .usize 8)) (by decide) (by rw [target]; exact eval_usize_sub big (by omega))
    refine PureRun.letPure f4 top ?_
    let S6 := S4.bindLocal 6 (.unsigned .usize (size * cap - 8))
    have f6 : S6.CellsWellFormed := f4.bindLocal _ _
    have l6_6 : S6.local? 6 = some (.unsigned .usize (size * cap - 8)) := local_bound f4 6 _
    have l6_1 : S6.local? 1 = some (.signed .i32 cap) := local_kept f4 _ (by decide) l4_1
    have l6_0 : S6.local? 0 = some (.pointer p) := local_kept f4 _ (by decide) l4_0
    have atTop : viewAddr T size p cap = p + (size * cap - 8) := by
      simp only [viewAddr, notI32, Nat.ne_of_gt positive, or_self, if_false]
      omega
    have pointer : RunsExpr P S6 (.binary .add (.local 0) (.local 6)) (.pointer (viewAddr T size p cap)) S6 :=
      RunsExpr.binary (RunsExpr.local' l6_0) (RunsExpr.local' l6_6) (by decide)
        (by rw [target, atTop]; exact eval_ptr_add (by omega))
    refine PureRun.letPure f6 (rawView_storage kind buf positive pointer (RunsExpr.local' l6_1)) ?_
    exact PureRun.ret (f6.bindLocal _ _) (RunsExpr.local' (local_bound f6 7 _))

#print axioms fromStorage_spec

end Lanius.Std
