import verified_compiler.tests.direct_ir_expression_kind
import Lanius.Surface

namespace IRBinaryKindProof

open Lanius Lanius.Core Lanius.Semantics IRTypeRefProof IRExpressionKindProof

private def decisionSource := Extracted.«lowering::body_expression».Functions.«binary_kind».core
private def operationSource := Extracted.«lowering::body_expression».Functions.«binary_operation».core
private def comparisonSource := Extracted.«backend::syntax».Functions.«binary_is_comparison».core

def operationValue : Surface.BinaryOp → Value
  | .logicalAnd => source_value Extracted.«backend::syntax».Types.«BinaryOperation».«BinaryAndThen» []
  | .logicalOr => source_value Extracted.«backend::syntax».Types.«BinaryOperation».«BinaryOrElse» []
  | .equal => source_value Extracted.«backend::syntax».Types.«BinaryOperation».«BinaryEqual» []
  | .notEqual => source_value Extracted.«backend::syntax».Types.«BinaryOperation».«BinaryNotEqual» []
  | .less => source_value Extracted.«backend::syntax».Types.«BinaryOperation».«BinaryLess» []
  | .lessEqual => source_value Extracted.«backend::syntax».Types.«BinaryOperation».«BinaryLessEqual» []
  | .greater => source_value Extracted.«backend::syntax».Types.«BinaryOperation».«BinaryGreater» []
  | .greaterEqual => source_value Extracted.«backend::syntax».Types.«BinaryOperation».«BinaryGreaterEqual» []
  | .add => source_value Extracted.«backend::syntax».Types.«BinaryOperation».«BinaryAdd» []
  | .subtract => source_value Extracted.«backend::syntax».Types.«BinaryOperation».«BinarySubtract» []
  | .multiply => source_value Extracted.«backend::syntax».Types.«BinaryOperation».«BinaryMultiply» []
  | .divide => source_value Extracted.«backend::syntax».Types.«BinaryOperation».«BinaryDivide» []
  | .remainder => source_value Extracted.«backend::syntax».Types.«BinaryOperation».«BinaryRemainder» []
  | .bitAnd => source_value Extracted.«backend::syntax».Types.«BinaryOperation».«BinaryBitAnd» []
  | .bitOr => source_value Extracted.«backend::syntax».Types.«BinaryOperation».«BinaryBitOr» []
  | .bitXor => source_value Extracted.«backend::syntax».Types.«BinaryOperation».«BinaryBitXor» []
  | .shiftLeft => source_value Extracted.«backend::syntax».Types.«BinaryOperation».«BinaryShiftLeft» []
  | .shiftRight => source_value Extracted.«backend::syntax».Types.«BinaryOperation».«BinaryShiftRight» []
def sourceValue : Surface.BinaryOp → Value
  | .logicalAnd => source_value Extracted.«verified::surface_expr».Types.«ExpressionOperator».«BinaryAndThen» []
  | .logicalOr => source_value Extracted.«verified::surface_expr».Types.«ExpressionOperator».«BinaryOrElse» []
  | .equal => source_value Extracted.«verified::surface_expr».Types.«ExpressionOperator».«BinaryEqual» []
  | .notEqual => source_value Extracted.«verified::surface_expr».Types.«ExpressionOperator».«BinaryNotEqual» []
  | .less => source_value Extracted.«verified::surface_expr».Types.«ExpressionOperator».«BinaryLess» []
  | .lessEqual => source_value Extracted.«verified::surface_expr».Types.«ExpressionOperator».«BinaryLessEqual» []
  | .greater => source_value Extracted.«verified::surface_expr».Types.«ExpressionOperator».«BinaryGreater» []
  | .greaterEqual => source_value Extracted.«verified::surface_expr».Types.«ExpressionOperator».«BinaryGreaterEqual» []
  | .add => source_value Extracted.«verified::surface_expr».Types.«ExpressionOperator».«BinaryAdd» []
  | .subtract => source_value Extracted.«verified::surface_expr».Types.«ExpressionOperator».«BinarySubtract» []
  | .multiply => source_value Extracted.«verified::surface_expr».Types.«ExpressionOperator».«BinaryMultiply» []
  | .divide => source_value Extracted.«verified::surface_expr».Types.«ExpressionOperator».«BinaryDivide» []
  | .remainder => source_value Extracted.«verified::surface_expr».Types.«ExpressionOperator».«BinaryRemainder» []
  | .bitAnd => source_value Extracted.«verified::surface_expr».Types.«ExpressionOperator».«BinaryBitAnd» []
  | .bitOr => source_value Extracted.«verified::surface_expr».Types.«ExpressionOperator».«BinaryBitOr» []
  | .bitXor => source_value Extracted.«verified::surface_expr».Types.«ExpressionOperator».«BinaryBitXor» []
  | .shiftLeft => source_value Extracted.«verified::surface_expr».Types.«ExpressionOperator».«BinaryShiftLeft» []
  | .shiftRight => source_value Extracted.«verified::surface_expr».Types.«ExpressionOperator».«BinaryShiftRight» []

