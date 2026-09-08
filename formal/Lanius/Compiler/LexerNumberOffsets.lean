import Lanius.Compiler.LexerNumbers
import Lanius.Compiler.LexerOffsets
import Std.Tactic

namespace Lanius.Compiler.Lexer

def DigitScanResult.shift (base : Nat) : DigitScanResult → DigitScanResult
  | .success finish => .success (base + finish)
  | .failure error => .failure (base + error)

def NumberScanResult.shift (base : Nat) : NumberScanResult → NumberScanResult
  | .success kind finish => .success kind (base + finish)
  | .failure error => .failure (base + error)

theorem scanDigitTail_offset (radix : Nat) (input : List Byte) (base offset : Nat) :
    scanDigitTail radix input (base + offset) =
      (scanDigitTail radix input offset).shift base := by
  rw [scanDigitTail.eq_def, scanDigitTail.eq_def]
  cases input with
  | nil => rfl
  | cons byte rest =>
      simp only []
      split
      · simpa only [Nat.add_assoc] using scanDigitTail_offset radix rest base (offset + 1)
      · split
        · cases rest with
          | nil => rfl
          | cons next tail =>
              simp only []
              split
              · simpa only [Nat.add_assoc] using scanDigitTail_offset radix tail base (offset + 2)
              · rfl
        · rfl
termination_by input.length

theorem scanDigitRun_offset (source : List Byte) (base start radix : Nat) :
    scanDigitRun source (base + start) radix =
      (scanDigitRun (source.drop base) start radix).shift base := by
  simp only [scanDigitRun, List.drop_drop]
  cases source.drop (base + start) with
  | nil => rfl
  | cons first rest =>
      simp only []
      split
      · simpa only [Nat.add_assoc] using scanDigitTail_offset radix rest base (start + 1)
      · rfl

theorem byteValueAt_offset (source : List Byte) (base start : Nat) :
    byteValueAt source (base + start) = byteValueAt (source.drop base) start := by
  simp [byteValueAt, List.getElem?_drop]

theorem exponentDigitsStart_offset (source : List Byte) (base start : Nat) :
    exponentDigitsStart source (base + start) =
      base + exponentDigitsStart (source.drop base) start := by
  simp only [exponentDigitsStart, Nat.add_assoc, byteValueAt_offset source base]
  split
  · split <;> rfl
  · rfl

theorem scanExponent_offset (source : List Byte) (base start : Nat) :
    scanExponent source (base + start) =
      (scanExponent (source.drop base) start).shift base := by
  simp only [scanExponent, exponentDigitsStart_offset, scanDigitRun_offset]
  cases scanDigitRun (source.drop base) (exponentDigitsStart (source.drop base) start) 10 <;> rfl

theorem finishDecimal_offset (source : List Byte) (base start : Nat) :
    finishDecimal source (base + start) =
      (finishDecimal (source.drop base) start).shift base := by
  simp only [finishDecimal, Nat.add_assoc, byteValueAt_offset source base,
    scanDigitRun_offset source base, scanExponent_offset source base]
  cases digits : scanDigitRun (source.drop base) (start + 1) 10
  all_goals repeat' first
    | simp_all only [Nat.add_assoc, scanDigitRun_offset source base,
        DigitScanResult.shift, NumberScanResult.shift,
        byteValueAt_offset source base, scanExponent_offset source base]
    | split
  all_goals rfl

theorem prefixedBase_offset (source : List Byte) (base start : Nat) :
    prefixedBase source (base + start) = prefixedBase (source.drop base) start := by
  simp only [prefixedBase, Nat.add_assoc, byteValueAt_offset source base]

theorem scanNumber_offset (source : List Byte) (base start : Nat) :
    scanNumber source (base + start) =
      (scanNumber (source.drop base) start).shift base := by
  simp only [scanNumber, prefixedBase_offset, Nat.add_assoc, scanDigitRun_offset source base]
  split
  · rename_i radix found
    cases scanDigitRun (source.drop base) (start + 2) radix <;> rfl
  · cases scanDigitRun (source.drop base) start 10 with
    | failure error => rfl
    | success finish => exact finishDecimal_offset source base finish

theorem scanLeadingDotNumber_offset (source : List Byte) (base start : Nat) :
    scanLeadingDotNumber source (base + start) =
      (scanLeadingDotNumber (source.drop base) start).shift base := by
  simp only [scanLeadingDotNumber, Nat.add_assoc, scanDigitRun_offset source base]
  cases scanDigitRun (source.drop base) (start + 1) 10 with
  | failure error => rfl
  | success finish =>
      simp only [DigitScanResult.shift, byteValueAt_offset source base]
      split
      · split
        · exact scanExponent_offset source base finish
        · rfl
      · rfl

end Lanius.Compiler.Lexer
