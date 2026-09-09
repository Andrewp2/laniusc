import Lanius.Extraction.CompactDecode.Artifact

namespace Lanius.Extraction.CompactDecode

open CompactOutput SemanticTokens Lanius.Compiler.Lexer

/-- Data in one wire unit, using the existing field encodings. This is a
proof view, not a second runtime serializer. -/
structure UnitData where
  path : String
  source : ByteArray
  raw : List RawToken
  tokens : List RawToken
  assignments : List Assignment
  nodes : List RecordVisit

def UnitData.chunks (data : UnitData) : List (List Nat) :=
  [hexDigits data.path.toUTF8.size 8,
   data.path.toUTF8.toList.flatMap (fun b => hexDigits b.toNat 2),
   hexDigits data.source.size 8,
   data.source.toList.flatMap (fun b => hexDigits b.toNat 2),
   hexDigits data.raw.length 8, data.raw.flatMap Tokens.encoding,
   hexDigits data.tokens.length 8, data.tokens.flatMap Tokens.encoding,
   Assignments.encodeAll data.assignments,
   hexDigits data.nodes.length 8, data.nodes.flatMap Nodes.encodeRecord]

def UnitData.encoding (data : UnitData) : List Nat := data.chunks.flatten

def UnitData.artifact (data : UnitData) : Artifact :=
  { Artifact.empty with
    sources := [{path := data.path, bytes := data.source.toList.map UInt8.toNat}]
    raw_tokens := some (data.raw.map fun t => ⟨t.kind.gpuCode, ⟨0, t.start, t.finish⟩⟩)
    tokens := data.tokens.map fun t => ⟨t.kind.gpuCode, ⟨0, t.start, t.finish⟩⟩
    semantic_token_kinds := data.assignments.map Assignment.code
    parse_nodes := data.nodes.map decodedNode
    parse_root := some (data.nodes.length - 1) }

structure UnitData.Encodable (data : UnitData) : Prop where
  pathFit : data.path.toUTF8.size < 4294967296
  sourceFit : data.source.size < 4294967296
  rawFit : data.raw.length < 4294967296
  tokenFit : data.tokens.length < 4294967296
  nodeFit : data.nodes.length < 4294967296
  rawFields : ∀ t ∈ data.raw, t.kind.gpuCode < 4294967296 ∧ t.start < 4294967296 ∧ t.finish < 4294967296
  tokenFields : ∀ t ∈ data.tokens, t.kind.gpuCode < 4294967296 ∧ t.start < 4294967296 ∧ t.finish < 4294967296
  assignments : ∀ a ∈ data.assignments, a.first < 4294967296 ∧
    (Assignments.secondWord a + 1).toNat < 4294967296
  assignmentCount : data.assignments.length = data.tokens.length
  nodes : ∀ n ∈ data.nodes, NodeEncodable n

theorem tokens_encoding_length (tokens : List RawToken) :
    (tokens.flatMap Tokens.encoding).length = tokens.length * 24 := by
  induction tokens with
  | nil => rfl
  | cons t ts ih =>
    simp only [List.flatMap_cons, List.length_append, Tokens.encoding, hexDigits_length, ih, List.length_cons]
    omega

theorem assignments_encoding_length (assignments : List Assignment) :
    (Assignments.encodeAll assignments).length = assignments.length * 16 := by
  induction assignments with
  | nil => rfl
  | cons a rest ih =>
    change (Assignments.encoding a.first (Assignments.secondWord a) ++ Assignments.encodeAll rest).length = _
    simp only [List.length_append, Assignments.encoding, hexDigits_length, ih, List.length_cons]
    omega

theorem nodes_encoding_min_length (nodes : List RecordVisit) :
    nodes.length * 32 ≤ (nodes.flatMap Nodes.encodeRecord).length := by
  induction nodes with
  | nil => exact Nat.le_refl 0
  | cons n ns ih =>
    simp only [List.flatMap_cons, List.length_append, record_encoding_length, List.length_cons]
    omega

theorem UnitData.decode (data : UnitData) (valid : data.Encodable)
    (encoded : EncodedAt bytes offset data.encoding) :
    readArtifact.run {bytes, offset} = if data.nodes.isEmpty then none else
      some (data.artifact, {bytes, offset := offset + data.encoding.length}) := by
  have e0 : EncodedAt bytes offset data.chunks.flatten := encoded
  have e1 := e0.right
  have e2 := e1.right
  have e3 := e2.right
  have e4 := e3.right
  have e5 := e4.right
  have e6 := e5.right
  have e7 := e6.right
  have e8 := e7.right
  have e9 := e8.right
  have e10 := e9.right
  have p0 := readU32_hex valid.pathFit e0.left
  have p1 := readBytes_array data.path.toUTF8 e1.left
  have p2 := readU32_hex valid.sourceFit e2.left
  have p3 := readBytes_array data.source e3.left
  have p4 := readU32_hex valid.rawFit e4.left
  have p5 := reads_tokens data.raw valid.rawFields e5.left
  have p6 := readU32_hex valid.tokenFit e6.left
  have p7 := reads_tokens data.tokens valid.tokenFields e7.left
  have p8 := reads_assignments data.assignments valid.assignments e8.left
  have p9 := readU32_hex valid.nodeFit e9.left
  have p10 := reads_nodes data.nodes valid.nodes e10.left
  have rawRoom := e5.left.remaining
  have tokenRoom := e7.remaining
  have nodeRoom := e10.left.remaining
  have nodeMin := nodes_encoding_min_length data.nodes
  simp only [hexDigits_length, byte_encoding_length, byteArray_toList, Array.length_toList,
    ByteArray.size_data, tokens_encoding_length, assignments_encoding_length,
    List.flatten_cons, List.flatten_nil, List.length_append, List.length_nil] at p0 p1 p2 p3 p4 p5 p6 p7 p8 p9 p10 rawRoom tokenRoom nodeRoom
  have result := readArtifact_fields data.path data.source
    (data.raw.map fun t => ⟨t.kind.gpuCode, ⟨0, t.start, t.finish⟩⟩)
    (data.tokens.map fun t => ⟨t.kind.gpuCode, ⟨0, t.start, t.finish⟩⟩)
    (data.assignments.map Assignment.code) (data.nodes.map decodedNode)
    p0 p1 p2 p3
    (by simpa only [List.length_map] using p4)
    (by simpa only [List.length_map] using rawRoom) p5
    (by simpa only [List.length_map] using p6)
    (by simpa only [List.length_map] using (show data.tokens.length * 40 ≤ _ from by
      have same := valid.assignmentCount
      omega)) p7
    (by simpa only [List.length_map] using valid.assignmentCount) p8
    (by simpa only [List.length_map] using p9)
    (by simpa only [List.length_map] using (Nat.le_trans nodeMin nodeRoom)) p10
  simpa only [UnitData.artifact, UnitData.encoding, UnitData.chunks, List.flatten_cons,
    List.flatten_nil, List.length_append, List.length_nil, hexDigits_length,
    byte_encoding_length, byteArray_toList, Array.length_toList, ByteArray.size_data,
    tokens_encoding_length, assignments_encoding_length, List.length_map,
    List.isEmpty_map, Nat.add_zero, Nat.add_assoc] using result

end Lanius.Extraction.CompactDecode
