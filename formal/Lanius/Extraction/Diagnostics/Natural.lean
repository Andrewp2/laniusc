import Lanius.Extraction.Diagnostics.Natural.Digits

namespace Lanius.Extraction.Diagnostics.Natural

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.Extraction.CompactOutput

theorem finish_executes (writer : Host.CheckedExternal program .writeByte 2)
    (initial : Allocation.Registry before) (representable : Host.RepresentableViews before)
    (writtenRead : before.local? 2 = some (.signed .i32 written)) :
    ∃ result after, Executes program before (finish writer.function.id) (.returned (some (.signed .i32 result))) after ∧
      Allocation.Registry after ∧ Host.RepresentableViews after ∧ Host.Effect CellSet.empty before after ∧
      Host.StderrOnly before.world after.world := by
  obtain ⟨after, called, registered, frame, effect, world⟩ := Host.evaluatesStderr writer initial representable 10
    (.cons (show Evaluates program before (number 2) (.signed .i32 2) before from ⟨1, rfl⟩)
      (.cons (show Evaluates program before (number 10) (.signed .i32 10) before from ⟨1, rfl⟩) (.nil _ _)))
  have guard : Evaluates program before (writeGuard writer.function.id (number 10)) (.boolean false) after :=
    evaluatesEagerBinary (by decide) (by decide) called
      (show Evaluates program after (number 1) (.signed .i32 1) after from ⟨1, rfl⟩) rfl
  have kept := effect.preservesLocal initial.wellFormed writtenRead (by simp [CellSet.empty])
  have result : Evaluates program after (binary .add (read 2) (number 1))
      (.signed .i32 (wrapSigned program.target .i32 (written + 1))) after :=
    evaluatesEagerBinary (by decide) (by decide) (local_evaluates program kept)
      (show Evaluates program after (number 1) (.signed .i32 1) after from ⟨1, rfl⟩) rfl
  exact ⟨_, after, executesSequence (executesIfFalse guard (executesSkip _ _))
    (executesSequenceReturned (executesReturnValue result)), registered, frame.representable, effect,
    world.symm ▸ Host.StderrOnly.byte before.world 10⟩

/-- Execute the real two-loop helper and hide only its freshly allocated
local cells. Every pre-existing buffer and caller cell survives the writes. -/
theorem nonnegative (writer : Host.CheckedExternal program .writeByte 2) (value : Nat)
    (bounded : value ≤ 2147483647) (initial : Allocation.Registry before)
    (representable : Host.RepresentableViews before)
    (valueRead : before.local? 0 = some (.signed .i32 value)) :
    ∃ result after, Executes program before (body writer.function.id) (.returned (some (.signed .i32 result))) after ∧
      Allocation.Registry after ∧ Host.RepresentableViews after ∧ Host.Effect CellSet.empty before after ∧
      Host.StderrOnly before.world after.world := by
  have guard : Evaluates program before (binary .lessEqual (read 0) negativeOne) (.boolean false) before := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program valueRead) (negativeOne_evaluates program before)
    simp [evalBinaryValue, evalSignedBinary]
    exact Int.lt_of_lt_of_le (by decide : (-1 : Int) < 0) (Int.natCast_nonneg value)
  obtain ⟨valueCell, valueOwned⟩ := Assertion.exists_localPointsTo_of_local before 0 (.signed .i32 value) valueRead
  have valueOld := StateWellFormed.cell_lt_next_of_entry initial.wellFormed valueOwned.2
  let divided := before.bindLocal 1 (.signed .i32 1)
  have dividedRegistry := initial.bindLocal 1 (.signed .i32 1)
  have divisorOwned := bindLocal_owns_fresh before 1 (.signed .i32 1) initial.wellFormed
  have inputDivided := bindLocal_preserves_localPointsTo_of_ne before 1 0 (.signed .i32 1) valueCell _
    initial.wellFormed (by decide) valueOwned
  obtain ⟨divisor, grown, grownRun, positive, divisorBound, _quotient, inputGrown, divisorGrown, growEffect, growHeap⟩ :=
    grow program value 1 bounded (by decide) (by decide) dividedRegistry.wellFormed inputDivided divisorOwned (Nat.ne_of_lt valueOld)
  have growMemory := Host.MemoryFrame.scalar growEffect growHeap divisorOwned.2
  have grownRegistry := growMemory.registry dividedRegistry
  have grownRepresentable := growMemory.representable dividedRegistry (representable.bindLocal initial 1 (.signed .i32 1))
  let counted := grown.bindLocal 2 (.signed .i32 0)
  have countedRegistry := grownRegistry.bindLocal 2 (.signed .i32 0)
  have inputCounted := bindLocal_preserves_localPointsTo_of_ne grown 2 0 (.signed .i32 0) valueCell _
    grownRegistry.wellFormed (by decide) inputGrown
  have divisorCounted := bindLocal_preserves_localPointsTo_of_ne grown 2 1 (.signed .i32 0) before.nextCell _
    grownRegistry.wellFormed (by decide) divisorGrown
  have writtenCounted := bindLocal_owns_fresh grown 2 (.signed .i32 0) grownRegistry.wellFormed
  obtain ⟨written, ready, digitRun, _inputReady, _divisorReady, writtenReady, readyRegistry, readyRepresentable, digitEffect, digitWorld⟩ :=
    digits writer value divisor 0 bounded divisorBound countedRegistry
      (grownRepresentable.bindLocal grownRegistry 2 (.signed .i32 0)) inputCounted divisorCounted writtenCounted
      (Nat.ne_of_lt valueOld)
      (Nat.ne_of_lt (StateWellFormed.cell_lt_next_of_entry grownRegistry.wellFormed inputGrown.2))
      (Nat.ne_of_lt (StateWellFormed.cell_lt_next_of_entry grownRegistry.wellFormed divisorGrown.2))
  obtain ⟨result, completed, finished, finalRegistry, finalRepresentable, finishEffect, finishWorld⟩ :=
    finish_executes writer readyRegistry readyRepresentable (Assertion.localPointsTo_local _ _ _ _ writtenReady)
  have digitFinish := digitEffect.trans (finishEffect.weaken (by intro _ impossible; exact False.elim impossible))
  have closedWritten := Host.Effect.closeLocal grown 2 (.signed .i32 0) grownRegistry.wellFormed digitFinish
  have writtenEffect : Host.Effect (CellSet.singleton before.nextCell) grown (restoreLocals grown completed) :=
    closedWritten.narrow (by
      intro cell old changed
      rcases changed with divisorCell | writtenCell
      · exact divisorCell
      · change cell = grown.nextCell at writtenCell
        exact False.elim ((Nat.ne_of_lt old) writtenCell))
  have fullEffect := (Host.Effect.ofCells growEffect growHeap).trans writtenEffect
  have closedDivisor := Host.Effect.closeLocal before 1 (.signed .i32 1) initial.wellFormed fullEffect
  have effect : Host.Effect CellSet.empty before (restoreLocals before (restoreLocals grown completed)) :=
    closedDivisor.narrow (by
      intro cell old changed
      change cell = before.nextCell at changed
      exact False.elim ((Nat.ne_of_lt old) changed))
  have world : Host.StderrOnly before.world completed.world := by
    have combined := digitWorld.trans finishWorld
    change Host.StderrOnly grown.world completed.world at combined
    rw [growEffect.world] at combined
    exact combined
  exact ⟨result, restoreLocals before (restoreLocals grown completed),
    executesSequence (executesIfFalse guard (executesSkip _ _))
      (executesLetLocal (show Evaluates program before (number 1) (.signed .i32 1) before from ⟨1, rfl⟩)
        (executesSequence grownRun
          (executesLetLocal (show Evaluates program grown (number 0) (.signed .i32 0) grown from ⟨1, rfl⟩)
            (executesSequence digitRun finished)))),
    (finalRegistry.restoreLocals grown closedWritten.wellFormed).restoreLocals before effect.wellFormed,
    finalRepresentable, effect, world⟩

