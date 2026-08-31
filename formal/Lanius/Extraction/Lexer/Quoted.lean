import Lanius.Extraction.Lexer.Scanners
import Lanius.Extraction.Lexer.ScanEnd
import Lanius.Extraction.Lexer.ScanEndCalls
import Lanius.FunctionalViewLoop
import Lanius.FunctionalViewCoreEffectfulStateful

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
  apply List.ext_getElem
  · simp [constructorBindings]
  · intro index leftBound rightBound
    have zero : index = 0 := by
      simp [constructorBindings] at rightBound
      omega
    subst index
    simp [parameterBindings, ScanEnd.offsetEnvironment, constructorBindings]

private theorem constructorParametersBound (function : Function)
    (parameters : function.parameters = [(0, i32Type)]) (offset : Int) :
    bindParameters function.parameters [.signed .i32 offset] =
      some (constructorBindings offset) := by
  rw [parameters]
  rfl

private theorem successfulBody_executes (state : State) (offset : Int)
    (wellFormed : StateWellFormed state) :
    Executes verifiedFrontendLexerCore (constructorCallee state offset)
      (Functions.functionBody Functions.successfulScanFunction)
      (.returned (some (ScanEnd.value true offset 0)))
      (constructorCallee state offset) := by
  have calleeWellFormed : StateWellFormed (constructorCallee state offset) := by
    simpa [constructorCallee, constructorBindings] using
      (enterCall_preserves_wellFormed
        (bindings := constructorBindings offset) wellFormed)
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
    environmentMatches (by rfl)
    (ScanEnd.successfulScanBlock_evaluates offset)
  rw [Functions.successfulScanBlock_toCore_exactly] at sound
  exact sound.1

private theorem failedBody_executes (state : State) (offset : Int)
    (wellFormed : StateWellFormed state) :
    Executes verifiedFrontendLexerCore (constructorCallee state offset)
      (Functions.functionBody Functions.failedScanFunction)
      (.returned (some (ScanEnd.value false 0 offset)))
      (constructorCallee state offset) := by
  have calleeWellFormed : StateWellFormed (constructorCallee state offset) := by
    simpa [constructorCallee, constructorBindings] using
      (enterCall_preserves_wellFormed
        (bindings := constructorBindings offset) wellFormed)
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
    environmentMatches (by rfl)
    (ScanEnd.failedScanBlock_evaluates offset)
  rw [Functions.failedScanBlock_toCore_exactly] at sound
  exact sound.1

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
  let callee := constructorCallee afterArguments offset
  let after := restoreLocals afterArguments callee
  have body := successfulBody_executes afterArguments offset
    afterArgumentsWellFormed
  have evaluation : Evaluates verifiedFrontendLexerCore before
      (.call Functions.successfulScanFunction.id arguments)
      (ScanEnd.value true offset 0) after := by
    apply evaluatesCallReturned
      (body := Functions.functionBody Functions.successfulScanFunction)
      argumentsResult (by rfl)
      (constructorParametersBound Functions.successfulScanFunction (by rfl)
        offset) (by rfl)
    simpa [callee, constructorCallee] using body
  have entered : StoreEffect CellSet.empty afterArguments callee := by
    simpa [callee, constructorCallee] using
      (enterCall_effect afterArguments (constructorBindings offset))
  have calleeWellFormed : StateWellFormed callee := by
    simpa [callee, constructorCallee] using
      (enterCall_preserves_wellFormed
        (bindings := constructorBindings offset) afterArgumentsWellFormed)
  exact ⟨evaluation, by simpa [after] using entered.restoreLocals,
    entered.restoreLocals_wellFormed afterArgumentsWellFormed calleeWellFormed⟩

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
  let callee := constructorCallee afterArguments offset
  let after := restoreLocals afterArguments callee
  have body := failedBody_executes afterArguments offset
    afterArgumentsWellFormed
  have evaluation : Evaluates verifiedFrontendLexerCore before
      (.call Functions.failedScanFunction.id arguments)
      (ScanEnd.value false 0 offset) after := by
    apply evaluatesCallReturned
      (body := Functions.functionBody Functions.failedScanFunction)
      argumentsResult (by rfl)
      (constructorParametersBound Functions.failedScanFunction (by rfl)
        offset) (by rfl)
    simpa [callee, constructorCallee] using body
  have entered : StoreEffect CellSet.empty afterArguments callee := by
    simpa [callee, constructorCallee] using
      (enterCall_effect afterArguments (constructorBindings offset))
  have calleeWellFormed : StateWellFormed callee := by
    simpa [callee, constructorCallee] using
      (enterCall_preserves_wellFormed
        (bindings := constructorBindings offset) afterArgumentsWellFormed)
  exact ⟨evaluation, by simpa [after] using entered.restoreLocals,
    entered.restoreLocals_wellFormed afterArgumentsWellFormed calleeWellFormed⟩

private theorem calls_success
    (evaluated : ScanEndCalls.calls.evaluate world function values =
      .ok (value, afterWorld)) :
    (∃ offset, function = Functions.successfulScanFunction.id ∧
      values = [.signed .i32 offset] ∧
      value = ScanEnd.value true offset 0 ∧ afterWorld = world) ∨
    (∃ offset, function = Functions.failedScanFunction.id ∧
      values = [.signed .i32 offset] ∧
      value = ScanEnd.value false 0 offset ∧ afterWorld = world) := by
  simp only [ScanEndCalls.calls] at evaluated
  split at evaluated
  next offset =>
    split at evaluated
    next successful =>
      obtain ⟨rfl, rfl⟩ := evaluated
      exact .inl ⟨offset, successful, rfl, rfl, rfl⟩
    next notSuccessful =>
      split at evaluated
      next failed =>
        obtain ⟨rfl, rfl⟩ := evaluated
        exact .inr ⟨offset, failed, rfl, rfl, rfl⟩
      next => contradiction
  next => contradiction

