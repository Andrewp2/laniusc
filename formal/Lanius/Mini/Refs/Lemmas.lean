module

public import Lanius.Mini.Refs.Model
public import Lanius.Mini.Borrowed
import all Lanius.Mini.Compiler.P.SrcType_same
import all Lanius.Mini.Compiler.P.widthOf
import all Lanius.Mini.Compiler.P.wordWidth
import all Lanius.Mini.Compiler.P.usizeWidth
import all Lanius.Mini.Compiler.P.UintTy_half
import all Lanius.Mini.Compiler.P.Lists_empty
import all Lanius.Mini.Compiler.P.render

@[expose] public section

/-! # References: facts about the memory model (F5)

The native layout of `Mini/Refs/Model.lean`: every slot's bytes lie in its
value's words (`SrcType.slot_fits`), a sub-place's slots are its parent's
slots at the same bytes (`SrcType.sub_holds`), and the run of `loadSlots`.
F5's proofs (`Lanius/Open/F5`) use them.
-/

namespace Lanius.Mini

open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

variable {sx : Statics} {places : List Addressed}

/-! ## Widths -/

theorem MemWidth.bytes_m32 : MemWidth.m32.bytes = 4 := by simp [MemWidth.bytes]

theorem MemWidth.bytes_m64 : MemWidth.m64.bytes = 8 := by simp [MemWidth.bytes]

theorem MemWidth.bytes_le_eight (w : MemWidth) : w.bytes ≤ 8 := by
  cases w <;> simp [MemWidth.bytes]

theorem Access.bytes_le (a : Access) : a.bytes ≤ 8 := by
  cases a with
  | byte => simp [Access.bytes]
  | word w => exact w.bytes_le_eight

theorem Access.bytes_pos (a : Access) : 0 < a.bytes := by
  cases a with
  | byte => simp [Access.bytes]
  | word w => cases w <;> simp [Access.bytes, MemWidth.bytes]

/-- A packed element type is an `i32` or a `u8`. -/
theorem SrcType.narrow_cases {e : SrcType} (h : e.accessKind.narrow = true) : e = .i32 ∨ e = .uint .uint8 := by
  cases e with
  | i32 => exact .inl rfl
  | uint k => cases k <;> simp_all [SrcType.accessKind, Access.narrow]
  | bool => simp [SrcType.accessKind, Access.narrow] at h
  | struct => simp [SrcType.accessKind, Access.narrow] at h
  | enum => simp [SrcType.accessKind, Access.narrow] at h
  | ptr => simp [SrcType.accessKind, Access.narrow] at h
  | slice => simp [SrcType.accessKind, Access.narrow] at h
  | array => simp [SrcType.accessKind, Access.narrow] at h
  | unit => simp [SrcType.accessKind, Access.narrow] at h
  | isize => simp [SrcType.accessKind, Access.narrow] at h
  | char => simp [SrcType.accessKind, Access.narrow] at h
  | float => simp [SrcType.accessKind, Access.narrow] at h
  | sint => simp [SrcType.accessKind, Access.narrow] at h
  | view => simp [SrcType.accessKind, Access.narrow] at h
  | str => simp [SrcType.accessKind, Access.narrow] at h

theorem SrcType.isUint_u8 {ty : SrcType} (h : ty.isUint .uint8 = true) : ty = .uint .uint8 := by
  cases ty with
  | uint k => cases k <;> simp_all [SrcType.isUint, UintTy.code]
  | i32 => simp [SrcType.isUint] at h
  | bool => simp [SrcType.isUint] at h
  | struct => simp [SrcType.isUint] at h
  | enum => simp [SrcType.isUint] at h
  | ptr => simp [SrcType.isUint] at h
  | slice => simp [SrcType.isUint] at h
  | array => simp [SrcType.isUint] at h
  | unit => simp [SrcType.isUint] at h
  | isize => simp [SrcType.isUint] at h
  | char => simp [SrcType.isUint] at h
  | float => simp [SrcType.isUint] at h
  | sint => simp [SrcType.isUint] at h
  | view => simp [SrcType.isUint] at h
  | str => simp [SrcType.isUint] at h

