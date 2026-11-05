module

public import Lanius.Mini.FrontSpec
public import Lanius.Mini.Reading.Prods
import all Lanius.Mini.Compiler.P.arithShiftRight
import all Lanius.Mini.Compiler.P.offsetOrArith
import all Lanius.Mini.Compiler.P.order
import all Lanius.Mini.Compiler.P.orderSint
import all Lanius.Mini.Compiler.P.orderUint
import all Lanius.Mini.Compiler.P.signKey
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
import all Lanius.Mini.Frontend.P.consName
import all Lanius.Mini.Frontend.P.consNameTail
import all Lanius.Mini.Frontend.P.distinct
import all Lanius.Mini.Frontend.P.distinctModules
import all Lanius.Mini.Frontend.P.moduleMember
import all Lanius.Mini.Frontend.P.position
import all Lanius.Mini.Frontend.P.sameSpellings
import all Lanius.Mini.Frontend.P.singleName
import all Lanius.Mini.Frontend.P.Inline_attachAfter
import all Lanius.Mini.Frontend.P.Inline_attachTerm
import all Lanius.Mini.Frontend.P.Inline_genericCloseAt
import all Lanius.Mini.Frontend.P.grammar
import all Lanius.Mini.Frontend.P.grammarPart13
import all Lanius.Mini.Frontend.P.grammarPart14
import all Lanius.Mini.Frontend.P.grammarPart15
import all Lanius.Mini.Frontend.P.grammarPart16
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
import all Lanius.Mini.Frontend.P.aliasDecls
import all Lanius.Mini.Frontend.P.collectFront
import all Lanius.Mini.Frontend.P.externTree
import all Lanius.Mini.Frontend.P.fnsDecls
import all Lanius.Mini.Frontend.P.hostExtern
import all Lanius.Mini.Frontend.P.hostId
import all Lanius.Mini.Frontend.P.implMethods
import all Lanius.Mini.Frontend.P.itemDecls
import all Lanius.Mini.Frontend.P.methodDecl
import all Lanius.Mini.Frontend.P.methodsOf
import all Lanius.Mini.Frontend.P.textFillSecureBytes
import all Lanius.Mini.Frontend.P.textLaniusStd
import all Lanius.Mini.Frontend.P.textMonotonicRead
import all Lanius.Mini.Frontend.P.textReadStdin
import all Lanius.Mini.Frontend.P.textSleepMsI32
import all Lanius.Mini.Frontend.P.textSystemRead
import all Lanius.Mini.Frontend.P.textWriteByte
import all Lanius.Mini.Frontend.P.textWriteNewline
import all Lanius.Mini.Frontend.P.textWriteStderr
import all Lanius.Mini.Frontend.P.textWriteStdout
import all Lanius.Mini.Frontend.P.textWriteText
import all Lanius.Mini.Frontend.P.typeDecls
import all Lanius.Mini.Frontend.P.withImpl
import all Lanius.Mini.Frontend.P.withImplDecl
import all Lanius.Mini.Frontend.P.consField
import all Lanius.Mini.Frontend.P.consFnDecl
import all Lanius.Mini.Frontend.P.consVariant
import all Lanius.Mini.Frontend.P.consVariantTail
import all Lanius.Mini.Frontend.P.enumDeclOf
import all Lanius.Mini.Frontend.P.fieldsOf
import all Lanius.Mini.Frontend.P.fnDeclOf
import all Lanius.Mini.Frontend.P.freeParams
import all Lanius.Mini.Frontend.P.ifUnbounded
import all Lanius.Mini.Frontend.P.importDecls
import all Lanius.Mini.Frontend.P.itemBody
import all Lanius.Mini.Frontend.P.joinDecls
import all Lanius.Mini.Frontend.P.moduleDecls
import all Lanius.Mini.Frontend.P.moduleOr
import all Lanius.Mini.Frontend.P.modulePath
import all Lanius.Mini.Frontend.P.noDecls
import all Lanius.Mini.Frontend.P.paramSpellings
import all Lanius.Mini.Frontend.P.structDeclFields
import all Lanius.Mini.Frontend.P.structDeclOf
import all Lanius.Mini.Frontend.P.typeDecl
import all Lanius.Mini.Frontend.P.typeParams
import all Lanius.Mini.Frontend.P.unbounded
import all Lanius.Mini.Frontend.P.variantPayload
import all Lanius.Mini.Frontend.P.variantsOf
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
import all Lanius.Mini.Frontend.P.build
import all Lanius.Mini.Frontend.P.buildChecked
import all Lanius.Mini.Frontend.P.buildClosed
import all Lanius.Mini.Frontend.P.buildCollected
import all Lanius.Mini.Frontend.P.buildFiles
import all Lanius.Mini.Frontend.P.buildMono
import all Lanius.Mini.Frontend.P.consRoot
import all Lanius.Mini.Frontend.P.filesFuel
import all Lanius.Mini.Frontend.P.frontEnd
import all Lanius.Mini.Frontend.P.frontEndFiles
import all Lanius.Mini.Frontend.P.lxDigit
import all Lanius.Mini.Frontend.P.lxIdentContinue
import all Lanius.Mini.Frontend.P.lxIdentStart
import all Lanius.Mini.Frontend.P.lxSpace
import all Lanius.Mini.Frontend.P.untypedRejected
import all Lanius.Mini.Frontend.P.validateFiles
import all Lanius.Mini.Frontend.P.wideLeftFuncs
import all Lanius.Mini.Frontend.P.wideLeftStmt
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
/-! # The reading, V8a: what the items declare

