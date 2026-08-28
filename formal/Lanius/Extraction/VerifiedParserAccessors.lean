import Lanius.Extraction.VerifiedParserBasics
import Lanius.Compiler.ParserGrammar

namespace Lanius.Extraction.ParserAccessors

open Lanius.Core
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.CallContracts
open Lanius.Extraction
open Lanius.Compiler.Parser

def extractedParserRhsLengthWire : CoreFunction :=
  artifact_function%
    (include_str "Artifacts" / "parser.json"),
    "verified_compiler/src/verified/parser.lani",
    "production_rhs_length"

def extractedParserRhsLengthFunction : Function :=
  CoreDecode.function extractedParserRhsLengthWire

def extractedParserLhsWire : CoreFunction :=
  artifact_function%
    (include_str "Artifacts" / "parser.json"),
    "verified_compiler/src/verified/parser.lani",
    "production_lhs"

def extractedParserLhsFunction : Function :=
  CoreDecode.function extractedParserLhsWire

def extractedParserRhsSymbolWire : CoreFunction :=
  artifact_function%
    (include_str "Artifacts" / "parser.json"),
    "verified_compiler/src/verified/parser.lani",
    "production_rhs_symbol"

def extractedParserRhsSymbolFunction : Function :=
  CoreDecode.function extractedParserRhsSymbolWire

def parserGrammarValue (values : List Int) (cell : CellId) : Value :=
  .slice parserI32Type cell [] 0 values.length

def parserTableReadFromExpr
    (headerConstant : ConstantId) (rowExpression : Expr) : Expr :=
  .index (.local 0)
    (.binary .add
      (.index (.local 0) (.constant headerConstant))
      rowExpression)

def parserTableReadExpr (headerConstant : ConstantId) : Expr :=
  parserTableReadFromExpr headerConstant (.local 1)

def parserTableReadBody (headerConstant : ConstantId) : Stmt :=
  .sequence (.returnValue (some (parserTableReadExpr headerConstant))) .skip

def parserRhsSymbolAddressExpr : Expr :=
  .binary .add
    (.binary .add
      (.index (.local 0) (.constant 18))
      (.local 3))
    (.local 2)

def parserRhsSymbolBody : Stmt :=
  .letLocal 3 parserI32Type (parserTableReadExpr 16)
    (.sequence
      (.returnValue (some (.index (.local 0) parserRhsSymbolAddressExpr)))
      .skip)

def extractedParserRhsLengthBody : Stmt :=
  extractedParserRhsLengthFunction.body.getD .skip

def extractedParserLhsBody : Stmt :=
  extractedParserLhsFunction.body.getD .skip

def extractedParserRhsSymbolBody : Stmt :=
  extractedParserRhsSymbolFunction.body.getD .skip

theorem extractedParser_accessor_shapes :
    extractedParserRhsLengthFunction.id = 14 ∧
      extractedParserRhsLengthFunction.parameters = [
        (0, .slice parserI32Type), (1, parserI32Type)] ∧
      extractedParserRhsLengthFunction.returnType = parserI32Type ∧
      extractedParserRhsLengthFunction.body = some (parserTableReadBody 17) ∧
      extractedParserRhsLengthFunction.external = none ∧
      extractedParserLhsFunction.id = 16 ∧
      extractedParserLhsFunction.parameters = [
        (0, .slice parserI32Type), (1, parserI32Type)] ∧
      extractedParserLhsFunction.returnType = parserI32Type ∧
      extractedParserLhsFunction.body = some (parserTableReadBody 15) ∧
      extractedParserLhsFunction.external = none := by
  exact ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩

theorem extractedParserRhsLengthBody_eq :
    extractedParserRhsLengthBody = parserTableReadBody 17 := by
  rfl

theorem extractedParserLhsBody_eq :
    extractedParserLhsBody = parserTableReadBody 15 := by
  rfl

theorem extractedParserRhsSymbol_function_shape :
    extractedParserRhsSymbolFunction.id = 15 ∧
      extractedParserRhsSymbolFunction.parameters = [
        (0, .slice parserI32Type), (1, parserI32Type),
        (2, parserI32Type)] ∧
      extractedParserRhsSymbolFunction.returnType = parserI32Type ∧
      extractedParserRhsSymbolFunction.body = some parserRhsSymbolBody ∧
      extractedParserRhsSymbolFunction.external = none := by
  exact ⟨rfl, rfl, rfl, rfl, rfl⟩

theorem extractedParserRhsSymbolBody_eq :
    extractedParserRhsSymbolBody = parserRhsSymbolBody := by
  rfl

theorem verifiedParser_accessor_constants :
    verifiedParserCore.constant? 17 = some {
        id := 17
        type := parserI32Type
        value := .signed .i32 10
      } ∧
      verifiedParserCore.constant? 15 = some {
        id := 15
        type := parserI32Type
        value := .signed .i32 8
      } := by
  have evidence :
      (verifiedParserCore.constant? 17).map (fun declaration =>
        (declaration.id, declaration.type,
          signedI32ConstantValue? declaration.value)) =
          some (17, parserI32Type, some 10) ∧
      (verifiedParserCore.constant? 15).map (fun declaration =>
        (declaration.id, declaration.type,
          signedI32ConstantValue? declaration.value)) =
          some (15, parserI32Type, some 8) := by
    native_decide
  exact ⟨
    constant_eq_of_signed_i32_evidence verifiedParserCore 17 10 evidence.1,
    constant_eq_of_signed_i32_evidence verifiedParserCore 15 8 evidence.2⟩

theorem verifiedParser_rhs_symbol_constants :
    verifiedParserCore.constant? 16 = some {
        id := 16
        type := parserI32Type
        value := .signed .i32 9
      } ∧
      verifiedParserCore.constant? 18 = some {
        id := 18
        type := parserI32Type
        value := .signed .i32 11
      } := by
  have evidence :
      (verifiedParserCore.constant? 16).map (fun declaration =>
        (declaration.id, declaration.type,
          signedI32ConstantValue? declaration.value)) =
          some (16, parserI32Type, some 9) ∧
      (verifiedParserCore.constant? 18).map (fun declaration =>
        (declaration.id, declaration.type,
          signedI32ConstantValue? declaration.value)) =
          some (18, parserI32Type, some 11) := by
    native_decide
  exact ⟨
    constant_eq_of_signed_i32_evidence verifiedParserCore 16 9 evidence.1,
    constant_eq_of_signed_i32_evidence verifiedParserCore 18 11 evidence.2⟩

