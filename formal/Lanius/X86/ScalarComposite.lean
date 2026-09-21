import Lanius.X86.ScalarValidator
import Lanius.X86.Machine.FrameSlots
import Lanius.Semantics.Loop

namespace Lanius.X86.ScalarValidator

open Lanius Lanius.Core Lanius.Semantics
open Lanius.X86
open Lanius.X86.Machine

/-!
  The first compositional fragment for the actual backend.

  `compile.lani` evaluates the left operand, allocates a frame slot, stores
  EAX at `[RBP - displacement(slot)]`, evaluates the right operand, and
  `operation::from_slot` moves the right value to ECX, loads the slot into
  EAX, and applies the operation.  This file covers that protocol for scalar
  i32 literals.  It is deliberately a
  suffix certificate: the caller supplies the post-prologue state and its
  frame/code invariants.  The patched prologue is authenticated by
  `Machine.framePrologueBytes` and its reusable `framePrologue_steps` proof;
  no post-state is supplied as a semantic conclusion.

  The suffix is still the exact byte sequence emitted by the backend.  Code
  and frame disjointness are explicit because the flat machine memory model
  does not provide a memory map or stack non-aliasing assumption.
-/

def binaryEpilogueBytes : List UInt8 :=
  moveBytes .w64 rspRegister rbpRegister ++ popBytes rbpRegister ++ returnBytes

def binaryLiteralBodyBytes (operation : Alu) (left right : BitVec 32) : List UInt8 :=
  immediateBytes .w32 resultRegister left 0 ++
    frameStoreBytes 0 ++
    immediateBytes .w32 resultRegister right 0 ++
    frameAluBytes 0 operation

def binaryLiteralFunctionRest (operation : Alu) (left right : BitVec 32) : List UInt8 :=
  binaryLiteralBodyBytes operation left right ++ (binaryEpilogueBytes ++ ud2Bytes)

def binaryLiteralFunctionBytes (operation : Alu) (left right : BitVec 32) : List UInt8 :=
  framePrologueBytes 1 ++ binaryLiteralFunctionRest operation left right

def binaryCoreOperation : Alu → BinaryOp
  | .add => .add
  | .subtract => .subtract
  | .and => .bitAnd
  | .or => .bitOr
  | .xor => .bitXor

def binaryNatResult : Alu → Nat → Nat → Nat
  | .add => fun left right => left + right
  | .subtract => fun left right => left - right
  | .and => Nat.land
  | .or => Nat.lor
  | .xor => Nat.xor

def binaryCoreBody (operation : Alu) (left right : Nat) : Stmt :=
  .returnValue (some (.binary (binaryCoreOperation operation)
    (.value (.signed .i32 (Int.ofNat left)))
    (.value (.signed .i32 (Int.ofNat right)))))

def binaryCoreResult (operation : Alu) (left right : Nat) : Value :=
  .signed .i32 (Int.ofNat (binaryNatResult operation left right))

/- Initial-state separation facts for the one-slot binary protocol.  The
   operation parameter keeps this certificate reusable for another scalar ALU
   operation without putting these low-level premises on every theorem. -/
structure FrameSafety (operation : Alu) (left right : BitVec 32)
    (before : Machine.State) where
  prologueDisjoint : ∀ index, index <
      (moveBytes .w64 rbpRegister rspRegister ++
        immediateBytes .w32 r11Register (frameSizeBits 1) 0 ++
        aluBytes .w64 .subtract rspRegister r11Register).length → ∀ lane : Fin 8,
      (before.rip + BitVec.ofNat 64 ((pushBytes rbpRegister).length + index)) +
        BitVec.ofNat 64 0 ≠
      (before.registers rspRegister - 8) + BitVec.ofNat 64 lane.val
  prologueTailDisjoint : ∀ index, index <
      (binaryLiteralFunctionRest operation left right).length → ∀ lane : Fin 8,
      (before.rip + BitVec.ofNat 64 (framePrologueBytes 1).length +
        BitVec.ofNat 64 index) + BitVec.ofNat 64 0 ≠
      (before.registers rspRegister - 8) + BitVec.ofNat 64 lane.val
  bodySpillDisjoint : ∀ index, index <
      (immediateBytes .w32 resultRegister right 0 ++ frameAluBytes 0 operation).length →
      ∀ lane : Fin 4,
      ((Machine.prologueState before 1).rip + BitVec.ofNat 64
        ((immediateBytes .w32 resultRegister left 0 ++ frameStoreBytes 0).length + index)) +
          BitVec.ofNat 64 0 ≠
      ((Machine.prologueState before 1).registers rbpRegister +
        (BitVec.ofInt 32 (frameDisplacement 0)).signExtend 64) +
          BitVec.ofNat 64 lane.val
  tailSpillDisjoint : ∀ index, index <
      (binaryEpilogueBytes ++ ud2Bytes).length → ∀ lane : Fin 4,
      ((Machine.prologueState before 1).rip + BitVec.ofNat 64
        (binaryLiteralBodyBytes operation left right).length + BitVec.ofNat 64 index) +
          BitVec.ofNat 64 0 ≠
      ((Machine.prologueState before 1).registers rbpRegister +
        (BitVec.ofInt 32 (frameDisplacement 0)).signExtend 64) +
          BitVec.ofNat 64 lane.val
  spillSavedDisjoint : ∀ i : Fin 8, ∀ j : Fin 4,
      (Machine.prologueState before 1).registers rbpRegister +
          BitVec.ofNat 64 i.val ≠
        ((Machine.prologueState before 1).registers rbpRegister +
          (BitVec.ofInt 32 (frameDisplacement 0)).signExtend 64) +
            BitVec.ofNat 64 j.val
  spillReturnDisjoint : ∀ i : Fin 8, ∀ j : Fin 4,
      ((Machine.prologueState before 1).registers rbpRegister + 8) +
          BitVec.ofNat 64 i.val ≠
        ((Machine.prologueState before 1).registers rbpRegister +
          (BitVec.ofInt 32 (frameDisplacement 0)).signExtend 64) +
            BitVec.ofNat 64 j.val
  prologueReturnDisjoint : ∀ i j : Fin 8,
      before.registers rspRegister + BitVec.ofNat 64 i.val ≠
        (before.registers rspRegister - 8) + BitVec.ofNat 64 j.val
  returnAddress : Machine.Address
  returnAddress_read : read64 before.memory
    (before.registers rspRegister) = returnAddress

