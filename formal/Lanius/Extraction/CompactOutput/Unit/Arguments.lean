import Lanius.Extraction.CompactOutput.Unit.Lexical
import Lanius.Extraction.CompactOutput.Unit.Collection
import Lanius.Extraction.CompactOutput.Unit.Call
import Lanius.Extraction.SemanticTokens.Frontend

namespace Lanius.Extraction.CompactOutput.Unit

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.Compiler.Lexer Lanius.Compiler.Parser
open Lanius.Extraction.Frontend Lanius.Extraction.SemanticTokens
open Lanius.Extraction.CanonicalTokens.CanonicalizeModel Lanius.FunctionalView.Core

/-- Caller-visible values of the existing 19-argument unit emitter. Logical
counts are separate from physical slice capacities. -/
structure Emission where
  data : SyntaxData
  path : List Byte
  pathCell : CellId
  pathCapacity : Nat
  semanticCell : CellId
  semanticOriginal : List Int
  outputCell : CellId
  original : List Int
  capacity : Nat
  position : Int
  count : Nat
  nodes : Nat
  words : Nat

def Emission.values (emission : Emission) : List Value :=
  [.slice i32 emission.pathCell [] 0 emission.pathCapacity, .signed .i32 emission.path.length,
    .slice i32 emission.data.sourceCell [] 0 emission.data.request.source.length, .signed .i32 emission.data.request.source.length,
    .slice i32 emission.data.rawCell [] 0 emission.data.records.length, .signed .i32 emission.data.records.length,
    .signed .i32 emission.data.raw.length,
    .slice i32 emission.data.canonicalCell [] 0 emission.data.canonical.length, .signed .i32 emission.data.canonical.length,
    .signed .i32 emission.count,
    .slice i32 emission.semanticCell [] 0 emission.semanticOriginal.length, .signed .i32 emission.semanticOriginal.length,
    .slice i32 emission.data.recordsCell [] 0 emission.data.treeRecords.length, .signed .i32 emission.data.treeRecords.length,
    .slice i32 emission.data.offsetsCell [] 0 emission.data.treeOffsets.length, .signed .i32 emission.nodes,
    .slice i32 emission.outputCell [] 0 emission.original.length, .signed .i32 emission.capacity, .signed .i32 emission.position]

def Emission.bindings (emission : Emission) : List (VarId × Value) :=
  parameterBindings (fun index : Fin 19 => emission.values.get index)

/-- Storage after collection, indexed by the selected frontend parse and its
collection. These are ordinary buffer facts, not assumed serializer runs. -/
structure Storage (emission : Emission)
    (result : FrontendResult emission.data emission.count emission.nodes emission.words extracted)
    (collection : CollectionRecords emission.data.grammar (artifactTokens emission.data.tokens) result.parse.tree 0 0)
    (state : State) : Prop where
  valid : emission.data.Valid
  kindsFit : emission.data.grammar.grammar.n_kinds ≤ 32768
  path : I32Prefix state emission.pathCell emission.pathCapacity (sourceIntegers emission.path)
  source : I32Prefix state emission.data.sourceCell emission.data.request.source.length (sourceIntegers emission.data.request.source)
  raw : I32Prefix state emission.data.rawCell emission.data.records.length (encodeTokens emission.data.raw)
  canonical : I32Prefix state emission.data.canonicalCell emission.data.canonical.length (encodeTokens emission.data.tokens)
  records : I32Prefix state emission.data.recordsCell emission.data.treeRecords.length (ParserTreeLayout.treeFrom 0 0 result.parse.tree).words
  offsets : I32Prefix state emission.data.offsetsCell emission.data.treeOffsets.length
    ((ParserTreeLayout.treeFrom 0 0 result.parse.tree).offsets.map Int.ofNat)
  semantic : state.cellEntry? emission.semanticCell = some {
    id := emission.semanticCell, value := some (.array (signedI32Values
      (collection.assignments.flatMap Assignment.words ++ emission.semanticOriginal.drop (emission.count * 2)))) }
  output : state.cellEntry? emission.outputCell = some {
    id := emission.outputCell, value := some (.array (signedI32Values emission.original)) }
  pathFit : emission.path.length ≤ 2147483647
  semanticFit : emission.semanticOriginal.length ≤ 2147483647
  semanticRoom : emission.count * 2 ≤ emission.semanticOriginal.length
  capacityFit : emission.capacity ≤ 2147483647
  room : emission.capacity ≤ emission.original.length
  separate : ∀ cell ∈ [emission.pathCell, emission.data.sourceCell, emission.data.rawCell,
    emission.data.canonicalCell, emission.semanticCell, emission.data.recordsCell, emission.data.offsetsCell],
    emission.outputCell ≠ cell

