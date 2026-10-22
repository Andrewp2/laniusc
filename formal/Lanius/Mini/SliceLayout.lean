import Lanius.Mini.HeapCorr

/-!
# Struct slice elements in Core's native layout

The front pass accepts a raw slice of structs whose fields are each one native
word (`i32`, `bool`, `usize`, `ptr`; `wordWidths`). Core lays such an element
out as one 8-byte word per field (`NativeLayout.words?`), field `j` at byte
`8 * j` (`structureFieldOffset?`), and reads and writes it field by field
(`readNativeValue`, `writeNativeValue`). This file states those facts for the
declaration the front pass checked, and the mini side: `loadFields` puts the
fields in consecutive slots.
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

/-- Every field is one native word. -/
def AllWord (fields : List SrcType) : Prop := ∀ f ∈ fields, ∃ w, wordWidth f = some w

theorem wordWidth_cases {f : SrcType} {w : MemWidth} (h : wordWidth f = some w) :
    (f = .i32 ∧ w = .m32) ∨ (f = .bool ∧ w = .m32) ∨ (f = .uint .usize ∧ w = .m64) ∨
      (f = .ptr ∧ w = .m64) := by
  cases f with
  | i32 => simp only [wordWidth, Option.some.injEq] at h; exact .inl ⟨rfl, h.symm⟩
  | bool => simp only [wordWidth, Option.some.injEq] at h; exact .inr (.inl ⟨rfl, h.symm⟩)
  | uint k =>
    cases k <;> simp only [wordWidth, usizeWidth, Option.some.injEq, reduceCtorEq] at h
    exact .inr (.inr (.inl ⟨rfl, h.symm⟩))
  | ptr => simp only [wordWidth, Option.some.injEq] at h; exact .inr (.inr (.inr ⟨rfl, h.symm⟩))
  | struct | enum | slice | unit | isize => simp [wordWidth] at h

theorem wordWidth_size {f : SrcType} {w : MemWidth} (h : wordWidth f = some w) : f.size = 1 := by
  rcases wordWidth_cases h with ⟨rfl, -⟩ | ⟨rfl, -⟩ | ⟨rfl, -⟩ | ⟨rfl, -⟩ <;> rfl

theorem wordWidth_scalar {f : SrcType} {w : MemWidth} (h : wordWidth f = some w) : f.isScalar = true := by
  rcases wordWidth_cases h with ⟨rfl, -⟩ | ⟨rfl, -⟩ | ⟨rfl, -⟩ | ⟨rfl, -⟩ <;> rfl

/-- `wordWidths` pairs each field with its width. -/
theorem wordWidths_get : ∀ {fields : List SrcType} {ws : List MemWidth}, wordWidths fields = some ws →
    ws.length = fields.length ∧ ∀ (j : Nat) f, fields[j]? = some f → ∃ w, ws[j]? = some w ∧ wordWidth f = some w
  | [], ws, h => by
    simp only [wordWidths, Option.some.injEq] at h
    subst h
    exact ⟨rfl, fun _ _ found => by simp at found⟩
  | f :: rest, ws, h => by
    simp only [wordWidths, consWidth] at h
    split at h
    · simp at h
    rename_i w hw
    split at h
    · simp at h
    rename_i rs hrs
    simp only [Option.some.injEq] at h
    subst h
    obtain ⟨len, each⟩ := wordWidths_get hrs
    refine ⟨by simp [len], fun j g found => ?_⟩
    cases j with
    | zero =>
      simp only [List.getElem?_cons_zero, Option.some.injEq] at found
      subst found
      exact ⟨w, rfl, hw⟩
    | succ j =>
      simp only [List.getElem?_cons_succ] at found ⊢
      exact each j g found

