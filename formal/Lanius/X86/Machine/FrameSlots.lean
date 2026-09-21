import Lanius.X86.Machine.Encoding

namespace Lanius.X86.Machine

/-!
  Layout facts for the frame-slot protocol in `verified_compiler/src/backend`.

  The backend's `frame::displacement(slot)` is `-(slot + 1) * 8`, relative to
  RBP.  `frame::bytes(slots)` rounds the required words to a 16-byte frame.
  These definitions deliberately model that source protocol rather than a
  register-only expression lowering.
-/

def rbpRegister : Register := 5
def rspRegister : Register := 4
def rcxRegister : Register := 1
def r11Register : Register := 11

/- A compact runtime-entry memory contract for a function image.  It says the
   image's text does not overlap either the saved-return-address word or the
   first frame slot that the one-slot backend allocates.  The scalar function
   proof derives all of its instruction-specific disjointness obligations
   from this single high-level fact. -/
def TextStackDisjoint (before : State) (code : Address) (length : Nat) : Prop :=
  ∀ index, index < length → ∀ lane : Fin 8,
    code + BitVec.ofNat 64 index ≠
        before.registers rspRegister - 8 + BitVec.ofNat 64 lane.val ∧
      code + BitVec.ofNat 64 index ≠
        before.registers rspRegister - 16 + BitVec.ofNat 64 lane.val

theorem stackWindow_disjoint {n : Nat} (nBound : n ≤ 8) (base : Address)
    (i : Fin 8) (j : Fin n) :
    base + BitVec.ofNat 64 i.val ≠ base - 8 + BitVec.ofNat 64 j.val := by
  intro h
  have hbase : base + BitVec.ofNat 64 i.val =
      base + ((- (8 : BitVec 64)) + BitVec.ofNat 64 j.val) := by
    simpa [BitVec.sub_eq_add_neg, BitVec.add_assoc] using h
  have h' : BitVec.ofNat 64 i.val =
      (- (8 : BitVec 64)) + BitVec.ofNat 64 j.val :=
    (BitVec.add_right_inj base).mp hbase
  have hi := i.isLt
  have negEight : (- (8 : BitVec 64)).toNat = 2^64 - 8 := by decide
  have hto := congrArg BitVec.toNat h'
  rw [BitVec.toNat_add, negEight, BitVec.toNat_ofNat] at hto
  rw [BitVec.toNat_ofNat] at hto
  have hj64 : j.val % 2^64 = j.val := Nat.mod_eq_of_lt (by omega)
  rw [hj64] at hto
  have hn : 2^64 - 8 + j.val < 2^64 := by omega
  rw [Nat.mod_eq_of_lt hn] at hto
  have hi64 : i.val % 2^64 = i.val := Nat.mod_eq_of_lt (by omega)
  rw [hi64] at hto
  omega

theorem stackWindow_disjoint_afterEight {n : Nat} (nBound : n ≤ 8)
    (base : Address) (i : Fin 8) (j : Fin n) :
    base + 8 + BitVec.ofNat 64 i.val ≠ base - 8 + BitVec.ofNat 64 j.val := by
  intro h
  have hbase : base + ((8 : BitVec 64) + BitVec.ofNat 64 i.val) =
      base + ((- (8 : BitVec 64)) + BitVec.ofNat 64 j.val) := by
    simpa [BitVec.sub_eq_add_neg, BitVec.add_assoc] using h
  have h' : (8 : BitVec 64) + BitVec.ofNat 64 i.val =
      (- (8 : BitVec 64)) + BitVec.ofNat 64 j.val :=
    (BitVec.add_right_inj base).mp hbase
  have hi := i.isLt
  have eight : (8 : BitVec 64).toNat = 8 := by decide
  have negEight : (- (8 : BitVec 64)).toNat = 2^64 - 8 := by decide
  have left8 : ((8 : BitVec 64) + BitVec.ofNat 64 i.val).toNat = 8 + i.val := by
    rw [BitVec.toNat_add, eight, BitVec.toNat_ofNat]
    have hi64 : i.val % 2^64 = i.val := Nat.mod_eq_of_lt (by omega)
    rw [hi64]
    exact Nat.mod_eq_of_lt (by omega)
  have hto := congrArg BitVec.toNat h'
  rw [left8, BitVec.toNat_add, negEight, BitVec.toNat_ofNat] at hto
  have hj64 : j.val % 2^64 = j.val := Nat.mod_eq_of_lt (by omega)
  rw [hj64] at hto
  have hn : 2^64 - 8 + j.val < 2^64 := by omega
  rw [Nat.mod_eq_of_lt hn] at hto
  omega

def frameDisplacement (slot : Nat) : Int :=
  -Int.ofNat ((slot + 1) * 8)

