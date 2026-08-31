import Lanius.Extraction.Decimal.EvaluationTerms
import Lanius.Extraction.Decimal.EvaluationBounds

namespace Lanius.Extraction.Decimal.ScanExponentEvaluation

open Lanius
open Lanius.Core
open Lanius.Compiler.Lexer
open Lanius.Compiler.Lexer.Program
open Lanius.Extraction
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Core.Effectful
open Lanius.FunctionalView.Stateful
open Lanius.Extraction.Decimal
open Lanius.Extraction.Decimal.EvaluationModel
open Lanius.Extraction.Decimal.EvaluationTerms
open Lanius.Extraction.Decimal.EvaluationBounds

private theorem updateDigitsStart
    (source : List Byte) (digitsStart : Nat)
    (bound : digitsStart + 1 ≤ 2147483647) :
    (commandMachine source).evalLocalUpdate .add
        (.signed .i32 digitsStart) (.signed .i32 1) =
      .ok (.signed .i32 (digitsStart + 1)) := by
  simp only [commandMachine, Stateful.machineWith]
  change Lanius.Semantics.evalAssignValue verifiedFrontendCore.target .add
    (some (.signed .i32 digitsStart)) (.signed .i32 1) = _
  simp only [Lanius.Semantics.evalAssignValue,
    Lanius.Semantics.assignOpBinary?, Lanius.Semantics.evalBinaryValue,
    beq_self_eq_true, if_true, Lanius.Semantics.evalSignedBinary]
  have addition : (digitsStart : Int) + 1 =
      (digitsStart + 1 : Nat) := by omega
  rw [addition]
  have wrapped := Lanius.Semantics.wrapSigned_i32_ofNat
    verifiedFrontendCore.target (digitsStart + 1) bound
  congr 3

private theorem popUpdatedDigitsStart
    (source : List Byte) (start digitsStart : Nat) (byte : Byte) :
    Env.pop (Stateful.Env.set
      (((environment source start).push (.signed .i32 digitsStart)).push
        (.signed .i32 byte.val)) 3
      (.signed .i32 (digitsStart + 1))) =
      (environment source start).push (.signed .i32 (digitsStart + 1)) := by
  rw [show (3 : Fin 5) = ⟨(3 : Fin 4).val,
      Nat.lt_succ_of_lt (3 : Fin 4).isLt⟩ by rfl]
  rw [Env.pop_set]
  simp only [Env.pop_push]
  exact setLast_push (environment source start)
    (.signed .i32 digitsStart) (.signed .i32 (digitsStart + 1))

