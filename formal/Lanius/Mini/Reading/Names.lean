import Lanius.Mini.Reading.Decls

/-! # The reading, V8a: names

What the modules' names must satisfy (`WellNamed`), the primitive types'
spellings (`primName`), and what the lookups find: a declaration of the
module with the spelling (`TypeNamed`, `FnNamed`, ...). Under `WellNamed`
there is at most one. -/

namespace Lanius.Mini.Reading

open Lanius.Mini

/-! ## The names a module gives -/

/-- The module's free functions' spellings (methods are not named here). -/
def fnNames (d : Decls) (m : ModPath) : List Name :=
  (d.fns.filter fun f => !f.inImpl && decide (f.home = m)).map (·.name)

/-- The module's structs' and enums' spellings. -/
def typeOnlyNames (d : Decls) (m : ModPath) : List Name :=
  (d.types.filter fun t => decide (t.home = m)).map (·.name)

/-- The module's types' spellings, each followed by its variants'. -/
def typeNames (d : Decls) (m : ModPath) : List Name :=
  (d.types.filter fun t => decide (t.home = m)).flatMap fun t => t.name :: t.variants

def aliasNames (d : Decls) (m : ModPath) : List Name :=
  (d.aliases.filter fun a => decide (a.home = m)).map (·.name)

def constNames (d : Decls) (m : ModPath) : List Name :=
  (d.consts.filter fun c => decide (c.home = m)).map (·.name)

/-- The primitive types' spellings: `i32`, `bool`, `u8`, `u32`, `u64`,
`usize`, `ptr` and `isize`. -/
def primNames : List (Name × SrcType) :=
  [([105, 51, 50], .i32), ([98, 111, 111, 108], .bool), ([117, 56], .uint .uint8), ([117, 51, 50], .uint .uint32),
   ([117, 54, 52], .uint .uint64), ([117, 115, 105, 122, 101], .uint .usize), ([112, 116, 114], .ptr),
   ([105, 115, 105, 122, 101], .isize)]

def primName (n : Name) : Option SrcType := primNames.lookup n

/-- The files are distinct modules. In each module the free functions,
types, aliases and constants have distinct spellings, and each enum's
variants are distinct and spelled like no free function or constant of the
module. No type or alias is spelled like a primitive type. -/
def WellNamed (c : Collected) : Prop :=
  c.modules.Nodup ∧
  (∀ m ∈ c.modules, (fnNames c.decls m ++ (typeOnlyNames c.decls m ++ (aliasNames c.decls m ++ constNames c.decls m))).Nodup ∧
    ∀ t ∈ c.decls.types, t.isEnum = true → t.home = m →
      t.variants.Nodup ∧ ∀ v ∈ t.variants, v ∉ fnNames c.decls m ++ constNames c.decls m) ∧
  (∀ t ∈ c.decls.types, primName t.name = none) ∧ (∀ a ∈ c.decls.aliases, primName a.name = none)

/-! ## Soundness of the name checks -/

