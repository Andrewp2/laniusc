import Lanius.Extraction.Lexer.Scanners
import Lanius.Extraction.Lexer.ScanEnd
import Lanius.Extraction.Lexer.ScanEndCalls
import Lanius.FunctionalViewLoop
import Lanius.FunctionalViewCoreEffectfulStateful
import Lanius.FunctionalViewRenaming
import Lanius.FunctionalViewCoreCallFrame

namespace Lanius.Extraction.Lexer.Quoted

open Lanius
open Lanius.Core
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.CallContracts
open Lanius.Compiler.Lexer
open Lanius.Compiler.Lexer.Program
open Lanius.Extraction
open Lanius.Extraction.Lexer
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Stateful
open Lanius.FunctionalView.Stateful.Loop

private def constructorBindings (offset : Int) : List (VarId × Value) :=
  [(0, .signed .i32 offset)]

private def constructorCallee (state : State) (offset : Int) : State :=
  enterCall state (constructorBindings offset)

private theorem constructorParameterBindings_eq (offset : Int) :
    parameterBindings (ScanEnd.offsetEnvironment offset) =
      constructorBindings offset := by
  rfl

private theorem constructorParametersBound (function : Function)
    (parameters : function.parameters = [(0, i32Type)]) (offset : Int) :
    bindParameters function.parameters [.signed .i32 offset] =
      some (constructorBindings offset) := by
  rw [parameters]
  rfl

private theorem constructorBody_executes (state : State) (offset : Int)
    (wellFormed : StateWellFormed state) (block : Block signature 1)
    (body : Stmt) (result : Value)
    (blockResult : Block.evaluate (machine verifiedFrontendLexerCore)
      ScanEnd.world (ScanEnd.offsetEnvironment offset) block =
      .done (.returned (some result)) ScanEnd.world)
    (bodyExact : Lanius.FunctionalView.Core.toCoreStmt
      identityLayout 1 block = body)
    (noLocals : localCapacity block = 0) :
    Executes verifiedFrontendLexerCore (constructorCallee state offset)
      body (.returned (some result)) (constructorCallee state offset) := by
  have environmentMatches : EnvironmentMatches
      (identityLayout (arity := 1)) (ScanEnd.offsetEnvironment offset)
      (constructorCallee state offset) := by
    simpa [constructorCallee, constructorParameterBindings_eq]
      using (enterCall_parameterBindings_matches
        (environment := ScanEnd.offsetEnvironment offset) wellFormed)
  have represents : World.Represents ScanEnd.world
      (constructorCallee state offset) := by
    intro cell contents found
    simp [ScanEnd.world] at found
  have sound := block_executes_without_locals
    (nextLocal := 1) (ReadOnly.bridge verifiedFrontendLexerCore) represents
    environmentMatches noLocals blockResult
  rw [bodyExact] at sound
  exact sound.1

private theorem successfulBody_executes (state : State) (offset : Int)
    (wellFormed : StateWellFormed state) :
    Executes verifiedFrontendLexerCore (constructorCallee state offset)
      (Functions.functionBody Functions.successfulScanFunction)
      (.returned (some (ScanEnd.value true offset 0)))
      (constructorCallee state offset) := by
  exact constructorBody_executes state offset wellFormed
    Functions.successfulScanBlock (Functions.functionBody
      Functions.successfulScanFunction) (ScanEnd.value true offset 0)
    (ScanEnd.successfulScanBlock_evaluates offset)
    Functions.successfulScanBlock_toCore_exactly (by rfl)

private theorem failedBody_executes (state : State) (offset : Int)
    (wellFormed : StateWellFormed state) :
    Executes verifiedFrontendLexerCore (constructorCallee state offset)
      (Functions.functionBody Functions.failedScanFunction)
      (.returned (some (ScanEnd.value false 0 offset)))
      (constructorCallee state offset) := by
  exact constructorBody_executes state offset wellFormed
    Functions.failedScanBlock (Functions.functionBody Functions.failedScanFunction)
    (ScanEnd.value false 0 offset) (ScanEnd.failedScanBlock_evaluates offset)
    Functions.failedScanBlock_toCore_exactly (by rfl)

private theorem scanCall_contract
    (function : Function) (body : Stmt) (result : Value)
    (functionFound : verifiedFrontendLexerCore.function? function.id = some function)
    (parameters : function.parameters = [(0, i32Type)])
    (bodyFound : function.body = some body)
    (before afterArguments : State) (arguments : List Expr) (offset : Int)
    (afterArgumentsWellFormed : StateWellFormed afterArguments)
    (argumentsResult : ArgumentsEvaluateTo verifiedFrontendLexerCore before
      arguments [.signed .i32 offset] afterArguments)
    (bodyExecution : Executes verifiedFrontendLexerCore
      (constructorCallee afterArguments offset) body
      (.returned (some result)) (constructorCallee afterArguments offset)) :
    let callee := constructorCallee afterArguments offset
    let after := restoreLocals afterArguments callee
    Evaluates verifiedFrontendLexerCore before
      (.call function.id arguments) result after ∧
    ModifiesOnly CellSet.empty afterArguments after ∧
    StateWellFormed after := by
  let callee := constructorCallee afterArguments offset
  let after := restoreLocals afterArguments callee
  have evaluation : Evaluates verifiedFrontendLexerCore before
      (.call function.id arguments) result after := by
    apply evaluatesCallReturned (body := body) argumentsResult functionFound
      (constructorParametersBound function parameters offset) bodyFound
    simpa [callee, constructorCallee] using bodyExecution
  have entered : StoreEffect CellSet.empty afterArguments callee := by
    simpa [callee, constructorCallee] using
      (enterCall_effect afterArguments (constructorBindings offset))
  have calleeWellFormed : StateWellFormed callee := by
    simpa [callee, constructorCallee] using
      (enterCall_preserves_wellFormed
        (bindings := constructorBindings offset) afterArgumentsWellFormed)
  exact ⟨evaluation, by simpa [after] using entered.restoreLocals,
    entered.restoreLocals_wellFormed afterArgumentsWellFormed calleeWellFormed⟩

