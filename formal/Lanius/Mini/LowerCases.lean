module

public import Lanius.Mini.Compiler
-- import all uses: Lanius.Mini.Compiler
import all Lanius.Mini.Compiler.P.SrcExpr_guard
import all Lanius.Mini.Compiler.P.UintTy_half
import all Lanius.Mini.Compiler.P.armPayload
import all Lanius.Mini.Compiler.P.arrayCallSig
import all Lanius.Mini.Compiler.P.exprRoots
import all Lanius.Mini.Compiler.P.fitsThen
import all Lanius.Mini.Compiler.P.indexPlace
import all Lanius.Mini.Compiler.P.letCallPick
import all Lanius.Mini.Compiler.P.letPick
import all Lanius.Mini.Compiler.P.lowerSetCallArgs
import all Lanius.Mini.Compiler.P.matchVariants
import all Lanius.Mini.Compiler.P.setPick
import all Lanius.Mini.Compiler.P.wordStride
-- end import all uses

@[expose] public section

/-! The lowering, one statement constructor at a time (F5 P3).

Each `lower_X` says what `SrcStmt.lower` gives for constructor `X`, by its result: from
`(SrcStmt.X ..).lower sigs decls ret scope next = some out`, the shapes `out` can have, homed and
not. The proofs about the lowering start from these and never unfold `SrcStmt.lower`, so a change
to the lowering (S6c) changes this file and not theirs.

A branch that S6b lowers like another constructor (an eval twin: a pure part reading a homed local,
or an assignment to a homed local) is stated as that constructor's lowering. Its Core meaning is the
same (`SrcStmt.toCore`), so its proof is the other constructor's case.

`Guard.lean` has the older `letView_lower_inv`, `letStr_lower_inv`, `matchArm_lower_inv` and
`unreachable_lower_inv`, which give the emitted code of those cases in full. -/

namespace Lanius.Mini

variable {sigs : List Sig} {decls : SrcDecls} {ret : SrcType} {scope : List Binding} {next : Nat}
  {out : Stmt}

/-! ### Helpers -/

/-- The code after a declaration's value: the body, after the home's first store when the
declaration has a home (`homeStoreThen`). -/
def declTail (frame : Nat) (home : Option Nat) (ty : SrcType) (slot : Nat) (b : Stmt) : Stmt :=
  match home with
  | none => b
  | some offset => .seq (.assign (slot + ty.size) (layAddOff frame offset))
      (.seq (storeSlots (homeInit ty) (slot + ty.size) slot) b)

@[simp] theorem declTail_none {frame : Nat} {ty : SrcType} {slot : Nat} {b : Stmt} :
    declTail frame none ty slot b = b := by
  simp only [declTail]

theorem homeStoreThen_some_eq {frame : Nat} {home : Option Nat} {ty : SrcType} {slot : Nat} {b : Stmt} :
    homeStoreThen frame home ty slot (some b) = some (declTail frame home ty slot b) := by
  cases home <;> rfl

theorem homeStoreThen_none_eq {frame : Nat} {home : Option Nat} {ty : SrcType} {slot : Nat} :
    homeStoreThen frame home ty slot none = none := by
  simp only [homeStoreThen]

theorem fitsThen_some {ok : Bool} {s : Option Stmt} (h : fitsThen ok s = some out) :
    ok = true ∧ s = some out := by
  cases ok with
  | false => simp [fitsThen] at h
  | true => exact ⟨rfl, h⟩

theorem fitsThen_true {s : Option Stmt} : fitsThen true s = s := by
  simp only [fitsThen, ↓reduceIte]

/-- `unhomedThen`, lowered: the declaration has no home. -/
theorem unhomedThen_some' {home : Option Nat} {s : Option Stmt}
    (h : unhomedThen home s = some out) : home = none ∧ s = some out := by
  cases home with
  | none => exact ⟨rfl, h⟩
  | some _ => simp [unhomedThen] at h

/-- `lookupSlot` is `lookup` on an unhomed binding. -/
theorem lookupSlot_unhomed {id : Nat} (h : isHomed (lookup scope id) = false) :
    lookupSlot scope id = lookup scope id := by
  simp only [lookupSlot, unhomed]
  cases hl : lookup scope id with
  | none => rfl
  | some b =>
    rw [hl] at h
    cases hb : b.home with
    | none => simp [hb]
    | some _ => simp [isHomed, hb] at h

/-- `lookupSlot` is `none` on a homed binding. -/
theorem lookupSlot_homed {id : Nat} (h : isHomed (lookup scope id) = true) :
    lookupSlot scope id = none := by
  simp only [lookupSlot, unhomed]
  cases hl : lookup scope id with
  | none => rfl
  | some b =>
    rw [hl] at h
    cases hb : b.home with
    | none => simp [isHomed, hb] at h
    | some _ => simp [hb]

theorem effsSlice_pures (es : List SrcExpr) : effsSlice (pures es) = false := by
  induction es with
  | nil => rfl
  | cons e rest ih => simp [pures, effsSlice, SrcEff.isSlice, ih]

