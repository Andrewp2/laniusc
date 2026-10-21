import Lanius.Compiler.DirectCoreCheck
import Lanius.Execution

namespace SourceAgreementProof
open Lanius Lanius.Extraction Lanius.Compiler.DirectCoreCheck

-- The harness supplies independent file bytes and two fresh outputs. Checked
-- mode is bootstrap-only; the ordinary artifact has no validation tree.
theorem sameProgram : Ordinary.extractedProgram = Audited.extractedProgram := rfl
theorem sameEntrypoint : Ordinary.extractedEntrypoint = Audited.extractedEntrypoint := rfl

theorem accepted : ∃ checked,
    checkTyped (Audited.extractedFrontend expectedSources) expectedSources
      Ordinary.extractedProgram Ordinary.extractedEntrypoint (fun _ => none) = .ok checked := by
  apply checkTyped_success
  decide +kernel

theorem wellTyped : Typing.ProgramWellTyped Ordinary.extractedProgram := by
  obtain ⟨checked, _⟩ := accepted
  exact (checked_typed_source_and_program checked).2.2.1

-- Acceptance retains the selected source body and all function-body lowering
-- witnesses; these are not reconstructed into the ordinary emitted module.
theorem entrypointOrigin : ∃ checked : CheckedTyped
    (Audited.extractedFrontend expectedSources) expectedSources
    Ordinary.extractedProgram Ordinary.extractedEntrypoint (fun _ => none),
    Ordinary.extractedProgram.function? Ordinary.extractedEntrypoint =
      some checked.semantic.selection.body.core := by
  obtain ⟨checked, _⟩ := accepted
  exact ⟨checked, typed_emitted_entrypoint checked⟩

-- A payload change retains valid Core typing but no longer implements the
-- independently supplied source. Rejection must reach the body-lowering stage,
-- not a syntax or typing error. This is a successful rejection proof, not an
-- intentionally failed theorem with an error-recovery admission.
theorem semanticMutationRejected : (match checkTyped
    (Audited.extractedFrontend expectedSources) expectedSources
    Tampered.extractedProgram Tampered.extractedEntrypoint (fun _ => none) with
    | .error (.lowering .missingBodies) => true
    | _ => false) = true := by
  decide +kernel

-- Behavior of the very same ordinary program authenticated above.
theorem entrypointReturnsSeven : (match Execution.run 64
    { program := Ordinary.extractedProgram, entrypoint := Ordinary.extractedEntrypoint } {} with
    | .returned (.signed .i32 7) _ => true
    | _ => false) = true := by
  decide +kernel

#print axioms accepted
#print axioms wellTyped
#print axioms entrypointOrigin
#print axioms typed_emitted_body
#print axioms semanticMutationRejected
#print axioms entrypointReturnsSeven

end SourceAgreementProof
