module

public import Lanius.Semantics
public import Lanius.Mini.Compiler.Types
-- import parts: Lanius.Mini.Compiler
-- end import parts

@[expose] public section

/-! The Core meaning of the source language's types, operators, expressions,
statements and functions (moved from `Source.lean`, which has the theorems):
what the pure semantics of the extraction certificates needs, without the
compiler's functions. -/

namespace Lanius.Mini

open Lanius.Core (Value)

def UintTy.toCore : UintTy → Core.UnsignedIntTy
  | .uint8 => .u8
  | .uint32 => .u32
  | .uint64 => .u64
  | .usize => .usize
  | .uint16 => .u16

/-- The signed type as wide. -/
def UintTy.toSigned : UintTy → Core.SignedIntTy
  | .uint8 => .i8
  | .uint32 => .i32
  | .uint64 => .i64
  | .usize => .isize
  | .uint16 => .i16

def UintTy.width : UintTy → Nat
  | .uint8 => 8
  | .uint32 => 32
  | .uint64 => 64
  | .usize => 64
  | .uint16 => 16

def SrcType.toCore : SrcType → Core.Ty
  | .i32 => .scalar (.signed .i32)
  | .bool => .scalar .bool
  | .uint kind => .scalar (.unsigned kind.toCore)
  | .struct id _ => .structure id
  | .enum id _ => .enumeration id
  | .ptr => .scalar .rawPtr
  | .slice element => .slice element.toCore
  | .unit => .unit
  | .isize => .scalar (.signed .isize)
  | .char => .scalar .char
  | .sint kind => .scalar (.signed kind.toSigned)

/-- The Core type id of a struct or enum type. -/
def SrcType.typeId : SrcType → Nat
  | .i32 => 0
  | .bool => 0
  | .uint _ => 0
  | .struct id _ => id
  | .enum id _ => id
  | .ptr => 0
  | .slice _ => 0
  | .unit => 0
  | .isize => 0
  | .char => 0
  | .sint _ => 0

/-- The Core type a cast to this type names. Lowering only casts to `i32`
and the unsigned types. -/
def SrcType.toScalar : SrcType → Core.ScalarTy
  | .i32 => .signed .i32
  | .bool => .bool
  | .uint kind => .unsigned kind.toCore
  | .struct _ _ => .bool
  | .enum _ _ => .bool
  | .ptr => .rawPtr
  | .slice _ => .bool
  | .unit => .bool
  | .isize => .signed .isize
  | .char => .char
  | .sint kind => .signed kind.toSigned

/-- Core's raw slice of this element type from a pointer and a length:
`slice_from_raw_parts` for `i32`, the typed form for the rest. -/
def SrcType.sliceFrom : SrcType → Core.Expr → Core.Expr → Core.Expr
  | .i32, pointer, length => .i32SliceFromRawParts pointer length
  | .bool, pointer, length => .typedSliceFromRawParts (.scalar .bool) pointer length
  | .uint kind, pointer, length => .typedSliceFromRawParts (.scalar (.unsigned kind.toCore)) pointer length
  | .struct id _, pointer, length => .typedSliceFromRawParts (.structure id) pointer length
  | .enum id _, pointer, length => .typedSliceFromRawParts (.enumeration id) pointer length
  | .ptr, pointer, length => .typedSliceFromRawParts (.scalar .rawPtr) pointer length
  | .slice element, pointer, length => .typedSliceFromRawParts (.slice element.toCore) pointer length
  | .unit, pointer, length => .typedSliceFromRawParts .unit pointer length
  | .isize, pointer, length => .typedSliceFromRawParts (.scalar (.signed .isize)) pointer length
  | .char, pointer, length => .typedSliceFromRawParts (.scalar .char) pointer length
  | .sint kind, pointer, length => .typedSliceFromRawParts (.scalar (.signed kind.toSigned)) pointer length

def SrcDivOp.toCore : SrcDivOp → Core.BinaryOp
  | .quotient => .divide
  | .remainder => .remainder

