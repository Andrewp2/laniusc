import Lanius.Extraction.Decimal.FinishEvaluationTerms
import Lanius.Extraction.Decimal.EvaluationBounds

namespace Lanius.Extraction.Decimal.FinishEvaluationSupport

open Lanius
open Lanius.Core
open Lanius.Compiler.Lexer
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Stateful
open Lanius.Extraction.Decimal

/-! Small, typed interfaces used by the `finish_decimal` execution proof.

The checked command and the logical lexer spell the exponent test in two
different Boolean forms.  Both are normalized through `isExponentByte`, so a
proof branches on the source-level proposition once instead of maintaining
parallel `decide` and `BEq` facts.

The tail wrappers keep the very large recovered command out of intermediate
theorem types.  Their definitions remain transparent when an execution proof
needs to unfold one local step.
-/

def isExponentByte (byte : Nat) : Prop :=
  byte = 101 ∨ byte = 69

instance (byte : Nat) : Decidable (isExponentByte byte) :=
  inferInstanceAs (Decidable (byte = 101 ∨ byte = 69))

def exponentFlag (byte : Nat) : Bool :=
  decide (isExponentByte byte)

@[simp] theorem exponentFlag_eq_decideOr (byte : Nat) :
    exponentFlag byte =
      (decide (byte = 101) || decide (byte = 69)) := by
  by_cases lower : byte = 101 <;> by_cases upper : byte = 69 <;>
    simp [exponentFlag, isExponentByte, lower, upper]

@[simp] theorem exponentFlag_eq_beqOr (byte : Nat) :
    exponentFlag byte = (byte == 101 || byte == 69) := by
  by_cases lower : byte = 101 <;> by_cases upper : byte = 69 <;>
    simp [exponentFlag, isExponentByte, lower, upper]

@[simp] theorem exponentFlag_eq_true_iff (byte : Nat) :
    exponentFlag byte = true ↔ isExponentByte byte := by
  simp [exponentFlag]

@[simp] theorem exponentFlag_eq_false_iff (byte : Nat) :
    exponentFlag byte = false ↔ ¬ isExponentByte byte := by
  simp [exponentFlag]

theorem decideOr_eq_true (byte : Nat) (exponent : isExponentByte byte) :
    (decide (byte = 101) || decide (byte = 69)) = true := by
  simpa using (exponentFlag_eq_true_iff byte).2 exponent

theorem decideOr_eq_false (byte : Nat) (exponent : ¬ isExponentByte byte) :
    (decide (byte = 101) || decide (byte = 69)) = false := by
  simpa using (exponentFlag_eq_false_iff byte).2 exponent

theorem beqOr_eq_true (byte : Nat) (exponent : isExponentByte byte) :
    (byte == 101 || byte == 69) = true := by
  simpa using (exponentFlag_eq_true_iff byte).2 exponent

theorem beqOr_eq_false (byte : Nat) (exponent : ¬ isExponentByte byte) :
    (byte == 101 || byte == 69) = false := by
  simpa using (exponentFlag_eq_false_iff byte).2 exponent

abbrev TailExecution :=
  Option (Stateful.Completion × ReadOnly.World × Env 4)

abbrev TailBodyExecution :=
  Option (Stateful.Completion × ReadOnly.World × Env 5)

noncomputable def tailRun (source : List Byte) (world : ReadOnly.World)
    (integerEnd : Nat) (next : Byte) : TailExecution :=
  Acyclic.run? (FinishEvaluationModel.termMachine source)
    (FinishEvaluationModel.commandMachine source) world
    ((EvaluationModel.environment source integerEnd).push
      (.signed .i32 next.val))
    Commands.finishDecimalTail

noncomputable def tailBodyRun (source : List Byte) (world : ReadOnly.World)
    (integerEnd : Nat) (next : Byte) : TailBodyExecution :=
  Acyclic.run? (FinishEvaluationModel.termMachine source)
    (FinishEvaluationModel.commandMachine source) world
    (((EvaluationModel.environment source integerEnd).push
      (.signed .i32 next.val)).push (.signed .i32 (integerEnd + 1)))
    Commands.finishDecimalTailBody

