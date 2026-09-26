import Lanius.Compiler.StructureCheck

namespace Lanius.Compiler.EnumShapeCheck

open Lanius

/-- Variant order and every payload type agree with the directly emitted Core
    enum. Core omits variant names, so names remain a catalog obligation. -/
abbrev VariantsLower := ProgramLowering.EnumVariantsLower

structure CheckedVariants (context : SurfaceElaboration.Context)
    (surface : List Surface.EnumVariant)
    (core : List (List Core.Ty)) : Type where
  lowering : VariantsLower context surface core

def checkVariants (context : SurfaceElaboration.Context) :
    (surface : List Surface.EnumVariant) →
    (core : List (List Core.Ty)) →
    Option (CheckedVariants context surface core)
  | [], [] => some { lowering := .nil }
  | surfaceHead :: surfaceTail, coreHead :: coreTail =>
      match StructureCheck.checkFields context surfaceHead.payload coreHead,
          checkVariants context surfaceTail coreTail with
      | some fields, some tail =>
          let lowered : VariantsLower context
              (surfaceHead :: surfaceTail) (coreHead :: coreTail) :=
            .cons fields.fieldTypes fields.lowering fields.grounded
              tail.lowering
          some { lowering := lowered }
      | _, _ => none
  | _, _ => none

/-- Every enum row carries its source enum and its ordered Core payloads.
    Non-enum rows impose no enum-specific obligation. -/
abbrev RowShape (pack : Declarations.SourcePack)
    (context : SurfaceElaboration.Context)
    (row : ProgramLowering.DeclarationLowering pack catalog program) : Prop :=
  ProgramLowering.EnumRowShape pack context row

def checkRow (pack : Declarations.SourcePack)
    (context : SurfaceElaboration.Context)
    (row : ProgramLowering.DeclarationLowering pack catalog program) :
    Option (PLift (RowShape pack context row)) :=
  match hCore : row.core with
  | .enumeration core =>
      match hOccurrence : row.occurrence with
      | .item address =>
          match hSource : pack.item? address with
          | some (.enumeration source) =>
              match checkVariants (context.forModule row.header.moduleId)
                  source.variants core.variants with
              | some checked =>
                  some ⟨by
                    simp only [RowShape, ProgramLowering.EnumRowShape, hCore]
                    exact ⟨address, source, hOccurrence, hSource,
                      checked.lowering⟩⟩
              | none => none
          | _ => none
      | _ => none
  | .structure _ | .constant _ | .function _ =>
      some ⟨by simp [RowShape, ProgramLowering.EnumRowShape, hCore]⟩

def checkRows (pack : Declarations.SourcePack)
    (context : SurfaceElaboration.Context) :
    (rows : List (ProgramLowering.DeclarationLowering pack catalog program)) →
    Option (PLift (∀ row ∈ rows, RowShape pack context row))
  | [] => some ⟨by simp⟩
  | head :: tail =>
      match checkRow pack context head, checkRows pack context tail with
      | some checkedHead, some checkedTail =>
          some ⟨by
            intro row member
            rcases List.mem_cons.mp member with rfl | member
            · exact checkedHead.down
            · exact checkedTail.down row member⟩
      | _, _ => none

end Lanius.Compiler.EnumShapeCheck
