module

public import Lanius.Faithful.Sim.Check
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
import all Lanius.Mini.Compiler.P.codeSize
import all Lanius.Mini.Compiler.P.compileExpr
import all Lanius.Mini.Compiler.P.declareFuncs
import all Lanius.Mini.Compiler.P.BinOp_compute
import all Lanius.Mini.Compiler.P.declareProgram
import all Lanius.Mini.Compiler.P.funcsReturn
import all Lanius.Mini.Compiler.P.lowBits
import all Lanius.Mini.Compiler.P.signedKey
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
import all Lanius.Mini.Compiler.P.SrcStmt_declare
import all Lanius.Mini.Compiler.P.SrcStmt_returns
import all Lanius.Mini.Compiler.P.SrcType_declare
import all Lanius.Mini.Compiler.P.declareEnum
import all Lanius.Mini.Compiler.P.declareFunc
import all Lanius.Mini.Compiler.P.declareParams
import all Lanius.Mini.Compiler.P.declareStruct
import all Lanius.Mini.Compiler.P.keepIf
import all Lanius.Mini.Compiler.P.lowerBody
import all Lanius.Mini.Compiler.P.lowerFunc
import all Lanius.Mini.Compiler.P.lowerFuncCons
import all Lanius.Mini.Compiler.P.lowerFuncs
import all Lanius.Mini.Compiler.P.unitTail
import all Lanius.Mini.Compiler.P.withFrame
import all Lanius.Mini.Compiler.P.SrcEff_types
import all Lanius.Mini.Compiler.P.evalIf
import all Lanius.Mini.Compiler.P.evalIfOf
import all Lanius.Mini.Compiler.P.evalLetIn
import all Lanius.Mini.Compiler.P.evalLetInOf
import all Lanius.Mini.Compiler.P.evalMatch
import all Lanius.Mini.Compiler.P.evalMatchOf
import all Lanius.Mini.Compiler.P.lowerDiscard
import all Lanius.Mini.Compiler.P.lowerIfEval
import all Lanius.Mini.Compiler.P.lowerLet
import all Lanius.Mini.Compiler.P.lowerLetCall
import all Lanius.Mini.Compiler.P.lowerLetEval
import all Lanius.Mini.Compiler.P.lowerReturnEval
import all Lanius.Mini.Compiler.P.lowerSetEval
import all Lanius.Mini.Compiler.P.lowerWhileEval
import all Lanius.Mini.Compiler.P.matchVariants
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
public import Lanius.Mini.Compiler.P.BinOp_compute
public import Lanius.Mini.Compiler.P.declareProgram
public import Lanius.Mini.Compiler.P.funcsReturn
public import Lanius.Mini.Compiler.P.lowBits
public import Lanius.Mini.Compiler.P.signedKey
public import Lanius.Mini.Compiler.P.wordElement

@[expose] public section
/-! # `PureProg` one function at a time

`PureProg` of a concrete program, from one fact per function (`FuncOk`): a
prim, a function `outside`, or a pure function. `FuncsOk n fs` says it of the
functions `fs` numbered from `n`, so a run of functions is checked on its
own (`funcsOk_cons`) and runs are put together (`funcsOk_append`). -/

namespace Lanius.Faithful

open Lanius.Mini

section
variable {sp : SrcProgram} {prims : Prims} {outside : List Nat}

/-- What `PureProg` asks of function `i`, `f`. -/
def FuncOk (sp : SrcProgram) (prims : Prims) (outside : List Nat) (i : Nat) (f : SrcFunc) : Prop :=
  prims.isPrim i = false → outside.contains i = false → PureFunc sp prims outside f = true

/-- What `PureProg` asks of the functions `fs`, numbered from `n`. -/
def FuncsOk (sp : SrcProgram) (prims : Prims) (outside : List Nat) (n : Nat) (fs : List SrcFunc) : Prop :=
  ∀ j f, fs[j]? = some f → FuncOk sp prims outside (n + j) f

