module

public import Lanius.Mini.Compiler
public import Lanius.Faithful.SelfPre.TS
public import Lanius.Faithful.SelfPre.HB
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
import all Lanius.Mini.Compiler.P.armBodyScope
import all Lanius.Mini.Compiler.P.fieldPayload
import all Lanius.Mini.Compiler.P.unitPayload
import all Lanius.Mini.Compiler.P.armScope
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
import all Lanius.Mini.Compiler.P.matchDst
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
import all Lanius.Mini.Compiler.P.lowerReturnUnit
import all Lanius.Mini.Compiler.P.lowerSetFieldEval
import all Lanius.Mini.Compiler.P.lowerUnreachable
import all Lanius.Mini.Compiler.P.lowerView
import all Lanius.Mini.Compiler.P.setFieldEvalAt
import all Lanius.Mini.Compiler.P.setFieldEvalOf
import all Lanius.Mini.Compiler.P.storeArray
import all Lanius.Mini.Compiler.P.strAscii
import all Lanius.Mini.Compiler.P.strWords
import all Lanius.Mini.Compiler.P.viewStores
import all Lanius.Mini.Compiler.P.blockAt
import all Lanius.Mini.Compiler.P.blockLoad
import all Lanius.Mini.Compiler.P.blockStore
import all Lanius.Mini.Compiler.P.elementLoads
import all Lanius.Mini.Compiler.P.elementStores
import all Lanius.Mini.Compiler.P.idAbsent
import all Lanius.Mini.Compiler.P.lowerAssert
import all Lanius.Mini.Compiler.P.lowerSetIndexAny
import all Lanius.Mini.Compiler.P.lowerSetIndexEval
import all Lanius.Mini.Compiler.P.lowerStr
import all Lanius.Mini.Compiler.P.packedWidth
import all Lanius.Mini.Compiler.P.strStores
import all Lanius.Mini.Unique
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
import all Lanius.Mini.Compiler.P.argBytes
import all Lanius.Mini.Compiler.P.arrayArg
import all Lanius.Mini.Compiler.P.arrayArgBefore
import all Lanius.Mini.Compiler.P.arrayArgChecked
import all Lanius.Mini.Compiler.P.arrayArgLocal
import all Lanius.Mini.Compiler.P.arrayArgPure
import all Lanius.Mini.Compiler.P.arrayArgSlice
import all Lanius.Mini.Compiler.P.arrayArgs
import all Lanius.Mini.Compiler.P.arrayCallCode
import all Lanius.Mini.Compiler.P.bindingBytes
import all Lanius.Mini.Compiler.P.blockLimit

@[expose] public section

/-! # How far the evaluator's slots grow between its checks (F14)

`SrcEff.eval` puts an expression's value in `slot, slot + 1, ...`. An operator's
right operand starts one slot further (`eApply`, `eDivide`); arguments, a
`let`'s body and a `match`'s arms start at slots that `eval_args`,
`eval_let_body` and `eval_arm_in` check against `evalSlotLimit` (`2 ^ 40`).
`SrcEff.slotNest` counts the unchecked steps: the most `+ 1`s on a path from
the expression to a checked start or a leaf. A statement's `slotNest` is the
largest of its expressions'. The compile side's pre lemmas keep
`slot + slotNest e` below a bound (`COMPILE_OVERRIDES`, `tools/pre_certs.py`). -/

namespace Lanius.Faithful.SelfPre

open Lanius.Mini

mutual
def SrcEff.slotNest : SrcEff → Nat
  | .ePure _ => 0
  | .eCall _ args => effsSlotNest args
  | .eApply _ left right => max (SrcEff.slotNest left) (SrcEff.slotNest right + 1)
  | .eNeg operand => SrcEff.slotNest operand
  | .eNot operand => SrcEff.slotNest operand
  | .eCast _ operand => SrcEff.slotNest operand
  | .eIndex _ index => SrcEff.slotNest index
  | .eStruct _ fields => effsSlotNest fields
  | .eVariant _ _ payload => effsSlotNest payload
  | .eMatch scrutinee _ _ _ values => max (SrcEff.slotNest scrutinee) (effsSlotNest values)
  | .eDivide _ left right => max (SrcEff.slotNest left) (SrcEff.slotNest right + 1)
  | .eStride _ => 0
  | .arraySlice _ _ => 0
  | .eIf condition _ thenValue elseValue =>
    max (SrcEff.slotNest condition) (max (SrcEff.slotNest thenValue) (SrcEff.slotNest elseValue))
  | .eLet _ _ value _ body => max (SrcEff.slotNest value) (SrcEff.slotNest body)
  | .eLen _ => 0
  | .eStr _ _ => 0
  | .eBorrow _ _ => 0
  | .eDeref _ _ => 0
  | .eField _ _ => 0
  | .eAt _ _ => 0