/- Derive the low-level obligations from the runtime-entry text/stack
   separation contract.  This is the only place that knows the byte offsets
   inside the actual one-slot function protocol. -/
def frameSafety_of_textStack
    (operation : Alu) (left right : BitVec 32) (before : Machine.State)
    (text : TextStackDisjoint before before.rip
      (binaryLiteralFunctionBytes operation left right).length)
    (returnAddress : Machine.Address)
    (returnAddress_read : read64 before.memory
      (before.registers rspRegister) = returnAddress) :
    FrameSafety operation left right before := by
  have spillAddress :
      (Machine.prologueState before 1).registers rbpRegister +
          (BitVec.ofInt 32 (frameDisplacement 0)).signExtend 64 =
        before.registers rspRegister - 16 := by
    have rbpValue : (Machine.prologueState before 1).registers rbpRegister =
        before.registers rspRegister - 8 := by
      simp [Machine.prologueState, Machine.State.alu64, Machine.State.alu,
        Machine.State.immediate32, Machine.State.move64, Machine.State.push64,
        rbpRegister, rspRegister, r11Register, frameSizeBits, frameBytes,
        Alu.result]
    have displacement :
        (BitVec.ofInt 32 (frameDisplacement 0)).signExtend 64 =
          (-8 : BitVec 64) := by decide
    rw [rbpValue, displacement]
    rw [← BitVec.sub_eq_add_neg]
    rw [BitVec.sub_sub]
    change before.registers rspRegister - BitVec.ofNat 64 (8 + 8) =
      before.registers rspRegister - BitVec.ofNat 64 16
    rfl
  refine {
    prologueDisjoint := ?_
    prologueTailDisjoint := ?_
    bodySpillDisjoint := ?_
    tailSpillDisjoint := ?_
    spillSavedDisjoint := ?_
    spillReturnDisjoint := ?_
    prologueReturnDisjoint := ?_
    returnAddress := returnAddress
    returnAddress_read := returnAddress_read }
  · intro index bound lane
    have prefixBound := Nat.add_lt_add_left bound (pushBytes rbpRegister).length
    have bound' : (pushBytes rbpRegister).length + index <
        (binaryLiteralFunctionBytes operation left right).length := by
      simp [binaryLiteralFunctionBytes, framePrologueBytes,
        binaryLiteralFunctionRest, binaryLiteralBodyBytes, binaryEpilogueBytes] at prefixBound ⊢
      omega
    have h := text ((pushBytes rbpRegister).length + index) bound' lane
    simpa [BitVec.ofNat_add, BitVec.add_assoc, BitVec.add_zero] using h.1
  · intro index bound lane
    have prefixBound := Nat.add_lt_add_left bound (framePrologueBytes 1).length
    have bound' : (framePrologueBytes 1).length + index <
        (binaryLiteralFunctionBytes operation left right).length := by
      simp [binaryLiteralFunctionBytes, binaryLiteralFunctionRest,
        binaryLiteralBodyBytes, binaryEpilogueBytes] at prefixBound ⊢
      omega
    have h := text ((framePrologueBytes 1).length + index) bound' lane
    simpa [BitVec.ofNat_add, BitVec.add_assoc, BitVec.add_zero] using h.1
  · intro index bound lane
    let lane8 : Fin 8 := ⟨lane.val, by omega⟩
    have prefixBound := Nat.add_lt_add_left bound
      ((framePrologueBytes 1).length +
        (immediateBytes .w32 resultRegister left 0 ++ frameStoreBytes 0).length)
    have bound' : (framePrologueBytes 1).length +
        (immediateBytes .w32 resultRegister left 0 ++ frameStoreBytes 0).length +
        index < (binaryLiteralFunctionBytes operation left right).length := by
      simp [binaryLiteralFunctionBytes, binaryLiteralFunctionRest,
        binaryLiteralBodyBytes, binaryEpilogueBytes] at prefixBound ⊢
      omega
    have h := text ((framePrologueBytes 1).length +
      (immediateBytes .w32 resultRegister left 0 ++ frameStoreBytes 0).length + index)
      bound' lane8
    rw [spillAddress]
    rw [framePrologue_rip]
    simpa [lane8, BitVec.ofNat_add, BitVec.add_assoc, BitVec.add_zero] using h.2
  · intro index bound lane
    let lane8 : Fin 8 := ⟨lane.val, by omega⟩
    have prefixBound := Nat.add_lt_add_left bound
      ((framePrologueBytes 1).length +
        (binaryLiteralBodyBytes operation left right).length)
    have bound' : (framePrologueBytes 1).length +
        (binaryLiteralBodyBytes operation left right).length + index <
          (binaryLiteralFunctionBytes operation left right).length := by
      simp [binaryLiteralFunctionBytes, binaryLiteralFunctionRest,
        binaryLiteralBodyBytes, binaryEpilogueBytes] at prefixBound ⊢
      omega
    have h := text ((framePrologueBytes 1).length +
      (binaryLiteralBodyBytes operation left right).length + index) bound' lane8
    rw [spillAddress]
    rw [framePrologue_rip]
    simpa [lane8, BitVec.ofNat_add, BitVec.add_assoc, BitVec.add_zero] using h.2
  · intro i j
    have n4 : (4 : Nat) ≤ 8 := by omega
    have h := stackWindow_disjoint n4
      ((Machine.prologueState before 1).registers rbpRegister) i j
    have displacement :
        (BitVec.ofInt 32 (frameDisplacement 0)).signExtend 64 =
          (-8 : BitVec 64) := by decide
    simpa only [displacement, BitVec.sub_eq_add_neg, BitVec.add_assoc] using h
  · intro i j
    have n4 : (4 : Nat) ≤ 8 := by omega
    have h := stackWindow_disjoint_afterEight n4
      ((Machine.prologueState before 1).registers rbpRegister) i j
    have displacement :
        (BitVec.ofInt 32 (frameDisplacement 0)).signExtend 64 =
          (-8 : BitVec 64) := by decide
    simpa only [displacement, BitVec.sub_eq_add_neg, BitVec.add_assoc] using h
  · intro i j
    have n8 : (8 : Nat) ≤ 8 := by omega
    exact stackWindow_disjoint n8 (before.registers rspRegister) i j

