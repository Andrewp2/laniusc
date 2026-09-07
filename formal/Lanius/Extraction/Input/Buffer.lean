import Lanius.Extraction.Input.Unpacking

namespace Lanius.Extraction.Input

open Lanius.Core Lanius.Semantics

def copiedBuffer (earlier untouched : List Int) (processed : List UInt8) : List Int :=
  earlier ++ processed.map (fun byte => (byte.toNat : Int)) ++ untouched.drop processed.length

theorem copiedBuffer_length (earlier untouched : List Int) (processed : List UInt8)
    (bound : processed.length ≤ untouched.length) :
    (copiedBuffer earlier untouched processed).length = earlier.length + untouched.length := by
  simp only [copiedBuffer, List.length_append, List.length_map, List.length_drop]
  omega

private theorem set_after_prefix (front : List Int) (old value : Int) (rest : List Int) :
    setI32Value (front ++ old :: rest) front.length value = front ++ value :: rest := by
  simp [setI32Value, List.set_append_right]

theorem copiedBuffer_step (earlier untouched : List Int) (processed : List UInt8) (byte : UInt8)
    (room : processed.length < untouched.length) :
    setI32Value (copiedBuffer earlier untouched processed) (earlier.length + processed.length)
      byte.toNat = copiedBuffer earlier untouched (processed ++ [byte]) := by
  cases remaining : untouched.drop processed.length with
  | nil =>
      have lengths := congrArg List.length remaining
      simp only [List.length_drop, List.length_nil] at lengths
      omega
  | cons old rest =>
      have next : untouched.drop (processed.length + 1) = rest := by
        have dropped := congrArg (List.drop 1) remaining
        simpa [List.drop_drop, Nat.add_comm] using dropped
      have position : earlier.length + processed.length =
          (earlier ++ processed.map (fun byte => (byte.toNat : Int))).length := by simp
      simp only [copiedBuffer, List.length_append, List.length_singleton, remaining, next]
      rw [position, set_after_prefix]
      simp [List.map_append, List.append_assoc]

theorem encoded_word_byte (values : List Int) (index lane : Nat) (word : Int)
    (encoded : encodeI32Array (signedI32Values values) = .ok storage)
    (selected : values[index]? = some word) (laneBound : lane < 4) :
    storage[index * 4 + lane]? = (i32Bytes word)[lane]? := by
  induction values generalizing storage index with
  | nil => simp at selected
  | cons first rest induction =>
      cases tailEncoded : encodeI32Array (signedI32Values rest) with
      | error reason =>
          have failure : encodeI32Array (signedI32Values (first :: rest)) = .error reason := by
            change (match encodeI32Array (signedI32Values rest) with
              | .ok bytes => Except.ok (i32Bytes first ++ bytes)
              | .error reason => Except.error reason) = _
            rw [tailEncoded]
          rw [failure] at encoded
          cases encoded
      | ok tail =>
          have same : i32Bytes first ++ tail = storage := by
            simpa only [signedI32Values, List.map_cons, encodeI32Array,
              show encodeI32Array (List.map (fun value => Value.signed .i32 value) rest) = .ok tail
                from tailEncoded, Except.ok.injEq] using encoded
          subst storage
          cases index with
          | zero =>
              simp only [List.getElem?_cons_zero, Option.some.injEq] at selected
              subst first
              simpa using List.getElem?_append_left
                (l₁ := i32Bytes word) (l₂ := tail) (by simpa [i32Bytes] using laneBound)
          | succ index =>
              simp only [List.getElem?_cons_succ] at selected
              have bound : (i32Bytes first).length ≤ (index + 1) * 4 + lane := by
                simp only [i32Bytes, List.length_map, List.length_range]
                omega
              rw [List.getElem?_append_right bound]
              have position : (index + 1) * 4 + lane - (i32Bytes first).length = index * 4 + lane := by
                simp only [i32Bytes, List.length_map, List.length_range]
                omega
              rw [position]
              exact induction index tailEncoded selected

