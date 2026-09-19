import Lanius.Extraction.VerifiedFrontend.Parser.Reads
import Lanius.FunctionalViewCoreCallFrame
import Lanius.FunctionalViewCoreEffectfulStateful
import Lanius.FunctionalViewCoreStatefulReification

namespace Lanius.Extraction.ParserReads.Functional

open Lanius.Core
open Lanius.Semantics
open Lanius.Fuel
open Lanius.Properties
open Lanius.Separation
open Lanius.CallContracts
open Lanius.Compiler.Parser
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly
open Lanius.FunctionalView.Core.Effectful
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Core.Stateful.Reification

/-! # FunctionalView contracts for parser workspace reads

These views are mechanically recovered from the checked `parser.lani`
artifact. Their round-trip theorems connect the proof-facing commands to the
exact extracted bodies, while the call models expose their mathematical
addressing and read semantics to FunctionalView clients.
-/

namespace ChartWord

def parameterLayout : Layout 2 := identityLayout

def parameterContext : Lanius.Typing.Context :=
  Lanius.Typing.parameterContext
    extractedParserChartWordFunction.parameters

private def reification? :=
  reifyCommand? verifiedParserCore extractedParserChartWordFunction.returnType
    parameterContext false parameterLayout 2 extractedParserChartWordBody

theorem reification_exists : reification?.isSome := by
  native_decide

def view := reification?.get reification_exists

theorem view_toCore_exactly :
    toCoreStmt actionAdapter parameterLayout 2 view.command =
      extractedParserChartWordBody :=
  view.toCoreExactly

def arguments (position field : Int) : List Value := [
  .signed .i32 position,
  .signed .i32 field]

def result (position field : Int) : Value :=
  .signed .i32
    (parserChartWordValue verifiedParserCore.target position field)

def calls : CallModel where
  evaluate := fun world function values =>
    if function = extractedParserChartWordFunction.id then
      match values with
      | [.signed .i32 position, .signed .i32 field] =>
          .ok (result position field, world)
      | _ => .error .typeMismatch
    else
      .error .invalidPointer

theorem calls_at_arguments :
    calls.evaluate world extractedParserChartWordFunction.id
        (arguments position field) =
      .ok (result position field, world) := by
  simp [calls, arguments, result]

theorem calls_success
    (evaluated : calls.evaluate world function values =
      .ok (value, afterWorld)) :
    ∃ position field,
      function = extractedParserChartWordFunction.id ∧
      values = arguments position field ∧
      value = result position field ∧
      afterWorld = world := by
  simp only [calls] at evaluated
  split at evaluated
  next functionEq =>
    split at evaluated
    next position field =>
      obtain ⟨rfl, rfl⟩ := evaluated
      exact ⟨position, field, functionEq, rfl, rfl, rfl⟩
    next => contradiction
  next => contradiction

theorem call_soundness :
    Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness
      verifiedParserCore calls := by
  constructor
  · intro arity commandLayout localCell beforeWorld afterWorld environment
      before afterArguments function callArguments values value argumentWrites
      afterArgumentsWellFormed represented argumentsExecution argumentsEffect
      evaluated
    obtain ⟨position, field, functionEq, valuesEq, valueEq, worldEq⟩ :=
      calls_success evaluated
    subst function
    subst values
    subst value
    subst afterWorld
    let after := parserChartWordCallState afterArguments position field
    have callExecution : Evaluates verifiedParserCore before
        (.call extractedParserChartWordFunction.id
          (toCoreExprs commandLayout callArguments))
        (result position field) after := by
      simpa [after, parserChartWordCallState, arguments, result] using
        extractedParserChartWordCall_evaluates before afterArguments
          (toCoreExprs commandLayout callArguments) position field
          afterArgumentsWellFormed argumentsExecution
    obtain ⟨afterWellFormed, afterRepresented, callEffect⟩ :=
      represented.restoreCallLocals (calleeArity := 2)
        afterArgumentsWellFormed
        (parserChartWordCallee_well_formed afterArgumentsWellFormed)
        (by exact (ModifiesOnly.refl _).weaken CellSet.empty_subset)
    exact ⟨after, CellSet.union argumentWrites CellSet.empty, callExecution,
      afterWellFormed, afterRepresented, argumentsEffect.trans callEffect⟩
  · intro beforeWorld afterWorld function values value evaluated cell
    obtain ⟨position, field, functionEq, valuesEq, valueEq, worldEq⟩ :=
      calls_success evaluated
    exact congrArg (fun currentWorld : World =>
      (currentWorld.i32Slice? cell).map List.length) worldEq

