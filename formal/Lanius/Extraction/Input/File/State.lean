import Lanius.Extraction.Input.File.Source
import Lanius.Extraction.Input.Loop
import Lanius.Extraction.Host.File.Read
import Lanius.Extraction.Host.Effect

namespace Lanius.Extraction.Input.File

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.CompactOutput

structure Resources where
  output : I32ArrayView
  packed : I32ArrayView
  original : List Int
  capacity : Nat
  world : Lanius.World.State
  originalHandles : List Lanius.World.FileHandle
  handle : Lanius.World.FileHandle
  file : Lanius.World.FileEntry
  handles : world.fileHandles = originalHandles ++ [handle]
  fresh : ∀ older ∈ originalHandles, older.id ≠ handle.id
  readable : handle.readable = true
  fileFound : world.file? handle.path = some file
  originalLength : original.length = output.length
  capacityBound : capacity ≤ output.length
  outputBound : output.length ≤ 2147483647
  scratch : 65536 ≤ packed.length * 4
  outputPacked : output.root ≠ packed.root

def Resources.bytes (resources : Resources) := resources.file.bytes.drop resources.handle.offset
def Resources.writes (resources : Resources) := CellSet.union (CellSet.singleton resources.output.root) (CellSet.singleton resources.packed.root)
def Resources.consumed (resources : Resources) := min resources.bytes.length (resources.capacity + 1)
def Resources.result (resources : Resources) : Int :=
  if resources.bytes.length ≤ resources.capacity then resources.bytes.length else -2
def Resources.finalWorld (resources : Resources) (reads : Nat) : Lanius.World.State := {
  resources.world with
  fileHandles := resources.originalHandles ++ [{ resources.handle with offset := resources.handle.offset + resources.consumed }]
  calls := resources.world.calls ++ List.replicate reads .read }

structure Memory extends Resources where
  totalCell : CellId
  outputTotal : output.root ≠ totalCell
  packedTotal : packed.root ≠ totalCell

def Memory.bytes (memory : Memory) : List UInt8 := memory.file.bytes.drop memory.handle.offset
def Memory.outputValues (memory : Memory) (processed : List UInt8) : List Int := copiedBuffer [] memory.original processed
def Memory.writes (memory : Memory) : CellSet :=
  CellSet.union (CellSet.union (CellSet.singleton memory.output.root) (CellSet.singleton memory.packed.root))
    (CellSet.singleton memory.totalCell)

def Memory.worldAt (memory : Memory) (processed : Nat) (reads : Nat) : Lanius.World.State := {
  memory.world with
  fileHandles := memory.originalHandles ++ [{ memory.handle with offset := memory.handle.offset + processed }]
  calls := memory.world.calls ++ List.replicate reads .read }

theorem Memory.worldAt_zero (memory : Memory) : memory.worldAt 0 0 = memory.world := by
  simp only [Memory.worldAt, Nat.add_zero, List.replicate_zero, List.append_nil, ← memory.handles]

theorem Memory.handleAt (memory : Memory) (processed reads : Nat) :
    (memory.worldAt processed reads).handle? memory.handle.id =
      some { memory.handle with offset := memory.handle.offset + processed } :=
  Lanius.World.handle_appended_fresh (opened := { memory.handle with offset := memory.handle.offset + processed })
    memory.fresh rfl

theorem Memory.fileAt (memory : Memory) (processed reads : Nat) :
    (memory.worldAt processed reads).file? memory.handle.path = some memory.file := memory.fileFound