/-- Read one fixed header word from a caller-owned packed grammar. -/
theorem evaluatesParserHeaderRead
    (values : List Int) (grammarCell : CellId)
    (headerConstant : ConstantId) (headerIndex : Nat)
    (headerBound : headerIndex < values.length)
    (state : State)
    (grammarLocal : state.local? 0 =
      some (parserGrammarValue values grammarCell))
    (backing : state.cellEntry? grammarCell = some {
      id := grammarCell
      value := some (.array (signedI32Values values))
    })
    (constantFound : verifiedParserCore.constant? headerConstant = some {
      id := headerConstant
      type := parserI32Type
      value := .signed .i32 (Int.ofNat headerIndex)
    }) :
    Evaluates verifiedParserCore state
      (.index (.local 0) (.constant headerConstant))
      (.signed .i32 (values.get ⟨headerIndex, headerBound⟩)) state := by
  have grammarResult : Evaluates verifiedParserCore state (.local 0)
      (parserGrammarValue values grammarCell) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 0
      (parserGrammarValue values grammarCell) grammarLocal⟩
  have headerIndexResult : Evaluates verifiedParserCore state
      (.constant headerConstant) (.signed .i32 (Int.ofNat headerIndex)) state :=
    evaluatesConstant constantFound
  exact evaluatesSignedI32SliceIndex verifiedParserCore state state state values
    (.local 0) (.constant headerConstant) grammarCell headerIndex headerBound
    grammarResult headerIndexResult backing

/-- Expression-parametric semantic rule for the packed grammar's indirect
    tables: `grammar[grammar[header] + row]`. The row expression may be a
    local, a calculated index, or a call result; both physical reads and the
    address addition remain hidden behind one checked rule. -/
theorem evaluatesParserTableReadFrom
    (values : List Int) (grammarCell : CellId)
    (headerConstant : ConstantId) (headerIndex tableOffset row : Nat)
    (headerBound : headerIndex < values.length)
    (headerValue : values.get ⟨headerIndex, headerBound⟩ =
      Int.ofNat tableOffset)
    (addressBound : tableOffset + row < values.length)
    (valuesI32 : values.length ≤ 2147483647)
    (state : State)
    (grammarLocal : state.local? 0 =
      some (parserGrammarValue values grammarCell))
    (rowExpression : Expr)
    (rowResult : Evaluates verifiedParserCore state rowExpression
      (.signed .i32 (Int.ofNat row)) state)
    (backing : state.cellEntry? grammarCell = some {
      id := grammarCell
      value := some (.array (signedI32Values values))
    })
    (constantFound : verifiedParserCore.constant? headerConstant = some {
      id := headerConstant
      type := parserI32Type
      value := .signed .i32 (Int.ofNat headerIndex)
    }) :
    Evaluates verifiedParserCore state
      (parserTableReadFromExpr headerConstant rowExpression)
      (.signed .i32
        (values.get ⟨tableOffset + row, addressBound⟩)) state := by
  have grammarResult : Evaluates verifiedParserCore state (.local 0)
      (parserGrammarValue values grammarCell) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 0
      (parserGrammarValue values grammarCell) grammarLocal⟩
  have headerRead : Evaluates verifiedParserCore state
      (.index (.local 0) (.constant headerConstant))
      (.signed .i32 (Int.ofNat tableOffset)) state := by
    have read := evaluatesParserHeaderRead values grammarCell headerConstant
      headerIndex headerBound state grammarLocal backing constantFound
    rw [headerValue] at read
    exact read
  have addressI32 : tableOffset + row ≤ 2147483647 :=
    Nat.le_trans (Nat.le_of_lt addressBound) valuesI32
  have addressWrap := wrapSigned_i32_ofNat verifiedParserCore.target
    (tableOffset + row) addressI32
  have castAddress :
      Int.ofNat tableOffset + Int.ofNat row =
        Int.ofNat (tableOffset + row) := by
    exact (Int.natCast_add tableOffset row).symm
  have addressResult : Evaluates verifiedParserCore state
      (.binary .add
        (.index (.local 0) (.constant headerConstant)) rowExpression)
      (.signed .i32 (Int.ofNat (tableOffset + row))) state := by
    apply evaluatesEagerBinary (by decide) (by decide) headerRead rowResult
    simp only [evalBinaryValue, evalSignedBinary]
    rw [castAddress, addressWrap]
    simp
  exact evaluatesSignedI32SliceIndex verifiedParserCore state state state values
    (.local 0)
    (.binary .add
      (.index (.local 0) (.constant headerConstant)) rowExpression)
    grammarCell (tableOffset + row) addressBound grammarResult addressResult
    backing

/-- Read a packed grammar table through an offset already held in a local or
    prior expression. Validator loops hoist table offsets out of their bodies;
    this rule keeps those direct indexed reads at the same abstraction level
    as `evaluatesParserTableReadFrom`. -/
