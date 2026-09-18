import Lanius.Extraction.Source.Storage
import Lanius.CallContracts.Expression

namespace Lanius.Extraction.Source

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core

/-- Close a composed one-cell expression contract at the authenticated source
body. The cell frame and caller restoration are supplied by `specCell`. -/
theorem CheckedInternal.specExpressionCell
    (checked : CheckedInternal program path name parameters resultType (.sequence (.returnValue (some expression)) .skip))
    {cell : CellId} {original written result : Value}
    (bound : bindParameters parameters values = some (parameterBindings (fun index : Fin values.length => values[index])))
    (spec : ExprSpec program.core values (CellSet.singleton cell) expression result
      (fun before => before.cellEntry? cell = some ⟨cell, some original⟩)
      (fun after => after.cellEntry? cell = some ⟨cell, some written⟩))
    (plain : ∀ value, value ∈ values → value ≠ original) :
    checked.Spec values result
      (fun before => before.cellEntry? cell = some ⟨cell, some original⟩)
      (fun _ after => after.cellEntry? cell = some ⟨cell, some written⟩) (CellSet.singleton cell) := by
  apply checked.specCell bound
  intro callee wellFormed reads backing
  obtain ⟨after, run, post, effect, heap⟩ :=
    spec callee wellFormed (LocalFrame.cell cell original reads backing plain) backing
  exact ⟨after, executesSequenceReturned (executesReturnValue run), post, effect, heap⟩

/-- Close a readonly expression contract using the empty-cell frame rule. -/
theorem CheckedInternal.specExpressionFrame
    (checked : CheckedInternal program path name parameters resultType
      (.sequence (.returnValue (some expression)) .skip))
    (bound : bindParameters parameters values =
      some (parameterBindings (fun index : Fin values.length => values[index])))
    (spec : ExprSpec program.core values CellSet.empty expression result
      (fun _ => True) (fun _ => True)) :
    checked.Spec values result := by
  apply checked.specFrame bound
  intro callee wellFormed reads
  obtain ⟨after, run, _, effect, heap⟩ := spec callee wellFormed (LocalFrame.empty reads) trivial
  exact ⟨after, executesSequenceReturned (executesReturnValue run), effect, heap⟩

end Lanius.Extraction.Source
