import Lanius.Compiler.ConstantCheck
import Lean.Util.SCC

namespace Lanius.Compiler.ConstantGraphCheck

open Lanius
open ProgramLowering

private def lower? (pack : Declarations.SourcePack) (catalog : Declarations.Catalog)
    (program : Core.Program) (environment : Names.Environment)
    (baseContext : SurfaceElaboration.Context)
    (rows : List (DeclarationLowering pack catalog program))
    (entry : { row : DeclarationLowering pack catalog program // row ∈ rows })
    (names : baseContext.names = environment) (target : program.target = baseContext.target)
    (available : List ConstantId) :
    Option { result : ConstantLowering pack catalog program environment baseContext rows //
      result.available = available } :=
  let row := entry.val
  match source : row.occurrence with
  | .item address =>
      match found : pack.item? address with
      | some (.constant name isPublic surfaceType value) =>
          match coreMap : row.core with
          | .constant core =>
              let context := baseContext.forModule row.header.moduleId
              let candidate : ConstantCheck.ConstantCandidate
                  pack catalog program environment baseContext rows := {
                row, rowMember := entry.property, address, name, isPublic, surfaceType, value
                sourceFound := found, source, core, coreMap, context
                contextMatches := ⟨names, rfl, rfl, rfl, rfl, rfl, rfl⟩
                target, noLocals := rfl }
              (ConstantCheck.check candidate available).toOption
          | _ => none
      | _ => none
  | _ => none

private def references (context : SurfaceElaboration.Context)
    (source : Surface.Expr) (tail : List ConstantId := []) : List ConstantId :=
  match source with
  | .path path => match ConstantExprCheck.resolveConstant context path with
      | some entry => entry.val.constant :: tail
      | none => tail
  | .unary _ operand => references context operand tail
  | .binary _ left right => references context left (references context right tail)
  | _ => tail

/-- Graph ordering is advisory: no SCC result is trusted as proof of acyclicity.
    The subsequent checker permits only earlier, verified constant IDs. -/
private def order (pack : Declarations.SourcePack) (baseContext : SurfaceElaboration.Context)
    (rows : List (DeclarationLowering pack catalog program)) :
    List { row : DeclarationLowering pack catalog program // row ∈ rows } := Id.run do
  let mut entries : Std.HashMap ConstantId
      { row : DeclarationLowering pack catalog program // row ∈ rows } := {}
  let mut graph : Std.HashMap ConstantId (List ConstantId) := {}
  let mut vertices := []
  for entry in rows.attach do
    match entry.val.core, entry.val.occurrence with
    | .constant core, .item address =>
        match pack.item? address with
        | some (.constant _ _ _ source) =>
            entries := entries.insert core.id entry
            graph := graph.insert core.id
              (references (baseContext.forModule entry.val.header.moduleId) source)
            vertices := core.id :: vertices
        | _ => pure ()
    | _, _ => pure ()
  return (Lean.SCC.scc vertices.reverse (fun key => graph[key]?.getD [])).flatten.filterMap
    fun key => entries[key]?

structure Checked (pack : Declarations.SourcePack) (catalog : Declarations.Catalog)
    (program : Core.Program) (environment : Names.Environment)
    (baseContext : SurfaceElaboration.Context)
    (rows : List (DeclarationLowering pack catalog program)) where
  lowerings : List (ConstantLowering pack catalog program environment baseContext rows)
  ids : List ConstantId
  idsMatch : ids = lowerings.map (·.core.id)
  initialized : ConstantsInitialized pack catalog program environment baseContext rows lowerings

/-- Each initializer is evaluated once, after its dependencies. The growing
    checked prefix and ID list are shared; no initializer is retried. Coverage
    remains a separate program-level obligation, so omissions fail closed. -/
def check (pack : Declarations.SourcePack) (catalog : Declarations.Catalog)
    (program : Core.Program) (environment : Names.Environment)
    (baseContext : SurfaceElaboration.Context)
    (rows : List (DeclarationLowering pack catalog program))
    (names : baseContext.names = environment) (target : program.target = baseContext.target) :
    Checked pack catalog program environment baseContext rows := Id.run do
  let mut checked : Checked pack catalog program environment baseContext rows :=
    ⟨[], [], rfl, .nil⟩
  for entry in order pack baseContext rows do
    if let some result := lower? pack catalog program environment baseContext rows entry
        names target checked.ids then
      if fresh : result.val.core.id ∉ checked.ids then
        checked := {
          lowerings := result.val :: checked.lowerings
          ids := result.val.core.id :: checked.ids
          idsMatch := congrArg (result.val.core.id :: ·) checked.idsMatch
          initialized := .cons checked.initialized (checked.idsMatch ▸ fresh)
            (result.property.trans checked.idsMatch) }
  return checked

end Lanius.Compiler.ConstantGraphCheck
