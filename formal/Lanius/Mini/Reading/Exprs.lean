import Lanius.Mini.Reading.Types

/-! # The reading, V8c: expressions and literals

`ExprR env scope c e`: the node `c` of the expression grammar, read where
`env` says with the locals `scope` (innermost first), denotes the source
expression `e`. Binary operators and casts apply left to right; a name is a
local, or else a constant, which denotes its value: a literal of its
declared type (`ConstValue`).

A constant's value may have two readings: the literal reading, and, when
its tokens are `n` or `-` and `n`, the wide one (`WideConst`), which the
builder uses when the literal reading fails (`n` of 2^31 or more). Where
both apply they denote the same value: the relation does not say that the
literal reading is tried first, since that is a negative condition on the
relation itself. -/

namespace Lanius.Mini.Reading

open Lanius.Mini Lanius.Mini.Prod

/-! ## Integer literals -/

/-- Decimal digits. -/
def Digits (text : List Nat) : Prop := ∀ b ∈ text, 48 ≤ b ∧ b ≤ 57

/-- The value of decimal digits read after `acc`. -/
def digitsFrom (acc : Nat) (text : List Nat) : Nat := text.foldl (fun a b => a * 10 + (b - 48)) acc

def digitsValue (text : List Nat) : Nat := digitsFrom 0 text

theorem digitsFrom_ge : ∀ (acc : Nat) (text : List Nat), acc ≤ digitsFrom acc text
  | _, [] => Nat.le_refl _
  | acc, b :: rest => Nat.le_trans (by omega) (digitsFrom_ge (acc * 10 + (b - 48)) rest)

theorem decimal_sound : ∀ (text : List Nat) (acc n : Nat), decimal text acc = some n →
    Digits text ∧ n = digitsFrom acc text ∧ n ≤ 2147483647
  | [], acc, n, h => by
    rw [decimal.eq_def] at h
    by_cases big : 2147483647 < acc
    · rw [if_pos big] at h; cases h
    · rw [if_neg big] at h
      cases h
      exact ⟨by simp [Digits], rfl, by omega⟩
  | b :: rest, acc, n, h => by
    rw [decimal.eq_def] at h
    by_cases big : 2147483647 < acc
    · rw [if_pos big] at h; cases h
    · rw [if_neg big] at h
      simp only at h
      by_cases dig : 48 ≤ b ∧ b ≤ 57
      · rw [if_pos (by simpa using dig)] at h
        obtain ⟨ds, rfl, le⟩ := decimal_sound rest _ n h
        exact ⟨fun x mem => by
          rcases List.mem_cons.1 mem with rfl | mem
          · exact dig
          · exact ds x mem, rfl, le⟩
      · rw [if_neg (by simpa using dig)] at h; cases h

theorem decimal_complete : ∀ (text : List Nat) (acc : Nat), Digits text → digitsFrom acc text ≤ 2147483647 →
    decimal text acc = some (digitsFrom acc text)
  | [], acc, _, le => by
    rw [decimal.eq_def, if_neg (by simp only [digitsFrom, List.foldl] at le; omega)]
    rfl
  | b :: rest, acc, ds, le => by
    have ge := digitsFrom_ge (acc * 10 + (b - 48)) rest
    have e : digitsFrom acc (b :: rest) = digitsFrom (acc * 10 + (b - 48)) rest := rfl
    rw [e] at le ⊢
    rw [decimal.eq_def, if_neg (by omega)]
    simp only
    rw [if_pos (by simpa using ds b (by simp))]
    exact decimal_complete rest _ (fun x mem => ds x (List.mem_cons_of_mem _ mem)) le

theorem wideDecimal_sound : ∀ (text : List Nat) (acc n : Nat), wideDecimal text acc = some n →
    Digits text ∧ n = digitsFrom acc text ∧ n ≤ 18446744073709551615
  | [], acc, n, h => by
    rw [wideDecimal.eq_def] at h
    by_cases big : 18446744073709551615 < acc
    · rw [if_pos big] at h; cases h
    · rw [if_neg big] at h
      cases h
      exact ⟨by simp [Digits], rfl, by omega⟩
  | b :: rest, acc, n, h => by
    rw [wideDecimal.eq_def] at h
    by_cases big : 18446744073709551615 < acc
    · rw [if_pos big] at h; cases h
    · rw [if_neg big] at h
      simp only at h
      by_cases dig : 48 ≤ b ∧ b ≤ 57
      · rw [if_pos (by simpa using dig)] at h
        obtain ⟨ds, rfl, le⟩ := wideDecimal_sound rest _ n h
        exact ⟨fun x mem => by
          rcases List.mem_cons.1 mem with rfl | mem
          · exact dig
          · exact ds x mem, rfl, le⟩
      · rw [if_neg (by simpa using dig)] at h; cases h

/-- An integer literal: below 2^31 it is an `i32` literal; from 2^31 to
2^64 it is the wide marker, `Cast(Unit, Unsigned(u64, n))`, which only a
constant's or a typed context's literal pass gives a type. -/
inductive IntLiteral (text : List Nat) : SrcExpr → Prop
  | small : Digits text → digitsValue text < 2 ^ 31 → IntLiteral text (.int (BitVec.ofNat 32 (digitsValue text)))
  | wide : Digits text → 2 ^ 31 ≤ digitsValue text → digitsValue text < 2 ^ 64 →
      IntLiteral text (.cast .unit (.unsigned .uint64 (BitVec.ofNat 64 (digitsValue text))))

theorem intLiteral_sound {text : List Nat} {e : SrcExpr} (h : intLiteral text = some e) : IntLiteral text e := by
  unfold intLiteral at h
  cases hd : decimal text 0 with
  | some v =>
    rw [hd] at h
    simp only at h
    obtain ⟨ds, rfl, le⟩ := decimal_sound text 0 v hd
    rw [if_pos le, Option.some.injEq] at h
    subst h
    exact .small ds (by unfold digitsValue; omega)
  | none =>
    rw [hd] at h
    simp only [wideMarker] at h
    cases hw : wideDecimal text 0 with
    | none => rw [hw] at h; cases h
    | some n =>
      rw [hw, Option.some.injEq] at h
      subst h
      obtain ⟨ds, rfl, le⟩ := wideDecimal_sound text 0 n hw
      refine .wide ds ?_ (by unfold digitsValue; omega)
      apply Nat.le_of_not_lt
      intro lt
      rw [decimal_complete text 0 ds (by unfold digitsValue at lt; omega)] at hd
      cases hd

/-! ## Char literals -/

/-- The UTF-8 encoding of a code point. -/
def utf8Encode (c : Nat) : List Nat :=
  if c < 128 then [c]
  else if c < 2048 then [192 + c / 64, 128 + c % 64]
  else if c < 65536 then [224 + c / 4096, 128 + c / 64 % 64, 128 + c % 64]
  else [240 + c / 262144, 128 + c / 4096 % 64, 128 + c / 64 % 64, 128 + c % 64]

/-- A Unicode scalar value: a code point that is not a surrogate. -/
def ScalarValue (c : Nat) : Prop := c < 1114112 ∧ ¬(55296 ≤ c ∧ c < 57344)

/-- The escapes `\n \r \t \0 \' \" \\`: the byte after the backslash and
the code it stands for. -/
inductive Escape : Nat → Nat → Prop
  | newline : Escape 110 10
  | ret : Escape 114 13
  | tab : Escape 116 9
  | zero : Escape 48 0
  | quote : Escape 39 39
  | dquote : Escape 34 34
  | backslash : Escape 92 92