def frameBytes (slots : Nat) : Nat := ((slots + 1) / 2) * 16

def frameSlotAddress (rbp : Address) (slot : Nat) : Address :=
  rbp + (BitVec.ofInt 32 (frameDisplacement slot)).signExtend 64

def frameStoreBytes (slot : Nat) : List UInt8 :=
  memoryBytes .w32 false 0 rbpRegister (frameDisplacement slot)

def frameLoadBytes (slot : Nat) : List UInt8 :=
  memoryBytes .w32 true 0 rbpRegister (frameDisplacement slot)

def rightToRcxBytes : List UInt8 := moveBytes .w32 rcxRegister 0

def frameAluBytes (slot : Nat) (operation : Alu) : List UInt8 :=
  rightToRcxBytes ++ frameLoadBytes slot ++ aluBytes .w32 operation 0 rcxRegister

def frameMultiplyBytes (slot : Nat) : List UInt8 :=
  rightToRcxBytes ++ frameLoadBytes slot ++ multiplyBytes .w32 0 rcxRegister

def frameSizeBits (slots : Nat) : BitVec 32 := BitVec.ofNat 32 (frameBytes slots)

def framePrologueSkeleton (_slots : Nat) : List UInt8 :=
  pushBytes rbpRegister ++ moveBytes .w64 rbpRegister rspRegister ++
    immediateBytes .w32 r11Register 0 0 ++
    aluBytes .w64 .subtract rspRegister r11Register

def framePrologueBytes (slots : Nat) : List UInt8 :=
  pushBytes rbpRegister ++ moveBytes .w64 rbpRegister rspRegister ++
    immediateBytes .w32 r11Register (frameSizeBits slots) 0 ++
    aluBytes .w64 .subtract rspRegister r11Register

def framePatchOffset : Nat :=
  (pushBytes rbpRegister).length + (moveBytes .w64 rbpRegister rspRegister).length + 2

def frameProloguePrefix : List UInt8 :=
  pushBytes rbpRegister ++ moveBytes .w64 rbpRegister rspRegister ++ [65, 187]

def framePrologueSuffix : List UInt8 :=
  aluBytes .w64 .subtract rspRegister r11Register

theorem frameImmediate_zero :
    immediateBytes .w32 r11Register 0 0 = [65, 187, 0, 0, 0, 0] := by decide

theorem frameImmediate_patch (slots : Nat) :
    immediateBytes .w32 r11Register (frameSizeBits slots) 0 =
      [65, 187] ++ displacementBytes (frameSizeBits slots) := by
  have rex : X86.Register.value .w32 0 r11Register false = 65 := by decide
  have opcode : 184 + UInt8.ofNat (r11Register.val % 8) = 187 := by decide
  simp [immediateBytes, rex, opcode]

theorem framePrologue_patch (slots : Nat) :
    framePrologueSkeleton slots =
      frameProloguePrefix ++ displacementBytes 0 ++ framePrologueSuffix := by
  rw [framePrologueSkeleton, frameImmediate_zero]
  simp [frameProloguePrefix, framePrologueSuffix, displacementBytes,
    wordBytes, List.append_assoc]

theorem framePrologue_patched (slots : Nat) :
    framePrologueBytes slots =
      frameProloguePrefix ++ displacementBytes (frameSizeBits slots) ++
        framePrologueSuffix := by
  rw [framePrologueBytes, frameImmediate_patch]
  simp [frameProloguePrefix, framePrologueSuffix, List.append_assoc]

theorem frameBytes_pos {slots : Nat} (positive : 0 < slots) : 0 < frameBytes slots := by
  unfold frameBytes
  omega

theorem frameSlot_bytes_bound {slot slots : Nat} (inFrame : slot < slots) :
    (slot + 1) * 8 ≤ frameBytes slots := by
  unfold frameBytes
  omega

theorem frameStore_decodes (slot : Nat) :
    decode (frameStoreBytes slot) =
      some (.store32 0 rbpRegister
        (BitVec.ofInt 32 (frameDisplacement slot)), (frameStoreBytes slot).length) := by
  simpa [frameStoreBytes, memoryInstruction] using
    memory_decodes .w32 false 0 rbpRegister (frameDisplacement slot) []

theorem frameLoad_decodes (slot : Nat) :
    decode (frameLoadBytes slot) =
      some (.load32 0 rbpRegister
        (BitVec.ofInt 32 (frameDisplacement slot)), (frameLoadBytes slot).length) := by
  simpa [frameLoadBytes, memoryInstruction] using
    memory_decodes .w32 true 0 rbpRegister (frameDisplacement slot) []

theorem rightToRcx_decodes :
    decode rightToRcxBytes =
      some (.move32 rcxRegister 0, rightToRcxBytes.length) := by
  simpa [rightToRcxBytes, moveInstruction] using move_decodes .w32 rcxRegister 0