end ChartWord

namespace StateWord

def parameterLayout : Layout 3 := identityLayout

def parameterContext : Lanius.Typing.Context :=
  Lanius.Typing.parameterContext
    extractedParserStateWordFunction.parameters

private def reification? :=
  reifyCommand? verifiedParserCore extractedParserStateWordFunction.returnType
    parameterContext false parameterLayout 3 extractedParserStateWordBody

theorem reification_exists : reification?.isSome := by
  native_decide

def view := reification?.get reification_exists

theorem view_toCore_exactly :
    toCoreStmt actionAdapter parameterLayout 3 view.command =
      extractedParserStateWordBody :=
  view.toCoreExactly

def arguments (base stateId field : Int) : List Value := [
  .signed .i32 base,
  .signed .i32 stateId,
  .signed .i32 field]

def result (base stateId field : Int) : Value :=
  .signed .i32
    (parserStateWordValue verifiedParserCore.target base stateId field)

def calls : CallModel where
  evaluate := fun world function values =>
    if function = extractedParserStateWordFunction.id then
      match values with
      | [.signed .i32 base, .signed .i32 stateId, .signed .i32 field] =>
          .ok (result base stateId field, world)
      | _ => .error .typeMismatch
    else
      .error .invalidPointer

theorem calls_at_arguments :
    calls.evaluate world extractedParserStateWordFunction.id
        (arguments base stateId field) =
      .ok (result base stateId field, world) := by
  simp [calls, arguments, result]

theorem calls_success
    (evaluated : calls.evaluate world function values =
      .ok (value, afterWorld)) :
    ∃ base stateId field,
      function = extractedParserStateWordFunction.id ∧
      values = arguments base stateId field ∧
      value = result base stateId field ∧
      afterWorld = world := by
  simp only [calls] at evaluated
  split at evaluated
  next functionEq =>
    split at evaluated
    next base stateId field =>
      obtain ⟨rfl, rfl⟩ := evaluated
      exact ⟨base, stateId, field, functionEq, rfl, rfl, rfl⟩
    next => contradiction
  next => contradiction

theorem call_soundness :
    Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness
      verifiedParserCore calls := by
  constructor
  · intro arity commandLayout localCell beforeWorld afterWorld environment
      before afterArguments function callArguments values value argumentWrites
      afterArgumentsWellFormed represented argumentsExecution argumentsEffect
      evaluated
    obtain ⟨base, stateId, field, functionEq, valuesEq, valueEq, worldEq⟩ :=
      calls_success evaluated
    subst function
    subst values
    subst value
    subst afterWorld
    let after := parserStateWordCallState afterArguments base stateId field
    have callExecution : Evaluates verifiedParserCore before
        (.call extractedParserStateWordFunction.id
          (toCoreExprs commandLayout callArguments))
        (result base stateId field) after := by
      simpa [after, parserStateWordCallState, arguments, result] using
        extractedParserStateWordCall_evaluates before afterArguments
          (toCoreExprs commandLayout callArguments) base stateId field
          afterArgumentsWellFormed argumentsExecution
    obtain ⟨afterWellFormed, afterRepresented, callEffect⟩ :=
      represented.restoreCallLocals (calleeArity := 3)
        afterArgumentsWellFormed
        (parserStateWordCallee_well_formed afterArgumentsWellFormed)
        (by exact (ModifiesOnly.refl _).weaken CellSet.empty_subset)
    exact ⟨after, CellSet.union argumentWrites CellSet.empty, callExecution,
      afterWellFormed, afterRepresented, argumentsEffect.trans callEffect⟩
  · intro beforeWorld afterWorld function values value evaluated cell
    obtain ⟨base, stateId, field, functionEq, valuesEq, valueEq, worldEq⟩ :=
      calls_success evaluated
    exact congrArg (fun currentWorld =>
      (currentWorld.i32Slice? cell).map List.length) worldEq

end StateWord

namespace StateValue

def parameterLayout : Layout 4 := identityLayout

def parameterContext : Lanius.Typing.Context :=
  Lanius.Typing.parameterContext
    extractedParserStateValueFunction.parameters

private def reification? :=
  reifyCommand? verifiedParserCore extractedParserStateValueFunction.returnType
    parameterContext false parameterLayout 4 extractedParserStateValueBody

