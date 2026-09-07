import Lanius.Extraction.CanonicalTokens.Compaction.Call

namespace Lanius.Extraction.Tests.Compaction

open Lanius.Core Lanius.Semantics Lanius.Compiler Lanius.Compiler.Lexer
open Lanius.Extraction.CanonicalTokens.CanonicalizeModel

private def samples : List (String × List RawToken) := [
  ("", []),
  ("return", [⟨.identifier, 0, 6⟩]),
  (" //x", [⟨.whitespace, 0, 1⟩, ⟨.lineComment, 1, 4⟩]),
  ("..=", [⟨.dotDot, 0, 2⟩, ⟨.assign, 2, 3⟩]),
  (".. =", [⟨.dotDot, 0, 2⟩, ⟨.whitespace, 2, 3⟩, ⟨.assign, 3, 4⟩]),
  ("fn x..=1", [⟨.identifier, 0, 2⟩, ⟨.whitespace, 2, 3⟩, ⟨.identifier, 3, 4⟩,
    ⟨.dotDot, 4, 6⟩, ⟨.assign, 6, 7⟩, ⟨.integer, 7, 8⟩])
]

/-- Regression execution of the actual checked function, not proof evidence.
Distinctive spare words detect writes past the canonical output prefix. -/
def check (program : Program) (function : FunctionId) : IO Unit := do
  for (text, raw) in samples do
    let source : List Byte := text.toUTF8.toList.map fun byte => ⟨byte.toNat, byte.toNat_lt⟩
    let canonical := canonicalizeTokens source raw
    for capacity in [0, 1, 7, 29] do
      let spare := (List.range capacity).map fun index => -(Int.ofNat index + 100)
      let records := encodeTokens raw ++ spare
      let expected := encodeTokens canonical ++ records.drop (3 * canonical.length)
      let before : State := {
        cells := [⟨0, some (.array (signedI32Values (sourceIntegers source)))⟩,
          ⟨1, some (.array (signedI32Values records))⟩]
        nextCell := 2
      }
      match evalExpr 10000 program before (.call function [
          .value (.slice (.scalar (.signed .i32)) 0 [] 0 source.length),
          .value (.slice (.scalar (.signed .i32)) 1 [] 0 records.length),
          .value (.signed .i32 raw.length)]) with
      | .done (.signed .i32 count) after =>
          unless count == (canonical.length : Int) &&
              after.cell? 1 == some (.array (signedI32Values expected)) &&
              after.cell? 0 == before.cell? 0 && after.locals == before.locals do
            throw (IO.userError s!"canonicalization disagrees on {reprStr text}, spare words={capacity}")
      | _ => throw (IO.userError s!"canonicalization did not return on {reprStr text}, spare words={capacity}")

end Lanius.Extraction.Tests.Compaction
