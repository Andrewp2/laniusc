import Lanius.Compiler.LexerStreamOffsets
import Lanius.Extraction.KernelReduction
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.LexerOffsets
open Lanius.Compiler.Lexer

-- A boundary result must not inspect the unconsumed suffix. This checks the
-- reduction contract without a machine-dependent timing assertion.
opaque unknownSuffix : List Byte := []
private theorem stops_without_suffix :
    scanDigitTail 10 (97 :: unknownSuffix) 1 = .success 1 := by kernel_rfl

private theorem symbols_without_suffix :
    matchSymbolHead (60 :: 60 :: 61 :: unknownSuffix) =
      some ⟨[60, 60, 61], .shiftLeftAssign⟩ := by kernel_rfl

private theorem symbol_cases :
    ([([], none), ([0, 255], none), ([60], some .less),
      ([60, 60], some .shiftLeft), ([60, 60, 61], some .shiftLeftAssign),
      ([62, 62, 61, 61], some .shiftRightAssign), ([47, 47], some .lineComment),
      ([47, 42], some .blockComment), ([46, 46, 61], some .dotDot),
      ([61, 62], some .matchArrow), ([59, 97], some .semicolon)].all
      fun (input, kind) => (matchSymbolHead input).map SymbolRule.kind == kind) = true := by
  decide +kernel

private theorem digit_cases :
    ([(10, [], 5, DigitScanResult.success 5),
      (10, [50, 95, 51, 33], 1, .success 4),
      (16, [65, 102, 32], 1, .success 3),
      (2, [50], 1, .success 1),
      (10, [95], 1, .failure 2),
      (10, [95, 120], 1, .failure 2),
      (10, [95, 95], 1, .failure 2)].all fun (base, input, offset, expected) =>
      scanDigitTail base input offset == expected) = true := by decide +kernel

private theorem number_cases :
    (scanNumber ([49, 50, 46, 51, 52, 101, 43, 53, 95, 54, 32, 120] : List Byte) 0 =
      .success .float 10) ∧
    (scanNumber ([49, 50, 46, 46, 51, 52] : List Byte) 0 = .success .integer 2) ∧
    (scanNumber ([48, 120] : List Byte) 0 = .failure 2) ∧
    (scanNumber ([49, 101, 43] : List Byte) 0 = .failure 3) := by decide +kernel

-- Audit the universal bridge used by the source execution proof. No native
-- decision oracle or project-specific axiom may justify scanner equivalence.
run_elab do
  for name in #[``scanOne_eq_scanOneAt, ``scanNumber_offset, ``scanQuotedBody_offset,
      ``scanBlockBody_offset, ``scanDigitTail_spec, ``stops_without_suffix,
      ``digit_cases, ``number_cases, ``startsWith_take, ``bestMatching_take,
      ``matchSymbolHead_eq, ``symbols_without_suffix, ``symbol_cases] do
    for assumption in ← Lean.collectAxioms name do
      unless #[``propext, ``Classical.choice, ``Quot.sound].contains assumption do
        throwError "scanner theorem {name} uses unexpected assumption {assumption}"

end Lanius.Extraction.Tests.LexerOffsets
