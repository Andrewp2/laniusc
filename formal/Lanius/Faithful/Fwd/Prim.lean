import Lanius.Faithful.Fwd.PrimStep
import Lanius.Faithful.Safe.Prims

/-! # Forward: the prims complete in Core

`size_of<T>()` and `typed_slice_from_storage<T>(p, 1)` complete (their values
and states then come from `sizeOf_call` and `slice_call`), and so do
`boxed<T>(value)`, within its cost `boxCost`, and `unbox<T>(box)`. -/

namespace Lanius.Faithful

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (State Completion evalExpr evalExprs evalPlace execStmt ResolvedPlace restoreLocals
  mapRawNominalSlice)

/-- An empty raw view of a word element type. -/
theorem map_empty {P : Core.Program} {s : State} {T : Core.Ty} {a w : Nat}
    (kind : (∃ id, T = .structure id) ∨ ∃ id, T = .enumeration id) (hw : NativeLayout.valueWords? P T = some w)
    (pos : 0 < w) : mapRawNominalSlice P s T a 0 = .done (.rawSlice T a 0) s := by
  have nz : (w == 0) = false := by simp only [beq_eq_false_iff_ne]; omega
  rcases kind with ⟨id, rfl⟩ | ⟨id, rfl⟩ <;> simp [mapRawNominalSlice, hw, nz]

section
variable {sp : SrcProgram} {st : State}

