import Lanius.Faithful.Pure
import Lanius.Semantics.NativeReadFrame

/-! # Core values and their pure meaning

`VRel P boxes heap t v p`: the Core value `v` of source type `t`, in `heap`,
means the pure value `p`. A scalar means itself, in its type's range; a
struct or an enum means the value with the meanings of its parts; a box (a
struct id that `boxes` gives an element type) means the meaning of the value
Core reads from its storage, where `boxed` wrote it. Core reads only grow
with the heap (`HeapReads`), and its blocks stay (`HeapRanges`), so the
relation does too (`VRel.mono`). -/

namespace Lanius.Faithful

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (HeapReads readNativeValue)

/-- A Core scalar of a source scalar type, in its range. -/
def STy : SrcType → Value → Prop
  | .i32, v => ∃ n, v = .signed .i32 n ∧ -2 ^ 31 ≤ n ∧ n < 2 ^ 31
  | .bool, v => ∃ b, v = .boolean b
  | .uint k, v => ∃ n, v = .unsigned k.toCore n ∧ n < 2 ^ k.width
  | .isize, v => ∃ n, v = .signed .isize n ∧ -2 ^ 63 ≤ n ∧ n < 2 ^ 63
  | .unit, v => v = .unit
  | .struct _ _, _ => False
  | .enum _ _, _ => False
  | .ptr, _ => False
  | .slice _, _ => False
  | .char, _ => False
  | .float _, _ => False
  | .sint _, _ => False

