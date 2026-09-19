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

/-- Capacity failure reports the state count of the same workspace returned
to the caller. The witness comes from a failed append, not from its status
code alone. -/
theorem RecognizerInitialContinuationOutcome.capacity_result
    (outcome : RecognizerInitialContinuationOutcome grammarLayout grammar words
      tokens workspaceLayout completion)
    (agreement : outcome.workspaceAgrees finalWorkspace)
    (exhausted : parseResultStatus? outcome.resultValue = some 2) :
    ∃ position : Nat,
      outcome.resultValue = parseResultValue 2 (Int.ofNat finalWorkspace.states.length)
        (-1) (Int.ofNat position) ∧
      workspaceLayout.capacity ≤ finalWorkspace.states.length := by
  cases outcome with
  | full stateCount workspace full =>
      subst finalWorkspace
      exact ⟨0, by simp [RecognizerInitialContinuationOutcome.resultValue, full.count],
        full.capacity_le_states⟩
  | seeded workspace values completion continuation =>
      cases continuation with
      | full position stateCount storedWorkspace full =>
          change storedWorkspace = finalWorkspace at agreement
          subst finalWorkspace
          exact ⟨position, by simp [RecognizerInitialContinuationOutcome.resultValue, full.count],
            full.capacity_le_states⟩
      | completed storedWorkspace values growth completion root =>
          cases root <;> simp [RecognizerInitialContinuationOutcome.resultValue] at exhausted

theorem RecognizerCallExecution.capacity_result
    (execution : RecognizerCallExecution grammarLayout grammar words tokens
      workspaceLayout workspaceValues grammarCell tokensCell workspaceCell
      before afterArguments arguments)
    (exhausted : parseResultStatus? execution.outcome.resultValue = some 2) :
    ∃ position : Nat,
      execution.outcome.resultValue = parseResultValue 2
        (Int.ofNat execution.finalWorkspace.states.length) (-1) (Int.ofNat position) ∧
      workspaceLayout.capacity ≤ execution.finalWorkspace.states.length :=
  execution.outcome.capacity_result execution.outcomeWorkspace exhausted

/-- The source buffer representation also forbids exceeding capacity, so a
capacity return means it is exactly full. -/
theorem RecognizerCallExecution.capacity_exhausted
    (execution : RecognizerCallExecution grammarLayout grammar words tokens
      workspaceLayout workspaceValues grammarCell tokensCell workspaceCell
      before afterArguments arguments)
    (exhausted : parseResultStatus? execution.outcome.resultValue = some 2) :
    execution.finalWorkspace.states.length = workspaceLayout.capacity := by
  obtain ⟨_, _, full⟩ := execution.capacity_result exhausted
  exact Nat.le_antisymm execution.workspaceArtifact.workspaceEncoded.stateCountFits full

private theorem RecognizerInitialContinuationOutcome.workspaceFacts
    (outcome : RecognizerInitialContinuationOutcome grammarLayout grammar words
      tokens workspaceLayout completion)
    (agreement : outcome.workspaceAgrees finalWorkspace) :
    WorkspaceGenerated grammar tokens finalWorkspace ∧
      (parseResultStatus? outcome.resultValue = some 2 ∨
        (StartSeeded grammar finalWorkspace ∧
          PredictionsBefore grammar finalWorkspace (finalPosition tokens.length + 1) ∧
          ScansBefore grammar tokens finalWorkspace (finalPosition tokens.length + 1) ∧
          ChartClosed grammar tokens finalWorkspace)) := by
  cases outcome with
  | full count workspace full generated =>
      exact ⟨agreement ▸ generated, .inl rfl⟩
  | seeded workspace values completion continuation =>
      cases continuation with
      | full position count storedWorkspace full generated =>
          exact ⟨agreement ▸ generated, .inl rfl⟩
      | completed storedWorkspace values growth completion root seeded predicted scanned closed generated =>
          exact ⟨agreement ▸ generated,
            .inr ⟨agreement ▸ seeded, agreement ▸ predicted,
              agreement ▸ scanned, agreement ▸ closed⟩⟩

