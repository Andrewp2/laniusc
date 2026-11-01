import Lanius.Faithful.Sim.PrimInv
import Lanius.Faithful.Sim.Check
import Lanius.Faithful.Sim.Store

/-! # Core runs of `size_of<T>` and `panic`

`size_of<T>()` returns `8 * w` for a word element `T` of `w` words: it reads
the stride of an empty raw view of `T`s, `-(8 * w)`, and negates it.
`panic()` asserts `false`, so no run of it completes. -/

namespace Lanius.Faithful

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (State Completion evalExpr evalExprs execStmt restoreLocals wrapSigned wrapUnsignedInt
  evalScalarCast evalBinaryValue mapRawNominalSlice)

/-! ## Scalars the helpers compute -/

theorem bv_zero : (0 : BitVec 32).toInt = 0 := by decide
theorem bv_one : (1 : BitVec 32).toInt = 1 := by decide
theorem bv_eight : (8 : BitVec 64).toNat = 8 := by decide

theorem wrap_isize_of {x : Int} (low : -2 ^ 63 ≤ x) (high : x < 2 ^ 63) : wrapSigned .x86_64 .isize x = x := by
  have hm : Semantics.signedModulus .x86_64 .isize = 18446744073709551616 := by decide
  have hs : Semantics.signedSignBit .x86_64 .isize = 9223372036854775808 := by decide
  simp only [wrapSigned]
  split <;> simp only [hm, hs] at * <;> omega

theorem wrap_i32_of {x : Int} (low : -2 ^ 31 ≤ x) (high : x < 2 ^ 31) : wrapSigned .x86_64 .i32 x = x := by
  have hm : Semantics.signedModulus .x86_64 .i32 = 4294967296 := by decide
  have hs : Semantics.signedSignBit .x86_64 .i32 = 2147483648 := by decide
  simp only [wrapSigned]
  split <;> simp only [hm, hs] at * <;> omega

theorem wrap_usize_of {x : Int} (low : 0 ≤ x) (high : x < 2 ^ 64) :
    (wrapUnsignedInt .x86_64 .usize x : Int) = x := by
  have hm : Semantics.unsignedModulus .x86_64 .usize = 18446744073709551616 := by decide
  simp only [wrapUnsignedInt, hm]
  rw [Int.emod_eq_of_lt low (by rw [Int.ofNat_eq_natCast]; omega)]
  omega

theorem cast_isize {n : Int} (low : -2 ^ 63 ≤ n) (high : n < 2 ^ 63) (ty : Core.SignedIntTy) :
    evalScalarCast .x86_64 (.signed .isize) (.signed ty n) = .ok (.signed .isize n) := by
  simp only [evalScalarCast, wrap_isize_of low high]

theorem cast_usize_nat {n : Nat} (high : n < 2 ^ 64) (ty : Core.SignedIntTy) :
    evalScalarCast .x86_64 (.unsigned .usize) (.signed ty n) = .ok (.unsigned .usize n) := by
  have := wrap_usize_of (x := n) (by omega) (by omega)
  simp only [evalScalarCast, Except.ok.injEq, Value.unsigned.injEq, true_and]
  omega

theorem signed_less (ty : Core.SignedIntTy) (a b : Int) :
    evalBinaryValue .x86_64 .less (.signed ty a) (.signed ty b) = .ok (.boolean (decide (a < b))) := by
  simp [evalBinaryValue, Semantics.evalSignedBinary]

theorem signed_greaterEqual (ty : Core.SignedIntTy) (a b : Int) :
    evalBinaryValue .x86_64 .greaterEqual (.signed ty a) (.signed ty b) = .ok (.boolean (decide (a ≥ b))) := by
  simp [evalBinaryValue, Semantics.evalSignedBinary]

theorem signed_equal (ty : Core.SignedIntTy) (a b : Int) :
    evalBinaryValue .x86_64 .equal (.signed ty a) (.signed ty b) = .ok (.boolean (a == b)) := by
  simp [evalBinaryValue, Semantics.scalarEqual]

theorem signed_subtract (ty : Core.SignedIntTy) (a b : Int) :
    evalBinaryValue .x86_64 .subtract (.signed ty a) (.signed ty b) =
      .ok (.signed ty (wrapSigned .x86_64 ty (a - b))) := by
  simp [evalBinaryValue, Semantics.evalSignedBinary]

/-! ## Empty and one-element raw views -/

