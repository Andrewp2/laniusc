module

public import Lanius.Mini.Reading.Funcs
import all Lanius.Mini.Frontend.P.allocClosed
import all Lanius.Mini.Frontend.P.eApplyClosed
import all Lanius.Mini.Frontend.P.eCallClosed
import all Lanius.Mini.Frontend.P.letIndexClosed
import all Lanius.Mini.Frontend.P.letSliceClosed
import all Lanius.Mini.Frontend.P.letStrClosed
import all Lanius.Mini.Frontend.P.letViewClosed
import all Lanius.Mini.Frontend.P.assertClosed
import all Lanius.Mini.Frontend.P.closeParams
import all Lanius.Mini.Frontend.P.closeRet
import all Lanius.Mini.Frontend.P.closeStmt
import all Lanius.Mini.Frontend.P.consFunc
import all Lanius.Mini.Frontend.P.consFuncTail
import all Lanius.Mini.Frontend.P.consSrcParam
import all Lanius.Mini.Frontend.P.setFieldEvalClosed
import all Lanius.Mini.Frontend.P.srcFunc
import all Lanius.Mini.Frontend.P.closeFuncs
import all Lanius.Mini.Frontend.P.isizeTy
import all Lanius.Mini.Frontend.P.consName
import all Lanius.Mini.Frontend.P.consNameTail
import all Lanius.Mini.Frontend.P.distinct
import all Lanius.Mini.Frontend.P.distinctModules
import all Lanius.Mini.Frontend.P.moduleMember
import all Lanius.Mini.Frontend.P.position
import all Lanius.Mini.Frontend.P.sameSpellings
import all Lanius.Mini.Frontend.P.singleName
import all Lanius.Mini.Frontend.P.eCastClosed
import all Lanius.Mini.Frontend.P.eDivideClosed
import all Lanius.Mini.Frontend.P.eNegClosed
import all Lanius.Mini.Frontend.P.eNotClosed
import all Lanius.Mini.Frontend.P.eArraySliceClosed
import all Lanius.Mini.Frontend.P.eDerefClosed
import all Lanius.Mini.Frontend.P.eIndexClosed
import all Lanius.Mini.Frontend.P.ePlaceAtClosed
import all Lanius.Mini.Frontend.P.ePlaceFieldClosed
import all Lanius.Mini.Frontend.P.setPlaceClosed
import all Lanius.Mini.Frontend.P.setPlaceOpClosed
import all Lanius.Mini.Frontend.P.closeEff
import all Lanius.Mini.Frontend.P.consSrcEff
import all Lanius.Mini.Frontend.P.eIfClosed
import all Lanius.Mini.Frontend.P.eLetClosed
import all Lanius.Mini.Frontend.P.eMatchClosed
import all Lanius.Mini.Frontend.P.eStructClosed
import all Lanius.Mini.Frontend.P.eVariantClosed
import all Lanius.Mini.Frontend.P.letEvalClosed
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
import all Lanius.Mini.Frontend.P.consType
import all Lanius.Mini.Frontend.P.consTypeTail
import all Lanius.Mini.Frontend.P.consTypes
import all Lanius.Mini.Frontend.P.consTypesTail
import all Lanius.Mini.Frontend.P.flatPayloads
import all Lanius.Mini.Frontend.P.flattenTys
import all Lanius.Mini.Frontend.P.refType
import all Lanius.Mini.Frontend.P.sliceType
import all Lanius.Mini.Frontend.P.weightAddTo
import all Lanius.Mini.Frontend.P.weightLimit
import all Lanius.Mini.Frontend.P.weightSum
import all Lanius.Mini.Frontend.P.arrayType
import all Lanius.Mini.Frontend.P.enumSrc
import all Lanius.Mini.Frontend.P.srcWeight
import all Lanius.Mini.Frontend.P.structSrc
import all Lanius.Mini.Frontend.P.weighed
import all Lanius.Mini.Frontend.P.weightAdd
import all Lanius.Mini.Frontend.P.weightArray
import all Lanius.Mini.Frontend.P.weightTimes
import all Lanius.Mini.Frontend.P.declWeight
import all Lanius.Mini.Frontend.P.fieldsWeight
import all Lanius.Mini.Frontend.P.funcsOnto
import all Lanius.Mini.Frontend.P.funcsTys
import all Lanius.Mini.Frontend.P.instWeight
import all Lanius.Mini.Frontend.P.isNoneWeight
import all Lanius.Mini.Frontend.P.loweredAll
import all Lanius.Mini.Frontend.P.monoLoop
import all Lanius.Mini.Frontend.P.namedWeight
import all Lanius.Mini.Frontend.P.paramTys
import all Lanius.Mini.Frontend.P.payloadsWeight
import all Lanius.Mini.Frontend.P.retTys
import all Lanius.Mini.Frontend.P.seedTys
import all Lanius.Mini.Frontend.P.stmtTys
import all Lanius.Mini.Frontend.P.tyKnown
import all Lanius.Mini.Frontend.P.tyWeight
import all Lanius.Mini.Frontend.P.typeTable
import all Lanius.Mini.Frontend.P.typeTableMore
import all Lanius.Mini.Frontend.P.tysWeight
import all Lanius.Mini.Frontend.P.unweighed
import all Lanius.Mini.Frontend.P.weighAgain
import all Lanius.Mini.Frontend.P.weighRound
import all Lanius.Mini.Frontend.P.weighRounds
import all Lanius.Mini.Frontend.P.weighedMore
import all Lanius.Mini.Frontend.P.allWeighed
import all Lanius.Mini.Frontend.P.closeNamed
import all Lanius.Mini.Frontend.P.closeTy
import all Lanius.Mini.Frontend.P.srcEnumId
import all Lanius.Mini.Frontend.P.tableWeighed
import all Lanius.Mini.Frontend.P.typesWeighed
import all Lanius.Mini.Frontend.P.letClosed
import all Lanius.Mini.Frontend.P.armTyClosed
import all Lanius.Mini.Frontend.P.ifClosed
import all Lanius.Mini.Frontend.P.letCallClosed
import all Lanius.Mini.Frontend.P.letEnumClosed
import all Lanius.Mini.Frontend.P.letMatchClosed
import all Lanius.Mini.Frontend.P.letStructClosed
import all Lanius.Mini.Frontend.P.matchArmClosed
import all Lanius.Mini.Frontend.P.setCallClosed
import all Lanius.Mini.Frontend.P.thenClosed
import all Lanius.Mini.Frontend.P.unreachableClosed
import all Lanius.Mini.Frontend.P.whileClosed
import all Lanius.Mini.Frontend.P.lowerTy
import all Lanius.Mini.Frontend.P.discardClosed
import all Lanius.Mini.Frontend.P.ifEvalClosed
import all Lanius.Mini.Frontend.P.returnEvalClosed
import all Lanius.Mini.Frontend.P.setEvalClosed
import all Lanius.Mini.Frontend.P.setIndexEvalClosed
import all Lanius.Mini.Frontend.P.whileEvalClosed
import all Lanius.Mini.Frontend.P.attach
import all Lanius.Mini.Frontend.P.only
import all Lanius.Mini.Frontend.P.shrFirst
import all Lanius.Mini.Frontend.P.shrSecond
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
import all Lanius.Mini.Frontend.P.checkedFunc