theorem stmtEval_eq_of {value : SrcEff} (h : value.passesSlices = false) :
    stmtEval value sigs decls scope next = value.eval sigs decls scope next := by
  simp [stmtEval, h]

theorem letPick_none {reads : Bool} {slot : Nat} {g : Expr} {values : Option (List Expr)} {ty : SrcType}
    {twin : Option Evaluated} : letPick reads slot g values ty twin none = none := by
  cases reads <;> cases values <;> cases twin <;> rfl

theorem letCallPick_none {reads : Bool} {slot : Nat} {g : Expr} {count callee : Nat}
    {args : Option (List Expr)} {ty : SrcType} {twin : Option Evaluated} :
    letCallPick reads slot g count callee args ty twin none = none := by
  cases reads <;> cases args <;> cases twin <;> rfl

theorem lowerThen_none {first : Option Stmt} : lowerThen first none = none := by
  cases first <;> rfl

theorem lowerLetEval_none {ty : SrcType} {value : Option Evaluated} :
    lowerLetEval ty value none = none := by
  cases value <;> rfl

/-! ### Declarations with a home -/

/-- `let id: ty = value; body`: the value's code (or, when it reads a homed local, `letEval`'s). -/
theorem lower_let {id : Nat} {ty : SrcType} {value : SrcExpr} {body : SrcStmt}
    (ok : (SrcStmt.let id ty value body).lower sigs decls ret scope next = some out) :
    homeFits (homeFor body.sliceUses scope id) ty (ownBlock sigs) = true ∧ ∃ b,
      body.lower sigs decls ret (⟨id, next, ty, homeFor body.sliceUses scope id⟩ :: scope) (next + ty.size) =
        some b ∧
      ((readsHome scope value = false ∧
          guarded next (value.guard scope) (lowerLet next (lowerValue scope value ty)
            (some (declTail (ownFrame sigs) (homeFor body.sliceUses scope id) ty next b))) = some out) ∨
       (readsHome scope value = true ∧
          (SrcStmt.letEval id ty (.ePure value) body).lower sigs decls ret scope next = some out)) := by
  simp only [SrcStmt.lower] at ok
  obtain ⟨fits, ok⟩ := fitsThen_some ok
  refine ⟨fits, ?_⟩
  cases hb : SrcStmt.lower body sigs decls ret
      (⟨id, next, ty, homeFor body.sliceUses scope id⟩ :: scope) (next + ty.size) with
  | none => rw [hb, homeStoreThen_none_eq, letPick_none] at ok; cases ok
  | some b =>
    rw [hb, homeStoreThen_some_eq] at ok
    refine ⟨b, rfl, ?_⟩
    cases reads : readsHome scope value
    · simp only [letPick, reads, Bool.false_eq_true, ↓reduceIte] at ok
      exact .inl ⟨rfl, ok⟩
    · simp only [letPick, reads, ↓reduceIte] at ok
      refine .inr ⟨rfl, ?_⟩
      simp only [SrcStmt.lower, fits, fitsThen_true, hb, homeStoreThen_some_eq,
        stmtEval_eq_of (rfl : (SrcEff.ePure value).passesSlices = false), SrcEff.eval]
      exact ok

/-- `let id: ty = T { fields }; body`. -/
theorem lower_letStruct {id : Nat} {ty : SrcType} {fields : List SrcExpr} {body : SrcStmt}
    (ok : (SrcStmt.letStruct id ty fields body).lower sigs decls ret scope next = some out) :
    homeFits (homeFor body.sliceUses scope id) ty (ownBlock sigs) = true ∧ ∃ b,
      body.lower sigs decls ret (⟨id, next, ty, homeFor body.sliceUses scope id⟩ :: scope) (next + ty.size) =
        some b ∧
      ((readsHomes scope fields = false ∧
          guarded next (guardAll scope fields) (lowerLet next (lowerLiteral scope ty fields)
            (some (declTail (ownFrame sigs) (homeFor body.sliceUses scope id) ty next b))) = some out) ∨
       (readsHomes scope fields = true ∧
          (SrcStmt.letEval id ty (.eStruct ty (pures fields)) body).lower sigs decls ret scope next =
            some out)) := by
  simp only [SrcStmt.lower] at ok
  obtain ⟨fits, ok⟩ := fitsThen_some ok
  refine ⟨fits, ?_⟩
  cases hb : SrcStmt.lower body sigs decls ret
      (⟨id, next, ty, homeFor body.sliceUses scope id⟩ :: scope) (next + ty.size) with
  | none => rw [hb, homeStoreThen_none_eq, letPick_none] at ok; cases ok
  | some b =>
    rw [hb, homeStoreThen_some_eq] at ok
    refine ⟨b, rfl, ?_⟩
    cases reads : readsHomes scope fields
    · simp only [letPick, reads, Bool.false_eq_true, ↓reduceIte] at ok
      exact .inl ⟨rfl, ok⟩
    · simp only [letPick, reads, ↓reduceIte] at ok
      refine .inr ⟨rfl, ?_⟩
      simp only [SrcStmt.lower, fits, fitsThen_true, hb, homeStoreThen_some_eq,
        stmtEval_eq_of (rfl : (SrcEff.eStruct ty (pures fields)).passesSlices = false)]
      exact ok

