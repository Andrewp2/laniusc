import Lanius.Faithful.Sim.Scalar
import Lanius.Faithful.Sim.Check
import Lanius.Mini.Fails

/-! # Core's operators on operands the checker types

On operands of the types `opTy`, `numOf`, `boolOf`, `castTy` and `divTy`
accept, Core's operators trap only where the program's own arithmetic is
undefined (a division by zero or that overflows, a shift too far), never
with `typeMismatch` (`binary_defined`, `divide_defined`); negation, `!` and
casts never trap. -/

namespace Lanius.Faithful

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (evalBinaryValue evalSignedBinary evalUnsignedBinary evalUnaryValue evalScalarCast)

theorem signed_error {tgt : Core.Target} {op : Core.BinaryOp} {ty : Core.SignedIntTy} {a b : Int}
    {reason : Lanius.Trap} (h : evalSignedBinary tgt op ty a b = .error reason)
    (notAnd : op ≠ .logicalAnd) (notOr : op ≠ .logicalOr) (notEq : op ≠ .equal) (notNe : op ≠ .notEqual) :
    undefinedTrap reason = false := by
  cases op <;> simp only [evalSignedBinary] at h
  all_goals first
    | exact absurd rfl notAnd
    | exact absurd rfl notOr
    | exact absurd rfl notEq
    | exact absurd rfl notNe
    | (simp at h; done)
    | (split at h
       · simp only [Except.error.injEq] at h; subst h; rfl
       · first
         | (simp at h; done)
         | (split at h
            · simp only [Except.error.injEq] at h; subst h; rfl
            · simp at h))

theorem unsigned_error {tgt : Core.Target} {op : Core.BinaryOp} {ty : Core.UnsignedIntTy} {a b : Nat}
    {reason : Lanius.Trap} (h : evalUnsignedBinary tgt op ty a b = .error reason)
    (notAnd : op ≠ .logicalAnd) (notOr : op ≠ .logicalOr) (notEq : op ≠ .equal) (notNe : op ≠ .notEqual) :
    undefinedTrap reason = false := by
  cases op <;> simp only [evalUnsignedBinary] at h
  all_goals first
    | exact absurd rfl notAnd
    | exact absurd rfl notOr
    | exact absurd rfl notEq
    | exact absurd rfl notNe
    | (simp at h; done)
    | (split at h
       · simp only [Except.error.injEq] at h; subst h; rfl
       · simp at h)

/-- Operands of one scalar type `t`: Core's binary operator traps only with
a defined trap. -/
theorem same_error {op : Core.BinaryOp} {t : SrcType} {lv rv : Value} {reason : Lanius.Trap}
    (hl : STy t lv) (hr : STy t rv) (notAnd : op ≠ .logicalAnd) (notOr : op ≠ .logicalOr)
    (cmp : op = .equal ∨ op = .notEqual ∨ numTy t = true)
    (h : evalBinaryValue .x86_64 op lv rv = .error reason) : undefinedTrap reason = false := by
  by_cases eq : op = .equal ∨ op = .notEqual
  · exfalso
    cases t with
    | i32 =>
      obtain ⟨a, rfl, -⟩ := hl; obtain ⟨b, rfl, -⟩ := hr
      rcases eq with rfl | rfl <;> simp [evalBinaryValue, Semantics.scalarEqual] at h
    | isize =>
      obtain ⟨a, rfl, -⟩ := hl; obtain ⟨b, rfl, -⟩ := hr
      rcases eq with rfl | rfl <;> simp [evalBinaryValue, Semantics.scalarEqual] at h
    | uint k =>
      obtain ⟨a, rfl, -⟩ := hl; obtain ⟨b, rfl, -⟩ := hr
      rcases eq with rfl | rfl <;> simp [evalBinaryValue, Semantics.scalarEqual] at h
    | bool =>
      obtain ⟨a, rfl⟩ := hl; obtain ⟨b, rfl⟩ := hr
      rcases eq with rfl | rfl <;> simp [evalBinaryValue, Semantics.scalarEqual] at h
    | unit =>
      have hl' : lv = .unit := hl
      have hr' : rv = .unit := hr
      subst hl' hr'
      rcases eq with rfl | rfl <;> simp [evalBinaryValue, Semantics.scalarEqual] at h
    | struct => exact hl.elim
    | enum => exact hl.elim
    | ptr => exact hl.elim
    | slice => exact hl.elim
    | sint => exact hl.elim
  · have notEq : op ≠ .equal := fun e => eq (.inl e)
    have notNe : op ≠ .notEqual := fun e => eq (.inr e)
    have num : numTy t = true := by rcases cmp with e | e | e <;> simp_all
    cases t with
    | i32 =>
      obtain ⟨a, rfl, -⟩ := hl
      obtain ⟨b, rfl, -⟩ := hr
      cases op <;> simp only [evalBinaryValue, beq_self_eq_true, if_true] at h <;>
        first
        | exact absurd rfl notAnd
        | exact absurd rfl notOr
        | exact absurd rfl notEq
        | exact absurd rfl notNe
        | exact signed_error h (by decide) (by decide) (by decide) (by decide)
    | isize =>
      obtain ⟨a, rfl, -⟩ := hl
      obtain ⟨b, rfl, -⟩ := hr
      cases op <;> simp only [evalBinaryValue, beq_self_eq_true, if_true] at h <;>
        first
        | exact absurd rfl notAnd
        | exact absurd rfl notOr
        | exact absurd rfl notEq
        | exact absurd rfl notNe
        | exact signed_error h (by decide) (by decide) (by decide) (by decide)
    | uint k =>
      obtain ⟨a, rfl, -⟩ := hl
      obtain ⟨b, rfl, -⟩ := hr
      cases op <;> simp only [evalBinaryValue, beq_self_eq_true, if_true] at h <;>
        first
        | exact absurd rfl notAnd
        | exact absurd rfl notOr
        | exact absurd rfl notEq
        | exact absurd rfl notNe
        | exact unsigned_error h (by decide) (by decide) (by decide) (by decide)
    | bool => simp [numTy] at num
    | unit => simp [numTy] at num
    | struct => simp [numTy] at num
    | enum => simp [numTy] at num
    | ptr => simp [numTy] at num
    | slice => simp [numTy] at num
    | sint => exact hl.elim

