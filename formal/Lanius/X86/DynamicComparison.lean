import Lanius.X86.ExpressionEnvironment
import Lanius.X86.Machine.ComparisonEncoding

namespace Lanius.X86.DynamicComparison

open Lanius Lanius.Core Lanius.Semantics
open Lanius.X86
open Lanius.X86.Machine
open Lanius.X86.ExpressionCheck
open Lanius.X86.ExpressionEnvironment
open Lanius.X86.LocalExpressionCheck

theorem compare_notEqual_condition (before : BitVec 64)
    (left right : BitVec 32) :
    condition (subtractFlags before left right) 5 = (left != right) := by
  change ((!((subtractFlags before left right).getLsbD 6)) = (left != right))
  unfold subtractFlags
  have zeroFlag (zero : Bool) (carry parity auxiliary sign overflow : Bool) :
      (arithmeticFlags before carry parity auxiliary zero sign overflow).getLsbD 6 = zero := by
    cases carry <;> cases parity <;> cases auxiliary <;> cases zero <;> cases sign <;>
      cases overflow <;> simp [arithmeticFlags]
  rw [zeroFlag]
  rw [Bool.eq_iff_iff]
  simp [BitVec.sub_eq_iff_eq_add]

def rebaseEntryAfterStore
    (entry : Entry coreBefore initial) (before stored : Machine.State)
    (storeResult : stored = before.store32 0 rbpRegister
      (BitVec.ofInt 32 (frameDisplacement slot)) (frameStoreBytes slot).length)
    (registerStable : ∀ reg, entry.location = .register reg →
      before.registers reg = initial.registers reg)
    (memoryStable : before.memory = initial.memory)
    (rbpStable : before.registers rbpRegister = initial.registers rbpRegister)
    (disjoint : ∀ oldSlot, entry.location = .frame oldSlot → ∀ i j : Fin 4,
      frameSlotAddress (before.registers rbpRegister) oldSlot +
          BitVec.ofNat 64 i.val ≠
        frameSlotAddress (before.registers rbpRegister) slot +
          BitVec.ofNat 64 j.val) :
    Entry coreBefore stored := by
  cases location : entry.location with
  | register reg =>
      refine {
        id := entry.id
        location := (by exact LocalExpressionCheck.Location.register reg)
        value := entry.value
        localValue := entry.localValue
        frameSlots := entry.frameSlots
        frameBound := ?_
        registerSafe := ?_
        representedRegister := ?_
        representedFrame := ?_ }
      · intro current h
        simp [location] at h
      · intro current h
        simpa [location] using entry.registerSafe current (location.trans h)
      · intro current h
        rw [storeResult]
        have stable := registerStable current (location.trans h)
        simpa [State.store32, stable] using entry.representedRegister current (location.trans h)
      · intro current h
        simp [location] at h
  | frame old =>
      refine {
        id := entry.id
        location := (by exact LocalExpressionCheck.Location.frame old)
        value := entry.value
        localValue := entry.localValue
        frameSlots := entry.frameSlots
        frameBound := ?_
        registerSafe := ?_
        representedRegister := ?_
        representedFrame := ?_ }
      · intro current h
        simpa [location] using entry.frameBound current (location.trans h)
      · intro current h
        simp [location] at h
      · intro current h
        simp [location] at h
      · intro current h
        have currentExact : current = old := by
          simpa [location] using h.symm
        subst current
        have oldBits := bits_eq_ofInt32_of_representation
          (entry.representedFrame old location)
        have storedValue := lowerFrameSlot_after_store before stored slot old
          storeResult (disjoint old location)
        have storedBits : read32 stored.memory
            (frameSlotAddress (stored.registers rbpRegister) old) =
            BitVec.ofInt 32 entry.value := by
          calc
            read32 stored.memory (frameSlotAddress (stored.registers rbpRegister) old) =
                read32 stored.memory
                  (frameSlotAddress (before.registers rbpRegister) old) := by
              rw [storeResult]
              rfl
            _ = read32 initial.memory
                (frameSlotAddress (before.registers rbpRegister) old) := by
              simpa [memoryStable] using storedValue
            _ = read32 initial.memory
                (frameSlotAddress (initial.registers rbpRegister) old) := by
              rw [rbpStable]
            _ = BitVec.ofInt 32 entry.value := oldBits
        rw [storedBits]
        exact ofInt32_toInt_of_representation (entry.representedFrame old location)

