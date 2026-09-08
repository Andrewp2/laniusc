import Lanius.Compiler.LexerNumbers

namespace Lanius.Compiler.Lexer

theorem DigitTailScan.result_end_le
    (scan : DigitTailScan base input offset result) :
    match result with
    | .success finish => finish ≤ offset + input.length
    | .failure error => error ≤ offset + input.length := by
  induction scan with
  | eof => simp
  | digit _ _ _ result _ _ induction => cases result <;> simp_all <;> omega
  | separator _ _ _ _ result _ _ _ induction => cases result <;> simp_all <;> omega
  | separatorAtEof => simp
  | separatorBeforeInvalid => simp
  | boundary => simp

theorem scanDigitRun_success_end_le
    {source : List Byte} {start base finish : Nat}
    (result : scanDigitRun source start base = .success finish) : finish ≤ source.length := by
  have scan := scanDigitRun_spec source start base
  rw [result] at scan
  cases scan with
  | valid first rest result input accepted tail =>
      have bound := tail.result_end_le
      have length := congrArg List.length input
      simp only [List.length_drop, List.length_cons] at length
      simp only [] at bound
      omega

theorem scanExponent_success_end_le
    {source : List Byte} {start finish : Nat} {kind : TokenKind}
    (result : scanExponent source start = .success kind finish) : finish ≤ source.length := by
  unfold scanExponent at result
  cases digits : scanDigitRun source (exponentDigitsStart source start) 10 with
  | failure error => simp [digits] at result
  | success digitEnd =>
      simp only [digits, NumberScanResult.success.injEq] at result
      obtain ⟨rfl, rfl⟩ := result
      exact scanDigitRun_success_end_le digits

theorem byteValueAt_found_lt
    {source : List Byte} {offset byte : Nat}
    (found : byteValueAt source offset = some byte) : offset < source.length := by
  by_cases inside : offset < source.length
  · exact inside
  · simp [byteValueAt, List.getElem?_eq_none (Nat.le_of_not_gt inside)] at found

theorem finishDecimal_success_end_le
    {source : List Byte} {integerEnd finish : Nat} {kind : TokenKind}
    (integerBound : integerEnd ≤ source.length)
    (result : finishDecimal source integerEnd = .success kind finish) : finish ≤ source.length := by
  unfold finishDecimal at result
  repeat' first | contradiction | split at result
  all_goals grind only [→ scanExponent_success_end_le, → scanDigitRun_success_end_le,
    → byteValueAt_found_lt]

theorem scanNumber_success_end_le
    {source : List Byte} {start finish : Nat} {kind : TokenKind}
    (result : scanNumber source start = .success kind finish) : finish ≤ source.length := by
  unfold scanNumber at result
  repeat' first | contradiction | split at result
  all_goals grind only [→ scanDigitRun_success_end_le, → finishDecimal_success_end_le]

theorem scanLeadingDotNumber_success_end_le
    {source : List Byte} {start finish : Nat} {kind : TokenKind}
    (result : scanLeadingDotNumber source start = .success kind finish) : finish ≤ source.length := by
  unfold scanLeadingDotNumber at result
  repeat' first | contradiction | split at result
  all_goals grind only [→ scanDigitRun_success_end_le, → scanExponent_success_end_le]

end Lanius.Compiler.Lexer
