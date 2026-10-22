import Lanius.Semantics

/-! # `std::vec` as Core templates

The Core functions that monomorphizing `stdlib/std/vec.lani` (with
`core::mem::typed_slice_from_storage`) at one element type gives, written as
Lean functions of the element type `T` and of the callee and type ids
(`VecIds`). A program is an instance (`VecInstance`) when its functions at
those ids are these templates; the specs in `VecSpec.lean` are proved once
for every instance.

The shapes are what `SrcProgram.toCore` gives for the front end's reading of
the source (`Mini/Source.lean`): `if (c) { return e; }` then the rest is
`.sequence (.ifThenElse c (.returnValue e) .skip) rest`, `let x: t = e;` is
`.letLocal`, `return slice_from_raw_parts(p, n);` is a slice local and its
return, an integer literal at `isize` is `.cast isize` of the `i32` literal,
and `slice_from_raw_parts` is `i32SliceFromRawParts` at `i32` and
`typedSliceFromRawParts T` otherwise (`SrcType.sliceFrom`). Locals are
numbered as `frontend_difftest.py` compares programs (`canonFunc`):
parameters first, then binders in order.

One deliberate difference from the front end as it stands: `let p: ptr = 0;`
is the pointer literal `.value (.pointer 0)`. The front end reads it as the
`i32` literal 0 (`int_literal_at` keeps `Int(0)` at `Ptr`), whose Core
meaning traps in `slice_from_raw_parts` and stores an `i32` in `Vec.storage`;
`compileSource` rejects such programs (ROADMAP step 8). The front end cannot
read `stdlib/std/vec.lani` yet (no parse tree of it is cached, and it has
`&self` methods and `where` clauses), so `vecI32Program` and
`vecPairProgram` below are hand transcriptions of what `mono` would emit,
checked against the templates by `rfl`. -/

namespace Lanius.Std

open Lanius Lanius.Core

/-- The ids a monomorphized `std::vec` instance uses. -/
structure VecIds where
  /-- `Vec<T>` -/
  vec : TypeId
  /-- `core::option::Option<T>`: `Some` is variant 0, `None` variant 1 -/
  option : TypeId
  new : FunctionId
  len : FunctionId
  capacity : FunctionId
  isEmpty : FunctionId
  get : FunctionId
  getOr : FunctionId
  trySet : FunctionId
  tryPop : FunctionId
  truncate : FunctionId
  clear : FunctionId
  slots : FunctionId
  /-- `core::mem::typed_slice_from_storage<T>` -/
  fromStorage : FunctionId
deriving Repr

def i32Ty : Ty := .scalar (.signed .i32)
def ptrTy : Ty := .scalar .rawPtr
def isizeTy : Ty := .scalar (.signed .isize)
def usizeTy : Ty := .scalar (.unsigned .usize)
def boolTy : Ty := .scalar .bool

def int (n : Int) : Expr := .value (.signed .i32 n)

/-- `slice_from_raw_parts(pointer, length)` at element type `T`
(`SrcType.sliceFrom`). -/
def rawView (T : Ty) (pointer length : Expr) : Expr :=
  if T = i32Ty then .i32SliceFromRawParts pointer length
  else .typedSliceFromRawParts T pointer length

/-- `if (condition) { return value; }` followed by `rest`. -/
def guardReturn (condition value : Expr) (rest : Stmt) : Stmt :=
  .sequence (.ifThenElse condition (.returnValue (some value)) .skip) rest

/-- `index < 0 || index >= value.length`, with `value` local 0. -/
def outOfRange (index : VarId) : Expr :=
  .binary .logicalOr (.binary .less (.local index) (int 0))
    (.binary .greaterEqual (.local index) (.field (.local 0) 1))

section templates
variable (ids : VecIds) (T : Ty)

def vecTy : Ty := .structure ids.vec

/-- `core::mem::typed_slice_from_storage<T>(storage: ptr, length: i32) -> [T]` -/
def fromStorageFn : Function where
  id := ids.fromStorage
  parameters := [(0, ptrTy), (1, i32Ty)]
  returnType := .slice T
  body := some <|
    .sequence (.expression (.intrinsic .assert (.binary .greaterEqual (.local 1) (int 0))))
    (.letLocal 2 ptrTy (.value (.pointer 0))
    (.letLocal 3 (.slice T) (rawView T (.local 2) (int 0))
    (.letLocal 4 isizeTy (.intrinsic .sliceStride (.local 3))
    (.sequence
      (.ifThenElse
        (.binary .logicalOr (.binary .greaterEqual (.local 4) (.cast (.signed .isize) (int 0)))
          (.binary .equal (.local 1) (int 0)))
        (.letLocal 5 (.slice T) (rawView T (.local 0) (.local 1)) (.returnValue (some (.local 5))))
        .skip)
    (.letLocal 6 usizeTy
      (.binary .subtract
        (.binary .multiply
          (.cast (.unsigned .usize) (.binary .subtract (.cast (.signed .isize) (int 0)) (.local 4)))
          (.cast (.unsigned .usize) (.local 1)))
        (.value (.unsigned .usize 8)))
    (.letLocal 7 (.slice T) (rawView T (.binary .add (.local 0) (.local 6)) (.local 1))
      (.returnValue (some (.local 7)))))))))

