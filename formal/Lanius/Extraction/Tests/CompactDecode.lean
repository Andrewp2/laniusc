import Lanius.Extraction.CompactDecode.Hex
import Lanius.Extraction.CompactDecode.Fields
import Lanius.Extraction.CompactDecode.Repeat
import Lanius.Extraction.CompactDecode.Bytes
import Lanius.Extraction.CompactDecode.Nodes
import Lanius.Extraction.CompactDecode.Tokens
import Lanius.Extraction.CompactDecode.Path
import Lanius.Extraction.CompactDecode.Pack
import Lanius.Extraction.CompactDecode.Artifact
import Lanius.Extraction.CompactDecode.Units
import Lanius.Extraction.CompactArtifact
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.CompactDecode

open Lanius.Extraction.CompactDecode Lanius.Extraction.CompactOutput

run_elab do
  let standard : Array Lean.Name := #[``propext, ``Classical.choice, ``Quot.sound]
  for name in #[``readHexDigit_at, ``EncodedAt.tail, ``EncodedAt.left, ``EncodedAt.right,
      ``readHexNat_digits, ``readU32_hex, ``readByte_hex,
      ``readToken_encoding, ``readSemanticKind_fields, ``readChild_fields,
      ``Reads.loop, ``Reads.readMany, ``reads_encoding,
      ``ensureRemaining_ok, ``Reads.readBytes, ``readBytes_encoding, ``readNode_header,
      ``readChild_encoding, ``reads_children, ``readNode_encoding,
      ``EncodedAt.remaining, ``children_encoding_length, ``record_encoding_length,
      ``reads_nodes, ``readNodes_encoding, ``readAssignment_encoding,
      ``reads_assignments, ``reads_tokens, ``readAssignments_encoding, ``readTokens_encoding,
      ``byteArray_toList, ``fold_bytes_data, ``fold_bytes_toList, ``fromUTF8_toUTF8,
      ``byte_encoding_length, ``readBytes_array, ``readPath_encoding,
      ``readPack_units, ``readPack_wrong_version, ``readArtifact_fields,
      ``tokens_encoding_length, ``assignments_encoding_length, ``nodes_encoding_min_length,
      ``UnitData.decode, ``reads_units, ``unit_encoding_min_length,
      ``units_encoding_min_length, ``readPack_encoding] do
    unless (← Lean.getEnv).contains name do throwError "Missing compact decoder theorem {name}"
    for axiomName in ← Lean.collectAxioms name do
      unless standard.contains axiomName do throwError "Compact decoder theorem {name} depends on {axiomName}"
  Lean.logInfo "Forty-eight compact decoder theorems use standard axioms only."

private def bytesOf (values : List Nat) : ByteArray :=
  ⟨(values.map UInt8.ofNat).toArray⟩