/-- `let id: ty = callee(args); body`. -/
theorem lower_letCall {id : Nat} {ty : SrcType} {callee : Nat} {args : List SrcExpr} {body : SrcStmt}
    (ok : (SrcStmt.letCall id ty callee args body).lower sigs decls ret scope next = some out) :
    homeFits (homeFor body.sliceUses scope id) ty (ownBlock sigs) = true ∧ ∃ b,
      body.lower sigs decls ret (⟨id, next, ty, homeFor body.sliceUses scope id⟩ :: scope) (next + ty.size) =
        some b ∧
      ((readsHomes scope args = false ∧
          guarded next (guardAll scope args) (lowerLetCall next ty.size callee (lowerCall sigs scope callee args ty)
            (some (declTail (ownFrame sigs) (homeFor body.sliceUses scope id) ty next b))) = some out) ∨
       (readsHomes scope args = true ∧
          (SrcStmt.letEval id ty (.eCall callee (pures args)) body).lower sigs decls ret scope next =
            some out)) := by
  simp only [SrcStmt.lower] at ok
  obtain ⟨fits, ok⟩ := fitsThen_some ok
  refine ⟨fits, ?_⟩
  cases hb : SrcStmt.lower body sigs decls ret
      (⟨id, next, ty, homeFor body.sliceUses scope id⟩ :: scope) (next + ty.size) with
  | none => rw [hb, homeStoreThen_none_eq, letCallPick_none] at ok; cases ok
  | some b =>
    rw [hb, homeStoreThen_some_eq] at ok
    refine ⟨b, rfl, ?_⟩
    cases reads : readsHomes scope args
    · simp only [letCallPick, reads, Bool.false_eq_true, ↓reduceIte] at ok
      exact .inl ⟨rfl, ok⟩
    · simp only [letCallPick, reads, ↓reduceIte] at ok
      refine .inr ⟨rfl, ?_⟩
      have np : (SrcEff.eCall callee (pures args)).passesSlices = false := by
        simp [SrcEff.passesSlices, effsSlice_pures]
      simp only [SrcStmt.lower, fits, fitsThen_true, hb, homeStoreThen_some_eq, stmtEval_eq_of np]
      exact ok

/-- `let id: ty = Enum::variant(payload); body`. -/
theorem lower_letEnum {id : Nat} {ty : SrcType} {variant : Nat} {payload : List SrcExpr} {body : SrcStmt}
    (ok : (SrcStmt.letEnum id ty variant payload body).lower sigs decls ret scope next = some out) :
    homeFits (homeFor body.sliceUses scope id) ty (ownBlock sigs) = true ∧ ∃ b,
      body.lower sigs decls ret (⟨id, next, ty, homeFor body.sliceUses scope id⟩ :: scope) (next + ty.size) =
        some b ∧
      ((readsHomes scope payload = false ∧
          guarded next (guardAll scope payload) (lowerLet next (lowerEnumValue scope ty variant payload)
            (some (declTail (ownFrame sigs) (homeFor body.sliceUses scope id) ty next b))) = some out) ∨
       (readsHomes scope payload = true ∧
          (SrcStmt.letEval id ty (.eVariant ty variant (pures payload)) body).lower sigs decls ret scope next =
            some out)) := by
  simp only [SrcStmt.lower] at ok
  obtain ⟨fits, ok⟩ := fitsThen_some ok
  refine ⟨fits, ?_⟩
  cases hb : SrcStmt.lower body sigs decls ret
      (⟨id, next, ty, homeFor body.sliceUses scope id⟩ :: scope) (next + ty.size) with
  | none => rw [hb, homeStoreThen_none_eq, letPick_none] at ok; cases ok
  | some b =>
    rw [hb, homeStoreThen_some_eq] at ok
    refine ⟨b, rfl, ?_⟩
    cases reads : readsHomes scope payload
    · simp only [letPick, reads, Bool.false_eq_true, ↓reduceIte] at ok
      exact .inl ⟨rfl, ok⟩
    · simp only [letPick, reads, ↓reduceIte] at ok
      refine .inr ⟨rfl, ?_⟩
      simp only [SrcStmt.lower, fits, fitsThen_true, hb, homeStoreThen_some_eq,
        stmtEval_eq_of (rfl : (SrcEff.eVariant ty variant (pures payload)).passesSlices = false)]
      exact ok

