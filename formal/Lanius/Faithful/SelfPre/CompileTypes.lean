module

public import Lanius.Faithful.SelfPre.TS
public import Lanius.Mini.Compiler.P.declareProgram
public import Lanius.Mini.Compiler.P.funcNeeds
public import Lanius.Mini.Compiler.P.structFields
public import Lanius.Mini.Compiler.P.enumVariants
public import Lanius.Mini.Compiler.P.withBudget
public import Lanius.Mini.Compiler.P.arrayCallSig
public import Lanius.Mini.Compiler.P.lowerBody
public import Lanius.Mini.Compiler.P.matchVariants
public import Lanius.Mini.Compiler.P.needCapped
public import Lanius.Faithful.SelfPre.Tactic
public import Lanius.Mini.Compiler.P.repeatType
public import Lanius.Mini.Compiler.P.UintTy_half
public import Lanius.Mini.Compiler.P.declareFuncs
public import Lanius.Mini.Compiler.P.shortCircuit
public import Lanius.Mini.Compiler.P.armBodyScope
import all Lanius.Mini.Compiler.P.SrcType_same
import all Lanius.Mini.Compiler.P.withBudget
import all Lanius.Mini.Compiler.P.arrayCallSig
import all Lanius.Mini.Compiler.P.enumVariants
import all Lanius.Mini.Compiler.P.funcNeeds
import all Lanius.Mini.Compiler.P.lowerBody
import all Lanius.Mini.Compiler.P.matchVariants
import all Lanius.Mini.Compiler.P.needCapped
import all Lanius.Mini.Compiler.P.structFields
import all Lanius.Mini.Compiler.P.repeatType
import all Lanius.Mini.Compiler.P.UintTy_half
import all Lanius.Mini.Compiler.P.declareFuncs
import all Lanius.Mini.Compiler.P.shortCircuit
import all Lanius.Mini.Compiler.P.declareProgram
import all Lanius.Mini.Compiler.P.armBodyScope

@[expose] public section

/-! # Type sizes of the compile side's declarations (F14)

`ts` (SelfPre/TS.lean) bounds the slot count of every type in a value, but a
declared struct (`SrcStructDecl`) keeps only its fields, whose `ts` is their
largest, not the struct's size (their sum). `tsd` measures the declarations by
the types they were declared from: a struct counts its fields' sizes and slots
(`tySlots` of the struct type), an enum `1 + maxSize` of its variants and their
slots. `declareProgram` declares only types of the program, so `tsd` of its
declarations is at most `ts` of the program (`vals_declareProgram`), which
`FrontEndTypeSlots` bounds by the weight limit.