theorem successfulScanCall_contract
    (before afterArguments : State) (arguments : List Expr) (offset : Int)
    (afterArgumentsWellFormed : StateWellFormed afterArguments)
    (argumentsResult : ArgumentsEvaluateTo verifiedFrontendLexerCore before
      arguments [.signed .i32 offset] afterArguments) :
    let callee := constructorCallee afterArguments offset
    let after := restoreLocals afterArguments callee
    Evaluates verifiedFrontendLexerCore before
      (.call Functions.successfulScanFunction.id arguments)
      (ScanEnd.value true offset 0) after ∧
    ModifiesOnly CellSet.empty afterArguments after ∧
    StateWellFormed after := by
  exact scanCall_contract Functions.successfulScanFunction
    (Functions.functionBody Functions.successfulScanFunction)
    (ScanEnd.value true offset 0) (by rfl) (by rfl) (by rfl)
    before afterArguments arguments offset afterArgumentsWellFormed
    argumentsResult (successfulBody_executes afterArguments offset
      afterArgumentsWellFormed)

theorem failedScanCall_contract
    (before afterArguments : State) (arguments : List Expr) (offset : Int)
    (afterArgumentsWellFormed : StateWellFormed afterArguments)
    (argumentsResult : ArgumentsEvaluateTo verifiedFrontendLexerCore before
      arguments [.signed .i32 offset] afterArguments) :
    let callee := constructorCallee afterArguments offset
    let after := restoreLocals afterArguments callee
    Evaluates verifiedFrontendLexerCore before
      (.call Functions.failedScanFunction.id arguments)
      (ScanEnd.value false 0 offset) after ∧
    ModifiesOnly CellSet.empty afterArguments after ∧
    StateWellFormed after := by
  exact scanCall_contract Functions.failedScanFunction
    (Functions.functionBody Functions.failedScanFunction)
    (ScanEnd.value false 0 offset) (by rfl) (by rfl) (by rfl)
    before afterArguments arguments offset afterArgumentsWellFormed
    argumentsResult (failedBody_executes afterArguments offset
      afterArgumentsWellFormed)

theorem scanEndCallSoundness :
    Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness
      verifiedFrontendLexerCore ScanEndCalls.calls := by
  constructor
  · intro arity layout localCell beforeWorld afterWorld environment before
      afterArguments function arguments values value argumentWrites
      afterArgumentsWellFormed represented argumentsExecution argumentsEffect
      evaluated
    have preserve :
        ∀ (after : State),
          ModifiesOnly CellSet.empty afterArguments after →
          Representation layout localCell beforeWorld environment after := by
      intro after callEffect
      exact {
        worldOwned := callEffect.empty_preserves_assertion
          afterArgumentsWellFormed (World.owns beforeWorld)
          represented.worldOwned
        localOwned := fun index => callEffect.empty_preserves_assertion
          afterArgumentsWellFormed
          (Assertion.localPointsTo (layout index) (localCell index)
            (some (environment index))) (represented.localOwned index)
        localCellsInjective := represented.localCellsInjective
        worldLocalsDisjoint := represented.worldLocalsDisjoint
      }
    rcases ScanEndCalls.calls_success evaluated with
      ⟨offset, functionEq, valuesEq, valueEq, worldEq⟩ |
      ⟨offset, functionEq, valuesEq, valueEq, worldEq⟩
    · subst function
      subst values
      subst value
      subst afterWorld
      obtain ⟨callExecution, callEffect, afterWellFormed⟩ :=
        successfulScanCall_contract before afterArguments
          (toCoreExprs layout arguments) offset afterArgumentsWellFormed
          argumentsExecution
      let after := restoreLocals afterArguments
        (constructorCallee afterArguments offset)
      exact ⟨after, CellSet.union argumentWrites CellSet.empty, callExecution,
        afterWellFormed, preserve after callEffect,
        argumentsEffect.trans callEffect⟩
    · subst function
      subst values
      subst value
      subst afterWorld
      obtain ⟨callExecution, callEffect, afterWellFormed⟩ :=
        failedScanCall_contract before afterArguments
          (toCoreExprs layout arguments) offset afterArgumentsWellFormed
          argumentsExecution
      let after := restoreLocals afterArguments
        (constructorCallee afterArguments offset)
      exact ⟨after, CellSet.union argumentWrites CellSet.empty, callExecution,
        afterWellFormed, preserve after callEffect,
        argumentsEffect.trans callEffect⟩
  · intro beforeWorld afterWorld function values value evaluated cell
    rcases ScanEndCalls.calls_success evaluated with
      ⟨offset, functionEq, valuesEq, valueEq, worldEq⟩ |
      ⟨offset, functionEq, valuesEq, valueEq, worldEq⟩
    · subst afterWorld
      rfl
    · subst afterWorld
      rfl

/-! ## The extracted quoted scanner -/

private abbrev T (arity : Nat) := Term signature arity
private abbrev C (arity : Nat) := Command signature actions arity

private def quotedSource : T 6 := reference ⟨0, by omega⟩
private def quotedBound : T 6 := reference ⟨1, by omega⟩
private def quotedOffset : T 6 := reference ⟨4, by omega⟩

private def quotedLiteral (value : Nat) : T 6 :=
  literal (.signed .i32 (Int.ofNat value))

private def quotedBeforeEnd : T 6 :=
  apply (.binary .less i32Type i32Type (.scalar .bool))
    [quotedOffset, quotedBound]

private def quotedCurrentByte : T 6 :=
  apply (.index (.slice i32Type) i32Type i32Type)
    [quotedSource, quotedOffset]

private def setEscaping (value : Bool) : C 7 :=
  .updateLocal .set ⟨5, by omega⟩ (literal (.boolean value))

private def incrementOffset : C 7 :=
  .updateLocal .add ⟨4, by omega⟩
    (literal (.signed .i32 1))

private def byteEqualsLiteral (value : Nat) : T 7 :=
  apply (.binary .equal i32Type i32Type (.scalar .bool))
    [reference ⟨6, by omega⟩,
      literal (.signed .i32 (Int.ofNat value))]

private def byteEqualsDelimiter : T 7 :=
  apply (.binary .equal i32Type i32Type (.scalar .bool))
    [reference ⟨6, by omega⟩, reference ⟨3, by omega⟩]

private def failedAtOffset : T 7 :=
  apply (.call Functions.failedScanFunction.id [i32Type] (.structure 0))
    [reference ⟨4, by omega⟩]

private def successfulAfterByte : T 7 :=
  apply (.call Functions.successfulScanFunction.id [i32Type] (.structure 0))
    [apply (.binary .add i32Type i32Type i32Type)
      [reference ⟨4, by omega⟩,
        literal (.signed .i32 1)]]

