import verified_compiler.tests.direct_byte_io_read_step

namespace ByteIoReadProof.Outer

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics

private def reader := Extracted.«verified::byte_io».Functions.«read_file».core
private def adjustment : Stmt :=
  match reader.bindingStatement 3 with
  | .letLocal _ _ _ (.sequence first _) => first
  | _ => .skip

/-- Real loop-entry facts: neither a request nor a read result is assumed.
    Full scratch capacity bounds both branches of the actual request guard. -/
structure Input (state : State) extends Loop.Buffers state where
  handle : Int
  capacityFits : capacity < 2 ^ 31
  totalBound : total ≤ capacity
  scratchSize : 16384 ≤ words
  handleFound : state.local? (reader.argumentId 0) = some (.signed .i32 handle)
  pointerFound : state.local? (reader.bindingId 0) = some (.pointer address)
  capacityFound : state.local? (reader.argumentId 2) = some (.signed .i32 capacity)

def Input.specification (input : Input state) : ReadStep.Specification :=
  ⟨input.address, input.destination, input.capacity, input.total, input.handle,
    if input.capacity - input.total < 65536 then input.capacity - input.total + 1 else 65536⟩

/-- One complete actual outer body. Request initialization, adjustment and
    usize conversion discharge all entry facts of the existing read contract. -/
