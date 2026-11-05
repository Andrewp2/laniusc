module

public import Lanius.Mini.Reading.Method
import all Lanius.Mini.Frontend.P.callParts
import all Lanius.Mini.Frontend.P.effLocal
import all Lanius.Mini.Frontend.P.pureLocal
import all Lanius.Mini.Frontend.P.viewArray
import all Lanius.Mini.Frontend.P.viewLocal
import all Lanius.Mini.Frontend.P.wantElem
import all Lanius.Mini.Frontend.P.argsOf
import all Lanius.Mini.Frontend.P.armBinders
import all Lanius.Mini.Frontend.P.armValues
import all Lanius.Mini.Frontend.P.bareEff
import all Lanius.Mini.Frontend.P.consEffArm
import all Lanius.Mini.Frontend.P.consExpr
import all Lanius.Mini.Frontend.P.consExprTail
import all Lanius.Mini.Frontend.P.effTy
import all Lanius.Mini.Frontend.P.effsTys
import all Lanius.Mini.Frontend.P.elemTyOf
import all Lanius.Mini.Frontend.P.exprsOf
import all Lanius.Mini.Frontend.P.fieldTyAt
import all Lanius.Mini.Frontend.P.fieldTyOf
import all Lanius.Mini.Frontend.P.fnInstRet
import all Lanius.Mini.Frontend.P.headTy
import all Lanius.Mini.Frontend.P.indexTy
import all Lanius.Mini.Frontend.P.instRet
import all Lanius.Mini.Frontend.P.isOwnerAt
import all Lanius.Mini.Frontend.P.isScalarOwner
import all Lanius.Mini.Frontend.P.isSomeIndex
import all Lanius.Mini.Frontend.P.isTypeOwner
import all Lanius.Mini.Frontend.P.resultTy
import all Lanius.Mini.Frontend.P.tailTys
import all Lanius.Mini.Frontend.P.xMatchOf
import all Lanius.Mini.Frontend.P.effPlace
import all Lanius.Mini.Frontend.P.hasAt
import all Lanius.Mini.Frontend.P.isRefTy
import all Lanius.Mini.Frontend.P.projection
import all Lanius.Mini.Frontend.P.referent
import all Lanius.Mini.Frontend.P.referentOr
import all Lanius.Mini.Frontend.P.xAtOf
import all Lanius.Mini.Frontend.P.aliasNamesIn
import all Lanius.Mini.Frontend.P.collect
import all Lanius.Mini.Frontend.P.collectFiles
import all Lanius.Mini.Frontend.P.collectedWith
import all Lanius.Mini.Frontend.P.constNamesIn
import all Lanius.Mini.Frontend.P.enumNamedOk
import all Lanius.Mini.Frontend.P.enumsNamedOk
import all Lanius.Mini.Frontend.P.fileCollected
import all Lanius.Mini.Frontend.P.fileDecls
import all Lanius.Mini.Frontend.P.fileItems
import all Lanius.Mini.Frontend.P.fnNamesIn
import all Lanius.Mini.Frontend.P.isNoneType
import all Lanius.Mini.Frontend.P.moduleGlobals
import all Lanius.Mini.Frontend.P.moduleNamesOk
import all Lanius.Mini.Frontend.P.modulesDistinctNames
import all Lanius.Mini.Frontend.P.noNames
import all Lanius.Mini.Frontend.P.noPrimitive
import all Lanius.Mini.Frontend.P.noPrimitiveAlias
import all Lanius.Mini.Frontend.P.noneMember
import all Lanius.Mini.Frontend.P.typeNamesIn
import all Lanius.Mini.Frontend.P.typeOnlyNamesIn
import all Lanius.Mini.Frontend.P.wellNamed
import all Lanius.Mini.Frontend.P.argsOfItems
import all Lanius.Mini.Frontend.P.boundGoals
import all Lanius.Mini.Frontend.P.boundOrNone
import all Lanius.Mini.Frontend.P.boundPathSpellings
import all Lanius.Mini.Frontend.P.calleeEnv
import all Lanius.Mini.Frontend.P.consGoal
import all Lanius.Mini.Frontend.P.consGoalTail
import all Lanius.Mini.Frontend.P.consTree
import all Lanius.Mini.Frontend.P.consTreeTail
import all Lanius.Mini.Frontend.P.goalAt
import all Lanius.Mini.Frontend.P.goalsOf
import all Lanius.Mini.Frontend.P.instFrom
import all Lanius.Mini.Frontend.P.joinGoals
import all Lanius.Mini.Frontend.P.joinGoalsTail
import all Lanius.Mini.Frontend.P.paramPatterns
import all Lanius.Mini.Frontend.P.patternOf
import all Lanius.Mini.Frontend.P.patternsOf
import all Lanius.Mini.Frontend.P.retPattern
import all Lanius.Mini.Frontend.P.traitAt
import all Lanius.Mini.Frontend.P.traitOfBound
import all Lanius.Mini.Frontend.P.traitOfTy
import all Lanius.Mini.Frontend.P.traitSplit
import all Lanius.Mini.Frontend.P.consName
import all Lanius.Mini.Frontend.P.consNameTail
import all Lanius.Mini.Frontend.P.distinct
import all Lanius.Mini.Frontend.P.distinctModules
import all Lanius.Mini.Frontend.P.moduleMember
import all Lanius.Mini.Frontend.P.position
import all Lanius.Mini.Frontend.P.sameSpellings
import all Lanius.Mini.Frontend.P.singleName
import all Lanius.Mini.Frontend.P.addInst
import all Lanius.Mini.Frontend.P.addInsts
import all Lanius.Mini.Frontend.P.declEnv
import all Lanius.Mini.Frontend.P.findAlias
import all Lanius.Mini.Frontend.P.findConst
import all Lanius.Mini.Frontend.P.findVariant
import all Lanius.Mini.Frontend.P.floatCode
import all Lanius.Mini.Frontend.P.ifItem
import all Lanius.Mini.Frontend.P.instIndex
import all Lanius.Mini.Frontend.P.instMember
import all Lanius.Mini.Frontend.P.isModule
import all Lanius.Mini.Frontend.P.sameFloat
import all Lanius.Mini.Frontend.P.sameInst
import all Lanius.Mini.Frontend.P.sameTy
import all Lanius.Mini.Frontend.P.uintCode
import all Lanius.Mini.Frontend.P.variantsNamed
import all Lanius.Mini.Frontend.P.findLocal
import all Lanius.Mini.Frontend.P.findLocalId
import all Lanius.Mini.Frontend.P.floatTyped
import all Lanius.Mini.Frontend.P.localOf
import all Lanius.Mini.Frontend.P.negateSome
import all Lanius.Mini.Frontend.P.negatedFloat
import all Lanius.Mini.Frontend.P.hasKids
import all Lanius.Mini.Frontend.P.isLink
import all Lanius.Mini.Frontend.P.joinItems
import all Lanius.Mini.Frontend.P.joinSecond
import all Lanius.Mini.Frontend.P.kidToken
import all Lanius.Mini.Frontend.P.leafToken
import all Lanius.Mini.Frontend.P.listItems
import all Lanius.Mini.Frontend.P.sameText
import all Lanius.Mini.Frontend.P.spelled
import all Lanius.Mini.Frontend.P.isEmptyUsize
import all Lanius.Mini.Frontend.P.noTokens
import all Lanius.Mini.Frontend.P.nodeProd
import all Lanius.Mini.Frontend.P.usedUp
import all Lanius.Mini.Frontend.P.validateTree
import all Lanius.Mini.Frontend.P.whole
import all Lanius.Mini.Frontend.P.genericTail
import all Lanius.Mini.Frontend.P.kid
import all Lanius.Mini.Frontend.P.kidsOf
import all Lanius.Mini.Frontend.P.noToken
import all Lanius.Mini.Frontend.P.startsWithKind
import all Lanius.Mini.Frontend.P.withKid
import all Lanius.Mini.Frontend.P.argsSegment
import all Lanius.Mini.Frontend.P.consSegment
import all Lanius.Mini.Frontend.P.noTrees
import all Lanius.Mini.Frontend.P.pathName
import all Lanius.Mini.Frontend.P.pathSpellings
import all Lanius.Mini.Frontend.P.pathRef
import all Lanius.Mini.Frontend.P.arrayParts
import all Lanius.Mini.Frontend.P.barePrim
import all Lanius.Mini.Frontend.P.bindTy
import all Lanius.Mini.Frontend.P.expectedArray
import all Lanius.Mini.Frontend.P.exprTy
import all Lanius.Mini.Frontend.P.exprsTys
import all Lanius.Mini.Frontend.P.findBind
import all Lanius.Mini.Frontend.P.indexElem
import all Lanius.Mini.Frontend.P.paramNamed
import all Lanius.Mini.Frontend.P.paramSpelling
import all Lanius.Mini.Frontend.P.pickTy
import all Lanius.Mini.Frontend.P.primIf
import all Lanius.Mini.Frontend.P.repeatTy
import all Lanius.Mini.Frontend.P.sameOrNone
import all Lanius.Mini.Frontend.P.sliceElem
import all Lanius.Mini.Frontend.P.diverges
import all Lanius.Mini.Frontend.P.initTys
import all Lanius.Mini.Frontend.P.lastTy
import all Lanius.Mini.Frontend.P.neverRet
import all Lanius.Mini.Frontend.P.projectionRet
import all Lanius.Mini.Frontend.P.attach
import all Lanius.Mini.Frontend.P.only
import all Lanius.Mini.Frontend.P.shrFirst
import all Lanius.Mini.Frontend.P.shrSecond
import all Lanius.Mini.Frontend.P.member
import all Lanius.Mini.Frontend.P.primitive
import all Lanius.Mini.Frontend.P.spelled0
import all Lanius.Mini.Frontend.P.spelled1
import all Lanius.Mini.Frontend.P.spelled2
import all Lanius.Mini.Frontend.P.spelled3
import all Lanius.Mini.Frontend.P.spelled4
import all Lanius.Mini.Frontend.P.spelled5
import all Lanius.Mini.Frontend.P.textAlloc
import all Lanius.Mini.Frontend.P.textAllocator
import all Lanius.Mini.Frontend.P.textAssert
import all Lanius.Mini.Frontend.P.textDealloc
import all Lanius.Mini.Frontend.P.textSelf
import all Lanius.Mini.Frontend.P.textSliceFromRawParts
import all Lanius.Mini.Frontend.P.textSliceStride
import all Lanius.Mini.Frontend.P.textStr
import all Lanius.Mini.Frontend.P.textStringDataPtr
import all Lanius.Mini.Frontend.P.textTypedSliceFromRawParts
import all Lanius.Mini.Frontend.P.inferred
import all Lanius.Mini.Frontend.P.isPtrTy
import all Lanius.Mini.Frontend.P.letHeadOrEval
import all Lanius.Mini.Frontend.P.literalHead
import all Lanius.Mini.Frontend.P.pureInferred
import all Lanius.Mini.Frontend.P.thenOf
import all Lanius.Mini.Frontend.P.thenRest
import all Lanius.Mini.Frontend.P.tryLet
import all Lanius.Mini.Frontend.P.tryStmt
import all Lanius.Mini.Frontend.P.untypedEval
import all Lanius.Mini.Frontend.P.untypedHead
import all Lanius.Mini.Frontend.P.untypedIf
import all Lanius.Mini.Frontend.P.untypedTry
import all Lanius.Mini.Frontend.P.arityOk
import all Lanius.Mini.Frontend.P.arrayLen
import all Lanius.Mini.Frontend.P.arrayTy
import all Lanius.Mini.Frontend.P.bareOf
import all Lanius.Mini.Frontend.P.bareTy
import all Lanius.Mini.Frontend.P.consTy
import all Lanius.Mini.Frontend.P.consTyTail
import all Lanius.Mini.Frontend.P.consTysTail
import all Lanius.Mini.Frontend.P.decimal
import all Lanius.Mini.Frontend.P.namedArgs
import all Lanius.Mini.Frontend.P.namedChecked
import all Lanius.Mini.Frontend.P.namedOf
import all Lanius.Mini.Frontend.P.primOrNamed
import all Lanius.Mini.Frontend.P.sliceTy
import all Lanius.Mini.Frontend.P.tyOf
import all Lanius.Mini.Frontend.P.typeDeclAt
import all Lanius.Mini.Frontend.P.applyTy
import all Lanius.Mini.Frontend.P.bareInt
import all Lanius.Mini.Frontend.P.dashText
import all Lanius.Mini.Frontend.P.exprOf
import all Lanius.Mini.Frontend.P.fieldTy
import all Lanius.Mini.Frontend.P.givesBool
import all Lanius.Mini.Frontend.P.localTy
import all Lanius.Mini.Frontend.P.peel
import all Lanius.Mini.Frontend.P.shiftOp
import all Lanius.Mini.Frontend.P.structFieldTys
import all Lanius.Mini.Frontend.P.wideConst
import all Lanius.Mini.Frontend.P.wideDigits
import all Lanius.Mini.Frontend.P.wideOf
import all Lanius.Mini.Frontend.P.wideSigned
import all Lanius.Mini.Frontend.P.assertArg
import all Lanius.Mini.Frontend.P.assertOf
import all Lanius.Mini.Frontend.P.assignOpOf
import all Lanius.Mini.Frontend.P.assignTarget
import all Lanius.Mini.Frontend.P.callStmt
import all Lanius.Mini.Frontend.P.compoundEff
import all Lanius.Mini.Frontend.P.compoundFieldEval
import all Lanius.Mini.Frontend.P.compoundOp
import all Lanius.Mini.Frontend.P.discardOf
import all Lanius.Mini.Frontend.P.freeOf
import all Lanius.Mini.Frontend.P.freeShifted
import all Lanius.Mini.Frontend.P.setPlaceOf
import all Lanius.Mini.Frontend.P.setPlaceOpOf
import all Lanius.Mini.Frontend.P.setPlaceOpValue
import all Lanius.Mini.Frontend.P.refRooted
import all Lanius.Mini.Frontend.P.refTarget
import all Lanius.Mini.Frontend.P.setFieldOrEval
import all Lanius.Mini.Frontend.P.setPlaceValue
import all Lanius.Mini.Frontend.P.divergeFunc
import all Lanius.Mini.Frontend.P.namesFieldBase
import all Lanius.Mini.Frontend.P.paramEffs
import all Lanius.Mini.Frontend.P.projectionFunc
import all Lanius.Mini.Frontend.P.readFn
import all Lanius.Mini.Frontend.P.refKids
import all Lanius.Mini.Frontend.P.refUsesOk
import all Lanius.Mini.Frontend.P.refsChecked
import all Lanius.Mini.Frontend.P.refsUsedOk
import all Lanius.Mini.Frontend.P.isFnPath
import all Lanius.Mini.Frontend.P.isMethodForm
import all Lanius.Mini.Frontend.P.memberArgs
import all Lanius.Mini.Frontend.P.effSliceLocal
import all Lanius.Mini.Frontend.P.fieldOfTy
import all Lanius.Mini.Frontend.P.fieldValue
import all Lanius.Mini.Frontend.P.methodOfTy
import all Lanius.Mini.Frontend.P.stepExpected
import all Lanius.Mini.Frontend.P.eArraySliceClosed
import all Lanius.Mini.Frontend.P.eDerefClosed
import all Lanius.Mini.Frontend.P.eIndexClosed
import all Lanius.Mini.Frontend.P.ePlaceAtClosed
import all Lanius.Mini.Frontend.P.ePlaceFieldClosed
import all Lanius.Mini.Frontend.P.setPlaceClosed
import all Lanius.Mini.Frontend.P.setPlaceOpClosed
import all Lanius.Mini.Frontend.P.checkedFunc

