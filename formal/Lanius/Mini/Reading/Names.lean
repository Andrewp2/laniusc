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

/-- The primitive types' spellings: `i32`, `bool`, `u8`, `u16`, `u32`, `u64`,
`usize`, `ptr`, `isize`, `i8`, `i16` and `i64`. -/
def primNames : List (Name × SrcType) :=
  [([105, 51, 50], .i32), ([98, 111, 111, 108], .bool), ([117, 56], .uint .uint8), ([117, 49, 54], .uint .uint16), ([117, 51, 50], .uint .uint32),
   ([117, 54, 52], .uint .uint64), ([117, 115, 105, 122, 101], .uint .usize), ([112, 116, 114], .ptr),
   ([105, 115, 105, 122, 101], .isize), ([105, 56], .sint .uint8), ([105, 49, 54], .sint .uint16),
   ([105, 54, 52], .sint .uint64), ([99, 104, 97, 114], .char), ([102, 51, 50], .float .f32),
   ([102, 54, 52], .float .f64)]

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
  by_cases h3' : n = [117, 49, 54]
  · subst h3'; rfl
  rw [if_neg (by rw [spelled_iff3]; exact h3')]
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
  by_cases h9 : n = [105, 56]
  · subst h9; rfl
  rw [if_neg (by rw [spelled_iff2]; exact h9)]
  by_cases h10 : n = [105, 49, 54]
  · subst h10; rfl
  rw [if_neg (by rw [spelled_iff3]; exact h10)]
  by_cases h11 : n = [105, 54, 52]
  · subst h11; rfl
  rw [if_neg (by rw [spelled_iff3]; exact h11)]
  by_cases h12 : n = [99, 104, 97, 114]
  · subst h12; rfl
  rw [if_neg (by rw [spelled_iff4]; exact h12)]
  by_cases h13 : n = [102, 51, 50]
  · subst h13; rfl
  rw [if_neg (by rw [spelled_iff3]; exact h13)]
  by_cases h14 : n = [102, 54, 52]
  · subst h14; rfl
  rw [if_neg (by rw [spelled_iff3]; exact h14)]
  simp [primName, primNames, List.lookup, beq_false_of_ne h1, beq_false_of_ne h2, beq_false_of_ne h3, beq_false_of_ne h3',
    beq_false_of_ne h4, beq_false_of_ne h5, beq_false_of_ne h6, beq_false_of_ne h7, beq_false_of_ne h8,
    beq_false_of_ne h9, beq_false_of_ne h10, beq_false_of_ne h11, beq_false_of_ne h12, beq_false_of_ne h13,
    beq_false_of_ne h14]

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

A lookup finds the first declaration of the module with the spelling, or
reports that there is none. Under `WellNamed` the first is the only one. -/

/-- `x`, at position `i`, is the first element of `xs` that satisfies `p`. -/
def FirstWith {α : Type} (xs : List α) (p : α → Prop) (i : Nat) (x : α) : Prop :=
  xs[i]? = some x ∧ p x ∧ ∀ j < i, ∀ y, xs[j]? = some y → ¬p y

theorem firstWith_zero {α : Type} {y x : α} {xs : List α} {p : α → Prop} (e : x = y) (h : p y) :
    FirstWith (y :: xs) p 0 x :=
  ⟨by simp [e], e ▸ h, fun _ lt => absurd lt (Nat.not_lt_zero _)⟩

theorem firstWith_succ {α : Type} {y x : α} {xs : List α} {p : α → Prop} {i : Nat} (n : ¬p y)
    (h : FirstWith xs p i x) : FirstWith (y :: xs) p (i + 1) x := by
  obtain ⟨at', px, before⟩ := h
  refine ⟨by simpa using at', px, fun j lt z hz => ?_⟩
  cases j with
  | zero => simp at hz; exact hz ▸ n
  | succ j => exact before j (by omega) z (by simpa using hz)

/-- An index-returning search: the position (counted from `k`) of the first
element that passes the test. -/
theorem find_sound {α : Type} (p : α → Bool) (q : α → Prop) (hpq : ∀ x, p x = true ↔ q x)
    (f : List α → Nat → Option Nat) (nil : ∀ k, f [] k = none)
    (cons : ∀ y xs k, f (y :: xs) k = if p y = true then some k else f xs (k + 1)) :
    ∀ (xs : List α) (k i : Nat), f xs k = some i → k ≤ i ∧ ∃ x, FirstWith xs q (i - k) x
  | [], k, i, h => by rw [nil] at h; cases h
  | y :: xs, k, i, h => by
    rw [cons] at h
    by_cases e : p y = true
    · rw [if_pos e] at h
      cases h
      exact ⟨Nat.le_refl _, y, by simpa using firstWith_zero rfl ((hpq y).1 e)⟩
    · rw [if_neg e] at h
      obtain ⟨le, x, fx⟩ := find_sound p q hpq f nil cons xs (k + 1) i h
      refine ⟨by omega, x, ?_⟩
      rw [show i - k = (i - (k + 1)) + 1 by omega]
      exact firstWith_succ (fun hq => e ((hpq y).2 hq)) fx

theorem find_none {α : Type} (p : α → Bool) (q : α → Prop) (hpq : ∀ x, p x = true ↔ q x)
    (f : List α → Nat → Option Nat)
    (cons : ∀ y xs k, f (y :: xs) k = if p y = true then some k else f xs (k + 1)) :
    ∀ (xs : List α) (k : Nat), f xs k = none → ∀ x ∈ xs, ¬q x
  | [], _, _ => by simp
  | y :: xs, k, h => by
    rw [cons] at h
    by_cases e : p y = true
    · rw [if_pos e] at h; cases h
    · rw [if_neg e] at h
      intro x mem
      rcases List.mem_cons.1 mem with rfl | mem
      · exact fun hq => e ((hpq x).2 hq)
      · exact find_none p q hpq f cons xs (k + 1) h x mem

/-- A value-returning search: the first element that passes the test. -/
theorem pick_sound {α : Type} (p : α → Bool) (q : α → Prop) (hpq : ∀ x, p x = true ↔ q x)
    (f : List α → Option α) (nil : f [] = none) (cons : ∀ y xs, f (y :: xs) = if p y = true then some y else f xs) :
    ∀ (xs : List α) (x : α), f xs = some x → ∃ i, FirstWith xs q i x
  | [], _, h => by rw [nil] at h; cases h
  | y :: xs, x, h => by
    rw [cons] at h
    by_cases e : p y = true
    · rw [if_pos e] at h
      cases h
      exact ⟨0, firstWith_zero rfl ((hpq _).1 e)⟩
    · rw [if_neg e] at h
      obtain ⟨i, fx⟩ := pick_sound p q hpq f nil cons xs x h
      exact ⟨i + 1, firstWith_succ (fun hq => e ((hpq y).2 hq)) fx⟩

theorem pick_none {α : Type} (p : α → Bool) (q : α → Prop) (hpq : ∀ x, p x = true ↔ q x)
    (f : List α → Option α) (cons : ∀ y xs, f (y :: xs) = if p y = true then some y else f xs) :
    ∀ (xs : List α), f xs = none → ∀ x ∈ xs, ¬q x
  | [], _ => by simp
  | y :: xs, h => by
    rw [cons] at h
    by_cases e : p y = true
    · rw [if_pos e] at h; cases h
    · rw [if_neg e] at h
      intro x mem
      rcases List.mem_cons.1 mem with rfl | mem
      · exact fun hq => e ((hpq x).2 hq)
      · exact pick_none p q hpq f cons xs h x mem

/-- Type `i` is the first of module `m`'s structs and enums spelled `name`. -/
def TypeNamed (d : Decls) (m : ModPath) (name : Name) (i : Nat) : Prop :=
  ∃ t, FirstWith d.types (fun t => t.home = m ∧ t.name = name) i t

/-- Function `i` is the first of module `m`'s free functions spelled `name`. -/
def FnNamed (d : Decls) (m : ModPath) (name : Name) (i : Nat) : Prop :=
  ∃ f, FirstWith d.fns (fun f => f.inImpl = false ∧ f.home = m ∧ f.name = name) i f

def ConstNamed (d : Decls) (m : ModPath) (name : Name) (c : ConstDecl) : Prop :=
  ∃ i, FirstWith d.consts (fun c => c.home = m ∧ c.name = name) i c

def AliasNamed (d : Decls) (m : ModPath) (name : Name) (a : AliasDecl) : Prop :=
  ∃ i, FirstWith d.aliases (fun a => a.home = m ∧ a.name = name) i a

/-- Variant `v.index` of type `v.owner`, an enum of module `m`, is its
first variant spelled `name`. -/
def VariantNamed (d : Decls) (m : ModPath) (name : Name) (v : VariantAt) : Prop :=
  ∃ t, d.types[v.owner]? = some t ∧ t.isEnum = true ∧ t.home = m ∧ FirstWith t.variants (· = name) v.index name

theorem typeTest (m : ModPath) (name : Name) (t : TypeDecl) :
    (sameText t.name name && sameSpellings t.home m) = true ↔ (t.home = m ∧ t.name = name) := by
  rw [Bool.and_eq_true, sameText_iff, sameSpellings_iff, and_comm]

theorem findType_sound {d : Decls} {m : ModPath} {name : Name} {i : Nat}
    (h : findType d.types m name 0 = some i) : TypeNamed d m name i := by
  unfold TypeNamed
  simpa using (find_sound _ _ (typeTest m name) (fun xs k => findType xs m name k) (fun _ => rfl)
    (fun _ _ _ => rfl) d.types 0 i h).2

theorem findType_none {d : Decls} {m : ModPath} {name : Name} (h : findType d.types m name 0 = none) :
    ∀ t ∈ d.types, ¬(t.home = m ∧ t.name = name) :=
  find_none _ _ (typeTest m name) (fun xs k => findType xs m name k) (fun _ _ _ => rfl) d.types 0 h

theorem fnTest (m : ModPath) (name : Name) (f : FnDecl) :
    (!f.inImpl && sameText f.name name && sameSpellings f.home m) = true ↔
      (f.inImpl = false ∧ f.home = m ∧ f.name = name) := by
  simp only [Bool.and_eq_true, Bool.not_eq_true', sameText_iff, sameSpellings_iff]
  exact ⟨fun ⟨⟨a, b⟩, c⟩ => ⟨a, c, b⟩, fun ⟨a, c, b⟩ => ⟨⟨a, b⟩, c⟩⟩

theorem findFn_sound {d : Decls} {m : ModPath} {name : Name} {i : Nat}
    (h : findFn d.fns m name 0 = some i) : FnNamed d m name i := by
  unfold FnNamed
  simpa using (find_sound _ _ (fnTest m name) (fun xs k => findFn xs m name k) (fun _ => rfl)
    (fun _ _ _ => rfl) d.fns 0 i h).2

theorem findFn_none {d : Decls} {m : ModPath} {name : Name} (h : findFn d.fns m name 0 = none) :
    ∀ f ∈ d.fns, ¬(f.inImpl = false ∧ f.home = m ∧ f.name = name) :=
  find_none _ _ (fnTest m name) (fun xs k => findFn xs m name k) (fun _ _ _ => rfl) d.fns 0 h

theorem findConst_sound {d : Decls} {m : ModPath} {name : Name} {c : ConstDecl}
    (h : findConst d.consts m name = some c) : ConstNamed d m name c :=
  pick_sound (fun c => sameText c.name name && sameSpellings c.home m) _
    (fun c => by rw [Bool.and_eq_true, sameText_iff, sameSpellings_iff, and_comm])
    (fun xs => findConst xs m name) rfl (fun _ _ => rfl) d.consts c h

theorem findConst_none {d : Decls} {m : ModPath} {name : Name} (h : findConst d.consts m name = none) :
    ∀ c ∈ d.consts, ¬(c.home = m ∧ c.name = name) :=
  pick_none (fun c => sameText c.name name && sameSpellings c.home m) _
    (fun c => by rw [Bool.and_eq_true, sameText_iff, sameSpellings_iff, and_comm])
    (fun xs => findConst xs m name) (fun _ _ => rfl) d.consts h

theorem findAlias_sound {d : Decls} {m : ModPath} {name : Name} {a : AliasDecl}
    (h : findAlias d.aliases m name = some a) : AliasNamed d m name a :=
  pick_sound (fun a => sameText a.name name && sameSpellings a.home m) _
    (fun a => by rw [Bool.and_eq_true, sameText_iff, sameSpellings_iff, and_comm])
    (fun xs => findAlias xs m name) rfl (fun _ _ => rfl) d.aliases a h

theorem findAlias_none {d : Decls} {m : ModPath} {name : Name} (h : findAlias d.aliases m name = none) :
    ∀ a ∈ d.aliases, ¬(a.home = m ∧ a.name = name) :=
  pick_none (fun a => sameText a.name name && sameSpellings a.home m) _
    (fun a => by rw [Bool.and_eq_true, sameText_iff, sameSpellings_iff, and_comm])
    (fun xs => findAlias xs m name) (fun _ _ => rfl) d.aliases h

theorem position_sound {names : List Name} {name : Name} {j : Nat}
    (h : position names name 0 = some j) : FirstWith names (· = name) j name := by
  obtain ⟨-, x, fx⟩ := find_sound (fun n => sameText n name) (· = name) (fun n => sameText_iff n name)
    (fun xs k => position xs name k) (fun _ => rfl) (fun _ _ _ => rfl) names 0 j h
  simp only [Nat.sub_zero] at fx
  exact fx.2.1 ▸ fx

theorem position_none {names : List Name} {name : Name} (h : position names name 0 = none) : name ∉ names :=
  fun mem => find_none (fun n => sameText n name) (· = name) (fun n => sameText_iff n name)
    (fun xs k => position xs name k) (fun _ _ _ => rfl) names 0 h name mem rfl

/-- Every variant `variantsNamed` lists is a variant of module `m`'s enums
spelled `name` (types counted from `k`). -/
theorem variantsNamed_sound' : ∀ (types : List TypeDecl) (m : ModPath) (name : Name) (k : Nat),
    ∀ v ∈ variantsNamed types m name k, k ≤ v.owner ∧
      ∃ t, types[v.owner - k]? = some t ∧ t.isEnum = true ∧ t.home = m ∧ FirstWith t.variants (· = name) v.index name
  | [], _, _, _, _, h => by simp [variantsNamed] at h
  | t :: rest, m, name, k, v, h => by
    rw [variantsNamed] at h
    have tail : v ∈ variantsNamed rest m name (k + 1) → k ≤ v.owner ∧
        ∃ t', (t :: rest)[v.owner - k]? = some t' ∧ t'.isEnum = true ∧ t'.home = m ∧
          FirstWith t'.variants (· = name) v.index name := by
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
        · exact ⟨Nat.le_refl _, t, by simp, e.1, e.2, position_sound hp⟩
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
enums of the module it is imported from by name (`import p::name;`, see
`itemImport`); else among the current module's enums, or, when they have
none, among the imported modules' enums. -/
inductive BareVariant (d : Decls) (m : ModPath) (name : Name) : VariantAt → Prop
  | item {p v} : itemImport d d.imports m name = some p → variantsNamed d.types p name 0 = [v] →
      BareVariant d m name v
  | here {v} : itemImport d d.imports m name = none → variantsNamed d.types m name 0 = [v] → BareVariant d m name v
  | imported {v} : itemImport d d.imports m name = none → variantsNamed d.types m name 0 = [] →
      importedVariants d.types d.imports m name = [v] → BareVariant d m name v

theorem bareVariant_sound {env : FrontEnv} {name : Name} {v : VariantAt}
    (h : bareVariant env name = some v) : BareVariant env.decls env.home name v := by
  unfold bareVariant at h
  cases hi : itemImport env.decls env.decls.imports env.home name with
  | some p => rw [hi] at h; exact .item hi (onlyVariant_sound h)
  | none =>
    rw [hi] at h
    cases hv : variantsNamed env.decls.types env.home name 0 with
    | nil => rw [hv] at h; exact .imported hi hv (onlyVariant_sound h)
    | cons w rest => rw [hv] at h; exact .here hi (hv.trans (onlyVariant_sound h))

end Lanius.Mini.Reading
