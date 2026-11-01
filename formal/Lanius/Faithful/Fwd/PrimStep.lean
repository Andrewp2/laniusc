import Lanius.Faithful.Fwd.Step
import Lanius.Faithful.Sim.PrimInv

/-! # Forward: the Core steps the prims take

Raw views, their strides, allocation, element places, writes and reads,
run forward as in `Fwd/Step.lean`. -/

namespace Lanius.Faithful

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (State Completion evalExpr evalExprs evalPlace execStmt ResolvedPlace restoreLocals
  mapRawNominalSlice)

section
variable {P : Core.Program} {st : State}

theorem typedSlice_fwd {el : Core.Ty} {p n : Core.Expr} {a : Nat} {c : Int} {v : Value} {s1 s2 s3 : State}
    (hp : Ev (fun k => evalExpr k P st p) (.pointer a) s1) (hn : Ev (fun k => evalExpr k P s1 n) (.signed .i32 c) s2)
    (m : mapRawNominalSlice P s2 el a c = .done v s3) :
    Ev (fun k => evalExpr k P st (.typedSliceFromRawParts el p n)) v s3 := by
  obtain ⟨K1, h1⟩ := hp
  obtain ⟨K2, h2⟩ := hn
  refine ⟨max K1 K2 + 1, fun k hk => ?_⟩
  obtain ⟨j, rfl⟩ : ∃ j, k = j + 1 := ⟨k - 1, by omega⟩
  simp only [evalExpr, h1 j (by omega), h2 j (by omega), m]

theorem stride_fwd {e : Core.Expr} {w : Value} {x : Int} {s : State} (sub : Ev (fun k => evalExpr k P st e) w s)
    (hs : Semantics.rawSliceStride? P w = some x) :
    Ev (fun k => evalExpr k P st (.intrinsic .sliceStride e)) (.signed .isize x) s := by
  obtain ⟨K, hK⟩ := sub
  refine ⟨K + 1, fun k hk => ?_⟩
  obtain ⟨j, rfl⟩ : ∃ j, k = j + 1 := ⟨k - 1, by omega⟩
  simp only [evalExpr, hK j (by omega)]
  cases w <;> simp_all [Semantics.rawSliceStride?]

theorem alloc_fwd {size align : Core.Expr} {n m p : Nat} {H : Memory.Heap} {s1 s2 : State}
    (hs : Ev (fun k => evalExpr k P st size) (.unsigned .usize n) s1)
    (ha : Ev (fun k => evalExpr k P s1 align) (.unsigned .usize m) s2) (al : s2.heap.allocate n m = .allocated p H) :
    Ev (fun k => evalExpr k P st (.alloc size align)) (.pointer p) { s2 with heap := H } := by
  obtain ⟨K1, h1⟩ := hs
  obtain ⟨K2, h2⟩ := ha
  refine ⟨max K1 K2 + 1, fun k hk => ?_⟩
  obtain ⟨j, rfl⟩ : ∃ j, k = j + 1 := ⟨k - 1, by omega⟩
  simp only [evalExpr, h1 j (by omega), h2 j (by omega), al]

theorem place_local_fwd {id : Nat} {x : Value} (known : st.local? id = some x) :
    ∃ r : ResolvedPlace, r.value = some x ∧ Ev (fun k => evalPlace k P st .read (.local id)) r st := by
  unfold State.local? State.cell? at known
  cases hc : st.cellId? id with
  | none => rw [hc] at known; cases known
  | some cell =>
    rw [hc, Option.bind_some] at known
    cases he : st.cellEntry? cell with
    | none => rw [he] at known; cases known
    | some entry =>
      rw [he, Option.bind_some] at known
      rcases entry with ⟨eid, _ | value⟩
      · cases known
      · simp only [Option.some.injEq] at known
        subst known
        refine ⟨{ root := cell, projections := [], value := some value }, rfl, 1, fun k hk => ?_⟩
        obtain ⟨j, rfl⟩ : ∃ j, k = j + 1 := ⟨k - 1, by omega⟩
        simp only [evalPlace, hc, he]

theorem place_index_fwd {b : Core.Place} {i : Core.Expr} {rb : ResolvedPlace} {s1 s2 : State} {el : Core.Ty}
    {a len : Nat} {iv : Value} {pos base : Nat}
    (hb : Ev (fun k => evalPlace k P st .read b) rb s1) (hv : rb.value = some (.rawSlice el a len))
    (hi : Ev (fun k => evalExpr k P s1 i) iv s2) (ip : Semantics.integerIndex iv = .ok pos) (lt : pos < len)
    (hbase : Semantics.rawSliceElementAddress? P el a pos = .ok base) :
    Ev (fun k => evalPlace k P st .address (.index b i)) { rb with value := none, raw := some (el, base) } s2 := by
  obtain ⟨K1, h1⟩ := hb
  obtain ⟨K2, h2⟩ := hi
  refine ⟨max K1 K2 + 1, fun k hk => ?_⟩
  obtain ⟨j, rfl⟩ : ∃ j, k = j + 1 := ⟨k - 1, by omega⟩
  simp only [evalPlace, h1 j (by omega), hv, h2 j (by omega), ip, lt, if_true, hbase]

theorem assign_fwd {place : Core.Place} {e : Core.Expr} {r : ResolvedPlace} {rv : Value} {s1 s2 s3 s4 : State}
    (hp : Ev (fun k => evalPlace k P st .address place) r s1) (he : Ev (fun k => evalExpr k P s1 e) rv s2)
    (w : Semantics.writeResolvedPlaceNative P s2 r rv = .ok s3)
    (sync : (if r.viewFreeRootWrite rv then .ok s3 else match r.raw with
        | none => Semantics.syncI32ViewsToHeap s3
        | some _ => Semantics.syncI32ViewsFromHeap s3) = .ok s4) :
    Ev (fun k => evalExpr k P st (.assign .set place e)) .unit s4 := by
  obtain ⟨K1, h1⟩ := hp
  obtain ⟨K2, h2⟩ := he
  refine ⟨max K1 K2 + 1, fun k hk => ?_⟩
  obtain ⟨j, rfl⟩ : ∃ j, k = j + 1 := ⟨k - 1, by omega⟩
  simp only [evalExpr, h1 j (by omega), h2 j (by omega), Semantics.evalAssignValue, Semantics.assignOpBinary?, w]
  revert sync
  cases (if r.viewFreeRootWrite rv = true then Except.ok s3 else
      match r.raw with
      | none => Semantics.syncI32ViewsToHeap s3
      | some _ => Semantics.syncI32ViewsFromHeap s3) with
  | ok x => intro sync; cases sync; rfl
  | error e => intro sync; cases sync

theorem index_fwd {b i : Core.Expr} {el : Core.Ty} {a len : Nat} {iv v : Value} {pos : Nat} {s1 s2 : State}
    (hb : Ev (fun k => evalExpr k P st b) (.rawSlice el a len) s1) (hi : Ev (fun k => evalExpr k P s1 i) iv s2)
    (ip : Semantics.integerIndex iv = .ok pos) (read : Semantics.readRawSliceIndex P s2 el a len pos = .ok v) :
    Ev (fun k => evalExpr k P st (.index b i)) v s2 := by
  obtain ⟨K1, h1⟩ := hb
  obtain ⟨K2, h2⟩ := hi
  refine ⟨max K1 K2 + 1, fun k hk => ?_⟩
  obtain ⟨j, rfl⟩ : ∃ j, k = j + 1 := ⟨k - 1, by omega⟩
  simp only [evalExpr, h1 j (by omega), h2 j (by omega), ip, read]

end

end Lanius.Faithful
