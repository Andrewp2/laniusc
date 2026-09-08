import Lanius.Extraction.RawLexer.LexInto.Frame
import Lanius.Extraction.RawLexer.LexInto.Buffer
import Lanius.Semantics.CellRenaming.Execution
import Lanius.Semantics.CellRenaming.Ownership
import Lanius.Semantics.CellRenaming.Effects

namespace Lanius.Extraction.RawLexer.LexInto.Caller
open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.FunctionalView.Core Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.FreshSimulation Lanius.CallContracts
open Lanius.Extraction.RawLexer.LexInto.Functions

def environment (sourceCell recordsCell : CellId) (source : List Compiler.Lexer.Byte)
    (records : List Int) (capacity : Nat) : FunctionalView.Env 4
  | ⟨0, _⟩ => .slice Structure.i32Type sourceCell [] 0 source.length
  | ⟨1, _⟩ => .signed .i32 (Int.ofNat source.length)
  | ⟨2, _⟩ => .slice Structure.i32Type recordsCell [] 0 records.length
  | ⟨3, _⟩ => .signed .i32 (Int.ofNat capacity)

theorem environment_renamed (rename : CellId → CellId) (source : List Compiler.Lexer.Byte)
    (records : List Int) (capacity : Nat) :
    (fun index => CellRenaming.value rename (Execution.initialEnvironment source records capacity index)) =
      environment (rename 0) (rename 1) source records capacity := by
  funext index
  obtain ⟨index, below⟩ := index
  have choices : index = 0 ∨ index = 1 ∨ index = 2 ∨ index = 3 := by omega
  rcases choices with rfl | rfl | rfl | rfl <;> rfl

/-- Apply the lexer body proof to an actual state whose buffer and local cells
use a different allocation layout. The inverse state is constructed inside
the proof, rather than demanded as a caller premise. -/
theorem body_executes
    (rename : CellRenaming.Permutation boundary)
    (invariant : CellRenaming.Execution.ProgramInvariant rename.forward verifiedFrontendCore)
    (request : Model.Request) (records : List Int)
    (recordsCapacity : 3 * request.capacity ≤ records.length)
    {localCell : Fin 4 → CellId} {before : State}
    (ready : boundary ≤ before.nextCell)
    (represented : Representation identityLayout (fun index => rename.forward (localCell index))
      (CellRenaming.world rename (Execution.world request.source records))
      (fun index => CellRenaming.value rename.forward
        (Execution.initialEnvironment request.source records request.capacity index)) before)
    (wellFormed : StateWellFormed before)
    (localsFresh : LocalsFresh boundary localCell) :
    ∃ after,
      Executes verifiedFrontendCore before lexIntoBody
        (CellRenaming.completion rename.forward (.returned (some (Model.resultValue request.outcome)))) after ∧
      StateWellFormed after ∧
      Representation identityLayout (fun index => rename.forward (localCell index))
        (CellRenaming.world rename (Execution.world request.source
          (Model.run request.source request.capacity records).records))
        (fun index => CellRenaming.value rename.forward
          (Execution.initialEnvironment request.source
            (Model.run request.source request.capacity records).records request.capacity index)) after ∧
      ModifiesOnly (CellSet.union (CellSet.singleton (rename.forward 1)) (freshCells boundary)) before after := by
  have modelRepresentation := CellRenaming.representation_inverse rename represented
  have modelWellFormed := CellRenaming.state_wellFormed rename.inverse ready wellFormed
  obtain ⟨completed, ran, completedWellFormed, completedRepresentation, effect⟩ :=
    Frame.body_executes request records recordsCapacity modelRepresentation modelWellFormed localsFresh ready
  obtain ⟨body, present, fixed⟩ := invariant.function lexIntoFunction.id lexIntoFunction
    verifiedFrontendCore_finds_lexInto
  rw [lexInto_has_body] at present
  cases Option.some.inj present
  obtain ⟨transport, completedReady⟩ := CellRenaming.Execution.executes
    (before := CellRenaming.state rename.backward before) invariant ready ran
  rw [fixed, CellRenaming.state_leftInverse _ _ rename.rightInverse] at transport
  have transportedEffect := CellRenaming.modifiesOnly rename
    (before := CellRenaming.state rename.backward before) ready effect
  rw [CellRenaming.state_leftInverse _ _ rename.rightInverse] at transportedEffect
  exact ⟨CellRenaming.state rename.forward completed, transport,
    CellRenaming.state_wellFormed rename completedReady completedWellFormed,
    CellRenaming.representation rename completedRepresentation, transportedEffect.weaken (by
      intro cell written
      rcases written with output | fresh
      · exact Or.inl ((rename.rightInverse cell).symm.trans (congrArg rename.forward output))
      · by_cases above : boundary ≤ cell
        · exact Or.inr above
        · exact (Nat.not_le_of_lt (rename.inverse.below (Nat.lt_of_not_ge above)) fresh).elim)⟩