theorem evaluatesParserDirectTableRead
    (values : List Int) (grammarCell : CellId)
    (tableOffset row : Nat)
    (addressBound : tableOffset + row < values.length)
    (valuesI32 : values.length ≤ 2147483647)
    (state : State)
    (grammarLocal : state.local? 0 =
      some (parserGrammarValue values grammarCell))
    (offsetExpression rowExpression : Expr)
    (offsetResult : Evaluates verifiedParserCore state offsetExpression
      (.signed .i32 (Int.ofNat tableOffset)) state)
    (rowResult : Evaluates verifiedParserCore state rowExpression
      (.signed .i32 (Int.ofNat row)) state)
    (backing : state.cellEntry? grammarCell = some {
      id := grammarCell
      value := some (.array (signedI32Values values))
    }) :
    Evaluates verifiedParserCore state
      (.index (.local 0) (.binary .add offsetExpression rowExpression))
      (.signed .i32
        (values.get ⟨tableOffset + row, addressBound⟩)) state := by
  have grammarResult : Evaluates verifiedParserCore state (.local 0)
      (parserGrammarValue values grammarCell) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 0
      (parserGrammarValue values grammarCell) grammarLocal⟩
  have addressI32 : tableOffset + row ≤ 2147483647 :=
    Nat.le_trans (Nat.le_of_lt addressBound) valuesI32
  have addressWrap := wrapSigned_i32_ofNat verifiedParserCore.target
    (tableOffset + row) addressI32
  have castAddress :
      Int.ofNat tableOffset + Int.ofNat row =
        Int.ofNat (tableOffset + row) := by
    exact (Int.natCast_add tableOffset row).symm
  have addressResult : Evaluates verifiedParserCore state
      (.binary .add offsetExpression rowExpression)
      (.signed .i32 (Int.ofNat (tableOffset + row))) state := by
    apply evaluatesEagerBinary (by decide) (by decide) offsetResult rowResult
    simp only [evalBinaryValue, evalSignedBinary]
    rw [castAddress, addressWrap]
    simp
  exact evaluatesSignedI32SliceIndex verifiedParserCore state state state values
    (.local 0) (.binary .add offsetExpression rowExpression)
    grammarCell (tableOffset + row) addressBound grammarResult addressResult
    backing

/-- Common specialization of `evaluatesParserTableReadFrom` for grammar
    accessors whose row is stored in parameter local 1. -/
theorem evaluatesParserTableRead
    (values : List Int) (grammarCell : CellId)
    (headerConstant : ConstantId) (headerIndex tableOffset row : Nat)
    (headerBound : headerIndex < values.length)
    (headerValue : values.get ⟨headerIndex, headerBound⟩ =
      Int.ofNat tableOffset)
    (addressBound : tableOffset + row < values.length)
    (valuesI32 : values.length ≤ 2147483647)
    (state : State)
    (grammarLocal : state.local? 0 =
      some (parserGrammarValue values grammarCell))
    (rowLocal : state.local? 1 = some (.signed .i32 (Int.ofNat row)))
    (backing : state.cellEntry? grammarCell = some {
      id := grammarCell
      value := some (.array (signedI32Values values))
    })
    (constantFound : verifiedParserCore.constant? headerConstant = some {
      id := headerConstant
      type := parserI32Type
      value := .signed .i32 (Int.ofNat headerIndex)
    }) :
    Evaluates verifiedParserCore state (parserTableReadExpr headerConstant)
      (.signed .i32
        (values.get ⟨tableOffset + row, addressBound⟩)) state := by
  have rowResult : Evaluates verifiedParserCore state (.local 1)
      (.signed .i32 (Int.ofNat row)) state :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore state 1
      (.signed .i32 (Int.ofNat row)) rowLocal⟩
  simpa [parserTableReadExpr] using
    evaluatesParserTableReadFrom values grammarCell headerConstant
    headerIndex tableOffset row headerBound headerValue addressBound valuesI32
    state grammarLocal (.local 1) rowResult backing constantFound

theorem executesParserTableReadBody
    (values : List Int) (grammarCell : CellId)
    (headerConstant : ConstantId) (headerIndex tableOffset row : Nat)
    (headerBound : headerIndex < values.length)
    (headerValue : values.get ⟨headerIndex, headerBound⟩ =
      Int.ofNat tableOffset)
    (addressBound : tableOffset + row < values.length)
    (valuesI32 : values.length ≤ 2147483647)
    (state : State)
    (grammarLocal : state.local? 0 =
      some (parserGrammarValue values grammarCell))
    (rowLocal : state.local? 1 = some (.signed .i32 (Int.ofNat row)))
    (backing : state.cellEntry? grammarCell = some {
      id := grammarCell
      value := some (.array (signedI32Values values))
    })
    (constantFound : verifiedParserCore.constant? headerConstant = some {
      id := headerConstant
      type := parserI32Type
      value := .signed .i32 (Int.ofNat headerIndex)
    }) :
    Executes verifiedParserCore state (parserTableReadBody headerConstant)
      (.returned (some (.signed .i32
        (values.get ⟨tableOffset + row, addressBound⟩)))) state := by
  apply executesSequenceReturned
  apply executesReturnValue
  exact evaluatesParserTableRead values grammarCell headerConstant headerIndex
    tableOffset row headerBound headerValue addressBound valuesI32 state
    grammarLocal rowLocal backing constantFound

