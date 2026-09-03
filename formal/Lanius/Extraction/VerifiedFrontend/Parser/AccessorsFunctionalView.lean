import Lanius.Extraction.VerifiedFrontend.Parser.Accessors
import Lanius.FunctionalViewCoreEffectfulStateful
import Lanius.FunctionalViewCoreStatefulReification

namespace Lanius.Extraction.ParserAccessors.FunctionalView

open Lanius.Core
open Lanius.Typing
open Lanius.Compiler.Parser
open Lanius.Extraction.ParserAccessors
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly
open Lanius.FunctionalView.Core.Effectful
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Core.Stateful.Reification

/-! # FunctionalView representations of packed-grammar accessors

Each view is recovered mechanically from the checked `parser.lani` artifact.
The logical call model below exposes grammar rows and symbols without leaking
the packed word offsets used by the source implementation.
-/

namespace RhsLength

def parameterLayout : Layout 2 := identityLayout

def parameterContext : Context :=
  Lanius.Typing.parameterContext extractedParserRhsLengthFunction.parameters

private def reification? :=
  reifyCommand? verifiedParserCore extractedParserRhsLengthFunction.returnType
    parameterContext false parameterLayout 2 extractedParserRhsLengthBody

theorem reification_exists : reification?.isSome := by
  native_decide

def view := reification?.get reification_exists

theorem view_toCore_exactly :
    toCoreStmt actionAdapter parameterLayout 2 view.command =
      extractedParserRhsLengthBody :=
  view.toCoreExactly

theorem semantic_body_agrees_with_reification :
    toCoreStmt parameterLayout 2
        (TableReadProof.body 17) =
      toCoreStmt actionAdapter parameterLayout 2 view.command := by
  calc
    _ = parserTableReadBody 17 := by
      simpa [parameterLayout] using
        (TableReadProof.body_toCore_exactly (headerConstant := 17))
    _ = extractedParserRhsLengthBody :=
      extractedParserRhsLengthBody_eq.symm
    _ = _ := view_toCore_exactly.symm

end RhsLength

namespace Lhs

def parameterLayout : Layout 2 := identityLayout

def parameterContext : Context :=
  Lanius.Typing.parameterContext extractedParserLhsFunction.parameters

private def reification? :=
  reifyCommand? verifiedParserCore extractedParserLhsFunction.returnType
    parameterContext false parameterLayout 2 extractedParserLhsBody

theorem reification_exists : reification?.isSome := by
  native_decide

def view := reification?.get reification_exists

theorem view_toCore_exactly :
    toCoreStmt actionAdapter parameterLayout 2 view.command =
      extractedParserLhsBody :=
  view.toCoreExactly

theorem semantic_body_agrees_with_reification :
    toCoreStmt parameterLayout 2
        (TableReadProof.body 15) =
      toCoreStmt actionAdapter parameterLayout 2 view.command := by
  calc
    _ = parserTableReadBody 15 := by
      simpa [parameterLayout] using
        (TableReadProof.body_toCore_exactly (headerConstant := 15))
    _ = extractedParserLhsBody := extractedParserLhsBody_eq.symm
    _ = _ := view_toCore_exactly.symm

end Lhs

namespace RhsSymbol

def parameterLayout : Layout 3 := identityLayout

def parameterContext : Context :=
  Lanius.Typing.parameterContext extractedParserRhsSymbolFunction.parameters

private def reification? :=
  reifyCommand? verifiedParserCore extractedParserRhsSymbolFunction.returnType
    parameterContext false parameterLayout 3 extractedParserRhsSymbolBody

theorem reification_exists : reification?.isSome := by
  native_decide

def view := reification?.get reification_exists

theorem view_toCore_exactly :
    toCoreStmt actionAdapter parameterLayout 3 view.command =
      extractedParserRhsSymbolBody :=
  view.toCoreExactly

theorem semantic_body_agrees_with_reification :
    toCoreStmt parameterLayout 3 RhsSymbolProof.body =
      toCoreStmt actionAdapter parameterLayout 3 view.command := by
  calc
    _ = extractedParserRhsSymbolBody := by
      simpa [parameterLayout] using RhsSymbolProof.body_toCore_exactly
    _ = _ := view_toCore_exactly.symm

end RhsSymbol

private def evaluateRow (words : List Int) (grammarCell : CellId)
    (rows : List Nat) (world : World) (arguments : List Value) :
    Except Trap (Value × World) :=
  match arguments with
  | [.slice elementType cell projections start length,
      .signed .i32 production] =>
      if elementType = parserI32Type ∧ cell = grammarCell ∧ projections = [] ∧
          start = 0 ∧ length = words.length ∧ 0 ≤ production then
        if world.i32Slice? grammarCell = some words then
          match rows[production.toNat]? with
          | some value => .ok (.signed .i32 (Int.ofNat value), world)
          | none => .error .arrayBounds
        else .error .invalidPointer
      else .error .typeMismatch
  | _ => .error .typeMismatch

