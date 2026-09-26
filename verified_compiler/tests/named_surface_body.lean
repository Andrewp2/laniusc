import Lanius.TypedIR.NamedSyntax

namespace SurfaceBodyTest

open Lanius.TypedIR.Named
open scoped Lanius.TypedIR.Named

def main : Function [] I32 :=
  function (id := 1, name := "main", arguments := .nil,
    bindings := [25]) do
    let selected : I32 := 7
    return selected

example : main.core.body = some
    (.letLocal 25 (.scalar (.signed .i32))
      (.value (.signed .i32 7))
      (.returnValue (some (.local 25)))) := rfl

end SurfaceBodyTest
