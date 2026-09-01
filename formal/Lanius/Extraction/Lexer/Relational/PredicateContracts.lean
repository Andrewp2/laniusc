import Lanius.Extraction.Lexer.Relational.SourceMemory
import Lanius.Extraction.Lexer.Relational.Functions
import Lanius.Extraction.Lexer.Relational.PredicateSyntax
import Lanius.Extraction.Lexer.Relational.PredicatePure
import Lanius.Relational.Adequacy

namespace Lanius.Extraction.Lexer.Relational.PredicateContracts

open Lanius
open Lanius.CallContracts
open Lanius.Core
open Lanius.Semantics
open Lanius.Separation
open Lanius.Compiler.Lexer
open Lanius.Extraction
open Lanius.Extraction.Lexer
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.FreshSimulation
open Lanius.Relational
open Lanius.Relational.Semantics
open Lanius.Typing

/-- Shared source-level contract for a read-only byte predicate. -/
def contract (source : List Byte)
    (function : checkedFrontend.FnRef Functions.predicateSignature)
    (accept : Byte → Bool) :
    FnContract checkedFrontend Functions.predicateSignature function where
  Args := Byte
  Result := Bool
  AbstractState := ReadOnly.World × List Byte
  Pre := fun _ before => before.2 = source
  Post := fun byte result before after =>
    result = accept byte ∧ after = before
  Frame := fun before after => after = before
  encodeArgs := fun byte => [.signed .i32 (Int.ofNat byte.val)]
  encodeResult := Value.boolean
  encodeArgs_typed := by
    intro byte before _pre
    have targetEq : checkedFrontend.core.target = .x86_64 := by rfl
    exact .cons (.signed .i32 _ (by
      rw [targetEq]
      simp [signedMin, SignedIntTy.bits]) (by
      rw [targetEq]
      simp only [signedMax, SignedIntTy.bits]
      rw [Int.ofNat_eq_natCast]
      omega)) .nil
  encodeResult_typed := by
    intro _byte result _before _after _pre _post
    exact .boolean result
  AbstractStateRep := fun abstract world =>
    abstract.1 = world ∧
      world.i32Slice? 0 = some (SourceMemory.sourceIntegers abstract.2)

def identifier (source : List Byte) :=
  contract source Functions.isIdentifierContinue isIdentifierContinue

def whitespace (source : List Byte) :=
  contract source Functions.isWhitespace isWhitespace

private def callABI
    (source : List Byte)
    (function : checkedFrontend.FnRef Functions.predicateSignature)
    (accept : Byte → Bool)
    (term : PredicateSyntax.T)
    (reification : Reifies function (PredicateSyntax.command term))
    (layoutExact : reification.layout = identityLayout)
    (parameters : function.function.parameters = [(0, i32Type)]) :
    CallABI (contract source function accept) reification where
  environment := PredicateSyntax.environment
  proofWorld := fun _ _ beforeWorld => beforeWorld
  parametersBound := by
    intro byte
    rw [parameters]
    rfl
  projectCallee := by
    intro callerArity layout localCell callerEnvironment beforeWorld
      afterArguments byte abstractBefore pre abstractRep wellFormed represented
    have entered := represented.enterCallParameters wellFormed
      (environment := PredicateSyntax.environment byte)
    simpa [layoutExact] using entered

