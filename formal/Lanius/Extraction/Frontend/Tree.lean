import Lanius.Extraction.Frontend.Result
import Lanius.Extraction.Parser.Tree.Materialize
import Lanius.Extraction.Parser.Recognize.Linked

namespace Lanius.Extraction.Frontend

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.Compiler.Parser Lanius.Extraction.ParserRecognize Lanius.Extraction.ParserDerivation
open Lanius.Extraction.ParserTreeSource
open Lanius.Extraction.CoreSynthesis.Program Lanius.Extraction.ParserResult

variable {artifacts : List Artifact} {program : CheckedProgram artifacts}
variable {visit : CheckedVisit program} {materializer : CheckedMaterialize visit}

structure CheckedAfterParse (materializer : CheckedMaterialize visit) where
  finish : CheckedFinish visit
  error : Source.CheckedProjection program ["verified", "parser"] "parse_error_position" materializer.parsedType 3
  failureId : ConstantId
  failure : constantValue program.core failureId 4

def CheckedAfterParse.condition (checked : CheckedAfterParse materializer) : Expr :=
  .binary .notEqual (.call materializer.status.source.function.id [.local 22]) (.constant materializer.parseSuccess)

def CheckedAfterParse.rejected (checked : CheckedAfterParse materializer) : Stmt :=
  .sequence (.returnValue (some (.call checked.finish.constructor.source.function.id
    [.constant checked.failureId, .call materializer.status.source.function.id [.local 22],
      .local 18, .local 20, .value (.signed .i32 0), .value (.signed .i32 0),
      .call checked.error.source.function.id [.local 22]]))) .skip

def materializeArguments : List Expr :=
  [.local 22, .local 10, .local 11, .local 20, .local 12, .local 13, .local 14, .local 15, .local 16]

def CheckedAfterParse.body (checked : CheckedAfterParse materializer) : Stmt :=
  .sequence (.ifThenElse checked.condition checked.rejected .skip)
    (.letLocal 23 (.structure visit.symbols.resultType) (.call materializer.source.function.id materializeArguments)
      (finishBody checked.finish.symbols))

def checkAfterParse? (materializer : CheckedMaterialize visit) (statement : Stmt) :
    Option (Σ checked : CheckedAfterParse materializer, Core.Equality.Evidence statement checked.body) := do
  let .sequence (.ifThenElse _ (.sequence (.returnValue (some (.call _ (.constant failureId :: _)))) .skip) .skip)
    (.letLocal _ _ _ ending) := statement | none
  let ⟨finish, _⟩ ← checkFinish? visit ending
  let error ← Source.checkProjection? program ["verified", "parser"] "parse_error_position" materializer.parsedType 3
  let failure ← checkConstantValue? program.core failureId 4
  let checked : CheckedAfterParse materializer := ⟨finish, error, failureId, failure.equal⟩
  let exactBody ← Core.Equality.statement? statement checked.body
  pure ⟨checked, exactBody⟩

private theorem local_read {id : VarId} (found : before.local? id = some value) :
    Evaluates program.core before (.local id) value before := ⟨1, evalLocal_of_local 0 _ _ _ _ found⟩

