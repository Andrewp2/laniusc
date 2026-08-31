import Lanius.FunctionalViewCoreEffectfulStateful

namespace Lanius.FunctionalView.FreshSimulation

open Lanius
open Lanius.Core
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.CallContracts
open Lanius.FunctionalView
open Lanius.FunctionalView.Stateful
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Core.Effectful

/-! A source call may allocate temporary cells, but expression evaluation must
not mutate any cell visible before the expression began.  The ordinary
`CallSoundness` interface intentionally permits writes. Nested read-only and
helper-call evaluation uses the stronger caller-frame-preserving boundary below. -/

structure FramePreservingCallSoundness (program : Program) (calls : CallModel) where
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
    ∃ after,
      Evaluates program before
        (.call function (Core.toCoreExprs layout arguments)) value after ∧
      StateWellFormed after ∧
      Representation layout localCell afterWorld environment after ∧
      ModifiesOnly argumentWrites before after

def WorldPreserving (calls : CallModel) : Prop :=
  ∀ {beforeWorld afterWorld function values value},
    calls.evaluate beforeWorld function values = .ok (value, afterWorld) →
    afterWorld = beforeWorld

theorem WorldPreserving.route
    (firstPreserves : WorldPreserving first)
    (secondPreserves : WorldPreserving second) :
    WorldPreserving (CallModel.route selectFirst first second) := by
  intro beforeWorld afterWorld function values value evaluated
  simp only [CallModel.route] at evaluated
  split at evaluated
  · exact firstPreserves evaluated
  · exact secondPreserves evaluated

/-- Compose two caller-frame-preserving call registries with the same routing
predicate used by `CallModel.route`. -/
theorem FramePreservingCallSoundness.route
    (firstSound : FramePreservingCallSoundness program first)
    (secondSound : FramePreservingCallSoundness program second) :
    FramePreservingCallSoundness program
      (CallModel.route selectFirst first second) := by
  constructor
  intro arity layout localCell beforeWorld afterWorld environment before
    afterArguments function arguments values value argumentWrites
    afterArgumentsWellFormed represented argumentsExecution argumentsEffect
    evaluated
  simp only [CallModel.route] at evaluated
  split at evaluated
  · exact firstSound.call afterArgumentsWellFormed represented
      argumentsExecution argumentsEffect evaluated
  · exact secondSound.call afterArgumentsWellFormed represented
      argumentsExecution argumentsEffect evaluated

/-- A frame-preserving registry whose abstract world is unchanged also
satisfies the ordinary separation-preserving call contract. -/
theorem FramePreservingCallSoundness.toCallSoundness
    (sound : FramePreservingCallSoundness program calls)
    (worldPreserved : WorldPreserving calls) :
    EffectfulStateful.CallSoundness program calls := by
  constructor
  · intro arity layout localCell beforeWorld afterWorld environment before
      afterArguments function arguments values value argumentWrites
      afterArgumentsWellFormed represented argumentsExecution argumentsEffect
      evaluated
    obtain ⟨after, execution, afterWellFormed, afterRepresented, effect⟩ :=
      sound.call afterArgumentsWellFormed represented argumentsExecution
        argumentsEffect evaluated
    exact ⟨after, argumentWrites, execution, afterWellFormed,
      afterRepresented, effect⟩
  · intro beforeWorld afterWorld function values value evaluated cell
    rw [worldPreserved evaluated]

structure FramePreservingOperationSoundness (program : Program)
    (calls : CallModel) where
  operation : ∀ {arity : Nat} {layout : Layout arity}
    {localCell : Fin arity → CellId}
    {argumentsWorld afterWorld : ReadOnly.World}
    {environment : Env arity} {before afterArguments : State}
    {operation : Operation} {arguments : List (Term Core.signature arity)}
    {values : List Value} {value : Value},
    StateWellFormed afterArguments →
    Representation layout localCell argumentsWorld environment afterArguments →
    arguments.length = values.length →
    ArgumentsEvaluateTo program before (Core.toCoreExprs layout arguments)
      values afterArguments →
    ModifiesOnly CellSet.empty before afterArguments →
    Effectful.evaluateOperation program calls argumentsWorld operation values =
      .ok (value, afterWorld) →
    ∃ after,
      Evaluates program before
        (Operation.toCoreExpr operation (Core.toCoreExprs layout arguments))
        value after ∧
      StateWellFormed after ∧
      Representation layout localCell afterWorld environment after ∧
      ModifiesOnly CellSet.empty before after

