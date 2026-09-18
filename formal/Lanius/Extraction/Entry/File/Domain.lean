import Lanius.Extraction.Entry.File.Resources
import Lanius.Extraction.Entry.Domain.Source
import Lanius.Extraction.CompactDecode.Acceptance.Tokens

namespace Lanius.Extraction.Entry
open Lanius.Compiler Lanius.Compiler.Lexer Lanius.Compiler.Parser
open Lanius.Extraction.Frontend Lanius.Extraction.SemanticTokens
open Lanius.Extraction.ParserTreeLayout Lanius.Extraction.CompactOutput

/-- Connect the exact externally loaded bytes and the source-checked call
capacities to the lexical/storage domain. Works with reused dirty buffers. -/
theorem File.Resources.token_storage
    (resources : File.Resources pipeline syntaxStage collectStage emitStage argument before)
    (domain : TokenDomain sources)
    (member : ({path := resources.input.path, bytes := resources.input.file.bytes.map UInt8.toNat} : SourceFile) ∈ sources) :
    ∃ tokens, TokenStorage resources.data.request.source tokens
      resources.data.records.length resources.data.canonical.length resources.data.kinds.length := by
  obtain ⟨source, tokens, decoded, storage⟩ := domain _ member
  have bytesDecoded : decodeBytes (resources.input.file.bytes.map UInt8.toNat) =
      some (resources.input.file.bytes.map UInt8.toFin) := by
    simpa only [List.map_map, Function.comp_def, UInt8.toFin_val] using
      decodeBytes_values (resources.input.file.bytes.map UInt8.toFin)
  have same := Option.some.inj (decoded.symm.trans bytesDecoded)
  subst source
  refine ⟨tokens, ?_⟩
  simpa only [resources.buffers.sourceBytes, resources.capacities.raw,
    resources.capacities.canonical, resources.capacities.kinds] using storage

theorem File.Resources.no_token_failure
    (resources : File.Resources pipeline syntaxStage collectStage emitStage argument before)
    (domain : TokenDomain sources)
    (member : ({path := resources.input.path, bytes := resources.input.file.bytes.map UInt8.toNat} : SourceFile) ∈ sources)
    (post : resources.data.Post stage detail count nodes words parserPosition ready after) :
    stage ≠ 2 ∧ stage ≠ 3 := by
  obtain ⟨tokens, storage⟩ := resources.token_storage domain member
  have noFailure := post.no_token_failure resources.valid storage
  exact ⟨noFailure.1, noFailure.2.1⟩

theorem File.Resources.recognizes
    (resources : File.Resources pipeline syntaxStage collectStage emitStage argument before)
    (storage : TokenDomain sources) (syntaxValid : SyntaxDomain sources)
    (member : ({path := resources.input.path, bytes := resources.input.file.bytes.map UInt8.toNat} : SourceFile) ∈ sources) :
    RecognizesInput resources.data.grammar (resources.data.tokens.map (fun token => token.kind.gpuCode)) := by
  obtain ⟨tokens, stored⟩ := resources.token_storage storage member
  obtain ⟨source, parsedTokens, decoded, lexical, parsed⟩ := syntaxValid _ member
  have bytesDecoded : decodeBytes (resources.input.file.bytes.map UInt8.toNat) =
      some (resources.input.file.bytes.map UInt8.toFin) := by
    simpa only [List.map_map, Function.comp_def, UInt8.toFin_val] using
      decodeBytes_values (resources.input.file.bytes.map UInt8.toFin)
  have same := Option.some.inj (decoded.symm.trans bytesDecoded)
  subst source
  have sourceLexical : lexCanonical resources.data.request.source = .success parsedTokens := by
    simpa only [resources.buffers.sourceBytes] using lexical
  have tokensEq := RawLexResult.success.inj (stored.lexical.symm.trans sourceLexical)
  subst parsedTokens
  obtain ⟨raw, completed, canonicalized, _⟩ := stored.realizes resources.valid.wordCapacity
  have actual : resources.data.tokens = tokens := by
    simp only [SyntaxData.tokens, SyntaxData.raw, completed, RawLexer.LexInto.Model.emittedTokens, canonicalized]
  rw [actual]
  exact parsed resources.data.grammar resources.grammarIdentity

