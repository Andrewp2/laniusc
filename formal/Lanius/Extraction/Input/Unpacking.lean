import Lanius.Extraction.OutputPacking.Prefix
import Lanius.ExecutionRules

namespace Lanius.Extraction.Input

open Lanius.Core Lanius.Semantics

private theorem wrap_mod_i32 (target : Target) (value : Int) :
    wrapSigned target .i32 value % 4294967296 = value % 4294967296 := by
  change (if value % 4294967296 ≥ 2147483648 then value % 4294967296 - 4294967296
    else value % 4294967296) % 4294967296 = value % 4294967296
  split <;> simp

/-- The source's arithmetic right shift agrees with floor division at each
byte lane, including negative packed words. -/
theorem shift_right_lane (target : Target) (word : Int) (lane : Nat) (bound : lane < 4) :
    evalSignedBinary target .shiftRight .i32 word (lane * 8 : Nat) =
      .ok (.signed .i32 (wrapSigned target .i32 (word / (2 ^ (lane * 8) : Nat)))) := by
  have laneCases : lane = 0 ∨ lane = 1 ∨ lane = 2 ∨ lane = 3 := by omega
  have arithmetic :
      (if word ≥ 0 then word / (2 ^ (lane * 8) : Nat)
       else -((-word + (2 ^ (lane * 8) : Nat) - 1) / (2 ^ (lane * 8) : Nat))) =
      word / (2 ^ (lane * 8) : Nat) := by
    rcases laneCases with rfl | rfl | rfl | rfl <;>
      simp only [Nat.reduceMul, Nat.reducePow] <;>
      split <;> omega
  have nonnegative : ¬ (((lane * 8 : Nat) : Int) < 0) := by omega
  have below : ¬ (((lane * 8 : Nat) : Int) ≥ ((32 : Nat) : Int)) := by omega
  unfold evalSignedBinary
  simp only [SignedIntTy.bits, Int.ofNat_eq_natCast, nonnegative, below, decide_false,
    Bool.false_or, Bool.false_eq_true, if_false, Int.toNat_natCast]
  change (Except.ok (Value.signed .i32 (wrapSigned target .i32
    (if word ≥ 0 then word / (2 ^ (lane * 8) : Nat)
     else -((-word + (2 ^ (lane * 8) : Nat) - 1) / (2 ^ (lane * 8) : Nat))))) :
      Except Lanius.Trap Value) = _
  rw [arithmetic]

theorem mask_low_byte (target : Target) (word : Int) :
    evalSignedBinary target .bitAnd .i32 (wrapSigned target .i32 word) 255 =
      .ok (.signed .i32 (word % 256)) := by
  change (Except.ok (Value.signed .i32 (wrapSigned target .i32
    (Int.ofNat (Nat.land ((wrapSigned target .i32 word % 4294967296).toNat) 255)))) :
      Except Lanius.Trap Value) = _
  rw [wrap_mod_i32]
  have masked : Nat.land (word % 4294967296).toNat 255 =
      (word % 4294967296).toNat % 256 :=
    Nat.and_two_pow_sub_one_eq_mod _ 8
  rw [masked]
  have modulo : (word % 4294967296).toNat % 256 = (word % 256).toNat := by omega
  rw [modulo]
  have canonical : Int.ofNat (word % 256).toNat = word % 256 :=
    Int.toNat_of_nonneg (Int.emod_nonneg _ (by decide))
  rw [canonical, wrapSigned_i32_of_nonnegative target _ (by omega) (by omega)]

/-- The byte obtained by shifting and masking is the corresponding byte of
the authoritative little-endian host representation. -/
theorem shifted_byte_is_storage_byte (word : Int) (lane : Nat) (bound : lane < 4) :
    (i32Bytes word)[lane]? =
      some (UInt8.ofNat (word / (2 ^ (lane * 8) : Nat) % 256).toNat) := by
  have laneCases : lane = 0 ∨ lane = 1 ∨ lane = 2 ∨ lane = 3 := by omega
  have modulo : (word % 4294967296).toNat / 2 ^ (lane * 8) % 256 =
      (word / (2 ^ (lane * 8) : Nat) % 256).toNat := by
    rcases laneCases with rfl | rfl | rfl | rfl <;>
      simp only [Nat.reduceMul, Nat.reducePow] <;> omega
  simpa [i32Bytes, bound, Nat.mul_comm] using congrArg (fun value => some (UInt8.ofNat value)) modulo

