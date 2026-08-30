import Lanius.Extraction.VerifiedParserFind
import Lanius.FunctionalViewCoreReadOnly

namespace Lanius.Extraction.ParserAppend

open Lanius.Core
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.CallContracts
open Lanius.Compiler.Parser
open Lanius.Extraction.ParserFind

def extractedParserAppendResultWire : CoreFunction :=
  artifact_function%
    (include_str "Artifacts" / "parser.json"),
    "verified_compiler/src/verified/parser.lani",
    "append_result"

def extractedParserAppendResultFunction : Function :=
  CoreDecode.function extractedParserAppendResultWire

def extractedParserStateSeedWire : CoreFunction :=
  artifact_function%
    (include_str "Artifacts" / "parser.json"),
    "verified_compiler/src/verified/parser.lani",
    "state_seed"

def extractedParserStateSeedFunction : Function :=
  CoreDecode.function extractedParserStateSeedWire

def appendResultValue
    (status stateId stateCount : Int) (inserted : Bool) : Value :=
  .structure 2 [
    .signed .i32 status,
    .signed .i32 stateId,
    .signed .i32 stateCount,
    .boolean inserted]

def appendStatusValue : AppendStatus → Int
  | .ok => 0
  | .full => 1

def appendOutcomeValue (outcome : AppendOutcome) : Value :=
  appendResultValue (appendStatusValue outcome.status)
    (encodeStateId outcome.stateId) (Int.ofNat outcome.stateCount)
    outcome.inserted

def appendSeedFieldValue (seed : StateSeed) : Nat → Int
  | 0 => Int.ofNat seed.production
  | 1 => Int.ofNat seed.dot
  | 2 => Int.ofNat seed.origin
  | 3 => previousValue seed.previous
  | 4 => childTag seed.child
  | 5 => childPayload seed.child
  | 6 => childKind seed.child
  | _ => 0

theorem stateSeedValue_append_field
    (fieldBound : field < 7) :
    (match stateSeedValue seed with
      | .structure _ fields => fields[field]?
      | _ => none) =
      some (.signed .i32 (appendSeedFieldValue seed field)) := by
  have cases : field = 0 ∨ field = 1 ∨ field = 2 ∨ field = 3 ∨ field = 4 ∨
      field = 5 ∨ field = 6 := by omega
  rcases cases with equal | equal | equal | equal | equal | equal | equal <;>
    subst field <;> rfl

def parserStateSeedArgumentsValues (seed : StateSeed) : List Value := [
  .signed .i32 (Int.ofNat seed.production),
  .signed .i32 (Int.ofNat seed.dot),
  .signed .i32 (Int.ofNat seed.origin),
  .signed .i32 (previousValue seed.previous),
  .signed .i32 (childTag seed.child),
  .signed .i32 (childPayload seed.child),
  .signed .i32 (childKind seed.child)]

def parserStateSeedBindings (seed : StateSeed) : List (VarId × Value) :=
  [(0, .signed .i32 (Int.ofNat seed.production)),
   (1, .signed .i32 (Int.ofNat seed.dot)),
   (2, .signed .i32 (Int.ofNat seed.origin)),
   (3, .signed .i32 (previousValue seed.previous)),
   (4, .signed .i32 (childTag seed.child)),
   (5, .signed .i32 (childPayload seed.child)),
   (6, .signed .i32 (childKind seed.child))]

def parserStateSeedCallee (caller : State) (seed : StateSeed) : State :=
  enterCall caller (parserStateSeedBindings seed)

def parserStateSeedExpr : Expr :=
  .structValue 1 [
    .local 0, .local 1, .local 2, .local 3, .local 4, .local 5, .local 6]

def parserStateSeedBody : Stmt :=
  .sequence (.returnValue (some parserStateSeedExpr)) .skip

theorem extractedParserStateSeed_function_shape :
    extractedParserStateSeedFunction.id = 5 ∧
      extractedParserStateSeedFunction.parameters = [
        (0, parserI32Type), (1, parserI32Type), (2, parserI32Type),
        (3, parserI32Type), (4, parserI32Type), (5, parserI32Type),
        (6, parserI32Type)] ∧
      extractedParserStateSeedFunction.returnType = .structure 1 ∧
      extractedParserStateSeedFunction.body = some parserStateSeedBody ∧
      extractedParserStateSeedFunction.external = none := by
  exact ⟨rfl, rfl, rfl, rfl, rfl⟩

theorem verifiedParserCore_finds_stateSeed :
    verifiedParserCore.function? extractedParserStateSeedFunction.id =
      some extractedParserStateSeedFunction := by
  unfold verifiedParserCore extractedParserStateSeedFunction
    extractedParserStateSeedWire
  rfl

namespace StateSeedProof

open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly

def world : World := { i32Slice? := fun _ => none }

def environment (seed : StateSeed) : Env 7
  | ⟨0, _⟩ => .signed .i32 (Int.ofNat seed.production)
  | ⟨1, _⟩ => .signed .i32 (Int.ofNat seed.dot)
  | ⟨2, _⟩ => .signed .i32 (Int.ofNat seed.origin)
  | ⟨3, _⟩ => .signed .i32 (previousValue seed.previous)
  | ⟨4, _⟩ => .signed .i32 (childTag seed.child)
  | ⟨5, _⟩ => .signed .i32 (childPayload seed.child)
  | ⟨6, _⟩ => .signed .i32 (childKind seed.child)

theorem parameterBindings_eq (seed : StateSeed) :
    Lanius.FunctionalView.Core.parameterBindings (environment seed) =
      parserStateSeedBindings seed := by
  apply List.ext_getElem
  · simp [parserStateSeedBindings]
  · intro index leftBound rightBound
    have alternatives : index = 0 ∨ index = 1 ∨ index = 2 ∨ index = 3 ∨
        index = 4 ∨ index = 5 ∨ index = 6 := by
      simp [parserStateSeedBindings] at rightBound
      omega
    rcases alternatives with rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
      simp [Lanius.FunctionalView.Core.parameterBindings_getElem,
        parserStateSeedBindings, environment]

private def resultTerm : Term Lanius.FunctionalView.Core.signature 7 :=
  .apply (.structValue 1 (List.replicate 7 parserI32Type)) [
    .reference (.slot ⟨0, by omega⟩),
    .reference (.slot ⟨1, by omega⟩),
    .reference (.slot ⟨2, by omega⟩),
    .reference (.slot ⟨3, by omega⟩),
    .reference (.slot ⟨4, by omega⟩),
    .reference (.slot ⟨5, by omega⟩),
    .reference (.slot ⟨6, by omega⟩)]

def body : Block Lanius.FunctionalView.Core.signature 7 :=
  .sequence (.returnValue (some resultTerm)) .skip

theorem body_toCore_exactly :
    toCoreStmt (identityLayout (arity := 7)) 7 body =
      parserStateSeedBody := by
  rfl

theorem evaluates (seed : StateSeed) :
    Block.evaluate (machine verifiedParserCore) world (environment seed) body =
      .done (.returned (some (stateSeedValue seed))) world := by
  rfl

theorem world_represents (state : State) : World.Represents world state := by
  intro _ _ found
  simp [world] at found

end StateSeedProof

/-- Store-pure contract for the extracted seven-field `state_seed`
    constructor. This is shared by every `append_state` site in the
    recognizer, rather than reproving its fresh call-local allocations in each
    Earley transition. -/
theorem extractedParserStateSeedCall_contract
    (before afterArguments : State) (arguments : List Expr)
    (seed : StateSeed)
    (afterArgumentsWellFormed : StateWellFormed afterArguments)
    (argumentsResult : ArgumentsEvaluateTo verifiedParserCore before arguments
      (parserStateSeedArgumentsValues seed) afterArguments) :
    let after := restoreLocals afterArguments
      (parserStateSeedCallee afterArguments seed)
    Evaluates verifiedParserCore before
      (.call extractedParserStateSeedFunction.id arguments)
      (stateSeedValue seed) after ∧
    ModifiesOnly CellSet.empty afterArguments after ∧
    StateWellFormed after := by
  let bindings := parserStateSeedBindings seed
  let callee := parserStateSeedCallee afterArguments seed
  let after := restoreLocals afterArguments callee
  have calleeWellFormed : StateWellFormed callee := by
    simpa [callee, parserStateSeedCallee, bindings,
      parserStateSeedBindings] using
      (enterCall_preserves_wellFormed
        (bindings := bindings) afterArgumentsWellFormed)
  have environmentMatches :
      Lanius.FunctionalView.Core.EnvironmentMatches
        (Lanius.FunctionalView.Core.identityLayout (arity := 7))
        (StateSeedProof.environment seed) callee := by
    simpa [callee, parserStateSeedCallee, bindings,
      StateSeedProof.parameterBindings_eq] using
      (Lanius.FunctionalView.Core.enterCall_parameterBindings_matches
        (environment := StateSeedProof.environment seed)
        afterArgumentsWellFormed)
  have functionalBodyResult : Executes verifiedParserCore callee
      parserStateSeedBody (.returned (some (stateSeedValue seed))) callee := by
    have sound := Lanius.FunctionalView.Core.block_executes_without_locals
      (nextLocal := 7)
      (Lanius.FunctionalView.Core.ReadOnly.bridge verifiedParserCore)
      (StateSeedProof.world_represents callee) environmentMatches (by rfl)
      (StateSeedProof.evaluates seed)
    rw [StateSeedProof.body_toCore_exactly] at sound
    exact sound.1
  have evaluation : Evaluates verifiedParserCore before
      (.call extractedParserStateSeedFunction.id arguments)
      (stateSeedValue seed) after := by
    apply evaluatesCallReturned (body := parserStateSeedBody)
      argumentsResult verifiedParserCore_finds_stateSeed
    · rw [extractedParserStateSeed_function_shape.2.1]
      rfl
    · exact extractedParserStateSeed_function_shape.2.2.2.1
    · simpa [after, callee, parserStateSeedCallee, bindings,
        parserStateSeedBindings, parserStateSeedArgumentsValues] using
        functionalBodyResult
  have entered : StoreEffect CellSet.empty afterArguments callee := by
    simpa [callee, parserStateSeedCallee, bindings,
      parserStateSeedBindings] using enterCall_effect afterArguments bindings
  have effect : ModifiesOnly CellSet.empty afterArguments after := by
    simpa [after] using entered.restoreLocals
  have afterWellFormed : StateWellFormed after :=
    entered.restoreLocals_wellFormed afterArgumentsWellFormed calleeWellFormed
  exact ⟨evaluation, effect, afterWellFormed⟩

theorem verifiedParser_append_status_constants :
    verifiedParserCore.constant? 40 = some {
      id := 40
      type := parserI32Type
      value := .signed .i32 0
    } ∧
    verifiedParserCore.constant? 41 = some {
      id := 41
      type := parserI32Type
      value := .signed .i32 1
    } := by
  exact ⟨rfl, rfl⟩

theorem verifiedParser_append_write_constants :
    verifiedParserCore.constant? 28 = some {
      id := 28, type := parserI32Type, value := .signed .i32 0
    } ∧
    verifiedParserCore.constant? 29 = some {
      id := 29, type := parserI32Type, value := .signed .i32 1
    } ∧
    verifiedParserCore.constant? 30 = some {
      id := 30, type := parserI32Type, value := .signed .i32 2
    } ∧
    verifiedParserCore.constant? 31 = some {
      id := 31, type := parserI32Type, value := .signed .i32 3
    } ∧
    verifiedParserCore.constant? 32 = some {
      id := 32, type := parserI32Type, value := .signed .i32 4
    } ∧
    verifiedParserCore.constant? 33 = some {
      id := 33, type := parserI32Type, value := .signed .i32 5
    } ∧
    verifiedParserCore.constant? 34 = some {
      id := 34, type := parserI32Type, value := .signed .i32 6
    } ∧
    verifiedParserCore.constant? 35 = some {
      id := 35, type := parserI32Type, value := .signed .i32 7
    } ∧
    verifiedParserCore.constant? 36 = some {
      id := 36, type := parserI32Type, value := .signed .i32 8
    } := by
  exact ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩

theorem verifiedParser_append_chart_constants :
    verifiedParserCore.constant? 25 = some {
      id := 25, type := parserI32Type, value := .signed .i32 0
    } ∧
    verifiedParserCore.constant? 26 = some {
      id := 26, type := parserI32Type, value := .signed .i32 1
    } := by
  exact ⟨rfl, rfl⟩

def parserAppendResultExpr : Expr :=
  .structValue 2 [.local 0, .local 1, .local 2, .local 3]

def parserAppendResultBody : Stmt :=
  .sequence (.returnValue (some parserAppendResultExpr)) .skip

theorem extractedParserAppendResult_function_shape :
    extractedParserAppendResultFunction.id = 6 ∧
      extractedParserAppendResultFunction.parameters = [
        (0, parserI32Type), (1, parserI32Type), (2, parserI32Type),
        (3, .scalar .bool)] ∧
      extractedParserAppendResultFunction.returnType = .structure 2 ∧
      extractedParserAppendResultFunction.body = some parserAppendResultBody ∧
      extractedParserAppendResultFunction.external = none := by
  exact ⟨rfl, rfl, rfl, rfl, rfl⟩

theorem verifiedParserCore_finds_appendResult :
    verifiedParserCore.function? extractedParserAppendResultFunction.id =
      some extractedParserAppendResultFunction := by
  unfold verifiedParserCore extractedParserAppendResultFunction
    extractedParserAppendResultWire
  rfl

namespace AppendResultProof

open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly

def world : World := { i32Slice? := fun _ => none }

def environment
    (status stateId stateCount : Int) (inserted : Bool) : Env 4
  | ⟨0, _⟩ => .signed .i32 status
  | ⟨1, _⟩ => .signed .i32 stateId
  | ⟨2, _⟩ => .signed .i32 stateCount
  | ⟨3, _⟩ => .boolean inserted

private def resultTerm : Term Lanius.FunctionalView.Core.signature 4 :=
  .apply (.structValue 2 [
      parserI32Type, parserI32Type, parserI32Type, .scalar .bool]) [
    .reference (.slot ⟨0, by omega⟩),
    .reference (.slot ⟨1, by omega⟩),
    .reference (.slot ⟨2, by omega⟩),
    .reference (.slot ⟨3, by omega⟩)]

def body : Block Lanius.FunctionalView.Core.signature 4 :=
  .sequence (.returnValue (some resultTerm)) .skip

theorem body_toCore_exactly :
    toCoreStmt (identityLayout (arity := 4)) 4 body =
      parserAppendResultBody := by
  rfl

theorem evaluates
    (status stateId stateCount : Int) (inserted : Bool) :
    Block.evaluate (machine verifiedParserCore) world
        (environment status stateId stateCount inserted) body =
      .done (.returned (some
        (appendResultValue status stateId stateCount inserted))) world := by
  rfl

theorem world_represents (state : State) : World.Represents world state := by
  intro _ _ found
  simp [world] at found

end AppendResultProof

theorem extractedParserAppendState_function_signature :
    extractedParserAppendStateFunction.id = 13 ∧
      extractedParserAppendStateFunction.parameters = [
        (0, .slice parserI32Type),
        (1, parserI32Type),
        (2, parserI32Type),
        (3, parserI32Type),
        (4, .structure 1),
        (5, parserI32Type)] ∧
      extractedParserAppendStateFunction.returnType = .structure 2 ∧
      extractedParserAppendStateFunction.body.isSome = true ∧
      extractedParserAppendStateFunction.external = none := by
  exact ⟨rfl, rfl, rfl, rfl, rfl⟩

theorem verifiedParserCore_finds_appendState :
    verifiedParserCore.function? extractedParserAppendStateFunction.id =
      some extractedParserAppendStateFunction := by
  unfold verifiedParserCore extractedParserAppendStateFunction
    extractedParserAppendStateWire
  rfl

def parserAppendFindExpr : Expr :=
  .call extractedParserFindStateFunction.id
    [.local 0, .local 1, .local 3, .local 4]

def parserAppendResultCall
    (status stateId stateCount inserted : Expr) : Expr :=
  .call extractedParserAppendResultFunction.id
    [status, stateId, stateCount, inserted]