/-- The source-linked frontend on certified syntax has only these remaining
outcomes. In particular, its error branch cannot report invalid syntax, and
neither the raw lexer nor the canonical/kind buffers can fail. -/
theorem File.Resources.frontend_success_or_resource
    (resources : File.Resources pipeline syntaxStage collectStage emitStage argument before)
    (storage : TokenDomain sources) (syntaxValid : SyntaxDomain sources)
    (member : ({path := resources.input.path, bytes := resources.input.file.bytes.map UInt8.toNat} : SourceFile) ∈ sources)
    (post : resources.data.Post stage detail count nodes words parserPosition ready after) :
    stage = 0 ∨ (stage = 4 ∧ detail = 2) ∨ stage = 5 := by
  have noToken := resources.no_token_failure storage member post
  have noReject : stage = 4 → detail ≠ 1 := by
    intro parserStage rejected
    exact bodyPost.parser_rejected_invalid post parserStage rejected (resources.recognizes storage syntaxValid member)
  rcases post with early | ⟨_, _, _, _, full | ⟨_, _, _, _, _, _, parsed, _⟩⟩
  · rcases early.1.stage with failed | failed <;> omega
  · have failed := full.2.1
    omega
  · rcases parsed with ⟨parserStage, status, _⟩ | ⟨root, treeStage, _⟩
    · exact .inr (.inl ⟨parserStage, by have := noReject parserStage; omega⟩)
    · unfold extractionTreeStage at treeStage
      split at treeStage <;> omega

theorem File.Resources.no_parser_capacity
    (resources : File.Resources pipeline syntaxStage collectStage emitStage argument before)
    (storage : TokenDomain sources) (domain : ParserDomain sources)
    (member : ({path := resources.input.path, bytes := resources.input.file.bytes.map UInt8.toNat} : SourceFile) ∈ sources)
    (post : resources.data.Post stage detail count nodes words parserPosition ready after) :
    ¬ (stage = 4 ∧ detail = 2) := by
  obtain ⟨tokens, stored⟩ := resources.token_storage storage member
  obtain ⟨source, parsedTokens, items, decoded, lexical, fits, closed⟩ := domain _ member
  have bytesDecoded : decodeBytes (resources.input.file.bytes.map UInt8.toNat) =
      some (resources.input.file.bytes.map UInt8.toFin) := by
    simpa only [List.map_map, Function.comp_def, UInt8.toFin_val] using
      decodeBytes_values (resources.input.file.bytes.map UInt8.toFin)
  have same := Option.some.inj (decoded.symm.trans bytesDecoded)
  subst source
  have sourceLexical : lexCanonical resources.data.request.source = .success parsedTokens := by
    simpa only [resources.buffers.sourceBytes] using lexical
  have tokensEq := RawLexResult.success.inj (stored.lexical.symm.trans sourceLexical)
  subst parsedTokens
  obtain ⟨raw, completed, canonicalized, _⟩ := stored.realizes resources.valid.wordCapacity
  have actual : resources.data.tokens = tokens := by
    simp only [SyntaxData.tokens, SyntaxData.raw, completed, RawLexer.LexInto.Model.emittedTokens, canonicalized]
  apply bodyPost.no_parser_capacity_of_closed_bound post
    (upper := Envelope.workspace items)
  · change ChartClosed resources.data.grammar (resources.data.tokens.map _) _
    rw [actual]
    exact closed resources.data.grammar resources.grammarIdentity
  · exact Envelope.chartSound items
  · simp only [Envelope.states_length, WorkspaceLayout.capacity]
    rw [← resources.valid.workspaceLength, resources.capacities.workspace,
      resources.valid.workspaceTokenCount, actual]
    exact fits