@[expose] public section
/-! # The reading, V8d: effectful expression types, arguments and paths

`EffTy decls scope x t`: the type of an effectful expression, as type
arguments are inferred from it (a call's is its instance's result type,
`InstRet`). A path's prefix names a type (`TypeOwner`) when it is a type
parameter or a primitive type, or names a struct, or an enum without a
variant of the called name, as a type path; the calls themselves are read
in `Reading/Effs`. -/

namespace Lanius.Mini.Reading

open Lanius.Mini Lanius.Mini.Prod

/-! ## Result types and effectful expression types -/

/-- The result type of a function instance: the last type argument of a
diverging one, its declared result type at its type arguments, or a
projection's field type. -/
inductive InstRet (decls : Decls) (inst : Inst) : Ty → Prop
  | diverge {fd : FnDecl} {t : Ty} : decls.fns[inst.decl]? = some fd → diverges fd inst = true →
      lastTy inst.args = some t → InstRet decls inst t
  | ret {fd : FnDecl} {r : CTree} {t : Ty} : decls.fns[inst.decl]? = some fd → diverges fd inst = false →
      RetPattern fd r → TyR (declScope decls fd.home (fd.implParams ++ fd.params) inst.args) r t → InstRet decls inst t
  | projection {a : Ty} {rest : List Ty} {d : Nat} {args ts : List Ty} {t : Ty} : decls.fns[inst.decl]? = none →
      inst.args = a :: rest → a = .tyNamed d args → FieldTys decls d args ts → ts[inst.decl - decls.fns.length]? = some t →
      InstRet decls inst t

