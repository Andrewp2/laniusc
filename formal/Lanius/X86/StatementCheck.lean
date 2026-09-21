import Lean.Elab.Tactic.Omega
import Lanius.X86.ExpressionCheck
import Lanius.Semantics.Branch
import Lanius.Semantics.Rules

namespace Lanius.X86.StatementCheck

open Lanius Lanius.Core Lanius.Semantics
open Lanius.X86
open Lanius.X86.Machine
open Lanius.X86.ExpressionCheck

/- A statement certificate keeps the Core completion and the machine suffix in
   one object.  The statement index is the actual Core syntax node; unsupported
   statement forms therefore have no constructor/theorem in this boundary. -/
structure Result
    (program : Program) (coreBefore : Semantics.State) (source : Stmt)
    (completion : Completion) (coreAfter : Semantics.State)
    (base upper : Nat) (before after : Machine.State) where
  core : Executes program coreBefore source completion coreAfter
  coreStable : ∃ threshold, StableStmt threshold program coreBefore source completion coreAfter
  consumed : List UInt8
  remainder : List UInt8
  steps : Nat
  run : Steps steps before after
  loaded : CodeAt before.memory before.rip (consumed ++ remainder)
  remainderLoaded : CodeAt after.memory after.rip remainder
  ripAdvance : after.rip = before.rip + BitVec.ofNat 64 consumed.length
  frameStable : after.registers rbpRegister = before.registers rbpRegister
  preserveBelow : ∀ slot, slot < base →
    read32 after.memory (frameSlotAddress (before.registers rbpRegister) slot) =
      read32 before.memory (frameSlotAddress (before.registers rbpRegister) slot)
  /-- The suffix boundary also preserves return-address words outside the
      statement's frame window.  The premise is quantified over the caller's
      whole window; recursive expression certificates restrict it to the
      slots they may actually allocate. -/
  preserveRead64Outside : ∀ address,
    (∀ slot, base ≤ slot → slot < upper → ∀ i : Fin 8, ∀ j : Fin 4,
      address + BitVec.ofNat 64 i.val ≠
        frameSlotAddress (before.registers rbpRegister) slot +
          BitVec.ofNat 64 j.val) →
    read64 after.memory address = read64 before.memory address
  /-- Authenticated code remains intact across the statement's frame stores. -/
  preserveCodeAt : ∀ address bytes,
    CodeAt before.memory address bytes →
    (∀ index, index < bytes.length → ∀ slot, base ≤ slot → slot < upper →
      ∀ lane : Fin 4,
        address + BitVec.ofNat 64 index ≠
          frameSlotAddress (before.registers rbpRegister) slot +
            BitVec.ofNat 64 lane.val) →
    CodeAt after.memory address bytes

theorem Result.below
    {program : Program} {coreBefore : Semantics.State} {source : Stmt}
    {completion : Completion} {coreAfter : Semantics.State}
    {base upper : Nat} {before after : Machine.State}
    (result : Result program coreBefore source completion coreAfter
      base upper before after) (slot : Nat) (below : slot < base) :
    read32 after.memory (frameSlotAddress (before.registers rbpRegister) slot) =
      read32 before.memory (frameSlotAddress (before.registers rbpRegister) slot) :=
  result.preserveBelow slot below

/- Authenticated execution of the TEST/Jcc prefix.  This is deliberately a
   path result rather than a checker case: callers still supply the selected
   statement result and the suffix invariant. -/
structure ConditionalPrefixResult
    {thenBody elseBody suffix : List UInt8} (before : Machine.State)
    (result : BitVec 32) where
  takeThen : Bool
  after : Machine.State
  afterExact : after = (before.test32 0 0 (before.flags.getLsbD 4)
    (Machine.testBytes .w32 0 0).length).branch 4
      (BitVec.ofNat 32 (thenBody.length + 5)) 6
  steps : Steps 2 before after
  choiceExact : takeThen = !(result == 0)
  selectedRipExact : after.rip =
    if takeThen then before.rip + BitVec.ofNat 64 (Machine.conditionalPrefix thenBody).length
    else before.rip + BitVec.ofNat 64 (Machine.conditionalPrefix thenBody).length +
      (BitVec.ofNat 32 (thenBody.length + 5)).signExtend 64
  selectedCode : List UInt8
  selectedCodeExact : selectedCode =
    if takeThen then
      thenBody ++ Machine.jumpBytes (BitVec.ofNat 32 elseBody.length) ++ elseBody ++ suffix
    else elseBody ++ suffix
  selectedLoaded : CodeAt after.memory after.rip selectedCode

def conditional_prefix_steps
    {thenBody elseBody suffix : List UInt8} {before : Machine.State}
    (thenBound : thenBody.length + 5 < 2 ^ 31)
    (elseBound : elseBody.length < 2 ^ 31)
    (loaded : CodeAt before.memory before.rip
      (Machine.conditionalBytes thenBody elseBody ++ suffix))
    (result : BitVec 32)
    (resultExact : (before.registers 0).setWidth 32 = result) :
    ConditionalPrefixResult (thenBody := thenBody) (elseBody := elseBody)
      (suffix := suffix) before result := by
  have controlLoaded : CodeAt before.memory before.rip
      (Machine.conditionalPrefix thenBody) := by
    apply CodeAt.prefix (first := Machine.conditionalPrefix thenBody)
      (rest := thenBody ++ Machine.jumpBytes (BitVec.ofNat 32 elseBody.length) ++
        elseBody ++ suffix)
    simpa [Machine.conditionalBytes, List.append_assoc] using loaded
  have targets := Machine.conditional_code_targets_suffix thenBound elseBound loaded
  let tested := before.test32 0 0 (before.flags.getLsbD 4)
    (Machine.testBytes .w32 0 0).length
  have first : Step before tested := by
    apply test_step .w32 before tested 0 0
      (by simpa [Machine.conditionalPrefix] using controlLoaded.prefix)
      (before.flags.getLsbD 4)
    rfl
  have branchLoaded : CodeAt tested.memory tested.rip
      (Machine.branchBytes ⟨4, by decide⟩
        (BitVec.ofNat 32 (thenBody.length + 5))) := by
    simpa [tested, Machine.State.test32, Machine.State.test,
      Machine.conditionalPrefix] using controlLoaded.suffix
  have testedCondition : condition tested.flags 4 = (result == 0) := by
    simpa [tested, Machine.State.test32, Machine.State.test, resultExact,
      BitVec.and_self, logical32Flags] using
      Machine.test32_zero_condition before.flags result
        (before.flags.getLsbD 4)
  by_cases zero : result == 0
  · let after := tested.branch 4 (BitVec.ofNat 32 (thenBody.length + 5)) 6
    have branchTaken : condition tested.flags 4 = true := by
      rw [testedCondition, zero]
    have second := branch_step_rip tested after 4 _ branchLoaded
      branchTaken rfl
    refine {
      takeThen := false
      after := after
      afterExact := rfl
      steps := by simpa [first] using
        Steps.cons first (Steps.cons second.1 (Steps.refl after))
      choiceExact := by rw [zero]; rfl
      selectedRipExact := by
        simp
        simpa [tested, Machine.State.test32, Machine.State.test,
          Machine.conditionalPrefix, Machine.branchBytes,
          Machine.testBytes, Machine.displacementBytes, List.length_append,
          BitVec.ofNat_add, BitVec.add_assoc] using second.2
      selectedCode := elseBody ++ suffix
      selectedCodeExact := by simp
      selectedLoaded := by
        rw [show after.memory = before.memory by rfl, second.2]
        simpa [tested, Machine.State.test32, Machine.State.test,
          Machine.conditionalPrefix, Machine.branchBytes,
          Machine.testBytes, Machine.displacementBytes, List.length_append,
          BitVec.ofNat_add, BitVec.add_assoc] using targets.2 }
  · let after := tested.branch 4 (BitVec.ofNat 32 (thenBody.length + 5)) 6
    have branchNotTaken : condition tested.flags 4 = false := by
      have resultNotZero : (result == 0) = false :=
        Bool.eq_false_iff.mpr (by intro equal; exact zero equal)
      rw [testedCondition, resultNotZero]
    have second := branch_step_rip_not_taken tested after 4 _ branchLoaded
      branchNotTaken rfl
    refine {
      takeThen := true
      after := after
      afterExact := rfl
      steps := by simpa [first] using
        Steps.cons first (Steps.cons second.1 (Steps.refl after))
      choiceExact := by
        have resultNotZero : (result == 0) = false :=
          Bool.eq_false_iff.mpr (by intro equal; exact zero equal)
        rw [resultNotZero]
        rfl
      selectedRipExact := by
        simp
        simpa [tested, Machine.State.test32, Machine.State.test,
          Machine.conditionalPrefix, Machine.branchBytes,
          Machine.testBytes, Machine.displacementBytes, List.length_append,
          BitVec.ofNat_add, BitVec.add_assoc] using second.2
      selectedCode := thenBody ++ Machine.jumpBytes (BitVec.ofNat 32 elseBody.length) ++
        elseBody ++ suffix
      selectedCodeExact := by simp
      selectedLoaded := by
        rw [show after.memory = before.memory by rfl, second.2]
        simpa [tested, Machine.State.test32, Machine.State.test,
          Machine.conditionalPrefix, Machine.branchBytes,
          Machine.testBytes, Machine.displacementBytes, List.length_append,
          BitVec.ofNat_add, BitVec.add_assoc] using targets.1 }