private def unescapedBody : C 7 :=
  .sequence
    (.ifThenElse (byteEqualsLiteral 10)
      (.sequence (.returnValue (some failedAtOffset)) .skip)
      .skip)
    (.sequence
      (.ifThenElse byteEqualsDelimiter
        (.sequence (.returnValue (some successfulAfterByte)) .skip)
        .skip)
      (.sequence
        (.ifThenElse (byteEqualsLiteral 92)
          (.sequence (setEscaping true) .skip)
          .skip)
        (.sequence incrementOffset .skip)))

private def quotedLoopCommand : C 7 :=
  .sequence
    (.ifThenElse (reference ⟨5, by omega⟩)
      (.sequence
        (setEscaping false)
        (.sequence incrementOffset .skip))
      unescapedBody)
    .skip

private def quotedLoopBody : C 6 :=
  .letValue i32Type quotedCurrentByte quotedLoopCommand

private def quotedLoop : C 6 :=
  .whileLoop quotedBeforeEnd quotedLoopBody

private def failedAtBound : T 6 :=
  apply (.call Functions.failedScanFunction.id [i32Type] (.structure 0))
    [quotedBound]

private def quotedInitializer : T 4 :=
  apply (.binary .add i32Type i32Type i32Type)
    [reference ⟨2, by omega⟩,
      literal (.signed .i32 1)]

private def quotedCommand : C 4 :=
  .letValue i32Type quotedInitializer
    (.letValue (.scalar .bool) (literal (.boolean false))
      (.sequence quotedLoop
        (.sequence (.returnValue (some failedAtBound)) .skip)))

theorem quotedCommand_toCore_exactly :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      identityLayout 4 quotedCommand = Scanners.scanQuotedEndBody := by
  rfl

def quotedView := {
  Scanners.scanQuotedEndView with
  command := quotedCommand
  toCoreExactly := quotedCommand_toCore_exactly
}

private def sourceIntegers (source : List Byte) : List Int :=
  source.map fun byte => Int.ofNat byte.val

private def world (source : List Byte) :=
  World.singleton 0 (sourceIntegers source)

private abbrev termMachine :=
  Lanius.FunctionalView.Core.Effectful.machine
    verifiedFrontendLexerCore ScanEndCalls.calls

private abbrev statefulMachine :=
  Stateful.machineWith verifiedFrontendLexerCore
    (Lanius.FunctionalView.Core.Effectful.evaluateOperation
      verifiedFrontendLexerCore ScanEndCalls.calls)

private abbrev Runs (before : Runtime termMachine arity)
    (command : C arity) (completion : Stateful.Completion)
    (after : Runtime termMachine arity) : Prop :=
  Command.Evaluates termMachine statefulMachine before.world before.environment
    command completion after.world after.environment

private abbrev Returns (before : Runtime termMachine arity)
    (term : T arity) (value : Value) : Prop :=
  Term.evaluate termMachine before.world before.environment term =
    .ok (value, before.world)

private def runtime (source : List Byte) (start : Nat) (delimiter : Byte)
    (offset : Nat) (escaping : Bool) : Runtime termMachine 6 :=
  (world source, fun
    | ⟨0, _⟩ => .slice i32Type 0 [] 0 source.length
    | ⟨1, _⟩ => .signed .i32 (Int.ofNat source.length)
    | ⟨2, _⟩ => .signed .i32 (Int.ofNat start)
    | ⟨3, _⟩ => .signed .i32 (Int.ofNat delimiter.val)
    | ⟨4, _⟩ => .signed .i32 (Int.ofNat offset)
    | ⟨5, _⟩ => .boolean escaping)

@[simp] private theorem runtime_world :
    (runtime source start delimiter offset escaping).world = world source := rfl

@[simp] private theorem sourceIntegers_length :
    (sourceIntegers source).length = source.length := by
  simp [sourceIntegers]

private theorem beforeEnd_evaluates (source : List Byte) (start : Nat)
    (delimiter : Byte) (offset : Nat) (escaping : Bool) :
      Returns (runtime source start delimiter offset escaping) quotedBeforeEnd
      (.boolean (decide (offset < source.length))) := by
  unfold Returns
  rw [Effectful.Term.evaluate_eq_readOnly_of_callFree
    (program := verifiedFrontendLexerCore) (calls := ScanEndCalls.calls)
    quotedBeforeEnd (by decide +kernel)]
  exact ReadOnly.Term.evaluate_i32_less (leftValue := offset) (rightValue := source.length) rfl rfl

private theorem currentByte_evaluates (source : List Byte) (start : Nat)
    (delimiter : Byte) (offset : Nat) (escaping : Bool)
    (byte : Byte) (inBounds : offset < source.length)
    (byteEq : byte = source.get ⟨offset, inBounds⟩) :
    Returns (runtime source start delimiter offset escaping) quotedCurrentByte
      (.signed .i32 (Int.ofNat byte.val)) := by
  unfold Returns
  rw [Effectful.Term.evaluate_eq_readOnly_of_callFree
    (program := verifiedFrontendLexerCore) (calls := ScanEndCalls.calls)
    quotedCurrentByte (by decide +kernel)]
  simpa [quotedCurrentByte, Lanius.FunctionalView.Core.apply, i32Type,
    runtime_world, byteEq] using
    (ReadOnly.Term.evaluate_i32_index_map
      (program := verifiedFrontendLexerCore) (world := world source)
      (environment := (runtime source start delimiter offset escaping).environment)
      (base := quotedSource) (index := quotedOffset)
      (baseType := .slice i32Type) (indexType := i32Type)
      (elementType := i32Type) (cell := 0) (values := source)
      (encode := fun byte => Int.ofNat byte.val) (position := offset)
      (by
        apply Term.evaluate_slot
        rfl) (by rfl)
      (by simp [world, sourceIntegers])
      (by simpa [sourceIntegers] using inBounds))

private def loopRuntime (source : List Byte) (start : Nat) (delimiter : Byte)
    (offset : Nat) (escaping : Bool) (byte : Byte) : Runtime termMachine 7 :=
  ((runtime source start delimiter offset escaping).world,
    (runtime source start delimiter offset escaping).environment.push
      (.signed .i32 (Int.ofNat byte.val)))

@[simp] private theorem loopRuntime_world :
    (loopRuntime source start delimiter offset escaping byte).world =
      world source := rfl