The lookups' lemmas (`vals_F xs v h : .. ≤ ..` for `h : F xs = some v`, and
`val_F xs` for a lookup passed on whole) give the pre lemmas of the compile side
(`tools/pre_certs.py --compile`) the bounds of what they look up: a binding's
type from the scope, a struct's fields and an enum's variants from the
declarations, a signature from the signatures. A signature's parameters are a
function's (`sigs`), so their sizes add up to its `paramsSize`
(`PreCompileSourceV4`'s premise, `paramsMax`). -/

namespace Lanius.Faithful.SelfPre

open Lanius.Mini

@[simp] theorem ts_list_SrcType : ∀ l : List SrcType, ts l = tySlotsList l
  | [] => by simp only [ts_nil, tySlotsList]
  | t :: l => by simp only [ts_cons, ts_SrcType, ts_list_SrcType l, tySlotsList]

@[simp] theorem ts_list_list_SrcType : ∀ l : List (List SrcType), ts l = tySlotsVariants l
  | [] => by simp only [ts_nil, tySlotsVariants]
  | v :: l => by simp only [ts_cons, ts_list_SrcType, ts_list_list_SrcType l, tySlotsVariants]

theorem tySlotsList_append : ∀ a b : List SrcType,
    tySlotsList (a ++ b) = max (tySlotsList a) (tySlotsList b)
  | [], b => by simp only [List.nil_append, tySlotsList]; omega
  | t :: a, b => by simp only [List.cons_append, tySlotsList, tySlotsList_append a b]; omega

/-! The declarations' measure. -/

/-- The struct declarations' largest size or slot count. -/
def tsdStructs : List SrcStructDecl → Nat
  | [] => 0
  | d :: ds => max (max (sizes d.fields) (tySlotsList d.fields)) (tsdStructs ds)

/-- The enum declarations' largest size or slot count. -/
def tsdEnums : List SrcEnumDecl → Nat
  | [] => 0
  | d :: ds => max (max (1 + maxSize d.variants) (tySlotsVariants d.variants)) (tsdEnums ds)

/-- The largest size or slot count of the declared types and their fields. -/
def tsd (d : SrcDecls) : Nat := max (tsdStructs d.structs) (tsdEnums d.enums)

/-- `tsd` of a declaring's result (`0` when it failed). -/
def tsdOpt : Option SrcDecls → Nat
  | none => 0
  | some d => tsd d

theorem tsd_structs (d : SrcDecls) : tsdStructs d.structs ≤ tsd d := Nat.le_max_left _ _
theorem tsd_enums (d : SrcDecls) : tsdEnums d.enums ≤ tsd d := Nat.le_max_right _ _
theorem ts_le_tsd (d : SrcDecls) : ts d ≤ tsd d := by
  have hs : ∀ l : List SrcStructDecl, ts l ≤ tsdStructs l := by
    intro l; induction l with
    | nil => simp only [ts_nil, tsdStructs]; omega
    | cons s l ih =>
      simp only [ts_cons, tsdStructs]
      have : ts s = tySlotsList s.fields := by rw [← ts_list_SrcType]; rfl
      omega
  have he : ∀ l : List SrcEnumDecl, ts l ≤ tsdEnums l := by
    intro l; induction l with
    | nil => simp only [ts_nil, tsdEnums]; omega
    | cons s l ih =>
      simp only [ts_cons, tsdEnums]
      have : ts s = tySlotsVariants s.variants := by rw [← ts_list_list_SrcType]; rfl
      omega
  have := hs d.structs
  have := he d.enums
  show max (ts d.structs) (ts d.enums) ≤ _
  simp only [tsd]; omega

/-! The lookups. -/

theorem vals_structFields : ∀ (ds : List SrcStructDecl) (id : Nat) (fs : List SrcType),
    structFields ds id = some fs → sizes fs ≤ tsdStructs ds ∧ tySlotsList fs ≤ tsdStructs ds
  | [], id, fs, h => by simp only [structFields, reduceCtorEq] at h
  | d :: ds, id, fs, h => by
    have ih := vals_structFields ds id fs
    simp only [structFields] at h
    split at h
    · cases h; simp only [tsdStructs]; omega
    · have := ih h; simp only [tsdStructs]; omega

theorem vals_enumVariants : ∀ (ds : List SrcEnumDecl) (id : Nat) (vs : List (List SrcType)),
    enumVariants ds id = some vs → 1 + maxSize vs ≤ tsdEnums ds ∧ tySlotsVariants vs ≤ tsdEnums ds
  | [], id, vs, h => by simp only [enumVariants, reduceCtorEq] at h
  | d :: ds, id, vs, h => by
    have ih := vals_enumVariants ds id vs
    simp only [enumVariants] at h
    split at h
    · cases h; simp only [tsdEnums]; omega
    · have := ih h; simp only [tsdEnums]; omega

theorem vals_lookup : ∀ (scope : List Binding) (id : Nat) (b : Binding),
    lookup scope id = some b → ts b ≤ ts scope ∧ tySlots b.ty ≤ ts scope
  | [], id, b, h => by simp only [lookup, reduceCtorEq] at h
  | c :: scope, id, b, h => by
    have ih := vals_lookup scope id b
    simp only [lookup] at h
    have hc : ts c = tySlots c.ty := rfl
    have hb : ts b = tySlots b.ty := rfl
    split at h
    · cases h; simp only [ts_cons]; omega
    · have := ih h; simp only [ts_cons]; omega

theorem val_lookup (scope : List Binding) (id : Nat) : ts (lookup scope id) ≤ ts scope := by
  cases h : lookup scope id with
  | none => simp only [ts_none]; omega
  | some b => have := vals_lookup scope id b h; simp only [ts_some]; exact this.1

/-! Signatures: `sigs` gives each function's parameters' types and return type. -/

/-- The largest sum of a signature's parameters' sizes. -/
def sigsParams : List Sig → Nat
  | [] => 0
  | s :: l => max (sizes s.params) (sigsParams l)

/-- A found signature's parameters' sizes (`0` when none was found). -/
def sigParamsOpt : Option Sig → Nat
  | none => 0
  | some s => sizes s.params

theorem ts_paramTypes : ∀ ps : List SrcParam, tySlotsList (paramTypes ps) = ts ps
  | [] => by simp only [paramTypes, tySlotsList, ts_nil]
  | p :: ps => by
    have hp : ts p = tySlots p.ty := rfl
    simp only [paramTypes, tySlotsList, ts_cons, ts_paramTypes ps, hp]

theorem sizes_paramTypes : ∀ ps : List SrcParam, sizes (paramTypes ps) = paramsSize ps
  | [] => by simp only [paramTypes, sizes, paramsSize]
  | p :: ps => by simp only [paramTypes, sizes, paramsSize, sizes_paramTypes ps]

/-- The most slots any of the functions' parameters take (`PreCompileSourceV4`'s
premise bounds each by `2 ^ 40`). -/
def paramsMax : List SrcFunc → Nat
  | [] => 0
  | f :: fs => max (paramsSize f.params) (paramsMax fs)

