module

public import Lanius.Faithful.Sim.Rel
public import Lanius.Mini.SliceLayout
public import Lanius.Mini.Compiler.P.SrcExpr_guard
public import Lanius.Mini.Compiler.P.boundsGuard
public import Lanius.Mini.Compiler.P.checkThen
public import Lanius.Mini.Compiler.P.expectType
public import Lanius.Mini.Compiler.P.guardAll
public import Lanius.Mini.Compiler.P.guarded
public import Lanius.Mini.Compiler.P.lowerAppend
public import Lanius.Mini.Compiler.P.lowerAs
public import Lanius.Mini.Compiler.P.slotVars
public import Lanius.Mini.Compiler.P.thenCheck
public import Lanius.Mini.Compiler.P.trap
import all Lanius.Mini.Compiler.P.DivOp_size
import all Lanius.Mini.Compiler.P.FOp_size
import all Lanius.Mini.Compiler.P.FloatTy_mask
import all Lanius.Mini.Compiler.P.FloatTy_number
import all Lanius.Mini.Compiler.P.FloatTy_rexSize
import all Lanius.Mini.Compiler.P.FloatTy_signBit
import all Lanius.Mini.Compiler.P.FloatTy_signWord
import all Lanius.Mini.Compiler.P.Instr_size
import all Lanius.Mini.Compiler.P.BinOp_size
import all Lanius.Mini.Compiler.P.Lists_concat
import all Lanius.Mini.Compiler.P.Lists_cons
import all Lanius.Mini.Compiler.P.Lists_empty
import all Lanius.Mini.Compiler.P.Lists_get
import all Lanius.Mini.Compiler.P.Lists_getOr
import all Lanius.Mini.Compiler.P.Lists_length
import all Lanius.Mini.Compiler.P.Lists_single
import all Lanius.Mini.Compiler.P.MemWidth_bytes
import all Lanius.Mini.Compiler.P.MemWidth_prefix
import all Lanius.Mini.Compiler.P.MemWidth_rex
import all Lanius.Mini.Compiler.P.Word_prefix
import all Lanius.Mini.Compiler.P.SrcExpr_guard
import all Lanius.Mini.Compiler.P.boundsGuard
import all Lanius.Mini.Compiler.P.checkThen
import all Lanius.Mini.Compiler.P.expectType
import all Lanius.Mini.Compiler.P.guardAll
import all Lanius.Mini.Compiler.P.guarded
import all Lanius.Mini.Compiler.P.lowerAppend
import all Lanius.Mini.Compiler.P.lowerAs
import all Lanius.Mini.Compiler.P.slotVars
import all Lanius.Mini.Compiler.P.thenCheck
import all Lanius.Mini.Compiler.P.trap
import all Lanius.Mini.Compiler.P.SrcType_same
import all Lanius.Mini.Compiler.P.SrcType_size
import all Lanius.Mini.Compiler.P.fieldOffset
import all Lanius.Mini.Compiler.P.norm
import all Lanius.Mini.Compiler.P.wrap
import all Lanius.Mini.Compiler.P.SrcType_floatTy
import all Lanius.Mini.Compiler.P.SrcType_isBool
import all Lanius.Mini.Compiler.P.SrcType_isChar
import all Lanius.Mini.Compiler.P.SrcType_isFloat
import all Lanius.Mini.Compiler.P.SrcType_isFloatAny
import all Lanius.Mini.Compiler.P.SrcType_isI32
import all Lanius.Mini.Compiler.P.SrcType_isInteger
import all Lanius.Mini.Compiler.P.SrcType_isIsize
import all Lanius.Mini.Compiler.P.SrcType_isPtr
import all Lanius.Mini.Compiler.P.SrcType_isScalar
import all Lanius.Mini.Compiler.P.SrcType_isSint
import all Lanius.Mini.Compiler.P.SrcType_isSintAny
import all Lanius.Mini.Compiler.P.SrcType_isStr
import all Lanius.Mini.Compiler.P.SrcType_isUint
import all Lanius.Mini.Compiler.P.SrcType_isUnit
import all Lanius.Mini.Compiler.P.SrcType_sintKind
import all Lanius.Mini.Compiler.P.SrcType_uintKind
import all Lanius.Mini.Compiler.P.SrcType_word
import all Lanius.Mini.Compiler.P.UintTy_half
import all Lanius.Mini.Compiler.P.UintTy_leastBits
import all Lanius.Mini.Compiler.P.UintTy_signedWord
import all Lanius.Mini.Compiler.P.UintTy_spare
import all Lanius.Mini.Compiler.P.boolBits
import all Lanius.Mini.Compiler.P.lookup
import all Lanius.Mini.Compiler.P.UintTy_isWide
import all Lanius.Mini.Compiler.P.arithShiftRight
import all Lanius.Mini.Compiler.P.offsetOrArith
import all Lanius.Mini.Compiler.P.order
import all Lanius.Mini.Compiler.P.orderSint
import all Lanius.Mini.Compiler.P.orderUint
import all Lanius.Mini.Compiler.P.signKey
import all Lanius.Mini.Compiler.P.SrcEff_isSlice
import all Lanius.Mini.Compiler.P.SrcEff_passesSlices
import all Lanius.Mini.Compiler.P.SrcEff_sliceCall
import all Lanius.Mini.Compiler.P.SrcStmt_breaksOut
import all Lanius.Mini.Compiler.P.SrcStmt_depth
import all Lanius.Mini.Compiler.P.SrcStmt_lower
import all Lanius.Mini.Compiler.P.arrayCall
import all Lanius.Mini.Compiler.P.arrayCallSig
import all Lanius.Mini.Compiler.P.effsSlice
import all Lanius.Mini.Compiler.P.paramScope
import all Lanius.Mini.Compiler.P.paramTypes
import all Lanius.Mini.Compiler.P.paramsSize
import all Lanius.Mini.Compiler.P.paramsValid
import all Lanius.Mini.Compiler.P.stmtEval
import all Lanius.Mini.Compiler.P.codeSize
import all Lanius.Mini.Compiler.P.compileExpr
import all Lanius.Mini.Compiler.P.enumVariants
import all Lanius.Mini.Compiler.P.equality
import all Lanius.Mini.Compiler.P.arith
import all Lanius.Mini.Compiler.P.floatApply
import all Lanius.Mini.Compiler.P.floatArith
import all Lanius.Mini.Compiler.P.floatCompare
import all Lanius.Mini.Compiler.P.floatOrder
import all Lanius.Mini.Compiler.P.Code_image
import all Lanius.Mini.Compiler.P.Code_size
import all Lanius.Mini.Compiler.P.Instr_encode
import all Lanius.Mini.Compiler.P.argBase
import all Lanius.Mini.Compiler.P.copyBytes
import all Lanius.Mini.Compiler.P.encodeFrom
import all Lanius.Mini.Compiler.P.encodeOnto
import all Lanius.Mini.Compiler.P.epilogue
import all Lanius.Mini.Compiler.P.frameSize
import all Lanius.Mini.Compiler.P.layout
import all Lanius.Mini.Compiler.P.linkFrom
import all Lanius.Mini.Compiler.P.linkOnto
import all Lanius.Mini.Compiler.P.loadAtBytes
import all Lanius.Mini.Compiler.P.loadWordBytes
import all Lanius.Mini.Compiler.P.prologue
import all Lanius.Mini.Compiler.P.relative
import all Lanius.Mini.Compiler.P.slotRange
import all Lanius.Mini.Compiler.P.stackCheck
import all Lanius.Mini.Compiler.P.storeAtBytes
import all Lanius.Mini.Compiler.P.storeWordBytes
import all Lanius.Mini.Compiler.P.sysBytes
import all Lanius.Mini.Compiler.P.syscallLinuxByte
import all Lanius.Mini.Compiler.P.syscallLinuxHigh
import all Lanius.Mini.Compiler.P.syscallRsiBytes
import all Lanius.Mini.Compiler.P.UintTy_code
import all Lanius.Mini.Compiler.P.entriesAt
import all Lanius.Mini.Compiler.P.funcsSize
import all Lanius.Mini.Compiler.P.funcsSlots
import all Lanius.Mini.Compiler.P.linkObjects
import all Lanius.Mini.Compiler.P.objectExports
import all Lanius.Mini.Compiler.P.objectFirsts
import all Lanius.Mini.Compiler.P.objectLayout
import all Lanius.Mini.Compiler.P.objectsLayout
import all Lanius.Mini.Compiler.P.objectsOk
import all Lanius.Mini.Compiler.P.objectsSlots
import all Lanius.Mini.Compiler.P.render
import all Lanius.Mini.Compiler.P.renderFuncs
import all Lanius.Mini.Compiler.P.renderObjects
import all Lanius.Mini.Compiler.P.structFields
import all Lanius.Mini.Compiler.P.wordElement
import all Lanius.Mini.Compiler.P.declaredSame
import all Lanius.Mini.Compiler.P.declaredVariants
import all Lanius.Mini.Compiler.P.wordType
import all Lanius.Mini.Compiler.P.wordWidth
import all Lanius.Mini.Compiler.Types
public import Lanius.Mini.Compiler.P.SrcType_floatTy
public import Lanius.Mini.Compiler.P.SrcType_isBool
public import Lanius.Mini.Compiler.P.SrcType_isChar
public import Lanius.Mini.Compiler.P.SrcType_isFloat
public import Lanius.Mini.Compiler.P.SrcType_isFloatAny
public import Lanius.Mini.Compiler.P.SrcType_isI32
public import Lanius.Mini.Compiler.P.SrcType_isInteger
public import Lanius.Mini.Compiler.P.SrcType_isIsize
public import Lanius.Mini.Compiler.P.SrcType_isPtr
public import Lanius.Mini.Compiler.P.SrcType_isScalar
public import Lanius.Mini.Compiler.P.SrcType_isSint
public import Lanius.Mini.Compiler.P.SrcType_isSintAny
public import Lanius.Mini.Compiler.P.SrcType_isStr
public import Lanius.Mini.Compiler.P.SrcType_isUint
public import Lanius.Mini.Compiler.P.SrcType_isUnit
public import Lanius.Mini.Compiler.P.SrcType_sintKind
public import Lanius.Mini.Compiler.P.SrcType_uintKind
public import Lanius.Mini.Compiler.P.SrcType_word
public import Lanius.Mini.Compiler.P.UintTy_half
public import Lanius.Mini.Compiler.P.UintTy_leastBits
public import Lanius.Mini.Compiler.P.UintTy_signedWord
public import Lanius.Mini.Compiler.P.UintTy_spare
public import Lanius.Mini.Compiler.P.boolBits
public import Lanius.Mini.Compiler.P.lookup
public import Lanius.Mini.Compiler.P.Code_image
public import Lanius.Mini.Compiler.P.Code_size
public import Lanius.Mini.Compiler.P.Instr_encode
public import Lanius.Mini.Compiler.P.argBase
public import Lanius.Mini.Compiler.P.copyBytes
public import Lanius.Mini.Compiler.P.encodeFrom
public import Lanius.Mini.Compiler.P.encodeOnto
public import Lanius.Mini.Compiler.P.epilogue
public import Lanius.Mini.Compiler.P.frameSize
public import Lanius.Mini.Compiler.P.layout
public import Lanius.Mini.Compiler.P.linkFrom
public import Lanius.Mini.Compiler.P.linkOnto
public import Lanius.Mini.Compiler.P.loadAtBytes
public import Lanius.Mini.Compiler.P.loadWordBytes
public import Lanius.Mini.Compiler.P.prologue
public import Lanius.Mini.Compiler.P.relative
public import Lanius.Mini.Compiler.P.slotRange
public import Lanius.Mini.Compiler.P.stackCheck
public import Lanius.Mini.Compiler.P.storeAtBytes
public import Lanius.Mini.Compiler.P.storeWordBytes
public import Lanius.Mini.Compiler.P.sysBytes
public import Lanius.Mini.Compiler.P.syscallLinuxByte
public import Lanius.Mini.Compiler.P.syscallLinuxHigh
public import Lanius.Mini.Compiler.P.syscallRsiBytes
public import Lanius.Mini.Compiler.P.wordElement

