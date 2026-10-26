module

public import Lanius.Core

@[expose] public section

namespace Lanius.NativeLayout

open Lanius
open Lanius.Core

/-- The Lanius x86 value ABI stores each scalar in an eight-byte word. A
    value's words descend from its address: word k is at `address - 8 * k`
    (laniusc's `docs/wasm-memory-layout.md`). This layout is distinct from the
    compact object layout in `Lanius.Layout`. -/
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
      | .scalar (.signed _) | .scalar (.unsigned _) | .scalar .bool
      | .scalar .rawPtr => some 1
      | .scalar .string => some 2
      | .slice (.scalar (.signed .i32)) => some 3
      | .slice (.structure id) =>
          if (program.structure? id).isSome then some 3 else none
      | .slice (.enumeration id) =>
          if (program.enumeration? id).isSome then some 3 else none
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

/-- A field's offset is how many bytes below its value's address (word 0)
    the field's own word 0 lies. -/
def structureFieldOffset? (program : Program) (id : TypeId)
    (field : FieldId) : Option Nat := do
  let declaration ← program.structure? id
  if field < declaration.fields.length then
    let widths ← (declaration.fields.take field).mapM
      (words? (maxDepth - 1) program)
    some (wordBytes * widths.foldl (· + ·) 0)
  else none

/-- Element `index` of a raw view of `words`-word values whose descriptor is
    element zero's word 0: its own word 0, `index * words` words below. The
    whole element must lie at or above address zero. -/
def elementBase? (highWordPointer index words : Nat) : Option Nat :=
  let displacement := (index * words + words - 1) * wordBytes
  if words == 0 || highWordPointer < displacement then none
  else some (highWordPointer - index * words * wordBytes)

/-- A raw view's signed byte stride: element i + 1 starts this many bytes
    after element i. i32 views are packed and run forward; views of structs
    and enums run down by their native size. -/
def elementStride? (program : Program) (element : Ty) : Option Int :=
  match element with
  | .scalar (.signed .i32) => some 4
  | .structure _ | .enumeration _ =>
      match valueWords? program element with
      | some words => some (-((wordBytes * words : Nat) : Int))
      | none => none
  | _ => none

end Lanius.NativeLayout
