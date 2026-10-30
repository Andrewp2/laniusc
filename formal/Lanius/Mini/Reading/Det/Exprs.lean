import Lanius.Mini.Reading.Det.Lower

/-! # The reading is deterministic, F1: pure expressions

Literals, locals, fields, casts, constants and the pure expressions
(`ExprR`). -/

namespace Lanius.Mini.Reading

open Lanius.Mini Lanius.Mini.Prod

/-- Close a goal whose hypotheses give one node two different productions,
the operator levels among them. -/
macro "expr_clash" : tactic => `(tactic| (exfalso; (try simp only [levelProds, List.mem_cons, List.not_mem_nil, or_false] at *); (try unfold_prods); omega))

theorem localOf_unique {scope : List Local} {c : CTree} {a b : Local} (h₁ : LocalOf scope c a)
    (h₂ : LocalOf scope c b) : a = b := by
  cases h₁ with
  | name e _ p n => cases h₂ with
    | name _ _ p' n' =>
      obtain ⟨_, _, _, rfl⟩ := p
      obtain ⟨_, _, _, rfl⟩ := p'
      obtain ⟨_, f⟩ := n
      obtain ⟨_, f'⟩ := n'
      exact (firstWith_unique f f').2
    | «self» e' _ => prod_clash
  | self e n => cases h₂ with
    | name e' _ _ _ => prod_clash
    | «self» _ n' =>
      obtain ⟨_, f⟩ := n
      obtain ⟨_, f'⟩ := n'
      exact (firstWith_unique f f').2

theorem fieldIndex_unique {decls : Decls} {t : Ty} {name : Name} {i j : Nat} (h₁ : FieldIndex decls t name i)
    (h₂ : FieldIndex decls t name j) : i = j := by
  obtain ⟨d, args, td, rfl, e, f⟩ := h₁
  obtain ⟨d', args', td', e', e'', f'⟩ := h₂
  cases e'
  rw [e] at e''
  cases e''
  exact (firstWith_unique f f').1

theorem member_unique {env : FrontEnv} {scope : List Local} {primary tail : CTree} {a b : SrcExpr}
    (h₁ : Member env scope primary tail a) (h₂ : Member env scope primary tail b) : a = b := by
  obtain ⟨_, _, l, j, lo, fi, rfl⟩ := h₁
  obtain ⟨_, _, l', j', lo', fi', rfl⟩ := h₂
  have el := localOf_unique lo lo'
  subst el
  rw [fieldIndex_unique fi fi']

theorem scalarTy_unique {t : Ty} {a b : SrcType} (h₁ : ScalarTy t a) (h₂ : ScalarTy t b) : a = b := by
  cases h₁ <;> cases h₂ <;> rfl

theorem namedScalar_unique {env : FrontEnv} {n : Name} {a b : SrcType} (h₁ : NamedScalar env n a)
    (h₂ : NamedScalar env n b) : a = b := by
  cases h₁ with
  | param p s => cases h₂ with
    | param p' s' =>
      rw [paramTy_unique p p'] at s
      exact scalarTy_unique s s'
    | prim no _ _ => exact (paramTy_noParam p no).elim
    | alias no _ _ _ => exact (paramTy_noParam p no).elim
  | prim no l s => cases h₂ with
    | param p' _ => exact (paramTy_noParam p' no).elim
    | prim _ l' s' =>
      rw [l] at l'
      cases l'
      exact scalarTy_unique s s'
    | alias _ l' _ _ => rw [l] at l'; cases l'
  | alias no l al s => cases h₂ with
    | param p' _ => exact (paramTy_noParam p' no).elim
    | prim _ l' _ => rw [l] at l'; cases l'
    | alias _ _ al' s' =>
      rw [aliasTy_unique al al'] at s
      exact scalarTy_unique s s'

theorem castType_unique {env : FrontEnv} {t : CTree} {a b : SrcType} (h₁ : CastType env t a)
    (h₂ : CastType env t b) : a = b :=
  namedScalar_unique h₁.2.2.2.2 h₂.2.2.2.2

theorem casts_unique {env : FrontEnv} : ∀ {acc : SrcExpr} {tail : CTree} {a b : SrcExpr},
    Casts env acc tail a → Casts env acc tail b → a = b
  | _, _, _, _, .done _, .done _ => rfl
  | _, _, _, _, .done e, .step e' .. => absurd e e'
  | _, _, _, _, .step e' .., .done e => absurd e e'
  | _, _, _, _, .step _ c r, .step _ c' r' => by
    have e := castType_unique c c'
    subst e
    exact casts_unique r r'

theorem intLiteral_unique {text : List Nat} {a b : SrcExpr} (h₁ : IntLiteral text a) (h₂ : IntLiteral text b) :
    a = b := by
  cases h₁ with
  | small _ lt => cases h₂ with
    | small => rfl
    | wide _ ge _ => omega
  | wide _ ge _ => cases h₂ with
    | small _ lt => omega
    | wide => rfl

theorem typedLiteral_unique {t : Ty} {v a b : SrcExpr} (h₁ : TypedLiteral t v a) (h₂ : TypedLiteral t v b) :
    a = b := by
  cases h₁ <;> cases h₂ <;> rfl

theorem wideOf_unique {t : Ty} {negative : Bool} {n : Nat} {a b : SrcExpr} (h₁ : WideOf t negative n a)
    (h₂ : WideOf t negative n b) : a = b := by
  cases h₁ <;> cases h₂ <;> rfl

theorem wideConst_unique {t : Ty} {toks : List Token} {a b : SrcExpr} (h₁ : WideConst t toks a)
    (h₂ : WideConst t toks b) : a = b := by
  cases h₁ with
  | pos _ _ w => cases h₂ with
    | pos _ _ w' => exact wideOf_unique w w'
  | neg _ _ _ w => cases h₂ with
    | «neg» _ _ _ w' => exact wideOf_unique w w'

mutual
theorem exprR_unique : ∀ {env : FrontEnv} {scope : List Local} {c : CTree} {a b : SrcExpr},
    ExprR env scope c a → ExprR env scope c b → a = b
  | _, _, _, _, _, .wrap _ r, h₂ => by
    cases h₂ with
    | «wrap» _ r' =>
      exact exprR_unique r r'
    | _ => expr_clash
  | _, _, _, _, _, .assign _ _ r, h₂ => by
    cases h₂ with
    | «assign» _ _ r' =>
      exact exprR_unique r r'
    | _ => expr_clash
  | _, _, _, _, _, .level _ r f, h₂ => by
    cases h₂ with
    | «level» _ r' f' =>
      have e := exprR_unique r r'
      subst e
      exact fold_unique f f'
    | _ => expr_clash
  | _, _, _, _, _, .cast _ r c, h₂ => by
    cases h₂ with
    | «cast» _ r' c' =>
      have e := exprR_unique r r'
      subst e
      exact casts_unique c c'
    | _ => expr_clash
  | _, _, _, _, _, .neg _ r, h₂ => by
    cases h₂ with
    | «neg» _ r' =>
      rw [exprR_unique r r']
    | _ => expr_clash
  | _, _, _, _, _, .not _ r, h₂ => by
    cases h₂ with
    | «not» _ r' =>
      rw [exprR_unique r r']
    | _ => expr_clash
  | _, _, _, _, _, .postfix _ _ r, h₂ => by
    cases h₂ with
    | «postfix» _ _ r' =>
      exact exprR_unique r r'
    | _ => expr_clash
  | _, _, _, _, _, .member _ _ m, h₂ => by
    cases h₂ with
    | «member» _ _ m' =>
      exact member_unique m m'
    | _ => expr_clash
  | _, _, _, _, _, .group _ r, h₂ => by
    cases h₂ with
    | «group» _ r' =>
      exact exprR_unique r r'
    | _ => expr_clash
  | _, _, _, _, _, .local _ _ l, h₂ => by
    cases h₂ with
    | «local» _ _ l' =>
      rw [localOf_unique l l']
    | «const» _ _ nl _ _ _ _ => exact (nl _ l).elim
    | _ => expr_clash
  | _, _, _, _, _, .const _ _ nl s r k v, h₂ => by
    cases h₂ with
    | «const» _ _ _ s' r' k' v' =>
      rw [pathSpellings_unique s s'] at r
      obtain ⟨rfl, rfl⟩ := resolves_unique r r'
      have e := constNamed_unique k k'
      subst e
      exact constValue_unique v v'
    | «local» _ _ l' => exact (nl _ l').elim
    | _ => expr_clash
  | _, _, _, _, _, .self _ l, h₂ => by
    cases h₂ with
    | «self» _ l' =>
      rw [localOf_unique l l']
    | _ => expr_clash
  | _, _, _, _, _, .int _ i, h₂ => by
    cases h₂ with
    | «int» _ i' =>
      exact intLiteral_unique i i'
    | _ => expr_clash
  | _, _, _, _, _, .true _, h₂ => by
    cases h₂ with
    | «true» _ =>
      rfl
    | _ => expr_clash
  | _, _, _, _, _, .false _, h₂ => by
    cases h₂ with
    | «false» _ =>
      rfl
    | _ => expr_clash

theorem fold_unique : ∀ {env : FrontEnv} {scope : List Local} {acc : SrcExpr} {tail : CTree} {a b : SrcExpr},
    Fold env scope acc tail a → Fold env scope acc tail b → a = b
  | _, _, _, _, _, _, .done _, .done _ => rfl
  | _, _, _, _, _, _, .done e, .step e' .. => absurd e e'
  | _, _, _, _, _, _, .step e' .., .done e => absurd e e'
  | _, _, _, _, _, _, .step _ o r f, .step _ o' r' f' => by
    rw [o] at o'
    cases o'
    have e := exprR_unique r r'
    subst e
    exact fold_unique f f'

theorem constValue_unique : ∀ {decls : Decls} {k : ConstDecl} {a b : SrcExpr},
    ConstValue decls k a → ConstValue decls k b → a = b
  | _, _, _, _, .literal t r _ l, .literal t' r' _ l' => by
    rw [tyR_unique t t', exprR_unique r r'] at l
    exact typedLiteral_unique l l'
  | _, _, _, _, .literal _ r n _, .wide _ r' w _ => by
    rw [exprR_unique r r', w] at n
    cases n
  | _, _, _, _, .wide _ r w _, .literal _ r' n _ => by
    rw [exprR_unique r r', n] at w
    cases w
  | _, _, _, _, .wide t _ _ w, .wide t' _ _ w' => by
    rw [tyR_unique t t'] at w
    exact wideConst_unique w w'
end

end Lanius.Mini.Reading
