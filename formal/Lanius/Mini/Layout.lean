module

public import Lanius.Mini.SourceCore
public import Lanius.Mini.Compiler.P.Lists_empty

@[expose] public section

/-! # Native layout and references (F5, trusted)

The layout definitions a reference's representation reaches
(`SrcType.HoldsAt.ref`, `RefHeld`): how a value's words lie in memory
(`SrcType.words`, SEMANTIC_DECISIONS "References: the memory model" point 4),
where a field or element of it starts (`SrcType.sub`), the places references
name (`Addressed`) and what a reference's word is (`RefTo`, `RefHeld`, point
5). Moved here from `Refs/Model.lean` in stage 1 (S2), so that `HoldsAt` can
use them; the rest of the model (slots, homes, code) stays there.
-/

namespace Lanius.Mini

open Lanius.Core (Value ValueProjection)

/-! ## Accesses -/

/-- How one slot of a value is read and written in memory: one byte, or a
4- or 8-byte little-endian word. -/
inductive Access where
  | byte
  | word (width : MemWidth)

def Access.bytes : Access → Nat
  | .byte => 1
  | .word width => width.bytes

/-- A narrow access: an element of this width is packed in an array. -/
def Access.narrow : Access → Bool
  | .byte => true
  | .word .m32 => true
  | .word .m64 => false

/-- How an element of an array of this type is packed: an `i32` at 4 bytes
and a `u8` at 1 (`narrow`, the packed arrays); the others are not packed and
take whole native words. A scalar outside a packed array is accessed at its
native width instead (`widthOf`, `SrcType.slotAt`). -/
def SrcType.accessKind : SrcType → Access
  | .i32 => .word .m32
  | .bool => .word .m64
  | .uint .uint8 => .byte
  | .uint .uint32 => .word .m64
  | .uint .uint64 => .word .m64
  | .uint .usize => .word .m64
  | .uint .uint16 => .word .m64
  | .struct _ _ => .word .m64
  | .enum _ _ => .word .m64
  | .ptr => .word .m64
  | .slice _ => .word .m64
  | .array _ _ => .word .m64
  | .unit => .word .m64
  | .isize => .word .m64
  | .char => .word .m64
  | .float _ => .word .m64
  | .sint _ => .word .m64
  | .view _ => .word .m64
  | .str => .word .m64
  | .ref _ => .word .m64

/-- A packed type: an array of `i32` or `u8`, its elements 4 or 1 bytes
apart, ascending (the slice layout, SEMANTIC_DECISIONS "Addressed locals"
point 2). -/
def SrcType.packed : SrcType → Bool
  | .array element _ => element.accessKind.narrow
  | .i32 => false
  | .bool => false
  | .uint _ => false
  | .struct _ _ => false
  | .enum _ _ => false
  | .ptr => false
  | .slice _ => false
  | .unit => false
  | .isize => false
  | .char => false
  | .float _ => false
  | .sint _ => false
  | .view _ => false
  | .str => false
  | .ref _ => false

/-! ## Native layout -/

mutual
/-- A value's native words (`NativeLayout.words?`, extended to arrays): one
per scalar, two for a `str`, three for a slice (pointer, length, stride), a
struct its fields' (at least one), an enum its tag and its largest payload,
a packed array its bytes rounded up to words, any other array its elements'. -/
def SrcType.words : SrcType → Nat
  | .i32 => 1
  | .bool => 1
  | .uint _ => 1
  | .struct _ fields => max 1 (fieldWords fields)
  | .enum _ variants => 1 + variantWords variants
  | .ptr => 1
  | .slice _ => 3
  | .array element length =>
      if element.accessKind.narrow then (element.accessKind.bytes * length + 7) / 8
      else length * element.words
  | .unit => 1
  | .isize => 1
  | .char => 1
  | .float _ => 1
  | .sint _ => 1
  | .view _ => 1
  | .str => 2
  | .ref _ => 1

/-- The words of fields one after another. -/
def fieldWords : List SrcType → Nat
  | [] => 0
  | t :: rest => t.words + fieldWords rest