theorem frameAlu_decodes (_slot : Nat) (operation : Alu) :
    decode (aluBytes .w32 operation 0 rcxRegister) =
      some (.alu32 operation 0 rcxRegister,
        (aluBytes .w32 operation 0 rcxRegister).length) :=
  alu_decodes .w32 operation 0 rcxRegister

theorem frameMultiply_decodes :
    decode (multiplyBytes .w32 0 rcxRegister) =
      some (.multiply32 0 rcxRegister,
        (multiplyBytes .w32 0 rcxRegister).length) :=
  multiply_decodes .w32 0 rcxRegister

theorem frameStore_step (before after : State) (slot : Nat)
    (loaded : CodeAt before.memory before.rip (frameStoreBytes slot))
    (result : after = before.store32 0 rbpRegister
      (BitVec.ofInt 32 (frameDisplacement slot)) (frameStoreBytes slot).length) :
    Step before after := by
  exact Step.decoded (frameStoreBytes slot) loaded
    (.store32 0 rbpRegister (BitVec.ofInt 32 (frameDisplacement slot)))
    (frameStoreBytes slot).length (frameStore_decodes slot) result

theorem frameLoad_step (before after : State) (slot : Nat)
    (loaded : CodeAt before.memory before.rip (frameLoadBytes slot))
    (result : after = before.load32 0 rbpRegister
      (BitVec.ofInt 32 (frameDisplacement slot)) (frameLoadBytes slot).length) :
    Step before after := by
  exact Step.decoded (frameLoadBytes slot) loaded
    (.load32 0 rbpRegister (BitVec.ofInt 32 (frameDisplacement slot)))
    (frameLoadBytes slot).length (frameLoad_decodes slot) result

theorem rightToRcx_step (before after : State)
    (loaded : CodeAt before.memory before.rip rightToRcxBytes)
    (result : after = before.move32 rcxRegister 0 rightToRcxBytes.length) :
    Step before after := by
  exact move_step before after .w32 rcxRegister 0 loaded result

theorem frameAlu_step (before after : State) (operation : Alu)
    (loaded : CodeAt before.memory before.rip (aluBytes .w32 operation 0 rcxRegister))
    (auxiliary : Bool)
    (result : after = before.alu32 operation 0 rcxRegister auxiliary
      (aluBytes .w32 operation 0 rcxRegister).length) :
    Step before after := by
  exact alu_step .w32 before after operation 0 rcxRegister loaded auxiliary result

theorem frameMultiply_step (before after : State)
    (loaded : CodeAt before.memory before.rip (multiplyBytes .w32 0 rcxRegister))
    (flags : BitVec 64)
    (result : after = before.multiply 32 0 rcxRegister flags
      (multiplyBytes .w32 0 rcxRegister).length) :
    Step before after := by
  exact multiply_step .w32 before after 0 rcxRegister loaded flags result

theorem frameStore_slot_value (before : State) (slot : Nat) :
    read32 (before.store32 0 rbpRegister
      (BitVec.ofInt 32 (frameDisplacement slot))
      (frameStoreBytes slot).length).memory
      (frameSlotAddress (before.registers rbpRegister) slot) =
      (before.registers 0).setWidth 32 := by
  unfold State.store32 frameSlotAddress
  exact read32_write32 _ _ _

theorem frameStore_slot_value_after_frame_stable
    (before after : State) (slot : Nat)
    (sameRbp : after.registers rbpRegister = before.registers rbpRegister)
    (sameSlot : read32 after.memory
      (frameSlotAddress (before.registers rbpRegister) slot) =
      read32 (before.store32 0 rbpRegister
        (BitVec.ofInt 32 (frameDisplacement slot))
        (frameStoreBytes slot).length).memory
        (frameSlotAddress (before.registers rbpRegister) slot)) :
    read32 after.memory
      (after.registers rbpRegister +
        (BitVec.ofInt 32 (frameDisplacement slot)).signExtend 64) =
      (before.registers 0).setWidth 32 := by
  rw [sameRbp]
  simpa [frameSlotAddress] using sameSlot.trans (frameStore_slot_value before slot)

