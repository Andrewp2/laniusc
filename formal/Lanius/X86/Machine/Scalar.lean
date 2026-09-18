import Lanius.X86.Machine.Memory
import Lanius.X86.Machine.Alu
import Lanius.X86.Register
import Lanius.X86.Control.Decode

namespace Lanius.X86.Machine

inductive Instruction where
  | move32 (destination source : Register)
  | move64 (destination source : Register)
  | load32 (destination base : Register) (displacement : BitVec 32)
  | store32 (source base : Register) (displacement : BitVec 32)
  | load64 (destination base : Register) (displacement : BitVec 32)
  | store64 (source base : Register) (displacement : BitVec 32)
  | immediate32 (destination : Register) (value : BitVec 32)
  | immediate64 (destination : Register) (value : BitVec 64)
  | push64 (source : Register)
  | pop64 (destination : Register)
  | subtract64 (destination source : Register)
  | alu32 (operation : Alu) (destination source : Register)
  | compare64 (left right : Register)
  | compare32 (left right : Register)
  | test32 (left right : Register)
  | signExtend32 (destination source : Register)
  | setCondition (condition : Fin 16) (destination : Register)
  | zeroExtendByte (destination source : Register)
  | address64 (destination base : Register) (index : Option Register) (scale : Fin 4) (displacement : BitVec 32)
  | branch (condition : Fin 16) (displacement : BitVec 32)
  | returnNear
  deriving DecidableEq, Repr

def extendRegister (low : Fin 8) (high : Bool) : Register :=
  ⟨low.val + if high then 8 else 0, by split <;> omega⟩

/-- The eight little-endian immediate bytes of REX.W + B8+rd io.
Unlike REX.W + C7 /0 id, this form does not sign-extend a 32-bit operand.
Intel SDM vol. 2B, MOV opcode table and operation (4-35–4-37). -/
def immediate64? (bytes : List UInt8) : Option (BitVec 64) := do
  let low ← Control.displacement? bytes
  let high ← Control.displacement? (bytes.drop 4)
  pure (BitVec.ofNat 64 (low.toNat + 4294967296 * high.toNat))

/-- Decode the emitter's base+disp32 addressing form. SIB is accepted only
for the no-index RSP/R12 form. REX.X would turn that into an R12 index and is
therefore rejected. Other legal x86 addressing modes remain unsupported. -/
def memoryForm (rex : X86.Register.Rex) (opcode : Nat) (modrm : UInt8)
    (rest : List UInt8) : Option (Instruction × Nat) := do
  if modrm.toNat / 64 != 2 then none else do
    let reg := extendRegister ⟨modrm.toNat / 8 % 8, by omega⟩ rex.r
    let base := extendRegister ⟨modrm.toNat % 8, by omega⟩ rex.b
    let (remaining, size) ← if modrm.toNat % 8 = 4 then
        match rest with
        | 36 :: remaining => if rex.x then none else some (remaining, 7)
        | _ => none
      else some (rest, 6)
    let displacement ← Control.displacement? remaining
    if opcode = 139 then some (if rex.w then .load64 reg base displacement else .load32 reg base displacement, size)
    else if opcode = 137 then some (if rex.w then .store64 reg base displacement else .store32 reg base displacement, size)
    else none

/-- LEA reads no data memory. Decode base+disp32 and base+index*scale+disp32
forms in 64-bit address/operand mode, including the SIB no-index encoding. -/
def addressForm (rex : X86.Register.Rex) (modrm : UInt8) (rest : List UInt8) : Option (Instruction × Nat) := do
  if !rex.w || modrm.toNat / 64 != 2 then none else do
    let destination := extendRegister ⟨modrm.toNat / 8 % 8, by omega⟩ rex.r
    if modrm.toNat % 8 = 4 then
      match rest with
      | [] => none
      | sib :: remaining => do
        let base := extendRegister ⟨sib.toNat % 8, by omega⟩ rex.b
        let index := if sib.toNat / 8 % 8 = 4 && !rex.x then none
          else some (extendRegister ⟨sib.toNat / 8 % 8, by omega⟩ rex.x)
        let scale : Fin 4 := ⟨sib.toNat / 64, by have := UInt8.toNat_lt sib; omega⟩
        let displacement ← Control.displacement? remaining
        pure (.address64 destination base index scale displacement, 7)
    else do
      let base := extendRegister ⟨modrm.toNat % 8, by omega⟩ rex.b
      let displacement ← Control.displacement? rest
      pure (.address64 destination base none 0 displacement, 6)

