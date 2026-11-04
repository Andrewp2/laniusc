module

public import Lanius.Faithful.GenB.SelfBModel5
public import Lanius.Faithful.SelfPre.HB
public import Lanius.Mini.Compiler

@[expose] public section

open Lanius.Mini
open Lanius.Faithful.Budget
open Lanius.Faithful.SelfBudget
open Lanius.Faithful.SelfPre

/-- Every function the front end builds from the words `W` needs at most
`2 ^ 23 * (W.length + 1)` slots for its lets (`SrcStmt.depth`, the slots that
lowering's `next` passes, `lower_body`'s `depth`). Why it holds: `depth` adds a
binding's type size only around the statements in its scope. It takes the max
over the two branches of an `if` and over a match arm's body and the arms
after it, so the per-variant copies of a wildcard arm and the instances of
monomorphization do not add up. Every binding on a scope path comes from a
binding in the source (a let, a match binder, a viewed array's two names),
which takes at least one word of the input, and its type has at most `2 ^ 22`
slots (`FrontEndTypeSlots`). A whole-program size bound is false, because
monomorphization copies bodies (PreCompileSourceV2/NOTES.md, 11-03). A
per-function one is false too, because wildcard arms are copied per variant
and nested. This statement bounds a sum along one scope path only. -/
def Lanius.Open.FrontEndStmtDepth : Prop :=
  ∀ (W : List (BitVec 32)) (p : Lanius.Mini.SrcProgram),
    Lanius.Mini.frontEndWords grammar W = some p →
    ∀ f ∈ p.funcs, Lanius.Mini.SrcStmt.depth f.body ≤ 2 ^ 23 * (W.length + 1)
