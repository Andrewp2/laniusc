module

public import Lanius.Mini.Reading.LetHeads
import all Lanius.Mini.Compiler.P.SrcType_uintKind
import all Lanius.Mini.Compiler.P.arithShiftRight
import all Lanius.Mini.Frontend.P.anyNested
import all Lanius.Mini.Frontend.P.armsOf
import all Lanius.Mini.Frontend.P.consBinder
import all Lanius.Mini.Frontend.P.consTreeTail
import all Lanius.Mini.Frontend.P.hasKids
import all Lanius.Mini.Frontend.P.isEmptyUsize
import all Lanius.Mini.Frontend.P.isUnderscore
import all Lanius.Mini.Frontend.P.namesSome
import all Lanius.Mini.Frontend.P.shadowUse
import all Lanius.Mini.Frontend.P.nestedUsed
import all Lanius.Mini.Frontend.P.noBlock
import all Lanius.Mini.Frontend.P.noToken
import all Lanius.Mini.Frontend.P.noTrees
import all Lanius.Mini.Frontend.P.plainNaming
import all Lanius.Mini.Frontend.P.repeatEff
import all Lanius.Mini.Frontend.P.shrFirst
import all Lanius.Mini.Frontend.P.variantArm
import all Lanius.Mini.Frontend.P.setPlaceOf
import all Lanius.Mini.Frontend.P.setFieldOrEval
import all Lanius.Mini.Frontend.P.primaryNames
import all Lanius.Mini.Frontend.P.isFnPath
import all Lanius.Mini.Frontend.P.fieldValue
import all Lanius.Mini.Frontend.P.eDerefClosed
import all Lanius.Mini.Frontend.P.checkedFunc

@[expose] public section
/-! # The reading, F11: nested patterns

A match expression with a nested arm, one whose payload patterns are not all
plain binders (`Ok(Some(x))`, `Pair(Bar::X(a), b)`), is read as nested
matches (`MatchOrder`, `NestedOrder`). Variant V's arm is (`VariantArm`):

* the wildcard's, `V(_, ..) -> value`, when no arm names V;
* V's one written arm, when it is plain;
* otherwise `V(b, .., h, ..) -> match (h) { p -> value, .. }` (`nestArm`):
  the arms naming V (`Rows`), in order, matched on the first arm's first
  column j that is not a binder. Every other column of every such arm is a
  binder spelled as the first arm's (`rowFits`), so the values mean what they
  mean where they are written. Each arm gives the inner match its pattern p at
  j with its value (`ColumnArms`); the last arm may bind a name at j that its
  value spells nowhere (`Mentions`), read as `_`. Then the wildcard, unless
  an inner arm is `_` already or the inner arms name every variant of h's enum
  with plain binders (`Covers`); the wildcard goes in only when its value
  spells none of the first arm's other binders (`ColsQuiet`), so binding them
  does not change what it means. h is a binder no source can spell (`[0]`),
  numbered by the first arm's pattern at j.

Every arm names some variant, the wildcard is used, and no arm's value is a
block `{ .. }` (`BlockValue`, which a match statement reads). The inner match
is read again by the effectful reading, nested or not. -/

namespace Lanius.Mini.Reading

open Lanius.Mini Lanius.Mini.Prod

/-! ## Known booleans -/

theorem orKnown_some {a b : Option Bool} {x : Bool} (h : orKnown a b = some x) :
    ∃ y z, a = some y ∧ b = some z ∧ x = (y || z) := by
  cases a with
  | none => simp [orKnown] at h
  | some y =>
    cases b with
    | none => simp [orKnown] at h
    | some z =>
      simp only [orKnown, Option.some.injEq] at h
      exact ⟨y, z, rfl, rfl, h.symm⟩

theorem andKnown_some {a b : Option Bool} {x : Bool} (h : andKnown a b = some x) :
    ∃ y z, a = some y ∧ b = some z ∧ x = (y && z) := by
  cases a with
  | none => simp [andKnown] at h
  | some y =>
    cases b with
    | none => simp [andKnown] at h
    | some z =>
      simp only [andKnown, Option.some.injEq] at h
      exact ⟨y, z, rfl, rfl, h.symm⟩

theorem notKnown_some {a : Option Bool} {x : Bool} (h : notKnown a = some x) : a = some (!x) := by
  cases a with
  | none => simp [notKnown] at h
  | some y =>
    simp only [notKnown, Option.some.injEq] at h
    subst h
    simp

/-! ## Spelling a name -/

/-- Some token of the tree is spelled `n`. -/
inductive Mentions (n : Name) : CTree → Prop
  | leaf {tok : Token} : tok.text = n → Mentions n (.leaf tok)
  | node {p : Nat} {kids : List CTree} {c : CTree} : c ∈ kids → Mentions n c → Mentions n (.node p kids)

theorem mentions_false : ∀ {fuel : Nat} {todo : List CTree} {n : Name},
    mentions fuel todo n = some false → ∀ t ∈ todo, ¬Mentions n t
  | 0, _, _, h, _, _ => by unfold mentions at h; simp at h
  | _ + 1, [], _, _, _, m => by cases m
  | f + 1, .leaf tok :: rest, n, h, t, m => by
    unfold mentions at h
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
    obtain ⟨y, z, ey, ez, e⟩ := orKnown_some h
    simp only [Option.some.injEq] at ey
    obtain ⟨hy, hz⟩ := Bool.or_eq_false_iff.1 e.symm
    subst hy hz
    rcases List.mem_cons.1 m with rfl | m
    · intro hm
      cases hm with
      | leaf e' => rw [(sameText_iff _ _).2 e'] at ey; cases ey
    · exact mentions_false ez t m
  | f + 1, .node q kids :: rest, n, h, t, m => by
    unfold mentions at h
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
    rcases List.mem_cons.1 m with rfl | m
    · intro hm
      cases hm with
      | node mc hc => exact mentions_false h _ (List.mem_append_left _ mc) hc
    · exact mentions_false h t (List.mem_append_right _ m)

