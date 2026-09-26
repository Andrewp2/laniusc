import Lanius.Typing.Check.Expressions

namespace Lanius.Typing.Check.RawNominalSliceTests

open Lanius Lanius.Core Lanius.Typing

private def program : Program := {
  structures := [{ id := 3, fields := [.scalar (.signed .i32)] }]
  enumerations := [{ id := 5, variants := [[]] }]
}

private def pointer : Expr := .value (.pointer 0)
private def length : Expr := .value (.signed .i32 2)

theorem structureAccepted :
    (checkExprAny program Context.empty
      (.typedSliceFromRawParts (.structure 3) pointer length)).isSome = true := by
  decide

example :
    (checkExprAny program Context.empty
      (.typedSliceFromRawParts (.enumeration 5) pointer length)).isSome = true := by
  decide

example :
    (checkExprAny program Context.empty
      (.typedSliceFromRawParts (.structure 4) pointer length)).isSome = false := by
  decide

example :
    (checkExprAny program Context.empty
      (.typedSliceFromRawParts (.scalar (.signed .i32)) pointer length)).isSome = false := by
  decide

example :
    (checkExprAny program Context.empty
      (.typedSliceFromRawParts (.structure 3) length length)).isSome = false := by
  decide

example :
    (checkExprAny program Context.empty
      (.typedSliceFromRawParts (.structure 3) pointer pointer)).isSome = false := by
  decide

end Lanius.Typing.Check.RawNominalSliceTests
