import Lanius.Extraction.Certificate
import Lanius.X86.ImageCheck

namespace Lanius.X86.CertificateImageCheck

open Lanius Lanius.Compiler Lanius.Extraction
open Lanius.X86
open Lanius.X86.ProgramCheck

/-! The certificate carries an ELF byte string and the backend work-table
    spans as offsets in that string.  This boundary is intentionally small:
    it authenticates the spans and constructs the `ProgramCheck.Image`; the
    existing `ProgramCheck` then checks each extracted slice against Core. -/

def imageOfSpan (elf : List UInt8) (span : FunctionSpan) : FunctionImage :=
  { address := ImageCheck.lanius.base + BitVec.ofNat 64 span.start
    bytes := (elf.drop span.start).take span.length }

def imagesOf (elf : List UInt8) : List FunctionSpan → List FunctionImage
  | [] => []
  | span :: spans => imageOfSpan elf span :: imagesOf elf spans

def spanOK (elfLength previous : Nat) (span : FunctionSpan) : Bool :=
  span.length > 0 &&
    previous ≤ span.start &&
    span.start ≤ elfLength &&
    span.length ≤ elfLength - span.start &&
    ImageCheck.lanius.base.toNat + span.start < 2 ^ 64

def spansOK (elfLength previous : Nat) : List FunctionSpan → Bool
  | [] => true
  | span :: spans =>
      spanOK elfLength previous span &&
        spansOK elfLength (span.start + span.length) spans

structure Checked (executable : Execution.Executable)
    (certificate : Certificate) where
  image : ProgramCheck.Image
  countExact : certificate.functions.length = executable.program.functions.length
  spansChecked : spansOK certificate.elf.length 0 certificate.functions = true
  imageExact : image.functions = imagesOf certificate.elf certificate.functions

def check (executable : Execution.Executable) (certificate : Certificate) :
    Option (Checked executable certificate) :=
  if countExact : certificate.functions.length = executable.program.functions.length then
    if spansChecked : spansOK certificate.elf.length 0 certificate.functions = true then
      let image : ProgramCheck.Image :=
        { functions := imagesOf certificate.elf certificate.functions }
      some { image, countExact, spansChecked, imageExact := rfl }
    else none
  else none

theorem Checked.image_functions
    {executable : Execution.Executable} {certificate : Certificate}
    (checked : Checked executable certificate) :
    checked.image.functions = imagesOf certificate.elf certificate.functions :=
  checked.imageExact

theorem check_sound {executable : Execution.Executable} {certificate : Certificate}
    {checked : Checked executable certificate}
    (_accepted : check executable certificate = some checked) :
    certificate.functions.length = executable.program.functions.length ∧
      spansOK certificate.elf.length 0 certificate.functions = true :=
  ⟨checked.countExact, checked.spansChecked⟩

end Lanius.X86.CertificateImageCheck
