import verified_compiler.tests.direct_byte_io_read_loop
import verified_compiler.tests.direct_host_views

namespace ByteIoReadProof.ReadStep

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics

private def reader := Extracted.«verified::byte_io».Functions.«read_file».core

/-- The actual continuation of the read/count declaration, not a replacement
    program. `run` below includes its initializer and enclosing read scope. -/
def continuation : Stmt :=
  match reader.bindingStatement 5 with
  | .letLocal _ _ _ body => body
  | _ => .skip

/-- Actual read-entry facts extend the same buffers used by the copy loop.
    Numeric/storage bounds and bindings are independent of read success. -/
structure Input (state : State) extends Loop.Buffers state where
  handle : Int
  request : Nat
  capacityFits : capacity < 2 ^ 31
  totalBound : total ≤ capacity
  requestFits : request < 2 ^ 31
  requestRoom : request ≤ words * 4
  handleFound : state.local? (reader.argumentId 0) = some (.signed .i32 handle)
  pointerFound : state.local? (reader.bindingId 0) = some (.pointer address)
  sizeFound : state.local? (reader.bindingId 4) = some (.unsigned .usize request)
  requestFound : state.local? (reader.bindingId 2) = some (.signed .i32 request)
  remainingFound : state.local? (reader.bindingId 3) = some (.signed .i32 (capacity - total : Nat))

/-- Observable read parameters do not depend on temporary lexical bindings. -/
structure Specification where
  address : Nat
  destination : Nat
  capacity : Nat
  total : Nat
  handle : Int
  request : Nat

def Input.specification (input : Input state) : Specification :=
  ⟨input.address, input.destination, input.capacity, input.total, input.handle, input.request⟩

/-- Execute the actual count initializer, including its real host declaration
    and argument lookups. It returns exact modeled data/cursor effects while
    retaining all cells and lexical bindings. No read success is assumed. -/
theorem initial (input : Input state) :
    ∃ value heap world, RunsExpr extractedProgram state (reader.bindingInitializer 5)
      value { state with heap, world } ∧
      FileReadResult state.heap state.world input.handle input.address input.request value heap world := by
  have readable : state.heap.Readable input.address input.request := by
    simpa only [Nat.add_zero] using input.inputRoom.subrange
      (start := 0) (length := input.request) (by simpa only [Nat.zero_add] using input.requestRoom)
  obtain ⟨value, heap, world, called, result⟩ :=
    HostViewsProof.readRaw (handle := input.handle) input.noViews input.unique readable
  core_facts [input]
  refine ⟨value, heap, world, ?_, result⟩
  apply RunsExpr.callArguments (values := [.signed .i32 input.handle, .pointer input.address, .unsigned .usize input.request]) ?_ called
  core_arguments

/-- A successful byte-read frame establishes the copy's loaded bytes and
    buffer validity. The read supplies the request bound, and the actual
    capacity guard supplies space in the destination. -/
def Input.chunk (input : Input state)
    (written : BytesWrite state.heap heap input.address bytes)
    (within : bytes.length ≤ input.request)
    (bounded : input.total + bytes.length ≤ input.capacity) :
    Loop.Input (({ state with heap, world } : State).bindLocal (reader.bindingId 5) (.signed .i32 bytes.length)) := by
  let read : State := { state with heap, world }
  core_facts [input]
  refine {
    address := input.address, words := input.words, destination := input.destination
    capacity := input.capacity, total := input.total, bytes := bytes
    fits := by omega, inputSize := Nat.le_trans within input.requestRoom, outputSize := bounded
    inputRoom := written.readable input.inputRoom, outputRoom := written.readable input.outputRoom
    loaded := written.loadBytes, separate := input.separate
    formed := input.formed.bindLocal (reader.bindingId 5) (.signed .i32 bytes.length)
    unique := written.unique, noViews := input.noViews, packed := ?_, output := ?_, cursor := ?_
    count := State.bindLocal_local? read input.formed (reader.bindingId 5) (.signed .i32 bytes.length) }
  all_goals
    apply State.bindLocal_local?_of_ne read input.formed <;> first | decide | exact input.packed | exact input.output | exact input.cursor

/-- Continuing reads discharge all actual count/capacity guards before entering
    the proved scoped chunk. Input bytes and all buffer/cell premises have an
    independent meaning; the preceding host read must establish them. -/