def operationSoundness (program : Program) (calls : CallModel)
    (callsSound : FramePreservingCallSoundness program calls) :
    FramePreservingOperationSoundness program calls where
  operation := by
    intro arity layout localCell argumentsWorld afterWorld environment before
      afterArguments operation arguments values value afterArgumentsWellFormed
      represented argumentsLength argumentsExecution argumentsEffect evaluated
    cases operation with
    | call function argumentTypes resultType =>
        exact callsSound.call afterArgumentsWellFormed represented
          argumentsExecution argumentsEffect evaluated
    | structValue typeId fieldTypes =>
        simp only [Effectful.evaluateOperation,
          ReadOnly.evaluateOperation] at evaluated
        obtain ⟨rfl, rfl⟩ := evaluated
        exact ⟨afterArguments, evaluatesStructValue argumentsExecution,
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
                    exact ⟨before, evaluatesConstant found,
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
                            exact ⟨afterOperand,
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
                            exact ⟨afterOperand,
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
                            exact ⟨afterBase,
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
                                        exact ⟨afterRight,
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
                                    exact ⟨afterIndex,
                                      evaluatesSignedI32SliceIndex program
                                        before afterBase afterIndex sliceValues
                                        _ _ cell position inBounds baseExecution
                                        indexExecution backing,
                                      afterArgumentsWellFormed, represented,
                                      argumentsEffect⟩