theorem wordWidths_all {fields : List SrcType} {ws : List MemWidth} (h : wordWidths fields = some ws) :
    AllWord fields := by
  intro f mem
  obtain ⟨j, found⟩ := List.getElem?_of_mem mem
  obtain ⟨w, -, hw⟩ := (wordWidths_get h).2 j f found
  exact ⟨w, hw⟩

theorem sizes_allWord : ∀ {fields : List SrcType}, AllWord fields → sizes fields = fields.length
  | [], _ => rfl
  | f :: rest, all => by
    obtain ⟨w, hw⟩ := all f (by simp)
    simp only [sizes, wordWidth_size hw, List.length_cons]
    rw [sizes_allWord (fun g mem => all g (by simp [mem]))]
    omega

/-- What the front pass checked about a struct slice element. -/
theorem elementWidths_some {ds : SrcDecls} {element : SrcType} {ws : List MemWidth}
    (h : elementWidths ds element = some ws) :
    ∃ sid fields, element = .struct sid fields ∧ structFields ds.structs sid = some fields ∧
      wordWidths fields = some ws ∧ ws ≠ [] := by
  cases element with
  | struct sid fields =>
    simp only [elementWidths, declaredWidths] at h
    split at h
    · simp at h
    rename_i fs found
    split at h
    case isFalse => simp at h
    rename_i same
    simp only [nonemptyWidths] at h
    split at h
    · simp at h
    rename_i ws' hws
    split at h
    · simp at h
    simp only [Option.some.injEq] at h
    subst h
    have := typesSame_eq fs same
    subst this
    exact ⟨sid, fs, rfl, found, hws, List.cons_ne_nil _ _⟩
  | i32 | bool | uint | enum | ptr | slice | unit | isize => simp [elementWidths] at h

/-- Core's `i32` read of 4 bytes `bits`, in the slot the mini load fills. -/
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

/-! ## Core's layout of a declared word struct -/

theorem words_word {P : Core.Program} {f : SrcType} {w : MemWidth} (h : wordWidth f = some w) (k : Nat) :
    NativeLayout.words? (k + 1) P f.toCore = some 1 := by
  rcases wordWidth_cases h with ⟨rfl, -⟩ | ⟨rfl, -⟩ | ⟨rfl, -⟩ | ⟨rfl, -⟩ <;>
    simp [NativeLayout.words?, SrcType.toCore, UintTy.toCore]

theorem words_all {P : Core.Program} (k : Nat) : ∀ {fields : List SrcType}, AllWord fields →
    (fields.map SrcType.toCore).mapM (NativeLayout.words? (k + 1) P) = some (fields.map fun _ => 1)
  | [], _ => rfl
  | f :: rest, all => by
    obtain ⟨w, hw⟩ := all f (by simp)
    have tail := words_all (P := P) k (fields := rest) (fun g m => all g (by simp [m]))
    simp [List.mapM_cons, words_word hw k, tail]

theorem foldl_ones {α : Type} : ∀ (l : List α) (a : Nat), (l.map fun _ => 1).foldl (· + ·) a = a + l.length
  | [], a => by simp
  | _ :: rest, a => by
    simp only [List.map_cons, List.foldl_cons, List.length_cons]
    rw [foldl_ones rest (a + 1)]
    omega

theorem AllWord.take {fields : List SrcType} (all : AllWord fields) (j : Nat) : AllWord (fields.take j) :=
  fun f mem => all f (List.mem_of_mem_take mem)

theorem valueWords_struct {P : Core.Program} {sid : Nat} {fields : List SrcType}
    (found : P.structure? sid = some ⟨sid, fields.map SrcType.toCore⟩) (all : AllWord fields) {words : Nat}
    (h : NativeLayout.valueWords? P (.structure sid) = some words) :
    words = max 1 fields.length ∧ fields.length ≤ NativeLayout.maxWords := by
  rw [NativeLayout.valueWords?, show NativeLayout.maxDepth = 63 + 1 from rfl, NativeLayout.words?] at h
  dsimp only at h
  rw [found, show (63 : Nat) = 62 + 1 from rfl] at h
  simp only [bind, Option.bind, words_all 62 all, foldl_ones, Nat.zero_add, List.length_map] at h
  split at h
  · rename_i le
    simp only [Option.some.injEq] at h
    exact ⟨h.symm, le⟩
  · simp at h