theorem reification_exists : reification?.isSome := by
  native_decide

def view := reification?.get reification_exists

theorem view_toCore_exactly :
    toCoreStmt actionAdapter parameterLayout 4 view.command =
      extractedParserStateValueBody :=
  view.toCoreExactly

def arguments (values : List Int) (workspaceCell : CellId)
    (base stateId field : Int) : List Value := [
  .slice parserI32Type workspaceCell [] 0 values.length,
  .signed .i32 base,
  .signed .i32 stateId,
  .signed .i32 field]

def result (values : List Int) (address : Nat)
    (addressBound : address < values.length) : Value :=
  .signed .i32 (values.get ⟨address, addressBound⟩)

noncomputable def calls (values : List Int) (workspaceCell : CellId)
    (base stateId field : Int) (address : Nat)
    (addressBound : address < values.length) : CallModel := by
  classical
  exact {
    evaluate := fun world function callArguments =>
      if function = extractedParserStateValueFunction.id then
        if callArguments = arguments values workspaceCell base stateId field then
          if world.i32Slice? workspaceCell = some values then
            .ok (result values address addressBound, world)
          else
            .error .invalidPointer
        else
          .error .typeMismatch
      else
        .error .invalidPointer
  }

theorem calls_at_arguments
    (found : world.i32Slice? workspaceCell = some values) :
    (calls values workspaceCell base stateId field address addressBound).evaluate
        world extractedParserStateValueFunction.id
        (arguments values workspaceCell base stateId field) =
      .ok (result values address addressBound, world) := by
  simp [calls, found]

theorem calls_success
    (evaluated :
      (calls values workspaceCell base stateId field address addressBound).evaluate
          world function callArguments = .ok (value, afterWorld)) :
    function = extractedParserStateValueFunction.id ∧
      callArguments = arguments values workspaceCell base stateId field ∧
      world.i32Slice? workspaceCell = some values ∧
      value = result values address addressBound ∧
      afterWorld = world := by
  simp only [calls] at evaluated
  split at evaluated
  next functionEq =>
    split at evaluated
    next argumentsEq =>
      split at evaluated
      next found =>
        obtain ⟨rfl, rfl⟩ := evaluated
        exact ⟨functionEq, argumentsEq, found, rfl, rfl⟩
      next => contradiction
    next => contradiction
  next => contradiction

private theorem evaluatesSignedI32SubsliceIndex
    (program : Program) (before afterBase afterIndex : State)
    (values : List Int) (baseExpression indexExpression : Expr)
    (cell : CellId) (start length index : Nat) (value : Int)
    (indexBound : index < length)
    (backingBound : start + length ≤ values.length)
    (valueFound : ((values.drop start).take length)[index]? = some value)
    (baseResult : Evaluates program before baseExpression
      (.slice parserI32Type cell [] start length) afterBase)
    (indexResult : Evaluates program afterBase indexExpression
      (.signed .i32 (Int.ofNat index)) afterIndex)
    (backing : afterIndex.cellEntry? cell = some {
      id := cell
      value := some (.array (signedI32Values values))
    }) :
    Evaluates program before (.index baseExpression indexExpression)
      (.signed .i32 value) afterIndex := by
  obtain ⟨baseFuel, baseResult⟩ := baseResult
  obtain ⟨indexFuel, indexResult⟩ := indexResult
  let fuel := max baseFuel indexFuel
  have baseAtFuel := evalExpr_done_at_larger_fuel
    (Nat.le_max_left baseFuel indexFuel) baseResult
  have indexAtFuel := evalExpr_done_at_larger_fuel
    (Nat.le_max_right baseFuel indexFuel) indexResult
  refine ⟨fuel + 1, ?_⟩
  rw [evalExpr.eq_def]
  simp only
  rw [baseAtFuel]
  simp only
  rw [indexAtFuel]
  simp only
  have integerResult :
      integerIndex (.signed .i32 (Int.ofNat index)) = .ok index := by
    simp [integerIndex]
  rw [integerResult]
  simp only
  rw [if_pos indexBound]
  have sliced :
      sliceValues afterIndex cell [] start length =
        .ok (signedI32Values ((values.drop start).take length)) := by
    simp [sliceValues, readCellProjection, projectedValue, backing,
      backingBound, signedI32Values, List.map_drop, List.map_take]
  rw [sliced]
  simp only
  have valueAt :
      (signedI32Values ((values.drop start).take length))[index]? =
        some (.signed .i32 value) := by
    change
      (List.map (fun integer => Value.signed .i32 integer)
        ((values.drop start).take length))[index]? =
          some (.signed .i32 value)
    simp only [List.getElem?_map, valueFound, Option.map_some]
  rw [valueAt]

