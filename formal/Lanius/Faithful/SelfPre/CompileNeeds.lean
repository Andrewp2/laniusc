module

public import Lanius.Faithful.SelfPre.NB
public import Lanius.Mini.FrameRoom
import all Lanius.Mini.Compiler.P.withBudget
import all Lanius.Mini.Compiler.P.Lists_empty
import all Lanius.Mini.Compiler.P.funcNeeds
import all Lanius.Mini.Compiler.P.needCapped
import all Lanius.Mini.Compiler.P.needsAfter
import all Lanius.Mini.Compiler.P.needLimit

@[expose] public section

/-! # The functions' needs, for the compile side's pre lemmas (F14)

A function's need is its frame block (at most `2 ^ 31`, `frameBlock_le`) plus the
largest need of a function it calls, by the previous round; every round caps it
at `needLimit` (`2 ^ 40`, `needCapped`). So a round's input needs are at most the
limit (`nb prev ≤ 2 ^ 40`, `COMPILE_OVERRIDES` of `need_round_at`, `need_round`,
`needs_after`), the callee part of a sum is at most them (`val_SrcStmt_calleeNeed`),
and each round's result is again at most the limit. `Tactic.valueFacts` finds the
`val_` lemmas by name. -/

namespace Lanius.Faithful.SelfPre

open Lanius.Mini

theorem getD_le_nb : ∀ (l : List Nat) (i : Nat), l.getD i 0 ≤ nb l
  | [], i => by simp
  | a :: l, 0 => by simp only [List.getD_cons_zero, nb_cons]; show a ≤ max a (nb l); omega
  | a :: l, i + 1 => by
    have := getD_le_nb l i
    simp only [List.getD_cons_succ, nb_cons]; omega

-- the largest need of a callee: at most the largest need
mutual
theorem val_SrcEff_calleeNeed : ∀ (self : SrcEff) (needs : List Nat), SrcEff.calleeNeed self needs ≤ nb needs
  | .ePure e, needs => by
    simp only [SrcEff.calleeNeed]; omega
  | .eCall callee args, needs => by
    have := val_effsCalleeNeed args needs
    have := getD_le_nb needs callee
    simp only [SrcEff.calleeNeed]; omega
  | .eApply op left right, needs => by
    have := val_SrcEff_calleeNeed left needs
    have := val_SrcEff_calleeNeed right needs
    simp only [SrcEff.calleeNeed]; omega
  | .eNeg operand, needs => by
    have := val_SrcEff_calleeNeed operand needs
    simp only [SrcEff.calleeNeed]; omega
  | .eNot operand, needs => by
    have := val_SrcEff_calleeNeed operand needs
    simp only [SrcEff.calleeNeed]; omega
  | .eCast ty operand, needs => by
    have := val_SrcEff_calleeNeed operand needs
    simp only [SrcEff.calleeNeed]; omega
  | .eIndex slice index, needs => by
    have := val_SrcEff_calleeNeed index needs
    simp only [SrcEff.calleeNeed]; omega
  | .eStruct ty fields, needs => by
    have := val_effsCalleeNeed fields needs
    simp only [SrcEff.calleeNeed]; omega
  | .eVariant ty variant payload, needs => by
    have := val_effsCalleeNeed payload needs
    simp only [SrcEff.calleeNeed]; omega
  | .eMatch scrutinee ety ty binders values, needs => by
    have := val_SrcEff_calleeNeed scrutinee needs
    have := val_effsCalleeNeed values needs
    simp only [SrcEff.calleeNeed]; omega
  | .eDivide op left right, needs => by
    have := val_SrcEff_calleeNeed left needs
    have := val_SrcEff_calleeNeed right needs
    simp only [SrcEff.calleeNeed]; omega
  | .eStride slice, needs => by
    simp only [SrcEff.calleeNeed]; omega
  | .arraySlice element array, needs => by
    simp only [SrcEff.calleeNeed]; omega
  | .eIf condition ty thenValue elseValue, needs => by
    have := val_SrcEff_calleeNeed condition needs
    have := val_SrcEff_calleeNeed thenValue needs
    have := val_SrcEff_calleeNeed elseValue needs
    simp only [SrcEff.calleeNeed]; omega
  | .eLet id ty value rt body, needs => by
    have := val_SrcEff_calleeNeed value needs
    have := val_SrcEff_calleeNeed body needs
    simp only [SrcEff.calleeNeed]; omega
  | .eLen slice, needs => by
    simp only [SrcEff.calleeNeed]; omega
  | .eStr offset chars, needs => by
    simp only [SrcEff.calleeNeed]; omega
  | .eBorrow bty bplace, needs => by
    have := val_SrcEff_calleeNeed bplace needs
    simp only [SrcEff.calleeNeed]; omega
  | .eDeref dty dref, needs => by
    have := val_SrcEff_calleeNeed dref needs
    simp only [SrcEff.calleeNeed]; omega
  | .eField fbase fidx, needs => by
    have := val_SrcEff_calleeNeed fbase needs
    simp only [SrcEff.calleeNeed]; omega
  | .eAt abase aindex, needs => by
    have := val_SrcEff_calleeNeed abase needs
    have := val_SrcEff_calleeNeed aindex needs
    simp only [SrcEff.calleeNeed]; omega
