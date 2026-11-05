module

public import Lanius.Faithful.GenB.SelfBModel5
public import Lanius.Faithful.SelfPre.HB
public import Lanius.Faithful.SelfPre.TS
public import Lanius.Mini.Frontend.Types
public import Lanius.Mini.Frontend.P.weightLimit
public import Lanius.Mini.Frontend.P.whole

@[expose] public section

open Lanius.Mini
open Lanius.Faithful.Budget
open Lanius.Faithful.SelfBudget
open Lanius.Faithful.SelfPre

/-- `compile_source`'s precondition at height `M` (`hb p ≤ M`, `M + b ≤ 2 ^ 62`,
the M-form of the generated pre lemmas) for a program whose types have at most
`2 ^ 22` slots (`ts`) and whose functions' lets need at most `2 ^ 55` slots
(`SrcStmt.depth`). Replaces `PreCompileSourceV2`, which is probably false at
any budget. Why it holds, by kind of number:
- Lengths, and values built at cost, are at most `M` plus the cost so far, as
  in the M-form.
- Type sizes, field offsets and `k * size` element offsets are at most
  `2 ^ 22`.
- A function's slot numbers (locals, `next`, frame sizes, temporaries) are at
  most its depth plus its temporaries, below `2 ^ 56`. `compile_func` then
  rejects a frame over `frame_limit`.
- Sums over the whole program (`layout`, `link_onto`, the image length) are
  checked against `image_limit` as they add up (`room_after`, SEMANTIC_DECISIONS
  "The image limit checked as the sizes add up"), so they stay below `2 ^ 31`.
- A function's `code_size` and its pc offsets are sums over instructions the
  compile allocated, so they are below a few bytes per unit of the budget.
  This is the one budget-bound part (PreCompileSourceV2/NOTES.md, 11-03). -/
def Lanius.Open.PreCompileSourceV3 : Prop :=
  ∀ (p : Lanius.Mini.SrcProgram) (n b M : Nat), ts p ≤ Lanius.Mini.weightLimit →
    (∀ f ∈ p.funcs, Lanius.Mini.SrcStmt.depth f.body ≤ 2 ^ 55) →
    hb p ≤ M → M + b ≤ 2 ^ 62 → Pre_compile_source n p b