theorem fieldOffset_struct {P : Core.Program} {sid : Nat} {fields : List SrcType}
    (found : P.structure? sid = some ⟨sid, fields.map SrcType.toCore⟩) (all : AllWord fields) {j : Nat}
    (lt : j < fields.length) : NativeLayout.structureFieldOffset? P sid j = some (8 * j) := by
  rw [NativeLayout.structureFieldOffset?, show NativeLayout.maxDepth - 1 = 62 + 1 from rfl]
  simp only [found, List.length_map, lt, if_true, ← List.map_take, words_all 62 (all.take j), foldl_ones,
    Nat.zero_add, List.length_take, Option.bind_eq_bind, Option.bind_some, NativeLayout.wordBytes]
  simp [Nat.min_eq_left (Nat.le_of_lt lt)]

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

/-- Core's read of a declared word struct: field `j` at byte `8 * j`. -/
theorem readNativeValue_struct {P : Core.Program} {heap : Memory.Heap} {sid : Nat} {fields : List SrcType}
    (found : P.structure? sid = some ⟨sid, fields.map SrcType.toCore⟩) (all : AllWord fields)
    {k base : Nat} {v : Value}
    (h : Semantics.readNativeValue (k + 1) P heap (.structure sid) base = .ok v) :
    ∃ vals, v = .structure sid vals ∧ vals.length = fields.length ∧
      ∀ (j : Nat) f, fields[j]? = some f → ∃ x, vals[j]? = some x ∧
        Semantics.readNativeValue k P heap f.toCore (base + 8 * j) = .ok x := by
  simp only [Semantics.readNativeValue, found] at h
  obtain ⟨vals, mapped, wrapped⟩ := except_bind_ok h
  simp only [pure, Except.pure, Except.ok.injEq] at wrapped
  subst wrapped
  obtain ⟨len, each⟩ := mapM_except_ok mapped
  simp only [List.length_range, List.length_map] at len
  refine ⟨vals, rfl, len, fun j f hf => ?_⟩
  have lt : j < fields.length := (List.getElem?_eq_some_iff.mp hf).1
  obtain ⟨x, hx, ok⟩ := each j j (by simp [List.getElem?_range, List.length_map, lt])
  refine ⟨x, hx, ?_⟩
  simp only [List.getElem?_map, hf, Option.map_some, fieldOffset_struct found all lt] at ok
  exact ok

/-- Core's read of one word field, in the slot the mini load fills. -/
theorem readWord_holds {P : Core.Program} {heap : Memory.Heap} {hp : Heap} (hc : HeapCorr heap hp)
    {f : SrcType} {w : MemWidth} (hw : wordWidth f = some w) {k a : Nat} {x : Value}
    (h : Semantics.readNativeValue (k + 1) P heap f.toCore a = .ok x) :
    f.Holds x (BitVec.ofNat 64 (hp.readLE a w.bytes)) ∧ a + w.bytes ≤ heap.nextAddress := by
  rcases wordWidth_cases hw with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
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
  · simp only [SrcType.toCore, UintTy.toCore, Semantics.readNativeValue] at h
    obtain ⟨bits, loaded, wrapped⟩ := except_bind_ok h
    simp only [pure, Except.pure, Except.ok.injEq] at wrapped
    subst wrapped
    obtain ⟨rfl, inside⟩ := hc.loadNatLE loaded
    have lt := hp.readLE_lt a 8
    refine ⟨⟨?_, ?_⟩, inside (by decide)⟩ <;>
      simp only [MemWidth.bytes, BitVec.toNat_ofNat, UintTy.toCore, UintTy.width] <;>
      rw [Nat.mod_eq_of_lt (by simpa using lt)]
    simpa using lt
  · simp only [SrcType.toCore, Semantics.readNativeValue] at h
    obtain ⟨bits, loaded, wrapped⟩ := except_bind_ok h
    simp only [pure, Except.pure, Except.ok.injEq] at wrapped
    subst wrapped
    obtain ⟨rfl, inside⟩ := hc.loadNatLE loaded
    have lt := hp.readLE_lt a 8
    refine ⟨?_, inside (by decide)⟩
    simp only [SrcType.Holds, MemWidth.bytes, BitVec.toNat_ofNat]
    rw [Nat.mod_eq_of_lt (by simpa using lt)]

