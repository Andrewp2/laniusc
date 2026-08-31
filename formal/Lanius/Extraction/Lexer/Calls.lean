import Lanius.Extraction.FrontendProgramExtensions
import Lanius.Extraction.Lexer.Predicates
import Lanius.Extraction.Lexer.ScanEnd
import Lanius.Extraction.Lexer.Scanners
import Lanius.Extraction.Lexer.LineComment
import Lanius.Extraction.Lexer.BlockComment
import Lanius.Extraction.Lexer.QuotedWrappers
import Lanius.FunctionalViewCoreCallFrame
import Lanius.FunctionalViewCoreFreshSimulation
import Lanius.FunctionalViewCoreStatefulCallRefinement
import Lanius.FunctionalViewLoop

namespace Lanius.Extraction.Lexer.Calls

open Lanius
open Lanius.Core
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.CallContracts
open Lanius.FunctionalView
open Lanius.FunctionalView.Stateful
open Lanius.FunctionalView.Stateful.Loop
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly
open Lanius.FunctionalView.Core.Effectful
open Lanius.FunctionalView.Core.Stateful
open Lanius.Extraction
open Lanius.Compiler.Lexer
open Lanius.Extraction.Lexer.Functions

/-! # Checked merged-program calls used by `raw_lexer.lani::scan_one`

This module is intentionally stated over `verifiedFrontendCore`.  The older
lexer proofs execute in the separately checked `lexer.lani` unit; a frontend
caller, however, evaluates its argument expressions in the merged program.
The adapters below therefore use the supplied merged argument execution,
execute the exact checked lexer body, and transport only that successful body
execution through `RuntimeExtends`.
-/

def decimalDigitCalls : CallModel where
  evaluate := fun world function arguments =>
    if function = isDecimalDigitFunction.id then
      match arguments with
      | [.signed .i32 (.ofNat byte)] =>
          if bounded : byte < 256 then
            let sourceByte : Byte := ⟨byte, bounded⟩
            .ok (.boolean (isDecimalDigit sourceByte), world)
          else .error .typeMismatch
      | _ => .error .typeMismatch
    else .error .invalidPointer

def classifyStartCalls : CallModel where
  evaluate := fun world function arguments =>
    if function = classifyStartFunction.id then
      match arguments with
      | [.signed .i32 (.ofNat byte)] =>
          if bounded : byte < 256 then
            let sourceByte : Byte := ⟨byte, bounded⟩
            .ok (.signed .i32 (Int.ofNat (classifyStartCode sourceByte)), world)
          else .error .typeMismatch
      | _ => .error .typeMismatch
    else .error .invalidPointer

def accessorCalls (function : FunctionId) (field : FieldId) : CallModel where
  evaluate := fun world candidate arguments =>
    if candidate = function then
      match arguments with
      | [.structure 0 [.boolean success, .signed .i32 endOffset,
          .signed .i32 errorOffset]] =>
          match [Value.boolean success, .signed .i32 endOffset,
              .signed .i32 errorOffset][field]? with
          | some result => .ok (result, world)
          | none => .error .typeMismatch
      | _ => .error .typeMismatch
    else .error .invalidPointer

def scanSucceededCalls : CallModel := accessorCalls scanSucceededFunction.id 0
def scanEndOffsetCalls : CallModel := accessorCalls scanEndOffsetFunction.id 1
def scanErrorOffsetCalls : CallModel := accessorCalls scanErrorOffsetFunction.id 2

def baseCallModel : CallModel :=
  CallModel.route (fun id => id = isDecimalDigitFunction.id)
    decimalDigitCalls
    (CallModel.route (fun id => id = classifyStartFunction.id)
      classifyStartCalls
      (CallModel.route (fun id => id = scanSucceededFunction.id)
        scanSucceededCalls
        (CallModel.route (fun id => id = scanEndOffsetFunction.id)
          scanEndOffsetCalls scanErrorOffsetCalls)))

@[simp] theorem decimalDigitCalls_at
    (world : World) (byte : Byte) :
    decimalDigitCalls.evaluate world isDecimalDigitFunction.id
        [.signed .i32 (Int.ofNat byte.val)] =
      .ok (.boolean (isDecimalDigit byte), world) := by
  simp [decimalDigitCalls, isDecimalDigit]

@[simp] theorem classifyStartCalls_at
    (world : World) (byte : Byte) :
    classifyStartCalls.evaluate world classifyStartFunction.id
        [.signed .i32 (Int.ofNat byte.val)] =
      .ok (.signed .i32 (Int.ofNat (classifyStartCode byte)), world) := by
  have byteNonnegative : (0 : Int) ≤ Int.ofNat byte.val := Int.natCast_nonneg _
  simp [classifyStartCalls, byte.isLt]

@[simp] theorem scanSucceededCalls_at
    (world : World) (success : Bool) (endOffset errorOffset : Int) :
    scanSucceededCalls.evaluate world scanSucceededFunction.id
        [ScanEnd.value success endOffset errorOffset] =
      .ok (.boolean success, world) := by
  rfl

@[simp] theorem scanEndOffsetCalls_at
    (world : World) (success : Bool) (endOffset errorOffset : Int) :
    scanEndOffsetCalls.evaluate world scanEndOffsetFunction.id
        [ScanEnd.value success endOffset errorOffset] =
      .ok (.signed .i32 endOffset, world) := by
  rfl

@[simp] theorem scanErrorOffsetCalls_at
    (world : World) (success : Bool) (endOffset errorOffset : Int) :
    scanErrorOffsetCalls.evaluate world scanErrorOffsetFunction.id
        [ScanEnd.value success endOffset errorOffset] =
      .ok (.signed .i32 errorOffset, world) := by
  rfl

private theorem unaryFramePreservingCallSoundness
    (function : Function) (resultFor : Byte → Value)
    (bodyExecutes : ∀ state, StateWellFormed state → ∀ byte,
      Executes verifiedFrontendLexerCore
        (Predicates.byteCalleeState state byte) (functionBody function)
        (.returned (some (resultFor byte)))
        (Predicates.byteCalleeState state byte))
    (found : verifiedFrontendLexerCore.function? function.id = some function)
    (parameters : function.parameters = [(0, .scalar (.signed .i32))])
    (hasBody : function.body = some (functionBody function))
    (model : CallModel)
    (modelSuccess : ∀ {world functionId arguments result afterWorld},
      model.evaluate world functionId arguments = .ok (result, afterWorld) →
      ∃ byte : Byte, functionId = function.id ∧
        arguments = [.signed .i32 (Int.ofNat byte.val)] ∧
        result = resultFor byte ∧ afterWorld = world) :
    FreshSimulation.FramePreservingCallSoundness verifiedFrontendCore model := by
  constructor
  · intro arity layout localCell beforeWorld afterWorld environment before
      afterArguments functionId arguments values value argumentWrites
      afterArgumentsWellFormed represented argumentsExecution argumentsEffect
      evaluated
    obtain ⟨byte, rfl, rfl, rfl, rfl⟩ := modelSuccess evaluated
    let callee := Predicates.byteCalleeState afterArguments byte
    let after := restoreLocals afterArguments callee
    have calleeWellFormed : StateWellFormed callee := by
      simpa [callee, Predicates.byteCalleeState] using
        (enterCall_preserves_wellFormed
          (bindings := parameterBindings (Predicates.byteEnvironment byte))
          afterArgumentsWellFormed)
    have bodySmall := bodyExecutes afterArguments afterArgumentsWellFormed byte
    have bodyMerged : Executes verifiedFrontendCore callee
        (functionBody function) (.returned (some (resultFor byte))) callee := by
      simpa [callee] using
        verifiedFrontendCore_extends_verifiedFrontendLexerCore.executes bodySmall
    have callExecution : Evaluates verifiedFrontendCore before
        (.call function.id (toCoreExprs layout arguments)) (resultFor byte)
        after := by
      apply evaluatesCallReturned argumentsExecution
        (verifiedFrontendCore_extends_verifiedFrontendLexerCore.function found)
      · rw [parameters]
        rfl
      · exact hasBody
      · change Executes verifiedFrontendCore callee (functionBody function)
          (.returned (some (resultFor byte))) callee
        exact bodyMerged
    have entered : StoreEffect CellSet.empty afterArguments callee := by
      simpa [callee, Predicates.byteCalleeState] using
        enterCall_effect afterArguments
          (parameterBindings (Predicates.byteEnvironment byte))
    have callEffect : ModifiesOnly CellSet.empty afterArguments after := by
      simpa [after, callee] using entered.restoreLocals
    have afterWellFormed : StateWellFormed after := by
      exact entered.restoreLocals_wellFormed afterArgumentsWellFormed
        calleeWellFormed
    have afterRepresented : Representation layout localCell afterWorld
        environment after := {
      worldOwned := callEffect.empty_preserves_assertion
        afterArgumentsWellFormed (World.owns afterWorld)
        represented.worldOwned
      localOwned := fun index => callEffect.empty_preserves_assertion
        afterArgumentsWellFormed
        (Assertion.localPointsTo (layout index) (localCell index)
          (some (environment index))) (represented.localOwned index)
      localCellsInjective := represented.localCellsInjective
      worldLocalsDisjoint := represented.worldLocalsDisjoint }
    exact ⟨after, callExecution, afterWellFormed, afterRepresented,
      argumentsEffect.trans_same (callEffect.weaken CellSet.empty_subset)⟩

private theorem decimalDigitCalls_success
    (evaluated : decimalDigitCalls.evaluate world function arguments =
      .ok (result, afterWorld)) :
    ∃ byte : Byte, function = isDecimalDigitFunction.id ∧
      arguments = [.signed .i32 (Int.ofNat byte.val)] ∧
      result = .boolean (isDecimalDigit byte) ∧ afterWorld = world := by
  simp only [decimalDigitCalls] at evaluated
  split at evaluated
  next functionEq =>
    split at evaluated
    next byte =>
      split at evaluated
      next bounded =>
        obtain ⟨rfl, rfl⟩ := evaluated
        let sourceByte : Byte := ⟨byte, bounded⟩
        refine ⟨sourceByte, functionEq, ?_, rfl, rfl⟩
        rfl
      next => contradiction
    next => contradiction
  next => contradiction

private theorem classifyStartCalls_success
    (evaluated : classifyStartCalls.evaluate world function arguments =
      .ok (result, afterWorld)) :
    ∃ byte : Byte, function = classifyStartFunction.id ∧
      arguments = [.signed .i32 (Int.ofNat byte.val)] ∧
      result = .signed .i32 (Int.ofNat (classifyStartCode byte)) ∧
      afterWorld = world := by
  simp only [classifyStartCalls] at evaluated
  split at evaluated
  next functionEq =>
    split at evaluated
    next byte =>
      split at evaluated
      next bounded =>
        obtain ⟨rfl, rfl⟩ := evaluated
        let sourceByte : Byte := ⟨byte, bounded⟩
        exact ⟨sourceByte, functionEq, rfl, rfl, rfl⟩
      next => contradiction
    next => contradiction
  next => contradiction

private theorem decimalDigitBody_executes
    (state : State) (wellFormed : StateWellFormed state) (byte : Byte) :
    Executes verifiedFrontendLexerCore
      (Predicates.byteCalleeState state byte)
      (functionBody isDecimalDigitFunction)
      (.returned (some (.boolean (isDecimalDigit byte))))
      (Predicates.byteCalleeState state byte) := by
  have expressionBase := Program.decimalDigitExpr_executes
    verifiedFrontendLexerCore
    state wellFormed byte
  have expression := Lanius.Fuel.evalExpr_done_at_larger_fuel
    (program := verifiedFrontendLexerCore)
    (by decide : 4 ≤ 8) expressionBase
  refine ⟨10, ?_⟩
  change execStmt 10 verifiedFrontendLexerCore
    (Program.unaryCalleeState state byte) extractedIsDecimalDigitBody = _
  rw [extracted_isDecimalDigitBody_shape]
  rw [Lanius.Semantics.execStmt.eq_def]
  simp only
  rw [Lanius.Semantics.execStmt.eq_def]
  simp only [Program.returnBool]
  rw [expression]
  rfl

theorem decimalDigitFramePreservingCallSoundness :
    FreshSimulation.FramePreservingCallSoundness verifiedFrontendCore
      decimalDigitCalls := by
  apply unaryFramePreservingCallSoundness isDecimalDigitFunction
    (fun byte => .boolean (isDecimalDigit byte))
    decimalDigitBody_executes
  · change verifiedFrontendLexerCore.function?
      extractedIsDecimalDigitFunction.id = some extractedIsDecimalDigitFunction
    exact verifiedFrontendLexerCore_finds_isDecimalDigit
  · rfl
  · rfl
  · exact decimalDigitCalls_success

theorem classifyStartFramePreservingCallSoundness :
    FreshSimulation.FramePreservingCallSoundness verifiedFrontendCore
      classifyStartCalls := by
  apply unaryFramePreservingCallSoundness classifyStartFunction
    (fun byte => .signed .i32 (Int.ofNat (classifyStartCode byte)))
    Predicates.classifyStartBody_executes
  · rfl
  · rfl
  · rfl
  · exact classifyStartCalls_success

private theorem accessorCalls_success
    (evaluated : (accessorCalls expectedFunction field).evaluate world
      function arguments = .ok (result, afterWorld)) :
    ∃ success endOffset errorOffset,
      function = expectedFunction ∧
      arguments = [ScanEnd.value success endOffset errorOffset] ∧
      [Value.boolean success, .signed .i32 endOffset,
          .signed .i32 errorOffset][field]? = some result ∧
      afterWorld = world := by
  simp only [accessorCalls] at evaluated
  split at evaluated
  next functionEq =>
    split at evaluated
    next success endOffset errorOffset =>
      split at evaluated
      next found =>
        obtain ⟨rfl, rfl⟩ := evaluated
        exact ⟨success, endOffset, errorOffset, functionEq, rfl, found, rfl⟩
      next => contradiction
    next => contradiction
  next => contradiction

private theorem accessorFramePreservingCallSoundness
    (function : Function) (field : FieldId)
    (resultFor : Bool → Int → Int → Value)
    (fieldResult : ∀ success endOffset errorOffset,
      [Value.boolean success, .signed .i32 endOffset,
          .signed .i32 errorOffset][field]? =
        some (resultFor success endOffset errorOffset))
    (bodyExecutes : ∀ state, StateWellFormed state →
      ∀ success endOffset errorOffset,
      Executes verifiedFrontendLexerCore
        (ScanEnd.resultCalleeState state success endOffset errorOffset)
        (functionBody function)
        (.returned (some (resultFor success endOffset errorOffset)))
        (ScanEnd.resultCalleeState state success endOffset errorOffset))
    (found : verifiedFrontendLexerCore.function? function.id = some function)
    (parameters : function.parameters = [(0, .structure 0)])
    (hasBody : function.body = some (functionBody function)) :
    FreshSimulation.FramePreservingCallSoundness verifiedFrontendCore
      (accessorCalls function.id field) := by
  constructor
  · intro arity layout localCell beforeWorld afterWorld environment before
      afterArguments functionId arguments values value argumentWrites
      afterArgumentsWellFormed represented argumentsExecution argumentsEffect
      evaluated
    obtain ⟨success, endOffset, errorOffset, rfl, rfl, selected, rfl⟩ :=
      accessorCalls_success evaluated
    rw [fieldResult] at selected
    cases selected
    let callee := ScanEnd.resultCalleeState afterArguments success
      endOffset errorOffset
    let after := ScanEnd.resultCallState afterArguments success
      endOffset errorOffset
    have calleeWellFormed : StateWellFormed callee := by
      simpa [callee, ScanEnd.resultCalleeState] using
        (enterCall_preserves_wellFormed
          (bindings := parameterBindings
            (ScanEnd.resultEnvironment success endOffset errorOffset))
          afterArgumentsWellFormed)
    have bodySmall := bodyExecutes afterArguments afterArgumentsWellFormed
      success endOffset errorOffset
    have bodyMerged : Executes verifiedFrontendCore callee
        (functionBody function)
        (.returned (some (resultFor success endOffset errorOffset))) callee := by
      simpa [callee] using
        verifiedFrontendCore_extends_verifiedFrontendLexerCore.executes bodySmall
    have callExecution : Evaluates verifiedFrontendCore before
        (.call function.id (toCoreExprs layout arguments))
        (resultFor success endOffset errorOffset) after := by
      apply evaluatesCallReturned argumentsExecution
      · exact verifiedFrontendCore_extends_verifiedFrontendLexerCore.function
          found
      · rw [parameters]
        rfl
      · exact hasBody
      · change Executes verifiedFrontendCore callee (functionBody function)
          (.returned (some (resultFor success endOffset errorOffset))) callee
        exact bodyMerged
    have entered : StoreEffect CellSet.empty afterArguments callee := by
      simpa [callee, ScanEnd.resultCalleeState] using
        enterCall_effect afterArguments
          (parameterBindings
            (ScanEnd.resultEnvironment success endOffset errorOffset))
    have callEffect : ModifiesOnly CellSet.empty afterArguments after := by
      simpa [after, ScanEnd.resultCallState, callee] using entered.restoreLocals
    have afterWellFormed : StateWellFormed after := by
      exact entered.restoreLocals_wellFormed afterArgumentsWellFormed
        calleeWellFormed
    have afterRepresented : Representation layout localCell afterWorld
        environment after := {
      worldOwned := callEffect.empty_preserves_assertion
        afterArgumentsWellFormed (World.owns afterWorld)
        represented.worldOwned
      localOwned := fun index => callEffect.empty_preserves_assertion
        afterArgumentsWellFormed
        (Assertion.localPointsTo (layout index) (localCell index)
          (some (environment index))) (represented.localOwned index)
      localCellsInjective := represented.localCellsInjective
      worldLocalsDisjoint := represented.worldLocalsDisjoint }
    exact ⟨after, callExecution, afterWellFormed, afterRepresented,
      argumentsEffect.trans_same (callEffect.weaken CellSet.empty_subset)⟩

