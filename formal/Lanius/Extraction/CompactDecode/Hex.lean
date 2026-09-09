import Lanius.Extraction.CompactDecode.Reader
import Lanius.Extraction.CompactOutput.Sequence

namespace Lanius.Extraction.CompactDecode

open CompactOutput

/-- Exact bytes at a cursor, leaving any surrounding pack bytes unrestricted. -/
def EncodedAt (bytes : ByteArray) (offset : Nat) (values : List Nat) : Prop :=
  ∀ index value, values[index]? = some value → bytes[offset + index]? = some (UInt8.ofNat value)

theorem readHexDigit_at (bounded : value < 16)
    (found : bytes[offset]? = some (UInt8.ofNat (hexDigit value))) :
    readHexDigit.run { bytes := bytes, offset := offset } =
      some (value, { bytes := bytes, offset := offset + 1 }) := by
  have byteBound := hexDigit_bound bounded
  have natValue : (UInt8.ofNat (hexDigit value)).toNat = hexDigit value := by
    exact UInt8.toNat_ofNat_of_lt' byteBound
  dsimp [readHexDigit, StateT.run, bind, StateT.bind, get, StateT.get, pure, StateT.pure,
    set, StateT.set, StateT.lift, liftM, Functor.map, StateT.map, getThe,
    MonadStateOf.get, MonadLiftT.monadLift, MonadLift.monadLift]
  rw [found]
  dsimp only
  rw [natValue]
  by_cases decimal : value < 10
  · have lower : 48 ≤ hexDigit value := by simp only [hexDigit, if_pos decimal]; omega
    have upper : hexDigit value ≤ 57 := by simp only [hexDigit, if_pos decimal]; omega
    rw [if_pos ⟨lower, upper⟩]
    simp [StateT.lift, StateT.bind, StateT.set, StateT.pure, bind, pure, hexDigit, decimal]
  · have lower : 97 ≤ hexDigit value := by simp only [hexDigit, if_neg decimal]; omega
    have upper : hexDigit value ≤ 102 := by simp only [hexDigit, if_neg decimal]; omega
    have notDecimal : ¬ hexDigit value ≤ 57 := by omega
    rw [if_neg (by intro both; exact notDecimal both.2), if_pos ⟨lower, upper⟩]
    simp [StateT.lift, StateT.bind, StateT.set, StateT.pure, bind, pure, hexDigit, decimal]

theorem EncodedAt.tail (encoded : EncodedAt bytes offset (first :: rest)) :
    EncodedAt bytes (offset + 1) rest := by
  intro index value found
  simpa only [Nat.add_assoc, Nat.add_comm 1 index] using
    encoded (index + 1) value (by simpa only [List.getElem?_cons_succ] using found)

theorem EncodedAt.left (encoded : EncodedAt bytes offset (first ++ second)) : EncodedAt bytes offset first := by
  intro index value found
  exact encoded index value (by
    rw [List.getElem?_append_left (List.getElem?_eq_some_iff.mp found).1]
    exact found)

theorem EncodedAt.right (encoded : EncodedAt bytes offset (first ++ second)) :
    EncodedAt bytes (offset + first.length) second := by
  intro index value found
  apply (Nat.add_assoc offset first.length index).symm ▸ encoded (first.length + index) value
  rw [List.getElem?_append_right (by omega), Nat.add_sub_cancel_left]
  exact found

/-- Base-16 accumulation runs on the exact wire bytes and leaves the suffix
untouched. This theorem is about the reader used by the public pack decoder. -/
theorem readHexNat_digits (digits : List Nat) (initial : Nat)
    (bounded : ∀ digit ∈ digits, digit < 16)
    (encoded : EncodedAt bytes offset (digits.map hexDigit)) :
    (readHexNat digits.length initial).run { bytes := bytes, offset := offset } =
      some (digits.foldl (fun acc digit => acc * 16 + digit) initial,
        { bytes := bytes, offset := offset + digits.length }) := by
  induction digits generalizing initial offset with
  | nil => rfl
  | cons digit rest ih =>
    have first := readHexDigit_at (bounded digit List.mem_cons_self)
      (by simpa only [Nat.add_zero] using encoded 0 (hexDigit digit) rfl)
    have later := ih (initial * 16 + digit)
      (fun digit member => bounded digit (List.mem_cons_of_mem _ member)) encoded.tail
    simp only [List.length_cons, readHexNat, StateT.run, bind, StateT.bind]
    dsimp only [StateT.run] at first later
    rw [first]
    simpa only [Option.bind_some, List.foldl_cons, List.length_cons, Nat.add_assoc, Nat.add_comm 1 rest.length] using later

/-- The actual eight-character reader inverts the proved word serializer,
including leading zeroes and arbitrary bytes before and after the field. -/
theorem readU32_hex (bounded : value < 4294967296)
    (encoded : EncodedAt bytes offset (hexDigits value 8)) :
    readU32.run { bytes := bytes, offset := offset } =
      some (value, { bytes := bytes, offset := offset + 8 }) := by
  let digits := [value / 268435456 % 16, value / 16777216 % 16, value / 1048576 % 16,
    value / 65536 % 16, value / 4096 % 16, value / 256 % 16, value / 16 % 16, value % 16]
  have digitBounds : ∀ digit ∈ digits, digit < 16 := by
    intro digit member
    simp only [digits, List.mem_cons, List.not_mem_nil, or_false] at member
    rcases member with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;> omega
  have wire : EncodedAt bytes offset (digits.map hexDigit) := by
    simpa [digits, hexDigits] using encoded
  have decoded := readHexNat_digits digits 0 digitBounds wire
  have valueEqual : digits.foldl (fun acc digit => acc * 16 + digit) 0 = value := by
    dsimp [digits, List.foldl]
    omega
  simpa only [readU32, show digits.length = 8 from rfl, valueEqual] using decoded

theorem readByte_hex (bounded : value < 256)
    (encoded : EncodedAt bytes offset (hexDigits value 2)) :
    readByte.run { bytes := bytes, offset := offset } =
      some (UInt8.ofNat value, { bytes := bytes, offset := offset + 2 }) := by
  let digits := [value / 16 % 16, value % 16]
  have digitBounds : ∀ digit ∈ digits, digit < 16 := by
    intro digit member
    simp only [digits, List.mem_cons, List.not_mem_nil, or_false] at member
    rcases member with rfl | rfl <;> omega
  have wire : EncodedAt bytes offset (digits.map hexDigit) := by
    simpa [digits, hexDigits] using encoded
  have decoded := readHexNat_digits digits 0 digitBounds wire
  have valueEqual : digits.foldl (fun acc digit => acc * 16 + digit) 0 = value := by
    dsimp [digits, List.foldl]
    omega
  have exactRead : (readHexNat 2 0).run { bytes := bytes, offset := offset } =
      some (value, { bytes := bytes, offset := offset + 2 }) := by
    simpa only [show digits.length = 2 from rfl, valueEqual] using decoded
  simp only [readByte, StateT.run, bind, StateT.bind]
  dsimp only [StateT.run] at exactRead
  rw [exactRead]
  rfl

end Lanius.Extraction.CompactDecode
