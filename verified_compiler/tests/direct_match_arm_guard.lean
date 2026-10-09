import SelfCore
import Lanius.Core.Bindings
import Lanius.Semantics.PureProof
import Lanius.Semantics.SourceValue

namespace MatchArmGuardTests

open Lanius Lanius.Core Lanius.Semantics

private def source := Extracted.«ir::body_tree».Functions.«arm_shape».core
private def guard : Expr := match source.body with
  | some (.sequence (.ifThenElse condition _ _) _) => condition
  | _ => .value (.boolean false)
private def wildcardBinding := source_value Extracted.«ir::body_events».Types.«MatchArm».mk
  [.signed .i32 (-1), .signed .i32 1]

/-- The actual classifier rejects bindings on a wildcard arm. An inverted
    count comparison must not satisfy this guard execution contract. -/
theorem rejectsWildcard {state : State} (formed : state.CellsWellFormed) :
    RunsExpr extractedProgram (state.bindLocal (source.argumentId 0) wildcardBinding) guard
      (.boolean true) (state.bindLocal (source.argumentId 0) wildcardBinding) := by
  have arm : (state.bindLocal (source.argumentId 0) wildcardBinding).local? (source.argumentId 0) =
      some wildcardBinding := by core_local
  core_run

#print axioms rejectsWildcard

end MatchArmGuardTests
