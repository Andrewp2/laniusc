import Lanius.FunctionalViewCoreStatefulReification
import Lanius.Extraction.CanonicalTokens.Pattern
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Reification

open Lanius Lanius.Core Lanius.Typing
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Stateful
open Lanius.FunctionalView.Stateful.Pattern
open Lanius.FunctionalView.Core.Stateful.Reification
open Lanius.Extraction.CanonicalTokens

private def program : Program := {}
private def layout : Layout 0 := Fin.elim0
private def i32 : Ty := .scalar (.signed .i32)
private def number (value : Int) : Expr := .value (.signed .i32 value)
private def boolean (value : Bool) : Expr := .value (.boolean value)

private def patternTerm (value : Int) : Term Core.signature 0 :=
  .reference (.literal (.signed .i32 value))

private def patternBinary (operation : BinaryOp) : Term Core.signature 0 :=
  .apply (.binary operation i32 i32 i32) [patternTerm 1, patternTerm 2]

private def supportedPatternCommand : Command Core.signature actions 0 :=
  .returnValue (some (patternTerm 7))

private def unsupportedPatternCommand : Command Core.signature actions 0 :=
  .returnValue (some (.reference (.literal (.array []))))

theorem pattern_matching_rejects_mismatches :
    (Pattern.termPattern (patternTerm 7)).matches (patternTerm 7) = true ∧
    (Pattern.termPattern (patternTerm 7)).matches (patternTerm 8) = false ∧
    (Pattern.termPattern (patternBinary .add)).matches (patternBinary .add) = true ∧
    (Pattern.termPattern (patternBinary .add)).matches (patternBinary .subtract) = false ∧
    (Pattern.commandPattern supportedPatternCommand).matches supportedPatternCommand = true ∧
    (Pattern.commandPattern unsupportedPatternCommand).matches unsupportedPatternCommand = false := by
  constructor
  · simp [Pattern.termPattern, patternTerm, TermPattern.matches, Exact.signed]
  constructor
  · simp [Pattern.termPattern, patternTerm, TermPattern.matches, Exact.signed]
  constructor
  · unfold Pattern.termPattern
    simp [Pattern.exactOp, Pattern.termPattern, patternBinary, patternTerm,
      TermPattern.matches, termPatternsMatch, Exact.signed,
      Exact.ofDecidableEq]
  constructor
  · unfold Pattern.termPattern
    simp [Pattern.exactOp, Pattern.termPattern, patternBinary, patternTerm,
      TermPattern.matches, termPatternsMatch, Exact.signed,
      Exact.ofDecidableEq]
  constructor
  · simp [Pattern.commandPattern, Pattern.termPattern,
      supportedPatternCommand, patternTerm, CommandPattern.matches,
      TermPattern.matches, Exact.signed]
  · simp [Pattern.commandPattern, Pattern.termPattern,
      unsupportedPatternCommand, CommandPattern.matches, TermPattern.matches,
      Exact.unit]

private def view? (result : Ty) (statement : Stmt) :=
  reifyCommand? program result Context.empty false layout 0 statement

private def typed? (result : Ty) (statement : Stmt) : Bool :=
  (CoreTyping.checkStmt program result Context.empty false statement).isSome

private def countedLoop : Stmt :=
  .letLocal 0 i32 (number 0)
    (.sequence
      (.whileLoop (.binary .less (.local 0) (number 3))
        (.ifThenElse (.binary .equal (.local 0) (number 2))
          .breakLoop
          (.expression (.assign .add (.local 0) (number 1)))))
      (.returnValue (some (.local 0))))

private def nestedBindings : Nat → Nat → Stmt
  | 0, _ => .ifThenElse (boolean true) (.returnValue none) .skip
  | depth + 1, next =>
      .letLocal next i32 (number 0)
        (.sequence .skip (nestedBindings depth (next + 1)))

private def fixtures : List (Ty × Stmt × Bool) := [
  (.unit, .skip, true),
  (.unit, .sequence .skip (.returnValue none), true),
  (i32, countedLoop, true),
  (.unit, nestedBindings 8 0, true),
  (.unit, .whileLoop (boolean true) .continueLoop, true),
  (.unit, .letLocal 0 i32 (boolean true) .skip, false),
  (.unit, .ifThenElse (number 0) .skip .skip, false),
  (.unit, .whileLoop (number 0) .skip, false),
  (.unit, .sequence .skip (.returnValue (some (number 0))), false),
  (i32, .letLocal 0 i32 (number 0) (.returnValue (some (.local 1))), false),
  (.unit, .sequence .skip .breakLoop, false),
  (.unit, .ifThenElse (boolean false) .skip .continueLoop, false)]