theorem scanSucceededFramePreservingCallSoundness :
    FreshSimulation.FramePreservingCallSoundness verifiedFrontendCore
      scanSucceededCalls := by
  exact accessorFramePreservingCallSoundness scanSucceededFunction 0
    (fun success _ _ => .boolean success) (by intros; rfl)
    ScanEnd.scanSucceededBody_executes (by rfl) (by rfl) (by rfl)

theorem scanEndOffsetFramePreservingCallSoundness :
    FreshSimulation.FramePreservingCallSoundness verifiedFrontendCore
      scanEndOffsetCalls := by
  exact accessorFramePreservingCallSoundness scanEndOffsetFunction 1
    (fun _ endOffset _ => .signed .i32 endOffset) (by intros; rfl)
    ScanEnd.scanEndOffsetBody_executes (by rfl) (by rfl) (by rfl)

theorem scanErrorOffsetFramePreservingCallSoundness :
    FreshSimulation.FramePreservingCallSoundness verifiedFrontendCore
      scanErrorOffsetCalls := by
  exact accessorFramePreservingCallSoundness scanErrorOffsetFunction 2
    (fun _ _ errorOffset => .signed .i32 errorOffset) (by intros; rfl)
    ScanEnd.scanErrorOffsetBody_executes (by rfl) (by rfl) (by rfl)

theorem baseFramePreservingCallSoundness :
    FreshSimulation.FramePreservingCallSoundness verifiedFrontendCore
      baseCallModel := by
  apply FreshSimulation.FramePreservingCallSoundness.route
    decimalDigitFramePreservingCallSoundness
  apply FreshSimulation.FramePreservingCallSoundness.route
    classifyStartFramePreservingCallSoundness
  apply FreshSimulation.FramePreservingCallSoundness.route
    scanSucceededFramePreservingCallSoundness
  apply FreshSimulation.FramePreservingCallSoundness.route
    scanEndOffsetFramePreservingCallSoundness
  exact scanErrorOffsetFramePreservingCallSoundness

private def constructorEnvironment (offset : Int) : Env 1 :=
  fun _ => .signed .i32 offset

private def constructorBindings (offset : Int) : List (VarId × Value) :=
  parameterBindings (constructorEnvironment offset)

private def constructorCallee (state : State) (offset : Int) : State :=
  enterCall state (constructorBindings offset)

private theorem constructorBody_executes
    (state : State) (wellFormed : StateWellFormed state)
    (function : Function) (block : Block signature 1) (offset : Int)
    (result : Value)
    (evaluated : Block.evaluate (ReadOnly.machine verifiedFrontendLexerCore)
      ScanEnd.world (constructorEnvironment offset) block =
        .done (.returned (some result)) ScanEnd.world)
    (exact : toCoreStmt identityLayout 1 block = functionBody function)
    (noLocals : localCapacity block = 0) :
    Executes verifiedFrontendLexerCore (constructorCallee state offset)
      (functionBody function) (.returned (some result))
      (constructorCallee state offset) := by
  have represented : ReadOnly.World.Represents ScanEnd.world
      (constructorCallee state offset) := by
    intro cell contents found
    simp [ScanEnd.world] at found
  have environmentMatches : EnvironmentMatches identityLayout
      (constructorEnvironment offset) (constructorCallee state offset) := by
    simpa [constructorCallee, constructorBindings, constructorEnvironment]
      using (enterCall_parameterBindings_matches
        (environment := constructorEnvironment offset) wellFormed)
  have execution := block_executes_without_locals
    (nextLocal := 1) (ReadOnly.bridge verifiedFrontendLexerCore) represented
    environmentMatches noLocals evaluated
  rw [exact] at execution
  simpa [Lanius.FunctionalView.Core.toCoreCompletion] using execution.1

private theorem successfulConstructorBody_executes
    (state : State) (wellFormed : StateWellFormed state) (offset : Int) :
    Executes verifiedFrontendLexerCore (constructorCallee state offset)
      (functionBody successfulScanFunction)
      (.returned (some (ScanEnd.value true offset 0)))
      (constructorCallee state offset) := by
  exact constructorBody_executes state wellFormed successfulScanFunction
    successfulScanBlock offset (ScanEnd.value true offset 0)
    (ScanEnd.successfulScanBlock_evaluates offset)
    successfulScanBlock_toCore_exactly (by native_decide)

private theorem failedConstructorBody_executes
    (state : State) (wellFormed : StateWellFormed state) (offset : Int) :
    Executes verifiedFrontendLexerCore (constructorCallee state offset)
      (functionBody failedScanFunction)
      (.returned (some (ScanEnd.value false 0 offset)))
      (constructorCallee state offset) := by
  exact constructorBody_executes state wellFormed failedScanFunction
    failedScanBlock offset (ScanEnd.value false 0 offset)
    (ScanEnd.failedScanBlock_evaluates offset)
    failedScanBlock_toCore_exactly (by native_decide)

private theorem scanEndConstructorCalls_success
    (evaluated : ScanEndCalls.calls.evaluate world function arguments =
      .ok (result, afterWorld)) :
    (∃ offset, function = successfulScanFunction.id ∧
      arguments = [.signed .i32 offset] ∧
      result = ScanEnd.value true offset 0 ∧ afterWorld = world) ∨
    (∃ offset, function = failedScanFunction.id ∧
      arguments = [.signed .i32 offset] ∧
      result = ScanEnd.value false 0 offset ∧ afterWorld = world) := by
  simp only [ScanEndCalls.calls] at evaluated
  split at evaluated
  next offset =>
    split at evaluated
    next successful =>
      obtain ⟨rfl, rfl⟩ := evaluated
      exact .inl ⟨offset, successful, rfl, rfl, rfl⟩
    next =>
      split at evaluated
      next failed =>
        obtain ⟨rfl, rfl⟩ := evaluated
        exact .inr ⟨offset, failed, rfl, rfl, rfl⟩
      next => contradiction
  next => contradiction

private theorem scanEndConstructorFramePreservingCallSoundnessFor
    (program : Program)
    (extension : verifiedFrontendLexerCore.RuntimeExtends program) :
    FreshSimulation.FramePreservingCallSoundness program ScanEndCalls.calls := by
  constructor
  intro arity layout localCell beforeWorld afterWorld environment before
    afterArguments function arguments values result argumentWrites
    afterArgumentsWellFormed represented argumentsExecution argumentsEffect
    evaluated
  rcases scanEndConstructorCalls_success evaluated with
    ⟨offset, rfl, rfl, rfl, worldEq⟩ | ⟨offset, rfl, rfl, rfl, worldEq⟩
  · subst afterWorld
    let callee := constructorCallee afterArguments offset
    let after := restoreLocals afterArguments callee
    have bodySmall := successfulConstructorBody_executes afterArguments
      afterArgumentsWellFormed offset
    have bodyMerged : Executes program callee
        (functionBody successfulScanFunction)
        (.returned (some (ScanEnd.value true offset 0))) callee := by
      simpa [callee] using
        extension.executes bodySmall
    have execution : Evaluates program before
        (.call successfulScanFunction.id (toCoreExprs layout arguments))
        (ScanEnd.value true offset 0) after := by
      apply evaluatesCallReturned
        (bindings := constructorBindings offset)
        (body := functionBody successfulScanFunction) argumentsExecution
      · exact extension.function (by rfl)
      · rfl
      · rfl
      · simpa [callee, constructorCallee] using bodyMerged
    have entered : StoreEffect CellSet.empty afterArguments callee := by
      simpa [callee, constructorCallee] using
        enterCall_effect afterArguments (constructorBindings offset)
    have callEffect : ModifiesOnly CellSet.empty afterArguments after := by
      simpa [after] using entered.restoreLocals
    have afterWellFormed := entered.restoreLocals_wellFormed
      afterArgumentsWellFormed (by
        simpa [callee, constructorCallee] using
          enterCall_preserves_wellFormed
            (bindings := constructorBindings offset) afterArgumentsWellFormed)
    have afterRepresented : Representation layout localCell beforeWorld
        environment after := {
      worldOwned := callEffect.empty_preserves_assertion
        afterArgumentsWellFormed (World.owns beforeWorld) represented.worldOwned
      localOwned := fun index => callEffect.empty_preserves_assertion
        afterArgumentsWellFormed
        (Assertion.localPointsTo (layout index) (localCell index)
          (some (environment index))) (represented.localOwned index)
      localCellsInjective := represented.localCellsInjective
      worldLocalsDisjoint := represented.worldLocalsDisjoint }
    exact ⟨after, execution, afterWellFormed, afterRepresented,
      argumentsEffect.trans_same (callEffect.weaken CellSet.empty_subset)⟩
  · subst afterWorld
    let callee := constructorCallee afterArguments offset
    let after := restoreLocals afterArguments callee
    have bodySmall := failedConstructorBody_executes afterArguments
      afterArgumentsWellFormed offset
    have bodyMerged : Executes program callee
        (functionBody failedScanFunction)
        (.returned (some (ScanEnd.value false 0 offset))) callee := by
      simpa [callee] using
        extension.executes bodySmall
    have execution : Evaluates program before
        (.call failedScanFunction.id (toCoreExprs layout arguments))
        (ScanEnd.value false 0 offset) after := by
      apply evaluatesCallReturned
        (bindings := constructorBindings offset)
        (body := functionBody failedScanFunction) argumentsExecution
      · exact extension.function (by rfl)
      · rfl
      · rfl
      · simpa [callee, constructorCallee] using bodyMerged
    have entered : StoreEffect CellSet.empty afterArguments callee := by
      simpa [callee, constructorCallee] using
        enterCall_effect afterArguments (constructorBindings offset)
    have callEffect : ModifiesOnly CellSet.empty afterArguments after := by
      simpa [after] using entered.restoreLocals
    have afterWellFormed := entered.restoreLocals_wellFormed
      afterArgumentsWellFormed (by
        simpa [callee, constructorCallee] using
          enterCall_preserves_wellFormed
            (bindings := constructorBindings offset) afterArgumentsWellFormed)
    have afterRepresented : Representation layout localCell beforeWorld
        environment after := {
      worldOwned := callEffect.empty_preserves_assertion
        afterArgumentsWellFormed (World.owns beforeWorld) represented.worldOwned
      localOwned := fun index => callEffect.empty_preserves_assertion
        afterArgumentsWellFormed
        (Assertion.localPointsTo (layout index) (localCell index)
          (some (environment index))) (represented.localOwned index)
      localCellsInjective := represented.localCellsInjective
      worldLocalsDisjoint := represented.worldLocalsDisjoint }
    exact ⟨after, execution, afterWellFormed, afterRepresented,
      argumentsEffect.trans_same (callEffect.weaken CellSet.empty_subset)⟩

theorem scanEndConstructorFramePreservingCallSoundness :
    FreshSimulation.FramePreservingCallSoundness verifiedFrontendCore
      ScanEndCalls.calls :=
  scanEndConstructorFramePreservingCallSoundnessFor verifiedFrontendCore
    verifiedFrontendCore_extends_verifiedFrontendLexerCore

private theorem scanEndConstructorLexerFramePreservingCallSoundness :
    FreshSimulation.FramePreservingCallSoundness verifiedFrontendLexerCore
      ScanEndCalls.calls :=
  scanEndConstructorFramePreservingCallSoundnessFor verifiedFrontendLexerCore
    (Core.Program.RuntimeExtends.refl verifiedFrontendLexerCore)

def sourceIntegers (source : List Byte) : List Int :=
  source.map fun byte => Int.ofNat byte.val

def sourceWorld (source : List Byte) : World :=
  World.singleton 0 (sourceIntegers source)

@[simp] theorem sourceWorld_finds (source : List Byte) :
    (sourceWorld source).i32Slice? 0 = some (sourceIntegers source) := by
  exact World.singleton_finds

def sourceSlice (source : List Byte) : Value :=
  .slice (.scalar (.signed .i32)) 0 [] 0 source.length

def scannerArguments (source : List Byte) (start : Nat) : List Value :=
  [sourceSlice source, .signed .i32 (Int.ofNat source.length),
    .signed .i32 (Int.ofNat start)]

def encodedScanEnd : ScanEnd → Value
  | .success finish => ScanEnd.value true (Int.ofNat finish) 0
  | .failure offset => ScanEnd.value false 0 (Int.ofNat offset)

def scannerCalls (source : List Byte) (expectedFunction : FunctionId)
    (requiresOpening : Bool) (resultFor : Nat → Value) : CallModel where
  evaluate := fun world function arguments =>
    match arguments with
    | [.slice (.scalar (.signed .i32)) 0 [] 0 sourceLength,
        .signed .i32 (.ofNat declaredLength), .signed .i32 (.ofNat start)] =>
      if sourceLength = source.length ∧
          declaredLength = source.length ∧ source.length ≤ 2147483647 ∧
          start < source.length ∧ start ≤ 2147483647 ∧
          world.i32Slice? 0 = some (sourceIntegers source) then
        if function = expectedFunction then
          if requiresOpening → start + 1 < source.length then
            .ok (resultFor start, world)
          else .error .typeMismatch
        else .error .invalidPointer
      else .error .typeMismatch
    | _ => .error .typeMismatch

@[simp] theorem scannerCalls_at_world
    (source : List Byte) (expectedFunction : FunctionId)
    (requiresOpening : Bool) (resultFor : Nat → Value)
    (world : World) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length)
    (startBound : start ≤ 2147483647)
    (openingInBounds : requiresOpening → start + 1 < source.length)
    (sourceFound : world.i32Slice? 0 = some (sourceIntegers source)) :
    (scannerCalls source expectedFunction requiresOpening resultFor).evaluate
        world expectedFunction (scannerArguments source start) =
      .ok (resultFor start, world) := by
  simp [scannerCalls, scannerArguments, sourceSlice, sourceBound, sourceFound]
  split <;> simp_all [Int.ofNat_inj] <;> omega

def identifierCalls (source : List Byte) : CallModel := scannerCalls source
  Scanners.scanIdentifierEndFunction.id false
  (fun start => .signed .i32 (Int.ofNat (scanIdentifierEnd source start)))

def whitespaceCalls (source : List Byte) : CallModel := scannerCalls source
  Scanners.scanWhitespaceEndFunction.id false
  (fun start => .signed .i32 (Int.ofNat (scanWhitespaceEnd source start)))

def stringCalls (source : List Byte) : CallModel := scannerCalls source
  Scanners.scanStringEndFunction.id false
  (fun start => encodedScanEnd
    (scanQuotedEnd source start Program.doubleQuoteByte))

def characterCalls (source : List Byte) : CallModel := scannerCalls source
  Scanners.scanCharacterEndFunction.id false
  (fun start => encodedScanEnd
    (scanQuotedEnd source start Program.singleQuoteByte))

def lineCommentCalls (source : List Byte) : CallModel := scannerCalls source
  Scanners.scanLineCommentEndFunction.id true
  (fun start => .signed .i32 (Int.ofNat (scanLineCommentEnd source start)))

def blockCommentCalls (source : List Byte) : CallModel := scannerCalls source
  Scanners.scanBlockCommentEndFunction.id true
  (fun start => encodedScanEnd (scanBlockCommentEnd source start))

def quotedAnyCalls (source : List Byte) : CallModel where
  evaluate := fun world function arguments =>
    match arguments with
    | [.slice (.scalar (.signed .i32)) 0 [] 0 sourceLength,
        .signed .i32 (.ofNat declaredLength), .signed .i32 (.ofNat start),
        .signed .i32 (.ofNat delimiterValue)] =>
      if bounded : delimiterValue < 256 then
        let delimiter : Byte := ⟨delimiterValue, bounded⟩
        if sourceLength = source.length ∧ declaredLength = source.length ∧
            source.length ≤ 2147483647 ∧ start < source.length ∧
            start ≤ 2147483647 ∧
            world.i32Slice? 0 = some (sourceIntegers source) then
          if function = Scanners.scanQuotedEndFunction.id then
            .ok (encodedScanEnd (scanQuotedEnd source start delimiter), world)
          else .error .invalidPointer
        else .error .typeMismatch
      else .error .typeMismatch
    | _ => .error .typeMismatch

def scannerCallModel (source : List Byte) : CallModel :=
  CallModel.route (fun id => id = Scanners.scanIdentifierEndFunction.id)
    (identifierCalls source)
    (CallModel.route (fun id => id = Scanners.scanWhitespaceEndFunction.id)
      (whitespaceCalls source)
      (CallModel.route (fun id => id = Scanners.scanStringEndFunction.id)
        (stringCalls source)
        (CallModel.route (fun id => id = Scanners.scanCharacterEndFunction.id)
          (characterCalls source)
          (CallModel.route
            (fun id => id = Scanners.scanLineCommentEndFunction.id)
            (lineCommentCalls source)
            (CallModel.route
              (fun id => id = Scanners.scanQuotedEndFunction.id)
              (quotedAnyCalls source) (blockCommentCalls source))))))