/-- Feed the actual retained parser outcome into materialization and return
the extractor's seven fields. The selected root and all call arguments are
derived here. Resource failures still return classified partial counts. -/
theorem CheckedAfterParse.accepted {visit : CheckedVisit program} {materializer : CheckedMaterialize visit}
    (checked : CheckedAfterParse materializer) (linked : LinkedReader visit.reader allowed symbols)
    (inverseType : TypeId → TypeId) (inverse : Function.RightInverse inverseType symbols.typeId)
    (parsedType : materializer.parsedType = symbols.typeId 0)
    (outcome : RecognizerInitialContinuationOutcome grammarLayout grammar grammarWords tokens layout completion)
    (agreement : outcome.workspaceAgrees workspace) (success : parseResultStatus? outcome.resultValue = some 0)
    (before : State) (wellFormed : StateWellFormed before)
    (artifact : RecognizerWorkspaceArtifact layout workspace workspaceValues workspaceCell before)
    (layoutTokens : layout.tokenCount = tokens.length)
    (parsedLocal : before.local? 22 = some (Core.Relocation.value symbols outcome.resultValue))
    (rawLocal : before.local? 18 = some (.signed .i32 rawCount))
    (tokenLocal : before.local? 20 = some (.signed .i32 (Int.ofNat tokens.length)))
    (workspaceLocal : before.local? 10 = some (.slice (.scalar (.signed .i32)) workspaceCell [] 0 workspaceValues.length))
    (workspaceLength : before.local? 11 = some (.signed .i32 (Int.ofNat workspaceValues.length)))
    (recordsLocal : before.local? 12 = some (.slice (.scalar (.signed .i32)) recordsCell [] 0 recordValues.length))
    (recordsLength : before.local? 13 = some (.signed .i32 (Int.ofNat recordValues.length)))
    (offsetsLocal : before.local? 14 = some (.slice (.scalar (.signed .i32)) offsetsCell [] 0 offsetValues.length))
    (offsetsLength : before.local? 15 = some (.signed .i32 (Int.ofNat offsetValues.length)))
    (depthLocal : before.local? 16 = some (.signed .i32 (Int.ofNat depth)))
    (records : before.cellEntry? recordsCell = some {
      id := recordsCell, value := some (.array (signedI32Values recordValues)) })
    (offsets : before.cellEntry? offsetsCell = some {
      id := offsetsCell, value := some (.array (signedI32Values offsetValues)) })
    (recordsSeparate : workspaceCell ≠ recordsCell) (offsetsSeparate : workspaceCell ≠ offsetsCell)
    (buffersDistinct : recordsCell ≠ offsetsCell)
    (recordsBound : recordValues.length ≤ 2147483647) (offsetsBound : offsetValues.length ≤ 2147483647)
    (depthBound : depth ≤ 2147483647) :
    let root := outcome.successRoot agreement success
    ∃ code nodes words after,
      Executes program.core before checked.body
        (.returned (some (syntaxResult checked.finish.constructor.typeId (extractionTreeStage code) code
          rawCount (Int.ofNat tokens.length) (Int.ofNat nodes) (Int.ofNat words) 0))) after ∧
      (materializeRuntime root.root recordValues offsetValues recordsCell offsetsCell).Result
        root.stored.tree code nodes words after.cells ∧
      RecognizerWorkspaceArtifact layout workspace workspaceValues workspaceCell after ∧
      CellEffect (CellSet.union (CellSet.singleton recordsCell) (CellSet.singleton offsetsCell)) before after := by
  dsimp only
  let root := outcome.successRoot agreement success
  have parsedReady : before.local? 22 = some (.structure materializer.parsedType
      [.signed .i32 0, .signed .i32 (Int.ofNat workspace.states.length), .signed .i32 (Int.ofNat root.rootState), .signed .i32 0]) := by
    rw [root.resultEq] at parsedLocal
    simpa only [parseResultValue, Core.Relocation.value, Core.Relocation.values, parsedType] using parsedLocal
  obtain ⟨guarded, statusCall, statusEffect⟩ := materializer.status.call wellFormed (.singleton (local_read parsedReady)) rfl
  have guardRun : Evaluates program.core before checked.condition (.boolean false) guarded :=
    evaluatesEagerBinary (by decide) (by decide) statusCall (evaluatesConstant materializer.success) rfl
  have localGuarded {id : VarId} {value : Value} (found : before.local? id = some value) :
      guarded.local? id = some value := statusEffect.empty_preserves_local wellFormed found
  have guardedArtifact : RecognizerWorkspaceArtifact layout workspace workspaceValues workspaceCell guarded :=
    ⟨artifact.workspaceLength, artifact.workspaceEncoded, statusEffect.empty_preserves_entry wellFormed artifact.workspaceBacking⟩
  have guardedRecords := statusEffect.empty_preserves_entry wellFormed records
  have guardedOffsets := statusEffect.empty_preserves_entry wellFormed offsets
  have arguments : ArgumentsEvaluateTo program.core guarded materializeArguments
      (materializeValues materializer.parsedType workspaceValues recordValues offsetValues workspaceCell recordsCell offsetsCell
        layout.tokenCount workspace.states.length root.rootState depth) guarded := by
    rw [materializeArguments, materializeValues, layoutTokens]
    refine .cons (local_read (localGuarded parsedReady)) ?_
    refine .cons (local_read (localGuarded workspaceLocal)) ?_
    refine .cons (local_read (localGuarded workspaceLength)) ?_
    refine .cons (local_read (localGuarded tokenLocal)) ?_
    refine .cons (local_read (localGuarded recordsLocal)) ?_
    refine .cons (local_read (localGuarded recordsLength)) ?_
    refine .cons (local_read (localGuarded offsetsLocal)) ?_
    exact .cons (local_read (localGuarded offsetsLength)) (.singleton (local_read (localGuarded depthLocal)))
  obtain ⟨code, nodes, words, materialized, treeCall, treeResult, treeArtifact, treeEffect⟩ :=
    materializer.call_bounded linked inverseType inverse root statusEffect.wellFormed guardedArtifact layoutTokens
      guardedRecords guardedOffsets recordsSeparate offsetsSeparate buffersDistinct recordsBound offsetsBound depthBound arguments
  let ready := materialized.bindLocal 23 (resultValue visit.symbols.resultType code (Int.ofNat nodes) (Int.ofNat words))
  have readyWF : StateWellFormed ready := bindLocal_preserves_well_formed _ _ _ treeEffect.wellFormed
  have preserved {id : VarId} {value : Value} (found : before.local? id = some value)
      (different : 23 ≠ id) (plain : ∀ values, value ≠ .array values) : ready.local? id = some value := by
    have afterTree := treeEffect.preserves_local statusEffect.wellFormed (localGuarded found) (by
      intro cell binding written
      exact written.elim (local_cell_ne_of_distinct_value (localGuarded found) guardedRecords (plain _) binding)
        (local_cell_ne_of_distinct_value (localGuarded found) guardedOffsets (plain _) binding))
    exact (bindLocal_preserves_other_local treeEffect.wellFormed different).trans afterTree
  obtain ⟨completed, finished, finishEffect⟩ := checked.finish.execute ready readyWF
    (bindLocal_finds_local _ _ _ treeEffect.wellFormed)
    (preserved rawLocal (by decide) (by intro values same; cases same))
    (preserved tokenLocal (by decide) (by intro values same; cases same))
  have finishClosed := CellEffect.closeLocal materialized 23
    (resultValue visit.symbols.resultType code (Int.ofNat nodes) (Int.ofNat words)) treeEffect.wellFormed finishEffect
  let after := restoreLocals guarded completed
  have finishFrame : CellEffect CellSet.empty materialized after := by
    simpa only [after, restoreLocals, treeEffect.locals] using finishClosed
  refine ⟨code, nodes, words, after, ?_, treeResult.preserved treeEffect.wellFormed finishFrame
    (by simp [CellSet.empty]) (by simp [CellSet.empty]),
    ⟨treeArtifact.workspaceLength, treeArtifact.workspaceEncoded,
      finishFrame.empty_preserves_entry treeEffect.wellFormed treeArtifact.workspaceBacking⟩,
    (statusEffect.weaken CellSet.empty_subset).trans (treeEffect.trans (finishFrame.weaken CellSet.empty_subset))⟩
  have tailRun := executesLetLocal (type := .structure visit.symbols.resultType) treeCall finished
  simpa only [CheckedAfterParse.body, after, restoreLocals, treeEffect.locals] using
    executesSequence (executesIfFalse guardRun (executesSkip _ _)) tailRun