/-- `let id: ty = match scrutinee { arms }; body`: the scrutinee is unhomed. -/
theorem lower_letMatch {id : Nat} {ty : SrcType} {scrutinee enumId : Nat} {arms : List SrcArm}
    {body : SrcStmt}
    (ok : (SrcStmt.letMatch id ty scrutinee enumId arms body).lower sigs decls ret scope next = some out) :
    homeFits (homeFor body.sliceUses scope id) ty (ownBlock sigs) = true ∧ ∃ b,
      body.lower sigs decls ret (⟨id, next, ty, homeFor body.sliceUses scope id⟩ :: scope) (next + ty.size) =
        some b ∧
      isHomed (lookup scope scrutinee) = false ∧
      lowerThen (lowerMatch scope (lookup scope scrutinee) enumId arms ty next)
        (some (declTail (ownFrame sigs) (homeFor body.sliceUses scope id) ty next b)) = some out := by
  simp only [SrcStmt.lower] at ok
  obtain ⟨fits, ok⟩ := fitsThen_some ok
  refine ⟨fits, ?_⟩
  cases hb : SrcStmt.lower body sigs decls ret
      (⟨id, next, ty, homeFor body.sliceUses scope id⟩ :: scope) (next + ty.size) with
  | none => rw [hb, homeStoreThen_none_eq, lowerThen_none] at ok; cases ok
  | some b =>
    rw [hb, homeStoreThen_some_eq] at ok
    refine ⟨b, rfl, ?_⟩
    cases hh : isHomed (lookup scope scrutinee)
    · rw [lookupSlot_unhomed hh] at ok
      exact ⟨rfl, ok⟩
    · rw [lookupSlot_homed hh] at ok
      simp [lowerMatch, lowerThen] at ok

/-- `let id: ty = value; body` for a value with effects. -/
theorem lower_letEval {id : Nat} {ty : SrcType} {value : SrcEff} {body : SrcStmt}
    (ok : (SrcStmt.letEval id ty value body).lower sigs decls ret scope next = some out) :
    homeFits (homeFor body.sliceUses scope id) ty (ownBlock sigs) = true ∧ ∃ b,
      body.lower sigs decls ret (⟨id, next, ty, homeFor body.sliceUses scope id⟩ :: scope) (next + ty.size) =
        some b ∧
      lowerLetEval ty (stmtEval value sigs decls scope next)
        (some (declTail (ownFrame sigs) (homeFor body.sliceUses scope id) ty next b)) = some out := by
  simp only [SrcStmt.lower] at ok
  obtain ⟨fits, ok⟩ := fitsThen_some ok
  refine ⟨fits, ?_⟩
  cases hb : SrcStmt.lower body sigs decls ret
      (⟨id, next, ty, homeFor body.sliceUses scope id⟩ :: scope) (next + ty.size) with
  | none => rw [hb, homeStoreThen_none_eq, lowerLetEval_none] at ok; cases ok
  | some b =>
    rw [hb, homeStoreThen_some_eq] at ok
    exact ⟨b, rfl, ok⟩

/-! ### Declarations without a home -/

theorem lower_letAlloc {id : Nat} {size : SrcExpr} {shift : Nat} {body : SrcStmt}
    (ok : (SrcStmt.letAlloc id size shift body).lower sigs decls ret scope next = some out) :
    homeFor body.sliceUses scope id = none ∧
      guarded next (size.guard scope) (lowerAlloc next shift (lowerAs scope size (.uint .usize))
        (body.lower sigs decls ret (⟨id, next, .ptr, none⟩ :: scope) (next + 1))) = some out := by
  simp only [SrcStmt.lower] at ok
  exact unhomedThen_some' ok

theorem lower_letLoad {id : Nat} {pointer offset : SrcExpr} {body : SrcStmt}
    (ok : (SrcStmt.letLoad id pointer offset body).lower sigs decls ret scope next = some out) :
    homeFor body.sliceUses scope id = none ∧
      guarded next (guardAnd (pointer.guard scope) (offset.guard scope))
        (lowerLoad next (lowerAddress (lowerAs scope pointer .ptr) (lowerAs scope offset (.uint .usize)))
          (body.lower sigs decls ret (⟨id, next, .uint .uint8, none⟩ :: scope) (next + 1))) = some out := by
  simp only [SrcStmt.lower] at ok
  exact unhomedThen_some' ok

theorem lower_letSlice {id : Nat} {element : SrcType} {pointer length : SrcExpr} {body : SrcStmt}
    (ok : (SrcStmt.letSlice id element pointer length body).lower sigs decls ret scope next = some out) :
    homeFor body.sliceUses scope id = none ∧
      guarded next (guardAnd (pointer.guard scope) (length.guard scope))
        (lowerLet next (lowerSlice decls element (lowerAs scope pointer .ptr) (lowerAs scope length .i32))
          (body.lower sigs decls ret (⟨id, next, .slice element, none⟩ :: scope) (next + 2))) = some out := by
  simp only [SrcStmt.lower] at ok
  exact unhomedThen_some' ok