def comparison : Surface.BinaryOp → Bool
  | .equal | .notEqual | .less | .lessEqual | .greater | .greaterEqual => true
  | _ => false

private def is (operation expected : Surface.BinaryOp) : Bool :=
  Value.beq (operationValue operation) (operationValue expected)

private theorem equalOperation (operation expected : Surface.BinaryOp) :
    evalBinaryValue extractedProgram.target .equal (operationValue operation) (operationValue expected) =
      .ok (.boolean (is operation expected)) := by
  cases operation <;> cases expected <;> rfl

@[core_pure_rule] theorem actualOperation (operation : Surface.BinaryOp) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call operationSource.id [.value (sourceValue operation)])
      (operationValue operation) after ∧ PureFrame before after := by
  cases operation <;> (core_call_pure operationSource as callee; core_pure)

@[core_pure_rule] theorem actualComparison (operation : Surface.BinaryOp) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call comparisonSource.id [.value (operationValue operation)])
      (.boolean (comparison operation)) after ∧ PureFrame before after := by
  cases operation <;> (core_call_pure comparisonSource as callee; core_pure)

/-- Contextual equality may inspect syntax and signatures. Scalar decisions
    below work with arbitrary context values because those branches are unused. -/
structure Site where
  context : Value
  count : Int
  left : Int
  right : Int

def Site.call (site : Site) (operation : Surface.BinaryOp) (left right : Value) : Expr :=
  .call decisionSource.id ([site.context, .signed .i32 site.count, .signed .i32 site.left, .signed .i32 site.right,
    operationValue operation, left, right].map Expr.value)

inductive IntegerKind where | i32 | usize
def IntegerKind.reference : IntegerKind → Reference | .i32 => .I32 | .usize => .Usize

def numericResult (operation : Surface.BinaryOp) (kind : IntegerKind) : Value :=
  match operation with
  | .logicalAnd | .logicalOr => unsupported
  | _ => known (if comparison operation then .Bool else kind.reference)

def integerAccepts : Surface.BinaryOp → Bool
  | .logicalAnd | .logicalOr => false
  | _ => true
def integerResult (operation : Surface.BinaryOp) : Reference :=
  if comparison operation then .Bool else .I32

theorem numericInteger (operation : Surface.BinaryOp) (accepted : integerAccepts operation = true) :
    numericResult operation .i32 = known (integerResult operation) := by
  cases operation <;> simp [integerAccepts, numericResult, integerResult, comparison, IntegerKind.reference] at *

private theorem numericResult_eq (operation : Surface.BinaryOp) (kind : IntegerKind) :
    numericResult operation kind =
      if is operation .logicalAnd || is operation .logicalOr then unsupported
      else known (if comparison operation then .Bool else kind.reference) := by
  cases operation <;> rfl

