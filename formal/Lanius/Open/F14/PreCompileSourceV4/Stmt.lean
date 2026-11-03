import Lanius.Faithful.GenB.SelfBModel5
import Lanius.Faithful.SelfPre.HB
import Lanius.Faithful.SelfPre.TS
import Lanius.Mini.Frontend

open Lanius.Mini
open Lanius.Faithful.Budget
open Lanius.Faithful.SelfBudget
open Lanius.Faithful.SelfPre

/-- `compile_source`'s precondition at height `M` (`hb p ≤ M`, `M + b ≤ 2 ^ 62`,
the M-form of the generated pre lemmas) for a program whose types have at most
`2 ^ 22` slots (`ts`), whose functions' lets need at most `2 ^ 55` slots
(`SrcStmt.depth`) and whose functions' parameters take at most `2 ^ 40` slots
(`paramsSize`). Replaces `PreCompileSourceV3`, which is probably false: without
the parameters' bound, `lower_func`'s `params_size` adds 2 ^ 43 parameters of
2 ^ 22 slots at a budget of about 2 ^ 44 (PreCompileSourceV3/NOTES.md, 11-03).
Why it holds, by kind of number:
- Lengths, and values built at cost, are at most `M` plus the cost so far, as
  in the M-form.
- Type sizes, field offsets and `k * size` element offsets are at most
  `2 ^ 22`; a struct's fields are within its size, which `ts` bounds.
- A function's slot numbers (parameters, locals, `next`, frame sizes) are at
  most its parameters' slots plus its depth, below `2 ^ 56`. Its temporaries
  are at most the steps that built them (`LowerFuncsTemps`, the optimizer
  keeping them, `OptimizeKeepsNumbers`), below `2 ^ 62`. `compile_func` then
  rejects a frame over `frame_limit`.
- Sums over the whole program (`layout`, `link_onto`, the image length) are
  checked against `image_limit` as they add up (`room_after`), so they stay
  below `2 ^ 31`.
- A function's code size and its pc offsets are at most 64 bytes per unit of
  its body's weight (`codeSize_le`), which `compile_func` checks against the
  image limit before it compiles the body, so they stay below `2 ^ 40`. -/
def Lanius.Open.PreCompileSourceV4 : Prop :=
  ∀ (p : Lanius.Mini.SrcProgram) (n b M : Nat), ts p ≤ Lanius.Mini.weightLimit →
    (∀ f ∈ p.funcs, Lanius.Mini.SrcStmt.depth f.body ≤ 2 ^ 55) →
    (∀ f ∈ p.funcs, Lanius.Mini.paramsSize f.params ≤ 2 ^ 40) →
    hb p ≤ M → M + b ≤ 2 ^ 62 → Pre_compile_source n p b
