import verified_compiler.tests.direct_surface_unary
import verified_compiler.tests.direct_surface_fallback

namespace SurfaceUnaryDispatchProof

open Lanius Lanius.Core Lanius.Semantics Lanius.Extraction Lanius.Memory
open SurfaceBooleanProof SurfaceDispatchProof SurfaceUnaryProof IRBuilderNavigationProof
open SurfaceOperationsProof

private def route (operation : Unary) : SurfaceFallbackProof.Route operation.event := {
  target := Extracted.«verified::lean_typed_body».Functions.«surface_unary_output».core.id,
  literalArguments := [],
  bindings := [], nonAtom := by cases operation <;> rfl,
  binary := by cases operation <;> rfl, intrinsic := by cases operation <;> rfl,
  selected := by cases operation <;> rfl, noShadow := by simp }

/-- Classification, both name lookups, and arm selection share the checked
    fallback rule. Final expression induction discharges the helper contract. -/
theorem actualUnaryDispatch (operation : Unary) (context : Context state) (input : Protected context reference)
    (tree : Ready region { state with heap := reference })
    (representation : context.tree = tree.value) (inside : index < region.count)
    (parent : region.events index = operation.event)
    {scope : Scope} (unaryWriter : Writer Context.unaryCall reference tree.value index output scope)
    (nameContext : scope.Matches context)
    (room : context.position + output.length ≤ context.capacity)
    (environment : WriterEnvironment state) :
    ∃ after, RunsExpr extractedProgram state (context.expressionCall index)
      (.signed .i32 (context.position + output.length : Nat)) after ∧
      WriterFrame state after (context.address + context.position) output :=
  SurfaceFallbackProof.actualDispatch (route operation) context input
    (tree.reheap (after := { heap := reference }) rfl) representation inside parent
    unaryWriter nameContext room environment

#print axioms actualUnaryDispatch

end SurfaceUnaryDispatchProof
