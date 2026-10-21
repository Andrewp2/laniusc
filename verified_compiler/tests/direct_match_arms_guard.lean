import SelfCore
import Lanius.Core.Bindings
import Lanius.Semantics.PureProof
import Lanius.Semantics.SourceValue

namespace MatchArmsGuardTests

open Lanius Lanius.Core Lanius.Semantics

private def source := Extracted.«verified::lean_typed_body».Functions.«surface_match_output».core
private def header (count : Nat) := source_value Extracted.«ir::body_events».Types.«MatchHeader».mk
  [source_value Extracted.«ir::type_ref».Types.«TypeRef».«I32» [], .signed .i32 0, .signed .i32 count]

/-- At the header's count, the actual outer guard is false. This check uses
    fresh admitted code, not the arm-loop proof model or old writer artifacts. -/
theorem stopsFinished (count : Nat) {state : State} (formed : state.CellsWellFormed) :
    let before := (state.bindLocal (source.bindingId 2) (header count)).bindLocal
      (source.bindingId 5) (.signed .i32 count)
    RunsExpr extractedProgram before (source.whileLoop 0).1 (.boolean false) before := by
  intro before
  have headerFound : before.local? (source.bindingId 2) = some (header count) := by core_local
  have ordinalFound : before.local? (source.bindingId 5) = some (.signed .i32 count) := by core_local
  core_run

#print axioms stopsFinished

end MatchArmsGuardTests
