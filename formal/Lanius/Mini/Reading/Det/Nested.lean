import Lanius.Mini.Reading.Det.Arms

/-! # Determinism: a match expression's arm order

`MatchOrder` gives one list: its branches are told apart by whether some arm
is nested; the plain one is `armsOrder_unique`, the nested one
`nestedOrder_unique` (`Reading/Nested`). -/

namespace Lanius.Mini.Reading

open Lanius.Mini Lanius.Mini.Prod

theorem matchOrder_unique {env : FrontEnv} {owner : TypeDecl} {vs : List VariantTy} (nd : (vs.map (·.name)).Nodup)
    {arms os₁ os₂ : List CTree} (o₁ : MatchOrder env owner vs arms os₁) (o₂ : MatchOrder env owner vs arms os₂)
    (h₁ : ListRel (ArmNames owner) os₁ (vs.map (·.name))) (h₂ : ListRel (ArmNames owner) os₂ (vs.map (·.name))) :
    os₁ = os₂ := by
  rcases o₁ with ⟨pl₁, ord₁⟩ | ⟨⟨a, ma, na⟩, ord₁⟩ <;> rcases o₂ with ⟨pl₂, ord₂⟩ | ⟨⟨a', ma', na'⟩, ord₂⟩
  · exact armsOrder_unique nd ord₁ ord₂ h₁ h₂
  · exact (pl₁ a' ma' na').elim
  · exact (pl₂ a ma na).elim
  · exact nestedOrder_unique ord₁ ord₂

theorem stmtOrder_unique {env : FrontEnv} {owner : TypeDecl} {vs : List VariantTy} (nd : (vs.map (·.name)).Nodup)
    {arms os₁ os₂ : List CTree} (o₁ : StmtOrder env owner vs arms os₁) (o₂ : StmtOrder env owner vs arms os₂)
    (h₁ : ListRel (ArmNames owner) os₁ (vs.map (·.name))) (h₂ : ListRel (ArmNames owner) os₂ (vs.map (·.name))) :
    os₁ = os₂ := by
  rcases o₁ with ⟨pl₁, ord₁⟩ | ⟨⟨a, ma, na⟩, ord₁⟩ <;> rcases o₂ with ⟨pl₂, ord₂⟩ | ⟨⟨a', ma', na'⟩, ord₂⟩
  · exact armsOrder_unique nd ord₁ ord₂ h₁ h₂
  · exact (pl₁ a' ma' na').elim
  · exact (pl₂ a ma na).elim
  · exact nestedRows_unique ord₁ ord₂

end Lanius.Mini.Reading
