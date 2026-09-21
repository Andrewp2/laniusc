import Lanius.X86.ImageCheck
import Lanius.X86.Machine.RuntimeEncoding

namespace Lanius.X86.StartupCheck

open Lanius Lanius.X86
open Lanius.X86.Machine

def rax : Register := 0
def rdi : Register := 7
def rbp : Register := 5
def rsp : Register := 4
def r10 : Register := 10
def r15 : Register := 15

def moveEntry : List UInt8 := moveBytes .w64 r10 rsp
def loadContext : List UInt8 := immediateBytes .w32 rax (BitVec.ofNat 32 3) 0
def pushContext : List UInt8 := pushBytes rax
def pushStack : List UInt8 := pushBytes r10
def saveContext : List UInt8 := moveBytes .w64 r15 rsp
def clearFrame : List UInt8 := aluBytes .w32 .xor rbp rbp
def callCode : List UInt8 := callBytes (BitVec.ofNat 32 235)
def returnResult : List UInt8 := moveBytes .w32 rdi rax
def loadExit : List UInt8 := immediateBytes .w32 rax (BitVec.ofNat 32 60) 0

def afterMoveBytes : List UInt8 :=
  loadContext ++ pushContext ++ pushStack ++ saveContext ++ clearFrame ++ callCode
def afterLoadBytes : List UInt8 := pushContext ++ pushStack ++ saveContext ++ clearFrame ++ callCode
def afterFirstPushBytes : List UInt8 := pushStack ++ saveContext ++ clearFrame ++ callCode
def afterSecondPushBytes : List UInt8 := saveContext ++ clearFrame ++ callCode
def afterSaveBytes : List UInt8 := clearFrame ++ callCode
def afterClearBytes : List UInt8 := callCode
def startupPrefix : List UInt8 := moveEntry ++ afterMoveBytes
def startupBytes : List UInt8 :=
  startupPrefix ++ returnResult ++ loadExit ++ syscallBytes ++ ud2Bytes

def base : Machine.Address := ImageCheck.lanius.base
def entry : Machine.Address := base + BitVec.ofNat 64 256
def code : Machine.Address := base + BitVec.ofNat 64 512
def loadAddress : Machine.Address := entry + BitVec.ofNat 64 moveEntry.length
def firstPushAddress : Machine.Address := loadAddress + BitVec.ofNat 64 loadContext.length
def secondPushAddress : Machine.Address := firstPushAddress + BitVec.ofNat 64 pushContext.length
def saveAddress : Machine.Address := secondPushAddress + BitVec.ofNat 64 pushStack.length
def clearAddress : Machine.Address := saveAddress + BitVec.ofNat 64 saveContext.length
def callAddress : Machine.Address := clearAddress + BitVec.ofNat 64 clearFrame.length

structure SliceEvidence (elf : List UInt8) (expected : Nat) (bytes : List UInt8) where
  offset : Nat
  offsetExact : offset = expected
  offsetBound : expected + bytes.length ≤ elf.length
  bytesExact : (elf.drop offset).take bytes.length = bytes

abbrev StartupEvidence (elf : List UInt8) := SliceEvidence elf 256 startupBytes
def programJumpBytes : List UInt8 := jumpBytes (BitVec.ofNat 32 0)
abbrev JumpEvidence (elf : List UInt8) (displacement : BitVec 32) :=
  SliceEvidence elf 512 (jumpBytes displacement)
abbrev ZeroJumpEvidence (elf : List UInt8) :=
  JumpEvidence elf (BitVec.ofNat 32 0)

def checkSlice (elf : List UInt8) (expected : Nat) (bytes : List UInt8) :
    Option (SliceEvidence elf expected bytes) :=
  if bound : expected + bytes.length ≤ elf.length then
    if exact : (elf.drop expected).take bytes.length = bytes then
      some ⟨expected, rfl, bound, exact⟩
    else none
  else none

def check (elf : List UInt8) : Option (StartupEvidence elf) := checkSlice elf 256 startupBytes