theorem rebaseEntryAfterStore_location
    (entry : Entry coreBefore initial) (before stored : Machine.State)
    (storeResult : stored = before.store32 0 rbpRegister
      (BitVec.ofInt 32 (frameDisplacement slot)) (frameStoreBytes slot).length)
    (registerStable : ∀ reg, entry.location = .register reg →
      before.registers reg = initial.registers reg)
    (memoryStable : before.memory = initial.memory)
    (rbpStable : before.registers rbpRegister = initial.registers rbpRegister)
    (disjoint : ∀ oldSlot, entry.location = .frame oldSlot → ∀ i j : Fin 4,
      frameSlotAddress (before.registers rbpRegister) oldSlot + BitVec.ofNat 64 i.val ≠
        frameSlotAddress (before.registers rbpRegister) slot + BitVec.ofNat 64 j.val) :
    (rebaseEntryAfterStore entry before stored storeResult registerStable memoryStable
      rbpStable disjoint).location = entry.location := by
  cases entry with
  | mk id location value localValue frameSlots frameBound registerSafe representedRegister representedFrame =>
      cases location <;> rfl

theorem rebaseEntryAfterStore_value
    (entry : Entry coreBefore initial) (before stored : Machine.State)
    (storeResult : stored = before.store32 0 rbpRegister
      (BitVec.ofInt 32 (frameDisplacement slot)) (frameStoreBytes slot).length)
    (registerStable : ∀ reg, entry.location = .register reg →
      before.registers reg = initial.registers reg)
    (memoryStable : before.memory = initial.memory)
    (rbpStable : before.registers rbpRegister = initial.registers rbpRegister)
    (disjoint : ∀ oldSlot, entry.location = .frame oldSlot → ∀ i j : Fin 4,
      frameSlotAddress (before.registers rbpRegister) oldSlot + BitVec.ofNat 64 i.val ≠
        frameSlotAddress (before.registers rbpRegister) slot + BitVec.ofNat 64 j.val) :
    (rebaseEntryAfterStore entry before stored storeResult registerStable memoryStable
      rbpStable disjoint).value = entry.value := by
  cases entry with
  | mk id location value localValue frameSlots frameBound registerSafe representedRegister representedFrame =>
      cases location <;> rfl

def localNotEqualBytes (left right : ExpressionEnvironment.Location) (slot : Nat) : List UInt8 :=
  left.bodyBytes ++ frameStoreBytes slot ++ right.bodyBytes ++ frameCompareBytes slot 5