def callModel (source : List Byte) : CallModel :=
  CallModel.route (fun function =>
      function = isDecimalDigitFunction.id ∨
      function = classifyStartFunction.id ∨
      function = scanSucceededFunction.id ∨
      function = scanEndOffsetFunction.id ∨
      function = scanErrorOffsetFunction.id)
    baseCallModel
    (CallModel.route (fun function =>
        function = successfulScanFunction.id ∨
        function = failedScanFunction.id)
      ScanEndCalls.calls (scannerCallModel source))

private theorem frameExtension_modifiesEmpty
    (extension : Program.FrameExtension before after)
    (wellFormed : StateWellFormed before) :
    ModifiesOnly CellSet.empty before after := {
  oldCells := fun cell old _ => extension.oldCells cell old
  nextCell := extension.nextCell
  heap := extension.heap
  world := extension.world
  views := extension.views
  domain := by
    constructor
    intro entry member
    have old := wellFormed.cellIdsBelowNext entry member
    have foundBefore := Program.stateWellFormed_cellEntry_of_mem
      wellFormed member
    have foundAfter : after.cellEntry? entry.id = some entry := by
      rw [extension.oldCells entry.id old, foundBefore]
    exact ⟨entry, List.mem_of_find?_eq_some foundAfter, rfl⟩
  locals := extension.locals }

def predicateCalls (expectedFunction : FunctionId)
    (accept : Byte → Bool) : CallModel where
  evaluate := fun world function arguments =>
    if function = expectedFunction then
      match arguments with
      | [.signed .i32 (.ofNat byte)] =>
          if bounded : byte < 256 then
            .ok (.boolean (accept ⟨byte, bounded⟩), world)
          else .error .typeMismatch
      | _ => .error .typeMismatch
    else .error .invalidPointer

private theorem predicateCalls_success
    (evaluated : (predicateCalls expectedFunction accept).evaluate world
      function arguments = .ok (result, afterWorld)) :
    ∃ byte : Byte, function = expectedFunction ∧
      arguments = [.signed .i32 (Int.ofNat byte.val)] ∧
      result = .boolean (accept byte) ∧ afterWorld = world := by
  simp only [predicateCalls] at evaluated
  split at evaluated
  next functionEq =>
    split at evaluated
    next byte =>
      split at evaluated
      next bounded =>
        obtain ⟨rfl, rfl⟩ := evaluated
        exact ⟨⟨byte, bounded⟩, functionEq, rfl, rfl, rfl⟩
      next => contradiction
    next => contradiction
  next => contradiction

private theorem predicateFramePreservingSoundness
    (function : Function) (accept : Byte → Bool)
    (bodyFinal : State → Byte → State)
    (bodyExecutes : ∀ state, StateWellFormed state → ∀ byte,
      Executes verifiedFrontendLexerCore
        (Program.unaryCalleeState state byte) (functionBody function)
        (.returned (some (.boolean (accept byte)))) (bodyFinal state byte))
    (closedExtends : ∀ state byte,
      Program.FrameExtension state
        (restoreLocals state (bodyFinal state byte)))
    (closedWellFormed : ∀ state, StateWellFormed state → ∀ byte,
      StateWellFormed (restoreLocals state (bodyFinal state byte)))
    (found : verifiedFrontendLexerCore.function? function.id = some function)
    (parameters : function.parameters = [(0, Program.i32Type)])
    (hasBody : function.body = some (functionBody function)) :
    FreshSimulation.FramePreservingCallSoundness verifiedFrontendCore
      (predicateCalls function.id accept) := by
  constructor
  intro arity layout localCell beforeWorld afterWorld environment before
    afterArguments functionId arguments values result argumentWrites
    afterArgumentsWellFormed represented argumentsExecution argumentsEffect
    evaluated
  obtain ⟨byte, rfl, rfl, rfl, rfl⟩ := predicateCalls_success evaluated
  let completed := bodyFinal afterArguments byte
  let after := restoreLocals afterArguments completed
  have bodySmall := bodyExecutes afterArguments afterArgumentsWellFormed byte
  have bodyMerged : Executes verifiedFrontendCore
      (Program.unaryCalleeState afterArguments byte) (functionBody function)
      (.returned (some (.boolean (accept byte)))) completed := by
    simpa [completed] using
      verifiedFrontendCore_extends_verifiedFrontendLexerCore.executes bodySmall
  have callExecution : Evaluates verifiedFrontendCore before
      (.call function.id (toCoreExprs layout arguments))
      (.boolean (accept byte)) after := by
    apply evaluatesCallReturned
      (bindings := [(0, .signed .i32 (Int.ofNat byte.val))])
      (body := functionBody function) argumentsExecution
    · exact verifiedFrontendCore_extends_verifiedFrontendLexerCore.function found
    · rw [parameters]
      rfl
    · exact hasBody
    · simpa [Program.unaryCalleeState, Program.clearLocals, enterCall,
        State.bindLocals] using bodyMerged
  have afterWellFormed : StateWellFormed after := by
    simpa [after, completed] using
      closedWellFormed afterArguments afterArgumentsWellFormed byte
  have closed : Program.FrameExtension afterArguments after := by
    simpa [after, completed] using closedExtends afterArguments byte
  have callEffect : ModifiesOnly CellSet.empty afterArguments after :=
    frameExtension_modifiesEmpty closed afterArgumentsWellFormed
  have afterRepresented : Representation layout localCell afterWorld
      environment after := {
    worldOwned := callEffect.empty_preserves_assertion
      afterArgumentsWellFormed (World.owns afterWorld) represented.worldOwned
    localOwned := fun index => callEffect.empty_preserves_assertion
      afterArgumentsWellFormed
      (Assertion.localPointsTo (layout index) (localCell index)
        (some (environment index))) (represented.localOwned index)
    localCellsInjective := represented.localCellsInjective
    worldLocalsDisjoint := represented.worldLocalsDisjoint }
  exact ⟨after, callExecution, afterWellFormed, afterRepresented,
    argumentsEffect.trans_same
      (callEffect.weaken CellSet.empty_subset)⟩

def identifierPredicateCalls : CallModel :=
  predicateCalls isIdentifierContinueFunction.id isIdentifierContinue

def whitespacePredicateCalls : CallModel :=
  predicateCalls isWhitespaceFunction.id isWhitespace

private theorem whitespaceBody_executes
    (state : State) (wellFormed : StateWellFormed state) (byte : Byte) :
    Executes verifiedFrontendLexerCore
      (Program.unaryCalleeState state byte)
      (functionBody isWhitespaceFunction)
      (.returned (some (.boolean (isWhitespace byte))))
      (Program.unaryCalleeState state byte) := by
  change Executes verifiedFrontendLexerCore
    (Program.unaryCalleeState state byte) extractedIsWhitespaceBody
    (.returned (some (.boolean (isWhitespace byte))))
    (Program.unaryCalleeState state byte)
  exact ⟨14, extracted_isWhitespaceBody_executes_at_fuel state wellFormed byte⟩

theorem identifierPredicateFramePreservingSoundness :
    FreshSimulation.FramePreservingCallSoundness verifiedFrontendCore
      identifierPredicateCalls := by
  exact predicateFramePreservingSoundness isIdentifierContinueFunction
    isIdentifierContinue Program.identifierContinueBodyState
    Predicates.isIdentifierContinueBody_executes
    Program.identifierContinueCallState_extends
    Program.identifierContinueCallState_well_formed
    (by rfl) (by rfl) (by rfl)

theorem whitespacePredicateFramePreservingSoundness :
    FreshSimulation.FramePreservingCallSoundness verifiedFrontendCore
      whitespacePredicateCalls := by
  exact predicateFramePreservingSoundness isWhitespaceFunction isWhitespace
    (fun state byte => Program.unaryCalleeState state byte)
    whitespaceBody_executes Program.unaryCallState_extends
    Program.unaryCallState_well_formed (by rfl) (by rfl) (by rfl)

private abbrev T (arity : Nat) := Term signature arity
private abbrev C (arity : Nat) := Command signature actions arity

private def scannerSourceTerm : T 4 := reference ⟨0, by omega⟩
private def scannerBoundTerm : T 4 := reference ⟨1, by omega⟩
private def scannerCursorTerm : T 4 := reference ⟨3, by omega⟩

private def scannerPredicateTerm (predicate : FunctionId) : T 4 :=
  apply (.call predicate [Program.i32Type] (.scalar .bool))
    [apply (.index (.slice Program.i32Type) Program.i32Type Program.i32Type)
      [scannerSourceTerm, scannerCursorTerm]]

private def scannerLoopCondition (predicate : FunctionId) : T 4 :=
  logicalAnd
    (apply (.binary .less Program.i32Type Program.i32Type (.scalar .bool))
      [scannerCursorTerm, scannerBoundTerm])
    (scannerPredicateTerm predicate)

private def scannerLoopBody : C 4 :=
  .sequence
    (.updateLocal .add ⟨3, by omega⟩
      (literal (.signed .i32 1)))
    .skip

private def scannerCommand (predicate : FunctionId) : C 3 :=
  .letValue Program.i32Type
    (apply (.binary .add Program.i32Type Program.i32Type Program.i32Type)
      [reference ⟨2, by omega⟩, literal (.signed .i32 1)])
    (.sequence (.whileLoop (scannerLoopCondition predicate) scannerLoopBody)
      (.sequence (.returnValue (some scannerCursorTerm)) .skip))

private theorem identifierCommand_exact :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      identityLayout 3 (scannerCommand isIdentifierContinueFunction.id) =
      Scanners.scanIdentifierEndBody := by
  rfl

private theorem whitespaceCommand_exact :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      identityLayout 3 (scannerCommand isWhitespaceFunction.id) =
      Scanners.scanWhitespaceEndBody := by
  rfl

private def scannerParameterEnvironment (source : List Byte) (start : Nat) :
    Env 3
  | ⟨0, _⟩ => sourceSlice source
  | ⟨1, _⟩ => .signed .i32 (Int.ofNat source.length)
  | ⟨2, _⟩ => .signed .i32 (Int.ofNat start)

private def scannerLoopEnvironment (source : List Byte) (start cursor : Nat) :
    Env 4
  | ⟨0, _⟩ => sourceSlice source
  | ⟨1, _⟩ => .signed .i32 (Int.ofNat source.length)
  | ⟨2, _⟩ => .signed .i32 (Int.ofNat start)
  | ⟨3, _⟩ => .signed .i32 (Int.ofNat cursor)

private def scannerRuntime (predicate : FunctionId) (accept : Byte → Bool)
    (source : List Byte) (start cursor : Nat) :
    Runtime (Effectful.machine verifiedFrontendCore
      (predicateCalls predicate accept)) 4 :=
  (sourceWorld source, scannerLoopEnvironment source start cursor)

@[simp] theorem predicateCalls_at (world : World) (function : FunctionId)
    (accept : Byte → Bool) (byte : Byte) :
    (predicateCalls function accept).evaluate world function
        [.signed .i32 (Int.ofNat byte.val)] =
      .ok (.boolean (accept byte), world) := by
  simp [predicateCalls, byte.isLt]

private theorem scannerCondition_in_bounds
    (predicate : FunctionId) (accept : Byte → Bool)
    (source : List Byte) (start cursor : Nat)
    (inBounds : cursor < source.length) :
    Term.evaluate (Effectful.machine verifiedFrontendCore
        (predicateCalls predicate accept))
      (scannerRuntime predicate accept source start cursor).world
      (scannerRuntime predicate accept source start cursor).environment
      (scannerLoopCondition predicate) =
      .ok (.boolean (accept (source.get ⟨cursor, inBounds⟩)),
        (scannerRuntime predicate accept source start cursor).world) := by
  have left : Term.evaluate (Effectful.machine verifiedFrontendCore
      (predicateCalls predicate accept))
      (scannerRuntime predicate accept source start cursor).world
      (scannerRuntime predicate accept source start cursor).environment
      (apply (.binary .less Program.i32Type Program.i32Type (.scalar .bool))
        [scannerCursorTerm, scannerBoundTerm]) =
      .ok (.boolean true,
        (scannerRuntime predicate accept source start cursor).world) := by
    change Term.evaluate (Effectful.machine verifiedFrontendCore
      (predicateCalls predicate accept)) (sourceWorld source)
      (scannerLoopEnvironment source start cursor)
      (apply (.binary .less Program.i32Type Program.i32Type (.scalar .bool))
        [scannerCursorTerm, scannerBoundTerm]) =
      .ok (.boolean true, sourceWorld source)
    calc
      _ = Term.evaluate (ReadOnly.machine verifiedFrontendCore)
          (sourceWorld source) (scannerLoopEnvironment source start cursor)
          (apply (.binary .less Program.i32Type Program.i32Type (.scalar .bool))
            [scannerCursorTerm, scannerBoundTerm]) :=
        Effectful.Term.evaluate_eq_readOnly_of_callFree
          (program := verifiedFrontendCore)
          (calls := predicateCalls predicate accept) _ (by native_decide)
      _ = _ := by
        have evaluated := ReadOnly.Term.evaluate_i32_less
          (program := verifiedFrontendCore) (world := sourceWorld source)
          (environment := scannerLoopEnvironment source start cursor)
          (leftType := Program.i32Type) (rightType := Program.i32Type)
          (outputType := .scalar .bool)
          (left := scannerCursorTerm) (right := scannerBoundTerm)
          (leftValue := cursor) (rightValue := source.length) (by rfl) (by rfl)
        have decided : decide (cursor < source.length) = true := by
          simp [inBounds]
        rw [decided] at evaluated
        exact evaluated
  unfold scannerLoopCondition
  apply Term.evaluate_logicalAnd_true left
  have currentByte : Term.evaluate (Effectful.machine verifiedFrontendCore
      (predicateCalls predicate accept))
      (sourceWorld source)
      (scannerRuntime predicate accept source start cursor).environment
      (apply (.index (.slice Program.i32Type) Program.i32Type Program.i32Type)
        [scannerSourceTerm, scannerCursorTerm]) =
      .ok (.signed .i32
        (Int.ofNat (source.get ⟨cursor, inBounds⟩).val), sourceWorld source) := by
    calc
      _ = Term.evaluate (ReadOnly.machine verifiedFrontendCore)
          (sourceWorld source) (scannerLoopEnvironment source start cursor)
          (apply (.index (.slice Program.i32Type) Program.i32Type Program.i32Type)
            [scannerSourceTerm, scannerCursorTerm]) :=
        Effectful.Term.evaluate_eq_readOnly_of_callFree
          (program := verifiedFrontendCore)
          (calls := predicateCalls predicate accept) _ (by native_decide)
      _ = _ := by
        apply ReadOnly.Term.evaluate_i32_index_as
          (cell := 0) (values := sourceIntegers source) (position := cursor)
          (expected := Int.ofNat (source.get ⟨cursor, inBounds⟩).val)
        · change Except.ok (sourceSlice source, sourceWorld source) =
            Except.ok (.slice (.scalar (.signed .i32)) 0 [] 0
              (sourceIntegers source).length, sourceWorld source)
          simp [sourceSlice, sourceIntegers]
        · rfl
        · exact sourceWorld_finds source
        · simp [sourceIntegers]
        · simpa [sourceIntegers] using inBounds
  apply Term.evaluate_apply1 currentByte
  exact predicateCalls_at (sourceWorld source) predicate accept
    (source.get ⟨cursor, inBounds⟩)

private theorem scannerCondition_out_of_bounds
    (predicate : FunctionId) (accept : Byte → Bool)
    (source : List Byte) (start cursor : Nat)
    (outOfBounds : ¬ cursor < source.length) :
    Term.evaluate (Effectful.machine verifiedFrontendCore
        (predicateCalls predicate accept))
      (scannerRuntime predicate accept source start cursor).world
      (scannerRuntime predicate accept source start cursor).environment
      (scannerLoopCondition predicate) =
      .ok (.boolean false,
        (scannerRuntime predicate accept source start cursor).world) := by
  change Term.evaluate (Effectful.machine verifiedFrontendCore
    (predicateCalls predicate accept)) (sourceWorld source)
    (scannerLoopEnvironment source start cursor)
    (scannerLoopCondition predicate) = .ok (.boolean false, sourceWorld source)
  unfold scannerLoopCondition
  apply Term.evaluate_logicalAnd_false
  calc
    _ = Term.evaluate (ReadOnly.machine verifiedFrontendCore)
        (sourceWorld source) (scannerLoopEnvironment source start cursor)
        (apply (.binary .less Program.i32Type Program.i32Type (.scalar .bool))
          [scannerCursorTerm, scannerBoundTerm]) :=
      Effectful.Term.evaluate_eq_readOnly_of_callFree
        (program := verifiedFrontendCore)
        (calls := predicateCalls predicate accept) _ (by native_decide)
    _ = _ := by
      have evaluated := ReadOnly.Term.evaluate_i32_less
        (program := verifiedFrontendCore) (world := sourceWorld source)
        (environment := scannerLoopEnvironment source start cursor)
        (leftType := Program.i32Type) (rightType := Program.i32Type)
        (outputType := .scalar .bool)
        (left := scannerCursorTerm) (right := scannerBoundTerm)
        (leftValue := cursor) (rightValue := source.length) (by rfl) (by rfl)
      have decided : decide (cursor < source.length) = false := by
        simp [outOfBounds]
      rw [decided] at evaluated
      exact evaluated