@[expose] public section
/-! # The reading, V8e: the closed program

`EffClosed decls fns types x s`, `StmtClosed` and `FuncClosed`: a
monomorphized expression, statement or function as a source one, its types
lowered against the type table (`LowerR`) and each call naming its
instance's first position in the function table. The builder reads a type
instance's lowering from a table made once (`Tables.lowered`); `LoweredOk`
says the table holds the instances' lowerings, so the reading is the same. -/

namespace Lanius.Mini.Reading

open Lanius.Mini

/-! ## Types -/

/-- The lowering table holds each type instance's lowering. -/
def LoweredOk (t : Tables) : Prop :=
  ∀ {i : Nat} {x : Inst} {s : SrcType}, t.types[i]? = some x → t.lowered[i]? = some (some s) →
    LowerR t.decls t.types (.tyNamed x.decl x.args) s

theorem loweredAll_get {fuel : Nat} {decls : Decls} {types : List Inst} : ∀ (xs : List Inst) (i : Nat),
    (loweredAll fuel decls types xs)[i]? = xs[i]?.map (fun x => lowerNamed (fuel - 1) decls types x.decl x.args)
  | [], i => by simp [loweredAll]
  | x :: rest, 0 => by simp [loweredAll]
  | x :: rest, i + 1 => by simp [loweredAll, loweredAll_get rest i]

theorem loweredAll_ok {fuel : Nat} {t : Tables} (h : t.lowered = loweredAll fuel t.decls t.types t.types) :
    LoweredOk t := by
  intro i x s hx hs
  rw [h, loweredAll_get, hx] at hs
  simp only [Option.map_some, Option.some.injEq] at hs
  exact (lowerSound _).2.1 hs

theorem closeTy_sound {t : Tables} (ok : LoweredOk t) :
    ∀ {fuel : Nat} {ty : Ty} {s : SrcType}, closeTy fuel t ty = some s → LowerR t.decls t.types ty s
  | 0, ty, s, h => by rw [closeTy.eq_def] at h; simp at h
  | f + 1, ty, s, h => by
    rw [closeTy.eq_def] at h
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
    cases ty with
    | tyI32 => cases h; exact .i32
    | tyBool => cases h; exact .bool
    | tyUint k => cases h; exact .uint
    | tyPtr => cases h; exact .ptr
    | tyIsize => cases h; exact .isize
    | tyChar => cases h; exact .char
    | tyStr => cases h; exact .str
    | tyFloat ft => cases h; exact .float
    | tySint _ => cases h; exact .sint
    | tySlice e =>
      simp only at h
      cases he : closeTy f t e with
      | none => rw [he] at h; cases h
      | some x => rw [he] at h; cases h; exact .slice (closeTy_sound ok he)
    | tyRef e =>
      simp only [refType] at h
      cases he : closeTy f t e with
      | none => rw [he] at h; cases h
      | some x => rw [he] at h; cases h; exact .ref (closeTy_sound ok he)
    | tyArray e n =>
      simp only [arrayType] at h
      cases he : closeTy f t e with
      | none => rw [he] at h; cases h
      | some x => rw [he] at h; obtain rfl := weighed_eq h; exact .array (closeTy_sound ok he)
    | tyNamed d args =>
      simp only [closeNamed, Nat.add_sub_cancel] at h
      cases hi : instIndex t.types ⟨d, args⟩ 0 with
      | none => rw [hi] at h; exact (lowerSound f).2.1 h
      | some i =>
        rw [hi] at h
        simp only at h
        cases hl : t.lowered[i]? with
        | none => rw [hl] at h; exact (lowerSound f).2.1 h
        | some x =>
          rw [hl] at h
          simp only at h
          exact ok (instIndex_sound hi).1 (by rw [hl, h])

theorem srcEnumId_some {x : Option SrcType} {e : Nat} (h : srcEnumId x = some e) :
    ∃ sss, x = some (.enum e sss) := by
  cases x with
  | none => simp [srcEnumId] at h
  | some y => cases y <;> simp [srcEnumId] at h; subst h; exact ⟨_, rfl⟩

/-! ## Expressions -/