mutual

  theorem termSoundness
      (operations : FramePreservingOperationSoundness program calls)
      (wellFormed : StateWellFormed state)
      (represented : Representation layout localCell world environment state)
      (evaluated : Term.evaluate (Effectful.machine program calls) world
        environment term = .ok (value, afterWorld)) :
      ∃ after,
        Evaluates program state (Core.toCoreExpr layout term) value after ∧
        StateWellFormed after ∧
        Representation layout localCell afterWorld environment after ∧
        ModifiesOnly CellSet.empty state after := by
    cases term with
    | reference reference =>
        cases reference with
        | slot index =>
            simp only [Term.evaluate, Ref.evaluate, Core.toCoreExpr,
              Core.refToCoreExpr] at evaluated ⊢
            obtain ⟨rfl, rfl⟩ := evaluated
            exact ⟨state,
              ⟨1, evalLocal_of_local 0 program state _ _
                (represented.environmentMatches index)⟩,
              wellFormed, represented, ModifiesOnly.refl state⟩
        | literal literalValue =>
            simp only [Term.evaluate, Ref.evaluate, Core.toCoreExpr,
              Core.refToCoreExpr] at evaluated ⊢
            obtain ⟨rfl, rfl⟩ := evaluated
            exact ⟨state, ⟨1, rfl⟩, wellFormed, represented,
              ModifiesOnly.refl state⟩
    | apply operation arguments =>
        simp only [Term.evaluate] at evaluated
        cases argumentsResult : evaluateTerms
            (Effectful.machine program calls) world environment arguments with
        | error reason =>
            rw [argumentsResult] at evaluated
            contradiction
        | ok result =>
            obtain ⟨values, argumentsWorld⟩ := result
            rw [argumentsResult] at evaluated
            change Effectful.evaluateOperation program calls argumentsWorld
              operation values = .ok (value, afterWorld) at evaluated
            obtain ⟨afterArguments, argumentsExecution,
                argumentsWellFormed, argumentsRepresented, argumentsEffect⟩ :=
              termsSoundness operations wellFormed represented argumentsResult
            exact operations.operation argumentsWellFormed argumentsRepresented
              (Effectful.evaluateTerms_length argumentsResult)
              argumentsExecution argumentsEffect evaluated
    | logicalAnd left right =>
        simp only [Term.evaluate] at evaluated
        cases leftResult : Term.evaluate (Effectful.machine program calls) world
            environment left with
        | error reason =>
            simp only [leftResult, bind, Except.bind] at evaluated
            contradiction
        | ok result =>
            obtain ⟨leftValue, leftWorld⟩ := result
            simp only [leftResult, bind, Except.bind] at evaluated
            obtain ⟨afterLeft, leftExecution, leftWellFormed,
                leftRepresented, leftEffect⟩ :=
              termSoundness operations wellFormed represented leftResult
            cases leftValue with
            | boolean leftBoolean =>
                cases leftBoolean with
                | false =>
                    obtain ⟨rfl, rfl⟩ := evaluated
                    exact ⟨afterLeft,
                      evaluatesLogicalAndFalse leftExecution,
                      leftWellFormed, leftRepresented, leftEffect⟩
                | true =>
                    obtain ⟨after, rightExecution, afterWellFormed,
                        afterRepresented, rightEffect⟩ :=
                      termSoundness operations leftWellFormed leftRepresented
                        evaluated
                    exact ⟨after,
                      evaluatesLogicalAndTrue leftExecution rightExecution,
                      afterWellFormed, afterRepresented,
                      leftEffect.trans_same rightEffect⟩
            | _ => contradiction
    | logicalOr left right =>
        simp only [Term.evaluate] at evaluated
        cases leftResult : Term.evaluate (Effectful.machine program calls) world
            environment left with
        | error reason =>
            simp only [leftResult, bind, Except.bind] at evaluated
            contradiction
        | ok result =>
            obtain ⟨leftValue, leftWorld⟩ := result
            simp only [leftResult, bind, Except.bind] at evaluated
            obtain ⟨afterLeft, leftExecution, leftWellFormed,
                leftRepresented, leftEffect⟩ :=
              termSoundness operations wellFormed represented leftResult
            cases leftValue with
            | boolean leftBoolean =>
                cases leftBoolean with
                | false =>
                    obtain ⟨after, rightExecution, afterWellFormed,
                        afterRepresented, rightEffect⟩ :=
                      termSoundness operations leftWellFormed leftRepresented
                        evaluated
                    exact ⟨after,
                      evaluatesLogicalOrFalse leftExecution rightExecution,
                      afterWellFormed, afterRepresented,
                      leftEffect.trans_same rightEffect⟩
                | true =>
                    obtain ⟨rfl, rfl⟩ := evaluated
                    exact ⟨afterLeft, evaluatesLogicalOrTrue leftExecution,
                      leftWellFormed, leftRepresented, leftEffect⟩
            | _ => contradiction

  theorem termsSoundness
      (operations : FramePreservingOperationSoundness program calls)
      (wellFormed : StateWellFormed state)
      (represented : Representation layout localCell world environment state)
      (evaluated : evaluateTerms (Effectful.machine program calls) world
        environment terms = .ok (values, afterWorld)) :
      ∃ after,
        ArgumentsEvaluateTo program state (Core.toCoreExprs layout terms)
          values after ∧
        StateWellFormed after ∧
        Representation layout localCell afterWorld environment after ∧
        ModifiesOnly CellSet.empty state after := by
    cases terms with
    | nil =>
        simp only [evaluateTerms, Core.toCoreExprs] at evaluated ⊢
        obtain ⟨rfl, rfl⟩ := evaluated
        exact ⟨state, ArgumentsEvaluateTo.nil program state,
          wellFormed, represented, ModifiesOnly.refl state⟩
    | cons head tail =>
        simp only [evaluateTerms] at evaluated
        cases headResult : Term.evaluate (Effectful.machine program calls) world
            environment head with
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
                obtain ⟨afterHead, headExecution, headWellFormed,
                    headRepresented, headEffect⟩ :=
                  termSoundness operations wellFormed represented headResult
                obtain ⟨after, tailExecution, afterWellFormed,
                    afterRepresented, tailEffect⟩ :=
                  termsSoundness operations headWellFormed headRepresented
                    tailResult
                exact ⟨after,
                  ArgumentsEvaluateTo.cons headExecution tailExecution,
                  afterWellFormed, afterRepresented,
                  headEffect.trans_same tailEffect⟩