/-- `let id: ty = slice[index]; body`: on a homed array, `letEval`'s place load. -/
theorem lower_letIndex {id : Nat} {ty : SrcType} {slice : Nat} {index : SrcExpr} {body : SrcStmt}
    (ok : (SrcStmt.letIndex id ty slice index body).lower sigs decls ret scope next = some out) :
    homeFor body.sliceUses scope id = none ∧
      ((isHomed (lookup scope slice) = false ∧
          lowerLetIndexAny decls scope next ty slice index
            (body.lower sigs decls ret (⟨id, next, ty, none⟩ :: scope) (next + ty.size)) = some out) ∨
       (isHomed (lookup scope slice) = true ∧
          (SrcStmt.letEval id ty (.eAt (.ePure (.local slice)) (.ePure index)) body).lower sigs decls ret scope
            next = some out)) := by
  simp only [SrcStmt.lower] at ok
  obtain ⟨none_, ok⟩ := unhomedThen_some' ok
  refine ⟨none_, ?_⟩
  cases hh : isHomed (lookup scope slice)
  · simp only [letIndexPick, hh, Bool.false_eq_true, ↓reduceIte] at ok
    exact .inl ⟨rfl, ok⟩
  · simp only [letIndexPick, hh, ↓reduceIte] at ok
    refine .inr ⟨rfl, ?_⟩
    simp only [SrcStmt.lower, none_, homeFits, fitsThen_true,
      stmtEval_eq_of (rfl : (SrcEff.eAt (.ePure (.local slice)) (.ePure index)).passesSlices = false),
      SrcEff.eval]
    cases hb : SrcStmt.lower body sigs decls ret (⟨id, next, ty, none⟩ :: scope) (next + ty.size) with
    | none => rw [hb, lowerLetEval_none] at ok; cases ok
    | some b => rw [hb] at ok; rw [homeStoreThen_some_eq]; exact ok

theorem lower_letView {id length : Nat} {fields : List SrcExpr} {pointer : Nat} {body : SrcStmt}
    (ok : (SrcStmt.letView id length fields pointer body).lower sigs decls ret scope next = some out) :
    homeFor body.sliceUses scope id = none ∧
      guarded next (guardAll scope fields)
        (lowerView next length (lowerLiteral scope (.array .i32 length) fields)
          (body.lower sigs decls ret (⟨pointer, next + length, .ptr, none⟩ :: ⟨id, next, .view length, none⟩ :: scope)
            (next + length + 1))) = some out := by
  simp only [SrcStmt.lower] at ok
  exact unhomedThen_some' ok

theorem lower_letStr {pointer : Nat} {chars : List Nat} {body : SrcStmt}
    (ok : (SrcStmt.letStr pointer chars body).lower sigs decls ret scope next = some out) :
    homeFor body.sliceUses scope pointer = none ∧
      lowerStr next chars (body.lower sigs decls ret (⟨pointer, next, .ptr, none⟩ :: scope) (next + 1)) =
        some out := by
  simp only [SrcStmt.lower] at ok
  exact unhomedThen_some' ok

/-! ### Assignments -/

/-- `id = value`: to a homed local, `setPlace`'s store; reading a homed local, `setEval`'s. -/
theorem lower_set {id : Nat} {value : SrcExpr}
    (ok : (SrcStmt.set id value).lower sigs decls ret scope next = some out) :
    (isHomed (lookup scope id) = true ∧
        (SrcStmt.setPlace (.ePure (.local id)) (.ePure value)).lower sigs decls ret scope next = some out) ∨
    (isHomed (lookup scope id) = false ∧ readsHome scope value = true ∧
        (SrcStmt.setEval id (.ePure value)).lower sigs decls ret scope next = some out) ∨
    (isHomed (lookup scope id) = false ∧ readsHome scope value = false ∧
        guarded next (value.guard scope) (lowerSet (lookup scope id) scope value) = some out) := by
  simp only [SrcStmt.lower] at ok
  cases hh : isHomed (lookup scope id)
  · simp only [setPick, hh, Bool.false_eq_true, ↓reduceIte] at ok
    cases reads : readsHome scope value
    · simp only [stmtPick, reads, Bool.false_eq_true, ↓reduceIte, lookupSlot_unhomed hh] at ok
      exact .inr (.inr ⟨rfl, rfl, ok⟩)
    · simp only [stmtPick, reads, ↓reduceIte] at ok
      refine .inr (.inl ⟨rfl, rfl, ?_⟩)
      simp only [SrcStmt.lower, setPick, hh, Bool.false_eq_true, ↓reduceIte, SrcEff.eval]
      exact ok
  · simp only [setPick, hh, ↓reduceIte] at ok
    refine .inl ⟨rfl, ?_⟩
    simp only [SrcStmt.lower, SrcEff.eval]
    exact ok

