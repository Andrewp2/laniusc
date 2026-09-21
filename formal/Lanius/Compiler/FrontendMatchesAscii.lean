import Lanius.Compiler.Lexer

namespace Lanius.Compiler.Lexer

/-- The bounded byte span read by `canonical_tokens.matches_ascii`. -/
def sourceSpan (source : List Byte) (start length : Nat) : List Byte :=
  (source.drop start).take length

/-- A small list model for the source loop.  The spelling list contains the
    compact, unpadded ASCII bytes; padding words never enters this model. -/
def matchesAsciiLoop : List Nat → List Nat → Bool
  | _, [] => true
  | [], _ :: _ => false
  | actual :: rest, expected :: tail =>
      actual == expected && matchesAsciiLoop rest tail

def matchesAscii (source : List Byte) (start : Nat) (spelling : List Nat) : Bool :=
  matchesAsciiLoop ((sourceSpan source start spelling.length).map Fin.val) spelling

theorem matchesAsciiLoop_iff (actual expected : List Nat) :
    matchesAsciiLoop actual expected = true ↔ actual.take expected.length = expected := by
  induction actual generalizing expected with
  | nil => cases expected <;> simp [matchesAsciiLoop]
  | cons actual rest inductionHypothesis =>
      cases expected with
      | nil => simp [matchesAsciiLoop]
      | cons expected tail =>
          simp only [matchesAsciiLoop, Bool.and_eq_true, beq_iff_eq]
          rw [inductionHypothesis]
          simp

theorem matchesAscii_iff_span
    (source : List Byte) (start : Nat) (spelling : List Nat)
    (bounded : start + spelling.length ≤ source.length) :
    matchesAscii source start spelling = true ↔
      (sourceSpan source start spelling.length).map Fin.val = spelling := by
  have spanLength : (sourceSpan source start spelling.length).length = spelling.length := by
    unfold sourceSpan
    rw [List.length_take]
    have dropLength : spelling.length ≤ (source.drop start).length := by
      rw [List.length_drop]
      omega
    exact Nat.min_eq_left dropLength
  let actual : List Nat := (sourceSpan source start spelling.length).map Fin.val
  have actualLength : actual.length = spelling.length := by
    dsimp [actual]
    simpa using spanLength
  have take_eq : actual.take spelling.length = actual := by
    rw [← actualLength]
    exact List.take_length
  change matchesAsciiLoop actual spelling = true ↔ actual = spelling
  rw [matchesAsciiLoop_iff, take_eq]

theorem matchesAscii_false_of_first_mismatch
    (pre : List Nat) (actual expected : Nat)
    (actualTail expectedTail : List Nat) (mismatch : actual ≠ expected) :
    matchesAsciiLoop (pre ++ actual :: actualTail)
      (pre ++ expected :: expectedTail) = false := by
  induction pre generalizing actual expected actualTail expectedTail with
  | nil => simp [matchesAsciiLoop, mismatch]
  | cons head tail inductionHypothesis =>
      simpa [matchesAsciiLoop] using
        inductionHypothesis actual expected actualTail expectedTail mismatch

theorem matchesAscii_false_of_source_mismatch
    (pre : List Byte) (actual : Byte) (suffix : List Byte)
    (expectedPrefix : List Nat) (expected : Nat) (expectedTail : List Nat)
    (prefixEq : pre.map Fin.val = expectedPrefix)
    (mismatch : actual.val ≠ expected) :
    matchesAsciiLoop ((pre ++ actual :: suffix).map Fin.val)
      (expectedPrefix ++ expected :: expectedTail) = false := by
  simp only [List.map_append, List.map_cons]
  rw [prefixEq]
  exact matchesAscii_false_of_first_mismatch
    expectedPrefix actual.val expected (suffix.map Fin.val) expectedTail mismatch

end Lanius.Compiler.Lexer