theorem sigsWith_ts : ∀ (funcs : List SrcFunc) (needs : List Nat),
    ts (sigsWith funcs needs) ≤ ts funcs ∧ sigsParams (sigsWith funcs needs) ≤ paramsMax funcs
  | [], needs => by simp only [sigsWith, ts_nil, sigsParams, paramsMax]; omega
  | f :: fs, needs => by
    have ih := sigsWith_ts fs (restNeeds needs)
    have hf : ts f = max (ts f.params) (max (ts f.ret) (ts f.body)) := rfl
    simp only [sigsWith, ts_cons, ts_Sig_mk, sigsParams, paramsMax, ts_list_SrcType,
      ts_paramTypes, sizes_paramTypes, hf]
    omega

theorem val_sigs (funcs : List SrcFunc) :
    ts (sigs funcs) ≤ ts funcs ∧ sigsParams (sigs funcs) ≤ paramsMax funcs :=
  sigsWith_ts funcs (funcNeeds funcs)

theorem val_getElem_sigs : ∀ (l : List Sig) (i : Nat),
    ts l[i]? ≤ ts l ∧ sigParamsOpt l[i]? ≤ sigsParams l
  | [], i => by simp only [List.getElem?_nil, ts_none, sigParamsOpt]; omega
  | s :: l, 0 => by
    simp only [List.getElem?_cons_zero, ts_some, ts_cons, sigParamsOpt, sigsParams]; omega
  | s :: l, i + 1 => by
    have ih := val_getElem_sigs l i
    simp only [List.getElem?_cons_succ, ts_cons, sigsParams]; omega

theorem vals_getElem_sigs (l : List Sig) (i : Nat) (s : Sig) (h : l[i]? = some s) :
    ts s ≤ ts l ∧ sizes s.params ≤ sigsParams l := by
  have := val_getElem_sigs l i
  rw [h] at this
  simpa only [ts_some, sigParamsOpt] using this

/-! Declaring keeps `tsd` below the declared types' `ts`. -/

theorem tsd_bind (o : Option SrcDecls) (f : SrcDecls → Option SrcDecls) (a b : Nat)
    (ho : tsdOpt o ≤ a) (hf : ∀ d, tsdOpt (f d) ≤ max b (tsd d)) :
    tsdOpt (match (generalizing := false) o with | none => none | some d => f d) ≤ max a b := by
  cases o with
  | none => simp only [tsdOpt]; omega
  | some d =>
    have := hf d
    simp only [tsdOpt] at ho
    show tsdOpt (f d) ≤ _
    omega

theorem tsd_keepIf (agrees : Bool) (d : SrcDecls) : tsdOpt (keepIf agrees d) ≤ tsd d := by
  cases agrees <;> simp only [keepIf, tsdOpt, Bool.false_eq_true, if_false, if_true] <;> omega

theorem tsd_declareStruct (id : Nat) (fields : List SrcType) :
    ∀ o, tsdOpt (declareStruct id fields o) ≤ max (max (sizes fields) (tySlotsList fields)) (tsdOpt o)
  | none => by simp only [declareStruct, tsdOpt]; omega
  | some d => by
    simp only [declareStruct]
    split
    · simp only [tsdOpt, tsd, tsdStructs]; omega
    · rename_i other _
      have := tsd_keepIf (typesSame other fields) d; show _ ≤ max _ (tsd d); omega

theorem tsd_declareEnum (id : Nat) (variants : List (List SrcType)) :
    ∀ o, tsdOpt (declareEnum id variants o) ≤
      max (max (1 + maxSize variants) (tySlotsVariants variants)) (tsdOpt o)
  | none => by simp only [declareEnum, tsdOpt]; omega
  | some d => by
    simp only [declareEnum]
    split
    · simp only [tsdOpt, tsd, tsdEnums]; omega
    · rename_i other _
      have := tsd_keepIf (variantsSame other variants) d; show _ ≤ max _ (tsd d); omega