/-- `id.index = value`. -/
theorem lower_setField {id index : Nat} {value : SrcExpr}
    (ok : (SrcStmt.setField id index value).lower sigs decls ret scope next = some out) :
    (isHomed (lookup scope id) = true ∧
        (SrcStmt.setPlace (.eField (.ePure (.local id)) index) (.ePure value)).lower sigs decls ret scope next =
          some out) ∨
    (isHomed (lookup scope id) = false ∧ readsHome scope value = true ∧
        (SrcStmt.setFieldEval id index (.ePure value)).lower sigs decls ret scope next = some out) ∨
    (isHomed (lookup scope id) = false ∧ readsHome scope value = false ∧
        guarded next (value.guard scope) (lowerSetField (lookup scope id) index scope value) = some out) := by
  simp only [SrcStmt.lower] at ok
  cases hh : isHomed (lookup scope id)
  · simp only [setPick, hh, Bool.false_eq_true, ↓reduceIte] at ok
    cases reads : readsHome scope value
    · simp only [stmtPick, reads, Bool.false_eq_true, ↓reduceIte, lookupSlot_unhomed hh] at ok
      exact .inr (.inr ⟨rfl, rfl, ok⟩)
    · simp only [stmtPick, reads, ↓reduceIte] at ok
      refine .inr (.inl ⟨rfl, rfl, ?_⟩)
      simp only [SrcStmt.lower, setPick, hh, Bool.false_eq_true, ↓reduceIte, SrcEff.eval]
      exact ok
  · simp only [setPick, hh, ↓reduceIte] at ok
    refine .inl ⟨rfl, ?_⟩
    simp only [SrcStmt.lower, SrcEff.eval]
    exact ok

/-- `id = callee(args)`. -/
theorem lower_setCall {id callee : Nat} {args : List SrcExpr}
    (ok : (SrcStmt.setCall id callee args).lower sigs decls ret scope next = some out) :
    (isHomed (lookup scope id) = true ∧
        (SrcStmt.setPlace (.ePure (.local id)) (.eCall callee (pures args))).lower sigs decls ret scope next =
          some out) ∨
    (isHomed (lookup scope id) = false ∧ readsHomes scope args = true ∧
        (SrcStmt.setEval id (.eCall callee (pures args))).lower sigs decls ret scope next = some out) ∨
    (isHomed (lookup scope id) = false ∧ readsHomes scope args = false ∧
        guarded next (guardAll scope args) (lowerSetCall sigs scope (lookup scope id) callee args) =
          some out) := by
  simp only [SrcStmt.lower] at ok
  cases hh : isHomed (lookup scope id)
  · simp only [setPick, hh, Bool.false_eq_true, ↓reduceIte] at ok
    cases reads : readsHomes scope args
    · simp only [stmtPick, reads, Bool.false_eq_true, ↓reduceIte, lookupSlot_unhomed hh] at ok
      exact .inr (.inr ⟨rfl, rfl, ok⟩)
    · simp only [stmtPick, reads, ↓reduceIte] at ok
      refine .inr (.inl ⟨rfl, rfl, ?_⟩)
      simp only [SrcStmt.lower, setPick, hh, Bool.false_eq_true, ↓reduceIte]
      exact ok
  · simp only [setPick, hh, ↓reduceIte] at ok
    refine .inl ⟨rfl, ?_⟩
    simp only [SrcStmt.lower]
    exact ok

/-- `slice[index] = value`: on a homed array, `setPlace`'s store. -/
theorem lower_setIndex {slice : Nat} {index value : SrcExpr}
    (ok : (SrcStmt.setIndex slice index value).lower sigs decls ret scope next = some out) :
    (isHomed (lookup scope slice) = true ∧
        (SrcStmt.setPlace (.eAt (.ePure (.local slice)) (.ePure index)) (.ePure value)).lower sigs decls ret
          scope next = some out) ∨
    (isHomed (lookup scope slice) = false ∧ lowerSetIndexAny decls scope next slice index value = some out) := by
  simp only [SrcStmt.lower] at ok
  cases hh : isHomed (lookup scope slice)
  · simp only [setPick, hh, Bool.false_eq_true, ↓reduceIte] at ok
    exact .inr ⟨rfl, ok⟩
  · simp only [setPick, hh, ↓reduceIte] at ok
    refine .inl ⟨rfl, ?_⟩
    simp only [SrcStmt.lower, SrcEff.eval]
    exact ok

/-- `id = value` for a value with effects. -/
theorem lower_setEval {id : Nat} {value : SrcEff}
    (ok : (SrcStmt.setEval id value).lower sigs decls ret scope next = some out) :
    (isHomed (lookup scope id) = true ∧
        (SrcStmt.setPlace (.ePure (.local id)) value).lower sigs decls ret scope next = some out) ∨
    (isHomed (lookup scope id) = false ∧
        lowerSetEval next (lookup scope id) (value.eval sigs decls scope next) = some out) := by
  simp only [SrcStmt.lower] at ok
  cases hh : isHomed (lookup scope id)
  · simp only [setPick, hh, Bool.false_eq_true, ↓reduceIte, lookupSlot_unhomed hh] at ok
    exact .inr ⟨rfl, ok⟩
  · simp only [setPick, hh, ↓reduceIte] at ok
    refine .inl ⟨rfl, ?_⟩
    simp only [SrcStmt.lower]
    exact ok

