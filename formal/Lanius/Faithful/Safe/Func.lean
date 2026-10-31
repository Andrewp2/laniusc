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
open Lanius.Semantics (State evalExprs)

section
variable {sp : SrcProgram} {prims : Prims} {outside : List Nat}

/-- The purity checker accepts no `break` or `continue`, so a pure body has
no loose one. -/
theorem stmtOk_inside {boxes : Boxes} {ret : SrcType} :
    ∀ {tenv : TEnv} {s : SrcStmt}, stmtOk sp outside boxes ret tenv s = true → s.breaksOut = false := by
  intro tenv s
  induction s generalizing tenv with
  | «let» _ _ _ _ ih | letStruct _ _ _ _ ih | letCall _ _ _ _ _ ih | letEnum _ _ _ _ _ ih
  | letEval _ _ _ _ ih =>
    intro ok
    simp only [stmtOk] at ok
    split at ok
    · exact ih ok
    · simp at ok
  | «then» _ _ ih1 ih2 =>
    intro ok
    simp only [stmtOk, Bool.and_eq_true] at ok
    simp [SrcStmt.breaksOut, ih1 ok.1, ih2 ok.2]
  | «if» _ _ _ ih1 ih2 | ifEval _ _ _ ih1 ih2 =>
    intro ok
    simp only [stmtOk, Bool.and_eq_true] at ok
    simp [SrcStmt.breaksOut, ih1 ok.1.2, ih2 ok.2]
  | nop | letMatch | set | setField | setCall | «while» | «return» | letAlloc | letLoad | setByte
  | free | letSlice | letIndex | setIndex | setEval | whileEval | returnEval | discard | setIndexEval
  | setFieldEval | returnUnit | «assert» | «break» | «continue» | matchArm =>
    intro ok; simp_all [stmtOk, SrcStmt.breaksOut]

theorem func_safe (pure : PureProg sp prims outside) (primsOk : PrimsOk sp prims) :
    ∀ m, FuncSafe sp prims outside m := by
  have calls := func_sim pure primsOk
  intro m
  induction m using Nat.strongRecOn with
  | _ m ih =>
  intro c f values ps st completed r found notOut len inv bound args run
  cases hp : prims.isPrim c with
  | false =>
    rcases run with run | ⟨d, run, rfl | ⟨bad, -⟩⟩
    · exact body_safe calls (fun i lt => ih i lt) (pure c f found hp notOut) inv bound args run
    · rfl
    · have ends := stmt_ends sp m (stmtOk_inside (pure c f found hp notOut)) run
      rcases bad with rfl | rfl <;> exact ends.elim
  | true =>
    have mem : c ∈ prims.boxed ∨ c ∈ prims.unbox := by simpa [Prims.isPrim] using hp
    rcases mem with mem | mem
    · obtain ⟨t, id, sizeOf, slice, panic, hf, hs, hl, hpn, el, -, laid⟩ := primsOk.1 c mem
      rw [hf, Option.some.injEq] at found
      subst found
      rcases run with run | ⟨d, run, rfl | ⟨bad, -⟩⟩
      · exact boxed_safe hs hl hpn el laid inv args _ _ _ run bound
      · rfl
      · have ends := stmt_ends sp m (by simp [boxedFunc, SrcStmt.breaksOut]) run
        rcases bad with rfl | rfl <;> exact ends.elim
    · obtain ⟨t, id, slice, hf, hl, el, box⟩ := primsOk.2 c mem
      rw [hf, Option.some.injEq] at found
      subst found
      rcases run with run | ⟨d, run, rfl | ⟨bad, -⟩⟩
      · exact unbox_safe hl el box inv args _ _ _ run bound
      · rfl
      · have ends := stmt_ends sp m (by simp [unboxFunc, SrcStmt.breaksOut]) run
        rcases bad with rfl | rfl <;> exact ends.elim

/-- A call of a function inside the pure subset, on arguments whose
completed runs mean pure values: its body traps definedly. -/
theorem safeE_call_pure (fs : ∀ m, FuncSafe sp prims outside m) {c : Nat} {f : SrcFunc} {st : State}
    {args : List Core.Expr} (found : sp.funcs[c]? = some f) (notOut : outside.contains c = false)
    (sa : SafeEs sp.toCore st args)
    (rels : ∀ {k values s}, evalExprs k sp.toCore st args = .done values s →
      Inv s ∧ ∃ ps, VRels sp.toCore (boxElem sp prims) s.heap (f.params.map SrcParam.ty) values ps) :
    SafeE sp.toCore st (.call c args) := by
  intro k r s h bound
  obtain ⟨j, -, ha | ⟨values, after, hargs, ⟨-, arity⟩ | ⟨f', completed, found', -, rfl, hb⟩⟩⟩ :=
    call_trap_inv h
  · exact sa _ _ _ ha bound
  · obtain ⟨-, ps, rs⟩ := rels hargs
    exact (arity f found (VRels.length_params rs)).elim
  · rw [found, Option.some.injEq] at found'
    subst found'
    obtain ⟨inv, ps, rs⟩ := rels hargs
    exact fs (completed := completed) _ found notOut (VRels.length_params rs) inv bound rs hb

end

end Lanius.Faithful
