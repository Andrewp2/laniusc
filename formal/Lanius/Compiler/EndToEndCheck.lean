import Lanius.Compiler.CertificateLoweringCheck
import Lanius.X86.CertificateImageCheck

namespace Lanius.Compiler.EndToEndCheck

open Lanius
open Lanius.Compiler
open Lanius.Compiler.CertificateLoweringCheck
open Lanius.Compiler.ProgramLowering
open Lanius.Compiler.ProgramLoweringCheck
open Lanius.Declarations
open Lanius.Extraction
open Lanius.X86
open Lanius.X86.ProgramCheck

/-!
  The executable checker is the final composition boundary.  A successful
  certificate supplies its own exact ELF bytes and work-table spans; the
  checker derives `ProgramCheck.Image` from those authenticated values before
  checking function bytes and the ELF layout.  There is no caller-supplied
  image or metadata that can be paired with the source/Core certificate.
-/

inductive Failure where
  | certificate (failure : Extraction.CertificateBoundary.Failure)
  | lowering (failure : ProgramLoweringCheck.Failure)
  | image
  | program
deriving DecidableEq, Repr

structure Checked (encoded : String)
    (expectedSources : List Extraction.SourceFile)
    (resolver : ExternalBehaviorResolver := noExternalBehavior) where
  certificate : CertificateLoweringCheck.Checked encoded expectedSources resolver
  certificateImage : X86.CertificateImageCheck.Checked
    certificate.certificate.backend.executable certificate.certificate.certificate
  program : X86.ProgramCheck.Authenticated
    certificate.certificate.backend.executable certificateImage.image
  image : X86.ImageCheck.Checked X86.ImageCheck.lanius
    certificate.certificate.certificate.elf certificateImage.image
  certificateAccepted :
    CertificateLoweringCheck.check encoded expectedSources resolver = .ok certificate
  imageMetadataAccepted :
    X86.CertificateImageCheck.check certificate.certificate.backend.executable
      certificate.certificate.certificate = some certificateImage
  programAccepted :
    X86.ProgramCheck.checkAuthenticated certificate.certificate.backend.executable
      certificateImage.image = some program
  imageAccepted :
    X86.ImageCheck.check X86.ImageCheck.lanius
      certificate.certificate.certificate.elf certificateImage.image = some image
  enumerationsEmpty :
    certificate.certificate.backend.executable.program.enumerations = []

/- The checker first authenticates source/Core, then authenticates span
   metadata and constructs the image, then checks the extracted bytes. -/
def check (encoded : String) (expectedSources : List Extraction.SourceFile)
    (resolver : ExternalBehaviorResolver := noExternalBehavior) :
    Except Failure (Checked encoded expectedSources resolver) :=
  match certificateAccepted : CertificateLoweringCheck.check encoded expectedSources resolver with
  | .error (.certificate failure) => .error (.certificate failure)
  | .error (.lowering failure) => .error (.lowering failure)
  | .ok certificate =>
      match imageMetadataAccepted :
          X86.CertificateImageCheck.check certificate.certificate.backend.executable
            certificate.certificate.certificate with
      | none => .error .image
      | some certificateImage =>
          match programAccepted :
              X86.ProgramCheck.checkAuthenticated certificate.certificate.backend.executable
                certificateImage.image with
          | none => .error .program
          | some program =>
              match imageAccepted :
                  X86.ImageCheck.check X86.ImageCheck.lanius
                    certificate.certificate.certificate.elf certificateImage.image with
              | none => .error .image
              | some imageChecked =>
                  if noEnums : certificate.certificate.backend.executable.program.enumerations = [] then .ok {
                    certificate
                    certificateImage
                    program
                    image := imageChecked
                    certificateAccepted
                    imageMetadataAccepted
                    programAccepted
                    imageAccepted
                    enumerationsEmpty := noEnums }
                  else .error .program