/-- Every returned workspace retains its generation from the input grammar,
including early capacity returns. -/
theorem RecognizerInitialContinuationOutcome.generated
    (outcome : RecognizerInitialContinuationOutcome grammarLayout grammar words
      tokens workspaceLayout completion)
    (agreement : outcome.workspaceAgrees finalWorkspace) :
    WorkspaceGenerated grammar tokens finalWorkspace :=
  (outcome.workspaceFacts agreement).1

theorem RecognizerCallExecution.generated
    (execution : RecognizerCallExecution grammarLayout grammar words tokens
      workspaceLayout workspaceValues grammarCell tokensCell workspaceCell before afterArguments arguments) :
    WorkspaceGenerated grammar tokens execution.finalWorkspace :=
  execution.outcome.generated execution.outcomeWorkspace

/-- A closed candidate chart bounds the real parser's state count, without
executing that parser or requiring matching state IDs/backpointers. -/
theorem RecognizerCallExecution.states_le_closed
    (execution : RecognizerCallExecution grammarLayout grammar words tokens
      workspaceLayout workspaceValues grammarCell tokensCell workspaceCell before afterArguments arguments)
    (closed : ChartClosed grammar tokens upper) (upperSound : ChartSound upper) :
    execution.finalWorkspace.states.length ≤ upper.states.length :=
  execution.generated.length_le execution.workspaceArtifact.workspaceEncoded.wellFormed closed upperSound

theorem RecognizerCallExecution.not_full_of_closed_bound
    (execution : RecognizerCallExecution grammarLayout grammar words tokens
      workspaceLayout workspaceValues grammarCell tokensCell workspaceCell before afterArguments arguments)
    (closed : ChartClosed grammar tokens upper) (upperSound : ChartSound upper)
    (fits : upper.states.length < workspaceLayout.capacity) :
    parseResultStatus? execution.outcome.resultValue ≠ some 2 := by
  intro exhausted
  have bound := execution.states_le_closed closed upperSound
  have full := execution.capacity_exhausted exhausted
  omega

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

/-- A rejected concrete result means exhaustive root search found no start
item in the very workspace returned to the caller. Capacity exhaustion is
not rejection and cannot provide this evidence. -/
theorem RecognizerInitialContinuationOutcome.rejected_noRoot
    (outcome : RecognizerInitialContinuationOutcome grammarLayout grammar words tokens workspaceLayout completion)
    (agreement : outcome.workspaceAgrees finalWorkspace)
    (rejected : parseResultStatus? outcome.resultValue = some 1) :
    NoRootIn grammar finalWorkspace (finalWorkspace.chart (finalPosition tokens.length)) := by
  cases outcome with
  | full stateCount => simp [RecognizerInitialContinuationOutcome.resultValue] at rejected
  | seeded workspace values completion continuation =>
      cases continuation with
      | full position stateCount => simp [RecognizerInitialContinuationOutcome.resultValue] at rejected
      | completed storedWorkspace finalValues growth completion root =>
          cases root with
          | accepted rootState candidate found bound matched stored =>
              simp [RecognizerInitialContinuationOutcome.resultValue] at rejected
          | rejected furthest absent =>
              subst finalWorkspace
              exact absent

theorem RecognizerCallExecution.rejected_noRoot
    (execution : RecognizerCallExecution grammarLayout grammar words tokens
      workspaceLayout workspaceValues grammarCell tokensCell workspaceCell before afterArguments arguments)
    (rejected : parseResultStatus? execution.outcome.resultValue = some 1) :
    NoRootIn grammar execution.finalWorkspace (execution.finalWorkspace.chart (finalPosition tokens.length)) :=
  execution.outcome.rejected_noRoot execution.outcomeWorkspace rejected