theorem Memory.afterRead (memory : Memory) (processed reads count : Nat) :
    { memory.worldAt processed reads with
      calls := (memory.worldAt processed reads).calls ++ [.read]
      fileHandles := Lanius.World.replaceHandle (memory.worldAt processed reads).fileHandles {
        memory.handle with offset := memory.handle.offset + processed + count } } =
      memory.worldAt (processed + count) (reads + 1) := by
  have replaced := Lanius.World.replaceHandle_appended_fresh
    (opened := { memory.handle with offset := memory.handle.offset + processed })
    (memory.handle.offset + processed + count) memory.fresh
  dsimp only [Memory.worldAt]
  rw [show Lanius.World.replaceHandle
      (memory.originalHandles ++ [{ memory.handle with offset := memory.handle.offset + processed }])
      { memory.handle with offset := memory.handle.offset + processed + count } =
        memory.originalHandles ++ [{ memory.handle with offset := memory.handle.offset + processed + count }] from replaced]
  simp only [List.replicate_succ', List.append_assoc, Nat.add_assoc]

structure Buffers (memory : Memory) (processed : List UInt8) (state : State) : Prop where
  registry : Allocation.Registry state
  representable : Host.RepresentableViews state
  disjoint : state.i32ArrayViews.Pairwise I32ViewRangesDisjoint
  outputMember : memory.output ∈ state.i32ArrayViews
  packedMember : memory.packed ∈ state.i32ArrayViews
  outputLocal : state.local? 1 = some (.slice i32 memory.output.root [] 0 memory.output.length)
  packedLocal : state.local? 3 = some (.slice i32 memory.packed.root [] 0 memory.packed.length)
  handleLocal : state.local? 0 = some (.signed .i32 memory.handle.id)
  capacityLocal : state.local? 2 = some (.signed .i32 memory.capacity)
  pointerLocal : state.local? 4 = some (.pointer memory.packed.address)
  total : (Assertion.localPointsTo 5 memory.totalCell (some (.signed .i32 processed.length))).holds state
  outputContents : state.cellEntry? memory.output.root = some {
    id := memory.output.root, value := some (.array (signedI32Values (memory.outputValues processed))) }
  capacity : processed.length ≤ memory.capacity
  stable : ∀ id ∈ [0, 1, 2, 3, 4], ∀ cell, state.cellId? id = some cell → ¬ memory.writes cell

structure Invariant (memory : Memory) (processed : List UInt8) (reads : Nat) (state : State) : Prop
    extends Buffers memory processed state where
  world : state.world = memory.worldAt processed.length reads

theorem Buffers.bindTemporary (invariant : Buffers memory processed before) (id : VarId) (value : Value)
    (temporary : 5 < id) : Buffers memory processed (before.bindLocal id value) := by
  have different (name : VarId) (small : name ≤ 5) : id ≠ name := by
    exact Ne.symm (Nat.ne_of_lt (Nat.lt_of_le_of_lt small temporary))
  refine ⟨invariant.registry.bindLocal id value, invariant.representable.bindLocal invariant.registry id value,
    invariant.disjoint, invariant.outputMember, invariant.packedMember, ?_, ?_, ?_, ?_, ?_, ?_, ?_, invariant.capacity, ?_⟩
  · exact (bindLocal_preserves_other_local invariant.registry.wellFormed (different 1 (by decide))).trans invariant.outputLocal
  · exact (bindLocal_preserves_other_local invariant.registry.wellFormed (different 3 (by decide))).trans invariant.packedLocal
  · exact (bindLocal_preserves_other_local invariant.registry.wellFormed (different 0 (by decide))).trans invariant.handleLocal
  · exact (bindLocal_preserves_other_local invariant.registry.wellFormed (different 2 (by decide))).trans invariant.capacityLocal
  · exact (bindLocal_preserves_other_local invariant.registry.wellFormed (different 4 (by decide))).trans invariant.pointerLocal
  · exact bindLocal_preserves_localPointsTo_of_ne before id 5 value memory.totalCell _
      invariant.registry.wellFormed (different 5 (by decide)) invariant.total
  · exact ((bindLocal_effect before id value).oldCells memory.output.root
      (invariant.registry.root_lt_next invariant.outputMember) (by simp [CellSet.empty])).trans invariant.outputContents
  · intro name member cell found
    have small : name ≤ 4 := by
      simp only [List.mem_cons, List.not_mem_nil, or_false] at member
      rcases member with rfl | rfl | rfl | rfl | rfl <;> decide
    apply invariant.stable name member cell
    simpa [State.cellId?, State.bindLocal, State.bindCell, different name (Nat.le_trans small (by decide))] using found

theorem Buffers.transport (invariant : Buffers memory processed before)
    (effect : Host.Effect writes before after) (registry : Allocation.Registry after)
    (representable : Host.RepresentableViews after)
    (outputKept : ¬ writes memory.output.root) (totalKept : ¬ writes memory.totalCell)
    (localsKept : ∀ id ∈ [0, 1, 2, 3, 4], ∀ cell, before.cellId? id = some cell → ¬ writes cell) :
    Buffers memory processed after := by
  refine ⟨registry, representable, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, invariant.capacity, ?_⟩
  · simpa only [effect.views] using invariant.disjoint
  · simpa only [effect.views] using invariant.outputMember
  · simpa only [effect.views] using invariant.packedMember
  · exact effect.preservesLocal invariant.registry.wellFormed invariant.outputLocal (localsKept 1 (by simp))
  · exact effect.preservesLocal invariant.registry.wellFormed invariant.packedLocal (localsKept 3 (by simp))
  · exact effect.preservesLocal invariant.registry.wellFormed invariant.handleLocal (localsKept 0 (by simp))
  · exact effect.preservesLocal invariant.registry.wellFormed invariant.capacityLocal (localsKept 2 (by simp))
  · exact effect.preservesLocal invariant.registry.wellFormed invariant.pointerLocal (localsKept 4 (by simp))
  · exact ⟨by simpa only [State.cellId?, effect.locals] using invariant.total.1,
      effect.preservesEntry invariant.registry.wellFormed invariant.total.2 totalKept⟩
  · exact effect.preservesEntry invariant.registry.wellFormed invariant.outputContents outputKept
  · intro id member cell found
    apply invariant.stable id member cell
    simpa only [State.cellId?, effect.locals] using found

theorem Buffers.pureScalar (invariant : Buffers memory processed before)
    (effect : ModifiesOnly (CellSet.singleton cell) before after) (valid : StateWellFormed after)
    (scalar : before.cellEntry? cell = some { id := cell, value := some (.signed .i32 value) })
    (totalKept : memory.totalCell ≠ cell)
    (localsKept : ∀ id ∈ [0, 1, 2, 3, 4], before.cellId? id ≠ some cell) : Buffers memory processed after := by
  have noView : ∀ view ∈ before.i32ArrayViews, ¬ CellSet.singleton cell view.root := by
    intro view member same
    change view.root = cell at same
    exact invariant.registry.notScalar member (same.symm ▸ scalar)
  have registry := invariant.registry.transport (CellEffect.ofModifiesOnly effect valid)
    (HeapFrame.ofStoreEffect effect.toStoreEffect) (fun view member written => False.elim (noView view member written))
  have representable := invariant.representable.transport invariant.registry (CellEffect.ofModifiesOnly effect valid)
    (HeapFrame.ofStoreEffect effect.toStoreEffect) (fun view member written => False.elim (noView view member written))
  apply invariant.transport (Host.Effect.ofPure effect valid) registry representable
    (noView memory.output invariant.outputMember) totalKept
  intro id member foundCell found same
  change foundCell = cell at same
  exact localsKept id member (same ▸ found)

/-- Reassemble the outer-loop invariant after a completed chunk. The
functional obligations are the new byte prefix and its total; the I/O frame
retains the caller's parameters, unrelated cells, and buffer registrations. -/
theorem Buffers.finish (invariant : Buffers memory processed before)
    (effect : Host.Effect memory.writes before after) (registry : Allocation.Registry after)
    (representable : Host.RepresentableViews after)
    (totalContents : after.cellEntry? memory.totalCell = some {
      id := memory.totalCell, value := some (.signed .i32 next.length) })
    (outputContents : after.cellEntry? memory.output.root = some {
      id := memory.output.root, value := some (.array (signedI32Values (memory.outputValues next))) })
    (capacity : next.length ≤ memory.capacity) : Buffers memory next after := by
  refine ⟨registry, representable, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, outputContents, capacity, ?_⟩
  · simpa only [effect.views] using invariant.disjoint
  · simpa only [effect.views] using invariant.outputMember
  · simpa only [effect.views] using invariant.packedMember
  · exact effect.preservesLocal invariant.registry.wellFormed invariant.outputLocal (invariant.stable 1 (by simp))
  · exact effect.preservesLocal invariant.registry.wellFormed invariant.packedLocal (invariant.stable 3 (by simp))
  · exact effect.preservesLocal invariant.registry.wellFormed invariant.handleLocal (invariant.stable 0 (by simp))
  · exact effect.preservesLocal invariant.registry.wellFormed invariant.capacityLocal (invariant.stable 2 (by simp))
  · exact effect.preservesLocal invariant.registry.wellFormed invariant.pointerLocal (invariant.stable 4 (by simp))
  · exact ⟨by simpa only [State.cellId?, effect.locals] using invariant.total.1, totalContents⟩
  · intro id member cell found
    exact invariant.stable id member cell (by simpa only [State.cellId?, effect.locals] using found)

theorem Memory.outputValues_append (memory : Memory) (processed bytes : List UInt8) :
    (memory.outputValues processed).take processed.length ++ bytes.map (fun byte => (byte.toNat : Int)) ++
      (memory.outputValues processed).drop (processed.length + bytes.length) = memory.outputValues (processed ++ bytes) := by
  simp only [Memory.outputValues, copiedBuffer, List.nil_append, List.map_append, List.length_append]
  rw [show processed.length = (processed.map (fun byte => (byte.toNat : Int))).length from (List.length_map _).symm]
  simp [List.take_append, List.drop_append, List.drop_drop, List.append_assoc]

/-- A byte-heap write to scratch leaves all other registered views intact.
Pairwise disjointness can be used in either order; distinct roots exclude
the reflexive case. -/
theorem readEffect (initial : Allocation.Registry before) (representable : Host.RepresentableViews before)
    (disjoint : before.i32ArrayViews.Pairwise I32ViewRangesDisjoint)
    (member : scratch ∈ before.i32ArrayViews) (frame : Host.Frame before after)
    (registered : Allocation.Registry after)
    (preserved : Host.PreservesViews before after (I32ViewRangesDisjoint scratch)) :
    Host.Effect (CellSet.singleton scratch.root) before after := by
  apply Host.Effect.ofHost frame initial registered
  intro view present untouched
  obtain ⟨words, _, contents⟩ := initial.storage present
  have apart := initial.apart member present (by simpa [CellSet.singleton, eq_comm] using untouched)
  have copied := preserved disjoint view present apart words
    (by simp only [readCellProjection, initial.roots view present, contents, projectedValue])
    (representable view present words contents)
  exact copied.trans contents.symm

end Lanius.Extraction.Input.File