/-- `size_of<t>()`'s body completes. -/
theorem sizeOf_body_fwd {t : SrcType} {w : Nat} (el : wordElement sp.decls t = true)
    (hw : NativeLayout.valueWords? sp.toCore t.toCore = some w) (inv : Inv st) :
    ∃ c st', Ev (fun k => execStmt k sp.toCore st (sizeOfFunc t).body.toCore) c st' := by
  obtain ⟨slice, kind⟩ := sliceFrom_word el
  have pos := valueWords_pos kind hw
  have most := valueWords_le kind hw
  simp only [NativeLayout.maxWords] at most
  simp only [sizeOfFunc, SrcStmt.toCore, SrcExpr.toCore, SrcEff.toCore, SrcOp.toCore, SrcType.toCore,
    SrcType.toScalar, UintTy.toCore, slice, bv_zero]
  -- the null pointer, the empty view, its stride
  have inv1 := inv.bindLocal 32 (.pointer 0)
  have e2 : Ev (fun k => evalExpr k sp.toCore (st.bindLocal 32 (.pointer 0))
      (.typedSliceFromRawParts t.toCore (.local 32) (.value (.signed .i32 0))))
      (.rawSlice t.toCore 0 0) (st.bindLocal 32 (.pointer 0)) :=
    typedSlice_fwd (local_fwd (local?_bindLocal_self inv 32 _)) (value_fwd _) (map_empty kind hw pos)
  generalize hs1 : st.bindLocal 32 (.pointer 0) = s1 at inv1 e2
  have inv2 := inv1.bindLocal 58 (.rawSlice t.toCore 0 0)
  have e3 : Ev (fun k => evalExpr k sp.toCore (s1.bindLocal 58 (.rawSlice t.toCore 0 0))
      (.intrinsic .sliceStride (.local 58))) (.signed .isize (-((8 * w : Nat) : Int)))
      (s1.bindLocal 58 (.rawSlice t.toCore 0 0)) :=
    stride_fwd (local_fwd (local?_bindLocal_self inv1 58 _)) (stride_word kind hw)
  generalize hs2 : s1.bindLocal 58 (.rawSlice t.toCore 0 0) = s2 at inv2 e3
  have known := local?_bindLocal_self inv2 113 (.signed .isize (-((8 * w : Nat) : Int)))
  generalize hs3 : s2.bindLocal 113 (.signed .isize (-((8 * w : Nat) : Int))) = s3 at known
  -- the negative stride's branch returns its negation
  have zero : Ev (fun k => evalExpr k sp.toCore s3 (.cast (.signed .isize) (.value (.signed .i32 0))))
      (.signed .isize 0) s3 :=
    cast_fwd (value_fwd _) (by rw [toCore_target']; exact cast_isize (by decide) (by decide) _)
  have test : Ev (fun k => evalExpr k sp.toCore s3 (.binary .less (.local 113)
      (.cast (.signed .isize) (.value (.signed .i32 0))))) (.boolean true) s3 := by
    refine binary_fwd (by decide) (by decide) (local_fwd known) zero ?_
    rw [toCore_target', signed_less]
    simp only [Except.ok.injEq, Value.boolean.injEq, decide_eq_true_eq]
    omega
  have negated : Ev (fun k => evalExpr k sp.toCore s3 (.binary .subtract
      (.cast (.signed .isize) (.value (.signed .i32 0))) (.local 113)))
      (.signed .isize ((8 * w : Nat) : Int)) s3 := by
    refine binary_fwd (by decide) (by decide) zero (local_fwd known) ?_
    rw [toCore_target', signed_subtract, Int.sub_neg, Int.zero_add, wrap_isize_of (by omega) (by omega)]
  have back : Ev (fun k => evalExpr k sp.toCore s3 (.cast (.unsigned .usize) (.binary .subtract
      (.cast (.signed .isize) (.value (.signed .i32 0))) (.local 113))))
      (.unsigned .usize (8 * w)) s3 :=
    cast_fwd negated (by rw [toCore_target']; exact cast_usize_nat (by omega) _)
  have rest := sequence_ret_fwd (b := Core.Stmt.returnValue (some (.cast (.unsigned .usize) (.local 113))))
    (if_fwd (b := Core.Stmt.skip) test (by simpa using return_fwd back))
  subst hs3 hs2 hs1
  exact ⟨_, _, letLocal_fwd (value_fwd _) (letLocal_fwd e2 (letLocal_fwd e3 rest))⟩

/-- A call of `size_of<t>()` completes. -/
theorem sizeOf_call_fwd {t : SrcType} {w : Nat} {callee : Nat} (found : sp.funcs[callee]? = some (sizeOfFunc t))
    (el : wordElement sp.decls t = true) (hw : NativeLayout.valueWords? sp.toCore t.toCore = some w) (inv : Inv st) :
    ∃ v st', Ev (fun k => evalExpr k sp.toCore st (.call callee [])) v st' := by
  obtain ⟨c, completed, body⟩ := sizeOf_body_fwd (st := ({ st with locals := [] } : State).bindLocals
    (paramBindings (sizeOfFunc t).params [])) el hw (Same.start inv _)
  obtain ⟨k, hk⟩ := body.at
  obtain ⟨w', -, -, -, rfl, -⟩ := sizeOf_body el (Same.start inv _) hk
  exact ⟨_, _, call_fwd exprs_nil_fwd found rfl body rfl⟩

/-- A one-element raw view of a word element type, over a range that checks. -/
theorem map_single {P : Core.Program} {s : State} {T : Core.Ty} {A w : Nat}
    (kind : (∃ id, T = .structure id) ∨ ∃ id, T = .enumeration id) (hw : NativeLayout.valueWords? P T = some w)
    (pos : 0 < w) (big : 8 * w ≤ A + 8) (ranged : s.heap.checkRange (A + 8 - 8 * w) (8 * w) 8 = .ok ()) :
    mapRawNominalSlice P s T A 1 = .done (.rawSlice T A 1) s := by
  have nz : (w == 0) = false := by simp only [beq_eq_false_iff_ne]; omega
  have bytes : Int.toNat 1 * w * NativeLayout.wordBytes = 8 * w := by
    simp only [NativeLayout.wordBytes, show Int.toNat 1 = 1 from rfl]; omega
  have fits : ¬ (A + NativeLayout.wordBytes < 8 * w) := by simp only [NativeLayout.wordBytes]; omega
  have one : (Int.toNat 1 == 0) = false := rfl
  have ranged' : s.heap.checkRange (A + 8 - 8 * w) (8 * w) NativeLayout.wordBytes = .ok () := ranged
  rcases kind with ⟨id, rfl⟩ | ⟨id, rfl⟩ <;>
  · unfold mapRawNominalSlice
    simp only [show ¬ ((1 : Int) < 0) by decide, if_false, Bool.not_true, Bool.false_eq_true, hw, nz, one,
      bytes, fits, show A + NativeLayout.wordBytes - 8 * w = A + 8 - 8 * w from rfl, ranged']
    rfl

/-- `typed_slice_from_storage<t>(storage, 1)`'s body completes on storage
`a` whose range checks. -/
theorem slice_body_fwd {t : SrcType} {w a : Nat} (el : wordElement sp.decls t = true)
    (hw : NativeLayout.valueWords? sp.toCore t.toCore = some w) (inv : Inv st)
    (storage : st.local? 28 = some (.pointer a)) (one : st.local? 42 = some (.signed .i32 1))
    (ranged : st.heap.checkRange a (8 * w) 8 = .ok ()) (room : a + 8 * w ≤ 2 ^ 64) :
    ∃ c st', Ev (fun k => execStmt k sp.toCore st (sliceFunc t).body.toCore) c st' := by
  obtain ⟨slice, kind⟩ := sliceFrom_word el
  have pos := valueWords_pos kind hw
  have most := valueWords_le kind hw
  simp only [NativeLayout.maxWords] at most
  simp only [sliceFunc, SrcStmt.toCore, SrcExpr.toCore, SrcEff.toCore, SrcOp.toCore, SrcType.toCore,
    SrcType.toScalar, UintTy.toCore, slice, bv_zero, bv_eight]
  -- the assertion
  have assertion : Ev (fun k => execStmt k sp.toCore st (.expression (.intrinsic .assert
      (.binary .greaterEqual (.local 42) (.value (.signed .i32 0)))))) .next st := by
    refine expression_fwd (assert_fwd (binary_fwd (by decide) (by decide) (local_fwd one) (value_fwd _) ?_))
    rw [toCore_target', signed_greaterEqual]
    rfl
  -- the empty view and its stride
  have inv1 := inv.bindLocal 97 (.pointer 0)
  have e2 : Ev (fun k => evalExpr k sp.toCore (st.bindLocal 97 (.pointer 0))
      (.typedSliceFromRawParts t.toCore (.local 97) (.value (.signed .i32 0))))
      (.rawSlice t.toCore 0 0) (st.bindLocal 97 (.pointer 0)) :=
    typedSlice_fwd (local_fwd (local?_bindLocal_self inv 97 _)) (value_fwd _) (map_empty kind hw pos)
  have inv2 := inv1.bindLocal 123 (.rawSlice t.toCore 0 0)
  have e3 : Ev (fun k => evalExpr k sp.toCore ((st.bindLocal 97 (.pointer 0)).bindLocal 123 (.rawSlice t.toCore 0 0))
      (.intrinsic .sliceStride (.local 123))) (.signed .isize (-((8 * w : Nat) : Int)))
      ((st.bindLocal 97 (.pointer 0)).bindLocal 123 (.rawSlice t.toCore 0 0)) :=
    stride_fwd (local_fwd (local?_bindLocal_self inv1 123 _)) (stride_word kind hw)
  generalize hs2 : (st.bindLocal 97 (.pointer 0)).bindLocal 123 (.rawSlice t.toCore 0 0) = s2 at inv2 e3
  have known := local?_bindLocal_self inv2 178 (.signed .isize (-((8 * w : Nat) : Int)))
  have one2 : s2.local? 42 = some (.signed .i32 1) := by
    rw [← hs2]
    exact local?_bindLocal_other (by decide) _ (local?_bindLocal_other (by decide) _ one)
  have storage2 : s2.local? 28 = some (.pointer a) := by
    rw [← hs2]
    exact local?_bindLocal_other (by decide) _ (local?_bindLocal_other (by decide) _ storage)
  have heap2 : s2.heap = st.heap := by rw [← hs2]; rfl
  have inv3 := inv2.bindLocal 178 (.signed .isize (-((8 * w : Nat) : Int)))
  have one3 := local?_bindLocal_other (id := 178) (by decide) (.signed .isize (-((8 * w : Nat) : Int))) one2
  have storage3 := local?_bindLocal_other (id := 178) (by decide) (.signed .isize (-((8 * w : Nat) : Int))) storage2
  generalize hs3 : s2.bindLocal 178 (.signed .isize (-((8 * w : Nat) : Int))) = s3 at known one3 storage3 inv3
  have heap3 : s3.heap = st.heap := by rw [← hs3]; exact heap2
  have zero : Ev (fun k => evalExpr k sp.toCore s3 (.cast (.signed .isize) (.value (.signed .i32 0))))
      (.signed .isize 0) s3 :=
    cast_fwd (value_fwd _) (by rw [toCore_target']; exact cast_isize (by decide) (by decide) _)
  -- the branch for forward strides and empty views, not taken
  have test : Ev (fun k => evalExpr k sp.toCore s3 (.binary .logicalOr
      (.binary .greaterEqual (.local 178) (.cast (.signed .isize) (.value (.signed .i32 0))))
      (.binary .equal (.local 42) (.value (.signed .i32 0))))) (.boolean false) s3 := by
    refine or_false_fwd (s1 := s3) ?_ ?_
    · refine binary_fwd (by decide) (by decide) (local_fwd known) zero ?_
      rw [toCore_target', signed_greaterEqual]
      simp only [Except.ok.injEq, Value.boolean.injEq, decide_eq_false_iff_not]
      omega
    · refine binary_fwd (by decide) (by decide) (local_fwd one3) (value_fwd _) ?_
      rw [toCore_target', signed_equal]
      rfl
  -- the last word's offset
  have negated : Ev (fun k => evalExpr k sp.toCore s3 (.cast (.unsigned .usize) (.binary .subtract
      (.cast (.signed .isize) (.value (.signed .i32 0))) (.local 178))))
      (.unsigned .usize (8 * w)) s3 := by
    refine cast_fwd (binary_fwd (v := .signed .isize ((8 * w : Nat) : Int)) (by decide) (by decide) zero (local_fwd known) ?_) ?_
    · rw [toCore_target', signed_subtract, Int.sub_neg, Int.zero_add, wrap_isize_of (by omega) (by omega)]
    · rw [toCore_target', cast_usize_int (by omega) (by omega)]
      simp only [Except.ok.injEq, Value.unsigned.injEq, true_and]
      omega
  have count : Ev (fun k => evalExpr k sp.toCore s3 (.cast (.unsigned .usize) (.local 42)))
      (.unsigned .usize 1) s3 :=
    cast_fwd (local_fwd one3) (by rw [toCore_target', cast_usize_int (by decide) (by decide)]; rfl)
  have times : Ev (fun k => evalExpr k sp.toCore s3 (.binary .multiply (.cast (.unsigned .usize) (.binary .subtract
      (.cast (.signed .isize) (.value (.signed .i32 0))) (.local 178))) (.cast (.unsigned .usize) (.local 42))))
      (.unsigned .usize (8 * w)) s3 := by
    refine binary_fwd (by decide) (by decide) negated count ?_
    rw [toCore_target', unsigned_multiply, Nat.mul_one, Nat.mod_eq_of_lt (by omega)]
  have offset : Ev (fun k => evalExpr k sp.toCore s3 (.binary .subtract (.binary .multiply
      (.cast (.unsigned .usize) (.binary .subtract (.cast (.signed .isize) (.value (.signed .i32 0))) (.local 178)))
      (.cast (.unsigned .usize) (.local 42))) (.value (.unsigned .usize 8))))
      (.unsigned .usize (8 * w - 8)) s3 := by
    refine binary_fwd (by decide) (by decide) times (value_fwd _) ?_
    rw [toCore_target', unsigned_subtract]
    simp only [Except.ok.injEq, Value.unsigned.injEq, true_and]
    omega
  have inv4 := inv3.bindLocal 321 (.unsigned .usize (8 * w - 8))
  have off4 := local?_bindLocal_self inv3 321 (.unsigned .usize (8 * w - 8))
  have one4 := local?_bindLocal_other (id := 321) (by decide) (.unsigned .usize (8 * w - 8)) one3
  have storage4 := local?_bindLocal_other (id := 321) (by decide) (.unsigned .usize (8 * w - 8)) storage3
  generalize hs4 : s3.bindLocal 321 (.unsigned .usize (8 * w - 8)) = s4 at inv4 off4 one4 storage4
  have heap4 : s4.heap = st.heap := by rw [← hs4]; exact heap3
  -- the view of the storage
  have view : Ev (fun k => evalExpr k sp.toCore s4 (.typedSliceFromRawParts t.toCore
      (.binary .add (.local 28) (.local 321)) (.local 42))) (.rawSlice t.toCore (a + 8 * w - 8) 1) s4 := by
    refine typedSlice_fwd (a := a + 8 * w - 8) (binary_fwd (by decide) (by decide) (local_fwd storage4) (local_fwd off4) ?_)
      (local_fwd one4) ?_
    · rw [toCore_target', pointer_add, show (a + (8 * w - 8)) % 2 ^ 64 = a + 8 * w - 8 by
        rw [Nat.mod_eq_of_lt (by omega)]; omega]
    · refine map_single kind hw pos (by omega) ?_
      rw [heap4, show a + 8 * w - 8 + 8 - 8 * w = a by omega]
      exact ranged
  have inv5 := inv4.bindLocal 394 (.rawSlice t.toCore (a + 8 * w - 8) 1)
  have ret := return_fwd (P := sp.toCore) (local_fwd (local?_bindLocal_self inv4 394 (.rawSlice t.toCore (a + 8 * w - 8) 1)))
  subst hs4 hs3 hs2
  exact ⟨_, _, sequence_next_fwd assertion (letLocal_fwd (value_fwd _) (letLocal_fwd e2 (letLocal_fwd e3
    (sequence_next_fwd (if_fwd (a := Core.Stmt.letLocal 268 (.slice t.toCore)
        (.typedSliceFromRawParts t.toCore (.local 28) (.local 42)) (.returnValue (some (.local 268)))) test
      (by simpa using skip_fwd))
      (letLocal_fwd offset (letLocal_fwd view ret))))))⟩

/-- A call of `typed_slice_from_storage<t>(p, 1)` on storage `a` whose range
checks completes. -/
theorem slice_call_fwd {t : SrcType} {w a callee : Nat} {p : Core.Expr}
    (found : sp.funcs[callee]? = some (sliceFunc t)) (el : wordElement sp.decls t = true)
    (hw : NativeLayout.valueWords? sp.toCore t.toCore = some w) (inv : Inv st)
    (storage : Ev (fun k => evalExpr k sp.toCore st p) (.pointer a) st)
    (ranged : st.heap.checkRange a (8 * w) 8 = .ok ()) (room : a + 8 * w ≤ 2 ^ 64) :
    ∃ v st', Ev (fun k => evalExpr k sp.toCore st (.call callee [p, .value (.signed .i32 1)])) v st' := by
  have start : (({ st with locals := [] } : State).bindLocals
      (paramBindings (sliceFunc t).params [.pointer a, .signed .i32 1])) =
      (({ st with locals := [] } : State).bindLocal 28 (.pointer a)).bindLocal 42 (.signed .i32 1) := rfl
  have inv1 : Inv (({ st with locals := [] } : State).bindLocal 28 (.pointer a)) := inv.clear.bindLocal _ _
  obtain ⟨c, completed, body⟩ := slice_body_fwd (st := (({ st with locals := [] } : State).bindLocal 28
    (.pointer a)).bindLocal 42 (.signed .i32 1)) el hw (inv1.bindLocal _ _)
    (local?_bindLocal_other (by decide) _ (local?_bindLocal_self inv.clear 28 _))
    (local?_bindLocal_self inv1 42 _) ranged room
  rw [← start] at body
  obtain ⟨k, hk⟩ := body.at
  rw [start] at hk
  obtain ⟨w', -, -, rfl, -⟩ := slice_body el (inv1.bindLocal _ _)
    (local?_bindLocal_other (by decide) _ (local?_bindLocal_self inv.clear 28 _))
    (local?_bindLocal_self inv1 42 _) hk
  exact ⟨_, _, call_fwd (exprs_cons_fwd storage (exprs_cons_fwd (value_fwd _) exprs_nil_fwd)) found rfl body rfl⟩

/-- The allocator's 8-aligned address is at most 8 past the cursor. -/
theorem allocationAddress_le (heap : Memory.Heap) : heap.allocationAddress 8 ≤ heap.nextAddress + 8 := by
  have division := Nat.mod_add_div (max heap.nextAddress 1 + 8 - 1) 8
  change ((max heap.nextAddress 1 + 8 - 1) / 8) * 8 ≤ heap.nextAddress + 8
  dsimp only [Lanius.Address] at *
  omega

/-- `boxed<t>(value)`'s body completes, growing the heap by at most
`8 * w + 8` bytes, on an unbounded allocator. -/
theorem boxed_live {boxes : Boxes} {t : SrcType} {id sizeOf slice panic w : Nat} {values ps : List Value}
    (sizeOfFound : sp.funcs[sizeOf]? = some (sizeOfFunc t)) (sliceFound : sp.funcs[slice]? = some (sliceFunc t))
    (el : wordElement sp.decls t = true) (hw : NativeLayout.valueWords? sp.toCore t.toCore = some w) (inv : Inv st)
    (args : VRels sp.toCore boxes st.heap ((boxedFunc t id sizeOf slice panic).params.map SrcParam.ty) values ps)
    (budget : st.heap.nextAddress + (8 * w + 8) ≤ 2 ^ 64) (fr : st.heap.remaining = none) :
    ∃ compl completed v, Ev (fun k => execStmt k sp.toCore (({ st with locals := [] } : State).bindLocals
        (paramBindings (boxedFunc t id sizeOf slice panic).params values))
        (boxedFunc t id sizeOf slice panic).body.toCore) compl completed ∧
      CallResult (boxedFunc t id sizeOf slice panic).ret compl v ∧
      completed.heap.nextAddress ≤ st.heap.nextAddress + (8 * w + 8) ∧ completed.heap.remaining = none := by
  obtain ⟨-, kind⟩ := sliceFrom_word el
  have pos := valueWords_pos kind hw
  simp only [boxedFunc, List.map_cons, List.map_nil] at args
  cases args with
  | cons r rest =>
  cases rest with
  | nil =>
  rename_i x p
  have start : (({ st with locals := [] } : State).bindLocals (paramBindings (boxedFunc t id sizeOf slice panic).params
      [x])) = ({ st with locals := [] } : State).bindLocal 9 x := rfl
  rw [start]
  have inv0 := inv.clear.bindLocal 9 x
  have x0 := local?_bindLocal_self inv.clear 9 x
  have heap0 : (({ st with locals := [] } : State).bindLocal 9 x).heap = st.heap := rfl
  generalize hs0 : ({ st with locals := [] } : State).bindLocal 9 x = s0 at inv0 x0 heap0
  simp only [boxedFunc, SrcStmt.toCore, SrcEff.toCore, SrcEff.toCoreList, SrcExpr.toCore, SrcType.toCore, SrcOp.toCore,
    SrcType.literal, List.map_cons, List.map_nil, bv_zero, bv_one, Nat.reducePow, UintTy.toCore]
  -- the storage's size
  obtain ⟨v1, s1, call1⟩ := sizeOf_call_fwd sizeOfFound el hw inv0
  obtain ⟨k1, hk1⟩ := call1.at
  obtain ⟨w', hw', -, -, rfl, same1, locals1⟩ := sizeOf_call sizeOfFound el inv0 hk1
  rw [hw, Option.some.injEq] at hw'
  subst hw'
  have inv1 := same1.inv.bindLocal 39 (.unsigned .usize (8 * w))
  have x1 := local?_bindLocal_other (id := 39) (by decide) (.unsigned .usize (8 * w)) (local?_step same1.step locals1 x0)
  have n1 := local?_bindLocal_self same1.inv 39 (.unsigned .usize (8 * w))
  have heap1 : (s1.bindLocal 39 (.unsigned .usize (8 * w))).heap = st.heap := same1.heap.trans heap0
  generalize hq1 : s1.bindLocal 39 (.unsigned .usize (8 * w)) = q1 at inv1 x1 n1 heap1
  -- the allocation
  have al := Memory.Heap.allocate_of_budget (heap := q1.heap) (size := 8 * w) (alignment := 8) (by decide)
    (by rw [heap1, fr]; rfl)
  generalize ha : q1.heap.allocationAddress 8 = a at al
  generalize hH : q1.heap.allocatedBytes (8 * w) 8 none = H1 at al
  have allocE := alloc_fwd (P := sp.toCore) (local_fwd n1) (value_fwd (.unsigned .usize 8)) al
  have apos : 0 < a := by rw [← ha]; exact Memory.Heap.allocationAddress_pos _ (by decide)
  have ale : a ≤ st.heap.nextAddress + 8 := by rw [← ha, ← heap1]; exact allocationAddress_le _
  have room : a + 8 * w ≤ 2 ^ 64 := by aomega
  have next1 : H1.nextAddress = a + 8 * w := by
    rw [← hH, ← ha]
    show q1.heap.allocationAddress 8 + max (8 * w) 1 = _
    aomega
  have rem1 : H1.remaining = none := by rw [← hH]; rfl
  have below1 : Memory.HeapBlocksBelowNext H1 := by
    rw [← hH]; exact Memory.Heap.allocatedBytes_below inv1.below (by decide)
  have unique1 : Memory.HeapBlockBasesUnique H1 := by
    rw [← hH]; exact Memory.Heap.allocatedBytes_unique inv1.below inv1.unique (by decide)
  have zeros : ∀ i, i < 8 * w → H1.loadByte a i = .ok 0 := by
    rw [← hH, ← ha]
    exact fun i lt => Memory.Heap.allocatedBytes_read inv1.below (by decide) lt
  have ranged : H1.checkRange a (8 * w) 8 = .ok () := by
    rw [← hH, ← ha]
    exact allocated_checkRange inv1.below (by omega) (by decide)
  have inv2 : Inv { q1 with heap := H1 } := ⟨inv1.views, inv1.fresh, below1, unique1⟩
  have inv3 := inv2.bindLocal 86 (.pointer a)
  have ptr := local?_bindLocal_self inv2 86 (.pointer a)
  have x3 := local?_bindLocal_other (id := 86) (by decide) (.pointer a)
    (show ({ q1 with heap := H1 } : State).local? 9 = some x from x1)
  generalize hq2 : ({ q1 with heap := H1 } : State).bindLocal 86 (.pointer a) = q2 at inv3 ptr x3
  have heap2 : q2.heap = H1 := by rw [← hq2]; rfl
  -- the null check
  have test : Ev (fun k => evalExpr k sp.toCore q2 (.binary .equal (.local 86) (.value (.pointer 0))))
      (.boolean false) q2 := by
    refine binary_fwd (by decide) (by decide) (local_fwd ptr) (value_fwd _) ?_
    rw [toCore_target', pointer_equal]
    simp only [Except.ok.injEq, Value.boolean.injEq, beq_eq_false_iff_ne, ne_eq]
    aomega
  have check := if_fwd (a := Core.Stmt.expression (.call panic [])) (b := Core.Stmt.skip) test
    (by simpa using skip_fwd)
  -- the view
  obtain ⟨v3, s3, call3⟩ := slice_call_fwd sliceFound el hw inv3 (local_fwd ptr) (heap2 ▸ ranged) room
  obtain ⟨k3, hk3⟩ := call3.at
  obtain ⟨w', hw', -, rfl, same3, locals3⟩ := slice_call sliceFound el inv3 (fun h => local_eval ptr h) hk3
  rw [hw, Option.some.injEq] at hw'
  subst hw'
  have hmod : (a + (8 * w - 8)) % 2 ^ 64 = a + 8 * w - 8 := by rw [Nat.mod_eq_of_lt (by aomega)]; aomega
  rw [hmod] at call3
  have inv4 := same3.inv.bindLocal 203 (.rawSlice t.toCore (a + 8 * w - 8) 1)
  have view4 := local?_bindLocal_self same3.inv 203 (.rawSlice t.toCore (a + 8 * w - 8) 1)
  have x4 := local?_bindLocal_other (id := 203) (by decide) (.rawSlice t.toCore (a + 8 * w - 8) 1)
    (local?_step same3.step locals3 x3)
  have ptr4 := local?_bindLocal_other (id := 203) (by decide) (.rawSlice t.toCore (a + 8 * w - 8) 1)
    (local?_step same3.step locals3 ptr)
  have heap4 : (s3.bindLocal 203 (.rawSlice t.toCore (a + 8 * w - 8) 1)).heap = H1 := same3.heap.trans heap2
  generalize hq4 : s3.bindLocal 203 (.rawSlice t.toCore (a + 8 * w - 8) 1) = q4 at inv4 view4 x4 ptr4 heap4
  -- the write
  obtain ⟨rb, hrb, baseRun⟩ := place_local_fwd (P := sp.toCore) view4
  have placeRun := place_index_fwd baseRun hrb (value_fwd (.signed .i32 0))
    (show Semantics.integerIndex (.signed .i32 0) = .ok 0 from rfl) (by decide) (elementAddress_zero kind hw pos)
  have spec : Semantics.NativeStoreSpec NativeLayout.maxDepth sp.toCore t.toCore x (8 * w) :=
    store_spec NativeLayout.maxDepth r (wordElement_wordType el) hw (Nat.le_refl _)
  have readable : q4.heap.Readable (a + 8 * w - 8 + 8 - 8 * w) (8 * w) := by
    rw [heap4, show a + 8 * w - 8 + 8 - 8 * w = a by aomega]
    exact fun i lt => ⟨0, zeros i lt⟩
  obtain ⟨after, write, -, region⟩ := spec q4 q4.heap (a + 8 * w - 8) (by aomega) readable (heap4 ▸ unique1)
  have written : Semantics.writeResolvedPlaceNative sp.toCore q4 { rb with value := none, raw := some (t.toCore,
      a + 8 * w - 8) } x = .ok { q4 with heap := after } := by
    simp only [Semantics.writeResolvedPlaceNative, write]
    rfl
  have synced : (if ({ rb with value := none, raw := some (t.toCore, a + 8 * w - 8) } : ResolvedPlace).viewFreeRootWrite x
      then .ok { q4 with heap := after } else match ({ rb with value := none, raw := some (t.toCore, a + 8 * w - 8) } :
        ResolvedPlace).raw with
      | none => Semantics.syncI32ViewsToHeap { q4 with heap := after }
      | some _ => Semantics.syncI32ViewsFromHeap { q4 with heap := after }) = .ok { q4 with heap := after } := by
    simp only [Semantics.ResolvedPlace.viewFreeRootWrite, Option.isNone_some, Bool.false_and,
      Bool.false_eq_true, if_false]
    exact syncFrom_ok (st := { q4 with heap := after }) inv4.views
  have assignE := expression_fwd (assign_fwd placeRun (local_fwd x4) written synced)
  -- the returned box
  have retE := return_fwd (P := sp.toCore) (struct_fwd (id := id)
    (exprs_cons_fwd (local_fwd (show ({ q4 with heap := after } : State).local? 86 = some (.pointer a) from ptr4))
      exprs_nil_fwd))
  refine ⟨.returned (some (.structure id [.pointer a])), _, _, letLocal_fwd call1 (by
    rw [hq1]
    exact letLocal_fwd allocE (by
      rw [hq2]
      exact sequence_next_fwd check (letLocal_fwd call3 (by
        rw [hq4]
        exact sequence_next_fwd assignE retE)))), rfl, ?_, ?_⟩
  · show after.nextAddress ≤ _
    rw [region.frontier, heap4, next1]
    aomega
  · show after.remaining = none
    rw [region.budget, heap4, rem1]

/-- `unbox<t>(box)`'s body completes, leaving the heap as it was. -/
theorem unbox_live {boxes : Boxes} {t : SrcType} {id slice : Nat} {values ps : List Value}
    (sliceFound : sp.funcs[slice]? = some (sliceFunc t)) (el : wordElement sp.decls t = true)
    (box : boxes id = some t) (inv : Inv st)
    (args : VRels sp.toCore boxes st.heap ((unboxFunc t id slice).params.map SrcParam.ty) values ps) :
    ∃ compl completed v, Ev (fun k => execStmt k sp.toCore (({ st with locals := [] } : State).bindLocals
        (paramBindings (unboxFunc t id slice).params values)) (unboxFunc t id slice).body.toCore) compl completed ∧
      CallResult (unboxFunc t id slice).ret compl v ∧ completed.heap = st.heap := by
  obtain ⟨-, kind⟩ := sliceFrom_word el
  simp only [unboxFunc, List.map_cons, List.map_nil] at args
  cases args with
  | cons r rest =>
  cases rest with
  | nil =>
  rename_i x p
  cases r with
  | scalar s => exact s.elim
  | struct none _ => rw [box] at none; cases none
  | box found wv pos room ranged read rel =>
  rename_i t' a w y
  rw [box, Option.some.injEq] at found
  subst found
  have start : (({ st with locals := [] } : State).bindLocals (paramBindings (unboxFunc t id slice).params
      [.structure id [.pointer a]])) = ({ st with locals := [] } : State).bindLocal 9 (.structure id [.pointer a]) :=
    rfl
  rw [start]
  have inv0 := inv.clear.bindLocal 9 (.structure id [.pointer a])
  have x0 := local?_bindLocal_self inv.clear 9 (.structure id [.pointer a])
  have heap0 : (({ st with locals := [] } : State).bindLocal 9 (.structure id [.pointer a])).heap = st.heap := rfl
  generalize hs0 : ({ st with locals := [] } : State).bindLocal 9 (.structure id [.pointer a]) = s0 at inv0 x0 heap0
  simp only [unboxFunc, SrcStmt.toCore, SrcEff.toCore, SrcExpr.toCore, SrcType.toCore,
    List.map_cons, List.map_nil, bv_zero, bv_one]
  have storageE : Ev (fun k => evalExpr k sp.toCore s0 (.field (.local 9) 0)) (.pointer a) s0 :=
    field_fwd (local_fwd x0) rfl
  have storage : ∀ {j u s}, evalExpr j sp.toCore s0 (.field (.local 9) 0) = .done u s → u = .pointer a ∧ s = s0 := by
    intro j u s h
    obtain ⟨_, sid, fields, -, base, hf⟩ := field_inv h
    obtain ⟨hv, rfl⟩ := local_eval x0 base
    simp only [Value.structure.injEq] at hv
    obtain ⟨rfl, rfl⟩ := hv
    simp only [List.getElem?_cons_zero, Option.some.injEq] at hf
    exact ⟨hf.symm, rfl⟩
  obtain ⟨v1, s1, call1⟩ := slice_call_fwd sliceFound el wv inv0 storageE (heap0 ▸ ranged) room
  obtain ⟨k1, hk1⟩ := call1.at
  obtain ⟨w', hw', -, rfl, same, -⟩ := slice_call sliceFound el inv0 storage hk1
  rw [wv, Option.some.injEq] at hw'
  subst hw'
  rw [show (a + (8 * w - 8)) % 2 ^ 64 = a + 8 * w - 8 by rw [Nat.mod_eq_of_lt (by omega)]; omega] at call1
  have view1 := local?_bindLocal_self same.inv 39 (.rawSlice t.toCore (a + 8 * w - 8) 1)
  have heap1 : (s1.bindLocal 39 (.rawSlice t.toCore (a + 8 * w - 8) 1)).heap = st.heap := same.heap.trans heap0
  have readE : Semantics.readRawSliceIndex sp.toCore (s1.bindLocal 39 (.rawSlice t.toCore (a + 8 * w - 8) 1))
      t.toCore (a + 8 * w - 8) 1 0 = .ok y := by
    simp only [Semantics.readRawSliceIndex, show ¬ (0 ≥ 1) by decide, if_false, elementAddress_zero kind wv pos]
    rw [heap1]
    exact read
  have idxE := index_fwd (local_fwd view1) (value_fwd (.signed .i32 0))
    (show Semantics.integerIndex (.signed .i32 0) = .ok 0 from rfl) readE
  exact ⟨.returned (some y), _, y, letLocal_fwd call1 (return_fwd idxE), rfl, heap1⟩

end

/-- The heap cost of a call of `boxed<t>`: the storage, and up to 8 bytes of
alignment. -/
def boxCost (sp : SrcProgram) (c : Nat) : Nat :=
  match sp.funcs[c]? with
  | none => 0
  | some f =>
    match f.params with
    | [] => 0
    | [p] => 8 * (NativeLayout.valueWords? (declsCore sp.decls) p.ty.toCore).getD 0 + 8
    | _ :: _ :: _ => 0

theorem boxCost_boxed {sp : SrcProgram} {c : Nat} {t : SrcType} {id sizeOf slice panic w : Nat}
    (found : sp.funcs[c]? = some (boxedFunc t id sizeOf slice panic))
    (hw : NativeLayout.valueWords? sp.toCore t.toCore = some w) : boxCost sp c = 8 * w + 8 := by
  rw [valueWords_toCore] at hw
  simp only [boxCost, found, boxedFunc, hw, Option.getD_some]

end Lanius.Faithful