structure LiteralBinarySupported (function : Function) where
  operation : Alu
  operands : Nat × Nat
  functionIdI32 : function.id < 2147483648
  zeroParameters : function.parameters = []
  resultType : function.returnType = .scalar (.signed .i32)
  internal : function.external = none
  leftBound : operands.1 < 2 ^ 31
  rightBound : operands.2 < 2 ^ 31
  resultBound : binaryNatResult operation operands.1 operands.2 < 2 ^ 31
  subtractionBound : operation = .subtract → operands.2 ≤ operands.1
  bodyExact : function.body = some (binaryCoreBody operation operands.1 operands.2)

theorem binaryMachineResult_toNat (operation : Alu) (left right : Nat)
    (rightBound : right < 2 ^ 32)
    (subtractionBound : operation = .subtract → right ≤ left) :
    operation.result (BitVec.ofNat 32 left) (BitVec.ofNat 32 right) =
      BitVec.ofNat 32 (binaryNatResult operation left right) := by
  cases operation with
  | add =>
      simp [Alu.result, binaryNatResult]
      rw [← BitVec.ofNat_add]
  | subtract =>
      simp [Alu.result, binaryNatResult]
      have hsub : right ≤ left := subtractionBound rfl
      exact BitVec.ofNat_sub_ofNat_of_le left right rightBound hsub
  | and => simp [Alu.result, binaryNatResult, BitVec.ofNat_and]
  | or => simp [Alu.result, binaryNatResult, BitVec.ofNat_or]
  | xor => simp [Alu.result, binaryNatResult, BitVec.ofNat_xor]

