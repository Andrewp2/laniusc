import SelfCore
import Lanius.Semantics.CallProof
import Lanius.Semantics.PureProof
import Lanius.Semantics.SourceValue

namespace IRDecimalProof

open Lanius Lanius.Core Lanius.Semantics

inductive Accumulator where
  | empty | number (value : Nat) | minimum | rejected
  deriving DecidableEq

def stateValue : Accumulator → Value
  | .empty => source_value Extracted.«lowering::constant_expression».Types.«DecimalState».«Empty» []
  | .number value => source_value Extracted.«lowering::constant_expression».Types.«DecimalState».«Number» [.signed .i32 value]
  | .minimum => source_value Extracted.«lowering::constant_expression».Types.«DecimalState».«Min» []
  | .rejected => source_value Extracted.«lowering::constant_expression».Types.«DecimalState».«Rejected» []

def bounded : Accumulator → Prop | .number value => value < 2 ^ 31 | _ => True

/-- Mathematical append, independent of the source's division-based guard. -/
def appendDigit (answer digit : Nat) : Accumulator :=
  if answer * 10 + digit < 2 ^ 31 then .number (answer * 10 + digit)
  else if answer * 10 + digit = 2 ^ 31 then .minimum else .rejected

def step (state : Accumulator) (byte : Int) : Accumulator :=
  if byte = 95 then state else if byte < 48 ∨ 57 < byte then .rejected else
    match state with
    | .empty => .number (byte - 48).toNat
    | .number answer => appendDigit answer (byte - 48).toNat
    | _ => .rejected

def resultValue : Accumulator → Value
  | .number value => source_value Extracted.«lowering::constant_expression».Types.«Result».«Integer» [.signed .i32 value]
  | .minimum => source_value Extracted.«lowering::constant_expression».Types.«Result».«MinMagnitude» []
  | _ => source_value Extracted.«lowering::constant_expression».Types.«Result».«Invalid» []

private def digitSource := Extracted.«lowering::constant_expression».Functions.«decimal_digit».core
private def stepSource := Extracted.«lowering::constant_expression».Functions.«decimal_step».core
private def finishSource := Extracted.«lowering::constant_expression».Functions.«decimal_finish».core
private def rejectedSource := Extracted.«lowering::constant_expression».Functions.«decimal_rejected».core

@[core_pure_rule] theorem actualDigit (answer digit : Nat) (fits : answer < 2 ^ 31)
    (digitBound : digit < 10) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call digitSource.id
      [.value (.signed .i32 answer), .value (.signed .i32 digit)])
      (stateValue (appendDigit answer digit)) after ∧ PureFrame before after := by
  have sub := eval_i32_subNat extractedProgram.target 2147483647 digit (by omega) (by decide)
  have div := eval_i32_divNat extractedProgram.target (2147483647 - digit) 10
    (by decide) (by omega)
  dsimp only [appendDigit]
  split
  · have multiply := eval_i32_mulNat extractedProgram.target answer 10 (by omega)
    have add := eval_i32_addNat extractedProgram.target (answer * 10) digit (by omega)
    core_call_pure digitSource as callee
    core_pure
  · split
    all_goals
      core_call_pure digitSource as callee
      core_pure

@[core_pure_rule] theorem actualFinish (state : Accumulator) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call finishSource.id [.value (stateValue state)])
      (resultValue state) after ∧ PureFrame before after := by
  cases state <;> dsimp only [stateValue, resultValue]
  all_goals (core_call_pure finishSource as callee; core_pure)

@[core_pure_rule] theorem actualRejected (state : Accumulator) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call rejectedSource.id [.value (stateValue state)])
      (.boolean (decide (state = .rejected))) after ∧ PureFrame before after := by
  cases state <;> dsimp only [stateValue] <;> simp only [reduceCtorEq, decide_false, decide_true]
  all_goals (core_call_pure rejectedSource as callee; core_pure)

theorem step_bounded (state : Accumulator) (byte : Int) (fits : bounded state) : bounded (step state byte) := by
  dsimp only [step]
  split
  · exact fits
  · split
    · trivial
    · cases state with
      | empty => dsimp only [bounded]; omega
      | number answer =>
          dsimp only
          unfold appendDigit
          split
          · dsimp only [bounded]; assumption
          · split <;> trivial
      | minimum | rejected => trivial

@[core_pure_rule] theorem actualStep (state : Accumulator) (byte : Int) (fits : bounded state)
    (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call stepSource.id
      [.value (stateValue state), .value (.signed .i32 byte)])
      (stateValue (step state byte)) after ∧ PureFrame before after := by
  dsimp only [step]
  split
  · core_call_pure stepSource as callee
    core_pure
  · split
    · core_call_pure stepSource as callee
      core_pure
    · have digitBound : (byte - 48).toNat < 10 := by omega
      have sub : evalBinaryValue extractedProgram.target .subtract (.signed .i32 byte) (.signed .i32 48) =
          .ok (.signed .i32 (byte - 48).toNat) := by
        simpa only [Int.toNat_of_nonneg (by omega : 0 ≤ byte - 48)] using
          eval_i32_subNonneg extractedProgram.target byte 48 (by omega) (by omega)
      core_call_pure stepSource as callee
      apply RunsStmt.guardPureFalse
      · core_run
      apply RunsStmt.guardPureFalse
      · core_run
      cases state <;> dsimp only [bounded] at fits <;> dsimp only [stateValue]
      all_goals core_pure

theorem rejected_absorbs (byte : Int) : step .rejected byte = .rejected := by
  simp [step]

def decode (bytes : List Int) : Accumulator := bytes.foldl step .empty

theorem decode_bounded (bytes : List Int) : bounded (decode bytes) := by
  suffices ∀ state, bounded state → bounded (bytes.foldl step state) from this .empty trivial
  induction bytes with
  | nil => exact fun _ fit => fit
  | cons byte bytes ih => exact fun state fit => ih _ (step_bounded state byte fit)

#print axioms actualDigit
#print axioms actualFinish
#print axioms actualRejected
#print axioms actualStep

end IRDecimalProof

