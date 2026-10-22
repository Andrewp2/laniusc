import Lanius.Std.VecTemplate

/-! # Hand transcriptions of monomorphized `std::vec`

Two Core programs as `mono` + `SrcProgram.toCore` would emit them for a
client of `std::vec` at `i32` and at `struct Pair { a: i32, b: i32 }`,
spelled out constructor by constructor from `stdlib/std/vec.lani` and
`stdlib/core/mem.lani` (see `VecTemplate.lean` for why by hand). Each is
checked to be an instance of the templates by `rfl`, so a change to a
template that the transcription does not share fails here. -/

namespace Lanius.Std

open Lanius Lanius.Core

/-- `typed_slice_from_storage<i32>`, as read: the view is
`i32SliceFromRawParts`. -/
private def i32FromStorage : Function where
  id := 6
  parameters := [(0, .scalar .rawPtr), (1, .scalar (.signed .i32))]
  returnType := .slice (.scalar (.signed .i32))
  body := some <|
    .sequence
      (.expression (.intrinsic .assert
        (.binary .greaterEqual (.local 1) (.value (.signed .i32 0)))))
      (.letLocal 2 (.scalar .rawPtr) (.value (.pointer 0))
        (.letLocal 3 (.slice (.scalar (.signed .i32)))
          (.i32SliceFromRawParts (.local 2) (.value (.signed .i32 0)))
          (.letLocal 4 (.scalar (.signed .isize)) (.intrinsic .sliceStride (.local 3))
            (.sequence
              (.ifThenElse
                (.binary .logicalOr
                  (.binary .greaterEqual (.local 4) (.cast (.signed .isize) (.value (.signed .i32 0))))
                  (.binary .equal (.local 1) (.value (.signed .i32 0))))
                (.letLocal 5 (.slice (.scalar (.signed .i32)))
                  (.i32SliceFromRawParts (.local 0) (.local 1))
                  (.returnValue (some (.local 5))))
                .skip)
              (.letLocal 6 (.scalar (.unsigned .usize))
                (.binary .subtract
                  (.binary .multiply
                    (.cast (.unsigned .usize)
                      (.binary .subtract (.cast (.signed .isize) (.value (.signed .i32 0))) (.local 4)))
                    (.cast (.unsigned .usize) (.local 1)))
                  (.value (.unsigned .usize 8)))
                (.letLocal 7 (.slice (.scalar (.signed .i32)))
                  (.i32SliceFromRawParts (.binary .add (.local 0) (.local 6)) (.local 1))
                  (.returnValue (some (.local 7)))))))))

/-- The same at `Pair` (struct id 2): the views are typed. -/
private def pairFromStorage : Function where
  id := 6
  parameters := [(0, .scalar .rawPtr), (1, .scalar (.signed .i32))]
  returnType := .slice (.structure 2)
  body := some <|
    .sequence
      (.expression (.intrinsic .assert
        (.binary .greaterEqual (.local 1) (.value (.signed .i32 0)))))
      (.letLocal 2 (.scalar .rawPtr) (.value (.pointer 0))
        (.letLocal 3 (.slice (.structure 2))
          (.typedSliceFromRawParts (.structure 2) (.local 2) (.value (.signed .i32 0)))
          (.letLocal 4 (.scalar (.signed .isize)) (.intrinsic .sliceStride (.local 3))
            (.sequence
              (.ifThenElse
                (.binary .logicalOr
                  (.binary .greaterEqual (.local 4) (.cast (.signed .isize) (.value (.signed .i32 0))))
                  (.binary .equal (.local 1) (.value (.signed .i32 0))))
                (.letLocal 5 (.slice (.structure 2))
                  (.typedSliceFromRawParts (.structure 2) (.local 0) (.local 1))
                  (.returnValue (some (.local 5))))
                .skip)
              (.letLocal 6 (.scalar (.unsigned .usize))
                (.binary .subtract
                  (.binary .multiply
                    (.cast (.unsigned .usize)
                      (.binary .subtract (.cast (.signed .isize) (.value (.signed .i32 0))) (.local 4)))
                    (.cast (.unsigned .usize) (.local 1)))
                  (.value (.unsigned .usize 8)))
                (.letLocal 7 (.slice (.structure 2))
                  (.typedSliceFromRawParts (.structure 2) (.binary .add (.local 0) (.local 6)) (.local 1))
                  (.returnValue (some (.local 7)))))))))

/-- `index < 0 || index >= value.length`. -/
private def badIndex (index : VarId) : Expr :=
  .binary .logicalOr (.binary .less (.local index) (.value (.signed .i32 0)))
    (.binary .greaterEqual (.local index) (.field (.local 0) 1))