/-! ## The mini side -/

theorem disp_eq (i n : Nat) (pos : 0 < n) : (i * n + n - 1) * 8 = i * (8 * n) + 8 * (n - 1) := by
  have : i * (8 * n) = 8 * (i * n) := Nat.mul_left_comm i 8 n
  rw [this]
  generalize i * n = m
  omega

/-- The element base the mini code computes is Core's `elementBase?`. -/
theorem elementBase_eval {env : Env} {slot n : Nat} {index : Expr} {i : Nat}
    (hi : (index.eval env).toNat = i) (small : n ≤ 4096)
    (fits : i * (8 * n) + 8 * (n - 1) ≤ (env slot).toNat) :
    ((elementBase slot n index).eval env).toNat = (env slot).toNat - (i * (8 * n) + 8 * (n - 1)) := by
  have lt := (env slot).isLt
  have n8 : (BitVec.ofNat 64 (8 * n)).toNat = 8 * n := by
    rw [BitVec.toNat_ofNat]; exact Nat.mod_eq_of_lt (by omega)
  have n8' : (BitVec.ofNat 64 (8 * (n - 1))).toNat = 8 * (n - 1) := by
    rw [BitVec.toNat_ofNat]; exact Nat.mod_eq_of_lt (by omega)
  simp only [elementBase, Expr.eval, Word.apply, BinOp.apply, BitVec.toNat_sub, BitVec.toNat_add,
    BitVec.toNat_mul, hi, n8, n8']
  rw [Nat.mod_eq_of_lt (a := i * (8 * n)) (by omega), Nat.mod_eq_of_lt (a := i * (8 * n) + 8 * (n - 1)) (by omega)]
  omega

/-- A field's address: the base plus its offset, without wrapping. -/
theorem fieldAddress_eval {env : Env} {base : Expr} {offset : Nat}
    (fits : (base.eval env).toNat + offset < 2 ^ 64) :
    ((Expr.binary Word.u64 BinOp.add base (Expr.lit (BitVec.ofNat 64 offset))).eval env).toNat =
      (base.eval env).toNat + offset := by
  simp only [Expr.eval, Word.apply, BinOp.apply, BitVec.toNat_add, BitVec.toNat_ofNat]
  rw [Nat.mod_eq_of_lt (a := offset) (by omega)]
  exact Nat.mod_eq_of_lt fits

theorem fieldsHold_of : ∀ {fields : List SrcType} {vals : List Value} {env : Env} {slot : Nat},
    AllWord fields → vals.length = fields.length →
    (∀ (j : Nat) f x, fields[j]? = some f → vals[j]? = some x → f.Holds x (env (slot + j))) →
    FieldsHold fields vals env slot
  | [], [], _, _, _, _, _ => .nil
  | [], _ :: _, _, _, _, len, _ => by simp at len
  | _ :: _, [], _, _, _, len, _ => by simp at len
  | f :: rest, x :: xs, env, slot, all, len, each => by
    obtain ⟨w, hw⟩ := all f (by simp)
    refine .cons ((SrcType.holdsAt_scalar (wordWidth_scalar hw)).mpr (by simpa using each 0 f x rfl rfl)) ?_
    rw [wordWidth_size hw]
    refine fieldsHold_of (fun g m => all g (by simp [m])) (by simpa using len) fun j g y hg hy => ?_
    have := each (j + 1) g y (by simpa using hg) (by simpa using hy)
    rwa [show slot + (j + 1) = slot + 1 + j by omega] at this

theorem holdsAt_struct_inv {id : Nat} {fields : List SrcType} {v : Value} {env : Env} {slot : Nat}
    (h : SrcType.HoldsAt (.struct id fields) v env slot) : ∃ vals, v = .structure id vals ∧ FieldsHold fields vals env slot := by
  cases h with
  | struct fh => exact ⟨_, rfl, fh⟩

/-- The converse of `fieldsHold_of`. -/
theorem fieldsHold_get {env : Env} : ∀ {fields : List SrcType} {vals : List Value} {slot : Nat},
    AllWord fields → FieldsHold fields vals env slot →
    vals.length = fields.length ∧ ∀ (j : Nat) f, fields[j]? = some f → ∃ x, vals[j]? = some x ∧ f.Holds x (env (slot + j))
  | [], _, _, _, h => by
    cases h
    exact ⟨rfl, fun j f hf => by simp at hf⟩
  | f :: rest, _, slot, all, h => by
    cases h with
    | @cons _ _ x xs _ _ head tail =>
    obtain ⟨w, hw⟩ := all f (by simp)
    rw [wordWidth_size hw] at tail
    obtain ⟨len, each⟩ := fieldsHold_get (fun g m => all g (by simp [m])) tail
    refine ⟨by simp [len], fun j g hg => ?_⟩
    cases j with
    | zero =>
      simp only [List.getElem?_cons_zero, Option.some.injEq] at hg
      subst hg
      exact ⟨x, rfl, by simpa using (SrcType.holdsAt_scalar (wordWidth_scalar hw)).mp head⟩
    | succ j =>
      obtain ⟨y, hy, hold⟩ := each j g (by simpa using hg)
      exact ⟨y, by simpa using hy, by rwa [show slot + (j + 1) = slot + 1 + j by omega]⟩

/-! ## Enum elements -/

theorem variantWidths_get : ∀ {variants : List (List SrcType)} {wss : List (List MemWidth)},
    variantWidths variants = some wss →
    wss.length = variants.length ∧ ∀ (m : Nat) fs, variants[m]? = some fs → ∃ ws, wss[m]? = some ws ∧ wordWidths fs = some ws
  | [], wss, h => by
    simp only [variantWidths, Option.some.injEq] at h
    subst h
    exact ⟨rfl, fun _ _ found => by simp at found⟩
  | fs :: rest, wss, h => by
    simp only [variantWidths, consWidths] at h
    split at h
    · simp at h
    rename_i ws hws
    split at h
    · simp at h
    rename_i wss' hrest
    simp only [Option.some.injEq] at h
    subst h
    obtain ⟨len, each⟩ := variantWidths_get hrest
    refine ⟨by simp [len], fun m gs hg => ?_⟩
    cases m with
    | zero =>
      simp only [List.getElem?_cons_zero, Option.some.injEq] at hg
      subst hg
      exact ⟨ws, rfl, hws⟩
    | succ m =>
      obtain ⟨w, hw, hwidth⟩ := each m gs (by simpa using hg)
      exact ⟨w, by simpa using hw, hwidth⟩

theorem variantWidths_all {variants : List (List SrcType)} {wss : List (List MemWidth)}
    (h : variantWidths variants = some wss) : ∀ fs ∈ variants, AllWord fs := by
  intro fs mem
  obtain ⟨m, found⟩ := List.getElem?_of_mem mem
  obtain ⟨ws, -, hws⟩ := (variantWidths_get h).2 m fs found
  exact wordWidths_all hws

theorem maxLength_eq : ∀ {variants : List (List SrcType)} {wss : List (List MemWidth)},
    variantWidths variants = some wss → maxLength wss = maxSize variants
  | [], wss, h => by
    simp only [variantWidths, Option.some.injEq] at h
    subst h
    rfl
  | fs :: rest, wss, h => by
    simp only [variantWidths, consWidths] at h
    split at h
    · simp at h
    rename_i ws hws
    split at h
    · simp at h
    rename_i wss' hrest
    simp only [Option.some.injEq] at h
    subst h
    simp only [maxLength, maxSize, maxLength_eq hrest, sizes_allWord (wordWidths_all hws),
      (wordWidths_get hws).1]

theorem enumWidths_some {ds : SrcDecls} {element : SrcType} {wss : List (List MemWidth)}
    (h : enumWidths ds element = some wss) :
    ∃ eid variants, element = .enum eid variants ∧ enumVariants ds.enums eid = some variants ∧
      variantWidths variants = some wss ∧ 0 < variants.length ∧ variants.length < 2 ^ 32 := by
  cases element with
  | enum eid variants =>
    simp only [enumWidths, declaredVariantWidths] at h
    split at h
    · simp at h
    rename_i vs found
    split at h
    case isFalse => simp at h
    rename_i cond
    simp only [Bool.and_eq_true, decide_eq_true_eq] at cond
    obtain ⟨⟨same, pos⟩, small⟩ := cond
    have := variantsSame_eq vs same
    subst this
    exact ⟨eid, vs, rfl, found, h, pos, small⟩
  | i32 | bool | uint | struct | ptr | slice | unit | isize => simp [enumWidths] at h

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

theorem maxSize_lengths : ∀ {variants : List (List SrcType)}, (∀ fs ∈ variants, AllWord fs) →
    (variants.map List.length).foldr max 0 = maxSize variants
  | [], _ => rfl
  | fs :: rest, all => by
    simp only [List.map_cons, List.foldr_cons, maxSize, sizes_allWord (all fs (by simp)),
      maxSize_lengths (variants := rest) (fun gs m => all gs (List.mem_cons_of_mem _ m))]

theorem valueWords_enum {P : Core.Program} {eid : Nat} {variants : List (List SrcType)}
    (found : P.enumeration? eid = some ⟨eid, variants.map (List.map SrcType.toCore)⟩)
    (all : ∀ fs ∈ variants, AllWord fs) {words : Nat}
    (h : NativeLayout.valueWords? P (.enumeration eid) = some words) :
    words = 1 + maxSize variants ∧ maxSize variants < NativeLayout.maxWords := by
  rw [NativeLayout.valueWords?, show NativeLayout.maxDepth = 63 + 1 from rfl, NativeLayout.words?] at h
  dsimp only at h
  rw [found, show (63 : Nat) = 62 + 1 from rfl] at h
  simp only [bind, Option.bind] at h
  split at h
  · simp at h
  rename_i ls hls
  simp only [Option.some.injEq] at h
  obtain ⟨len, each⟩ := mapM_option_ok hls
  have per : ∀ (i : Nat) fs, variants[i]? = some fs → ls[i]? = some fs.length ∧ fs.length < NativeLayout.maxWords := by
    intro i fs hf
    obtain ⟨y, hy, ok⟩ := each i (fs.map SrcType.toCore) (by simp [List.getElem?_map, hf])
    simp only [words_all 62 (all fs (List.mem_of_getElem? hf)), foldl_ones, Nat.zero_add, List.length_map] at ok
    split at ok
    · rename_i lt
      simp only [Option.some.injEq] at ok
      subst ok
      exact ⟨hy, lt⟩
    · simp at ok
  have hls' : ls = variants.map List.length := by
    apply List.ext_getElem?
    intro i
    cases hv : variants[i]? with
    | none =>
      have : variants.length ≤ i := List.getElem?_eq_none_iff.mp hv
      simp only [List.getElem?_map, hv, Option.map_none]
      exact List.getElem?_eq_none_iff.mpr (by simp at len; omega)
    | some fs => simp [List.getElem?_map, hv, (per i fs hv).1]
  subst hls'
  rw [foldl_max, maxSize_lengths all] at h
  refine ⟨by omega, ?_⟩
  have bound : ∀ (vs : List (List SrcType)), (∀ fs ∈ vs, fs.length < NativeLayout.maxWords) →
      (∀ fs ∈ vs, AllWord fs) → maxSize vs < NativeLayout.maxWords := by
    intro vs
    induction vs with
    | nil => intro _ _; simp [maxSize, NativeLayout.maxWords]
    | cons fs rest ih =>
      intro lt allv
      simp only [maxSize, sizes_allWord (allv fs (by simp))]
      have := ih (fun g m => lt g (by simp [m])) (fun g m => allv g (by simp [m]))
      have := lt fs (by simp)
      omega
  exact bound variants (fun fs mem => by
    obtain ⟨i, hi⟩ := List.getElem?_of_mem mem
    exact (per i fs hi).2) all

theorem payloadOffset {P : Core.Program} {fs : List SrcType} (all : AllWord fs) {j : Nat} (lt : j < fs.length) :
    ((fs.map SrcType.toCore).take j).mapM (fun member => NativeLayout.words? (NativeLayout.maxDepth - 1) P member) =
      some ((fs.take j).map fun _ => 1) := by
  rw [show NativeLayout.maxDepth - 1 = 62 + 1 from rfl, ← List.map_take]
  exact words_all 62 (all.take j)

theorem readNativeValue_enum {P : Core.Program} {heap : Memory.Heap} {eid : Nat} {variants : List (List SrcType)}
    (found : P.enumeration? eid = some ⟨eid, variants.map (List.map SrcType.toCore)⟩)
    (all : ∀ fs ∈ variants, AllWord fs) {k base : Nat} {v : Value}
    (h : Semantics.readNativeValue (k + 1) P heap (.enumeration eid) base = .ok v) :
    ∃ variant fs payload, v = .enumeration eid variant payload ∧ Semantics.loadNatLE heap base 4 = .ok variant ∧
      variants[variant]? = some fs ∧ payload.length = fs.length ∧
      ∀ (j : Nat) f, fs[j]? = some f → ∃ x, payload[j]? = some x ∧
        Semantics.readNativeValue k P heap f.toCore (base + 8 * (1 + j)) = .ok x := by
  simp only [Semantics.readNativeValue, found] at h
  obtain ⟨variant, loaded, h⟩ := except_bind_ok h
  cases hv : variants[variant]? with
  | none => simp [List.getElem?_map, hv] at h
  | some fs =>
  simp only [List.getElem?_map, hv, Option.map_some] at h
  obtain ⟨payload, mapped, wrapped⟩ := except_bind_ok h
  simp only [pure, Except.pure, Except.ok.injEq] at wrapped
  subst wrapped
  obtain ⟨len, each⟩ := mapM_except_ok mapped
  simp only [List.length_range, List.length_map] at len
  have allF := all fs (List.mem_of_getElem? hv)
  refine ⟨variant, fs, payload, rfl, loaded, hv, len, fun j f hf => ?_⟩
  have lt : j < fs.length := (List.getElem?_eq_some_iff.mp hf).1
  obtain ⟨x, hx, ok⟩ := each j j (by simp [List.getElem?_range, List.length_map, lt])
  refine ⟨x, hx, ?_⟩
  simp only [List.getElem?_map, hf, Option.map_some, payloadOffset allF lt, foldl_ones, Nat.zero_add,
    List.length_take, NativeLayout.wordBytes, Nat.min_eq_left (Nat.le_of_lt lt)] at ok
  exact ok

end Lanius.Mini
