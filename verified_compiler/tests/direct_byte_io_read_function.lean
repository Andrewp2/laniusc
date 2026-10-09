import verified_compiler.tests.direct_byte_io_read_total

namespace ByteIoReadProof.Function

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics

private def reader := Extracted.«verified::byte_io».Functions.«read_file».core
private def body := reader.body.getD .skip

/-- Negative capacity is rejected before reading either buffer or the file. -/
theorem rejectCapacity (found : before.local? (reader.argumentId 2) = some (.signed .i32 capacity))
    (negative : capacity < 0) :
    RunsStmt extractedProgram before body (.returned (some (.signed .i32 (-2)))) before := by
  core_stmt

/-- Null scratch is rejected without assuming that either buffer is readable. -/
theorem rejectScratch (formed : before.CellsWellFormed)
    (packed : before.local? (reader.argumentId 3) = some (.rawSlice (.scalar (.signed .i32)) 0 words))
    (found : before.local? (reader.argumentId 2) = some (.signed .i32 capacity)) (nonnegative : 0 ≤ capacity) :
    ∃ after, RunsStmt extractedProgram before body (.returned (some (.signed .i32 (-2)))) after ∧
      PureFrame before after := by
  let ready := before.bindLocal (reader.bindingId 0) (.pointer 0)
  have initial : RunsExpr extractedProgram before (reader.bindingInitializer 0) (.pointer 0) before :=
    .ofStable (.rawSliceDataPtr (.local packed)) rfl
  have pointerFound := formed.bindLocal_local (reader.bindingId 0) (.pointer 0)
  have reject : RunsStmt extractedProgram ready
      (match reader.bindingStatement 0 with | .letLocal _ _ _ rest => rest | _ => .skip)
      (.returned (some (.signed .i32 (-2)))) ready := by core_stmt
  have scopedRun := RunsStmt.letLocal (id := reader.bindingId 0) (type := .scalar .rawPtr) initial reject
  exact ⟨restoreLocals before ready, by core_stmt,
    ((CallerFrame.refl formed).bindLocal _ _).restoreLocals⟩

def ready (parameters : Total.Parameters before) : State :=
  before.bindLocal (reader.bindingId 0) (.pointer parameters.address)

/-- Derive lexical loop entry once for both safety and content consumers. -/
def context (parameters : Total.Parameters before) : Total.Context (ready parameters) := {
    address := parameters.address, words := parameters.words, destination := parameters.destination
    capacity := parameters.capacity, handle := parameters.handle
    formed := parameters.formed.bindLocal _ _, capacityFits := parameters.capacityFits
    scratchSize := parameters.scratchSize, separate := parameters.separate
    packed := by core_facts [parameters]; core_local
    output := by core_facts [parameters]; core_local
    handleFound := by core_facts [parameters]; core_local
    capacityFound := by core_facts [parameters]; core_local
    pointerFound := parameters.formed.bindLocal_local _ _ }

theorem enter (parameters : Total.Parameters before) (nonzero : parameters.address ≠ 0)
    (total : RunsStmt extractedProgram (ready parameters) (reader.bindingStatement 1)
      (.returned (some value)) after) :
    RunsStmt extractedProgram before body (.returned (some value)) (restoreLocals before after) := by
  have initial : RunsExpr extractedProgram before (reader.bindingInitializer 0) (.pointer parameters.address) before :=
    .ofStable (.rawSliceDataPtr (.local parameters.packed)) rfl
  let context := context parameters
  core_facts [parameters, context]
  have nonnull : context.address ≠ 0 := nonzero
  have rest : RunsStmt extractedProgram (ready parameters)
      (match reader.bindingStatement 0 with | .letLocal _ _ _ rest => rest | _ => .skip)
      (.returned (some value)) after := by core_stmt
  have scopedRun := RunsStmt.letLocal (id := reader.bindingId 0) (type := .scalar .rawPtr) initial rest
  core_stmt

/-- Total actual body execution for independent raw buffers, including
    every modeled I/O outcome and caller scope/cell restoration. -/