mutual
inductive EffClosed (decls : Decls) (fns types : List Inst) : MEff → SrcEff → Prop
  | pure {e : SrcExpr} : EffClosed decls fns types (.xPure e) (.ePure e)
  | call {inst : Inst} {k : Nat} {args : List MEff} {as : List SrcEff} :
      FirstWith fns (· = inst) k inst → EffsClosed decls fns types args as →
      EffClosed decls fns types (.xCall inst args) (.eCall k as)
  | apply {op : SrcOp} {l r : MEff} {a b : SrcEff} :
      EffClosed decls fns types l a → EffClosed decls fns types r b →
      EffClosed decls fns types (.xApply op l r) (.eApply op a b)
  | neg {x : MEff} {a : SrcEff} : EffClosed decls fns types x a → EffClosed decls fns types (.xNeg x) (.eNeg a)
  | not {x : MEff} {a : SrcEff} : EffClosed decls fns types x a → EffClosed decls fns types (.xNot x) (.eNot a)
  | cast {ty : SrcType} {x : MEff} {a : SrcEff} :
      EffClosed decls fns types x a → EffClosed decls fns types (.xCast ty x) (.eCast ty a)
  | index {sl : Nat} {x : MEff} {a : SrcEff} :
      EffClosed decls fns types x a → EffClosed decls fns types (.xIndex sl x) (.eIndex sl a)
  | struct {ty : Ty} {s : SrcType} {fs : List MEff} {xs : List SrcEff} :
      LowerR decls types ty s → EffsClosed decls fns types fs xs →
      EffClosed decls fns types (.xStruct ty fs) (.eStruct s xs)
  | variant {ty : Ty} {s : SrcType} {k : Nat} {ps : List MEff} {xs : List SrcEff} :
      LowerR decls types ty s → EffsClosed decls fns types ps xs →
      EffClosed decls fns types (.xVariant ty k ps) (.eVariant s k xs)
  | «match» {sc : MEff} {a : SrcEff} {ety ty : Ty} {e s : SrcType} {bs : List (List Nat)} {vs : List MEff}
      {xs : List SrcEff} :
      EffClosed decls fns types sc a → LowerR decls types ety e → LowerR decls types ty s →
      EffsClosed decls fns types vs xs →
      EffClosed decls fns types (.xMatch sc ety ty bs vs) (.eMatch a e s bs xs)
  | divide {op : SrcDivOp} {l r : MEff} {a b : SrcEff} :
      EffClosed decls fns types l a → EffClosed decls fns types r b →
      EffClosed decls fns types (.xDivide op l r) (.eDivide op a b)
  | stride {sl : Nat} : EffClosed decls fns types (.xStride sl) (.eStride sl)
  | arraySlice {ty : Ty} {s : SrcType} {a : Nat} :
      LowerR decls types ty s → EffClosed decls fns types (.xArraySlice ty a) (.arraySlice s a)
  | host {id : Nat} {args : List MEff} {as : List SrcEff} : EffsClosed decls fns types args as →
      EffClosed decls fns types (.xHost id args) (.eCall id as)
  | «if» {c x y : MEff} {c' x' y' : SrcEff} {ty : Ty} {s : SrcType} :
      EffClosed decls fns types c c' → LowerR decls types ty s → EffClosed decls fns types x x' →
      EffClosed decls fns types y y' → EffClosed decls fns types (.xIf c ty x y) (.eIf c' s x' y')
  | «let» {id : Nat} {ty rt : Ty} {v b : MEff} {s r : SrcType} {v' b' : SrcEff} :
      LowerR decls types ty s → EffClosed decls fns types v v' → LowerR decls types rt r →
      EffClosed decls fns types b b' → EffClosed decls fns types (.xLet id ty v rt b) (.eLet id s v' r b')
  | len {sl : Nat} : EffClosed decls fns types (.xLen sl) (.eLen sl)
  /-- a string literal, at offset 0 until the literals are placed (`placedProgram`) -/
  | str {cs : List Nat} : EffClosed decls fns types (.xStr cs) (.eStr 0 cs)
  /-- (F5, S5) a reference's referent, a field of a place, an element of one -/
  | deref {ty : Ty} {s : SrcType} {x : MEff} {a : SrcEff} :
      LowerR decls types ty s → EffClosed decls fns types x a → EffClosed decls fns types (.xDeref ty x) (.eDeref s a)
  | placeField {x : MEff} {a : SrcEff} {j : Nat} :
      EffClosed decls fns types x a → EffClosed decls fns types (.xPlaceField x j) (.eField a j)
  | placeAt {x i : MEff} {a b : SrcEff} :
      EffClosed decls fns types x a → EffClosed decls fns types i b →
      EffClosed decls fns types (.xPlaceAt x i) (.eAt a b)

inductive EffsClosed (decls : Decls) (fns types : List Inst) : List MEff → List SrcEff → Prop
  | nil : EffsClosed decls fns types [] []
  | cons {x : MEff} {a : SrcEff} {xs : List MEff} {as : List SrcEff} :
      EffClosed decls fns types x a → EffsClosed decls fns types xs as →
      EffsClosed decls fns types (x :: xs) (a :: as)
end

