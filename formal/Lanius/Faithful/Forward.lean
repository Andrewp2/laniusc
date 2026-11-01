import Lanius.Faithful.Simulation
import Lanius.Faithful.Safe.Func
import Lanius.Faithful.Sim.Term

/-! # From pure calls to Core calls (review #5 step 3, piece (b))

`call_sim` goes backward: a Core call that completes means its pure call.
This file goes forward. A pure call settles (`Settles`, `pcall_complete`) to
an answer, `some w` or `none`.

* `none` (`call_settled_none`): Core never completes the call with the heap
  within `2 ^ 64`. Where Core does complete it, `call_sim` gives the pure call
  a value at that fuel, and more fuel keeps it (`pcall_mono`), against the
  settled `none`. With `func_safe`'s defined traps this is `Failing` at every
  fuel within any limit up to `2 ^ 64`.
* `some w`: Core completes the call (to come). -/

namespace Lanius.Faithful

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (State evalExpr)
open Lanius.Faithful.Termination (Settles)

section
variable {sp : SrcProgram} {prims : Prims} {outside : List Nat}

/-- A pure call settled to `none` is one Core never completes within the
`2 ^ 64` bound `call_sim` needs. -/
theorem call_settled_none (pure : PureProg sp prims outside) (primsOk : PrimsOk sp prims)
    {c : Nat} {f : SrcFunc} {args ps : List Value} {st : State}
    (found : sp.funcs[c]? = some f) (notOutside : outside.contains c = false) (inv : Inv st)
    (rel : VRels sp.toCore (boxElem sp prims) st.heap (f.params.map SrcParam.ty) args ps)
    {N : Nat} (settled : ∀ m, N ≤ m → pcall sp prims m c ps = none)
    (fuel : Nat) {v : Value} {st' : State}
    (run : evalExpr fuel sp.toCore st (.call c (args.map .value)) = .done v st') :
    2 ^ 64 < st'.heap.nextAddress := by
  refine Nat.lt_of_not_le fun bound => ?_
  obtain ⟨w, hw, -⟩ := call_sim pure primsOk found notOutside inv bound rel run
  have := pcall_mono sp prims fuel hw (Nat.le_max_left fuel N)
  rw [settled _ (Nat.le_max_right fuel N)] at this
  cases this

/-- A settled pure call: either it settles to a value, or Core never
completes it within `2 ^ 64`. -/
theorem call_settles (pure : PureProg sp prims outside) (primsOk : PrimsOk sp prims)
    {c : Nat} {f : SrcFunc} {args ps : List Value} {st : State}
    (found : sp.funcs[c]? = some f) (notOutside : outside.contains c = false) (inv : Inv st)
    (rel : VRels sp.toCore (boxElem sp prims) st.heap (f.params.map SrcParam.ty) args ps)
    (settles : Settles sp prims c ps) :
    (∃ N w, ∀ m, N ≤ m → pcall sp prims m c ps = some w) ∨
      ∀ fuel v st', evalExpr fuel sp.toCore st (.call c (args.map .value)) = .done v st' →
        2 ^ 64 < st'.heap.nextAddress := by
  obtain ⟨N, hN⟩ := settles
  cases h : pcall sp prims N c ps with
  | some w => exact Or.inl ⟨N, w, fun m hm => (hN m hm).trans h⟩
  | none =>
    exact Or.inr fun fuel v st' run =>
      call_settled_none pure primsOk found notOutside inv rel (fun m hm => (hN m hm).trans h) fuel run

theorem knowns_values {P : Core.Program} {st : State} :
    ∀ xs : List Value, Knowns P st (xs.map .value) xs
  | [] => knowns_nil
  | x :: xs => knowns_cons (known_value x) (knowns_values xs)

/-- **A pure call settled to `none` fails in Core**: at every fuel, Core's
call runs out of fuel, traps definedly, or ends past `limit`, for any
`limit` up to `2 ^ 64`. -/
theorem call_settled_none_failing (pure : PureProg sp prims outside) (primsOk : PrimsOk sp prims)
    {c : Nat} {f : SrcFunc} {args ps : List Value} {st : State}
    (found : sp.funcs[c]? = some f) (notOutside : outside.contains c = false) (inv : Inv st)
    (rel : VRels sp.toCore (boxElem sp prims) st.heap (f.params.map SrcParam.ty) args ps)
    {N : Nat} (settled : ∀ m, N ≤ m → pcall sp prims m c ps = none) {limit : Nat} (small : limit ≤ 2 ^ 64) :
    ∀ fuel, Failing limit (evalExpr fuel sp.toCore st (.call c (args.map .value))) := by
  have safe : SafeE sp.toCore st (.call c (args.map .value)) :=
    safeE_call_pure (func_safe pure primsOk) found notOutside (knowns_values args).safeEs fun h => by
      obtain ⟨rfl, rfl⟩ := (knowns_values args).done h
      exact ⟨inv, ps, rel⟩
  intro fuel
  cases h : evalExpr fuel sp.toCore st (.call c (args.map .value)) with
  | done v st' =>
    exact Nat.lt_of_le_of_lt small (call_settled_none pure primsOk found notOutside inv rel settled fuel h)
  | trapped r s =>
    show undefinedTrap r = false ∨ limit < s.heap.nextAddress
    by_cases bound : s.heap.nextAddress ≤ 2 ^ 64
    · exact Or.inl (safe fuel r s h bound)
    · exact Or.inr (Nat.lt_of_le_of_lt small (Nat.lt_of_not_le bound))
  | exited => trivial
  | outOfFuel => trivial

end

end Lanius.Faithful
