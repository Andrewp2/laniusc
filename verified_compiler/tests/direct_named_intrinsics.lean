import Lanius.TypedIR.Surface.Syntax

open Lanius Lanius.TypedIR.Surface
open scoped Lanius.TypedIR.Surface


example (value : Expr String) :
    (Builtin.stringDataPtr value).core =
      .stringDataPtr value.core := rfl

example (value : Expr (Slice I32)) :
    (Builtin.i32SliceDataPtr value).core =
      .i32SliceDataPtr value.core := rfl

example (pointer : Expr RawPtr) (length : Expr I32) :
    (Builtin.i32SliceFromRawParts pointer length).core =
      .i32SliceFromRawParts pointer.core length.core := rfl

private inductive Cell where | empty
attribute [lanius_type record 4] Cell

private def view : Function [RawPtr, I32] (Slice Cell) :=
  let pointer : Var RawPtr := Var.named 0 "pointer"
  let length : Var I32 := Var.named 1 "length"
  function (id := 0, name := "view", arguments := [pointer := pointer.id, length := length.id], bindings := []) do
    return (Lanius.TypedIR.Surface.Builtin.typedSliceFromRawParts pointer length : Slice Cell)

example : view.core.body = some (.returnValue (some
    (.typedSliceFromRawParts (.structure 4) (.local 0) (.local 1)))) := rfl

private def widen : Function [] Usize :=
  function (id := 1, name := "widen", arguments := [], bindings := [0]) do
    let value : Usize := (7 : Usize)
    return value + Lanius.TypedIR.Surface.Builtin.toUsize 9

example : widen.core.body = some (.letLocal 0 (.scalar (.unsigned .usize))
    (.value (.unsigned .usize 7)) (.returnValue (some (.binary .add (.local 0)
      (.cast (.unsigned .usize) (.value (.signed .i32 9))))))) := rfl

private def offset : Function [] RawPtr :=
  function (id := 2, name := "offset", arguments := [], bindings := []) do
    return Lanius.TypedIR.Surface.Builtin.pointerAdd (0 : RawPtr) 8

example : offset.core.body = some (.returnValue (some
    (.binary .add (.value (.pointer 0)) (.value (.signed .i32 8))))) := rfl
