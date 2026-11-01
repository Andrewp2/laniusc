import Lanius.Faithful.Sim.PrimInv
import Lanius.Faithful.Sim.Slice
import Lanius.Semantics.NativeReadFrame
import Lanius.Memory.Store

/-! # Core runs of driver code

The self-host driver is not in the pure subset: it makes raw i32 slices of
its input and output, reads input words and writes output words. These are
the facts its proof uses about those constructs, and about locals, beyond
what the pure subset needs. -/

namespace Lanius.Faithful

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (State Completion evalExpr evalExprs evalPlace execStmt ResolvedPlace restoreLocals
  evalBinaryValue readRawSliceIndex)

/-! ## Locals -/

/-- A local keeps its value while its cell stays and the locals do. -/
theorem local?_prefix {st st' : State} (pre : st.cells <+: st'.cells) (locals : st'.locals = st.locals)
    {id : Nat} {v : Value} (found : st.local? id = some v) : st'.local? id = some v := by
  unfold State.local? State.cellId? at found ⊢
  rw [locals]
  cases hc : (st.locals.find? fun binding => binding.1 == id) with
  | none => rw [hc] at found; cases found
  | some b => rw [hc] at found; exact cell?_prefix pre found

theorem local?_bindLocals_other : ∀ (bs : List (Nat × Value)) {st : State} {id : Nat} {v : Value},
    (∀ b ∈ bs, b.1 ≠ id) → st.local? id = some v → (st.bindLocals bs).local? id = some v
  | [], _, _, _, _, found => found
  | b :: bs, st, id, v, ne, found => by
    rw [bindLocals_cons]
    exact local?_bindLocals_other bs (fun b' m => ne b' (List.mem_cons_of_mem _ m))
      (local?_bindLocal_other (ne b List.mem_cons_self) b.2 found)

theorem bindLocals_append : ∀ (pre post : List (Nat × Value)) (st : State),
    st.bindLocals (pre ++ post) = (st.bindLocals pre).bindLocals post
  | [], _, _ => rfl
  | b :: pre, post, st => by
    rw [List.cons_append, bindLocals_cons, bindLocals_cons]
    exact bindLocals_append pre post _

/-- A parameter's value on entry: the last binding of its id. -/
theorem local?_entry {st : State} (inv : Inv st) (pre post : List (Nat × Value)) (id : Nat) (v : Value)
    {bs : List (Nat × Value)} (eq : bs = pre ++ (id, v) :: post) (ne : ∀ b ∈ post, b.1 ≠ id) :
    (({ st with locals := [] } : State).bindLocals bs).local? id = some v := by
  subst eq
  rw [bindLocals_append, bindLocals_cons]
  exact local?_bindLocals_other post ne
    (local?_bindLocal_self ((Inv.bindLocals pre inv.clear)) id v)

/-- Locals with known values evaluate to them and keep the state. -/
theorem exprs_locals {P : Core.Program} {st : State} :
    ∀ (bs : List (Nat × Value)), (∀ b ∈ bs, st.local? b.1 = some b.2) →
    ∀ {k : Nat} {vs : List Value} {st' : State},
      evalExprs k P st (bs.map fun b => .local b.1) = .done vs st' → vs = bs.map Prod.snd ∧ st' = st
  | [], _, _, _, _, h => exprs_nil_inv h
  | b :: bs, known, _, _, _, h => by
    obtain ⟨j, v, s1, more, -, run, runRest, rfl⟩ := exprs_cons_inv h
    obtain ⟨rfl, rfl⟩ := local_eval (known b List.mem_cons_self) run
    obtain ⟨rfl, rfl⟩ := exprs_locals bs (fun b' m => known b' (List.mem_cons_of_mem _ m)) runRest
    exact ⟨rfl, rfl⟩

/-- A call's run on fresh locals, as a step of the caller's state. -/
theorem Step.call {st completed : State} (bs : List (Nat × Value))
    (body : Step (({ st with locals := [] } : State).bindLocals bs) completed) :
    Step st (restoreLocals st completed) :=
  ((Step.clear st).trans ((Step.bindLocals bs _).trans body)).restore st

/-! ## usize arithmetic -/

theorem nat_greater (a b : Nat) :
    evalBinaryValue .x86_64 .greater (.unsigned .usize a) (.unsigned .usize b) = .ok (.boolean (decide (a > b))) := by
  simp [evalBinaryValue, Semantics.evalUnsignedBinary]

theorem nat_add {a b : Nat} (lt : a + b < 2 ^ 64) :
    evalBinaryValue .x86_64 .add (.unsigned .usize a) (.unsigned .usize b) = .ok (.unsigned .usize (a + b)) := by
  have hb : (2 : Nat) ^ Core.Target.x86_64.pointerWidth.bits = 18446744073709551616 := by decide
  simp only [evalBinaryValue, beq_self_eq_true, if_true, Semantics.evalUnsignedBinary, Semantics.wrapUnsigned,
    Semantics.unsignedModulus, Core.UnsignedIntTy.bits, hb, Except.ok.injEq, Value.unsigned.injEq, true_and]
  omega

theorem nat_sub {a b : Nat} (le : b ≤ a) (lt : a < 2 ^ 64) :
    evalBinaryValue .x86_64 .subtract (.unsigned .usize a) (.unsigned .usize b) = .ok (.unsigned .usize (a - b)) := by
  rw [unsigned_subtract]
  simp only [Except.ok.injEq, Value.unsigned.injEq, true_and]
  omega

theorem nat_half (a : Nat) (lt : a < 2 ^ 64) :
    evalBinaryValue .x86_64 .divide (.unsigned .usize a) (.unsigned .usize 2) = .ok (.unsigned .usize (a / 2)) := by
  have hb : (2 : Nat) ^ Core.Target.x86_64.pointerWidth.bits = 18446744073709551616 := by decide
  simp only [evalBinaryValue, beq_self_eq_true, if_true, Semantics.evalUnsignedBinary, Semantics.wrapUnsigned,
    Semantics.unsignedModulus, Core.UnsignedIntTy.bits, hb]
  simp only [show ((2 : Nat) == 0) = false by decide, Bool.false_eq_true, if_false, Except.ok.injEq,
    Value.unsigned.injEq, true_and]
  omega

/-! ## Raw i32 slices -/

section
variable {P : Core.Program} {k : Nat} {st st' : State}

/-- `slice_from_raw_parts(p, n)` that completed: a pointer, a length, the
view, and no change to the state. -/
theorem i32Slice_inv {p n : Core.Expr} {v : Value}
    (h : evalExpr k P st (.i32SliceFromRawParts p n) = .done v st') :
    ∃ j a s1 len, k = j + 1 ∧ evalExpr j P st p = .done (.pointer a) s1 ∧
      evalExpr j P s1 n = .done (.signed .i32 len) st' ∧ 0 ≤ len ∧
      v = .rawSlice (.scalar (.signed .i32)) a len.toNat := by
  cases k with
  | zero => simp [evalExpr] at h
  | succ j =>
    simp only [evalExpr] at h
    split at h
    · rename_i a s1 runP
      split at h
      · rename_i len s2 runN
        refine ⟨j, a, s1, len, rfl, runP, ?_⟩
        unfold Semantics.mapRawI32Slice at h
        split at h
        · simp at h
        · split at h
          · rename_i zero
            simp only [Semantics.Outcome.done.injEq] at h
            obtain ⟨rfl, rfl⟩ := h
            exact ⟨runN, by omega, by rw [zero]; rfl⟩
          · simp only at h
            split at h
            · simp at h
            · simp only [Semantics.Outcome.done.injEq] at h
              obtain ⟨rfl, rfl⟩ := h
              exact ⟨runN, by omega, rfl⟩
      all_goals simp at h
    all_goals simp at h

end

/-- An i32 store through a raw place: the bytes of the value at its address. -/
theorem writeNative_i32 {P : Core.Program} {st : State} {heap : Memory.Heap} {a : Nat} {x : Int} :
    Semantics.writeNativeValue NativeLayout.maxDepth P st heap (.scalar (.signed .i32)) a (.signed .i32 x) =
      heap.storeBytes a (Semantics.i32Bytes x) := by
  simp [NativeLayout.maxDepth, Semantics.writeNativeValue]

/-- A store that the heap's storage allows is the exact byte write. -/
theorem storeBytes_write {heap heap' : Memory.Heap} {a : Nat} {bytes : List UInt8}
    (unique : Memory.HeapBlockBasesUnique heap)
    (room : heap.Readable a bytes.length)
    (stored : heap.storeBytes a bytes = .ok heap') : Memory.BytesWrite heap heap' a bytes := by
  obtain ⟨after, ok, write⟩ := Memory.Heap.storeBytes_of_readable bytes unique (fun i lt => room i lt)
  rw [ok, Except.ok.injEq] at stored
  subst stored
  exact write

end Lanius.Faithful
