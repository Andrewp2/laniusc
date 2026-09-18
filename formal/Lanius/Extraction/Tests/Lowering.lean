import Lanius.Extraction.CoreSynthesis.Provenance
import Lanius.Extraction.KernelReduction
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Lowering
open Lanius CoreSynthesis.Program

private def i32 : Surface.TypeExpr := .path [.mk "i32" []]
private def unit : CoreSynthesis.Program.Unit := {
  moduleId := 0
  modulePath := ["fixture"]
  surface := { items := [
    .module { segments := [.mk "fixture" []] },
    .function {
      name := "value", returnType := some i32
      body := [.returnValue (some (.literal (.integer "7")))] }] } }

private def returns (unit : CoreSynthesis.Program.Unit) (expected : Int) : Bool :=
  match lowerUnits? [unit] with
  | none => false
  | some lowered =>
    match Semantics.evalExpr 200 lowered.core {} (.call 0 []) with
    | .done (.signed .i32 value) _ => value == expected
    | _ => false

private def number (text : String) : Surface.Expr := .literal (.integer text)
private def read (name : String) : Surface.Expr := .path { segments := [.mk name []] }
private def constant : CoreSynthesis.Program.Unit := { unit with surface := { items := [
  .constant "seven" false i32 (number "7"),
  .function {
    name := "value", returnType := some i32
    body := [.returnValue (some (read "seven"))] }] } }
private def fields : CoreSynthesis.Program.Unit := { unit with surface := { items := [
  .structure { name := "B", fields := [{ name := "value", type := .path [.mk "bool" []] }] },
  .structure { name := "A", fields := [{ name := "value", type := i32 }] },
  .function {
    name := "field", returnType := some i32
    body := [
      .letLocal "a" none (some (.structValue { segments := [.mk "A" []] } [("value", number "7")])),
      .expression (.assign .add (.member (read "a") "value") (number "4")),
      .returnValue (some (.member (read "a") "value"))] }] } }
private def nested : CoreSynthesis.Program.Unit := { unit with surface := { items := [
  .constant "x" false i32 (number "999"),
  .function {
    name := "nested", returnType := some i32
    body := [
      .letLocal "x" none (some (number "7")),
      .block [.letLocal "x" none (some (number "99"))],
      .ifThenElse (.literal (.boolean true))
        [.letLocal "temporary" none (some (number "12"))] [],
      .letLocal "y" (some i32) (some (number "2")),
      .whileLoop (.binary .less (read "x") (number "9")) [
        .expression (.assign .add (read "x") (number "1")),
        .ifThenElse (.binary .equal (read "x") (number "8")) [.continueLoop] [],
        .breakLoop],
      .returnValue (some (.binary .add (read "x") (read "y")))] }] } }

-- Check results, lexical shadowing, branch-local allocation, and loop control,
-- without making a particular Core tree shape part of the contract.
private theorem output :
    returns unit 7 = true ∧ returns constant 7 = true ∧
      returns fields 11 = true ∧ returns nested 11 = true := by
  refine ⟨?_, ?_, ?_, ?_⟩ <;> kernel_rfl

private theorem rejected :
    (lowerUnits? [unit, unit]).isNone = true ∧
    (lowerUnits? [{ unit with surface := { items := [
      .importPath { segments := [.mk "missing" []] }] } }]).isNone = true ∧
    (lowerUnits? [{ unit with surface := { items := [
      .function {
        name := "bad", returnType := some i32
        body := [.returnValue (some (.literal (.boolean true)))] }] } }]).isNone = true := by
  refine ⟨?_, ?_, ?_⟩ <;> kernel_rfl

private def pair := [unit, { unit with moduleId := 1, modulePath := ["other"] }]
set_option Elab.async false
private def prepared : Prepared := (prepareUnits? pair).get (by kernel_rfl)
private def function (id : Nat) : Core.Function := {
  id, parameters := [], returnType := .scalar (.signed .i32)
  body := some (.sequence (.returnValue (some (.value (.signed .i32 7)))) .skip) }

-- Two modules share a context but keep distinct function IDs. The final
-- equation must reach the original whole-program lowering operation.
private theorem joined :
    (lowerFunctions prepared.context prepared.allocations).toOption.map (·.core) =
      some [function 0, function 1] := by
  have first : (lowerFunctions prepared.context [prepared.allocations[0]'(by decide)]).toOption.map
      (·.core) = some [function 0] := by kernel_rfl
  have second : (lowerFunctions prepared.context [prepared.allocations[1]'(by decide)]).toOption.map
      (·.core) = some [function 1] := by kernel_rfl
  exact lowerFunctions_cons first (lowerFunctions_cons second
    (show (lowerFunctions prepared.context []).toOption.map (·.core) = some [] from rfl))

private theorem composed : (lowerUnits? pair).map (·.core) = some {
    target := .x86_64, functions := [function 0, function 1] } := by
  refine (lowerUnits_of_functions (show prepareUnits? pair = some prepared from (Option.some_get _).symm)
    joined).trans ?_
  kernel_rfl

-- The public source-facing synthesis consumes the same retained stage result;
-- this audit includes the existing stronger source-provenance relationship.
run_elab do
  for name in #[``output, ``rejected, ``composed, ``synthesize_of_lowered, ``sourceBound_of_lowered,
      ``SourceBound.metadata, ``lowerUnits?, ``lowerFunctions_cons,
      ``lowerFunctions_derivation, ``lowerFunctions_eq, ``lowerPrepared_of_functions,
      ``lowerUnits_of_functions] do
    for assumption in ← Lean.collectAxioms name do
      unless #[``propext, ``Classical.choice, ``Quot.sound].contains assumption do
        throwError "lowering stage {name} uses unexpected assumption {assumption}"

end Lanius.Extraction.Tests.Lowering
