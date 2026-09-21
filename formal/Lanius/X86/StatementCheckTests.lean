import Lanius.X86.StatementCheck

namespace Lanius.X86.StatementCheckTests

open Lanius Lanius.Core Lanius.Semantics
open Lanius.X86
open Lanius.X86.Machine
open Lanius.X86.ExpressionCheck
open Lanius.X86.StatementCheck

private def two : BitVec 32 := BitVec.ofNat 32 2
private def three : BitVec 32 := BitVec.ofNat 32 3
private def four : BitVec 32 := BitVec.ofNat 32 4

private def literalTwo : Core.Expr := .value (.signed .i32 2)
private def literalThree : Core.Expr := .value (.signed .i32 3)
private def literalFour : Core.Expr := .value (.signed .i32 4)
private def addTwoThree : Core.Expr := .binary .add literalTwo literalThree
private def nestedAdd : Core.Expr := .binary .add addTwoThree literalFour

private def nestedBytes : List UInt8 :=
  immediateBytes .w32 ScalarValidator.resultRegister two 0 ++
    frameStoreBytes 0 ++
    immediateBytes .w32 ScalarValidator.resultRegister three 0 ++
    frameAluBytes 0 .add ++
    frameStoreBytes 1 ++
    immediateBytes .w32 ScalarValidator.resultRegister four 0 ++
    frameAluBytes 1 .add

private def emptyMachine : Machine.State := {
  registers := fun _ => 0
  rip := 0
  memory := fun _ => 0
  flags := 0
}
private def trueMachine : Machine.State :=
  { emptyMachine with registers := fun register => if register = 0 then 1 else 0 }

#eval (checkBody? nestedAdd nestedBytes).isSome
#eval (checkBody? nestedAdd (nestedBytes.set 0 0)).isNone

example : (checkBody? nestedAdd nestedBytes).isSome := by
  decide

example : (checkBody? nestedAdd (nestedBytes.set 0 0)).isNone := by
  decide

example : Result ({} : Program) ({} : Semantics.State)
    .skip .next ({} : Semantics.State) 0 0 emptyMachine emptyMachine := by
  exact checked_skip [] (by simp [Machine.CodeAt]) rfl

example : Result ({} : Program) ({} : Semantics.State)
    (.sequence .skip .skip) .next ({} : Semantics.State)
    0 0 emptyMachine emptyMachine := by
  exact checked_sequence_skip (checked_skip [] (by simp [Machine.CodeAt]) rfl)

private def literalBytes : List UInt8 :=
  immediateBytes .w32 ScalarValidator.resultRegister two 0

private def expressionStmt : Stmt := .expression literalTwo
private def expressionSequence : Stmt :=
  .sequence expressionStmt expressionStmt
private def expressionSequenceBytes : List UInt8 := literalBytes ++ literalBytes

