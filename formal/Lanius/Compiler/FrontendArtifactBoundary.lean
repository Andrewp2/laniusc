import Lanius.Compiler.FrontendArtifact
import Lanius.Compiler.SourceCoreBoundary
import Lanius.Extraction.CurrentSourceClosure
import Lanius.Semantics.Pure

namespace Lanius.Compiler.FrontendArtifactBoundary

open Lanius
open Lanius.Core
open Lanius.Compiler
open Lanius.Compiler.ProgramLowering
open Lanius.Extraction
open Lanius.Semantics

/-! The frontend Core quotation is a separate artifact from the current
    source closure.  This boundary keeps that fact explicit: the compact
    checker authenticates current frontend source bytes and Surface data,
    while one program equality is required to rebase the existing frontend
    proofs onto a checked current lowering. -/

structure ArtifactMatch {encoded : String}
    {checked : SyntaxCheck.CheckedSourcePack encoded
      CurrentSourceClosure.frontendSources}
    (boundary : SourceCoreBoundary.SourceCoreBoundary encoded
      CurrentSourceClosure.frontendSources checked) : Prop where
  program : boundary.lowering.program = FrontendArtifact.frontendProgram

theorem current_source_authenticated {encoded : String}
    {checked : SyntaxCheck.CheckedSourcePack encoded
      CurrentSourceClosure.frontendSources}
    (_accepted : CurrentSourceClosure.checkFrontend encoded = .ok checked) :
    compactPackSources checked.compact.pack = CurrentSourceClosure.frontendSources := by
  exact (CurrentSourceClosure.check_frontend_sound _accepted).2.2.1

theorem authenticated_core {encoded : String}
    {checked : SyntaxCheck.CheckedSourcePack encoded
      CurrentSourceClosure.frontendSources}
    (accepted : CurrentSourceClosure.checkFrontend encoded = .ok checked)
    (boundary : SourceCoreBoundary.SourceCoreBoundary encoded
      CurrentSourceClosure.frontendSources checked)
    (matchEvidence : ArtifactMatch boundary) :
    compactPackSources checked.compact.pack = CurrentSourceClosure.frontendSources ∧
      boundary.lowering.program = FrontendArtifact.frontendProgram ∧
      Typing.ProgramWellTyped FrontendArtifact.frontendProgram := by
  have source := current_source_authenticated accepted
  have typed : Typing.ProgramWellTyped boundary.lowering.program :=
    boundary.lowering.wellTyped
  refine ⟨source, matchEvidence.program, ?_⟩
  rw [← matchEvidence.program]
  exact typed

theorem rebase_pure {program₁ program₂ : Core.Program} {caller : State}
    {expression : Core.Expr} {value : Core.Value}
    (programEq : program₁ = program₂)
    (evaluates : PurelyEvaluates program₂ caller expression value) :
    PurelyEvaluates program₁ caller expression value := by
  simpa [programEq] using evaluates

theorem rebase_pure_authenticated {encoded : String}
    {checked : SyntaxCheck.CheckedSourcePack encoded
      CurrentSourceClosure.frontendSources}
    (accepted : CurrentSourceClosure.checkFrontend encoded = .ok checked)
    (boundary : SourceCoreBoundary.SourceCoreBoundary encoded
      CurrentSourceClosure.frontendSources checked)
    (matchEvidence : ArtifactMatch boundary)
    {caller : State} {expression : Core.Expr} {value : Core.Value}
    (evaluates : PurelyEvaluates FrontendArtifact.frontendProgram caller
      expression value) :
    PurelyEvaluates boundary.lowering.program caller expression value := by
  exact rebase_pure (authenticated_core accepted boundary matchEvidence).2.1
    evaluates

end Lanius.Compiler.FrontendArtifactBoundary
