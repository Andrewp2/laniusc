import Lanius.Extraction.OutputPacking.Loop

namespace Lanius.Extraction.OutputPacking

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

def clearedPrefix (count : Nat) (values : List Int) : List Int :=
  List.replicate count 0 ++ values.drop count

theorem clearedPrefix_length (values : List Int) (count : Nat) (bound : count ≤ values.length) :
    (clearedPrefix count values).length = values.length := by
  simp only [clearedPrefix, List.length_append, List.length_replicate, List.length_drop]
  omega

theorem clearedPrefix_step (values : List Int) (count : Nat) (bound : count < values.length) :
    setI32Value (clearedPrefix count values) count 0 = clearedPrefix (count + 1) values := by
  induction values generalizing count with
  | nil => simp at bound
  | cons first rest induction =>
      cases count with
      | zero => simp [clearedPrefix, setI32Value]
      | succ count =>
          have restBound : count < rest.length := by simpa using bound
          simpa [clearedPrefix, setI32Value, List.replicate_succ] using
            congrArg (0 :: ·) (induction count restBound)

structure ClearMemory where
  workspaceCell : CellId
  cursorCell : CellId
  original : List Int
  words : Nat
  capacity : words ≤ original.length
  bounded : words ≤ 2147483647
  distinct : workspaceCell ≠ cursorCell

def ClearMemory.writes (memory : ClearMemory) :=
  CellSet.union (CellSet.singleton memory.workspaceCell) (CellSet.singleton memory.cursorCell)

structure ClearInvariant (memory : ClearMemory) (locals : LoopLocals)
    (position : Nat) (state : State) : Prop where
  wellFormed : StateWellFormed state
  workspaceLocal : state.local? locals.workspace = some
    (.slice (.scalar (.signed .i32)) memory.workspaceCell [] 0 memory.original.length)
  contents : state.cellEntry? memory.workspaceCell = some {
    id := memory.workspaceCell
    value := some (.array (signedI32Values (clearedPrefix position memory.original))) }
  cursor : (Assertion.localPointsTo locals.cursor memory.cursorCell
    (some (.signed .i32 position))).holds state
  limit : state.local? locals.length = some (.signed .i32 memory.words)
  stable : ∀ localId, localId ∈ [locals.workspace, locals.length] →
    ∀ cell, state.cellId? localId = some cell → ¬ memory.writes cell

private theorem clear_body_step (program : Program) (memory : ClearMemory) (locals : LoopLocals)
    (position : Nat) (before : State) (bound : position < memory.words)
    (invariant : ClearInvariant memory locals position before) :
    ∃ after, Executes program before locals.clearBody .next after ∧
      ClearInvariant memory locals (position + 1) after ∧
      ModifiesOnly memory.writes before after := by
  have inBounds : position < memory.original.length := Nat.lt_of_lt_of_le bound memory.capacity
  have lengthEq := clearedPrefix_length memory.original position (Nat.le_of_lt inBounds)
  have cursorResult : Evaluates program before (.local locals.cursor) (.signed .i32 position) before :=
    ⟨1, evalLocal_of_local 0 program before locals.cursor _
      (Assertion.localPointsTo_local _ _ _ _ invariant.cursor)⟩
  have zeroResult : Evaluates program before (.value (.signed .i32 0)) (.signed .i32 0) before :=
    ⟨1, rfl⟩
  obtain ⟨cleared, assignment, clearedWF, clearedContents, clearEffect⟩ :=
    evaluatesSetSignedI32SliceIndexFromEmpty program before before before
      (clearedPrefix position memory.original) locals.workspace (.local locals.cursor)
      (.value (.signed .i32 0)) memory.workspaceCell position 0
      (by simpa [lengthEq] using inBounds)
      (by simpa [lengthEq] using invariant.workspaceLocal)
      cursorResult invariant.wellFormed (ModifiesOnly.refl _)
      zeroResult invariant.wellFormed (ModifiesOnly.refl _) invariant.contents
  rw [clearedPrefix_step memory.original position inBounds] at clearedContents
  have cursorStill := clearEffect.preserves_localPointsTo invariant.wellFormed invariant.cursor
    (by simpa [CellSet.singleton, eq_comm] using memory.distinct)
  have incrementBound : position + 1 ≤ 2147483647 := by have := memory.bounded; omega
  obtain ⟨after, increment, afterWF, afterCursor, incrementEffect⟩ :=
    executesIncrementOwnedI32Local program cleared locals.cursor memory.cursorCell position
      clearedWF cursorStill incrementBound
  have effect := clearEffect.trans incrementEffect
  refine ⟨after, executesSequence (executesExpression assignment) increment, ?_, effect⟩
  refine ⟨afterWF, ?_, ?_, afterCursor, ?_, ?_⟩
  · exact effect.preserves_local invariant.wellFormed invariant.workspaceLocal
      (invariant.stable _ (by simp))
  · exact incrementEffect.preserves_entry clearedWF clearedContents
      (by simpa [CellSet.singleton] using memory.distinct)
  · exact effect.preserves_local invariant.wellFormed invariant.limit
      (invariant.stable _ (by simp))
  · intro localId member cell found
    apply invariant.stable localId member cell
    simpa [State.cellId?, effect.locals] using found

