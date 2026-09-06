import Lanius.Extraction.TokenChecker
import Lanius.Extraction.KernelReduction

namespace Lanius.Extraction.TokenCheckerTests
open Lanius.Compiler Lanius.Compiler.Lexer

private def reference (token : Token) : Option RawToken := do
  if token.span.file != 0 then none else
  if token.span.start > token.span.finish then none else
  let kind ← TokenKind.ofGpuCode token.kind
  pure ⟨kind, token.span.start, token.span.finish⟩

theorem decodeToken_eq_reference (token : Token) : decodeToken token = reference token := by
  rcases token with ⟨code, ⟨file, start, finish⟩⟩
  rfl

theorem decodeTokens_eq_reference (tokens : List Token) :
    decodeTokens tokens = tokens.mapM reference := by
  simp only [decodeTokens, show decodeToken = reference from funext decodeToken_eq_reference]

private def casesPass : Bool :=
  decodeToken ⟨1, ⟨0, 3, 5⟩⟩ == some ⟨.identifier, 3, 5⟩ &&
  decodeToken ⟨1, ⟨0, 3, 3⟩⟩ == some ⟨.identifier, 3, 3⟩ &&
  decodeToken ⟨1, ⟨1, 3, 5⟩⟩ == none &&
  decodeToken ⟨1, ⟨0, 5, 3⟩⟩ == none &&
  decodeToken ⟨999, ⟨0, 3, 5⟩⟩ == none
example : casesPass = true := by kernel_rfl
#guard casesPass

-- Compiled comparison exercises all nearby codes, valid/invalid source IDs,
-- and ordered, empty, and reversed spans; the theorem covers all other inputs.
#guard (List.range 200).all fun code =>
  ([0, 1]).all fun file =>
    ([(0, 0), (0, 5), (5, 0), (3, 5)]).all fun (start, finish) =>
      decodeToken ⟨code, ⟨file, start, finish⟩⟩ == reference ⟨code, ⟨file, start, finish⟩⟩

#print axioms decodeToken_eq_reference
#print axioms decodeTokens_eq_reference
end Lanius.Extraction.TokenCheckerTests