/-- The public body contract names caller buffers directly. Choosing the
permutation and constructing model coordinates are internal proof steps. -/
theorem body_executes_at
    (invariant : ∀ rename, CellRenaming.Execution.ProgramInvariant rename verifiedFrontendCore)
    (request : Model.Request) (records : List Int)
    (recordsCapacity : 3 * request.capacity ≤ records.length)
    (sourceCell recordsCell : CellId) (distinct : sourceCell ≠ recordsCell)
    {localCell : Fin 4 → CellId} {before : State}
    (represented : Representation identityLayout localCell
      (ReadOnly.World.pair sourceCell (ScanOne.Model.sourceIntegers request.source) recordsCell records)
      (environment sourceCell recordsCell request.source records request.capacity) before)
    (wellFormed : StateWellFormed before)
    (sourceBelow : sourceCell < frontier) (recordsBelow : recordsCell < frontier)
    (localsFresh : LocalsFresh frontier localCell) (ready : frontier ≤ before.nextCell) :
    ∃ after,
      Executes verifiedFrontendCore before lexIntoBody
        (.returned (some (Model.resultValue request.outcome))) after ∧
      StateWellFormed after ∧
      Representation identityLayout localCell
        (ReadOnly.World.pair sourceCell (ScanOne.Model.sourceIntegers request.source) recordsCell
          (Model.run request.source request.capacity records).records)
        (environment sourceCell recordsCell request.source
          (Model.run request.source request.capacity records).records request.capacity) after ∧
      ModifiesOnly (CellSet.union (CellSet.singleton recordsCell) (freshCells frontier)) before after := by
  have zeroBelow : 0 < frontier := Nat.lt_of_le_of_lt (Nat.zero_le sourceCell) sourceBelow
  have oneBelow : 1 < frontier := by
    by_cases zero : sourceCell = 0
    · have positive : 0 < recordsCell := Nat.pos_of_ne_zero (by
        intro recordsZero
        exact distinct (zero.trans recordsZero.symm))
      exact Nat.lt_of_le_of_lt positive recordsBelow
    · exact Nat.lt_of_le_of_lt (Nat.pos_of_ne_zero zero) sourceBelow
  let rename := CellRenaming.Permutation.placePair 0 1 sourceCell recordsCell
    zeroBelow oneBelow sourceBelow recordsBelow
  have sourcePlaced : rename.forward 0 = sourceCell :=
    CellRenaming.Permutation.placePair_left zeroBelow oneBelow sourceBelow recordsBelow (by decide) distinct
  have recordsPlaced : rename.forward 1 = recordsCell :=
    CellRenaming.Permutation.placePair_right zeroBelow oneBelow sourceBelow recordsBelow
  have localsFixed : (fun index => rename.forward (rename.backward (localCell index))) = localCell := by
    funext index
    exact rename.rightInverse (localCell index)
  have modelRepresentation : Representation identityLayout
      (fun index => rename.forward (rename.backward (localCell index)))
      (CellRenaming.world rename (Execution.world request.source records))
      (fun index => CellRenaming.value rename.forward
        (Execution.initialEnvironment request.source records request.capacity index)) before := by
    simpa only [localsFixed, Execution.world, CellRenaming.world_pair, environment_renamed,
      sourcePlaced, recordsPlaced] using represented
  have modelLocalsFresh : LocalsFresh frontier (fun index => rename.backward (localCell index)) := by
    intro index
    change frontier ≤ rename.backward (localCell index)
    rw [rename.backward_fresh (localsFresh index)]
    exact localsFresh index
  obtain ⟨after, ran, afterWellFormed, afterRepresentation, effect⟩ := body_executes rename
    (invariant rename.forward) request records recordsCapacity ready modelRepresentation wellFormed modelLocalsFresh
  have resultFixed : CellRenaming.completion rename.forward
      (.returned (some (Model.resultValue request.outcome))) =
        .returned (some (Model.resultValue request.outcome)) := by
    cases request.outcome <;> rfl
  rw [resultFixed] at ran
  refine ⟨after, ran, afterWellFormed, ?_, by simpa only [recordsPlaced] using effect⟩
  simpa only [localsFixed, Execution.world, CellRenaming.world_pair, environment_renamed,
    sourcePlaced, recordsPlaced] using afterRepresentation

/-- Derive the full callee resources from caller-owned storage. The internal
    permutation and parameter-cell identities do not escape this boundary. -/
