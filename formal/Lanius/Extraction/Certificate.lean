import Lanius.Extraction.CompactBoundary
import Lanius.Compiler.BackendBoundary
import Lanius.Compiler.CoreBoundary
import Lanius.Compiler.FrontendBoundary

namespace Lanius.Extraction

/-! The compiler certificate is an envelope around the existing compact source
    pack, canonical signed-i32 Core transport, and the exact emitted ELF.
    Version 3 additionally carries ordered function start/length metadata.
    Decoding does not trust any payload: the compact slice is passed to the
    existing frontend checker, the words to `BackendBoundary.check`, and the
    ELF/span data to the image boundary after the Core program is joined back
    by `CoreBoundary.check`. -/

structure FunctionSpan where
  start : Nat
  length : Nat
deriving DecidableEq, Repr

structure Certificate where
  compact : String
  transport : List Int
  elf : List UInt8
  functions : List FunctionSpan
deriving DecidableEq, Repr

namespace CertificateDecode

open CompactDecode

def readSignedWord : DecodeM Int := do
  let value ← readHexNat 8 0
  if value < 2147483648 then
    pure (Int.ofNat value)
  else
    pure (Int.ofNat value - 4294967296)

def readCertificate : DecodeM Certificate := do
  let version ← readU32
  if version != 3 then failure
  let compactLength ← readU32
  let compactBytes ← readRawBytes compactLength
  let some compact := String.fromUTF8? compactBytes
    | failure
  let count ← readU32
  let transport ← readMany count readSignedWord
  let elfLength ← readU32
  let elf ← readBytes elfLength
  let functionCount ← readU32
  let functions ← readMany functionCount do
    let start ← readU32
    let length ← readU32
    pure { start, length }
  let state ← get
  if state.offset != state.bytes.size then failure
  pure { compact, transport, elf := elf.toList, functions }

end CertificateDecode

def decodeCertificate? (encoded : String) : Option Certificate :=
  (CertificateDecode.readCertificate.run
    { bytes := encoded.toUTF8, offset := 0 }).map Prod.fst

namespace CertificateBoundary

open Lanius.Compiler
open Lanius.Declarations

inductive Failure where
  | decode
  | compact (failure : FrontendBoundary.Failure)
  | backend (failure : BackendBoundary.Failure)
  | core (failure : CoreBoundary.Failure)
deriving DecidableEq, Repr

structure Checked (encoded : String)
    (expectedSources : List SourceFile) where
  certificate : Certificate
  decoded : decodeCertificate? encoded = some certificate
  frontend : FrontendBoundary.Checked certificate.compact expectedSources
  frontendAccepted : FrontendBoundary.check certificate.compact expectedSources =
    .ok frontend
  backend : BackendBoundary.Checked certificate.transport
  backendAccepted : BackendBoundary.check certificate.transport = .ok backend
  core : CoreBoundary.Checked certificate.compact expectedSources frontend
    backend.executable.program
  coreAccepted : CoreBoundary.check frontend backend.executable.program = .ok core

def check (encoded : String) (expectedSources : List SourceFile) :
    Except Failure (Checked encoded expectedSources) :=
  match decoded : decodeCertificate? encoded with
  | none => .error .decode
  | some certificate =>
      match frontendAccepted : FrontendBoundary.check certificate.compact expectedSources with
      | .error failure => .error (.compact failure)
      | .ok frontend =>
          match backendAccepted : BackendBoundary.check certificate.transport with
          | .error failure => .error (.backend failure)
          | .ok backend =>
              match coreAccepted :
                  CoreBoundary.check frontend backend.executable.program with
              | .error failure => .error (.core failure)
              | .ok core =>
                  .ok {
                    certificate
                    decoded
                    frontend
                    frontendAccepted
                    backend
                    backendAccepted
                    core
                    coreAccepted
                  }

theorem check_sound {encoded : String} {expectedSources : List SourceFile}
    {checked : Checked encoded expectedSources}
    (_accepted : check encoded expectedSources = .ok checked) :
    decodeCertificate? encoded = some checked.certificate ∧
      decodeCompactPack? checked.certificate.compact =
        some checked.frontend.frontend.compact.compact.pack ∧
      compactPackSources checked.frontend.frontend.compact.compact.pack =
        expectedSources ∧
      SourcePackWellFormed
        (FrontendBoundary.frontendPack checked.frontend.frontend) ∧
      CatalogWellFormed
        (FrontendBoundary.frontendPack checked.frontend.frontend)
        checked.frontend.catalog.catalog ∧
      ImportCollectionCovers
        (FrontendBoundary.frontendPack checked.frontend.frontend)
        checked.frontend.imports ∧
      ProgramLowering.DeclarationLoweringsExact
        (FrontendBoundary.frontendPack checked.frontend.frontend)
        checked.frontend.catalog.catalog checked.backend.executable.program
        checked.core.declarations.rows ∧
      Typing.ProgramWellTyped checked.backend.executable.program ∧
      Execution.ExecutableWellFormed checked.backend.executable ∧
      X86.Transport.EncodesProgram checked.backend.executable.entrypoint
        checked.backend.executable.program checked.certificate.transport := by
  have frontend := FrontendBoundary.checked_source_evidence
    (checked := checked.frontend)
  have backend := BackendBoundary.check_sound checked.backendAccepted
  have core := CoreBoundary.check_sound checked.coreAccepted
  exact ⟨checked.decoded, frontend.1, frontend.2.1,
    core.1, core.2.1, core.2.2.1, core.2.2.2.1,
    core.2.2.2.2, backend.2.1, backend.2.2⟩

end CertificateBoundary

end Lanius.Extraction