def Storage.inputs (storage : Storage emission result collection before)
    (wellFormed : StateWellFormed before) :
    Inputs (enterCall before emission.bindings) emission.outputCell emission.original.length := by
  have locals (index : Fin 19) : (enterCall before emission.bindings).local? index.val = some (emission.values.get index) :=
    enterCall_parameterBindings_matches wellFormed index
  have preserve {cell : CellId} {value : Option Value}
      (found : before.cellEntry? cell = some { id := cell, value := value }) :
      (enterCall before emission.bindings).cellEntry? cell = some { id := cell, value := value } :=
    ((enterCall_effect before emission.bindings).oldCells cell
      (StateWellFormed.cell_lt_next_of_entry wellFormed found) (by simp [CellSet.empty])).trans found
  have prefixPreserved {cell : CellId} {capacity : Nat} {values : List Int}
      (input : I32Prefix before cell capacity values) : I32Prefix (enterCall before emission.bindings) cell capacity values := by
    obtain ⟨unused, size, backing⟩ := input
    exact ⟨unused, size, preserve backing⟩
  have countEqual : emission.count = emission.data.tokens.length := by
    simpa only [artifactTokens, List.length_map] using result.countEq
  let grammarData : Collect.GrammarData := ⟨emission.data.grammarLayout, emission.data.grammar,
    emission.data.grammarWords, storage.valid.grammarEncoded, storage.valid.grammarWellFormed,
    storage.valid.wordsFit, storage.kindsFit⟩
  exact {
    path := byteInput (prefixPreserved storage.path) (locals ⟨0, by decide⟩) (locals ⟨1, by decide⟩)
      (storage.separate _ (by simp)) storage.pathFit
    source := byteInput (prefixPreserved storage.source) (locals ⟨2, by decide⟩) (locals ⟨3, by decide⟩)
      (storage.separate _ (by simp)) (by have := emission.data.request.sourceFitsI32; omega)
    raw := by
      let input := rawInput emission.data storage.valid
        (prefixPreserved storage.raw) (locals ⟨4, by decide⟩) (locals ⟨5, by decide⟩) (locals ⟨6, by decide⟩)
        (storage.separate _ (by simp))
      exact { input with fields := by simpa only [byteInput, List.length_map] using input.fields }
    canonical := by
      have countRead : (enterCall before emission.bindings).local? 9 = some (.signed .i32 emission.count) := locals ⟨9, by decide⟩
      let input := canonicalInput emission.data storage.valid
        (prefixPreserved storage.canonical) (locals ⟨7, by decide⟩) (locals ⟨8, by decide⟩)
        (by rw [countEqual] at countRead; exact countRead)
        (storage.separate _ (by simp))
      exact { input with fields := by simpa only [byteInput, List.length_map] using input.fields }
    semantic := by
      let input := collection.semanticInput storage.kindsFit
        (by simpa only [← result.countEq] using storage.semanticRoom) storage.semanticFit
        (by simpa only [← result.countEq] using preserve storage.semantic)
        (locals ⟨10, by decide⟩) (locals ⟨11, by decide⟩) (storage.separate _ (by simp))
      exact { input with countEqual := by simpa only [canonicalInput, artifactTokens, List.length_map] using input.countEqual }
    nodes := by
      have nodesRead : (enterCall before emission.bindings).local? 15 = some (.signed .i32 emission.nodes) := locals ⟨15, by decide⟩
      let input := collection.nodeInput grammarData result.parse result.tokensFit
        (prefixPreserved storage.records) (prefixPreserved storage.offsets)
        (locals ⟨12, by decide⟩) (locals ⟨13, by decide⟩) (locals ⟨14, by decide⟩)
        (by rw [result.nodesEq] at nodesRead; exact nodesRead)
        (storage.separate _ (by simp)) (storage.separate _ (by simp)) storage.valid.treeRecordsFit storage.valid.treeOffsetsFit
      exact { input with tokenBound := by simpa only [canonicalInput, artifactTokens, List.length_map] using input.tokenBound }
    capacity := emission.capacity
    outputRead := locals ⟨16, by decide⟩
    capacityRead := locals ⟨17, by decide⟩
    room := storage.room
    capacityFit := storage.capacityFit
  }

theorem Storage.inputs_nonempty (storage : Storage emission result collection before)
    (wellFormed : StateWellFormed before) : 0 < (storage.inputs wellFormed).nodes.records.length := by
  change 0 < collection.records.length
  exact collection.nonempty result.parse

def Emission.encoding (emission : Emission) (assignments : List Assignment) (records : List RecordVisit) : List Nat :=
  hexDigits emission.path.length 8 ++ Bytes.encoding (emission.path.map Fin.val) ++
  hexDigits emission.data.request.source.length 8 ++ Bytes.encoding (emission.data.request.source.map Fin.val) ++
  hexDigits emission.data.raw.length 8 ++ Tokens.encodeAll emission.data.raw ++
  hexDigits emission.data.tokens.length 8 ++ Tokens.encodeAll emission.data.tokens ++
  Assignments.encodeAll assignments ++ hexDigits records.length 8 ++ Nodes.encodeAll records

theorem Storage.inputs_encoding (storage : Storage emission result collection before)
    (wellFormed : StateWellFormed before) :
    (storage.inputs wellFormed).encoding = emission.encoding collection.assignments collection.records := by
  simp only [Inputs.encoding, Inputs.tailEncoding, Storage.inputs, byteInput, List.length_map,
    rawInput, canonicalInput, CollectionRecords.semanticInput, CollectionRecords.nodeInput, Emission.encoding, List.append_assoc]

