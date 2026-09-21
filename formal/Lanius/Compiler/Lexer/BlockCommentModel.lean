import Lean.Elab.Tactic.Omega
import Lanius.Compiler.Lexer

namespace Lanius.Compiler.Lexer

/-! Pure equations for the mathematical block-comment scanner.  These expose
    the branches and well-founded cursor facts used by the ID17 loop proof. -/

@[simp] theorem scanBlockBody_nil (offset : Nat) :
    scanBlockBody [] offset = .failure offset := by
  rfl

@[simp] theorem scanBlockBody_final (byte : Byte) (offset : Nat) :
    scanBlockBody [byte] offset = .failure (offset + 1) := by
  rfl

theorem scanBlockBody_close
    (star slash : Byte) (rest : List Byte) (offset : Nat)
    (isStar : star.val = 42) (isSlash : slash.val = 47) :
    scanBlockBody (star :: slash :: rest) offset = .success (offset + 2) := by
  simp [scanBlockBody, isStar, isSlash]

theorem scanBlockBody_ordinary
    (byte next : Byte) (rest : List Byte) (offset : Nat)
    (notClose : ¬(byte.val = 42 ∧ next.val = 47)) :
    scanBlockBody (byte :: next :: rest) offset =
      scanBlockBody (next :: rest) (offset + 1) := by
  simp [scanBlockBody, notClose]

theorem scanBlockBody_source_spec (source : List Byte) (cursor : Nat) :
    BlockBodyScan (source.drop cursor) cursor
      (scanBlockBody (source.drop cursor) cursor) :=
  scanBlockBody_spec (source.drop cursor) cursor

theorem scanBlockBody_source_eof
    (source : List Byte) (cursor : Nat) (outOfBounds : ¬ cursor < source.length) :
    scanBlockBody (source.drop cursor) cursor = .failure cursor := by
  have bound : source.length ≤ cursor := Nat.le_of_not_gt outOfBounds
  rw [List.drop_eq_nil_of_le bound]
  rfl

theorem scanBlockBody_cursor_decreases
    (source : List Byte) (cursor : Nat) (inBounds : cursor < source.length) :
    source.length - (cursor + 1) < source.length - cursor := by
  omega

theorem scanBlockBody_source_result_bounds
    (source : List Byte) (cursor : Nat)
    (cursorInSource : cursor ≤ source.length) :
    match scanBlockBody (source.drop cursor) cursor with
    | .success endOffset | .failure endOffset =>
        cursor ≤ endOffset ∧ endOffset ≤ source.length := by
  have bounds := scanBlockBody_result_bounds
    (source.drop cursor) cursor
  cases result : scanBlockBody (source.drop cursor) cursor <;>
    simp [result, List.length_drop] at bounds ⊢ <;> omega

end Lanius.Compiler.Lexer