theorem funcOk_pure {i : Nat} {f : SrcFunc} (h : PureFunc sp prims outside f = true) :
    FuncOk sp prims outside i f :=
  fun _ _ => h

theorem funcOk_prim {i : Nat} {f : SrcFunc} (h : prims.isPrim i = true) : FuncOk sp prims outside i f :=
  fun np _ => absurd h (by rw [np]; exact Bool.false_ne_true)

theorem funcOk_outside {i : Nat} {f : SrcFunc} (h : outside.contains i = true) :
    FuncOk sp prims outside i f :=
  fun _ no => absurd h (by rw [no]; exact Bool.false_ne_true)

theorem funcsOk_nil {n : Nat} : FuncsOk sp prims outside n [] :=
  fun _ _ h => nomatch h

theorem funcsOk_cons {n : Nat} {f : SrcFunc} {fs : List SrcFunc} (head : FuncOk sp prims outside n f)
    (tail : FuncsOk sp prims outside (n + 1) fs) : FuncsOk sp prims outside n (f :: fs)
  | 0, g, h => by
    rw [List.getElem?_cons_zero, Option.some.injEq] at h
    subst h
    exact head
  | j + 1, g, h => by
    rw [List.getElem?_cons_succ] at h
    have := tail j g h
    rwa [Nat.add_assoc, Nat.add_comm 1 j] at this