end

def freshCells (frontier : CellId) : CellSet := fun cell => frontier ≤ cell

def LocalsFresh (frontier : CellId) (localCell : Fin arity → CellId) : Prop :=
  ∀ index, frontier ≤ localCell index

def actionFree : Command Core.signature actions arity → Bool
  | .skip => true
  | .sequence first second => actionFree first && actionFree second
  | .letValue _ _ body => actionFree body
  | .setLocal _ _ => true
  | .updateLocal _ _ _ => true
  | .action _ => false
  | .ifThenElse _ thenBranch elseBranch =>
      actionFree thenBranch && actionFree elseBranch
  | .whileLoop _ body => actionFree body
  | .returnValue _ => true
  | .breakLoop => true
  | .continueLoop => true

def SimulatesFresh
    (program : Program) (frontier : CellId) (layout : Layout arity)
    (localCell : Fin arity → CellId)
    (beforeWorld : ReadOnly.World) (beforeEnvironment : Env arity)
    (before : State) (command : Command Core.signature actions arity)
    (completion : Lanius.FunctionalView.Stateful.Completion)
    (afterWorld : ReadOnly.World) (afterEnvironment : Env arity)
    (nextLocal : VarId) : Prop :=
  ∃ after,
    Executes program before
      (toCoreStmt actionAdapter layout nextLocal command)
      (Lanius.FunctionalView.Core.Stateful.toCoreCompletion completion) after ∧
    StateWellFormed after ∧
    Representation layout localCell afterWorld afterEnvironment after ∧
    ModifiesOnly (freshCells frontier) before after

