import Lanius.Extraction.Host.MemoryFrame

namespace Lanius.Extraction.Host

open Lanius.Core Lanius.Semantics Lanius.Separation

/-- A native-memory-preserving prefix followed by cell-only work. The cut is
after the last borrowed allocation; runtime typing at the final boundary can
then recover array lengths and word ranges without replaying the suffix. -/
def MemoryPath (before after : State) : Prop :=
  ∃ boundary, MemoryFrame before boundary ∧ HeapFrame boundary after

theorem MemoryFrame.path (frame : MemoryFrame before after) : MemoryPath before after :=
  ⟨after, frame, HeapFrame.refl after⟩

theorem HeapFrame.memoryPath (frame : HeapFrame before after) : MemoryPath before after :=
  ⟨before, MemoryFrame.refl before, frame⟩

theorem MemoryPath.thenHeap (path : MemoryPath before middle) (frame : HeapFrame middle after) :
    MemoryPath before after := by
  obtain ⟨boundary, prefixFrame, suffixFrame⟩ := path
  exact ⟨boundary, prefixFrame, suffixFrame.trans frame⟩

theorem MemoryPath.prepend (path : MemoryPath middle after) (frame : MemoryFrame before middle) :
    MemoryPath before after := by
  obtain ⟨boundary, prefixFrame, suffixFrame⟩ := path
  exact ⟨boundary, frame.trans prefixFrame, suffixFrame⟩

theorem MemoryPath.restoreLocals (path : MemoryPath before after) (caller : State) :
    MemoryPath before (Lanius.Semantics.restoreLocals caller after) :=
  path.thenHeap ⟨rfl, rfl⟩

theorem MemoryPath.closeLocal (before : State) (id : VarId) (value : Value)
    (path : MemoryPath (before.bindLocal id value) after) :
    MemoryPath before (Lanius.Semantics.restoreLocals before after) :=
  (path.prepend (MemoryFrame.bindLocal before id value)).restoreLocals before

theorem MemoryPath.closeCall (before : State) (bindings : List (VarId × Value))
    (path : MemoryPath (enterCall before bindings) after) :
    MemoryPath before (Lanius.Semantics.restoreLocals before after) :=
  (path.prepend (MemoryFrame.enterCall before bindings)).restoreLocals before

end Lanius.Extraction.Host