theorem callee_executes
    (invariant : ∀ rename, CellRenaming.Execution.ProgramInvariant rename verifiedFrontendCore)
    (request : Model.Request) (records : List Int) (recordsCapacity : 3 * request.capacity ≤ records.length)
    (sourceCell recordsCell : CellId) (distinct : sourceCell ≠ recordsCell)
    (wellFormed : StateWellFormed caller)
    (owned : (ReadOnly.World.owns (ReadOnly.World.pair sourceCell (ScanOne.Model.sourceIntegers request.source)
      recordsCell records)).holds caller) :
    let bindings := parameterBindings (environment sourceCell recordsCell request.source records request.capacity)
    ∃ completed, Executes verifiedFrontendCore (enterCall caller bindings) lexIntoBody
        (.returned (some (Model.resultValue request.outcome))) completed ∧
      (ReadOnly.World.owns (ReadOnly.World.pair sourceCell (ScanOne.Model.sourceIntegers request.source) recordsCell
        (CanonicalTokens.CanonicalizeModel.encodeTokens (Model.emittedTokens request.outcome) ++
          records.drop (3 * (Model.emittedTokens request.outcome).length)))).holds completed ∧
      CellEffect (CellSet.union (CellSet.singleton recordsCell) (freshCells caller.nextCell))
        (enterCall caller bindings) completed := by
  let env := environment sourceCell recordsCell request.source records request.capacity
  let bindings := parameterBindings env
  have emptyRepresentation : Representation (identityLayout (arity := 0)) (fun index => Fin.elim0 index)
      (ReadOnly.World.pair sourceCell (ScanOne.Model.sourceIntegers request.source) recordsCell records)
      (fun index => Fin.elim0 index) caller := {
    worldOwned := owned
    localOwned := fun index => Fin.elim0 index
    localCellsInjective := fun index => Fin.elim0 index
    worldLocalsDisjoint := by
      intro cell _ member
      obtain ⟨index, _⟩ := member
      exact Fin.elim0 index
  }
  have represented := emptyRepresentation.enterCallParameters (environment := env) wellFormed
  obtain ⟨completed, executed, completedWF, completedRepresentation, effect⟩ :=
    body_executes_at invariant request records recordsCapacity sourceCell recordsCell distinct represented
      (enterCall_preserves_wellFormed wellFormed)
      (StateWellFormed.cell_lt_next_of_entry wellFormed (owned _ _ ReadOnly.World.pair_finds_first))
      (StateWellFormed.cell_lt_next_of_entry wellFormed (owned _ _ (ReadOnly.World.pair_finds_second (Ne.symm distinct))))
      (fun index => Nat.le_add_right _ _) (enterCall_effect caller bindings).nextCell
  have buffers := completedRepresentation.worldOwned
  rw [run_records_prefix request.source request.capacity records recordsCapacity] at buffers
  exact ⟨completed, executed, buffers, CellEffect.ofModifiesOnly effect completedWF⟩

/-- Ordinary caller arguments and storage suffice for the actual lexer call
    at arbitrary buffer addresses, with exact output and an output-only frame. -/
theorem call_evaluates_at
    (invariant : ∀ rename, CellRenaming.Execution.ProgramInvariant rename verifiedFrontendCore)
    (request : Model.Request) (records : List Int) (recordsCapacity : 3 * request.capacity ≤ records.length)
    (sourceCell recordsCell : CellId) (distinct : sourceCell ≠ recordsCell)
    (wellFormed : StateWellFormed afterArguments)
    (owned : (ReadOnly.World.owns (ReadOnly.World.pair sourceCell (ScanOne.Model.sourceIntegers request.source)
      recordsCell records)).holds afterArguments)
    (argumentsResult : ArgumentsEvaluateTo verifiedFrontendCore before arguments
      [.slice Structure.i32Type sourceCell [] 0 request.source.length, .signed .i32 request.source.length,
        .slice Structure.i32Type recordsCell [] 0 records.length, .signed .i32 request.capacity] afterArguments) :
    ∃ after, Evaluates verifiedFrontendCore before (.call lexIntoFunction.id arguments)
        (Model.resultValue request.outcome) after ∧
      (ReadOnly.World.owns (ReadOnly.World.pair sourceCell (ScanOne.Model.sourceIntegers request.source) recordsCell
        (CanonicalTokens.CanonicalizeModel.encodeTokens (Model.emittedTokens request.outcome) ++
          records.drop (3 * (Model.emittedTokens request.outcome).length)))).holds after ∧
      CellEffect (CellSet.singleton recordsCell) afterArguments after := by
  let bindings := parameterBindings (environment sourceCell recordsCell request.source records request.capacity)
  obtain ⟨completed, executed, buffers, effect⟩ :=
    callee_executes invariant request records recordsCapacity sourceCell recordsCell distinct wellFormed owned
  have bound : bindParameters lexIntoFunction.parameters
      [.slice Structure.i32Type sourceCell [] 0 request.source.length, .signed .i32 request.source.length,
        .slice Structure.i32Type recordsCell [] 0 records.length, .signed .i32 request.capacity] = some bindings := by rfl
  have closed := CellEffect.closeCall afterArguments bindings wellFormed effect
  refine ⟨restoreLocals afterArguments completed,
    evaluatesCallReturned argumentsResult verifiedFrontendCore_finds_lexInto bound lexInto_has_body executed,
    buffers, closed.narrow ?_⟩
  intro cell old written
  rcases written with output | fresh
  · exact output
  · exact (Nat.not_le_of_lt old fresh).elim

end Lanius.Extraction.RawLexer.LexInto.Caller
