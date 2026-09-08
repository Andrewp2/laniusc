import Lanius.Extraction.BufferCopy.Source
import Lanius.Separation.SliceCopy

namespace Lanius.Extraction.BufferCopy

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

def buffer (untouched processed : List Int) : List Int :=
  processed ++ untouched.drop processed.length

theorem buffer_length (untouched processed : List Int)
    (bound : processed.length ≤ untouched.length) :
    (buffer untouched processed).length = untouched.length := by
  simp only [buffer, List.length_append, List.length_drop]
  omega

theorem buffer_step (untouched processed : List Int) (value : Int)
    (room : processed.length < untouched.length) :
    (buffer untouched processed).set processed.length value =
      buffer untouched (processed ++ [value]) := by
  cases remaining : untouched.drop processed.length with
  | nil =>
      have lengths := congrArg List.length remaining
      simp only [List.length_drop, List.length_nil] at lengths
      omega
  | cons old rest =>
      have next : untouched.drop (processed.length + 1) = rest := by
        have dropped := congrArg (List.drop 1) remaining
        simpa [List.drop_drop, Nat.add_comm] using dropped
      simp [buffer, remaining, next, List.set_append_right, List.append_assoc]

structure Memory (locals : Locals) where
  sourceCell : CellId
  destinationCell : CellId
  cursorCell : CellId
  source : List Int
  untouched : List Int
  values : List Int
  count : Nat
  countLength : count * locals.countScale.factor = values.length
  selected : ∀ index value, values[index]? = some value →
    source[index * locals.readScale.factor]? = some value
  capacity : values.length ≤ untouched.length
  destinationFits : untouched.length ≤ 2147483647
  sourceFits : source.length ≤ 2147483647
  source_destination : sourceCell ≠ destinationCell
  source_cursor : sourceCell ≠ cursorCell
  destination_cursor : destinationCell ≠ cursorCell

def Memory.writes (memory : Memory locals) : CellSet :=
  CellSet.union (CellSet.singleton memory.destinationCell) (CellSet.singleton memory.cursorCell)

structure Invariant (memory : Memory locals) (processed : List Int) (state : State) : Prop where
  wellFormed : StateWellFormed state
  sourceLocal : state.local? locals.source = some
    (.slice (.scalar (.signed .i32)) memory.sourceCell [] 0 memory.source.length)
  destinationLocal : state.local? locals.destination = some
    (.slice (.scalar (.signed .i32)) memory.destinationCell [] 0 memory.untouched.length)
  sourceContents : state.cellEntry? memory.sourceCell = some {
    id := memory.sourceCell, value := some (.array (signedI32Values memory.source)) }
  destinationContents : state.cellEntry? memory.destinationCell = some {
    id := memory.destinationCell, value := some (.array (signedI32Values (buffer memory.untouched processed))) }
  cursor : (Assertion.localPointsTo locals.cursor memory.cursorCell
    (some (.signed .i32 processed.length))).holds state
  count : state.local? locals.count = some (.signed .i32 memory.count)
  stable : ∀ localId, localId ∈ [locals.source, locals.destination, locals.count] →
    ∀ cell, state.cellId? localId = some cell → ¬ memory.writes cell

private theorem scaled_result (program : Program) (before : State) (scale : Scale)
    (id : VarId) (value : Nat) (found : before.local? id = some (.signed .i32 value))
    (fits : value * scale.factor ≤ 2147483647) :
    Evaluates program before (scale.expression id) (.signed .i32 (value * scale.factor : Nat)) before := by
  have localResult : Evaluates program before (.local id) (.signed .i32 value) before :=
    ⟨1, evalLocal_of_local 0 program before id _ found⟩
  cases scale with
  | plain => simpa [Scale.expression, Scale.factor] using localResult
  | triple =>
      exact evaluatesNatI32Multiply localResult
        (show Evaluates program before (.value (.signed .i32 3)) (.signed .i32 3) before from ⟨1, rfl⟩) fits

