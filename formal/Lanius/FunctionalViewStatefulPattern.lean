import Lanius.FunctionalViewStatefulAcyclic

namespace Lanius.FunctionalView.Stateful.Pattern

open Lanius
open Lanius.Core
open Lanius.FunctionalView
open Lanius.FunctionalView.Stateful

/-! # Exact constructor patterns

FunctionalView commands contain `Core.Value`, whose nested recursive shape does
not admit Lean's generated `DecidableEq`.  Proofs nevertheless need to expose
large mechanically recovered commands as small readable definitions.  This
module compares their constructors directly and carries a proof for each leaf
recognizer, so a successful executable match reconstructs an actual equality.
-/

/-- An executable recognizer for one exact value of an arbitrary leaf type. -/
structure Exact (α : Type) where
  value : α
  accepts : α → Bool
  sound : ∀ candidate, accepts candidate = true → candidate = value

def Exact.ofDecidableEq [DecidableEq α] (value : α) : Exact α where
  value := value
  accepts := fun candidate => decide (candidate = value)
  sound := fun _ accepted => of_decide_eq_true accepted

def Exact.unit : Exact Value where
  value := .unit
  accepts
    | .unit => true
    | _ => false
  sound := by intro candidate accepted; cases candidate <;> simp_all

def Exact.boolean (expected : Bool) : Exact Value where
  value := .boolean expected
  accepts
    | .boolean candidate => decide (candidate = expected)
    | _ => false
  sound := by
    intro candidate accepted
    cases candidate <;> simp_all

def Exact.signed (type : SignedIntTy) (expected : Int) : Exact Value where
  value := .signed type expected
  accepts
    | .signed candidateType candidate =>
        decide (candidateType = type ∧ candidate = expected)
    | _ => false
  sound := by
    intro candidate accepted
    cases candidate <;> simp_all

def Exact.unsigned (type : UnsignedIntTy) (expected : Nat) : Exact Value where
  value := .unsigned type expected
  accepts
    | .unsigned candidateType candidate =>
        decide (candidateType = type ∧ candidate = expected)
    | _ => false
  sound := by
    intro candidate accepted
    cases candidate <;> simp_all

def Exact.f32Bits (expected : UInt32) : Exact Value where
  value := .f32Bits expected
  accepts
    | .f32Bits candidate => decide (candidate = expected)
    | _ => false
  sound := by
    intro candidate accepted
    cases candidate <;> simp_all

def Exact.f64Bits (expected : UInt64) : Exact Value where
  value := .f64Bits expected
  accepts
    | .f64Bits candidate => decide (candidate = expected)
    | _ => false
  sound := by
    intro candidate accepted
    cases candidate <;> simp_all

def Exact.character (expected : UInt32) : Exact Value where
  value := .character expected
  accepts
    | .character candidate => decide (candidate = expected)
    | _ => false
  sound := by
    intro candidate accepted
    cases candidate <;> simp_all

def Exact.string (expected : String) : Exact Value where
  value := .string expected
  accepts
    | .string candidate => decide (candidate = expected)
    | _ => false
  sound := by
    intro candidate accepted
    cases candidate <;> simp_all

def Exact.pointer (expected : Address) : Exact Value where
  value := .pointer expected
  accepts
    | .pointer candidate => decide (candidate = expected)
    | _ => false
  sound := by
    intro candidate accepted
    cases candidate <;> simp_all

/-- Readable exact syntax for FunctionalView terms.  Operations remain
dialect-parametric: a client supplies the small exact recognizer appropriate
to its operation type. -/
inductive TermPattern (signature : Signature) (arity : Nat) where
  | slot (index : Fin arity)
  | literal (value : Exact Value)
  | apply (operation : Exact signature.Op)
      (arguments : List (TermPattern signature arity))
  | logicalAnd (left right : TermPattern signature arity)
  | logicalOr (left right : TermPattern signature arity)

def TermPattern.denote :
    TermPattern signature arity → Term signature arity
  | .slot index => .reference (.slot index)
  | .literal value => .reference (.literal value.value)
  | .apply operation arguments =>
      .apply operation.value (arguments.map TermPattern.denote)
  | .logicalAnd left right => .logicalAnd left.denote right.denote
  | .logicalOr left right => .logicalOr left.denote right.denote

