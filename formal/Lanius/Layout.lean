import Lanius.Core

namespace Lanius.Layout

open Lanius
open Lanius.Core

structure ObjectLayout where
  size : Nat
  alignment : Nat
deriving DecidableEq, Repr

def pointerBytes (target : Target) : Nat := target.pointerWidth.bits / 8

def scalarLayout (target : Target) : ScalarTy → ObjectLayout
  | .bool => ⟨1, 1⟩
  | .signed type =>
      let bytes := type.bits target / 8
      ⟨bytes, bytes⟩
  | .unsigned type =>
      let bytes := type.bits target / 8
      ⟨bytes, bytes⟩
  | .f32 => ⟨4, 4⟩
  | .f64 => ⟨8, 8⟩
  | .char => ⟨4, 4⟩
  | .string =>
      let bytes := pointerBytes target
      ⟨2 * bytes, bytes⟩
  | .rawPtr =>
      let bytes := pointerBytes target
      ⟨bytes, bytes⟩

def alignUp (offset alignment : Nat) : Nat :=
  ((offset + alignment - 1) / alignment) * alignment

def aggregateAlignment (fields : List ObjectLayout) : Nat :=
  fields.foldl (fun alignment field => max alignment field.alignment) 1

def fieldOffsetsFrom : Nat → List ObjectLayout → List Nat
  | _, [] => []
  | cursor, field :: tail =>
      let offset := alignUp cursor field.alignment
      offset :: fieldOffsetsFrom (offset + field.size) tail

def aggregateEndFrom : Nat → List ObjectLayout → Nat
  | cursor, [] => cursor
  | cursor, field :: tail =>
      let offset := alignUp cursor field.alignment
      aggregateEndFrom (offset + field.size) tail

def aggregateLayout (fields : List ObjectLayout) : ObjectLayout :=
  let alignment := aggregateAlignment fields
  ⟨alignUp (aggregateEndFrom 0 fields) alignment, alignment⟩

def maxPayloadSize (variants : List ObjectLayout) : Nat :=
  variants.foldl (fun size variant => max size variant.size) 0

def maxPayloadAlignment (variants : List ObjectLayout) : Nat :=
  variants.foldl (fun alignment variant => max alignment variant.alignment) 1

/-- Enums use a 32-bit discriminant followed by one aligned payload region.
    The payload region is large enough for the largest variant. -/
def taggedUnionLayout (variants : List ObjectLayout) : ObjectLayout :=
  let payloadAlignment := maxPayloadAlignment variants
  let payloadOffset := alignUp 4 payloadAlignment
  let alignment := max 4 payloadAlignment
  ⟨alignUp (payloadOffset + maxPayloadSize variants) alignment, alignment⟩

def taggedUnionPayloadOffset (variants : List ObjectLayout) : Nat :=
  alignUp 4 (maxPayloadAlignment variants)

mutual
  inductive TyHasLayout (program : Program) (target : Target) :
      Ty → ObjectLayout → Prop where
    | unit : TyHasLayout program target .unit ⟨0, 1⟩
    | scalar : TyHasLayout program target (.scalar type) (scalarLayout target type)
    | array
        (element : TyHasLayout program target elementType elementLayout) :
        TyHasLayout program target (.array elementType length) {
          size := elementLayout.size * length
          alignment := elementLayout.alignment
        }
    | slice :
        TyHasLayout program target (.slice elementType) {
          size := 2 * pointerBytes target
          alignment := pointerBytes target
        }
    | reference :
        TyHasLayout program target (.reference referentType) {
          size := pointerBytes target
          alignment := pointerBytes target
        }
    | structure
        (declaration : program.structure? typeId = some structureDecl)
        (fields : TypesHaveLayouts program target structureDecl.fields fieldLayouts) :
        TyHasLayout program target (.structure typeId) (aggregateLayout fieldLayouts)
    | enumeration
        (declaration : program.enumeration? typeId = some enumeration)
        (variants : VariantPayloadsHaveLayouts program target enumeration.variants
          variantLayouts) :
        TyHasLayout program target (.enumeration typeId)
          (taggedUnionLayout variantLayouts)

  inductive TypesHaveLayouts (program : Program) (target : Target) :
      List Ty → List ObjectLayout → Prop where
    | nil : TypesHaveLayouts program target [] []
    | cons
        (head : TyHasLayout program target sourceHead layoutHead)
        (tail : TypesHaveLayouts program target sourceTail layoutTail) :
        TypesHaveLayouts program target (sourceHead :: sourceTail)
          (layoutHead :: layoutTail)

  inductive VariantPayloadsHaveLayouts (program : Program) (target : Target) :
      List (List Ty) → List ObjectLayout → Prop where
    | nil : VariantPayloadsHaveLayouts program target [] []
    | cons
        (payload : TypesHaveLayouts program target sourceHead fieldLayouts)
        (tail : VariantPayloadsHaveLayouts program target sourceTail layoutTail) :
        VariantPayloadsHaveLayouts program target (sourceHead :: sourceTail)
          (aggregateLayout fieldLayouts :: layoutTail)
end

def StructFieldOffsets
    (program : Program) (target : Target) (typeId : TypeId)
    (offsets : List Nat) : Prop :=
  ∃ declaration layouts,
    program.structure? typeId = some declaration ∧
      TypesHaveLayouts program target declaration.fields layouts ∧
      offsets = fieldOffsetsFrom 0 layouts

def EnumPayloadOffset
    (program : Program) (target : Target) (typeId : TypeId)
    (offset : Nat) : Prop :=
  ∃ declaration layouts,
    program.enumeration? typeId = some declaration ∧
      VariantPayloadsHaveLayouts program target declaration.variants layouts ∧
      offset = taggedUnionPayloadOffset layouts

def ProgramHasLayouts (program : Program) : Prop :=
  (∀ declaration, declaration ∈ program.structures →
    ∃ layout, TyHasLayout program program.target (.structure declaration.id) layout) ∧
  (∀ declaration, declaration ∈ program.enumerations →
    ∃ layout, TyHasLayout program program.target (.enumeration declaration.id) layout) ∧
  (∀ constant, constant ∈ program.constants →
    ∃ layout, TyHasLayout program program.target constant.type layout) ∧
  ∀ function, function ∈ program.functions →
    (∀ parameter, parameter ∈ function.parameters →
      ∃ layout, TyHasLayout program program.target parameter.2 layout) ∧
    ∃ layout, TyHasLayout program program.target function.returnType layout

end Lanius.Layout
