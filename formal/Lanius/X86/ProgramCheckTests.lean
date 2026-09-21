import Lanius.X86.ProgramCheck
import Lanius.X86.DirectCallFunctionCheck
import Lanius.X86.CertificateImageCheck
import Lanius.X86.Transport

namespace Lanius.X86.ProgramCheckTests

open Lanius Lanius.Core
open Lanius.X86
open Lanius.X86.Machine
open Lanius.X86.ProgramCheck
open Lanius.X86.DirectCallFunctionCheck
open Lanius.X86.CertificateImageCheck
open Lanius.X86.Transport
open Lanius.X86.ScalarValidator
open Lanius.Extraction

private def literalFunction : Function := {
  id := 7
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some (.returnValue (some (.value (.signed .i32 42))))
  external := none }

private def parameterFunction : Function := {
  id := 9
  parameters := [(3, .scalar (.signed .i32))]
  returnType := .scalar (.signed .i32)
  body := some (.returnValue (some (.local 3)))
  external := none }

private def addFunction : Function := {
  id := 11
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some (.returnValue (some (.binary .add
    (.value (.signed .i32 2)) (.value (.signed .i32 3)))))
  external := none }

private def executable : Execution.Executable := {
  program := { target := .x86_64, functions := [literalFunction, parameterFunction] }
  entrypoint := 7 }

private def image : Image := {
  functions := [
    { address := 512, bytes := LiteralReturn.bytes (.i32 (BitVec.ofNat 32 42)) },
    { address := 528, bytes := ParameterReturn.bytes ⟨0, by decide⟩ }]
  }

#eval (check executable image).isSome -- true
#eval (check executable { image with functions := image.functions ++ [{ address := 544, bytes := [] }] }).isSome -- false

private def parameterEntrypoint : Execution.Executable := { executable with entrypoint := 9 }
#eval (check parameterEntrypoint image).isSome -- false

private def addExecutable : Execution.Executable := {
  program := { target := .x86_64, functions := [addFunction] }
  entrypoint := 11 }

private def addImage : Image := {
  functions := [
    { address := 544,
      bytes := ScalarValidator.binaryLiteralFunctionBytes .add
        (BitVec.ofNat 32 2) (BitVec.ofNat 32 3) }] }

#eval (check addExecutable addImage).isSome -- true
#eval (check addExecutable { functions :=
  [{ address := 544, bytes := [85] }] }).isSome -- false

/- This is the connected scalar-local body path: the initializer is lowered to
   an immediate, stored in frame slot 0, then read back by the local-expression
   certificate before the ordinary epilogue. -/
private def letLocalFunction : Function := {
  id := 19
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some (.letLocal 23 (.scalar (.signed .i32))
    (.value (.signed .i32 2))
    (.returnValue (some (.local 23))))
  external := none }

private def wrongTypeLetLocalFunction : Function := {
  letLocalFunction with
    body := some (.letLocal 23 (.scalar .bool) (.value (.signed .i32 2))
      (.returnValue (some (.local 23)))) }

private def letLocalExecutable : Execution.Executable := {
  program := { target := .x86_64, functions := [letLocalFunction] }
  entrypoint := letLocalFunction.id }

private def letLocalBytes : List UInt8 :=
  framePrologueBytes 1 ++
    immediateBytes .w32 ScalarValidator.resultRegister (BitVec.ofNat 32 2) 0 ++
    frameStoreBytes 0 ++ frameLoadBytes 0 ++ binaryEpilogueBytes ++ ud2Bytes

private def letLocalImage : Image := {
  functions := [
    { address := 560, bytes := letLocalBytes }] }

#eval (check letLocalExecutable letLocalImage).isSome -- true

#eval (FunctionCheck.check wrongTypeLetLocalFunction letLocalBytes).isSome -- false

example : (check letLocalExecutable letLocalImage).isSome := by
  decide

example : (FunctionCheck.check wrongTypeLetLocalFunction letLocalBytes).isNone := by
  decide

example {checked : Checked executable image} (accepted : check executable image = some checked) :
    checked.entrypoint.function.id = 7 ∧ checked.entrypoint.function.parameters = [] :=
  check_sound accepted

private def directCallee : Function := {
  id := 42
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some (.returnValue (some (.value (.signed .i32 7))))
  external := none }