theorem File.Resources.frontend_success_or_tree_resource
    (resources : File.Resources pipeline syntaxStage collectStage emitStage argument before)
    (storage : TokenDomain sources) (syntaxValid : SyntaxDomain sources) (parser : ParserDomain sources)
    (member : ({path := resources.input.path, bytes := resources.input.file.bytes.map UInt8.toNat} : SourceFile) ∈ sources)
    (post : resources.data.Post stage detail count nodes words parserPosition ready after) :
    stage = 0 ∨ stage = 5 := by
  rcases resources.frontend_success_or_resource storage syntaxValid member post with success | full | tree
  · exact .inl success
  · exact False.elim (resources.no_parser_capacity storage parser member post full)
  · exact .inr tree

theorem File.Resources.no_tree_failure
    (resources : File.Resources pipeline syntaxStage collectStage emitStage argument before)
    (storage : TokenDomain sources) (domain : TreeDomain sources)
    (member : ({path := resources.input.path, bytes := resources.input.file.bytes.map UInt8.toNat} : SourceFile) ∈ sources)
    (post : resources.data.Post stage detail count nodes words parserPosition ready after) : stage ≠ 5 := by
  obtain ⟨tokens, stored⟩ := resources.token_storage storage member
  obtain ⟨source, parsedTokens, decoded, lexical, fits⟩ := domain _ member
  have bytesDecoded : decodeBytes (resources.input.file.bytes.map UInt8.toNat) =
      some (resources.input.file.bytes.map UInt8.toFin) := by
    simpa only [List.map_map, Function.comp_def, UInt8.toFin_val] using
      decodeBytes_values (resources.input.file.bytes.map UInt8.toFin)
  have same := Option.some.inj (decoded.symm.trans bytesDecoded)
  subst source
  have sourceLexical : lexCanonical resources.data.request.source = .success parsedTokens := by
    simpa only [resources.buffers.sourceBytes] using lexical
  have tokensEq := RawLexResult.success.inj (stored.lexical.symm.trans sourceLexical)
  subst parsedTokens
  obtain ⟨raw, completed, canonicalized, _⟩ := stored.realizes resources.valid.wordCapacity
  have actual : resources.data.tokens = tokens := by
    simp only [SyntaxData.tokens, SyntaxData.raw, completed, RawLexer.LexInto.Model.emittedTokens, canonicalized]
  apply bodyPost.no_tree_failure post
  change ∀ parse : MaterializedParse resources.data.grammar (resources.data.tokens.map _),
    ParserTreeBounds.Fits parse.tree resources.data.treeRecords.length resources.data.treeOffsets.length resources.data.depth
  rw [actual]
  simpa only [resources.capacities.records, resources.capacities.offsets, resources.capacities.depth] using
    fits resources.data.grammar resources.grammarIdentity

/-- On the source-only lexical, syntax, parser, and tree domains, the actual
frontend can only return success. Semantic collection and module output are
later stages and are deliberately not included in this conclusion. -/
theorem File.Resources.frontend_success
    (resources : File.Resources pipeline syntaxStage collectStage emitStage argument before)
    (storage : TokenDomain sources) (syntaxValid : SyntaxDomain sources)
    (parser : ParserDomain sources) (tree : TreeDomain sources)
    (member : ({path := resources.input.path, bytes := resources.input.file.bytes.map UInt8.toNat} : SourceFile) ∈ sources)
    (post : resources.data.Post stage detail count nodes words parserPosition ready after) : stage = 0 := by
  rcases resources.frontend_success_or_tree_resource storage syntaxValid parser member post with success | failed
  · exact success
  · exact False.elim (resources.no_tree_failure storage tree member post failed)

