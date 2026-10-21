import Lanius.Mini.Semantics
import Lanius.Semantics

/-! The Core meaning of source programs, and how a Core value sits in a slot.

`SrcProgram.toCore` is the specification side of the front pass: each source
construct is the Core construct of the same name, with functions numbered by
position. The theorem in `SourceCorrect.lean` is about Core's own evaluator
(`Lanius.Semantics.evalExpr`) on that program. -/

namespace Lanius.Mini

open Lanius.Core (Value)

def SrcType.toCore : SrcType → Core.Ty
  | .i32 => .scalar (.signed .i32)
  | .bool => .scalar .bool
  | .struct id _ => .structure id

/-- The Core type id of a struct type. -/
def SrcType.structId : SrcType → Nat
  | .i32 => 0
  | .bool => 0
  | .struct id _ => id

def SrcOp.toCore : SrcOp → Core.BinaryOp
  | .plus => .add
  | .minus => .subtract
  | .times => .multiply
  | .bitAnd => .bitAnd
  | .bitOr => .bitOr
  | .bitXor => .bitXor
  | .less => .less
  | .lessEq => .lessEqual
  | .greater => .greater
  | .greaterEq => .greaterEqual
  | .equal => .equal
  | .notEqual => .notEqual
  | .logicalAnd => .logicalAnd
  | .logicalOr => .logicalOr

def SrcExpr.toCore : SrcExpr → Core.Expr
  | .int value => .value (.signed .i32 value.toInt)
  | .boolean value => .value (.boolean value)
  | .local id => .local id
  | .field id index => .field (.local id) index
  | .negate operand => .unary .negate operand.toCore
  | .not operand => .unary .logicalNot operand.toCore
  | .apply op left right => .binary op.toCore left.toCore right.toCore

def SrcStmt.toCore : SrcStmt → Core.Stmt
  | .nop => .skip
  | .let id ty value body => .letLocal id ty.toCore value.toCore body.toCore
  | .letStruct id ty fields body =>
      .letLocal id ty.toCore (.structValue ty.structId (fields.map SrcExpr.toCore)) body.toCore
  | .letCall id ty callee args body =>
      .letLocal id ty.toCore (.call callee (args.map SrcExpr.toCore)) body.toCore
  | .set id value => .expression (.assign .set (.local id) value.toCore)
  | .setField id index value => .expression (.assign .set (.field (.local id) index) value.toCore)
  | .setCall id callee args =>
      .expression (.assign .set (.local id) (.call callee (args.map SrcExpr.toCore)))
  | .then first second => .sequence first.toCore second.toCore
  | .if condition thenBranch elseBranch =>
      .ifThenElse condition.toCore thenBranch.toCore elseBranch.toCore
  | .while condition body => .whileLoop condition.toCore body.toCore
  | .return value => .returnValue (some value.toCore)

def SrcFunc.toCore (id : Nat) (func : SrcFunc) : Core.Function where
  id := id
  parameters := func.params.map fun param => (param.id, param.ty.toCore)
  returnType := func.ret.toCore
  body := some func.body.toCore

/-- Functions numbered from `id`. -/
def coreFuncs : Nat → List SrcFunc → List Core.Function
  | _, [] => []
  | id, func :: rest => func.toCore id :: coreFuncs (id + 1) rest

def SrcProgram.toCore (prog : SrcProgram) : Core.Program where
  functions := coreFuncs 0 prog.funcs

/-- `ty.Holds value bits`: one slot holding `bits` represents the Core `value`
of scalar type `ty`. Booleans are 1 and 0. -/
def SrcType.Holds : SrcType → Value → BitVec 32 → Prop
  | .i32, value, bits => value = .signed .i32 bits.toInt
  | .bool, value, bits => ∃ b, value = .boolean b ∧ bits = boolBits b
  | .struct _ _, _, _ => False

/-- Struct fields, one slot each from `slot`. -/
inductive FieldsHold : List FieldTy → List Value → Env → Nat → Prop where
  | nil {env : Env} {slot : Nat} : FieldsHold [] [] env slot
  | cons {f : FieldTy} {fs : List FieldTy} {v : Value} {vs : List Value} {env : Env} {slot : Nat} :
      f.ty.Holds v (env slot) → FieldsHold fs vs env (slot + 1) → FieldsHold (f :: fs) (v :: vs) env slot

/-- `ty.HoldsAt value env slot`: the `ty.size` slots of `env` from `slot`
represent `value`. -/
def SrcType.HoldsAt : SrcType → Value → Env → Nat → Prop
  | .i32, value, env, slot => SrcType.i32.Holds value (env slot)
  | .bool, value, env, slot => SrcType.bool.Holds value (env slot)
  | .struct id fields, value, env, slot => ∃ vs, value = .structure id vs ∧ FieldsHold fields vs env slot

theorem SrcType.holdsAt_scalar {ty : SrcType} (scalar : ty.isScalar = true) {v : Value} {env : Env}
    {slot : Nat} : ty.HoldsAt v env slot ↔ ty.Holds v (env slot) := by
  cases ty <;> simp_all [SrcType.HoldsAt, SrcType.isScalar]

theorem FieldTy.ty_scalar (f : FieldTy) : f.ty.isScalar = true := by
  cases f <;> rfl

theorem FieldsHold.length {fs vs env slot} (holds : FieldsHold fs vs env slot) :
    vs.length = fs.length := by
  induction holds with
  | nil => rfl
  | cons _ _ ih => simp [ih]

