import Lanius.Extraction.Frontend.Function

namespace Lanius.Extraction.Frontend

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.Compiler.Lexer Lanius.Compiler.Parser
open Lanius.Extraction.RawLexer.LexInto
open Lanius.Extraction.CanonicalTokens CanonicalizeModel Compaction
open Lanius.Extraction.ParserRecognize Lanius.Extraction.ParserAccessors Lanius.Extraction.ParserFind
open Lanius.Extraction.ParserTreeSource Lanius.Extraction.ParserDerivation Lanius.Extraction.ParserResult

variable {program : CoreSynthesis.Program.CheckedProgram artifacts}
variable {visit : CheckedVisit program} {materializer : CheckedMaterialize visit}

/-- Ordinary source, buffer, grammar and resource data for the public call.
This contains no execution evidence or internal parser invariant. -/
structure SyntaxData where
  request : Model.Request
  records : List Int
  canonical : List Int
  kinds : List Int
  workspaceValues : List Int
  treeRecords : List Int
  treeOffsets : List Int
  grammarLayout : PackedGrammarLayout
  grammar : IndexedGrammar
  grammarWords : List Int
  workspaceLayout : WorkspaceLayout
  sourceCell : CellId
  rawCell : CellId
  canonicalCell : CellId
  kindsCell : CellId
  grammarCell : CellId
  workspaceCell : CellId
  recordsCell : CellId
  offsetsCell : CellId
  depth : Nat

def SyntaxData.raw (data : SyntaxData) : List RawToken := Model.emittedTokens data.request.outcome
def SyntaxData.tokens (data : SyntaxData) := canonicalizeTokens data.request.source data.raw

def SyntaxData.values (data : SyntaxData) : List Value :=
  [.slice Structure.i32Type data.sourceCell [] 0 data.request.source.length, .signed .i32 data.request.source.length,
    .slice Structure.i32Type data.grammarCell [] 0 data.grammarWords.length, .signed .i32 data.grammarWords.length,
    .slice Structure.i32Type data.rawCell [] 0 data.records.length, .signed .i32 data.records.length,
    .slice Structure.i32Type data.canonicalCell [] 0 data.canonical.length, .signed .i32 data.canonical.length,
    .slice Structure.i32Type data.kindsCell [] 0 data.kinds.length, .signed .i32 data.kinds.length,
    .slice Structure.i32Type data.workspaceCell [] 0 data.workspaceValues.length, .signed .i32 data.workspaceValues.length,
    .slice Structure.i32Type data.recordsCell [] 0 data.treeRecords.length, .signed .i32 data.treeRecords.length,
    .slice Structure.i32Type data.offsetsCell [] 0 data.treeOffsets.length, .signed .i32 data.treeOffsets.length,
    .signed .i32 data.depth]

def SyntaxData.environment (data : SyntaxData) : Fin 17 → Value := fun index => data.values.get index
def SyntaxData.bindings (data : SyntaxData) := parameterBindings data.environment
def SyntaxData.Locals (data : SyntaxData) (state : State) : Prop :=
  ∀ index : Fin 17, state.local? index.val = some (data.environment index)

