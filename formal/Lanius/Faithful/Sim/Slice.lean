import Lanius.Faithful.Sim.SizeOf

/-! # Core runs of `typed_slice_from_storage<T>(storage, 1)`

On storage at `a` of a word element `T` of `w` words, the view has element
0's word 0 at the storage's last word, `a + 8 * w - 8` (modulo `2 ^ 64`). -/

namespace Lanius.Faithful

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (State Completion evalExpr evalExprs execStmt restoreLocals wrapSigned wrapUnsignedInt
  evalScalarCast evalBinaryValue mapRawNominalSlice)

theorem cast_usize_int {n : Int} (low : 0 ≤ n) (high : n < 2 ^ 64) (ty : Core.SignedIntTy) :
    evalScalarCast .x86_64 (.unsigned .usize) (.signed ty n) = .ok (.unsigned .usize n.toNat) := by
  have := wrap_usize_of low high
  simp only [evalScalarCast, Except.ok.injEq, Value.unsigned.injEq, true_and]
  omega

theorem unsigned_multiply (a b : Nat) :
    evalBinaryValue .x86_64 .multiply (.unsigned .usize a) (.unsigned .usize b) =
      .ok (.unsigned .usize ((a * b) % 2 ^ 64)) := by
  have hb : (2 : Nat) ^ Core.Target.x86_64.pointerWidth.bits = 18446744073709551616 := by decide
  simp [evalBinaryValue, Semantics.evalUnsignedBinary, Semantics.wrapUnsigned, Semantics.unsignedModulus,
    Core.UnsignedIntTy.bits, hb]

theorem unsigned_subtract (a b : Nat) :
    evalBinaryValue .x86_64 .subtract (.unsigned .usize a) (.unsigned .usize b) =
      .ok (.unsigned .usize ((a + 2 ^ 64 - b % 2 ^ 64) % 2 ^ 64)) := by
  have hb : (2 : Nat) ^ Core.Target.x86_64.pointerWidth.bits = 18446744073709551616 := by decide
  simp [evalBinaryValue, Semantics.evalUnsignedBinary, Semantics.wrapUnsigned, Semantics.unsignedModulus,
    Core.UnsignedIntTy.bits, hb]

theorem pointer_add (a n : Nat) :
    evalBinaryValue .x86_64 .add (.pointer a) (.unsigned .usize n) = .ok (.pointer ((a + n) % 2 ^ 64)) := by
  simp only [evalBinaryValue, Semantics.pointerOffset, Except.ok.injEq, Value.pointer.injEq, Int.ofNat_eq_natCast,
    Bool.false_eq_true, if_false]
  have : (2 : Int) ^ Core.Target.x86_64.pointerWidth.bits = 18446744073709551616 := by decide
  rw [this]
  change (((a : Int) + n) % 18446744073709551616).toNat = (a + n) % 18446744073709551616
  omega