/-- A REX prefix, even 0x40, selects SPL/BPL/SIL/DIL rather than AH/CH/DH/BH.
The legacy high-byte forms and memory byte operands are outside this subset. -/
def byteRegister? (rex : X86.Register.Rex) (rexPresent : Bool) (modrm : UInt8) : Option Register :=
  if rexPresent || modrm.toNat % 8 < 4 then
    some (extendRegister ⟨modrm.toNat % 8, by omega⟩ rex.b)
  else none

def escapedForm (rex : X86.Register.Rex) (rexPresent : Bool) (bytes : List UInt8) : Option (Instruction × Nat) :=
  match bytes with
  | opcode :: modrm :: _ =>
    if cc : 144 ≤ opcode.toNat ∧ opcode.toNat < 160 then do
      if modrm.toNat / 64 != 3 then none else do
        let destination ← byteRegister? rex rexPresent modrm
        pure (.setCondition ⟨opcode.toNat - 144, by omega⟩ destination, 3)
    else if opcode.toNat = 182 then do
      if modrm.toNat / 64 != 3 then none else do
        let source ← byteRegister? rex rexPresent modrm
        pure (.zeroExtendByte (extendRegister ⟨modrm.toNat / 8 % 8, by omega⟩ rex.r) source, 3)
    else match Control.decode (15 :: bytes) with
      | some (.branch condition displacement, size) => some (.branch condition displacement, size)
      | _ => none
  | _ => none

def decodeOpcode (rex : X86.Register.Rex) (rexPresent : Bool) : List UInt8 → Option (Instruction × Nat)
  | [] => none
  | opcode :: rest =>
    if opcode.toNat = 195 then some (.returnNear, 1)
    else if push : 80 ≤ opcode.toNat ∧ opcode.toNat < 88 then
      some (.push64 (extendRegister ⟨opcode.toNat - 80, by omega⟩ rex.b), 1)
    else if pop : 88 ≤ opcode.toNat ∧ opcode.toNat < 96 then
      some (.pop64 (extendRegister ⟨opcode.toNat - 88, by omega⟩ rex.b), 1)
    else if immediate : 184 ≤ opcode.toNat ∧ opcode.toNat < 192 then do
      if rex.w then do
        let value ← immediate64? rest
        pure (.immediate64 (extendRegister ⟨opcode.toNat - 184, by omega⟩ rex.b) value, 9)
      else do
        let value ← Control.displacement? rest
        pure (.immediate32 (extendRegister ⟨opcode.toNat - 184, by omega⟩ rex.b) value, 5)
    else if opcode.toNat = 137 || opcode.toNat = 139 then
      match rest with
      | [] => none
      | modrm :: remaining =>
        if modrm.toNat / 64 = 3 then
          let reg := extendRegister ⟨modrm.toNat / 8 % 8, by omega⟩ rex.r
          let rm := extendRegister ⟨modrm.toNat % 8, by omega⟩ rex.b
          let (destination, source) := if opcode.toNat = 137 then (rm, reg) else (reg, rm)
          some (if rex.w then .move64 destination source else .move32 destination source, 2)
        else memoryForm rex opcode.toNat modrm remaining
    else if (opcode.toNat = 41 && rex.w) || opcode.toNat = 57 then
      match rest with
      | [] => none
      | modrm :: _ =>
        if (rex.w || opcode.toNat = 57) && modrm.toNat / 64 = 3 then
          let left := extendRegister ⟨modrm.toNat % 8, by omega⟩ rex.b
          let right := extendRegister ⟨modrm.toNat / 8 % 8, by omega⟩ rex.r
          some (if opcode.toNat = 57 then
            (if rex.w then .compare64 left right else .compare32 left right)
            else .subtract64 left right, 2)
        else none
    else if let some operation := Alu.ofOpcode? opcode.toNat then
      match rest with
      | modrm :: _ => if !rex.w && modrm.toNat / 64 = 3 then
          some (.alu32 operation (extendRegister ⟨modrm.toNat % 8, by omega⟩ rex.b)
            (extendRegister ⟨modrm.toNat / 8 % 8, by omega⟩ rex.r), 2)
        else none
      | [] => none
    else if opcode.toNat = 133 then
      match rest with
      | modrm :: _ => if !rex.w && modrm.toNat / 64 = 3 then
          some (.test32 (extendRegister ⟨modrm.toNat % 8, by omega⟩ rex.b)
            (extendRegister ⟨modrm.toNat / 8 % 8, by omega⟩ rex.r), 2)
        else none
      | [] => none
    else if opcode.toNat = 99 then
      match rest with
      | modrm :: _ => if rex.w && modrm.toNat / 64 = 3 then
          some (.signExtend32 (extendRegister ⟨modrm.toNat / 8 % 8, by omega⟩ rex.r)
            (extendRegister ⟨modrm.toNat % 8, by omega⟩ rex.b), 2)
        else none
      | [] => none
    else if opcode.toNat = 141 then
      match rest with | modrm :: remaining => addressForm rex modrm remaining | [] => none
    else if opcode.toNat = 15 then
      escapedForm rex rexPresent rest
    else none