mutual
theorem closeEff_sound {fuel : Nat} {t : Tables} (ok : LoweredOk t) :
    ∀ (x : MEff) (s : SrcEff), closeEff fuel t x = some s → EffClosed t.decls t.fns t.types x s
  | .xPure e, s, h => by simp only [closeEff, Option.some.injEq] at h; subst h; exact .pure
  | .xCall inst args, s, h => by
    simp only [closeEff] at h
    cases hi : instIndex t.fns inst 0 <;> cases ha : closeEffs fuel t args <;>
      simp [hi, ha, eCallClosed] at h
    subst h
    exact .call (instIndex_sound hi) (closeEffs_sound ok _ _ ha)
  | .xApply op l r, s, h => by
    simp only [closeEff] at h
    cases hl : closeEff fuel t l <;> cases hr : closeEff fuel t r <;> simp [hl, hr, eApplyClosed] at h
    subst h
    exact .apply (closeEff_sound ok _ _ hl) (closeEff_sound ok _ _ hr)
  | .xNeg a, s, h => by
    simp only [closeEff] at h
    cases ha : closeEff fuel t a <;> simp [ha, eNegClosed] at h
    subst h
    exact .neg (closeEff_sound ok _ _ ha)
  | .xNot a, s, h => by
    simp only [closeEff] at h
    cases ha : closeEff fuel t a <;> simp [ha, eNotClosed] at h
    subst h
    exact .not (closeEff_sound ok _ _ ha)
  | .xCast ty a, s, h => by
    simp only [closeEff] at h
    cases ha : closeEff fuel t a <;> simp [ha, eCastClosed] at h
    subst h
    exact .cast (closeEff_sound ok _ _ ha)
  | .xIndex sl i, s, h => by
    simp only [closeEff] at h
    cases ha : closeEff fuel t i <;> simp [ha, eIndexClosed] at h
    subst h
    exact .index (closeEff_sound ok _ _ ha)
  | .xStruct ty fs, s, h => by
    simp only [closeEff] at h
    cases ht : closeTy fuel t ty <;> cases ha : closeEffs fuel t fs <;> simp [ht, ha, eStructClosed] at h
    subst h
    exact .struct (closeTy_sound ok ht) (closeEffs_sound ok _ _ ha)
  | .xVariant ty k ps, s, h => by
    simp only [closeEff] at h
    cases ht : closeTy fuel t ty <;> cases ha : closeEffs fuel t ps <;> simp [ht, ha, eVariantClosed] at h
    subst h
    exact .variant (closeTy_sound ok ht) (closeEffs_sound ok _ _ ha)
  | .xMatch sc ety ty bs vs, s, h => by
    simp only [closeEff] at h
    cases hs : closeEff fuel t sc <;> cases he : closeTy fuel t ety <;> cases ht : closeTy fuel t ty <;>
      cases ha : closeEffs fuel t vs <;> simp [hs, he, ht, ha, eMatchClosed] at h
    subst h
    exact .match (closeEff_sound ok _ _ hs) (closeTy_sound ok he) (closeTy_sound ok ht) (closeEffs_sound ok _ _ ha)
  | .xDivide op l r, s, h => by
    simp only [closeEff] at h
    cases hl : closeEff fuel t l <;> cases hr : closeEff fuel t r <;> simp [hl, hr, eDivideClosed] at h
    subst h
    exact .divide (closeEff_sound ok _ _ hl) (closeEff_sound ok _ _ hr)
  | .xStride sl, s, h => by simp only [closeEff, Option.some.injEq] at h; subst h; exact .stride
  | .xArraySlice ty a, s, h => by
    simp only [closeEff] at h
    cases ht : closeTy fuel t ty <;> simp [ht, eArraySliceClosed] at h
    subst h
    exact .arraySlice (closeTy_sound ok ht)
  | .xHost id args, s, h => by
    simp only [closeEff] at h
    cases ha : closeEffs fuel t args <;> simp [ha, eCallClosed] at h
    subst h
    exact .host (closeEffs_sound ok _ _ ha)
  | .xIf c ty x y, s, h => by
    simp only [closeEff] at h
    cases hc : closeEff fuel t c <;> cases ht : closeTy fuel t ty <;> cases hx : closeEff fuel t x <;>
      cases hy : closeEff fuel t y <;> simp [hc, ht, hx, hy, eIfClosed] at h
    subst h
    exact .if (closeEff_sound ok _ _ hc) (closeTy_sound ok ht) (closeEff_sound ok _ _ hx) (closeEff_sound ok _ _ hy)
  | .xLet id ty v rt b, s, h => by
    simp only [closeEff] at h
    cases ht : closeTy fuel t ty <;> cases hv : closeEff fuel t v <;> cases hr : closeTy fuel t rt <;>
      cases hb : closeEff fuel t b <;> simp [ht, hv, hr, hb, eLetClosed] at h
    subst h
    exact .let (closeTy_sound ok ht) (closeEff_sound ok _ _ hv) (closeTy_sound ok hr) (closeEff_sound ok _ _ hb)
  | .xLen sl, s, h => by simp only [closeEff, Option.some.injEq] at h; subst h; exact .len
  | .xStr cs, s, h => by simp only [closeEff, Option.some.injEq] at h; subst h; exact .str
  | .xDeref ty a, s, h => by
    simp only [closeEff] at h
    cases ht : closeTy fuel t ty <;> cases ha : closeEff fuel t a <;> simp [ht, ha, eDerefClosed] at h
    subst h
    exact .deref (closeTy_sound ok ht) (closeEff_sound ok _ _ ha)
  | .xPlaceField b j, s, h => by
    simp only [closeEff] at h
    cases hb : closeEff fuel t b <;> simp [hb, ePlaceFieldClosed] at h
    subst h
    exact .placeField (closeEff_sound ok _ _ hb)
  | .xPlaceAt b i, s, h => by
    simp only [closeEff] at h
    cases hb : closeEff fuel t b <;> cases hi : closeEff fuel t i <;> simp [hb, hi, ePlaceAtClosed] at h
    subst h
    exact .placeAt (closeEff_sound ok _ _ hb) (closeEff_sound ok _ _ hi)