theorem SliceEvidence.loaded {elf : List UInt8} {memory : Machine.Memory}
    {expected : Nat} {bytes : List UInt8} (checked : SliceEvidence elf expected bytes)
    (mapped : CodeAt memory base elf) :
    CodeAt memory (base + BitVec.ofNat 64 expected) bytes := by
  intro index bound
  have total := checked.offsetBound
  have sourceBound : expected + index < elf.length := by omega
  have bytesExact := checked.bytesExact
  rw [checked.offsetExact] at bytesExact
  have equality := congrArg (fun values : List UInt8 => values[index]?) bytesExact
  simp only [List.getElem?_take, List.getElem?_drop, if_pos bound] at equality
  have sourceSlice? : elf[expected + index]? = some bytes[index] := by
    simpa only [List.getElem?_eq_getElem sourceBound,
      List.getElem?_eq_getElem bound] using equality
  have sourceSlice : elf[expected + index] = bytes[index] :=
    Option.some.inj ((List.getElem?_eq_getElem sourceBound).symm.trans sourceSlice?)
  calc
    memory ((base + BitVec.ofNat 64 expected) + BitVec.ofNat 64 index) =
        memory (base + BitVec.ofNat 64 expected + BitVec.ofNat 64 index) := by rfl
    _ = memory (base + BitVec.ofNat 64 (expected + index)) := by
      congr 1
      rw [BitVec.add_assoc, ← BitVec.ofNat_add]
    _ = elf[expected + index] := mapped (expected + index) sourceBound
    _ = bytes[index] := sourceSlice

theorem StartupEvidence.loaded {elf : List UInt8} {memory : Machine.Memory} (checked : StartupEvidence elf)
    (mapped : CodeAt memory base elf) : CodeAt memory entry startupBytes := by
  change CodeAt memory (base + BitVec.ofNat 64 256) startupBytes
  exact SliceEvidence.loaded checked mapped

def jumpTarget (displacement : BitVec 32) : Machine.Address :=
  code + BitVec.ofNat 64 (jumpBytes displacement).length + displacement.signExtend 64

def functionEntry : Machine.Address := jumpTarget (BitVec.ofNat 32 0)

def checkJump (elf : List UInt8) (displacement : BitVec 32) :
    Option (JumpEvidence elf displacement) :=
  checkSlice elf 512 (jumpBytes displacement)

theorem JumpEvidence.loaded {elf : List UInt8} {memory : Machine.Memory}
    {displacement : BitVec 32} (checked : JumpEvidence elf displacement)
    (mapped : CodeAt memory base elf) : CodeAt memory code (jumpBytes displacement) := by
  change CodeAt memory (base + BitVec.ofNat 64 512) (jumpBytes displacement)
  exact SliceEvidence.loaded checked mapped

theorem jump_reaches_target {before after : Machine.State}
    {displacement : BitVec 32} (ripAtCode : before.rip = code)
    (loaded : CodeAt before.memory before.rip (jumpBytes displacement))
    (stepResult : after = before.jump displacement (jumpBytes displacement).length) :
    Step before after ∧ after.rip = jumpTarget displacement := by
  constructor
  · exact jump_step before after displacement loaded stepResult
  · rw [stepResult]
    change before.rip + BitVec.ofNat 64 (jumpBytes displacement).length +
      displacement.signExtend 64 = jumpTarget displacement
    rw [ripAtCode]
    rfl

theorem jump_reaches_entry {before after : Machine.State}
    (ripAtCode : before.rip = code)
    (loaded : CodeAt before.memory before.rip programJumpBytes)
    (stepResult : after = before.jump (BitVec.ofNat 32 0) programJumpBytes.length) :
    Step before after ∧ after.rip = functionEntry := by
  exact jump_reaches_target ripAtCode loaded stepResult

theorem startup_head {memory : Machine.Memory}
    (loaded : CodeAt memory entry startupBytes) :
    CodeAt memory entry (moveEntry ++ afterMoveBytes) := by
  have first : CodeAt memory entry
      (startupPrefix ++ returnResult ++ loadExit ++ syscallBytes ++ ud2Bytes) := CodeAt.prefix loaded
  have second : CodeAt memory entry startupPrefix := CodeAt.prefix first
  simpa only [startupPrefix] using second

/- One linear-layout rule supplies every instruction chunk.  Keeping the
   prefix explicit makes the address calculation part of the proof instead of
   duplicating a suffix chain for each startup instruction. -/
theorem linear_chunk {memory : Machine.Memory} {leading chunk rest : List UInt8}
    (loaded : CodeAt memory entry (leading ++ chunk ++ rest)) :
    CodeAt memory (entry + BitVec.ofNat 64 leading.length) chunk := by
  have tail : CodeAt memory entry (leading ++ (chunk ++ rest)) := by
    simpa only [List.append_assoc] using loaded
  exact CodeAt.prefix (CodeAt.suffix (first := leading) (rest := chunk ++ rest) tail)