/-- One optional REX prefix followed by supported MOV/MOVSXD/MOVZX, SETcc, LEA, register
PUSH/POP, ADD/SUB/AND/OR/XOR32, SUB64/CMP64, TEST32, Jcc, or near RET.
`none` means unsupported or truncated, not invalid ISA.
Instruction sizes include prefixes; displacement decoding ignores the tail. -/
def decode : List UInt8 → Option (Instruction × Nat)
  | [] => none
  | first :: rest => match X86.Register.Rex.decode? first.toNat with
      | some rex => (decodeOpcode rex true rest).map fun (instruction, size) => (instruction, size + 1)
      | none => decodeOpcode ⟨false, false, false, false⟩ false (first :: rest)

def State.move64 (before : State) (destination source : Register) (size : Nat) : State :=
  { before with
    registers := fun register => if register = destination then before.registers source else before.registers register
    rip := before.rip + BitVec.ofNat 64 size }

def State.immediate32 (before : State) (destination : Register) (value : BitVec 32) (size : Nat) : State :=
  { before with
    registers := fun register => if register = destination then value.setWidth 64 else before.registers register
    rip := before.rip + BitVec.ofNat 64 size }

/-- MOV r64, imm64 replaces all 64 destination bits and leaves flags alone. -/
def State.immediate64 (before : State) (destination : Register) (value : BitVec 64) (size : Nat) : State :=
  { before with
    registers := fun register => if register = destination then value else before.registers register
    rip := before.rip + BitVec.ofNat 64 size }

def State.load32 (before : State) (destination base : Register) (displacement : BitVec 32) (size : Nat) : State :=
  before.immediate32 destination (read32 before.memory (before.registers base + displacement.signExtend 64)) size

def State.store32 (before : State) (source base : Register) (displacement : BitVec 32) (size : Nat) : State :=
  { before with
    memory := write32 before.memory (before.registers base + displacement.signExtend 64)
      ((before.registers source).setWidth 32)
    rip := before.rip + BitVec.ofNat 64 size }

def State.load64 (before : State) (destination base : Register) (displacement : BitVec 32) (size : Nat) : State :=
  { before with
    registers := fun register => if register = destination then
      read64 before.memory (before.registers base + displacement.signExtend 64) else before.registers register
    rip := before.rip + BitVec.ofNat 64 size }

def State.store64 (before : State) (source base : Register) (displacement : BitVec 32) (size : Nat) : State :=
  { before with
    memory := write64 before.memory (before.registers base + displacement.signExtend 64) (before.registers source)
    rip := before.rip + BitVec.ofNat 64 size }