private theorem byteEqualsLiteral_evaluates (source : List Byte) (start : Nat)
    (delimiter byte : Byte) (offset expected : Nat) (escaping : Bool) :
    Returns (loopRuntime source start delimiter offset escaping byte)
      (byteEqualsLiteral expected)
      (.boolean (decide (byte.val = expected))) := by
  unfold Returns
  rw [Effectful.Term.evaluate_eq_readOnly_of_callFree
    (program := verifiedFrontendLexerCore) (calls := ScanEndCalls.calls)
    (byteEqualsLiteral expected) (by rfl)]
  exact ReadOnly.Term.evaluate_i32_equal (leftValue := byte.val) (rightValue := expected) rfl rfl

private theorem byteEqualsDelimiter_evaluates (source : List Byte)
    (start : Nat) (delimiter byte : Byte) (offset : Nat) (escaping : Bool) :
    Returns (loopRuntime source start delimiter offset escaping byte)
      byteEqualsDelimiter (.boolean (decide (byte.val = delimiter.val))) := by
  unfold Returns
  rw [Effectful.Term.evaluate_eq_readOnly_of_callFree
    (program := verifiedFrontendLexerCore) (calls := ScanEndCalls.calls)
    byteEqualsDelimiter (by decide +kernel)]
  exact ReadOnly.Term.evaluate_i32_equal (leftValue := byte.val) (rightValue := delimiter.val) rfl rfl

private theorem successfulAfterByte_evaluates (source : List Byte)
    (start : Nat) (delimiter byte : Byte) (offset : Nat) (escaping : Bool)
    (bound : offset + 1 ≤ 2147483647) :
    Returns (loopRuntime source start delimiter offset escaping byte)
      successfulAfterByte (ScanEnd.value true (Int.ofNat (offset + 1)) 0) := by
  unfold Returns
  unfold successfulAfterByte apply
  apply Term.evaluate_apply1
  · calc
      _ = _ :=
        Effectful.Term.evaluate_eq_readOnly_of_callFree
          (program := verifiedFrontendLexerCore) (calls := ScanEndCalls.calls)
          _ (by decide +kernel)
      _ = _ := by
        exact ReadOnly.Term.evaluate_i32_add (leftValue := offset) (rightValue := 1) rfl rfl bound
  · exact ScanEndCalls.successful (world source) (Int.ofNat (offset + 1))

private theorem failedAtOffset_evaluates (source : List Byte) (start : Nat)
    (delimiter byte : Byte) (offset : Nat) (escaping : Bool) :
    Returns (loopRuntime source start delimiter offset escaping byte)
      failedAtOffset (ScanEnd.value false 0 (Int.ofNat offset)) := by
  unfold Returns
  unfold failedAtOffset apply
  apply Term.evaluate_apply1 (by rfl)
  exact ScanEndCalls.failed (world source) (Int.ofNat offset)

private theorem setEscaping_evaluates (source : List Byte) (start : Nat)
    (delimiter byte : Byte) (offset : Nat) (escaping value : Bool) :
    Runs (loopRuntime source start delimiter offset escaping byte)
      (setEscaping value) .next
      (loopRuntime source start delimiter offset value byte) := by
  unfold Runs
  have afterEnvironment :
      (loopRuntime source start delimiter offset value byte).environment =
        Env.set
          (loopRuntime source start delimiter offset escaping byte).environment
          ⟨5, by omega⟩ (.boolean value) := by
    exact Env.eq_ofFn rfl
  rw [afterEnvironment]
  apply Command.Evaluates.updateLocal (by rfl)
  rfl

private theorem incrementOffset_evaluates (source : List Byte) (start : Nat)
    (delimiter byte : Byte) (offset : Nat) (escaping : Bool)
    (bound : offset + 1 ≤ 2147483647) :
    Runs (loopRuntime source start delimiter offset escaping byte)
      incrementOffset .next
      (loopRuntime source start delimiter (offset + 1) escaping byte) := by
  unfold Runs
  have afterEnvironment :
      (loopRuntime source start delimiter (offset + 1) escaping byte).environment =
        Env.set
          (loopRuntime source start delimiter offset escaping byte).environment
          ⟨4, by omega⟩ (.signed .i32 (Int.ofNat (offset + 1))) := by
    exact Env.eq_ofFn rfl
  rw [afterEnvironment]
  apply Command.Evaluates.updateLocal (by rfl)
  change evalAssignValue verifiedFrontendLexerCore.target .add
    (some (.signed .i32 (Int.ofNat offset))) (.signed .i32 1) =
      .ok (.signed .i32 (Int.ofNat (offset + 1)))
  simp only [evalAssignValue, assignOpBinary?, evalBinaryValue,
    beq_self_eq_true, if_true, evalSignedBinary]
  rw [show Int.ofNat offset + 1 = Int.ofNat (offset + 1) by simp]
  rw [Lanius.Semantics.wrapSigned_i32_ofNat _ _ bound]

private theorem escapedBody_evaluates (source : List Byte) (start : Nat)
    (delimiter byte : Byte) (offset : Nat)
    (bound : offset + 1 ≤ 2147483647) :
    Runs (loopRuntime source start delimiter offset true byte)
      quotedLoopCommand .next
      (loopRuntime source start delimiter (offset + 1) false byte) := by
  apply Command.Evaluates.sequenceNext
  · apply Command.Evaluates.ifTrue (by rfl)
    apply Command.Evaluates.sequenceNext
    · exact setEscaping_evaluates source start delimiter byte offset true false
    · apply Command.Evaluates.sequenceNext
      · exact incrementOffset_evaluates source start delimiter byte offset false bound
      · exact .skip
  · exact .skip

private theorem unescapedNewline_evaluates (source : List Byte) (start : Nat)
    (delimiter byte : Byte) (offset : Nat) (newline : byte.val = 10) :
    Runs (loopRuntime source start delimiter offset false byte)
      quotedLoopCommand
      (.returned (some (ScanEnd.value false 0 (Int.ofNat offset))))
      (loopRuntime source start delimiter offset false byte) := by
  exact .sequenceStop
    (.ifFalse (by rfl)
      (.sequenceStop
        (.ifTrue (by
          simpa [Returns, newline, loopRuntime_world] using
            (byteEqualsLiteral_evaluates source start delimiter byte
              offset 10 false))
          (.sequenceStop
            (.returnSome (failedAtOffset_evaluates source start delimiter byte
              offset false))
            (by simp)))
        (by simp)))
    (by simp)

