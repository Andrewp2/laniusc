import Lanius.TypedIR.Surface.FunctionTests

namespace Lanius.TypedIR.Surface.FunctionImportTests
open Lanius FunctionTests
open scoped Surface

run_cmd do
  unless (← Lean.findDocString? (← Lean.getEnv) ``FunctionTests.start).isSome do
    throwError "public source-function documentation was lost"

-- Imported code remains reducible and executable, including private callees.
example : program.functions.map (·.id) = [7, 8, 9] := rfl
example : (match Execution.run 256 { program, entrypoint := 8 } {} with
  | .returned (.signed .i32 7) _ => true | _ => false) = true := by decide
#eval (show IO Unit from match Execution.run 256 { program, entrypoint := 8 } {} with
  | .returned (.signed .i32 7) _ => pure ()
  | _ => throw (IO.userError "imported recursive source calls changed"))

mutual functions
def caller : Function [] I32 :=
  function (id := 12, name := "caller", arguments := [], bindings := []) do
    return start ()
end
example : caller.core.body = some
    (.returnValue (some (.call 8 []))) := rfl

end Lanius.TypedIR.Surface.FunctionImportTests
