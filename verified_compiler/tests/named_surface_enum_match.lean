import Lanius.TypedIR.NamedSyntax

namespace SurfaceEnumTest

open Lanius.TypedIR.Named
open scoped Lanius.TypedIR.Named

inductive Choice where
  | None
  | Some (value : I32)

instance : Code Choice where ty := .enumeration 0

private def noneVariant : Variant Choice [] :=
  Variant.named 0 0 "None" rfl
private def someVariant : Variant Choice [I32] :=
  Variant.named 0 1 "Some" rfl
def main : Function [] I32 :=
  function (id := 1, name := "main", arguments := .nil,
    bindings := [25, 42]) do
    let selected : Choice := someVariant 7
    return match selected with
      | someVariant value => value
      | noneVariant => 0

example : main.core.body = some
    (.letLocal 25 (.enumeration 0)
      (.enumValue 0 1 [.value (.signed .i32 7)])
      (.returnValue (some (.matchValue (.local 25)
        [(.enumVariant 0 1 [.bind 42], .local 42),
         (.enumVariant 0 0 [], .value (.signed .i32 0))])))) := rfl

end SurfaceEnumTest
