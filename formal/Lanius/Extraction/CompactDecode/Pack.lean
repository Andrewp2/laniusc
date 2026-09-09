import Lanius.Extraction.CompactDecode.Bytes
import Lanius.Extraction.CompactOutput.PackHeader

namespace Lanius.Extraction.CompactDecode

/-- The actual framing reader preserves unit order and rejects empty packs
and trailing bytes, given the composed executions of its unit reader. -/
theorem readPack_units (units : List Artifact)
    (fit : units.length < 4294967296)
    (header : EncodedAt bytes offset (CompactOutput.PackHeader.encoding units.length))
    (room : units.length * 40 ≤ bytes.size - (offset + 16))
    (unitReads : Reads readArtifact {bytes, offset := offset + 16} units after) :
    readPack.run {bytes, offset} =
      if units.isEmpty then none
      else if after.offset = after.bytes.size then some (⟨schemaVersion, units⟩, after)
      else none := by
  have version := readU32_hex (by decide : 1 < 4294967296) header.left
  have count := readU32_hex fit header.right
  simp only [CompactOutput.hexDigits_length] at count
  have guard := ensureRemaining_ok (state := {bytes, offset := offset + 16}) room
  have payload := unitReads.readMany
  simp only [readPack, StateT.run, bind, StateT.bind]
  dsimp only [StateT.run] at version count
  rw [version]
  simp only [Option.bind_some]
  simp only [show (1 != 1) = false from rfl, Bool.false_eq_true, ↓reduceIte]
  dsimp only [StateT.bind]
  rw [count]
  dsimp only [bind, Option.bind, StateT.bind]
  dsimp only [StateT.run, bind, StateT.bind, pure, StateT.pure] at guard payload ⊢
  simp only [Nat.add_assoc] at guard payload ⊢
  rw [guard]
  dsimp only
  rw [payload]
  dsimp only
  split <;> simp_all [get, StateT.get, getThe, MonadStateOf.get, StateT.bind,
    pure, StateT.pure, bind, StateT.run, failure, StateT.failure]
  split <;> rfl

theorem readPack_wrong_version (fit : version < 4294967296) (wrong : version ≠ 1)
    (encoded : EncodedAt bytes offset (CompactOutput.hexDigits version 8)) :
    readPack.run {bytes, offset} = none := by
  have first := readU32_hex fit encoded
  simp only [readPack, StateT.run, bind, StateT.bind]
  dsimp only [StateT.run] at first
  rw [first]
  simp [wrong, StateT.bind, failure, StateT.failure, bind]

end Lanius.Extraction.CompactDecode
