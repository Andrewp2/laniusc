import Lanius.X86.FunctionCheck

namespace Lanius.X86.FunctionCheckTests

open Lanius Lanius.Core
open Lanius.X86
open Lanius.X86.FunctionCheck

private def literalFunction : Function := {
  id := 7
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some (.returnValue (some (.value (.signed .i32 42))))
  external := none }

private def boolFunction : Function := {
  id := 8
  parameters := []
  returnType := .scalar .bool
  body := some (.returnValue (some (.value (.boolean true))))
  external := none }

private def trailingLiteralFunction : Function := {
  literalFunction with
    body := some (.sequence
      (.returnValue (some (.value (.signed .i32 42)))) .skip) }

private def parameterFunction : Function := {
  id := 9
  parameters := [(3, .scalar (.signed .i32)), (8, .scalar (.signed .i32))]
  returnType := .scalar (.signed .i32)
  body := some (.sequence (.returnValue (some (.local 8))) .skip)
  external := none }

private def wrongShapeFunction : Function := {
  literalFunction with body := some .skip }

private def literalBytes : List UInt8 :=
  LiteralReturn.bytes (.i32 (BitVec.ofNat 32 42))

private def boolBytes : List UInt8 := LiteralReturn.bytes (.bool true)

private def parameterBytes : List UInt8 :=
  ParameterReturn.bytes ⟨1, by decide⟩

/- This is the exact 2+3 sequence emitted by the current compiler's
   frame-slot binary-add lowering, including the unreachable UD2 trailer. -/
private def addFunction : Function := {
  id := 0
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some (.returnValue (some (.binary .add
    (.value (.signed .i32 2)) (.value (.signed .i32 3)))))
  external := none }

private def addBytes : List UInt8 := ScalarValidator.binaryLiteralFunctionBytes .add
  (BitVec.ofNat 32 2) (BitVec.ofNat 32 3)

#eval (check literalFunction literalBytes).isSome -- true
#eval (check boolFunction boolBytes).isSome -- true
#eval (check trailingLiteralFunction literalBytes).isSome -- true
#eval (check parameterFunction parameterBytes).isSome -- true
#eval (check literalFunction (literalBytes ++ [0])).isSome -- false
#eval (check parameterFunction [195]).isSome -- false
#eval (check wrongShapeFunction literalBytes).isSome -- false
#eval (check addFunction addBytes).isSome -- true
#eval (check addFunction (addBytes.set 0 0)).isSome -- false
/- A successful constructor contains the authenticated byte equality used by
   the corresponding function-level preservation path. -/
example (supported : LiteralReturn.Supported literalFunction)
    (bytesExact : literalBytes = LiteralReturn.bytes supported.literal) :
    Checked literalFunction literalBytes :=
  .literal supported bytesExact

example (supported : ParameterReturn.Supported parameterFunction)
    (bytesExact : parameterBytes = ParameterReturn.bytes supported.argument) :
    Checked parameterFunction parameterBytes :=
  .parameter supported bytesExact

example {function : Function} {emitted : List UInt8}
    {checked : Checked function emitted}
    (accepted : check function emitted = some checked) :
    Checked.Authenticated checked :=
  check_sound accepted

example {function : Function} {emitted : List UInt8}
    {checked : Checked function emitted}
    (accepted : check function emitted = some checked) :
    functionAllocationCount function ≤ 2^28 := by
  generalize h : check function emitted = result at accepted
  cases result with
  | none => simp at accepted
  | some proof =>
      have equal : proof = checked := Option.some.inj accepted
      subst checked
      exact Checked.function_allocation_count_le proof

end Lanius.X86.FunctionCheckTests