private theorem scannerBody_evaluates
    (predicate : FunctionId) (accept : Byte → Bool)
    (source : List Byte) (start cursor : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (inBounds : cursor < source.length) :
    Command.Evaluates
      (Effectful.machine verifiedFrontendCore (predicateCalls predicate accept))
      (Stateful.machineWith verifiedFrontendCore
        (Effectful.evaluateOperation verifiedFrontendCore
          (predicateCalls predicate accept)))
      (scannerRuntime predicate accept source start cursor).world
      (scannerRuntime predicate accept source start cursor).environment
      scannerLoopBody .next
      (scannerRuntime predicate accept source start (cursor + 1)).world
      (scannerRuntime predicate accept source start (cursor + 1)).environment := by
  have nextEnvironment :
      (scannerRuntime predicate accept source start (cursor + 1)).environment =
      Env.set (scannerRuntime predicate accept source start cursor).environment
        ⟨3, by omega⟩ (.signed .i32 (Int.ofNat (cursor + 1))) := by
    funext index
    have cases : index.val = 0 ∨ index.val = 1 ∨ index.val = 2 ∨
        index.val = 3 := by omega
    rcases cases with zero | one | two | three
    · have same : index = ⟨0, by omega⟩ := Fin.ext zero
      rw [same]
      simp [scannerRuntime, scannerLoopEnvironment, Runtime.environment,
        Env.set]
    · have same : index = ⟨1, by omega⟩ := Fin.ext one
      rw [same]
      simp [scannerRuntime, scannerLoopEnvironment, Runtime.environment,
        Env.set]
    · have same : index = ⟨2, by omega⟩ := Fin.ext two
      rw [same]
      simp [scannerRuntime, scannerLoopEnvironment, Runtime.environment,
        Env.set]
    · have same : index = ⟨3, by omega⟩ := Fin.ext three
      rw [same]
      simp [scannerRuntime, scannerLoopEnvironment, Runtime.environment,
        Env.set]
  rw [nextEnvironment]
  have updateResult : evalAssignValue verifiedFrontendCore.target .add
      (some (.signed .i32 (Int.ofNat cursor))) (.signed .i32 1) =
      .ok (.signed .i32 (Int.ofNat (cursor + 1))) := by
    simp only [evalAssignValue, assignOpBinary?, evalBinaryValue,
      beq_self_eq_true, if_true, evalSignedBinary]
    have addition : Int.ofNat cursor + 1 = Int.ofNat (cursor + 1) := by simp
    rw [addition]
    rw [Lanius.Semantics.wrapSigned_i32_ofNat _ _
      (Nat.le_trans (Nat.succ_le_of_lt inBounds) sourceBound)]
  apply Command.Evaluates.sequenceNext
  · exact Command.Evaluates.updateLocal (by rfl) (by
      simpa [Stateful.machineWith, scannerRuntime, scannerLoopEnvironment,
        Runtime.environment, Ref.evaluate] using updateResult)
  · exact .skip

private def scannerAccepts (source : List Byte) (accept : Byte → Bool)
    (cursor : Nat) : Bool :=
  (source[cursor]?.map accept).getD false

private theorem scannerRecurrence (source : List Byte)
    (accept : Byte → Bool) :
    CursorScan.Recurrence source.length (scannerAccepts source accept)
      (Program.scanAcceptedFrom accept source) := by
  constructor
  · exact Program.scanAcceptedFrom_out_of_bounds accept source
  · intro cursor inBounds rejected
    apply Program.scanAcceptedFrom_rejected accept source cursor inBounds
    simpa [scannerAccepts, List.getElem?_eq_getElem inBounds] using rejected
  · intro cursor inBounds accepted
    apply Program.scanAcceptedFrom_accepted accept source cursor inBounds
    simpa [scannerAccepts, List.getElem?_eq_getElem inBounds] using accepted

private theorem scannerSpec (predicate : FunctionId) (accept : Byte → Bool)
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647) :
    CursorScan.Spec
      (Effectful.machine verifiedFrontendCore (predicateCalls predicate accept))
      (Stateful.machineWith verifiedFrontendCore
        (Effectful.evaluateOperation verifiedFrontendCore
          (predicateCalls predicate accept)))
      (scannerLoopCondition predicate) scannerLoopBody
      (scannerRuntime predicate accept source start) source.length
      (scannerAccepts source accept) := {
  conditionInBounds := fun cursor inBounds => by
    simpa [scannerAccepts, List.getElem?_eq_getElem inBounds] using
      scannerCondition_in_bounds predicate accept source start cursor inBounds
  conditionOutOfBounds := scannerCondition_out_of_bounds predicate accept source start
  body := fun cursor inBounds _ => scannerBody_evaluates predicate accept source
    start cursor sourceBound inBounds }

private theorem scannerCommand_evaluates
    (predicate : FunctionId) (accept : Byte → Bool)
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    ∃ afterWorld afterEnvironment,
      Command.Evaluates
        (Effectful.machine verifiedFrontendCore
          (predicateCalls predicate accept))
        (Stateful.machineWith verifiedFrontendCore
          (Effectful.evaluateOperation verifiedFrontendCore
            (predicateCalls predicate accept)))
        (sourceWorld source)
        (scannerParameterEnvironment source start)
        (scannerCommand predicate)
        (.returned (some (.signed .i32
          (Int.ofNat (Program.scanAcceptedFrom accept source (start + 1))))))
        afterWorld afterEnvironment := by
  let initial := start + 1
  have initialBound : initial ≤ 2147483647 :=
    Nat.le_trans (Nat.succ_le_of_lt startInBounds) sourceBound
  have initializerResult : Term.evaluate
      (Effectful.machine verifiedFrontendCore (predicateCalls predicate accept))
      (sourceWorld source)
      (scannerParameterEnvironment source start)
      (apply (.binary .add Program.i32Type Program.i32Type Program.i32Type)
        [reference ⟨2, by omega⟩, literal (.signed .i32 1)]) =
      .ok (.signed .i32 (Int.ofNat initial), sourceWorld source) := by
    calc
      _ = Term.evaluate (ReadOnly.machine verifiedFrontendCore)
          (sourceWorld source) (scannerParameterEnvironment source start)
          (apply (.binary .add Program.i32Type Program.i32Type Program.i32Type)
            [reference ⟨2, by omega⟩, literal (.signed .i32 1)]) :=
        Effectful.Term.evaluate_eq_readOnly_of_callFree
          (program := verifiedFrontendCore)
          (calls := predicateCalls predicate accept) _ (by rfl)
      _ = _ := by
        have evaluated := ReadOnly.Term.evaluate_i32_add
          (program := verifiedFrontendCore) (world := sourceWorld source)
          (environment := scannerParameterEnvironment source start)
          (leftType := Program.i32Type) (rightType := Program.i32Type)
          (outputType := Program.i32Type)
          (left := reference ⟨2, by omega⟩)
          (right := literal (.signed .i32 1))
          (leftValue := start) (rightValue := 1) (by rfl) (by rfl)
          initialBound
        have addition : Int.ofNat (start + 1) = Int.ofNat initial := by
          simp [initial]
        rw [addition] at evaluated
        exact evaluated
  have pushed : (scannerParameterEnvironment source start).push
      (.signed .i32 (Int.ofNat initial)) =
      scannerLoopEnvironment source start initial := by
    funext index
    have cases : index.val = 0 ∨ index.val = 1 ∨ index.val = 2 ∨
        index.val = 3 := by omega
    rcases cases with zero | one | two | three
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
  let execution := CursorScan.run
    (scannerSpec predicate accept source start sourceBound)
    (scannerRecurrence source accept) initial
  have loopResult : Command.Evaluates
      (Effectful.machine verifiedFrontendCore (predicateCalls predicate accept))
      (Stateful.machineWith verifiedFrontendCore
        (Effectful.evaluateOperation verifiedFrontendCore
          (predicateCalls predicate accept)))
      (scannerRuntime predicate accept source start initial).world
      (scannerRuntime predicate accept source start initial).environment
      (.whileLoop (scannerLoopCondition predicate) scannerLoopBody) .next
      execution.after.world execution.after.environment := by
    simpa [execution.result.completionEq] using execution.trace.evaluates
  have afterEq : execution.after = scannerRuntime predicate accept source start
      (Program.scanAcceptedFrom accept source initial) := by
    simp [execution.result.afterEq, execution.result.finalEq]
  rw [afterEq] at loopResult
  let finish := Program.scanAcceptedFrom accept source initial
  have returnResult : Term.evaluate
      (Effectful.machine verifiedFrontendCore (predicateCalls predicate accept))
      (scannerRuntime predicate accept source start finish).world
      (scannerRuntime predicate accept source start finish).environment
      scannerCursorTerm =
      .ok (.signed .i32 (Int.ofNat finish),
        (scannerRuntime predicate accept source start finish).world) := by rfl
  have bodyResult := Command.Evaluates.sequenceNext loopResult
    (Command.Evaluates.sequenceStop (secondCommand := .skip)
      (Command.Evaluates.returnSome returnResult) (by simp))
  have whole := Command.Evaluates.letValue
    (type := Program.i32Type) initializerResult (by
      rw [pushed]
      simpa [scannerRuntime, Runtime.world, Runtime.environment] using bodyResult)
  exact ⟨sourceWorld source,
    Env.pop (scannerLoopEnvironment source start finish),
    by simpa [scannerCommand, initial, finish] using whole⟩

private theorem scannerCalls_success
    (evaluated : (scannerCalls source expectedFunction requiresOpening
      resultFor).evaluate world function arguments = .ok (result, afterWorld)) :
    ∃ start : Nat,
      world.i32Slice? 0 = some (sourceIntegers source) ∧
      function = expectedFunction ∧ arguments = scannerArguments source start ∧
      source.length ≤ 2147483647 ∧ start < source.length ∧
      start ≤ 2147483647 ∧ (requiresOpening → start + 1 < source.length) ∧
      result = resultFor start ∧ afterWorld = world := by
  simp only [scannerCalls] at evaluated
  split at evaluated
  next sourceLength declaredLength start =>
    split at evaluated
    next valid =>
      split at evaluated
      next functionEq =>
        split at evaluated
        next opening =>
          obtain ⟨rfl, rfl⟩ := evaluated
          refine ⟨start, valid.2.2.2.2.2, functionEq, ?_,
            valid.2.2.1, valid.2.2.2.1, valid.2.2.2.2.1,
            opening, rfl, rfl⟩
          simp [scannerArguments, sourceSlice, valid.1, valid.2.1]
        next => contradiction
      next => contradiction
    next => contradiction
  next => contradiction

theorem representationOnlySource
    (represented : Representation layout localCell world environment state)
    (sourceFound : world.i32Slice? 0 = some (sourceIntegers source)) :
    Representation layout localCell (sourceWorld source) environment state := {
  worldOwned := by
    intro cell values found
    have cellEq : cell = 0 := by
      by_cases same : cell = 0
      · exact same
      · simp [sourceWorld, World.singleton, same] at found
    subst cell
    have valuesEq : values = sourceIntegers source := by
      simpa [sourceWorld, World.singleton] using found.symm
    subst values
    exact represented.worldOwned 0 (sourceIntegers source) sourceFound
  localOwned := represented.localOwned
  localCellsInjective := represented.localCellsInjective
  worldLocalsDisjoint := by
    intro cell worldMember localMember
    obtain ⟨values, found⟩ := worldMember
    have cellEq : cell = 0 := by
      by_cases same : cell = 0
      · exact same
      · simp [sourceWorld, World.singleton, same] at found
    subst cell
    exact represented.worldLocalsDisjoint 0
      ⟨sourceIntegers source, sourceFound⟩ localMember }

private theorem basicScannerFramePreservingSoundness
    (source : List Byte) (function : Function) (predicate : FunctionId)
    (accept : Byte → Bool) (resultFor : Nat → Nat)
    (predicateSound : FreshSimulation.FramePreservingCallSoundness
      verifiedFrontendCore (predicateCalls predicate accept))
    (commandExact : Lanius.FunctionalView.Core.Stateful.toCoreStmt
      actionAdapter identityLayout 3 (scannerCommand predicate) =
        functionBody function)
    (resultEq : ∀ start, Program.scanAcceptedFrom accept source (start + 1) =
      resultFor start)
    (found : verifiedFrontendLexerCore.function? function.id = some function)
    (parameters : function.parameters =
      [(0, .slice Program.i32Type), (1, Program.i32Type),
        (2, Program.i32Type)])
    (hasBody : function.body = some (functionBody function)) :
    FreshSimulation.FramePreservingCallSoundness verifiedFrontendCore
      (scannerCalls source function.id false
        (fun start => .signed .i32 (Int.ofNat (resultFor start)))) := by
  constructor
  intro arity layout localCell beforeWorld afterWorld callerEnvironment before
    afterArguments functionId sourceArguments values result argumentWrites
    afterArgumentsWellFormed represented argumentsExecution argumentsEffect
    evaluated
  obtain ⟨start, sourceFound, rfl, rfl, sourceBound, startInBounds,
      startBound, _, rfl, worldEq⟩ := scannerCalls_success evaluated
  subst afterWorld
  let calleeEnvironment := scannerParameterEnvironment source start
  let bindings := parameterBindings calleeEnvironment
  let callee := enterCall afterArguments bindings
  have calleeRepresentedFull : Representation identityLayout
      (callLocalCells afterArguments) beforeWorld calleeEnvironment callee := by
    simpa [callee, bindings] using
      represented.enterCallParameters afterArgumentsWellFormed
        (environment := calleeEnvironment)
  have calleeRepresented : Representation identityLayout
      (callLocalCells afterArguments) (sourceWorld source)
      calleeEnvironment callee :=
    representationOnlySource calleeRepresentedFull sourceFound
  have calleeWellFormed : StateWellFormed callee := by
    simpa [callee, bindings] using
      enterCall_preserves_wellFormed afterArgumentsWellFormed
  obtain ⟨afterFunctionalWorld, afterFunctionalEnvironment,
      functionalEvaluation⟩ := scannerCommand_evaluates predicate accept source
        start sourceBound startInBounds
  let operations := FreshSimulation.operationSoundness verifiedFrontendCore
    (predicateCalls predicate accept) predicateSound
  have simulation := FreshSimulation.commandSoundness operations
    functionalEvaluation (by rfl) calleeRepresented
    (LayoutBelow.identity (arity := 3)) calleeWellFormed
    (frontier := afterArguments.nextCell)
    (by intro index; simp [callLocalCells])
    (by simpa [callee] using (enterCall_effect afterArguments bindings).nextCell)
  obtain ⟨completed, bodyExecution, completedWellFormed,
      completedRepresented, bodyEffect⟩ := simulation
  rw [commandExact] at bodyExecution
  rw [resultEq start] at bodyExecution
  change Executes verifiedFrontendCore callee (functionBody function)
    (.returned (some (.signed .i32 (Int.ofNat (resultFor start)))))
    completed at bodyExecution
  have callExecution : Evaluates verifiedFrontendCore before
      (.call function.id (toCoreExprs layout sourceArguments))
      (.signed .i32 (Int.ofNat (resultFor start)))
      (restoreLocals afterArguments completed) := by
    apply evaluatesCallReturned (bindings := bindings)
      (body := functionBody function) argumentsExecution
    · exact verifiedFrontendCore_extends_verifiedFrontendLexerCore.function found
    · rw [parameters]
      simp [bindings, calleeEnvironment, parameterBindings,
        scannerParameterEnvironment, scannerArguments, sourceSlice,
        List.finRange]
      rfl
    · exact hasBody
    · simpa [callee, bindings] using bodyExecution
  obtain ⟨afterWellFormed, afterRepresented, callEffect⟩ :=
    represented.restoreFreshCall afterArgumentsWellFormed completedWellFormed
      (bindings := bindings) bodyEffect (by intro cell written; exact written)
  exact ⟨restoreLocals afterArguments completed, callExecution,
    afterWellFormed, afterRepresented,
    argumentsEffect.trans_same (callEffect.weaken CellSet.empty_subset)⟩

theorem identifierFramePreservingCallSoundness (source : List Byte) :
    FreshSimulation.FramePreservingCallSoundness verifiedFrontendCore
      (identifierCalls source) := by
  exact basicScannerFramePreservingSoundness source
    Scanners.scanIdentifierEndFunction isIdentifierContinueFunction.id
    isIdentifierContinue (fun start => scanIdentifierEnd source start)
    identifierPredicateFramePreservingSoundness
    identifierCommand_exact (by intro start; rfl)
    Scanners.verifiedFrontendLexerCore_finds_scanIdentifierEnd
    (by native_decide) Scanners.scanIdentifierEndFunction_has_body

theorem whitespaceFramePreservingCallSoundness (source : List Byte) :
    FreshSimulation.FramePreservingCallSoundness verifiedFrontendCore
      (whitespaceCalls source) := by
  exact basicScannerFramePreservingSoundness source
    Scanners.scanWhitespaceEndFunction isWhitespaceFunction.id isWhitespace
    (fun start => scanWhitespaceEnd source start)
    whitespacePredicateFramePreservingSoundness whitespaceCommand_exact
    (by intro start; rfl)
    Scanners.verifiedFrontendLexerCore_finds_scanWhitespaceEnd
    (by native_decide) Scanners.scanWhitespaceEndFunction_has_body