/-- Every range Core's raw views check in `h` still checks in `h'`: blocks
stay live with their bases, sizes and alignments. -/
def HeapRanges (h h' : Memory.Heap) : Prop :=
  ∀ p s a, h.checkRange p s a = .ok () → h'.checkRange p s a = .ok ()

theorem HeapRanges.refl (h : Memory.Heap) : HeapRanges h h := fun _ _ _ ok => ok

theorem HeapRanges.trans {a b c : Memory.Heap} (first : HeapRanges a b) (second : HeapRanges b c) :
    HeapRanges a c := fun _ _ _ ok => second _ _ _ (first _ _ _ ok)

/-- The box struct ids, and the type of the value each box holds. -/
abbrev Boxes := Nat → Option SrcType

mutual
/-- The Core value `v` of type `t` means the pure value `p`. A box's value
is element 0 of the raw view `typed_slice_from_storage` makes of its
`w`-word storage at `a`: its word 0 is the storage's last word. -/
inductive VRel (P : Core.Program) (boxes : Boxes) (heap : Memory.Heap) :
    SrcType → Value → Value → Prop where
  | scalar {t : SrcType} {v : Value} : STy t v → VRel P boxes heap t v v
  | struct {id : Nat} {fs : List SrcType} {vs ps : List Value} :
      boxes id = none → VRels P boxes heap fs vs ps →
      VRel P boxes heap (.struct id fs) (.structure id vs) (.structure id ps)
  | enum {id : Nat} {variants : List (List SrcType)} {k : Nat} {fs : List SrcType} {vs ps : List Value} :
      variants[k]? = some fs → VRels P boxes heap fs vs ps →
      VRel P boxes heap (.enum id variants) (.enumeration id k vs) (.enumeration id k ps)
  | box {id : Nat} {t : SrcType} {a w : Nat} {v p : Value} :
      boxes id = some t → NativeLayout.valueWords? P t.toCore = some w → 0 < w → a + 8 * w ≤ 2 ^ 64 →
      heap.checkRange a (8 * w) 8 = .ok () →
      readNativeValue NativeLayout.maxDepth P heap t.toCore (a + 8 * w - 8) = .ok v →
      VRel P boxes heap t v p → VRel P boxes heap (.struct id [.ptr]) (.structure id [.pointer a]) p

/-- Values of these types, one after another: fields, payloads, arguments. -/
inductive VRels (P : Core.Program) (boxes : Boxes) (heap : Memory.Heap) :
    List SrcType → List Value → List Value → Prop where
  | nil : VRels P boxes heap [] [] []
  | cons {t : SrcType} {ts : List SrcType} {v p : Value} {vs ps : List Value} :
      VRel P boxes heap t v p → VRels P boxes heap ts vs ps → VRels P boxes heap (t :: ts) (v :: vs) (p :: ps)
end

section
variable {P : Core.Program} {boxes : Boxes}

mutual
theorem VRel.mono {h h' : Memory.Heap} (reads : HeapReads h h') (ranges : HeapRanges h h') :
    ∀ {t : SrcType} {v p : Value}, VRel P boxes h t v p → VRel P boxes h' t v p
  | _, _, _, .scalar s => .scalar s
  | _, _, _, .struct n rs => .struct n (VRels.mono reads ranges rs)
  | _, _, _, .enum k rs => .enum k (VRels.mono reads ranges rs)
  | _, _, _, .box b w pos a c r rel =>
    .box b w pos a (ranges _ _ _ c) (reads.nativeValue r) (VRel.mono reads ranges rel)

theorem VRels.mono {h h' : Memory.Heap} (reads : HeapReads h h') (ranges : HeapRanges h h') :
    ∀ {ts : List SrcType} {vs ps : List Value}, VRels P boxes h ts vs ps → VRels P boxes h' ts vs ps
  | _, _, _, .nil => .nil
  | _, _, _, .cons r rs => .cons (VRel.mono reads ranges r) (VRels.mono reads ranges rs)
end

/-- A value that is not a struct or an enum. -/
def Flat : Value → Prop
  | .structure _ _ => False
  | .enumeration _ _ _ => False
  | .unit | .boolean _ | .signed _ _ | .unsigned _ _ | .f32Bits _ | .f64Bits _ | .character _ | .string _
  | .pointer _ | .array _ | .slice _ _ _ _ _ | .rawSlice _ _ _ | .reference _ _ _ => True

/-- A flat Core value means itself, a scalar of its type. -/
theorem VRel.flat {heap : Memory.Heap} {t : SrcType} {v p : Value} (r : VRel P boxes heap t v p)
    (flat : Flat v) : p = v ∧ STy t v := by
  cases r with
  | scalar s => exact ⟨rfl, s⟩
  | struct => exact flat.elim
  | enum => exact flat.elim
  | box => exact flat.elim

theorem VRel.boolean {heap : Memory.Heap} {t : SrcType} {b : Bool} {p : Value}
    (r : VRel P boxes heap t (.boolean b) p) : p = .boolean b :=
  (r.flat trivial).1

theorem STy.flat : ∀ {t : SrcType} {v : Value}, STy t v → Flat v
  | .i32, _, ⟨_, rfl, _⟩ => trivial
  | .bool, _, ⟨_, rfl⟩ => trivial
  | .uint _, _, ⟨_, rfl, _⟩ => trivial
  | .isize, _, ⟨_, rfl, _⟩ => trivial
  | .unit, _, rfl => trivial
  | .struct _ _, _, s => s.elim
  | .enum _ _, _, s => s.elim
  | .ptr, _, s => s.elim
  | .slice _, _, s => s.elim
  | .char, _, s => s.elim
  | .float _, _, s => s.elim
  | .sint _, _, s => s.elim

theorem VRels.length {heap : Memory.Heap} :
    ∀ {ts : List SrcType} {vs ps : List Value}, VRels P boxes heap ts vs ps →
      vs.length = ts.length ∧ ps.length = ts.length
  | _, _, _, .nil => ⟨rfl, rfl⟩
  | _, _, _, .cons _ rs => by simp [rs.length.1, rs.length.2]

theorem VRels.get {heap : Memory.Heap} :
    ∀ {ts : List SrcType} {vs ps : List Value}, VRels P boxes heap ts vs ps → ∀ {i : Nat} {v : Value},
      vs[i]? = some v → ∃ t p, ts[i]? = some t ∧ ps[i]? = some p ∧ VRel P boxes heap t v p
  | _, _, _, .nil, _, _, found => by simp at found
  | _, _, _, .cons r rs, 0, _, found => by
    simp only [List.getElem?_cons_zero, Option.some.injEq] at found
    subst found
    exact ⟨_, _, rfl, rfl, r⟩
  | _, _, _, .cons _ rs, i + 1, _, found => by
    simp only [List.getElem?_cons_succ] at found ⊢
    exact rs.get found

end

/-! ## Types of locals -/

/-- Local types, the newest binding first, as `Env` has the values. -/
abbrev TEnv := List (Nat × SrcType)

def TEnv.get? (tenv : TEnv) (id : Nat) : Option SrcType :=
  (tenv.find? (fun binding => binding.1 == id)).map Prod.snd

def TEnv.bindAll (tenv : TEnv) (bindings : List (Nat × SrcType)) : TEnv :=
  bindings.foldl (fun result binding => binding :: result) tenv

def paramTEnv (params : List SrcParam) : TEnv :=
  TEnv.bindAll [] (params.map fun p => (p.id, p.ty))

theorem TEnv.get?_cons (tenv : TEnv) (k id : Nat) (t : SrcType) :
    TEnv.get? ((k, t) :: tenv) id = if k = id then some t else tenv.get? id := by
  by_cases h : k = id
  · simp [TEnv.get?, List.find?, h]
  · have : (k == id) = false := by simpa using h
    simp [TEnv.get?, List.find?, h, this]

theorem Env.get?_cons' (env : Env) (k id : Nat) (v : Value) :
    Env.get? ((k, v) :: env) id = if k = id then some v else env.get? id := by
  by_cases h : k = id
  · simp [Env.get?, List.find?, h]
  · have : (k == id) = false := by simpa using h
    simp [Env.get?, List.find?, h, this]

end Lanius.Faithful
