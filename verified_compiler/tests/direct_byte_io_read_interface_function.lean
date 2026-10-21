import verified_compiler.tests.direct_byte_io_read_interface_total

namespace ByteIoReadInterface.Function

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics

private def body := reader.body.getD .skip

/-- Negative capacity is rejected before either buffer or the file is read. -/
theorem rejectCapacity (found : before.local? (reader.argumentId 2) = some (.signed .i32 capacity))
    (negative : capacity < 0) :
    RunsStmt extractedProgram before body (.returned (some (.signed .i32 (-2)))) before := by
  core_stmt

/-- The null-scratch rejection requires no readable-buffer assumption. -/
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

/-- The unchanged public reader domain: independent raw storage and the
actual caller's formed cells, with no assumptions about future I/O. -/
structure Input (caller : State) extends Configuration where
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
def Input.ready (input : Input caller) := input.entry.bindLocal (reader.bindingId 0) (.pointer input.address)

theorem Input.entryEnv (input : Input caller) :
    LocalEnv caller input.entry input.toConfiguration.values :=
  (LocalEnv.clear input.formed).bindLocals input.bindings

def Input.context (input : Input caller) : Context caller input.ready := {
  toConfiguration := input.toConfiguration
  env := input.entryEnv.bind (reader.bindingId 0) (.pointer input.address)
  capacityFits := input.capacityFits, scratchSize := input.scratchSize, separate := input.separate
  heap := rfl, world := rfl, views := rfl }

theorem Input.enter (input : Input caller) (nonzero : input.address ≠ 0)
    (total : RunsStmt extractedProgram input.ready (reader.bindingStatement 1)
      (.returned (some value)) after) :
    RunsStmt extractedProgram input.entry body (.returned (some value)) (restoreLocals input.entry after) := by
  have packed := input.entryEnv.read (show input.toConfiguration.values (reader.argumentId 3) =
    some (.rawSlice (.scalar (.signed .i32)) input.address input.words) from rfl)
  have capacity := input.entryEnv.read (show input.toConfiguration.values (reader.argumentId 2) =
    some (.signed .i32 input.capacity) from rfl)
  have pointer := input.context.env.read (show input.toConfiguration.readyValues (reader.bindingId 0) =
    some (.pointer input.address) from rfl)
  have initial : RunsExpr extractedProgram input.entry (reader.bindingInitializer 0) (.pointer input.address) input.entry :=
    .ofStable (.rawSliceDataPtr (.local packed)) rfl
  have rest : RunsStmt extractedProgram input.ready
      (match reader.bindingStatement 0 with | .letLocal _ _ _ rest => rest | _ => .skip)
      (.returned (some value)) after := by core_stmt
  have scopedRun := RunsStmt.letLocal (id := reader.bindingId 0) (type := .scalar .rawPtr) initial rest
  core_stmt

theorem Input.invoke (input : Input caller)
    (executed : RunsStmt extractedProgram input.entry body (.returned (some value)) after) :
    RunsExpr extractedProgram caller (.call reader.id (input.values.map Expr.value)) value (restoreLocals caller after) :=
  RunsExpr.call (functionId := reader.id) (function := reader) (body := body) (bindings := input.bindings)
    (by core_lookup) rfl (RunsExprs.values input.values) (by rfl) executed

/-- One actual outer execution supports safety and a supplied observation
invariant. The tracker only consumes read outcomes; it assumes no execution. -/
theorem callTracked (input : Input caller) (nonzero : input.address ≠ 0)
    (tracker : Tracker input.context) (tracked : tracker.Inv 0 caller.heap caller.world) :
    ∃ value after, RunsExpr extractedProgram caller (.call reader.id (input.values.map Expr.value)) value after ∧
      Result input.toConfiguration caller value after ∧
      tracker.Done (.returned (some value)) after.heap after.world ∧
      after.locals = caller.locals ∧ after.i32ArrayViews = caller.i32ArrayViews := by
  obtain ⟨value, after, total, _, result, done⟩ := declarationTracked input.context tracker tracked
    ⟨input.inputRoom, input.outputRoom⟩ input.unique input.noViews
  have executed := input.enter nonzero total
  refine ⟨value, restoreLocals caller (restoreLocals input.entry after), input.invoke executed, result, done, rfl, ?_⟩
  exact result.choose_spec.2.2.2.2.2.1.trans input.noViews.symm

/-- Whole Core1584 call for every modeled read outcome. Argument and local
binding, loop execution, and scope restoration are conclusions. -/
theorem call (input : Input caller) :
    ∃ value after, RunsExpr extractedProgram caller (.call reader.id (input.values.map Expr.value)) value after ∧
      Result input.toConfiguration caller value after ∧
      after.locals = caller.locals ∧ after.i32ArrayViews = caller.i32ArrayViews := by
  by_cases zero : input.address = 0
  · have packed := input.entryEnv.read (show input.toConfiguration.values (reader.argumentId 3) =
      some (.rawSlice (.scalar (.signed .i32)) input.address input.words) from rfl)
    rw [zero] at packed
    have capacity := input.entryEnv.read (show input.toConfiguration.values (reader.argumentId 2) =
      some (.signed .i32 input.capacity) from rfl)
    obtain ⟨after, rejected, frame⟩ := rejectScratch input.entryEnv.formed packed capacity (Int.natCast_nonneg _)
    have heap : after.heap = caller.heap := frame.heap.trans input.context.heap
    refine ⟨_, restoreLocals caller after, input.invoke rejected, ?_, rfl, frame.views⟩
    exact ⟨0, Nat.zero_le _, (input.entryEnv.cells.trans frame.cells).restoreLocals,
      by simpa only [restoreLocals_heap, heap] using input.inputRoom,
      by simpa only [restoreLocals_heap, heap] using input.outputRoom,
      by simpa only [restoreLocals_heap, heap] using input.unique,
      frame.views.trans input.noViews, Or.inr (Or.inl rfl),
      by simpa only [restoreLocals_heap, heap] using (HeapWritesOn.refl (allowed := input.toConfiguration.mutable) input.unique)⟩
  · obtain ⟨value, after, executed, result, _, locals, views⟩ := callTracked input zero .unobserved True.intro
    exact ⟨value, after, executed, result, locals, views⟩

#print axioms rejectCapacity
#print axioms rejectScratch
#print axioms call

end ByteIoReadInterface.Function
