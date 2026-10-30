import Lanius.Mini.Reading.Calls

/-! # The reading, V8d: let heads

A `let`'s initializer is read by its shape under wrappers (`Peel`): a
`match` over an enum local, a struct literal of the let's own type, a call
`path(args)` (an allocation `alloc(size, 2^k)`, a raw slice
`slice_from_raw_parts(pointer, length)`, a free or static call, or a variant
of the let's own enum type with a payload), a method call, a slice index
`local[index]`, a unit variant, or a plain expression.

A plain reading is allowed for any initializer that reads as an expression:
the builder falls back to it when the peel or a unit variant's path fails,
which can fail for want of fuel (SEMANTIC_DECISIONS, "The reading states
searches' positive part"). The same holds for a call's path: the alloc and
slice readings are not excluded from the named reading, and a match's arms
are one naming arm per variant, without the condition that no other arm
names it. -/

namespace Lanius.Mini.Reading

open Lanius.Mini Lanius.Mini.Prod

/-! ## Small helpers -/

theorem namedDecl_eq : ∀ {ty : Ty} {d : Nat}, namedDecl ty = some d → ∃ args, ty = .tyNamed d args
  | .tyNamed d' args, d, h => by
    simp only [namedDecl, Option.some.injEq] at h
    subst h
    exact ⟨args, rfl⟩
  | .tyI32, _, h => by simp [namedDecl] at h
  | .tyBool, _, h => by simp [namedDecl] at h
  | .tyUint _, _, h => by simp [namedDecl] at h
  | .tyPtr, _, h => by simp [namedDecl] at h
  | .tyIsize, _, h => by simp [namedDecl] at h
  | .tySlice _, _, h => by simp [namedDecl] at h

theorem namedParts_eq : ∀ {ty : Ty} {n : Inst}, namedParts ty = some n → ty = .tyNamed n.decl n.args
  | .tyNamed d args, n, h => by
    simp only [namedParts, Option.some.injEq] at h
    subst h
    rfl
  | .tyI32, _, h => by simp [namedParts] at h
  | .tyBool, _, h => by simp [namedParts] at h
  | .tyUint _, _, h => by simp [namedParts] at h
  | .tyPtr, _, h => by simp [namedParts] at h
  | .tyIsize, _, h => by simp [namedParts] at h
  | .tySlice _, _, h => by simp [namedParts] at h

theorem isPath_eq {s : Option (List Name)} {w : List Name} (h : isPath s w = true) : s = some w := by
  cases s with
  | none => simp [isPath] at h
  | some ss =>
    simp only [isPath, sameSpellings_iff] at h
    rw [h]

theorem hasKids_false {c : CTree} (h : hasKids c = false) : kidsOf c = [] := by
  cases hk : kidsOf c with
  | nil => rfl
  | cons x xs =>
    have := (hasKids_iff c).2 (by rw [hk]; simp)
    rw [h] at this
    cases this

theorem plainHead_some {e : Option SrcExpr} {hd : LetHead} (h : plainHead e = some hd) :
    ∃ x, e = some x ∧ hd = .plain x := by
  cases e with
  | none => simp [plainHead] at h
  | some x =>
    simp only [plainHead, Option.some.injEq] at h
    exact ⟨x, rfl, h.symm⟩

/-! ## Peeling wrappers -/

/-- The postfix expression an initializer is under: through `expr`/`base`
wrappers and operator levels, casts and assignments with no tail. -/
inductive Peel : CTree → CTree → Prop
  | wrap {c pf : CTree} : (nodeProd c = pExpr ∨ nodeProd c = pBase) → Peel (kid c 0) pf → Peel c pf
  | bare {c pf : CTree} : (nodeProd c = pAssign ∨ nodeProd c ∈ levelProds ∨ nodeProd c = pCast) →
      kidsOf (kid c 1) = [] → Peel (kid c 0) pf → Peel c pf
  | here {c : CTree} : nodeProd c = pPostfix → Peel c c

theorem peel_sound : ∀ {fuel : Nat} {c pf : CTree}, peel fuel c = some pf → Peel c pf
  | 0, _, _, h => by unfold peel at h; simp at h
  | f + 1, c, pf, h => by
    unfold peel at h
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
    split at h
    · rename_i w
      simp only [Bool.or_eq_true, decide_eq_true_eq] at w
      exact .wrap w (peel_sound h)
    · split at h
      · rename_i w
        simp only [Bool.and_eq_true, Bool.or_eq_true, decide_eq_true_eq, Bool.not_eq_true', isLevel_iff,
          or_assoc] at w
        exact .bare w.1 (hasKids_false w.2) (peel_sound h)
      · split at h
        · rename_i e
          simp only [Option.some.injEq] at h
          subst h
          exact .here e
        · cases h

/-! ## Shifts, allocations and raw slices -/

/-- A literal `2^k`, `k < 31`, of type i32 or an unsigned type. -/
inductive LiteralShift : SrcExpr → Nat → Prop
  | int {v : BitVec 32} {k : Nat} : k < 31 → BitVec.setWidth 64 v = BitVec.ofNat 64 (2 ^ k) →
      LiteralShift (.int v) k
  | unsigned {u : UintTy} {v : BitVec 64} {k : Nat} : k < 31 → v = BitVec.ofNat 64 (2 ^ k) →
      LiteralShift (.unsigned u v) k

/-- An alignment `2^k`: a literal, or a literal cast to usize. -/
inductive ShiftOf : SrcExpr → Nat → Prop
  | lit {e : SrcExpr} {k : Nat} : LiteralShift e k → ShiftOf e k
  | cast {x : SrcExpr} {k : Nat} : LiteralShift x k → ShiftOf (.cast (.uint .usize) x) k

theorem shiftOfU64_sound : ∀ {fuel : Nat} {k : BitVec 64} {s p r : Nat}, shiftOfU64 fuel k s p = some r →
    ∃ j, j < fuel ∧ r = s + j ∧ BitVec.ofNat 64 (p * 2 ^ j) = k
  | 0, _, _, _, _, h => by unfold shiftOfU64 at h; simp at h
  | f + 1, k, s, p, r, h => by
    unfold shiftOfU64 at h
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
    split at h
    · rename_i e
      simp only [Option.some.injEq] at h
      subst h
      exact ⟨0, by omega, by omega, by simpa using e⟩
    · obtain ⟨j, lt, rfl, e⟩ := shiftOfU64_sound h
      refine ⟨j + 1, by omega, by omega, ?_⟩
      rw [← e, Nat.pow_succ', ← Nat.mul_assoc]

theorem literalShift_sound {e : SrcExpr} {k : Nat} (h : literalShift e = some k) : LiteralShift e k := by
  cases e with
  | int v =>
    simp only [literalShift] at h
    obtain ⟨j, lt, rfl, w⟩ := shiftOfU64_sound h
    exact .int (by omega) (by simpa using w.symm)
  | unsigned u v =>
    simp only [literalShift] at h
    obtain ⟨j, lt, rfl, w⟩ := shiftOfU64_sound h
    exact .unsigned (by omega) (by simpa using w.symm)
  | boolean _ | «local» _ | field _ _ | negate _ | «not» _ | apply _ _ _ | cast _ _ | null =>
    simp [literalShift] at h

theorem shiftOf_sound {e : SrcExpr} {k : Nat} (h : shiftOf e = some k) : ShiftOf e k := by
  cases e with
  | int v => simp only [shiftOf] at h; exact .lit (literalShift_sound h)
  | unsigned u v => simp only [shiftOf] at h; exact .lit (literalShift_sound h)
  | cast t x =>
    simp only [shiftOf, castShift] at h
    split at h
    · rename_i u
      have : t = .uint .usize := by
        cases t <;> (try cases ‹UintTy›) <;> simp [isUsize] at u ⊢
      subst this
      exact .cast (literalShift_sound h)
    · cases h
  | boolean _ | «local» _ | field _ _ | negate _ | «not» _ | apply _ _ _ | null =>
    simp [shiftOf] at h

/-- `alloc(size, 2^k)`. -/
def AllocHeadR (es : List SrcExpr) (hd : LetHead) : Prop :=
  ∃ size align k, es = [size, align] ∧ ShiftOf align k ∧ hd = .allocOf size k

theorem allocHead_sound {es : List SrcExpr} {hd : LetHead} (h : allocHead (some es) = some hd) : AllocHeadR es hd := by
  match es, h with
  | [], h => simp [allocHead] at h
  | [_], h => simp [allocHead] at h
  | size :: align :: more, h =>
    simp only [allocHead] at h
    cases hs : shiftOf align with
    | none => rw [hs] at h; simp [allocShifted] at h
    | some k =>
      rw [hs] at h
      cases more with
      | nil =>
        simp only [allocShifted, Option.some.injEq] at h
        exact ⟨size, align, k, rfl, shiftOf_sound hs, h.symm⟩
      | cons _ _ => simp [allocShifted] at h

theorem sliceHead_sound {es : List SrcExpr} {hd : LetHead} (h : sliceHead (some es) = some hd) :
    ∃ p l, es = [p, l] ∧ hd = .sliceOf p l := by
  match es, h with
  | [p, l], h =>
    simp only [sliceHead, Option.some.injEq] at h
    exact ⟨p, l, rfl, h.symm⟩
  | [], h => simp [sliceHead] at h
  | [_], h => simp [sliceHead] at h
  | _ :: _ :: _ :: _, h => simp [sliceHead] at h

/-! ## Variants by path -/

/-- `T::name` with `T` an enum the path's prefix names: variant `name` of `T`. -/
def EnumVariant (env : FrontEnv) (front : ModPath) (name : Name) (v : VariantAt) : Prop :=
  DeclAt env front v.owner ∧
    ∃ t, env.decls.types[v.owner]? = some t ∧ t.isEnum = true ∧ FirstWith t.variants (· = name) v.index name

/-- A variant a path names: a bare name's single variant (here or
imported), the variant of the enum the prefix names, or else the single
variant so spelled among the enums of the module the prefix names. -/
inductive VariantByPath (env : FrontEnv) (front : ModPath) (name : Name) : VariantAt → Prop
  | bare {v : VariantAt} : front = [] → BareVariant env.decls env.home name v → VariantByPath env front name v
  | enum {v : VariantAt} : front ≠ [] → EnumVariant env front name v → VariantByPath env front name v
  | module {v : VariantAt} : front ≠ [] → (¬∃ u, EnumVariant env front name u) →
      variantsNamed env.decls.types front name 0 = [v] → VariantByPath env front name v

theorem enumVariant_sound {env : FrontEnv} {front : ModPath} {name : Name} {v : VariantAt}
    (h : enumVariant env front name = some v) : EnumVariant env front name v := by
  unfold enumVariant at h
  cases hs : splitLast front with
  | none => rw [hs] at h; cases h
  | some sp =>
    rw [hs] at h
    simp only [variantIn] at h
    cases hf : findType env.decls.types (moduleOr env.home sp.home) sp.name 0 with
    | none => rw [hf] at h; cases h
    | some k =>
      rw [hf] at h
      have da : DeclAt env front k := typeDeclAt_sound (by unfold typeDeclAt; rw [hs]; exact hf)
      simp only at h
      cases ht : env.decls.types[k]? with
      | none => rw [ht] at h; cases h
      | some t =>
        rw [ht] at h
        simp only [variantOfDecl] at h
        split at h
        · rename_i en
          cases hp : position t.variants name 0 with
          | none => rw [hp] at h; cases h
          | some j =>
            rw [hp] at h
            simp only [Option.some.injEq] at h
            subst h
            exact ⟨da, t, ht, en, position_sound hp⟩
        · cases h

theorem enumVariant_none {env : FrontEnv} {front : ModPath} {name : Name}
    (h : enumVariant env front name = none) : ¬∃ u, EnumVariant env front name u := by
  rintro ⟨v, ⟨m, n, r, ft⟩, t, ht, en, fv⟩
  obtain ⟨hs, rfl⟩ := resolves_split' r
  unfold enumVariant at h
  rw [hs] at h
  simp only [variantIn] at h
  obtain ⟨t', fw⟩ := ft
  cases hf : findType env.decls.types (moduleOr env.home front.dropLast) n 0 with
  | none => exact findType_none hf t' (firstWith_mem fw).1 (firstWith_mem fw).2
  | some k =>
    rw [hf] at h
    obtain ⟨t'', fk⟩ := findType_sound hf
    have e : k = v.owner := (firstWith_unique fk fw).1
    rw [e] at h
    simp only [ht, variantOfDecl, en, if_true] at h
    cases hp : position t.variants name 0 with
    | none => exact position_none hp (firstWith_mem fv).1
    | some j => rw [hp] at h; cases h

theorem variantByPath_sound {env : FrontEnv} {s : Split} {v : VariantAt} (h : variantByPath env s = some v) :
    VariantByPath env s.home s.name v := by
  unfold variantByPath at h
  split at h
  · rename_i nn
    exact .bare ((noNames_iff _).1 nn) (bareVariant_sound h)
  · rename_i nn
    have ne : s.home ≠ [] := fun e => nn ((noNames_iff _).2 e)
    cases he : enumVariant env s.home s.name with
    | some u =>
      rw [he] at h
      simp only [Option.some.injEq] at h
      subst h
      exact .enum ne (enumVariant_sound he)
    | none =>
      rw [he] at h
      exact .module ne (enumVariant_none he) (onlyVariant_sound h)

/-- A variant of the let's own enum type, with no type arguments written. -/
def VariantHeadR (ty : Ty) (v : VariantAt) (targs : List CTree) (es : List SrcExpr) (hd : LetHead) : Prop :=
  (∃ args, ty = .tyNamed v.owner args) ∧ targs = [] ∧ hd = .variantOf v.index es

theorem variantHead_sound {ty : Ty} {v : VariantAt} {targs : List CTree} {es : List SrcExpr} {hd : LetHead}
    (h : variantHead ty (some v) targs es = some hd) : VariantHeadR ty v targs es hd := by
  simp only [variantHead] at h
  cases hn : namedDecl ty with
  | none => rw [hn] at h; cases h
  | some d =>
    rw [hn] at h
    obtain ⟨args, rfl⟩ := namedDecl_eq hn
    simp only [variantChecked] at h
    split at h
    · rename_i c
      simp only [Bool.and_eq_true, decide_eq_true_eq, noTrees_iff] at c
      obtain ⟨rfl, rfl⟩ := c
      simp only [Option.some.injEq] at h
      exact ⟨⟨args, rfl⟩, rfl, h.symm⟩
    · cases h

/-! ## Named calls -/

/-- A path names a function: its prefix names a type, or it names a free
function. -/
def IsFnPath (env : FrontEnv) (front : ModPath) (name : Name) : Prop :=
  (∃ n, TypeOwner env front n) ∨ ∃ d, FnNamed env.decls (if front = [] then env.home else front) name d

theorem isFnPath_iff (env : FrontEnv) (s : Split) : isFnPath env s = true ↔ IsFnPath env s.home s.name := by
  unfold isFnPath IsFnPath
  rw [Bool.or_eq_true, isTypeParam_iff, ← moduleOr_eq]
  apply or_congr Iff.rfl
  cases hf : findFn env.decls.fns (moduleOr env.home s.home) s.name 0 with
  | none =>
    simp only [isSomeIndex, Bool.false_eq_true, false_iff, not_exists]
    rintro d ⟨f, fw⟩
    exact findFn_none hf f (firstWith_mem fw).1 (firstWith_mem fw).2
  | some d =>
    simp only [isSomeIndex, true_iff]
    exact ⟨d, findFn_sound hf⟩

/-- `front::name(args)` in a let: a call when the path names a function,
else a variant with a payload. The negation is fuel-free and exact. -/
inductive NamedHeadR (env : FrontEnv) (scope : List Local) (ty : Ty) (front : ModPath) (name : Name)
    (targs : List CTree) (es : List SrcExpr) : LetHead → Prop
  | call {c : Called} : IsFnPath env front name → PathCall env scope ty front name targs es c →
      NamedHeadR env scope ty front name targs es (.callOf c)
  | variant {v : VariantAt} {hd : LetHead} : ¬IsFnPath env front name → VariantByPath env front name v →
      VariantHeadR ty v targs es hd → NamedHeadR env scope ty front name targs es hd

theorem namedHead_sound {fuel : Nat} {env : FrontEnv} {scope : List Local} {ty : Ty} {s : Split}
    {targs : List CTree} {es : List SrcExpr} {hd : LetHead} (h : namedHead fuel env scope ty s targs es = some hd) :
    NamedHeadR env scope ty s.home s.name targs es hd := by
  unfold namedHead at h
  split at h
  · rename_i fp
    cases hc : pathCall fuel env scope ty s targs es with
    | none => rw [hc] at h; simp [callHeadOf] at h
    | some c =>
      rw [hc] at h
      simp only [callHeadOf, Option.some.injEq] at h
      subst h
      exact .call ((isFnPath_iff env s).1 fp) (pathCall_sound hc)
  · rename_i fp
    cases hv : variantByPath env s with
    | none => rw [hv] at h; simp [variantHead] at h
    | some v =>
      rw [hv] at h
      exact .variant (fun q => fp ((isFnPath_iff env s).2 q)) (variantByPath_sound hv) (variantHead_sound h)

/-- `path(args)` in a let: an allocation, a raw slice, or a named call or
variant. -/
inductive CallPathHeadR (env : FrontEnv) (scope : List Local) (ty : Ty) (path args : CTree) : LetHead → Prop
  | alloc {es : List SrcExpr} {hd : LetHead} : PathSpellings (kid path 0) (kid path 1) allocPath →
      ArgsOfR env scope args es → AllocHeadR es hd → CallPathHeadR env scope ty path args hd
  | slice {p l : SrcExpr} : PathSpellings (kid path 0) (kid path 1) [textSliceFromRawParts] →
      ArgsOfR env scope args [p, l] → CallPathHeadR env scope ty path args (.sliceOf p l)
  | named {pr : PathRef} {front : ModPath} {name : Name} {es : List SrcExpr} {hd : LetHead} :
      PathRefR (kid path 0) (kid path 1) pr → pr.segments = front ++ [name] → ArgsOfR env scope args es →
      NamedHeadR env scope ty front name pr.targs es hd → CallPathHeadR env scope ty path args hd

theorem callPathHead_sound {fuel : Nat} {env : FrontEnv} {scope : List Local} {ty : Ty} {path args : CTree}
    {hd : LetHead} (h : callPathHead fuel env scope ty path args = some hd) : CallPathHeadR env scope ty path args hd := by
  unfold callPathHead at h
  simp only at h
  split at h
  · rename_i ia
    cases ha : argsOf fuel env scope args with
    | none => rw [ha] at h; simp [allocHead] at h
    | some es =>
      rw [ha] at h
      exact .alloc (pathSpellings_sound (isPath_eq ia)) (argsOf_sound ha) (allocHead_sound h)
  · split at h
    · rename_i _ isl
      cases ha : argsOf fuel env scope args with
      | none => rw [ha] at h; simp [sliceHead] at h
      | some es =>
        rw [ha] at h
        obtain ⟨p, l, rfl, rfl⟩ := sliceHead_sound h
        exact .slice (pathSpellings_sound (isPath_eq isl)) (argsOf_sound ha)
    · cases hp : pathRef fuel (kid path 0) (kid path 1) with
      | none => rw [hp] at h; cases h
      | some pr =>
        rw [hp] at h
        simp only at h
        cases hs : splitLast pr.segments with
        | none => rw [hs] at h; cases h
        | some s =>
          rw [hs] at h
          simp only at h
          cases ha : argsOf fuel env scope args with
          | none => rw [ha] at h; cases h
          | some es =>
            rw [ha] at h
            exact .named (pathRef_sound hp) (splitLast_sound hs) (argsOf_sound ha) (namedHead_sound h)

/-! ## Struct literals -/

theorem sameNames_iff : ∀ (names : List Name) (fs : List CTree),
    sameNames names fs = true ↔ names = fs.map (fun f => (kidToken f 0).text)
  | [], [] => by simp [sameNames]
  | [], _ :: _ => by simp [sameNames]
  | _ :: _, [] => by simp [sameNames]
  | n :: rest, f :: more => by simp [sameNames, sameText_iff, sameNames_iff rest more]

theorem fieldValues_eq : ∀ (fs : List CTree), fieldValues fs = fs.map (kid · 2)
  | [] => by simp [fieldValues]
  | f :: rest => by simp [fieldValues, fieldValues_eq rest]

/-- `T { f: e, .. }` in a let of struct type `T`, its fields written in
declaration order. -/
def LiteralHeadR (env : FrontEnv) (scope : List Local) (ty : Ty) (path fields : CTree) (hd : LetHead) : Prop :=
  ∃ ss d args t fs es, PathSpellings (kid path 0) (kid path 1) ss ∧ DeclAt env ss d ∧ ty = .tyNamed d args ∧
    env.decls.types[d]? = some t ∧ t.isEnum = false ∧ Items fields fs ∧
    t.fields = fs.map (fun f => (kidToken f 0).text) ∧ ExprsR env scope (fs.map (kid · 2)) es ∧ hd = .literalOf es

theorem literalHead_sound {fuel : Nat} {env : FrontEnv} {scope : List Local} {ty : Ty} {path fields : CTree}
    {hd : LetHead} (h : literalHead fuel env scope ty path fields = some hd) :
    LiteralHeadR env scope ty path fields hd := by
  unfold literalHead at h
  cases hs : pathSpellings fuel (kid path 0) (kid path 1) with
  | none => rw [hs] at h; cases h
  | some ss =>
    rw [hs] at h
    simp only at h
    cases hi : listItems fuel fields with
    | none => rw [hi] at h; cases h
    | some fs =>
      rw [hi] at h
      simp only [literalAt] at h
      cases hx : typeDeclAt env ss with
      | none => rw [hx] at h; cases h
      | some x =>
        rw [hx] at h
        simp only at h
        cases hn : namedDecl ty with
        | none => rw [hn] at h; cases h
        | some e =>
          rw [hn] at h
          obtain ⟨args, rfl⟩ := namedDecl_eq hn
          simp only [literalEntry] at h
          cases ht : env.decls.types[x]? with
          | none => rw [ht] at h; cases h
          | some t =>
            rw [ht] at h
            simp only [literalChecked] at h
            split at h
            · rename_i c
              simp only [Bool.and_eq_true, decide_eq_true_eq, Bool.not_eq_true', sameNames_iff] at c
              obtain ⟨⟨xe, en⟩, names⟩ := c
              subst xe
              cases he : exprsOf fuel env scope (fieldValues fs) with
              | none => rw [he] at h; cases h
              | some es =>
                rw [he] at h
                simp only [Option.some.injEq] at h
                subst h
                refine ⟨ss, _, args, t, fs, es, pathSpellings_sound hs, typeDeclAt_sound hx, rfl, ht, en,
                  listItems_sound hi, names, ?_, rfl⟩
                rw [← fieldValues_eq]
                exact exprsOf_sound he
            · cases h

/-! ## Matches -/

def ArmPrefix (p : ModPath) (owner : TypeDecl) : Prop :=
  p = [] ∨ p = owner.home ∨ p = [owner.name] ∨ p = owner.home ++ [owner.name]

/-- An arm's path names variant `name` of `owner`: bare, or after the
enum's module, its name, or both. -/
def ArmNamed (ss : List Name) (owner : TypeDecl) (name : Name) : Prop :=
  ∃ front, ss = front ++ [name] ∧ ArmPrefix front owner

theorem armPrefix_iff (p : ModPath) (owner : TypeDecl) : armPrefix p owner = true ↔ ArmPrefix p owner := by
  simp [armPrefix, ArmPrefix, noNames_iff, sameSpellings_iff, or_assoc]

theorem armNamed_sound {ss : List Name} {owner : TypeDecl} {name : Name}
    (h : armNamed (some ss) owner name = true) : ArmNamed ss owner name := by
  simp only [armNamed] at h
  cases hs : splitLast ss with
  | none => rw [hs] at h; simp at h
  | some s =>
    rw [hs] at h
    simp only [Bool.and_eq_true, sameText_iff, armPrefix_iff] at h
    obtain ⟨e, p⟩ := h
    exact ⟨s.home, by rw [splitLast_sound hs, e], p⟩

/-- Payload binders: plain names, not globals, numbered by their offsets. -/
inductive BindersR (env : FrontEnv) : List Local → List CTree → List Ty → Bound → Prop
  | nil {scope : List Local} : BindersR env scope [] [] { ids := [], scope := scope }
  | cons {scope : List Local} {p : CTree} {more : List CTree} {t : Ty} {rest : List Ty} {b : Bound} {n : Name} :
      nodeProd p = pPatternIdent → nodeProd (kid p 1) = pPatternPlain → PathName (kid p 0) n → n ∉ env.globals →
      FreshId scope ((kidToken (kid (kid p 0) 0) 0).start - env.base) → BindersR env ({ name := n, id := (kidToken (kid (kid p 0) 0) 0).start - env.base, ty := t } :: scope) more rest b →
      BindersR env scope (p :: more) (t :: rest)
        { ids := ((kidToken (kid (kid p 0) 0) 0).start - env.base) :: b.ids, scope := b.scope }

theorem bindersOf_sound {env : FrontEnv} : ∀ {scope : List Local} {pats : List CTree} {payload : List Ty} {b : Bound},
    bindersOf env scope pats payload = some b → BindersR env scope pats payload b
  | scope, [], [], b, h => by
    simp only [bindersOf, Option.some.injEq] at h
    subst h
    exact .nil
  | _, _ :: _, [], _, h => by simp [bindersOf] at h
  | _, [], _ :: _, _, h => by simp [bindersOf] at h
  | scope, p :: more, t :: rest, b, h => by
    simp only [bindersOf] at h
    split at h
    · rename_i c
      simp only [Bool.and_eq_true, decide_eq_true_eq, Bool.not_eq_true'] at c
      obtain ⟨⟨⟨⟨pi, pl⟩, sn⟩, ng⟩, fr⟩ := c
      cases hn : pathName (kid p 0) with
      | none => rw [hn] at sn; simp [isSomeName] at sn
      | some n =>
        have pn := pathName_eq hn
        have e := pn.2.2.2
        subst e
        cases hr : bindersOf env (⟨(kidToken (kid (kid p 0) 0) 0).text, (kidToken (kid (kid p 0) 0) 0).start - env.base, t⟩ :: scope) more rest with
        | none => rw [hr] at h; simp [consBinder] at h
        | some b' =>
          rw [hr] at h
          simp only [consBinder, Option.some.injEq] at h
          subst h
          refine .cons pi pl pn (fun mem => ?_) ((freshId_iff _ _).1 fr) (bindersOf_sound hr)
          rw [(member_iff _ _).2 mem] at ng
          cases ng
    · cases h

/-- One arm, for variant `v`: a unit pattern, or a payload pattern binding
each payload value. -/
inductive ArmR (env : FrontEnv) (scope : List Local) (owner : TypeDecl) (v : VariantTy) (arm : CTree) : SrcArm → Prop
  | unit {ss : List Name} {e : SrcExpr} : nodeProd (kid arm 0) = pPatternIdent →
      PathSpellings (kid (kid (kid arm 0) 0) 0) (kid (kid (kid arm 0) 0) 1) ss → ArmNamed ss owner v.name →
      nodeProd (kid (kid arm 0) 1) = pPatternPlain → ExprR env scope (kid arm 2) e →
      ArmR env scope owner v arm { binders := [], value := e }
  | payload {ss : List Name} {pats : List CTree} {b : Bound} {e : SrcExpr} : nodeProd (kid arm 0) = pPatternIdent →
      PathSpellings (kid (kid (kid arm 0) 0) 0) (kid (kid (kid arm 0) 0) 1) ss → ArmNamed ss owner v.name →
      nodeProd (kid (kid arm 0) 1) ≠ pPatternPlain → Items (kid (kid (kid arm 0) 1) 1) pats →
      BindersR env scope pats v.payload b → ExprR env b.scope (kid arm 2) e →
      ArmR env scope owner v arm { binders := b.ids, value := e }

theorem armOf_sound {fuel : Nat} {env : FrontEnv} {scope : List Local} {owner : TypeDecl} {v : VariantTy}
    {arm : CTree} {sa : SrcArm} (h : armOf fuel env scope owner v arm = some sa) : ArmR env scope owner v arm sa := by
  unfold armOf at h
  simp only at h
  split at h
  · rename_i c
    simp only [Bool.and_eq_true, decide_eq_true_eq] at c
    obtain ⟨pi, an⟩ := c
    cases hs : pathSpellings fuel (kid (kid (kid arm 0) 0) 0) (kid (kid (kid arm 0) 0) 1) with
    | none => rw [hs] at an; simp [armNamed] at an
    | some ss =>
      rw [hs] at an
      have ps := pathSpellings_sound hs
      have na := armNamed_sound an
      split at h
      · rename_i pl
        simp only [armBound] at h
        cases he : exprOf fuel env scope (kid arm 2) with
        | none => rw [he] at h; simp [armValue] at h
        | some e =>
          rw [he] at h
          simp only [armValue, Option.some.injEq] at h
          subst h
          exact .unit pi ps na pl (exprOf_sound he)
      · rename_i pl
        cases hl : listItems fuel (kid (kid (kid arm 0) 1) 1) with
        | none => rw [hl] at h; cases h
        | some pats =>
          rw [hl] at h
          simp only at h
          cases hb : bindersOf env scope pats v.payload with
          | none => rw [hb] at h; simp [armBound] at h
          | some b =>
            rw [hb] at h
            simp only [armBound] at h
            cases he : exprOf fuel env b.scope (kid arm 2) with
            | none => rw [he] at h; simp [armValue] at h
            | some e =>
              rw [he] at h
              simp only [armValue, Option.some.injEq] at h
              subst h
              exact .payload pi ps na pl (listItems_sound hl) (bindersOf_sound hb) (exprOf_sound he)
  · cases h

/-- The arms, one per variant in declaration order. -/
inductive ArmsR (env : FrontEnv) (scope : List Local) (owner : TypeDecl) :
    List VariantTy → List CTree → List SrcArm → Prop
  | nil : ArmsR env scope owner [] [] []
  | cons {v : VariantTy} {vs : List VariantTy} {a : CTree} {as : List CTree} {sa : SrcArm} {sas : List SrcArm} :
      ArmR env scope owner v a sa → ArmsR env scope owner vs as sas → ArmsR env scope owner (v :: vs) (a :: as) (sa :: sas)

theorem armsOf_sound {fuel : Nat} {env : FrontEnv} {scope : List Local} {owner : TypeDecl} :
    ∀ {vs : List VariantTy} {arms : List CTree} {sas : List SrcArm},
      armsOf fuel env scope owner vs arms = some sas → ArmsR env scope owner vs arms sas
  | [], [], sas, h => by
    simp only [armsOf, Option.some.injEq] at h
    subst h
    exact .nil
  | [], _ :: _, _, h => by simp [armsOf] at h
  | _ :: _, [], _, h => by simp [armsOf] at h
  | v :: rest, a :: more, sas, h => by
    simp only [armsOf] at h
    cases ha : armOf fuel env scope owner v a with
    | none => rw [ha] at h; simp [consArm] at h
    | some sa =>
      rw [ha] at h
      cases hr : armsOf fuel env scope owner rest more with
      | none => rw [hr] at h; simp [consArm, consArmTail] at h
      | some sas' =>
        rw [hr] at h
        simp only [consArm, consArmTail, Option.some.injEq] at h
        subst h
        exact .cons (armOf_sound ha) (armsOf_sound hr)

theorem armsNaming_mem {fuel : Nat} {owner : TypeDecl} {name : Name} :
    ∀ {arms : List CTree} {a : CTree}, a ∈ armsNaming fuel owner name arms → a ∈ arms
  | [], a, h => by simp [armsNaming] at h
  | b :: rest, a, h => by
    rw [armsNaming] at h
    unfold armsNamingAt at h
    split at h
    · rcases List.mem_cons.1 h with rfl | h
      · exact List.mem_cons_self
      · exact List.mem_cons_of_mem _ (armsNaming_mem h)
    · exact List.mem_cons_of_mem _ (armsNaming_mem h)

theorem armsByVariant_mem {fuel : Nat} {owner : TypeDecl} {arms : List CTree} :
    ∀ {vs : List VariantTy} {os : List CTree}, armsByVariant fuel owner vs arms = some os → ∀ a ∈ os, a ∈ arms
  | [], os, h => by
    simp only [armsByVariant, Option.some.injEq] at h
    subst h
    simp
  | v :: rest, os, h => by
    rw [armsByVariant] at h
    cases hn : armsNaming fuel owner v.name arms with
    | nil => rw [hn] at h; cases h
    | cons a more =>
      rw [hn] at h
      cases more with
      | cons _ _ => cases h
      | nil =>
        simp only at h
        cases hr : armsByVariant fuel owner rest arms with
        | none => rw [hr] at h; simp [consTreeTail] at h
        | some ts =>
          rw [hr] at h
          simp only [consTreeTail, Option.some.injEq] at h
          subst h
          intro x mem
          rcases List.mem_cons.1 mem with rfl | mem
          · exact armsNaming_mem (by rw [hn]; exact List.mem_cons_self)
          · exact armsByVariant_mem hr x mem

theorem zipVariants_eq : ∀ (ns : List Name) (ps : List (List Ty)), zipVariants ns ps = List.zipWith VariantTy.mk ns ps
  | [], _ => by simp [zipVariants]
  | _ :: _, [] => by simp [zipVariants]
  | n :: rest, p :: more => by simp [zipVariants, zipVariants_eq rest more]

/-- `match x { arms }` with `x` a local of enum type: one arm per variant
(at the local's type arguments), in declaration order. -/
def MatchHeadR (env : FrontEnv) (scope : List Local) (m : CTree) (hd : LetHead) : Prop :=
  ∃ pf l d args t ps arms os sas, Peel (kid m 2) pf ∧ nodeProd (kid pf 1) = pPostfixEnd ∧
    LocalOf scope (kid pf 0) l ∧ l.ty = .tyNamed d args ∧ env.decls.types[d]? = some t ∧ t.isEnum = true ∧
    PayloadTys env.decls d args ps ∧ Items (kid m 5) arms ∧
    arms.length = (List.zipWith VariantTy.mk t.variants ps).length ∧ (∀ a ∈ os, a ∈ arms) ∧
    ArmsR env scope t (List.zipWith VariantTy.mk t.variants ps) os sas ∧ hd = .matchOf l.id l.ty sas

theorem matchHead_sound {fuel : Nat} {env : FrontEnv} {scope : List Local} {m : CTree} {hd : LetHead}
    (h : matchHead fuel env scope m = some hd) : MatchHeadR env scope m hd := by
  unfold matchHead at h
  cases hp : peel fuel (kid m 2) with
  | none => rw [hp] at h; cases h
  | some pf =>
    rw [hp] at h
    simp only [matchScrutinee] at h
    split at h
    · rename_i pe
      cases hl : localOf env scope (kid pf 0) with
      | none => rw [hl] at h; cases h
      | some l =>
        rw [hl] at h
        simp only [matchLocal] at h
        cases hn : namedParts l.ty with
        | none => rw [hn] at h; cases h
        | some n =>
          rw [hn] at h
          simp only at h
          cases ht : env.decls.types[n.decl]? with
          | none => rw [ht] at h; cases h
          | some t =>
            rw [ht] at h
            simp only [matchEnum] at h
            split at h
            · rename_i en
              cases hq : payloadTys fuel env.decls n.decl n.args with
              | none => rw [hq] at h; cases h
              | some ps =>
                rw [hq] at h
                simp only at h
                cases hi : listItems fuel (kid m 5) with
                | none => rw [hi] at h; cases h
                | some arms =>
                  rw [hi] at h
                  simp only at h
                  cases ho : armsOrdered fuel env scope t (zipVariants t.variants ps) arms with
                  | none => rw [ho] at h; simp [matchArms] at h
                  | some sas =>
                    rw [ho] at h
                    simp only [matchArms, Option.some.injEq] at h
                    subst h
                    unfold armsOrdered at ho
                    cases hio : armsInOrder fuel t (zipVariants t.variants ps) arms with
                    | none => rw [hio] at ho; cases ho
                    | some os =>
                      rw [hio] at ho
                      simp only at ho
                      unfold armsInOrder at hio
                      split at hio
                      · rename_i len
                        rw [zipVariants_eq] at len hio ho
                        exact ⟨pf, l, n.decl, n.args, t, ps, arms, os, sas, peel_sound hp, pe, localOf_sound hl,
                          namedParts_eq hn, ht, en, payloadTys_sound hq, listItems_sound hi, len,
                          armsByVariant_mem hio, armsOf_sound ho, rfl⟩
                      · cases hio
            · cases h
    · cases h

/-! ## Let heads -/

/-- `recv.m(args)` with no type arguments, the receiver `self` or a name. -/
def MethodForm (pf : CTree) : Prop :=
  (nodeProd (kid pf 0) = pSelfValue ∨ nodeProd (kid pf 0) = pIdent ∧ nodeProd (kid (kid pf 0) 1) = pIdentPlain) ∧
    nodeProd (kid pf 1) = pPostfixMember ∧ nodeProd (kid (kid pf 1) 2) = pMemberTypeArgsNone ∧
    nodeProd (kid (kid pf 1) 3) = pPostfixCall ∧ nodeProd (kid (kid (kid pf 1) 3) 3) = pPostfixEnd

theorem isMethodForm_sound {pf : CTree} (h : isMethodForm pf = true) : MethodForm pf := by
  simpa [isMethodForm, MethodForm, and_assoc] using h

/-- The head of `let x: ty = init`. -/
inductive LetHeadR (env : FrontEnv) (scope : List Local) (ty : Ty) (init : CTree) : LetHead → Prop
  | plain {e : SrcExpr} : ExprR env scope init e → LetHeadR env scope ty init (.plain e)
  | «match» {pf : CTree} {hd : LetHead} : Peel init pf → nodeProd (kid pf 0) = pMatchExpr →
      nodeProd (kid pf 1) = pPostfixEnd → MatchHeadR env scope (kid pf 0) hd → LetHeadR env scope ty init hd
  | literal {pf : CTree} {hd : LetHead} : Peel init pf → nodeProd (kid pf 0) = pIdent →
      nodeProd (kid (kid pf 0) 1) = pStructLit → nodeProd (kid pf 1) = pPostfixEnd →
      LiteralHeadR env scope ty (kid (kid pf 0) 0) (kid (kid (kid pf 0) 1) 1) hd → LetHeadR env scope ty init hd
  | callPath {pf : CTree} {hd : LetHead} : Peel init pf → nodeProd (kid pf 0) = pIdent →
      nodeProd (kid (kid pf 0) 1) = pIdentPlain → nodeProd (kid pf 1) = pPostfixCall →
      nodeProd (kid (kid pf 1) 3) = pPostfixEnd → CallPathHeadR env scope ty (kid (kid pf 0) 0) (kid (kid pf 1) 1) hd →
      LetHeadR env scope ty init hd
  | method {pf : CTree} {c : Called} : Peel init pf → MethodForm pf → MethodCallOf env scope ty pf c →
      LetHeadR env scope ty init (.callOf c)
  | index {pf : CTree} {l : Local} {i : SrcExpr} : Peel init pf → nodeProd (kid pf 0) = pIdent →
      nodeProd (kid (kid pf 0) 1) = pIdentPlain → nodeProd (kid pf 1) = pPostfixIndex →
      nodeProd (kid (kid pf 1) 3) = pPostfixEnd → LocalOf scope (kid pf 0) l → ExprR env scope (kid (kid pf 1) 1) i →
      LetHeadR env scope ty init (.indexOf l.id i)
  | unit {pf : CTree} {ss : List Name} {front : ModPath} {name : Name} {v : VariantAt} {hd : LetHead} :
      Peel init pf → nodeProd (kid pf 0) = pIdent → nodeProd (kid (kid pf 0) 1) = pIdentPlain →
      nodeProd (kid pf 1) = pPostfixEnd → PathSpellings (kid (kid (kid pf 0) 0) 0) (kid (kid (kid pf 0) 0) 1) ss →
      ss = front ++ [name] → VariantByPath env front name v → VariantHeadR ty v [] [] hd → LetHeadR env scope ty init hd

theorem plainHead_sound {fuel : Nat} {env : FrontEnv} {scope : List Local} {ty : Ty} {init : CTree} {hd : LetHead}
    (h : plainHead (exprOf fuel env scope init) = some hd) : LetHeadR env scope ty init hd := by
  obtain ⟨e, he, rfl⟩ := plainHead_some h
  exact .plain (exprOf_sound he)

theorem postfixHead_sound {fuel : Nat} {env : FrontEnv} {scope : List Local} {ty : Ty} {pf init : CTree}
    {hd : LetHead} (pe : Peel init pf) (h : postfixHead fuel env scope ty pf init = some hd) :
    LetHeadR env scope ty init hd := by
  unfold postfixHead at h
  simp only at h
  split at h
  · rename_i c
    simp only [Bool.and_eq_true, decide_eq_true_eq] at c
    exact .match pe c.1 c.2 (matchHead_sound h)
  · split at h
    · rename_i c
      simp only [Bool.and_eq_true, decide_eq_true_eq, and_assoc] at c
      exact .literal pe c.1 c.2.1 c.2.2 (literalHead_sound h)
    · split at h
      · rename_i c
        simp only [isPathCall, Bool.and_eq_true, decide_eq_true_eq, and_assoc] at c
        exact .callPath pe c.1 c.2.1 c.2.2.1 c.2.2.2 (callPathHead_sound h)
      · split at h
        · rename_i c
          cases hm : methodCallOf fuel env scope ty pf with
          | none => rw [hm] at h; simp [callHeadOf] at h
          | some m =>
            rw [hm] at h
            simp only [callHeadOf, Option.some.injEq] at h
            subst h
            exact .method pe (isMethodForm_sound c) (methodCallOf_sound hm)
        · split at h
          · rename_i c
            simp only [Bool.and_eq_true, decide_eq_true_eq, and_assoc] at c
            cases hl : localOf env scope (kid pf 0) with
            | none => rw [hl] at h; simp [indexHead] at h
            | some l =>
              rw [hl] at h
              cases hi : exprOf fuel env scope (kid (kid pf 1) 1) with
              | none => rw [hi] at h; simp [indexHead] at h
              | some i =>
                rw [hi] at h
                simp only [indexHead, Option.some.injEq] at h
                subst h
                exact .index pe c.1 c.2.1 c.2.2.1 c.2.2.2 (localOf_sound hl) (exprOf_sound hi)
          · split at h
            · rename_i c
              simp only [Bool.and_eq_true, decide_eq_true_eq, and_assoc] at c
              unfold unitHead at h
              cases hs : pathSpellings fuel (kid (kid (kid pf 0) 0) 0) (kid (kid (kid pf 0) 0) 1) with
              | none => rw [hs] at h; exact plainHead_sound h
              | some ss =>
                rw [hs] at h
                simp only at h
                cases hl : splitLast ss with
                | none => rw [hl] at h; cases h
                | some s =>
                  rw [hl] at h
                  simp only at h
                  cases hv : variantByPath env s with
                  | none => rw [hv] at h; exact plainHead_sound h
                  | some v =>
                    rw [hv] at h
                    simp only at h
                    exact .unit pe c.1 c.2.1 c.2.2 (pathSpellings_sound hs) (splitLast_sound hl)
                      (variantByPath_sound hv) (variantHead_sound h)
            · exact plainHead_sound h

theorem letHead_sound {fuel : Nat} {env : FrontEnv} {scope : List Local} {ty : Ty} {init : CTree} {hd : LetHead}
    (h : letHead fuel env scope ty init = some hd) : LetHeadR env scope ty init hd := by
  unfold letHead at h
  cases hp : peel fuel init with
  | none => rw [hp] at h; exact plainHead_sound h
  | some pf =>
    rw [hp] at h
    exact postfixHead_sound (peel_sound hp) h

end Lanius.Mini.Reading