/-- Field `j`'s type in the struct type `t`. -/
def FieldTyAt (decls : Decls) (t : Ty) (j : Nat) (ty : Ty) : Prop :=
  ∃ d args ts, t = .tyNamed d args ∧ FieldTys decls d args ts ∧ ts[j]? = some ty

inductive EffTy (decls : Decls) (scope : List Local) : MEff → Ty → Prop
  | pure {e : SrcExpr} {t : Ty} : ExprTy decls scope e t → EffTy decls scope (.xPure e) t
  | call {inst : Inst} {args : List MEff} {t : Ty} : InstRet decls inst t → EffTy decls scope (.xCall inst args) t
  | compare {op : SrcOp} {l r : MEff} : givesBool op = true → EffTy decls scope (.xApply op l r) .tyBool
  | left {op : SrcOp} {l r : MEff} {t : Ty} : givesBool op = false → (bareEff l && !shiftOp op) = false →
      EffTy decls scope l t → EffTy decls scope (.xApply op l r) t
  | right {op : SrcOp} {l r : MEff} {t : Ty} : givesBool op = false → (bareEff l && !shiftOp op) = true →
      EffTy decls scope r t → EffTy decls scope (.xApply op l r) t
  | neg {a : MEff} {t : Ty} : EffTy decls scope a t → EffTy decls scope (.xNeg a) t
  | not {a : MEff} : EffTy decls scope (.xNot a) .tyBool
  | cast {s : SrcType} {a : MEff} {t : Ty} : ScalarTy t s → EffTy decls scope (.xCast s a) t
  | index {s : Nat} {i : MEff} {l : Local} {t : Ty} : LocalWithId scope s l → l.ty = .tySlice t →
      EffTy decls scope (.xIndex s i) t
  | indexArray {s : Nat} {i : MEff} {l : Local} {t : Ty} {n : Nat} : LocalWithId scope s l → l.ty = .tyArray t n →
      EffTy decls scope (.xIndex s i) t
  | struct {t : Ty} {fs : List MEff} : EffTy decls scope (.xStruct t fs) t
  | variant {t : Ty} {k : Nat} {ps : List MEff} : EffTy decls scope (.xVariant t k ps) t
  | «match» {s : MEff} {ety t : Ty} {bs : List (List Nat)} {vs : List MEff} : EffTy decls scope (.xMatch s ety t bs vs) t
  | divideLeft {op : SrcDivOp} {l r : MEff} {t : Ty} : bareEff l = false → EffTy decls scope l t →
      EffTy decls scope (.xDivide op l r) t
  | divideRight {op : SrcDivOp} {l r : MEff} {t : Ty} : bareEff l = true → EffTy decls scope r t →
      EffTy decls scope (.xDivide op l r) t
  | stride {sl : Nat} : EffTy decls scope (.xStride sl) .tyIsize
  | host {id : Nat} {args : List MEff} : EffTy decls scope (.xHost id args) .tyI32
  | arraySlice {e : Ty} {a : Nat} : EffTy decls scope (.xArraySlice e a) (.tySlice e)
  | «if» {c a b : MEff} {t : Ty} : EffTy decls scope (.xIf c t a b) t
  | «let» {id : Nat} {t rt : Ty} {v b : MEff} : EffTy decls scope (.xLet id t v rt b) rt
  | len {sl : Nat} : EffTy decls scope (.xLen sl) (.tyUint .usize)
  | str {cs : List Nat} : EffTy decls scope (.xStr cs) .tyStr
  /-- (F5, S5) a referent has its type, a field of a place the field's type, an element of a place its
  element type -/
  | deref {ty : Ty} {a : MEff} : EffTy decls scope (.xDeref ty a) ty
  | placeField {b : MEff} {j : Nat} {t u : Ty} : EffTy decls scope b t → FieldTyAt decls t j u →
      EffTy decls scope (.xPlaceField b j) u
  | placeAt {b i : MEff} {t : Ty} : EffTy decls scope b (.tySlice t) → EffTy decls scope (.xPlaceAt b i) t
  | placeAtArray {b i : MEff} {t : Ty} {n : Nat} : EffTy decls scope b (.tyArray t n) →
      EffTy decls scope (.xPlaceAt b i) t