theorem extractedParserRhsSymbolBody_executes
    (values : List Int) (grammarCell : CellId)
    (production dot rhsOffsetsOffset relative rhsSymbolsOffset : Nat)
    (rhsOffsetsHeaderBound : 9 < values.length)
    (rhsOffsetsHeader : values.get ⟨9, rhsOffsetsHeaderBound⟩ =
      Int.ofNat rhsOffsetsOffset)
    (rhsOffsetAddressBound :
      rhsOffsetsOffset + production < values.length)
    (relativeValue :
      values.get ⟨rhsOffsetsOffset + production, rhsOffsetAddressBound⟩ =
        Int.ofNat relative)
    (rhsSymbolsHeaderBound : 11 < values.length)
    (rhsSymbolsHeader : values.get ⟨11, rhsSymbolsHeaderBound⟩ =
      Int.ofNat rhsSymbolsOffset)
    (symbolAddressBound :
      rhsSymbolsOffset + relative + dot < values.length)
    (valuesI32 : values.length ≤ 2147483647)
    (state : State) (stateWellFormed : StateWellFormed state)
    (grammarLocal : state.local? 0 =
      some (parserGrammarValue values grammarCell))
    (productionLocal : state.local? 1 =
      some (.signed .i32 (Int.ofNat production)))
    (dotLocal : state.local? 2 = some (.signed .i32 (Int.ofNat dot)))
    (backing : state.cellEntry? grammarCell = some {
      id := grammarCell
      value := some (.array (signedI32Values values))
    }) :
    let relativeState := state.bindLocal 3
      (.signed .i32 (Int.ofNat relative))
    Executes verifiedParserCore state extractedParserRhsSymbolBody
      (.returned (some (.signed .i32
        (values.get ⟨rhsSymbolsOffset + relative + dot,
          symbolAddressBound⟩))))
      (restoreLocals state relativeState) := by
  dsimp only
  let relativeState := state.bindLocal 3
    (.signed .i32 (Int.ofNat relative))
  have initializer : Evaluates verifiedParserCore state
      (parserTableReadExpr 16) (.signed .i32 (Int.ofNat relative)) state := by
    have read := evaluatesParserTableRead values grammarCell 16 9
      rhsOffsetsOffset production rhsOffsetsHeaderBound rhsOffsetsHeader
      rhsOffsetAddressBound valuesI32 state grammarLocal productionLocal
      backing verifiedParser_rhs_symbol_constants.1
    rw [relativeValue] at read
    exact read
  have relativeWellFormed : StateWellFormed relativeState := by
    exact bindLocal_preserves_well_formed state 3
      (.signed .i32 (Int.ofNat relative)) stateWellFormed
  have grammarAfter : relativeState.local? 0 =
      some (parserGrammarValue values grammarCell) := by
    exact (bindLocal_preserves_other_local stateWellFormed (by decide : 3 ≠ 0))
      |>.trans grammarLocal
  have dotAfter : relativeState.local? 2 =
      some (.signed .i32 (Int.ofNat dot)) := by
    exact (bindLocal_preserves_other_local stateWellFormed (by decide : 3 ≠ 2))
      |>.trans dotLocal
  have relativeAfter : relativeState.local? 3 =
      some (.signed .i32 (Int.ofNat relative)) := by
    exact bindLocal_finds_local state 3 (.signed .i32 (Int.ofNat relative))
      stateWellFormed
  have grammarOld : grammarCell < state.nextCell :=
    Lanius.Separation.StateWellFormed.cell_lt_next_of_entry
      stateWellFormed backing
  have backingAfter : relativeState.cellEntry? grammarCell = some {
      id := grammarCell
      value := some (.array (signedI32Values values))
    } := by
    exact ((bindLocal_effect state 3 (.signed .i32 (Int.ofNat relative)))
      |>.oldCells grammarCell grammarOld (by simp [CellSet.empty])).trans backing
  have grammarResult : Evaluates verifiedParserCore relativeState (.local 0)
      (parserGrammarValue values grammarCell) relativeState :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore relativeState 0
      (parserGrammarValue values grammarCell) grammarAfter⟩
  have symbolsHeaderRead : Evaluates verifiedParserCore relativeState
      (.index (.local 0) (.constant 18))
      (.signed .i32 (Int.ofNat rhsSymbolsOffset)) relativeState := by
    have read := evaluatesParserHeaderRead values grammarCell 18 11
      rhsSymbolsHeaderBound relativeState grammarAfter backingAfter
      verifiedParser_rhs_symbol_constants.2
    rw [rhsSymbolsHeader] at read
    exact read
  have relativeResult : Evaluates verifiedParserCore relativeState (.local 3)
      (.signed .i32 (Int.ofNat relative)) relativeState :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore relativeState 3
      (.signed .i32 (Int.ofNat relative)) relativeAfter⟩
  have partialBound : rhsSymbolsOffset + relative < values.length := by
    omega
  have partialI32 : rhsSymbolsOffset + relative ≤ 2147483647 :=
    Nat.le_trans (Nat.le_of_lt partialBound) valuesI32
  have partialWrap := wrapSigned_i32_ofNat verifiedParserCore.target
    (rhsSymbolsOffset + relative) partialI32
  have headerRelativeCast :
      Int.ofNat rhsSymbolsOffset + Int.ofNat relative =
        Int.ofNat (rhsSymbolsOffset + relative) :=
    (Int.natCast_add rhsSymbolsOffset relative).symm
  have partialAddress : Evaluates verifiedParserCore relativeState
      (.binary .add (.index (.local 0) (.constant 18)) (.local 3))
      (.signed .i32 (Int.ofNat (rhsSymbolsOffset + relative)))
      relativeState := by
    apply evaluatesEagerBinary (by decide) (by decide) symbolsHeaderRead
      relativeResult
    simp only [evalBinaryValue, evalSignedBinary]
    rw [headerRelativeCast, partialWrap]
    simp
  have dotResult : Evaluates verifiedParserCore relativeState (.local 2)
      (.signed .i32 (Int.ofNat dot)) relativeState :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore relativeState 2
      (.signed .i32 (Int.ofNat dot)) dotAfter⟩
  have symbolI32 : rhsSymbolsOffset + relative + dot ≤ 2147483647 :=
    Nat.le_trans (Nat.le_of_lt symbolAddressBound) valuesI32
  have symbolWrap := wrapSigned_i32_ofNat verifiedParserCore.target
    (rhsSymbolsOffset + relative + dot) symbolI32
  have symbolCast :
      Int.ofNat (rhsSymbolsOffset + relative) + Int.ofNat dot =
        Int.ofNat (rhsSymbolsOffset + relative + dot) :=
    (Int.natCast_add (rhsSymbolsOffset + relative) dot).symm
  have addressResult : Evaluates verifiedParserCore relativeState
      parserRhsSymbolAddressExpr
      (.signed .i32 (Int.ofNat (rhsSymbolsOffset + relative + dot)))
      relativeState := by
    apply evaluatesEagerBinary (by decide) (by decide) partialAddress dotResult
    simp only [evalBinaryValue, evalSignedBinary]
    rw [symbolCast, symbolWrap]
    simp
  have symbolRead : Evaluates verifiedParserCore relativeState
      (.index (.local 0) parserRhsSymbolAddressExpr)
      (.signed .i32 (values.get ⟨rhsSymbolsOffset + relative + dot,
        symbolAddressBound⟩)) relativeState :=
    evaluatesSignedI32SliceIndex verifiedParserCore relativeState
      relativeState relativeState values (.local 0) parserRhsSymbolAddressExpr
      grammarCell (rhsSymbolsOffset + relative + dot) symbolAddressBound
      grammarResult addressResult backingAfter
  have returned : Executes verifiedParserCore relativeState
      (.sequence
        (.returnValue (some (.index (.local 0) parserRhsSymbolAddressExpr)))
        .skip)
      (.returned (some (.signed .i32
        (values.get ⟨rhsSymbolsOffset + relative + dot,
          symbolAddressBound⟩)))) relativeState := by
    apply executesSequenceReturned
    apply executesReturnValue
    exact symbolRead
  rw [extractedParserRhsSymbolBody_eq]
  exact executesLetLocal initializer returned