mutual

  def TermPattern.matches :
      TermPattern signature arity → Term signature arity → Bool
    | .slot expected, .reference (.slot candidate) =>
        decide (candidate = expected)
    | .literal expected, .reference (.literal candidate) =>
        expected.accepts candidate
    | .apply expectedOperation expectedArguments,
        .apply candidateOperation candidateArguments =>
      expectedOperation.accepts candidateOperation &&
        termPatternsMatch expectedArguments candidateArguments
    | .logicalAnd expectedLeft expectedRight,
        .logicalAnd candidateLeft candidateRight =>
      expectedLeft.matches candidateLeft && expectedRight.matches candidateRight
    | .logicalOr expectedLeft expectedRight,
        .logicalOr candidateLeft candidateRight =>
      expectedLeft.matches candidateLeft && expectedRight.matches candidateRight
    | _, _ => false

  def termPatternsMatch :
      List (TermPattern signature arity) → List (Term signature arity) → Bool
    | [], [] => true
    | expected :: expectedTail, candidate :: candidateTail =>
        expected.matches candidate &&
          termPatternsMatch expectedTail candidateTail
    | _, _ => false

end

mutual

  theorem TermPattern.matches_sound
      {pattern : TermPattern signature arity}
      {candidate : Term signature arity}
      (accepted : pattern.matches candidate = true) :
      candidate = pattern.denote := by
    cases pattern with
    | slot expected =>
        cases candidate with
        | reference reference =>
            cases reference with
            | slot candidate =>
                simp only [TermPattern.matches, decide_eq_true_eq] at accepted
                subst candidate
                simp only [TermPattern.denote]
            | literal => simp [TermPattern.matches] at accepted
        | apply | logicalAnd | logicalOr =>
            simp [TermPattern.matches] at accepted
    | literal expected =>
        cases candidate with
        | reference reference =>
            cases reference with
            | slot => simp [TermPattern.matches] at accepted
            | literal candidate =>
                simp only [TermPattern.matches] at accepted
                simp only [TermPattern.denote]
                rw [expected.sound _ accepted]
        | apply | logicalAnd | logicalOr =>
            simp [TermPattern.matches] at accepted
    | apply expectedOperation expectedArguments =>
        cases candidate with
        | apply candidateOperation candidateArguments =>
            simp only [TermPattern.matches, Bool.and_eq_true] at accepted
            simp only [TermPattern.denote]
            rw [expectedOperation.sound _ accepted.1,
              termPatternsMatch_sound accepted.2]
        | reference | logicalAnd | logicalOr =>
            simp [TermPattern.matches] at accepted
    | logicalAnd expectedLeft expectedRight =>
        cases candidate with
        | logicalAnd candidateLeft candidateRight =>
            simp only [TermPattern.matches, Bool.and_eq_true] at accepted
            simp only [TermPattern.denote]
            rw [expectedLeft.matches_sound accepted.1,
              expectedRight.matches_sound accepted.2]
        | reference | apply | logicalOr =>
            simp [TermPattern.matches] at accepted
    | logicalOr expectedLeft expectedRight =>
        cases candidate with
        | logicalOr candidateLeft candidateRight =>
            simp only [TermPattern.matches, Bool.and_eq_true] at accepted
            simp only [TermPattern.denote]
            rw [expectedLeft.matches_sound accepted.1,
              expectedRight.matches_sound accepted.2]
        | reference | apply | logicalAnd =>
            simp [TermPattern.matches] at accepted

  theorem termPatternsMatch_sound
      {patterns : List (TermPattern signature arity)}
      {candidates : List (Term signature arity)}
      (accepted : termPatternsMatch patterns candidates = true) :
      candidates = patterns.map TermPattern.denote := by
    cases patterns <;> cases candidates <;>
      simp only [termPatternsMatch] at accepted
    case nil.nil => rfl
    case cons.cons pattern patterns candidate candidates =>
      simp only [Bool.and_eq_true] at accepted
      simp only [List.map_cons]
      rw [pattern.matches_sound accepted.1,
        termPatternsMatch_sound accepted.2]
    all_goals contradiction

end