theorem SrcType.refSlotAt_u8 (s : Nat) : (SrcType.uint .uint8).refSlotAt s = (0, .byte) := by
  simp [SrcType.refSlotAt, SrcType.isUint, UintTy.code]

theorem SrcType.refSlotAt_other {ty : SrcType} (h : ty.isUint .uint8 = false) (s : Nat) :
    ty.refSlotAt s = ty.slotAt s := by
  simp [SrcType.refSlotAt, h]

theorem SrcType.slotAt_u8 (s : Nat) : (SrcType.uint .uint8).slotAt s = (0, .word .m32) := by
  simp [SrcType.slotAt, widthOf, wordWidth, usizeWidth]

/-! ## Offsets -/

theorem fieldOffset_add_le : ∀ {fs : List SrcType} {k : Nat} {f : SrcType},
    fs[k]? = some f → fieldOffset fs k + f.size ≤ sizes fs
  | [], _, _, h => by simp at h
  | t :: rest, 0, f, h => by
    simp only [List.getElem?_cons_zero, Option.some.injEq] at h
    subst h
    simp only [fieldOffset_zero, sizes]
    omega
  | t :: rest, k + 1, f, h => by
    simp only [List.getElem?_cons_succ] at h
    have := fieldOffset_add_le h
    rw [fieldOffset_succ]
    simp only [sizes]
    omega

/-- Field `k`'s slot `s` is that field's slot `s`, below the fields before it. -/
theorem fieldsSlotAt_get : ∀ {fs : List SrcType} {k : Nat} {f : SrcType} (total above : Nat) {s : Nat},
    fs[k]? = some f → s < f.size →
    fieldsSlotAt total above fs (fieldOffset fs k + s) =
      (8 * (total - (above + fieldWords (fs.take k)) - f.words) + (f.slotAt s).1, (f.slotAt s).2)
  | [], _, _, _, _, _, h, _ => by simp at h
  | t :: rest, 0, f, total, above, s, h, lt => by
    simp only [List.getElem?_cons_zero, Option.some.injEq] at h
    subst h
    simp [fieldsSlotAt, fieldOffset_zero, lt, fieldWords]
  | t :: rest, k + 1, f, total, above, s, h, lt => by
    simp only [List.getElem?_cons_succ] at h
    rw [fieldOffset_succ, fieldsSlotAt, if_neg (by omega),
      show t.size + fieldOffset rest k + s - t.size = fieldOffset rest k + s by omega,
      fieldsSlotAt_get total (above + t.words) h lt]
    simp [fieldWords, Nat.add_assoc]

/-! ## Every slot lies in its value's words -/

