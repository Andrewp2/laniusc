import Lanius.Mini.HeapCorr

/-!
# Slice elements in Core's native layout: the word fields

A struct slice element, or an enum payload, is laid out by its leaves, word
fields (`i32`, `bool`, `u8`, `u32`, `u64`, `usize`, `isize`, `ptr`; `wordWidth`)
of one 8-byte word each (`FlatLayout`). This file has the facts about one
word: its widths (`leafWidths`), Core's read and write of it in the slot the
mini code fills, and the mini side's element and field addresses.
-/

namespace Lanius.Mini

open Lanius.Core (Value)

mutual
theorem SrcType.eq_of_same : ∀ (a : SrcType) {b : SrcType}, a.same b = true → a = b
  | .i32, b, same => by cases b <;> simp_all [SrcType.same, SrcType.isI32]
  | .bool, b, same => by cases b <;> simp_all [SrcType.same, SrcType.isBool]
  | .uint k, b, same => (SrcType.eq_of_isUint (by simpa [SrcType.same] using same)).symm
  | .ptr, b, same => by cases b <;> simp_all [SrcType.same, SrcType.isPtr]
  | .struct id fs, b, same => by
    cases b with
    | struct id' gs =>
      simp only [SrcType.same, Bool.and_eq_true, decide_eq_true_eq] at same
      rw [same.1, typesSame_eq fs same.2]
    | i32 => simp [SrcType.same] at same
    | bool => simp [SrcType.same] at same
    | uint => simp [SrcType.same] at same
    | enum => simp [SrcType.same] at same
    | ptr => simp [SrcType.same] at same
    | slice => simp [SrcType.same] at same
    | unit => simp [SrcType.same] at same
    | isize => simp [SrcType.same] at same
  | .enum id vs, b, same => by
    cases b with
    | enum id' ws =>
      simp only [SrcType.same, Bool.and_eq_true, decide_eq_true_eq] at same
      rw [same.1, variantsSame_eq vs same.2]
    | i32 => simp [SrcType.same] at same
    | bool => simp [SrcType.same] at same
    | uint => simp [SrcType.same] at same
    | struct => simp [SrcType.same] at same
    | ptr => simp [SrcType.same] at same
    | slice => simp [SrcType.same] at same
    | unit => simp [SrcType.same] at same
    | isize => simp [SrcType.same] at same
  | .slice e, b, same => by
    cases b with
    | slice e' =>
      simp only [SrcType.same] at same
      rw [SrcType.eq_of_same e same]
    | i32 => simp [SrcType.same] at same
    | bool => simp [SrcType.same] at same
    | uint => simp [SrcType.same] at same
    | struct => simp [SrcType.same] at same
    | enum => simp [SrcType.same] at same
    | ptr => simp [SrcType.same] at same
    | unit => simp [SrcType.same] at same
    | isize => simp [SrcType.same] at same
  | .unit, b, same => by cases b <;> simp_all [SrcType.same, SrcType.isUnit]
  | .isize, b, same => by cases b <;> simp_all [SrcType.same, SrcType.isIsize]

theorem typesSame_eq : ∀ (fs : List SrcType) {gs : List SrcType}, typesSame fs gs = true → fs = gs
  | [], gs, same => by cases gs <;> simp_all [typesSame]
  | f :: fs, gs, same => by
    cases gs with
    | nil => simp [typesSame] at same
    | cons g gs =>
      simp only [typesSame, Bool.and_eq_true] at same
      rw [SrcType.eq_of_same f same.1, typesSame_eq fs same.2]

theorem variantsSame_eq : ∀ (vs : List (List SrcType)) {ws : List (List SrcType)},
    variantsSame vs ws = true → vs = ws
  | [], ws, same => by cases ws <;> simp_all [variantsSame]
  | v :: vs, ws, same => by
    cases ws with
    | nil => simp [variantsSame] at same
    | cons w ws =>
      simp only [variantsSame, Bool.and_eq_true] at same
      rw [typesSame_eq v same.1, variantsSame_eq vs same.2]
end