/-- The element-independent functions; `Vec<T>` is struct id 0, `Option<T>`
enum id 1. -/
private def commonFunctions (element : Ty) : List Function := [
  { id := 0, parameters := [], returnType := .structure 0,
    body := some (.letLocal 0 (.scalar .rawPtr) (.value (.pointer 0))
      (.returnValue (some (.structValue 0
        [.local 0, .value (.signed .i32 0), .value (.signed .i32 0)])))) },
  { id := 1, parameters := [(0, .structure 0)], returnType := .scalar (.signed .i32),
    body := some (.returnValue (some (.field (.local 0) 1))) },
  { id := 2, parameters := [(0, .structure 0)], returnType := .scalar (.signed .i32),
    body := some (.returnValue (some (.field (.local 0) 2))) },
  { id := 3, parameters := [(0, .structure 0)], returnType := .scalar .bool,
    body := some (.returnValue (some (.binary .equal (.field (.local 0) 1) (.value (.signed .i32 0))))) },
  { id := 4, parameters := [(0, .structure 0), (1, .scalar (.signed .i32))],
    returnType := .enumeration 1,
    body := some (.sequence
      (.ifThenElse (badIndex 1) (.returnValue (some (.enumValue 1 1 []))) .skip)
      (.letLocal 2 (.slice element) (.call 5 [.local 0])
        (.returnValue (some (.enumValue 1 0 [.index (.local 2) (.local 1)]))))) },
  { id := 5, parameters := [(0, .structure 0)], returnType := .slice element,
    body := some (.returnValue (some (.call 6 [.field (.local 0) 0, .field (.local 0) 2]))) },
  { id := 7, parameters := [(0, .structure 0), (1, .scalar (.signed .i32)), (2, element)],
    returnType := element,
    body := some (.sequence
      (.ifThenElse (badIndex 1) (.returnValue (some (.local 2))) .skip)
      (.letLocal 3 (.slice element) (.call 5 [.local 0])
        (.returnValue (some (.index (.local 3) (.local 1)))))) },
  { id := 8, parameters := [(0, .structure 0), (1, .scalar (.signed .i32)), (2, element)],
    returnType := .structure 0,
    body := some (.sequence
      (.ifThenElse (badIndex 1) (.returnValue (some (.local 0))) .skip)
      (.letLocal 3 (.slice element) (.call 5 [.local 0])
        (.sequence (.expression (.assign .set (.index (.local 3) (.local 1)) (.local 2)))
          (.returnValue (some (.local 0)))))) },
  { id := 9, parameters := [(0, .structure 0)], returnType := .structure 0,
    body := some (.sequence
      (.ifThenElse (.binary .equal (.field (.local 0) 1) (.value (.signed .i32 0)))
        (.returnValue (some (.local 0))) .skip)
      (.returnValue (some (.structValue 0 [.field (.local 0) 0,
        .binary .subtract (.field (.local 0) 1) (.value (.signed .i32 1)), .field (.local 0) 2])))) },
  { id := 10, parameters := [(0, .structure 0), (1, .scalar (.signed .i32))],
    returnType := .structure 0,
    body := some (.sequence
      (.ifThenElse (badIndex 1) (.returnValue (some (.local 0))) .skip)
      (.returnValue (some (.structValue 0 [.field (.local 0) 0, .local 1, .field (.local 0) 2])))) },
  { id := 11, parameters := [(0, .structure 0)], returnType := .structure 0,
    body := some (.returnValue (some (.structValue 0
      [.field (.local 0) 0, .value (.signed .i32 0), .field (.local 0) 2]))) }]

def vecI32Program : Program where
  structures := [{ id := 0, fields := [.scalar .rawPtr, .scalar (.signed .i32), .scalar (.signed .i32)] }]
  enumerations := [{ id := 1, variants := [[.scalar (.signed .i32)], []] }]
  functions := commonFunctions (.scalar (.signed .i32)) ++ [i32FromStorage]

def vecPairProgram : Program where
  structures := [{ id := 0, fields := [.scalar .rawPtr, .scalar (.signed .i32), .scalar (.signed .i32)] },
    { id := 2, fields := [.scalar (.signed .i32), .scalar (.signed .i32)] }]
  enumerations := [{ id := 1, variants := [[.structure 2], []] }]
  functions := commonFunctions (.structure 2) ++ [pairFromStorage]

def transcriptionIds : VecIds where
  vec := 0
  option := 1
  new := 0
  len := 1
  capacity := 2
  isEmpty := 3
  get := 4
  slots := 5
  fromStorage := 6
  getOr := 7
  trySet := 8
  tryPop := 9
  truncate := 10
  clear := 11

theorem vecI32Program_instance : VecInstance vecI32Program i32Ty transcriptionIds :=
  ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩

theorem vecPairProgram_instance : VecInstance vecPairProgram (.structure 2) transcriptionIds :=
  ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩

end Lanius.Std
