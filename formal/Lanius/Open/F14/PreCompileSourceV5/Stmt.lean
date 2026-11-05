module

public import Lanius.Faithful.GenB.SelfBModel5
public import Lanius.Faithful.SelfPre.HB
public import Lanius.Faithful.SelfPre.NB
public import Lanius.Faithful.SelfPre.TS
public import Lanius.Faithful.SelfPre.EvalSlots
public import Lanius.Mini.Frontend.Types
public import Lanius.Mini.Frontend.P.weightLimit

@[expose] public section

open Lanius.Mini
open Lanius.Faithful.Budget
open Lanius.Faithful.SelfBudget
open Lanius.Faithful.SelfPre

/-- `compile_source`'s precondition at height `M`, as `PreCompileSourceV4` states it,
with two more premises V4 lacks (PreCompileSourceV4/NOTES.md, 11-04):
- the program's numbers are below `M` (`nb p ≤ M`): its ids, field indices,
  array lengths and string offsets reach parameters the pre lemmas bound by `M`,
  and `hb` does not count numbers;
- each function body's expressions nest at most `2 ^ 55` unchecked slot steps
  (`SrcStmt.slotNest`, SelfPre/EvalSlots). The evaluator starts an operator's right
  operand one slot past its left (`eApply`, `eDivide`) with no step of its own,
  and a borrow on the left costs nothing, so a right-nested chain
  `eApply op (eBorrow ..) (eApply op (eBorrow ..) ..)` reaches slot `slot + d`
  at no cost: without a bound on `d` the pre lemmas' `slot + 1 < 2 ^ 64` fails
  for a deep enough chain. The checked starts (`evalSlotLimit`, `eval_args`,
  `eval_let_body`, `eval_arm_in`) reset the count.
Why the slots hold: a statement's next slot plus its lets' slots is below
`2 ^ 56`, an expression's slot plus its nesting below `2 ^ 57`, a binding's last
slot below `2 ^ 57 + 2 ^ 56` (an arm's bindings view the scrutinee's payload in
place), and each lowering helper's slots below `2 ^ 58` plus a fixed step per level
of the call graph below it (`slot_tiers`, tools/pre_certs.py). -/
def Lanius.Open.PreCompileSourceV5 : Prop :=
  ∀ (p : Lanius.Mini.SrcProgram) (n b M : Nat), ts p ≤ Lanius.Mini.weightLimit →
    (∀ f ∈ p.funcs, Lanius.Mini.SrcStmt.depth f.body ≤ 2 ^ 55) →
    (∀ f ∈ p.funcs, Lanius.Mini.paramsSize f.params ≤ 2 ^ 40) →
    (∀ f ∈ p.funcs, Lanius.Faithful.SelfPre.SrcStmt.slotNest f.body ≤ 2 ^ 55) →
    hb p ≤ M → nb p ≤ M → M + b ≤ 2 ^ 62 → Pre_compile_source n p b