/-- Compose the exact Core shift-and-mask expression used to unpack host
file reads into the extractor's one-i32-per-byte source buffer. -/
theorem evaluates_unpacked_byte
    {program : Program} {before afterWord afterShift : State}
    {wordExpr shiftExpr : Expr} (word : Int) (lane : Nat) (bound : lane < 4)
    (wordResult : Evaluates program before wordExpr (.signed .i32 word) afterWord)
    (shiftResult : Evaluates program afterWord shiftExpr (.signed .i32 (lane * 8 : Nat)) afterShift) :
    Evaluates program before
      (.binary .bitAnd (.binary .shiftRight wordExpr shiftExpr) (.value (.signed .i32 255)))
      (.signed .i32 (word / (2 ^ (lane * 8) : Nat) % 256)) afterShift := by
  have shifted : Evaluates program before (.binary .shiftRight wordExpr shiftExpr)
      (.signed .i32 (wrapSigned program.target .i32 (word / (2 ^ (lane * 8) : Nat)))) afterShift := by
    apply evaluatesEagerBinary (by decide) (by decide) wordResult shiftResult
    simpa only [evalBinaryValue, BEq.rfl, if_true] using shift_right_lane program.target word lane bound
  apply evaluatesEagerBinary (by decide) (by decide) shifted
    (show Evaluates program afterShift (.value (.signed .i32 255)) (.signed .i32 255) afterShift from ⟨1, rfl⟩)
  simpa only [evalBinaryValue, BEq.rfl, if_true] using
    mask_low_byte program.target (word / (2 ^ (lane * 8) : Nat))

/-- Refreshing a packed raw view loses no byte information. Together with
`shifted_byte_is_storage_byte`, this links source-byte reads to the bytes
actually supplied by the host, including a partially overwritten last word. -/
theorem encode_after_decode_i32_array
    (decoded : decodeI32Array count bytes = .ok elements) :
    encodeI32Array elements = .ok bytes := by
  induction count generalizing bytes elements with
  | zero =>
      cases bytes with
      | nil => simp [decodeI32Array] at decoded; subst elements; rfl
      | cons byte rest => simp [decodeI32Array] at decoded
  | succ count induction =>
      match bytes with
      | [] => simp [decodeI32Array] at decoded
      | [a] => simp [decodeI32Array] at decoded
      | [a, b] => simp [decodeI32Array] at decoded
      | [a, b, c] => simp [decodeI32Array] at decoded
      | a :: b :: c :: d :: rest =>
          have enough : ¬ rest.length + 1 + 1 + 1 + 1 < 4 := by omega
          cases remaining : decodeI32Array count rest with
          | error reason => simp [decodeI32Array, remaining, enough] at decoded
          | ok tail =>
              have result : Value.signed .i32 (decodeI32 [a, b, c, d]) :: tail = elements := by
                simpa [decodeI32Array, remaining, enough] using decoded
              subst elements
              simp [encodeI32Array, induction remaining, OutputPacking.i32Bytes_decode_four]

/-- Every whole-word byte buffer decodes to signed i32 storage. This is an
existence theorem, not an assumption that decoding already succeeded. -/
theorem decode_whole_words (count : Nat) (bytes : List UInt8)
    (length : bytes.length = count * 4) :
    ∃ words : List Int, words.length = count ∧
      decodeI32Array count bytes = .ok (signedI32Values words) ∧
      encodeI32Array (signedI32Values words) = .ok bytes := by
  suffices result : ∃ words : List Int, words.length = count ∧
      decodeI32Array count bytes = .ok (signedI32Values words) by
    obtain ⟨words, size, decoded⟩ := result
    exact ⟨words, size, decoded, encode_after_decode_i32_array decoded⟩
  induction count generalizing bytes with
  | zero =>
      have empty : bytes = [] := List.eq_nil_of_length_eq_zero (by simpa using length)
      subst bytes
      exact ⟨[], rfl, rfl⟩
  | succ count ih =>
      match bytes with
      | [] | [_] | [_, _] | [_, _, _] => simp at length <;> omega
      | a :: b :: c :: d :: rest =>
          obtain ⟨words, size, decoded⟩ := ih rest (by simp only [List.length_cons] at length; omega)
          refine ⟨decodeI32 [a, b, c, d] :: words, by simp [size], ?_⟩
          simp [decodeI32Array, decoded, signedI32Values]

