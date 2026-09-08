import Lanius.Extraction.Frontend.Pipeline
import Lanius.Extraction.Frontend.Tree
import Lanius.Extraction.Frontend.Early

namespace Lanius.Extraction.Frontend

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.FunctionalView.Core Lanius.Compiler.Lexer Lanius.Compiler.Parser
open Lanius.Extraction.RawLexer.LexInto
open Lanius.Extraction.CanonicalTokens CanonicalizeModel Compaction
open Lanius.Extraction.ParserRecognize Lanius.Extraction.ParserAccessors Lanius.Extraction.ParserFind
open Lanius.Extraction.ParserTreeSource Lanius.Extraction.ParserDerivation Lanius.Extraction.ParserResult

/-- Compose the checked adjacent source regions into the exact statement
executed below. Occurrence inside extract_syntax is distinct from proving its
outer guards and public call, which remain separate obligations. -/
theorem syntax_source_sequence {body : Stmt}
    (tokenization : Source.LocatedStatement Tokenization.body body)
    (recognition : Source.CheckedStatement RecognitionStage.body tokenization.locals.rest)
    (tail : CheckedAfterParse materializer) (tailEq : recognition.locals.rest = tail.body) :
    Source.StatementIn (tokenizationBody tokenization.locals.symbols tokenization.locals.lexicalFailure
      tokenization.locals.storageFailure (recognitionBody recognition.locals.functionId recognition.locals.resultType
        recognition.locals.storageFailure tail.body)) body := by
  have adjacent := recognition.exactSource
  rw [RecognitionStage.body, tailEq] at adjacent
  simpa only [Tokenization.body, adjacent] using tokenization.occurs

/-- The same adjacent statement with all three early return bodies checked
against the final tail's result constructor. -/
theorem syntax_source_all {body : Stmt}
    (tokenization : Source.LocatedStatement Tokenization.body body)
    (recognition : Source.CheckedStatement RecognitionStage.body tokenization.locals.rest)
    (tail : CheckedAfterParse materializer) (tailEq : recognition.locals.rest = tail.body)
    (early : EarlySource tail.finish.constructor tokenization.locals recognition.locals) :
    Source.StatementIn (tokenizationBody tokenization.locals.symbols early.checked.lexicalBody
      early.checked.canonicalBody (recognitionBody recognition.locals.functionId recognition.locals.resultType
        early.checked.kindsBody tail.body)) body := by
  simpa only [early.lexical, early.canonical, early.kinds] using
    syntax_source_sequence tokenization recognition tail tailEq

/-- The return contract retains the recognizer's selected workspace/tree, not
an unrelated valid parse. Parser failure leaves both tree buffers untouched;
tree resource failure carries bounded partial counts and cannot claim success. -/
def syntaxPost (outcome : RecognizerInitialContinuationOutcome grammarLayout grammar grammarWords codes layout completion)
    (workspace : LogicalWorkspace) (records offsets : List Int) (recordsCell offsetsCell : CellId)
    (stage detail : Int) (nodes words : Nat) (position : Int) (after : State) : Prop :=
  (stage = 4 ∧ (detail = 1 ∨ detail = 2) ∧ nodes = 0 ∧ words = 0 ∧
    ∃ states root, outcome.resultValue = parseResultValue detail states root position ∧
      after.cellEntry? recordsCell = some { id := recordsCell, value := some (.array (signedI32Values records)) } ∧
      after.cellEntry? offsetsCell = some { id := offsetsCell, value := some (.array (signedI32Values offsets)) }) ∨
  (∃ root : RecognizerRootResult grammar codes workspace outcome.resultValue,
    stage = extractionTreeStage detail ∧ position = 0 ∧
      (materializeRuntime root.root records offsets recordsCell offsetsCell).Result root.stored.tree detail nodes words after.cells)

/-- Observing extraction success certifies the selected complete-input parse
and its exact serialized buffers. Neither parser rejection nor partial tree
output can satisfy this contract. -/
theorem syntaxPost.success
    {outcome : RecognizerInitialContinuationOutcome grammarLayout grammar grammarWords codes layout completion}
    (post : syntaxPost outcome workspace records offsets recordsCell offsetsCell stage detail nodes words position after)
    (success : stage = 0) :
    ∃ root : RecognizerRootResult grammar codes workspace outcome.resultValue,
      detail = 0 ∧ position = 0 ∧
      nodes = (ParserTreeLayout.treeFrom 0 0 root.stored.tree).offsets.length ∧
      words = (ParserTreeLayout.treeFrom 0 0 root.stored.tree).words.length ∧
      after.cellEntry? recordsCell = some {
        id := recordsCell, value := some (.array (signedI32Values
          ((ParserTreeLayout.treeFrom 0 0 root.stored.tree).words ++ records.drop words))) } ∧
      after.cellEntry? offsetsCell = some {
        id := offsetsCell, value := some (.array (signedI32Values
          ((ParserTreeLayout.treeFrom 0 0 root.stored.tree).offsets.map Int.ofNat ++ offsets.drop nodes))) } := by
  rcases post with failure | ⟨root, stageEq, positionEq, output⟩
  · have failedStage := failure.1
    omega
  · have zero : detail = 0 := by
      by_cases zero : detail = 0
      · exact zero
      · simp only [extractionTreeStage, if_neg zero, success] at stageEq
        contradiction
    obtain ⟨nodesEq, wordsEq, recordOutput, offsetOutput⟩ := output.2.2.2.2.2 zero
    refine ⟨root, zero, positionEq, ?_⟩
    simpa only [materializeRuntime, Nat.zero_add, List.take_zero, List.nil_append, State.cellEntry?] using
      And.intro nodesEq (And.intro wordsEq (And.intro recordOutput offsetOutput))