theorem accepted_and_rejected_typing :
    fixtures.all (fun (result, statement, accepted) =>
      (view? result statement).isSome == accepted &&
        typed? result statement == accepted) = true := by decide +kernel

/-- Core typing alone must not bypass the reifier's layout or syntax checks. -/
theorem structural_rejection :
    typed? .unit (.letLocal 1 i32 (number 0) .skip) = true ∧
    (view? .unit (.letLocal 1 i32 (number 0) .skip)).isSome = false ∧
    typed? .unit (.letUninitialized 0 i32 .skip) = true ∧
    (view? .unit (.letUninitialized 0 i32 .skip)).isSome = false := by decide +kernel

private def blockFixtures : List (Ty × Stmt × Bool) := [
  (.unit, .skip, true),
  (.unit, .sequence .skip (.returnValue none), true),
  (.unit, nestedBindings 8 0, true),
  (i32, .letLocal 0 i32 (number 3) (.returnValue (some (.local 0))), true),
  (.unit, .letLocal 0 i32 (boolean true) .skip, false),
  (.unit, .ifThenElse (number 0) .skip .skip, false),
  (.unit, .sequence .skip (.returnValue (some (number 0))), false),
  (i32, .letLocal 0 i32 (number 0) (.returnValue (some (.local 1))), false)]

theorem block_typing :
    blockFixtures.all (fun (result, statement, accepted) =>
      (Lanius.FunctionalView.Core.Reification.reifyBlock? program result
        Context.empty false layout 0 statement).isSome == accepted &&
        typed? result statement == accepted) = true := by decide +kernel

private def countedView := (view? i32 countedLoop).get (by decide +kernel)

theorem counted_loop_typed :
    StmtHasType program i32 Context.empty false countedLoop := countedView.coreTyped

theorem counted_loop_exact :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt
      Lanius.FunctionalView.Core.Stateful.actionAdapter layout 0
      countedView.command = countedLoop := countedView.toCoreExactly

private def expressionFixtures : List (Expr × Option Ty) := [
  (.cast (.signed .i64) (number 7), some (.scalar (.signed .i64))),
  (.cast .bool (number 7), none),
  (.unary .negate (number 1), some i32),
  (.unary .positive (boolean true), none),
  (.unary .logicalNot (boolean true), some (.scalar .bool)),
  (.unary .logicalNot (number 1), none),
  (.binary .add (number 1) (.binary .multiply (number 2) (number 3)), some i32),
  (.binary .less (number 1) (number 2), some (.scalar .bool)),
  (.binary .logicalAnd (boolean true) (.binary .less (number 1) (number 2)),
    some (.scalar .bool)),
  (.binary .logicalOr (.unary .logicalNot (boolean false)) (boolean true),
    some (.scalar .bool)),
  (.binary .logicalAnd (boolean true) (number 1), none),
  (.binary .logicalOr (number 1) (boolean false), none),
  (.unary .negate (boolean true), none),
  (.binary .add (number 1) (.value (.signed .i64 2)), none)]

/-- Child-proof reuse must preserve both valid expression types and rejection
    of bad operand combinations, agreeing with the independent Core checker. -/
theorem expression_typing :
    expressionFixtures.all (fun (expression, expected) =>
      ((Lanius.FunctionalView.Core.Reification.reifyTerm? program Context.empty
        layout expression).map (·.type) == expected) &&
      ((CoreTyping.inferExpr program Context.empty expression).map (·.type) ==
        expected)) = true := by decide +kernel

private def aggregateProgram : Program := {
  structures := [⟨0, [i32, .scalar .bool]⟩, ⟨1, []⟩]
  functions := [
    ⟨0, [(0, i32), (1, .scalar .bool)], .structure 0,
      some (.returnValue (some (.structValue 0 [.local 0, .local 1]))), none⟩,
    ⟨1, [], i32, some (.returnValue (some (number 3))), none⟩]
}

private def aggregateContext : Context :=
  (Context.empty.bind 0 (.array i32 2)).bind 1 (.slice i32)

