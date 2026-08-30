import Lanius.Extraction.VerifiedParserRecognize
import Lanius.Extraction.VerifiedParserRecognizeFunctionalView
import Lanius.FunctionalViewCoreStatefulRenaming
import Lanius.FunctionalViewCoreStatefulCallRefinement
import Lanius.FunctionalViewCoreStatefulReification
import Lanius.FunctionalViewCoreStatefulSimulation
import Lanius.FunctionalViewLoop
import Lanius.LoopVerification
import Lanius.Compiler.WorkspaceLoop

namespace Lanius.Extraction.ParserRecognize

set_option maxRecDepth 100000

open Lanius.Core
open Lanius.SymbolicCore
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.CallContracts
open Lanius.Extraction
open Lanius.Extraction.ParserScan
open Lanius.Extraction.ParserAppend
open Lanius.Extraction.ParserAccessors
open Lanius.Extraction.ParserFind
open Lanius.Extraction.ParserResult
open Lanius.Compiler.Parser
open Lanius.Typing
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Core.Stateful.Reification

/-- Read one fixed packed-grammar header word while retaining the complete
    recognizer representation invariant. -/
theorem RecognizerInvariant.read_packed_header
    (invariant : RecognizerInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell runtime)
    (headerConstant : ConstantId) (headerIndex value : Nat)
    (header : HeaderWord words headerIndex value)
    (constantFound : verifiedParserCore.constant? headerConstant = some {
      id := headerConstant
      type := parserI32Type
      value := .signed .i32 (Int.ofNat headerIndex)
    }) :
    Evaluates verifiedParserCore runtime
      (.index (.local 0) (.constant headerConstant))
      (.signed .i32 (Int.ofNat value)) runtime := by
  have result := evaluatesParserHeaderRead words grammarCell headerConstant
    headerIndex header.index_in_bounds runtime invariant.grammarLocal
    invariant.grammarBacking constantFound
  have selected : words.get ⟨headerIndex, header.index_in_bounds⟩ =
      Int.ofNat value := by
    simpa using header.get
  rw [selected] at result
  exact result

/-- Read a natural-number row from any packed grammar table whose offset and
    semantic row index are already held in locals.  This is the common GPU-
    independent operation behind the recognizer's LHS offset/count lookups. -/
