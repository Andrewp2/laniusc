import Lanius.Faithful.Sim.Check

/-! # Core's scalar operators on scalars of source types

Core's operators wrap their results, so a result that Core computes from
scalars in range is a scalar in range, of the type `exprTy` gives it; and an
operator Core applies to a scalar has only scalars as operands, which mean
themselves. -/

namespace Lanius.Faithful

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (evalBinaryValue evalUnaryValue evalScalarCast evalSignedBinary evalUnsignedBinary
  wrapSigned wrapUnsigned wrapUnsignedInt scalarEqual)

theorem uint_bits (k : UintTy) : k.toCore.bits .x86_64 = k.width := by cases k <;> rfl

theorem wrap_i32 (x : Int) : -2 ^ 31 ≤ wrapSigned .x86_64 .i32 x ∧ wrapSigned .x86_64 .i32 x < 2 ^ 31 := by
  have hm : Semantics.signedModulus .x86_64 .i32 = 4294967296 := by decide
  have hs : Semantics.signedSignBit .x86_64 .i32 = 2147483648 := by decide
  have := Int.emod_nonneg x (by decide : (4294967296 : Int) ≠ 0)
  have := Int.emod_lt_of_pos x (by decide : (0 : Int) < 4294967296)
  simp only [wrapSigned]
  split <;> simp only [hm, hs] at * <;> omega

theorem wrap_isize (x : Int) : -2 ^ 63 ≤ wrapSigned .x86_64 .isize x ∧ wrapSigned .x86_64 .isize x < 2 ^ 63 := by
  have hm : Semantics.signedModulus .x86_64 .isize = 18446744073709551616 := by decide
  have hs : Semantics.signedSignBit .x86_64 .isize = 9223372036854775808 := by decide
  have := Int.emod_nonneg x (by decide : (18446744073709551616 : Int) ≠ 0)
  have := Int.emod_lt_of_pos x (by decide : (0 : Int) < 18446744073709551616)
  simp only [wrapSigned]
  split <;> simp only [hm, hs] at * <;> omega

theorem wrapU_lt (k : UintTy) (x : Nat) : wrapUnsigned .x86_64 k.toCore x < 2 ^ k.width := by
  simp only [wrapUnsigned, Semantics.unsignedModulus, uint_bits]
  exact Nat.mod_lt _ (Nat.two_pow_pos _)

theorem wrapUInt_lt (k : UintTy) (x : Int) : wrapUnsignedInt .x86_64 k.toCore x < 2 ^ k.width := by
  simp only [wrapUnsignedInt, Semantics.unsignedModulus, uint_bits, Int.ofNat_eq_natCast]
  have pos : (0 : Int) < ((2 ^ k.width : Nat) : Int) := by have := Nat.two_pow_pos k.width; omega
  have := Int.emod_lt_of_pos x pos
  have := Int.emod_nonneg x (Int.ne_of_gt pos)
  omega

/-! ## Results of the source types -/

theorem sty_signed {t : SrcType} {ty : Core.SignedIntTy} {a : Int} (h : STy t (.signed ty a)) (x : Int) :
    STy t (.signed ty (wrapSigned .x86_64 ty x)) := by
  cases t with
  | i32 =>
    obtain ⟨n, hv, -⟩ := h
    simp only [Value.signed.injEq] at hv
    obtain ⟨rfl, -⟩ := hv
    exact ⟨_, rfl, wrap_i32 x⟩
  | isize =>
    obtain ⟨n, hv, -⟩ := h
    simp only [Value.signed.injEq] at hv
    obtain ⟨rfl, -⟩ := hv
    exact ⟨_, rfl, wrap_isize x⟩
  | bool => obtain ⟨b, hv⟩ := h; cases hv
  | uint k => obtain ⟨n, hv, -⟩ := h; cases hv
  | unit => cases h
  | struct => exact h.elim
  | enum => exact h.elim
  | ptr => exact h.elim
  | slice => exact h.elim

