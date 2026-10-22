import Lanius.Mini.SliceLayout

/-!
# Nested word structs: the leaves of a layout

The front pass accepts a struct slice element, or an enum payload, whose
fields are native words or declared structs of such fields, nested
(`wordWidths`). Both sides lay such a value out by its leaves, the word
fields reached by flattening the nested structs in order: Core's leaf `i`
is `8 * i` bytes below the value's word 0 (a nested struct's fields are
below its own word 0, which is below the outer value's), and the mini
code's leaf `i` is slot `i` (a nested struct takes `sizes` slots, one a
leaf).

`Leaves ds fs ls` says flattening fields `fs` gives the word fields `ls`;
`Flat ds fs vs ls xs` pairs values `vs` of `fs` with values `xs` of the
leaves. This file proves Core's layout facts by leaves (words, offsets,
reads, writes as a `WriteChain`) and the mini representation by leaves.
-/

namespace Lanius.Mini

open Lanius.Core (Value)

/-- Flattening fields `fs` (declared structs nested) gives word fields `ls`. -/
inductive Leaves (ds : SrcDecls) : List SrcType → List SrcType → Prop where
  | nil : Leaves ds [] []
  | word {f : SrcType} {w : MemWidth} {fs ls : List SrcType} :
      wordWidth f = some w → Leaves ds fs ls → Leaves ds (f :: fs) (f :: ls)
  | nest {sid : Nat} {gs ms fs ls : List SrcType} :
      structFields ds.structs sid = some gs → Leaves ds gs ms → ms ≠ [] → Leaves ds fs ls →
      Leaves ds (.struct sid gs :: fs) (ms ++ ls)

/-- Values `vs` of fields `fs`, and the values `xs` of their leaves `ls`. -/
inductive Flat (ds : SrcDecls) : List SrcType → List Value → List SrcType → List Value → Prop where
  | nil : Flat ds [] [] [] []
  | word {f : SrcType} {w : MemWidth} {fs ls : List SrcType} {v : Value} {vs xs : List Value} :
      wordWidth f = some w → Flat ds fs vs ls xs → Flat ds (f :: fs) (v :: vs) (f :: ls) (v :: xs)
  | nest {sid : Nat} {gs ms fs ls : List SrcType} {us ys vs xs : List Value} :
      structFields ds.structs sid = some gs → Flat ds gs us ms ys → ms ≠ [] → Flat ds fs vs ls xs →
      Flat ds (.struct sid gs :: fs) (.structure sid us :: vs) (ms ++ ls) (ys ++ xs)

/-! ## Leaves and widths -/

theorem leafWidths_append : ∀ {m ls : List SrcType} {a b : List MemWidth},
    leafWidths m = some a → leafWidths ls = some b → leafWidths (m ++ ls) = some (a ++ b)
  | [], ls, a, b, ha, hb => by
    simp only [leafWidths, Option.some.injEq] at ha
    subst ha
    simpa using hb
  | f :: m, ls, a, b, ha, hb => by
    simp only [leafWidths, consWidth] at ha
    split at ha
    · simp at ha
    rename_i w hw
    split at ha
    · simp at ha
    rename_i rs hrs
    simp only [Option.some.injEq] at ha
    subst ha
    simp [leafWidths, consWidth, hw, leafWidths_append hrs hb]

theorem Leaves.cons_of {ds : SrcDecls} {f : SrcType} {m fs ls : List SrcType}
    (head : Leaves ds [f] m) (rest : Leaves ds fs ls) : Leaves ds (f :: fs) (m ++ ls) := by
  cases head with
  | word hw tail =>
    cases tail
    exact .word hw rest
  | nest decl inner ne tail =>
    cases tail
    simpa using Leaves.nest decl inner ne rest

theorem appendWidths_some {a b : Option (List MemWidth)} {ws : List MemWidth} (h : appendWidths a b = some ws) :
    ∃ x y, a = some x ∧ b = some y ∧ ws = x ++ y := by
  simp only [appendWidths] at h
  split at h
  · simp at h
  rename_i x
  split at h
  · simp at h
  rename_i y
  simp only [Option.some.injEq] at h
  exact ⟨x, y, rfl, rfl, h.symm⟩

theorem oneWidth_leaves {ds : SrcDecls} {f : SrcType} {ws : List MemWidth} (h : oneWidth (wordWidth f) = some ws) :
    ∃ m, Leaves ds [f] m ∧ leafWidths m = some ws := by
  simp only [oneWidth] at h
  split at h
  · simp at h
  rename_i w hw
  simp only [Option.some.injEq] at h
  subst h
  exact ⟨[f], .word hw .nil, by simp [leafWidths, consWidth, hw]⟩

theorem leafWidths_length : ∀ {ls : List SrcType} {ws : List MemWidth}, leafWidths ls = some ws →
    ws.length = ls.length
  | _, _, h => (leafWidths_get h).1

mutual
/-- What the front pass's `wordWidths` checked: the fields flatten to word leaves of these widths. -/
theorem wordWidths_leaves {ds : SrcDecls} : ∀ (fs : List SrcType) {ws : List MemWidth},
    wordWidths ds fs = some ws → ∃ ls, Leaves ds fs ls ∧ leafWidths ls = some ws
  | [], ws, h => by
    simp only [wordWidths, Option.some.injEq] at h
    subst h
    exact ⟨[], .nil, rfl⟩
  | f :: rest, ws, h => by
    simp only [wordWidths] at h
    obtain ⟨x, y, hx, hy, rfl⟩ := appendWidths_some h
    obtain ⟨m, lm, wm⟩ := fieldWidths_leaves f hx
    obtain ⟨ls, lls, wls⟩ := wordWidths_leaves rest hy
    exact ⟨m ++ ls, lm.cons_of lls, leafWidths_append wm wls⟩