structure Soundness (encoded : String)
    (expectedSources : List Extraction.SourceFile)
    (resolver : ExternalBehaviorResolver := noExternalBehavior)
    (checked : Checked encoded expectedSources resolver) where
  programLowering :
    ∃ lowering : ProgramLowering,
      lowering = checked.certificate.lowering ∧
        lowering.program = checked.certificate.certificate.backend.executable.program
  programLoweringProgram :
    checked.certificate.lowering.program =
      checked.certificate.certificate.backend.executable.program
  decodedCertificate :
    Extraction.decodeCertificate? encoded =
      some checked.certificate.certificate.certificate
  decodedCompact :
    Extraction.decodeCompactPack? checked.certificate.certificate.certificate.compact =
      some checked.certificate.certificate.frontend.frontend.compact.compact.pack
  sourceExact :
    compactPackSources checked.certificate.certificate.frontend.frontend.compact.compact.pack =
      expectedSources
  sourceWellFormed :
    SourcePackWellFormed
      (FrontendBoundary.frontendPack checked.certificate.certificate.frontend.frontend)
  catalogWellFormed :
    CatalogWellFormed
      (FrontendBoundary.frontendPack checked.certificate.certificate.frontend.frontend)
      checked.certificate.certificate.frontend.catalog.catalog
  importsCovered :
    ImportCollectionCovers
      (FrontendBoundary.frontendPack checked.certificate.certificate.frontend.frontend)
      checked.certificate.certificate.frontend.imports
  declarationsExact :
    DeclarationLoweringsExact
      (FrontendBoundary.frontendPack checked.certificate.certificate.frontend.frontend)
      checked.certificate.certificate.frontend.catalog.catalog
      checked.certificate.certificate.backend.executable.program
      checked.certificate.certificate.core.declarations.rows
  typed : Typing.ProgramWellTyped checked.certificate.certificate.backend.executable.program
  executableWellFormed :
    Execution.ExecutableWellFormed checked.certificate.certificate.backend.executable
  canonicalTransport :
    X86.Transport.EncodesProgram checked.certificate.certificate.backend.executable.entrypoint
      checked.certificate.certificate.backend.executable.program
      checked.certificate.certificate.certificate.transport
  programTarget :
    checked.certificate.certificate.backend.executable.program.target = Core.Target.x86_64
  enumerationsEmpty :
    checked.certificate.certificate.backend.executable.program.enumerations = []
  spanCountExact :
    checked.certificate.certificate.certificate.functions.length =
      checked.certificate.certificate.backend.executable.program.functions.length
  spansWellFormed :
    X86.CertificateImageCheck.spansOK
      checked.certificate.certificate.certificate.elf.length 0
      checked.certificate.certificate.certificate.functions = true
  functionsExact :
    checked.program.functions.map (fun evidence => evidence.function) =
      checked.certificate.certificate.backend.executable.program.functions
  imageExact :
    checked.program.functions.map (fun evidence => evidence.image) =
      checked.certificateImage.image.functions
  programSlicesExact :
    checked.program.functions.map (fun evidence => evidence.image) =
      checked.image.slices.map (fun evidence => evidence.image)
  entrypointExact :
    checked.program.entrypoint.function.id =
      checked.certificate.certificate.backend.executable.entrypoint
  entrypointZeroParameters : checked.program.entrypoint.function.parameters = []
  functionsAuthenticated : X86.ProgramCheck.Authenticated.bytesAuthenticated checked.program
  headerAuthenticated :
    X86.ImageCheck.fieldsOK checked.certificate.certificate.certificate.elf
      (X86.ImageCheck.fields X86.ImageCheck.lanius
        checked.certificate.certificate.certificate.elf.length) = true
  headerLengthBound : checked.certificate.certificate.certificate.elf.length < 2 ^ 64
  slicesExact :
    checked.image.slices.map (fun evidence => evidence.image) =
      checked.certificateImage.image.functions
  loadedFromElf :
    ∀ (machine : X86.Machine.State),
      X86.Machine.CodeAt machine.memory X86.ImageCheck.lanius.base
        checked.certificate.certificate.certificate.elf →
        checked.program.Loaded machine
  entrypointPreserves :
    ∀ (coreBefore : Semantics.State) (machineBefore : X86.Machine.State),
      (loaded : checked.program.Loaded machineBefore) →
      (environment : X86.ProgramCheck.PreservationEnvironment checked.program
        coreBefore machineBefore) →
      (ripAtEntry : machineBefore.rip = checked.program.entrypoint.image.address) →
      (returnAddress : X86.Machine.Address) →
      (poppedReturn : X86.Machine.read64 machineBefore.memory
          (machineBefore.registers 4) = returnAddress) →
      checked.program.Preserves coreBefore machineBefore loaded environment ripAtEntry
        returnAddress poppedReturn

