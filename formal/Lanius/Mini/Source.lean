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
  | .enum id _ => .enumeration id

/-- The Core type id of a struct or enum type. -/
def SrcType.typeId : SrcType → Nat
  | .i32 => 0
  | .bool => 0
  | .struct id _ => id
  | .enum id _ => id

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

/-- Match arms from variant `k`: arm `k` matches variant `k` of enum type
`id`, binding its payload. -/
def coreArms (id : Nat) : Nat → List SrcArm → List (Core.Pattern × Core.Expr)
  | _, [] => []
  | k, arm :: rest => (.enumVariant id k (arm.binders.map .bind), arm.value.toCore) :: coreArms id (k + 1) rest

def SrcStmt.toCore : SrcStmt → Core.Stmt
  | .nop => .skip
  | .let id ty value body => .letLocal id ty.toCore value.toCore body.toCore
  | .letStruct id ty fields body =>
      .letLocal id ty.toCore (.structValue ty.typeId (fields.map SrcExpr.toCore)) body.toCore
  | .letCall id ty callee args body =>
      .letLocal id ty.toCore (.call callee (args.map SrcExpr.toCore)) body.toCore
  | .letEnum id ty variant payload body =>
      .letLocal id ty.toCore (.enumValue ty.typeId variant (payload.map SrcExpr.toCore)) body.toCore
  | .letMatch id ty scrutinee enumId arms body =>
      .letLocal id ty.toCore (.matchValue (.local scrutinee) (coreArms enumId 0 arms)) body.toCore
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
  | .enum _ _, _, _ => False

mutual
/-- `ty.HoldsAt value env slot`: the `ty.size` slots of `env` from `slot`
represent `value`. A struct's fields follow one another; an enum's tag is its
variant number, and its payload follows. -/
inductive SrcType.HoldsAt : SrcType → Value → Env → Nat → Prop where
  | i32 {value : Value} {env : Env} {slot : Nat} :
      SrcType.i32.Holds value (env slot) → SrcType.HoldsAt .i32 value env slot
  | bool {value : Value} {env : Env} {slot : Nat} :
      SrcType.bool.Holds value (env slot) → SrcType.HoldsAt .bool value env slot
  | struct {id : Nat} {fields : List SrcType} {vs : List Value} {env : Env} {slot : Nat} :
      FieldsHold fields vs env slot → SrcType.HoldsAt (.struct id fields) (.structure id vs) env slot
  | enum {id : Nat} {variants : List (List SrcType)} {k : Nat} {fs : List SrcType} {vs : List Value}
      {env : Env} {slot : Nat} :
      variants[k]? = some fs → env slot = BitVec.ofNat 32 k → FieldsHold fs vs env (slot + 1) →
      SrcType.HoldsAt (.enum id variants) (.enumeration id k vs) env slot

/-- Values of these types, one after another from `slot`: a struct's fields,
a payload, or arguments. -/
inductive FieldsHold : List SrcType → List Value → Env → Nat → Prop where
  | nil {env : Env} {slot : Nat} : FieldsHold [] [] env slot
  | cons {ty : SrcType} {tys : List SrcType} {v : Value} {vs : List Value} {env : Env} {slot : Nat} :
      ty.HoldsAt v env slot → FieldsHold tys vs env (slot + ty.size) → FieldsHold (ty :: tys) (v :: vs) env slot
end

theorem SrcType.holdsAt_scalar {ty : SrcType} (scalar : ty.isScalar = true) {v : Value} {env : Env}
    {slot : Nat} : ty.HoldsAt v env slot ↔ ty.Holds v (env slot) := by
  cases ty with
  | i32 => exact ⟨fun | .i32 h => h, .i32⟩
  | bool => exact ⟨fun | .bool h => h, .bool⟩
  | struct => simp [SrcType.isScalar] at scalar
  | enum => simp [SrcType.isScalar] at scalar

theorem FieldsHold.length : ∀ {fs vs env slot}, FieldsHold fs vs env slot → vs.length = fs.length
  | [], _, _, _, .nil => rfl
  | _ :: _, _, _, _, .cons _ rest => by simp [rest.length]

theorem sizes_le_maxSize : ∀ {variants : List (List SrcType)} {k : Nat} {fs : List SrcType},
    variants[k]? = some fs → sizes fs ≤ maxSize variants
  | [], _, _, found => by simp at found
  | v :: rest, 0, fs, found => by
    simp only [List.getElem?_cons_zero, Option.some.injEq] at found
    subst found
    simp only [maxSize]
    omega
  | v :: rest, k + 1, fs, found => by
    simp only [List.getElem?_cons_succ] at found
    have := sizes_le_maxSize found
    simp only [maxSize]
    omega

