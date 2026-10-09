import Lanius.TypedIR.Surface.Syntax

open Lanius Lanius.TypedIR.Surface
open scoped Lanius.TypedIR.Surface


private inductive Choice where | None | Some (value : I32)
attribute [lanius_type enum 3] Choice

private def select : Function [] I32 :=
  function (id := 1, name := "select", arguments := [], bindings := [4, 9]) do
    let selected : Choice := .Some 7
    return match selected with
      | .Some value => value
      | .None => 0

example : select.core.body = some
    (.letLocal 4 (.enumeration 3) (.enumValue 3 1 [.value (.signed .i32 7)])
      (.returnValue (some (.matchValue (.local 4)
        [(.enumVariant 3 1 [.bind 9], .local 9),
         (.enumVariant 3 0 [], .value (.signed .i32 0))])))) := rfl

-- An identical constructor spelling resolves from the nominal owner, not
-- instance declaration order or a global unqualified name.
private inductive Other where | Some (flag : Bool)
attribute [lanius_type enum 8] Other


private def other : Function [] Other :=
  function (id := 2, name := "other", arguments := [], bindings := []) do
    return (.Some true : Other)

example : other.core.body = some
    (.returnValue (some (.enumValue 8 0 [.value (.boolean true)]))) := rfl

-- Parameters are instantiated from the owner; reserved source constructors
-- retain their native declaration order after name escaping.
private inductive Generic (α : Type) where | «constructor:rec» | Some (value : α)
attribute [lanius_type enum 9] Generic

private def generic : Function [Generic I32] I32 :=
  function (id := 3, name := "generic", arguments := [selected := 1], bindings := [2]) do
    return match selected with
      | .Some value => value
      | .rec => 0

example : generic.core.body = some (.returnValue (some (.matchValue (.local 1)
    [(.enumVariant 9 1 [.bind 2], .local 2),
     (.enumVariant 9 0 [], .value (.signed .i32 0))]))) := rfl
