import Lanius.Semantics

namespace Lanius.Extraction.OutputPacking

open Lanius.Core Lanius.Semantics

/-! Byte-level specification for the extractor's final packed workspace.
The authoritative raw-view serializer is `encodeI32Array`. The lemmas here
connect signed i32 storage to exact bytes, including high-bit bytes and the
zero-padded final word. They do not assume that the source packing loop has
already established this representation. -/

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

/-- The mathematical contents of the packed output workspace. The final word
is zero padded, but the host write uses the unpadded byte count. -/
def pack : List UInt8 → List Value
  | [] => []
  | [a] => [.signed .i32 (decodeI32 [a, 0, 0, 0])]
  | [a, b] => [.signed .i32 (decodeI32 [a, b, 0, 0])]
  | [a, b, c] => [.signed .i32 (decodeI32 [a, b, c, 0])]
  | a :: b :: c :: d :: rest =>
      .signed .i32 (decodeI32 [a, b, c, d]) :: pack rest

def padding (length : Nat) : Nat := (4 - length % 4) % 4

theorem encodeI32Array_append (left right : List Value) :
    encodeI32Array (left ++ right) =
      match encodeI32Array left, encodeI32Array right with
      | .ok first, .ok second => .ok (first ++ second)
      | .error reason, _ => .error reason
      | _, .error reason => .error reason := by
  induction left with
  | nil => cases result : encodeI32Array right <;> simp [encodeI32Array, result]
  | cons head tail ih =>
      cases head <;> try simp [encodeI32Array]
      rename_i type value
      cases type <;> try simp [encodeI32Array]
      simp only [ih]
      cases encodeI32Array tail <;> cases encodeI32Array right <;>
        simp [List.append_assoc]

theorem encode_pack (bytes : List UInt8) :
    encodeI32Array (pack bytes) =
      .ok (bytes ++ List.replicate (padding bytes.length) 0) := by
  match bytes with
  | [] => rfl
  | [a] => simp [pack, encodeI32Array, i32Bytes_decode_four, padding]
  | [a, b] => simp [pack, encodeI32Array, i32Bytes_decode_four, padding]
  | [a, b, c] => simp [pack, encodeI32Array, i32Bytes_decode_four, padding]
  | a :: b :: c :: d :: rest =>
      rw [pack, encodeI32Array, encode_pack rest, i32Bytes_decode_four]
      have samePadding : padding (rest.length + 1 + 1 + 1 + 1) =
          padding rest.length := by unfold padding; omega
      simp only [List.length_cons, samePadding]
      rfl
termination_by bytes.length

theorem encode_pack_exact_prefix (bytes : List UInt8) :
    ∃ storage, encodeI32Array (pack bytes) = .ok storage ∧
      storage.take bytes.length = bytes := by
  refine ⟨bytes ++ List.replicate (padding bytes.length) 0, encode_pack bytes, ?_⟩
  simp

/-- The parser workspace can be larger than the output. Its unused tail may
contain arbitrary i32 values; the requested prefix still contains exactly the
output bytes, without requiring the rest of the allocation to be zeroed. -/
theorem encode_pack_workspace_prefix (bytes : List UInt8) (tail : List Value)
    (storage : List UInt8)
    (encoded : encodeI32Array (pack bytes ++ tail) = .ok storage) :
    bytes.length ≤ storage.length ∧ storage.take bytes.length = bytes := by
  rw [encodeI32Array_append, encode_pack] at encoded
  cases encodedTail : encodeI32Array tail with
  | error reason => simp [encodedTail] at encoded
  | ok tailBytes =>
      simp only [encodedTail, Except.ok.injEq] at encoded
      subst storage
      simp [List.append_assoc]

theorem pack_length (bytes : List UInt8) :
    (pack bytes).length = (bytes.length + 3) / 4 := by
  match bytes with
  | [] => rfl
  | [a] => simp [pack]
  | [a, b] => simp [pack]
  | [a, b, c] => simp [pack]
  | a :: b :: c :: d :: rest =>
      simp only [pack, List.length_cons, pack_length rest]
      omega
termination_by bytes.length