/-- Establish the complete emitter storage contract using the frontend
postcondition and the collector's actual output-only effect. -/
theorem Storage.of_collection {emission : Emission}
    {result : FrontendResult emission.data emission.count emission.nodes emission.words extracted}
    {collection : CollectionRecords emission.data.grammar (artifactTokens emission.data.tokens) result.parse.tree 0 0}
    (valid : emission.data.Valid) (kindsFit : emission.data.grammar.grammar.n_kinds ≤ 32768)
    (post : emission.data.Post stage detail emission.count emission.nodes emission.words position frontBefore extracted)
    (raw : emission.data.RawOutput extracted) (success : stage = 0)
    (wellFormed : StateWellFormed extracted)
    (effect : CellEffect (CellSet.singleton emission.semanticCell) extracted collected)
    (collectorSeparate : ∀ cell ∈ [emission.data.sourceCell, emission.data.rawCell, emission.data.canonicalCell,
      emission.data.recordsCell, emission.data.offsetsCell], cell ≠ emission.semanticCell)
    (semantic : collected.cellEntry? emission.semanticCell = some {
      id := emission.semanticCell, value := some (.array (signedI32Values
        (collection.assignments.flatMap Assignment.words ++ emission.semanticOriginal.drop (emission.count * 2)))) })
    (path : I32Prefix collected emission.pathCell emission.pathCapacity (sourceIntegers emission.path))
    (output : collected.cellEntry? emission.outputCell = some {
      id := emission.outputCell, value := some (.array (signedI32Values emission.original)) })
    (pathFit : emission.path.length ≤ 2147483647)
    (semanticFit : emission.semanticOriginal.length ≤ 2147483647)
    (semanticRoom : emission.count * 2 ≤ emission.semanticOriginal.length)
    (capacityFit : emission.capacity ≤ 2147483647) (room : emission.capacity ≤ emission.original.length)
    (separate : ∀ cell ∈ [emission.pathCell, emission.data.sourceCell, emission.data.rawCell,
      emission.data.canonicalCell, emission.semanticCell, emission.data.recordsCell, emission.data.offsetsCell],
      emission.outputCell ≠ cell) : Storage emission result collection collected := by
  obtain ⟨source, raw, canonical⟩ := lexical_storage_after_collection emission.data valid post raw success wellFormed effect
    (collectorSeparate _ (by simp)) (collectorSeparate _ (by simp)) (collectorSeparate _ (by simp))
  exact ⟨valid, kindsFit, path, source, raw, canonical,
    result.records.preserved wellFormed effect (collectorSeparate _ (by simp)),
    result.offsets.preserved wellFormed effect (collectorSeparate _ (by simp)),
    semantic, output, pathFit, semanticFit, semanticRoom, capacityFit, room, separate⟩

/-- Public emitter call from caller storage and the real 19 argument values.
The callee input contract, parameter bindings, and nonempty-node condition are
all derived, not additional caller assumptions. -/
theorem Storage.write (storage : Storage emission result collection before)
    (word : Word.Checked program byte digit)
    (bytes : Bytes.Checked program byte digit hex)
    (tokens : Tokens.Checked program byte digit word)
    (semantic : Assignments.Checked program byte digit word)
    (nodes : Nodes.Checked program byte digit word tokenTag stateTag)
    (checked : Checked program ⟨word.source.function.id, bytes.source.function.id,
      tokens.source.function.id, semantic.source.function.id, nodes.source.function.id⟩)
    (tokenConstant : ParserTreeSource.constantValue program.core tokenTag 1)
    (stateConstant : ParserTreeSource.constantValue program.core stateTag 2)
    (wellFormed : StateWellFormed before)
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments emission.values before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments)
        (.signed .i32 (appendAll emission.capacity (emission.encoding collection.assignments collection.records)
          emission.position emission.original).position) after ∧
      after.cellEntry? emission.outputCell = some {
        id := emission.outputCell, value := some (.array (signedI32Values
          (appendAll emission.capacity (emission.encoding collection.assignments collection.records)
            emission.position emission.original).contents)) } ∧
      CellEffect (CellSet.singleton emission.outputCell) before after := by
  have positionRead : (enterCall before emission.bindings).local? 18 = some (.signed .i32 emission.position) :=
    enterCall_parameterBindings_matches wellFormed ⟨18, by decide⟩
  have called := Checked.write word bytes tokens semantic nodes checked tokenConstant stateConstant wellFormed
    argumentsResult (bindings := emission.bindings) rfl (storage.inputs wellFormed) emission.position positionRead
    (storage.inputs_nonempty wellFormed) storage.output
  have capacityEqual : (storage.inputs wellFormed).capacity = emission.capacity := rfl
  simpa only [storage.inputs_encoding wellFormed, capacityEqual] using called

end Lanius.Extraction.CompactOutput.Unit
