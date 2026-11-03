import Lanius.Faithful.GenB.SelfBModel5
import Lanius.Mini.Compiler

open Lanius.Mini
open Lanius.Faithful.Budget
open Lanius.Faithful.SelfBudget

/-- Every function the front end builds needs at most `2 ^ 40` slots for its
lets (`SrcStmt.depth`, the slots that lowering's `next` passes, `lower_body`'s
`depth`). Why it holds: the front end rejects a program whose lets need more
than `depth_limit()` (`2 ^ 40`) slots along a scope (`untyped_rejected`'s
`lim_funcs`, SEMANTIC_DECISIONS "The front end's implementation limits").
Replaces `FrontEndStmtDepth`, whose bound grows with the input: proving it
needs a simulation through monomorphization and match lowering, and
`PreCompileWords` only uses that the depth is far below `2 ^ 64`. -/
def Lanius.Open.FrontEndStmtDepthV2 : Prop :=
  ∀ (W : List (BitVec 32)) (p : Lanius.Mini.SrcProgram),
    Lanius.Mini.frontEndWords grammar W = some p →
    ∀ f ∈ p.funcs, Lanius.Mini.SrcStmt.depth f.body ≤ 2 ^ 40
