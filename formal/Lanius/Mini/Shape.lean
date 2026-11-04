module

public import Lanius.Typing
public import Lanius.Semantics

@[expose] public section

/-! # Value shapes: Core's operations on typed values never mismatch

The first step of review finding 2 (`typeMismatch` is never reached by a
well-typed program without raw memory). `Shape P v ty` is Core's value typing
(`Typing.ValueHasType`) without the numeric ranges: the constructor of the
value is the one `ty` names, a struct's or an enum's fields have their
declared shapes. Core's operators, casts and assignment operators typed by
Core's rules (`UnaryOpHasType`, `ScalarCast`, `BinaryOpHasType`,
`AssignOpHasType`) give, on values of their operand shapes, either a value
of the result shape or a trap other than `typeMismatch`; a pattern typed by
`PatternHasType` binds, on a value of its shape, values of its bindings'
shapes. -/

namespace Lanius.Mini.NoMismatch

open Lanius.Core (Value Ty ScalarTy)
open Lanius.Typing

/-- A value's shape: Core's value typing without the numeric ranges. -/
inductive Shape (P : Core.Program) : Value → Ty → Prop where
  | unit : Shape P .unit .unit
  | boolean (b : Bool) : Shape P (.boolean b) (.scalar .bool)
  | signed (t : Core.SignedIntTy) (v : Int) : Shape P (.signed t v) (.scalar (.signed t))
  | unsigned (t : Core.UnsignedIntTy) (v : Nat) : Shape P (.unsigned t v) (.scalar (.unsigned t))
  | f32 (b : UInt32) : Shape P (.f32Bits b) (.scalar .f32)
  | f64 (b : UInt64) : Shape P (.f64Bits b) (.scalar .f64)
  | character (c : UInt32) : Shape P (.character c) (.scalar .char)
  | string (s : String) : Shape P (.string s) (.scalar .string)
  | pointer (a : Nat) : Shape P (.pointer a) (.scalar .rawPtr)
  | array (vs : List Value) (t : Ty) (n : Nat) (len : vs.length = n) (each : ∀ v ∈ vs, Shape P v t) :
      Shape P (.array vs) (.array t n)
  | structure (d : Core.StructDecl) (vs : List Value) (found : P.structure? d.id = some d)
      (len : vs.length = d.fields.length) (each : ∀ p ∈ vs.zip d.fields, Shape P p.1 p.2) :
      Shape P (.structure d.id vs) (.structure d.id)
  | enumeration (d : Core.EnumDecl) (variant : Nat) (tys : List Ty) (vs : List Value)
      (found : P.enumeration? d.id = some d) (variantFound : d.variants[variant]? = some tys)
      (len : vs.length = tys.length) (each : ∀ p ∈ vs.zip tys, Shape P p.1 p.2) :
      Shape P (.enumeration d.id variant vs) (.enumeration d.id)
  | slice (t : Ty) (cell : Nat) (projections : List Core.ValueProjection) (start length : Nat) :
      Shape P (.slice t cell projections start length) (.slice t)
  | rawSlice (t : Ty) (address length : Nat) : Shape P (.rawSlice t address length) (.slice t)
  | reference (t : Ty) (cell : Nat) (projections : List Core.ValueProjection) :
      Shape P (.reference t cell projections) (.reference t)

/-- Shapes of a list of values, one a type. -/
def Shapes (P : Core.Program) (vs : List Value) (tys : List Ty) : Prop :=
  vs.length = tys.length ∧ ∀ p ∈ vs.zip tys, Shape P p.1 p.2

theorem Shapes.nil (P : Core.Program) : Shapes P [] [] := ⟨rfl, fun _ h => by cases h⟩

