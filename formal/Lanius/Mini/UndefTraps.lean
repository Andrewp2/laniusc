import Lanius.Mini.Fails

/-!
# Undefined traps of Core's raw memory

`UndefErr e`: every error `e` can return is an undefined trap. Core's native
loads and stores of typed values fail only with raw memory errors and
`typeMismatch`, so they are `UndefErr`.
-/

namespace Lanius.Mini

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

theorem writeNativeValue_undef : ∀ (fuel : Nat) (P : Core.Program) (st : State) (heap : Memory.Heap) (ty : Core.Ty)
    (a : Nat) (v : Core.Value), st.i32ArrayViews = [] → UndefErr (Semantics.writeNativeValue fuel P st heap ty a v)
  | 0, _, _, _, _, _, _, _ => by simp only [Semantics.writeNativeValue]; exact UndefErr.error rfl
  | fuel + 1, P, st, heap, ty, a, v, views => by
    have ih : ∀ heap ty a v, UndefErr (Semantics.writeNativeValue fuel P st heap ty a v) :=
      fun heap ty a v => writeNativeValue_undef fuel P st heap ty a v views
    have nofind : ∀ p, st.i32ArrayViews.find? p = none := by simp [views]
    simp only [Semantics.writeNativeValue]
    repeat' undef_step

end Lanius.Mini