def parserGrammarRowBindings
    (values : List Int) (grammarCell : CellId) (row : Nat) :
    List (VarId × Value) := [
  (0, parserGrammarValue values grammarCell),
  (1, .signed .i32 (Int.ofNat row))]

def parserGrammarRowCallee
    (caller : State) (values : List Int) (grammarCell : CellId) (row : Nat) :
    State :=
  enterCall caller (parserGrammarRowBindings values grammarCell row)

structure GrammarRowEntry
    (values : List Int) (grammarCell : CellId) (row : Nat)
    (caller : State) : Prop where
  valuesI32 : values.length ≤ 2147483647
  wellFormed : StateWellFormed caller
  backing : caller.cellEntry? grammarCell = some {
    id := grammarCell
    value := some (.array (signedI32Values values))
  }

theorem GrammarRowEntry.callee_wellFormed
    (entry : GrammarRowEntry values grammarCell row caller) :
    StateWellFormed (parserGrammarRowCallee caller values grammarCell row) :=
  enterCall_preserves_wellFormed entry.wellFormed

theorem GrammarRowEntry.callee_backing
    (entry : GrammarRowEntry values grammarCell row caller) :
    (parserGrammarRowCallee caller values grammarCell row).cellEntry?
        grammarCell = some {
      id := grammarCell
      value := some (.array (signedI32Values values))
    } := by
  have old : grammarCell < caller.nextCell :=
    Lanius.Separation.StateWellFormed.cell_lt_next_of_entry
      entry.wellFormed entry.backing
  exact ((enterCall_effect caller
    (parserGrammarRowBindings values grammarCell row)).oldCells
      grammarCell old (by simp [CellSet.empty])).trans entry.backing

theorem GrammarRowEntry.callee_grammar
    (entry : GrammarRowEntry values grammarCell row caller) :
    (parserGrammarRowCallee caller values grammarCell row).local? 0 =
      some (parserGrammarValue values grammarCell) := by
  simpa [parserGrammarRowCallee, parserGrammarRowBindings] using
    (enterCall_local_of_binding caller [] [
      (1, .signed .i32 (Int.ofNat row))]
      0 (parserGrammarValue values grammarCell) entry.wellFormed (by simp))

theorem GrammarRowEntry.callee_row
    (entry : GrammarRowEntry values grammarCell row caller) :
    (parserGrammarRowCallee caller values grammarCell row).local? 1 =
      some (.signed .i32 (Int.ofNat row)) := by
  simpa [parserGrammarRowCallee, parserGrammarRowBindings] using
    (enterCall_local_of_binding caller [
      (0, parserGrammarValue values grammarCell)] []
      1 (.signed .i32 (Int.ofNat row)) entry.wellFormed (by simp))

theorem verifiedParserCore_finds_rhsLength :
    verifiedParserCore.function? extractedParserRhsLengthFunction.id =
      some extractedParserRhsLengthFunction := by
  unfold verifiedParserCore extractedParserRhsLengthFunction
    extractedParserRhsLengthWire
  rfl

theorem verifiedParserCore_finds_lhs :
    verifiedParserCore.function? extractedParserLhsFunction.id =
      some extractedParserLhsFunction := by
  unfold verifiedParserCore extractedParserLhsFunction extractedParserLhsWire
  rfl

theorem verifiedParserCore_finds_rhsSymbol :
    verifiedParserCore.function? extractedParserRhsSymbolFunction.id =
      some extractedParserRhsSymbolFunction := by
  unfold verifiedParserCore extractedParserRhsSymbolFunction
    extractedParserRhsSymbolWire
  rfl

theorem extractedParserRhsLengthCall_evaluates
    (values : List Int) (grammarCell : CellId) (production : Nat)
    (rhsLengthsOffset : Nat)
    (headerBound : 10 < values.length)
    (headerValue : values.get ⟨10, headerBound⟩ =
      Int.ofNat rhsLengthsOffset)
    (addressBound : rhsLengthsOffset + production < values.length)
    (before afterArguments : State) (arguments : List Expr)
    (entry : GrammarRowEntry values grammarCell production afterArguments)
    (argumentsResult : ArgumentsEvaluateTo verifiedParserCore before arguments [
      parserGrammarValue values grammarCell,
      .signed .i32 (Int.ofNat production)] afterArguments) :
    let callee := parserGrammarRowCallee afterArguments values grammarCell
      production
    let after := restoreLocals afterArguments callee
    Evaluates verifiedParserCore before
      (.call extractedParserRhsLengthFunction.id arguments)
      (.signed .i32
        (values.get ⟨rhsLengthsOffset + production, addressBound⟩)) after := by
  dsimp only
  let callee := parserGrammarRowCallee afterArguments values grammarCell
    production
  let after := restoreLocals afterArguments callee
  have body : Executes verifiedParserCore callee (parserTableReadBody 17)
      (.returned (some (.signed .i32
        (values.get ⟨rhsLengthsOffset + production, addressBound⟩))))
      callee := by
    exact executesParserTableReadBody values grammarCell 17 10
      rhsLengthsOffset production headerBound headerValue addressBound
      entry.valuesI32 callee entry.callee_grammar entry.callee_row
      entry.callee_backing verifiedParser_accessor_constants.1
  apply evaluatesCallReturned argumentsResult verifiedParserCore_finds_rhsLength
  · rw [extractedParser_accessor_shapes.2.1]
    rfl
  · exact extractedParser_accessor_shapes.2.2.2.1
  · simpa [callee, after, parserGrammarRowCallee,
      parserGrammarRowBindings] using body