/-- Execute the contiguous extract_syntax source from its lexer call through
its actual return. There is no continuation or intermediate-execution premise.
Lexical success and sufficient token storage define this domain; both parser
outcomes and all materializer resource outcomes are covered. Outer input guards
and early lexer/token-storage failures are separate remaining boundaries. -/
theorem lex_to_syntax
    {visit : CheckedVisit program} {materializer : CheckedMaterialize visit}
    (tail : CheckedAfterParse materializer) (reader : LinkedReader visit.reader parserAllowed parserSymbols)
    (parsedType : materializer.parsedType = parserSymbols.typeId 0)
    (symbols : TokenizationSymbols)
    (invariant : ∀ rename, Semantics.CellRenaming.Execution.ProgramInvariant rename verifiedFrontendCore)
    (lexerLink : Semantics.Relocation.Link lexerAllowed relocation verifiedFrontendCore program.core)
    (lexerInjective : Function.Injective relocation.typeId)
    (lexerInverseType : TypeId → TypeId) (lexerInverse : Function.RightInverse lexerInverseType relocation.typeId)
    (lexerRetained : lexerAllowed Functions.lexIntoFunction.id = true)
    (countAccessor : Source.CheckedProjection program ["verified", "raw_lexer"] "lex_token_count" (relocation.typeId 4) 1)
    (statusAccessor : Source.CheckedProjection program ["verified", "raw_lexer"] "lex_status" symbols.resultType 0)
    (lexerId : symbols.lexer = relocation.functionId Functions.lexIntoFunction.id)
    (countId : symbols.count = countAccessor.source.function.id)
    (statusId : symbols.status = statusAccessor.source.function.id)
    (resultType : symbols.resultType = relocation.typeId 4)
    (successConstant : Trivia.ConstantAt program.core symbols.success 0)
    (canonicalizer : CheckedSource program.core symbols.canonicalize triviaId kindId keywordId matcher)
    (parserInverseType : TypeId → TypeId) (parserInverse : Function.RightInverse parserInverseType parserSymbols.typeId)
    (parserRetained : parserAllowed extractedParserRecognizeFunction.id = true)
    (request : Model.Request) (raw : List RawToken) (successful : request.outcome = .completed raw)
    (records canonical kinds workspaceValues treeRecords treeOffsets : List Int)
    (wordCapacity : request.capacity = records.length / 3)
    (recordsFit : records.length ≤ 2147483647) (canonicalFit : canonical.length ≤ 2147483647)
    (canonicalCapacity : 3 * raw.length ≤ canonical.length)
    (kindsFit : kinds.length ≤ 2147483647) (kindsCapacity : (canonicalizeTokens request.source raw).length ≤ kinds.length)
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
    let tokens := canonicalizeTokens request.source raw
    let codes := tokens.map (fun token => token.kind.gpuCode)
    ∃ completion, ∃ (outcome : RecognizerInitialContinuationOutcome grammarLayout grammar grammarWords codes workspaceLayout completion),
      ∃ finalWorkspace finalValues stage detail nodes words position after,
      (∀ lexicalFailure canonicalFailure kindsFailure,
        Executes program.core before (tokenizationBody symbols lexicalFailure canonicalFailure
          (recognitionBody (parserSymbols.functionId extractedParserRecognizeFunction.id) (parserSymbols.typeId 0)
            kindsFailure tail.body))
          (.returned (some (syntaxResult tail.finish.constructor.typeId stage detail (Int.ofNat raw.length)
            (Int.ofNat tokens.length) (Int.ofNat nodes) (Int.ofNat words) position))) after) ∧
      syntaxPost outcome finalWorkspace treeRecords treeOffsets recordsCell offsetsCell stage detail nodes words position after ∧
      RecognizerWorkspaceArtifact workspaceLayout finalWorkspace finalValues workspaceCell after ∧
      (ReadOnly.World.owns (ReadOnly.World.pair sourceCell (sourceIntegers request.source) rawCell
        (encodeTokens raw ++ records.drop (3 * raw.length)))).holds after ∧
      after.cellEntry? canonicalCell = some {
        id := canonicalCell, value := some (.array (signedI32Values
          (compactedBuffer raw (canonical.drop (3 * raw.length)) tokens))) } ∧
      after.cellEntry? kindsCell = some {
        id := kindsCell, value := some (.array (signedI32Values (BufferCopy.tokenKinds tokens ++ kinds.drop tokens.length))) } ∧
      CellEffect (CellSet.union
        (CellSet.union (CellSet.union (CellSet.singleton rawCell) (CellSet.singleton canonicalCell))
          (CellSet.union (CellSet.singleton kindsCell) (CellSet.singleton workspaceCell)))
        (CellSet.union (CellSet.singleton recordsCell) (CellSet.singleton offsetsCell))) before after := by
  dsimp only
  let tokens := canonicalizeTokens request.source raw
  let codes := tokens.map (fun token => token.kind.gpuCode)
  obtain ⟨completion, outcome, finalWorkspace, finalValues, ready, prefixRun, readyWF, rawCount, tokenCount,
      parsed, agreement, growth, artifact, rawBuffers, compacted, kindBuffer, localsPreserved, prefixEffect⟩ :=
    lex_to_recognize symbols invariant lexerLink lexerInjective lexerInverseType lexerInverse lexerRetained
      countAccessor statusAccessor lexerId countId statusId resultType successConstant canonicalizer
      reader.link reader.injective parserInverseType parserInverse parserRetained request raw successful
      records canonical kinds workspaceValues wordCapacity recordsFit canonicalFit canonicalCapacity kindsFit kindsCapacity
      grammarEncoded grammarWellFormed wordsFit workspaceLength workspaceTokenCount
      sourceCell rawCell canonicalCell kindsCell grammarCell workspaceCell
      sourceRaw sourceCanonical sourceKinds sourceWorkspace rawCanonical rawKinds rawWorkspace canonicalKinds canonicalWorkspace
      grammarRaw grammarCanonical grammarKinds grammarWorkspace kindsWorkspace before wellFormed
      sourceLocal sourceLength rawLocal rawLength canonicalLocal canonicalLength kindsLocal kindsLength grammarLocal grammarLengthLocal
      workspaceLocal workspaceLengthLocal owned canonicalContents kindsContents grammarContents workspaceContents
  have readyLocal {id : VarId} {value : Value} (early : id < 17) (found : before.local? id = some value)
      (plain : ∀ values, value ≠ .array values) : ready.local? id = some value :=
    localsPreserved id value early found (plain _) (plain _) (plain _) (plain _)
  have outputReady {cell : CellId} {values : List Int}
      (found : before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
      (notWritten : ∀ other ∈ [rawCell, canonicalCell, kindsCell, workspaceCell], cell ≠ other) :
      ready.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) } :=
    prefixEffect.preserves_entry wellFormed found (by
      rintro ((raw | canonical) | (kinds | workspace))
      · exact notWritten rawCell (by simp) raw
      · exact notWritten canonicalCell (by simp) canonical
      · exact notWritten kindsCell (by simp) kinds
      · exact notWritten workspaceCell (by simp) workspace)
  have outputSeparate {cell : CellId} (member : cell ∈ [rawCell, canonicalCell, kindsCell, workspaceCell]) :
      cell ≠ recordsCell ∧ cell ≠ offsetsCell := by
    apply outputSeparation cell
    simp only [List.mem_cons, List.not_mem_nil, or_false] at member ⊢
    rcases member with same | same | same | same <;> simp [same]
  have recordsReady := outputReady recordContents (fun _ member => Ne.symm (outputSeparate member).1)
  have offsetsReady := outputReady offsetContents (fun _ member => Ne.symm (outputSeparate member).2)
  let outputWrites := CellSet.union (CellSet.singleton recordsCell) (CellSet.singleton offsetsCell)
  have returned : ∃ stage detail nodes words position done,
      Executes program.core ready tail.body
        (.returned (some (syntaxResult tail.finish.constructor.typeId stage detail (Int.ofNat raw.length)
          (Int.ofNat tokens.length) (Int.ofNat nodes) (Int.ofNat words) position))) done ∧
      syntaxPost outcome finalWorkspace treeRecords treeOffsets recordsCell offsetsCell stage detail nodes words position done ∧
      RecognizerWorkspaceArtifact workspaceLayout finalWorkspace finalValues workspaceCell done ∧
      CellEffect outputWrites ready done := by
    by_cases accepted : parseResultStatus? outcome.resultValue = some 0
    · have workspaceSize : finalValues.length = workspaceValues.length := artifact.workspaceLength.trans workspaceLength.symm
      have liveWorkspace : ready.local? 10 = some (.slice Structure.i32Type workspaceCell [] 0 finalValues.length) := by
        rw [workspaceSize]
        exact readyLocal (by decide) workspaceLocal (by intro values same; cases same)
      have liveWorkspaceLength : ready.local? 11 = some (.signed .i32 (Int.ofNat finalValues.length)) := by
        rw [workspaceSize]
        exact readyLocal (by decide) workspaceLengthLocal (by intro values same; cases same)
      obtain ⟨code, nodes, words, done, executed, tree, retained, effect⟩ :=
        tail.accepted reader parserInverseType parserInverse parsedType outcome agreement accepted ready readyWF artifact
          (by simpa only [codes, tokens, List.length_map] using workspaceTokenCount) parsed
          (by simpa only [Int.ofNat_eq_natCast] using rawCount)
          (by simpa only [codes, tokens, List.length_map, Int.ofNat_eq_natCast] using tokenCount)
          liveWorkspace liveWorkspaceLength
          (readyLocal (by decide) recordsLocal (by intro values same; cases same))
          (readyLocal (by decide) recordsLengthLocal (by intro values same; cases same))
          (readyLocal (by decide) offsetsLocal (by intro values same; cases same))
          (readyLocal (by decide) offsetsLengthLocal (by intro values same; cases same))
          (readyLocal (by decide) depthLocal (by intro values same; cases same)) recordsReady offsetsReady
          (outputSeparation workspaceCell (by simp)).1 (outputSeparation workspaceCell (by simp)).2
          outputsDistinct treeRecordsFit treeOffsetsFit depthFit
      refine ⟨extractionTreeStage code, code, nodes, words, 0, done, ?_,
        Or.inr ⟨outcome.successRoot agreement accepted, rfl, rfl, tree⟩, retained, effect⟩
      simpa only [tokens, List.length_map, Int.ofNat_eq_natCast, Int.ofNat_zero] using executed
    · obtain ⟨code, states, root, position, done, fields, codeFailure, executed, effect⟩ :=
        tail.rejected_outcome parserSymbols parsedType outcome accepted ready readyWF parsed
          (by simpa only [Int.ofNat_eq_natCast] using rawCount)
          (by simpa only [codes, tokens, List.length_map, Int.ofNat_eq_natCast] using tokenCount)
      refine ⟨4, code, 0, 0, position, done, ?_,
        Or.inl ⟨rfl, codeFailure, rfl, rfl, states, root, fields,
          effect.empty_preserves_entry readyWF recordsReady, effect.empty_preserves_entry readyWF offsetsReady⟩,
        ⟨artifact.workspaceLength, artifact.workspaceEncoded, effect.empty_preserves_entry readyWF artifact.workspaceBacking⟩,
        effect.weaken CellSet.empty_subset⟩
      simpa only [tokens, List.length_map, Int.ofNat_eq_natCast, Int.ofNat_zero] using executed
  obtain ⟨stage, detail, nodes, words, position, done, executed, post, retained, tailEffect⟩ := returned
  have preserve {cell : CellId} {values : List Int}
      (found : ready.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
      (member : cell ∈ [sourceCell, rawCell, canonicalCell, kindsCell, grammarCell, workspaceCell]) :
      done.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) } :=
    tailEffect.preserves_entry readyWF found (fun written => written.elim
      (outputSeparation cell member).1 (outputSeparation cell member).2)
  have sourceBuffers : (ReadOnly.World.owns (ReadOnly.World.pair sourceCell (sourceIntegers request.source) rawCell
      (encodeTokens raw ++ records.drop (3 * raw.length)))).holds done := by
    intro cell values found
    by_cases first : cell = sourceCell
    · subst cell; exact preserve (rawBuffers _ _ found) (by simp)
    · have second : cell = rawCell := by
        by_cases second : cell = rawCell
        · exact second
        · simp [ReadOnly.World.pair, first, second] at found
      subst cell; exact preserve (rawBuffers _ _ found) (by simp)
  have restored : restoreLocals ready done = done := by
    simp only [restoreLocals, ← tailEffect.locals]
  refine ⟨completion, outcome, finalWorkspace, finalValues, stage, detail, nodes, words, position,
    restoreLocals before done, ?_, post, retained.transfer_cells rfl, sourceBuffers,
    preserve compacted (by simp), preserve kindBuffer (by simp),
    (prefixEffect.weaken CellSet.subset_union_left).transScoped
      (show CellEffect _ ready (restoreLocals ready done) from by rw [restored]; exact tailEffect.weaken CellSet.subset_union_right) wellFormed⟩
  intro lexicalFailure canonicalFailure kindsFailure
  simpa only [Int.ofNat_eq_natCast] using prefixRun lexicalFailure canonicalFailure kindsFailure _ _ _ executed

end Lanius.Extraction.Frontend