mutual
theorem SrcType.slot_fits : ∀ (ty : SrcType) (s : Nat), s < ty.size →
    (ty.slotAt s).1 + (ty.slotAt s).2.bytes ≤ 8 * ty.words
  | .i32, s, _ => by simp [SrcType.slotAt, SrcType.words, Access.bytes, widthOf, wordWidth, MemWidth.bytes]
  | .bool, s, _ => by simp [SrcType.slotAt, SrcType.words, Access.bytes, widthOf, wordWidth, MemWidth.bytes]
  | .uint kind, s, _ => by
    have := (widthOf (.uint kind)).bytes_le_eight
    simp only [SrcType.slotAt, SrcType.words, Access.bytes]
    omega
  | .struct id fields, s, lt => by
    have := fieldsSlot_fits fields (max 1 (fieldWords fields)) 0 s (by simpa [SrcType.size] using lt)
      (by omega)
    simpa [SrcType.slotAt, SrcType.words] using this
  | .enum id variants, 0, _ => by
    simp only [SrcType.slotAt, SrcType.words, Access.bytes, MemWidth.bytes]
    omega
  | .enum id variants, s + 1, _ => by
    have := ((variantsWidths variants).getD s .m64).bytes_le_eight
    simp only [SrcType.slotAt, SrcType.words, Access.bytes]
    omega
  | .ptr, s, _ => by simp [SrcType.slotAt, SrcType.words, Access.bytes, widthOf, wordWidth, MemWidth.bytes]
  | .slice e, s, lt => by
    simp only [SrcType.size] at lt
    simp only [SrcType.slotAt, SrcType.words, Access.bytes, MemWidth.bytes]
    omega
  | .array e n, s, lt => by
    cases hn : e.accessKind.narrow with
    | true =>
      rcases SrcType.narrow_cases hn with rfl | rfl
      · simp only [SrcType.size, Nat.mul_one] at lt
        simp only [SrcType.slotAt, SrcType.words, SrcType.accessKind, Access.narrow, if_true, Access.bytes,
          MemWidth.bytes]
        omega
      · simp only [SrcType.size, Nat.mul_one] at lt
        simp only [SrcType.slotAt, SrcType.words, SrcType.accessKind, Access.narrow, if_true, Access.bytes]
        omega
    | false =>
      simp only [SrcType.size] at lt
      have pos : 0 < e.size := Nat.pos_of_ne_zero (by rintro h; simp [h] at lt)
      have q : s / e.size < n := (Nat.div_lt_iff_lt_mul pos).2 lt
      have r : s % e.size < e.size := Nat.mod_lt _ pos
      have ih := SrcType.slot_fits e (s % e.size) r
      have room : (s / e.size + 1) * e.words ≤ n * e.words := Nat.mul_le_mul_right _ q
      have one : e.words ≤ (s / e.size + 1) * e.words := Nat.le_mul_of_pos_left _ (Nat.succ_pos _)
      simp only [SrcType.slotAt, SrcType.words, hn, Bool.false_eq_true, if_false]
      omega
  | .unit, s, _ => by simp [SrcType.slotAt, SrcType.words, Access.bytes, widthOf, wordWidth, MemWidth.bytes]
  | .isize, s, _ => by simp [SrcType.slotAt, SrcType.words, Access.bytes, widthOf, wordWidth, MemWidth.bytes]
  | .char, s, _ => by simp [SrcType.slotAt, SrcType.words, Access.bytes, widthOf, wordWidth, MemWidth.bytes]
  | .float ft, s, _ => by
    simp [SrcType.slotAt, SrcType.words, Access.bytes, widthOf, wordWidth, MemWidth.bytes]
  | .sint kind, s, _ => by
    have := (widthOf (.sint kind)).bytes_le_eight
    simp only [SrcType.slotAt, SrcType.words, Access.bytes]
    omega
  | .view n, s, _ => by
    simp [SrcType.slotAt, SrcType.words, Access.bytes, widthOf, wordWidth, MemWidth.bytes]
  | .str, s, lt => by
    simp only [SrcType.size] at lt
    simp only [SrcType.slotAt, SrcType.words, Access.bytes, MemWidth.bytes]
    omega
termination_by structural ty => ty

theorem fieldsSlot_fits : ∀ (fs : List SrcType) (total above s : Nat), s < sizes fs →
    above + fieldWords fs ≤ total →
    (fieldsSlotAt total above fs s).1 + (fieldsSlotAt total above fs s).2.bytes ≤ 8 * total
  | [], _, _, s, lt, _ => by simp [sizes] at lt
  | t :: rest, total, above, s, lt, room => by
    simp only [fieldWords] at room
    simp only [sizes] at lt
    rw [fieldsSlotAt]
    split
    · rename_i h
      have := SrcType.slot_fits t s h
      dsimp only
      omega
    · rename_i h
      exact fieldsSlot_fits rest total (above + t.words) (s - t.size) (by omega) (by omega)
termination_by structural fs => fs
end

/-! ## Sub-places -/