def effsSlotNest : List SrcEff → Nat
  | [] => 0
  | e :: rest => max (SrcEff.slotNest e) (effsSlotNest rest)
end

/-- The largest `slotNest` of a statement's expressions. -/
def SrcStmt.slotNest : SrcStmt → Nat
  | .nop => 0
  | .let _ _ _ body => SrcStmt.slotNest body
  | .letStruct _ _ _ body => SrcStmt.slotNest body
  | .letCall _ _ _ _ body => SrcStmt.slotNest body
  | .letEnum _ _ _ _ body => SrcStmt.slotNest body
  | .letMatch _ _ _ _ _ body => SrcStmt.slotNest body
  | .set _ _ => 0
  | .setField _ _ _ => 0
  | .setCall _ _ _ => 0
  | .then first second => max (SrcStmt.slotNest first) (SrcStmt.slotNest second)
  | .if _ thenBranch elseBranch => max (SrcStmt.slotNest thenBranch) (SrcStmt.slotNest elseBranch)
  | .while _ body => SrcStmt.slotNest body
  | .return _ => 0
  | .letAlloc _ _ _ body => SrcStmt.slotNest body
  | .letLoad _ _ _ body => SrcStmt.slotNest body
  | .setByte _ _ _ => 0
  | .free _ _ _ => 0
  | .letSlice _ _ _ _ body => SrcStmt.slotNest body
  | .letIndex _ _ _ _ body => SrcStmt.slotNest body
  | .setIndex _ _ _ => 0
  | .letEval _ _ value body => max (SrcEff.slotNest value) (SrcStmt.slotNest body)
  | .setEval _ value => SrcEff.slotNest value
  | .ifEval condition thenBranch elseBranch =>
    max (SrcEff.slotNest condition) (max (SrcStmt.slotNest thenBranch) (SrcStmt.slotNest elseBranch))
  | .whileEval condition body => max (SrcEff.slotNest condition) (SrcStmt.slotNest body)
  | .returnEval value => SrcEff.slotNest value
  | .discard value => SrcEff.slotNest value
  | .setIndexEval _ index value => max (SrcEff.slotNest index) (SrcEff.slotNest value)
  | .setFieldEval _ _ value => SrcEff.slotNest value
  | .returnUnit => 0
  | .assert condition => SrcEff.slotNest condition
  | .break => 0
  | .continue => 0
  | .matchArm _ _ _ _ _ _ body rest => max (SrcStmt.slotNest body) (SrcStmt.slotNest rest)
  | .unreachable _ _ => 0
  | .letView _ _ _ _ body => SrcStmt.slotNest body
  | .letStr _ _ body => SrcStmt.slotNest body
  | .setPlace _ _ => 0
  | .setPlaceOp _ _ _ => 0

/-- The functions' largest `SrcStmt.depth` (their lets' slots). -/
def depthMax : List SrcFunc → Nat
  | [] => 0
  | f :: fs => max (SrcStmt.depth f.body) (depthMax fs)

/-- The functions' largest `SrcStmt.slotNest`. -/
def nestMax : List SrcFunc → Nat
  | [] => 0
  | f :: fs => max (SrcStmt.slotNest f.body) (nestMax fs)

/-! ## The scope's slots

A binding takes the slots `b.slot .. b.slot + SrcType.size b.ty`. A match arm's
bindings view the scrutinee's payload in place, so they end within its slots;
`scopeTop` (the largest end) stays below the bound however deep the matches. -/

/-- The largest slot past a binding of the scope. -/
def scopeTop : List Binding → Nat
  | [] => 0
  | b :: rest => max (b.slot + SrcType.size b.ty) (scopeTop rest)

