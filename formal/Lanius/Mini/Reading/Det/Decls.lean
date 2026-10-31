import Lanius.Mini.Reading.Det.Base
import Lanius.Mini.Reading.Det.Prods

/-! # The reading is deterministic, F1: declarations

What the items of each file declare, and the files' modules. -/

namespace Lanius.Mini.Reading

open Lanius.Mini Lanius.Mini.Prod

theorem methodDecl_unique : ∀ {home : ModPath} {ips : List Name} {selfType m : CTree} {a b : FnDecl},
    MethodDecl home ips selfType m a → MethodDecl home ips selfType m b → a = b
  | _, _, _, _, _, _, .plain _ _ p, .plain _ _ p' => by rw [typeParams_unique p p']
  | _, _, _, _, _, _, .plain .., .pub .. => by prod_clash
  | _, _, _, _, _, _, .pub .., .plain .. => by prod_clash
  | _, _, _, _, _, _, .pub _ _ p, .pub _ _ p' => by rw [typeParams_unique p p']

theorem methodDecls_unique {home : ModPath} {ips : List Name} {selfType : CTree} {ms : List CTree}
    {a b : List FnDecl} (h₁ : ListRel (MethodDecl home ips selfType) ms a)
    (h₂ : ListRel (MethodDecl home ips selfType) ms b) : a = b :=
  listRel_unique (R := MethodDecl home ips selfType) (fun _ _ _ x y => methodDecl_unique x y) h₁ h₂

theorem itemDecls_unique : ∀ {home : ModPath} {item : CTree} {a b : Decls},
    ItemDecls home item a → ItemDecls home item b → a = b
  | _, _, _, _, .type _ t, .type _ t' => by rw [typeDeclR_unique t t']
  | _, _, _, _, .type .., .fn .. => by prod_clash
  | _, _, _, _, .type .., .const .. => by prod_clash
  | _, _, _, _, .type .., .implInherent .. => by prod_clash
  | _, _, _, _, .type .., .implTrait .. => by prod_clash
  | _, _, _, _, .type .., .imports .. => by prod_clash
  | _, _, _, _, .type .., .alias .. => by prod_clash
  | _, _, _, _, .type .., .host .. => by prod_clash
  | _, _, _, _, .type .., .none .. => by prod_clash
  | _, _, _, _, .fn .., .type .. => by prod_clash
  | _, _, _, _, .fn _ p, .fn _ p' => by rw [typeParams_unique p p']
  | _, _, _, _, .fn .., .const .. => by prod_clash
  | _, _, _, _, .fn .., .implInherent .. => by prod_clash
  | _, _, _, _, .fn .., .implTrait .. => by prod_clash
  | _, _, _, _, .fn .., .imports .. => by prod_clash
  | _, _, _, _, .fn .., .alias .. => by prod_clash
  | _, _, _, _, .fn .., .host .. => by prod_clash
  | _, _, _, _, .fn .., .none .. => by prod_clash
  | _, _, _, _, .const .., .type .. => by prod_clash
  | _, _, _, _, .const .., .fn .. => by prod_clash
  | _, _, _, _, .const _, .const _ => rfl
  | _, _, _, _, .const .., .implInherent .. => by prod_clash
  | _, _, _, _, .const .., .implTrait .. => by prod_clash
  | _, _, _, _, .const .., .imports .. => by prod_clash
  | _, _, _, _, .const .., .alias .. => by prod_clash
  | _, _, _, _, .const .., .host .. => by prod_clash
  | _, _, _, _, .const .., .none .. => by prod_clash
  | _, _, _, _, .implInherent .., .type .. => by prod_clash
  | _, _, _, _, .implInherent .., .fn .. => by prod_clash
  | _, _, _, _, .implInherent .., .const .. => by prod_clash
  | _, _, _, _, .implInherent _ _ p i ms, .implInherent _ _ p' i' ms' => by
    have ep := typeParams_unique p p'
    subst ep
    have ei := items_unique i i'
    subst ei
    rw [methodDecls_unique ms ms']
  | _, _, _, _, .implInherent .., .implTrait .. => by prod_clash
  | _, _, _, _, .implInherent .., .imports .. => by prod_clash
  | _, _, _, _, .implInherent .., .alias .. => by prod_clash
  | _, _, _, _, .implInherent .., .host .. => by prod_clash
  | _, _, _, _, .implInherent .., .none .. => by prod_clash
  | _, _, _, _, .implTrait .., .type .. => by prod_clash
  | _, _, _, _, .implTrait .., .fn .. => by prod_clash
  | _, _, _, _, .implTrait .., .const .. => by prod_clash
  | _, _, _, _, .implTrait .., .implInherent .. => by prod_clash
  | _, _, _, _, .implTrait _ _ p i ms, .implTrait _ _ p' i' ms' => by
    have ep := typeParams_unique p p'
    subst ep
    have ei := items_unique i i'
    subst ei
    rw [methodDecls_unique ms ms']
  | _, _, _, _, .implTrait .., .imports .. => by prod_clash
  | _, _, _, _, .implTrait .., .alias .. => by prod_clash
  | _, _, _, _, .implTrait .., .host .. => by prod_clash
  | _, _, _, _, .implTrait .., .none .. => by prod_clash
  | _, _, _, _, .imports .., .type .. => by prod_clash
  | _, _, _, _, .imports .., .fn .. => by prod_clash
  | _, _, _, _, .imports .., .const .. => by prod_clash
  | _, _, _, _, .imports .., .implInherent .. => by prod_clash
  | _, _, _, _, .imports .., .implTrait .. => by prod_clash
  | _, _, _, _, .imports _ _ s, .imports _ _ s' => by rw [pathSpellings_unique s s']
  | _, _, _, _, .imports .., .alias .. => by prod_clash
  | _, _, _, _, .imports .., .host .. => by prod_clash
  | _, _, _, _, .imports .., .none .. => by prod_clash
  | _, _, _, _, .alias .., .type .. => by prod_clash
  | _, _, _, _, .alias .., .fn .. => by prod_clash
  | _, _, _, _, .alias .., .const .. => by prod_clash
  | _, _, _, _, .alias .., .implInherent .. => by prod_clash
  | _, _, _, _, .alias .., .implTrait .. => by prod_clash
  | _, _, _, _, .alias .., .imports .. => by prod_clash
  | _, _, _, _, .alias _ _ p, .alias _ _ p' => by rw [typeParams_unique p p']
  | _, _, _, _, .alias .., .host .. => by prod_clash
  | _, _, _, _, .alias .., .none .. => by prod_clash
  | _, _, _, _, .host .., .type .. => by prod_clash
  | _, _, _, _, .host .., .fn .. => by prod_clash
  | _, _, _, _, .host .., .const .. => by prod_clash
  | _, _, _, _, .host .., .implInherent .. => by prod_clash
  | _, _, _, _, .host .., .implTrait .. => by prod_clash
  | _, _, _, _, .host .., .imports .. => by prod_clash
  | _, _, _, _, .host .., .alias .. => by prod_clash
  | _, _, _, _, .host _ _ p, .host _ _ p' => by rw [typeParams_unique p p']
  | _, _, _, _, .host _ hx _, .none n => by
    simp only [hx, Bool.true_eq_false, and_false, false_or] at n
    prod_clash
  | _, _, _, _, .none .., .type .. => by prod_clash
  | _, _, _, _, .none .., .fn .. => by prod_clash
  | _, _, _, _, .none .., .const .. => by prod_clash
  | _, _, _, _, .none .., .implInherent .. => by prod_clash
  | _, _, _, _, .none .., .implTrait .. => by prod_clash
  | _, _, _, _, .none .., .imports .. => by prod_clash
  | _, _, _, _, .none .., .alias .. => by prod_clash
  | _, _, _, _, .none n, .host _ hx _ => by
    simp only [hx, Bool.true_eq_false, and_false, false_or] at n
    prod_clash
  | _, _, _, _, .none _, .none _ => rfl