theorem FieldsHold.congr {fs vs env slot} (holds : FieldsHold fs vs env slot) {env' : Env} {slot' : Nat}
    (agree : ∀ i < fs.length, env' (slot' + i) = env (slot + i)) : FieldsHold fs vs env' slot' := by
  induction holds generalizing slot' with
  | nil => exact .nil
  | cons head _ ih =>
    refine .cons ?_ (ih fun i h => ?_)
    · have := agree 0 (by simp)
      simp only [Nat.add_zero] at this
      rw [this]; exact head
    · have := agree (i + 1) (by simp; omega)
      rw [show slot' + 1 + i = slot' + (i + 1) by omega, this]
      congr 1
      omega

theorem SrcType.HoldsAt.congr {ty : SrcType} {v : Value} {env : Env} {slot : Nat}
    (holds : ty.HoldsAt v env slot) {env' : Env} {slot' : Nat}
    (agree : ∀ i < ty.size, env' (slot' + i) = env (slot + i)) : ty.HoldsAt v env' slot' := by
  cases ty with
  | i32 =>
    have := agree 0 (by simp [SrcType.size])
    simp only [Nat.add_zero] at this
    simpa [SrcType.HoldsAt, this] using holds
  | bool =>
    have := agree 0 (by simp [SrcType.size])
    simp only [Nat.add_zero] at this
    simpa [SrcType.HoldsAt, this] using holds
  | struct id fields =>
    obtain ⟨vs, rfl, fieldsHold⟩ := holds
    exact ⟨vs, rfl, fieldsHold.congr (by simpa [SrcType.size] using agree)⟩

theorem FieldsHold.get {fs vs env slot} (holds : FieldsHold fs vs env slot) {k : Nat} {f : FieldTy}
    (found : fs[k]? = some f) : ∃ v, vs[k]? = some v ∧ f.ty.Holds v (env (slot + k)) := by
  induction holds generalizing k with
  | nil => simp at found
  | cons head _ ih =>
    cases k with
    | zero =>
      simp only [List.getElem?_cons_zero, Option.some.injEq] at found
      subst found
      exact ⟨_, rfl, by simpa using head⟩
    | succ k =>
      simp only [List.getElem?_cons_succ] at found ⊢
      obtain ⟨v, got, holdsV⟩ := ih found
      have shift : ∀ a : Nat, a + (k + 1) = a + 1 + k := fun a => by omega
      exact ⟨v, got, by rw [shift]; exact holdsV⟩

theorem FieldsHold.set {fs vs env slot} (holds : FieldsHold fs vs env slot) {k : Nat} {f : FieldTy}
    (found : fs[k]? = some f) {nv : Value} {x : BitVec 32} (holdsNew : f.ty.Holds nv x) :
    FieldsHold fs (Semantics.setValue vs k nv) (env.set (slot + k) x) slot := by
  induction holds generalizing k with
  | nil => simp at found
  | cons head rest ih =>
    cases k with
    | zero =>
      simp only [List.getElem?_cons_zero, Option.some.injEq] at found
      subst found
      refine .cons (by simpa [Env.set] using holdsNew) (rest.congr fun i _ => ?_)
      simp only [Env.set]
      rw [if_neg (by omega)]
    | succ k =>
      simp only [List.getElem?_cons_succ] at found
      refine .cons ?_ ?_
      · simp only [Env.set]
        rw [if_neg (by omega)]
        exact head
      · have shift : ∀ a : Nat, a + (k + 1) = a + 1 + k := fun a => by omega
        rw [shift]
        exact ih found

/-! Core's i32 arithmetic is `BitVec 32` arithmetic on `toInt`. -/

theorem wrapSigned_i32 (n : Int) :
    Semantics.wrapSigned Core.Target.x86_64 .i32 n = (BitVec.ofInt 32 n).toInt := by
  rw [BitVec.toInt_ofInt]
  change (if n % 4294967296 ≥ 2147483648 then n % 4294967296 - 4294967296 else n % 4294967296) =
    (if n % 4294967296 < 2147483648 then n % 4294967296 else n % 4294967296 - 4294967296)
  by_cases h : 2147483648 ≤ n % 4294967296
  · rw [if_pos h, if_neg (by omega)]
  · rw [if_neg h, if_pos (by omega)]

theorem toInt_emod (x : BitVec 32) : x.toInt % 4294967296 = (x.toNat : Int) := by
  rw [BitVec.toInt_eq_toNat_bmod]
  have := x.isLt
  simp only [Int.bmod]
  split <;> omega

theorem wrap_add (x y : BitVec 32) :
    Semantics.wrapSigned Core.Target.x86_64 .i32 (x.toInt + y.toInt) = (x + y).toInt := by
  rw [wrapSigned_i32, BitVec.toInt_ofInt, BitVec.toInt_add]

theorem wrap_sub (x y : BitVec 32) :
    Semantics.wrapSigned Core.Target.x86_64 .i32 (x.toInt - y.toInt) = (x - y).toInt := by
  rw [wrapSigned_i32, BitVec.toInt_ofInt, BitVec.toInt_sub]

theorem wrap_mul (x y : BitVec 32) :
    Semantics.wrapSigned Core.Target.x86_64 .i32 (x.toInt * y.toInt) = (x * y).toInt := by
  rw [wrapSigned_i32, BitVec.toInt_ofInt, BitVec.toInt_mul]

theorem wrap_neg (x : BitVec 32) :
    Semantics.wrapSigned Core.Target.x86_64 .i32 (-x.toInt) = (-x).toInt := by
  rw [wrapSigned_i32, BitVec.toInt_ofInt, BitVec.toInt_neg]

theorem wrap_nat (n : Nat) :
    Semantics.wrapSigned Core.Target.x86_64 .i32 (Int.ofNat n) = (BitVec.ofNat 32 n).toInt := by
  rw [wrapSigned_i32]
  congr 1

theorem boolBits_ne_zero (b : Bool) : (boolBits b ≠ 0) = (b = true) := by
  cases b <;> simp [boolBits]

end Lanius.Mini