private theorem unescapedDelimiter_evaluates (source : List Byte) (start : Nat)
    (delimiter byte : Byte) (offset : Nat)
    (notNewline : byte.val ≠ 10) (isDelimiter : byte = delimiter)
    (bound : offset + 1 ≤ 2147483647) :
    Runs (loopRuntime source start delimiter offset false byte)
      quotedLoopCommand
      (.returned (some (ScanEnd.value true (Int.ofNat (offset + 1)) 0)))
      (loopRuntime source start delimiter offset false byte) := by
  exact .sequenceStop
    (.ifFalse (by rfl)
      (.sequenceNext
        (.ifFalse (by
          simpa [Returns, notNewline, loopRuntime_world] using
            (byteEqualsLiteral_evaluates source start delimiter byte
              offset 10 false))
          .skip)
        (.sequenceStop
          (.ifTrue (by
            subst byte
            simpa [Returns, loopRuntime_world] using
              (byteEqualsDelimiter_evaluates source start delimiter
                delimiter offset false))
            (.sequenceStop
              (.returnSome (successfulAfterByte_evaluates source start delimiter
                byte offset false bound))
              (by simp)))
          (by simp))))
    (by simp)

private theorem unescapedStep_evaluates (source : List Byte) (start : Nat)
    (delimiter byte : Byte) (offset : Nat) (nextEscaping : Bool)
    (notNewline : byte.val ≠ 10) (notDelimiter : byte ≠ delimiter)
    (sourceBound : source.length ≤ 2147483647)
    (inBounds : offset < source.length)
    (escapeCondition : decide (byte.val = 92) = nextEscaping) :
    Runs (loopRuntime source start delimiter offset false byte)
      quotedLoopCommand .next
      (loopRuntime source start delimiter (offset + 1) nextEscaping byte) := by
  have byteValuesDiffer : byte.val ≠ delimiter.val := by
    intro equal
    apply notDelimiter
    exact Fin.ext equal
  have escapeBranch : Runs
      (loopRuntime source start delimiter offset false byte)
      (.ifThenElse (byteEqualsLiteral 92)
        (.sequence (setEscaping true) .skip) .skip)
      .next
      (loopRuntime source start delimiter offset nextEscaping byte) := by
    cases nextEscaping with
    | false =>
        exact .ifFalse (by
          simpa [Returns, escapeCondition, loopRuntime_world] using
            (byteEqualsLiteral_evaluates source start delimiter byte
              offset 92 false))
          .skip
    | true =>
        apply Command.Evaluates.ifTrue (by
          simpa [Returns, escapeCondition, loopRuntime_world] using
            (byteEqualsLiteral_evaluates source start delimiter byte
              offset 92 false))
        apply Command.Evaluates.sequenceNext
        · exact setEscaping_evaluates source start delimiter byte offset false true
        · exact .skip
  have increment := incrementOffset_evaluates source start delimiter byte offset
    nextEscaping (Nat.le_trans (Nat.succ_le_of_lt inBounds) sourceBound)
  exact .sequenceNext
    (.ifFalse (by rfl)
      (.sequenceNext
        (.ifFalse (by
          simpa [Returns, notNewline, loopRuntime_world] using
            (byteEqualsLiteral_evaluates source start delimiter byte
              offset 10 false))
          .skip)
        (.sequenceNext
          (.ifFalse (by
            simpa [Returns, byteValuesDiffer, loopRuntime_world] using
              (byteEqualsDelimiter_evaluates source start delimiter byte
                offset false))
            .skip)
          (.sequenceNext escapeBranch
            (.sequenceNext increment .skip)))))
    .skip

private theorem loopBody_evaluates
    (source : List Byte) (start : Nat) (delimiter byte : Byte)
    (offset finalOffset : Nat) (escaping finalEscaping : Bool)
    {completion : Stateful.Completion}
    (byteResult : Term.evaluate termMachine
      (runtime source start delimiter offset escaping).world
      (runtime source start delimiter offset escaping).environment
      quotedCurrentByte =
        .ok (.signed .i32 (Int.ofNat byte.val),
          (runtime source start delimiter offset escaping).world))
    (bodyResult : Runs
      (loopRuntime source start delimiter offset escaping byte)
      quotedLoopCommand completion
      (loopRuntime source start delimiter finalOffset finalEscaping byte)) :
    Runs (runtime source start delimiter offset escaping)
      quotedLoopBody completion
      (runtime source start delimiter finalOffset finalEscaping) := by
  unfold Runs
  simpa only [quotedLoopBody, loopRuntime, Runtime.world, Runtime.environment,
    Env.pop_push] using
      (Command.Evaluates.letValue (type := i32Type) byteResult bodyResult)

private theorem loopBody_step (source : List Byte) (start : Nat)
    (delimiter byte : Byte) (offset : Nat) (escaping nextEscaping : Bool)
    (sourceBound : source.length ≤ 2147483647)
    (inBounds : offset < source.length)
    (byteEq : byte = source.get ⟨offset, inBounds⟩)
    (step : escaping = true ∧ nextEscaping = false ∨
      escaping = false ∧ byte.val ≠ 10 ∧ byte ≠ delimiter ∧
        decide (byte.val = 92) = nextEscaping) :
    Runs (runtime source start delimiter offset escaping)
      quotedLoopBody .next
      (runtime source start delimiter (offset + 1) nextEscaping) := by
  have byteResult := currentByte_evaluates source start delimiter offset escaping
    byte inBounds byteEq
  rcases step with ⟨rfl, rfl⟩ | ⟨rfl, notNewline, notDelimiter, escape⟩
  · have bodyResult := escapedBody_evaluates source start delimiter byte offset
      (Nat.le_trans (Nat.succ_le_of_lt inBounds) sourceBound)
    exact loopBody_evaluates source start delimiter byte offset (offset + 1)
      true false byteResult bodyResult
  · have bodyResult := unescapedStep_evaluates source start delimiter byte
      offset nextEscaping notNewline notDelimiter sourceBound inBounds escape
    exact loopBody_evaluates source start delimiter byte offset (offset + 1)
      false nextEscaping byteResult bodyResult

private theorem loopBody_newline (source : List Byte) (start : Nat)
    (delimiter byte : Byte) (offset : Nat)
    (inBounds : offset < source.length)
    (byteEq : byte = source.get ⟨offset, inBounds⟩)
    (newline : byte.val = 10) :
    Runs (runtime source start delimiter offset false)
      quotedLoopBody
      (.returned (some (ScanEnd.value false 0 (Int.ofNat offset))))
      (runtime source start delimiter offset false) := by
  have byteResult := currentByte_evaluates source start delimiter offset false
    byte inBounds byteEq
  have bodyResult := unescapedNewline_evaluates source start delimiter byte
    offset newline
  exact loopBody_evaluates source start delimiter byte offset offset false false
    byteResult bodyResult