theorem fieldWidths_leaves {ds : SrcDecls} : ∀ (f : SrcType) {ws : List MemWidth},
    fieldWidths ds f = some ws → ∃ m, Leaves ds [f] m ∧ leafWidths m = some ws
  | .i32, ws, h => oneWidth_leaves (by simpa [fieldWidths] using h)
  | .bool, ws, h => oneWidth_leaves (by simpa [fieldWidths] using h)
  | .uint _, ws, h => oneWidth_leaves (by simpa [fieldWidths] using h)
  | .ptr, ws, h => oneWidth_leaves (by simpa [fieldWidths] using h)
  | .isize, ws, h => oneWidth_leaves (by simpa [fieldWidths] using h)
  | .enum _ _, ws, h => by simp [fieldWidths] at h
  | .slice _, ws, h => by simp [fieldWidths] at h
  | .unit, ws, h => by simp [fieldWidths] at h
  | .struct sid gs, ws, h => by
    simp only [fieldWidths, nestedWidths] at h
    split at h
    case isFalse => simp at h
    rename_i same
    simp only [nonemptyWidths] at h
    split at h
    · simp at h
    rename_i ws' hws
    split at h
    · simp at h
    rename_i w0 wrest
    simp only [Option.some.injEq] at h
    subst h
    simp only [declaredSame] at same
    split at same
    · simp at same
    rename_i fs0 decl
    have := typesSame_eq fs0 same
    subst this
    obtain ⟨ms, lms, wms⟩ := wordWidths_leaves fs0 hws
    have ne : ms ≠ [] := by
      intro e
      subst e
      simp [leafWidths] at wms
    exact ⟨ms ++ [], .nest decl lms ne .nil, by simpa using wms⟩
end

/-- A leaf takes one slot: fields take as many as they have leaves. -/
theorem Leaves.sizes_eq {ds : SrcDecls} {fs ls : List SrcType} (h : Leaves ds fs ls) : sizes fs = ls.length := by
  induction h with
  | nil => rfl
  | word hw _ ih => simp [Lanius.Mini.sizes, wordWidth_size hw, ih]; omega
  | nest _ _ _ _ ihi ihr => simp [Lanius.Mini.sizes, SrcType.size, ihi, ihr]

theorem Flat.sizes_eq {ds : SrcDecls} {fs ls : List SrcType} {vs xs : List Value} (h : Flat ds fs vs ls xs) :
    sizes fs = ls.length := by
  induction h with
  | nil => rfl
  | word hw _ ih => simp [Lanius.Mini.sizes, wordWidth_size hw, ih]; omega
  | nest _ _ _ _ ihi ihr => simp [Lanius.Mini.sizes, SrcType.size, ihi, ihr]

theorem Flat.lengths {ds : SrcDecls} {fs ls : List SrcType} {vs xs : List Value} (h : Flat ds fs vs ls xs) :
    vs.length = fs.length ∧ xs.length = ls.length := by
  induction h with
  | nil => exact ⟨rfl, rfl⟩
  | word _ _ ih => simp [ih.1, ih.2]
  | nest _ _ _ _ ihi ihr => simp [ihi.2, ihr.1, ihr.2]

theorem Leaves.take {ds : SrcDecls} {fs ls : List SrcType} (h : Leaves ds fs ls) :
    ∀ j, ∃ ls', Leaves ds (fs.take j) ls' := by
  induction h with
  | nil => intro j; exact ⟨[], by simpa using Leaves.nil⟩
  | word hw _ ih =>
    intro j
    cases j with
    | zero => exact ⟨[], .nil⟩
    | succ j =>
      obtain ⟨l, hl⟩ := ih j
      exact ⟨_, .word hw hl⟩
  | nest decl inner ne _ _ ihr =>
    intro j
    cases j with
    | zero => exact ⟨[], .nil⟩
    | succ j =>
      obtain ⟨l, hl⟩ := ihr j
      exact ⟨_, .nest decl inner ne hl⟩

/-! ## Core's words and offsets by leaves -/

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

/-- Core's words for a declared struct, given its fields' words. -/
theorem structure_words {sp : SrcProgram} {sid k n : Nat} {gs ms : List SrcType}
    (decl : structFields sp.decls.structs sid = some gs)
    (ih : ∀ ns, (gs.map SrcType.toCore).mapM (NativeLayout.words? k sp.toCore) = some ns →
      ns.foldl (· + ·) 0 = sizes gs)
    (sz : sizes gs = ms.length) (ne : ms ≠ [])
    (h : NativeLayout.words? (k + 1) sp.toCore (.structure sid) = some n) :
    n = ms.length ∧ ms.length ≤ NativeLayout.maxWords := by
  rw [NativeLayout.words?] at h
  dsimp only at h
  rw [structFields_toCore decl] at h
  simp only [bind, Option.bind] at h
  split at h
  · simp at h
  rename_i ns hns
  dsimp only at h
  rw [ih ns hns, sz] at h
  have pos : 0 < ms.length := List.length_pos_iff.mpr ne
  split at h
  · rename_i le
    simp only [Option.some.injEq] at h
    exact ⟨by omega, le⟩
  · simp at h

/-- Core's words for fields are their leaves. -/
theorem Leaves.words {sp : SrcProgram} {fs ls : List SrcType} (h : Leaves sp.decls fs ls) :
    ∀ {fuel : Nat} {ns : List Nat}, (fs.map SrcType.toCore).mapM (NativeLayout.words? fuel sp.toCore) = some ns →
      ns.foldl (· + ·) 0 = sizes fs := by
  induction h with
  | nil =>
    intro fuel ns e
    simp only [List.map_nil, List.mapM_nil, pure, Option.some.injEq] at e
    subst e
    rfl
  | word hw _ ih =>
    intro fuel ns e
    obtain ⟨b, bs, hb, hbs, rfl⟩ := mapM_option_cons e
    rw [List.foldl_cons, foldl_add, ih hbs, word_words hw hb, sizes, wordWidth_size hw]
  | @nest sid gs ms fs ls decl inner ne _ ihi ihr =>
    intro fuel ns e
    obtain ⟨b, bs, hb, hbs, rfl⟩ := mapM_option_cons e
    rw [List.foldl_cons, foldl_add, ihr hbs, sizes, SrcType.size]
    cases fuel with
    | zero => simp [NativeLayout.words?] at hb
    | succ k =>
      obtain ⟨rfl, -⟩ := structure_words decl (fun ns e => ihi e) inner.sizes_eq ne hb
      rw [inner.sizes_eq]
      omega

