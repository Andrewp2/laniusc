import Lanius.Faithful.Sim.Rel
import Lanius.Mini.SliceLayout

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
  | .struct _ _ | .enum _ _ | .ptr | .slice _ | .sint _ => false

/-- The number types: Core's arithmetic, comparisons and casts take them. -/
def numTy : SrcType → Bool
  | .i32 | .uint _ | .isize => true
  | .bool | .struct _ _ | .enum _ _ | .ptr | .slice _ | .unit | .sint _ => false

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
  | .i32, _ | .bool, _ | .uint _, _ | .enum _ _, _ | .ptr, _ | .slice _, _ | .unit, _ | .isize, _ | .sint _, _ => none

/-- A struct literal of type `ty` from fields of types `ts`. -/
def structTy (boxes : Boxes) (ty : SrcType) (ts : List SrcType) : Option SrcType :=
  match ty with
  | .struct id fs => if (boxes id).isNone && typesSame ts fs then some ty else none
  | .i32 | .bool | .uint _ | .enum _ _ | .ptr | .slice _ | .unit | .isize | .sint _ => none

/-- Variant `k` of the enum type `ty` from a payload of types `ts`. -/
def variantTy (ty : SrcType) (k : Nat) (ts : List SrcType) : Option SrcType :=
  match ty with
  | .enum _ variants =>
    match variants[k]? with
    | some fs => if typesSame ts fs then some ty else none
    | none => none
  | .i32 | .bool | .uint _ | .struct _ _ | .ptr | .slice _ | .unit | .isize | .sint _ => none

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
      | .i32 | .bool | .uint _ | .struct _ _ | .ptr | .slice _ | .unit | .isize | .sint _ => none
  | .eDivide _ left right => (effTy tenv left).bind fun l => (effTy tenv right).bind (divTy l)
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
    isBoolTy (exprTy boxes tenv condition) && stmtOk ret tenv thenBranch && stmtOk ret tenv elseBranch
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
    isBoolTy (effTy sp outside boxes tenv condition) && stmtOk ret tenv thenBranch && stmtOk ret tenv elseBranch
  | .whileEval _ _ => false
  | .returnEval value =>
    match effTy sp outside boxes tenv value with
    | some t => t.same ret
    | none => false
  | .discard value => (effTy sp outside boxes tenv value).isSome
  | .setIndexEval _ _ _ => false
  | .setFieldEval _ _ _ => false
  | .returnUnit => true
  | .assert condition => isBoolTy (effTy sp outside boxes tenv condition)

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