theorem sty_unsigned {t : SrcType} {ty : Core.UnsignedIntTy} {a : Nat} (h : STy t (.unsigned ty a)) :
    ∃ k, t = .uint k ∧ ty = k.toCore := by
  cases t with
  | uint k =>
    obtain ⟨n, hv, -⟩ := h
    simp only [Value.unsigned.injEq] at hv
    exact ⟨k, rfl, hv.1⟩
  | i32 => obtain ⟨n, hv, -⟩ := h; cases hv
  | isize => obtain ⟨n, hv, -⟩ := h; cases hv
  | bool => obtain ⟨b, hv⟩ := h; cases hv
  | unit => cases h
  | struct => exact h.elim
  | enum => exact h.elim
  | ptr => exact h.elim
  | slice => exact h.elim

theorem sty_wrapU {t : SrcType} {ty : Core.UnsignedIntTy} {a : Nat} (h : STy t (.unsigned ty a)) (x : Nat) :
    STy t (.unsigned ty (wrapUnsigned .x86_64 ty x)) := by
  obtain ⟨k, rfl, rfl⟩ := sty_unsigned h
  exact ⟨_, rfl, wrapU_lt k x⟩

theorem sty_wrapUInt {t : SrcType} {ty : Core.UnsignedIntTy} {a : Nat} (h : STy t (.unsigned ty a)) (x : Int) :
    STy t (.unsigned ty (wrapUnsignedInt .x86_64 ty x)) := by
  obtain ⟨k, rfl, rfl⟩ := sty_unsigned h
  exact ⟨_, rfl, wrapUInt_lt k x⟩

/-- A scalar of a source type is a boolean, a signed or unsigned integer, or unit. -/
theorem sty_cases {t : SrcType} {v : Value} (h : STy t v) :
    (∃ b, v = .boolean b) ∨ (∃ ty a, v = .signed ty a) ∨ (∃ ty a, v = .unsigned ty a) ∨ v = .unit := by
  cases t with
  | i32 => obtain ⟨n, rfl, -⟩ := h; exact .inr (.inl ⟨_, _, rfl⟩)
  | isize => obtain ⟨n, rfl, -⟩ := h; exact .inr (.inl ⟨_, _, rfl⟩)
  | bool => obtain ⟨b, rfl⟩ := h; exact .inl ⟨_, rfl⟩
  | uint k => obtain ⟨n, rfl, -⟩ := h; exact .inr (.inr (.inl ⟨_, _, rfl⟩))
  | unit => exact .inr (.inr (.inr h))
  | struct => exact h.elim
  | enum => exact h.elim
  | ptr => exact h.elim
  | slice => exact h.elim

/-! ## Binary operators -/

/-- What Core's binary operators compute, by the shapes of their operands. -/
theorem binary_ok_cases {tgt : Core.Target} {op : Core.BinaryOp} {l r v : Value}
    (h : evalBinaryValue tgt op l r = .ok v) :
    (∃ x y, op = .logicalAnd ∧ l = .boolean x ∧ r = .boolean y ∧ v = .boolean (x && y)) ∨
    (∃ x y, op = .logicalOr ∧ l = .boolean x ∧ r = .boolean y ∧ v = .boolean (x || y)) ∨
    (∃ b, op = .equal ∧ scalarEqual l r = some b ∧ v = .boolean b) ∨
    (∃ b, op = .notEqual ∧ scalarEqual l r = some b ∧ v = .boolean !b) ∨
    (∃ ty a b, l = .signed ty a ∧ r = .signed ty b ∧ evalSignedBinary tgt op ty a b = .ok v) ∨
    (∃ ty a b, l = .unsigned ty a ∧ r = .unsigned ty b ∧ evalUnsignedBinary tgt op ty a b = .ok v) ∨
    (∃ a, l = .pointer a) ∨ (∃ a, l = .f32Bits a) ∨ (∃ a, l = .f64Bits a) ∨ (∃ a, l = .character a) := by
  unfold evalBinaryValue at h
  split at h
  · simp only [Except.ok.injEq] at h
    exact .inl ⟨_, _, rfl, rfl, rfl, h.symm⟩
  · simp only [Except.ok.injEq] at h
    exact .inr (.inl ⟨_, _, rfl, rfl, rfl, h.symm⟩)
  · split at h
    · rename_i b eq
      simp only [Except.ok.injEq] at h
      exact .inr (.inr (.inl ⟨b, rfl, eq, h.symm⟩))
    · simp at h
  · split at h
    · rename_i b eq
      simp only [Except.ok.injEq] at h
      exact .inr (.inr (.inr (.inl ⟨b, rfl, eq, h.symm⟩)))
    · simp at h
  all_goals first
    | exact .inr (.inr (.inr (.inr (.inr (.inr (.inl ⟨_, rfl⟩))))))
    | skip
  · split at h
    · rename_i same
      obtain rfl := beq_iff_eq.mp same
      exact .inr (.inr (.inr (.inr (.inl ⟨_, _, _, rfl, rfl, h⟩))))
    · simp at h
  · split at h
    · rename_i same
      obtain rfl := beq_iff_eq.mp same
      exact .inr (.inr (.inr (.inr (.inr (.inl ⟨_, _, _, rfl, rfl, h⟩)))))
    · simp at h
  · exact .inr (.inr (.inr (.inr (.inr (.inr (.inr (.inl ⟨_, rfl⟩)))))))
  · exact .inr (.inr (.inr (.inr (.inr (.inr (.inr (.inr (.inl ⟨_, rfl⟩))))))))
  · exact .inr (.inr (.inr (.inr (.inr (.inr (.inr (.inr (.inr ⟨_, rfl⟩))))))))
  · simp at h