theorem keep_memory {before after : Machine.State} {address : Machine.Address} {bytes : List UInt8}
    (loaded : CodeAt before.memory address bytes) (same : after.memory = before.memory) :
    CodeAt after.memory address bytes := by rw [same]; exact loaded

theorem keep_write64 {before : Machine.State} {address store : Machine.Address}
    {bytes : List UInt8} (value : BitVec 64) (loaded : CodeAt before.memory address bytes)
    (disjoint : ∀ index, index < bytes.length → ∀ lane : Fin 8,
      address + BitVec.ofNat 64 index ≠ store + BitVec.ofNat 64 lane.val) :
    CodeAt (Machine.write64 before.memory store value) address bytes :=
  CodeAt.write64 loaded value disjoint

def afterMove (before : Machine.State) : Machine.State := before.move64 r10 rsp moveEntry.length
def afterLoad (before : Machine.State) : Machine.State :=
  (afterMove before).immediate32 rax (BitVec.ofNat 32 3) loadContext.length
def afterFirstPush (before : Machine.State) : Machine.State :=
  (afterLoad before).push64 rax pushContext.length
def afterSecondPush (before : Machine.State) : Machine.State :=
  (afterFirstPush before).push64 r10 pushStack.length
def afterSave (before : Machine.State) : Machine.State :=
  (afterSecondPush before).move64 r15 rsp saveContext.length
def afterClear (before : Machine.State) : Machine.State :=
  (afterSave before).alu32 .xor rbp rbp false clearFrame.length
def afterCall (before : Machine.State) : Machine.State :=
  (afterClear before).call (BitVec.ofNat 32 235) callCode.length

theorem advance_rip {before after : Machine.State} {address : Machine.Address}
    (h : before.rip = address) (next : after.rip = before.rip + BitVec.ofNat 64 size) :
    after.rip = address + BitVec.ofNat 64 size := by
  rw [next, h]

theorem startup_rips {before} (h : before.rip = entry) :
    (afterMove before).rip = loadAddress ∧
    (afterLoad before).rip = firstPushAddress ∧
    (afterFirstPush before).rip = secondPushAddress ∧
    (afterSecondPush before).rip = saveAddress ∧
    (afterSave before).rip = clearAddress ∧
    (afterClear before).rip = callAddress := by
  exact ⟨advance_rip h rfl, advance_rip (advance_rip h rfl) rfl,
    advance_rip (advance_rip (advance_rip h rfl) rfl) rfl,
    advance_rip (advance_rip (advance_rip (advance_rip h rfl) rfl) rfl) rfl,
    advance_rip (advance_rip (advance_rip (advance_rip (advance_rip h rfl) rfl) rfl) rfl) rfl,
    advance_rip (advance_rip (advance_rip (advance_rip (advance_rip (advance_rip h rfl) rfl) rfl) rfl) rfl) rfl⟩

def StackDisjoint (before : Machine.State) : Prop :=
  ∀ index, index < startupBytes.length → ∀ lane : Fin 8,
    entry + BitVec.ofNat 64 index ≠ before.registers rsp - 8 + BitVec.ofNat 64 lane.val ∧
    entry + BitVec.ofNat 64 index ≠ before.registers rsp - 16 + BitVec.ofNat 64 lane.val
def CodeStackDisjoint (before : Machine.State) (displacement : BitVec 32) : Prop :=
  ∀ index, index < (jumpBytes displacement).length → ∀ lane : Fin 8,
    code + BitVec.ofNat 64 index ≠ before.registers rsp - 8 + BitVec.ofNat 64 lane.val ∧
    code + BitVec.ofNat 64 index ≠ before.registers rsp - 16 + BitVec.ofNat 64 lane.val ∧
    code + BitVec.ofNat 64 index ≠ before.registers rsp - 24 + BitVec.ofNat 64 lane.val

theorem sub_twice (v : Machine.Address) : v - 8 - 8 = v - 16 := by
  rw [BitVec.sub_sub]; change v - BitVec.ofNat 64 (8 + 8) = v - BitVec.ofNat 64 16; rfl
theorem sub_sixteen_eight (v : Machine.Address) : v - 16 - 8 = v - 24 := by
  rw [BitVec.sub_sub]; change v - BitVec.ofNat 64 24 = v - BitVec.ofNat 64 24; rfl
