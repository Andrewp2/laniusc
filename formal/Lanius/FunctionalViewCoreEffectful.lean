import Lanius.FunctionalViewCoreEffectfulSimulation

namespace Lanius.FunctionalView.Core.Effectful

open Lanius
open Lanius.Core
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.CallContracts
open Lanius.FunctionalView
open Lanius.FunctionalView.Core

/-! # Core calls as FunctionalView operations

A call model gives source functions mathematical, store-passing semantics.
`CallSoundness` is the checked boundary: every successful modeled call must
execute the corresponding structural-Core call while preserving the active
FunctionalView representation and local environment.  The model is useful
for reasoning only after that obligation has been discharged.
-/

structure CallModel where
  evaluate : ReadOnly.World → FunctionId → List Value →
    Except Trap (Value × ReadOnly.World)

/-- Compose two source-call registries with an explicit function-ID router.
    This keeps parser-specific dispatch policy outside the generic evaluator
    while allowing independently proved call models to form one machine. -/
def CallModel.route (selectFirst : FunctionId → Bool)
    (first second : CallModel) : CallModel where
  evaluate := fun world function arguments =>
    if selectFirst function then
      first.evaluate world function arguments
    else
      second.evaluate world function arguments

def evaluateOperation (program : Program) (calls : CallModel)
    (world : ReadOnly.World) :
    Operation → List Value → Except Trap (Value × ReadOnly.World)
  | .binary .logicalAnd _ _ _, _ => .error .typeMismatch
  | .binary .logicalOr _ _ _, _ => .error .typeMismatch
  | .call function _ _, arguments => calls.evaluate world function arguments
  | operation, arguments =>
      ReadOnly.evaluateOperation program world operation arguments

def machine (program : Program) (calls : CallModel) :
    Machine Core.signature := {
  World := ReadOnly.World
  evalOperation := evaluateOperation program calls
}

/-! ## Call-free compatibility

The effectful evaluator differs from the read-only evaluator at exactly one
operation constructor: source calls.  Keeping that fact as a structural
theorem lets mixed parser commands reuse all read-only arithmetic and slice
lemmas for their call-free subterms instead of unfolding either evaluator.
-/

def operationCallFree : Operation → Bool
  | .call _ _ _ => false
  | .binary .logicalAnd _ _ _ => false
  | .binary .logicalOr _ _ _ => false
  | _ => true

mutual
  def termCallFree : Term Core.signature arity → Bool
    | .reference _ => true
    | .apply operation arguments =>
        operationCallFree operation && termsCallFree arguments
    | .logicalAnd left right | .logicalOr left right =>
        termCallFree left && termCallFree right

  def termsCallFree : List (Term Core.signature arity) → Bool
    | [] => true
    | term :: terms => termCallFree term && termsCallFree terms
end

theorem evaluateOperation_eq_readOnly_of_callFree
    (free : operationCallFree operation = true) :
    evaluateOperation program calls world operation arguments =
      ReadOnly.evaluateOperation program world operation arguments := by
  cases operation <;> simp_all [operationCallFree, evaluateOperation]
  case binary operation _ _ _ =>
    cases operation <;> simp_all [operationCallFree, evaluateOperation]

