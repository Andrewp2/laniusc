module

public import Lanius.Mini.LowerExpr
public import Lanius.Mini.HeapCorr
public import Lanius.Mini.Views
import all Lanius.Mini.Compiler.P.SrcType_size
import all Lanius.Mini.Compiler.P.UintTy_half

@[expose] public section
/-! # Borrowed slices

A slice of a caller's array (`SrcType.HoldsAt.borrowed`): Core reads and
writes the array in its cell, and the mini code the packed `i32` or `u8`
elements of the place's block in frame memory, which `FrameCorr` keeps equal
to the cell. This file has the facts the reads and writes of such a slice
use: an element's slots, where its bytes lie, and the correspondence after a
store into one element.
-/

namespace Lanius.Mini

open Lanius.Core (Value)
open Lanius.Semantics (State)

variable {bud : Budget} {places : List Addressed}

/-! ## Arrays as fields -/

theorem fieldsHold_replicate_get {e : SrcType} : ∀ {n : Nat} {vs : List Value} {env : Env} {slot pos : Nat}
    {v : Value}, FieldsHold places (List.replicate n e) vs env slot → vs[pos]? = some v →
      e.HoldsAt places v env (slot + pos * e.size)
  | 0, _, _, _, _, _, h, found => by
    cases h
    simp at found
  | n + 1, _, _, slot, pos, _, h, found => by
    rw [List.replicate_succ] at h
    cases h with
    | cons head rest =>
      cases pos with
      | zero =>
        simp only [List.getElem?_cons_zero, Option.some.injEq] at found
        subst found
        simpa using head
      | succ pos =>
        simp only [List.getElem?_cons_succ] at found
        have := fieldsHold_replicate_get rest found
        rw [show slot + (pos + 1) * e.size = slot + e.size + pos * e.size by rw [Nat.succ_mul]; omega]
        exact this