private theorem pureReturnsCorrectly
    (source : List Byte)
    (function : checkedFrontend.FnRef Functions.predicateSignature)
    (accept : Byte → Bool)
    (term : PredicateSyntax.T)
    (reification : Reifies function (PredicateSyntax.command term))
    (layoutExact : reification.layout = identityLayout)
    (adapterExact : reification.adapter = actionAdapter)
    (parameters : function.function.parameters = [(0, i32Type)])
    (free : FunctionalView.Core.Effectful.termCallFree term = true)
    (evaluates : ∀ world byte,
      FunctionalView.Term.evaluate (ReadOnly.machine checkedFrontend.core)
        world (PredicateSyntax.environment byte) term =
        .ok (.boolean (accept byte), world)) :
    ReturnsCorrectly (contract source function accept) := by
  let adequate : RelationalSuccessfulCoreRefinement reification
      PredicatePure.registry PredicatePure.Admissible := by
    apply RelationalSuccessfulCoreRefinement.structuralWhen reification
      adapterExact
      (PredicateSyntax.command_actionFree term)
    refine CoreReflection.CommandReflectsWhen.sequence
      (CoreReflection.CommandReflectsWhen.returnSome
        (PredicatePure.reflects term accept free evaluates)) ?_
      (CoreReflection.CommandReflectsWhen.ofLeaves
        (CoreReflection.CommandLeaves.skip))
    intro world environment input
    intro completion afterWorld afterEnvironment evaluated next
    trivial
  apply ReturnsCorrectly.ofRelationalReadOnlyWP reification
    (callABI source function accept term reification layoutExact parameters)
    (by simp [Functions.predicateSignature]) adequate
  · intro byte abstractBefore beforeWorld pre abstractRep
    exact ⟨byte, rfl⟩
  · intro byte result abstractBefore abstractAfter beforeWorld pre
      abstractBeforeRep post frame
    exact frame ▸ abstractBeforeRep
  · intro byte abstractBefore beforeWorld pre abstractBeforeRep
    apply SemanticWP.Command.sequence
    apply SemanticWP.Command.returnSome
    intro value afterWorld termEvaluated
    obtain ⟨valueEq, worldEq⟩ :=
      PredicatePure.term_wp term accept free evaluates beforeWorld byte
        value afterWorld termEvaluated
    subst value
    subst afterWorld
    exact ⟨accept byte, abstractBefore, rfl, rfl, abstractBeforeRep,
      ⟨rfl, rfl⟩, rfl⟩

theorem identifierStart_returnsCorrectly (source : List Byte) :
    ReturnsCorrectly
      (contract source Functions.isIdentifierStart isIdentifierStart) := by
  exact pureReturnsCorrectly source Functions.isIdentifierStart
    isIdentifierStart PredicateSyntax.identifierStartTerm
    PredicateSyntax.identifierStartReification (by rfl) (by rfl) (by rfl)
    PredicateSyntax.identifierStart_callFree
    PredicatePure.identifierStart_evaluates

theorem decimalDigit_returnsCorrectly (source : List Byte) :
    ReturnsCorrectly
      (contract source Functions.isDecimalDigit isDecimalDigit) := by
  exact pureReturnsCorrectly source Functions.isDecimalDigit isDecimalDigit
    PredicateSyntax.decimalDigitTerm PredicateSyntax.decimalDigitReification
    (by rfl) (by rfl) (by rfl) PredicateSyntax.decimalDigit_callFree
    PredicatePure.decimalDigit_evaluates

theorem whitespace_returnsCorrectly (source : List Byte) :
    ReturnsCorrectly (whitespace source) := by
  exact pureReturnsCorrectly source Functions.isWhitespace isWhitespace
    PredicateSyntax.whitespaceTerm PredicateSyntax.whitespaceReification
    (by rfl) (by rfl) (by rfl) PredicateSyntax.whitespace_callFree
    PredicatePure.whitespace_evaluates

private def identifierRegistry (source : List Byte) : OperationRegistry :=
  OperationRegistry.readOnly fun world candidate arguments value afterWorld =>
    (candidate = Functions.isIdentifierStart.function.id ∧
      (contract source Functions.isIdentifierStart isIdentifierStart).AllowsCall
        world arguments value afterWorld) ∨
    (candidate = Functions.isDecimalDigit.function.id ∧
      (contract source Functions.isDecimalDigit isDecimalDigit).AllowsCall
        world arguments value afterWorld)

private def IdentifierAdmissible (source : List Byte)
    (world : ReadOnly.World) (environment : Env 1) : Prop :=
  ∃ byte : Byte,
    environment = PredicateSyntax.environment byte ∧
    world.i32Slice? 0 = some (SourceMemory.sourceIntegers source)

