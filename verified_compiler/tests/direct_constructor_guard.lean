import SelfCore
import Lanius.Core.Bindings
import Lanius.Semantics.PureProof
import Lanius.Semantics.SourceValue

namespace ConstructorGuardTests

open Lanius Lanius.Core Lanius.Semantics

private def source := Extracted.«verified::lean_typed_body».Functions.«surface_constructor_output».core
private def guard : Expr := match source.body with
  | some (.letLocal _ _ _ (.letLocal _ _ _ (.letLocal _ _ _ (.letLocal _ _ _
      (.sequence _ (.letLocal _ _ _ (.letLocal _ _ _ (.sequence (.whileLoop condition _) _)))))))) => condition
  | _ => .value (.boolean true)
private def emptyConstructor := source_value Extracted.«ir::body_events».Types.«EnumVariant».mk
  [.signed .i32 0, .signed .i32 0, .signed .i32 0]

/-- Exercise the real loop condition at the zero-payload boundary. A weakened
    `<` to `<=` guard must not satisfy this execution contract. -/
theorem stopsEmpty {state : State} (formed : state.CellsWellFormed) :
    RunsExpr extractedProgram
      ((state.bindLocal (source.bindingId 2) emptyConstructor).bindLocal (source.bindingId 5) (.signed .i32 0))
      guard (.boolean false)
      ((state.bindLocal (source.bindingId 2) emptyConstructor).bindLocal (source.bindingId 5) (.signed .i32 0)) := by
  have count : ((state.bindLocal (source.bindingId 2) emptyConstructor).bindLocal (source.bindingId 5) (.signed .i32 0)).local?
      (source.bindingId 2) = some emptyConstructor := by core_local
  have ordinal : ((state.bindLocal (source.bindingId 2) emptyConstructor).bindLocal (source.bindingId 5) (.signed .i32 0)).local?
      (source.bindingId 5) = some (.signed .i32 0) := by core_local
  core_run

#print axioms stopsEmpty

end ConstructorGuardTests
