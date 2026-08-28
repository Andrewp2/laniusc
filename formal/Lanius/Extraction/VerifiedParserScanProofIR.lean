import Lanius.Extraction.VerifiedParserScan
import Lanius.ProofIRCoreSimulation

namespace Lanius.Extraction.ParserScan.Proof

open Lanius.Core
open Lanius.ProofIR
open Lanius.ProofIR.Core
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.Extraction.ParserScan
open Lanius.Compiler.Parser

/-! # Proof IR representation of `scan_terminal`

This is the proof-facing program. Its slots are lexically scoped `Fin`
indices; the physical Core locals 5, 6, and 7 are introduced only by
`lowerBlock`. The exact-lowering theorem below prevents this representation
from drifting away from the extracted compiler artifact.
-/

private abbrev ScanBlock (arity : Nat) := Block signature arity
private abbrev ScanTerm (arity : Nat) := Term signature arity

private def slot {arity : Nat} (index : Nat)
    (bound : index < arity := by omega) : ScanTerm arity :=
  reference ⟨index, bound⟩

private def i32 (value : Int) : ScanTerm arity :=
  literal (.signed .i32 value)

private def constant (id : ConstantId) : ScanTerm arity :=
  apply (.constant id parserI32Type) []

private def unaryI32 (operation : UnaryOp) (operand : ScanTerm arity) :
    ScanTerm arity :=
  apply (.unary operation parserI32Type parserI32Type) [operand]

private def binaryI32 (operation : BinaryOp)
    (left right : ScanTerm arity) : ScanTerm arity :=
  apply (.binary operation parserI32Type parserI32Type parserI32Type)
    [left, right]

private def compareI32 (operation : BinaryOp)
    (left right : ScanTerm arity) : ScanTerm arity :=
  apply (.binary operation parserI32Type parserI32Type (.scalar .bool))
    [left, right]

private def logicalAnd (left right : ScanTerm arity) : ScanTerm arity :=
  apply (.binary .logicalAnd (.scalar .bool) (.scalar .bool) (.scalar .bool))
    [left, right]

private def indexI32 (base index : ScanTerm arity) : ScanTerm arity :=
  apply (.index (.slice parserI32Type) parserI32Type parserI32Type)
    [base, index]

private def reject : ScanBlock arity :=
  .sequence (.returnValue (some (unaryI32 .negate (i32 1)))) .skip

private def advance (amount : Int) : ScanBlock 8 :=
  .sequence
    (.returnValue (some (binaryI32 .add (slot 3) (i32 amount))))
    .skip

private def splitMatch : ScanTerm 8 :=
  logicalAnd
    (compareI32 .equal (slot 6) (indexI32 (slot 0) (constant 12)))
    (compareI32 .equal (slot 7) (indexI32 (slot 0) (constant 13)))

private def splitMatchBlock : ScanBlock 8 :=
  .ifThenElse splitMatch (advance 1) .skip

private def oddPosition : ScanBlock 8 :=
  .sequence splitMatchBlock reject

private def canonicalMatch : ScanBlock 8 :=
  .ifThenElse (compareI32 .equal (slot 6) (slot 7)) (advance 2) .skip

private def evenPosition : ScanBlock 8 :=
  .sequence canonicalMatch (.sequence splitMatchBlock reject)

private def dispatch : ScanBlock 8 :=
  .sequence
    (.ifThenElse
      (compareI32 .equal (binaryI32 .remainder (slot 3) (i32 2)) (i32 1))
      oddPosition .skip)
    evenPosition

private def canonicalKind : ScanTerm 7 :=
  indexI32 (slot 0)
    (binaryI32 .add (indexI32 (slot 0) (constant 14)) (slot 4))

/-- Name-free, intrinsically scoped representation of the terminal scan. -/
def scanTerminal : ScanBlock 5 :=
  .letValue parserI32Type (binaryI32 .divide (slot 3) (i32 2))
    (.sequence
      (.ifThenElse
        (compareI32 .greaterEqual (slot 5) (slot 2))
        reject .skip)
      (.letValue parserI32Type (indexI32 (slot 1) (slot 5))
        (.letValue parserI32Type canonicalKind dispatch)))

/-- The Proof IR is not a second, manually trusted parser model. Deterministic
    lowering recreates the body decoded from the checked compiler artifact. -/
theorem scanTerminal_lowers_exactly :
    lowerBlock (identityLayout (arity := 5)) 5 scanTerminal =
      extractedParserScanTerminalBody := by
  rfl

/-- Reusable correctness boundary for the extracted function. A parser model
    now proves only that `scanTerminal` evaluates to the desired result under
    its primitive-operation bridge. Cell allocation, restoration, branching,
    returns, and preservation of caller state are discharged here once. -/
theorem extractedScanTerminal_executes_of_evaluation
    (bridge : ReadOnlyBridge machine verifiedParserCore)
    (represented : bridge.Represents world state)
    (environment : Env 5)
    (environmentMatches : EnvironmentMatches
      (identityLayout (arity := 5)) environment state)
    (wellFormed : StateWellFormed state)
    (evaluated : Block.evaluate machine world environment scanTerminal =
      .done completion afterWorld) :
    ∃ after,
      Executes verifiedParserCore state extractedParserScanTerminalBody
        (lowerCompletion completion) after ∧
      ModifiesOnly CellSet.empty state after ∧
      StateWellFormed after ∧
      bridge.Represents afterWorld after ∧
      EnvironmentMatches (identityLayout (arity := 5)) environment after := by
  have below : LayoutBelow (identityLayout (arity := 5)) 5 := by
    intro index
    exact index.isLt
  obtain ⟨after, execution, effect, afterWellFormed, afterRepresented,
    afterMatches⟩ := block_executes bridge represented environmentMatches below
      wellFormed evaluated
  rw [scanTerminal_lowers_exactly] at execution
  exact ⟨after, execution, effect, afterWellFormed, afterRepresented,
    afterMatches⟩

end Lanius.Extraction.ParserScan.Proof