theorem unpacked_value_of_encoded_byte (values : List Int) (index lane : Nat)
    (word : Int) (byte : UInt8)
    (encoded : encodeI32Array (signedI32Values values) = .ok storage)
    (selected : values[index]? = some word) (laneBound : lane < 4)
    (byteSelected : storage[index * 4 + lane]? = some byte) :
    word / (2 ^ (lane * 8) : Nat) % 256 = (byte.toNat : Int) := by
  have wordByte := encoded_word_byte values index lane word encoded selected laneBound
  have actualByte := shifted_byte_is_storage_byte word lane laneBound
  have same := Option.some.inj (actualByte.symm.trans (wordByte.symm.trans byteSelected))
  have natural := congrArg UInt8.toNat same
  have nonnegative : 0 ≤ word / (2 ^ (lane * 8) : Nat) % 256 := Int.emod_nonneg _ (by decide)
  have bound : (word / (2 ^ (lane * 8) : Nat) % 256).toNat < 256 := by omega
  change (word / (2 ^ (lane * 8) : Nat) % 256).toNat % 256 = byte.toNat at natural
  rw [Nat.mod_eq_of_lt bound] at natural
  exact (Int.toNat_of_nonneg nonnegative).symm.trans (congrArg Int.ofNat natural)

/-- The byte-access expression shared by file unpacking and compact ASCII
comparison. Arithmetic is over the existing packed i32 words, without a
second decoding pass or assumed correspondence to source bytes. -/
def packedByteExpression (packed index : Expr) : Expr :=
  .binary .bitAnd
    (.binary .shiftRight
      (.index packed (.binary .divide index (.value (.signed .i32 4))))
      (.binary .multiply (.binary .remainder index (.value (.signed .i32 4)))
        (.value (.signed .i32 8))))
    (.value (.signed .i32 255))

theorem evaluates_encoded_byte (program : Program) (before : State)
    (packed indexExpression : Expr) (root : CellId) (values : List Int)
    (storage : List UInt8) (index : Nat) (byte : UInt8)
    (bounded : index ≤ 2147483647)
    (packedResult : Evaluates program before packed
      (.slice (.scalar (.signed .i32)) root [] 0 values.length) before)
    (indexResult : Evaluates program before indexExpression (.signed .i32 index) before)
    (contents : before.cellEntry? root = some {
      id := root
      value := some (.array (signedI32Values values)) })
    (encoded : encodeI32Array (signedI32Values values) = .ok storage)
    (selected : storage[index]? = some byte) :
    Evaluates program before (packedByteExpression packed indexExpression)
      (.signed .i32 byte.toNat) before := by
  have byteBound := (List.getElem?_eq_some_iff.mp selected).1
  have storageLength : storage.length = values.length * 4 := by
    rw [encodeSignedI32Values] at encoded
    cases encoded
    simp [List.length_flatMap, i32Bytes, List.map_const', List.sum_replicate_nat]
  have wordBound : index / 4 < values.length := by omega
  let word := values.get ⟨index / 4, wordBound⟩
  have wordSelected : values[index / 4]? = some word := by simp [word, wordBound]
  have laneBound : index % 4 < 4 := Nat.mod_lt _ (by decide)
  have byteValue := unpacked_value_of_encoded_byte values (index / 4) (index % 4) word byte
    encoded wordSelected laneBound (by simpa [Nat.mul_comm, Nat.div_add_mod] using selected)
  have four : Evaluates program before (.value (.signed .i32 4)) (.signed .i32 4) before := ⟨1, rfl⟩
  have eight : Evaluates program before (.value (.signed .i32 8)) (.signed .i32 8) before := ⟨1, rfl⟩
  have quotient := evaluatesNatI32Divide (leftValue := index) (rightValue := 4)
    indexResult four (by decide) (by omega)
  have remainder := evaluatesNatI32Remainder (leftValue := index) (rightValue := 4)
    indexResult four (by decide) (by omega)
  have shift := evaluatesNatI32Multiply (leftValue := index % 4) (rightValue := 8)
    remainder eight (by omega)
  have wordResult := evaluatesSignedI32SliceIndex program before before before values
    packed _ root (index / 4) wordBound packedResult quotient contents
  have result := evaluates_unpacked_byte word (index % 4) laneBound wordResult shift
  rw [byteValue] at result
  exact result

end Lanius.Extraction.Input
