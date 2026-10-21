import verified_compiler.tests.direct_ir_body_production_scalar_domain
import Lanius.SurfaceElaboration

namespace IRBodyProductionScalar

open Lanius Lanius.Core Lanius.Semantics
open Lanius.Elaboration (digitValue? parseDigitsLoop)

private def characters (bytes : List Int) : List Char := bytes.map (fun word => Char.ofNat word.toNat)

private theorem digitCode (digit : Nat) (bound : digit < 10) :
    (Char.ofNat (48 + digit)).toNat = 48 + digit := by
  have valid : (48 + digit).isValidChar := Or.inl (by omega)
  simp only [Char.ofNat, dif_pos valid, Char.ofNatAux, Char.toNat]
  rfl

private theorem parseDigit (digit : Nat) (bound : digit < 10) (rest : List Char) (value : Nat) (seen : Bool) :
    parseDigitsLoop 10 (Char.ofNat (48 + digit) :: rest) value seen =
      parseDigitsLoop 10 rest (value * 10 + digit) true := by
  have code := digitCode digit bound
  have other : Char.ofNat (48 + digit) ≠ '_' := by
    intro same
    have equal := congrArg Char.toNat same
    rw [code] at equal
    change 48 + digit = 95 at equal
    omega
  have decoded : digitValue? (Char.ofNat (48 + digit)) = some digit := by
    dsimp only [digitValue?]
    rw [code, if_pos (show '0'.toNat ≤ 48 + digit ∧ 48 + digit ≤ '9'.toNat by
      change 48 ≤ 48 + digit ∧ 48 + digit ≤ 57
      omega)]
    congr 1
    change 48 + digit - 48 = digit
    omega
  simp only [parseDigitsLoop, other, decoded]
  change (if digit < 10 then parseDigitsLoop 10 rest (value * 10 + digit) true else none) = _
  rw [if_pos bound]

/-- Induction on the independent grammar, through the existing parser's actual loop. -/
private theorem DecimalSpelling.parseContinuation (spelled : DecimalSpelling bytes magnitude) (rest : List Char) :
    parseDigitsLoop 10 (characters bytes ++ rest) 0 false = parseDigitsLoop 10 rest magnitude true := by
  induction spelled generalizing rest with
  | digit digit bound =>
      have code : (48 + (digit : Int)).toNat = 48 + digit := by omega
      simp only [characters, List.map_cons, List.map_nil, List.cons_append, List.nil_append, code]
      rw [parseDigit digit bound]
      simp only [Nat.zero_mul, Nat.zero_add]
  | @append bytes value initial digit bound separated ih =>
      have code : (48 + (digit : Int)).toNat = 48 + digit := by omega
      dsimp only [characters] at ih
      cases separated <;> simp only [Bool.false_eq_true, if_false, if_true,
        characters, List.map_append, List.map_cons, List.map_nil, List.nil_append,
        List.cons_append, List.append_nil, List.append_assoc, code]
      · rw [ih, parseDigit digit bound]
      · rw [ih]
        change parseDigitsLoop 10 ('_' :: Char.ofNat (48 + digit) :: rest) value true = _
        rw [parseDigitsLoop, parseDigit digit bound]

private theorem DecimalSpelling.codes (spelled : DecimalSpelling bytes magnitude) :
    ∀ word ∈ bytes, word = 95 ∨ (48 ≤ word ∧ word ≤ 57) := by
  induction spelled with
  | digit digit bound =>
      intro word member
      simp only [List.mem_singleton] at member
      subst word
      right
      omega
  | @append bytes value initial digit bound separated ih =>
      intro word member
      simp only [List.mem_append] at member
      rcases member with (member | member) | member
      · exact ih word member
      · cases separated with
        | false => exact (show False by simpa using member).elim
        | true => exact Or.inl (by simpa using member)
      · simp only [List.mem_singleton] at member
        subst word
        right
        omega

theorem DecimalSpelling.parsedDecimal (spelled : DecimalSpelling (ascii text) magnitude) :
    Elaboration.parseUnsignedDecimal text = some magnitude := by
  have recovered : characters (ascii text) = text.toList := by
    simp [characters, ascii, List.map_map, Function.comp_def]
  have parsed := spelled.parseContinuation []
  simpa only [List.append_nil, recovered, Elaboration.parseUnsignedDecimal, parseDigitsLoop, ite_true] using parsed