theorem Leaves.ne_length {ds : SrcDecls} {fs ls : List SrcType} (h : Leaves ds fs ls) (ne : ls ≠ []) :
    0 < ls.length := List.length_pos_iff.mpr ne

/-- A declared struct of leaves `ls` takes `ls.length` native words. -/
theorem valueWords_leaves {sp : SrcProgram} {sid : Nat} {fields ls : List SrcType}
    (decl : structFields sp.decls.structs sid = some fields) (lv : Leaves sp.decls fields ls) (ne : ls ≠ [])
    {words : Nat} (h : NativeLayout.valueWords? sp.toCore (.structure sid) = some words) :
    words = ls.length ∧ ls.length ≤ NativeLayout.maxWords := by
  rw [NativeLayout.valueWords?, show NativeLayout.maxDepth = 63 + 1 from rfl] at h
  exact structure_words decl (fun ns e => lv.words e) lv.sizes_eq ne h

/-- Field `j` of a declared struct of leaves is `8 * sizes (take j)` bytes below it. -/
theorem fieldOffset_leaves {sp : SrcProgram} {sid : Nat} {fields ls : List SrcType}
    (decl : structFields sp.decls.structs sid = some fields) (lv : Leaves sp.decls fields ls) {j o : Nat}
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
    obtain ⟨ls', lt'⟩ := lv.take j
    rw [← h, lt'.words hns, NativeLayout.wordBytes]
  · simp at h

/-- A payload field's offset: the tag's word, then the earlier fields' leaves. -/
theorem payloadOffset_leaves {sp : SrcProgram} {fs ls : List SrcType} (lv : Leaves sp.decls fs ls) {j : Nat}
    {widths : List Nat}
    (h : ((fs.map SrcType.toCore).take j).mapM
      (fun member => NativeLayout.words? (NativeLayout.maxDepth - 1) sp.toCore member) = some widths) :
    widths.foldl (· + ·) 0 = sizes (fs.take j) := by
  rw [← List.map_take] at h
  obtain ⟨ls', lt'⟩ := lv.take j
  exact lt'.words h

/-! ## Core's reads by leaves -/

/-- Core's read of a declared struct of leaves: field `j` at `8 * sizes (take j)`. -/
theorem readNativeValue_fields {sp : SrcProgram} {heap : Memory.Heap} {sid : Nat} {fields ls : List SrcType}
    (decl : structFields sp.decls.structs sid = some fields) (lv : Leaves sp.decls fields ls)
    {k base : Nat} {v : Value}
    (h : Semantics.readNativeValue (k + 1) sp.toCore heap (.structure sid) base = .ok v) :
    ∃ vals, v = .structure sid vals ∧ vals.length = fields.length ∧
      ∀ (j : Nat) f, fields[j]? = some f → ∃ x, vals[j]? = some x ∧ 8 * sizes (fields.take j) ≤ base ∧
        Semantics.readNativeValue k sp.toCore heap f.toCore (base - 8 * sizes (fields.take j)) = .ok x := by
  simp only [Semantics.readNativeValue, structFields_toCore decl] at h
  obtain ⟨vals, mapped, wrapped⟩ := except_bind_ok h
  simp only [pure, Except.pure, Except.ok.injEq] at wrapped
  subst wrapped
  obtain ⟨len, each⟩ := mapM_except_ok mapped
  simp only [List.length_range, List.length_map] at len
  refine ⟨vals, rfl, len, fun j f hf => ?_⟩
  have lt : j < fields.length := (List.getElem?_eq_some_iff.mp hf).1
  obtain ⟨x, hx, ok⟩ := each j j (by simp [List.length_map, lt])
  refine ⟨x, hx, ?_⟩
  simp only [List.getElem?_map, hf, Option.map_some] at ok
  split at ok
  case h_2 => simp at ok
  rename_i o ho
  rw [fieldOffset_leaves decl lv ho] at ok
  obtain ⟨a, below, ok⟩ := except_bind_ok ok
  obtain ⟨le, rfl⟩ := wordBelow_ok below
  exact ⟨le, ok⟩

theorem readNativeValue_zero {P : Core.Program} {heap : Memory.Heap} {t : Core.Ty} {a : Nat} {x : Value}
    (h : Semantics.readNativeValue 0 P heap t a = .ok x) : False := by
  simp [Semantics.readNativeValue] at h

theorem getElem?_append_cases {α : Type} {l r : List α} {i : Nat} {x : α} (h : (l ++ r)[i]? = some x) :
    (i < l.length ∧ l[i]? = some x) ∨ (l.length ≤ i ∧ r[i - l.length]? = some x) := by
  by_cases lt : i < l.length
  · left
    rw [List.getElem?_append_left lt] at h
    exact ⟨lt, h⟩
  · right
    rw [List.getElem?_append_right (by omega)] at h
    exact ⟨by omega, h⟩

/-- Core's reads of fields, field `j` at `start + 8 * sizes (take j)` bytes
below `a`, are reads of their leaves, leaf `i` at `start + 8 * i`. -/
theorem Leaves.read {sp : SrcProgram} {heap : Memory.Heap} {fs ls : List SrcType} (lv : Leaves sp.decls fs ls) :
    ∀ {vals : List Value} {start a : Nat}, vals.length = fs.length →
      (∀ (j : Nat) f, fs[j]? = some f → ∃ x, vals[j]? = some x ∧ start + 8 * sizes (fs.take j) ≤ a ∧
        ∃ k, Semantics.readNativeValue k sp.toCore heap f.toCore (a - (start + 8 * sizes (fs.take j))) = .ok x) →
      ∃ xs, Flat sp.decls fs vals ls xs ∧ ∀ (i : Nat) l x, ls[i]? = some l → xs[i]? = some x →
        start + 8 * i ≤ a ∧ ∃ k, Semantics.readNativeValue (k + 1) sp.toCore heap l.toCore (a - (start + 8 * i)) = .ok x := by
  induction lv with
  | nil =>
    intro vals start a len _
    cases vals with
    | cons => simp at len
    | nil => exact ⟨[], .nil, fun i l x hl => by simp at hl⟩
  | @word f w fs ls hw _ ih =>
    intro vals start a len each
    cases vals with
    | nil => simp at len
    | cons v vals =>
    obtain ⟨x0, hx0, le0, k0, read0⟩ := each 0 f rfl
    simp only [List.getElem?_cons_zero, Option.some.injEq] at hx0
    subst hx0
    obtain ⟨xs, fl, leaves⟩ := ih (vals := vals) (start := start + 8) (a := a) (by simpa using len)
      (fun j g hg => by
        obtain ⟨x, hx, le, k, rd⟩ := each (j + 1) g (by simpa using hg)
        simp only [List.take_succ_cons, sizes, wordWidth_size hw] at le rd
        refine ⟨x, by simpa using hx, by omega, k, ?_⟩
        rwa [show start + 8 * (1 + sizes (List.take j fs)) = start + 8 + 8 * sizes (List.take j fs) by omega] at rd)
    refine ⟨v :: xs, .word hw fl, fun i l x hl hx => ?_⟩
    cases i with
    | zero =>
      simp only [List.getElem?_cons_zero, Option.some.injEq] at hl hx
      subst hl hx
      cases k0 with
      | zero => exact (readNativeValue_zero read0).elim
      | succ k => exact ⟨by simpa [sizes] using le0, k, by simpa [sizes] using read0⟩
    | succ i =>
      obtain ⟨le, k, rd⟩ := leaves i l x (by simpa using hl) (by simpa using hx)
      refine ⟨by omega, k, ?_⟩
      rwa [show start + 8 * (i + 1) = start + 8 + 8 * i by omega]
  | @nest sid gs ms fs ls decl inner ne _ ihi ihr =>
    intro vals start a len each
    cases vals with
    | nil => simp at len
    | cons v vals =>
    obtain ⟨x0, hx0, le0, k0, read0⟩ := each 0 (.struct sid gs) rfl
    simp only [List.getElem?_cons_zero, Option.some.injEq] at hx0
    subst hx0
    simp only [List.take_zero, sizes, Nat.mul_zero, Nat.add_zero] at le0 read0
    cases k0 with
    | zero => exact (readNativeValue_zero read0).elim
    | succ k =>
    obtain ⟨us, rfl, ulen, ueach⟩ := readNativeValue_fields decl inner (by simpa [SrcType.toCore] using read0)
    obtain ⟨ys, fli, inLeaves⟩ := ihi (vals := us) (start := start) (a := a) ulen (fun j g hg => by
      obtain ⟨x, hx, le, rd⟩ := ueach j g hg
      refine ⟨x, hx, by omega, k, ?_⟩
      rwa [Nat.sub_sub] at rd)
    have msz := inner.sizes_eq
    obtain ⟨xs, flr, outLeaves⟩ := ihr (vals := vals) (start := start + 8 * ms.length) (a := a)
      (by simpa using len)
      (fun j g hg => by
        obtain ⟨x, hx, le, k, rd⟩ := each (j + 1) g (by simpa using hg)
        simp only [List.take_succ_cons, sizes, SrcType.size, msz] at le rd
        refine ⟨x, by simpa using hx, by omega, k, ?_⟩
        rwa [show start + 8 * (ms.length + sizes (List.take j fs)) =
          start + 8 * ms.length + 8 * sizes (List.take j fs) by omega] at rd)
    refine ⟨ys ++ xs, .nest decl fli ne flr, fun i l x hl hx => ?_⟩
    have ylen := fli.lengths.2
    rcases getElem?_append_cases hl with ⟨lt, hl⟩ | ⟨ge, hl⟩
    · rw [List.getElem?_append_left (by omega)] at hx
      exact inLeaves i l x hl hx
    · rw [List.getElem?_append_right (by omega), ylen] at hx
      obtain ⟨le, k, rd⟩ := outLeaves (i - ms.length) l x hl hx
      refine ⟨by omega, k, ?_⟩
      rwa [show start + 8 * ms.length + 8 * (i - ms.length) = start + 8 * i by omega] at rd

/-- Core's read of a declared struct, by its leaves: leaf `i` at `8 * i`. -/
theorem readNativeValue_leaves {sp : SrcProgram} {heap : Memory.Heap} {sid : Nat} {fields ls : List SrcType}
    (decl : structFields sp.decls.structs sid = some fields) (lv : Leaves sp.decls fields ls)
    {k base : Nat} {v : Value}
    (h : Semantics.readNativeValue (k + 1) sp.toCore heap (.structure sid) base = .ok v) :
    ∃ vals xs, v = .structure sid vals ∧ Flat sp.decls fields vals ls xs ∧
      ∀ (i : Nat) l x, ls[i]? = some l → xs[i]? = some x →
        8 * i ≤ base ∧ ∃ k, Semantics.readNativeValue (k + 1) sp.toCore heap l.toCore (base - 8 * i) = .ok x := by
  obtain ⟨vals, rfl, len, each⟩ := readNativeValue_fields decl lv h
  obtain ⟨xs, fl, leaves⟩ := lv.read (heap := heap) (start := 0) (a := base) len (fun j f hf => by
    obtain ⟨x, hx, le, rd⟩ := each j f hf
    exact ⟨x, hx, by omega, k, by simpa using rd⟩)
  exact ⟨vals, xs, rfl, fl, fun i l x hl hx => by simpa using leaves i l x hl hx⟩

/-- Core's read of a declared enum: its tag, then the variant's payload by
leaves, leaf `i` at `8 * (1 + i)`. -/
theorem readNativeValue_enum_leaves {sp : SrcProgram} {heap : Memory.Heap} {eid : Nat}
    {variants : List (List SrcType)} (decl : enumVariants sp.decls.enums eid = some variants)
    {k base : Nat} {v : Value}
    (h : Semantics.readNativeValue (k + 1) sp.toCore heap (.enumeration eid) base = .ok v) :
    ∃ variant fs payload, v = .enumeration eid variant payload ∧ Semantics.loadNatLE heap base 4 = .ok variant ∧
      variants[variant]? = some fs ∧ payload.length = fs.length ∧
      ∀ ls, Leaves sp.decls fs ls → ∃ xs, Flat sp.decls fs payload ls xs ∧ ∀ (i : Nat) l x, ls[i]? = some l →
        xs[i]? = some x → 8 * (1 + i) ≤ base ∧
          ∃ k, Semantics.readNativeValue (k + 1) sp.toCore heap l.toCore (base - 8 * (1 + i)) = .ok x := by
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
  refine ⟨variant, fs, payload, rfl, loaded, hv, len, fun ls lv => ?_⟩
  obtain ⟨xs, fl, leaves⟩ := lv.read (heap := heap) (start := 8) (a := base) len (fun j f hf => by
    have lt : j < fs.length := (List.getElem?_eq_some_iff.mp hf).1
    obtain ⟨x, hx, ok⟩ := each j j (by simp [List.length_map, lt])
    refine ⟨x, hx, ?_⟩
    simp only [hf, Option.map_some] at ok
    split at ok
    case h_2 => simp at ok
    rename_i widths hwidths
    rw [payloadOffset_leaves lv hwidths, NativeLayout.wordBytes] at ok
    obtain ⟨a, below, ok⟩ := except_bind_ok ok
    obtain ⟨le, rfl⟩ := wordBelow_ok below
    refine ⟨by omega, k, ?_⟩
    rwa [show 8 * (1 + sizes (List.take j fs)) = 8 + 8 * sizes (List.take j fs) by omega] at ok)
  refine ⟨xs, fl, fun i l x hl hx => ?_⟩
  obtain ⟨le, k, rd⟩ := leaves i l x hl hx
  exact ⟨by omega, k, by rwa [show 8 * (1 + i) = 8 + 8 * i by omega]⟩

/-! ## The mini side by leaves -/

/-- Leaves holding in consecutive slots are the fields holding. -/
theorem Flat.holds {ds : SrcDecls} {fs ls : List SrcType} {vs xs : List Value} (fl : Flat ds fs vs ls xs) :
    ∀ {env : Env} {slot : Nat}, (∀ (i : Nat) l x, ls[i]? = some l → xs[i]? = some x → l.Holds x (env (slot + i))) →
      FieldsHold fs vs env slot := by
  induction fl with
  | nil => intro env slot _; exact .nil
  | word hw _ ih =>
    intro env slot each
    refine .cons ((SrcType.holdsAt_scalar (wordWidth_scalar hw)).mpr (by simpa using each 0 _ _ rfl rfl)) ?_
    rw [wordWidth_size hw]
    refine ih fun i l x hl hx => ?_
    have := each (i + 1) l x (by simpa using hl) (by simpa using hx)
    rwa [show slot + (i + 1) = slot + 1 + i by omega] at this
  | @nest sid gs ms fs ls us ys vs xs decl inner ne _ ihi ihr =>
    intro env slot each
    have ylen := inner.lengths.2
    refine .cons (.struct (ihi fun i l x hl hx => ?_)) ?_
    · have lt : i < ms.length := (List.getElem?_eq_some_iff.mp hl).1
      exact each i l x (by rw [List.getElem?_append_left lt]; exact hl)
        (by rw [List.getElem?_append_left (by omega)]; exact hx)
    · rw [SrcType.size, inner.sizes_eq]
      refine ihr fun i l x hl hx => ?_
      have := each (ms.length + i) l x (by rw [List.getElem?_append_right (by omega)]; simpa using hl)
        (by rw [List.getElem?_append_right (by omega)]; simpa [ylen] using hx)
      rwa [show slot + (ms.length + i) = slot + ms.length + i by omega] at this

/-- The converse of `Flat.holds`: fields holding are their leaves holding. -/
theorem Leaves.holds {ds : SrcDecls} {fs ls : List SrcType} (lv : Leaves ds fs ls) :
    ∀ {vs : List Value} {env : Env} {slot : Nat}, FieldsHold fs vs env slot →
      ∃ xs, Flat ds fs vs ls xs ∧ ∀ (i : Nat) l, ls[i]? = some l → ∃ x, xs[i]? = some x ∧ l.Holds x (env (slot + i)) := by
  induction lv with
  | nil =>
    intro vs env slot h
    cases h
    exact ⟨[], .nil, fun i l hl => by simp at hl⟩
  | word hw _ ih =>
    intro vs env slot h
    cases h with
    | @cons _ _ x vs _ _ head tail =>
    rw [wordWidth_size hw] at tail
    obtain ⟨xs, fl, each⟩ := ih tail
    refine ⟨x :: xs, .word hw fl, fun i l hl => ?_⟩
    cases i with
    | zero =>
      simp only [List.getElem?_cons_zero, Option.some.injEq] at hl
      subst hl
      exact ⟨x, rfl, by simpa using (SrcType.holdsAt_scalar (wordWidth_scalar hw)).mp head⟩
    | succ i =>
      obtain ⟨y, hy, hold⟩ := each i l (by simpa using hl)
      exact ⟨y, by simpa using hy, by rwa [show slot + (i + 1) = slot + 1 + i by omega]⟩
  | @nest sid gs ms fs ls decl inner ne _ ihi ihr =>
    intro vs env slot h
    cases h with
    | @cons _ _ v vs _ _ head tail =>
    cases head with
    | @struct _ _ us _ _ fh =>
    rw [SrcType.size, inner.sizes_eq] at tail
    obtain ⟨ys, fli, inEach⟩ := ihi fh
    obtain ⟨xs, flr, outEach⟩ := ihr tail
    have ylen := fli.lengths.2
    refine ⟨ys ++ xs, .nest decl fli ne flr, fun i l hl => ?_⟩
    rcases getElem?_append_cases hl with ⟨lt, hl⟩ | ⟨ge, hl⟩
    · obtain ⟨y, hy, hold⟩ := inEach i l hl
      exact ⟨y, by rw [List.getElem?_append_left (by omega)]; exact hy, hold⟩
    · obtain ⟨y, hy, hold⟩ := outEach (i - ms.length) l hl
      refine ⟨y, by rw [List.getElem?_append_right (by omega), ylen]; exact hy, ?_⟩
      rwa [show slot + ms.length + (i - ms.length) = slot + i by omega] at hold

/-! ## Core's writes by leaves -/

open Lanius.Semantics (State) in
/-- Core's writes of leaves `ls`, values `xs`, one after another from heap
`h` to `h'`: leaf `i` at `start + 8 * i` bytes below `base`. -/
inductive WriteChain (P : Core.Program) (st : State) (base : Nat) :
    List SrcType → List Value → Nat → Memory.Heap → Memory.Heap → Prop where
  | nil {start : Nat} {h : Memory.Heap} : WriteChain P st base [] [] start h h
  | cons {l : SrcType} {ls : List SrcType} {x : Value} {xs : List Value} {start : Nat}
      {h h1 h2 : Memory.Heap} : start ≤ base →
      (∃ k, Semantics.writeNativeValue (k + 1) P st h l.toCore (base - start) x = .ok h1) →
      WriteChain P st base ls xs (start + 8) h1 h2 → WriteChain P st base (l :: ls) (x :: xs) start h h2

open Lanius.Semantics (State)

theorem WriteChain.append {P : Core.Program} {st : State} {base : Nat} {ms ls : List SrcType}
    {ys xs : List Value} {start : Nat} {h h1 h2 : Memory.Heap} (first : WriteChain P st base ms ys start h h1)
    (rest : WriteChain P st base ls xs (start + 8 * ms.length) h1 h2) :
    WriteChain P st base (ms ++ ls) (ys ++ xs) start h h2 := by
  induction first with
  | nil => simpa using rest
  | @cons l ls' x xs' s0 h0 h1' h2' le wrote _ ih =>
    refine .cons le wrote (ih ?_)
    simp only [List.length_cons] at rest
    rwa [show s0 + 8 + 8 * ls'.length = s0 + 8 * (ls'.length + 1) by omega]