theorem frameAlu_protocol (slot : Nat) (operation : Alu)
    (leftValue rightValue : BitVec 32) (rightState : State)
    (slotValue : read32 rightState.memory
      (rightState.registers rbpRegister +
        (BitVec.ofInt 32 (frameDisplacement slot)).signExtend 64) = leftValue)
    (rightResult : rightState.registers 0 = rightValue.setWidth 64)
    (loaded : CodeAt rightState.memory rightState.rip
      (frameAluBytes slot operation)) :
    ∃ moved loadedLeft after, Step rightState moved ∧ Step moved loadedLeft ∧
      Step loadedLeft after ∧
      after.registers 0 = (operation.result leftValue rightValue).setWidth 64 ∧
      after.registers rbpRegister = rightState.registers rbpRegister ∧
      after.memory = rightState.memory ∧
      after.rip = rightState.rip + BitVec.ofNat 64 (frameAluBytes slot operation).length := by
  let moved := rightState.move32 rcxRegister 0 rightToRcxBytes.length
  let loadedLeft := moved.load32 0 rbpRegister
    (BitVec.ofInt 32 (frameDisplacement slot)) (frameLoadBytes slot).length
  let after := loadedLeft.alu32 operation 0 rcxRegister false
    (aluBytes .w32 operation 0 rcxRegister).length
  have loaded' : CodeAt rightState.memory rightState.rip
      (rightToRcxBytes ++ (frameLoadBytes slot ++
        aluBytes .w32 operation 0 rcxRegister)) := by
    simpa [frameAluBytes, List.append_assoc] using loaded
  have rightLoaded : CodeAt rightState.memory rightState.rip rightToRcxBytes :=
    loaded'.prefix
  have leftLoaded : CodeAt moved.memory moved.rip (frameLoadBytes slot) := by
    have suffix := loaded'.suffix
    have suffix' : CodeAt moved.memory moved.rip
        (frameLoadBytes slot ++ aluBytes .w32 operation 0 rcxRegister) := by
      simpa [moved, State.move32] using suffix
    exact suffix'.prefix
  have operationLoaded : CodeAt loadedLeft.memory loadedLeft.rip
      (aluBytes .w32 operation 0 rcxRegister) := by
    have suffix := loaded'.suffix
    have suffix' : CodeAt moved.memory moved.rip
        (frameLoadBytes slot ++ aluBytes .w32 operation 0 rcxRegister) := by
      simpa [moved, State.move32] using suffix
    have tail := suffix'.suffix
    simpa [loadedLeft, moved, State.move32, State.load32, State.immediate32,
      rbpRegister, rcxRegister] using tail
  have first := rightToRcx_step rightState moved rightLoaded (by rfl)
  have second := frameLoad_step moved loadedLeft slot leftLoaded (by rfl)
  have third := frameAlu_step loadedLeft after operation operationLoaded false (by rfl)
  refine ⟨moved, loadedLeft, after, first, second, third, ?_, ?_, ?_, ?_⟩
  have slotValue' : read32 rightState.memory
      (rightState.registers 5 +
        (BitVec.ofInt 32 (frameDisplacement slot)).signExtend 64) = leftValue := by
    simpa [rbpRegister] using slotValue
  have leftRegister : (loadedLeft.registers 0).setWidth 32 = leftValue := by
    simp [loadedLeft, moved, State.load32, State.immediate32, State.move32,
      rbpRegister, rcxRegister, slotValue']
  have rightRegister : (loadedLeft.registers rcxRegister).setWidth 32 = rightValue := by
    simpa [loadedLeft, moved, State.load32, State.immediate32, State.move32,
      rbpRegister, rcxRegister] using
      congrArg (fun value : BitVec 64 => value.setWidth 32) rightResult
  · simp [after, State.alu32, State.alu, leftRegister, rightRegister]
  · rfl
  · rfl
  · simp [after, loadedLeft, moved, State.alu32, State.alu, State.load32,
      State.immediate32, State.move32, rbpRegister, rcxRegister,
      BitVec.ofNat_add, BitVec.add_assoc, frameAluBytes, rightToRcxBytes]

theorem frameMultiply_protocol (slot : Nat)
    (leftValue rightValue : BitVec 32) (rightState : State)
    (slotValue : read32 rightState.memory
      (rightState.registers rbpRegister +
        (BitVec.ofInt 32 (frameDisplacement slot)).signExtend 64) = leftValue)
    (rightResult : rightState.registers 0 = rightValue.setWidth 64)
    (loaded : CodeAt rightState.memory rightState.rip
      (frameMultiplyBytes slot)) :
    ∃ moved loadedLeft after, Step rightState moved ∧ Step moved loadedLeft ∧
      Step loadedLeft after ∧
      after.registers 0 = (leftValue * rightValue).setWidth 64 ∧
      after.registers rbpRegister = rightState.registers rbpRegister ∧
      after.memory = rightState.memory ∧
      after.rip = rightState.rip + BitVec.ofNat 64
        (frameMultiplyBytes slot).length := by
  let moved := rightState.move32 rcxRegister 0 rightToRcxBytes.length
  let loadedLeft := moved.load32 0 rbpRegister
    (BitVec.ofInt 32 (frameDisplacement slot)) (frameLoadBytes slot).length
  let after := loadedLeft.multiply 32 0 rcxRegister 0
    (multiplyBytes .w32 0 rcxRegister).length
  have loaded' : CodeAt rightState.memory rightState.rip
      (rightToRcxBytes ++ (frameLoadBytes slot ++
        multiplyBytes .w32 0 rcxRegister)) := by
    simpa [frameMultiplyBytes, List.append_assoc] using loaded
  have rightLoaded : CodeAt rightState.memory rightState.rip rightToRcxBytes :=
    loaded'.prefix
  have leftLoaded : CodeAt moved.memory moved.rip (frameLoadBytes slot) := by
    have suffix := loaded'.suffix
    have suffix' : CodeAt moved.memory moved.rip
        (frameLoadBytes slot ++ multiplyBytes .w32 0 rcxRegister) := by
      simpa [moved, State.move32] using suffix
    exact suffix'.prefix
  have operationLoaded : CodeAt loadedLeft.memory loadedLeft.rip
      (multiplyBytes .w32 0 rcxRegister) := by
    have suffix := loaded'.suffix
    have suffix' : CodeAt moved.memory moved.rip
        (frameLoadBytes slot ++ multiplyBytes .w32 0 rcxRegister) := by
      simpa [moved, State.move32] using suffix
    have tail := suffix'.suffix
    simpa [loadedLeft, moved, State.move32, State.load32, State.immediate32,
      rbpRegister, rcxRegister] using tail
  have first := rightToRcx_step rightState moved rightLoaded (by rfl)
  have second := frameLoad_step moved loadedLeft slot leftLoaded (by rfl)
  have third := frameMultiply_step loadedLeft after operationLoaded 0 (by rfl)
  refine ⟨moved, loadedLeft, after, first, second, third, ?_, ?_, ?_, ?_⟩
  have slotValue' : read32 rightState.memory
      (rightState.registers 5 +
        (BitVec.ofInt 32 (frameDisplacement slot)).signExtend 64) = leftValue := by
    simpa [rbpRegister] using slotValue
  have leftRegister : (loadedLeft.registers 0).setWidth 32 = leftValue := by
    simp [loadedLeft, moved, State.load32, State.immediate32, State.move32,
      rbpRegister, rcxRegister, slotValue']
  have rightRegister : (loadedLeft.registers rcxRegister).setWidth 32 = rightValue := by
    simpa [loadedLeft, moved, State.load32, State.immediate32, State.move32,
      rbpRegister, rcxRegister] using
      congrArg (fun value : BitVec 64 => value.setWidth 32) rightResult
  · simp [after, State.multiply, leftRegister, rightRegister]
  · rfl
  · rfl
  · simp [after, loadedLeft, moved, State.multiply, State.load32,
      State.immediate32, State.move32, rbpRegister, rcxRegister,
      BitVec.ofNat_add, BitVec.add_assoc, frameMultiplyBytes, rightToRcxBytes]

theorem prologue_push_step (before after : State)
    (loaded : CodeAt before.memory before.rip (pushBytes rbpRegister))
    (result : after = before.push64 rbpRegister (pushBytes rbpRegister).length) :
    Step before after :=
  push_step before after rbpRegister loaded result

theorem prologue_rbp_step (before after : State)
    (loaded : CodeAt before.memory before.rip (moveBytes .w64 rbpRegister rspRegister))
    (result : after = before.move64 rbpRegister rspRegister
      (moveBytes .w64 rbpRegister rspRegister).length) :
    Step before after :=
  move_step before after .w64 rbpRegister rspRegister loaded result

theorem prologue_size_step (before after : State) (slots : Nat)
    (loaded : CodeAt before.memory before.rip
      (immediateBytes .w32 r11Register (frameSizeBits slots) 0))
    (result : after = before.immediate32 r11Register (frameSizeBits slots)
      (immediateBytes .w32 r11Register (frameSizeBits slots) 0).length) :
    Step before after :=
  immediate_step before after .w32 r11Register (frameSizeBits slots) 0 loaded result

theorem prologue_sub_step (before after : State)
    (loaded : CodeAt before.memory before.rip
      (aluBytes .w64 .subtract rspRegister r11Register))
    (auxiliary : Bool)
    (result : after = before.alu64 .subtract rspRegister r11Register auxiliary
      (aluBytes .w64 .subtract rspRegister r11Register).length) :
    Step before after :=
  alu_step .w64 before after .subtract rspRegister r11Register loaded auxiliary result

/- The complete frame transitions are shared by every expression certificate.
   The only memory-map obligation is the explicit PUSH disjointness below;
   all later prologue instructions are register-only. -/
def prologueState (before : State) (slots : Nat) : State :=
  let pushed := before.push64 rbpRegister (pushBytes rbpRegister).length
  let rbpSet := pushed.move64 rbpRegister rspRegister
    (moveBytes .w64 rbpRegister rspRegister).length
  let sized := rbpSet.immediate32 r11Register (frameSizeBits slots)
    (immediateBytes .w32 r11Register (frameSizeBits slots) 0).length
  sized.alu64 .subtract rspRegister r11Register false
    (aluBytes .w64 .subtract rspRegister r11Register).length

def epilogueState (before : State) : State :=
  let moved := before.move64 rspRegister rbpRegister
    (moveBytes .w64 rspRegister rbpRegister).length
  let popped := moved.pop64 rbpRegister (popBytes rbpRegister).length
  popped.returnNear

theorem framePrologue_steps (slots : Nat) (before : State)
    (loaded : CodeAt before.memory before.rip (framePrologueBytes slots))
    (pushDisjoint : ∀ index, index <
      (moveBytes .w64 rbpRegister rspRegister ++
        immediateBytes .w32 r11Register (frameSizeBits slots) 0 ++
        aluBytes .w64 .subtract rspRegister r11Register).length →
      ∀ lane : Fin 8,
        (before.rip + BitVec.ofNat 64
          ((pushBytes rbpRegister).length + index)) + BitVec.ofNat 64 0 ≠
        (before.registers rspRegister - 8) + BitVec.ofNat 64 lane.val) :
    Steps 4 before (prologueState before slots) := by
  let pushBytes' := pushBytes rbpRegister
  let rbpBytes' := moveBytes .w64 rbpRegister rspRegister
  let sizeBytes' := immediateBytes .w32 r11Register (frameSizeBits slots) 0
  let subBytes' := aluBytes .w64 .subtract rspRegister r11Register
  have loaded' : CodeAt before.memory before.rip
      (pushBytes' ++ (rbpBytes' ++ (sizeBytes' ++ subBytes'))) := by
    simpa [framePrologueBytes, pushBytes', rbpBytes', sizeBytes', subBytes',
      List.append_assoc] using loaded
  let pushed := before.push64 rbpRegister pushBytes'.length
  have pushLoaded : CodeAt before.memory before.rip pushBytes' := loaded'.prefix
  have pushStep' : Step before pushed := by
    apply prologue_push_step before pushed pushLoaded
    rfl
  have tailAfterPush : CodeAt pushed.memory pushed.rip
      (rbpBytes' ++ (sizeBytes' ++ subBytes')) := by
    have source := loaded'.suffix
    have protectedCode := CodeAt.write64 source (before.registers rbpRegister)
      (by
        intro index bound lane
        simpa [pushed, State.push64, pushBytes', rbpRegister, rspRegister,
          BitVec.ofNat_add, BitVec.add_assoc] using pushDisjoint index bound lane)
    simpa [pushed, State.push64, pushBytes'] using protectedCode
  let rbpSet := pushed.move64 rbpRegister rspRegister rbpBytes'.length
  have rbpLoaded : CodeAt pushed.memory pushed.rip rbpBytes' :=
    tailAfterPush.prefix
  have rbpStep' : Step pushed rbpSet := by
    apply prologue_rbp_step pushed rbpSet rbpLoaded
    rfl
  have tailAfterRbp : CodeAt rbpSet.memory rbpSet.rip
      (sizeBytes' ++ subBytes') := by
    simpa [rbpSet, pushed, State.move64, rbpBytes'] using tailAfterPush.suffix
  let sized := rbpSet.immediate32 r11Register (frameSizeBits slots) sizeBytes'.length
  have sizeLoaded : CodeAt rbpSet.memory rbpSet.rip sizeBytes' :=
    tailAfterRbp.prefix
  have sizeStep' : Step rbpSet sized := by
    apply prologue_size_step rbpSet sized slots sizeLoaded
    rfl
  have subLoaded : CodeAt sized.memory sized.rip subBytes' := by
    simpa [sized, rbpSet, State.immediate32, sizeBytes'] using
      tailAfterRbp.suffix
  let after := sized.alu64 .subtract rspRegister r11Register false subBytes'.length
  have subStep' : Step sized after := by
    apply prologue_sub_step sized after subLoaded false
    rfl
  have all : Steps 4 before after := Steps.cons pushStep'
      (Steps.cons rbpStep' (Steps.cons sizeStep'
        (Steps.cons subStep' (Steps.refl after))))
  simpa [prologueState, pushed, rbpSet, sized, after, pushBytes', rbpBytes',
    sizeBytes', subBytes'] using all

theorem framePrologue_rip (slots : Nat) (before : State) :
    (prologueState before slots).rip =
      before.rip + BitVec.ofNat 64 (framePrologueBytes slots).length := by
  simp [prologueState, framePrologueBytes, State.alu64, State.alu,
    State.immediate32, State.move64, State.push64, rbpRegister, rspRegister,
    r11Register, BitVec.ofNat_add, BitVec.add_assoc]

/- The prologue writes only the saved RBP word.  This companion lemma carries
   an authenticated suffix across that write, so callers can compose the
   shared prologue proof with an arbitrary body without re-proving its frame
   layout. -/
theorem framePrologue_tail (slots : Nat) (before : State) (rest : List UInt8)
    (loaded : CodeAt before.memory before.rip (framePrologueBytes slots ++ rest))
    (tailDisjoint : ∀ index, index < rest.length → ∀ lane : Fin 8,
      (before.rip + BitVec.ofNat 64 (framePrologueBytes slots).length +
        BitVec.ofNat 64 index) + BitVec.ofNat 64 0 ≠
      (before.registers rspRegister - 8) + BitVec.ofNat 64 lane.val) :
    CodeAt (prologueState before slots).memory
      (prologueState before slots).rip rest := by
  have source := loaded.suffix
  have protectedCode := CodeAt.write64 source (before.registers rbpRegister) (by
    intro index bound lane
    have h := tailDisjoint index bound lane
    simpa [BitVec.ofNat_add, BitVec.add_assoc, Nat.add_assoc] using h)
  have prologueRip : (prologueState before slots).rip =
      before.rip + BitVec.ofNat 64 (framePrologueBytes slots).length := by
    simp [prologueState, framePrologueBytes, State.alu64, State.alu,
      State.immediate32, State.move64, State.push64, rbpRegister, rspRegister,
      r11Register, BitVec.ofNat_add, BitVec.add_assoc]
  rw [prologueRip]
  simpa [prologueState, State.push64, State.move64, State.immediate32,
    State.alu64, State.alu, rbpRegister, rspRegister] using protectedCode

theorem frameEpilogue_steps (before : State)
    (loaded : CodeAt before.memory before.rip
      (moveBytes .w64 rspRegister rbpRegister ++ popBytes rbpRegister ++ returnBytes)) :
    Steps 3 before (epilogueState before) := by
  let moveBytes' := moveBytes .w64 rspRegister rbpRegister
  let popBytes' := popBytes rbpRegister
  have loaded' : CodeAt before.memory before.rip
      (moveBytes' ++ (popBytes' ++ returnBytes)) := by
    simpa [moveBytes', popBytes', List.append_assoc] using loaded
  let moved := before.move64 rspRegister rbpRegister moveBytes'.length
  have moveLoaded : CodeAt before.memory before.rip moveBytes' := loaded'.prefix
  have moveStep' : Step before moved := by
    apply move_step before moved .w64 rspRegister rbpRegister moveLoaded
    rfl
  have moveTail : CodeAt moved.memory moved.rip (popBytes' ++ returnBytes) := by
    simpa [moved, State.move64, moveBytes'] using loaded'.suffix
  let popped := moved.pop64 rbpRegister popBytes'.length
  have popLoaded : CodeAt moved.memory moved.rip popBytes' := moveTail.prefix
  have popStep' : Step moved popped := by
    apply pop_step moved popped rbpRegister popLoaded
    rfl
  have returnLoaded : CodeAt popped.memory popped.rip returnBytes := by
    simpa [popped, moved, State.pop64, State.move64, popBytes'] using
      moveTail.suffix
  let after := popped.returnNear
  have returnStep' : Step popped after := by
    apply return_step popped after returnLoaded
    rfl
  have all : Steps 3 before after := Steps.cons moveStep'
      (Steps.cons popStep' (Steps.cons returnStep' (Steps.refl after)))
  simpa [epilogueState, moved, popped, after, moveBytes', popBytes'] using all

theorem frameStore_then_alu_protocol (count : Nat) (slot : Nat) (operation : Alu)
    (leftValue rightValue : BitVec 32) (before stored rightState : State)
    (storeLoaded : CodeAt before.memory before.rip (frameStoreBytes slot))
    (storeResult : stored = before.store32 0 rbpRegister
      (BitVec.ofInt 32 (frameDisplacement slot)) (frameStoreBytes slot).length)
    (leftValue_eq : (before.registers 0).setWidth 32 = leftValue)
    (rightSteps : Steps count stored rightState)
    (sameRbp : rightState.registers rbpRegister = before.registers rbpRegister)
    (sameSlot : read32 rightState.memory
      (frameSlotAddress (before.registers rbpRegister) slot) =
      read32 stored.memory
        (frameSlotAddress (before.registers rbpRegister) slot))
    (rightResult : rightState.registers 0 = rightValue.setWidth 64)
    (loaded : CodeAt rightState.memory rightState.rip
      (frameAluBytes slot operation)) :
    ∃ after : State, Steps (count + 4) before after ∧
      after.registers 0 = (operation.result leftValue rightValue).setWidth 64 ∧
      after.registers rbpRegister = before.registers rbpRegister ∧
      after.memory = rightState.memory ∧
      after.rip = rightState.rip + BitVec.ofNat 64
        (frameAluBytes slot operation).length := by
  have storeStep := frameStore_step before stored slot storeLoaded storeResult
  have storedSlot : read32 stored.memory
      (frameSlotAddress (before.registers rbpRegister) slot) =
      (before.registers 0).setWidth 32 := by
    rw [storeResult]
    exact frameStore_slot_value before slot
  have slotValue : read32 rightState.memory
      (rightState.registers rbpRegister +
        (BitVec.ofInt 32 (frameDisplacement slot)).signExtend 64) = leftValue := by
    rw [sameRbp]
    have storedValue : read32 rightState.memory
        (frameSlotAddress (before.registers rbpRegister) slot) =
        (before.registers 0).setWidth 32 :=
      Eq.trans (by simpa [storeResult] using sameSlot)
        (frameStore_slot_value before slot)
    simpa only [frameSlotAddress] using storedValue.trans leftValue_eq
  obtain ⟨moved, loadedLeft, after, first, second, third, result,
      afterRbp, afterMemory, afterRip⟩ :=
    frameAlu_protocol slot operation leftValue rightValue rightState
      slotValue rightResult loaded
  have tail : Steps 3 rightState after := by
    simpa using Steps.cons first (Steps.cons second (Steps.cons third (Steps.refl after)))
  have all : Steps (1 + (count + 3)) before after := by
    have storeRun : Steps 1 before stored := by
      simpa using Steps.cons storeStep (Steps.refl stored)
    exact storeRun.trans (rightSteps.trans tail)
  refine ⟨after, ?_, result, ?_, ?_, afterRip⟩
  simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using all
  · calc
      after.registers rbpRegister = rightState.registers rbpRegister := afterRbp
      _ = before.registers rbpRegister := sameRbp
  · exact afterMemory

theorem frameStore_then_multiply_protocol (count : Nat) (slot : Nat)
    (leftValue rightValue : BitVec 32) (before stored rightState : State)
    (storeLoaded : CodeAt before.memory before.rip (frameStoreBytes slot))
    (storeResult : stored = before.store32 0 rbpRegister
      (BitVec.ofInt 32 (frameDisplacement slot)) (frameStoreBytes slot).length)
    (leftValue_eq : (before.registers 0).setWidth 32 = leftValue)
    (rightSteps : Steps count stored rightState)
    (sameRbp : rightState.registers rbpRegister = before.registers rbpRegister)
    (sameSlot : read32 rightState.memory
      (frameSlotAddress (before.registers rbpRegister) slot) =
      read32 stored.memory
        (frameSlotAddress (before.registers rbpRegister) slot))
    (rightResult : rightState.registers 0 = rightValue.setWidth 64)
    (loaded : CodeAt rightState.memory rightState.rip
      (frameMultiplyBytes slot)) :
    ∃ after : State, Steps (count + 4) before after ∧
      after.registers 0 = (leftValue * rightValue).setWidth 64 ∧
      after.registers rbpRegister = before.registers rbpRegister ∧
      after.memory = rightState.memory ∧
      after.rip = rightState.rip + BitVec.ofNat 64
        (frameMultiplyBytes slot).length := by
  have storeStep := frameStore_step before stored slot storeLoaded storeResult
  have slotValue : read32 rightState.memory
      (rightState.registers rbpRegister +
        (BitVec.ofInt 32 (frameDisplacement slot)).signExtend 64) = leftValue := by
    rw [sameRbp]
    have storedValue : read32 rightState.memory
        (frameSlotAddress (before.registers rbpRegister) slot) =
        (before.registers 0).setWidth 32 :=
      Eq.trans (by simpa [storeResult] using sameSlot)
        (frameStore_slot_value before slot)
    simpa only [frameSlotAddress] using storedValue.trans leftValue_eq
  obtain ⟨moved, loadedLeft, after, first, second, third, result,
      afterRbp, afterMemory, afterRip⟩ :=
    frameMultiply_protocol slot leftValue rightValue rightState
      slotValue rightResult loaded
  have tail : Steps 3 rightState after := by
    simpa using Steps.cons first (Steps.cons second (Steps.cons third (Steps.refl after)))
  have all : Steps (1 + (count + 3)) before after := by
    have storeRun : Steps 1 before stored := by
      simpa using Steps.cons storeStep (Steps.refl stored)
    exact storeRun.trans (rightSteps.trans tail)
  refine ⟨after, ?_, result, ?_, ?_, afterRip⟩
  simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using all
  · calc
      after.registers rbpRegister = rightState.registers rbpRegister := afterRbp
      _ = before.registers rbpRegister := sameRbp
  · exact afterMemory

end Lanius.X86.Machine
