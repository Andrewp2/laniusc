import Lanius.FunctionalViewCoreEffectfulStateful

namespace Lanius.FunctionalView.Core.Stateful

open Lanius
open Lanius.Core
open Lanius.Properties
open Lanius.Semantics
open Lanius.Separation
open Lanius.FunctionalView
open Lanius.FunctionalView.Core

/-! # Closing source-call frames

Function parameters and FunctionalView temporaries are allocated above the
caller's `nextCell`.  This module packages the exact freshness fact needed to
turn a callee-local write set into an empty caller-visible write set. -/

/-- Canonical physical cells allocated for a dense parameter environment. -/
def callLocalCells (caller : State) : Fin arity → CellId :=
  fun index => caller.nextCell + index.val

theorem callLocalCells_injective :
    Function.Injective (callLocalCells (arity := arity) caller) := by
  intro left right same
  apply Fin.ext
  simp only [callLocalCells] at same
  exact Nat.add_left_cancel same

theorem callLocalFootprint_fresh
    (member : localFootprint (callLocalCells (arity := arity) caller) cell) :
    caller.nextCell ≤ cell := by
  obtain ⟨index, rfl⟩ := member
  simp [callLocalCells]

/-- Entering a checked source call with canonical dense parameter bindings
constructs the complete callee representation.  Parameter-cell identities are
derived from allocation order rather than guessed by each caller proof. -/
theorem Representation.enterCallParameters
    (represented : Representation layout localCell world callerEnvironment
      caller)
    (callerWellFormed : StateWellFormed caller) :
    Representation identityLayout (callLocalCells caller) world environment
      (enterCall caller (parameterBindings environment)) := by
  let bindings := parameterBindings environment
  let base : State := { caller with locals := [] }
  have baseWellFormed : StateWellFormed base := by
    simpa [base] using clearLocals_preserves_wellFormed callerWellFormed
  refine {
    worldOwned := ?_
    localOwned := ?_
    localCellsInjective := callLocalCells_injective
    worldLocalsDisjoint := ?_
  }
  · intro cell values found
    have beforeEntry := represented.worldOwned cell values found
    have below := StateWellFormed.cell_lt_next_of_entry callerWellFormed
      beforeEntry
    exact ((enterCall_effect caller bindings).oldCells cell below
      (fun written => written)).trans beforeEntry
  · intro index
    have indexBound : index.val < bindings.length := by
      simpa [bindings] using index.isLt
    have selected : bindings[index.val] =
        (index.val, environment index) := by
      simpa [bindings] using
        parameterBindings_getElem environment index.val index.isLt
    have decomposition : bindings =
        bindings.take index.val ++
          (index.val, environment index) :: bindings.drop (index.val + 1) := by
      calc
        bindings = bindings.take index.val ++ bindings.drop index.val :=
          (List.take_append_drop index.val bindings).symm
        _ = bindings.take index.val ++
            bindings[index.val] :: bindings.drop (index.val + 1) := by
          rw [List.getElem_cons_drop indexBound]
        _ = bindings.take index.val ++
            (index.val, environment index) ::
              bindings.drop (index.val + 1) := by rw [selected]
    have notRebound : ∀ binding,
        binding ∈ bindings.drop (index.val + 1) →
          binding.1 ≠ index.val := by
      intro binding member same
      rw [List.mem_drop_iff_getElem] at member
      obtain ⟨later, laterBound, laterAt⟩ := member
      have positionBound : index.val + 1 + later < bindings.length := by omega
      have laterValue : bindings[index.val + 1 + later] =
          (index.val + 1 + later,
            environment ⟨index.val + 1 + later, by
              simpa [bindings] using positionBound⟩) := by
        apply parameterBindings_getElem
      rw [laterValue] at laterAt
      have idEqual : index.val + 1 + later = binding.1 := by
        simpa using congrArg Prod.fst laterAt
      have impossible : index.val + 1 + later = index.val :=
        idEqual.trans same
      omega
    have owned := bindLocals_owns_binding base (bindings.take index.val)
      (bindings.drop (index.val + 1)) index.val (environment index)
      baseWellFormed notRebound
    have stateEq : enterCall caller (parameterBindings environment) =
        base.bindLocals
          (bindings.take index.val ++ (index.val, environment index) ::
            bindings.drop (index.val + 1)) := by
      simp only [enterCall, base, bindings]
      exact congrArg (State.bindLocals base) decomposition
    rw [stateEq]
    simpa [base, bindings, callLocalCells, identityLayout, indexBound] using owned
  · intro cell worldMember localMember
    have allocated := (ReadOnly.World.owns world).allocated
      represented.worldOwned callerWellFormed cell worldMember
    exact (Nat.not_le_of_lt allocated)
      (callLocalFootprint_fresh localMember)

