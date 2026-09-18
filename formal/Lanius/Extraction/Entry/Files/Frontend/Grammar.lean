import Lanius.Extraction.Entry.Files.Frontend.Source

namespace Lanius.Extraction.Entry.Files
open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

variable {program : CoreSynthesis.Program.CheckedProgram artifacts}
variable {pipeline : File.Load.Pipeline program}

/-- The initialized allocation contains exactly the grammar words, not a
possibly padded buffer that happens to have the right prefix. Its physical
capacity and the decoder's count are both checked source facts. -/
theorem FrontendSource.grammarWords
    (checked : FrontendSource pipeline stage buffers aliases literal framing)
    (evidence : Grammar.LiteralEvidence Grammar.indexedLanius literal.text)
    (memory : Grammar.Memory literal.setup.cursor.locals) (selected : memory.values = evidence.values)
    (originalRead : original.local? literal.setup.cursor.locals.destination = some
      (.slice (.scalar (.signed .i32)) memory.destinationCell [] 0 memory.untouched.length))
    (readyRegistry : Allocation.Registry ready)
    (initialized : ready.cellEntry? memory.destinationCell = some {
      id := memory.destinationCell, value := some (.array (signedI32Values (memory.buffer memory.values))) })
    (storage : BufferStorage stage.grammar 2179 original
      (ready.bindLocal pipeline.path.argument (.signed .i32 1))) :
    storage.values = evidence.values.map Int.ofNat := by
  have exactRead := storage.originalRead.symm.trans (checked.grammarBinding ▸ originalRead)
  have root : storage.view.root = memory.destinationCell := by injection exactRead with same; injection same
  have length : memory.untouched.length = 2179 := by
    injection exactRead with same
    injection same
    omega
  have count := memory.count
  rw [checked.grammarCount] at count
  have valuesLength : memory.values.length = 2179 := by omega
  have exactWords : memory.buffer memory.values = evidence.values.map Int.ofNat := by
    unfold Grammar.Memory.buffer BufferCopy.buffer
    rw [List.length_map, valuesLength,
      List.drop_eq_nil_of_le (by omega : memory.untouched.length ≤ 2179), List.append_nil, selected]
  have current := ((bindLocal_effect ready pipeline.path.argument (.signed .i32 1)).oldCells memory.destinationCell
    (StateWellFormed.cell_lt_next_of_entry readyRegistry.wellFormed initialized) (by simp [CellSet.empty])).trans initialized
  rw [← root, storage.stored] at current
  have encoded : signedI32Values storage.values = signedI32Values (memory.buffer memory.values) := by
    exact Value.array.inj (Option.some.inj (congrArg Cell.value (Option.some.inj current)))
  exact (signedI32Values_injective encoded).trans exactWords

end Lanius.Extraction.Entry.Files
