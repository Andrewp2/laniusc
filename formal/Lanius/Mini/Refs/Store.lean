module

public import Lanius.Mini.Refs.Lemmas
import all Lanius.Mini.Compiler.P.SrcType_same
import all Lanius.Mini.Compiler.P.SrcType_size
import all Lanius.Mini.Compiler.P.fieldOffset
import all Lanius.Mini.Compiler.P.norm
import all Lanius.Mini.Compiler.P.wrap
import all Lanius.Mini.Compiler.P.widthOf
import all Lanius.Mini.Compiler.P.declaredSame
import all Lanius.Mini.Compiler.P.declaredVariants
import all Lanius.Mini.Compiler.P.wordType
import all Lanius.Mini.Compiler.P.wordWidth
import all Lanius.Mini.Compiler.P.usizeWidth
import all Lanius.Mini.Compiler.P.SrcType_floatTy
import all Lanius.Mini.Compiler.P.SrcType_isBool
import all Lanius.Mini.Compiler.P.SrcType_isChar
import all Lanius.Mini.Compiler.P.SrcType_isFloat
import all Lanius.Mini.Compiler.P.SrcType_isFloatAny
import all Lanius.Mini.Compiler.P.SrcType_isI32
import all Lanius.Mini.Compiler.P.SrcType_isInteger
import all Lanius.Mini.Compiler.P.SrcType_isIsize
import all Lanius.Mini.Compiler.P.SrcType_isPtr
import all Lanius.Mini.Compiler.P.SrcType_isScalar
import all Lanius.Mini.Compiler.P.SrcType_isSint
import all Lanius.Mini.Compiler.P.SrcType_isSintAny
import all Lanius.Mini.Compiler.P.SrcType_isStr
import all Lanius.Mini.Compiler.P.SrcType_isUint
import all Lanius.Mini.Compiler.P.SrcType_isUnit
import all Lanius.Mini.Compiler.P.SrcType_sintKind
import all Lanius.Mini.Compiler.P.SrcType_uintKind
import all Lanius.Mini.Compiler.P.SrcType_word
import all Lanius.Mini.Compiler.P.UintTy_half
import all Lanius.Mini.Compiler.P.UintTy_leastBits
import all Lanius.Mini.Compiler.P.UintTy_signedWord
import all Lanius.Mini.Compiler.P.UintTy_spare
import all Lanius.Mini.Compiler.P.boolBits
import all Lanius.Mini.Compiler.P.lookup
import all Lanius.Mini.Compiler.P.BinOp_size
import all Lanius.Mini.Compiler.P.Lists_concat
import all Lanius.Mini.Compiler.P.Lists_cons
import all Lanius.Mini.Compiler.P.Lists_empty
import all Lanius.Mini.Compiler.P.Lists_get
import all Lanius.Mini.Compiler.P.Lists_getOr
import all Lanius.Mini.Compiler.P.Lists_length
import all Lanius.Mini.Compiler.P.Lists_single
import all Lanius.Mini.Compiler.P.MemWidth_bytes
import all Lanius.Mini.Compiler.P.MemWidth_prefix
import all Lanius.Mini.Compiler.P.MemWidth_rex
import all Lanius.Mini.Compiler.P.Word_prefix
import all Lanius.Mini.Compiler.P.UintTy_code
import all Lanius.Mini.Compiler.P.entriesAt
import all Lanius.Mini.Compiler.P.funcsSize
import all Lanius.Mini.Compiler.P.funcsSlots
import all Lanius.Mini.Compiler.P.linkObjects
import all Lanius.Mini.Compiler.P.objectExports
import all Lanius.Mini.Compiler.P.objectFirsts
import all Lanius.Mini.Compiler.P.objectLayout
import all Lanius.Mini.Compiler.P.objectsLayout
import all Lanius.Mini.Compiler.P.objectsOk
import all Lanius.Mini.Compiler.P.objectsSlots
import all Lanius.Mini.Compiler.P.render
import all Lanius.Mini.Compiler.P.renderFuncs
import all Lanius.Mini.Compiler.P.renderObjects

@[expose] public section

/-! # References: stores (F5)

Facts for a write through a reference (`RefStore`): the widths of uniform
types and how an enum's variants agree on them, slots of a homed type lie
apart (`SrcType.slots_apart`), a held value survives the truncation of each
slot to its access width (`SrcType.HoldsAt.trunc`), the run of
`storeSlots`, and a replaced sub-value held in its parent's slots.
-/

namespace Lanius.Mini

open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

variable {sx : Statics} {places : List Addressed}

/-! ## Lists of widths -/

theorem MemWidth.eq_of_bytes {a b : MemWidth} (h : a.bytes = b.bytes) : a = b := by
  cases a <;> cases b <;> simp_all [MemWidth.bytes]

theorem mergeWidths_length : ∀ (a b : List MemWidth), (mergeWidths a b).length = max a.length b.length
  | [], b => by simp [mergeWidths]
  | a :: as, [] => by simp [mergeWidths]
  | a :: as, _ :: bs => by simp [mergeWidths, mergeWidths_length as bs, Nat.succ_max_succ]

theorem mergeWidths_getD_left : ∀ (a b : List MemWidth) {i : Nat} (d : MemWidth), i < a.length →
    (mergeWidths a b).getD i d = a.getD i d
  | [], b, i, d, lt => by simp at lt
  | a :: as, [], i, d, lt => by simp [mergeWidths]
  | a :: as, _ :: bs, 0, d, lt => by simp [mergeWidths]
  | a :: as, _ :: bs, i + 1, d, lt => by
    simp only [mergeWidths, List.getD_cons_succ]
    exact mergeWidths_getD_left as bs d (by simpa using lt)

theorem mergeWidths_getD_right : ∀ (a b : List MemWidth) {i : Nat} (d : MemWidth), a.length ≤ i →
    (mergeWidths a b).getD i d = b.getD i d
  | [], b, i, d, le => by simp [mergeWidths]
  | a :: as, [], i, d, le => by
    simp only [mergeWidths, List.getD_eq_getElem?_getD, List.getElem?_nil, Option.getD_none]
    rw [List.getElem?_eq_none (by simpa using le)]
    rfl
  | a :: as, _ :: bs, 0, d, le => by simp at le
  | a :: as, _ :: bs, i + 1, d, le => by
    simp only [mergeWidths, List.getD_cons_succ]
    exact mergeWidths_getD_right as bs d (by simpa using le)