/-- A char literal's text, its quotes included, and its code: the UTF-8
encoding of a scalar value other than the quote, backslash and newline, or
an escape. -/
inductive CharLiteral : List Nat → Nat → Prop
  | plain {c : Nat} : ScalarValue c → c ≠ 39 → c ≠ 92 → c ≠ 10 → CharLiteral (39 :: utf8Encode c ++ [39]) c
  | escape {e c : Nat} : Escape e c → CharLiteral [39, 92, e, 39] c

theorem charClose_some {code : Nat} {rest : List Nat} {e : SrcExpr} (h : charClose code rest = some e) :
    rest = [39] ∧ e = .char (BitVec.ofNat 32 code) := by
  cases rest with
  | nil => cases h
  | cons q more =>
    simp only [charClose] at h
    by_cases hq : q = 39
    · subst hq
      cases more with
      | nil => simp only [if_pos, Option.some.injEq] at h; exact ⟨rfl, h.symm⟩
      | cons _ _ => simp at h
    · rw [if_neg hq] at h; cases h

theorem charTail0 {rest : List Nat} {code lo hi : Nat} {e : SrcExpr} (h : charTail rest 0 code lo hi = some e) :
    ∃ b, rest = [b, 39] ∧ lo ≤ b ∧ b ≤ hi ∧ e = .char (BitVec.ofNat 32 (code * 64 + (b - 128))) := by
  unfold charTail at h
  split at h
  · cases h
  · rename_i b rest
    split at h
    · rename_i range
      simp only [Bool.and_eq_true, decide_eq_true_eq] at range
      simp only [if_pos] at h
      obtain ⟨rfl, rfl⟩ := charClose_some h
      exact ⟨b, rfl, range.1, range.2, rfl⟩
    · cases h

theorem charTail1 {rest : List Nat} {code lo hi : Nat} {e : SrcExpr} (h : charTail rest 1 code lo hi = some e) :
    ∃ b c, rest = [b, c, 39] ∧ lo ≤ b ∧ b ≤ hi ∧ 128 ≤ c ∧ c ≤ 191 ∧
      e = .char (BitVec.ofNat 32 ((code * 64 + (b - 128)) * 64 + (c - 128))) := by
  unfold charTail at h
  split at h
  · cases h
  · rename_i b rest
    split at h
    · rename_i range
      simp only [Bool.and_eq_true, decide_eq_true_eq] at range
      simp only [Nat.one_ne_zero, if_false, Nat.sub_self] at h
      obtain ⟨c, rfl, lc, hc, rfl⟩ := charTail0 h
      exact ⟨b, c, rfl, range.1, range.2, lc, hc, rfl⟩
    · cases h

theorem charTail2 {rest : List Nat} {code lo hi : Nat} {e : SrcExpr} (h : charTail rest 2 code lo hi = some e) :
    ∃ b c d, rest = [b, c, d, 39] ∧ lo ≤ b ∧ b ≤ hi ∧ 128 ≤ c ∧ c ≤ 191 ∧ 128 ≤ d ∧ d ≤ 191 ∧
      e = .char (BitVec.ofNat 32 (((code * 64 + (b - 128)) * 64 + (c - 128)) * 64 + (d - 128))) := by
  unfold charTail at h
  split at h
  · cases h
  · rename_i b rest
    split at h
    · rename_i range
      simp only [Bool.and_eq_true, decide_eq_true_eq] at range
      simp only [show (2 : Nat) ≠ 0 from by decide, if_false, show (2 : Nat) - 1 = 1 from rfl] at h
      obtain ⟨c, d, rfl, lc, hc, ld, hd, rfl⟩ := charTail1 h
      exact ⟨b, c, d, rfl, range.1, range.2, lc, hc, ld, hd, rfl⟩
    · cases h

theorem escapedByte_some {e c : Nat} (h : escapedByte e = some c) : Escape e c := by
  unfold escapedByte at h
  by_cases h1 : e = 110
  · subst h1; cases h; exact .newline
  rw [if_neg h1] at h
  by_cases h2 : e = 114
  · subst h2; cases h; exact .ret
  rw [if_neg h2] at h
  by_cases h3 : e = 116
  · subst h3; cases h; exact .tab
  rw [if_neg h3] at h
  by_cases h4 : e = 48
  · subst h4; cases h; exact .zero
  rw [if_neg h4] at h
  split at h
  · rename_i q
    simp only [Bool.or_eq_true, decide_eq_true_eq] at q
    simp only [Option.some.injEq] at h
    subst h
    rcases q with (rfl | rfl) | rfl
    · exact .quote
    · exact .dquote
    · exact .backslash
  · cases h

theorem exists_char {P : Nat → Prop} {n : Nat} (p : P n) :
    ∃ m, P m ∧ SrcExpr.char (BitVec.ofNat 32 n) = .char (BitVec.ofNat 32 m) := ⟨n, p, rfl⟩

theorem charLiteral_sound {text : List Nat} {e : SrcExpr} (h : charLiteral text = some e) :
    ∃ n, CharLiteral text n ∧ e = .char (BitVec.ofNat 32 n) := by
  unfold charLiteral at h
  split at h
  · cases h
  rename_i q rest
  split at h
  rotate_left
  · cases h
  rename_i hq
  subst hq
  unfold charBody at h
  split at h
  · cases h
  rename_i b rest
  by_cases bs : b = 92
  · subst bs
    rw [if_pos rfl] at h
    split at h
    · cases h
    rename_i x rest
    simp only [charCloseOpt] at h
    split at h
    · cases h
    rename_i c hc
    obtain ⟨rfl, rfl⟩ := charClose_some h
    exact ⟨c, .escape (escapedByte_some hc), rfl⟩
  rw [if_neg bs] at h
  split at h
  · cases h
  rename_i nq
  simp only [Bool.or_eq_true, decide_eq_true_eq, not_or] at nq
  by_cases ascii : b < 128
  · rw [if_pos ascii] at h
    obtain ⟨rfl, rfl⟩ := charClose_some h
    refine ⟨b, ?_, rfl⟩
    have := CharLiteral.plain (c := b) ⟨by omega, by omega⟩ nq.1 bs nq.2
    simpa [utf8Encode, ascii] using this
  rw [if_neg ascii] at h
  have plain : ∀ {c : Nat} {rest : List Nat}, ScalarValue c → 128 ≤ c → b :: rest = utf8Encode c ++ [39] →
      CharLiteral (39 :: b :: rest) c := by
    intro c rest sv big enc
    have := CharLiteral.plain sv (by omega) (by omega) (by omega)
    rw [List.cons_append, ← enc] at this
    exact this
  split at h
  · rename_i r
    simp only [Bool.and_eq_true, decide_eq_true_eq] at r
    obtain ⟨x, rfl, lx, hx, rfl⟩ := charTail0 h
    apply exists_char
    apply plain
    · exact ⟨by omega, by omega⟩
    · omega
    simp only [utf8Encode]
    rw [if_neg (by omega), if_pos (by omega)]
    simp only [List.cons_append, List.nil_append, List.cons.injEq, and_true]
    omega
  split at h
  · rename_i r
    subst r
    obtain ⟨x, y, rfl, lx, hx, ly, hy, rfl⟩ := charTail1 h
    apply exists_char
    apply plain
    · exact ⟨by omega, by omega⟩
    · omega
    simp only [utf8Encode]
    rw [if_neg (by omega), if_neg (by omega), if_pos (by omega)]
    simp only [List.cons_append, List.nil_append, List.cons.injEq, and_true]
    omega
  split at h
  · rename_i r
    subst r
    obtain ⟨x, y, rfl, lx, hx, ly, hy, rfl⟩ := charTail1 h
    apply exists_char
    apply plain
    · exact ⟨by omega, by omega⟩
    · omega
    simp only [utf8Encode]
    rw [if_neg (by omega), if_neg (by omega), if_pos (by omega)]
    simp only [List.cons_append, List.nil_append, List.cons.injEq, and_true]
    omega
  split at h
  · rename_i r
    simp only [Bool.and_eq_true, decide_eq_true_eq] at r
    obtain ⟨x, y, rfl, lx, hx, ly, hy, rfl⟩ := charTail1 h
    apply exists_char
    apply plain
    · exact ⟨by omega, by omega⟩
    · omega
    simp only [utf8Encode]
    rw [if_neg (by omega), if_neg (by omega), if_pos (by omega)]
    simp only [List.cons_append, List.nil_append, List.cons.injEq, and_true]
    omega
  split at h
  · rename_i r
    subst r
    obtain ⟨x, y, z, rfl, lx, hx, ly, hy, lz, hz, rfl⟩ := charTail2 h
    apply exists_char
    apply plain
    · exact ⟨by omega, by omega⟩
    · omega
    simp only [utf8Encode]
    rw [if_neg (by omega), if_neg (by omega), if_neg (by omega)]
    simp only [List.cons_append, List.nil_append, List.cons.injEq, and_true]
    omega
  split at h
  · rename_i r
    subst r
    obtain ⟨x, y, z, rfl, lx, hx, ly, hy, lz, hz, rfl⟩ := charTail2 h
    apply exists_char
    apply plain
    · exact ⟨by omega, by omega⟩
    · omega
    simp only [utf8Encode]
    rw [if_neg (by omega), if_neg (by omega), if_neg (by omega)]
    simp only [List.cons_append, List.nil_append, List.cons.injEq, and_true]
    omega
  split at h
  · rename_i r
    simp only [Bool.and_eq_true, decide_eq_true_eq] at r
    obtain ⟨x, y, z, rfl, lx, hx, ly, hy, lz, hz, rfl⟩ := charTail2 h
    apply exists_char
    apply plain
    · exact ⟨by omega, by omega⟩
    · omega
    simp only [utf8Encode]
    rw [if_neg (by omega), if_neg (by omega), if_neg (by omega)]
    simp only [List.cons_append, List.nil_append, List.cons.injEq, and_true]
    omega
  · cases h