theorem run (parameters : Total.Parameters before)
    (inputRoom : before.heap.Readable parameters.address (parameters.words * 4))
    (outputRoom : before.heap.Readable parameters.destination (parameters.capacity * 4))
    (unique : HeapBlockBasesUnique before.heap) (noViews : before.i32ArrayViews = []) :
    ∃ value after, RunsStmt extractedProgram before body (.returned (some value)) after ∧
      Total.Result parameters.toConfiguration before value after := by
  by_cases zero : parameters.address = 0
  · have packed : before.local? (reader.argumentId 3) =
        some (.rawSlice (.scalar (.signed .i32)) parameters.address parameters.words) := parameters.packed
    rw [zero] at packed
    obtain ⟨after, rejected, frame⟩ := rejectScratch parameters.formed packed
      parameters.capacityFound (Int.natCast_nonneg _)
    exact ⟨_, after, rejected, 0, Nat.zero_le _, frame.cells,
      by simpa only [frame.heap] using inputRoom, by simpa only [frame.heap] using outputRoom,
      by simpa only [frame.heap] using unique, frame.views.trans noViews, Or.inr (Or.inl rfl),
      by simpa only [frame.heap] using (HeapWritesOn.refl (allowed := parameters.toConfiguration.mutable) unique)⟩
  · obtain ⟨value, after, total, result⟩ := Total.declaration (context parameters) inputRoom outputRoom unique noViews
    have executed := enter parameters zero total
    obtain ⟨index, bounded, cells, scratch, output, unique, views, values, written⟩ := result
    exact ⟨value, _, executed, index, bounded,
      ((FreshCellFrame.bindLocal before _ _).trans cells).restoreLocals,
      scratch, output, unique, views, values, written⟩

#print axioms rejectCapacity
#print axioms rejectScratch
#print axioms run

/-- Raw buffer/caller assumptions at a public call, with no internal locals.
    All are independent storage, representation and separation facts. -/
structure Input (caller : State) extends Total.Configuration where
  formed : caller.CellsWellFormed
  capacityFits : capacity < 2 ^ 31
  scratchSize : 16384 ≤ words
  separate : destination + capacity * 4 ≤ address ∨ address + words * 4 ≤ destination
  inputRoom : caller.heap.Readable address (words * 4)
  outputRoom : caller.heap.Readable destination (capacity * 4)
  unique : HeapBlockBasesUnique caller.heap
  noViews : caller.i32ArrayViews = []

def Input.values (input : Input caller) : List Value :=
  [.signed .i32 input.handle, .rawSlice (.scalar (.signed .i32)) input.destination input.capacity,
    .signed .i32 input.capacity, .rawSlice (.scalar (.signed .i32)) input.address input.words]

def Input.bindings (input : Input caller) := List.zip (reader.parameters.map Prod.fst) input.values
def Input.entry (input : Input caller) := ({ caller with locals := [] } : State).bindLocals input.bindings

theorem Input.entryFrame (input : Input caller) : FreshCellFrame caller input.entry :=
  FreshCellFrame.bindLocals { caller with locals := [] } input.bindings

def Input.parameters (input : Input caller) : Total.Parameters input.entry := by
  have clearFormed : ({ caller with locals := [] } : State).CellsWellFormed := input.formed
  exact {
    toConfiguration := input.toConfiguration
    formed := input.entryFrame.after_cellsWellFormed input.formed
    capacityFits := input.capacityFits, scratchSize := input.scratchSize, separate := input.separate
    packed := by core_local
    output := by core_local
    handleFound := by core_local
    capacityFound := by core_local }
theorem Input.invoke (input : Input caller)
    (executed : RunsStmt extractedProgram input.entry body (.returned (some value)) after) :
    RunsExpr extractedProgram caller (.call reader.id (input.values.map Expr.value)) value (restoreLocals caller after) :=
  RunsExpr.call (functionId := reader.id) (function := reader) (body := body) (bindings := input.bindings)
    (by core_lookup) rfl (RunsExprs.values input.values) (by rfl) executed

/-- Bind the actual arguments and restore the caller. Internal bindings,
    body execution and correct output are not input assumptions. -/
theorem call (input : Input caller) :
    ∃ value after, RunsExpr extractedProgram caller (.call reader.id (input.values.map Expr.value)) value after ∧
      Total.Result input.toConfiguration caller value after := by
  obtain ⟨value, after, executed, result⟩ := run input.parameters input.inputRoom input.outputRoom input.unique input.noViews
  obtain ⟨index, bounded, cells, scratch, output, unique, views, values, written⟩ := result
  exact ⟨value, restoreLocals caller after, input.invoke executed, index, bounded,
    (input.entryFrame.trans cells).restoreLocals, scratch, output, unique, views, values, written⟩

#print axioms call

end ByteIoReadProof.Function
