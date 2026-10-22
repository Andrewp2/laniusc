import Lanius.Compiler.LexerCanonical
import Lanius.Mini.Frontend

/-! The tokens the front end validates against: the Lean lexer's
(`Lanius.Compiler.Lexer.lexCanonical`), as `Token`s with laniusc's token kind
codes, and the front end from source bytes and laniusc's parse tree. -/

namespace Lanius.Mini

open Lanius.Compiler Lanius.Compiler.Lexer

/-- laniusc's lexer reads the identifier `as` as the cast keyword (token code
195); `keywordRules` does not have it yet, so it is added here. -/
def tokenCode (source : List Byte) (token : RawToken) : Nat :=
  if token.kind = .identifier ∧ tokenByteValues source token = [97, 115] then 195
  else token.kind.gpuCode

def toToken (source : List Byte) (token : RawToken) : Token :=
  { kind := tokenCode source token, start := token.start, text := tokenByteValues source token }

set_option linter.unusedVariables false in
/-- The token stream of a source file, if it lexes. -/
def lexTokens (source : List Byte) : Option (List Token) :=
  match lexCanonical source with
  | .success tokens => some (tokens.map (toToken source))
  | .failure accepted errorOffset => none
  | .fuelExhausted accepted offset => none

/-- The verified compiler's front end: the source program of `source`, given
laniusc's parse tree (its preorder production ids and each node's parent). -/
def sourceProgram (source : List Byte) (prods parents : List Nat) : Option SrcProgram :=
  match lexTokens source with
  | some tokens => frontEnd grammar tokens prods parents
  | none => none

end Lanius.Mini
