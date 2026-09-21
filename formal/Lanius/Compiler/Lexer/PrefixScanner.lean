import Lanius.Compiler.Lexer.Correct

namespace Lanius.Compiler.Lexer

open Lanius Lanius.Core Lanius.Semantics

structure PrefixLoopOracle (program : Program) (condition : Expr) (body : Stmt)
    (accept : Byte → Bool) (source : List Byte) where
  Inv : Nat → State → Prop
  outOfBounds : ∀ {cursor state}, Inv cursor state → ¬ cursor < source.length →
    ∃ threshold after, StableExpr threshold program state condition (.boolean false) after ∧
      Inv cursor after
  rejected : ∀ {cursor state} (inBounds : cursor < source.length), Inv cursor state →
    accept (source.get ⟨cursor, inBounds⟩) = false →
    ∃ threshold after, StableExpr threshold program state condition (.boolean false) after ∧
      Inv cursor after
  accepted : ∀ {cursor state} (inBounds : cursor < source.length), Inv cursor state →
    accept (source.get ⟨cursor, inBounds⟩) = true →
    ∃ conditionThreshold bodyThreshold conditionAfter bodyAfter,
      StableExpr conditionThreshold program state condition (.boolean true) conditionAfter ∧
      StableStmt bodyThreshold program conditionAfter body .next bodyAfter ∧ Inv (cursor + 1) bodyAfter

def acceptedPrefixCursor (accept : Byte → Bool) (source : List Byte)
    (cursor : Nat) : Nat :=
  cursor + (splitPrefix accept (source.drop cursor)).1.length

theorem acceptedPrefixCursor_outOfBounds
    (accept : Byte → Bool) (source : List Byte) (cursor : Nat)
    (outOfBounds : ¬ cursor < source.length) :
    acceptedPrefixCursor accept source cursor = cursor := by
  have bound : source.length ≤ cursor := Nat.le_of_not_gt outOfBounds
  simp [acceptedPrefixCursor, List.drop_eq_nil_of_le bound, splitPrefix]

theorem acceptedPrefixCursor_rejected
    (accept : Byte → Bool) (source : List Byte) (cursor : Nat)
    (inBounds : cursor < source.length)
    (rejected : accept (source.get ⟨cursor, inBounds⟩) = false) :
    acceptedPrefixCursor accept source cursor = cursor := by
  simp only [acceptedPrefixCursor, List.drop_eq_getElem_cons inBounds, splitPrefix]
  have acceptedAt : accept source[cursor] = false := by simpa using rejected
  simp [acceptedAt]

theorem acceptedPrefixCursor_accepted
    (accept : Byte → Bool) (source : List Byte) (cursor : Nat)
    (inBounds : cursor < source.length)
    (accepted : accept (source.get ⟨cursor, inBounds⟩) = true) :
    acceptedPrefixCursor accept source cursor =
      acceptedPrefixCursor accept source (cursor + 1) := by
  simp only [acceptedPrefixCursor, List.drop_eq_getElem_cons inBounds, splitPrefix]
  have acceptedAt : accept source[cursor] = true := by simpa using accepted
  simp [acceptedAt, Nat.add_assoc, Nat.add_comm]

theorem acceptedPrefixCursor_scanEnd
    (accept : Byte → Bool) (source : List Byte) (start : Nat) :
    acceptedPrefixCursor accept source (start + 1) = scanEnd accept source start 1 := by
  rfl

private theorem stopPrefixLoop
    (oracle : PrefixLoopOracle program condition body accept source)
    (conditionRun : StableExpr threshold program initialState condition (.boolean false) after)
    (nextInvariant : oracle.Inv initialCursor after)
    (cursorEq : acceptedPrefixCursor accept source initialCursor = initialCursor) :
    ∃ threshold finalState, StableStmt threshold program initialState (.whileLoop condition body)
      .next finalState ∧
      oracle.Inv (acceptedPrefixCursor accept source initialCursor) finalState := by
  refine ⟨threshold + 1, after, (fun fuel enough => by
    simpa [show fuel - 1 + 1 = fuel by omega] using
      execStmt_while_false (fuel := fuel - 1) program initialState condition body after
        (conditionRun (fuel - 1) (by omega))), ?_⟩
  simpa [cursorEq] using nextInvariant