def optTop : Option Binding → Nat
  | none => 0
  | some b => b.slot + SrcType.size b.ty

def optScopeTop : Option (List Binding) → Nat
  | none => 0
  | some s => scopeTop s

-- their constructors' values, for `hb_simp` (unfolding the definitions would leave a `match`)
theorem optTop_none : optTop none = 0 := rfl
theorem optTop_some (b : Binding) : optTop (some b) = b.slot + SrcType.size b.ty := rfl
theorem optScopeTop_none : optScopeTop none = 0 := rfl
theorem optScopeTop_some (s : List Binding) : optScopeTop (some s) = scopeTop s := rfl

/-- A lowered body's extent (`Stmt.extent`: past its largest slot), `0` for none. -/
def optExtent : Option Stmt → Nat
  | none => 0
  | some s => Stmt.extent s

theorem optExtent_none : optExtent none = 0 := rfl
theorem optExtent_some (s : Stmt) : optExtent (some s) = Stmt.extent s := rfl

theorem slots_lookup : ∀ (scope : List Binding) (id : Nat), optTop (lookup scope id) ≤ scopeTop scope
  | [], _ => by simp [lookup, optTop, scopeTop]
  | b :: rest, id => by
    have := slots_lookup rest id
    rw [lookup]
    split
    · simp only [optTop, scopeTop]; omega
    · simp only [scopeTop]; omega

theorem slotsSome_lookup (scope : List Binding) (id : Nat) (b : Binding) (h : lookup scope id = some b) :
    b.slot + SrcType.size b.ty ≤ scopeTop scope := by
  have := slots_lookup scope id
  rw [h] at this
  exact this

/-- The block bytes an argument takes: an array local's, within the scope's slots. -/
theorem slots_argBytes (scope : List Binding) (arg : SrcEff) : argBytes scope arg ≤ 8 * scopeTop scope := by
  have := slots_lookup scope
  cases arg <;> simp only [argBytes] <;> try omega
  case arraySlice element id =>
    have h := this id
    cases hl : lookup scope id with
    | none => simp [bindingBytes]
    | some b => rw [hl, optTop_some] at h; simp only [bindingBytes]; omega

/-- An arm's binders start at `slot` and after the types before them. -/
theorem slots_armScope : ∀ (binders : List Nat) (types : List SrcType) (slot : Nat) (scope : List Binding),
    optScopeTop (armScope binders types slot scope) ≤ max (scopeTop scope) (slot + sizes types)
  | [], [], _, _ => by simp only [armScope, optScopeTop]; omega
  | [], _ :: _, _, _ => by simp only [armScope, optScopeTop]; omega
  | _ :: _, [], _, _ => by simp only [armScope, optScopeTop]; omega
  | binder :: rest, ty :: more, slot, scope => by
    have := slots_armScope rest more (slot + SrcType.size ty) ({ id := binder, slot := slot, ty := ty, home := none } :: scope)
    rw [armScope]
    split
    · simp only [scopeTop, sizes] at *; omega
    · simp only [optScopeTop]; omega

theorem slotsSome_armScope (binders : List Nat) (types : List SrcType) (slot : Nat) (scope : List Binding)
    (s : List Binding) (h : armScope binders types slot scope = some s) :
    scopeTop s ≤ max (scopeTop scope) (slot + sizes types) := by
  have := slots_armScope binders types slot scope
  rw [h] at this
  exact this

/-- The parameters start at `slot` and after the ones before them. -/
theorem slots_paramScope : ∀ (params : List SrcParam) (slot : Nat) (scope : List Binding),
    scopeTop (paramScope params slot scope) ≤ max (scopeTop scope) (slot + paramsSize params)
  | [], _, _ => by simp only [paramScope]; omega
  | param :: rest, slot, scope => by
    have := slots_paramScope rest (slot + SrcType.size param.ty) ({ id := param.id, slot := slot, ty := param.ty, home := none } :: scope)
    simp only [paramScope, scopeTop, paramsSize] at *; omega

theorem slots_armBodyScope (binds : Bool) (binder : Nat) (ty : SrcType) (next : Nat) (scope : List Binding) :
    scopeTop (armBodyScope binds binder ty next scope) ≤ max (scopeTop scope) (next + SrcType.size ty) := by
  unfold armBodyScope
  split
  · omega
  · simp only [scopeTop]; omega