theorem modulePath_unique : ∀ {items : List CTree} {a b : ModPath}, ModulePath items a → ModulePath items b → a = b
  | _, _, _, .none, .none => rfl
  | _, _, _, .here _ s, .here _ s' => pathSpellings_unique s s'
  | _, _, _, .here e _, .skip e' _ => absurd e e'
  | _, _, _, .skip e _, .here e' _ => absurd e' e
  | _, _, _, .skip _ r, .skip _ r' => modulePath_unique r r'

theorem collect_unique : ∀ {home : ModPath} {items : List CTree} {a b : Decls},
    Collect home items a → Collect home items b → a = b
  | _, _, _, _, .nil, .nil => rfl
  | _, _, _, _, .cons d r, .cons d' r' => by rw [itemDecls_unique d d', collect_unique r r']

theorem fileDeclsR_unique {root : CTree} {a b : FileDecls} (h₁ : FileDeclsR root a) (h₂ : FileDeclsR root b) :
    a = b := by
  obtain ⟨_, i, it, m, c⟩ := h₁
  obtain ⟨_, i', it', m', c'⟩ := h₂
  have ei := items_unique it it'
  subst ei
  cases a
  cases b
  simp only at m c m' c' ⊢
  have em := modulePath_unique m m'
  subst em
  rw [collect_unique c c']

theorem collectedR_unique : ∀ {roots : List CTree} {a b : Collected}, CollectedR roots a → CollectedR roots b → a = b
  | _, _, _, .nil, .nil => rfl
  | _, _, _, .cons f r, .cons f' r' => by rw [fileDeclsR_unique f f', collectedR_unique r r']

end Lanius.Mini.Reading
