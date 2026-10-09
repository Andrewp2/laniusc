import verified_compiler.tests.direct_byte_io_read_function
import Lanius.World.FileRead
import Lanius.Memory.BufferPrefix

namespace ByteIoReadProof.File

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics

private def reader := Extracted.«verified::byte_io».Functions.«read_file».core

/-- The initial file suffix is independent of compiler/read execution. -/
def available (file : World.FileEntry) (handle : World.FileHandle) := file.bytes.drop handle.offset

def Progress (geometry : Total.Configuration) (base : State) (file : World.FileEntry) (handle : World.FileHandle)
    (total : Nat) (heap : Heap) (world : World.State) : Prop :=
  ∃ reads, total ≤ (available file handle).length ∧
    (total < (available file handle).length → total % 65536 = 0) ∧
    reads = (total + 65535) / 65536 ∧
    World.FileCursor world geometry.handle file { handle with offset := handle.offset + total } ∧
    world.calls = base.world.calls ++ List.replicate reads .read ∧
    BufferPrefix base.heap heap geometry.destination (geometry.capacity * 4)
      (((available file handle).take total).flatMap Loop.encodeByte)

/-- Exact whole-file bytes, unchanged output tail, count, cursor and host
    trace on readable files fitting the output capacity. -/
def Result (geometry : Total.Configuration) (base : State) (file : World.FileEntry) (handle : World.FileHandle)
    (completion : Completion) (heap : Heap) (world : World.State) : Prop :=
  completion = .returned (some (.signed .i32 (available file handle).length)) ∧
    World.FileCursor world geometry.handle file { handle with offset := handle.offset + (available file handle).length } ∧
    world.calls = base.world.calls ++ List.replicate (((available file handle).length + 65535) / 65536 + 1) .read ∧
    BufferPrefix base.heap heap geometry.destination (geometry.capacity * 4)
      ((available file handle).flatMap Loop.encodeByte)

variable {base before after : State} {context : Total.Context base}
  {file : World.FileEntry} {handle : World.FileHandle} {total : Nat} {completion : Completion}

theorem start (cursor : World.FileCursor base.world context.handle file handle) :
    Progress context.toConfiguration base file handle 0 base.heap base.world :=
  ⟨0, Nat.zero_le _, by intros; rfl, by decide,
    by simpa only [Nat.add_zero] using cursor, by simp, BufferPrefix.refl⟩