theorem extractedParserLhsCall_evaluates
    (values : List Int) (grammarCell : CellId) (production : Nat)
    (lhsOffset : Nat)
    (headerBound : 8 < values.length)
    (headerValue : values.get ⟨8, headerBound⟩ = Int.ofNat lhsOffset)
    (addressBound : lhsOffset + production < values.length)
    (before afterArguments : State) (arguments : List Expr)
    (entry : GrammarRowEntry values grammarCell production afterArguments)
    (argumentsResult : ArgumentsEvaluateTo verifiedParserCore before arguments [
      parserGrammarValue values grammarCell,
      .signed .i32 (Int.ofNat production)] afterArguments) :
    let callee := parserGrammarRowCallee afterArguments values grammarCell
      production
    let after := restoreLocals afterArguments callee
    Evaluates verifiedParserCore before
      (.call extractedParserLhsFunction.id arguments)
      (.signed .i32
        (values.get ⟨lhsOffset + production, addressBound⟩)) after := by
  dsimp only
  let callee := parserGrammarRowCallee afterArguments values grammarCell
    production
  let after := restoreLocals afterArguments callee
  have body : Executes verifiedParserCore callee (parserTableReadBody 15)
      (.returned (some (.signed .i32
        (values.get ⟨lhsOffset + production, addressBound⟩))))
      callee := by
    exact executesParserTableReadBody values grammarCell 15 8 lhsOffset
      production headerBound headerValue addressBound entry.valuesI32 callee
      entry.callee_grammar entry.callee_row entry.callee_backing
      verifiedParser_accessor_constants.2
  apply evaluatesCallReturned argumentsResult verifiedParserCore_finds_lhs
  · rw [extractedParser_accessor_shapes.2.2.2.2.2.2.1]
    rfl
  · exact extractedParser_accessor_shapes.2.2.2.2.2.2.2.2.1
  · simpa [callee, after, parserGrammarRowCallee,
      parserGrammarRowBindings] using body

def parserGrammarDotBindings
    (values : List Int) (grammarCell : CellId)
    (production dot : Nat) : List (VarId × Value) := [
  (0, parserGrammarValue values grammarCell),
  (1, .signed .i32 (Int.ofNat production)),
  (2, .signed .i32 (Int.ofNat dot))]

def parserGrammarDotCallee
    (caller : State) (values : List Int) (grammarCell : CellId)
    (production dot : Nat) : State :=
  enterCall caller
    (parserGrammarDotBindings values grammarCell production dot)

structure GrammarDotEntry
    (values : List Int) (grammarCell : CellId) (production dot : Nat)
    (caller : State) : Prop where
  valuesI32 : values.length ≤ 2147483647
  wellFormed : StateWellFormed caller
  backing : caller.cellEntry? grammarCell = some {
    id := grammarCell
    value := some (.array (signedI32Values values))
  }

theorem GrammarDotEntry.callee_wellFormed
    (entry : GrammarDotEntry values grammarCell production dot caller) :
    StateWellFormed
      (parserGrammarDotCallee caller values grammarCell production dot) :=
  enterCall_preserves_wellFormed entry.wellFormed

theorem GrammarDotEntry.callee_backing
    (entry : GrammarDotEntry values grammarCell production dot caller) :
    (parserGrammarDotCallee caller values grammarCell production dot).cellEntry?
        grammarCell = some {
      id := grammarCell
      value := some (.array (signedI32Values values))
    } := by
  have old : grammarCell < caller.nextCell :=
    Lanius.Separation.StateWellFormed.cell_lt_next_of_entry
      entry.wellFormed entry.backing
  exact ((enterCall_effect caller
    (parserGrammarDotBindings values grammarCell production dot)).oldCells
      grammarCell old (by simp [CellSet.empty])).trans entry.backing

theorem GrammarDotEntry.callee_grammar
    (entry : GrammarDotEntry values grammarCell production dot caller) :
    (parserGrammarDotCallee caller values grammarCell production dot).local? 0 =
      some (parserGrammarValue values grammarCell) := by
  simpa [parserGrammarDotCallee, parserGrammarDotBindings] using
    (enterCall_local_of_binding caller [] [
      (1, .signed .i32 (Int.ofNat production)),
      (2, .signed .i32 (Int.ofNat dot))]
      0 (parserGrammarValue values grammarCell) entry.wellFormed (by simp))

theorem GrammarDotEntry.callee_production
    (entry : GrammarDotEntry values grammarCell production dot caller) :
    (parserGrammarDotCallee caller values grammarCell production dot).local? 1 =
      some (.signed .i32 (Int.ofNat production)) := by
  simpa [parserGrammarDotCallee, parserGrammarDotBindings] using
    (enterCall_local_of_binding caller [
      (0, parserGrammarValue values grammarCell)] [
      (2, .signed .i32 (Int.ofNat dot))]
      1 (.signed .i32 (Int.ofNat production)) entry.wellFormed (by simp))

theorem GrammarDotEntry.callee_dot
    (entry : GrammarDotEntry values grammarCell production dot caller) :
    (parserGrammarDotCallee caller values grammarCell production dot).local? 2 =
      some (.signed .i32 (Int.ofNat dot)) := by
  simpa [parserGrammarDotCallee, parserGrammarDotBindings] using
    (enterCall_local_of_binding caller [
      (0, parserGrammarValue values grammarCell),
      (1, .signed .i32 (Int.ofNat production))] []
      2 (.signed .i32 (Int.ofNat dot)) entry.wellFormed (by simp))

/-- Full source-call contract for extracted `production_rhs_symbol`. The
    temporary `relative` local is allocated and scoped exactly as in the
    extracted Core body; only its fresh physical cell survives internally. -/