theorem WriteChain.rebase {P : Core.Program} {st : State} {b : Nat} {ls : List SrcType} {xs : List Value}
    {s : Nat} {h h' : Memory.Heap} (chain : WriteChain P st b ls xs s h h') :
    ∀ {base start : Nat}, b = base - start → start ≤ base → WriteChain P st base ls xs (start + s) h h' := by
  induction chain with
  | nil => intro base start _ _; exact .nil
  | @cons l ls' x xs' s0 h0 h1' h2' le wrote _ ih =>
    intro base start hb sb
    subst hb
    have wrote' : ∃ k, Semantics.writeNativeValue (k + 1) P st h0 l.toCore (base - (start + s0)) x = .ok h1' := by
      rwa [Nat.sub_sub] at wrote
    have rest : WriteChain P st base ls' xs' (start + s0 + 8) h1' h2' := by
      rw [Nat.add_assoc]
      exact ih rfl sb
    exact .cons (by omega) wrote' rest

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

theorem writeNativeValue_zero {P : Core.Program} {st : State} {h h' : Memory.Heap} {t : Core.Ty} {a : Nat}
    {x : Value} (w : Semantics.writeNativeValue 0 P st h t a x = .ok h') : False := by
  simp [Semantics.writeNativeValue] at w

/-- Core's field-by-field writes, field `i` at `s + 8 * sizes (take i)`
bytes below `b`, from field `j` on: the leaves' writes, as a chain. -/
def FlatWrites (sp : SrcProgram) (st : State) (fs : List SrcType) (vs : List Value) (ls : List SrcType)
    (xs : List Value) : Prop :=
  ∀ {FS : List SrcType} {VS : List Value} {g : Memory.Heap → Nat → Except Trap Memory.Heap} {b s j : Nat}
    {h h' : Memory.Heap},
    (∀ (i : Nat) f x h0 h1, FS[i]? = some f → VS[i]? = some x → g h0 i = .ok h1 →
      s + 8 * sizes (FS.take i) ≤ b ∧
        ∃ k, Semantics.writeNativeValue k sp.toCore st h0 f.toCore (b - (s + 8 * sizes (FS.take i))) x = .ok h1) →
    FS.drop j = fs → VS.drop j = vs → (List.range' j fs.length).foldlM g h = .ok h' →
    WriteChain sp.toCore st b ls xs (s + 8 * sizes (FS.take j)) h h'

theorem Flat.leaves {ds : SrcDecls} {fs ls : List SrcType} {vs xs : List Value} (fl : Flat ds fs vs ls xs) :
    Leaves ds fs ls := by
  induction fl with
  | nil => exact .nil
  | word hw _ ih => exact .word hw ih
  | nest decl _ ne _ ihi ihr => exact .nest decl ihi ne ihr

/-- Core's write of a declared struct, given its fields' `FlatWrites`. -/
theorem structure_write_of {sp : SrcProgram} {st : State} {sid : Nat} {gs ms : List SrcType}
    {us ys : List Value} (decl : structFields sp.decls.structs sid = some gs) (fl : Flat sp.decls gs us ms ys)
    (ih : FlatWrites sp st gs us ms ys) {k b : Nat} {h h' : Memory.Heap}
    (w : Semantics.writeNativeValue (k + 1) sp.toCore st h (.structure sid) b (.structure sid us) = .ok h') :
    WriteChain sp.toCore st b ms ys 0 h h' := by
  have ulen := fl.lengths.1
  rw [Semantics.writeNativeValue] at w
  simp only [bne_self_eq_false, Bool.false_eq_true, if_false, structFields_toCore decl, List.length_map, ulen] at w
  rw [List.range_eq_range'] at w
  have := ih (FS := gs) (VS := us) (b := b) (s := 0) (j := 0) (fun i f x h0 h1 hf hx step => by
      simp only [List.getElem?_map, hf, hx, Option.map_some] at step
      split at step
      case h_2 => simp at step
      rename_i o ho
      rw [fieldOffset_leaves decl fl.leaves ho] at step
      obtain ⟨a, below, step⟩ := except_bind_ok step
      obtain ⟨le, rfl⟩ := wordBelow_ok below
      exact ⟨by omega, k, by simpa using step⟩)
    rfl rfl w
  simpa [sizes] using this

theorem Flat.writes {sp : SrcProgram} {st : State} {fs ls : List SrcType} {vs xs : List Value}
    (fl : Flat sp.decls fs vs ls xs) : FlatWrites sp st fs vs ls xs := by
  induction fl with
  | nil =>
    intro FS VS g b s j h h' _ _ _ run
    simp only [List.length_nil, List.range'_zero, List.foldlM_nil, pure, Except.pure, Except.ok.injEq] at run
    subst run
    exact .nil
  | @word f w fs ls v vs xs hw _ ih =>
    intro FS VS g b s j h h' step dfs dvs run
    obtain ⟨hf, dfs'⟩ := drop_cons_get dfs
    obtain ⟨hv, dvs'⟩ := drop_cons_get dvs
    simp only [List.length_cons, List.range'_succ, List.foldlM_cons] at run
    obtain ⟨h1, first, run⟩ := except_bind_ok run
    obtain ⟨le, k, wrote⟩ := step j f v h h1 hf hv first
    cases k with
    | zero => exact (writeNativeValue_zero wrote).elim
    | succ k =>
    refine .cons le ⟨k, wrote⟩ ?_
    have := ih step dfs' dvs' run
    rwa [sizes_take_succ hf, wordWidth_size hw, Nat.mul_add, Nat.mul_one, ← Nat.add_assoc] at this
  | @nest sid gs ms fs ls us ys vs xs decl inner ne _ ihi ihr =>
    intro FS VS g b s j h h' step dfs dvs run
    obtain ⟨hf, dfs'⟩ := drop_cons_get dfs
    obtain ⟨hv, dvs'⟩ := drop_cons_get dvs
    simp only [List.length_cons, List.range'_succ, List.foldlM_cons] at run
    obtain ⟨h1, first, run⟩ := except_bind_ok run
    obtain ⟨le, k, wrote⟩ := step j _ _ h h1 hf hv first
    cases k with
    | zero => exact (writeNativeValue_zero wrote).elim
    | succ k =>
    have chain := structure_write_of decl inner ihi (by simpa [SrcType.toCore] using wrote)
    have chain := chain.rebase rfl le
    rw [Nat.add_zero] at chain
    refine chain.append ?_
    have := ihr step dfs' dvs' run
    rwa [sizes_take_succ hf, SrcType.size, inner.sizes_eq, Nat.mul_add, ← Nat.add_assoc] at this

/-- Core's write of a declared struct, by its leaves: leaf `i` at `8 * i`. -/
theorem writeNativeValue_leaves {sp : SrcProgram} {st : State} {sid : Nat} {fields ls : List SrcType}
    {vals xs : List Value} (decl : structFields sp.decls.structs sid = some fields)
    (fl : Flat sp.decls fields vals ls xs) {k b : Nat} {h h' : Memory.Heap}
    (w : Semantics.writeNativeValue (k + 1) sp.toCore st h (.structure sid) b (.structure sid vals) = .ok h') :
    WriteChain sp.toCore st b ls xs 0 h h' :=
  structure_write_of decl fl fl.writes w

/-- Core's write of a declared enum: its tag as 4 bytes, then the payload by
leaves, leaf `i` at `8 * (1 + i)`. -/
theorem writeNativeValue_enum_leaves {sp : SrcProgram} {st : State} {eid : Nat}
    {variants : List (List SrcType)} (decl : enumVariants sp.decls.enums eid = some variants) {variant : Nat}
    {fs ls : List SrcType} {payload xs : List Value} (hv : variants[variant]? = some fs)
    (fl : Flat sp.decls fs payload ls xs) {k b : Nat} {h h' : Memory.Heap}
    (w : Semantics.writeNativeValue (k + 1) sp.toCore st h (.enumeration eid) b
      (.enumeration eid variant payload) = .ok h') :
    ∃ tagged, h.storeBytes b (Semantics.encodeNatLE 4 variant) = .ok tagged ∧
      WriteChain sp.toCore st b ls xs 8 tagged h' := by
  have plen := fl.lengths.1
  have lv := fl.leaves
  rw [Semantics.writeNativeValue] at w
  simp only [bne_self_eq_false, Bool.false_eq_true, if_false, enumVariants_toCore decl, List.getElem?_map, hv,
    Option.map_some, List.length_map, plen] at w
  obtain ⟨tagged, tagStored, w⟩ := except_bind_ok w
  refine ⟨tagged, tagStored, ?_⟩
  rw [List.range_eq_range'] at w
  have := fl.writes (FS := fs) (VS := payload) (b := b) (s := 8) (j := 0) (fun i f x h0 h1 hf hx step => by
      simp only [hf, hx, Option.map_some] at step
      split at step
      case h_2 => simp at step
      rename_i widths hwidths
      rw [payloadOffset_leaves lv hwidths, NativeLayout.wordBytes] at step
      obtain ⟨a, below, step⟩ := except_bind_ok step
      obtain ⟨le, rfl⟩ := wordBelow_ok below
      refine ⟨by omega, k, ?_⟩
      rwa [show 8 * (1 + sizes (List.take i fs)) = 8 + 8 * sizes (List.take i fs) by omega] at step)
    rfl rfl w
  simpa [sizes] using this

/-! ## What the front pass checked about slice elements -/

/-- What the front pass checked about a struct slice element: its declared
fields flatten to word leaves, at least one. -/
theorem elementWidths_leaves {ds : SrcDecls} {element : SrcType} {ws : List MemWidth}
    (h : elementWidths ds element = some ws) :
    ∃ sid fields ls, element = .struct sid fields ∧ structFields ds.structs sid = some fields ∧
      Leaves ds fields ls ∧ leafWidths ls = some ws ∧ ws ≠ [] := by
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
    obtain ⟨ls, lv, wls⟩ := wordWidths_leaves fs hws
    exact ⟨sid, fs, ls, rfl, found, lv, wls, List.cons_ne_nil _ _⟩
  | i32 | bool | uint | enum | ptr | slice | unit | isize => simp [elementWidths] at h

theorem variantWidths_leaves {ds : SrcDecls} : ∀ {variants : List (List SrcType)} {wss : List (List MemWidth)},
    variantWidths ds variants = some wss →
    wss.length = variants.length ∧ ∀ (m : Nat) fs, variants[m]? = some fs →
      ∃ ws ls, wss[m]? = some ws ∧ Leaves ds fs ls ∧ leafWidths ls = some ws
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
    obtain ⟨len, each⟩ := variantWidths_leaves hrest
    refine ⟨by simp [len], fun m gs hg => ?_⟩
    cases m with
    | zero =>
      simp only [List.getElem?_cons_zero, Option.some.injEq] at hg
      subst hg
      obtain ⟨ls, lv, wls⟩ := wordWidths_leaves _ hws
      exact ⟨ws, ls, rfl, lv, wls⟩
    | succ m =>
      obtain ⟨w, ls, hw, lv, wls⟩ := each m gs (by simpa using hg)
      exact ⟨w, ls, by simpa using hw, lv, wls⟩

theorem maxLength_leaves {ds : SrcDecls} : ∀ {variants : List (List SrcType)} {wss : List (List MemWidth)},
    variantWidths ds variants = some wss → maxLength wss = maxSize variants
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
    obtain ⟨ls, lv, wls⟩ := wordWidths_leaves _ hws
    simp only [maxLength, maxSize, maxLength_leaves hrest, lv.sizes_eq, leafWidths_length wls]

theorem enumWidths_leaves {ds : SrcDecls} {element : SrcType} {wss : List (List MemWidth)}
    (h : enumWidths ds element = some wss) :
    ∃ eid variants, element = .enum eid variants ∧ enumVariants ds.enums eid = some variants ∧
      variantWidths ds variants = some wss ∧ 0 < variants.length ∧ variants.length < 2 ^ 32 := by
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

theorem maxSize_sizes : ∀ (variants : List (List SrcType)), (variants.map sizes).foldr max 0 = maxSize variants
  | [] => rfl
  | fs :: rest => by simp only [List.map_cons, List.foldr_cons, maxSize, maxSize_sizes rest]

/-- A declared enum whose payloads flatten to leaves takes a tag word and its
longest payload's leaves. -/
theorem valueWords_enum_leaves {sp : SrcProgram} {eid : Nat} {variants : List (List SrcType)}
    (decl : enumVariants sp.decls.enums eid = some variants)
    (lvs : ∀ fs ∈ variants, ∃ ls, Leaves sp.decls fs ls) {words : Nat}
    (h : NativeLayout.valueWords? sp.toCore (.enumeration eid) = some words) :
    words = 1 + maxSize variants ∧ maxSize variants < NativeLayout.maxWords := by
  rw [NativeLayout.valueWords?, show NativeLayout.maxDepth = 63 + 1 from rfl, NativeLayout.words?] at h
  dsimp only at h
  rw [enumVariants_toCore decl] at h
  simp only [bind, Option.bind] at h
  split at h
  · simp at h
  rename_i ls hls
  simp only [Option.some.injEq] at h
  obtain ⟨len, each⟩ := mapM_option_ok hls
  have per : ∀ (i : Nat) fs, variants[i]? = some fs → ls[i]? = some (sizes fs) ∧ sizes fs < NativeLayout.maxWords := by
    intro i fs hf
    obtain ⟨y, hy, ok⟩ := each i (fs.map SrcType.toCore) (by simp [List.getElem?_map, hf])
    obtain ⟨leaves, lv⟩ := lvs fs (List.mem_of_getElem? hf)
    split at ok
    · simp at ok
    rename_i ns hns
    dsimp only at ok
    rw [lv.words hns] at ok
    split at ok
    · rename_i lt
      simp only [Option.some.injEq] at ok
      subst ok
      exact ⟨hy, lt⟩
    · simp at ok
  have hls' : ls = variants.map sizes := by
    apply List.ext_getElem?
    intro i
    cases hv : variants[i]? with
    | none =>
      have : variants.length ≤ i := List.getElem?_eq_none_iff.mp hv
      simp only [List.getElem?_map, hv, Option.map_none]
      exact List.getElem?_eq_none_iff.mpr (by simp at len; omega)
    | some fs => simp [List.getElem?_map, hv, (per i fs hv).1]
  subst hls'
  rw [foldl_max, maxSize_sizes] at h
  refine ⟨by omega, ?_⟩
  have bound : ∀ (vs : List (List SrcType)), (∀ fs ∈ vs, sizes fs < NativeLayout.maxWords) →
      maxSize vs < NativeLayout.maxWords := by
    intro vs
    induction vs with
    | nil => intro _; simp [maxSize, NativeLayout.maxWords]
    | cons fs rest ih =>
      intro lt
      simp only [maxSize]
      have := ih (fun g m => lt g (by simp [m]))
      have := lt fs (by simp)
      omega
  exact bound variants (fun fs mem => by
    obtain ⟨i, hi⟩ := List.getElem?_of_mem mem
    exact (per i fs hi).2)

#print axioms elementWidths_leaves
#print axioms valueWords_enum_leaves

#print axioms writeNativeValue_leaves
#print axioms writeNativeValue_enum_leaves

#print axioms valueWords_leaves
#print axioms readNativeValue_leaves
#print axioms readNativeValue_enum_leaves
#print axioms Flat.holds
#print axioms Leaves.holds

#print axioms wordWidths_leaves
#print axioms Leaves.take

end Lanius.Mini
