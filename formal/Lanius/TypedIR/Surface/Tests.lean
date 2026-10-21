import Lanius.TypedIR.Surface.Syntax
import Lanius.Execution

namespace Lanius.TypedIR.Surface.Tests
open Lanius
open scoped Surface

inductive Choice | none | some (value : I32)
attribute [lanius_type enum 0] Choice

def main : Function [] I32 :=
  function (id := 1, name := "main", arguments := [], bindings := [25, 42]) do
    let selected : Choice := (.some 7 : Choice)
    return match selected with
      | .some value => value
      | .none => 0

example : main.name = "main" := rfl

example : main.core.body = some
    (.letLocal 25 (.enumeration 0) (.enumValue 0 1 [.value (.signed .i32 7)])
      (.returnValue (some (.matchValue (.local 25)
        [(.enumVariant 0 1 [.bind 42], .local 42), (.enumVariant 0 0 [], .value (.signed .i32 0))])))) := rfl

def program : Core.Program :=
  { enumerations := [⟨0, [[], [.scalar (.signed .i32)]]⟩], functions := [main.pack] }
example : (match Execution.run 128 { program, entrypoint := 1 } {} with
  | .returned (.signed .i32 7) _ => true | _ => false) = true := by decide

-- Calls record their arguments without carrying a callee parameter-type list.
-- Signatures belong to function declarations and are checked by Lanius.
private def callee : Function [I32] I32 :=
  function (id := 9, name := "callee", arguments := [value := 1], bindings := []) do
    return value
example : (Expr.call callee
    (.cons (Expr.bool true) .nil)).core = .call 9 [.value (.boolean true)] := rfl
example : (Expr.call callee
    .nil).core = .call 9 [] := rfl

private def uncheckedCall : Function [] Bool :=
  function (id := 3, name := "unchecked", arguments := [], bindings := []) do
    return callee true
example : uncheckedCall.core.returnType = .scalar .bool ∧
    uncheckedCall.core.body = some (.returnValue (some (.call 9 [.value (.boolean true)]))) :=
  ⟨rfl, rfl⟩

-- Scope identities, constants and large literals are data, not local proofs.
example : (Expr.local (Var.named 42 "x" : Var I32)).core = .local 42 := rfl
example : (Expr.constant (constant (id := 5) true : Constant Bool)).core = .constant 5 := rfl
example : (constant (id := 6) -2147483648 : Constant I32).core =
    ⟨6, .scalar (.signed .i32), .signed .i32 (-2147483648)⟩ := rfl
example : (constant (id := 7) 0xffffffffffffffff : Constant Usize).core =
    ⟨7, .scalar (.unsigned .usize), .unsigned .usize 18446744073709551615⟩ := rfl
example : (constant (id := 7) 0x00000001ffffffff : Constant Usize).core.value =
    .unsigned .usize 8589934591 := rfl
example : (constant (id := 7) 0x8000000000000000 : Constant Usize).core.value =
    .unsigned .usize 9223372036854775808 := rfl
example : (constant (id := 8) "A\x00é" : Constant String).core =
    ⟨8, .scalar .string, .string "A\x00é"⟩ := rfl
example : (constant (id := 9) 0 : Constant RawPtr).core =
    ⟨9, .scalar .rawPtr, .pointer 0⟩ := rfl
example : (Expr.i32 2147483648).core = .value (.signed .i32 2147483648) := rfl

private def minimumLiteral : Function [] I32 :=
  function (id := 0, name := "minimum", arguments := [], bindings := []) do
    return -2147483648
example : minimumLiteral.core.body = some
    (.returnValue (some (.value (.signed .i32 (-2147483648))))) := rfl

private def ordinaryNegative : Function [] I32 :=
  function (id := 0, name := "negative", arguments := [], bindings := []) do
    return -7
example : ordinaryNegative.core.body = some
    (.returnValue (some (.unary .negate (.value (.signed .i32 7))))) := rfl

private def shadow : Function [] I32 :=
  function (id := 2, name := "shadow", arguments := [], bindings := [1, 2]) do
    let value : I32 := 7
    do
      let value : Bool := true
      value := false
    return value
example : shadow.core.body = some
    (.letLocal 1 (.scalar (.signed .i32)) (.value (.signed .i32 7))
      (.sequence (.letLocal 2 (.scalar .bool) (.value (.boolean true))
        (.expression (.assign .set (.local 2) (.value (.boolean false)))))
        (.returnValue (some (.local 1))))) := rfl

private def identity (α : Type) [Code α] (argument : Var α) : Function [α] α :=
  function (id := 1, name := "identity", arguments := [argument := argument.id], bindings := []) do
    return argument
example (α : Type) [Code α] (argument : Var α) :
    (identity α argument).core.body = some (.returnValue (some (.local argument.id))) := rfl
example (α : Type) [Code α] (argument : Var α) :
    (identity α argument).core.parameters = [(argument.id, Code.ty α)] := rfl

-- Names and IDs bind directly; the signature supplies their labels in order.
private def select : Function [Bool, I32] I32 :=
  function (id := 4, name := "select", arguments := [flag := 31, value := 72], bindings := []) do
    if flag then
      return value
    else
      return 0
example : select.core.parameters = [(31, .scalar .bool), (72, .scalar (.signed .i32))] := rfl
example : select.core.body = some (.ifThenElse (.local 31)
    (.returnValue (some (.local 72))) (.returnValue (some (.value (.signed .i32 0))))) := rfl

-- A source spelling must not turn an ordinary function into a primitive.
namespace Collision
namespace Builtin
def toI32 : Function [I32] I32 :=
  function (id := 99, name := "toI32", arguments := [value := 1], bindings := []) do
    return value
end Builtin
private def call : Function [] I32 :=
  function (id := 3, name := "call", arguments := [], bindings := []) do
    return Builtin.toI32 7
example : call.core.body = some
    (.returnValue (some (.call 99 [.value (.signed .i32 7)]))) := rfl
end Collision

end Lanius.TypedIR.Surface.Tests
