import Lanius.X86.ProgramCheck

namespace Lanius.X86.ExpressionFunctionCheckTests

open Lanius Lanius.Core
open Lanius.X86
open Lanius.X86.Machine
open Lanius.X86.ProgramCheck
open Lanius.X86.ScalarValidator

private def literalTwo : Core.Expr := .value (.signed .i32 2)
private def literalThree : Core.Expr := .value (.signed .i32 3)
private def literalFour : Core.Expr := .value (.signed .i32 4)
private def literalFive : Core.Expr := .value (.signed .i32 5)
private def addTwoThree : Core.Expr := .binary .add literalTwo literalThree
private def nestedAdd : Core.Expr := .binary .add addTwoThree literalFour
private def deepAdd : Core.Expr := .binary .add nestedAdd literalFive

private def nestedBody : List UInt8 :=
  immediateBytes .w32 resultRegister (BitVec.ofNat 32 2) 0 ++
    frameStoreBytes 0 ++
    immediateBytes .w32 resultRegister (BitVec.ofNat 32 3) 0 ++
    frameAluBytes 0 .add ++
    frameStoreBytes 1 ++
    immediateBytes .w32 resultRegister (BitVec.ofNat 32 4) 0 ++
    frameAluBytes 1 .add

private def nestedFunction : Function := {
  id := 17
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some (.returnValue (some nestedAdd))
  external := none }

private def nestedBytes : List UInt8 :=
  framePrologueBytes 2 ++ nestedBody ++ binaryEpilogueBytes ++ ud2Bytes

private def deepBody : List UInt8 :=
  nestedBody ++ frameStoreBytes 2 ++
    immediateBytes .w32 resultRegister (BitVec.ofNat 32 5) 0 ++
    frameAluBytes 2 .add

private def deepFunction : Function := {
  id := 18
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some (.returnValue (some deepAdd))
  external := none }

private def deepBytes : List UInt8 :=
  framePrologueBytes 3 ++ deepBody ++ binaryEpilogueBytes ++ ud2Bytes

private def letLocalFunction : Function := {
  id := 19
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some (.letLocal 23 (.scalar (.signed .i32)) literalTwo
    (.returnValue (some (.local 23))))
  external := none }

private def letLocalBytes : List UInt8 :=
  framePrologueBytes 1 ++ immediateBytes .w32 resultRegister (BitVec.ofNat 32 2) 0 ++
    frameStoreBytes 0 ++ frameLoadBytes 0 ++ binaryEpilogueBytes ++ ud2Bytes

private def nestedExecutable : Execution.Executable := {
  program := { target := .x86_64, functions := [nestedFunction] }
  entrypoint := nestedFunction.id }

private def nestedImage : Image := {
  functions := [{ address := 4096, bytes := nestedBytes }] }

#eval (FunctionCheck.check nestedFunction nestedBytes).isSome
#eval (ProgramCheck.check nestedExecutable nestedImage).isSome
#eval (FunctionCheck.check deepFunction deepBytes).isSome
#eval (FunctionCheck.check letLocalFunction letLocalBytes).isSome

example : framePrologueBytes 3 ≠ framePrologueBytes 1 := by
  decide

example : (FunctionCheck.check deepFunction deepBytes).isSome := by
  decide

example : (FunctionCheck.check nestedFunction nestedBytes).isSome := by
  decide

example : (FunctionCheck.check letLocalFunction letLocalBytes).isSome := by
  decide

example : ExpressionFunctionCheck.checkBodyValue? nestedFunction nestedBytes =
    some (.signed .i32 9) := by
  rfl

example : ExpressionFunctionCheck.checkBodyValue? letLocalFunction letLocalBytes =
    some (.signed .i32 2) := by
  rfl

example : (ProgramCheck.check nestedExecutable nestedImage).isSome := by
  decide

example {checked : FunctionCheck.Checked nestedFunction nestedBytes}
    (accepted : FunctionCheck.check nestedFunction nestedBytes = some checked) :
    FunctionCheck.Checked.Authenticated checked :=
  FunctionCheck.check_sound accepted

end Lanius.X86.ExpressionFunctionCheckTests