private theorem effectfulScannerFramePreservingSoundness
    (source : List Byte) (function : Function) (command : C 3)
    (helpers : CallModel)
    (helperSound : FreshSimulation.FramePreservingCallSoundness
      verifiedFrontendLexerCore helpers)
    (resultFor : Nat → Value)
    (evaluates : ∀ start, source.length ≤ 2147483647 →
      start + 1 < source.length →
      ∃ afterWorld afterEnvironment,
        Command.Evaluates (Effectful.machine verifiedFrontendLexerCore helpers)
          (Stateful.machineWith verifiedFrontendLexerCore
            (Effectful.evaluateOperation verifiedFrontendLexerCore helpers))
          (sourceWorld source) (scannerParameterEnvironment source start)
          command (.returned (some (resultFor start)))
          afterWorld afterEnvironment)
    (commandExact : Lanius.FunctionalView.Core.Stateful.toCoreStmt
      actionAdapter identityLayout 3 command = functionBody function)
    (actionFree : FreshSimulation.actionFree command = true)
    (found : verifiedFrontendLexerCore.function? function.id = some function)
    (parameters : function.parameters =
      [(0, .slice Program.i32Type), (1, Program.i32Type),
        (2, Program.i32Type)])
    (hasBody : function.body = some (functionBody function)) :
    FreshSimulation.FramePreservingCallSoundness verifiedFrontendCore
      (scannerCalls source function.id true resultFor) := by
  constructor
  intro arity layout localCell beforeWorld afterWorld callerEnvironment before
    afterArguments functionId sourceArguments values result argumentWrites
    afterArgumentsWellFormed represented argumentsExecution argumentsEffect
    evaluated
  obtain ⟨start, sourceFound, rfl, rfl, sourceBound, startInBounds,
      startBound, openingInBounds, rfl, worldEq⟩ :=
    scannerCalls_success evaluated
  subst afterWorld
  let calleeEnvironment := scannerParameterEnvironment source start
  let bindings := parameterBindings calleeEnvironment
  let callee := enterCall afterArguments bindings
  have calleeRepresentedFull : Representation identityLayout
      (callLocalCells afterArguments) beforeWorld calleeEnvironment callee := by
    simpa [callee, bindings] using
      represented.enterCallParameters afterArgumentsWellFormed
        (environment := calleeEnvironment)
  have calleeRepresented : Representation identityLayout
      (callLocalCells afterArguments) (sourceWorld source)
      calleeEnvironment callee :=
    representationOnlySource calleeRepresentedFull sourceFound
  have calleeWellFormed : StateWellFormed callee := by
    simpa [callee, bindings] using
      enterCall_preserves_wellFormed afterArgumentsWellFormed
  obtain ⟨afterFunctionalWorld, afterFunctionalEnvironment,
      functionalEvaluation⟩ := evaluates start sourceBound (openingInBounds rfl)
  let operations := FreshSimulation.operationSoundness verifiedFrontendLexerCore
    helpers helperSound
  have simulation := FreshSimulation.commandSoundness operations
    functionalEvaluation actionFree calleeRepresented
    (LayoutBelow.identity (arity := 3)) calleeWellFormed
    (frontier := afterArguments.nextCell)
    (by intro index; simp [callLocalCells])
    (by simpa [callee] using (enterCall_effect afterArguments bindings).nextCell)
  obtain ⟨completed, bodyExecution, completedWellFormed,
      completedRepresented, bodyEffect⟩ := simulation
  rw [commandExact] at bodyExecution
  change Executes verifiedFrontendLexerCore callee (functionBody function)
    (.returned (some (resultFor start))) completed at bodyExecution
  have bodyExecutionMerged : Executes verifiedFrontendCore callee
      (functionBody function) (.returned (some (resultFor start))) completed :=
    verifiedFrontendCore_extends_verifiedFrontendLexerCore.executes bodyExecution
  have callExecution : Evaluates verifiedFrontendCore before
      (.call function.id (toCoreExprs layout sourceArguments))
      (resultFor start) (restoreLocals afterArguments completed) := by
    apply evaluatesCallReturned (bindings := bindings)
      (body := functionBody function) argumentsExecution
    · exact verifiedFrontendCore_extends_verifiedFrontendLexerCore.function found
    · rw [parameters]
      simp [bindings, calleeEnvironment, parameterBindings,
        scannerParameterEnvironment, scannerArguments, sourceSlice,
        List.finRange]
      rfl
    · exact hasBody
    · simpa [callee, bindings] using bodyExecutionMerged
  obtain ⟨afterWellFormed, afterRepresented, callEffect⟩ :=
    represented.restoreFreshCall afterArgumentsWellFormed completedWellFormed
      (bindings := bindings) bodyEffect (by intro cell written; exact written)
  exact ⟨restoreLocals afterArguments completed, callExecution,
    afterWellFormed, afterRepresented,
    argumentsEffect.trans_same (callEffect.weaken CellSet.empty_subset)⟩

private theorem blockCommentCommand_evaluates
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (openingInBounds : start + 1 < source.length) :
    ∃ afterWorld afterEnvironment,
      Command.Evaluates
        (Effectful.machine verifiedFrontendLexerCore ScanEndCalls.calls)
        (Stateful.machineWith verifiedFrontendLexerCore
          (Effectful.evaluateOperation verifiedFrontendLexerCore ScanEndCalls.calls))
        (sourceWorld source) (scannerParameterEnvironment source start)
        BlockComment.view.command
        (.returned (some (encodedScanEnd
          (scanBlockCommentEnd source start))))
        afterWorld afterEnvironment := by
  obtain ⟨afterWorld, afterEnvironment, evaluated⟩ :=
    BlockComment.view_evaluates source start sourceBound openingInBounds
  refine ⟨afterWorld, afterEnvironment, ?_⟩
  change Command.Evaluates
    (Effectful.machine verifiedFrontendLexerCore ScanEndCalls.calls)
    (Stateful.machineWith verifiedFrontendLexerCore
      (Effectful.evaluateOperation verifiedFrontendLexerCore ScanEndCalls.calls))
    (sourceWorld source) (scannerParameterEnvironment source start)
    BlockComment.view.command
    (.returned (some
      (Program.scanEndValue (scanBlockCommentEnd source start))))
    afterWorld afterEnvironment at evaluated
  have resultEq : Program.scanEndValue (scanBlockCommentEnd source start) =
      encodedScanEnd (scanBlockCommentEnd source start) := by
    cases scanBlockCommentEnd source start <;> rfl
  rw [resultEq] at evaluated
  exact evaluated

theorem blockCommentFramePreservingCallSoundness (source : List Byte) :
    FreshSimulation.FramePreservingCallSoundness verifiedFrontendCore
      (blockCommentCalls source) := by
  exact effectfulScannerFramePreservingSoundness source
    Scanners.scanBlockCommentEndFunction BlockComment.view.command
    ScanEndCalls.calls scanEndConstructorLexerFramePreservingCallSoundness
    (fun start => encodedScanEnd (scanBlockCommentEnd source start))
    (blockCommentCommand_evaluates source)
    BlockComment.command_toCore_exactly
    (by native_decide)
    Scanners.verifiedFrontendLexerCore_finds_scanBlockCommentEnd
    (by native_decide) Scanners.scanBlockCommentEndFunction_has_body

private def quotedEnvironment (source : List Byte) (start : Nat)
    (delimiter : Byte) : Env 4
  | ⟨0, _⟩ => sourceSlice source
  | ⟨1, _⟩ => .signed .i32 (Int.ofNat source.length)
  | ⟨2, _⟩ => .signed .i32 (Int.ofNat start)
  | ⟨3, _⟩ => .signed .i32 (Int.ofNat delimiter.val)

private def quotedArguments (source : List Byte) (start : Nat)
    (delimiter : Byte) : List Value :=
  [sourceSlice source, .signed .i32 (Int.ofNat source.length),
    .signed .i32 (Int.ofNat start), .signed .i32 (Int.ofNat delimiter.val)]

private def quotedCalls (source : List Byte) (delimiter : Byte) : CallModel where
  evaluate := fun world function arguments =>
    match arguments with
    | [.slice (.scalar (.signed .i32)) 0 [] 0 sourceLength,
        .signed .i32 (.ofNat declaredLength), .signed .i32 (.ofNat start),
        .signed .i32 (.ofNat delimiterValue)] =>
      if sourceLength = source.length ∧ declaredLength = source.length ∧
          delimiterValue = delimiter.val ∧ source.length ≤ 2147483647 ∧
          start < source.length ∧ start ≤ 2147483647 ∧
          world.i32Slice? 0 = some (sourceIntegers source) then
        if function = Scanners.scanQuotedEndFunction.id then
          .ok (encodedScanEnd (scanQuotedEnd source start delimiter), world)
        else .error .invalidPointer
      else .error .typeMismatch
    | _ => .error .typeMismatch

private theorem quotedAnyCalls_success
    (evaluated : (quotedAnyCalls source).evaluate world function arguments =
      .ok (result, afterWorld)) :
    ∃ (start : Nat) (delimiter : Byte),
      world.i32Slice? 0 = some (sourceIntegers source) ∧
      function = Scanners.scanQuotedEndFunction.id ∧
      arguments = quotedArguments source start delimiter ∧
      source.length ≤ 2147483647 ∧ start < source.length ∧
      start ≤ 2147483647 ∧
      result = encodedScanEnd (scanQuotedEnd source start delimiter) ∧
      afterWorld = world := by
  simp only [quotedAnyCalls] at evaluated
  split at evaluated
  next sourceLength declaredLength start delimiterValue =>
    split at evaluated
    next delimiterBound =>
      split at evaluated
      next valid =>
        split at evaluated
        next functionEq =>
          obtain ⟨rfl, rfl⟩ := evaluated
          let delimiter : Byte := ⟨delimiterValue, delimiterBound⟩
          refine ⟨start, delimiter, valid.2.2.2.2.2,
            functionEq, ?_, valid.2.2.1, valid.2.2.2.1,
            valid.2.2.2.2.1, rfl, rfl⟩
          simp [quotedArguments, sourceSlice, valid.1, valid.2.1, delimiter]
        next => contradiction
      next => contradiction
    next => contradiction
  next => contradiction

private theorem quotedCalls_success
    (evaluated : (quotedCalls source delimiter).evaluate world function arguments =
      .ok (result, afterWorld)) :
    ∃ start : Nat,
      world.i32Slice? 0 = some (sourceIntegers source) ∧
      function = Scanners.scanQuotedEndFunction.id ∧
      arguments = quotedArguments source start delimiter ∧
      source.length ≤ 2147483647 ∧ start < source.length ∧
      start ≤ 2147483647 ∧
      result = encodedScanEnd (scanQuotedEnd source start delimiter) ∧
      afterWorld = world := by
  simp only [quotedCalls] at evaluated
  split at evaluated
  next sourceLength declaredLength start delimiterValue =>
    split at evaluated
    next valid =>
      split at evaluated
      next functionEq =>
        obtain ⟨rfl, rfl⟩ := evaluated
        refine ⟨start, valid.2.2.2.2.2.2, functionEq, ?_, valid.2.2.2.1,
          valid.2.2.2.2.1, valid.2.2.2.2.2.1, rfl, rfl⟩
        simp [quotedArguments, sourceSlice, valid.1, valid.2.1, valid.2.2.1]
      next => contradiction
    next => contradiction
  next => contradiction

@[simp] theorem quotedCalls_at (source : List Byte) (start : Nat)
    (delimiter : Byte) (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) (startBound : start ≤ 2147483647) :
    (quotedCalls source delimiter).evaluate (sourceWorld source)
      Scanners.scanQuotedEndFunction.id (quotedArguments source start delimiter) =
      .ok (encodedScanEnd (scanQuotedEnd source start delimiter),
        sourceWorld source) := by
  unfold quotedCalls
  change (if source.length = source.length ∧ source.length = source.length ∧
      delimiter.val = delimiter.val ∧ source.length ≤ 2147483647 ∧
      start < source.length ∧ start ≤ 2147483647 ∧
      (sourceWorld source).i32Slice? 0 = some (sourceIntegers source) then
        Except.ok (encodedScanEnd (scanQuotedEnd source start delimiter),
          sourceWorld source)
      else Except.error Trap.typeMismatch) = _
  rw [if_pos]
  simp [sourceBound, startInBounds, startBound]

private theorem quotedCalls_at_world (source : List Byte) (world : World)
    (start : Nat) (delimiter : Byte)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) (startBound : start ≤ 2147483647)
    (sourceFound : world.i32Slice? 0 = some (sourceIntegers source)) :
    (quotedCalls source delimiter).evaluate world
      Scanners.scanQuotedEndFunction.id (quotedArguments source start delimiter) =
      .ok (encodedScanEnd (scanQuotedEnd source start delimiter), world) := by
  unfold quotedCalls
  change (if source.length = source.length ∧ source.length = source.length ∧
      delimiter.val = delimiter.val ∧ source.length ≤ 2147483647 ∧
      start < source.length ∧ start ≤ 2147483647 ∧
      world.i32Slice? 0 = some (sourceIntegers source) then
        Except.ok (encodedScanEnd (scanQuotedEnd source start delimiter), world)
      else Except.error Trap.typeMismatch) = _
  rw [if_pos]
  simp [sourceBound, startInBounds, startBound, sourceFound]

private theorem quotedCommand_evaluates
    (source : List Byte) (start : Nat) (delimiter : Byte)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    ∃ afterWorld afterEnvironment,
      Command.Evaluates
        (Effectful.machine verifiedFrontendLexerCore ScanEndCalls.calls)
        (Stateful.machineWith verifiedFrontendLexerCore
          (Effectful.evaluateOperation verifiedFrontendLexerCore ScanEndCalls.calls))
        (sourceWorld source) (quotedEnvironment source start delimiter)
        Quoted.quotedView.command
        (.returned (some (encodedScanEnd
          (scanQuotedEnd source start delimiter))))
        afterWorld afterEnvironment := by
  obtain ⟨afterWorld, afterEnvironment, evaluated⟩ :=
    Quoted.command_evaluates source start delimiter sourceBound startInBounds
  refine ⟨afterWorld, afterEnvironment, ?_⟩
  change Command.Evaluates
    (Effectful.machine verifiedFrontendLexerCore ScanEndCalls.calls)
    (Stateful.machineWith verifiedFrontendLexerCore
      (Effectful.evaluateOperation verifiedFrontendLexerCore ScanEndCalls.calls))
    (sourceWorld source) (quotedEnvironment source start delimiter)
    Quoted.quotedView.command
    (.returned (some (Program.scanEndValue
      (scanQuotedEnd source start delimiter)))) afterWorld afterEnvironment
    at evaluated
  have resultEq : Program.scanEndValue (scanQuotedEnd source start delimiter) =
      encodedScanEnd (scanQuotedEnd source start delimiter) := by
    cases scanQuotedEnd source start delimiter <;> rfl
  rw [resultEq] at evaluated
  exact evaluated

private theorem quotedFramePreservingCallSoundness
    (source : List Byte) (delimiter : Byte) :
    FreshSimulation.FramePreservingCallSoundness verifiedFrontendCore
      (quotedCalls source delimiter) := by
  constructor
  intro arity layout localCell beforeWorld afterWorld callerEnvironment before
    afterArguments function sourceArguments values result argumentWrites
    afterArgumentsWellFormed represented argumentsExecution argumentsEffect
    evaluated
  obtain ⟨start, sourceFound, rfl, rfl, sourceBound, startInBounds,
      startBound, rfl, worldEq⟩ := quotedCalls_success evaluated
  subst afterWorld
  let calleeEnvironment := quotedEnvironment source start delimiter
  let bindings := parameterBindings calleeEnvironment
  let callee := enterCall afterArguments bindings
  have calleeRepresentedFull : Representation identityLayout
      (callLocalCells afterArguments) beforeWorld calleeEnvironment callee := by
    simpa [callee, bindings] using
      represented.enterCallParameters afterArgumentsWellFormed
        (environment := calleeEnvironment)
  have calleeRepresented : Representation identityLayout
      (callLocalCells afterArguments) (sourceWorld source)
      calleeEnvironment callee :=
    representationOnlySource calleeRepresentedFull sourceFound
  have calleeWellFormed : StateWellFormed callee := by
    simpa [callee, bindings] using
      enterCall_preserves_wellFormed afterArgumentsWellFormed
  obtain ⟨afterFunctionalWorld, afterFunctionalEnvironment,
      functionalEvaluation⟩ := quotedCommand_evaluates source start delimiter
        sourceBound startInBounds
  let operations := FreshSimulation.operationSoundness verifiedFrontendLexerCore
    ScanEndCalls.calls scanEndConstructorLexerFramePreservingCallSoundness
  have simulation := FreshSimulation.commandSoundness operations
    functionalEvaluation (by native_decide) calleeRepresented
    (LayoutBelow.identity (arity := 4)) calleeWellFormed
    (frontier := afterArguments.nextCell)
    (by intro index; simp [callLocalCells])
    (by simpa [callee] using (enterCall_effect afterArguments bindings).nextCell)
  obtain ⟨completed, bodyExecution, completedWellFormed,
      completedRepresented, bodyEffect⟩ := simulation
  rw [Quoted.quotedView.toCoreExactly] at bodyExecution
  change Executes verifiedFrontendLexerCore callee
    Scanners.scanQuotedEndBody
    (.returned (some (encodedScanEnd
      (scanQuotedEnd source start delimiter)))) completed at bodyExecution
  have bodyExecutionMerged :=
    verifiedFrontendCore_extends_verifiedFrontendLexerCore.executes bodyExecution
  have callExecution : Evaluates verifiedFrontendCore before
      (.call Scanners.scanQuotedEndFunction.id
        (toCoreExprs layout sourceArguments))
      (encodedScanEnd (scanQuotedEnd source start delimiter))
      (restoreLocals afterArguments completed) := by
    apply evaluatesCallReturned (bindings := bindings)
      (body := Scanners.scanQuotedEndBody) argumentsExecution
    · exact verifiedFrontendCore_extends_verifiedFrontendLexerCore.function
        Scanners.verifiedFrontendLexerCore_finds_scanQuotedEnd
    · rfl
    · exact Scanners.scanQuotedEndFunction_has_body
    · simpa [callee, bindings] using bodyExecutionMerged
  obtain ⟨afterWellFormed, afterRepresented, callEffect⟩ :=
    represented.restoreFreshCall afterArgumentsWellFormed completedWellFormed
      (bindings := bindings) bodyEffect (by intro cell written; exact written)
  exact ⟨restoreLocals afterArguments completed, callExecution,
    afterWellFormed, afterRepresented,
    argumentsEffect.trans_same (callEffect.weaken CellSet.empty_subset)⟩