structure ConditionalTrueTrace
    {program : Program} {coreBefore coreMiddle coreAfter : Semantics.State}
    {condition : Core.Expr} {thenBranch elseBranch : Stmt}
    {completion : Completion} {base upper : Nat}
    {before prefixBefore thenAfter final : Machine.State}
    {thenBranchBytes elseBranchBytes : List UInt8} (suffix : List UInt8) where
  conditionResult : Result program coreBefore (.expression condition) .next coreMiddle
    base upper before prefixBefore
  conditionStable : ∃ fuel, StableExpr fuel program coreBefore condition
    (.boolean true) coreMiddle
  control : ConditionalPrefixResult (thenBody := thenBranchBytes)
    (elseBody := elseBranchBytes) (suffix := suffix) prefixBefore (BitVec.ofNat 32 1)
  thenResult : Result program coreMiddle thenBranch completion coreAfter
    base upper control.after thenAfter
  conditionRemainderExact : conditionResult.remainder =
    Machine.conditionalBytes thenBranchBytes elseBranchBytes ++ suffix
  thenConsumedExact : thenResult.consumed = thenBranchBytes
  thenRemainderExact : thenResult.remainder =
    Machine.jumpBytes (BitVec.ofNat 32 elseBranchBytes.length) ++ elseBranchBytes ++ suffix
  elseBound : elseBranchBytes.length < 2 ^ 31
  jumpAfterExact : final = thenAfter.jump (BitVec.ofNat 32 elseBranchBytes.length)
    (Machine.jumpBytes (BitVec.ofNat 32 elseBranchBytes.length)).length

def checked_conditional_true
    {program : Program} {coreBefore coreMiddle coreAfter : Semantics.State}
    {condition : Core.Expr} {thenBranch elseBranch : Stmt}
    {completion : Completion} {base upper : Nat}
    {before prefixBefore thenAfter final : Machine.State}
    {thenBranchBytes elseBranchBytes suffix : List UInt8}
    (trace : ConditionalTrueTrace (program := program) (coreBefore := coreBefore)
      (coreMiddle := coreMiddle) (coreAfter := coreAfter) (condition := condition)
      (thenBranch := thenBranch) (elseBranch := elseBranch) (completion := completion)
      (base := base) (upper := upper) (before := before)
      (prefixBefore := prefixBefore) (thenAfter := thenAfter) (final := final)
      (thenBranchBytes := thenBranchBytes) (elseBranchBytes := elseBranchBytes) suffix) :
    Result program coreBefore (.ifThenElse condition thenBranch elseBranch)
      completion coreAfter base upper before final := by
  have jumpLoaded : CodeAt thenAfter.memory thenAfter.rip
      (Machine.jumpBytes (BitVec.ofNat 32 elseBranchBytes.length)) := by
    have loaded : CodeAt thenAfter.memory thenAfter.rip
        (Machine.jumpBytes (BitVec.ofNat 32 elseBranchBytes.length) ++
          elseBranchBytes ++ suffix) := by
      simpa [trace.thenRemainderExact] using trace.thenResult.remainderLoaded
    simpa [trace.thenRemainderExact] using loaded.prefix.prefix
  have jumpStep := Machine.jump_step thenAfter final
    (BitVec.ofNat 32 elseBranchBytes.length) jumpLoaded trace.jumpAfterExact
  have prefixFrame : trace.control.after.registers rbpRegister =
      before.registers rbpRegister := by
    rw [trace.control.afterExact]
    simp [Machine.State.branch, Machine.State.test32, Machine.State.test,
      trace.conditionResult.frameStable]
  have controlRbp : trace.control.after.registers rbpRegister =
      prefixBefore.registers rbpRegister := by
    rw [trace.control.afterExact]
    rfl
  have controlMemory : trace.control.after.memory = prefixBefore.memory := by
    rw [trace.control.afterExact]
    rfl
  have jumpDisp : (BitVec.ofNat 32 elseBranchBytes.length).signExtend 64 =
      BitVec.ofNat 64 elseBranchBytes.length := by
    apply BitVec.eq_of_toNat_eq
    have bound := trace.elseBound
    have hs : (BitVec.ofNat 32 elseBranchBytes.length).msb = false := by
      rw [BitVec.msb_eq_getMsbD_zero, BitVec.getMsbD_eq_getLsbD]
      simp only [show 0 < 32 by decide, decide_true, Bool.true_and,
        show 32 - 1 = 31 by decide]
      have hn : (BitVec.ofNat 32 elseBranchBytes.length).toNat < 2 ^ 31 := by
        simpa [BitVec.toNat_ofNat, Nat.mod_eq_of_lt (show elseBranchBytes.length < 2 ^ 32 by omega)] using bound
      exact Nat.testBit_lt_two_pow hn
    simp [BitVec.toNat_signExtend, hs,
      Nat.mod_eq_of_lt (show elseBranchBytes.length < 2 ^ 32 by omega),
      Nat.mod_eq_of_lt (show elseBranchBytes.length < 2 ^ 64 by omega)]
  refine {
    core := by
      obtain ⟨conditionFuel, conditionRun⟩ := trace.conditionStable
      obtain ⟨thenFuel, thenRun⟩ := trace.thenResult.coreStable
      refine ⟨max conditionFuel thenFuel + 1, ?_⟩
      exact execStmt_ifThenElse (max conditionFuel thenFuel) program coreBefore
        condition thenBranch elseBranch true completion coreMiddle coreAfter
        (conditionRun _ (by omega)) (thenRun _ (by omega))
    coreStable := by
      obtain ⟨conditionFuel, conditionRun⟩ := trace.conditionStable
      obtain ⟨thenFuel, thenRun⟩ := trace.thenResult.coreStable
      exact ⟨max conditionFuel thenFuel + 1,
        StableStmt.ifThenElse_true conditionRun thenRun⟩
    consumed := trace.conditionResult.consumed ++ Machine.conditionalPrefix thenBranchBytes ++
      trace.thenResult.consumed ++ Machine.jumpBytes (BitVec.ofNat 32 elseBranchBytes.length) ++
      elseBranchBytes
    remainder := suffix
    steps := trace.conditionResult.steps + (2 + (trace.thenResult.steps + 1))
    run := trace.conditionResult.run.trans
      (trace.control.steps.trans
        (trace.thenResult.run.trans (Steps.cons jumpStep (Steps.refl final))))
    loaded := by
      simpa [trace.conditionRemainderExact, trace.thenConsumedExact,
        trace.thenRemainderExact, Machine.conditionalBytes, List.append_assoc]
        using trace.conditionResult.loaded
    remainderLoaded := by
      have loaded : CodeAt thenAfter.memory thenAfter.rip
          (Machine.jumpBytes (BitVec.ofNat 32 elseBranchBytes.length) ++
            elseBranchBytes ++ suffix) := by
        simpa [trace.thenRemainderExact] using trace.thenResult.remainderLoaded
      have jumpTail := loaded.suffix
          (first := Machine.jumpBytes (BitVec.ofNat 32 elseBranchBytes.length))
      have finalLoaded := jumpTail.suffix (first := elseBranchBytes)
      rw [trace.jumpAfterExact]
      simpa [Machine.State.jump, Machine.jumpBytes, Machine.displacementBytes,
        List.length_append, BitVec.ofNat_add, BitVec.add_assoc, BitVec.add_comm,
        jumpDisp] using finalLoaded
    ripAdvance := by
      simp [trace.jumpAfterExact, Machine.State.jump, trace.thenResult.ripAdvance,
        trace.thenConsumedExact, trace.control.selectedRipExact,
        trace.control.choiceExact, trace.conditionResult.ripAdvance,
        Machine.conditionalPrefix, Machine.jumpBytes, Machine.displacementBytes,
        Machine.branchBytes, Machine.testBytes, List.length_append, List.length_cons,
        X86.Register.value, X86.Register.fields, X86.Register.Rex.encode,
        BitVec.ofNat_add, BitVec.add_comm, jumpDisp] <;> ac_rfl
    frameStable := by
      simpa [trace.jumpAfterExact, Machine.State.jump] using
        trace.thenResult.frameStable.trans prefixFrame
    preserveBelow := by
      intro slot below
      have thenBelow := trace.thenResult.preserveBelow slot below
      have conditionBelow := trace.conditionResult.preserveBelow slot below
      have thenBelow' := show read32 thenAfter.memory
          (frameSlotAddress (before.registers rbpRegister) slot) =
          read32 prefixBefore.memory (frameSlotAddress (before.registers rbpRegister) slot) by
        rw [controlMemory] at thenBelow
        rw [controlRbp] at thenBelow
        rw [trace.conditionResult.frameStable] at thenBelow
        exact thenBelow
      have jumpBelow : read32 final.memory
          (frameSlotAddress (before.registers rbpRegister) slot) =
          read32 thenAfter.memory (frameSlotAddress (before.registers rbpRegister) slot) := by
        rw [trace.jumpAfterExact]
        rfl
      calc
        read32 final.memory (frameSlotAddress (before.registers rbpRegister) slot) =
            read32 thenAfter.memory (frameSlotAddress (before.registers rbpRegister) slot) := jumpBelow
        _ = read32 prefixBefore.memory (frameSlotAddress (before.registers rbpRegister) slot) := thenBelow'
        _ = read32 before.memory (frameSlotAddress (before.registers rbpRegister) slot) := conditionBelow
    preserveRead64Outside := by
      intro address outside
      have thenRead := trace.thenResult.preserveRead64Outside address (by
        simpa [prefixFrame] using outside)
      have conditionRead := trace.conditionResult.preserveRead64Outside address outside
      have thenRead' : read64 thenAfter.memory address = read64 prefixBefore.memory address := by
        simpa [controlMemory] using thenRead
      simpa [trace.jumpAfterExact, Machine.State.jump] using thenRead'.trans conditionRead
    preserveCodeAt := by
      intro address bytes loaded outside
      have conditionCode := trace.conditionResult.preserveCodeAt address bytes loaded outside
      have conditionCode' : CodeAt trace.control.after.memory address bytes := by
        simpa [controlMemory] using conditionCode
      have thenCode := trace.thenResult.preserveCodeAt address bytes conditionCode' (by
        simpa [prefixFrame] using outside)
      simpa [trace.jumpAfterExact, Machine.State.jump] using thenCode }

