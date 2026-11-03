import Lanius.Open.F5.AssignAfterRhs.Stmt
import Lanius.Open.F5.RefStoreV2.Proof
import Lanius.Mini.Refs.HomedLemmas

open Lanius.Mini

/-- The address from `RPlace.addr_exec` in `st`, kept by `rhs`, below `2 ^ 62`
(`Homes.sub_lt`); then `RefStoreV2` in `st₁` at the home whose cell is the
place's. -/
theorem Lanius.Open.AssignAfterRhs.proof : Lanius.Open.AssignAfterRhs := by
  intro sx bud places st st₁ st' hp c p t code rhs ty cell path old v root root' cprog prog depth env scratch slot
    R homes agree hcode hres hruns hread tout fitTags hrhs hroot hrep hassign
  obtain ⟨x, mem, a, env₀, xcell, xsub, run, envT, same⟩ := RPlace.addr_exec homes agree tout p hcode hres hruns hread
  obtain ⟨env₁, hp₁, runR, keepT, homes₁, holds, hR⟩ := hrhs env₀ same
  obtain ⟨i, hi⟩ := List.mem_iff_getElem?.mp mem
  have ht : (env₁ t).toNat = a := by rw [keepT, envT, toNat_ofNat_small (homes.sub_lt mem xsub)]
  obtain ⟨hp', runS, homes', others, outside⟩ :=
    Lanius.Open.RefStoreV2.proof sx bud places st₁ st' hp₁ i x path a ty v root root' prog depth env₁ t slot
      homes₁ hi xsub fitTags ht (holds i x hi xcell) (by rw [xcell]; exact hroot) hrep (by rw [xcell]; exact hassign)
  exact ⟨env₁, hp₁, hp', hR, .seq run (.seq runR runS), homes', others, x, mem, a, xcell, xsub, outside⟩