theorem closeEffs_sound {fuel : Nat} {t : Tables} (ok : LoweredOk t) :
    ∀ (xs : List MEff) (ss : List SrcEff), closeEffs fuel t xs = some ss → EffsClosed t.decls t.fns t.types xs ss
  | [], ss, h => by simp only [closeEffs, Option.some.injEq] at h; subst h; exact .nil
  | x :: rest, ss, h => by
    simp only [closeEffs] at h
    cases hx : closeEff fuel t x <;> cases hr : closeEffs fuel t rest <;> simp [hx, hr, consSrcEff] at h
    subst h
    exact .cons (closeEff_sound ok _ _ hx) (closeEffs_sound ok _ _ hr)
end

/-! ## Statements -/

inductive StmtClosed (decls : Decls) (fns types : List Inst) : MStmt → SrcStmt → Prop
  | nop : StmtClosed decls fns types .mNop .nop
  | «let» {id : Nat} {ty : Ty} {s : SrcType} {e : SrcExpr} {b : MStmt} {c : SrcStmt} :
      LowerR decls types ty s → StmtClosed decls fns types b c →
      StmtClosed decls fns types (.mLet id ty e b) (.let id s e c)
  | letStruct {id : Nat} {ty : Ty} {s : SrcType} {es : List SrcExpr} {b : MStmt} {c : SrcStmt} :
      LowerR decls types ty s → StmtClosed decls fns types b c →
      StmtClosed decls fns types (.mLetStruct id ty es b) (.letStruct id s es c)
  | letCall {id : Nat} {ty : Ty} {s : SrcType} {inst : Inst} {k : Nat} {args : List SrcExpr} {b : MStmt}
      {c : SrcStmt} :
      LowerR decls types ty s → FirstWith fns (· = inst) k inst → StmtClosed decls fns types b c →
      StmtClosed decls fns types (.mLetCall id ty inst args b) (.letCall id s k args c)
  | letEnum {id : Nat} {ty : Ty} {s : SrcType} {k : Nat} {es : List SrcExpr} {b : MStmt} {c : SrcStmt} :
      LowerR decls types ty s → StmtClosed decls fns types b c →
      StmtClosed decls fns types (.mLetEnum id ty k es b) (.letEnum id s k es c)
  | letMatch {id : Nat} {ty : Ty} {s : SrcType} {sc : Nat} {sty : Ty} {e : Nat} {sss : List (List SrcType)}
      {arms : List SrcArm} {b : MStmt} {c : SrcStmt} :
      LowerR decls types ty s → LowerR decls types sty (.enum e sss) → StmtClosed decls fns types b c →
      StmtClosed decls fns types (.mLetMatch id ty sc sty arms b) (.letMatch id s sc e arms c)
  | set {id : Nat} {e : SrcExpr} : StmtClosed decls fns types (.mSet id e) (.set id e)
  | setField {id j : Nat} {e : SrcExpr} : StmtClosed decls fns types (.mSetField id j e) (.setField id j e)
  | setCall {id : Nat} {inst : Inst} {k : Nat} {args : List SrcExpr} :
      FirstWith fns (· = inst) k inst → StmtClosed decls fns types (.mSetCall id inst args) (.setCall id k args)
  | «then» {a b : MStmt} {c d : SrcStmt} :
      StmtClosed decls fns types a c → StmtClosed decls fns types b d →
      StmtClosed decls fns types (.mThen a b) (.then c d)
  | «if» {e : SrcExpr} {a b : MStmt} {c d : SrcStmt} :
      StmtClosed decls fns types a c → StmtClosed decls fns types b d →
      StmtClosed decls fns types (.mIf e a b) (.if e c d)
  | «while» {e : SrcExpr} {b : MStmt} {c : SrcStmt} :
      StmtClosed decls fns types b c → StmtClosed decls fns types (.mWhile e b) (.while e c)
  | «return» {e : SrcExpr} : StmtClosed decls fns types (.mReturn e) (.return e)
  | letAlloc {id : Nat} {size : SrcExpr} {shift : Nat} {b : MStmt} {c : SrcStmt} :
      StmtClosed decls fns types b c →
      StmtClosed decls fns types (.mLetAlloc id size shift b) (.letAlloc id size shift c)
  | free {p size : SrcExpr} {shift : Nat} :
      StmtClosed decls fns types (.mFree p size shift) (.free p size shift)
  | letSlice {id : Nat} {ty : Ty} {s : SrcType} {p n : SrcExpr} {b : MStmt} {c : SrcStmt} :
      LowerR decls types ty s → StmtClosed decls fns types b c →
      StmtClosed decls fns types (.mLetSlice id ty p n b) (.letSlice id s p n c)
  | letIndex {id : Nat} {ty : Ty} {s : SrcType} {sl : Nat} {i : SrcExpr} {b : MStmt} {c : SrcStmt} :
      LowerR decls types ty s → StmtClosed decls fns types b c →
      StmtClosed decls fns types (.mLetIndex id ty sl i b) (.letIndex id s sl i c)
  | letView {id n p : Nat} {es : List SrcExpr} {b : MStmt} {c : SrcStmt} :
      StmtClosed decls fns types b c → StmtClosed decls fns types (.mLetView id n es p b) (.letView id n es p c)
  | letStr {id : Nat} {cs : List Nat} {b : MStmt} {c : SrcStmt} :
      StmtClosed decls fns types b c → StmtClosed decls fns types (.mLetStr id cs b) (.letStr id cs c)
  | setIndex {sl : Nat} {i v : SrcExpr} : StmtClosed decls fns types (.mSetIndex sl i v) (.setIndex sl i v)
  | letEval {id : Nat} {ty : Ty} {s : SrcType} {x : MEff} {a : SrcEff} {b : MStmt} {c : SrcStmt} :
      LowerR decls types ty s → EffClosed decls fns types x a → StmtClosed decls fns types b c →
      StmtClosed decls fns types (.mLetEval id ty x b) (.letEval id s a c)
  | setEval {id : Nat} {x : MEff} {a : SrcEff} :
      EffClosed decls fns types x a → StmtClosed decls fns types (.mSetEval id x) (.setEval id a)
  | ifEval {x : MEff} {e : SrcEff} {a b : MStmt} {c d : SrcStmt} :
      EffClosed decls fns types x e → StmtClosed decls fns types a c → StmtClosed decls fns types b d →
      StmtClosed decls fns types (.mIfEval x a b) (.ifEval e c d)
  | whileEval {x : MEff} {e : SrcEff} {b : MStmt} {c : SrcStmt} :
      EffClosed decls fns types x e → StmtClosed decls fns types b c →
      StmtClosed decls fns types (.mWhileEval x b) (.whileEval e c)
  | returnEval {x : MEff} {a : SrcEff} :
      EffClosed decls fns types x a → StmtClosed decls fns types (.mReturnEval x) (.returnEval a)
  | discard {x : MEff} {a : SrcEff} :
      EffClosed decls fns types x a → StmtClosed decls fns types (.mDiscard x) (.discard a)
  | setIndexEval {sl : Nat} {i v : MEff} {a b : SrcEff} :
      EffClosed decls fns types i a → EffClosed decls fns types v b →
      StmtClosed decls fns types (.mSetIndexEval sl i v) (.setIndexEval sl a b)
  | setFieldEval {id j : Nat} {x : MEff} {a : SrcEff} :
      EffClosed decls fns types x a → StmtClosed decls fns types (.mSetFieldEval id j x) (.setFieldEval id j a)
  | returnUnit : StmtClosed decls fns types .mReturnUnit .returnUnit
  | «break» : StmtClosed decls fns types .mBreak .break
  | «continue» : StmtClosed decls fns types .mContinue .continue
  | «assert» {x : MEff} {a : SrcEff} :
      EffClosed decls fns types x a → StmtClosed decls fns types (.mAssert x) (.assert a)
  | matchArmBound {sc : Nat} {sty : Ty} {e : Nat} {sss : List (List SrcType)} {k x : Nat} {ty : Ty} {s : SrcType}
      {b r : MStmt} {c d : SrcStmt} :
      LowerR decls types sty (.enum e sss) → LowerR decls types ty s → StmtClosed decls fns types b c →
      StmtClosed decls fns types r d →
      StmtClosed decls fns types (.mMatchArm sc sty k true x ty b r) (.matchArm sc e k true x s c d)
  | unreachable {id : Nat} {ty : Ty} {s : SrcType} :
      LowerR decls types ty s → StmtClosed decls fns types (.mUnreachable id ty) (.unreachable id s)
  /-- (F5, S5) an assignment to a place -/
  | setPlace {p v : MEff} {a b : SrcEff} :
      EffClosed decls fns types p a → EffClosed decls fns types v b →
      StmtClosed decls fns types (.mSetPlace p v) (.setPlace a b)
  | setPlaceOp {op : SrcAssignOp} {p v : MEff} {a b : SrcEff} :
      EffClosed decls fns types p a → EffClosed decls fns types v b →
      StmtClosed decls fns types (.mSetPlaceOp op p v) (.setPlaceOp op a b)
  | matchArmUnbound {sc : Nat} {sty : Ty} {e : Nat} {sss : List (List SrcType)} {k x : Nat} {ty : Ty}
      {b r : MStmt} {c d : SrcStmt} :
      LowerR decls types sty (.enum e sss) → StmtClosed decls fns types b c → StmtClosed decls fns types r d →
      StmtClosed decls fns types (.mMatchArm sc sty k false x ty b r) (.matchArm sc e k false x .unit c d)