/-- All integer operators follow the language's primitive typing rule.
    Context values are arbitrary: this path never consults source or signatures. -/
theorem actualNumeric (site : Site) (operation : Surface.BinaryOp) (kind : IntegerKind)
    (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before
      (site.call operation (known kind.reference) (known kind.reference))
      (numericResult operation kind) after ∧ PureFrame before after := by
  have boolean := fun {state : State} (h : state.CellsWellFormed) => actualKnown .Bool (by decide) h
  have integer := fun {state : State} (h : state.CellsWellFormed) =>
    actualKnown kind.reference (by cases kind <;> rfl) h
  have comparisonRun := fun {state : State} (h : state.CellsWellFormed) => actualComparison operation h
  have boolSame := fun {state : State} (h : state.CellsWellFormed) => actualSame kind.reference .Bool h
  have selfSame := fun {state : State} (h : state.CellsWellFormed) => actualSame kind.reference kind.reference h
  have i32Same := fun {state : State} (h : state.CellsWellFormed) => actualSame kind.reference .I32 h
  have usizeSame := fun {state : State} (h : state.CellsWellFormed) => actualSame kind.reference .Usize h
  have validRun := fun {state : State} (h : state.CellsWellFormed) => actualValid kind.reference h
  have valid : isValid kind.reference = true := by cases kind <;> rfl
  have numeric : (sameType kind.reference .I32 || sameType kind.reference .Usize) = true := by cases kind <;> rfl
  have notBool : sameType kind.reference .Bool = false := by cases kind <;> rfl
  have identical : sameType kind.reference kind.reference = true := by cases kind <;> rfl
  simp only [notBool] at boolSame
  simp only [identical] at selfSame
  simp only [valid] at validRun
  have andThen := equalOperation operation .logicalAnd
  have orElse := equalOperation operation .logicalOr
  have equal := equalOperation operation .equal
  have notEqual := equalOperation operation .notEqual
  core_call_pure decisionSource as callee
  iterate 2 (apply RunsStmt.letFramedPure; core_pure_expr; intro middle frame)
  iterate 2 (apply RunsStmt.guardFramedFalse; core_pure_guard; intro middle frame)
  by_cases logical : (is operation .logicalAnd || is operation .logicalOr) = true
  · simp only [numericResult_eq, logical, ↓reduceIte]
    apply RunsStmt.guardFramedTrue
    · simp
    · core_pure_guard
    · intro middle frame
      core_pure
  · apply RunsStmt.guardFramedFalse
    · core_pure_guard
    · intro middle frame
      iterate 2 (apply RunsStmt.letFramedPure; core_pure_expr; intro middle frame)
      apply RunsStmt.guardFramedTrue
      · simp
      · core_pure_guard
      · intro middle frame
        apply RunsStmt.guardFramedTrue
        · simp
        · core_pure_guard
        · intro middle frame
          by_cases compared : comparison operation = true
          · simp only [numericResult_eq, logical, compared, ↓reduceIte]
            apply RunsStmt.guardFramedTrue
            · simp
            · core_pure_guard
            · intro middle frame
              core_pure
          · simp only [numericResult_eq, logical, compared, ↓reduceIte]
            apply RunsStmt.guardFramedFalse
            · core_pure_guard
            · intro middle frame
              core_pure

def booleanAccepts : Surface.BinaryOp → Bool
  | .logicalAnd | .logicalOr | .equal | .notEqual => true
  | _ => false

/-- The primitive domain supported by recursive inference. This is a type
    specification, independent of successful native execution. -/
def scalarResult (operation : Surface.BinaryOp) (left right : Reference) : Option Reference :=
  match left, right with
  | .I32, .I32 => if integerAccepts operation then some (integerResult operation) else none
  | .Bool, .Bool => if booleanAccepts operation then some .Bool else none
  | _, _ => none

theorem scalarCases (accepted : scalarResult operation left right = some kind) :
    (left = .I32 ∧ right = .I32 ∧ integerAccepts operation = true ∧ kind = integerResult operation) ∨
    (left = .Bool ∧ right = .Bool ∧ booleanAccepts operation = true ∧ kind = .Bool) := by
  unfold scalarResult at accepted
  split at accepted
  · split at accepted <;> simp_all
  · split at accepted <;> simp_all
  · contradiction

theorem scalarValid (accepted : scalarResult operation left right = some kind) :
    isValid left = true ∧ isValid right = true ∧ isValidResult kind = true := by
  rcases scalarCases accepted with ⟨rfl, rfl, _, rfl⟩ | ⟨rfl, rfl, _, rfl⟩
  · refine ⟨rfl, rfl, ?_⟩
    unfold integerResult
    split <;> rfl
  · exact ⟨rfl, rfl, rfl⟩

theorem actualBoolean (site : Site) (operation : Surface.BinaryOp)
    (accepted : booleanAccepts operation = true) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before
      (site.call operation (known .Bool) (known .Bool)) (known .Bool) after ∧ PureFrame before after := by
  have boolean := fun {state : State} (h : state.CellsWellFormed) => actualKnown .Bool (by decide) h
  have validRun := fun {state : State} (h : state.CellsWellFormed) => actualValid .Bool h
  have selfSame := fun {state : State} (h : state.CellsWellFormed) => actualSame .Bool .Bool h
  have i32Same := fun {state : State} (h : state.CellsWellFormed) => actualSame .Bool .I32 h
  have usizeSame := fun {state : State} (h : state.CellsWellFormed) => actualSame .Bool .Usize h
  have comparisonRun := fun {state : State} (h : state.CellsWellFormed) => actualComparison operation h
  simp only [show isValid .Bool = true from rfl] at validRun
  simp only [show sameType .Bool .Bool = true from rfl] at selfSame
  simp only [show sameType .Bool .I32 = false from rfl] at i32Same
  simp only [show sameType .Bool .Usize = false from rfl] at usizeSame
  have andThen := equalOperation operation .logicalAnd
  have orElse := equalOperation operation .logicalOr
  have equal := equalOperation operation .equal
  have notEqual := equalOperation operation .notEqual
  core_call_pure decisionSource as callee
  iterate 2 (apply RunsStmt.letFramedPure; core_pure_expr; intro middle frame)
  iterate 2 (apply RunsStmt.guardFramedFalse; core_pure_guard; intro middle frame)
  by_cases logical : (is operation .logicalAnd || is operation .logicalOr) = true
  · apply RunsStmt.guardFramedTrue
    · simp
    · core_pure_guard
    · intro middle frame
      core_pure
  · have equality : (is operation .equal || is operation .notEqual) = true := by
      cases operation <;> simp only [booleanAccepts, Bool.false_eq_true] at accepted
      all_goals first | exact rfl | exact False.elim (logical rfl)
    apply RunsStmt.guardFramedFalse
    · core_pure_guard
    · intro middle frame
      iterate 2 (apply RunsStmt.letFramedPure; core_pure_expr; intro middle frame)
      apply RunsStmt.guardFramedTrue
      · simp
      · core_pure_guard
      · intro middle frame
        apply RunsStmt.guardFramedFalse
        · core_pure_guard
        · intro middle frame
          core_pure

/-- One decision contract serves both primitive operand domains. -/
theorem actualScalar (site : Site) (accepted : scalarResult operation left right = some kind)
    (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before
      (site.call operation (known left) (known right)) (known kind) after ∧ PureFrame before after := by
  rcases scalarCases accepted with ⟨rfl, rfl, integer, rfl⟩ | ⟨rfl, rfl, boolean, rfl⟩
  · simpa only [IntegerKind.reference, numericInteger operation integer] using actualNumeric site operation .i32 formed
  · exact actualBoolean site operation boolean formed

#print axioms actualBoolean
#print axioms actualScalar
#print axioms actualOperation
#print axioms actualComparison
#print axioms actualNumeric

end IRBinaryKindProof
