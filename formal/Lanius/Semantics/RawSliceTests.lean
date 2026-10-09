import Lanius.Semantics.RawSlice

namespace Lanius.Semantics.RawSliceTests

open Lanius.Core Lanius.Memory

private def block : Block := {
  base := 4, size := 8, alignment := 4, bytes := i32Bytes 7 ++ i32Bytes 11 }
private def state : State := { heap := { blocks := [block], nextAddress := 12 } }

-- Raw construction adds neither backing cells nor registered views.
example : (match mapRawI32Slice state 4 2 with
  | .done (.rawSlice (.scalar (.signed .i32)) 4 2) after =>
      after.cells.isEmpty && after.i32ArrayViews.isEmpty && after.nextCell == 0 &&
        (match after.heap.block? 4 with | some block => !block.owned | _ => false)
  | _ => false) = true := by decide

example : (match mapRawI32Slice state 4 2 with
  | .done first after => match mapRawI32Slice after 4 2 with
    | .done second final => first == second && final.cells.isEmpty && final.i32ArrayViews.isEmpty
    | _ => false
  | _ => false) = true := by decide

example : (match mapRawI32Slice state 4 3 with
  | .trapped .rawMemoryBounds _ => true | _ => false) = true := by decide

example : (match mapRawI32Slice {} 0 (-1) with
  | .trapped .rawMemoryBounds _ => true | _ => false) = true := by decide

example : (match mapRawI32Slice state 16 2 with
  | .trapped .invalidPointer _ => true | _ => false) = true := by decide

-- Empty descriptors do not access or take ownership of backing storage.
example (state : State) (address : Lanius.Address) :
    mapRawI32Slice state address 0 = .done (.rawSlice (.scalar (.signed .i32)) address 0) state :=
  mapRawI32Slice_empty state address
example : mapRawI32Slice {} 0 0 = .done (.rawSlice (.scalar (.signed .i32)) 0 0) {} := rfl
example : (match mapRawI32Slice {} 0 1 with
  | .trapped .invalidPointer _ => true | _ => false) = true := by decide
example (program : Program) (state : State) (address position : Nat) :
    readRawSliceIndex program state (.scalar (.signed .i32)) address 0 position = .error .arrayBounds := by
  simp [readRawSliceIndex]

example : (match mapRawI32Slice
    { heap := { blocks := [{ base := 4, size := 0, alignment := 4, bytes := [] }] } } 4 0 with
  | .done (.rawSlice element address length) after =>
      match readRawSliceIndex {} after element address length 0 with
      | .error .arrayBounds => true | _ => false
  | _ => false) = true := by decide

private def alias : Outcome Value :=
  let elements := [.signed .i32 7, .signed .i32 11]
  let initial := ({} : State).bindLocal 1 (.array elements)
  match mapI32ArrayView initial 0 [] elements with
  | .done (.pointer address) after => mapRawI32Slice after address 2
  | other => other

-- Genuine language-array aliases still synchronize in both directions.
-- This is an executable regression, not a general alias-coherence theorem.
private def mixedAliases : Bool := match alias with
  | .done raw mapped =>
    let bound := mapped.bindLocal 2 raw
    match evalExpr 12 {} bound
        (.assign .set (.index (.local 2) (.value (.signed .i32 1))) (.value (.signed .i32 29))) with
    | .done .unit afterRaw =>
      match afterRaw.local? 1 with
      | some (.array [.signed .i32 7, .signed .i32 29]) =>
        match evalExpr 12 {} afterRaw
            (.assign .set (.index (.local 1) (.value (.signed .i32 0))) (.value (.signed .i32 37))) with
        | .done .unit afterArray =>
          match evalExpr 4 {} afterArray (.index (.local 2) (.value (.signed .i32 0))) with
          | .done (.signed .i32 37) _ => afterArray.i32ArrayViews.length == 1
          | _ => false
        | _ => false
      | _ => false
    | _ => false
  | _ => false

#eval (do
  unless mixedAliases do throw (IO.userError "raw/cell-backed aliases diverged") : IO Unit)

#print axioms mapRawI32Slice_of_block
#print axioms mapRawI32Slice_empty
#print axioms StableExpr.rawSliceDataPtr

-- These are general setup contracts, not assumptions of successful raw
-- construction. Empty and padded UTF-8 input use the same rules.
example (input : String) : mapRawI32Slice
    { heap := ({} : Heap).borrowedI32 (stringStorage input) }
    ({} : Heap).borrowedAddress (((World.utf8Bytes input).length + 3) / 4 : Nat) =
    .done (.rawSlice (.scalar (.signed .i32)) 4 (((World.utf8Bytes input).length + 3) / 4))
      { heap := ({} : Heap).borrowedI32 (stringStorage input) } := by
  exact mapRawI32Slice_stringStorage rfl (by simp [HeapBlocksBelowNext])
    (by simp [HeapBlockBasesUnique])

#print axioms mapRawI32Slice_stringStorage
#print axioms RunsExpr.stringDataPtr
#print axioms RunsExpr.rawSliceFromParts

end Lanius.Semantics.RawSliceTests