structure ConditionalFalseTrace
    {program : Program} {coreBefore coreMiddle coreAfter : Semantics.State} {condition : Core.Expr}
    {thenBranch elseBranch : Stmt} {completion : Completion} {base upper : Nat}
    {before prefixBefore elseAfter : Machine.State}
    {thenBranchBytes elseBranchBytes : List UInt8} (suffix : List UInt8) where
  conditionResult : Result program coreBefore (.expression condition) .next coreMiddle base upper before prefixBefore
  conditionStable : ∃ fuel, StableExpr fuel program coreBefore condition (.boolean false) coreMiddle
  control : ConditionalPrefixResult (thenBody := thenBranchBytes) (elseBody := elseBranchBytes) (suffix := suffix) prefixBefore (BitVec.ofNat 32 0)
  elseResult : Result program coreMiddle elseBranch completion coreAfter base upper control.after elseAfter
  conditionRemainderExact : conditionResult.remainder = Machine.conditionalBytes thenBranchBytes elseBranchBytes ++ suffix
  thenBound : thenBranchBytes.length + 5 < 2 ^ 31
  elseConsumedExact : elseResult.consumed = elseBranchBytes
  elseRemainderExact : elseResult.remainder = suffix

def checked_conditional_false
    {program : Program} {coreBefore coreMiddle coreAfter : Semantics.State} {condition : Core.Expr}
    {thenBranch elseBranch : Stmt} {completion : Completion} {base upper : Nat}
    {before prefixBefore elseAfter : Machine.State} {thenBranchBytes elseBranchBytes suffix : List UInt8}
    (trace : ConditionalFalseTrace (program := program) (coreBefore := coreBefore) (coreMiddle := coreMiddle)
      (coreAfter := coreAfter) (condition := condition) (thenBranch := thenBranch) (elseBranch := elseBranch)
      (completion := completion) (base := base) (upper := upper) (before := before)
      (prefixBefore := prefixBefore) (elseAfter := elseAfter) (thenBranchBytes := thenBranchBytes)
      (elseBranchBytes := elseBranchBytes) suffix) :
    Result program coreBefore (.ifThenElse condition thenBranch elseBranch) completion coreAfter base upper before elseAfter := by
  have prefixFrame : trace.control.after.registers rbpRegister = before.registers rbpRegister := by
    rw [trace.control.afterExact]
    simp [Machine.State.branch, Machine.State.test32, Machine.State.test, trace.conditionResult.frameStable]
  have controlRbp : trace.control.after.registers rbpRegister = prefixBefore.registers rbpRegister := by rw [trace.control.afterExact]; rfl
  have controlMemory : trace.control.after.memory = prefixBefore.memory := by rw [trace.control.afterExact]; rfl
  have thenDisp : (BitVec.ofNat 32 (thenBranchBytes.length + 5)).signExtend 64 =
      BitVec.ofNat 64 (thenBranchBytes.length + 5) := by
    apply BitVec.eq_of_toNat_eq
    have bound : thenBranchBytes.length + 5 < 2 ^ 31 := trace.thenBound
    have hs : (BitVec.ofNat 32 (thenBranchBytes.length + 5)).msb = false := by
      rw [BitVec.msb_eq_getMsbD_zero, BitVec.getMsbD_eq_getLsbD]
      simp only [show 0 < 32 by decide, decide_true, Bool.true_and, show 32 - 1 = 31 by decide]
      have hn : (BitVec.ofNat 32 (thenBranchBytes.length + 5)).toNat < 2 ^ 31 := by simpa [BitVec.toNat_ofNat, Nat.mod_eq_of_lt (show thenBranchBytes.length + 5 < 2 ^ 32 by omega)] using bound
      exact Nat.testBit_lt_two_pow hn
    simp [BitVec.toNat_signExtend, hs, Nat.mod_eq_of_lt (show thenBranchBytes.length + 5 < 2 ^ 32 by omega), Nat.mod_eq_of_lt (show thenBranchBytes.length + 5 < 2 ^ 64 by omega)]
  have thenDisp' : (BitVec.ofNat 32 thenBranchBytes.length + (5#32)).signExtend 64 = BitVec.ofNat 64 (thenBranchBytes.length + 5) := by rw [← BitVec.ofNat_add]; exact thenDisp
  refine {
    core := by
      obtain ⟨conditionFuel, conditionRun⟩ := trace.conditionStable
      obtain ⟨elseFuel, elseRun⟩ := trace.elseResult.coreStable
      refine ⟨max conditionFuel elseFuel + 1, ?_⟩
      exact execStmt_ifThenElse (max conditionFuel elseFuel) program coreBefore
        condition thenBranch elseBranch false completion coreMiddle coreAfter
        (conditionRun _ (by omega)) (elseRun _ (by omega))
    coreStable := by
      obtain ⟨conditionFuel, conditionRun⟩ := trace.conditionStable
      obtain ⟨elseFuel, elseRun⟩ := trace.elseResult.coreStable
      exact ⟨max conditionFuel elseFuel + 1,
        StableStmt.ifThenElse_false conditionRun elseRun⟩
    consumed := trace.conditionResult.consumed ++ Machine.conditionalPrefix thenBranchBytes ++
      thenBranchBytes ++ Machine.jumpBytes (BitVec.ofNat 32 elseBranchBytes.length) ++
      trace.elseResult.consumed
    remainder := suffix
    steps := trace.conditionResult.steps + (2 + trace.elseResult.steps)
    run := trace.conditionResult.run.trans
      (trace.control.steps.trans trace.elseResult.run)
    loaded := by
      simpa [trace.conditionRemainderExact, trace.elseConsumedExact,
        trace.elseRemainderExact, Machine.conditionalBytes, List.append_assoc]
        using trace.conditionResult.loaded
    remainderLoaded := by
      simpa [trace.elseRemainderExact] using trace.elseResult.remainderLoaded
    ripAdvance := by
      simp [trace.control.selectedRipExact, trace.control.choiceExact,
        trace.elseResult.ripAdvance, trace.elseConsumedExact,
        trace.conditionResult.ripAdvance, Machine.conditionalPrefix,
        Machine.jumpBytes, Machine.displacementBytes, Machine.branchBytes,
        Machine.testBytes, List.length_append, List.length_cons,
        X86.Register.value, X86.Register.fields, X86.Register.Rex.encode,
        BitVec.ofNat_add, BitVec.add_comm, thenDisp'] <;> ac_rfl
    frameStable := by
      simpa [Machine.State.jump] using trace.elseResult.frameStable.trans prefixFrame
    preserveBelow := by
      intro slot below
      have elseBelow := trace.elseResult.preserveBelow slot below
      have conditionBelow := trace.conditionResult.preserveBelow slot below
      have elseBelow' := show read32 elseAfter.memory
          (frameSlotAddress (before.registers rbpRegister) slot) =
          read32 prefixBefore.memory (frameSlotAddress (before.registers rbpRegister) slot) by
        rw [controlMemory] at elseBelow
        rw [controlRbp] at elseBelow
        rw [trace.conditionResult.frameStable] at elseBelow
        exact elseBelow
      calc
        read32 elseAfter.memory (frameSlotAddress (before.registers rbpRegister) slot) =
            read32 prefixBefore.memory (frameSlotAddress (before.registers rbpRegister) slot) := elseBelow'
        _ = read32 before.memory (frameSlotAddress (before.registers rbpRegister) slot) := conditionBelow
    preserveRead64Outside := by
      intro address outside
      have elseRead := trace.elseResult.preserveRead64Outside address (by
        simpa [prefixFrame] using outside)
      have conditionRead := trace.conditionResult.preserveRead64Outside address outside
      have elseRead' : read64 elseAfter.memory address = read64 prefixBefore.memory address := by
        simpa [controlMemory] using elseRead
      exact elseRead'.trans conditionRead
    preserveCodeAt := by
      intro address bytes loaded outside
      have conditionCode := trace.conditionResult.preserveCodeAt address bytes loaded outside
      have conditionCode' : CodeAt trace.control.after.memory address bytes := by
        simpa [controlMemory] using conditionCode
      have elseCode := trace.elseResult.preserveCodeAt address bytes conditionCode' (by
        simpa [prefixFrame] using outside)
      simpa [controlMemory] using elseCode }