/-- Source-faithful semantics of `state_value` for any valid `i32` subslice
    and runtime integer address tuple. The model computes the same wrapped
    `i32` address as the extracted `state_word` helper, then reads through the
    slice descriptor rather than assuming a zero start or a fixed backing. -/
def evaluateGeneric (world : World) (callArguments : List Value) :
    Except Trap (Value × World) :=
  match callArguments with
  | [.slice (.scalar (.signed .i32)) cell [] start length,
      .signed .i32 base, .signed .i32 stateId, .signed .i32 field] =>
      let addressValue := parserStateWordValue verifiedParserCore.target
        base stateId field
      if addressNonnegative : 0 ≤ addressValue then
        let address := addressValue.toNat
        if addressBound : address < length then
          match world.i32Slice? cell with
          | none => .error .invalidPointer
          | some values =>
              if backingBound : start + length ≤ values.length then
                match ((values.drop start).take length)[address]? with
                | some value => .ok (.signed .i32 value, world)
                | none => .error .arrayBounds
              else .error .arrayBounds
        else .error .arrayBounds
      else .error .arrayBounds
  | _ => .error .typeMismatch

def genericCalls : CallModel where
  evaluate := fun world function callArguments =>
    if function = extractedParserStateValueFunction.id then
      evaluateGeneric world callArguments
    else
      .error .invalidPointer

theorem genericCalls_success
    {beforeWorld afterWorld : World} {function : FunctionId}
    {callArguments : List Value} {resultValue : Value}
    (evaluated : genericCalls.evaluate beforeWorld function callArguments =
      .ok (resultValue, afterWorld)) :
    ∃ cell start length base stateId field values address value,
      function = extractedParserStateValueFunction.id ∧
      callArguments = [
        .slice parserI32Type cell [] start length,
        .signed .i32 base,
        .signed .i32 stateId,
        .signed .i32 field] ∧
      parserStateWordValue verifiedParserCore.target base stateId field =
        Int.ofNat address ∧
      address < length ∧
      beforeWorld.i32Slice? cell = some values ∧
      start + length ≤ values.length ∧
      ((values.drop start).take length)[address]? = some value ∧
      resultValue = .signed .i32 value ∧
      afterWorld = beforeWorld := by
  simp only [genericCalls] at evaluated
  split at evaluated
  next functionEq =>
    simp only [evaluateGeneric] at evaluated
    split at evaluated
    next cell start length base stateId field =>
      split at evaluated
      next addressNonnegative =>
        split at evaluated
        next addressBound =>
          split at evaluated
          next => contradiction
          next values found =>
            split at evaluated
            next backingBound =>
              split at evaluated
              next value valueFound =>
                obtain ⟨rfl, rfl⟩ := evaluated
                exact ⟨cell, start, length, base, stateId, field, values,
                  (parserStateWordValue verifiedParserCore.target base stateId
                    field).toNat,
                  value, functionEq, rfl,
                  (Int.toNat_of_nonneg addressNonnegative).symm,
                  addressBound, found, backingBound, valueFound, rfl, rfl⟩
              next => contradiction
            next => contradiction
        next => contradiction
      next => contradiction
    next => contradiction
  next => contradiction

theorem genericCalls_at_valid
    (addressValue :
      parserStateWordValue verifiedParserCore.target base stateId field =
        Int.ofNat address)
    (addressBound : address < length)
    (found : world.i32Slice? cell = some values)
    (backingBound : start + length ≤ values.length)
    (valueFound : ((values.drop start).take length)[address]? = some value) :
    genericCalls.evaluate world extractedParserStateValueFunction.id [
        .slice parserI32Type cell [] start length,
        .signed .i32 base,
        .signed .i32 stateId,
        .signed .i32 field] =
      .ok (.signed .i32 value, world) := by
  have nonnegative : 0 ≤
      parserStateWordValue verifiedParserCore.target base stateId field := by
    rw [addressValue]
    exact Int.natCast_nonneg address
  simp [genericCalls, evaluateGeneric, parserI32Type, nonnegative, addressValue,
    addressBound, found, backingBound, valueFound]

