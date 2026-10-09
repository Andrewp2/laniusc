import Lanius.Compiler.FrontendBoundary
import Lanius.Compiler.CoreBoundary
import Lanius.Compiler.ContextSynthesis
import Lanius.Compiler.ProgramLoweringCheck
import Lanius.Compiler.EntrypointCheck

namespace Lanius.Compiler.DirectCoreCheck

open Lanius
open Lanius.Declarations
open Lanius.Extraction
open Lanius.Compiler.ProgramLowering

def environmentForInput (input : FrontendBoundary.CoreInput) : Names.Environment :=
  ContextSynthesis.environment input.pack input.catalog.catalog input.imports

def contextForInput (input : FrontendBoundary.CoreInput)
    {program : Core.Program}
    (core : CoreBoundary.CheckedInput input program) :
    SurfaceElaboration.Context :=
  ContextSynthesis.synthesize input.pack input.catalog.catalog input.imports
    program core.declarations.rows core.declarations.aliases

inductive SemanticFailure where
  | core (failure : CoreBoundary.Failure)
  | lowering (failure : ProgramLoweringCheck.Failure)
  | selection (failure : EntrypointCheck.Failure)
  | entrypoint
deriving DecidableEq, Repr

structure SemanticChecked (input : FrontendBoundary.CoreInput)
    (program : Core.Program) (entrypoint : FunctionId)
    (resolver : ExternalBehaviorResolver) where
  core : CoreBoundary.CheckedInput input program
  coreAccepted : CoreBoundary.checkInput input program = .ok core
  lowering : ProgramLowering
  loweringAccepted : ProgramLoweringCheck.checkInput input core
    (contextForInput input core) (environmentForInput input) resolver rfl = .ok lowering
  selection : ExecutableBoundary.MainSelection lowering
  selectionAccepted : EntrypointCheck.check lowering = .ok selection
  selectedEntrypoint : selection.body.core.id = entrypoint

def checkSemantic (input : FrontendBoundary.CoreInput)
    (program : Core.Program) (entrypoint : FunctionId)
    (resolver : ExternalBehaviorResolver) :
    Except SemanticFailure (SemanticChecked input program entrypoint resolver) :=
  match coreAccepted : CoreBoundary.checkInput input program with
  | .error failure => .error (.core failure)
  | .ok core =>
      match loweringAccepted : ProgramLoweringCheck.checkInput input core
          (contextForInput input core) (environmentForInput input) resolver rfl with
      | .error failure => .error (.lowering failure)
      | .ok lowering =>
          match selectionAccepted : EntrypointCheck.check lowering with
          | .error failure => .error (.selection failure)
          | .ok selection =>
              if selectedEntrypoint : selection.body.core.id = entrypoint then
                .ok {
                  core
                  coreAccepted
                  lowering
                  loweringAccepted
                  selection
                  selectionAccepted
                  selectedEntrypoint
                }
              else .error .entrypoint

inductive TypedFailure where
  | frontend (failure : FrontendBoundary.TypedFailure)
  | core (failure : CoreBoundary.Failure)
  | lowering (failure : ProgramLoweringCheck.Failure)
  | selection (failure : EntrypointCheck.Failure)
  | entrypoint
deriving DecidableEq, Repr

def TypedFailure.ofSemantic : SemanticFailure → TypedFailure
  | .core failure => .core failure
  | .lowering failure => .lowering failure
  | .selection failure => .selection failure
  | .entrypoint => .entrypoint

structure CheckedTyped (artifact : ArtifactPack) (sources : List Extraction.SourceFile)
    (program : Core.Program) (entrypoint : FunctionId)
    (resolver : ExternalBehaviorResolver) where
  frontend : FrontendBoundary.CheckedTyped artifact sources
  frontendAccepted : FrontendBoundary.checkTyped artifact sources = .ok frontend
  semantic : SemanticChecked (FrontendBoundary.typedCoreInput frontend)
    program entrypoint resolver

def checkTyped (artifact : ArtifactPack) (sources : List Extraction.SourceFile)
    (program : Core.Program) (entrypoint : FunctionId)
    (resolver : ExternalBehaviorResolver) :
    Except TypedFailure (CheckedTyped artifact sources program entrypoint resolver) :=
  match frontendAccepted : FrontendBoundary.checkTyped artifact sources with
  | .error failure => .error (.frontend failure)
  | .ok frontend =>
      match checkSemantic (FrontendBoundary.typedCoreInput frontend)
          program entrypoint resolver with
      | .error failure => .error (TypedFailure.ofSemantic failure)
      | .ok semantic => .ok {
          frontend
          frontendAccepted
          semantic
        }

/-- Turn a kernel-checked success decision into the existing agreement witness.
    This is for optional bootstrap audits, not normal emitted program data. -/
theorem checkTyped_success
    (accepted : (checkTyped artifact sources program entrypoint resolver).isOk = true) :
    ∃ checked, checkTyped artifact sources program entrypoint resolver = .ok checked := by
  cases result : checkTyped artifact sources program entrypoint resolver with
  | error failure => simp [Except.isOk, Except.toBool, result] at accepted
  | ok checked => exact ⟨checked, rfl⟩