/-- `fn slots<T>(value: Vec<T>) -> [T]` -/
def slotsFn : Function where
  id := ids.slots
  parameters := [(0, vecTy ids)]
  returnType := .slice T
  body := some (.returnValue (some (.call ids.fromStorage [.field (.local 0) 0, .field (.local 0) 2])))

def newFn : Function where
  id := ids.new
  parameters := []
  returnType := vecTy ids
  body := some (.letLocal 0 ptrTy (.value (.pointer 0))
    (.returnValue (some (.structValue ids.vec [.local 0, int 0, int 0]))))

def lenFn : Function where
  id := ids.len
  parameters := [(0, vecTy ids)]
  returnType := i32Ty
  body := some (.returnValue (some (.field (.local 0) 1)))

def capacityFn : Function where
  id := ids.capacity
  parameters := [(0, vecTy ids)]
  returnType := i32Ty
  body := some (.returnValue (some (.field (.local 0) 2)))

def isEmptyFn : Function where
  id := ids.isEmpty
  parameters := [(0, vecTy ids)]
  returnType := boolTy
  body := some (.returnValue (some (.binary .equal (.field (.local 0) 1) (int 0))))

def getFn : Function where
  id := ids.get
  parameters := [(0, vecTy ids), (1, i32Ty)]
  returnType := .enumeration ids.option
  body := some <| guardReturn (outOfRange 1) (.enumValue ids.option 1 [])
    (.letLocal 2 (.slice T) (.call ids.slots [.local 0])
      (.returnValue (some (.enumValue ids.option 0 [.index (.local 2) (.local 1)]))))

def getOrFn : Function where
  id := ids.getOr
  parameters := [(0, vecTy ids), (1, i32Ty), (2, T)]
  returnType := T
  body := some <| guardReturn (outOfRange 1) (.local 2)
    (.letLocal 3 (.slice T) (.call ids.slots [.local 0])
      (.returnValue (some (.index (.local 3) (.local 1)))))

def trySetFn : Function where
  id := ids.trySet
  parameters := [(0, vecTy ids), (1, i32Ty), (2, T)]
  returnType := vecTy ids
  body := some <| guardReturn (outOfRange 1) (.local 0)
    (.letLocal 3 (.slice T) (.call ids.slots [.local 0])
      (.sequence (.expression (.assign .set (.index (.local 3) (.local 1)) (.local 2)))
        (.returnValue (some (.local 0)))))

def tryPopFn : Function where
  id := ids.tryPop
  parameters := [(0, vecTy ids)]
  returnType := vecTy ids
  body := some <| guardReturn (.binary .equal (.field (.local 0) 1) (int 0)) (.local 0)
    (.returnValue (some (.structValue ids.vec
      [.field (.local 0) 0, .binary .subtract (.field (.local 0) 1) (int 1), .field (.local 0) 2])))

def truncateFn : Function where
  id := ids.truncate
  parameters := [(0, vecTy ids), (1, i32Ty)]
  returnType := vecTy ids
  body := some <| guardReturn (outOfRange 1) (.local 0)
    (.returnValue (some (.structValue ids.vec [.field (.local 0) 0, .local 1, .field (.local 0) 2])))

def clearFn : Function where
  id := ids.clear
  parameters := [(0, vecTy ids)]
  returnType := vecTy ids
  body := some (.returnValue (some (.structValue ids.vec [.field (.local 0) 0, int 0, .field (.local 0) 2])))

end templates

/-- `P` holds the `std::vec` functions at element type `T` under `ids`. -/
structure VecInstance (P : Program) (T : Ty) (ids : VecIds) : Prop where
  target : P.target = Target.x86_64
  fromStorage : P.function? ids.fromStorage = some (fromStorageFn ids T)
  slots : P.function? ids.slots = some (slotsFn ids T)
  new : P.function? ids.new = some (newFn ids)
  len : P.function? ids.len = some (lenFn ids)
  capacity : P.function? ids.capacity = some (capacityFn ids)
  isEmpty : P.function? ids.isEmpty = some (isEmptyFn ids)
  get : P.function? ids.get = some (getFn ids T)
  getOr : P.function? ids.getOr = some (getOrFn ids T)
  trySet : P.function? ids.trySet = some (trySetFn ids T)
  tryPop : P.function? ids.tryPop = some (tryPopFn ids)
  truncate : P.function? ids.truncate = some (truncateFn ids)
  clear : P.function? ids.clear = some (clearFn ids)

end Lanius.Std
