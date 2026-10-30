import Lanius.Mini.SliceLayout

/-!
# Slice elements of word types in Core's native layout

A struct or enum slice element is a word type (`wordType`): word scalars
(`wordWidth`), declared structs of word types taking at least one word, and
declared enums of word-type payloads. Core gives each such type its mini
size in words, puts field `j` of a struct `8 * sizes (take j)` bytes below the
struct and payload field `j` of an enum `8 * (1 + sizes (take j))` bytes below
it, so a value's word `k` is the slot `k` of the mini code. This file has those
facts, and Core's reads and writes of a struct's fields and an enum's payload
as chains, one field after another (`FieldReads`, `FieldWrites`).
-/

namespace Lanius.Mini

open Lanius.Core (Value)

theorem foldl_add : ∀ (l : List Nat) (a : Nat), l.foldl (· + ·) a = a + l.foldl (· + ·) 0
  | [], a => by simp
  | x :: rest, a => by
    simp only [List.foldl_cons]
    rw [foldl_add rest (a + x), foldl_add rest (0 + x)]
    omega

theorem mapM_option_cons {α β : Type} {g : α → Option β} {a : α} {l : List α} {ns : List β}
    (h : (a :: l).mapM g = some ns) : ∃ b bs, g a = some b ∧ l.mapM g = some bs ∧ ns = b :: bs := by
  simp only [List.mapM_cons, bind, Option.bind] at h
  split at h
  · simp at h
  rename_i b hb
  dsimp only at h
  split at h
  · simp at h
  rename_i bs hbs
  simp only [pure, Option.some.injEq] at h
  exact ⟨b, bs, hb, hbs, h.symm⟩

theorem word_words {P : Core.Program} {f : SrcType} {w : MemWidth} (hw : wordWidth f = some w) :
    ∀ {fuel n : Nat}, NativeLayout.words? fuel P f.toCore = some n → n = 1
  | 0, n, h => by simp [NativeLayout.words?] at h
  | k + 1, n, h => by
    rw [words_word hw k, Option.some.injEq] at h
    exact h.symm

theorem sizes_append : ∀ (a b : List SrcType), sizes (a ++ b) = sizes a + sizes b
  | [], b => by simp [sizes]
  | f :: a, b => by simp only [List.cons_append, sizes, sizes_append a b]; omega

theorem sizes_take_succ {fs : List SrcType} {j : Nat} {f : SrcType} (hf : fs[j]? = some f) :
    sizes (fs.take (j + 1)) = sizes (fs.take j) + f.size := by
  rw [List.take_add_one, hf, sizes_append]
  simp [sizes]

theorem drop_cons_get {α : Type} {l : List α} {j : Nat} {a : α} {rest : List α} (h : l.drop j = a :: rest) :
    l[j]? = some a ∧ l.drop (j + 1) = rest := by
  constructor
  · have := congrArg (·[0]?) h
    simpa using this
  · rw [← List.drop_drop, h]
    rfl

theorem readNativeValue_zero {P : Core.Program} {heap : Memory.Heap} {t : Core.Ty} {a : Nat} {x : Value}
    (h : Semantics.readNativeValue 0 P heap t a = .ok x) : False := by
  simp [Semantics.readNativeValue] at h