theorem binaryCore_eval
    (operation : Alu) (left right : Nat)
    (leftBound : left < 2 ^ 31) (rightBound : right < 2 ^ 31)
    (resultBound : binaryNatResult operation left right < 2 ^ 31)
    (subtractionBound : operation = .subtract → right ≤ left)
    (program : Program) :
    evalBinaryValue program.target (binaryCoreOperation operation)
      (.signed .i32 (Int.ofNat left)) (.signed .i32 (Int.ofNat right)) =
        .ok (binaryCoreResult operation left right) := by
  cases operation with
  | add =>
      simp [evalBinaryValue, evalSignedBinary, binaryCoreOperation,
        binaryCoreResult, binaryNatResult]
      rw [← Int.natCast_add]
      exact wrapSigned_i32_nat_lt program.target (left + right) resultBound
  | subtract =>
      have hsub : (Int.ofNat left - Int.ofNat right) =
          Int.ofNat (left - right) := by
        symm
        exact Int.ofNat_sub (subtractionBound rfl)
      simp [evalBinaryValue, evalSignedBinary, binaryCoreOperation,
        binaryCoreResult, binaryNatResult]
      change wrapSigned program.target .i32
        (Int.ofNat left - Int.ofNat right) = Int.ofNat (left - right)
      rw [hsub]
      exact wrapSigned_i32_nat_lt program.target (left - right) resultBound
  | and =>
      simp only [binaryCoreOperation]
      rw [show evalBinaryValue program.target .bitAnd
          (.signed .i32 (Int.ofNat left)) (.signed .i32 (Int.ofNat right)) =
          evalSignedBinary program.target .bitAnd .i32
            (Int.ofNat left) (Int.ofNat right) by rfl]
      rw [evalSignedBinary_bitAnd_i32_nat program.target left right (by omega) (by omega)]
      simp only [binaryCoreResult, binaryNatResult]
      exact congrArg (fun value : Int =>
        (Except.ok (Value.signed .i32 value) : Except Trap Value))
        (wrapSigned_i32_nat_lt program.target (Nat.land left right) resultBound)
  | or =>
      simp only [binaryCoreOperation]
      rw [show evalBinaryValue program.target .bitOr
          (.signed .i32 (Int.ofNat left)) (.signed .i32 (Int.ofNat right)) =
          evalSignedBinary program.target .bitOr .i32
            (Int.ofNat left) (Int.ofNat right) by rfl]
      rw [evalSignedBinary_bitOr_i32_nat program.target left right (by omega) (by omega)]
      simp only [binaryCoreResult, binaryNatResult]
      exact congrArg (fun value : Int =>
        (Except.ok (Value.signed .i32 value) : Except Trap Value))
        (wrapSigned_i32_nat_lt program.target (Nat.lor left right) resultBound)
  | xor =>
      simp only [binaryCoreOperation]
      rw [show evalBinaryValue program.target .bitXor
          (.signed .i32 (Int.ofNat left)) (.signed .i32 (Int.ofNat right)) =
          evalSignedBinary program.target .bitXor .i32
            (Int.ofNat left) (Int.ofNat right) by rfl]
      rw [evalSignedBinary_bitXor_i32_nat program.target left right (by omega) (by omega)]
      simp only [binaryCoreResult, binaryNatResult]
      exact congrArg (fun value : Int =>
        (Except.ok (Value.signed .i32 value) : Except Trap Value))
        (wrapSigned_i32_nat_lt program.target (Nat.xor left right) resultBound)

theorem binaryCore_executes (operation : Alu) (left right : Nat)
    (leftBound : left < 2 ^ 31) (rightBound : right < 2 ^ 31)
    (resultBound : binaryNatResult operation left right < 2 ^ 31)
    (subtractionBound : operation = .subtract → right ≤ left)
    (program : Program) (before : Lanius.Semantics.State) :
    Executes program before (binaryCoreBody operation left right)
      (.returned (some (binaryCoreResult operation left right))) before := by
  refine ⟨4, ?_⟩
  apply execStmt_return 3 program before
    (.binary (binaryCoreOperation operation)
      (.value (.signed .i32 (Int.ofNat left)))
      (.value (.signed .i32 (Int.ofNat right))))
    (binaryCoreResult operation left right) before
  apply evalExpr_binary_done (fuel := 2) program before
    (binaryCoreOperation operation)
    (.value (.signed .i32 (Int.ofNat left)))
    (.value (.signed .i32 (Int.ofNat right)))
    (.signed .i32 (Int.ofNat left)) (.signed .i32 (Int.ofNat right))
    (binaryCoreResult operation left right) before before
  · exact evalExpr_value 1 program before (.signed .i32 (Int.ofNat left))
  · exact evalExpr_value 1 program before (.signed .i32 (Int.ofNat right))
  · cases operation <;> simp [binaryCoreOperation]
  · exact binaryCore_eval operation left right leftBound rightBound
      resultBound subtractionBound program

private def literalBodyState (before : Machine.State) (left : BitVec 32) : Machine.State :=
  before.immediate32 resultRegister left
    (immediateBytes .w32 resultRegister left 0).length

