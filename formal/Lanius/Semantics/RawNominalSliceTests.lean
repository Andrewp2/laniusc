import Lanius.Semantics

namespace Lanius.Semantics.RawNominalSliceTests

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics

private def pairProgram : Program := {
  structures := [{ id := 3, fields :=
    [.scalar (.signed .i32), .scalar (.signed .i32)] }]
}

private def block : Block :=
  { base := 8, size := 32, alignment := 8,
    bytes := List.replicate 32 (0 : UInt8) }

private def state : State :=
  { heap := { blocks := [block], nextAddress := 40 } }

private def valuedBlock : Block :=
  { block with bytes := (
      i32Bytes 40 ++ List.replicate 4 0 ++
      i32Bytes 2 ++ List.replicate 4 0 ++
      i32Bytes 20 ++ List.replicate 4 0 ++
      i32Bytes 1 ++ List.replicate 4 0) }

private def valuedState : State :=
  { state with heap := { state.heap with blocks := [valuedBlock] } }

private def boundState : State :=
  valuedState.bindLocal 0 (.rawSlice (.structure 3) 32 2)

example : NativeLayout.valueWords? pairProgram (.structure 3) = some 2 := by
  decide

example : NativeLayout.structureFieldOffset? pairProgram 3 0 = some 0 := by
  decide

example : NativeLayout.structureFieldOffset? pairProgram 3 1 = some 8 := by
  decide

example : NativeLayout.elementBase? 32 0 2 = some 24 := by
  decide

example : NativeLayout.elementBase? 32 1 2 = some 8 := by
  decide

example :
    (match mapRawNominalSlice pairProgram state (.structure 3) 32 2 with
    | .done (.rawSlice (.structure 3) 32 2) after =>
        match after.heap.block? 8 with
        | some block => !block.owned
        | none => false
    | _ => false) = true := by
  decide

example :
    (match mapRawNominalSlice pairProgram state (.structure 3) 32 1 with
    | .done (.rawSlice (.structure 3) 32 1) _ => true
    | _ => false) = true := by
  decide

example :
    (match mapRawNominalSlice pairProgram state (.structure 3) 32 3 with
    | .trapped .rawMemoryBounds _ => true
    | _ => false) = true := by
  decide

example :
    (match mapRawNominalSlice pairProgram state (.structure 3) 32 (-1) with
    | .trapped .rawMemoryBounds _ => true
    | _ => false) = true := by
  decide

example :
    (match mapRawNominalSlice pairProgram state (.structure 3) 0 0 with
    | .done (.rawSlice (.structure 3) 0 0) _ => true
    | _ => false) = true := by
  decide

example :
    (match evalExpr 4 pairProgram state
      (.typedSliceFromRawParts (.structure 3) (.value (.pointer 32))
        (.value (.signed .i32 2))) with
    | .done (.rawSlice (.structure 3) 32 2) _ => true
    | _ => false) = true := by
  decide

example :
    (match mapRawNominalSlice pairProgram state
      (.scalar (.signed .i32)) 32 1 with
    | .trapped .typeMismatch _ => true
    | _ => false) = true := by
  decide

example :
    (match readRawSliceIndex pairProgram valuedState (.structure 3) 32 2 0 with
    | .ok (.structure 3 [.signed .i32 20, .signed .i32 1]) => true
    | _ => false) = true := by
  decide

example :
    (match readRawSliceIndex pairProgram valuedState (.structure 3) 32 2 1 with
    | .ok (.structure 3 [.signed .i32 40, .signed .i32 2]) => true
    | _ => false) = true := by
  decide

example :
    (match evalExpr 6 pairProgram valuedState
      (.index
        (.typedSliceFromRawParts (.structure 3) (.value (.pointer 32))
          (.value (.signed .i32 2)))
        (.value (.signed .i32 1))) with
    | .done (.structure 3 [.signed .i32 40, .signed .i32 2]) _ => true
    | _ => false) = true := by
  decide

example :
    (match readRawSliceIndex pairProgram valuedState (.structure 3) 32 2 2 with
    | .error .arrayBounds => true
    | _ => false) = true := by
  decide

example :
    (match evalExpr 12 pairProgram boundState
      (.assign .set
        (.field (.index (.local 0) (.value (.signed .i32 1))) 0)
        (.value (.signed .i32 99))) with
    | .done .unit after =>
        match readRawSliceIndex pairProgram after (.structure 3) 32 2 1,
            readRawSliceIndex pairProgram after (.structure 3) 32 2 0 with
        | .ok (.structure 3 [.signed .i32 99, .signed .i32 2]),
          .ok (.structure 3 [.signed .i32 20, .signed .i32 1]) => true
        | _, _ => false
    | _ => false) = true := by
  decide

private def descriptorProgram : Program := {
  structures := [{ id := 4, fields := [.slice (.scalar (.signed .i32))] }]
}

private def descriptorBlock : Block :=
  { base := 8, size := 48, alignment := 8,
    bytes := encodeNatLE 8 40 ++ encodeNatLE 8 1 ++
      List.replicate 16 (0 : UInt8) ++ i32Bytes 77 ++
      List.replicate 12 (0 : UInt8) }

private def descriptorState : State :=
  { heap := { blocks := [descriptorBlock], nextAddress := 56 } }

example :
    (match readRawSliceIndex descriptorProgram descriptorState
        (.structure 4) 16 1 0 with
      | .ok (.structure 4 [.rawSlice (.scalar (.signed .i32)) 40 1]) => true
      | _ => false) = true := by
  decide

example :
    (match writeNativeValue NativeLayout.maxDepth descriptorProgram
        descriptorState descriptorState.heap (.structure 4) 8
        (.structure 4 [.rawSlice (.scalar (.signed .i32)) 40 1]) with
      | .ok heap =>
          match readNativeValue NativeLayout.maxDepth descriptorProgram heap
              (.structure 4) 8 with
          | .ok (.structure 4 [.rawSlice (.scalar (.signed .i32)) 40 1]) => true
          | _ => false
      | .error _ => false) = true := by
  decide

private def viewState : State :=
  { descriptorState with i32ArrayViews :=
      [{ address := 40, root := 5, projections := [], length := 1 }] }

example :
    (match writeNativeValue NativeLayout.maxDepth descriptorProgram
        viewState viewState.heap (.structure 4) 8
        (.structure 4 [.slice (.scalar (.signed .i32)) 5 [] 0 1]) with
      | .ok heap =>
          match readNativeValue NativeLayout.maxDepth descriptorProgram heap
              (.structure 4) 8 with
          | .ok (.structure 4 [.rawSlice (.scalar (.signed .i32)) 40 1]) => true
          | _ => false
      | .error _ => false) = true := by
  decide

end Lanius.Semantics.RawNominalSliceTests
