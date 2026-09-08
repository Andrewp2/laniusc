import Lanius.Semantics.Restriction

open Lanius Lanius.Core Lanius.Semantics

private def allowed (id : FunctionId) : Bool := id < 2
private def function (id : FunctionId) (body : Stmt) : Core.Function :=
  { id, parameters := [], returnType := .unit, body := some body }
private def program : Program :=
  { functions := [function 0 (.expression (.call 1 [])), function 1 .skip,
      function 2 (.expression (.call 999 []))] }

-- An unreachable malformed dependency does not invalidate the retained code.
example : Dependencies.closed program allowed = true := by decide
example : (Restriction.check? program allowed).isSome = true := by decide
example : (Dependencies.restrict program allowed).function? 2 = none := by decide

-- Direct and nested escapes are rejected, including calls in mutable places.
example : Dependencies.expression allowed (.call 2 []) = false := by decide
example : Dependencies.expression allowed (.call 0 [.call 2 []]) = false := by decide
example : Dependencies.place allowed (.index (.local 0) (.call 2 [])) = false := by decide
example : Dependencies.statement allowed
    (.forRange 0 (.value (.signed .i32 0)) (some (.call 2 [])) false .skip) = false := by decide
example : Dependencies.statement allowed (.returnValue (some (.call 2 []))) = false := by decide
example : Dependencies.closed
    { functions := [function 0 (.expression (.call 2 [])), function 2 .skip] } allowed = false := by decide

-- Exercise the semantic theorem, not just its Boolean precondition.
example {before after : State}
    (executed : Executes program before (.expression (.call 0 [])) .next after) :
    Executes (Dependencies.restrict program allowed) before (.expression (.call 0 [])) .next after :=
  Restriction.executes (Restriction.ofClosed program allowed (by decide)) executed (by decide)

#print axioms Lanius.Semantics.Restriction.evaluates
#print axioms Lanius.Semantics.Restriction.executes