mutual
theorem tsd_declare : ∀ (t : SrcType) (d : SrcDecls), tsdOpt (SrcType.declare t d) ≤ max (tySlots t) (tsd d)
  | .i32, d => by simp only [SrcType.declare, tsdOpt]; omega
  | .bool, d => by simp only [SrcType.declare, tsdOpt]; omega
  | .uint k, d => by simp only [SrcType.declare, tsdOpt]; omega
  | .struct id fields, d => by
    have ih := tsd_declareTypes fields d
    have := tsd_declareStruct id fields (declareTypes fields d)
    simp only [SrcType.declare, tySlots, SrcType.size]; omega
  | .enum id variants, d => by
    have ih := tsd_declareVariants variants d
    have := tsd_declareEnum id variants (declareVariants variants d)
    simp only [SrcType.declare, tySlots, SrcType.size]; omega
  | .ptr, d => by simp only [SrcType.declare, tsdOpt]; omega
  | .slice element, d => by
    have ih := tsd_declare element d
    simp only [SrcType.declare, tySlots]; omega
  | .array element length, d => by
    have ih := tsd_declare element d
    simp only [SrcType.declare, tySlots]; omega
  | .unit, d => by simp only [SrcType.declare, tsdOpt]; omega
  | .isize, d => by simp only [SrcType.declare, tsdOpt]; omega
  | .char, d => by simp only [SrcType.declare, tsdOpt]; omega
  | .float ft, d => by simp only [SrcType.declare, tsdOpt]; omega
  | .sint k, d => by simp only [SrcType.declare, tsdOpt]; omega
  | .view length, d => by simp only [SrcType.declare, tsdOpt]; omega
  | .str, d => by simp only [SrcType.declare, tsdOpt]; omega
  | .ref referent, d => by simp only [SrcType.declare, tsdOpt]; omega
