import Lanius.X86.EnvironmentExpressionCheck
import Lanius.X86.StatementCheck

namespace Lanius.X86.EnvironmentConditionalCheck

open Lanius Lanius.Core Lanius.Semantics
open Lanius.X86
open Lanius.X86.Machine
open Lanius.X86.ExpressionCheck
open Lanius.X86.ExpressionEnvironment
open Lanius.X86.DynamicComparison
open Lanius.X86.EnvironmentExpressionCheck
open Lanius.X86.StatementCheck

structure ConditionalCertificate
    (leftId rightId : VarId) (thenBranch elseBranch : Stmt) (emitted : List UInt8) where
  conditionBytes : List UInt8
  condition : NotEqualCertificate leftId rightId conditionBytes
  thenBytes : List UInt8
  elseBytes : List UInt8
  base : Nat
  thenShape : StatementShape thenBranch
  elseShape : StatementShape elseBranch
  baseExact : condition.slot = base
  thenBytesExact : thenBytes = thenShape.bodyBytes base
  elseBytesExact : elseBytes = elseShape.bodyBytes base
  thenBound : thenBytes.length + 5 < 2 ^ 31
  elseBound : elseBytes.length < 2 ^ 31
  emittedExact : emitted = conditionBytes ++ Machine.conditionalBytes thenBytes elseBytes

inductive Supported : Stmt → List UInt8 → Type
  | conditional {leftId rightId : VarId} {thenBranch elseBranch : Stmt}
      (certificate : ConditionalCertificate leftId rightId thenBranch elseBranch emitted) :
      Supported (.ifThenElse (.binary .notEqual (.local leftId) (.local rightId))
        thenBranch elseBranch) emitted