/-- Readable exact syntax for dependent stateful commands. -/
inductive CommandPattern (signature : Signature)
    (actions : ActionSignature signature) : Nat → Type where
  | skip {arity : Nat} : CommandPattern signature actions arity
  | sequence {arity : Nat}
      (first second : CommandPattern signature actions arity) :
      CommandPattern signature actions arity
  | letValue {arity : Nat} (type : Ty)
      (initializer : TermPattern signature arity)
      (body : CommandPattern signature actions (arity + 1)) :
      CommandPattern signature actions arity
  | setLocal {arity : Nat} (target : Fin arity)
      (value : TermPattern signature arity) :
      CommandPattern signature actions arity
  | updateLocal {arity : Nat} (operation : AssignOp) (target : Fin arity)
      (value : TermPattern signature arity) :
      CommandPattern signature actions arity
  | action {arity : Nat} (operation : Exact (actions.Action arity)) :
      CommandPattern signature actions arity
  | ifThenElse {arity : Nat} (condition : TermPattern signature arity)
      (thenBranch elseBranch : CommandPattern signature actions arity) :
      CommandPattern signature actions arity
  | whileLoop {arity : Nat} (condition : TermPattern signature arity)
      (body : CommandPattern signature actions arity) :
      CommandPattern signature actions arity
  | returnValue {arity : Nat} (value : Option (TermPattern signature arity)) :
      CommandPattern signature actions arity
  | breakLoop {arity : Nat} : CommandPattern signature actions arity
  | continueLoop {arity : Nat} : CommandPattern signature actions arity

def CommandPattern.denote :
    CommandPattern signature actions arity → Command signature actions arity
  | .skip => .skip
  | .sequence first second => .sequence first.denote second.denote
  | .letValue type initializer body =>
      .letValue type initializer.denote body.denote
  | .setLocal target value => .setLocal target value.denote
  | .updateLocal operation target value =>
      .updateLocal operation target value.denote
  | .action operation => .action operation.value
  | .ifThenElse condition thenBranch elseBranch =>
      .ifThenElse condition.denote thenBranch.denote elseBranch.denote
  | .whileLoop condition body => .whileLoop condition.denote body.denote
  | .returnValue value => .returnValue (value.map TermPattern.denote)
  | .breakLoop => .breakLoop
  | .continueLoop => .continueLoop

def CommandPattern.matches :
    CommandPattern signature actions arity →
      Command signature actions arity → Bool
  | .skip, .skip => true
  | .sequence expectedFirst expectedSecond,
      .sequence candidateFirst candidateSecond =>
    expectedFirst.matches candidateFirst &&
      expectedSecond.matches candidateSecond
  | .letValue expectedType expectedInitializer expectedBody,
      .letValue candidateType candidateInitializer candidateBody =>
    decide (candidateType = expectedType) &&
      expectedInitializer.matches candidateInitializer &&
      expectedBody.matches candidateBody
  | .setLocal expectedTarget expectedValue,
      .setLocal candidateTarget candidateValue =>
    decide (candidateTarget = expectedTarget) &&
      expectedValue.matches candidateValue
  | .updateLocal expectedOperation expectedTarget expectedValue,
      .updateLocal candidateOperation candidateTarget candidateValue =>
    decide (candidateOperation = expectedOperation) &&
      decide (candidateTarget = expectedTarget) &&
      expectedValue.matches candidateValue
  | .action expected, .action candidate => expected.accepts candidate
  | .ifThenElse expectedCondition expectedThen expectedElse,
      .ifThenElse candidateCondition candidateThen candidateElse =>
    expectedCondition.matches candidateCondition &&
      expectedThen.matches candidateThen && expectedElse.matches candidateElse
  | .whileLoop expectedCondition expectedBody,
      .whileLoop candidateCondition candidateBody =>
    expectedCondition.matches candidateCondition &&
      expectedBody.matches candidateBody
  | .returnValue none, .returnValue none => true
  | .returnValue (some expected), .returnValue (some candidate) =>
      expected.matches candidate
  | .breakLoop, .breakLoop => true
  | .continueLoop, .continueLoop => true
  | _, _ => false

