import Lanius.Extraction.CompactOutput.Unit.Inputs
import Lanius.Extraction.Frontend.Call
import Lanius.Extraction.RawLexer.LexInto.Spans

namespace Lanius.Extraction.CompactOutput.Unit

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler Lanius.Compiler.Lexer Lanius.Extraction.Frontend

theorem kind_fits (kind : TokenKind) : kind.gpuCode ≤ 2147483647 := by
  cases kind <;> decide

theorem canonical_filter_spans (derivation : Canonicalizes source raw canonical)
    (spans : ∀ token ∈ raw, token.start ≤ token.finish ∧ token.finish ≤ source.length) :
    ∀ token ∈ canonical, token.start ≤ token.finish ∧ token.finish ≤ source.length := by
  induction derivation with
  | empty => simp
  | dropsTrivia trivia tail ih =>
    exact ih (fun token member => spans token (List.mem_cons_of_mem _ member))
  | keepsToken kept tail ih =>
    intro token member
    rcases List.mem_cons.mp member with rfl | later
    · have head := spans _ List.mem_cons_self
      exact head
    · exact ih (fun token member => spans token (List.mem_cons_of_mem _ member)) token later

theorem inclusive_range_spans (derivation : InclusiveRangeRetags input output)
    (spans : ∀ token ∈ input, token.start ≤ token.finish ∧ token.finish ≤ limit) :
    ∀ token ∈ output, token.start ≤ token.finish ∧ token.finish ≤ limit := by
  induction derivation with
  | empty => simp
  | singleton token => exact spans
  | inclusive pair tail ih =>
    intro token member
    rcases List.mem_cons.mp member with rfl | later
    · have head := spans _ List.mem_cons_self
      exact head
    · exact ih (fun token member => spans token (List.mem_cons_of_mem _ member)) token later
  | ordinary pair tail ih =>
    intro token member
    rcases List.mem_cons.mp member with rfl | later
    · exact spans _ List.mem_cons_self
    · exact ih (fun token member => spans token (List.mem_cons_of_mem _ member)) token later

theorem raw_fields (data : SyntaxData) :
    ∀ token ∈ data.raw, token.kind.gpuCode ≤ 2147483647 ∧
      token.start ≤ token.finish ∧ token.finish ≤ data.request.source.length := by
  intro token member
  exact ⟨kind_fits token.kind,
    RawLexer.LexInto.Model.emittedTokens_validSpans data.request.source data.request.capacity token member⟩

/-- Both canonicalization passes only change kinds or remove tokens. They
therefore retain the raw lexer's byte-span bounds, including range retagging. -/
theorem canonical_fields (data : SyntaxData) :
    ∀ token ∈ data.tokens, token.kind.gpuCode ≤ 2147483647 ∧
      token.start ≤ token.finish ∧ token.finish ≤ data.request.source.length := by
  have filtered := canonical_filter_spans (filterRetagTokens_spec data.request.source data.raw)
    (fun token member => (raw_fields data token member).2)
  have ranged := inclusive_range_spans (retagInclusiveRanges_spec (filterRetagTokens data.request.source data.raw)) filtered
  intro token member
  exact ⟨kind_fits token.kind, ranged token member⟩

/-- Source/path bytes are bounded by their representation; no separately
trusted byte-range claim is needed at the serializer boundary. -/
def byteInput {values : List Byte} (input : I32Prefix state cell capacity (values.map (fun value => (value.val : Int))))
    (inputRead : state.local? inputId = some (.slice i32 cell [] 0 capacity))
    (lengthRead : state.local? lengthId = some (.signed .i32 values.length))
    (distinct : outputCell ≠ cell) (lengthFit : values.length ≤ 2147483647) :
    ByteInput state inputId lengthId outputCell where
  values := values.map Fin.val
  cell := cell
  capacity := capacity
  input := by simpa only [List.map_map, Function.comp_def, Int.ofNat_eq_natCast] using input
  inputRead := inputRead
  lengthRead := by simpa only [List.length_map] using lengthRead
  distinct := distinct
  lengthFit := by simpa only [List.length_map] using lengthFit
  byteBound := by
    intro value member
    obtain ⟨byte, _, rfl⟩ := List.mem_map.mp member
    exact byte.isLt

open Lanius.Extraction.CanonicalTokens CanonicalizeModel Compaction
open Lanius.FunctionalView.Core