def parserAppendExistingIf : Stmt :=
  .ifThenElse
    (.binary .greaterEqual (.local 6) (.value (.signed .i32 0)))
    (.sequence
      (.returnValue (some (parserAppendResultCall
        (.constant 40) (.local 6) (.local 5) (.value (.boolean false)))))
      .skip)
    .skip

def parserAppendFullIf : Stmt :=
  .ifThenElse
    (.binary .greaterEqual (.local 5) (.local 2))
    (.sequence
      (.returnValue (some (parserAppendResultCall
        (.constant 41)
        (.unary .negate (.value (.signed .i32 1)))
        (.local 5) (.value (.boolean false)))))
      .skip)
    .skip

def parserAppendStateWrite (fieldConstant : ConstantId) (value : Expr) : Stmt :=
  .expression (.assign .set
    (.index (.local 0)
      (.call extractedParserStateWordFunction.id
        [.local 1, .local 7, .constant fieldConstant]))
    value)

def parserAppendLinkChart : Stmt :=
  .sequence
    (.ifThenElse
      (.binary .less (.local 10) (.value (.signed .i32 0)))
      (.sequence
        (.expression (.assign .set
          (.index (.local 0) (.local 8)) (.local 7)))
        .skip)
      (.sequence
        (.expression (.assign .set
          (.index (.local 0)
            (.call extractedParserStateWordFunction.id
              [.local 1, .local 10, .constant 32]))
          (.local 7)))
        .skip))
    (.sequence
      (.expression (.assign .set
        (.index (.local 0) (.local 9)) (.local 7)))
      (.sequence
        (.returnValue (some (parserAppendResultCall
          (.constant 40) (.local 7)
          (.binary .add (.local 5) (.value (.signed .i32 1)))
          (.value (.boolean true)))))
        .skip))

def parserAppendChartWords : Stmt :=
  .letLocal 8 parserI32Type
    (.call extractedParserChartWordFunction.id [.local 3, .constant 25])
    (.letLocal 9 parserI32Type
      (.call extractedParserChartWordFunction.id [.local 3, .constant 26])
      (.letLocal 10 parserI32Type
        (.index (.local 0) (.local 9))
        parserAppendLinkChart))

def parserAppendStateWrites (tail : Stmt) : Stmt :=
  .sequence (parserAppendStateWrite 28 (.field (.local 4) 0))
    (.sequence (parserAppendStateWrite 29 (.field (.local 4) 1))
      (.sequence (parserAppendStateWrite 30 (.field (.local 4) 2))
        (.sequence (parserAppendStateWrite 31 (.local 3))
          (.sequence (parserAppendStateWrite 32
              (.unary .negate (.value (.signed .i32 1))))
            (.sequence (parserAppendStateWrite 33 (.field (.local 4) 3))
              (.sequence (parserAppendStateWrite 34 (.field (.local 4) 4))
                (.sequence
                  (parserAppendStateWrite 35 (.field (.local 4) 5))
                  (.sequence
                    (parserAppendStateWrite 36 (.field (.local 4) 6))
                    tail))))))))

def parserAppendInsertBody : Stmt :=
  .letLocal 7 parserI32Type (.local 5)
    (parserAppendStateWrites parserAppendChartWords)

def parserAppendStateBody : Stmt :=
  .letLocal 6 parserI32Type parserAppendFindExpr
    (.sequence parserAppendExistingIf
      (.sequence parserAppendFullIf parserAppendInsertBody))

theorem extractedParserAppendState_body_eq :
    extractedParserAppendStateFunction.body = some parserAppendStateBody := by
  rfl

structure AppendEntryInvariant
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (values : List Int) (workspaceCell : CellId)
    (position : Nat) (seed : StateSeed) (runtime : State) where
  valuesLength : values.length = layout.workspaceLength
  encoded : EncodesWorkspace layout workspace (listWords values)
  positionBound : position ≤ finalPosition layout.tokenCount
  seedOriginBound : seed.origin ≤ finalPosition layout.tokenCount
  wellFormed : StateWellFormed runtime
  workspaceLocal : runtime.local? 0 = some
    (workspaceValue values workspaceCell)
  baseLocal : runtime.local? 1 = some
    (.signed .i32 (Int.ofNat (stateBase layout.tokenCount)))
  capacityLocal : runtime.local? 2 = some
    (.signed .i32 (Int.ofNat layout.capacity))
  positionLocal : runtime.local? 3 = some
    (.signed .i32 (Int.ofNat position))
  seedLocal : runtime.local? 4 = some (stateSeedValue seed)
  stateCountLocal : runtime.local? 5 = some
    (.signed .i32 (Int.ofNat workspace.states.length))
  backing : runtime.cellEntry? workspaceCell = some {
    id := workspaceCell
    value := some (.array (signedI32Values values))
  }

theorem AppendEntryInvariant.after_empty_effect
    (invariant : AppendEntryInvariant layout workspace values workspaceCell
      position seed before)
    (effect : ModifiesOnly CellSet.empty before after)
    (afterWellFormed : StateWellFormed after) :
    AppendEntryInvariant layout workspace values workspaceCell position seed
      after := {
  valuesLength := invariant.valuesLength
  encoded := invariant.encoded
  positionBound := invariant.positionBound
  seedOriginBound := invariant.seedOriginBound
  wellFormed := afterWellFormed
  workspaceLocal := effect.empty_preserves_local invariant.wellFormed
    invariant.workspaceLocal
  baseLocal := effect.empty_preserves_local invariant.wellFormed
    invariant.baseLocal
  capacityLocal := effect.empty_preserves_local invariant.wellFormed
    invariant.capacityLocal
  positionLocal := effect.empty_preserves_local invariant.wellFormed
    invariant.positionLocal
  seedLocal := effect.empty_preserves_local invariant.wellFormed
    invariant.seedLocal
  stateCountLocal := effect.empty_preserves_local invariant.wellFormed
    invariant.stateCountLocal
  backing := effect.empty_preserves_entry invariant.wellFormed
    invariant.backing
}

theorem AppendEntryInvariant.after_bind_local
    (invariant : AppendEntryInvariant layout workspace values workspaceCell
      position seed runtime)
    (id : VarId) (value : Value)
    (not0 : id ≠ 0) (not1 : id ≠ 1) (not2 : id ≠ 2)
    (not3 : id ≠ 3) (not4 : id ≠ 4) (not5 : id ≠ 5) :
    AppendEntryInvariant layout workspace values workspaceCell position seed
      (runtime.bindLocal id value) := {
  valuesLength := invariant.valuesLength
  encoded := invariant.encoded
  positionBound := invariant.positionBound
  seedOriginBound := invariant.seedOriginBound
  wellFormed := bindLocal_preserves_well_formed runtime id value
    invariant.wellFormed
  workspaceLocal :=
    (bindLocal_preserves_other_local invariant.wellFormed not0).trans
      invariant.workspaceLocal
  baseLocal :=
    (bindLocal_preserves_other_local invariant.wellFormed not1).trans
      invariant.baseLocal
  capacityLocal :=
    (bindLocal_preserves_other_local invariant.wellFormed not2).trans
      invariant.capacityLocal
  positionLocal :=
    (bindLocal_preserves_other_local invariant.wellFormed not3).trans
      invariant.positionLocal
  seedLocal :=
    (bindLocal_preserves_other_local invariant.wellFormed not4).trans
      invariant.seedLocal
  stateCountLocal :=
    (bindLocal_preserves_other_local invariant.wellFormed not5).trans
      invariant.stateCountLocal
  backing := by
    have old := Lanius.Separation.StateWellFormed.cell_lt_next_of_entry
      invariant.wellFormed invariant.backing
    exact (bindLocal_effect runtime id value).oldCells workspaceCell old
      (by simp [CellSet.empty]) |>.trans invariant.backing
}

/-- The insertion branch has crossed the two read-only guards and bound the
    dense ID of the new state.  From here on, every source statement either
    performs a read-only address calculation or mutates the one workspace
    backing cell. -/
structure AppendMutationInvariant
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (values : List Int) (workspaceCell : CellId)
    (position : Nat) (seed : StateSeed) (runtime : State) where
  valuesLength : values.length = layout.workspaceLength
  stateIdBound : workspace.states.length < layout.capacity
  positionBound : position ≤ finalPosition layout.tokenCount
  wellFormed : StateWellFormed runtime
  workspaceLocal : runtime.local? 0 = some
    (workspaceValue values workspaceCell)
  baseLocal : runtime.local? 1 = some
    (.signed .i32 (Int.ofNat (stateBase layout.tokenCount)))
  positionLocal : runtime.local? 3 = some
    (.signed .i32 (Int.ofNat position))
  seedLocal : runtime.local? 4 = some (stateSeedValue seed)
  stateCountLocal : runtime.local? 5 = some
    (.signed .i32 (Int.ofNat workspace.states.length))
  stateIdLocal : runtime.local? 7 = some
    (.signed .i32 (Int.ofNat workspace.states.length))
  backing : runtime.cellEntry? workspaceCell = some {
    id := workspaceCell
    value := some (.array (signedI32Values values))
  }

theorem AppendMutationInvariant.after_empty_effect
    (invariant : AppendMutationInvariant layout workspace values workspaceCell
      position seed before)
    (effect : ModifiesOnly CellSet.empty before after)
    (afterWellFormed : StateWellFormed after) :
    AppendMutationInvariant layout workspace values workspaceCell position seed
      after := {
  valuesLength := invariant.valuesLength
  stateIdBound := invariant.stateIdBound
  positionBound := invariant.positionBound
  wellFormed := afterWellFormed
  workspaceLocal := effect.empty_preserves_local invariant.wellFormed
    invariant.workspaceLocal
  baseLocal := effect.empty_preserves_local invariant.wellFormed
    invariant.baseLocal
  positionLocal := effect.empty_preserves_local invariant.wellFormed
    invariant.positionLocal
  seedLocal := effect.empty_preserves_local invariant.wellFormed
    invariant.seedLocal
  stateCountLocal := effect.empty_preserves_local invariant.wellFormed
    invariant.stateCountLocal
  stateIdLocal := effect.empty_preserves_local invariant.wellFormed
    invariant.stateIdLocal
  backing := effect.empty_preserves_entry invariant.wellFormed
    invariant.backing
}

theorem AppendMutationInvariant.after_workspace_write
    (invariant : AppendMutationInvariant layout workspace values workspaceCell
      position seed before)
    (index : Nat) (replacement : Int) (after : State)
    (effect : ModifiesOnly (CellSet.singleton workspaceCell) before after)
    (afterWellFormed : StateWellFormed after)
    (afterBacking : after.cellEntry? workspaceCell = some {
      id := workspaceCell
      value := some (.array
        (signedI32Values (setI32Value values index replacement)))
    }) :
    AppendMutationInvariant layout workspace
      (setI32Value values index replacement) workspaceCell position seed after := {
  valuesLength := by simpa using invariant.valuesLength
  stateIdBound := invariant.stateIdBound
  positionBound := invariant.positionBound
  wellFormed := afterWellFormed
  workspaceLocal := by
    simpa [workspaceValue] using
      effect.singleton_preserves_local_of_ne invariant.wellFormed
        invariant.workspaceLocal invariant.backing (by
          intro impossible
          cases impossible)
  baseLocal := effect.singleton_preserves_local_of_ne invariant.wellFormed
    invariant.baseLocal invariant.backing (by simp)
  positionLocal := effect.singleton_preserves_local_of_ne invariant.wellFormed
    invariant.positionLocal invariant.backing (by simp)
  seedLocal := effect.singleton_preserves_local_of_ne invariant.wellFormed
    invariant.seedLocal invariant.backing (by simp [stateSeedValue])
  stateCountLocal := effect.singleton_preserves_local_of_ne invariant.wellFormed
    invariant.stateCountLocal invariant.backing (by simp)
  stateIdLocal := effect.singleton_preserves_local_of_ne invariant.wellFormed
    invariant.stateIdLocal invariant.backing (by simp)
  backing := afterBacking
}

theorem AppendMutationInvariant.after_bind_local
    (invariant : AppendMutationInvariant layout workspace values workspaceCell
      position seed runtime)
    (id : VarId) (value : Value)
    (not0 : id ≠ 0) (not1 : id ≠ 1) (not3 : id ≠ 3)
    (not4 : id ≠ 4) (not5 : id ≠ 5) (not7 : id ≠ 7) :
    AppendMutationInvariant layout workspace values workspaceCell position seed
      (runtime.bindLocal id value) := {
  valuesLength := invariant.valuesLength
  stateIdBound := invariant.stateIdBound
  positionBound := invariant.positionBound
  wellFormed := bindLocal_preserves_well_formed runtime id value
    invariant.wellFormed
  workspaceLocal :=
    (bindLocal_preserves_other_local invariant.wellFormed not0).trans
      invariant.workspaceLocal
  baseLocal :=
    (bindLocal_preserves_other_local invariant.wellFormed not1).trans
      invariant.baseLocal
  positionLocal :=
    (bindLocal_preserves_other_local invariant.wellFormed not3).trans
      invariant.positionLocal
  seedLocal :=
    (bindLocal_preserves_other_local invariant.wellFormed not4).trans
      invariant.seedLocal
  stateCountLocal :=
    (bindLocal_preserves_other_local invariant.wellFormed not5).trans
      invariant.stateCountLocal
  stateIdLocal :=
    (bindLocal_preserves_other_local invariant.wellFormed not7).trans
      invariant.stateIdLocal
  backing := by
    have old := Lanius.Separation.StateWellFormed.cell_lt_next_of_entry
      invariant.wellFormed invariant.backing
    exact (bindLocal_effect runtime id value).oldCells workspaceCell old
      (by simp [CellSet.empty]) |>.trans invariant.backing
}

structure AppendStateWriteExecution
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (values : List Int) (workspaceCell : CellId)
    (position : Nat) (seed : StateSeed) (runtime : State)
    (invariant : AppendMutationInvariant layout workspace values workspaceCell
      position seed runtime)
    (fieldConstant : ConstantId) (field : Nat)
    (right : Expr) (replacement : Int) where
  after : State
  execution : Executes verifiedParserCore runtime
    (parserAppendStateWrite fieldConstant right) .next after
  effect : ModifiesOnly (CellSet.singleton workspaceCell) runtime after
  invariant : AppendMutationInvariant layout workspace
    (setI32Value values
      (stateWord (stateBase layout.tokenCount) workspace.states.length field)
      replacement) workspaceCell position seed after

structure AppendWorkspaceWriteExecution
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (values : List Int) (workspaceCell : CellId)
    (position : Nat) (seed : StateSeed) (runtime : State)
    (invariant : AppendMutationInvariant layout workspace values workspaceCell
      position seed runtime)
    (statement : Stmt) (index : Nat) (replacement : Int) where
  after : State
  execution : Executes verifiedParserCore runtime statement .next after
  effect : ModifiesOnly (CellSet.singleton workspaceCell) runtime after
  invariant : AppendMutationInvariant layout workspace
    (setI32Value values index replacement) workspaceCell position seed after