theorem executes_clear_loop (program : Program) (memory : ClearMemory) (locals : LoopLocals)
    (position : Nat) (before : State) (bound : position ≤ memory.words)
    (invariant : ClearInvariant memory locals position before) :
    ∃ after, Executes program before locals.clearLoop .next after ∧
      ClearInvariant memory locals memory.words after ∧
      ModifiesOnly memory.writes before after := by
  have cursorResult : Evaluates program before (.local locals.cursor) (.signed .i32 position) before :=
    ⟨1, evalLocal_of_local 0 program before locals.cursor _
      (Assertion.localPointsTo_local _ _ _ _ invariant.cursor)⟩
  have limitResult : Evaluates program before (.local locals.length) (.signed .i32 memory.words) before :=
    ⟨1, evalLocal_of_local 0 program before locals.length _ invariant.limit⟩
  by_cases complete : position = memory.words
  · subst position
    refine ⟨before, executesWhileFalse ?_, invariant, ModifiesOnly.reflAny _ _⟩
    apply evaluatesEagerBinary (by decide) (by decide) cursorResult limitResult
    simp [evalBinaryValue, scalarEqual]
  · have active : position < memory.words := by omega
    have differentInt : Int.ofNat position ≠ Int.ofNat memory.words := by
      intro same
      exact complete (Int.ofNat.inj same)
    have condition : Evaluates program before
        (.binary .notEqual (.local locals.cursor) (.local locals.length)) (.boolean true) before := by
      apply evaluatesEagerBinary (by decide) (by decide) cursorResult limitResult
      simp only [evalBinaryValue, scalarEqual, BEq.rfl, if_true,
        Except.ok.injEq, Value.boolean.injEq]
      change (!(Int.ofNat position == Int.ofNat memory.words)) = true
      rw [beq_eq_false_iff_ne.mpr differentInt]
      rfl
    obtain ⟨middle, body, nextInvariant, bodyEffect⟩ :=
      clear_body_step program memory locals position before active invariant
    obtain ⟨after, rest, afterInvariant, restEffect⟩ :=
      executes_clear_loop program memory locals (position + 1) middle (by omega) nextInvariant
    exact ⟨after, executesWhileTrue condition body rest, afterInvariant,
      bodyEffect.trans_same restEffect⟩
termination_by memory.words - position

theorem ClearInvariant.initial_packing_contents
    (invariant : ClearInvariant memory locals memory.words state) :
    state.cellEntry? memory.workspaceCell = some {
      id := memory.workspaceCell
      value := some (.array (workspace memory.words []
        (signedI32Values (memory.original.drop memory.words)))) } := by
  simpa [workspace, pack, clearedPrefix, signedI32Values] using invariant.contents

end Lanius.Extraction.OutputPacking