/-! ## Typed literals -/

/-- The width of an unsigned type. -/
def uintBits : UintTy → Nat
  | .uint8 => 8
  | .uint32 => 32
  | .uint64 => 64
  | .usize => 64
  | .uint16 => 16

theorem uintInRange_some {u : UintTy} {v : BitVec 64} {e : SrcExpr} (h : uintInRange u v = some e) :
    v.toNat < 2 ^ uintBits u ∧ e = .unsigned u v := by
  unfold uintInRange at h
  by_cases le : v ≤ uintMask u
  · rw [if_pos le, Option.some.injEq] at h
    refine ⟨?_, h.symm⟩
    have := BitVec.le_def.1 le
    have lt := v.isLt
    cases u <;> simp [uintMask, uintBits] at this ⊢ <;> omega
  · rw [if_neg le] at h; cases h

/-- An `i32` value in the range of the signed type as wide as `u`. -/
def SintFits (u : UintTy) (k : BitVec 32) : Prop :=
  32 ≤ uintBits u ∨ (-2 ^ (uintBits u - 1) ≤ k.toInt ∧ k.toInt < 2 ^ (uintBits u - 1))

theorem sintFits_iff (u : UintTy) (k : BitVec 32) : sintFits u k = true ↔ SintFits u k := by
  have := k.isLt
  cases u <;> simp only [sintFits, SintFits, uintBits, Bool.or_eq_true, decide_eq_true_eq, BitVec.le_def,
    BitVec.toInt_eq_toNat_cond, true_iff] <;>
    first | exact .inl (by decide) | skip
  all_goals split <;> omega

/-- A constant's value as a literal of its type: an `i32` literal (or its
negation) of `i32`, of `isize` (cast), of an unsigned type when it fits, `0`
of `ptr` (the null pointer), `true` or `false` of `bool`, and of a signed
type the cast of the `i32` literal (or of its negation) when the type holds it. -/
inductive TypedLiteral : Ty → SrcExpr → SrcExpr → Prop
  | i32 {k : BitVec 32} : TypedLiteral .tyI32 (.int k) (.int k)
  | uint {u : UintTy} {k : BitVec 32} : k.toNat < 2 ^ uintBits u →
      TypedLiteral (.tyUint u) (.int k) (.unsigned u (k.setWidth 64))
  | null : TypedLiteral .tyPtr (.int 0) .null
  | isize {k : BitVec 32} : TypedLiteral .tyIsize (.int k) (.cast .isize (.int k))
  | bool {b : Bool} : TypedLiteral .tyBool (.boolean b) (.boolean b)
  | negI32 {k : BitVec 32} : TypedLiteral .tyI32 (.negate (.int k)) (.negate (.int k))
  | negIsize {k : BitVec 32} : TypedLiteral .tyIsize (.negate (.int k)) (.negate (.cast .isize (.int k)))
  | sint {u : UintTy} {k : BitVec 32} : SintFits u k → TypedLiteral (.tySint u) (.int k) (.cast (.sint u) (.int k))
  | negSint {u : UintTy} {k : BitVec 32} : SintFits u (0 - k) →
      TypedLiteral (.tySint u) (.negate (.int k)) (.cast (.sint u) (.int (0 - k)))
  | char {c : BitVec 32} : TypedLiteral .tyChar (.char c) (.char c)

theorem typedLiteral_sound {t : Ty} {v e : SrcExpr} (h : typedLiteral t v = some e) : TypedLiteral t v e := by
  cases v with
  | int k =>
    cases t with
    | tyI32 => cases h; exact .i32
    | tyUint u =>
      obtain ⟨lt, rfl⟩ := uintInRange_some h
      have small : k.toNat < 2 ^ 64 := by have := k.isLt; omega
      exact .uint (by simpa [BitVec.toNat_setWidth, Nat.mod_eq_of_lt small] using lt)
    | tyPtr =>
      simp only [typedLiteral, nullConst] at h
      by_cases z : k = 0
      · subst z
        rw [if_pos rfl, Option.some.injEq] at h
        subst h
        exact .null
      · rw [if_neg z] at h; cases h
    | tyIsize => cases h; exact .isize
    | tyChar => cases h
    | tyBool => cases h
    | tySlice _ => cases h
    | tyNamed _ _ => cases h
    | tySint u =>
      simp only [typedLiteral, sintConst] at h
      by_cases f : sintFits u k = true
      · rw [if_pos f, Option.some.injEq] at h
        subst h
        exact .sint ((sintFits_iff u k).1 f)
      · rw [if_neg f] at h; cases h
  | boolean b =>
    cases t with
    | tyBool => cases h; exact .bool
    | tyI32 => cases h
    | tyUint _ => cases h
    | tyPtr => cases h
    | tyIsize => cases h
    | tyChar => cases h
    | tySlice _ => cases h
    | tyNamed _ _ => cases h
    | tySint _ => cases h
  | negate x =>
    cases t with
    | tyI32 =>
      cases x <;> simp [typedLiteral, negatedInt] at h
      subst h
      exact .negI32
    | tyIsize =>
      cases x <;> simp [typedLiteral, negatedInt] at h
      subst h
      exact .negIsize
    | tyBool => cases h
    | tyChar => cases h
    | tyUint _ => cases h
    | tyPtr => cases h
    | tySlice _ => cases h
    | tyNamed _ _ => cases h
    | tySint u =>
      cases x
      case int k =>
        simp only [typedLiteral, negSintConst, sintConst] at h
        by_cases f : sintFits u (0 - k) = true
        · rw [if_pos f, Option.some.injEq] at h
          subst h
          exact .negSint ((sintFits_iff u _).1 f)
        · rw [if_neg f] at h; cases h
      all_goals simp [typedLiteral, negSintConst] at h
  | unsigned _ _ => cases h
  | «local» _ => cases h
  | field _ _ => cases h
  | not _ => cases h
  | apply _ _ _ => cases h
  | cast _ _ => cases h
  | null => cases h
  | char c =>
    cases t <;> simp only [typedLiteral, reduceCtorEq, Option.some.injEq] at h
    subst h
    exact .char

