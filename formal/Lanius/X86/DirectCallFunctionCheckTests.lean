import Lanius.X86.DirectCallFunctionCheck

namespace Lanius.X86.DirectCallFunctionCheckTests

open Lanius Lanius.Core
open Lanius.X86
open Lanius.X86.DirectCallFunctionCheck

private def callee : Function := {
  id := 42
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some (.returnValue (some (.value (.signed .i32 0))))
  external := none }

private def caller : Function := {
  id := 43
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some (.returnValue (some (.call callee.id [])))
  external := none }

private def callerWithParameter : Function :=
  { caller with parameters := [(0, .scalar (.signed .i32))] }

private def boolCallee : Function :=
  { callee with returnType := .scalar .bool }

private def callerAddress : Machine.Address := BitVec.ofNat 64 4096
private def displacement : BitVec 32 := BitVec.ofNat 32 32
private def targetAddress : Machine.Address :=
  callSite callerAddress + BitVec.ofNat 64 (Machine.callBytes displacement).length +
    displacement.signExtend 64

example : (check caller callee callerAddress targetAddress displacement
    (functionBytes displacement)).isSome = true := by
  rfl

example : (check callerWithParameter callee callerAddress targetAddress displacement
    (functionBytes displacement)).isSome = false := by
  decide

example : (check caller boolCallee callerAddress targetAddress displacement
    (functionBytes displacement)).isSome = false := by
  decide

example : (check caller callee callerAddress targetAddress displacement
    [0]).isSome = false := by
  rfl

end Lanius.X86.DirectCallFunctionCheckTests