theorem SrcType.same_eq {a b : SrcType} (same : a.same b = true) : a = b := SrcType.eq_of_same a same

theorem wordWidth_cases {f : SrcType} {w : MemWidth} (h : wordWidth f = some w) :
    (f = .i32 ∧ w = .m32) ∨ (f = .bool ∧ w = .m32) ∨ (∃ k, f = .uint k ∧ usizeWidth k = some w) ∨
      (f = .ptr ∧ w = .m64) ∨ (f = .isize ∧ w = .m64) := by
  cases f with
  | i32 => simp only [wordWidth, Option.some.injEq] at h; exact .inl ⟨rfl, h.symm⟩
  | bool => simp only [wordWidth, Option.some.injEq] at h; exact .inr (.inl ⟨rfl, h.symm⟩)
  | uint k => exact .inr (.inr (.inl ⟨k, rfl, h⟩))
  | ptr => simp only [wordWidth, Option.some.injEq] at h; exact .inr (.inr (.inr (.inl ⟨rfl, h.symm⟩)))
  | isize => simp only [wordWidth, Option.some.injEq] at h; exact .inr (.inr (.inr (.inr ⟨rfl, h.symm⟩)))
  | struct | enum | slice | unit => simp [wordWidth] at h

theorem wordWidth_size {f : SrcType} {w : MemWidth} (h : wordWidth f = some w) : f.size = 1 := by
  rcases wordWidth_cases h with ⟨rfl, -⟩ | ⟨rfl, -⟩ | ⟨k, rfl, -⟩ | ⟨rfl, -⟩ | ⟨rfl, -⟩ <;> rfl

theorem wordWidth_scalar {f : SrcType} {w : MemWidth} (h : wordWidth f = some w) : f.isScalar = true := by
  rcases wordWidth_cases h with ⟨rfl, -⟩ | ⟨rfl, -⟩ | ⟨k, rfl, -⟩ | ⟨rfl, -⟩ | ⟨rfl, -⟩ <;> rfl

/-- One width a field, each field one native word: the widths of a struct's
leaves (`FlatLayout`), which `wordWidths` gives for nested structs too. -/
def leafWidths : List SrcType → Option (List MemWidth)
  | [] => some []
  | f :: rest => consWidth (wordWidth f) (leafWidths rest)

/-- `leafWidths` pairs each field with its width. -/
theorem leafWidths_get : ∀ {fields : List SrcType} {ws : List MemWidth}, leafWidths fields = some ws →
    ws.length = fields.length ∧ ∀ (j : Nat) f, fields[j]? = some f → ∃ w, ws[j]? = some w ∧ wordWidth f = some w
  | [], ws, h => by
    simp only [leafWidths, Option.some.injEq] at h
    subst h
    exact ⟨rfl, fun _ _ found => by simp at found⟩
  | f :: rest, ws, h => by
    simp only [leafWidths, consWidth] at h
    split at h
    · simp at h
    rename_i w hw
    split at h
    · simp at h
    rename_i rs hrs
    simp only [Option.some.injEq] at h
    subst h
    obtain ⟨len, each⟩ := leafWidths_get hrs
    refine ⟨by simp [len], fun j g found => ?_⟩
    cases j with
    | zero =>
      simp only [List.getElem?_cons_zero, Option.some.injEq] at found
      subst found
      exact ⟨w, rfl, hw⟩
    | succ j =>
      simp only [List.getElem?_cons_succ] at found ⊢
      exact each j g found

theorem i32_load_holds {bits : Nat} (lt : bits < 2 ^ 32) :
    SrcType.i32.Holds (.signed .i32 (if bits ≥ 2 ^ 31 then Int.ofNat bits - 2 ^ 32 else Int.ofNat bits))
      (BitVec.ofNat 64 bits) := by
  have w : BitVec.ofNat 64 bits = widen (BitVec.ofNat 32 bits) := by
    apply BitVec.eq_of_toNat_eq
    simp only [widen, BitVec.toNat_ofNat, BitVec.toNat_setWidth]
    omega
  have i : (if bits ≥ 2 ^ 31 then Int.ofNat bits - 2 ^ 32 else Int.ofNat bits) = (BitVec.ofNat 32 bits).toInt := by
    rw [BitVec.toInt_eq_toNat_cond]
    simp only [BitVec.toNat_ofNat, Nat.mod_eq_of_lt lt, Int.ofNat_eq_natCast]
    split <;> split <;> omega
  rw [w, i]
  exact holds_i32 _