private def directCaller : Function := {
  id := 43
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some (.returnValue (some (.call directCallee.id [])))
  external := none }

private def directDisplacement : BitVec 32 := BitVec.ofNat 32 32
private def directCallerAddress : Machine.Address := BitVec.ofNat 64 4096
private def directCalleeAddress : Machine.Address :=
  callSite directCallerAddress + BitVec.ofNat 64 (Machine.callBytes directDisplacement).length +
    directDisplacement.signExtend 64

private def directExecutable : Execution.Executable := {
  program := { target := .x86_64, functions := [directCaller, directCallee] }
  entrypoint := directCaller.id }

private def directImage : Image := {
  functions := [
    { address := directCallerAddress, bytes := functionBytes directDisplacement },
    { address := directCalleeAddress,
      bytes := LiteralReturn.bytes (.i32 (BitVec.ofNat 32 7)) }] }

private def directUnrelated : Function := {
  id := 99
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some (.returnValue (some (.value (.signed .i32 11))))
  external := none }

private def directThreeExecutable : Execution.Executable := {
  program := { target := .x86_64, functions := [directCaller, directUnrelated, directCallee] }
  entrypoint := directCaller.id }

private def directThreeImage : Image := {
  functions := [
    { address := directCallerAddress, bytes := functionBytes directDisplacement },
    { address := BitVec.ofNat 64 8192,
      bytes := LiteralReturn.bytes (.i32 (BitVec.ofNat 32 11)) },
    { address := directCalleeAddress,
      bytes := LiteralReturn.bytes (.i32 (BitVec.ofNat 32 7)) }] }

example : (checkDirect directThreeExecutable directThreeImage
    directDisplacement).isSome = true := by
  decide

private def bodyDirectCallee : Function := {
  id := 44
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some (.returnValue (some (.binary .add
    (.value (.signed .i32 2)) (.value (.signed .i32 3)))))
  external := none }

private def bodyDirectCaller : Function := {
  id := 45
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some (.returnValue (some (.call bodyDirectCallee.id [])))
  external := none }

private def bodyDirectDisplacement : BitVec 32 := BitVec.ofNat 32 32
private def bodyDirectCallerAddress : Machine.Address := BitVec.ofNat 64 12288
private def bodyDirectCalleeAddress : Machine.Address :=
  callSite bodyDirectCallerAddress + BitVec.ofNat 64
      (Machine.callBytes bodyDirectDisplacement).length +
    bodyDirectDisplacement.signExtend 64

private def bodyDirectExecutable : Execution.Executable := {
  program := { target := .x86_64, functions := [bodyDirectCaller, bodyDirectCallee] }
  entrypoint := bodyDirectCaller.id }

private def bodyDirectImage : Image := {
  functions := [
    { address := bodyDirectCallerAddress,
      bytes := functionBytes bodyDirectDisplacement },
    { address := bodyDirectCalleeAddress,
      bytes := ScalarValidator.binaryLiteralFunctionBytes .add
        (BitVec.ofNat 32 2) (BitVec.ofNat 32 3) }] }

/- Generic body certificates are retained by the direct checker even though
   their machine preservation theorem is intentionally a later step. -/
example : (checkDirect bodyDirectExecutable bodyDirectImage
    bodyDirectDisplacement).isSome = true := by
  decide

example : (checkDirectDerived directThreeExecutable directThreeImage).isSome = true := by
  decide

private def badDirectCalleeImage : Image := {
  functions := [
    { address := directCallerAddress, bytes := functionBytes directDisplacement },
    { address := directCalleeAddress, bytes := [195] }] }

private def overlappingDirectImage : Image := {
  functions := [
    { address := directCallerAddress, bytes := functionBytes directDisplacement },
    { address := directCallerAddress,
      bytes := LiteralReturn.bytes (.i32 (BitVec.ofNat 32 7)) }] }

example : (checkDirect directExecutable directImage directDisplacement).isSome = true := by
  rfl

example : (checkDirect directExecutable
    badDirectCalleeImage directDisplacement).isSome = false := by
  rfl

example : (checkDirect directExecutable
    overlappingDirectImage directDisplacement).isSome = false := by
  rfl

private def wrongDirectEntrypoint : Execution.Executable :=
  { directExecutable with entrypoint := directCallee.id }