theorem instRet_sound {fuel : Nat} {decls : Decls} {inst : Inst} {t : Ty} (h : instRet fuel decls inst = some t) :
    InstRet decls inst t := by
  unfold instRet at h
  cases hf : decls.fns[inst.decl]? with
  | some fd =>
    rw [hf] at h
    simp only [fnInstRet] at h
    by_cases dv : diverges fd inst = true
    · rw [if_pos dv] at h
      exact .diverge hf dv h
    · rw [if_neg dv] at h
      cases hr : retPattern fd with
      | none => rw [hr] at h; cases h
      | some r =>
        rw [hr] at h
        exact .ret hf (by simpa using dv) (retPattern_sound hr) (tyOf_sound h)
  | none =>
    rw [hf] at h
    simp only [projectionRet] at h
    cases ha : inst.args with
    | nil => rw [ha] at h; cases h
    | cons a rest =>
      rw [ha] at h
      simp only at h
      cases hs : structFieldTys fuel decls a with
      | none => rw [hs] at h; cases h
      | some ts =>
        rw [hs] at h
        simp only at h
        unfold structFieldTys at hs
        cases a with
        | tyNamed d args => exact .projection hf ha rfl (fieldTys_sound hs) h
        | tyI32 => cases hs
        | tyBool => cases hs
        | tyUint _ => cases hs
        | tyPtr => cases hs
        | tyIsize => cases hs
        | tyChar => cases hs
        | tyStr => cases hs
        | tyFloat ft => cases hs
        | tySint _ => cases hs
        | tyArray _ _ => cases hs
        | tySlice _ => cases hs
        | tyRef _ => cases hs