structure SyntaxData.Valid (data : SyntaxData) : Prop where
  wordCapacity : data.request.capacity = data.records.length / 3
  recordsFit : data.records.length ≤ 2147483647
  canonicalFit : data.canonical.length ≤ 2147483647
  kindsFit : data.kinds.length ≤ 2147483647
  grammarEncoded : EncodesGrammar data.grammarLayout data.grammar data.grammarWords
  grammarWellFormed : data.grammar.WellFormed
  wordsFit : data.grammarWords.length ≤ 2147483647
  workspaceLength : data.workspaceValues.length = data.workspaceLayout.workspaceLength
  workspaceTokenCount : data.workspaceLayout.tokenCount = data.tokens.length
  sourceRaw : data.sourceCell ≠ data.rawCell
  sourceCanonical : data.sourceCell ≠ data.canonicalCell
  sourceKinds : data.sourceCell ≠ data.kindsCell
  sourceWorkspace : data.sourceCell ≠ data.workspaceCell
  rawCanonical : data.rawCell ≠ data.canonicalCell
  rawKinds : data.rawCell ≠ data.kindsCell
  rawWorkspace : data.rawCell ≠ data.workspaceCell
  canonicalKinds : data.canonicalCell ≠ data.kindsCell
  canonicalWorkspace : data.canonicalCell ≠ data.workspaceCell
  grammarRaw : data.grammarCell ≠ data.rawCell
  grammarCanonical : data.grammarCell ≠ data.canonicalCell
  grammarKinds : data.grammarCell ≠ data.kindsCell
  grammarWorkspace : data.grammarCell ≠ data.workspaceCell
  kindsWorkspace : data.kindsCell ≠ data.workspaceCell
  outputSeparation : ∀ cell ∈ [data.sourceCell, data.rawCell, data.canonicalCell, data.kindsCell, data.grammarCell, data.workspaceCell],
    cell ≠ data.recordsCell ∧ cell ≠ data.offsetsCell
  outputsDistinct : data.recordsCell ≠ data.offsetsCell
  treeRecordsFit : data.treeRecords.length ≤ 2147483647
  treeOffsetsFit : data.treeOffsets.length ≤ 2147483647
  depthFit : data.depth ≤ 2147483647

structure SyntaxData.Owns (data : SyntaxData) (state : State) : Prop where
  sourceRaw : (ReadOnly.World.owns (ReadOnly.World.pair data.sourceCell (sourceIntegers data.request.source)
    data.rawCell data.records)).holds state
  canonical : state.cellEntry? data.canonicalCell = some {
    id := data.canonicalCell, value := some (.array (signedI32Values data.canonical)) }
  kinds : state.cellEntry? data.kindsCell = some {
    id := data.kindsCell, value := some (.array (signedI32Values data.kinds)) }
  grammar : state.cellEntry? data.grammarCell = some {
    id := data.grammarCell, value := some (.array (signedI32Values data.grammarWords)) }
  workspace : state.cellEntry? data.workspaceCell = some {
    id := data.workspaceCell, value := some (.array (signedI32Values data.workspaceValues)) }
  records : state.cellEntry? data.recordsCell = some {
    id := data.recordsCell, value := some (.array (signedI32Values data.treeRecords)) }
  offsets : state.cellEntry? data.offsetsCell = some {
    id := data.offsetsCell, value := some (.array (signedI32Values data.treeOffsets)) }

def SyntaxData.Post (data : SyntaxData) := bodyPost data.request data.raw data.canonical data.kinds
  data.treeRecords data.treeOffsets data.rawCell data.canonicalCell data.kindsCell data.workspaceCell
  data.recordsCell data.offsetsCell data.grammarLayout data.grammar data.grammarWords data.workspaceLayout

def SyntaxData.RawOutput (data : SyntaxData) (after : State) : Prop :=
  (ReadOnly.World.owns (ReadOnly.World.pair data.sourceCell (sourceIntegers data.request.source) data.rawCell
    (encodeTokens data.raw ++ data.records.drop (3 * data.raw.length)))).holds after

def SyntaxData.writes (data : SyntaxData) := syntaxWrites data.rawCell data.canonicalCell data.kindsCell
  data.workspaceCell data.recordsCell data.offsetsCell

