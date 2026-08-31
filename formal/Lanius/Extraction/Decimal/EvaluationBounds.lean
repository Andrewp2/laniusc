import Lanius.Compiler.LexerNumbers

namespace Lanius.Extraction.Decimal.EvaluationBounds

open Lanius.Compiler.Lexer

theorem digitTailResult_le
    (scan : DigitTailScan base input offset result) :
    match result with
    | .success finish | .failure finish => finish ≤ offset + input.length := by
  induction scan with
  | eof => simp
  | digit byte rest offset result accepted tail induction =>
      cases result <;> simp_all <;> omega
  | separator underscore next after offset result isSeparator accepted tail
      induction =>
      cases result <;> simp_all <;> omega
  | separatorAtEof => simp
  | separatorBeforeInvalid => simp
  | boundary => simp

theorem digitRunScanResult_bound
    (scan : DigitRunScan source start base result)
    (sourceBound : source.length ≤ 2147483647)
    (startBound : start ≤ 2147483647) :
    match result with
    | .success finish | .failure finish => finish ≤ 2147483647 := by
  cases scan with
  | missing => exact startBound
  | invalid => exact startBound
  | valid first rest result input accepted tail =>
      have lengths := congrArg List.length input
      simp only [List.length_drop, List.length_cons] at lengths
      have resultBound := digitTailResult_le tail
      cases result <;> simp_all <;> omega

theorem digitRunResult_bound
    (sourceBound : source.length ≤ 2147483647)
    (startBound : start ≤ 2147483647) :
    match scanDigitRun source start base with
    | .success finish | .failure finish => finish ≤ 2147483647 := by
  cases resultEq : scanDigitRun source start base with
  | success finish =>
      have scan := scanDigitRun_spec source start base
      rw [resultEq] at scan
      exact digitRunScanResult_bound scan sourceBound startBound
  | failure error =>
      have scan := scanDigitRun_spec source start base
      rw [resultEq] at scan
      exact digitRunScanResult_bound scan sourceBound startBound

end Lanius.Extraction.Decimal.EvaluationBounds
