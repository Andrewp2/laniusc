import Lanius.Mini.Compiler
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
  | .negate operand => .unary .negate operand.toCore
  | .not operand => .unary .logicalNot operand.toCore
  | .apply op left right => .binary op.toCore left.toCore right.toCore

def SrcStmt.toCore : SrcStmt → Core.Stmt
  | .nop => .skip
  | .let id ty value body => .letLocal id ty.toCore value.toCore body.toCore
  | .letCall id ty callee args body =>
      .letLocal id ty.toCore (.call callee (args.map SrcExpr.toCore)) body.toCore
  | .set id value => .expression (.assign .set (.local id) value.toCore)
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

/-- `ty.Holds value bits`: slot contents `bits` represent the Core `value` of
type `ty`. Booleans are 1 and 0. -/
def SrcType.Holds : SrcType → Value → BitVec 32 → Prop
  | .i32, value, bits => value = .signed .i32 bits.toInt
  | .bool, value, bits => ∃ b, value = .boolean b ∧ bits = boolBits b

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