/-- Checked component links used by the existing body theorem. Grouping these
static facts keeps the public caller's dynamic resources separate. -/
structure LinkedSyntax (checked : CheckedSyntax materializer) where
  invariant : ∀ rename, Semantics.CellRenaming.Execution.ProgramInvariant rename verifiedFrontendCore
  lexerAllowed : FunctionId → Bool
  lexerSymbols : Core.Relocation.Symbols
  lexerLink : Semantics.Relocation.Link lexerAllowed lexerSymbols verifiedFrontendCore program.core
  lexerInjective : Function.Injective lexerSymbols.typeId
  lexerInverseType : TypeId → TypeId
  lexerInverse : Function.RightInverse lexerInverseType lexerSymbols.typeId
  lexerRetained : lexerAllowed Functions.lexIntoFunction.id = true
  countAccessor : Source.CheckedProjection program ["verified", "raw_lexer"] "lex_token_count" (lexerSymbols.typeId 4) 1
  lexerId : checked.symbols.lexer = lexerSymbols.functionId Functions.lexIntoFunction.id
  countId : checked.symbols.count = countAccessor.source.function.id
  resultType : checked.symbols.resultType = lexerSymbols.typeId 4
  triviaId : FunctionId
  kindId : FunctionId
  keywordId : FunctionId
  matcher : FunctionId
  canonicalizer : CheckedSource program.core checked.symbols.canonicalize triviaId kindId keywordId matcher
  parserAllowed : FunctionId → Bool
  parserSymbols : Core.Relocation.Symbols
  reader : LinkedReader visit.reader parserAllowed parserSymbols
  parsedType : materializer.parsedType = parserSymbols.typeId 0
  parserId : checked.parserId = parserSymbols.functionId extractedParserRecognizeFunction.id
  parserType : checked.parserType = parserSymbols.typeId 0
  parserInverseType : TypeId → TypeId
  parserInverse : Function.RightInverse parserInverseType parserSymbols.typeId
  parserRetained : parserAllowed extractedParserRecognizeFunction.id = true

theorem SyntaxData.lengths_nonnegative {data : SyntaxData} (locals : data.Locals before) :
    ∀ entry ∈ inputLengths, ∃ length, before.local? entry.1 = some (.signed .i32 length) ∧ 0 ≤ length := by
  intro entry member
  simp only [inputLengths, List.mem_cons, List.not_mem_nil, or_false] at member
  rcases member with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl
  · exact ⟨_, locals ⟨1, by decide⟩, Int.natCast_nonneg _⟩
  · exact ⟨_, locals ⟨3, by decide⟩, Int.natCast_nonneg _⟩
  · exact ⟨_, locals ⟨5, by decide⟩, Int.natCast_nonneg _⟩
  · exact ⟨_, locals ⟨7, by decide⟩, Int.natCast_nonneg _⟩
  · exact ⟨_, locals ⟨9, by decide⟩, Int.natCast_nonneg _⟩
  · exact ⟨_, locals ⟨11, by decide⟩, Int.natCast_nonneg _⟩
  · exact ⟨_, locals ⟨13, by decide⟩, Int.natCast_nonneg _⟩
  · exact ⟨_, locals ⟨15, by decide⟩, Int.natCast_nonneg _⟩