theorem fieldTyAt_sound {fuel : Nat} {decls : Decls} {t : Ty} {j : Nat} :
    ∀ ty, fieldTyAt fuel decls t j = some ty → FieldTyAt decls t j ty := by
  intro ty h
  unfold fieldTyAt at h
  cases t with
  | tyNamed d args =>
    simp only [structFieldTys] at h
    cases hf : fieldTys fuel decls d args with
    | none => rw [hf] at h; cases h
    | some ts =>
      rw [hf] at h
      exact ⟨d, args, ts, rfl, fieldTys_sound hf, h⟩
  | tyI32 => cases h
  | tyBool => cases h
  | tyUint _ => cases h
  | tyPtr => cases h
  | tyIsize => cases h
  | tyChar => cases h
  | tyStr => cases h
  | tyFloat ft => cases h
  | tySint _ => cases h
  | tyArray _ _ => cases h
  | tySlice _ => cases h
  | tyRef _ => cases h

theorem effTy_sound : ∀ {fuel : Nat} {env : FrontEnv} {scope : List Local} {x : MEff} {t : Ty},
    effTy fuel env scope x = some t → EffTy env.decls scope x t
  | 0, _, _, _, _, h => by rw [effTy.eq_def] at h; simp at h
  | f + 1, env, scope, x, t, h => by
    rw [effTy.eq_def] at h
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
    cases x with
    | xPure e => exact .pure (exprTy_sound h)
    | xCall inst args => exact .call (instRet_sound h)
    | xApply op l r =>
      simp only [applyTy] at h
      by_cases g : givesBool op = true
      · rw [if_pos g, Option.some.injEq] at h
        subst h
        exact .compare g
      · rw [if_neg g] at h
        have g' : givesBool op = false := by simpa using g
        simp only [pickTy] at h
        by_cases bl : (bareEff l && !shiftOp op) = true
        · rw [if_pos bl] at h
          exact .right g' bl (effTy_sound h)
        · rw [if_neg bl] at h
          exact .left g' (by simpa using bl) (effTy_sound h)
    | xNeg a => exact .neg (effTy_sound h)
    | xNot a => cases h; exact .not
    | xCast s a => exact .cast (srcTy_sound h)
    | xIndex s i =>
      simp only [indexTy] at h
      cases hl : findLocalId scope s with
      | none => rw [hl] at h; cases h
      | some l =>
        rw [hl] at h
        simp only at h
        unfold indexElem at h
        cases hty : l.ty with
        | tySlice e => rw [hty] at h; cases h; exact .index (findLocalId_sound hl) hty
        | tyI32 => rw [hty] at h; cases h
        | tyBool => rw [hty] at h; cases h
        | tyUint _ => rw [hty] at h; cases h
        | tyPtr => rw [hty] at h; cases h
        | tyIsize => rw [hty] at h; cases h
        | tyChar => rw [hty] at h; cases h
        | tyStr => rw [hty] at h; cases h
        | tyFloat ft => rw [hty] at h; cases h
        | tySint _ => rw [hty] at h; cases h
        | tyArray e n => rw [hty] at h; cases h; exact .indexArray (findLocalId_sound hl) hty
        | tyNamed _ _ => rw [hty] at h; cases h
        | tyRef _ => rw [hty] at h; cases h
    | xStruct t' fs => cases h; exact .struct
    | xVariant t' k ps => cases h; exact .variant
    | xMatch s ety t' bs vs => cases h; exact .match
    | xDivide op l r =>
      simp only [pickTy] at h
      by_cases bl : bareEff l = true
      · rw [if_pos bl] at h
        exact .divideRight bl (effTy_sound h)
      · rw [if_neg bl] at h
        exact .divideLeft (by simpa using bl) (effTy_sound h)
    | xStride sl => cases h; exact .stride
    | xHost id args => cases h; exact .host
    | xArraySlice e a => cases h; exact .arraySlice
    | xIf c t' a b => cases h; exact .if
    | xLet id t' v rt b => cases h; exact .let
    | xLen sl => cases h; exact .len
    | xStr cs => cases h; exact .str
    | xDeref ty a => cases h; exact .deref
    | xPlaceField b j =>
      simp only [fieldTyOf] at h
      cases hb : effTy f env scope b with
      | none => rw [hb] at h; cases h
      | some tb => rw [hb] at h; exact .placeField (effTy_sound hb) (fieldTyAt_sound _ h)
    | xPlaceAt b i =>
      simp only [elemTyOf] at h
      cases hb : effTy f env scope b with
      | none => rw [hb] at h; cases h
      | some tb =>
        rw [hb] at h
        simp only at h
        unfold indexElem at h
        cases tb with
        | tySlice e => cases h; exact .placeAt (effTy_sound hb)
        | tyArray e n => cases h; exact .placeAtArray (effTy_sound hb)
        | tyI32 => cases h
        | tyBool => cases h
        | tyUint _ => cases h
        | tyPtr => cases h
        | tyIsize => cases h
        | tyChar => cases h
        | tyStr => cases h
        | tyFloat ft => cases h
        | tySint _ => cases h
        | tyNamed _ _ => cases h
        | tyRef _ => cases h

