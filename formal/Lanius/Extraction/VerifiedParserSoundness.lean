import Lanius.Extraction.VerifiedParserRecognizeSetup

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
              exact materializedParse.recognizesInput
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