/-- A match's variants' payloads are within its type. -/
theorem slots_matchVariants (t : SrcType) : maxSize (matchVariants t) ≤ tySlots t := by
  have := size_le_tySlots t
  cases t <;> simp only [matchVariants, maxSize, SrcType.size] at * <;> omega

/-- A match's arms start past the larger of the scrutinee's and the result's slots. -/
theorem slots_matchDst (slot : Nat) (ety ty : SrcType) :
    matchDst slot ety ty ≤ slot + max (tySlots ety) (tySlots ty) := by
  have := size_le_tySlots ety
  have := size_le_tySlots ty
  simp only [matchDst]; omega

/-- A variant's payload's slots, if there is one. -/
def optSizes : Option (List SrcType) → Nat
  | none => 0
  | some types => sizes types

theorem optSizes_none : optSizes none = 0 := rfl
theorem optSizes_some (types : List SrcType) : optSizes (some types) = sizes types := rfl

/-- A variant's payload is within the largest. -/
theorem slots_getElem_variants : ∀ (variants : List (List SrcType)) (i : Nat),
    optSizes variants[i]? ≤ maxSize variants
  | [], _ => by simp [optSizes]
  | v :: rest, 0 => by simp only [List.getElem?_cons_zero, optSizes, maxSize]; omega
  | v :: rest, i + 1 => by
    have := slots_getElem_variants rest i
    simp only [List.getElem?_cons_succ, maxSize]; omega

/-- A type's slots are within its `tySlots` (`ts` bounds that). -/
theorem slots_size (t : SrcType) : SrcType.size t ≤ tySlots t := size_le_tySlots t

/-! ## Counters -/

theorem slots_slotVars : ∀ (slot count : Nat), (slotVars slot count).length ≤ count
  | _, 0 => by simp [slotVars]
  | slot, c + 1 => by
    have := slots_slotVars (slot + 1) c
    rw [slotVars]; simp only [Nat.add_one_ne_zero, if_false, List.length_cons, Nat.add_sub_cancel]; omega

theorem slots_packedWidth (element : SrcType) : packedWidth element ≤ 4 := by
  unfold packedWidth; split
  · omega
  · split <;> omega

/-- A field's offset is within its struct. -/
theorem slots_fieldOffset : ∀ (types : List SrcType) (index : Nat), fieldOffset types index ≤ sizes types
  | [], _ => by simp [fieldOffset]
  | ty :: rest, index => by
    have := slots_fieldOffset rest (index - 1)
    rw [fieldOffset]; split
    · omega
    · simp only [sizes]; omega

/-- A string's words take four of its characters each, the last one to four. -/
theorem slots_strWords : ∀ (chars : List Nat), 4 * hb (strWords chars) ≤ hb chars + 3
  | [] => by simp [strWords]
  | [_] => by simp [strWords]
  | [_, _] => by simp [strWords]
  | [_, _, _] => by simp [strWords]
  | _ :: _ :: _ :: _ :: r4 => by
    have := slots_strWords r4
    simp only [strWords, hb_cons, hb_bitvec, hb_nat, Nat.zero_max] at *; omega


/-- The slots of the types a literal of type `t` is lowered at (`lower_literal`): a struct's
fields', an array's element's (not the array's own size, which only its length gives). -/
def litTs : SrcType → Nat
  | .i32 => 0
  | .bool => 0
  | .uint _ => 0
  | .struct _ fields => tySlotsList fields
  | .enum _ _ => 0
  | .ptr => 0
  | .slice _ => 0
  | .array element _ => tySlots element
  | .unit => 0
  | .isize => 0
  | .char => 0
  | .float _ => 0
  | .sint _ => 0
  | .view _ => 0
  | .str => 0
  | .ref _ => 0

theorem litTs_struct (id : Nat) (fields : List SrcType) : litTs (.struct id fields) = tySlotsList fields := rfl
theorem litTs_array (element : SrcType) (length : Nat) : litTs (.array element length) = tySlots element := rfl

theorem slots_litTs (t : SrcType) : litTs t ≤ tySlots t := by
  cases t <;> simp only [litTs, tySlots] <;> omega

end Lanius.Faithful.SelfPre
