import Lanius.Faithful.Sim.Unbox

/-! # Core runs of `boxed<T>(value)`

`boxed` allocates `size_of<T>()` bytes (a null pointer would `panic`, which
never completes), writes the value as element 0 of the storage's one-element
view, and returns the box of the storage: a box the value's pure meaning
means, in a heap that keeps every earlier read. -/

namespace Lanius.Faithful

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (State Completion evalExpr evalExprs execStmt restoreLocals readNativeValue HeapReads
  NativeStoreSpec)
open Lanius.Memory (HeapBlocksBelowNext HeapBlockBasesUnique)

theorem pointer_equal (a b : Nat) :
    Semantics.evalBinaryValue .x86_64 .equal (.pointer a) (.pointer b) = .ok (.boolean (a == b)) := by
  simp [Semantics.evalBinaryValue, Semantics.scalarEqual]

section
variable {sp : SrcProgram} {prims : Prims} {m : Nat}

/-- A run of `boxed<t>` on a value: a box that means the value's meaning. -/
theorem boxed_sim {c : Nat} {t : SrcType} {id sizeOf slice panic : Nat} {values ps : List Value}
    {st completed : State} {compl : Completion} {v : Value}
    (sizeOfFound : sp.funcs[sizeOf]? = some (sizeOfFunc t)) (sliceFound : sp.funcs[slice]? = some (sliceFunc t))
    (panicFound : sp.funcs[panic]? = some panicFunc) (el : wordElement sp.decls t = true)
    (box : boxElem sp prims id = some t) (prim : prims.isPrim c = true) (inv : Inv st)
    (bound : completed.heap.nextAddress ≤ 2 ^ 64)
    (args : VRels sp.toCore (boxElem sp prims) st.heap
      ((boxedFunc t id sizeOf slice panic).params.map SrcParam.ty) values ps)
    (run : execStmt m sp.toCore (({ st with locals := [] } : State).bindLocals
      (paramBindings (boxedFunc t id sizeOf slice panic).params values))
      (boxedFunc t id sizeOf slice panic).body.toCore = .done compl completed)
    (result : CallResult (boxedFunc t id sizeOf slice panic).ret compl v) :
    ∃ w, pcall sp prims (m + 1) c ps = some w ∧
      VRel sp.toCore (boxElem sp prims) completed.heap (.struct id [.ptr]) v w ∧ Inv completed ∧ Step st completed := by
  obtain ⟨-, kind⟩ := sliceFrom_word el
  simp only [boxedFunc, List.map_cons, List.map_nil] at args
  cases args with
  | cons r rest =>
  cases rest with
  | nil =>
  rename_i x p
  have pc : pcall sp prims (m + 1) c [p] = some p := by simp only [pcall, prim, if_true, single]
  refine ⟨p, pc, ?_⟩
  have start : (({ st with locals := [] } : State).bindLocals (paramBindings (boxedFunc t id sizeOf slice panic).params
      [x])) = ({ st with locals := [] } : State).bindLocal 9 x := rfl
  rw [start] at run
  have inv0 := inv.clear.bindLocal 9 x
  have x0 := local?_bindLocal_self inv.clear 9 x
  have step0 : Step st (({ st with locals := [] } : State).bindLocal 9 x) :=
    (Step.clear st).trans (Step.bindLocal _ 9 x)
  have heap0 : (({ st with locals := [] } : State).bindLocal 9 x).heap = st.heap := rfl
  generalize hs0 : ({ st with locals := [] } : State).bindLocal 9 x = s0 at run inv0 x0 step0 heap0
  simp only [boxedFunc, SrcStmt.toCore, SrcEff.toCore, SrcEff.toCoreList, SrcExpr.toCore, SrcType.toCore, SrcOp.toCore,
    SrcType.typeId, List.map_cons, List.map_nil, bv_zero, bv_one, Nat.reducePow] at run
  -- the storage's size
  obtain ⟨_, v1, s1, s2, -, call1, b1, rfl⟩ := letLocal_inv run
  obtain ⟨w, hw, pos, most, rfl, same1, locals1⟩ := sizeOf_call sizeOfFound el inv0 call1
  simp only [NativeLayout.maxWords] at most
  have inv1 := same1.inv.bindLocal 39 (.unsigned .usize (8 * w))
  have x1 := local?_bindLocal_other (id := 39) (by decide) (.unsigned .usize (8 * w)) (local?_step same1.step locals1 x0)
  have n1 := local?_bindLocal_self same1.inv 39 (.unsigned .usize (8 * w))
  have heap1 : (s1.bindLocal 39 (.unsigned .usize (8 * w))).heap = st.heap := same1.heap.trans heap0
  have step1 : Step st (s1.bindLocal 39 (.unsigned .usize (8 * w))) :=
    step0.trans (same1.step.trans (Step.bindLocal _ _ _))
  generalize hq1 : s1.bindLocal 39 (.unsigned .usize (8 * w)) = q1 at b1 inv1 x1 n1 heap1 step1
  -- the allocation
  obtain ⟨_, v2, s3, s4, -, e2, b2, rfl⟩ := letLocal_inv b1
  obtain ⟨_, n, s5, al, s6, -, sz, alr, alloc⟩ := alloc_inv e2
  obtain ⟨hn, hs5⟩ := local_eval n1 sz
  subst s5
  obtain ⟨hal, hs6⟩ := value_inv alr
  subst s6
  simp only [Value.unsigned.injEq, true_and] at hn hal
  subst hn hal
  rcases alloc with ⟨a0, H1, allocated, rfl, rfl⟩ | ⟨H1, exhausted, rfl, rfl⟩
  case inr =>
    exfalso
    have same := allocate_exhausted' exhausted
    subst same
    obtain ⟨_, s7, c7, -, first, -⟩ := sequence_inv b2
    obtain ⟨_, s8, x8, -, cond, branch⟩ := if_inv first
    obtain ⟨_, l, s9, r, -, lr, rr, op⟩ := binary_inv (by decide) (by decide) cond
    obtain ⟨rfl, rfl⟩ := local_eval (local?_bindLocal_self (st := { q1 with heap := q1.heap }) inv1 86 _) lr
    obtain ⟨rfl, rfl⟩ := value_inv rr
    rw [toCore_target', pointer_equal, Except.ok.injEq, Value.boolean.injEq] at op
    subst op
    simp only [show ((0 : Nat) == 0) = true from rfl, if_true] at branch
    obtain ⟨_, u, -, panicRun, -⟩ := expression_inv branch
    exact panic_call panicFound panicRun
  obtain ⟨a, ha0⟩ : ∃ a : Nat, a = a0 := ⟨a0, rfl⟩
  subst ha0
  obtain ⟨ha, budget, hH⟩ := allocate_allocated allocated
  have apos : 0 < a := by rw [ha]; exact Memory.Heap.allocationAddress_pos _ (by decide)
  have age : q1.heap.nextAddress ≤ a := by rw [ha]; exact Memory.Heap.allocationAddress_ge _ (by decide)
  have zeros : ∀ i, i < 8 * w → H1.loadByte a i = .ok 0 := by
    rw [hH, ha]
    exact fun i lt => Memory.Heap.allocatedBytes_read inv1.below (by decide) lt
  have oldReads : HeapReads q1.heap H1 := by
    rw [hH]
    exact fun _ _ _ read => Memory.Heap.allocatedBytes_oldRead read
  have next1 : H1.nextAddress = a + max (8 * w) 1 := by rw [hH, ha]; rfl
  have below1 : HeapBlocksBelowNext H1 := by rw [hH]; exact Memory.Heap.allocatedBytes_below inv1.below (by decide)
  have unique1 : HeapBlockBasesUnique H1 := by
    rw [hH]; exact Memory.Heap.allocatedBytes_unique inv1.below inv1.unique (by decide)
  have inv2 : Inv { q1 with heap := H1 } := ⟨inv1.views, inv1.fresh, below1, unique1⟩
  have inv3 := inv2.bindLocal 86 (.pointer a)
  have ptr := local?_bindLocal_self inv2 86 (.pointer a)
  have x3 := local?_bindLocal_other (id := 86) (by decide) (.pointer a)
    (show ({ q1 with heap := H1 } : State).local? 9 = some x from x1)
  -- the null check
  obtain ⟨_, s7, c7, -, first, rest⟩ := sequence_inv b2
  obtain ⟨_, s8, x8, -, cond, branch⟩ := if_inv first
  obtain ⟨_, l, s9, r, -, lr, rr, op⟩ := binary_inv (by decide) (by decide) cond
  obtain ⟨rfl, rfl⟩ := local_eval ptr lr
  obtain ⟨rfl, rfl⟩ := value_inv rr
  rw [toCore_target', pointer_equal, Except.ok.injEq, Value.boolean.injEq] at op
  have nonNull : (a == 0) = false := by simp only [beq_eq_false_iff_ne, ne_eq]; omega
  rw [nonNull] at op
  subst op
  simp only [Bool.false_eq_true, if_false] at branch
  obtain ⟨rfl, rfl⟩ := skip_inv branch
  replace rest := (rest.resolve_right fun h => h.1 rfl).2
  -- the view
  obtain ⟨_, v3, s10, s11, -, call3, b3, rfl⟩ := letLocal_inv rest
  obtain ⟨w', hw', -, rfl, same3, locals3⟩ := slice_call sliceFound el inv3 (fun h => local_eval ptr h) call3
  rw [hw, Option.some.injEq] at hw'
  subst hw'
  have inv4 := same3.inv.bindLocal 203 (.rawSlice t.toCore ((a + (8 * w - 8)) % 2 ^ 64) 1)
  have view4 := local?_bindLocal_self same3.inv 203 (.rawSlice t.toCore ((a + (8 * w - 8)) % 2 ^ 64) 1)
  have x4 := local?_bindLocal_other (id := 203) (by decide) (.rawSlice t.toCore ((a + (8 * w - 8)) % 2 ^ 64) 1)
    (local?_step same3.step locals3 x3)
  have ptr4 := local?_bindLocal_other (id := 203) (by decide) (.rawSlice t.toCore ((a + (8 * w - 8)) % 2 ^ 64) 1)
    (local?_step same3.step locals3 ptr)
  have heap4 : (s10.bindLocal 203 (.rawSlice t.toCore ((a + (8 * w - 8)) % 2 ^ 64) 1)).heap = H1 := same3.heap
  -- the write
  obtain ⟨_, s12, c12, -, first4, rest4⟩ := sequence_inv b3
  obtain ⟨_, u, -, asg, rfl⟩ := expression_inv first4
  replace rest4 := (rest4.resolve_right fun h => h.1 rfl).2
  obtain ⟨_, rp, s13, rv, s14, s15, -, placeRun, valueRun, written, synced⟩ := assign_inv asg
  obtain ⟨_, rb, s16, -, baseRun, idx⟩ := place_index_inv placeRun
  obtain ⟨hrb, rfl⟩ := place_local_read view4 baseRun
  obtain ⟨iv, posn, base, ir, hi, -, hb, raw⟩ := idx _ _ _ hrb
  obtain ⟨rfl, rfl⟩ := value_inv ir
  simp only [Semantics.integerIndex, show ¬ ((0 : Int) < 0) by decide, if_false, Except.ok.injEq,
    show Int.toNat 0 = 0 from rfl] at hi
  subst hi
  obtain ⟨hrv, hs14⟩ := local_eval x4 valueRun
  subst rv s14
  simp only [Semantics.writeResolvedPlaceNative, raw] at written
  obtain ⟨H2, stored, wrapped⟩ := except_bind_ok written
  simp only [pure, Except.pure, Except.ok.injEq] at wrapped
  subst wrapped
  simp only [Semantics.ResolvedPlace.viewFreeRootWrite, raw, Option.isNone_some, Bool.false_and,
    Bool.false_eq_true, if_false, syncFrom_ok (st := { (s10.bindLocal 203 _) with heap := H2 }) inv4.views,
    Except.ok.injEq] at synced
  subst synced
  -- the returned box
  obtain ⟨_, rv', -, sv, rfl⟩ := return_inv rest4
  obtain ⟨_, vs, -, es, rfl⟩ := structValue_inv sv
  obtain ⟨_, u1, s17, rest5, -, e17, es2, rfl⟩ := exprs_cons_inv es
  obtain ⟨rfl, rfl⟩ := local_eval (show ({ (s10.bindLocal 203 (.rawSlice t.toCore ((a + (8 * w - 8)) % 2 ^ 64) 1))
    with heap := H2 } : State).local? 86 = some (.pointer a) from ptr4) e17
  obtain ⟨rfl, rfl⟩ := exprs_nil_inv es2
  simp only [CallResult] at result
  subst result
  -- the box's storage fits below the cursor
  have next2 : H2.nextAddress = H1.nextAddress := (writeNativeValue_next _ stored).trans (congrArg _ heap4)
  have room : a + 8 * w ≤ 2 ^ 64 := by
    have h2 : H2.nextAddress ≤ 2 ^ 64 := bound
    rw [next2, next1] at h2
    exact Nat.le_trans (Nat.add_le_add_left (Nat.le_max_left _ _) a) h2
  rw [show (a + (8 * w - 8)) % 2 ^ 64 = a + 8 * w - 8 by rw [Nat.mod_eq_of_lt (by omega)]; omega,
    elementAddress_zero kind hw pos, Except.ok.injEq] at hb
  subst hb
  -- the value's store
  have spec : NativeStoreSpec NativeLayout.maxDepth sp.toCore t.toCore x (8 * w) :=
    store_spec NativeLayout.maxDepth r (wordElement_wordType el) hw (Nat.le_refl _)
  have readable : (s10.bindLocal 203 (.rawSlice t.toCore ((a + (8 * w - 8)) % 2 ^ 64) 1)).heap.Readable
      (a + 8 * w - 8 + 8 - 8 * w) (8 * w) := by
    rw [heap4, show a + 8 * w - 8 + 8 - 8 * w = a by omega]
    exact fun i lt => ⟨0, zeros i lt⟩
  obtain ⟨after, write, snap, region⟩ := spec _ _ (a + 8 * w - 8) (by omega) readable (heap4 ▸ unique1)
  rw [stored, Except.ok.injEq] at write
  subst write
  rw [heap4, show a + 8 * w - 8 + 8 - 8 * w = a by omega] at region
  have reads : HeapReads st.heap H2 := heap1 ▸ oldReads.writeRegionFresh inv1.below age region
  have inv5 : Inv { (s10.bindLocal 203 (.rawSlice t.toCore ((a + (8 * w - 8)) % 2 ^ 64) 1)) with heap := H2 } :=
    ⟨inv4.views, inv4.fresh, region.below below1, region.unique⟩
  refine ⟨?_, ((inv5.restore _).restore _).restore _, ⟨?_, reads⟩⟩
  · exact .box box hw pos room snap.read (VRel.mono reads r)
  · exact step1.cells.trans ((Step.bindLocal { q1 with heap := H1 } 86 _).cells.trans
      (same3.step.cells.trans (Step.bindLocal s10 203 _).cells))

end

end Lanius.Faithful