theorem quietIn_true {fuel : Nat} {name : Option Name} {value : CTree} (h : quietIn fuel name value = some true) :
    ∃ n, name = some n ∧ ¬Mentions n value := by
  cases name with
  | none => simp [quietIn] at h
  | some n =>
    simp only [quietIn] at h
    exact ⟨n, rfl, mentions_false (notKnown_some h) value List.mem_cons_self⟩

/-- The value spells none of the binders `pa` has off column j. -/
def ColsQuiet (pa : List CTree) (j : Nat) (value : CTree) : Prop :=
  ∀ i x, i ≠ j → pa[i]? = some x → ∃ n, pathName (kid x 0) = some n ∧ ¬Mentions n value

theorem colsQuiet_true : ∀ {fuel : Nat} {pa : List CTree} {i j : Nat} {value : CTree},
    colsQuiet fuel pa i j value = some true →
      ∀ k x, k + i ≠ j → pa[k]? = some x → ∃ n, pathName (kid x 0) = some n ∧ ¬Mentions n value
  | _, [], _, _, _, _, _, _, _, hx => by simp at hx
  | fuel, y :: rest, i, j, value, h, k, x, ne, hx => by
    simp only [colsQuiet] at h
    obtain ⟨a, b, ea, eb, e⟩ := andKnown_some h
    obtain ⟨ha, hb⟩ := Bool.and_eq_true_iff.1 e.symm
    subst ha hb
    cases k with
    | zero =>
      simp only [List.getElem?_cons_zero, Option.some.injEq] at hx
      subst hx
      unfold colQuiet at ea
      rw [if_neg (by simpa using ne)] at ea
      exact quietIn_true ea
    | succ k =>
      exact colsQuiet_true eb k x (by omega) (by simpa using hx)

theorem colsQuiet_sound {fuel : Nat} {pa : List CTree} {j : Nat} {value : CTree}
    (h : colsQuiet fuel pa 0 j value = some true) : ColsQuiet pa j value :=
  fun i x ne hx => colsQuiet_true h i x (by simpa using ne) hx

/-! ## Rows -/

/-- Arm r's payload patterns: `V(p, ...) -> value`. -/
def RowPats (r : CTree) (ps : List CTree) : Prop :=
  nodeProd (kid r 0) = pPatternIdent ∧ nodeProd (kid (kid r 0) 1) ≠ pPatternPlain ∧ Items (kid (kid (kid r 0) 1) 1) ps

/-- Arm a is nested: a payload pattern of it is not a plain binder. -/
def Nested (env : FrontEnv) (a : CTree) : Prop :=
  ∃ ps, RowPats a ps ∧ allBinders env ps = false

theorem rowPats_unique {r : CTree} {ps qs : List CTree} (h₁ : RowPats r ps) (h₂ : RowPats r qs) : ps = qs :=
  items_unique h₁.2.2 h₂.2.2

theorem rowPats_sound {fuel : Nat} {r : CTree} {ps : List CTree} (h : rowPats fuel r = some ps) : RowPats r ps := by
  unfold rowPats at h
  dsimp only at h
  split at h
  · rename_i c
    simp only [Bool.and_eq_true, decide_eq_true_eq] at c
    exact ⟨c.1, c.2, listItems_sound h⟩
  · cases h