@[simp] theorem quotedAnyCalls_at (source : List Byte) (start : Nat)
    (delimiter : Byte) (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) (startBound : start ≤ 2147483647) :
    (quotedAnyCalls source).evaluate (sourceWorld source)
        Scanners.scanQuotedEndFunction.id
        (quotedArguments source start delimiter) =
      .ok (encodedScanEnd (scanQuotedEnd source start delimiter),
        sourceWorld source) := by
  unfold quotedAnyCalls
  simp only [quotedArguments, sourceSlice]
  split
  next delimiterBound =>
    have delimiterEq : (⟨delimiter.val, delimiterBound⟩ : Byte) = delimiter := by
      apply Fin.ext
      rfl
    simp [sourceBound, startInBounds, startBound, delimiterEq]
  next delimiterUnbounded => exact (delimiterUnbounded delimiter.isLt).elim

@[simp] theorem quotedAnyCalls_at_world (source : List Byte) (world : World)
    (start : Nat) (delimiter : Byte)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) (startBound : start ≤ 2147483647)
    (sourceFound : world.i32Slice? 0 = some (sourceIntegers source)) :
    (quotedAnyCalls source).evaluate world Scanners.scanQuotedEndFunction.id
        (quotedArguments source start delimiter) =
      .ok (encodedScanEnd (scanQuotedEnd source start delimiter), world) := by
  unfold quotedAnyCalls
  simp only [quotedArguments, sourceSlice]
  split
  next delimiterBound =>
    have delimiterEq : (⟨delimiter.val, delimiterBound⟩ : Byte) = delimiter := by
      apply Fin.ext
      rfl
    simp [sourceBound, startInBounds, startBound, sourceFound, delimiterEq]
  next delimiterUnbounded => exact (delimiterUnbounded delimiter.isLt).elim

theorem quotedAnyFramePreservingCallSoundness (source : List Byte) :
    FreshSimulation.FramePreservingCallSoundness verifiedFrontendCore
      (quotedAnyCalls source) := by
  constructor
  intro arity layout localCell beforeWorld afterWorld callerEnvironment before
    afterArguments function sourceArguments values result argumentWrites
    afterArgumentsWellFormed represented argumentsExecution argumentsEffect
    evaluated
  obtain ⟨start, delimiter, sourceFound, rfl, rfl, sourceBound,
      startInBounds, startBound, rfl, worldEq⟩ :=
    quotedAnyCalls_success evaluated
  subst afterWorld
  have fixedEvaluation := quotedCalls_at_world source beforeWorld start delimiter
    sourceBound startInBounds startBound sourceFound
  exact (quotedFramePreservingCallSoundness source delimiter).call
    afterArgumentsWellFormed represented argumentsExecution argumentsEffect
    fixedEvaluation

private def quotedLocalTerms (delimiter : Byte) : List (T 3) :=
  [reference ⟨0, by omega⟩, reference ⟨1, by omega⟩,
    reference ⟨2, by omega⟩,
    literal (.signed .i32 (Int.ofNat delimiter.val))]

private theorem quotedLocalTerms_toCore (delimiter : Byte) :
    toCoreExprs identityLayout (quotedLocalTerms delimiter) =
      [.local 0, .local 1, .local 2,
        .value (.signed .i32 (Int.ofNat delimiter.val))] := by
  rfl

private theorem quotedWrapperFramePreservingCallSoundness
    (source : List Byte) (delimiter : Byte) (function : Function)
    (resultFor : Nat → Value)
    (resultEq : ∀ start, resultFor start =
      encodedScanEnd (scanQuotedEnd source start delimiter))
    (bodyFromCall : ∀ {state after result},
      Evaluates verifiedFrontendCore state
        (.call Scanners.scanQuotedEndFunction.id
          (toCoreExprs identityLayout (quotedLocalTerms delimiter))) result after →
      Executes verifiedFrontendCore state (functionBody function)
        (.returned (some result)) after)
    (found : verifiedFrontendLexerCore.function? function.id = some function)
    (parameters : function.parameters =
      [(0, .slice Program.i32Type), (1, Program.i32Type),
        (2, Program.i32Type)])
    (hasBody : function.body = some (functionBody function)) :
    FreshSimulation.FramePreservingCallSoundness verifiedFrontendCore
      (scannerCalls source function.id false resultFor) := by
  constructor
  intro arity layout localCell beforeWorld afterWorld callerEnvironment before
    afterArguments functionId sourceArguments values result argumentWrites
    afterArgumentsWellFormed represented argumentsExecution argumentsEffect
    evaluated
  obtain ⟨start, sourceFound, rfl, rfl, sourceBound, startInBounds,
      startBound, _, rfl, worldEq⟩ := scannerCalls_success evaluated
  subst afterWorld
  let calleeEnvironment := scannerParameterEnvironment source start
  let bindings := parameterBindings calleeEnvironment
  let callee := enterCall afterArguments bindings
  have calleeRepresentedFull : Representation identityLayout
      (callLocalCells afterArguments) beforeWorld calleeEnvironment callee := by
    simpa [callee, bindings] using
      represented.enterCallParameters afterArgumentsWellFormed
        (environment := calleeEnvironment)
  have calleeRepresented : Representation identityLayout
      (callLocalCells afterArguments) (sourceWorld source)
      calleeEnvironment callee :=
    representationOnlySource calleeRepresentedFull sourceFound
  have calleeWellFormed : StateWellFormed callee := by
    simpa [callee, bindings] using
      enterCall_preserves_wellFormed afterArgumentsWellFormed
  have quotedArgumentsExecution : ArgumentsEvaluateTo verifiedFrontendCore
      callee (toCoreExprs identityLayout (quotedLocalTerms delimiter))
      (quotedArguments source start delimiter) callee := by
    rw [quotedLocalTerms_toCore]
    have local0 : callee.local? 0 = some (sourceSlice source) := by
      simpa [calleeEnvironment, scannerParameterEnvironment, identityLayout] using
        calleeRepresented.environmentMatches ⟨0, by omega⟩
    have local1 : callee.local? 1 =
        some (.signed .i32 (Int.ofNat source.length)) := by
      simpa [calleeEnvironment, scannerParameterEnvironment, identityLayout] using
        calleeRepresented.environmentMatches ⟨1, by omega⟩
    have local2 : callee.local? 2 =
        some (.signed .i32 (Int.ofNat start)) := by
      simpa [calleeEnvironment, scannerParameterEnvironment, identityLayout] using
        calleeRepresented.environmentMatches ⟨2, by omega⟩
    have first : Evaluates verifiedFrontendCore callee (.local 0)
        (sourceSlice source) callee :=
      ⟨1, evalLocal_of_local 1 verifiedFrontendCore callee 0 _ local0⟩
    have second : Evaluates verifiedFrontendCore callee (.local 1)
        (.signed .i32 (Int.ofNat source.length)) callee :=
      ⟨1, evalLocal_of_local 1 verifiedFrontendCore callee 1 _ local1⟩
    have third : Evaluates verifiedFrontendCore callee (.local 2)
        (.signed .i32 (Int.ofNat start)) callee :=
      ⟨1, evalLocal_of_local 1 verifiedFrontendCore callee 2 _ local2⟩
    have fourth : Evaluates verifiedFrontendCore callee
        (.value (.signed .i32 (Int.ofNat delimiter.val)))
        (.signed .i32 (Int.ofNat delimiter.val)) callee := ⟨1, rfl⟩
    exact ArgumentsEvaluateTo.cons first
      (ArgumentsEvaluateTo.cons second
        (ArgumentsEvaluateTo.cons third
          (ArgumentsEvaluateTo.singleton fourth)))
  have quotedModelEvaluation := quotedCalls_at source start delimiter
    sourceBound startInBounds startBound
  obtain ⟨quotedAfter, quotedExecution, quotedAfterWellFormed,
      quotedAfterRepresented, quotedEffect⟩ :=
    (quotedFramePreservingCallSoundness source delimiter).call
      calleeWellFormed calleeRepresented quotedArgumentsExecution
      (ModifiesOnly.refl callee) quotedModelEvaluation
  have bodyExecution : Executes verifiedFrontendCore callee
      (functionBody function) (.returned (some (resultFor start)))
      quotedAfter := by
    rw [resultEq start]
    exact bodyFromCall quotedExecution
  have callExecution : Evaluates verifiedFrontendCore before
      (.call function.id (toCoreExprs layout sourceArguments))
      (resultFor start) (restoreLocals afterArguments quotedAfter) := by
    apply evaluatesCallReturned (bindings := bindings)
      (body := functionBody function) argumentsExecution
    · exact verifiedFrontendCore_extends_verifiedFrontendLexerCore.function found
    · rw [parameters]
      simp [bindings, calleeEnvironment, parameterBindings,
        scannerParameterEnvironment, scannerArguments, sourceSlice,
        List.finRange]
      rfl
    · exact hasBody
    · simpa [callee, bindings] using bodyExecution
  obtain ⟨afterWellFormed, afterRepresented, callEffect⟩ :=
    represented.restoreFreshCall afterArgumentsWellFormed
      quotedAfterWellFormed (bindings := bindings) quotedEffect
      (by intro cell written; contradiction)
  exact ⟨restoreLocals afterArguments quotedAfter, callExecution,
    afterWellFormed, afterRepresented,
    argumentsEffect.trans_same (callEffect.weaken CellSet.empty_subset)⟩

private theorem stringBodyFromQuotedCall
    {state after : State} {result : Value}
    (callExecution : Evaluates verifiedFrontendCore state
      (.call Scanners.scanQuotedEndFunction.id
        (toCoreExprs identityLayout
          (quotedLocalTerms Program.doubleQuoteByte))) result after) :
    Executes verifiedFrontendCore state Scanners.scanStringEndBody
      (.returned (some result)) after := by
  apply removeTrailingSkips_executes_complete
    QuotedWrappers.scanStringEndBody_normalization_supported
  rw [QuotedWrappers.scanStringEndBody_normalizes]
  rw [quotedLocalTerms_toCore] at callExecution
  have functionEq : Scanners.scanQuotedEndFunction.id =
      Program.scanQuotedEndFunction.id := by rfl
  rw [functionEq] at callExecution
  have delimiterEq : Int.ofNat Program.doubleQuoteByte.val = 34 := by
    native_decide
  rw [delimiterEq] at callExecution
  simpa [Program.quotedWrapperBody, Program.i32Literal] using
    executesReturnValue callExecution

private theorem characterBodyFromQuotedCall
    {state after : State} {result : Value}
    (callExecution : Evaluates verifiedFrontendCore state
      (.call Scanners.scanQuotedEndFunction.id
        (toCoreExprs identityLayout
          (quotedLocalTerms Program.singleQuoteByte))) result after) :
    Executes verifiedFrontendCore state Scanners.scanCharacterEndBody
      (.returned (some result)) after := by
  apply removeTrailingSkips_executes_complete
    QuotedWrappers.scanCharacterEndBody_normalization_supported
  rw [QuotedWrappers.scanCharacterEndBody_normalizes]
  rw [quotedLocalTerms_toCore] at callExecution
  have functionEq : Scanners.scanQuotedEndFunction.id =
      Program.scanQuotedEndFunction.id := by rfl
  rw [functionEq] at callExecution
  have delimiterEq : Int.ofNat Program.singleQuoteByte.val = 39 := by
    native_decide
  rw [delimiterEq] at callExecution
  simpa [Program.quotedWrapperBody, Program.i32Literal] using
    executesReturnValue callExecution

theorem stringFramePreservingCallSoundness (source : List Byte) :
    FreshSimulation.FramePreservingCallSoundness verifiedFrontendCore
      (stringCalls source) := by
  exact quotedWrapperFramePreservingCallSoundness source
    Program.doubleQuoteByte Scanners.scanStringEndFunction
    (fun start => encodedScanEnd
      (scanQuotedEnd source start Program.doubleQuoteByte))
    (by intro start; rfl) stringBodyFromQuotedCall
    Scanners.verifiedFrontendLexerCore_finds_scanStringEnd
    (by native_decide) Scanners.scanStringEndFunction_has_body

theorem characterFramePreservingCallSoundness (source : List Byte) :
    FreshSimulation.FramePreservingCallSoundness verifiedFrontendCore
      (characterCalls source) := by
  exact quotedWrapperFramePreservingCallSoundness source
    Program.singleQuoteByte Scanners.scanCharacterEndFunction
    (fun start => encodedScanEnd
      (scanQuotedEnd source start Program.singleQuoteByte))
    (by intro start; rfl) characterBodyFromQuotedCall
    Scanners.verifiedFrontendLexerCore_finds_scanCharacterEnd
    (by native_decide) Scanners.scanCharacterEndFunction_has_body

private def commandCallFree : C arity → Bool
  | .skip | .breakLoop | .continueLoop | .returnValue none => true
  | .sequence first second => commandCallFree first && commandCallFree second
  | .letValue _ initializer body =>
      Effectful.termCallFree initializer && commandCallFree body
  | .setLocal _ value | .updateLocal _ _ value => Effectful.termCallFree value
  | .action _ => false
  | .ifThenElse condition thenBranch elseBranch =>
      Effectful.termCallFree condition && commandCallFree thenBranch &&
        commandCallFree elseBranch
  | .whileLoop condition body =>
      Effectful.termCallFree condition && commandCallFree body
  | .returnValue (some value) => Effectful.termCallFree value

private theorem commandEvaluates_effectful_of_readOnly
    (calls : CallModel) (command : C arity)
    (free : commandCallFree command = true)
    (evaluated : Command.Evaluates
      (ReadOnly.machine verifiedFrontendLexerCore)
      (Stateful.machine verifiedFrontendLexerCore)
      beforeWorld beforeEnvironment command completion afterWorld
      afterEnvironment) :
    Command.Evaluates (Effectful.machine verifiedFrontendLexerCore calls)
      (Stateful.machineWith verifiedFrontendLexerCore
        (Effectful.evaluateOperation verifiedFrontendLexerCore calls))
      beforeWorld beforeEnvironment command completion afterWorld
      afterEnvironment := by
  induction evaluated with
  | skip => exact .skip
  | sequenceNext firstResult secondResult firstIH secondIH =>
      simp only [commandCallFree, Bool.and_eq_true] at free
      exact .sequenceNext (firstIH free.1) (secondIH free.2)
  | sequenceStop firstResult stops firstIH =>
      simp only [commandCallFree, Bool.and_eq_true] at free
      exact .sequenceStop (firstIH free.1) stops
  | letValue initializerResult bodyResult bodyIH =>
      simp only [commandCallFree, Bool.and_eq_true] at free
      have initializerResult' :=
        (Effectful.Term.evaluate_eq_readOnly_of_callFree
          (calls := calls) _ free.1).trans
          initializerResult
      exact .letValue initializerResult' (bodyIH free.2)
  | setLocal valueResult =>
      have valueResult' :=
        (Effectful.Term.evaluate_eq_readOnly_of_callFree (calls := calls) _ (by
          simpa only [commandCallFree] using free)).trans valueResult
      exact .setLocal valueResult'
  | updateLocal valueResult updateResult =>
      have valueResult' :=
        (Effectful.Term.evaluate_eq_readOnly_of_callFree (calls := calls) _ (by
          simpa only [commandCallFree] using free)).trans valueResult
      exact .updateLocal valueResult' updateResult
  | action actionResult => simp [commandCallFree] at free
  | ifTrue conditionResult branchResult branchIH =>
      simp only [commandCallFree, Bool.and_eq_true] at free
      have conditionResult' :=
        (Effectful.Term.evaluate_eq_readOnly_of_callFree
          (calls := calls) _ free.1.1).trans
          conditionResult
      exact .ifTrue conditionResult' (branchIH free.1.2)
  | ifFalse conditionResult branchResult branchIH =>
      simp only [commandCallFree, Bool.and_eq_true] at free
      have conditionResult' :=
        (Effectful.Term.evaluate_eq_readOnly_of_callFree
          (calls := calls) _ free.1.1).trans
          conditionResult
      exact .ifFalse conditionResult' (branchIH free.2)
  | whileFalse conditionResult =>
      simp only [commandCallFree, Bool.and_eq_true] at free
      have conditionResult' :=
        (Effectful.Term.evaluate_eq_readOnly_of_callFree
          (calls := calls) _ free.1).trans
          conditionResult
      exact .whileFalse conditionResult'
  | whileNext conditionResult bodyResult restResult bodyIH restIH =>
      have loopFree := free
      simp only [commandCallFree, Bool.and_eq_true] at free
      have conditionResult' :=
        (Effectful.Term.evaluate_eq_readOnly_of_callFree
          (calls := calls) _ free.1).trans
          conditionResult
      exact .whileNext conditionResult' (bodyIH free.2) (restIH loopFree)
  | whileContinue conditionResult bodyResult restResult bodyIH restIH =>
      have loopFree := free
      simp only [commandCallFree, Bool.and_eq_true] at free
      have conditionResult' :=
        (Effectful.Term.evaluate_eq_readOnly_of_callFree
          (calls := calls) _ free.1).trans
          conditionResult
      exact .whileContinue conditionResult' (bodyIH free.2) (restIH loopFree)
  | whileBreak conditionResult bodyResult bodyIH =>
      simp only [commandCallFree, Bool.and_eq_true] at free
      have conditionResult' :=
        (Effectful.Term.evaluate_eq_readOnly_of_callFree
          (calls := calls) _ free.1).trans
          conditionResult
      exact .whileBreak conditionResult' (bodyIH free.2)
  | whileReturn conditionResult bodyResult bodyIH =>
      simp only [commandCallFree, Bool.and_eq_true] at free
      have conditionResult' :=
        (Effectful.Term.evaluate_eq_readOnly_of_callFree
          (calls := calls) _ free.1).trans
          conditionResult
      exact .whileReturn conditionResult' (bodyIH free.2)
  | returnNone => exact .returnNone
  | returnSome valueResult =>
      have valueResult' :=
        (Effectful.Term.evaluate_eq_readOnly_of_callFree (calls := calls) _ (by
          simpa only [commandCallFree] using free)).trans valueResult
      exact .returnSome valueResult'
  | breakLoop => exact .breakLoop
  | continueLoop => exact .continueLoop