theorem Shapes.cons {P : Core.Program} {v : Value} {t : Ty} {vs : List Value} {tys : List Ty}
    (h : Shape P v t) (t' : Shapes P vs tys) : Shapes P (v :: vs) (t :: tys) := by
  refine ⟨by simp [t'.1], fun p mem => ?_⟩
  simp only [List.zip_cons_cons, List.mem_cons] at mem
  rcases mem with rfl | mem
  · exact h
  · exact t'.2 p mem

theorem Shapes.cons_inv {P : Core.Program} {v : Value} {t : Ty} {vs : List Value} {tys : List Ty}
    (h : Shapes P (v :: vs) (t :: tys)) : Shape P v t ∧ Shapes P vs tys :=
  ⟨h.2 (v, t) (by simp), by simpa using h.1, fun p mem => h.2 p (by simp [mem])⟩

theorem Shapes.append {P : Core.Program} {vs ws : List Value} {ts us : List Ty}
    (a : Shapes P vs ts) (b : Shapes P ws us) : Shapes P (vs ++ ws) (ts ++ us) := by
  induction vs generalizing ts with
  | nil =>
    cases ts with
    | nil => simpa using b
    | cons => exact absurd a.1 (by simp)
  | cons v vs ih =>
    cases ts with
    | nil => exact absurd a.1 (by simp)
    | cons t ts =>
      obtain ⟨hv, hvs⟩ := a.cons_inv
      exact Shapes.cons hv (ih hvs)

/-- `Shapes` at an index. -/
theorem Shapes.get {P : Core.Program} {vs : List Value} {tys : List Ty} (h : Shapes P vs tys)
    {i : Nat} {t : Ty} (found : tys[i]? = some t) : ∃ v, vs[i]? = some v ∧ Shape P v t := by
  induction vs generalizing tys i with
  | nil => cases tys with
    | nil => simp at found
    | cons => exact absurd h.1 (by simp)
  | cons v vs ih =>
    cases tys with
    | nil => simp at found
    | cons t' tys =>
      obtain ⟨hv, hvs⟩ := h.cons_inv
      cases i with
      | zero =>
        simp only [List.getElem?_cons_zero, Option.some.injEq] at found
        subst found
        exact ⟨v, rfl, hv⟩
      | succ i =>
        simp only [List.getElem?_cons_succ] at found ⊢
        exact ih hvs found

/-- `Shapes` with one value replaced by another of its shape. -/
theorem Shapes.set {P : Core.Program} {vs : List Value} {tys : List Ty} (h : Shapes P vs tys)
    {i : Nat} {t : Ty} (found : tys[i]? = some t) {w : Value} (hw : Shape P w t) :
    Shapes P (vs.set i w) tys := by
  induction vs generalizing tys i with
  | nil => simpa using h
  | cons v vs ih =>
    cases tys with
    | nil => simp at found
    | cons t' tys =>
      obtain ⟨hv, hvs⟩ := h.cons_inv
      cases i with
      | zero =>
        simp only [List.getElem?_cons_zero, Option.some.injEq] at found
        subst found
        exact Shapes.cons hw hvs
      | succ i =>
        simp only [List.getElem?_cons_succ] at found
        exact Shapes.cons hv (ih hvs found)

/-! ## Typed values have their shapes -/

mutual
theorem ValueHasType.shape {P : Core.Program} : ∀ {v : Value} {t : Ty}, ValueHasType P v t → Shape P v t
  | _, _, .unit => .unit
  | _, _, .boolean b => .boolean b
  | _, _, .signed t v _ _ => .signed t v
  | _, _, .unsigned t v _ => .unsigned t v
  | _, _, .f32Bits b => .f32 b
  | _, _, .f64Bits b => .f64 b
  | _, _, .character c => .character c
  | _, _, .string s => .string s
  | _, _, .pointer a => .pointer a
  | _, _, .array vs t len elements => by
    have hs := ValuesHaveTypes.shapes elements
    refine .array vs t _ len fun v mem => ?_
    obtain ⟨i, lt, rfl⟩ := List.getElem_of_mem mem
    have := hs.get (i := i) (t := t) (by simp [List.getElem?_replicate]; omega)
    obtain ⟨w, hw, sw⟩ := this
    rw [List.getElem?_eq_getElem lt, Option.some.injEq] at hw
    rw [hw]; exact sw
  | _, _, .slice t cell projections start length => .slice t cell projections start length
  | _, _, .rawSlice _ address length => .rawSlice _ address length
  | _, _, .structure d found fields => by
    have hs := ValuesHaveTypes.shapes fields
    exact .structure d _ found hs.1 hs.2
  | _, _, .enumeration d found variantFound payload => by
    have hs := ValuesHaveTypes.shapes payload
    exact .enumeration d _ _ _ found variantFound hs.1 hs.2
  | _, _, .reference t cell projections => .reference t cell projections

theorem ValuesHaveTypes.shapes {P : Core.Program} :
    ∀ {vs : List Value} {ts : List Ty}, ValuesHaveTypes P vs ts → Shapes P vs ts
  | _, _, .nil => Shapes.nil P
  | _, _, .cons head tail => Shapes.cons (ValueHasType.shape head) (ValuesHaveTypes.shapes tail)
end

/-! ## Operations -/

/-- What an operation gives on shaped operands: a value of shape `t`, or a
trap other than `typeMismatch`. -/
def OpOk (P : Core.Program) (t : Ty) : Except Lanius.Trap Value → Prop
  | .ok v => Shape P v t
  | .error r => r ≠ .typeMismatch

theorem Shape.enum_inv {P : Core.Program} {v : Value} {id : Nat} (h : Shape P v (.enumeration id)) :
    ∃ variant vs, v = .enumeration id variant vs := by
  cases h
  exact ⟨_, _, rfl⟩

theorem Shape.struct_inv {P : Core.Program} {v : Value} {id : Nat} (h : Shape P v (.structure id)) :
    ∃ vs, v = .structure id vs := by
  cases h
  exact ⟨_, rfl⟩

theorem unary_ok {P : Core.Program} {tgt : Core.Target} {op : Core.UnaryOp} {v : Value} {t t' : Ty}
    (typed : UnaryOpHasType op t t') (hv : Shape P v t) : OpOk P t' (Lanius.Semantics.evalUnaryValue tgt op v) := by
  cases typed with
  | positive c => cases c <;> cases hv <;> (simp only [Lanius.Semantics.evalUnaryValue, OpOk]; constructor)
  | logicalNot => cases hv; simp only [Lanius.Semantics.evalUnaryValue, OpOk]; constructor
  | negate c => cases c <;> cases hv <;> (simp only [Lanius.Semantics.evalUnaryValue, OpOk]; constructor)

theorem cast_ok {P : Core.Program} {tgt : Core.Target} {s d : ScalarTy} {v : Value}
    (c : ScalarCast s d) (hv : Shape P v (.scalar s)) : OpOk P (.scalar d) (Lanius.Semantics.evalScalarCast tgt d v) := by
  cases c <;> cases hv <;> (simp only [Lanius.Semantics.evalScalarCast, OpOk]; constructor)

@[simp] theorem OpOk.ok_iff {P : Core.Program} {t : Ty} {v : Value} : OpOk P t (.ok v) ↔ Shape P v t := Iff.rfl

@[simp] theorem OpOk.error_iff {P : Core.Program} {t : Ty} {r : Lanius.Trap} :
    OpOk P t (.error r) ↔ r ≠ .typeMismatch := Iff.rfl

attribute [simp] Shape.unit Shape.boolean Shape.signed Shape.unsigned Shape.f32 Shape.f64 Shape.character
  Shape.string Shape.pointer

/-- Unfold Core's binary operations on values of known constructors. -/
macro "binary_ok" : tactic => `(tactic| (
  simp only [Lanius.Semantics.evalBinaryValue, Lanius.Semantics.evalSignedBinary,
    Lanius.Semantics.evalUnsignedBinary, Lanius.Semantics.evalF32Binary, Lanius.Semantics.evalF64Binary,
    Lanius.Semantics.evalCharBinary, Lanius.Semantics.evalShiftBy, Lanius.Semantics.scalarEqual,
    Lanius.Semantics.pointerOffset, beq_self_eq_true, if_true, reduceIte, apply_ite (OpOk _ _),
    OpOk.ok_iff, OpOk.error_iff] <;>
  (try split) <;> (try split) <;> simp))

theorem binary_ok {P : Core.Program} {tgt : Core.Target} {op : Core.BinaryOp} {l r : Value} {lt rt out : Ty}
    (typed : BinaryOpHasType op lt rt out) (hl : Shape P l lt) (hr : Shape P r rt) :
    OpOk P out (Lanius.Semantics.evalBinaryValue tgt op l r) := by
  cases typed with
  | logicalAnd | logicalOr => cases hl; cases hr; binary_ok
  | equal c | notEqual c =>
    cases c with
    | enumeration id =>
      obtain ⟨a, as, rfl⟩ := hl.enum_inv
      obtain ⟨b, bs, rfl⟩ := hr.enum_inv
      binary_ok
    | _ => cases hl; cases hr; binary_ok
  | less c | lessEqual c | greater c | greaterEqual c | add c | subtract c | multiply c | divide c =>
    cases c <;> cases hl <;> cases hr <;> binary_ok
  | remainder c | bitAnd c | bitOr c | bitXor c | shiftLeft c | shiftRight c =>
    cases c <;> cases hl <;> cases hr <;> binary_ok
  | pointerAdd c | pointerSubtract c => cases c <;> cases hl <;> cases hr <;> binary_ok
  | shiftLeftBy c d | shiftRightBy c d => cases c <;> cases d <;> cases hl <;> cases hr <;> binary_ok

theorem assign_ok {P : Core.Program} {tgt : Core.Target} {op : Core.AssignOp} {current : Option Value}
    {right : Value} {t : Ty} (typed : AssignOpHasType op t) (hc : ∀ v, current = some v → Shape P v t)
    (hr : Shape P right t) : OpOk P t (Lanius.Semantics.evalAssignValue tgt op current right) := by
  have bin : ∀ b, (∃ bt : BinaryOpHasType b t t t, True) → Lanius.Semantics.assignOpBinary? op = some b →
      OpOk P t (Lanius.Semantics.evalAssignValue tgt op current right) := by
    intro b ⟨bt, _⟩ eq
    simp only [Lanius.Semantics.evalAssignValue, eq]
    cases current with
    | none => simp
    | some left => exact binary_ok bt (hc left rfl) hr
  cases typed with
  | set => exact hr
  | add c => exact bin _ ⟨.add c, trivial⟩ rfl
  | subtract c => exact bin _ ⟨.subtract c, trivial⟩ rfl
  | multiply c => exact bin _ ⟨.multiply c, trivial⟩ rfl
  | divide c => exact bin _ ⟨.divide c, trivial⟩ rfl
  | remainder c => exact bin _ ⟨.remainder c, trivial⟩ rfl
  | bitXor c => exact bin _ ⟨.bitXor c, trivial⟩ rfl
  | shiftLeft c => exact bin _ ⟨.shiftLeft c, trivial⟩ rfl
  | shiftRight c => exact bin _ ⟨.shiftRight c, trivial⟩ rfl
  | bitAnd c => exact bin _ ⟨.bitAnd c, trivial⟩ rfl
  | bitOr c => exact bin _ ⟨.bitOr c, trivial⟩ rfl

/-! ## Patterns -/

/-- The bindings a match gives have the names and shapes the pattern's
typing gives. -/
def BindsAs (P : Core.Program) (bs : List (Nat × Value)) (typed : List (Nat × Ty)) : Prop :=
  bs.map Prod.fst = typed.map Prod.fst ∧ Shapes P (bs.map Prod.snd) (typed.map Prod.snd)

theorem BindsAs.append {P : Core.Program} {a b : List (Nat × Value)} {s t : List (Nat × Ty)}
    (ha : BindsAs P a s) (hb : BindsAs P b t) : BindsAs P (a ++ b) (s ++ t) := by
  refine ⟨by simp [ha.1, hb.1], ?_⟩
  simpa using Shapes.append ha.2 hb.2

mutual
theorem pattern_binds {P : Core.Program} :
    ∀ {pat : Core.Pattern} {t : Ty} {typed : List (Nat × Ty)}, PatternHasType P pat t typed →
      ∀ {v : Value} {bs : List (Nat × Value)}, Shape P v t → Lanius.Semantics.matchPattern pat v = some bs →
        BindsAs P bs typed
  | _, _, _, .wildcard, _, _, _, h => by
    simp only [Lanius.Semantics.matchPattern, Option.some.injEq] at h
    subst h; exact ⟨rfl, Shapes.nil P⟩
  | _, _, _, .bind id, _, _, hv, h => by
    simp only [Lanius.Semantics.matchPattern, Option.some.injEq] at h
    subst h; exact ⟨rfl, Shapes.cons hv (Shapes.nil P)⟩
  | _, _, _, .literal _, _, _, _, h => by
    simp only [Lanius.Semantics.matchPattern] at h
    split at h
    · cases h; exact ⟨rfl, Shapes.nil P⟩
    · cases h
  | _, _, _, .enumVariant d found variantFound payload, v, _, hv, h => by
    obtain ⟨variant, vs, rfl⟩ := hv.enum_inv
    cases hv with
    | enumeration d' variant' tys' vs' found' vf' len each =>
      simp only [Lanius.Semantics.matchPattern, Bool.and_eq_true, beq_iff_eq] at h
      split at h
      · rename_i same
        obtain ⟨-, rfl⟩ := same
        rw [found', Option.some.injEq] at found
        subst found
        rw [vf', Option.some.injEq] at variantFound
        subst variantFound
        exact patterns_binds payload ⟨len, each⟩ h
      · cases h
termination_by pat => sizeOf pat

theorem patterns_binds {P : Core.Program} :
    ∀ {pats : List Core.Pattern} {ts : List Ty} {typed : List (Nat × Ty)}, PatternsHaveTypes P pats ts typed →
      ∀ {vs : List Value} {bs : List (Nat × Value)}, Shapes P vs ts →
        Lanius.Semantics.matchPatterns pats vs = some bs → BindsAs P bs typed
  | _, _, _, .nil, vs, _, hv, h => by
    cases vs with
    | nil =>
      simp only [Lanius.Semantics.matchPatterns, Option.some.injEq] at h
      subst h; exact ⟨rfl, Shapes.nil P⟩
    | cons => exact absurd hv.1 (by simp)
  | _, _, _, .cons head tail, vs, _, hv, h => by
    cases vs with
    | nil => exact absurd hv.1 (by simp)
    | cons v vs =>
      obtain ⟨h1, h2⟩ := hv.cons_inv
      simp only [Lanius.Semantics.matchPatterns] at h
      split at h
      · rename_i hh ht
        cases h
        exact (pattern_binds head h1 hh).append (patterns_binds tail h2 ht)
      · cases h
termination_by pats => sizeOf pats
end

end Lanius.Mini.NoMismatch