private theorem helperCall_reflects
    (source : List Byte)
    (function : checkedFrontend.FnRef Functions.predicateSignature)
    (accept : Byte → Bool)
    (correct : ReturnsCorrectly (contract source function accept))
    (included : ∀ world candidate arguments value afterWorld,
      (candidate = function.function.id ∧
        (contract source function accept).AllowsCall world arguments value
          afterWorld) →
      (identifierRegistry source).call world candidate arguments value
        afterWorld) :
    CoreReflection.TermReflectsWhen checkedFrontend.core
      (identifierRegistry source) (IdentifierAdmissible source)
      (PredicateSyntax.call function.function.id) := by
  intro layout localCell world environment before after frontier value
    wellFormed represented input actual
  obtain ⟨byte, rfl, sourceFound⟩ := input
  have argumentExecutable : FunctionalView.Term.evaluate
      (FunctionalView.Core.Effectful.machine checkedFrontend.core
        PredicatePure.rejectingCalls)
      world (PredicateSyntax.environment byte) PredicateSyntax.argument =
      .ok (.signed .i32 (Int.ofNat byte.val), world) := by
    rfl
  obtain ⟨afterArguments, argumentExecution, afterArgumentsWellFormed,
      afterArgumentsRepresented, argumentEffect⟩ :=
    FreshSimulation.termSoundness
      (FreshSimulation.operationSoundness checkedFrontend.core
        PredicatePure.rejectingCalls PredicatePure.rejectingCalls_sound)
      wellFormed represented argumentExecutable
  have argumentsExecution : ArgumentsEvaluateTo checkedFrontend.core before
      (Core.toCoreExprs layout [PredicateSyntax.argument])
      [.signed .i32 (Int.ofNat byte.val)] afterArguments :=
    by
      simpa only [Core.toCoreExprs] using
        ArgumentsEvaluateTo.singleton argumentExecution
  have abstractBeforeRep :
      (contract source function accept).AbstractStateRep (world, source) world :=
    ⟨rfl, sourceFound⟩
  have actualCall : Evaluates checkedFrontend.core before
      (.call function.function.id
        (Core.toCoreExprs layout [PredicateSyntax.argument])) value after := by
    simpa only [PredicateSyntax.call, Core.apply, Core.toCoreExpr,
      Core.Operation.toCoreExpr] using actual
  obtain ⟨result, abstractAfter, afterWorld, valueEq, abstractAfterRep,
      post, frame, afterWellFormed, afterRepresented, effect⟩ :=
    correct byte (world, source) rfl abstractBeforeRep
      afterArgumentsWellFormed afterArgumentsRepresented argumentsExecution
      argumentEffect actualCall
  refine ⟨afterWorld, ?_, afterWellFormed, afterRepresented,
    effect.weaken CellSet.empty_subset⟩
  apply TermEvaluates.apply
  · exact .cons (.reference _) .nil
  · change (identifierRegistry source).call world function.function.id
      [.signed .i32 (Int.ofNat byte.val)] value afterWorld
    apply included
    exact ⟨rfl, byte, (world, source), result, abstractAfter, rfl, valueEq,
      rfl, abstractBeforeRep, post, frame, abstractAfterRep⟩

private theorem identifierStartCall_reflects (source : List Byte) :
    CoreReflection.TermReflectsWhen checkedFrontend.core
      (identifierRegistry source) (IdentifierAdmissible source)
      (PredicateSyntax.call Functions.isIdentifierStart.function.id) := by
  apply helperCall_reflects source Functions.isIdentifierStart
    isIdentifierStart (identifierStart_returnsCorrectly source)
  intro world candidate arguments value afterWorld related
  exact .inl related

private theorem decimalDigitCall_reflects (source : List Byte) :
    CoreReflection.TermReflectsWhen checkedFrontend.core
      (identifierRegistry source) (IdentifierAdmissible source)
      (PredicateSyntax.call Functions.isDecimalDigit.function.id) := by
  apply helperCall_reflects source Functions.isDecimalDigit isDecimalDigit
    (decimalDigit_returnsCorrectly source)
  intro world candidate arguments value afterWorld related
  exact .inr related

