import Lanius.Extraction.CompactDecode.Unit
import Lanius.Extraction.CompactOutput.Unit.Arguments

namespace Lanius.Extraction.CompactDecode

open CompactOutput SemanticTokens Lanius.Compiler.Lexer

theorem byte_hex_encoding (value : UInt8) :
    hexDigits value.toNat 2 = [hexDigit (value.toNat / 16), hexDigit (value.toNat % 16)] := by
  have bound := value.toNat_lt
  have high : value.toNat / 16 < 16 := by omega
  simp [hexDigits, Nat.mod_eq_of_lt high]

def sourceArray (values : List Byte) : ByteArray :=
  ⟨(values.map fun value => UInt8.ofNat value.val).toArray⟩

theorem sourceArray_size (values : List Byte) : (sourceArray values).size = values.length := by
  simp only [sourceArray, ByteArray.size, List.size_toArray, List.length_map]

theorem sourceArray_values (values : List Byte) :
    (sourceArray values).toList.map UInt8.toNat = values.map Fin.val := by
  rw [byteArray_toList]
  simp only [sourceArray, List.toList_toArray, List.map_map]
  apply List.map_congr_left
  intro value _
  exact UInt8.toNat_ofNat_of_lt' value.isLt

def emissionUnit (emission : Unit.Emission) (path : String)
    (assignments : List Assignment) (records : List RecordVisit) : UnitData :=
  {path, source := sourceArray emission.data.request.source,
    raw := emission.data.raw, tokens := emission.data.tokens, assignments, nodes := records}

theorem emission_encoding (emission : Unit.Emission) (path : String)
    (assignments : List Assignment) (records : List RecordVisit)
    (pathBytes : path.toUTF8.toList.map UInt8.toNat = emission.path.map Fin.val) :
    (emissionUnit emission path assignments records).encoding = emission.encoding assignments records := by
  have pathCount := congrArg List.length pathBytes
  simp only [List.length_map, byteArray_toList, Array.length_toList, ByteArray.size_data] at pathCount
  have pathHex : path.toUTF8.toList.flatMap (fun b => hexDigits b.toNat 2) =
      Bytes.encoding (emission.path.map Fin.val) := by
    rw [← pathBytes]
    simp only [Bytes.encoding, List.flatMap_map, byte_hex_encoding]
  have sourceHex : (sourceArray emission.data.request.source).toList.flatMap
      (fun b => hexDigits b.toNat 2) = Bytes.encoding (emission.data.request.source.map Fin.val) := by
    rw [← sourceArray_values emission.data.request.source]
    simp only [Bytes.encoding, List.flatMap_map, byte_hex_encoding]
  simp only [UnitData.encoding, UnitData.chunks, emissionUnit, List.flatten_cons,
    List.flatten_nil, List.append_nil, pathCount, sourceArray_size, pathHex, sourceHex,
    Unit.Emission.encoding, Tokens.encodeAll, Nodes.encodeAll, List.append_assoc]

theorem emission_decode (emission : Unit.Emission) (path : String)
    (assignments : List Assignment) (records : List RecordVisit)
    (pathBytes : path.toUTF8.toList.map UInt8.toNat = emission.path.map Fin.val)
    (valid : (emissionUnit emission path assignments records).Encodable)
    (encoded : EncodedAt bytes offset (emission.encoding assignments records)) :
    readArtifact.run {bytes, offset} = if records.isEmpty then none else
      some ((emissionUnit emission path assignments records).artifact,
        {bytes, offset := offset + (emission.encoding assignments records).length}) := by
  have same := emission_encoding emission path assignments records pathBytes
  have run := (emissionUnit emission path assignments records).decode valid (same.symm ▸ encoded)
  rw [same] at run
  exact run

end Lanius.Extraction.CompactDecode