/-- The exact function body, including all outer guards, from ordinary local
values and owned buffers. No caller-supplied component execution is required. -/
theorem CheckedSyntax.body_executes (checked : CheckedSyntax materializer) (linked : LinkedSyntax checked)
    (data : SyntaxData) (valid : data.Valid) (wellFormed : StateWellFormed before)
    (locals : data.Locals before) (owned : data.Owns before) :
    ∃ stage detail : Int, ∃ count nodes words : Nat, ∃ position : Int, ∃ after,
      Executes program.core before (syntaxFunctionBody checked.tail checked.early checked.inputs checked.parserId checked.parserType)
        (.returned (some (syntaxResult checked.tail.finish.constructor.typeId stage detail data.raw.length count nodes words position))) after ∧
      data.Post stage detail count nodes words position before after ∧ data.RawOutput after ∧
      CellEffect data.writes before after := by
  obtain ⟨stage, detail, count, nodes, words, position, after, run, post, buffers, effect⟩ :=
    lex_to_return checked.tail linked.reader linked.parsedType checked.symbols checked.early checked.sameConstructor
      linked.invariant linked.lexerLink linked.lexerInjective linked.lexerInverseType linked.lexerInverse linked.lexerRetained
      linked.countAccessor linked.lexerId linked.countId linked.resultType linked.canonicalizer
      linked.parserInverseType linked.parserInverse linked.parserRetained data.request data.raw rfl
      data.records data.canonical data.kinds data.workspaceValues data.treeRecords data.treeOffsets
      valid.wordCapacity valid.recordsFit valid.canonicalFit valid.kindsFit valid.grammarEncoded valid.grammarWellFormed
      valid.wordsFit valid.workspaceLength valid.workspaceTokenCount
      data.sourceCell data.rawCell data.canonicalCell data.kindsCell data.grammarCell data.workspaceCell data.recordsCell data.offsetsCell
      valid.sourceRaw valid.sourceCanonical valid.sourceKinds valid.sourceWorkspace valid.rawCanonical valid.rawKinds valid.rawWorkspace
      valid.canonicalKinds valid.canonicalWorkspace valid.grammarRaw valid.grammarCanonical valid.grammarKinds valid.grammarWorkspace
      valid.kindsWorkspace valid.outputSeparation valid.outputsDistinct valid.treeRecordsFit valid.treeOffsetsFit valid.depthFit
      before wellFormed (locals ⟨0, by decide⟩) (locals ⟨1, by decide⟩) (locals ⟨4, by decide⟩) (locals ⟨5, by decide⟩)
      (locals ⟨6, by decide⟩) (locals ⟨7, by decide⟩) (locals ⟨8, by decide⟩) (locals ⟨9, by decide⟩)
      (locals ⟨2, by decide⟩) (locals ⟨3, by decide⟩) (locals ⟨10, by decide⟩) (locals ⟨11, by decide⟩)
      (locals ⟨12, by decide⟩) (locals ⟨13, by decide⟩) (locals ⟨14, by decide⟩) (locals ⟨15, by decide⟩)
      (locals ⟨16, by decide⟩) owned.sourceRaw owned.canonical owned.kinds owned.grammar owned.workspace owned.records owned.offsets
  refine ⟨stage, detail, count, nodes, words, position, after, ?_, post, buffers, effect⟩
  apply inputGuards.pass program.core _ _ inputLengths (data.lengths_nonnegative locals)
  simpa only [linked.parserId, linked.parserType] using run

theorem SyntaxData.Owns.entered {data : SyntaxData} (owned : data.Owns before)
    (wellFormed : StateWellFormed before) (bindings : List (VarId × Value)) : data.Owns (enterCall before bindings) := by
  have preserve {cell : CellId} {value : Option Value}
      (found : before.cellEntry? cell = some { id := cell, value := value }) :
      (enterCall before bindings).cellEntry? cell = some { id := cell, value := value } :=
    ((enterCall_effect before bindings).oldCells cell
      (StateWellFormed.cell_lt_next_of_entry wellFormed found) (by simp [CellSet.empty])).trans found
  exact ⟨fun cell values found => preserve (owned.sourceRaw cell values found), preserve owned.canonical,
    preserve owned.kinds, preserve owned.grammar, preserve owned.workspace, preserve owned.records, preserve owned.offsets⟩

/-- Close the caller scope in every result branch, including the narrower early
write footprints. The selected parser and exact output buffers remain the same. -/
theorem SyntaxData.Post.closeCall {data : SyntaxData} {bindings : List (VarId × Value)} (wellFormed : StateWellFormed before)
    (post : data.Post stage detail count nodes words position (enterCall before bindings) after) :
    data.Post stage detail count nodes words position before (restoreLocals before after) := by
  rcases post with ⟨early, countEq, nodesEq, wordsEq, effect⟩ |
    ⟨completed, capacity, countEq, canonical, storage | ⟨kindsFit, kinds, completion, outcome, workspace, values, parsed, artifact⟩⟩
  · exact Or.inl ⟨early, countEq, nodesEq, wordsEq, CellEffect.closeCall before bindings wellFormed effect⟩
  · obtain ⟨full, stageEq, detailEq, nodesEq, wordsEq, positionEq, effect⟩ := storage
    exact Or.inr ⟨completed, capacity, countEq, canonical,
      Or.inl ⟨full, stageEq, detailEq, nodesEq, wordsEq, positionEq, CellEffect.closeCall before bindings wellFormed effect⟩⟩
  · exact Or.inr ⟨completed, capacity, countEq, canonical,
      Or.inr ⟨kindsFit, kinds, completion, outcome, workspace, values, parsed, artifact.transfer_cells rfl⟩⟩