/-- `slice[index] = value` with effects. -/
theorem lower_setIndexEval {slice : Nat} {index value : SrcEff}
    (ok : (SrcStmt.setIndexEval slice index value).lower sigs decls ret scope next = some out) :
    (isHomed (lookup scope slice) = true ∧
        (SrcStmt.setPlace (.eAt (.ePure (.local slice)) index) value).lower sigs decls ret scope next =
          some out) ∨
    (isHomed (lookup scope slice) = false ∧
        lowerSetIndexEval decls next (lookup scope slice) (index.eval sigs decls scope next)
          (value.eval sigs decls scope (next + 1)) = some out) := by
  simp only [SrcStmt.lower] at ok
  cases hh : isHomed (lookup scope slice)
  · simp only [setPick, hh, Bool.false_eq_true, ↓reduceIte, lookupSlot_unhomed hh] at ok
    exact .inr ⟨rfl, ok⟩
  · simp only [setPick, hh, ↓reduceIte] at ok
    refine .inl ⟨rfl, ?_⟩
    simp only [SrcStmt.lower]
    exact ok

/-- `id.field = value` with effects. -/
theorem lower_setFieldEval {id field : Nat} {value : SrcEff}
    (ok : (SrcStmt.setFieldEval id field value).lower sigs decls ret scope next = some out) :
    (isHomed (lookup scope id) = true ∧
        (SrcStmt.setPlace (.eField (.ePure (.local id)) field) value).lower sigs decls ret scope next =
          some out) ∨
    (isHomed (lookup scope id) = false ∧
        lowerSetFieldEval next (lookup scope id) field (value.eval sigs decls scope next) = some out) := by
  simp only [SrcStmt.lower] at ok
  cases hh : isHomed (lookup scope id)
  · simp only [setPick, hh, Bool.false_eq_true, ↓reduceIte, lookupSlot_unhomed hh] at ok
    exact .inr ⟨rfl, ok⟩
  · simp only [setPick, hh, ↓reduceIte] at ok
    refine .inl ⟨rfl, ?_⟩
    simp only [SrcStmt.lower]
    exact ok

/-- `place = value`. -/
theorem lower_setPlace {place value : SrcEff} :
    (SrcStmt.setPlace place value).lower sigs decls ret scope next =
      storePlace next (placeCode (ownFrame sigs) scope next place) (value.eval sigs decls scope (next + 1)) := by
  simp only [SrcStmt.lower]

/-- `place op= value`. -/
theorem lower_setPlaceOp {op : SrcAssignOp} {place value : SrcEff} :
    (SrcStmt.setPlaceOp op place value).lower sigs decls ret scope next =
      storePlaceOp op next (placeCode (ownFrame sigs) scope next place) (value.eval sigs decls scope (next + 2)) := by
  simp only [SrcStmt.lower]

/-! ### Control -/

/-- `if condition { .. } else { .. }`: reading a homed local, `ifEval`'s. -/
theorem lower_if {condition : SrcExpr} {thenBranch elseBranch : SrcStmt}
    (ok : (SrcStmt.if condition thenBranch elseBranch).lower sigs decls ret scope next = some out) :
    (readsHome scope condition = false ∧
        guarded next (condition.guard scope) (lowerIf (lowerAs scope condition .bool)
          (thenBranch.lower sigs decls ret scope next) (elseBranch.lower sigs decls ret scope next)) = some out) ∨
    (readsHome scope condition = true ∧
        (SrcStmt.ifEval (.ePure condition) thenBranch elseBranch).lower sigs decls ret scope next = some out) := by
  simp only [SrcStmt.lower] at ok
  cases reads : readsHome scope condition
  · simp only [ifPick, reads, Bool.false_eq_true, ↓reduceIte] at ok
    exact .inl ⟨rfl, ok⟩
  · simp only [ifPick, reads, ↓reduceIte] at ok
    refine .inr ⟨rfl, ?_⟩
    simp only [SrcStmt.lower, SrcEff.eval]
    exact ok

/-- `while condition { .. }`: reading a homed local, `whileEval`'s. -/
theorem lower_while {condition : SrcExpr} {body : SrcStmt}
    (ok : (SrcStmt.while condition body).lower sigs decls ret scope next = some out) :
    (readsHome scope condition = false ∧
        lowerWhile next (condition.guard scope) (lowerAs scope condition .bool)
          (body.lower sigs decls ret scope next) = some out) ∨
    (readsHome scope condition = true ∧
        (SrcStmt.whileEval (.ePure condition) body).lower sigs decls ret scope next = some out) := by
  simp only [SrcStmt.lower] at ok
  cases reads : readsHome scope condition
  · simp only [whilePick, reads, Bool.false_eq_true, ↓reduceIte] at ok
    exact .inl ⟨rfl, ok⟩
  · simp only [whilePick, reads, ↓reduceIte] at ok
    refine .inr ⟨rfl, ?_⟩
    simp only [SrcStmt.lower, SrcEff.eval]
    exact ok