theorem after_first_rsp {before : Machine.State} :
    (afterFirstPush before).registers rsp - 8 = before.registers rsp - 16 := by
  change (before.registers rsp - 8) - 8 = _; exact sub_twice _

theorem startup_steps {before : Machine.State} (ripAtEntry : before.rip = entry)
    (loaded : CodeAt before.memory before.rip startupBytes)
    (disjoint : StackDisjoint before) : Steps 7 before (afterCall before) := by
  have h0 : CodeAt before.memory entry startupBytes := by simpa only [ripAtEntry] using loaded
  have rips := startup_rips ripAtEntry
  have moveLoaded : CodeAt before.memory before.rip moveEntry := by
    simpa only [ripAtEntry] using CodeAt.prefix (startup_head h0)
  have moveStep : Step before (afterMove before) := by
    apply move_step before _ .w64 r10 rsp moveLoaded
    rfl
  have h1 : CodeAt (afterMove before).memory entry startupBytes := by
    exact keep_memory h0 rfl
  have loadLoaded : CodeAt (afterMove before).memory (afterMove before).rip loadContext := by
    simpa only [rips.1, loadAddress] using
      (linear_chunk (leading := moveEntry) (chunk := loadContext)
        (rest := pushContext ++ pushStack ++ saveContext ++ clearFrame ++ callCode)
        (by simpa only [afterMoveBytes, List.append_assoc] using startup_head h1))
  have loadStep : Step (afterMove before) (afterLoad before) := by
    apply immediate_step _ _ .w32 rax (BitVec.ofNat 32 3) 0 loadLoaded
    rfl
  have h2 : CodeAt (afterLoad before).memory entry startupBytes := by
    exact keep_memory h1 rfl
  have firstLoaded : CodeAt (afterLoad before).memory (afterLoad before).rip pushContext := by
    simpa only [rips.2.1, firstPushAddress, loadAddress, List.length_append, BitVec.ofNat_add, BitVec.add_assoc] using
      (linear_chunk (leading := moveEntry ++ loadContext) (chunk := pushContext)
        (rest := pushStack ++ saveContext ++ clearFrame ++ callCode)
        (by simpa only [afterMoveBytes, List.append_assoc] using startup_head h2))
  have firstStep : Step (afterLoad before) (afterFirstPush before) := by
    apply push_step _ _ rax firstLoaded
    rfl
  have h3 : CodeAt (afterFirstPush before).memory entry startupBytes := by
    simpa only [afterFirstPush, Machine.State.push64, rax, rsp] using
      keep_write64 (store := (afterLoad before).registers rsp - 8)
        (value := (afterLoad before).registers rax) h2
        (fun i b l => (disjoint i b l).1)
  have secondLoaded : CodeAt (afterFirstPush before).memory (afterFirstPush before).rip pushStack := by
    simpa only [rips.2.2.1, secondPushAddress, firstPushAddress, loadAddress, List.length_append, BitVec.ofNat_add, BitVec.add_assoc] using
      (linear_chunk (leading := moveEntry ++ loadContext ++ pushContext) (chunk := pushStack)
        (rest := saveContext ++ clearFrame ++ callCode)
        (by simpa only [afterMoveBytes, List.append_assoc] using startup_head h3))
  have d2 : ∀ i, i < startupBytes.length → ∀ l : Fin 8,
      entry + BitVec.ofNat 64 i ≠ (afterFirstPush before).registers rsp - 8 + BitVec.ofNat 64 l.val := by
    intro i b l
    rw [after_first_rsp]
    exact (disjoint i b l).2
  have secondStep : Step (afterFirstPush before) (afterSecondPush before) := by
    apply push_step _ _ r10 secondLoaded
    rfl
  have h4 : CodeAt (afterSecondPush before).memory entry startupBytes := by
    simpa only [afterSecondPush, Machine.State.push64, r10, rsp] using
      keep_write64 (store := (afterFirstPush before).registers rsp - 8)
        (value := (afterFirstPush before).registers r10) h3 d2
  have saveLoaded : CodeAt (afterSecondPush before).memory (afterSecondPush before).rip saveContext := by
    simpa only [rips.2.2.2.1, saveAddress, secondPushAddress, firstPushAddress, loadAddress, List.length_append, BitVec.ofNat_add, BitVec.add_assoc] using
      (linear_chunk (leading := moveEntry ++ loadContext ++ pushContext ++ pushStack)
        (chunk := saveContext) (rest := clearFrame ++ callCode)
        (by simpa only [afterMoveBytes, List.append_assoc] using startup_head h4))
  have saveStep : Step (afterSecondPush before) (afterSave before) := by
    apply move_step _ _ .w64 r15 rsp saveLoaded
    rfl
  have h5 : CodeAt (afterSave before).memory entry startupBytes := by
    exact keep_memory h4 rfl
  have clearLoaded : CodeAt (afterSave before).memory (afterSave before).rip clearFrame := by
    simpa only [rips.2.2.2.2.1, clearAddress, saveAddress, secondPushAddress, firstPushAddress, loadAddress, List.length_append, BitVec.ofNat_add, BitVec.add_assoc] using
      (linear_chunk (leading := moveEntry ++ loadContext ++ pushContext ++ pushStack ++ saveContext)
        (chunk := clearFrame) (rest := callCode)
        (by simpa only [afterMoveBytes, List.append_assoc] using startup_head h5))
  have clearStep : Step (afterSave before) (afterClear before) := by
    apply alu_step .w32 _ _ .xor rbp rbp clearLoaded false
    rfl
  have h6 : CodeAt (afterClear before).memory entry startupBytes := by
    exact keep_memory h5 rfl
  have callLoaded : CodeAt (afterClear before).memory (afterClear before).rip callCode := by
    simpa only [rips.2.2.2.2.2, callAddress, clearAddress, saveAddress, secondPushAddress, firstPushAddress, loadAddress, List.length_append, BitVec.ofNat_add, BitVec.add_assoc] using
      (linear_chunk (leading := moveEntry ++ loadContext ++ pushContext ++ pushStack ++ saveContext ++ clearFrame)
        (chunk := callCode) (rest := [])
        (by simpa only [afterMoveBytes, List.append_assoc, List.append_nil] using startup_head h6))
  have callStep : Step (afterClear before) (afterCall before) := by
    apply call_step _ _ (BitVec.ofNat 32 235) callLoaded
    rfl
  exact Steps.cons moveStep <| Steps.cons loadStep <| Steps.cons firstStep <|
    Steps.cons secondStep <| Steps.cons saveStep <| Steps.cons clearStep <|
    Steps.cons callStep (Steps.refl _)

