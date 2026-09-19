import Lanius.Extraction.Diagnostics.Natural.Grow
import Lanius.Extraction.Host.MemoryFrame

namespace Lanius.Extraction.Diagnostics.Natural

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.CompactOutput

theorem digit_evaluates (program : Program) (value divisor : Nat)
    (bounded : value ≤ 2147483647) (positive : 0 < divisor)
    (input : before.local? 0 = some (.signed .i32 value))
    (divisorRead : before.local? 1 = some (.signed .i32 divisor)) :
    Evaluates program before digit (.signed .i32 (48 + (value / divisor) % 10 : Nat)) before := by
  have remainderBound := Nat.mod_lt (value / divisor) (by decide : 0 < 10)
  exact evaluatesNatI32Add evaluatesValue
    (evaluatesNatI32Remainder
      (evaluatesNatI32Divide (local_evaluates program input) (local_evaluates program divisorRead)
        positive (Nat.le_trans (Nat.div_le_self _ _) bounded)) evaluatesValue (by decide) (by omega)) (by omega)

/-- Each digit writes one byte and divides a positive divisor by ten. The
counter is modeled with its actual i32 wrapping semantics; its numeric value
is irrelevant to failure safety because the caller discards this return. -/
theorem digits (writer : Host.CheckedExternal program .writeByte 2) (value divisor : Nat) (written : Int)
    (bounded : value ≤ 2147483647) (divisorBound : divisor ≤ 2147483647)
    (initial : Allocation.Registry before) (representable : Host.RepresentableViews before)
    (input : (Assertion.localPointsTo 0 valueCell (some (.signed .i32 value))).holds before)
    (divisorOwned : (Assertion.localPointsTo 1 divisorCell (some (.signed .i32 divisor))).holds before)
    (writtenOwned : (Assertion.localPointsTo 2 writtenCell (some (.signed .i32 written))).holds before)
    (valueDivisor : valueCell ≠ divisorCell) (valueWritten : valueCell ≠ writtenCell)
    (divisorWritten : divisorCell ≠ writtenCell) :
    ∃ finalWritten after, Executes program before (digitLoop writer.function.id) .next after ∧
      (Assertion.localPointsTo 0 valueCell (some (.signed .i32 value))).holds after ∧
      (Assertion.localPointsTo 1 divisorCell (some (.signed .i32 0))).holds after ∧
      (Assertion.localPointsTo 2 writtenCell (some (.signed .i32 finalWritten))).holds after ∧
      Allocation.Registry after ∧ Host.RepresentableViews after ∧
      Host.Effect (CellSet.union (CellSet.singleton divisorCell) (CellSet.singleton writtenCell)) before after ∧
      Host.StderrOnly before.world after.world := by
  induction divisor using Nat.strongRecOn generalizing written before with
  | ind divisor ih =>
    have condition : Evaluates program before (binary .notEqual (read 1) (number 0))
        (.boolean (decide (divisor ≠ 0))) before := by
      apply evaluatesEagerBinary (by decide) (by decide)
        (local_evaluates program (Assertion.localPointsTo_local _ _ _ _ divisorOwned))
        (show Evaluates program before (number 0) (.signed .i32 0) before from evaluatesValue)
      by_cases zero : divisor = 0
      · simp [evalBinaryValue, scalarEqual, zero]
      · have nonzero : (divisor : Int) ≠ 0 := by omega
        simp [evalBinaryValue, scalarEqual, zero, beq_eq_false_iff_ne.mpr nonzero]
    by_cases zero : divisor = 0
    · subst divisor
      exact ⟨written, before, executesWhileFalse (by simpa using condition), input, divisorOwned, writtenOwned,
        initial, representable, Host.Effect.refl initial.wellFormed, Host.StderrOnly.refl before.world⟩
    · have positive : 0 < divisor := by omega
      obtain ⟨called, wrote, registered, hostFrame, hostEffect, world⟩ := Host.evaluatesStderr writer initial representable
        (48 + (value / divisor) % 10 : Nat)
        (.cons (show Evaluates program before (number 2) (.signed .i32 2) before from evaluatesValue)
          (.cons (digit_evaluates program value divisor bounded positive
            (Assertion.localPointsTo_local _ _ _ _ input) (Assertion.localPointsTo_local _ _ _ _ divisorOwned)) (.nil _ _)))
      have guard : Evaluates program before (writeGuard writer.function.id digit) (.boolean false) called :=
        evaluatesEagerBinary (by decide) (by decide) wrote
          (show Evaluates program called (number 1) (.signed .i32 1) called from evaluatesValue) rfl
      have inputCalled := hostEffect.preservesLocalPointsTo initial.wellFormed input (by simp [CellSet.empty])
      have divisorCalled := hostEffect.preservesLocalPointsTo initial.wellFormed divisorOwned (by simp [CellSet.empty])
      have writtenCalled := hostEffect.preservesLocalPointsTo initial.wellFormed writtenOwned (by simp [CellSet.empty])
      let nextWritten := wrapSigned program.target .i32 (written + 1)
      obtain ⟨counted, increment, writtenCounted, countEffect, countHeap⟩ := evaluatesOwnedLocalUpdate registered.wellFormed writtenCalled
        (show Evaluates program called (number 1) (.signed .i32 1) called from evaluatesValue)
        (op := .add) (replacement := .signed .i32 nextWritten) (by
          simp only [evalAssignValue, assignOpBinary?, evalBinaryValue, BEq.rfl, if_true, evalSignedBinary, nextWritten])
      have countMemory := Host.MemoryFrame.scalar countEffect countHeap writtenCalled.2
      have countedRegistry := countMemory.registry registered
      have countedRepresentable := countMemory.representable registered hostFrame.representable
      have inputCounted := countEffect.preserves_localPointsTo registered.wellFormed inputCalled valueWritten
      have divisorCounted := countEffect.preserves_localPointsTo registered.wellFormed divisorCalled divisorWritten
      have quotient : truncDiv (divisor : Int) 10 = (divisor / 10 : Nat) := by simp [truncDiv]
      obtain ⟨lowered, divide, divisorLowered, divideEffect, divideHeap⟩ := evaluatesOwnedLocalUpdate countedRegistry.wellFormed divisorCounted
        (show Evaluates program counted (number 10) (.signed .i32 10) counted from evaluatesValue)
        (op := .divide) (replacement := .signed .i32 (divisor / 10 : Nat)) (by
          simp only [evalAssignValue, assignOpBinary?, evalBinaryValue, BEq.rfl, if_true, evalSignedBinary]
          simp only [show ((10 : Int) == 0) = false from rfl, show ((10 : Int) == -1) = false from rfl,
            Bool.and_false, Bool.false_eq_true, if_false, quotient]
          have wrapped := wrapSigned_i32_ofNat program.target _ (Nat.le_trans (Nat.div_le_self divisor 10) divisorBound)
          simp only [Int.ofNat_eq_natCast] at wrapped
          rw [wrapped])
      have divideMemory := Host.MemoryFrame.scalar divideEffect divideHeap divisorCounted.2
      have loweredRegistry := divideMemory.registry countedRegistry
      have loweredRepresentable := divideMemory.representable countedRegistry countedRepresentable
      have inputLowered := divideEffect.preserves_localPointsTo countedRegistry.wellFormed inputCounted valueDivisor
      have writtenLowered := divideEffect.preserves_localPointsTo countedRegistry.wellFormed writtenCounted divisorWritten.symm
      obtain ⟨finalWritten, after, rest, inputAfter, divisorAfter, writtenAfter, finalRegistry, finalRepresentable, remaining, remainingWorld⟩ :=
        ih (divisor / 10) (Nat.div_lt_self positive (by decide)) nextWritten
          (Nat.le_trans (Nat.div_le_self _ _) divisorBound) loweredRegistry loweredRepresentable
          inputLowered divisorLowered writtenLowered
      have stepped : Executes program before (digitStep writer.function.id) .next lowered :=
        executesSequence (executesIfFalse guard (executesSkip _ _))
          (executesSequence (executesExpression increment) (executesSequence (executesExpression divide) (executesSkip _ _)))
      have effects := (hostEffect.weaken (by intro _ impossible; exact False.elim impossible)).trans
        ((Host.Effect.ofCells countEffect countHeap).weaken CellSet.subset_union_right |>.trans
          ((Host.Effect.ofCells divideEffect divideHeap).weaken CellSet.subset_union_left))
      have throughByte : Host.StderrOnly before.world lowered.world := by
        rw [divideEffect.world, countEffect.world, world]
        exact Host.StderrOnly.byte _ _
      exact ⟨finalWritten, after, executesWhileTrueThen (by simpa [zero] using condition) stepped rest,
        inputAfter, divisorAfter, writtenAfter, finalRegistry, finalRepresentable, effects.trans remaining,
        throughByte.trans remainingWorld⟩

end Lanius.Extraction.Diagnostics.Natural