/-- Execute the current public extract_syntax call. Parameter bindings and all
internal resources are derived from the actual argument values and caller-owned
buffers; the caller supplies no callee state or intermediate execution. -/
theorem CheckedSyntax.call_evaluates (checked : CheckedSyntax materializer) (linked : LinkedSyntax checked)
    (data : SyntaxData) (valid : data.Valid) (wellFormed : StateWellFormed before)
    (owned : data.Owns before)
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments data.values before) :
    ∃ stage detail : Int, ∃ count nodes words : Nat, ∃ position : Int, ∃ after,
      Evaluates program.core caller (.call checked.source.function.id arguments)
        (syntaxResult checked.tail.finish.constructor.typeId stage detail data.raw.length count nodes words position) after ∧
      data.Post stage detail count nodes words position before after ∧ data.RawOutput after ∧
      CellEffect data.writes before after := by
  let callee := enterCall before data.bindings
  have locals : data.Locals callee := enterCall_parameterBindings_matches wellFormed
  obtain ⟨stage, detail, count, nodes, words, position, after, run, post, buffers, effect⟩ :=
    checked.body_executes linked data valid (enterCall_preserves_wellFormed wellFormed) locals (owned.entered wellFormed _)
  have identity : checked.source.function.id = checked.source.source.id := by
    simpa [Program.function?] using List.find?_some checked.source.found
  have found : program.core.function? checked.source.function.id = some checked.source.function := by
    rw [identity]; exact checked.source.found
  have bound : bindParameters checked.source.function.parameters data.values = some data.bindings := by
    rw [checked.signature.1]
    rfl
  exact ⟨stage, detail, count, nodes, words, position, restoreLocals before after,
    evaluatesCallReturned argumentsResult found bound checked.body run, post.closeCall wellFormed, buffers,
    CellEffect.closeCall before data.bindings wellFormed effect⟩

def syntaxArgumentValues (environment : Fin 17 → Value) : List Value := (List.finRange 17).map environment

def syntaxArgumentLookup (environment : Fin 17 → Value) (id : VarId) : Option Value :=
  if bound : id < 17 then some (environment ⟨id, bound⟩) else none

/-- Negative-length rejection at the public call boundary. Only the scalar
arguments up to the first error matter; no buffer contents, lengths, grammar,
lexer link, or parser execution assumptions are required. -/
theorem CheckedSyntax.reject_call (checked : CheckedSyntax materializer)
    (environment : Fin 17 → Value) (wellFormed : StateWellFormed before)
    (failed : FirstNegative (syntaxArgumentLookup environment) inputLengths detail)
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments (syntaxArgumentValues environment) before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments)
        (syntaxResult checked.tail.finish.constructor.typeId 1 detail 0 0 0 0 0) after ∧
      CellEffect CellSet.empty before after := by
  let bindings := parameterBindings environment
  let callee := enterCall before bindings
  have locals (index : Fin 17) : callee.local? index.val = some (environment index) :=
    enterCall_parameterBindings_matches wellFormed index
  have failedLocal : FirstNegative callee.local? inputLengths detail := failed.transfer (by
    intro entry member
    have bound : entry.1 < 17 := by
      simp only [inputLengths, List.mem_cons, List.not_mem_nil, or_false] at member
      rcases member with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;> decide
    simpa only [syntaxArgumentLookup, dif_pos bound] using locals ⟨entry.1, bound⟩)
  obtain ⟨after, run, effect⟩ := checked.inputs.reject (enterCall_preserves_wellFormed wellFormed) failedLocal
  have identity : checked.source.function.id = checked.source.source.id := by
    simpa [Program.function?] using List.find?_some checked.source.found
  have found : program.core.function? checked.source.function.id = some checked.source.function := by
    rw [identity]; exact checked.source.found
  have bound : bindParameters checked.source.function.parameters (syntaxArgumentValues environment) = some bindings := by
    rw [checked.signature.1]
    rfl
  exact ⟨restoreLocals before after, evaluatesCallReturned argumentsResult found bound checked.body (run _),
    CellEffect.closeCall before bindings wellFormed effect⟩

end Lanius.Extraction.Frontend
