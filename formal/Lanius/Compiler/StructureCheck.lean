import Lanius.Compiler.ConstantCheck

namespace Lanius.Compiler.StructureCheck

open Lanius
open Lanius.Compiler.ProgramLowering

/- The recursive checker returns the existing `TypesGround` evidence and the
   corresponding Core list agreement. -/
structure CheckedFields (context : SurfaceElaboration.Context)
    (surfaceFields : List Surface.TypeExpr) (coreFields : List Core.Ty) where
  fieldTypes : List Static.GroundTy
  lowering : SurfaceElaboration.TypesGround context surfaceFields fieldTypes
  grounded : Static.GroundTy.listToCore context.monomorphization fieldTypes =
    some coreFields

def checkFields (context : SurfaceElaboration.Context) :
    (surfaceFields : List Surface.TypeExpr) →
    (coreFields : List Core.Ty) →
    Option (CheckedFields context surfaceFields coreFields)
  | [], [] => some {
      fieldTypes := []
      lowering := .nil
      grounded := rfl }
  | surfaceHead :: surfaceTail, coreHead :: coreTail =>
      match TypeLoweringCheck.check context surfaceHead coreHead with
      | none => none
      | some head =>
          match checkFields context surfaceTail coreTail with
          | none => none
          | some tail =>
              some {
                fieldTypes := head.groundType :: tail.fieldTypes
                lowering := .cons head.typed.down tail.lowering
                grounded := by
                  simp [Static.GroundTy.listToCore, head.grounded, tail.grounded] }
  | _, _ => none

/- Everything outside field lowering is supplied by the declaration/catalog
   checker.  Keeping it in the candidate makes this checker compositional and
   lets its result be the project's existing `StructureLowering` witness. -/
structure StructureCandidate
    (pack : Declarations.SourcePack) (catalog : Declarations.Catalog)
    (program : Core.Program) (environment : Names.Environment)
    (baseContext : SurfaceElaboration.Context)
    (rows : List (DeclarationLowering pack catalog program)) where
  row : DeclarationLowering pack catalog program
  rowMember : row ∈ rows
  address : Declarations.ItemAddress
  declaration : Surface.StructDecl
  sourceFound : pack.item? address = some (.structure declaration)
  source : row.occurrence = .item address
  core : Core.StructDecl
  coreMap : row.core = .structure core
  context : SurfaceElaboration.Context
  contextMatches : ContextMatches context baseContext environment row.header.moduleId
  noLocals : context.locals = []

inductive Failure where
  | sourceMismatch
  | noLocals
  | unsupportedFields
deriving DecidableEq, Repr

def check
    (candidate : StructureCandidate pack catalog program environment baseContext rows) :
    Except Failure
      (StructureLowering pack catalog program environment baseContext rows) :=
  if _source : candidate.row.header.kind = .structureType then
    if locals : candidate.context.locals = [] then
      match checkFields candidate.context
          (candidate.declaration.fields.map (fun field => field.type)) candidate.core.fields with
      | none => .error .unsupportedFields
      | some fields =>
          .ok {
            row := candidate.row
            rowMember := candidate.rowMember
            address := candidate.address
            declaration := candidate.declaration
            sourceFound := candidate.sourceFound
            source := candidate.source
            core := candidate.core
            coreMap := candidate.coreMap
            context := candidate.context
            fieldTypes := fields.fieldTypes
            fieldsLowering := fields.lowering
            fieldsGrounded := fields.grounded
            contextMatches := candidate.contextMatches
            noLocals := locals }
    else .error .noLocals
  else .error .sourceMismatch

end Lanius.Compiler.StructureCheck