def SrcOp.toCore : SrcOp → Core.BinaryOp
  | .plus => .add
  | .minus => .subtract
  | .times => .multiply
  | .bitAnd => .bitAnd
  | .bitOr => .bitOr
  | .bitXor => .bitXor
  | .shiftLeft => .shiftLeft
  | .shiftRight => .shiftRight
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
  | .unsigned kind value => .value (.unsigned kind.toCore value.toNat)
  | .local id => .local id
  | .field id index => .field (.local id) index
  | .negate operand => .unary .negate operand.toCore
  | .not operand => .unary .logicalNot operand.toCore
  | .apply op left right => .binary op.toCore left.toCore right.toCore
  | .cast ty operand => .cast ty.toScalar operand.toCore
  | .null => .value (.pointer 0)
  | .char code => .value (.character (UInt32.ofNat code.toNat))

/-- Match arms from variant `k`: arm `k` matches variant `k` of enum type
`id`, binding its payload. -/
def coreArms (id : Nat) : Nat → List SrcArm → List (Core.Pattern × Core.Expr)
  | _, [] => []
  | k, arm :: rest => (.enumVariant id k (arm.binders.map .bind), arm.value.toCore) :: coreArms id (k + 1) rest

mutual
/-- An effectful expression means the same Core expression as its pure
counterpart, with calls, reads and literals where they occur. -/
def SrcEff.toCore : SrcEff → Core.Expr
  | .ePure e => e.toCore
  | .eCall callee args => .call callee (SrcEff.toCoreList args)
  | .eApply op left right => .binary op.toCore left.toCore right.toCore
  | .eNeg operand => .unary .negate operand.toCore
  | .eNot operand => .unary .logicalNot operand.toCore
  | .eCast ty operand => .cast ty.toScalar operand.toCore
  | .eIndex slice index => .index (.local slice) index.toCore
  | .eStruct ty fields => .structValue ty.typeId (SrcEff.toCoreList fields)
  | .eVariant ty variant payload => .enumValue ty.typeId variant (SrcEff.toCoreList payload)
  | .eMatch scrutinee ety _ binders values =>
      .matchValue scrutinee.toCore (SrcEff.coreArms ety.typeId 0 binders values)
  | .eDivide op left right => .binary op.toCore left.toCore right.toCore
  | .eStride slice => .intrinsic .sliceStride (.local slice)

def SrcEff.toCoreList : List SrcEff → List Core.Expr
  | [] => []
  | e :: es => e.toCore :: SrcEff.toCoreList es

/-- Arm `k` matches variant `k`, binding its payload. -/
def SrcEff.coreArms (id : Nat) : Nat → List (List Nat) → List SrcEff → List (Core.Pattern × Core.Expr)
  | _, [], _ => []
  | _, _ :: _, [] => []
  | k, binders :: rest, value :: values =>
      (.enumVariant id k (binders.map .bind), value.toCore) :: SrcEff.coreArms id (k + 1) rest values
end

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
  | .letAlloc id size shift body =>
      .letLocal id (.scalar .rawPtr) (.alloc size.toCore (.value (.unsigned .usize (2 ^ shift)))) body.toCore
  | .letLoad id pointer offset body =>
      .letLocal id (.scalar (.unsigned .u8)) (.loadByte pointer.toCore offset.toCore) body.toCore
  | .setByte pointer offset value => .expression (.storeByte pointer.toCore offset.toCore value.toCore)
  | .free pointer size shift =>
      .expression (.dealloc pointer.toCore size.toCore (.value (.unsigned .usize (2 ^ shift))))
  | .letSlice id element pointer length body =>
      .letLocal id (.slice element.toCore) (element.sliceFrom pointer.toCore length.toCore) body.toCore
  | .letIndex id ty slice index body =>
      .letLocal id ty.toCore (.index (.local slice) index.toCore) body.toCore
  | .setIndex slice index value =>
      .expression (.assign .set (.index (.local slice) index.toCore) value.toCore)
  | .letEval id ty value body => .letLocal id ty.toCore value.toCore body.toCore
  | .setEval id value => .expression (.assign .set (.local id) value.toCore)
  | .ifEval condition thenBranch elseBranch =>
      .ifThenElse condition.toCore thenBranch.toCore elseBranch.toCore
  | .whileEval condition body => .whileLoop condition.toCore body.toCore
  | .returnEval value => .returnValue (some value.toCore)
  | .discard value => .expression value.toCore
  | .setIndexEval slice index value =>
      .expression (.assign .set (.index (.local slice) index.toCore) value.toCore)
  | .setFieldEval id index value => .expression (.assign .set (.field (.local id) index) value.toCore)
  | .returnUnit => .returnValue none
  | .assert condition => .expression (.intrinsic .assert condition.toCore)
  | .break => .breakLoop
  | .continue => .continueLoop