/-! ## Core's words, one field at a time -/

theorem words_word {P : Core.Program} {f : SrcType} {w : MemWidth} (h : wordWidth f = some w) (k : Nat) :
    NativeLayout.words? (k + 1) P f.toCore = some 1 := by
  rcases wordWidth_cases h with ⟨rfl, -⟩ | ⟨rfl, -⟩ | ⟨k, rfl, -⟩ | ⟨rfl, -⟩ | ⟨rfl, -⟩
  all_goals try cases k
  all_goals simp [NativeLayout.words?, SrcType.toCore, UintTy.toCore]

theorem mapM_except_ok {α β ε : Type} {g : α → Except ε β} : ∀ {l : List α} {vs : List β},
    l.mapM g = .ok vs →
      vs.length = l.length ∧ ∀ (i : Nat) x, l[i]? = some x → ∃ y, vs[i]? = some y ∧ g x = .ok y
  | [], vs, h => by
    simp only [List.mapM_nil, pure, Except.pure, Except.ok.injEq] at h
    subst h
    exact ⟨rfl, fun _ _ found => by simp at found⟩
  | a :: rest, vs, h => by
    simp only [List.mapM_cons] at h
    obtain ⟨b, hb, h⟩ := except_bind_ok h
    obtain ⟨bs, hbs, h⟩ := except_bind_ok h
    simp only [pure, Except.pure, Except.ok.injEq] at h
    subst h
    obtain ⟨len, each⟩ := mapM_except_ok hbs
    refine ⟨by simp [len], fun i x found => ?_⟩
    cases i with
    | zero =>
      simp only [List.getElem?_cons_zero, Option.some.injEq] at found
      subst found
      exact ⟨b, rfl, hb⟩
    | succ i =>
      simp only [List.getElem?_cons_succ] at found ⊢
      exact each i x found

theorem wordBelow_ok {address offset a : Nat} (h : Semantics.wordBelow address offset = .ok a) :
    offset ≤ address ∧ a = address - offset := by
  simp only [Semantics.wordBelow] at h
  split at h
  · simp only [Except.ok.injEq] at h
    exact ⟨by assumption, h.symm⟩
  · simp at h

theorem uint_load_holds {k : UintTy} {bits : Nat} (lt : bits < 2 ^ k.width) :
    (SrcType.uint k).Holds (.unsigned k.toCore bits) (BitVec.ofNat 64 bits) := by
  have le : 2 ^ k.width ≤ 2 ^ 64 := Nat.pow_le_pow_right (by decide) (by cases k <;> decide)
  simp only [SrcType.Holds, BitVec.toNat_ofNat]
  rw [Nat.mod_eq_of_lt (by omega)]
  exact ⟨rfl, lt⟩

/-- Core's `isize` read of 8 bytes `bits`, in the slot the mini load fills. -/
theorem isize_load_holds {bits : Nat} (lt : bits < 2 ^ 64) :
    SrcType.isize.Holds (.signed .isize (Semantics.signed64 bits)) (BitVec.ofNat 64 bits) := by
  simp only [SrcType.Holds, Value.signed.injEq, true_and]
  rw [BitVec.toInt_eq_toNat_cond, BitVec.toNat_ofNat, Nat.mod_eq_of_lt lt]
  have a : (2 : Nat) ^ 64 = 18446744073709551616 := by rfl
  have b : (2 : Nat) ^ 63 = 9223372036854775808 := by rfl
  have c : (2 : Int) ^ 64 = 18446744073709551616 := by rfl
  simp only [Semantics.signed64, a, b, c, Int.ofNat_eq_natCast] at lt ⊢
  split <;> split <;> omega