private def aggregateLayout : Layout 2 := fun slot => slot.val

private def aggregateFixtures : List (Expr × Option Ty) := [
  (.structValue 0 [number 9, boolean true], some (.structure 0)),
  (.structValue 0 [number 9], none),
  (.structValue 0 [number 9, boolean true, number 0], none),
  (.structValue 0 [boolean true, number 9], none),
  (.structValue 1 [], some (.structure 1)),
  (.structValue 1 [number 9], none),
  (.structValue 2 [], none),
  (.call 0 [number 9, boolean true], some (.structure 0)),
  (.call 0 [], none),
  (.call 0 [boolean true, number 9], none),
  (.call 0 [number 9, boolean true, number 0], none),
  (.call 1 [], some i32),
  (.call 1 [number 9], none),
  (.call 2 [], none),
  (.call 0 [.binary .add (number 1) (number 2),
    .binary .less (number 1) (number 2)], some (.structure 0)),
  (.structValue 0 [.call 1 [], boolean false], some (.structure 0)),
  (.index (.local 0) (number 0), some i32),
  (.index (.local 1) (number 1), some i32),
  (.index (.local 0) (number (-1)), some i32),
  (.index (.local 1) (boolean true), none),
  (.index (number 0) (number 0), none),
  (.index (.local 2) (number 0), none),
  (.field (.structValue 0 [number 9, boolean true]) 0, some i32),
  (.field (.call 0 [number 9, boolean true]) 1, some (.scalar .bool)),
  (.field (.call 0 [number 9, boolean true]) 2, none),
  (.field (number 0) 0, none)]

theorem aggregate_typing :
    aggregateFixtures.all (fun (expression, expected) =>
      ((Lanius.FunctionalView.Core.Reification.reifyTerm? aggregateProgram
        aggregateContext aggregateLayout expression).map (·.type) == expected) &&
      ((CoreTyping.inferExpr aggregateProgram aggregateContext expression).map
        (·.type) == expected)) = true := by decide +kernel

/-- Argument automation must reuse a known constant declaration even when
    its identifier, value, source program, and surrounding locals are symbolic. -/
theorem symbolic_arguments (source : Program) (world : ReadOnly.World)
    (environment : Lanius.FunctionalView.Env arity) (slot : Fin arity)
    (id : ConstantId) (localValue constantValue : Value)
    (localFound : environment slot = localValue)
    (constantFound : source.constant? id = some ⟨id, i32, constantValue⟩) :
    Lanius.FunctionalView.evaluateTerms (ReadOnly.machine source) world environment
      [.reference (.slot slot), .apply (.constant id i32) []] =
      .ok ([localValue, constantValue], world) := by
  functional_eval

private def booleanTerm (value : Bool) : Term Core.signature 0 :=
  .reference (.literal (.boolean value))

private def failingTerm : Term Core.signature 0 :=
  .apply (.constant 0 i32) []

private def emptyEnvironment : Env 0 := fun index => Fin.elim0 index

private abbrev advancingMachine (result : Bool) : Machine Core.signature where
  World := Nat
  evalOperation := fun world _ _ => .ok (.boolean result, world + 1)

private def advancingTerm : Term Core.signature 0 :=
  .apply (.structValue 0 []) []

theorem guarded_and_evaluates_rhs_after_left :
    Term.evaluate (advancingMachine true) 0 emptyEnvironment
      (.logicalAnd advancingTerm (booleanTerm false)) =
      .ok (.boolean false, 1) := by
  apply Term.evaluate_logicalAnd_guarded
    (leftValue := true) (rightValue := false) (leftResult := by rfl)
  intro _
  rfl

theorem guarded_or_evaluates_rhs_after_left :
    Term.evaluate (advancingMachine false) 0 emptyEnvironment
      (.logicalOr advancingTerm (booleanTerm true)) =
      .ok (.boolean true, 1) := by
  apply Term.evaluate_logicalOr_guarded
    (leftValue := false) (rightValue := true) (leftResult := by rfl)
  intro _
  rfl

