import Lanius.Cert.Model

/-! A node's value is its tree's value. -/

namespace Lanius.Cert

theorem denTms_map (M : Model) (σ : Nat → Nat) (f : Nat → Tm) :
    ∀ xs : List Nat, denTms M σ (xs.map f) = xs.map fun i => denTm M σ (f i)
  | [] => rfl
  | x :: xs => by simp only [List.map_cons, denTms, denTms_map M σ f xs]

theorem den_decode (M : Model) (w : Words) (σ : Nat → Nat) (n : Int) :
    den M w σ n = denTm M σ (decode w n) := by
  induction h : n.toNat using Nat.strongRecOn generalizing n with
  | _ m ih =>
    rw [den, decode]
    by_cases nonneg : 0 ≤ n
    · simp only [if_pos nonneg]
      by_cases var : head w n = VAR
      · simp only [if_pos var, denTm]
      · simp only [if_neg var, denTm, denTms_map]
        congr 1
        apply List.map_congr_left
        intro i _
        by_cases hx : 0 ≤ arg w n i ∧ arg w n i < n
        · simp only [dif_pos hx]
          exact ih _ (by omega) _ rfl
        · simp only [dif_neg hx, denTm]
    · simp only [if_neg nonneg, denTm]

end Lanius.Cert