/-- Every successful generic model evaluation executes the exact extracted
    `state_value` source function and preserves the caller's FunctionalView
    world, locals, and separation resources. -/
theorem genericCall_soundness :
    Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness
      verifiedParserCore genericCalls := by
  constructor
  · intro arity commandLayout localCell beforeWorld afterWorld environment
      before afterArguments function callArguments values' value argumentWrites
      afterArgumentsWellFormed represented argumentsExecution argumentsEffect
      evaluated
    obtain ⟨workspaceCell, start, length, base, stateId, field, values,
      address, element, functionEq, argumentsEq, addressValue, addressBound,
      found, backingBound, valueFound, valueEq, worldEq⟩ :=
      genericCalls_success evaluated
    subst function
    subst values'
    subst value
    subst afterWorld
    let workspaceValue : Value :=
      .slice parserI32Type workspaceCell [] start length
    let callee := parserStateValueCallee afterArguments workspaceValue
      base stateId field
    let afterWord := restoreLocals callee
      (parserStateWordCallee callee base stateId field)
    let after := parserStateValueCallState afterArguments workspaceValue
      base stateId field
    have calleeWellFormed : StateWellFormed callee :=
      parserStateValueCallee_well_formed afterArgumentsWellFormed
    let calleeEnvironment : Lanius.FunctionalView.Env 4 := fun index =>
      match index with
      | ⟨0, _⟩ => workspaceValue
      | ⟨1, _⟩ => .signed .i32 base
      | ⟨2, _⟩ => .signed .i32 stateId
      | ⟨3, _⟩ => .signed .i32 field
    have bindingsEq : parserStateValueBindings workspaceValue base stateId field =
        parameterBindings calleeEnvironment := by
      simp [parserStateValueBindings, parameterBindings, calleeEnvironment,
        List.finRange]
      rfl
    have calleeRepresented :
        Representation identityLayout (callLocalCells afterArguments)
          beforeWorld calleeEnvironment callee := by
      change Representation identityLayout (callLocalCells afterArguments)
        beforeWorld calleeEnvironment
        (enterCall afterArguments
          (parserStateValueBindings workspaceValue base stateId field))
      rw [bindingsEq]
      exact represented.enterCallParameters afterArgumentsWellFormed
    have calleeMatches : EnvironmentMatches identityLayout calleeEnvironment
        callee := calleeRepresented.environmentMatches
    have wordArguments : ArgumentsEvaluateTo verifiedParserCore callee
        [.local 1, .local 2, .local 3]
        [.signed .i32 base, .signed .i32 stateId, .signed .i32 field]
        callee :=
      ArgumentsEvaluateTo.cons
        ⟨1, evalLocal_of_local 1 verifiedParserCore callee 1 _
          (calleeMatches ⟨1, by decide⟩)⟩
        (ArgumentsEvaluateTo.cons
          ⟨1, evalLocal_of_local 1 verifiedParserCore callee 2 _
            (calleeMatches ⟨2, by decide⟩)⟩
          (ArgumentsEvaluateTo.singleton
            ⟨1, evalLocal_of_local 1 verifiedParserCore callee 3 _
              (calleeMatches ⟨3, by decide⟩)⟩))
    have wordCall : Evaluates verifiedParserCore callee
        (.call extractedParserStateWordFunction.id
          [.local 1, .local 2, .local 3])
        (.signed .i32 (Int.ofNat address)) afterWord := by
      have result := extractedParserStateWordCall_evaluates callee callee
        [.local 1, .local 2, .local 3] base stateId field calleeWellFormed
        wordArguments
      rw [addressValue] at result
      simpa [afterWord] using result
    have calleeBacking := calleeRepresented.worldOwned workspaceCell values found
    have calleeWorkspaceOld : workspaceCell < callee.nextCell :=
      StateWellFormed.cell_lt_next_of_entry calleeWellFormed calleeBacking
    have afterWordBacking : afterWord.cellEntry? workspaceCell = some {
        id := workspaceCell
        value := some (.array (signedI32Values values))
      } := by
      have nestedEffect := enterCall_effect callee
        (parserStateWordBindings base stateId field)
      have preserved := nestedEffect.restoreLocals.oldCells workspaceCell
        calleeWorkspaceOld (by simp [CellSet.empty])
      exact preserved.trans calleeBacking
    have bodyExecution : Executes verifiedParserCore callee
        extractedParserStateValueBody (.returned (some (.signed .i32 element)))
        afterWord := by
      rw [extractedParserStateValueBody_eq]
      apply executesSequenceReturned
      apply executesReturnValue
      apply evaluatesSignedI32SubsliceIndex verifiedParserCore callee callee
        afterWord values (.local 0)
        (.call extractedParserStateWordFunction.id
          [.local 1, .local 2, .local 3])
        workspaceCell start length address element addressBound backingBound
        valueFound
      · exact ⟨1, evalLocal_of_local 1 verifiedParserCore callee 0
          workspaceValue (calleeMatches ⟨0, by decide⟩)⟩
      · exact wordCall
      · exact afterWordBacking
    have callExecution : Evaluates verifiedParserCore before
        (.call extractedParserStateValueFunction.id
          (toCoreExprs commandLayout callArguments))
        (.signed .i32 element) after := by
      rw [extractedParserStateValueBody_eq] at bodyExecution
      simpa [after, parserStateValueCallState, callee, afterWord,
        workspaceValue, parserStateValueCallee, parserStateValueBindings] using
        (evaluatesCallReturned argumentsExecution
          verifiedParserCore_finds_stateValue
          (by rw [extractedParserStateValue_function_shape.2.1]; rfl)
          extractedParserStateValue_function_shape.2.2.2.1 bodyExecution)
    have afterWordWellFormed : StateWellFormed afterWord := by
      simpa [afterWord, parserStateWordCallState, parserStateWordCallee] using
        parserStateWordCallState_well_formed
          (state := callee) (base := base) (stateId := stateId)
          (field := field) calleeWellFormed
    obtain ⟨afterWellFormed, afterRepresented, callEffect⟩ :=
      represented.restoreCallLocals (calleeArity := 4)
        afterArgumentsWellFormed afterWordWellFormed (by
          have nested := parserStateWordCallState_effect
            (state := callee) (base := base) (stateId := stateId)
            (field := field)
          simpa [callee, workspaceValue, parserStateValueCallee,
            parserStateValueBindings, afterWord, parserStateWordCallState,
            parserStateWordCallee]
            using nested.weaken CellSet.empty_subset)
    exact ⟨after, CellSet.union argumentWrites CellSet.empty, callExecution,
      afterWellFormed, afterRepresented, argumentsEffect.trans callEffect⟩
  · intro beforeWorld afterWorld function callArguments value evaluated cell
    obtain ⟨workspaceCell, start, length, base, stateId, field, values,
      address, element, functionEq, argumentsEq, addressValue, addressBound,
      found, backingBound, valueFound, valueEq, worldEq⟩ :=
      genericCalls_success evaluated
    exact congrArg (fun currentWorld : World =>
      (currentWorld.i32Slice? cell).map List.length) worldEq