private def literalStoredState (before : Machine.State) (left : BitVec 32) : Machine.State :=
  (literalBodyState before left).store32 resultRegister rbpRegister
    (BitVec.ofInt 32 (frameDisplacement 0)) (frameStoreBytes 0).length

private def literalRightState (before : Machine.State) (left right : BitVec 32) : Machine.State :=
  (literalStoredState before left).immediate32 resultRegister right
    (immediateBytes .w32 resultRegister right 0).length

/- The body theorem authenticates every instruction in the actual left-store-
right-from-slot sequence.  The only memory assumptions are initial-state
invariants: the spill does not overwrite future code, and the right child
does not change RBP or the spill slot. -/
theorem binaryLiteralBody_machine
    (operation : Alu) (left right : BitVec 32) (before : Machine.State)
    (loaded : Machine.CodeAt before.memory before.rip
      (binaryLiteralBodyBytes operation left right))
    (spillDisjoint : ∀ index, index <
      (immediateBytes .w32 resultRegister right 0 ++
        frameAluBytes 0 operation).length → ∀ lane : Fin 4,
      (before.rip + BitVec.ofNat 64
        ((immediateBytes .w32 resultRegister left 0 ++ frameStoreBytes 0).length + index)) +
          BitVec.ofNat 64 0 ≠
        (before.registers rbpRegister +
          (BitVec.ofInt 32 (frameDisplacement 0)).signExtend 64) +
          BitVec.ofNat 64 lane.val)
    :
    ∃ after : Machine.State, Machine.Steps 6 before after ∧
      after.registers resultRegister = (operation.result left right).setWidth 64 ∧
      after.registers rbpRegister = before.registers rbpRegister ∧
      after.memory = Machine.write32 before.memory
        (before.registers rbpRegister +
          (BitVec.ofInt 32 (frameDisplacement 0)).signExtend 64) left ∧
      after.rip = before.rip + BitVec.ofNat 64
        (binaryLiteralBodyBytes operation left right).length := by
  let leftBytes := immediateBytes .w32 resultRegister left 0
  let storeBytes := frameStoreBytes 0
  let rightBytes := immediateBytes .w32 resultRegister right 0
  let aluBytes := frameAluBytes 0 operation
  have split : binaryLiteralBodyBytes operation left right =
      leftBytes ++ storeBytes ++ rightBytes ++ aluBytes := by
    simp [binaryLiteralBodyBytes, leftBytes, storeBytes, rightBytes, aluBytes,
      List.append_assoc]
  rw [split] at loaded
  have loaded' : CodeAt before.memory before.rip
      (leftBytes ++ (storeBytes ++ (rightBytes ++ aluBytes))) := by
    simpa [List.append_assoc] using loaded
  have leftLoaded : CodeAt before.memory before.rip leftBytes :=
    loaded'.prefix
  let leftState := literalBodyState before left
  have leftStep : Step before leftState := by
    apply immediate_step before leftState .w32 resultRegister left 0 leftLoaded
    rfl
  have tailAfterLeft : CodeAt leftState.memory leftState.rip
      (storeBytes ++ rightBytes ++ aluBytes) := by
    simpa [leftState, literalBodyState, State.immediate32, leftBytes] using
      loaded'.suffix
  have tailLeft' : CodeAt leftState.memory leftState.rip
      (storeBytes ++ (rightBytes ++ aluBytes)) := by
    simpa [List.append_assoc] using tailAfterLeft
  have storeLoaded : CodeAt leftState.memory leftState.rip storeBytes :=
    tailLeft'.prefix
  let storedState := literalStoredState before left
  have storeStep : Step leftState storedState := by
    apply frameStore_step leftState storedState 0 storeLoaded
    rfl
  have tailAfterStore : CodeAt storedState.memory storedState.rip
      (rightBytes ++ aluBytes) := by
    have source := tailLeft'.suffix
    have protectedCode := CodeAt.write32
      (address := leftState.registers rbpRegister +
        (BitVec.ofInt 32 (frameDisplacement 0)).signExtend 64) source
      ((leftState.registers resultRegister).setWidth 32)
      (by
        intro index bound lane
        simpa [leftState, literalBodyState, State.immediate32, leftBytes, storeBytes,
          Nat.add_assoc, Nat.add_zero, BitVec.ofNat_add, BitVec.add_assoc,
          rbpRegister, resultRegister] using
          spillDisjoint index bound lane)
    simpa only [storedState, literalStoredState, leftState, literalBodyState,
      State.store32, State.immediate32, storeBytes, BitVec.ofNat_add,
      BitVec.add_assoc] using protectedCode
  have rightLoaded : CodeAt storedState.memory storedState.rip rightBytes :=
    tailAfterStore.prefix
  let rightState := literalRightState before left right
  have rightStep : Step storedState rightState := by
    apply immediate_step storedState rightState .w32 resultRegister right 0 rightLoaded
    rfl
  have tailAfterRight : CodeAt rightState.memory rightState.rip aluBytes := by
    have source := tailAfterStore.suffix
    simpa [rightState, storedState, literalRightState, literalStoredState, leftState,
      literalBodyState, State.immediate32, rightBytes] using source
  have rightResult : rightState.registers resultRegister = right.setWidth 64 := by
    simp [rightState, literalRightState, literalStoredState, literalBodyState,
      State.immediate32, resultRegister]
  have rightRbp : rightState.registers rbpRegister =
      storedState.registers rbpRegister := by
    simp [rightState, literalRightState, storedState, literalStoredState,
      State.immediate32, rbpRegister, resultRegister]
  have rightSlot : read32 rightState.memory
        (frameSlotAddress (storedState.registers rbpRegister) 0) =
      read32 storedState.memory
        (frameSlotAddress (storedState.registers rbpRegister) 0) := by
    simp [rightState, literalRightState, storedState, literalStoredState,
      State.immediate32, rbpRegister, resultRegister]
  have leftValue : (leftState.registers resultRegister).setWidth 32 = left := by
    simp [leftState, literalBodyState, State.immediate32, resultRegister]
  have rightSteps : Machine.Steps 1 storedState rightState := by
    exact Machine.Steps.cons rightStep (Machine.Steps.refl rightState)
  obtain ⟨after, second, result, afterRbp, afterMemory, afterRip⟩ :=
    frameStore_then_alu_protocol 1 0 operation left right leftState storedState rightState
      storeLoaded rfl leftValue rightSteps rightRbp rightSlot rightResult tailAfterRight
  refine ⟨after, ?_, result, ?_, ?_, ?_⟩
  have first : Machine.Steps 1 before leftState :=
    Machine.Steps.cons leftStep (Machine.Steps.refl leftState)
  simpa using first.trans second
  · calc
      after.registers rbpRegister = leftState.registers rbpRegister := afterRbp
      _ = before.registers rbpRegister := by
        simp [leftState, literalBodyState, State.immediate32, rbpRegister, resultRegister]
  · calc
      after.memory = rightState.memory := afterMemory
      _ = Machine.write32 before.memory
        (before.registers rbpRegister +
          (BitVec.ofInt 32 (frameDisplacement 0)).signExtend 64) left := by
          simp [rightState, literalRightState, storedState, literalStoredState,
            leftState, literalBodyState, State.immediate32, State.store32,
            rbpRegister, resultRegister, leftValue]
  · calc
      after.rip = rightState.rip + BitVec.ofNat 64
        (frameAluBytes 0 operation).length := afterRip
      _ = before.rip + BitVec.ofNat 64
        (binaryLiteralBodyBytes operation left right).length := by
          simp [rightState, literalRightState, storedState, literalStoredState,
            leftState, literalBodyState, State.immediate32, State.store32,
            binaryLiteralBodyBytes,
            BitVec.ofNat_add, BitVec.add_assoc]