private def nonconstantCondition : Core.Expr := .unary .logicalNot (.value (.boolean false))
private def nonconstantConditionBytes : List UInt8 :=
  immediateBytes .w32 ScalarValidator.resultRegister (0#32) 0 ++
    testBytes .w32 ScalarValidator.resultRegister ScalarValidator.resultRegister ++
    [15, 148, 192] ++ zeroExtendByteBytes ScalarValidator.resultRegister ScalarValidator.resultRegister
private def conditionalSkip : Stmt := .ifThenElse nonconstantCondition .skip .skip
private def conditionalSkipBytes : List UInt8 :=
  nonconstantConditionBytes ++ conditionalBytes [] []

#eval (check? conditionalSkip conditionalSkipBytes).isSome

example : (check? conditionalSkip conditionalSkipBytes).isSome := by
  decide

#eval (check? expressionSequence expressionSequenceBytes).isSome
#eval (check? (.returnValue (some literalTwo)) literalBytes).isNone

example : (check? expressionSequence expressionSequenceBytes).isSome := by
  decide

example : (check? expressionSequence (literalBytes.set 0 0)).isNone := by
  decide

example : (check? (.returnValue (some literalTwo)) literalBytes).isNone := by
  decide

example : ∃ checked : Supported expressionSequence expressionSequenceBytes,
    check? expressionSequence expressionSequenceBytes = some checked := by
  have isSome : (check? expressionSequence expressionSequenceBytes).isSome := by
    decide
  cases h : check? expressionSequence expressionSequenceBytes with
  | none => simp [h] at isSome
  | some checked => exact ⟨checked, rfl⟩

example
    {checked : Supported expressionSequence expressionSequenceBytes}
    (accepted : check? expressionSequence expressionSequenceBytes = some checked)
    {program : Program} {coreBefore : Semantics.State}
    (upper : Nat) (before : Machine.State) (remainder : List UInt8)
    (window : checked.shape.allocations ≤ upper)
    (invariant : FrameCodeInvariant before 0 upper
      (expressionSequenceBytes ++ remainder)) :
    Nonempty (Σ after : Machine.State,
      ExactResult (program := program) (coreBefore := coreBefore)
        (source := expressionSequence) (completion := .next)
        (coreAfter := coreBefore) (base := 0) (upper := upper)
        (before := before) (after := after)
        expressionSequenceBytes remainder) := by
  exact checked_result (checked := checked) accepted program coreBefore upper before remainder
    window invariant

/- The public sequential rule is deliberately independent of a separately
   supplied sequence execution: the two exact post-state results provide the
   Core stability needed to derive it. -/
example
    {program : Program} {coreBefore coreMiddle coreAfter : Semantics.State}
    {before middle after : Machine.State} {completion : Completion}
    (expressionResult : Result program coreBefore
      (.expression literalTwo) .next coreMiddle
      0 0 before middle)
    (returnResult : Result program coreMiddle
      (.returnValue (some literalThree)) completion coreAfter
      0 0 middle after)
    (tailAligned : expressionResult.remainder =
      returnResult.consumed ++ returnResult.remainder) :
    Result program coreBefore
      (.sequence (.expression literalTwo)
        (.returnValue (some literalThree))) completion coreAfter
      0 0 before after := by
  exact checked_sequence_next expressionResult returnResult tailAligned

example {suffix : List UInt8} (loaded : CodeAt trueMachine.memory 0 (conditionalBytes [] [] ++ suffix)) :
    ∃ path : ConditionalPrefixResult (thenBody := []) (elseBody := []) (suffix := suffix) trueMachine (BitVec.ofNat 32 1),
      path.takeThen = true ∧ path.selectedCode = jumpBytes 0 ++ suffix ∧ path.after.rip = trueMachine.rip + BitVec.ofNat 64 (conditionalPrefix []).length := by
  let path := conditional_prefix_steps (thenBody := []) (elseBody := []) (by decide) (by decide) loaded (BitVec.ofNat 32 1) (by simp [trueMachine, emptyMachine])
  refine ⟨path, by rw [path.choiceExact]; decide, ?_, ?_⟩
  · have choice : path.takeThen = true := by rw [path.choiceExact]; decide
    rw [path.selectedCodeExact, choice]
    simp
  · rw [path.afterExact]
    have cond : condition (logicalFlags (0#64) (1#32) false) 4 = false := by decide
    simp [trueMachine, emptyMachine, Machine.State.branch, Machine.State.test32, Machine.State.test, conditionalPrefix, testBytes, branchBytes, displacementBytes, X86.Register.value, X86.Register.fields, X86.Register.Rex.encode, cond]

example {suffix : List UInt8} (loaded : CodeAt emptyMachine.memory 0 (conditionalBytes [] [] ++ suffix)) :
    ∃ path : ConditionalPrefixResult (thenBody := []) (elseBody := []) (suffix := suffix) emptyMachine (BitVec.ofNat 32 0),
      path.takeThen = false ∧ path.selectedCode = suffix ∧
        path.after.rip = emptyMachine.rip + BitVec.ofNat 64 (conditionalPrefix []).length +
          (BitVec.ofNat 32 5).signExtend 64 := by
  let path := conditional_prefix_steps (thenBody := []) (elseBody := []) (by decide) (by decide) loaded (BitVec.ofNat 32 0) (by simp [emptyMachine])
  refine ⟨path, by rw [path.choiceExact]; decide, ?_, ?_⟩
  · have choice : path.takeThen = false := by rw [path.choiceExact]; decide
    rw [path.selectedCodeExact, choice]
    simp
  · rw [path.afterExact]
    have cond : condition (logicalFlags (0#64) (0#32) false) 4 = true := by decide
    simp [emptyMachine, Machine.State.branch, Machine.State.test32, Machine.State.test, conditionalPrefix, testBytes, branchBytes, displacementBytes, X86.Register.value, X86.Register.fields, X86.Register.Rex.encode, cond]

end Lanius.X86.StatementCheckTests
