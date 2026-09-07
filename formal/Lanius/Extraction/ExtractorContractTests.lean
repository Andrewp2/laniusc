import Lanius.Extraction.ExtractorContract

namespace Lanius.Extraction.ExtractorContract

example : modulePrefix.toUTF8.size = 146 := by
  native_decide

example : moduleSuffix.toUTF8.size = 677 := by
  native_decide

example : renderedModule "abc" = modulePrefix ++ "abc" ++ moduleSuffix := by
  rfl

example : FailureCode 1 := .noInputs

example : FailureCode 28 := .extraction

example :
    Lanius.World.callSimple ({} : Lanius.World.State) .writeByte
        [.signed .i32 1, .signed .i32 65] =
      .returned (.signed .i32 1) {
        ({} : Lanius.World.State) with
        standardOutput := [65]
        calls := [.writeByte]
      } := by
  rfl

def twoWordHeap : Lanius.Memory.Heap := {
  blocks := [{
    base := 4
    size := 8
    alignment := 4
    bytes := List.replicate 8 0
  }]
  nextAddress := 12
}

def rawSliceConstructionAccepted : Bool :=
  match Lanius.Semantics.mapRawI32Slice { heap := twoWordHeap } 4 2 with
  | .done (.slice (.scalar (.signed .i32)) _ [] 0 2) after =>
      after.cells.length == 1 && after.i32ArrayViews.length == 1 &&
        (after.heap.block? 4 |>.map (fun block => !block.owned) |>.getD false)
  | _ => false

example : rawSliceConstructionAccepted = true := by
  native_decide

def existingSlicePointerReusesView : Bool :=
  match Lanius.Semantics.mapRawI32Slice { heap := twoWordHeap } 4 2 with
  | .done (.slice (.scalar (.signed .i32)) root [] 0 2) after =>
      match Lanius.Semantics.mapI32SliceDataPtr after root [] 0 2 with
      | .done (.pointer address) reused =>
          address == 4 && reused.i32ArrayViews.length == 1 &&
            reused.cells.length == after.cells.length
      | _ => false
  | _ => false

example : existingSlicePointerReusesView = true := by
  native_decide

def rawSliceNegativeLengthRejected : Bool :=
  match Lanius.Semantics.mapRawI32Slice { heap := twoWordHeap } 4 (-1) with
  | .trapped .rawMemoryBounds _ => true
  | _ => false

example : rawSliceNegativeLengthRejected = true := by
  native_decide

def stringStorageAccepted : Bool :=
  match Lanius.Semantics.mapStringDataPtr {} "abcd" with
  | .done (.pointer address) after =>
      match after.heap.loadBytes address 4 with
      | .ok bytes => bytes == Lanius.World.utf8Bytes "abcd"
      | .error _ => false
  | _ => false

example : stringStorageAccepted = true := by
  native_decide

/-- Whole-word borrowing must not silently make bytes beyond a string valid. -/
def wordStringAccepted (text : String) (words : Int) : Bool :=
  match Lanius.Semantics.mapStringDataPtr {} text with
  | .done (.pointer address) after =>
      match Lanius.Semantics.mapRawI32Slice after address words with
      | .done (.slice _ _ _ _ _) _ => true
      | _ => false
  | _ => false

example : (["f", "fn", "pub", "false", "return"].all fun text =>
    !wordStringAccepted text ((text.toUTF8.size + 3) / 4)) = true := by native_decide

example : (["f\x00\x00\x00", "fn\x00\x00", "pub\x00", "else",
    "false\x00\x00\x00", "return\x00\x00", "continue"].all fun text =>
    wordStringAccepted text (text.toUTF8.size / 4)) = true := by native_decide

end Lanius.Extraction.ExtractorContract
