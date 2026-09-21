import Lanius.X86.AuthenticatedStackFootprint

namespace Lanius.X86.AuthenticatedStackFootprintTests

open Lanius Lanius.Core
open Lanius.X86
open Lanius.X86.Machine
open Lanius.X86.ProgramCheck
open Lanius.X86.ScalarValidator
open Lanius.X86.AuthenticatedStackFootprint

private def literalTwo : Core.Expr := .value (.signed .i32 2)
private def literalThree : Core.Expr := .value (.signed .i32 3)
private def literalFour : Core.Expr := .value (.signed .i32 4)
private def addTwoThree : Core.Expr := .binary .add literalTwo literalThree
private def nestedAdd : Core.Expr := .binary .add addTwoThree literalFour

private def bodyCallee : Function := {
  id := 17
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some (.returnValue (some nestedAdd))
  external := none }

private def bodyCaller : Function := {
  id := 18
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some (.returnValue (some (.call bodyCallee.id [])))
  external := none }

private def displacement : BitVec 32 := BitVec.ofNat 32 32
private def callerAddress : Machine.Address := BitVec.ofNat 64 12288
private def calleeAddress : Machine.Address :=
  DirectCallFunctionCheck.callSite callerAddress +
    BitVec.ofNat 64 (Machine.callBytes displacement).length +
    displacement.signExtend 64

private def nestedBody : List UInt8 :=
  immediateBytes .w32 resultRegister (BitVec.ofNat 32 2) 0 ++
    frameStoreBytes 0 ++
    immediateBytes .w32 resultRegister (BitVec.ofNat 32 3) 0 ++
    frameAluBytes 0 .add ++
    frameStoreBytes 1 ++
    immediateBytes .w32 resultRegister (BitVec.ofNat 32 4) 0 ++
    frameAluBytes 1 .add

private def calleeBytes : List UInt8 :=
  framePrologueBytes 2 ++ nestedBody ++ binaryEpilogueBytes ++ ud2Bytes

private def executable : Execution.Executable := {
  program := { target := .x86_64, functions := [bodyCaller, bodyCallee] }
  entrypoint := bodyCaller.id }

private def image : Image := {
  functions := [
    { address := callerAddress, bytes := DirectCallFunctionCheck.functionBytes displacement },
    { address := calleeAddress, bytes := calleeBytes }] }

example : (checkDirect executable image displacement).isSome = true := by
  decide

/- This is intentionally beyond slot zero: nestedAdd allocates two callee
   slots, so offset 56 (= 48 + 8*1) must be present. -/
example : (checkDirect executable image displacement).map (fun checked =>
    decide (56 ∈ authenticated (.direct displacement checked))) = some true := by
  decide

example : (checkDirect executable image displacement).map (fun checked =>
    decide (72 ∈ authenticatedStartupStackFootprint (.direct displacement checked))) = some true := by
  decide

example : (48 ∉ ([8, 16, 32, 40] : List Nat)) := by decide

end Lanius.X86.AuthenticatedStackFootprintTests