section
variable {sp : SrcProgram} {k : Nat} {st st' : State} {c : Completion}

/-- The body on storage `a` and length 1. -/
theorem slice_body {t : SrcType} (el : wordElement sp.decls t = true) (inv : Inv st) {a : Nat}
    (storage : st.local? 28 = some (.pointer a)) (one : st.local? 42 = some (.signed .i32 1))
    (run : execStmt k sp.toCore st (sliceFunc t).body.toCore = .done c st') :
    ∃ w, NativeLayout.valueWords? sp.toCore t.toCore = some w ∧ 0 < w ∧
      c = .returned (some (.rawSlice t.toCore ((a + (8 * w - 8)) % 2 ^ 64) 1)) ∧ Same st st' := by
  obtain ⟨slice, kind⟩ := sliceFrom_word el
  simp only [sliceFunc, SrcStmt.toCore, SrcExpr.toCore, SrcEff.toCore, SrcOp.toCore, SrcType.toCore,
    SrcType.toScalar, UintTy.toCore, slice, bv_zero, bv_eight] at run
  -- the assertion
  obtain ⟨_, s1, c1, -, first, rest⟩ := sequence_inv run
  obtain ⟨_, u, -, e, rfl⟩ := expression_inv first
  replace rest := (rest.resolve_right fun h => h.1 rfl).2
  obtain ⟨_, -, cond, -⟩ := assert_inv e
  obtain ⟨_, l, s2, r, -, lr, rr, -⟩ := binary_inv (by decide) (by decide) cond
  obtain ⟨rfl, rfl⟩ := local_eval one lr
  obtain ⟨rfl, rfl⟩ := value_inv rr
  -- the empty view and its stride
  obtain ⟨_, v1, s3, s4, -, e1, b1, rfl⟩ := letLocal_inv rest
  obtain ⟨rfl, rfl⟩ := value_inv e1
  have inv1 := inv.bindLocal 97 (.pointer 0)
  obtain ⟨_, v2, s5, s6, -, e2, b2, rfl⟩ := letLocal_inv b1
  obtain ⟨_, a0, s7, n0, s8, -, p2, n2, m2⟩ := typedSlice_inv e2
  obtain ⟨ha, rfl⟩ := local_eval (local?_bindLocal_self inv 97 _) p2
  obtain ⟨hn, rfl⟩ := value_inv n2
  simp only [Value.pointer.injEq, Value.signed.injEq, true_and] at ha hn
  subst ha hn
  obtain ⟨w, hw, pos, -, rfl, rfl⟩ := map_inv kind m2
  have inv2 := inv1.bindLocal 123 (.rawSlice t.toCore 0 (Int.toNat 0))
  obtain ⟨_, v3, s9, s10, -, e3, b3, rfl⟩ := letLocal_inv b2
  obtain ⟨_, x3, stride, -, l3, hs, rfl⟩ := stride_inv e3
  obtain ⟨rfl, rfl⟩ := local_eval (local?_bindLocal_self inv1 123 _) l3
  rw [stride_word kind hw, Option.some.injEq] at hs
  subst hs
  have inv3 := inv2.bindLocal 178 (.signed .isize (-((8 * w : Nat) : Int)))
  have known := local?_bindLocal_self inv2 178 (.signed .isize (-((8 * w : Nat) : Int)))
  have one3 := local?_bindLocal_other (id := 178) (by decide) (.signed .isize (-((8 * w : Nat) : Int)))
    (local?_bindLocal_other (id := 123) (by decide) (.rawSlice t.toCore 0 (Int.toNat 0))
      (local?_bindLocal_other (id := 97) (by decide) (.pointer 0) one))
  have most := valueWords_le kind hw
  simp only [NativeLayout.maxWords] at most
  -- the branch for forward strides and empty views, not taken
  obtain ⟨_, s11, c2, -, first2, rest2⟩ := sequence_inv b3
  obtain ⟨_, s12, x, -, cond2, branch⟩ := if_inv first2
  obtain ⟨_, s13, y, -, left, rest3⟩ := logicalOr_inv cond2
  obtain ⟨_, l4, s14, r4, -, l4r, r4r, op4⟩ := binary_inv (by decide) (by decide) left
  obtain ⟨rfl, rfl⟩ := local_eval known l4r
  obtain ⟨_, r40, -, r40r, c4⟩ := cast_inv r4r
  obtain ⟨rfl, rfl⟩ := value_inv r40r
  rw [toCore_target', cast_isize (by decide) (by decide), Except.ok.injEq] at c4
  subst c4
  rw [toCore_target', signed_greaterEqual, Except.ok.injEq, Value.boolean.injEq] at op4
  have back : (-((8 * w : Nat) : Int) ≥ 0) = False := by simp only [eq_iff_iff, iff_false]; omega
  simp only [back, decide_false] at op4
  subst op4
  rcases rest3 with ⟨bad, -⟩ | ⟨-, right⟩
  · cases bad
  obtain ⟨_, l5, s15, r5, -, l5r, r5r, op5⟩ := binary_inv (by decide) (by decide) right
  obtain ⟨rfl, rfl⟩ := local_eval one3 l5r
  obtain ⟨rfl, rfl⟩ := value_inv r5r
  rw [toCore_target', signed_equal, Except.ok.injEq, Value.boolean.injEq] at op5
  subst op5
  simp only [show ((1 : Int) == 0) = false from rfl] at branch
  obtain ⟨rfl, rfl⟩ := skip_inv branch
  replace rest2 := (rest2.resolve_right fun h => h.1 rfl).2
  -- the last word's offset
  obtain ⟨_, v6, s16, s17, -, e6, b6, rfl⟩ := letLocal_inv rest2
  obtain ⟨_, l6, s18, r6, -, l6r, r6r, op6⟩ := binary_inv (by decide) (by decide) e6
  obtain ⟨_, l7, s19, r7, -, l7r, r7r, op7⟩ := binary_inv (by decide) (by decide) l6r
  obtain ⟨_, l8, -, l8r, c8⟩ := cast_inv l7r
  obtain ⟨_, l9, s20, r9, -, l9r, r9r, op9⟩ := binary_inv (by decide) (by decide) l8r
  obtain ⟨_, l10, -, l10r, c10⟩ := cast_inv l9r
  obtain ⟨rfl, rfl⟩ := value_inv l10r
  rw [toCore_target', cast_isize (by decide) (by decide), Except.ok.injEq] at c10
  subst c10
  obtain ⟨rfl, rfl⟩ := local_eval known r9r
  rw [toCore_target', signed_subtract, Except.ok.injEq, Int.sub_neg, Int.zero_add,
    wrap_isize_of (by omega) (by omega)] at op9
  subst op9
  rw [toCore_target', cast_usize_int (by omega) (by omega), Except.ok.injEq] at c8
  subst c8
  obtain ⟨_, r70, -, r70r, c7⟩ := cast_inv r7r
  obtain ⟨rfl, rfl⟩ := local_eval one3 r70r
  rw [toCore_target', cast_usize_int (by decide) (by decide), Except.ok.injEq] at c7
  subst c7
  rw [toCore_target', unsigned_multiply, Except.ok.injEq] at op7
  subst op7
  obtain ⟨rfl, rfl⟩ := value_inv r6r
  rw [toCore_target', unsigned_subtract, Except.ok.injEq] at op6
  subst op6
  have offset : ((Int.toNat ((8 * w : Nat) : Int) * Int.toNat 1 % 2 ^ 64 + 2 ^ 64 - 8 % 2 ^ 64) % 2 ^ 64) =
      8 * w - 8 := by
    simp only [Int.toNat_natCast, show Int.toNat 1 = 1 from rfl, Nat.mul_one]
    omega
  rw [offset] at b6
  have inv4 := inv3.bindLocal 321 (.unsigned .usize (8 * w - 8))
  -- the view of the storage
  obtain ⟨_, v7, s21, s22, -, e7, b7, rfl⟩ := letLocal_inv b6
  obtain ⟨_, a1, s23, n1, s24, -, p7, n7, m7⟩ := typedSlice_inv e7
  obtain ⟨_, l11, s25, r11, -, l11r, r11r, op11⟩ := binary_inv (by decide) (by decide) p7
  have storage4 := local?_bindLocal_other (id := 321) (by decide) (.unsigned .usize (8 * w - 8))
    (local?_bindLocal_other (id := 178) (by decide) (.signed .isize (-((8 * w : Nat) : Int)))
      (local?_bindLocal_other (id := 123) (by decide) (.rawSlice t.toCore 0 (Int.toNat 0))
        (local?_bindLocal_other (id := 97) (by decide) (.pointer 0) storage)))
  obtain ⟨rfl, rfl⟩ := local_eval storage4 l11r
  obtain ⟨rfl, rfl⟩ := local_eval (local?_bindLocal_self inv3 321 _) r11r
  rw [toCore_target', pointer_add, Except.ok.injEq, Value.pointer.injEq] at op11
  subst op11
  obtain ⟨hn1, rfl⟩ := local_eval (local?_bindLocal_other (id := 321) (by decide) _ one3) n7
  simp only [Value.signed.injEq, true_and] at hn1
  subst hn1
  obtain ⟨w', hw', -, -, rfl, rfl⟩ := map_inv kind m7
  rw [hw, Option.some.injEq] at hw'
  subst hw'
  obtain ⟨_, rv, -, rr, rfl⟩ := return_inv b7
  obtain ⟨rfl, rfl⟩ := local_eval (local?_bindLocal_self inv4 394 _) rr
  refine ⟨w, hw, pos, rfl, ?_⟩
  exact (((((((Same.refl inv).bind 97 _).bind 123 _).bind 178 _).bind 321 _).bind 394 _).restore _
    |>.restore _ |>.restore _ |>.restore _ |>.restore _)

/-- A call of `typed_slice_from_storage<t>(p, 1)` on storage `a`: the view, the
state's heap and locals as they were. -/
theorem slice_call {t : SrcType} {callee : Nat} {p : Core.Expr} {a : Nat} {v : Value}
    (found : sp.funcs[callee]? = some (sliceFunc t)) (el : wordElement sp.decls t = true) (inv : Inv st)
    (storage : ∀ {j u s}, evalExpr j sp.toCore st p = .done u s → u = .pointer a ∧ s = st)
    (h : evalExpr k sp.toCore st (.call callee [p, .value (.signed .i32 1)]) = .done v st') :
    ∃ w, NativeLayout.valueWords? sp.toCore t.toCore = some w ∧ 0 < w ∧
      v = .rawSlice t.toCore ((a + (8 * w - 8)) % 2 ^ 64) 1 ∧ Same st st' ∧ st'.locals = st.locals := by
  have args : ∀ {j vs s}, evalExprs j sp.toCore st [p, .value (.signed .i32 1)] = .done vs s →
      vs = [.pointer a, .signed .i32 1] ∧ s = st := by
    intro j vs s run
    obtain ⟨_, u, s1, rest, -, pr, restr, rfl⟩ := exprs_cons_inv run
    obtain ⟨rfl, rfl⟩ := storage pr
    obtain ⟨_, u2, s2, rest2, -, pr2, restr2, rfl⟩ := exprs_cons_inv restr
    obtain ⟨rfl, rfl⟩ := value_inv pr2
    obtain ⟨rfl, rfl⟩ := exprs_nil_inv restr2
    exact ⟨rfl, rfl⟩
  obtain ⟨j, completed, c, body, result, rfl⟩ := call_pure found args h
  have inv0 := Same.start inv (paramBindings (sliceFunc t).params [.pointer a, .signed .i32 1])
  have start : (({ st with locals := [] } : State).bindLocals
      (paramBindings (sliceFunc t).params [.pointer a, .signed .i32 1])) =
      (({ st with locals := [] } : State).bindLocal 28 (.pointer a)).bindLocal 42 (.signed .i32 1) := rfl
  have inv1 : Inv (({ st with locals := [] } : State).bindLocal 28 (.pointer a)) := inv.clear.bindLocal _ _
  rw [start] at body inv0
  obtain ⟨w, hw, pos, rfl, same⟩ := slice_body el inv0
    (local?_bindLocal_other (id := 42) (by decide) _ (local?_bindLocal_self inv.clear 28 _))
    (local?_bindLocal_self inv1 42 _) body
  refine ⟨w, hw, pos, result, ?_, rfl⟩
  have := Same.call (st := st) (completed := completed) (paramBindings (sliceFunc t).params [.pointer a, .signed .i32 1])
  rw [start] at this
  exact this same

end

end Lanius.Faithful
