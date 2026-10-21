import SelfCore
import Lanius.Core.Bindings
import Lanius.Semantics.ExpressionProof
import Lanius.Semantics.HostCall
import verified_compiler.tests.direct_ir_allocation

namespace HostViewsProof

open Lanius Lanius.Core Lanius.Semantics Lanius.Typing Lanius.Memory

private def stdout := Extracted.«verified::host».Functions.«write_stdout».core
private def reader := Extracted.«verified::host».Functions.«read».core

/-- The actual extractor's stdout declaration, with live registered arrays.
    This specifies the modeled host service, not the native syscall bridge. -/
theorem write (access : before.I32ViewsAccessible extractedProgram types)
    (readable : before.heap.Readable pointer count) :
    ∃ bytes after, RunsExpr extractedProgram before
      (.call stdout.id [.value (.pointer pointer), .value (.unsigned .usize count)]) (World.i32Result count) after ∧
      after.I32ViewsAccessible extractedProgram types ∧ bytes.length = count ∧
      after.world.standardOutput = before.world.standardOutput ++ bytes := by
  apply RunsExpr.writeStdoutViews (function := stdout)
    (bindings := [(stdout.argumentId 0, .pointer pointer), (stdout.argumentId 1, .unsigned .usize count)])
    ?_ rfl rfl rfl access readable
  core_lookup

/-- The actual extractor's read declaration for arbitrary file state/handle.
    A readable destination prevents storage traps; invalid handles may return -1. -/
theorem read (access : before.I32ViewsAccessible extractedProgram types)
    (readable : before.heap.Readable pointer count) :
    ∃ value after, RunsExpr extractedProgram before
      (.call reader.id [.value (.signed .i32 handle), .value (.pointer pointer), .value (.unsigned .usize count)])
      value after ∧ after.I32ViewsAccessible extractedProgram types ∧
      (before.I32ViewsUnique → after.I32ViewsCoherent extractedProgram types) ∧
      (before.I32ViewsReady extractedProgram types → after.I32ViewsReady extractedProgram types) ∧
      ReadEffect before handle pointer count value after := by
  apply RunsExpr.readViews (function := reader)
    (bindings := [(reader.argumentId 0, .signed .i32 handle), (reader.argumentId 1, .pointer pointer),
      (reader.argumentId 2, .unsigned .usize count)]) ?_ rfl rfl rfl access readable
  core_lookup

/-- The same actual declaration on the extractor's raw scratch route. Its
    byte/file effects are shared with the registered-view contract above. -/
theorem readRaw (noViews : before.i32ArrayViews = []) (unique : HeapBlockBasesUnique before.heap)
    (readable : before.heap.Readable pointer count) :
    ∃ value heap world, RunsExpr extractedProgram before
      (.call reader.id [.value (.signed .i32 handle), .value (.pointer pointer), .value (.unsigned .usize count)])
      value { before with heap, world } ∧
      FileReadResult before.heap before.world handle pointer count value heap world := by
  apply RunsExpr.readRaw (function := reader)
    (bindings := [(reader.argumentId 0, .signed .i32 handle), (reader.argumentId 1, .pointer pointer),
      (reader.argumentId 2, .unsigned .usize count)]) ?_ rfl rfl rfl noViews unique readable
  core_lookup

/-- The real read declaration with the extractor's slice-pointer convention.
    Validity is checked in the state after operand effects; the pointer's
    requested range follows from the descriptor, not an assumed raw read. -/
theorem readSlice
    (operand : RunsExpr extractedProgram before expression slice middle)
    (valid : I32SliceValid extractedProgram types middle slice length)
    (ready : middle.I32ViewsReady extractedProgram types) (bound : count ≤ length * 4) :
    ∃ value after, RunsExpr extractedProgram before
      (.call reader.id [.value (.signed .i32 handle), .i32SliceDataPtr expression,
        .value (.unsigned .usize count)]) value after ∧
      after.I32ViewsReady extractedProgram types ∧ after.I32ViewsCoherent extractedProgram types ∧
      PointerReadEffect extractedProgram before (.i32SliceDataPtr expression) handle count value after := by
  apply RunsExpr.readSlice (function := reader)
    (bindings := fun pointer => [(reader.argumentId 0, .signed .i32 handle), (reader.argumentId 1, .pointer pointer),
      (reader.argumentId 2, .unsigned .usize count)]) ?_ rfl rfl (fun _ => rfl) operand valid ready bound
  core_lookup

