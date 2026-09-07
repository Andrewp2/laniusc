import Lanius.Extraction.CanonicalTokens.Dispatch.Checked

namespace Lanius.Extraction.Tests.Dispatch

open Lanius.Core Lanius.Compiler Lanius.Compiler.Lexer
open Lanius.Extraction.CanonicalTokens Lanius.Extraction.CanonicalTokens.Dispatch

private def constant (id : Nat) (value : Int) : Constant :=
  ⟨id, .scalar (.signed .i32), .signed .i32 value⟩

private def program : Program := {
  constants := constant 1 1 :: keywordRules.map (fun rule => constant rule.kind.gpuCode rule.kind.gpuCode)
  functions := [Ascii.sourceFunction 0]
}

private def paddedText (spelling : List Nat) : String :=
  String.ofList (spelling.map Char.ofNat ++ List.replicate ((4 - spelling.length % 4) % 4) '\x00')

private def groups : List Group := [2, 3, 4, 5, 6, 8].map fun width =>
  ⟨width, (keywordRules.filter (fun rule => rule.spelling.length == width)).map
    (fun rule => ⟨paddedText rule.spelling, rule.kind.gpuCode⟩)⟩

example : (check? program 0 (body 0 1 groups)).isSome = true := by native_decide

-- Rule order is not semantic; the independent reference table is a permutation.
example : (check? program 0 (body 0 1 groups.reverse)).isSome = true := by native_decide

-- Reject changing the selected callee or a callee body, not just table entries.
example : (check? program 0 (body 1 1 groups)).isSome = false := by native_decide
example : (check? { program with functions := [{ Ascii.sourceFunction 0 with body := some .skip }] }
    0 (body 0 1 groups)).isSome = false := by native_decide

-- Short strings must not acquire implicit readable word padding.
example : (checkGroups? program [⟨2, [⟨"fn", 67⟩]⟩]).isSome = false := by native_decide

-- Padding contents are irrelevant; only bytes inside the spelling are compared.
example : (checkGroups? program [⟨2, [⟨"fn!!", 67⟩]⟩]).isSome = true := by native_decide

-- The exact table rejects missing/duplicated rules and incorrect token values.
example : (check? program 0 (body 0 1 (groups.drop 1))).isSome = false := by native_decide
example : (check? program 0 (body 0 1 (groups ++ groups))).isSome = false := by native_decide
example : (check? { program with
    constants := program.constants.map (fun entry => if entry.id == 67 then constant 67 68 else entry) }
    0 (body 0 1 groups)).isSome = false := by native_decide
example : (check? program 0 (body 0 67 groups)).isSome = false := by native_decide

end Lanius.Extraction.Tests.Dispatch