theorem opTy_same {op : SrcOp} {tl tr t : SrcType} (ht : opTy op tl tr = some t) (notAnd : op ≠ .logicalAnd)
    (notOr : op ≠ .logicalOr) : tr = tl ∧ (op = .equal ∨ op = .notEqual ∨ numTy tl = true) := by
  cases op
  all_goals first
    | exact absurd rfl notAnd
    | exact absurd rfl notOr
    | skip
  all_goals
    simp only [opTy] at ht
    split at ht
    · rename_i ok
      simp only [Bool.and_eq_true] at ok
      exact ⟨(SrcType.same_eq ok.2).symm, by simp_all⟩
    · simp at ht

/-- `left op right` on operands of the types `opTy` accepts traps only with a
defined trap. -/
theorem binary_defined {op : SrcOp} {tl tr t : SrcType} {lv rv : Value} {reason : Lanius.Trap}
    (ht : opTy op tl tr = some t) (notAnd : op ≠ .logicalAnd) (notOr : op ≠ .logicalOr)
    (hl : STy tl lv) (hr : STy tr rv) (h : evalBinaryValue .x86_64 op.toCore lv rv = .error reason) :
    undefinedTrap reason = false := by
  obtain ⟨rfl, cmp⟩ := opTy_same ht notAnd notOr
  refine same_error hl hr (fun e => notAnd (SrcOp.toCore_logicalAnd e)) (fun e => notOr (SrcOp.toCore_logicalOr e)) ?_ h
  rcases cmp with rfl | rfl | n
  · exact .inl rfl
  · exact .inr (.inl rfl)
  · exact .inr (.inr n)

theorem divide_defined {op : SrcDivOp} {tl tr t : SrcType} {lv rv : Value} {reason : Lanius.Trap}
    (ht : divTy tl tr = some t) (hl : STy tl lv) (hr : STy tr rv)
    (h : evalBinaryValue .x86_64 op.toCore lv rv = .error reason) : undefinedTrap reason = false := by
  obtain ⟨rfl, num, rfl⟩ := divTy_some ht
  exact same_error hl hr (by cases op <;> simp [SrcDivOp.toCore]) (by cases op <;> simp [SrcDivOp.toCore])
    (.inr (.inr num)) h

theorem neg_ok {t : SrcType} {v : Value} {reason : Lanius.Trap} (num : numTy t = true) (hv : STy t v)
    (h : evalUnaryValue .x86_64 .negate v = .error reason) : False := by
  cases t with
  | i32 => obtain ⟨a, rfl, -⟩ := hv; simp [evalUnaryValue] at h
  | isize => obtain ⟨a, rfl, -⟩ := hv; simp [evalUnaryValue] at h
  | sint => exact hv.elim
  | uint k => obtain ⟨a, rfl, -⟩ := hv; simp [evalUnaryValue] at h
  | bool => simp [numTy] at num
  | unit => simp [numTy] at num
  | struct => simp [numTy] at num
  | enum => simp [numTy] at num
  | ptr => simp [numTy] at num
  | slice => simp [numTy] at num

theorem not_ok {tgt : Core.Target} {v : Value} {reason : Lanius.Trap} (hv : STy .bool v)
    (h : evalUnaryValue tgt .logicalNot v = .error reason) : False := by
  obtain ⟨b, rfl⟩ := hv
  simp [evalUnaryValue] at h

theorem cast_ok {ty t : SrcType} {v : Value} {reason : Lanius.Trap} (num : numTy t = true) (numTo : numTy ty = true)
    (hv : STy t v) (h : evalScalarCast .x86_64 ty.toScalar v = .error reason) : False := by
  cases t with
  | i32 => obtain ⟨a, rfl, -⟩ := hv; cases ty <;> simp_all [numTy, SrcType.toScalar, evalScalarCast]
  | isize => obtain ⟨a, rfl, -⟩ := hv; cases ty <;> simp_all [numTy, SrcType.toScalar, evalScalarCast]
  | sint => exact hv.elim
  | uint k => obtain ⟨a, rfl, -⟩ := hv; cases ty <;> simp_all [numTy, SrcType.toScalar, evalScalarCast]
  | bool => simp [numTy] at num
  | unit => simp [numTy] at num
  | struct => simp [numTy] at num
  | enum => simp [numTy] at num
  | ptr => simp [numTy] at num
  | slice => simp [numTy] at num

end Lanius.Faithful
