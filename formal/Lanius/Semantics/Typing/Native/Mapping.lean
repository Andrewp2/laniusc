import Lanius.Semantics.Typing.Native.Coherence
import Lanius.Semantics.Typing.Slice
import Lanius.Semantics.Typing.Assignment
import Lanius.Semantics.NativeReadFrame

namespace Lanius.Semantics

open Lanius Lanius.Core Lanius.Typing Lanius.Memory

/-- Storage ready for pointer exposure and host refresh. This does not assert
    exclusive ownership, region separation, or validity of raw/temporary views. -/
structure State.I32ViewsReady (state : State) (program : Program) (types : CellTypes) : Prop
    extends state.I32ViewsAccessible program types where
  below : HeapBlocksBelowNext state.heap
  keys : state.I32ViewsUnique

/-- Fresh cells and storage preserve existing declarations and native targets.
    New cells need their own declarations; this retains the caller's map. -/
theorem State.I32ViewsReady.retained {before after : State}
    (ready : before.I32ViewsReady program types) (cells : FreshCellFrame before after)
    (reads : HeapReads before.heap after.heap) (unique : HeapBlockBasesUnique after.heap)
    (below : HeapBlocksBelowNext after.heap) (views : after.i32ArrayViews = before.i32ArrayViews) :
    after.I32ViewsReady program types := by
  refine ⟨⟨ready.store.retained cells, unique, ?_⟩, below, ?_⟩
  · intro view member
    obtain ⟨target, readable⟩ := ready.views view (by simpa only [views] using member)
    exact ⟨target.retained cells, reads.readable readable⟩
  · simpa only [State.I32ViewsUnique, views] using ready.keys

theorem State.I32ViewsReady.cellEffect {before after : State}
    (ready : before.I32ViewsReady program types) (effect : CellEffect before after cell updated)
    (declared : types cell = some type) (typed : ValueHasType program updated type) :
    after.I32ViewsReady program types :=
  ⟨ready.toI32ViewsAccessible.cellEffect effect declared typed,
    by simpa only [effect.heap] using ready.below,
    by simpa only [State.I32ViewsUnique, effect.views] using ready.keys⟩

def State.i32ArrayAddress (state : State) (cell : CellId) (path : List ValueProjection) : Address :=
  ((state.i32ArrayView? cell path).map I32ArrayView.address).getD state.heap.borrowedAddress

/-- The actual first-registration branch, for any typed nested array target.
    The exact post-state retains all cells and aliases; no mapping is assumed. -/
