import Lanius.X86.DirectCallCheck
import Lanius.X86.Machine.FrameSlots
import Lanius.X86.ExpressionFunctionCheck

namespace Lanius.X86.DirectCallFunctionCheck

open Lanius Lanius.Core
open Lanius.X86
open Lanius.X86.Machine

/- The backend's scalar call return path is
   `framePrologue; call; MOV RSP,RBP; POP RBP; RET`.  The first function
   certificate deliberately accepts the zero-argument case only: argument
   staging and stack-passed layouts remain unsupported until their emitted
   load/store sequences have matching machine lemmas. -/

def epilogueBytes : List UInt8 :=
  moveBytes .w64 rspRegister rbpRegister ++ popBytes rbpRegister ++ returnBytes

/- The generic backend appends its unreachable-missing-return trap after a
   non-unit statement, so the authenticated function span includes UD2. -/
def trapBytes : List UInt8 := [0x0f, 0x0b]

def callSite (address : Machine.Address) : Machine.Address :=
  address + BitVec.ofNat 64 (framePrologueBytes 1).length

def functionBytes (displacement : BitVec 32) : List UInt8 :=
  framePrologueBytes 1 ++ callBytes displacement ++ epilogueBytes ++ trapBytes

def tailBytes (displacement : BitVec 32) : List UInt8 :=
  callBytes displacement ++ epilogueBytes ++ trapBytes

def callAfterState (before : Machine.State) (displacement : BitVec 32) : Machine.State :=
  (Machine.prologueState before 1).call displacement (callBytes displacement).length

structure CallerSupported (caller callee : Function) : Type where
  noParameters : caller.parameters = []
  resultI32 : caller.returnType = .scalar (.signed .i32)
  internal : caller.external = none
  bodyExact :
    caller.body = some (.returnValue (some (.call callee.id []))) ∨
      caller.body = some (.sequence (.returnValue (some (.call callee.id []))) .skip)

private def callerShape? (caller callee : Function) : Option (CallerSupported caller callee) :=
  match caller with
  | ⟨_, [], returnType, some (.returnValue (some (.call id []))), none⟩ =>
      if result : returnType = .scalar (.signed .i32) then
        if calleeId : id = callee.id then
          some {
            noParameters := rfl
            resultI32 := result
            internal := rfl
            bodyExact := Or.inl (by simp [calleeId]) }
        else none
      else none
  | ⟨_, [], returnType,
      some (.sequence (.returnValue (some (.call id []))) .skip), none⟩ =>
      if result : returnType = .scalar (.signed .i32) then
        if calleeId : id = callee.id then
          some {
            noParameters := rfl
            resultI32 := result
            internal := rfl
            bodyExact := Or.inr (by simp [calleeId]) }
        else none
      else none
  | _ => none

structure Checked (caller callee : Function)
    (callerAddress target : Machine.Address) (displacement : BitVec 32)
    (emitted : List UInt8) where
  callerSupported : CallerSupported caller callee
  direct : DirectCallCheck.Checked callee 0 (callSite callerAddress) target
    displacement (callBytes displacement) returnBytes
  bytesExact : emitted = functionBytes displacement

def check (caller callee : Function) (callerAddress target : Machine.Address)
    (displacement : BitVec 32) (emitted : List UInt8) :
    Option (Checked caller callee callerAddress target displacement emitted) :=
  match callerShape? caller callee with
  | none => none
  | some callerSupported =>
      match DirectCallCheck.check callee 0 (callSite callerAddress) target displacement
          (callBytes displacement) returnBytes with
      | none => none
      | some direct =>
          if bytesExact : emitted = functionBytes displacement then
            some { callerSupported := callerSupported, direct := direct, bytesExact := bytesExact }
          else none

theorem check_sound {caller callee : Function}
    {callerAddress target : Machine.Address} {displacement : BitVec 32}
    {emitted : List UInt8}
    {checked : Checked caller callee callerAddress target displacement emitted}
    (accepted : check caller callee callerAddress target displacement emitted = some checked) :
    emitted = functionBytes displacement := by
  simp only [check] at accepted
  split at accepted
  next _ => simp at accepted
  next callerSupported =>
    split at accepted
    next _ => simp at accepted
    next direct =>
      split at accepted
      next bytesExact =>
        cases accepted
        exact bytesExact
      next _ => simp at accepted

def prologueDisjoint (before : Machine.State) : Prop :=
  ∀ index, index <
      (moveBytes .w64 rbpRegister rspRegister ++
        immediateBytes .w32 r11Register (frameSizeBits 1) 0 ++
        aluBytes .w64 .subtract rspRegister r11Register).length → ∀ lane : Fin 8,
    (before.rip + BitVec.ofNat 64 ((pushBytes rbpRegister).length + index)) +
        BitVec.ofNat 64 0 ≠
      (before.registers rspRegister - 8) + BitVec.ofNat 64 lane.val

