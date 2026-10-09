import Lanius.Execution
import Lanius.TypedIR.Surface.Syntax

open Lanius Lanius.TypedIR.Surface
open scoped Lanius.TypedIR.Surface


private def readBeforeWrite : Function [] I32 :=
  function (id := 0, name := "readBeforeWrite", arguments := [], bindings := [3]) do
    let value : I32
    return value

example : readBeforeWrite.core.body = some
    (.letUninitialized 3 (.scalar (.signed .i32))
      (.returnValue (some (.local 3)))) := rfl

-- Extraction must not silently replace an absent initializer with zero.
example : (match Execution.run 16
    { program := { functions := [readBeforeWrite.pack] }, entrypoint := 0 } {} with
  | .trapped .uninitializedLocal _ => true
  | _ => false) = true := by decide

private def finish : Function [] Unit :=
  function (id := 1, name := "finish", arguments := [], bindings := []) do
    return

example : finish.core.body = some (.returnValue none) := rfl


-- An uninitialized binder shadows the outer variable without losing its ID.
private def shadowed : Function [] I32 :=
  function (id := 2, name := "shadowed", arguments := [], bindings := [4, 9]) do
    let value : Bool := true
    let value : I32
    value := 17
    return value

example : (match Execution.run 32
    { program := { functions := [shadowed.pack] }, entrypoint := 2 } {} with
  | .returned (.signed .i32 17) _ => true
  | _ => false) = true := by decide