theorem clear_rsp {before : Machine.State} :
    (afterClear before).registers rsp = before.registers rsp - 16 := by
  simp [afterClear, afterSave, afterSecondPush, afterFirstPush, afterLoad, afterMove, Machine.State.alu32,
    Machine.State.alu, Machine.State.move64, Machine.State.push64, Machine.State.immediate32, rax, rsp, rbp]; exact sub_twice _

theorem reaches_code {before : Machine.State} (ripAtEntry : before.rip = entry)
    (loaded : CodeAt before.memory before.rip startupBytes) (disjoint : StackDisjoint before) :
    Steps 7 before (afterCall before) ∧ (afterCall before).rip = code ∧
      (afterCall before).registers rsp = before.registers rsp - 24 ∧
      (afterCall before).registers r15 = before.registers rsp - 16 ∧
      (afterCall before).registers rbp = 0 := by
  have steps := startup_steps ripAtEntry loaded disjoint
  have rips := startup_rips ripAtEntry
  have clearR15 : (afterClear before).registers r15 = before.registers rsp - 16 := by
    simp [afterClear, afterSave, afterSecondPush, afterFirstPush, afterLoad, afterMove,
      Machine.State.alu32, Machine.State.alu, Machine.State.move64, Machine.State.push64,
      Machine.State.immediate32, rax, rsp, rbp, r15, r10]
    exact sub_twice _
  have clearRbp : (afterClear before).registers rbp = 0 := by
    simp [afterClear, Machine.State.alu32, Machine.State.alu, rbp, Alu.result, BitVec.xor_self]
  have callRip : (afterCall before).rip = code := by
    change (afterClear before).rip + BitVec.ofNat 64 callCode.length +
      (BitVec.ofNat 32 235).signExtend 64 = code
    rw [rips.2.2.2.2.2]
    decide
  have callRsp : (afterCall before).registers rsp = before.registers rsp - 24 := by
    change (afterClear before).registers rsp - 8 = _
    rw [clear_rsp]
    exact sub_sixteen_eight _
  have callR15 : (afterCall before).registers r15 = before.registers rsp - 16 := by
    change (afterClear before).registers r15 = _
    exact clearR15
  have callRbp : (afterCall before).registers rbp = 0 := by
    change (afterClear before).registers rbp = _
    exact clearRbp
  exact ⟨steps, callRip, callRsp, callR15, callRbp⟩