def tailDisjoint (before : Machine.State) (displacement : BitVec 32) : Prop :=
  ∀ index, index < (tailBytes displacement).length → ∀ lane : Fin 8,
    (before.rip + BitVec.ofNat 64 (framePrologueBytes 1).length +
        BitVec.ofNat 64 index) ≠
      (before.registers rspRegister - 8) + BitVec.ofNat 64 lane.val

def callDisjoint (before : Machine.State) (displacement : BitVec 32) : Prop :=
  ∀ index, index < (epilogueBytes ++ trapBytes).length → ∀ lane : Fin 8,
    ((Machine.prologueState before 1).rip +
        BitVec.ofNat 64 (callBytes displacement).length + BitVec.ofNat 64 index) ≠
      ((Machine.prologueState before 1).registers rspRegister - 8) +
        BitVec.ofNat 64 lane.val

def callerEpilogueAddress (before : Machine.State) (displacement : BitVec 32) : Machine.Address :=
  (Machine.prologueState before 1).rip + BitVec.ofNat 64 (callBytes displacement).length
def read64Disjoint (address write : Machine.Address) : Prop := ∀ i j : Fin 8,
  address + BitVec.ofNat 64 i.val ≠ write + BitVec.ofNat 64 j.val
def read32Disjoint (address write : Machine.Address) : Prop := ∀ i : Fin 8, ∀ j : Fin 4,
  address + BitVec.ofNat 64 i.val ≠ write + BitVec.ofNat 64 j.val
def byteDisjoint64 (address write : Machine.Address) : Prop := ∀ lane : Fin 8,
  address ≠ write + BitVec.ofNat 64 lane.val
def byteDisjoint32 (address write : Machine.Address) : Prop := ∀ lane : Fin 4,
  address ≠ write + BitVec.ofNat 64 lane.val
def calleeCodeDisjoint (before : Machine.State) (displacement : BitVec 32)
    (allocations : Nat) (address : Machine.Address) : Prop :=
  byteDisjoint64 address ((callAfterState before displacement).registers rspRegister - 8) ∧
    ∀ slot, slot < allocations → byteDisjoint32 address
      (frameSlotAddress ((Machine.prologueState (callAfterState before displacement) allocations).registers rbpRegister) slot)
def calleeReadDisjoint (before : Machine.State) (displacement : BitVec 32)
    (allocations : Nat) (address : Machine.Address) : Prop :=
  read64Disjoint address ((callAfterState before displacement).registers rspRegister - 8) ∧
    ∀ slot, slot < allocations → read32Disjoint address
      (frameSlotAddress ((Machine.prologueState (callAfterState before displacement) allocations).registers rbpRegister) slot)

structure CompletedCalleeLayout (before : Machine.State) (displacement : BitVec 32)
    (allocations : Nat) : Prop where
  prologue : prologueDisjoint before
  tail : tailDisjoint before displacement
  call : callDisjoint before displacement
  epilogue : ∀ index, index < epilogueBytes.length → calleeCodeDisjoint before displacement allocations
    (callerEpilogueAddress before displacement + BitVec.ofNat 64 index)
  callerFrame : calleeReadDisjoint before displacement allocations (before.registers rspRegister - 8)
  outerReturn : calleeReadDisjoint before displacement allocations (before.registers rspRegister)

def completedReadDisjoint (before : Machine.State) (displacement : BitVec 32)
    (allocations : Nat) (address : Machine.Address) : Prop :=
  read64Disjoint address (before.registers rspRegister - 8) ∧
  read64Disjoint address
    ((Machine.prologueState before 1).registers rspRegister - 8) ∧
  calleeReadDisjoint before displacement allocations address

structure CompletedCalleeResult (before after : Machine.State) (displacement : BitVec 32)
    (allocations count : Nat) (returnAddress : Machine.Address) (value : Value) : Prop where
  steps : Machine.Steps count before after
  result : LiteralReturn.RaxMatches value ((after.registers DirectCallCheck.resultRegister).setWidth 32)
  rip : after.rip = returnAddress
  stack : after.registers rspRegister = before.registers rspRegister + 8
  frame : after.registers rbpRegister = before.registers rbpRegister
  preserveRead64Outside : ∀ address,
    completedReadDisjoint before displacement allocations address →
    read64 after.memory address = read64 before.memory address

private theorem read64_write64_sub_eight (memory : Machine.Memory)
    (address value : Machine.Address) :
    Machine.read64 (Machine.write64 memory (address - 8) value) address =
      Machine.read64 memory address := by
  apply Machine.read64_frame
  intro i j
  exact stackWindow_disjoint (nBound := by decide) address i j