theorem SrcType.sub_cons {ty : SrcType} {p : ValueProjection} {rest : List ValueProjection} {off : Nat}
    {t : SrcType} (h : ty.sub (p :: rest) = some (off, t)) :
    ∃ o child inner, ty.subStep p = some (o, child) ∧ child.sub rest = some (inner, t) ∧ off = o + inner := by
  simp only [SrcType.sub] at h
  split at h
  · cases h
  · rename_i o child hstep
    split at h
    · cases h
    · rename_i inner t' hrest
      simp only [Option.some.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      exact ⟨o, child, inner, hstep, hrest, rfl⟩

theorem SrcType.sub_u8 : ∀ {rest : List ValueProjection} {inner : Nat} {t : SrcType},
    (SrcType.uint .uint8).sub rest = some (inner, t) → inner = 0 ∧ t = .uint .uint8
  | [], inner, t, h => by
    simp only [SrcType.sub, Option.some.injEq, Prod.mk.injEq] at h
    exact ⟨h.1.symm, h.2.symm⟩
  | p :: rest, inner, t, h => by
    obtain ⟨o, child, inner', hstep, -, -⟩ := SrcType.sub_cons h
    simp [SrcType.subStep] at hstep

/-- How a sub-place's slots sit in its parent's: at the same bytes and
width, or, for a `u8` element of a packed array, one byte at the element's
offset. -/
def SlotsIn (ty : SrcType) (j off : Nat) (t : SrcType) : Prop :=
  ∀ s < t.size, ty.slotAt (j + s) = (off + (t.slotAt s).1, (t.slotAt s).2) ∨
    (t = .uint .uint8 ∧ ty.slotAt (j + s) = (off, .byte))

/-- One projection: the child's value is held `j` slots in, inside the
parent's slots, at the child's offset. -/
theorem SrcType.step_holds {ty : SrcType} {p : ValueProjection} {o : Nat} {child : SrcType}
    (h : ty.subStep p = some (o, child)) {root v : Value} {E : Env} {k : Nat} {rest : List ValueProjection}
    (hold : ty.HoldsAt sx places root E k) (hv : Semantics.projectedValue root (p :: rest) = .ok v) :
    ∃ j v', j + child.size ≤ ty.size ∧ child.HoldsAt sx places v' E (k + j) ∧
      Semantics.projectedValue v' rest = .ok v ∧ SlotsIn ty j o child := by
  cases ty with
  | struct id fields =>
    cases p with
    | index _ => simp [SrcType.subStep] at h
    | field f =>
      simp only [SrcType.subStep] at h
      split at h
      · rename_i fty hf
        simp only [Option.some.injEq, Prod.mk.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        cases hold with
        | struct hfields =>
          rename_i vs
          obtain ⟨v', hv', hchild⟩ := hfields.get hf
          simp only [Semantics.projectedValue, hv'] at hv
          refine ⟨fieldOffset fields f, v', ?_, hchild, hv, fun s lt => .inl ?_⟩
          · simpa [SrcType.size] using fieldOffset_add_le hf
          · simp only [SrcType.slotAt]
            rw [fieldsSlotAt_get _ 0 hf lt, Nat.zero_add]
      · cases h
  | array e n =>
    cases p with
    | field _ => simp [SrcType.subStep] at h
    | index i =>
      simp only [SrcType.subStep] at h
      split at h
      · rename_i lt
        cases hold with
        | array hfields =>
          rename_i vs
          have len := hfields.length
          simp only [List.length_replicate] at len
          have hv' : vs[i]? = some (vs[i]'(by omega)) := by
            simp [List.getElem?_eq_getElem (by omega : i < vs.length)]
          have hchild := fieldsHold_replicate_get hfields hv'
          simp only [Semantics.projectedValue, hv'] at hv
          have room : (i + 1) * e.size ≤ n * e.size := Nat.mul_le_mul_right _ lt
          rw [Nat.succ_mul] at room
          cases hn : e.accessKind.narrow with
          | true =>
            simp only [hn, if_true, Option.some.injEq, Prod.mk.injEq] at h
            obtain ⟨rfl, rfl⟩ := h
            refine ⟨i * e.size, _, by simp only [SrcType.size]; omega, hchild, hv, fun s slt => ?_⟩
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
            refine ⟨i * e.size, _, by simp only [SrcType.size]; omega, hchild, hv, fun s slt => .inl ?_⟩
            have pos : 0 < e.size := by omega
            have d : (i * e.size + s) / e.size = i := by
              rw [Nat.mul_comm, Nat.mul_add_div pos, Nat.div_eq_of_lt slt, Nat.add_zero]
            have m : (i * e.size + s) % e.size = s := by
              rw [Nat.mul_comm, Nat.mul_add_mod, Nat.mod_eq_of_lt slt]
            simp only [SrcType.slotAt, hn, Bool.false_eq_true, if_false, d, m]
      · cases h
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
  | str => simp [SrcType.subStep] at h

/-- Down a projection path: the sub-place's value is held `j` slots into
its parent's, and its slots are the parent's (`SlotsIn`). -/
theorem SrcType.sub_holds : ∀ (path : List ValueProjection) {ty t : SrcType} {off : Nat} {root v : Value}
    {E : Env} {k : Nat},
    ty.sub path = some (off, t) → ty.HoldsAt sx places root E k →
    Semantics.projectedValue root path = .ok v →
    ∃ j, j + t.size ≤ ty.size ∧ t.HoldsAt sx places v E (k + j) ∧ SlotsIn ty j off t
  | [], ty, t, off, root, v, E, k, hsub, hold, hv => by
    simp only [SrcType.sub, Option.some.injEq, Prod.mk.injEq] at hsub
    obtain ⟨rfl, rfl⟩ := hsub
    simp only [Semantics.projectedValue, Except.ok.injEq] at hv
    subst hv
    exact ⟨0, by omega, by simpa using hold, fun s _ => .inl (by simp)⟩
  | p :: rest, ty, t, off, root, v, E, k, hsub, hold, hv => by
    obtain ⟨o, child, inner, hstep, hrest, rfl⟩ := SrcType.sub_cons hsub
    obtain ⟨j₁, v', hj₁, hchild, hv', slots₁⟩ := SrcType.step_holds hstep hold hv
    obtain ⟨j₂, hj₂, ht, slots₂⟩ := SrcType.sub_holds rest hrest hchild hv'
    refine ⟨j₁ + j₂, by omega, by simpa [Nat.add_assoc] using ht, fun s lt => ?_⟩
    rw [Nat.add_assoc]
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

/-! ## Bytes -/

theorem Heap.readLE_split (hp : Heap) : ∀ (a m n : Nat),
    hp.readLE a (m + n) = hp.readLE a m + 256 ^ m * hp.readLE (a + m) n
  | a, 0, n => by simp [Heap.readLE]
  | a, m + 1, n => by
    rw [Nat.add_right_comm]
    simp only [Heap.readLE]
    rw [Heap.readLE_split hp (a + 1) m n, Nat.pow_succ, show a + 1 + m = a + (m + 1) by omega]
    simp only [Nat.mul_add, Nat.add_assoc]
    rw [Nat.mul_comm (256 ^ m) 256, Nat.mul_assoc]

/-- A narrow read of a word whose upper bytes are zero reads the word. -/
theorem Heap.readLE_narrow (hp : Heap) {a w m : Nat} (le : w ≤ m) (small : hp.readLE a m < 256 ^ w) :
    hp.readLE a w = hp.readLE a m := by
  have split := hp.readLE_split a w (m - w)
  rw [show w + (m - w) = m by omega] at split
  rcases Nat.eq_zero_or_pos (hp.readLE (a + w) (m - w)) with z | pos
  · rw [z] at split
    omega
  · have := Nat.le_mul_of_pos_right (256 ^ w) pos
    omega

/-! ## Loads -/

theorem addOff_eval {env : Env} {r a off : Nat} (hr : (env r).toNat = a) (lt : a + off < 2 ^ 64) :
    ((addOff r off).eval env).toNat = a + off := by
  simp only [addOff, Expr.eval, Word.apply, BinOp.apply, BitVec.toNat_add, BitVec.toNat_ofNat, hr]
  rw [Nat.mod_eq_of_lt (by omega : off < 2 ^ 64)]
  exact Nat.mod_eq_of_lt lt

theorem Access.load_exec {prog : Program} {depth : Nat} (acc : Access) {target : Nat} {address : Expr}
    {env : Env} {hp : Heap} (inside : (address.eval env).toNat + acc.bytes ≤ hp.top) :
    Exec prog depth env hp (acc.load target address)
      (.normal (env.set target (BitVec.ofNat 64 (hp.readLE (address.eval env).toNat acc.bytes))) hp) := by
  cases acc with
  | byte =>
    have := Exec.loadByte (prog := prog) (depth := depth) (target := target) (address := address)
      (env := env) (heap := hp) (by simp only [Access.bytes] at inside; omega)
    simpa [Access.load, Access.bytes, Heap.readLE] using this
  | word w => exact Exec.loadWord inside

/-- The loads of a reference's read, each slot at `refSlotAt`. -/
theorem SrcType.loadsFrom_exec {prog : Program} {depth : Nat} (ty : SrcType) {r target address : Nat}
    {hp : Heap} : ∀ (count s : Nat) (env : Env), (env r).toNat = address →
      (∀ i, s ≤ i → i < s + count → r ≠ target + i) →
      (∀ i, s ≤ i → i < s + count →
        address + (ty.refSlotAt i).1 + (ty.refSlotAt i).2.bytes ≤ hp.top ∧
          address + (ty.refSlotAt i).1 < 2 ^ 64) →
      ∃ env', Exec prog depth env hp (ty.loadsFrom r target s count) (.normal env' hp) ∧
        (∀ i, s ≤ i → i < s + count → env' (target + i) =
          BitVec.ofNat 64 (hp.readLE (address + (ty.refSlotAt i).1) (ty.refSlotAt i).2.bytes)) ∧
        (∀ q, (∀ i, s ≤ i → i < s + count → q ≠ target + i) → env' q = env q)
  | 0, s, env, _, _, _ => ⟨env, by simpa [SrcType.loadsFrom] using Exec.skip, fun i lo hi => by omega,
      fun _ _ => rfl⟩
  | count + 1, s, env, hr, apart, fits => by
    obtain ⟨top, lt⟩ := fits s (Nat.le_refl _) (by omega)
    have eval := addOff_eval (r := r) (off := (ty.refSlotAt s).1) hr lt
    have first := (ty.refSlotAt s).2.load_exec (prog := prog) (depth := depth) (target := target + s)
      (address := addOff r (ty.refSlotAt s).1) (env := env) (hp := hp) (by rw [eval]; omega)
    rw [eval] at first
    let env1 := env.set (target + s)
      (BitVec.ofNat 64 (hp.readLE (address + (ty.refSlotAt s).1) (ty.refSlotAt s).2.bytes))
    have hr1 : (env1 r).toNat = address := by
      simp only [env1, Env.set, if_neg (apart s (Nat.le_refl _) (by omega))]
      exact hr
    obtain ⟨env', run, loaded, same⟩ := SrcType.loadsFrom_exec ty count (s + 1) env1 hr1
      (fun i lo hi => apart i (by omega) (by omega)) (fun i lo hi => fits i (by omega) (by omega))
    refine ⟨env', .seq first run, fun i lo hi => ?_, fun q away => ?_⟩
    · rcases Nat.lt_or_ge s i with gt | le
      · exact loaded i (by omega) (by omega)
      · have : i = s := by omega
        subst this
        rw [same (target + i) (fun k lo hi => by omega)]
        simp [env1, Env.set]
    · rw [same q (fun k lo hi => away k (by omega) (by omega))]
      simp only [env1, Env.set, if_neg (away s (Nat.le_refl _) (by omega))]

/-! ## Homes -/

theorem readCell_path {st : State} {c : Nat} {root : Value} (h : Semantics.readCellProjection st c [] = .ok root)
    (path : List ValueProjection) :
    Semantics.readCellProjection st c path = Semantics.projectedValue root path := by
  unfold Semantics.readCellProjection at h ⊢
  split at h
  · cases h
  · cases h
  · simp only [Semantics.projectedValue, Except.ok.injEq] at h
    rw [h]

end Lanius.Mini