theorem fnNamesIn_eq (d : Decls) (m : ModPath) : fnNamesIn d.fns m = fnNames d m := by
  unfold fnNames
  induction d.fns with
  | nil => rfl
  | cons f rest ih =>
    simp only [fnNamesIn, List.filter_cons]
    by_cases h : (!f.inImpl && sameSpellings f.home m) = true
    · have h' : (!f.inImpl && decide (f.home = m)) = true := by simpa [sameSpellings_iff] using h
      rw [if_pos h, if_pos h', List.map_cons, ih]
    · have h' : ¬(!f.inImpl && decide (f.home = m)) = true := by simpa [sameSpellings_iff] using h
      rw [if_neg h, if_neg h', ih]

theorem typeOnlyNamesIn_eq (d : Decls) (m : ModPath) : typeOnlyNamesIn d.types m = typeOnlyNames d m := by
  unfold typeOnlyNames
  induction d.types with
  | nil => rfl
  | cons t rest ih =>
    simp only [typeOnlyNamesIn, List.filter_cons]
    by_cases h : t.home = m
    · rw [if_pos ((sameSpellings_iff _ _).2 h), if_pos (by simpa using h), List.map_cons, ih]
    · rw [if_neg (by rw [sameSpellings_iff]; exact h), if_neg (by simpa using h), ih]

theorem typeNamesIn_eq (d : Decls) (m : ModPath) : typeNamesIn d.types m = typeNames d m := by
  unfold typeNames
  induction d.types with
  | nil => rfl
  | cons t rest ih =>
    simp only [typeNamesIn, List.filter_cons]
    by_cases h : t.home = m
    · rw [if_pos ((sameSpellings_iff _ _).2 h), if_pos (by simpa using h), List.flatMap_cons, ih]
      rfl
    · rw [if_neg (by rw [sameSpellings_iff]; exact h), if_neg (by simpa using h), ih]

theorem aliasNamesIn_eq (d : Decls) (m : ModPath) : aliasNamesIn d.aliases m = aliasNames d m := by
  unfold aliasNames
  induction d.aliases with
  | nil => rfl
  | cons a rest ih =>
    simp only [aliasNamesIn, List.filter_cons]
    by_cases h : a.home = m
    · rw [if_pos ((sameSpellings_iff _ _).2 h), if_pos (by simpa using h), List.map_cons, ih]
    · rw [if_neg (by rw [sameSpellings_iff]; exact h), if_neg (by simpa using h), ih]

theorem constNamesIn_eq (d : Decls) (m : ModPath) : constNamesIn d.consts m = constNames d m := by
  unfold constNames
  induction d.consts with
  | nil => rfl
  | cons c rest ih =>
    simp only [constNamesIn, List.filter_cons]
    by_cases h : c.home = m
    · rw [if_pos ((sameSpellings_iff _ _).2 h), if_pos (by simpa using h), List.map_cons, ih]
    · rw [if_neg (by rw [sameSpellings_iff]; exact h), if_neg (by simpa using h), ih]

theorem noneMember_iff : ∀ (names others : List Name), noneMember names others = true ↔ ∀ n ∈ names, n ∉ others
  | [], _ => by simp [noneMember]
  | n :: rest, others => by
    have := member_iff others n
    cases hm : member others n <;> simp_all [noneMember, noneMember_iff rest others]

theorem enumsNamedOk_iff (m : ModPath) (values : List Name) : ∀ (types : List TypeDecl),
    enumsNamedOk types m values = true ↔
      ∀ t ∈ types, t.isEnum = true → t.home = m → t.variants.Nodup ∧ ∀ v ∈ t.variants, v ∉ values
  | [] => by simp [enumsNamedOk]
  | t :: rest => by
    rw [enumsNamedOk, Bool.and_eq_true, enumsNamedOk_iff m values rest, List.forall_mem_cons]
    apply and_congr_left'
    simp only [enumNamedOk]
    by_cases e : t.isEnum = true <;> by_cases hm : t.home = m
    · rw [if_pos (by simp [e, sameSpellings_iff, hm]), Bool.and_eq_true, distinct_iff, noneMember_iff]
      simp [e, hm]
    · rw [if_neg (by simp [sameSpellings_iff, hm])]
      simp [hm]
    · rw [if_neg (by simp [e])]
      simp [e]
    · rw [if_neg (by simp [e])]
      simp [e]

theorem spelled_iff0 (n : Name) : spelled0 n = true ↔ n = [] := by
  cases n <;> simp [spelled0]

theorem spelled_iff1 (n : Name) (a : Nat) : spelled1 n a = true ↔ n = [a] := by
  cases n <;> simp [spelled1, spelled_iff0]

theorem spelled_iff2 (n : Name) (a b : Nat) : spelled2 n a b = true ↔ n = [a, b] := by
  cases n <;> simp [spelled2, spelled_iff1]

theorem spelled_iff3 (n : Name) (a b c : Nat) : spelled3 n a b c = true ↔ n = [a, b, c] := by
  cases n <;> simp [spelled3, spelled_iff2]

theorem spelled_iff4 (n : Name) (a b c d : Nat) : spelled4 n a b c d = true ↔ n = [a, b, c, d] := by
  cases n <;> simp [spelled4, spelled_iff3]

theorem spelled_iff5 (n : Name) (a b c d e : Nat) : spelled5 n a b c d e = true ↔ n = [a, b, c, d, e] := by
  cases n <;> simp [spelled5, spelled_iff4]

theorem primitive_eq (n : Name) : primitive n = primName n := by
  simp only [primitive]
  by_cases h1 : n = [105, 51, 50]
  · subst h1; rfl
  rw [if_neg (by rw [spelled_iff3]; exact h1)]
  by_cases h2 : n = [98, 111, 111, 108]
  · subst h2; rfl
  rw [if_neg (by rw [spelled_iff4]; exact h2)]
  by_cases h3 : n = [117, 56]
  · subst h3; rfl
  rw [if_neg (by rw [spelled_iff2]; exact h3)]
  by_cases h4 : n = [117, 51, 50]
  · subst h4; rfl
  rw [if_neg (by rw [spelled_iff3]; exact h4)]
  by_cases h5 : n = [117, 54, 52]
  · subst h5; rfl
  rw [if_neg (by rw [spelled_iff3]; exact h5)]
  by_cases h6 : n = [117, 115, 105, 122, 101]
  · subst h6; rfl
  rw [if_neg (by rw [spelled_iff5]; exact h6)]
  by_cases h7 : n = [112, 116, 114]
  · subst h7; rfl
  rw [if_neg (by rw [spelled_iff3]; exact h7)]
  by_cases h8 : n = [105, 115, 105, 122, 101]
  · subst h8; rfl
  rw [if_neg (by rw [spelled_iff5]; exact h8)]
  simp [primName, primNames, List.lookup, beq_false_of_ne h1, beq_false_of_ne h2, beq_false_of_ne h3,
    beq_false_of_ne h4, beq_false_of_ne h5, beq_false_of_ne h6, beq_false_of_ne h7, beq_false_of_ne h8]

theorem noPrimitive_iff : ∀ (types : List TypeDecl), noPrimitive types = true ↔ ∀ t ∈ types, primName t.name = none
  | [] => by simp [noPrimitive]
  | t :: rest => by
    rw [noPrimitive, Bool.and_eq_true, noPrimitive_iff rest, List.forall_mem_cons, primitive_eq]
    cases primName t.name <;> simp [isNoneType]

theorem noPrimitiveAlias_iff : ∀ (aliases : List AliasDecl),
    noPrimitiveAlias aliases = true ↔ ∀ a ∈ aliases, primName a.name = none
  | [] => by simp [noPrimitiveAlias]
  | a :: rest => by
    rw [noPrimitiveAlias, Bool.and_eq_true, noPrimitiveAlias_iff rest, List.forall_mem_cons, primitive_eq]
    cases primName a.name <;> simp [isNoneType]

theorem wellNamed_sound {c : Collected} (h : wellNamed c = true) : WellNamed c := by
  simp only [wellNamed, Bool.and_eq_true] at h
  obtain ⟨⟨⟨dm, dn⟩, np⟩, na⟩ := h
  refine ⟨(distinctModules_iff _).1 dm, ?_, (noPrimitive_iff _).1 np, (noPrimitiveAlias_iff _).1 na⟩
  intro m mem
  have : ∀ ms : List ModPath, modulesDistinctNames c.decls ms = true → m ∈ ms → moduleNamesOk c.decls m = true := by
    intro ms
    induction ms with
    | nil => intro _ h; cases h
    | cons x rest ih =>
      intro h mem
      simp only [modulesDistinctNames, Bool.and_eq_true] at h
      rcases List.mem_cons.1 mem with rfl | mem
      · exact h.1
      · exact ih h.2 mem
  have ok := this _ dn mem
  simp only [moduleNamesOk, Bool.and_eq_true, distinct_iff, fnNamesIn_eq, typeOnlyNamesIn_eq, aliasNamesIn_eq,
    constNamesIn_eq, enumsNamedOk_iff] at ok
  exact ok

end Lanius.Mini.Reading
