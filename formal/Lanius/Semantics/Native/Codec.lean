import Lanius.Semantics

namespace Lanius.Semantics

/-- Four arbitrary bytes survive signed-i32 decoding and re-encoding. -/
theorem i32Bytes_decode_four (a b c d : UInt8) :
    i32Bytes (decodeI32 [a, b, c, d]) = [a, b, c, d] := by
  have ha := UInt8.toNat_lt a
  have hb := UInt8.toNat_lt b
  have hc := UInt8.toNat_lt c
  have hd := UInt8.toNat_lt d
  let bits := a.toNat + b.toNat * 256 + c.toNat * 65536 + d.toNat * 16777216
  have bounds : bits < 4294967296 := by dsimp [bits]; omega
  have decoded :
      (decodeI32 [a, b, c, d] % 4294967296).toNat = bits := by
    simp only [decodeI32]
    change ((if bits ≥ 2147483648 then (bits : Int) - 4294967296
      else (bits : Int)) % 4294967296).toNat = bits
    split <;> omega
  have h0 : bits % 256 = a.toNat := by dsimp [bits]; omega
  have h1 : bits / 256 % 256 = b.toNat := by dsimp [bits]; omega
  have h2 : bits / 65536 % 256 = c.toNat := by dsimp [bits]; omega
  have h3 : bits / 16777216 % 256 = d.toNat := by dsimp [bits]; omega
  simp [i32Bytes, List.range_succ, decoded, h0, h1, h2, h3]

theorem decodeNatLE_i32Bytes (word : BitVec 32) :
    decodeNatLE (i32Bytes word.toInt) = word.toNat := by
  have bound := word.isLt
  have bits : (word.toInt % (2 ^ 32 : Int)).toNat = word.toNat :=
    signedBits_i32_bitvec_x86 word word.toInt rfl
  simp only [i32Bytes, bits]
  simp [List.range_succ, decodeNatLE]
  omega
/-- The native signed codec recovers every representable i32 word. -/
theorem decodeI32_i32Bytes_word (word : BitVec 32) :
    decodeI32 (i32Bytes word.toInt) = word.toInt := by
  have bound := word.isLt
  have bits : (word.toInt % (2 ^ 32 : Int)).toNat = word.toNat :=
    signedBits_i32_bitvec_x86 word word.toInt rfl
  simp only [i32Bytes, bits]
  simp [List.range_succ, decodeI32, BitVec.toInt_eq_msb_cond, BitVec.msb_eq_decide]
  omega

theorem decodeI32_i32Bytes (lower : (-2147483648 : Int) ≤ value) (upper : value ≤ 2147483647) :
    decodeI32 (i32Bytes value) = value := by
  have exact : (BitVec.ofInt 32 value).toInt = value :=
    BitVec.toInt_ofInt_eq_self (by decide) (by change -2147483648 ≤ value; exact lower)
      (by change value < 2147483648; omega)
  simpa only [exact] using decodeI32_i32Bytes_word (BitVec.ofInt 32 value)

/-- The same native bytes justify both an indexed read and a later write. -/
theorem readRawSliceIndex_i32Bytes (program : Lanius.Core.Program) (state : State)
    {word : BitVec 32}
    (bound : position < length)
    (loaded : state.heap.loadBytes (address + position * 4) 4 = .ok (i32Bytes word.toInt)) :
    readRawSliceIndex program state (.scalar (.signed .i32)) address length position =
      .ok (.signed .i32 word.toInt) := by
  unfold readRawSliceIndex
  rw [if_neg (Nat.not_le_of_lt bound)]
  change readNativeValue NativeLayout.maxDepth program state.heap
    (.scalar (.signed .i32)) (address + position * 4) = _
  simp only [readNativeValue, NativeLayout.maxDepth, loadNatLE]
  rw [loaded]
  change (Except.ok (.signed .i32 (if decodeNatLE (i32Bytes word.toInt) ≥ 2 ^ 31 then
    Int.ofNat (decodeNatLE (i32Bytes word.toInt)) - 2 ^ 32 else
    Int.ofNat (decodeNatLE (i32Bytes word.toInt)))) : Except Lanius.Trap Lanius.Core.Value) = _
  rw [decodeNatLE_i32Bytes]
  congr 2
  simp [BitVec.toInt_eq_msb_cond, BitVec.msb_eq_decide]

#print axioms decodeI32_i32Bytes
#print axioms readRawSliceIndex_i32Bytes

end Lanius.Semantics