private theorem stackWindow_disjoint_afterSixteen {n : Nat} (nBound : n ≤ 8)
    (base : Machine.Address) (i : Fin 8) (j : Fin n) :
    base + 16 + BitVec.ofNat 64 i.val ≠
      base - 8 + BitVec.ofNat 64 j.val := by
  intro h
  have hbase : base + ((16 : BitVec 64) + BitVec.ofNat 64 i.val) =
      base + ((- (8 : BitVec 64)) + BitVec.ofNat 64 j.val) := by
    simpa [BitVec.sub_eq_add_neg, BitVec.add_assoc] using h
  have h' : (16 : BitVec 64) + BitVec.ofNat 64 i.val =
      (- (8 : BitVec 64)) + BitVec.ofNat 64 j.val :=
    (BitVec.add_right_inj base).mp hbase
  have hi := i.isLt
  have hj := j.isLt
  have hto := congrArg BitVec.toNat h'
  have left16 : ((16 : BitVec 64) + BitVec.ofNat 64 i.val).toNat = 16 + i.val := by
    have sixteen : BitVec.toNat (16 : BitVec 64) = 16 := by decide
    rw [BitVec.toNat_add, sixteen, BitVec.toNat_ofNat]
    have hi64 : i.val % 2^64 = i.val := Nat.mod_eq_of_lt (by omega)
    rw [hi64]
    exact Nat.mod_eq_of_lt (by omega)
  have negEight : (- (8 : BitVec 64)).toNat = 2^64 - 8 := by decide
  rw [left16, BitVec.toNat_add, negEight, BitVec.toNat_ofNat] at hto
  have hj64 : j.val % 2^64 = j.val := Nat.mod_eq_of_lt (by omega)
  rw [hj64] at hto
  have rightBound : 2^64 - 8 + j.val < 2^64 := by omega
  rw [Nat.mod_eq_of_lt rightBound] at hto
  omega

private theorem stackWindow_disjoint_afterTwentyFour {n : Nat} (nBound : n ≤ 8)
    (base : Machine.Address) (i : Fin 8) (j : Fin n) :
    base + 24 + BitVec.ofNat 64 i.val ≠
      base - 8 + BitVec.ofNat 64 j.val := by
  intro h
  have hbase : base + ((24 : BitVec 64) + BitVec.ofNat 64 i.val) =
      base + ((- (8 : BitVec 64)) + BitVec.ofNat 64 j.val) := by
    simpa [BitVec.sub_eq_add_neg, BitVec.add_assoc] using h
  have h' : (24 : BitVec 64) + BitVec.ofNat 64 i.val =
      (- (8 : BitVec 64)) + BitVec.ofNat 64 j.val :=
    (BitVec.add_right_inj base).mp hbase
  have hi := i.isLt
  have hj := j.isLt
  have hto := congrArg BitVec.toNat h'
  have left24 : ((24 : BitVec 64) + BitVec.ofNat 64 i.val).toNat = 24 + i.val := by
    have twentyFour : BitVec.toNat (24 : BitVec 64) = 24 := by decide
    rw [BitVec.toNat_add, twentyFour, BitVec.toNat_ofNat]
    have hi64 : i.val % 2^64 = i.val := Nat.mod_eq_of_lt (by omega)
    rw [hi64]
    exact Nat.mod_eq_of_lt (by omega)
  have negEight : (- (8 : BitVec 64)).toNat = 2^64 - 8 := by decide
  rw [left24, BitVec.toNat_add, negEight, BitVec.toNat_ofNat] at hto
  have hj64 : j.val % 2^64 = j.val := Nat.mod_eq_of_lt (by omega)
  rw [hj64] at hto
  have rightBound : 2^64 - 8 + j.val < 2^64 := by omega
  rw [Nat.mod_eq_of_lt rightBound] at hto
  omega

/- The full function theorem starts at the actual function entry.  The callee
   contract is deliberately the existing `DirectCallCheck` preservation
   contract at the post-prologue call state; no machine post-state is
   guessed.  Code after the call is supplied at the state where the callee's
   `RET` returns, because the flat memory model does not assume stack/code
   disjointness for us. -/
