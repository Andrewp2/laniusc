import Lanius.Semantics
import Lanius.Compiler.LexerCanonical

namespace Lanius.Extraction.Tests.Ascii

open Lanius.Core Lanius.Semantics

def keywords : List String := Compiler.Lexer.keywordRules.map fun rule =>
  String.ofList (rule.spelling.map Char.ofNat)

/-- Run the actual checked helper, including its string-to-word entry, on a
nonzero-offset source span. This is regression execution, not proof evidence. -/
def observes (program : Program) (function : FunctionId) (source : String)
    (spelling : String) (expected : Bool) : Bool := Id.run do
  let bytes := source.toUTF8.toList.map (fun byte => Value.signed .i32 byte.toNat)
  let before : State := {
    cells := [⟨0, some (.array (.signed .i32 33 :: bytes ++ [.signed .i32 33]))⟩]
    nextCell := 1
  }
  let length := spelling.toUTF8.size
  let padded := spelling ++ String.ofList (List.replicate ((4 - length % 4) % 4) '\x00')
  match evalExpr 1000 program before (.call function [
      .value (.slice (.scalar (.signed .i32)) 0 [] 0 (bytes.length + 2)),
      .value (.signed .i32 1), .value (.string padded), .value (.signed .i32 length)]) with
  | .done (.boolean result) after =>
      return result == expected && after.cell? 0 == before.cell? 0
  | _ => return false

def check (program : Program) (function : FunctionId) : IO Unit := do
  for word in "" :: keywords do
    unless observes program function word word true do
      throw (IO.userError s!"ASCII matcher rejected exact spelling {reprStr word}")
    for index in List.range word.length do
      let changed := String.ofList (word.toList.set index '!')
      unless observes program function changed word false do
        throw (IO.userError s!"ASCII matcher failed mismatch at byte {index} of {word}")

/-- Exercise source-owned keyword literals and length dispatch against the
independent lexer specification, including longer identifiers with keyword
prefixes. The helper-only tests cannot detect an unpadded call-site literal. -/
def checkKeywords (program : Program) (function : FunctionId) : IO Unit := do
  let samples := ["", "a", "letter", "fnx", "structural"] ++ keywords ++
    keywords.map (· ++ "x") ++ keywords.map ("x" ++ ·)
  for word in samples do
    let bytes := word.toUTF8.toList.map UInt8.toNat
    let values := bytes.map (fun byte => Value.signed .i32 (Int.ofNat byte))
    let before : State := {
      cells := [⟨0, some (.array (.signed .i32 33 :: values ++ [.signed .i32 33]))⟩]
      nextCell := 1
    }
    let expected := (Compiler.Lexer.exactKeywordKind bytes Compiler.Lexer.keywordRules).getD .identifier
    match evalExpr 1000 program before (.call function [
        .value (.slice (.scalar (.signed .i32)) 0 [] 0 (values.length + 2)),
        .value (.signed .i32 1), .value (.signed .i32 (values.length + 1))]) with
    | .done (.signed .i32 result) after =>
        unless result == (expected.gpuCode : Int) && after.cell? 0 == before.cell? 0 do
          throw (IO.userError s!"keyword dispatch disagrees on {reprStr word}")
    | _ => throw (IO.userError s!"keyword dispatch did not return on {reprStr word}")

end Lanius.Extraction.Tests.Ascii