/-- A wide literal `n` (or `-n`, `negative`) as a literal of a type:
`-2^31` of `i32`, `n` of an unsigned type when it fits, and for `isize`
the `u64` literal holding its two's complement bits. -/
inductive WideOf : Ty → Bool → Nat → SrcExpr → Prop
  | i32 : WideOf .tyI32 true (2 ^ 31) (.int (BitVec.ofNat 32 (2 ^ 31)))
  | uint {u : UintTy} {n : Nat} : n < 2 ^ uintBits u → WideOf (.tyUint u) false n (.unsigned u (BitVec.ofNat 64 n))
  | isize {n : Nat} : n < 2 ^ 63 → WideOf .tyIsize false n (.cast .isize (.unsigned .uint64 (BitVec.ofNat 64 n)))
  | isizeNeg {n : Nat} : n ≤ 2 ^ 63 →
      WideOf .tyIsize true n (.cast .isize (.unsigned .uint64 (BitVec.ofNat 64 (2 ^ 64 - n))))
  | sint {u : UintTy} {n : Nat} : uintBits u = 64 → n < 2 ^ 63 →
      WideOf (.tySint u) false n (.cast (.sint u) (.unsigned .uint64 (BitVec.ofNat 64 n)))
  | sintNeg {u : UintTy} {n : Nat} : uintBits u = 64 → n ≤ 2 ^ 63 →
      WideOf (.tySint u) true n (.cast (.sint u) (.unsigned .uint64 (BitVec.ofNat 64 (2 ^ 64 - n))))

/-- A constant's value tokens `n` or `-` `n` as a wide literal. -/
inductive WideConst (t : Ty) : List Token → SrcExpr → Prop
  | pos {a : Token} {e : SrcExpr} : Digits a.text → digitsValue a.text < 2 ^ 64 →
      WideOf t false (digitsValue a.text) e → WideConst t [a] e
  | neg {a b : Token} {e : SrcExpr} : a.text = [45] → Digits b.text → digitsValue b.text < 2 ^ 64 →
      WideOf t true (digitsValue b.text) e → WideConst t [a, b] e

theorem wideOf_sound {t : Ty} {negative : Bool} {n : Nat} {e : SrcExpr} (h : wideOf t negative n = some e) :
    WideOf t negative n e := by
  cases t with
  | tyI32 =>
    simp only [wideOf, wideI32] at h
    by_cases c : negative = true ∧ n = 2147483648
    · obtain ⟨rfl, rfl⟩ := c
      rw [if_pos (by decide), Option.some.injEq] at h
      subst h
      exact .i32
    · rw [if_neg (by simpa using c)] at h; cases h
  | tyUint u =>
    simp only [wideOf, wideUint] at h
    by_cases c : negative = false ∧ n ≤ 18446744073709551615
    · obtain ⟨rfl, le⟩ := c
      rw [if_pos (by simpa using le)] at h
      obtain ⟨lt, rfl⟩ := uintInRange_some h
      rw [BitVec.toNat_ofNat, Nat.mod_eq_of_lt (by omega)] at lt
      exact .uint lt
    · rw [if_neg (by cases negative <;> simp_all)] at h; cases h
  | tyIsize =>
    simp only [wideOf, wideIsize] at h
    by_cases c : negative = false ∧ n ≤ 9223372036854775807
    · obtain ⟨rfl, le⟩ := c
      rw [if_pos (by simpa using le), Option.some.injEq] at h
      subst h
      exact .isize (by omega)
    · rw [if_neg (by cases negative <;> simp_all)] at h
      by_cases d : negative = true ∧ n ≤ 9223372036854775808
      · obtain ⟨rfl, le⟩ := d
        rw [if_pos (by simpa using le), Option.some.injEq] at h
        subst h
        rw [show 18446744073709551615 - n + 1 = 2 ^ 64 - n by omega]
        exact .isizeNeg (by omega)
      · rw [if_neg (by cases negative <;> simp_all)] at h; cases h
  | tyBool => cases h
  | tyChar => cases h
  | tyPtr => cases h
  | tySlice _ => cases h
  | tyNamed _ _ => cases h
  | tySint u =>
    simp only [wideOf, wideSint] at h
    by_cases w : sintWide u = true
    · have bits : uintBits u = 64 := by cases u <;> simp_all [sintWide, uintBits]
      rw [if_neg (by simp [w])] at h
      by_cases c : negative = false ∧ n ≤ 9223372036854775807
      · obtain ⟨rfl, le⟩ := c
        rw [if_pos (by simpa using le), Option.some.injEq] at h
        subst h
        exact .sint bits (by omega)
      · rw [if_neg (by cases negative <;> simp_all)] at h
        by_cases d : negative = true ∧ n ≤ 9223372036854775808
        · obtain ⟨rfl, le⟩ := d
          rw [if_pos (by simpa using le), Option.some.injEq] at h
          subst h
          rw [show 18446744073709551615 - n + 1 = 2 ^ 64 - n by omega]
          exact .sintNeg bits (by omega)
        · rw [if_neg (by cases negative <;> simp_all)] at h; cases h
    · rw [if_pos (by simpa using w)] at h; cases h

theorem wideDigits_sound {t : Ty} {negative : Bool} {text : List Nat} {e : SrcExpr}
    (h : wideDigits t negative (wideDecimal text 0) = some e) :
    Digits text ∧ digitsValue text < 2 ^ 64 ∧ WideOf t negative (digitsValue text) e := by
  unfold wideDigits at h
  cases hw : wideDecimal text 0 with
  | none => rw [hw] at h; cases h
  | some n =>
    rw [hw] at h
    obtain ⟨ds, rfl, le⟩ := wideDecimal_sound text 0 n hw
    exact ⟨ds, by unfold digitsValue; omega, wideOf_sound h⟩

theorem wideConst_sound {t : Ty} {toks : List Token} {e : SrcExpr} (h : wideConst (some t) toks = some e) :
    WideConst t toks e := by
  unfold wideConst at h
  match toks, h with
  | [a], h =>
    obtain ⟨ds, lt, w⟩ := wideDigits_sound h
    exact .pos ds lt w
  | [a, b], h =>
    simp only [wideSigned] at h
    by_cases dash : sameText a.text dashText = true
    · rw [if_pos dash] at h
      obtain ⟨ds, lt, w⟩ := wideDigits_sound h
      exact .neg ((sameText_iff _ _).1 dash) ds lt w
    · rw [if_neg dash] at h; cases h
  | [], h => cases h
  | _ :: _ :: _ :: _, h => cases h

/-! ## Locals and fields -/

/-- The innermost local spelled `n`. -/
def LocalNamed (scope : List Local) (n : Name) (l : Local) : Prop :=
  ∃ i, FirstWith scope (·.name = n) i l

/-- The spelling of `self`. -/
def selfText : Name := [115, 101, 108, 102]

/-- A path of one plain segment, spelled `n`. -/
def PathName (path : CTree) (n : Name) : Prop :=
  nodeProd path = pPath ∧ nodeProd (kid path 0) = pPathIdent ∧ nodeProd (kid path 1) = pPathEnd ∧
    n = (kidToken (kid path 0) 0).text

/-- A primary that names a local: a plain name, or `self`. -/
inductive LocalOf (scope : List Local) (c : CTree) : Local → Prop
  | name {n : Name} {l : Local} : nodeProd c = pIdent → nodeProd (kid c 1) = pIdentPlain → PathName (kid c 0) n →
      LocalNamed scope n l → LocalOf scope c l
  | self {l : Local} : nodeProd c = pSelfValue → LocalNamed scope selfText l → LocalOf scope c l

