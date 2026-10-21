import Lanius.Semantics.Typing.Values
import Lanius.Semantics.Native.Codec

namespace Lanius.Semantics

open Lanius.Core Lanius.Typing

/-- Every typed i32 array encodes at exactly its native four-byte stride.
    Encoding success is derived from the element types, not supplied by callers. -/
theorem encodeI32Array_typed (typed : ValuesHaveTypes program elements
    (List.replicate count (.scalar (.signed .i32)))) :
    ∃ bytes, encodeI32Array elements = .ok bytes ∧ bytes.length = count * 4 := by
  induction count generalizing elements with
  | zero => cases typed; exact ⟨[], rfl, rfl⟩
  | succ count ih =>
    cases typed with
    | cons head tail =>
      cases head with
      | signed _ value lower upper =>
        obtain ⟨bytes, encoded, length⟩ := ih tail
        exact ⟨i32Bytes value ++ bytes, by simp only [encodeI32Array, encoded],
          by simp only [List.length_append, i32Bytes, List.length_map, List.length_range, length]; omega⟩

#print axioms encodeI32Array_typed

/-- Four arbitrary bytes always decode to a representable signed i32.
    Short lists use the decoder's specified zero result. -/
theorem decodeI32_typed (bytes : List UInt8) :
    ValueHasType program (.signed .i32 (decodeI32 bytes)) (.scalar (.signed .i32)) := by
  match bytes with
  | [] | [_] | [_, _] | [_, _, _] =>
    exact .signed .i32 0 (by change (-2147483648 : Int) ≤ 0; decide)
      (by change (0 : Int) ≤ 2147483647; decide)
  | a :: b :: c :: d :: rest =>
    have ha := UInt8.toNat_lt a
    have hb := UInt8.toNat_lt b
    have hc := UInt8.toNat_lt c
    have hd := UInt8.toNat_lt d
    apply ValueHasType.signed
    all_goals
      simp only [signedMin, signedMax, SignedIntTy.bits, decodeI32, Int.ofNat_eq_natCast]
      split <;> omega

/-- Readability supplies the exact byte count; arbitrary host-written data
    then decodes successfully to an array of the declared extent and type. -/
theorem decodeI32Array_typed (length : bytes.length = count * 4) :
    ∃ elements, decodeI32Array count bytes = .ok elements ∧
      ValueHasType program (.array elements) (.array (.scalar (.signed .i32)) count) := by
  induction count generalizing bytes with
  | zero =>
    have empty : bytes = [] := List.eq_nil_of_length_eq_zero (by omega)
    subst bytes
    exact ⟨[], rfl, .array _ _ rfl .nil⟩
  | succ count ih =>
    obtain ⟨elements, decoded, typed⟩ := ih (bytes := bytes.drop 4) (by simp only [List.length_drop]; omega)
    cases typed with
    | array elements element extent elementsTyped =>
      exact ⟨.signed .i32 (decodeI32 (bytes.take 4)) :: elements,
        by simp only [decodeI32Array, if_neg (by omega : ¬bytes.length < 4), decoded],
        .array _ _ (by simp only [List.length_cons, extent])
          (.cons (decodeI32_typed _) elementsTyped)⟩

#print axioms decodeI32Array_typed

theorem encodeI32Array_length (encoded : encodeI32Array elements = .ok bytes) :
    bytes.length = elements.length * 4 := by
  induction elements generalizing bytes with
  | nil => cases encoded; rfl
  | cons head tail ih =>
    cases head <;> try simp [encodeI32Array] at encoded
    case signed type value =>
      cases type <;> try simp [encodeI32Array] at encoded
      case i32 =>
        cases result : encodeI32Array tail with
        | error reason => simp only [result] at encoded; cases encoded
        | ok rest =>
          have same : bytes = i32Bytes value ++ rest := by
            simpa only [encodeI32Array, result, Except.ok.injEq] using encoded.symm
          subst bytes
          simp only [List.length_cons, List.length_append, i32Bytes, List.length_map, List.length_range, ih result]
          omega

/-- Native synchronization recovers the complete typed array, not merely
    another array with the same element type and extent. -/
theorem decodeI32Array_encode (typed : ValuesHaveTypes program elements
    (List.replicate count (.scalar (.signed .i32)))) (encoded : encodeI32Array elements = .ok bytes) :
    decodeI32Array count bytes = .ok elements := by
  induction count generalizing elements bytes with
  | zero => cases typed; cases encoded; rfl
  | succ count ih =>
    cases typed with
    | cons head tail =>
      cases head with
      | signed _ value lower upper =>
        obtain ⟨rest, tailEncoded, _⟩ := encodeI32Array_typed tail
        have same : bytes = i32Bytes value ++ rest := by
          simpa only [encodeI32Array, tailEncoded, Except.ok.injEq] using encoded.symm
        subst bytes
        have width : (i32Bytes value).length = 4 := by simp only [i32Bytes, List.length_map, List.length_range]
        have decoded := decodeI32_i32Bytes (by simpa [signedMin, SignedIntTy.bits] using lower)
          (by simpa [signedMax, SignedIntTy.bits] using upper)
        have take : (i32Bytes value ++ rest).take 4 = i32Bytes value := by
          rw [← width]; simp
        have drop : (i32Bytes value ++ rest).drop 4 = rest := by
          rw [← width]; simp
        simp only [decodeI32Array, List.length_append, width, if_neg (by omega : ¬ 4 + rest.length < 4),
          take, drop, decoded, ih tail tailEncoded]

/-- Every exact native byte range also survives decoding and re-encoding. -/
theorem encodeI32Array_decode (length : bytes.length = count * 4)
    (decoded : decodeI32Array count bytes = .ok elements) : encodeI32Array elements = .ok bytes := by
  induction count generalizing bytes elements with
  | zero =>
    have empty : bytes = [] := List.eq_nil_of_length_eq_zero (by omega)
    subst bytes; cases decoded; rfl
  | succ count ih =>
    match bytes with
    | [] | [_] | [_, _] | [_, _, _] => simp only [List.length_cons, List.length_nil] at length; omega
    | a :: b :: c :: d :: rest =>
      obtain ⟨tail, tailDecoded, _⟩ := decodeI32Array_typed (program := ({} : Program)) (count := count)
        (bytes := rest) (by simp only [List.length_cons] at length; omega)
      have same : elements = .signed .i32 (decodeI32 [a, b, c, d]) :: tail := by
        simpa only [decodeI32Array, List.length_cons, if_neg (by omega : ¬rest.length + 1 + 1 + 1 + 1 < 4),
          List.take, List.drop, tailDecoded, Except.ok.injEq] using decoded.symm
      subst elements
      simp only [encodeI32Array, ih (by simp only [List.length_cons] at length; omega) tailDecoded,
        i32Bytes_decode_four, List.cons_append, List.nil_append]

#print axioms decodeI32Array_encode
#print axioms encodeI32Array_decode

end Lanius.Semantics