private theorem transport_target
    {entrypoint : FunctionId} {program : Core.Program} {words : List Int}
    (encoded : X86.Transport.EncodesProgram entrypoint program words) :
    program.target = Core.Target.x86_64 := by
  unfold X86.Transport.EncodesProgram X86.Transport.encodeProgram at encoded
  split at encoded
  · simp_all
  · simp_all

/- `check_sound` is the sole composition theorem.  Every image fact is taken
   from the dependent certificate-owned image and exact ELF slices. -/
theorem check_sound {encoded : String}
    {expectedSources : List Extraction.SourceFile}
    {resolver : ExternalBehaviorResolver}
    (checked : Checked encoded expectedSources resolver) :
    Soundness encoded expectedSources resolver checked := by
  have certificate :=
    Extraction.CertificateBoundary.check_sound checked.certificate.certificateAccepted
  have programLowering :=
    CertificateLoweringCheck.program_sound checked.certificateAccepted
  have imageMetadata :=
    X86.CertificateImageCheck.check_sound checked.imageMetadataAccepted
  have transportTarget := transport_target certificate.2.2.2.2.2.2.2.2.2
  have loadedFromElf := fun (machine : X86.Machine.State)
      (mapped : X86.Machine.CodeAt machine.memory X86.ImageCheck.lanius.base
        checked.certificate.certificate.certificate.elf) =>
    X86.ProgramCheck.Authenticated.loaded_of_slices checked.program machine
      (fun function member => checked.image.slice_loaded mapped function member)
  refine {
    programLowering := ⟨checked.certificate.lowering, rfl, programLowering⟩
    programLoweringProgram := programLowering
    decodedCertificate := certificate.1
    decodedCompact := certificate.2.1
    sourceExact := certificate.2.2.1
    sourceWellFormed := certificate.2.2.2.1
    catalogWellFormed := certificate.2.2.2.2.1
    importsCovered := certificate.2.2.2.2.2.1
    declarationsExact := certificate.2.2.2.2.2.2.1
    typed := certificate.2.2.2.2.2.2.2.1
    executableWellFormed := certificate.2.2.2.2.2.2.2.2.1
    canonicalTransport := certificate.2.2.2.2.2.2.2.2.2
    programTarget := transportTarget
    enumerationsEmpty := checked.enumerationsEmpty
    spanCountExact := imageMetadata.1
    spansWellFormed := imageMetadata.2
    functionsExact := X86.ProgramCheck.Authenticated.functions_exact checked.program
    imageExact := X86.ProgramCheck.Authenticated.images_exact checked.program
    programSlicesExact :=
      (X86.ProgramCheck.Authenticated.images_exact checked.program).trans
        checked.image.slicesExact.symm
    entrypointExact := X86.ProgramCheck.Authenticated.entrypoint_exact checked.program
    entrypointZeroParameters :=
      X86.ProgramCheck.Authenticated.entrypoint_zero_parameters checked.program
    functionsAuthenticated :=
      X86.ProgramCheck.Authenticated.bytes_authenticated checked.program
    headerAuthenticated := checked.image.header.fieldsChecked
    headerLengthBound := checked.image.header.lengthBound
    slicesExact := checked.image.slicesExact
    loadedFromElf
    entrypointPreserves := by
      intro coreBefore machineBefore loaded environment ripAtEntry returnAddress poppedReturn
      exact checked.program.entrypoint_preserves coreBefore machineBefore loaded
        environment ripAtEntry returnAddress poppedReturn }

end Lanius.Compiler.EndToEndCheck