/-- Restore a caller after a body that wrote only fresh callee cells.  The
result is frameable as an empty write effect, so every hidden caller local and
every read-only world resource is preserved. -/
theorem closeFreshCallFrame
    (callerWellFormed : StateWellFormed caller)
    (completedWellFormed : StateWellFormed completed)
    (bodyEffect : ModifiesOnly writes (enterCall caller bindings) completed)
    (writesFresh : ∀ cell, writes cell → caller.nextCell ≤ cell) :
    let after := restoreLocals caller completed
    ModifiesOnly CellSet.empty caller after ∧ StateWellFormed after := by
  let callee := enterCall caller bindings
  let after := restoreLocals caller completed
  have entered : StoreEffect writes caller callee :=
    (enterCall_effect caller bindings).weaken CellSet.empty_subset
  have total : StoreEffect writes caller completed := by
    simpa [callee] using entered.trans_same bodyEffect.toStoreEffect
  have hidden : StoreEffect CellSet.empty caller completed :=
    total.hideFreshWrites writesFresh
  exact ⟨by simpa [after] using hidden.restoreLocals,
    by simpa [after] using
      (hidden.restoreLocals_wellFormed callerWellFormed
        completedWellFormed)⟩

/-- Rebuild the caller's complete FunctionalView representation after closing
a fresh callee frame. -/
theorem Representation.restoreFreshCall
    (represented : Representation layout localCell world environment caller)
    (callerWellFormed : StateWellFormed caller)
    (completedWellFormed : StateWellFormed completed)
    (bodyEffect : ModifiesOnly writes (enterCall caller bindings) completed)
    (writesFresh : ∀ cell, writes cell → caller.nextCell ≤ cell) :
    let after := restoreLocals caller completed
    StateWellFormed after ∧
      Representation layout localCell world environment after ∧
      ModifiesOnly CellSet.empty caller after := by
  let after := restoreLocals caller completed
  obtain ⟨effect, afterWellFormed⟩ := closeFreshCallFrame
    callerWellFormed completedWellFormed bodyEffect writesFresh
  have afterRepresented :
      Representation layout localCell world environment after := {
    worldOwned := effect.empty_preserves_assertion callerWellFormed
      (ReadOnly.World.owns world) represented.worldOwned
    localOwned := fun index =>
      effect.empty_preserves_assertion callerWellFormed
        (Assertion.localPointsTo (layout index) (localCell index)
          (some (environment index))) (represented.localOwned index)
    localCellsInjective := represented.localCellsInjective
    worldLocalsDisjoint := represented.worldLocalsDisjoint
  }
  exact ⟨afterWellFormed, afterRepresented, effect⟩

/-- Common specialization for a body whose writes are exactly bounded by the
canonical dense parameter cells. -/
theorem Representation.restoreCallLocals
    (represented : Representation layout localCell world environment caller)
    (callerWellFormed : StateWellFormed caller)
    (completedWellFormed : StateWellFormed completed)
    (bodyEffect : ModifiesOnly
      (localFootprint (callLocalCells (arity := calleeArity) caller))
      (enterCall caller bindings) completed) :
    let after := restoreLocals caller completed
    StateWellFormed after ∧
      Representation layout localCell world environment after ∧
      ModifiesOnly CellSet.empty caller after := by
  exact represented.restoreFreshCall callerWellFormed completedWellFormed
    bodyEffect (fun _ member => callLocalFootprint_fresh member)

end Lanius.FunctionalView.Core.Stateful
