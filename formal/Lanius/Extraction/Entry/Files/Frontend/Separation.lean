import Lanius.Extraction.Entry.Files.Frontend.Resources

namespace Lanius.Extraction.Entry.Files
open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.Frontend

variable {program : CoreSynthesis.Program.CheckedProgram artifacts}
variable {pipeline : File.Load.Pipeline program}

/-- Derive separation of a semantic/output allocation from every frontend
buffer using their actual live reads and distinct source declarations. -/
theorem FrontendSource.apart
    (checked : FrontendSource pipeline stage buffers aliases literal framing)
    (data : SyntaxData)
    (reads : stage.Reads data capacity (ready.bindLocal pipeline.path.argument (.signed .i32 1)))
    (other : BufferStorage otherId otherCount original (ready.bindLocal pipeline.path.argument (.signed .i32 1)))
    (otherSource : BufferSource buffers aliases literal framing pipeline.path.argument otherId otherCount)
    (history : Allocation.HostReady buffers initial allocated)
    (frame : Pointers.AliasFrame aliases allocated original)
    (registry : Allocation.Registry original) (readyRegistry : Allocation.Registry ready)
    (names : (buffers.map Allocation.Buffer.binding).Nodup)
    (retained : Retained literal framing original ready)
    (different : ∀ id ∈ stage.bufferLocals, id ≠ otherId) :
    ∀ cell ∈ data.bufferRoots, cell ≠ other.view.root := by
  have separate {id : VarId} {count : Nat} {root : CellId} {length : Nat}
      (source : BufferSource buffers aliases literal framing pipeline.path.argument id count)
      (member : id ∈ stage.bufferLocals)
      (read : (ready.bindLocal pipeline.path.argument (.signed .i32 1)).local? id =
        some (.slice (.scalar (.signed .i32)) root [] 0 length)) : root ≠ other.view.root := by
    obtain ⟨storage⟩ := source.storage history frame registry readyRegistry names retained
    have rootEqual : storage.view.root = root := by
      have same := storage.read.symm.trans read
      injection same with same
      injection same
    exact rootEqual ▸ storage.apart other source otherSource history frame names (different id member)
  have bufferRead {id : VarId} {root : CellId} {length : Nat}
      (member : (id, Value.slice (.scalar (.signed .i32)) root [] 0 length) ∈
        stage.bufferBindings data capacity) :
      (ready.bindLocal pipeline.path.argument (.signed .i32 1)).local? id =
        some (.slice (.scalar (.signed .i32)) root [] 0 length) := reads _ member
  intro cell member
  simp only [SyntaxData.bufferRoots, SyntaxData.buffers, List.map_cons, List.map_nil,
    List.mem_cons, List.not_mem_nil, or_false] at member
  rcases member with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl
  · exact separate (length := capacity) checked.source (by simp [File.Syntax.Stage.bufferLocals]) (bufferRead (by simp [File.Syntax.Stage.bufferBindings]))
  · exact separate (length := data.records.length) checked.raw (by simp [File.Syntax.Stage.bufferLocals]) (bufferRead (by simp [File.Syntax.Stage.bufferBindings]))
  · exact separate (length := data.canonical.length) checked.canonical (by simp [File.Syntax.Stage.bufferLocals]) (bufferRead (by simp [File.Syntax.Stage.bufferBindings]))
  · exact separate (length := data.kinds.length) checked.kinds (by simp [File.Syntax.Stage.bufferLocals]) (bufferRead (by simp [File.Syntax.Stage.bufferBindings]))
  · exact separate (length := data.grammarWords.length) checked.grammar (by simp [File.Syntax.Stage.bufferLocals]) (bufferRead (by simp [File.Syntax.Stage.bufferBindings]))
  · exact separate (length := data.workspaceValues.length) checked.workspace (by simp [File.Syntax.Stage.bufferLocals]) (bufferRead (by simp [File.Syntax.Stage.bufferBindings]))
  · exact separate (length := data.treeRecords.length) checked.records (by simp [File.Syntax.Stage.bufferLocals]) (bufferRead (by simp [File.Syntax.Stage.bufferBindings]))
  · exact separate (length := data.treeOffsets.length) checked.offsets (by simp [File.Syntax.Stage.bufferLocals]) (bufferRead (by simp [File.Syntax.Stage.bufferBindings]))

end Lanius.Extraction.Entry.Files
