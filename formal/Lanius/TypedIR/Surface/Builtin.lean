import Lanius.TypedIR.Surface.Operations

namespace Lanius.TypedIR.Surface.Builtin

-- These build the primitive's syntax directly. No argument-type certificate
-- or fallback value is constructed; Lanius supplies the resolved operands.
def toUsize (value : Expr α) : Expr Usize := ⟨.cast (.unsigned .usize) value.core⟩
def toI32 (value : Expr α) : Expr I32 := ⟨.cast (.signed .i32) value.core⟩
def i32SliceFromRawParts (pointer : Expr α) (length : Expr β) : Expr (Slice I32) :=
  ⟨.i32SliceFromRawParts pointer.core length.core⟩
def typedSliceFromRawParts [Code element] (pointer : Expr α) (length : Expr β) : Expr (Slice element) :=
  ⟨.typedSliceFromRawParts (Code.ty element) pointer.core length.core⟩
def i32SliceDataPtr (value : Expr α) : Expr RawPtr := ⟨.i32SliceDataPtr value.core⟩
def stringDataPtr (value : Expr α) : Expr RawPtr := ⟨.stringDataPtr value.core⟩
def pointerAdd (pointer : Expr α) (offset : Expr β) : Expr RawPtr :=
  ⟨.binary .add pointer.core offset.core⟩
def pointerSubtract (pointer : Expr α) (offset : Expr β) : Expr RawPtr :=
  ⟨.binary .subtract pointer.core offset.core⟩

end Lanius.TypedIR.Surface.Builtin