theorem preserves
    (checked : Checked caller callee callerAddress target displacement emitted)
    (before calleeAfter : Machine.State) (result : Int)
    (ripAtCaller : before.rip = callerAddress)
    (loadedFunction : Machine.CodeAt before.memory before.rip emitted)
    (stackDisjoint : prologueDisjoint before)
    (tailDisjoint : tailDisjoint before displacement)
    (callStackDisjoint : callDisjoint before displacement)
    (calleePreservation : DirectCallCheck.CalleePreservation
      (callAfterState before displacement) calleeAfter target [] result)
    (loadedReturn : Machine.CodeAt calleeAfter.memory calleeAfter.rip returnBytes)
    (returnAddress : Machine.Address)
    (poppedReturn : Machine.read64 before.memory
      (before.registers rspRegister) = returnAddress) :
    ∃ after calleeCount, Machine.Steps (calleeCount + 9) before after ∧
      ((after.registers DirectCallCheck.resultRegister).setWidth 32).toInt = result ∧
      after.rip = returnAddress ∧
      after.registers rspRegister = before.registers rspRegister + 8 ∧
      after.memory = (callAfterState before displacement).memory := by
  rw [checked.bytesExact] at loadedFunction
  have loadedPrologue : Machine.CodeAt before.memory before.rip (framePrologueBytes 1) := by
    exact Machine.CodeAt.prefix (first := framePrologueBytes 1)
      (rest := callBytes displacement ++ (epilogueBytes ++ trapBytes)) loadedFunction
  have prologueRip : (Machine.prologueState before 1).rip =
      before.rip + BitVec.ofNat 64 (framePrologueBytes 1).length := by
    simp [Machine.prologueState, framePrologueBytes, State.alu64, State.alu,
      State.immediate32, State.move64, State.push64, rbpRegister, rspRegister,
      r11Register, BitVec.ofNat_add, BitVec.add_assoc]
  have loadedTailBefore : Machine.CodeAt before.memory
      (before.rip + BitVec.ofNat 64 (framePrologueBytes 1).length)
      (tailBytes displacement) := by
    exact Machine.CodeAt.suffix (first := framePrologueBytes 1)
      (rest := tailBytes displacement) loadedFunction
  have loadedTail : Machine.CodeAt (Machine.prologueState before 1).memory
      (Machine.prologueState before 1).rip
      (tailBytes displacement) := by
    have protectedCode := Machine.CodeAt.write64
      (address := before.registers rspRegister - 8) loadedTailBefore
      (before.registers rbpRegister) (by
        intro index bound lane
        exact tailDisjoint index bound lane)
    rw [prologueRip]
    simpa [Machine.prologueState, State.push64, State.move64, State.immediate32,
      State.alu64, State.alu, rbpRegister, rspRegister] using protectedCode
  have loadedCall : Machine.CodeAt (Machine.prologueState before 1).memory
      (Machine.prologueState before 1).rip (callBytes displacement) :=
    Machine.CodeAt.prefix (first := callBytes displacement)
      (rest := epilogueBytes ++ trapBytes) loadedTail
  have prologue := framePrologue_steps 1 before loadedPrologue (by
    intro index bound lane
    simpa [prologueDisjoint, BitVec.ofNat_add, BitVec.add_assoc] using
      stackDisjoint index bound lane)
  have callRip : (Machine.prologueState before 1).rip = callSite callerAddress := by
    simp [Machine.prologueState, callSite, ripAtCaller, State.alu64, State.alu,
      State.immediate32, State.move64, State.push64, framePrologueBytes,
      rbpRegister, rspRegister, r11Register, BitVec.ofNat_add, BitVec.add_assoc]
  let callAfter := callAfterState before displacement
  have callStep : Machine.Step (Machine.prologueState before 1) callAfter := by
    apply Machine.call_step (Machine.prologueState before 1) callAfter displacement loadedCall
    rfl
  have targetRip : callAfter.rip = target := by
    change (Machine.prologueState before 1).rip +
      BitVec.ofNat 64 (callBytes displacement).length +
      displacement.signExtend 64 = target
    rw [callRip]
    have targetEquation := checked.direct.targetExact
    simp only [DirectCallCheck.callBytes] at targetEquation
    rw [← targetEquation]
  have represented : DirectCallCheck.argumentsRepresented (callAfterState before displacement) [] := by
    intro index bound
    simp at bound
  obtain ⟨calleeCount, calleeSteps⟩ := calleePreservation.steps
  have loadedEpilogueAtReturn : Machine.CodeAt (callAfterState before displacement).memory
      ((Machine.prologueState before 1).rip + BitVec.ofNat 64
        (callBytes displacement).length) epilogueBytes := by
    have source : Machine.CodeAt (Machine.prologueState before 1).memory
        ((Machine.prologueState before 1).rip + BitVec.ofNat 64
          (callBytes displacement).length) (epilogueBytes ++ trapBytes) :=
      Machine.CodeAt.suffix (first := callBytes displacement)
        (rest := epilogueBytes ++ trapBytes) loadedTail
    have protectedCode := Machine.CodeAt.write64
      (address := (Machine.prologueState before 1).registers rspRegister - 8)
      source ((Machine.prologueState before 1).rip + BitVec.ofNat 64
        (callBytes displacement).length) (by
          intro index bound lane
          exact callStackDisjoint index bound lane)
    have protectedTail : Machine.CodeAt (callAfterState before displacement).memory
        ((Machine.prologueState before 1).rip + BitVec.ofNat 64
          (callBytes displacement).length) (epilogueBytes ++ trapBytes) := by
      simpa [callAfterState, State.call, rspRegister, tailBytes, List.append_assoc] using
        protectedCode
    exact Machine.CodeAt.prefix (first := epilogueBytes) (rest := trapBytes)
      protectedTail
  let returned := calleeAfter.returnNear
  have stackAtCallee : calleeAfter.registers rspRegister =
      (Machine.prologueState before 1).registers rspRegister - 8 := by
    simpa [DirectCallCheck.stackRegister, rspRegister, callAfterState, State.call] using
      calleePreservation.stack
  have returnRip : returned.rip =
      (Machine.prologueState before 1).rip + BitVec.ofNat 64
        (callBytes displacement).length := by
    change read64 calleeAfter.memory (calleeAfter.registers rspRegister) = _
    rw [calleePreservation.memory, stackAtCallee]
    exact Machine.read64_write64 (Machine.prologueState before 1).memory
      ((Machine.prologueState before 1).registers rspRegister - 8)
      ((Machine.prologueState before 1).rip + BitVec.ofNat 64
        (callBytes displacement).length)
  have returnStep : Machine.Step calleeAfter returned := by
    apply Machine.return_step calleeAfter returned loadedReturn
    rfl
  have resultAtReturn :
      ((returned.registers DirectCallCheck.resultRegister).setWidth 32).toInt = result := by
    have resultAtCallee :
        ((calleeAfter.registers DirectCallCheck.resultRegister).setWidth 32).toInt = result :=
      calleePreservation.resultFrom targetRip represented
    simpa [returned, State.returnNear, DirectCallCheck.resultRegister] using resultAtCallee
  have loadedEpilogue : Machine.CodeAt returned.memory returned.rip epilogueBytes := by
    change Machine.CodeAt calleeAfter.memory returned.rip epilogueBytes
    rw [returnRip, calleePreservation.memory]
    exact loadedEpilogueAtReturn
  have epilogueRun : Machine.Steps 3 returned (Machine.epilogueState returned) := by
    apply frameEpilogue_steps returned
    simpa [epilogueBytes, List.append_assoc] using loadedEpilogue
  let after := Machine.epilogueState returned
  have resultAfter : after.registers DirectCallCheck.resultRegister =
      returned.registers DirectCallCheck.resultRegister := by
    simp [after, Machine.epilogueState, State.returnNear, State.pop64, State.move64,
      DirectCallCheck.resultRegister, rbpRegister, rspRegister]
  have resultFinal :
      ((after.registers DirectCallCheck.resultRegister).setWidth 32).toInt = result := by
    rw [resultAfter]
    exact resultAtReturn
  have calleeRbp : calleeAfter.registers rbpRegister =
      before.registers rspRegister - 8 := by
    rw [calleePreservation.stable rbpRegister (by decide) (by decide)]
    simp [callAfterState, Machine.prologueState, State.call, State.push64,
      State.move64, State.immediate32, State.alu64, State.alu,
      rbpRegister, rspRegister, r11Register]
  have returnedRbp : returned.registers rbpRegister =
      before.registers rspRegister - 8 := by
    simpa [returned, State.returnNear, rbpRegister, rspRegister] using calleeRbp
  have finalRip : after.rip = returnAddress := by
    have prologueStack : (Machine.prologueState before 1).registers rspRegister =
        before.registers rspRegister - 24 := by
      simp [Machine.prologueState, State.push64, State.move64, State.immediate32,
        State.alu64, State.alu, Alu.result, frameSizeBits, frameBytes,
        rbpRegister, rspRegister, r11Register, BitVec.sub_eq_add_neg,
        BitVec.add_assoc]
    have prologueMemory : (Machine.prologueState before 1).memory =
        Machine.write64 before.memory (before.registers rspRegister - 8)
          (before.registers rbpRegister) := by
      rfl
    have prologueRead : Machine.read64 (Machine.prologueState before 1).memory
        (before.registers rspRegister) =
        Machine.read64 before.memory (before.registers rspRegister) := by
      rw [prologueMemory]
      exact read64_write64_sub_eight before.memory
        (before.registers rspRegister) (before.registers rbpRegister)
    have callMemory : (callAfterState before displacement).memory =
        Machine.write64 (Machine.prologueState before 1).memory
          ((Machine.prologueState before 1).registers rspRegister - 8)
          ((Machine.prologueState before 1).rip +
            BitVec.ofNat 64 (callBytes displacement).length) := by
      rfl
    have callRead : Machine.read64 (callAfterState before displacement).memory
        (before.registers rspRegister) =
        Machine.read64 (Machine.prologueState before 1).memory
          (before.registers rspRegister) := by
      rw [callMemory]
      apply Machine.read64_frame
      intro i j
      have beforeStack : before.registers rspRegister =
          (Machine.prologueState before 1).registers rspRegister + 24 := by
        rw [prologueStack]
        simp [BitVec.sub_eq_add_neg, BitVec.add_assoc]
      rw [beforeStack]
      exact stackWindow_disjoint_afterTwentyFour (nBound := by decide)
        ((Machine.prologueState before 1).registers rspRegister) i j
    have returnRead' : Machine.read64 calleeAfter.memory
        (before.registers rspRegister) = returnAddress := by
      rw [calleePreservation.memory]
      rw [callRead, prologueRead]
      exact poppedReturn
    have returnRead : Machine.read64 returned.memory
        (before.registers rspRegister) = returnAddress := by
      simpa [returned, State.returnNear] using returnRead'
    change Machine.read64 returned.memory
      (returned.registers rbpRegister + 8) = returnAddress
    rw [returnedRbp, BitVec.sub_add_cancel]
    exact returnRead
  have finalStack : after.registers rspRegister = before.registers rspRegister + 8 := by
    have afterStack : after.registers rspRegister =
        returned.registers rbpRegister + 8 + 8 := by
      simp [after, Machine.epilogueState, State.returnNear, State.pop64,
        State.move64, rbpRegister, rspRegister]
    rw [afterStack, BitVec.add_assoc]
    have eight : (8 : BitVec 64) + 8 = 16 := by decide
    rw [eight, returnedRbp]
    simp [BitVec.sub_eq_add_neg, BitVec.add_assoc]
  have finalMemory : after.memory = (callAfterState before displacement).memory := by
    simp [after, returned, Machine.epilogueState, State.returnNear, State.pop64,
      State.move64, calleePreservation.memory]
  have callRun : Machine.Steps 1 (Machine.prologueState before 1) callAfter := by
    exact Steps.cons callStep (Steps.refl callAfter)
  have returnRun : Machine.Steps 1 calleeAfter returned := by
    exact Steps.cons returnStep (Steps.refl returned)
  have suffix := callRun.trans (calleeSteps.trans (returnRun.trans epilogueRun))
  refine ⟨after, calleeCount, ?_, resultFinal, finalRip, finalStack, finalMemory⟩
  simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using prologue.trans suffix

