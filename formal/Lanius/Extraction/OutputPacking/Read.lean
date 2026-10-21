import Lanius.Extraction.OutputPacking.Byte
import Lanius.Semantics.Bitwise
import Lanius.Semantics.Stable
import Lanius.Memory.Read

namespace Lanius.Extraction.OutputPacking

open Lanius Lanius.Core Lanius.Semantics

/-- Every readable four-byte word has the representation expected by the
    byte writer; its old contents need not be zero or nonnegative. -/
theorem readableWord {heap : Memory.Heap} (readable : heap.Readable address 4) :
    ∃ word : BitVec 32, heap.loadBytes address 4 = .ok (i32Bytes word.toInt) := by
  obtain ⟨a, ha⟩ := readable 0 (by decide)
  obtain ⟨b, hb⟩ := readable 1 (by decide)
  obtain ⟨c, hc⟩ := readable 2 (by decide)
  obtain ⟨d, hd⟩ := readable 3 (by decide)
  let word := BitVec.ofInt 32 (decodeI32 [a, b, c, d])
  have encode : i32Bytes word.toInt = [a, b, c, d] := by
    have bits : (word.toInt % (2 ^ 32 : Int)).toNat = word.toNat :=
      signedBits_i32_bitvec_x86 word word.toInt rfl
    have same : i32Bytes word.toInt = i32Bytes (decodeI32 [a, b, c, d]) := by
      simp only [i32Bytes, bits, word, BitVec.toNat_ofInt]
      rfl
    exact same.trans (i32Bytes_decode_four a b c d)
  refine ⟨word, ?_⟩
  rw [encode]
  simp only [Memory.Heap.loadBytes, Memory.loadBytesFrom, ha, hb, hc, hd]

/-- An arbitrary readable packed range supplies the indexed word and its
    exact selected byte. Other lanes may contain any bytes, including sign bits. -/
theorem readableByte {state : State} (readable : state.heap.Readable address (count * 4))
    (inside : index < count * 4) :
    ∃ word : BitVec 32,
      readRawSliceIndex program state (.scalar (.signed .i32)) address count (index / 4) =
        .ok (.signed .i32 word.toInt) ∧
      state.heap.loadByte address index =
        .ok (UInt8.ofBitVec (byteAt word ⟨index % 4, Nat.mod_lt _ (by decide)⟩)) := by
  obtain ⟨word, loaded⟩ := readableWord
    (readable.subrange (start := index / 4 * 4) (length := 4) (by omega))
  refine ⟨word, readRawSliceIndex_i32Bytes program state (by omega) loaded, ?_⟩
  exact Memory.Heap.loadByte_alias
    (Memory.Heap.loadBytes_get loaded (i32Bytes_at word ⟨index % 4, Nat.mod_lt _ (by decide)⟩)) (by
      dsimp only [Lanius.Address]; omega)

/-- Decode a packed byte using the source language's signed shift and mask.
    Operand expressions remain arbitrary proved computations. -/
theorem readByteExpression (word : BitVec 32) (lane : Fin 4)
    (target : program.target = .x86_64)
    (read : StableExpr readFuel program state wordExpr (.signed .i32 word.toInt) state)
    (shift : StableExpr shiftFuel program state shiftExpr (.signed .i32 (lane.val * 8 : Nat)) state)
    (mask : StableExpr maskFuel program state maskExpr (.signed .i32 255) state) :
    StableExpr (max (max readFuel shiftFuel + 1) maskFuel + 1) program state
      (.binary .bitAnd (.binary .shiftRight wordExpr shiftExpr) maskExpr)
      (.signed .i32 (byteAt word lane).toNat) state := by
  have shiftOp : evalBinaryValue program.target .shiftRight
      (.signed .i32 word.toInt) (.signed .i32 (lane.val * 8 : Nat)) =
      .ok (.signed .i32 (word.sshiftRight (lane.val * 8)).toInt) := by
    have shifted := evalSignedBinary_shiftRight_i32_x86_word word.toInt (lane.val * 2) (by omega)
    have count : 4 * (lane.val * 2) = lane.val * 8 := by omega
    rw [count, ← BitVec.toInt_sshiftRight, wrapSigned_bmod, ← BitVec.toInt_ofInt,
      BitVec.ofInt_toInt] at shifted
    simpa only [evalBinaryValue, target, BEq.rfl, ↓reduceIte, Int.ofNat_eq_natCast] using shifted
  have shifted := StableExpr.binary read shift (by decide) shiftOp
  apply StableExpr.binary shifted mask (by decide)
  simpa only [evalBinaryValue, target, BEq.rfl, ↓reduceIte,
    show (255 : BitVec 32).toInt = 255 by decide, byteAt_shift_mask, byteAt_toInt] using
    evalSignedBinary_i32_and (word.sshiftRight (lane.val * 8)) 255

#print axioms readableByte

end Lanius.Extraction.OutputPacking