theorem closeStmt_sound {fuel : Nat} {t : Tables} (ok : LoweredOk t) :
    ∀ (m : MStmt) (s : SrcStmt), closeStmt fuel t m = some s → StmtClosed t.decls t.fns t.types m s
  | .mNop, s, h => by simp only [closeStmt, Option.some.injEq] at h; subst h; exact .nop
  | .mLet id ty e b, s, h => by
    simp only [closeStmt] at h
    cases ht : closeTy fuel t ty <;> cases hb : closeStmt fuel t b <;> simp [ht, hb, letClosed] at h
    subst h
    exact .let (closeTy_sound ok ht) (closeStmt_sound ok _ _ hb)
  | .mLetStruct id ty es b, s, h => by
    simp only [closeStmt] at h
    cases ht : closeTy fuel t ty <;> cases hb : closeStmt fuel t b <;> simp [ht, hb, letStructClosed] at h
    subst h
    exact .letStruct (closeTy_sound ok ht) (closeStmt_sound ok _ _ hb)
  | .mLetCall id ty inst args b, s, h => by
    simp only [closeStmt] at h
    cases ht : closeTy fuel t ty <;> cases hi : instIndex t.fns inst 0 <;> cases hb : closeStmt fuel t b <;>
      simp [ht, hi, hb, letCallClosed] at h
    subst h
    exact .letCall (closeTy_sound ok ht) (instIndex_sound hi) (closeStmt_sound ok _ _ hb)
  | .mLetEnum id ty k es b, s, h => by
    simp only [closeStmt] at h
    cases ht : closeTy fuel t ty <;> cases hb : closeStmt fuel t b <;> simp [ht, hb, letEnumClosed] at h
    subst h
    exact .letEnum (closeTy_sound ok ht) (closeStmt_sound ok _ _ hb)
  | .mLetMatch id ty sc sty arms b, s, h => by
    simp only [closeStmt] at h
    cases ht : closeTy fuel t ty <;> cases he : srcEnumId (closeTy fuel t sty) <;>
      cases hb : closeStmt fuel t b <;> simp [ht, he, hb, letMatchClosed] at h
    subst h
    obtain ⟨sss, hs⟩ := srcEnumId_some he
    exact .letMatch (closeTy_sound ok ht) (closeTy_sound ok hs) (closeStmt_sound ok _ _ hb)
  | .mSet id e, s, h => by simp only [closeStmt, Option.some.injEq] at h; subst h; exact .set
  | .mSetField id j e, s, h => by simp only [closeStmt, Option.some.injEq] at h; subst h; exact .setField
  | .mSetCall id inst args, s, h => by
    simp only [closeStmt] at h
    cases hi : instIndex t.fns inst 0 <;> simp [hi, setCallClosed] at h
    subst h
    exact .setCall (instIndex_sound hi)
  | .mThen a b, s, h => by
    simp only [closeStmt] at h
    cases ha : closeStmt fuel t a <;> cases hb : closeStmt fuel t b <;> simp [ha, hb, thenClosed] at h
    subst h
    exact .then (closeStmt_sound ok _ _ ha) (closeStmt_sound ok _ _ hb)
  | .mIf e a b, s, h => by
    simp only [closeStmt] at h
    cases ha : closeStmt fuel t a <;> cases hb : closeStmt fuel t b <;> simp [ha, hb, ifClosed] at h
    subst h
    exact .if (closeStmt_sound ok _ _ ha) (closeStmt_sound ok _ _ hb)
  | .mWhile e b, s, h => by
    simp only [closeStmt] at h
    cases hb : closeStmt fuel t b <;> simp [hb, whileClosed] at h
    subst h
    exact .while (closeStmt_sound ok _ _ hb)
  | .mReturn e, s, h => by simp only [closeStmt, Option.some.injEq] at h; subst h; exact .return
  | .mLetAlloc id size shift b, s, h => by
    simp only [closeStmt] at h
    cases hb : closeStmt fuel t b <;> simp [hb, allocClosed] at h
    subst h
    exact .letAlloc (closeStmt_sound ok _ _ hb)
  | .mFree p size shift, s, h => by simp only [closeStmt, Option.some.injEq] at h; subst h; exact .free
  | .mLetSlice id ty p n b, s, h => by
    simp only [closeStmt] at h
    cases ht : closeTy fuel t ty <;> cases hb : closeStmt fuel t b <;> simp [ht, hb, letSliceClosed] at h
    subst h
    exact .letSlice (closeTy_sound ok ht) (closeStmt_sound ok _ _ hb)
  | .mLetIndex id ty sl i b, s, h => by
    simp only [closeStmt] at h
    cases ht : closeTy fuel t ty <;> cases hb : closeStmt fuel t b <;> simp [ht, hb, letIndexClosed] at h
    subst h
    exact .letIndex (closeTy_sound ok ht) (closeStmt_sound ok _ _ hb)
  | .mLetView id n es p b, s, h => by
    simp only [closeStmt] at h
    cases hb : closeStmt fuel t b <;> simp [hb, letViewClosed] at h
    subst h
    exact .letView (closeStmt_sound ok _ _ hb)
  | .mLetStr id cs b, s, h => by
    simp only [closeStmt] at h
    cases hb : closeStmt fuel t b <;> simp [hb, letStrClosed] at h
    subst h
    exact .letStr (closeStmt_sound ok _ _ hb)
  | .mSetIndex sl i v, s, h => by simp only [closeStmt, Option.some.injEq] at h; subst h; exact .setIndex
  | .mLetEval id ty x b, s, h => by
    simp only [closeStmt] at h
    cases ht : closeTy fuel t ty <;> cases hx : closeEff fuel t x <;> cases hb : closeStmt fuel t b <;>
      simp [ht, hx, hb, letEvalClosed] at h
    subst h
    exact .letEval (closeTy_sound ok ht) (closeEff_sound ok _ _ hx) (closeStmt_sound ok _ _ hb)
  | .mSetEval id x, s, h => by
    simp only [closeStmt] at h
    cases hx : closeEff fuel t x <;> simp [hx, setEvalClosed] at h
    subst h
    exact .setEval (closeEff_sound ok _ _ hx)
  | .mIfEval x a b, s, h => by
    simp only [closeStmt] at h
    cases hx : closeEff fuel t x <;> cases ha : closeStmt fuel t a <;> cases hb : closeStmt fuel t b <;>
      simp [hx, ha, hb, ifEvalClosed] at h
    subst h
    exact .ifEval (closeEff_sound ok _ _ hx) (closeStmt_sound ok _ _ ha) (closeStmt_sound ok _ _ hb)
  | .mWhileEval x b, s, h => by
    simp only [closeStmt] at h
    cases hx : closeEff fuel t x <;> cases hb : closeStmt fuel t b <;> simp [hx, hb, whileEvalClosed] at h
    subst h
    exact .whileEval (closeEff_sound ok _ _ hx) (closeStmt_sound ok _ _ hb)
  | .mReturnEval x, s, h => by
    simp only [closeStmt] at h
    cases hx : closeEff fuel t x <;> simp [hx, returnEvalClosed] at h
    subst h
    exact .returnEval (closeEff_sound ok _ _ hx)
  | .mDiscard x, s, h => by
    simp only [closeStmt] at h
    cases hx : closeEff fuel t x <;> simp [hx, discardClosed] at h
    subst h
    exact .discard (closeEff_sound ok _ _ hx)
  | .mSetIndexEval sl i v, s, h => by
    simp only [closeStmt] at h
    cases hi : closeEff fuel t i <;> cases hv : closeEff fuel t v <;> simp [hi, hv, setIndexEvalClosed] at h
    subst h
    exact .setIndexEval (closeEff_sound ok _ _ hi) (closeEff_sound ok _ _ hv)
  | .mSetFieldEval id j x, s, h => by
    simp only [closeStmt] at h
    cases hx : closeEff fuel t x <;> simp [hx, setFieldEvalClosed] at h
    subst h
    exact .setFieldEval (closeEff_sound ok _ _ hx)
  | .mReturnUnit, s, h => by simp only [closeStmt, Option.some.injEq] at h; subst h; exact .returnUnit
  | .mBreak, s, h => by simp only [closeStmt, Option.some.injEq] at h; subst h; exact .break
  | .mContinue, s, h => by simp only [closeStmt, Option.some.injEq] at h; subst h; exact .continue
  | .mAssert x, s, h => by
    simp only [closeStmt] at h
    cases hx : closeEff fuel t x <;> simp [hx, assertClosed] at h
    subst h
    exact .assert (closeEff_sound ok _ _ hx)
  | .mUnreachable id ty, s, h => by
    simp only [closeStmt] at h
    cases ht : closeTy fuel t ty <;> simp [ht, unreachableClosed] at h
    subst h
    exact .unreachable (closeTy_sound ok ht)
  | .mSetPlace p v, s, h => by
    simp only [closeStmt] at h
    cases hp : closeEff fuel t p <;> cases hv : closeEff fuel t v <;> simp [hp, hv, setPlaceClosed] at h
    subst h
    exact .setPlace (closeEff_sound ok _ _ hp) (closeEff_sound ok _ _ hv)
  | .mSetPlaceOp op p v, s, h => by
    simp only [closeStmt] at h
    cases hp : closeEff fuel t p <;> cases hv : closeEff fuel t v <;> simp [hp, hv, setPlaceOpClosed] at h
    subst h
    exact .setPlaceOp (closeEff_sound ok _ _ hp) (closeEff_sound ok _ _ hv)
  | .mMatchArm sc sty k true x ty b r, s, h => by
    simp only [closeStmt] at h
    cases he : srcEnumId (closeTy fuel t sty) <;> cases ht : closeTy fuel t ty <;>
      cases hb : closeStmt fuel t b <;> cases hr : closeStmt fuel t r <;>
      simp [he, ht, hb, hr, armTyClosed, matchArmClosed] at h
    subst h
    obtain ⟨sss, hs⟩ := srcEnumId_some he
    exact .matchArmBound (closeTy_sound ok hs) (closeTy_sound ok ht) (closeStmt_sound ok _ _ hb)
      (closeStmt_sound ok _ _ hr)
  | .mMatchArm sc sty k false x ty b r, s, h => by
    simp only [closeStmt] at h
    cases he : srcEnumId (closeTy fuel t sty) <;> cases hb : closeStmt fuel t b <;>
      cases hr : closeStmt fuel t r <;> simp [he, hb, hr, armTyClosed, matchArmClosed] at h
    subst h
    obtain ⟨sss, hs⟩ := srcEnumId_some he
    exact .matchArmUnbound (closeTy_sound ok hs) (closeStmt_sound ok _ _ hb) (closeStmt_sound ok _ _ hr)

