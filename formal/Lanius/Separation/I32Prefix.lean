import Lanius.Separation.CellEffect

namespace Lanius.Separation

open Lanius.Core Lanius.Semantics Lanius.Properties

/-- Meaningful i32 elements followed by arbitrary spare capacity. The physical
slice length is retained; the unused suffix is not part of the logical input. -/
def I32Prefix (state : State) (cell : CellId) (capacity : Nat) (values : List Int) : Prop :=
  ∃ unused : List Int, values.length + unused.length = capacity ∧
    state.cellEntry? cell = some {
      id := cell, value := some (.array (signedI32Values (values ++ unused))) }

theorem I32Prefix.length_le (owned : I32Prefix state cell capacity values) :
    values.length ≤ capacity := by
  obtain ⟨unused, length, _⟩ := owned
  omega

theorem I32Prefix.preserved (owned : I32Prefix before cell capacity values)
    (wellFormed : StateWellFormed before) (effect : CellEffect writes before after)
    (untouched : ¬ writes cell) : I32Prefix after cell capacity values := by
  obtain ⟨unused, length, contents⟩ := owned
  exact ⟨unused, length, effect.preserves_entry wellFormed contents untouched⟩

/-- Reading within the meaningful prefix is independent of spare contents,
even when the source expression evaluates to a full-capacity slice. -/
theorem I32Prefix.read (owned : I32Prefix before cell capacity values)
    (program : Program) (slice indexExpression : Expr) (index : Nat)
    (bound : index < values.length)
    (sliceResult : Evaluates program before slice
      (.slice (.scalar (.signed .i32)) cell [] 0 capacity) before)
    (indexResult : Evaluates program before indexExpression (.signed .i32 index) before) :
    Evaluates program before (.index slice indexExpression)
      (.signed .i32 (values.get ⟨index, bound⟩)) before := by
  obtain ⟨unused, length, contents⟩ := owned
  have fullBound : index < (values ++ unused).length := by simp only [List.length_append]; omega
  have read := evaluatesSignedI32SliceIndex program before before before (values ++ unused)
    slice indexExpression cell index fullBound
    (by simpa only [List.length_append, length] using sliceResult) indexResult contents
  have selected : (values ++ unused).get ⟨index, fullBound⟩ = values.get ⟨index, bound⟩ := by
    have same := List.getElem?_append_left (l₂ := unused) bound
    simpa only [List.getElem?_eq_getElem fullBound, List.getElem?_eq_getElem bound,
      Option.some.injEq, List.get_eq_getElem] using same
  simpa only [selected] using read

/-- A local slice and its backing storage agree on physical capacity, while
only `values` belong to the logical input. Hiding the capacity keeps loop
invariants independent of the caller's allocation size. -/
def I32PrefixLocal (state : State) (localId : VarId) (cell : CellId)
    (values : List Int) : Prop :=
  ∃ capacity, state.local? localId =
      some (.slice (.scalar (.signed .i32)) cell [] 0 capacity) ∧
    I32Prefix state cell capacity values

theorem I32PrefixLocal.of_storage
    (sliceLocal : state.local? localId =
      some (.slice (.scalar (.signed .i32)) cell [] 0 capacity))
    (storage : I32Prefix state cell capacity values) :
    I32PrefixLocal state localId cell values :=
  ⟨capacity, sliceLocal, storage⟩

theorem I32PrefixLocal.exists_unused
    (owned : I32PrefixLocal state localId cell values) :
    ∃ unused : List Int,
      state.local? localId = some (.slice (.scalar (.signed .i32)) cell [] 0
        (values.length + unused.length)) ∧
      state.cellEntry? cell = some {
        id := cell
        value := some (.array (signedI32Values (values ++ unused))) } := by
  obtain ⟨capacity, sliceLocal, unused, length, contents⟩ := owned
  exact ⟨unused, by simpa only [length] using sliceLocal, contents⟩

/-- A proof-facing name for the physical suffix. Uniqueness below makes the
choice independent of which resource proof a loop step reconstructs. -/
noncomputable def I32PrefixLocal.unused
    (owned : I32PrefixLocal state localId cell values) : List Int :=
  Classical.choose owned.exists_unused

theorem I32PrefixLocal.unused_local
    (owned : I32PrefixLocal state localId cell values) :
    state.local? localId = some (.slice (.scalar (.signed .i32)) cell [] 0
      (values.length + owned.unused.length)) :=
  (Classical.choose_spec owned.exists_unused).1