theorem scanExponent_run
    (source : List Byte) (world : ReadOnly.World) (start : Nat)
    (sourceFound : world.i32Slice? 0 = some (sourceIntegers source))
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    Stateful.Acyclic.run? (termMachine source) (commandMachine source)
        world (environment source start) Commands.scanExponentReadable =
      some (.returned (some (encoded (scanExponent source start))), world,
        environment source start) := by
  let digitsStart := start + 1
  have digitsStartBound : digitsStart ≤ 2147483647 := by
    dsimp [digitsStart]
    omega
  have initialized := add_evaluates (source := source) (world := world)
    (environment source start) (Commands.slot 2) (Commands.i32 1)
    start 1 digitsStartBound (by rfl) (by rfl)
  change Term.evaluate (termMachine source) world (environment source start)
      (Commands.add (Commands.slot 2) (Commands.i32 1)) =
    .ok (.signed .i32 digitsStart, world) at initialized
  simp only [Commands.scanExponentReadable, Stateful.Acyclic.run?]
  rw [initialized]
  simp only [bind, Except.bind]
  have inBoundsResult := less_evaluates (source := source) (world := world)
    ((environment source start).push (.signed .i32 digitsStart))
    (Commands.slot 3) (Commands.slot 1) digitsStart source.length
    (by rfl) (by rfl)
  rw [inBoundsResult]
  by_cases digitsInBounds : digitsStart < source.length
  · rw [decide_eq_true digitsInBounds]
    simp only [bind, Except.bind]
    let byte := source.get ⟨digitsStart, digitsInBounds⟩
    have byteResult := index_evaluates (source := source) world
      ((environment source start).push (.signed .i32 digitsStart))
      (Commands.slot 0) (Commands.slot 3) digitsStart digitsInBounds
      sourceFound (by rfl) (by rfl)
    change Term.evaluate (termMachine source) world
        ((environment source start).push (.signed .i32 digitsStart))
        (Commands.index (Commands.slot 0) (Commands.slot 3)) =
      .ok (.signed .i32 byte.val, world) at byteResult
    rw [byteResult]
    simp only [bind, Except.bind]
    have plusResult := equal_evaluates (source := source) (world := world)
      (((environment source start).push (.signed .i32 digitsStart)).push
        (.signed .i32 byte.val))
      (Commands.slot 4) (Commands.i32 43) byte.val 43 (by rfl) (by rfl)
    have minusResult := equal_evaluates (source := source) (world := world)
      (((environment source start).push (.signed .i32 digitsStart)).push
        (.signed .i32 byte.val))
      (Commands.slot 4) (Commands.i32 45) byte.val 45 (by rfl) (by rfl)
    have signResult := logicalOr_evaluates (source := source) (world := world)
      (((environment source start).push (.signed .i32 digitsStart)).push
        (.signed .i32 byte.val))
      (Commands.comparison .equal (Commands.slot 4) (Commands.i32 43))
      (Commands.comparison .equal (Commands.slot 4) (Commands.i32 45))
      (decide (byte.val = 43)) (decide (byte.val = 45)) plusResult minusResult
    rw [signResult]
    let hasSign := decide (byte.val = 43) || decide (byte.val = 45)
    by_cases sign : hasSign = true
    · dsimp [hasSign] at sign
      rw [sign]
      simp only [bind, Except.bind]
      have nextBound : digitsStart + 1 ≤ 2147483647 := by omega
      have updated := updateDigitsStart source digitsStart nextBound
      rw [show Term.evaluate (termMachine source) world
        (((environment source start).push (.signed .i32 digitsStart)).push
          (.signed .i32 byte.val)) (Commands.i32 1) =
        .ok (.signed .i32 1, world) by rfl]
      simp only [bind, Except.bind]
      rw [show (((environment source start).push
        (.signed .i32 digitsStart)).push (.signed .i32 byte.val)) 3 =
        .signed .i32 digitsStart by rfl]
      rw [updated]
      simp only [Stateful.Acyclic.run?, popUpdatedDigitsStart]
      let scanStart := digitsStart + 1
      have scanStartBound : scanStart ≤ 2147483647 := nextBound
      have digitResult := digitRun_evaluates (source := source) (world := world)
        ((environment source start).push (.signed .i32 scanStart))
        (Commands.slot 0) (Commands.slot 1) (Commands.slot 3)
        (Commands.i32 10) scanStart 10 sourceFound sourceBound scanStartBound
        (by omega) (by rfl) (by rfl) (by rfl) (by rfl)
      dsimp [scanStart] at digitResult
      rw [digitResult]
      simp only [bind, Except.bind]
      have logicalStart : exponentDigitsStart source start = scanStart := by
        rcases Bool.or_eq_true_iff.mp sign with plus | minus
        · have plusEq : byte.val = 43 := of_decide_eq_true plus
          simp [exponentDigitsStart, byteValueAt, digitsStart, scanStart,
            digitsInBounds, byte, plusEq]
          intro impossible
          exact (impossible (by simpa [byte, digitsStart] using plusEq)).elim
        · have minusEq : byte.val = 45 := of_decide_eq_true minus
          simp [exponentDigitsStart, byteValueAt, digitsStart, scanStart,
            digitsInBounds, byte, minusEq]
          intro _
          simpa [byte, digitsStart] using minusEq
      simp only [scanExponent]
      rw [logicalStart]
      cases resultEq : scanDigitRun source scanStart 10 with
      | success finish =>
          have resultBound := digitRunResult_bound (source := source)
            (start := scanStart) (base := 10) sourceBound scanStartBound
          rw [resultEq] at resultBound digitResult
          have succeeded : Term.evaluate (termMachine source) world
              (((environment source start).push (.signed .i32 scanStart)).push
                (digitScanValue (.success finish)))
              (Commands.digitSucceeded (Commands.slot 4)) =
              .ok (.boolean true, world) := digitSucceeded_evaluates (source := source)
            (world := world)
            (((environment source start).push (.signed .i32 scanStart)).push
              (digitScanValue (.success finish)))
            (Commands.slot 4) (.success finish) resultBound (by rfl)
          have notSucceeded := logicalNot_evaluates (source := source)
            (((environment source start).push (.signed .i32 scanStart)).push
              (digitScanValue (.success finish)))
            (Commands.digitSucceeded (Commands.slot 4)) true succeeded
          dsimp [scanStart] at notSucceeded
          rw [notSucceeded]
          simp only [Commands.returned, Stateful.Acyclic.run?, Bool.not_true,
            bind, Except.bind]
          have endResult := digitEnd_evaluates (source := source)
            (world := world)
            (((environment source start).push (.signed .i32 scanStart)).push
              (digitScanValue (.success finish)))
            (Commands.slot 4) finish resultBound (by rfl)
          have returned := floatScan_evaluates (source := source)
            (world := world)
            (((environment source start).push (.signed .i32 scanStart)).push
              (digitScanValue (.success finish)))
            (Commands.digitEnd (Commands.slot 4)) finish resultBound endResult
          dsimp [scanStart] at returned
          rw [returned]
          simp [encoded, scanExponent, resultEq]
          rfl
      | failure error =>
          have resultBound := digitRunResult_bound (source := source)
            (start := scanStart) (base := 10) sourceBound scanStartBound
          rw [resultEq] at resultBound digitResult
          have succeeded : Term.evaluate (termMachine source) world
              (((environment source start).push (.signed .i32 scanStart)).push
                (digitScanValue (.failure error)))
              (Commands.digitSucceeded (Commands.slot 4)) =
              .ok (.boolean false, world) := digitSucceeded_evaluates (source := source)
            (world := world)
            (((environment source start).push (.signed .i32 scanStart)).push
              (digitScanValue (.failure error)))
            (Commands.slot 4) (.failure error) resultBound (by rfl)
          have notSucceeded := logicalNot_evaluates (source := source)
            (((environment source start).push (.signed .i32 scanStart)).push
              (digitScanValue (.failure error)))
            (Commands.digitSucceeded (Commands.slot 4)) false succeeded
          dsimp [scanStart] at notSucceeded
          rw [notSucceeded]
          simp only [Commands.returned, Stateful.Acyclic.run?, Bool.not_false,
            bind, Except.bind]
          have errorResult := digitError_evaluates (source := source)
            (world := world)
            (((environment source start).push (.signed .i32 scanStart)).push
              (digitScanValue (.failure error)))
            (Commands.slot 4) error resultBound (by rfl)
          have returned := numberFailure_evaluates (source := source)
            (world := world)
            (((environment source start).push (.signed .i32 scanStart)).push
              (digitScanValue (.failure error)))
            (Commands.digitError (Commands.slot 4)) error resultBound errorResult
          dsimp [scanStart] at returned
          rw [returned]
          simp [encoded, scanExponent, resultEq]
          rfl
    · have signFalse : hasSign = false := Bool.eq_false_iff.mpr sign
      dsimp [hasSign] at signFalse
      rw [signFalse]
      simp only [Stateful.Acyclic.run?, Env.pop_push, bind, Except.bind]
      let scanStart := digitsStart
      have digitResult := digitRun_evaluates (source := source) (world := world)
        ((environment source start).push (.signed .i32 scanStart))
        (Commands.slot 0) (Commands.slot 1) (Commands.slot 3)
        (Commands.i32 10) scanStart 10 sourceFound sourceBound digitsStartBound
        (by omega) (by rfl) (by rfl) (by rfl) (by rfl)
      rw [digitResult]
      simp only [bind, Except.bind]
      have logicalStart : exponentDigitsStart source start = scanStart := by
        have components := Bool.or_eq_false_iff.mp signFalse
        have notPlus : byte.val ≠ 43 := of_decide_eq_false components.1
        have notMinus : byte.val ≠ 45 := of_decide_eq_false components.2
        simp [exponentDigitsStart, byteValueAt, digitsStart, scanStart,
          digitsInBounds, byte, notPlus, notMinus]
        constructor
        · simpa [byte, digitsStart] using notPlus
        · simpa [byte, digitsStart] using notMinus
      simp only [scanExponent]
      rw [logicalStart]
      cases resultEq : scanDigitRun source scanStart 10 with
      | success finish =>
          have resultBound := digitRunResult_bound (source := source)
            (start := scanStart) (base := 10) sourceBound digitsStartBound
          rw [resultEq] at resultBound digitResult
          have succeeded : Term.evaluate (termMachine source) world
              (((environment source start).push (.signed .i32 scanStart)).push
                (digitScanValue (.success finish)))
              (Commands.digitSucceeded (Commands.slot 4)) =
              .ok (.boolean true, world) := digitSucceeded_evaluates (source := source)
            (world := world)
            (((environment source start).push (.signed .i32 scanStart)).push
              (digitScanValue (.success finish)))
            (Commands.slot 4) (.success finish) resultBound (by rfl)
          have notSucceeded := logicalNot_evaluates (source := source)
            (((environment source start).push (.signed .i32 scanStart)).push
              (digitScanValue (.success finish)))
            (Commands.digitSucceeded (Commands.slot 4)) true succeeded
          dsimp [scanStart] at notSucceeded
          rw [notSucceeded]
          simp only [Commands.returned, Stateful.Acyclic.run?, Bool.not_true,
            bind, Except.bind]
          have endResult := digitEnd_evaluates (source := source)
            (world := world)
            (((environment source start).push (.signed .i32 scanStart)).push
              (digitScanValue (.success finish)))
            (Commands.slot 4) finish resultBound (by rfl)
          have returned := floatScan_evaluates (source := source)
            (world := world)
            (((environment source start).push (.signed .i32 scanStart)).push
              (digitScanValue (.success finish)))
            (Commands.digitEnd (Commands.slot 4)) finish resultBound endResult
          dsimp [scanStart] at returned
          rw [returned]
          simp [encoded, scanExponent, resultEq]
          rfl
      | failure error =>
          have resultBound := digitRunResult_bound (source := source)
            (start := scanStart) (base := 10) sourceBound digitsStartBound
          rw [resultEq] at resultBound digitResult
          have succeeded : Term.evaluate (termMachine source) world
              (((environment source start).push (.signed .i32 scanStart)).push
                (digitScanValue (.failure error)))
              (Commands.digitSucceeded (Commands.slot 4)) =
              .ok (.boolean false, world) := digitSucceeded_evaluates (source := source)
            (world := world)
            (((environment source start).push (.signed .i32 scanStart)).push
              (digitScanValue (.failure error)))
            (Commands.slot 4) (.failure error) resultBound (by rfl)
          have notSucceeded := logicalNot_evaluates (source := source)
            (((environment source start).push (.signed .i32 scanStart)).push
              (digitScanValue (.failure error)))
            (Commands.digitSucceeded (Commands.slot 4)) false succeeded
          dsimp [scanStart] at notSucceeded
          rw [notSucceeded]
          simp only [Commands.returned, Stateful.Acyclic.run?, Bool.not_false,
            bind, Except.bind]
          have errorResult := digitError_evaluates (source := source)
            (world := world)
            (((environment source start).push (.signed .i32 scanStart)).push
              (digitScanValue (.failure error)))
            (Commands.slot 4) error resultBound (by rfl)
          have returned := numberFailure_evaluates (source := source)
            (world := world)
            (((environment source start).push (.signed .i32 scanStart)).push
              (digitScanValue (.failure error)))
            (Commands.digitError (Commands.slot 4)) error resultBound errorResult
          dsimp [scanStart] at returned
          rw [returned]
          simp [encoded, scanExponent, resultEq]
          rfl
  · rw [decide_eq_false digitsInBounds]
    simp only [bind, Except.bind]
    let scanStart := digitsStart
    have digitResult := digitRun_evaluates (source := source) (world := world)
      ((environment source start).push (.signed .i32 scanStart))
      (Commands.slot 0) (Commands.slot 1) (Commands.slot 3)
      (Commands.i32 10) scanStart 10 sourceFound sourceBound digitsStartBound
      (by omega) (by rfl) (by rfl) (by rfl) (by rfl)
    rw [digitResult]
    simp only [bind, Except.bind]
    have logicalStart : exponentDigitsStart source start = scanStart := by
      simp [exponentDigitsStart, byteValueAt, digitsStart, scanStart,
        digitsInBounds]
    simp only [scanExponent]
    rw [logicalStart]
    cases resultEq : scanDigitRun source scanStart 10 with
    | success finish =>
        have resultBound := digitRunResult_bound (source := source)
          (start := scanStart) (base := 10) sourceBound digitsStartBound
        rw [resultEq] at resultBound digitResult
        have succeeded : Term.evaluate (termMachine source) world
            (((environment source start).push (.signed .i32 scanStart)).push
              (digitScanValue (.success finish)))
            (Commands.digitSucceeded (Commands.slot 4)) =
            .ok (.boolean true, world) := digitSucceeded_evaluates (source := source)
          (world := world)
          (((environment source start).push (.signed .i32 scanStart)).push
            (digitScanValue (.success finish)))
          (Commands.slot 4) (.success finish) resultBound (by rfl)
        have notSucceeded := logicalNot_evaluates (source := source)
          (((environment source start).push (.signed .i32 scanStart)).push
            (digitScanValue (.success finish)))
          (Commands.digitSucceeded (Commands.slot 4)) true succeeded
        dsimp [scanStart] at notSucceeded
        rw [notSucceeded]
        simp only [Commands.returned, Stateful.Acyclic.run?, Bool.not_true,
          bind, Except.bind]
        have endResult := digitEnd_evaluates (source := source)
          (world := world)
          (((environment source start).push (.signed .i32 scanStart)).push
            (digitScanValue (.success finish)))
          (Commands.slot 4) finish resultBound (by rfl)
        have returned := floatScan_evaluates (source := source)
          (world := world)
          (((environment source start).push (.signed .i32 scanStart)).push
            (digitScanValue (.success finish)))
          (Commands.digitEnd (Commands.slot 4)) finish resultBound endResult
        dsimp [scanStart] at returned
        rw [returned]
        simp [Stateful.Acyclic.run?, encoded, scanExponent, resultEq]
        rfl
    | failure error =>
        have resultBound := digitRunResult_bound (source := source)
          (start := scanStart) (base := 10) sourceBound digitsStartBound
        rw [resultEq] at resultBound digitResult
        have succeeded : Term.evaluate (termMachine source) world
            (((environment source start).push (.signed .i32 scanStart)).push
              (digitScanValue (.failure error)))
            (Commands.digitSucceeded (Commands.slot 4)) =
            .ok (.boolean false, world) := digitSucceeded_evaluates (source := source)
          (world := world)
          (((environment source start).push (.signed .i32 scanStart)).push
            (digitScanValue (.failure error)))
          (Commands.slot 4) (.failure error) resultBound (by rfl)
        have notSucceeded := logicalNot_evaluates (source := source)
          (((environment source start).push (.signed .i32 scanStart)).push
            (digitScanValue (.failure error)))
          (Commands.digitSucceeded (Commands.slot 4)) false succeeded
        dsimp [scanStart] at notSucceeded
        rw [notSucceeded]
        simp only [Commands.returned, Stateful.Acyclic.run?, Bool.not_false,
          bind, Except.bind]
        have errorResult := digitError_evaluates (source := source)
          (world := world)
          (((environment source start).push (.signed .i32 scanStart)).push
            (digitScanValue (.failure error)))
          (Commands.slot 4) error resultBound (by rfl)
        have returned := numberFailure_evaluates (source := source)
          (world := world)
          (((environment source start).push (.signed .i32 scanStart)).push
            (digitScanValue (.failure error)))
          (Commands.digitError (Commands.slot 4)) error resultBound errorResult
        dsimp [scanStart] at returned
        rw [returned]
        simp [Stateful.Acyclic.run?, encoded, scanExponent, resultEq]
        rfl

theorem scanExponent_evaluates
    (source : List Byte) (world : ReadOnly.World) (start : Nat)
    (sourceFound : world.i32Slice? 0 = some (sourceIntegers source))
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    Command.Evaluates (termMachine source) (commandMachine source)
      world (environment source start) Commands.scanExponentReadable
      (.returned (some (encoded (scanExponent source start)))) world
      (environment source start) :=
  Stateful.Acyclic.run?_sound
    (scanExponent_run source world start sourceFound sourceBound startInBounds)

end Lanius.Extraction.Decimal.ScanExponentEvaluation