private theorem callerPrefixRead64 (before : Machine.State) (displacement : BitVec 32)
    (address : Machine.Address) (prologueOutside : read64Disjoint address (before.registers rspRegister - 8))
    (callOutside : read64Disjoint address ((Machine.prologueState before 1).registers rspRegister - 8)) :
    read64 (callAfterState before displacement).memory address = read64 before.memory address := by
  have callRead : read64 (callAfterState before displacement).memory address =
      read64 (Machine.prologueState before 1).memory address := by
    rw [show (callAfterState before displacement).memory = Machine.write64 (Machine.prologueState before 1).memory
      ((Machine.prologueState before 1).registers rspRegister - 8)
      ((Machine.prologueState before 1).rip + BitVec.ofNat 64 (callBytes displacement).length) by rfl]
    apply read64_frame
    exact callOutside
  calc
    _ = read64 (Machine.prologueState before 1).memory address := callRead
    _ = _ := by
      rw [show (Machine.prologueState before 1).memory = Machine.write64 before.memory
        (before.registers rspRegister - 8) (before.registers rbpRegister) by rfl]
      apply read64_frame
      exact prologueOutside

private theorem callerFrameRead64 (before : Machine.State) (displacement : BitVec 32) :
    read64 (callAfterState before displacement).memory (before.registers rspRegister - 8) = before.registers rbpRegister := by
  have callSaved : read64 (callAfterState before displacement).memory (before.registers rspRegister - 8) =
      read64 (Machine.prologueState before 1).memory (before.registers rspRegister - 8) := by
    rw [show (callAfterState before displacement).memory = Machine.write64 (Machine.prologueState before 1).memory
      ((Machine.prologueState before 1).registers rspRegister - 8)
      ((Machine.prologueState before 1).rip + BitVec.ofNat 64 (callBytes displacement).length) by rfl]
    apply read64_frame
    intro i j
    have h : before.registers rspRegister - 8 = (Machine.prologueState before 1).registers rspRegister + 16 := by
      simp [Machine.prologueState, State.push64, State.move64, State.immediate32,
        State.alu64, State.alu, Alu.result, frameSizeBits, frameBytes,
        rbpRegister, rspRegister, r11Register, BitVec.sub_eq_add_neg, BitVec.add_assoc]
    rw [h]
    exact stackWindow_disjoint_afterSixteen (n := 8) (nBound := by decide)
      ((Machine.prologueState before 1).registers rspRegister) i j
  calc
    _ = read64 (Machine.prologueState before 1).memory (before.registers rspRegister - 8) := callSaved
    _ = _ := by
      rw [show (Machine.prologueState before 1).memory =
        Machine.write64 before.memory (before.registers rspRegister - 8)
          (before.registers rbpRegister) by rfl]
      exact read64_write64 _ _ _