The first layer of the reading of parse trees (roadmap step V8): the items
of list nodes (`Items`), paths (`PathSpellings`), type parameters, and what
each item of a file declares (`ItemDecls`), file by file (`FileDeclsR`,
`CollectedR`). The rules mention only the tree and the builder's data
(`Decls`, `FnDecl`, ...), never its code; each `_sound` theorem says the
builder's function gives what the rule says. -/

namespace Lanius.Mini.Reading

open Lanius.Mini
open Lanius.Mini.Prod

/-- A spelling: the bytes of an identifier. -/
abbrev Name := List Nat

/-- A module path: its segments' spellings. -/
abbrev ModPath := List Name

/-! ## Spellings -/

theorem sameText_iff : ∀ (a b : Name), sameText a b = true ↔ a = b
  | [], [] => by simp [sameText]
  | [], _ :: _ => by simp [sameText]
  | _ :: _, [] => by simp [sameText]
  | x :: a, y :: b => by simp [sameText, sameText_iff a b]

theorem sameSpellings_iff : ∀ (a b : ModPath), sameSpellings a b = true ↔ a = b
  | [], [] => by simp [sameSpellings]
  | [], _ :: _ => by simp [sameSpellings]
  | _ :: _, [] => by simp [sameSpellings]
  | x :: a, y :: b => by simp [sameSpellings, sameText_iff, sameSpellings_iff a b]

theorem member_iff : ∀ (names : List Name) (n : Name), member names n = true ↔ n ∈ names
  | [], _ => by simp [member]
  | m :: rest, n => by
    rw [member, Bool.or_eq_true, sameText_iff, member_iff rest n, List.mem_cons]
    exact ⟨fun h => h.elim (fun e => .inl e.symm) .inr, fun h => h.elim (fun e => .inl e.symm) .inr⟩

theorem distinct_iff : ∀ (names : List Name), distinct names = true ↔ names.Nodup
  | [] => by simp [distinct]
  | n :: rest => by
    have := member_iff rest n
    cases hm : member rest n <;> simp_all [distinct, distinct_iff rest]

theorem moduleMember_iff : ∀ (ms : List ModPath) (m : ModPath), moduleMember ms m = true ↔ m ∈ ms
  | [], _ => by simp [moduleMember]
  | x :: rest, m => by
    rw [moduleMember, Bool.or_eq_true, sameSpellings_iff, moduleMember_iff rest m, List.mem_cons]
    exact ⟨fun h => h.elim (fun e => .inl e.symm) .inr, fun h => h.elim (fun e => .inl e.symm) .inr⟩

theorem distinctModules_iff : ∀ (ms : List ModPath), distinctModules ms = true ↔ ms.Nodup
  | [] => by simp [distinctModules]
  | m :: rest => by
    have := moduleMember_iff rest m
    cases hm : moduleMember rest m <;> simp_all [distinctModules, distinctModules_iff rest]

/-! ## The items of a list node

The grammar writes a list (of items, parameters, fields, ...) as a chain of
link nodes; its items are the children that are neither links nor
childless (separators), in order, with a link's own items in its place. -/

inductive ItemsIn : List CTree → List CTree → Prop
  | nil : ItemsIn [] []
  | link {k : CTree} {rest a b : List CTree} : isLink (nodeProd k) = true → ItemsIn (kidsOf k) a →
      ItemsIn rest b → ItemsIn (k :: rest) (a ++ b)
  | item {k : CTree} {rest b : List CTree} : isLink (nodeProd k) = false → hasKids k = true →
      ItemsIn rest b → ItemsIn (k :: rest) (k :: b)
  | skip {k : CTree} {rest b : List CTree} : isLink (nodeProd k) = false → hasKids k = false →
      ItemsIn rest b → ItemsIn (k :: rest) b

/-- The items of the list node `c`. -/
def Items (c : CTree) (xs : List CTree) : Prop := ItemsIn (kidsOf c) xs