theorem CellTargetValid.mapFresh
    (target : CellTargetValid program types state cell path (.array (.scalar (.signed .i32)) count))
    (read : readCellProjection state cell path = .ok (.array elements))
    (access : state.I32ViewsAccessible program types) (below : HeapBlocksBelowNext state.heap)
    (missing : state.i32ArrayView? cell path = none) :
    ∃ bytes, let view : I32ArrayView := { address := state.heap.borrowedAddress, root := cell, projections := path, length := count }
      let after : State := { state with heap := state.heap.borrowedI32 bytes, i32ArrayViews := state.i32ArrayViews ++ [view] }
      mapI32ArrayView state cell path elements = .done (.pointer state.heap.borrowedAddress) after ∧
      after.I32ViewsAccessible program types ∧ after.heap.Readable view.address (count * 4) ∧
      HeapBlocksBelowNext after.heap ∧
      (state.I32ViewsCoherent program types → after.I32ViewsCoherent program types) ∧
      (state.I32ViewsUnique → after.I32ViewsUnique) := by
  obtain ⟨value, actualRead, typed⟩ := target.read access.store
  have same : value = .array elements := Except.ok.inj (actualRead.symm.trans read)
  subst value
  cases typed with
  | array elements element length elementsTyped =>
    obtain ⟨bytes, encoded, width⟩ := encodeI32Array_typed elementsTyped
    let view : I32ArrayView := { address := state.heap.borrowedAddress, root := cell, projections := path, length := count }
    let after : State := { state with heap := state.heap.borrowedI32 bytes, i32ArrayViews := state.i32ArrayViews ++ [view] }
    have readable : after.heap.Readable view.address (count * 4) := by
      simpa only [view, after, Heap.appendI32, Heap.borrowedI32, ← width] using
        (Heap.appendI32_readable (bytes := bytes) (owned := false) (budget := state.heap.remaining) below)
    have accessible : after.I32ViewsAccessible program types := by
      refine ⟨access.store, Heap.borrowedI32_unique below access.unique, ?_⟩
      intro other member
      rcases List.mem_append.mp member with old | fresh
      · obtain ⟨oldTarget, oldReadable⟩ := access.views other old
        exact ⟨oldTarget, Heap.appendI32_oldReadable oldReadable⟩
      · have same : other = view := List.mem_singleton.mp fresh
        subst other
        exact ⟨target, readable⟩
    refine ⟨bytes, ?_, accessible, readable,
      Heap.appendI32_below (bytes := bytes) (owned := false) (budget := state.heap.remaining) below, ?_, ?_⟩
    · simp only [mapI32ArrayView, missing, encoded, Heap.mapBorrowed_i32, length]
    · intro coherent
      refine ⟨accessible, ?_⟩
      intro other member
      rcases List.mem_append.mp member with old | fresh
      · obtain ⟨values, data, oldRead, enc, loaded⟩ := coherent.bytes other old
        exact ⟨values, data, oldRead, enc, Heap.appendI32_oldLoad loaded⟩
      · have same : other = view := List.mem_singleton.mp fresh
        subst other
        refine ⟨elements, bytes, read, encoded, ?_⟩
        have loaded := Heap.borrowedI32_loadBytes below bytes bytes.length
        simp only [List.take_length] at loaded
        simpa only [after, view, width] using loaded
    · intro unique
      simp only [State.I32ViewsUnique, List.map_append, List.map_cons, List.map_nil]
      rw [List.nodup_append]
      refine ⟨unique, by simp, ?_⟩
      intro key member new fresh same
      have equal : new = (cell, path) := List.mem_singleton.mp fresh
      subst new; subst key
      obtain ⟨old, member, equal⟩ := List.mem_map.mp member
      have absent : ∀ (old : I32ArrayView), old ∈ state.i32ArrayViews → ¬ (old.root = cell ∧ old.projections = path) := by
        simpa only [State.i32ArrayView?, List.find?_eq_none, decide_eq_true_eq] using missing
      exact absent old member (Prod.mk.inj equal)

/-- Both mapper branches derive a usable pointer and preserve the storage
    invariant. Reuse keeps the canonical address; first exposure allocates it. -/
theorem CellTargetValid.map
    (target : CellTargetValid program types state cell path (.array (.scalar (.signed .i32)) count))
    (read : readCellProjection state cell path = .ok (.array elements)) (ready : state.I32ViewsReady program types) :
    ∃ after, mapI32ArrayView state cell path elements = .done (.pointer (state.i32ArrayAddress cell path)) after ∧
      after.I32ViewsReady program types ∧ after.heap.Readable (state.i32ArrayAddress cell path) (count * 4) ∧
      (state.I32ViewsCoherent program types → after.I32ViewsCoherent program types) := by
  obtain ⟨value, actualRead, typed⟩ := target.read ready.store
  have same : value = .array elements := Except.ok.inj (actualRead.symm.trans read)
  subst value
  cases typed with
  | array elements element length elementsTyped =>
    cases registered : state.i32ArrayView? cell path with
    | none =>
      obtain ⟨bytes, mapped, access, readable, below, coherent, unique⟩ :=
        target.mapFresh read ready.toI32ViewsAccessible ready.below registered
      refine ⟨_, ?_, ⟨access, below, unique ready.keys⟩, ?_, coherent⟩
      · simpa only [State.i32ArrayAddress, registered, Option.map_none, Option.getD_none] using mapped
      · simpa only [State.i32ArrayAddress, registered, Option.map_none, Option.getD_none] using readable
    | some view =>
      have member : view ∈ state.i32ArrayViews := List.mem_of_find?_eq_some registered
      have key : view.root = cell ∧ view.projections = path := by
        simpa only [decide_eq_true_eq] using List.find?_some registered
      obtain ⟨old, oldRead, oldTyped⟩ := (ready.views view member).1.read ready.store
      rw [key.1, key.2] at oldRead
      have same : old = .array elements := Except.ok.inj (oldRead.symm.trans read)
      subst old
      have sameCount : count = view.length := by
        cases oldTyped with
        | array _ _ oldLength _ => exact length.symm.trans oldLength
      obtain ⟨heap, flushed, access, retained, bounded⟩ := ready.toI32ViewsAccessible.flush
      refine ⟨{ state with heap }, ?_,
        ⟨access, bounded ready.below, ready.keys⟩, ?_, ?_⟩
      · simp only [State.i32ArrayAddress, Option.map_some, Option.getD_some, mapI32ArrayView, registered, flushed]
      · simpa only [State.i32ArrayAddress, registered, Option.map_some, Option.getD_some, sameCount] using
          retained view.address (view.length * 4) (ready.views view member).2
      · intro coherent
        have unchanged : ({ state with heap } : State) = state := Except.ok.inj (flushed.symm.trans coherent.flush)
        simpa only [unchanged] using coherent

