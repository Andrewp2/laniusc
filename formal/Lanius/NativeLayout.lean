import Lanius.Core

namespace Lanius.NativeLayout

open Lanius
open Lanius.Core

/-- The Lanius x86 value ABI stores each scalar in an eight-byte slot. This
    layout is distinct from the compact object layout in `Lanius.Layout`. -/
def wordBytes : Nat := 8
def maxWords : Nat := 4096
def maxDepth : Nat := 64

/-- Resolve the word width of the x86 backend's currently supported value
    types. Slices cut recursive nominal references; by-value cycles exhaust
    the depth bound. The bound and width cap match the Lanius backend. -/
def words? : Nat → Program → Ty → Option Nat
  | 0, _, _ => none
  | fuel + 1, program, type =>
      match type with
      | .scalar (.signed .i32) | .scalar .bool
      | .scalar (.unsigned .usize) | .scalar .rawPtr => some 1
      | .scalar .string => some 2
      | .slice (.scalar (.signed .i32)) => some 2
      | .slice (.structure id) =>
          if (program.structure? id).isSome then some 2 else none
      | .slice (.enumeration id) =>
          if (program.enumeration? id).isSome then some 2 else none
      | .structure id => do
          let declaration ← program.structure? id
          let widths ← declaration.fields.mapM (words? fuel program)
          let total := widths.foldl (· + ·) 0
          if total ≤ maxWords then some (max 1 total) else none
      | .enumeration id => do
          let declaration ← program.enumeration? id
          let payloads ← declaration.variants.mapM fun fields => do
            let widths ← fields.mapM (words? fuel program)
            let total := widths.foldl (· + ·) 0
            if total < maxWords then some total else none
          some (1 + payloads.foldl max 0)
      | _ => none

def valueWords? (program : Program) (type : Ty) : Option Nat :=
  words? maxDepth program type

/-- Positive field offsets are measured from the low word of an x86 value.
    A raw nominal-slice descriptor instead points to the high word of its
    first element; indexed access normalizes that pointer first. -/
def structureFieldOffset? (program : Program) (id : TypeId)
    (field : FieldId) : Option Nat := do
  let declaration ← program.structure? id
  if field < declaration.fields.length then
    let widths ← (declaration.fields.take field).mapM
      (words? (maxDepth - 1) program)
    some (wordBytes * widths.foldl (· + ·) 0)
  else none

def elementBase? (highWordPointer index words : Nat) : Option Nat :=
  let displacement := (index * words + words - 1) * wordBytes
  if words == 0 || highWordPointer < displacement then none
  else some (highWordPointer - displacement)

end Lanius.NativeLayout
