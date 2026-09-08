import Lanius.Extraction.Frontend.Syntax

namespace Lanius.Extraction.Frontend

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.FunctionalView.Core Lanius.Compiler.Lexer Lanius.Compiler.Parser
open Lanius.Extraction.RawLexer.LexInto
open Lanius.Extraction.CanonicalTokens CanonicalizeModel Compaction
open Lanius.Extraction.ParserRecognize Lanius.Extraction.ParserAccessors Lanius.Extraction.ParserFind
open Lanius.Extraction.ParserTreeSource Lanius.Extraction.ParserDerivation Lanius.Extraction.ParserResult

def syntaxWrites (raw canonical kinds workspace records offsets : CellId) : CellSet :=
  CellSet.union
    (CellSet.union (CellSet.union (CellSet.singleton raw) (CellSet.singleton canonical))
      (CellSet.union (CellSet.singleton kinds) (CellSet.singleton workspace)))
    (CellSet.union (CellSet.singleton records) (CellSet.singleton offsets))

/-- A single contract for every lexer-to-return branch. Early errors retain
their narrower write sets; the final branch retains the actual parser outcome.
Raw output is common to all branches and is stated separately by lex_to_return. -/
def bodyPost (request : Model.Request) (raw : List RawToken)
    (canonical kinds treeRecords treeOffsets : List Int)
    (rawCell canonicalCell kindsCell workspaceCell recordsCell offsetsCell : CellId)
    (grammarLayout : PackedGrammarLayout) (grammar : IndexedGrammar) (grammarWords : List Int)
    (workspaceLayout : WorkspaceLayout)
    (stage detail : Int) (count nodes words : Nat) (position : Int) (before after : State) : Prop :=
  let tokens := canonicalizeTokens request.source raw
  (lexerEarlyPost request.outcome canonical.length stage detail position ∧
    count = 0 ∧ nodes = 0 ∧ words = 0 ∧ CellEffect (CellSet.singleton rawCell) before after) ∨
  (request.outcome = .completed raw ∧ 3 * raw.length ≤ canonical.length ∧ count = tokens.length ∧
    after.cellEntry? canonicalCell = some { id := canonicalCell, value := some (.array (signedI32Values
      (compactedBuffer raw (canonical.drop (3 * raw.length)) tokens))) } ∧
    ((kinds.length < tokens.length ∧ stage = 3 ∧ detail = 1 ∧ nodes = 0 ∧ words = 0 ∧ position = 0 ∧
      CellEffect (CellSet.union (CellSet.singleton rawCell) (CellSet.singleton canonicalCell)) before after) ∨
    (tokens.length ≤ kinds.length ∧
      after.cellEntry? kindsCell = some { id := kindsCell, value := some (.array (signedI32Values
        (BufferCopy.tokenKinds tokens ++ kinds.drop tokens.length))) } ∧
      ∃ completion, ∃ outcome : RecognizerInitialContinuationOutcome grammarLayout grammar grammarWords
          (tokens.map (fun token => token.kind.gpuCode)) workspaceLayout completion,
        ∃ finalWorkspace finalValues,
          syntaxPost outcome finalWorkspace treeRecords treeOffsets recordsCell offsetsCell
            stage detail nodes words position after ∧
          RecognizerWorkspaceArtifact workspaceLayout finalWorkspace finalValues workspaceCell after)))

/-- Observing success excludes all lexer/token/parser/tree resource failures.
It yields the selected complete-input parse and exact serialized tree outputs. -/
theorem bodyPost.success
    (post : bodyPost request raw canonical kinds treeRecords treeOffsets
      rawCell canonicalCell kindsCell workspaceCell recordsCell offsetsCell grammarLayout grammar grammarWords workspaceLayout
      stage detail count nodes words position before after) (success : stage = 0) :
    request.outcome = .completed raw ∧ count = (canonicalizeTokens request.source raw).length ∧
    ∃ completion, ∃ outcome : RecognizerInitialContinuationOutcome grammarLayout grammar grammarWords
        ((canonicalizeTokens request.source raw).map (fun token => token.kind.gpuCode)) workspaceLayout completion,
      ∃ workspace, ∃ root : RecognizerRootResult grammar
        ((canonicalizeTokens request.source raw).map (fun token => token.kind.gpuCode)) workspace outcome.resultValue,
        detail = 0 ∧ position = 0 ∧
        nodes = (ParserTreeLayout.treeFrom 0 0 root.stored.tree).offsets.length ∧
        words = (ParserTreeLayout.treeFrom 0 0 root.stored.tree).words.length ∧
        after.cellEntry? recordsCell = some { id := recordsCell, value := some (.array (signedI32Values
          ((ParserTreeLayout.treeFrom 0 0 root.stored.tree).words ++ treeRecords.drop words))) } ∧
        after.cellEntry? offsetsCell = some { id := offsetsCell, value := some (.array (signedI32Values
          ((ParserTreeLayout.treeFrom 0 0 root.stored.tree).offsets.map Int.ofNat ++ treeOffsets.drop nodes))) } := by
  rcases post with early | ⟨completed, _, countEq, _, storage | ⟨_, _, completion, outcome, workspace, _, parsed, _⟩⟩
  · rcases early.1.stage with failed | failed <;> omega
  · have failed := storage.2.1
    omega
  · obtain ⟨root, fields⟩ := parsed.success success
    exact ⟨completed, countEq, completion, outcome, workspace, root, fields⟩

