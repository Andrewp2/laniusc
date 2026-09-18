import Std.Tactic

namespace Lanius.X86

/-- Four bytes in increasing memory-address order, not host-native storage. -/
structure WordBytes where
  low : Fin 256
  second : Fin 256
  third : Fin 256
  high : Fin 256
deriving DecidableEq, Repr

def wordBytes (value : BitVec 32) : WordBytes :=
  let n := value.toNat
  ⟨⟨n % 256, Nat.mod_lt _ (by decide)⟩,
   ⟨(n / 256) % 256, Nat.mod_lt _ (by decide)⟩,
   ⟨(n / 65536) % 256, Nat.mod_lt _ (by decide)⟩,
   ⟨(n / 16777216) % 256, Nat.mod_lt _ (by decide)⟩⟩

def readBytes (bytes : WordBytes) : BitVec 32 :=
  BitVec.ofNat 32 (bytes.low.val + 256 * bytes.second.val +
    65536 * bytes.third.val + 16777216 * bytes.high.val)

theorem readBytes_wordBytes (value : BitVec 32) : readBytes (wordBytes value) = value := by
  apply BitVec.eq_of_toNat_eq
  have bound := value.isLt
  simp only [readBytes, wordBytes, BitVec.toNat_ofNat]
  omega

theorem wordBytes_injective : Function.Injective wordBytes := by
  intro left right same
  have := congrArg readBytes same
  simpa only [readBytes_wordBytes] using this

abbrev ByteMemory := Nat → Fin 256

def readWord (memory : ByteMemory) (field : Nat) : BitVec 32 :=
  readBytes ⟨memory field, memory (field + 1), memory (field + 2), memory (field + 3)⟩

def writeWord (memory : ByteMemory) (field : Nat) (value : BitVec 32) : ByteMemory :=
  let bytes := wordBytes value
  fun index =>
    if index = field then bytes.low
    else if index = field + 1 then bytes.second
    else if index = field + 2 then bytes.third
    else if index = field + 3 then bytes.high
    else memory index

theorem readWord_writeWord (memory : ByteMemory) (field : Nat) (value : BitVec 32) :
    readWord (writeWord memory field value) field = value := by
  have one : field + 1 ≠ field := by omega
  have two : field + 2 ≠ field := by omega
  have three : field + 3 ≠ field := by omega
  have twoOne : field + 2 ≠ field + 1 := by omega
  have threeOne : field + 3 ≠ field + 1 := by omega
  have threeTwo : field + 3 ≠ field + 2 := by omega
  simpa only [readWord, writeWord, ↓reduceIte, if_neg one, if_neg two,
    if_neg three, if_neg twoOne, if_neg threeOne, if_neg threeTwo]
    using readBytes_wordBytes value

theorem writeWord_frame (memory : ByteMemory) (field index : Nat) (value : BitVec 32)
    (outside : index < field ∨ field + 4 ≤ index) :
    writeWord memory field value index = memory index := by
  have a : index ≠ field := by omega
  have b : index ≠ field + 1 := by omega
  have c : index ≠ field + 2 := by omega
  have d : index ≠ field + 3 := by omega
  simp only [writeWord, if_neg a, if_neg b, if_neg c, if_neg d]

end Lanius.X86