theorem scalarEqual_flat {l r : Value} {b : Bool} (h : scalarEqual l r = some b) (flat : Flat l) : Flat r := by
  unfold scalarEqual at h
  split at h
  all_goals first
    | trivial
    | exact flat.elim
    | simp at h

/-- The comparisons give booleans. -/
def isCompare : Core.BinaryOp → Bool
  | .less | .lessEqual | .greater | .greaterEqual | .equal | .notEqual => true
  | .logicalAnd | .logicalOr | .add | .subtract | .multiply | .divide | .remainder | .bitAnd | .bitOr
  | .bitXor | .shiftLeft | .shiftRight => false

theorem signed_result {tgt : Core.Target} {op : Core.BinaryOp} {ty : Core.SignedIntTy} {a b : Int} {v : Value}
    (h : evalSignedBinary tgt op ty a b = .ok v) :
    (isCompare op = true ∧ ∃ x, v = .boolean x) ∨ (isCompare op = false ∧ ∃ x, v = .signed ty (wrapSigned tgt ty x)) := by
  cases op <;> simp only [evalSignedBinary] at h
  all_goals (repeat' split at h)
  all_goals first
    | (simp at h; done)
    | (simp only [Except.ok.injEq] at h; subst h; first
        | exact .inl ⟨rfl, _, rfl⟩
        | exact .inr ⟨rfl, _, rfl⟩)

theorem unsigned_result {tgt : Core.Target} {op : Core.BinaryOp} {ty : Core.UnsignedIntTy} {a b : Nat} {v : Value}
    (h : evalUnsignedBinary tgt op ty a b = .ok v) :
    (isCompare op = true ∧ ∃ x, v = .boolean x) ∨
      (isCompare op = false ∧ ∃ x, v = .unsigned ty (wrapUnsigned tgt ty x)) := by
  cases op <;> simp only [evalUnsignedBinary] at h
  all_goals (repeat' split at h)
  all_goals first
    | (simp at h; done)
    | (simp only [Except.ok.injEq] at h; subst h; first
        | exact .inl ⟨rfl, _, rfl⟩
        | exact .inr ⟨rfl, _, rfl⟩)

/-- An operator Core applies to a scalar has a flat right operand, and, unless
it is `==` or `!=`, a flat left one. -/
theorem binary_flat {tgt : Core.Target} {op : Core.BinaryOp} {l r v : Value}
    (h : evalBinaryValue tgt op l r = .ok v) :
    (∀ {t : SrcType}, STy t l → Flat r) ∧ (op ≠ .equal → op ≠ .notEqual → Flat l) := by
  rcases binary_ok_cases h with ⟨x, y, rfl, rfl, rfl, -⟩ | ⟨x, y, rfl, rfl, rfl, -⟩ | ⟨b, rfl, eq, -⟩ |
    ⟨b, rfl, eq, -⟩ | ⟨ty, a, b, rfl, rfl, -⟩ | ⟨ty, a, b, rfl, rfl, -⟩ | ⟨a, rfl⟩ | ⟨a, rfl⟩ | ⟨a, rfl⟩ | ⟨a, rfl⟩
  · exact ⟨fun _ => trivial, fun _ _ => trivial⟩
  · exact ⟨fun _ => trivial, fun _ _ => trivial⟩
  · exact ⟨fun hl => scalarEqual_flat eq hl.flat, fun ne => absurd rfl ne⟩
  · exact ⟨fun hl => scalarEqual_flat eq hl.flat, fun _ ne => absurd rfl ne⟩
  · exact ⟨fun _ => trivial, fun _ _ => trivial⟩
  · exact ⟨fun _ => trivial, fun _ _ => trivial⟩
  all_goals refine ⟨fun hl => ?_, fun _ _ => trivial⟩
  all_goals rcases sty_cases hl with ⟨_, h'⟩ | ⟨_, _, h'⟩ | ⟨_, _, h'⟩ | h' <;> cases h'

theorem SrcOp.toCore_logicalAnd {op : SrcOp} (h : op.toCore = .logicalAnd) : op = .logicalAnd := by
  cases op <;> simp_all [SrcOp.toCore]

theorem SrcOp.toCore_logicalOr {op : SrcOp} (h : op.toCore = .logicalOr) : op = .logicalOr := by
  cases op <;> simp_all [SrcOp.toCore]

/-- A comparison of a scalar gives a boolean. -/
theorem compare_bool {tgt : Core.Target} {op : Core.BinaryOp} {tl : SrcType} {lv rv v : Value} (hl : STy tl lv)
    (h : evalBinaryValue tgt op lv rv = .ok v) (cmp : isCompare op = true) : ∃ b, v = .boolean b := by
  rcases binary_ok_cases h with ⟨x, y, -, -, -, rfl⟩ | ⟨x, y, -, -, -, rfl⟩ | ⟨b, -, -, rfl⟩ |
    ⟨b, -, -, rfl⟩ | ⟨ty, a, b, rfl, rfl, hs⟩ | ⟨ty, a, b, rfl, rfl, hs⟩ | ⟨a, rfl⟩ | ⟨a, rfl⟩ | ⟨a, rfl⟩ | ⟨a, rfl⟩
  · exact ⟨_, rfl⟩
  · exact ⟨_, rfl⟩
  · exact ⟨_, rfl⟩
  · exact ⟨_, rfl⟩
  · rcases signed_result hs with ⟨-, x, rfl⟩ | ⟨ncmp, -⟩
    · exact ⟨_, rfl⟩
    · rw [cmp] at ncmp; cases ncmp
  · rcases unsigned_result hs with ⟨-, x, rfl⟩ | ⟨ncmp, -⟩
    · exact ⟨_, rfl⟩
    · rw [cmp] at ncmp; cases ncmp
  all_goals rcases sty_cases hl with ⟨_, h'⟩ | ⟨_, _, h'⟩ | ⟨_, _, h'⟩ | h' <;> cases h'

/-- Arithmetic on a scalar keeps its type. -/
theorem arith_sty {op : Core.BinaryOp} {tl : SrcType} {lv rv v : Value} (hl : STy tl lv)
    (h : evalBinaryValue .x86_64 op lv rv = .ok v) (cmp : isCompare op = false)
    (notAnd : op ≠ .logicalAnd) (notOr : op ≠ .logicalOr) : STy tl v := by
  rcases binary_ok_cases h with ⟨x, y, hop, -, -, -⟩ | ⟨x, y, hop, -, -, -⟩ | ⟨b, hop, -, rfl⟩ |
    ⟨b, hop, -, rfl⟩ | ⟨ty, a, b, rfl, rfl, hs⟩ | ⟨ty, a, b, rfl, rfl, hs⟩ | ⟨a, rfl⟩ | ⟨a, rfl⟩ | ⟨a, rfl⟩ | ⟨a, rfl⟩
  · exact absurd hop notAnd
  · exact absurd hop notOr
  · subst hop; simp [isCompare] at cmp
  · subst hop; simp [isCompare] at cmp
  · rcases signed_result hs with ⟨ncmp, -⟩ | ⟨-, x, rfl⟩
    · rw [cmp] at ncmp; cases ncmp
    · exact sty_signed hl x
  · rcases unsigned_result hs with ⟨ncmp, -⟩ | ⟨-, x, rfl⟩
    · rw [cmp] at ncmp; cases ncmp
    · exact sty_wrapU hl x
  all_goals rcases sty_cases hl with ⟨_, h'⟩ | ⟨_, _, h'⟩ | ⟨_, _, h'⟩ | h' <;> cases h'

/-- `left op right` has the type `opTy` gives it. -/
theorem binary_sty {op : SrcOp} {tl tr t : SrcType} {lv rv v : Value} (hl : STy tl lv)
    (ht : opTy op tl tr = some t) (notAnd : op ≠ .logicalAnd) (notOr : op ≠ .logicalOr)
    (h : evalBinaryValue .x86_64 op.toCore lv rv = .ok v) : STy t v := by
  cases op
  all_goals simp only [opTy] at ht
  all_goals first
    | exact absurd rfl notAnd
    | exact absurd rfl notOr
    | (simp only [Option.some.injEq] at ht; subst ht
       first
       | (obtain ⟨b, rfl⟩ := compare_bool hl h rfl; exact ⟨b, rfl⟩)
       | exact arith_sty hl h rfl (by simp [SrcOp.toCore]) (by simp [SrcOp.toCore]))
    | (split at ht
       · simp only [Option.some.injEq] at ht; subst ht
         obtain ⟨b, rfl⟩ := compare_bool hl h rfl; exact ⟨b, rfl⟩
       · simp at ht)

/-- Division keeps its left operand's type. -/
theorem divide_sty {op : SrcDivOp} {tl : SrcType} {lv rv v : Value} (hl : STy tl lv)
    (h : evalBinaryValue .x86_64 op.toCore lv rv = .ok v) : STy tl v := by
  cases op <;> exact arith_sty hl h rfl (by simp [SrcDivOp.toCore]) (by simp [SrcDivOp.toCore])

/-! ## Unary operators and casts -/

theorem unary_flat {tgt : Core.Target} {op : Core.UnaryOp} {l v : Value} (h : evalUnaryValue tgt op l = .ok v) :
    Flat l := by
  unfold evalUnaryValue at h
  split at h <;> first | trivial | simp at h

theorem neg_sty {t : SrcType} {lv v : Value} (hl : STy t lv) (h : evalUnaryValue .x86_64 .negate lv = .ok v) :
    STy t v := by
  rcases sty_cases hl with ⟨b, rfl⟩ | ⟨ty, a, rfl⟩ | ⟨ty, a, rfl⟩ | rfl <;>
    simp only [evalUnaryValue, Except.ok.injEq, reduceCtorEq] at h
  · subst h; exact sty_signed hl _
  · subst h; exact sty_wrapUInt hl _

theorem not_sty {tgt : Core.Target} {lv v : Value} (h : evalUnaryValue tgt .logicalNot lv = .ok v) : STy .bool v := by
  cases lv <;> simp only [evalUnaryValue, Except.ok.injEq, reduceCtorEq] at h
  subst h
  exact ⟨_, rfl⟩

theorem cast_flat {tgt : Core.Target} {d : Core.ScalarTy} {l v : Value} (h : evalScalarCast tgt d l = .ok v) :
    Flat l := by
  unfold evalScalarCast at h
  split at h <;> first | trivial | simp at h

theorem cast_sty {ty t : SrcType} {lv v : Value} (hl : STy t lv)
    (h : evalScalarCast .x86_64 ty.toScalar lv = .ok v) : STy ty v := by
  rcases sty_cases hl with ⟨b, rfl⟩ | ⟨sty, a, rfl⟩ | ⟨uty, a, rfl⟩ | rfl <;>
    cases ty <;> simp only [SrcType.toScalar, evalScalarCast, Except.ok.injEq, reduceCtorEq] at h
  all_goals subst h
  all_goals first
    | exact ⟨_, rfl, wrap_i32 _⟩
    | exact ⟨_, rfl, wrap_isize _⟩
    | exact ⟨_, rfl, wrapU_lt _ _⟩
    | exact ⟨_, rfl, wrapUInt_lt _ _⟩

end Lanius.Faithful