/-- Core's read of one word field, in the slot the mini load fills. -/
theorem readWord_holds {P : Core.Program} {heap : Memory.Heap} {hp : Heap} (hc : HeapCorr heap hp)
    {f : SrcType} {w : MemWidth} (hw : wordWidth f = some w) {k a : Nat} {x : Value}
    (h : Semantics.readNativeValue (k + 1) P heap f.toCore a = .ok x) :
    f.Holds x (BitVec.ofNat 64 (hp.readLE a w.bytes)) ∧ a + w.bytes ≤ heap.nextAddress := by
  rcases wordWidth_cases hw with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨kind, rfl, hk⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
  · simp only [SrcType.toCore, Semantics.readNativeValue] at h
    obtain ⟨bits, loaded, wrapped⟩ := except_bind_ok h
    simp only [pure, Except.pure, Except.ok.injEq] at wrapped
    subst wrapped
    obtain ⟨rfl, inside⟩ := hc.loadNatLE loaded
    have lt := hp.readLE_lt a 4
    exact ⟨i32_load_holds (by simpa using lt), inside (by decide)⟩
  · simp only [SrcType.toCore, Semantics.readNativeValue] at h
    obtain ⟨bits, loaded, wrapped⟩ := except_bind_ok h
    obtain ⟨rfl, inside⟩ := hc.loadNatLE loaded
    split at wrapped
    · rename_i le
      simp only [pure, Except.pure, Except.ok.injEq] at wrapped
      subst wrapped
      refine ⟨⟨_, rfl, ?_⟩, inside (by decide)⟩
      simp only [MemWidth.bytes]
      rcases Nat.le_one_iff_eq_zero_or_eq_one.mp le with e | e <;> rw [e] <;> rfl
    · simp at wrapped
  · cases kind <;> simp only [usizeWidth, Option.some.injEq] at hk <;> subst hk <;>
      simp only [SrcType.toCore, UintTy.toCore, Semantics.readNativeValue] at h <;>
      obtain ⟨bits, loaded, wrapped⟩ := except_bind_ok h <;>
      obtain ⟨rfl, inside⟩ := hc.loadNatLE loaded
    · split at wrapped
      · rename_i small
        simp only [pure, Except.pure, Except.ok.injEq] at wrapped
        subst wrapped
        exact ⟨uint_load_holds (k := .uint8) (by simpa [UintTy.width] using small), inside (by decide)⟩
      · simp at wrapped
    all_goals
      simp only [pure, Except.pure, Except.ok.injEq] at wrapped
      subst wrapped
    · have lt := hp.readLE_lt a 4
      exact ⟨uint_load_holds (k := .uint32) (by simpa [UintTy.width] using lt), inside (by decide)⟩
    · have lt := hp.readLE_lt a 8
      exact ⟨uint_load_holds (k := .uint64) (by simpa [UintTy.width] using lt), inside (by decide)⟩
    · have lt := hp.readLE_lt a 8
      exact ⟨uint_load_holds (k := .usize) (by simpa [UintTy.width] using lt), inside (by decide)⟩
  · simp only [SrcType.toCore, Semantics.readNativeValue] at h
    obtain ⟨bits, loaded, wrapped⟩ := except_bind_ok h
    simp only [pure, Except.pure, Except.ok.injEq] at wrapped
    subst wrapped
    obtain ⟨rfl, inside⟩ := hc.loadNatLE loaded
    have lt := hp.readLE_lt a 8
    refine ⟨?_, inside (by decide)⟩
    simp only [SrcType.Holds, MemWidth.bytes, BitVec.toNat_ofNat]
    rw [Nat.mod_eq_of_lt (by simpa using lt)]
  · simp only [SrcType.toCore, Semantics.readNativeValue] at h
    obtain ⟨bits, loaded, wrapped⟩ := except_bind_ok h
    simp only [pure, Except.pure, Except.ok.injEq] at wrapped
    subst wrapped
    obtain ⟨rfl, inside⟩ := hc.loadNatLE loaded
    have lt := hp.readLE_lt a 8
    exact ⟨isize_load_holds (by simpa using lt), inside (by decide)⟩