/- The backend epilogue is also kept separate from the prologue theorem.  Its
   only stack obligations are the explicit saved-RBP and return-address reads
   below; it does not assume a claimed post-state. -/
theorem binaryEpilogue_machine (before : Machine.State) (result : BitVec 64)
    (loaded : CodeAt before.memory before.rip binaryEpilogueBytes)
    (savedFrame returnAddress : Machine.Address)
    (savedFrame_read : Machine.read64 before.memory
      (before.registers rbpRegister) = savedFrame)
    (returnAddress_read : Machine.read64 before.memory
      (before.registers rbpRegister + 8) = returnAddress)
    (bodyResult : before.registers resultRegister = result) :
    ∃ after : Machine.State, Machine.Steps 3 before after ∧
      after.registers resultRegister = result ∧
      after.registers rbpRegister = savedFrame ∧
      after.registers rspRegister = before.registers rbpRegister + 16 ∧
      after.rip = returnAddress ∧ after.memory = before.memory ∧
      after.flags = before.flags := by
  let after := Machine.epilogueState before
  have steps := Machine.frameEpilogue_steps before loaded
  refine ⟨after, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩
  · simpa [after] using steps
  · simp [after, Machine.epilogueState, Machine.State.returnNear,
      Machine.State.pop64, Machine.State.move64, resultRegister, rbpRegister,
      rspRegister]
    exact bodyResult
  · simp [after, Machine.epilogueState, Machine.State.returnNear,
      Machine.State.pop64, Machine.State.move64, rbpRegister, rspRegister]
    exact savedFrame_read
  · simp [after, Machine.epilogueState, Machine.State.returnNear,
      Machine.State.pop64, Machine.State.move64, rbpRegister, rspRegister]
    rw [BitVec.add_assoc]
    have eight : (8 : BitVec 64) + (8 : BitVec 64) = 16 := by decide
    exact congrArg (fun value : BitVec 64 => before.registers rbpRegister + value) eight
  · simp [after, Machine.epilogueState, Machine.State.returnNear,
      Machine.State.pop64, Machine.State.move64, rbpRegister, rspRegister]
    exact returnAddress_read
  · rfl
  · rfl

