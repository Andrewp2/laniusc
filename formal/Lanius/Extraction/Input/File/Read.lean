import Lanius.Extraction.Input.File.Request
import Lanius.Extraction.CompactOutput.Byte

namespace Lanius.Extraction.Input.File

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.CompactOutput

def Memory.chunk (memory : Memory) (processed : List UInt8) : List UInt8 :=
  (memory.file.bytes.drop (memory.handle.offset + processed.length)).take (requestSize (memory.capacity - processed.length))

def sizeEntry (memory : Memory) (processed : List UInt8) (before : State) : State :=
  before.bindLocal 8 (.unsigned .usize (requestSize (memory.capacity - processed.length)))

structure ReadResult (memory : Memory) (processed : List UInt8) (reads : Nat) (before after : State) : Prop
    extends Buffers memory processed after where
  request : after.local? 6 = some (.signed .i32 (requestSize (memory.capacity - processed.length)))
  remaining : after.local? 7 = some (.signed .i32 (Int.ofNat (memory.capacity - processed.length)))
  copied : Host.Copied memory.packed (memory.chunk processed) after
  world : after.world = memory.worldAt (processed.length + (memory.chunk processed).length) (reads + 1)
  effect : Host.Effect (CellSet.singleton memory.packed.root) (sizeEntry memory processed before) after

/-- The actual host call advances exactly the selected handle, returns the
requested prefix, and leaves the destination buffer and total untouched. -/
theorem readNext (reader : Host.CheckedExternal program .read 3)
    (invariant : Buffers memory processed before)
    (request : before.local? 6 = some (.signed .i32 (requestSize (memory.capacity - processed.length))))
    (remaining : before.local? 7 = some (.signed .i32 (Int.ofNat (memory.capacity - processed.length))))
    (world : before.world = memory.worldAt processed.length reads) :
    ∃ after, Evaluates program (sizeEntry memory processed before) (.call reader.function.id [read 0, read 4, read 8])
        (.signed .i32 (memory.chunk processed).length) after ∧ ReadResult memory processed reads before after := by
  let ready := sizeEntry memory processed before
  have buffers := invariant.bindTemporary 8 (.unsigned .usize (requestSize (memory.capacity - processed.length))) (by decide)
  have size : ready.local? 8 = some (.unsigned .usize (requestSize (memory.capacity - processed.length))) :=
    Assertion.localPointsTo_local _ _ _ _ (bindLocal_owns_fresh before 8 _ invariant.registry.wellFormed)
  have requestAt : ready.local? 6 = some (.signed .i32 (requestSize (memory.capacity - processed.length))) :=
    (bindLocal_preserves_other_local invariant.registry.wellFormed (show (8 : VarId) ≠ 6 by decide)).trans request
  have remainingAt : ready.local? 7 = some (.signed .i32 (Int.ofNat (memory.capacity - processed.length))) :=
    (bindLocal_preserves_other_local invariant.registry.wellFormed (show (8 : VarId) ≠ 7 by decide)).trans remaining
  have bounds := requestSize_bounds (memory.capacity - processed.length)
  obtain ⟨after, run, registry, frame, worldAfter, copied, preserved⟩ := Host.File.evaluatesRead reader
    buffers.registry memory.handle.id { memory.handle with offset := memory.handle.offset + processed.length }
    memory.file (requestSize (memory.capacity - processed.length))
    (by change before.world.handle? _ = _; rw [world]; exact memory.handleAt _ _)
    memory.readable
    (by change before.world.file? _ = _; rw [world]; exact memory.fileAt _ _)
    buffers.packedMember (Nat.le_trans bounds.2.1 memory.scratch) (Nat.le_trans bounds.2.1 (by decide))
    (.cons (local_evaluates program buffers.handleLocal) (.cons (local_evaluates program buffers.pointerLocal)
      (.cons (local_evaluates program size) (.nil _ _))))
  have effect := readEffect buffers.registry buffers.representable buffers.disjoint buffers.packedMember frame registry preserved
  have kept := buffers.transport effect registry frame.representable memory.outputPacked memory.packedTotal.symm
    (by
      intro id member cell binding changed
      exact buffers.stable id member cell binding (Or.inl (Or.inr changed)))
  refine ⟨after, run, ⟨kept, frame.preservesLocal buffers.registry requestAt (by intro values same; cases same),
    frame.preservesLocal buffers.registry remainingAt (by intro values same; cases same), copied, ?_, effect⟩⟩
  exact worldAfter.trans (by
    change ({ before.world with calls := before.world.calls ++ [.read], fileHandles :=
      Lanius.World.replaceHandle before.world.fileHandles { memory.handle with offset :=
        memory.handle.offset + processed.length + (memory.chunk processed).length } } : Lanius.World.State) = _
    rw [world]
    exact memory.afterRead _ _ _)

/-- Compose the usize conversion and effectful count initializer with the
real count guards, restoring both temporary scopes at the boundary. -/
theorem executesRead (reader : Host.CheckedExternal program .read 3)
    (invariant : Buffers memory processed before)
    (request : before.local? 6 = some (.signed .i32 (requestSize (memory.capacity - processed.length))))
    (remaining : before.local? 7 = some (.signed .i32 (Int.ofNat (memory.capacity - processed.length))))
    (world : before.world = memory.worldAt processed.length reads)
    (sizeFit : 65536 < unsignedModulus program.target .usize)
    (completion : Completion) (post : State → Prop)
    (continuation : ∀ middle, ReadResult memory processed reads before middle →
      ∃ after, Executes program (middle.bindLocal 9 (.signed .i32 (memory.chunk processed).length))
        countGuards completion after ∧ post (restoreLocals before after)) :
    ∃ after, Executes program before (readChunk reader.function.id) completion after ∧ post after := by
  have size : Evaluates program before (.cast (.unsigned .usize) (read 6))
      (.unsigned .usize (requestSize (memory.capacity - processed.length))) before := by
    apply evaluatesCast (local_evaluates program request)
    change (Except.ok (Value.unsigned .usize
      (((requestSize (memory.capacity - processed.length)) : Int) % (unsignedModulus program.target .usize : Int)).toNat) :
        Except Lanius.Trap Value) = .ok (.unsigned .usize (requestSize (memory.capacity - processed.length)))
    rw [Int.emod_eq_of_lt (Int.natCast_nonneg _) (Int.ofNat_lt.mpr
      (Nat.lt_of_le_of_lt (requestSize_bounds _).2.1 sizeFit))]
    rfl
  obtain ⟨middle, call, result⟩ := readNext reader invariant request remaining world
  obtain ⟨after, run, done⟩ := continuation middle result
  exact ⟨restoreLocals before (restoreLocals middle after), executesLetLocal size (executesLetLocal call run), done⟩

end Lanius.Extraction.Input.File
