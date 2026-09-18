import Lanius.X86.Select.Execution
import Lanius.X86.Source.Lower
import Lanius.FunctionalView.Stateful.Frame
import Lanius.FunctionalViewCoreCallFrame
import Lanius.Separation.HeapFrame

namespace Lanius.X86.Select.Frame

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView Lanius.FunctionalView.Core Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.FreshSimulation

/-- No helper calls occur in the selector. Successful calls in this model are
impossible, so its simulation obligation introduces no assumed callee. -/
private def noCalls : Effectful.CallModel := ⟨fun _ _ _ => .error .typeMismatch⟩

private theorem noCalls_sound (program : Program) : FramePreservingCallSoundness program noCalls where
  call := by
    intro arity layout localCell beforeWorld afterWorld environment before afterArguments function arguments values value
      argumentWrites wellFormed represented argumentsRun argumentsEffect evaluated
    cases evaluated

private theorem noCalls_world : WorldPreserving noCalls := by
  intro beforeWorld afterWorld function values value evaluated
  cases evaluated

theorem body_executes (program : Program) (input : Input)
    (represented : Representation identityLayout localCell (ReadOnly.World.singleton cell input.words)
      (Environment.initial input cell) before)
    (wellFormed : StateWellFormed before)
    (localsFresh : LocalsFresh frontier localCell) (nextFresh : frontier ≤ before.nextCell) :
    ∃ after, Executes program before Syntax.body (.returned (some (.signed .i32 input.position.val))) after ∧
      StateWellFormed after ∧
      Representation identityLayout localCell (ReadOnly.World.singleton cell input.words)
        (Environment.initial input cell) after ∧
      ModifiesOnly (freshCells frontier) before after := by
  obtain ⟨after, run, afterWF, afterRepresented, effect⟩ :=
    StatefulFrame.command_executes ((noCalls_sound program).toCallSoundness noCalls_world)
      (operationSoundness program noCalls (noCalls_sound program))
      (Execution.command (program := program) (calls := noCalls) (input := input) (cell := cell)
        ReadOnly.World.singleton_finds)
      represented (LayoutBelow.identity (arity := 2)) wellFormed localsFresh nextFresh
  refine ⟨after, run, afterWF, afterRepresented, { effect with oldCells := ?_ }⟩
  intro candidate old untouched
  by_cases named : ∃ values, (ReadOnly.World.singleton cell input.words).i32Slice? candidate = some values
  · obtain ⟨values, found⟩ := named
    exact (afterRepresented.worldOwned candidate values found).trans (represented.worldOwned candidate values found).symm
  · apply effect.oldCells candidate old
    intro written
    rcases written with resource | fresh
    · exact named resource
    · exact untouched fresh

/-- The actual source selector returns the parameter position from the
transport, while preserving every caller cell, byte-heap entry, and raw view.
The caller supplies input storage and normal argument evaluation only. -/
theorem call (checked : Source.Lower.CheckedSelector program) (input : Input)
    (wellFormed : StateWellFormed before)
    (backing : before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values input.words)) })
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      [.slice Syntax.i32 cell [] 0 input.words.length, .signed .i32 input.words.length] before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments)
        (.signed .i32 input.position.val) after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  let environment := Environment.initial input cell
  let bindings := parameterBindings environment
  have owned : (ReadOnly.World.owns (ReadOnly.World.singleton cell input.words)).holds before := by
    intro candidate values found
    by_cases same : candidate = cell
    · subst candidate
      simp only [ReadOnly.World.singleton_finds, Option.some.injEq] at found
      subst values
      exact backing
    · simp [ReadOnly.World.singleton, same] at found
  have emptyRepresentation : Representation (identityLayout (arity := 0)) (fun index => Fin.elim0 index)
      (ReadOnly.World.singleton cell input.words) (fun index => Fin.elim0 index) before := {
    worldOwned := owned
    localOwned := fun index => Fin.elim0 index
    localCellsInjective := fun index => Fin.elim0 index
    worldLocalsDisjoint := by
      intro candidate worldMember localMember
      obtain ⟨index, _⟩ := localMember
      exact Fin.elim0 index
  }
  have represented := emptyRepresentation.enterCallParameters (environment := environment) wellFormed
  obtain ⟨completed, run, completedWF, completedRepresentation, bodyEffect⟩ :=
    body_executes program.core input represented (enterCall_preserves_wellFormed wellFormed)
      (frontier := before.nextCell) (fun index => Nat.le_add_right _ _)
      (enterCall_effect before bindings).nextCell
  let internal : Lanius.Extraction.Source.CheckedInternal program ["backend", "parameter"] "select"
      [(0, .slice Syntax.i32), (1, Syntax.i32)] Syntax.i32 Syntax.body := {
    source := checked.source
    signature := checked.signature
    bodyExact := checked.bodyPresent.trans (congrArg some checked.bodyExact)
  }
  have closed := internal.call wellFormed argumentsResult (bindings := bindings) rfl run
    (CellEffect.ofModifiesOnly bodyEffect completedWF)
  refine ⟨restoreLocals before completed, closed.1, closed.2.narrow ?_,
    HeapFrame.closeCall before bindings (HeapFrame.ofStoreEffect bodyEffect.toStoreEffect)⟩
  intro candidate old fresh
  exact (Nat.not_le_of_lt old fresh).elim

end Lanius.X86.Select.Frame
