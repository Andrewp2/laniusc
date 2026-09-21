import Lean.Elab.Tactic.Omega
import Lanius.Compiler.Lexer

namespace Lanius.Compiler.Lexer

/-! Pure equations for the mathematical quoted scanner.  These facts expose
    the same six branches used by the quoted Core loop without re-proving its
    evaluator behavior. -/

@[simp] theorem scanQuotedBody_nil (delimiter : Byte) (escaping : Bool) (offset : Nat) :
    scanQuotedBody delimiter escaping [] offset = .failure offset := by rfl

@[simp] theorem scanQuotedBody_escaped (delimiter byte : Byte) (rest : List Byte) (offset : Nat) :
    scanQuotedBody delimiter true (byte :: rest) offset = scanQuotedBody delimiter false rest (offset + 1) := by rfl

theorem scanQuotedBody_newline (delimiter byte : Byte) (rest : List Byte) (offset : Nat)
    (isNewline : byte.val = 10) :
    scanQuotedBody delimiter false (byte :: rest) offset = .failure offset := by simp [scanQuotedBody, isNewline]

theorem scanQuotedBody_delimiter (delimiter byte : Byte) (rest : List Byte) (offset : Nat)
    (notNewline : byte.val ≠ 10) (isDelimiter : byte = delimiter) :
    scanQuotedBody delimiter false (byte :: rest) offset = .success (offset + 1) := by
  have delimiterNotNewline : delimiter.val ≠ 10 := by simpa [isDelimiter] using notNewline
  simp [scanQuotedBody, delimiterNotNewline, isDelimiter]

theorem scanQuotedBody_backslash (delimiter byte : Byte) (rest : List Byte) (offset : Nat)
    (_notNewline : byte.val ≠ 10) (notDelimiter : byte ≠ delimiter) (isBackslash : byte.val = 92) :
    scanQuotedBody delimiter false (byte :: rest) offset = scanQuotedBody delimiter true rest (offset + 1) := by
  simp [scanQuotedBody, notDelimiter, isBackslash]

theorem scanQuotedBody_ordinary (delimiter byte : Byte) (rest : List Byte) (offset : Nat)
    (notNewline : byte.val ≠ 10) (notDelimiter : byte ≠ delimiter) (notBackslash : byte.val ≠ 92) :
    scanQuotedBody delimiter false (byte :: rest) offset = scanQuotedBody delimiter false rest (offset + 1) := by
  simp [scanQuotedBody, notNewline, notDelimiter, notBackslash]

theorem scanQuotedBody_source_eof
    (delimiter : Byte) (escaping : Bool) (source : List Byte) (cursor : Nat)
    (outOfBounds : ¬ cursor < source.length) :
    scanQuotedBody delimiter escaping (source.drop cursor) cursor =
      .failure cursor := by
  have bound : source.length ≤ cursor := Nat.le_of_not_gt outOfBounds
  rw [List.drop_eq_nil_of_le bound]
  rfl

theorem scanQuotedBody_cursor_decreases
    (source : List Byte) (cursor : Nat) (inBounds : cursor < source.length) :
    source.length - (cursor + 1) < source.length - cursor := by
  omega

theorem scanQuotedBody_source_result_bounds
    (delimiter : Byte) (escaping : Bool) (source : List Byte) (cursor : Nat)
    (cursorInSource : cursor ≤ source.length) :
    match scanQuotedBody delimiter escaping (source.drop cursor) cursor with
    | .success endOffset | .failure endOffset =>
        cursor ≤ endOffset ∧ endOffset ≤ source.length := by
  have bounds := scanQuotedBody_result_bounds delimiter escaping
    (source.drop cursor) cursor
  cases result : scanQuotedBody delimiter escaping (source.drop cursor) cursor with
  | success endOffset =>
      rw [result] at bounds
      change cursor ≤ endOffset ∧ endOffset ≤ source.length
      simp only [List.length_drop] at bounds
      omega
  | failure errorOffset =>
      rw [result] at bounds
      change cursor ≤ errorOffset ∧ errorOffset ≤ source.length
      simp only [List.length_drop] at bounds
      omega

end Lanius.Compiler.Lexer
