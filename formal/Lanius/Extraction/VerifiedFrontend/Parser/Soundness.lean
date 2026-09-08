import Lanius.Extraction.VerifiedFrontend.Parser.Recognize.Setup

namespace Lanius.Extraction.ParserRecognize

open Lanius.Core
open Lanius.Compiler.Parser
open Lanius.Extraction.ParserResult

/-- Decode the status field of the concrete `ParseResult` value returned by
    the extracted parser.  The public soundness theorem below is phrased in
    terms of this artifact-level observation rather than its internal Earley
    proof object. -/
def parseResultStatus? : Value → Option Int
  | .structure 0 (.signed .i32 status :: _stateCount :: _root ::
      _errorPosition :: []) => some status
  | _ => none

@[simp] theorem parseResultStatus?_parseResultValue
    (status stateCount rootState errorPosition : Int) :
    parseResultStatus?
      (parseResultValue status stateCount rootState errorPosition) =
      some status := by
  rfl

/-- A successful concrete result identifies a stored root in the workspace
    returned to the caller, and fixes both numeric fields of `ParseResult`. -/
structure RecognizerRootResult (grammar : IndexedGrammar) (tokens : List Nat)
    (workspace : LogicalWorkspace) (result : Value) where
  rootState : Nat
  root : EarleyState
  found : workspace.state? rootState = some root
  stored : StoredRootParse grammar tokens workspace rootState
  resultEq : result = parseResultValue 0 (Int.ofNat workspace.states.length)
    (Int.ofNat rootState) 0

def RecognizerInitialContinuationOutcome.successRoot
    {completion : Lanius.Semantics.Completion}
    (outcome : RecognizerInitialContinuationOutcome grammarLayout grammar words
      tokens workspaceLayout completion)
    (agreement : outcome.workspaceAgrees finalWorkspace)
    (success : parseResultStatus? outcome.resultValue = some 0) :
    RecognizerRootResult grammar tokens finalWorkspace outcome.resultValue := by
  cases outcome with
  | full stateCount =>
      simp [RecognizerInitialContinuationOutcome.resultValue] at success
  | seeded workspace workspaceValues completion continuation =>
      cases continuation with
      | full position stateCount =>
          simp [RecognizerInitialContinuationOutcome.resultValue] at success
      | completed storedWorkspace finalValues growth completion root =>
          cases root with
          | accepted rootState candidate found productionBound candidateMatches stored =>
              change storedWorkspace = finalWorkspace at agreement
              subst finalWorkspace
              exact ⟨rootState, candidate, found, stored, rfl⟩
          | rejected furthest =>
              simp [RecognizerInitialContinuationOutcome.resultValue] at success

/-- No semantic-workspace assumption is supplied by the caller: it follows
    from the recognizer's successful execution result. -/
def RecognizerCallExecution.successRoot
    (execution : RecognizerCallExecution grammarLayout grammar words tokens
      workspaceLayout workspaceValues grammarCell tokensCell workspaceCell
      before afterArguments arguments)
    (success : parseResultStatus? execution.outcome.resultValue = some 0) :
    RecognizerRootResult grammar tokens execution.finalWorkspace
      execution.outcome.resultValue :=
  execution.outcome.successRoot execution.outcomeWorkspace success

/-- The reader's state index is in bounds because the returned root is
    present in the same stored workspace, not because a caller assumes it. -/
theorem RecognizerRootResult.root_lt_stateCount
    (result : RecognizerRootResult grammar tokens workspace value) :
    result.rootState < workspace.states.length := by
  exact getElem?_some_implies_bound result.found

/-- A successful concrete result can only arise from the accepted root-search
    constructor, which contains a checked materialized derivation for the
    complete token stream. -/
theorem RecognizerInitialContinuationOutcome.success_recognizesInput
    {completion : Lanius.Semantics.Completion}
    (outcome : RecognizerInitialContinuationOutcome grammarLayout grammar words
      tokens workspaceLayout completion)
    (success : parseResultStatus? outcome.resultValue = some 0) :
    RecognizesInput grammar tokens := by
  cases outcome with
  | full stateCount =>
      simp [RecognizerInitialContinuationOutcome.resultValue] at success
  | seeded workspace workspaceValues completion continuation =>
      cases continuation with
      | full position stateCount =>
          simp [RecognizerInitialContinuationOutcome.resultValue] at success
      | completed finalWorkspace finalValues growth completion root =>
          cases root with
          | accepted rootState candidate found productionBound candidateMatches
              materializedParse =>
              exact materializedParse.toMaterializedParse.recognizesInput
          | rejected furthest =>
              simp [RecognizerInitialContinuationOutcome.resultValue] at success

/-- End-to-end soundness of the real, source-extracted
    `parser.lani::recognize` call. The body is mechanically recovered as
    `parserRecognizeView`, lowers exactly to the checked source artifact, and
    `RecognizerCallExecution` contains the resulting concrete call
    evaluation. Observing `PARSE_SUCCESS` therefore entails recognition by
    the declarative grammar semantics. -/
theorem RecognizerCallExecution.success_recognizesInput
    (execution : RecognizerCallExecution grammarLayout grammar words tokens
      workspaceLayout workspaceValues grammarCell tokensCell workspaceCell
      before afterArguments arguments)
    (success : parseResultStatus? execution.outcome.resultValue = some 0) :
    RecognizesInput grammar tokens :=
  execution.outcome.success_recognizesInput success

end Lanius.Extraction.ParserRecognize