theorem armNested_sound {fuel : Nat} {env : FrontEnv} {a : CTree} {b : Bool} (h : armNested fuel env a = some b) :
    Nested env a ↔ b = true := by
  unfold armNested at h
  dsimp only at h
  split at h
  · rename_i c
    simp only [Bool.and_eq_true, decide_eq_true_eq] at c
    cases hi : listItems fuel (kid (kid (kid a 0) 1) 1) with
    | none => rw [hi] at h; simp [patsNested] at h
    | some ps =>
      rw [hi] at h
      simp only [patsNested, Option.some.injEq] at h
      subst h
      have it := listItems_sound hi
      constructor
      · rintro ⟨ps', ⟨_, _, it'⟩, ab⟩
        rw [items_unique it it', ab]
        rfl
      · intro e
        exact ⟨ps, ⟨c.1, c.2, it⟩, by simpa using e⟩
  · rename_i c
    simp only [Option.some.injEq] at h
    subst h
    simp only [Bool.and_eq_true, decide_eq_true_eq, not_and, Decidable.not_not] at c
    constructor
    · rintro ⟨_, ⟨p1, p2, _⟩, _⟩
      exact absurd (c p1) p2
    · intro e
      cases e

theorem anyNested_sound : ∀ {fuel : Nat} {env : FrontEnv} {arms : List CTree} {b : Bool},
    anyNested fuel env arms = some b → ((∃ a ∈ arms, Nested env a) ↔ b = true)
  | _, _, [], b, h => by
    simp only [anyNested, Option.some.injEq] at h
    subst h
    simp
  | fuel, env, a :: rest, b, h => by
    simp only [anyNested] at h
    obtain ⟨y, z, ey, ez, e⟩ := orKnown_some h
    subst e
    have ha := armNested_sound ey
    have hr := anyNested_sound ez
    simp only [List.mem_cons, exists_eq_or_imp, Bool.or_eq_true]
    rw [ha, hr]

/-- Arm a's path names variant n of `owner` (b) or not. -/
def ArmNaming (owner : TypeDecl) (n : Name) (a : CTree) (b : Bool) : Prop :=
  ∃ ss, PathSpellings (kid (kid (kid a 0) 0) 0) (kid (kid (kid a 0) 0) 1) ss ∧ armNamed (some ss) owner n = b

theorem armNaming_unique {owner : TypeDecl} {n : Name} {a : CTree} {b b' : Bool}
    (h₁ : ArmNaming owner n a b) (h₂ : ArmNaming owner n a b') : b = b' := by
  obtain ⟨ss, p, e⟩ := h₁
  obtain ⟨ss', p', e'⟩ := h₂
  rw [pathSpellings_unique p p'] at e
  rw [← e, ← e']

theorem armNaming_sound {fuel : Nat} {owner : TypeDecl} {n : Name} {a : CTree} {b : Bool}
    (h : armNaming fuel owner n a = some b) : ArmNaming owner n a b := by
  unfold armNaming at h
  dsimp only at h
  cases hp : pathSpellings fuel (kid (kid (kid a 0) 0) 0) (kid (kid (kid a 0) 0) 1) with
  | none => rw [hp] at h; simp [namedKnown] at h
  | some ss =>
    rw [hp] at h
    simp only [namedKnown, Option.some.injEq] at h
    exact ⟨ss, pathSpellings_sound hp, h⟩

/-- The arms that name variant n, in order. -/
inductive Rows (owner : TypeDecl) (n : Name) : List CTree → List CTree → Prop
  | nil : Rows owner n [] []
  | yes {a : CTree} {arms rs : List CTree} : ArmNaming owner n a true → Rows owner n arms rs →
      Rows owner n (a :: arms) (a :: rs)
  | no {a : CTree} {arms rs : List CTree} : ArmNaming owner n a false → Rows owner n arms rs →
      Rows owner n (a :: arms) rs

theorem rows_unique {owner : TypeDecl} {n : Name} : ∀ {arms rs rs' : List CTree},
    Rows owner n arms rs → Rows owner n arms rs' → rs = rs'
  | _, _, _, .nil, .nil => rfl
  | _, _, _, .yes _ r, .yes _ r' => by rw [rows_unique r r']
  | _, _, _, .no _ r, .no _ r' => rows_unique r r'
  | _, _, _, .yes y _, .no y' _ => by cases armNaming_unique y y'
  | _, _, _, .no y _, .yes y' _ => by cases armNaming_unique y y'

theorem rowsNaming_sound : ∀ {fuel : Nat} {owner : TypeDecl} {n : Name} {arms rs : List CTree},
    rowsNaming fuel owner n arms = some rs → Rows owner n arms rs
  | _, _, _, [], rs, h => by
    simp only [rowsNaming, Option.some.injEq] at h
    subst h
    exact .nil
  | fuel, owner, n, a :: rest, rs, h => by
    simp only [rowsNaming] at h
    cases ha : armNaming fuel owner n a with
    | none => rw [ha] at h; simp [rowCons] at h
    | some b =>
      rw [ha] at h
      cases hr : rowsNaming fuel owner n rest with
      | none => rw [hr] at h; simp [rowCons] at h
      | some r =>
        rw [hr] at h
        simp only [rowCons, Option.some.injEq] at h
        subst h
        cases b with
        | true =>
          simp only [armsNamingAt, if_true]
          exact .yes (armNaming_sound ha) (rowsNaming_sound hr)
        | false =>
          simp only [armsNamingAt, Bool.false_eq_true, if_false]
          exact .no (armNaming_sound ha) (rowsNaming_sound hr)

/-! ## The inner match's arms -/

/-- Row r's inner arm at its pattern p: p, or `_` for a binder its value
does not spell. -/
inductive ColumnSub (env : FrontEnv) (r p : CTree) : CTree → Prop
  | pat : isBinderPat env p = false → ColumnSub env r p (subArm r p)
  | quiet {n : Name} : isBinderPat env p = true → pathName (kid p 0) = some n → ¬Mentions n (kid r 2) →
      ColumnSub env r p (subArm r (wildPat p))

/-- The inner arms from the rows, matched on column j. -/
inductive ColumnArms (env : FrontEnv) (pa : List CTree) (j : Nat) : List CTree → List CTree → Prop
  | nil : ColumnArms env pa j [] []
  | cons {r p s : CTree} {rest ps inner : List CTree} : RowPats r ps → ps[j]? = some p →
      rowFits env pa ps 0 j (isLast rest) = true → ColumnSub env r p s → ColumnArms env pa j rest inner →
      ColumnArms env pa j (r :: rest) (s :: inner)

theorem columnSub_unique {env : FrontEnv} {r p s s' : CTree} (h₁ : ColumnSub env r p s) (h₂ : ColumnSub env r p s') :
    s = s' := by
  cases h₁ with
  | pat b => cases h₂ with
    | pat _ => rfl
    | quiet b' _ _ => rw [b] at b'; cases b'
  | quiet b _ _ => cases h₂ with
    | pat b' => rw [b] at b'; cases b'
    | quiet _ _ _ => rfl

theorem columnArms_unique {env : FrontEnv} {pa : List CTree} {j : Nat} : ∀ {rows base base' : List CTree},
    ColumnArms env pa j rows base → ColumnArms env pa j rows base' → base = base'
  | _, _, _, .nil, .nil => rfl
  | _, _, _, .cons rp pj _ cs rest, .cons rp' pj' _ cs' rest' => by
    cases rowPats_unique rp rp'
    rw [pj] at pj'
    cases pj'
    rw [columnSub_unique cs cs', columnArms_unique rest rest']

theorem columnSub_sound {fuel : Nat} {env : FrontEnv} {r p s : CTree} (h : columnSub fuel env r p = some s) :
    ColumnSub env r p s := by
  unfold columnSub at h
  split at h
  · rename_i b
    unfold quietSub at h
    cases hq : quietIn fuel (pathName (kid p 0)) (kid r 2) with
    | none => rw [hq] at h; simp at h
    | some q =>
      rw [hq] at h
      simp only at h
      unfold quietArm at h
      split at h
      · rename_i e
        subst e
        simp only [Option.some.injEq] at h
        subst h
        obtain ⟨n, hn, nm⟩ := quietIn_true hq
        exact .quiet b hn nm
      · cases h
  · rename_i b
    simp only [Option.some.injEq] at h
    subst h
    exact .pat (by simpa using b)

theorem columnArms_sound : ∀ {fuel : Nat} {env : FrontEnv} {pa : List CTree} {j : Nat} {rows base : List CTree},
    columnArms fuel env pa j rows = some base → ColumnArms env pa j rows base
  | _, _, _, _, [], base, h => by
    simp only [columnArms, Option.some.injEq] at h
    subst h
    exact .nil
  | fuel, env, pa, j, r :: rest, base, h => by
    simp only [columnArms] at h
    unfold columnArm at h
    cases hp : rowPats fuel r with
    | none => rw [hp] at h; simp at h
    | some ps =>
      rw [hp] at h
      simp only at h
      cases hj : ps[j]? with
      | none => rw [hj] at h; simp at h
      | some p =>
        rw [hj] at h
        simp only at h
        unfold columnFit at h
        split at h
        · rename_i fits
          cases hs : columnSub fuel env r p with
          | none => rw [hs] at h; simp at h
          | some s =>
            rw [hs] at h
            simp only at h
            cases hr : columnArms fuel env pa j rest with
            | none => rw [hr] at h; simp [consTreeTail] at h
            | some inner =>
              rw [hr] at h
              simp only [consTreeTail, Option.some.injEq] at h
              subst h
              exact .cons (rowPats_sound hp) hj fits (columnSub_sound hs) (columnArms_sound hr)
        · cases h

/-! ## Covering the column's enum -/

/-- Inner arms naming every variant of ty's enum, each with plain binders. -/
def Covers (env : FrontEnv) (ty : Ty) (inner : List CTree) : Prop :=
  ∃ n t, namedParts ty = some n ∧ env.decls.types[n.decl]? = some t ∧ t.isEnum = true ∧
    ∀ u ∈ t.variants, ∃ ia ∈ inner, ArmNaming t u ia true ∧ ¬Nested env ia

theorem plainNaming_sound {fuel : Nat} {env : FrontEnv} {t : TypeDecl} {u : Name} {ia : CTree} {b : Bool}
    (h : plainNaming fuel env t u ia = some b) : (ArmNaming t u ia true ∧ ¬Nested env ia) ↔ b = true := by
  unfold plainNaming at h
  obtain ⟨y, z, ey, ez, e⟩ := andKnown_some h
  subst e
  have an := armNaming_sound ey
  have nz := armNested_sound (notKnown_some ez)
  rw [nz]
  constructor
  · rintro ⟨an', nn⟩
    cases armNaming_unique an an'
    cases z <;> simp_all
  · intro e
    simp only [Bool.and_eq_true] at e
    obtain ⟨rfl, rfl⟩ := e
    exact ⟨an, by simp⟩

theorem coveredBy_sound : ∀ {fuel : Nat} {env : FrontEnv} {t : TypeDecl} {u : Name} {inner : List CTree} {b : Bool},
    coveredBy fuel env t u inner = some b → ((∃ ia ∈ inner, ArmNaming t u ia true ∧ ¬Nested env ia) ↔ b = true)
  | _, _, _, _, [], b, h => by
    simp only [coveredBy, Option.some.injEq] at h
    subst h
    simp
  | fuel, env, t, u, ia :: rest, b, h => by
    simp only [coveredBy] at h
    obtain ⟨y, z, ey, ez, e⟩ := orKnown_some h
    subst e
    simp only [List.mem_cons, exists_eq_or_imp, Bool.or_eq_true]
    rw [plainNaming_sound ey, coveredBy_sound ez]

theorem coversAll_sound : ∀ {fuel : Nat} {env : FrontEnv} {t : TypeDecl} {names : List Name} {inner : List CTree}
    {b : Bool}, coversAll fuel env t names inner = some b →
      ((∀ u ∈ names, ∃ ia ∈ inner, ArmNaming t u ia true ∧ ¬Nested env ia) ↔ b = true)
  | _, _, _, [], _, b, h => by
    simp only [coversAll, Option.some.injEq] at h
    subst h
    simp
  | fuel, env, t, u :: rest, inner, b, h => by
    simp only [coversAll] at h
    obtain ⟨y, z, ey, ez, e⟩ := andKnown_some h
    subst e
    simp only [List.mem_cons, forall_eq_or_imp, Bool.and_eq_true]
    rw [coveredBy_sound ey, coversAll_sound ez]

theorem covers_sound {fuel : Nat} {env : FrontEnv} {ty : Ty} {inner : List CTree} {b : Bool}
    (h : covers fuel env ty inner = some b) : Covers env ty inner ↔ b = true := by
  unfold covers at h
  cases hn : namedParts ty with
  | none =>
    rw [hn] at h
    simp only [Option.some.injEq] at h
    subst h
    simp only [Bool.false_eq_true, iff_false]
    rintro ⟨n, _, hn', _⟩
    rw [hn] at hn'
    cases hn'
  | some n =>
    rw [hn] at h
    simp only at h
    unfold coversDecl at h
    cases ht : env.decls.types[n.decl]? with
    | none =>
      rw [ht] at h
      simp only [Option.some.injEq] at h
      subst h
      simp only [Bool.false_eq_true, iff_false]
      rintro ⟨n', _, hn', ht', _⟩
      rw [hn] at hn'
      cases hn'
      rw [ht] at ht'
      cases ht'
    | some d =>
      rw [ht] at h
      simp only at h
      unfold coversEnum at h
      split at h
      · rename_i en
        rw [← coversAll_sound h]
        constructor
        · rintro ⟨n', t', hn', ht', _, all⟩
          rw [hn] at hn'
          cases hn'
          rw [ht] at ht'
          cases ht'
          exact all
        · intro all
          exact ⟨n, d, hn, ht, en, all⟩
      · rename_i en
        simp only [Option.some.injEq] at h
        subst h
        simp only [Bool.false_eq_true, iff_false]
        rintro ⟨n', t', hn', ht', en', _⟩
        rw [hn] at hn'
        cases hn'
        rw [ht] at ht'
        cases ht'
        exact en en'

/-! ## A variant's arm -/

/-- The inner arms after the rows' (`base`): none without a wildcard, or
when an inner arm is `_` or the rows cover the column's enum; else the
wildcard, its value spelling none of the first row's other binders. Also
whether the wildcard is used. -/
inductive InnerTail (env : FrontEnv) (pa : List CTree) (j : Nat) (ty : Ty) (base : List CTree) :
    Option CTree → List CTree → Bool → Prop
  | none : InnerTail env pa j ty base none base false
  | ends {w : CTree} : endsWild base = true → InnerTail env pa j ty base (some w) base false
  | covered {w : CTree} : endsWild base = false → Covers env ty base → InnerTail env pa j ty base (some w) base false
  | wild {w : CTree} : endsWild base = false → ¬Covers env ty base → ColsQuiet pa j (kid w 2) →
      InnerTail env pa j ty base (some w) (base ++ [w]) true

theorem innerTail_unique {env : FrontEnv} {pa : List CTree} {j : Nat} {ty : Ty} {base : List CTree}
    {w : Option CTree} {ins ins' : List CTree} {u u' : Bool}
    (h₁ : InnerTail env pa j ty base w ins u) (h₂ : InnerTail env pa j ty base w ins' u') : ins = ins' ∧ u = u' := by
  cases h₁ with
  | none => cases h₂ with
    | none => exact ⟨rfl, rfl⟩
  | ends e => cases h₂ with
    | ends _ => exact ⟨rfl, rfl⟩
    | covered e' _ => rw [e] at e'; cases e'
    | wild e' _ _ => rw [e] at e'; cases e'
  | covered e c => cases h₂ with
    | ends e' => rw [e] at e'; cases e'
    | covered _ _ => exact ⟨rfl, rfl⟩
    | wild _ c' _ => exact absurd c c'
  | wild e c _ => cases h₂ with
    | ends e' => rw [e] at e'; cases e'
    | covered _ c' => exact absurd c' c
    | wild _ _ _ => exact ⟨rfl, rfl⟩

theorem nestInner_sound {fuel : Nat} {env : FrontEnv} {a : CTree} {pa : List CTree} {j : Nat} {p : CTree} {ty : Ty}
    {base : List CTree} {w : Option CTree} {x : ArmUse} (h : nestInner fuel env a pa j p ty (some base) w = some x) :
    ∃ ins, InnerTail env pa j ty base w ins x.used ∧ x.arm = nestArm a pa j p ins := by
  unfold nestInner at h
  cases w with
  | none =>
    simp only [Option.some.injEq] at h
    subst h
    exact ⟨base, .none, rfl⟩
  | some w =>
    simp only at h
    unfold wildInner at h
    split at h
    · rename_i e
      simp only [Option.some.injEq] at h
      subst h
      exact ⟨base, .ends e, rfl⟩
    · rename_i e
      simp only [Bool.not_eq_true] at e
      unfold knownUse at h
      cases hc : covers fuel env ty base with
      | none => rw [hc] at h; simp at h
      | some c =>
        rw [hc] at h
        simp only at h
        unfold coveredUse at h
        split at h
        · rename_i ec
          subst ec
          simp only [Option.some.injEq] at h
          subst h
          exact ⟨base, .covered e ((covers_sound hc).2 rfl), rfl⟩
        · rename_i ec
          unfold quietUse at h
          cases hq : colsQuiet fuel pa 0 j (kid w 2) with
          | none => rw [hq] at h; simp at h
          | some q =>
            rw [hq] at h
            simp only at h
            unfold appendedUse at h
            split at h
            · rename_i eq
              subst eq
              simp only [Option.some.injEq] at h
              subst h
              exact ⟨base ++ [w], .wild e (fun cv => ec ((covers_sound hc).1 cv)) (colsQuiet_sound hq), rfl⟩
            · cases h

/-- Variant v's arm, and whether it is or holds the wildcard `w`, from the
arms `init` (the wildcard's not among them). -/
inductive VariantArm (env : FrontEnv) (owner : TypeDecl) (init : List CTree) (w : Option CTree) (v : VariantTy) :
    CTree → Bool → Prop
  | wild {x : CTree} : Rows owner v.name init [] → w = some x → VariantArm env owner init w v (wildArmFor x v) true
  | plain {a : CTree} : Rows owner v.name init [a] → ¬Nested env a → VariantArm env owner init w v a false
  /-- V's first arm a is plain and a later one nested: a matches every value
  of V, so the later arms never run (laniusc accepts them); they are not
  read. -/
  | shadow {a : CTree} {more : List CTree} : Rows owner v.name init (a :: more) → ¬Nested env a →
      (∃ b ∈ more, Nested env b) → VariantArm env owner init w v a false
  | nested {a p : CTree} {more pa base ins : List CTree} {j : Nat} {ty : Ty} {u : Bool} :
      Rows owner v.name init (a :: more) → RowPats a pa → firstNested env pa 0 = some j → pa[j]? = some p →
      v.payload[j]? = some ty → ColumnArms env pa j (a :: more) base → InnerTail env pa j ty base w ins u →
      VariantArm env owner init w v (nestArm a pa j p ins) u

theorem firstNested_some {env : FrontEnv} : ∀ {pa : List CTree} {i j : Nat},
    firstNested env pa i = some j → allBinders env pa = false
  | [], _, _, h => by simp [firstNested] at h
  | p :: rest, i, j, h => by
    simp only [firstNested] at h
    unfold firstAt at h
    simp only [allBinders, Bool.and_eq_false_iff]
    split at h
    · exact .inr (firstNested_some h)
    · rename_i b
      exact .inl (by simpa using b)

theorem variantArm_unique {env : FrontEnv} {owner : TypeDecl} {init : List CTree} {w : Option CTree} {v : VariantTy}
    {o o' : CTree} {u u' : Bool} (h₁ : VariantArm env owner init w v o u) (h₂ : VariantArm env owner init w v o' u') :
    o = o' ∧ u = u' := by
  cases h₁ with
  | wild r e => cases h₂ with
    | wild _ e' => rw [e] at e'; cases e'; exact ⟨rfl, rfl⟩
    | plain r' _ => cases rows_unique r r'
    | shadow r' _ _ => cases rows_unique r r'
    | nested r' _ _ _ _ _ _ => cases rows_unique r r'
  | plain r nn => cases h₂ with
    | wild r' _ => cases rows_unique r r'
    | plain r' _ => cases rows_unique r r'; exact ⟨rfl, rfl⟩
    | shadow r' _ sb =>
      cases rows_unique r r'
      obtain ⟨_, mb, _⟩ := sb
      cases mb
    | nested r' rp fn _ _ _ _ =>
      cases rows_unique r r'
      exact (nn ⟨_, rp, firstNested_some fn⟩).elim
  | shadow r nn sb => cases h₂ with
    | wild r' _ => cases rows_unique r r'
    | plain r' _ =>
      cases rows_unique r r'
      obtain ⟨_, mb, _⟩ := sb
      cases mb
    | shadow r' _ _ => cases rows_unique r r'; exact ⟨rfl, rfl⟩
    | nested r' rp fn _ _ _ _ =>
      cases rows_unique r r'
      exact (nn ⟨_, rp, firstNested_some fn⟩).elim
  | nested r rp fn pj vj ca it => cases h₂ with
    | wild r' _ => cases rows_unique r r'
    | plain r' nn =>
      cases rows_unique r r'
      exact (nn ⟨_, rp, firstNested_some fn⟩).elim
    | shadow r' nn _ =>
      cases rows_unique r r'
      exact (nn ⟨_, rp, firstNested_some fn⟩).elim
    | nested r' rp' fn' pj' vj' ca' it' =>
      cases rows_unique r r'
      cases rowPats_unique rp rp'
      rw [fn] at fn'
      cases fn'
      rw [pj] at pj'
      cases pj'
      rw [vj] at vj'
      cases vj'
      cases columnArms_unique ca ca'
      obtain ⟨rfl, rfl⟩ := innerTail_unique it it'
      exact ⟨rfl, rfl⟩

theorem variantArm_sound {fuel : Nat} {env : FrontEnv} {owner : TypeDecl} {init : List CTree} {w : Option CTree}
    {v : VariantTy} {x : ArmUse} (h : variantArm fuel env v (rowsNaming fuel owner v.name init) w = some x) :
    VariantArm env owner init w v x.arm x.used := by
  unfold variantArm at h
  cases hr : rowsNaming fuel owner v.name init with
  | none => rw [hr] at h; simp at h
  | some rs =>
    rw [hr] at h
    have rows := rowsNaming_sound hr
    simp only at h
    cases rs with
    | nil =>
      unfold wildUse at h
      cases w with
      | none => simp at h
      | some y =>
        simp only [Option.some.injEq] at h
        subst h
        exact .wild rows rfl
    | cons a more =>
      simp only at h
      unfold rowsUse at h
      cases hn : armNested fuel env a with
      | none => rw [hn] at h; simp at h
      | some n =>
        rw [hn] at h
        simp only at h
        unfold nestedOrPlain at h
        split at h
        · rename_i en
          subst en
          unfold nestUse at h
          cases hp : rowPats fuel a with
          | none => rw [hp] at h; simp at h
          | some pa =>
            rw [hp] at h
            simp only at h
            unfold nestPats at h
            cases hf : firstNested env pa 0 with
            | none => rw [hf] at h; simp at h
            | some j =>
              rw [hf] at h
              simp only at h
              unfold nestAt at h
              cases hj : pa[j]? with
              | none => rw [hj] at h; simp at h
              | some p =>
                rw [hj] at h
                simp only at h
                cases hv : v.payload[j]? with
                | none => rw [hv] at h; simp at h
                | some ty =>
                  rw [hv] at h
                  simp only at h
                  cases hc : columnArms fuel env pa j (a :: more) with
                  | none => rw [hc] at h; simp [nestInner] at h
                  | some base =>
                    rw [hc] at h
                    obtain ⟨ins, it, e⟩ := nestInner_sound h
                    rw [e]
                    exact .nested rows (rowPats_sound hp) hf hj hv (columnArms_sound hc) it
        · rename_i en
          simp only [Bool.not_eq_true] at en
          subst en
          unfold plainUse at h
          cases more with
          | cons b others =>
            simp only at h
            unfold shadowUse at h
            cases ha : anyNested fuel env (b :: others) with
            | none => rw [ha] at h; simp at h
            | some n =>
              rw [ha] at h
              simp only at h
              unfold shadowIf at h
              split at h
              · rename_i e
                simp only [Option.some.injEq] at h
                subst h
                exact .shadow rows (fun nn => by cases (armNested_sound hn).1 nn) ((anyNested_sound ha).2 e)
              · cases h
          | nil =>
            simp only [Option.some.injEq] at h
            subst h
            exact .plain rows (fun nn => by cases (armNested_sound hn).1 nn)

/-- Each variant's arm in variant order, and whether some is or holds the
wildcard. -/
inductive VariantArms (env : FrontEnv) (owner : TypeDecl) (init : List CTree) (w : Option CTree) :
    List VariantTy → List CTree → Bool → Prop
  | nil : VariantArms env owner init w [] [] false
  | cons {v : VariantTy} {vs : List VariantTy} {o : CTree} {os : List CTree} {u us : Bool} :
      VariantArm env owner init w v o u → VariantArms env owner init w vs os us →
      VariantArms env owner init w (v :: vs) (o :: os) (u || us)

theorem variantArms_unique {env : FrontEnv} {owner : TypeDecl} {init : List CTree} {w : Option CTree} :
    ∀ {vs : List VariantTy} {os os' : List CTree} {u u' : Bool},
      VariantArms env owner init w vs os u → VariantArms env owner init w vs os' u' → os = os' ∧ u = u'
  | _, _, _, _, _, .nil, .nil => ⟨rfl, rfl⟩
  | _, _, _, _, _, .cons a rest, .cons a' rest' => by
    obtain ⟨rfl, rfl⟩ := variantArm_unique a a'
    obtain ⟨rfl, rfl⟩ := variantArms_unique rest rest'
    exact ⟨rfl, rfl⟩

theorem variantArms_sound {fuel : Nat} {env : FrontEnv} {owner : TypeDecl} {init : List CTree} {w : Option CTree} :
    ∀ {vs : List VariantTy} {r : ArmsUse}, variantArms fuel env owner vs init w = some r →
      VariantArms env owner init w vs r.arms r.used
  | [], r, h => by
    simp only [variantArms, Option.some.injEq] at h
    subst h
    exact .nil
  | v :: rest, r, h => by
    simp only [variantArms] at h
    unfold consUse at h
    cases ha : variantArm fuel env v (rowsNaming fuel owner v.name init) w with
    | none => rw [ha] at h; simp at h
    | some x =>
      rw [ha] at h
      simp only at h
      unfold joinUse at h
      cases hr : variantArms fuel env owner rest init w with
      | none => rw [hr] at h; simp at h
      | some y =>
        rw [hr] at h
        simp only [Option.some.injEq] at h
        subst h
        exact .cons (variantArm_sound ha) (variantArms_sound hr)

/-! ## Block values -/

/-- A value that is a block `{ statements }`, as a match statement's arm. -/
def BlockValue (c : CTree) : Prop :=
  ∃ pf, Peel c pf ∧ nodeProd (kid pf 0) = pArmBlock ∧ nodeProd (kid pf 1) = pPostfixEnd

theorem levelProds_ne {p : Nat} (h : p ∈ levelProds) : p ≠ pExpr ∧ p ≠ pBase ∧ p ≠ pPostfix := by
  simp only [levelProds, List.mem_cons, List.not_mem_nil, or_false] at h
  rcases h with h | h | h | h | h | h | h | h | h | h <;> subst h <;> decide

theorem blockValue_false : ∀ {fuel : Nat} {c : CTree}, blockValue fuel c = some false → ¬BlockValue c
  | 0, _, h, _ => by unfold blockValue at h; simp at h
  | f + 1, c, h, ⟨pf, pl, e1, e2⟩ => by
    unfold blockValue at h
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
    split at h
    · rename_i c1
      simp only [Bool.or_eq_true, decide_eq_true_eq] at c1
      cases pl with
      | wrap _ pl' => exact blockValue_false h ⟨pf, pl', e1, e2⟩
      | bare w _ _ =>
        rcases w with w | w | w
        · rcases c1 with c1 | c1 <;> rw [c1] at w <;> cases w
        · have := levelProds_ne w
          rcases c1 with c1 | c1
          · exact this.1 c1
          · exact this.2.1 c1
        · rcases c1 with c1 | c1 <;> rw [c1] at w <;> cases w
      | here e => rcases c1 with c1 | c1 <;> rw [c1] at e <;> cases e
    · rename_i c1
      simp only [Bool.or_eq_true, decide_eq_true_eq, not_or] at c1
      split at h
      · rename_i c2
        cases pl with
        | wrap w _ => rcases w with w | w; exact c1.1 w; exact c1.2 w
        | bare _ _ pl' => exact blockValue_false h ⟨pf, pl', e1, e2⟩
        | here e =>
          simp only [Bool.and_eq_true, Bool.or_eq_true, decide_eq_true_eq, isLevel_iff, e] at c2
          rcases c2.1 with (c | c) | c
          · cases c
          · exact (levelProds_ne c).2.2 rfl
          · cases c
      · rename_i c2
        split at h
        · rename_i c3
          cases pl with
          | wrap w _ => rcases w with w | w <;> rw [c3] at w <;> cases w
          | bare w _ _ =>
            rcases w with w | w | w
            · rw [c3] at w; cases w
            · exact (levelProds_ne w).2.2 c3
            · rw [c3] at w; cases w
          | here _ =>
            simp only [Option.some.injEq, Bool.and_eq_false_iff, decide_eq_false_iff_not] at h
            rcases h with h | h
            · exact h e1
            · exact h e2
        · rename_i c3
          cases pl with
          | wrap w _ => rcases w with w | w; exact c1.1 w; exact c1.2 w
          | bare w k _ =>
            apply c2
            have hk : hasKids (kid c 1) = false := by simp [hasKids, k]
            simp only [Bool.and_eq_true, Bool.or_eq_true, decide_eq_true_eq, isLevel_iff, hk, Bool.not_false,
              and_true]
            rcases w with w | w | w
            · exact .inl (.inl w)
            · exact .inl (.inr w)
            · exact .inr w
          | here e => exact c3 e

theorem noBlock_true : ∀ {fuel : Nat} {arms : List CTree}, noBlock fuel arms = some true →
    ∀ a ∈ arms, ¬BlockValue (kid a 2)
  | _, [], _, _, m => by cases m
  | fuel, b :: rest, h, a, m => by
    simp only [noBlock] at h
    obtain ⟨y, z, ey, ez, e⟩ := andKnown_some h
    obtain ⟨hy, hz⟩ := Bool.and_eq_true_iff.1 e.symm
    subst hy hz
    rcases List.mem_cons.1 m with rfl | m
    · exact blockValue_false (notKnown_some ey)
    · exact noBlock_true ez a m

/-! ## The order -/

/-- Arm a names one of the variants. -/
def NamesSome (owner : TypeDecl) (vs : List VariantTy) (a : CTree) : Prop :=
  ∃ v ∈ vs, nodeProd (kid a 0) = pPatternIdent ∧ ArmNaming owner v.name a true

theorem namesSome_sound {fuel : Nat} {owner : TypeDecl} {vs : List VariantTy} {a : CTree}
    (h : namesSome fuel owner vs a = true) : NamesSome owner vs a := by
  obtain ⟨v, mv, hv⟩ := namesSome_exists h
  unfold armNames at hv
  simp only [Bool.and_eq_true, decide_eq_true_eq] at hv
  obtain ⟨pp, hn⟩ := hv
  cases hp : pathSpellings fuel (kid (kid (kid a 0) 0) 0) (kid (kid (kid a 0) 0) 1) with
  | none => rw [hp] at hn; simp [armNamed] at hn
  | some ss =>
    rw [hp] at hn
    exact ⟨v, mv, pp, ss, pathSpellings_sound hp, hn⟩

/-- The arms in variant order when some arm is nested: every arm but a last
wildcard names a variant, and each variant's arm is `VariantArm`'s; a
wildcard is used. -/
def NestedRows (env : FrontEnv) (owner : TypeDecl) (vs : List VariantTy) (arms os : List CTree) : Prop :=
  (wildSplit arms = none ∧ (∀ a ∈ arms, NamesSome owner vs a) ∧ ∃ u, VariantArms env owner arms none vs os u) ∨
    ∃ s, wildSplit arms = some s ∧ (∀ a ∈ s.init, NamesSome owner vs a) ∧
      VariantArms env owner s.init (some s.wild) vs os true

/-- A match expression's nested arms in variant order: `NestedRows`, no
arm's value a block. -/
def NestedOrder (env : FrontEnv) (owner : TypeDecl) (vs : List VariantTy) (arms os : List CTree) : Prop :=
  (∀ a ∈ arms, ¬BlockValue (kid a 2)) ∧ NestedRows env owner vs arms os

/-- A match expression's arms in variant order: `ArmsOrder` when no arm is
nested, else `NestedOrder`. -/
def MatchOrder (env : FrontEnv) (owner : TypeDecl) (vs : List VariantTy) (arms os : List CTree) : Prop :=
  ((∀ a ∈ arms, ¬Nested env a) ∧ ArmsOrder vs arms os) ∨
    ((∃ a ∈ arms, Nested env a) ∧ NestedOrder env owner vs arms os)

theorem nestedRows_unique {env : FrontEnv} {owner : TypeDecl} {vs : List VariantTy} {arms os os' : List CTree}
    (h₁ : NestedRows env owner vs arms os) (h₂ : NestedRows env owner vs arms os') : os = os' := by
  rcases h₁ with ⟨w, _, u, va⟩ | ⟨s, w, _, va⟩ <;> rcases h₂ with ⟨w', _, u', va'⟩ | ⟨s', w', _, va'⟩
  · exact (variantArms_unique va va').1
  · rw [w] at w'; cases w'
  · rw [w] at w'; cases w'
  · rw [w] at w'
    cases w'
    exact (variantArms_unique va va').1

theorem nestedOrder_unique {env : FrontEnv} {owner : TypeDecl} {vs : List VariantTy} {arms os os' : List CTree}
    (h₁ : NestedOrder env owner vs arms os) (h₂ : NestedOrder env owner vs arms os') : os = os' :=
  nestedRows_unique h₁.2 h₂.2

theorem nestedChecked_sound {fuel : Nat} {env : FrontEnv} {owner : TypeDecl} {vs : List VariantTy}
    {arms os : List CTree} (h : nestedChecked fuel env owner vs arms true = some os) :
    NestedRows env owner vs arms os := by
  unfold NestedRows
  unfold nestedChecked at h
  simp only [if_true] at h
  cases hw : wildSplit arms with
  | none =>
    rw [hw] at h
    simp only at h
    unfold nestedWith at h
    split at h
    · rename_i all
      unfold nestedUsed at h
      cases hv : variantArms fuel env owner vs arms none with
      | none => rw [hv] at h; simp at h
      | some r =>
        rw [hv] at h
        simp only [wildUsed, Option.some.injEq] at h
        subst h
        exact .inl ⟨rfl, fun a ma => namesSome_sound (allNameSome_mem all a ma), r.used, variantArms_sound hv⟩
    · cases h
  | some s =>
    rw [hw] at h
    simp only at h
    unfold nestedWith at h
    split at h
    · rename_i all
      unfold nestedUsed at h
      cases hv : variantArms fuel env owner vs s.init (some s.wild) with
      | none => rw [hv] at h; simp at h
      | some r =>
        rw [hv] at h
        simp only [wildUsed] at h
        unfold usedArms at h
        split at h
        · rename_i eu
          simp only [Option.some.injEq] at h
          subst h
          have va := variantArms_sound hv
          rw [eu] at va
          exact .inr ⟨s, rfl, fun a ma => namesSome_sound (allNameSome_mem all a ma), va⟩
        · cases h
    · cases h

theorem nestedOrder_sound {fuel : Nat} {env : FrontEnv} {owner : TypeDecl} {vs : List VariantTy} {arms os : List CTree}
    (h : nestedOrder fuel env owner vs arms = some os) : NestedOrder env owner vs arms os := by
  unfold nestedOrder at h
  cases hb : noBlock fuel arms with
  | none => rw [hb] at h; simp at h
  | some ok =>
    rw [hb] at h
    simp only at h
    cases ok with
    | true => exact ⟨noBlock_true hb, nestedChecked_sound h⟩
    | false => unfold nestedChecked at h; simp at h

theorem matchOrder_sound {fuel : Nat} {env : FrontEnv} {owner : TypeDecl} {vs : List VariantTy} {arms os : List CTree}
    (h : matchOrder fuel env owner vs arms = some os) : MatchOrder env owner vs arms os := by
  unfold matchOrder at h
  cases hn : anyNested fuel env arms with
  | none => rw [hn] at h; simp at h
  | some n =>
    rw [hn] at h
    simp only at h
    have an := anyNested_sound hn
    unfold orderBy at h
    split at h
    · rename_i e
      exact .inr ⟨an.2 e, nestedOrder_sound h⟩
    · rename_i e
      refine .inl ⟨fun a ma na => e (an.1 ⟨a, ma, na⟩), armsInOrder_sound h⟩

/-- A match statement's arms in variant order: as a match expression's
(`MatchOrder`), but an arm's value may be a block. -/
def StmtOrder (env : FrontEnv) (owner : TypeDecl) (vs : List VariantTy) (arms os : List CTree) : Prop :=
  ((∀ a ∈ arms, ¬Nested env a) ∧ ArmsOrder vs arms os) ∨
    ((∃ a ∈ arms, Nested env a) ∧ NestedRows env owner vs arms os)

theorem stmtArmOrder_sound {fuel : Nat} {env : FrontEnv} {owner : TypeDecl} {vs : List VariantTy}
    {arms os : List CTree} (h : stmtArmOrder fuel env owner vs arms = some os) : StmtOrder env owner vs arms os := by
  unfold stmtArmOrder at h
  cases hn : anyNested fuel env arms with
  | none => rw [hn] at h; simp at h
  | some n =>
    rw [hn] at h
    simp only at h
    have an := anyNested_sound hn
    unfold stmtOrderBy at h
    split at h
    · rename_i e
      exact .inr ⟨an.2 e, nestedChecked_sound h⟩
    · rename_i e
      exact .inl ⟨fun a ma na => e (an.1 ⟨a, ma, na⟩), armsInOrder_sound h⟩

end Lanius.Mini.Reading