termination_by structural self => self
theorem val_effsCalleeNeed : ∀ (es : List SrcEff) (needs : List Nat), effsCalleeNeed es needs ≤ nb needs
  | [], needs => by simp only [effsCalleeNeed]; omega
  | e :: rest, needs => by
    have := val_SrcEff_calleeNeed e needs
    have := val_effsCalleeNeed rest needs
    simp only [effsCalleeNeed]; omega
termination_by structural es => es
end

theorem val_SrcStmt_calleeNeed : ∀ (self : SrcStmt) (needs : List Nat), SrcStmt.calleeNeed self needs ≤ nb needs
  | .nop, needs => by
    simp only [SrcStmt.calleeNeed]; omega
  | .let id ty value body, needs => by
    have := val_SrcStmt_calleeNeed body needs
    simp only [SrcStmt.calleeNeed]; omega
  | .letStruct id ty fields body, needs => by
    have := val_SrcStmt_calleeNeed body needs
    simp only [SrcStmt.calleeNeed]; omega
  | .letCall id ty callee args body, needs => by
    have := val_SrcStmt_calleeNeed body needs
    have := getD_le_nb needs callee
    simp only [SrcStmt.calleeNeed]; omega
  | .letEnum id ty variant payload body, needs => by
    have := val_SrcStmt_calleeNeed body needs
    simp only [SrcStmt.calleeNeed]; omega
  | .letMatch id ty scrutinee enumId arms body, needs => by
    have := val_SrcStmt_calleeNeed body needs
    simp only [SrcStmt.calleeNeed]; omega
  | .set id value, needs => by
    simp only [SrcStmt.calleeNeed]; omega
  | .setField id index value, needs => by
    simp only [SrcStmt.calleeNeed]; omega
  | .setCall id callee args, needs => by
    have := getD_le_nb needs callee
    simp only [SrcStmt.calleeNeed]; omega
  | .then first second, needs => by
    have := val_SrcStmt_calleeNeed first needs
    have := val_SrcStmt_calleeNeed second needs
    simp only [SrcStmt.calleeNeed]; omega
  | .if condition thenBranch elseBranch, needs => by
    have := val_SrcStmt_calleeNeed thenBranch needs
    have := val_SrcStmt_calleeNeed elseBranch needs
    simp only [SrcStmt.calleeNeed]; omega
  | .while condition body, needs => by
    have := val_SrcStmt_calleeNeed body needs
    simp only [SrcStmt.calleeNeed]; omega
  | .return value, needs => by
    simp only [SrcStmt.calleeNeed]; omega
  | .letAlloc id size shift body, needs => by
    have := val_SrcStmt_calleeNeed body needs
    simp only [SrcStmt.calleeNeed]; omega
  | .letLoad id pointer offset body, needs => by
    have := val_SrcStmt_calleeNeed body needs
    simp only [SrcStmt.calleeNeed]; omega
  | .setByte pointer offset value, needs => by
    simp only [SrcStmt.calleeNeed]; omega
  | .free pointer size shift, needs => by
    simp only [SrcStmt.calleeNeed]; omega
  | .letSlice id element pointer length body, needs => by
    have := val_SrcStmt_calleeNeed body needs
    simp only [SrcStmt.calleeNeed]; omega
  | .letIndex id ty slice index body, needs => by
    have := val_SrcStmt_calleeNeed body needs
    simp only [SrcStmt.calleeNeed]; omega
  | .setIndex slice index value, needs => by
    simp only [SrcStmt.calleeNeed]; omega
  | .letEval id ty value body, needs => by
    have := val_SrcEff_calleeNeed value needs
    have := val_SrcStmt_calleeNeed body needs
    simp only [SrcStmt.calleeNeed]; omega
  | .setEval id value, needs => by
    have := val_SrcEff_calleeNeed value needs
    simp only [SrcStmt.calleeNeed]; omega
  | .ifEval condition thenBranch elseBranch, needs => by
    have := val_SrcEff_calleeNeed condition needs
    have := val_SrcStmt_calleeNeed thenBranch needs
    have := val_SrcStmt_calleeNeed elseBranch needs
    simp only [SrcStmt.calleeNeed]; omega
  | .whileEval condition body, needs => by
    have := val_SrcEff_calleeNeed condition needs
    have := val_SrcStmt_calleeNeed body needs
    simp only [SrcStmt.calleeNeed]; omega
  | .returnEval value, needs => by
    have := val_SrcEff_calleeNeed value needs
    simp only [SrcStmt.calleeNeed]; omega
  | .discard value, needs => by
    have := val_SrcEff_calleeNeed value needs
    simp only [SrcStmt.calleeNeed]; omega
  | .setIndexEval slice index value, needs => by
    have := val_SrcEff_calleeNeed index needs
    have := val_SrcEff_calleeNeed value needs
    simp only [SrcStmt.calleeNeed]; omega
  | .setFieldEval id field value, needs => by
    have := val_SrcEff_calleeNeed value needs
    simp only [SrcStmt.calleeNeed]; omega
  | .returnUnit, needs => by
    simp only [SrcStmt.calleeNeed]; omega
  | .assert condition, needs => by
    have := val_SrcEff_calleeNeed condition needs
    simp only [SrcStmt.calleeNeed]; omega
  | .break, needs => by
    simp only [SrcStmt.calleeNeed]; omega
  | .continue, needs => by
    simp only [SrcStmt.calleeNeed]; omega
  | .matchArm scrutinee enumId variant binds binder ty body rest, needs => by
    have := val_SrcStmt_calleeNeed body needs
    have := val_SrcStmt_calleeNeed rest needs
    simp only [SrcStmt.calleeNeed]; omega
  | .unreachable id ty, needs => by
    simp only [SrcStmt.calleeNeed]; omega
  | .letView id length fields pointer body, needs => by
    have := val_SrcStmt_calleeNeed body needs
    simp only [SrcStmt.calleeNeed]; omega
  | .letStr pointer chars body, needs => by
    have := val_SrcStmt_calleeNeed body needs
    simp only [SrcStmt.calleeNeed]; omega
  | .setPlace aplace avalue, needs => by
    have := val_SrcEff_calleeNeed aplace needs
    have := val_SrcEff_calleeNeed avalue needs
    simp only [SrcStmt.calleeNeed]; omega
  | .setPlaceOp aop aplace avalue, needs => by
    have := val_SrcEff_calleeNeed aplace needs
    have := val_SrcEff_calleeNeed avalue needs
    simp only [SrcStmt.calleeNeed]; omega
