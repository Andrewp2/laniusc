import verified_compiler.tests.direct_ir_decimal_loop
import verified_compiler.tests.direct_ir_error

namespace IRIntegerLoweringProof

open Lanius Lanius.Core Lanius.Semantics IRDecimalProof IRDecimalLoopProof

variable {before after : State}
private def integerSource := Extracted.«lowering::body_context».Functions.«integer_literal».core
private def decimalSource := Extracted.«lowering::body_context».Functions.«decimal».core
private def succeededSource := Extracted.«lowering::constant_expression».Functions.«succeeded».core
private def valueSource := Extracted.«lowering::constant_expression».Functions.«value».core
private def tokenType : Ty := match source_value Extracted.«verified::token».Types.«TokenRow».mk [] with
  | .structure id _ => .structure id | _ => .unit

structure Input (before : State) extends IRDecimalLoopProof.Input before where
  tokenAddress : Nat
  tokenCapacity : Nat
  tokenCount : Nat
  tokenBound : tokenCount ≤ tokenCapacity
  tokenStorage : Nat
  tokenIndex : Nat
  tokenFits : tokenCount < 2 ^ 31
  tokenInside : tokenIndex < tokenCount
  tokenRead : readRawSliceIndex extractedProgram before tokenType tokenAddress tokenCapacity tokenIndex = .ok
    (source_value Extracted.«verified::token».Types.«TokenRow».mk
      [source_value Extracted.«verified::token».Types.«TokenKind».«Integer» [],
        .signed .i32 start, .signed .i32 (start + length)])

def Input.reheap (input : Input before) (same : after.heap = before.heap) : Input after :=
  { input with
    reads := by intro index bound; simpa only [readRawSliceIndex, same] using input.reads index bound
    tokenRead := by simpa only [readRawSliceIndex, same] using input.tokenRead }
def Input.tokens (input : Input before) : Value := source_value Extracted.«verified::token».Types.«TokenTable».mk
  [.rawSlice tokenType input.tokenAddress input.tokenCapacity, .signed .i32 input.tokenCount, .pointer input.tokenStorage]
def Input.integerCall (input : Input before) : Expr := .call integerSource.id
  [.value (.rawSlice (.scalar (.signed .i32)) input.address input.capacity), .value (.signed .i32 input.count),
    .value input.tokens, .value (.signed .i32 input.tokenCount), .value (.signed .i32 input.tokenIndex)]
def Input.decimalCall (input : Input before) : Expr := .call decimalSource.id
  [.value (.rawSlice (.scalar (.signed .i32)) input.address input.capacity), .value (.signed .i32 input.count),
    .value input.tokens, .value (.signed .i32 input.tokenCount), .value (.signed .i32 input.tokenIndex)]

def succeeded : Accumulator → Bool | .number _ => true | _ => false
def integerValue : Accumulator → Int | .number number => number | _ => 0
def loweredValue : Accumulator → Int | .number number => number | _ => -1

@[core_pure_rule] theorem actualSucceeded (state : Accumulator) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call succeededSource.id [.value (resultValue state)])
      (.boolean (succeeded state)) after ∧ PureFrame before after := by
  cases state <;> dsimp only [resultValue, succeeded]
  all_goals (core_call_pure succeededSource as callee; core_pure)

@[core_pure_rule] theorem actualValue (state : Accumulator) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call valueSource.id [.value (resultValue state)])
      (.signed .i32 (integerValue state)) after ∧ PureFrame before after := by
  cases state <;> dsimp only [resultValue, integerValue]
  all_goals (core_call_pure valueSource as callee; core_pure)

/-- The source token's actual native row supplies the decoder's span. -/
theorem actualInteger (input : Input before) (formed : before.CellsWellFormed) (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before input.integerCall
      (resultValue (scan input.bytes input.length 0 .empty)) after ∧ PureFrame before after := by
  core_facts [input]
  core_call_pure integerSource as callee
  apply RunsStmt.guardPureFalse
  · core_run
  · apply RunsStmt.letPure
    · core_run
    · core_formed
    · apply RunsStmt.returnPure
      apply RunsExpr.callPureArguments
      · core_arguments
      · core_state current
        exact IRDecimalLoopProof.actualDecimal (input.reheap (after := current) rfl).toInput (by core_formed) noViews

/-- Positive literals become their numeric value; empty, malformed, overflowing
    or unary-minus-only magnitudes become the frontend's explicit -1 failure. -/
theorem actualDecimal (input : Input before) (formed : before.CellsWellFormed) (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before input.decimalCall
      (.signed .i32 (loweredValue (scan input.bytes input.length 0 .empty))) after ∧ PureFrame before after := by
  core_call_pure decimalSource as callee
  apply RunsStmt.letFramedPure
  · apply RunsExpr.callPureArguments
    · core_arguments
    · core_state current
      exact actualInteger (input.reheap (after := current) rfl) (by core_formed) noViews
  · intro ready pure
    dsimp only [Input.reheap]
    cases result : scan input.bytes input.length 0 .empty with
    | number number =>
        dsimp only [loweredValue]
        apply RunsStmt.guardFramedFalse
        · apply RunsExpr.unaryPure
          · apply RunsExpr.callPureArguments
            · core_arguments
            · exact actualSucceeded (.number number) (by core_formed)
          · rfl
        · intro checked frame
          apply RunsStmt.returnPure
          apply RunsExpr.callPureArguments
          · core_arguments
          · exact actualValue (.number number) (by core_formed)
    | empty | minimum | rejected => dsimp only [loweredValue]; core_pure

#print axioms actualInteger
#print axioms actualDecimal

end IRIntegerLoweringProof