theorem local_notEqual
    (program : Program) (environment : ExpressionEnvironment.Environment coreBefore machineBefore)
    (leftId rightId : VarId) (left right : ExpressionEnvironment.Location) (leftValue rightValue : Int)
    (slot lower upper : Nat)
    (leftRelated : environment.Relates leftId left leftValue)
    (rightRelated : environment.Relates rightId right rightValue)
    (leftWindow : ∀ old, left = .frame old → lower ≤ old ∧ old < upper)
    (rightWindow : ∀ old, right = .frame old → lower ≤ old ∧ old < upper)
    (slotWindow : lower ≤ slot ∧ slot < upper)
    (rightNotSlot : ∀ old, right = .frame old → old ≠ slot)
    (invariant : FrameCodeInvariant machineBefore lower upper
      (localNotEqualBytes left right slot)) :
    ∃ after, evalExpr 2 program coreBefore
        (.binary .notEqual (.local leftId) (.local rightId)) =
        .done (.boolean (leftValue != rightValue)) coreBefore ∧
      Steps 8 machineBefore after ∧
      after.registers 0 = (if leftValue != rightValue then (1 : BitVec 64) else 0) ∧
      after.registers rbpRegister = machineBefore.registers rbpRegister ∧
      after.memory = write32 machineBefore.memory
        (frameSlotAddress (machineBefore.registers rbpRegister) slot)
        (BitVec.ofInt 32 leftValue) ∧
      after.rip = machineBefore.rip + BitVec.ofNat 64
        (localNotEqualBytes left right slot).length := by
  rcases leftRelated with ⟨leftEntry, leftFound, leftExact, leftValueExact⟩
  rcases rightRelated with ⟨rightEntry, rightFound, rightExact, rightValueExact⟩
  have initialLoaded : CodeAt machineBefore.memory machineBefore.rip
      (left.bodyBytes ++ (frameStoreBytes slot ++
        (right.bodyBytes ++ frameCompareBytes slot 5))) := by
    simpa [localNotEqualBytes, List.append_assoc] using invariant.loaded
  have leftLoaded : CodeAt machineBefore.memory machineBefore.rip left.bodyBytes := by
    exact initialLoaded.prefix
  obtain ⟨leftCore, leftAfter, leftStep, leftResult, leftRip, leftRsp,
      leftPreserved, leftMemory, leftFlags⟩ :=
    loadLocal environment program leftId left leftValue
      ⟨leftEntry, leftFound, leftExact, leftValueExact⟩ leftLoaded
  let continuation := frameStoreBytes slot ++ right.bodyBytes ++ frameCompareBytes slot 5
  have leftTailLoaded : CodeAt leftAfter.memory leftAfter.rip continuation := by
    have tail := initialLoaded.suffix
    simpa [continuation, localNotEqualBytes, leftRip, leftMemory,
      List.append_assoc] using tail
  have leftInvariant : FrameCodeInvariant leftAfter lower upper continuation := by
    have initialInvariant : FrameCodeInvariant machineBefore lower upper
        (left.bodyBytes ++ continuation) := by
      simpa [localNotEqualBytes, continuation, List.append_assoc] using invariant
    apply FrameCodeInvariant.suffix initialInvariant
    · exact leftTailLoaded
    · exact leftRip
    · exact leftPreserved rbpRegister (by decide) (by decide)
  let stored := leftAfter.store32 0 rbpRegister
    (BitVec.ofInt 32 (frameDisplacement slot)) (frameStoreBytes slot).length
  have storeLoaded : CodeAt leftAfter.memory leftAfter.rip (frameStoreBytes slot) := by
    have tail : CodeAt leftAfter.memory leftAfter.rip
        (frameStoreBytes slot ++ (right.bodyBytes ++ frameCompareBytes slot 5)) := by
      simpa [continuation, List.append_assoc] using leftTailLoaded
    exact tail.prefix
  have storeStep := frameStore_step leftAfter stored slot storeLoaded (by rfl)
  have storedInvariant : FrameCodeInvariant stored lower upper
      (right.bodyBytes ++ frameCompareBytes slot 5) := by
    have afterStore := FrameCodeInvariant.after_store leftInvariant
      slotWindow.1 slotWindow.2 (by rfl)
    simpa [continuation] using afterStore
  have rightDisjoint : ∀ old, rightEntry.location = .frame old → ∀ i j : Fin 4,
      frameSlotAddress (leftAfter.registers rbpRegister) old + BitVec.ofNat 64 i.val ≠
        frameSlotAddress (leftAfter.registers rbpRegister) slot + BitVec.ofNat 64 j.val := by
    intro old oldExact i j
    have oldBounds := rightWindow old (rightExact.symm.trans oldExact)
    have different := rightNotSlot old (rightExact.symm.trans oldExact)
    have separated := leftInvariant.slotsSeparated old slot oldBounds.1 oldBounds.2
      slotWindow.1 slotWindow.2 different i j
    exact separated
  have rightRegisterStable : ∀ reg, rightEntry.location = .register reg →
      leftAfter.registers reg = machineBefore.registers reg := by
    intro reg location
    have safe := rightEntry.registerSafe reg location
    exact leftPreserved reg safe.1 safe.2
  have rightRbpStable := leftPreserved rbpRegister (by decide) (by decide)
  have rightStoreResult : stored = leftAfter.store32 0 rbpRegister
      (BitVec.ofInt 32 (frameDisplacement slot)) (frameStoreBytes slot).length := by
    simp [stored]
  let rightStored := rebaseEntryAfterStore rightEntry leftAfter stored rightStoreResult
    rightRegisterStable leftMemory rightRbpStable rightDisjoint
  have rightLocation : rightStored.location = right := by
    have rebased := rebaseEntryAfterStore_location rightEntry leftAfter stored
      rightStoreResult rightRegisterStable leftMemory rightRbpStable rightDisjoint
    simpa [rightStored] using rebased.trans rightExact
  have rightValueStored : rightStored.value = rightValue := by
    have rebased := rebaseEntryAfterStore_value rightEntry leftAfter stored
      rightStoreResult rightRegisterStable leftMemory rightRbpStable rightDisjoint
    simpa [rightStored, rightValueExact] using rebased
  have rightLoaded : CodeAt stored.memory stored.rip rightStored.location.bodyBytes := by
    have loaded := storedInvariant.loaded
    simpa [rightLocation, rightExact, List.append_assoc] using loaded.prefix
  let rightChecked : LocalExpressionCheck.Supported rightStored
      (.local rightStored.id) rightStored.location.bodyBytes :=
    { id := rightStored.id
      location := rightStored.location
      idExact := rfl
      locationExact := rfl
      sourceExact := rfl
      bytesExact := rfl }
  obtain ⟨rightAfter, _, rightStep, rightResult, rightRip, rightRsp,
      rightPreserved, rightMemory, rightFlags⟩ :=
    LocalExpressionCheck.preserves rightChecked program rightLoaded
  have rightResult' : rightAfter.registers 0 =
      (BitVec.ofInt 32 rightValue).setWidth 64 := by
    simpa [rightValueStored, ScalarValidator.resultRegister] using rightResult
  have rightMemory' : rightAfter.memory = stored.memory := rightMemory
  have rightRip' : rightAfter.rip = stored.rip +
      BitVec.ofNat 64 rightStored.location.bodyBytes.length := by
    simpa [rightStored] using rightRip
  have compareLoaded : CodeAt rightAfter.memory rightAfter.rip
      (frameCompareBytes slot 5) := by
    have loaded := storedInvariant.loaded
    have tail := loaded.suffix
    simpa [rightMemory', rightRip', rightLocation, List.append_assoc] using tail
  have rightCore : evalExpr 1 program coreBefore (.local rightId) =
      .done (.signed .i32 rightValue) coreBefore := by
    have idExact := environment.keyed rightId rightEntry rightFound
    have localEval := evalExpr_local_of_local? 0 program coreBefore rightEntry.id
      (.signed .i32 rightEntry.value) rightEntry.localValue
    simpa [idExact, rightValueExact] using localEval
  have coreEval : evalExpr 2 program coreBefore
      (.binary .notEqual (.local leftId) (.local rightId)) =
      .done (.boolean (leftValue != rightValue)) coreBefore := by
    apply evalExpr_binary_done (fuel := 1) program coreBefore .notEqual
      (.local leftId) (.local rightId)
      (.signed .i32 leftValue) (.signed .i32 rightValue)
      (.boolean (leftValue != rightValue)) coreBefore coreBefore leftCore rightCore
    · simp
    · have boolNe : (!(leftValue == rightValue)) = (leftValue != rightValue) := by
        rfl
      simpa [evalBinaryValue, scalarEqual, boolNe]
  have leftBits : (leftAfter.registers 0).setWidth 32 = BitVec.ofInt 32 leftValue := by
    simpa [ScalarValidator.resultRegister] using
      congrArg (fun bits : BitVec 64 => bits.setWidth 32) leftResult
  have leftSlot : read32 stored.memory
      (frameSlotAddress (leftAfter.registers rbpRegister) slot) =
      BitVec.ofInt 32 leftValue := by
    calc
      _ = (leftAfter.registers 0).setWidth 32 := by
        simpa [stored] using frameStore_slot_value leftAfter slot
      _ = _ := leftBits
  have rightRbp := rightPreserved rbpRegister (by decide) (by decide)
  have slotValue : read32 rightAfter.memory
      (rightAfter.registers rbpRegister +
        (BitVec.ofInt 32 (frameDisplacement slot)).signExtend 64) =
      BitVec.ofInt 32 leftValue := by
    calc
      _ = read32 stored.memory
          (stored.registers rbpRegister +
            (BitVec.ofInt 32 (frameDisplacement slot)).signExtend 64) := by
        rw [rightMemory', rightRbp]
      _ = read32 stored.memory (frameSlotAddress (leftAfter.registers rbpRegister) slot) := by
        simp [stored, State.store32, frameSlotAddress]
      _ = _ := by simpa [frameSlotAddress] using leftSlot
  obtain ⟨moved, loadedLeft, compared, conditioned, after,
      first, second, third, fourth, fifth, machineResult, machineRbp,
      machineMemory, machineRip⟩ :=
    frameCompare_protocol slot 5 (BitVec.ofInt 32 leftValue)
      (BitVec.ofInt 32 rightValue) rightAfter slotValue rightResult' compareLoaded
  have valueBits :
      ((BitVec.ofInt 32 leftValue != BitVec.ofInt 32 rightValue) =
        (leftValue != rightValue)) := by
    rw [Bool.eq_iff_iff]
    simp only [bne_iff_ne]
    constructor
    · intro different equal
      apply different
      exact congrArg (fun value : Int => BitVec.ofInt 32 value) equal
    · intro different equal
      apply different
      have intEqual := congrArg BitVec.toInt equal
      simpa [show (BitVec.ofInt 32 leftValue).toInt = leftValue by
        simpa [leftValueExact] using leftEntry.value_toInt,
        show (BitVec.ofInt 32 rightValue).toInt = rightValue by
          simpa [rightValueExact] using rightEntry.value_toInt] using intEqual
  have finalResult : after.registers 0 =
      (if leftValue != rightValue then (1 : BitVec 64) else 0) := by
    calc
      after.registers 0 =
          (if condition (subtractFlags rightAfter.flags
              (BitVec.ofInt 32 leftValue) (BitVec.ofInt 32 rightValue)) 5
            then (1 : BitVec 64) else 0) := machineResult
      _ = if BitVec.ofInt 32 leftValue != BitVec.ofInt 32 rightValue
            then (1 : BitVec 64) else 0 := by
        rw [compare_notEqual_condition]
      _ = _ := by rw [valueBits]
  have finalRbp : after.registers rbpRegister = machineBefore.registers rbpRegister := by
    calc
      after.registers rbpRegister = rightAfter.registers rbpRegister := machineRbp
      _ = stored.registers rbpRegister := rightRbp
      _ = leftAfter.registers rbpRegister := by simp [stored, State.store32]
      _ = machineBefore.registers rbpRegister := leftPreserved rbpRegister (by decide) (by decide)
  have finalMemory : after.memory =
      write32 machineBefore.memory
        (frameSlotAddress (machineBefore.registers rbpRegister) slot)
        (BitVec.ofInt 32 leftValue) := by
    calc
      after.memory = rightAfter.memory := machineMemory
      _ = stored.memory := rightMemory'
      _ = write32 leftAfter.memory
          (frameSlotAddress (leftAfter.registers rbpRegister) slot)
          (BitVec.ofInt 32 leftValue) := by
        simp [stored, State.store32, frameSlotAddress]
        rw [leftBits]
      _ = _ := by rw [leftMemory, leftPreserved rbpRegister (by decide) (by decide)]
  have finalRip : after.rip = machineBefore.rip + BitVec.ofNat 64
      (localNotEqualBytes left right slot).length := by
    calc
      after.rip = rightAfter.rip + BitVec.ofNat 64
          (frameCompareBytes slot 5).length := machineRip
      _ = stored.rip + BitVec.ofNat 64 rightStored.location.bodyBytes.length +
          BitVec.ofNat 64 (frameCompareBytes slot 5).length := by rw [rightRip']
      _ = leftAfter.rip + BitVec.ofNat 64 (frameStoreBytes slot).length +
          BitVec.ofNat 64 right.bodyBytes.length +
          BitVec.ofNat 64 (frameCompareBytes slot 5).length := by
        simp [stored, State.store32, rightLocation, List.append_assoc,
          BitVec.ofNat_add, BitVec.add_assoc]
      _ = machineBefore.rip + BitVec.ofNat 64
          (localNotEqualBytes left right slot).length := by
        rw [leftRip]
        simp [localNotEqualBytes, List.length_append, BitVec.ofNat_add,
          BitVec.add_assoc]
  refine ⟨after, coreEval, ?_, finalResult, finalRbp, finalMemory, finalRip⟩
  simpa using Steps.cons leftStep (Steps.cons storeStep
    (Steps.cons rightStep (Steps.cons first (Steps.cons second
      (Steps.cons third (Steps.cons fourth (Steps.cons fifth (Steps.refl after))))))))

end Lanius.X86.DynamicComparison