theorem wrapped_i32_bits (target : Target) (bits : Nat)
    (bounded : bits < 4294967296) :
    (wrapSigned target .i32 bits % 4294967296).toNat = bits := by
  change ((if (bits : Int) % 4294967296 ≥ 2147483648 then
    (bits : Int) % 4294967296 - 4294967296
    else (bits : Int) % 4294967296) % 4294967296).toNat = bits
  by_cases sign : (bits : Int) % 4294967296 ≥ 2147483648
  · rw [if_pos sign]; omega
  · rw [if_neg sign]; omega

/-- The actual Core shift used by the source packing loop is defined for each
of the four byte lanes, including the sign-bit lane. -/
theorem packing_shift (target : Target) (byte : UInt8) (lane : Nat)
    (laneBound : lane < 4) :
    evalSignedBinary target .shiftLeft .i32 byte.toNat (lane * 8 : Nat) =
      .ok (.signed .i32
        (wrapSigned target .i32 (byte.toNat * 2 ^ (lane * 8) : Nat))) := by
  have valid : (decide (((lane * 8 : Nat) : Int) < 0) ||
      decide (((lane * 8 : Nat) : Int) ≥ Int.ofNat (SignedIntTy.i32.bits target))) =
        false := by simp [SignedIntTy.bits]; omega
  unfold evalSignedBinary
  rw [valid]
  simp only [Bool.false_eq_true, if_false, Int.toNat_natCast]
  rw [Int.natCast_mul]
  rfl

/-- OR-ing the next byte into an initially zero word agrees with arithmetic
concatenation. `lowerBound` is the loop invariant that unfilled high lanes are
still zero; without it OR would not implement packing. -/
theorem packing_or (target : Target) (byte : UInt8) (lane lower : Nat)
    (laneBound : lane < 4) (lowerBound : lower < 2 ^ (lane * 8)) :
    evalSignedBinary target .bitOr .i32
        (wrapSigned target .i32 lower)
        (wrapSigned target .i32 (byte.toNat * 2 ^ (lane * 8) : Nat)) =
      .ok (.signed .i32 (wrapSigned target .i32
        (lower + byte.toNat * 2 ^ (lane * 8) : Nat))) := by
  have byteBound := UInt8.toNat_lt byte
  have cases : lane = 0 ∨ lane = 1 ∨ lane = 2 ∨ lane = 3 := by omega
  have lower32 : lower < 4294967296 := by
    rcases cases with rfl | rfl | rfl | rfl <;> simp_all <;> omega
  have shifted32 : byte.toNat * 2 ^ (lane * 8) < 4294967296 := by
    rcases cases with rfl | rfl | rfl | rfl <;> simp_all <;> omega
  have combined : Nat.lor lower (byte.toNat * 2 ^ (lane * 8)) =
      lower + byte.toNat * 2 ^ (lane * 8) := by
    simpa [Nat.shiftLeft_eq, Nat.or_comm, Nat.add_comm] using
      (Nat.shiftLeft_add_eq_or_of_lt lowerBound byte.toNat).symm
  change (Except.ok (.signed .i32 (wrapSigned target .i32
    (Nat.lor (wrapSigned target .i32 lower % 4294967296).toNat
      (wrapSigned target .i32
        (byte.toNat * 2 ^ (lane * 8) : Nat) % 4294967296).toNat : Nat))) :
      Except Lanius.Trap Value) = _
  rw [wrapped_i32_bits target lower lower32,
    wrapped_i32_bits target _ shifted32, combined]

theorem packing_preserves_zero_high_lanes (byte : UInt8) (lane lower : Nat)
    (lowerBound : lower < 2 ^ (lane * 8)) :
    lower + byte.toNat * 2 ^ (lane * 8) < 2 ^ ((lane + 1) * 8) := by
  have byteBound := UInt8.toNat_lt byte
  rw [Nat.add_mul, Nat.pow_add]
  have positive := Nat.two_pow_pos (lane * 8)
  have mulBound := Nat.mul_le_mul_right (2 ^ (lane * 8))
    (show byte.toNat ≤ 255 by omega)
  simp only [Nat.one_mul] at *
  omega

end Lanius.Extraction.OutputPacking