theorem commandSoundness
    {arity : Nat} {program : Program} {calls : CallModel}
    {world afterWorld : ReadOnly.World}
    {environment afterEnvironment : Env arity}
    {command : Command Core.signature actions arity}
    {completion : Lanius.FunctionalView.Stateful.Completion}
    (operations : FramePreservingOperationSoundness program calls)
    (evaluated : Command.Evaluates (Effectful.machine program calls)
      (machineWith program (Effectful.evaluateOperation program calls))
      world environment command completion afterWorld afterEnvironment) :
    actionFree command = true →
    ∀ {frontier : CellId} {layout : Layout arity} {state : State}
      {localCell : Fin arity → CellId} {nextLocal : VarId},
      Representation layout localCell world environment state →
      LayoutBelow layout nextLocal →
      StateWellFormed state →
      LocalsFresh frontier localCell →
      frontier ≤ state.nextCell →
      SimulatesFresh program frontier layout localCell world environment state
        command completion afterWorld afterEnvironment nextLocal := by
  let motive : {arity : Nat} →
      (world : ReadOnly.World) → (environment : Env arity) →
      (command : Command Core.signature actions arity) →
      (completion : Lanius.FunctionalView.Stateful.Completion) →
      (afterWorld : ReadOnly.World) → (afterEnvironment : Env arity) →
      Command.Evaluates (Effectful.machine program calls)
        (machineWith program (Effectful.evaluateOperation program calls))
        world environment command completion afterWorld afterEnvironment → Prop :=
    fun {arity} world environment command completion afterWorld
      afterEnvironment _ =>
      actionFree command = true →
      ∀ {frontier : CellId} {layout : Layout arity} {state : State}
        {localCell : Fin arity → CellId} {nextLocal : VarId},
        Representation layout localCell world environment state →
        LayoutBelow layout nextLocal →
        StateWellFormed state →
        LocalsFresh frontier localCell →
        frontier ≤ state.nextCell →
        SimulatesFresh program frontier layout localCell world environment state
          command completion afterWorld afterEnvironment nextLocal
  change motive world environment command completion afterWorld
    afterEnvironment evaluated
  apply @Command.Evaluates.rec Core.signature actions
    (Effectful.machine program calls)
    (machineWith program (Effectful.evaluateOperation program calls)) motive
  case skip =>
      intro _world _arity _environment free frontier layout state localCell
        nextLocal represented below wellFormed localsFresh nextFresh
      exact ⟨state, executesSkip program state, wellFormed, represented,
        (ModifiesOnly.refl state).weaken CellSet.empty_subset⟩
  case sequenceNext =>
      intro _beforeWorld _arity _beforeEnvironment firstCommand _middleWorld
        _middleEnvironment secondCommand _completion _afterWorld
        _afterEnvironment _firstResult _secondResult firstInduction
        secondInduction free frontier layout state localCell nextLocal represented
        below wellFormed localsFresh nextFresh
      simp only [actionFree, Bool.and_eq_true] at free
      obtain ⟨middle, firstExecution, middleWellFormed, middleRepresented,
        firstEffect⟩ := firstInduction free.1 represented below wellFormed
          localsFresh nextFresh
      have secondBelow := below.mono
        (Nat.le_add_right nextLocal (localCapacity actionAdapter firstCommand))
      obtain ⟨after, secondExecution, afterWellFormed, afterRepresented,
        secondEffect⟩ := secondInduction free.2 middleRepresented secondBelow
          middleWellFormed localsFresh
          (Nat.le_trans nextFresh firstEffect.nextCell)
      exact ⟨after, executesSequence firstExecution secondExecution,
        afterWellFormed, afterRepresented,
        firstEffect.trans_same secondEffect⟩
  case sequenceStop =>
      intro _beforeWorld _arity _beforeEnvironment firstCommand completion
        _afterWorld _afterEnvironment secondCommand _firstResult stops
        firstInduction free frontier layout state localCell nextLocal represented
        below wellFormed localsFresh nextFresh
      simp only [actionFree, Bool.and_eq_true] at free
      obtain ⟨after, execution, afterWellFormed, afterRepresented, effect⟩ :=
        firstInduction free.1 represented below wellFormed localsFresh nextFresh
      exact ⟨after, executesSequenceNonNext execution (by
        intro same
        apply stops
        cases completion <;>
          simp_all [Lanius.FunctionalView.Core.Stateful.toCoreCompletion]),
        afterWellFormed, afterRepresented, effect⟩
  case letValue =>
      intro beforeWorld branchArity beforeEnvironment initializer value
        initializedWorld body completion afterWorld extendedEnvironment type
        initializerResult bodyResult induction free frontier layout state
        localCell nextLocal represented below wellFormed localsFresh nextFresh
      simp only [actionFree] at free
      obtain ⟨initialized, initializerExecution, initializedWellFormed,
          initializedRepresented, initializerEffect⟩ :=
        termSoundness operations wellFormed represented initializerResult
      let bound := initialized.bindLocal nextLocal value
      let boundCells := pushCells localCell initialized.nextCell
      have boundWellFormed := bindLocal_preserves_well_formed initialized
        nextLocal value initializedWellFormed
      have boundRepresented : Representation (Layout.push layout nextLocal)
          boundCells initializedWorld (beforeEnvironment.push value) bound := by
        simpa [bound, boundCells] using
          initializedRepresented.bindLocal below initializedWellFormed value
      have boundFresh : LocalsFresh frontier boundCells := by
        intro index
        simp only [boundCells, pushCells]
        split
        · exact localsFresh _
        · exact Nat.le_trans nextFresh initializerEffect.nextCell
      have boundNextFresh : frontier ≤ bound.nextCell := by
        simp [bound, State.bindLocal, State.bindCell]
        exact Nat.le_trans nextFresh
          (Nat.le_trans initializerEffect.nextCell (Nat.le_succ _))
      obtain ⟨completed, bodyExecution, completedWellFormed,
          completedRepresented, bodyEffect⟩ :=
        induction free boundRepresented below.push boundWellFormed boundFresh
          boundNextFresh
      let after := restoreLocals initialized completed
      have scopeEffect : ModifiesOnly (freshCells frontier) initialized after :=
        temporaryLocal_effect nextLocal value bodyEffect.toStoreEffect
      have afterWellFormed : StateWellFormed after := by
        have entered : StoreEffect (freshCells frontier) initialized bound :=
          (bindLocal_effect initialized nextLocal value).weaken
            CellSet.empty_subset
        simpa [after] using
          (entered.trans_same bodyEffect.toStoreEffect).restoreLocals_wellFormed
            initializedWellFormed completedWellFormed
      have afterRepresented : Representation layout localCell afterWorld
          (Env.pop extendedEnvironment) after := by
        refine {
          worldOwned := ?_
          localOwned := ?_
          localCellsInjective := initializedRepresented.localCellsInjective
          worldLocalsDisjoint := ?_
        }
        · intro cell values found
          simpa [after, restoreLocals, State.cellEntry?] using
            completedRepresented.worldOwned cell values found
        · intro index
          let lifted : Fin (branchArity + 1) :=
            ⟨index.val, Nat.lt_succ_of_lt index.isLt⟩
          have owned := completedRepresented.localOwned lifted
          constructor
          · simpa [after, restoreLocals, State.cellId?] using
              (initializedRepresented.localOwned index).1
          · simpa [after, restoreLocals, State.cellEntry?, boundCells,
              pushCells, lifted, Env.pop] using owned.2
        · intro cell worldMember localMember
          exact completedRepresented.worldLocalsDisjoint cell worldMember (by
            obtain ⟨index, same⟩ := localMember
            let lifted : Fin (branchArity + 1) :=
              ⟨index.val, Nat.lt_succ_of_lt index.isLt⟩
            exact ⟨lifted, by
              simpa [boundCells, pushCells, lifted] using same⟩)
      exact ⟨after, executesLetLocal initializerExecution bodyExecution,
        afterWellFormed, afterRepresented,
        (initializerEffect.weaken CellSet.empty_subset).trans_same scopeEffect⟩
  case setLocal =>
      intro _beforeWorld _arity _beforeEnvironment _value _result _afterWorld
        target valueResult free frontier layout state localCell nextLocal
        represented below wellFormed localsFresh nextFresh
      obtain ⟨afterRight, rightExecution, rightWellFormed, rightRepresented,
          rightEffect⟩ :=
        termSoundness operations wellFormed represented valueResult
      obtain ⟨after, execution, afterWellFormed, afterRepresented, effect⟩ :=
        represented.setLocalAfterTerm rightRepresented rightExecution
          rightWellFormed rightEffect
      exact ⟨after, executesExpression execution, afterWellFormed,
        afterRepresented, effect.weaken (by
          intro cell member
          rcases member with impossible | written
          · exact False.elim impossible
          · simp [CellSet.singleton] at written
            subst cell
            exact localsFresh target)⟩
  case updateLocal =>
      intro _beforeWorld _arity _beforeEnvironment _value _right _afterWorld
        operation target _result valueResult updateResult free frontier layout
        state localCell nextLocal represented below wellFormed localsFresh
        nextFresh
      obtain ⟨afterRight, rightExecution, rightWellFormed, rightRepresented,
          rightEffect⟩ :=
        termSoundness operations wellFormed represented valueResult
      obtain ⟨after, execution, afterWellFormed, afterRepresented, effect⟩ :=
        represented.updateLocalAfterTerm rightRepresented rightExecution
          rightWellFormed rightEffect updateResult
      exact ⟨after, executesExpression execution, afterWellFormed,
        afterRepresented, effect.weaken (by
          intro cell member
          rcases member with impossible | written
          · exact False.elim impossible
          · simp [CellSet.singleton] at written
            subst cell
            exact localsFresh target)⟩
  case action =>
      intro _beforeWorld _arity _beforeEnvironment operation _afterWorld
        actionResult free
      simp [actionFree] at free
  case ifTrue =>
      intro _beforeWorld _arity _beforeEnvironment _condition _conditionWorld
        thenBranch _completion _afterWorld _afterEnvironment elseBranch
        conditionResult _branchResult induction free frontier layout state
        localCell nextLocal represented below wellFormed localsFresh nextFresh
      simp only [actionFree, Bool.and_eq_true] at free
      obtain ⟨conditionState, conditionExecution, conditionWellFormed,
          conditionRepresented, conditionEffect⟩ :=
        termSoundness operations wellFormed represented conditionResult
      obtain ⟨after, branchExecution, afterWellFormed, afterRepresented,
          branchEffect⟩ :=
        induction free.1 conditionRepresented below conditionWellFormed
          localsFresh (Nat.le_trans nextFresh conditionEffect.nextCell)
      exact ⟨after, executesIfTrue conditionExecution branchExecution,
        afterWellFormed, afterRepresented,
        (conditionEffect.weaken CellSet.empty_subset).trans_same branchEffect⟩
  case ifFalse =>
      intro _beforeWorld _arity _beforeEnvironment _condition _conditionWorld
        elseBranch _completion _afterWorld _afterEnvironment thenBranch
        conditionResult _branchResult induction free frontier layout state
        localCell nextLocal represented below wellFormed localsFresh nextFresh
      simp only [actionFree, Bool.and_eq_true] at free
      obtain ⟨conditionState, conditionExecution, conditionWellFormed,
          conditionRepresented, conditionEffect⟩ :=
        termSoundness operations wellFormed represented conditionResult
      obtain ⟨after, branchExecution, afterWellFormed, afterRepresented,
          branchEffect⟩ :=
        induction free.2 conditionRepresented below conditionWellFormed
          localsFresh (Nat.le_trans nextFresh conditionEffect.nextCell)
      exact ⟨after, executesIfFalse conditionExecution branchExecution,
        afterWellFormed, afterRepresented,
        (conditionEffect.weaken CellSet.empty_subset).trans_same branchEffect⟩
  case whileFalse =>
      intro _beforeWorld _arity _beforeEnvironment _condition _afterWorld body
        conditionResult free frontier layout state localCell nextLocal
        represented below wellFormed localsFresh nextFresh
      obtain ⟨after, conditionExecution, afterWellFormed, afterRepresented,
          conditionEffect⟩ :=
        termSoundness operations wellFormed represented conditionResult
      exact ⟨after, executesWhileFalse conditionExecution, afterWellFormed,
        afterRepresented, conditionEffect.weaken CellSet.empty_subset⟩
  case whileNext =>
      intro _beforeWorld _arity _beforeEnvironment _condition _conditionWorld
        body _bodyWorld _bodyEnvironment _completion _afterWorld
        _afterEnvironment conditionResult _bodyResult _restResult bodyInduction
        restInduction free frontier layout state localCell nextLocal represented
        below wellFormed localsFresh nextFresh
      simp only [actionFree] at free
      obtain ⟨conditionState, conditionExecution, conditionWellFormed,
          conditionRepresented, conditionEffect⟩ :=
        termSoundness operations wellFormed represented conditionResult
      obtain ⟨middle, bodyExecution, middleWellFormed, middleRepresented,
          bodyEffect⟩ := bodyInduction free conditionRepresented below
        conditionWellFormed localsFresh
        (Nat.le_trans nextFresh conditionEffect.nextCell)
      obtain ⟨after, restExecution, afterWellFormed, afterRepresented,
          restEffect⟩ := restInduction free middleRepresented below
        middleWellFormed localsFresh
        (Nat.le_trans nextFresh
          (Nat.le_trans conditionEffect.nextCell bodyEffect.nextCell))
      exact ⟨after,
        executesWhileTrueThen conditionExecution bodyExecution restExecution,
        afterWellFormed, afterRepresented,
        (conditionEffect.weaken CellSet.empty_subset).trans_same
          (bodyEffect.trans_same restEffect)⟩
  case whileContinue =>
      intro _beforeWorld _arity _beforeEnvironment _condition _conditionWorld
        body _bodyWorld _bodyEnvironment _completion _afterWorld
        _afterEnvironment conditionResult _bodyResult _restResult bodyInduction
        restInduction free frontier layout state localCell nextLocal represented
        below wellFormed localsFresh nextFresh
      simp only [actionFree] at free
      obtain ⟨conditionState, conditionExecution, conditionWellFormed,
          conditionRepresented, conditionEffect⟩ :=
        termSoundness operations wellFormed represented conditionResult
      obtain ⟨middle, bodyExecution, middleWellFormed, middleRepresented,
          bodyEffect⟩ := bodyInduction free conditionRepresented below
        conditionWellFormed localsFresh
        (Nat.le_trans nextFresh conditionEffect.nextCell)
      obtain ⟨after, restExecution, afterWellFormed, afterRepresented,
          restEffect⟩ := restInduction free middleRepresented below
        middleWellFormed localsFresh
        (Nat.le_trans nextFresh
          (Nat.le_trans conditionEffect.nextCell bodyEffect.nextCell))
      exact ⟨after,
        executesWhileContinueThen conditionExecution bodyExecution restExecution,
        afterWellFormed, afterRepresented,
        (conditionEffect.weaken CellSet.empty_subset).trans_same
          (bodyEffect.trans_same restEffect)⟩
  case whileBreak =>
      intro _beforeWorld _arity _beforeEnvironment _condition _conditionWorld
        body _afterWorld _afterEnvironment conditionResult _bodyResult induction
        free frontier layout state localCell nextLocal represented below
        wellFormed localsFresh nextFresh
      simp only [actionFree] at free
      obtain ⟨conditionState, conditionExecution, conditionWellFormed,
          conditionRepresented, conditionEffect⟩ :=
        termSoundness operations wellFormed represented conditionResult
      obtain ⟨after, bodyExecution, afterWellFormed, afterRepresented,
          bodyEffect⟩ := induction free conditionRepresented below
        conditionWellFormed localsFresh
        (Nat.le_trans nextFresh conditionEffect.nextCell)
      exact ⟨after, executesWhileBreak conditionExecution bodyExecution,
        afterWellFormed, afterRepresented,
        (conditionEffect.weaken CellSet.empty_subset).trans_same bodyEffect⟩
  case whileReturn =>
      intro _beforeWorld _arity _beforeEnvironment _condition _conditionWorld
        body _value _afterWorld _afterEnvironment conditionResult _bodyResult
        induction free frontier layout state localCell nextLocal represented
        below wellFormed localsFresh nextFresh
      simp only [actionFree] at free
      obtain ⟨conditionState, conditionExecution, conditionWellFormed,
          conditionRepresented, conditionEffect⟩ :=
        termSoundness operations wellFormed represented conditionResult
      obtain ⟨after, bodyExecution, afterWellFormed, afterRepresented,
          bodyEffect⟩ := induction free conditionRepresented below
        conditionWellFormed localsFresh
        (Nat.le_trans nextFresh conditionEffect.nextCell)
      exact ⟨after, executesWhileReturned conditionExecution bodyExecution,
        afterWellFormed, afterRepresented,
        (conditionEffect.weaken CellSet.empty_subset).trans_same bodyEffect⟩
  case returnNone =>
      intro _world _arity _environment free frontier layout state localCell
        nextLocal represented below wellFormed localsFresh nextFresh
      exact ⟨state, executesReturnNone program state, wellFormed, represented,
        (ModifiesOnly.refl state).weaken CellSet.empty_subset⟩
  case returnSome =>
      intro _beforeWorld _arity _beforeEnvironment _value _result _afterWorld
        valueResult free frontier layout state localCell nextLocal represented
        below wellFormed localsFresh nextFresh
      obtain ⟨after, valueExecution, afterWellFormed, afterRepresented,
          effect⟩ := termSoundness operations wellFormed represented valueResult
      exact ⟨after, executesReturnValue valueExecution, afterWellFormed,
        afterRepresented, effect.weaken CellSet.empty_subset⟩
  case breakLoop =>
      intro _world _arity _environment free frontier layout state localCell
        nextLocal represented below wellFormed localsFresh nextFresh
      exact ⟨state, executesBreak program state, wellFormed, represented,
        (ModifiesOnly.refl state).weaken CellSet.empty_subset⟩
  case continueLoop =>
      intro _world _arity _environment free frontier layout state localCell
        nextLocal represented below wellFormed localsFresh nextFresh
      exact ⟨state, executesContinue program state, wellFormed, represented,
        (ModifiesOnly.refl state).weaken CellSet.empty_subset⟩
  case t => exact evaluated

end Lanius.FunctionalView.FreshSimulation