private theorem lineCommentCommand_evaluates
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (openingInBounds : start + 1 < source.length) :
    ∃ afterWorld afterEnvironment,
      Command.Evaluates
        (Effectful.machine verifiedFrontendLexerCore ScanEndCalls.calls)
        (Stateful.machineWith verifiedFrontendLexerCore
          (Effectful.evaluateOperation verifiedFrontendLexerCore ScanEndCalls.calls))
        (sourceWorld source) (scannerParameterEnvironment source start)
        LineComment.view.command
        (.returned (some (.signed .i32
          (Int.ofNat (scanLineCommentEnd source start)))))
        afterWorld afterEnvironment := by
  obtain ⟨afterWorld, afterEnvironment, evaluated⟩ :=
    LineComment.view_evaluates source start sourceBound openingInBounds
  change Command.Evaluates (ReadOnly.machine verifiedFrontendLexerCore)
    (Stateful.machine verifiedFrontendLexerCore)
    (sourceWorld source) (scannerParameterEnvironment source start)
    LineComment.view.command
    (.returned (some (.signed .i32
      (Int.ofNat (scanLineCommentEnd source start)))))
    afterWorld afterEnvironment at evaluated
  exact ⟨afterWorld, afterEnvironment,
    commandEvaluates_effectful_of_readOnly ScanEndCalls.calls
      LineComment.view.command (by native_decide) evaluated⟩

theorem lineCommentFramePreservingCallSoundness (source : List Byte) :
    FreshSimulation.FramePreservingCallSoundness verifiedFrontendCore
      (lineCommentCalls source) := by
  exact effectfulScannerFramePreservingSoundness source
    Scanners.scanLineCommentEndFunction LineComment.view.command
    ScanEndCalls.calls scanEndConstructorLexerFramePreservingCallSoundness
    (fun start => .signed .i32 (Int.ofNat (scanLineCommentEnd source start)))
    (lineCommentCommand_evaluates source) LineComment.view_toCore_exactly
    (by native_decide)
    Scanners.verifiedFrontendLexerCore_finds_scanLineCommentEnd
    (by native_decide) Scanners.scanLineCommentEndFunction_has_body

theorem scannerFramePreservingCallSoundness (source : List Byte) :
    FreshSimulation.FramePreservingCallSoundness verifiedFrontendCore
      (scannerCallModel source) := by
  apply FreshSimulation.FramePreservingCallSoundness.route
    (identifierFramePreservingCallSoundness source)
  apply FreshSimulation.FramePreservingCallSoundness.route
    (whitespaceFramePreservingCallSoundness source)
  apply FreshSimulation.FramePreservingCallSoundness.route
    (stringFramePreservingCallSoundness source)
  apply FreshSimulation.FramePreservingCallSoundness.route
    (characterFramePreservingCallSoundness source)
  apply FreshSimulation.FramePreservingCallSoundness.route
    (lineCommentFramePreservingCallSoundness source)
  apply FreshSimulation.FramePreservingCallSoundness.route
    (quotedAnyFramePreservingCallSoundness source)
  exact blockCommentFramePreservingCallSoundness source

theorem framePreservingCallSoundness (source : List Byte) :
    FreshSimulation.FramePreservingCallSoundness verifiedFrontendCore
      (callModel source) := by
  apply FreshSimulation.FramePreservingCallSoundness.route
    baseFramePreservingCallSoundness
  apply FreshSimulation.FramePreservingCallSoundness.route
    scanEndConstructorFramePreservingCallSoundness
  exact scannerFramePreservingCallSoundness source

private theorem decimalDigitWorldPreserving :
    FreshSimulation.WorldPreserving decimalDigitCalls := by
  intro beforeWorld afterWorld function values value evaluated
  obtain ⟨byte, functionEq, valuesEq, valueEq, worldEq⟩ :=
    decimalDigitCalls_success evaluated
  exact worldEq

private theorem classifyStartWorldPreserving :
    FreshSimulation.WorldPreserving classifyStartCalls := by
  intro beforeWorld afterWorld function values value evaluated
  obtain ⟨byte, functionEq, valuesEq, valueEq, worldEq⟩ :=
    classifyStartCalls_success evaluated
  exact worldEq

private theorem accessorWorldPreserving (function : FunctionId)
    (field : FieldId) :
    FreshSimulation.WorldPreserving (accessorCalls function field) := by
  intro beforeWorld afterWorld functionId values value evaluated
  obtain ⟨success, endOffset, errorOffset, functionEq, valuesEq,
    selected, worldEq⟩ := accessorCalls_success evaluated
  exact worldEq

private theorem baseWorldPreserving :
    FreshSimulation.WorldPreserving baseCallModel := by
  apply FreshSimulation.WorldPreserving.route decimalDigitWorldPreserving
  apply FreshSimulation.WorldPreserving.route classifyStartWorldPreserving
  apply FreshSimulation.WorldPreserving.route
    (accessorWorldPreserving scanSucceededFunction.id 0)
  apply FreshSimulation.WorldPreserving.route
    (accessorWorldPreserving scanEndOffsetFunction.id 1)
  exact accessorWorldPreserving scanErrorOffsetFunction.id 2

private theorem scanEndConstructorWorldPreserving :
    FreshSimulation.WorldPreserving ScanEndCalls.calls := by
  intro beforeWorld afterWorld function values value evaluated
  rcases scanEndConstructorCalls_success evaluated with successful | failed
  · obtain ⟨offset, functionEq, valuesEq, valueEq, worldEq⟩ := successful
    exact worldEq
  · obtain ⟨offset, functionEq, valuesEq, valueEq, worldEq⟩ := failed
    exact worldEq

private theorem scannerCallsWorldPreserving
    (source : List Byte) (function : FunctionId) (requiresOpening : Bool)
    (resultFor : Nat → Value) :
    FreshSimulation.WorldPreserving
      (scannerCalls source function requiresOpening resultFor) := by
  intro beforeWorld afterWorld functionId values value evaluated
  obtain ⟨start, sourceFound, functionEq, valuesEq, sourceBound,
    startInBounds, startBound, opening, valueEq, worldEq⟩ :=
      scannerCalls_success evaluated
  exact worldEq

private theorem quotedAnyWorldPreserving (source : List Byte) :
    FreshSimulation.WorldPreserving (quotedAnyCalls source) := by
  intro beforeWorld afterWorld function values value evaluated
  obtain ⟨start, delimiter, sourceFound, functionEq, valuesEq, sourceBound,
    startInBounds, startBound, valueEq, worldEq⟩ :=
      quotedAnyCalls_success evaluated
  exact worldEq

private theorem scannerWorldPreserving (source : List Byte) :
    FreshSimulation.WorldPreserving (scannerCallModel source) := by
  apply FreshSimulation.WorldPreserving.route
    (scannerCallsWorldPreserving source Scanners.scanIdentifierEndFunction.id
      false (fun start =>
        .signed .i32 (Int.ofNat (scanIdentifierEnd source start))))
  apply FreshSimulation.WorldPreserving.route
    (scannerCallsWorldPreserving source Scanners.scanWhitespaceEndFunction.id
      false (fun start =>
        .signed .i32 (Int.ofNat (scanWhitespaceEnd source start))))
  apply FreshSimulation.WorldPreserving.route
    (scannerCallsWorldPreserving source Scanners.scanStringEndFunction.id false
      (fun start => encodedScanEnd
        (scanQuotedEnd source start Program.doubleQuoteByte)))
  apply FreshSimulation.WorldPreserving.route
    (scannerCallsWorldPreserving source Scanners.scanCharacterEndFunction.id
      false (fun start => encodedScanEnd
        (scanQuotedEnd source start Program.singleQuoteByte)))
  apply FreshSimulation.WorldPreserving.route
    (scannerCallsWorldPreserving source Scanners.scanLineCommentEndFunction.id
      true (fun start =>
        .signed .i32 (Int.ofNat (scanLineCommentEnd source start))))
  apply FreshSimulation.WorldPreserving.route
    (quotedAnyWorldPreserving source)
  exact scannerCallsWorldPreserving source
    Scanners.scanBlockCommentEndFunction.id true
    (fun start => encodedScanEnd (scanBlockCommentEnd source start))

theorem worldPreserving (source : List Byte) :
    FreshSimulation.WorldPreserving (callModel source) := by
  apply FreshSimulation.WorldPreserving.route baseWorldPreserving
  apply FreshSimulation.WorldPreserving.route scanEndConstructorWorldPreserving
  exact scannerWorldPreserving source

theorem callSoundness (source : List Byte) :
    EffectfulStateful.CallSoundness verifiedFrontendCore (callModel source) :=
  (framePreservingCallSoundness source).toCallSoundness
    (worldPreserving source)

@[simp] theorem scannerCallModel_identifier
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length)
    (startBound : start ≤ 2147483647) :
    (scannerCallModel source).evaluate (sourceWorld source)
        Scanners.scanIdentifierEndFunction.id (scannerArguments source start) =
      .ok (.signed .i32 (Int.ofNat (scanIdentifierEnd source start)),
        sourceWorld source) := by
  simp [scannerCallModel, CallModel.route, identifierCalls, scannerCalls,
    scannerArguments, sourceSlice, sourceBound]
  split <;> simp_all [Int.ofNat_inj] <;> omega

@[simp] theorem scannerCallModel_whitespace
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length)
    (startBound : start ≤ 2147483647) :
    (scannerCallModel source).evaluate (sourceWorld source)
        Scanners.scanWhitespaceEndFunction.id (scannerArguments source start) =
      .ok (.signed .i32 (Int.ofNat (scanWhitespaceEnd source start)),
        sourceWorld source) := by
  have different : Scanners.scanWhitespaceEndFunction.id ≠
      Scanners.scanIdentifierEndFunction.id := by native_decide
  simp [scannerCallModel, CallModel.route, whitespaceCalls, scannerCalls,
    scannerArguments, sourceSlice, sourceBound, different]
  split <;> simp_all [Int.ofNat_inj] <;> omega

@[simp] theorem scannerCallModel_string
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length)
    (startBound : start ≤ 2147483647) :
    (scannerCallModel source).evaluate (sourceWorld source)
        Scanners.scanStringEndFunction.id (scannerArguments source start) =
      .ok (encodedScanEnd
          (scanQuotedEnd source start Program.doubleQuoteByte),
        sourceWorld source) := by
  have identifierDifferent : Scanners.scanStringEndFunction.id ≠
      Scanners.scanIdentifierEndFunction.id := by native_decide
  have whitespaceDifferent : Scanners.scanStringEndFunction.id ≠
      Scanners.scanWhitespaceEndFunction.id := by native_decide
  simp [scannerCallModel, CallModel.route, stringCalls, scannerCalls,
    scannerArguments, sourceSlice, sourceBound,
    identifierDifferent, whitespaceDifferent]
  split <;> simp_all [Int.ofNat_inj] <;> omega

@[simp] theorem scannerCallModel_character
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length)
    (startBound : start ≤ 2147483647) :
    (scannerCallModel source).evaluate (sourceWorld source)
        Scanners.scanCharacterEndFunction.id (scannerArguments source start) =
      .ok (encodedScanEnd
          (scanQuotedEnd source start Program.singleQuoteByte),
        sourceWorld source) := by
  have identifierDifferent : Scanners.scanCharacterEndFunction.id ≠
      Scanners.scanIdentifierEndFunction.id := by native_decide
  have whitespaceDifferent : Scanners.scanCharacterEndFunction.id ≠
      Scanners.scanWhitespaceEndFunction.id := by native_decide
  have stringDifferent : Scanners.scanCharacterEndFunction.id ≠
      Scanners.scanStringEndFunction.id := by native_decide
  simp [scannerCallModel, CallModel.route, characterCalls, scannerCalls,
    scannerArguments, sourceSlice, sourceBound,
    identifierDifferent, whitespaceDifferent, stringDifferent]
  split <;> simp_all [Int.ofNat_inj] <;> omega

@[simp] theorem scannerCallModel_lineComment
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (openingInBounds : start + 1 < source.length)
    (startBound : start ≤ 2147483647) :
    (scannerCallModel source).evaluate (sourceWorld source)
        Scanners.scanLineCommentEndFunction.id (scannerArguments source start) =
      .ok (.signed .i32 (Int.ofNat (scanLineCommentEnd source start)),
        sourceWorld source) := by
  have startInBounds : start < source.length := by omega
  have identifierDifferent : Scanners.scanLineCommentEndFunction.id ≠
      Scanners.scanIdentifierEndFunction.id := by native_decide
  have whitespaceDifferent : Scanners.scanLineCommentEndFunction.id ≠
      Scanners.scanWhitespaceEndFunction.id := by native_decide
  have stringDifferent : Scanners.scanLineCommentEndFunction.id ≠
      Scanners.scanStringEndFunction.id := by native_decide
  have characterDifferent : Scanners.scanLineCommentEndFunction.id ≠
      Scanners.scanCharacterEndFunction.id := by native_decide
  simp [scannerCallModel, CallModel.route, lineCommentCalls, scannerCalls,
    scannerArguments, sourceSlice, sourceBound,
    identifierDifferent, whitespaceDifferent,
    stringDifferent, characterDifferent]
  split <;> simp_all [Int.ofNat_inj] <;> omega

@[simp] theorem scannerCallModel_blockComment
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (openingInBounds : start + 1 < source.length)
    (startBound : start ≤ 2147483647) :
    (scannerCallModel source).evaluate (sourceWorld source)
        Scanners.scanBlockCommentEndFunction.id (scannerArguments source start) =
      .ok (encodedScanEnd (scanBlockCommentEnd source start),
        sourceWorld source) := by
  have startInBounds : start < source.length := by omega
  have identifierDifferent : Scanners.scanBlockCommentEndFunction.id ≠
      Scanners.scanIdentifierEndFunction.id := by native_decide
  have whitespaceDifferent : Scanners.scanBlockCommentEndFunction.id ≠
      Scanners.scanWhitespaceEndFunction.id := by native_decide
  have stringDifferent : Scanners.scanBlockCommentEndFunction.id ≠
      Scanners.scanStringEndFunction.id := by native_decide
  have characterDifferent : Scanners.scanBlockCommentEndFunction.id ≠
      Scanners.scanCharacterEndFunction.id := by native_decide
  have lineDifferent : Scanners.scanBlockCommentEndFunction.id ≠
      Scanners.scanLineCommentEndFunction.id := by native_decide
  have quotedDifferent : Scanners.scanBlockCommentEndFunction.id ≠
      Scanners.scanQuotedEndFunction.id := by native_decide
  simp [scannerCallModel, CallModel.route, blockCommentCalls, scannerCalls,
    scannerArguments, sourceSlice, sourceBound,
    identifierDifferent, whitespaceDifferent,
    stringDifferent, characterDifferent, lineDifferent, quotedDifferent]
  split <;> simp_all [Int.ofNat_inj] <;> omega

@[simp] theorem scannerCallModel_quoted
    (source : List Byte) (start : Nat) (delimiter : Byte)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length)
    (startBound : start ≤ 2147483647) :
    (scannerCallModel source).evaluate (sourceWorld source)
        Scanners.scanQuotedEndFunction.id
        (quotedArguments source start delimiter) =
      .ok (encodedScanEnd (scanQuotedEnd source start delimiter),
        sourceWorld source) := by
  simp only [scannerCallModel, CallModel.route]
  rw [if_neg (by native_decide), if_neg (by native_decide),
    if_neg (by native_decide), if_neg (by native_decide),
    if_neg (by native_decide)]
  rw [show decide True = true by native_decide]
  simp only [if_true]
  exact quotedAnyCalls_at source start delimiter sourceBound startInBounds
    startBound

private theorem callModel_scanner_route (source : List Byte)
    (function : FunctionId) (world : World) (arguments : List Value)
    (notBase : ¬(function = isDecimalDigitFunction.id ∨
      function = classifyStartFunction.id ∨
      function = scanSucceededFunction.id ∨
      function = scanEndOffsetFunction.id ∨
      function = scanErrorOffsetFunction.id))
    (notConstructor : ¬(function = successfulScanFunction.id ∨
      function = failedScanFunction.id)) :
    (callModel source).evaluate world function arguments =
      (scannerCallModel source).evaluate world function arguments := by
  simp [callModel, CallModel.route, notBase, notConstructor]

