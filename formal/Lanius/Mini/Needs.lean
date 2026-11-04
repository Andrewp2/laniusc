module

public import Lanius.Mini.LowerStmt
import all Lanius.Mini.Compiler.P.withBudget
import all Lanius.Mini.Compiler.P.needCapped
import all Lanius.Mini.Compiler.P.needLimit
import all Lanius.Mini.Compiler.P.needsAfter
import all Lanius.Mini.Compiler.P.funcNeeds

/-! # Programs that need no frame memory

When no function takes a block of frame memory (`frameBlock`, each array it
passes as a slice), every function's need (`SrcProgram.need`) is 0: each
round of `needsAfter` from needs that are all 0 gives needs that are all 0.
The top theorems' premise on frame memory (TRUSTED_BASE "Frame room") then
holds for any heap. -/

public section

namespace Lanius.Mini

/-- Needs that are 0 at every index. -/
def Zeros (needs : List Nat) : Prop := ∀ i, needs.getD i 0 = 0

theorem zeros_nil : Zeros [] := fun _ => rfl

mutual
  theorem SrcEff.calleeNeed_zeros {needs : List Nat} (z : Zeros needs) (e : SrcEff) : e.calleeNeed needs = 0 := by
    match e with
    | .ePure _ => simp only [SrcEff.calleeNeed]
    | .eCall callee args =>
      simp only [SrcEff.calleeNeed, z callee, effsCalleeNeed_zeros z args, Nat.max_self]
    | .eApply _ left right =>
      simp only [SrcEff.calleeNeed, SrcEff.calleeNeed_zeros z left, SrcEff.calleeNeed_zeros z right, Nat.max_self]
    | .eNeg operand => simp only [SrcEff.calleeNeed, SrcEff.calleeNeed_zeros z operand]
    | .eNot operand => simp only [SrcEff.calleeNeed, SrcEff.calleeNeed_zeros z operand]
    | .eCast _ operand => simp only [SrcEff.calleeNeed, SrcEff.calleeNeed_zeros z operand]
    | .eIndex _ index => simp only [SrcEff.calleeNeed, SrcEff.calleeNeed_zeros z index]
    | .eStruct _ fields => simp only [SrcEff.calleeNeed, effsCalleeNeed_zeros z fields]
    | .eVariant _ _ payload => simp only [SrcEff.calleeNeed, effsCalleeNeed_zeros z payload]
    | .eMatch scrutinee _ _ _ values =>
      simp only [SrcEff.calleeNeed, SrcEff.calleeNeed_zeros z scrutinee, effsCalleeNeed_zeros z values, Nat.max_self]
    | .eDivide _ left right =>
      simp only [SrcEff.calleeNeed, SrcEff.calleeNeed_zeros z left, SrcEff.calleeNeed_zeros z right, Nat.max_self]
    | .eStride _ => simp only [SrcEff.calleeNeed]
    | .arraySlice _ _ => simp only [SrcEff.calleeNeed]
    | .eIf condition _ a b =>
      simp only [SrcEff.calleeNeed, SrcEff.calleeNeed_zeros z condition, SrcEff.calleeNeed_zeros z a,
        SrcEff.calleeNeed_zeros z b, Nat.max_self]
    | .eLet _ _ value _ body =>
      simp only [SrcEff.calleeNeed, SrcEff.calleeNeed_zeros z value, SrcEff.calleeNeed_zeros z body, Nat.max_self]
    | .eLen _ => simp only [SrcEff.calleeNeed]
    | .eStr _ _ => simp only [SrcEff.calleeNeed]
    | .eBorrow _ x => simp only [SrcEff.calleeNeed, SrcEff.calleeNeed_zeros z x]
    | .eDeref _ x => simp only [SrcEff.calleeNeed, SrcEff.calleeNeed_zeros z x]
    | .eField x _ => simp only [SrcEff.calleeNeed, SrcEff.calleeNeed_zeros z x]
    | .eAt x i =>
      simp only [SrcEff.calleeNeed, SrcEff.calleeNeed_zeros z x, SrcEff.calleeNeed_zeros z i, Nat.max_self]
  termination_by structural e

  theorem effsCalleeNeed_zeros {needs : List Nat} (z : Zeros needs) (es : List SrcEff) : effsCalleeNeed es needs = 0 := by
    match es with
    | [] => simp only [effsCalleeNeed]
    | e :: rest =>
      simp only [effsCalleeNeed, SrcEff.calleeNeed_zeros z e, effsCalleeNeed_zeros z rest, Nat.max_self]
  termination_by structural es
