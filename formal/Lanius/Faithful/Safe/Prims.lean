import Lanius.Faithful.Safe.Run
import Lanius.Faithful.Sim.Boxed

/-! # The prims trap only definedly

`size_of<T>` and `typed_slice_from_storage<T>` make views Core can check:
an empty one, and a one-element one of storage whose range checks. `panic`
traps `assertionFailed`. `boxed<T>` writes into storage it allocated, and
`unbox<T>` reads a box's storage, whose range and value `VRel.box` keep. -/

namespace Lanius.Faithful

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (State Completion evalExpr evalExprs execStmt restoreLocals mapRawNominalSlice)

/-! ## Raw views of word elements -/

theorem map_zero {P : Core.Program} {s : State} {T : Core.Ty} {a w : Nat}
    (kind : (∃ id, T = .structure id) ∨ ∃ id, T = .enumeration id) (hw : NativeLayout.valueWords? P T = some w)
    (pos : 0 < w) : mapRawNominalSlice P s T a 0 = .done (.rawSlice T a (Int.toNat 0)) s := by
  have nz : (w == 0) = false := by simp only [beq_eq_false_iff_ne]; omega
  rcases kind with ⟨id, rfl⟩ | ⟨id, rfl⟩ <;>
  · simp only [mapRawNominalSlice, hw, nz]
    rfl

theorem map_one {P : Core.Program} {s : State} {T : Core.Ty} {a w : Nat}
    (kind : (∃ id, T = .structure id) ∨ ∃ id, T = .enumeration id) (hw : NativeLayout.valueWords? P T = some w)
    (pos : 0 < w) (room : a + 8 * w ≤ 2 ^ 64) (range : s.heap.checkRange a (8 * w) 8 = .ok ()) :
    mapRawNominalSlice P s T (a + 8 * w - 8) 1 = .done (.rawSlice T (a + 8 * w - 8) (Int.toNat 1)) s := by
  have nz : (w == 0) = false := by simp only [beq_eq_false_iff_ne]; omega
  have first : a + 8 * w - 8 + 8 - 8 * w = a := by omega
  have fits : ¬ (a + 8 * w - 8 + 8 < 8 * w) := by omega
  rcases kind with ⟨id, rfl⟩ | ⟨id, rfl⟩ <;>
  · simp [mapRawNominalSlice, hw, nz, NativeLayout.wordBytes, first, fits, range, Nat.mul_comm w 8]

/-! ## Raw stores and allocations -/

section
variable {P : Core.Program} {st : State} {k : Nat} {r : Lanius.Trap} {s : State}

theorem place_local_trap {id : Nat} {x : Value} {acc : Semantics.PlaceAccess} (known : st.local? id = some x)
    (h : Semantics.evalPlace k P st acc (.local id) = .trapped r s) : False := by
  cases k with
  | zero => simp [Semantics.evalPlace] at h
  | succ j =>
    simp only [State.local?] at known
    simp only [Semantics.evalPlace] at h
    split at h
    · rename_i none; simp [none] at known
    · rename_i cell hc
      rw [hc, Option.bind_some] at known
      split at h
      · rename_i none; simp [State.cell?, none] at known
      · rename_i entry he
        simp only [State.cell?, he, Option.bind_some] at known
        split at h
        · rename_i hv; rw [hv] at known; simp at known
        · simp at h

