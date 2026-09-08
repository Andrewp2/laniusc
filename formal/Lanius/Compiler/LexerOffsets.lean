import Lanius.Compiler.Lexer

namespace Lanius.Compiler.Lexer

def ScanEnd.shift (base : Nat) : ScanEnd → ScanEnd
  | .success finish => .success (base + finish)
  | .failure error => .failure (base + error)

theorem scanIdentifierEnd_offset (source : List Byte) (base start : Nat) :
    scanIdentifierEnd source (base + start) =
      base + scanIdentifierEnd (source.drop base) start := by
  simp [scanIdentifierEnd, List.drop_drop, Nat.add_assoc]

theorem scanWhitespaceEnd_offset (source : List Byte) (base start : Nat) :
    scanWhitespaceEnd source (base + start) =
      base + scanWhitespaceEnd (source.drop base) start := by
  simp [scanWhitespaceEnd, List.drop_drop, Nat.add_assoc]

theorem scanLineCommentEnd_offset (source : List Byte) (base start : Nat) :
    scanLineCommentEnd source (base + start) =
      base + scanLineCommentEnd (source.drop base) start := by
  simp [scanLineCommentEnd, List.drop_drop, Nat.add_assoc]

theorem scanQuotedBody_offset (delimiter : Byte) (input : List Byte)
    (base offset : Nat) (escaping : Bool) :
    scanQuotedBody delimiter escaping input (base + offset) =
      (scanQuotedBody delimiter escaping input offset).shift base := by
  induction input generalizing escaping offset with
  | nil => rfl
  | cons byte rest induction =>
      cases escaping <;>
        simp only [scanQuotedBody, Nat.add_assoc, induction]
      split
      · rfl
      · split
        · rfl
        · split <;> rfl

theorem scanQuotedEnd_offset (source : List Byte) (base start : Nat) (delimiter : Byte) :
    scanQuotedEnd source (base + start) delimiter =
      (scanQuotedEnd (source.drop base) start delimiter).shift base := by
  simp only [scanQuotedEnd, List.drop_drop, Nat.add_assoc]
  exact scanQuotedBody_offset delimiter _ base (start + 1) false

theorem scanBlockBody_offset (input : List Byte) (base offset : Nat) :
    scanBlockBody input (base + offset) = (scanBlockBody input offset).shift base := by
  induction input generalizing offset with
  | nil => rfl
  | cons byte rest induction =>
      cases rest with
      | nil => rfl
      | cons next tail =>
          rw [scanBlockBody, scanBlockBody]
          split
          · rfl
          · simpa only [Nat.add_assoc] using induction (offset + 1)

theorem scanBlockCommentEnd_offset (source : List Byte) (base start : Nat) :
    scanBlockCommentEnd source (base + start) =
      (scanBlockCommentEnd (source.drop base) start).shift base := by
  simp only [scanBlockCommentEnd, List.drop_drop, Nat.add_assoc]
  exact scanBlockBody_offset _ base (start + 2)

end Lanius.Compiler.Lexer