/- The full emitted binary function.  The authenticated span includes
   backend::compile's unreachable UD2 after RET; only the finite prefix up to
   RET is executed.  Every stack/code non-aliasing fact is an initial-state
   invariant, because the flat memory model does not infer a memory map. -/
theorem binaryLiteralFunction_machine
    (operation : Alu) (left right : BitVec 32) (before : Machine.State)
    (loaded : CodeAt before.memory before.rip
      (binaryLiteralFunctionBytes operation left right))
    (safety : FrameSafety operation left right before) :
    ∃ after : Machine.State, Machine.Steps 13 before after ∧
      after.registers resultRegister = (operation.result left right).setWidth 64 ∧
      after.rip = safety.returnAddress ∧
      after.registers rspRegister = before.registers rspRegister + 8 ∧
      after.memory = Machine.write32
        (Machine.write64 before.memory
          (before.registers rspRegister - 8) (before.registers rbpRegister))
        (before.registers rspRegister - 16) left := by
  have loadedFull : CodeAt before.memory before.rip
      (framePrologueBytes 1 ++ binaryLiteralFunctionRest operation left right) := by
    simpa [binaryLiteralFunctionBytes, binaryLiteralFunctionRest,
      binaryLiteralBodyBytes, binaryEpilogueBytes,
      List.append_assoc] using loaded
  have loadedPrologue := loadedFull.prefix
  have prologueRun := framePrologue_steps 1 before loadedPrologue safety.prologueDisjoint
  have loadedRest : CodeAt (Machine.prologueState before 1).memory
      (Machine.prologueState before 1).rip
        (binaryLiteralFunctionRest operation left right) := by
    apply framePrologue_tail 1 before (binaryLiteralFunctionRest operation left right) loadedFull
    simpa using safety.prologueTailDisjoint
  have loadedBody := loadedRest.prefix
  have loadedTailBeforeBody := loadedRest.suffix
  obtain ⟨bodyAfter, bodyRun, bodyResult, bodyRbp, bodyMemory, bodyRip⟩ :=
    binaryLiteralBody_machine operation left right (Machine.prologueState before 1)
      loadedBody safety.bodySpillDisjoint
  have loadedTailAfterBody : CodeAt bodyAfter.memory bodyAfter.rip
      (binaryEpilogueBytes ++ ud2Bytes) := by
    have source := loadedTailBeforeBody
    have protectedCode := CodeAt.write32
      (address := (Machine.prologueState before 1).registers rbpRegister +
        (BitVec.ofInt 32 (frameDisplacement 0)).signExtend 64) source left (by
          intro index bound lane
          simpa only [BitVec.ofNat_add, BitVec.add_assoc, BitVec.add_zero] using
            safety.tailSpillDisjoint index bound lane)
    simpa [bodyMemory, bodyRip, binaryLiteralFunctionRest,
      binaryLiteralBodyBytes, Machine.prologueState] using protectedCode
  have savedRead : read64 bodyAfter.memory
      (bodyAfter.registers rbpRegister) = before.registers rbpRegister := by
    rw [bodyRbp, bodyMemory]
    rw [read64_write32_frame _ _ _ _ safety.spillSavedDisjoint]
    change read64 (Machine.write64 before.memory
      (before.registers rspRegister - 8) (before.registers rbpRegister))
        (before.registers rspRegister - 8) = before.registers rbpRegister
    exact read64_write64 _ _ _
  have returnRead : read64 bodyAfter.memory
      (bodyAfter.registers rbpRegister + 8) = safety.returnAddress := by
    rw [bodyRbp, bodyMemory]
    rw [read64_write32_frame _ _ _ _ safety.spillReturnDisjoint]
    change read64 (Machine.write64 before.memory
      (before.registers rspRegister - 8) (before.registers rbpRegister))
        ((before.registers rspRegister - 8) + 8) = safety.returnAddress
    rw [BitVec.sub_add_cancel]
    rw [read64_frame _ _ _ _ safety.prologueReturnDisjoint]
    exact safety.returnAddress_read
  have loadedEpilogue := loadedTailAfterBody.prefix
  obtain ⟨after, epilogueRun, finalResult, finalRbp, finalRsp, finalRip,
    finalMemory, _⟩ :=
    binaryEpilogue_machine bodyAfter ((operation.result left right).setWidth 64) loadedEpilogue
      (before.registers rbpRegister) safety.returnAddress savedRead returnRead bodyResult
  have finalStack : after.registers rspRegister = before.registers rspRegister + 8 := by
    rw [finalRsp, bodyRbp]
    simp [Machine.prologueState, Machine.State.push64, Machine.State.move64,
      Machine.State.immediate32, Machine.State.alu64, Machine.State.alu,
      rbpRegister, rspRegister, r11Register, frameSizeBits, frameBytes,
      BitVec.sub_eq_add_neg, BitVec.add_assoc]
  have finalMemory' : after.memory = Machine.write32
      (Machine.write64 before.memory
        (before.registers rspRegister - 8) (before.registers rbpRegister))
      (before.registers rspRegister - 16) left := by
    have spillAddress :
        (Machine.prologueState before 1).registers rbpRegister +
            (BitVec.ofInt 32 (frameDisplacement 0)).signExtend 64 =
          before.registers rspRegister - 16 := by
      have rbpValue : (Machine.prologueState before 1).registers rbpRegister =
          before.registers rspRegister - 8 := by
        simp [Machine.prologueState, Machine.State.alu64, Machine.State.alu,
          Machine.State.immediate32, Machine.State.move64, Machine.State.push64,
          rbpRegister, rspRegister, r11Register, frameSizeBits, frameBytes,
          Alu.result]
      have displacement :
          (BitVec.ofInt 32 (frameDisplacement 0)).signExtend 64 =
            (-8 : BitVec 64) := by decide
      rw [rbpValue, displacement]
      rw [← BitVec.sub_eq_add_neg, BitVec.sub_sub]
      change before.registers rspRegister - BitVec.ofNat 64 (8 + 8) =
        before.registers rspRegister - BitVec.ofNat 64 16
      rfl
    rw [finalMemory, bodyMemory]
    rw [spillAddress]
    simp [Machine.prologueState, Machine.State.push64, Machine.State.move64,
      Machine.State.immediate32, Machine.State.alu64, Machine.State.alu,
      rbpRegister, rspRegister, r11Register, frameSizeBits, frameBytes,
      BitVec.sub_eq_add_neg, BitVec.add_assoc]
  refine ⟨after, ?_, finalResult, finalRip, finalStack, finalMemory'⟩
  simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using
    prologueRun.trans (bodyRun.trans epilogueRun)