/-- Allocate and construct the actual raw scratch slice, then pass its pointer
    to the actual read declaration. No raw readability premise is left over. -/
theorem readScratch (words : Nat) (positive : 0 < words) (bounded : words ≤ 536870911)
    (formed : before.CellsWellFormed) (ready : before.I32ViewsReady extractedProgram types)
    (noViews : before.i32ArrayViews = [])
    (capacity : ∀ available, before.heap.remaining = some available → words * 4 ≤ available)
    (bound : count ≤ words * 4) :
    ∃ allocated scratch value after,
      RunsExpr extractedProgram before (.call Extracted.«verified::host».Functions.«alloc_i32».core.id
        [.value (.signed .i32 words)]) (.pointer before.heap.borrowedAddress) allocated ∧
      RunsExpr extractedProgram allocated (.call Extracted.«verified::host».Functions.«i32_slice_from_raw_parts».core.id
        [.value (.pointer before.heap.borrowedAddress), .value (.signed .i32 words)])
      (.rawSlice (.scalar (.signed .i32)) before.heap.borrowedAddress words) scratch ∧
      HeapReads before.heap scratch.heap ∧
      scratch.world = World.record before.world .alloc ∧
      RunsExpr extractedProgram scratch (.call reader.id [.value (.signed .i32 handle),
        .i32SliceDataPtr (.value (.rawSlice (.scalar (.signed .i32)) before.heap.borrowedAddress words)),
        .value (.unsigned .usize count)]) value after ∧
      after.I32ViewsReady extractedProgram types ∧ after.I32ViewsCoherent extractedProgram types ∧
      after.heap.Readable before.heap.borrowedAddress (words * 4) ∧
      FileReadResult scratch.heap scratch.world handle before.heap.borrowedAddress count value after.heap after.world := by
  obtain ⟨allocated, scratch, allocate, construct, _, _, storage, valid, reads, world, views⟩ :=
    IRAllocationProof.actualScratch words positive bounded formed ready noViews capacity
  obtain ⟨value, after, run, storage, coherent, effect⟩ := readSlice (handle := handle) (.ofStable .value rfl) valid storage bound
  have result := (effect.atPointer (.ofStable (.rawSliceDataPtr .value) rfl)).noViews views
  exact ⟨allocated, scratch, value, after, allocate, construct, reads, world, run, storage, coherent,
    result.readable (by cases valid with | raw readable => exact readable), result⟩

/-- Strengthened contract for the actual stdout declaration: array/cell
    contents are unchanged, not just assigned some value of the same type. -/
theorem writeFramed (access : before.I32ViewsAccessible extractedProgram types)
    (readable : before.heap.Readable pointer count)
    (apart : before.i32ArrayViews.Pairwise I32ArrayView.Disjoint) (unique : (before.cells.map Cell.id).Nodup) :
    ∃ bytes heap world, RunsExpr extractedProgram before
      (.call stdout.id [.value (.pointer pointer), .value (.unsigned .usize count)]) (World.i32Result count)
      { before with heap, world } ∧ ({ before with heap } : State).I32ViewsCoherent extractedProgram types ∧
      heap.loadBytes pointer count = .ok bytes ∧ bytes.length = count ∧
      world = { World.record before.world .writeStdout with standardOutput := before.world.standardOutput ++ bytes } := by
  apply RunsExpr.writeStdoutFramed (function := stdout)
    (bindings := [(stdout.argumentId 0, .pointer pointer), (stdout.argumentId 1, .unsigned .usize count)])
    ?_ rfl rfl rfl access readable apart unique
  core_lookup

#print axioms write
#print axioms read
#print axioms readRaw
#print axioms readSlice
#print axioms readScratch
#print axioms writeFramed

end HostViewsProof