def State.move32 (before : State) (destination source : Register) (size : Nat) : State :=
  { before with
    registers := fun register => if register = destination then
      ((before.registers source).setWidth 32).setWidth 64 else before.registers register
    rip := before.rip + BitVec.ofNat 64 size }

def State.returnNear (before : State) : State :=
  { before with
    registers := fun register => if register = 4 then before.registers 4 + 8 else before.registers register
    rip := read64 before.memory (before.registers 4) }

/-- PUSH reads the source before decrementing RSP, including PUSH RSP. -/
def State.push64 (before : State) (source : Register) (size : Nat) : State :=
  { before with
    registers := fun register => if register = 4 then before.registers 4 - 8 else before.registers register
    memory := write64 before.memory (before.registers 4 - 8) (before.registers source)
    rip := before.rip + BitVec.ofNat 64 size }

/-- The popped value wins when the destination is RSP; it is read from the
old top of stack. No stack memory is erased by POP. -/
def State.pop64 (before : State) (destination : Register) (size : Nat) : State :=
  { before with
    registers := fun register => if register = destination then read64 before.memory (before.registers 4)
      else if register = 4 then before.registers 4 + 8 else before.registers register
    rip := before.rip + BitVec.ofNat 64 size }

def State.subtract64 (before : State) (destination source : Register) (size : Nat) : State :=
  { before with
    registers := fun register => if register = destination then before.registers destination - before.registers source
      else before.registers register
    flags := subtractFlags before.flags (before.registers destination) (before.registers source)
    rip := before.rip + BitVec.ofNat 64 size }

def State.compare64 (before : State) (left right : Register) (size : Nat) : State :=
  { before with
    flags := subtractFlags before.flags (before.registers left) (before.registers right)
    rip := before.rip + BitVec.ofNat 64 size }

/-- A 32-bit destination write clears its high half, including when both
operands name the same register. Operand reads precede that write. -/
def State.alu32 (before : State) (operation : Alu) (destination source : Register)
    (auxiliary : Bool) (size : Nat) : State :=
  let left := (before.registers destination).setWidth 32
  let right := (before.registers source).setWidth 32
  { before.immediate32 destination (operation.result left right) size with
    flags := operation.flags before.flags left right auxiliary }

/-- CMP r/m32,r32 observes only the low words and writes flags, not operands.
Intel SDM vol. 2A, CMP (3-153–3-154), opcode 39 /r; REX.W selects CMP64. -/
def State.compare32 (before : State) (left right : Register) (size : Nat) : State :=
  { before with
    flags := subtractFlags before.flags ((before.registers left).setWidth 32) ((before.registers right).setWidth 32)
    rip := before.rip + BitVec.ofNat 64 size }

/-- Both AF choices are permitted by `Step.tested`; every other effect is
fixed by the operands. In particular TEST does not zero the high RAX half. -/
def State.test32 (before : State) (left right : Register) (auxiliary : Bool) (size : Nat) : State :=
  { before with
    flags := logical32Flags before.flags
      ((before.registers left).setWidth 32 &&& (before.registers right).setWidth 32) auxiliary
    rip := before.rip + BitVec.ofNat 64 size }

def State.signExtend32 (before : State) (destination source : Register) (size : Nat) : State :=
  { before with
    registers := fun register => if register = destination then
      ((before.registers source).setWidth 32).signExtend 64 else before.registers register
    rip := before.rip + BitVec.ofNat 64 size }

/-- SETcc writes only the low byte; MOVZX subsequently clears the whole upper
part of the destination. Both preserve flags. Intel SDM vol. 2B, SETcc and
MOVZX (4-611–4-613, 4-136); the latter's 32/64-bit forms have the same effect. -/
def State.setCondition (before : State) (code : Fin 16) (destination : Register) (size : Nat) : State :=
  { before with
    registers := fun register => if register = destination then
      (before.registers register).extractLsb' 8 56 ++
        (if condition before.flags code then (1 : BitVec 8) else 0)
      else before.registers register
    rip := before.rip + BitVec.ofNat 64 size }

def State.zeroExtendByte (before : State) (destination source : Register) (size : Nat) : State :=
  { before with
    registers := fun register => if register = destination then
      ((before.registers source).setWidth 8).setWidth 64 else before.registers register
    rip := before.rip + BitVec.ofNat 64 size }