noncomputable def tailReturnRun (source : List Byte) (world : ReadOnly.World)
    (integerEnd : Nat) (next : Byte) : TailBodyExecution :=
  Acyclic.run? (FinishEvaluationModel.termMachine source)
    (FinishEvaluationModel.commandMachine source) world
    (((EvaluationModel.environment source integerEnd).push
      (.signed .i32 next.val)).push (.signed .i32 (integerEnd + 1)))
    (Commands.returned (Commands.floatScan (Commands.slot 4)))

noncomputable def fractionBodyRun (source : List Byte) (world : ReadOnly.World)
    (integerEnd : Nat) (next : Byte) : TailBodyExecution :=
  Acyclic.run? (FinishEvaluationModel.termMachine source)
    (FinishEvaluationModel.commandMachine source) world
    (((EvaluationModel.environment source integerEnd).push
      (.signed .i32 next.val)).push (.signed .i32 (integerEnd + 1)))
    Commands.finishDecimalFractionBody

def fractionBodyCompletion (source : List Byte) (integerEnd : Nat)
    (first : Byte) : Stateful.Completion :=
  if isDigitForBase first 10 || exponentFlag first then
    .returned (some (EvaluationModel.encoded (finishDecimal source integerEnd)))
  else
    .next

noncomputable def tailBodyResult (source : List Byte) (world : ReadOnly.World)
    (integerEnd : Nat) (next : Byte) (completion : Stateful.Completion) :
    TailBodyExecution :=
  match completion with
  | .next => tailReturnRun source world integerEnd next
  | completion =>
      some (completion, world,
        ((EvaluationModel.environment source integerEnd).push
          (.signed .i32 next.val)).push
            (.signed .i32 (integerEnd + 1)))

def tailResult (source : List Byte) (world : ReadOnly.World)
    (integerEnd : Nat) (next : Byte) : TailExecution :=
  some (Stateful.Completion.returned
      (some (EvaluationModel.encoded (finishDecimal source integerEnd))),
    world,
    (EvaluationModel.environment source integerEnd).push
      (.signed .i32 next.val))

@[simp] theorem byteValueAt_get (source : List Byte) (offset : Nat)
    (inBounds : offset < source.length) :
    byteValueAt source offset =
      some (source.get ⟨offset, inBounds⟩).val := by
  unfold byteValueAt
  simp only [List.getElem?_eq_getElem inBounds, Option.map_some]
  congr

theorem finishDecimal_fractionAtEnd
    (source : List Byte) (integerEnd : Nat) (next : Byte)
    (inBounds : integerEnd < source.length)
    (nextAt : source[integerEnd] = next)
    (isDot : next.val = 46)
    (fractionAtEnd : ¬ integerEnd + 1 < source.length) :
    finishDecimal source integerEnd =
      .success .float (integerEnd + 1) := by
  have atEnd : integerEnd + 1 = source.length := by omega
  have nextValue : byteValueAt source integerEnd = some next.val := by
    rw [byteValueAt_get source integerEnd inBounds]
    simp [nextAt]
  have fractionValue : byteValueAt source (integerEnd + 1) = none := by
    unfold byteValueAt
    simp [atEnd]
  simp [finishDecimal, nextValue, fractionValue, isDot]

theorem finishDecimal_digitFailure
    (source : List Byte) (integerEnd first error : Nat)
    (dotAt : byteValueAt source integerEnd = some 46)
    (notDoubleDot : byteValueAt source (integerEnd + 1) ≠ some 46)
    (firstAt : byteValueAt source (integerEnd + 1) = some first)
    (decimal : 48 ≤ first ∧ first ≤ 57)
    (digits : scanDigitRun source (integerEnd + 1) 10 = .failure error) :
    finishDecimal source integerEnd = .failure error := by
  have firstNotDot : first ≠ 46 := by
    intro equal
    apply notDoubleDot
    simpa [equal] using firstAt
  simp [finishDecimal, dotAt, firstAt, firstNotDot, decimal, digits]

