import Lanius.Faithful.Sim.State
import Lanius.Memory.Allocated

/-! # What a completed Core run of the prims' constructs did

The constructs `boxed`, `unbox` and the helpers they call use beyond the pure
subset: allocation, raw-slice index reads and writes. -/

namespace Lanius.Faithful

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (State Completion evalExpr evalExprs evalPlace execStmt ResolvedPlace restoreLocals)

theorem toCore_target' (sp : SrcProgram) : sp.toCore.target = .x86_64 := rfl

section
variable {P : Core.Program} {k : Nat} {st st' : State}

/-- A local read gives the local's value. -/
theorem local_eval {id : Nat} {x v : Value} (known : st.local? id = some x)
    (h : evalExpr k P st (.local id) = .done v st') : v = x ∧ st' = st := by
  obtain ⟨found, rfl⟩ := local_inv h
  rw [known] at found
  exact ⟨(Option.some.inj found).symm, rfl⟩

theorem alloc_inv {size align : Core.Expr} {v : Value} (h : evalExpr k P st (.alloc size align) = .done v st') :
    ∃ j n s1 m s2, k = j + 1 ∧ evalExpr j P st size = .done (.unsigned .usize n) s1 ∧
      evalExpr j P s1 align = .done (.unsigned .usize m) s2 ∧
      ((∃ p heap, s2.heap.allocate n m = .allocated p heap ∧ v = .pointer p ∧ st' = { s2 with heap }) ∨
        (∃ heap, s2.heap.allocate n m = .exhausted heap ∧ v = .pointer 0 ∧ st' = { s2 with heap })) := by
  cases k with
  | zero => simp [evalExpr] at h
  | succ j =>
    simp only [evalExpr] at h
    split at h
    · rename_i n s1 sizeRun
      split at h
      · rename_i m s2 alignRun
        split at h
        · rename_i p heap allocated
          simp only [Semantics.Outcome.done.injEq] at h
          obtain ⟨rfl, rfl⟩ := h
          exact ⟨j, n, s1, m, s2, rfl, sizeRun, alignRun, .inl ⟨p, heap, allocated, rfl, rfl⟩⟩
        · rename_i heap exhausted
          simp only [Semantics.Outcome.done.injEq] at h
          obtain ⟨rfl, rfl⟩ := h
          exact ⟨j, n, s1, m, s2, rfl, sizeRun, alignRun, .inr ⟨heap, exhausted, rfl, rfl⟩⟩
        · simp at h
      all_goals simp at h
    all_goals simp at h

theorem index_inv {b i : Core.Expr} {v : Value} (h : evalExpr k P st (.index b i) = .done v st') :
    ∃ j bv s1, k = j + 1 ∧ evalExpr j P st b = .done bv s1 ∧
      ∀ el a len, bv = .rawSlice el a len → ∃ iv pos, evalExpr j P s1 i = .done iv st' ∧
        Semantics.integerIndex iv = .ok pos ∧ Semantics.readRawSliceIndex P st' el a len pos = .ok v := by
  cases k with
  | zero => simp [evalExpr] at h
  | succ j =>
    simp only [evalExpr] at h
    split at h
    · rename_i elements s1 run
      exact ⟨j, _, s1, rfl, run, fun _ _ _ eq => by cases eq⟩
    · rename_i _ cell projections start length s1 run
      exact ⟨j, _, s1, rfl, run, fun _ _ _ eq => by cases eq⟩
    · rename_i el a len s1 run
      refine ⟨j, _, s1, rfl, run, fun el' a' len' eq => ?_⟩
      simp only [Value.rawSlice.injEq] at eq
      obtain ⟨rfl, rfl, rfl⟩ := eq
      split at h
      · rename_i iv s2 indexRun
        split at h
        · simp at h
        · rename_i pos posOk
          split at h
          · rename_i w read
            simp only [Semantics.Outcome.done.injEq] at h
            obtain ⟨rfl, rfl⟩ := h
            exact ⟨iv, pos, indexRun, posOk, read⟩
          · simp at h
      all_goals simp at h
    all_goals simp at h

/-- A local's place, for a read: its value. -/
theorem place_local_read {id : Nat} {x : Value} {r : ResolvedPlace} (known : st.local? id = some x)
    (h : evalPlace k P st .read (.local id) = .done r st') : r.value = some x ∧ st' = st := by
  cases k with
  | zero => simp [evalPlace] at h
  | succ j =>
    simp only [State.local?] at known
    simp only [evalPlace] at h
    split at h
    · simp at h
    · rename_i cell hc
      rw [hc] at known
      split at h
      · simp at h
      · rename_i entry he
        simp only [State.cell?, he, Option.bind_some] at known
        split at h
        · rename_i hv
          rw [hv] at known
          simp at known
        · simp only [Semantics.Outcome.done.injEq] at h
          obtain ⟨rfl, rfl⟩ := h
          exact ⟨known, rfl⟩

/-- An element's place in a raw slice. -/
theorem place_index_inv {b : Core.Place} {i : Core.Expr} {r : ResolvedPlace}
    (h : evalPlace k P st .address (.index b i) = .done r st') :
    ∃ j rb s1, k = j + 1 ∧ evalPlace j P st .read b = .done rb s1 ∧
      ∀ el a len, rb.value = some (.rawSlice el a len) → ∃ iv pos base, evalExpr j P s1 i = .done iv st' ∧
        Semantics.integerIndex iv = .ok pos ∧ pos < len ∧ Semantics.rawSliceElementAddress? P el a pos = .ok base ∧
        r.raw = some (el, base) := by
  cases k with
  | zero => simp [evalPlace] at h
  | succ j =>
    simp only [evalPlace] at h
    split at h
    · rename_i rb s1 baseRun
      refine ⟨j, rb, s1, rfl, baseRun, fun el a len hv => ?_⟩
      simp only [hv] at h
      split at h
      · rename_i iv s2 indexRun
        split at h
        · simp at h
        · rename_i pos posOk
          split at h
          · split at h
            · simp at h
            · rename_i lt _ base baseOk
              simp only [Semantics.Outcome.done.injEq] at h
              obtain ⟨rfl, rfl⟩ := h
              exact ⟨iv, pos, base, indexRun, posOk, lt, baseOk, rfl⟩
          · simp at h
      all_goals simp at h
    all_goals simp at h

/-- `place = e` that completed: the place, the value, the write, then the sync. -/
theorem assign_inv {place : Core.Place} {e : Core.Expr} {u : Value}
    (h : evalExpr k P st (.assign .set place e) = .done u st') :
    ∃ j r s1 rv s2 s3, k = j + 1 ∧ evalPlace j P st .address place = .done r s1 ∧
      evalExpr j P s1 e = .done rv s2 ∧ Semantics.writeResolvedPlaceNative P s2 r rv = .ok s3 ∧
      (if r.viewFreeRootWrite rv then .ok s3 else match r.raw with
        | none => Semantics.syncI32ViewsToHeap s3
        | some _ => Semantics.syncI32ViewsFromHeap s3) = .ok st' := by
  cases k with
  | zero => simp [evalExpr] at h
  | succ j =>
    simp only [evalExpr] at h
    split at h
    · rename_i r s1 placeRun
      split at h
      · rename_i rv s2 valueRun
        split at h
        · simp at h
        · rename_i result assigned
          simp only [Semantics.evalAssignValue, Semantics.assignOpBinary?, Except.ok.injEq] at assigned
          subst assigned
          split at h
          · rename_i s3 written
            split at h
            · rename_i coherent synced
              simp only [Semantics.Outcome.done.injEq] at h
              obtain ⟨rfl, rfl⟩ := h
              exact ⟨j, r, s1, rv, s2, s3, rfl, placeRun, valueRun, written, synced⟩
            · simp at h
          · simp at h
      all_goals simp at h
    all_goals simp at h

end

/-- A run that kept the invariant, the cells and the heap. -/
structure Same (st st' : State) : Prop where
  inv : Inv st'
  step : Step st st'
  heap : st'.heap = st.heap

theorem Same.refl {st : State} (inv : Inv st) : Same st st := ⟨inv, Step.refl st, rfl⟩

theorem Same.trans {a b c : State} (first : Same a b) (second : Same b c) : Same a c :=
  ⟨second.inv, first.step.trans second.step, second.heap.trans first.heap⟩

theorem Same.bind {a b : State} (first : Same a b) (id : Nat) (v : Value) : Same a (b.bindLocal id v) :=
  ⟨first.inv.bindLocal id v, first.step.trans (Step.bindLocal b id v), first.heap⟩

theorem Same.restore {a b : State} (s : State) (first : Same a b) : Same a (restoreLocals s b) :=
  ⟨first.inv.restore s, first.step.restore s, first.heap⟩

/-- A call whose arguments Core evaluates to `vals`, keeping the state: the
callee's body on fresh locals, then the caller's locals back. -/
theorem call_pure {sp : SrcProgram} {k : Nat} {st st' : State} {callee : Nat} {args : List Core.Expr}
    {vals : List Value} {v : Value} {f : SrcFunc} (found : sp.funcs[callee]? = some f)
    (pure : ∀ {j vs s}, evalExprs j sp.toCore st args = .done vs s → vs = vals ∧ s = st)
    (h : evalExpr k sp.toCore st (.call callee args) = .done v st') :
    ∃ j completed c, execStmt j sp.toCore (({ st with locals := [] } : State).bindLocals
      (paramBindings f.params vals)) f.body.toCore = .done c completed ∧ CallResult f.ret c v ∧
      st' = restoreLocals st completed := by
  obtain ⟨j, f', values, afterArgs, completed, c, -, argsRun, found', -, body, result, rfl⟩ := call_inv' h
  obtain ⟨rfl, rfl⟩ := pure argsRun
  rw [found, Option.some.injEq] at found'
  subst found'
  exact ⟨j, completed, c, body, result, rfl⟩

/-- A call's state: the body's run on fresh locals, with the caller's locals back. -/
theorem Same.call {st completed : State} (bs : List (Nat × Value))
    (body : Same (({ st with locals := [] } : State).bindLocals bs) completed) :
    Same st (restoreLocals st completed) :=
  ⟨body.inv.restore st, ((Step.clear st).trans ((Step.bindLocals bs _).trans body.step)).restore st,
    body.heap.trans (bindLocals_same bs _).1⟩

theorem Same.start {st : State} (inv : Inv st) (bs : List (Nat × Value)) :
    Inv (({ st with locals := [] } : State).bindLocals bs) :=
  Inv.bindLocals bs inv.clear

/-- The allocator's fresh block: at the allocation address, zeroed. -/
theorem allocate_allocated {heap heap' : Memory.Heap} {n m p : Nat}
    (h : heap.allocate n m = .allocated p heap') :
    p = heap.allocationAddress m ∧ ∃ budget, heap' = heap.allocatedBytes n m budget := by
  unfold Memory.Heap.allocate at h
  split at h
  · simp at h
  · split at h
    · simp at h
    · rename_i budget _
      simp only [Memory.AllocationResult.allocated.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      exact ⟨rfl, budget, rfl⟩

theorem allocate_exhausted' {heap heap' : Memory.Heap} {n m : Nat}
    (h : heap.allocate n m = .exhausted heap') : heap' = heap := by
  unfold Memory.Heap.allocate at h
  split at h
  · simp at h
  · split at h
    · simp only [Memory.AllocationResult.exhausted.injEq] at h
      exact h.symm
    · simp at h

end Lanius.Faithful