end

theorem SrcStmt.calleeNeed_zeros {needs : List Nat} (z : Zeros needs) (s : SrcStmt) : s.calleeNeed needs = 0 := by
  induction s <;>
    simp_all only [SrcStmt.calleeNeed, SrcEff.calleeNeed_zeros z, z _, Nat.max_self]

theorem needRoundAt_zeros {prev : List Nat} (z : Zeros prev) :
    ∀ {funcs : List SrcFunc}, (∀ f ∈ funcs, frameBlock f = 0) → ∀ {mine : List Nat}, Zeros mine →
      Zeros (needRoundAt funcs prev mine)
  | [], _, _, _ => zeros_nil
  | f :: rest, blocks, mine, zm => by
    intro i
    cases i with
    | zero =>
      simp only [needRoundAt, List.getD_cons_zero, blocks f List.mem_cons_self, SrcStmt.calleeNeed_zeros z,
        Nat.add_zero, zm 0, needCapped, needLimit]
      decide
    | succ i =>
      simp only [needRoundAt, List.getD_cons_succ]
      exact needRoundAt_zeros z (fun g mem => blocks g (List.mem_cons_of_mem _ mem))
        (fun j => by
          cases mine with
          | nil => rfl
          | cons m ms => simpa [restNeeds] using zm (j + 1)) i

theorem needRound_zeros {funcs : List SrcFunc} (blocks : ∀ f ∈ funcs, frameBlock f = 0) {prev : List Nat}
    (z : Zeros prev) : Zeros (needRound funcs prev) :=
  needRoundAt_zeros z blocks z

theorem needsAfter_zeros {funcs : List SrcFunc} (blocks : ∀ f ∈ funcs, frameBlock f = 0) :
    ∀ (rounds : Nat) {prev : List Nat}, Zeros prev → Zeros (needsAfter funcs prev rounds) := by
  intro rounds
  induction rounds with
  | zero => intro prev z; rw [needsAfter]; exact needRound_zeros blocks z
  | succ k ih =>
    intro prev z
    rw [needsAfter]
    simp only [Nat.add_one_ne_zero, ↓reduceIte, Nat.add_sub_cancel]
    split
    · exact needRound_zeros blocks z
    · exact ih (needRound_zeros blocks z)

/-- A program none of whose functions takes a block of frame memory needs
none at any function. -/
theorem SrcProgram.need_zero {sp : SrcProgram} (blocks : ∀ f ∈ sp.funcs, frameBlock f = 0) (i : Nat) :
    sp.need i = 0 :=
  needsAfter_zeros blocks _ zeros_nil i

/-- `need_zero` from a check of every function's block. -/
theorem SrcProgram.need_zero_of_all {sp : SrcProgram} (blocks : (sp.funcs.all fun f => frameBlock f == 0) = true)
    (i : Nat) : sp.need i = 0 :=
  SrcProgram.need_zero (fun f mem => by
    have := List.all_eq_true.mp blocks f mem
    simpa using this) i

/-- A list's check from its checks in pieces of `c`, the `k`th piece
`(l.drop (k * c)).take c`, so that a kernel check of a long list can run piece
by piece. -/
theorem all_of_pieces {α : Type} (p : α → Bool) (c : Nat) :
    ∀ (n : Nat) (l : List α), l.length ≤ n * c → (∀ k < n, ((l.drop (k * c)).take c).all p = true) →
      l.all p = true
  | 0, l, len, _ => by
    have : l = [] := List.eq_nil_of_length_eq_zero (by simpa using len)
    subst this; rfl
  | n + 1, l, len, pieces => by
    rw [← List.take_append_drop c l, List.all_append, Bool.and_eq_true]
    refine ⟨by simpa using pieces 0 (by omega), all_of_pieces p c n (l.drop c) ?_ fun k lt => ?_⟩
    · simp only [List.length_drop]
      rw [Nat.add_mul] at len
      omega
    · have := pieces (k + 1) (by omega)
      rwa [List.drop_drop, show c + k * c = (k + 1) * c by rw [Nat.add_mul]; omega]

end Lanius.Mini