/-- Every non-capacity result comes after the actual complete seeding loop.
Append-only chart growth preserves all its start items into the returned
workspace, whether root search accepts or rejects. -/
theorem RecognizerInitialContinuationOutcome.startSeeded
    (outcome : RecognizerInitialContinuationOutcome grammarLayout grammar words tokens workspaceLayout completion)
    (agreement : outcome.workspaceAgrees finalWorkspace)
    (notFull : parseResultStatus? outcome.resultValue ≠ some 2) :
    StartSeeded grammar finalWorkspace := by
  exact (outcome.workspaceFacts agreement).2.elim
    (fun full => False.elim (notFull full)) (fun facts => facts.1)

theorem RecognizerCallExecution.startSeeded
    (execution : RecognizerCallExecution grammarLayout grammar words tokens
      workspaceLayout workspaceValues grammarCell tokensCell workspaceCell before afterArguments arguments)
    (notFull : parseResultStatus? execution.outcome.resultValue ≠ some 2) :
    StartSeeded grammar execution.finalWorkspace :=
  execution.outcome.startSeeded execution.outcomeWorkspace notFull

/-- Normal completion of the source position loop establishes prediction
closure for every input chart in the actual returned workspace, not merely
the chart being visited by its last state-loop iteration. -/
theorem RecognizerInitialContinuationOutcome.predictionsComplete
    (outcome : RecognizerInitialContinuationOutcome grammarLayout grammar words tokens workspaceLayout completion)
    (agreement : outcome.workspaceAgrees finalWorkspace)
    (notFull : parseResultStatus? outcome.resultValue ≠ some 2) :
    PredictionsBefore grammar finalWorkspace (finalPosition tokens.length + 1) := by
  exact (outcome.workspaceFacts agreement).2.elim
    (fun full => False.elim (notFull full)) (fun facts => facts.2.1)

theorem RecognizerCallExecution.predictionsComplete
    (execution : RecognizerCallExecution grammarLayout grammar words tokens
      workspaceLayout workspaceValues grammarCell tokensCell workspaceCell before afterArguments arguments)
    (notFull : parseResultStatus? execution.outcome.resultValue ≠ some 2) :
    PredictionsBefore grammar execution.finalWorkspace (finalPosition tokens.length + 1) :=
  execution.outcome.predictionsComplete execution.outcomeWorkspace notFull

/-- Matching terminal scans are retained for every input chart, including
items appended while earlier charts were processed. Capacity failure cannot
be used to claim this normal-completion guarantee. -/
theorem RecognizerInitialContinuationOutcome.scansComplete
    (outcome : RecognizerInitialContinuationOutcome grammarLayout grammar words tokens workspaceLayout completion)
    (agreement : outcome.workspaceAgrees finalWorkspace)
    (notFull : parseResultStatus? outcome.resultValue ≠ some 2) :
    ScansBefore grammar tokens finalWorkspace (finalPosition tokens.length + 1) := by
  exact (outcome.workspaceFacts agreement).2.elim
    (fun full => False.elim (notFull full)) (fun facts => facts.2.2.1)

theorem RecognizerCallExecution.scansComplete
    (execution : RecognizerCallExecution grammarLayout grammar words tokens
      workspaceLayout workspaceValues grammarCell tokensCell workspaceCell before afterArguments arguments)
    (notFull : parseResultStatus? execution.outcome.resultValue ≠ some 2) :
    ScansBefore grammar tokens execution.finalWorkspace (finalPosition tokens.length + 1) :=
  execution.outcome.scansComplete execution.outcomeWorkspace notFull

/-- Every non-capacity return carries full closure from the actual source
traversals, for the same physical workspace returned to the caller. -/
theorem RecognizerInitialContinuationOutcome.chartClosed
    (outcome : RecognizerInitialContinuationOutcome grammarLayout grammar words tokens workspaceLayout completion)
    (agreement : outcome.workspaceAgrees finalWorkspace)
    (notFull : parseResultStatus? outcome.resultValue ≠ some 2) :
    ChartClosed grammar tokens finalWorkspace := by
  exact (outcome.workspaceFacts agreement).2.elim
    (fun full => False.elim (notFull full)) (fun facts => facts.2.2.2)

