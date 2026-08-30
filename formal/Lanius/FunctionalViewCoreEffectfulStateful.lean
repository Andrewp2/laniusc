import Lanius.FunctionalViewCoreEffectful
import Lanius.FunctionalViewCoreStatefulSimulation

namespace Lanius.FunctionalView.Core.EffectfulStateful

open Lanius
open Lanius.Core
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.CallContracts
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful

/-- Separation-preserving source-call boundary.  Unlike the weaker
    expression-only call contract, this one retains the exact physical cells
    backing every active local as well as the abstract slice ownership. -/
structure CallSoundness (program : Program)
    (calls : Effectful.CallModel) where
  call : ∀ {arity : Nat} {layout : Layout arity}
    {localCell : Fin arity → CellId}
    {beforeWorld afterWorld : ReadOnly.World}
    {environment : Env arity} {before afterArguments : State}
    {function : FunctionId}
    {arguments : List (Term Core.signature arity)} {values : List Value}
    {value : Value} {argumentWrites : CellSet},
    StateWellFormed afterArguments →
    Representation layout localCell beforeWorld environment afterArguments →
    ArgumentsEvaluateTo program before (Core.toCoreExprs layout arguments)
      values afterArguments →
    ModifiesOnly argumentWrites before afterArguments →
    calls.evaluate beforeWorld function values = .ok (value, afterWorld) →
    ∃ after writes,
      Evaluates program before
        (.call function (Core.toCoreExprs layout arguments)) value after ∧
      StateWellFormed after ∧
      Representation layout localCell afterWorld environment after ∧
      ModifiesOnly writes before after
  shape : ∀ {beforeWorld afterWorld : ReadOnly.World}
    {function : FunctionId} {values : List Value} {value : Value},
    calls.evaluate beforeWorld function values = .ok (value, afterWorld) →
    ∀ cell,
      (afterWorld.i32Slice? cell).map List.length =
        (beforeWorld.i32Slice? cell).map List.length

/-- Separation-preserving composition of independently verified source-call
    registries. -/
theorem CallSoundness.route
    (firstSound : CallSoundness program first)
    (secondSound : CallSoundness program second) :
    CallSoundness program
      (Effectful.CallModel.route selectFirst first second) := by
  constructor
  · intro arity layout localCell beforeWorld afterWorld environment before
      afterArguments function arguments values value argumentWrites
      afterArgumentsWellFormed represented argumentsExecution argumentsEffect
      evaluated
    simp only [Effectful.CallModel.route] at evaluated
    split at evaluated
    · exact firstSound.call afterArgumentsWellFormed represented
        argumentsExecution argumentsEffect evaluated
    · exact secondSound.call afterArgumentsWellFormed represented
        argumentsExecution argumentsEffect evaluated
  · intro beforeWorld afterWorld function values value evaluated cell
    simp only [Effectful.CallModel.route] at evaluated
    split at evaluated
    · exact firstSound.shape evaluated cell
    · exact secondSound.shape evaluated cell

theorem evaluateOperation_shape
    (callSoundness : CallSoundness program calls)
    (evaluated : Effectful.evaluateOperation program calls beforeWorld
      operation values = .ok (value, afterWorld)) (cell : CellId) :
    (afterWorld.i32Slice? cell).map List.length =
      (beforeWorld.i32Slice? cell).map List.length := by
  cases operation with
  | call function argumentTypes resultType =>
      exact callSoundness.shape evaluated cell
  | binary operation leftType rightType outputType =>
      cases operation <;> simp [Effectful.evaluateOperation] at evaluated
      all_goals
        exact congrArg (fun world => (world.i32Slice? cell).map List.length)
          (ReadOnly.evaluateOperation_world_eq evaluated)
  | structValue typeId fieldTypes =>
      exact congrArg (fun world => (world.i32Slice? cell).map List.length)
        (ReadOnly.evaluateOperation_world_eq (by
          simpa [Effectful.evaluateOperation] using evaluated))
  | constant id type =>
      exact congrArg (fun world => (world.i32Slice? cell).map List.length)
        (ReadOnly.evaluateOperation_world_eq (by
          simpa [Effectful.evaluateOperation] using evaluated))
  | unary operation input output =>
      exact congrArg (fun world => (world.i32Slice? cell).map List.length)
        (ReadOnly.evaluateOperation_world_eq (by
          simpa [Effectful.evaluateOperation] using evaluated))
  | cast source target =>
      exact congrArg (fun world => (world.i32Slice? cell).map List.length)
        (ReadOnly.evaluateOperation_world_eq (by
          simpa [Effectful.evaluateOperation] using evaluated))
  | field source field target =>
      exact congrArg (fun world => (world.i32Slice? cell).map List.length)
        (ReadOnly.evaluateOperation_world_eq (by
          simpa [Effectful.evaluateOperation] using evaluated))
  | index base index element =>
      exact congrArg (fun world => (world.i32Slice? cell).map List.length)
        (ReadOnly.evaluateOperation_world_eq (by
          simpa [Effectful.evaluateOperation] using evaluated))

