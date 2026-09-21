import Lanius.X86.EntrypointRefinement

namespace Lanius.X86.EntrypointRefinementTests

open Lanius Lanius.Core
open Lanius.X86
open Lanius.X86.ProgramCheck
open Lanius.X86.EntrypointRefinement

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

private def executable : Execution.Executable := {
  program := { target := .x86_64, functions := [literalFunction, parameterFunction] }
  entrypoint := 7 }

private def image : Image := {
  functions := [
    { address := 512, bytes := LiteralReturn.bytes (.i32 (BitVec.ofNat 32 42)) },
    { address := 528, bytes := ParameterReturn.bytes ⟨0, by decide⟩ }] }

#eval (check executable image).isSome -- true
#eval (checkAuthenticated executable image).isSome -- true

private def binaryFunction : Function := {
  id := 11
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some (.returnValue (some (.binary .add
    (.value (.signed .i32 2)) (.value (.signed .i32 3)))))
  external := none }

private def binaryExecutable : Execution.Executable := {
  program := { target := .x86_64, functions := [binaryFunction] }
  entrypoint := 11 }

private def binaryImage : Image := {
  functions := [
    { address := 544,
      bytes := ScalarValidator.binaryLiteralFunctionBytes .add
        (BitVec.ofNat 32 2) (BitVec.ofNat 32 3) }] }

#eval (checkAuthenticated binaryExecutable binaryImage).isSome -- true

private def parameterEntrypoint : Execution.Executable :=
  { executable with entrypoint := 9 }

#eval (check parameterEntrypoint image).isSome -- false

example {checked : ProgramCheck.Checked executable image}
    (_accepted : check executable image = some checked) :
    checked.entrypoint.function.parameters = [] := by
  exact checked.entrypointZeroParameters

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
  DirectCallFunctionCheck.callSite directCallerAddress +
    BitVec.ofNat 64 (Machine.callBytes directDisplacement).length +
    directDisplacement.signExtend 64

private def directExecutable : Execution.Executable := {
  program := { target := .x86_64, functions := [directCaller, directCallee] }
  entrypoint := directCaller.id }

private def directImage : Image := {
  functions := [
    { address := directCallerAddress, bytes := DirectCallFunctionCheck.functionBytes directDisplacement },
    { address := directCalleeAddress,
      bytes := LiteralReturn.bytes (.i32 (BitVec.ofNat 32 7)) }] }

#eval (checkAuthenticated directExecutable directImage).isSome -- true

#check Result
#check refines

end Lanius.X86.EntrypointRefinementTests