theorem localTest (n : Name) (l : Local) : sameText l.name n = true ↔ l.name = n := sameText_iff _ _

theorem findLocal_sound {scope : List Local} {n : Name} {l : Local} (h : findLocal scope n = some l) :
    LocalNamed scope n l :=
  pick_sound (fun l => sameText l.name n) _ (localTest n) (fun xs => findLocal xs n) rfl (fun _ _ => rfl) scope l h

theorem findLocal_none {scope : List Local} {n : Name} (h : findLocal scope n = none) : ∀ l ∈ scope, l.name ≠ n :=
  pick_none (fun l => sameText l.name n) _ (localTest n) (fun xs => findLocal xs n) (fun _ _ => rfl) scope h

theorem pathName_eq {path : CTree} {n : Name} (h : pathName path = some n) : PathName path n := by
  unfold pathName at h
  by_cases c : nodeProd path = pPath ∧ nodeProd (kid path 0) = pPathIdent ∧ nodeProd (kid path 1) = pPathEnd
  · rw [if_pos (by simpa [and_assoc] using c), Option.some.injEq] at h
    exact ⟨c.1, c.2.1, c.2.2, h.symm⟩
  · rw [if_neg (by simpa [and_assoc] using c)] at h; cases h

theorem pathName_of {path : CTree} {n : Name} (h : PathName path n) : pathName path = some n := by
  obtain ⟨a, b, c, rfl⟩ := h
  unfold pathName
  rw [if_pos (by simp [a, b, c])]

theorem localOf_sound {env : FrontEnv} {scope : List Local} {c : CTree} {l : Local}
    (h : localOf env scope c = some l) : LocalOf scope c l := by
  unfold localOf at h
  by_cases nm : nodeProd c = pIdent ∧ nodeProd (kid c 1) = pIdentPlain
  · rw [if_pos (by simpa using nm)] at h
    cases hp : pathName (kid c 0) with
    | none => rw [hp] at h; cases h
    | some n =>
      rw [hp] at h
      exact .name nm.1 nm.2 (pathName_eq hp) (findLocal_sound h)
  · rw [if_neg (by simpa using nm)] at h
    by_cases sv : nodeProd c = pSelfValue
    · rw [if_pos sv] at h
      exact .self sv (findLocal_sound h)
    · rw [if_neg sv] at h; cases h

theorem localOf_none {env : FrontEnv} {scope : List Local} {c : CTree} (h : localOf env scope c = none) :
    ∀ l, ¬LocalOf scope c l := by
  intro l r
  unfold localOf at h
  cases r with
  | name pi pp pn ln =>
    rw [if_pos (by simp [pi, pp]), pathName_of pn] at h
    obtain ⟨i, fi⟩ := ln
    exact findLocal_none h l (firstWith_mem fi).1 (firstWith_mem fi).2
  | self sv ln =>
    rw [if_neg (by simp [sv]), if_pos sv] at h
    obtain ⟨i, fi⟩ := ln
    exact findLocal_none h l (firstWith_mem fi).1 (firstWith_mem fi).2

/-- No local in scope has the id: each binding's id is its own. -/
def FreshId (scope : List Local) (id : Nat) : Prop := ∀ l ∈ scope, l.id ≠ id

theorem freshId_iff : ∀ (scope : List Local) (id : Nat), freshId scope id = true ↔ FreshId scope id
  | [], _ => by simp [freshId, FreshId]
  | l :: rest, id => by simp [freshId, FreshId, freshId_iff rest id]

/-- Field `j` of the struct type `t` is the first spelled `name`. -/
def FieldIndex (decls : Decls) (t : Ty) (name : Name) (j : Nat) : Prop :=
  ∃ d args td, t = .tyNamed d args ∧ decls.types[d]? = some td ∧ FirstWith td.fields (· = name) j name

/-- `primary.member`: a field of a struct local. -/
def Member (env : FrontEnv) (scope : List Local) (primary tail : CTree) (e : SrcExpr) : Prop :=
  nodeProd (kid tail 2) = pMemberTypeArgsNone ∧ nodeProd (kid tail 3) = pPostfixEnd ∧
    ∃ l j, LocalOf scope primary l ∧ FieldIndex env.decls l.ty (kidToken tail 1).text j ∧ e = .field l.id j

theorem memberOf_sound {env : FrontEnv} {scope : List Local} {primary tail : CTree} {e : SrcExpr}
    (h : memberOf env scope primary tail = some e) : Member env scope primary tail e := by
  unfold memberOf at h
  by_cases c : nodeProd (kid tail 2) = pMemberTypeArgsNone ∧ nodeProd (kid tail 3) = pPostfixEnd
  · rw [if_pos (by simpa using c)] at h
    refine ⟨c.1, c.2, ?_⟩
    cases hl : localOf env scope primary with
    | none => rw [hl] at h; cases h
    | some l =>
      rw [hl] at h
      simp only [fieldExpr] at h
      cases hf : fieldIndex env l.ty (kidToken tail 1).text with
      | none => rw [hf] at h; cases h
      | some j =>
        rw [hf, Option.some.injEq] at h
        refine ⟨l, j, localOf_sound hl, ?_, h.symm⟩
        unfold fieldIndex at hf
        cases ht : l.ty with
        | tyNamed d args =>
          rw [ht] at hf
          simp only [fieldIn] at hf
          cases hd : env.decls.types[d]? with
          | none => rw [hd] at hf; cases hf
          | some td =>
            rw [hd] at hf
            exact ⟨d, args, td, rfl, hd, position_sound hf⟩
        | tyI32 => rw [ht] at hf; cases hf
        | tyBool => rw [ht] at hf; cases hf
        | tyUint _ => rw [ht] at hf; cases hf
        | tyPtr => rw [ht] at hf; cases hf
        | tyIsize => rw [ht] at hf; cases hf
        | tyChar => rw [ht] at hf; cases hf
        | tySlice _ => rw [ht] at hf; cases hf
        | tySint _ => rw [ht] at hf; cases hf
  · rw [if_neg (by simpa using c)] at h; cases h

/-! ## Casts -/

/-- The scalar types as source types. -/
inductive ScalarTy : Ty → SrcType → Prop
  | i32 : ScalarTy .tyI32 .i32
  | bool : ScalarTy .tyBool .bool
  | uint {k : UintTy} : ScalarTy (.tyUint k) (.uint k)
  | ptr : ScalarTy .tyPtr .ptr
  | isize : ScalarTy .tyIsize .isize
  | char : ScalarTy .tyChar .char
  | sint {k : UintTy} : ScalarTy (.tySint k) (.sint k)

theorem scalarSrc_sound {t : Ty} {s : SrcType} (h : scalarSrc t = some s) : ScalarTy t s := by
  cases t <;> simp [scalarSrc] at h <;> subst h <;> constructor

/-- The scalar type a one-segment name stands for: a type parameter's, a
primitive type, or else a type alias of the module. -/
inductive NamedScalar (env : FrontEnv) (n : Name) : SrcType → Prop
  | param {t : Ty} {s : SrcType} : ParamTy env n t → ScalarTy t s → NamedScalar env n s
  | prim {t : Ty} {s : SrcType} : NoParam env n → primTys.lookup n = some t → ScalarTy t s → NamedScalar env n s
  | alias {t : Ty} {s : SrcType} : NoParam env n → primTys.lookup n = none → AliasTy env [n] [] t → ScalarTy t s →
      NamedScalar env n s