/-- A parser failure returns before materialization. No tree/workspace storage
assumption is needed on this branch, and no caller-owned cell is changed. -/
theorem CheckedAfterParse.reject (checked : CheckedAfterParse materializer)
    (before : State) (wellFormed : StateWellFormed before)
    (parsedLocal : before.local? 22 = some (.structure materializer.parsedType
      [.signed .i32 code, .signed .i32 states, .signed .i32 root, .signed .i32 position]))
    (failed : code ≠ 0)
    (rawLocal : before.local? 18 = some (.signed .i32 rawCount))
    (tokenLocal : before.local? 20 = some (.signed .i32 tokenCount)) :
    ∃ after, Executes program.core before checked.body
        (.returned (some (syntaxResult checked.finish.constructor.typeId 4 code rawCount tokenCount 0 0 position))) after ∧
      CellEffect CellSet.empty before after := by
  obtain ⟨guarded, statusCall, statusEffect⟩ := materializer.status.call wellFormed
    (.singleton (local_read parsedLocal)) rfl
  have guardRun : Evaluates program.core before checked.condition (.boolean true) guarded :=
    evaluatesEagerBinary (by decide) (by decide) statusCall (evaluatesConstant materializer.success)
      (by simp [evalBinaryValue, scalarEqual, failed])
  have guardedParse := statusEffect.empty_preserves_local wellFormed parsedLocal
  obtain ⟨detailed, detailCall, detailEffect⟩ := materializer.status.call statusEffect.wellFormed
    (.singleton (local_read guardedParse)) rfl
  have prefixEffect := statusEffect.trans detailEffect
  obtain ⟨positioned, positionCall, positionEffect⟩ := checked.error.call detailEffect.wellFormed
    (.singleton (local_read (prefixEffect.empty_preserves_local wellFormed parsedLocal))) rfl
  have arguments : ArgumentsEvaluateTo program.core guarded
      [.constant checked.failureId, .call materializer.status.source.function.id [.local 22],
        .local 18, .local 20, .value (.signed .i32 0), .value (.signed .i32 0),
        .call checked.error.source.function.id [.local 22]]
      [.signed .i32 4, .signed .i32 code, .signed .i32 rawCount, .signed .i32 tokenCount,
        .signed .i32 0, .signed .i32 0, .signed .i32 position] positioned := by
    refine .cons (evaluatesConstant checked.failure) (.cons detailCall ?_)
    refine .cons (local_read (prefixEffect.empty_preserves_local wellFormed rawLocal)) ?_
    refine .cons (local_read (prefixEffect.empty_preserves_local wellFormed tokenLocal)) ?_
    exact .cons ⟨1, rfl⟩ (.cons ⟨1, rfl⟩ (.singleton positionCall))
  obtain ⟨after, returned, returnEffect⟩ := checked.finish.constructor.call positionEffect.wellFormed arguments
  exact ⟨after, executesSequenceReturned (executesIfTrue guardRun
      (executesSequenceReturned (executesReturnValue returned))),
    prefixEffect.trans (positionEffect.trans returnEffect)⟩