private theorem identifierStart_ne_decimalDigit :
    Functions.isIdentifierStart.function.id ≠
      Functions.isDecimalDigit.function.id := by
  decide +kernel

private theorem helperCall_result
    (source : List Byte)
    (function : checkedFrontend.FnRef Functions.predicateSignature)
    (accept : Byte → Bool)
    (select : ∀ world arguments value afterWorld,
      (identifierRegistry source).call world function.function.id arguments
          value afterWorld →
        (contract source function accept).AllowsCall world arguments value
          afterWorld)
    (world : ReadOnly.World) (byte : Byte)
    (evaluated : TermEvaluates
      ((identifierRegistry source).machine checkedFrontend.core)
      world (PredicateSyntax.environment byte)
      (PredicateSyntax.call function.function.id) value afterWorld) :
    value = .boolean (accept byte) ∧ afterWorld = world := by
  obtain ⟨values, afterArguments, argumentsResult, operationResult⟩ :=
    evaluated.applyInversion
  obtain ⟨argumentValue, tailValues, afterArgument, valuesEq,
      argumentResult, tailResult⟩ := argumentsResult.consInversion
  obtain ⟨tailValuesEq, afterArgumentsEq⟩ := tailResult.nilInversion
  obtain ⟨argumentValueEq, afterArgumentEq⟩ :=
    argumentResult.referenceInversion
  subst values
  subst tailValues
  subst argumentValue
  subst afterArgument
  subst afterArguments
  simp only [OperationRegistry.machine] at operationResult
  obtain ⟨argument, before, result, after, argumentsEq, valueEq, pre,
      beforeRep, post, frame, afterRep⟩ :=
    select world [.signed .i32 (Int.ofNat byte.val)] value afterWorld
      operationResult
  change [Value.signed .i32 (Int.ofNat byte.val)] =
    [Value.signed .i32 (Int.ofNat argument.val)] at argumentsEq
  change value = .boolean result at valueEq
  change before.2 = source at pre
  change before.1 = world ∧
    world.i32Slice? 0 = some (SourceMemory.sourceIntegers before.2) at beforeRep
  change result = accept argument ∧ after = before at post
  change after = before at frame
  change after.1 = afterWorld ∧
    afterWorld.i32Slice? 0 = some (SourceMemory.sourceIntegers after.2) at afterRep
  have byteValueEq : Int.ofNat byte.val = Int.ofNat argument.val := by
    simpa using argumentsEq
  have argumentEq : argument = byte := by
    apply Fin.ext
    exact Int.ofNat.inj byteValueEq |>.symm
  subst argument
  obtain ⟨resultEq, afterEq⟩ := post
  subst result
  subst after
  exact ⟨valueEq, afterRep.1.symm.trans beforeRep.1⟩

private theorem identifierStartCall_result
    (source : List Byte) (world : ReadOnly.World) (byte : Byte)
    (evaluated : TermEvaluates
      ((identifierRegistry source).machine checkedFrontend.core)
      world (PredicateSyntax.environment byte)
      (PredicateSyntax.call Functions.isIdentifierStart.function.id)
      value afterWorld) :
    value = .boolean (isIdentifierStart byte) ∧ afterWorld = world := by
  apply helperCall_result source Functions.isIdentifierStart isIdentifierStart
    (world := world) (byte := byte) (evaluated := evaluated)
  intro before arguments result after related
  change
    (Functions.isIdentifierStart.function.id =
        Functions.isIdentifierStart.function.id ∧
      (contract source Functions.isIdentifierStart isIdentifierStart).AllowsCall
        before arguments result after) ∨
    (Functions.isIdentifierStart.function.id =
        Functions.isDecimalDigit.function.id ∧
      (contract source Functions.isDecimalDigit isDecimalDigit).AllowsCall
        before arguments result after) at related
  rcases related with start | digit
  · exact start.2
  · exact (identifierStart_ne_decimalDigit digit.1).elim

