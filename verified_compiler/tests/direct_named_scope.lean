import Lanius.TypedIR.Surface.Syntax

open Lanius Lanius.TypedIR.Surface
open scoped Lanius.TypedIR.Surface


-- A repeated spelling must retain distinct resolved identities. In a let
-- initializer it denotes the outer binding, including for a different type.
private def shadowed : Function [] I32 :=
  function (id := 0, name := "shadowed", arguments := [], bindings := [4, 9]) do
    let value : I32 := 7
    let value : Bool := value == 7
    if value then
      return 1
    else
      return 0

example : shadowed.core.body = some
    (.letLocal 4 (.scalar (.signed .i32)) (.value (.signed .i32 7))
      (.letLocal 9 (.scalar .bool)
        (.binary .equal (.local 4) (.value (.signed .i32 7)))
        (.ifThenElse (.local 9)
          (.returnValue (some (.value (.signed .i32 1))))
          (.returnValue (some (.value (.signed .i32 0))))))) := rfl

-- A shared body must retain variables supplied by the surrounding Lean
-- definition, not just closed binders emitted as local `let` declarations.
private def identity (argument : Var I32) : Function [I32] I32 :=
  function (id := 1, name := "identity", arguments := [argument := argument.id],
      bindings := []) do
    return argument

example (argument : Var I32) :
    (identity argument).core.body = some
      (.returnValue (some (.local argument.id))) := rfl

-- Internal context sharing must not capture a source parameter named `scope`,
-- either at function entry or after extending the local scope.
private def scopeNamedArgument (scope : Var I32) : Function [I32] I32 :=
  function (id := 8, name := "scopeNamedArgument", arguments := [scope := scope.id],
      bindings := [101]) do
    let value : I32 := 7
    return scope + value

example (scope : Var I32) :
    (scopeNamedArgument scope).core.body = some
      (.letLocal 101 (.scalar (.signed .i32)) (.value (.signed .i32 7))
        (.returnValue (some (.binary .add (.local scope.id) (.local 101))))) := rfl

private def genericIdentity (α : Type) [Code α] (argument : Var α) :
    Function [α] α :=
  function (id := 2, name := "genericIdentity", arguments := [argument := argument.id],
      bindings := []) do
    return argument

example (α : Type) [Code α] (argument : Var α) :
    (genericIdentity α argument).core.body = some
      (.returnValue (some (.local argument.id))) := rfl

-- Closure construction must expand dependent local lets without losing
-- genuine type and value parameters from the surrounding definition.
private def capturedLet (α : Type) [Code α] (input : Var α) : Function [α] α :=
  let Alias := α
  let captured : Var Alias := input
  function (id := 5, name := "capturedLet", arguments := [captured := captured.id],
      bindings := []) do
    return captured

example (α : Type) [Code α] (input : Var α) :
    (capturedLet α input).core.body = some
      (.returnValue (some (.local input.id))) := rfl

-- Body closure must retain a constant supplied by the surrounding Lean
-- declaration, including its use for the unused-variable linter.
#guard_msgs in
private def capturedValue (value : Constant I32) : Function [] I32 :=
  function (id := 6, name := "capturedValue", arguments := [], bindings := []) do
    return value

example (value : Constant I32) : (capturedValue value).core.body =
    some (.returnValue (some (.constant value.id))) := rfl

-- A signature variable is reused by reads and writes. A shadowing initializer
-- still resolves that outer variable, not the fresh local with another type.
private def mutateAndShadow (input : Var I32) : Function [I32] I32 :=
  function (id := 3, name := "mutateAndShadow", arguments := [input := input.id],
      bindings := [12]) do
    input += input
    let input : Bool := input == 7
    if input then
      return 1
    else
      return 0

example (input : Var I32) : (mutateAndShadow input).core.body = some
    (.sequence (.expression (.assign .add (.local input.id) (.local input.id)))
      (.letLocal 12 (.scalar .bool)
        (.binary .equal (.local input.id) (.value (.signed .i32 7)))
        (.ifThenElse (.local 12)
          (.returnValue (some (.value (.signed .i32 1))))
          (.returnValue (some (.value (.signed .i32 0))))))) := rfl

-- A computed signature and parameter ID remain supported, not just literals.
private def computedSignature (input : Var I32) : Function (id [I32]) I32 :=
  function (id := 4, name := "computedSignature", arguments := [input := id input.id],
      bindings := []) do
    return input

example (input : Var I32) : (computedSignature input).core.body = some
    (.returnValue (some (.local input.id))) := rfl

def main : IO Unit := do
  match (identity (Var.named 17 "input")).core.body with
  | some (.returnValue (some (.local 17))) => pure ()
  | _ => throw (IO.userError "function body lost its captured argument")

-- Nested source blocks must not extend their locals into the continuation.
private def nestedBlock : Function [] I32 :=
  function (id := 7, name := "nestedBlock", arguments := [], bindings := [1, 2, 3]) do
    let result : I32 := 0
    do
      let value : I32 := 7
      result := value
      skip
    let value : Bool := true
    if value then
      return result
    else
      return 0

example : nestedBlock.core.body = some
    (.letLocal 1 (.scalar (.signed .i32)) (.value (.signed .i32 0))
      (.sequence
        (.letLocal 2 (.scalar (.signed .i32)) (.value (.signed .i32 7))
          (.sequence (.expression (.assign .set (.local 1) (.local 2))) .skip))
        (.letLocal 3 (.scalar .bool) (.value (.boolean true))
          (.ifThenElse (.local 3)
            (.returnValue (some (.local 1)))
            (.returnValue (some (.value (.signed .i32 0)))))))) := rfl