private theorem callerOuterRead64 (before : Machine.State) (displacement : BitVec 32)
    (returnAddress : Machine.Address)
    (poppedReturn : read64 before.memory (before.registers rspRegister) = returnAddress) :
    read64 (callAfterState before displacement).memory (before.registers rspRegister) = returnAddress := by
  calc
    _ = read64 before.memory (before.registers rspRegister) := callerPrefixRead64 before displacement (before.registers rspRegister)
      (by intro i j; exact stackWindow_disjoint (nBound := by decide) _ i j)
      (by
        intro i j
        have h : before.registers rspRegister = (Machine.prologueState before 1).registers rspRegister + 24 := by
          simp [Machine.prologueState, State.push64, State.move64, State.immediate32,
            State.alu64, State.alu, Alu.result, frameSizeBits, frameBytes,
            rbpRegister, rspRegister, r11Register, BitVec.sub_eq_add_neg, BitVec.add_assoc]
        rw [h]
        exact stackWindow_disjoint_afterTwentyFour (n := 8) (nBound := by decide)
          ((Machine.prologueState before 1).registers rspRegister) i j)
    _ = returnAddress := poppedReturn

/- A completed expression-calibrated callee already includes its own RET.  This
   composition only authenticates the caller's prologue, CALL, and epilogue;
   the callee RET is consumed through [bodyResult.steps]. -/