private theorem loopBody_delimiter (source : List Byte) (start : Nat)
    (delimiter byte : Byte) (offset : Nat)
    (inBounds : offset < source.length)
    (byteEq : byte = source.get ⟨offset, inBounds⟩)
    (notNewline : byte.val ≠ 10) (isDelimiter : byte = delimiter)
    (bound : offset + 1 ≤ 2147483647) :
    Runs (runtime source start delimiter offset false)
      quotedLoopBody
      (.returned (some (ScanEnd.value true (Int.ofNat (offset + 1)) 0)))
      (runtime source start delimiter offset false) := by
  have byteResult := currentByte_evaluates source start delimiter offset false
    byte inBounds byteEq
  have bodyResult := unescapedDelimiter_evaluates source start delimiter byte
    offset notNewline isDelimiter bound
  exact loopBody_evaluates source start delimiter byte offset offset false false
    byteResult bodyResult

private theorem failedAtBound_evaluates (source : List Byte) (start : Nat)
    (delimiter : Byte) (offset : Nat) (escaping : Bool) :
    Term.evaluate termMachine
      (runtime source start delimiter offset escaping).world
      (runtime source start delimiter offset escaping).environment
      failedAtBound = .ok
        (ScanEnd.value false 0 (Int.ofNat source.length), world source) := by
  unfold failedAtBound apply
  apply Term.evaluate_apply1 (by rfl)
  exact ScanEndCalls.failed (world source) (Int.ofNat source.length)

private theorem loopAndFallback_evaluates (source : List Byte) (start : Nat)
    (delimiter : Byte) (offset : Nat) (escaping : Bool)
    (sourceBound : source.length ≤ 2147483647)
    (offsetBound : offset ≤ source.length) :
    ∃ finalOffset finalEscaping,
      Runs (runtime source start delimiter offset escaping)
        (.sequence quotedLoop
          (.sequence (.returnValue (some failedAtBound)) .skip))
        (.returned (some (scanEndValue
          (scanQuotedBody delimiter escaping (source.drop offset) offset))))
        (runtime source start delimiter finalOffset finalEscaping) := by
  unfold Runs
  by_cases inBounds : offset < source.length
  · have condition := beforeEnd_evaluates source start delimiter offset escaping
    simp [inBounds] at condition
    let byte := source.get ⟨offset, inBounds⟩
    have dropped := List.drop_eq_getElem_cons inBounds
    cases escaping with
    | true =>
        have bodyResult := loopBody_step source start delimiter byte offset true
          false sourceBound inBounds rfl (.inl ⟨rfl, rfl⟩)
        have stepEq : scanQuotedBody delimiter true (source.drop offset) offset =
            scanQuotedBody delimiter false (source.drop (offset + 1))
              (offset + 1) := by
          rw [dropped]
          rfl
        obtain ⟨finalOffset, finalEscaping, loopResult⟩ :=
          loopAndFallback_evaluates source start delimiter (offset + 1) false
            sourceBound (Nat.succ_le_of_lt inBounds)
        rw [stepEq]
        exact ⟨finalOffset, finalEscaping,
            Command.Evaluates.whileNextSequence condition bodyResult loopResult⟩
    | false =>
        by_cases newline : byte.val = 10
        · have bodyResult := loopBody_newline source start delimiter byte offset
            inBounds rfl newline
          have resultEq : scanQuotedBody delimiter false (source.drop offset)
              offset = .failure offset := by
            rw [dropped]
            change (if byte.val = 10 then
              Lanius.Compiler.Lexer.ScanEnd.failure offset else _) =
              Lanius.Compiler.Lexer.ScanEnd.failure offset
            simp [newline]
          refine ⟨offset, false, ?_⟩
          rw [resultEq]
          simpa [quotedLoop, scanEndValue, ScanEnd.value,
            scanEndDeclaration] using
            (Command.Evaluates.sequenceStop
              (Command.Evaluates.whileReturn (body := quotedLoopBody)
                condition bodyResult) (by simp))
        · by_cases closes : byte = delimiter
          · have bodyResult := loopBody_delimiter source start delimiter byte
              offset inBounds rfl newline closes
              (Nat.le_trans (Nat.succ_le_of_lt inBounds) sourceBound)
            have delimiterNotNewline : delimiter.val ≠ 10 := by
              simpa [closes] using newline
            have resultEq : scanQuotedBody delimiter false (source.drop offset)
                offset = .success (offset + 1) := by
              rw [dropped]
              change (if byte.val = 10 then
                Lanius.Compiler.Lexer.ScanEnd.failure offset else
                if byte = delimiter then
                  Lanius.Compiler.Lexer.ScanEnd.success (offset + 1) else _) =
                  Lanius.Compiler.Lexer.ScanEnd.success (offset + 1)
              simp [delimiterNotNewline, closes]
            refine ⟨offset, false, ?_⟩
            rw [resultEq]
            simpa [quotedLoop, scanEndValue, ScanEnd.value,
              scanEndDeclaration] using
              (Command.Evaluates.sequenceStop
                (Command.Evaluates.whileReturn (body := quotedLoopBody)
                  condition bodyResult) (by simp))
          · let nextEscaping := decide (byte.val = 92)
            have bodyResult := loopBody_step source start delimiter byte offset
              false nextEscaping sourceBound inBounds rfl
              (.inr ⟨rfl, newline, closes, rfl⟩)
            have stepEq : scanQuotedBody delimiter false (source.drop offset)
                offset = scanQuotedBody delimiter nextEscaping
                  (source.drop (offset + 1)) (offset + 1) := by
              rw [dropped]
              change (if byte.val = 10 then
                Lanius.Compiler.Lexer.ScanEnd.failure offset else
                if byte = delimiter then
                  Lanius.Compiler.Lexer.ScanEnd.success (offset + 1) else
                if byte.val = 92 then
                  scanQuotedBody delimiter true (source.drop (offset + 1))
                    (offset + 1)
                else scanQuotedBody delimiter false
                  (source.drop (offset + 1)) (offset + 1)) =
                scanQuotedBody delimiter nextEscaping
                  (source.drop (offset + 1)) (offset + 1)
              by_cases escape : byte.val = 92
              · simp [closes, escape, nextEscaping]
              · simp [newline, closes, escape, nextEscaping]
            obtain ⟨finalOffset, finalEscaping, loopResult⟩ :=
              loopAndFallback_evaluates source start delimiter (offset + 1)
                nextEscaping sourceBound (Nat.succ_le_of_lt inBounds)
            rw [stepEq]
            exact ⟨finalOffset, finalEscaping,
              Command.Evaluates.whileNextSequence condition bodyResult
                loopResult⟩
  · have atEnd : offset = source.length :=
      Nat.le_antisymm offsetBound (Nat.le_of_not_gt inBounds)
    have condition := beforeEnd_evaluates source start delimiter offset escaping
    simp [inBounds] at condition
    refine ⟨source.length, escaping, ?_⟩
    have resultEq : scanQuotedBody delimiter escaping (source.drop offset) offset =
        .failure source.length := by
      simp [atEnd, scanQuotedBody]
    rw [resultEq]
    have failedResult := failedAtBound_evaluates source start delimiter
      source.length escaping
    simpa [quotedLoop, atEnd, runtime_world, scanEndValue,
      scanEndDeclaration, ScanEnd.value] using
        (Command.Evaluates.sequenceNext
        (Command.Evaluates.whileFalse (body := quotedLoopBody) condition)
        (.sequenceStop
          (.returnSome (by
            simpa [atEnd, runtime_world, scanEndValue, scanEndDeclaration,
              ScanEnd.value] using failedResult)) (by simp)))
