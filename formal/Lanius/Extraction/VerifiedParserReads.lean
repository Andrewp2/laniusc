import Lanius.Compiler.ParserEncoding
import Lanius.CallContracts

namespace Lanius.Extraction

open Lanius.Core
open Lanius.Semantics
open Lanius.Compiler.Parser
open Lanius.Properties
open Lanius.Separation
open Lanius.CallContracts

def parserChartWordBindings (position field : Int) :
    List (VarId × Value) :=
  [(0, .signed .i32 position), (1, .signed .i32 field)]

def parserChartWordCallee (state : State) (position field : Int) : State :=
  enterCall state (parserChartWordBindings position field)

theorem parserChartWordCallee_well_formed
    (wellFormed : StateWellFormed state) :
    StateWellFormed (parserChartWordCallee state position field) :=
  enterCall_preserves_wellFormed wellFormed

def parserChartWordCallState (state : State) (position field : Int) : State :=
  restoreLocals state (parserChartWordCallee state position field)

theorem parserChartWordCallState_effect :
    ModifiesOnly CellSet.empty state
      (parserChartWordCallState state position field) := by
  exact (enterCall_effect state (parserChartWordBindings position field))
    |>.restoreLocals

theorem parserChartWordCallState_well_formed
    (wellFormed : StateWellFormed state) :
    StateWellFormed (parserChartWordCallState state position field) := by
  exact (enterCall_effect state (parserChartWordBindings position field))
    |>.restoreLocals_wellFormed wellFormed
      (parserChartWordCallee_well_formed wellFormed)

private theorem parserChartWordCallee_position
    (wellFormed : StateWellFormed state) :
    (parserChartWordCallee state position field).local? 0 =
      some (.signed .i32 position) := by
  let cleared : State := { state with locals := [] }
  have clearedWellFormed := clearLocals_preserves_wellFormed wellFormed
  have entry := bindLocals_finds_cell_after_prefix cleared []
    [(1, .signed .i32 field)] 0 (.signed .i32 position) clearedWellFormed
  have cellId : (parserChartWordCallee state position field).cellId? 0 =
      some state.nextCell := by
    rfl
  rw [State.local?, cellId]
  simp only [Option.bind_some, State.cell?]
  rw [show (parserChartWordCallee state position field).cellEntry?
      state.nextCell = some {
        id := state.nextCell
        value := some (.signed .i32 position)
      } by
    simpa [parserChartWordCallee, parserChartWordBindings, enterCall, cleared]
      using entry]
  rfl

private theorem parserChartWordCallee_field
    (wellFormed : StateWellFormed state) :
    (parserChartWordCallee state position field).local? 1 =
      some (.signed .i32 field) := by
  let cleared : State := { state with locals := [] }
  have clearedWellFormed := clearLocals_preserves_wellFormed wellFormed
  have entry := bindLocals_finds_cell_after_prefix cleared
    [(0, .signed .i32 position)] [] 1 (.signed .i32 field)
    clearedWellFormed
  have cellId : (parserChartWordCallee state position field).cellId? 1 =
      some (state.nextCell + 1) := by
    rfl
  rw [State.local?, cellId]
  simp only [Option.bind_some, State.cell?]
  rw [show (parserChartWordCallee state position field).cellEntry?
      (state.nextCell + 1) = some {
        id := state.nextCell + 1
        value := some (.signed .i32 field)
      } by
    simpa [parserChartWordCallee, parserChartWordBindings, enterCall, cleared]
      using entry]
  rfl

theorem extractedParserChartWordCall_evaluates
    (before afterArguments : State) (arguments : List Expr)
    (position field : Int)
    (afterArgumentsWellFormed : StateWellFormed afterArguments)
    (argumentsResult : ArgumentsEvaluateTo verifiedParserCore before arguments
      [.signed .i32 position, .signed .i32 field] afterArguments) :
    Evaluates verifiedParserCore before
      (.call extractedParserChartWordFunction.id arguments)
      (.signed .i32
        (parserChartWordValue verifiedParserCore.target position field))
      (restoreLocals afterArguments
        (parserChartWordCallee afterArguments position field)) := by
  let callee := parserChartWordCallee afterArguments position field
  have bodyResult : Executes verifiedParserCore callee parserChartWordBody
      (.returned (some (.signed .i32
        (parserChartWordValue verifiedParserCore.target position field))))
      callee := by
    exact parserChartWordBody_executes verifiedParserCore callee position field
      (parserChartWordCallee_position afterArgumentsWellFormed)
      (parserChartWordCallee_field afterArgumentsWellFormed)
      verifiedParser_workspace_constants.1
  apply evaluatesCallReturned argumentsResult verifiedParserCore_finds_chartWord
  · rw [extractedParser_workspace_function_shapes.1]
    rfl
  · exact extractedParser_workspace_function_shapes.2.2.1
  · simpa [callee, parserChartWordCallee, parserChartWordBindings]
      using bodyResult