theorem widthsAgree_getD : ∀ (a b : List MemWidth) {i : Nat} (d : MemWidth), widthsAgree a b = true →
    i < a.length → i < b.length → a.getD i d = b.getD i d
  | [], b, i, d, _, lt, _ => by simp at lt
  | a :: as, [], i, d, _, _, lt => by simp at lt
  | a :: as, b :: bs, 0, d, h, _, _ => by
    simp only [widthsAgree, Bool.and_eq_true, beq_iff_eq] at h
    simpa using MemWidth.eq_of_bytes h.1
  | a :: as, b :: bs, i + 1, d, h, lt, lt' => by
    simp only [widthsAgree, Bool.and_eq_true] at h
    simp only [List.getD_cons_succ]
    exact widthsAgree_getD as bs d h.2 (by simpa using lt) (by simpa using lt')

theorem List.getD_append_left' {α : Type} (l l' : List α) {i : Nat} (d : α) (lt : i < l.length) :
    (l ++ l').getD i d = l.getD i d := by
  simp [List.getD_eq_getElem?_getD, List.getElem?_append_left lt]

theorem List.getD_append_right' {α : Type} (l l' : List α) {i : Nat} (d : α) (le : l.length ≤ i) :
    (l ++ l').getD i d = l'.getD (i - l.length) d := by
  simp [List.getD_eq_getElem?_getD, List.getElem?_append_right le]

theorem flatten_replicate_getD {α : Type} (l : List α) (d : α) (pos : 0 < l.length) :
    ∀ (n i : Nat), i < n * l.length → (List.replicate n l).flatten.getD i d = l.getD (i % l.length) d
  | 0, i, lt => by simp at lt
  | n + 1, i, lt => by
    rw [List.replicate_succ, List.flatten_cons]
    rcases Nat.lt_or_ge i l.length with small | big
    · rw [List.getD_append_left' _ _ _ small, Nat.mod_eq_of_lt small]
    · rw [List.getD_append_right' _ _ _ big, flatten_replicate_getD l d pos n _ (by rw [Nat.succ_mul] at lt; omega)]
      congr 1
      conv => rhs; rw [show i = (i - l.length) + l.length by omega, Nat.add_mod_right]

/-! ## Uniform types -/

mutual
theorem SrcType.homeOk_of_uniform : ∀ (t : SrcType), t.uniform = true → t.homeOk = true
  | .struct _ fs, h => by
    simp only [SrcType.uniform, Bool.and_eq_true] at h
    simp only [SrcType.homeOk]
    exact fieldsHomeOk_of_uniform fs h.2
  | .enum _ vs, h => by simpa [SrcType.uniform, SrcType.homeOk] using h
  | .array e n, h => by
    simp only [SrcType.uniform, Bool.and_eq_true] at h
    simp only [SrcType.homeOk]
    exact SrcType.homeOk_of_uniform e h.2
  | .slice _, h => by simp [SrcType.uniform] at h
  | .view _, h => by simp [SrcType.uniform] at h
  | .i32, _ => rfl
  | .bool, _ => rfl
  | .uint _, _ => rfl
  | .ptr, _ => rfl
  | .unit, _ => rfl
  | .isize, _ => rfl
  | .char, _ => rfl
  | .float _, _ => rfl
  | .sint _, _ => rfl
  | .str, _ => rfl
  | .ref _, _ => rfl
termination_by structural t => t

theorem fieldsHomeOk_of_uniform : ∀ (fs : List SrcType), fieldsUniform fs = true → fieldsHomeOk fs = true
  | [], _ => rfl
  | t :: rest, h => by
    simp only [fieldsUniform, Bool.and_eq_true] at h
    simp only [fieldsHomeOk, SrcType.homeOk_of_uniform t h.1, fieldsHomeOk_of_uniform rest h.2, Bool.and_self]
termination_by structural fs => fs
end

mutual
theorem SrcType.widths_length : ∀ (t : SrcType), t.uniform = true → t.widths.length = t.size
  | .struct _ fs, h => by
    simp only [SrcType.uniform, Bool.and_eq_true] at h
    simp only [SrcType.widths, SrcType.size]
    exact fieldsWidths_length fs h.2
  | .enum _ vs, h => by
    simp only [SrcType.uniform, Bool.and_eq_true] at h
    simp only [SrcType.widths, SrcType.size, List.length_cons, variantsWidths_length vs h.1]
    omega
  | .array e n, h => by
    simp only [SrcType.uniform, Bool.and_eq_true] at h
    simp [SrcType.widths, SrcType.size, SrcType.widths_length e h.2]
  | .slice _, h => by simp [SrcType.uniform] at h
  | .view _, h => by simp [SrcType.uniform] at h
  | .i32, _ => rfl
  | .bool, _ => rfl
  | .uint _, _ => rfl
  | .ptr, _ => rfl
  | .unit, _ => rfl
  | .isize, _ => rfl
  | .char, _ => rfl
  | .float _, _ => rfl
  | .sint _, _ => rfl
  | .str, _ => rfl
  | .ref _, _ => rfl
termination_by structural t => t

theorem fieldsWidths_length : ∀ (fs : List SrcType), fieldsUniform fs = true → (fieldsWidths fs).length = sizes fs
  | [], _ => rfl
  | t :: rest, h => by
    simp only [fieldsUniform, Bool.and_eq_true] at h
    simp only [fieldsWidths, sizes, List.length_append, SrcType.widths_length t h.1, fieldsWidths_length rest h.2]
termination_by structural fs => fs

theorem variantsWidths_length : ∀ (vs : List (List SrcType)), variantsUniform vs = true →
    (variantsWidths vs).length = maxSize vs
  | [], _ => rfl
  | fs :: rest, h => by
    simp only [variantsUniform, Bool.and_eq_true] at h
    simp only [variantsWidths, maxSize, mergeWidths_length, fieldsWidths_length fs h.1,
      variantsWidths_length rest h.2]
termination_by structural vs => vs
end

mutual
theorem SrcType.size_le_words : ∀ (t : SrcType), t.uniform = true → t.size ≤ t.words
  | .struct _ fs, h => by
    simp only [SrcType.uniform, Bool.and_eq_true] at h
    have := fieldsSize_le_words fs h.2
    simp only [SrcType.size, SrcType.words]
    omega
  | .enum _ vs, h => by
    simp only [SrcType.uniform, Bool.and_eq_true] at h
    have := variantsSize_le_words vs h.1
    simp only [SrcType.size, SrcType.words]
    omega
  | .array e n, h => by
    simp only [SrcType.uniform, Bool.and_eq_true, Bool.not_eq_true'] at h
    simp only [SrcType.size, SrcType.words, h.1, Bool.false_eq_true, if_false]
    exact Nat.mul_le_mul_left _ (SrcType.size_le_words e h.2)
  | .slice _, h => by simp [SrcType.uniform] at h
  | .view _, h => by simp [SrcType.uniform] at h
  | .i32, _ => by simp [SrcType.size, SrcType.words]
  | .bool, _ => by simp [SrcType.size, SrcType.words]
  | .uint _, _ => by simp [SrcType.size, SrcType.words]
  | .ptr, _ => by simp [SrcType.size, SrcType.words]
  | .unit, _ => by simp [SrcType.size, SrcType.words]
  | .isize, _ => by simp [SrcType.size, SrcType.words]
  | .char, _ => by simp [SrcType.size, SrcType.words]
  | .float _, _ => by simp [SrcType.size, SrcType.words]
  | .sint _, _ => by simp [SrcType.size, SrcType.words]
  | .str, _ => by simp [SrcType.size, SrcType.words]
  | .ref _, _ => by simp [SrcType.size, SrcType.words]
termination_by structural t => t

theorem fieldsSize_le_words : ∀ (fs : List SrcType), fieldsUniform fs = true → sizes fs ≤ fieldWords fs
  | [], _ => by simp [sizes, fieldWords]
  | t :: rest, h => by
    simp only [fieldsUniform, Bool.and_eq_true] at h
    have := SrcType.size_le_words t h.1
    have := fieldsSize_le_words rest h.2
    simp only [sizes, fieldWords]
    omega
termination_by structural fs => fs

theorem variantsSize_le_words : ∀ (vs : List (List SrcType)), variantsUniform vs = true →
    maxSize vs ≤ variantWords vs
  | [], _ => by simp [maxSize, variantWords]
  | fs :: rest, h => by
    simp only [variantsUniform, Bool.and_eq_true] at h
    have := fieldsSize_le_words fs h.1
    have := variantsSize_le_words rest h.2
    simp only [maxSize, variantWords]
    omega
termination_by structural vs => vs
end

mutual
theorem SrcType.slotAt_uniform : ∀ (t : SrcType), t.uniform = true → ∀ i < t.size,
    (t.slotAt i).2 = .word (t.widths.getD i .m64)
  | .struct _ fs, h, i, lt => by
    simp only [SrcType.uniform, Bool.and_eq_true] at h
    simp only [SrcType.slotAt, SrcType.widths]
    exact fieldsSlotAt_uniform fs h.2 _ _ i (by simpa [SrcType.size] using lt)
  | .enum _ vs, h, 0, lt => by simp [SrcType.slotAt, SrcType.widths]
  | .enum _ vs, h, i + 1, lt => by simp [SrcType.slotAt, SrcType.widths]
  | .array e n, h, i, lt => by
    simp only [SrcType.uniform, Bool.and_eq_true, Bool.not_eq_true'] at h
    simp only [SrcType.size] at lt
    have pos : 0 < e.size := Nat.pos_of_ne_zero (by rintro z; simp [z] at lt)
    have len := SrcType.widths_length e h.2
    simp only [SrcType.slotAt, h.1, Bool.false_eq_true, if_false, SrcType.widths]
    rw [flatten_replicate_getD _ _ (by omega) n i (by rw [len]; exact lt), len]
    exact SrcType.slotAt_uniform e h.2 _ (Nat.mod_lt _ pos)
  | .slice _, h, _, _ => by simp [SrcType.uniform] at h
  | .view _, h, _, _ => by simp [SrcType.uniform] at h
  | .i32, _, i, lt => by
    obtain rfl : i = 0 := by simp only [SrcType.size] at lt; omega
    rfl
  | .bool, _, i, lt => by
    obtain rfl : i = 0 := by simp only [SrcType.size] at lt; omega
    rfl
  | .uint _, _, i, lt => by
    obtain rfl : i = 0 := by simp only [SrcType.size] at lt; omega
    rfl
  | .ptr, _, i, lt => by
    obtain rfl : i = 0 := by simp only [SrcType.size] at lt; omega
    rfl
  | .unit, _, i, lt => by
    obtain rfl : i = 0 := by simp only [SrcType.size] at lt; omega
    rfl
  | .isize, _, i, lt => by
    obtain rfl : i = 0 := by simp only [SrcType.size] at lt; omega
    rfl
  | .char, _, i, lt => by
    obtain rfl : i = 0 := by simp only [SrcType.size] at lt; omega
    rfl
  | .float _, _, i, lt => by
    obtain rfl : i = 0 := by simp only [SrcType.size] at lt; omega
    rfl
  | .sint _, _, i, lt => by
    obtain rfl : i = 0 := by simp only [SrcType.size] at lt; omega
    rfl
  | .ref _, _, i, lt => by
    obtain rfl : i = 0 := by simp only [SrcType.size] at lt; omega
    rfl
  | .str, _, i, lt => by
    simp only [SrcType.size] at lt
    rcases (show i = 0 ∨ i = 1 by omega) with rfl | rfl <;> rfl
termination_by structural t => t

theorem fieldsSlotAt_uniform : ∀ (fs : List SrcType), fieldsUniform fs = true → ∀ (total above i : Nat),
    i < sizes fs → (fieldsSlotAt total above fs i).2 = .word ((fieldsWidths fs).getD i .m64)
  | [], _, _, _, i, lt => by simp [sizes] at lt
  | t :: rest, h, total, above, i, lt => by
    simp only [fieldsUniform, Bool.and_eq_true] at h
    simp only [sizes] at lt
    have len := SrcType.widths_length t h.1
    rw [fieldsSlotAt, fieldsWidths]
    split
    · rename_i small
      rw [List.getD_append_left' _ _ _ (by omega)]
      exact SrcType.slotAt_uniform t h.1 i small
    · rename_i big
      rw [List.getD_append_right' _ _ _ (by omega), len]
      exact fieldsSlotAt_uniform rest h.2 _ _ _ (by omega)
termination_by structural fs => fs
end

theorem variantsUniform_get : ∀ {vs : List (List SrcType)} {k : Nat} {fs : List SrcType},
    variantsUniform vs = true → vs[k]? = some fs → fieldsUniform fs = true
  | [], _, _, _, h => by simp at h
  | f :: rest, 0, fs, u, h => by
    simp only [variantsUniform, Bool.and_eq_true] at u
    simp only [List.getElem?_cons_zero, Option.some.injEq] at h
    exact h ▸ u.1
  | f :: rest, k + 1, fs, u, h => by
    simp only [variantsUniform, Bool.and_eq_true] at u
    simp only [List.getElem?_cons_succ] at h
    exact variantsUniform_get u.2 h

theorem variantsTagsFit_get : ∀ {vs : List (List SrcType)} {k : Nat} {fs : List SrcType},
    variantsTagsFit vs = true → vs[k]? = some fs → fieldsTagsFit fs = true
  | [], _, _, _, h => by simp at h
  | f :: rest, 0, fs, u, h => by
    simp only [variantsTagsFit, Bool.and_eq_true] at u
    simp only [List.getElem?_cons_zero, Option.some.injEq] at h
    exact h ▸ u.1
  | f :: rest, k + 1, fs, u, h => by
    simp only [variantsTagsFit, Bool.and_eq_true] at u
    simp only [List.getElem?_cons_succ] at h
    exact variantsTagsFit_get u.2 h

theorem fieldsHomeOk_get : ∀ {fs : List SrcType} {k : Nat} {t : SrcType},
    fieldsHomeOk fs = true → fs[k]? = some t → t.homeOk = true
  | [], _, _, _, h => by simp at h
  | f :: rest, 0, t, u, h => by
    simp only [fieldsHomeOk, Bool.and_eq_true] at u
    simp only [List.getElem?_cons_zero, Option.some.injEq] at h
    exact h ▸ u.1
  | f :: rest, k + 1, t, u, h => by
    simp only [fieldsHomeOk, Bool.and_eq_true] at u
    simp only [List.getElem?_cons_succ] at h
    exact fieldsHomeOk_get u.2 h

/-- The variants agree on each payload slot's width, so the enum's width
there is its active variant's. -/
theorem variantsWidths_getD : ∀ (vs : List (List SrcType)) {k : Nat} {fs : List SrcType} {i : Nat},
    variantsUniform vs = true → variantsAgree vs = true → vs[k]? = some fs → i < sizes fs →
    (variantsWidths vs).getD i .m64 = (fieldsWidths fs).getD i .m64
  | [], _, _, _, _, _, h, _ => by simp at h
  | f :: rest, 0, fs, i, u, a, h, lt => by
    simp only [List.getElem?_cons_zero, Option.some.injEq] at h
    subst h
    simp only [variantsUniform, Bool.and_eq_true] at u
    simp only [variantsWidths]
    exact mergeWidths_getD_left _ _ _ (by rw [fieldsWidths_length _ u.1]; exact lt)
  | f :: rest, k + 1, fs, i, u, a, h, lt => by
    simp only [List.getElem?_cons_succ] at h
    simp only [variantsUniform, Bool.and_eq_true] at u
    simp only [variantsAgree, Bool.and_eq_true] at a
    have ih := variantsWidths_getD rest u.2 a.2 h lt
    have restLen : i < (variantsWidths rest).length := by
      rw [variantsWidths_length _ u.2]
      have := sizes_le_maxSize h
      omega
    simp only [variantsWidths]
    rcases Nat.lt_or_ge i (fieldsWidths f).length with small | big
    · rw [mergeWidths_getD_left _ _ _ small, widthsAgree_getD _ _ _ a.1 small restLen, ih]
    · rw [mergeWidths_getD_right _ _ _ big, ih]

/-- A field's slot is accessed the same way wherever the fields start. -/
theorem fieldsSlotAt_access : ∀ (fs : List SrcType) (total above total' above' i : Nat),
    (fieldsSlotAt total above fs i).2 = (fieldsSlotAt total' above' fs i).2
  | [], _, _, _, _, _ => rfl
  | t :: rest, total, above, total', above', i => by
    simp only [fieldsSlotAt]
    split
    · rfl
    · exact fieldsSlotAt_access rest _ _ _ _ _

theorem fieldsSlotAt_replicate (e : SrcType) : ∀ (n total above i : Nat), i < n * e.size →
    (fieldsSlotAt total above (List.replicate n e) i).2 = (e.slotAt (i % e.size)).2
  | 0, _, _, i, lt => by simp at lt
  | n + 1, total, above, i, lt => by
    rw [List.replicate_succ, fieldsSlotAt]
    split
    · rename_i small
      rw [Nat.mod_eq_of_lt small]
    · rename_i big
      rw [fieldsSlotAt_replicate e n _ _ _ (by rw [Nat.succ_mul] at lt; omega)]
      congr 2
      conv => rhs; rw [show i = (i - e.size) + e.size by omega, Nat.add_mod_right]

/-! ## Slots lie apart -/

mutual
theorem SrcType.slots_apart : ∀ (t : SrcType), t.homeOk = true → ∀ (s s' : Nat), s < t.size → s' < t.size → s ≠ s' →
    (t.slotAt s).1 + (t.slotAt s).2.bytes ≤ (t.slotAt s').1 ∨ (t.slotAt s').1 + (t.slotAt s').2.bytes ≤ (t.slotAt s).1
  | .struct _ fs, h, s, s', hs, hs', ne => by
    simp only [SrcType.homeOk] at h
    simp only [SrcType.size] at hs hs'
    simp only [SrcType.slotAt]
    exact fieldsSlots_apart fs _ 0 h (by omega) s s' hs hs' ne
  | .enum _ vs, h, s, s', hs, hs', ne => by
    simp only [SrcType.homeOk, Bool.and_eq_true] at h
    have le := variantsSize_le_words vs h.1
    simp only [SrcType.size] at hs hs'
    cases s with
    | zero =>
      cases s' with
      | zero => exact absurd rfl ne
      | succ s' =>
        have := ((variantsWidths vs).getD s' .m64).bytes_le_eight
        right
        simp only [SrcType.slotAt, SrcType.words, Access.bytes]
        omega
    | succ s =>
      have := ((variantsWidths vs).getD s .m64).bytes_le_eight
      cases s' with
      | zero =>
        left
        simp only [SrcType.slotAt, SrcType.words, Access.bytes]
        omega
      | succ s' =>
        have := ((variantsWidths vs).getD s' .m64).bytes_le_eight
        simp only [SrcType.slotAt, SrcType.words, Access.bytes]
        omega
  | .array e n, h, s, s', hs, hs', ne => by
    simp only [SrcType.homeOk] at h
    cases hn : e.accessKind.narrow with
    | true =>
      rcases SrcType.narrow_cases hn with rfl | rfl
      · simp only [SrcType.slotAt, SrcType.accessKind, Access.narrow, if_true, Access.bytes, MemWidth.bytes]
        omega
      · simp only [SrcType.slotAt, SrcType.accessKind, Access.narrow, if_true, Access.bytes]
        omega
    | false =>
      simp only [SrcType.size] at hs hs'
      have pos : 0 < e.size := Nat.pos_of_ne_zero (by rintro z; simp [z] at hs)
      have q : s / e.size < n := (Nat.div_lt_iff_lt_mul pos).2 hs
      have q' : s' / e.size < n := (Nat.div_lt_iff_lt_mul pos).2 hs'
      have r := Nat.mod_lt s pos
      have r' := Nat.mod_lt s' pos
      have fit := SrcType.slot_fits e (s % e.size) r
      have fit' := SrcType.slot_fits e (s' % e.size) r'
      have room : (s / e.size + 1) * e.words ≤ n * e.words := Nat.mul_le_mul_right _ q
      have room' : (s' / e.size + 1) * e.words ≤ n * e.words := Nat.mul_le_mul_right _ q'
      simp only [SrcType.slotAt, hn, Bool.false_eq_true, if_false]
      rcases Nat.lt_trichotomy (s / e.size) (s' / e.size) with lt | eq | gt
      · have step : (s / e.size + 1) * e.words + e.words ≤ (s' / e.size + 1) * e.words := by
          rw [← Nat.succ_mul]; exact Nat.mul_le_mul_right _ (by omega)
        right
        omega
      · have rne : s % e.size ≠ s' % e.size := by
          intro h'
          apply ne
          rw [← Nat.div_add_mod s e.size, ← Nat.div_add_mod s' e.size, eq, h']
        rw [eq]
        rcases SrcType.slots_apart e h _ _ r r' rne with a | a
        · left; omega
        · right; omega
      · have step : (s' / e.size + 1) * e.words + e.words ≤ (s / e.size + 1) * e.words := by
          rw [← Nat.succ_mul]; exact Nat.mul_le_mul_right _ (by omega)
        left
        omega
  | .slice _, _, s, s', hs, hs', ne => by
    simp only [SrcType.size] at hs hs'
    simp only [SrcType.slotAt, Access.bytes, MemWidth.bytes]
    omega
  | .view _, h, _, _, _, _, _ => by simp [SrcType.homeOk] at h
  | .str, _, s, s', hs, hs', ne => by
    simp only [SrcType.size] at hs hs'
    simp only [SrcType.slotAt, Access.bytes, MemWidth.bytes]
    omega
  | .i32, _, s, s', hs, hs', ne => by simp only [SrcType.size] at hs hs'; omega
  | .ref _, _, s, s', hs, hs', ne => by simp only [SrcType.size] at hs hs'; omega
  | .bool, _, s, s', hs, hs', ne => by simp only [SrcType.size] at hs hs'; omega
  | .uint _, _, s, s', hs, hs', ne => by simp only [SrcType.size] at hs hs'; omega
  | .ptr, _, s, s', hs, hs', ne => by simp only [SrcType.size] at hs hs'; omega
  | .unit, _, s, s', hs, hs', ne => by simp only [SrcType.size] at hs hs'; omega
  | .isize, _, s, s', hs, hs', ne => by simp only [SrcType.size] at hs hs'; omega
  | .char, _, s, s', hs, hs', ne => by simp only [SrcType.size] at hs hs'; omega
  | .float _, _, s, s', hs, hs', ne => by simp only [SrcType.size] at hs hs'; omega
  | .sint _, _, s, s', hs, hs', ne => by simp only [SrcType.size] at hs hs'; omega
termination_by structural t => t

theorem fieldsSlots_apart : ∀ (fs : List SrcType) (total above : Nat), fieldsHomeOk fs = true →
    above + fieldWords fs ≤ total → ∀ (s s' : Nat), s < sizes fs → s' < sizes fs → s ≠ s' →
    (fieldsSlotAt total above fs s).1 + (fieldsSlotAt total above fs s).2.bytes ≤ (fieldsSlotAt total above fs s').1 ∨
      (fieldsSlotAt total above fs s').1 + (fieldsSlotAt total above fs s').2.bytes ≤ (fieldsSlotAt total above fs s).1
  | [], _, _, _, _, s, _, hs, _, _ => by simp [sizes] at hs
  | t :: rest, total, above, h, room, s, s', hs, hs', ne => by
    simp only [fieldsHomeOk, Bool.and_eq_true] at h
    simp only [fieldWords] at room
    simp only [sizes] at hs hs'
    simp only [fieldsSlotAt]
    by_cases a : s < t.size <;> by_cases b : s' < t.size
    · simp only [a, b, if_true]
      rcases SrcType.slots_apart t h.1 s s' a b ne with c | c
      · left; omega
      · right; omega
    · simp only [a, b, if_true, if_false]
      have := fieldsSlot_fits rest total (above + t.words) (s' - t.size) (by omega) (by omega)
      right; omega
    · simp only [a, b, if_true, if_false]
      have := fieldsSlot_fits rest total (above + t.words) (s - t.size) (by omega) (by omega)
      left; omega
    · simp only [a, b, if_false]
      exact fieldsSlots_apart rest total (above + t.words) h.2 (by omega) _ _ (by omega) (by omega) (by omega)
termination_by structural fs => fs
end

/-! ## Truncation to access widths -/

theorem trunc_fit {x : BitVec 64} {b : Nat} (fit : x.toNat < 256 ^ b) :
    BitVec.ofNat 64 (x.toNat % 256 ^ b) = x := by
  rw [Nat.mod_eq_of_lt fit, BitVec.ofNat_toNat, BitVec.setWidth_eq]

theorem fit64 (x : BitVec 64) : x.toNat < 256 ^ (Access.word .m64).bytes := by
  have := x.isLt
  simp only [Access.bytes, MemWidth.bytes]
  omega

theorem fit32 {x : BitVec 64} (h : x.toNat < 2 ^ 32) : x.toNat < 256 ^ (Access.word .m32).bytes := by
  simp only [Access.bytes, MemWidth.bytes]
  omega

theorem widen_lt (a : BitVec 32) : (widen a).toNat < 2 ^ 32 := by
  simp only [widen, BitVec.toNat_setWidth]
  have := a.isLt
  omega

theorem fieldsHomeOk_replicate {e : SrcType} (h : e.homeOk = true) : ∀ n, fieldsHomeOk (List.replicate n e) = true
  | 0 => rfl
  | n + 1 => by simp [List.replicate_succ, fieldsHomeOk, h, fieldsHomeOk_replicate h n]

theorem fieldsTagsFit_replicate {e : SrcType} (h : e.tagsFit = true) : ∀ n, fieldsTagsFit (List.replicate n e) = true
  | 0 => rfl
  | n + 1 => by simp [List.replicate_succ, fieldsTagsFit, h, fieldsTagsFit_replicate h n]

/-- A scalar slot equal to its value truncated to a width it fits. -/
theorem slot_trunc {env₂ : Env} {q : Nat} {x : BitVec 64} {b : Nat} (h : env₂ q = BitVec.ofNat 64 (x.toNat % 256 ^ b))
    (fit : x.toNat < 256 ^ b) : env₂ q = x := by
  rw [h, trunc_fit fit]

mutual
/-- A held value of a homed type is still held after each slot is cut to
its access width: the slots that matter fit their widths. -/
theorem SrcType.HoldsAt.trunc : ∀ {ty : SrcType} {v : Value} {env : Env} {slot : Nat},
    ty.HoldsAt sx places v env slot → ty.homeOk = true → ty.tagsFit = true → ∀ {env₂ : Env} {slot₂ : Nat},
      (∀ i < ty.size, env₂ (slot₂ + i) = BitVec.ofNat 64 ((env (slot + i)).toNat % 256 ^ (ty.slotAt i).2.bytes)) →
      ty.HoldsAt sx places v env₂ slot₂
  | .i32, _, env, slot, .i32 holds, _, _, _, _, agree => by
    have h := agree 0 (by simp [SrcType.size])
    simp only [Nat.add_zero] at h
    have fit : (env slot).toNat < 256 ^ (SrcType.i32.slotAt 0).2.bytes := by
      simp only [SrcType.slotAt, widthOf, wordWidth]
      exact fit32 (by rw [holds.2]; exact widen_lt _)
    exact .i32 (by rw [slot_trunc h fit]; exact holds)
  | .bool, _, env, slot, .bool holds, _, _, _, _, agree => by
    have h := agree 0 (by simp [SrcType.size])
    simp only [Nat.add_zero] at h
    have fit : (env slot).toNat < 256 ^ (SrcType.bool.slotAt 0).2.bytes := by
      simp only [SrcType.slotAt, widthOf, wordWidth]
      obtain ⟨b, -, hb⟩ := holds
      apply fit32
      rw [hb]
      cases b <;> simp [boolBits]
    exact .bool (by rw [slot_trunc h fit]; exact holds)
  | .uint kind, _, env, slot, .uint holds, _, _, _, _, agree => by
    have h := agree 0 (by simp [SrcType.size])
    simp only [Nat.add_zero] at h
    have fit : (env slot).toNat < 256 ^ ((SrcType.uint kind).slotAt 0).2.bytes := by
      have b := holds.2
      cases kind with
      | uint64 => exact fit64 _
      | usize => exact fit64 _
      | uint8 =>
        simp only [UintTy.width] at b
        exact fit32 (by omega)
      | uint16 =>
        simp only [UintTy.width] at b
        exact fit32 (by omega)
      | uint32 =>
        simp only [UintTy.width] at b
        exact fit32 (by omega)
    exact .uint (by rw [slot_trunc h fit]; exact holds)
  | .struct _ fields, _, _, _, .struct holds, home, tags, _, _, agree =>
    .struct (FieldsHold.trunc holds (by simpa [SrcType.homeOk] using home)
      (by simpa [SrcType.tagsFit] using tags) fun i below => by
        rw [agree i (by simpa [SrcType.size] using below)]
        simp only [SrcType.slotAt]
        rw [fieldsSlotAt_access _ _ _ 0 0])
  | .enum eid variants, _, env, slot, @SrcType.HoldsAt.enum _ _ _ _ k fs vs _ _ found tag payload, home, tags, _,
      slot₂, agree => by
    simp only [SrcType.homeOk, Bool.and_eq_true] at home
    simp only [SrcType.tagsFit, Bool.and_eq_true, decide_eq_true_eq] at tags
    have bound := sizes_le_maxSize found
    have klt : k < 2 ^ 32 := by
      have := (List.getElem?_eq_some_iff.mp found).1
      omega
    refine .enum found ?_ (FieldsHold.trunc payload
      (fieldsHomeOk_of_uniform _ (variantsUniform_get home.1 found)) (variantsTagsFit_get tags.2 found)
      fun i below => ?_)
    · have h := agree 0 (by simp only [SrcType.size]; omega)
      simp only [Nat.add_zero] at h
      have fit : (env slot).toNat < 256 ^ ((SrcType.enum eid variants).slotAt 0).2.bytes := by
        rw [tag]
        simp only [SrcType.slotAt]
        apply fit32
        rw [BitVec.toNat_ofNat, Nat.mod_eq_of_lt (by omega)]
        exact klt
      rw [slot_trunc h fit, tag]
    · have h := agree (i + 1) (by simp only [SrcType.size]; omega)
      rw [show slot₂ + 1 + i = slot₂ + (i + 1) by omega, h, show slot + 1 + i = slot + (i + 1) by omega]
      simp only [SrcType.slotAt]
      rw [variantsWidths_getD _ home.1 home.2 found below,
        fieldsSlotAt_uniform _ (variantsUniform_get home.1 found) 0 0 i below]
  | .ptr, _, env, slot, .ptr holds, _, _, _, _, agree => by
    have h := agree 0 (by simp [SrcType.size])
    simp only [Nat.add_zero] at h
    exact .ptr (by rw [slot_trunc h (fit64 _)]; exact holds)
  | .slice _, _, env, slot, .slice len small, _, _, env₂, slot₂, agree => by
    have h0 := agree 0 (by simp [SrcType.size])
    have h1 := agree 1 (by simp [SrcType.size])
    simp only [Nat.add_zero] at h0
    have e0 : env₂ slot₂ = env slot := slot_trunc h0 (fit64 _)
    have e1 : env₂ (slot₂ + 1) = env (slot + 1) := slot_trunc h1 (fit64 _)
    rw [← e0]
    exact .slice (by rw [e1]; exact len) small
  | .slice _, _, env, slot, .borrowed mem sliced root ty packed pointer len small, _, _, env₂, slot₂, agree => by
    have h0 := agree 0 (by simp [SrcType.size])
    have h1 := agree 1 (by simp [SrcType.size])
    simp only [Nat.add_zero] at h0
    exact .borrowed mem sliced root ty packed (by rw [slot_trunc h0 (fit64 _)]; exact pointer)
      (by rw [slot_trunc h1 (fit64 _)]; exact len) small
  | .array element length, _, env, slot, @SrcType.HoldsAt.array _ _ _ _ vs _ _ holds, home, tags, env₂, slot₂,
      agree => by
    simp only [SrcType.homeOk] at home
    simp only [SrcType.tagsFit] at tags
    cases hn : element.accessKind.narrow with
    | true =>
      refine .array (FieldsHold.congr holds fun i below => ?_)
      rw [sizes_replicate] at below
      have len := holds.length
      simp only [List.length_replicate] at len
      rcases SrcType.narrow_cases hn with rfl | rfl
      · simp only [SrcType.size, Nat.mul_one] at below
        have hv := fieldsHold_replicate_get holds (List.getElem?_eq_getElem (l := vs) (by omega : i < vs.length))
        simp only [SrcType.size, Nat.mul_one] at hv
        cases hv with
        | i32 held =>
          refine slot_trunc (agree i (by simp only [SrcType.size]; omega)) ?_
          simp only [SrcType.slotAt, SrcType.accessKind, Access.narrow, if_true]
          exact fit32 (by rw [held.2]; exact widen_lt _)
      · simp only [SrcType.size, Nat.mul_one] at below
        have hv := fieldsHold_replicate_get holds (List.getElem?_eq_getElem (l := vs) (by omega : i < vs.length))
        simp only [SrcType.size, Nat.mul_one] at hv
        cases hv with
        | uint held =>
          refine slot_trunc (agree i (by simp only [SrcType.size]; omega)) ?_
          simp only [SrcType.slotAt, SrcType.accessKind, Access.narrow, if_true, Access.bytes]
          have := held.2
          simp only [UintTy.width] at this
          omega
    | false =>
      refine .array (FieldsHold.trunc holds (fieldsHomeOk_replicate home _) (fieldsTagsFit_replicate tags _)
        fun i below => ?_)
      rw [sizes_replicate] at below
      rw [agree i (by simpa [SrcType.size] using below)]
      simp only [SrcType.slotAt, hn, Bool.false_eq_true, if_false]
      rw [fieldsSlotAt_replicate _ _ _ _ _ below]
  | .unit, _, _, _, .unit, _, _, _, _, _ => .unit
  | .isize, _, env, slot, .isize holds, _, _, _, _, agree => by
    have h := agree 0 (by simp [SrcType.size])
    simp only [Nat.add_zero] at h
    exact .isize (by rw [slot_trunc h (fit64 _)]; exact holds)
  | .char, _, env, slot, .char holds, _, _, _, _, agree => by
    have h := agree 0 (by simp [SrcType.size])
    simp only [Nat.add_zero] at h
    exact .char (by rw [slot_trunc h (fit64 _)]; exact holds)
  | .float _, _, env, slot, .float holds, _, _, _, _, agree => by
    have h := agree 0 (by simp [SrcType.size])
    simp only [Nat.add_zero] at h
    exact .float (by rw [slot_trunc h (fit64 _)]; exact holds)
  | .sint kind, _, env, slot, .sint holds, _, _, _, _, agree => by
    have h := agree 0 (by simp [SrcType.size])
    simp only [Nat.add_zero] at h
    have fit : (env slot).toNat < 256 ^ ((SrcType.sint kind).slotAt 0).2.bytes := by
      cases kind with
      | uint64 => exact fit64 _
      | usize => exact fit64 _
      | uint8 => exact fit32 (by rw [holds.2.1]; exact widen_lt _)
      | uint16 => exact fit32 (by rw [holds.2.1]; exact widen_lt _)
      | uint32 => exact fit32 (by rw [holds.2.1]; exact widen_lt _)
    exact .sint (by rw [slot_trunc h fit]; exact holds)
  | .view _, _, _, _, .view len i32s, _, _, _, _, _ => .view len i32s
  | .str, _, env, slot, .str pointer len small bytes, _, _, _, _, agree => by
    have h0 := agree 0 (by simp [SrcType.size])
    have h1 := agree 1 (by simp [SrcType.size])
    simp only [Nat.add_zero] at h0
    exact .str (by rw [slot_trunc h0 (fit64 _)]; exact pointer) (by rw [slot_trunc h1 (fit64 _)]; exact len)
      small bytes
  | .ref _, _, env, slot, .ref held, _, _, _, _, agree => by
    have h := agree 0 (by simp [SrcType.size])
    simp only [Nat.add_zero] at h
    exact .ref (by rw [slot_trunc h (fit64 _)]; exact held)

theorem FieldsHold.trunc : ∀ {fs : List SrcType} {vs : List Value} {env : Env} {slot : Nat},
    FieldsHold sx places fs vs env slot → fieldsHomeOk fs = true → fieldsTagsFit fs = true →
    ∀ {env₂ : Env} {slot₂ : Nat},
      (∀ i < sizes fs, env₂ (slot₂ + i) =
        BitVec.ofNat 64 ((env (slot + i)).toNat % 256 ^ (fieldsSlotAt 0 0 fs i).2.bytes)) →
      FieldsHold sx places fs vs env₂ slot₂
  | [], _, _, _, .nil, _, _, _, _, _ => .nil
  | t :: rest, _, env, slot, .cons head tail, home, tags, env₂, slot₂, agree => by
    simp only [fieldsHomeOk, Bool.and_eq_true] at home
    simp only [fieldsTagsFit, Bool.and_eq_true] at tags
    refine .cons (SrcType.HoldsAt.trunc head home.1 tags.1 fun i below => ?_)
      (FieldsHold.trunc tail home.2 tags.2 fun i below => ?_)
    · rw [agree i (by simp only [sizes]; omega)]
      simp only [fieldsSlotAt, below, if_true]
    · have h := agree (t.size + i) (by simp only [sizes]; omega)
      rw [show slot₂ + t.size + i = slot₂ + (t.size + i) by omega, h, show slot + t.size + i = slot + (t.size + i) by omega]
      simp only [fieldsSlotAt, show ¬ (t.size + i < t.size) by omega, if_false, Nat.add_sub_cancel_left]
      rw [fieldsSlotAt_access _ _ _ 0 0]
end

/-! ## Cells -/

theorem find_replaceCell_ne : ∀ (cs : List Semantics.Cell) {c c' : Nat} (w : Value), c' ≠ c →
    (Semantics.replaceCell cs c w).find? (fun cell => cell.id == c') = cs.find? (fun cell => cell.id == c')
  | [], _, _, _, _ => rfl
  | cell :: rest, c, c', w, ne => by
    simp only [Semantics.replaceCell]
    by_cases h : cell.id = c
    · have hb : (c == c') = false := by simpa using Ne.symm ne
      simp [h, find_replaceCell_ne rest w ne, hb]
    · simp [h, List.find?_cons, find_replaceCell_ne rest w ne]

theorem find_replaceCell_self : ∀ (cs : List Semantics.Cell) (c : Nat) (w : Value) (ent : Semantics.Cell),
    cs.find? (fun cell => cell.id == c) = some ent →
    (Semantics.replaceCell cs c w).find? (fun cell => cell.id == c) = some { ent with value := some w }
  | [], _, _, _, h => by simp at h
  | cell :: rest, c, w, ent, h => by
    simp only [Semantics.replaceCell]
    by_cases hc : cell.id = c
    · simp only [List.find?_cons, hc, beq_self_eq_true] at h
      simp only [Option.some.injEq] at h
      subst h
      simp [hc]
    · have hb : (cell.id == c) = false := by simpa using hc
      simp only [List.find?_cons, hb] at h
      simp [hc, find_replaceCell_self rest c w ent h]

/-- `assignCell` gives the cell its new value and keeps every other cell and
the views. -/
theorem assignCell_read {st st' : State} {c : Nat} {w : Value} (h : st.assignCell c w = some st') :
    Semantics.readCellProjection st' c [] = .ok w ∧
      (∀ c' path, c' ≠ c → Semantics.readCellProjection st' c' path = Semantics.readCellProjection st c' path) ∧
      st'.i32ArrayViews = st.i32ArrayViews := by
  unfold Semantics.State.assignCell at h
  split at h
  · rename_i some_
    simp only [Option.some.injEq] at h
    subst h
    obtain ⟨ent, hent⟩ := Option.isSome_iff_exists.mp some_
    refine ⟨?_, fun c' path ne => ?_, rfl⟩
    · simp only [Semantics.readCellProjection, Semantics.State.cellEntry?]
      unfold Semantics.State.cellEntry? at hent
      rw [find_replaceCell_self _ _ _ _ hent]
      simp [Semantics.projectedValue]
    · simp only [Semantics.readCellProjection, Semantics.State.cellEntry?]
      rw [find_replaceCell_ne _ w ne]
  · cases h

/-! ## Stores -/

theorem Heap.writeLE_others : ∀ (hp : Heap) (a v n : Nat), { hp.writeLE a v n with bytes := hp.bytes } = hp
  | _, _, _, 0 => rfl
  | hp, a, v, n + 1 => by
    simp only [Heap.writeLE]
    have ih := Heap.writeLE_others (hp.write a (UInt8.ofNat v)) (a + 1) (v / 256) n
    calc { (hp.write a (UInt8.ofNat v)).writeLE (a + 1) (v / 256) n with bytes := hp.bytes }
        = { { (hp.write a (UInt8.ofNat v)).writeLE (a + 1) (v / 256) n with
              bytes := (hp.write a (UInt8.ofNat v)).bytes } with bytes := hp.bytes } := rfl
      _ = { hp.write a (UInt8.ofNat v) with bytes := hp.bytes } := by rw [ih]
      _ = hp := rfl

theorem Heap.top_of_others {hp hp' : Heap} (h : { hp' with bytes := hp.bytes } = hp) :
    hp'.top = hp.top ∧ hp'.fsp = hp.fsp ∧ hp'.limit = hp.limit ∧ hp'.staticBase = hp.staticBase ∧
      hp'.statics = hp.statics := by
  rw [← h]
  exact ⟨rfl, rfl, rfl, rfl, rfl⟩

theorem Access.store_exec {prog : Program} {depth : Nat} (acc : Access) {address value : Expr}
    {env : Env} {hp : Heap} (inside : (address.eval env).toNat + acc.bytes ≤ hp.top) :
    Exec prog depth env hp (acc.store address value)
      (.normal env (hp.writeLE (address.eval env).toNat (value.eval env).toNat acc.bytes)) := by
  cases acc with
  | byte =>
    have := Exec.storeByte (prog := prog) (depth := depth) (address := address) (value := value)
      (env := env) (heap := hp) (by simp only [Access.bytes] at inside; omega)
    have same : hp.write (address.eval env).toNat (lowByte (value.eval env)) =
        hp.writeLE (address.eval env).toNat (value.eval env).toNat 1 := by
      simp only [Heap.writeLE]
      congr 1
      apply UInt8.toNat_inj.mp
      rw [show (lowByte (value.eval env)).toNat = (value.eval env).toNat % 256 by
        simp [lowByte, BitVec.toNat_setWidth], UInt8.toNat_ofNat']
    simpa [Access.store, Access.bytes, same] using this
  | word w => exact Exec.storeWord inside

/-- The stores of a reference's write, each slot at `refSlotAt`, into slot
ranges that lie apart: each range then holds its slot's low bytes, and no
byte outside the ranges changes. -/
theorem SrcType.storesFrom_exec {prog : Program} {depth : Nat} (ty : SrcType) {r slot address : Nat} :
    ∀ (count s : Nat) (env : Env) (hp : Heap), (env r).toNat = address →
      (∀ i, s ≤ i → i < s + count →
        address + (ty.refSlotAt i).1 + (ty.refSlotAt i).2.bytes ≤ hp.top ∧ address + (ty.refSlotAt i).1 < 2 ^ 64) →
      (∀ i i', s ≤ i → i < s + count → s ≤ i' → i' < s + count → i ≠ i' →
        (ty.refSlotAt i).1 + (ty.refSlotAt i).2.bytes ≤ (ty.refSlotAt i').1 ∨
          (ty.refSlotAt i').1 + (ty.refSlotAt i').2.bytes ≤ (ty.refSlotAt i).1) →
      ∃ hp', Exec prog depth env hp (ty.storesFrom r slot s count) (.normal env hp') ∧
        { hp' with bytes := hp.bytes } = hp ∧
        (∀ b, (∀ i, s ≤ i → i < s + count →
          b < address + (ty.refSlotAt i).1 ∨ address + (ty.refSlotAt i).1 + (ty.refSlotAt i).2.bytes ≤ b) →
            hp'.bytes b = hp.bytes b) ∧
        (∀ i, s ≤ i → i < s + count →
          hp'.readLE (address + (ty.refSlotAt i).1) (ty.refSlotAt i).2.bytes =
            (env (slot + i)).toNat % 256 ^ (ty.refSlotAt i).2.bytes)
  | 0, s, env, hp, _, _, _ => ⟨hp, by simpa [SrcType.storesFrom] using Exec.skip, rfl, fun _ _ => rfl,
      fun i lo hi => by omega⟩
  | count + 1, s, env, hp, hr, fits, apart => by
    obtain ⟨top, lt⟩ := fits s (Nat.le_refl _) (by omega)
    have eval := addOff_eval (r := r) (off := (ty.refSlotAt s).1) hr lt
    have first := (ty.refSlotAt s).2.store_exec (prog := prog) (depth := depth)
      (address := addOff r (ty.refSlotAt s).1) (value := .var (slot + s)) (env := env) (hp := hp)
      (by rw [eval]; omega)
    rw [eval] at first
    simp only [Expr.eval] at first
    let hp1 := hp.writeLE (address + (ty.refSlotAt s).1) (env (slot + s)).toNat (ty.refSlotAt s).2.bytes
    have others1 : { hp1 with bytes := hp.bytes } = hp := Heap.writeLE_others _ _ _ _
    have top1 := (Heap.top_of_others others1).1
    obtain ⟨hp', run, others, outside, stored⟩ := SrcType.storesFrom_exec ty count (s + 1) env hp1 hr
      (fun i lo hi => by rw [top1]; exact fits i (by omega) (by omega))
      (fun i i' lo hi lo' hi' ne => apart i i' (by omega) (by omega) (by omega) (by omega) ne)
    refine ⟨hp', .seq first run, ?_, fun b away => ?_, fun i lo hi => ?_⟩
    · calc { hp' with bytes := hp.bytes } = { { hp' with bytes := hp1.bytes } with bytes := hp.bytes } := rfl
        _ = { hp1 with bytes := hp.bytes } := by rw [others]
        _ = hp := others1
    · rw [outside b (fun i lo hi => away i (by omega) (by omega))]
      exact Heap.writeLE_bytes_outside _ _ _ _ _ (away s (Nat.le_refl _) (by omega))
    · rcases Nat.lt_or_ge s i with gt | le
      · exact stored i (by omega) (by omega)
      · have : i = s := by omega
        subst this
        rw [Heap.readLE_congr (hp := hp1) (fun a lo' hi' => outside a (fun k lo hi => by
          rcases apart i k (Nat.le_refl _) (by omega) (by omega) (by omega) (by omega) with c | c <;> omega))]
        exact Heap.readLE_writeLE _ _ _ _

/-! ## Replacing a sub-value -/

theorem fieldOffset_replicate (e : SrcType) : ∀ (n i : Nat), i ≤ n → fieldOffset (List.replicate n e) i = i * e.size
  | n, 0, _ => by simp [fieldOffset_zero]
  | 0, i + 1, le => by omega
  | n + 1, i + 1, le => by
    rw [List.replicate_succ, fieldOffset_succ, fieldOffset_replicate e n i (by omega), Nat.succ_mul]
    omega

/-- Field `k` takes a new value held in new slots, the other fields' slots
unchanged. -/
theorem FieldsHold.setAt : ∀ {fs : List SrcType} {vs : List Value} {env : Env} {slot : Nat},
    FieldsHold sx places fs vs env slot → ∀ {k : Nat} {t : SrcType} {nv : Value} {env' : Env},
      fs[k]? = some t → t.HoldsAt sx places nv env' (slot + fieldOffset fs k) →
      (∀ q, slot ≤ q → q < slot + sizes fs → (q < slot + fieldOffset fs k ∨ slot + fieldOffset fs k + t.size ≤ q) →
        env' q = env q) →
      FieldsHold sx places fs (Semantics.setValue vs k nv) env' slot
  | [], _, _, _, .nil, _, _, _, _, found, _, _ => by simp at found
  | f :: rest, _ :: _, env, slot, .cons head tail, k, t, nv, env', found, held, away => by
    cases k with
    | zero =>
      simp only [List.getElem?_cons_zero, Option.some.injEq] at found
      subst found
      simp only [Semantics.setValue]
      refine .cons (by simpa [fieldOffset_zero] using held) (tail.congr fun i below => ?_)
      exact away _ (by omega) (by simp only [sizes]; omega) (.inr (by simp only [fieldOffset_zero]; omega))
    | succ k =>
      simp only [List.getElem?_cons_succ] at found
      simp only [Semantics.setValue]
      have := fieldOffset_add_le found
      refine .cons (head.congr fun i below => ?_) ?_
      · exact away _ (by omega) (by simp only [sizes]; omega) (.inl (by rw [fieldOffset_succ]; omega))
      · refine FieldsHold.setAt tail found ?_ fun q lo hi side => ?_
        · rw [show slot + f.size + fieldOffset rest k = slot + fieldOffset (f :: rest) (k + 1) by
            rw [fieldOffset_succ]; omega]
          exact held
        · exact away q (by omega) (by simp only [sizes]; omega) (by rw [fieldOffset_succ]; omega)

theorem replace_cons {root v root' : Value} {p : ValueProjection} {rest : List ValueProjection}
    (h : Semantics.replaceProjectedValue root (p :: rest) v = .ok root') :
    (∃ id vs f c, root = .structure id vs ∧ p = .field f ∧ vs[f]? = some c ∧ ∃ updated,
        Semantics.replaceProjectedValue c rest v = .ok updated ∧ root' = .structure id (Semantics.setValue vs f updated)) ∨
      (∃ vs i c, root = .array vs ∧ p = .index i ∧ vs[i]? = some c ∧ ∃ updated,
        Semantics.replaceProjectedValue c rest v = .ok updated ∧ root' = .array (Semantics.setValue vs i updated)) := by
  cases p with
  | field f =>
    cases root
    case «structure» id vs =>
      simp only [Semantics.replaceProjectedValue] at h
      cases hc : vs[f]? with
      | none => simp [hc] at h
      | some c =>
        simp only [hc] at h
        cases hu : Semantics.replaceProjectedValue c rest v with
        | error e => simp [hu] at h
        | ok updated =>
          simp only [hu, Except.ok.injEq] at h
          exact .inl ⟨id, vs, f, c, rfl, rfl, hc, updated, hu, h.symm⟩
    all_goals simp [Semantics.replaceProjectedValue] at h
  | index i =>
    cases root
    case array vs =>
      simp only [Semantics.replaceProjectedValue] at h
      cases hc : vs[i]? with
      | none => simp [hc] at h
      | some c =>
        simp only [hc] at h
        cases hu : Semantics.replaceProjectedValue c rest v with
        | error e => simp [hu] at h
        | ok updated =>
          simp only [hu, Except.ok.injEq] at h
          exact .inr ⟨vs, i, c, rfl, rfl, hc, updated, hu, h.symm⟩
    all_goals simp [Semantics.replaceProjectedValue] at h

/-- One projection, for a write: the child's old value is held `j` slots in,
inside the parent's slots, and a new child value held in new slots, the
parent's other slots unchanged, gives the parent's new value held. -/
theorem SrcType.step_replace {ty : SrcType} {p : ValueProjection} {o : Nat} {child : SrcType}
    (h : ty.subStep p = some (o, child)) {root v root' : Value} {E : Env} {k : Nat} {rest : List ValueProjection}
    (hold : ty.HoldsAt sx places root E k) (hr : Semantics.replaceProjectedValue root (p :: rest) v = .ok root') :
    ∃ j c, j + child.size ≤ ty.size ∧ child.HoldsAt sx places c E (k + j) ∧ SlotsIn ty j o child ∧
      Semantics.projectedValue root (p :: rest) = Semantics.projectedValue c rest ∧
      ∃ updated, Semantics.replaceProjectedValue c rest v = .ok updated ∧
        ∀ E' : Env, child.HoldsAt sx places updated E' (k + j) →
          (∀ q, k ≤ q → q < k + ty.size → (q < k + j ∨ k + j + child.size ≤ q) → E' q = E q) →
          ty.HoldsAt sx places root' E' k := by
  rcases replace_cons hr with ⟨id, vs, f, c, rfl, rfl, hc, updated, hu, rfl⟩ | ⟨vs, i, c, rfl, rfl, hc, updated, hu, rfl⟩
  · cases ty with
    | struct sid fields =>
      simp only [SrcType.subStep] at h
      split at h
      · rename_i fty hf
        simp only [Option.some.injEq, Prod.mk.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        cases hold with
        | struct hfields =>
          obtain ⟨c', hc', hchild⟩ := hfields.get hf
          rw [hc] at hc'
          cases hc'
          refine ⟨fieldOffset fields f, c, by simpa [SrcType.size] using fieldOffset_add_le hf, hchild,
            fun s lt => .inl ?_, by simp [Semantics.projectedValue, hc], updated, hu, fun E' held away => ?_⟩
          · simp only [SrcType.slotAt]
            rw [fieldsSlotAt_get _ 0 hf lt, Nat.zero_add]
          · exact .struct (hfields.setAt hf held fun q lo hi side => away q lo (by simpa [SrcType.size] using hi) side)
      · cases h
    | array e n => simp [SrcType.subStep] at h
    | i32 => simp [SrcType.subStep] at h
    | bool => simp [SrcType.subStep] at h
    | uint => simp [SrcType.subStep] at h
    | enum => simp [SrcType.subStep] at h
    | ptr => simp [SrcType.subStep] at h
    | slice => simp [SrcType.subStep] at h
    | unit => simp [SrcType.subStep] at h
    | isize => simp [SrcType.subStep] at h
    | char => simp [SrcType.subStep] at h
    | float => simp [SrcType.subStep] at h
    | sint => simp [SrcType.subStep] at h
    | view => simp [SrcType.subStep] at h
    | str | ref => simp [SrcType.subStep] at h
  · cases ty with
    | array e n =>
      simp only [SrcType.subStep] at h
      split at h
      · rename_i lt
        cases hold with
        | array hfields =>
          have hchild := fieldsHold_replicate_get hfields hc
          have room : (i + 1) * e.size ≤ n * e.size := Nat.mul_le_mul_right _ lt
          rw [Nat.succ_mul] at room
          have get : (List.replicate n e)[i]? = some e := by simp [lt]
          have off := fieldOffset_replicate e n i (by omega)
          have slots : SlotsIn (.array e n) (i * e.size) o child ∧ child = e := by
            cases hn : e.accessKind.narrow with
            | true =>
              simp only [hn, if_true, Option.some.injEq, Prod.mk.injEq] at h
              obtain ⟨rfl, rfl⟩ := h
              refine ⟨fun s slt => ?_, rfl⟩
              rcases SrcType.narrow_cases hn with rfl | rfl
              · left
                simp only [SrcType.size] at slt
                obtain rfl : s = 0 := by omega
                simp [SrcType.slotAt, SrcType.size, SrcType.accessKind, Access.narrow, widthOf, wordWidth]
              · right
                simp only [SrcType.size] at slt
                obtain rfl : s = 0 := by omega
                simp [SrcType.slotAt, SrcType.size, SrcType.accessKind, Access.narrow, Access.bytes]
            | false =>
              simp only [hn, Bool.false_eq_true, if_false, Option.some.injEq, Prod.mk.injEq] at h
              obtain ⟨rfl, rfl⟩ := h
              refine ⟨fun s slt => .inl ?_, rfl⟩
              have pos : 0 < e.size := by omega
              have d : (i * e.size + s) / e.size = i := by
                rw [Nat.mul_comm, Nat.mul_add_div pos, Nat.div_eq_of_lt slt, Nat.add_zero]
              have m : (i * e.size + s) % e.size = s := by
                rw [Nat.mul_comm, Nat.mul_add_mod, Nat.mod_eq_of_lt slt]
              simp only [SrcType.slotAt, hn, Bool.false_eq_true, if_false, d, m]
          obtain ⟨slots, rfl⟩ := slots
          refine ⟨i * child.size, c, by simp only [SrcType.size]; omega, hchild, slots,
            by simp [Semantics.projectedValue, hc], updated, hu, fun E' held away => ?_⟩
          refine .array (hfields.setAt get (by rw [off]; exact held) fun q lo hi side => ?_)
          rw [sizes_replicate] at hi
          exact away q lo (by simpa [SrcType.size] using hi) (by rw [off] at side; exact side)
      · cases h
    | struct sid fields => simp [SrcType.subStep] at h
    | i32 => simp [SrcType.subStep] at h
    | bool => simp [SrcType.subStep] at h
    | uint => simp [SrcType.subStep] at h
    | enum => simp [SrcType.subStep] at h
    | ptr => simp [SrcType.subStep] at h
    | slice => simp [SrcType.subStep] at h
    | unit => simp [SrcType.subStep] at h
    | isize => simp [SrcType.subStep] at h
    | char => simp [SrcType.subStep] at h
    | float => simp [SrcType.subStep] at h
    | sint => simp [SrcType.subStep] at h
    | view => simp [SrcType.subStep] at h
    | str | ref => simp [SrcType.subStep] at h

/-- Down a projection path, for a write: the old sub-value is held `j` slots
into its parent's (`SlotsIn`), and a new one held in new slots, the
parent's other slots unchanged, gives the root's new value held. -/
theorem SrcType.sub_replace : ∀ (path : List ValueProjection) {ty t : SrcType} {off : Nat} {root v root' : Value}
    {E : Env} {k : Nat},
    ty.sub path = some (off, t) → ty.HoldsAt sx places root E k →
    Semantics.replaceProjectedValue root path v = .ok root' →
    ∃ j old, j + t.size ≤ ty.size ∧ Semantics.projectedValue root path = .ok old ∧
      t.HoldsAt sx places old E (k + j) ∧ SlotsIn ty j off t ∧
      ∀ E' : Env, t.HoldsAt sx places v E' (k + j) →
        (∀ q, k ≤ q → q < k + ty.size → (q < k + j ∨ k + j + t.size ≤ q) → E' q = E q) →
        ty.HoldsAt sx places root' E' k
  | [], ty, t, off, root, v, root', E, k, hsub, hold, hr => by
    simp only [SrcType.sub, Option.some.injEq, Prod.mk.injEq] at hsub
    obtain ⟨rfl, rfl⟩ := hsub
    simp only [Semantics.replaceProjectedValue, Except.ok.injEq] at hr
    subst hr
    exact ⟨0, root, by omega, by simp [Semantics.projectedValue], by simpa using hold,
      fun s _ => .inl (by simp), fun E' held _ => by simpa using held⟩
  | p :: rest, ty, t, off, root, v, root', E, k, hsub, hold, hr => by
    obtain ⟨o, child, inner, hstep, hrest, rfl⟩ := SrcType.sub_cons hsub
    obtain ⟨j₁, c, hj₁, hchild, slots₁, hproj, updated, hu, rebuild⟩ := SrcType.step_replace hstep hold hr
    obtain ⟨j₂, old, hj₂, hold₂, ht, slots₂, rebuild₂⟩ := SrcType.sub_replace rest hrest hchild hu
    refine ⟨j₁ + j₂, old, by omega, by rw [hproj]; exact hold₂, by simpa [Nat.add_assoc] using ht,
      fun s lt => ?_, fun E' held away => ?_⟩
    · rw [Nat.add_assoc]
      rcases slots₁ (j₂ + s) (by omega) with eq₁ | ⟨rfl, eq₁⟩
      · rw [eq₁]
        rcases slots₂ s lt with eq₂ | ⟨rfl, eq₂⟩
        · rw [eq₂]
          left
          simp [Nat.add_assoc]
        · rw [eq₂]
          right
          exact ⟨rfl, rfl⟩
      · obtain ⟨rfl, rfl⟩ := SrcType.sub_u8 hrest
        right
        simpa using eq₁
    · refine rebuild E' (rebuild₂ E' (by simpa [Nat.add_assoc] using held) fun q lo hi side =>
        away q (by omega) (by omega) (by omega)) fun q lo hi side => away q lo hi (by omega)

/-! ## The referent -/

/-- A sub-place of a homed type is homed. -/
theorem SrcType.sub_homeOk : ∀ (path : List ValueProjection) {ty t : SrcType} {off : Nat},
    ty.homeOk = true → ty.sub path = some (off, t) → t.homeOk = true
  | [], ty, t, off, h, hsub => by
    simp only [SrcType.sub, Option.some.injEq, Prod.mk.injEq] at hsub
    obtain ⟨-, rfl⟩ := hsub
    exact h
  | p :: rest, ty, t, off, h, hsub => by
    obtain ⟨o, child, inner, hstep, hrest, -⟩ := SrcType.sub_cons hsub
    refine SrcType.sub_homeOk rest ?_ hrest
    cases ty with
    | struct sid fields =>
      cases p with
      | index _ => simp [SrcType.subStep] at hstep
      | field f =>
        simp only [SrcType.subStep] at hstep
        split at hstep
        · rename_i fty hf
          simp only [Option.some.injEq, Prod.mk.injEq] at hstep
          obtain ⟨-, rfl⟩ := hstep
          exact fieldsHomeOk_get (by simpa [SrcType.homeOk] using h) hf
        · cases hstep
    | array e n =>
      cases p with
      | field _ => simp [SrcType.subStep] at hstep
      | index i =>
        simp only [SrcType.subStep] at hstep
        split at hstep
        · split at hstep
          all_goals
            simp only [Option.some.injEq, Prod.mk.injEq] at hstep
            obtain ⟨-, rfl⟩ := hstep
            simpa [SrcType.homeOk] using h
        · cases hstep
    | i32 => simp [SrcType.subStep] at hstep
    | bool => simp [SrcType.subStep] at hstep
    | uint => simp [SrcType.subStep] at hstep
    | enum => simp [SrcType.subStep] at hstep
    | ptr => simp [SrcType.subStep] at hstep
    | slice => simp [SrcType.subStep] at hstep
    | unit => simp [SrcType.subStep] at hstep
    | isize => simp [SrcType.subStep] at hstep
    | char => simp [SrcType.subStep] at hstep
    | float => simp [SrcType.subStep] at hstep
    | sint => simp [SrcType.subStep] at hstep
    | view => simp [SrcType.subStep] at hstep
    | str | ref => simp [SrcType.subStep] at hstep

theorem SrcType.refSlots_apart {ty : SrcType} (h : ty.homeOk = true) (s s' : Nat) (hs : s < ty.size)
    (hs' : s' < ty.size) (ne : s ≠ s') :
    (ty.refSlotAt s).1 + (ty.refSlotAt s).2.bytes ≤ (ty.refSlotAt s').1 ∨
      (ty.refSlotAt s').1 + (ty.refSlotAt s').2.bytes ≤ (ty.refSlotAt s).1 := by
  cases hu : ty.isUint .uint8 with
  | true =>
    obtain rfl := SrcType.isUint_u8 hu
    simp only [SrcType.size] at hs hs'
    omega
  | false =>
    rw [SrcType.refSlotAt_other hu, SrcType.refSlotAt_other hu]
    exact SrcType.slots_apart ty h s s' hs hs' ne

/-- A reference's write of a `ty` touches only its `span`. -/
theorem SrcType.refSlot_in_span (ty : SrcType) (s : Nat) (lt : s < ty.size) :
    (ty.refSlotAt s).1 + (ty.refSlotAt s).2.bytes ≤ ty.span := by
  cases hu : ty.isUint .uint8 with
  | true =>
    obtain rfl := SrcType.isUint_u8 hu
    simp [SrcType.refSlotAt_u8, SrcType.span, Access.bytes]
  | false =>
    rw [SrcType.refSlotAt_other hu]
    have fits := SrcType.slot_fits ty s lt
    cases ty with
    | i32 => simp [SrcType.slotAt, SrcType.span, Access.bytes]
    | bool => simp [SrcType.slotAt, SrcType.span, Access.bytes]
    | uint kind =>
      simp only [SrcType.span, SrcType.refSlotAt_other hu]
      simp [SrcType.slotAt]
    | sint kind => simp [SrcType.slotAt, SrcType.span, Access.bytes]
    | array e n =>
      cases hn : e.accessKind.narrow with
      | true =>
        simp only [SrcType.size] at lt
        rcases SrcType.narrow_cases hn with rfl | rfl
        · simp only [SrcType.size, Nat.mul_one] at lt
          simp only [SrcType.slotAt, SrcType.span, SrcType.accessKind, Access.narrow, if_true, Access.bytes,
            MemWidth.bytes]
          omega
        · simp only [SrcType.size, Nat.mul_one] at lt
          simp only [SrcType.slotAt, SrcType.span, SrcType.accessKind, Access.narrow, if_true, Access.bytes]
          omega
      | false =>
        simp only [SrcType.span, hn, Bool.false_eq_true, if_false]
        exact fits
    | struct => simpa [SrcType.span] using fits
    | enum => simpa [SrcType.span] using fits
    | ptr => simpa [SrcType.span] using fits
    | slice => simpa [SrcType.span] using fits
    | unit => simpa [SrcType.span] using fits
    | isize => simpa [SrcType.span] using fits
    | char => simpa [SrcType.span] using fits
    | float => simpa [SrcType.span] using fits
    | view => simpa [SrcType.span] using fits
    | str | ref => simpa [SrcType.span] using fits

/-- A referent slot lies at the start of its parent slot and is no wider. -/
theorem SlotsIn.ref {ty t : SrcType} {j off : Nat} (h : SlotsIn ty j off t) (s : Nat) (lt : s < t.size) :
    off + (t.refSlotAt s).1 = (ty.slotAt (j + s)).1 ∧ (t.refSlotAt s).2.bytes ≤ (ty.slotAt (j + s)).2.bytes := by
  cases hu : t.isUint .uint8 with
  | false =>
    rw [SrcType.refSlotAt_other hu]
    rcases h s lt with eq | ⟨rfl, -⟩
    · simp [eq]
    · simp [SrcType.isUint, UintTy.code] at hu
  | true =>
    obtain rfl := SrcType.isUint_u8 hu
    rw [SrcType.refSlotAt_u8]
    rcases h s lt with eq | ⟨-, eq⟩
    · rw [SrcType.slotAt_u8] at eq
      simp [eq, Access.bytes, MemWidth.bytes_m32]
    · simp [eq]

/-! ## A home's first store -/

/-- The type a new home's first store writes (`homeInit` in lowering-spec
S6b): a `u8` as a `u32`, so its 4-byte native word (`slotAt`) gets zero
upper bytes; every other type as itself, whose `refSlotAt` is already
`slotAt`. -/
def SrcType.homeInit (ty : SrcType) : SrcType := if ty.isUint .uint8 then .uint .uint32 else ty

theorem SrcType.homeInit_size (ty : SrcType) : ty.homeInit.size = ty.size := by
  unfold SrcType.homeInit
  cases hu : ty.isUint .uint8 with
  | false => rfl
  | true => obtain rfl := SrcType.isUint_u8 hu; rfl

/-- The first store writes each slot at its native place and width. -/
theorem SrcType.homeInit_refSlotAt (ty : SrcType) (s : Nat) : ty.homeInit.refSlotAt s = ty.slotAt s := by
  unfold SrcType.homeInit
  cases hu : ty.isUint .uint8 with
  | false => simp only [Bool.false_eq_true, if_false]; exact SrcType.refSlotAt_other hu s
  | true =>
    obtain rfl := SrcType.isUint_u8 hu
    simp [SrcType.refSlotAt, SrcType.isUint, UintTy.code, SrcType.slotAt, widthOf, wordWidth, usizeWidth]

end Lanius.Mini