theorem LiteralBinarySupported.preserves (checked : LiteralBinarySupported function)
    (program : Program) (coreBefore : Lanius.Semantics.State)
    (machineBefore : Machine.State) (emitted : List UInt8)
    (bytesExact : emitted = binaryLiteralFunctionBytes checked.operation
      (BitVec.ofNat 32 checked.operands.1)
      (BitVec.ofNat 32 checked.operands.2))
    (loaded : Machine.CodeAt machineBefore.memory machineBefore.rip emitted)
    (textStack : TextStackDisjoint machineBefore machineBefore.rip emitted.length)
    (returnAddress : Machine.Address)
    (poppedReturn : Machine.read64 machineBefore.memory
      (machineBefore.registers rspRegister) = returnAddress) :
    function.body = some (binaryCoreBody checked.operation
      checked.operands.1 checked.operands.2) ∧
      Executes program coreBefore
        (binaryCoreBody checked.operation checked.operands.1 checked.operands.2)
        (.returned (some (binaryCoreResult checked.operation
          checked.operands.1 checked.operands.2))) coreBefore ∧
      ∃ after : Machine.State, Machine.Steps 13 machineBefore after ∧
        after.registers resultRegister =
          (checked.operation.result
            (BitVec.ofNat 32 checked.operands.1)
            (BitVec.ofNat 32 checked.operands.2)).setWidth 64 ∧
        after.rip = returnAddress ∧
        after.registers rspRegister = machineBefore.registers rspRegister + 8 ∧
        after.memory = Machine.write32
          (Machine.write64 machineBefore.memory
            (machineBefore.registers rspRegister - 8)
            (machineBefore.registers rbpRegister))
          (machineBefore.registers rspRegister - 16)
          (BitVec.ofNat 32 checked.operands.1) := by
  refine ⟨checked.bodyExact,
    binaryCore_executes checked.operation checked.operands.1 checked.operands.2
      checked.leftBound checked.rightBound checked.resultBound
      checked.subtractionBound program coreBefore, ?_⟩
  rw [bytesExact] at loaded
  rw [bytesExact] at textStack
  have safety := frameSafety_of_textStack checked.operation
    (BitVec.ofNat 32 checked.operands.1) (BitVec.ofNat 32 checked.operands.2)
    machineBefore textStack returnAddress poppedReturn
  have result := binaryLiteralFunction_machine checked.operation
    (BitVec.ofNat 32 checked.operands.1) (BitVec.ofNat 32 checked.operands.2)
    machineBefore loaded safety
  have safetyAddress : safety.returnAddress = returnAddress := by
    exact safety.returnAddress_read.symm.trans poppedReturn
  rw [safetyAddress] at result
  exact result

end Lanius.X86.ScalarValidator
