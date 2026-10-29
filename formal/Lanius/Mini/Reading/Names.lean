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

/-! ## The lookups

A lookup finds a declaration of the module with the spelling, or reports
that there is none. -/

/-- Type `i` of the declarations is module `m`'s struct or enum `name`. -/
def TypeNamed (d : Decls) (m : ModPath) (name : Name) (i : Nat) : Prop :=
  ∃ t, d.types[i]? = some t ∧ t.home = m ∧ t.name = name

/-- Function `i` is module `m`'s free function `name`. -/
def FnNamed (d : Decls) (m : ModPath) (name : Name) (i : Nat) : Prop :=
  ∃ f, d.fns[i]? = some f ∧ f.inImpl = false ∧ f.home = m ∧ f.name = name

def ConstNamed (d : Decls) (m : ModPath) (name : Name) (c : ConstDecl) : Prop :=
  c ∈ d.consts ∧ c.home = m ∧ c.name = name

def AliasNamed (d : Decls) (m : ModPath) (name : Name) (a : AliasDecl) : Prop :=
  a ∈ d.aliases ∧ a.home = m ∧ a.name = name

/-- Variant `v.index` of type `v.owner` is spelled `name`, and the type is
an enum of module `m`. -/
def VariantNamed (d : Decls) (m : ModPath) (name : Name) (v : VariantAt) : Prop :=
  ∃ t, d.types[v.owner]? = some t ∧ t.isEnum = true ∧ t.home = m ∧ t.variants[v.index]? = some name

theorem position_sound : ∀ (names : List Name) (name : Name) (k j : Nat),
    position names name k = some j → k ≤ j ∧ names[j - k]? = some name
  | [], _, _, _, h => by simp [position] at h
  | n :: rest, name, k, j, h => by
    rw [position] at h
    by_cases e : sameText n name = true
    · rw [if_pos e] at h
      cases h
      exact ⟨Nat.le_refl _, by simp [(sameText_iff _ _).1 e]⟩
    · rw [if_neg e] at h
      obtain ⟨le, got⟩ := position_sound rest name (k + 1) j h
      refine ⟨by omega, ?_⟩
      rw [show j - k = (j - (k + 1)) + 1 by omega]
      simpa using got

theorem position_none : ∀ (names : List Name) (name : Name) (k : Nat),
    position names name k = none → name ∉ names
  | [], _, _, _ => by simp
  | n :: rest, name, k, h => by
    rw [position] at h
    by_cases e : sameText n name = true
    · rw [if_pos e] at h; cases h
    · rw [if_neg e] at h
      have := position_none rest name (k + 1) h
      rw [sameText_iff] at e
      simp only [List.mem_cons, not_or]
      exact ⟨fun h => e h.symm, this⟩

theorem findType_sound' : ∀ (types : List TypeDecl) (m : ModPath) (name : Name) (k i : Nat),
    findType types m name k = some i → k ≤ i ∧ ∃ t, types[i - k]? = some t ∧ t.home = m ∧ t.name = name
  | [], _, _, _, _, h => by simp [findType] at h
  | t :: rest, m, name, k, i, h => by
    rw [findType] at h
    by_cases e : (sameText t.name name && sameSpellings t.home m) = true
    · rw [if_pos e] at h
      cases h
      simp only [Bool.and_eq_true, sameText_iff, sameSpellings_iff] at e
      exact ⟨Nat.le_refl _, t, by simp, e.2, e.1⟩
    · rw [if_neg e] at h
      obtain ⟨le, t', got, rest'⟩ := findType_sound' rest m name (k + 1) i h
      refine ⟨by omega, t', ?_, rest'⟩
      rw [show i - k = (i - (k + 1)) + 1 by omega]
      simpa using got