theorem scanEndCallSoundness :
    Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness
      verifiedFrontendLexerCore ScanEndCalls.calls := by
  constructor
  · intro arity layout localCell beforeWorld afterWorld environment before
      afterArguments function arguments values value argumentWrites
      afterArgumentsWellFormed represented argumentsExecution argumentsEffect
      evaluated
    rcases calls_success evaluated with
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
      have afterRepresented : Representation layout localCell beforeWorld
          environment after := {
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
      exact ⟨after, CellSet.union argumentWrites CellSet.empty, callExecution,
        afterWellFormed, afterRepresented, argumentsEffect.trans callEffect⟩
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
      have afterRepresented : Representation layout localCell beforeWorld
          environment after := {
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
      exact ⟨after, CellSet.union argumentWrites CellSet.empty, callExecution,
        afterWellFormed, afterRepresented, argumentsEffect.trans callEffect⟩
  · intro beforeWorld afterWorld function values value evaluated cell
    rcases calls_success evaluated with
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
    Term.evaluate termMachine (runtime source start delimiter offset escaping).world
        (runtime source start delimiter offset escaping).environment
        quotedBeforeEnd =
      .ok (.boolean (decide (offset < source.length)),
        (runtime source start delimiter offset escaping).world) := by
  unfold quotedBeforeEnd apply
  apply Term.evaluate_apply2 (by rfl) (by rfl)
  change ReadOnly.evaluateOperation verifiedFrontendLexerCore (world source)
    (.binary .less i32Type i32Type (.scalar .bool))
    [.signed .i32 (Int.ofNat offset),
      .signed .i32 (Int.ofNat source.length)] = _
  exact ReadOnly.evaluateOperation_i32_less
    (program := verifiedFrontendLexerCore) (world := world source)
    (leftType := i32Type) (rightType := i32Type)
    (outputType := .scalar .bool) offset source.length

private theorem currentByte_evaluates (source : List Byte) (start : Nat)
    (delimiter : Byte) (offset : Nat) (escaping : Bool)
    (inBounds : offset < source.length) :
    ∃ integerInBounds : offset < (sourceIntegers source).length,
      Term.evaluate termMachine
          (runtime source start delimiter offset escaping).world
          (runtime source start delimiter offset escaping).environment
          quotedCurrentByte =
        .ok (.signed .i32
            ((sourceIntegers source).get ⟨offset, integerInBounds⟩),
          world source) := by
  have integerInBounds : offset < (sourceIntegers source).length := by
    simpa [sourceIntegers] using inBounds
  have evaluated := ReadOnly.evaluateOperation_i32_index
    (program := verifiedFrontendLexerCore) (world := world source)
    (baseType := .slice i32Type) (indexType := i32Type)
    (elementType := i32Type) (cell := 0)
    (values := sourceIntegers source) (position := offset)
    World.singleton_finds integerInBounds
  refine ⟨integerInBounds, ?_⟩
  unfold quotedCurrentByte apply
  apply Term.evaluate_apply2 (by rfl) (by rfl)
  change ReadOnly.evaluateOperation verifiedFrontendLexerCore (world source)
    (.index (.slice i32Type) i32Type i32Type)
    [.slice i32Type 0 [] 0 source.length,
      .signed .i32 (Int.ofNat offset)] = _
  rw [show source.length = (sourceIntegers source).length by simp [sourceIntegers]]
  exact evaluated

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
    Term.evaluate termMachine
        (loopRuntime source start delimiter offset escaping byte).world
        (loopRuntime source start delimiter offset escaping byte).environment
        (byteEqualsLiteral expected) =
      .ok (.boolean (decide (byte.val = expected)), world source) := by
  unfold byteEqualsLiteral apply
  apply Term.evaluate_apply2 (by rfl) (by rfl)
  change ReadOnly.evaluateOperation verifiedFrontendLexerCore (world source)
    (.binary .equal i32Type i32Type (.scalar .bool))
    [.signed .i32 (Int.ofNat byte.val),
      .signed .i32 (Int.ofNat expected)] = _
  exact ReadOnly.evaluateOperation_i32_equal
    (program := verifiedFrontendLexerCore) (world := world source)
    (leftType := i32Type) (rightType := i32Type)
    (outputType := .scalar .bool) byte.val expected

private theorem byteEqualsDelimiter_evaluates (source : List Byte)
    (start : Nat) (delimiter byte : Byte) (offset : Nat) (escaping : Bool) :
    Term.evaluate termMachine
        (loopRuntime source start delimiter offset escaping byte).world
        (loopRuntime source start delimiter offset escaping byte).environment
        byteEqualsDelimiter =
      .ok (.boolean (decide (byte.val = delimiter.val)), world source) := by
  unfold byteEqualsDelimiter apply
  apply Term.evaluate_apply2 (by rfl) (by rfl)
  change ReadOnly.evaluateOperation verifiedFrontendLexerCore (world source)
    (.binary .equal i32Type i32Type (.scalar .bool))
    [.signed .i32 (Int.ofNat byte.val),
      .signed .i32 (Int.ofNat delimiter.val)] = _
  exact ReadOnly.evaluateOperation_i32_equal
    (program := verifiedFrontendLexerCore) (world := world source)
    (leftType := i32Type) (rightType := i32Type)
    (outputType := .scalar .bool) byte.val delimiter.val

private theorem successfulAfterByte_evaluates (source : List Byte)
    (start : Nat) (delimiter byte : Byte) (offset : Nat) (escaping : Bool)
    (bound : offset + 1 ≤ 2147483647) :
    Term.evaluate termMachine
        (loopRuntime source start delimiter offset escaping byte).world
        (loopRuntime source start delimiter offset escaping byte).environment
        successfulAfterByte =
      .ok (ScanEnd.value true (Int.ofNat (offset + 1)) 0, world source) := by
  unfold successfulAfterByte apply
  apply Term.evaluate_apply1
  · apply Term.evaluate_apply2 (by rfl) (by rfl)
    change ReadOnly.evaluateOperation verifiedFrontendLexerCore (world source)
      (.binary .add i32Type i32Type i32Type)
      [.signed .i32 (Int.ofNat offset), .signed .i32 1] = _
    exact ReadOnly.evaluateOperation_i32_add
      (program := verifiedFrontendLexerCore) (world := world source)
      (leftType := i32Type) (rightType := i32Type) (outputType := i32Type)
      offset 1 bound
  · exact ScanEndCalls.successful (world source) (Int.ofNat (offset + 1))

private theorem failedAtOffset_evaluates (source : List Byte) (start : Nat)
    (delimiter byte : Byte) (offset : Nat) (escaping : Bool) :
    Term.evaluate termMachine
        (loopRuntime source start delimiter offset escaping byte).world
        (loopRuntime source start delimiter offset escaping byte).environment
        failedAtOffset =
      .ok (ScanEnd.value false 0 (Int.ofNat offset), world source) := by
  unfold failedAtOffset apply
  apply Term.evaluate_apply1 (by rfl)
  exact ScanEndCalls.failed (world source) (Int.ofNat offset)

private theorem setEscaping_evaluates (source : List Byte) (start : Nat)
    (delimiter byte : Byte) (offset : Nat) (escaping value : Bool) :
    Command.Evaluates termMachine statefulMachine
      (loopRuntime source start delimiter offset escaping byte).world
      (loopRuntime source start delimiter offset escaping byte).environment
      (setEscaping value) .next
      (loopRuntime source start delimiter offset escaping byte).world
      (loopRuntime source start delimiter offset value byte).environment := by
  have afterEnvironment :
      (loopRuntime source start delimiter offset value byte).environment =
        Env.set
          (loopRuntime source start delimiter offset escaping byte).environment
          ⟨5, by omega⟩ (.boolean value) := by
    funext index
    have cases : index.val = 0 ∨ index.val = 1 ∨ index.val = 2 ∨
        index.val = 3 ∨ index.val = 4 ∨ index.val = 5 ∨
        index.val = 6 := by omega
    rcases cases with zero | one | two | three | four | five | six
    · have same : index = ⟨0, by omega⟩ := Fin.ext zero
      rw [same]
      rfl
    · have same : index = ⟨1, by omega⟩ := Fin.ext one
      rw [same]
      rfl
    · have same : index = ⟨2, by omega⟩ := Fin.ext two
      rw [same]
      rfl
    · have same : index = ⟨3, by omega⟩ := Fin.ext three
      rw [same]
      rfl
    · have same : index = ⟨4, by omega⟩ := Fin.ext four
      rw [same]
      rfl
    · have same : index = ⟨5, by omega⟩ := Fin.ext five
      rw [same]
      rfl
    · have same : index = ⟨6, by omega⟩ := Fin.ext six
      rw [same]
      rfl
  rw [afterEnvironment]
  apply Command.Evaluates.updateLocal (by rfl)
  rfl

private theorem incrementOffset_evaluates (source : List Byte) (start : Nat)
    (delimiter byte : Byte) (offset : Nat) (escaping : Bool)
    (bound : offset + 1 ≤ 2147483647) :
    Command.Evaluates termMachine statefulMachine
      (loopRuntime source start delimiter offset escaping byte).world
      (loopRuntime source start delimiter offset escaping byte).environment
      incrementOffset .next
      (loopRuntime source start delimiter offset escaping byte).world
      (loopRuntime source start delimiter (offset + 1) escaping byte).environment := by
  have afterEnvironment :
      (loopRuntime source start delimiter (offset + 1) escaping byte).environment =
        Env.set
          (loopRuntime source start delimiter offset escaping byte).environment
          ⟨4, by omega⟩ (.signed .i32 (Int.ofNat (offset + 1))) := by
    funext index
    have cases : index.val = 0 ∨ index.val = 1 ∨ index.val = 2 ∨
        index.val = 3 ∨ index.val = 4 ∨ index.val = 5 ∨
        index.val = 6 := by omega
    rcases cases with zero | one | two | three | four | five | six
    · have same : index = ⟨0, by omega⟩ := Fin.ext zero
      rw [same]
      rfl
    · have same : index = ⟨1, by omega⟩ := Fin.ext one
      rw [same]
      rfl
    · have same : index = ⟨2, by omega⟩ := Fin.ext two
      rw [same]
      rfl
    · have same : index = ⟨3, by omega⟩ := Fin.ext three
      rw [same]
      rfl
    · have same : index = ⟨4, by omega⟩ := Fin.ext four
      rw [same]
      rfl
    · have same : index = ⟨5, by omega⟩ := Fin.ext five
      rw [same]
      rfl
    · have same : index = ⟨6, by omega⟩ := Fin.ext six
      rw [same]
      rfl
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
    Command.Evaluates termMachine statefulMachine
      (loopRuntime source start delimiter offset true byte).world
      (loopRuntime source start delimiter offset true byte).environment
      quotedLoopCommand .next
      (loopRuntime source start delimiter offset true byte).world
      (loopRuntime source start delimiter (offset + 1) false byte).environment := by
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
    Command.Evaluates termMachine statefulMachine
      (loopRuntime source start delimiter offset false byte).world
      (loopRuntime source start delimiter offset false byte).environment
      quotedLoopCommand
      (.returned (some (ScanEnd.value false 0 (Int.ofNat offset))))
      (loopRuntime source start delimiter offset false byte).world
      (loopRuntime source start delimiter offset false byte).environment := by
  have condition := byteEqualsLiteral_evaluates source start delimiter byte
    offset 10 false
  have conditionTrue : Term.evaluate termMachine
      (loopRuntime source start delimiter offset false byte).world
      (loopRuntime source start delimiter offset false byte).environment
      (byteEqualsLiteral 10) = .ok (.boolean true,
        (loopRuntime source start delimiter offset false byte).world) := by
    simpa [newline, loopRuntime_world] using condition
  have returned : Command.Evaluates termMachine statefulMachine
      (loopRuntime source start delimiter offset false byte).world
      (loopRuntime source start delimiter offset false byte).environment
      (.returnValue (some failedAtOffset))
      (.returned (some (ScanEnd.value false 0 (Int.ofNat offset))))
      (loopRuntime source start delimiter offset false byte).world
      (loopRuntime source start delimiter offset false byte).environment :=
    .returnSome (failedAtOffset_evaluates source start delimiter byte offset false)
  have returnedWithSkip : Command.Evaluates termMachine statefulMachine
      (loopRuntime source start delimiter offset false byte).world
      (loopRuntime source start delimiter offset false byte).environment
      (.sequence (.returnValue (some failedAtOffset)) .skip)
      (.returned (some (ScanEnd.value false 0 (Int.ofNat offset))))
      (loopRuntime source start delimiter offset false byte).world
      (loopRuntime source start delimiter offset false byte).environment :=
    .sequenceStop returned (by simp)
  have branch : Command.Evaluates termMachine statefulMachine
      (loopRuntime source start delimiter offset false byte).world
      (loopRuntime source start delimiter offset false byte).environment
      (.ifThenElse (byteEqualsLiteral 10)
        (.sequence (.returnValue (some failedAtOffset)) .skip) .skip)
      (.returned (some (ScanEnd.value false 0 (Int.ofNat offset))))
      (loopRuntime source start delimiter offset false byte).world
      (loopRuntime source start delimiter offset false byte).environment :=
    .ifTrue conditionTrue returnedWithSkip
  have unescaped : Command.Evaluates termMachine statefulMachine
      (loopRuntime source start delimiter offset false byte).world
      (loopRuntime source start delimiter offset false byte).environment
      unescapedBody
      (.returned (some (ScanEnd.value false 0 (Int.ofNat offset))))
      (loopRuntime source start delimiter offset false byte).world
      (loopRuntime source start delimiter offset false byte).environment :=
    .sequenceStop branch (by simp)
  have escapingIf : Command.Evaluates termMachine statefulMachine
      (loopRuntime source start delimiter offset false byte).world
      (loopRuntime source start delimiter offset false byte).environment
      (.ifThenElse (reference ⟨5, by omega⟩)
        (.sequence (setEscaping false) (.sequence incrementOffset .skip))
        unescapedBody)
      (.returned (some (ScanEnd.value false 0 (Int.ofNat offset))))
      (loopRuntime source start delimiter offset false byte).world
      (loopRuntime source start delimiter offset false byte).environment :=
    .ifFalse (by rfl) unescaped
  exact .sequenceStop escapingIf (by simp)

private theorem unescapedDelimiter_evaluates (source : List Byte) (start : Nat)
    (delimiter byte : Byte) (offset : Nat)
    (notNewline : byte.val ≠ 10) (isDelimiter : byte = delimiter)
    (bound : offset + 1 ≤ 2147483647) :
    Command.Evaluates termMachine statefulMachine
      (loopRuntime source start delimiter offset false byte).world
      (loopRuntime source start delimiter offset false byte).environment
      quotedLoopCommand
      (.returned (some (ScanEnd.value true (Int.ofNat (offset + 1)) 0)))
      (loopRuntime source start delimiter offset false byte).world
      (loopRuntime source start delimiter offset false byte).environment := by
  have newlineCondition := byteEqualsLiteral_evaluates source start delimiter
    byte offset 10 false
  have newlineFalse : Term.evaluate termMachine
      (loopRuntime source start delimiter offset false byte).world
      (loopRuntime source start delimiter offset false byte).environment
      (byteEqualsLiteral 10) = .ok (.boolean false,
        (loopRuntime source start delimiter offset false byte).world) := by
    simpa [notNewline, loopRuntime_world] using newlineCondition
  have delimiterCondition := byteEqualsDelimiter_evaluates source start delimiter
    byte offset false
  have delimiterTrue : Term.evaluate termMachine
      (loopRuntime source start delimiter offset false byte).world
      (loopRuntime source start delimiter offset false byte).environment
      byteEqualsDelimiter = .ok (.boolean true,
        (loopRuntime source start delimiter offset false byte).world) := by
    subst byte
    simpa [loopRuntime_world] using delimiterCondition
  have returned : Command.Evaluates termMachine statefulMachine
      (loopRuntime source start delimiter offset false byte).world
      (loopRuntime source start delimiter offset false byte).environment
      (.returnValue (some successfulAfterByte))
      (.returned (some (ScanEnd.value true (Int.ofNat (offset + 1)) 0)))
      (loopRuntime source start delimiter offset false byte).world
      (loopRuntime source start delimiter offset false byte).environment :=
    .returnSome (successfulAfterByte_evaluates source start delimiter byte
      offset false bound)
  have returnedWithSkip : Command.Evaluates termMachine statefulMachine
      (loopRuntime source start delimiter offset false byte).world
      (loopRuntime source start delimiter offset false byte).environment
      (.sequence (.returnValue (some successfulAfterByte)) .skip)
      (.returned (some (ScanEnd.value true (Int.ofNat (offset + 1)) 0)))
      (loopRuntime source start delimiter offset false byte).world
      (loopRuntime source start delimiter offset false byte).environment :=
    .sequenceStop returned (by simp)
  have second : Command.Evaluates termMachine statefulMachine
      (loopRuntime source start delimiter offset false byte).world
      (loopRuntime source start delimiter offset false byte).environment
      (.ifThenElse byteEqualsDelimiter
        (.sequence (.returnValue (some successfulAfterByte)) .skip) .skip)
      (.returned (some (ScanEnd.value true (Int.ofNat (offset + 1)) 0)))
      (loopRuntime source start delimiter offset false byte).world
      (loopRuntime source start delimiter offset false byte).environment :=
    .ifTrue delimiterTrue returnedWithSkip
  have rest : Command.Evaluates termMachine statefulMachine
      (loopRuntime source start delimiter offset false byte).world
      (loopRuntime source start delimiter offset false byte).environment
      (.sequence
        (.ifThenElse byteEqualsDelimiter
          (.sequence (.returnValue (some successfulAfterByte)) .skip) .skip)
        (.sequence
          (.ifThenElse (byteEqualsLiteral 92)
            (.sequence (setEscaping true) .skip) .skip)
          (.sequence incrementOffset .skip)))
      (.returned (some (ScanEnd.value true (Int.ofNat (offset + 1)) 0)))
      (loopRuntime source start delimiter offset false byte).world
      (loopRuntime source start delimiter offset false byte).environment :=
    .sequenceStop second (by simp)
  have first : Command.Evaluates termMachine statefulMachine
      (loopRuntime source start delimiter offset false byte).world
      (loopRuntime source start delimiter offset false byte).environment
      (.ifThenElse (byteEqualsLiteral 10)
        (.sequence (.returnValue (some failedAtOffset)) .skip) .skip)
      .next (loopRuntime source start delimiter offset false byte).world
      (loopRuntime source start delimiter offset false byte).environment :=
    .ifFalse newlineFalse .skip
  have unescaped : Command.Evaluates termMachine statefulMachine
      (loopRuntime source start delimiter offset false byte).world
      (loopRuntime source start delimiter offset false byte).environment
      unescapedBody
      (.returned (some (ScanEnd.value true (Int.ofNat (offset + 1)) 0)))
      (loopRuntime source start delimiter offset false byte).world
      (loopRuntime source start delimiter offset false byte).environment :=
    .sequenceNext first rest
  have escapingIf : Command.Evaluates termMachine statefulMachine
      (loopRuntime source start delimiter offset false byte).world
      (loopRuntime source start delimiter offset false byte).environment
      (.ifThenElse (reference ⟨5, by omega⟩)
        (.sequence (setEscaping false) (.sequence incrementOffset .skip))
        unescapedBody)
      (.returned (some (ScanEnd.value true (Int.ofNat (offset + 1)) 0)))
      (loopRuntime source start delimiter offset false byte).world
      (loopRuntime source start delimiter offset false byte).environment :=
    .ifFalse (by rfl) unescaped
  exact .sequenceStop escapingIf (by simp)

private theorem unescapedStep_evaluates (source : List Byte) (start : Nat)
    (delimiter byte : Byte) (offset : Nat) (nextEscaping : Bool)
    (notNewline : byte.val ≠ 10) (notDelimiter : byte ≠ delimiter)
    (sourceBound : source.length ≤ 2147483647)
    (inBounds : offset < source.length)
    (escapeCondition : decide (byte.val = 92) = nextEscaping) :
    Command.Evaluates termMachine statefulMachine
      (loopRuntime source start delimiter offset false byte).world
      (loopRuntime source start delimiter offset false byte).environment
      quotedLoopCommand .next
      (loopRuntime source start delimiter (offset + 1) nextEscaping byte).world
      (loopRuntime source start delimiter (offset + 1) nextEscaping byte).environment := by
  have newlineResult := byteEqualsLiteral_evaluates source start delimiter byte
    offset 10 false
  have newlineFalse : Term.evaluate termMachine
      (loopRuntime source start delimiter offset false byte).world
      (loopRuntime source start delimiter offset false byte).environment
      (byteEqualsLiteral 10) = .ok (.boolean false,
        (loopRuntime source start delimiter offset false byte).world) := by
    simpa [notNewline, loopRuntime_world] using newlineResult
  have delimiterResult := byteEqualsDelimiter_evaluates source start delimiter
    byte offset false
  have byteValuesDiffer : byte.val ≠ delimiter.val := by
    intro equal
    apply notDelimiter
    exact Fin.ext equal
  have delimiterFalse : Term.evaluate termMachine
      (loopRuntime source start delimiter offset false byte).world
      (loopRuntime source start delimiter offset false byte).environment
      byteEqualsDelimiter = .ok (.boolean false,
        (loopRuntime source start delimiter offset false byte).world) := by
    simpa [byteValuesDiffer, loopRuntime_world] using delimiterResult
  have escapeResult := byteEqualsLiteral_evaluates source start delimiter byte
    offset 92 false
  have escapeEvaluated : Term.evaluate termMachine
      (loopRuntime source start delimiter offset false byte).world
      (loopRuntime source start delimiter offset false byte).environment
      (byteEqualsLiteral 92) = .ok (.boolean nextEscaping,
        (loopRuntime source start delimiter offset false byte).world) := by
    simpa [escapeCondition, loopRuntime_world] using escapeResult
  have escapeBranch : Command.Evaluates termMachine statefulMachine
      (loopRuntime source start delimiter offset false byte).world
      (loopRuntime source start delimiter offset false byte).environment
      (.ifThenElse (byteEqualsLiteral 92)
        (.sequence (setEscaping true) .skip) .skip)
      .next
      (loopRuntime source start delimiter offset nextEscaping byte).world
      (loopRuntime source start delimiter offset nextEscaping byte).environment := by
    cases nextEscaping with
    | false => exact .ifFalse escapeEvaluated .skip
    | true =>
        apply Command.Evaluates.ifTrue escapeEvaluated
        apply Command.Evaluates.sequenceNext
        · exact setEscaping_evaluates source start delimiter byte offset false true
        · exact .skip
  have increment := incrementOffset_evaluates source start delimiter byte offset
    nextEscaping (Nat.le_trans (Nat.succ_le_of_lt inBounds) sourceBound)
  have escapeAndIncrement : Command.Evaluates termMachine statefulMachine
      (loopRuntime source start delimiter offset false byte).world
      (loopRuntime source start delimiter offset false byte).environment
      (.sequence
        (.ifThenElse (byteEqualsLiteral 92)
          (.sequence (setEscaping true) .skip) .skip)
        (.sequence incrementOffset .skip))
      .next
      (loopRuntime source start delimiter (offset + 1) nextEscaping byte).world
      (loopRuntime source start delimiter (offset + 1) nextEscaping byte).environment := by
    apply Command.Evaluates.sequenceNext escapeBranch
    exact .sequenceNext increment .skip
  have delimiterBranch : Command.Evaluates termMachine statefulMachine
      (loopRuntime source start delimiter offset false byte).world
      (loopRuntime source start delimiter offset false byte).environment
      (.ifThenElse byteEqualsDelimiter
        (.sequence (.returnValue (some successfulAfterByte)) .skip) .skip)
      .next
      (loopRuntime source start delimiter offset false byte).world
      (loopRuntime source start delimiter offset false byte).environment :=
    .ifFalse delimiterFalse .skip
  have delimiterAndRest :=
    Command.Evaluates.sequenceNext delimiterBranch escapeAndIncrement
  have newlineBranch : Command.Evaluates termMachine statefulMachine
      (loopRuntime source start delimiter offset false byte).world
      (loopRuntime source start delimiter offset false byte).environment
      (.ifThenElse (byteEqualsLiteral 10)
        (.sequence (.returnValue (some failedAtOffset)) .skip) .skip)
      .next
      (loopRuntime source start delimiter offset false byte).world
      (loopRuntime source start delimiter offset false byte).environment :=
    .ifFalse newlineFalse .skip
  have unescaped := Command.Evaluates.sequenceNext newlineBranch delimiterAndRest
  have escapingIf : Command.Evaluates termMachine statefulMachine
      (loopRuntime source start delimiter offset false byte).world
      (loopRuntime source start delimiter offset false byte).environment
      (.ifThenElse (reference ⟨5, by omega⟩)
        (.sequence (setEscaping false) (.sequence incrementOffset .skip))
        unescapedBody)
      .next
      (loopRuntime source start delimiter (offset + 1) nextEscaping byte).world
      (loopRuntime source start delimiter (offset + 1) nextEscaping byte).environment :=
    .ifFalse (by rfl) unescaped
  exact .sequenceNext escapingIf .skip

private theorem loopBody_step (source : List Byte) (start : Nat)
    (delimiter byte : Byte) (offset : Nat) (escaping nextEscaping : Bool)
    (sourceBound : source.length ≤ 2147483647)
    (inBounds : offset < source.length)
    (byteEq : byte = source.get ⟨offset, inBounds⟩)
    (step : escaping = true ∧ nextEscaping = false ∨
      escaping = false ∧ byte.val ≠ 10 ∧ byte ≠ delimiter ∧
        decide (byte.val = 92) = nextEscaping) :
    Command.Evaluates termMachine statefulMachine
      (runtime source start delimiter offset escaping).world
      (runtime source start delimiter offset escaping).environment
      quotedLoopBody .next
      (runtime source start delimiter (offset + 1) nextEscaping).world
      (runtime source start delimiter (offset + 1) nextEscaping).environment := by
  obtain ⟨integerInBounds, byteResult⟩ :=
    currentByte_evaluates source start delimiter offset escaping inBounds
  have mappedByte : (sourceIntegers source).get
      ⟨offset, integerInBounds⟩ = Int.ofNat byte.val := by
    subst byte
    simp [sourceIntegers]
  rw [mappedByte] at byteResult
  rcases step with ⟨rfl, rfl⟩ | ⟨rfl, notNewline, notDelimiter, escape⟩
  · have bodyResult := escapedBody_evaluates source start delimiter byte offset
      (Nat.le_trans (Nat.succ_le_of_lt inBounds) sourceBound)
    have whole := Command.Evaluates.letValue (type := i32Type)
      byteResult bodyResult
    have afterWorld :
        (loopRuntime source start delimiter offset true byte).world =
          (runtime source start delimiter (offset + 1) false).world := by rfl
    have afterEnvironment :
        Env.pop (loopRuntime source start delimiter (offset + 1) false byte).environment =
          (runtime source start delimiter (offset + 1) false).environment := by
      exact Env.pop_push _ _
    rw [← afterWorld, ← afterEnvironment]
    simpa only [quotedLoopBody] using whole
  · have bodyResult := unescapedStep_evaluates source start delimiter byte
      offset nextEscaping notNewline notDelimiter sourceBound inBounds escape
    have whole := Command.Evaluates.letValue (type := i32Type)
      byteResult bodyResult
    have afterWorld :
        (loopRuntime source start delimiter (offset + 1) nextEscaping byte).world =
          (runtime source start delimiter (offset + 1) nextEscaping).world := by rfl
    have afterEnvironment : Env.pop
        (loopRuntime source start delimiter (offset + 1) nextEscaping byte).environment =
          (runtime source start delimiter (offset + 1) nextEscaping).environment := by
      exact Env.pop_push _ _
    rw [← afterWorld, ← afterEnvironment]
    simpa only [quotedLoopBody] using whole

private theorem loopBody_newline (source : List Byte) (start : Nat)
    (delimiter byte : Byte) (offset : Nat)
    (inBounds : offset < source.length)
    (byteEq : byte = source.get ⟨offset, inBounds⟩)
    (newline : byte.val = 10) :
    Command.Evaluates termMachine statefulMachine
      (runtime source start delimiter offset false).world
      (runtime source start delimiter offset false).environment
      quotedLoopBody
      (.returned (some (ScanEnd.value false 0 (Int.ofNat offset))))
      (runtime source start delimiter offset false).world
      (runtime source start delimiter offset false).environment := by
  obtain ⟨integerInBounds, byteResult⟩ :=
    currentByte_evaluates source start delimiter offset false inBounds
  have mappedByte : (sourceIntegers source).get
      ⟨offset, integerInBounds⟩ = Int.ofNat byte.val := by
    subst byte
    simp [sourceIntegers]
  rw [mappedByte] at byteResult
  have bodyResult := unescapedNewline_evaluates source start delimiter byte
    offset newline
  have whole := Command.Evaluates.letValue (type := i32Type)
    byteResult bodyResult
  have afterWorld :
      (loopRuntime source start delimiter offset false byte).world =
        (runtime source start delimiter offset false).world := by rfl
  have afterEnvironment : Env.pop
      (loopRuntime source start delimiter offset false byte).environment =
        (runtime source start delimiter offset false).environment := by
    exact Env.pop_push _ _
  rw [afterWorld, afterEnvironment] at whole
  simpa only [quotedLoopBody] using whole

private theorem loopBody_delimiter (source : List Byte) (start : Nat)
    (delimiter byte : Byte) (offset : Nat)
    (inBounds : offset < source.length)
    (byteEq : byte = source.get ⟨offset, inBounds⟩)
    (notNewline : byte.val ≠ 10) (isDelimiter : byte = delimiter)
    (bound : offset + 1 ≤ 2147483647) :
    Command.Evaluates termMachine statefulMachine
      (runtime source start delimiter offset false).world
      (runtime source start delimiter offset false).environment
      quotedLoopBody
      (.returned (some (ScanEnd.value true (Int.ofNat (offset + 1)) 0)))
      (runtime source start delimiter offset false).world
      (runtime source start delimiter offset false).environment := by
  obtain ⟨integerInBounds, byteResult⟩ :=
    currentByte_evaluates source start delimiter offset false inBounds
  have mappedByte : (sourceIntegers source).get
      ⟨offset, integerInBounds⟩ = Int.ofNat byte.val := by
    subst byte
    simp [sourceIntegers]
  rw [mappedByte] at byteResult
  have bodyResult := unescapedDelimiter_evaluates source start delimiter byte
    offset notNewline isDelimiter bound
  have whole := Command.Evaluates.letValue (type := i32Type)
    byteResult bodyResult
  have afterWorld :
      (loopRuntime source start delimiter offset false byte).world =
        (runtime source start delimiter offset false).world := by rfl
  have afterEnvironment : Env.pop
      (loopRuntime source start delimiter offset false byte).environment =
        (runtime source start delimiter offset false).environment := by
    exact Env.pop_push _ _
  rw [afterWorld, afterEnvironment] at whole
  simpa only [quotedLoopBody] using whole

private theorem loop_evaluates (source : List Byte) (start : Nat)
    (delimiter : Byte) (offset : Nat) (escaping : Bool)
    (sourceBound : source.length ≤ 2147483647)
    (offsetBound : offset ≤ source.length) :
    (∃ finalEscaping,
      scanQuotedBody delimiter escaping (source.drop offset) offset =
        .failure source.length ∧
      Command.Evaluates termMachine statefulMachine
        (runtime source start delimiter offset escaping).world
        (runtime source start delimiter offset escaping).environment
        quotedLoop .next
        (runtime source start delimiter source.length finalEscaping).world
        (runtime source start delimiter source.length finalEscaping).environment) ∨
    (∃ finalOffset finalEscaping,
      Command.Evaluates termMachine statefulMachine
        (runtime source start delimiter offset escaping).world
        (runtime source start delimiter offset escaping).environment
        quotedLoop
        (.returned (some (scanEndValue
          (scanQuotedBody delimiter escaping (source.drop offset) offset))))
        (runtime source start delimiter finalOffset finalEscaping).world
        (runtime source start delimiter finalOffset finalEscaping).environment) := by
  by_cases inBounds : offset < source.length
  · have condition := beforeEnd_evaluates source start delimiter offset escaping
    have conditionTrue : Term.evaluate termMachine
        (runtime source start delimiter offset escaping).world
        (runtime source start delimiter offset escaping).environment
        quotedBeforeEnd = .ok (.boolean true,
          (runtime source start delimiter offset escaping).world) := by
      simpa [inBounds] using condition
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
        rcases loop_evaluates source start delimiter (offset + 1) false
            sourceBound (Nat.succ_le_of_lt inBounds) with
          ⟨finalEscaping, resultEq, rest⟩ |
          ⟨finalOffset, finalEscaping, rest⟩
        · left
          exact ⟨finalEscaping, stepEq.trans resultEq,
            Command.Evaluates.whileNext conditionTrue bodyResult rest⟩
        · right
          refine ⟨finalOffset, finalEscaping, ?_⟩
          rw [stepEq]
          exact Command.Evaluates.whileNext conditionTrue bodyResult rest
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
          right
          refine ⟨offset, false, ?_⟩
          rw [resultEq]
          change Command.Evaluates termMachine statefulMachine
            (runtime source start delimiter offset false).world
            (runtime source start delimiter offset false).environment
            quotedLoop
            (.returned (some (ScanEnd.value false 0 (Int.ofNat offset))))
            (runtime source start delimiter offset false).world
            (runtime source start delimiter offset false).environment
          exact Command.Evaluates.whileReturn conditionTrue bodyResult
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
            right
            refine ⟨offset, false, ?_⟩
            rw [resultEq]
            change Command.Evaluates termMachine statefulMachine
              (runtime source start delimiter offset false).world
              (runtime source start delimiter offset false).environment
              quotedLoop
              (.returned (some
                (ScanEnd.value true (Int.ofNat (offset + 1)) 0)))
              (runtime source start delimiter offset false).world
              (runtime source start delimiter offset false).environment
            exact Command.Evaluates.whileReturn conditionTrue bodyResult
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
              · simp [newline, closes, escape, nextEscaping]
              · simp [newline, closes, escape, nextEscaping]
            rcases loop_evaluates source start delimiter (offset + 1)
                nextEscaping sourceBound (Nat.succ_le_of_lt inBounds) with
              ⟨finalEscaping, resultEq, rest⟩ |
              ⟨finalOffset, finalEscaping, rest⟩
            · left
              exact ⟨finalEscaping, stepEq.trans resultEq,
                Command.Evaluates.whileNext conditionTrue bodyResult rest⟩
            · right
              refine ⟨finalOffset, finalEscaping, ?_⟩
              rw [stepEq]
              exact Command.Evaluates.whileNext conditionTrue bodyResult rest
  · have atEnd : offset = source.length :=
      Nat.le_antisymm offsetBound (Nat.le_of_not_gt inBounds)
    have condition := beforeEnd_evaluates source start delimiter offset escaping
    have conditionFalse : Term.evaluate termMachine
        (runtime source start delimiter offset escaping).world
        (runtime source start delimiter offset escaping).environment
        quotedBeforeEnd = .ok (.boolean false,
          (runtime source start delimiter offset escaping).world) := by
      simpa [inBounds] using condition
    left
    refine ⟨escaping, ?_, ?_⟩
    · simp [atEnd, scanQuotedBody]
    · simpa [quotedLoop, atEnd] using
        (Command.Evaluates.whileFalse (body := quotedLoopBody) conditionFalse)
termination_by source.length - offset
decreasing_by all_goals omega

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
      Command.Evaluates termMachine statefulMachine
        (runtime source start delimiter offset escaping).world
        (runtime source start delimiter offset escaping).environment
        (.sequence quotedLoop
          (.sequence (.returnValue (some failedAtBound)) .skip))
        (.returned (some (scanEndValue
          (scanQuotedBody delimiter escaping (source.drop offset) offset))))
        (runtime source start delimiter finalOffset finalEscaping).world
        (runtime source start delimiter finalOffset finalEscaping).environment := by
  rcases loop_evaluates source start delimiter offset escaping sourceBound
      offsetBound with ⟨finalEscaping, resultEq, loopResult⟩ |
      ⟨finalOffset, finalEscaping, loopResult⟩
  · refine ⟨source.length, finalEscaping, ?_⟩
    have failedResult := failedAtBound_evaluates source start delimiter
      source.length finalEscaping
    have returned : Command.Evaluates termMachine statefulMachine
        (runtime source start delimiter source.length finalEscaping).world
        (runtime source start delimiter source.length finalEscaping).environment
        (.returnValue (some failedAtBound))
        (.returned (some
          (ScanEnd.value false 0 (Int.ofNat source.length))))
        (runtime source start delimiter source.length finalEscaping).world
        (runtime source start delimiter source.length finalEscaping).environment :=
      .returnSome (by simpa [runtime_world] using failedResult)
    have returnedWithSkip : Command.Evaluates termMachine statefulMachine
        (runtime source start delimiter source.length finalEscaping).world
        (runtime source start delimiter source.length finalEscaping).environment
        (.sequence (.returnValue (some failedAtBound)) .skip)
        (.returned (some
          (ScanEnd.value false 0 (Int.ofNat source.length))))
        (runtime source start delimiter source.length finalEscaping).world
        (runtime source start delimiter source.length finalEscaping).environment :=
      Command.Evaluates.sequenceStop returned (by simp)
    rw [resultEq]
    change Command.Evaluates termMachine statefulMachine
      (runtime source start delimiter offset escaping).world
      (runtime source start delimiter offset escaping).environment
      (.sequence quotedLoop
        (.sequence (.returnValue (some failedAtBound)) .skip))
      (.returned (some
        (ScanEnd.value false 0 (Int.ofNat source.length))))
      (runtime source start delimiter source.length finalEscaping).world
      (runtime source start delimiter source.length finalEscaping).environment
    exact Command.Evaluates.sequenceNext loopResult returnedWithSkip
  · exact ⟨finalOffset, finalEscaping,
      Command.Evaluates.sequenceStop loopResult (by simp)⟩

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
    unfold quotedInitializer apply
    apply Term.evaluate_apply2 (by rfl) (by rfl)
    change ReadOnly.evaluateOperation verifiedFrontendLexerCore (world source)
      (.binary .add i32Type i32Type i32Type)
      [.signed .i32 (Int.ofNat start), .signed .i32 1] = _
    exact ReadOnly.evaluateOperation_i32_add
      (program := verifiedFrontendLexerCore) (world := world source)
      (leftType := i32Type) (rightType := i32Type) (outputType := i32Type)
      start 1 initialI32Bound
  have escapingResult : Term.evaluate termMachine (world source)
      ((parameterEnvironment source start delimiter).push
        (.signed .i32 (Int.ofNat initialOffset)))
      (literal (.boolean false)) =
      .ok (.boolean false, world source) := by rfl
  have pushed : ((parameterEnvironment source start delimiter).push
      (.signed .i32 (Int.ofNat initialOffset))).push (.boolean false) =
      (runtime source start delimiter initialOffset false).environment := by
    funext index
    have cases : index.val = 0 ∨ index.val = 1 ∨ index.val = 2 ∨
        index.val = 3 ∨ index.val = 4 ∨ index.val = 5 := by omega
    rcases cases with zero | one | two | three | four | five
    · have same : index = ⟨0, by omega⟩ := Fin.ext zero
      rw [same]
      rfl
    · have same : index = ⟨1, by omega⟩ := Fin.ext one
      rw [same]
      rfl
    · have same : index = ⟨2, by omega⟩ := Fin.ext two
      rw [same]
      rfl
    · have same : index = ⟨3, by omega⟩ := Fin.ext three
      rw [same]
      rfl
    · have same : index = ⟨4, by omega⟩ := Fin.ext four
      rw [same]
      rfl
    · have same : index = ⟨5, by omega⟩ := Fin.ext five
      rw [same]
      rfl
  obtain ⟨finalOffset, finalEscaping, bodyResult⟩ :=
    loopAndFallback_evaluates source start delimiter initialOffset false
      sourceBound initialOffsetBound
  have escapingLet := Command.Evaluates.letValue
    (type := .scalar .bool) escapingResult (by
      rw [pushed]
      exact bodyResult)
  have offsetLet := Command.Evaluates.letValue (type := i32Type)
    initializerResult escapingLet
  exact ⟨_, _, by
    simpa [quotedCommand, scanQuotedEnd, initialOffset] using offsetLet⟩

private def localCells : Fin 4 → CellId :=
  fun index => index.val + 1

private theorem quotedParameterState_represents (source : List Byte)
    (start : Nat) (delimiter : Byte) :
    Representation identityLayout localCells (world source)
      (parameterEnvironment source start delimiter)
      (quotedParameterState source start delimiter) := by
  have wellFormed := quotedParameterState_well_formed source start delimiter
  refine {
    worldOwned := ?_
    localOwned := ?_
    localCellsInjective := ?_
    worldLocalsDisjoint := ?_
  }
  · rw [World.owns_iff_represents wellFormed]
    apply World.singleton_represents wellFormed
    simp [world, sourceIntegers, sourceValues, signedI32Values,
      quotedParameterState, State.bindLocals, State.bindLocal,
      State.bindCell, sourceState, State.cellEntry?]
  · intro index
    have cases : index.val = 0 ∨ index.val = 1 ∨ index.val = 2 ∨
        index.val = 3 := by omega
    rcases cases with zero | one | two | three
    · have same : index = ⟨0, by omega⟩ := Fin.ext zero
      rw [same]
      simp [identityLayout, localCells, parameterEnvironment,
        quotedParameterState, State.bindLocals, State.bindLocal,
        State.bindCell, sourceState, Assertion.localPointsTo,
        State.cellId?, State.cellEntry?, i32Type]
    · have same : index = ⟨1, by omega⟩ := Fin.ext one
      rw [same]
      simp [identityLayout, localCells, parameterEnvironment,
        quotedParameterState, State.bindLocals, State.bindLocal,
        State.bindCell, sourceState, Assertion.localPointsTo,
        State.cellId?, State.cellEntry?, i32Type]
    · have same : index = ⟨2, by omega⟩ := Fin.ext two
      rw [same]
      simp [identityLayout, localCells, parameterEnvironment,
        quotedParameterState, State.bindLocals, State.bindLocal,
        State.bindCell, sourceState, Assertion.localPointsTo,
        State.cellId?, State.cellEntry?, i32Type]
    · have same : index = ⟨3, by omega⟩ := Fin.ext three
      rw [same]
      simp [identityLayout, localCells, parameterEnvironment,
        quotedParameterState, State.bindLocals, State.bindLocal,
        State.bindCell, sourceState, Assertion.localPointsTo,
        State.cellId?, State.cellEntry?, i32Type]
  · intro left right same
    apply Fin.ext
    simp [localCells] at same
    omega
  · intro cell worldMember localMember
    obtain ⟨values, found⟩ := worldMember
    have cellZero : cell = 0 := by
      by_cases same : cell = 0
      · exact same
      · simp [world, World.singleton, same] at found
    subst cell
    obtain ⟨index, localZero⟩ := localMember
    have positive : 0 < localCells index := by simp [localCells]
    simp [localCells] at localZero

private def nestedLocalCells : Fin 4 → CellId :=
  fun index => index.val + 4

private theorem quotedParameterStateFromScanner_well_formed
    (source : List Byte) (start : Nat) (delimiter : Byte) :
    StateWellFormed
      (quotedParameterStateFrom (scannerParameterState source start)
        source start delimiter) := by
  unfold quotedParameterStateFrom State.bindLocals
  simp only [List.foldl]
  exact bindLocal_preserves_well_formed _ 3 (.signed .i32 delimiter.val)
    (bindLocal_preserves_well_formed _ 2 (.signed .i32 start)
      (bindLocal_preserves_well_formed _ 1 (.signed .i32 source.length)
        (bindLocal_preserves_well_formed _ 0
          (.slice i32Type 0 [] 0 source.length)
          (clearLocals_well_formed _
            (scannerParameterState_well_formed source start)))))

private theorem quotedParameterStateFromScanner_represents
    (source : List Byte) (start : Nat) (delimiter : Byte) :
    Representation identityLayout nestedLocalCells (world source)
      (parameterEnvironment source start delimiter)
      (quotedParameterStateFrom (scannerParameterState source start)
        source start delimiter) := by
  have wellFormed :=
    quotedParameterStateFromScanner_well_formed source start delimiter
  refine {
    worldOwned := ?_
    localOwned := ?_
    localCellsInjective := ?_
    worldLocalsDisjoint := ?_
  }
  · rw [World.owns_iff_represents wellFormed]
    apply World.singleton_represents wellFormed
    simp [world, sourceIntegers, sourceValues, signedI32Values,
      quotedParameterStateFrom, scannerParameterState, clearLocals,
      State.bindLocals, State.bindLocal, State.bindCell, sourceState,
      State.cellEntry?]
  · intro index
    have cases : index.val = 0 ∨ index.val = 1 ∨ index.val = 2 ∨
        index.val = 3 := by omega
    rcases cases with zero | one | two | three
    · have same : index = ⟨0, by omega⟩ := Fin.ext zero
      rw [same]
      simp [identityLayout, nestedLocalCells, parameterEnvironment,
        quotedParameterStateFrom, scannerParameterState, clearLocals,
        State.bindLocals, State.bindLocal, State.bindCell, sourceState,
        Assertion.localPointsTo, State.cellId?, State.cellEntry?, i32Type]
    · have same : index = ⟨1, by omega⟩ := Fin.ext one
      rw [same]
      simp [identityLayout, nestedLocalCells, parameterEnvironment,
        quotedParameterStateFrom, scannerParameterState, clearLocals,
        State.bindLocals, State.bindLocal, State.bindCell, sourceState,
        Assertion.localPointsTo, State.cellId?, State.cellEntry?, i32Type]
    · have same : index = ⟨2, by omega⟩ := Fin.ext two
      rw [same]
      simp [identityLayout, nestedLocalCells, parameterEnvironment,
        quotedParameterStateFrom, scannerParameterState, clearLocals,
        State.bindLocals, State.bindLocal, State.bindCell, sourceState,
        Assertion.localPointsTo, State.cellId?, State.cellEntry?, i32Type]
    · have same : index = ⟨3, by omega⟩ := Fin.ext three
      rw [same]
      simp [identityLayout, nestedLocalCells, parameterEnvironment,
        quotedParameterStateFrom, scannerParameterState, clearLocals,
        State.bindLocals, State.bindLocal, State.bindCell, sourceState,
        Assertion.localPointsTo, State.cellId?, State.cellEntry?, i32Type]
  · intro left right same
    apply Fin.ext
    simp [nestedLocalCells] at same
    omega
  · intro cell worldMember localMember
    obtain ⟨values, found⟩ := worldMember
    have cellZero : cell = 0 := by
      by_cases same : cell = 0
      · exact same
      · simp [world, World.singleton, same] at found
    subst cell
    obtain ⟨index, localZero⟩ := localMember
    have positive : 0 < nestedLocalCells index := by
      simp [nestedLocalCells]
    exact (Nat.ne_of_gt positive) localZero

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