@[simp] theorem callModel_decimalDigit (source : List Byte)
    (world : World) (byte : Byte) :
    (callModel source).evaluate world isDecimalDigitFunction.id
        [.signed .i32 (Int.ofNat byte.val)] =
      .ok (.boolean (isDecimalDigit byte), world) := by
  rw [show (callModel source).evaluate world isDecimalDigitFunction.id
      [.signed .i32 (Int.ofNat byte.val)] =
      decimalDigitCalls.evaluate world isDecimalDigitFunction.id
        [.signed .i32 (Int.ofNat byte.val)] by
    simp [callModel, baseCallModel, CallModel.route]]
  exact decimalDigitCalls_at world byte

@[simp] theorem callModel_classifyStart (source : List Byte)
    (world : World) (byte : Byte) :
    (callModel source).evaluate world classifyStartFunction.id
        [.signed .i32 (Int.ofNat byte.val)] =
      .ok (.signed .i32 (Int.ofNat (classifyStartCode byte)), world) := by
  rw [show (callModel source).evaluate world classifyStartFunction.id
      [.signed .i32 (Int.ofNat byte.val)] =
      classifyStartCalls.evaluate world classifyStartFunction.id
        [.signed .i32 (Int.ofNat byte.val)] by
    simp [callModel, baseCallModel, CallModel.route,
      (by native_decide : classifyStartFunction.id ≠ isDecimalDigitFunction.id)]]
  exact classifyStartCalls_at world byte

@[simp] theorem callModel_scanSucceeded (source : List Byte)
    (world : World) (success : Bool) (endOffset errorOffset : Int) :
    (callModel source).evaluate world scanSucceededFunction.id
        [ScanEnd.value success endOffset errorOffset] =
      .ok (.boolean success, world) := by
  rw [show (callModel source).evaluate world scanSucceededFunction.id
      [ScanEnd.value success endOffset errorOffset] =
      scanSucceededCalls.evaluate world scanSucceededFunction.id
        [ScanEnd.value success endOffset errorOffset] by
    simp [callModel, baseCallModel, CallModel.route,
      (by native_decide : scanSucceededFunction.id ≠ isDecimalDigitFunction.id),
      (by native_decide : scanSucceededFunction.id ≠ classifyStartFunction.id)]]
  exact scanSucceededCalls_at world success endOffset errorOffset

@[simp] theorem callModel_scanEndOffset (source : List Byte)
    (world : World) (success : Bool) (endOffset errorOffset : Int) :
    (callModel source).evaluate world scanEndOffsetFunction.id
        [ScanEnd.value success endOffset errorOffset] =
      .ok (.signed .i32 endOffset, world) := by
  rw [show (callModel source).evaluate world scanEndOffsetFunction.id
      [ScanEnd.value success endOffset errorOffset] =
      scanEndOffsetCalls.evaluate world scanEndOffsetFunction.id
        [ScanEnd.value success endOffset errorOffset] by
    simp [callModel, baseCallModel, CallModel.route,
      (by native_decide : scanEndOffsetFunction.id ≠ isDecimalDigitFunction.id),
      (by native_decide : scanEndOffsetFunction.id ≠ classifyStartFunction.id),
      (by native_decide : scanEndOffsetFunction.id ≠ scanSucceededFunction.id)]]
  exact scanEndOffsetCalls_at world success endOffset errorOffset

@[simp] theorem callModel_scanErrorOffset (source : List Byte)
    (world : World) (success : Bool) (endOffset errorOffset : Int) :
    (callModel source).evaluate world scanErrorOffsetFunction.id
        [ScanEnd.value success endOffset errorOffset] =
      .ok (.signed .i32 errorOffset, world) := by
  rw [show (callModel source).evaluate world scanErrorOffsetFunction.id
      [ScanEnd.value success endOffset errorOffset] =
      scanErrorOffsetCalls.evaluate world scanErrorOffsetFunction.id
        [ScanEnd.value success endOffset errorOffset] by
    simp [callModel, baseCallModel, CallModel.route,
      (by native_decide : scanErrorOffsetFunction.id ≠ isDecimalDigitFunction.id),
      (by native_decide : scanErrorOffsetFunction.id ≠ classifyStartFunction.id),
      (by native_decide : scanErrorOffsetFunction.id ≠ scanSucceededFunction.id),
      (by native_decide : scanErrorOffsetFunction.id ≠ scanEndOffsetFunction.id)]]
  exact scanErrorOffsetCalls_at world success endOffset errorOffset

@[simp] theorem callModel_successfulScan (source : List Byte)
    (world : World) (offset : Int) :
    (callModel source).evaluate world successfulScanFunction.id
        [.signed .i32 offset] =
      .ok (ScanEnd.value true offset 0, world) := by
  rw [show (callModel source).evaluate world successfulScanFunction.id
      [.signed .i32 offset] = ScanEndCalls.calls.evaluate world
        successfulScanFunction.id [.signed .i32 offset] by
    simp [callModel, CallModel.route,
      (by native_decide : ¬(successfulScanFunction.id = isDecimalDigitFunction.id ∨
        successfulScanFunction.id = classifyStartFunction.id ∨
        successfulScanFunction.id = scanSucceededFunction.id ∨
        successfulScanFunction.id = scanEndOffsetFunction.id ∨
        successfulScanFunction.id = scanErrorOffsetFunction.id))]]
  exact ScanEndCalls.successful world offset

@[simp] theorem callModel_failedScan (source : List Byte)
    (world : World) (offset : Int) :
    (callModel source).evaluate world failedScanFunction.id
        [.signed .i32 offset] =
      .ok (ScanEnd.value false 0 offset, world) := by
  rw [show (callModel source).evaluate world failedScanFunction.id
      [.signed .i32 offset] = ScanEndCalls.calls.evaluate world
        failedScanFunction.id [.signed .i32 offset] by
    simp [callModel, CallModel.route,
      (by native_decide : ¬(failedScanFunction.id = isDecimalDigitFunction.id ∨
        failedScanFunction.id = classifyStartFunction.id ∨
        failedScanFunction.id = scanSucceededFunction.id ∨
        failedScanFunction.id = scanEndOffsetFunction.id ∨
        failedScanFunction.id = scanErrorOffsetFunction.id)),
      (by native_decide : failedScanFunction.id ≠ successfulScanFunction.id)]]
  exact ScanEndCalls.failed world offset

@[simp] theorem callModel_identifier
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length)
    (startBound : start ≤ 2147483647) :
    (callModel source).evaluate (sourceWorld source)
        Scanners.scanIdentifierEndFunction.id (scannerArguments source start) =
      .ok (.signed .i32 (Int.ofNat (scanIdentifierEnd source start)),
        sourceWorld source) := by
  rw [callModel_scanner_route source Scanners.scanIdentifierEndFunction.id
    (sourceWorld source) (scannerArguments source start)
    (by native_decide) (by native_decide)]
  exact scannerCallModel_identifier source start sourceBound startInBounds
    startBound

@[simp] theorem callModel_whitespace
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length)
    (startBound : start ≤ 2147483647) :
    (callModel source).evaluate (sourceWorld source)
        Scanners.scanWhitespaceEndFunction.id (scannerArguments source start) =
      .ok (.signed .i32 (Int.ofNat (scanWhitespaceEnd source start)),
        sourceWorld source) := by
  rw [callModel_scanner_route source Scanners.scanWhitespaceEndFunction.id
    (sourceWorld source) (scannerArguments source start)
    (by native_decide) (by native_decide)]
  exact scannerCallModel_whitespace source start sourceBound startInBounds
    startBound

@[simp] theorem callModel_quoted
    (source : List Byte) (start : Nat) (delimiter : Byte)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length)
    (startBound : start ≤ 2147483647) :
    (callModel source).evaluate (sourceWorld source)
        Scanners.scanQuotedEndFunction.id
        (quotedArguments source start delimiter) =
      .ok (encodedScanEnd (scanQuotedEnd source start delimiter),
        sourceWorld source) := by
  rw [callModel_scanner_route source Scanners.scanQuotedEndFunction.id
    (sourceWorld source) (quotedArguments source start delimiter)
    (by native_decide) (by native_decide)]
  exact scannerCallModel_quoted source start delimiter sourceBound
    startInBounds startBound

@[simp] theorem callModel_string
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length)
    (startBound : start ≤ 2147483647) :
    (callModel source).evaluate (sourceWorld source)
        Scanners.scanStringEndFunction.id (scannerArguments source start) =
      .ok (encodedScanEnd
          (scanQuotedEnd source start Program.doubleQuoteByte),
        sourceWorld source) := by
  rw [callModel_scanner_route source Scanners.scanStringEndFunction.id
    (sourceWorld source) (scannerArguments source start)
    (by native_decide) (by native_decide)]
  exact scannerCallModel_string source start sourceBound startInBounds startBound

@[simp] theorem callModel_character
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length)
    (startBound : start ≤ 2147483647) :
    (callModel source).evaluate (sourceWorld source)
        Scanners.scanCharacterEndFunction.id (scannerArguments source start) =
      .ok (encodedScanEnd
          (scanQuotedEnd source start Program.singleQuoteByte),
        sourceWorld source) := by
  rw [callModel_scanner_route source Scanners.scanCharacterEndFunction.id
    (sourceWorld source) (scannerArguments source start)
    (by native_decide) (by native_decide)]
  exact scannerCallModel_character source start sourceBound startInBounds
    startBound

@[simp] theorem callModel_lineComment
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (openingInBounds : start + 1 < source.length)
    (startBound : start ≤ 2147483647) :
    (callModel source).evaluate (sourceWorld source)
        Scanners.scanLineCommentEndFunction.id (scannerArguments source start) =
      .ok (.signed .i32 (Int.ofNat (scanLineCommentEnd source start)),
        sourceWorld source) := by
  rw [callModel_scanner_route source Scanners.scanLineCommentEndFunction.id
    (sourceWorld source) (scannerArguments source start)
    (by native_decide) (by native_decide)]
  exact scannerCallModel_lineComment source start sourceBound openingInBounds
    startBound

@[simp] theorem callModel_blockComment
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (openingInBounds : start + 1 < source.length)
    (startBound : start ≤ 2147483647) :
    (callModel source).evaluate (sourceWorld source)
        Scanners.scanBlockCommentEndFunction.id (scannerArguments source start) =
      .ok (encodedScanEnd (scanBlockCommentEnd source start),
        sourceWorld source) := by
  rw [callModel_scanner_route source Scanners.scanBlockCommentEndFunction.id
    (sourceWorld source) (scannerArguments source start)
    (by native_decide) (by native_decide)]
  exact scannerCallModel_blockComment source start sourceBound openingInBounds
    startBound

@[simp] theorem callModel_identifier_in_world
    (source : List Byte) (world : World) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length)
    (startBound : start ≤ 2147483647)
    (sourceFound : world.i32Slice? 0 = some (sourceIntegers source)) :
    (callModel source).evaluate world Scanners.scanIdentifierEndFunction.id
        (scannerArguments source start) =
      .ok (.signed .i32 (Int.ofNat (scanIdentifierEnd source start)), world) := by
  rw [callModel_scanner_route source Scanners.scanIdentifierEndFunction.id
    world (scannerArguments source start) (by native_decide) (by native_decide)]
  simp only [scannerCallModel, CallModel.route]
  rw [show decide True = true by native_decide]
  simp only [if_true]
  exact scannerCalls_at_world source Scanners.scanIdentifierEndFunction.id
    false _ world start sourceBound startInBounds startBound (by simp) sourceFound

@[simp] theorem callModel_whitespace_in_world
    (source : List Byte) (world : World) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length)
    (startBound : start ≤ 2147483647)
    (sourceFound : world.i32Slice? 0 = some (sourceIntegers source)) :
    (callModel source).evaluate world Scanners.scanWhitespaceEndFunction.id
        (scannerArguments source start) =
      .ok (.signed .i32 (Int.ofNat (scanWhitespaceEnd source start)), world) := by
  rw [callModel_scanner_route source Scanners.scanWhitespaceEndFunction.id
    world (scannerArguments source start) (by native_decide) (by native_decide)]
  simp only [scannerCallModel, CallModel.route]
  rw [if_neg (by native_decide)]
  rw [show decide True = true by native_decide]
  simp only [if_true]
  exact scannerCalls_at_world source Scanners.scanWhitespaceEndFunction.id
    false _ world start sourceBound startInBounds startBound (by simp) sourceFound

@[simp] theorem callModel_string_in_world
    (source : List Byte) (world : World) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length)
    (startBound : start ≤ 2147483647)
    (sourceFound : world.i32Slice? 0 = some (sourceIntegers source)) :
    (callModel source).evaluate world Scanners.scanStringEndFunction.id
        (scannerArguments source start) =
      .ok (encodedScanEnd
        (scanQuotedEnd source start Program.doubleQuoteByte), world) := by
  rw [callModel_scanner_route source Scanners.scanStringEndFunction.id
    world (scannerArguments source start) (by native_decide) (by native_decide)]
  simp only [scannerCallModel, CallModel.route]
  rw [if_neg (by native_decide), if_neg (by native_decide)]
  rw [show decide True = true by native_decide]
  simp only [if_true]
  exact scannerCalls_at_world source Scanners.scanStringEndFunction.id
    false _ world start sourceBound startInBounds startBound (by simp) sourceFound

@[simp] theorem callModel_character_in_world
    (source : List Byte) (world : World) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length)
    (startBound : start ≤ 2147483647)
    (sourceFound : world.i32Slice? 0 = some (sourceIntegers source)) :
    (callModel source).evaluate world Scanners.scanCharacterEndFunction.id
        (scannerArguments source start) =
      .ok (encodedScanEnd
        (scanQuotedEnd source start Program.singleQuoteByte), world) := by
  rw [callModel_scanner_route source Scanners.scanCharacterEndFunction.id
    world (scannerArguments source start) (by native_decide) (by native_decide)]
  simp only [scannerCallModel, CallModel.route]
  rw [if_neg (by native_decide), if_neg (by native_decide),
    if_neg (by native_decide)]
  rw [show decide True = true by native_decide]
  simp only [if_true]
  exact scannerCalls_at_world source Scanners.scanCharacterEndFunction.id
    false _ world start sourceBound startInBounds startBound (by simp) sourceFound

@[simp] theorem callModel_lineComment_in_world
    (source : List Byte) (world : World) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (openingInBounds : start + 1 < source.length)
    (startBound : start ≤ 2147483647)
    (sourceFound : world.i32Slice? 0 = some (sourceIntegers source)) :
    (callModel source).evaluate world Scanners.scanLineCommentEndFunction.id
        (scannerArguments source start) =
      .ok (.signed .i32 (Int.ofNat (scanLineCommentEnd source start)), world) := by
  have startInBounds : start < source.length := by omega
  rw [callModel_scanner_route source Scanners.scanLineCommentEndFunction.id
    world (scannerArguments source start) (by native_decide) (by native_decide)]
  simp only [scannerCallModel, CallModel.route]
  rw [if_neg (by native_decide), if_neg (by native_decide),
    if_neg (by native_decide), if_neg (by native_decide)]
  rw [show decide True = true by native_decide]
  simp only [if_true]
  exact scannerCalls_at_world source Scanners.scanLineCommentEndFunction.id
    true _ world start sourceBound startInBounds startBound
    (by simpa using openingInBounds) sourceFound

@[simp] theorem callModel_blockComment_in_world
    (source : List Byte) (world : World) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (openingInBounds : start + 1 < source.length)
    (startBound : start ≤ 2147483647)
    (sourceFound : world.i32Slice? 0 = some (sourceIntegers source)) :
    (callModel source).evaluate world Scanners.scanBlockCommentEndFunction.id
        (scannerArguments source start) =
      .ok (encodedScanEnd (scanBlockCommentEnd source start), world) := by
  have startInBounds : start < source.length := by omega
  rw [callModel_scanner_route source Scanners.scanBlockCommentEndFunction.id
    world (scannerArguments source start) (by native_decide) (by native_decide)]
  simp only [scannerCallModel, CallModel.route]
  rw [if_neg (by native_decide), if_neg (by native_decide),
    if_neg (by native_decide), if_neg (by native_decide),
    if_neg (by native_decide), if_neg (by native_decide)]
  exact scannerCalls_at_world source Scanners.scanBlockCommentEndFunction.id
    true _ world start sourceBound startInBounds startBound
    (by simpa using openingInBounds) sourceFound

@[simp] theorem callModel_quoted_in_world
    (source : List Byte) (world : World) (start : Nat) (delimiter : Byte)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length)
    (startBound : start ≤ 2147483647)
    (sourceFound : world.i32Slice? 0 = some (sourceIntegers source)) :
    (callModel source).evaluate world Scanners.scanQuotedEndFunction.id
        (quotedArguments source start delimiter) =
      .ok (encodedScanEnd (scanQuotedEnd source start delimiter), world) := by
  rw [callModel_scanner_route source Scanners.scanQuotedEndFunction.id
    world (quotedArguments source start delimiter)
    (by native_decide) (by native_decide)]
  simp only [scannerCallModel, CallModel.route]
  rw [if_neg (by native_decide), if_neg (by native_decide),
    if_neg (by native_decide), if_neg (by native_decide),
    if_neg (by native_decide)]
  rw [show decide True = true by native_decide]
  simp only [if_true]
  exact quotedAnyCalls_at_world source world start delimiter sourceBound
    startInBounds startBound sourceFound

end Lanius.Extraction.Lexer.Calls
