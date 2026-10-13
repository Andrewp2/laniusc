import verified_compiler.tests.direct_byte_io_read_interface_function
import Lanius.World.FileRead
import Lanius.Memory.BufferPrefix

namespace ByteIoReadInterface.File

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics ByteIoReadProof

/-- The file suffix and observations are data predicates, independent of
execution. They intentionally do not import the old whole-reader proof. -/
def available (file : World.FileEntry) (handle : World.FileHandle) := file.bytes.drop handle.offset

def Progress (geometry : Configuration) (origin : State) (file : World.FileEntry) (handle : World.FileHandle)
    (total : Nat) (heap : Heap) (world : World.State) : Prop :=
  ∃ reads, total ≤ (available file handle).length ∧
    (total < (available file handle).length → total % 65536 = 0) ∧
    reads = (total + 65535) / 65536 ∧
    World.FileCursor world geometry.handle file { handle with offset := handle.offset + total } ∧
    world.calls = origin.world.calls ++ List.replicate reads .read ∧
    BufferPrefix origin.heap heap geometry.destination (geometry.capacity * 4)
      (((available file handle).take total).flatMap Loop.encodeByte)

/-- Exact content, unchanged output tail, returned length, cursor and number
of read observations, including the final end-of-file probe. -/
def Result (geometry : Configuration) (origin : State) (file : World.FileEntry) (handle : World.FileHandle)
    (completion : Completion) (heap : Heap) (world : World.State) : Prop :=
  completion = .returned (some (.signed .i32 (available file handle).length)) ∧
    World.FileCursor world geometry.handle file { handle with offset := handle.offset + (available file handle).length } ∧
    world.calls = origin.world.calls ++ List.replicate (((available file handle).length + 65535) / 65536 + 1) .read ∧
    BufferPrefix origin.heap heap geometry.destination (geometry.capacity * 4)
      ((available file handle).flatMap Loop.encodeByte)

variable {origin base before after : State} {context : Context origin base}
  {file : World.FileEntry} {handle : World.FileHandle} {total next : Nat} {completion : Completion}

theorem start {geometry : Configuration} (cursor : World.FileCursor origin.world geometry.handle file handle) :
    Progress geometry origin file handle 0 origin.heap origin.world :=
  ⟨0, Nat.zero_le _, by intros; rfl, by decide,
    by simpa only [Nat.add_zero] using cursor, by simp, BufferPrefix.refl⟩

/-- Observe the host/copy result already derived from the real outer body.
No repeated evaluator execution or local-cell identity is involved. -/
theorem step (fits : (available file handle).length ≤ context.capacity)
    (current : Invariant context before total)
    (tracked : Progress context.toConfiguration origin file handle total before.heap before.world)
    (result : Step.Result (specification context.toConfiguration total) before completion after next) :
    (completion = .next → Progress context.toConfiguration origin file handle next after.heap after.world) ∧
    (Ends completion next → Result context.toConfiguration origin file handle completion after.heap after.world) := by
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
  change Step.Result ⟨context.address, context.destination, context.capacity, total, context.handle, request⟩
    before completion after next at result
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
    dsimp only [Configuration.destination, Configuration.capacity, Address] at *
    rcases context.separate with left | right <;> omega)
  have afterTrace : after.world.calls = origin.world.calls ++ List.replicate (reads + 1) .read := by
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
    · intro continues
      rw [outcome.2.1] at continues
      cases continues
    · intro _
      exact ⟨by simpa only [complete] using outcome.2.1,
        by simpa only [afterWorld, empty, List.length_nil, Nat.add_zero, complete] using advanced,
        by simpa only [readCount, complete] using afterTrace,
        by simpa only [outcome.2.2, complete, List.take_length] using kept⟩
  · have bounded : total + bytes.length ≤ context.capacity := Nat.le_trans copiedBound fits
    simp only [if_neg empty, if_pos bounded] at outcome
    constructor
    · intro _
      rw [outcome.1]
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
    · intro done
      rcases done with first | second | third <;> rw [outcome.2.1] at * <;> contradiction

def tracker (context : Context origin base) (file : World.FileEntry) (handle : World.FileHandle)
    (fits : (available file handle).length ≤ context.capacity) : Tracker context := {
  Inv := fun total heap world => Progress context.toConfiguration origin file handle total heap world
  Done := fun completion heap world => Result context.toConfiguration origin file handle completion heap world
  observe := step fits }

theorem Result.loaded (result : Result geometry origin file handle completion heap world)
    (fits : (available file handle).length ≤ geometry.capacity) :
    heap.loadBytes geometry.destination ((available file handle).length * 4) =
      .ok ((available file handle).flatMap Loop.encodeByte) := by
  rw [← Loop.encode_length]
  exact result.2.2.2.loaded (by rw [Loop.encode_length]; omega)

theorem Result.tail (result : Result geometry origin file handle completion heap world)
    (past : (available file handle).length * 4 ≤ index) (bound : index < geometry.capacity * 4) :
    heap.loadByte geometry.destination index = origin.heap.loadByte geometry.destination index :=
  result.2.2.2.tail (by rwa [Loop.encode_length]) bound

/-- The original full-file public domain, with caller locals and native
view metadata explicitly restored in the conclusions. -/
theorem call (input : Function.Input before) (nonzero : input.address ≠ 0)
    (cursor : World.FileCursor before.world input.handle file handle)
    (fits : (available file handle).length ≤ input.capacity) :
    ∃ value after, RunsExpr extractedProgram before (.call reader.id (input.values.map Expr.value)) value after ∧
      ByteIoReadInterface.Result input.toConfiguration before value after ∧
      Result input.toConfiguration before file handle (.returned (some value)) after.heap after.world ∧
      after.locals = before.locals ∧ after.i32ArrayViews = before.i32ArrayViews := by
  exact Function.callTracked input nonzero (tracker input.context file handle fits) (start cursor)

#print axioms step
#print axioms call

end ByteIoReadInterface.File
