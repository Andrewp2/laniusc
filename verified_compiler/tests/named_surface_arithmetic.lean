import Lanius.TypedIR.NamedSyntax

namespace SurfaceArithmeticTest

open Lanius.TypedIR.Named
open scoped Lanius.TypedIR.Named

def main : Function [] I32 :=
  function (id := 1, name := "main", arguments := .nil,
    bindings := [20]) do
    let start : I32 := 2
    return (start + 3) * 4

example : main.core.body = some
    (.letLocal 20 (.scalar (.signed .i32))
      (.value (.signed .i32 2))
      (.returnValue (some (.binary .multiply
        (.binary .add (.local 20) (.value (.signed .i32 3)))
        (.value (.signed .i32 4)))))) := rfl

end SurfaceArithmeticTest