theorem CommandPattern.matches_sound
    {pattern : CommandPattern signature actions arity}
    {candidate : Command signature actions arity}
    (accepted : pattern.matches candidate = true) :
    candidate = pattern.denote := by
  induction pattern with
  | skip =>
      cases candidate <;>
        simp only [CommandPattern.matches, Bool.false_eq_true] at accepted
      simp only [CommandPattern.denote]
  | sequence first second firstIH secondIH =>
      cases candidate with
      | sequence candidateFirst candidateSecond =>
          simp only [CommandPattern.matches, Bool.and_eq_true] at accepted
          simp only [CommandPattern.denote]
          rw [firstIH accepted.1, secondIH accepted.2]
      | _ => simp [CommandPattern.matches] at accepted
  | letValue type initializer body bodyIH =>
      cases candidate with
      | letValue candidateType candidateInitializer candidateBody =>
          simp only [CommandPattern.matches, Bool.and_eq_true,
            decide_eq_true_eq] at accepted
          simp only [CommandPattern.denote]
          obtain ⟨⟨rfl, initializerAccepted⟩, bodyAccepted⟩ := accepted
          rw [initializer.matches_sound initializerAccepted,
            bodyIH bodyAccepted]
      | _ => simp [CommandPattern.matches] at accepted
  | setLocal target value =>
      cases candidate with
      | setLocal candidateTarget candidateValue =>
          simp only [CommandPattern.matches, Bool.and_eq_true,
            decide_eq_true_eq] at accepted
          simp only [CommandPattern.denote]
          rw [accepted.1, value.matches_sound accepted.2]
      | _ => simp [CommandPattern.matches] at accepted
  | updateLocal operation target value =>
      cases candidate with
      | updateLocal candidateOperation candidateTarget candidateValue =>
          simp only [CommandPattern.matches, Bool.and_eq_true,
            decide_eq_true_eq] at accepted
          simp only [CommandPattern.denote]
          obtain ⟨⟨rfl, rfl⟩, valueAccepted⟩ := accepted
          rw [value.matches_sound valueAccepted]
      | _ => simp [CommandPattern.matches] at accepted
  | action operation =>
      cases candidate with
      | action candidateOperation =>
          simp only [CommandPattern.matches, CommandPattern.denote] at accepted ⊢
          rw [operation.sound _ accepted]
      | _ => simp [CommandPattern.matches] at accepted
  | ifThenElse condition thenBranch elseBranch thenIH elseIH =>
      cases candidate with
      | ifThenElse candidateCondition candidateThen candidateElse =>
          simp only [CommandPattern.matches, Bool.and_eq_true] at accepted
          simp only [CommandPattern.denote]
          obtain ⟨⟨conditionAccepted, thenAccepted⟩, elseAccepted⟩ := accepted
          rw [condition.matches_sound conditionAccepted, thenIH thenAccepted,
            elseIH elseAccepted]
      | _ => simp [CommandPattern.matches] at accepted
  | whileLoop condition body bodyIH =>
      cases candidate with
      | whileLoop candidateCondition candidateBody =>
          simp only [CommandPattern.matches, Bool.and_eq_true] at accepted
          simp only [CommandPattern.denote]
          rw [condition.matches_sound accepted.1, bodyIH accepted.2]
      | _ => simp [CommandPattern.matches] at accepted
  | returnValue value =>
      cases candidate with
      | returnValue candidateValue =>
          cases value with
          | none =>
              cases candidateValue with
              | none => simp only [CommandPattern.denote, Option.map]
              | some => simp [CommandPattern.matches] at accepted
          | some expected =>
              cases candidateValue with
              | none => simp [CommandPattern.matches] at accepted
              | some candidate =>
                  simp only [CommandPattern.matches] at accepted
                  simp only [CommandPattern.denote, Option.map]
                  rw [expected.matches_sound accepted]
      | _ => simp [CommandPattern.matches] at accepted
  | breakLoop =>
      cases candidate <;>
        simp only [CommandPattern.matches, Bool.false_eq_true] at accepted
      simp only [CommandPattern.denote]
  | continueLoop =>
      cases candidate <;>
        simp only [CommandPattern.matches, Bool.false_eq_true] at accepted
      simp only [CommandPattern.denote]

/-- A successful executable pattern check exposes the recovered command as
the pattern's readable denotation. -/
theorem exact_of_matches
    {pattern : CommandPattern signature actions arity}
    {candidate : Command signature actions arity}
    (accepted : pattern.matches candidate = true) :
    candidate = pattern.denote :=
  pattern.matches_sound accepted

end Lanius.FunctionalView.Stateful.Pattern