private theorem parser_fields
    (outcome : RecognizerInitialContinuationOutcome grammarLayout grammar grammarWords tokens layout completion) :
    ∃ code states root position, outcome.resultValue = parseResultValue code states root position ∧
      (code = 0 ∨ code = 1 ∨ code = 2) := by
  cases outcome with
  | full count => exact ⟨2, Int.ofNat count, -1, 0, rfl, Or.inr (Or.inr rfl)⟩
  | seeded workspace values completion continuation =>
    cases continuation with
    | full position count => exact ⟨2, Int.ofNat count, -1, Int.ofNat position, rfl, Or.inr (Or.inr rfl)⟩
    | completed workspace values growth completion root =>
      cases root with
      | accepted rootState candidate found bounded candidateMatches stored =>
        exact ⟨0, Int.ofNat workspace.states.length, Int.ofNat rootState, 0, rfl, Or.inl rfl⟩
      | rejected furthest => exact ⟨1, Int.ofNat workspace.states.length, -1, Int.ofNat furthest, rfl, Or.inr (Or.inl rfl)⟩

/-- Derive the failure fields from the same retained outcome consumed by the
success branch. The caller does not supply a separate parse-result shape. -/
theorem CheckedAfterParse.rejected_outcome (checked : CheckedAfterParse materializer)
    (symbols : Core.Relocation.Symbols) (parsedType : materializer.parsedType = symbols.typeId 0)
    (outcome : RecognizerInitialContinuationOutcome grammarLayout grammar grammarWords tokens layout completion)
    (failed : parseResultStatus? outcome.resultValue ≠ some 0)
    (before : State) (wellFormed : StateWellFormed before)
    (parsedLocal : before.local? 22 = some (Core.Relocation.value symbols outcome.resultValue))
    (rawLocal : before.local? 18 = some (.signed .i32 rawCount))
    (tokenLocal : before.local? 20 = some (.signed .i32 (Int.ofNat tokens.length))) :
    ∃ code states root position after,
      outcome.resultValue = parseResultValue code states root position ∧ (code = 1 ∨ code = 2) ∧
      Executes program.core before checked.body
        (.returned (some (syntaxResult checked.finish.constructor.typeId 4 code rawCount (Int.ofNat tokens.length) 0 0 position))) after ∧
      CellEffect CellSet.empty before after := by
  obtain ⟨code, states, root, position, fields, status⟩ := parser_fields outcome
  have nonzero : code ≠ 0 := by
    intro zero
    apply failed
    rw [fields, parseResultStatus?_parseResultValue, zero]
  have parsed : before.local? 22 = some (.structure materializer.parsedType
      [.signed .i32 code, .signed .i32 states, .signed .i32 root, .signed .i32 position]) := by
    rw [fields] at parsedLocal
    simpa only [parseResultValue, Core.Relocation.value, Core.Relocation.values, parsedType] using parsedLocal
  obtain ⟨after, execution, effect⟩ := checked.reject before wellFormed parsed nonzero rawLocal tokenLocal
  exact ⟨code, states, root, position, after, fields, status.resolve_left nonzero, execution, effect⟩

end Lanius.Extraction.Frontend
