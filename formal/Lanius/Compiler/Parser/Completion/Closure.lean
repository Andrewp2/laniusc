import Lanius.Compiler.Parser.Completion.Pairs
import Lanius.Compiler.Parser.Scanning
import Lanius.Compiler.Parser.Seeding

namespace Lanius.Compiler.Parser

/-- Grammar derivations never consume a backwards token span, including
recursive and empty productions. -/
theorem RecognizesSymbol.start_le_finish
    (recognized : RecognizesSymbol grammar tokens symbol start finish) : start ≤ finish := by
  induction recognized using RecognizesSymbol.rec
      (motive_2 := fun _ start finish _ => start ≤ finish) with
  | terminal _ scanned => exact Nat.le_of_lt (scanTerminal_some_gt scanned)
  | nonterminal _ _ _ _ ih => exact ih
  | empty => exact Nat.le_refl _
  | cons _ _ head tail => exact Nat.le_trans head tail

theorem RecognizesSequence.start_le_finish
    (recognized : RecognizesSequence grammar tokens symbols start finish) : start ≤ finish := by
  induction symbols generalizing start with
  | nil => cases recognized; exact Nat.le_refl _
  | cons symbol symbols ih =>
      cases recognized with
      | cons head tail => exact Nat.le_trans head.start_le_finish (ih tail)

theorem EarleyStateSound.origin_le_position
    (sound : EarleyStateSound grammar tokens state) : state.origin ≤ state.position :=
  sound.recognizedPrefix.start_le_finish

private theorem state_position {id : Nat} (sound : ChartSound workspace)
    (listed : id ∈ workspace.chart position) (found : workspace.state? id = some state) :
    state.position = position := by
  obtain ⟨actual, stored, atPosition⟩ := sound position id listed
  have same := Option.some.inj (stored.symm.trans found)
  subst state
  exact atPosition

/-- Assemble the four source-loop guarantees on the same final workspace.
Its physical encoding supplies the position bound, and its derivations supply
the child-span bound. Neither is an assumption of successful parsing. -/
theorem ChartClosed.of_phases
    (seeded : StartSeeded grammar workspace)
    (predicted : PredictionsBefore grammar workspace (finalPosition tokens.length + 1))
    (scanned : ScansBefore grammar tokens workspace (finalPosition tokens.length + 1))
    (completed : CompletionsBefore grammar workspace (finalPosition tokens.length + 1))
    (sound : ChartSound workspace)
    (language : WorkspaceLanguageSound grammar tokens workspace)
    (bounded : ∀ id state, workspace.state? id = some state →
      state.position ≤ finalPosition tokens.length) :
    ChartClosed grammar tokens workspace := by
  have keyBound : ∀ position key, workspace.containsKey position key →
      position ≤ finalPosition tokens.length := by
    intro position key ⟨id, state, listed, found, _⟩
    have atPosition := state_position sound listed found
    simpa only [atPosition] using bounded id state found
  refine ⟨seeded, ?_, ?_, ?_⟩
  · intro parent child dot origin position waiting expected
    exact (predicted position (by have := keyBound position _ waiting; omega)).predict
      parent child dot origin waiting expected
  · intro production dot origin position kind finish waiting expected terminal matched
    exact (scanned position (by have := keyBound position _ waiting; omega)).scan
      production dot origin kind finish waiting expected terminal matched
  · intro parent child dot origin middle finish waiting expected finished
    have span : middle ≤ finish := by
      obtain ⟨id, state, listed, found, key⟩ := finished
      have atPosition := state_position sound listed found
      have origin : state.origin = middle := congrArg StateKey.origin key
      simpa only [atPosition, origin] using (language id state found).origin_le_position
    exact (completed finish (by have := keyBound finish _ finished; omega)).complete
      parent child dot origin middle span waiting expected finished

end Lanius.Compiler.Parser