/-- Decimal spelling rules out the existing radix dispatch and yields its exact positional value. -/
theorem DecimalSpelling.parsedInteger (spelled : DecimalSpelling (ascii text) magnitude) :
    Elaboration.parseUnsignedInteger text = some magnitude := by
  have decimal := spelled.parsedDecimal
  have allowed (character : Char) (member : character ∈ text.toList) :
      character = '_' ∨ ('0'.toNat ≤ character.toNat ∧ character.toNat ≤ '9'.toNat) := by
    have codes := spelled.codes (character.toNat : Int) (List.mem_map.mpr ⟨character, member, rfl⟩)
    rcases codes with same | range
    · left
      apply Char.toNat_inj.mp
      change character.toNat = 95
      omega
    · right
      change 48 ≤ character.toNat ∧ character.toNat ≤ 57
      omega
  unfold Elaboration.parseUnsignedInteger
  split
  · rename_i rest same
    have bad := allowed 'x' (by rw [same]; simp)
    simp at bad
  · rename_i rest same
    have bad := allowed 'X' (by rw [same]; simp)
    simp at bad
  · rename_i rest same
    have bad := allowed 'b' (by rw [same]; simp)
    simp at bad
  · rename_i rest same
    have bad := allowed 'B' (by rw [same]; simp)
    simp at bad
  · rename_i rest same
    have bad := allowed 'o' (by rw [same]; simp)
    simp at bad
  · rename_i rest same
    have bad := allowed 'O' (by rw [same]; simp)
    simp at bad
  · rename_i chars same
    simpa only [Elaboration.parseUnsignedDecimal, same] using decimal

theorem booleanMeaning (context : SurfaceElaboration.Context) (program : Program) (flag : Bool) :
    SurfaceElaboration.ExprChecks context (.literal (.boolean flag)) (.scalar .bool) (.value (.boolean flag)) ∧
      Typing.ExprHasType program context.coreLocals (.value (.boolean flag)) (.scalar .bool) :=
  ⟨.literal _ .boolean rfl, .value (.boolean flag) rfl⟩

theorem decimalMeaning (context : SurfaceElaboration.Context) (program : Program)
    (spelled : DecimalSpelling (ascii text) magnitude) (bound : magnitude < 2 ^ 31) :
    SurfaceElaboration.ExprChecks context (.literal (.integer text)) (.scalar (.signed .i32))
      (.value (.signed .i32 magnitude)) ∧
      Typing.ExprHasType program context.coreLocals (.value (.signed .i32 magnitude)) (.scalar (.signed .i32)) := by
  have upper : (magnitude : Int) ≤ Typing.signedMax context.target .i32 := by
    change (magnitude : Int) ≤ 2147483647
    omega
  exact ⟨.literal _ (.signedInteger spelled.parsedInteger upper) rfl,
    .value (.signed _ _ (by change (-2147483648 : Int) ≤ magnitude; omega)
      (by change (magnitude : Int) ≤ 2147483647; omega)) rfl⟩

theorem negativeMeaning (context : SurfaceElaboration.Context) (program : Program)
    (spelled : DecimalSpelling (ascii text) magnitude) (bound : magnitude ≤ 2 ^ 31) :
    let expression := if magnitude < 2 ^ 31 then .unary .negate (.value (.signed .i32 magnitude))
      else (.value (.signed .i32 (-2147483648)) : Expr)
    SurfaceElaboration.ExprChecks context (.unary .negative (.literal (.integer text))) (.scalar (.signed .i32)) expression ∧
      Typing.ExprHasType program context.coreLocals expression (.scalar (.signed .i32)) := by
  dsimp only
  by_cases ordinary : magnitude < 2 ^ 31
  · rw [if_pos ordinary]
    have literal := decimalMeaning context program spelled ordinary
    have upper : (magnitude : Int) ≤ Typing.signedMax context.target .i32 := by
      change (magnitude : Int) ≤ 2147483647
      omega
    exact ⟨.unaryLiteral (.signedInteger spelled.parsedInteger upper) rfl (.negate (.signed .i32)),
      .unary literal.2 (.negate (.signed .i32))⟩
  · rw [if_neg ordinary]
    have minimum : (magnitude : Int) = -(Typing.signedMin context.target .i32) := by
      change (magnitude : Int) = 2147483648
      omega
    exact ⟨.signedMinimumLiteral (.minimum spelled.parsedInteger minimum) rfl,
      .value (.signed _ _ (by change (-2147483648 : Int) ≤ -2147483648; omega)
        (by change (-2147483648 : Int) ≤ 2147483647; omega)) rfl⟩

#print axioms DecimalSpelling.parsedDecimal
#print axioms DecimalSpelling.parsedInteger
#print axioms booleanMeaning
#print axioms decimalMeaning
#print axioms negativeMeaning

end IRBodyProductionScalar
