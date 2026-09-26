import Lanius.TypedIR.Named

namespace Extracted.App

open Lanius.TypedIR.Named

inductive Choice where
  | none
  | some (value : I32)

instance : Code Choice where ty := .enumeration 0

private def noneVariant : Variant Choice [] :=
  Variant.named 0 0 "None" rfl

private def someVariant : Variant Choice [I32] :=
  Variant.named 0 1 "Some" rfl

private def selected : Var Choice := Var.named 25 "selected"
private def value : Var I32 := Var.named 42 "value"

def main : Function [] I32 :=
  { id := 1, name := "main", arguments := .nil,
    body := some (.letLocal selected
      (Expr.variant someVariant (.cons (Expr.i32 7) .nil))
      (.returnValue (Expr.matchValue (Expr.local selected)
        [Arm.variant someVariant (.cons value .nil) (Expr.local value),
         Arm.variant noneVariant .nil (Expr.i32 0)]))) }

def program : Lanius.TypedIR.Program :=
  Lanius.TypedIR.require 1
    (assemble
      { enumerations := [{ id := 0, variants := [[], [.scalar (.signed .i32)]] }] }
      [main.pack])
    (by decide)
    (by decide)

example : main.core.body = some
    (.letLocal 25 (.enumeration 0)
      (.enumValue 0 1 [.value (.signed .i32 7)])
      (.returnValue (some (.matchValue (.local 25)
        [(.enumVariant 0 1 [.bind 42], .local 42),
         (.enumVariant 0 0 [], .value (.signed .i32 0))])))) := rfl

end Extracted.App