/- Fuel sufficient for an authenticated expression.  The expression checker
   already proves the machine relation; this size is only for the Core
   evaluator witness carried by a return statement. -/
def shapeFuel {source : Core.Expr} : Shape source → Nat
  | .lit _ _ _ => 1
  | .unary _ _ operand => shapeFuel operand + 1
  | .binary _ _ _ _ _ left right => max (shapeFuel left) (shapeFuel right) + 1

/- An expression certificate retains the exact checker output needed by the
   existing recursive machine theorem.  The statement checker below never
   turns a merely well-formed expression into a certificate by assertion. -/
structure ExpressionCertificate (source : Core.Expr) where
  body : List UInt8
  checked : { shape : ExpressionCheck.Shape source //
    body = shape.bodyBytes 0 ∧ ExpressionCheck.WellFormed shape }
  accepted : checkBody? source body = some checked

def expressionCertificate? (source : Core.Expr) : Option (ExpressionCertificate source) :=
  match ExpressionCheck.checkShape? source with
  | none => none
  | some ⟨shape, _⟩ =>
      let body := shape.bodyBytes 0
      match accepted : checkBody? source body with
      | none => none
      | some checked => some {
          body := body
          checked := checked
          accepted := accepted }

/- A syntax-directed statement shape is indexed by the actual Core statement.
   This boundary deliberately stops before terminal return lowering: return
   epilogues and RET are authenticated by the function layer. -/
inductive StatementShape : Stmt → Type
  | skip : StatementShape .skip
    | expr {source : Core.Expr}
      (expression : ExpressionCertificate source) :
      StatementShape (.expression source)
  | ifThenElse {condition : Core.Expr}
      (conditionCertificate : ExpressionCertificate condition) (conditionValue : Bool)
      (conditionExact : conditionCertificate.checked.1.coreValue? = some (.boolean conditionValue)) :
      StatementShape (.ifThenElse condition .skip .skip)
  | sequence {first second : Stmt}
      (left : StatementShape first) (right : StatementShape second) :
      StatementShape (.sequence first second)

def StatementShape.allocations {source : Stmt} (shape : StatementShape source) : Nat :=
  match shape with
  | .skip => 0
  | .expr expression => expression.checked.1.allocations
  | .ifThenElse conditionCertificate _ _ => conditionCertificate.checked.1.allocations
  | .sequence left right => max left.allocations right.allocations

def StatementShape.bodyBytes {source : Stmt} (shape : StatementShape source) :
    Nat → List UInt8 :=
  match shape with
  | .skip => fun _ => []
  | .expr expression => fun base => expression.checked.1.bodyBytes base
  | .ifThenElse conditionCertificate _ _ => fun base =>
      conditionCertificate.checked.1.bodyBytes base ++
        Machine.conditionalBytes [] []
  | .sequence left right => fun base => left.bodyBytes base ++ right.bodyBytes base

def StatementShape.consumedBytes {source : Stmt} (shape : StatementShape source) :
    Nat → List UInt8 :=
  match shape with
  | .skip => fun _ => []
  | .expr expression => fun base => expression.checked.1.bodyBytes base
  | .ifThenElse conditionCertificate _ _ => fun base =>
      conditionCertificate.checked.1.bodyBytes base ++
        Machine.conditionalBytes [] []
  | .sequence left right => fun base =>
      left.consumedBytes base ++ right.consumedBytes base

def StatementShape.remainderBytes {source : Stmt} (_shape : StatementShape source) :
    Nat → List UInt8 := fun _ => []

theorem StatementShape.bodyBytes_eq
    {source : Stmt} (shape : StatementShape source) (base : Nat) :
    shape.bodyBytes base =
      shape.consumedBytes base ++ shape.remainderBytes base := by
  induction shape with
  | skip => simp [StatementShape.bodyBytes, StatementShape.consumedBytes,
      StatementShape.remainderBytes]
  | expr => simp [StatementShape.bodyBytes, StatementShape.consumedBytes,
      StatementShape.remainderBytes]
  | ifThenElse conditionCertificate conditionValue conditionExact =>
      simp [StatementShape.bodyBytes, StatementShape.consumedBytes,
        StatementShape.remainderBytes, Machine.conditionalBytes,
        List.append_assoc]
  | sequence left right leftInduction rightInduction =>
      simp [StatementShape.bodyBytes, StatementShape.consumedBytes,
        StatementShape.remainderBytes, leftInduction, rightInduction]

structure Supported (source : Stmt) (emitted : List UInt8) where
  shape : StatementShape source
  bytesExact : emitted = shape.bodyBytes 0

def checkShape? : (source : Stmt) → Option (StatementShape source)
  | .skip => some .skip
  | .expression source =>
      match expressionCertificate? source with
      | none => none
      | some expression => some (.expr expression)
  | .sequence first second =>
      match checkShape? first, checkShape? second with
      | some left, some right => some (.sequence left right)
      | none, _ => none
      | _, none => none
  | .ifThenElse condition .skip .skip =>
      match expressionCertificate? condition with
      | some conditionCertificate =>
          match conditionExact : conditionCertificate.checked.1.coreValue? with
          | some (.boolean value) => some (.ifThenElse conditionCertificate value conditionExact)
          | _ => none
      | none => none
  | .ifThenElse _ _ _ => none
  | _ => none