/-- The type a cast names: one segment, a `NamedScalar`. -/
def CastType (env : FrontEnv) (t : CTree) (s : SrcType) : Prop :=
  nodeProd t = pCastTypeName ∧ nodeProd (kid t 0) = pCastTypePath ∧ nodeProd (kid (kid t 0) 0) = pCastTypePathIdent ∧
    nodeProd (kid (kid t 0) 1) = pCastTypePathEnd ∧ NamedScalar env (kidToken (kid (kid t 0) 0) 0).text s

theorem hasKids_iff (c : CTree) : hasKids c = true ↔ kidsOf c ≠ [] := by
  unfold hasKids
  cases kidsOf c <;> simp

/-- `acc as T as U ...`: the casts apply left to right. -/
inductive Casts (env : FrontEnv) : SrcExpr → CTree → SrcExpr → Prop
  | done {acc : SrcExpr} {tail : CTree} : kidsOf tail = [] → Casts env acc tail acc
  | step {acc : SrcExpr} {tail : CTree} {s : SrcType} {e : SrcExpr} : kidsOf tail ≠ [] → CastType env (kid tail 1) s →
      Casts env (.cast s acc) (kid tail 2) e → Casts env acc tail e

theorem namedScalar_sound {fuel : Nat} {env : FrontEnv} {n : Name} {s : SrcType}
    (h : namedScalar fuel env n = some s) : NamedScalar env n s := by
  unfold namedScalar at h
  cases hp : paramTy env n with
  | some t =>
    rw [hp] at h
    exact .param (paramTy_sound hp) (scalarSrc_sound h)
  | none =>
    rw [hp] at h
    simp only at h
    rw [primTy_eq] at h
    cases hq : primTys.lookup n with
    | some t =>
      rw [hq] at h
      exact .prim (paramTy_none hp) hq (scalarSrc_sound h)
    | none =>
      rw [hq] at h
      simp only [scalarOf] at h
      cases ha : aliasTy fuel env [n] (some []) with
      | none => rw [ha] at h; cases h
      | some t =>
        rw [ha] at h
        obtain ⟨ts, e, al⟩ := (tySound fuel).2.2.2.1 ha
        cases e
        exact .alias (paramTy_none hp) hq al (scalarSrc_sound h)

theorem castTypeOf_sound {fuel : Nat} {env : FrontEnv} {t : CTree} {s : SrcType}
    (h : castTypeOf fuel env t = some s) : CastType env t s := by
  unfold castTypeOf at h
  by_cases c : nodeProd t = pCastTypeName ∧ nodeProd (kid t 0) = pCastTypePath ∧
      nodeProd (kid (kid t 0) 0) = pCastTypePathIdent ∧ nodeProd (kid (kid t 0) 1) = pCastTypePathEnd
  · rw [if_pos (by simpa [and_assoc] using c)] at h
    exact ⟨c.1, c.2.1, c.2.2.1, c.2.2.2, namedScalar_sound h⟩
  · rw [if_neg (by simpa [and_assoc] using c)] at h; cases h

theorem casts_sound : ∀ {fuel : Nat} {env : FrontEnv} {acc : Option SrcExpr} {tail : CTree} {e : SrcExpr},
    casts fuel env acc tail = some e → ∃ a, acc = some a ∧ Casts env a tail e
  | 0, _, _, _, _, h => by rw [casts.eq_def] at h; simp at h
  | f + 1, env, acc, tail, e, h => by
    rw [casts.eq_def] at h
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
    by_cases k : hasKids tail = true
    · rw [if_pos k] at h
      obtain ⟨a', ha, r⟩ := casts_sound h
      simp only [castInto] at ha
      cases hc : castTypeOf (f + 1) env (kid tail 1) with
      | none => rw [hc] at ha; cases ha
      | some s =>
        rw [hc] at ha
        simp only [castValue] at ha
        cases acc with
        | none => cases ha
        | some a =>
          simp only [Option.some.injEq] at ha
          subst ha
          exact ⟨a, rfl, .step ((hasKids_iff _).1 k) (castTypeOf_sound hc) r⟩
    · rw [if_neg k] at h
      exact ⟨e, h, .done (by simpa [hasKids_iff] using k)⟩

/-! ## Binary operators -/

/-- The binary operators of the operator tail productions. -/
def tailOps : List (Nat × SrcOp) :=
  [(pOrTail, .logicalOr), (pAndTail, .logicalAnd), (pBorTail, .bitOr), (pXorTail, .bitXor), (pBandTail, .bitAnd),
   (pEqTail, .equal), (pNeTail, .notEqual), (pLtTail, .less), (pGtTail, .greater), (pLeTail, .lessEq),
   (pGeTail, .greaterEq), (pShlTail, .shiftLeft), (pShrTail, .shiftRight), (pAddTail, .plus), (pSubTail, .minus),
   (pMulTail, .times)]

/-- The levels of binary operators: `level -> operand level_tail`. -/
def levelProds : List Nat :=
  [pOrexpr, pAndexpr, pBitOr, pBitXor, pBitAnd, pEquality, pCompare, pShift, pAdd, pMul]

theorem ite_lookup {β : Type} (p a : Nat) (b : β) (rest : List (Nat × β)) (x : Option β)
    (hx : x = rest.lookup p) : (if p = a then some b else x) = ((a, b) :: rest).lookup p := by
  by_cases e : p = a
  · subst e; simp [List.lookup]
  · rw [if_neg e, hx, List.lookup, beq_false_of_ne e]

theorem tailOp_eq (p : Nat) : tailOp p = tailOps.lookup p := by
  unfold tailOp tailOps
  repeat (refine ite_lookup _ _ _ _ _ ?_)
  rfl

theorem isLevel_iff (p : Nat) : isLevel p = true ↔ p ∈ levelProds := by
  simp [isLevel, levelProds, pOrexpr, pAndexpr, pBitOr, pBitXor, pBitAnd, pEquality, pCompare, pShift, pAdd, pMul,
    or_assoc]

/-! ## The expression reading -/

/-- Where a constant's value and type are read: its module, no type
parameters. -/
abbrev constScope (decls : Decls) (k : ConstDecl) : FrontEnv := declScope decls k.home [] []

