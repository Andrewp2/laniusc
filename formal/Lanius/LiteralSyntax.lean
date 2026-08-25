import Lanius.SurfaceSyntax

namespace Lanius.Elaboration

private def digitValue? (character : Char) : Option Nat :=
  let code := character.toNat
  if '0'.toNat ≤ code ∧ code ≤ '9'.toNat then
    some (code - '0'.toNat)
  else if 'a'.toNat ≤ code ∧ code ≤ 'f'.toNat then
    some (10 + code - 'a'.toNat)
  else if 'A'.toNat ≤ code ∧ code ≤ 'F'.toNat then
    some (10 + code - 'A'.toNat)
  else
    none

private def parseDigitsLoop (base : Nat) : List Char → Nat → Bool → Option Nat
  | [], value, seen => if seen then some value else none
  | '_' :: rest, value, seen => parseDigitsLoop base rest value seen
  | character :: rest, value, _ => do
      let digit ← digitValue? character
      if digit < base then parseDigitsLoop base rest (value * base + digit) true else none

def parseUnsignedDecimal (text : String) : Option Nat :=
  parseDigitsLoop 10 text.toList 0 false

def parseUnsignedInteger (text : String) : Option Nat :=
  match text.toList with
  | '0' :: 'x' :: rest | '0' :: 'X' :: rest => parseDigitsLoop 16 rest 0 false
  | '0' :: 'b' :: rest | '0' :: 'B' :: rest => parseDigitsLoop 2 rest 0 false
  | '0' :: 'o' :: rest | '0' :: 'O' :: rest => parseDigitsLoop 8 rest 0 false
  | characters => parseDigitsLoop 10 characters 0 false

private def splitAtEither : List Char → Char → Char → Option (List Char × List Char)
  | [], _, _ => none
  | character :: rest, first, second =>
      if character = first ∨ character = second then some ([], rest)
      else
        match splitAtEither rest first second with
        | none => none
        | some (before, after) => some (character :: before, after)

private def splitAtCharacter : List Char → Char → Option (List Char × List Char)
  | [], _ => none
  | character :: rest, target =>
      if character = target then some ([], rest)
      else
        match splitAtCharacter rest target with
        | none => none
        | some (before, after) => some (character :: before, after)

private def parseSignedDecimalChars : List Char → Option Int
  | '-' :: rest => parseDigitsLoop 10 rest 0 false |>.map (fun value => -Int.ofNat value)
  | '+' :: rest => parseDigitsLoop 10 rest 0 false |>.map Int.ofNat
  | characters => parseDigitsLoop 10 characters 0 false |>.map Int.ofNat

/-- Decimal and scientific float syntax is parsed exactly once during
    elaboration. The resulting IEEE rounding is delegated to Lean's specified
    `Float.ofScientific`, then narrowed explicitly for `f32`. -/
def parseFloatLiteral (text : String) : Option Float := do
  let characters := text.toList.filter (fun character => character != '_')
  let (mantissaCharacters, exponent) ←
    match splitAtEither characters 'e' 'E' with
    | none => some (characters, 0)
    | some (mantissa, exponentCharacters) => do
        let exponent ← parseSignedDecimalChars exponentCharacters
        pure (mantissa, exponent)
  let (whole, fractional) :=
    match splitAtCharacter mantissaCharacters '.' with
    | none => (mantissaCharacters, [])
    | some parts => parts
  /- The lexer admits both `1.` and `.5`. Validating the concatenated
     significant digits accepts either spelling while still rejecting `.`. -/
  let mantissa ← parseDigitsLoop 10 (whole ++ fractional) 0 false
  let decimalScale := exponent - Int.ofNat fractional.length
  match decimalScale with
  | .ofNat scale => pure (Float.ofScientific mantissa false scale)
  | .negSucc scale => pure (Float.ofScientific mantissa true (scale + 1))

end Lanius.Elaboration

namespace Lanius.SurfaceSyntax

/-- Literal token classification is supplied by the lexer. This layer owns
    deterministic decoding from that classified token into the surface AST. -/
inductive LiteralTokenKind where
  | integer
  | float
  | string
  | character
  | boolean
deriving DecidableEq

def literalFromToken? : LiteralTokenKind → String → Option Surface.Literal
  | .integer, token => do
      let _ ← Elaboration.parseUnsignedInteger token
      pure (.integer token)
  | .float, token => do
      let _ ← Elaboration.parseFloatLiteral token
      pure (.float token)
  | .string, token => stringLiteralValue? token |>.map .string
  | .character, token => characterLiteralValue? token |>.map .character
  | .boolean, "true" => some (.boolean true)
  | .boolean, "false" => some (.boolean false)
  | .boolean, _ => none

def LiteralTokenSpells
    (kind : LiteralTokenKind) (token : String) (literal : Surface.Literal) : Prop :=
  literalFromToken? kind token = some literal

instance : Decidable (LiteralTokenSpells kind token literal) := by
  unfold LiteralTokenSpells
  infer_instance

theorem LiteralTokenSpells.functional
    (left : LiteralTokenSpells kind token leftLiteral)
    (right : LiteralTokenSpells kind token rightLiteral) :
    leftLiteral = rightLiteral := by
  exact Option.some.inj (left.symm.trans right)

end Lanius.SurfaceSyntax
