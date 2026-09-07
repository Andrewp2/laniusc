import Lanius.Core

namespace Lanius.Extraction.CanonicalTokens.Ascii

def matchesBytes (source : List Int) (position : Nat) : List UInt8 → Bool
  | [] => true
  | byte :: rest => source[position]? == some (byte.toNat : Int) && matchesBytes source (position + 1) rest

/-- The loop's recursive comparison is exactly equality with the selected
source span, including zero-length spellings. -/
theorem matchesBytes_iff_span (source : List Int) (position : Nat) (bytes : List UInt8)
    (bounded : position + bytes.length ≤ source.length) :
    matchesBytes source position bytes = true ↔
      (source.drop position).take bytes.length = bytes.map (fun byte => (byte.toNat : Int)) := by
  induction bytes generalizing position with
  | nil => simp [matchesBytes]
  | cons byte rest induction =>
      have inBounds : position < source.length := by simp only [List.length_cons] at bounded; omega
      have remaining : position + 1 + rest.length ≤ source.length := by
        simp only [List.length_cons] at bounded
        omega
      simp only [matchesBytes, Bool.and_eq_true, beq_iff_eq, induction (position + 1) remaining]
      rw [List.drop_eq_getElem_cons inBounds]
      simp only [List.length_cons, List.map_cons, List.take_succ_cons, List.cons.injEq,
        List.getElem?_eq_getElem inBounds, Option.some.injEq]

end Lanius.Extraction.CanonicalTokens.Ascii
