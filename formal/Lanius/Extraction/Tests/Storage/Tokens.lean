import Lanius.Extraction.Entry.Domain.Tokens
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Storage.Tokens
open Lanius.Compiler Lanius.Compiler.Lexer Lanius.Extraction.Frontend

private def artifact (text : String) (tokens : List RawToken) : Artifact := {
  Artifact.empty with
  sources := [{path := "input.lani", bytes := text.toUTF8.toList.map UInt8.toNat}]
  tokens := tokens.map fun token => ⟨token.kind.gpuCode, ⟨0, token.start, token.finish⟩⟩ }

/-- Tiny fixture authentication is deliberately separate from the storage
check. Production callers already have this lexical evidence. -/
private def checkFixture (input : Artifact) (raw canonical kinds : Nat) : Bool :=
  if valid : checkTokenArtifact input = true then
    (checkArtifactTokenStorage? input (checkTokenArtifact_sound valid) raw canonical kinds).isSome
  else false

def check : IO Unit := do
  let cases : List (String × Nat × Nat × Nat) := [
    ("", 0, 0, 0),
    ("abcdefgh", 1, 1, 1),
    ("  abcdefgh  ", 3, 1, 5),
    ("/* many bytes */", 1, 0, 16),
    ("..=", 2, 2, 2),
    ("\"abcdefgh\"", 1, 1, 1),
    ("let x = 12;", 8, 5, 8)]
  let mut boundaries := 0
  for (text, rawCount, tokenCount, expectedBudget) in cases do
    let source := text.toUTF8.toList.map UInt8.toFin
    let .success raw := lexRaw source
      | throw (IO.userError s!"storage fixture lexing failed: {reprStr text}")
    let tokens := canonicalizeTokens source raw
    let budget := rawTokenBudget source.length tokens
    unless raw.length == rawCount && tokens.length == tokenCount && budget == expectedBudget && raw.length ≤ budget do
      throw (IO.userError s!"storage budget/count contract differs: {reprStr text}")
    let input := artifact text tokens
    let exactWords := 3 * budget
    let checks := [(exactWords, exactWords, tokenCount, true),
        (exactWords + 2, exactWords + 2, tokenCount + 1, true)] ++
      (if budget > 0 then [(exactWords - 1, exactWords, tokenCount, false),
        (exactWords, exactWords - 1, tokenCount, false)] else []) ++
      (if tokenCount > 0 then [(exactWords, exactWords, tokenCount - 1, false)] else [])
    for (rawWords, canonicalWords, kindWords, expected) in checks do
      unless checkFixture input rawWords canonicalWords kindWords == expected do
        throw (IO.userError s!"storage acceptance differs: {reprStr text}, capacities={(rawWords, canonicalWords, kindWords)}")
      boundaries := boundaries + 1
    -- Small numeric bounds are not authority to trust a forged span.
    if !input.tokens.isEmpty then
      let forged := {input with tokens := input.tokens.map fun token =>
        {token with span := {token.span with finish := token.span.finish + 1}}}
      if checkFixture forged 65536 65536 65536 then
        throw (IO.userError "storage fixture accepted an unauthenticated token span")
  for text in ["\"unterminated", "/* unterminated"] do
    if checkFixture (artifact text []) 65536 65536 65536 then
      throw (IO.userError "storage fixture admitted lexical failure")
  unless (checkUnitsTokenStorage? 0 0 0 .nil).isSome do
    throw (IO.userError "empty source pack requires token storage")
  IO.println s!"{boundaries} token-storage boundaries passed; trivia, retagging, long tokens, forged spans, and lexical failures covered"

#eval check

run_elab do
  let standard := #[``propext, ``Classical.choice, ``Quot.sound]
  for name in #[``Lexer.RawTokenPrefix.consumed_bytes, ``Lexer.rawTokenBudget_bounds,
      ``Lexer.lexCanonical_raw_budget, ``Frontend.TokenStorage.realizes,
      ``Frontend.SyntaxData.Post.no_token_failure, ``Frontend.checkArtifactTokenStorage?,
      ``Frontend.checkUnitsTokenStorage?, ``Entry.CheckedExecution.checkTokenDomain?,
      ``Entry.File.Resources.token_storage, ``Entry.File.Resources.no_token_failure] do
    for assumption in ← Lean.collectAxioms name do
      unless standard.contains assumption do
        throwError "Token-storage result {name} adds unexpected axiom {assumption}"
  Lean.logInfo "Token-storage bounds, checked-source domain, and file-loop failure exclusion use only standard Lean axioms."

end Lanius.Extraction.Tests.Storage.Tokens