theorem fieldsHold_replicate_set {e : SrcType} {v : Value} {env env' : Env} :
    ∀ {n : Nat} {vs : List Value} {slot pos : Nat}, FieldsHold places (List.replicate n e) vs env slot → pos < n →
      e.HoldsAt places v env' (slot + pos * e.size) →
      (∀ j, j < slot + pos * e.size ∨ slot + pos * e.size + e.size ≤ j → env' j = env j) →
      FieldsHold places (List.replicate n e) (Semantics.setValue vs pos v) env' slot
  | 0, _, _, _, _, lt, _, _ => by omega
  | n + 1, _, slot, pos, h, lt, held, away => by
    rw [List.replicate_succ] at h ⊢
    cases h with
    | cons head rest =>
      cases pos with
      | zero =>
        simp only [Semantics.setValue]
        refine .cons (by simpa using held) (rest.congr fun i _ => ?_)
        exact away _ (.inr (by simp only [Nat.zero_mul]; omega))
      | succ pos =>
        simp only [Semantics.setValue]
        refine .cons (head.congr fun i below => away _ (.inl ?_)) ?_
        · rw [Nat.succ_mul]; omega
        · refine fieldsHold_replicate_set rest (by omega) ?_ ?_
          · rw [show slot + e.size + pos * e.size = slot + (pos + 1) * e.size by rw [Nat.succ_mul]; omega]
            exact held
          · intro j hj
            exact away j (by rw [Nat.succ_mul]; omega)

/-! ## More places -/

mutual
/-- A representation over some places holds over more: only a borrowed
slice names a place, and it still names it. -/
theorem SrcType.HoldsAt.mono {places places' : List Addressed} (sub : ∀ x ∈ places, x ∈ places') :
    ∀ {ty : SrcType} {v : Value} {env : Env} {slot : Nat},
      ty.HoldsAt places v env slot → ty.HoldsAt places' v env slot
  | _, _, _, _, .i32 h => .i32 h
  | _, _, _, _, .bool h => .bool h
  | _, _, _, _, .uint h => .uint h
  | _, _, _, _, .struct h => .struct (FieldsHold.mono sub h)
  | _, _, _, _, .enum found tag payload => .enum found tag (FieldsHold.mono sub payload)
  | _, _, _, _, .ptr h => .ptr h
  | _, _, _, _, .slice len small => .slice len small
  | _, _, _, _, .borrowed mem sliced root ty packed pointer len small =>
    .borrowed (sub _ mem) sliced root ty packed pointer len small
  | _, _, _, _, .array h => .array (FieldsHold.mono sub h)
  | _, _, _, _, .unit => .unit
  | _, _, _, _, .isize h => .isize h
  | _, _, _, _, .char h => .char h
  | _, _, _, _, .float h => .float h
  | _, _, _, _, .sint h => .sint h
  | _, _, _, _, .view len h => .view len h

theorem FieldsHold.mono {places places' : List Addressed} (sub : ∀ x ∈ places, x ∈ places') :
    ∀ {fs : List SrcType} {vs : List Value} {env : Env} {slot : Nat},
      FieldsHold places fs vs env slot → FieldsHold places' fs vs env slot
  | _, _, _, _, .nil => .nil
  | _, _, _, _, .cons head rest => .cons (SrcType.HoldsAt.mono sub head) (FieldsHold.mono sub rest)
end

/-- Scalars, one after another, do not depend on the places. -/
theorem fieldsHold_replicate_scalar {e : SrcType} (scalar : e.isScalar = true) {places' : List Addressed} :
    ∀ {n : Nat} {vs : List Value} {env : Env} {slot : Nat},
      FieldsHold places (List.replicate n e) vs env slot → FieldsHold places' (List.replicate n e) vs env slot
  | 0, _, _, _, h => by
    cases h
    exact .nil
  | n + 1, _, _, _, h => by
    cases h with
    | cons head rest =>
      exact .cons ((SrcType.holdsAt_scalar scalar).mpr ((SrcType.holdsAt_scalar scalar).mp head))
        (fieldsHold_replicate_scalar scalar rest)

/-- A packed place's value is represented over any places. -/
theorem Addressed.Packed.holdsAt {x : Addressed} (packed : x.Packed) {places' : List Addressed} {v : Value}
    {env : Env} {slot : Nat} (h : x.ty.HoldsAt places v env slot) : x.ty.HoldsAt places' v env slot := by
  obtain ⟨-, -, element, n, ty, el⟩ := packed
  rw [ty] at h ⊢
  have scalar : element.isScalar = true := by
    rcases el with rfl | rfl <;> simp [SrcType.isScalar]
  cases h with
  | array h => exact .array (fieldsHold_replicate_scalar scalar h)

/-- The correspondence for more places holds for fewer: a caller's places
after its callee, which borrowed more, returns. -/
theorem FrameCorr.restrict {places' : List Addressed} {st : State} {hp : Heap} (fc : FrameCorr bud places' st hp)
    (sub : ∀ x ∈ places, x ∈ places') : FrameCorr bud places st hp := by
  refine ⟨fun x mem => ?_, fun x mem => fc.inside x (sub x mem), fun x mem => fc.small x (sub x mem),
    fun x mem y ymem ne => fc.apart x (sub x mem) y (sub y ymem) ne, fun x mem => fc.packed x (sub x mem),
    fun v vmem x mem => fc.unviewed v vmem x (sub x mem), fc.room, fc.ceiling, fc.bounded⟩
  obtain ⟨v, read, h⟩ := fc.holds x (sub x mem)
  exact ⟨v, read, (fc.packed x (sub x mem)).holdsAt h⟩

/-! ## A sliced place's array -/

/-- A sliced array place: Core's array in its cell, as long as its type
says, and its elements in the place's slots. -/
theorem FrameCorr.array {st : State} {hp : Heap} (fc : FrameCorr bud places st hp) {x : Addressed} (mem : x ∈ places)
    (root : x.projections = []) {element : SrcType} {n : Nat} (ty : x.ty = .array element n) :
    ∃ vs, Semantics.readCellProjection st x.cell [] = .ok (.array vs) ∧ vs.length = n ∧
      FieldsHold places (List.replicate n element) vs (x.view hp) 0 := by
  obtain ⟨v, read, holds⟩ := fc.holds x mem
  rw [root] at read
  rw [ty] at holds
  cases holds with
  | array elems => exact ⟨_, read, by simpa using elems.length, elems⟩

/-- The elements of the slice of a whole array are the array's. -/
theorem sliceValues_whole {st : State} {cell : Nat} {vs : List Value}
    (read : Semantics.readCellProjection st cell [] = .ok (.array vs)) :
    Semantics.sliceValues st cell [] 0 vs.length = .ok vs := by
  simp [Semantics.sliceValues, read]

/-- Element `pos` of a borrowed slice, as Core reads it, is in the place's
slots of that element. -/
theorem FrameCorr.borrowed_get {st : State} {hp : Heap} (fc : FrameCorr bud places st hp) {x : Addressed}
    (mem : x ∈ places) (root : x.projections = []) {element : SrcType} {n : Nat} (ty : x.ty = .array element n)
    {elems : List Value} (values : Semantics.sliceValues st x.cell [] 0 n = .ok elems) {pos : Nat} {v : Value}
    (found : elems[pos]? = some v) : pos < n ∧ element.HoldsAt places v (x.view hp) (pos * element.size) := by
  obtain ⟨vs, read, len, elemsHold⟩ := fc.array mem root ty
  rw [← len, sliceValues_whole read] at values
  simp only [Except.ok.injEq] at values
  subst values
  refine ⟨?_, by simpa using fieldsHold_replicate_get elemsHold found⟩
  rw [← len]
  exact (List.getElem?_eq_some_iff.mp found).1

/-- A borrowed slice's reads never fail: every index below its length has
an element. -/
theorem FrameCorr.borrowed_values {st : State} {hp : Heap} (fc : FrameCorr bud places st hp) {x : Addressed}
    (mem : x ∈ places) (root : x.projections = []) {element : SrcType} {n : Nat} (ty : x.ty = .array element n) :
    ∃ vs, Semantics.sliceValues st x.cell [] 0 n = .ok vs ∧ vs.length = n := by
  obtain ⟨vs, read, len, -⟩ := fc.array mem root ty
  exact ⟨vs, by rw [← len]; exact sliceValues_whole read, len⟩

/-- The block of a sliced place: from its address, 8 bytes a slot, below
the top and `2 ^ 62`. -/
theorem FrameCorr.block {st : State} {hp : Heap} (fc : FrameCorr bud places st hp) {x : Addressed}
    (mem : x ∈ places) : hp.limit ≤ x.address ∧ x.address + 8 * x.ty.size ≤ hp.top ∧
      x.address + 8 * x.ty.size < 2 ^ 62 :=
  ⟨(fc.inside x mem).2.1, (fc.inside x mem).2.2, fc.small x mem⟩

theorem Addressed.pointer_i32 {x : Addressed} {n : Nat} (ty : x.ty = .array .i32 n) : x.pointer = x.address := by
  simp [Addressed.pointer, ty]

theorem Addressed.pointer_u8 {x : Addressed} {n : Nat} (ty : x.ty = .array (.uint .uint8) n) :
    x.pointer = x.address := by
  simp [Addressed.pointer, ty]

theorem Addressed.size_i32 {x : Addressed} {n : Nat} (ty : x.ty = .array .i32 n) : x.ty.size = n := by
  simp [ty, SrcType.size]

theorem Addressed.size_u8 {x : Addressed} {n : Nat} (ty : x.ty = .array (.uint .uint8) n) : x.ty.size = n := by
  simp [ty, SrcType.size]

/-! ## Stores into a borrowed array -/

/-- The bump heap below the limit is all the correspondence with Core's heap
sees: frame memory may change. -/
theorem HeapCorr.high {h : Memory.Heap} {w : Lanius.World.State} {hp hp' : Heap} (hc : HeapCorr h w hp)
    (within : h.nextAddress ≤ hp.limit) (bytes : ∀ a, a < hp.limit → hp'.bytes a = hp.bytes a)
    (cursor : hp'.cursor = hp.cursor) (limit : hp'.limit = hp.limit) (io : hp'.io = hp.io) : HeapCorr h w hp' := by
  refine ⟨cursor.trans hc.cursor, hc.pos, hc.unbounded, limit ▸ hc.small, hc.sized, hc.below, hc.apart, hc.unique,
    fun b mem live i lt => ?_, fun a lo hi => ?_, io ▸ hc.out, io ▸ hc.err, hc.closed, io ▸ hc.input, io ▸ hc.streams⟩
  · have below := hc.below b mem
    have sized := hc.sized b mem
    have := Nat.le_max_left b.size 1
    rw [bytes _ (by addr_omega)]
    exact hc.bytes b mem live i lt
  · rw [bytes _ (limit ▸ hi)]
    exact hc.zero a lo (limit ▸ hi)

/-- A store into element `pos` of a sliced array place: Core's cell holds the
array with that element replaced, and the mini heap changed only in the
place's block, the element's slots holding the new value and the others
unchanged. The correspondence still holds. -/
theorem FrameCorr.borrowed_set {st st' : State} {hp hp' : Heap} (fc : FrameCorr bud places st hp) {x : Addressed}
    (mem : x ∈ places) (root : x.projections = []) {element : SrcType} {n : Nat} (ty : x.ty = .array element n)
    {vs : List Value} (read : Semantics.readCellProjection st x.cell [] = .ok (.array vs)) {pos : Nat} (lt : pos < n)
    {v : Value} (readNew : Semantics.readCellProjection st' x.cell [] = .ok (.array (Semantics.setValue vs pos v)))
    (others : ∀ y ∈ places, y.cell ≠ x.cell → st'.cellEntry? y.cell = st.cellEntry? y.cell)
    (held : element.HoldsAt places v (x.view hp') (pos * element.size))
    (away : ∀ s, s < pos * element.size ∨ pos * element.size + element.size ≤ s → x.view hp' s = x.view hp s)
    (bytes : ∀ a, ¬ x.Covers a → hp'.bytes a = hp.bytes a)
    (fsp : hp'.fsp = hp.fsp) (limit : hp'.limit = hp.limit) (top : hp'.top = hp.top)
    (views : st'.i32ArrayViews = st.i32ArrayViews := by rfl) :
    FrameCorr bud places st' hp' := by
  refine ⟨fun y ymem => ?_, fun y ymem => ?_, fc.small, fc.apart, fc.packed, by rw [views]; exact fc.unviewed,
    by rw [fsp, limit]; exact fc.room,
    by rw [fsp, top]; exact fc.ceiling, by rw [top]; exact fc.bounded⟩
  · by_cases same : y = x
    · subst same
      obtain ⟨vs', read', -, elems⟩ := fc.array mem root ty
      rw [read] at read'
      simp only [Except.ok.injEq, Value.array.injEq] at read'
      subst read'
      refine ⟨_, by rw [root]; exact readNew, ?_⟩
      rw [ty]
      exact .array (fieldsHold_replicate_set elems lt (by simpa using held) (by simpa using away))
    · obtain ⟨cellNe, apart⟩ := fc.apart y ymem x mem same
      obtain ⟨w, readY, holdsY⟩ := fc.holds y ymem
      refine ⟨w, ?_, holdsY.congr (Addressed.view_congr fun a covers => bytes a ?_)⟩
      · simp only [Semantics.readCellProjection, others y ymem cellNe] at readY ⊢
        exact readY
      · intro coversX
        unfold Addressed.Covers at covers coversX
        omega
  · have := fc.inside y ymem
    exact ⟨fsp ▸ this.1, limit ▸ this.2.1, top ▸ this.2.2⟩

/-- A 4-byte store at slot `pos` of a sliced `i32` array: that slot is the
stored value's low 32 bits, the other slots and the bytes outside the block
unchanged. -/
theorem Addressed.view_store_i32 {x : Addressed} (sliced : x.sliced = true) {n : Nat} (ty : x.ty = .array .i32 n)
    (hp : Heap) {pos : Nat} (lt : pos < n) (value : Nat) :
    x.view (hp.writeLE (x.pointer + 4 * pos) value 4) pos = BitVec.ofNat 64 (value % 256 ^ 4) ∧
      (∀ s, s ≠ pos → x.view (hp.writeLE (x.pointer + 4 * pos) value 4) s = x.view hp s) ∧
      ∀ a, ¬ x.Covers a → (hp.writeLE (x.pointer + 4 * pos) value 4).bytes a = hp.bytes a := by
  have size := Addressed.size_i32 ty
  rw [Addressed.pointer_i32 ty]
  refine ⟨?_, fun s ne => ?_, fun a outside => ?_⟩
  · rw [Addressed.view_i32 sliced ty, Addressed.pointer_i32 ty, Heap.readLE_writeLE]
  · rw [Addressed.view_i32 sliced ty, Addressed.view_i32 sliced ty, Addressed.pointer_i32 ty]
    have apart : x.address + 4 * s + 4 ≤ x.address + 4 * pos ∨ x.address + 4 * pos + 4 ≤ x.address + 4 * s := by
      rcases Nat.lt_or_gt_of_ne ne with h | h <;> omega
    rw [Heap.readLE_congr fun a lo hi => Heap.writeLE_bytes_outside _ _ _ _ _ (by omega)]
  · apply Heap.writeLE_bytes_outside
    unfold Addressed.Covers at outside
    omega

/-- A byte store at slot `pos` of a sliced `u8` array: that slot is the byte,
the other slots and the bytes outside the block unchanged. -/
theorem Addressed.view_store_u8 {x : Addressed} (sliced : x.sliced = true) {n : Nat}
    (ty : x.ty = .array (.uint .uint8) n) (hp : Heap) {pos : Nat} (lt : pos < n) (byte : UInt8) :
    x.view (hp.write (x.pointer + pos) byte) pos = BitVec.ofNat 64 byte.toNat ∧
      (∀ s, s ≠ pos → x.view (hp.write (x.pointer + pos) byte) s = x.view hp s) ∧
      ∀ a, ¬ x.Covers a → (hp.write (x.pointer + pos) byte).bytes a = hp.bytes a := by
  have size := Addressed.size_u8 ty
  rw [Addressed.pointer_u8 ty]
  refine ⟨?_, fun s ne => ?_, fun a outside => ?_⟩
  · rw [Addressed.view_u8 sliced ty, Addressed.pointer_u8 ty]
    simp [Heap.readLE, Heap.write_bytes]
  · rw [Addressed.view_u8 sliced ty, Addressed.view_u8 sliced ty, Addressed.pointer_u8 ty]
    have same := Heap.readLE_congr (hp := hp) (hp' := hp.write (x.address + pos) byte) (address := x.address + s)
      (count := 1) fun a lo hi => by rw [Heap.write_bytes, if_neg (by omega)]
    rw [same]
  · rw [Heap.write_bytes, if_neg]
    unfold Addressed.Covers at outside
    omega

/-! ## Core's store into a safe slice -/

/-- Core's `slice[idx] = e` on a safe slice of a whole array: the index and
the value, then the array in the slice's cell with that element replaced. -/
theorem eval_setIndex_safe {P : Core.Program} {k : Nat} {st : State} {slice : Nat} {idx e : Core.Expr}
    {element : Core.Ty} {cell length root : Nat} {u : Value} {st' : State}
    (hold : Views.ViewsHold st) (apart : ∀ v ∈ st.i32ArrayViews, v.root ≠ cell)
    (idxPure : ∀ {f v s}, Semantics.evalExpr f P st idx = .done v s → s = st)
    (ePure : ∀ {f v s}, Semantics.evalExpr f P st e = .done v s → s = st)
    (base : Semantics.evalPlace (k + 1) P st .read (.local slice) =
      .done { root, projections := [], value := some (.slice element cell [] 0 length) } st)
    (run : Semantics.evalExpr (k + 3) P st (.assign .set (.index (.local slice) idx) e) = .done u st') :
    ∃ iv pos elems right entry vs, Semantics.evalExpr (k + 1) P st idx = .done iv st ∧
      Semantics.integerIndex iv = .ok pos ∧ pos < length ∧
      Semantics.sliceValues st cell [] 0 length = .ok elems ∧
      Semantics.evalExpr (k + 2) P st e = .done right st ∧
      st.cellEntry? cell = some entry ∧ entry.value = some (.array vs) ∧ pos < vs.length ∧
      st' = { st with cells := Semantics.replaceCell st.cells cell (.array (Semantics.setValue vs pos right)) } := by
  rw [Semantics.evalExpr] at run
  rw [Semantics.evalPlace] at run
  rw [base] at run
  simp only at run
  split at run
  · rename_i resolved st1 placeRun
    split at placeRun
    · rename_i iv afterIndex indexRun
      have := idxPure indexRun
      subst afterIndex
      split at placeRun
      · simp at placeRun
      rename_i pos posOk
      split at placeRun
      case isFalse => simp at placeRun
      rename_i lt
      split at placeRun
      · simp at placeRun
      rename_i elems values
      split at placeRun
      · simp at placeRun
      rename_i old got
      simp only [Semantics.Outcome.done.injEq] at placeRun
      obtain ⟨rfl, rfl⟩ := placeRun
      split at run
      · rename_i right st2 valueRun
        have := ePure valueRun
        subst st2
        simp only [Semantics.evalAssignValue, Semantics.assignOpBinary?, Semantics.writeResolvedPlaceNative,
          Semantics.writeResolvedPlace, List.nil_append, Nat.zero_add] at run
        cases entry : st.cellEntry? cell with
        | none => simp [entry] at run
        | some en =>
          obtain ⟨id, value⟩ := en
          cases value with
          | none => simp [entry] at run
          | some rootValue =>
            cases rootValue
            all_goals simp only [entry, Semantics.replaceProjectedValue] at run
            all_goals try simp at run
            rename_i vs
            cases got' : vs[pos]? with
            | none => simp [got'] at run
            | some old' =>
            simp only [got', State.assignCell, entry, Option.isSome_some, if_true,
              Semantics.ResolvedPlace.viewFreeRootWrite, List.isEmpty_cons, Bool.false_and, Bool.and_false,
              Bool.false_eq_true, if_false,
              Views.syncTo_ok (hold.replace (value := .array (Semantics.setValue vs pos right)) apart),
              Semantics.Outcome.done.injEq] at run
            obtain ⟨-, rfl⟩ := run
            exact ⟨iv, pos, elems, right, _, vs, indexRun, posOk, lt, values, valueRun, rfl, rfl,
              (List.getElem?_eq_some_iff.mp got').1, rfl⟩
      all_goals simp at run
    all_goals simp at placeRun
  all_goals simp at run

end Lanius.Mini
