import Lanius.Semantics.Capacity.Input
import Lanius.Semantics.Capacity.Execution
import Lanius.CallContracts
import Lanius.Separation.CellEffect

namespace Lanius.Semantics.Capacity
open Lanius.Core Lanius.Properties Lanius.Separation Lanius.CallContracts

theorem Input.entered (input : Input before) (wellFormed : StateWellFormed before)
    (entriesClosed : ∀ binding ∈ entries, closed input.config binding.2 = true) :
    state input.config (enterCall input.logical entries) = enterCall before (Execution.bindings input.config entries) ∧
      Ready input.config (enterCall input.logical entries) := by
  obtain ⟨transport, ready⟩ := Execution.bindLocals (input.valid wellFormed) (input.ready wellFormed) entriesClosed
  change ({ state input.config input.logical with locals := [] }).bindLocals (Execution.bindings input.config entries) = _ at transport
  rw [input.restored wellFormed] at transport
  exact ⟨transport.symm, ready⟩

/-- Call administration for a logical-buffer body proof. Component theorems
provide that proof; callers do not supply an assumed padded execution. -/
theorem Input.call {id : FunctionId} (input : Input before) (wellFormed : StateWellFormed before)
    (checked : Fragment.Checked program allowed) (included : allowed id = true)
    (found : program.function? id = some declaration) (bodyExact : declaration.body = some body)
    (bound : bindParameters declaration.parameters entries = some bindings)
    (entriesClosed : closeds input.config entries = true)
    (argumentsResult : ArgumentsEvaluateTo program caller arguments (values input.config entries) before)
    (executed : Executes program (enterCall input.logical bindings) body (.returned (some result)) after) :
    Evaluates program caller (.call id arguments) (value input.config result)
      (restoreLocals before (state input.config after)) := by
  obtain ⟨bodyFound, bodyPresent, supported⟩ := checked.function id declaration included found
  have same : bodyFound = body := Option.some.inj (bodyPresent.symm.trans bodyExact)
  subst bodyFound
  obtain ⟨entered, ready⟩ := input.entered wellFormed (Execution.parameters_closed entriesClosed bound)
  obtain ⟨fuel, run⟩ := executed
  obtain ⟨transport, _, _⟩ := (execution (input.valid wellFormed) checked fuel).statement ready supported run
  rw [entered] at transport
  have mappedBound : bindParameters declaration.parameters (values input.config entries) =
      some (Execution.bindings input.config bindings) := by
    rw [Execution.parameters, bound]; rfl
  have identity : declaration.id = id := by simpa using List.find?_some found
  have lookup : program.function? declaration.id = some declaration := by simpa only [identity] using found
  simpa only [identity] using evaluatesCallReturned argumentsResult lookup mappedBound bodyExact ⟨fuel, transport⟩

theorem effect (config : Config) (original : CellEffect writes before after) :
    CellEffect writes (state config before) (state config after) := by
  refine ⟨state_wellFormed config original.wellFormed, original.locals, original.world, ?_, original.nextCell, ?_⟩
  · intro root old unchanged
    simp only [cellEntry, original.oldCells root old unchanged]
  · constructor
    intro entry member
    obtain ⟨originalEntry, originalMember, rfl⟩ := List.mem_map.mp member
    obtain ⟨nextEntry, nextMember, same⟩ := original.domain.cells originalEntry originalMember
    exact ⟨cell config nextEntry, List.mem_map.mpr ⟨nextEntry, nextMember, rfl⟩, same⟩

theorem cellEntry_plain (config : Config) {id : CellId} (different : id ≠ config.root)
    (entryPlain : plain entry = true) (found : before.cellEntry? id = some { id, value := some entry }) :
    (state config before).cellEntry? id = some { id, value := some entry } := by
  simp only [cellEntry, found, Option.map_some, cell, stored, different, ↓reduceIte, plain_fixed config entry entryPlain]
  split <;> rfl

theorem signedValues_plain (entries : List Int) : plains (signedI32Values entries) = true := by
  induction entries <;> simp_all [signedI32Values, plains, plain]

end Lanius.Semantics.Capacity