theorem effsTys_sound {fuel : Nat} {env : FrontEnv} {scope : List Local} :
    ∀ {xs : List MEff} {ts : List Ty}, effsTys fuel env scope xs = some ts → ListRel (EffTy env.decls scope) xs ts
  | [], ts, h => by
    simp only [effsTys, Option.some.injEq] at h
    subst h
    exact .nil
  | x :: rest, ts, h => by
    simp only [effsTys, consTy] at h
    cases hx : effTy fuel env scope x with
    | none => rw [hx] at h; cases h
    | some t =>
      rw [hx] at h
      simp only [consTyTail] at h
      cases hr : effsTys fuel env scope rest with
      | none => rw [hr] at h; cases h
      | some tr =>
        rw [hr, Option.some.injEq] at h
        subst h
        exact .cons (effTy_sound hx) (effsTys_sound hr)

/-! ## Arguments -/

/-- Expressions read in order. -/
def ExprsR (env : FrontEnv) (scope : List Local) (items : List CTree) (es : List SrcExpr) : Prop :=
  ListRel (ExprR env scope) items es

/-- A call's argument list. -/
def ArgsOfR (env : FrontEnv) (scope : List Local) (args : CTree) (es : List SrcExpr) : Prop :=
  ∃ items, Items args items ∧ ExprsR env scope items es

