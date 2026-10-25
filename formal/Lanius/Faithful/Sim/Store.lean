import Lanius.Faithful.Sim.Codec

/-! # Native stores of word-type values

A Core value that means a pure value at a word type (`wordType`), the types
`boxed` stores, has a native store of its type's words that reads it back
(`store_spec`): scalars by their codecs, structs and boxes as records of
their fields, enums as their tag and payload. -/

namespace Lanius.Faithful

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (NativeStoreSpec)

theorem mapM_option_take {α β : Type} {g : α → Option β} :
    ∀ {l : List α} {r : List β} (i : Nat), l.mapM g = some r → (l.take i).mapM g = some (r.take i)
  | [], r, i, h => by
    simp only [List.mapM_nil, pure, Option.some.injEq] at h
    subst h
    simp
  | a :: rest, r, 0, h => by simp
  | a :: rest, r, i + 1, h => by
    obtain ⟨b, bs, hb, hbs, rfl⟩ := mapM_option_cons h
    simp only [List.take_succ_cons, List.mapM_cons, hb, mapM_option_take i hbs]
    rfl

theorem mapM_option_get {α β : Type} {g : α → Option β} :
    ∀ {l : List α} {r : List β} {i : Nat} {x : α}, l.mapM g = some r → l[i]? = some x →
      ∃ y, g x = some y ∧ r[i]? = some y
  | [], _, _, _, _, found => by simp at found
  | a :: rest, r, 0, x, h, found => by
    obtain ⟨b, bs, hb, hbs, rfl⟩ := mapM_option_cons h
    simp only [List.getElem?_cons_zero, Option.some.injEq] at found
    subst found
    exact ⟨b, hb, rfl⟩
  | a :: rest, r, i + 1, x, h, found => by
    obtain ⟨b, bs, hb, hbs, rfl⟩ := mapM_option_cons h
    simp only [List.getElem?_cons_succ] at found ⊢
    exact mapM_option_get hbs found

theorem sizes_take_le : ∀ (fs : List SrcType) {i j : Nat}, i ≤ j → sizes (fs.take i) ≤ sizes (fs.take j)
  | [], _, _, _ => by simp [sizes]
  | f :: rest, 0, j, _ => by simp [sizes]
  | f :: rest, i + 1, 0, le => by omega
  | f :: rest, i + 1, j + 1, le => by
    simp only [List.take_succ_cons, sizes]
    have := sizes_take_le rest (show i ≤ j by omega)
    omega

theorem sizes_take_all (fs : List SrcType) (i : Nat) : sizes (fs.take i) ≤ sizes fs := by
  have := sizes_take_le fs (Nat.le_max_left i fs.length)
  rwa [List.take_of_length_le (Nat.le_max_right i fs.length)] at this

theorem wordType_pos {ds : SrcDecls} : ∀ {t : SrcType}, wordType ds t = true → 0 < t.size
  | .i32, _ => by decide
  | .bool, _ => by decide
  | .uint _, _ => by simp [SrcType.size]
  | .struct _ _, ok => (wordType_struct ok).2.2
  | .enum _ _, _ => by simp only [SrcType.size]; omega
  | .ptr, _ => by decide
  | .isize, _ => by decide
  | .slice _, ok => by simp [wordType] at ok
  | .unit, ok => by simp [wordType] at ok

section
variable {sp : SrcProgram} {boxes : Boxes}

/-- The store contract of every word-type value with fuel `n`. -/
def StoreAt (sp : SrcProgram) (boxes : Boxes) (n : Nat) : Prop :=
  ∀ {heap : Memory.Heap} {t : SrcType} {v p : Value} {w : Nat}, VRel sp.toCore boxes heap t v p →
    wordType sp.decls t = true → NativeLayout.words? n sp.toCore t.toCore = some w → n ≤ NativeLayout.maxDepth →
    NativeStoreSpec n sp.toCore t.toCore v (8 * w)

theorem getD_map_toCore {fs : List SrcType} {i : Nat} {f : SrcType} (found : fs[i]? = some f) :
    ((fs.map SrcType.toCore)[i]?).getD .unit = f.toCore := by
  simp [found]

/-- The fields' stores, from the store contract one level down. -/
theorem fields_spec {n : Nat} (ih : StoreAt sp boxes n) {heap : Memory.Heap} {fs : List SrcType}
    {vs ps : List Value} {ws : List Nat} (words : wordTypes sp.decls fs = true)
    (rs : VRels sp.toCore boxes heap fs vs ps)
    (hws : (fs.map SrcType.toCore).mapM (NativeLayout.words? n sp.toCore) = some ws) (le : n ≤ NativeLayout.maxDepth) :
    ∀ i, i < vs.length → NativeStoreSpec n sp.toCore (((fs.map SrcType.toCore)[i]?).getD .unit)
      ((vs[i]?).getD .unit) (8 * (((fs[i]?).map SrcType.size).getD 0)) := by
  intro i inside
  obtain ⟨v, hv⟩ : ∃ v, vs[i]? = some v := ⟨vs[i], List.getElem?_eq_getElem inside⟩
  obtain ⟨f, p, hf, hp, r⟩ := rs.get hv
  have mem : (fs.map SrcType.toCore)[i]? = some f.toCore := by simp [hf]
  obtain ⟨wf, hwf, -⟩ := mapM_option_get hws mem
  have okf := wordTypes_get words hf
  have := wordType_words f okf hwf
  subst this
  rw [getD_map_toCore hf, hv, hf]
  exact ih r okf hwf le

