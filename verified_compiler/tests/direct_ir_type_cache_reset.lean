import SelfCore
import Lanius.Core.Bindings
import Lanius.Semantics.CountedLocal
import Lanius.Semantics.LoopRun
import Lanius.Semantics.RawStore
import Lanius.Semantics.NativeReadFrame
import Lanius.Semantics.ScopedEffect

namespace IRTypeCacheResetProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics

variable {before after base : State}
private def source := Extracted.«lowering::body_expression».Functions.«clear_expression_kinds».core
private def counter := source.bindingId 0
private def loop : Expr × Stmt := match source.body.getD .skip with
  | .letLocal _ _ _ (.sequence (.whileLoop condition body) _) => (condition, body)
  | _ => (.value .unit, .skip)
private def valueExpr : Expr := match loop.2 with
  | .sequence (.expression (.assign _ _ value)) _ => value
  | _ => .value .unit

/-- Clearing accepts arbitrary old bytes; it does not require a valid cache. -/
structure Input (state : State) where
  address : Nat
  count : Nat
  capacity : Nat
  inside : count ≤ capacity
  fits : count < 2 ^ 31
  room : state.heap.Readable address (count * 4)

def Input.call (input : Input state) : Expr := .call source.id
  [.value (.rawSlice (.scalar (.signed .i32)) input.address input.capacity), .value (.signed .i32 input.count)]

def Cleared (input : Input before) (after : State) : Prop :=
  ∀ index, index < input.count → readRawSliceIndex extractedProgram after
    (.scalar (.signed .i32)) input.address input.capacity index = .ok (.signed .i32 (-1))

private structure Context (base : State) extends Input base where
  formed : base.CellsWellFormed
  unique : HeapBlockBasesUnique base.heap
  noViews : base.i32ArrayViews = []
  codesFound : base.local? (source.argumentId 0) = some (.rawSlice (.scalar (.signed .i32)) address capacity)
  countFound : base.local? (source.argumentId 1) = some (.signed .i32 count)

private structure Frame (context : Context base) (state : State) (index : Nat) : Prop extends
    CountedLocal base state counter index where
  written : HeapRegionWrite base.heap state.heap context.address (context.count * 4)
  cleared : ∀ position, position < index → readRawSliceIndex extractedProgram state
    (.scalar (.signed .i32)) context.address context.capacity position = .ok (.signed .i32 (-1))
  world : state.world = base.world
  views : state.i32ArrayViews = base.i32ArrayViews

private theorem Context.runLoop (context : Context base) (frame : Frame context before index)
    (remaining : Nat) (total : index + remaining = context.count) :
    ∃ after, RunsStmt extractedProgram before (.whileLoop loop.1 loop.2) .next after ∧
      Frame context after context.count := by
  induction remaining generalizing before index with
  | zero =>
      have same : index = context.count := by omega
      subst index
      core_facts [context, frame]
      exact ⟨before, .whileFalse (by core_run), frame⟩
  | succ remaining ih =>
      core_facts [context, frame]
      have bound : index < context.capacity := by omega
      have codesFound := frame.toCountedLocal.read (source.argumentId 0)
        (.rawSlice (.scalar (.signed .i32)) context.address context.capacity) (by decide) context.codesFound
      have guard : RunsExpr extractedProgram before loop.1 (.boolean true) before := by core_run
      obtain ⟨heap, storeRun, write⟩ := RunsExpr.assignRawI32 (program := extractedProgram)
        (before := before) (indexed := before) (ready := before)
        (sourceId := source.argumentId 0) (indexExpression := .local counter)
        (address := context.address) (length := context.capacity) (position := index)
        (expression := valueExpr) (value := -1) codesFound (.ofStable (.local frame.counter) rfl) bound
        ((frame.written.readable _ _ context.room).subrange (start := index * 4) (length := 4) (by omega))
        frame.written.unique (frame.views.trans context.noViews) (by core_run)
      let stored : State := { before with heap }
      have storedCounter : CountedLocal base stored counter index :=
        ⟨frame.cells, frame.locals, frame.counter⟩
      obtain ⟨next, increment, counted, sameHeap, world, views⟩ :=
        storedCounter.increment (program := extractedProgram) context.formed (by omega)
      have advanced : Frame context next (index + 1) := by
        refine ⟨counted, ?_, ?_, world.trans frame.world, views.trans frame.views⟩
        · rw [sameHeap]
          exact frame.written.trans ((HeapRegionWrite.ofBytes write).enlarge (by omega)
            (by simp only [i32Bytes, List.length_map, List.length_range]; omega))
        · intro position inside
          have read := readRawSliceIndex_i32_afterStore (program := extractedProgram)
            (before := before) (after := stored) (pointer := context.address)
            (position := position) (capacity := context.capacity) (previous := -1) write (by decide) (by omega)
            ((frame.written.readable _ _ context.room).subrange (start := position * 4) (length := 4) (by omega))
            (by intro different; exact frame.cleared position (by omega))
          simpa only [readRawSliceIndex, sameHeap, ite_self] using read
      have iteration : RunsStmt extractedProgram before loop.2 .next next := by core_stmt
      obtain ⟨after, rest, final⟩ := ih advanced (by omega)
      exact ⟨after, .whileStep guard iteration (Or.inl rfl) rest, final⟩

/-- The actual clearing function terminates, clears every live code word and
    frames the rest of memory, even if all initial codes were stale or corrupt. -/
theorem actualReset (input : Input before) (formed : before.CellsWellFormed)
    (unique : HeapBlockBasesUnique before.heap) (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before input.call .unit after ∧
      MemoryEffect (fun first last => HeapRegionWrite first last input.address (input.count * 4)) before after ∧
      Cleared input after := by
  let values := [Value.rawSlice (.scalar (.signed .i32)) input.address input.capacity, .signed .i32 input.count]
  let bindings := [(source.argumentId 0, Value.rawSlice (.scalar (.signed .i32)) input.address input.capacity),
    (source.argumentId 1, .signed .i32 input.count)]
  let callee := ({ before with locals := [] }).bindLocals bindings
  have calleeFormed : callee.CellsWellFormed := by core_formed
  let context : Context callee := {
    toInput := { input with room := input.room }, formed := calleeFormed,
    unique := unique, noViews := noViews, codesFound := by core_local, countFound := by core_local }
  let ready := callee.bindLocal counter (.signed .i32 0)
  have initial : Frame context ready 0 :=
    ⟨CountedLocal.start calleeFormed counter 0, HeapRegionWrite.refl _ unique, by intro i h; omega, rfl, rfl⟩
  obtain ⟨completed, run, final⟩ := context.runLoop initial context.count (Nat.zero_add _)
  have body : RunsStmt extractedProgram callee (source.body.getD .skip) .next
      (restoreLocals callee completed) := by
    apply RunsStmt.letLocal (by core_run)
    exact .sequenceNext run (.skip _ _)
  exact ⟨restoreLocals before (restoreLocals callee completed),
    RunsExpr.callUnit (function := source) (values := values) (bindings := bindings)
      (by core_lookup) rfl rfl
      (by simpa only [values, List.map] using RunsExprs.values (program := extractedProgram) (state := before) values)
      rfl body,
    ⟨(FreshCellFrame.bindLocals ({ before with locals := [] }) bindings).trans final.cells,
    final.world, final.views, final.written⟩, final.cleared⟩

#print axioms actualReset

end IRTypeCacheResetProof
