import Lanius.Faithful.Safe.Stmt
import Lanius.Faithful.Safe.Prims
import Lanius.Faithful.Sim.Func

/-! # No call Core runs traps undefined

By strong induction on the fuel, beside `func_sim`: a function the purity
checker accepts traps only definedly (`body_safe`, with the calls below), and
so do `boxed` and `unbox` (`boxed_safe`, `unbox_safe`). -/

namespace Lanius.Faithful

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (State)

section
variable {sp : SrcProgram} {prims : Prims} {outside : List Nat}

theorem func_safe (pure : PureProg sp prims outside) (primsOk : PrimsOk sp prims) :
    ∀ m, FuncSafe sp prims outside m := by
  have calls := func_sim pure primsOk
  intro m
  induction m using Nat.strongRecOn with
  | _ m ih =>
  intro c f values ps st completed r found notOut len inv bound args run
  cases hp : prims.isPrim c with
  | false => exact body_safe calls (fun i lt => ih i lt) (pure c f found hp notOut) inv bound args run
  | true =>
    have mem : c ∈ prims.boxed ∨ c ∈ prims.unbox := by simpa [Prims.isPrim] using hp
    rcases mem with mem | mem
    · obtain ⟨t, id, sizeOf, slice, panic, hf, hs, hl, hpn, el, -, laid⟩ := primsOk.1 c mem
      rw [hf, Option.some.injEq] at found
      subst found
      exact boxed_safe hs hl hpn el laid inv args _ _ _ run bound
    · obtain ⟨t, id, slice, hf, hl, el, box⟩ := primsOk.2 c mem
      rw [hf, Option.some.injEq] at found
      subst found
      exact unbox_safe hl el box inv args _ _ _ run bound

end

end Lanius.Faithful