private theorem lowering_program_eq
    {input : FrontendBoundary.CoreInput}
    {program : Core.Program}
    {core : CoreBoundary.CheckedInput input program}
    {context : SurfaceElaboration.Context} {environment : Names.Environment}
    {resolver : ExternalBehaviorResolver} {lowering : ProgramLowering}
    (canonical : context = CoreBoundary.enumContextInput input program core.declarations)
    (accepted : ProgramLoweringCheck.checkInput input core context environment resolver canonical =
      .ok lowering) : lowering.program = program := by
  dsimp only [ProgramLoweringCheck.checkInput] at accepted
  repeat' split at accepted
  all_goals simp_all
  cases accepted
  rfl

theorem checked_typed_program {artifact : ArtifactPack}
    {sources : List Extraction.SourceFile} {program : Core.Program}
    {entrypoint : FunctionId} {resolver : ExternalBehaviorResolver}
    (checked : CheckedTyped artifact sources program entrypoint resolver) :
    checked.semantic.lowering.program = program :=
  lowering_program_eq rfl checked.semantic.loweringAccepted

theorem typed_emitted_executable_wellFormed {artifact : ArtifactPack}
    {sources : List Extraction.SourceFile} {program : Core.Program}
    {entrypoint : FunctionId} {resolver : ExternalBehaviorResolver}
    (checked : CheckedTyped artifact sources program entrypoint resolver) :
    Execution.ExecutableWellFormed
      { program := program, entrypoint := entrypoint } := by
  have selected := ExecutableBoundary.selected_wellFormed
    checked.semantic.lowering checked.semantic.selection
  simpa [checked_typed_program checked,
    checked.semantic.selectedEntrypoint] using selected

/-- The selected emitted function is the source-lowered body, not merely some
    well-typed function with the same entrypoint ID. -/
theorem typed_emitted_entrypoint {artifact : ArtifactPack}
    {sources : List Extraction.SourceFile} {program : Core.Program}
    {entrypoint : FunctionId} {resolver : ExternalBehaviorResolver}
    (checked : CheckedTyped artifact sources program entrypoint resolver) :
    program.function? entrypoint = some checked.semantic.selection.body.core := by
  simpa only [checked_typed_program checked, checked.semantic.selectedEntrypoint] using
    ExecutableBoundary.selected_function checked.semantic.lowering checked.semantic.selection

/-- Every source function has its actual emitted body and source-lowering
    evidence. Exactness comes from the checker, not an assumed successful run. -/
theorem typed_emitted_body {artifact : ArtifactPack}
    {sources : List Extraction.SourceFile} {program : Core.Program}
    {entrypoint : FunctionId} {resolver : ExternalBehaviorResolver}
    (checked : CheckedTyped artifact sources program entrypoint resolver)
    (source : checked.semantic.lowering.pack.item? address = some (.function declaration)) :
    ∃ body ∈ checked.semantic.lowering.functionBodies,
      body.address = address ∧ body.declaration = declaration ∧
      body.core ∈ program.functions ∧ body.core.body = some body.lowering.core ∧
      body.core.external = none := by
  obtain ⟨body, member, sameAddress⟩ :=
    checked.semantic.lowering.functionBodiesExact.1 address declaration source
  have sameDeclaration : body.declaration = declaration := by
    have found := body.sourceFound
    rw [sameAddress, source] at found
    exact Surface.Item.function.inj (Option.some.inj found).symm
  have emitted := body.row.member
  rw [body.coreMap] at emitted
  change body.core ∈ checked.semantic.lowering.program.functions at emitted
  rw [congrArg Core.Program.functions (checked_typed_program checked)] at emitted
  exact ⟨body, member, sameAddress, sameDeclaration, emitted, body.coreShape⟩

theorem checked_typed_source_and_program {artifact : ArtifactPack}
    {sources : List Extraction.SourceFile} {program : Core.Program}
    {entrypoint : FunctionId} {resolver : ExternalBehaviorResolver}
    (checked : CheckedTyped artifact sources program entrypoint resolver) :
    compactPackSources artifact = sources ∧
      DeclarationLoweringsExact
        (FrontendBoundary.typedFrontendPack checked.frontend.frontend)
        checked.frontend.catalog.catalog program checked.semantic.core.declarations.rows ∧
      Typing.ProgramWellTyped program ∧
      checked.semantic.lowering.program = program ∧
      checked.semantic.selection.body.core.id = entrypoint := by
  have source := FrontendBoundary.checked_typed_source_evidence checked.frontend
  have core := CoreBoundary.checked_input_evidence
    (checked := checked.semantic.core)
  exact ⟨source.1, core.2.2.2.1, core.2.2.2.2,
    checked_typed_program checked, checked.semantic.selectedEntrypoint⟩

end Lanius.Compiler.DirectCoreCheck