theorem functional_eval_logical_guards :
    (Term.evaluate (ReadOnly.machine program) (ReadOnly.World.singleton 0 [])
        emptyEnvironment (.logicalAnd (booleanTerm false) failingTerm) =
      .ok (.boolean false, ReadOnly.World.singleton 0 [])) ∧
    (Term.evaluate (ReadOnly.machine program) (ReadOnly.World.singleton 0 [])
        emptyEnvironment (.logicalOr (booleanTerm true) failingTerm) =
      .ok (.boolean true, ReadOnly.World.singleton 0 [])) ∧
    (Term.evaluate (ReadOnly.machine program) (ReadOnly.World.singleton 0 [])
        emptyEnvironment (.logicalAnd (booleanTerm true) (booleanTerm false)) =
      .ok (.boolean false, ReadOnly.World.singleton 0 [])) ∧
    (Term.evaluate (ReadOnly.machine program) (ReadOnly.World.singleton 0 [])
        emptyEnvironment (.logicalOr (booleanTerm false) (booleanTerm true)) =
      .ok (.boolean true, ReadOnly.World.singleton 0 [])) := by
  constructor
  · functional_eval
  constructor
  · functional_eval
  constructor <;> functional_eval

theorem functional_eval_symbolic_and
    (conditionTerm rightTerm : Term Core.signature 0)
    (world : ReadOnly.World) (environment : Env 0) (leftValue rightValue : Bool)
    (leftEval : Term.evaluate (ReadOnly.machine program) world environment conditionTerm =
      .ok (.boolean leftValue, world))
    (rightEval : leftValue = true →
      Term.evaluate (ReadOnly.machine program) world environment rightTerm =
        .ok (.boolean rightValue, world)) :
    Term.evaluate (ReadOnly.machine program) world environment
        (.logicalAnd conditionTerm rightTerm) =
      .ok (.boolean (leftValue && rightValue), world) := by
  functional_eval

theorem functional_eval_symbolic_or
    (conditionTerm rightTerm : Term Core.signature 0)
    (world : ReadOnly.World) (environment : Env 0) (leftValue rightValue : Bool)
    (leftEval : Term.evaluate (ReadOnly.machine program) world environment conditionTerm =
      .ok (.boolean leftValue, world))
    (rightEval : leftValue = false →
      Term.evaluate (ReadOnly.machine program) world environment rightTerm =
        .ok (.boolean rightValue, world)) :
    Term.evaluate (ReadOnly.machine program) world environment
        (.logicalOr conditionTerm rightTerm) =
      .ok (.boolean (leftValue || rightValue), world) := by
  functional_eval

theorem guarded_rejects_failing_or_wrong_rhs :
    (¬ Term.evaluate (ReadOnly.machine program)
        (ReadOnly.World.singleton 0 []) emptyEnvironment
        (.logicalAnd (booleanTerm true) failingTerm) =
      .ok (.boolean true, ReadOnly.World.singleton 0 [])) ∧
    (¬ Term.evaluate (advancingMachine false) 0 emptyEnvironment
        (.logicalAnd (booleanTerm true) advancingTerm) =
      .ok (.boolean true, 1)) := by
  constructor
  · intro evaluated
    change (Except.error Trap.invalidPointer :
      Except Trap (Value × ReadOnly.World)) =
      .ok (.boolean true, ReadOnly.World.singleton 0 []) at evaluated
    cases evaluated
  · intro evaluated
    change (Except.ok (.boolean false, 1) : Except Trap (Value × Nat)) =
      .ok (.boolean true, 1) at evaluated
    cases evaluated

run_elab do
  for name in #[``accepted_and_rejected_typing, ``structural_rejection,
      ``block_typing, ``counted_loop_typed, ``counted_loop_exact, ``expression_typing,
      ``aggregate_typing, ``pattern_matching_rejects_mismatches,
      ``Lanius.FunctionalView.Core.Reification.reifyTerm?,
      ``Lanius.FunctionalView.Core.Reification.reifyTerms?,
      ``Lanius.FunctionalView.Core.Reification.reifyBlock?,
      ``reifyCommand?, ``symbolic_arguments,
      ``guarded_and_evaluates_rhs_after_left,
      ``guarded_or_evaluates_rhs_after_left,
      ``functional_eval_logical_guards,
      ``functional_eval_symbolic_and, ``functional_eval_symbolic_or,
      ``guarded_rejects_failing_or_wrong_rhs] do
    for assumption in ← Lean.collectAxioms name do
      unless #[``propext, ``Classical.choice, ``Quot.sound].contains assumption do
        throwError "Reification proof {name} adds unexpected axiom {assumption}"

end Lanius.Extraction.Tests.Reification