def check? (source : Stmt) (emitted : List UInt8) : Option (Supported source emitted) :=
  match checkShape? source with
  | none => none
  | some shape =>
      if exact : emitted = shape.bodyBytes 0 then
        some { shape := shape, bytesExact := exact }
      else none

theorem shape_evaluates_at
    {source : Core.Expr} (shape : Shape source) (wellFormed : WellFormed shape)
    (fuel : Nat) (enough : shapeFuel shape ≤ fuel)
    (program : Program)
    (state : Semantics.State) :
    ∃ value, shape.coreValue? = some value ∧
      evalExpr fuel program state source = .done value state := by
  revert wellFormed fuel program state
  induction shape with
  | lit literal value exact =>
      intro wellFormed fuel enough program state
      refine ⟨value, ?_, ?_⟩
      simp [Shape.coreValue?, exact]
      have fuelPositive : 0 < fuel := by
        simp [shapeFuel] at enough
        omega
      simpa [shapeFuel,
        Nat.sub_add_cancel (Nat.one_le_iff_ne_zero.mpr (Nat.ne_of_gt fuelPositive))] using
        evalExpr_value (fuel := fuel - 1)
        program state value
  | unary coreOperation operand operandShape ihOperand =>
      intro wellFormed fuel enough program state
      cases wellFormed with
      | unary _ _ _ operandWitness operandValue result operandExact resultExact supported =>
          obtain ⟨operandResult, operandCoreExact, operandEvaluates⟩ :=
            ihOperand operandWitness (fuel - 1) (by
              simp [shapeFuel] at enough ⊢
              omega) program state
          have fuelPositive : 0 < fuel := by
            simp [shapeFuel] at enough
            omega
          have operandResultExact : operandResult = operandValue :=
            Option.some.inj (operandCoreExact.symm.trans operandExact)
          have unaryResultExact :
              evalUnaryValue program.target coreOperation operandResult = .ok result := by
            rw [operandResultExact]
            have targetIndependent :
                evalUnaryValue program.target coreOperation operandValue =
                  evalUnaryValue Target.x86_64 coreOperation operandValue := by
              cases coreOperation with
              | positive =>
                  cases operandValue <;> rfl
              | logicalNot =>
                  cases operandValue <;> rfl
              | negate =>
                  cases operandValue with
                  | signed type value =>
                      cases type with
                      | i8 => simp [evalUnaryValue, wrapSigned, signedModulus,
                          signedSignBit, SignedIntTy.bits]
                      | i16 => simp [evalUnaryValue, wrapSigned, signedModulus,
                          signedSignBit, SignedIntTy.bits]
                      | i32 => simp [evalUnaryValue, wrapSigned, signedModulus,
                          signedSignBit, SignedIntTy.bits]
                      | i64 => simp [evalUnaryValue, wrapSigned, signedModulus,
                          signedSignBit, SignedIntTy.bits]
                      | isize => cases supported
                  | unsigned type value => cases supported
                  | f32Bits bits => rfl
                  | f64Bits bits => rfl
                  | character value => rfl
                  | _ => cases supported
            rw [targetIndependent]
            exact resultExact
          refine ⟨result, ?_, ?_⟩
          · simp only [Shape.coreValue?, operandExact]
            rw [resultExact]
            rfl
          · have fuelExact : fuel = (fuel - 1) + 1 := by omega
            rw [fuelExact]
            simp [evalExpr, operandEvaluates, unaryResultExact]
  | binary coreOperation operation leftSource rightSource operationExact left right ihLeft ihRight =>
      intro wellFormed fuel enough program state
      cases wellFormed with
      | binary _ _ _ _ _ _ _ leftWitness rightWitness leftValue rightValue result
          leftExact rightExact resultExact =>
          obtain ⟨leftResult, leftCoreExact, leftEvaluates⟩ :=
            ihLeft leftWitness (fuel - 1) (by
              simp [shapeFuel] at enough ⊢
              omega) program state
          obtain ⟨rightResult, rightCoreExact, rightEvaluates⟩ :=
            ihRight rightWitness (fuel - 1) (by
              simp [shapeFuel] at enough ⊢
              omega) program state
          have fuelPositive : 0 < fuel := by
            simp [shapeFuel] at enough
            omega
          have leftResultExact : leftResult = .signed .i32 leftValue := by
            exact Option.some.inj (leftCoreExact.symm.trans leftExact)
          have rightResultExact : rightResult = .signed .i32 rightValue := by
            exact Option.some.inj (rightCoreExact.symm.trans rightExact)
          have operationResultExact :
              evalBinaryValue program.target coreOperation leftResult rightResult =
                .ok (.signed .i32 result) := by
            have targetIndependent :
                evalBinaryValue program.target coreOperation
                    (.signed .i32 leftValue) (.signed .i32 rightValue) =
                  evalBinaryValue Target.x86_64 coreOperation
                    (.signed .i32 leftValue) (.signed .i32 rightValue) := by
              cases coreOperation <;> rfl
            rw [leftResultExact, rightResultExact, targetIndependent]
            exact resultExact
          have binaryEvaluates := evalExpr_binary_done (fuel := fuel - 1)
            program state coreOperation leftSource rightSource
            leftResult rightResult (.signed .i32 result) state state
            leftEvaluates rightEvaluates (by
              cases coreOperation <;> simp_all [operation?]) operationResultExact
          refine ⟨.signed .i32 result, ?_, ?_⟩
          · simp [Shape.coreValue?, leftExact, rightExact, resultExact]
          · simpa [Nat.sub_add_cancel (Nat.one_le_iff_ne_zero.mpr (Nat.ne_of_gt fuelPositive))]
              using binaryEvaluates

theorem shape_return_executes
    {program : Program} {state : Semantics.State} {source : Core.Expr}
    (shape : Shape source) (wellFormed : WellFormed shape) :
    ∃ value, shape.coreValue? = some value ∧
      Executes program state (.returnValue (some source))
        (.returned (some value)) state := by
  have fuelEnough : shapeFuel shape ≤ shapeFuel shape := Nat.le_refl _
  obtain ⟨value, exact, evaluates⟩ :=
    shape_evaluates_at shape wellFormed (shapeFuel shape) fuelEnough program state
  refine ⟨value, exact, ?_⟩
  refine ⟨shapeFuel shape + 1, ?_⟩
  exact execStmt_return (shapeFuel shape) program state source value state evaluates

theorem shape_return_stable
    {program : Program} {state : Semantics.State} {source : Core.Expr}
    (shape : Shape source) (wellFormed : WellFormed shape) :
    ∃ value, shape.coreValue? = some value ∧
      StableStmt (shapeFuel shape + 1) program state
        (.returnValue (some source)) (.returned (some value)) state := by
  have fuelEnough : shapeFuel shape ≤ shapeFuel shape := Nat.le_refl _
  obtain ⟨value, exact, _⟩ :=
    shape_evaluates_at shape wellFormed (shapeFuel shape) fuelEnough program state
  refine ⟨value, exact, ?_⟩
  intro fuel enough
  have evaluates := shape_evaluates_at shape wellFormed (fuel - 1) (by omega)
    program state
  obtain ⟨value', exact', evaluates⟩ := evaluates
  have valueEq : value' = value := Option.some.inj (exact'.symm.trans exact)
  subst value'
  simpa [show fuel - 1 + 1 = fuel by omega] using
    execStmt_return (fuel - 1) program state source value state evaluates

theorem shape_expression_executes
    {program : Program} {state : Semantics.State} {source : Core.Expr}
    (shape : Shape source) (wellFormed : WellFormed shape) :
    ∃ value, shape.coreValue? = some value ∧
      Executes program state (.expression source) .next state := by
  have fuelEnough : shapeFuel shape ≤ shapeFuel shape := Nat.le_refl _
  obtain ⟨value, exact, evaluates⟩ :=
    shape_evaluates_at shape wellFormed (shapeFuel shape) fuelEnough program state
  refine ⟨value, exact, ?_⟩
  refine ⟨shapeFuel shape + 1, ?_⟩
  exact execStmt_expression (shapeFuel shape) program state source value state evaluates