example : (checkDirect wrongDirectEntrypoint directImage directDisplacement).isSome = false := by
  rfl

example {checked : DirectChecked directExecutable directImage directDisplacement}
    (accepted : checkDirect directExecutable directImage directDisplacement = some checked) :
    checked.callerImage.bytes = functionBytes directDisplacement ∧
      FunctionCheck.Checked.Authenticated checked.calleeChecked :=
  checkDirect_sound accepted

/- Exact current backend shape used by the two-function certificate fixture. -/
private def emittedCaller : Function := {
  id := 0
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some (.returnValue (some (.call 1 [])))
  external := none }

private def emittedCallee : Function := {
  id := 1
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some (.returnValue (some (.value (.signed .i32 7))))
  external := none }

private def emittedCallerBytes : List UInt8 := [
  85, 72, 137, 229, 65, 187, 16, 0, 0, 0, 76, 41, 220,
  232, 7, 0, 0, 0, 72, 137, 236, 93, 195, 15, 11]
private def emittedCalleeBytes : List UInt8 := [184, 7, 0, 0, 0, 195]
private def emittedElf : List UInt8 :=
  List.replicate 517 0 ++ emittedCallerBytes ++ emittedCalleeBytes
private def emittedSpans : List FunctionSpan :=
  [{ start := 517, length := 25 }, { start := 542, length := 6 }]
private def emittedExecutable : Execution.Executable := {
  program := { target := .x86_64, functions := [emittedCaller, emittedCallee] }
  entrypoint := 0 }
private def emittedImage : Image := { functions := [
  { address := ImageCheck.lanius.base + BitVec.ofNat 64 517,
    bytes := emittedCallerBytes },
  { address := ImageCheck.lanius.base + BitVec.ofNat 64 542,
    bytes := emittedCalleeBytes }] }

example : emittedCallerBytes = functionBytes (BitVec.ofNat 32 7) := by decide
example : emittedCalleeBytes = LiteralReturn.bytes (.i32 (BitVec.ofNat 32 7)) := by decide
example : (checkAuthenticated emittedExecutable emittedImage).isSome = true := by
  rfl

private def certificateDirectProgram : Program :=
  { functions := [directCaller, directCallee] }
private def certificateDirectWords : List Int :=
  [2, 64, 43, 0, 0, 2,
   11, 1, 64, 43, 1, 0, 5, 10, 1, 14, 42, 0,
   11, 1, 64, 42, 1, 0, 5, 10, 1, 0, 1, 7]
private def certificateDirectElf : List UInt8 :=
  [233, 0, 0, 0, 0] ++ functionBytes (BitVec.ofNat 32 7) ++
    LiteralReturn.bytes (.i32 (BitVec.ofNat 32 7))
private def certificateDirectExpectedElf : List UInt8 := [
  233, 0, 0, 0, 0,
  85, 72, 137, 229, 65, 187, 16, 0, 0, 0, 76, 41, 220,
  232, 7, 0, 0, 0, 72, 137, 236, 93, 195, 15, 11,
  184, 7, 0, 0, 0, 195]
private def certificateDirectSpans : List FunctionSpan :=
  [{ start := 5, length := 25 }, { start := 30, length := 6 }]
private def certificateDirect : Certificate := {
  compact := ""
  transport := certificateDirectWords
  elf := certificateDirectElf
  functions := certificateDirectSpans }
private def certificateDirectImage : Image :=
  { functions := imagesOf certificateDirectElf certificateDirectSpans }
private def certificateDirectExecutable : Execution.Executable := {
  program := certificateDirectProgram
  entrypoint := directCaller.id }

example : encodeProgram 43 certificateDirectProgram = some certificateDirectWords := by
  simp [certificateDirectProgram, directCaller, directCallee, certificateDirectWords,
    encodeProgram, encodeFunction, encodeParameters, encodeStmt, encodeExpr,
    encodeValue, typeTag]

example : certificateDirectElf = certificateDirectExpectedElf := by
  decide

example : (CertificateImageCheck.check certificateDirectExecutable certificateDirect).isSome = true := by
  rfl

example : (checkDirect certificateDirectExecutable certificateDirectImage
    (BitVec.ofNat 32 7)).isSome = true := by
  rfl

end Lanius.X86.ProgramCheckTests