private theorem decimalDigitCall_result
    (source : List Byte) (world : ReadOnly.World) (byte : Byte)
    (evaluated : TermEvaluates
      ((identifierRegistry source).machine checkedFrontend.core)
      world (PredicateSyntax.environment byte)
      (PredicateSyntax.call Functions.isDecimalDigit.function.id)
      value afterWorld) :
    value = .boolean (isDecimalDigit byte) ∧ afterWorld = world := by
  apply helperCall_result source Functions.isDecimalDigit isDecimalDigit
    (world := world) (byte := byte) (evaluated := evaluated)
  intro before arguments result after related
  change
    (Functions.isDecimalDigit.function.id =
        Functions.isIdentifierStart.function.id ∧
      (contract source Functions.isIdentifierStart isIdentifierStart).AllowsCall
        before arguments result after) ∨
    (Functions.isDecimalDigit.function.id =
        Functions.isDecimalDigit.function.id ∧
      (contract source Functions.isDecimalDigit isDecimalDigit).AllowsCall
        before arguments result after) at related
  rcases related with start | digit
  · exact (identifierStart_ne_decimalDigit start.1.symm).elim
  · exact digit.2

private theorem identifierContinue_reflects (source : List Byte) :
    CoreReflection.TermReflectsWhen checkedFrontend.core
      (identifierRegistry source) (IdentifierAdmissible source)
      PredicateSyntax.identifierContinueTerm := by
  intro layout localCell world environment before after frontier value
    wellFormed represented input actual
  obtain ⟨byte, rfl, sourceFound⟩ := input
  have actualOr : Evaluates checkedFrontend.core before
      (.binary .logicalOr
        (Core.toCoreExpr layout
          (PredicateSyntax.call Functions.isIdentifierStart.function.id))
        (Core.toCoreExpr layout
          (PredicateSyntax.call Functions.isDecimalDigit.function.id)))
      value after := by
    simpa only [PredicateSyntax.identifierContinueTerm, Core.logicalOr,
      Core.toCoreExpr] using actual
  rcases CoreSuccess.evaluatesLogicalOrInversion actualOr with
    trueBranch | falseBranch
  · obtain ⟨valueEq, startActual⟩ := trueBranch
    obtain ⟨afterWorld, startEvaluated, afterWellFormed, afterRepresented,
        effect⟩ :=
      identifierStartCall_reflects source (frontier := frontier) wellFormed
        represented ⟨byte, rfl, sourceFound⟩ startActual
    subst value
    exact ⟨afterWorld, .logicalOrTrue startEvaluated, afterWellFormed,
      afterRepresented, effect⟩
  · obtain ⟨middle, startActual, digitActual⟩ := falseBranch
    obtain ⟨middleWorld, startEvaluated, middleWellFormed,
        middleRepresented, startEffect⟩ :=
      identifierStartCall_reflects source (frontier := frontier) wellFormed
        represented ⟨byte, rfl, sourceFound⟩ startActual
    obtain ⟨_startValue, middleWorldEq⟩ :=
      identifierStartCall_result source world byte startEvaluated
    subst middleWorld
    obtain ⟨afterWorld, digitEvaluated, afterWellFormed, afterRepresented,
        digitEffect⟩ :=
      decimalDigitCall_reflects source (frontier := frontier) middleWellFormed
        middleRepresented ⟨byte, rfl, sourceFound⟩ digitActual
    exact ⟨afterWorld, .logicalOrFalse startEvaluated digitEvaluated,
      afterWellFormed, afterRepresented,
      startEffect.trans_same digitEffect⟩

