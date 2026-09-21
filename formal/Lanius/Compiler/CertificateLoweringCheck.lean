import Lanius.Extraction.Certificate
import Lanius.Compiler.ContextSynthesis
import Lanius.Compiler.ProgramLoweringCheck

namespace Lanius.Compiler.CertificateLoweringCheck

open Lanius
open Lanius.Compiler
open Lanius.Compiler.ContextSynthesis
open Lanius.Compiler.ProgramLowering
open Lanius.Compiler.ProgramLoweringCheck
open Lanius.Declarations
open Lanius.Extraction

/-!
  This is the source/Core continuation of `CertificateBoundary`.  The
  certificate boundary fixes the frontend pack, catalog, imports, and checked
  declaration rows; this boundary derives the semantic context from exactly
  those values before invoking `ProgramLoweringCheck`.

  External behavior is intentionally an explicit input.  It is host/backend
  policy, not something that can be inferred from a source declaration, so a
  successful result records the resolver through the returned lowering
  evidence instead of silently choosing one.
-/

abbrev Pack {encoded : String} {expectedSources : List Extraction.SourceFile}
    (certificate : Extraction.CertificateBoundary.Checked encoded expectedSources) :
    Declarations.SourcePack :=
  FrontendBoundary.frontendPack certificate.frontend.frontend

abbrev Catalog {encoded : String} {expectedSources : List Extraction.SourceFile}
    (certificate : Extraction.CertificateBoundary.Checked encoded expectedSources) :
    Declarations.Catalog := certificate.frontend.catalog.catalog

abbrev Imports {encoded : String} {expectedSources : List Extraction.SourceFile}
    (certificate : Extraction.CertificateBoundary.Checked encoded expectedSources) :
    List Declarations.CollectedImport := certificate.frontend.imports

abbrev Program {encoded : String} {expectedSources : List Extraction.SourceFile}
    (certificate : Extraction.CertificateBoundary.Checked encoded expectedSources) :
  Core.Program := certificate.backend.executable.program

/-- Conservative CLI/default policy: certificates containing externals are
    rejected until a host-supplied behavior resolver is provided. -/
def noExternalBehavior : ExternalBehaviorResolver := fun _ => none

def environmentFor {encoded : String}
    {expectedSources : List Extraction.SourceFile}
    (certificate : Extraction.CertificateBoundary.Checked encoded expectedSources) :
    Names.Environment :=
  ContextSynthesis.environment (Pack certificate) (Catalog certificate)
    (Imports certificate)

def contextFor {encoded : String}
    {expectedSources : List Extraction.SourceFile}
    (certificate : Extraction.CertificateBoundary.Checked encoded expectedSources) :
    SurfaceElaboration.Context :=
  ContextSynthesis.synthesize (Pack certificate) (Catalog certificate)
    (Imports certificate) (Program certificate)
    certificate.core.declarations.rows certificate.core.declarations.aliases

inductive Failure where
  | certificate (failure : Extraction.CertificateBoundary.Failure)
  | lowering (failure : ProgramLoweringCheck.Failure)
deriving DecidableEq, Repr

structure Checked (encoded : String)
    (expectedSources : List Extraction.SourceFile)
    (resolver : ExternalBehaviorResolver) where
  certificate : Extraction.CertificateBoundary.Checked encoded expectedSources
  lowering : ProgramLowering
  certificateAccepted :
    Extraction.CertificateBoundary.check encoded expectedSources = .ok certificate
  loweringAccepted :
    ProgramLoweringCheck.check certificate.core (contextFor certificate)
      (environmentFor certificate) resolver = .ok lowering

def check (encoded : String) (expectedSources : List Extraction.SourceFile)
    (resolver : ExternalBehaviorResolver) :
    Except Failure (Checked encoded expectedSources resolver) :=
  match certificateAccepted : Extraction.CertificateBoundary.check encoded expectedSources with
  | .error failure => .error (.certificate failure)
  | .ok certificate =>
      match loweringAccepted :
          ProgramLoweringCheck.check certificate.core (contextFor certificate)
            (environmentFor certificate) resolver with
      | .error failure => .error (.lowering failure)
      | .ok lowering =>
          .ok { certificate, lowering, certificateAccepted, loweringAccepted }

private theorem lowering_fields_eq
    {encoded : String} {expectedSources : List Extraction.SourceFile}
    {frontend : FrontendBoundary.Checked encoded expectedSources}
    {program : Core.Program}
    {coreChecked : CoreBoundary.Checked encoded expectedSources frontend program}
    {baseContext : SurfaceElaboration.Context}
    {environment : Names.Environment}
    {resolver : ExternalBehaviorResolver}
    {lowering : ProgramLowering}
    (accepted : ProgramLoweringCheck.check coreChecked baseContext environment resolver =
      .ok lowering) :
    lowering.pack = FrontendBoundary.frontendPack frontend.frontend ∧
      lowering.catalog = frontend.catalog.catalog ∧
      lowering.imports = frontend.imports ∧
      lowering.environment = environment ∧
      lowering.context = baseContext ∧
      lowering.program = program := by
  dsimp only [ProgramLoweringCheck.check] at accepted
  repeat' split at accepted
  all_goals simp_all
  cases accepted
  exact ⟨rfl, rfl, rfl, by assumption, rfl, rfl⟩

/- The theorem exposes the non-vacuous part of the join: the context accepted
   by the lowering checker has the canonical source environment and the exact
   Core target selected by the certificate's executable. -/
theorem context_sound {encoded : String}
    {expectedSources : List Extraction.SourceFile}
    {resolver : ExternalBehaviorResolver}
    {checked : Checked encoded expectedSources resolver}
    (_accepted : check encoded expectedSources resolver = .ok checked) :
    checked.lowering.context.names =
        Declarations.nameEnvironment (Pack checked.certificate)
          (Catalog checked.certificate) (Imports checked.certificate) ∧
      checked.lowering.context.target = checked.lowering.program.target := by
  have fields := lowering_fields_eq checked.loweringAccepted
  have names := checked.lowering.contextEnvironment.trans checked.lowering.environmentMatches
  constructor
  · simpa [fields.1, fields.2.1, fields.2.2.1] using names
  · exact checked.lowering.contextTarget

theorem program_sound {encoded : String}
    {expectedSources : List Extraction.SourceFile}
    {resolver : ExternalBehaviorResolver}
    {checked : Checked encoded expectedSources resolver}
    (_accepted : check encoded expectedSources resolver = .ok checked) :
    checked.lowering.program = Program checked.certificate := by
  exact (lowering_fields_eq checked.loweringAccepted).2.2.2.2.2

/- The same dependent result also retains the exact Surface pack selected by
   the certificate frontend; expose that field without introducing another
   lowering relation. -/
theorem source_pack_sound {encoded : String}
    {expectedSources : List Extraction.SourceFile}
    {resolver : ExternalBehaviorResolver}
    {checked : Checked encoded expectedSources resolver}
    (_accepted : check encoded expectedSources resolver = .ok checked) :
    checked.lowering.pack = Pack checked.certificate := by
  exact (lowering_fields_eq checked.loweringAccepted).1

end Lanius.Compiler.CertificateLoweringCheck
