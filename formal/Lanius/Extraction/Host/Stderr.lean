import Lanius.Extraction.Host.External
import Lanius.Extraction.Host.Effect

namespace Lanius.Extraction.Host

open Lanius.Core Lanius.Semantics Lanius.CallContracts Lanius.Separation

def stderrWorld (world : Lanius.World.State) (value : Int) : Lanius.World.State := {
  world with
  calls := world.calls ++ [.writeByte]
  standardError := world.standardError ++ [UInt8.ofNat (Int.toNat (value % 256))] }

/-- Diagnostics may append stderr bytes and their byte-call trace, but no
other part of the host world changes. Their precise text is not required by
the extractor's failure-safety contract. -/
def StderrOnly (before after : Lanius.World.State) : Prop :=
  ∃ bytes : List UInt8, after = { before with
    standardError := before.standardError ++ bytes
    calls := before.calls ++ List.replicate bytes.length .writeByte }

theorem StderrOnly.refl (world : Lanius.World.State) : StderrOnly world world :=
  ⟨[], by simp⟩

theorem StderrOnly.byte (world : Lanius.World.State) (value : Int) : StderrOnly world (stderrWorld world value) :=
  ⟨[UInt8.ofNat (Int.toNat (value % 256))], rfl⟩

theorem StderrOnly.trans (first : StderrOnly before middle) (second : StderrOnly middle after) :
    StderrOnly before after := by
  obtain ⟨left, rfl⟩ := first
  obtain ⟨right, rfl⟩ := second
  exact ⟨left ++ right, by simp [List.append_assoc]⟩

/-- The diagnostic byte service writes only stderr. Both array synchronization
passes execute from ordinary registered storage; every representable array,
source file, argument, open handle, and stdout byte is preserved. -/
theorem evaluatesStderr (checked : CheckedExternal program .writeByte 2)
    (initial : Allocation.Registry before) (representable : RepresentableViews before)
    (value : Int)
    (argumentsResult : ArgumentsEvaluateTo program caller arguments [.signed .i32 2, .signed .i32 value] before) :
    ∃ after, Evaluates program caller (.call checked.function.id arguments) (.signed .i32 1) after ∧
      Allocation.Registry after ∧ Frame before after ∧ Effect CellSet.empty before after ∧
      after.world = stderrWorld before.world value := by
  obtain ⟨bindings, bound⟩ := checked.bindings [.signed .i32 2, .signed .i32 value] rfl
  have call (ready : State) (synced : syncI32ViewsToHeap before = .ok ready) :
      Lanius.World.call ready.heap ready.world .writeByte [.signed .i32 2, .signed .i32 value] =
        .returned (.signed .i32 1) ready.heap (stderrWorld before.world value) := by
    rw [Lanius.Properties.syncI32ViewsToHeap_preserves_world synced]
    simp only [Lanius.World.call, Lanius.World.callSimple, Lanius.World.writeBytes]
    rfl
  obtain ⟨after, run, registered, frame, world⟩ :=
    evaluatesReadOnly initial argumentsResult checked.found bound checked.noBody checked.host call
  refine ⟨after, run, registered, frame, Effect.ofHost frame initial registered ?_, world⟩
  intro view member _
  obtain ⟨words, _, contents⟩ := initial.storage member
  have kept := readOnlyPreservesView initial argumentsResult checked.found bound checked.noBody checked.host
    call initial.disjoint member
    (by simp only [readCellProjection, initial.roots view member, contents, projectedValue])
    (representable view member words contents) run
  exact kept.trans contents.symm

end Lanius.Extraction.Host
