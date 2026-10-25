import Lanius.Faithful.Sim.Rel
import Lanius.Mini.SliceLayout

/-! # Which programs the pure semantics is faithful to

`PureFunc` checks a function body by computing the source type of each
expression from the types of the locals in scope (`exprTy`, `effTy`): it
rules out what has no pure meaning (loops, assignment, raw memory, indexing),
field reads of boxes, struct literals of box types, and `==` on non-scalars
(Core compares an enum's payload words, boxes by address). Types are what
`VRel` needs to know which Core values are boxes; Core's own checks do the
rest, so arithmetic just keeps its left operand's type.

`PrimsOk` says each prim is the prelude's `boxed<T>` or `unbox<T>` at a type
`T` the front pass can put in a raw slice (`wordElement`). -/

namespace Lanius.Faithful

open Lanius.Mini

/-- The scalar types `==` compares as Core does on the pure side. -/
def scalarTy : SrcType → Bool
  | .i32 | .bool | .uint _ | .isize | .unit => true
  | .struct _ _ | .enum _ _ | .ptr | .slice _ => false

/-- The type of `left op right`: comparisons give `bool`, `&&` and `||` give
their `bool` right side, arithmetic keeps the left side's type. -/
def opTy (op : SrcOp) (left right : SrcType) : Option SrcType :=
  match op with
  | .less | .lessEq | .greater | .greaterEq => some .bool
  | .equal | .notEqual => if scalarTy left then some .bool else none
  | .logicalAnd | .logicalOr => if right.isBool then some .bool else none
  | .plus | .minus | .times | .bitAnd | .bitOr | .bitXor | .shiftLeft | .shiftRight => some left

/-- Field `index` of a struct that is not a box. -/
def fieldTy (boxes : Boxes) : SrcType → Nat → Option SrcType
  | .struct id fs, index => if (boxes id).isNone then fs[index]? else none
  | .i32, _ | .bool, _ | .uint _, _ | .enum _ _, _ | .ptr, _ | .slice _, _ | .unit, _ | .isize, _ => none

/-- A struct literal of type `ty` from fields of types `ts`. -/
def structTy (boxes : Boxes) (ty : SrcType) (ts : List SrcType) : Option SrcType :=
  match ty with
  | .struct id fs => if (boxes id).isNone && typesSame ts fs then some ty else none
  | .i32 | .bool | .uint _ | .enum _ _ | .ptr | .slice _ | .unit | .isize => none

/-- Variant `k` of the enum type `ty` from a payload of types `ts`. -/
def variantTy (ty : SrcType) (k : Nat) (ts : List SrcType) : Option SrcType :=
  match ty with
  | .enum _ variants =>
    match variants[k]? with
    | some fs => if typesSame ts fs then some ty else none
    | none => none
  | .i32 | .bool | .uint _ | .struct _ _ | .ptr | .slice _ | .unit | .isize => none

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
  | .negate operand => exprTy tenv operand
  | .not operand => (exprTy tenv operand).map fun _ => .bool
  | .apply op left right => (exprTy tenv left).bind fun l => (exprTy tenv right).bind (opTy op l)
  | .cast ty operand => (exprTy tenv operand).map fun _ => ty
  | .null => none

def exprTys (tenv : TEnv) : List SrcExpr → Option (List SrcType)
  | [] => some []
  | e :: es => (exprTy boxes tenv e).bind fun t => (exprTys tenv es).map (t :: ·)

mutual
def effTy (tenv : TEnv) : SrcEff → Option SrcType
  | .ePure e => exprTy boxes tenv e
  | .eCall callee args => (effTys tenv args).bind (callTy sp outside callee)
  | .eApply op left right => (effTy tenv left).bind fun l => (effTy tenv right).bind (opTy op l)
  | .eNeg operand => effTy tenv operand
  | .eNot operand => (effTy tenv operand).map fun _ => .bool
  | .eCast ty operand => (effTy tenv operand).map fun _ => ty
  | .eIndex _ _ => none
  | .eStruct ty fields => (effTys tenv fields).bind (structTy boxes ty)
  | .eVariant ty variant payload => (effTys tenv payload).bind (variantTy ty variant)
  | .eMatch scrutinee ety rty binders values =>
    (effTy tenv scrutinee).bind fun st =>
      match ety with
      | .enum _ variants => if st.same ety && armsOk tenv rty variants binders values then some rty else none
      | .i32 | .bool | .uint _ | .struct _ _ | .ptr | .slice _ | .unit | .isize => none
  | .eDivide _ left right => (effTy tenv left).bind fun l => (effTy tenv right).map fun _ => l
  | .eStride _ => none

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
  | .set _ _ => false
  | .setField _ _ _ => false
  | .setCall _ _ _ => false
  | .then first second => stmtOk ret tenv first && stmtOk ret tenv second
  | .if condition thenBranch elseBranch =>
    (exprTy boxes tenv condition).isSome && stmtOk ret tenv thenBranch && stmtOk ret tenv elseBranch
  | .while _ _ => false
  | .return value =>
    match exprTy boxes tenv value with
    | some t => t.same ret
    | none => false
  | .letAlloc _ _ _ _ => false
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
  | .setEval _ _ => false
  | .ifEval condition thenBranch elseBranch =>
    (effTy sp outside boxes tenv condition).isSome && stmtOk ret tenv thenBranch && stmtOk ret tenv elseBranch
  | .whileEval _ _ => false
  | .returnEval value =>
    match effTy sp outside boxes tenv value with
    | some t => t.same ret
    | none => false
  | .discard value => (effTy sp outside boxes tenv value).isSome
  | .setIndexEval _ _ _ => false
  | .setFieldEval _ _ _ => false
  | .returnUnit => true
  | .assert condition => (effTy sp outside boxes tenv condition).isSome

end

/-- The box struct ids: the return type of each `boxed` instance, holding its
parameter's type. -/
def boxElem (sp : SrcProgram) (prims : Prims) : Boxes := fun id =>
  prims.boxed.findSome? fun i =>
    (sp.funcs[i]?).bind fun f =>
      match f.params with
      | [p] => if f.ret.typeId = id then some p.ty else none
      | _ => none

def PureFunc (sp : SrcProgram) (prims : Prims) (outside : List Nat) (f : SrcFunc) : Bool :=
  stmtOk sp outside (boxElem sp prims) f.ret (paramTEnv f.params) f.body

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
  body := .let 2525 .ptr .null (.letSlice 2551 t (.local 2525) (.int 0) (.letEval 2606 .isize (.eStride 2551)
    (.then (.if (.apply .less (.local 2606) (.cast .isize (.int 0)))
        (.return (.cast (.uint .usize) (.apply .minus (.cast .isize (.int 0)) (.local 2606)))) .nop)
      (.return (.cast (.uint .usize) (.local 2606))))))

/-- `typed_slice_from_storage<T>(storage, len)`: a view whose element 0 is the
storage's last word for a downward stride. -/
def sliceFunc (t : SrcType) : SrcFunc where
  params := [{ id := 3284, ty := .ptr }, { id := 3298, ty := .i32 }]
  ret := .slice t
  body := .then (.assert (.ePure (.apply .greaterEq (.local 3298) (.int 0))))
    (.let 3353 .ptr .null (.letSlice 3379 t (.local 3353) (.int 0) (.letEval 3434 .isize (.eStride 3379)
      (.then (.if (.apply .logicalOr (.apply .greaterEq (.local 3434) (.cast .isize (.int 0)))
            (.apply .equal (.local 3298) (.int 0)))
          (.letSlice 3524 t (.local 3284) (.local 3298) (.return (.local 3524))) .nop)
        (.let 3577 (.uint .usize) (.apply .minus (.apply .times
            (.cast (.uint .usize) (.apply .minus (.cast .isize (.int 0)) (.local 3434)))
            (.cast (.uint .usize) (.local 3298))) (.unsigned .usize 8))
          (.letSlice 3650 t (.apply .plus (.local 3284) (.local 3577)) (.local 3298)
            (.return (.local 3650))))))))

def panicFunc : SrcFunc where
  params := []
  ret := .unit
  body := .assert (.ePure (.boolean false))

/-- `boxed<T>(value)` with the box struct `id`. -/
def boxedFunc (t : SrcType) (id sizeOf slice panic : Nat) : SrcFunc where
  params := [{ id := 827, ty := t }]
  ret := .struct id [.ptr]
  body := .letCall 857 (.uint .usize) sizeOf [] (.letAlloc 904 (.local 857) 3
    (.then (.if (.apply .equal (.local 904) .null) (.discard (.eCall panic [])) .nop)
      (.letCall 1021 (.slice t) slice [.local 904, .int 1]
        (.then (.setIndex 1021 (.int 0) (.local 827))
          (.returnEval (.eStruct (.struct id [.ptr]) [.ePure (.local 904)]))))))

/-- `unbox<T>(value)` with the box struct `id`. -/
def unboxFunc (t : SrcType) (id slice : Nat) : SrcFunc where
  params := [{ id := 1159, ty := .struct id [.ptr] }]
  ret := t
  body := .letCall 1189 (.slice t) slice [.field 1159 0, .int 1]
    (.returnEval (.eIndex 1189 (.ePure (.int 0))))

/-- Function `i` is `boxed<t>`, of the box struct `id`. -/
def BoxedAt (sp : SrcProgram) (prims : Prims) (i : Nat) : Prop :=
  ∃ t id sizeOf slice panic, sp.funcs[i]? = some (boxedFunc t id sizeOf slice panic) ∧
    sp.funcs[sizeOf]? = some (sizeOfFunc t) ∧ sp.funcs[slice]? = some (sliceFunc t) ∧
    sp.funcs[panic]? = some panicFunc ∧ wordElement sp.decls t = true ∧ boxElem sp prims id = some t

/-- Function `i` is `unbox<t>`, of the box struct `id`. -/
def UnboxAt (sp : SrcProgram) (prims : Prims) (i : Nat) : Prop :=
  ∃ t id slice, sp.funcs[i]? = some (unboxFunc t id slice) ∧ sp.funcs[slice]? = some (sliceFunc t) ∧
    wordElement sp.decls t = true ∧ boxElem sp prims id = some t

def PrimsOk (sp : SrcProgram) (prims : Prims) : Prop :=
  (∀ i ∈ prims.boxed, BoxedAt sp prims i) ∧ ∀ i ∈ prims.unbox, UnboxAt sp prims i

end Lanius.Faithful
