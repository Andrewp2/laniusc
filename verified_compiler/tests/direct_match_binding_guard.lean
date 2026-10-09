import SelfCore
import Lanius.Core.Bindings
import Lanius.Semantics.PureProof
import Lanius.Semantics.SourceValue

namespace MatchBindingGuardTests

open Lanius Lanius.Core Lanius.Semantics

private def source := Extracted.«verified::lean_typed_body».Functions.«surface_match_output».core
private def emptyArm := source_value Extracted.«ir::body_events».Types.«MatchArm».mk
  [.signed .i32 0, .signed .i32 0]

/-- Zero bindings must skip the real loop, leaving its final expression node
    unconsumed. Changing the guard from `<` to `<=` must fail this contract. -/
theorem stopsEmpty {state : State} (formed : state.CellsWellFormed) :
    RunsExpr extractedProgram
      ((state.bindLocal (source.bindingId 6) emptyArm).bindLocal (source.bindingId 8) (.signed .i32 0))
      (source.whileLoop 1).1 (.boolean false)
      ((state.bindLocal (source.bindingId 6) emptyArm).bindLocal (source.bindingId 8) (.signed .i32 0)) := by
  have arm : ((state.bindLocal (source.bindingId 6) emptyArm).bindLocal (source.bindingId 8) (.signed .i32 0)).local?
      (source.bindingId 6) = some emptyArm := by core_local
  have counter : ((state.bindLocal (source.bindingId 6) emptyArm).bindLocal (source.bindingId 8) (.signed .i32 0)).local?
      (source.bindingId 8) = some (.signed .i32 0) := by core_local
  core_run

#print axioms stopsEmpty

end MatchBindingGuardTests