/-! ## Functions -/

/-- A parameter keeps its id and has its type lowered. -/
def ParamClosed (decls : Decls) (types : List Inst) (p : MParam) (q : SrcParam) : Prop :=
  q.id = p.id ∧ LowerR decls types p.ty q.ty

inductive RetClosed (decls : Decls) (types : List Inst) : RetTy → SrcType → Prop
  | unit : RetClosed decls types .retUnit .unit
  | ty {x : Ty} {s : SrcType} : LowerR decls types x s → RetClosed decls types (.retOf x) s

def FuncClosed (decls : Decls) (fns types : List Inst) (f : MFunc) (g : SrcFunc) : Prop :=
  ListRel (ParamClosed decls types) f.params g.params ∧ RetClosed decls types f.ret g.ret ∧
    StmtClosed decls fns types f.body g.body

theorem closeParams_sound {fuel : Nat} {t : Tables} (ok : LoweredOk t) :
    ∀ (ps : List MParam) (qs : List SrcParam), closeParams fuel t ps = some qs →
      ListRel (ParamClosed t.decls t.types) ps qs
  | [], qs, h => by simp only [closeParams, Option.some.injEq] at h; subst h; exact .nil
  | p :: rest, qs, h => by
    simp only [closeParams] at h
    cases ht : closeTy fuel t p.ty <;> cases hr : closeParams fuel t rest <;> simp [ht, hr, consSrcParam] at h
    subst h
    exact .cons ⟨rfl, closeTy_sound ok ht⟩ (closeParams_sound ok _ _ hr)

