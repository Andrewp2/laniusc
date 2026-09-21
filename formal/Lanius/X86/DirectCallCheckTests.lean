import Lanius.X86.DirectCallCheck

namespace Lanius.X86.DirectCallCheckTests

open Lanius Lanius.Core
open Lanius.X86
open Lanius.X86.DirectCallCheck

private def callee : Function := {
  id := 42
  parameters := [(7, .scalar (.signed .i32))]
  returnType := .scalar (.signed .i32)
  body := some (.returnValue (some (.value (.signed .i32 0))))
  external := none }

private def tooManyParameters : Function :=
  { callee with parameters := List.replicate 7 (7, .scalar (.signed .i32)) }

private def callerAddress : Machine.Address := BitVec.ofNat 64 4096
private def displacement : BitVec 32 := BitVec.ofNat 32 32
private def targetAddress : Machine.Address :=
  callerAddress + BitVec.ofNat 64 (Machine.callBytes displacement).length +
    displacement.signExtend 64

#eval (check callee callee.parameters.length callerAddress targetAddress displacement
  (callBytes displacement) returnBytes).isSome -- true
#eval (check callee 0 callerAddress targetAddress displacement
  (callBytes displacement) returnBytes).isSome -- false: arity metadata
#eval (check callee callee.parameters.length callerAddress callerAddress displacement
  (callBytes displacement) returnBytes).isSome -- false: target
#eval (check callee callee.parameters.length callerAddress targetAddress displacement
  [232, 0, 0, 0] returnBytes).isSome -- false: truncated call
#eval (check callee callee.parameters.length callerAddress targetAddress (BitVec.ofNat 32 31)
  (callBytes displacement) returnBytes).isSome -- false: malformed displacement
#eval (check callee callee.parameters.length callerAddress targetAddress displacement
  (callBytes displacement) [194]).isSome -- false: malformed return
#eval (check tooManyParameters 7 callerAddress targetAddress displacement
  (callBytes displacement) returnBytes).isSome -- false: unsupported arity

example {function : Function} {arity : Nat} {caller target : Machine.Address}
    {displacement : BitVec 32} {callEmitted returnEmitted : List UInt8}
    {checked : Checked function arity caller target displacement callEmitted returnEmitted}
    (accepted : check function arity caller target displacement callEmitted returnEmitted =
      some checked) :
    callEmitted = callBytes displacement ∧ returnEmitted = returnBytes := by
  exact ⟨(check_sound accepted).1, (check_sound accepted).2.1⟩

end Lanius.X86.DirectCallCheckTests