theorem body_step (program : Program) (locals : Locals) (memory : Memory locals)
    (processed remaining : List Int) (value : Int) (before : State)
    (source : memory.values = processed ++ value :: remaining)
    (invariant : Invariant memory processed before) :
    ∃ after, Executes program before locals.body .next after ∧
      Invariant memory (processed ++ [value]) after ∧ CellEffect memory.writes before after := by
  have valuesLength : memory.values.length = processed.length + 1 + remaining.length := by
    simp [source]; omega
  have room : processed.length < memory.untouched.length := by have := memory.capacity; omega
  have selected := memory.selected processed.length value (by simp [source])
  have readBound : processed.length * locals.readScale.factor < memory.source.length := by
    by_cases inside : processed.length * locals.readScale.factor < memory.source.length
    · exact inside
    · rw [List.getElem?_eq_none (by omega)] at selected
      contradiction
  have readValue : memory.source.get ⟨processed.length * locals.readScale.factor, readBound⟩ = value := by
    simpa only [List.getElem?_eq_getElem readBound, Option.some.injEq, List.get_eq_getElem] using selected
  have cursorLocal := Assertion.localPointsTo_local _ _ _ _ invariant.cursor
  have indexResult : Evaluates program before (.local locals.cursor) (.signed .i32 processed.length) before :=
    ⟨1, evalLocal_of_local 0 program before locals.cursor _ cursorLocal⟩
  have readResult := scaled_result program before locals.readScale locals.cursor processed.length cursorLocal
    (by have := memory.sourceFits; omega)
  have length := buffer_length memory.untouched processed (by omega)
  obtain ⟨copied, assignment, contents, _, copyEffect⟩ := evaluatesSliceCopy program before
    memory.source (buffer memory.untouched processed) locals.source locals.destination
    memory.sourceCell memory.destinationCell (processed.length * locals.readScale.factor) processed.length
    (locals.readScale.expression locals.cursor) (.local locals.cursor) invariant.wellFormed
    memory.source_destination readBound (by omega) invariant.sourceLocal
    (by simpa only [length] using invariant.destinationLocal) readResult indexResult
    invariant.sourceContents invariant.destinationContents
  rw [readValue, buffer_step memory.untouched processed value room] at contents
  have cursorStill := copyEffect.preserves_localPointsTo invariant.wellFormed invariant.cursor
    (by simpa [CellSet.singleton, eq_comm] using memory.destination_cursor)
  obtain ⟨after, incremented, afterWF, cursorAfter, incrementEffect⟩ := executesIncrementOwnedI32Local
    program copied locals.cursor memory.cursorCell processed.length copyEffect.wellFormed cursorStill
    (by have := memory.destinationFits; omega)
  have effect : CellEffect memory.writes before after :=
    (copyEffect.weaken CellSet.subset_union_left).trans
      ((CellEffect.ofModifiesOnly incrementEffect afterWF).weaken CellSet.subset_union_right)
  refine ⟨after, executesSequence (executesExpression assignment) incremented, ?_, effect⟩
  refine ⟨afterWF, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩
  · exact effect.preserves_local invariant.wellFormed invariant.sourceLocal (invariant.stable _ (by simp))
  · exact effect.preserves_local invariant.wellFormed invariant.destinationLocal (invariant.stable _ (by simp))
  · exact effect.preserves_entry invariant.wellFormed invariant.sourceContents
      (by simp [Memory.writes, CellSet.union, CellSet.singleton, memory.source_destination, memory.source_cursor])
  · exact incrementEffect.preserves_entry copyEffect.wellFormed contents memory.destination_cursor
  · simpa using cursorAfter
  · exact effect.preserves_local invariant.wellFormed invariant.count (invariant.stable _ (by simp))
  · intro localId member cell found
    apply invariant.stable localId member cell
    simpa only [State.cellId?, effect.locals] using found

theorem executes_loop (program : Program) (locals : Locals) (memory : Memory locals)
    (processed remaining : List Int) (before : State)
    (source : memory.values = processed ++ remaining)
    (invariant : Invariant memory processed before) :
    ∃ after, Executes program before locals.loop .next after ∧
      Invariant memory memory.values after ∧ CellEffect memory.writes before after := by
  have cursorResult : Evaluates program before (.local locals.cursor) (.signed .i32 processed.length) before :=
    ⟨1, evalLocal_of_local 0 program before locals.cursor _
      (Assertion.localPointsTo_local _ _ _ _ invariant.cursor)⟩
  have countResult := scaled_result program before locals.countScale locals.count memory.count invariant.count
    (by have := memory.countLength; have := memory.capacity; have := memory.destinationFits; omega)
  rw [memory.countLength] at countResult
  have condition : Evaluates program before
      (.binary .notEqual (.local locals.cursor) (locals.countScale.expression locals.count))
      (.boolean (!(Int.ofNat processed.length == Int.ofNat memory.values.length))) before := by
    apply evaluatesEagerBinary (by decide) (by decide) cursorResult countResult
    simp [evalBinaryValue, scalarEqual]
  cases remaining with
  | nil =>
      have complete : memory.values = processed := by simpa using source
      refine ⟨before, executesWhileFalse ?_, ?_, CellEffect.refl invariant.wellFormed⟩
      · simpa [complete] using condition
      · simpa [complete] using invariant
  | cons value rest =>
      have different : Int.ofNat processed.length ≠ Int.ofNat memory.values.length := by
        intro equal
        have equalNat := Int.ofNat.inj equal
        simp only [source, List.length_append, List.length_cons] at equalNat
        omega
      have conditionTrue : Evaluates program before
          (.binary .notEqual (.local locals.cursor) (locals.countScale.expression locals.count))
          (.boolean true) before := by
        rw [beq_eq_false_iff_ne.mpr different] at condition
        exact condition
      obtain ⟨middle, body, nextInvariant, bodyEffect⟩ :=
        body_step program locals memory processed rest value before source invariant
      obtain ⟨after, loop, complete, loopEffect⟩ := executes_loop program locals memory
        (processed ++ [value]) rest middle (by simpa [List.append_assoc] using source) nextInvariant
      exact ⟨after, executesWhileTrue conditionTrue body loop, complete, bodyEffect.trans loopEffect⟩
termination_by remaining.length

/-- Any successful observed execution agrees with the total loop contract,
regardless of the fuel used by its caller. -/
theorem loop_sound (program : Program) (locals : Locals) (memory : Memory locals)
    (processed remaining : List Int) (before after : State)
    (source : memory.values = processed ++ remaining)
    (invariant : Invariant memory processed before)
    (actual : Executes program before locals.loop completion after) :
    completion = .next ∧ Invariant memory memory.values after ∧
      CellEffect memory.writes before after := by
  obtain ⟨expected, executed, complete, effect⟩ :=
    executes_loop program locals memory processed remaining before source invariant
  obtain ⟨sameCompletion, sameState⟩ := Lanius.Fuel.executes_deterministic actual executed
  subst after
  exact ⟨sameCompletion, complete, effect⟩

theorem checked_loop_executes (program : Program)
    (checked : Source.CheckedStatement Locals.loop statement)
    (memory : Memory checked.locals) (before : State)
    (invariant : Invariant memory [] before) :
    ∃ after, Executes program before statement .next after ∧
      Invariant memory memory.values after ∧ CellEffect memory.writes before after := by
  rcases checked with ⟨locals, rfl⟩
  exact executes_loop program locals memory [] memory.values before rfl invariant

end Lanius.Extraction.BufferCopy