theorem shape_expression_stable
    {program : Program} {state : Semantics.State} {source : Core.Expr}
    (shape : Shape source) (wellFormed : WellFormed shape) :
    ∃ value, shape.coreValue? = some value ∧
      StableStmt (shapeFuel shape + 1) program state
        (.expression source) .next state := by
  have fuelEnough : shapeFuel shape ≤ shapeFuel shape := Nat.le_refl _
  obtain ⟨value, exact, _⟩ :=
    shape_evaluates_at shape wellFormed (shapeFuel shape) fuelEnough program state
  refine ⟨value, exact, ?_⟩
  intro fuel enough
  obtain ⟨value', exact', evaluates⟩ := shape_evaluates_at shape wellFormed (fuel - 1) (by omega)
    program state
  have valueEq : value' = value := Option.some.inj (exact'.symm.trans exact)
  subst value'
  simpa [show fuel - 1 + 1 = fuel by omega] using
    execStmt_expression (fuel - 1) program state source value state evaluates

theorem shape_boolean_stable
    {program : Program} {state : Semantics.State} {source : Core.Expr}
    (shape : Shape source) (wellFormed : WellFormed shape) {value : Bool}
    (exact : shape.coreValue? = some (.boolean value)) :
    ∃ fuel, StableExpr fuel program state source (.boolean value) state := by
  refine ⟨shapeFuel shape + 1, ?_⟩
  intro fuel enough
  obtain ⟨value', exact', evaluates⟩ := shape_evaluates_at shape wellFormed
    fuel (by omega) program state
  have valueEq : value' = .boolean value := Option.some.inj (exact'.symm.trans exact)
  subst value'
  simpa using evaluates

structure ExactResult
    {program : Program} {coreBefore : Semantics.State} {source : Stmt}
    {completion : Completion} {coreAfter : Semantics.State}
    {base upper : Nat} {before after : Machine.State}
    (consumed remainder : List UInt8) where
  result : Result program coreBefore source completion coreAfter
    base upper before after
  consumedExact : result.consumed = consumed
  remainderExact : result.remainder = remainder

structure ExpressionExactResult
    {program : Program} {coreBefore : Semantics.State} {source : Core.Expr}
    {base upper : Nat} {before after : Machine.State}
    (expression : Shape source) (consumed remainder : List UInt8) where
  result : Result program coreBefore (.expression source) .next coreBefore
    base upper before after
  bits : BitVec 32
  resultRegister : after.registers ScalarValidator.resultRegister = bits.setWidth 64
  coreValue : Value
  coreValueExact : expression.coreValue? = some coreValue
  representation : LiteralReturn.RaxMatches coreValue bits
  consumedExact : result.consumed = consumed
  remainderExact : result.remainder = remainder

theorem checked_expression_exact
    {program : Program} {coreBefore : Semantics.State} {source : Core.Expr}
    {emitted : List UInt8}
    (checked : { shape : Shape source //
      emitted = shape.bodyBytes 0 ∧ WellFormed shape })
    (accepted : checkBody? source emitted = some checked)
    (base upper : Nat) (before : Machine.State) (remainder : List UInt8)
    (window : base + checked.1.allocations ≤ upper)
    (invariant : FrameCodeInvariant before base upper
      (checked.1.bodyBytes base ++ remainder)) :
    Nonempty (Σ after : Machine.State,
      ExpressionExactResult (program := program) (coreBefore := coreBefore)
        (source := source) (base := base) (upper := upper)
        (before := before) (after := after) checked.1
        (checked.1.bodyBytes base) remainder) := by
  obtain ⟨⟨after, recursive⟩⟩ := checked_recursive_result checked accepted
    base upper before remainder window invariant
  obtain ⟨_, _, coreStable⟩ :=
    shape_expression_stable checked.1 checked.2.2
  refine ⟨⟨after, {
    result := {
      core := ⟨shapeFuel checked.1 + 1, coreStable _ (Nat.le_refl _)⟩
      coreStable := ⟨shapeFuel checked.1 + 1, coreStable⟩
      consumed := recursive.result.consumed
      remainder := recursive.result.remainder
      steps := recursive.result.steps
      run := recursive.result.run
      loaded := recursive.result.loaded
      remainderLoaded := recursive.result.remainderLoaded
      ripAdvance := recursive.result.ripAdvance
      frameStable := recursive.result.frameStable
      preserveBelow := recursive.result.preserveBelow
      preserveRead64Outside := by
        intro address outside
        exact recursive.preserveRead64Outside address (by
          intro slot lowerBound upperBound i j
          exact outside slot lowerBound (by
            have shapeWindow := window
            omega) i j)
      preserveCodeAt := by
        intro address bytes loaded outside
        exact recursive.preserveCodeAt address bytes loaded (by
          intro index bound slot lowerBound upperBound lane
          exact outside index bound slot lowerBound (by omega) lane) }
    bits := recursive.result.bits
    resultRegister := recursive.result.resultRegister
    coreValue := recursive.result.coreValue
    coreValueExact := recursive.result.coreValueExact
    representation := recursive.result.representation
    consumedExact := recursive.consumedExact
    remainderExact := recursive.remainderExact
  }⟩⟩

def checked_skip
    {program : Program} {coreBefore : Semantics.State}
    {base upper : Nat} {before after : Machine.State}
    (remainder : List UInt8)
    (loaded : CodeAt before.memory before.rip remainder)
    (stateEq : after = before) :
    Result program coreBefore .skip .next coreBefore base upper before after := by
  subst after
  refine {
    core := by
      exact ⟨1, by simp [execStmt.eq_def]⟩
    coreStable := ⟨1, StableStmt.skip program coreBefore⟩
    consumed := []
    remainder := remainder
    steps := 0
    run := Steps.refl before
    loaded := by simpa using loaded
    remainderLoaded := by simpa using loaded
    ripAdvance := by simp
    frameStable := rfl
    preserveBelow := by
      intro slot _
      rfl
    preserveRead64Outside := by
      intro address _
      rfl
    preserveCodeAt := by
      intro address bytes loaded _
      exact loaded
  }

/- A next-completing first statement can be erased from the machine suffix when
   it is the Core skip.  This is the generic sequence/skip control rule. -/
def checked_sequence_skip
    {program : Program} {coreBefore : Semantics.State} {second : Stmt}
    {completion : Completion} {coreAfter : Semantics.State}
    {base upper : Nat} {before after : Machine.State}
    (secondResult : Result program coreBefore second completion coreAfter
      base upper before after) :
    Result program coreBefore (.sequence .skip second) completion coreAfter
      base upper before after := by
  refine {
    core := by
      obtain ⟨fuel, secondRun⟩ := secondResult.core
      refine ⟨fuel + 1, ?_⟩
      exact execStmt_sequence_next fuel program coreBefore .skip second
        completion coreBefore coreAfter (by
          cases fuel with
          | zero => simp [execStmt.eq_def] at secondRun
          | succ fuel => simp [execStmt.eq_def]) secondRun
    coreStable := by
      obtain ⟨secondFuel, secondContract⟩ := secondResult.coreStable
      exact ⟨max 1 secondFuel + 1,
        StableStmt.sequence_next (StableStmt.skip program coreBefore) secondContract⟩
    consumed := secondResult.consumed
    remainder := secondResult.remainder
    steps := secondResult.steps
    run := secondResult.run
    loaded := secondResult.loaded
    remainderLoaded := secondResult.remainderLoaded
    ripAdvance := secondResult.ripAdvance
    frameStable := secondResult.frameStable
    preserveBelow := secondResult.preserveBelow
    preserveRead64Outside := secondResult.preserveRead64Outside
    preserveCodeAt := secondResult.preserveCodeAt
  }

/- Generic sequential composition.  Each result retains a threshold-stable Core
   contract, so differing hidden fuels are synchronized by the existing
   `StableStmt.sequence_next` rule; the machine part is composed for any
   `.next` first result. -/