theorem jump_preserved {before : Machine.State}
    {displacement : BitVec 32}
    (jumpLoaded : CodeAt before.memory code (jumpBytes displacement))
    (codeStackDisjoint : CodeStackDisjoint before displacement) :
    CodeAt (afterCall before).memory code (jumpBytes displacement) := by
  have d2 : ∀ i, i < (jumpBytes displacement).length → ∀ l : Fin 8,
      code + BitVec.ofNat 64 i ≠ (afterFirstPush before).registers rsp - 8 + BitVec.ofNat 64 l.val := by
    intro i b l
    rw [after_first_rsp]
    exact (codeStackDisjoint i b l).2.1
  have d3addr : (afterClear before).registers rsp - 8 = before.registers rsp - 24 := by
    rw [clear_rsp]
    exact sub_sixteen_eight _
  have d3 : ∀ i, i < (jumpBytes displacement).length → ∀ l : Fin 8,
      code + BitVec.ofNat 64 i ≠ (afterClear before).registers rsp - 8 + BitVec.ofNat 64 l.val := by
    intro i b l
    rw [d3addr]
    exact (codeStackDisjoint i b l).2.2
  have j2 : CodeAt (afterLoad before).memory code (jumpBytes displacement) := by
    exact keep_memory jumpLoaded rfl
  have j3 : CodeAt (afterFirstPush before).memory code (jumpBytes displacement) := by
    simpa only [afterFirstPush, Machine.State.push64, rax, rsp] using
      keep_write64 (store := (afterLoad before).registers rsp - 8)
        (value := (afterLoad before).registers rax) j2
        (fun i b l => (codeStackDisjoint i b l).1)
  have j4 : CodeAt (afterSecondPush before).memory code (jumpBytes displacement) := by
    simpa only [afterSecondPush, Machine.State.push64, r10, rsp] using
      keep_write64 (store := (afterFirstPush before).registers rsp - 8)
        (value := (afterFirstPush before).registers r10) j3 d2
  have j6 : CodeAt (afterClear before).memory code (jumpBytes displacement) := by
    exact keep_memory j4 rfl
  have j7 : CodeAt (afterCall before).memory code (jumpBytes displacement) := by
    simpa only [afterCall, Machine.State.call, rsp] using
      keep_write64 (store := (afterClear before).registers rsp - 8)
        (value := (afterClear before).rip + BitVec.ofNat 64 callCode.length) j6 d3
  exact j7

/-- The caller-facing startup contract.  The ELF slices and the mapped image
    are separate evidence; this groups only the machine-layout obligations. -/
structure StartupLayout (before : Machine.State) (displacement : BitVec 32) : Prop where
  ripAtEntry : before.rip = entry
  stackDisjoint : StackDisjoint before
  codeStackDisjoint : CodeStackDisjoint before displacement

/-- Authenticate the two ELF slices and execute the complete startup boundary:
    entry -> CALL target (CODE) -> the authenticated program jump -> function.
    The returned state is the actual state expression, so callers do not need
    to manufacture an intermediate machine state or reassemble the jump. -/
theorem reaches_function {elf : List UInt8} {before : Machine.State}
    {displacement : BitVec 32} (startup : StartupEvidence elf)
    (jump : JumpEvidence elf displacement) (mapped : CodeAt before.memory base elf)
    (layout : StartupLayout before displacement) :
    Steps 8 before ((afterCall before).jump displacement (jumpBytes displacement).length) ∧
      ((afterCall before).jump displacement (jumpBytes displacement).length).rip =
        jumpTarget displacement := by
  have startupLoaded : CodeAt before.memory before.rip startupBytes := by
    simpa only [layout.ripAtEntry] using startup.loaded mapped
  have reached := reaches_code layout.ripAtEntry startupLoaded layout.stackDisjoint
  have preserved := jump_preserved (jump.loaded mapped) layout.codeStackDisjoint
  have jumpLoaded : CodeAt (afterCall before).memory (afterCall before).rip
      (jumpBytes displacement) := by
    simpa only [reached.2.1] using preserved
  have jumped := jump_reaches_target reached.2.1 jumpLoaded rfl
  exact ⟨Steps.trans reached.1 (Steps.cons jumped.1 (Steps.refl _)), jumped.2⟩

end Lanius.X86.StartupCheck