termination_by structural t => t
theorem tsd_declareTypes : ∀ (l : List SrcType) (d : SrcDecls),
    tsdOpt (declareTypes l d) ≤ max (tySlotsList l) (tsd d)
  | [], d => by simp only [declareTypes, tsdOpt]; omega
  | t :: l, d => by
    have ih := tsd_declare t d
    have ih' := fun d' => tsd_declareTypes l d'
    rw [declareTypes]
    refine Nat.le_trans (tsd_bind (SrcType.declare t d) (fun d' => declareTypes l d') _ _ ih ih') ?_
    simp only [tySlotsList]; omega
termination_by structural l => l
theorem tsd_declareVariants : ∀ (l : List (List SrcType)) (d : SrcDecls),
    tsdOpt (declareVariants l d) ≤ max (tySlotsVariants l) (tsd d)
  | [], d => by simp only [declareVariants, tsdOpt]; omega
  | v :: l, d => by
    have ih := tsd_declareTypes v d
    have ih' := fun d' => tsd_declareVariants l d'
    rw [declareVariants]
    refine Nat.le_trans (tsd_bind (declareTypes v d) (fun d' => declareVariants l d') _ _ ih ih') ?_
    simp only [tySlotsVariants]; omega
termination_by structural l => l
end

mutual
theorem tySlots_effTypes : ∀ e : SrcEff, tySlotsList (SrcEff.types e) ≤ ts e
  | .ePure e => by simp only [SrcEff.types, tySlotsList]; omega
  | .eCall callee args => by
    have := tySlots_effsTypes args
    simp only [SrcEff.types, ts_SrcEff_eCall]; omega
  | .eApply op l r => by
    have := tySlots_effTypes l
    have := tySlots_effTypes r
    simp only [SrcEff.types, ts_SrcEff_eApply, tySlotsList_append]; omega
  | .eNeg a => by
    have := tySlots_effTypes a
    simp only [SrcEff.types, ts_SrcEff_eNeg]; omega
  | .eNot a => by
    have := tySlots_effTypes a
    simp only [SrcEff.types, ts_SrcEff_eNot]; omega
  | .eCast ty a => by
    have := tySlots_effTypes a
    simp only [SrcEff.types, ts_SrcEff_eCast]; omega
  | .eIndex slice a => by
    have := tySlots_effTypes a
    simp only [SrcEff.types, ts_SrcEff_eIndex]; omega
  | .eStruct ty fields => by
    have := tySlots_effsTypes fields
    simp only [SrcEff.types, ts_SrcEff_eStruct, tySlotsList, ts_SrcType]; omega
  | .eVariant ty v payload => by
    have := tySlots_effsTypes payload
    simp only [SrcEff.types, ts_SrcEff_eVariant, tySlotsList, ts_SrcType]; omega
  | .eMatch sc ety ty binders values => by
    have := tySlots_effTypes sc
    have := tySlots_effsTypes values
    simp only [SrcEff.types, ts_SrcEff_eMatch, tySlotsList, tySlotsList_append, ts_SrcType]; omega
  | .eDivide op l r => by
    have := tySlots_effTypes l
    have := tySlots_effTypes r
    simp only [SrcEff.types, ts_SrcEff_eDivide, tySlotsList_append]; omega
  | .eStride slice => by simp only [SrcEff.types, tySlotsList]; omega
  | .arraySlice element array => by
    simp only [SrcEff.types, ts_SrcEff_arraySlice, tySlotsList, ts_SrcType]; omega
  | .eIf c ty t e => by
    have := tySlots_effTypes c
    have := tySlots_effTypes t
    have := tySlots_effTypes e
    simp only [SrcEff.types, ts_SrcEff_eIf, tySlotsList_append]; omega
  | .eLet id ty value rt body => by
    have := tySlots_effTypes value
    have := tySlots_effTypes body
    simp only [SrcEff.types, ts_SrcEff_eLet, tySlotsList, tySlotsList_append, ts_SrcType]; omega
  | .eLen slice => by simp only [SrcEff.types, tySlotsList]; omega
  | .eStr offset chars => by simp only [SrcEff.types, tySlotsList]; omega
  | .eBorrow ty place => by
    have := tySlots_effTypes place
    simp only [SrcEff.types, ts_SrcEff_eBorrow]; omega
  | .eDeref ty ref => by
    have := tySlots_effTypes ref
    simp only [SrcEff.types, ts_SrcEff_eDeref]; omega
  | .eField base field => by
    have := tySlots_effTypes base
    simp only [SrcEff.types, ts_SrcEff_eField]; omega
  | .eAt base index => by
    have := tySlots_effTypes base
    have := tySlots_effTypes index
    simp only [SrcEff.types, ts_SrcEff_eAt, tySlotsList_append]; omega
termination_by structural e => e
theorem tySlots_effsTypes : ∀ es : List SrcEff, tySlotsList (effsTypes es) ≤ ts es
  | [] => by simp only [effsTypes, tySlotsList]; omega
  | e :: es => by
    have := tySlots_effTypes e
    have := tySlots_effsTypes es
    simp only [effsTypes, ts_cons, tySlotsList_append]; omega
termination_by structural es => es
end

/-- A declaring step through `types` (bound `a`) and then `f`. -/
theorem tsd_bindTypes (types : List SrcType) (d : SrcDecls) (f : SrcDecls → Option SrcDecls) (b : Nat)
    (hf : ∀ d, tsdOpt (f d) ≤ max b (tsd d)) :
    tsdOpt (match (generalizing := false) declareTypes types d with | none => none | some d => f d) ≤
      max (max (tySlotsList types) (tsd d)) b :=
  tsd_bind _ f _ b (tsd_declareTypes types d) hf

theorem tsd_stmt (s : SrcStmt) : ∀ d, tsdOpt (SrcStmt.declare s d) ≤ max (ts s) (tsd d) := by
  induction s with
  | nop => intro d; simp only [SrcStmt.declare, tsdOpt]; omega
  | «let» id ty value body ih =>
    intro d; rw [SrcStmt.declare]
    refine Nat.le_trans (tsd_bind _ _ _ _ (tsd_declare ty d) ih) ?_
    simp only [ts_SrcStmt_let, ts_SrcType]; omega
  | letStruct id ty fields body ih =>
    intro d; rw [SrcStmt.declare]
    refine Nat.le_trans (tsd_bind _ _ _ _ (tsd_declare ty d) ih) ?_
    simp only [ts_SrcStmt_letStruct, ts_SrcType]; omega
  | letCall id ty callee args body ih =>
    intro d; rw [SrcStmt.declare]
    refine Nat.le_trans (tsd_bind _ _ _ _ (tsd_declare ty d) ih) ?_
    simp only [ts_SrcStmt_letCall, ts_SrcType]; omega
  | letEnum id ty variant payload body ih =>
    intro d; rw [SrcStmt.declare]
    refine Nat.le_trans (tsd_bind _ _ _ _ (tsd_declare ty d) ih) ?_
    simp only [ts_SrcStmt_letEnum, ts_SrcType]; omega
  | letMatch id ty scrutinee enumId arms body ih =>
    intro d; rw [SrcStmt.declare]
    refine Nat.le_trans (tsd_bind _ _ _ _ (tsd_declare ty d) ih) ?_
    simp only [ts_SrcStmt_letMatch, ts_SrcType]; omega
  | set id value => intro d; simp only [SrcStmt.declare, tsdOpt]; omega
  | setField id index value => intro d; simp only [SrcStmt.declare, tsdOpt]; omega
  | setCall id callee args => intro d; simp only [SrcStmt.declare, tsdOpt]; omega
  | «then» first second ih1 ih2 =>
    intro d; rw [SrcStmt.declare]
    refine Nat.le_trans (tsd_bind _ _ _ _ (ih1 d) ih2) ?_
    simp only [ts_SrcStmt_then]; omega
  | «if» condition thenBranch elseBranch ih1 ih2 =>
    intro d; rw [SrcStmt.declare]
    refine Nat.le_trans (tsd_bind _ _ _ _ (ih1 d) ih2) ?_
    simp only [ts_SrcStmt_if]; omega
  | «while» condition body ih =>
    intro d; have := ih d; simp only [SrcStmt.declare, ts_SrcStmt_while]; omega
  | «return» value => intro d; simp only [SrcStmt.declare, tsdOpt]; omega
  | letAlloc id size shift body ih =>
    intro d; have := ih d; simp only [SrcStmt.declare, ts_SrcStmt_letAlloc]; omega
  | letLoad id pointer offset body ih =>
    intro d; have := ih d; simp only [SrcStmt.declare, ts_SrcStmt_letLoad]; omega
  | setByte pointer offset value => intro d; simp only [SrcStmt.declare, tsdOpt]; omega
  | free pointer size shift => intro d; simp only [SrcStmt.declare, tsdOpt]; omega
  | letSlice id element pointer length body ih =>
    intro d; rw [SrcStmt.declare]
    refine Nat.le_trans (tsd_bind _ _ _ _ (tsd_declare element d) ih) ?_
    simp only [ts_SrcStmt_letSlice, ts_SrcType]; omega
  | letIndex id ty slice index body ih =>
    intro d; rw [SrcStmt.declare]
    refine Nat.le_trans (tsd_bind _ _ _ _ (tsd_declare ty d) ih) ?_
    simp only [ts_SrcStmt_letIndex, ts_SrcType]; omega
  | setIndex slice index value => intro d; simp only [SrcStmt.declare, tsdOpt]; omega
  | letEval id ty value body ih =>
    intro d; rw [SrcStmt.declare]
    have := tySlots_effTypes value
    refine Nat.le_trans (tsd_bindTypes _ d _ _ ih) ?_
    simp only [ts_SrcStmt_letEval, tySlotsList, ts_SrcType]; omega
  | setEval id value =>
    intro d; have := tySlots_effTypes value; have := tsd_declareTypes (SrcEff.types value) d
    simp only [SrcStmt.declare, ts_SrcStmt_setEval]; omega
  | ifEval condition thenBranch elseBranch ih1 ih2 =>
    intro d; rw [SrcStmt.declare]
    have := tySlots_effTypes condition
    refine Nat.le_trans (tsd_bind _ _ _ _ (tsd_bindTypes _ d _ _ ih1) ih2) ?_
    simp only [ts_SrcStmt_ifEval]; omega
  | whileEval condition body ih =>
    intro d; rw [SrcStmt.declare]
    have := tySlots_effTypes condition
    refine Nat.le_trans (tsd_bindTypes _ d _ _ ih) ?_
    simp only [ts_SrcStmt_whileEval]; omega
  | returnEval value =>
    intro d; have := tySlots_effTypes value; have := tsd_declareTypes (SrcEff.types value) d
    simp only [SrcStmt.declare, ts_SrcStmt_returnEval]; omega
  | discard value =>
    intro d; have := tySlots_effTypes value; have := tsd_declareTypes (SrcEff.types value) d
    simp only [SrcStmt.declare, ts_SrcStmt_discard]; omega
  | setIndexEval slice index value =>
    intro d; have := tySlots_effTypes index; have := tySlots_effTypes value
    have := tsd_declareTypes (SrcEff.types index ++ SrcEff.types value) d
    simp only [SrcStmt.declare, ts_SrcStmt_setIndexEval, tySlotsList_append] at *; omega
  | setFieldEval id field value =>
    intro d; have := tySlots_effTypes value; have := tsd_declareTypes (SrcEff.types value) d
    simp only [SrcStmt.declare, ts_SrcStmt_setFieldEval]; omega
  | returnUnit => intro d; simp only [SrcStmt.declare, tsdOpt]; omega
  | assert condition =>
    intro d; have := tySlots_effTypes condition; have := tsd_declareTypes (SrcEff.types condition) d
    simp only [SrcStmt.declare, ts_SrcStmt_assert]; omega
  | «break» => intro d; simp only [SrcStmt.declare, tsdOpt]; omega
  | «continue» => intro d; simp only [SrcStmt.declare, tsdOpt]; omega
  | matchArm scrutinee enumId variant binds binder ty body rest ih1 ih2 =>
    intro d; rw [SrcStmt.declare]
    refine Nat.le_trans (tsd_bind _ _ _ _ (tsd_bind _ _ _ _ (tsd_declare ty d) ih1) ih2) ?_
    simp only [ts_SrcStmt_matchArm, ts_SrcType]; omega
  | unreachable id ty =>
    intro d; have := tsd_declare ty d; simp only [SrcStmt.declare, ts_SrcStmt_unreachable, ts_SrcType]; omega
  | letView id length fields pointer body ih =>
    intro d; have := ih d; simp only [SrcStmt.declare, ts_SrcStmt_letView]; omega
  | letStr pointer chars body ih =>
    intro d; have := ih d; simp only [SrcStmt.declare, ts_SrcStmt_letStr]; omega
  | setPlace place value =>
    intro d; have := tySlots_effTypes place; have := tySlots_effTypes value
    have := tsd_declareTypes (SrcEff.types place ++ SrcEff.types value) d
    simp only [SrcStmt.declare, ts_SrcStmt_setPlace, tySlotsList_append] at *; omega
  | setPlaceOp op place value =>
    intro d; have := tySlots_effTypes place; have := tySlots_effTypes value
    have := tsd_declareTypes (SrcEff.types place ++ SrcEff.types value) d
    simp only [SrcStmt.declare, ts_SrcStmt_setPlaceOp, tySlotsList_append] at *; omega

theorem tsd_declareParams : ∀ (ps : List SrcParam) (d : SrcDecls),
    tsdOpt (declareParams ps d) ≤ max (ts ps) (tsd d)
  | [], d => by simp only [declareParams, tsdOpt, ts_nil]; omega
  | p :: ps, d => by
    have ih := fun d' => tsd_declareParams ps d'
    have hp : ts p = tySlots p.ty := rfl
    rw [declareParams]
    refine Nat.le_trans (tsd_bind _ _ _ _ (tsd_declare p.ty d) ih) ?_
    simp only [ts_cons, hp]; omega

theorem tsd_declareFunc (f : SrcFunc) (d : SrcDecls) : tsdOpt (declareFunc f d) ≤ max (ts f) (tsd d) := by
  have hf : ts f = max (ts f.params) (max (ts f.ret) (ts f.body)) := rfl
  have h1 := tsd_declareParams f.params d
  rw [declareFunc]
  cases h : declareParams f.params d with
  | none => simp only [tsdOpt]; omega
  | some w =>
    rw [h] at h1
    simp only [tsdOpt] at h1
    refine Nat.le_trans (tsd_bind _ _ _ _ (tsd_declare f.ret w) (tsd_stmt f.body)) ?_
    simp only [hf, ts_SrcType]; omega

theorem tsd_declareFuncs : ∀ (fs : List SrcFunc) (d : SrcDecls),
    tsdOpt (declareFuncs fs d) ≤ max (ts fs) (tsd d)
  | [], d => by simp only [declareFuncs, tsdOpt, ts_nil]; omega
  | f :: fs, d => by
    have ih := fun d' => tsd_declareFuncs fs d'
    rw [declareFuncs]
    refine Nat.le_trans (tsd_bind _ _ _ _ (tsd_declareFunc f d) ih) ?_
    simp only [ts_cons]; omega

/-- The program's declarations count no more than its types. -/
theorem val_declareProgram (p : SrcProgram) : tsdOpt (declareProgram p) ≤ ts p := by
  have := tsd_declareFuncs p.funcs { structs := [], enums := [], statics := p.statics }
  have hp : ts p = ts p.funcs := rfl
  simp only [declareProgram, tsd, tsdStructs, tsdEnums] at this ⊢
  omega

theorem vals_declareProgram (p : SrcProgram) (d : SrcDecls) (h : declareProgram p = some d) :
    tsd d ≤ ts p := by
  have := val_declareProgram p
  rw [h] at this
  exact this

/-! Types taken out of types: an element, a repeated element, an enum's variants, an index. -/

theorem vals_elementOf (t e : SrcType) (h : elementOf t = some e) : tySlots e ≤ tySlots t := by
  cases t <;> simp only [elementOf, reduceCtorEq, Option.some.injEq] at h
  subst h; simp only [tySlots]; omega

theorem val_elementOf (t : SrcType) : ts (elementOf t) ≤ tySlots t := by
  cases h : elementOf t with
  | none => simp only [ts_none]; omega
  | some e => have := vals_elementOf t e h; simp only [ts_some, ts_SrcType]; omega

theorem val_repeatType (t : SrcType) (n : Nat) :
    tySlotsList (repeatType t n) ≤ tySlots t ∧ sizes (repeatType t n) = n * SrcType.size t := by
  induction n with
  | zero => rw [repeatType]; simp only [if_true, tySlotsList, sizes]; omega
  | succ n ih =>
    rw [repeatType]
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel, tySlotsList, sizes]
    rw [Nat.succ_mul]; omega

theorem val_matchVariants (t : SrcType) :
    tySlotsVariants (matchVariants t) ≤ tySlots t ∧ maxSize (matchVariants t) ≤ tySlots t := by
  cases t <;> simp only [matchVariants, tySlotsVariants, maxSize, tySlots, SrcType.size] <;> omega

theorem vals_getElem_types : ∀ (l : List SrcType) (i : Nat) (v : SrcType), l[i]? = some v →
    tySlots v ≤ tySlotsList l ∧ SrcType.size v ≤ sizes l
  | [], i, v, h => by simp only [List.getElem?_nil, reduceCtorEq] at h
  | t :: l, 0, v, h => by
    simp only [List.getElem?_cons_zero, Option.some.injEq] at h
    subst h; simp only [tySlotsList, sizes]; omega
  | t :: l, i + 1, v, h => by
    simp only [List.getElem?_cons_succ] at h
    have := vals_getElem_types l i v h
    simp only [tySlotsList, sizes]; omega

theorem val_getElem_types (l : List SrcType) (i : Nat) : ts l[i]? ≤ tySlotsList l := by
  cases h : l[i]? with
  | none => simp only [ts_none]; omega
  | some v => have := vals_getElem_types l i v h; simp only [ts_some, ts_SrcType]; omega

theorem vals_getElem_variants : ∀ (l : List (List SrcType)) (i : Nat) (v : List SrcType), l[i]? = some v →
    tySlotsList v ≤ tySlotsVariants l ∧ sizes v ≤ maxSize l
  | [], i, v, h => by simp only [List.getElem?_nil, reduceCtorEq] at h
  | t :: l, 0, v, h => by
    simp only [List.getElem?_cons_zero, Option.some.injEq] at h
    subst h; simp only [tySlotsVariants, maxSize]; omega
  | t :: l, i + 1, v, h => by
    simp only [List.getElem?_cons_succ] at h
    have := vals_getElem_variants l i v h
    simp only [tySlotsVariants, maxSize]; omega

theorem val_getElem_variants (l : List (List SrcType)) (i : Nat) : ts l[i]? ≤ tySlotsVariants l := by
  cases h : l[i]? with
  | none => simp only [ts_none]; omega
  | some v => have := vals_getElem_variants l i v h; simp only [ts_some, ts_list_SrcType]; omega

/-- A function's budget in the signatures keeps their types. -/
theorem val_withBudget : ∀ (sigs : List Sig) (room block : Nat),
    ts (withBudget sigs room block) ≤ ts sigs ∧ sigsParams (withBudget sigs room block) ≤ sigsParams sigs
  | [], room, block => by simp only [withBudget, ts_nil, sigsParams]; omega
  | s :: l, room, block => by
    have ih := val_withBudget l room block
    have hs : ts s = max (ts s.params) (ts s.ret) := rfl
    simp only [withBudget, ts_cons, ts_Sig_mk, sigsParams, hs]; omega

/-- The parameters' scope binds their types. -/
theorem val_paramScope : ∀ (ps : List SrcParam) (slot : Nat) (scope : List Binding),
    ts (paramScope ps slot scope) ≤ max (ts ps) (ts scope)
  | [], slot, scope => by simp only [paramScope, ts_nil]; omega
  | p :: ps, slot, scope => by
    have ih := val_paramScope ps (slot + SrcType.size p.ty)
      ({ id := p.id, slot := slot, ty := p.ty, home := none } :: scope)
    have hp : ts p = tySlots p.ty := rfl
    simp only [paramScope, ts_cons, ts_Binding_mk, ts_SrcType, hp] at ih ⊢; omega

/-- An arm's body scope binds its payload's type. -/
theorem val_armBodyScope (binds : Bool) (binder : Nat) (ty : SrcType) (next : Nat) (scope : List Binding) :
    ts (armBodyScope binds binder ty next scope) ≤ max (ts ty) (ts scope) := by
  simp only [armBodyScope]
  split
  · omega
  · simp only [ts_cons, ts_Binding_mk]; omega

/-- A field's offset is at most its struct's size. -/
theorem val_fieldOffset : ∀ (l : List SrcType) (i : Nat), fieldOffset l i ≤ sizes l
  | [], i => by simp only [fieldOffset, sizes]; omega
  | t :: l, i => by
    have := val_fieldOffset l (i - 1)
    simp only [fieldOffset, sizes]; split <;> omega

/-- A type's size is at most its slot count (for `valueFacts`, on any `SrcType.size t`). -/
theorem val_SrcType_size (t : SrcType) : SrcType.size t ≤ tySlots t := size_le_tySlots t

end Lanius.Faithful.SelfPre