/-- A raw view of a struct or enum element type that Core made. -/
theorem map_inv {P : Core.Program} {s s' : State} {T : Core.Ty} {a : Nat} {n : Int} {v : Value}
    (kind : (∃ id, T = .structure id) ∨ ∃ id, T = .enumeration id) (h : mapRawNominalSlice P s T a n = .done v s') :
    ∃ w, NativeLayout.valueWords? P T = some w ∧ 0 < w ∧ 0 ≤ n ∧ v = .rawSlice T a n.toNat ∧ s' = s := by
  rcases kind with ⟨id, rfl⟩ | ⟨id, rfl⟩ <;>
  · unfold mapRawNominalSlice at h
    dsimp only at h
    split at h
    · simp at h
    simp only [Bool.not_true, Bool.false_eq_true, if_false] at h
    split at h
    · simp at h
    rename_i w hw
    split at h
    · simp at h
    rename_i nz
    split at h
    · rename_i zero
      simp only [Semantics.Outcome.done.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      simp only [beq_iff_eq] at nz zero
      exact ⟨w, hw, by omega, by omega, by rw [zero], rfl⟩
    split at h
    · simp at h
    split at h
    · simp at h
    simp only [Semantics.Outcome.done.injEq] at h
    obtain ⟨rfl, rfl⟩ := h
    simp only [beq_iff_eq] at nz
    exact ⟨w, hw, by omega, by omega, rfl, rfl⟩

/-- Core's slice of a word element type: a typed raw view of its Core type. -/
theorem sliceFrom_word {ds : SrcDecls} {t : SrcType} (el : wordElement ds t = true) :
    (∀ p n, t.sliceFrom p n = .typedSliceFromRawParts t.toCore p n) ∧
      ((∃ id, t.toCore = .structure id) ∨ ∃ id, t.toCore = .enumeration id) := by
  cases t with
  | struct id fs => exact ⟨fun _ _ => rfl, .inl ⟨id, rfl⟩⟩
  | enum id vs => exact ⟨fun _ _ => rfl, .inr ⟨id, rfl⟩⟩
  | i32 => simp [wordElement] at el
  | bool => simp [wordElement] at el
  | uint => simp [wordElement] at el
  | ptr => simp [wordElement] at el
  | slice => simp [wordElement] at el
  | unit => simp [wordElement] at el
  | isize => simp [wordElement] at el
  | char => simp [wordElement] at el
  | float => simp [wordElement] at el
  | sint => simp [wordElement] at el
  | array => simp [wordElement] at el

theorem stride_word {P : Core.Program} {T : Core.Ty} {a len w : Nat}
    (kind : (∃ id, T = .structure id) ∨ ∃ id, T = .enumeration id) (words : NativeLayout.valueWords? P T = some w) :
    Semantics.rawSliceStride? P (.rawSlice T a len) = some (-((8 * w : Nat) : Int)) := by
  rcases kind with ⟨id, rfl⟩ | ⟨id, rfl⟩ <;>
    simp [Semantics.rawSliceStride?, NativeLayout.elementStride?, words, NativeLayout.wordBytes]

theorem valueWords_le {P : Core.Program} {T : Core.Ty} {w : Nat}
    (kind : (∃ id, T = .structure id) ∨ ∃ id, T = .enumeration id) (words : NativeLayout.valueWords? P T = some w) :
    w ≤ NativeLayout.maxWords :=
  words_le_max (k := NativeLayout.maxDepth - 1) kind words

/-! ## The runs -/

section
variable {sp : SrcProgram} {k : Nat} {st st' : State} {c : Completion}

/-- `size_of<t>()`'s body returns `8 * w`, `t`'s words in bytes. -/
theorem sizeOf_body {t : SrcType} (el : wordElement sp.decls t = true) (inv : Inv st)
    (run : execStmt k sp.toCore st (sizeOfFunc t).body.toCore = .done c st') :
    ∃ w, NativeLayout.valueWords? sp.toCore t.toCore = some w ∧ 0 < w ∧ w ≤ NativeLayout.maxWords ∧
      c = .returned (some (.unsigned .usize (8 * w))) ∧ Same st st' := by
  obtain ⟨slice, kind⟩ := sliceFrom_word el
  simp only [sizeOfFunc, SrcStmt.toCore, SrcExpr.toCore, SrcEff.toCore, SrcOp.toCore, SrcType.toCore,
    SrcType.toScalar, UintTy.toCore, slice, bv_zero] at run
  obtain ⟨_, v1, s1, s2, -, e1, b1, rfl⟩ := letLocal_inv run
  obtain ⟨rfl, rfl⟩ := value_inv e1
  have inv1 := inv.bindLocal 32 (.pointer 0)
  obtain ⟨_, v2, s3, s4, -, e2, b2, rfl⟩ := letLocal_inv b1
  obtain ⟨_, a, s5, n, s6, -, p2, n2, m2⟩ := typedSlice_inv e2
  obtain ⟨ha, rfl⟩ := local_eval (local?_bindLocal_self inv 32 _) p2
  obtain ⟨hn, rfl⟩ := value_inv n2
  simp only [Value.pointer.injEq, Value.signed.injEq, true_and] at ha hn
  subst ha hn
  obtain ⟨w, hw, pos, -, rfl, rfl⟩ := map_inv kind m2
  have inv2 := inv1.bindLocal 58 (.rawSlice t.toCore 0 (Int.toNat 0))
  obtain ⟨_, v3, s7, s8, -, e3, b3, rfl⟩ := letLocal_inv b2
  obtain ⟨_, x3, stride, -, l3, hs, rfl⟩ := stride_inv e3
  obtain ⟨rfl, rfl⟩ := local_eval (local?_bindLocal_self inv1 58 _) l3
  rw [stride_word kind hw, Option.some.injEq] at hs
  subst hs
  have inv3 := inv2.bindLocal 113 (.signed .isize (-((8 * w : Nat) : Int)))
  have known := local?_bindLocal_self inv2 113 (.signed .isize (-((8 * w : Nat) : Int)))
  have most := valueWords_le kind hw
  simp only [NativeLayout.maxWords] at most
  obtain ⟨_, s10, c1, -, first, rest⟩ := sequence_inv b3
  obtain ⟨_, s11, x, -, cond, branch⟩ := if_inv first
  obtain ⟨_, l, s12, r, -, lr, rr, op⟩ := binary_inv (by decide) (by decide) cond
  obtain ⟨rfl, rfl⟩ := local_eval known lr
  obtain ⟨_, r0, -, r0r, cr⟩ := cast_inv rr
  obtain ⟨rfl, rfl⟩ := value_inv r0r
  rw [toCore_target', cast_isize (by decide) (by decide), Except.ok.injEq] at cr
  subst cr
  rw [toCore_target', signed_less, Except.ok.injEq, Value.boolean.injEq] at op
  have neg : (-((8 * w : Nat) : Int) < 0) = True := by simp only [eq_iff_iff, iff_true]; omega
  simp only [neg, decide_true] at op
  subst op
  simp only [if_true] at branch
  obtain ⟨_, rv, -, rr, rfl⟩ := return_inv branch
  obtain ⟨_, sub, -, subr, csub⟩ := cast_inv rr
  obtain ⟨_, l2, s13, r2, -, l2r, r2r, op2⟩ := binary_inv (by decide) (by decide) subr
  obtain ⟨_, l20, -, l20r, cl⟩ := cast_inv l2r
  obtain ⟨rfl, rfl⟩ := value_inv l20r
  rw [toCore_target', cast_isize (by decide) (by decide), Except.ok.injEq] at cl
  subst cl
  obtain ⟨rfl, rfl⟩ := local_eval known r2r
  rw [toCore_target', signed_subtract, Except.ok.injEq, Int.sub_neg, Int.zero_add,
    wrap_isize_of (by omega) (by omega)] at op2
  subst op2
  rw [toCore_target', cast_usize_nat (by omega), Except.ok.injEq] at csub
  subst csub
  rcases rest with ⟨bad, -⟩ | ⟨-, rfl, rfl⟩
  · cases bad
  refine ⟨w, hw, pos, most, rfl, ?_⟩
  exact (((((Same.refl inv).bind 32 _).bind 58 _).bind 113 _).restore _).restore _ |>.restore _

/-- A call of `size_of<t>()`: `8 * w`, the state's heap and locals as they were. -/
theorem sizeOf_call {t : SrcType} {callee : Nat} {v : Value} (found : sp.funcs[callee]? = some (sizeOfFunc t))
    (el : wordElement sp.decls t = true) (inv : Inv st)
    (h : evalExpr k sp.toCore st (.call callee []) = .done v st') :
    ∃ w, NativeLayout.valueWords? sp.toCore t.toCore = some w ∧ 0 < w ∧ w ≤ NativeLayout.maxWords ∧
      v = .unsigned .usize (8 * w) ∧ Same st st' ∧ st'.locals = st.locals := by
  obtain ⟨j, completed, c, body, result, rfl⟩ := call_pure found (fun run => exprs_nil_inv run) h
  obtain ⟨w, hw, pos, most, rfl, same⟩ := sizeOf_body el (Same.start inv _) body
  exact ⟨w, hw, pos, most, result, Same.call _ same, rfl⟩

/-- No call of `panic()` completes. -/
theorem panic_call {callee : Nat} {v : Value} (found : sp.funcs[callee]? = some panicFunc)
    (h : evalExpr k sp.toCore st (.call callee []) = .done v st') : False := by
  obtain ⟨j, completed, c, body, -, -⟩ := call_pure found (fun run => exprs_nil_inv run) h
  simp only [panicFunc, SrcStmt.toCore, SrcEff.toCore, SrcExpr.toCore] at body
  obtain ⟨_, u, -, e, -⟩ := expression_inv body
  obtain ⟨_, -, e2, -⟩ := assert_inv e
  obtain ⟨bad, -⟩ := value_inv e2
  cases bad

end

end Lanius.Faithful
