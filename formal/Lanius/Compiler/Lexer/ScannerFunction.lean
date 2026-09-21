import Lean.Elab.Tactic.Omega
import Lanius.Compiler.Lexer.PrefixScannerFunction
import Lanius.Compiler.Lexer.ScannerOracle

namespace Lanius.Compiler.Lexer

open Lanius Lanius.Core Lanius.Semantics

private theorem predicateScannerFunction
    (caller : State) (cell : CellId) (source : List Byte) (start : Nat)
    (functionId predicateId : FunctionId) (accept : Byte → Bool)
    (backing : SourceByteBacking caller cell source)
    (predicate : ScannerPredicateContract caller cell source predicateId accept)
    (functionFound : Artifact.lexerProgram.function? functionId =
      some (Artifact.scannerFunction functionId predicateId))
    (formed : caller.CellsWellFormed) (startInSource : start < source.length)
    (sourceLengthI32 : source.length < 2 ^ 31) :
    ∃ threshold after, ThresholdPure threshold Artifact.lexerProgram caller
      (.call functionId (scannerArgumentExpressions cell source start))
      (.signed .i32 (Int.ofNat (scanEnd accept source start 1))) after := by
  let oracle := scannerLoopOracle caller cell source predicateId accept backing predicate
  let current := scannerCalleeWithCursor caller cell source start
  let initializer : Expr :=
    .binary .add (.local 2) (.value (.signed .i32 1))
  have invariant := scannerCalleeWithCursor_invariant caller cell source start
    formed backing startInSource sourceLengthI32
  have initialInvariant : oracle.Inv (start + 1) current := by
    exact ⟨_, invariant⟩
  have initializerRun : ∀ fuel, 2 ≤ fuel →
      evalExpr fuel Artifact.lexerProgram (scannerCallee caller cell source start)
        initializer =
        .done (.signed .i32 (Int.ofNat (start + 1)))
          (scannerCallee caller cell source start) := by
    intro fuel enough
    simpa [initializer] using evalScannerInitializer fuel Artifact.lexerProgram
      (scannerCallee caller cell source start) start
      (scannerCallee_startLocal caller cell source start formed) (by omega) enough
  exact prefixScannerFunction_call Artifact.lexerProgram caller cell source start 1
    (Artifact.scannerCondition predicateId) Artifact.scannerLoopBody accept
    (Artifact.scannerFunction functionId predicateId) 3 oracle current initialInvariant
    (by rfl)
    (by intro cursor state invariant; rcases invariant with ⟨_, invariant⟩
        exact invariant.frame)
    (by intro state invariant; rcases invariant with ⟨_, invariant⟩
        exact invariant.cursorLocal)
    initializer 2 initializerRun functionFound (by rfl)
    (scannerFunction_bindParameters functionId predicateId cell source start)

theorem identifierContinueScannerFunction
    (caller : State) (cell : CellId) (source : List Byte) (start : Nat)
    (backing : SourceByteBacking caller cell source)
    (formed : caller.CellsWellFormed) (startInSource : start < source.length)
    (sourceLengthI32 : source.length < 2 ^ 31) :
    ∃ threshold after, ThresholdPure threshold Artifact.lexerProgram caller
      (.call Artifact.scanIdentifierEndFunction.id
        (scannerArgumentExpressions cell source start))
      (.signed .i32 (Int.ofNat (scanIdentifierEnd source start))) after := by
  simpa [scanIdentifierEnd] using predicateScannerFunction caller cell source start
    Artifact.scanIdentifierEndFunction.id Artifact.identifierContinueFunction.id
    isIdentifierContinue backing (identifierContinuePredicateContract caller cell source)
    (by rfl) formed startInSource sourceLengthI32

theorem whitespaceScannerFunction
    (caller : State) (cell : CellId) (source : List Byte) (start : Nat)
    (backing : SourceByteBacking caller cell source)
    (formed : caller.CellsWellFormed) (startInSource : start < source.length)
    (sourceLengthI32 : source.length < 2 ^ 31) :
    ∃ threshold after, ThresholdPure threshold Artifact.lexerProgram caller
      (.call Artifact.scanWhitespaceEndFunction.id
        (scannerArgumentExpressions cell source start))
      (.signed .i32 (Int.ofNat (scanWhitespaceEnd source start))) after := by
  simpa [scanWhitespaceEnd] using predicateScannerFunction caller cell source start
    Artifact.scanWhitespaceEndFunction.id Artifact.whitespaceFunction.id
    isWhitespace backing (whitespacePredicateContract caller cell source)
    (by rfl) formed startInSource sourceLengthI32

theorem scanIdentifierEnd_pure
    (caller : State) (cell : CellId) (source : List Byte) (start : Nat)
    (backing : SourceByteBacking caller cell source)
    (formed : caller.CellsWellFormed) (startInSource : start < source.length)
    (sourceLengthI32 : source.length < 2 ^ 31) :
    PurelyEvaluates Artifact.lexerProgram caller
      (.call Artifact.scanIdentifierEndFunction.id
        (scannerArgumentExpressions cell source start))
      (.signed .i32 (Int.ofNat (scanIdentifierEnd source start))) := by
  obtain ⟨_, _, contract⟩ := identifierContinueScannerFunction caller cell source
    start backing formed startInSource sourceLengthI32
  exact contract.erase

theorem scanWhitespaceEnd_pure
    (caller : State) (cell : CellId) (source : List Byte) (start : Nat)
    (backing : SourceByteBacking caller cell source)
    (formed : caller.CellsWellFormed) (startInSource : start < source.length)
    (sourceLengthI32 : source.length < 2 ^ 31) :
    PurelyEvaluates Artifact.lexerProgram caller
      (.call Artifact.scanWhitespaceEndFunction.id
        (scannerArgumentExpressions cell source start))
      (.signed .i32 (Int.ofNat (scanWhitespaceEnd source start))) := by
  obtain ⟨_, _, contract⟩ := whitespaceScannerFunction caller cell source start
    backing formed startInSource sourceLengthI32
  exact contract.erase

end Lanius.Compiler.Lexer