/-- The complete lexer-to-return source on ordinary caller resources, without
assuming lexer success or sufficient canonical/kind storage. This dispatches
logical outcomes, not caller-supplied execution certificates. Outer input guards
and the public function-call boundary remain separate from this statement. -/
theorem lex_to_return
    {visit : CheckedVisit program} {materializer : CheckedMaterialize visit}
    (tail : CheckedAfterParse materializer) (reader : LinkedReader visit.reader parserAllowed parserSymbols)
    (parsedType : materializer.parsedType = parserSymbols.typeId 0)
    (symbols : TokenizationSymbols) (early : CheckedEarly program symbols)
    (sameConstructor : early.constructor = tail.finish.constructor)
    (invariant : ∀ rename, Semantics.CellRenaming.Execution.ProgramInvariant rename verifiedFrontendCore)
    (lexerLink : Semantics.Relocation.Link lexerAllowed relocation verifiedFrontendCore program.core)
    (lexerInjective : Function.Injective relocation.typeId)
    (lexerInverseType : TypeId → TypeId) (lexerInverse : Function.RightInverse lexerInverseType relocation.typeId)
    (lexerRetained : lexerAllowed Functions.lexIntoFunction.id = true)
    (countAccessor : Source.CheckedProjection program ["verified", "raw_lexer"] "lex_token_count" (relocation.typeId 4) 1)
    (lexerId : symbols.lexer = relocation.functionId Functions.lexIntoFunction.id)
    (countId : symbols.count = countAccessor.source.function.id)
    (resultType : symbols.resultType = relocation.typeId 4)
    (canonicalizer : CheckedSource program.core symbols.canonicalize triviaId kindId keywordId matcher)
    (parserInverseType : TypeId → TypeId) (parserInverse : Function.RightInverse parserInverseType parserSymbols.typeId)
    (parserRetained : parserAllowed extractedParserRecognizeFunction.id = true)
    (request : Model.Request) (raw : List RawToken) (emitted : Model.emittedTokens request.outcome = raw)
    (records canonical kinds workspaceValues treeRecords treeOffsets : List Int)
    (wordCapacity : request.capacity = records.length / 3)
    (recordsFit : records.length ≤ 2147483647) (canonicalFit : canonical.length ≤ 2147483647)
    (kindsFit : kinds.length ≤ 2147483647)
    (grammarEncoded : EncodesGrammar grammarLayout grammar grammarWords)
    (grammarWellFormed : grammar.WellFormed) (wordsFit : grammarWords.length ≤ 2147483647)
    (workspaceLength : workspaceValues.length = workspaceLayout.workspaceLength)
    (workspaceTokenCount : workspaceLayout.tokenCount = (canonicalizeTokens request.source raw).length)
    (sourceCell rawCell canonicalCell kindsCell grammarCell workspaceCell recordsCell offsetsCell : CellId)
    (sourceRaw : sourceCell ≠ rawCell) (sourceCanonical : sourceCell ≠ canonicalCell)
    (sourceKinds : sourceCell ≠ kindsCell) (sourceWorkspace : sourceCell ≠ workspaceCell)
    (rawCanonical : rawCell ≠ canonicalCell) (rawKinds : rawCell ≠ kindsCell) (rawWorkspace : rawCell ≠ workspaceCell)
    (canonicalKinds : canonicalCell ≠ kindsCell) (canonicalWorkspace : canonicalCell ≠ workspaceCell)
    (grammarRaw : grammarCell ≠ rawCell) (grammarCanonical : grammarCell ≠ canonicalCell)
    (grammarKinds : grammarCell ≠ kindsCell) (grammarWorkspace : grammarCell ≠ workspaceCell)
    (kindsWorkspace : kindsCell ≠ workspaceCell)
    (outputSeparation : ∀ cell ∈ [sourceCell, rawCell, canonicalCell, kindsCell, grammarCell, workspaceCell],
      cell ≠ recordsCell ∧ cell ≠ offsetsCell)
    (outputsDistinct : recordsCell ≠ offsetsCell)
    (treeRecordsFit : treeRecords.length ≤ 2147483647) (treeOffsetsFit : treeOffsets.length ≤ 2147483647)
    (depthFit : depth ≤ 2147483647)
    (before : State) (wellFormed : StateWellFormed before)
    (sourceLocal : before.local? 0 = some (.slice Structure.i32Type sourceCell [] 0 request.source.length))
    (sourceLength : before.local? 1 = some (.signed .i32 request.source.length))
    (rawLocal : before.local? 4 = some (.slice Structure.i32Type rawCell [] 0 records.length))
    (rawLength : before.local? 5 = some (.signed .i32 records.length))
    (canonicalLocal : before.local? 6 = some (.slice Structure.i32Type canonicalCell [] 0 canonical.length))
    (canonicalLength : before.local? 7 = some (.signed .i32 canonical.length))
    (kindsLocal : before.local? 8 = some (.slice Structure.i32Type kindsCell [] 0 kinds.length))
    (kindsLength : before.local? 9 = some (.signed .i32 kinds.length))
    (grammarLocal : before.local? 2 = some (parserGrammarValue grammarWords grammarCell))
    (grammarLengthLocal : before.local? 3 = some (.signed .i32 (Int.ofNat grammarWords.length)))
    (workspaceLocal : before.local? 10 = some (workspaceValue workspaceValues workspaceCell))
    (workspaceLengthLocal : before.local? 11 = some (.signed .i32 (Int.ofNat workspaceValues.length)))
    (recordsLocal : before.local? 12 = some (.slice Structure.i32Type recordsCell [] 0 treeRecords.length))
    (recordsLengthLocal : before.local? 13 = some (.signed .i32 (Int.ofNat treeRecords.length)))
    (offsetsLocal : before.local? 14 = some (.slice Structure.i32Type offsetsCell [] 0 treeOffsets.length))
    (offsetsLengthLocal : before.local? 15 = some (.signed .i32 (Int.ofNat treeOffsets.length)))
    (depthLocal : before.local? 16 = some (.signed .i32 (Int.ofNat depth)))
    (owned : (ReadOnly.World.owns (ReadOnly.World.pair sourceCell (sourceIntegers request.source) rawCell records)).holds before)
    (canonicalContents : before.cellEntry? canonicalCell = some {
      id := canonicalCell, value := some (.array (signedI32Values canonical)) })
    (kindsContents : before.cellEntry? kindsCell = some {
      id := kindsCell, value := some (.array (signedI32Values kinds)) })
    (grammarContents : before.cellEntry? grammarCell = some {
      id := grammarCell, value := some (.array (signedI32Values grammarWords)) })
    (workspaceContents : before.cellEntry? workspaceCell = some {
      id := workspaceCell, value := some (.array (signedI32Values workspaceValues)) })
    (recordContents : before.cellEntry? recordsCell = some {
      id := recordsCell, value := some (.array (signedI32Values treeRecords)) })
    (offsetContents : before.cellEntry? offsetsCell = some {
      id := offsetsCell, value := some (.array (signedI32Values treeOffsets)) }) :
    ∃ stage detail : Int, ∃ count nodes words : Nat, ∃ position : Int, ∃ after,
      Executes program.core before (tokenizationBody symbols early.lexicalBody early.canonicalBody
        (recognitionBody (parserSymbols.functionId extractedParserRecognizeFunction.id) (parserSymbols.typeId 0)
          early.kindsBody tail.body))
        (.returned (some (syntaxResult tail.finish.constructor.typeId stage detail raw.length count nodes words position))) after ∧
      bodyPost request raw canonical kinds treeRecords treeOffsets rawCell canonicalCell kindsCell workspaceCell
        recordsCell offsetsCell grammarLayout grammar grammarWords workspaceLayout
        stage detail count nodes words position before after ∧
      (ReadOnly.World.owns (ReadOnly.World.pair sourceCell (sourceIntegers request.source) rawCell
        (encodeTokens raw ++ records.drop (3 * raw.length)))).holds after ∧
      CellEffect (syntaxWrites rawCell canonicalCell kindsCell workspaceCell recordsCell offsetsCell) before after := by
  by_cases proceed : request.outcome = .completed raw ∧ 3 * raw.length ≤ canonical.length
  · obtain ⟨successful, canonicalCapacity⟩ := proceed
    by_cases kindsCapacity : (canonicalizeTokens request.source raw).length ≤ kinds.length
    · obtain ⟨completion, outcome, workspace, finalValues, stage, detail, nodes, words, position,
          after, run, post, artifact, buffers, compacted, copied, effect⟩ :=
        lex_to_syntax tail reader parsedType symbols invariant lexerLink lexerInjective lexerInverseType lexerInverse
          lexerRetained countAccessor early.status lexerId countId early.statusId resultType early.lexerSuccess canonicalizer
          parserInverseType parserInverse parserRetained request raw successful records canonical kinds workspaceValues
          treeRecords treeOffsets wordCapacity recordsFit canonicalFit canonicalCapacity kindsFit kindsCapacity
          grammarEncoded grammarWellFormed wordsFit workspaceLength workspaceTokenCount
          sourceCell rawCell canonicalCell kindsCell grammarCell workspaceCell recordsCell offsetsCell
          sourceRaw sourceCanonical sourceKinds sourceWorkspace rawCanonical rawKinds rawWorkspace canonicalKinds canonicalWorkspace
          grammarRaw grammarCanonical grammarKinds grammarWorkspace kindsWorkspace outputSeparation outputsDistinct
          treeRecordsFit treeOffsetsFit depthFit before wellFormed sourceLocal sourceLength rawLocal rawLength
          canonicalLocal canonicalLength kindsLocal kindsLength grammarLocal grammarLengthLocal workspaceLocal workspaceLengthLocal
          recordsLocal recordsLengthLocal offsetsLocal offsetsLengthLocal depthLocal owned canonicalContents kindsContents
          grammarContents workspaceContents recordContents offsetContents
      refine ⟨stage, detail, (canonicalizeTokens request.source raw).length, nodes, words, position, after, ?_,
        Or.inr ⟨successful, canonicalCapacity, rfl, compacted,
          Or.inr ⟨kindsCapacity, copied, completion, outcome, workspace, finalValues, post, artifact⟩⟩, buffers, effect⟩
      simpa only [Int.ofNat_eq_natCast] using run early.lexicalBody early.canonicalBody early.kindsBody
    · have full : kinds.length < (canonicalizeTokens request.source raw).length := by omega
      obtain ⟨after, run, buffers, compacted, effect⟩ :=
        lex_to_kinds_failure early invariant lexerLink lexerInjective lexerInverseType lexerInverse lexerRetained countAccessor
          lexerId countId resultType canonicalizer request raw successful records canonical kinds.length
          wordCapacity recordsFit canonicalFit canonicalCapacity full sourceCell rawCell canonicalCell
          sourceRaw sourceCanonical rawCanonical before wellFormed sourceLocal sourceLength rawLocal rawLength
          canonicalLocal canonicalLength kindsLength owned canonicalContents
      refine ⟨3, 1, (canonicalizeTokens request.source raw).length, 0, 0, 0, after, ?_,
        Or.inr ⟨successful, canonicalCapacity, rfl, compacted,
          Or.inl ⟨full, rfl, rfl, rfl, rfl, rfl, effect⟩⟩, buffers, effect.weaken ?_⟩
      · simpa [sameConstructor] using run (parserSymbols.functionId extractedParserRecognizeFunction.id)
          (parserSymbols.typeId 0) tail.body
      · exact fun _ written => Or.inl (Or.inl written)
  · have rejected : ∀ tokens, request.outcome = .completed tokens → canonical.length < 3 * tokens.length := by
      intro tokens completed
      have same : tokens = raw := by simpa only [completed, Model.emittedTokens] using emitted
      subst tokens
      exact Nat.lt_of_not_ge (fun sufficient => proceed ⟨completed, sufficient⟩)
    obtain ⟨stage, detail, position, after, post, run, buffers, effect⟩ :=
      lex_to_early_failure early invariant lexerLink lexerInjective lexerInverseType lexerInverse lexerRetained countAccessor
        lexerId countId resultType request records canonical.length wordCapacity recordsFit canonicalFit rejected
        sourceCell rawCell sourceRaw before wellFormed sourceLocal sourceLength rawLocal rawLength canonicalLength owned
    refine ⟨stage, detail, 0, 0, 0, position, after, ?_, Or.inl ⟨post, rfl, rfl, rfl, effect⟩, ?_,
      effect.weaken (fun _ written => Or.inl (Or.inl (Or.inl written)))⟩
    · simpa [sameConstructor, emitted] using run
        (recognitionBody (parserSymbols.functionId extractedParserRecognizeFunction.id) (parserSymbols.typeId 0)
          early.kindsBody tail.body)
    · simpa only [emitted] using buffers

end Lanius.Extraction.Frontend