mutual

  theorem term_evaluate_shape
      (callSoundness : CallSoundness program calls)
      (evaluated : Term.evaluate (Effectful.machine program calls) beforeWorld
        environment term = .ok (value, afterWorld)) (cell : CellId) :
      (afterWorld.i32Slice? cell).map List.length =
        (beforeWorld.i32Slice? cell).map List.length := by
    cases term with
    | reference reference =>
        cases reference <;>
          simp [Term.evaluate, Ref.evaluate] at evaluated <;>
          obtain ⟨rfl, rfl⟩ := evaluated <;> rfl
    | apply operation arguments =>
        simp only [Term.evaluate] at evaluated
        cases argumentsResult : evaluateTerms (Effectful.machine program calls)
            beforeWorld environment arguments with
        | error reason =>
            rw [argumentsResult] at evaluated
            contradiction
        | ok result =>
            obtain ⟨values, argumentsWorld⟩ := result
            rw [argumentsResult] at evaluated
            have argumentsShape := terms_evaluate_shape callSoundness
              argumentsResult cell
            have operationShape := evaluateOperation_shape
              callSoundness evaluated cell
            exact operationShape.trans argumentsShape
    | logicalAnd left right | logicalOr left right =>
        simp only [Term.evaluate] at evaluated
        cases leftResult : Term.evaluate (Effectful.machine program calls)
            beforeWorld environment left with
        | error reason =>
            simp only [leftResult, bind, Except.bind] at evaluated
            contradiction
        | ok result =>
            obtain ⟨leftValue, leftWorld⟩ := result
            simp only [leftResult, bind, Except.bind] at evaluated
            have leftShape := term_evaluate_shape callSoundness leftResult cell
            cases leftValue with
            | boolean leftBoolean =>
                cases leftBoolean <;> simp only at evaluated
                all_goals
                  first
                  | obtain ⟨rfl, rfl⟩ := evaluated; exact leftShape
                  | exact (term_evaluate_shape callSoundness evaluated cell).trans
                      leftShape
            | _ => contradiction

  theorem terms_evaluate_shape
      (callSoundness : CallSoundness program calls)
      (evaluated : evaluateTerms (Effectful.machine program calls) beforeWorld
        environment terms = .ok (values, afterWorld)) (cell : CellId) :
      (afterWorld.i32Slice? cell).map List.length =
        (beforeWorld.i32Slice? cell).map List.length := by
    cases terms with
    | nil =>
        simp [evaluateTerms] at evaluated
        obtain ⟨rfl, rfl⟩ := evaluated
        rfl
    | cons head tail =>
        simp only [evaluateTerms] at evaluated
        cases headResult : Term.evaluate (Effectful.machine program calls)
            beforeWorld environment head with
        | error reason =>
            rw [headResult] at evaluated
            contradiction
        | ok result =>
            obtain ⟨headValue, headWorld⟩ := result
            rw [headResult] at evaluated
            simp only [bind, Except.bind] at evaluated
            cases tailResult : evaluateTerms (Effectful.machine program calls)
                headWorld environment tail with
            | error reason =>
                rw [tailResult] at evaluated
                contradiction
            | ok result =>
                obtain ⟨tailValues, tailWorld⟩ := result
                rw [tailResult] at evaluated
                obtain ⟨rfl, rfl⟩ := evaluated
                exact (terms_evaluate_shape callSoundness tailResult cell).trans
                  (term_evaluate_shape callSoundness headResult cell)

end

/-- Ordinary Core operations are framed automatically; only `.call` reaches
    the source-function registry above. -/