/-- The largest payload's words. -/
def variantWords : List (List SrcType) → Nat
  | [] => 0
  | fields :: rest => max (fieldWords fields) (variantWords rest)
end

/-! ## Places -/

/-- A place a reference or a borrowed slice names, held in frame memory:
Core's cell `cell` at the projection path `projections` holds a value of
`ty`, whose representation is in the mini heap from `address` (`FrameCorr`).
A `sliced` place is an array passed as a slice, laid out as a slice's
elements (`Addressed.view`); the others take one word per slot. -/
structure Addressed where
  cell : Nat
  projections : List Lanius.Core.ValueProjection
  ty : SrcType
  address : Nat
  sliced : Bool

/-- The pointer of a slice of a sliced place in native layout: its lowest
byte for packed `i32` and `u8` elements, which run up from it, and its top
word for the others, whose words run down from it (SEMANTIC_DECISIONS
"References: the memory model" point 4). -/
def Addressed.pointer (x : Addressed) : Nat :=
  match x.ty with
  | .array .i32 _ => x.address
  | .array (.uint .uint8) _ => x.address
  | _ => x.address + 8 * (x.ty.words - 1)

/-! ## Sub-places -/

/-- One projection into a value of `ty`: the byte offset of the field's or
element's block from the lowest byte of the value's block, and its type. A
struct's field `f` is the words of the fields before it below the top; a
packed array's element `i` is `i` widths up; another array's element `i` is
`i + 1` elements below the top. -/
def SrcType.subStep (ty : SrcType) (p : ValueProjection) : Option (Nat × SrcType) :=
  match ty with
  | .struct _ fields =>
      match p with
      | .field f =>
          match fields[f]? with
          | some fieldTy =>
              some (8 * (max 1 (fieldWords fields) - fieldWords (fields.take f) - fieldTy.words), fieldTy)
          | none => none
      | .index _ => none
  | .array element length =>
      match p with
      | .field _ => none
      | .index i =>
          if i < length then
            if element.accessKind.narrow then some (element.accessKind.bytes * i, element)
            else some (8 * (length * element.words - (i + 1) * element.words), element)
          else none
  | .i32 => none
  | .bool => none
  | .uint _ => none
  | .enum _ _ => none
  | .ptr => none
  | .slice _ => none
  | .unit => none
  | .isize => none
  | .char => none
  | .float _ => none
  | .sint _ => none
  | .view _ => none
  | .str => none
  | .ref _ => none

/-- The byte offset and type of the sub-place at `path` of a value of `ty`.
None when a projection does not fit the type or an element is out of range. -/
def SrcType.sub : SrcType → List ValueProjection → Option (Nat × SrcType)
  | ty, [] => some (0, ty)
  | ty, p :: rest =>
      match ty.subStep p with
      | none => none
      | some (offset, child) =>
          match child.sub rest with
          | none => none
          | some (inner, target) => some (offset + inner, target)

/-- The lowest byte and type of the sub-place of `x` at `path`. -/
def Addressed.sub (x : Addressed) (path : List ValueProjection) : Option (Nat × SrcType) :=
  match x.ty.sub path with
  | none => none
  | some (offset, ty) => some (x.address + offset, ty)

/-- `RefTo places ty cell path w`: the word `w` is the lowest byte of the
sub-place at `path`, of type `ty`, of the place whose cell is `cell`. -/
def RefTo (places : List Addressed) (ty : SrcType) (cell : Lanius.CellId) (path : List ValueProjection)
    (w : BitVec 64) : Prop :=
  ∃ x ∈ places, x.cell = cell ∧ x.sub path = some (w.toNat, ty)

/-- `RefHeld places ty v w`: the word `w` represents the reference `v` to a
`ty`. Stage 1's `SrcType.HoldsAt.ref ty` is this. It names the source type
`ty`, since `SrcType.toCore` is not one-to-one (`i32` and `sint .uint32`,
an `[i32; n]` and a view, structs' field lists). -/
def RefHeld (places : List Addressed) (ty : SrcType) (v : Value) (w : BitVec 64) : Prop :=
  ∃ cell path, v = .reference ty.toCore cell path ∧ RefTo places ty cell path w

end Lanius.Mini