/-- Execution checks complement the generic proofs with actual byte arrays,
every byte value, word boundaries, nonzero cursors, and truncated fields. -/
def checkExecution : IO Unit := do
  let mut cases := 0
  let units : List UnitData := [
    {path := "first.lani", source := "first".toUTF8, raw := [], tokens := [],
      assignments := [], nodes := [⟨0, 0, 0, 0, []⟩]},
    {path := "第二.lani", source := "second".toUTF8, raw := [], tokens := [],
      assignments := [], nodes := [⟨0, 0, 0, 0, []⟩]}]
  let wire := PackHeader.encoding units.length ++ units.flatMap UnitData.encoding
  for cut in List.range (wire.length + 1) do
    let result := decodeCompactArtifactPack? (String.fromUTF8! (bytesOf (wire.take cut)))
    if cut < wire.length then
      unless result.isNone do throw (IO.userError "Ordered pack accepted a truncation")
    else
      let some pack := result | throw (IO.userError "Ordered unit encoding failed")
      unless pack.units.map (·.sources) == units.map (fun unit => unit.artifact.sources) do
        throw (IO.userError "Ordered pack changed source contents or order")
    cases := cases + 1
  let path := "编译/source.lani"
  let source := [0, 255, 65]
  let pathHex := path.toUTF8.toList.flatMap (fun value => hexDigits value.toNat 2)
  let sourceHex := source.flatMap (fun value => hexDigits value 2)
  let rest := [1, 1, 0, 3, 1, 1, 0, 3, 1, 0, 1, 0, 0, 1, 1, 1, 0]
  let rich := hexDigits path.toUTF8.size 8 ++ pathHex ++ hexDigits source.length 8 ++
    sourceHex ++ rest.flatMap (fun value => hexDigits value 8)
  for cut in List.range (rich.length + 1) do
    let bytes := bytesOf (rich.take cut)
    let result := readArtifact.run {bytes, offset := 0}
    if cut < rich.length then
      unless result.isNone do throw (IO.userError "Artifact reader accepted truncated fields")
    else
      let some (unit, state) := result | throw (IO.userError "Complete artifact did not decode")
      let expectedToken : Token := ⟨1, ⟨0, 0, 3⟩⟩
      unless unit.sources == [{path, bytes := source}] && unit.raw_tokens == some [expectedToken] &&
          unit.tokens == [expectedToken] && unit.semantic_token_kinds == [1] &&
          unit.parse_root == some 0 && unit.parse_nodes.map (·.children) == [[.token 0]] &&
          state.offset == rich.length && state.bytes == bytes do
        throw (IO.userError "Artifact decoding lost a source, token, semantic kind, child, or cursor")
    cases := cases + 1
  let unitFields := [0, 0, 0, 0, 1, 0, 0, 0, 0]
  for count in [1, 2] do
    let fields := [1, count] ++ (List.replicate count unitFields).flatten
    let encoded := String.fromUTF8! (bytesOf (fields.flatMap (fun value => hexDigits value 8)))
    let some pack := decodeCompactArtifactPack? encoded
      | throw (IO.userError "Well-framed compact pack fixture failed to decode")
    unless pack.units.length = count && pack.units.all (fun unit =>
        unit.sources.length = 1 && unit.tokens.isEmpty && unit.parse_nodes.length = 1 &&
        unit.parse_root == some 0) do
      throw (IO.userError "Decoded compact pack fixture lost fields")
    cases := cases + 1
    for suffix in ["0", "00", "00000000"] do
      unless (decodeCompactArtifactPack? (encoded ++ suffix)).isNone do
        throw (IO.userError "Compact pack accepted trailing bytes")
      cases := cases + 1
  for version in [0, 2, 4294967295] do
    let encoded := String.fromUTF8! (bytesOf (([version, 1] ++ unitFields).flatMap
      (fun value => hexDigits value 8)))
    unless (decodeCompactArtifactPack? encoded).isNone do
      throw (IO.userError "Compact pack accepted wrong version")
    cases := cases + 1
  for path in ["", "src/main.lani", "é/编译/🦅.lani"] do
    let encoded := hexDigits path.toUTF8.size 8 ++
      path.toUTF8.toList.flatMap (fun value => hexDigits value.toNat 2)
    for cut in List.range (encoded.length + 1) do
      let bytes := bytesOf (encoded.take cut)
      let reader : DecodeM String := do
        let pathBytes ← readBytes (← readU32)
        let some decoded := String.fromUTF8? pathBytes | failure
        pure decoded
      let actual := (reader.run {bytes, offset := 0}).map
        (fun (value, state) => (value, state.offset, state.bytes == bytes))
      let expected := if cut = encoded.length then some (path, cut, true) else none
      unless actual == expected do throw (IO.userError s!"Path decoding failed: path={path}, cut={cut}")
      cases := cases + 1
  for fields in [[], [(0, 0)], [(32767, 0), (0, 1), (32767, 32768)]] do
    let encoded := fields.flatMap (fun (first, second) => hexDigits first 8 ++ hexDigits second 8)
    let expectedValues := fields.map (fun (first, second) =>
      if second = 0 then first else 2147483648 + first + (second - 1) * 32768)
    for cut in List.range (encoded.length + 1) do
      let bytes := bytesOf (encoded.take cut)
      let actual := ((readMany fields.length readSemanticKind).run {bytes, offset := 0}).map
        (fun (values, state) => (values, state.offset, state.bytes == bytes))
      let expected := if cut = encoded.length then some (expectedValues, cut, true) else none
      unless actual == expected do
        throw (IO.userError s!"Semantic-kind list failed: cut={cut}")
      cases := cases + 1
  let some production := laniusGrammar.production? 0
    | throw (IO.userError "Node decoder fixture requires grammar production zero")
  for children in [([] : List ParseChild), [.token 0, .node 1, .token 4294967295]] do
    let fields := [0, 0, 3, children.length] ++ children.flatMap (fun child =>
      match child with | .token id => [1, id] | .node id => [2, id])
    let encoded := fields.flatMap (fun field => hexDigits field 8)
    for count in [0, 2] do
      let repeated := (List.replicate count encoded).flatten
      for cut in List.range (repeated.length + 1) do
        let bytes := bytesOf (repeated.take cut)
        let actual := ((readMany count readNode).run {bytes, offset := 0}).map
          (fun (nodes, state) => (nodes, state.offset, state.bytes == bytes))
        let node : ParseNode := ⟨0, production.lhs, 0, 3, children⟩
        let expected := if cut = repeated.length then
          some (List.replicate count node, cut, true) else none
        unless actual == expected do
          throw (IO.userError s!"Node-list reader failed: count={count}, cut={cut}")
        cases := cases + 1
    for padding in [0, 3] do
      for cut in List.range (encoded.length + 1) do
        let bytes := bytesOf (List.replicate padding 255 ++ encoded.take cut)
        let actual := (readNode.run {bytes, offset := padding}).map (fun (node, state) =>
          (node.production, node.nonterminal, node.position_start, node.position_end,
            node.children, state.offset, state.bytes == bytes))
        let expected := if cut = encoded.length then
          some (0, production.lhs, 0, 3, children, padding + cut, true) else none
        unless actual == expected do
          throw (IO.userError s!"Node reader failed: padding={padding}, cut={cut}")
        cases := cases + 1
  for values in [[], [0], [0, 255, 1, 128]] do
    for padding in [0, 3] do
      let encoded := values.flatMap (fun value => hexDigits value 2)
      for cut in List.range (encoded.length + 1) do
        let bytes := bytesOf (List.replicate padding 255 ++ encoded.take cut)
        let actual := ((readMany values.length readByte).run {bytes, offset := padding}).map
          (fun (result, state) => (result.map UInt8.toNat, state.offset, state.bytes == bytes))
        let expected := if cut = encoded.length then some (values, padding + cut, true) else none
        unless actual == expected do
          throw (IO.userError s!"Repeated reader failed: values={values}, padding={padding}, cut={cut}")
        cases := cases + 1
        let actualBytes := ((readBytes values.length).run {bytes, offset := padding}).map
          (fun (result, state) => (result.toList.map UInt8.toNat, state.offset, state.bytes == bytes))
        unless actualBytes == expected do
          throw (IO.userError s!"Byte-array reader failed: values={values}, padding={padding}, cut={cut}")
        cases := cases + 1
  for padding in [0, 3] do
    for value in List.range 256 do
      for cut in List.range 3 do
        let bytes := bytesOf (List.replicate padding 255 ++ (hexDigits value 2).take cut)
        let decoded := readByte.run { bytes, offset := padding }
        let actual := decoded.map (fun (value, state) => (value.toNat, state.offset, state.bytes == bytes))
        let expected := if cut = 2 then some (value, padding + 2, true) else none
        unless actual == expected do throw (IO.userError s!"Byte decoding failed: value={value}, padding={padding}, cut={cut}")
        cases := cases + 1
    for value in [0, 1, 15, 16, 255, 256, 65535, 65536, 2147483647, 4294967295] do
      for cut in List.range 9 do
        let bytes := bytesOf (List.replicate padding 255 ++ (hexDigits value 8).take cut)
        let decoded := readU32.run { bytes, offset := padding }
        let actual := decoded.map (fun (value, state) => (value, state.offset, state.bytes == bytes))
        let expected := if cut = 8 then some (value, padding + 8, true) else none
        unless actual == expected do throw (IO.userError s!"Word decoding failed: value={value}, padding={padding}, cut={cut}")
        cases := cases + 1
  for encoded in ["", "not-hex", "0000000100000000", "0000000100000001ffffffff", "000000010000000100000000"] do
    unless (decodeCompactArtifactPack? encoded).isNone do
      throw (IO.userError "Malformed or empty compact pack was accepted")
    cases := cases + 1
  IO.println s!"Compact decoder: {cases} byte/word truncation, cursor, boundary, and malformed-pack executions passed."

#eval checkExecution

end Lanius.Extraction.Tests.CompactDecode