def parserFindChartHeadExpr : Expr :=
  .index (.local 0)
    (.call extractedParserChartWordFunction.id [.local 2, .constant 25])

theorem parserFindChartHeadExpr_reads_encoded
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (values : List Int) (workspaceCell : CellId)
    (valuesLength : values.length = layout.workspaceLength)
    (encoded : EncodesWorkspace layout workspace (listWords values))
    (position : Nat)
    (positionBound : position ≤ finalPosition layout.tokenCount)
    (before : State) (beforeWellFormed : StateWellFormed before)
    (workspaceLocal : before.local? 0 = some
      (.slice parserI32Type workspaceCell [] 0 values.length))
    (positionLocal : before.local? 2 =
      some (.signed .i32 (Int.ofNat position)))
    (backing : before.cellEntry? workspaceCell = some {
      id := workspaceCell
      value := some (.array (signedI32Values values))
    }) :
    let afterCall := restoreLocals before
      (parserChartWordCallee before (Int.ofNat position) 0)
    Evaluates verifiedParserCore before parserFindChartHeadExpr
      (.signed .i32 (chartHeadValue workspace position)) afterCall := by
  dsimp only
  let afterCall := restoreLocals before
    (parserChartWordCallee before (Int.ofNat position) 0)
  have positionArgument : Evaluates verifiedParserCore before (.local 2)
      (.signed .i32 (Int.ofNat position)) before :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore before 2
      (.signed .i32 (Int.ofNat position)) positionLocal⟩
  have fieldArgument : Evaluates verifiedParserCore before (.constant 25)
      (.signed .i32 0) before := by
    refine ⟨2, ?_⟩
    simp [evalExpr, verifiedParser_find_constants.1]
  have arguments : ArgumentsEvaluateTo verifiedParserCore before
      [.local 2, .constant 25]
      [.signed .i32 (Int.ofNat position), .signed .i32 0] before :=
    ArgumentsEvaluateTo.cons positionArgument
      (ArgumentsEvaluateTo.singleton fieldArgument)
  have addressCall : Evaluates verifiedParserCore before
      (.call extractedParserChartWordFunction.id [.local 2, .constant 25])
      (.signed .i32 (Int.ofNat (chartWord position 0))) afterCall := by
    have call := extractedParserChartWordCall_evaluates before before
      [.local 2, .constant 25] (Int.ofNat position) 0 beforeWellFormed
      arguments
    have addressValue :
        parserChartWordValue verifiedParserCore.target
            (Int.ofNat position) 0 = Int.ofNat (chartWord position 0) := by
      simpa using layout.chart_value_eq_address
        (position := position) (field := 0) positionBound (by decide)
    rw [addressValue] at call
    simpa [afterCall] using call
  have addressBound : chartWord position 0 < values.length := by
    rw [valuesLength]
    exact layout.chart_address_valid positionBound (by decide)
  have workspaceOld : workspaceCell < before.nextCell :=
    Lanius.Separation.StateWellFormed.cell_lt_next_of_entry
      beforeWellFormed backing
  have afterBacking : afterCall.cellEntry? workspaceCell = some {
      id := workspaceCell
      value := some (.array (signedI32Values values))
    } := by
    have entered := enterCall_effect before
      (parserChartWordBindings (Int.ofNat position) 0)
    have restored := entered.restoreLocals
    have preserved := restored.oldCells workspaceCell workspaceOld
      (by simp [CellSet.empty])
    exact preserved.trans backing
  have indexed := evaluatesSignedI32SliceIndex verifiedParserCore before before
    afterCall values (.local 0)
    (.call extractedParserChartWordFunction.id [.local 2, .constant 25])
    workspaceCell (chartWord position 0) addressBound
    ⟨1, evalLocal_of_local 1 verifiedParserCore before 0
      (.slice parserI32Type workspaceCell [] 0 values.length)
      workspaceLocal⟩ addressCall afterBacking
  have chartRead : values.get ⟨chartWord position 0, addressBound⟩ =
      chartHeadValue workspace position := by
    have concrete := encoded.chartHead position positionBound
    rw [listWords_get values (chartWord position 0) addressBound] at concrete
    exact concrete
  rw [chartRead] at indexed
  simpa [parserFindChartHeadExpr, afterCall] using indexed

def parserStateWordBindings (base stateId field : Int) :
    List (VarId × Value) :=
  [(0, .signed .i32 base), (1, .signed .i32 stateId),
    (2, .signed .i32 field)]

def parserStateWordCallee
    (state : State) (base stateId field : Int) : State :=
  enterCall state (parserStateWordBindings base stateId field)

