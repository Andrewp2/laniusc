module

public import Lanius.Mini.Fails
public import Lanius.Mini.Compiler.P.Code_image
public import Lanius.Mini.Compiler.P.Code_size
public import Lanius.Mini.Compiler.P.Instr_encode
public import Lanius.Mini.Compiler.P.argBase
public import Lanius.Mini.Compiler.P.copyBytes
public import Lanius.Mini.Compiler.P.encodeFrom
public import Lanius.Mini.Compiler.P.encodeOnto
public import Lanius.Mini.Compiler.P.epilogue
public import Lanius.Mini.Compiler.P.frameSize
public import Lanius.Mini.Compiler.P.layout
public import Lanius.Mini.Compiler.P.linkFrom
public import Lanius.Mini.Compiler.P.linkOnto
public import Lanius.Mini.Compiler.P.loadAtBytes
public import Lanius.Mini.Compiler.P.loadWordBytes
public import Lanius.Mini.Compiler.P.prologue
public import Lanius.Mini.Compiler.P.relative
public import Lanius.Mini.Compiler.P.slotRange
public import Lanius.Mini.Compiler.P.stackCheck
public import Lanius.Mini.Compiler.P.storeAtBytes
public import Lanius.Mini.Compiler.P.storeWordBytes
public import Lanius.Mini.Compiler.P.sysBytes
public import Lanius.Mini.Compiler.P.syscallLinuxByte
public import Lanius.Mini.Compiler.P.syscallLinuxHigh
public import Lanius.Mini.Compiler.P.syscallRsiBytes
import all Lanius.Mini.Compiler.P.BinOp_size
import all Lanius.Mini.Compiler.P.Lists_concat
import all Lanius.Mini.Compiler.P.Lists_cons
import all Lanius.Mini.Compiler.P.Lists_empty
import all Lanius.Mini.Compiler.P.Lists_get
import all Lanius.Mini.Compiler.P.Lists_getOr
import all Lanius.Mini.Compiler.P.Lists_length
import all Lanius.Mini.Compiler.P.Lists_single
import all Lanius.Mini.Compiler.P.MemWidth_bytes
import all Lanius.Mini.Compiler.P.MemWidth_prefix
import all Lanius.Mini.Compiler.P.MemWidth_rex
import all Lanius.Mini.Compiler.P.Word_prefix
import all Lanius.Mini.Compiler.P.Code_image
import all Lanius.Mini.Compiler.P.Code_size
import all Lanius.Mini.Compiler.P.Instr_encode
import all Lanius.Mini.Compiler.P.argBase
import all Lanius.Mini.Compiler.P.copyBytes
import all Lanius.Mini.Compiler.P.encodeFrom
import all Lanius.Mini.Compiler.P.encodeOnto
import all Lanius.Mini.Compiler.P.epilogue
import all Lanius.Mini.Compiler.P.frameSize
import all Lanius.Mini.Compiler.P.layout
import all Lanius.Mini.Compiler.P.linkFrom
import all Lanius.Mini.Compiler.P.linkOnto
import all Lanius.Mini.Compiler.P.loadAtBytes
import all Lanius.Mini.Compiler.P.loadWordBytes
import all Lanius.Mini.Compiler.P.prologue
import all Lanius.Mini.Compiler.P.relative
import all Lanius.Mini.Compiler.P.slotRange
import all Lanius.Mini.Compiler.P.stackCheck
import all Lanius.Mini.Compiler.P.storeAtBytes
import all Lanius.Mini.Compiler.P.storeWordBytes
import all Lanius.Mini.Compiler.P.sysBytes
import all Lanius.Mini.Compiler.P.syscallLinuxByte
import all Lanius.Mini.Compiler.P.syscallLinuxHigh
import all Lanius.Mini.Compiler.P.syscallRsiBytes
import all Lanius.Mini.Compiler.Types

@[expose] public section
/-!
# Undefined traps of Core's raw memory

`UndefErr e`: every error `e` can return is an undefined trap. Core's native
loads and stores of typed values fail only with raw memory errors and
`typeMismatch`, so they are `UndefErr`.
-/

