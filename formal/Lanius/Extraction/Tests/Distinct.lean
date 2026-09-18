import Lanius.Extraction.SymbolicLocalChecker
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Distinct
open Lanius.Core Lanius.ScopeGraph Lanius.SymbolicCore SymbolicLocalChecker

example : @decide ([3, 1, 2] : List Nat).Nodup
    (Distinct.nodupOn id _) = true := by decide +kernel
example : @decide ([3, 1, 3] : List Nat).Nodup
    (Distinct.nodupOn id _) = false := by decide +kernel
example : @decide ([3, 1, 2] : List Nat).Nodup
    (Distinct.nodupOn (fun _ => 0) _) = true := by decide +kernel
example : @decide ([3, 1, 3] : List Nat).Nodup
    (Distinct.nodupOn (fun _ => 0) _) = false := by decide +kernel

private def binding (node : Nat) (scope : List ScopeId) : LocalBinding := {
  identity := { functionDeclaration := ⟨0, 0⟩, declaration := ⟨0, node⟩, scope, name := "x" }
  coreId := 0
  type := .scalar (.signed .i32)
  kind := .local
}

private def reuse : Function := {
  id := 0, parameters := [], returnType := .unit,
  body := some (.sequence
    (.letLocal 0 (.scalar (.signed .i32)) (.value (.signed .i32 1)) .skip)
    (.letLocal 0 (.scalar (.signed .i32)) (.value (.signed .i32 2)) .skip))
}

private def left := binding 10 [.functionBody 0, .thenBody 4]
private def right := binding 11 [.functionBody 0, .elseBody 4]
private def fixtures : List (Function × List LocalBinding × Bool) := [
  (reuse, [left, right], true),
  -- The source-node key collides, but the full identities are distinct.
  (reuse, [left, binding 10 [.functionBody 0, .elseBody 4]], true),
  -- The address key collides, but the complete scope paths are distinct.
  (reuse, [binding 10 [.functionBody 1, .afterLocal 5],
    binding 11 [.functionBody 2, .afterLocal 5]], true),
  (reuse, [left, left], false),
  (reuse, [left, binding 11 [.functionBody 0, .thenBody 4]], false),
  (reuse, [left], false),
  ({ reuse with body := some (.expression (.local 9)) }, [], false)]

theorem layouts_preserve_acceptance :
    fixtures.all (fun (core, bindings, accepted) =>
      (buildView? core bindings).isSome == accepted) = true := by decide +kernel

run_elab do
  for name in #[``Lanius.Extraction.Distinct.nodupOn,
      ``Lanius.Extraction.Distinct.decide_nodupOn,
      ``buildView?_accepted_iff, ``layouts_preserve_acceptance] do
    for assumption in ← Lean.collectAxioms name do
      unless #[``propext, ``Classical.choice, ``Quot.sound].contains assumption do
        throwError "Uniqueness checking extends kernel trust: {name}: {assumption}"
  Lean.logInfo "Uniqueness checks preserve duplicate rejection, colliding keys, and scope-local ID reuse."

end Lanius.Extraction.Tests.Distinct
