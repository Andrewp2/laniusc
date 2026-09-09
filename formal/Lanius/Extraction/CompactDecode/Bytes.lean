import Lanius.Extraction.CompactDecode.Repeat

namespace Lanius.Extraction.CompactDecode

theorem EncodedAt.remaining (encoded : EncodedAt bytes offset values) :
    values.length ≤ bytes.size - offset := by
  by_cases empty : values.length = 0
  · omega
  · have index : values.length - 1 < values.length := by omega
    have found := encoded (values.length - 1) values[values.length - 1]
      (List.getElem?_eq_getElem index)
    have bound : offset + (values.length - 1) < bytes.size := by
      by_cases inside : offset + (values.length - 1) < bytes.size
      · exact inside
      · simp [getElem?_def, inside] at found
    omega

theorem ensureRemaining_ok (room : needed ≤ state.bytes.size - state.offset) :
    (ensureRemaining needed).run state = some ((), state) := by
  simp [ensureRemaining, StateT.run, bind, StateT.bind, get, StateT.get,
    getThe, MonadStateOf.get, pure, StateT.pure, room]

theorem Reads.readBytes {before after : DecodeState} {values : List UInt8}
    (reads : Reads readByte before values after)
    (room : values.length * 2 ≤ before.bytes.size - before.offset) :
    (CompactDecode.readBytes values.length).run before =
      some (values.foldl ByteArray.push ByteArray.empty, after) := by
  have guard := ensureRemaining_ok room
  have loop := reads.loop (List.range' 0 values.length) (by simp) ByteArray.push ByteArray.empty
  unfold CompactDecode.readBytes
  dsimp only
  rw [Std.Legacy.Range.forIn_eq_forIn_range']
  simp only [StateT.run, bind, StateT.bind]
  dsimp only [StateT.run, bind, StateT.bind, pure, StateT.pure] at guard loop ⊢
  rw [guard]
  simp only [Option.bind_some, Std.Legacy.Range.size, Nat.sub_zero,
    Nat.add_sub_cancel, Nat.div_one]
  rw [loop]
  rfl

theorem readBytes_encoding (values : List UInt8)
    (room : values.length * 2 ≤ bytes.size - offset)
    (encoded : EncodedAt bytes offset
      (values.flatMap fun value => CompactOutput.hexDigits value.toNat 2)) :
    (readBytes values.length).run {bytes, offset} =
      some (values.foldl ByteArray.push ByteArray.empty,
        {bytes, offset := offset + values.length * 2}) := by
  have fields : ∀ (value : UInt8) (position : Nat), True →
      EncodedAt bytes position (CompactOutput.hexDigits value.toNat 2) →
      readByte.run {bytes, offset := position} = some (value,
        {bytes, offset := position + (CompactOutput.hexDigits value.toNat 2).length}) := by
    intro value position _ found
    simpa [CompactOutput.hexDigits_length] using readByte_hex value.toNat_lt found
  have reads := reads_encoding (fun value : UInt8 => CompactOutput.hexDigits value.toNat 2)
    (fun _ => True) fields values (by simp) encoded
  have length : (values.flatMap fun value => CompactOutput.hexDigits value.toNat 2).length =
      values.length * 2 := by
    clear room encoded reads
    induction values with
    | nil => rfl
    | cons value values ih => simp [List.flatMap_cons, CompactOutput.hexDigits_length, ih, Nat.add_mul, Nat.add_comm]
  simpa only [length] using reads.readBytes room

end Lanius.Extraction.CompactDecode