theorem funcsOk_append {n : Nat} {xs ys : List SrcFunc} (left : FuncsOk sp prims outside n xs)
    (right : FuncsOk sp prims outside (n + xs.length) ys) : FuncsOk sp prims outside n (xs ++ ys) := by
  intro j f h
  by_cases lt : j < xs.length
  · rw [List.getElem?_append_left lt] at h
    exact left j f h
  · have le : xs.length ≤ j := Nat.le_of_not_lt lt
    rw [List.getElem?_append_right le] at h
    have := right (j - xs.length) f h
    rwa [Nat.add_assoc, Nat.add_sub_cancel' le] at this

theorem pureProg_of_funcsOk (h : FuncsOk sp prims outside 0 sp.funcs) : PureProg sp prims outside := by
  intro i f found np no
  have := h i f found
  rw [Nat.zero_add] at this
  exact this np no

end

/-! ## The box structs, computed once

`boxElem` looks each `boxed` prim up in the program at every field read; a
concrete program's box structs are listed once (`boxPairs`) and looked up in
the list (`boxElem_eq`). -/

/-- The box struct id and element type of function `i`, a `boxed` prim. -/
def boxPair (sp : SrcProgram) (i : Nat) : Option (Nat × SrcType) :=
  (sp.funcs[i]?).bind fun f =>
    match f.params with
    | [] => none
    | [p] => some (f.ret.typeId, p.ty)
    | _ :: _ :: _ => none

/-- The element type of box struct `id` in a list of `boxPair`s. -/
def lookupBox (pairs : List (Option (Nat × SrcType))) (id : Nat) : Option SrcType :=
  pairs.findSome? fun pair => pair.bind fun kt => if kt.1 = id then some kt.2 else none

theorem boxElem_eq_lookup (sp : SrcProgram) (prims : Prims) (id : Nat) :
    boxElem sp prims id = lookupBox (prims.boxed.map (boxPair sp)) id := by
  unfold boxElem lookupBox
  induction prims.boxed with
  | nil => rfl
  | cons i rest ih =>
    rw [List.map_cons, List.findSome?_cons, List.findSome?_cons, ih]
    unfold boxPair
    cases sp.funcs[i]? with
    | none => rfl
    | some f =>
      simp only [Option.bind_some]
      match f.params with
      | [] => rfl
      | [p] => rfl
      | _ :: _ :: _ => rfl

def pairsSame : List (Option (Nat × SrcType)) → List (Option (Nat × SrcType)) → Bool
  | [], [] => true
  | [], _ :: _ => false
  | _ :: _, [] => false
  | none :: as, none :: bs => pairsSame as bs
  | none :: _, some _ :: _ => false
  | some _ :: _, none :: _ => false
  | some (i, s) :: as, some (j, t) :: bs => decide (i = j) && s.same t && pairsSame as bs

theorem pairsSame_eq : ∀ {as bs : List (Option (Nat × SrcType))}, pairsSame as bs = true → as = bs
  | [], [], _ => rfl
  | [], _ :: _, h => nomatch h
  | _ :: _, [], h => nomatch h
  | none :: as, none :: bs, h => by rw [pairsSame_eq (as := as) (bs := bs) h]
  | none :: _, some _ :: _, h => nomatch h
  | some _ :: _, none :: _, h => nomatch h
  | some (i, s) :: as, some (j, t) :: bs, h => by
    simp only [pairsSame, Bool.and_eq_true, decide_eq_true_eq] at h
    obtain ⟨⟨rfl, same⟩, rest⟩ := h
    rw [SrcType.same_eq same, pairsSame_eq rest]

theorem boxElem_eq {sp : SrcProgram} {prims : Prims} {pairs : List (Option (Nat × SrcType))}
    (h : pairsSame (prims.boxed.map (boxPair sp)) pairs = true) : boxElem sp prims = lookupBox pairs := by
  funext id
  rw [boxElem_eq_lookup, pairsSame_eq h]

/-! ## Declarations, computed once

`PrimsOk` asks `wordElement sp.decls t` of each prim's type; `declareProgram`
is slow to reduce, so a concrete program's declarations are compared once
with their value (`declsSame_eq`). -/

def structsSame : List SrcStructDecl → List SrcStructDecl → Bool
  | [], [] => true
  | [], _ :: _ => false
  | _ :: _, [] => false
  | a :: as, b :: bs => decide (a.id = b.id) && typesSame a.fields b.fields && structsSame as bs

def enumsSame : List SrcEnumDecl → List SrcEnumDecl → Bool
  | [], [] => true
  | [], _ :: _ => false
  | _ :: _, [] => false
  | a :: as, b :: bs => decide (a.id = b.id) && variantsSame a.variants b.variants && enumsSame as bs

def declsSame (a b : SrcDecls) : Bool :=
  structsSame a.structs b.structs && enumsSame a.enums b.enums && decide (a.statics = b.statics)

theorem structsSame_eq : ∀ {as bs : List SrcStructDecl}, structsSame as bs = true → as = bs
  | [], [], _ => rfl
  | [], _ :: _, h => nomatch h
  | _ :: _, [], h => nomatch h
  | ⟨i, fs⟩ :: as, ⟨j, gs⟩ :: bs, h => by
    simp only [structsSame, Bool.and_eq_true, decide_eq_true_eq] at h
    obtain ⟨⟨rfl, same⟩, rest⟩ := h
    rw [typesSame_eq fs same, structsSame_eq rest]

theorem enumsSame_eq : ∀ {as bs : List SrcEnumDecl}, enumsSame as bs = true → as = bs
  | [], [], _ => rfl
  | [], _ :: _, h => nomatch h
  | _ :: _, [], h => nomatch h
  | ⟨i, vs⟩ :: as, ⟨j, ws⟩ :: bs, h => by
    simp only [enumsSame, Bool.and_eq_true, decide_eq_true_eq] at h
    obtain ⟨⟨rfl, same⟩, rest⟩ := h
    rw [variantsSame_eq vs same, enumsSame_eq rest]

theorem declsSame_eq {a b : SrcDecls} (h : declsSame a b = true) : a = b := by
  obtain ⟨as, ae, ac⟩ := a
  obtain ⟨bs, be, bc⟩ := b
  simp only [declsSame, Bool.and_eq_true, decide_eq_true_eq] at h
  rw [structsSame_eq h.1.1, enumsSame_eq h.1.2, h.2]

end Lanius.Faithful