theorem items_sound : ∀ fuel,
    (∀ {c xs}, listItems fuel c = some xs → Items c xs) ∧
    (∀ {kids xs}, itemsIn fuel kids = some xs → ItemsIn kids xs) ∧
    (∀ {k rest xs}, itemsCons fuel k rest = some xs → ItemsIn (k :: rest) xs)
  | 0 => ⟨fun h => by rw [listItems] at h; simp at h, fun h => by rw [itemsIn.eq_def] at h; simp at h,
      fun h => by rw [itemsCons] at h; simp at h⟩
  | fuel + 1 => by
    obtain ⟨hl, hi, hc⟩ := items_sound fuel
    refine ⟨fun h => ?_, fun h => ?_, fun h => ?_⟩
    · rw [listItems] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      exact hi h
    · rw [itemsIn.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      split at h
      · simp only [Option.some.injEq] at h
        subst h
        exact .nil
      · exact hc h
    · rename_i k rest xs
      rw [itemsCons] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      by_cases link : isLink (nodeProd k) = true
      · rw [if_pos link] at h
        simp only [joinItems] at h
        cases ha : listItems fuel k with
        | none => rw [ha] at h; cases h
        | some a =>
          rw [ha] at h
          simp only [joinSecond] at h
          cases hb : itemsIn fuel rest with
          | none => rw [hb] at h; cases h
          | some b =>
            rw [hb, Option.some.injEq] at h
            subst h
            exact .link link (hl ha) (hi hb)
      · rw [if_neg link] at h
        have nl : isLink (nodeProd k) = false := by simpa using link
        by_cases kids : hasKids k = true
        · rw [if_pos kids] at h
          simp only [joinItems, joinSecond] at h
          cases hb : itemsIn fuel rest with
          | none => rw [hb] at h; cases h
          | some b =>
            rw [hb, Option.some.injEq] at h
            subst h
            exact .item nl kids (hi hb)
        · rw [if_neg kids] at h
          exact .skip nl (by simpa using kids) (hi h)

theorem listItems_sound {fuel : Nat} {c : CTree} {xs : List CTree} (h : listItems fuel c = some xs) : Items c xs :=
  (items_sound fuel).1 h

/-! ## Paths -/

/-- The spellings of a path's segments (`a::b::c`), none with type
arguments: `segment` is the first segment's node and `tail` the rest. -/
inductive PathSpellings : CTree → CTree → ModPath → Prop
  | last {segment tail : CTree} : nodeProd segment = pPathIdent → nodeProd tail = pPathEnd →
      PathSpellings segment tail [(kidToken segment 0).text]
  | more {segment tail : CTree} {rest : ModPath} : nodeProd segment = pPathIdent → nodeProd tail = pPathMore →
      PathSpellings (kid tail 2) (kid tail 3) rest →
      PathSpellings segment tail ((kidToken segment 0).text :: rest)

theorem pathSpellings_sound : ∀ {fuel : Nat} {segment tail : CTree} {ns : ModPath},
    pathSpellings fuel segment tail = some ns → PathSpellings segment tail ns
  | 0, _, _, _, h => by rw [pathSpellings] at h; simp at h
  | fuel + 1, segment, tail, ns, h => by
    rw [pathSpellings] at h
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
    by_cases one : nodeProd segment = pPathIdent ∧ nodeProd tail = pPathEnd
    · rw [if_pos (by simpa using one), Option.some.injEq] at h
      subst h
      exact .last one.1 one.2
    · rw [if_neg (by simpa using one)] at h
      by_cases two : nodeProd segment = pPathIdent ∧ nodeProd tail = pPathMore
      · rw [if_pos (by simpa using two)] at h
        simp only [consName, consNameTail] at h
        cases hr : pathSpellings fuel (kid tail 2) (kid tail 3) with
        | none => rw [hr] at h; cases h
        | some rest =>
          rw [hr, Option.some.injEq] at h
          subst h
          exact .more two.1 two.2 (pathSpellings_sound hr)
      · rw [if_neg (by simpa using two)] at h
        cases h

/-! ## Type parameters -/

/-- The spellings of type parameters: each item is an `enum_type_param`
(its bounds are not read). -/
def ParamSpellings (items : List CTree) (ps : List Name) : Prop :=
  ListRel (fun p n => nodeProd p = pEnumTypeParam ∧ n = (kidToken p 0).text) items ps

/-- The type parameters of an `enum_type_params_opt` node. -/
def TypeParams (t : CTree) (ps : List Name) : Prop :=
  ∃ items, Items t items ∧ ParamSpellings items ps

theorem paramSpellings_sound : ∀ {items : List CTree} {ps : List Name},
    paramSpellings items = some ps → ParamSpellings items ps
  | [], ps, h => by
    simp only [paramSpellings, Option.some.injEq] at h
    subst h
    exact .nil
  | p :: rest, ps, h => by
    simp only [paramSpellings] at h
    split at h
    · rename_i hp
      simp only [consName, consNameTail] at h
      cases hr : paramSpellings rest with
      | none => rw [hr] at h; cases h
      | some ns =>
        rw [hr, Option.some.injEq] at h
        subst h
        exact .cons ⟨hp, rfl⟩ (paramSpellings_sound hr)
    · cases h

theorem typeParams_sound {fuel : Nat} {t : CTree} {ps : List Name} (h : typeParams fuel t = some ps) :
    TypeParams t ps := by
  simp only [typeParams] at h
  cases hi : listItems fuel t with
  | none => rw [hi] at h; cases h
  | some items =>
    rw [hi] at h
    exact ⟨items, listItems_sound hi, paramSpellings_sound h⟩

/-- The type parameters of a struct, enum or alias: none has a bound
(`T: Tr`), as such bounds are not checked. -/
def FreeParams (t : CTree) (ps : List Name) : Prop :=
  ∃ items, Items t items ∧ (∀ p ∈ items, nodeProd (kid p 1) = pTypeParamBoundNone) ∧ ParamSpellings items ps

theorem unbounded_iff : ∀ (items : List CTree),
    unbounded items = true ↔ ∀ p ∈ items, nodeProd (kid p 1) = pTypeParamBoundNone
  | [] => by simp [unbounded]
  | p :: rest => by simp [unbounded, unbounded_iff rest]

theorem freeParams_sound {fuel : Nat} {t : CTree} {ps : List Name} (h : freeParams fuel t = some ps) :
    FreeParams t ps := by
  simp only [freeParams] at h
  cases hi : listItems fuel t with
  | none => rw [hi] at h; cases h
  | some items =>
    rw [hi] at h
    simp only [ifUnbounded] at h
    split at h
    · rename_i u
      exact ⟨items, listItems_sound hi, (unbounded_iff items).1 u, paramSpellings_sound h⟩
    · cases h

/-! ## Type declarations -/

/-- A struct's fields: each `field` item's spelling and type expression. -/
def fieldNames (fs : List CTree) : List Name := fs.map fun f => (kidToken f 0).text

def fieldTypes (fs : List CTree) : List CTree := fs.map fun f => kid f 2

/-- An `enum_variant`'s payload type expressions: none for a unit variant. -/
inductive VariantPayload : CTree → List CTree → Prop
  | unit {v : CTree} : nodeProd (kid v 1) = pEnumVariantUnit → VariantPayload v []
  | tuple {v : CTree} {ps : List CTree} : nodeProd (kid v 1) ≠ pEnumVariantUnit → Items (kid (kid v 1) 1) ps →
      VariantPayload v ps

def structDeclAt (home : ModPath) (s : CTree) (ps : List Name) (fs : List CTree) : TypeDecl :=
  { home := home, name := (kidToken s 1).text, params := ps, isEnum := false,
    fields := fieldNames fs, fieldTypes := fieldTypes fs, variants := [], payloads := [] }

def enumDeclAt (home : ModPath) (s : CTree) (ps : List Name) (vs : List CTree) (pays : List (List CTree)) : TypeDecl :=
  { home := home, name := (kidToken s 1).text, params := ps, isEnum := true,
    fields := [], fieldTypes := [], variants := vs.map (fun v => (kidToken v 0).text), payloads := pays }

/-- What a `struct_item` or `enum_item` without a where clause or bounds
declares; a struct's field spellings are distinct. -/
inductive TypeDeclR (home : ModPath) : CTree → TypeDecl → Prop
  | struct {s : CTree} {ps : List Name} {fs : List CTree} :
      nodeProd s = pStruct → nodeProd (kid s 3) = pWhereNone → FreeParams (kid s 2) ps → Items (kid s 5) fs →
      (fieldNames fs).Nodup →
      TypeDeclR home s (structDeclAt home s ps fs)
  | enum {s : CTree} {ps : List Name} {vs : List CTree} {pays : List (List CTree)} :
      nodeProd s = pEnum → nodeProd (kid s 3) = pWhereNone → FreeParams (kid s 2) ps → Items (kid s 5) vs →
      ListRel VariantPayload vs pays →
      TypeDeclR home s (enumDeclAt home s ps vs pays)

theorem fieldsOf_eq : ∀ fs : List CTree, fieldsOf fs = { names := fieldNames fs, types := fieldTypes fs }
  | [] => rfl
  | f :: rest => by simp [fieldsOf, consField, fieldsOf_eq rest, fieldNames, fieldTypes]

theorem variantsOf_sound : ∀ {fuel : Nat} {items : List CTree} {vs : Variants}, variantsOf fuel items = some vs →
    vs.names = items.map (fun v => (kidToken v 0).text) ∧ ListRel VariantPayload items vs.payloads
  | _, [], vs, h => by
    simp only [variantsOf, Option.some.injEq] at h
    subst h
    exact ⟨rfl, .nil⟩
  | fuel, v :: rest, vs, h => by
    simp only [variantsOf, consVariant] at h
    cases hp : variantPayload fuel v with
    | none => rw [hp] at h; cases h
    | some p =>
      rw [hp] at h
      simp only [consVariantTail] at h
      cases hr : variantsOf fuel rest with
      | none => rw [hr] at h; cases h
      | some r =>
        rw [hr, Option.some.injEq] at h
        subst h
        obtain ⟨names, pays⟩ := variantsOf_sound hr
        refine ⟨by simp [names], .cons ?_ pays⟩
        simp only [variantPayload] at hp
        by_cases u : nodeProd (kid v 1) = pEnumVariantUnit
        · rw [if_pos u, Option.some.injEq] at hp
          subst hp
          exact .unit u
        · rw [if_neg u] at hp
          exact .tuple u (listItems_sound hp)

theorem typeDecl_sound {fuel : Nat} {home : ModPath} {s : CTree} {t : TypeDecl}
    (h : typeDecl fuel home s = some t) : TypeDeclR home s t := by
  simp only [typeDecl] at h
  by_cases st : nodeProd s = pStruct ∧ nodeProd (kid s 3) = pWhereNone
  · rw [if_pos (by simpa using st)] at h
    simp only [structDeclOf] at h
    cases hp : freeParams fuel (kid s 2) with
    | none => rw [hp] at h; cases h
    | some ps =>
      rw [hp] at h
      cases hi : listItems fuel (kid s 5) with
      | none => rw [hi] at h; cases h
      | some fs =>
        rw [hi] at h
        simp only [structDeclFields, fieldsOf_eq] at h
        split at h
        · rename_i nd
          rw [Option.some.injEq] at h
          subst h
          exact .struct st.1 st.2 (freeParams_sound hp) (listItems_sound hi) ((distinct_iff _).1 nd)
        · cases h
  · rw [if_neg (by simpa using st)] at h
    by_cases en : nodeProd s = pEnum ∧ nodeProd (kid s 3) = pWhereNone
    · rw [if_pos (by simpa using en)] at h
      cases hi : listItems fuel (kid s 5) with
      | none => rw [hi] at h; cases h
      | some items =>
        rw [hi] at h
        simp only [enumDeclOf] at h
        cases hp : freeParams fuel (kid s 2) with
        | none => rw [hp] at h; cases h
        | some ps =>
          rw [hp] at h
          cases hv : variantsOf fuel items with
          | none => rw [hv] at h; cases h
          | some vs =>
            rw [hv, Option.some.injEq] at h
            subst h
            obtain ⟨names, pays⟩ := variantsOf_sound hv
            rw [names]
            exact .enum en.1 en.2 (freeParams_sound hp) (listItems_sound hi) pays
    · rw [if_neg (by simpa using en)] at h
      cases h

/-! ## Functions and methods -/

/-- A function's declaration: `f` is its `fn_item` or `impl_fn_item`, and
`implTree` a method's impl node. -/
def fnDeclAt (home : ModPath) (f : CTree) (inImpl : Bool) (implParams : List Name) (selfType implTree : CTree)
    (ps : List Name) : FnDecl :=
  { home := home, name := (kidToken f 1).text, inImpl := inImpl, implParams := implParams, selfType := selfType,
    params := ps, tree := f, implTree := implTree }

/-- An `impl_method` item, `pub` or not, holding an `impl_fn_item`. -/
inductive MethodDecl (home : ModPath) (implParams : List Name) (selfType implTree : CTree) : CTree → FnDecl → Prop
  | plain {m : CTree} {ps : List Name} : nodeProd m = pImplMethod → nodeProd (kid m 0) = pImplFn →
      TypeParams (kid (kid m 0) 2) ps →
      MethodDecl home implParams selfType implTree m (fnDeclAt home (kid m 0) true implParams selfType implTree ps)
  | pub {m : CTree} {ps : List Name} : nodeProd m = pImplMethodPub → nodeProd (kid m 1) = pImplFn →
      TypeParams (kid (kid m 1) 2) ps →
      MethodDecl home implParams selfType implTree m (fnDeclAt home (kid m 1) true implParams selfType implTree ps)

theorem methodsOf_sound : ∀ {fuel : Nat} {home : ModPath} {ips : List Name} {selfType implTree : CTree}
    {items : List CTree} {fs : List FnDecl}, methodsOf fuel home ips selfType implTree items = some fs →
    ListRel (MethodDecl home ips selfType implTree) items fs
  | _, _, _, _, _, [], fs, h => by
    simp only [methodsOf, Option.some.injEq] at h
    subst h
    exact .nil
  | fuel, home, ips, selfType, implTree, m :: rest, fs, h => by
    simp only [methodsOf, consFnDecl] at h
    cases hm : methodDecl fuel home ips selfType implTree m with
    | none => rw [hm] at h; cases h
    | some d =>
      rw [hm] at h
      cases hr : methodsOf fuel home ips selfType implTree rest with
      | none => rw [hr] at h; cases h
      | some ds =>
        rw [hr, Option.some.injEq] at h
        subst h
        refine .cons ?_ (methodsOf_sound hr)
        simp only [methodDecl] at hm
        by_cases a : nodeProd m = pImplMethod ∧ nodeProd (kid m 0) = pImplFn
        · rw [if_pos (by simpa using a)] at hm
          simp only [fnDeclOf] at hm
          cases hp : typeParams fuel (kid (kid m 0) 2) with
          | none => rw [hp] at hm; cases hm
          | some ps =>
            rw [hp, Option.some.injEq] at hm
            subst hm
            exact .plain a.1 a.2 (typeParams_sound hp)
        · rw [if_neg (by simpa using a)] at hm
          by_cases b : nodeProd m = pImplMethodPub ∧ nodeProd (kid m 1) = pImplFn
          · rw [if_pos (by simpa using b)] at hm
            simp only [fnDeclOf] at hm
            cases hp : typeParams fuel (kid (kid m 1) 2) with
            | none => rw [hp] at hm; cases hm
            | some ps =>
              rw [hp, Option.some.injEq] at hm
              subst hm
              exact .pub b.1 b.2 (typeParams_sound hp)
          · rw [if_neg (by simpa using b)] at hm
            cases hm

/-! ## Items -/

def constDeclAt (home : ModPath) (b : CTree) : ConstDecl :=
  { home := home, name := (kidToken b 1).text, ty := kid b 3, value := kid b 5 }

def aliasDeclAt (home : ModPath) (b : CTree) (ps : List Name) : AliasDecl :=
  { home := home, name := (kidToken b 1).text, params := ps, ty := kid b 6 }

def _root_.Lanius.Mini.Decls.append (a b : Decls) : Decls :=
  { types := a.types ++ b.types, fns := a.fns ++ b.fns, consts := a.consts ++ b.consts,
    imports := a.imports ++ b.imports, aliases := a.aliases ++ b.aliases, impls := a.impls ++ b.impls,
    homes := a.homes ++ b.homes }

def onlyTypes (ts : List TypeDecl) : Decls := { noDecls with types := ts }
def onlyFns (fs : List FnDecl) : Decls := { noDecls with fns := fs }
def onlyConsts (cs : List ConstDecl) : Decls := { noDecls with consts := cs }
def onlyImports (is : List ImportDecl) : Decls := { noDecls with imports := is }
def onlyAliases (as : List AliasDecl) : Decls := { noDecls with aliases := as }
def onlyHomes (ms : List ModPath) : Decls := { noDecls with homes := ms }

/-- What an item (`b` is the item it holds, `pub` or not) declares in the
module `home`: a struct or enum, a function, a constant, the methods of an
impl block (and a trait impl itself, for the bounds), an import, a type
alias without a where clause or bounds, or an `extern "lanius_std" fn` of a
host service (`hostExtern`;
its tree rearranged by `externTree` to a function's shape), or a `module`
item's path, a module whatever its file declares (as laniusc's module
records). Another `extern fn`, a trait, an import of another form and an
alias with a where clause declare nothing. -/
inductive ItemDecls (home : ModPath) : CTree → Decls → Prop
  | type {item : CTree} {t : TypeDecl} : (nodeProd (itemBody item) = pStruct ∨ nodeProd (itemBody item) = pEnum) →
      TypeDeclR home (itemBody item) t → ItemDecls home item (onlyTypes [t])
  | fn {item : CTree} {ps : List Name} : nodeProd (itemBody item) = pFn → TypeParams (kid (itemBody item) 2) ps →
      ItemDecls home item (onlyFns [fnDeclAt home (itemBody item) false [] (itemBody item) (itemBody item) ps])
  | const {item : CTree} : nodeProd (itemBody item) = pConst →
      ItemDecls home item (onlyConsts [constDeclAt home (itemBody item)])
  | implInherent {item : CTree} {ps : List Name} {ms : List CTree} {fs : List FnDecl} :
      nodeProd (itemBody item) = pImplInherent →
      TypeParams (kid (itemBody item) 1) ps → Items (kid (itemBody item) 5) ms →
      ListRel (MethodDecl home ps (kid (itemBody item) 2) (itemBody item)) ms fs → ItemDecls home item (onlyFns fs)
  | implTrait {item : CTree} {ps : List Name} {ms : List CTree} {fs : List FnDecl} :
      nodeProd (itemBody item) = pImplTrait →
      TypeParams (kid (itemBody item) 1) ps → Items (kid (itemBody item) 7) ms →
      ListRel (MethodDecl home ps (kid (itemBody item) 4) (itemBody item)) ms fs →
      ItemDecls home item { onlyFns fs with impls := [{ home := home, params := ps, tree := itemBody item }] }
  | imports {item : CTree} {target : ModPath} : nodeProd (itemBody item) = pImport →
      nodeProd (kid (itemBody item) 1) = pImportPath →
      PathSpellings (kid (kid (kid (itemBody item) 1) 0) 0) (kid (kid (kid (itemBody item) 1) 0) 1) target →
      ItemDecls home item (onlyImports [({ home := home, target := target } : ImportDecl)])
  | alias {item : CTree} {ps : List Name} : nodeProd (itemBody item) = pTypeAlias →
      nodeProd (kid (itemBody item) 3) = pWhereNone → FreeParams (kid (itemBody item) 2) ps →
      ItemDecls home item (onlyAliases [aliasDeclAt home (itemBody item) ps])
  | host {item : CTree} {ps : List Name} : nodeProd (itemBody item) = pExternFn →
      hostExtern (itemBody item) = true → TypeParams (kid (itemBody item) 4) ps →
      ItemDecls home item (onlyFns [fnDeclAt home (externTree (itemBody item)) false [] (itemBody item) (itemBody item) ps])
  | «module» {item : CTree} {m : ModPath} : nodeProd (itemBody item) = pModule →
      PathSpellings (kid (kid (itemBody item) 1) 0) (kid (kid (itemBody item) 1) 1) m →
      ItemDecls home item (onlyHomes [m])
  | none {item : CTree} : ((nodeProd (itemBody item) = pImport ∧ nodeProd (kid (itemBody item) 1) ≠ pImportPath) ∨
        (nodeProd (itemBody item) = pExternFn ∧ hostExtern (itemBody item) = false) ∨
        nodeProd (itemBody item) = pTrait ∨
        (nodeProd (itemBody item) = pTypeAlias ∧ nodeProd (kid (itemBody item) 3) ≠ pWhereNone)) →
      ItemDecls home item noDecls

theorem implMethods_sound {fuel : Nat} {home : ModPath} {params : Option (List Name)} {selfType implTree list : CTree}
    {d : Decls} {t : CTree} (hps : typeParams fuel t = params)
    (h : implMethods fuel home params selfType implTree list = some d) :
    ∃ ps ms fs, typeParams fuel t = some ps ∧ TypeParams t ps ∧ Items list ms ∧
      ListRel (MethodDecl home ps selfType implTree) ms fs ∧ d = onlyFns fs := by
  simp only [implMethods] at h
  cases params with
  | none => cases h
  | some ps =>
    cases hi : listItems fuel list with
    | none => rw [hi] at h; cases h
    | some items =>
      rw [hi] at h
      simp only [fnsDecls] at h
      cases hm : methodsOf fuel home ps selfType implTree items with
      | none => rw [hm] at h; cases h
      | some fs =>
        rw [hm, Option.some.injEq] at h
        exact ⟨ps, items, fs, hps, typeParams_sound hps, listItems_sound hi, methodsOf_sound hm, h.symm⟩

theorem itemDecls_sound {fuel : Nat} {home : ModPath} {item : CTree} {d : Decls}
    (h : itemDecls fuel home item = some d) : ItemDecls home item d := by
  simp only [itemDecls] at h
  by_cases ty : nodeProd (itemBody item) = pStruct ∨ nodeProd (itemBody item) = pEnum
  · rw [if_pos (by simpa using ty)] at h
    simp only [typeDecls] at h
    cases ht : typeDecl fuel home (itemBody item) with
    | none => rw [ht] at h; cases h
    | some t =>
      rw [ht, Option.some.injEq] at h
      subst h
      exact .type ty (typeDecl_sound ht)
  rw [if_neg (by simpa using ty)] at h
  by_cases fn : nodeProd (itemBody item) = pFn
  · rw [if_pos fn] at h
    simp only [fnsDecls, consFnDecl, fnDeclOf] at h
    cases hp : typeParams fuel (kid (itemBody item) 2) with
    | none => rw [hp] at h; cases h
    | some ps =>
      rw [hp, Option.some.injEq] at h
      subst h
      exact .fn fn (typeParams_sound hp)
  rw [if_neg fn] at h
  by_cases cn : nodeProd (itemBody item) = pConst
  · rw [if_pos cn, Option.some.injEq] at h
    subst h
    exact .const cn
  rw [if_neg cn] at h
  by_cases ii : nodeProd (itemBody item) = pImplInherent
  · rw [if_pos (by simpa using ii)] at h
    obtain ⟨ps, ms, fs, -, tp, items, rel, rfl⟩ := implMethods_sound rfl h
    exact .implInherent ii tp items rel
  rw [if_neg (by simpa using ii)] at h
  by_cases it : nodeProd (itemBody item) = pImplTrait
  · rw [if_pos (by simpa using it)] at h
    simp only [withImpl] at h
    cases hp : typeParams fuel (kid (itemBody item) 1) with
    | none => rw [hp] at h; cases h
    | some ps =>
      rw [hp] at h
      simp only at h
      cases hm : implMethods fuel home (some ps) (kid (itemBody item) 4) (itemBody item) (kid (itemBody item) 7) with
      | none => rw [hm] at h; cases h
      | some d =>
        rw [hm, Option.some.injEq] at h
        subst h
        obtain ⟨ps', ms, fs, e, tp, items, rel, rfl⟩ := implMethods_sound hp hm
        rw [hp, Option.some.injEq] at e
        subst e
        exact .implTrait it tp items rel
  rw [if_neg (by simpa using it)] at h
  by_cases im : nodeProd (itemBody item) = pImport ∧ nodeProd (kid (itemBody item) 1) = pImportPath
  · rw [if_pos (by simpa using im)] at h
    simp only [importDecls] at h
    cases hp : pathSpellings fuel (kid (kid (kid (itemBody item) 1) 0) 0) (kid (kid (kid (itemBody item) 1) 0) 1) with
    | none => rw [hp] at h; cases h
    | some t =>
      rw [hp, Option.some.injEq] at h
      subst h
      exact .imports im.1 im.2 (pathSpellings_sound hp)
  rw [if_neg (by simpa using im)] at h
  by_cases al : nodeProd (itemBody item) = pTypeAlias ∧ nodeProd (kid (itemBody item) 3) = pWhereNone
  · rw [if_pos (by simpa using al)] at h
    simp only [aliasDecls] at h
    cases hp : freeParams fuel (kid (itemBody item) 2) with
    | none => rw [hp] at h; cases h
    | some ps =>
      rw [hp, Option.some.injEq] at h
      subst h
      exact .alias al.1 al.2 (freeParams_sound hp)
  rw [if_neg (by simpa using al)] at h
  by_cases ex : nodeProd (itemBody item) = pExternFn ∧ hostExtern (itemBody item) = true
  · rw [if_pos (by simpa using ex)] at h
    simp only [fnsDecls, consFnDecl, fnDeclOf] at h
    cases hp : typeParams fuel (kid (itemBody item) 4) with
    | none => rw [hp] at h; cases h
    | some ps =>
      rw [hp, Option.some.injEq] at h
      subst h
      exact .host ex.1 ex.2 (typeParams_sound hp)
  rw [if_neg (by simpa using ex)] at h
  by_cases md : nodeProd (itemBody item) = pModule
  · rw [if_pos md] at h
    simp only [moduleDecls] at h
    cases hp : pathSpellings fuel (kid (kid (itemBody item) 1) 0) (kid (kid (itemBody item) 1) 1) with
    | none => rw [hp] at h; cases h
    | some m =>
      rw [hp, Option.some.injEq] at h
      subst h
      exact .module md (pathSpellings_sound hp)
  rw [if_neg md] at h
  split at h
  · rename_i nd
    rw [Option.some.injEq] at h
    subst h
    refine .none ?_
    simp only [Bool.or_eq_true, decide_eq_true_eq] at nd
    simp only [not_and, Bool.not_eq_true] at im al ex
    rcases nd with ((i | e) | t) | a
    · exact .inl ⟨i, im i⟩
    · exact .inr (.inl ⟨e, ex e⟩)
    · exact .inr (.inr (.inl t))
    · exact .inr (.inr (.inr ⟨a, al a⟩))
  · cases h

/-! ## Files -/

/-- A file's module path: that of its first `module` item, or the empty
path when it has none. -/
inductive ModulePath : List CTree → ModPath → Prop
  | none : ModulePath [] []
  | here {item : CTree} {rest : List CTree} {m : ModPath} : nodeProd (itemBody item) = pModule →
      PathSpellings (kid (kid (itemBody item) 1) 0) (kid (kid (itemBody item) 1) 1) m → ModulePath (item :: rest) m
  | skip {item : CTree} {rest : List CTree} {m : ModPath} : nodeProd (itemBody item) ≠ pModule →
      ModulePath rest m → ModulePath (item :: rest) m

/-- The declarations of a list of items, in order. -/
inductive Collect (home : ModPath) : List CTree → Decls → Prop
  | nil : Collect home [] noDecls
  | cons {item : CTree} {rest : List CTree} {d e : Decls} : ItemDecls home item d → Collect home rest e →
      Collect home (item :: rest) (d.append e)

/-- A `file` tree's module path and declarations. -/
def FileDeclsR (root : CTree) (f : FileDecls) : Prop :=
  nodeProd root = pFile ∧ ∃ items, Items (kid root 0) items ∧ ModulePath items f.home ∧ Collect f.home items f.decls

/-- The declarations of several files, in file order, and their modules. -/
inductive CollectedR : List CTree → Collected → Prop
  | nil : CollectedR [] { decls := noDecls, modules := [] }
  | cons {root : CTree} {rest : List CTree} {f : FileDecls} {c : Collected} : FileDeclsR root f → CollectedR rest c →
      CollectedR (root :: rest) { decls := f.decls.append c.decls, modules := f.home :: c.modules }

theorem modulePath_sound : ∀ {fuel : Nat} {items : List CTree} {m : ModPath},
    modulePath fuel items = some m → ModulePath items m
  | _, [], m, h => by
    simp only [modulePath, Option.some.injEq] at h
    subst h
    exact .none
  | fuel, item :: rest, m, h => by
    simp only [modulePath] at h
    by_cases md : nodeProd (itemBody item) = pModule
    · rw [if_pos md] at h
      exact .here md (pathSpellings_sound h)
    · rw [if_neg md] at h
      exact .skip md (modulePath_sound h)

theorem append_assoc (a b c : Decls) : (a.append b).append c = a.append (b.append c) := by
  simp [Decls.append, List.append_assoc]

theorem noDecls_append (a : Decls) : noDecls.append a = a := by
  simp [Decls.append, noDecls]

theorem append_noDecls (a : Decls) : a.append noDecls = a := by
  simp [Decls.append, noDecls]

theorem joinDecls_some (a d : Decls) : joinDecls a (some d) = some (a.append d) := by rfl

theorem collect_sound : ∀ {fuel : Nat} {home : ModPath} {items : List CTree} {d : Decls},
    collect fuel home items = some d → Collect home items d
  | _, _, [], d, h => by
    simp only [collect, Option.some.injEq] at h
    subst h
    exact .nil
  | fuel, home, item :: rest, d, h => by
    simp only [collect] at h
    cases hi : itemDecls fuel home item with
    | none => rw [hi] at h; simp [collectFront] at h
    | some x =>
      rw [hi] at h
      simp only [collectFront] at h
      cases hr : collect fuel home rest with
      | none => rw [hr] at h; simp [joinDecls] at h
      | some e =>
        rw [hr, joinDecls_some, Option.some.injEq] at h
        subst h
        exact .cons (itemDecls_sound hi) (collect_sound hr)

theorem fileDecls_sound {fuel : Nat} {root : CTree} {f : FileDecls} (h : fileDecls fuel root = some f) :
    FileDeclsR root f := by
  simp only [fileDecls] at h
  by_cases r : nodeProd root = pFile
  · rw [if_pos r] at h
    cases hi : listItems fuel (kid root 0) with
    | none => rw [hi] at h; cases h
    | some items =>
      rw [hi] at h
      simp only [fileItems] at h
      cases hm : modulePath fuel items with
      | none => rw [hm] at h; cases h
      | some m =>
        rw [hm] at h
        simp only [fileCollected] at h
        cases hc : collect fuel m items with
        | none => rw [hc] at h; cases h
        | some d =>
          rw [hc, Option.some.injEq] at h
          subst h
          exact ⟨r, items, listItems_sound hi, modulePath_sound hm, collect_sound hc⟩
  · rw [if_neg r] at h
    cases h

theorem collectedWith_eq (c : Collected) (f : FileDecls) :
    collectedWith c f = { decls := c.decls.append f.decls, modules := c.modules ++ [f.home] } := by rfl

/-- `collectFiles` appends the files' declarations to what it has. -/
theorem collectFiles_sound : ∀ {fuel : Nat} {roots : List CTree} {acc c : Collected},
    collectFiles fuel roots acc = some c →
    ∃ r, CollectedR roots r ∧ c = { decls := acc.decls.append r.decls, modules := acc.modules ++ r.modules }
  | _, [], acc, c, h => by
    simp only [collectFiles, Option.some.injEq] at h
    subst h
    exact ⟨_, .nil, by simp [append_noDecls]⟩
  | fuel, root :: rest, acc, c, h => by
    simp only [collectFiles] at h
    cases hf : fileDecls fuel root with
    | none => rw [hf] at h; cases h
    | some f =>
      rw [hf] at h
      obtain ⟨r, cr, rfl⟩ := collectFiles_sound h
      refine ⟨_, .cons (fileDecls_sound hf) cr, ?_⟩
      simp [collectedWith_eq, append_assoc, List.append_assoc]

/-- The files' declarations, in file order: what `buildFiles` collects
before it reads anything else. -/
theorem collected_sound {fuel : Nat} {first : CTree} {rest : List CTree} {f : FileDecls} {c : Collected}
    (hf : fileDecls fuel first = some f)
    (hc : collectFiles fuel rest { decls := f.decls, modules := [f.home] } = some c) :
    CollectedR (first :: rest) c := by
  obtain ⟨r, cr, rfl⟩ := collectFiles_sound hc
  exact .cons (fileDecls_sound hf) cr

end Lanius.Mini.Reading