theorem writeNativeValue_zero {P : Core.Program} {st : Semantics.State} {h h' : Memory.Heap} {t : Core.Ty} {a : Nat}
    {x : Value} (w : Semantics.writeNativeValue 0 P st h t a x = .ok h') : False := by
  simp [Semantics.writeNativeValue] at w

theorem getElem?_append_cases {α : Type} {l r : List α} {i : Nat} {x : α} (h : (l ++ r)[i]? = some x) :
    (i < l.length ∧ l[i]? = some x) ∨ (l.length ≤ i ∧ r[i - l.length]? = some x) := by
  by_cases lt : i < l.length
  · left
    rw [List.getElem?_append_left lt] at h
    exact ⟨lt, h⟩
  · right
    rw [List.getElem?_append_right (by omega)] at h
    exact ⟨by omega, h⟩

theorem wordTypes_iff {ds : SrcDecls} : ∀ {fs : List SrcType},
    wordTypes ds fs = true ↔ ∀ f ∈ fs, wordType ds f = true
  | [] => by simp [wordTypes]
  | f :: rest => by
    simp only [wordTypes, Bool.and_eq_true, List.mem_cons, forall_eq_or_imp]
    rw [wordTypes_iff]

theorem wordVariants_iff {ds : SrcDecls} : ∀ {vs : List (List SrcType)},
    wordVariants ds vs = true ↔ ∀ fs ∈ vs, wordTypes ds fs = true
  | [] => by simp [wordVariants]
  | fs :: rest => by
    simp only [wordVariants, Bool.and_eq_true, List.mem_cons, forall_eq_or_imp]
    rw [wordVariants_iff]

theorem wordTypes_take {ds : SrcDecls} {fs : List SrcType} (h : wordTypes ds fs = true) (j : Nat) :
    wordTypes ds (fs.take j) = true :=
  wordTypes_iff.mpr fun f mem => wordTypes_iff.mp h f (List.mem_of_mem_take mem)

theorem wordTypes_get {ds : SrcDecls} {fs : List SrcType} (h : wordTypes ds fs = true) {j : Nat}
    {f : SrcType} (found : fs[j]? = some f) : wordType ds f = true :=
  wordTypes_iff.mp h f (List.mem_of_getElem? found)

theorem wordVariants_get {ds : SrcDecls} {vs : List (List SrcType)} (h : wordVariants ds vs = true) {j : Nat}
    {fs : List SrcType} (found : vs[j]? = some fs) : wordTypes ds fs = true :=
  wordVariants_iff.mp h fs (List.mem_of_getElem? found)

/-- What `wordType` checked about a struct. -/
theorem wordType_struct {ds : SrcDecls} {sid : Nat} {fields : List SrcType}
    (h : wordType ds (.struct sid fields) = true) :
    structFields ds.structs sid = some fields ∧ wordTypes ds fields = true ∧ 0 < sizes fields := by
  simp only [wordType, Bool.and_eq_true, decide_eq_true_eq] at h
  obtain ⟨⟨declared, words⟩, pos⟩ := h
  refine ⟨?_, words, pos⟩
  cases found : structFields ds.structs sid with
  | none => simp [found, declaredSame] at declared
  | some gs =>
    simp only [found, declaredSame] at declared
    rw [typesSame_eq gs declared]

/-- What `wordType` checked about an enum. -/
theorem wordType_enum {ds : SrcDecls} {eid : Nat} {variants : List (List SrcType)}
    (h : wordType ds (.enum eid variants) = true) :
    enumVariants ds.enums eid = some variants ∧ wordVariants ds variants = true ∧ 0 < variants.length ∧
      variants.length < 4294967296 := by
  simp only [wordType, Bool.and_eq_true, decide_eq_true_eq] at h
  obtain ⟨⟨⟨declared, pos⟩, small⟩, words⟩ := h
  refine ⟨?_, words, pos, small⟩
  cases found : enumVariants ds.enums eid with
  | none => simp [found, declaredVariants] at declared
  | some vs =>
    simp only [found, declaredVariants] at declared
    rw [variantsSame_eq vs declared]

/-- A word type's scalars: the word scalars. -/
theorem wordType_scalar {ds : SrcDecls} {t : SrcType} (h : wordType ds t = true) (scalar : t.isScalar = true) :
    wordWidth t = some (widthOf t) := by
  cases t <;> simp_all [wordType, wordWidth, widthOf, SrcType.isScalar]
  all_goals
    rename_i kind
    cases kind <;> rfl

/-! ## Core's words -/

theorem mapM_option_map {α β : Type} {g : α → Option β} {f : α → β} :
    ∀ {l : List α} {vs : List β}, l.mapM g = some vs → (∀ x ∈ l, ∀ y, g x = some y → y = f x) → vs = l.map f
  | [], vs, h, _ => by
    simp only [List.mapM_nil, pure, Option.some.injEq] at h
    simp [h]
  | a :: rest, vs, h, each => by
    obtain ⟨b, bs, hb, hbs, rfl⟩ := mapM_option_cons h
    rw [each a (by simp) b hb, mapM_option_map hbs fun x mem y hy => each x (by simp [mem]) y hy]
    rfl

/-- Core's words for a payload, as `words?` computes them for an enum. -/
def payloadWords (fuel : Nat) (P : Core.Program) (fields : List Core.Ty) : Option Nat := do
  let widths ← fields.mapM (NativeLayout.words? fuel P)
  let total := widths.foldl (· + ·) 0
  if total < NativeLayout.maxWords then some total else none

/-- The largest `f x` of the list. -/
def maxMap {α : Type} (f : α → Nat) : List α → Nat
  | [] => 0
  | x :: rest => max (f x) (maxMap f rest)

theorem foldl_max_map {α : Type} (f : α → Nat) : ∀ (l : List α) (a : Nat),
    (l.map f).foldl max a = max a (maxMap f l)
  | [], a => by simp [maxMap]
  | x :: rest, a => by
    simp only [List.map_cons, List.foldl_cons, foldl_max_map f rest (max a (f x)), maxMap]
    omega

theorem maxMap_sizes : ∀ (vs : List (List SrcType)), maxMap sizes vs = maxSize vs
  | [] => rfl
  | fs :: rest => by simp only [maxMap, maxSize, maxMap_sizes rest]

mutual
/-- Core gives a word type its mini size in words. -/
theorem wordType_words {sp : SrcProgram} : ∀ (t : SrcType), wordType sp.decls t = true →
    ∀ {fuel n : Nat}, NativeLayout.words? fuel sp.toCore t.toCore = some n → n = t.size
  | .i32, _, fuel, n, h => word_words (w := .m32) rfl h
  | .bool, _, fuel, n, h => word_words (w := .m32) rfl h
  | .uint kind, _, fuel, n, h => by
    cases kind
    all_goals exact word_words (by rfl) h
  | .ptr, _, fuel, n, h => word_words (w := .m64) rfl h
  | .isize, _, fuel, n, h => word_words (w := .m64) rfl h
  | .sint kind, _, fuel, n, h => by
    cases kind
    all_goals exact word_words (by rfl) h
  | .slice _, ok, _, _, _ => by simp [wordType] at ok
  | .unit, ok, _, _, _ => by simp [wordType] at ok
  | .struct sid fields, ok, fuel, n, h => by
    obtain ⟨decl, words, pos⟩ := wordType_struct ok
    cases fuel with
    | zero => simp [NativeLayout.words?] at h
    | succ k =>
    simp only [SrcType.toCore] at h
    rw [NativeLayout.words?] at h
    dsimp only at h
    rw [structFields_toCore decl] at h
    simp only [bind, Option.bind] at h
    split at h
    · simp at h
    rename_i ns hns
    dsimp only at h
    rw [wordTypes_words fields words hns] at h
    split at h
    · simp only [Option.some.injEq] at h
      simp only [SrcType.size]
      omega
    · simp at h
  | .enum eid variants, ok, fuel, n, h => by
    obtain ⟨decl, words, pos, -⟩ := wordType_enum ok
    cases fuel with
    | zero => simp [NativeLayout.words?] at h
    | succ k =>
    simp only [SrcType.toCore] at h
    rw [NativeLayout.words?] at h
    dsimp only at h
    rw [enumVariants_toCore decl] at h
    simp only [bind, Option.bind] at h
    split at h
    · simp at h
    rename_i ps hps
    simp only [Option.some.injEq] at h
    rw [wordVariants_words variants words (fuel := k) hps, foldl_max_map, maxMap_sizes] at h
    simp only [SrcType.size]
    omega

theorem wordTypes_words {sp : SrcProgram} : ∀ (fs : List SrcType), wordTypes sp.decls fs = true →
    ∀ {fuel : Nat} {ns : List Nat}, (fs.map SrcType.toCore).mapM (NativeLayout.words? fuel sp.toCore) = some ns →
      ns.foldl (· + ·) 0 = sizes fs
  | [], _, fuel, ns, e => by
    simp only [List.map_nil, List.mapM_nil, pure, Option.some.injEq] at e
    subst e
    rfl
  | f :: rest, ok, fuel, ns, e => by
    simp only [wordTypes, Bool.and_eq_true] at ok
    obtain ⟨b, bs, hb, hbs, rfl⟩ := mapM_option_cons e
    rw [List.foldl_cons, foldl_add, wordTypes_words rest ok.2 hbs, wordType_words f ok.1 hb, sizes]
    omega

theorem wordVariants_words {sp : SrcProgram} : ∀ (vs : List (List SrcType)), wordVariants sp.decls vs = true →
    ∀ {fuel : Nat} {ps : List Nat}, (vs.map (List.map SrcType.toCore)).mapM (payloadWords fuel sp.toCore) = some ps →
      ps = vs.map sizes
  | [], _, fuel, ps, e => by
    simp only [List.map_nil, List.mapM_nil, pure, Option.some.injEq] at e
    simp [e]
  | fs :: rest, ok, fuel, ps, e => by
    simp only [wordVariants, Bool.and_eq_true] at ok
    obtain ⟨b, bs, hb, hbs, rfl⟩ := mapM_option_cons e
    rw [wordVariants_words rest ok.2 hbs]
    simp only [payloadWords, bind, Option.bind] at hb
    split at hb
    · simp at hb
    rename_i ns hns
    dsimp only at hb
    split at hb
    · simp only [Option.some.injEq] at hb
      rw [← hb, wordTypes_words fs ok.1 hns]
      rfl
    · simp at hb
end

theorem mapM_option_mem {α β : Type} {g : α → Option β} : ∀ {l : List α} {vs : List β},
    l.mapM g = some vs → ∀ y ∈ vs, ∃ x ∈ l, g x = some y
  | [], vs, h, y, mem => by
    simp only [List.mapM_nil, pure, Option.some.injEq] at h
    simp [← h] at mem
  | a :: rest, vs, h, y, mem => by
    obtain ⟨b, bs, hb, hbs, rfl⟩ := mapM_option_cons h
    rcases List.mem_cons.mp mem with rfl | mem
    · exact ⟨a, by simp, hb⟩
    · obtain ⟨x, xmem, hx⟩ := mapM_option_mem hbs y mem
      exact ⟨x, by simp [xmem], hx⟩

theorem foldl_max_lt : ∀ (l : List Nat) {a m : Nat}, a < m → (∀ p ∈ l, p < m) → l.foldl max a < m
  | [], _, _, lt, _ => lt
  | p :: rest, a, m, lt, each => by
    simp only [List.foldl_cons]
    exact foldl_max_lt rest (by have := each p (by simp); omega) fun q mem => each q (by simp [mem])

/-- A struct or enum's words fit Core's cap. -/
theorem words_le_max {P : Core.Program} {k n : Nat} :
    ∀ {t : Core.Ty}, ((∃ id, t = .structure id) ∨ ∃ id, t = .enumeration id) →
      NativeLayout.words? (k + 1) P t = some n → n ≤ NativeLayout.maxWords
  | _, .inl ⟨id, rfl⟩, h => by
    rw [NativeLayout.words?] at h
    dsimp only at h
    simp only [bind, Option.bind] at h
    split at h
    · simp at h
    dsimp only at h
    split at h
    · simp at h
    dsimp only at h
    split at h
    · simp only [Option.some.injEq] at h
      simp only [NativeLayout.maxWords] at *
      omega
    · simp at h
  | _, .inr ⟨id, rfl⟩, h => by
    rw [NativeLayout.words?] at h
    dsimp only at h
    simp only [bind, Option.bind] at h
    split at h
    all_goals try (simp at h; done)
    dsimp only at h
    split at h
    all_goals try (simp at h; done)
    rename_i ps hps
    simp only [Option.some.injEq] at h
    have := foldl_max_lt ps (a := 0) (m := NativeLayout.maxWords) (by decide) fun p mem => by
      obtain ⟨x, -, hx⟩ := mapM_option_mem hps p mem
      try simp only [bind, Option.bind] at hx
      try dsimp only at hx
      split at hx
      all_goals try (simp at hx; done)
      dsimp only at hx
      split at hx
      all_goals try (simp at hx; done)
      simp only [Option.some.injEq] at hx
      omega
    simp only [NativeLayout.maxWords] at *
    omega

/-- Field `j` of a declared struct of word types is `8 * sizes (take j)` bytes below it. -/
theorem fieldOffset_word {sp : SrcProgram} {sid : Nat} {fields : List SrcType}
    (decl : structFields sp.decls.structs sid = some fields) (words : wordTypes sp.decls fields = true) {j o : Nat}
    (h : NativeLayout.structureFieldOffset? sp.toCore sid j = some o) :
    o = 8 * sizes (fields.take j) := by
  rw [NativeLayout.structureFieldOffset?] at h
  simp only [structFields_toCore decl, bind, Option.bind, List.length_map] at h
  split at h
  · rename_i lt
    rw [← List.map_take] at h
    split at h
    · simp at h
    rename_i ns hns
    simp only [Option.some.injEq] at h
    rw [← h, wordTypes_words _ (wordTypes_take words j) hns, NativeLayout.wordBytes]
  · simp at h

/-- A payload field's offset: the tag's word, then the earlier fields' words. -/
theorem payloadOffset_word {sp : SrcProgram} {fs : List SrcType} (words : wordTypes sp.decls fs = true) {j : Nat}
    {widths : List Nat}
    (h : ((fs.map SrcType.toCore).take j).mapM
      (fun member => NativeLayout.words? (NativeLayout.maxDepth - 1) sp.toCore member) = some widths) :
    widths.foldl (· + ·) 0 = sizes (fs.take j) := by
  rw [← List.map_take] at h
  exact wordTypes_words _ (wordTypes_take words j) h

/-! ## Core's reads and writes of fields, one after another -/

/-- Core's reads of these fields, field `f` at `off` bytes below `a`, the
next `8 * f.size` bytes below it. -/
inductive FieldReads (P : Core.Program) (heap : Memory.Heap) (a : Nat) :
    List SrcType → List Value → Nat → Prop where
  | nil {off : Nat} : FieldReads P heap a [] [] off
  | cons {f : SrcType} {fs : List SrcType} {x : Value} {xs : List Value} {off : Nat} :
      off ≤ a → (∃ k, Semantics.readNativeValue k P heap f.toCore (a - off) = .ok x) →
      FieldReads P heap a fs xs (off + 8 * f.size) → FieldReads P heap a (f :: fs) (x :: xs) off

theorem FieldReads.of_get {P : Core.Program} {heap : Memory.Heap} {a : Nat} :
    ∀ {fs : List SrcType} {vals : List Value} {start : Nat}, vals.length = fs.length →
      (∀ (j : Nat) f, fs[j]? = some f → ∃ x, vals[j]? = some x ∧ start + 8 * sizes (fs.take j) ≤ a ∧
        ∃ k, Semantics.readNativeValue k P heap f.toCore (a - (start + 8 * sizes (fs.take j))) = .ok x) →
      FieldReads P heap a fs vals start
  | [], [], _, _, _ => .nil
  | [], _ :: _, _, len, _ => by simp at len
  | _ :: _, [], _, len, _ => by simp at len
  | f :: fs, v :: vals, start, len, each => by
    obtain ⟨x0, hx0, le0, read0⟩ := each 0 f rfl
    simp only [List.getElem?_cons_zero, Option.some.injEq] at hx0
    subst hx0
    simp only [List.take_zero, sizes, Nat.mul_zero, Nat.add_zero] at le0 read0
    refine .cons le0 read0 (FieldReads.of_get (by simpa using len) fun j g hg => ?_)
    obtain ⟨x, hx, le, rd⟩ := each (j + 1) g (by simpa using hg)
    simp only [List.take_succ_cons, sizes] at le rd
    refine ⟨x, by simpa using hx, by omega, ?_⟩
    rwa [show start + 8 * (f.size + sizes (List.take j fs)) =
      start + 8 * f.size + 8 * sizes (List.take j fs) by rw [Nat.mul_add, Nat.add_assoc]] at rd

theorem FieldReads.length {P : Core.Program} {heap : Memory.Heap} {a : Nat} {fs : List SrcType}
    {xs : List Value} {off : Nat} (h : FieldReads P heap a fs xs off) : xs.length = fs.length := by
  induction h with
  | nil => rfl
  | cons _ _ _ ih => simp [ih]

/-- Core's read of a declared struct of word types: its fields, one after another. -/
theorem readNativeValue_struct_reads {sp : SrcProgram} {heap : Memory.Heap} {sid : Nat} {fields : List SrcType}
    (decl : structFields sp.decls.structs sid = some fields) (words : wordTypes sp.decls fields = true)
    {k a : Nat} {v : Value}
    (h : Semantics.readNativeValue (k + 1) sp.toCore heap (.structure sid) a = .ok v) :
    ∃ vals, v = .structure sid vals ∧ FieldReads sp.toCore heap a fields vals 0 := by
  simp only [Semantics.readNativeValue, structFields_toCore decl] at h
  obtain ⟨vals, mapped, wrapped⟩ := except_bind_ok h
  simp only [pure, Except.pure, Except.ok.injEq] at wrapped
  subst wrapped
  obtain ⟨len, each⟩ := mapM_except_ok mapped
  simp only [List.length_range, List.length_map] at len
  refine ⟨vals, rfl, FieldReads.of_get len fun j f hf => ?_⟩
  have lt : j < fields.length := (List.getElem?_eq_some_iff.mp hf).1
  obtain ⟨x, hx, ok⟩ := each j j (by simp [List.length_map, lt])
  refine ⟨x, hx, ?_⟩
  simp only [List.getElem?_map, hf, Option.map_some] at ok
  split at ok
  case h_2 => simp at ok
  rename_i o ho
  rw [fieldOffset_word decl words ho] at ok
  obtain ⟨a', below, ok⟩ := except_bind_ok ok
  obtain ⟨le, rfl⟩ := wordBelow_ok below
  exact ⟨by omega, k, by simpa using ok⟩

/-- Core's read of a declared enum of word-type payloads: its tag, then the
variant's payload fields one after another, from `8` bytes below it. -/
theorem readNativeValue_enum_reads {sp : SrcProgram} {heap : Memory.Heap} {eid : Nat}
    {variants : List (List SrcType)} (decl : enumVariants sp.decls.enums eid = some variants)
    (words : wordVariants sp.decls variants = true) {k a : Nat} {v : Value}
    (h : Semantics.readNativeValue (k + 1) sp.toCore heap (.enumeration eid) a = .ok v) :
    ∃ variant fs payload, v = .enumeration eid variant payload ∧ Semantics.loadNatLE heap a 4 = .ok variant ∧
      variants[variant]? = some fs ∧ FieldReads sp.toCore heap a fs payload 8 := by
  simp only [Semantics.readNativeValue, enumVariants_toCore decl] at h
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
  have fw := wordVariants_get words hv
  refine ⟨variant, fs, payload, rfl, loaded, hv, FieldReads.of_get len fun j f hf => ?_⟩
  have lt : j < fs.length := (List.getElem?_eq_some_iff.mp hf).1
  obtain ⟨x, hx, ok⟩ := each j j (by simp [List.length_map, lt])
  refine ⟨x, hx, ?_⟩
  simp only [hf, Option.map_some] at ok
  split at ok
  case h_2 => simp at ok
  rename_i widths hwidths
  rw [payloadOffset_word fw hwidths, NativeLayout.wordBytes] at ok
  obtain ⟨a', below, ok⟩ := except_bind_ok ok
  obtain ⟨le, rfl⟩ := wordBelow_ok below
  refine ⟨by omega, k, ?_⟩
  rwa [show 8 * (1 + sizes (List.take j fs)) = 8 + 8 * sizes (List.take j fs) by omega] at ok

/-- Core's writes of these fields, field `f` at `off` bytes below `a`, the
next `8 * f.size` bytes below it. -/
inductive FieldWrites (P : Core.Program) (st : Semantics.State) (a : Nat) :
    List SrcType → List Value → Nat → Memory.Heap → Memory.Heap → Prop where
  | nil {off : Nat} {h : Memory.Heap} : FieldWrites P st a [] [] off h h
  | cons {f : SrcType} {fs : List SrcType} {x : Value} {xs : List Value} {off : Nat} {h h1 h2 : Memory.Heap} :
      off ≤ a → (∃ k, Semantics.writeNativeValue k P st h f.toCore (a - off) x = .ok h1) →
      FieldWrites P st a fs xs (off + 8 * f.size) h1 h2 → FieldWrites P st a (f :: fs) (x :: xs) off h h2

/-- Core's field-by-field writes from field `j` of `FS` on, field `i` at
`c + 8 * sizes (take i)` bytes below `a`, as a chain. -/
theorem FieldWrites.of_fold {P : Core.Program} {st : Semantics.State} {a c : Nat} {FS : List SrcType}
    {VS : List Value} {g : Memory.Heap → Nat → Except Trap Memory.Heap}
    (step : ∀ (i : Nat) f x h0 h1, FS[i]? = some f → VS[i]? = some x → g h0 i = .ok h1 →
      c + 8 * sizes (FS.take i) ≤ a ∧
        ∃ k, Semantics.writeNativeValue k P st h0 f.toCore (a - (c + 8 * sizes (FS.take i))) x = .ok h1)
    (len : VS.length = FS.length) :
    ∀ {fs : List SrcType} {j : Nat} {h h' : Memory.Heap}, FS.drop j = fs →
      (List.range' j fs.length).foldlM g h = .ok h' →
      FieldWrites P st a fs (VS.drop j) (c + 8 * sizes (FS.take j)) h h'
  | [], j, h, h', dfs, run => by
    simp only [List.length_nil, List.range'_zero, List.foldlM_nil, pure, Except.pure, Except.ok.injEq] at run
    subst run
    have : VS.drop j = [] := by
      apply List.eq_nil_of_length_eq_zero
      have := congrArg List.length dfs
      simp only [List.length_drop, List.length_nil] at this ⊢
      omega
    rw [this]
    exact .nil
  | f :: fs, j, h, h', dfs, run => by
    obtain ⟨hf, dfs'⟩ := drop_cons_get dfs
    have jlt : j < VS.length := by rw [len]; exact (List.getElem?_eq_some_iff.mp hf).1
    obtain ⟨x, hx⟩ : ∃ x, VS[j]? = some x := ⟨VS[j], by simp [jlt]⟩
    have dvs : VS.drop j = x :: VS.drop (j + 1) := by
      rw [List.drop_eq_getElem_cons jlt]
      simp only [List.getElem?_eq_getElem jlt, Option.some.injEq] at hx
      rw [hx]
    simp only [List.length_cons, List.range'_succ, List.foldlM_cons] at run
    obtain ⟨h1, first, run⟩ := except_bind_ok run
    obtain ⟨le, wrote⟩ := step j f x h h1 hf hx first
    rw [dvs]
    refine .cons le wrote ?_
    have := FieldWrites.of_fold step len dfs' run
    rwa [sizes_take_succ hf, Nat.mul_add, ← Nat.add_assoc] at this

/-- `FieldWrites.of_fold` from the first field, the fold given first. -/
theorem FieldWrites.of_run {P : Core.Program} {st : Semantics.State} {a c : Nat} {FS : List SrcType}
    {VS : List Value} {g : Memory.Heap → Nat → Except Trap Memory.Heap} {h h' : Memory.Heap}
    (run : (List.range' 0 VS.length).foldlM g h = .ok h') (len : VS.length = FS.length)
    (step : ∀ (i : Nat) f x h0 h1, FS[i]? = some f → VS[i]? = some x → g h0 i = .ok h1 →
      c + 8 * sizes (FS.take i) ≤ a ∧
        ∃ k, Semantics.writeNativeValue k P st h0 f.toCore (a - (c + 8 * sizes (FS.take i))) x = .ok h1) :
    FieldWrites P st a FS VS c h h' := by
  have := FieldWrites.of_fold step len (j := 0) rfl (by rw [List.drop_zero, ← len]; exact run)
  simpa [sizes] using this

/-- Core's write of a declared struct of word types: its fields, one after another. -/
theorem writeNativeValue_struct_writes {sp : SrcProgram} {st : Semantics.State} {sid : Nat}
    {fields : List SrcType} {vals : List Value} (decl : structFields sp.decls.structs sid = some fields)
    (words : wordTypes sp.decls fields = true) {k a : Nat} {h h' : Memory.Heap}
    (w : Semantics.writeNativeValue (k + 1) sp.toCore st h (.structure sid) a (.structure sid vals) = .ok h') :
    FieldWrites sp.toCore st a fields vals 0 h h' := by
  rw [Semantics.writeNativeValue] at w
  simp only [bne_self_eq_false, Bool.false_eq_true, if_false, structFields_toCore decl, List.length_map] at w
  split at w
  all_goals try (simp at w; done)
  rename_i lenEq'
  have lenEq : vals.length = fields.length := by simpa using lenEq'
  rw [List.range_eq_range'] at w
  refine FieldWrites.of_run (FS := fields) (VS := vals) (a := a) (c := 0) w lenEq (fun i f x h0 h1 hf hx step => by
      simp only [List.getElem?_map, hf, hx, Option.map_some] at step
      split at step
      case h_2 => simp at step
      rename_i o ho
      rw [fieldOffset_word decl words ho] at step
      obtain ⟨a', below, step⟩ := except_bind_ok step
      obtain ⟨le, rfl⟩ := wordBelow_ok below
      exact ⟨by omega, k, by simpa using step⟩)

/-- Core's write of a declared enum of word-type payloads: its tag as 4 bytes,
then the payload fields one after another, from `8` bytes below it. -/
theorem writeNativeValue_enum_writes {sp : SrcProgram} {st : Semantics.State} {eid : Nat}
    {variants : List (List SrcType)} (decl : enumVariants sp.decls.enums eid = some variants)
    (words : wordVariants sp.decls variants = true) {variant : Nat} {fs : List SrcType} {payload : List Value}
    (hv : variants[variant]? = some fs) {k a : Nat} {h h' : Memory.Heap}
    (w : Semantics.writeNativeValue (k + 1) sp.toCore st h (.enumeration eid) a
      (.enumeration eid variant payload) = .ok h') :
    ∃ tagged, h.storeBytes a (Semantics.encodeNatLE 4 variant) = .ok tagged ∧
      FieldWrites sp.toCore st a fs payload 8 tagged h' := by
  have fw := wordVariants_get words hv
  rw [Semantics.writeNativeValue] at w
  simp only [bne_self_eq_false, Bool.false_eq_true, if_false, enumVariants_toCore decl, List.getElem?_map, hv,
    Option.map_some, List.length_map] at w
  split at w
  all_goals try (simp at w; done)
  rename_i lenEq'
  have lenEq : payload.length = fs.length := by simpa using lenEq'
  obtain ⟨tagged, tagStored, w⟩ := except_bind_ok w
  refine ⟨tagged, tagStored, ?_⟩
  rw [List.range_eq_range'] at w
  refine FieldWrites.of_run (FS := fs) (VS := payload) (a := a) (c := 8) w lenEq (fun i f x h0 h1 hf hx step => by
      simp only [hf, hx, Option.map_some] at step
      split at step
      case h_2 => simp at step
      rename_i widths hwidths
      rw [payloadOffset_word fw hwidths, NativeLayout.wordBytes] at step
      obtain ⟨a', below, step⟩ := except_bind_ok step
      obtain ⟨le, rfl⟩ := wordBelow_ok below
      refine ⟨by omega, k, ?_⟩
      rwa [show 8 * (1 + sizes (List.take i fs)) = 8 + 8 * sizes (List.take i fs) by omega] at step)

theorem FieldReads.rebase {P : Core.Program} {heap : Memory.Heap} {a c : Nat} :
    ∀ {fs : List SrcType} {xs : List Value} {off : Nat}, FieldReads P heap (a - c) fs xs off → c ≤ a →
      FieldReads P heap a fs xs (c + off)
  | [], [], _, .nil, _ => .nil
  | _ :: _, _ :: _, off, .cons le read more, ca => by
    refine .cons (by omega) (by rwa [Nat.sub_sub] at read) ?_
    have := FieldReads.rebase more ca
    rwa [← Nat.add_assoc] at this

theorem FieldWrites.rebase {P : Core.Program} {st : Semantics.State} {a c : Nat} :
    ∀ {fs : List SrcType} {xs : List Value} {off : Nat} {h h' : Memory.Heap},
      FieldWrites P st (a - c) fs xs off h h' → c ≤ a → FieldWrites P st a fs xs (c + off) h h'
  | [], [], _, _, _, .nil, _ => .nil
  | _ :: _, _ :: _, off, _, _, .cons le wrote more, ca => by
    refine .cons (by omega) (by rwa [Nat.sub_sub] at wrote) ?_
    have := FieldWrites.rebase more ca
    rwa [← Nat.add_assoc] at this

theorem wordElement_wordType {ds : SrcDecls} {e : SrcType} (h : wordElement ds e = true) : wordType ds e = true := by
  cases e <;> simp_all [wordElement]

theorem wordElement_size {ds : SrcDecls} {e : SrcType} (h : wordElement ds e = true) : 0 < e.size := by
  cases e with
  | struct sid fields => exact (wordType_struct (wordElement_wordType h)).2.2
  | enum => simp only [SrcType.size]; omega
  | _ => simp [wordElement] at h

/-- Where Core puts element `pos` of a raw slice of a word element type: its
word 0, `pos * size` words below the descriptor. -/
theorem rawSliceElementAddress_word {sp : SrcProgram} {element : SrcType} (hel : wordElement sp.decls element = true)
    {addr pos at_ : Nat} (h : Semantics.rawSliceElementAddress? sp.toCore element.toCore addr pos = .ok at_) :
    at_ = addr - pos * (8 * element.size) ∧ pos * (8 * element.size) ≤ addr ∧ element.size ≤ 4096 := by
  have ok := wordElement_wordType hel
  have npos := wordElement_size hel
  have agg : (∃ id, element.toCore = .structure id) ∨ ∃ id, element.toCore = .enumeration id := by
    cases element <;> simp_all [wordElement, SrcType.toCore]
  have agg2 := agg
  rcases agg2 with ⟨id, e⟩ | ⟨id, e⟩ <;>
    (rw [e] at h; simp only [Semantics.rawSliceElementAddress?] at h; rw [← e] at h)
  all_goals
    cases hwords : NativeLayout.valueWords? sp.toCore element.toCore with
    | none => simp [hwords] at h
    | some words =>
    cases hcbase : NativeLayout.elementBase? addr pos words with
    | none => simp [hwords, hcbase] at h
    | some cbase =>
    simp only [hwords, hcbase, pure, Except.pure, Except.ok.injEq] at h
    subst h
    rw [NativeLayout.valueWords?, show NativeLayout.maxDepth = 63 + 1 from rfl] at hwords
    have wLe := words_le_max agg hwords
    have wEq := wordType_words element ok hwords
    subst wEq
    simp only [NativeLayout.elementBase?] at hcbase
    split at hcbase
    all_goals try (simp at hcbase; done)
    rename_i notBelow
    simp only [Option.some.injEq, NativeLayout.wordBytes] at hcbase
    simp only [Bool.or_eq_true, beq_iff_eq, not_or, NativeLayout.wordBytes] at notBelow
    rw [show pos * element.size * 8 = pos * (8 * element.size) by
      rw [Nat.mul_assoc, Nat.mul_comm element.size 8]] at hcbase
    have fits : pos * (8 * element.size) ≤ addr := by
      have h2 : ¬ (addr < (pos * element.size + element.size - 1) * 8) := by
        intro lt
        have := notBelow.2
        simp [lt] at this
      rw [disp_eq pos element.size npos] at h2
      omega
    exact ⟨hcbase.symm, fits, by simpa [NativeLayout.maxWords] using wLe⟩

/-! ## The front pass's layout check -/

theorem foldl_sizes : ∀ (fs : List SrcType), (fs.map SrcType.size).foldl (· + ·) 0 = sizes fs
  | [] => rfl
  | f :: rest => by
    rw [List.map_cons, List.foldl_cons, foldl_add, foldl_sizes rest, sizes]
    omega

theorem withinLayout_depth {d : Nat} {t : SrcType} (h : withinLayout d t = true) : d ≤ 63 := by
  unfold withinLayout at h
  split at h
  · cases h
  · omega

mutual
/-- A word type within the layout limits from depth `d` has its mini size
in Core's words at fuel `64 - d`. -/
theorem wordType_layout {sp : SrcProgram} : ∀ (t : SrcType) {d k : Nat}, wordType sp.decls t = true →
    withinLayout d t = true → d + k = 64 → NativeLayout.words? k sp.toCore t.toCore = some t.size
  | t, d, k, ok, wl, e => by
    have dl := withinLayout_depth wl
    obtain ⟨k, rfl⟩ : ∃ k', k = k' + 1 := ⟨k - 1, by omega⟩
    rw [withinLayout.eq_def, if_neg (by omega)] at wl
    match t, ok, wl with
    | .i32, _, _ => exact words_word (w := .m32) rfl k
    | .bool, _, _ => exact words_word (w := .m32) rfl k
    | .uint kind, _, _ => cases kind <;> exact words_word (by rfl) k
    | .ptr, _, _ => exact words_word (w := .m64) rfl k
    | .isize, _, _ => exact words_word (w := .m64) rfl k
    | .sint kind, _, _ => cases kind <;> exact words_word (by rfl) k
    | .slice _, ok, _ => simp [wordType] at ok
    | .unit, ok, _ => simp [wordType] at ok
    | .struct sid fields, ok, wl =>
      obtain ⟨decl, words, pos⟩ := wordType_struct ok
      simp only [Bool.and_eq_true, decide_eq_true_eq] at wl
      have hm := wordTypes_layout fields words wl.2 (by omega : d + 1 + k = 64)
      simp only [SrcType.toCore, SrcType.size]
      rw [NativeLayout.words?]
      dsimp only
      rw [structFields_toCore decl]
      simp only [bind, Option.bind, hm, foldl_sizes]
      rw [if_pos (by simp only [NativeLayout.maxWords]; omega)]
      congr 1
      omega
    | .enum eid variants, ok, wl =>
      obtain ⟨decl, words, -, -⟩ := wordType_enum ok
      have hp := wordVariants_layout variants words wl (by omega : d + 1 + k = 64)
      simp only [SrcType.toCore, SrcType.size]
      rw [NativeLayout.words?]
      dsimp only
      rw [enumVariants_toCore decl]
      simp only [bind, Option.bind]
      split
      · rename_i hn
        exact absurd (hp.symm.trans hn) (by simp)
      · rename_i ps hs
        cases Option.some.inj (hs.symm.trans hp)
        dsimp only
        rw [foldl_max_map, maxMap_sizes]
        simp
termination_by structural t => t

theorem wordTypes_layout {sp : SrcProgram} : ∀ (fs : List SrcType) {d k : Nat}, wordTypes sp.decls fs = true →
    withinLayouts d fs = true → d + k = 64 →
    (fs.map SrcType.toCore).mapM (NativeLayout.words? k sp.toCore) = some (fs.map SrcType.size)
  | [], _, _, _, _, _ => rfl
  | f :: rest, d, k, ok, wl, e => by
    simp only [wordTypes, Bool.and_eq_true] at ok
    simp only [withinLayouts, Bool.and_eq_true] at wl
    simp only [List.map_cons, List.mapM_cons, wordType_layout f ok.1 wl.1 e, wordTypes_layout rest ok.2 wl.2 e,
      bind, Option.bind, pure]
termination_by structural fs => fs

theorem wordVariants_layout {sp : SrcProgram} : ∀ (vs : List (List SrcType)) {d k : Nat},
    wordVariants sp.decls vs = true → withinPayloads d vs = true → d + k = 64 →
    (vs.map (List.map SrcType.toCore)).mapM (payloadWords k sp.toCore) = some (vs.map sizes)
  | [], _, _, _, _, _ => rfl
  | fs :: rest, d, k, ok, wl, e => by
    simp only [wordVariants, Bool.and_eq_true] at ok
    simp only [withinPayloads, Bool.and_eq_true, decide_eq_true_eq] at wl
    have hfs := wordTypes_layout fs ok.1 wl.1.2 e
    have hrest := wordVariants_layout rest ok.2 wl.2 e
    simp only [List.map_cons, List.mapM_cons, hrest, bind, Option.bind, pure, payloadWords, hfs, foldl_sizes]
    rw [if_pos (by simp only [NativeLayout.maxWords]; omega)]
termination_by structural vs => vs
end

/-- A raw slice the front pass lowers has an element type Core lays out, at
its mini size. -/
theorem lowerSlice_layout {sp : SrcProgram} {element : SrcType} {p l : Option Expr} {xs : List Expr}
    (h : lowerSlice sp.decls element p l = some xs) :
    NativeLayout.valueWords? sp.toCore element.toCore = some element.size := by
  unfold lowerSlice at h
  split at h
  · rename_i cond
    simp only [Bool.and_eq_true, Bool.or_eq_true] at cond
    have ok : wordType sp.decls element = true := by
      rcases cond.1 with c | c
      · cases element <;> simp_all [SrcType.isI32, wordType]
      · exact wordElement_wordType c
    exact wordType_layout element ok cond.2 rfl
  · cases h

end Lanius.Mini
