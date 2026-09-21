import Lanius.Semantics.MutableLocal

namespace Lanius.Semantics

open Lanius
open Lanius.Core

/-! Indexed facts for the fresh bindings introduced by `bindLocals`. -/

theorem State.bindLocals_nextCell (state : State) (bindings : List (VarId × Value)) :
    (state.bindLocals bindings).nextCell = state.nextCell + bindings.length := by
  induction bindings generalizing state with
  | nil => simp [State.bindLocals]
  | cons head tail inductionHypothesis =>
      change ((state.bindLocal head.1 head.2).bindLocals tail).nextCell =
        state.nextCell + (head :: tail).length
      rw [inductionHypothesis]
      simp [State.bindLocal, State.bindCell, Nat.add_comm, Nat.add_left_comm]

private theorem bindLocals_nodup_cons
    (head : VarId × Value) (tail : List (VarId × Value))
    (unique : ((head :: tail).map Prod.fst).Nodup) :
    head.1 ∉ tail.map Prod.fst ∧ (tail.map Prod.fst).Nodup :=
  List.nodup_cons.mp (by simpa only [List.map_cons] using unique)

private theorem bindLocals_cellId?_of_not_mem (state : State) (bindings : List (VarId × Value))
    (id : VarId) (cell : CellId) (notMem : ∀ binding ∈ bindings, binding.1 ≠ id)
    (found : state.cellId? id = some cell) :
    (state.bindLocals bindings).cellId? id = some cell := by
  induction bindings generalizing state with
  | nil => simpa [State.bindLocals] using found
  | cons head tail inductionHypothesis =>
      simp only [State.bindLocals, List.foldl_cons]
      apply inductionHypothesis (state := state.bindLocal head.1 head.2)
      · intro binding member
        exact notMem binding (by simp [member])
      · rw [State.bindLocal_cellId_of_ne state id head.1
          (notMem head (by simp)) head.2]
        exact found

private theorem bindLocals_local?_of_not_mem (state : State) (bindings : List (VarId × Value))
    (formed : state.CellsWellFormed) (id : VarId) (value : Value)
    (notMem : ∀ binding ∈ bindings, binding.1 ≠ id) (found : state.local? id = some value) :
    (state.bindLocals bindings).local? id = some value := by
  induction bindings generalizing state with
  | nil => simpa [State.bindLocals] using found
  | cons head tail inductionHypothesis =>
      simp only [State.bindLocals, List.foldl_cons]
      apply inductionHypothesis (state := state.bindLocal head.1 head.2)
        (formed := formed.bindCell head.1 (some head.2))
      · intro binding member
        exact notMem binding (by simp [member])
      · exact State.bindLocal_local?_of_ne state formed id head.1 value head.2
          (notMem head (by simp)) found

theorem State.bindLocals_cellId?_get? (state : State) (bindings : List (VarId × Value))
    (unique : (bindings.map Prod.fst).Nodup) (index : Nat) (binding : VarId × Value)
    (found : bindings[index]? = some binding) :
    (state.bindLocals bindings).cellId? binding.1 =
      some (state.nextCell + index) := by
  induction bindings generalizing state index with
  | nil => simp at found
  | cons head tail inductionHypothesis =>
      cases index with
      | zero =>
          simp only [List.getElem?_cons_zero] at found
          have foundEq : head = binding := Option.some.inj found
          subst binding
          have split := bindLocals_nodup_cons head tail unique
          apply bindLocals_cellId?_of_not_mem
            (state := state.bindLocal head.1 head.2) (id := head.1)
            (cell := state.nextCell)
          · intro item member same
            apply split.1
            exact List.mem_map.mpr ⟨item, member, same⟩
          · exact State.bindLocal_cellId state head.1 head.2
      | succ index =>
          have tailFound : tail[index]? = some binding := by
            simpa using found
          have tailUnique := (bindLocals_nodup_cons head tail unique).2
          change ((state.bindLocal head.1 head.2).bindLocals tail).cellId?
              binding.1 = some (state.nextCell + Nat.succ index)
          simpa [State.bindLocal, State.bindCell, Nat.succ_eq_add_one,
            Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using
              inductionHypothesis (state := state.bindLocal head.1 head.2)
              (index := index) tailUnique tailFound

theorem State.bindLocals_cellId?_get?_fresh (state : State) (bindings : List (VarId × Value))
    (unique : (bindings.map Prod.fst).Nodup) (index : Nat) (binding : VarId × Value)
    (found : bindings[index]? = some binding) (newId : VarId) (newValue : Value)
    (different : newId ≠ binding.1) :
    ((state.bindLocals bindings).bindLocal newId newValue).cellId?
        binding.1 ≠ some (state.bindLocals bindings).nextCell := by
  have oldCell := State.bindLocals_cellId?_get? state bindings unique index binding found
  have preserved := State.bindLocal_cellId_of_ne (state.bindLocals bindings) binding.1 newId different newValue
  have advanced := State.bindLocals_nextCell state bindings
  have indexLt : index < bindings.length := (List.getElem?_eq_some_iff.mp found).choose
  intro equal
  rw [preserved, oldCell, advanced] at equal
  have unequal : state.nextCell + index ≠
      state.nextCell + bindings.length := by
    intro same
    exact Nat.ne_of_lt indexLt (Nat.add_left_cancel same)
  exact unequal (Option.some.inj equal)

theorem State.bindLocals_local?_get? (state : State) (bindings : List (VarId × Value))
    (formed : state.CellsWellFormed) (unique : (bindings.map Prod.fst).Nodup)
    (index : Nat) (binding : VarId × Value) (found : bindings[index]? = some binding) :
    (state.bindLocals bindings).local? binding.1 = some binding.2 := by
  induction bindings generalizing state index with
  | nil => simp at found
  | cons head tail inductionHypothesis =>
      cases index with
      | zero =>
          simp only [List.getElem?_cons_zero] at found
          have foundEq : head = binding := Option.some.inj found
          subst binding
          have split := bindLocals_nodup_cons head tail unique
          apply bindLocals_local?_of_not_mem
            (state := state.bindLocal head.1 head.2)
            (bindings := tail) (formed := formed.bindCell head.1 (some head.2))
            (id := head.1) (value := head.2)
          · intro item member same
            apply split.1
            exact List.mem_map.mpr ⟨item, member, same⟩
          · exact State.bindLocal_local? state formed head.1 head.2
      | succ index =>
          have tailFound : tail[index]? = some binding := by
            simpa using found
          have tailUnique := (bindLocals_nodup_cons head tail unique).2
          change ((state.bindLocal head.1 head.2).bindLocals tail).local?
              binding.1 = some binding.2
          exact inductionHypothesis (state := state.bindLocal head.1 head.2)
            (formed := formed.bindCell head.1 (some head.2))
            (index := index) tailUnique tailFound

theorem State.bindLocals_cellId?_get?_ne (state : State) (bindings : List (VarId × Value))
    (unique : (bindings.map Prod.fst).Nodup) (leftIndex rightIndex : Nat)
    (left right : VarId × Value) (leftFound : bindings[leftIndex]? = some left)
    (rightFound : bindings[rightIndex]? = some right) (different : leftIndex ≠ rightIndex) :
    (state.bindLocals bindings).cellId? left.1 ≠
      (state.bindLocals bindings).cellId? right.1 := by
  rw [State.bindLocals_cellId?_get? state bindings unique leftIndex left leftFound,
    State.bindLocals_cellId?_get? state bindings unique rightIndex right rightFound]
  exact fun equal => different (Nat.add_left_cancel (Option.some.inj equal))

end Lanius.Semantics