theorem extractedParserRhsSymbolCall_evaluates
    (values : List Int) (grammarCell : CellId)
    (production dot rhsOffsetsOffset relative rhsSymbolsOffset : Nat)
    (rhsOffsetsHeaderBound : 9 < values.length)
    (rhsOffsetsHeader : values.get ⟨9, rhsOffsetsHeaderBound⟩ =
      Int.ofNat rhsOffsetsOffset)
    (rhsOffsetAddressBound :
      rhsOffsetsOffset + production < values.length)
    (relativeValue :
      values.get ⟨rhsOffsetsOffset + production, rhsOffsetAddressBound⟩ =
        Int.ofNat relative)
    (rhsSymbolsHeaderBound : 11 < values.length)
    (rhsSymbolsHeader : values.get ⟨11, rhsSymbolsHeaderBound⟩ =
      Int.ofNat rhsSymbolsOffset)
    (symbolAddressBound :
      rhsSymbolsOffset + relative + dot < values.length)
    (before afterArguments : State) (arguments : List Expr)
    (entry : GrammarDotEntry values grammarCell production dot afterArguments)
    (argumentsResult : ArgumentsEvaluateTo verifiedParserCore before arguments [
      parserGrammarValue values grammarCell,
      .signed .i32 (Int.ofNat production),
      .signed .i32 (Int.ofNat dot)] afterArguments) :
    let callee := parserGrammarDotCallee afterArguments values grammarCell
      production dot
    let relativeState := callee.bindLocal 3
      (.signed .i32 (Int.ofNat relative))
    let completed := restoreLocals callee relativeState
    let after := restoreLocals afterArguments completed
    Evaluates verifiedParserCore before
        (.call extractedParserRhsSymbolFunction.id arguments)
        (.signed .i32
          (values.get ⟨rhsSymbolsOffset + relative + dot,
            symbolAddressBound⟩)) after ∧
      ModifiesOnly CellSet.empty afterArguments after ∧
      StateWellFormed after ∧
      after.cellEntry? grammarCell = some {
        id := grammarCell
        value := some (.array (signedI32Values values))
      } := by
  dsimp only
  let callee := parserGrammarDotCallee afterArguments values grammarCell
    production dot
  let relativeState := callee.bindLocal 3
    (.signed .i32 (Int.ofNat relative))
  let completed := restoreLocals callee relativeState
  let after := restoreLocals afterArguments completed
  have body : Executes verifiedParserCore callee parserRhsSymbolBody
      (.returned (some (.signed .i32
        (values.get ⟨rhsSymbolsOffset + relative + dot,
          symbolAddressBound⟩)))) completed := by
    rw [← extractedParserRhsSymbolBody_eq]
    simpa [relativeState, completed] using
      (extractedParserRhsSymbolBody_executes values grammarCell production dot
        rhsOffsetsOffset relative rhsSymbolsOffset rhsOffsetsHeaderBound
        rhsOffsetsHeader rhsOffsetAddressBound relativeValue
        rhsSymbolsHeaderBound rhsSymbolsHeader symbolAddressBound
        entry.valuesI32 callee entry.callee_wellFormed entry.callee_grammar
        entry.callee_production entry.callee_dot entry.callee_backing)
  have evaluation : Evaluates verifiedParserCore before
      (.call extractedParserRhsSymbolFunction.id arguments)
      (.signed .i32
        (values.get ⟨rhsSymbolsOffset + relative + dot,
          symbolAddressBound⟩)) after := by
    apply evaluatesCallReturned argumentsResult
      verifiedParserCore_finds_rhsSymbol
    · rw [extractedParserRhsSymbol_function_shape.2.1]
      rfl
    · exact extractedParserRhsSymbol_function_shape.2.2.2.1
    · simpa [callee, after, parserGrammarDotCallee,
        parserGrammarDotBindings] using body
  have relativeWellFormed : StateWellFormed relativeState := by
    exact bindLocal_preserves_well_formed callee 3
      (.signed .i32 (Int.ofNat relative)) entry.callee_wellFormed
  have temporaryStore : StoreEffect CellSet.empty callee completed := by
    exact ((bindLocal_effect callee 3 (.signed .i32 (Int.ofNat relative)))
      |>.restoreLocals).toStoreEffect
  have effect : ModifiesOnly CellSet.empty afterArguments after := by
    simpa [callee, completed, after, parserGrammarDotCallee] using
      (call_effect temporaryStore)
  have completedWellFormed : StateWellFormed completed := by
    exact (bindLocal_effect callee 3 (.signed .i32 (Int.ofNat relative)))
      |>.restoreLocals_wellFormed entry.callee_wellFormed relativeWellFormed
  have callStore : StoreEffect CellSet.empty afterArguments completed := by
    exact (enterCall_effect afterArguments
      (parserGrammarDotBindings values grammarCell production dot))
      |>.trans_same temporaryStore
  have afterWellFormed : StateWellFormed after := by
    exact callStore.restoreLocals_wellFormed entry.wellFormed
      completedWellFormed
  have backingAfter : after.cellEntry? grammarCell = some {
      id := grammarCell
      value := some (.array (signedI32Values values))
    } := by
    have old : grammarCell < afterArguments.nextCell :=
      Lanius.Separation.StateWellFormed.cell_lt_next_of_entry
        entry.wellFormed entry.backing
    exact (effect.toStoreEffect.oldCells grammarCell old
      (by simp [CellSet.empty])).trans entry.backing
  exact ⟨evaluation, effect, afterWellFormed, backingAfter⟩

/-- Semantic wrapper for `production_rhs_length`: the physical header and
    table premises are discharged from the packed-grammar relation, so users
    of the parser proof see a logical grammar row rather than word offsets. -/