theorem closeRet_sound {fuel : Nat} {t : Tables} (ok : LoweredOk t) {r : RetTy} {s : SrcType}
    (h : closeRet fuel t r = some s) : RetClosed t.decls t.types r s := by
  cases r with
  | retUnit => simp only [closeRet, Option.some.injEq] at h; subst h; exact .unit
  | retOf x => exact .ty (closeTy_sound ok h)

theorem closeFuncs_sound {fuel : Nat} {t : Tables} (ok : LoweredOk t) :
    ∀ (fs : List MFunc) (gs : List SrcFunc), closeFuncs fuel t fs = some gs →
      ListRel (FuncClosed t.decls t.fns t.types) fs gs
  | [], gs, h => by simp only [closeFuncs, Option.some.injEq] at h; subst h; exact .nil
  | f :: rest, gs, h => by
    simp only [closeFuncs] at h
    cases hp : closeParams fuel t f.params <;> cases hr : closeRet fuel t f.ret <;>
      cases hb : closeStmt fuel t f.body <;> cases hs : closeFuncs fuel t rest <;>
      simp [hp, hr, hb, hs, srcFunc, consFunc, consFuncTail] at h
    subst h
    exact .cons ⟨closeParams_sound ok _ _ hp, closeRet_sound ok hr, closeStmt_sound ok _ _ hb⟩
      (closeFuncs_sound ok _ _ hs)

end Lanius.Mini.Reading