theorem copy (input : Loop.Input ready) (request : Nat)
    (counter : CountedLocal base before (reader.bindingId 1) input.total)
    (formed : base.CellsWellFormed) (setup : FreshCellFrame before ready)
    (cell : ready.cellId? (reader.bindingId 1) = some base.nextCell)
    (requestFound : ready.local? (reader.bindingId 2) = some (.signed .i32 request))
    (remainingFound : ready.local? (reader.bindingId 3) = some (.signed .i32 (input.capacity - input.total : Nat)))
    (positive : 0 < input.bytes.length) (bounded : input.bytes.length ≤ request) :
    ∃ after, RunsStmt extractedProgram ready continuation .next after ∧
      CountedLocal base (restoreLocals before after) (reader.bindingId 1) (input.total + input.bytes.length : Nat) ∧
      BytesWrite ready.heap after.heap (input.destination + input.total * 4) (input.bytes.flatMap Loop.encodeByte) ∧
      after.world = ready.world ∧ after.i32ArrayViews = ready.i32ArrayViews := by
  obtain ⟨after, chunk, counted, written, world, views⟩ := Loop.chunk input counter formed setup cell
  core_facts [input]
  exact ⟨after, by core_stmt, counted, written, world, views⟩

/-- Exact file/copy observations, including every returning branch. The file
    model chooses the bytes; no successful execution or output is assumed. -/
def Result (spec : Specification) (origin base before : State) (completion : Completion) (after : State) : Prop :=
  ∃ value heap world,
    FileReadResult origin.heap origin.world spec.handle spec.address spec.request value heap world ∧
    after.world = world ∧ after.i32ArrayViews = origin.i32ArrayViews ∧
    match World.readFileBytes (World.record origin.world .read) spec.handle spec.request with
    | none => completion = .returned (some (.signed .i32 (-1))) ∧ after.heap = heap ∧
        CountedLocal base (restoreLocals before after) (reader.bindingId 1) spec.total
    | some (bytes, _) =>
        if bytes = [] then completion = .returned (some (.signed .i32 spec.total)) ∧ after.heap = heap ∧
          CountedLocal base (restoreLocals before after) (reader.bindingId 1) spec.total
        else if spec.total + bytes.length ≤ spec.capacity then completion = .next ∧
          CountedLocal base (restoreLocals before after) (reader.bindingId 1) (spec.total + bytes.length : Nat) ∧
          BytesWrite heap after.heap (spec.destination + spec.total * 4) (bytes.flatMap Loop.encodeByte)
        else completion = .returned (some (.signed .i32 (-2))) ∧ after.heap = heap ∧
          CountedLocal base (restoreLocals before after) (reader.bindingId 1) spec.total

theorem Result.prepend (result : Result spec ready base before completion after)
    (setup : CallerFrame origin ready) : Result spec origin base before completion after := by
  simpa only [Result, setup.heap, setup.world, setup.views] using result

theorem Result.scope (result : Result spec origin base before completion after) (caller : State) :
    Result spec origin base before completion (restoreLocals caller after) := by
  simpa only [Result, restoreLocals] using result

/-- The existing exact read/copy effects frame the union of scratch request
    and output storage; this does not reevaluate either computation. -/
def Specification.mutable (spec : Specification) (location : Address) : Prop :=
  (spec.address ≤ location ∧ location < spec.address + spec.request) ∨
  (spec.destination ≤ location ∧ location < spec.destination + spec.capacity * 4)

theorem Result.footprint (result : Result spec origin base before completion after)
    (unique : HeapBlockBasesUnique origin.heap) : HeapWritesOn origin.heap after.heap spec.mutable := by
  obtain ⟨value, heap, world, read, _, _, outcome⟩ := result
  have first : HeapWritesOn origin.heap heap spec.mutable :=
    (read.footprint unique).weaken (fun _ inside => Or.inl inside)
  cases reading : World.readFileBytes (World.record origin.world .read) spec.handle spec.request with
  | none =>
      simp only [reading] at outcome
      simpa only [outcome.2.1] using first
  | some pair =>
      rcases pair with ⟨bytes, updated⟩
      simp only [reading] at outcome
      by_cases empty : bytes = []
      · simp only [if_pos empty] at outcome
        simpa only [outcome.2.1] using first
      · by_cases bounded : spec.total + bytes.length ≤ spec.capacity
        · simp only [if_neg empty, if_pos bounded] at outcome
          exact first.trans (outcome.2.2.footprint.weaken (by
            intro location inside
            apply Or.inr
            rw [Loop.encode_length] at inside
            dsimp only [Address] at *
            constructor <;> omega))
        · simp only [if_neg empty, if_neg bounded] at outcome
          simpa only [outcome.2.1] using first

/-- Total execution of the actual count declaration: host read, source-ordered
    guards, copy/update and count-scope restoration share one contract. -/
