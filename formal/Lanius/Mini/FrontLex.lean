import Lanius.Compiler.LexerCanonical
import Lanius.Mini.Frontend
import Lanius.Mini.Compiler

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

/-- `toToken`, from the source's suffix at the token's start. -/
def toTokenAt (suffix : List Byte) (token : RawToken) : Token :=
  { kind := if token.kind = .identifier ∧ tokenBytesFrom suffix token = [97, 115] then 195 else token.kind.gpuCode
    start := token.start
    text := tokenBytesFrom suffix token }

/-- `tokens.map (toToken source)` with a cursor (`rest = source.drop pos`)
through the tokens' starts, so a token's text is not read by walking the
source from its start. Compiled code runs it, by `lexTokens_eq_fast`. -/
def toTokensFrom (source rest : List Byte) (pos : Nat) : List RawToken → List Token
  | [] => []
  | token :: more =>
      let here := dropTo source rest pos token.start
      toTokenAt here token :: toTokensFrom source here token.start more

theorem toTokensFrom_eq (source : List Byte) (tokens : List RawToken) :
    ∀ rest pos, rest = source.drop pos → toTokensFrom source rest pos tokens = tokens.map (toToken source) := by
  induction tokens with
  | nil => intro rest pos _; rfl
  | cons token more inductionHypothesis =>
      intro rest pos at_pos
      rw [toTokensFrom, List.map_cons]
      simp only [dropTo_eq token.start at_pos]
      rw [inductionHypothesis _ _ rfl]
      rfl

set_option linter.unusedVariables false in
def lexTokensFast (source : List Byte) : Option (List Token) :=
  match lexCanonical source with
  | .success tokens => some (toTokensFrom source source 0 tokens)
  | .failure accepted errorOffset => none
  | .fuelExhausted accepted offset => none

@[csimp] theorem lexTokens_eq_fast : @lexTokens = @lexTokensFast := by
  funext source
  unfold lexTokens lexTokensFast
  cases lexCanonical source with
  | success tokens => simp only [toTokensFrom_eq source tokens source 0 List.drop_zero.symm]
  | failure accepted errorOffset => rfl
  | fuelExhausted accepted offset => rfl

/-- The verified compiler's front end: the source program of `source`, given
laniusc's parse tree (its preorder production ids and each node's parent). -/
def sourceProgram (source : List Byte) (prods parents : List Nat) : Option SrcProgram :=
  match lexTokens source with
  | some tokens => frontEnd grammar tokens prods parents
  | none => none

/-- One file of a several-file program: its bytes and laniusc's parse tree. -/
structure SourceFile where
  source : List Byte
  prods : List Nat
  parents : List Nat

set_option linter.unusedVariables false in
/-- Each file's tokens, with its parse tree, if every file lexes. -/
def lexFiles : List SourceFile → Option (List FileInput)
  | [] => some []
  | f :: rest =>
    match lexTokens f.source, lexFiles rest with
    | some tokens, some more => some ({ tokens := tokens, prods := f.prods, parents := f.parents } :: more)
    | some tokens, none => none
    | none, more => none

/-- The verified compiler's front end for several files, each a module, the
program's own first. -/
def sourceProgramFiles (files : List SourceFile) : Option SrcProgram :=
  match lexFiles files with
  | some inputs => frontEndFiles grammar inputs
  | none => none

end Lanius.Mini
