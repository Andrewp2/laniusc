import Lanius.Extraction.Input.File.Initialize

namespace Lanius.Extraction.Input.File

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.Extraction.CompactOutput Lanius.FunctionalView.Core

def Resources.values (resources : Resources) : List Value := [
  .signed .i32 resources.handle.id, .slice i32 resources.output.root [] 0 resources.output.length,
  .signed .i32 resources.capacity, .slice i32 resources.packed.root [] 0 resources.packed.length]

/-- Execute the authenticated Lanius `read_file` call for any file size.
The result is its length if it fits and -2 otherwise. The entire body, finite
loop execution, and caller-scope restoration are derived from resources. -/
theorem Checked.read (checked : Checked program) (resources : Resources)
    (initial : Allocation.Registry before) (representable : Host.RepresentableViews before)
    (disjoint : before.i32ArrayViews.Pairwise I32ViewRangesDisjoint)
    (outputMember : resources.output ∈ before.i32ArrayViews) (packedMember : resources.packed ∈ before.i32ArrayViews)
    (outputContents : before.cellEntry? resources.output.root = some {
      id := resources.output.root
      value := some (.array (signedI32Values resources.original)) })
    (world : before.world = resources.world)
    (sizeFit : 65536 < unsignedModulus program.core.target .usize)
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments resources.values before) :
    ∃ after, Evaluates program.core caller (.call checked.source.source.function.id arguments)
        (.signed .i32 resources.result) after ∧ Finished resources before after := by
  let bindings := parameterBindings (fun index : Fin 4 => resources.values.get index)
  let entered := enterCall before bindings
  have localRead (index : Fin 4) : entered.local? index.val = some (resources.values.get index) :=
    enterCall_parameterBindings_matches initial.wellFormed index
  have prefixEffect := enterCall_effect before bindings
  have enteredContents := (prefixEffect.oldCells resources.output.root (initial.root_lt_next outputMember)
    (by simp [CellSet.empty])).trans outputContents
  obtain ⟨completed, run, done⟩ := body_returns checked.reader checked.wordsFound checked.wordsValue resources
    (initial.enterCall bindings) (representable.enterCall initial bindings)
    (by simpa only [prefixEffect.views] using disjoint)
    (by simpa only [prefixEffect.views] using outputMember) (by simpa only [prefixEffect.views] using packedMember)
    enteredContents (localRead ⟨0, by decide⟩) (localRead ⟨1, by decide⟩)
    (localRead ⟨2, by decide⟩) (localRead ⟨3, by decide⟩) (prefixEffect.world.trans world) sizeFit
  have identity : checked.source.source.function.id = checked.source.source.source.id := by
    simpa [Program.function?] using List.find?_some checked.source.source.found
  have found : program.core.function? checked.source.source.function.id = some checked.source.source.function := by
    rw [identity]
    exact checked.source.source.found
  have bound : bindParameters checked.source.source.function.parameters resources.values = some bindings := by
    rw [checked.source.signature.1]
    rfl
  have called := evaluatesCallReturned argumentsResult found bound checked.source.bodyExact run
  have effect := done.effect.closeCall before bindings initial.wellFormed
  exact ⟨restoreLocals before completed, called, ⟨done.registry.restoreLocals before effect.wellFormed,
    done.representable, done.output, done.world, effect⟩⟩

end Lanius.Extraction.Input.File
