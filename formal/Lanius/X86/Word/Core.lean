import Lanius.X86.Word
import Lanius.Extraction.Input.Unpacking

namespace Lanius.X86

def WordBytes.toBytes (bytes : WordBytes) : List UInt8 :=
  [UInt8.ofNat bytes.low.val, UInt8.ofNat bytes.second.val,
   UInt8.ofNat bytes.third.val, UInt8.ofNat bytes.high.val]

/-- The backend's instruction/displacement words use exactly Core's existing
raw i32 memory representation, including negative integers. -/
theorem wordBytes_core (value : Int) :
    (wordBytes (BitVec.ofInt 32 value)).toBytes = Lanius.Semantics.i32Bytes value := by
  simp [WordBytes.toBytes, wordBytes, BitVec.toNat_ofInt,
    Lanius.Semantics.i32Bytes, List.range_succ]

/-- Reuse the frontend's proved shift/mask interpretation rather than defining
another meaning for the Lanius encoder's byte extraction expressions. -/
theorem wordBytes_sourceLane (value : Int) (lane : Nat) (bound : lane < 4) :
    ((wordBytes (BitVec.ofInt 32 value)).toBytes)[lane]? =
      some (UInt8.ofNat (value / (2 ^ (lane * 8) : Nat) % 256).toNat) := by
  rw [wordBytes_core]
  exact Lanius.Extraction.Input.shifted_byte_is_storage_byte value lane bound

end Lanius.X86