theorem preserves_completed_callee
    {caller callee : Function} {callerAddress target : Machine.Address}
    {displacement : BitVec 32} {emitted calleeEmitted : List UInt8}
    (checked : Checked caller callee callerAddress target displacement emitted)
    {calleeChecked : ExpressionFunctionCheck.BodySupported callee calleeEmitted}
    {program : Program} {coreBefore coreAfter : Semantics.State}
    {body : Stmt} {value : Value} {before calleeAfter : Machine.State}
    {calleeCount : Nat} {returnAddress : Machine.Address}
    (bodyResult : ExpressionFunctionCheck.BodyResult calleeChecked program coreBefore
      (callAfterState before displacement) (callerEpilogueAddress before displacement)
      coreAfter body value calleeAfter calleeCount)
    (ripAtCaller : before.rip = callerAddress)
    (loadedFunction : CodeAt before.memory before.rip emitted)
    (layout : CompletedCalleeLayout before displacement
      calleeChecked.checkedShape.1.allocations)
    (poppedReturn : read64 before.memory (before.registers rspRegister) = returnAddress) :
    ∃ after, CompletedCalleeResult before after displacement
      calleeChecked.checkedShape.1.allocations (calleeCount + 8) returnAddress value := by
  rw [checked.bytesExact] at loadedFunction
  have loadedFunction' : CodeAt before.memory before.rip
      (framePrologueBytes 1 ++ tailBytes displacement) := by
    simpa [functionBytes, tailBytes, List.append_assoc] using loadedFunction
  have loadedTail := Machine.framePrologue_tail 1 before
    (callBytes displacement ++ (epilogueBytes ++ trapBytes)) loadedFunction'
    (by
      intro index bound lane
      simpa [tailDisjoint, BitVec.add_zero, BitVec.ofNat_add, BitVec.add_assoc] using
        layout.tail index bound lane)
  have callRip : (Machine.prologueState before 1).rip = callSite callerAddress := by
    simp [Machine.prologueState, callSite, ripAtCaller, State.alu64, State.alu,
      State.immediate32, State.move64, State.push64, framePrologueBytes,
      rbpRegister, rspRegister, r11Register, BitVec.ofNat_add, BitVec.add_assoc]
  have prologueRun := framePrologue_steps 1 before loadedFunction'.prefix (by
    intro index bound lane
    simpa [prologueDisjoint, BitVec.ofNat_add, BitVec.add_assoc] using
      layout.prologue index bound lane)
  have loadedCall : CodeAt (Machine.prologueState before 1).memory
      (Machine.prologueState before 1).rip (callBytes displacement) := loadedTail.prefix
  let callAfter := callAfterState before displacement
  have callStep : Machine.Step (Machine.prologueState before 1) callAfter := by
    apply Machine.call_step (Machine.prologueState before 1) callAfter displacement loadedCall
    rfl
  have source : CodeAt (Machine.prologueState before 1).memory
      ((Machine.prologueState before 1).rip +
        BitVec.ofNat 64 (callBytes displacement).length)
      (epilogueBytes ++ trapBytes) := loadedTail.suffix
  have loadedEpilogueAtCall : CodeAt callAfter.memory
      (callerEpilogueAddress before displacement) epilogueBytes := by
    have protectedCode := Machine.CodeAt.write64
      (address := (Machine.prologueState before 1).registers rspRegister - 8)
      source ((Machine.prologueState before 1).rip +
        BitVec.ofNat 64 (callBytes displacement).length) (by
          intro index bound lane
          exact layout.call index bound lane)
    have protectedTail : CodeAt callAfter.memory
        (callerEpilogueAddress before displacement) (epilogueBytes ++ trapBytes) := by
      simpa [callAfter, callAfterState, State.call, callerEpilogueAddress, callRip,
        rspRegister, DirectCallCheck.stackRegister] using protectedCode
    exact protectedTail.prefix
  have loadedEpilogueAfter : CodeAt calleeAfter.memory calleeAfter.rip epilogueBytes := by
    have protectedCode : CodeAt calleeAfter.memory
        (callerEpilogueAddress before displacement) epilogueBytes :=
      bodyResult.protectedCode
      (callerEpilogueAddress before displacement) epilogueBytes loadedEpilogueAtCall
      (by
        intro index bound lane
        exact (layout.epilogue index bound).1 lane)
      (by
        intro index bound slot slotUpper lane
        exact (layout.epilogue index bound).2 slot slotUpper lane)
    rw [bodyResult.rip]
    exact protectedCode
  have epilogueRun : Machine.Steps 3 calleeAfter (Machine.epilogueState calleeAfter) := by
    exact frameEpilogue_steps calleeAfter loadedEpilogueAfter
  have calleeRbp : calleeAfter.registers rbpRegister =
      before.registers rspRegister - 8 := by
    rw [bodyResult.frame]
    simp [callAfterState, Machine.prologueState, State.call, State.push64,
      State.move64, State.immediate32, State.alu64, State.alu,
      rbpRegister, rspRegister, r11Register]
  have resultAfter : (Machine.epilogueState calleeAfter).registers
      DirectCallCheck.resultRegister = calleeAfter.registers DirectCallCheck.resultRegister := by
    simp [Machine.epilogueState, State.returnNear, State.pop64, State.move64,
      DirectCallCheck.resultRegister, rbpRegister, rspRegister]
  have savedFrameRead : read64 calleeAfter.memory
      (before.registers rspRegister - 8) = before.registers rbpRegister := by
    have bodySaved := bodyResult.preserveRead64Outside
      (before.registers rspRegister - 8) layout.callerFrame.1 layout.callerFrame.2
    calc
      read64 calleeAfter.memory (before.registers rspRegister - 8) =
          read64 (callAfterState before displacement).memory
            (before.registers rspRegister - 8) := bodySaved
      _ = before.registers rbpRegister := callerFrameRead64 before displacement
  have finalFrame : (Machine.epilogueState calleeAfter).registers rbpRegister =
      before.registers rbpRegister := by
    change read64 calleeAfter.memory (calleeAfter.registers rbpRegister) =
      before.registers rbpRegister
    rw [calleeRbp]
    exact savedFrameRead
  have finalRip : (Machine.epilogueState calleeAfter).rip = returnAddress := by
    have outerRead := bodyResult.preserveRead64Outside
      (before.registers rspRegister) layout.outerReturn.1 layout.outerReturn.2
    have outerRead' : read64 calleeAfter.memory (before.registers rspRegister) = returnAddress := by
      calc
        _ = read64 (callAfterState before displacement).memory
            (before.registers rspRegister) := outerRead
        _ = returnAddress := callerOuterRead64 before displacement returnAddress poppedReturn
    change read64 calleeAfter.memory (calleeAfter.registers rbpRegister + 8) = returnAddress
    rw [calleeRbp, BitVec.sub_add_cancel]
    exact outerRead'
  have finalStack : (Machine.epilogueState calleeAfter).registers rspRegister =
      before.registers rspRegister + 8 := by
    have epilogueStack : (Machine.epilogueState calleeAfter).registers rspRegister =
        calleeAfter.registers rbpRegister + 16 := by
      simp [Machine.epilogueState, State.returnNear, State.pop64, State.move64,
        rbpRegister, rspRegister, BitVec.add_assoc]
    rw [epilogueStack, calleeRbp]
    simp [BitVec.sub_eq_add_neg, BitVec.add_assoc]
  have preserveRead : ∀ address,
      completedReadDisjoint before displacement
        calleeChecked.checkedShape.1.allocations address →
      read64 (Machine.epilogueState calleeAfter).memory address =
        read64 before.memory address := by
    intro address outside
    rcases outside with ⟨prologueOutside, callOutside, calleeSavedOutside, slotsOutside⟩
    have bodyOutside := bodyResult.preserveRead64Outside address
      calleeSavedOutside slotsOutside
    have prefixRead := callerPrefixRead64 before displacement address prologueOutside callOutside
    calc
      read64 (Machine.epilogueState calleeAfter).memory address = read64 calleeAfter.memory address := by
        simp [Machine.epilogueState, State.returnNear, State.pop64, State.move64]
      _ = read64 (callAfterState before displacement).memory address := bodyOutside
      _ = read64 before.memory address := prefixRead
  refine ⟨Machine.epilogueState calleeAfter, {
    steps := by
      have callRun : Machine.Steps 1 (Machine.prologueState before 1) callAfter :=
        Steps.cons callStep (Steps.refl callAfter)
      have suffix := callRun.trans (bodyResult.steps.trans epilogueRun)
      simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using prologueRun.trans suffix
    result := by
      rw [resultAfter]
      exact bodyResult.rax
    rip := finalRip
    stack := finalStack
    frame := finalFrame
    preserveRead64Outside := preserveRead }⟩

end Lanius.X86.DirectCallFunctionCheck