mutual
theorem SrcType.HoldsAt.congr : ∀ {ty : SrcType} {v : Value} {env : Env} {slot : Nat},
    ty.HoldsAt v env slot → ∀ {env' : Env} {slot' : Nat},
      (∀ i < ty.size, env' (slot' + i) = env (slot + i)) → ty.HoldsAt v env' slot'
  | .i32, _, _, _, .i32 holds, _, _, agree => by
    have := agree 0 (by simp [SrcType.size])
    simp only [Nat.add_zero] at this
    exact .i32 (by rw [this]; exact holds)
  | .bool, _, _, _, .bool holds, _, _, agree => by
    have := agree 0 (by simp [SrcType.size])
    simp only [Nat.add_zero] at this
    exact .bool (by rw [this]; exact holds)
  | .struct _ fields, _, _, _, .struct holds, _, _, agree =>
    .struct (FieldsHold.congr holds fun i below => agree i (by simp only [SrcType.size]; exact below))
  | .enum _ variants, _, _, slot, .enum found tag payload, _, slot', agree => by
    have bound := sizes_le_maxSize found
    refine .enum found ?_ (FieldsHold.congr payload fun i below => ?_)
    · have := agree 0 (by simp only [SrcType.size]; omega)
      simp only [Nat.add_zero] at this
      rw [this, tag]
    · have := agree (i + 1) (by simp only [SrcType.size]; omega)
      rw [show slot' + 1 + i = slot' + (i + 1) by omega, this]
      congr 1
      omega

theorem FieldsHold.congr : ∀ {fs : List SrcType} {vs : List Value} {env : Env} {slot : Nat},
    FieldsHold fs vs env slot → ∀ {env' : Env} {slot' : Nat},
      (∀ i < sizes fs, env' (slot' + i) = env (slot + i)) → FieldsHold fs vs env' slot'
  | [], _, _, _, .nil, _, _, _ => .nil
  | ty :: tys, _, _, slot, .cons head rest, _, slot', agree => by
    refine .cons (SrcType.HoldsAt.congr head fun i below => agree i (by simp only [sizes]; omega))
      (FieldsHold.congr rest fun i below => ?_)
    have := agree (ty.size + i) (by simp only [sizes]; omega)
    rw [show slot' + ty.size + i = slot' + (ty.size + i) by omega, this]
    congr 1
    omega
end

theorem fieldOffset_zero (fs : List SrcType) : fieldOffset fs 0 = 0 := by
  cases fs <;> simp [fieldOffset]

theorem fieldOffset_succ (ty : SrcType) (rest : List SrcType) (k : Nat) :
    fieldOffset (ty :: rest) (k + 1) = ty.size + fieldOffset rest k := by
  simp [fieldOffset]

/-- Field `k`, at its offset. -/
theorem FieldsHold.get : ∀ {fs vs env slot}, FieldsHold fs vs env slot → ∀ {k : Nat} {f : SrcType},
    fs[k]? = some f → ∃ v, vs[k]? = some v ∧ f.HoldsAt v env (slot + fieldOffset fs k)
  | [], _, _, _, .nil, _, _, found => by simp at found
  | _ :: _, _, _, _, .cons head rest, k, f, found => by
    cases k with
    | zero =>
      simp only [List.getElem?_cons_zero, Option.some.injEq] at found
      subst found
      exact ⟨_, rfl, by simpa [fieldOffset] using head⟩
    | succ k =>
      simp only [List.getElem?_cons_succ] at found ⊢
      obtain ⟨v, got, holdsV⟩ := rest.get found
      exact ⟨v, got, by rw [fieldOffset_succ, ← Nat.add_assoc]; exact holdsV⟩

theorem fieldOffset_lt : ∀ {fs : List SrcType} {k : Nat} {f : SrcType}, fs[k]? = some f →
    fieldOffset fs k + f.size ≤ sizes fs
  | [], _, _, found => by simp at found
  | ty :: rest, 0, f, found => by
    simp only [List.getElem?_cons_zero, Option.some.injEq] at found
    subst found
    simp [fieldOffset, sizes]
  | ty :: rest, k + 1, f, found => by
    simp only [List.getElem?_cons_succ] at found
    have := fieldOffset_lt found
    rw [fieldOffset_succ]
    simp only [sizes]
    omega

theorem SrcType.size_scalar {ty : SrcType} (scalar : ty.isScalar = true) : ty.size = 1 := by
  cases ty <;> simp_all [SrcType.isScalar, SrcType.size]

/-- Storing a scalar field `k`. -/
theorem FieldsHold.set : ∀ {fs vs env slot}, FieldsHold fs vs env slot → ∀ {k : Nat} {f : SrcType},
    fs[k]? = some f → f.isScalar = true → ∀ {nv : Value} {x : BitVec 32}, f.Holds nv x →
      FieldsHold fs (Semantics.setValue vs k nv) (env.set (slot + fieldOffset fs k) x) slot
  | [], _, _, _, .nil, _, _, found, _, _, _, _ => by simp at found
  | ty :: tys, v :: vs, env, slot, .cons head rest, k, f, found, scalar, nv, x, holdsNew => by
    cases k with
    | zero =>
      simp only [List.getElem?_cons_zero, Option.some.injEq] at found
      subst found
      have one := SrcType.size_scalar scalar
      refine .cons ((SrcType.holdsAt_scalar scalar).mpr (by simpa [Env.set, fieldOffset_zero] using holdsNew))
        (rest.congr fun i _ => ?_)
      simp only [Env.set, fieldOffset_zero]
      rw [if_neg (by omega)]
    | succ k =>
      simp only [List.getElem?_cons_succ] at found
      refine .cons (head.congr fun i below => ?_) ?_
      · simp only [Env.set]
        rw [fieldOffset_succ, if_neg (by omega)]
      · rw [fieldOffset_succ, ← Nat.add_assoc]
        exact rest.set found scalar holdsNew

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