noncomputable def AppendMutationInvariant.write_state_id_at_local_index
    (invariant : AppendMutationInvariant layout workspace values workspaceCell
      position seed runtime)
    (indexLocal : VarId) (index : Nat)
    (indexBound : index < values.length)
    (indexFound : runtime.local? indexLocal = some
      (.signed .i32 (Int.ofNat index))) :
    AppendWorkspaceWriteExecution layout workspace values workspaceCell position
      seed runtime invariant
      (.expression (.assign .set
        (.index (.local 0) (.local indexLocal)) (.local 7)))
      index workspace.states.length := by
  have indexResult : Evaluates verifiedParserCore runtime (.local indexLocal)
      (.signed .i32 (Int.ofNat index)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime indexLocal
      (.signed .i32 (Int.ofNat index)) indexFound⟩
  have rightResult : Evaluates verifiedParserCore runtime (.local 7)
      (.signed .i32 (Int.ofNat workspace.states.length)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 7
      (.signed .i32 (Int.ofNat workspace.states.length))
      invariant.stateIdLocal⟩
  have write := evaluatesSetSignedI32SliceIndexFromEmpty verifiedParserCore
    runtime runtime runtime values 0 (.local indexLocal) (.local 7)
    workspaceCell index (Int.ofNat workspace.states.length) indexBound
    invariant.workspaceLocal indexResult invariant.wellFormed
    (ModifiesOnly.refl runtime) rightResult invariant.wellFormed
    (ModifiesOnly.refl runtime) invariant.backing
  let after := Classical.choose write
  have facts := Classical.choose_spec write
  exact {
    after := after
    execution := executesExpression facts.1
    effect := facts.2.2.2
    invariant := invariant.after_workspace_write index
      (Int.ofNat workspace.states.length) after facts.2.2.2 facts.2.1
      facts.2.2.1
  }

noncomputable def AppendMutationInvariant.write_tail_next
    (invariant : AppendMutationInvariant layout workspace values workspaceCell
      position seed runtime)
    (tail : Nat) (tailBound : tail < layout.capacity)
    (tailLocal : runtime.local? 10 = some
      (.signed .i32 (Int.ofNat tail))) :
    AppendWorkspaceWriteExecution layout workspace values workspaceCell position
      seed runtime invariant
      (.expression (.assign .set
        (.index (.local 0)
          (.call extractedParserStateWordFunction.id
            [.local 1, .local 10, .constant 32]))
        (.local 7)))
      (stateWord (stateBase layout.tokenCount) tail 4)
      workspace.states.length := by
  let address := stateWord (stateBase layout.tokenCount) tail 4
  let afterIndex := parserStateWordCallState runtime
    (Int.ofNat (stateBase layout.tokenCount)) (Int.ofNat tail) 4
  have baseArgument : Evaluates verifiedParserCore runtime (.local 1)
      (.signed .i32 (Int.ofNat (stateBase layout.tokenCount))) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 1
      (.signed .i32 (Int.ofNat (stateBase layout.tokenCount)))
      invariant.baseLocal⟩
  have tailArgument : Evaluates verifiedParserCore runtime (.local 10)
      (.signed .i32 (Int.ofNat tail)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 10
      (.signed .i32 (Int.ofNat tail)) tailLocal⟩
  have fieldArgument : Evaluates verifiedParserCore runtime (.constant 32)
      (.signed .i32 4) runtime := by
    refine ⟨2, ?_⟩
    simp [evalExpr, verifiedParser_append_write_constants.2.2.2.2.1]
  have arguments : ArgumentsEvaluateTo verifiedParserCore runtime
      [.local 1, .local 10, .constant 32] [
        .signed .i32 (Int.ofNat (stateBase layout.tokenCount)),
        .signed .i32 (Int.ofNat tail), .signed .i32 4] runtime :=
    ArgumentsEvaluateTo.cons baseArgument
      (ArgumentsEvaluateTo.cons tailArgument
        (ArgumentsEvaluateTo.singleton fieldArgument))
  have indexResult : Evaluates verifiedParserCore runtime
      (.call extractedParserStateWordFunction.id
        [.local 1, .local 10, .constant 32])
      (.signed .i32 (Int.ofNat address)) afterIndex := by
    have call := extractedParserStateWordCall_evaluates runtime runtime
      [.local 1, .local 10, .constant 32]
      (Int.ofNat (stateBase layout.tokenCount)) (Int.ofNat tail) 4
      invariant.wellFormed arguments
    have addressValue := layout.state_value_eq_address
      (stateId := tail) (field := 4) tailBound (by decide)
    have addressValue' :
        parserStateWordValue verifiedParserCore.target
          (Int.ofNat (stateBase layout.tokenCount)) (Int.ofNat tail) 4 =
          Int.ofNat (stateWord (stateBase layout.tokenCount) tail 4) := by
      simpa using addressValue
    rw [addressValue'] at call
    simpa [afterIndex, address, parserStateWordCallState] using call
  have indexEffect : ModifiesOnly CellSet.empty runtime afterIndex := by
    simpa [afterIndex] using
      (parserStateWordCallState_effect (state := runtime)
        (base := Int.ofNat (stateBase layout.tokenCount))
        (stateId := Int.ofNat tail) (field := 4))
  have indexWellFormed : StateWellFormed afterIndex :=
    parserStateWordCallState_well_formed invariant.wellFormed
  have afterIndexInvariant := invariant.after_empty_effect indexEffect
    indexWellFormed
  have rightResult : Evaluates verifiedParserCore afterIndex (.local 7)
      (.signed .i32 (Int.ofNat workspace.states.length)) afterIndex :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore afterIndex 7
      (.signed .i32 (Int.ofNat workspace.states.length))
      afterIndexInvariant.stateIdLocal⟩
  have addressBound : address < values.length := by
    rw [invariant.valuesLength]
    exact layout.state_address_valid tailBound (by decide)
  have write := evaluatesSetSignedI32SliceIndexFromEmpty verifiedParserCore
    runtime afterIndex afterIndex values 0
    (.call extractedParserStateWordFunction.id
      [.local 1, .local 10, .constant 32])
    (.local 7) workspaceCell address (Int.ofNat workspace.states.length)
    addressBound invariant.workspaceLocal indexResult indexWellFormed indexEffect
    rightResult indexWellFormed (ModifiesOnly.refl afterIndex)
    afterIndexInvariant.backing
  let after := Classical.choose write
  have facts := Classical.choose_spec write
  exact {
    after := after
    execution := by simpa using executesExpression facts.1
    effect := facts.2.2.2
    invariant := by
      simpa [address] using invariant.after_workspace_write address
        (Int.ofNat workspace.states.length) after facts.2.2.2 facts.2.1
        facts.2.2.1
  }

structure AppendChartAddressRead
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (values : List Int) (workspaceCell : CellId)
    (position : Nat) (seed : StateSeed) (runtime : State)
    (invariant : AppendMutationInvariant layout workspace values workspaceCell
      position seed runtime)
    (fieldConstant : ConstantId) (field : Nat) where
  after : State
  evaluation : Evaluates verifiedParserCore runtime
    (.call extractedParserChartWordFunction.id
      [.local 3, .constant fieldConstant])
    (.signed .i32 (Int.ofNat (chartWord position field))) after
  effect : ModifiesOnly CellSet.empty runtime after
  invariant : AppendMutationInvariant layout workspace values workspaceCell
    position seed after

noncomputable def AppendMutationInvariant.read_chart_address
    (invariant : AppendMutationInvariant layout workspace values workspaceCell
      position seed runtime)
    (fieldConstant : ConstantId) (field : Nat)
    (fieldBound : field < chartWords)
    (constantFound : verifiedParserCore.constant? fieldConstant = some {
      id := fieldConstant
      type := parserI32Type
      value := .signed .i32 (Int.ofNat field)
    }) :
    AppendChartAddressRead layout workspace values workspaceCell position seed
      runtime invariant fieldConstant field := by
  have positionArgument : Evaluates verifiedParserCore runtime (.local 3)
      (.signed .i32 (Int.ofNat position)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 3
      (.signed .i32 (Int.ofNat position)) invariant.positionLocal⟩
  have fieldArgument : Evaluates verifiedParserCore runtime
      (.constant fieldConstant) (.signed .i32 (Int.ofNat field)) runtime := by
    refine ⟨2, ?_⟩
    simp [evalExpr, constantFound]
  have arguments : ArgumentsEvaluateTo verifiedParserCore runtime
      [.local 3, .constant fieldConstant]
      [.signed .i32 (Int.ofNat position), .signed .i32 (Int.ofNat field)]
      runtime := ArgumentsEvaluateTo.cons positionArgument
        (ArgumentsEvaluateTo.singleton fieldArgument)
  let after := parserChartWordCallState runtime (Int.ofNat position)
    (Int.ofNat field)
  have evaluation : Evaluates verifiedParserCore runtime
      (.call extractedParserChartWordFunction.id
        [.local 3, .constant fieldConstant])
      (.signed .i32 (Int.ofNat (chartWord position field))) after := by
    have call := extractedParserChartWordCall_evaluates runtime runtime
      [.local 3, .constant fieldConstant] (Int.ofNat position)
      (Int.ofNat field) invariant.wellFormed arguments
    rw [layout.chart_value_eq_address invariant.positionBound fieldBound] at call
    simpa [after, parserChartWordCallState] using call
  have effect : ModifiesOnly CellSet.empty runtime after := by
    simpa [after] using
      (parserChartWordCallState_effect (state := runtime)
        (position := Int.ofNat position) (field := Int.ofNat field))
  have wellFormed : StateWellFormed after :=
    parserChartWordCallState_well_formed invariant.wellFormed
  exact {
    after := after
    evaluation := evaluation
    effect := effect
    invariant := invariant.after_empty_effect effect wellFormed
  }

noncomputable def AppendMutationInvariant.write_state_field
    (invariant : AppendMutationInvariant layout workspace values workspaceCell
      position seed runtime)
    (fieldConstant : ConstantId) (field : Nat)
    (fieldBound : field < stateWords)
    (constantFound : verifiedParserCore.constant? fieldConstant = some {
      id := fieldConstant
      type := parserI32Type
      value := .signed .i32 (Int.ofNat field)
    })
    (right : Expr) (replacement : Int)
    (rightResult :
      let afterIndex := parserStateWordCallState runtime
        (Int.ofNat (stateBase layout.tokenCount))
        (Int.ofNat workspace.states.length) (Int.ofNat field)
      Evaluates verifiedParserCore afterIndex right
        (.signed .i32 replacement) afterIndex) :
    AppendStateWriteExecution layout workspace values workspaceCell position seed
      runtime invariant fieldConstant field right replacement := by
  let address := stateWord (stateBase layout.tokenCount)
    workspace.states.length field
  let afterIndex := parserStateWordCallState runtime
    (Int.ofNat (stateBase layout.tokenCount))
    (Int.ofNat workspace.states.length) (Int.ofNat field)
  have baseArgument : Evaluates verifiedParserCore runtime (.local 1)
      (.signed .i32 (Int.ofNat (stateBase layout.tokenCount))) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 1
      (.signed .i32 (Int.ofNat (stateBase layout.tokenCount)))
      invariant.baseLocal⟩
  have stateIdArgument : Evaluates verifiedParserCore runtime (.local 7)
      (.signed .i32 (Int.ofNat workspace.states.length)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 7
      (.signed .i32 (Int.ofNat workspace.states.length))
      invariant.stateIdLocal⟩
  have fieldArgument : Evaluates verifiedParserCore runtime
      (.constant fieldConstant) (.signed .i32 (Int.ofNat field)) runtime := by
    refine ⟨2, ?_⟩
    simp [evalExpr, constantFound]
  have arguments : ArgumentsEvaluateTo verifiedParserCore runtime
      [.local 1, .local 7, .constant fieldConstant] [
        .signed .i32 (Int.ofNat (stateBase layout.tokenCount)),
        .signed .i32 (Int.ofNat workspace.states.length),
        .signed .i32 (Int.ofNat field)] runtime :=
    ArgumentsEvaluateTo.cons baseArgument
      (ArgumentsEvaluateTo.cons stateIdArgument
        (ArgumentsEvaluateTo.singleton fieldArgument))
  have indexResult : Evaluates verifiedParserCore runtime
      (.call extractedParserStateWordFunction.id
        [.local 1, .local 7, .constant fieldConstant])
      (.signed .i32 (Int.ofNat address)) afterIndex := by
    have call := extractedParserStateWordCall_evaluates runtime runtime
      [.local 1, .local 7, .constant fieldConstant]
      (Int.ofNat (stateBase layout.tokenCount))
      (Int.ofNat workspace.states.length) (Int.ofNat field)
      invariant.wellFormed arguments
    have addressValue := layout.state_value_eq_address invariant.stateIdBound
      fieldBound
    rw [addressValue] at call
    simpa [afterIndex, address, parserStateWordCallState] using call
  have indexEffect : ModifiesOnly CellSet.empty runtime afterIndex := by
    simpa [afterIndex] using
      (parserStateWordCallState_effect (state := runtime)
        (base := Int.ofNat (stateBase layout.tokenCount))
        (stateId := Int.ofNat workspace.states.length)
        (field := Int.ofNat field))
  have indexWellFormed : StateWellFormed afterIndex := by
    exact parserStateWordCallState_well_formed invariant.wellFormed
  have afterIndexInvariant := invariant.after_empty_effect indexEffect
    indexWellFormed
  have addressBound : address < values.length := by
    rw [invariant.valuesLength]
    exact layout.state_address_valid invariant.stateIdBound fieldBound
  have write := evaluatesSetSignedI32SliceIndexFromEmpty verifiedParserCore
    runtime afterIndex afterIndex values 0
    (.call extractedParserStateWordFunction.id
      [.local 1, .local 7, .constant fieldConstant])
    right workspaceCell address replacement addressBound
    invariant.workspaceLocal indexResult indexWellFormed indexEffect
    (by simpa [afterIndex] using rightResult) indexWellFormed
    (ModifiesOnly.refl afterIndex) afterIndexInvariant.backing
  let after := Classical.choose write
  have facts := Classical.choose_spec write
  have afterInvariant := invariant.after_workspace_write address replacement
    after facts.2.2.2 facts.2.1 facts.2.2.1
  exact {
    after := after
    execution := by
      simpa [parserAppendStateWrite] using executesExpression facts.1
    effect := facts.2.2.2
    invariant := by simpa [address] using afterInvariant
  }

theorem AppendMutationInvariant.evaluates_seed_field
    (invariant : AppendMutationInvariant layout workspace values workspaceCell
      position seed runtime)
    (field : Nat) (fieldBound : field < 7) :
    Evaluates verifiedParserCore runtime (.field (.local 4) field)
      (.signed .i32 (appendSeedFieldValue seed field)) runtime := by
  have seedResult : Evaluates verifiedParserCore runtime (.local 4)
      (stateSeedValue seed) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 4
      (stateSeedValue seed) invariant.seedLocal⟩
  apply evaluatesStructureField seedResult
  simpa [stateSeedValue] using
    (stateSeedValue_append_field (seed := seed) (field := field) fieldBound)

theorem AppendMutationInvariant.evaluates_position
    (invariant : AppendMutationInvariant layout workspace values workspaceCell
      position seed runtime) :
    Evaluates verifiedParserCore runtime (.local 3)
      (.signed .i32 (Int.ofNat position)) runtime :=
  ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 3
    (.signed .i32 (Int.ofNat position)) invariant.positionLocal⟩

noncomputable def AppendMutationInvariant.write_seed_field
    (invariant : AppendMutationInvariant layout workspace values workspaceCell
      position seed runtime)
    (fieldConstant : ConstantId) (field seedField : Nat)
    (fieldBound : field < stateWords) (seedFieldBound : seedField < 7)
    (constantFound : verifiedParserCore.constant? fieldConstant = some {
      id := fieldConstant
      type := parserI32Type
      value := .signed .i32 (Int.ofNat field)
    }) :
    AppendStateWriteExecution layout workspace values workspaceCell position seed
      runtime invariant fieldConstant field (.field (.local 4) seedField)
      (appendSeedFieldValue seed seedField) := by
  apply invariant.write_state_field fieldConstant field fieldBound constantFound
  · dsimp only
    let afterIndex := parserStateWordCallState runtime
      (Int.ofNat (stateBase layout.tokenCount))
      (Int.ofNat workspace.states.length) (Int.ofNat field)
    have effect : ModifiesOnly CellSet.empty runtime afterIndex := by
      simpa [afterIndex] using
        (parserStateWordCallState_effect (state := runtime)
          (base := Int.ofNat (stateBase layout.tokenCount))
          (stateId := Int.ofNat workspace.states.length)
          (field := Int.ofNat field))
    have wellFormed : StateWellFormed afterIndex :=
      parserStateWordCallState_well_formed invariant.wellFormed
    exact (invariant.after_empty_effect effect wellFormed).evaluates_seed_field
      seedField seedFieldBound

noncomputable def AppendMutationInvariant.write_position
    (invariant : AppendMutationInvariant layout workspace values workspaceCell
      position seed runtime) :
    AppendStateWriteExecution layout workspace values workspaceCell position seed
      runtime invariant 31 3 (.local 3) (Int.ofNat position) := by
  apply invariant.write_state_field 31 3 (by decide)
    verifiedParser_append_write_constants.2.2.2.1
  · dsimp only
    let afterIndex := parserStateWordCallState runtime
      (Int.ofNat (stateBase layout.tokenCount))
      (Int.ofNat workspace.states.length) 3
    have effect : ModifiesOnly CellSet.empty runtime afterIndex := by
      simpa [afterIndex] using
        (parserStateWordCallState_effect (state := runtime)
          (base := Int.ofNat (stateBase layout.tokenCount))
          (stateId := Int.ofNat workspace.states.length) (field := 3))
    have wellFormed : StateWellFormed afterIndex :=
      parserStateWordCallState_well_formed invariant.wellFormed
    exact (invariant.after_empty_effect effect wellFormed).evaluates_position

noncomputable def AppendMutationInvariant.write_missing_next
    (invariant : AppendMutationInvariant layout workspace values workspaceCell
      position seed runtime) :
    AppendStateWriteExecution layout workspace values workspaceCell position seed
      runtime invariant 32 4
      (.unary .negate (.value (.signed .i32 1))) (-1) := by
  apply invariant.write_state_field 32 4 (by decide)
    verifiedParser_append_write_constants.2.2.2.2.1
  · dsimp only
    let afterIndex := parserStateWordCallState runtime
      (Int.ofNat (stateBase layout.tokenCount))
      (Int.ofNat workspace.states.length) 4
    have one : Evaluates verifiedParserCore afterIndex
        (.value (.signed .i32 1)) (.signed .i32 1) afterIndex := ⟨1, rfl⟩
    have wrapped : wrapSigned verifiedParserCore.target .i32 (-1) = -1 := by
      generalize verifiedParserCore.target = target
      rcases target with ⟨width⟩
      cases width <;> native_decide
    apply evaluatesUnary one
    simp [evalUnaryValue, wrapped]

structure AppendStateRecordExecution
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (values : List Int) (workspaceCell : CellId)
    (position : Nat) (seed : StateSeed) (before : State)
    (beforeInvariant : AppendMutationInvariant layout workspace values
      workspaceCell position seed before) where
  after : State
  continues : ∀ (tail : Stmt) (outcome : Completion) (finalState : State),
    Executes verifiedParserCore after tail outcome finalState →
    Executes verifiedParserCore before (parserAppendStateWrites tail)
      outcome finalState
  effect : ModifiesOnly (CellSet.singleton workspaceCell) before after
  invariant : AppendMutationInvariant layout workspace
    (applyWordWrites values
      (insertedStateRecordWrites layout workspace position seed))
    workspaceCell position seed after

noncomputable def AppendMutationInvariant.execute_state_record_writes
    (invariant : AppendMutationInvariant layout workspace values workspaceCell
      position seed runtime) :
    AppendStateRecordExecution layout workspace values workspaceCell position
      seed runtime invariant := by
  let write0 := invariant.write_seed_field 28 0 0 (by decide) (by decide)
    verifiedParser_append_write_constants.1
  let write1 := write0.invariant.write_seed_field 29 1 1 (by decide) (by decide)
    verifiedParser_append_write_constants.2.1
  let write2 := write1.invariant.write_seed_field 30 2 2 (by decide) (by decide)
    verifiedParser_append_write_constants.2.2.1
  let write3 := write2.invariant.write_position
  let write4 := write3.invariant.write_missing_next
  let write5 := write4.invariant.write_seed_field 33 5 3 (by decide) (by decide)
    verifiedParser_append_write_constants.2.2.2.2.2.1
  let write6 := write5.invariant.write_seed_field 34 6 4 (by decide) (by decide)
    verifiedParser_append_write_constants.2.2.2.2.2.2.1
  let write7 := write6.invariant.write_seed_field 35 7 5 (by decide) (by decide)
    verifiedParser_append_write_constants.2.2.2.2.2.2.2.1
  let write8 := write7.invariant.write_seed_field 36 8 6 (by decide) (by decide)
    verifiedParser_append_write_constants.2.2.2.2.2.2.2.2
  have completeEffect : ModifiesOnly (CellSet.singleton workspaceCell)
      runtime write8.after :=
    write0.effect.trans_same
      (write1.effect.trans_same
        (write2.effect.trans_same
          (write3.effect.trans_same
            (write4.effect.trans_same
              (write5.effect.trans_same
                (write6.effect.trans_same
                  (write7.effect.trans_same write8.effect)))))))
  exact {
    after := write8.after
    continues := by
      intro tail outcome finalState continuation
      exact executesSequence write0.execution
        (executesSequence write1.execution
          (executesSequence write2.execution
            (executesSequence write3.execution
              (executesSequence write4.execution
                (executesSequence write5.execution
                  (executesSequence write6.execution
                    (executesSequence write7.execution
                      (executesSequence write8.execution continuation))))))))
    effect := completeEffect
    invariant := by
      simpa [insertedStateRecordWrites, applyWordWrites,
        appendSeedFieldValue] using write8.invariant
  }

def closeAppendChartLocals
    (afterHead afterTail beforeTailLocal completed : State) : State :=
  restoreLocals afterHead
    (restoreLocals afterTail (restoreLocals beforeTailLocal completed))

structure AppendChartSetupExecution
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (values : List Int) (workspaceCell : CellId)
    (position : Nat) (seed : StateSeed) (before : State)
    (beforeInvariant : AppendMutationInvariant layout workspace values
      workspaceCell position seed before) where
  afterHead : State
  afterTail : State
  beforeTailLocal : State
  after : State
  tailValue : Int
  tailMeaning : tailValue = chartTailValue workspace position
  afterHeadLocals : afterHead.locals = before.locals
  local8 : after.local? 8 = some
    (.signed .i32 (Int.ofNat (chartWord position 0)))
  local9 : after.local? 9 = some
    (.signed .i32 (Int.ofNat (chartWord position 1)))
  local10 : after.local? 10 = some (.signed .i32 tailValue)
  invariant : AppendMutationInvariant layout workspace values workspaceCell
    position seed after
  entered : StoreEffect CellSet.empty before after
  continues : ∀ (completion : Completion) (completed : State),
    Executes verifiedParserCore after parserAppendLinkChart completion completed →
    Executes verifiedParserCore before parserAppendChartWords completion
      (closeAppendChartLocals afterHead afterTail beforeTailLocal completed)

noncomputable def AppendStateRecordExecution.setup_chart_locals
    (record : AppendStateRecordExecution layout workspace originalValues
      workspaceCell position seed before beforeInvariant)
    (encoded : EncodesWorkspace layout workspace (listWords originalValues)) :
    AppendChartSetupExecution layout workspace
      (applyWordWrites originalValues
        (insertedStateRecordWrites layout workspace position seed))
      workspaceCell position seed record.after record.invariant := by
  let values := applyWordWrites originalValues
    (insertedStateRecordWrites layout workspace position seed)
  let headRead := record.invariant.read_chart_address 25 0 (by decide)
    verifiedParser_append_chart_constants.1
  let afterHead := headRead.after
  let bound8 := afterHead.bindLocal 8
    (.signed .i32 (Int.ofNat (chartWord position 0)))
  have bound8Invariant : AppendMutationInvariant layout workspace values
      workspaceCell position seed bound8 := by
    exact headRead.invariant.after_bind_local 8 _ (by decide) (by decide)
      (by decide) (by decide) (by decide) (by decide)
  let tailRead := bound8Invariant.read_chart_address 26 1 (by decide)
    verifiedParser_append_chart_constants.2
  let afterTail := tailRead.after
  let bound9 := afterTail.bindLocal 9
    (.signed .i32 (Int.ofNat (chartWord position 1)))
  have bound9Invariant : AppendMutationInvariant layout workspace values
      workspaceCell position seed bound9 := by
    exact tailRead.invariant.after_bind_local 9 _ (by decide) (by decide)
      (by decide) (by decide) (by decide) (by decide)
  have local9AtBound9 : bound9.local? 9 = some
      (.signed .i32 (Int.ofNat (chartWord position 1))) := by
    simpa [bound9] using bindLocal_finds_local afterTail 9
      (.signed .i32 (Int.ofNat (chartWord position 1)))
      tailRead.invariant.wellFormed
  have chartTailBound : chartWord position 1 < values.length := by
    rw [bound9Invariant.valuesLength]
    exact layout.chart_address_valid bound9Invariant.positionBound (by decide)
  have tailAt : values.get ⟨chartWord position 1, chartTailBound⟩ =
      chartTailValue workspace position := by
    have preserved := insertedStateRecordWrites_preserve_chart layout workspace
      position seed originalValues position 1 beforeInvariant.positionBound
      (by decide)
    have originalBound : chartWord position 1 < originalValues.length := by
      rw [beforeInvariant.valuesLength]
      exact layout.chart_address_valid beforeInvariant.positionBound (by decide)
    rw [listWords_get values (chartWord position 1) chartTailBound] at preserved
    rw [listWords_get originalValues (chartWord position 1) originalBound]
      at preserved
    have originalTail := encoded.chartTail position beforeInvariant.positionBound
    rw [listWords_get originalValues (chartWord position 1) originalBound]
      at originalTail
    exact preserved.trans originalTail
  have tailIndex : Evaluates verifiedParserCore bound9
      (.index (.local 0) (.local 9))
      (.signed .i32 (chartTailValue workspace position)) bound9 := by
    have baseResult : Evaluates verifiedParserCore bound9 (.local 0)
        (workspaceValue values workspaceCell) bound9 :=
      ⟨1, evalLocal_of_local 1 verifiedParserCore bound9 0
        (workspaceValue values workspaceCell) bound9Invariant.workspaceLocal⟩
    have indexResult : Evaluates verifiedParserCore bound9 (.local 9)
        (.signed .i32 (Int.ofNat (chartWord position 1))) bound9 :=
      ⟨1, evalLocal_of_local 1 verifiedParserCore bound9 9
        (.signed .i32 (Int.ofNat (chartWord position 1))) local9AtBound9⟩
    have result := evaluatesSignedI32SliceIndex verifiedParserCore bound9 bound9
      bound9 values (.local 0) (.local 9) workspaceCell
      (chartWord position 1) chartTailBound baseResult indexResult
      bound9Invariant.backing
    rw [tailAt] at result
    simpa [workspaceValue] using result
  let bound10 := bound9.bindLocal 10
    (.signed .i32 (chartTailValue workspace position))
  have bound10Invariant : AppendMutationInvariant layout workspace values
      workspaceCell position seed bound10 := by
    exact bound9Invariant.after_bind_local 10 _ (by decide) (by decide)
      (by decide) (by decide) (by decide) (by decide)
  have local10 : bound10.local? 10 = some
      (.signed .i32 (chartTailValue workspace position)) := by
    simpa [bound10] using bindLocal_finds_local bound9 10
      (.signed .i32 (chartTailValue workspace position))
      bound9Invariant.wellFormed
  have local9AtBound10 : bound10.local? 9 = some
      (.signed .i32 (Int.ofNat (chartWord position 1))) := by
    simpa [bound10] using
      (bindLocal_preserves_other_local bound9Invariant.wellFormed
        (by decide : (10 : VarId) ≠ 9)).trans local9AtBound9
  have local8AtBound8 : bound8.local? 8 = some
      (.signed .i32 (Int.ofNat (chartWord position 0))) := by
    simpa [bound8] using bindLocal_finds_local afterHead 8
      (.signed .i32 (Int.ofNat (chartWord position 0)))
      headRead.invariant.wellFormed
  have local8AtAfterTail : afterTail.local? 8 = some
      (.signed .i32 (Int.ofNat (chartWord position 0))) :=
    tailRead.effect.empty_preserves_local bound8Invariant.wellFormed local8AtBound8
  have local8AtBound9 : bound9.local? 8 = some
      (.signed .i32 (Int.ofNat (chartWord position 0))) := by
    simpa [bound9] using
      (bindLocal_preserves_other_local tailRead.invariant.wellFormed
        (by decide : (9 : VarId) ≠ 8)).trans local8AtAfterTail
  have local8AtBound10 : bound10.local? 8 = some
      (.signed .i32 (Int.ofNat (chartWord position 0))) := by
    simpa [bound10] using
      (bindLocal_preserves_other_local bound9Invariant.wellFormed
        (by decide : (10 : VarId) ≠ 8)).trans local8AtBound9
  have entered : StoreEffect CellSet.empty record.after bound10 :=
    headRead.effect.toStoreEffect.trans_same
      ((bindLocal_effect afterHead 8
          (.signed .i32 (Int.ofNat (chartWord position 0)))).trans_same
        (tailRead.effect.toStoreEffect.trans_same
          ((bindLocal_effect afterTail 9
              (.signed .i32 (Int.ofNat (chartWord position 1)))).trans_same
            (bindLocal_effect bound9 10
              (.signed .i32 (chartTailValue workspace position))))))
  exact {
    afterHead := afterHead
    afterTail := afterTail
    beforeTailLocal := bound9
    after := bound10
    tailValue := chartTailValue workspace position
    tailMeaning := rfl
    afterHeadLocals := headRead.effect.locals
    local8 := local8AtBound10
    local9 := local9AtBound10
    local10 := local10
    invariant := bound10Invariant
    entered := by simpa [afterHead, afterTail, bound8, bound9, bound10] using entered
    continues := by
      intro completion completed continuation
      have local10Scope := executesLetLocal (type := parserI32Type) tailIndex
        continuation
      have local9Scope := executesLetLocal (type := parserI32Type)
        tailRead.evaluation local10Scope
      have local8Scope := executesLetLocal (type := parserI32Type)
        headRead.evaluation local9Scope
      simpa [parserAppendChartWords, closeAppendChartLocals, afterHead,
        afterTail, bound8, bound9, bound10] using local8Scope
  }

structure AppendFindRead
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (values : List Int) (workspaceCell : CellId)
    (position : Nat) (seed : StateSeed) (before : State)
    (beforeInvariant : AppendEntryInvariant layout workspace values
      workspaceCell position seed before) where
  after : State
  evaluation : Evaluates verifiedParserCore before parserAppendFindExpr
    (.signed .i32
      (encodeStateId (workspace.findStateId? position seed.key))) after
  effect : ModifiesOnly CellSet.empty before after
  invariant : AppendEntryInvariant layout workspace values workspaceCell
    position seed after

noncomputable def AppendEntryInvariant.read_find_state
    (invariant : AppendEntryInvariant layout workspace values workspaceCell
      position seed runtime) :
    AppendFindRead layout workspace values workspaceCell position seed runtime
      invariant := by
  have workspaceArgument : Evaluates verifiedParserCore runtime (.local 0)
      (workspaceValue values workspaceCell) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 0
      (workspaceValue values workspaceCell) invariant.workspaceLocal⟩
  have baseArgument : Evaluates verifiedParserCore runtime (.local 1)
      (.signed .i32 (Int.ofNat (stateBase layout.tokenCount))) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 1
      (.signed .i32 (Int.ofNat (stateBase layout.tokenCount)))
      invariant.baseLocal⟩
  have positionArgument : Evaluates verifiedParserCore runtime (.local 3)
      (.signed .i32 (Int.ofNat position)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 3
      (.signed .i32 (Int.ofNat position)) invariant.positionLocal⟩
  have seedArgument : Evaluates verifiedParserCore runtime (.local 4)
      (stateSeedValue seed) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 4
      (stateSeedValue seed) invariant.seedLocal⟩
  have arguments : ArgumentsEvaluateTo verifiedParserCore runtime
      [.local 0, .local 1, .local 3, .local 4] [
        workspaceValue values workspaceCell,
        .signed .i32 (Int.ofNat (stateBase layout.tokenCount)),
        .signed .i32 (Int.ofNat position), stateSeedValue seed] runtime :=
    ArgumentsEvaluateTo.cons workspaceArgument
      (ArgumentsEvaluateTo.cons baseArgument
        (ArgumentsEvaluateTo.cons positionArgument
          (ArgumentsEvaluateTo.singleton seedArgument)))
  let result := extractedParserFindStateCall_evaluates layout workspace values
      workspaceCell position seed runtime runtime
      [.local 0, .local 1, .local 3, .local 4]
      invariant.valuesLength invariant.encoded invariant.positionBound
      invariant.wellFormed arguments invariant.backing
  let after := Classical.choose result
  have resultFacts := Classical.choose_spec result
  have evaluation := resultFacts.1
  have effect := resultFacts.2.1
  have afterWellFormed := resultFacts.2.2.1
  exact {
    after := after
    evaluation := by simpa [parserAppendFindExpr] using evaluation
    effect := effect
    invariant := invariant.after_empty_effect effect afterWellFormed
  }

theorem evaluatesParserAppendExistingCondition
    (localFound : runtime.local? 6 =
      some (.signed .i32 (Int.ofNat stateId))) :
    Evaluates verifiedParserCore runtime
      (.binary .greaterEqual (.local 6) (.value (.signed .i32 0)))
      (.boolean true) runtime := by
  have left : Evaluates verifiedParserCore runtime (.local 6)
      (.signed .i32 (Int.ofNat stateId)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 6
      (.signed .i32 (Int.ofNat stateId)) localFound⟩
  have right : Evaluates verifiedParserCore runtime
      (.value (.signed .i32 0)) (.signed .i32 0) runtime := ⟨1, rfl⟩
  apply evaluatesEagerBinary (by decide) (by decide) left right
  simp [evalBinaryValue, evalSignedBinary]

theorem evaluatesParserAppendMissingCondition
    (localFound : runtime.local? 6 = some (.signed .i32 (-1))) :
    Evaluates verifiedParserCore runtime
      (.binary .greaterEqual (.local 6) (.value (.signed .i32 0)))
      (.boolean false) runtime := by
  have left : Evaluates verifiedParserCore runtime (.local 6)
      (.signed .i32 (-1)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 6
      (.signed .i32 (-1)) localFound⟩
  have right : Evaluates verifiedParserCore runtime
      (.value (.signed .i32 0)) (.signed .i32 0) runtime := ⟨1, rfl⟩
  apply evaluatesEagerBinary (by decide) (by decide) left right
  simp [evalBinaryValue, evalSignedBinary]

theorem evaluatesParserAppendCapacityConditionFull
    (countLocal : runtime.local? 5 =
      some (.signed .i32 (Int.ofNat count)))
    (capacityLocal : runtime.local? 2 =
      some (.signed .i32 (Int.ofNat capacity)))
    (full : capacity ≤ count) :
    Evaluates verifiedParserCore runtime
      (.binary .greaterEqual (.local 5) (.local 2))
      (.boolean true) runtime := by
  have left : Evaluates verifiedParserCore runtime (.local 5)
      (.signed .i32 (Int.ofNat count)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 5
      (.signed .i32 (Int.ofNat count)) countLocal⟩
  have right : Evaluates verifiedParserCore runtime (.local 2)
      (.signed .i32 (Int.ofNat capacity)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 2
      (.signed .i32 (Int.ofNat capacity)) capacityLocal⟩
  apply evaluatesEagerBinary (by decide) (by decide) left right
  simp [evalBinaryValue, evalSignedBinary, full]

theorem evaluatesParserAppendCapacityConditionAvailable
    (countLocal : runtime.local? 5 =
      some (.signed .i32 (Int.ofNat count)))
    (capacityLocal : runtime.local? 2 =
      some (.signed .i32 (Int.ofNat capacity)))
    (available : count < capacity) :
    Evaluates verifiedParserCore runtime
      (.binary .greaterEqual (.local 5) (.local 2))
      (.boolean false) runtime := by
  have left : Evaluates verifiedParserCore runtime (.local 5)
      (.signed .i32 (Int.ofNat count)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 5
      (.signed .i32 (Int.ofNat count)) countLocal⟩
  have right : Evaluates verifiedParserCore runtime (.local 2)
      (.signed .i32 (Int.ofNat capacity)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 2
      (.signed .i32 (Int.ofNat capacity)) capacityLocal⟩
  apply evaluatesEagerBinary (by decide) (by decide) left right
  simp [evalBinaryValue, evalSignedBinary, Nat.not_le_of_lt available]

theorem evaluatesParserAppendNegativeOne (runtime : State) :
    Evaluates verifiedParserCore runtime
      (.unary .negate (.value (.signed .i32 1)))
      (.signed .i32 (-1)) runtime := by
  have one : Evaluates verifiedParserCore runtime
      (.value (.signed .i32 1)) (.signed .i32 1) runtime := ⟨1, rfl⟩
  have wrapped : wrapSigned verifiedParserCore.target .i32 (-1) = -1 := by
    generalize verifiedParserCore.target = target
    rcases target with ⟨width⟩
    cases width <;> native_decide
  apply evaluatesUnary one
  simp [evalUnaryValue, wrapped]

def parserAppendResultBindings
    (status stateId stateCount : Int) (inserted : Bool) :
    List (VarId × Value) := [
  (0, .signed .i32 status),
  (1, .signed .i32 stateId),
  (2, .signed .i32 stateCount),
  (3, .boolean inserted)]

theorem AppendResultProof.parameterBindings_eq
    (status stateId stateCount : Int) (inserted : Bool) :
    Lanius.FunctionalView.Core.parameterBindings
        (AppendResultProof.environment status stateId stateCount inserted) =
      parserAppendResultBindings status stateId stateCount inserted := by
  apply List.ext_getElem
  · simp [parserAppendResultBindings]
  · intro index leftBound rightBound
    have alternatives : index = 0 ∨ index = 1 ∨ index = 2 ∨ index = 3 := by
      simp [parserAppendResultBindings] at rightBound
      omega
    rcases alternatives with rfl | rfl | rfl | rfl <;>
      simp [Lanius.FunctionalView.Core.parameterBindings_getElem,
        parserAppendResultBindings, AppendResultProof.environment]

def parserAppendResultCallee
    (caller : State) (status stateId stateCount : Int) (inserted : Bool) :
    State :=
  enterCall caller
    (parserAppendResultBindings status stateId stateCount inserted)

theorem parserAppendResultCallee_wellFormed
    (wellFormed : StateWellFormed caller) :
    StateWellFormed
      (parserAppendResultCallee caller status stateId stateCount inserted) :=
  enterCall_preserves_wellFormed wellFormed

/-- Full source-call contract for the extracted `append_result` constructor.
    This helper is used by all three semantic branches of `append_state`. -/
theorem extractedParserAppendResultCall_evaluates
    (before afterArguments : State) (arguments : List Expr)
    (status stateId stateCount : Int) (inserted : Bool)
    (afterArgumentsWellFormed : StateWellFormed afterArguments)
    (argumentsResult : ArgumentsEvaluateTo verifiedParserCore before arguments [
      .signed .i32 status, .signed .i32 stateId,
      .signed .i32 stateCount, .boolean inserted] afterArguments) :
    Evaluates verifiedParserCore before
      (.call extractedParserAppendResultFunction.id arguments)
      (appendResultValue status stateId stateCount inserted)
      (restoreLocals afterArguments
        (parserAppendResultCallee afterArguments status stateId stateCount
          inserted)) := by
  let callee := parserAppendResultCallee afterArguments status stateId
    stateCount inserted
  have bodyResult : Executes verifiedParserCore callee parserAppendResultBody
      (.returned (some
        (appendResultValue status stateId stateCount inserted))) callee := by
    have environmentMatches :
        Lanius.FunctionalView.Core.EnvironmentMatches
          (Lanius.FunctionalView.Core.identityLayout (arity := 4))
          (AppendResultProof.environment status stateId stateCount inserted)
          callee := by
      simpa [callee, parserAppendResultCallee, parserAppendResultBindings,
        AppendResultProof.parameterBindings_eq] using
        (Lanius.FunctionalView.Core.enterCall_parameterBindings_matches
          (environment := AppendResultProof.environment status stateId
            stateCount inserted)
          afterArgumentsWellFormed)
    have sound := Lanius.FunctionalView.Core.block_executes_without_locals
      (nextLocal := 4)
      (Lanius.FunctionalView.Core.ReadOnly.bridge verifiedParserCore)
      (AppendResultProof.world_represents callee) environmentMatches (by rfl)
      (AppendResultProof.evaluates status stateId stateCount inserted)
    rw [AppendResultProof.body_toCore_exactly] at sound
    exact sound.1
  apply evaluatesCallReturned (body := parserAppendResultBody)
    argumentsResult verifiedParserCore_finds_appendResult
  · rw [extractedParserAppendResult_function_shape.2.1]
    rfl
  · exact extractedParserAppendResult_function_shape.2.2.2.1
  · simpa [callee, parserAppendResultCallee, parserAppendResultBindings]
      using bodyResult

/-- The constructor call is store-pure: its four parameter cells are fresh
    call-local implementation detail and disappear when caller locals are
    restored.  Packaging this once keeps every `append_state` branch focused
    on its actual control-flow and workspace effect. -/
theorem extractedParserAppendResultCall_contract
    (before afterArguments : State) (arguments : List Expr)
    (status stateId stateCount : Int) (inserted : Bool)
    (afterArgumentsWellFormed : StateWellFormed afterArguments)
    (argumentsResult : ArgumentsEvaluateTo verifiedParserCore before arguments [
      .signed .i32 status, .signed .i32 stateId,
      .signed .i32 stateCount, .boolean inserted] afterArguments) :
    let after := restoreLocals afterArguments
      (parserAppendResultCallee afterArguments status stateId stateCount
        inserted)
    Evaluates verifiedParserCore before
      (.call extractedParserAppendResultFunction.id arguments)
      (appendResultValue status stateId stateCount inserted) after ∧
    ModifiesOnly CellSet.empty afterArguments after ∧
    StateWellFormed after := by
  let bindings := parserAppendResultBindings status stateId stateCount inserted
  let callee := parserAppendResultCallee afterArguments status stateId
    stateCount inserted
  let after := restoreLocals afterArguments callee
  have evaluation : Evaluates verifiedParserCore before
      (.call extractedParserAppendResultFunction.id arguments)
      (appendResultValue status stateId stateCount inserted) after := by
    simpa [after, callee] using
      extractedParserAppendResultCall_evaluates before afterArguments arguments
        status stateId stateCount inserted afterArgumentsWellFormed
        argumentsResult
  have entered : StoreEffect CellSet.empty afterArguments callee := by
    simpa [callee, parserAppendResultCallee, bindings,
      parserAppendResultBindings] using
      enterCall_effect afterArguments bindings
  have effect : ModifiesOnly CellSet.empty afterArguments after := by
    simpa [after] using entered.restoreLocals
  have calleeWellFormed : StateWellFormed callee := by
    simpa [callee, parserAppendResultCallee, bindings,
      parserAppendResultBindings] using
      (enterCall_preserves_wellFormed
        (bindings := bindings) afterArgumentsWellFormed)
  have afterWellFormed : StateWellFormed after :=
    entered.restoreLocals_wellFormed afterArgumentsWellFormed calleeWellFormed
  exact ⟨evaluation, effect, afterWellFormed⟩

def existingAppendOutcome (workspace : LogicalWorkspace)
    (stateId : Nat) : AppendOutcome := {
  status := .ok
  stateId := some stateId
  stateCount := workspace.states.length
  inserted := false
}

def fullAppendOutcome (workspace : LogicalWorkspace) : AppendOutcome := {
  status := .full
  stateId := none
  stateCount := workspace.states.length
  inserted := false
}

def insertedAppendOutcome (workspace : LogicalWorkspace) : AppendOutcome := {
  status := .ok
  stateId := some workspace.states.length
  stateCount := workspace.states.length + 1
  inserted := true
}

theorem AppendMutationInvariant.stateCountSuccI32
    (invariant : AppendMutationInvariant layout workspace values workspaceCell
      position seed runtime) :
    workspace.states.length + 1 ≤ 2147483647 := by
  have countLeCapacity : workspace.states.length + 1 ≤ layout.capacity :=
    Nat.succ_le_of_lt invariant.stateIdBound
  have capacityWords := stateCapacity_words_le_suffix layout.tokenCount
    layout.workspaceLength
  have capacityLeWords : layout.capacity ≤ layout.capacity * stateWords := by
    change stateCapacity layout.tokenCount layout.workspaceLength ≤
      stateCapacity layout.tokenCount layout.workspaceLength * 9
    omega
  have capacityLeWorkspace : layout.capacity ≤ layout.workspaceLength := by
    exact Nat.le_trans capacityLeWords
      (Nat.le_trans capacityWords (Nat.sub_le _ _))
  exact Nat.le_trans countLeCapacity
    (Nat.le_trans capacityLeWorkspace layout.workspaceI32)

theorem AppendMutationInvariant.evaluates_incremented_count
    (invariant : AppendMutationInvariant layout workspace values workspaceCell
      position seed runtime) :
    Evaluates verifiedParserCore runtime
      (.binary .add (.local 5) (.value (.signed .i32 1)))
      (.signed .i32 (Int.ofNat (workspace.states.length + 1))) runtime := by
  have left : Evaluates verifiedParserCore runtime (.local 5)
      (.signed .i32 (Int.ofNat workspace.states.length)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 5
      (.signed .i32 (Int.ofNat workspace.states.length))
      invariant.stateCountLocal⟩
  have right : Evaluates verifiedParserCore runtime
      (.value (.signed .i32 1)) (.signed .i32 1) runtime := ⟨1, rfl⟩
  have wrapped := wrapSigned_i32_ofNat verifiedParserCore.target
    (workspace.states.length + 1) invariant.stateCountSuccI32
  have sumCast : Int.ofNat workspace.states.length + 1 =
      Int.ofNat (workspace.states.length + 1) := by simp
  apply evaluatesEagerBinary (by decide) (by decide) left right
  simp only [evalBinaryValue, evalSignedBinary]
  rw [sumCast, wrapped]
  rfl

structure AppendInsertedReturnExecution
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (values : List Int) (workspaceCell : CellId)
    (position : Nat) (seed : StateSeed) (before : State)
    (invariant : AppendMutationInvariant layout workspace values workspaceCell
      position seed before) where
  after : State
  execution : Executes verifiedParserCore before
    (.sequence
      (.returnValue (some (parserAppendResultCall
        (.constant 40) (.local 7)
        (.binary .add (.local 5) (.value (.signed .i32 1)))
        (.value (.boolean true)))))
      .skip)
    (.returned (some (appendOutcomeValue (insertedAppendOutcome workspace))))
    after
  effect : ModifiesOnly CellSet.empty before after
  wellFormed : StateWellFormed after

noncomputable def AppendMutationInvariant.return_inserted
    (invariant : AppendMutationInvariant layout workspace values workspaceCell
      position seed runtime) :
    AppendInsertedReturnExecution layout workspace values workspaceCell position
      seed runtime invariant := by
  have statusArgument : Evaluates verifiedParserCore runtime (.constant 40)
      (.signed .i32 0) runtime := by
    refine ⟨2, ?_⟩
    simp [evalExpr, verifiedParser_append_status_constants.1]
  have stateIdArgument : Evaluates verifiedParserCore runtime (.local 7)
      (.signed .i32 (Int.ofNat workspace.states.length)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 7
      (.signed .i32 (Int.ofNat workspace.states.length))
      invariant.stateIdLocal⟩
  have countArgument := invariant.evaluates_incremented_count
  have insertedArgument : Evaluates verifiedParserCore runtime
      (.value (.boolean true)) (.boolean true) runtime := ⟨1, rfl⟩
  have arguments : ArgumentsEvaluateTo verifiedParserCore runtime [
      .constant 40, .local 7,
      .binary .add (.local 5) (.value (.signed .i32 1)),
      .value (.boolean true)] [
        .signed .i32 0,
        .signed .i32 (Int.ofNat workspace.states.length),
        .signed .i32 (Int.ofNat (workspace.states.length + 1)),
        .boolean true] runtime :=
    ArgumentsEvaluateTo.cons statusArgument
      (ArgumentsEvaluateTo.cons stateIdArgument
        (ArgumentsEvaluateTo.cons countArgument
          (ArgumentsEvaluateTo.singleton insertedArgument)))
  let after := restoreLocals runtime
    (parserAppendResultCallee runtime 0
      (Int.ofNat workspace.states.length)
      (Int.ofNat (workspace.states.length + 1)) true)
  have contract := extractedParserAppendResultCall_contract runtime runtime [
      .constant 40, .local 7,
      .binary .add (.local 5) (.value (.signed .i32 1)),
      .value (.boolean true)] 0 (Int.ofNat workspace.states.length)
    (Int.ofNat (workspace.states.length + 1)) true invariant.wellFormed
    arguments
  have call : Evaluates verifiedParserCore runtime
      (parserAppendResultCall (.constant 40) (.local 7)
        (.binary .add (.local 5) (.value (.signed .i32 1)))
        (.value (.boolean true)))
      (appendOutcomeValue (insertedAppendOutcome workspace)) after := by
    simpa [parserAppendResultCall, after, insertedAppendOutcome,
      appendOutcomeValue, appendStatusValue, encodeStateId] using contract.1
  exact {
    after := after
    execution := executesSequenceReturned (second := Stmt.skip)
      (executesReturnValue call)
    effect := by simpa [after] using contract.2.1
    wellFormed := by simpa [after] using contract.2.2
  }

theorem evaluatesParserAppendEmptyTailCondition
    (local10 : runtime.local? 10 = some (.signed .i32 (-1))) :
    Evaluates verifiedParserCore runtime
      (.binary .less (.local 10) (.value (.signed .i32 0)))
      (.boolean true) runtime := by
  have left : Evaluates verifiedParserCore runtime (.local 10)
      (.signed .i32 (-1)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 10
      (.signed .i32 (-1)) local10⟩
  have right : Evaluates verifiedParserCore runtime
      (.value (.signed .i32 0)) (.signed .i32 0) runtime := ⟨1, rfl⟩
  apply evaluatesEagerBinary (by decide) (by decide) left right
  simp [evalBinaryValue, evalSignedBinary]

theorem evaluatesParserAppendNonemptyTailCondition
    (local10 : runtime.local? 10 = some
      (.signed .i32 (Int.ofNat tail))) :
    Evaluates verifiedParserCore runtime
      (.binary .less (.local 10) (.value (.signed .i32 0)))
      (.boolean false) runtime := by
  have left : Evaluates verifiedParserCore runtime (.local 10)
      (.signed .i32 (Int.ofNat tail)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 10
      (.signed .i32 (Int.ofNat tail)) local10⟩
  have right : Evaluates verifiedParserCore runtime
      (.value (.signed .i32 0)) (.signed .i32 0) runtime := ⟨1, rfl⟩
  apply evaluatesEagerBinary (by decide) (by decide) left right
  simp [evalBinaryValue, evalSignedBinary]

structure AppendChartLinkExecution
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (values : List Int) (workspaceCell : CellId)
    (position : Nat) (seed : StateSeed) (before : State)
    (beforeInvariant : AppendMutationInvariant layout workspace values
      workspaceCell position seed before)
    (setup : AppendChartSetupExecution layout workspace values workspaceCell
      position seed before beforeInvariant) where
  after : State
  execution : Executes verifiedParserCore setup.after parserAppendLinkChart
    (.returned (some (appendOutcomeValue (insertedAppendOutcome workspace))))
    after
  effect : ModifiesOnly (CellSet.singleton workspaceCell) setup.after after
  wellFormed : StateWellFormed after
  backing : after.cellEntry? workspaceCell = some {
    id := workspaceCell
    value := some (.array (signedI32Values
      (applyWordWrites values
        (insertedChartLinkWrites layout workspace position))))
  }

noncomputable def AppendChartSetupExecution.execute_empty_chart
    (setup : AppendChartSetupExecution layout workspace values workspaceCell
      position seed before beforeInvariant)
    (tailFound : (workspace.chart position).getLast? = none) :
    AppendChartLinkExecution layout workspace values workspaceCell position seed
      before beforeInvariant setup := by
  have tailValue : chartTailValue workspace position = -1 := by
    simp [chartTailValue, tailFound, encodeStateId]
  have local10 : setup.after.local? 10 = some (.signed .i32 (-1)) := by
    rw [← tailValue]
    rw [← setup.tailMeaning]
    exact setup.local10
  have condition := evaluatesParserAppendEmptyTailCondition local10
  have headBound : chartWord position 0 < values.length := by
    rw [setup.invariant.valuesLength]
    exact layout.chart_address_valid setup.invariant.positionBound (by decide)
  let headWrite := setup.invariant.write_state_id_at_local_index 8
    (chartWord position 0) headBound setup.local8
  have local9AfterHead : headWrite.after.local? 9 = some
      (.signed .i32 (Int.ofNat (chartWord position 1))) :=
    headWrite.effect.singleton_preserves_local_of_ne
      setup.invariant.wellFormed setup.local9 setup.invariant.backing (by simp)
  have tailBound : chartWord position 1 <
      (setI32Value values (chartWord position 0)
        (Int.ofNat workspace.states.length)).length := by
    rw [setI32Value_length, setup.invariant.valuesLength]
    exact layout.chart_address_valid setup.invariant.positionBound (by decide)
  let tailWrite := headWrite.invariant.write_state_id_at_local_index 9
    (chartWord position 1) tailBound local9AfterHead
  let returned := tailWrite.invariant.return_inserted
  have selected : Executes verifiedParserCore setup.after
      (.ifThenElse
        (.binary .less (.local 10) (.value (.signed .i32 0)))
        (.sequence
          (.expression (.assign .set
            (.index (.local 0) (.local 8)) (.local 7))) .skip)
        (.sequence
          (.expression (.assign .set
            (.index (.local 0)
              (.call extractedParserStateWordFunction.id
                [.local 1, .local 10, .constant 32]))
            (.local 7))) .skip))
      .next headWrite.after := by
    have thenBranch := executesSequence headWrite.execution
      (executesSkip verifiedParserCore headWrite.after)
    exact executesIfTrue condition thenBranch
  have rest : Executes verifiedParserCore headWrite.after
      (.sequence
        (.expression (.assign .set
          (.index (.local 0) (.local 9)) (.local 7)))
        (.sequence
          (.returnValue (some (parserAppendResultCall
            (.constant 40) (.local 7)
            (.binary .add (.local 5) (.value (.signed .i32 1)))
            (.value (.boolean true))))) .skip))
      (.returned (some (appendOutcomeValue (insertedAppendOutcome workspace))))
      returned.after := executesSequence tailWrite.execution returned.execution
  have execution : Executes verifiedParserCore setup.after parserAppendLinkChart
      (.returned (some (appendOutcomeValue (insertedAppendOutcome workspace))))
      returned.after := by
    simpa [parserAppendLinkChart] using executesSequence selected rest
  have returnedAsWorkspace : ModifiesOnly (CellSet.singleton workspaceCell)
      tailWrite.after returned.after :=
    returned.effect.weaken CellSet.empty_subset
  have effect := headWrite.effect.trans_same
    (tailWrite.effect.trans_same returnedAsWorkspace)
  have finalBacking := returned.effect.empty_preserves_entry
    tailWrite.invariant.wellFormed tailWrite.invariant.backing
  exact {
    after := returned.after
    execution := execution
    effect := effect
    wellFormed := returned.wellFormed
    backing := by
      simpa [insertedChartLinkWrites, tailFound, applyWordWrites] using
        finalBacking
  }

noncomputable def AppendChartSetupExecution.execute_nonempty_chart
    (setup : AppendChartSetupExecution layout workspace values workspaceCell
      position seed before beforeInvariant)
    (encoded : EncodesWorkspace layout workspace originalWords)
    (tail : Nat) (tailFound : (workspace.chart position).getLast? = some tail) :
    AppendChartLinkExecution layout workspace values workspaceCell position seed
      before beforeInvariant setup := by
  have tailListed : tail ∈ workspace.chart position :=
    List.mem_of_getLast? tailFound
  have sound := encoded.wellFormed.chartSound position tail tailListed
  let tailState := Classical.choose sound
  have stateFound : workspace.state? tail = some tailState :=
    (Classical.choose_spec sound).1
  have tailBound : tail < layout.capacity := encoded.state_id_lt_capacity
    stateFound
  have tailValue : chartTailValue workspace position = Int.ofNat tail := by
    simp [chartTailValue, tailFound, encodeStateId]
  have local10 : setup.after.local? 10 = some
      (.signed .i32 (Int.ofNat tail)) := by
    rw [← tailValue, ← setup.tailMeaning]
    exact setup.local10
  have condition := evaluatesParserAppendNonemptyTailCondition local10
  let linkWrite := setup.invariant.write_tail_next tail tailBound local10
  have local9AfterLink : linkWrite.after.local? 9 = some
      (.signed .i32 (Int.ofNat (chartWord position 1))) :=
    linkWrite.effect.singleton_preserves_local_of_ne
      setup.invariant.wellFormed setup.local9 setup.invariant.backing (by simp)
  have chartTailBound : chartWord position 1 <
      (setI32Value values
        (stateWord (stateBase layout.tokenCount) tail 4)
        (Int.ofNat workspace.states.length)).length := by
    rw [setI32Value_length, setup.invariant.valuesLength]
    exact layout.chart_address_valid setup.invariant.positionBound (by decide)
  let tailWrite := linkWrite.invariant.write_state_id_at_local_index 9
    (chartWord position 1) chartTailBound local9AfterLink
  let returned := tailWrite.invariant.return_inserted
  have selected : Executes verifiedParserCore setup.after
      (.ifThenElse
        (.binary .less (.local 10) (.value (.signed .i32 0)))
        (.sequence
          (.expression (.assign .set
            (.index (.local 0) (.local 8)) (.local 7))) .skip)
        (.sequence
          (.expression (.assign .set
            (.index (.local 0)
              (.call extractedParserStateWordFunction.id
                [.local 1, .local 10, .constant 32]))
            (.local 7))) .skip))
      .next linkWrite.after := by
    have elseBranch := executesSequence linkWrite.execution
      (executesSkip verifiedParserCore linkWrite.after)
    exact executesIfFalse condition elseBranch
  have rest : Executes verifiedParserCore linkWrite.after
      (.sequence
        (.expression (.assign .set
          (.index (.local 0) (.local 9)) (.local 7)))
        (.sequence
          (.returnValue (some (parserAppendResultCall
            (.constant 40) (.local 7)
            (.binary .add (.local 5) (.value (.signed .i32 1)))
            (.value (.boolean true))))) .skip))
      (.returned (some (appendOutcomeValue (insertedAppendOutcome workspace))))
      returned.after := executesSequence tailWrite.execution returned.execution
  have execution : Executes verifiedParserCore setup.after parserAppendLinkChart
      (.returned (some (appendOutcomeValue (insertedAppendOutcome workspace))))
      returned.after := by
    simpa [parserAppendLinkChart] using executesSequence selected rest
  have returnedAsWorkspace : ModifiesOnly (CellSet.singleton workspaceCell)
      tailWrite.after returned.after :=
    returned.effect.weaken CellSet.empty_subset
  have effect := linkWrite.effect.trans_same
    (tailWrite.effect.trans_same returnedAsWorkspace)
  have finalBacking := returned.effect.empty_preserves_entry
    tailWrite.invariant.wellFormed tailWrite.invariant.backing
  exact {
    after := returned.after
    execution := execution
    effect := effect
    wellFormed := returned.wellFormed
    backing := by
      simpa [insertedChartLinkWrites, tailFound, applyWordWrites] using
        finalBacking
  }

structure AppendInsertedBodyExecution
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (values : List Int) (workspaceCell : CellId)
    (position : Nat) (seed : StateSeed) (before : State)
    (beforeInvariant : AppendEntryInvariant layout workspace values
      workspaceCell position seed before) where
  after : State
  execution : Executes verifiedParserCore before parserAppendStateBody
    (.returned (some (appendOutcomeValue (insertedAppendOutcome workspace))))
    after
  effect : ModifiesOnly (CellSet.singleton workspaceCell) before after
  wellFormed : StateWellFormed after
  backing : after.cellEntry? workspaceCell = some {
    id := workspaceCell
    value := some (.array (signedI32Values
      (insertEncodedState layout workspace position seed values)))
  }
  encoded : EncodesWorkspace layout (insertState workspace position seed)
    (listWords (insertEncodedState layout workspace position seed values))

noncomputable def AppendEntryInvariant.execute_inserted
    (invariant : AppendEntryInvariant layout workspace values workspaceCell
      position seed runtime)
    (missing : workspace.findStateId? position seed.key = none)
    (available : workspace.states.length < layout.capacity) :
    AppendInsertedBodyExecution layout workspace values workspaceCell position
      seed runtime invariant := by
  let read := invariant.read_find_state
  have findInitializer : Evaluates verifiedParserCore runtime parserAppendFindExpr
      (.signed .i32 (-1)) read.after := by
    have evaluation := read.evaluation
    rw [missing] at evaluation
    simpa [encodeStateId] using evaluation
  let bound6 := read.after.bindLocal 6 (.signed .i32 (-1))
  have bound6Invariant : AppendEntryInvariant layout workspace values
      workspaceCell position seed bound6 := by
    exact read.invariant.after_bind_local 6 _ (by decide) (by decide)
      (by decide) (by decide) (by decide) (by decide)
  have local6 : bound6.local? 6 = some (.signed .i32 (-1)) := by
    simpa [bound6] using bindLocal_finds_local read.after 6
      (.signed .i32 (-1)) read.invariant.wellFormed
  have existingCondition := evaluatesParserAppendMissingCondition local6
  have existingSkipped : Executes verifiedParserCore bound6
      parserAppendExistingIf .next bound6 := by
    simpa [parserAppendExistingIf] using
      (executesIfFalse existingCondition
        (executesSkip verifiedParserCore bound6))
  have capacityCondition := evaluatesParserAppendCapacityConditionAvailable
    bound6Invariant.stateCountLocal bound6Invariant.capacityLocal available
  have capacitySkipped : Executes verifiedParserCore bound6
      parserAppendFullIf .next bound6 := by
    simpa [parserAppendFullIf] using
      (executesIfFalse capacityCondition
        (executesSkip verifiedParserCore bound6))
  have stateIdInitializer : Evaluates verifiedParserCore bound6 (.local 5)
      (.signed .i32 (Int.ofNat workspace.states.length)) bound6 :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore bound6 5
      (.signed .i32 (Int.ofNat workspace.states.length))
      bound6Invariant.stateCountLocal⟩
  let bound7 := bound6.bindLocal 7
    (.signed .i32 (Int.ofNat workspace.states.length))
  have mutationInvariant : AppendMutationInvariant layout workspace values
      workspaceCell position seed bound7 := {
    valuesLength := bound6Invariant.valuesLength
    stateIdBound := available
    positionBound := bound6Invariant.positionBound
    wellFormed := bindLocal_preserves_well_formed bound6 7
      (.signed .i32 (Int.ofNat workspace.states.length))
      bound6Invariant.wellFormed
    workspaceLocal :=
      (bindLocal_preserves_other_local bound6Invariant.wellFormed
        (by decide : (7 : VarId) ≠ 0)).trans bound6Invariant.workspaceLocal
    baseLocal :=
      (bindLocal_preserves_other_local bound6Invariant.wellFormed
        (by decide : (7 : VarId) ≠ 1)).trans bound6Invariant.baseLocal
    positionLocal :=
      (bindLocal_preserves_other_local bound6Invariant.wellFormed
        (by decide : (7 : VarId) ≠ 3)).trans bound6Invariant.positionLocal
    seedLocal :=
      (bindLocal_preserves_other_local bound6Invariant.wellFormed
        (by decide : (7 : VarId) ≠ 4)).trans bound6Invariant.seedLocal
    stateCountLocal :=
      (bindLocal_preserves_other_local bound6Invariant.wellFormed
        (by decide : (7 : VarId) ≠ 5)).trans bound6Invariant.stateCountLocal
    stateIdLocal := by
      simpa [bound7] using bindLocal_finds_local bound6 7
        (.signed .i32 (Int.ofNat workspace.states.length))
        bound6Invariant.wellFormed
    backing := by
      have old := Lanius.Separation.StateWellFormed.cell_lt_next_of_entry
        bound6Invariant.wellFormed bound6Invariant.backing
      exact (bindLocal_effect bound6 7
        (.signed .i32 (Int.ofNat workspace.states.length))).oldCells
          workspaceCell old (by simp [CellSet.empty]) |>.trans
            bound6Invariant.backing
  }
  let record := mutationInvariant.execute_state_record_writes
  let setup := record.setup_chart_locals invariant.encoded
  let link : AppendChartLinkExecution layout workspace
      (applyWordWrites values
        (insertedStateRecordWrites layout workspace position seed))
      workspaceCell position seed record.after record.invariant setup := by
    cases tailFound : (workspace.chart position).getLast? with
    | none => exact setup.execute_empty_chart tailFound
    | some tail =>
        exact setup.execute_nonempty_chart invariant.encoded tail tailFound
  let chartAfter := closeAppendChartLocals setup.afterHead setup.afterTail
    setup.beforeTailLocal link.after
  have chartExecution : Executes verifiedParserCore record.after
      parserAppendChartWords
      (.returned (some (appendOutcomeValue (insertedAppendOutcome workspace))))
      chartAfter := by
    simpa [chartAfter] using setup.continues _ _ link.execution
  have chartStore : StoreEffect (CellSet.singleton workspaceCell)
      record.after link.after :=
    (setup.entered.weaken CellSet.empty_subset).trans_same
      link.effect.toStoreEffect
  have chartAfterEq : chartAfter = restoreLocals record.after link.after := by
    simp [chartAfter, closeAppendChartLocals, restoreLocals,
      setup.afterHeadLocals]
  have chartEffect : ModifiesOnly (CellSet.singleton workspaceCell)
      record.after chartAfter := by
    rw [chartAfterEq]
    exact chartStore.restoreLocals
  have chartWellFormed : StateWellFormed chartAfter := by
    rw [chartAfterEq]
    exact chartStore.restoreLocals_wellFormed record.invariant.wellFormed
      link.wellFormed
  have writesExecution : Executes verifiedParserCore bound7
      (parserAppendStateWrites parserAppendChartWords)
      (.returned (some (appendOutcomeValue (insertedAppendOutcome workspace))))
      chartAfter := record.continues _ _ _ chartExecution
  have writesEffect : ModifiesOnly (CellSet.singleton workspaceCell)
      bound7 chartAfter := record.effect.trans_same chartEffect
  let after7 := restoreLocals bound6 chartAfter
  have insertionExecution : Executes verifiedParserCore bound6
      parserAppendInsertBody
      (.returned (some (appendOutcomeValue (insertedAppendOutcome workspace))))
      after7 := by
    have insertionScoped := executesLetLocal (type := parserI32Type) stateIdInitializer
      writesExecution
    simpa [parserAppendInsertBody, bound7, after7] using insertionScoped
  have entered7 : StoreEffect (CellSet.singleton workspaceCell) bound6 bound7 :=
    (bindLocal_effect bound6 7
      (.signed .i32 (Int.ofNat workspace.states.length))).weaken
        CellSet.empty_subset
  have scope7Store : StoreEffect (CellSet.singleton workspaceCell)
      bound6 chartAfter := entered7.trans_same writesEffect.toStoreEffect
  have effect7 : ModifiesOnly (CellSet.singleton workspaceCell) bound6 after7 := by
    simpa [after7] using scope7Store.restoreLocals
  have wellFormed7 : StateWellFormed after7 := by
    simpa [after7] using scope7Store.restoreLocals_wellFormed
      bound6Invariant.wellFormed chartWellFormed
  have boundBody : Executes verifiedParserCore bound6
      (.sequence parserAppendExistingIf
        (.sequence parserAppendFullIf parserAppendInsertBody))
      (.returned (some (appendOutcomeValue (insertedAppendOutcome workspace))))
      after7 := executesSequence existingSkipped
        (executesSequence capacitySkipped insertionExecution)
  have entered6 : StoreEffect (CellSet.singleton workspaceCell) read.after bound6 :=
    (bindLocal_effect read.after 6 (.signed .i32 (-1))).weaken
      CellSet.empty_subset
  have scope6Store : StoreEffect (CellSet.singleton workspaceCell)
      read.after after7 := entered6.trans_same effect7.toStoreEffect
  let after := restoreLocals read.after after7
  have scopedBody := executesLetLocal (type := parserI32Type) findInitializer
    boundBody
  have execution : Executes verifiedParserCore runtime parserAppendStateBody
      (.returned (some (appendOutcomeValue (insertedAppendOutcome workspace))))
      after := by
    simpa [parserAppendStateBody, bound6, after] using scopedBody
  have afterReadEffect : ModifiesOnly (CellSet.singleton workspaceCell)
      read.after after := by
    simpa [after] using scope6Store.restoreLocals
  have completeEffect : ModifiesOnly (CellSet.singleton workspaceCell)
      runtime after :=
    (read.effect.weaken CellSet.empty_subset).trans_same afterReadEffect
  have afterWellFormed : StateWellFormed after := by
    simpa [after] using scope6Store.restoreLocals_wellFormed
      read.invariant.wellFormed wellFormed7
  have finalBacking : after.cellEntry? workspaceCell = some {
      id := workspaceCell
      value := some (.array (signedI32Values
        (insertEncodedState layout workspace position seed values)))
    } := by
    have backing : link.after.cellEntry? workspaceCell = some {
        id := workspaceCell
        value := some (.array (signedI32Values
          (insertEncodedState layout workspace position seed values)))
      } := by
      simpa [insertEncodedState, insertedWorkspaceWrites, applyWordWrites,
        List.foldl_append] using link.backing
    have sameEntry : after.cellEntry? workspaceCell =
        link.after.cellEntry? workspaceCell := by
      rfl
    exact sameEntry.trans backing
  exact {
    after := after
    execution := execution
    effect := completeEffect
    wellFormed := afterWellFormed
    backing := finalBacking
    encoded := insertEncodedState_encodes layout workspace position seed values
      invariant.valuesLength invariant.encoded invariant.positionBound
      invariant.seedOriginBound available
      (workspace.findStateId?_none_iff.mp missing)
  }

structure AppendUnchangedBodyExecution
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (values : List Int) (workspaceCell : CellId)
    (position : Nat) (seed : StateSeed) (before : State)
    (beforeInvariant : AppendEntryInvariant layout workspace values
      workspaceCell position seed before)
    (outcome : AppendOutcome) where
  after : State
  execution : Executes verifiedParserCore before parserAppendStateBody
    (.returned (some (appendOutcomeValue outcome))) after
  effect : ModifiesOnly CellSet.empty before after
  wellFormed : StateWellFormed after
  backing : after.cellEntry? workspaceCell = some {
    id := workspaceCell
    value := some (.array (signedI32Values values))
  }

/-- Execute the extracted branch that returns an already-present parser
    state.  The verified `find_state` result drives the branch condition and
    the workspace is unchanged. -/
noncomputable def AppendEntryInvariant.execute_existing
    (invariant : AppendEntryInvariant layout workspace values workspaceCell
      position seed runtime)
    (stateId : Nat)
    (found : workspace.findStateId? position seed.key = some stateId) :
    AppendUnchangedBodyExecution layout workspace values workspaceCell
      position seed runtime invariant (existingAppendOutcome workspace stateId) := by
  let read := invariant.read_find_state
  have initializer : Evaluates verifiedParserCore runtime parserAppendFindExpr
      (.signed .i32 (Int.ofNat stateId)) read.after := by
    have evaluation := read.evaluation
    rw [found] at evaluation
    simpa [encodeStateId] using evaluation
  let bound := read.after.bindLocal 6
    (.signed .i32 (Int.ofNat stateId))
  have boundWellFormed : StateWellFormed bound :=
    bindLocal_preserves_well_formed read.after 6
      (.signed .i32 (Int.ofNat stateId)) read.invariant.wellFormed
  have local6 : bound.local? 6 =
      some (.signed .i32 (Int.ofNat stateId)) := by
    simpa [bound] using bindLocal_finds_local read.after 6
      (.signed .i32 (Int.ofNat stateId)) read.invariant.wellFormed
  have local5 : bound.local? 5 = some
      (.signed .i32 (Int.ofNat workspace.states.length)) := by
    simpa [bound] using
      (bindLocal_preserves_other_local read.invariant.wellFormed
        (by decide : (6 : VarId) ≠ 5)).trans
          read.invariant.stateCountLocal
  have statusArgument : Evaluates verifiedParserCore bound (.constant 40)
      (.signed .i32 0) bound := by
    refine ⟨2, ?_⟩
    simp [evalExpr, verifiedParser_append_status_constants.1]
  have stateIdArgument : Evaluates verifiedParserCore bound (.local 6)
      (.signed .i32 (Int.ofNat stateId)) bound :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore bound 6
      (.signed .i32 (Int.ofNat stateId)) local6⟩
  have countArgument : Evaluates verifiedParserCore bound (.local 5)
      (.signed .i32 (Int.ofNat workspace.states.length)) bound :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore bound 5
      (.signed .i32 (Int.ofNat workspace.states.length)) local5⟩
  have insertedArgument : Evaluates verifiedParserCore bound
      (.value (.boolean false)) (.boolean false) bound := ⟨1, rfl⟩
  have arguments : ArgumentsEvaluateTo verifiedParserCore bound
      [.constant 40, .local 6, .local 5, .value (.boolean false)] [
        .signed .i32 0, .signed .i32 (Int.ofNat stateId),
        .signed .i32 (Int.ofNat workspace.states.length), .boolean false]
      bound :=
    ArgumentsEvaluateTo.cons statusArgument
      (ArgumentsEvaluateTo.cons stateIdArgument
        (ArgumentsEvaluateTo.cons countArgument
          (ArgumentsEvaluateTo.singleton insertedArgument)))
  let resultAfter := restoreLocals bound
    (parserAppendResultCallee bound 0 (Int.ofNat stateId)
      (Int.ofNat workspace.states.length) false)
  have resultContract := extractedParserAppendResultCall_contract bound bound
    [.constant 40, .local 6, .local 5, .value (.boolean false)]
    0 (Int.ofNat stateId) (Int.ofNat workspace.states.length) false
    boundWellFormed arguments
  have resultEvaluation : Evaluates verifiedParserCore bound
      (parserAppendResultCall (.constant 40) (.local 6) (.local 5)
        (.value (.boolean false)))
      (appendOutcomeValue (existingAppendOutcome workspace stateId))
      resultAfter := by
    simpa [parserAppendResultCall, resultAfter, existingAppendOutcome,
      appendOutcomeValue, appendStatusValue, encodeStateId] using
        resultContract.1
  have resultEffect : ModifiesOnly CellSet.empty bound resultAfter := by
    simpa [resultAfter] using resultContract.2.1
  have resultWellFormed : StateWellFormed resultAfter := by
    simpa [resultAfter] using resultContract.2.2
  have condition := evaluatesParserAppendExistingCondition local6
  have selected : Executes verifiedParserCore bound parserAppendExistingIf
      (.returned (some
        (appendOutcomeValue (existingAppendOutcome workspace stateId))))
      resultAfter := by
    have returned := executesReturnValue resultEvaluation
    have thenBranch := executesSequenceReturned (second := Stmt.skip) returned
    simpa [parserAppendExistingIf] using
      (executesIfTrue (elseBranch := Stmt.skip) condition thenBranch)
  have boundBody : Executes verifiedParserCore bound
      (.sequence parserAppendExistingIf
        (.sequence parserAppendFullIf parserAppendInsertBody))
      (.returned (some
        (appendOutcomeValue (existingAppendOutcome workspace stateId))))
      resultAfter := executesSequenceReturned selected
  have scopedExecution :=
    executesLetLocal (type := parserI32Type) initializer boundBody
  let after := restoreLocals read.after resultAfter
  have execution : Executes verifiedParserCore runtime parserAppendStateBody
      (.returned (some
        (appendOutcomeValue (existingAppendOutcome workspace stateId))))
      after := by
    simpa [parserAppendStateBody, bound, after] using scopedExecution
  have entered : StoreEffect CellSet.empty read.after bound := by
    simpa [bound] using
      bindLocal_effect read.after 6 (.signed .i32 (Int.ofNat stateId))
  have scopeStore : StoreEffect CellSet.empty read.after resultAfter :=
    entered.trans_same resultEffect.toStoreEffect
  have closed : ModifiesOnly CellSet.empty read.after after := by
    simpa [after] using scopeStore.restoreLocals
  have completeEffect : ModifiesOnly CellSet.empty runtime after :=
    read.effect.trans_same closed
  have afterWellFormed : StateWellFormed after :=
    scopeStore.restoreLocals_wellFormed read.invariant.wellFormed
      resultWellFormed
  exact {
    after := after
    execution := execution
    effect := completeEffect
    wellFormed := afterWellFormed
    backing := completeEffect.empty_preserves_entry invariant.wellFormed
      invariant.backing
  }

/-- Execute the extracted capacity guard after `find_state` reports no
    existing key.  Like the existing-state branch, this returns without
    mutating the encoded workspace. -/
noncomputable def AppendEntryInvariant.execute_full
    (invariant : AppendEntryInvariant layout workspace values workspaceCell
      position seed runtime)
    (missing : workspace.findStateId? position seed.key = none)
    (atCapacity : layout.capacity ≤ workspace.states.length) :
    AppendUnchangedBodyExecution layout workspace values workspaceCell
      position seed runtime invariant (fullAppendOutcome workspace) := by
  let read := invariant.read_find_state
  have initializer : Evaluates verifiedParserCore runtime parserAppendFindExpr
      (.signed .i32 (-1)) read.after := by
    have evaluation := read.evaluation
    rw [missing] at evaluation
    simpa [encodeStateId] using evaluation
  let bound := read.after.bindLocal 6 (.signed .i32 (-1))
  have boundWellFormed : StateWellFormed bound :=
    bindLocal_preserves_well_formed read.after 6 (.signed .i32 (-1))
      read.invariant.wellFormed
  have local6 : bound.local? 6 = some (.signed .i32 (-1)) := by
    simpa [bound] using bindLocal_finds_local read.after 6
      (.signed .i32 (-1)) read.invariant.wellFormed
  have local5 : bound.local? 5 = some
      (.signed .i32 (Int.ofNat workspace.states.length)) := by
    simpa [bound] using
      (bindLocal_preserves_other_local read.invariant.wellFormed
        (by decide : (6 : VarId) ≠ 5)).trans
          read.invariant.stateCountLocal
  have local2 : bound.local? 2 = some
      (.signed .i32 (Int.ofNat layout.capacity)) := by
    simpa [bound] using
      (bindLocal_preserves_other_local read.invariant.wellFormed
        (by decide : (6 : VarId) ≠ 2)).trans
          read.invariant.capacityLocal
  have existingCondition := evaluatesParserAppendMissingCondition local6
  have existingSkipped : Executes verifiedParserCore bound
      parserAppendExistingIf .next bound := by
    simpa [parserAppendExistingIf] using
      (executesIfFalse existingCondition
        (executesSkip verifiedParserCore bound))
  have capacityCondition := evaluatesParserAppendCapacityConditionFull
    local5 local2 atCapacity
  have statusArgument : Evaluates verifiedParserCore bound (.constant 41)
      (.signed .i32 1) bound := by
    refine ⟨2, ?_⟩
    simp [evalExpr, verifiedParser_append_status_constants.2]
  have missingArgument := evaluatesParserAppendNegativeOne bound
  have countArgument : Evaluates verifiedParserCore bound (.local 5)
      (.signed .i32 (Int.ofNat workspace.states.length)) bound :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore bound 5
      (.signed .i32 (Int.ofNat workspace.states.length)) local5⟩
  have insertedArgument : Evaluates verifiedParserCore bound
      (.value (.boolean false)) (.boolean false) bound := ⟨1, rfl⟩
  have arguments : ArgumentsEvaluateTo verifiedParserCore bound [
      .constant 41,
      .unary .negate (.value (.signed .i32 1)),
      .local 5,
      .value (.boolean false)] [
        .signed .i32 1, .signed .i32 (-1),
        .signed .i32 (Int.ofNat workspace.states.length), .boolean false]
      bound :=
    ArgumentsEvaluateTo.cons statusArgument
      (ArgumentsEvaluateTo.cons missingArgument
        (ArgumentsEvaluateTo.cons countArgument
          (ArgumentsEvaluateTo.singleton insertedArgument)))
  let resultAfter := restoreLocals bound
    (parserAppendResultCallee bound 1 (-1)
      (Int.ofNat workspace.states.length) false)
  have resultContract := extractedParserAppendResultCall_contract bound bound [
      .constant 41,
      .unary .negate (.value (.signed .i32 1)),
      .local 5,
      .value (.boolean false)]
    1 (-1) (Int.ofNat workspace.states.length) false boundWellFormed arguments
  have resultEvaluation : Evaluates verifiedParserCore bound
      (parserAppendResultCall (.constant 41)
        (.unary .negate (.value (.signed .i32 1)))
        (.local 5) (.value (.boolean false)))
      (appendOutcomeValue (fullAppendOutcome workspace)) resultAfter := by
    simpa [parserAppendResultCall, resultAfter, fullAppendOutcome,
      appendOutcomeValue, appendStatusValue, encodeStateId] using
        resultContract.1
  have resultEffect : ModifiesOnly CellSet.empty bound resultAfter := by
    simpa [resultAfter] using resultContract.2.1
  have resultWellFormed : StateWellFormed resultAfter := by
    simpa [resultAfter] using resultContract.2.2
  have fullSelected : Executes verifiedParserCore bound parserAppendFullIf
      (.returned (some (appendOutcomeValue (fullAppendOutcome workspace))))
      resultAfter := by
    have returned := executesReturnValue resultEvaluation
    have thenBranch := executesSequenceReturned (second := Stmt.skip) returned
    simpa [parserAppendFullIf] using
      (executesIfTrue (elseBranch := Stmt.skip) capacityCondition thenBranch)
  have restReturned : Executes verifiedParserCore bound
      (.sequence parserAppendFullIf parserAppendInsertBody)
      (.returned (some (appendOutcomeValue (fullAppendOutcome workspace))))
      resultAfter := executesSequenceReturned fullSelected
  have boundBody : Executes verifiedParserCore bound
      (.sequence parserAppendExistingIf
        (.sequence parserAppendFullIf parserAppendInsertBody))
      (.returned (some (appendOutcomeValue (fullAppendOutcome workspace))))
      resultAfter := executesSequence existingSkipped restReturned
  have scopedExecution :=
    executesLetLocal (type := parserI32Type) initializer boundBody
  let after := restoreLocals read.after resultAfter
  have execution : Executes verifiedParserCore runtime parserAppendStateBody
      (.returned (some (appendOutcomeValue (fullAppendOutcome workspace))))
      after := by
    simpa [parserAppendStateBody, bound, after] using scopedExecution
  have entered : StoreEffect CellSet.empty read.after bound := by
    simpa [bound] using
      bindLocal_effect read.after 6 (.signed .i32 (-1))
  have scopeStore : StoreEffect CellSet.empty read.after resultAfter :=
    entered.trans_same resultEffect.toStoreEffect
  have closed : ModifiesOnly CellSet.empty read.after after := by
    simpa [after] using scopeStore.restoreLocals
  have completeEffect : ModifiesOnly CellSet.empty runtime after :=
    read.effect.trans_same closed
  have afterWellFormed : StateWellFormed after :=
    scopeStore.restoreLocals_wellFormed read.invariant.wellFormed
      resultWellFormed
  exact {
    after := after
    execution := execution
    effect := completeEffect
    wellFormed := afterWellFormed
    backing := completeEffect.empty_preserves_entry invariant.wellFormed
      invariant.backing
  }

def appendResultValues
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (position : Nat) (seed : StateSeed) (values : List Int) : List Int :=
  if (appendLogical layout.capacity position seed workspace).1.inserted then
    insertEncodedState layout workspace position seed values
  else values

/-- A full append leaves both the logical workspace and its encoded backing
    values unchanged. -/
theorem appendResultValues_eq_of_full
    (statusFull :
      (appendLogical layout.capacity position seed workspace).1.status =
        .full) :
    appendResultValues layout workspace position seed values = values := by
  unfold appendResultValues
  have notInserted :
      (appendLogical layout.capacity position seed workspace).1.inserted =
        false := by
    unfold appendLogical at statusFull ⊢
    split
    · simp_all
    · split
      · rfl
      · simp_all
  simp [notInserted]

@[simp] theorem appendResultValues_length
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (position : Nat) (seed : StateSeed) (values : List Int) :
    (appendResultValues layout workspace position seed values).length =
      values.length := by
  unfold appendResultValues
  split <;> simp

structure AppendBodyExecution
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (values : List Int) (workspaceCell : CellId)
    (position : Nat) (seed : StateSeed) (before : State)
    (beforeInvariant : AppendEntryInvariant layout workspace values
      workspaceCell position seed before) where
  after : State
  execution : Executes verifiedParserCore before parserAppendStateBody
    (.returned (some (appendOutcomeValue
      (appendLogical layout.capacity position seed workspace).1))) after
  effect : ModifiesOnly (CellSet.singleton workspaceCell) before after
  wellFormed : StateWellFormed after
  backing : after.cellEntry? workspaceCell = some {
    id := workspaceCell
    value := some (.array (signedI32Values
      (appendResultValues layout workspace position seed values)))
  }
  encoded : EncodesWorkspace layout
    (appendLogical layout.capacity position seed workspace).2
    (listWords (appendResultValues layout workspace position seed values))

noncomputable def AppendEntryInvariant.execute_body
    (invariant : AppendEntryInvariant layout workspace values workspaceCell
      position seed runtime) :
    AppendBodyExecution layout workspace values workspaceCell position seed
      runtime invariant := by
  cases found : workspace.findStateId? position seed.key with
  | some stateId =>
      let result := invariant.execute_existing stateId found
      exact {
        after := result.after
        execution := by
          simpa [appendLogical, found, existingAppendOutcome] using
            result.execution
        effect := result.effect.weaken CellSet.empty_subset
        wellFormed := result.wellFormed
        backing := by
          simpa [appendResultValues, appendLogical, found] using result.backing
        encoded := by
          simpa [appendResultValues, appendLogical, found] using invariant.encoded
      }
  | none =>
      by_cases atCapacity : layout.capacity ≤ workspace.states.length
      · let result := invariant.execute_full found atCapacity
        exact {
          after := result.after
          execution := by
            simpa [appendLogical, found, atCapacity, fullAppendOutcome] using
              result.execution
          effect := result.effect.weaken CellSet.empty_subset
          wellFormed := result.wellFormed
          backing := by
            simpa [appendResultValues, appendLogical, found, atCapacity] using
              result.backing
          encoded := by
            simpa [appendResultValues, appendLogical, found, atCapacity] using
              invariant.encoded
        }
      · have available : workspace.states.length < layout.capacity :=
          Nat.lt_of_not_ge atCapacity
        let result := invariant.execute_inserted found available
        exact {
          after := result.after
          execution := by
            simpa [appendLogical, found, atCapacity, insertedAppendOutcome] using
              result.execution
          effect := result.effect
          wellFormed := result.wellFormed
          backing := by
            simpa [appendResultValues, appendLogical, found, atCapacity] using
              result.backing
          encoded := by
            simpa [appendResultValues, appendLogical, found, atCapacity] using
              result.encoded
        }

def parserAppendStateBindings
    (values : List Int) (workspaceCell : CellId)
    (layout : WorkspaceLayout) (position : Nat) (seed : StateSeed)
    (stateCount : Nat) : List (VarId × Value) := [
  (0, workspaceValue values workspaceCell),
  (1, .signed .i32 (Int.ofNat (stateBase layout.tokenCount))),
  (2, .signed .i32 (Int.ofNat layout.capacity)),
  (3, .signed .i32 (Int.ofNat position)),
  (4, stateSeedValue seed),
  (5, .signed .i32 (Int.ofNat stateCount))]

def parserAppendStateCallee
    (caller : State) (values : List Int) (workspaceCell : CellId)
    (layout : WorkspaceLayout) (position : Nat) (seed : StateSeed)
    (stateCount : Nat) : State :=
  enterCall caller
    (parserAppendStateBindings values workspaceCell layout position seed
      stateCount)

theorem parserAppendStateCallee_entry
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (values : List Int) (workspaceCell : CellId)
    (position : Nat) (seed : StateSeed) (caller : State)
    (valuesLength : values.length = layout.workspaceLength)
    (encoded : EncodesWorkspace layout workspace (listWords values))
    (positionBound : position ≤ finalPosition layout.tokenCount)
    (seedOriginBound : seed.origin ≤ finalPosition layout.tokenCount)
    (wellFormed : StateWellFormed caller)
    (backing : caller.cellEntry? workspaceCell = some {
      id := workspaceCell
      value := some (.array (signedI32Values values))
    }) :
    AppendEntryInvariant layout workspace values workspaceCell position seed
      (parserAppendStateCallee caller values workspaceCell layout position seed
        workspace.states.length) := by
  let workspaceArgument := workspaceValue values workspaceCell
  let base := Int.ofNat (stateBase layout.tokenCount)
  let capacity := Int.ofNat layout.capacity
  let sourcePosition := Int.ofNat position
  let seedArgument := stateSeedValue seed
  let count := Int.ofNat workspace.states.length
  let bindings : List (VarId × Value) := [
    (0, workspaceArgument), (1, .signed .i32 base),
    (2, .signed .i32 capacity), (3, .signed .i32 sourcePosition),
    (4, seedArgument), (5, .signed .i32 count)]
  let callee := enterCall caller bindings
  have calleeWellFormed : StateWellFormed callee :=
    enterCall_preserves_wellFormed wellFormed
  have workspaceOld : workspaceCell < caller.nextCell :=
    Lanius.Separation.StateWellFormed.cell_lt_next_of_entry wellFormed backing
  have calleeBacking : callee.cellEntry? workspaceCell = some {
      id := workspaceCell
      value := some (.array (signedI32Values values))
    } := by
    exact (enterCall_effect caller bindings).oldCells workspaceCell workspaceOld
      (by simp [CellSet.empty]) |>.trans backing
  have local0 : callee.local? 0 = some workspaceArgument := by
    simpa [callee, bindings] using
      (enterCall_local_of_binding caller [] [
        (1, .signed .i32 base), (2, .signed .i32 capacity),
        (3, .signed .i32 sourcePosition), (4, seedArgument),
        (5, .signed .i32 count)] 0 workspaceArgument wellFormed (by simp))
  have local1 : callee.local? 1 = some (.signed .i32 base) := by
    simpa [callee, bindings] using
      (enterCall_local_of_binding caller [(0, workspaceArgument)] [
        (2, .signed .i32 capacity), (3, .signed .i32 sourcePosition),
        (4, seedArgument), (5, .signed .i32 count)] 1
        (.signed .i32 base) wellFormed (by simp))
  have local2 : callee.local? 2 = some (.signed .i32 capacity) := by
    simpa [callee, bindings] using
      (enterCall_local_of_binding caller [
        (0, workspaceArgument), (1, .signed .i32 base)] [
        (3, .signed .i32 sourcePosition), (4, seedArgument),
        (5, .signed .i32 count)] 2 (.signed .i32 capacity) wellFormed
        (by simp))
  have local3 : callee.local? 3 = some (.signed .i32 sourcePosition) := by
    simpa [callee, bindings] using
      (enterCall_local_of_binding caller [
        (0, workspaceArgument), (1, .signed .i32 base),
        (2, .signed .i32 capacity)] [
        (4, seedArgument), (5, .signed .i32 count)] 3
        (.signed .i32 sourcePosition) wellFormed (by simp))
  have local4 : callee.local? 4 = some seedArgument := by
    simpa [callee, bindings] using
      (enterCall_local_of_binding caller [
        (0, workspaceArgument), (1, .signed .i32 base),
        (2, .signed .i32 capacity), (3, .signed .i32 sourcePosition)] [
        (5, .signed .i32 count)] 4 seedArgument wellFormed (by simp))
  have local5 : callee.local? 5 = some (.signed .i32 count) := by
    simpa [callee, bindings] using
      (enterCall_local_of_binding caller [
        (0, workspaceArgument), (1, .signed .i32 base),
        (2, .signed .i32 capacity), (3, .signed .i32 sourcePosition),
        (4, seedArgument)] [] 5 (.signed .i32 count) wellFormed (by simp))
  simpa [parserAppendStateCallee, parserAppendStateBindings,
      workspaceArgument, base, capacity, sourcePosition, seedArgument, count,
      bindings, callee] using
    (show AppendEntryInvariant layout workspace values workspaceCell position
        seed callee from {
      valuesLength := valuesLength
      encoded := encoded
      positionBound := positionBound
      seedOriginBound := seedOriginBound
      wellFormed := calleeWellFormed
      workspaceLocal := local0
      baseLocal := local1
      capacityLocal := local2
      positionLocal := local3
      seedLocal := local4
      stateCountLocal := local5
      backing := calleeBacking
    })

/-- Full source-call contract for extracted `append_state`.  The result and
    post-state are the executable abstract `appendLogical`; the physical
    backing is either unchanged or the eleven-write compact insertion, and
    the representation invariant is re-established before caller locals are
    restored. -/
theorem extractedParserAppendStateCall_evaluates
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (values : List Int) (workspaceCell : CellId)
    (position : Nat) (seed : StateSeed)
    (before afterArguments : State) (arguments : List Expr)
    (valuesLength : values.length = layout.workspaceLength)
    (encoded : EncodesWorkspace layout workspace (listWords values))
    (positionBound : position ≤ finalPosition layout.tokenCount)
    (seedOriginBound : seed.origin ≤ finalPosition layout.tokenCount)
    (afterArgumentsWellFormed : StateWellFormed afterArguments)
    (argumentsResult : ArgumentsEvaluateTo verifiedParserCore before arguments [
      workspaceValue values workspaceCell,
      .signed .i32 (Int.ofNat (stateBase layout.tokenCount)),
      .signed .i32 (Int.ofNat layout.capacity),
      .signed .i32 (Int.ofNat position), stateSeedValue seed,
      .signed .i32 (Int.ofNat workspace.states.length)] afterArguments)
    (backing : afterArguments.cellEntry? workspaceCell = some {
      id := workspaceCell
      value := some (.array (signedI32Values values))
    }) :
    ∃ after,
      Evaluates verifiedParserCore before
        (.call extractedParserAppendStateFunction.id arguments)
        (appendOutcomeValue
          (appendLogical layout.capacity position seed workspace).1) after ∧
      ModifiesOnly (CellSet.singleton workspaceCell) afterArguments after ∧
      StateWellFormed after ∧
      after.cellEntry? workspaceCell = some {
        id := workspaceCell
        value := some (.array (signedI32Values
          (appendResultValues layout workspace position seed values)))
      } ∧
      EncodesWorkspace layout
        (appendLogical layout.capacity position seed workspace).2
        (listWords
          (appendResultValues layout workspace position seed values)) := by
  let bindings := parserAppendStateBindings values workspaceCell layout
    position seed workspace.states.length
  let callee := parserAppendStateCallee afterArguments values workspaceCell
    layout position seed workspace.states.length
  have entry : AppendEntryInvariant layout workspace values workspaceCell
      position seed callee := by
    simpa [callee] using parserAppendStateCallee_entry layout workspace values
      workspaceCell position seed afterArguments valuesLength encoded
      positionBound seedOriginBound afterArgumentsWellFormed backing
  let bodyResult := entry.execute_body
  let after := restoreLocals afterArguments bodyResult.after
  have evaluation : Evaluates verifiedParserCore before
      (.call extractedParserAppendStateFunction.id arguments)
      (appendOutcomeValue
        (appendLogical layout.capacity position seed workspace).1) after := by
    apply evaluatesCallReturned (body := parserAppendStateBody)
      argumentsResult verifiedParserCore_finds_appendState
    · rw [extractedParserAppendState_function_signature.2.1]
      rfl
    · exact extractedParserAppendState_body_eq
    · simpa [after, callee, parserAppendStateCallee, bindings,
        parserAppendStateBindings] using bodyResult.execution
  have entered : StoreEffect (CellSet.singleton workspaceCell)
      afterArguments callee := by
    exact (enterCall_effect afterArguments bindings).weaken CellSet.empty_subset
  have callStore : StoreEffect (CellSet.singleton workspaceCell)
      afterArguments bodyResult.after := by
    exact entered.trans_same bodyResult.effect.toStoreEffect
  have callEffect : ModifiesOnly (CellSet.singleton workspaceCell)
      afterArguments after := by
    simpa [after] using callStore.restoreLocals
  have afterWellFormed : StateWellFormed after :=
    callStore.restoreLocals_wellFormed afterArgumentsWellFormed
      bodyResult.wellFormed
  have afterBacking : after.cellEntry? workspaceCell = some {
      id := workspaceCell
      value := some (.array (signedI32Values
        (appendResultValues layout workspace position seed values)))
    } := by
    have sameEntry : after.cellEntry? workspaceCell =
        bodyResult.after.cellEntry? workspaceCell := by rfl
    exact sameEntry.trans bodyResult.backing
  exact ⟨after, evaluation, callEffect, afterWellFormed, afterBacking,
    bodyResult.encoded⟩

end Lanius.Extraction.ParserAppend
