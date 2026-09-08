import Lanius.Compiler.LexerStream
import Lanius.Compiler.LexerNumberOffsets

namespace Lanius.Compiler.Lexer

theorem tokenFromNumber_offset (base start : Nat) (number : NumberScanResult) :
    tokenFromNumber (base + start) (number.shift base) =
      (tokenFromNumber start number).shift base := by
  cases number <;> rfl

theorem tokenFromDelimited_offset (kind : TokenKind) (base start : Nat) (scan : ScanEnd) :
    tokenFromDelimited kind (base + start) (scan.shift base) =
      (tokenFromDelimited kind start scan).shift base := by
  cases scan <;> rfl

theorem scanFixedSymbol_offset (source : List Byte) (base start : Nat) :
    scanFixedSymbol source (base + start) =
      (scanFixedSymbol (source.drop base) start).shift base := by
  simp only [scanFixedSymbol, List.drop_drop]
  split
  · rfl
  · split
    · simp only [scanLineCommentEnd_offset, OneTokenResult.shift, RawToken.shift]
    · split
      · rw [scanBlockCommentEnd_offset, tokenFromDelimited_offset]
      · simp only [OneTokenResult.shift, RawToken.shift, Nat.add_assoc]

theorem scanSymbol_offset (source : List Byte) (base start : Nat) :
    scanSymbol source (base + start) =
      (scanSymbol (source.drop base) start).shift base := by
  simp only [scanSymbol, List.getElem?_drop, Nat.add_assoc]
  repeat' first
    | rw [scanFixedSymbol_offset]
    | rw [scanLeadingDotNumber_offset, tokenFromNumber_offset]
    | split
  all_goals rfl

theorem scanOneAt_offset (source : List Byte) (base start : Nat) :
    scanOneAt source (base + start) =
      (scanOneAt (source.drop base) start).shift base := by
  simp only [scanOneAt, List.getElem?_drop]
  split
  · rfl
  · split
    · simp only [scanIdentifierEnd_offset, OneTokenResult.shift, RawToken.shift]
    · rw [scanNumber_offset, tokenFromNumber_offset]
    · simp only [scanWhitespaceEnd_offset, OneTokenResult.shift, RawToken.shift]
    · rw [scanQuotedEnd_offset, tokenFromDelimited_offset]
    · rw [scanQuotedEnd_offset, tokenFromDelimited_offset]
    · exact scanSymbol_offset source base start
    · rfl

/-- The optimized suffix scanner has the same success and failure behavior
as the absolute-offset specification used by the Lanius execution proofs. -/
theorem scanOne_eq_scanOneAt (source : List Byte) (start : Nat) :
    scanOne source start = scanOneAt source start := by
  simpa only [scanOne, Nat.add_zero] using (scanOneAt_offset source start 0).symm

end Lanius.Compiler.Lexer