theorem iteration (input : Input before)
    (counter : CountedLocal base before (reader.bindingId 1) input.total)
    (formed : base.CellsWellFormed) :
    ∃ completion after, RunsStmt extractedProgram before (reader.whileLoop 0).2 completion after ∧
      ReadStep.Result input.specification before base before completion after := by
  let remaining := input.capacity - input.total
  let request := input.specification.request
  let seeded := before.bindLocal (reader.bindingId 2) (.signed .i32 65536)
  let staged := seeded.bindLocal (reader.bindingId 3) (.signed .i32 remaining)
  have stageFrame := ((CallerFrame.refl input.formed).bindLocal (reader.bindingId 2) (.signed .i32 65536)).bindLocal
    (reader.bindingId 3) (.signed .i32 remaining)
  have stageRequest : staged.local? (reader.bindingId 2) = some (.signed .i32 65536) :=
    State.bindLocal_local?_of_ne seeded (input.formed.bindLocal _ _) _ _ _ _ (by decide)
      (input.formed.bindLocal_local _ _)
  have stageRemaining : staged.local? (reader.bindingId 3) = some (.signed .i32 remaining) :=
    (input.formed.bindLocal _ _).bindLocal_local _ _
  have requestCell : staged.cellId? (reader.bindingId 2) = some before.nextCell := by
    rw [State.bindLocal_cellId_of_ne _ _ _ (by decide)]
    exact State.bindLocal_cellId _ _ _
  have requestFits : request < 2 ^ 31 := by
    dsimp [request, Input.specification]
    split <;> omega
  have requestRoom : request ≤ input.words * 4 := by
    dsimp [request, Input.specification]
    split <;> have := input.scratchSize <;> omega
  have finish (ready : State) (adjusted : RunsStmt extractedProgram staged adjustment .next ready)
      (frame : CallerFrame before ready) (locals : ready.locals = staged.locals)
      (requested : ready.local? (reader.bindingId 2) = some (.signed .i32 request))
      (remainder : ready.local? (reader.bindingId 3) = some (.signed .i32 remaining)) :
      ∃ completion after, RunsStmt extractedProgram before (reader.whileLoop 0).2 completion after ∧
        ReadStep.Result input.specification before base before completion after := by
    let readReady := ready.bindLocal (reader.bindingId 4) (.unsigned .usize request)
    have readyFormed := frame.currentFormed
    core_facts [input]
    have kept (id : VarId) (stored : Value) (different : id ≠ reader.bindingId 2 ∧ id ≠ reader.bindingId 3)
        (found : before.local? id = some stored) : ready.local? id = some stored :=
      frame.cells.localFoundAt (by
        simp only [State.cellId?, locals, staged, seeded, State.bindLocal, State.bindCell]
        simp [Ne.symm different.1, Ne.symm different.2]) stored found
    let readInput : ReadStep.Input readReady := {
      address := input.address, words := input.words, destination := input.destination
      capacity := input.capacity, total := input.total, handle := input.handle, request := request
      capacityFits := input.capacityFits, totalBound := input.totalBound, requestFits := requestFits, requestRoom := requestRoom
      inputRoom := by change ready.heap.Readable _ _; rw [frame.heap]; exact input.inputRoom
      outputRoom := by change ready.heap.Readable _ _; rw [frame.heap]; exact input.outputRoom
      separate := input.separate, formed := frame.currentFormed.bindLocal _ _
      unique := by change HeapBlockBasesUnique ready.heap; rw [frame.heap]; exact input.unique
      noViews := frame.views.trans input.noViews
      packed := by core_local
      output := by core_local
      cursor := by core_local
      handleFound := by core_local
      pointerFound := by core_local
      sizeFound := by core_local
      requestFound := by core_local, remainingFound := by core_local }
    have totalCell : readReady.cellId? (reader.bindingId 1) = some base.nextCell := by
      simp only [readReady, State.cellId?, locals, staged, seeded, State.bindLocal, State.bindCell]
      simp [show reader.bindingId 4 ≠ reader.bindingId 1 by decide,
        show reader.bindingId 3 ≠ reader.bindingId 1 by decide,
        show reader.bindingId 2 ≠ reader.bindingId 1 by decide, counter.locals]
    obtain ⟨completion, after, read, result⟩ := ReadStep.run readInput counter formed
      (frame.bindLocal _ _).cells totalCell
    have sizeFits : request < unsignedModulus extractedProgram.target .usize := by
      change request < 2 ^ 64
      omega
    have size : RunsExpr extractedProgram ready (reader.bindingInitializer 4) (.unsigned .usize request) ready := by
      core_run
    have initialRequest : RunsExpr extractedProgram before (reader.bindingInitializer 2) (.signed .i32 65536) before := by
      core_run
    have subtract : RunsExpr extractedProgram seeded (reader.bindingInitializer 3) (.signed .i32 remaining) seeded := by
      core_run
    have sized := RunsStmt.letLocal (id := reader.bindingId 4) (type := .scalar (.unsigned .usize))
      (afterInit := ready) size read
    have remainingRun := RunsStmt.letLocal (id := reader.bindingId 3) (type := .scalar (.signed .i32))
      (afterInit := seeded) subtract (RunsStmt.sequenceNext adjusted sized)
    have requestRun := RunsStmt.letLocal (id := reader.bindingId 2) (type := .scalar (.signed .i32))
      (afterInit := before) initialRequest remainingRun
    refine ⟨completion, restoreLocals before after, ?_, ?_⟩
    · exact Eq.mp (by congr 1 <;> rfl) requestRun
    · simpa only [readInput, ReadStep.Input.specification, Input.specification, request] using
        (result.prepend (frame.bindLocal _ _)).scope before
  core_facts [input]
  by_cases short : remaining < 65536
  · obtain ⟨ready, assigned, stored, effect⟩ := RunsExpr.assignI32 (program := extractedProgram)
      (expression := match reader.effectExpression 0 with | .assign _ _ rhs => rhs | _ => .value .unit)
      (op := .set) (operand := remaining + 1) (replacement := remaining + 1) requestCell stageRequest
      (by core_run) rfl
    have frame := stageFrame.assignLocalFresh (reader.bindingId 2) before.nextCell (.signed .i32 (remaining + 1))
      requestCell (Nat.le_refl _) stored
    have unchanged : ready.local? (reader.bindingId 3) = some (.signed .i32 remaining) :=
      assignCell_preserves_other_local_of_cellId _ _ _ (assignLocal_assignCell _ _ _ requestCell stored)
        stageRemaining (by simp [staged, seeded, State.bindLocal, State.bindCell, State.cellId?])
    apply finish ready (by core_stmt) frame effect.locals
    · simpa only [request, Input.specification, remaining, if_pos short, Int.natCast_add, Int.natCast_one] using
        assignLocal_finds_assigned _ _ _ requestCell stored
    · exact unchanged
  · apply finish staged (by core_stmt) stageFrame rfl
    · simpa only [request, Input.specification, remaining, if_neg short, Int.cast_ofNat_Int] using stageRequest
    · exact stageRemaining

#print axioms iteration

end ByteIoReadProof.Outer
