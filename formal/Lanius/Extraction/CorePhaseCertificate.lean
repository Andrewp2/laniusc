import Lanius.Extraction.Certificate
import Lanius.Extraction.CertificateRoundTrip
import Lanius.Compiler.CertificateLoweringCheck

namespace Lanius.Extraction.CorePhaseCertificate

open Lanius.Compiler
open Lanius.Declarations
open Lanius.Extraction
open Lanius.Extraction.CertificateRoundTrip

/-! A native `--core` extraction is a strict v3 phase certificate.  It uses
    the ordinary compact payload and canonical transport fields, then leaves
    image construction to the existing compiler boundary.  This wrapper adds
    only the phase invariant that no ELF or function-span claim is present. -/

inductive Failure where
  | lowering (failure : CertificateLoweringCheck.Failure)
  | image
  | functions
deriving DecidableEq, Repr

structure Checked (encoded : String)
    (expectedSources : List SourceFile) where
  lowering : CertificateLoweringCheck.Checked encoded expectedSources
    CertificateLoweringCheck.noExternalBehavior
  loweringAccepted : CertificateLoweringCheck.check encoded expectedSources
    CertificateLoweringCheck.noExternalBehavior = .ok lowering
  imageEmpty : lowering.certificate.certificate.elf = []
  functionsEmpty : lowering.certificate.certificate.functions = []

def check (encoded : String) (expectedSources : List SourceFile) :
    Except Failure (Checked encoded expectedSources) :=
  match accepted : CertificateLoweringCheck.check encoded expectedSources
      CertificateLoweringCheck.noExternalBehavior with
  | .error failure => .error (.lowering failure)
  | .ok lowering =>
      if imageEmpty : lowering.certificate.certificate.elf = [] then
        if functionsEmpty : lowering.certificate.certificate.functions = [] then
          .ok { lowering, loweringAccepted := accepted, imageEmpty, functionsEmpty }
        else
          .error .functions
      else
        .error .image

theorem check_sound {encoded : String} {expectedSources : List SourceFile}
    {checked : Checked encoded expectedSources}
    (_accepted : check encoded expectedSources = .ok checked) :
    decodeCertificate? encoded = some checked.lowering.certificate.certificate ∧
      checked.lowering.certificate.certificate.elf = [] ∧
      checked.lowering.certificate.certificate.functions = [] := by
  exact ⟨checked.lowering.certificate.decoded, checked.imageEmpty,
    checked.functionsEmpty⟩

theorem sound {encoded : String} {expectedSources : List SourceFile}
    {checked : Checked encoded expectedSources} :
    (decodeCertificate? encoded = some checked.lowering.certificate.certificate ∧
      decodeCompactPack? checked.lowering.certificate.certificate.compact =
        some checked.lowering.certificate.frontend.frontend.compact.compact.pack ∧
      compactPackSources checked.lowering.certificate.frontend.frontend.compact.compact.pack =
        expectedSources ∧
      SourcePackWellFormed
        (FrontendBoundary.frontendPack checked.lowering.certificate.frontend.frontend) ∧
      CatalogWellFormed
        (FrontendBoundary.frontendPack checked.lowering.certificate.frontend.frontend)
        checked.lowering.certificate.frontend.catalog.catalog ∧
      ImportCollectionCovers
        (FrontendBoundary.frontendPack checked.lowering.certificate.frontend.frontend)
        checked.lowering.certificate.frontend.imports ∧
      ProgramLowering.DeclarationLoweringsExact
        (FrontendBoundary.frontendPack checked.lowering.certificate.frontend.frontend)
        checked.lowering.certificate.frontend.catalog.catalog
        checked.lowering.certificate.backend.executable.program
        checked.lowering.certificate.core.declarations.rows ∧
      Typing.ProgramWellTyped checked.lowering.certificate.backend.executable.program ∧
      Execution.ExecutableWellFormed checked.lowering.certificate.backend.executable ∧
      X86.Transport.EncodesProgram checked.lowering.certificate.backend.executable.entrypoint
        checked.lowering.certificate.backend.executable.program
        checked.lowering.certificate.certificate.transport) ∧
      checked.lowering.lowering.pack =
        CertificateLoweringCheck.Pack checked.lowering.certificate ∧
      checked.lowering.lowering.program =
        CertificateLoweringCheck.Program checked.lowering.certificate ∧
      checked.lowering.certificate.certificate.elf = [] ∧
      checked.lowering.certificate.certificate.functions = [] := by
  exact ⟨CertificateBoundary.check_sound checked.lowering.certificateAccepted,
    CertificateLoweringCheck.source_pack_sound checked.loweringAccepted,
    CertificateLoweringCheck.program_sound checked.loweringAccepted,
    checked.imageEmpty, checked.functionsEmpty⟩

theorem transported_program_exact {encoded : String}
    {expectedSources : List SourceFile}
    {checked : Checked encoded expectedSources} :
    checked.lowering.lowering.pack =
        CertificateLoweringCheck.Pack checked.lowering.certificate ∧
      checked.lowering.lowering.program =
        CertificateLoweringCheck.Program checked.lowering.certificate := by
  exact ⟨CertificateLoweringCheck.source_pack_sound checked.loweringAccepted,
    CertificateLoweringCheck.program_sound checked.loweringAccepted⟩

theorem phase_fields_roundtrip (certificate : Certificate)
    (representable : Representable certificate)
    (phase : certificate.elf = [] ∧ certificate.functions = []) :
    (decodeCertificate? (encodeCertificate certificate)).map
        (fun decoded =>
          (decoded.compact, decoded.transport, decoded.elf, decoded.functions)) =
      some (certificate.compact, certificate.transport, [], []) := by
  rw [decodeCertificate_roundtrip certificate representable]
  simp [phase.1, phase.2]

end Lanius.Extraction.CorePhaseCertificate
