import Lanius.Faithful.Sim.Stmt
import Lanius.Faithful.Sim.Boxed

/-! # Every call Core completes

By strong induction on the fuel: a function the purity checker accepts runs
as `pcall` says (`body_sim`, with the calls below), and `boxed` and `unbox`
run as the identity on pure values (`boxed_sim`, `unbox_sim`). -/

namespace Lanius.Faithful

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (State)

section
variable {sp : SrcProgram} {prims : Prims} {outside : List Nat}

theorem func_sim (pure : PureProg sp prims outside) (primsOk : PrimsOk sp prims) :
    ∀ m, FuncSim sp prims outside m := by
  intro m
  induction m using Nat.strongRecOn with
  | _ m ih =>
  intro c f values ps st completed compl v found notOut len inv bound args run result
  cases hp : prims.isPrim c with
  | false => exact body_sim (fun i lt => ih i lt) found hp (pure c f found hp notOut) inv bound args run result
  | true =>
    have mem : c ∈ prims.boxed ∨ c ∈ prims.unbox := by simpa [Prims.isPrim] using hp
    rcases mem with mem | mem
    · obtain ⟨t, id, sizeOf, slice, panic, hf, hs, hl, hpn, el, box⟩ := primsOk.1 c mem
      rw [hf, Option.some.injEq] at found
      subst found
      exact boxed_sim hs hl hpn el box hp inv bound args run result
    · obtain ⟨t, id, slice, hf, hl, el, box⟩ := primsOk.2 c mem
      rw [hf, Option.some.injEq] at found
      subst found
      exact unbox_sim hl el box hp inv args run result

end

end Lanius.Faithful
