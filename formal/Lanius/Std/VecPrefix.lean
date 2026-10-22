import Lanius.Std.SetSpec

/-! # `as_slice` and `at`

`as_slice(v)` is `typed_prefix_from_storage(v.storage, v.reserved, v.length)`:
the first `length` of the `reserved` elements, at the addresses `slots(v)`
reads them from. For a nominal `T` with spare capacity the view starts
inside the storage block, so the specs assume the heap's blocks are
disjoint (`HeapBlocksDisjoint`): then the block that holds an interior
address is the storage block. -/

namespace Lanius.Std

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory

variable {P : Program} {T : Ty} {ids : VecIds} {size : Nat}

theorem ElemKind.size_words {P : Program} {T : Ty} {size : Nat} (kind : ElemKind P T size)
    (nominal : T ≠ i32Ty) : ∃ w, size = 8 * w := by
  cases kind with
  | i32 => exact absurd rfl nominal
  | «structure» _ _ _ => exact ⟨_, rfl⟩
  | enumeration _ _ _ => exact ⟨_, rfl⟩

/-- In a heap with disjoint blocks, the block holding `p` holds every
address of it. -/
theorem containingBlock_interior {h : Heap} {p k : Nat} {block : Block} (disjoint : HeapBlocksDisjoint h)
    (hb : h.containingBlock? p = some block) (inside : p + k < block.base + block.size) :
    h.containingBlock? (p + k) = some block := by
  unfold Heap.containingBlock? at hb ⊢
  have mem := List.mem_of_find?_eq_some hb
  have holds := List.find?_some hb
  simp only [Bool.and_eq_true, decide_eq_true_eq] at holds
  obtain ⟨⟨live, ge⟩, _⟩ := holds
  have geN : (block.base : Nat) ≤ p := ge
  cases found : h.blocks.find? (fun b => b.live && decide (b.base ≤ p + k) && decide (p + k < b.base + b.size)) with
  | none =>
      have miss := List.find?_eq_none.mp found block mem
      simp only [Bool.and_eq_true, decide_eq_true_eq] at miss
      exact (miss ⟨⟨live, Nat.le_trans geN (Nat.le_add_right p k)⟩, inside⟩).elim
  | some b =>
      have mb := List.mem_of_find?_eq_some found
      have hold := List.find?_some found
      simp only [Bool.and_eq_true, decide_eq_true_eq] at hold
      obtain ⟨⟨_, ge'⟩, lt'⟩ := hold
      have geN' : (b.base : Nat) ≤ p + k := ge'
      have ltN' : p + k < (b.base : Nat) + (b.size : Nat) := lt'
      by_cases same : b = block
      · rw [same]
      · rcases disjoint b mb block mem same with d | d
        · have dN : (b.base : Nat) + (b.size : Nat) ≤ (block.base : Nat) := d
          exact (Nat.lt_irrefl _ (Nat.lt_of_lt_of_le ltN' (Nat.le_trans dN (Nat.le_trans geN (Nat.le_add_right p k))))).elim
        · have dN : (block.base : Nat) + (block.size : Nat) ≤ (b.base : Nat) := d
          exact (Nat.lt_irrefl _ (Nat.lt_of_lt_of_le inside (Nat.le_trans dN geN'))).elim

theorem Within.shrink {h : Heap} {q n m : Nat} (within : Within h q n) (le : m ≤ n) : Within h q m := by
  obtain ⟨block, hb, balign, aligned, bounds, room⟩ := within
  exact ⟨block, hb, balign, aligned, by omega, by omega⟩

/-- A range of a buffer, starting at an aligned offset, in a heap with
disjoint blocks. -/
theorem Buffer.withinAt {h : Heap} {p n k m : Nat} (buffer : Buffer h p n) (disjoint : HeapBlocksDisjoint h)
    (aligned : (p + k) % 8 = 0) (positive : 0 < m) (fits : k + m ≤ n) : Within h (p + k) m := by
  obtain ⟨found, _, _, room⟩ := buffer
  cases hb : h.containingBlock? p with
  | none => simp [hb] at found
  | some block =>
    simp only [hb, Option.map_some, Option.some.injEq, Block.shape] at found
    have base : block.base = p := congrArg Block.base found
    have bsize : block.size = n := congrArg Block.size found
    have balign : block.alignment = 8 := congrArg Block.alignment found
    refine ⟨block, containingBlock_interior disjoint hb (by rw [base, bsize]; omega), by rw [balign]; exact Nat.le_refl _,
      aligned, by rw [base, bsize]; omega, by omega⟩

theorem readRawSliceIndex_shorter {P : Program} {S : State} {T : Ty} {a len cap i : Nat} (inside : i < len)
    (le : len ≤ cap) : readRawSliceIndex P S T a len i = readRawSliceIndex P S T a cap i := by
  simp only [readRawSliceIndex, show ¬ i ≥ len by omega, show ¬ i ≥ cap by omega, if_false]

/-! ## Templates -/

/-- `core::mem::typed_prefix_from_storage<T>(storage: ptr, capacity: i32, length: i32) -> [T]` -/
def prefixFromStorageFn (T : Ty) (f fromStorage : FunctionId) : Function where
  id := f
  parameters := [(0, ptrTy), (1, i32Ty), (2, i32Ty)]
  returnType := .slice T
  body := some <|
    .sequence (.expression (.intrinsic .assert (.binary .logicalAnd (.binary .greaterEqual (.local 2) (int 0))
      (.binary .lessEqual (.local 2) (.local 1)))))
    (.letLocal 3 ptrTy (.value (.pointer 0))
    (.letLocal 4 (.slice T) (rawView T (.local 3) (int 0))
    (.letLocal 5 isizeTy (.intrinsic .sliceStride (.local 4))
    (.sequence
      (.ifThenElse
        (.binary .logicalOr (.binary .greaterEqual (.local 5) (.cast (.signed .isize) (int 0)))
          (.binary .equal (.local 2) (int 0)))
        (.letLocal 6 (.slice T) (rawView T (.local 0) (.local 2)) (.returnValue (some (.local 6))))
        .skip)
    (.letLocal 7 usizeTy
      (.binary .multiply
        (.cast (.unsigned .usize) (.binary .subtract (.cast (.signed .isize) (int 0)) (.local 5)))
        (.cast (.unsigned .usize) (.binary .subtract (.local 1) (.local 2))))
      (.returnValue (some (.call fromStorage [.binary .add (.local 0) (.local 7), .local 2]))))))))

/-- `pub fn as_slice<T>(value: Vec<T>) -> [T]` -/
def asSliceFn (ids : VecIds) (T : Ty) (f prefixFn : FunctionId) : Function where
  id := f
  parameters := [(0, vecTy ids)]
  returnType := .slice T
  body := some (.returnValue (some (.call prefixFn [.field (.local 0) 0, .field (.local 0) 2, .field (.local 0) 1])))

/-- `pub fn at<T>(value: Vec<T>, index: i32) -> T { let items = as_slice(value); return items[index]; }` -/
def atFn (ids : VecIds) (T : Ty) (f asSlice : FunctionId) : Function where
  id := f
  parameters := [(0, vecTy ids), (1, i32Ty)]
  returnType := T
  body := some (.letLocal 2 (.slice T) (.call asSlice [.local 0]) (.returnValue (some (.index (.local 2) (.local 1)))))

/-- Where the prefix view of `len` of the `cap` elements at `p` starts. -/
def prefixAddr (T : Ty) (size p cap len : Nat) : Nat := if len = 0 then p else viewAddr T size p cap

/-! ## Specs -/

theorem prefixFromStorage_spec (inst : VecInstance P T ids) (kind : ElemKind P T size) {f : FunctionId}
    (found : P.function? f = some (prefixFromStorageFn T f ids.fromStorage))
    {caller : State} (formed : caller.CellsWellFormed) {p cap len : Nat} (capBound : cap < 2 ^ 31)
    (le : len ≤ cap) (buffer : 0 < cap → Buffer caller.heap p (size * cap))
    (disjoint : HeapBlocksDisjoint caller.heap) :
    ∃ after, RunsExpr P caller (.call f ([Value.pointer p, .signed .i32 cap, .signed .i32 len].map Expr.value))
      (.rawSlice T (prefixAddr T size p cap len) len) after ∧ PureFrame caller after := by
  refine PureRun.call found rfl rfl formed ?_
  have target := inst.target
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  have f1 := f0.bindLocal 0 (.pointer p)
  have f2 := f1.bindLocal 1 (.signed .i32 cap)
  let E : State := ((E0.bindLocal 0 (.pointer p)).bindLocal 1 (.signed .i32 cap)).bindLocal 2 (.signed .i32 len)
  change PureRun P E _ _
  have fE : E.CellsWellFormed := f2.bindLocal _ _
  have l2 : E.local? 2 = some (.signed .i32 len) := local_bound f2 2 _
  have l1 : E.local? 1 = some (.signed .i32 cap) := local_kept f2 _ (by decide) (local_bound f1 1 _)
  have l0 : E.local? 0 = some (.pointer p) :=
    local_kept f2 _ (by decide) (local_kept f1 _ (by decide) (local_bound f0 0 _))
  have check := RunsExpr.logicalAndBool
    (RunsExpr.binary (operation := .greaterEqual) (RunsExpr.local' l2) (RunsExpr.value' (P := P) (S := E) (.signed .i32 0))
      (by decide) (eval_i32_ge _ _ _))
    (RunsExpr.binary (operation := .lessEqual) (RunsExpr.local' l2) (RunsExpr.local' l1) (by decide) (eval_i32_le _ _ _))
  rw [show (decide ((len : Int) ≥ 0) && decide ((len : Int) ≤ cap)) = true by simp; omega] at check
  refine PureRun.assert check ?_
  refine PureRun.letPure fE (RunsExpr.value' (.pointer 0)) ?_
  let S3 := E.bindLocal 3 (.pointer 0)
  have f3 : S3.CellsWellFormed := fE.bindLocal _ _
  have l3_3 : S3.local? 3 = some (.pointer 0) := local_bound fE 3 _
  have l3_2 : S3.local? 2 = some (.signed .i32 len) := local_kept fE _ (by decide) l2
  have l3_1 : S3.local? 1 = some (.signed .i32 cap) := local_kept fE _ (by decide) l1
  have l3_0 : S3.local? 0 = some (.pointer p) := local_kept fE _ (by decide) l0
  refine PureRun.letPure f3 (rawView_empty kind (RunsExpr.local' l3_3) (RunsExpr.value' _)) ?_
  let S4 := S3.bindLocal 4 (.rawSlice T 0 0)
  have f4 : S4.CellsWellFormed := f3.bindLocal _ _
  have l4_4 : S4.local? 4 = some (.rawSlice T 0 0) := local_bound f3 4 _
  have l4_2 : S4.local? 2 = some (.signed .i32 len) := local_kept f3 _ (by decide) l3_2
  have l4_1 : S4.local? 1 = some (.signed .i32 cap) := local_kept f3 _ (by decide) l3_1
  have l4_0 : S4.local? 0 = some (.pointer p) := local_kept f3 _ (by decide) l3_0
  refine PureRun.letPure f4 (RunsExpr.sliceStride' (RunsExpr.local' l4_4) (rawSliceStride_kind kind 0 0)) ?_
  let S5 := S4.bindLocal 5 (.signed .isize (strideOf T size))
  have f5 : S5.CellsWellFormed := f4.bindLocal _ _
  have l5_5 : S5.local? 5 = some (.signed .isize (strideOf T size)) := local_bound f4 5 _
  have l5_2 : S5.local? 2 = some (.signed .i32 len) := local_kept f4 _ (by decide) l4_2
  have l5_1 : S5.local? 1 = some (.signed .i32 cap) := local_kept f4 _ (by decide) l4_1
  have l5_0 : S5.local? 0 = some (.pointer p) := local_kept f4 _ (by decide) l4_0
  have zero : RunsExpr P S5 (.cast (.signed .isize) (int 0)) (.signed .isize 0) S5 :=
    RunsExpr.cast' (RunsExpr.value' _) (by rw [target]; exact cast_isize_zero)
  have cond : RunsExpr P S5 (.binary .logicalOr
      (.binary .greaterEqual (.local 5) (.cast (.signed .isize) (int 0))) (.binary .equal (.local 2) (int 0)))
      (.boolean (decide (strideOf T size ≥ 0) || ((len : Int) == 0))) S5 := RunsExpr.logicalOrBool
    (RunsExpr.binary (RunsExpr.local' l5_5) zero (by decide) (eval_isize_ge _ _ _))
    (RunsExpr.binary (RunsExpr.local' l5_2) (RunsExpr.value' (.signed .i32 0)) (by decide)
      (eval_i32_eq _ _ _))
  by_cases taken : T = i32Ty ∨ len = 0
  · have isTrue : (decide (strideOf T size ≥ 0) || ((len : Int) == 0)) = true := by
      rcases taken with i32 | zero
      · simp [strideOf, i32]
      · simp [zero]
    rw [isTrue] at cond
    refine PureRun.guardTaken cond ?_ nofun
    have view : RunsExpr P S5 (rawView T (.local 0) (.local 2))
        (.rawSlice T (prefixAddr T size p cap len) len) S5 := by
      by_cases empty : len = 0
      · have at0 : prefixAddr T size p cap len = p := if_pos empty
        rw [at0]
        subst empty
        exact rawView_empty kind (RunsExpr.local' l5_0) (RunsExpr.local' l5_2)
      · have i32 : T = i32Ty := taken.resolve_right empty
        have atP : prefixAddr T size p cap len = p := by
          simp only [prefixAddr, viewAddr, if_neg empty, i32, true_or, if_true]
        have atLen : viewAddr T size p len = p := if_pos (Or.inl i32)
        rw [atP]
        have run := rawView_within (S := S5) kind (((buffer (by omega)).within).shrink (m := size * len)
          (Nat.mul_le_mul_left _ le)) (by omega) (by rw [atLen]; exact RunsExpr.local' l5_0) (RunsExpr.local' l5_2)
        rw [atLen] at run
        exact run
    refine PureRun.letPure f5 view ?_
    exact PureRun.ret (f5.bindLocal _ _) (RunsExpr.local' (local_bound f5 6 _))
  · have notI32 : T ≠ i32Ty := fun h => taken (Or.inl h)
    have positive : 0 < len := by omega
    have capPos : 0 < cap := by omega
    have eight := kind.size_eight notI32
    have small := kind.size_le
    obtain ⟨w, hw⟩ := kind.size_words notI32
    have buf := buffer capPos
    have room : p + size * cap < 18446744073709551616 := buf.2.2.2
    have split : size * (cap - len) + size * len = size * cap := by
      rw [← Nat.mul_add, Nat.sub_add_cancel le]
    have isFalse : (decide (strideOf T size ≥ 0) || ((len : Int) == 0)) = false := by
      have : ¬ (-(size : Int) ≥ 0) := by omega
      simp [strideOf, notI32, Nat.ne_of_gt positive, show size ≠ 0 by omega]
    rw [isFalse] at cond
    refine PureRun.guardSkip cond ?_
    have stride : strideOf T size = -(size : Int) := if_neg notI32
    rw [stride] at l5_5
    have magnitude : RunsExpr P S5
        (.cast (.unsigned .usize) (.binary .subtract (.cast (.signed .isize) (int 0)) (.local 5)))
        (.unsigned .usize size) S5 :=
      RunsExpr.cast' (RunsExpr.binary zero (RunsExpr.local' l5_5) (by decide)
        (by rw [target]; exact eval_isize_neg (by omega))) (by rw [target]; exact cast_usize_of_isize (by omega))
    have diff : RunsExpr P S5 (.binary .subtract (.local 1) (.local 2)) (.signed .i32 ((cap - len : Nat) : Int)) S5 := by
      have r := RunsExpr.binary (operation := .subtract) (RunsExpr.local' l5_1) (RunsExpr.local' l5_2) (by decide)
        (by rw [target]; exact eval_i32_sub (by omega) (by omega))
      rw [show (cap : Int) - (len : Int) = ((cap - len : Nat) : Int) by omega] at r
      exact r
    have count : RunsExpr P S5 (.cast (.unsigned .usize) (.binary .subtract (.local 1) (.local 2)))
        (.unsigned .usize (cap - len)) S5 :=
      RunsExpr.cast' diff (by rw [target]; exact cast_usize_of_i32 (by omega))
    have skipRun : RunsExpr P S5 (.binary .multiply
        (.cast (.unsigned .usize) (.binary .subtract (.cast (.signed .isize) (int 0)) (.local 5)))
        (.cast (.unsigned .usize) (.binary .subtract (.local 1) (.local 2))))
        (.unsigned .usize (size * (cap - len))) S5 :=
      RunsExpr.binary magnitude count (by decide) (by rw [target]; exact eval_usize_mul (by omega))
    refine PureRun.letPure f5 skipRun ?_
    let S7 := S5.bindLocal 7 (.unsigned .usize (size * (cap - len)))
    have f7 : S7.CellsWellFormed := f5.bindLocal _ _
    have l7_7 : S7.local? 7 = some (.unsigned .usize (size * (cap - len))) := local_bound f5 7 _
    have l7_2 : S7.local? 2 = some (.signed .i32 len) := local_kept f5 _ (by decide) l5_2
    have l7_0 : S7.local? 0 = some (.pointer p) := local_kept f5 _ (by decide) l5_0
    have pointer : RunsExpr P S7 (.binary .add (.local 0) (.local 7)) (.pointer (p + size * (cap - len))) S7 :=
      RunsExpr.binary (RunsExpr.local' l7_0) (RunsExpr.local' l7_7) (by decide)
        (by rw [target]; exact eval_ptr_add (by omega))
    have aligned : (p + size * (cap - len)) % 8 = 0 := by
      have pa := buf.2.2.1
      rw [hw, Nat.mul_assoc]; omega
    have within : Within S7.heap (p + size * (cap - len)) (size * len) :=
      buf.withinAt disjoint aligned (Nat.mul_pos (by omega) positive) (by omega)
    obtain ⟨after, run, frame⟩ := fromStorage_within_spec inst kind f7 (by omega : len < 2 ^ 31)
      (fun _ => within)
    have addr : viewAddr T size (p + size * (cap - len)) len = prefixAddr T size p cap len := by
      simp only [prefixAddr, viewAddr, notI32, Nat.ne_of_gt positive, Nat.ne_of_gt capPos, or_self, if_false]
      omega
    rw [addr] at run
    exact PureRun.retCall (RunsExprs.two pointer (RunsExpr.local' l7_2)) ⟨after, run, frame⟩

theorem asSlice_spec (inst : VecInstance P T ids) (kind : ElemKind P T size) {f pf : FunctionId}
    (found : P.function? f = some (asSliceFn ids T f pf))
    (pfFound : P.function? pf = some (prefixFromStorageFn T pf ids.fromStorage))
    {caller : State} (formed : caller.CellsWellFormed) {xs : List Value} {p cap : Nat}
    (rep : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]) xs)
    (disjoint : HeapBlocksDisjoint caller.heap) :
    ∃ after, RunsExpr P caller (.call f
        ([Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]].map Expr.value))
      (.rawSlice T (prefixAddr T size p cap xs.length) xs.length) after ∧ PureFrame caller after := by
  obtain ⟨_, lenLe, capBound, buffer, _⟩ := rep.fields
  refine PureRun.call found rfl rfl formed ?_
  let vv := Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  let E := E0.bindLocal 0 vv
  change PureRun P E _ _
  have fE : E.CellsWellFormed := f0.bindLocal _ _
  have l0 : E.local? 0 = some vv := local_bound f0 0 _
  exact PureRun.retCall (RunsExprs.three (RunsExpr.field' (j := 0) (RunsExpr.local' l0) rfl)
    (RunsExpr.field' (j := 2) (RunsExpr.local' l0) rfl) (RunsExpr.field' (j := 1) (RunsExpr.local' l0) rfl))
    (prefixFromStorage_spec inst kind pfFound fE capBound lenLe buffer disjoint)

/-- `at(v, i)` for `i` in range is `xs[i]`. -/
theorem at_spec (inst : VecInstance P T ids) (kind : ElemKind P T size) {f sl pf : FunctionId}
    (found : P.function? f = some (atFn ids T f sl)) (slFound : P.function? sl = some (asSliceFn ids T sl pf))
    (pfFound : P.function? pf = some (prefixFromStorageFn T pf ids.fromStorage))
    {caller : State} (formed : caller.CellsWellFormed) {xs : List Value} {p cap : Nat}
    (rep : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]) xs)
    (disjoint : HeapBlocksDisjoint caller.heap) {i : Nat} (inside : i < xs.length) :
    ∃ after, RunsExpr P caller (.call f
        ([Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap], .signed .i32 i].map
          Expr.value))
      xs[i] after ∧ PureFrame caller after := by
  obtain ⟨_, lenLe, _, _, reads⟩ := rep.fields
  refine PureRun.call found rfl rfl formed ?_
  let vv := Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  have f1 := f0.bindLocal 0 vv
  let E := (E0.bindLocal 0 vv).bindLocal 1 (.signed .i32 i)
  change PureRun P E _ _
  have fE : E.CellsWellFormed := f1.bindLocal _ _
  have l1 : E.local? 1 = some (.signed .i32 i) := local_bound f1 1 _
  have l0 : E.local? 0 = some vv := local_kept f1 _ (by decide) (local_bound f0 0 _)
  obtain ⟨S', run, frame⟩ := asSlice_spec inst kind slFound pfFound fE rep disjoint
  refine PureRun.letRun (callArgs (RunsExprs.one (RunsExpr.local' l0)) run) frame ?_
  have fS := frame.afterFormed
  have b2 := local_bound fS 2 (.rawSlice T (prefixAddr T size p cap xs.length) xs.length)
  have b1 := local_kept fS (.rawSlice T (prefixAddr T size p cap xs.length) xs.length) (show (2 : VarId) ≠ 1 by decide)
    (frame.localFound l1)
  have addr : prefixAddr T size p cap xs.length = viewAddr T size p cap := if_neg (by omega)
  have read := reads i inside (S'.bindLocal 2 (.rawSlice T (prefixAddr T size p cap xs.length) xs.length))
    (by rw [show (S'.bindLocal 2 _).heap = caller.heap from frame.heap]; exact ReadsWithin.refl _ _ _)
  rw [← readRawSliceIndex_shorter inside lenLe, ← addr] at read
  exact PureRun.ret (fS.bindLocal _ _) (RunsExpr.rawIndex b2 b1 read)

#print axioms containingBlock_interior
#print axioms prefixFromStorage_spec
#print axioms asSlice_spec
#print axioms at_spec

end Lanius.Std