mutual
inductive ExprR : FrontEnv → List Local → CTree → SrcExpr → Prop
  | wrap {env : FrontEnv} {scope : List Local} {c : CTree} {e : SrcExpr} :
      (nodeProd c = pExpr ∨ nodeProd c = pBase) → ExprR env scope (kid c 0) e → ExprR env scope c e
  | assign {env : FrontEnv} {scope : List Local} {c : CTree} {e : SrcExpr} :
      nodeProd c = pAssign → nodeProd (kid c 1) = pAssignEnd → ExprR env scope (kid c 0) e → ExprR env scope c e
  | level {env : FrontEnv} {scope : List Local} {c : CTree} {a e : SrcExpr} :
      nodeProd c ∈ levelProds → ExprR env scope (kid c 0) a → Fold env scope a (kid c 1) e → ExprR env scope c e
  | cast {env : FrontEnv} {scope : List Local} {c : CTree} {a e : SrcExpr} :
      nodeProd c = pCast → ExprR env scope (kid c 0) a → Casts env a (kid c 1) e → ExprR env scope c e
  | neg {env : FrontEnv} {scope : List Local} {c : CTree} {a : SrcExpr} :
      nodeProd c = pNeg → ExprR env scope (kid c 1) a → ExprR env scope c (.negate a)
  | not {env : FrontEnv} {scope : List Local} {c : CTree} {a : SrcExpr} :
      nodeProd c = pNot → ExprR env scope (kid c 1) a → ExprR env scope c (.not a)
  | postfix {env : FrontEnv} {scope : List Local} {c : CTree} {e : SrcExpr} :
      nodeProd c = pPostfix → nodeProd (kid c 1) = pPostfixEnd → ExprR env scope (kid c 0) e → ExprR env scope c e
  | member {env : FrontEnv} {scope : List Local} {c : CTree} {e : SrcExpr} :
      nodeProd c = pPostfix → nodeProd (kid c 1) = pPostfixMember → Member env scope (kid c 0) (kid c 1) e →
      ExprR env scope c e
  | group {env : FrontEnv} {scope : List Local} {c : CTree} {e : SrcExpr} :
      nodeProd c = pGroup → ExprR env scope (kid c 1) e → ExprR env scope c e
  | local {env : FrontEnv} {scope : List Local} {c : CTree} {l : Local} :
      nodeProd c = pIdent → nodeProd (kid c 1) = pIdentPlain → LocalOf scope c l → ExprR env scope c (.local l.id)
  | const {env : FrontEnv} {scope : List Local} {c : CTree} {ss : List Name} {m : ModPath} {n : Name} {k : ConstDecl}
      {e : SrcExpr} :
      nodeProd c = pIdent → nodeProd (kid c 1) = pIdentPlain → (∀ l, ¬LocalOf scope c l) →
      PathSpellings (kid (kid c 0) 0) (kid (kid c 0) 1) ss → Resolves env.home ss m n → ConstNamed env.decls m n k →
      ConstValue env.decls k e → ExprR env scope c e
  | self {env : FrontEnv} {scope : List Local} {c : CTree} {l : Local} :
      nodeProd c = pSelfValue → LocalOf scope c l → ExprR env scope c (.local l.id)
  | int {env : FrontEnv} {scope : List Local} {c : CTree} {e : SrcExpr} :
      nodeProd c = pInt → IntLiteral (kidToken c 0).text e → ExprR env scope c e
  | char {env : FrontEnv} {scope : List Local} {c : CTree} {n : Nat} :
      nodeProd c = pChar → CharLiteral (kidToken c 0).text n → ExprR env scope c (.char (BitVec.ofNat 32 n))
  | true {env : FrontEnv} {scope : List Local} {c : CTree} : nodeProd c = pTrue → ExprR env scope c (.boolean true)
  | false {env : FrontEnv} {scope : List Local} {c : CTree} : nodeProd c = pFalse → ExprR env scope c (.boolean false)

/-- `acc op operand op operand ...`: the operators apply left to right. -/
inductive Fold : FrontEnv → List Local → SrcExpr → CTree → SrcExpr → Prop
  | done {env : FrontEnv} {scope : List Local} {acc : SrcExpr} {tail : CTree} : kidsOf tail = [] → Fold env scope acc tail acc
  | step {env : FrontEnv} {scope : List Local} {acc : SrcExpr} {tail : CTree} {o : SrcOp} {r e : SrcExpr} :
      kidsOf tail ≠ [] → tailOps.lookup (nodeProd tail) = some o → ExprR env scope (kid tail 1) r →
      Fold env scope (.apply o acc r) (kid tail 2) e → Fold env scope acc tail e

/-- A constant's value: its value expression, read in its module with no
locals, as a literal of its declared type; or, when that expression is a
wide literal or its negation (`wideRead`), its tokens as a wide literal of
the type. -/
inductive ConstValue : Decls → ConstDecl → SrcExpr → Prop
  | literal {decls : Decls} {k : ConstDecl} {t : Ty} {v e : SrcExpr} : TyR (constScope decls k) k.ty t →
      ExprR (constScope decls k) [] k.value v → wideRead v = false → TypedLiteral t v e → ConstValue decls k e
  | wide {decls : Decls} {k : ConstDecl} {t : Ty} {v e : SrcExpr} : TyR (constScope decls k) k.ty t →
      ExprR (constScope decls k) [] k.value v → wideRead v = true → WideConst t k.value.leaves e →
      ConstValue decls k e
end

/-! ## Soundness -/

mutual
theorem treeTokens_eq : ∀ (t : CTree), treeTokens t = t.leaves
  | .leaf _ => rfl
  | .node _ kids => by rw [treeTokens, CTree.leaves, treesTokens_eq kids]
theorem treesTokens_eq : ∀ (ts : List CTree), treesTokens ts = CTree.leavesOf ts
  | [] => rfl
  | t :: rest => by rw [treesTokens, CTree.leavesOf, treeTokens_eq t, treesTokens_eq rest]
end

def ExprSound (fuel : Nat) : Prop :=
  (∀ {env scope c e}, exprOf fuel env scope c = some e → ExprR env scope c e) ∧
  (∀ {env scope c e}, identExpr fuel env scope c = some e → nodeProd (kid c 1) = pIdentPlain ∧
    ((∃ l, LocalOf scope c l ∧ e = .local l.id) ∨
     ((∀ l, ¬LocalOf scope c l) ∧ ∃ ss m n k, PathSpellings (kid (kid c 0) 0) (kid (kid c 0) 1) ss ∧
       Resolves env.home ss m n ∧ ConstNamed env.decls m n k ∧ ConstValue env.decls k e))) ∧
  (∀ {env segs e}, constRef fuel env segs = some e → ∃ ss m n k, segs = some ss ∧ Resolves env.home ss m n ∧
    ConstNamed env.decls m n k ∧ ConstValue env.decls k e) ∧
  (∀ {decls k e}, constValue fuel decls k = some e → ConstValue decls k e) ∧
  (∀ {env scope c e}, assignValue fuel env scope c = some e →
    nodeProd (kid c 1) = pAssignEnd ∧ ExprR env scope (kid c 0) e) ∧
  (∀ {env scope primary tail e}, postfixValue fuel env scope primary tail = some e →
    (nodeProd tail = pPostfixEnd ∧ ExprR env scope primary e) ∨
    (nodeProd tail = pPostfixMember ∧ Member env scope primary tail e)) ∧
  (∀ {env scope acc tail e}, fold fuel env scope acc tail = some e → ∃ a, acc = some a ∧ Fold env scope a tail e) ∧
  (∀ {env scope acc op tail e}, foldOp fuel env scope acc op tail = some e → ∃ a o r, acc = some a ∧ op = some o ∧
    ExprR env scope (kid tail 1) r ∧ Fold env scope (.apply o a r) (kid tail 2) e) ∧
  (∀ {env scope left op tail e}, foldLeft fuel env scope left op tail = some e → ∃ o r, op = some o ∧
    ExprR env scope (kid tail 1) r ∧ Fold env scope (.apply o left r) (kid tail 2) e)