def SrcFunc.toCore (id : Nat) (func : SrcFunc) : Core.Function where
  id := id
  parameters := func.params.map fun param => (param.id, param.ty.toCore)
  returnType := func.ret.toCore
  body := some func.body.toCore

/-- Functions numbered from `id`. -/
def coreFuncs : Nat → List SrcFunc → List Core.Function
  | _, [] => []
  | id, func :: rest => func.toCore id :: coreFuncs (id + 1) rest

/-! ## Host services (roadmap F8)

Core's host services that the verified compiler lowers to system calls are
Core functions without a body (`ExternalBehavior.host`), from function id
`hostBase` = 2^32 on, past every program's own functions. A source program
calls them like its own functions (an `extern` declaration is a function of
the program whose body returns the host function's result). -/

def hostBase : Nat := 4294967296

/-- The host service at function id `id`. -/
def hostService? (id : Nat) : Option Core.HostService :=
  if id = hostBase then some .writeByte
  else if id = hostBase + 1 then some .writeStdout
  else if id = hostBase + 2 then some .writeStderr
  else none

/-- Parameters numbered from `n`. -/
def numberedParams : Nat → List Core.Ty → List (Nat × Core.Ty)
  | _, [] => []
  | n, ty :: rest => (n, ty) :: numberedParams (n + 1) rest

/-- The host function `id` for `service`: its parameters have the service's
types, numbered from 0. -/
def hostFunc (id : Nat) (service : Core.HostService) : Core.Function where
  id := id
  parameters := numberedParams 0 service.parameterTypes
  returnType := service.returnType
  body := none
  external := some (.host service)

def hostFuncs : List Core.Function :=
  [hostFunc hostBase .writeByte, hostFunc (hostBase + 1) .writeStdout, hostFunc (hostBase + 2) .writeStderr]

def SrcStructDecl.toCore (decl : SrcStructDecl) : Core.StructDecl where
  id := decl.id
  fields := decl.fields.map SrcType.toCore

def SrcEnumDecl.toCore (decl : SrcEnumDecl) : Core.EnumDecl where
  id := decl.id
  variants := decl.variants.map (List.map SrcType.toCore)

def paramBindings (params : List SrcParam) (values : List Value) : List (Nat × Value) :=
  ((params.map fun p => (p.id, p.ty.toCore)).zip values).map fun pair => (pair.1.1, pair.2)

/-! Core's i32 arithmetic is `BitVec 32` arithmetic on `toInt`. -/

theorem wrapSigned_i32 (n : Int) :
    Semantics.wrapSigned Core.Target.x86_64 .i32 n = (BitVec.ofInt 32 n).toInt := by
  rw [BitVec.toInt_ofInt]
  change (if n % 4294967296 ≥ 2147483648 then n % 4294967296 - 4294967296 else n % 4294967296) =
    (if n % 4294967296 < 2147483648 then n % 4294967296 else n % 4294967296 - 4294967296)
  by_cases h : 2147483648 ≤ n % 4294967296
  · rw [if_pos h, if_neg (by omega)]
  · rw [if_neg h, if_pos (by omega)]

end Lanius.Mini