theorem CellTargetValid.i32ArrayDataPtr
    (target : CellTargetValid program types state cell [] (.array (.scalar (.signed .i32)) count))
    (binding : state.cellId? localId = some cell) (ready : state.I32ViewsReady program types) :
    ∃ after, RunsExpr program state (.i32ArrayDataPtr (.local localId))
      (.pointer (state.i32ArrayAddress cell [])) after ∧ after.I32ViewsReady program types ∧
      after.heap.Readable (state.i32ArrayAddress cell []) (count * 4) ∧
      (state.I32ViewsCoherent program types → after.I32ViewsCoherent program types) := by
  obtain ⟨value, found, typed⟩ := target.localRead ready.store binding
  cases typed with
  | array elements element length elementsTyped =>
    have stored := cellEntry_of_local state localId cell _ binding found
    have read : readCellProjection state cell [] = .ok (.array elements) := by
      simp only [readCellProjection, stored, projectedValue]
    obtain ⟨after, mapped, finalReady, readable, coherent⟩ := target.map read ready
    refine ⟨after, RunsExpr.ofEval (fuel := 2) ?_, finalReady, readable, coherent⟩
    rw [evalExpr.eq_def]
    simpa only [expressionPlace?, evalPlace_local_of_local? 0 program state .read localId cell _ binding found] using mapped

/-- A cell slice exposes the whole canonical array once, then offsets its
    pointer to the slice's exact subrange. The slice bounds supply readability. -/
theorem CellSliceValid.mapPointer
    (valid : CellSliceValid program types state (.slice (.scalar (.signed .i32)) cell path start length) (.scalar (.signed .i32)))
    (ready : state.I32ViewsReady program types) :
    ∃ after, mapI32SliceDataPtr state cell path start length =
      .done (.pointer (state.i32ArrayAddress cell path + start * 4)) after ∧ after.I32ViewsReady program types ∧
      after.heap.Readable (state.i32ArrayAddress cell path + start * 4) (length * 4) ∧
      (state.I32ViewsCoherent program types → after.I32ViewsCoherent program types) := by
  cases valid with
  | slice target bounds =>
    obtain ⟨value, read, typed⟩ := target.read ready.store
    cases typed with
    | array values element size elementsTyped =>
      obtain ⟨after, mapped, finalReady, readable, coherent⟩ := target.map read ready
      refine ⟨after, ?_, finalReady, readable.subrange (start := start * 4) (length := length * 4) (by omega), coherent⟩
      simp only [mapI32SliceDataPtr, read, if_pos (show start + length ≤ values.length from by omega), mapped]

