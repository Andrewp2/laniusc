import Lanius.X86.StatementCheck
import Lanius.X86.Machine.LoopEncoding

namespace Lanius.X86.StatementCheck

open Lanius Lanius.Core Lanius.Semantics
open Lanius.X86
open Lanius.X86.Machine
open Lanius.X86.ExpressionCheck

/-! Finite loop traces.  These are deliberately separate from the checker:
    they compose already authenticated guard/body results without claiming
    arbitrary recursive termination. -/

structure WhileFalseTrace
    {program : Program} {coreBefore coreAfter : Semantics.State}
    {condition : Core.Expr} {body : Stmt} {base upper : Nat}
    {before prefixBefore final : Machine.State}
    {bodyBytes : List UInt8} (suffix : List UInt8) where
  conditionResult : Result program coreBefore (.expression condition) .next coreAfter
    base upper before prefixBefore
  conditionStable : ∃ fuel, StableExpr fuel program coreBefore condition
    (.boolean false) coreAfter
  guardBits : (prefixBefore.registers 0).setWidth 32 = 0
  guardResult : final =
    (prefixBefore.test32 0 0 (prefixBefore.flags.getLsbD 4)
      (testBytes .w32 0 0).length).branch 4
      (BitVec.ofNat 32 (bodyBytes.length + 5)) 6
  conditionRemainderExact : conditionResult.remainder = loopBytes bodyBytes ++ suffix
  loopBound : loopDistance bodyBytes < 2 ^ 31

private theorem loopBodyBound {body : List UInt8}
    (bound : loopDistance body < 2 ^ 31) : body.length + 5 < 2 ^ 31 := by
  simp [loopDistance, conditionalPrefix, testBytes, branchBytes, displacementBytes] at bound ⊢
  omega

private theorem loopExitLoaded
    {memory : Memory} {address : Machine.Address} {body suffix : List UInt8}
    (bound : loopDistance body < 2 ^ 31)
    (loaded : CodeAt memory address (loopBytes body ++ suffix)) :
    CodeAt memory
      (address + BitVec.ofNat 64 (conditionalPrefix body).length +
        (BitVec.ofNat 32 (body.length + 5)).signExtend 64) suffix := by
  have exact : CodeAt memory address
      (conditionalPrefix body ++ body ++
        jumpBytes (loopBackDisplacement body) ++ suffix) := by
    simpa [loopBytes, List.append_assoc] using loaded
  have tail := exact.suffix
    (first := conditionalPrefix body ++ body ++ jumpBytes (loopBackDisplacement body))
    (rest := suffix)
  have target := conditional_code_target_address
    (address := address) (thenBody := body) (elseBody := ([] : List UInt8))
    (loopBodyBound bound)
  rw [target]
  simpa [List.length_append, jumpBytes, displacementBytes] using tail

private theorem guard_not_taken_steps (before middle after : Machine.State)
    {body : List UInt8}
    (loaded : CodeAt before.memory before.rip (conditionalPrefix body))
    (testResult : middle = before.test32 0 0 (before.flags.getLsbD 4)
      (testBytes .w32 0 0).length)
    (branchResult : after = middle.branch 4
      (BitVec.ofNat 32 (body.length + 5)) 6)
    (notTaken : condition middle.flags 4 = false) :
    Steps 2 before after ∧
      after.rip = before.rip + BitVec.ofNat 64 (conditionalPrefix body).length := by
  have testLoaded : CodeAt before.memory before.rip (testBytes .w32 0 0) := by
    simpa [conditionalPrefix] using loaded.prefix
  have branchLoaded : CodeAt middle.memory middle.rip
      (branchBytes ⟨4, by decide⟩ (BitVec.ofNat 32 (body.length + 5))) := by
    simpa [testResult, State.test32, State.test, conditionalPrefix] using loaded.suffix
  have first : Step before middle :=
    test_step .w32 before middle 0 0 testLoaded (before.flags.getLsbD 4) testResult
  have second := branch_step_rip_not_taken middle after 4 _ branchLoaded notTaken branchResult
  refine ⟨by simpa using Steps.cons first (Steps.cons second.1 (Steps.refl after)), ?_⟩
  simpa [testResult, State.test32, State.test, conditionalPrefix,
    List.length_append, branchBytes, displacementBytes, BitVec.ofNat_add,
    BitVec.add_assoc] using second.2

