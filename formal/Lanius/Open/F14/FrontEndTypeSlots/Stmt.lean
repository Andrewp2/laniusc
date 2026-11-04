module

public import Lanius.Faithful.GenB.SelfBModel5
public import Lanius.Faithful.SelfPre.TS
public import Lanius.Mini.Frontend

@[expose] public section

open Lanius.Mini
open Lanius.Faithful.Budget
open Lanius.Faithful.SelfBudget
open Lanius.Faithful.SelfPre

/-- Every type anywhere in the front end's output, and every type inside one,
has at most `weightLimit` (`2 ^ 22`) slots (`ts`, the largest `SrcType.size`).
Why it holds: the validator weighs types (SEMANTIC_DECISIONS "Type weights").
`arrayType` keeps an array type only within the limit (`weighed`), and
`types_weighed` rejects the program unless every struct and enum instance in
the type table is within it. A type's weight is at least its slot count, and
its parts weigh less than it does. Every other type has at most 2 slots: a
scalar, a slice, a pointer, `str`, and a view, whose length is that of a weighed
array type. The bound is on slot counts, not weights: a slice is never
weighed, and its weight grows with its element, while its size is 2. Needed
by `PreCompileSourceV3`: type sizes, field offsets and `k * size` element
offsets are at most `2 ^ 22` whatever the budget. -/
def Lanius.Open.FrontEndTypeSlots : Prop :=
  ∀ (W : List (BitVec 32)) (p : Lanius.Mini.SrcProgram),
    Lanius.Mini.frontEndWords grammar W = some p → ts p ≤ Lanius.Mini.weightLimit