def checked_sequence_next
    {program : Program} {coreBefore coreMiddle coreAfter : Semantics.State}
    {first second : Stmt} {completion : Completion}
    {base upper : Nat} {before middle after : Machine.State}
    (firstResult : Result program coreBefore first .next coreMiddle
      base upper before middle)
    (secondResult : Result program coreMiddle second completion coreAfter
      base upper middle after)
    (tailAligned : firstResult.remainder =
      secondResult.consumed ++ secondResult.remainder) :
    Result program coreBefore (.sequence first second) completion coreAfter
      base upper before after := by
  have firstBelow : ∀ (slot : Nat), slot < base →
      read32 middle.memory (frameSlotAddress (before.registers rbpRegister) slot) =
        read32 before.memory (frameSlotAddress (before.registers rbpRegister) slot) :=
    firstResult.preserveBelow
  refine {
    core := by
      obtain ⟨firstFuel, firstContract⟩ := firstResult.coreStable
      obtain ⟨secondFuel, secondContract⟩ := secondResult.coreStable
      have sequenceContract := StableStmt.sequence_next firstContract secondContract
      exact ⟨max firstFuel secondFuel + 1,
        sequenceContract _ (Nat.le_refl _)⟩
    coreStable := by
      obtain ⟨firstFuel, firstContract⟩ := firstResult.coreStable
      obtain ⟨secondFuel, secondContract⟩ := secondResult.coreStable
      exact ⟨max firstFuel secondFuel + 1,
        StableStmt.sequence_next firstContract secondContract⟩
    consumed := firstResult.consumed ++ secondResult.consumed
    remainder := secondResult.remainder
    steps := firstResult.steps + secondResult.steps
    run := firstResult.run.trans secondResult.run
    loaded := by
      have remainderExact : firstResult.remainder =
          secondResult.consumed ++ secondResult.remainder := tailAligned
      simpa [remainderExact, List.append_assoc] using firstResult.loaded
    remainderLoaded := secondResult.remainderLoaded
    ripAdvance := by
      calc
        after.rip = middle.rip + BitVec.ofNat 64 secondResult.consumed.length :=
          secondResult.ripAdvance
        _ = (before.rip + BitVec.ofNat 64 firstResult.consumed.length) +
            BitVec.ofNat 64 secondResult.consumed.length := by
          rw [firstResult.ripAdvance]
        _ = before.rip + BitVec.ofNat 64
            (firstResult.consumed ++ secondResult.consumed).length := by
          simp [List.length_append, BitVec.ofNat_add, BitVec.add_assoc]
    frameStable := by
      exact secondResult.frameStable.trans firstResult.frameStable
    preserveBelow := by
      intro slot below
      have secondBelow := secondResult.preserveBelow slot below
      rw [firstResult.frameStable] at secondBelow
      exact secondBelow.trans (firstBelow slot below)
    preserveRead64Outside := by
      intro address outside
      have firstOutside := firstResult.preserveRead64Outside address outside
      have secondOutside := secondResult.preserveRead64Outside address (by
        intro slot lowerBound upperBound i j
        simpa [firstResult.frameStable] using
          outside slot lowerBound upperBound i j)
      exact secondOutside.trans firstOutside
    preserveCodeAt := by
      intro address bytes loaded outside
      have middleLoaded := firstResult.preserveCodeAt address bytes loaded outside
      exact secondResult.preserveCodeAt address bytes middleLoaded (by
        intro index bound slot lowerBound upperBound lane
        simpa [firstResult.frameStable] using
          outside index bound slot lowerBound upperBound lane)
  }

theorem conditional_prefix_invariant
    {before : Machine.State} {lower upper : Nat} {thenBody elseBody suffix : List UInt8}
    {result : BitVec 32}
    (invariant : FrameCodeInvariant before lower upper
      (Machine.conditionalBytes thenBody elseBody ++ suffix))
    (thenBound : thenBody.length + 5 < 2 ^ 31) (elseBound : elseBody.length < 2 ^ 31)
    (control : ConditionalPrefixResult (thenBody := thenBody) (elseBody := elseBody) (suffix := suffix) before result) :
    (if control.takeThen then
      FrameCodeInvariant control.after lower upper
        (thenBody ++ Machine.jumpBytes (BitVec.ofNat 32 elseBody.length) ++ elseBody ++ suffix)
    else FrameCodeInvariant control.after lower upper (elseBody ++ suffix)) := by
  have controlMemory : control.after.memory = before.memory := by rw [control.afterExact]; rfl
  have controlFrame : control.after.registers rbpRegister = before.registers rbpRegister := by
    rw [control.afterExact]; simp [Machine.State.branch, Machine.State.test32, Machine.State.test]
  cases choice : control.takeThen with
  | false =>
      let thenState : Machine.State := { control.after with rip := before.rip + BitVec.ofNat 64 (Machine.conditionalPrefix thenBody).length }
      have thenInvariant := FrameCodeInvariant.conditional_split_suffix
        (thenState := thenState) (elseState := control.after) invariant thenBound elseBound
        (by simpa [thenState, controlMemory]) controlMemory rfl
        (by simpa [choice] using control.selectedRipExact) (by simp [thenState, controlFrame]) controlFrame
      simpa [choice] using thenInvariant.2
  | true =>
      let elseState : Machine.State := { control.after with
        rip := before.rip + BitVec.ofNat 64 (Machine.conditionalPrefix thenBody).length +
          (BitVec.ofNat 32 (thenBody.length + 5)).signExtend 64 }
      have thenInvariant := FrameCodeInvariant.conditional_split_suffix
        (thenState := control.after) (elseState := elseState) invariant thenBound elseBound
        controlMemory (by simpa [elseState, controlMemory])
        (by simpa [choice] using control.selectedRipExact) rfl controlFrame
        (by simp [elseState, controlFrame])
      simpa [choice] using thenInvariant.1

/- Executable structural statement boundary for the currently proven fragment.
   Every accepted statement completes `.next`; terminal return lowering stays
   in the function layer where its epilogue and RET are part of the contract. -/
