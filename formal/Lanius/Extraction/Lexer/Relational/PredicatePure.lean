import Lanius.Extraction.Lexer.Relational.PredicateSyntax
import Lanius.Extraction.Lexer.Predicates
import Lanius.Relational.LeafMigration

namespace Lanius.Extraction.Lexer.Relational.PredicatePure

open Lanius
open Lanius.Core
open Lanius.Semantics
open Lanius.Separation
open Lanius.Compiler.Lexer
open Lanius.Compiler.Lexer.Program
open Lanius.Extraction
open Lanius.Extraction.Lexer
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly
open Lanius.FunctionalView.Core.Effectful
open Lanius.FunctionalView.FreshSimulation
open Lanius.Relational
open Lanius.Relational.Semantics

def rejectingCalls : CallModel where
  evaluate := fun _ _ _ => .error .invalidPointer

def registry : OperationRegistry :=
  OperationRegistry.readOnly (fun _ _ _ _ _ => False)

theorem rejectingCalls_sound :
    FramePreservingCallSoundness checkedFrontend.core rejectingCalls := by
  constructor
  intro arity layout localCell beforeWorld afterWorld environment before
    afterArguments function arguments values result argumentWrites
    afterArgumentsWellFormed represented argumentsExecution argumentsEffect
    evaluated
  simp [rejectingCalls] at evaluated

theorem operationsAgree :
    ExecutableRefinement.OperationsAgree checkedFrontend.core rejectingCalls
      registry := by
  constructor
  intro world operation arguments value afterWorld evaluated
  cases operation with
  | binary operation left right output =>
      cases operation <;>
        simp_all [registry, OperationRegistry.readOnly,
          Effectful.evaluateOperation, rejectingCalls]
  | call function inputs output =>
      simp [Effectful.evaluateOperation, rejectingCalls] at evaluated
  | _ =>
      exact evaluated

theorem operationsReflect :
    ExecutableRefinement.OperationsReflect checkedFrontend.core rejectingCalls
      registry := by
  constructor
  intro world operation arguments value afterWorld free related
  cases operation with
  | binary operation left right output =>
      cases operation <;>
        simp_all [Effectful.operationCallFree, registry,
          OperationRegistry.readOnly, Effectful.evaluateOperation,
          rejectingCalls]
  | call function inputs output =>
      simp [Effectful.operationCallFree] at free
  | _ =>
      exact related

def Admissible (world : ReadOnly.World) (environment : Env 1) : Prop :=
  ∃ byte : Byte, environment = PredicateSyntax.environment byte

private theorem greaterEqual_evaluates
    (world : ReadOnly.World) (byte : Byte) (bound : Nat) :
    FunctionalView.Term.evaluate (ReadOnly.machine checkedFrontend.core) world
      (PredicateSyntax.environment byte)
      (PredicateSyntax.comparison .greaterEqual PredicateSyntax.argument
        (PredicateSyntax.literal (Int.ofNat bound))) =
      .ok (.boolean (decide (bound ≤ byte.val)), world) := by
  exact Term.evaluate_i32_greaterEqual (by rfl) (by rfl)

private theorem lessEqual_evaluates
    (world : ReadOnly.World) (byte : Byte) (bound : Nat) :
    FunctionalView.Term.evaluate (ReadOnly.machine checkedFrontend.core) world
      (PredicateSyntax.environment byte)
      (PredicateSyntax.comparison .lessEqual PredicateSyntax.argument
        (PredicateSyntax.literal (Int.ofNat bound))) =
      .ok (.boolean
        (decide (Int.ofNat byte.val ≤ Int.ofNat bound)), world) := by
  exact Term.evaluate_i32_lessEqual_int (by rfl) (by rfl)

private theorem equal_evaluates
    (world : ReadOnly.World) (byte : Byte) (bound : Nat) :
    FunctionalView.Term.evaluate (ReadOnly.machine checkedFrontend.core) world
      (PredicateSyntax.environment byte)
      (PredicateSyntax.comparison .equal PredicateSyntax.argument
        (PredicateSyntax.literal (Int.ofNat bound))) =
      .ok (.boolean (decide (byte.val = bound)), world) := by
  exact Term.evaluate_i32_equal (by rfl) (by rfl)

private theorem identifierStart_computed : ∀ byte : Byte,
    (((decide (97 ≤ byte.val) &&
        decide (Int.ofNat byte.val ≤ Int.ofNat 122)) ||
      (decide (65 ≤ byte.val) &&
        decide (Int.ofNat byte.val ≤ Int.ofNat 90))) ||
      decide (byte.val = 95)) = isIdentifierStart byte := by
  decide +kernel

private theorem decimalDigit_computed : ∀ byte : Byte,
    (decide (48 ≤ byte.val) &&
      decide (Int.ofNat byte.val ≤ Int.ofNat 57)) =
      isDecimalDigit byte := by
  decide +kernel

private theorem whitespace_computed : ∀ byte : Byte,
    (((decide (byte.val = 32) || decide (byte.val = 9)) ||
      decide (byte.val = 10)) || decide (byte.val = 13)) =
      isWhitespace byte := by
  decide +kernel

