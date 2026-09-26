import Lanius.TypedIR.Checked

namespace Readable

open Lanius.TypedIR

abbrev Choice : Ty := .enumeration 0

def none : Variant 0 [] := ⟨0, "None"⟩
def some : Variant 0 [I32] := ⟨1, "Some"⟩
def selected : Var Choice := ⟨25, "selected"⟩
def value : Var I32 := ⟨42, "value"⟩

def main : Function [] I32 :=
  { id := 1, name := "main", arguments := .nil,
    body := Option.some (.letLocal selected
      (Expr.variant some (.cons (Expr.i32 7) .nil))
      (.returnValue (Expr.matchValue (Expr.local selected)
        [Arm.variant some (.cons value .nil) (Expr.local value),
         Arm.variant none .nil (Expr.i32 0)]))) }

def program : Program :=
  link 1 { enumerations := [{ id := 0, variants := [[], [I32]] }] }
    [main.pack]
    (by decide)
    (by decide)

end Readable

example : Readable.program.entry = 1 := rfl
example : Lanius.Typing.ProgramWellTyped Readable.program.core :=
  Readable.program.wellTyped