theorem run (input : Input ready)
    (counter : CountedLocal base before (reader.bindingId 1) input.total)
    (formed : base.CellsWellFormed) (setup : FreshCellFrame before ready)
    (cell : ready.cellId? (reader.bindingId 1) = some base.nextCell) :
    ∃ completion after, RunsStmt extractedProgram ready (reader.bindingStatement 5) completion after ∧
      Result input.specification ready base before completion after := by
  dsimp only [Result, Input.specification]
  obtain ⟨value, heap, world, initialized, result⟩ := initial input
  let read : State := { ready with heap, world }
  let bound := read.bindLocal (reader.bindingId 5) value
  have unchanged : FreshCellFrame ready read := ⟨[], by simp [read], Nat.le_refl _, by simp⟩
  have fresh := setup.trans (unchanged.trans (FreshCellFrame.bindLocal read (reader.bindingId 5) value))
  have kept (id : VarId) (stored : Value) (different : id ≠ reader.bindingId 5)
      (found : ready.local? id = some stored) : bound.local? id = some stored :=
    State.bindLocal_local?_of_ne read input.formed id _ stored value (Ne.symm different) found
  have totalCell : bound.cellId? (reader.bindingId 1) = some base.nextCell := by
    rw [State.bindLocal_cellId_of_ne _ _ _ (by decide)]
    exact cell
  have counted := counter.restoreScoped (counter.cells.trans fresh) totalCell
    (kept _ _ (by decide) input.cursor)
  have finish (completion : Completion) (after : State)
      (body : RunsStmt extractedProgram bound continuation completion after) :
      RunsStmt extractedProgram ready (reader.bindingStatement 5) completion (restoreLocals ready after) :=
    RunsStmt.letLocal (afterInit := read) (afterBody := after) initialized body
  core_facts [input]
  cases reading : World.readFileBytes (World.record ready.world .read) input.handle input.request with
  | none =>
      have invalid : value = .signed .i32 (-1) := by
        have failed := result
        simp only [FileReadResult, reading] at failed
        exact failed.1.trans (by unfold World.i32Result; congr 1)
      have found : bound.local? (reader.bindingId 5) = some (.signed .i32 (-1)) :=
        invalid ▸ input.formed.bindLocal_local _ value
      refine ⟨.returned (some (.signed .i32 (-1))), restoreLocals ready bound, finish _ _ (by core_stmt),
        _, heap, world, result, rfl, rfl, ?_⟩
      simp only
      exact ⟨True.intro, rfl, by simpa only [restoreLocals] using counted⟩
  | some pair =>
      rcases pair with ⟨bytes, updated⟩
      obtain ⟨same, _, within, written⟩ := result.success reading input.requestFits
      have found : bound.local? (reader.bindingId 5) = some (.signed .i32 bytes.length) :=
        same ▸ input.formed.bindLocal_local _ value
      by_cases empty : bytes = []
      · subst bytes
        refine ⟨.returned (some (.signed .i32 input.total)), restoreLocals ready bound, finish _ _ (by core_stmt),
          _, heap, world, result, rfl, rfl, ?_⟩
        simp only
        exact ⟨True.intro, rfl, by simpa only [restoreLocals] using counted⟩
      · have positive : 0 < bytes.length := List.length_pos_iff.mpr empty
        by_cases bounded : input.total + bytes.length ≤ input.capacity
        · let chunk := input.chunk (world := world) written within bounded
          have chunkState : bound = read.bindLocal (reader.bindingId 5) (.signed .i32 bytes.length) := by
            change read.bindLocal (reader.bindingId 5) value = _
            rw [same]
          obtain ⟨after, body, counted, copied, finalWorld, views⟩ := copy chunk input.request counter formed
            (by simpa only [same] using fresh) (by simpa only [chunkState] using totalCell)
            (by simpa only [chunkState] using kept _ _ (by decide) input.requestFound)
            (by simpa only [chunkState, chunk, Input.chunk] using kept _ _ (by decide) input.remainingFound) positive within
          refine ⟨.next, restoreLocals ready after, finish _ _ (by simpa only [chunkState] using body),
            _, heap, world, result, finalWorld, views, ?_⟩
          simp only [if_neg empty, if_pos bounded]
          exact ⟨True.intro, by simpa only [restoreLocals, chunk, Input.chunk] using counted, copied⟩
        · refine ⟨.returned (some (.signed .i32 (-2))), restoreLocals ready bound, finish _ _ (by core_stmt),
            _, heap, world, result, rfl, rfl, ?_⟩
          simp only [if_neg empty, if_neg bounded]
          exact ⟨True.intro, rfl, by simpa only [restoreLocals] using counted⟩

#print axioms copy
#print axioms initial
#print axioms run

end ByteIoReadProof.ReadStep