theorem extractedParserRhsLengthCall_reads_encoded
    (layout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (encoded : EncodesGrammar layout grammar words)
    (grammarCell : CellId) (production : Nat)
    (productionBound : production < grammar.productionCount)
    (before afterArguments : State) (arguments : List Expr)
    (entry : GrammarRowEntry words grammarCell production afterArguments)
    (argumentsResult : ArgumentsEvaluateTo verifiedParserCore before arguments [
      parserGrammarValue words grammarCell,
      .signed .i32 (Int.ofNat production)] afterArguments) :
    let callee := parserGrammarRowCallee afterArguments words grammarCell
      production
    let after := restoreLocals afterArguments callee
    Evaluates verifiedParserCore before
      (.call extractedParserRhsLengthFunction.id arguments)
      (.signed .i32 (Int.ofNat
        (grammar.rhsLengths.get ⟨production, by simpa using productionBound⟩)))
      after := by
  dsimp only
  have rowBound : production < grammar.rhsLengths.length := by
    simpa using productionBound
  have headerBound := encoded.rhsLengthsOffset.index_in_bounds
  have headerValue := encoded.rhsLengthsOffset.get
  have addressBound := encoded.rhsLengths.row_in_bounds rowBound
  have result := extractedParserRhsLengthCall_evaluates words grammarCell
    production layout.rhsLengthsOffset headerBound headerValue addressBound
    before afterArguments arguments entry argumentsResult
  have physicalValue := encoded.rhsLengths.get rowBound
  rw [physicalValue] at result
  exact result

/-- Semantic wrapper for `production_lhs`, again hiding the packed-table
    address arithmetic behind `EncodesGrammar`. -/
theorem extractedParserLhsCall_reads_encoded
    (layout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (encoded : EncodesGrammar layout grammar words)
    (grammarCell : CellId) (production : Nat)
    (productionBound : production < grammar.productionCount)
    (before afterArguments : State) (arguments : List Expr)
    (entry : GrammarRowEntry words grammarCell production afterArguments)
    (argumentsResult : ArgumentsEvaluateTo verifiedParserCore before arguments [
      parserGrammarValue words grammarCell,
      .signed .i32 (Int.ofNat production)] afterArguments) :
    let callee := parserGrammarRowCallee afterArguments words grammarCell
      production
    let after := restoreLocals afterArguments callee
    Evaluates verifiedParserCore before
      (.call extractedParserLhsFunction.id arguments)
      (.signed .i32 (Int.ofNat
        (grammar.productionLhs.get
          ⟨production, by simpa using productionBound⟩))) after := by
  dsimp only
  have rowBound : production < grammar.productionLhs.length := by
    simpa using productionBound
  have headerBound := encoded.productionLhsOffset.index_in_bounds
  have headerValue := encoded.productionLhsOffset.get
  have addressBound := encoded.productionLhs.row_in_bounds rowBound
  have result := extractedParserLhsCall_evaluates words grammarCell production
    layout.productionLhsOffset headerBound headerValue addressBound before
    afterArguments arguments entry argumentsResult
  have physicalValue := encoded.productionLhs.get rowBound
  rw [physicalValue] at result
  exact result

/-- Semantic wrapper for `production_rhs_symbol`. The relative RHS offset and
    flattened symbol row are facts about the logical grammar; every physical
    address and word equality is recovered from `EncodesGrammar`. -/
theorem extractedParserRhsSymbolCall_reads_encoded
    (layout : PackedGrammarLayout) (grammar : IndexedGrammar)
    (words : List Int) (encoded : EncodesGrammar layout grammar words)
    (grammarCell : CellId) (production dot relative : Nat)
    (productionBound : production < grammar.productionCount)
    (relativeValue : grammar.rhsOffsets.get
      ⟨production, by simpa using productionBound⟩ = relative)
    (symbolRowBound : relative + dot < grammar.rhsSymbols.length)
    (before afterArguments : State) (arguments : List Expr)
    (entry : GrammarDotEntry words grammarCell production dot afterArguments)
    (argumentsResult : ArgumentsEvaluateTo verifiedParserCore before arguments [
      parserGrammarValue words grammarCell,
      .signed .i32 (Int.ofNat production),
      .signed .i32 (Int.ofNat dot)] afterArguments) :
    let callee := parserGrammarDotCallee afterArguments words grammarCell
      production dot
    let relativeState := callee.bindLocal 3
      (.signed .i32 (Int.ofNat relative))
    let completed := restoreLocals callee relativeState
    let after := restoreLocals afterArguments completed
    Evaluates verifiedParserCore before
        (.call extractedParserRhsSymbolFunction.id arguments)
        (.signed .i32 (Int.ofNat
          (grammar.rhsSymbols.get ⟨relative + dot, symbolRowBound⟩))) after ∧
      ModifiesOnly CellSet.empty afterArguments after ∧
      StateWellFormed after ∧
      after.cellEntry? grammarCell = some {
        id := grammarCell
        value := some (.array (signedI32Values words))
      } := by
  dsimp only
  have rhsOffsetsRowBound : production < grammar.rhsOffsets.length := by
    simpa using productionBound
  have rhsOffsetsHeaderBound := encoded.rhsOffsetsOffset.index_in_bounds
  have rhsOffsetsHeader := encoded.rhsOffsetsOffset.get
  have rhsOffsetAddressBound :=
    encoded.rhsOffsets.row_in_bounds rhsOffsetsRowBound
  have physicalRelative := encoded.rhsOffsets.get rhsOffsetsRowBound
  rw [relativeValue] at physicalRelative
  have rhsSymbolsHeaderBound := encoded.rhsSymbolsOffset.index_in_bounds
  have rhsSymbolsHeader := encoded.rhsSymbolsOffset.get
  have symbolAddressBound :=
    encoded.rhsSymbols.row_in_bounds symbolRowBound
  have symbolAddressBound' :
      layout.rhsSymbolsOffset + relative + dot < words.length := by
    omega
  have result := extractedParserRhsSymbolCall_evaluates words grammarCell
    production dot layout.rhsOffsetsOffset relative layout.rhsSymbolsOffset
    rhsOffsetsHeaderBound rhsOffsetsHeader rhsOffsetAddressBound
    physicalRelative rhsSymbolsHeaderBound rhsSymbolsHeader symbolAddressBound'
    before afterArguments arguments entry argumentsResult
  have physicalSymbol := encoded.rhsSymbols.get symbolRowBound
  have physicalSymbol' :
      words.get ⟨layout.rhsSymbolsOffset + relative + dot,
        symbolAddressBound'⟩ =
      Int.ofNat (grammar.rhsSymbols.get ⟨relative + dot,
        symbolRowBound⟩) := by
    simpa only [Nat.add_assoc] using physicalSymbol
  exact physicalSymbol' ▸ result

end Lanius.Extraction.ParserAccessors
