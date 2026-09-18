import Lanius.Extraction.Diagnostics.Natural
import Lanius.Extraction.Source.Projection
import Lanius.Extraction.Host.Typed

namespace Lanius.Extraction.Diagnostics

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.Typing
open Lanius.Extraction.CompactOutput

/-- The diagnostic source reads either a caller integer or a checked result
accessor. This covers frontend diagnostics and the reader's local counters. -/
inductive Argument (program : CoreSynthesis.Program.CheckedProgram artifacts) where
  | local (localId : VarId)
  | field {modulePath name typeId fieldId}
      (accessor : Source.CheckedProjection program modulePath name typeId fieldId) (localId : VarId)

variable {program : CoreSynthesis.Program.CheckedProgram artifacts}

def Argument.expression : Argument program → Expr
  | .local localId => read localId
  | .field accessor localId => .call accessor.source.function.id [read localId]

def Argument.Reads (argument : Argument program) (state : State) (value : Int) : Prop :=
  match argument with
  | .local localId => state.local? localId = some (.signed .i32 value)
  | .field (typeId := typeId) (fieldId := fieldId) _ localId =>
      ∃ fields, state.local? localId = some (.structure typeId fields) ∧ fields[fieldId]? = some (.signed .i32 value)

private theorem local_typed {localId : VarId} {value : Value}
    (typed : StateHasType program.core context state store)
    (found : state.local? localId = some value) : ∃ type, ValueHasType program.core value type := by
  obtain ⟨cell, owned⟩ := Assertion.exists_localPointsTo_of_local state localId value found
  obtain ⟨type, _, contents⟩ := typed.storeMatches _ (List.mem_of_find?_eq_some owned.2)
  exact ⟨type, contents.1⟩

/-- Integer bounds come from the entry state's existing store typing, not
from an assumed diagnostic result or a second run of the frontend. -/
theorem Argument.bounded (argument : Argument program) (typed : StateHasType program.core context state store)
    (readable : argument.Reads state value) : value ≤ 2147483647 := by
  cases argument with
  | «local» localId =>
      obtain ⟨_, valueTyped⟩ := local_typed typed readable
      cases valueTyped with
      | signed _ _ _ upper => exact upper
  | field accessor localId =>
      obtain ⟨fields, found, selected⟩ := readable
      obtain ⟨_, valueTyped⟩ := local_typed typed found
      cases valueTyped with
      | «structure» declaration _ fieldsTyped =>
          obtain ⟨_, _, fieldTyped⟩ := ValuesHaveTypes.getElem?_aligned _ fieldsTyped selected
          cases fieldTyped with
          | signed _ _ _ upper => exact upper

theorem Argument.preserved (argument : Argument program) (readable : argument.Reads before value)
    (valid : StateWellFormed before) (effect : Host.Effect CellSet.empty before after) :
    argument.Reads after value := by
  cases argument with
  | «local» localId => exact effect.preservesLocal valid readable (by simp [CellSet.empty])
  | field accessor localId =>
      obtain ⟨fields, found, selected⟩ := readable
      exact ⟨fields, effect.preservesLocal valid found (by simp [CellSet.empty]), selected⟩

theorem Argument.evaluate (argument : Argument program) (readable : argument.Reads before value)
    (valid : StateWellFormed before) :
    ∃ after, Evaluates program.core before argument.expression (.signed .i32 value) after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  cases argument with
  | «local» localId => exact ⟨before, local_evaluates program.core readable, CellEffect.refl valid, HeapFrame.refl before⟩
  | field accessor localId =>
      obtain ⟨fields, found, selected⟩ := readable
      exact accessor.call valid (.cons (local_evaluates program.core found) (.nil _ _)) selected

def statement (writer : FunctionId) (arguments : List (Argument program)) (code : Nat) : Stmt :=
  match arguments with
  | [] => returned (number code)
  | argument :: rest => .sequence (.expression (.call writer [argument.expression])) (statement writer rest code)

/-- Execute every actual argument expression and diagnostic helper call in
order, then return the source's failure code. All old cells and all host
inputs survive; only stderr and its trace may grow. -/
theorem sequence (writer : Natural.Checked program) (items : List (Argument program × Int)) (code : Nat)
    (initial : Allocation.Registry before) (representable : Host.RepresentableViews before)
    (readable : ∀ item ∈ items, item.1.Reads before item.2)
    (bounded : ∀ item ∈ items, item.2 ≤ 2147483647) :
    ∃ after, Executes program.core before (statement writer.source.source.function.id (items.map Prod.fst) code)
        (.returned (some (.signed .i32 code))) after ∧
      Allocation.Registry after ∧ Host.RepresentableViews after ∧ Host.Effect CellSet.empty before after ∧
      Host.StderrOnly before.world after.world := by
  induction items generalizing before with
  | nil => exact ⟨before, executesSequenceReturned (executesReturnValue (show
      Evaluates program.core before (number code) (.signed .i32 code) before from ⟨1, rfl⟩)),
      initial, representable, Host.Effect.refl initial.wellFormed, Host.StderrOnly.refl before.world⟩
  | cons item rest ih =>
      obtain ⟨argumentsState, evaluated, argumentEffect, argumentHeap⟩ := item.1.evaluate (readable item (by simp)) initial.wellFormed
      have memory := Host.MemoryFrame.unchanged argumentEffect argumentHeap
      obtain ⟨result, written, called, registered, writtenRepresentable, writtenEffect, writtenWorld⟩ :=
        writer.write item.2 (bounded item (by simp)) (memory.registry initial) (memory.representable initial representable)
          (.cons evaluated (.nil _ _))
      have effect := (Host.Effect.ofCells argumentEffect argumentHeap).trans writtenEffect
      obtain ⟨after, continued, finalRegistry, finalRepresentable, finalEffect, finalWorld⟩ := ih registered writtenRepresentable
        (fun entry member => entry.1.preserved (readable entry (by simp [member])) initial.wellFormed effect)
        (fun entry member => bounded entry (by simp [member]))
      exact ⟨after, executesSequence (executesExpression called) continued, finalRegistry, finalRepresentable,
        effect.trans finalEffect, (by simpa only [argumentEffect.world] using writtenWorld.trans finalWorld)⟩

end Lanius.Extraction.Diagnostics