termination_by source.length - offset
decreasing_by all_goals omega

private def parameterEnvironment (source : List Byte) (start : Nat)
    (delimiter : Byte) : Env 4
  | ⟨0, _⟩ => .slice i32Type 0 [] 0 source.length
  | ⟨1, _⟩ => .signed .i32 (Int.ofNat source.length)
  | ⟨2, _⟩ => .signed .i32 (Int.ofNat start)
  | ⟨3, _⟩ => .signed .i32 (Int.ofNat delimiter.val)

theorem command_evaluates (source : List Byte) (start : Nat)
    (delimiter : Byte) (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    ∃ afterWorld afterEnvironment,
      Command.Evaluates termMachine statefulMachine (world source)
        (parameterEnvironment source start delimiter) quotedCommand
        (.returned (some (scanEndValue
          (scanQuotedEnd source start delimiter))))
        afterWorld afterEnvironment := by
  let initialOffset := start + 1
  have initialOffsetBound : initialOffset ≤ source.length :=
    Nat.succ_le_of_lt startInBounds
  have initialI32Bound : initialOffset ≤ 2147483647 :=
    Nat.le_trans initialOffsetBound sourceBound
  have initializerResult : Term.evaluate termMachine (world source)
      (parameterEnvironment source start delimiter) quotedInitializer =
      .ok (.signed .i32 (Int.ofNat initialOffset), world source) := by
    calc
      _ = _ :=
        Effectful.Term.evaluate_eq_readOnly_of_callFree
          (program := verifiedFrontendLexerCore) (calls := ScanEndCalls.calls)
          quotedInitializer (by decide +kernel)
      _ = _ := ReadOnly.Term.evaluate_i32_add (by rfl) (by rfl)
        initialI32Bound
  have pushed : ((parameterEnvironment source start delimiter).push
      (.signed .i32 (Int.ofNat initialOffset))).push (.boolean false) =
      (runtime source start delimiter initialOffset false).environment := by
    exact Env.eq_ofFn rfl
  obtain ⟨finalOffset, finalEscaping, bodyResult⟩ :=
    loopAndFallback_evaluates source start delimiter initialOffset false
      sourceBound initialOffsetBound
  refine ⟨(runtime source start delimiter finalOffset finalEscaping).world,
    Env.pop (Env.pop
      (runtime source start delimiter finalOffset finalEscaping).environment), ?_⟩
  simpa [quotedCommand, scanQuotedEnd, initialOffset] using
      (Command.Evaluates.letValue (type := i32Type) initializerResult
      (Command.Evaluates.letValue (type := .scalar .bool) (by
        change Term.evaluate termMachine (world source)
            ((parameterEnvironment source start delimiter).push
              (.signed .i32 (Int.ofNat initialOffset)))
            (literal (.boolean false)) =
          .ok (.boolean false, world source)
        rfl) (by
        rw [pushed]
        exact bodyResult)))

private theorem quotedParameterState_represents (source : List Byte)
    (start : Nat) (delimiter : Byte) :
    Representation identityLayout (callLocalCells (sourceState source)) (world source)
      (parameterEnvironment source start delimiter)
      (quotedParameterState source start delimiter) := by
  exact (Scanners.sourceState_represents source).enterCallParameters
    (sourceState_well_formed source)

private theorem quotedParameterStateFromScanner_well_formed
    (source : List Byte) (start : Nat) (delimiter : Byte) :
    StateWellFormed
      (quotedParameterStateFrom (scannerParameterState source start)
        source start delimiter) := by
  exact enterCall_preserves_wellFormed
    (scannerParameterState_well_formed source start)

private def scannerParameterEnvironment (source : List Byte) (start : Nat) : Env 3
  | ⟨0, _⟩ => .slice i32Type 0 [] 0 source.length
  | ⟨1, _⟩ => .signed .i32 (Int.ofNat source.length)
  | ⟨2, _⟩ => .signed .i32 (Int.ofNat start)

private theorem scannerParameterState_represents
    (source : List Byte) (start : Nat) :
    Representation identityLayout (callLocalCells (sourceState source))
      (world source) (scannerParameterEnvironment source start)
      (scannerParameterState source start) := by
  exact (Scanners.sourceState_represents source).enterCallParameters
    (sourceState_well_formed source)

private theorem quotedParameterStateFromScanner_represents
    (source : List Byte) (start : Nat) (delimiter : Byte) :
    Representation identityLayout
      (callLocalCells (scannerParameterState source start)) (world source)
      (parameterEnvironment source start delimiter)
      (quotedParameterStateFrom (scannerParameterState source start)
        source start delimiter) := by
  exact (scannerParameterState_represents source start).enterCallParameters
    (environment := parameterEnvironment source start delimiter)
    (scannerParameterState_well_formed source start)

theorem core_body_executes (source : List Byte) (start : Nat)
    (delimiter : Byte) (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    ∃ after,
      Executes verifiedFrontendLexerCore
        (quotedParameterState source start delimiter)
        Scanners.scanQuotedEndBody
        (.returned (some
          (scanEndValue (scanQuotedEnd source start delimiter)))) after ∧
      StateWellFormed after := by
  obtain ⟨afterWorld, afterEnvironment, evaluated⟩ :=
    command_evaluates source start delimiter sourceBound startInBounds
  have simulation := Stateful.command_executes
    (Lanius.FunctionalView.Core.EffectfulStateful.expressionSoundness
      verifiedFrontendLexerCore ScanEndCalls.calls scanEndCallSoundness)
    (Lanius.FunctionalView.Core.EffectfulStateful.actionSoundness
      verifiedFrontendLexerCore ScanEndCalls.calls scanEndCallSoundness)
    evaluated (quotedParameterState_represents source start delimiter)
    (LayoutBelow.identity (arity := 4))
    (quotedParameterState_well_formed source start delimiter)
  obtain ⟨after, writes, execution, afterWellFormed, _, _⟩ := simulation
  rw [quotedCommand_toCore_exactly] at execution
  exact ⟨after, execution, afterWellFormed⟩

theorem core_body_from_scanner_parameters_executes
    (source : List Byte) (start : Nat) (delimiter : Byte)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    ∃ after,
      Executes verifiedFrontendLexerCore
        (quotedParameterStateFrom (scannerParameterState source start)
          source start delimiter)
        Scanners.scanQuotedEndBody
        (.returned (some
          (scanEndValue (scanQuotedEnd source start delimiter)))) after ∧
      StateWellFormed after := by
  obtain ⟨afterWorld, afterEnvironment, evaluated⟩ :=
    command_evaluates source start delimiter sourceBound startInBounds
  have simulation := Stateful.command_executes
    (Lanius.FunctionalView.Core.EffectfulStateful.expressionSoundness
      verifiedFrontendLexerCore ScanEndCalls.calls scanEndCallSoundness)
    (Lanius.FunctionalView.Core.EffectfulStateful.actionSoundness
      verifiedFrontendLexerCore ScanEndCalls.calls scanEndCallSoundness)
    evaluated
    (quotedParameterStateFromScanner_represents source start delimiter)
    (LayoutBelow.identity (arity := 4))
    (quotedParameterStateFromScanner_well_formed source start delimiter)
  obtain ⟨after, writes, execution, afterWellFormed, _, _⟩ := simulation
  rw [quotedCommand_toCore_exactly] at execution
  exact ⟨after, execution, afterWellFormed⟩

theorem call_executes (source : List Byte) (start : Nat)
    (delimiter : Byte) (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    ∃ after,
      Evaluates verifiedFrontendLexerCore (sourceState source)
        (.call Scanners.scanQuotedEndFunction.id
          [sourceSlice source, i32Literal source.length, i32Literal start,
            i32Literal delimiter.val])
        (scanEndValue (scanQuotedEnd source start delimiter)) after := by
  obtain ⟨bodyFinal, bodyExecution, _⟩ :=
    core_body_executes source start delimiter sourceBound startInBounds
  have argumentsResult : ArgumentsEvaluateTo verifiedFrontendLexerCore
      (sourceState source)
      [sourceSlice source, i32Literal source.length, i32Literal start,
        i32Literal delimiter.val]
      [.slice i32Type 0 [] 0 source.length,
        .signed .i32 (Int.ofNat source.length),
        .signed .i32 (Int.ofNat start),
        .signed .i32 (Int.ofNat delimiter.val)]
      (sourceState source) := ⟨5, by rfl⟩
  let after := restoreLocals (sourceState source) bodyFinal
  refine ⟨after, ?_⟩
  apply evaluatesCallReturned
    (body := Scanners.scanQuotedEndBody)
    argumentsResult Scanners.verifiedFrontendLexerCore_finds_scanQuotedEnd
    (by rfl) Scanners.scanQuotedEndFunction_has_body
  have callee : enterCall (sourceState source)
      (List.map (fun pair => (pair.fst.fst, pair.snd))
        (Scanners.scanQuotedEndFunction.parameters.zip
          [.slice i32Type 0 [] 0 source.length,
            .signed .i32 (Int.ofNat source.length),
            .signed .i32 (Int.ofNat start),
            .signed .i32 (Int.ofNat delimiter.val)])) =
      quotedParameterState source start delimiter := by rfl
  rw [callee]
  exact bodyExecution

theorem call_from_scanner_parameters_executes
    (source : List Byte) (start : Nat) (delimiter : Byte)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    ∃ after,
      Evaluates verifiedFrontendLexerCore (scannerParameterState source start)
        (.call Scanners.scanQuotedEndFunction.id
          [.local 0, .local 1, .local 2, i32Literal delimiter.val])
        (scanEndValue (scanQuotedEnd source start delimiter)) after := by
  obtain ⟨bodyFinal, bodyExecution, _⟩ :=
    core_body_from_scanner_parameters_executes source start delimiter
      sourceBound startInBounds
  have argumentsResult : ArgumentsEvaluateTo verifiedFrontendLexerCore
      (scannerParameterState source start)
      [.local 0, .local 1, .local 2, i32Literal delimiter.val]
      [.slice i32Type 0 [] 0 source.length,
        .signed .i32 (Int.ofNat source.length),
        .signed .i32 (Int.ofNat start),
        .signed .i32 (Int.ofNat delimiter.val)]
      (scannerParameterState source start) := ⟨5, by rfl⟩
  let after := restoreLocals (scannerParameterState source start) bodyFinal
  refine ⟨after, ?_⟩
  apply evaluatesCallReturned
    (body := Scanners.scanQuotedEndBody)
    argumentsResult Scanners.verifiedFrontendLexerCore_finds_scanQuotedEnd
    (by rfl) Scanners.scanQuotedEndFunction_has_body
  have callee : enterCall (scannerParameterState source start)
      (List.map (fun pair => (pair.fst.fst, pair.snd))
        (Scanners.scanQuotedEndFunction.parameters.zip
          [.slice i32Type 0 [] 0 source.length,
            .signed .i32 (Int.ofNat source.length),
            .signed .i32 (Int.ofNat start),
            .signed .i32 (Int.ofNat delimiter.val)])) =
      quotedParameterStateFrom (scannerParameterState source start)
        source start delimiter := by rfl
  rw [callee]
  exact bodyExecution

end Lanius.Extraction.Lexer.Quoted