def branchCheck (source : Stmt) (base : Nat) (bytes : List UInt8) :
    Option { shape : StatementShape source // bytes = shape.bodyBytes base } :=
  match checkShape? source with
  | some shape => if exact : bytes = shape.bodyBytes base then some ⟨shape, exact⟩ else none
  | none => none

def check (source : Stmt) (emitted : List UInt8) (conditionBytes thenBytes elseBytes : List UInt8)
    (left right : ExpressionEnvironment.Location) (slot : Nat) : Option (Supported source emitted) :=
  match source with
  | .ifThenElse (.binary .notEqual (.local leftId) (.local rightId)) thenBranch elseBranch =>
      match EnvironmentExpressionCheck.check
          (.binary .notEqual (.local leftId) (.local rightId)) conditionBytes left right slot with
      | some (.notEqual condition) =>
          match branchCheck thenBranch slot thenBytes, branchCheck elseBranch slot elseBytes with
          | some ⟨thenShape, thenBytesExact⟩, some ⟨elseShape, elseBytesExact⟩ =>
              if thenBound : thenBytes.length + 5 < 2 ^ 31 then
                if elseBound : elseBytes.length < 2 ^ 31 then
                  if emittedExact : emitted = conditionBytes ++
                      Machine.conditionalBytes thenBytes elseBytes then
                    some (.conditional {
                      conditionBytes := conditionBytes
                      condition := condition
                      thenBytes := thenBytes
                      elseBytes := elseBytes
                      base := slot
                      thenShape := thenShape
                      elseShape := elseShape
                      baseExact := by simp [EnvironmentExpressionCheck.check]
                      thenBytesExact := thenBytesExact
                      elseBytesExact := elseBytesExact
                      thenBound := thenBound
                      elseBound := elseBound
                      emittedExact := emittedExact })
                  else none
                else none
              else none
          | _, _ => none
      | _ => none
  | _ => none

theorem prefixInvariant
    {before : Machine.State} {lower upper : Nat} {head suffix : List UInt8}
    (invariant : FrameCodeInvariant before lower upper (head ++ suffix)) :
    FrameCodeInvariant before lower upper head := by
  have loaded : CodeAt before.memory before.rip head :=
    CodeAt.prefix (first := head) invariant.loaded
  refine ⟨loaded, ?_, invariant.slotsSeparated, invariant.belowSlotsSeparated⟩
  intro index bound slot lowerBound upperBound lane
  exact invariant.separated index (by simp only [List.length_append]; omega)
    slot lowerBound upperBound lane

theorem sound
    {leftId rightId : VarId} {thenBranch elseBranch : Stmt} {emitted : List UInt8}
    (certificate : ConditionalCertificate leftId rightId thenBranch elseBranch emitted)
    (program : Program) (environment : Environment coreBefore machineBefore)
    (leftValue rightValue : Int) (lower upper : Nat)
    (leftRelated : environment.Relates leftId certificate.condition.leftLocation leftValue)
    (rightRelated : environment.Relates rightId certificate.condition.rightLocation rightValue)
    (leftWindow : ∀ old, certificate.condition.leftLocation = .frame old →
      lower ≤ old ∧ old < upper)
    (rightWindow : ∀ old, certificate.condition.rightLocation = .frame old →
      lower ≤ old ∧ old < upper)
    (slotWindow : lower ≤ certificate.base ∧ certificate.base < upper)
    (rightNotSlot : ∀ old, certificate.condition.rightLocation = .frame old →
      old ≠ certificate.base)
    (thenWindow : certificate.base + certificate.thenShape.allocations ≤ upper)
    (elseWindow : certificate.base + certificate.elseShape.allocations ≤ upper)
    (invariant : FrameCodeInvariant machineBefore lower upper emitted) :
    Nonempty (Σ after : Machine.State,
      Result program coreBefore
        (.ifThenElse (.binary .notEqual (.local leftId) (.local rightId)) thenBranch elseBranch)
        .next coreBefore certificate.base upper machineBefore after) := by
  rcases leftRelated with ⟨leftEntry, leftFound, leftExact, leftValueExact⟩
  rcases rightRelated with ⟨rightEntry, rightFound, rightExact, rightValueExact⟩
  have leftIdExact := environment.keyed leftId leftEntry leftFound
  have rightIdExact := environment.keyed rightId rightEntry rightFound
  have leftLocal : coreBefore.local? leftId = some (.signed .i32 leftValue) := by
    simpa [leftIdExact, leftValueExact] using leftEntry.localValue
  have rightLocal : coreBefore.local? rightId = some (.signed .i32 rightValue) := by
    simpa [rightIdExact, rightValueExact] using rightEntry.localValue
  have leftRelated' : environment.Relates leftId certificate.condition.leftLocation leftValue :=
    ⟨leftEntry, leftFound, leftExact, leftValueExact⟩
  have rightRelated' : environment.Relates rightId certificate.condition.rightLocation rightValue :=
    ⟨rightEntry, rightFound, rightExact, rightValueExact⟩
  rw [certificate.emittedExact] at invariant
  have conditionInvariant : FrameCodeInvariant machineBefore lower upper
      certificate.conditionBytes := prefixInvariant invariant
  have conditionStable : StableExpr 2 program coreBefore
        (.binary .notEqual (.local leftId) (.local rightId))
        (.boolean (leftValue != rightValue)) coreBefore := by
    intro fuel enough
    rw [show fuel = (fuel - 2).succ.succ by omega]
    apply evalExpr_binary_done (fuel := (fuel - 2).succ) program coreBefore .notEqual
      (.local leftId) (.local rightId) (.signed .i32 leftValue) (.signed .i32 rightValue)
      (.boolean (leftValue != rightValue)) coreBefore coreBefore
    · exact evalExpr_local_of_local? (fuel - 2) program coreBefore leftId
        (.signed .i32 leftValue) leftLocal
    · exact evalExpr_local_of_local? (fuel - 2) program coreBefore rightId
        (.signed .i32 rightValue) rightLocal
    · simp
    · simpa [evalBinaryValue, scalarEqual] using
        (show (!(leftValue == rightValue)) = (leftValue != rightValue) by rfl)
  have conditionBytesExact : certificate.conditionBytes =
      localNotEqualBytes certificate.condition.leftLocation certificate.condition.rightLocation
        certificate.base := by
    calc
      certificate.conditionBytes = localNotEqualBytes certificate.condition.leftLocation
          certificate.condition.rightLocation certificate.condition.slot :=
        certificate.condition.bytesExact
      _ = localNotEqualBytes certificate.condition.leftLocation certificate.condition.rightLocation
          certificate.base := by rw [certificate.baseExact]
  have conditionInvariant' : FrameCodeInvariant machineBefore lower upper
      (localNotEqualBytes certificate.condition.leftLocation certificate.condition.rightLocation
        certificate.base) := by
    rw [← conditionBytesExact]
    exact conditionInvariant
  obtain ⟨prefixBefore, conditionCore, conditionSteps, conditionRegister64,
      conditionRbp, conditionMemory, conditionRip⟩ :=
    local_notEqual program environment leftId rightId certificate.condition.leftLocation
      certificate.condition.rightLocation leftValue rightValue certificate.base lower upper
      leftRelated' rightRelated' leftWindow rightWindow slotWindow rightNotSlot conditionInvariant'
  have conditionEval := conditionStable 2 (by omega)
  have conditionRip' : prefixBefore.rip = machineBefore.rip +
      BitVec.ofNat 64 certificate.conditionBytes.length := by
    simpa [conditionBytesExact] using conditionRip
  have conditionTail0 : CodeAt machineBefore.memory
      (machineBefore.rip + BitVec.ofNat 64 certificate.conditionBytes.length)
      (Machine.conditionalBytes certificate.thenBytes certificate.elseBytes) :=
    CodeAt.suffix (first := certificate.conditionBytes) invariant.loaded
  have conditionTail' : CodeAt
      (write32 machineBefore.memory
        (frameSlotAddress (machineBefore.registers rbpRegister) certificate.base)
        (BitVec.ofInt 32 leftValue))
      (machineBefore.rip + BitVec.ofNat 64 certificate.conditionBytes.length)
      (Machine.conditionalBytes certificate.thenBytes certificate.elseBytes) := by
    apply conditionTail0.write32
    intro index bound lane
    simpa [List.length_append, BitVec.ofNat_add, BitVec.add_assoc] using
      invariant.separated (certificate.conditionBytes.length + index)
        (by simp only [List.length_append]; omega) certificate.base
        slotWindow.1 slotWindow.2 lane
  have conditionTail : CodeAt prefixBefore.memory prefixBefore.rip
      (Machine.conditionalBytes certificate.thenBytes certificate.elseBytes) := by
    simpa [conditionMemory, conditionRip'] using conditionTail'
  have conditionPrefixInvariant := FrameCodeInvariant.suffix invariant conditionTail
    conditionRip' conditionRbp
  have conditionStatementStable : StableStmt 3 program coreBefore
      (.expression (.binary .notEqual (.local leftId) (.local rightId))) .next coreBefore := by
    intro fuel enough
    have h := execStmt_expression (fuel - 1) program coreBefore
        (.binary .notEqual (.local leftId) (.local rightId))
        (.boolean (leftValue != rightValue)) coreBefore
        (conditionStable (fuel - 1) (by omega))
    convert h using 1 <;> omega
  let conditionResult : Result program coreBefore
      (.expression (.binary .notEqual (.local leftId) (.local rightId))) .next coreBefore
      certificate.base upper machineBefore prefixBefore := {
    core := ⟨3, execStmt_expression 2 program coreBefore
      (.binary .notEqual (.local leftId) (.local rightId))
      (.boolean (leftValue != rightValue)) coreBefore conditionEval⟩
    coreStable := ⟨3, conditionStatementStable⟩
    consumed := certificate.conditionBytes
    remainder := Machine.conditionalBytes certificate.thenBytes certificate.elseBytes
    steps := 8
    run := conditionSteps
    loaded := invariant.loaded
    remainderLoaded := conditionTail
    ripAdvance := conditionRip'
    frameStable := conditionRbp
    preserveBelow := by
      intro below belowBound
      rw [conditionMemory]
      apply read32_frame
      by_cases inWindow : lower ≤ below
      · exact invariant.slotsSeparated below certificate.base inWindow
          (by omega) slotWindow.1 slotWindow.2 (by omega)
      · exact invariant.belowSlotsSeparated below (by omega) certificate.base
          slotWindow.1 slotWindow.2 (by omega)
    preserveRead64Outside := by
      intro address outside
      rw [conditionMemory]
      apply read64_write32_frame
      intro i j
      exact outside certificate.base (Nat.le_refl _) slotWindow.2 i j
    preserveCodeAt := by
      intro address bytes loaded outside
      rw [conditionMemory]
      apply CodeAt.write32 loaded
      intro index bound lane
      exact outside index bound certificate.base (Nat.le_refl _) slotWindow.2 lane }
  have conditionRegister : (prefixBefore.registers 0).setWidth 32 =
      BitVec.ofNat 32 (if leftValue != rightValue then 1 else 0) := by
    have exact := congrArg (fun bits : BitVec 64 => bits.setWidth 32) conditionRegister64
    cases h : (leftValue != rightValue) <;> simp [h] at exact ⊢ <;> exact exact
  let control := conditional_prefix_steps (suffix := []) certificate.thenBound certificate.elseBound
    (by simpa using conditionTail)
      (BitVec.ofNat 32 (if leftValue != rightValue then 1 else 0)) conditionRegister
  have controlInvariant := conditional_prefix_invariant (by simpa using conditionPrefixInvariant)
    certificate.thenBound certificate.elseBound control
  by_cases equal : leftValue = rightValue
  · have choice : control.takeThen = false := by
      rw [control.choiceExact]
      simp [equal]
    have elseInvariant : FrameCodeInvariant control.after lower upper
        (certificate.elseShape.bodyBytes certificate.base) := by
      simpa [choice, certificate.thenBytesExact, certificate.elseBytesExact] using controlInvariant
    obtain ⟨⟨elseAfter, elseExact⟩⟩ := checked_shape_result certificate.elseShape
      program coreBefore certificate.base upper control.after [] elseWindow elseInvariant
    let finalResult := checked_conditional_false (trace := {
      conditionResult := conditionResult
      conditionStable := by simpa [equal] using (⟨2, conditionStable⟩)
      control := control
      elseResult := elseExact.result
      conditionRemainderExact := by simp [conditionResult]
      thenBound := certificate.thenBound
      elseConsumedExact := by simpa [certificate.elseBytesExact] using elseExact.consumedExact
      elseRemainderExact := elseExact.remainderExact })
    exact ⟨⟨elseAfter, finalResult⟩⟩
  · have choice : control.takeThen = true := by
      rw [control.choiceExact]
      simp [equal]
    have thenInvariant : FrameCodeInvariant control.after lower upper
        (certificate.thenShape.bodyBytes certificate.base ++
          (Machine.jumpBytes (BitVec.ofNat 32 certificate.elseBytes.length) ++
            certificate.elseShape.bodyBytes certificate.base)) := by
      simpa [choice, certificate.thenBytesExact, certificate.elseBytesExact,
        List.append_assoc] using controlInvariant
    obtain ⟨⟨thenAfter, thenExact⟩⟩ := checked_shape_result certificate.thenShape
      program coreBefore certificate.base upper control.after
      (Machine.jumpBytes (BitVec.ofNat 32 certificate.elseBytes.length) ++
        certificate.elseBytes) thenWindow (by
          simpa [certificate.thenBytesExact, certificate.elseBytesExact, List.append_assoc]
            using thenInvariant)
    let final := thenAfter.jump (BitVec.ofNat 32 certificate.elseBytes.length)
      (Machine.jumpBytes (BitVec.ofNat 32 certificate.elseBytes.length)).length
    let finalResult := checked_conditional_true (trace := {
      conditionResult := conditionResult
      conditionStable := by simpa [equal] using (⟨2, conditionStable⟩)
      control := control
      thenResult := thenExact.result
      conditionRemainderExact := by simp [conditionResult]
      thenConsumedExact := by simpa [certificate.thenBytesExact] using thenExact.consumedExact
      thenRemainderExact := by simpa using thenExact.remainderExact
      elseBound := certificate.elseBound
      jumpAfterExact := by rfl })
    exact ⟨⟨final, finalResult⟩⟩

end Lanius.X86.EnvironmentConditionalCheck