def operationSoundness (program : Program) (calls : Effectful.CallModel)
    (callSoundness : CallSoundness program calls) :
    OperationSoundness program (Effectful.evaluateOperation program calls) where
  operation := by
    intro arity layout localCell argumentsWorld afterWorld environment before
      afterArguments operation arguments values value argumentWrites
      afterArgumentsWellFormed represented argumentsLength argumentsExecution
      argumentsEffect evaluated
    cases operation with
    | call function argumentTypes resultType =>
        exact callSoundness.call afterArgumentsWellFormed represented
          argumentsExecution argumentsEffect evaluated
    | structValue typeId fieldTypes =>
        simp only [Effectful.evaluateOperation,
          ReadOnly.evaluateOperation] at evaluated
        obtain ⟨rfl, rfl⟩ := evaluated
        exact ⟨afterArguments, argumentWrites,
          evaluatesStructValue argumentsExecution,
          afterArgumentsWellFormed, represented, argumentsEffect⟩
    | constant id type =>
        cases values with
        | cons _ _ =>
            simp [Effectful.evaluateOperation, ReadOnly.evaluateOperation]
              at evaluated
        | nil =>
            cases arguments with
            | cons _ _ => simp at argumentsLength
            | nil =>
                have afterEq := argumentsExecution.nil_finalState
                subst afterArguments
                cases found : program.constant? id with
                | none =>
                    simp [Effectful.evaluateOperation,
                      ReadOnly.evaluateOperation, found] at evaluated
                | some declaration =>
                    simp [Effectful.evaluateOperation,
                      ReadOnly.evaluateOperation, found] at evaluated
                    obtain ⟨rfl, rfl⟩ := evaluated
                    exact ⟨before, argumentWrites, evaluatesConstant found,
                      afterArgumentsWellFormed, represented, argumentsEffect⟩
    | unary operation input output =>
        cases values with
        | nil =>
            simp [Effectful.evaluateOperation, ReadOnly.evaluateOperation]
              at evaluated
        | cons operandValue valueTail =>
            cases valueTail with
            | cons _ _ =>
                simp [Effectful.evaluateOperation, ReadOnly.evaluateOperation]
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
                        simp only [Effectful.evaluateOperation,
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
                              argumentsEffect⟩
    | cast source target =>
        cases values with
        | nil =>
            simp [Effectful.evaluateOperation, ReadOnly.evaluateOperation]
              at evaluated
        | cons operandValue valueTail =>
            cases valueTail with
            | cons _ _ =>
                simp [Effectful.evaluateOperation, ReadOnly.evaluateOperation]
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
                        simp only [Effectful.evaluateOperation,
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
                              argumentsEffect⟩
    | field baseType field resultType =>
        cases values with
        | nil =>
            simp [Effectful.evaluateOperation, ReadOnly.evaluateOperation]
              at evaluated
        | cons baseValue valueTail =>
            cases valueTail with
            | cons _ _ =>
                simp [Effectful.evaluateOperation, ReadOnly.evaluateOperation]
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
                        simp only [Effectful.evaluateOperation,
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
                              argumentsEffect⟩
    | binary operation leftType rightType outputType =>
        cases values with
        | nil =>
            cases operation <;>
              simp [Effectful.evaluateOperation, ReadOnly.evaluateOperation]
                at evaluated
        | cons leftValue valueRest =>
            cases valueRest with
            | nil =>
                cases operation <;>
                  simp [Effectful.evaluateOperation,
                    ReadOnly.evaluateOperation] at evaluated
            | cons rightValue valueTail =>
                cases valueTail with
                | cons _ _ =>
                    cases operation <;>
                      simp [Effectful.evaluateOperation,
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
                                    simp [Effectful.evaluateOperation]
                                      at evaluated
                                | logicalOr =>
                                    simp [Effectful.evaluateOperation]
                                      at evaluated
                                | equal | notEqual | less | lessEqual | greater |
                                    greaterEqual | add | subtract | multiply |
                                    divide | remainder | bitAnd | bitOr | bitXor |
                                    shiftLeft | shiftRight =>
                                    simp only [Effectful.evaluateOperation,
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
                                          argumentsEffect⟩
    | index baseType indexType elementType =>
        cases values with
        | nil =>
            simp [Effectful.evaluateOperation, ReadOnly.evaluateOperation]
              at evaluated
        | cons baseValue valueRest =>
            cases valueRest with
            | nil =>
                simp [Effectful.evaluateOperation, ReadOnly.evaluateOperation]
                  at evaluated
            | cons indexValue valueTail =>
                cases valueTail with
                | cons _ _ =>
                    simp [Effectful.evaluateOperation,
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
                                simp only [Effectful.evaluateOperation,
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
                                      (represented.worldRepresents
                                        afterArgumentsWellFormed cell
                                        sliceValues found).1
                                    exact ⟨afterIndex, argumentWrites,
                                      evaluatesSignedI32SliceIndex program
                                        before afterBase afterIndex sliceValues
                                        _ _ cell position inBounds baseExecution
                                        indexExecution backing,
                                      afterArgumentsWellFormed, represented,
                                      argumentsEffect⟩

def expressionSoundness (program : Program) (calls : Effectful.CallModel)
    (callSoundness : CallSoundness program calls) :
    ExpressionSoundness program (Effectful.evaluateOperation program calls) :=
  expressionSoundnessOfOperations
    (operationSoundness program calls callSoundness)

/-- Finish an indexed write after its index and replacement terms have each
    taken an arbitrary framed transition.  The abstract call model preserves
    allocation shape, so the backing slice seen by the index has the same
    length as the backing slice finally written by the action. -/
theorem Representation.setI32IndexAfterTerms
    {arity : Nat} {layout : Layout arity}
    {localCell : Fin arity → CellId}
    {beforeWorld indexWorld rightWorld : ReadOnly.World}
    {environment : Env arity}
    {before afterIndex afterRight : State} {program : Program}
    {base : Fin arity} {index value : Term Core.signature arity}
    {cell : CellId} {indexValues rightValues : List Int} {position : Nat}
    {replacement : Int} {indexWrites rightWrites : CellSet}
    (beforeRepresented : Representation layout localCell beforeWorld
      environment before)
    (indexRepresented : Representation layout localCell indexWorld
      environment afterIndex)
    (rightRepresented : Representation layout localCell rightWorld
      environment afterRight)
    (rightWellFormed : StateWellFormed afterRight)
    (baseValue : environment base =
      .slice (.scalar (.signed .i32)) cell [] 0 rightValues.length)
    (indexExecution : Evaluates program before (Core.toCoreExpr layout index)
      (.signed .i32 (Int.ofNat position)) afterIndex)
    (indexEffect : ModifiesOnly indexWrites before afterIndex)
    (rightExecution : Evaluates program afterIndex
      (Core.toCoreExpr layout value) (.signed .i32 replacement) afterRight)
    (rightEffect : ModifiesOnly rightWrites afterIndex afterRight)
    (foundIndex : indexWorld.i32Slice? cell = some indexValues)
    (foundRight : rightWorld.i32Slice? cell = some rightValues)
    (sameLength : indexValues.length = rightValues.length)
    (inBounds : position < rightValues.length) :
    ∃ after,
      Executes program before
        (actionAdapter.toCoreStmt layout (.setI32Index base index value))
        .next after ∧
      StateWellFormed after ∧
      Representation layout localCell
        (ReadOnly.World.setI32Slice rightWorld cell
          (setI32Value rightValues position replacement)) environment after ∧
      ModifiesOnly (CellSet.union indexWrites
        (CellSet.union rightWrites (CellSet.singleton cell))) before after := by
  have sliceLocal : before.local? (layout base) = some
      (.slice (.scalar (.signed .i32)) cell [] 0 rightValues.length) := by
    rw [beforeRepresented.environmentMatches base, baseValue]
  have backingAtIndex := indexRepresented.worldOwned cell indexValues foundIndex
  have backingAtRight := rightRepresented.worldOwned cell rightValues foundRight
  obtain ⟨after, written, afterWellFormed, afterBacking, completeEffect,
      assignmentEffect⟩ :=
    evaluatesSetSignedI32SliceIndex program before afterIndex afterRight
      indexValues rightValues (layout base) (Core.toCoreExpr layout index)
      (Core.toCoreExpr layout value) cell position replacement sameLength
      inBounds sliceLocal indexExecution indexEffect rightExecution
      rightWellFormed rightEffect backingAtIndex backingAtRight
  have afterWorldOwned : (ReadOnly.World.owns
      (ReadOnly.World.setI32Slice rightWorld cell
        (setI32Value rightValues position replacement))).holds after := by
    intro candidate contents candidateFound
    by_cases same : candidate = cell
    · subst candidate
      have contentsEq : contents =
          setI32Value rightValues position replacement := by
        simpa using candidateFound.symm
      subst contents
      exact afterBacking
    · have oldFound : rightWorld.i32Slice? candidate = some contents := by
        simpa [ReadOnly.World.setI32Slice, same] using candidateFound
      exact assignmentEffect.preserves_entry rightWellFormed
        (rightRepresented.worldOwned candidate contents oldFound) (by
          simpa [CellSet.singleton] using same)
  have afterLocalsOwned : ∀ slot,
      (Assertion.localPointsTo (layout slot) (localCell slot)
        (some (environment slot))).holds after := by
    intro slot
    exact assignmentEffect.preserve rightWellFormed
      (Assertion.localPointsTo (layout slot) (localCell slot)
        (some (environment slot))) (rightRepresented.localOwned slot) (by
          intro candidate member written
          exact rightRepresented.worldCell_ne_localCell foundRight slot
            (written.symm.trans member))
  have footprint := ReadOnly.World.setI32Slice_footprint
    (replacement := setI32Value rightValues position replacement) foundRight
  exact ⟨after, executesExpression written, afterWellFormed, {
    worldOwned := afterWorldOwned
    localOwned := afterLocalsOwned
    localCellsInjective := rightRepresented.localCellsInjective
    worldLocalsDisjoint := by simpa [footprint] using
      rightRepresented.worldLocalsDisjoint
  }, completeEffect⟩

/-- Stateful action bridge for call-aware FunctionalView programs. -/
def actionSoundness (program : Program) (calls : Effectful.CallModel)
    (callSoundness : CallSoundness program calls) :
    ActionSoundness program (Effectful.evaluateOperation program calls) where
  action := by
    intro arity layout localCell world environment state operation afterWorld
      nextLocal wellFormed represented actionResult
    cases operation with
    | setI32Index base index value =>
        change evaluateActionWith
          (Effectful.evaluateOperation program calls) world environment
          (.setI32Index base index value) = .ok afterWorld at actionResult
        cases indexResult : Term.evaluate
            (termMachine (Effectful.evaluateOperation program calls))
            world environment index with
        | error reason =>
            simp [evaluateActionWith, indexResult, bind, Except.bind]
              at actionResult
        | ok result =>
            obtain ⟨indexValue, indexWorld⟩ := result
            simp only [evaluateActionWith, indexResult, bind, Except.bind]
              at actionResult
            obtain ⟨afterIndex, indexWrites, indexExecution,
                indexWellFormed, indexRepresented, indexEffect⟩ :=
              (expressionSoundness program calls callSoundness).term
                wellFormed represented indexResult
            cases valueResult : Term.evaluate
                (termMachine (Effectful.evaluateOperation program calls))
                indexWorld environment value with
            | error reason =>
                rw [valueResult] at actionResult
                contradiction
            | ok result =>
                obtain ⟨replacementValue, rightWorld⟩ := result
                rw [valueResult] at actionResult
                simp only [bind, Except.bind] at actionResult
                obtain ⟨afterRight, rightWrites, rightExecution,
                    rightWellFormed, rightRepresented, rightEffect⟩ :=
                  (expressionSoundness program calls callSoundness).term
                    indexWellFormed indexRepresented valueResult
                obtain ⟨cell, rightValues, position, replacement, baseValue,
                    indexValueEq, replacementValueEq, foundRight, inBounds,
                    afterWorldEq⟩ := writeI32Slice_result actionResult
                subst indexValue
                subst replacementValue
                subst afterWorld
                have valueResultEffectful := valueResult
                change Term.evaluate (Effectful.machine program calls)
                  indexWorld environment value =
                    .ok (.signed .i32 replacement, rightWorld)
                  at valueResultEffectful
                have shape := term_evaluate_shape callSoundness
                  valueResultEffectful cell
                rw [foundRight] at shape
                cases foundIndex : indexWorld.i32Slice? cell with
                | none => simp [foundIndex] at shape
                | some indexValues =>
                    have sameLength : indexValues.length =
                        rightValues.length := by
                      simpa [foundIndex] using shape.symm
                    obtain ⟨after, execution, afterWellFormed,
                        afterRepresented, effect⟩ :=
                      EffectfulStateful.Representation.setI32IndexAfterTerms
                        represented indexRepresented
                        rightRepresented rightWellFormed baseValue indexExecution
                        indexEffect rightExecution rightEffect foundIndex
                        foundRight sameLength inBounds
                    exact ⟨after, _, execution, afterWellFormed,
                      afterRepresented, effect⟩

end Lanius.FunctionalView.Core.EffectfulStateful