/-- Field `i`'s size, and the sizes of the fields before it. -/
theorem field_size {ds : SrcDecls} {fs : List SrcType} {vs : List Value} (words : wordTypes ds fs = true)
    (length : vs.length = fs.length) (i : Nat) (inside : i < vs.length) :
    ∃ f : SrcType, (((fs[i]?).map SrcType.size).getD 0) = f.size ∧
      sizes (fs.take (i + 1)) = sizes (fs.take i) + f.size ∧ 0 < f.size := by
  obtain ⟨f, hf⟩ : ∃ f, fs[i]? = some f := ⟨fs[i], List.getElem?_eq_getElem (by omega)⟩
  exact ⟨f, by simp [hf], sizes_take_succ hf, wordType_pos (wordTypes_get words hf)⟩

/-- A struct's store, from its fields' stores: field `i` is `8 * sizes (take i)` bytes down. -/
theorem record_spec {n : Nat} {id : Nat} {fs : List SrcType} {vs : List Value} {ws : List Nat}
    (hdecl : sp.toCore.structure? id = some ⟨id, fs.map SrcType.toCore⟩) (words : wordTypes sp.decls fs = true)
    (length : vs.length = fs.length)
    (hws : (fs.map SrcType.toCore).mapM (NativeLayout.words? (NativeLayout.maxDepth - 1) sp.toCore) = some ws)
    (codecs : ∀ i, i < vs.length → NativeStoreSpec n sp.toCore (((fs.map SrcType.toCore)[i]?).getD .unit)
      ((vs[i]?).getD .unit) (8 * (((fs[i]?).map SrcType.size).getD 0))) :
    NativeStoreSpec (n + 1) sp.toCore (.structure id) (.structure id vs) (8 * sizes fs) := by
  apply NativeStoreSpec.record hdecl (by simpa using length) (offset := fun i => 8 * sizes (fs.take i))
    (width := fun i => 8 * (((fs[i]?).map SrcType.size).getD 0))
  · intro i inside
    have take := mapM_option_take i hws
    rw [← List.map_take] at take
    simp only [NativeLayout.structureFieldOffset?, hdecl, bind, Option.bind, List.length_map,
      if_pos (show i < fs.length by omega), ← List.map_take, take,
      wordTypes_words _ (wordTypes_take words i) take, NativeLayout.wordBytes]
  · intro i inside
    obtain ⟨f, hs, step, -⟩ := field_size words length i inside
    have := sizes_take_all fs (i + 1)
    rw [hs]
    omega
  · intro i inside
    obtain ⟨f, hs, -, pos⟩ := field_size words length i inside
    rw [hs]
    omega
  · intro l r lt inside
    obtain ⟨f, hs, step, -⟩ := field_size words length l (by omega)
    have := sizes_take_le fs (show l + 1 ≤ r by omega)
    rw [hs]
    omega
  · exact codecs

/-- Variant `k`'s store, from its fields' stores: field `i` is the tag's word and
`sizes (take i)` words down. -/
theorem variant_spec {n : Nat} {id k : Nat} {variants : List (List SrcType)} {fs : List SrcType} {vs : List Value}
    {ws : List Nat}
    (hdecl : sp.toCore.enumeration? id = some ⟨id, variants.map (List.map SrcType.toCore)⟩)
    (hk : variants[k]? = some fs) (fits : variants.length < 4294967296) (words : wordTypes sp.decls fs = true)
    (length : vs.length = fs.length)
    (hws : (fs.map SrcType.toCore).mapM (NativeLayout.words? (NativeLayout.maxDepth - 1) sp.toCore) = some ws)
    (codecs : ∀ i, i < vs.length → NativeStoreSpec n sp.toCore (((fs.map SrcType.toCore)[i]?).getD .unit)
      ((vs[i]?).getD .unit) (8 * (((fs[i]?).map SrcType.size).getD 0))) :
    NativeStoreSpec (n + 1) sp.toCore (.enumeration id) (.enumeration id k vs) (8 * (1 + maxSize variants)) := by
  have kl : k < variants.length := by
    rcases List.getElem?_eq_some_iff.mp hk with ⟨lt, -⟩
    exact lt
  have most := sizes_le_maxSize hk
  apply NativeStoreSpec.variant hdecl (k := k) (types := fs.map SrcType.toCore) (by simp [hk]) (by omega)
    (by simpa using length) (offset := fun i => 8 * (1 + sizes (fs.take i)))
    (width := fun i => 8 * (((fs[i]?).map SrcType.size).getD 0))
  · intro i inside
    have take := mapM_option_take i hws
    exact ⟨ws.take i, take, by rw [payloadOffset_word words take, NativeLayout.wordBytes]⟩
  · intro i inside
    omega
  · intro i inside
    obtain ⟨f, hs, step, -⟩ := field_size words length i inside
    have := sizes_take_all fs (i + 1)
    rw [hs]
    omega
  · intro i inside
    obtain ⟨f, hs, -, pos⟩ := field_size words length i inside
    rw [hs]
    omega
  · intro l r lt inside
    obtain ⟨f, hs, step, -⟩ := field_size words length l (by omega)
    have := sizes_take_le fs (show l + 1 ≤ r by omega)
    rw [hs]
    omega
  · omega
  · exact codecs