def State.address64 (before : State) (destination base : Register) (index : Option Register)
    (scale : Fin 4) (displacement : BitVec 32) (size : Nat) : State :=
  { before with
    registers := fun register => if register = destination then
      before.registers base + (match index with
        | none => 0 | some index => before.registers index * BitVec.ofNat 64 (2^scale.val)) +
          displacement.signExtend 64 else before.registers register
    rip := before.rip + BitVec.ofNat 64 size }

def State.branch (before : State) (code : Fin 16) (displacement : BitVec 32) (size : Nat) : State :=
  { before with rip := before.rip + BitVec.ofNat 64 size +
    if condition before.flags code then displacement.signExtend 64 else 0 }

def execute (instruction : Instruction) (size : Nat) (before : State) : State :=
  match instruction with
  | .move32 destination source => before.move32 destination source size
  | .move64 destination source => before.move64 destination source size
  | .load32 destination base displacement => before.load32 destination base displacement size
  | .store32 source base displacement => before.store32 source base displacement size
  | .load64 destination base displacement => before.load64 destination base displacement size
  | .store64 source base displacement => before.store64 source base displacement size
  | .immediate32 destination value => before.immediate32 destination value size
  | .immediate64 destination value => before.immediate64 destination value size
  | .push64 source => before.push64 source size
  | .pop64 destination => before.pop64 destination size
  | .subtract64 destination source => before.subtract64 destination source size
  | .alu32 operation destination source => before.alu32 operation destination source (before.flags.getLsbD 4) size
  | .compare64 left right => before.compare64 left right size
  | .compare32 left right => before.compare32 left right size
  -- A deterministic representative only. `Step.tested` includes both AF
  -- outcomes, and TEST continuation theorems quantify over that choice.
  | .test32 left right => before.test32 left right (before.flags.getLsbD 4) size
  | .signExtend32 destination source => before.signExtend32 destination source size
  | .setCondition code destination => before.setCondition code destination size
  | .zeroExtendByte destination source => before.zeroExtendByte destination source size
  | .address64 destination base index scale displacement => before.address64 destination base index scale displacement size
  | .branch code displacement => before.branch code displacement size
  | .returnNear => before.returnNear

/-- Decoding consumes bytes actually loaded at RIP. The pure register and
stack effects above cannot be substituted without that byte-level premise. -/
inductive Step (before : State) (after : State) : Prop where
  | decoded (bytes : List UInt8) (loaded : CodeAt before.memory before.rip bytes)
      (instruction : Instruction) (size : Nat) (decoded : decode bytes = some (instruction, size))
      (result : after = execute instruction size before)
  | tested (bytes : List UInt8) (loaded : CodeAt before.memory before.rip bytes)
      (left right : Register) (size : Nat) (decoded : decode bytes = some (.test32 left right, size))
      (auxiliary : Bool) (result : after = before.test32 left right auxiliary size)
  | arithmetic (bytes : List UInt8) (loaded : CodeAt before.memory before.rip bytes)
      (operation : Alu) (destination source : Register) (size : Nat)
      (decoded : decode bytes = some (.alu32 operation destination source, size))
      (auxiliary : Bool) (result : after = before.alu32 operation destination source auxiliary size)

/-- UD2 raises #UD at its own RIP. This records the architectural fault,
not a Linux signal handler or an assumed successful instruction transition. -/
inductive Fault (before : State) : Prop where
  | ud2 (loaded : CodeAt before.memory before.rip [15, 11])

/-- Finite instruction execution, used to compose body proofs with the
actual frame protocol without forgetting the intervening machine steps. -/
inductive Steps : Nat → State → State → Prop where
  | refl (state) : Steps 0 state state
  | cons : Step before middle → Steps count middle after → Steps (count + 1) before after

theorem Steps.trans (first : Steps left before middle) (second : Steps right middle after) :
    Steps (left + right) before after := by
  induction first with
  | refl => simpa using second
  | cons step tail ih => simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using Steps.cons step (ih second)

end Lanius.X86.Machine