/-- Encoding and refreshing an in-range signed word preserves its value,
including negative words. Out-of-range mathematical integers are not valid
i32 storage and are intentionally excluded. -/
theorem decode_encoded_i32_value (word : Int)
    (lower : -2147483648 ≤ word) (upper : word ≤ 2147483647) :
    decodeI32 (i32Bytes word) = word := by
  let bits := (word % 4294967296).toNat
  have bitsBound : bits < 4294967296 := by dsimp [bits]; omega
  have digits : bits % 256 + bits / 256 % 256 * 256 +
      bits / 65536 % 256 * 65536 + bits / 16777216 % 256 * 16777216 = bits := by omega
  have decoded : decodeI32 (i32Bytes word) =
      if bits ≥ 2147483648 then (bits : Int) - 4294967296 else (bits : Int) := by
    have bytes : i32Bytes word = [UInt8.ofNat (bits % 256),
        UInt8.ofNat (bits / 256 % 256), UInt8.ofNat (bits / 65536 % 256),
        UInt8.ofNat (bits / 16777216 % 256)] := by
      simp [i32Bytes, List.range_succ, bits]
    rw [bytes]
    simp only [decodeI32, UInt8.toNat_ofNat', Nat.reducePow, Nat.mod_mod]
    rw [digits]
    rfl
  rw [decoded]
  dsimp [bits]
  split <;> omega

/-- Any array of valid i32 values is coherent across raw-view encoding and
refresh. This discharges the coherence premise when framing typed buffers. -/
theorem decode_i32_array_of_encoding (values : List Int)
    (range : ∀ word ∈ values, -2147483648 ≤ word ∧ word ≤ 2147483647)
    (encoded : encodeI32Array (signedI32Values values) = .ok bytes) :
    decodeI32Array values.length bytes = .ok (signedI32Values values) := by
  induction values generalizing bytes with
  | nil =>
      simp [signedI32Values, encodeI32Array] at encoded
      subst bytes
      rfl
  | cons word rest induction =>
      change (match encodeI32Array (signedI32Values rest) with
        | .ok bytes => Except.ok (i32Bytes word ++ bytes)
        | .error reason => Except.error reason) = _ at encoded
      cases tailEncoded : encodeI32Array (signedI32Values rest) with
      | error reason => rw [tailEncoded] at encoded; cases encoded
      | ok tail =>
          rw [tailEncoded] at encoded
          cases encoded
          have width : (i32Bytes word).length = 4 := by simp [i32Bytes]
          have first : (i32Bytes word ++ tail).take 4 = i32Bytes word := by rw [← width]; simp
          have restBytes : (i32Bytes word ++ tail).drop 4 = tail := by rw [← width]; simp
          have enough : ¬ (i32Bytes word ++ tail).length < 4 := by simp [width]
          have wordRange := range word (by simp)
          have restRange := fun value (member : value ∈ rest) => range value (by simp [member])
          have decodedWord := decode_encoded_i32_value word wordRange.1 wordRange.2
          simp only [List.length_cons, decodeI32Array, enough, if_false, restBytes, first,
            induction restRange tailEncoded, decodedWord]
          rfl

/-- A successful scratch-buffer refresh has exactly the requested number of
signed words. This supplies the typed list and capacity used by the loop. -/
theorem decode_i32_array_values
    (decoded : decodeI32Array count bytes = .ok elements) :
    ∃ values : List Int, elements = signedI32Values values ∧ values.length = count := by
  induction count generalizing bytes elements with
  | zero =>
      cases bytes with
      | nil => simp [decodeI32Array] at decoded; subst elements; exact ⟨[], rfl, rfl⟩
      | cons byte rest => simp [decodeI32Array] at decoded
  | succ count induction =>
      match bytes with
      | [] => simp [decodeI32Array] at decoded
      | [a] => simp [decodeI32Array] at decoded
      | [a, b] => simp [decodeI32Array] at decoded
      | [a, b, c] => simp [decodeI32Array] at decoded
      | a :: b :: c :: d :: rest =>
          have enough : ¬ rest.length + 1 + 1 + 1 + 1 < 4 := by omega
          cases remaining : decodeI32Array count rest with
          | error reason => simp [decodeI32Array, remaining, enough] at decoded
          | ok tail =>
              have result : Value.signed .i32 (decodeI32 [a, b, c, d]) :: tail = elements := by
                simpa [decodeI32Array, remaining, enough] using decoded
              obtain ⟨values, valuesEq, lengthEq⟩ := induction remaining
              subst elements
              exact ⟨decodeI32 [a, b, c, d] :: values,
                by simp [signedI32Values, valuesEq], by simp [lengthEq]⟩

end Lanius.Extraction.Input