theorem findType_sound {d : Decls} {m : ModPath} {name : Name} {i : Nat}
    (h : findType d.types m name 0 = some i) : TypeNamed d m name i := by
  unfold TypeNamed
  simpa using (findType_sound' d.types m name 0 i h).2

theorem findType_none : ∀ (types : List TypeDecl) (m : ModPath) (name : Name) (k : Nat),
    findType types m name k = none → ∀ t ∈ types, ¬(t.home = m ∧ t.name = name)
  | [], _, _, _, _ => by simp
  | t :: rest, m, name, k, h => by
    rw [findType] at h
    by_cases e : (sameText t.name name && sameSpellings t.home m) = true
    · rw [if_pos e] at h; cases h
    · rw [if_neg e] at h
      simp only [Bool.and_eq_true, sameText_iff, sameSpellings_iff] at e
      intro u mem
      rcases List.mem_cons.1 mem with rfl | mem
      · exact fun ⟨a, b⟩ => e ⟨b, a⟩
      · exact findType_none rest m name (k + 1) h u mem

theorem findFn_sound' : ∀ (fns : List FnDecl) (m : ModPath) (name : Name) (k i : Nat),
    findFn fns m name k = some i →
      k ≤ i ∧ ∃ f, fns[i - k]? = some f ∧ f.inImpl = false ∧ f.home = m ∧ f.name = name
  | [], _, _, _, _, h => by simp [findFn] at h
  | f :: rest, m, name, k, i, h => by
    rw [findFn] at h
    by_cases e : (!f.inImpl && sameText f.name name && sameSpellings f.home m) = true
    · rw [if_pos e] at h
      cases h
      simp only [Bool.and_eq_true, Bool.not_eq_true', sameText_iff, sameSpellings_iff] at e
      exact ⟨Nat.le_refl _, f, by simp, e.1.1, e.2, e.1.2⟩
    · rw [if_neg e] at h
      obtain ⟨le, f', got, rest'⟩ := findFn_sound' rest m name (k + 1) i h
      refine ⟨by omega, f', ?_, rest'⟩
      rw [show i - k = (i - (k + 1)) + 1 by omega]
      simpa using got

theorem findFn_sound {d : Decls} {m : ModPath} {name : Name} {i : Nat}
    (h : findFn d.fns m name 0 = some i) : FnNamed d m name i := by
  unfold FnNamed
  simpa using (findFn_sound' d.fns m name 0 i h).2

theorem findFn_none : ∀ (fns : List FnDecl) (m : ModPath) (name : Name) (k : Nat),
    findFn fns m name k = none → ∀ f ∈ fns, ¬(f.inImpl = false ∧ f.home = m ∧ f.name = name)
  | [], _, _, _, _ => by simp
  | f :: rest, m, name, k, h => by
    rw [findFn] at h
    by_cases e : (!f.inImpl && sameText f.name name && sameSpellings f.home m) = true
    · rw [if_pos e] at h; cases h
    · rw [if_neg e] at h
      simp only [Bool.and_eq_true, Bool.not_eq_true', sameText_iff, sameSpellings_iff] at e
      intro u mem
      rcases List.mem_cons.1 mem with rfl | mem
      · exact fun ⟨a, b, c⟩ => e ⟨⟨a, c⟩, b⟩
      · exact findFn_none rest m name (k + 1) h u mem

theorem findConst_sound' : ∀ (consts : List ConstDecl) (m : ModPath) (name : Name) (c : ConstDecl),
    findConst consts m name = some c → c ∈ consts ∧ c.home = m ∧ c.name = name
  | [], _, _, _, h => by simp [findConst] at h
  | x :: rest, m, name, c, h => by
    rw [findConst] at h
    by_cases e : (sameText x.name name && sameSpellings x.home m) = true
    · rw [if_pos e] at h
      cases h
      simp only [Bool.and_eq_true, sameText_iff, sameSpellings_iff] at e
      exact ⟨by simp, e.2, e.1⟩
    · rw [if_neg e] at h
      obtain ⟨mem, rest'⟩ := findConst_sound' rest m name c h
      exact ⟨List.mem_cons_of_mem _ mem, rest'⟩

theorem findConst_sound {d : Decls} {m : ModPath} {name : Name} {c : ConstDecl}
    (h : findConst d.consts m name = some c) : ConstNamed d m name c :=
  findConst_sound' d.consts m name c h

theorem findConst_none : ∀ (consts : List ConstDecl) (m : ModPath) (name : Name),
    findConst consts m name = none → ∀ c ∈ consts, ¬(c.home = m ∧ c.name = name)
  | [], _, _, _ => by simp
  | x :: rest, m, name, h => by
    rw [findConst] at h
    by_cases e : (sameText x.name name && sameSpellings x.home m) = true
    · rw [if_pos e] at h; cases h
    · rw [if_neg e] at h
      simp only [Bool.and_eq_true, sameText_iff, sameSpellings_iff] at e
      intro u mem
      rcases List.mem_cons.1 mem with rfl | mem
      · exact fun ⟨a, b⟩ => e ⟨b, a⟩
      · exact findConst_none rest m name h u mem

theorem findAlias_sound' : ∀ (aliases : List AliasDecl) (m : ModPath) (name : Name) (a : AliasDecl),
    findAlias aliases m name = some a → a ∈ aliases ∧ a.home = m ∧ a.name = name
  | [], _, _, _, h => by simp [findAlias] at h
  | x :: rest, m, name, a, h => by
    rw [findAlias] at h
    by_cases e : (sameText x.name name && sameSpellings x.home m) = true
    · rw [if_pos e] at h
      cases h
      simp only [Bool.and_eq_true, sameText_iff, sameSpellings_iff] at e
      exact ⟨by simp, e.2, e.1⟩
    · rw [if_neg e] at h
      obtain ⟨mem, rest'⟩ := findAlias_sound' rest m name a h
      exact ⟨List.mem_cons_of_mem _ mem, rest'⟩

theorem findAlias_sound {d : Decls} {m : ModPath} {name : Name} {a : AliasDecl}
    (h : findAlias d.aliases m name = some a) : AliasNamed d m name a :=
  findAlias_sound' d.aliases m name a h

theorem findAlias_none : ∀ (aliases : List AliasDecl) (m : ModPath) (name : Name),
    findAlias aliases m name = none → ∀ a ∈ aliases, ¬(a.home = m ∧ a.name = name)
  | [], _, _, _ => by simp
  | x :: rest, m, name, h => by
    rw [findAlias] at h
    by_cases e : (sameText x.name name && sameSpellings x.home m) = true
    · rw [if_pos e] at h; cases h
    · rw [if_neg e] at h
      simp only [Bool.and_eq_true, sameText_iff, sameSpellings_iff] at e
      intro u mem
      rcases List.mem_cons.1 mem with rfl | mem
      · exact fun ⟨a, b⟩ => e ⟨b, a⟩
      · exact findAlias_none rest m name h u mem

/-- Every variant `variantsNamed` lists is a variant of module `m`'s enums
spelled `name` (types counted from `k`). -/
theorem variantsNamed_sound' : ∀ (types : List TypeDecl) (m : ModPath) (name : Name) (k : Nat),
    ∀ v ∈ variantsNamed types m name k, k ≤ v.owner ∧
      ∃ t, types[v.owner - k]? = some t ∧ t.isEnum = true ∧ t.home = m ∧ t.variants[v.index]? = some name
  | [], _, _, _, _, h => by simp [variantsNamed] at h
  | t :: rest, m, name, k, v, h => by
    rw [variantsNamed] at h
    have tail : v ∈ variantsNamed rest m name (k + 1) → k ≤ v.owner ∧
        ∃ t', (t :: rest)[v.owner - k]? = some t' ∧ t'.isEnum = true ∧ t'.home = m ∧
          t'.variants[v.index]? = some name := by
      intro mem
      obtain ⟨le, t', got, more⟩ := variantsNamed_sound' rest m name (k + 1) v mem
      refine ⟨by omega, t', ?_, more⟩
      rw [show v.owner - k = (v.owner - (k + 1)) + 1 by omega]
      simpa using got
    by_cases e : (t.isEnum && sameSpellings t.home m) = true
    · rw [if_pos e] at h
      simp only [Bool.and_eq_true, sameSpellings_iff] at e
      cases hp : position t.variants name 0 with
      | none => rw [hp] at h; exact tail h
      | some j =>
        rw [hp] at h
        rcases List.mem_cons.1 h with rfl | h
        · obtain ⟨-, got⟩ := position_sound _ _ _ _ hp
          exact ⟨Nat.le_refl _, t, by simp, e.1, e.2, by simpa using got⟩
        · exact tail h
    · rw [if_neg e] at h
      exact tail h

theorem variantsNamed_sound {d : Decls} {m : ModPath} {name : Name} {v : VariantAt}
    (h : v ∈ variantsNamed d.types m name 0) : VariantNamed d m name v := by
  unfold VariantNamed
  simpa using (variantsNamed_sound' d.types m name 0 v h).2

/-- A variant `importedVariants` lists belongs to a module that `m` imports. -/
theorem importedVariants_sound {d : Decls} {m : ModPath} {name : Name} {v : VariantAt} :
    ∀ (imports : List ImportDecl), v ∈ importedVariants d.types imports m name →
      ∃ i ∈ imports, i.home = m ∧ VariantNamed d i.target name v
  | [], h => by simp [importedVariants] at h
  | i :: rest, h => by
    rw [importedVariants] at h
    by_cases e : sameSpellings i.home m = true
    · rw [if_pos e] at h
      rcases List.mem_append.1 h with h | h
      · exact ⟨i, by simp, (sameSpellings_iff _ _).1 e, variantsNamed_sound h⟩
      · obtain ⟨j, mem, rest'⟩ := importedVariants_sound rest h
        exact ⟨j, List.mem_cons_of_mem _ mem, rest'⟩
    · rw [if_neg e] at h
      obtain ⟨j, mem, rest'⟩ := importedVariants_sound rest h
      exact ⟨j, List.mem_cons_of_mem _ mem, rest'⟩

theorem onlyVariant_sound : ∀ {vs : List VariantAt} {v : VariantAt}, onlyVariant vs = some v → vs = [v]
  | [], _, h => by simp [onlyVariant] at h
  | [w], _, h => by simp [onlyVariant] at h; rw [h]
  | _ :: _ :: _, _, h => by simp [onlyVariant] at h

/-- A bare variant name is the one variant with that spelling among the
current module's enums, or, when they have none, the one among the imported
modules' enums. -/
inductive BareVariant (d : Decls) (m : ModPath) (name : Name) : VariantAt → Prop
  | here {v} : variantsNamed d.types m name 0 = [v] → BareVariant d m name v
  | imported {v} : variantsNamed d.types m name 0 = [] → importedVariants d.types d.imports m name = [v] →
      BareVariant d m name v

theorem bareVariant_sound {env : FrontEnv} {name : Name} {v : VariantAt}
    (h : bareVariant env name = some v) : BareVariant env.decls env.home name v := by
  unfold bareVariant at h
  cases hv : variantsNamed env.decls.types env.home name 0 with
  | nil => rw [hv] at h; exact .imported hv (onlyVariant_sound h)
  | cons w rest => rw [hv] at h; exact .here (hv.trans (onlyVariant_sound h))

end Lanius.Mini.Reading
