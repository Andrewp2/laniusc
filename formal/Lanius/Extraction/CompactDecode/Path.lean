import Lanius.Extraction.CompactDecode.Bytes

namespace Lanius.Extraction.CompactDecode

theorem byteArray_toList (bytes : ByteArray) : bytes.toList = bytes.data.toList := by
  have loop : ∀ i acc, ByteArray.toList.loop bytes i acc = acc.reverse ++ bytes.data.toList.drop i := by
    intro i acc
    fun_induction ByteArray.toList.loop bytes i acc with
    | case1 i acc inside ih =>
      rw [ih]
      have item : bytes.get! i = bytes.data.toList[i] := by
        simp [ByteArray.get!, ByteArray.get, inside]
      rw [item]
      simp only [List.reverse_cons, List.append_assoc]
      congr 1
      exact (List.drop_eq_getElem_cons (by simpa using inside)).symm
    | case2 i acc outside =>
      rw [List.drop_eq_nil_of_le (by simpa using Nat.le_of_not_gt outside), List.append_nil]
  simpa only [ByteArray.toList, List.reverse_nil, List.drop_zero, List.nil_append] using loop 0 []

theorem fold_bytes_data (values : List UInt8) (initial : ByteArray) :
    (values.foldl ByteArray.push initial).data = values.foldl Array.push initial.data := by
  induction values generalizing initial with
  | nil => rfl
  | cons value values ih => exact ih (initial.push value)

theorem fold_bytes_toList (bytes : ByteArray) :
    bytes.toList.foldl ByteArray.push ByteArray.empty = bytes := by
  apply ByteArray.ext
  rw [fold_bytes_data]
  rw [byteArray_toList]
  change bytes.data.toList.foldl Array.push #[] = bytes.data
  rw [List.foldl_push_eq_append', Array.empty_append, Array.toArray_toList]

theorem fromUTF8_toUTF8 (path : String) : String.fromUTF8? path.toUTF8 = some path := by
  simp [String.fromUTF8?, String.toUTF8, path.isValidUTF8, String.fromUTF8]

theorem byte_encoding_length (values : List UInt8) :
    (values.flatMap fun value => CompactOutput.hexDigits value.toNat 2).length = values.length * 2 := by
  induction values with
  | nil => rfl
  | cons value values ih =>
    simp [List.flatMap_cons, CompactOutput.hexDigits_length, ih, Nat.add_mul, Nat.add_comm]

theorem readBytes_array (source : ByteArray)
    (encoded : EncodedAt bytes offset
      (source.toList.flatMap fun value => CompactOutput.hexDigits value.toNat 2)) :
    (readBytes source.size).run {bytes, offset} =
      some (source, {bytes, offset := offset + source.size * 2}) := by
  have room := encoded.remaining
  rw [byte_encoding_length] at room
  have run := readBytes_encoding source.toList room encoded
  rw [fold_bytes_toList] at run
  simpa only [byteArray_toList, Array.length_toList, ByteArray.size_data] using run

theorem readPath_encoding (path : String) (fit : path.toUTF8.size < 4294967296)
    (encoded : EncodedAt bytes offset (CompactOutput.hexDigits path.toUTF8.size 8 ++
      path.toUTF8.toList.flatMap (fun value => CompactOutput.hexDigits value.toNat 2))) :
    ((do
      let pathBytes ← readBytes (← readU32)
      let some decoded := String.fromUTF8? pathBytes | failure
      pure decoded) : DecodeM String).run {bytes, offset} =
      some (path, {bytes, offset := offset + 8 + path.toUTF8.size * 2}) := by
  have lengthRead := readU32_hex fit encoded.left
  have bytesRead := readBytes_array path.toUTF8 encoded.right
  simp only [CompactOutput.hexDigits_length] at bytesRead
  simp only [StateT.run, bind, StateT.bind]
  dsimp only [StateT.run] at lengthRead bytesRead
  rw [lengthRead]
  simp only [Option.bind_some]
  rw [bytesRead]
  simp only [Option.bind_some, fromUTF8_toUTF8]
  rfl

end Lanius.Extraction.CompactDecode