/-- `return value`: reading a homed local, `returnEval`'s. -/
theorem lower_return {value : SrcExpr}
    (ok : (SrcStmt.return value).lower sigs decls ret scope next = some out) :
    (readsHome scope value = false ∧
        guarded next (value.guard scope) (lowerReturn (lowerValue scope value ret)) = some out) ∨
    (readsHome scope value = true ∧
        (SrcStmt.returnEval (.ePure value)).lower sigs decls ret scope next = some out) := by
  simp only [SrcStmt.lower] at ok
  cases reads : readsHome scope value
  · simp only [returnPick, reads, Bool.false_eq_true, ↓reduceIte] at ok
    exact .inl ⟨rfl, ok⟩
  · simp only [returnPick, reads, ↓reduceIte] at ok
    refine .inr ⟨rfl, ?_⟩
    simp only [SrcStmt.lower, SrcEff.eval]
    exact ok

/-- A match arm: the scrutinee is unhomed. -/
theorem lower_matchArm {scrutinee enumId variant : Nat} {binds : Bool} {binder : Nat} {ty : SrcType}
    {body rest : SrcStmt}
    (ok : (SrcStmt.matchArm scrutinee enumId variant binds binder ty body rest).lower sigs decls ret scope next =
      some out) :
    isHomed (lookup scope scrutinee) = false ∧
      lowerMatchArm scope (lookup scope scrutinee) enumId variant binds binder ty next
        (body.lower sigs decls ret (armBodyScope binds binder ty next scope) (next + ty.size))
        (rest.lower sigs decls ret scope next) = some out := by
  simp only [SrcStmt.lower] at ok
  cases hh : isHomed (lookup scope scrutinee)
  · rw [lookupSlot_unhomed hh] at ok
    exact ⟨rfl, ok⟩
  · rw [lookupSlot_homed hh] at ok
    simp [lowerMatchArm] at ok

/-! ### The constructors S6b left alone -/

theorem lower_nop : SrcStmt.nop.lower sigs decls ret scope next = some .skip := by
  simp only [SrcStmt.lower]

theorem lower_then {first second : SrcStmt} :
    (SrcStmt.then first second).lower sigs decls ret scope next =
      lowerThen (first.lower sigs decls ret scope next) (second.lower sigs decls ret scope next) := by
  simp only [SrcStmt.lower]

theorem lower_setByte {pointer offset value : SrcExpr} :
    (SrcStmt.setByte pointer offset value).lower sigs decls ret scope next =
      guarded next (guardAnd (pointer.guard scope) (guardAnd (offset.guard scope) (value.guard scope)))
        (lowerStore (lowerAddress (lowerAs scope pointer .ptr) (lowerAs scope offset (.uint .usize)))
          (lowerAs scope value (.uint .uint8))) := by
  simp only [SrcStmt.lower]

theorem lower_free {pointer size : SrcExpr} {shift : Nat} :
    (SrcStmt.free pointer size shift).lower sigs decls ret scope next =
      guarded next (guardAnd (pointer.guard scope) (size.guard scope))
        (lowerFree shift (lowerAs scope pointer .ptr) (lowerAs scope size (.uint .usize))) := by
  simp only [SrcStmt.lower]

theorem lower_ifEval {condition : SrcEff} {thenBranch elseBranch : SrcStmt} :
    (SrcStmt.ifEval condition thenBranch elseBranch).lower sigs decls ret scope next =
      lowerIfEval next (condition.eval sigs decls scope next) (thenBranch.lower sigs decls ret scope next)
        (elseBranch.lower sigs decls ret scope next) := by
  simp only [SrcStmt.lower]

theorem lower_whileEval {condition : SrcEff} {body : SrcStmt} :
    (SrcStmt.whileEval condition body).lower sigs decls ret scope next =
      lowerWhileEval next (condition.eval sigs decls scope next) (body.lower sigs decls ret scope next) := by
  simp only [SrcStmt.lower]

theorem lower_returnEval {value : SrcEff} :
    (SrcStmt.returnEval value).lower sigs decls ret scope next =
      lowerReturnEval next ret (value.eval sigs decls scope next) := by
  simp only [SrcStmt.lower]

theorem lower_discard {value : SrcEff} :
    (SrcStmt.discard value).lower sigs decls ret scope next = lowerDiscard (stmtEval value sigs decls scope next) := by
  simp only [SrcStmt.lower]

theorem lower_returnUnit : SrcStmt.returnUnit.lower sigs decls ret scope next = lowerReturnUnit ret := by
  simp only [SrcStmt.lower]

theorem lower_assert {condition : SrcEff} :
    (SrcStmt.assert condition).lower sigs decls ret scope next =
      lowerAssert (condition.eval sigs decls scope next) next := by
  simp only [SrcStmt.lower]

theorem lower_break : SrcStmt.break.lower sigs decls ret scope next = some .brk := by
  simp only [SrcStmt.lower]

theorem lower_continue : SrcStmt.continue.lower sigs decls ret scope next = some .cont := by
  simp only [SrcStmt.lower]

theorem lower_unreachable {id : Nat} {ty : SrcType} :
    (SrcStmt.unreachable id ty).lower sigs decls ret scope next = lowerUnreachable (ty.same ret) next := by
  simp only [SrcStmt.lower]

end Lanius.Mini