mutual
  theorem term_evaluate_eq_readOnly_of_callFree
      (term : Term Core.signature arity) (free : termCallFree term = true) :
      Term.evaluate (machine program calls) world environment term =
        Term.evaluate (ReadOnly.machine program) world environment term := by
    cases term with
    | reference reference => rfl
    | apply operation arguments =>
        have components : operationCallFree operation = true ∧
            termsCallFree arguments = true := by
          simpa only [termCallFree, Bool.and_eq_true] using free
        simp only [Term.evaluate]
        rw [terms_evaluate_eq_readOnly_of_callFree arguments components.2]
        apply bind_congr
        intro result
        exact evaluateOperation_eq_readOnly_of_callFree components.1
    | logicalAnd left right =>
        have components : termCallFree left = true ∧
            termCallFree right = true := by
          simpa only [termCallFree, Bool.and_eq_true] using free
        have rightEq : ∀ nextWorld,
            Term.evaluate (machine program calls) nextWorld environment right =
              Term.evaluate (ReadOnly.machine program) nextWorld environment
                right := fun nextWorld =>
          term_evaluate_eq_readOnly_of_callFree right components.2
        simp only [Term.evaluate]
        rw [term_evaluate_eq_readOnly_of_callFree left components.1]
        apply bind_congr
        intro result
        obtain ⟨value, nextWorld⟩ := result
        cases value <;> try rfl
        case boolean value =>
          cases value
          · rfl
          · exact rightEq nextWorld
    | logicalOr left right =>
        have components : termCallFree left = true ∧
            termCallFree right = true := by
          simpa only [termCallFree, Bool.and_eq_true] using free
        have rightEq : ∀ nextWorld,
            Term.evaluate (machine program calls) nextWorld environment right =
              Term.evaluate (ReadOnly.machine program) nextWorld environment
                right := fun nextWorld =>
          term_evaluate_eq_readOnly_of_callFree right components.2
        simp only [Term.evaluate]
        rw [term_evaluate_eq_readOnly_of_callFree left components.1]
        apply bind_congr
        intro result
        obtain ⟨value, nextWorld⟩ := result
        cases value <;> try rfl
        case boolean value =>
          cases value
          · exact rightEq nextWorld
          · rfl

  theorem terms_evaluate_eq_readOnly_of_callFree
      (terms : List (Term Core.signature arity))
      (free : termsCallFree terms = true) :
      evaluateTerms (machine program calls) world environment terms =
        evaluateTerms (ReadOnly.machine program) world environment terms := by
    cases terms with
    | nil => rfl
    | cons term terms =>
        have components : termCallFree term = true ∧
            termsCallFree terms = true := by
          simpa only [termsCallFree, Bool.and_eq_true] using free
        have tailEq : ∀ nextWorld,
            evaluateTerms (machine program calls) nextWorld environment terms =
              evaluateTerms (ReadOnly.machine program) nextWorld environment
                terms := fun nextWorld =>
          terms_evaluate_eq_readOnly_of_callFree terms components.2
        simp only [evaluateTerms]
        rw [term_evaluate_eq_readOnly_of_callFree term components.1]
        apply bind_congr
        intro result
        obtain ⟨value, nextWorld⟩ := result
        rw [tailEq nextWorld]
        rfl
end

namespace Term

theorem evaluate_eq_readOnly_of_callFree
    (term : Term Core.signature arity) (free : termCallFree term = true) :
    Term.evaluate (machine program calls) world environment term =
      Term.evaluate (ReadOnly.machine program) world environment term :=
  term_evaluate_eq_readOnly_of_callFree term free

end Term


namespace Terms

theorem evaluate_eq_readOnly_of_callFree
    (terms : List (Term Core.signature arity))
    (free : termsCallFree terms = true) :
    evaluateTerms (machine program calls) world environment terms =
      evaluateTerms (ReadOnly.machine program) world environment terms :=
  terms_evaluate_eq_readOnly_of_callFree terms free

end Terms

structure CallSoundness (program : Program) (calls : CallModel) where
  call : ∀ {arity : Nat} {layout : Layout arity}
    {environment : Env arity} {beforeWorld afterWorld : ReadOnly.World}
    {before afterArguments : State} {function : FunctionId}
    {arguments : List (Term Core.signature arity)} {values : List Value}
    {value : Value} {argumentWrites : CellSet},
    StateWellFormed afterArguments →
    ReadOnly.World.Represents beforeWorld afterArguments →
    EnvironmentMatches layout environment afterArguments →
    ArgumentsEvaluateTo program before (toCoreExprs layout arguments)
      values afterArguments →
    ModifiesOnly argumentWrites before afterArguments →
    calls.evaluate beforeWorld function values = .ok (value, afterWorld) →
    ∃ after writes,
      Evaluates program before (.call function (toCoreExprs layout arguments))
        value after ∧
      StateWellFormed after ∧
      ReadOnly.World.Represents afterWorld after ∧
      EnvironmentMatches layout environment after ∧
      ModifiesOnly writes before after