private def evaluateRhsSymbol (grammar : IndexedGrammar) (words : List Int)
    (grammarCell : CellId) (world : World) (arguments : List Value) :
    Except Trap (Value × World) :=
  match arguments with
  | [.slice elementType cell projections start length,
      .signed .i32 production, .signed .i32 dot] =>
      if elementType = parserI32Type ∧ cell = grammarCell ∧ projections = [] ∧
          start = 0 ∧ length = words.length ∧ 0 ≤ production ∧ 0 ≤ dot then
        if world.i32Slice? grammarCell = some words then
          match grammar.grammar.productions[production.toNat]? with
          | some row =>
              match row.rhs[dot.toNat]? with
              | some symbol => .ok (.signed .i32 (Int.ofNat symbol), world)
              | none => .error .arrayBounds
          | none => .error .arrayBounds
        else .error .invalidPointer
      else .error .typeMismatch
  | _ => .error .typeMismatch

/-- Logical call semantics for all three packed-grammar accessors. -/
def calls (grammar : IndexedGrammar) (words : List Int)
    (grammarCell : CellId) : CallModel where
  evaluate := fun world function arguments =>
    if function = extractedParserRhsLengthFunction.id then
      evaluateRow words grammarCell grammar.rhsLengths world arguments
    else if function = extractedParserLhsFunction.id then
      evaluateRow words grammarCell grammar.productionLhs world arguments
    else if function = extractedParserRhsSymbolFunction.id then
      evaluateRhsSymbol grammar words grammarCell world arguments
    else
      .error .invalidPointer

theorem calls_at_rhs_length
    (found : world.i32Slice? grammarCell = some words)
    (bound : production < grammar.rhsLengths.length) :
    (calls grammar words grammarCell).evaluate world
        extractedParserRhsLengthFunction.id [
          parserGrammarValue words grammarCell,
          .signed .i32 (Int.ofNat production)] =
      .ok (.signed .i32 (Int.ofNat
        (grammar.rhsLengths.get ⟨production, bound⟩)), world) := by
  have lookup : grammar.rhsLengths[production]? =
      some (grammar.rhsLengths.get ⟨production, bound⟩) :=
    List.getElem?_eq_getElem bound
  simp [calls, evaluateRow, parserGrammarValue, found, lookup]

theorem calls_at_lhs
    (found : world.i32Slice? grammarCell = some words)
    (bound : production < grammar.productionLhs.length) :
    (calls grammar words grammarCell).evaluate world
        extractedParserLhsFunction.id [
          parserGrammarValue words grammarCell,
          .signed .i32 (Int.ofNat production)] =
      .ok (.signed .i32 (Int.ofNat
        (grammar.productionLhs.get ⟨production, bound⟩)), world) := by
  have notRhs : extractedParserLhsFunction.id ≠
      extractedParserRhsLengthFunction.id := by native_decide
  have lookup : grammar.productionLhs[production]? =
      some (grammar.productionLhs.get ⟨production, bound⟩) :=
    List.getElem?_eq_getElem bound
  simp [calls, evaluateRow, parserGrammarValue, found, lookup, notRhs]

theorem calls_at_rhs_symbol
    (found : world.i32Slice? grammarCell = some words)
    (productionBound : production < grammar.productionCount)
    (dotBound : dot <
      (grammar.productionAt ⟨production, productionBound⟩).rhs.length) :
    (calls grammar words grammarCell).evaluate world
        extractedParserRhsSymbolFunction.id [
          parserGrammarValue words grammarCell,
          .signed .i32 (Int.ofNat production),
          .signed .i32 (Int.ofNat dot)] =
      .ok (.signed .i32 (Int.ofNat
        ((grammar.productionAt ⟨production, productionBound⟩).rhs.get
          ⟨dot, dotBound⟩)), world) := by
  have notRhs : extractedParserRhsSymbolFunction.id ≠
      extractedParserRhsLengthFunction.id := by native_decide
  have notLhs : extractedParserRhsSymbolFunction.id ≠
      extractedParserLhsFunction.id := by native_decide
  have productionLookup : grammar.grammar.productions[production]? =
      some (grammar.productionAt ⟨production, productionBound⟩) :=
    List.getElem?_eq_getElem (by
      simpa [IndexedGrammar.productionCount] using productionBound)
  have symbolLookup :
      (grammar.productionAt ⟨production, productionBound⟩).rhs[dot]? =
        some ((grammar.productionAt ⟨production, productionBound⟩).rhs.get
          ⟨dot, dotBound⟩) :=
    List.getElem?_eq_getElem dotBound
  simp [calls, evaluateRhsSymbol, parserGrammarValue, found, notRhs, notLhs,
    productionLookup, symbolLookup]

end Lanius.Extraction.ParserAccessors.FunctionalView