/-! ## The mini side -/

theorem disp_eq (i n : Nat) (pos : 0 < n) : (i * n + n - 1) * 8 = i * (8 * n) + 8 * (n - 1) := by
  have : i * (8 * n) = 8 * (i * n) := Nat.mul_left_comm i 8 n
  rw [this]
  generalize i * n = m
  omega

/-- The element base the mini code computes is Core's `elementBase?`: the
element's word 0, `i * n` words below the descriptor. -/
theorem elementBase_eval {env : Env} {slot n : Nat} {index : Expr} {i : Nat}
    (hi : (index.eval env).toNat = i) (small : n ≤ 4096)
    (fits : i * (8 * n) ≤ (env slot).toNat) :
    ((elementBase slot n index).eval env).toNat = (env slot).toNat - i * (8 * n) := by
  have lt := (env slot).isLt
  have n8 : (BitVec.ofNat 64 (8 * n)).toNat = 8 * n := by
    rw [BitVec.toNat_ofNat]; exact Nat.mod_eq_of_lt (by omega)
  simp only [elementBase, Expr.eval, Word.apply, BinOp.apply, BitVec.toNat_sub, BitVec.toNat_mul, hi, n8]
  rw [Nat.mod_eq_of_lt (a := i * (8 * n)) (by omega)]
  omega

/-- A field's address: the base less its offset, without wrapping. -/
theorem fieldAddress_eval {env : Env} {base : Expr} {offset : Nat}
    (fits : offset ≤ (base.eval env).toNat) :
    ((Expr.binary Word.u64 BinOp.sub base (Expr.lit (BitVec.ofNat 64 offset))).eval env).toNat =
      (base.eval env).toNat - offset := by
  have lt := (base.eval env).isLt
  simp only [Expr.eval, Word.apply, BinOp.apply, BitVec.toNat_sub, BitVec.toNat_ofNat]
  rw [Nat.mod_eq_of_lt (a := offset) (by omega)]
  omega

theorem holdsAt_struct_inv {id : Nat} {fields : List SrcType} {v : Value} {env : Env} {slot : Nat}
    (h : SrcType.HoldsAt (.struct id fields) v env slot) : ∃ vals, v = .structure id vals ∧ FieldsHold fields vals env slot := by
  cases h with
  | struct fh => exact ⟨_, rfl, fh⟩

theorem mapM_option_ok {α β : Type} {g : α → Option β} : ∀ {l : List α} {vs : List β},
    l.mapM g = some vs →
      vs.length = l.length ∧ ∀ (i : Nat) x, l[i]? = some x → ∃ y, vs[i]? = some y ∧ g x = some y
  | [], vs, h => by
    simp only [List.mapM_nil, pure, Option.some.injEq] at h
    subst h
    exact ⟨rfl, fun _ _ found => by simp at found⟩
  | a :: rest, vs, h => by
    simp only [List.mapM_cons, bind, Option.bind] at h
    split at h
    · simp at h
    rename_i b hb
    dsimp only at h
    split at h
    · simp at h
    rename_i bs hbs
    simp only [pure, Option.some.injEq] at h
    subst h
    obtain ⟨len, each⟩ := mapM_option_ok hbs
    refine ⟨by simp [len], fun i x found => ?_⟩
    cases i with
    | zero =>
      simp only [List.getElem?_cons_zero, Option.some.injEq] at found
      subst found
      exact ⟨b, rfl, hb⟩
    | succ i =>
      obtain ⟨y, hy, ok⟩ := each i x (by simpa using found)
      exact ⟨y, by simpa using hy, ok⟩

theorem foldl_max : ∀ (l : List Nat) (a : Nat), l.foldl max a = max a (l.foldr max 0)
  | [], a => by simp
  | x :: rest, a => by
    simp only [List.foldl_cons, List.foldr_cons, foldl_max rest (max a x)]
    omega

end Lanius.Mini