theorem RecognizerCallExecution.chartClosed
    (execution : RecognizerCallExecution grammarLayout grammar words tokens
      workspaceLayout workspaceValues grammarCell tokensCell workspaceCell before afterArguments arguments)
    (notFull : parseResultStatus? execution.outcome.resultValue ≠ some 2) :
    ChartClosed grammar tokens execution.finalWorkspace :=
  execution.outcome.chartClosed execution.outcomeWorkspace notFull

/-- Declaratively valid input cannot be rejected by the real root search.
The only remaining alternative is the explicit capacity result. -/
theorem RecognizerInitialContinuationOutcome.success_of_recognizes
    (outcome : RecognizerInitialContinuationOutcome grammarLayout grammar words tokens workspaceLayout completion)
    (recognized : RecognizesInput grammar tokens)
    (notFull : parseResultStatus? outcome.resultValue ≠ some 2) :
    parseResultStatus? outcome.resultValue = some 0 := by
  cases outcome with
  | full stateCount => simp [RecognizerInitialContinuationOutcome.resultValue] at notFull
  | seeded workspace values completion continuation =>
      cases continuation with
      | full position stateCount => simp [RecognizerInitialContinuationOutcome.resultValue] at notFull
      | completed storedWorkspace finalValues growth completion root seeded predicted scanned closed =>
          cases root with
          | accepted => rfl
          | rejected furthest absent =>
              exact False.elim (absent.not_hasRoot (closed.contains_root recognized))

theorem RecognizerCallExecution.success_of_recognizes
    (execution : RecognizerCallExecution grammarLayout grammar words tokens
      workspaceLayout workspaceValues grammarCell tokensCell workspaceCell before afterArguments arguments)
    (recognized : RecognizesInput grammar tokens)
    (notFull : parseResultStatus? execution.outcome.resultValue ≠ some 2) :
    parseResultStatus? execution.outcome.resultValue = some 0 :=
  execution.outcome.success_of_recognizes recognized notFull

theorem RecognizerCallExecution.success_or_capacity
    (execution : RecognizerCallExecution grammarLayout grammar words tokens
      workspaceLayout workspaceValues grammarCell tokensCell workspaceCell before afterArguments arguments)
    (recognized : RecognizesInput grammar tokens) :
    parseResultStatus? execution.outcome.resultValue = some 0 ∨
      parseResultStatus? execution.outcome.resultValue = some 2 := by
  by_cases full : parseResultStatus? execution.outcome.resultValue = some 2
  · exact .inr full
  · exact .inl (execution.success_of_recognizes recognized full)

/-- Syntax plus a finite closed envelope strictly below capacity guarantees
success of the actual source parser. The bound is not defined by that run. -/
theorem RecognizerCallExecution.success_of_closed_bound
    (execution : RecognizerCallExecution grammarLayout grammar words tokens
      workspaceLayout workspaceValues grammarCell tokensCell workspaceCell before afterArguments arguments)
    (recognized : RecognizesInput grammar tokens)
    (closed : ChartClosed grammar tokens upper) (upperSound : ChartSound upper)
    (fits : upper.states.length < workspaceLayout.capacity) :
    parseResultStatus? execution.outcome.resultValue = some 0 :=
  execution.success_of_recognizes recognized (execution.not_full_of_closed_bound closed upperSound fits)

/-- Expose the actual selected derivation, not only its success status. -/
def RecognizerCallExecution.root_of_recognizes
    (execution : RecognizerCallExecution grammarLayout grammar words tokens
      workspaceLayout workspaceValues grammarCell tokensCell workspaceCell before afterArguments arguments)
    (recognized : RecognizesInput grammar tokens)
    (notFull : parseResultStatus? execution.outcome.resultValue ≠ some 2) :
    RecognizerRootResult grammar tokens execution.finalWorkspace execution.outcome.resultValue :=
  execution.successRoot (execution.success_of_recognizes recognized notFull)

end Lanius.Extraction.ParserRecognize