theorem executePrefixLoop
    (oracle : PrefixLoopOracle program condition body accept source)
    (initialCursor : Nat) (initialState : State)
    (initialInvariant : oracle.Inv initialCursor initialState) :
    ∃ threshold finalState,
      StableStmt threshold program initialState
        (.whileLoop condition body) .next finalState ∧
      oracle.Inv (acceptedPrefixCursor accept source initialCursor) finalState := by
  let rec loop (cursor : Nat) (state : State) (invariant : oracle.Inv cursor state) :
      ∃ threshold finalState,
        StableStmt threshold program state (.whileLoop condition body) .next finalState ∧
        oracle.Inv (acceptedPrefixCursor accept source cursor) finalState := by
    by_cases inBounds : cursor < source.length
    · by_cases accepted : accept (source.get ⟨cursor, inBounds⟩) = true
      · obtain ⟨conditionThreshold, bodyThreshold, conditionAfter, bodyAfter,
          conditionRun, bodyRun, nextInvariant⟩ :=
          oracle.accepted inBounds invariant accepted
        obtain ⟨recursiveThreshold, finalState, recursiveRun, finalInvariant⟩ :=
          loop (cursor + 1) bodyAfter nextInvariant
        refine ⟨max (recursiveThreshold + 1)
          (max conditionThreshold bodyThreshold + 1), finalState, (fun fuel enough => by
            simpa [show fuel - 1 + 1 = fuel by omega] using
              execStmt_while_true_step (fuel := fuel - 1) program state condition body
                conditionAfter bodyAfter finalState .next .next
                (conditionRun (fuel - 1) (by omega)) (bodyRun (fuel - 1) (by omega))
                (Or.inl rfl) (recursiveRun (fuel - 1) (by omega))), ?_⟩
        simpa [acceptedPrefixCursor_accepted accept source cursor inBounds accepted]
          using finalInvariant
      · obtain ⟨conditionThreshold, conditionAfter, conditionRun, nextInvariant⟩ :=
          oracle.rejected inBounds invariant (Bool.eq_false_iff.mpr accepted)
        exact stopPrefixLoop oracle conditionRun nextInvariant
          (acceptedPrefixCursor_rejected accept source cursor inBounds
            (Bool.eq_false_iff.mpr accepted))
    · obtain ⟨conditionThreshold, conditionAfter, conditionRun, nextInvariant⟩ :=
        oracle.outOfBounds invariant inBounds
      exact stopPrefixLoop oracle conditionRun nextInvariant
        (acceptedPrefixCursor_outOfBounds accept source cursor inBounds)
    termination_by source.length - cursor
    decreasing_by omega
  exact loop initialCursor initialState initialInvariant

theorem executePrefixLoop_underCaller
    (caller : State)
    (oracle : PrefixLoopOracle program condition body accept source)
    (initialCursor : Nat) (initialState : State)
    (initialInvariant : oracle.Inv initialCursor initialState)
    (frameInvariant : ∀ {cursor state}, oracle.Inv cursor state →
      CallerFrame caller state) :
    ∃ threshold finalState,
      StableStmt threshold program initialState
        (.whileLoop condition body) .next finalState ∧
      oracle.Inv (acceptedPrefixCursor accept source initialCursor) finalState ∧
      CallerFrame caller finalState := by
  obtain ⟨threshold, finalState, execution, finalInvariant⟩ :=
    executePrefixLoop oracle initialCursor initialState initialInvariant
  exact ⟨threshold, finalState, execution, finalInvariant,
    frameInvariant finalInvariant⟩

theorem executePrefixLoop_scanEnd_underCaller
    (caller : State)
    (oracle : PrefixLoopOracle program condition body accept source)
    (start : Nat) (initialState : State)
    (initialInvariant : oracle.Inv (start + 1) initialState)
    (frameInvariant : ∀ {cursor state}, oracle.Inv cursor state →
      CallerFrame caller state) :
    ∃ threshold finalState,
      StableStmt threshold program initialState
        (.whileLoop condition body) .next finalState ∧
      oracle.Inv (scanEnd accept source start 1) finalState ∧
      CallerFrame caller finalState := by
  simpa only [acceptedPrefixCursor_scanEnd accept source start] using
    executePrefixLoop_underCaller caller oracle (start + 1) initialState
      initialInvariant frameInvariant

end Lanius.Compiler.Lexer
