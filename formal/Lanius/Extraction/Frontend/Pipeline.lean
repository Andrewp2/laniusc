import Lanius.Extraction.Frontend.Canonicalize
import Lanius.Extraction.Frontend.Recognize

namespace Lanius.Extraction.Frontend

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.FunctionalView.Core Lanius.Compiler.Lexer Lanius.Compiler.Parser
open Lanius.Extraction.RawLexer.LexInto
open Lanius.Extraction.CanonicalTokens CanonicalizeModel Compaction
open Lanius.Extraction.ParserRecognize Lanius.Extraction.ParserAccessors Lanius.Extraction.ParserFind

/-- The contiguous source prefix from lexer invocation through the bound parse
result. Intermediate buffers and calls are derived, not assumed. Logical lexer
success and token-storage capacity define this domain; parser failure remains
part of the returned outcome. The remaining continuation is the tree/result tail. -/
theorem lex_to_recognize
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
    (parserLink : Semantics.Relocation.Link parserAllowed parserSymbols verifiedParserCore program.core)
    (parserInjective : Function.Injective parserSymbols.typeId)
    (parserInverseType : TypeId → TypeId) (parserInverse : Function.RightInverse parserInverseType parserSymbols.typeId)
    (parserRetained : parserAllowed extractedParserRecognizeFunction.id = true)
    (request : Model.Request) (raw : List RawToken) (successful : request.outcome = .completed raw)
    (records canonical kinds workspaceValues : List Int) (wordCapacity : request.capacity = records.length / 3)
    (recordsFit : records.length ≤ 2147483647) (canonicalFit : canonical.length ≤ 2147483647)
    (canonicalCapacity : 3 * raw.length ≤ canonical.length)
    (kindsFit : kinds.length ≤ 2147483647) (kindsCapacity : (canonicalizeTokens request.source raw).length ≤ kinds.length)
    (grammarEncoded : EncodesGrammar grammarLayout grammar words)
    (grammarWellFormed : grammar.WellFormed) (wordsFit : words.length ≤ 2147483647)
    (workspaceLength : workspaceValues.length = workspaceLayout.workspaceLength)
    (workspaceTokenCount : workspaceLayout.tokenCount = (canonicalizeTokens request.source raw).length)
    (sourceCell rawCell canonicalCell kindsCell grammarCell workspaceCell : CellId)
    (sourceRaw : sourceCell ≠ rawCell) (sourceCanonical : sourceCell ≠ canonicalCell)
    (sourceKinds : sourceCell ≠ kindsCell) (sourceWorkspace : sourceCell ≠ workspaceCell)
    (rawCanonical : rawCell ≠ canonicalCell) (rawKinds : rawCell ≠ kindsCell) (rawWorkspace : rawCell ≠ workspaceCell)
    (canonicalKinds : canonicalCell ≠ kindsCell) (canonicalWorkspace : canonicalCell ≠ workspaceCell)
    (grammarRaw : grammarCell ≠ rawCell) (grammarCanonical : grammarCell ≠ canonicalCell)
    (grammarKinds : grammarCell ≠ kindsCell) (grammarWorkspace : grammarCell ≠ workspaceCell)
    (kindsWorkspace : kindsCell ≠ workspaceCell)
    (before : State) (wellFormed : StateWellFormed before)
    (sourceLocal : before.local? 0 = some (.slice Structure.i32Type sourceCell [] 0 request.source.length))
    (sourceLength : before.local? 1 = some (.signed .i32 request.source.length))
    (rawLocal : before.local? 4 = some (.slice Structure.i32Type rawCell [] 0 records.length))
    (rawLength : before.local? 5 = some (.signed .i32 records.length))
    (canonicalLocal : before.local? 6 = some (.slice Structure.i32Type canonicalCell [] 0 canonical.length))
    (canonicalLength : before.local? 7 = some (.signed .i32 canonical.length))
    (kindsLocal : before.local? 8 = some (.slice Structure.i32Type kindsCell [] 0 kinds.length))
    (kindsLength : before.local? 9 = some (.signed .i32 kinds.length))
    (grammarLocal : before.local? 2 = some (parserGrammarValue words grammarCell))
    (grammarLengthLocal : before.local? 3 = some (.signed .i32 (Int.ofNat words.length)))
    (workspaceLocal : before.local? 10 = some (workspaceValue workspaceValues workspaceCell))
    (workspaceLengthLocal : before.local? 11 = some (.signed .i32 (Int.ofNat workspaceValues.length)))
    (owned : (ReadOnly.World.owns (ReadOnly.World.pair sourceCell (sourceIntegers request.source) rawCell records)).holds before)
    (canonicalContents : before.cellEntry? canonicalCell = some {
      id := canonicalCell, value := some (.array (signedI32Values canonical)) })
    (kindsContents : before.cellEntry? kindsCell = some {
      id := kindsCell, value := some (.array (signedI32Values kinds)) })
    (grammarContents : before.cellEntry? grammarCell = some {
      id := grammarCell, value := some (.array (signedI32Values words)) })
    (workspaceContents : before.cellEntry? workspaceCell = some {
      id := workspaceCell, value := some (.array (signedI32Values workspaceValues)) }) :
    let tokens := canonicalizeTokens request.source raw
    let codes := tokens.map (fun token => token.kind.gpuCode)
    ∃ completion, ∃ (outcome : RecognizerInitialContinuationOutcome grammarLayout grammar words codes workspaceLayout completion),
      ∃ finalWorkspace finalValues ready,
      (∀ lexicalFailure canonicalFailure kindsFailure rest completion final,
        Executes program.core ready rest completion final →
        Executes program.core before (tokenizationBody symbols lexicalFailure canonicalFailure
          (recognitionBody (parserSymbols.functionId extractedParserRecognizeFunction.id) (parserSymbols.typeId 0)
            kindsFailure rest)) completion (restoreLocals before final)) ∧
      StateWellFormed ready ∧
      ready.local? 18 = some (.signed .i32 raw.length) ∧
      ready.local? 20 = some (.signed .i32 tokens.length) ∧
      ready.local? 22 = some (Core.Relocation.value parserSymbols outcome.resultValue) ∧
      outcome.workspaceAgrees finalWorkspace ∧
      WorkspaceAppendClosure workspaceLayout.capacity emptyWorkspace finalWorkspace ∧
      RecognizerWorkspaceArtifact workspaceLayout finalWorkspace finalValues workspaceCell ready ∧
      (ReadOnly.World.owns (ReadOnly.World.pair sourceCell (sourceIntegers request.source) rawCell
        (encodeTokens raw ++ records.drop (3 * raw.length)))).holds ready ∧
      ready.cellEntry? canonicalCell = some {
        id := canonicalCell, value := some (.array (signedI32Values
          (compactedBuffer raw (canonical.drop (3 * raw.length)) tokens))) } ∧
      ready.cellEntry? kindsCell = some {
        id := kindsCell, value := some (.array (signedI32Values (BufferCopy.tokenKinds tokens ++ kinds.drop tokens.length))) } ∧
      (∀ id value, id < 17 → before.local? id = some value →
        value ≠ .array (signedI32Values records) → value ≠ .array (signedI32Values canonical) →
        value ≠ .array (signedI32Values kinds) → value ≠ .array (signedI32Values workspaceValues) →
        ready.local? id = some value) ∧
      CellEffect (CellSet.union (CellSet.union (CellSet.singleton rawCell) (CellSet.singleton canonicalCell))
        (CellSet.union (CellSet.singleton kindsCell) (CellSet.singleton workspaceCell)))
        before (restoreLocals before ready) := by
  dsimp only
  obtain ⟨canonicalized, lexRun, canonicalWF, rawCount, tokenCount, rawBuffers, compacted, localsPreserved, lexerEffect⟩ :=
    lex_to_canonical symbols invariant lexerLink lexerInjective lexerInverseType lexerInverse lexerRetained
      countAccessor statusAccessor lexerId countId statusId resultType successConstant canonicalizer
      request raw successful records canonical wordCapacity recordsFit canonicalFit canonicalCapacity
      sourceCell rawCell canonicalCell sourceRaw sourceCanonical rawCanonical before wellFormed
      sourceLocal sourceLength rawLocal rawLength canonicalLocal canonicalLength owned canonicalContents
  have preservedEntry {cell : CellId} {value : Option Value}
      (found : before.cellEntry? cell = some { id := cell, value := value })
      (notRaw : cell ≠ rawCell) (notCanonical : cell ≠ canonicalCell) :
      canonicalized.cellEntry? cell = some { id := cell, value := value } :=
    lexerEffect.preserves_entry wellFormed found (by
      simp only [CellSet.union, CellSet.singleton, not_or]; exact ⟨notRaw, notCanonical⟩)
  have canonicalSize : 3 * raw.length + (canonical.drop (3 * raw.length)).length = canonical.length := by
    simp only [List.length_drop]; omega
  have canonicalReady : canonicalized.local? 6 = some
      (.slice Structure.i32Type canonicalCell [] 0 (3 * raw.length + (canonical.drop (3 * raw.length)).length)) := by
    rw [canonicalSize]
    exact localsPreserved 6 _ (by decide) canonicalLocal (by intro same; cases same) (by intro same; cases same)
  obtain ⟨completion, outcome, finalWorkspace, finalValues, ready, parseRun, readyWF, parsed,
      agreement, growth, artifact, finalCanonical, finalKinds, parseLocals, parseEffect⟩ :=
    canonical_to_recognize parserLink parserInjective parserInverseType parserInverse parserRetained
      request.source raw (canonical.drop (3 * raw.length)) kinds workspaceValues canonicalized canonicalWF
      canonicalCell kindsCell grammarCell workspaceCell canonicalKinds canonicalWorkspace grammarKinds grammarWorkspace
      kindsWorkspace (by simpa only [canonicalSize] using canonicalFit) kindsFit kindsCapacity
      grammarEncoded grammarWellFormed wordsFit workspaceLength workspaceTokenCount canonicalReady
      (localsPreserved 8 _ (by decide) kindsLocal (by intro same; cases same) (by intro same; cases same))
      (localsPreserved 9 _ (by decide) kindsLength (by intro same; cases same) (by intro same; cases same)) tokenCount
      (localsPreserved 2 _ (by decide) grammarLocal (by intro same; cases same) (by intro same; cases same))
      (localsPreserved 3 _ (by decide) grammarLengthLocal (by intro same; cases same) (by intro same; cases same))
      (localsPreserved 10 _ (by decide) workspaceLocal (by intro same; cases same) (by intro same; cases same))
      (localsPreserved 11 _ (by decide) workspaceLengthLocal (by intro same; cases same) (by intro same; cases same))
      compacted (preservedEntry kindsContents (Ne.symm rawKinds) (Ne.symm canonicalKinds))
      (preservedEntry grammarContents grammarRaw grammarCanonical)
      (preservedEntry workspaceContents (Ne.symm rawWorkspace) (Ne.symm canonicalWorkspace))
  refine ⟨completion, outcome, finalWorkspace, finalValues, ready, ?_, readyWF,
    parseLocals 18 _ (by decide) rawCount (by intro same; cases same) (by intro same; cases same),
    parseLocals 20 _ (by decide) tokenCount (by intro same; cases same) (by intro same; cases same),
    parsed, agreement, growth, artifact, ?_, finalCanonical, finalKinds, ?_,
    (lexerEffect.weaken CellSet.subset_union_left).transScoped
      (parseEffect.weaken CellSet.subset_union_right) wellFormed⟩
  · intro lexicalFailure canonicalFailure kindsFailure rest completion final continuation
    simpa only [restoreLocals] using lexRun lexicalFailure canonicalFailure _ _ _
      (parseRun kindsFailure rest completion final continuation)
  · have preserve {cell : CellId} {values : List Int}
        (found : canonicalized.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
        (notKinds : cell ≠ kindsCell) (notWorkspace : cell ≠ workspaceCell) :
        ready.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) } :=
      parseEffect.preserves_entry canonicalWF found (by
        simp only [CellSet.union, CellSet.singleton, not_or]; exact ⟨notKinds, notWorkspace⟩)
    intro cell values found
    by_cases first : cell = sourceCell
    · subst cell
      exact preserve (rawBuffers _ _ found) sourceKinds sourceWorkspace
    · have second : cell = rawCell := by
        by_cases second : cell = rawCell
        · exact second
        · simp [ReadOnly.World.pair, first, second] at found
      subst cell
      exact preserve (rawBuffers _ _ found) rawKinds rawWorkspace
  · intro id value early found notRaw notCanonical notKinds notWorkspace
    exact parseLocals id value (Nat.lt_of_lt_of_le early (by decide : 17 ≤ 21))
      (localsPreserved id value early found notRaw notCanonical) notKinds notWorkspace

end Lanius.Extraction.Frontend