end

/-- A struct's words have its fields' words at one less fuel. -/
theorem struct_words {P : Core.Program} {n id w : Nat} {decl : Core.StructDecl}
    (words : NativeLayout.words? (n + 1) P (.structure id) = some w) (found : P.structure? id = some decl) :
    ∃ ws, decl.fields.mapM (NativeLayout.words? n P) = some ws := by
  rw [NativeLayout.words?] at words
  simp only [found, bind, Option.bind] at words
  split at words
  · simp at words
  · exact ⟨_, by assumption⟩

/-- An enum's words have each variant's fields' words at one less fuel. -/
theorem enum_words {P : Core.Program} {n id w k : Nat} {decl : Core.EnumDecl} {types : List Core.Ty}
    (words : NativeLayout.words? (n + 1) P (.enumeration id) = some w) (found : P.enumeration? id = some decl)
    (variant : decl.variants[k]? = some types) :
    ∃ ws, types.mapM (NativeLayout.words? n P) = some ws := by
  rw [NativeLayout.words?] at words
  simp only [found, bind, Option.bind] at words
  split at words
  · simp at words
  rename_i payloads hps
  obtain ⟨total, ht, -⟩ := mapM_option_get hps variant
  try simp only [bind, Option.bind] at ht
  split at ht
  · simp at ht
  · exact ⟨_, by assumption⟩

section
variable {sp : SrcProgram} {boxes : Boxes}

/-- Every word-type value that means a pure value has a store of its words. -/
theorem store_spec : ∀ n, StoreAt sp boxes n
  | 0 => by
    intro _ _ words _
    simp [NativeLayout.words?] at words
  | n + 1 => by
    intro r ok words le
    rename_i heap t v p w
    have ih : StoreAt sp boxes n := store_spec n
    have hw := wordType_words t ok words
    subst hw
    have up : ∀ x y, NativeLayout.words? n sp.toCore x = some y →
        NativeLayout.words? (NativeLayout.maxDepth - 1) sp.toCore x = some y :=
      fun x y h => words_mono n h (by omega)
    cases r with
    | scalar s =>
      have notUnit : t ≠ .unit := by rintro rfl; simp [wordType] at ok
      cases t with
      | struct _ _ => exact s.elim
      | enum _ _ => exact s.elim
      | ptr => exact s.elim
      | slice _ => exact s.elim
      | i32 => exact NativeStoreSpec.sty s notUnit
      | bool => exact NativeStoreSpec.sty s notUnit
      | uint _ => exact NativeStoreSpec.sty s notUnit
      | isize => exact NativeStoreSpec.sty s notUnit
      | unit => exact absurd rfl notUnit
    | struct none rs =>
      obtain ⟨decl, fieldWords, -⟩ := wordType_struct ok
      have hdecl := structFields_toCore (sp := sp) decl
      obtain ⟨ws, hws⟩ := struct_words words hdecl
      exact record_spec hdecl fieldWords (VRels.length rs).1 (mapM_option_mono up hws)
        (fields_spec ih fieldWords rs hws (by omega))
    | enum hk rs =>
      rename_i id variants k fs vs ps
      obtain ⟨decl, variantWords, -, fits⟩ := wordType_enum ok
      have hdecl := enumVariants_toCore (sp := sp) decl
      have fieldWords := wordVariants_get variantWords hk
      obtain ⟨ws, hws⟩ := enum_words words hdecl (k := k) (types := fs.map SrcType.toCore) (by simp [hk])
      exact variant_spec hdecl hk fits fieldWords (VRels.length rs).1 (mapM_option_mono up hws)
        (fields_spec ih fieldWords rs hws (by omega))
    | box found wv pos room read rel =>
      rename_i a _ _
      obtain ⟨decl, fieldWords, -⟩ := wordType_struct ok
      have hdecl := structFields_toCore (sp := sp) decl
      obtain ⟨ws, hws⟩ := struct_words words hdecl
      obtain ⟨m, rfl⟩ : ∃ m, n = m + 1 := by
        cases n with
        | zero => simp [NativeLayout.words?] at hws
        | succ m => exact ⟨m, rfl⟩
      apply record_spec hdecl fieldWords (vs := [.pointer a]) rfl (mapM_option_mono up hws)
      intro i inside
      obtain rfl : i = 0 := by simp at inside; omega
      exact NativeStoreSpec.rawPtr (by omega)

end

end Lanius.Faithful