/-- The bound applies to the actual frontend's selected tree and serializer,
including raw-token records and semantic assignments. Successful serialization
is a conclusion of later capacity reasoning, never a premise here. -/
theorem File.Resources.encoding_bound
    (resources : File.Resources pipeline syntaxStage collectStage emitStage argument before)
    (storage : TokenDomain sources)
    (member : ({path := resources.input.path, bytes := resources.input.file.bytes.map UInt8.toNat} : SourceFile) ∈ sources)
    (bounded : SourceOutputBound {path := resources.input.path, bytes := resources.input.file.bytes.map UInt8.toNat} bound)
    (observed : File.FrontendReturn resources.input resources.data)
    (result : FrontendResult resources.data observed.count observed.nodes observed.words ready)
    (collection : CollectionRecords resources.data.grammar (artifactTokens resources.data.tokens) result.parse.tree 0 0) :
    ((File.Emit.emission observed resources.semantic resources.output resources.position).encoding
      collection.assignments collection.records).length ≤ bound := by
  obtain ⟨tokens, stored⟩ := resources.token_storage storage member
  obtain ⟨raw, lexed, canonical, rawBound⟩ := lexCanonical_raw_budget stored.lexical
  have rawFits : raw.length ≤ resources.data.request.capacity := by
    have capacity := resources.valid.wordCapacity
    have fits := stored.rawFits
    omega
  have completed : resources.data.request.outcome = .completed raw :=
    RawLexer.LexInto.Model.successful_unbounded_stream_preserved lexed rawFits
  have actualRaw : resources.data.raw = raw := by
    simp only [SyntaxData.raw, completed, RawLexer.LexInto.Model.emittedTokens]
  have actualTokens : resources.data.tokens = tokens := by
    simp only [SyntaxData.tokens, actualRaw, canonical]
  have bytesDecoded : decodeBytes (resources.input.file.bytes.map UInt8.toNat) =
      some resources.data.request.source := by
    rw [resources.buffers.sourceBytes]
    simpa only [List.map_map, Function.comp_def, UInt8.toFin_val] using
      decodeBytes_values (resources.input.file.bytes.map UInt8.toFin)
  have treeBound := bounded resources.data.request.source resources.data.raw resources.data.tokens
    bytesDecoded (by simpa only [actualRaw] using lexed) (by simpa only [actualTokens] using stored.lexical)
    resources.data.grammar resources.grammarIdentity
    { tree := result.parse.tree, recognizes := by simpa only [artifactTokens_kinds] using result.parse.recognizes }
  rw [Size.emission_encoding_size
    (emission := File.Emit.emission observed resources.semantic resources.output resources.position) result collection]
  simpa only [File.Emit.emission, List.length_map, Lanius.World.utf8Bytes,
    Array.length_toList, ByteArray.size_data, ← result.nodesEq, ← result.wordsEq] using treeBound

theorem File.Resources.supported_frontend
    (resources : File.Resources pipeline syntaxStage collectStage emitStage argument before)
    (supported : SourceDomain {path := resources.input.path, bytes := resources.input.file.bytes.map UInt8.toNat} bound)
    (observed : File.FrontendReturn resources.input resources.data) : observed.status = 0 := by
  obtain ⟨tokens, syntaxValid, parser, tree⟩ := supported.singleton
  exact resources.frontend_success tokens syntaxValid parser tree (by simp) observed.result

theorem File.Resources.supported_output
    (resources : File.Resources pipeline syntaxStage collectStage emitStage argument before)
    (supported : SourceDomain {path := resources.input.path, bytes := resources.input.file.bytes.map UInt8.toNat} bound)
    (observed : File.FrontendReturn resources.input resources.data)
    (result : FrontendResult resources.data observed.count observed.nodes observed.words ready)
    (collection : CollectionRecords resources.data.grammar (artifactTokens resources.data.tokens) result.parse.tree 0 0) :
    ((File.Emit.emission observed resources.semantic resources.output resources.position).encoding
      collection.assignments collection.records).length ≤ bound :=
  resources.encoding_bound supported.singleton.1 (by simp) supported.output observed result collection

end Lanius.Extraction.Entry