theorem finishDecimal_digitSuccessExponent
    (source : List Byte) (integerEnd first finish exponentByte : Nat)
    (dotAt : byteValueAt source integerEnd = some 46)
    (notDoubleDot : byteValueAt source (integerEnd + 1) ≠ some 46)
    (firstAt : byteValueAt source (integerEnd + 1) = some first)
    (decimal : 48 ≤ first ∧ first ≤ 57)
    (digits : scanDigitRun source (integerEnd + 1) 10 = .success finish)
    (exponentAt : byteValueAt source finish = some exponentByte)
    (hasExponent : isExponentByte exponentByte) :
    finishDecimal source integerEnd = scanExponent source finish := by
  have firstNotDot : first ≠ 46 := by
    intro equal
    apply notDoubleDot
    simpa [equal] using firstAt
  simp [finishDecimal, dotAt, firstAt, firstNotDot, decimal, digits,
    exponentAt, beqOr_eq_true exponentByte hasExponent]

theorem finishDecimal_digitSuccessNoExponent
    (source : List Byte) (integerEnd first finish exponentByte : Nat)
    (dotAt : byteValueAt source integerEnd = some 46)
    (notDoubleDot : byteValueAt source (integerEnd + 1) ≠ some 46)
    (firstAt : byteValueAt source (integerEnd + 1) = some first)
    (decimal : 48 ≤ first ∧ first ≤ 57)
    (digits : scanDigitRun source (integerEnd + 1) 10 = .success finish)
    (exponentAt : byteValueAt source finish = some exponentByte)
    (notExponent : ¬ isExponentByte exponentByte) :
    finishDecimal source integerEnd = .success .float finish := by
  have firstNotDot : first ≠ 46 := by
    intro equal
    apply notDoubleDot
    simpa [equal] using firstAt
  simp [finishDecimal, dotAt, firstAt, firstNotDot, decimal, digits,
    exponentAt, beqOr_eq_false exponentByte notExponent]

theorem finishDecimal_digitSuccessAtEnd
    (source : List Byte) (integerEnd first finish : Nat)
    (dotAt : byteValueAt source integerEnd = some 46)
    (notDoubleDot : byteValueAt source (integerEnd + 1) ≠ some 46)
    (firstAt : byteValueAt source (integerEnd + 1) = some first)
    (decimal : 48 ≤ first ∧ first ≤ 57)
    (digits : scanDigitRun source (integerEnd + 1) 10 = .success finish)
    (atEnd : byteValueAt source finish = none) :
    finishDecimal source integerEnd = .success .float finish := by
  have firstNotDot : first ≠ 46 := by
    intro equal
    apply notDoubleDot
    simpa [equal] using firstAt
  simp [finishDecimal, dotAt, firstAt, firstNotDot, decimal, digits, atEnd]

theorem finishDecimal_nonDigitExponent
    (source : List Byte) (integerEnd first : Nat)
    (dotAt : byteValueAt source integerEnd = some 46)
    (notDoubleDot : byteValueAt source (integerEnd + 1) ≠ some 46)
    (firstAt : byteValueAt source (integerEnd + 1) = some first)
    (notDecimal : ¬ (48 ≤ first ∧ first ≤ 57))
    (exponent : isExponentByte first) :
    finishDecimal source integerEnd =
      scanExponent source (integerEnd + 1) := by
  have firstNotDot : first ≠ 46 := by
    intro equal
    apply notDoubleDot
    simpa [equal] using firstAt
  simp [finishDecimal, dotAt, firstAt, firstNotDot, notDecimal,
    beqOr_eq_true first exponent]

theorem finishDecimal_nonDigitNoExponent
    (source : List Byte) (integerEnd first : Nat)
    (dotAt : byteValueAt source integerEnd = some 46)
    (notDoubleDot : byteValueAt source (integerEnd + 1) ≠ some 46)
    (firstAt : byteValueAt source (integerEnd + 1) = some first)
    (notDecimal : ¬ (48 ≤ first ∧ first ≤ 57))
    (notExponent : ¬ isExponentByte first) :
    finishDecimal source integerEnd = .success .float (integerEnd + 1) := by
  have firstNotDot : first ≠ 46 := by
    intro equal
    apply notDoubleDot
    simpa [equal] using firstAt
  simp [finishDecimal, dotAt, firstAt, firstNotDot, notDecimal,
    beqOr_eq_false first notExponent]

end Lanius.Extraction.Decimal.FinishEvaluationSupport