namespace Lanius.Mini

variable {sx : Statics}

open Lanius.Semantics (State)

def UndefErr {α : Type} (e : Except Lanius.Trap α) : Prop :=
  ∀ r, e = .error r → undefinedTrap r = true

theorem UndefErr.ok {α : Type} (a : α) : UndefErr (.ok a : Except Lanius.Trap α) := by
  intro r h; cases h

theorem UndefErr.pure {α : Type} (a : α) : UndefErr (Pure.pure a : Except Lanius.Trap α) := by
  intro r h; cases h

theorem UndefErr.error {α : Type} {r : Lanius.Trap} (h : undefinedTrap r = true) :
    UndefErr (.error r : Except Lanius.Trap α) := by
  intro r' e
  cases e
  exact h

theorem UndefErr.bind {α β : Type} {x : Except Lanius.Trap α} {f : α → Except Lanius.Trap β}
    (hx : UndefErr x) (hf : ∀ a, UndefErr (f a)) : UndefErr (x >>= f) := by
  intro r h
  cases hx' : x with
  | error e =>
    rw [hx'] at h
    cases h
    exact hx _ hx'
  | ok a =>
    rw [hx'] at h
    exact hf a r h

theorem UndefErr.mapM {α β : Type} {f : α → Except Lanius.Trap β} :
    ∀ {l : List α}, (∀ a ∈ l, UndefErr (f a)) → UndefErr (l.mapM f)
  | [], _ => by simp only [List.mapM_nil]; exact UndefErr.pure _
  | a :: l, each => by
    rw [List.mapM_cons]
    exact UndefErr.bind (each a List.mem_cons_self) fun b =>
      UndefErr.bind (UndefErr.mapM fun a' mem => each a' (List.mem_cons_of_mem _ mem)) fun bs => UndefErr.pure _

theorem UndefErr.foldlM {α β : Type} {f : β → α → Except Lanius.Trap β} :
    ∀ {l : List α} {init : β}, (∀ b, ∀ a ∈ l, UndefErr (f b a)) → UndefErr (l.foldlM f init)
  | [], _, _ => by simp only [List.foldlM_nil]; exact UndefErr.pure _
  | a :: l, init, each => by
    rw [List.foldlM_cons]
    exact UndefErr.bind (each init a List.mem_cons_self) fun b =>
      UndefErr.foldlM fun b' a' mem => each b' a' (List.mem_cons_of_mem _ mem)

/-! ## Bytes -/

theorem loadByte_undef (h : Memory.Heap) (p o : Nat) : UndefErr (h.loadByte p o) := by
  intro r bad
  simp only [Memory.Heap.loadByte] at bad
  split at bad
  · split at bad
    · simp only [Except.error.injEq] at bad; subst bad; rfl
    · split at bad <;> (simp only [Except.error.injEq] at bad; subst bad; rfl)
    · simp only [Except.error.injEq] at bad; subst bad; rfl
  · split at bad
    · simp only [Except.error.injEq] at bad; subst bad; rfl
    · simp at bad

theorem storeByte_undef (h : Memory.Heap) (p o : Nat) (v : UInt8) : UndefErr (h.storeByte p o v) := by
  intro r bad
  simp only [Memory.Heap.storeByte] at bad
  split at bad
  · split at bad
    · simp only [Except.error.injEq] at bad; subst bad; rfl
    · split at bad <;> (simp only [Except.error.injEq] at bad; subst bad; rfl)
    · simp only [Except.error.injEq] at bad; subst bad; rfl
  · simp at bad

theorem loadBytesFrom_undef (h : Memory.Heap) (p : Nat) :
    ∀ (count offset : Nat), UndefErr (Memory.loadBytesFrom h p offset count)
  | 0, _ => by simp only [Memory.loadBytesFrom]; exact UndefErr.ok _
  | count + 1, offset => by
    intro r bad
    simp only [Memory.loadBytesFrom] at bad
    split at bad
    · rename_i reason e
      cases bad
      exact loadByte_undef h p offset _ e
    · split at bad
      · rename_i reason e
        cases bad
        exact loadBytesFrom_undef h p count (offset + 1) _ e
      · cases bad

theorem loadBytes_undef (h : Memory.Heap) (p n : Nat) : UndefErr (h.loadBytes p n) :=
  loadBytesFrom_undef h p n 0

theorem storeBytesFrom_undef (p : Nat) :
    ∀ (bytes : List UInt8) (h : Memory.Heap) (offset : Nat), UndefErr (Memory.storeBytesFrom h p offset bytes)
  | [], _, _ => by simp only [Memory.storeBytesFrom]; exact UndefErr.ok _
  | byte :: rest, h, offset => by
    intro r bad
    simp only [Memory.storeBytesFrom] at bad
    split at bad
    · rename_i reason e
      cases bad
      exact storeByte_undef h p offset byte _ e
    · rename_i next _
      exact storeBytesFrom_undef p rest next (offset + 1) r bad

theorem storeBytes_undef (h : Memory.Heap) (p : Nat) (bytes : List UInt8) : UndefErr (h.storeBytes p bytes) :=
  storeBytesFrom_undef p bytes h 0

theorem loadNatLE_undef (h : Memory.Heap) (a w : Nat) : UndefErr (Semantics.loadNatLE h a w) :=
  UndefErr.bind (loadBytes_undef h a w) fun _ => UndefErr.pure _

theorem wordBelow_undef (a o : Nat) : UndefErr (Semantics.wordBelow a o) := by
  intro r bad
  simp only [Semantics.wordBelow] at bad
  split at bad
  · cases bad
  · simp only [Except.error.injEq] at bad; subst bad; rfl

/-! ## Native values -/

-- One step on an `UndefErr` goal of Core's native layout code; `ih` covers the
-- recursive calls and `nofind` the empty view list.
set_option hygiene false in
macro "undef_step" : tactic => `(tactic| first
  | exact UndefErr.pure _
  | exact UndefErr.ok _
  | exact UndefErr.error rfl
  | exact loadNatLE_undef _ _ _
  | exact wordBelow_undef _ _
  | exact loadBytes_undef _ _ _
  | exact storeBytes_undef _ _ _
  | exact ih _ _
  | exact ih _ _ _ _
  | refine UndefErr.bind ?_ fun _ => ?_
  | refine UndefErr.mapM fun _ _ => ?_
  | refine UndefErr.foldlM fun _ _ _ => ?_
  | split
  | dsimp only
  | (exfalso; simp only [nofind, reduceCtorEq] at *))

theorem readNativeValue_undef : ∀ (fuel : Nat) (P : Core.Program) (heap : Memory.Heap) (ty : Core.Ty) (a : Nat),
    UndefErr (Semantics.readNativeValue fuel P heap ty a)
  | 0, _, _, _, _ => by simp only [Semantics.readNativeValue]; exact UndefErr.error rfl
  | fuel + 1, P, heap, ty, a => by
    have ih := readNativeValue_undef fuel P heap
    have nofind : True := trivial
    simp only [Semantics.readNativeValue]
    repeat' undef_step

/-! ## Safe slices inside a value -/

/-- `SliceIn r v`: a safe slice of the cell `r` is inside `v`, itself or in a
field or payload. -/
inductive SliceIn (r : Nat) : Lanius.Core.Value → Prop where
  | here {ty : Lanius.Core.Ty} {projections : List Lanius.Core.ValueProjection} {start length : Nat} :
      SliceIn r (.slice ty r projections start length)
  | field {id : Nat} {fields : List Lanius.Core.Value} {v : Lanius.Core.Value} :
      v ∈ fields → SliceIn r v → SliceIn r (.structure id fields)
  | payload {id k : Nat} {vs : List Lanius.Core.Value} {v : Lanius.Core.Value} :
      v ∈ vs → SliceIn r v → SliceIn r (.enumeration id k vs)

/-- No array view roots at a safe slice inside `v`. -/
def Unhit (views : List Semantics.I32ArrayView) (v : Lanius.Core.Value) : Prop :=
  ∀ w ∈ views, ∀ r, SliceIn r v → w.root ≠ r

theorem Unhit.nil (v : Lanius.Core.Value) : Unhit [] v := fun _ mem => by simp at mem

theorem Unhit.field {views : List Semantics.I32ArrayView} {id : Nat} {fields : List Lanius.Core.Value}
    (hit : Unhit views (.structure id fields)) {i : Nat} {fv : Lanius.Core.Value} (got : fields[i]? = some fv) :
    Unhit views fv :=
  fun w wm r s => hit w wm r (.field (List.mem_of_getElem? got) s)

theorem Unhit.payload {views : List Semantics.I32ArrayView} {id k : Nat} {vs : List Lanius.Core.Value}
    (hit : Unhit views (.enumeration id k vs)) {i : Nat} {fv : Lanius.Core.Value} (got : vs[i]? = some fv) :
    Unhit views fv :=
  fun w wm r s => hit w wm r (.payload (List.mem_of_getElem? got) s)

theorem Unhit.find {views : List Semantics.I32ArrayView} {ty : Lanius.Core.Ty} {root : Nat}
    {projections : List Lanius.Core.ValueProjection} {start length : Nat}
    (hit : Unhit views (.slice ty root projections start length)) {view : Semantics.I32ArrayView}
    (found : views.find? (fun candidate => decide (candidate.root = root ∧ candidate.projections = projections)) =
      some view) : False := by
  have mem := List.mem_of_find?_eq_some found
  have same := List.find?_some found
  simp only [decide_eq_true_eq] at same
  exact hit view mem root .here same.1

theorem writeNativeValue_undefHit : ∀ (fuel : Nat) (P : Core.Program) (st : State) (heap : Memory.Heap)
    (ty : Core.Ty) (a : Nat) (v : Core.Value), Unhit st.i32ArrayViews v →
      UndefErr (Semantics.writeNativeValue fuel P st heap ty a v)
  | 0, _, _, _, _, _, _, _ => by simp only [Semantics.writeNativeValue]; exact UndefErr.error rfl
  | fuel + 1, P, st, heap, ty, a, v, hit => by
    have ih : ∀ heap ty a v, Unhit st.i32ArrayViews v → UndefErr (Semantics.writeNativeValue fuel P st heap ty a v) :=
      fun heap ty a v h => writeNativeValue_undefHit fuel P st heap ty a v h
    have nofind : True := trivial
    simp only [Semantics.writeNativeValue]
    split
    all_goals first
      | exact storeBytes_undef _ _ _
      | skip
    all_goals repeat' (first
      | exact ih _ _ _ _ (hit.field ‹_›)
      | exact ih _ _ _ _ (hit.payload ‹_›)
      | (exfalso; exact hit.find ‹_›)
      | undef_step)

theorem writeNativeValue_undef (fuel : Nat) (P : Core.Program) (st : State) (heap : Memory.Heap) (ty : Core.Ty)
    (a : Nat) (v : Core.Value) (views : st.i32ArrayViews = []) :
    UndefErr (Semantics.writeNativeValue fuel P st heap ty a v) :=
  writeNativeValue_undefHit fuel P st heap ty a v (by rw [Unhit, views]; exact Unhit.nil v)

/-- A raw store: one byte of a byte view, or a native value's words. -/
theorem writeRawNative_undef (P : Core.Program) (st : State) (place : Semantics.ResolvedPlace) (ty : Core.Ty)
    (a : Nat) (v : Core.Value) (hit : Unhit st.i32ArrayViews v) :
    UndefErr (Semantics.writeRawNative P st place ty a v) := by
  simp only [Semantics.writeRawNative]
  split
  · simp only [Semantics.storeRawByte]
    split
    · exact storeBytes_undef _ _ _
    · exact UndefErr.error rfl
  · exact writeNativeValue_undefHit _ _ _ _ _ _ _ hit

/-- A scalar value has no safe slice inside. -/
theorem SrcType.Holds.noSlice {ty : SrcType} {v : Core.Value} {bits : BitVec 64} (h : ty.Holds v bits)
    {r : Nat} (s : SliceIn r v) : False := by
  cases s <;> cases ty <;> first
    | (simp [SrcType.Holds] at h; done)
    | (rename_i k; cases k <;> simp [SrcType.Holds, UintTy.SintHolds, NarrowHolds, FloatTy.value] at h <;> done)

mutual
/-- A safe slice inside a value that holds is of a place's cell. -/
theorem SrcType.HoldsAt.sliceIn {places : List Addressed} : ∀ {ty : SrcType} {v : Core.Value} {env : Env} {slot : Nat},
    ty.HoldsAt sx places v env slot → ∀ {r : Nat}, SliceIn r v → ∃ x ∈ places, x.cell = r
  | .i32, _, _, _, .i32 h, _, s => (h.noSlice s).elim
  | .bool, _, _, _, .bool h, _, s => (h.noSlice s).elim
  | .uint _, _, _, _, .uint h, _, s => (h.noSlice s).elim
  | .struct _ _, _, _, _, .struct fields, _, s => by
    cases s with
    | field mem inner => exact FieldsHold.sliceIn fields mem inner
  | .enum _ _, _, _, _, .enum _ _ payload, _, s => by
    cases s with
    | payload mem inner => exact FieldsHold.sliceIn payload mem inner
  | .ptr, _, _, _, .ptr h, _, s => (h.noSlice s).elim
  | .slice _, _, _, _, .slice _ _, _, s => by cases s
  | .slice _, _, _, _, .borrowed mem _ _ _ _ _ _ _, _, s => by
    cases s with
    | here => exact ⟨_, mem, rfl⟩
  | .array _ _, _, _, _, .array _, _, s => by cases s
  | .unit, _, _, _, .unit, _, s => by cases s
  | .isize, _, _, _, .isize h, _, s => (h.noSlice s).elim
  | .char, _, _, _, .char h, _, s => (h.noSlice s).elim
  | .float _, _, _, _, .float h, _, s => (h.noSlice s).elim
  | .sint _, _, _, _, .sint h, _, s => (h.noSlice s).elim
  | .view _, _, _, _, .view _ _, _, s => by cases s
  | .str, _, _, _, .str _ _ _ _, _, s => by cases s
  | .ref _, _, _, _, .ref held, _, s => by
    obtain ⟨_, _, rfl, _⟩ := held
    cases s
  termination_by structural _ _ _ _ h => h

theorem FieldsHold.sliceIn {places : List Addressed} : ∀ {fs : List SrcType} {vs : List Core.Value} {env : Env} {slot : Nat},
    FieldsHold sx places fs vs env slot → ∀ {v : Core.Value}, v ∈ vs → ∀ {r : Nat}, SliceIn r v →
      ∃ x ∈ places, x.cell = r
  | [], _, _, _, .nil, _, mem, _, _ => by simp at mem
  | _ :: _, _, _, _, .cons head rest, _, mem, _, s => by
    cases mem with
    | head => exact SrcType.HoldsAt.sliceIn head s
    | tail _ mem => exact FieldsHold.sliceIn rest mem s
  termination_by structural _ _ _ _ h => h
end

/-- A value that holds is unhit by views that root at no place. -/
theorem SrcType.HoldsAt.unhit {places : List Addressed} {ty : SrcType} {v : Core.Value} {env : Env} {slot : Nat}
    (holds : ty.HoldsAt sx places v env slot) {views : List Semantics.I32ArrayView}
    (unviewed : ∀ w ∈ views, ∀ x ∈ places, w.root ≠ x.cell) : Unhit views v := fun w wm r s => by
  obtain ⟨x, mem, rfl⟩ := holds.sliceIn s
  exact unviewed w wm x mem

theorem SrcType.Holds.unhit {ty : SrcType} {v : Core.Value} {bits : BitVec 64} (h : ty.Holds v bits)
    (views : List Semantics.I32ArrayView) : Unhit views v := fun _ _ _ s => (h.noSlice s).elim

end Lanius.Mini