theorem exprsOf_sound {fuel : Nat} {env : FrontEnv} {scope : List Local} :
    ∀ {items : List CTree} {es : List SrcExpr}, exprsOf fuel env scope items = some es → ExprsR env scope items es
  | [], es, h => by
    simp only [exprsOf, Option.some.injEq] at h
    subst h
    exact .nil
  | e :: rest, es, h => by
    simp only [exprsOf, consExpr] at h
    cases he : exprOf fuel env scope e with
    | none => rw [he] at h; cases h
    | some x =>
      rw [he] at h
      simp only [consExprTail] at h
      cases hr : exprsOf fuel env scope rest with
      | none => rw [hr] at h; cases h
      | some xs =>
        rw [hr, Option.some.injEq] at h
        subst h
        exact .cons (exprOf_sound he) (exprsOf_sound hr)

theorem argsOf_sound {fuel : Nat} {env : FrontEnv} {scope : List Local} {args : CTree} {es : List SrcExpr}
    (h : argsOf fuel env scope args = some es) : ArgsOfR env scope args es := by
  unfold argsOf at h
  cases hi : listItems fuel args with
  | none => rw [hi] at h; cases h
  | some items => rw [hi] at h; exact ⟨items, listItems_sound hi, exprsOf_sound h⟩

/-- A path's segments and its last segment's type arguments
(`a::b::f::<T>`). -/
inductive PathRefR : CTree → CTree → PathRef → Prop
  | last {segment tail : CTree} : nodeProd segment = pPathIdent → nodeProd tail = pPathEnd →
      PathRefR segment tail ⟨[(kidToken segment 0).text], []⟩
  | args {segment tail : CTree} {gs : List CTree} : nodeProd segment = pPathIdentArgs → nodeProd tail = pPathEnd →
      Items segment gs → PathRefR segment tail ⟨[(kidToken segment 0).text], gs⟩
  | more {segment tail : CTree} {r : PathRef} : nodeProd segment = pPathIdent → nodeProd tail = pPathMore →
      PathRefR (kid tail 2) (kid tail 3) r → PathRefR segment tail ⟨(kidToken segment 0).text :: r.segments, r.targs⟩