/-- `view[i] = x` on a raw view whose element `i` has an address: only the
native write can trap, at the state it started from. -/
theorem set_raw_trap {view x : Nat} {iv : Value} {el : Core.Ty} {a len pos base : Nat} {v : Value}
    (views : st.i32ArrayViews = [])
    (hview : st.local? view = some (.rawSlice el a len)) (hx : st.local? x = some v)
    (ix : Semantics.integerIndex iv = .ok pos) (lt : pos < len)
    (hb : Semantics.rawSliceElementAddress? P el a pos = .ok base)
    (h : evalExpr k P st (.assign .set (.index (.local view) (.value iv)) (.local x)) = .trapped r s) :
    s = st ∧ Semantics.writeNativeValue NativeLayout.maxDepth P st st.heap el base v = .error r := by
  cases k with
  | zero => simp [evalExpr] at h
  | succ j =>
    simp only [evalExpr] at h
    cases hp : Semantics.evalPlace j P st .address (.index (.local view) (.value iv)) with
    | done rp s1 =>
      rw [hp] at h
      simp only at h
      obtain ⟨j', rb, s0, rfl, baseRun, idx⟩ := place_index_inv hp
      obtain ⟨hrb, hs0⟩ := place_local_read hview baseRun
      subst s0
      obtain ⟨iv', pos', base', ir, hi, -, hb', raw⟩ := idx _ _ _ hrb
      obtain ⟨rfl, hs1⟩ := value_inv ir
      subst s1
      rw [ix, Except.ok.injEq] at hi
      subst hi
      rw [hb, Except.ok.injEq] at hb'
      subst hb'
      cases hv : evalExpr (j' + 1) P st (.local x) with
      | done u s2 =>
        obtain ⟨rfl, hs2⟩ := local_eval hx hv
        subst s2
        rw [hv] at h
        simp only [Semantics.evalAssignValue, Semantics.assignOpBinary?, Semantics.writeResolvedPlaceNative, raw] at h
        cases hw : Semantics.writeNativeValue NativeLayout.maxDepth P st st.heap el base u with
        | ok H =>
          simp only [hw, bind, Except.bind, pure, Except.pure, Semantics.ResolvedPlace.viewFreeRootWrite, raw,
            Option.isNone_some, Bool.false_and, Bool.false_eq_true, if_false,
            syncFrom_ok (st := { st with heap := H }) views] at h
          simp at h
        | error e =>
          simp only [hw, bind, Except.bind] at h
          simp only [Semantics.Outcome.trapped.injEq] at h
          obtain ⟨rfl, rfl⟩ := h
          exact ⟨rfl, rfl⟩
      | trapped r2 s2 => exact (local_trap hx hv).elim
      | exited c s2 => rw [hv] at h; simp at h
      | outOfFuel => rw [hv] at h; simp at h
    | trapped r1 s1 =>
      exfalso
      cases j with
      | zero => simp [Semantics.evalPlace] at hp
      | succ j' =>
        simp only [Semantics.evalPlace] at hp
        cases hl : Semantics.evalPlace j' P st .read (.local view) with
        | done rb s0 =>
          obtain ⟨hrb, hs0⟩ := place_local_read hview hl
          subst s0
          rw [hl] at hp
          simp only [hrb] at hp
          cases hi : evalExpr j' P st (.value iv) with
          | done u s2 =>
            obtain ⟨rfl, hs2⟩ := value_inv hi
            subst s2
            rw [hi] at hp
            simp [ix, lt, hb] at hp
          | trapped r2 s2 => exact value_trap hi
          | exited c s2 => rw [hi] at hp; simp at hp
          | outOfFuel => rw [hi] at hp; simp at hp
        | trapped r0 s0 => exact place_local_trap hview hl
        | exited c s0 => rw [hl] at hp; simp at hp
        | outOfFuel => rw [hl] at hp; simp at hp
    | exited c s1 => rw [hp] at h; simp at h
    | outOfFuel => rw [hp] at h; simp at h

theorem allocate_not_trapped {h h' : Memory.Heap} {n m : Nat} (valid : Memory.validAlignment m = true)
    (ok : h.allocate n m = .trapped r h') : False := by
  simp only [Memory.Heap.allocate, valid, Bool.not_true, Bool.false_eq_true, if_false] at ok
  split at ok <;> simp at ok

/-- An allocation of a known size at a valid alignment does not trap. -/
theorem alloc_trap {size align : Core.Expr} {n m : Nat}
    (ks : Known P st size (.unsigned .usize n)) (ka : Known P st align (.unsigned .usize m))
    (valid : Memory.validAlignment m = true) (h : evalExpr k P st (.alloc size align) = .trapped r s) : False := by
  cases k with
  | zero => simp [evalExpr] at h
  | succ j =>
    simp only [evalExpr] at h
    cases hs : evalExpr j P st size with
    | done u s1 =>
      obtain ⟨rfl, hs1⟩ := ks.done hs
      subst s1
      rw [hs] at h
      simp only at h
      cases ha : evalExpr j P st align with
      | done u2 s2 =>
        obtain ⟨rfl, hs2⟩ := ka.done ha
        subst s2
        rw [ha] at h
        simp only at h
        cases hal : st.heap.allocate n m with
        | allocated p H => rw [hal] at h; simp at h
        | exhausted H => rw [hal] at h; simp at h
        | trapped r' H => exact allocate_not_trapped valid hal
      | trapped r2 s2 => exact ka.safe ha
      | exited c s2 => rw [ha] at h; simp at h
      | outOfFuel => rw [ha] at h; simp at h
    | trapped r1 s1 => exact ks.safe hs
    | exited c s1 => rw [hs] at h; simp at h
    | outOfFuel => rw [hs] at h; simp at h

end

/-- A trapped run of a statement of `sp` ends with the heap cursor at or past
where it started, so a safety proof may assume the start's cursor in bounds. -/
theorem SafeS.of_bound {sp : SrcProgram} {st : State} {s : SrcStmt} (inv : Inv st)
    (safe : st.heap.nextAddress ≤ 2 ^ 64 → SafeS sp.toCore st s.toCore) : SafeS sp.toCore st s.toCore :=
  fun k r s' h bound => safe (Nat.le_trans ((execStmt_trap_grows h) inv.views).2 bound) k r s' h bound

theorem valueWords_pos {P : Core.Program} {T : Core.Ty} {w : Nat}
    (kind : (∃ id, T = .structure id) ∨ ∃ id, T = .enumeration id) (hw : NativeLayout.valueWords? P T = some w) :
    0 < w := by
  rw [NativeLayout.valueWords?, show NativeLayout.maxDepth = (NativeLayout.maxDepth - 1) + 1 by decide] at hw
  rcases kind with ⟨id, rfl⟩ | ⟨id, rfl⟩
  · rw [NativeLayout.words?] at hw
    simp only [bind, Option.bind_eq_some_iff] at hw
    obtain ⟨_, _, _, _, hw⟩ := hw
    split at hw
    · simp only [Option.some.injEq] at hw; omega
    · simp at hw
  · rw [NativeLayout.words?] at hw
    simp only [bind, Option.bind_eq_some_iff] at hw
    obtain ⟨_, _, _, _, hw⟩ := hw
    simp only [Option.some.injEq] at hw
    omega

section
variable {sp : SrcProgram} {st : State}

/-! ## `size_of` and `panic` -/

theorem sizeOf_safe {t : SrcType} (el : wordElement sp.decls t = true) {w : Nat}
    (hw : NativeLayout.valueWords? sp.toCore t.toCore = some w) (pos : 0 < w) (inv : Inv st) :
    SafeS sp.toCore st (sizeOfFunc t).body.toCore := by
  obtain ⟨slice, kind⟩ := sliceFrom_word el
  have most := valueWords_le kind hw
  simp only [NativeLayout.maxWords] at most
  simp only [sizeOfFunc, SrcStmt.toCore, SrcExpr.toCore, SrcEff.toCore, SrcOp.toCore, SrcType.toCore,
    SrcType.toScalar, UintTy.toCore, slice, bv_zero]
  have inv1 := inv.bindLocal 32 (.pointer 0)
  refine safeS_let_known (known_value _) ?_
  refine safeS_let_known (known_typedSlice (known_local (local?_bindLocal_self inv 32 _)) (known_value _)
    (map_zero kind hw pos)) ?_
  have inv2 := inv1.bindLocal 58 (.rawSlice t.toCore 0 (Int.toNat 0))
  refine safeS_let_known (known_stride (known_local (local?_bindLocal_self inv1 58 _)) (stride_word kind hw)) ?_
  have known := local?_bindLocal_self inv2 113 (.signed .isize (-((8 * w : Nat) : Int)))
  have zero : ∀ {s : State}, Known sp.toCore s (.cast (.signed .isize) (.value (.signed .i32 0))) (.signed .isize 0) :=
    known_cast (known_value _) (by rw [toCore_target']; exact cast_isize (by decide) (by decide) _)
  have cond := known_binary (P := sp.toCore) (op := .less) (by decide) (by decide) (known_local known) zero
    (by rw [toCore_target', signed_less])
  have neg : decide (-((8 * w : Nat) : Int) < 0) = true := by simp only [decide_eq_true_eq]; omega
  rw [neg] at cond
  refine safeS_seq (safeS_if_known cond ?_) fun h => ?_
  · simp only [if_true]
    refine safeS_return (known_cast (v := .unsigned .usize (8 * w)) (known_binary (by decide) (by decide) zero
      (known_local known) (by rw [toCore_target', signed_subtract])) ?_).safeE
    rw [Int.sub_neg, Int.zero_add, wrap_isize_of (by omega) (by omega), toCore_target']
    exact cast_usize_nat (by omega) _
  · obtain ⟨j, -, h⟩ := if_known_done cond h
    exact (return_not_next h).elim

/-- `typed_slice_from_storage<t>(storage, 1)` on storage at `a` whose range
checks. -/
theorem slice_safe {t : SrcType} (el : wordElement sp.decls t = true) {w a : Nat}
    (hw : NativeLayout.valueWords? sp.toCore t.toCore = some w) (pos : 0 < w) (inv : Inv st)
    (storage : st.local? 28 = some (.pointer a)) (one : st.local? 42 = some (.signed .i32 1))
    (room : st.heap.nextAddress ≤ 2 ^ 64 → a + 8 * w ≤ 2 ^ 64) (range : st.heap.checkRange a (8 * w) 8 = .ok ()) :
    SafeS sp.toCore st (sliceFunc t).body.toCore := by
  refine SafeS.of_bound inv fun bound => ?_
  replace room := room bound
  obtain ⟨slice, kind⟩ := sliceFrom_word el
  have most := valueWords_le kind hw
  simp only [NativeLayout.maxWords] at most
  simp only [sliceFunc, SrcStmt.toCore, SrcExpr.toCore, SrcEff.toCore, SrcOp.toCore, SrcType.toCore,
    SrcType.toScalar, UintTy.toCore, slice, bv_zero, bv_eight]
  -- the assertion
  have nonneg := known_binary (P := sp.toCore) (op := .greaterEqual) (by decide) (by decide) (known_local one)
    (known_value (.signed .i32 0)) (by rw [toCore_target', signed_greaterEqual])
  have yes : decide ((1 : Int) ≥ 0) = true := by decide
  rw [yes] at nonneg
  refine safeS_seq (safeS_expression (known_assert nonneg).safeE) fun h => ?_
  obtain ⟨-, rfl⟩ := expression_known_done (known_assert nonneg) h
  -- the empty view and its stride
  have inv1 := inv.bindLocal 97 (.pointer 0)
  refine safeS_let_known (known_value _) ?_
  refine safeS_let_known (known_typedSlice (known_local (local?_bindLocal_self inv 97 _)) (known_value _)
    (map_zero kind hw pos)) ?_
  have inv2 := inv1.bindLocal 123 (.rawSlice t.toCore 0 (Int.toNat 0))
  refine safeS_let_known (known_stride (known_local (local?_bindLocal_self inv1 123 _)) (stride_word kind hw)) ?_
  have inv3 := inv2.bindLocal 178 (.signed .isize (-((8 * w : Nat) : Int)))
  have known := local?_bindLocal_self inv2 178 (.signed .isize (-((8 * w : Nat) : Int)))
  have one3 := local?_bindLocal_other (id := 178) (by decide) (.signed .isize (-((8 * w : Nat) : Int)))
    (local?_bindLocal_other (id := 123) (by decide) (.rawSlice t.toCore 0 (Int.toNat 0))
      (local?_bindLocal_other (id := 97) (by decide) (.pointer 0) one))
  have storage3 := local?_bindLocal_other (id := 178) (by decide) (.signed .isize (-((8 * w : Nat) : Int)))
    (local?_bindLocal_other (id := 123) (by decide) (.rawSlice t.toCore 0 (Int.toNat 0))
      (local?_bindLocal_other (id := 97) (by decide) (.pointer 0) storage))
  have zero : ∀ {s : State}, Known sp.toCore s (.cast (.signed .isize) (.value (.signed .i32 0))) (.signed .isize 0) :=
    known_cast (known_value _) (by rw [toCore_target']; exact cast_isize (by decide) (by decide) _)
  -- the branch for forward strides and empty views, not taken
  have left := known_binary (P := sp.toCore) (op := .greaterEqual) (by decide) (by decide) (known_local known) zero
    (by rw [toCore_target', signed_greaterEqual])
  have right := known_binary (P := sp.toCore) (op := .equal) (by decide) (by decide) (known_local one3)
    (known_value (.signed .i32 0)) (by rw [toCore_target', signed_equal])
  have cond := known_or left right
  have no : (decide (-((8 * w : Nat) : Int) ≥ 0) || ((1 : Int) == 0)) = false := by
    simp only [Bool.or_eq_false_iff, decide_eq_false_iff_not]
    exact ⟨by omega, rfl⟩
  rw [no] at cond
  refine safeS_seq (safeS_if_known cond safeS_skip) fun h => ?_
  obtain ⟨j, -, h⟩ := if_known_done cond h
  obtain ⟨-, rfl⟩ := skip_inv h
  -- the last word's offset
  have back := known_binary (P := sp.toCore) (op := .subtract) (by decide) (by decide) zero (known_local known)
    (by rw [toCore_target', signed_subtract])
  rw [Int.sub_neg, Int.zero_add, wrap_isize_of (by omega) (by omega)] at back
  have size := known_cast (P := sp.toCore) (ty := .unsigned .usize) (v := .unsigned .usize (8 * w)) back
    (by rw [toCore_target']; exact cast_usize_nat (by omega) _)
  have count := known_cast (P := sp.toCore) (ty := .unsigned .usize) (v := .unsigned .usize 1) (known_local one3)
    (by rw [toCore_target']; exact cast_usize_nat (n := 1) (by decide) _)
  have bytes := known_binary (P := sp.toCore) (op := .multiply) (by decide) (by decide) size count
    (by rw [toCore_target', unsigned_multiply])
  have offset := known_binary (P := sp.toCore) (op := .subtract) (by decide) (by decide) bytes
    (known_value (.unsigned .usize 8)) (by rw [toCore_target', unsigned_subtract])
  have eq : ((8 * w * 1 % 2 ^ 64 + 2 ^ 64 - 8 % 2 ^ 64) % 2 ^ 64) = 8 * w - 8 := by omega
  rw [eq] at offset
  refine safeS_let_known offset ?_
  have inv4 := inv3.bindLocal 321 (.unsigned .usize (8 * w - 8))
  -- the view of the storage
  have address := known_binary (P := sp.toCore) (op := .add) (by decide) (by decide)
    (known_local (local?_bindLocal_other (id := 321) (by decide) (.unsigned .usize (8 * w - 8)) storage3))
    (known_local (local?_bindLocal_self inv3 321 _)) (by rw [toCore_target', pointer_add])
  rw [show (a + (8 * w - 8)) % 2 ^ 64 = a + 8 * w - 8 by rw [Nat.mod_eq_of_lt (by omega)]; omega] at address
  refine safeS_let_known (known_typedSlice address
    (known_local (local?_bindLocal_other (id := 321) (by decide) (.unsigned .usize (8 * w - 8)) one3)) (map_one kind hw pos room range)) ?_
  exact safeS_return (known_local (local?_bindLocal_self inv4 394 _)).safeE

theorem panic_safe : SafeS sp.toCore st panicFunc.body.toCore := by
  simp only [panicFunc, SrcStmt.toCore, SrcEff.toCore, SrcExpr.toCore]
  exact safeS_expression (safeE_assert (known_value _).safeE fun h => ⟨false, (value_inv h).1⟩)

/-! ## Calls of the helpers -/

theorem sizeOf_call_safe {t : SrcType} {callee : Nat} (found : sp.funcs[callee]? = some (sizeOfFunc t))
    (el : wordElement sp.decls t = true) {w : Nat} (hw : NativeLayout.valueWords? sp.toCore t.toCore = some w)
    (pos : 0 < w) (inv : Inv st) : SafeE sp.toCore st (.call callee []) :=
  safeE_call found safeEs_nil fun {k values s} h => by
    obtain ⟨rfl, hs⟩ := exprs_nil_inv h
    subst s
    exact ⟨rfl, sizeOf_safe el hw pos (Same.start inv _)⟩

theorem panic_call_safe {callee : Nat} (found : sp.funcs[callee]? = some panicFunc) :
    SafeE sp.toCore st (.call callee []) :=
  safeE_call found safeEs_nil fun {k values s} h => by
    obtain ⟨rfl, hs⟩ := exprs_nil_inv h
    subst s
    exact ⟨rfl, panic_safe⟩

theorem slice_call_safe {t : SrcType} {callee : Nat} {p : Core.Expr} {a w : Nat}
    (found : sp.funcs[callee]? = some (sliceFunc t)) (el : wordElement sp.decls t = true)
    (hw : NativeLayout.valueWords? sp.toCore t.toCore = some w) (pos : 0 < w) (inv : Inv st)
    (storage : Known sp.toCore st p (.pointer a)) (room : st.heap.nextAddress ≤ 2 ^ 64 → a + 8 * w ≤ 2 ^ 64)
    (range : st.heap.checkRange a (8 * w) 8 = .ok ()) :
    SafeE sp.toCore st (.call callee [p, .value (.signed .i32 1)]) := by
  have args := knowns_cons storage (knowns_cons (known_value (.signed .i32 1)) knowns_nil)
  refine safeE_call found args.safeEs fun {k values s} h => ?_
  obtain ⟨rfl, hs⟩ := args.done h
  subst s
  refine ⟨rfl, ?_⟩
  have inv1 : Inv (({ st with locals := [] } : State).bindLocal 28 (.pointer a)) := inv.clear.bindLocal _ _
  exact slice_safe el hw pos (inv1.bindLocal 42 _)
    (local?_bindLocal_other (id := 42) (by decide) _ (local?_bindLocal_self inv.clear 28 _))
    (local?_bindLocal_self inv1 42 _) room range

end

/-! ## `unbox` -/

section
variable {sp : SrcProgram} {prims : Prims}

theorem raw_read_of {P : Core.Program} {s : State} {T : Core.Ty} {a w : Nat} {v : Value}
    (kind : (∃ id, T = .structure id) ∨ ∃ id, T = .enumeration id) (words : NativeLayout.valueWords? P T = some w)
    (pos : 0 < w) (h : Semantics.readNativeValue NativeLayout.maxDepth P s.heap T (a + 8 * w - 8) = .ok v) :
    Semantics.readRawSliceIndex P s T (a + 8 * w - 8) 1 0 = .ok v := by
  simp only [Semantics.readRawSliceIndex, show ¬ (0 ≥ 1) by decide, if_false,
    elementAddress_zero kind words pos]
  exact h

theorem unbox_safe {t : SrcType} {id slice : Nat} {values ps : List Value} {st : State}
    (sliceFound : sp.funcs[slice]? = some (sliceFunc t)) (el : wordElement sp.decls t = true)
    (box : boxElem sp prims id = some t) (inv : Inv st)
    (args : VRels sp.toCore (boxElem sp prims) st.heap ((unboxFunc t id slice).params.map SrcParam.ty) values ps) :
    SafeS sp.toCore (({ st with locals := [] } : State).bindLocals (paramBindings (unboxFunc t id slice).params values))
      (unboxFunc t id slice).body.toCore := by
  obtain ⟨-, kind⟩ := sliceFrom_word el
  simp only [unboxFunc, List.map_cons, List.map_nil] at args
  cases args with
  | cons r rest =>
  cases rest with
  | nil =>
  rename_i x p
  cases r with
  | scalar s => exact s.elim
  | struct none _ => rw [box] at none; cases none
  | box found wv pos room ranged read rel =>
  rename_i t' a w y
  rw [box, Option.some.injEq] at found
  subst found
  have start : (({ st with locals := [] } : State).bindLocals (paramBindings (unboxFunc t id slice).params
      [.structure id [.pointer a]])) = ({ st with locals := [] } : State).bindLocal 9 (.structure id [.pointer a]) :=
    rfl
  rw [start]
  have inv0 := inv.clear.bindLocal 9 (.structure id [.pointer a])
  simp only [unboxFunc, SrcStmt.toCore, SrcEff.toCore, SrcExpr.toCore, SrcType.toCore,
    List.map_cons, List.map_nil, bv_zero, bv_one]
  have field := known_field (P := sp.toCore) (index := 0) (x := .pointer a)
    (local?_bindLocal_self inv.clear 9 (.structure id [.pointer a])) rfl
  refine safeS_let (slice_call_safe sliceFound el wv pos inv0 field (fun _ => room) ranged) fun {k v s} h => ?_
  obtain ⟨w', hw', -, rfl, same, -⟩ := slice_call sliceFound el inv0 field.done h
  rw [wv, Option.some.injEq] at hw'
  subst hw'
  rw [show (a + (8 * w - 8)) % 2 ^ 64 = a + 8 * w - 8 by rw [Nat.mod_eq_of_lt (by omega)]; omega]
  refine safeS_return (known_index_raw (known_local (local?_bindLocal_self same.inv 39 _))
    (known_value (.signed .i32 0)) (pos := 0) (v := y) (by simp [Semantics.integerIndex]) ?_).safeE
  refine raw_read_of kind wv pos ?_
  have heap : (s.bindLocal 39 (.rawSlice t.toCore (a + 8 * w - 8) 1)).heap = st.heap := same.heap
  rw [heap]
  exact read

end

/-! ## `boxed` -/

section
variable {sp : SrcProgram} {prims : Prims}

theorem boxed_safe {t : SrcType} {id sizeOf slice panic : Nat} {values ps : List Value} {st : State}
    (sizeOfFound : sp.funcs[sizeOf]? = some (sizeOfFunc t)) (sliceFound : sp.funcs[slice]? = some (sliceFunc t))
    (panicFound : sp.funcs[panic]? = some panicFunc) (el : wordElement sp.decls t = true)
    (laid : (NativeLayout.valueWords? (declsCore sp.decls) t.toCore).isSome = true) (inv : Inv st)
    (args : VRels sp.toCore (boxElem sp prims) st.heap
      ((boxedFunc t id sizeOf slice panic).params.map SrcParam.ty) values ps) :
    SafeS sp.toCore (({ st with locals := [] } : State).bindLocals
      (paramBindings (boxedFunc t id sizeOf slice panic).params values))
      (boxedFunc t id sizeOf slice panic).body.toCore := by
  obtain ⟨-, kind⟩ := sliceFrom_word el
  rw [← valueWords_toCore] at laid
  obtain ⟨w, hw⟩ := Option.isSome_iff_exists.1 laid
  have pos := valueWords_pos kind hw
  have most := valueWords_le kind hw
  simp only [NativeLayout.maxWords] at most
  simp only [boxedFunc, List.map_cons, List.map_nil] at args
  cases args with
  | cons rx rest =>
  cases rest with
  | nil =>
  rename_i x p
  have start : (({ st with locals := [] } : State).bindLocals (paramBindings (boxedFunc t id sizeOf slice panic).params
      [x])) = ({ st with locals := [] } : State).bindLocal 9 x := rfl
  rw [start]
  have inv0 := inv.clear.bindLocal 9 x
  have x0 := local?_bindLocal_self inv.clear 9 x
  have heap0 : (({ st with locals := [] } : State).bindLocal 9 x).heap = st.heap := rfl
  generalize ({ st with locals := [] } : State).bindLocal 9 x = s0 at inv0 x0 heap0 ⊢
  simp only [boxedFunc, SrcStmt.toCore, SrcEff.toCore, SrcEff.toCoreList, SrcExpr.toCore, SrcType.toCore, SrcOp.toCore,
    SrcType.typeId, List.map_cons, List.map_nil, bv_zero, bv_one, Nat.reducePow]
  -- the storage's size
  refine safeS_let (sizeOf_call_safe sizeOfFound el hw pos inv0) fun {k v s1} call1 => ?_
  obtain ⟨w', hw', -, -, rfl, same1, locals1⟩ := sizeOf_call sizeOfFound el inv0 call1
  rw [hw, Option.some.injEq] at hw'
  subst hw'
  have inv1 := same1.inv.bindLocal 39 (.unsigned .usize (8 * w))
  have x1 := local?_bindLocal_other (id := 39) (by decide) (.unsigned .usize (8 * w)) (local?_step same1.step locals1 x0)
  have n1 := local?_bindLocal_self same1.inv 39 (.unsigned .usize (8 * w))
  generalize s1.bindLocal 39 (.unsigned .usize (8 * w)) = q1 at inv1 x1 n1 ⊢
  -- the allocation
  refine safeS_let (fun _ _ _ h _ => (alloc_trap (known_local n1) (known_value (.unsigned .usize 8)) (by decide) h).elim)
    fun {k v s2} e2 => ?_
  obtain ⟨_, n, s5, al, s6, -, sz, alr, alloc⟩ := alloc_inv e2
  obtain ⟨hn, hs5⟩ := local_eval n1 sz
  subst s5
  obtain ⟨hal, hs6⟩ := value_inv alr
  subst s6
  simp only [Value.unsigned.injEq, true_and] at hn hal
  subst hn hal
  rcases alloc with ⟨a0, H1, allocated, rfl, rfl⟩ | ⟨H1, exhausted, rfl, rfl⟩
  case inr =>
    have same := allocate_exhausted' exhausted
    subst same
    have cond := known_binary (P := sp.toCore) (op := .equal) (by decide) (by decide)
      (known_local (local?_bindLocal_self (st := { q1 with heap := q1.heap }) inv1 86 (.pointer 0)))
      (known_value (.pointer 0)) (by rw [toCore_target', pointer_equal])
    simp only [show ((0 : Nat) == 0) = true from rfl] at cond
    refine safeS_seq (safeS_if_known cond ?_) fun h => ?_
    · simp only [if_true]
      exact safeS_expression (panic_call_safe panicFound)
    · obtain ⟨j, -, h⟩ := if_known_done cond h
      simp only [if_true] at h
      obtain ⟨_, u, -, panicRun, -⟩ := expression_inv h
      exact (panic_call panicFound panicRun).elim
  obtain ⟨a, ha0⟩ : ∃ a : Nat, a = a0 := ⟨a0, rfl⟩
  subst ha0
  obtain ⟨ha, budget, hH⟩ := allocate_allocated allocated
  have apos : 0 < a := by rw [ha]; exact Memory.Heap.allocationAddress_pos _ (by decide)
  have next1 : H1.nextAddress = a + max (8 * w) 1 := by rw [hH, ha]; rfl
  have below1 : Memory.HeapBlocksBelowNext H1 := by
    rw [hH]; exact Memory.Heap.allocatedBytes_below inv1.below (by decide)
  have unique1 : Memory.HeapBlockBasesUnique H1 := by
    rw [hH]; exact Memory.Heap.allocatedBytes_unique inv1.below inv1.unique (by decide)
  have zeros : ∀ i, i < 8 * w → H1.loadByte a i = .ok 0 := by
    rw [hH, ha]
    exact fun i lt => Memory.Heap.allocatedBytes_read inv1.below (by decide) lt
  have range1 : H1.checkRange a (8 * w) 8 = .ok () := by
    rw [hH, ha]; exact allocated_checkRange inv1.below (by omega) (by decide)
  have inv2 : Inv { q1 with heap := H1 } := ⟨inv1.views, inv1.fresh, below1, unique1⟩
  have inv3 := inv2.bindLocal 86 (.pointer a)
  have ptr := local?_bindLocal_self inv2 86 (.pointer a)
  have x3 := local?_bindLocal_other (id := 86) (by decide) (.pointer a)
    (show ({ q1 with heap := H1 } : State).local? 9 = some x from x1)
  -- the rest runs past the allocation, so its cursor bounds the storage's end
  refine SafeS.of_bound (s := .then (.if (.apply .equal (.local 86) .null) (.discard (.eCall panic [])) .nop)
    (.letCall 203 (.slice t) slice [.local 86, .int 1] (.then (.setIndex 203 (.int 0) (.local 9))
      (.returnEval (.eStruct (.struct id [.ptr]) [.ePure (.local 86)]))))) inv3 fun bound => ?_
  have room : a + 8 * w ≤ 2 ^ 64 := by
    have : H1.nextAddress ≤ 2 ^ 64 := bound
    rw [next1] at this
    exact Nat.le_trans (Nat.add_le_add_left (Nat.le_max_left _ _) a) this
  simp only [SrcStmt.toCore, SrcEff.toCore, SrcEff.toCoreList, SrcExpr.toCore, SrcType.toCore, SrcOp.toCore,
    SrcType.typeId, List.map_cons, List.map_nil, bv_zero, bv_one]
  -- the null check
  have cond := known_binary (P := sp.toCore) (op := .equal) (by decide) (by decide) (known_local ptr)
    (known_value (.pointer 0)) (by rw [toCore_target', pointer_equal])
  have nonNull : (a == 0) = false := by simp only [beq_eq_false_iff_ne, ne_eq]; omega
  rw [nonNull] at cond
  refine safeS_seq (safeS_if_known cond safeS_skip) fun {k s} h => ?_
  obtain ⟨j, -, h⟩ := if_known_done cond h
  obtain ⟨-, hs⟩ := skip_inv h
  subst s
  -- the view
  refine safeS_let (slice_call_safe sliceFound el hw pos inv3 (known_local ptr) (fun _ => room) range1)
    fun {k v s10} call3 => ?_
  obtain ⟨w', hw', -, rfl, same3, locals3⟩ := slice_call sliceFound el inv3 (fun h => local_eval ptr h) call3
  rw [hw, Option.some.injEq] at hw'
  subst hw'
  rw [show (a + (8 * w - 8)) % 2 ^ 64 = a + 8 * w - 8 by rw [Nat.mod_eq_of_lt (by omega)]; omega]
  have inv4 := same3.inv.bindLocal 203 (.rawSlice t.toCore (a + 8 * w - 8) 1)
  have view4 := local?_bindLocal_self same3.inv 203 (.rawSlice t.toCore (a + 8 * w - 8) 1)
  have x4 := local?_bindLocal_other (id := 203) (by decide) (.rawSlice t.toCore (a + 8 * w - 8) 1)
    (local?_step same3.step locals3 x3)
  have ptr4 := local?_bindLocal_other (id := 203) (by decide) (.rawSlice t.toCore (a + 8 * w - 8) 1)
    (local?_step same3.step locals3 ptr)
  have heap4 : (s10.bindLocal 203 (.rawSlice t.toCore (a + 8 * w - 8) 1)).heap = H1 := same3.heap
  -- the write: the value's store fits in the storage
  refine safeS_seq (safeS_expression fun k r s h bound => ?_) fun {k s} h => ?_
  · obtain ⟨rfl, write⟩ := set_raw_trap (P := sp.toCore) (pos := 0) inv4.views view4 x4
      (by simp [Semantics.integerIndex]) (by decide) (elementAddress_zero kind hw pos) h
    have spec : Semantics.NativeStoreSpec NativeLayout.maxDepth sp.toCore t.toCore x (8 * w) :=
      store_spec NativeLayout.maxDepth rx (wordElement_wordType el) hw (Nat.le_refl _)
    have readable : (s10.bindLocal 203 (.rawSlice t.toCore (a + 8 * w - 8) 1)).heap.Readable
        (a + 8 * w - 8 + 8 - 8 * w) (8 * w) := by
      rw [heap4, show a + 8 * w - 8 + 8 - 8 * w = a by omega]
      exact fun i lt => ⟨0, zeros i lt⟩
    obtain ⟨after, ok, -, -⟩ := spec _ _ (a + 8 * w - 8) (by omega) readable (heap4 ▸ unique1)
    rw [ok] at write
    cases write
  · -- the returned box
    obtain ⟨_, u, -, asg, -⟩ := expression_inv h
    obtain ⟨_, rp, s13, rv, s14, s15, -, placeRun, valueRun, written, synced⟩ := assign_inv asg
    obtain ⟨_, rb, s16, -, baseRun, idx⟩ := place_index_inv placeRun
    obtain ⟨hrb, rfl⟩ := place_local_read view4 baseRun
    obtain ⟨iv, posn, base, ir, hi, -, hb, raw⟩ := idx _ _ _ hrb
    obtain ⟨rfl, rfl⟩ := value_inv ir
    obtain ⟨rfl, rfl⟩ := local_eval x4 valueRun
    simp only [Semantics.writeResolvedPlaceNative, raw] at written
    obtain ⟨H2, -, wrapped⟩ := except_bind_ok written
    simp only [pure, Except.pure, Except.ok.injEq] at wrapped
    subst wrapped
    simp only [Semantics.ResolvedPlace.viewFreeRootWrite, raw, Option.isNone_some, Bool.false_and,
      Bool.false_eq_true, if_false, syncFrom_ok (st := { (s10.bindLocal 203 _) with heap := H2 }) inv4.views,
      Except.ok.injEq] at synced
    subst synced
    exact safeS_return (known_struct (knowns_cons (known_local (show ({ (s10.bindLocal 203
      (.rawSlice t.toCore (a + 8 * w - 8) 1)) with heap := H2 } : State).local? 86 = some (.pointer a) from ptr4))
      knowns_nil)).safeE

end

end Lanius.Faithful