termination_by structural self => self

theorem val_frameBlock (f : SrcFunc) : frameBlock f ≤ 2147483648 := frameBlock_le f

theorem needCapped_le (old next : Nat) : needCapped old next ≤ 1099511627776 := by
  unfold needCapped needLimit
  by_cases h1 : 1099511627776 ≤ old
  · rw [if_pos h1]; exact Nat.le_refl _
  · rw [if_neg h1]
    by_cases h2 : 1099511627776 ≤ next
    · rw [if_pos h2]; exact Nat.le_refl _
    · rw [if_neg h2]; omega

theorem val_needRoundAt : ∀ (funcs : List SrcFunc) (prev mine : List Nat),
    nb (needRoundAt funcs prev mine) ≤ 1099511627776
  | [], prev, mine => by simp only [needRoundAt, nb_nil]; omega
  | f :: rest, prev, mine => by
    have := needCapped_le (mine.getD 0 0) (frameBlock f + SrcStmt.calleeNeed f.body prev)
    have := val_needRoundAt rest prev (restNeeds mine)
    simp only [needRoundAt, nb_cons]
    show max (needCapped (mine.getD 0 0) (frameBlock f + SrcStmt.calleeNeed f.body prev))
      (nb (needRoundAt rest prev (restNeeds mine))) ≤ _
    omega

theorem val_needRound (funcs : List SrcFunc) (prev : List Nat) : nb (needRound funcs prev) ≤ 1099511627776 :=
  val_needRoundAt funcs prev prev

theorem val_needsAfter (funcs : List SrcFunc) : ∀ (prev : List Nat) (rounds : Nat),
    nb (needsAfter funcs prev rounds) ≤ 1099511627776
  | prev, 0 => by rw [needsAfter]; simp only [if_true]; exact val_needRound funcs prev
  | prev, rounds + 1 => by
    rw [needsAfter]; simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel]
    split
    · exact val_needRound funcs prev
    · exact val_needsAfter funcs _ rounds

theorem val_funcNeeds (funcs : List SrcFunc) : nb (funcNeeds funcs) ≤ 1099511627776 :=
  val_needsAfter funcs [] funcs.length

end Lanius.Faithful.SelfPre