/-- Observe the retained read result, not a replay of the outer body. -/
theorem step (fits : (available file handle).length ≤ context.capacity)
    (current : Total.Invariant context before total)
    (tracked : Progress context.toConfiguration base file handle total before.heap before.world)
    (body : RunsStmt extractedProgram before (reader.whileLoop 0).2 completion after)
    (result : ReadStep.Result current.input.specification before base before completion after) :
    (Total.Done context completion after → Result context.toConfiguration base file handle completion after.heap after.world) ∧
    (∀ next, completion = .next → Total.Invariant context after next →
      Progress context.toConfiguration base file handle next after.heap after.world) := by
  obtain ⟨reads, within, aligned, readCount, cursor, trace, stored⟩ := tracked
  let request := if context.capacity - total < 65536 then context.capacity - total + 1 else 65536
  let bytes := (file.bytes.drop (handle.offset + total)).take request
  have positive : 0 < request := by dsimp [request]; split <;> omega
  have bytesLength : bytes.length = min request ((available file handle).length - total) := by
    simp only [bytes, available, ← List.drop_drop, List.length_take, List.length_drop]
  have copiedBound : total + bytes.length ≤ (available file handle).length := by
    have := Nat.min_le_right request ((available file handle).length - total)
    omega
  obtain ⟨nextWorld, reading, advanced, calls⟩ := cursor.record.read request
  change World.readFileBytes (World.record before.world .read) context.handle request = some (bytes, nextWorld) at reading
  change World.FileCursor nextWorld context.handle file { handle with offset := handle.offset + total + bytes.length } at advanced
  change ReadStep.Result ⟨context.address, context.destination, context.capacity, total, context.handle, request⟩
    before base before completion after at result
  obtain ⟨value, heap, world, read, worldEq, _, outcome⟩ := result
  simp only [FileReadResult, reading] at read
  have afterWorld : after.world = nextWorld := worldEq.trans read.2.1
  have scratchBound : bytes.length ≤ context.words * 4 := by
    have bounded := read.2.2.1
    have := context.scratchSize
    dsimp [request] at bounded
    split at bounded <;> omega
  have kept := stored.frame read.2.2.2.footprint (by
    intro index bound inside
    dsimp only [Total.Configuration.destination, Total.Configuration.capacity, Address] at *
    rcases context.separate with left | right <;> omega)
  have afterTrace : after.world.calls = base.world.calls ++ List.replicate (reads + 1) .read := by
    rw [afterWorld, calls]
    change before.world.calls ++ [.read] = _
    rw [trace, List.replicate_succ', List.append_assoc]
  simp only [reading] at outcome
  by_cases empty : bytes = []
  · simp only [if_pos empty] at outcome
    have complete : total = (available file handle).length := by
      have : bytes.length = 0 := by rw [empty]; rfl
      omega
    constructor
    · intro _
      exact ⟨by simpa only [complete] using outcome.1,
        by simpa only [afterWorld, empty, List.length_nil, Nat.add_zero, complete] using advanced,
        by simpa only [readCount, complete] using afterTrace,
        by simpa only [outcome.2.1, complete, List.take_length] using kept⟩
    · intro next continues _
      rw [outcome.1] at continues
      cases continues
  · have bounded : total + bytes.length ≤ context.capacity := Nat.le_trans copiedBound fits
    simp only [if_neg empty, if_pos bounded] at outcome
    constructor
    · intro done
      obtain ⟨index, _, first | second | third⟩ := done <;> rw [outcome.1] at * <;> contradiction
    · intro next _ invariant
      have restored : restoreLocals before after = after := by
        unfold restoreLocals
        rw [← body.choose_spec.2]
      have counter := outcome.2.1.counter
      rw [restored] at counter
      change after.local? (reader.bindingId 1) = some (.signed .i32 (total + bytes.length)) at counter
      have counted : after.local? (reader.bindingId 1) = some (.signed .i32 next) := invariant.counter.counter
      rw [counted] at counter
      have same : next = total + bytes.length := by
        simp only [Option.some.injEq, Value.signed.injEq] at counter
        omega
      rw [same]
      have full : total + bytes.length < (available file handle).length → bytes.length = 65536 := by
        intro below
        have room : 65536 ≤ context.capacity - total := by
          by_cases enough : 65536 ≤ context.capacity - total
          · exact enough
          · have req : request = context.capacity - total + 1 := by dsimp [request]; split <;> omega
            rw [req] at bytesLength
            omega
        have req : request = 65536 := by dsimp [request]; split <;> omega
        rw [req] at bytesLength
        omega
      have nextReads : reads + 1 = (total + bytes.length + 65535) / 65536 := by
        have nonzero := List.length_pos_iff.mpr empty
        have divisible := aligned (by omega)
        have size : bytes.length ≤ 65536 := by
          have := Nat.min_le_left request ((available file handle).length - total)
          dsimp [request] at bytesLength
          split at bytesLength <;> omega
        omega
      have oldLength : (((available file handle).take total).flatMap Loop.encodeByte).length = total * 4 := by
        rw [Loop.encode_length, List.length_take, Nat.min_eq_left within]
      have copied : BytesWrite heap after.heap
          (context.destination + (((available file handle).take total).flatMap Loop.encodeByte).length)
          (bytes.flatMap Loop.encodeByte) := by simpa only [oldLength] using outcome.2.2
      have growing := kept.append copied
      have chunk : bytes = ((available file handle).drop total).take request := by
        simp only [bytes, available, List.drop_drop]
      have joined : (available file handle).take total ++ bytes =
          (available file handle).take (total + bytes.length) := by
        rw [List.take_add]
        congr 1
        rw [chunk]
        simp
      exact ⟨reads + 1, copiedBound, by intro below; rw [full below]; have := aligned (by omega); omega,
        nextReads, by simpa only [afterWorld, Nat.add_assoc] using advanced, afterTrace,
        by simpa only [← List.flatMap_append, joined] using growing⟩

def tracker (context : Total.Context base) (file : World.FileEntry) (handle : World.FileHandle)
    (fits : (available file handle).length ≤ context.capacity) : Total.Tracker context := {
  Inv := fun total heap world => Progress context.toConfiguration base file handle total heap world
  Done := fun completion heap world => Result context.toConfiguration base file handle completion heap world
  observe := step fits }

theorem declaration (context : Total.Context base)
    (cursor : World.FileCursor base.world context.handle file handle)
    (fits : (available file handle).length ≤ context.capacity)
    (inputRoom : base.heap.Readable context.address (context.words * 4))
    (outputRoom : base.heap.Readable context.destination (context.capacity * 4))
    (unique : HeapBlockBasesUnique base.heap) (noViews : base.i32ArrayViews = []) :
    ∃ value after, RunsStmt extractedProgram base (reader.bindingStatement 1) (.returned (some value)) after ∧
      Total.Result context.toConfiguration base value after ∧
      Result context.toConfiguration base file handle (.returned (some value)) after.heap after.world :=
  Total.declarationTracked context (tracker context file handle fits) (start cursor) inputRoom outputRoom unique noViews

#print axioms declaration

theorem Result.loaded (result : Result geometry base file handle completion heap world)
    (fits : (available file handle).length ≤ geometry.capacity) :
    heap.loadBytes geometry.destination ((available file handle).length * 4) =
      .ok ((available file handle).flatMap Loop.encodeByte) := by
  rw [← Loop.encode_length]
  exact result.2.2.2.loaded (by rw [Loop.encode_length]; omega)

theorem Result.tail (result : Result geometry base file handle completion heap world)
    (past : (available file handle).length * 4 ≤ index) (bound : index < geometry.capacity * 4) :
    heap.loadByte geometry.destination index = base.heap.loadByte geometry.destination index :=
  result.2.2.2.tail (by rwa [Loop.encode_length]) bound

theorem body (parameters : Total.Parameters before) (nonzero : parameters.address ≠ 0)
    (cursor : World.FileCursor before.world parameters.handle file handle)
    (fits : (available file handle).length ≤ parameters.capacity)
    (inputRoom : before.heap.Readable parameters.address (parameters.words * 4))
    (outputRoom : before.heap.Readable parameters.destination (parameters.capacity * 4))
    (unique : HeapBlockBasesUnique before.heap) (noViews : before.i32ArrayViews = []) :
    ∃ value after, RunsStmt extractedProgram before (reader.body.getD .skip) (.returned (some value)) after ∧
      Total.Result parameters.toConfiguration before value after ∧
      Result parameters.toConfiguration before file handle (.returned (some value)) after.heap after.world := by
  obtain ⟨value, after, declared, result, final⟩ :=
    declaration (Function.context parameters) cursor fits inputRoom outputRoom unique noViews
  obtain ⟨index, bounded, cells, scratch, output, unique, views, values, written⟩ := result
  exact ⟨value, restoreLocals before after, Function.enter parameters nonzero declared,
    ⟨index, bounded, ((FreshCellFrame.bindLocal before _ _).trans cells).restoreLocals,
      scratch, output, unique, views, values, written⟩, final⟩

/-- Actual public call: independent readable file/storage/size facts imply
    full-file bytes and observations, not an assumed execution or output. -/
theorem call (input : Function.Input before) (nonzero : input.address ≠ 0)
    (cursor : World.FileCursor before.world input.handle file handle)
    (fits : (available file handle).length ≤ input.capacity) :
    ∃ value after, RunsExpr extractedProgram before (.call reader.id (input.values.map Expr.value)) value after ∧
      Total.Result input.toConfiguration before value after ∧
      Result input.toConfiguration before file handle (.returned (some value)) after.heap after.world := by
  obtain ⟨value, after, executed, result, final⟩ := body input.parameters nonzero cursor fits
    input.inputRoom input.outputRoom input.unique input.noViews
  obtain ⟨index, bounded, cells, scratch, output, unique, views, values, written⟩ := result
  exact ⟨value, restoreLocals before after, input.invoke executed,
    ⟨index, bounded, (input.entryFrame.trans cells).restoreLocals,
      scratch, output, unique, views, values, written⟩, final⟩

#print axioms call

end ByteIoReadProof.File