theorem call_soundness
    (addressValue :
      parserStateWordValue verifiedParserCore.target base stateId field =
        Int.ofNat address) :
    Lanius.FunctionalView.Core.EffectfulStateful.CallSoundness
      verifiedParserCore
      (calls values workspaceCell base stateId field address addressBound) := by
  constructor
  · intro arity commandLayout localCell beforeWorld afterWorld environment
      before afterArguments function callArguments values' value argumentWrites
      afterArgumentsWellFormed represented argumentsExecution argumentsEffect
      evaluated
    obtain ⟨functionEq, argumentsEq, found, valueEq, worldEq⟩ :=
      calls_success evaluated
    subst function
    subst values'
    subst value
    subst afterWorld
    have valueFound :
        ((values.drop 0).take values.length)[address]? =
          some (values.get ⟨address, addressBound⟩) := by
      simp [addressBound]
    have genericEvaluated := genericCalls_at_valid
      (world := beforeWorld) (cell := workspaceCell) (start := 0)
      (length := values.length) (values := values) (base := base)
      (stateId := stateId) (field := field) (address := address)
      (value := values.get ⟨address, addressBound⟩)
      addressValue addressBound found (by simp) valueFound
    simpa [result] using
      genericCall_soundness.call afterArgumentsWellFormed represented
        argumentsExecution argumentsEffect genericEvaluated
  · intro beforeWorld afterWorld function callArguments value evaluated cell
    exact congrArg (fun currentWorld : World =>
      (currentWorld.i32Slice? cell).map List.length)
      (calls_success evaluated).2.2.2.2

end StateValue

end Lanius.Extraction.ParserReads.Functional