/-- Recover the existing source, raw, and canonical arrays on frontend
success. Their unused suffixes stay storage, not additional logical tokens. -/
theorem lexical_storage (data : SyntaxData) (valid : data.Valid)
    (post : data.Post stage detail count nodes words position before after)
    (raw : data.RawOutput after) (success : stage = 0) :
    I32Prefix after data.sourceCell data.request.source.length (sourceIntegers data.request.source) ∧
    I32Prefix after data.rawCell data.records.length (encodeTokens data.raw) ∧
    I32Prefix after data.canonicalCell data.canonical.length (encodeTokens data.tokens) := by
  have sourceBacking := raw _ _ ReadOnly.World.pair_finds_first
  have rawBacking := raw _ _ (ReadOnly.World.pair_finds_second valid.sourceRaw.symm)
  have rawRoom : 3 * data.raw.length ≤ data.records.length := by
    have bound := RawLexer.LexInto.Model.emittedTokens_length_le_capacity data.request.source data.request.capacity
    change data.raw.length ≤ data.request.capacity at bound
    rw [valid.wordCapacity] at bound
    omega
  refine ⟨⟨[], ?_, ?_⟩, ⟨data.records.drop (3 * data.raw.length), ?_, rawBacking⟩, ?_⟩
  · simp only [sourceIntegers, List.length_map, List.length_nil, Nat.add_zero]
  · simpa only [List.append_nil] using sourceBacking
  · rw [encoded_length, List.length_drop]
    omega
  rcases post with early | ⟨completed, capacity, countEq, canonical, rest⟩
  · rcases early.1.stage with failed | failed <;> omega
  · have tokenRoom : data.tokens.length ≤ data.raw.length := by
      simpa only [SyntaxData.tokens, canonicalizeTokens, Range.retag_length] using
        filtered_length data.request.source data.raw
    refine ⟨(encodeTokens data.raw ++ data.canonical.drop (3 * data.raw.length)).drop
      (encodeTokens data.tokens).length, ?_, canonical⟩
    rw [List.length_drop, List.length_append, encoded_length, encoded_length, List.length_drop]
    omega

def rawInput (data : SyntaxData) (valid : data.Valid)
    (input : I32Prefix state data.rawCell data.records.length (encodeTokens data.raw))
    (inputRead : state.local? 4 = some (.slice i32 data.rawCell [] 0 data.records.length))
    (lengthRead : state.local? 5 = some (.signed .i32 data.records.length))
    (countRead : state.local? 6 = some (.signed .i32 data.raw.length))
    (distinct : outputCell ≠ data.rawCell) :
    TokenInput state 4 5 6 data.request.source.length outputCell where
  tokens := data.raw
  cell := data.rawCell
  capacity := data.records.length
  inputLength := data.records.length
  input := input
  inputRead := inputRead
  lengthRead := lengthRead
  countRead := countRead
  distinct := distinct
  inputRoom := by simpa only [encoded_length] using input.length_le
  lengthFit := valid.recordsFit
  fields := raw_fields data

def canonicalInput (data : SyntaxData) (valid : data.Valid)
    (input : I32Prefix state data.canonicalCell data.canonical.length (encodeTokens data.tokens))
    (inputRead : state.local? 7 = some (.slice i32 data.canonicalCell [] 0 data.canonical.length))
    (lengthRead : state.local? 8 = some (.signed .i32 data.canonical.length))
    (countRead : state.local? 9 = some (.signed .i32 data.tokens.length))
    (distinct : outputCell ≠ data.canonicalCell) :
    TokenInput state 7 8 9 data.request.source.length outputCell where
  tokens := data.tokens
  cell := data.canonicalCell
  capacity := data.canonical.length
  inputLength := data.canonical.length
  input := input
  inputRead := inputRead
  lengthRead := lengthRead
  countRead := countRead
  distinct := distinct
  inputRoom := by simpa only [encoded_length] using input.length_le
  lengthFit := valid.canonicalFit
  fields := canonical_fields data

/-- The collector's output-only effect retains all three lexical inputs for
emission. This uses the separate collector effect kept by the pipeline. -/
theorem lexical_storage_after_collection (data : SyntaxData) (valid : data.Valid)
    (post : data.Post stage detail count nodes words position before extracted)
    (raw : data.RawOutput extracted) (success : stage = 0)
    (wellFormed : StateWellFormed extracted)
    (effect : CellEffect (CellSet.singleton semanticCell) extracted collected)
    (sourceSeparate : data.sourceCell ≠ semanticCell)
    (rawSeparate : data.rawCell ≠ semanticCell)
    (canonicalSeparate : data.canonicalCell ≠ semanticCell) :
    I32Prefix collected data.sourceCell data.request.source.length (sourceIntegers data.request.source) ∧
    I32Prefix collected data.rawCell data.records.length (encodeTokens data.raw) ∧
    I32Prefix collected data.canonicalCell data.canonical.length (encodeTokens data.tokens) := by
  obtain ⟨source, raw, canonical⟩ := lexical_storage data valid post raw success
  exact ⟨source.preserved wellFormed effect sourceSeparate,
    raw.preserved wellFormed effect rawSeparate,
    canonical.preserved wellFormed effect canonicalSeparate⟩

end Lanius.Extraction.CompactOutput.Unit