theorem identifierStart_evaluates
    (world : ReadOnly.World) (byte : Byte) :
    FunctionalView.Term.evaluate (ReadOnly.machine checkedFrontend.core) world
      (PredicateSyntax.environment byte) PredicateSyntax.identifierStartTerm =
      .ok (.boolean (isIdentifierStart byte), world) := by
  let computed :=
    ((decide (97 ≤ byte.val) &&
        decide (Int.ofNat byte.val ≤ Int.ofNat 122)) ||
      (decide (65 ≤ byte.val) &&
        decide (Int.ofNat byte.val ≤ Int.ofNat 90))) ||
      decide (byte.val = 95)
  have evaluated : FunctionalView.Term.evaluate
      (ReadOnly.machine checkedFrontend.core) world
      (PredicateSyntax.environment byte) PredicateSyntax.identifierStartTerm =
      .ok (.boolean computed, world) := by
    unfold PredicateSyntax.identifierStartTerm
    apply Term.evaluate_logicalOr_bool
    · apply Term.evaluate_logicalOr_bool
      · apply Term.evaluate_logicalAnd_bool
        · exact greaterEqual_evaluates world byte 97
        · exact lessEqual_evaluates world byte 122
      · apply Term.evaluate_logicalAnd_bool
        · exact greaterEqual_evaluates world byte 65
        · exact lessEqual_evaluates world byte 90
    · exact equal_evaluates world byte 95
  have same : computed = isIdentifierStart byte := identifierStart_computed byte
  simpa [same] using evaluated

theorem decimalDigit_evaluates
    (world : ReadOnly.World) (byte : Byte) :
    FunctionalView.Term.evaluate (ReadOnly.machine checkedFrontend.core) world
      (PredicateSyntax.environment byte) PredicateSyntax.decimalDigitTerm =
      .ok (.boolean (isDecimalDigit byte), world) := by
  let computed := decide (48 ≤ byte.val) &&
    decide (Int.ofNat byte.val ≤ Int.ofNat 57)
  have evaluated : FunctionalView.Term.evaluate
      (ReadOnly.machine checkedFrontend.core) world
      (PredicateSyntax.environment byte) PredicateSyntax.decimalDigitTerm =
      .ok (.boolean computed, world) := by
    unfold PredicateSyntax.decimalDigitTerm
    apply Term.evaluate_logicalAnd_bool
    · exact greaterEqual_evaluates world byte 48
    · exact lessEqual_evaluates world byte 57
  have same : computed = isDecimalDigit byte := decimalDigit_computed byte
  simpa [same] using evaluated

theorem whitespace_evaluates
    (world : ReadOnly.World) (byte : Byte) :
    FunctionalView.Term.evaluate (ReadOnly.machine checkedFrontend.core) world
      (PredicateSyntax.environment byte) PredicateSyntax.whitespaceTerm =
      .ok (.boolean (isWhitespace byte), world) := by
  let computed :=
    (((decide (byte.val = 32) || decide (byte.val = 9)) ||
      decide (byte.val = 10)) || decide (byte.val = 13))
  have evaluated : FunctionalView.Term.evaluate
      (ReadOnly.machine checkedFrontend.core) world
      (PredicateSyntax.environment byte) PredicateSyntax.whitespaceTerm =
      .ok (.boolean computed, world) := by
    unfold PredicateSyntax.whitespaceTerm
    apply Term.evaluate_logicalOr_bool
    · apply Term.evaluate_logicalOr_bool
      · apply Term.evaluate_logicalOr_bool
        · exact equal_evaluates world byte 32
        · exact equal_evaluates world byte 9
      · exact equal_evaluates world byte 10
    · exact equal_evaluates world byte 13
  have same : computed = isWhitespace byte := whitespace_computed byte
  simpa [same] using evaluated

theorem reflects
    (term : PredicateSyntax.T) (accept : Byte → Bool)
    (free : Effectful.termCallFree term = true)
    (evaluates : ∀ world byte,
      FunctionalView.Term.evaluate (ReadOnly.machine checkedFrontend.core)
        world (PredicateSyntax.environment byte) term =
        .ok (.boolean (accept byte), world)) :
    CoreReflection.TermReflectsWhen checkedFrontend.core registry Admissible
      term := by
  apply LeafMigration.termReflectsWhenOfAgreement
    (FreshSimulation.operationSoundness checkedFrontend.core rejectingCalls
      rejectingCalls_sound) operationsAgree
  intro world environment input
  obtain ⟨byte, rfl⟩ := input
  refine ⟨.boolean (accept byte), world, ?_⟩
  exact (Effectful.Term.evaluate_eq_readOnly_of_callFree term free).trans
    (evaluates world byte)

theorem term_wp
    (term : PredicateSyntax.T) (accept : Byte → Bool)
    (free : Effectful.termCallFree term = true)
    (evaluates : ∀ world byte,
      FunctionalView.Term.evaluate (ReadOnly.machine checkedFrontend.core)
        world (PredicateSyntax.environment byte) term =
        .ok (.boolean (accept byte), world))
    (world : (Effectful.machine checkedFrontend.core rejectingCalls).World)
    (byte : Byte) :
    SemanticWP.Term.WP (registry.machine checkedFrontend.core) term
      (fun value afterWorld =>
        value = .boolean (accept byte) ∧ afterWorld = world)
      world (PredicateSyntax.environment byte) := by
  intro value afterWorld relational
  have executable := ExecutableRefinement.termToExecutable operationsReflect
    free relational
  have canonical : FunctionalView.Term.evaluate
      (Effectful.machine checkedFrontend.core rejectingCalls) world
      (PredicateSyntax.environment byte) term =
      .ok (.boolean (accept byte), world) := by
    exact (Effectful.Term.evaluate_eq_readOnly_of_callFree term free).trans
      (evaluates world byte)
  have same := executable.symm.trans canonical
  injection same with pairEq
  exact ⟨congrArg Prod.fst pairEq, congrArg Prod.snd pairEq⟩

end Lanius.Extraction.Lexer.Relational.PredicatePure
