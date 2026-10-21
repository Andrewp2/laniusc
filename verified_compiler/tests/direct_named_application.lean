import Lanius.TypedIR.Surface.Syntax

open Lanius Lanius.TypedIR.Surface
open scoped Lanius.TypedIR.Surface


mutual functions
private def nested : Function [] I32 :=
  function (id := 0, name := "nested", arguments := [], bindings := []) do
    return increment (seed ())
private def increment : Function [I32] I32 :=
  function (id := 7, name := "increment", arguments := [value := 1], bindings := []) do
    return value + 1
private def seed : Function [] I32 :=
  function (id := 3, name := "seed", arguments := [], bindings := []) do
    return 6
end

example : nested.core.body = some
    (.returnValue (some (.call 7 [.call 3 []]))) := rfl

-- Captured declarations work without a separate reference value.
private def indirect (callee : Function [I32] I32) : Function [] I32 :=
  function (id := 0, name := "indirect", arguments := [], bindings := []) do
    return callee 9

example (callee : Function [I32] I32) : (indirect callee).core.body =
    some (.returnValue (some (.call callee.core.id [.value (.signed .i32 9)]))) := rfl

-- Completed declarations remain callable after leaving the mutual scope.
private def later : Function [] I32 :=
  function (id := 10, name := "later", arguments := [], bindings := []) do
    return increment 8
example : later.core.body = some
    (.returnValue (some (.call 7 [.value (.signed .i32 8)]))) := rfl

-- Function scope must not hide ordinary captured Lean locals.
mutual functions
private def captured (value : Var I32) : Function [] I32 :=
  function (id := 13, name := "captured", arguments := [], bindings := []) do
    return value
end
example (value : Var I32) : (captured value).core.body =
    some (.returnValue (some (.local value.id))) := rfl

-- The command does not reserve the identifier used by the link notation.
private def functions : Nat := 7
example : functions = 7 := rfl

-- The header ID must come from the actual external-function constructor,
-- not from an arbitrary function with similarly named arguments.
private def changedId (id : Nat) (name : String) (arguments : Vars [])
    (behavior : Core.ExternalBehavior) : Function [] I32 :=
  Function.external (id + 1) name arguments behavior
/-- error: expected Function.external -/
#guard_msgs in
mutual functions
private def mislabeled : Function [] I32 :=
  changedId (id := 15) (name := "mislabeled") (arguments := .nil) (behavior := .panic)
end

-- Polymorphic targets use their Application dictionary; simplifying concrete
-- constructor applications must not narrow the rest of the DSL.
private def abstractCall {source : Type} [Application source I32]
    (callee : source) : Function [] I32 :=
  function (id := 0, name := "abstractCall", arguments := [], bindings := []) do
    return callee ()

example {source : Type} [Application source I32] (callee : source) :
    (abstractCall callee).core.body =
      some (.returnValue (some (Expr.apply callee .nil).core)) := rfl
