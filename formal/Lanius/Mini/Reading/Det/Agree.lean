import Lanius.Mini.Reading.Effs

/-! # The reading is deterministic, F1: the pure and effectful readings agree

A node that reads as a pure expression `e` reads as an effectful expression
only as `.xPure e` (`pure_agree`): the effectful readings of operators,
casts, negations and field accesses keep a pure result pure, and a unit
variant is not read where a local or constant of that name exists. This
holds in a scope where each local has its own id (`IdsFresh`), which the
reading keeps (a binding's id is fresh in its scope). -/

namespace Lanius.Mini.Reading

open Lanius.Mini Lanius.Mini.Prod

/-- Each local in scope has its own id. -/
def IdsFresh (scope : List Local) : Prop := (scope.map (·.id)).Nodup

theorem idsFresh_eq : ∀ {scope : List Local} {a b : Local}, IdsFresh scope → a ∈ scope → b ∈ scope → a.id = b.id →
    a = b
  | [], _, _, _, ma, _, _ => by cases ma
  | x :: rest, a, b, nd, ma, mb, e => by
    simp only [IdsFresh, List.map_cons, List.nodup_cons, List.mem_map] at nd
    obtain ⟨nx, nr⟩ := nd
    rcases List.mem_cons.1 ma with ha | ma'
    · rcases List.mem_cons.1 mb with hb | mb'
      · rw [ha, hb]
      · subst ha; exact (nx ⟨b, mb', e.symm⟩).elim
    · rcases List.mem_cons.1 mb with hb | mb'
      · subst hb; exact (nx ⟨a, ma', e⟩).elim
      · exact idsFresh_eq nr ma' mb' e

theorem idsFresh_cons {scope : List Local} {l : Local} (nd : IdsFresh scope) (fr : FreshId scope l.id) :
    IdsFresh (l :: scope) := by
  simp only [IdsFresh, List.map_cons, List.nodup_cons, List.mem_map]
  exact ⟨fun ⟨b, mb, e⟩ => fr b mb e, nd⟩

theorem localOf_mem {scope : List Local} {p : CTree} {l : Local} (lo : LocalOf scope p l) : l ∈ scope := by
  cases lo with
  | name _ _ _ ln => obtain ⟨_, fi⟩ := ln; exact (firstWith_mem fi).1
  | self _ ln => obtain ⟨_, fi⟩ := ln; exact (firstWith_mem fi).1

/-- The local a name finds is the one its id finds. -/
theorem localWith_named {scope : List Local} {p : CTree} {l l' : Local} (nd : IdsFresh scope) (lo : LocalOf scope p l)
    (lw : LocalWithId scope l.id l') : l' = l := by
  obtain ⟨_, fw⟩ := lw
  exact idsFresh_eq nd (firstWith_mem fw).1 (localOf_mem lo) (firstWith_mem fw).2

theorem exprR_local {env : FrontEnv} {scope : List Local} {p : CTree} {e : SrcExpr} {l : Local}
    (pr : ExprR env scope p e) (lo : LocalOf scope p l) : e = .local l.id := by
  cases pr with
  | «local» _ _ lo' => rw [localOf_unique lo' lo]
  | «self» _ lo' => rw [localOf_unique lo' lo]
  | const _ _ nl _ _ _ _ => exact (nl l lo).elim
  | _ => cases lo <;> expr_clash

theorem eff_local {env : FrontEnv} {scope : List Local} {p : CTree} {l : Local} {expected : Option Ty} {x : MEff}
    (lo : LocalOf scope p l) (h : EffR env scope expected p x) : x = .xPure (.local l.id) := by
  cases h with
  | pure pr => rw [exprR_local pr lo]
  | unitVariant _ _ _ _ nl _ _ _ => exact (nl l lo).elim
  | _ => cases lo <;> expr_clash

theorem chain_end {env : FrontEnv} {scope : List Local} {expected : Option Ty} {a : MEff} {tail : CTree} {x : MEff}
    (te : nodeProd tail = pPostfixEnd) (ch : EffChain env scope expected a tail x) : x = a := by
  cases ch with
  | done _ => rfl
  | _ => expr_clash

theorem chain_member {env : FrontEnv} {scope : List Local} {p tail : CTree} {e : SrcExpr} {l : Local}
    {expected : Option Ty} {x : MEff} (mb : Member env scope p tail e) (tm : nodeProd tail = pPostfixMember)
    (nd : IdsFresh scope) (lo : LocalOf scope p l) (ch : EffChain env scope expected (.xPure (.local l.id)) tail x) :
    x = .xPure e := by
  obtain ⟨_, te, l₀, j, lo₀, fi, rfl⟩ := mb
  have el := localOf_unique lo₀ lo
  subst el
  cases ch with
  | done _ => expr_clash
  | method _ _ _ _ _ _ _ _ _ => expr_clash
  | field _ _ _ ty fi₂ ch' =>
    cases ty with
    | pure et =>
      cases et with
      | «local» lw =>
        have e := localWith_named nd lo lw
        subst e
        rw [fieldIndex_unique fi₂ fi] at ch'
        simpa [fieldValue, effLocal, purePart, pureLocal] using chain_end te ch'
  | index _ _ _ _ _ => expr_clash

theorem casts_agree {env : FrontEnv} {a : SrcExpr} {tail : CTree} {e : SrcExpr} (h : Casts env a tail e) :
    ∀ {x : MEff}, EffCasts env (.xPure a) tail x → x = .xPure e := by
  induction h with
  | done kids =>
    intro x h₂
    cases h₂ with
    | done _ => rfl
    | step ne _ _ _ => exact absurd kids ne
  | step ne ct _ ih =>
    intro x h₂
    cases h₂ with
    | done kids => exact absurd kids ne
    | step _ ct₂ xc ec =>
      have es := castType_unique ct₂ ct
      subst es
      simp only [xCastInto, purePart, Option.some.injEq] at xc
      subst xc
      exact ih ec

theorem effBinary_pure {p : Nat} {o : SrcOp} {a r : SrcExpr} (lk : tailOps.lookup p = some o) :
    effBinary p (some (.xPure a)) (some (.xPure r)) = some (.xPure (.apply o a r)) := by
  have n153 : p ≠ 153 := by
    rintro rfl
    simp only [tailOps] at lk
    unfold_prods
    simp [List.lookup] at lk
  have n154 : p ≠ 154 := by
    rintro rfl
    simp only [tailOps] at lk
    unfold_prods
    simp [List.lookup] at lk
  simp only [effBinary, if_neg n153, if_neg n154, tailOp_eq, lk, xApplyOf, applyEff, purePart]

mutual
theorem pure_agree : ∀ {env : FrontEnv} {scope : List Local} {c : CTree} {e : SrcExpr}, ExprR env scope c e →
    IdsFresh scope → ∀ {expected : Option Ty} {x : MEff}, EffR env scope expected c x → x = .xPure e
  | _, _, _, _, h₁@(.wrap w k), nd, _, _, h₂ => by
    cases h₂ with
    | pure p => rw [exprR_unique p h₁]
    | wrap _ k₂ => exact pure_agree k nd k₂
    | _ => expr_clash
  | _, _, _, _, h₁@(.assign pa pe k), nd, _, _, h₂ => by
    cases h₂ with
    | pure p => rw [exprR_unique p h₁]
    | bare _ _ k₂ => exact pure_agree k nd k₂
    | _ => expr_clash
  | _, _, _, _, h₁@(.level lp k fo), nd, _, _, h₂ => by
    have lq := lp
    cases h₂ with
    | pure p => rw [exprR_unique p h₁]
    | bare _ kids k₂ =>
      have e := pure_agree k nd k₂
      subst e
      cases fo with
      | done _ => rfl
      | step ne _ _ _ => exact absurd kids ne
    | level _ _ k₂ ef =>
      have e := pure_agree k nd k₂
      subst e
      exact fold_agree fo nd ef
    | _ => expr_clash
  | _, _, _, _, h₁@(.cast pc k cs), nd, _, _, h₂ => by
    cases h₂ with
    | pure p => rw [exprR_unique p h₁]
    | bare _ kids k₂ =>
      have e := pure_agree k nd k₂
      subst e
      cases cs with
      | done _ => rfl
      | step ne _ _ => exact absurd kids ne
    | cast _ _ k₂ ec =>
      have e := pure_agree k nd k₂
      subst e
      exact casts_agree cs ec
    | _ => expr_clash
  | _, _, _, _, h₁@(.neg pn k), nd, _, _, h₂ => by
    cases h₂ with
    | pure p => rw [exprR_unique p h₁]
    | neg _ k₂ xn =>
      have e := pure_agree k nd k₂
      subst e
      simp only [xNegOf, purePart, Option.some.injEq] at xn
      exact xn.symm
    | _ => expr_clash
  | _, _, _, _, h₁@(.not pn k), nd, _, _, h₂ => by
    cases h₂ with
    | pure p => rw [exprR_unique p h₁]
    | «not» _ k₂ xn =>
      have e := pure_agree k nd k₂
      subst e
      simp only [xNotOf, purePart, Option.some.injEq] at xn
      exact xn.symm
    | _ => expr_clash
  | _, _, _, _, h₁@(.postfix pp pe k), nd, _, _, h₂ => by
    cases h₂ with
    | pure p => rw [exprR_unique p h₁]
    | primary _ _ k₂ => exact pure_agree k nd k₂
    | method _ mf _ _ _ _ _ =>
      obtain ⟨_, m1, _⟩ := mf
      expr_clash
    | chainLocal _ cf _ _ => exact absurd pe cf.1
    | chain _ cf _ _ => exact absurd pe cf.1
    | _ => expr_clash
  | _, _, _, _, h₁@(.member pp pm mb), nd, _, _, h₂ => by
    cases h₂ with
    | pure p => rw [exprR_unique p h₁]
    | method _ mf _ _ _ _ _ =>
      obtain ⟨_, _, _, m3, _⟩ := mf
      obtain ⟨_, te, _⟩ := mb
      expr_clash
    | chainLocal _ _ lo ch => exact chain_member mb pm nd lo ch
    | chain _ _ k₂ ch =>
      obtain ⟨_, _, l, _, lo, _, _⟩ := id mb
      have e := eff_local lo k₂
      subst e
      exact chain_member mb pm nd lo ch
    | _ => expr_clash
  | _, _, _, _, h₁@(.group pg k), nd, _, _, h₂ => by
    cases h₂ with
    | pure p => rw [exprR_unique p h₁]
    | group _ k₂ => exact pure_agree k nd k₂
    | _ => expr_clash
  | _, _, _, _, h₁@(.local pi pl lo), _, _, _, h₂ => by
    cases h₂ with
    | pure p => rw [exprR_unique p h₁]
    | unitVariant _ _ _ _ nl _ _ _ => exact (nl _ lo).elim
    | _ => expr_clash
  | _, _, _, _, h₁@(.const pi pl nl ps r kn cv), _, _, _, h₂ => by
    cases h₂ with
    | pure p => rw [exprR_unique p h₁]
    | unitVariant _ _ ps₂ _ _ nk _ _ =>
      have es := pathSpellings_unique ps ps₂
      subst es
      exact (nk _ _ _ r kn).elim
    | _ => expr_clash
  | _, _, _, _, h₁@(.self psv lo), _, _, _, h₂ => by
    cases h₂ with
    | pure p => rw [exprR_unique p h₁]
    | _ => expr_clash
  | _, _, _, _, h₁@(.int pn il), _, _, _, h₂ => by
    cases h₂ with
    | pure p => rw [exprR_unique p h₁]
    | _ => expr_clash
  | _, _, _, _, h₁@(.true pt), _, _, _, h₂ => by
    cases h₂ with
    | pure p => rw [exprR_unique p h₁]
    | _ => expr_clash
  | _, _, _, _, h₁@(.false pf), _, _, _, h₂ => by
    cases h₂ with
    | pure p => rw [exprR_unique p h₁]
    | _ => expr_clash
  | _, _, _, _, h₁@(.char pc cl), _, _, _, h₂ => by
    cases h₂ with
    | pure p => rw [exprR_unique p h₁]
    | _ => expr_clash

theorem fold_agree : ∀ {env : FrontEnv} {scope : List Local} {a : SrcExpr} {tail : CTree} {e : SrcExpr},
    Fold env scope a tail e → IdsFresh scope → ∀ {x : MEff}, EffFold env scope (.xPure a) tail x → x = .xPure e
  | _, _, _, _, _, .done kids, _, _, h₂ => by
    cases h₂ with
    | done _ => rfl
    | step ne _ _ _ => exact absurd kids ne
  | _, _, _, _, _, .step ne lk k fo, nd, _, h₂ => by
    cases h₂ with
    | done kids => exact absurd kids ne
    | step _ k₂ eb ef =>
      have e := pure_agree k nd k₂
      subst e
      rw [effBinary_pure lk] at eb
      cases eb
      exact fold_agree fo nd ef
end

end Lanius.Mini.Reading