theorem RecognizerInvariant.read_packed_nat_table
    (invariant : RecognizerInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell runtime)
    (offsetLocal indexLocal offset index : Nat) (values : List Nat)
    (encoded : PackedTableAt words offset values)
    (offsetFound : runtime.local? offsetLocal =
      some (.signed .i32 (Int.ofNat offset)))
    (indexFound : runtime.local? indexLocal =
      some (.signed .i32 (Int.ofNat index)))
    (indexBound : index < values.length) :
    Evaluates verifiedParserCore runtime
      (.index (.local 0)
        (.binary .add (.local offsetLocal) (.local indexLocal)))
      (.signed .i32 (Int.ofNat (values.get ⟨index, indexBound⟩))) runtime := by
  have physicalBound := encoded.row_in_bounds indexBound
  have grammarResult : Evaluates verifiedParserCore runtime (.local 0)
      (parserGrammarValue words grammarCell) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 0 _
      invariant.grammarLocal⟩
  have offsetResult : Evaluates verifiedParserCore runtime (.local offsetLocal)
      (.signed .i32 (Int.ofNat offset)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime offsetLocal _
      offsetFound⟩
  have indexResult : Evaluates verifiedParserCore runtime (.local indexLocal)
      (.signed .i32 (Int.ofNat index)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime indexLocal _
      indexFound⟩
  have addressBound : offset + index ≤ 2147483647 :=
    Nat.le_trans (Nat.le_of_lt physicalBound) invariant.wordsI32
  have addressResult : Evaluates verifiedParserCore runtime
      (.binary .add (.local offsetLocal) (.local indexLocal))
      (.signed .i32 (Int.ofNat (offset + index))) runtime := by
    have castAddress : Int.ofNat offset + Int.ofNat index =
        Int.ofNat (offset + index) := (Int.natCast_add _ _).symm
    have wrapped := wrapSigned_i32_ofNat verifiedParserCore.target _
      addressBound
    apply evaluatesEagerBinary (by decide) (by decide) offsetResult indexResult
    simp only [evalBinaryValue, evalSignedBinary]
    rw [castAddress, wrapped]
    simp
  have read := evaluatesSignedI32SliceIndex verifiedParserCore runtime runtime
    runtime words (.local 0)
      (.binary .add (.local offsetLocal) (.local indexLocal))
    grammarCell (offset + index) physicalBound grammarResult addressResult
    invariant.grammarBacking
  have physical := encoded.get indexBound
  rw [physical] at read
  exact read

/-- Equality of nonnegative i32 values, allowing the right operand to perform
    store-pure calls and therefore advance the runtime state. -/
theorem evaluatesNatEqualityThreaded
    (before middle after : State) (left right : Expr)
    (leftValue rightValue : Nat)
    (leftResult : Evaluates verifiedParserCore before left
      (.signed .i32 (Int.ofNat leftValue)) middle)
    (rightResult : Evaluates verifiedParserCore middle right
      (.signed .i32 (Int.ofNat rightValue)) after) :
    Evaluates verifiedParserCore before (.binary .equal left right)
      (.boolean (decide (leftValue = rightValue))) after := by
  apply evaluatesEagerBinary (by decide) (by decide) leftResult rightResult
  by_cases same : leftValue = rightValue
  · subst rightValue
    simp [evalBinaryValue, scalarEqual]
  · have different : Int.ofNat leftValue ≠ Int.ofNat rightValue := by
      intro equal
      exact same (Int.ofNat_inj.mp equal)
    simp [evalBinaryValue, scalarEqual, same]
    exact different

/-- Strict comparison of nonnegative i32 values, allowing the right operand
    to perform store-pure calls and advance the runtime state. -/
theorem evaluatesNatLessThreaded
    (before middle after : State) (left right : Expr)
    (leftValue rightValue : Nat)
    (leftResult : Evaluates verifiedParserCore before left
      (.signed .i32 (Int.ofNat leftValue)) middle)
    (rightResult : Evaluates verifiedParserCore middle right
      (.signed .i32 (Int.ofNat rightValue)) after) :
    Evaluates verifiedParserCore before (.binary .less left right)
      (.boolean (decide (leftValue < rightValue))) after := by
  apply evaluatesEagerBinary (by decide) (by decide) leftResult rightResult
  simp [evalBinaryValue, evalSignedBinary, Int.ofNat_lt]

/-- One ambient FunctionalView world for the complete recognizer. Grammar,
    workspace, and token slices share this representation across every
    recognition operation. -/
def recognizerWorld (words : List Int) (tokens : List Nat)
    (workspaceValues : List Int)
    (grammarCell tokensCell workspaceCell : CellId) :
    Lanius.FunctionalView.Core.ReadOnly.World := {
  i32Slice? := fun candidate =>
    if candidate = grammarCell then some words
    else if candidate = workspaceCell then some workspaceValues
    else if candidate = tokensCell then some (tokens.map Int.ofNat)
    else none
}

@[simp] theorem recognizerWorld_finds_grammar :
    (recognizerWorld words tokens workspaceValues grammarCell tokensCell
      workspaceCell).i32Slice? grammarCell = some words := by
  simp [recognizerWorld]

@[simp] theorem recognizerWorld_finds_workspace
    (different : workspaceCell ≠ grammarCell) :
    (recognizerWorld words tokens workspaceValues grammarCell tokensCell
      workspaceCell).i32Slice? workspaceCell = some workspaceValues := by
  simp [recognizerWorld, different]

@[simp] theorem recognizerWorld_finds_tokens
    (grammarDifferent : tokensCell ≠ grammarCell)
    (workspaceDifferent : tokensCell ≠ workspaceCell) :
    (recognizerWorld words tokens workspaceValues grammarCell tokensCell
      workspaceCell).i32Slice? tokensCell =
      some (tokens.map Int.ofNat) := by
  simp [recognizerWorld, grammarDifferent, workspaceDifferent]

@[simp] theorem recognizerWorld_set_workspace
    (grammarDifferent : workspaceCell ≠ grammarCell)
    (tokensDifferent : workspaceCell ≠ tokensCell) :
    Lanius.FunctionalView.Core.ReadOnly.World.setI32Slice
        (recognizerWorld words tokens beforeValues grammarCell tokensCell
          workspaceCell)
        workspaceCell afterValues =
      recognizerWorld words tokens afterValues grammarCell tokensCell
        workspaceCell := by
  apply congrArg Lanius.FunctionalView.Core.ReadOnly.World.mk
  funext candidate
  by_cases workspaceEq : candidate = workspaceCell
  · subst candidate
    simp [Lanius.FunctionalView.Core.ReadOnly.World.setI32Slice,
      recognizerWorld, grammarDifferent, tokensDifferent]
  · simp [Lanius.FunctionalView.Core.ReadOnly.World.setI32Slice,
      recognizerWorld, workspaceEq]

theorem recognizerWorld_represents
    (invariant : RecognizerInvariant grammarLayout grammar words tokens
      workspaceLayout workspace workspaceValues grammarCell tokensCell
      workspaceCell runtime) :
    Lanius.FunctionalView.Core.ReadOnly.World.Represents
      (recognizerWorld words tokens workspaceValues grammarCell tokensCell
        workspaceCell) runtime := by
  intro cell values found
  change (if cell = grammarCell then some words
    else if cell = workspaceCell then some workspaceValues
    else if cell = tokensCell then some (tokens.map Int.ofNat)
    else none) = some values at found
  split at found
  next grammarEq =>
    subst cell
    simp only [Option.some.injEq] at found
    subst values
    exact ⟨invariant.grammarBacking,
      Lanius.Separation.StateWellFormed.cell_lt_next_of_entry
        invariant.wellFormed invariant.grammarBacking⟩
  next grammarNe =>
    split at found
    next workspaceEq =>
      subst cell
      simp only [Option.some.injEq] at found
      subst values
      exact ⟨invariant.workspaceBacking,
        Lanius.Separation.StateWellFormed.cell_lt_next_of_entry
          invariant.wellFormed invariant.workspaceBacking⟩
    next workspaceNe =>
      split at found
      next tokensEq =>
        subst cell
        simp only [Option.some.injEq] at found
        subst values
        exact ⟨invariant.tokensBacking,
          Lanius.Separation.StateWellFormed.cell_lt_next_of_entry
            invariant.wellFormed invariant.tokensBacking⟩
      next tokensNe => simp at found

theorem evaluatesLogicalAnd
    {arity : Nat}
    (machine : Lanius.FunctionalView.Machine
      Lanius.FunctionalView.Core.signature)
    (world : machine.World) (environment : Lanius.FunctionalView.Env arity)
    (left right : Lanius.FunctionalView.Term
      Lanius.FunctionalView.Core.signature arity)
    (leftValue rightValue : Bool)
    (leftResult : Lanius.FunctionalView.Term.evaluate machine world
      environment left = .ok (.boolean leftValue, world))
    (rightResult : Lanius.FunctionalView.Term.evaluate machine world
      environment right = .ok (.boolean rightValue, world)) :
    Lanius.FunctionalView.Term.evaluate machine world environment
      (.logicalAnd left right) =
      .ok (.boolean (leftValue && rightValue), world) := by
  cases leftValue with
  | false =>
      simpa using Lanius.FunctionalView.Term.evaluate_logicalAnd_false
        leftResult
  | true =>
      simpa using Lanius.FunctionalView.Term.evaluate_logicalAnd_true
        leftResult rightResult

def parserCapacityCompletion (position stateCount : Nat) : Completion :=
  .returned (some
    (parseResultValue 2 (Int.ofNat stateCount) (-1) (Int.ofNat position)))

end Lanius.Extraction.ParserRecognize