theorem checked_shape_result
    {source : Stmt} (shape : StatementShape source)
    (program : Program) (coreBefore : Semantics.State)
    (base upper : Nat) (before : Machine.State) (remainder : List UInt8)
    (window : base + shape.allocations ≤ upper)
    (invariant : FrameCodeInvariant before base upper
      (shape.bodyBytes base ++ remainder)) :
    Nonempty (Σ after : Machine.State,
      ExactResult (program := program) (coreBefore := coreBefore)
        (source := source) (completion := .next) (coreAfter := coreBefore)
        (base := base) (upper := upper) (before := before) (after := after)
        (shape.bodyBytes base) remainder) := by
  revert program coreBefore base upper before remainder
  induction shape with
  | skip =>
      intro program coreBefore base upper before remainder window invariant
      have loaded : CodeAt before.memory before.rip remainder := by
        simpa [StatementShape.bodyBytes] using invariant.loaded
      refine ⟨⟨before, {
        result := checked_skip remainder loaded rfl
        consumedExact := by rfl
        remainderExact := by rfl }⟩⟩
  | expr expression =>
      intro program coreBefore base upper before remainder window invariant
      obtain ⟨after, exact⟩ := checked_expression_exact
        (program := program) (coreBefore := coreBefore)
        expression.checked
        expression.accepted base upper before remainder window invariant
      refine ⟨⟨after, {
        result := exact.result
        consumedExact := by
          simpa [StatementShape.bodyBytes] using exact.consumedExact
        remainderExact := exact.remainderExact }⟩⟩
  | ifThenElse conditionCertificate conditionValue conditionExact =>
      intro program coreBefore base upper before remainder window invariant
      have conditionWindow : base + conditionCertificate.checked.1.allocations ≤ upper := by simp [StatementShape.allocations] at window ⊢; omega
      have controlInvariant : FrameCodeInvariant before base upper
          (conditionCertificate.checked.1.bodyBytes base ++ (Machine.conditionalBytes [] [] ++ remainder)) := by simpa [StatementShape.bodyBytes, Machine.conditionalBytes, List.append_assoc] using invariant
      obtain ⟨prefixBefore, conditionExactResult⟩ := checked_expression_exact (program := program) (coreBefore := coreBefore) conditionCertificate.checked conditionCertificate.accepted base upper before (Machine.conditionalBytes [] [] ++ remainder) conditionWindow controlInvariant
      have conditionRip : prefixBefore.rip = before.rip + BitVec.ofNat 64 (conditionCertificate.checked.1.bodyBytes base).length := by simpa [conditionExactResult.consumedExact] using conditionExactResult.result.ripAdvance
      have conditionalLoaded : CodeAt prefixBefore.memory prefixBefore.rip (Machine.conditionalBytes [] [] ++ remainder) := by simpa [conditionExactResult.remainderExact] using conditionExactResult.result.remainderLoaded
      have conditionPrefixInvariant := FrameCodeInvariant.suffix controlInvariant conditionalLoaded conditionRip conditionExactResult.result.frameStable
      have conditionValueExact : conditionExactResult.coreValue = .boolean conditionValue := Option.some.inj (conditionExactResult.coreValueExact.symm.trans conditionExact)
      have bitsExact : conditionExactResult.bits =
          BitVec.ofNat 32 (if conditionValue then 1 else 0) := by
        have representation := conditionExactResult.representation
        rw [conditionValueExact] at representation
        apply BitVec.eq_of_toInt_eq
        cases conditionValue <;>
          simp [LiteralReturn.RaxMatches] at representation ⊢ <;> exact representation
      have conditionRegister : (prefixBefore.registers ScalarValidator.resultRegister).setWidth 32 = BitVec.ofNat 32 (if conditionValue then 1 else 0) := by rw [conditionExactResult.resultRegister, bitsExact]; simp
      have conditionStable := shape_boolean_stable (program := program) (state := coreBefore)
        conditionCertificate.checked.1 conditionCertificate.checked.2.2 conditionExact
      cases conditionValue with
      | false =>
          let control := conditional_prefix_steps (thenBody := []) (elseBody := []) (by decide) (by decide) conditionalLoaded (BitVec.ofNat 32 0) (by simpa [ScalarValidator.resultRegister] using conditionRegister)
          have choice : control.takeThen = false := by rw [control.choiceExact]; decide
          have selectedInvariant := conditional_prefix_invariant conditionPrefixInvariant (by decide) (by decide) control
          have elseInvariant : FrameCodeInvariant control.after base upper remainder := by simpa [choice] using selectedInvariant
          let elseResult : Result program coreBefore .skip .next coreBefore
              base upper control.after control.after := checked_skip (program := program) (coreBefore := coreBefore) (base := base) (upper := upper) remainder elseInvariant.loaded rfl
          refine ⟨⟨control.after, {
            result := checked_conditional_false (thenBranch := .skip) (elseBranch := .skip) (trace := {
              conditionResult := conditionExactResult.result
              conditionStable := conditionStable
              control := control
              elseResult := elseResult
              conditionRemainderExact := by
                simpa [conditionExactResult.remainderExact] using
                  conditionExactResult.result.remainder
              thenBound := by decide
              elseConsumedExact := by rfl
              elseRemainderExact := by rfl })
            consumedExact := by
              simp [checked_conditional_false, checked_skip, elseResult, StatementShape.bodyBytes,
                conditionExactResult.consumedExact, Machine.conditionalBytes]
            remainderExact := by rfl }⟩⟩
      | true =>
          let control := conditional_prefix_steps (thenBody := []) (elseBody := []) (by decide) (by decide) conditionalLoaded (BitVec.ofNat 32 1) (by simpa [ScalarValidator.resultRegister] using conditionRegister)
          have choice : control.takeThen = true := by rw [control.choiceExact]; decide
          have selectedInvariant := conditional_prefix_invariant conditionPrefixInvariant (by decide) (by decide) control
          have thenInvariant : FrameCodeInvariant control.after base upper (Machine.jumpBytes (BitVec.ofNat 32 0) ++ remainder) := by simpa [choice] using selectedInvariant
          let thenResult : Result program coreBefore .skip .next coreBefore
              base upper control.after control.after := checked_skip (program := program) (coreBefore := coreBefore) (base := base) (upper := upper) (Machine.jumpBytes (BitVec.ofNat 32 0) ++ remainder) thenInvariant.loaded rfl
          let final := control.after.jump (BitVec.ofNat 32 0) (Machine.jumpBytes (BitVec.ofNat 32 0)).length
          refine ⟨⟨final, {
            result := checked_conditional_true (thenBranch := .skip) (elseBranch := .skip) (trace := {
              conditionResult := conditionExactResult.result
              conditionStable := conditionStable
              control := control
              thenResult := thenResult
              conditionRemainderExact := by
                simpa [conditionExactResult.remainderExact] using
                  conditionExactResult.result.remainder
              thenConsumedExact := by rfl
              thenRemainderExact := by rfl
              elseBound := by decide
              jumpAfterExact := by rfl })
            consumedExact := by
              simp [checked_conditional_true, checked_skip, thenResult, StatementShape.bodyBytes,
                conditionExactResult.consumedExact, Machine.conditionalBytes]
            remainderExact := by rfl }⟩⟩
  | sequence left right ihLeft ihRight =>
      intro program coreBefore base upper before remainder window invariant
      have leftWindow : base + left.allocations ≤ upper := by
        simp [StatementShape.allocations] at window ⊢
        omega
      have rightWindow : base + right.allocations ≤ upper := by
        simp [StatementShape.allocations] at window ⊢
        omega
      have leftInvariant : FrameCodeInvariant before base upper
          (left.bodyBytes base ++ (right.bodyBytes base ++ remainder)) := by
        simpa [StatementShape.bodyBytes, List.append_assoc] using invariant
      obtain ⟨middle, leftExact⟩ := ihLeft program coreBefore base upper before
        (right.bodyBytes base ++ remainder) leftWindow leftInvariant
      have middleInvariant : FrameCodeInvariant middle base upper
          (right.bodyBytes base ++ remainder) := by
        have leftRip : middle.rip = before.rip +
            BitVec.ofNat 64 (left.bodyBytes base).length := by
          simpa [leftExact.consumedExact] using leftExact.result.ripAdvance
        have remainderLoaded : CodeAt middle.memory middle.rip
            (right.bodyBytes base ++ remainder) := by
          simpa [leftExact.remainderExact] using leftExact.result.remainderLoaded
        have suffix' := FrameCodeInvariant.suffix leftInvariant
          remainderLoaded leftRip
          leftExact.result.frameStable
        exact suffix'
      obtain ⟨after, rightExact⟩ := ihRight program coreBefore base upper middle
        remainder rightWindow middleInvariant
      have tailAligned : leftExact.result.remainder =
          rightExact.result.consumed ++ rightExact.result.remainder := by
        rw [leftExact.remainderExact, rightExact.consumedExact,
          rightExact.remainderExact]
      let composed := checked_sequence_next leftExact.result rightExact.result
        tailAligned
      refine ⟨⟨after, {
        result := composed
        consumedExact := by
          change leftExact.result.consumed ++ rightExact.result.consumed =
            left.bodyBytes base ++ right.bodyBytes base
          rw [leftExact.consumedExact, rightExact.consumedExact]
        remainderExact := by
          change rightExact.result.remainder = remainder
          exact rightExact.remainderExact }⟩⟩

theorem checked_result
    {source : Stmt} {emitted : List UInt8} {checked : Supported source emitted}
    (_accepted : check? source emitted = some checked)
    (program : Program) (coreBefore : Semantics.State)
    (upper : Nat) (before : Machine.State) (remainder : List UInt8)
    (window : checked.shape.allocations ≤ upper)
    (invariant : FrameCodeInvariant before 0 upper (emitted ++ remainder)) :
    Nonempty (Σ after : Machine.State,
      ExactResult (program := program) (coreBefore := coreBefore)
        (source := source) (completion := .next) (coreAfter := coreBefore)
        (base := 0) (upper := upper) (before := before) (after := after)
        emitted remainder) := by
  have shapeWindow : 0 + checked.shape.allocations ≤ upper := by
    simpa using window
  have shapeInvariant : FrameCodeInvariant before 0 upper
      (checked.shape.bodyBytes 0 ++ remainder) := by
    simpa [checked.bytesExact] using invariant
  obtain ⟨after, exact⟩ := checked_shape_result checked.shape program coreBefore
    0 upper before remainder shapeWindow shapeInvariant
  refine ⟨⟨after, {
    result := exact.result
    consumedExact := exact.consumedExact.trans checked.bytesExact.symm
    remainderExact := exact.remainderExact }⟩⟩

end Lanius.X86.StatementCheck
