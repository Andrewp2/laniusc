import Lanius.TypedIR.Surface.Link
import Lanius.Execution

namespace Lanius.TypedIR.Surface.FunctionTests
open Lanius
open scoped Surface

-- Native Lean definitions are closed data even when source calls are recursive.
mutual functions
private def left : Function [I32] I32 :=
  function (id := 7, name := "left", arguments := [value := 1], bindings := []) do
    return right value
/-- Public entry calling a private forward declaration. -/
def start : Function [] I32 :=
  function (id := 8, name := "start", arguments := [], bindings := []) do
    return left 3
private def right : Function [I32] I32 :=
  function (id := 9, name := "right", arguments := [value := 1], bindings := []) do
    if value == 0 then
      return 7
    else
      return left (value - 1)
end

def program : Core.Program :=
  link (types := [], constants := [], functions := [left.pack, start.pack, right.pack])
example : start.core.body = some
    (.returnValue (some (.call 7 [.value (.signed .i32 3)]))) := rfl
example : (match Execution.run 256 { program, entrypoint := 8 } {} with
  | .returned (.signed .i32 7) _ => true | _ => false) = true := by decide

-- Generic definitions still use normal elaboration and keep captured labels.
section
variable (α : Type) [Code α]
mutual functions
def identity : Function [α] α :=
  function (id := 10, name := "identity", arguments := [value := 1], bindings := []) do
    return value
end
example : (identity α).core.parameters = [(1, Code.ty α)] := rfl
end

-- Attributes are handled by ordinary Lean admission, not silently dropped.
mutual functions
@[inline] def attributed : Function [] I32 :=
  function (id := 11, name := "attributed", arguments := [], bindings := []) do
    return 7
end
example : attributed.core.body = some
    (.returnValue (some (.value (.signed .i32 7)))) := rfl

-- Handwritten metadata may depend on another Lean definition. Such a block
-- needs ordinary closure/dependency processing rather than closed-data admission.
mutual functions
private def dependent : Function [I32] I32 :=
  Function.external (id := 20) (name := "dependent")
    (arguments := .cons (Var.named parameterId.core.id "value") .nil) (behavior := .panic)
private def parameterId : Function [] I32 :=
  function (id := 21, name := "parameterId", arguments := [], bindings := []) do
    return 0
end
example : dependent.core.parameters = [(21, .scalar (.signed .i32))] := rfl

end Lanius.TypedIR.Surface.FunctionTests