/-- Negative diagnostics return immediately; nonnegative diagnostics execute
both finite loops. No execution result or internal invariant is a premise. -/
theorem executes (writer : Host.CheckedExternal program .writeByte 2) (value : Int)
    (bounded : value ≤ 2147483647) (initial : Allocation.Registry before)
    (representable : Host.RepresentableViews before)
    (valueRead : before.local? 0 = some (.signed .i32 value)) :
    ∃ result after, Executes program before (body writer.function.id) (.returned (some (.signed .i32 result))) after ∧
      Allocation.Registry after ∧ Host.RepresentableViews after ∧ Host.Effect CellSet.empty before after ∧
      Host.StderrOnly before.world after.world := by
  by_cases negative : value < 0
  · have guard : Evaluates program before (binary .lessEqual (read 0) negativeOne) (.boolean true) before := by
      apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program valueRead) (negativeOne_evaluates program before)
      simp only [evalBinaryValue, evalSignedBinary, BEq.rfl, if_true, Except.ok.injEq, Value.boolean.injEq,
        decide_eq_true_eq]
      omega
    exact ⟨-1, before, executesSequenceReturned (executesIfTrue guard
      (executesSequenceReturned (executesReturnValue (negativeOne_evaluates program before)))), initial, representable,
      Host.Effect.refl initial.wellFormed, Host.StderrOnly.refl before.world⟩
  · have equal : (value.toNat : Int) = value := Int.toNat_of_nonneg (by omega)
    exact nonnegative writer value.toNat (by omega) initial representable (equal.symm ▸ valueRead)

theorem Checked.write (checked : Checked program) (value : Int) (bounded : value ≤ 2147483647)
    (initial : Allocation.Registry before) (representable : Host.RepresentableViews before)
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments [.signed .i32 value] before) :
    ∃ result after, Evaluates program.core caller (.call checked.source.source.function.id arguments) (.signed .i32 result) after ∧
      Allocation.Registry after ∧ Host.RepresentableViews after ∧ Host.Effect CellSet.empty before after ∧
      Host.StderrOnly before.world after.world := by
  let bindings : List (VarId × Value) := [(0, .signed .i32 value)]
  have localRead : (enterCall before bindings).local? 0 = some (.signed .i32 value) :=
    enterCall_local_of_binding before [] [] 0 (.signed .i32 value) initial.wellFormed (by simp)
  obtain ⟨result, completed, run, registered, values, effect, world⟩ := executes checked.writer value bounded
    (initial.enterCall bindings) (representable.enterCall initial bindings) localRead
  have identity : checked.source.source.function.id = checked.source.source.source.id := by
    simpa [Program.function?] using List.find?_some checked.source.source.found
  have found : program.core.function? checked.source.source.function.id = some checked.source.source.function := by
    rw [identity]
    exact checked.source.source.found
  have called := evaluatesCallReturned argumentsResult found
    (show bindParameters checked.source.source.function.parameters [.signed .i32 value] = some bindings from by
      rw [checked.source.signature.1]; rfl) checked.source.bodyExact run
  have closed := effect.closeCall before bindings initial.wellFormed
  exact ⟨result, restoreLocals before completed, called, registered.restoreLocals before closed.wellFormed,
    values, closed, world⟩

end Lanius.Extraction.Diagnostics.Natural