/-- Sound call registries remain sound when composed by a function-ID
    router.  Individual source-function contracts can therefore be proved in
    isolation and assembled without one monolithic dispatch proof. -/
theorem CallSoundness.route
    (firstSound : CallSoundness program first)
    (secondSound : CallSoundness program second) :
    CallSoundness program (CallModel.route selectFirst first second) := by
  constructor
  intro arity layout environment beforeWorld afterWorld before afterArguments
    function arguments values value argumentWrites afterArgumentsWellFormed
    represented environmentMatches argumentsExecution argumentsEffect
    evaluated
  simp only [CallModel.route] at evaluated
  split at evaluated
  · exact firstSound.call afterArgumentsWellFormed represented
      environmentMatches argumentsExecution argumentsEffect evaluated
  · exact secondSound.call afterArgumentsWellFormed represented
      environmentMatches argumentsExecution argumentsEffect evaluated

/-- The standard effectful Core bridge. Pure/read operations reuse the
    argument transition; calls delegate only their semantic leaf to the
    verified call registry. -/
def bridge (program : Program) (calls : CallModel)
    (callSoundness : CallSoundness program calls) :
    Bridge (machine program calls) program where
  Represents := ReadOnly.World.Represents
  operation := by
    intro arity layout environment argumentsWorld afterWorld before
      afterArguments operation arguments values value argumentWrites
      afterArgumentsWellFormed represented environmentMatches
      argumentsLength argumentsExecution argumentsEffect evaluated
    cases operation with
    | call function argumentTypes resultType =>
        exact callSoundness.call afterArgumentsWellFormed represented
          environmentMatches argumentsExecution argumentsEffect evaluated
    | structValue typeId fieldTypes =>
        simp only [machine, evaluateOperation,
          ReadOnly.evaluateOperation] at evaluated
        obtain ⟨rfl, rfl⟩ := evaluated
        exact ⟨afterArguments, argumentWrites,
          evaluatesStructValue argumentsExecution,
          afterArgumentsWellFormed, represented, environmentMatches,
          argumentsEffect⟩
    | constant id type =>
        cases values with
        | cons _ _ =>
            simp [machine, evaluateOperation, ReadOnly.evaluateOperation]
              at evaluated
        | nil =>
            cases arguments with
            | cons _ _ => simp at argumentsLength
            | nil =>
                have afterEq := argumentsExecution.nil_finalState
                subst afterArguments
                cases found : program.constant? id with
                | none => simp [machine, evaluateOperation,
                    ReadOnly.evaluateOperation, found] at evaluated
                | some declaration =>
                    simp [machine, evaluateOperation,
                      ReadOnly.evaluateOperation, found] at evaluated
                    obtain ⟨rfl, rfl⟩ := evaluated
                    exact ⟨before, argumentWrites, evaluatesConstant found,
                      afterArgumentsWellFormed, represented,
                      environmentMatches, argumentsEffect⟩
    | unary operation input output =>
        cases values with
        | nil => simp [machine, evaluateOperation,
            ReadOnly.evaluateOperation] at evaluated
        | cons operandValue valueTail =>
            cases valueTail with
            | cons _ _ => simp [machine, evaluateOperation,
                ReadOnly.evaluateOperation] at evaluated
            | nil =>
                cases arguments with
                | nil => simp at argumentsLength
                | cons operand rest =>
                    cases rest with
                    | cons _ _ => simp at argumentsLength
                    | nil =>
                        obtain ⟨afterOperand, operandExecution,
                          tailExecution⟩ := argumentsExecution.uncons
                        have afterEq := tailExecution.nil_finalState
                        subst afterArguments
                        simp only [machine, evaluateOperation,
                          ReadOnly.evaluateOperation, bind, Except.bind]
                          at evaluated
                        cases operationResult : evalUnaryValue program.target
                            operation operandValue with
                        | error reason =>
                            rw [operationResult] at evaluated
                            contradiction
                        | ok result =>
                            rw [operationResult] at evaluated
                            obtain ⟨rfl, rfl⟩ := evaluated
                            exact ⟨afterOperand, argumentWrites,
                              evaluatesUnary operandExecution operationResult,
                              afterArgumentsWellFormed, represented,
                              environmentMatches, argumentsEffect⟩
    | cast source target =>
        cases values with
        | nil =>
            simp [machine, evaluateOperation, ReadOnly.evaluateOperation]
              at evaluated
        | cons operandValue valueTail =>
            cases valueTail with
            | cons _ _ =>
                simp [machine, evaluateOperation, ReadOnly.evaluateOperation]
                  at evaluated
            | nil =>
                cases arguments with
                | nil => simp at argumentsLength
                | cons operand rest =>
                    cases rest with
                    | cons _ _ => simp at argumentsLength
                    | nil =>
                        obtain ⟨afterOperand, operandExecution,
                          tailExecution⟩ := argumentsExecution.uncons
                        have afterEq := tailExecution.nil_finalState
                        subst afterArguments
                        simp only [machine, evaluateOperation,
                          ReadOnly.evaluateOperation, bind, Except.bind]
                          at evaluated
                        cases operationResult : evalScalarCast program.target
                            target operandValue with
                        | error reason =>
                            rw [operationResult] at evaluated
                            contradiction
                        | ok result =>
                            rw [operationResult] at evaluated
                            obtain ⟨rfl, rfl⟩ := evaluated
                            exact ⟨afterOperand, argumentWrites,
                              evaluatesCast operandExecution operationResult,
                              afterArgumentsWellFormed, represented,
                              environmentMatches, argumentsEffect⟩
    | field baseType field resultType =>
        cases values with
        | nil =>
            simp [machine, evaluateOperation, ReadOnly.evaluateOperation]
              at evaluated
        | cons baseValue valueTail =>
            cases valueTail with
            | cons _ _ =>
                simp [machine, evaluateOperation, ReadOnly.evaluateOperation]
                  at evaluated
            | nil =>
                cases arguments with
                | nil => simp at argumentsLength
                | cons base rest =>
                    cases rest with
                    | cons _ _ => simp at argumentsLength
                    | nil =>
                        obtain ⟨afterBase, baseExecution, tailExecution⟩ :=
                          argumentsExecution.uncons
                        have afterEq := tailExecution.nil_finalState
                        subst afterArguments
                        simp only [machine, evaluateOperation,
                          ReadOnly.evaluateOperation, bind, Except.bind]
                          at evaluated
                        cases fieldResult :
                            ReadOnly.readStructureField baseValue field with
                        | error reason =>
                            rw [fieldResult] at evaluated
                            contradiction
                        | ok result =>
                            rw [fieldResult] at evaluated
                            obtain ⟨rfl, rfl⟩ := evaluated
                            obtain ⟨structureId, fields, rfl, found⟩ :=
                              ReadOnly.readStructureField_result fieldResult
                            exact ⟨afterBase, argumentWrites,
                              evaluatesStructureField baseExecution found,
                              afterArgumentsWellFormed, represented,
                              environmentMatches, argumentsEffect⟩
    | binary operation leftType rightType outputType =>
        cases values with
        | nil =>
            cases operation <;>
              simp [machine, evaluateOperation, ReadOnly.evaluateOperation]
                at evaluated
        | cons leftValue valueRest =>
            cases valueRest with
            | nil =>
                cases operation <;>
                  simp [machine, evaluateOperation, ReadOnly.evaluateOperation]
                    at evaluated
            | cons rightValue valueTail =>
                cases valueTail with
                | cons _ _ =>
                    cases operation <;>
                      simp [machine, evaluateOperation,
                        ReadOnly.evaluateOperation] at evaluated
                | nil =>
                    cases arguments with
                    | nil => simp at argumentsLength
                    | cons left rest =>
                        cases rest with
                        | nil => simp at argumentsLength
                        | cons right tail =>
                            cases tail with
                            | cons _ _ => simp at argumentsLength
                            | nil =>
                                obtain ⟨afterLeft, leftExecution,
                                  restExecution⟩ := argumentsExecution.uncons
                                obtain ⟨afterRight, rightExecution,
                                  tailExecution⟩ := restExecution.uncons
                                have afterEq := tailExecution.nil_finalState
                                subst afterArguments
                                cases operation with
                                | logicalAnd =>
                                    simp [machine, evaluateOperation] at evaluated
                                | logicalOr =>
                                    simp [machine, evaluateOperation] at evaluated
                                | equal | notEqual | less | lessEqual | greater |
                                    greaterEqual | add | subtract | multiply |
                                    divide | remainder | bitAnd | bitOr | bitXor |
                                    shiftLeft | shiftRight =>
                                    simp only [machine, evaluateOperation,
                                      ReadOnly.evaluateOperation, bind,
                                      Except.bind] at evaluated
                                    cases operationResult :
                                        evalBinaryValue program.target _
                                          leftValue rightValue with
                                    | error reason =>
                                        rw [operationResult] at evaluated
                                        contradiction
                                    | ok result =>
                                        rw [operationResult] at evaluated
                                        obtain ⟨rfl, rfl⟩ := evaluated
                                        exact ⟨afterRight, argumentWrites,
                                          evaluatesEagerBinary (by decide)
                                            (by decide) leftExecution
                                            rightExecution operationResult,
                                          afterArgumentsWellFormed, represented,
                                          environmentMatches, argumentsEffect⟩
    | index baseType indexType elementType =>
        cases values with
        | nil =>
            simp [machine, evaluateOperation, ReadOnly.evaluateOperation]
              at evaluated
        | cons baseValue valueRest =>
            cases valueRest with
            | nil =>
                simp [machine, evaluateOperation, ReadOnly.evaluateOperation]
                  at evaluated
            | cons indexValue valueTail =>
                cases valueTail with
                | cons _ _ =>
                    simp [machine, evaluateOperation,
                      ReadOnly.evaluateOperation] at evaluated
                | nil =>
                    cases arguments with
                    | nil => simp at argumentsLength
                    | cons base rest =>
                        cases rest with
                        | nil => simp at argumentsLength
                        | cons index tail =>
                            cases tail with
                            | cons _ _ => simp at argumentsLength
                            | nil =>
                                obtain ⟨afterBase, baseExecution,
                                  restExecution⟩ := argumentsExecution.uncons
                                obtain ⟨afterIndex, indexExecution,
                                  tailExecution⟩ := restExecution.uncons
                                have afterEq := tailExecution.nil_finalState
                                subst afterArguments
                                simp only [machine, evaluateOperation,
                                  ReadOnly.evaluateOperation, bind,
                                  Except.bind] at evaluated
                                cases readResult : ReadOnly.readI32Slice
                                    argumentsWorld baseValue indexValue with
                                | error reason =>
                                    rw [readResult] at evaluated
                                    contradiction
                                | ok result =>
                                    rw [readResult] at evaluated
                                    obtain ⟨rfl, rfl⟩ := evaluated
                                    obtain ⟨cell, sliceValues, position,
                                      inBounds, found, rfl, rfl, rfl⟩ :=
                                      ReadOnly.readI32Slice_result readResult
                                    have backing :=
                                      (represented cell sliceValues found).1
                                    exact ⟨afterIndex, argumentWrites,
                                      evaluatesSignedI32SliceIndex program
                                        before afterBase afterIndex sliceValues
                                        _ _ cell position inBounds baseExecution
                                        indexExecution backing,
                                      afterArgumentsWellFormed, represented,
                                      environmentMatches, argumentsEffect⟩

end Lanius.FunctionalView.Core.Effectful