theorem pathRef_sound : ∀ {fuel : Nat} {segment tail : CTree} {pr : PathRef},
    pathRef fuel segment tail = some pr → PathRefR segment tail pr
  | 0, _, _, _, h => by rw [pathRef.eq_def] at h; simp at h
  | f + 1, segment, tail, pr, h => by
    rw [pathRef.eq_def] at h
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
    by_cases one : nodeProd segment = pPathIdent ∧ nodeProd tail = pPathEnd
    · rw [if_pos (by simpa using one), Option.some.injEq] at h
      subst h
      exact .last one.1 one.2
    rw [if_neg (by simpa using one)] at h
    by_cases ar : nodeProd segment = pPathIdentArgs ∧ nodeProd tail = pPathEnd
    · rw [if_pos (by simpa using ar)] at h
      simp only [argsSegment] at h
      cases hi : listItems (f + 1) segment with
      | none => rw [hi] at h; cases h
      | some gs =>
        rw [hi, Option.some.injEq] at h
        subst h
        exact .args ar.1 ar.2 (listItems_sound hi)
    rw [if_neg (by simpa using ar)] at h
    by_cases mo : nodeProd segment = pPathIdent ∧ nodeProd tail = pPathMore
    · rw [if_pos (by simpa using mo)] at h
      simp only [consSegment] at h
      cases hr : pathRef f (kid tail 2) (kid tail 3) with
      | none => rw [hr] at h; cases h
      | some r =>
        rw [hr, Option.some.injEq] at h
        subst h
        exact .more mo.1 mo.2 (pathRef_sound hr)
    rw [if_neg (by simpa using mo)] at h
    cases h

/-! ## Type owners -/

/-- A path's prefix that names a type, for the function spelled `name`: a
type parameter or a primitive type (one segment), or a struct, or an enum
with no variant spelled `name` (`E::V(..)` names the variant), that the
prefix names as a type path (`DeclAt`: the current module's, an imported
item, or a qualified path's). The type is the prefix read as a type without
arguments (`BareTy`). -/
def TypeOwner (env : FrontEnv) (front : ModPath) (name : Name) : Prop :=
  (∃ n, front = [n] ∧ (n ∈ env.names ∨ primName n ≠ none)) ∨
    ∃ d t, DeclAt env front d ∧ env.decls.types[d]? = some t ∧ (t.isEnum = false ∨ name ∉ t.variants)

theorem isOwnerAt_typeDeclAt (env : FrontEnv) (ss : List Name) (name : Name) :
    isOwnerAt env (typeDeclAt env ss) name = true ↔
      ∃ d t, DeclAt env ss d ∧ env.decls.types[d]? = some t ∧ (t.isEnum = false ∨ name ∉ t.variants) := by
  cases h : typeDeclAt env ss with
  | some d =>
    have a := typeDeclAt_sound h
    unfold isOwnerAt
    cases ht : env.decls.types[d]? with
    | none =>
      simp only [ht]
      refine ⟨fun e => absurd e (by decide), ?_⟩
      rintro ⟨d', t, a', ht', -⟩
      rw [declAt_unique a a', ht'] at ht
      cases ht
    | some t =>
      simp only [ht, Bool.or_eq_true, Bool.not_eq_true']
      have e : (member t.variants name = false) ↔ name ∉ t.variants := by
        rw [← member_iff]; simp
      refine ⟨fun c => ⟨d, t, a, ht, by rcases c with c | c; exact .inl c; exact .inr (e.1 c)⟩, ?_⟩
      rintro ⟨d', t', a', ht', c⟩
      rw [declAt_unique a a', ht'] at ht
      cases ht
      rcases c with c | c
      · exact .inl c
      · exact .inr (e.2 c)
  | none =>
    refine ⟨fun e => (by simp [isOwnerAt] at e), ?_⟩
    rintro ⟨d, -, a, -⟩
    exact absurd a (noDeclAt_not (typeDeclAt_none h))

theorem isScalarOwner_iff (env : FrontEnv) (front : ModPath) :
    isScalarOwner env (singleName front) = true ↔ ∃ n, front = [n] ∧ (n ∈ env.names ∨ primName n ≠ none) := by
  rw [singleName_eq]
  match front with
  | [n] =>
    simp only [isScalarOwner, Bool.or_eq_true, member_iff, Bool.not_eq_true', primitive_eq]
    constructor
    · intro h
      refine ⟨n, rfl, ?_⟩
      rcases h with h | h
      · exact .inl h
      · right
        cases hp : primName n <;> simp_all [isNoneType]
    · rintro ⟨m, e, h⟩
      cases e
      rcases h with h | h
      · exact .inl h
      · right
        cases hp : primName n <;> simp_all [isNoneType]
  | [] => simp [isScalarOwner]
  | _ :: _ :: _ => simp [isScalarOwner]

theorem isTypeOwner_iff (env : FrontEnv) (front : ModPath) (name : Name) :
    isTypeOwner env front name = true ↔ TypeOwner env front name := by
  unfold isTypeOwner TypeOwner
  rw [Bool.or_eq_true, isScalarOwner_iff, isOwnerAt_typeDeclAt]

end Lanius.Mini.Reading
