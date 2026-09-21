import Lanius.X86.ScalarValidator

namespace Lanius.X86.ScalarValidatorTests

open Lanius Lanius.Core Lanius.X86
open Lanius.X86.ScalarValidator

private def literalFunction : Function := {
  id := 17
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some (.returnValue (some (.value (.signed .i32 42))))
  external := none }

private def literalBytes : List UInt8 :=
  Expr.returnBytes (.lit (.i32 (BitVec.ofNat 32 42)))

private def badFunction : Function :=
  { literalFunction with body := some .skip }

private def binaryFunction : Function := {
  id := 18
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some (.returnValue (some (.binary .add
    (.value (.signed .i32 42)) (.value (.signed .i32 5)))))
  external := none }

private def unsupportedFunction : Function := {
  id := 19
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some (.returnValue (some (.binary .divide
    (.value (.signed .i32 42)) (.value (.signed .i32 5)))))
  external := none }

private def multiplyFunction : Function := {
  id := 21
  parameters := []
  returnType := .scalar (.signed .i32)
  body := some (.returnValue (some (.binary .multiply
    (.value (.signed .i32 6)) (.value (.signed .i32 7)))))
  external := none }

private def wrongParameterType : Function := {
  id := 20
  parameters := [(1, .scalar .bool)]
  returnType := .scalar (.signed .i32)
  body := some (.returnValue (some (.local 1)))
  external := none }

def noRegister : VarId → Option Register := fun _ => none

#eval (check literalFunction noRegister literalBytes).isSome
#eval (check literalFunction noRegister (literalBytes ++ [0])).isSome
#eval (check badFunction noRegister literalBytes).isSome
#eval (check binaryFunction noRegister []).isSome -- composite lowering is not accepted
#eval (check unsupportedFunction noRegister []).isSome
#eval (check multiplyFunction noRegister []).isSome -- frame-slot lowering is not accepted
#eval (check wrongParameterType (fun _ => some 1) []).isSome

example {function : Function} {emitted : List UInt8}
    {checked : Checked function emitted}
    (accepted : check function noRegister emitted = some checked) :
    emitted = checked.supported.expression.returnBytes :=
  check_sound accepted

/- The machine theorem is generic in the literal, and derives its result from
   authenticated bytes plus the initial loaded-code/frame premises. -/
example (literal : LiteralReturn.Literal) (before : Machine.State)
    (loaded : Machine.CodeAt before.memory before.rip
      (Expr.returnBytes (.lit literal)))
    (returnAddress : Machine.Address)
    (poppedReturn : Machine.read64 before.memory (before.registers 4) = returnAddress) :
    ∃ middle after, Machine.Step before middle ∧ Machine.Step middle after := by
  obtain ⟨middle, after, first, second, _, _, _, _, _, _, _, _⟩ :=
    literalPreserves literal before loaded returnAddress poppedReturn
  exact ⟨middle, after, first, second⟩

end Lanius.X86.ScalarValidatorTests