theorem I32PrefixLocal.unused_backing
    (owned : I32PrefixLocal state localId cell values) :
    state.cellEntry? cell = some {
      id := cell
      value := some (.array (signedI32Values (values ++ owned.unused))) } :=
  (Classical.choose_spec owned.exists_unused).2

theorem I32PrefixLocal.unused_eq_of_backing
    (owned : I32PrefixLocal state localId cell values)
    (backing : state.cellEntry? cell = some {
      id := cell
      value := some (.array (signedI32Values (values ++ suffix))) }) :
    owned.unused = suffix := by
  have cells := Option.some.inj (owned.unused_backing.symm.trans backing)
  have arrays := Option.some.inj (congrArg Cell.value cells)
  have encoded : signedI32Values (values ++ owned.unused) =
      signedI32Values (values ++ suffix) := by injection arrays
  exact List.append_cancel_left (signedI32Values_injective encoded)

theorem I32PrefixLocal.unused_preserved
    (beforeOwned : I32PrefixLocal before beforeLocal cell values)
    (afterOwned : I32PrefixLocal after afterLocal cell values)
    (wellFormed : StateWellFormed before) (effect : CellEffect writes before after)
    (untouched : ¬ writes cell) : afterOwned.unused = beforeOwned.unused :=
  afterOwned.unused_eq_of_backing
    (effect.preserves_entry wellFormed beforeOwned.unused_backing untouched)

theorem I32PrefixLocal.transport
    (owned : I32PrefixLocal before localId cell values)
    (preserveLocal : ∀ capacity,
      before.local? localId = some (.slice (.scalar (.signed .i32)) cell [] 0 capacity) →
      after.local? localId = some (.slice (.scalar (.signed .i32)) cell [] 0 capacity))
    (preserveEntry : ∀ contents, before.cellEntry? cell = some { id := cell, value := contents } →
      after.cellEntry? cell = some { id := cell, value := contents }) :
    I32PrefixLocal after localId cell values := by
  obtain ⟨capacity, sliceLocal, unused, length, contents⟩ := owned
  exact ⟨capacity, preserveLocal _ sliceLocal, unused, length, preserveEntry _ contents⟩

/-- Preserve the same capacity and suffix, rather than choosing unrelated
witnesses for the local and backing array after a loop step. -/
theorem I32PrefixLocal.preserved
    (owned : I32PrefixLocal before localId cell values)
    (preserveLocal : ∀ value, before.local? localId = some value →
      after.local? localId = some value)
    (wellFormed : StateWellFormed before) (effect : CellEffect writes before after)
    (untouched : ¬ writes cell) : I32PrefixLocal after localId cell values := by
  obtain ⟨capacity, sliceLocal, storage⟩ := owned
  exact ⟨capacity, preserveLocal _ sliceLocal,
    storage.preserved wellFormed effect untouched⟩

theorem I32PrefixLocal.read
    (owned : I32PrefixLocal state localId cell values)
    (program : Program) (indexExpression : Expr) (index : Nat)
    (bound : index < values.length)
    (indexResult : Evaluates program state indexExpression (.signed .i32 index) state) :
    Evaluates program state (.index (.local localId) indexExpression)
      (.signed .i32 (values.get ⟨index, bound⟩)) state := by
  obtain ⟨capacity, sliceLocal, storage⟩ := owned
  exact storage.read program (.local localId) indexExpression index bound
    ⟨1, evalLocal_of_local 1 program state localId _ sliceLocal⟩ indexResult

/-- A fresh lexical binding preserves an existing slice and its exact spare
capacity unless it shadows the slice's local name. -/
theorem I32PrefixLocal.bindLocal (owned : I32PrefixLocal state localId cell values)
    (wellFormed : StateWellFormed state) (id : VarId) (value : Value) (different : id ≠ localId) :
    I32PrefixLocal (state.bindLocal id value) localId cell values := by
  apply owned.transport
  · intro capacity found
    exact (bindLocal_preserves_other_local wellFormed different).trans found
  · intro contents found
    exact ((bindLocal_effect state id value).oldCells cell
      (StateWellFormed.cell_lt_next_of_entry wellFormed found) (by simp [CellSet.empty])).trans found

end Lanius.Separation