def checked_while_false
    {program : Program} {coreBefore coreAfter : Semantics.State}
    {condition : Core.Expr} {body : Stmt} {base upper : Nat}
    {before prefixBefore final : Machine.State} {bodyBytes suffix : List UInt8}
    (trace : WhileFalseTrace (program := program) (coreBefore := coreBefore)
      (coreAfter := coreAfter) (condition := condition) (body := body)
      (base := base) (upper := upper) (before := before)
      (prefixBefore := prefixBefore) (final := final) (bodyBytes := bodyBytes) suffix) :
    Result program coreBefore (.whileLoop condition body) .next coreAfter
      base upper before final := by
  have bound := loopBodyBound trace.loopBound
  have loopLoaded : CodeAt prefixBefore.memory prefixBefore.rip
      (loopBytes bodyBytes ++ suffix) := by
    simpa [trace.conditionRemainderExact] using trace.conditionResult.remainderLoaded
  have prefixLoaded : CodeAt prefixBefore.memory prefixBefore.rip
      (conditionalPrefix bodyBytes) := by
    apply CodeAt.prefix (first := conditionalPrefix bodyBytes)
      (rest := bodyBytes ++ jumpBytes (loopBackDisplacement bodyBytes) ++ suffix)
    simpa [loopBytes, List.append_assoc] using loopLoaded
  let tested := prefixBefore.test32 0 0 (prefixBefore.flags.getLsbD 4)
    (testBytes .w32 0 0).length
  have taken : Machine.condition tested.flags 4 = true := by
    simpa [tested, State.test32, State.test, trace.guardBits,
      BitVec.and_self, logical32Flags] using
      test32_zero_condition prefixBefore.flags 0 (prefixBefore.flags.getLsbD 4)
  have guardResult : final = tested.branch 4
      (BitVec.ofNat 32 (bodyBytes.length + 5)) 6 := by
    simpa [tested] using trace.guardResult
  have guard := loop_guard_steps prefixBefore tested final bodyBytes prefixLoaded
    (by rfl) guardResult taken
  have exitLoaded := loopExitLoaded (memory := prefixBefore.memory)
    (address := prefixBefore.rip) (body := bodyBytes) (suffix := suffix)
    trace.loopBound loopLoaded
  have finalMemory : final.memory = prefixBefore.memory := by
    rw [trace.guardResult]
    rfl
  have finalFrame : final.registers rbpRegister = prefixBefore.registers rbpRegister := by
    rw [trace.guardResult]
    rfl
  refine {
    core := by
      obtain ⟨fuel, run⟩ := trace.conditionStable
      exact ⟨fuel + 1, execStmt_while_false fuel program coreBefore condition body coreAfter
        (run fuel (by omega))⟩
    coreStable := by
      obtain ⟨fuel, run⟩ := trace.conditionStable
      refine ⟨fuel + 1, ?_⟩
      intro fuel' enough
      cases fuel' with
      | zero => omega
      | succ fuel' =>
          exact execStmt_while_false fuel' program coreBefore condition body coreAfter
            (run fuel' (by omega))
    consumed := trace.conditionResult.consumed ++ loopBytes bodyBytes
    remainder := suffix
    steps := trace.conditionResult.steps + 2
    run := trace.conditionResult.run.trans guard.1
    loaded := by
      simpa [trace.conditionRemainderExact, loopBytes, List.append_assoc] using
        trace.conditionResult.loaded
    remainderLoaded := by simpa [finalMemory, guard.2] using exitLoaded
    ripAdvance := by
      rw [guard.2, trace.conditionResult.ripAdvance]
      have target := conditional_code_target_address
        (address := before.rip + BitVec.ofNat 64 trace.conditionResult.consumed.length)
        (thenBody := bodyBytes) (elseBody := ([] : List UInt8)) bound
      simpa [loopBytes, List.length_append, jumpBytes, displacementBytes,
        conditionalPrefix, branchBytes, testBytes, BitVec.ofNat_add,
        BitVec.add_assoc] using target
    frameStable := finalFrame.trans trace.conditionResult.frameStable
    preserveBelow := by
      intro slot below
      have unchanged : read32 final.memory
          (frameSlotAddress (before.registers rbpRegister) slot) =
          read32 prefixBefore.memory
            (frameSlotAddress (before.registers rbpRegister) slot) := by
        rw [finalMemory]
      calc
        read32 final.memory (frameSlotAddress (before.registers rbpRegister) slot) =
            read32 prefixBefore.memory
              (frameSlotAddress (before.registers rbpRegister) slot) := unchanged
        _ = read32 before.memory (frameSlotAddress (before.registers rbpRegister) slot) :=
          trace.conditionResult.preserveBelow slot below
    preserveRead64Outside := by
      intro address outside
      rw [finalMemory]
      exact trace.conditionResult.preserveRead64Outside address outside
    preserveCodeAt := by
      intro address bytes loaded outside
      rw [finalMemory]
      exact trace.conditionResult.preserveCodeAt address bytes loaded outside }

structure WhileOneTrace
    {program : Program} {coreBefore coreMiddle coreBodyAfter coreAfter : Semantics.State}
    {condition : Core.Expr} {body : Stmt} {base upper : Nat}
    {before prefixBefore firstAfter bodyAfter loopAfter secondPrefixBefore final : Machine.State}
    {bodyBytes : List UInt8} (suffix : List UInt8) where
  conditionResult : Result program coreBefore (.expression condition) .next coreMiddle
    base upper before prefixBefore
  conditionStableTrue : ∃ fuel, StableExpr fuel program coreBefore condition
    (.boolean true) coreMiddle
  firstGuardBits : (prefixBefore.registers 0).setWidth 32 = 1
  firstGuardResult : firstAfter =
    (prefixBefore.test32 0 0 (prefixBefore.flags.getLsbD 4)
      (testBytes .w32 0 0).length).branch 4
      (BitVec.ofNat 32 (bodyBytes.length + 5)) 6
  bodyResult : Result program coreMiddle body .next coreBodyAfter
    base upper firstAfter bodyAfter
  bodyConsumedExact : bodyResult.consumed = bodyBytes
  bodyRemainderExact : bodyResult.remainder =
    jumpBytes (loopBackDisplacement bodyBytes) ++ suffix
  jumpResult : loopAfter = bodyAfter.jump (loopBackDisplacement bodyBytes)
    (jumpBytes (loopBackDisplacement bodyBytes)).length
  secondConditionResult : Result program coreBodyAfter (.expression condition) .next coreAfter
    base upper loopAfter secondPrefixBefore
  conditionStableFalse : ∃ fuel, StableExpr fuel program coreBodyAfter condition
    (.boolean false) coreAfter
  secondGuardBits : (secondPrefixBefore.registers 0).setWidth 32 = 0
  secondGuardResult : final =
    (secondPrefixBefore.test32 0 0 (secondPrefixBefore.flags.getLsbD 4)
      (testBytes .w32 0 0).length).branch 4
      (BitVec.ofNat 32 (bodyBytes.length + 5)) 6
  conditionRemainderExact : conditionResult.remainder = loopBytes bodyBytes ++ suffix
  secondConditionRemainderExact : secondConditionResult.remainder = loopBytes bodyBytes ++ suffix
  conditionConsumedExact : secondConditionResult.consumed = conditionResult.consumed
  loopBound : loopDistance bodyBytes < 2 ^ 31

def checked_while_one_then_false
    {program : Program} {coreBefore coreMiddle coreBodyAfter coreAfter : Semantics.State}
    {condition : Core.Expr} {body : Stmt} {base upper : Nat}
    {before prefixBefore firstAfter bodyAfter loopAfter secondPrefixBefore final : Machine.State}
    {bodyBytes suffix : List UInt8}
    (trace : WhileOneTrace (program := program) (coreBefore := coreBefore)
      (coreMiddle := coreMiddle) (coreBodyAfter := coreBodyAfter) (coreAfter := coreAfter)
      (condition := condition) (body := body) (base := base) (upper := upper)
      (before := before) (prefixBefore := prefixBefore) (firstAfter := firstAfter)
      (bodyAfter := bodyAfter) (loopAfter := loopAfter)
      (secondPrefixBefore := secondPrefixBefore) (final := final)
      (bodyBytes := bodyBytes) suffix) :
    Result program coreBefore (.whileLoop condition body) .next coreAfter
      base upper before final := by
  have bound := loopBodyBound trace.loopBound
  have loopLoaded : CodeAt prefixBefore.memory prefixBefore.rip
      (loopBytes bodyBytes ++ suffix) := by
    simpa [trace.conditionRemainderExact] using trace.conditionResult.remainderLoaded
  have prefixLoaded : CodeAt prefixBefore.memory prefixBefore.rip
      (conditionalPrefix bodyBytes) := by
    apply CodeAt.prefix (first := conditionalPrefix bodyBytes)
      (rest := bodyBytes ++ jumpBytes (loopBackDisplacement bodyBytes) ++ suffix)
    simpa [loopBytes, List.append_assoc] using loopLoaded
  let tested := prefixBefore.test32 0 0 (prefixBefore.flags.getLsbD 4)
    (testBytes .w32 0 0).length
  have notTaken : Machine.condition tested.flags 4 = false := by
    have c := test32_zero_condition prefixBefore.flags 1
      (prefixBefore.flags.getLsbD 4)
    simpa [tested, State.test32, State.test, trace.firstGuardBits,
      logical32Flags] using c
  have firstGuardResult : firstAfter = tested.branch 4
      (BitVec.ofNat 32 (bodyBytes.length + 5)) 6 := by
    simpa [tested] using trace.firstGuardResult
  have firstGuard := guard_not_taken_steps (body := bodyBytes) prefixBefore tested firstAfter
    prefixLoaded (by rfl) firstGuardResult notTaken
  have jumpTail : CodeAt bodyAfter.memory bodyAfter.rip
      (jumpBytes (loopBackDisplacement bodyBytes) ++ suffix) := by
    simpa [trace.bodyRemainderExact] using trace.bodyResult.remainderLoaded
  have jumpLoaded := jumpTail.prefix
  have jump := loop_back_jump_step_rip bodyAfter loopAfter bodyBytes jumpLoaded
    trace.jumpResult
  have secondLoopLoaded : CodeAt secondPrefixBefore.memory secondPrefixBefore.rip
      (loopBytes bodyBytes ++ suffix) := by
    simpa [trace.secondConditionRemainderExact] using
      trace.secondConditionResult.remainderLoaded
  have secondPrefixLoaded : CodeAt secondPrefixBefore.memory secondPrefixBefore.rip
      (conditionalPrefix bodyBytes) := by
    apply CodeAt.prefix (first := conditionalPrefix bodyBytes)
      (rest := bodyBytes ++ jumpBytes (loopBackDisplacement bodyBytes) ++ suffix)
    simpa [loopBytes, List.append_assoc] using secondLoopLoaded
  let secondTested := secondPrefixBefore.test32 0 0
    (secondPrefixBefore.flags.getLsbD 4) (testBytes .w32 0 0).length
  have secondTaken : Machine.condition secondTested.flags 4 = true := by
    simpa [secondTested, State.test32, State.test, trace.secondGuardBits,
      BitVec.and_self, logical32Flags] using
      test32_zero_condition secondPrefixBefore.flags 0
        (secondPrefixBefore.flags.getLsbD 4)
  have secondGuardResult : final = secondTested.branch 4
      (BitVec.ofNat 32 (bodyBytes.length + 5)) 6 := by
    simpa [secondTested] using trace.secondGuardResult
  have secondGuard := loop_guard_steps secondPrefixBefore secondTested final bodyBytes
    secondPrefixLoaded (by rfl) secondGuardResult secondTaken
  have loopHeader : loopAfter.rip = prefixBefore.rip := by
    rw [jump.2, trace.bodyResult.ripAdvance, trace.bodyConsumedExact,
      firstGuard.2]
    have target := loop_back_target_address (address := prefixBefore.rip)
      (body := bodyBytes) trace.loopBound
    simpa [conditionalPrefix, jumpBytes, displacementBytes, testBytes,
      branchBytes, List.length_append, BitVec.ofNat_add, BitVec.add_assoc] using target
  have exitLoaded := loopExitLoaded trace.loopBound secondLoopLoaded
  have finalMemory : final.memory = secondPrefixBefore.memory := by
    rw [secondGuardResult]
    rfl
  have firstFrame : firstAfter.registers rbpRegister = prefixBefore.registers rbpRegister := by
    rw [firstGuardResult]
    rfl
  have loopFrame : loopAfter.registers rbpRegister = bodyAfter.registers rbpRegister := by
    rw [trace.jumpResult]
    rfl
  have secondFrame : final.registers rbpRegister = secondPrefixBefore.registers rbpRegister := by
    rw [secondGuardResult]
    rfl
  have coreStable : ∃ fuel, StableStmt fuel program coreBefore
      (.whileLoop condition body) .next coreAfter := by
    obtain ⟨conditionFuel, conditionRun⟩ := trace.conditionStableTrue
    obtain ⟨bodyFuel, bodyRun⟩ := trace.bodyResult.coreStable
    obtain ⟨secondFuel, secondRun⟩ := trace.conditionStableFalse
    refine ⟨max conditionFuel (max bodyFuel (secondFuel + 1)) + 2, ?_⟩
    intro fuel enough
    cases fuel with
    | zero => omega
    | succ fuel =>
      cases fuel with
      | zero => omega
      | succ fuel =>
        apply execStmt_while_true_step (fuel := fuel.succ) program coreBefore condition body
          coreMiddle coreBodyAfter coreAfter .next .next
        · exact conditionRun fuel.succ (by omega)
        · exact bodyRun fuel.succ (by omega)
        · exact Or.inl rfl
        · exact execStmt_while_false fuel program coreBodyAfter condition body coreAfter
            (secondRun fuel (by omega))
  refine {
    core := by
      obtain ⟨conditionFuel, conditionRun⟩ := trace.conditionStableTrue
      obtain ⟨bodyFuel, bodyRun⟩ := trace.bodyResult.coreStable
      obtain ⟨secondFuel, secondRun⟩ := trace.conditionStableFalse
      refine ⟨max conditionFuel (max bodyFuel (secondFuel + 1)) + 2, ?_⟩
      apply execStmt_while_true_step
        (fuel := max conditionFuel (max bodyFuel (secondFuel + 1)) + 1)
        program coreBefore condition body coreMiddle coreBodyAfter coreAfter .next .next
      · exact conditionRun _ (by omega)
      · exact bodyRun _ (by omega)
      · exact Or.inl rfl
      · apply execStmt_while_false
        exact secondRun _ (by omega)
    coreStable := coreStable
    consumed := trace.conditionResult.consumed ++ loopBytes bodyBytes
    remainder := suffix
    steps := trace.conditionResult.steps + (2 + (trace.bodyResult.steps + 1)) +
      trace.secondConditionResult.steps + 2
    run := trace.conditionResult.run.trans
      (firstGuard.1.trans
        (trace.bodyResult.run.trans
          (jump.1.trans
            (trace.secondConditionResult.run.trans secondGuard.1))))
    loaded := by
      simpa [trace.conditionRemainderExact, loopBytes, List.append_assoc] using
        trace.conditionResult.loaded
    remainderLoaded := by
      simpa [finalMemory, secondGuard.2] using exitLoaded
    ripAdvance := by
      rw [secondGuard.2, trace.secondConditionResult.ripAdvance, loopHeader,
        trace.conditionConsumedExact, trace.conditionResult.ripAdvance]
      have target := conditional_code_target_address
        (address := before.rip + BitVec.ofNat 64 trace.conditionResult.consumed.length)
        (thenBody := bodyBytes) (elseBody := ([] : List UInt8)) bound
      simpa [loopBytes, List.length_append, jumpBytes, displacementBytes,
        conditionalPrefix, branchBytes, testBytes, BitVec.ofNat_add,
        BitVec.add_assoc] using target
    frameStable := by
      calc
        final.registers rbpRegister = secondPrefixBefore.registers rbpRegister := secondFrame
        _ = loopAfter.registers rbpRegister := trace.secondConditionResult.frameStable
        _ = bodyAfter.registers rbpRegister := loopFrame
        _ = firstAfter.registers rbpRegister := trace.bodyResult.frameStable
        _ = prefixBefore.registers rbpRegister := firstFrame
        _ = before.registers rbpRegister := trace.conditionResult.frameStable
    preserveBelow := by
      intro slot below
      have c1 := trace.conditionResult.preserveBelow slot below
      have bodyBelow := trace.bodyResult.preserveBelow slot (by omega)
      have bodyBelow' : read32 bodyAfter.memory
          (frameSlotAddress (before.registers rbpRegister) slot) =
          read32 firstAfter.memory
            (frameSlotAddress (before.registers rbpRegister) slot) := by
        simpa [firstFrame] using bodyBelow
      have jumpBelow : read32 loopAfter.memory
          (frameSlotAddress (before.registers rbpRegister) slot) =
          read32 bodyAfter.memory
            (frameSlotAddress (before.registers rbpRegister) slot) := by
        rw [trace.jumpResult]
        rfl
      have c2 := trace.secondConditionResult.preserveBelow slot below
      have c2' : read32 secondPrefixBefore.memory
          (frameSlotAddress (before.registers rbpRegister) slot) =
          read32 loopAfter.memory
            (frameSlotAddress (before.registers rbpRegister) slot) := by
        simpa [loopFrame] using c2
      calc
        read32 final.memory (frameSlotAddress (before.registers rbpRegister) slot) =
            read32 secondPrefixBefore.memory
              (frameSlotAddress (before.registers rbpRegister) slot) := by
          rw [finalMemory]
        _ = read32 loopAfter.memory (frameSlotAddress (before.registers rbpRegister) slot) := c2'
        _ = read32 bodyAfter.memory (frameSlotAddress (before.registers rbpRegister) slot) := jumpBelow
        _ = read32 firstAfter.memory (frameSlotAddress (before.registers rbpRegister) slot) := bodyBelow'
        _ = read32 prefixBefore.memory (frameSlotAddress (before.registers rbpRegister) slot) := by
          rw [firstGuardResult]
          rfl
        _ = read32 before.memory (frameSlotAddress (before.registers rbpRegister) slot) := c1
    preserveRead64Outside := by
      intro address outside
      have bodyRead := trace.bodyResult.preserveRead64Outside address (by
        simpa [firstFrame] using outside)
      have c2Read := trace.secondConditionResult.preserveRead64Outside address (by
        simpa [loopFrame] using outside)
      have bodyRead' : read64 bodyAfter.memory address = read64 firstAfter.memory address := bodyRead
      have jumpRead : read64 loopAfter.memory address = read64 bodyAfter.memory address := by
        rw [trace.jumpResult]
        rfl
      have c2Read' : read64 secondPrefixBefore.memory address = read64 loopAfter.memory address := c2Read
      calc
        read64 final.memory address = read64 secondPrefixBefore.memory address := by rw [finalMemory]
        _ = read64 loopAfter.memory address := c2Read'
        _ = read64 bodyAfter.memory address := jumpRead
        _ = read64 firstAfter.memory address := bodyRead'
        _ = read64 prefixBefore.memory address := by rw [firstGuardResult]; rfl
        _ = read64 before.memory address := trace.conditionResult.preserveRead64Outside address outside
    preserveCodeAt := by
      intro address bytes loaded outside
      have c1 := trace.conditionResult.preserveCodeAt address bytes loaded outside
      have bodyCode := trace.bodyResult.preserveCodeAt address bytes c1 (by
        simpa [firstFrame] using outside)
      have jumpCode : CodeAt loopAfter.memory address bytes := by
        rw [trace.jumpResult]
        exact bodyCode
      have c2Code := trace.secondConditionResult.preserveCodeAt address bytes jumpCode (by
        simpa [loopFrame] using outside)
      rw [finalMemory]
      exact c2Code }

end Lanius.X86.StatementCheck
