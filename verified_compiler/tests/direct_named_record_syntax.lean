import Lanius.TypedIR.Surface.Syntax

open Lanius Lanius.TypedIR.Surface
open scoped Lanius.TypedIR.Surface


private inductive Pair where | mk (value : I32) (valid : Bool)
attribute [lanius_type record 0] Pair


private def buildPair : Function [] Pair :=
  function (id := 0, name := "buildPair", arguments := [], bindings := []) do
    return { value := 7, valid := true : Pair }

example : buildPair.core.body = some (.returnValue (some
    (.structValue 0 [.value (.signed .i32 7), .value (.boolean true)]))) := rfl

-- Field names, not their written order, select the stored slots. This must
-- agree with Lanius lowering when a proof rebuilds an extracted record.
private def reorderedPair : Function [] Pair :=
  function (id := 0, name := "reorderedPair", arguments := [], bindings := []) do
    return { valid := true, value := 7 : Pair }

example : reorderedPair.core = buildPair.core := rfl

-- This is name resolution, not a new Lanius typing check. A mismatched
-- initializer is still ordinary Core data, just like an unchecked call.
private def uncheckedPair : Function [] Pair :=
  function (id := 0, name := "uncheckedPair", arguments := [], bindings := []) do
    return { value := true, valid := 7 : Pair }
example : uncheckedPair.core.body = some (.returnValue (some
    (.structValue 0 [.value (.boolean true), .value (.signed .i32 7)]))) := rfl

/-- error: duplicate source field value -/
#guard_msgs in
example : Function [] Pair :=
  function (id := 0, name := "duplicate", arguments := [], bindings := []) do
    return { value := 7, valid := true, value := 9 : Pair }

/-- error: missing source field valid -/
#guard_msgs in
example : Function [] Pair :=
  function (id := 0, name := "missing", arguments := [], bindings := []) do
    return { value := 7 : Pair }

/-- error: unknown source field in record construction -/
#guard_msgs in
example : Function [] Pair :=
  function (id := 0, name := "unknown", arguments := [], bindings := []) do
    return { value := 7, valid := true, extra := 9 : Pair }

private def readPair (pair : Var Pair) : Function [Pair] I32 :=
  function (id := 2, name := "readPair", arguments := [pair := pair.id], bindings := []) do
    (pair).value += 1
    return (pair).value

example (pair : Var Pair) : (readPair pair).core.body = some
    (.sequence (.expression (.assign .add (.field (.local pair.id) 0) (.value (.signed .i32 1))))
      (.returnValue (some (.field (.local pair.id) 0)))) := rfl

private inductive EmptyRecord where | mk
attribute [lanius_type record 1] EmptyRecord


private def buildEmpty : Function [] EmptyRecord :=
  function (id := 1, name := "buildEmpty", arguments := [], bindings := []) do
    return { : EmptyRecord }

example : buildEmpty.core.body = some (.returnValue (some (.structValue 1 []))) := rfl

-- Applied labels and aliases use constructor binders, including Lean keywords.
private inductive Box (α : Type) where | mk («match» : Bool) (value : α)
attribute [lanius_type record 2] Box
private abbrev BoxAlias := Box

private def readBox [Code α] : Function [BoxAlias α] α :=
  function (id := 3, name := "readBox", arguments := [box := 7], bindings := []) do
    if (box).«match» then
      return (box).value
    else
      return (box).value

example [Code α] : (readBox (α := α)).core.body = some
    (.ifThenElse (.field (.local 7) 0)
      (.returnValue (some (.field (.local 7) 1)))
      (.returnValue (some (.field (.local 7) 1)))) := rfl

-- Aliases and applied constructor labels remain usable when order changes.
private def buildBox : Function [] (BoxAlias Pair) :=
  function (id := 5, name := "buildBox", arguments := [], bindings := []) do
    return { value := { valid := true, value := 7 : Pair }, «match» := false : BoxAlias Pair }
example : buildBox.core.body = some (.returnValue (some
    (.structValue 2 [.value (.boolean false),
      .structValue 0 [.value (.signed .i32 7), .value (.boolean true)]]))) := rfl

private inductive Numbers where | mk (left : I32) (right : I32)
attribute [lanius_type record 5] Numbers

-- Arbitrary callees may have effects. Initializer evaluation follows the
-- declaration order chosen by Lanius lowering, not this written permutation.
private def reorderedCalls (left right : Function [] I32) : Function [] Numbers :=
  function (id := 6, name := "reorderedCalls", arguments := [], bindings := []) do
    return { right := right (), left := left () : Numbers }
example (left right : Function [] I32) : (reorderedCalls left right).core.body = some
    (.returnValue (some (.structValue 5 [.call left.core.id [], .call right.core.id []]))) := rfl

mutual
  private inductive Link where | next (branch : Branch) | stop
  private inductive Branch where | mk (links : Slice Link)
end
attribute [lanius_type enum 3] Link
attribute [lanius_type record 4] Branch

private def recursiveLabel : Function [Link] Link :=
  function (id := 4, name := "recursiveLabel", arguments := [link := 1], bindings := [2]) do
    return match link with
      | .next branch => (branch).links[0]
      | .stop => (.stop : Link)

example : recursiveLabel.core.body = some (.returnValue (some (.matchValue (.local 1)
    [(.enumVariant 3 0 [.bind 2], .index (.field (.local 2) 0) (.value (.signed .i32 0))),
     (.enumVariant 3 1 [], .enumValue 3 1 [])]))) := rfl