theorem parserStateWordCallee_well_formed
    (wellFormed : StateWellFormed state) :
    StateWellFormed (parserStateWordCallee state base stateId field) := by
  exact enterCall_preserves_wellFormed wellFormed

def parserStateWordCallState
    (state : State) (base stateId field : Int) : State :=
  restoreLocals state (parserStateWordCallee state base stateId field)

theorem parserStateWordCallState_effect :
    ModifiesOnly CellSet.empty state
      (parserStateWordCallState state base stateId field) := by
  exact (enterCall_effect state
    (parserStateWordBindings base stateId field)).restoreLocals

theorem parserStateWordCallState_well_formed
    (wellFormed : StateWellFormed state) :
    StateWellFormed (parserStateWordCallState state base stateId field) := by
  exact (enterCall_effect state
    (parserStateWordBindings base stateId field))
      |>.restoreLocals_wellFormed wellFormed
        (parserStateWordCallee_well_formed wellFormed)

theorem parserStateWordCallee_base
    (wellFormed : StateWellFormed state) :
    (parserStateWordCallee state base stateId field).local? 0 =
      some (.signed .i32 base) := by
  let cleared : State := { state with locals := [] }
  have clearedWellFormed : StateWellFormed cleared :=
    clearLocals_preserves_wellFormed wellFormed
  have entry := bindLocals_finds_cell_after_prefix cleared []
    [(1, .signed .i32 stateId), (2, .signed .i32 field)]
    0 (.signed .i32 base) clearedWellFormed
  have cellId :
      (parserStateWordCallee state base stateId field).cellId? 0 =
        some state.nextCell := by
    rfl
  rw [State.local?, cellId]
  simp only [Option.bind_some, State.cell?]
  have entry' :
      (parserStateWordCallee state base stateId field).cellEntry?
          state.nextCell =
        some { id := state.nextCell, value := some (.signed .i32 base) } := by
    simpa [parserStateWordCallee, parserStateWordBindings, enterCall, cleared]
      using entry
  rw [entry']
  rfl

theorem parserStateWordCallee_stateId
    (wellFormed : StateWellFormed state) :
    (parserStateWordCallee state base stateId field).local? 1 =
      some (.signed .i32 stateId) := by
  let cleared : State := { state with locals := [] }
  have clearedWellFormed : StateWellFormed cleared :=
    clearLocals_preserves_wellFormed wellFormed
  have entry := bindLocals_finds_cell_after_prefix cleared
    [(0, .signed .i32 base)] [(2, .signed .i32 field)]
    1 (.signed .i32 stateId) clearedWellFormed
  have cellId :
      (parserStateWordCallee state base stateId field).cellId? 1 =
        some (state.nextCell + 1) := by
    rfl
  rw [State.local?, cellId]
  simp only [Option.bind_some, State.cell?]
  have entry' :
      (parserStateWordCallee state base stateId field).cellEntry?
          (state.nextCell + 1) =
        some {
          id := state.nextCell + 1
          value := some (.signed .i32 stateId)
        } := by
    simpa [parserStateWordCallee, parserStateWordBindings, enterCall, cleared]
      using entry
  rw [entry']
  rfl

theorem parserStateWordCallee_field
    (wellFormed : StateWellFormed state) :
    (parserStateWordCallee state base stateId field).local? 2 =
      some (.signed .i32 field) := by
  let cleared : State := { state with locals := [] }
  have clearedWellFormed : StateWellFormed cleared :=
    clearLocals_preserves_wellFormed wellFormed
  have entry := bindLocals_finds_cell_after_prefix cleared
    [(0, .signed .i32 base), (1, .signed .i32 stateId)] []
    2 (.signed .i32 field) clearedWellFormed
  have cellId :
      (parserStateWordCallee state base stateId field).cellId? 2 =
        some (state.nextCell + 2) := by
    rfl
  rw [State.local?, cellId]
  simp only [Option.bind_some, State.cell?]
  have entry' :
      (parserStateWordCallee state base stateId field).cellEntry?
          (state.nextCell + 2) =
        some {
          id := state.nextCell + 2
          value := some (.signed .i32 field)
        } := by
    simpa [parserStateWordCallee, parserStateWordBindings, enterCall, cleared]
      using entry
  rw [entry']
  rfl

def extractedParserStateValueWire : CoreFunction :=
  artifact_function%
    (include_str "Artifacts" / "parser.json"),
    "verified_compiler/src/verified/parser.lani",
    "state_value"

def extractedParserStateValueFunction : Function :=
  CoreDecode.function extractedParserStateValueWire

def parserStateValueExpr : Expr :=
  .index (.local 0)
    (.call extractedParserStateWordFunction.id
      [.local 1, .local 2, .local 3])

def parserStateValueBody : Stmt :=
  .sequence (.returnValue (some parserStateValueExpr)) .skip

def extractedParserStateValueBody : Stmt :=
  extractedParserStateValueFunction.body.getD .skip

theorem extractedParserStateValue_function_shape :
    extractedParserStateValueFunction.id = 11 ∧
      extractedParserStateValueFunction.parameters = [
        (0, .slice parserI32Type),
        (1, parserI32Type),
        (2, parserI32Type),
        (3, parserI32Type)] ∧
      extractedParserStateValueFunction.returnType = parserI32Type ∧
      extractedParserStateValueFunction.body = some parserStateValueBody ∧
      extractedParserStateValueFunction.external = none := by
  exact ⟨rfl, rfl, rfl, rfl, rfl⟩

def extractedParserFindStateWire : CoreFunction :=
  artifact_function%
    (include_str "Artifacts" / "parser.json"),
    "verified_compiler/src/verified/parser.lani",
    "find_state"

def extractedParserFindStateFunction : Function :=
  CoreDecode.function extractedParserFindStateWire

theorem extractedParserFindState_function_signature :
    extractedParserFindStateFunction.id = 12 ∧
      extractedParserFindStateFunction.parameters = [
        (0, .slice parserI32Type),
        (1, parserI32Type),
        (2, parserI32Type),
        (3, .structure 1)] ∧
      extractedParserFindStateFunction.returnType = parserI32Type ∧
      extractedParserFindStateFunction.body.isSome = true ∧
      extractedParserFindStateFunction.external = none := by
  exact ⟨rfl, rfl, rfl, rfl, rfl⟩

def parserFindStateValueExpr (fieldConstant : ConstantId) : Expr :=
  .call extractedParserStateValueFunction.id
    [.local 0, .local 1, .local 4, .constant fieldConstant]

def parserFindFieldMatch
    (fieldConstant : ConstantId) (seedField : FieldId) : Expr :=
  .binary .equal (parserFindStateValueExpr fieldConstant)
    (.field (.local 3) seedField)

def parserFindKeyMatchExpr : Expr :=
  .binary .logicalAnd
    (.binary .logicalAnd
      (parserFindFieldMatch 28 0)
      (parserFindFieldMatch 29 1))
    (parserFindFieldMatch 30 2)

def parserFindReturnCurrent : Stmt :=
  .sequence (.returnValue (some (.local 4))) .skip

def parserFindUpdateCurrent : Stmt :=
  .sequence
    (.expression (.assign .set (.local 4)
      (parserFindStateValueExpr 32)))
    .skip

def parserFindLoopBody : Stmt :=
  .sequence
    (.ifThenElse parserFindKeyMatchExpr parserFindReturnCurrent .skip)
    parserFindUpdateCurrent

def parserFindLoop : Stmt :=
  .whileLoop
    (.binary .greaterEqual (.local 4) (.value (.signed .i32 0)))
    parserFindLoopBody

def parserFindReturnMissing : Stmt :=
  .sequence
    (.returnValue (some
      (.unary .negate (.value (.signed .i32 1)))))
    .skip

def parserFindStateBody : Stmt :=
  .letLocal 4 parserI32Type parserFindChartHeadExpr
    (.sequence parserFindLoop parserFindReturnMissing)

def extractedParserFindStateBody : Stmt :=
  extractedParserFindStateFunction.body.getD .skip

theorem extractedParserFindStateBody_eq :
    extractedParserFindStateBody = parserFindStateBody := by
  rfl

theorem verifiedParserCore_finds_stateValue :
    verifiedParserCore.function? extractedParserStateValueFunction.id =
      some extractedParserStateValueFunction := by
  unfold verifiedParserCore extractedParserStateValueFunction
    extractedParserStateValueWire
  rfl

theorem verifiedParserCore_finds_findState :
    verifiedParserCore.function? extractedParserFindStateFunction.id =
      some extractedParserFindStateFunction := by
  unfold verifiedParserCore extractedParserFindStateFunction
    extractedParserFindStateWire
  rfl

def parserStateValueBindings
    (workspaceValue : Value) (base stateId field : Int) :
    List (VarId × Value) := [
  (0, workspaceValue),
  (1, .signed .i32 base),
  (2, .signed .i32 stateId),
  (3, .signed .i32 field)]

def parserStateValueCallee (state : State)
    (workspaceValue : Value) (base stateId field : Int) : State :=
  enterCall state (parserStateValueBindings workspaceValue base stateId field)

def parserStateValueCallState (state : State)
    (workspaceValue : Value) (base stateId field : Int) : State :=
  let callee := parserStateValueCallee state workspaceValue base stateId field
  let afterWord := restoreLocals callee
    (parserStateWordCallee callee base stateId field)
  restoreLocals state afterWord

theorem parserStateValueCallee_well_formed
    (wellFormed : StateWellFormed state) :
    StateWellFormed
      (parserStateValueCallee state workspaceValue base stateId field) :=
  enterCall_preserves_wellFormed wellFormed

theorem parserStateValueCallState_effect :
    ModifiesOnly CellSet.empty state
      (parserStateValueCallState state workspaceValue base stateId field) := by
  let callee := parserStateValueCallee state workspaceValue base stateId field
  let afterWord := restoreLocals callee
    (parserStateWordCallee callee base stateId field)
  have outer := enterCall_effect state
    (parserStateValueBindings workspaceValue base stateId field)
  have nested := enterCall_effect callee
    (parserStateWordBindings base stateId field)
  have nestedClosed : ModifiesOnly CellSet.empty callee afterWord := by
    simpa [afterWord, parserStateWordCallee] using nested.restoreLocals
  have completed : StoreEffect CellSet.empty state afterWord := by
    exact outer.trans_same nestedClosed.toStoreEffect
  simpa [parserStateValueCallState, callee, afterWord] using
    completed.restoreLocals

theorem parserStateValueCallState_well_formed
    (wellFormed : StateWellFormed state) :
    StateWellFormed
      (parserStateValueCallState state workspaceValue base stateId field) := by
  let callee := parserStateValueCallee state workspaceValue base stateId field
  let nestedCallee := parserStateWordCallee callee base stateId field
  let afterWord := restoreLocals callee nestedCallee
  have calleeWellFormed : StateWellFormed callee :=
    parserStateValueCallee_well_formed wellFormed
  have nestedWellFormed : StateWellFormed nestedCallee :=
    parserStateWordCallee_well_formed calleeWellFormed
  have nested := enterCall_effect callee
    (parserStateWordBindings base stateId field)
  have afterWordWellFormed : StateWellFormed afterWord := by
    exact nested.restoreLocals_wellFormed calleeWellFormed nestedWellFormed
  have outer := enterCall_effect state
    (parserStateValueBindings workspaceValue base stateId field)
  have nestedClosed : ModifiesOnly CellSet.empty callee afterWord := by
    simpa [afterWord, nestedCallee, parserStateWordCallee] using
      nested.restoreLocals
  have completed : StoreEffect CellSet.empty state afterWord :=
    outer.trans_same nestedClosed.toStoreEffect
  simpa [parserStateValueCallState, callee, afterWord, nestedCallee] using
    completed.restoreLocals_wellFormed wellFormed afterWordWellFormed

private theorem parserStateValueCallee_local0
    (wellFormed : StateWellFormed state) :
    (parserStateValueCallee state workspaceValue base stateId field).local? 0 =
      some workspaceValue := by
  let cleared : State := { state with locals := [] }
  have clearedWellFormed : StateWellFormed cleared :=
    clearLocals_preserves_wellFormed wellFormed
  have entry := bindLocals_finds_cell_after_prefix cleared [] [
      (1, .signed .i32 base), (2, .signed .i32 stateId),
      (3, .signed .i32 field)] 0 workspaceValue clearedWellFormed
  have cellId :
      (parserStateValueCallee state workspaceValue base stateId field).cellId? 0 =
        some state.nextCell := by
    rfl
  rw [State.local?, cellId]
  simp only [Option.bind_some, State.cell?]
  rw [show
    (parserStateValueCallee state workspaceValue base stateId field).cellEntry?
        state.nextCell =
      some { id := state.nextCell, value := some workspaceValue } by
    simpa [parserStateValueCallee, parserStateValueBindings, enterCall, cleared]
      using entry]
  rfl

private theorem parserStateValueCallee_local1
    (wellFormed : StateWellFormed state) :
    (parserStateValueCallee state workspaceValue base stateId field).local? 1 =
      some (.signed .i32 base) := by
  let cleared : State := { state with locals := [] }
  have clearedWellFormed := clearLocals_preserves_wellFormed wellFormed
  have entry := bindLocals_finds_cell_after_prefix cleared
    [(0, workspaceValue)] [
      (2, .signed .i32 stateId), (3, .signed .i32 field)]
    1 (.signed .i32 base) clearedWellFormed
  have cellId :
      (parserStateValueCallee state workspaceValue base stateId field).cellId? 1 =
        some (state.nextCell + 1) := by
    rfl
  rw [State.local?, cellId]
  simp only [Option.bind_some, State.cell?]
  rw [show
    (parserStateValueCallee state workspaceValue base stateId field).cellEntry?
        (state.nextCell + 1) = some {
          id := state.nextCell + 1
          value := some (.signed .i32 base)
        } by
    simpa [parserStateValueCallee, parserStateValueBindings, enterCall, cleared]
      using entry]
  rfl

private theorem parserStateValueCallee_local2
    (wellFormed : StateWellFormed state) :
    (parserStateValueCallee state workspaceValue base stateId field).local? 2 =
      some (.signed .i32 stateId) := by
  let cleared : State := { state with locals := [] }
  have clearedWellFormed := clearLocals_preserves_wellFormed wellFormed
  have entry := bindLocals_finds_cell_after_prefix cleared
    [(0, workspaceValue), (1, .signed .i32 base)]
    [(3, .signed .i32 field)] 2 (.signed .i32 stateId) clearedWellFormed
  have cellId :
      (parserStateValueCallee state workspaceValue base stateId field).cellId? 2 =
        some (state.nextCell + 2) := by
    rfl
  rw [State.local?, cellId]
  simp only [Option.bind_some, State.cell?]
  rw [show
    (parserStateValueCallee state workspaceValue base stateId field).cellEntry?
        (state.nextCell + 2) = some {
          id := state.nextCell + 2
          value := some (.signed .i32 stateId)
        } by
    simpa [parserStateValueCallee, parserStateValueBindings, enterCall, cleared]
      using entry]
  rfl

private theorem parserStateValueCallee_local3
    (wellFormed : StateWellFormed state) :
    (parserStateValueCallee state workspaceValue base stateId field).local? 3 =
      some (.signed .i32 field) := by
  let cleared : State := { state with locals := [] }
  have clearedWellFormed := clearLocals_preserves_wellFormed wellFormed
  have entry := bindLocals_finds_cell_after_prefix cleared [
      (0, workspaceValue), (1, .signed .i32 base),
      (2, .signed .i32 stateId)] []
    3 (.signed .i32 field) clearedWellFormed
  have cellId :
      (parserStateValueCallee state workspaceValue base stateId field).cellId? 3 =
        some (state.nextCell + 3) := by
    rfl
  rw [State.local?, cellId]
  simp only [Option.bind_some, State.cell?]
  rw [show
    (parserStateValueCallee state workspaceValue base stateId field).cellEntry?
        (state.nextCell + 3) = some {
          id := state.nextCell + 3
          value := some (.signed .i32 field)
        } by
    simpa [parserStateValueCallee, parserStateValueBindings, enterCall, cleared]
      using entry]
  rfl

theorem extractedParserStateValueBody_eq :
    extractedParserStateValueBody = parserStateValueBody := by
  rfl

theorem extractedParserStateWordCall_evaluates
    (before afterArguments : State) (arguments : List Expr)
    (base stateId field : Int)
    (afterArgumentsWellFormed : StateWellFormed afterArguments)
    (argumentsResult : ArgumentsEvaluateTo verifiedParserCore before arguments
      [.signed .i32 base, .signed .i32 stateId, .signed .i32 field]
      afterArguments) :
    Evaluates verifiedParserCore before
      (.call extractedParserStateWordFunction.id arguments)
      (.signed .i32
        (parserStateWordValue verifiedParserCore.target base stateId field))
      (restoreLocals afterArguments
        (parserStateWordCallee afterArguments base stateId field)) := by
  let callee := parserStateWordCallee afterArguments base stateId field
  have bodyResult : Executes verifiedParserCore callee
      extractedParserStateWordBody
      (.returned (some (.signed .i32
        (parserStateWordValue verifiedParserCore.target base stateId field))))
      callee := by
    exact extractedParserStateWordBody_executes callee base stateId field
      (parserStateWordCallee_base afterArgumentsWellFormed)
      (parserStateWordCallee_stateId afterArgumentsWellFormed)
      (parserStateWordCallee_field afterArgumentsWellFormed)
  rw [extractedParserStateWordBody_eq] at bodyResult
  apply evaluatesCallReturned argumentsResult
    verifiedParserCore_finds_stateWord
  · rw [extractedParser_workspace_function_shapes.2.2.2.2.1]
    rfl
  · exact extractedParser_workspace_function_shapes.2.2.2.2.2.2.1
  · simpa [callee, parserStateWordCallee, parserStateWordBindings]
      using bodyResult

/-- `state_value` is an ordinary slice read after its extracted call to
    `state_word`. The call premise is kept modular so the `state_word` call
    contract and the array-read rule can be proved and reused independently. -/
theorem extractedParserStateValueBody_executes
    (program : Program) (before afterWordCall : State)
    (values : List Int) (workspaceCell : CellId) (address : Nat)
    (addressBound : address < values.length)
    (workspaceLocal : before.local? 0 = some
      (.slice parserI32Type workspaceCell [] 0 values.length))
    (wordCall : Evaluates program before
      (.call extractedParserStateWordFunction.id
        [.local 1, .local 2, .local 3])
      (.signed .i32 (Int.ofNat address)) afterWordCall)
    (backing : afterWordCall.cellEntry? workspaceCell = some {
      id := workspaceCell
      value := some (.array (signedI32Values values))
    }) :
    Executes program before extractedParserStateValueBody
      (.returned (some (.signed .i32
        (values.get ⟨address, addressBound⟩)))) afterWordCall := by
  rw [extractedParserStateValueBody_eq]
  apply executesSequenceReturned
  apply executesReturnValue
  apply evaluatesSignedI32SliceIndex program before before afterWordCall
    values (.local 0)
    (.call extractedParserStateWordFunction.id
      [.local 1, .local 2, .local 3])
    workspaceCell address addressBound
  · exact ⟨1, evalLocal_of_local 0 program before 0
      (.slice parserI32Type workspaceCell [] 0 values.length)
      workspaceLocal⟩
  · exact wordCall
  · exact backing

/-- Full source-call semantics for the extracted `state_value` helper.  The
    theorem exposes the caller-visible post-call state, including the fresh
    parameter cells allocated by the nested `state_word` call, while proving
    that the workspace backing cell is preserved. -/
theorem extractedParserStateValueCall_evaluates
    (before afterArguments : State) (arguments : List Expr)
    (workspaceValue : Value) (base stateId field : Int)
    (values : List Int) (workspaceCell : CellId) (address : Nat)
    (addressBound : address < values.length)
    (addressValue :
      parserStateWordValue verifiedParserCore.target base stateId field =
        Int.ofNat address)
    (afterArgumentsWellFormed : StateWellFormed afterArguments)
    (argumentsResult : ArgumentsEvaluateTo verifiedParserCore before arguments
      [workspaceValue, .signed .i32 base, .signed .i32 stateId,
        .signed .i32 field] afterArguments)
    (workspaceShape : workspaceValue =
      .slice parserI32Type workspaceCell [] 0 values.length)
    (backing : afterArguments.cellEntry? workspaceCell = some {
      id := workspaceCell
      value := some (.array (signedI32Values values))
    }) :
    let callee := parserStateValueCallee afterArguments workspaceValue
      base stateId field
    let afterWord := restoreLocals callee
      (parserStateWordCallee callee base stateId field)
    Evaluates verifiedParserCore before
      (.call extractedParserStateValueFunction.id arguments)
      (.signed .i32 (values.get ⟨address, addressBound⟩))
      (restoreLocals afterArguments afterWord) := by
  dsimp only
  let callee := parserStateValueCallee afterArguments workspaceValue
    base stateId field
  let afterWord := restoreLocals callee
    (parserStateWordCallee callee base stateId field)
  have calleeWellFormed : StateWellFormed callee :=
    parserStateValueCallee_well_formed afterArgumentsWellFormed
  have workspaceOld : workspaceCell < afterArguments.nextCell :=
    Lanius.Separation.StateWellFormed.cell_lt_next_of_entry
      afterArgumentsWellFormed backing
  have calleeBacking : callee.cellEntry? workspaceCell = some {
      id := workspaceCell
      value := some (.array (signedI32Values values))
    } := by
    have preserved := (enterCall_effect afterArguments
      (parserStateValueBindings workspaceValue base stateId field)).oldCells
        workspaceCell workspaceOld (by simp [CellSet.empty])
    exact preserved.trans backing
  have local1 : Evaluates verifiedParserCore callee (.local 1)
      (.signed .i32 base) callee :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore callee 1
      (.signed .i32 base)
      (parserStateValueCallee_local1 afterArgumentsWellFormed)⟩
  have local2 : Evaluates verifiedParserCore callee (.local 2)
      (.signed .i32 stateId) callee :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore callee 2
      (.signed .i32 stateId)
      (parserStateValueCallee_local2 afterArgumentsWellFormed)⟩
  have local3 : Evaluates verifiedParserCore callee (.local 3)
      (.signed .i32 field) callee :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore callee 3
      (.signed .i32 field)
      (parserStateValueCallee_local3 afterArgumentsWellFormed)⟩
  have wordArguments : ArgumentsEvaluateTo verifiedParserCore callee
      [.local 1, .local 2, .local 3]
      [.signed .i32 base, .signed .i32 stateId, .signed .i32 field]
      callee :=
    ArgumentsEvaluateTo.cons local1
      (ArgumentsEvaluateTo.cons local2
        (ArgumentsEvaluateTo.singleton local3))
  have wordCall : Evaluates verifiedParserCore callee
      (.call extractedParserStateWordFunction.id
        [.local 1, .local 2, .local 3])
      (.signed .i32 (Int.ofNat address)) afterWord := by
    have result := extractedParserStateWordCall_evaluates callee callee
      [.local 1, .local 2, .local 3] base stateId field calleeWellFormed
      wordArguments
    rw [addressValue] at result
    simpa [afterWord] using result
  have calleeWorkspace : callee.local? 0 = some
      (.slice parserI32Type workspaceCell [] 0 values.length) := by
    rw [← workspaceShape]
    exact parserStateValueCallee_local0 afterArgumentsWellFormed
  have calleeWorkspaceOld : workspaceCell < callee.nextCell :=
    Lanius.Separation.StateWellFormed.cell_lt_next_of_entry
      calleeWellFormed calleeBacking
  have afterWordBacking : afterWord.cellEntry? workspaceCell = some {
      id := workspaceCell
      value := some (.array (signedI32Values values))
    } := by
    have nestedEffect := enterCall_effect callee
      (parserStateWordBindings base stateId field)
    have restored := nestedEffect.restoreLocals
    have preserved := restored.oldCells workspaceCell calleeWorkspaceOld
      (by simp [CellSet.empty])
    exact preserved.trans calleeBacking
  have bodyResult : Executes verifiedParserCore callee parserStateValueBody
      (.returned (some (.signed .i32
        (values.get ⟨address, addressBound⟩)))) afterWord := by
    have result := extractedParserStateValueBody_executes verifiedParserCore
      callee afterWord values workspaceCell address addressBound
      calleeWorkspace wordCall afterWordBacking
    rw [extractedParserStateValueBody_eq] at result
    exact result
  apply evaluatesCallReturned argumentsResult verifiedParserCore_finds_stateValue
  · rw [extractedParserStateValue_function_shape.2.1]
    rfl
  · exact extractedParserStateValue_function_shape.2.2.2.1
  · simpa [callee, afterWord, parserStateValueCallee,
      parserStateValueBindings] using bodyResult

theorem extractedParserStateValueCall_reads_encoded
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (values : List Int) (workspaceCell : CellId)
    (valuesLength : values.length = layout.workspaceLength)
    (encoded : EncodesWorkspace layout workspace (listWords values))
    (state : EarleyState) (stateId field : Nat)
    (found : workspace.state? stateId = some state)
    (fieldBound : field < stateWords)
    (before afterArguments : State) (arguments : List Expr)
    (afterArgumentsWellFormed : StateWellFormed afterArguments)
    (argumentsResult : ArgumentsEvaluateTo verifiedParserCore before arguments [
      .slice parserI32Type workspaceCell [] 0 values.length,
      .signed .i32 (Int.ofNat (stateBase layout.tokenCount)),
      .signed .i32 (Int.ofNat stateId),
      .signed .i32 (Int.ofNat field)] afterArguments)
    (backing : afterArguments.cellEntry? workspaceCell = some {
      id := workspaceCell
      value := some (.array (signedI32Values values))
    }) :
    let workspaceValue :=
      .slice parserI32Type workspaceCell [] 0 values.length
    let callee := parserStateValueCallee afterArguments workspaceValue
      (Int.ofNat (stateBase layout.tokenCount)) (Int.ofNat stateId)
      (Int.ofNat field)
    let afterWord := restoreLocals callee
      (parserStateWordCallee callee
        (Int.ofNat (stateBase layout.tokenCount)) (Int.ofNat stateId)
        (Int.ofNat field))
    Evaluates verifiedParserCore before
      (.call extractedParserStateValueFunction.id arguments)
      (.signed .i32 (stateFieldValue workspace stateId state field))
      (restoreLocals afterArguments afterWord) := by
  dsimp only
  let address := stateWord (stateBase layout.tokenCount) stateId field
  have addressBound : address < values.length := by
    have workspaceBound := encoded.state_address_valid found fieldBound
    rw [valuesLength]
    exact workspaceBound
  have addressValue :
      parserStateWordValue verifiedParserCore.target
          (Int.ofNat (stateBase layout.tokenCount)) (Int.ofNat stateId)
          (Int.ofNat field) = Int.ofNat address :=
    layout.state_value_eq_address (encoded.state_id_lt_capacity found)
      fieldBound
  have fieldRead : values.get ⟨address, addressBound⟩ =
      stateFieldValue workspace stateId state field := by
    have concrete := encoded.stateField stateId state found field fieldBound
    rw [listWords_get values address addressBound] at concrete
    exact concrete
  have result := extractedParserStateValueCall_evaluates before afterArguments
    arguments
    (.slice parserI32Type workspaceCell [] 0 values.length)
    (Int.ofNat (stateBase layout.tokenCount)) (Int.ofNat stateId)
    (Int.ofNat field) values workspaceCell address addressBound addressValue
    afterArgumentsWellFormed argumentsResult rfl backing
  rw [fieldRead] at result
  exact result

end Lanius.Extraction