private theorem identifierContinue_term_wp
    (source : List Byte) (world : ReadOnly.World) (byte : Byte) :
    SemanticWP.Term.WP
      ((identifierRegistry source).machine checkedFrontend.core)
      PredicateSyntax.identifierContinueTerm
      (fun value afterWorld =>
        value = .boolean (isIdentifierContinue byte) ∧ afterWorld = world)
      world (PredicateSyntax.environment byte) := by
  intro value afterWorld evaluated
  rcases evaluated.logicalOrInversion with trueBranch | falseBranch
  · obtain ⟨valueEq, startEvaluated⟩ := trueBranch
    obtain ⟨startValueEq, worldEq⟩ :=
      identifierStartCall_result source world byte startEvaluated
    have startTrue : isIdentifierStart byte = true := by
      exact (Value.boolean.inj startValueEq).symm
    exact ⟨by simpa [isIdentifierContinue, startTrue] using valueEq, worldEq⟩
  · obtain ⟨middleWorld, startEvaluated, digitEvaluated⟩ := falseBranch
    obtain ⟨startValueEq, middleWorldEq⟩ :=
      identifierStartCall_result source world byte startEvaluated
    have startFalse : isIdentifierStart byte = false := by
      exact (Value.boolean.inj startValueEq).symm
    subst middleWorld
    obtain ⟨digitValueEq, afterWorldEq⟩ :=
      decimalDigitCall_result source world byte digitEvaluated
    exact ⟨by
      simpa [isIdentifierContinue, startFalse] using digitValueEq,
      afterWorldEq⟩

theorem identifier_returnsCorrectly (source : List Byte) :
    ReturnsCorrectly (identifier source) := by
  let adequate : RelationalSuccessfulCoreRefinement
      PredicateSyntax.identifierContinueReification
      (identifierRegistry source) (IdentifierAdmissible source) := by
    apply RelationalSuccessfulCoreRefinement.structuralWhen
      PredicateSyntax.identifierContinueReification (by rfl)
      (PredicateSyntax.command_actionFree
        PredicateSyntax.identifierContinueTerm)
    refine CoreReflection.CommandReflectsWhen.sequence
      (CoreReflection.CommandReflectsWhen.returnSome
        (identifierContinue_reflects source)) ?_
      (CoreReflection.CommandReflectsWhen.ofLeaves
        CoreReflection.CommandLeaves.skip)
    intro world environment input
    intro completion afterWorld afterEnvironment evaluated next
    trivial
  apply ReturnsCorrectly.ofRelationalReadOnlyWP
    PredicateSyntax.identifierContinueReification
    (callABI source Functions.isIdentifierContinue isIdentifierContinue
      PredicateSyntax.identifierContinueTerm
      PredicateSyntax.identifierContinueReification (by rfl) (by rfl))
    (by simp [Functions.predicateSignature]) adequate
  · intro byte abstractBefore beforeWorld pre abstractBeforeRep
    refine ⟨byte, rfl, ?_⟩
    change beforeWorld.i32Slice? 0 =
      some (SourceMemory.sourceIntegers source)
    rw [← pre]
    exact abstractBeforeRep.2
  · intro byte result abstractBefore abstractAfter beforeWorld pre
      abstractBeforeRep post frame
    exact frame ▸ abstractBeforeRep
  · intro byte abstractBefore beforeWorld pre abstractBeforeRep
    apply SemanticWP.Command.sequence
    apply SemanticWP.Command.returnSome
    intro value afterWorld termEvaluated
    obtain ⟨valueEq, worldEq⟩ :=
      identifierContinue_term_wp source beforeWorld byte value afterWorld
        termEvaluated
    subst value
    subst afterWorld
    exact ⟨isIdentifierContinue byte, abstractBefore, rfl, rfl,
      abstractBeforeRep, ⟨rfl, rfl⟩, rfl⟩

def identifierEntry (source : List Byte) :
    SpecEntry Functions.isIdentifierContinue where
  contract := identifier source
  sound := identifier_returnsCorrectly source

def whitespaceEntry (source : List Byte) :
    SpecEntry Functions.isWhitespace where
  contract := whitespace source
  sound := whitespace_returnsCorrectly source

end Lanius.Extraction.Lexer.Relational.PredicateContracts