@[expose] public section
/-! # Which programs the pure semantics is faithful to

`PureFunc` checks a function body by computing the source type of each
expression from the types of the locals in scope (`exprTy`, `effTy`): it
rules out what has no pure meaning (loops, assignment, raw memory, indexing),
field reads of boxes, struct literals of box types, and `==` on non-scalars
(Core compares an enum's payload words, boxes by address). Types are what
`VRel` needs to know which Core values are boxes, and what rules out Core's
`typeMismatch` (`Sim/Safe.lean`): operators take operands of one type,
numbers for arithmetic and `bool`s for `&&`, `||`, `!` and conditions.

`PrimsOk` says each prim is the prelude's `boxed<T>` or `unbox<T>` at a type
`T` the front pass can put in a raw slice (`wordElement`). -/

namespace Lanius.Faithful

open Lanius.Mini

/-- The scalar types `==` compares as Core does on the pure side. -/
def scalarTy : SrcType → Bool
  | .i32 | .bool | .uint _ | .isize | .unit => true
  | .struct _ _ | .enum _ _ | .ptr | .slice _ | .char | .float _ | .sint _ | .array _ _ | .view _ | .str | .ref _ => false

/-- The number types: Core's arithmetic, comparisons and casts take them. -/
def numTy : SrcType → Bool
  | .i32 | .uint _ | .isize => true
  | .bool | .struct _ _ | .enum _ _ | .ptr | .slice _ | .unit | .char | .float _ | .sint _ | .array _ _ | .view _ | .str | .ref _ => false

/-- The type of `left op right`, on operands of one type: comparisons of
numbers and `==` of scalars give `bool`, `&&` and `||` take `bool`s, and
arithmetic keeps its numbers' type. -/
def opTy (op : SrcOp) (left right : SrcType) : Option SrcType :=
  match op with
  | .less | .lessEq | .greater | .greaterEq => if numTy left && left.same right then some .bool else none
  | .equal | .notEqual => if scalarTy left && left.same right then some .bool else none
  | .logicalAnd | .logicalOr => if left.isBool && right.isBool then some .bool else none
  | .plus | .minus | .times | .bitAnd | .bitOr | .bitXor | .shiftLeft | .shiftRight =>
    if numTy left && left.same right then some left else none

/-- A number's type, for negation. -/
def numOf (t : SrcType) : Option SrcType := if numTy t then some t else none

/-- `!` of a `bool`. -/
def boolOf (t : SrcType) : Option SrcType := if t.isBool then some .bool else none

/-- A cast of a number of type `t` to the number type `ty`. -/
def castTy (ty t : SrcType) : Option SrcType := if numTy t && numTy ty then some ty else none

/-- A division of numbers of one type. -/
def divTy (left right : SrcType) : Option SrcType := if numTy left && left.same right then some left else none

/-- A condition's type is `bool`. -/
def isBoolTy : Option SrcType → Bool
  | some t => t.isBool
  | none => false

theorem numOf_some {t t' : SrcType} (h : numOf t = some t') : t' = t ∧ numTy t = true := by
  simp only [numOf] at h
  split at h
  · simp only [Option.some.injEq] at h; exact ⟨h.symm, by assumption⟩
  · simp at h

theorem SrcType.isBool_eq {t : SrcType} (h : t.isBool = true) : t = .bool := by
  cases t <;> simp_all [SrcType.isBool]

theorem boolOf_some {t t' : SrcType} (h : boolOf t = some t') : t' = .bool ∧ t = .bool := by
  simp only [boolOf] at h
  split at h
  · simp only [Option.some.injEq] at h; exact ⟨h.symm, SrcType.isBool_eq (by assumption)⟩
  · simp at h

theorem castTy_some {ty t t' : SrcType} (h : castTy ty t = some t') : t' = ty ∧ numTy t = true ∧ numTy ty = true := by
  simp only [castTy] at h
  split at h
  · rename_i ok
    simp only [Bool.and_eq_true] at ok
    simp only [Option.some.injEq] at h; exact ⟨h.symm, ok⟩
  · simp at h

theorem divTy_some {l r t : SrcType} (h : divTy l r = some t) : t = l ∧ numTy l = true ∧ r = l := by
  simp only [divTy] at h
  split at h
  · rename_i ok
    simp only [Bool.and_eq_true] at ok
    simp only [Option.some.injEq] at h; exact ⟨h.symm, ok.1, (SrcType.same_eq ok.2).symm⟩
  · simp at h

theorem isBoolTy_some {o : Option SrcType} (h : isBoolTy o = true) : o = some .bool := by
  cases o with
  | none => simp [isBoolTy] at h
  | some t => simp only [isBoolTy] at h; rw [SrcType.isBool_eq h]

/-- Field `index` of a struct that is not a box. -/
def fieldTy (boxes : Boxes) : SrcType → Nat → Option SrcType
  | .struct id fs, index => if (boxes id).isNone then fs[index]? else none
  | .i32, _ | .bool, _ | .uint _, _ | .enum _ _, _ | .ptr, _ | .slice _, _ | .unit, _ | .isize, _ | .char, _ | .float _, _ | .sint _, _ | .array _ _, _ | .view _, _ | .str, _ | .ref _, _ => none

/-- A struct literal of type `ty` from fields of types `ts`. -/
def structTy (boxes : Boxes) (ty : SrcType) (ts : List SrcType) : Option SrcType :=
  match ty with
  | .struct id fs => if (boxes id).isNone && typesSame ts fs then some ty else none
  | .i32 | .bool | .uint _ | .enum _ _ | .ptr | .slice _ | .unit | .isize | .char | .float _ | .sint _ | .array _ _ | .view _ | .str | .ref _ => none

/-- Variant `k` of the enum type `ty` from a payload of types `ts`. -/
def variantTy (ty : SrcType) (k : Nat) (ts : List SrcType) : Option SrcType :=
  match ty with
  | .enum _ variants =>
    match variants[k]? with
    | some fs => if typesSame ts fs then some ty else none
    | none => none
  | .i32 | .bool | .uint _ | .struct _ _ | .ptr | .slice _ | .unit | .isize | .char | .float _ | .sint _ | .array _ _ | .view _ | .str | .ref _ => none

/-- A call of `callee` on arguments of types `ts`, a function not `outside`
the pure fragment. -/
def callTy (sp : SrcProgram) (outside : List Nat) (callee : Nat) (ts : List SrcType) : Option SrcType :=
  if outside.contains callee then none
  else
    match sp.funcs[callee]? with
    | some f => if typesSame ts (f.params.map SrcParam.ty) then some f.ret else none
    | none => none

section
variable (sp : SrcProgram) (outside : List Nat) (boxes : Boxes)

def exprTy (tenv : TEnv) : SrcExpr → Option SrcType
  | .int _ => some .i32
  | .boolean _ => some .bool
  | .unsigned kind value => if value.toNat < 2 ^ kind.width then some (.uint kind) else none
  | .local id => tenv.get? id
  | .field id index => (tenv.get? id).bind (fieldTy boxes · index)
  | .negate operand => (exprTy tenv operand).bind numOf
  | .not operand => (exprTy tenv operand).bind boolOf
  | .apply op left right => (exprTy tenv left).bind fun l => (exprTy tenv right).bind (opTy op l)
  | .cast ty operand => (exprTy tenv operand).bind (castTy ty)
  | .null => none
  | .char _ => none
  | .float _ _ => none

def exprTys (tenv : TEnv) : List SrcExpr → Option (List SrcType)
  | [] => some []
  | e :: es => (exprTy boxes tenv e).bind fun t => (exprTys tenv es).map (t :: ·)

mutual
def effTy (tenv : TEnv) : SrcEff → Option SrcType
  | .ePure e => exprTy boxes tenv e
  | .eCall callee args => (effTys tenv args).bind (callTy sp outside callee)
  | .eApply op left right => (effTy tenv left).bind fun l => (effTy tenv right).bind (opTy op l)
  | .eNeg operand => (effTy tenv operand).bind numOf
  | .eNot operand => (effTy tenv operand).bind boolOf
  | .eCast ty operand => (effTy tenv operand).bind (castTy ty)
  | .eIndex _ _ => none
  | .eStruct ty fields => (effTys tenv fields).bind (structTy boxes ty)
  | .eVariant ty variant payload => (effTys tenv payload).bind (variantTy ty variant)
  | .eMatch scrutinee ety rty binders values =>
    (effTy tenv scrutinee).bind fun st =>
      match ety with
      | .enum _ variants => if st.same ety && armsOk tenv rty variants binders values then some rty else none
      | .i32 | .bool | .uint _ | .struct _ _ | .ptr | .slice _ | .unit | .isize | .char | .float _ | .sint _ | .array _ _ | .view _ | .str | .ref _ => none
  | .eDivide _ left right => (effTy tenv left).bind fun l => (effTy tenv right).bind (divTy l)
  | .eStride _ => none
  | .arraySlice _ _ => none
  | .eIf condition _ thenValue elseValue =>
    if isBoolTy (effTy tenv condition) then
      (effTy tenv thenValue).bind fun a => (effTy tenv elseValue).bind fun b => if a.same b then some a else none
    else none
  | .eLet id _ value _ body => (effTy tenv value).bind fun t => effTy ((id, t) :: tenv) body
  | .eLen _ | .eStr _ _ | .eBorrow _ _ | .eDeref _ _ | .eField _ _ | .eAt _ _ => none

def effTys (tenv : TEnv) : List SrcEff → Option (List SrcType)
  | [] => some []
  | e :: es => (effTy tenv e).bind fun t => (effTys tenv es).map (t :: ·)

/-- Arm `k` binds variant `k`'s whole payload, and its value has type `rty`. -/
def armsOk (tenv : TEnv) (rty : SrcType) : List (List SrcType) → List (List Nat) → List SrcEff → Bool
  | _, [], [] => true
  | _, [], _ :: _ => false
  | _, _ :: _, [] => false
  | [], _ :: _, _ :: _ => false
  | fs :: variants, binders :: rest, value :: values =>
    binders.length == fs.length &&
      (match effTy (tenv.bindAll (binders.zip fs)) value with
       | some t => t.same rty
       | none => false) &&
      armsOk tenv rty variants rest values
end

/-- An assignment `id = value` takes a bound local and a value of its type. -/
def setOk (tenv : TEnv) (id : Nat) (value : Option SrcType) : Bool :=
  match tenv.get? id with
  | some t =>
    match value with
    | some t' => t'.same t
    | none => false
  | none => false

/-- A body with a pure meaning, whose returns have type `ret`. -/
def stmtOk (ret : SrcType) (tenv : TEnv) : SrcStmt → Bool
  | .nop => true
  | .let id _ value body =>
    match exprTy boxes tenv value with
    | some t => stmtOk ret ((id, t) :: tenv) body
    | none => false
  | .letStruct id ty fields body =>
    match (exprTys boxes tenv fields).bind (structTy boxes ty) with
    | some t => stmtOk ret ((id, t) :: tenv) body
    | none => false
  | .letCall id _ callee args body =>
    match (exprTys boxes tenv args).bind (callTy sp outside callee) with
    | some t => stmtOk ret ((id, t) :: tenv) body
    | none => false
  | .letEnum id ty variant payload body =>
    match (exprTys boxes tenv payload).bind (variantTy ty variant) with
    | some t => stmtOk ret ((id, t) :: tenv) body
    | none => false
  | .letMatch _ _ _ _ _ _ => false
  | .set id value => setOk tenv id (exprTy boxes tenv value)
  | .setField _ _ _ => false
  | .setCall _ _ _ => false
  | .then first second => stmtOk ret tenv first && stmtOk ret tenv second
  | .if condition thenBranch elseBranch =>
    isBoolTy (exprTy boxes tenv condition) && stmtOk ret tenv thenBranch && stmtOk ret tenv elseBranch
  | .while condition body => isBoolTy (exprTy boxes tenv condition) && stmtOk ret tenv body
  | .return value =>
    match exprTy boxes tenv value with
    | some t => t.same ret
    | none => false
  | .letAlloc _ _ _ _ => false
  | .letView _ _ _ _ _ => false
  | .letStr _ _ _ => false
  | .letLoad _ _ _ _ => false
  | .setByte _ _ _ => false
  | .free _ _ _ => false
  | .letSlice _ _ _ _ _ => false
  | .letIndex _ _ _ _ _ => false
  | .setIndex _ _ _ => false
  | .letEval id _ value body =>
    match effTy sp outside boxes tenv value with
    | some t => stmtOk ret ((id, t) :: tenv) body
    | none => false
  | .setEval id value => setOk tenv id (effTy sp outside boxes tenv value)
  | .ifEval condition thenBranch elseBranch =>
    isBoolTy (effTy sp outside boxes tenv condition) && stmtOk ret tenv thenBranch && stmtOk ret tenv elseBranch
  | .whileEval condition body => isBoolTy (effTy sp outside boxes tenv condition) && stmtOk ret tenv body
  | .returnEval value =>
    match effTy sp outside boxes tenv value with
    | some t => t.same ret
    | none => false
  | .discard value => (effTy sp outside boxes tenv value).isSome
  | .setIndexEval _ _ _ => false
  | .setFieldEval _ _ _ => false
  | .setPlace _ _ => false
  | .setPlaceOp _ _ _ => false
  | .returnUnit => true
  | .assert condition => isBoolTy (effTy sp outside boxes tenv condition)
  | .break => true
  | .continue => true
  | .matchArm _ _ _ _ _ _ _ _ => false
  | .unreachable _ _ => false

end

/-- The box struct ids: the return type of each `boxed` instance, holding its
parameter's type. -/
def boxElem (sp : SrcProgram) (prims : Prims) : Boxes := fun id =>
  prims.boxed.findSome? fun i =>
    (sp.funcs[i]?).bind fun f =>
      match f.params with
      | [p] => if f.ret.typeId = id then some p.ty else none
      | _ => none

/-- A `break` or `continue` outside every loop of the statement
(`SrcStmt.breaksOut`, which `looseJump_eq` shows it is): a body that ends
with one makes its call trap. -/
def looseJump : SrcStmt → Bool
  | .nop => false
  | .let _ _ _ body => looseJump body
  | .letStruct _ _ _ body => looseJump body
  | .letCall _ _ _ _ body => looseJump body
  | .letEnum _ _ _ _ body => looseJump body
  | .letMatch _ _ _ _ _ body => looseJump body
  | .set _ _ => false
  | .setField _ _ _ => false
  | .setCall _ _ _ => false
  | .then first second => looseJump first || looseJump second
  | .if _ thenBranch elseBranch => looseJump thenBranch || looseJump elseBranch
  | .while _ _ => false
  | .return _ => false
  | .letAlloc _ _ _ body => looseJump body
  | .letView _ _ _ _ body => looseJump body
  | .letStr _ _ body => looseJump body
  | .letLoad _ _ _ body => looseJump body
  | .setByte _ _ _ => false
  | .free _ _ _ => false
  | .letSlice _ _ _ _ body => looseJump body
  | .letIndex _ _ _ _ body => looseJump body
  | .setIndex _ _ _ => false
  | .letEval _ _ _ body => looseJump body
  | .setEval _ _ => false
  | .ifEval _ thenBranch elseBranch => looseJump thenBranch || looseJump elseBranch
  | .whileEval _ _ => false
  | .returnEval _ => false
  | .discard _ => false
  | .setIndexEval _ _ _ => false
  | .setFieldEval _ _ _ => false
  | .setPlace _ _ => false
  | .setPlaceOp _ _ _ => false
  | .returnUnit => false
  | .assert _ => false
  | .break => true
  | .continue => true
  | .matchArm _ _ _ _ _ _ body rest => looseJump body || looseJump rest
  | .unreachable _ _ => false

/-- A body with a pure meaning, and no `break` or `continue` outside its loops. -/
def PureFunc (sp : SrcProgram) (prims : Prims) (outside : List Nat) (f : SrcFunc) : Bool :=
  stmtOk sp outside (boxElem sp prims) f.ret (paramTEnv f.params) f.body && !looseJump f.body

theorem PureFunc.stmt {sp : SrcProgram} {prims : Prims} {outside : List Nat} {f : SrcFunc}
    (h : PureFunc sp prims outside f = true) :
    stmtOk sp outside (boxElem sp prims) f.ret (paramTEnv f.params) f.body = true :=
  ((Bool.and_eq_true _ _).mp h).1

theorem PureFunc.noJump {sp : SrcProgram} {prims : Prims} {outside : List Nat} {f : SrcFunc}
    (h : PureFunc sp prims outside f = true) : looseJump f.body = false := by
  have := ((Bool.and_eq_true _ _).mp h).2
  simpa using this

/-- Every function but the prims and those `outside` (the driver, the prims'
helpers), which pure functions do not call, has a pure meaning. -/
def PureProg (sp : SrcProgram) (prims : Prims) (outside : List Nat) : Prop :=
  ∀ i f, sp.funcs[i]? = some f → prims.isPrim i = false → outside.contains i = false →
    PureFunc sp prims outside f = true

/-! ## The prims -/

/-- `size_of<T>()`: the stride of a null view, negated. -/
def sizeOfFunc (t : SrcType) : SrcFunc where
  params := []
  ret := .uint .usize
  body := .let 32 .ptr .null (.letSlice 58 t (.local 32) (.int 0) (.letEval 113 .isize (.eStride 58)
    (.then (.if (.apply .less (.local 113) (.cast .isize (.int 0)))
        (.return (.cast (.uint .usize) (.apply .minus (.cast .isize (.int 0)) (.local 113)))) .nop)
      (.return (.cast (.uint .usize) (.local 113))))))

/-- `typed_slice_from_storage<T>(storage, len)`: a view whose element 0 is the
storage's last word for a downward stride. -/
def sliceFunc (t : SrcType) : SrcFunc where
  params := [{ id := 28, ty := .ptr }, { id := 42, ty := .i32 }]
  ret := .slice t
  body := .then (.assert (.ePure (.apply .greaterEq (.local 42) (.int 0))))
    (.let 97 .ptr .null (.letSlice 123 t (.local 97) (.int 0) (.letEval 178 .isize (.eStride 123)
      (.then (.if (.apply .logicalOr (.apply .greaterEq (.local 178) (.cast .isize (.int 0)))
            (.apply .equal (.local 42) (.int 0)))
          (.letSlice 268 t (.local 28) (.local 42) (.return (.local 268))) .nop)
        (.let 321 (.uint .usize) (.apply .minus (.apply .times
            (.cast (.uint .usize) (.apply .minus (.cast .isize (.int 0)) (.local 178)))
            (.cast (.uint .usize) (.local 42))) (.unsigned .usize 8))
          (.letSlice 394 t (.apply .plus (.local 28) (.local 321)) (.local 42)
            (.return (.local 394))))))))

def panicFunc : SrcFunc where
  params := []
  ret := .unit
  body := .assert (.ePure (.boolean false))

/-- `boxed<T>(value)` with the box struct `id`. -/
def boxedFunc (t : SrcType) (id sizeOf slice panic : Nat) : SrcFunc where
  params := [{ id := 9, ty := t }]
  ret := .struct id [.ptr]
  body := .letCall 39 (.uint .usize) sizeOf [] (.letAlloc 86 (.local 39) 3
    (.then (.if (.apply .equal (.local 86) .null) (.discard (.eCall panic [])) .nop)
      (.letCall 203 (.slice t) slice [.local 86, .int 1]
        (.then (.setIndex 203 (.int 0) (.local 9))
          (.returnEval (.eStruct (.struct id [.ptr]) [.ePure (.local 86)]))))))

/-- `unbox<T>(value)` with the box struct `id`. -/
def unboxFunc (t : SrcType) (id slice : Nat) : SrcFunc where
  params := [{ id := 9, ty := .struct id [.ptr] }]
  ret := t
  body := .letCall 39 (.slice t) slice [.field 9 0, .int 1]
    (.returnEval (.eIndex 39 (.ePure (.int 0))))

/-- The declarations of `ds` as a Core program: the native layout reads only
these. -/
def declsCore (ds : SrcDecls) : Core.Program where
  structures := ds.structs.map SrcStructDecl.toCore
  enumerations := ds.enums.map SrcEnumDecl.toCore

theorem words?_toCore (sp : SrcProgram) :
    ∀ n T, NativeLayout.words? n sp.toCore T = NativeLayout.words? n (declsCore sp.decls) T := by
  intro n
  induction n with
  | zero => intro T; rfl
  | succ n ih =>
    have same : NativeLayout.words? n sp.toCore = NativeLayout.words? n (declsCore sp.decls) := funext ih
    intro T
    simp only [NativeLayout.words?, same]
    rfl

theorem valueWords_toCore (sp : SrcProgram) (T : Core.Ty) :
    NativeLayout.valueWords? sp.toCore T = NativeLayout.valueWords? (declsCore sp.decls) T :=
  words?_toCore sp _ T

/-- Function `i` is `boxed<t>`, of the box struct `id`, and `t` has a native
layout (Core's raw views of a type past its limits trap `typeMismatch`). -/
def BoxedAt (sp : SrcProgram) (prims : Prims) (i : Nat) : Prop :=
  ∃ t id sizeOf slice panic, sp.funcs[i]? = some (boxedFunc t id sizeOf slice panic) ∧
    sp.funcs[sizeOf]? = some (sizeOfFunc t) ∧ sp.funcs[slice]? = some (sliceFunc t) ∧
    sp.funcs[panic]? = some panicFunc ∧ wordElement sp.decls t = true ∧ boxElem sp prims id = some t ∧
    (NativeLayout.valueWords? (declsCore sp.decls) t.toCore).isSome = true

/-- Function `i` is `unbox<t>`, of the box struct `id`. -/
def UnboxAt (sp : SrcProgram) (prims : Prims) (i : Nat) : Prop :=
  ∃ t id slice, sp.funcs[i]? = some (unboxFunc t id slice) ∧ sp.funcs[slice]? = some (sliceFunc t) ∧
    wordElement sp.decls t = true ∧ boxElem sp prims id = some t

def PrimsOk (sp : SrcProgram) (prims : Prims) : Prop :=
  (∀ i ∈ prims.boxed, BoxedAt sp prims i) ∧ ∀ i ∈ prims.unbox, UnboxAt sp prims i

end Lanius.Faithful