theorem RunsExpr.i32CellSliceDataPtr
    (operand : RunsExpr program before expression (.slice (.scalar (.signed .i32)) cell path start length) middle)
    (valid : CellSliceValid program types middle (.slice (.scalar (.signed .i32)) cell path start length) (.scalar (.signed .i32)))
    (ready : middle.I32ViewsReady program types) :
    ∃ after, RunsExpr program before (.i32SliceDataPtr expression)
      (.pointer (middle.i32ArrayAddress cell path + start * 4)) after ∧ after.I32ViewsReady program types ∧
      after.heap.Readable (middle.i32ArrayAddress cell path + start * 4) (length * 4) ∧
      (middle.I32ViewsCoherent program types → after.I32ViewsCoherent program types) := by
  obtain ⟨after, mapped, finalReady, readable, coherent⟩ := valid.mapPointer ready
  obtain ⟨fuel, stable, _⟩ := operand
  refine ⟨after, RunsExpr.ofEval (fuel := fuel + 1) ?_, finalReady, readable, coherent⟩
  rw [evalExpr.eq_def]
  simpa only [stable fuel (Nat.le_refl _)] using mapped

/-- Storage validity needed by the byte-I/O pointer intrinsic, for both actual
    descriptor forms. Raw storage is readable now, not presumed live forever. -/
inductive I32SliceValid (program : Program) (types : CellTypes) (state : State) : Value → Nat → Prop where
  | cell (valid : CellSliceValid program types state
      (.slice (.scalar (.signed .i32)) cell path start length) (.scalar (.signed .i32))) :
      I32SliceValid program types state (.slice (.scalar (.signed .i32)) cell path start length) length
  | raw (readable : state.heap.Readable address (length * 4)) :
      I32SliceValid program types state (.rawSlice (.scalar (.signed .i32)) address length) length

theorem I32SliceValid.cellEffect {assigned : CellId} (valid : I32SliceValid program types before slice length)
    (effect : CellEffect before after assigned updated) : I32SliceValid program types after slice length := by
  cases valid with
  | cell valid => exact .cell (valid.cellEffect effect)
  | raw readable => exact .raw (by simpa only [effect.heap] using readable)

theorem I32SliceValid.retained (valid : I32SliceValid program types before slice length)
    (cells : FreshCellFrame before after) (reads : HeapReads before.heap after.heap) :
    I32SliceValid program types after slice length := by
  cases valid with
  | cell valid => exact .cell (valid.retained cells)
  | raw readable => exact .raw (reads.readable readable)

theorem I32SliceValid.dataPointer
    (operand : RunsExpr program before expression slice middle)
    (valid : I32SliceValid program types middle slice length) (ready : middle.I32ViewsReady program types) :
    ∃ address after, RunsExpr program before (.i32SliceDataPtr expression) (.pointer address) after ∧
      after.I32ViewsReady program types ∧ after.heap.Readable address (length * 4) ∧
      (middle.I32ViewsCoherent program types → after.I32ViewsCoherent program types) := by
  cases valid with
  | cell valid =>
    obtain ⟨after, run, finalReady, readable, coherent⟩ := operand.i32CellSliceDataPtr valid ready
    exact ⟨_, after, run, finalReady, readable, coherent⟩
  | raw readable =>
    obtain ⟨fuel, stable, _⟩ := operand
    refine ⟨_, middle, RunsExpr.ofEval (fuel := fuel + 1) ?_, ready, readable, fun coherent => coherent⟩
    rw [evalExpr.eq_def]
    simp only [stable fuel (Nat.le_refl _)]

#print axioms CellTargetValid.mapFresh
#print axioms CellTargetValid.map
#print axioms CellTargetValid.i32ArrayDataPtr
#print axioms CellSliceValid.mapPointer
#print axioms RunsExpr.i32CellSliceDataPtr
#print axioms I32SliceValid.dataPointer
#print axioms State.I32ViewsReady.cellEffect
#print axioms I32SliceValid.cellEffect
#print axioms State.I32ViewsReady.retained
#print axioms I32SliceValid.retained

end Lanius.Semantics