theorem exprSound : ∀ fuel, ExprSound fuel
  | 0 => by
    refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩ <;> intros <;>
      first
      | (rename_i h; rw [exprOf.eq_def] at h; simp at h)
      | (rename_i h; rw [identExpr.eq_def] at h; simp at h)
      | (rename_i h; rw [constRef.eq_def] at h; simp at h)
      | (rename_i h; rw [constValue.eq_def] at h; simp at h)
      | (rename_i h; rw [assignValue.eq_def] at h; simp at h)
      | (rename_i h; rw [postfixValue.eq_def] at h; simp at h)
      | (rename_i h; rw [fold.eq_def] at h; simp at h)
      | (rename_i h; rw [foldOp.eq_def] at h; simp at h)
      | (rename_i h; rw [foldLeft.eq_def] at h; simp at h)
  | f + 1 => by
    obtain ⟨expr_ih, ident_ih, constRef_ih, constValue_ih, assign_ih, postfix_ih, fold_ih, foldOp_ih, foldLeft_ih⟩ :=
      exprSound f
    refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩
    · intro env scope c e h
      rw [exprOf.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      by_cases w : nodeProd c = pExpr ∨ nodeProd c = pBase
      · rw [if_pos (by simpa using w)] at h
        exact .wrap w (expr_ih h)
      rw [if_neg (by simpa using w)] at h
      by_cases a : nodeProd c = pAssign
      · rw [if_pos a] at h
        obtain ⟨ae, r⟩ := assign_ih h
        exact .assign a ae r
      rw [if_neg a] at h
      by_cases lv : isLevel (nodeProd c) = true
      · rw [if_pos lv] at h
        obtain ⟨x, hx, r⟩ := fold_ih h
        exact .level ((isLevel_iff _).1 lv) (expr_ih hx) r
      rw [if_neg lv] at h
      by_cases ca : nodeProd c = pCast
      · rw [if_pos ca] at h
        obtain ⟨x, hx, r⟩ := casts_sound h
        exact .cast ca (expr_ih hx) r
      rw [if_neg ca] at h
      by_cases ng : nodeProd c = pNeg
      · rw [if_pos ng] at h
        simp only [negated] at h
        cases hx : exprOf f env scope (kid c 1) with
        | none => rw [hx] at h; cases h
        | some x =>
          rw [hx, Option.some.injEq] at h
          subst h
          exact .neg ng (expr_ih hx)
      rw [if_neg ng] at h
      by_cases nt : nodeProd c = pNot
      · rw [if_pos nt] at h
        simp only [notted] at h
        cases hx : exprOf f env scope (kid c 1) with
        | none => rw [hx] at h; cases h
        | some x =>
          rw [hx, Option.some.injEq] at h
          subst h
          exact .not nt (expr_ih hx)
      rw [if_neg nt] at h
      by_cases pf : nodeProd c = pPostfix
      · rw [if_pos pf] at h
        rcases postfix_ih h with ⟨pe, r⟩ | ⟨pm, r⟩
        · exact .postfix pf pe r
        · exact .member pf pm r
      rw [if_neg pf] at h
      by_cases gr : nodeProd c = pGroup
      · rw [if_pos gr] at h
        exact .group gr (expr_ih h)
      rw [if_neg gr] at h
      by_cases id : nodeProd c = pIdent
      · rw [if_pos id] at h
        obtain ⟨ip, r⟩ := ident_ih h
        rcases r with ⟨l, lo, rfl⟩ | ⟨nl, ss, m, n, k, sp, rs, cn, cv⟩
        · exact .local id ip lo
        · exact .const id ip nl sp rs cn cv
      rw [if_neg id] at h
      by_cases sv : nodeProd c = pSelfValue
      · rw [if_pos sv] at h
        simp only [localExpr] at h
        cases hl : localOf env scope c with
        | none => rw [hl] at h; cases h
        | some l =>
          rw [hl, Option.some.injEq] at h
          subst h
          exact .self sv (localOf_sound hl)
      rw [if_neg sv] at h
      by_cases it : nodeProd c = pInt
      · rw [if_pos it] at h
        exact .int it (intLiteral_sound h)
      rw [if_neg it] at h
      by_cases tr : nodeProd c = pTrue
      · rw [if_pos tr, Option.some.injEq] at h
        subst h
        exact .true tr
      rw [if_neg tr] at h
      by_cases fa : nodeProd c = pFalse
      · rw [if_pos fa, Option.some.injEq] at h
        subst h
        exact .false fa
      rw [if_neg fa] at h
      by_cases ch : nodeProd c = pChar
      · rw [if_pos ch] at h
        obtain ⟨n, lit, rfl⟩ := charLiteral_sound h
        exact .char ch lit
      rw [if_neg ch] at h
      cases h
    · intro env scope c e h
      rw [identExpr.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      by_cases ip : nodeProd (kid c 1) = pIdentPlain
      · rw [if_pos ip] at h
        refine ⟨ip, ?_⟩
        cases hl : localOf env scope c with
        | some l =>
          rw [hl, Option.some.injEq] at h
          exact .inl ⟨l, localOf_sound hl, h.symm⟩
        | none =>
          rw [hl] at h
          obtain ⟨ss, m, n, k, hs, rs, cn, cv⟩ := constRef_ih h
          exact .inr ⟨localOf_none hl, ss, m, n, k, pathSpellings_sound hs, rs, cn, cv⟩
      · rw [if_neg ip] at h; cases h
    · intro env segs e h
      rw [constRef.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      cases segs with
      | none => cases h
      | some ss =>
        simp only at h
        cases hs : splitLast ss with
        | none => rw [hs] at h; cases h
        | some s =>
          rw [hs] at h
          simp only at h
          cases hk : findConst env.decls.consts (moduleOr env.home s.home) s.name with
          | none => rw [hk] at h; cases h
          | some k =>
            rw [hk] at h
            exact ⟨ss, _, _, k, rfl, resolves_split hs, findConst_sound hk, constValue_ih h⟩
    · intro decls k e h
      rw [constValue.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      cases ht : tyOf f (declEnv decls k.home [] []) k.ty with
      | none =>
        rw [ht] at h
        simp only [literalAs, wideConst] at h
        split at h <;> cases h
      | some t =>
        rw [ht] at h
        cases hv : exprOf f (declEnv decls k.home [] []) [] k.value with
        | none =>
          rw [hv] at h
          simp [wideReadOf, literalAs] at h
        | some v =>
          rw [hv] at h
          by_cases w : wideRead v = true
          · rw [if_pos (by simpa [wideReadOf] using w), treeTokens_eq] at h
            exact .wide (tyOf_sound ht) (expr_ih hv) w (wideConst_sound h)
          · rw [if_neg (by simpa [wideReadOf] using w)] at h
            simp only [literalAs] at h
            exact .literal (tyOf_sound ht) (expr_ih hv) (by simpa using w) (typedLiteral_sound h)
    · intro env scope c e h
      rw [assignValue.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      by_cases ae : nodeProd (kid c 1) = pAssignEnd
      · rw [if_pos ae] at h
        exact ⟨ae, expr_ih h⟩
      · rw [if_neg ae] at h; cases h
    · intro env scope primary tail e h
      rw [postfixValue.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      by_cases pe : nodeProd tail = pPostfixEnd
      · rw [if_pos pe] at h
        exact .inl ⟨pe, expr_ih h⟩
      rw [if_neg pe] at h
      by_cases pm : nodeProd tail = pPostfixMember
      · rw [if_pos pm] at h
        exact .inr ⟨pm, memberOf_sound h⟩
      · rw [if_neg pm] at h; cases h
    · intro env scope acc tail e h
      rw [fold.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      by_cases k : hasKids tail = true
      · rw [if_pos k] at h
        obtain ⟨a, o, r, rfl, ho, rr, fr⟩ := foldOp_ih h
        rw [tailOp_eq] at ho
        exact ⟨a, rfl, .step ((hasKids_iff _).1 k) ho rr fr⟩
      · rw [if_neg k] at h
        exact ⟨e, h, .done (by simpa [hasKids_iff] using k)⟩
    · intro env scope acc op tail e h
      rw [foldOp.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      cases acc with
      | none => cases h
      | some a =>
        simp only at h
        obtain ⟨o, r, rfl, rr, fr⟩ := foldLeft_ih h
        exact ⟨a, o, r, rfl, rfl, rr, fr⟩
    · intro env scope left op tail e h
      rw [foldLeft.eq_def] at h
      simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
      cases op with
      | none => cases h
      | some o =>
        simp only at h
        obtain ⟨x, hx, fr⟩ := fold_ih h
        simp only [applyOf] at hx
        cases hr : exprOf f env scope (kid tail 1) with
        | none => rw [hr] at hx; cases hx
        | some r =>
          rw [hr, Option.some.injEq] at hx
          subst hx
          exact ⟨o, r, rfl, expr_ih hr, fr⟩

theorem exprOf_sound {fuel : Nat} {env : FrontEnv} {scope : List Local} {c : CTree} {e : SrcExpr}
    (h : exprOf fuel env scope c = some e) : ExprR env scope c e :=
  (exprSound fuel).1 h

end Lanius.Mini.Reading
