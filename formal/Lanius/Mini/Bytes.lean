import Lanius.Mini.Asm
import Lanius.X86.Machine.FrameSlots
import Lanius.X86.Machine.ControlEncoding
import Lanius.X86.Machine.DivisionEncoding

/-! Assembly. The extracted `Instr.encode` (`Lanius.Mini.Compiler`) writes
literal bytes; here each is proved equal to the existing encoders in
`X86/Machine/*Encoding.lean`, whose decoding the machine semantics uses, so
`Instr.encode` is `Instr.bytes` below. Jumps are relative to the end of the
instruction. A call copies its arguments to just below the return address it
pushes, which is where the callee's prologue puts its parameter slots.

A program image is its functions back to back, each the frame prologue
followed by its body. -/

namespace Lanius.Mini
open Lanius.X86.Machine

def BinOp.alu : BinOp → Alu
  | .add => .add
  | .sub => .subtract
  | .mul => .add
  | .and => .and
  | .or => .or
  | .xor => .xor
  | .shl | .shr | .sar => .add

/-- The x86 shift of a shift operator. -/
def BinOp.shift : BinOp → Shift
  | .shl => .left
  | .shr => .right
  | .sar => .arithmeticRight
  | .add | .sub | .mul | .and | .or | .xor => .left

/-- `mov rax, [rbp + disp32]` -/
def slotLoadBytes (slot : Nat) : List UInt8 :=
  memoryBytes .w64 true 0 rbpRegister (frameDisplacement slot)

/-- `mov [rbp + disp32], rax` -/
def slotStoreBytes (slot : Nat) : List UInt8 :=
  memoryBytes .w64 false 0 rbpRegister (frameDisplacement slot)

/-- `mov rcx, rax` -/
def accToRcxBytes : List UInt8 := moveBytes .w64 rcxRegister 0

def Word.width : Word → X86.Register.Width
  | .s32 => .w32
  | .u64 => .w64

/-- `op eax, ecx` or `op rax, rcx` -/
def BinOp.opBytes (word : Word) (operation : BinOp) : List UInt8 :=
  match operation with
  | .mul => multiplyBytes word.width 0 rcxRegister
  | .add | .sub | .and | .or | .xor => aluBytes word.width operation.alu 0 rcxRegister
  | .shl | .shr | .sar => shiftBytes word.width operation.shift 0

/-- The x86 encoding of `slot op rax` into rax. -/
def BinOp.spec (word : Word) (operation : BinOp) (slot : Nat) : List UInt8 :=
  accToRcxBytes ++ slotLoadBytes slot ++ operation.opBytes word

/-- `cmp eax, ecx` or `cmp rax, rcx` -/
def Word.compareBytes : Word → List UInt8
  | .s32 => Lanius.X86.Machine.compareBytes 0 rcxRegister
  | .u64 => [72, 57, 200]

/-- The condition code that holds after `cmp left, right` exactly when the
comparison does: signed for `s32`, unsigned for `u64`. -/
def CmpOp.code : Word → CmpOp → Fin 16
  | .s32, .eq => 4
  | .s32, .ne => 5
  | .s32, .lt => 12
  | .s32, .le => 14
  | .s32, .gt => 15
  | .s32, .ge => 13
  | .u64, .eq => 4
  | .u64, .ne => 5
  | .u64, .lt => 2
  | .u64, .le => 6
  | .u64, .gt => 7
  | .u64, .ge => 3

/-- `mov rcx, rax; mov rax, [slot]; cmp; setcc al; movzx eax, al` -/
def cmpBytes (word : Word) (operation : CmpOp) (slot : Nat) : List UInt8 :=
  accToRcxBytes ++ slotLoadBytes slot ++ word.compareBytes ++
    setConditionBytes (operation.code word) 0 ++ zeroExtendByteBytes 0 0

def rdxRegister : Register := 2
def rsiRegister : Register := 6
def rdiRegister : Register := 7

def DivOp.signed : DivOp → Bool
  | .sDiv | .sRem => true
  | .uDiv | .uRem => false

def DivOp.remainder : DivOp → Bool
  | .sDiv | .uDiv => false
  | .sRem | .uRem => true

/-- The dividend's high half: `cdq` or `cqo` for a signed division, `xor edx, edx`
for an unsigned one -/
def dividendBytes (word : Word) : Bool → List UInt8
  | true => signExtendDividendBytes word.width
  | false => aluBytes .w32 .xor rdxRegister rdxRegister

/-- `mov rax, rdx` for a remainder -/
def resultBytes : Bool → List UInt8
  | false => []
  | true => moveBytes .w64 0 rdxRegister

/-- The x86 encoding of `slot op rax` into rax: `mov rcx, rax; mov rax, [slot];
mov r11, rdx; cdq, cqo or xor edx, edx; idiv or div ecx (rcx); mov rax, rdx
for a remainder; mov rdx, r11`. rdx is not scratch, so r11 keeps it. -/
def DivOp.spec (word : Word) (operation : DivOp) (slot : Nat) : List UInt8 :=
  accToRcxBytes ++ slotLoadBytes slot ++ moveBytes .w64 r11Register rdxRegister ++
    (dividendBytes word operation.signed ++ divisionBytes word.width operation.signed rcxRegister) ++
    (resultBytes operation.remainder ++ moveBytes .w64 rdxRegister r11Register)

/-- The two 32-bit halves of a 64-bit immediate. -/
def lowHalf (value : BitVec 64) : BitVec 32 := value.setWidth 32
def highHalf (value : BitVec 64) : BitVec 32 := (value >>> 32).setWidth 32

def epilogueBytes : List UInt8 :=
  moveBytes .w64 rspRegister rbpRegister ++ popBytes rbpRegister ++ returnBytes

/-- The heap base, the allocation cursor and the heap limit (an offset). -/
def heapBaseRegister : Register := 12
def cursorRegister : Register := 13
def limitRegister : Register := 14

/-- `mov r11, imm64` -/
def r11Bytes (value : BitVec 64) : List UInt8 := immediateBytes .w64 r11Register (lowHalf value) (highHalf value)

/-- `cmp r11, r14` -/
def limitCompareBytes : List UInt8 := [77, 57, 243]

/-- `ud2` -/
def trapBytes : List UInt8 := [15, 11]

/-- r15 holds the lowest address the stack may reach. -/
def stackRegister : Register := 15

/-- `cmp r15, rsp` -/
def stackCompareBytes : List UInt8 := [73, 57, 231]

/-- After the frame prologue: fault unless r15 is at most rsp. -/
def stackCheckBytes : List UInt8 := stackCompareBytes ++ (branchBytes 6 2 ++ trapBytes)

/-- Round the cursor up into rcx, check that rcx + rax neither wraps nor
passes the limit, advance the cursor and return the old rounded cursor in rax. -/
def bumpSpec (shift : Nat) : List UInt8 :=
  moveBytes .w64 rcxRegister cursorRegister ++ (r11Bytes (pow2 shift - 1) ++
  (aluBytes .w64 .add rcxRegister r11Register ++ (r11Bytes (0 - pow2 shift) ++
  (aluBytes .w64 .and rcxRegister r11Register ++ (moveBytes .w64 r11Register rcxRegister ++
  (aluBytes .w64 .add r11Register 0 ++ (branchBytes 2 9 ++ (limitCompareBytes ++ (branchBytes 6 2 ++
  (trapBytes ++ (moveBytes .w64 cursorRegister r11Register ++ moveBytes .w64 0 rcxRegister)))))))))))

/-- `add rax, r12; movzx eax, byte [rax]` -/
def loadAtSpec : List UInt8 := aluBytes .w64 .add 0 heapBaseRegister ++ loadByteBytes 0 0 0

/-- `mov rcx, [slot]; add rcx, r12; mov [rcx], al` -/
def storeAtSpec (slot : Nat) : List UInt8 :=
  memoryBytes .w64 true rcxRegister rbpRegister (frameDisplacement slot) ++
    (aluBytes .w64 .add rcxRegister heapBaseRegister ++ storeByteBytes 0 rcxRegister 0)

/-- The x86 operand width of a heap word access. -/
def MemWidth.x86 : MemWidth → X86.Register.Width
  | .m32 => .w32
  | .m64 => .w64

/-- `add rax, r12; mov eax, [rax]` (`rax` for `m64`) -/
def loadWordSpec (width : MemWidth) : List UInt8 :=
  aluBytes .w64 .add 0 heapBaseRegister ++ memoryBytes width.x86 true 0 0 0

/-- `mov rcx, [slot]; add rcx, r12; mov [rcx], eax` (`rax` for `m64`) -/
def storeWordSpec (width : MemWidth) (slot : Nat) : List UInt8 :=
  memoryBytes .w64 true rcxRegister rbpRegister (frameDisplacement slot) ++
    (aluBytes .w64 .add rcxRegister heapBaseRegister ++ memoryBytes width.x86 false 0 rcxRegister 0)

/-- `syscall` -/
def syscallBytes : List UInt8 := [15, 5]

/-- The Linux number of a system call. -/
def Syscall.linux : Syscall → BitVec 32
  | .write => 1
  | .read => 0
  | .poll => 7

/-- What a system call does to its second argument in rsi: `add rsi, r12`
makes it a heap address for `write` and `read`; `mov rsi, rsi` keeps it for
`poll`. -/
def Syscall.rsiBytes : Syscall → List UInt8
  | .write => aluBytes .w64 .add rsiRegister heapBaseRegister
  | .read => aluBytes .w64 .add rsiRegister heapBaseRegister
  | .poll => moveBytes .w64 rsiRegister rsiRegister

/-- `mov rdi, [slot]; mov rsi, [slot + 1]; add rsi, r12; mov rdx, [slot + 2];
mov eax, number; syscall; mov r11, rcx`. The kernel leaves r11 unknown; the last
move makes it a function of the state again. -/
def sysSpec (kind : Syscall) (slot : Nat) : List UInt8 :=
  memoryBytes .w64 true rdiRegister rbpRegister (frameDisplacement slot) ++
    (memoryBytes .w64 true rsiRegister rbpRegister (frameDisplacement (slot + 1)) ++
    (kind.rsiBytes ++
    (memoryBytes .w64 true rdxRegister rbpRegister (frameDisplacement (slot + 2)) ++
    (immediateBytes .w32 0 kind.linux 0 ++ (syscallBytes ++ moveBytes .w64 r11Register rcxRegister)))))

/-- The bytes of the instruction at body offset `pc`, as the x86 encoders write them. -/
def Instr.bytes (i : Instr) (place : Place) (pc : Nat) : List UInt8 :=
  match i with
  | .imm value => immediateBytes .w64 0 (lowHalf value) (highHalf value)
  | .load slot => slotLoadBytes slot
  | .store slot => slotStoreBytes slot
  | .neg => negateBytes .w32 0
  | .op word operation slot => operation.spec word slot
  | .cmp word operation slot => cmpBytes word operation slot
  | .jmp target => jumpBytes (relative (pc + 5) target)
  | .jz target => testBytes .w64 0 0 ++ branchBytes 4 (relative (pc + 9) target)
  | .call callee args target count => copyBytes (argBase place.slots) args 0 ++
      callBytes (relative (place.body + pc + 14 * args.length + 5) (place.entries.getD callee 0)) ++
      copyBytes target (slotRange (argBase place.slots) count) 0
  | .ret sources => copyBytes 0 sources 0 ++ epilogueBytes
  | .bump shift => bumpSpec shift
  | .loadAt => loadAtSpec
  | .storeAt slot => storeAtSpec slot
  | .loadWordAt width => loadWordSpec width
  | .storeWordAt width slot => storeWordSpec width slot
  | .div word operation slot => operation.spec word slot
  | .fp operation slot => accToRcxBytes ++ slotLoadBytes slot ++ operation.opcodeBytes
  | .sys kind slot => sysSpec kind slot

/-! The extracted encoders are the x86 ones. (A float operation's SSE bytes
are the extracted ones themselves: `Simulation.lean` proves what each
decodes to.) -/

theorem uint8_ofNat_mod (n : Nat) : UInt8.ofNat (n % 256) = UInt8.ofNat n := by
  apply UInt8.toNat_inj.mp
  simp

theorem le32_toNat (value : BitVec 32) :
    le32 value = [UInt8.ofNat value.toNat, UInt8.ofNat (value.toNat / 256), UInt8.ofNat (value.toNat / 65536),
      UInt8.ofNat (value.toNat / 16777216)] := by
  simp only [le32, BitVec.toNat_ushiftRight, Nat.shiftRight_eq_div_pow]

theorem le32_eq (value : BitVec 32) : le32 value = displacementBytes value := by
  rw [le32_toNat]
  simp only [displacementBytes, Lanius.X86.wordBytes, uint8_ofNat_mod]

theorem le32_i32Bytes (value : BitVec 32) (x : Int) (same : value.toNat = Int.toNat (x % 2 ^ 32)) :
    le32 value = Lanius.Semantics.i32Bytes x := by
  rw [le32_toNat]
  simp only [Lanius.Semantics.i32Bytes, ← same]
  simp [List.range_succ, uint8_ofNat_mod]

theorem slotOffset_toNat (slot : Nat) :
    (slotOffset slot).toNat = Int.toNat (frameDisplacement slot % 2 ^ 32) := by
  have zero : BitVec.toNat (0 : BitVec 32) = 0 := rfl
  simp only [slotOffset, frameDisplacement, BitVec.toNat_sub, BitVec.toNat_ofNat, zero, Int.ofNat_eq_natCast]
  omega

theorem slotLoad_eq (slot : Nat) : slotLoad slot = slotLoadBytes slot := by
  rw [slotLoad, le32_i32Bytes _ _ (slotOffset_toNat slot)]
  rfl

theorem slotStore_eq (slot : Nat) : slotStore slot = slotStoreBytes slot := by
  rw [slotStore, le32_i32Bytes _ _ (slotOffset_toNat slot)]
  rfl

theorem uint8_ofNat_congr {a b : Nat} (same : a % 256 = b % 256) : UInt8.ofNat a = UInt8.ofNat b := by
  rw [← uint8_ofNat_mod a, same, uint8_ofNat_mod]

theorem le64_eq (value : BitVec 64) :
    le64 value = displacementBytes (lowHalf value) ++ displacementBytes (highHalf value) := by
  simp only [le64, lowHalf, highHalf, displacementBytes, Lanius.X86.wordBytes, BitVec.toNat_ushiftRight,
    BitVec.toNat_setWidth, Nat.shiftRight_eq_div_pow, List.cons_append, List.nil_append, List.cons.injEq,
    Nat.reducePow]
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, trivial⟩ <;> apply uint8_ofNat_congr <;> omega

theorem frameSize_eq (slots : Nat) : frameSize slots = frameBytes slots := rfl

theorem prologue_eq (slots : Nat) : prologue slots = framePrologueBytes slots ++ stackCheckBytes := by
  rw [prologue, le32_eq]
  rfl

theorem relative_ofInt (source target : Nat) : relative source target = BitVec.ofInt 32 ((target : Int) - source) := by
  rw [relative, Int.sub_eq_add_neg, BitVec.ofInt_add, BitVec.ofInt_neg, BitVec.ofInt_natCast, BitVec.ofInt_natCast,
    BitVec.sub_eq_add_neg]


theorem BinOp.bytes_eq (operation : BinOp) (word : Word) (slot : Nat) :
    operation.bytes word slot = operation.spec word slot := by
  cases word <;> cases operation <;> rw [BinOp.bytes, slotOperands, slotLoad_eq] <;> rfl

theorem DivOp.bytes_eq (operation : DivOp) (word : Word) (slot : Nat) :
    operation.bytes word slot = operation.spec word slot := by
  cases word <;> cases operation <;> rw [DivOp.bytes, slotOperands, slotLoad_eq] <;> rfl

theorem slotCompare_eq (word : Word) (operation : CmpOp) (slot : Nat) :
    slotCompare word operation slot = cmpBytes word operation slot := by
  cases word <;> cases operation <;> rw [slotCompare, slotOperands, slotLoad_eq] <;> rfl

theorem Instr.encode_eq (i : Instr) (place : Place) (pc : Nat) : i.encode place pc = i.bytes place pc := by
  cases i with
  | imm value => rw [Instr.encode, Instr.bytes, le64_eq]; rfl
  | load slot => exact slotLoad_eq slot
  | store slot => exact slotStore_eq slot
  | neg => rfl
  | op word operation slot => exact BinOp.bytes_eq operation word slot
  | cmp word operation slot => exact slotCompare_eq word operation slot
  | jmp target => rw [Instr.encode, Instr.bytes, le32_eq]; rfl
  | jz target => rw [Instr.encode, Instr.bytes, le32_eq]; rfl
  | call callee args target count => rw [Instr.encode, Instr.bytes, le32_eq]; rfl
  | ret sources => rfl
  | bump shift => simp only [Instr.encode, Instr.bytes, bumpBytes, le64_eq]; rfl
  | loadAt => rfl
  | storeAt slot => rw [Instr.encode, Instr.bytes, storeAtBytes, le32_i32Bytes _ _ (slotOffset_toNat slot)]; rfl
  | loadWordAt width => cases width <;> rfl
  | storeWordAt width slot =>
    cases width <;> rw [Instr.encode, Instr.bytes, storeWordBytes, le32_i32Bytes _ _ (slotOffset_toNat slot)] <;> rfl
  | div word operation slot => exact DivOp.bytes_eq operation word slot
  | fp operation slot => rw [Instr.encode, FOp.bytes, slotOperands, slotLoad_eq]; rfl
  | sys kind slot =>
    cases kind <;>
    · rw [Instr.encode, Instr.bytes, sysBytes, le32_i32Bytes _ _ (slotOffset_toNat slot),
        le32_i32Bytes _ _ (slotOffset_toNat (slot + 1)), le32_i32Bytes _ _ (slotOffset_toNat (slot + 2))]
      rfl

/-- A transfer by `relative source target` from `base + source` lands on `base + target`. -/
theorem relative_eq (base : BitVec 64) (source target : Nat) (sourceSmall : source < 2 ^ 31)
    (targetSmall : target < 2 ^ 31) :
    base + BitVec.ofNat 64 source + (relative source target).signExtend 64 = base + BitVec.ofNat 64 target := by
  have extended : (relative source target).signExtend 64 = BitVec.ofInt 64 ((target : Int) - source) := by
    apply BitVec.eq_of_toInt_eq
    rw [relative_ofInt, BitVec.toInt_signExtend, BitVec.toInt_ofInt, BitVec.toInt_ofInt]
    simp only [Nat.min_eq_right (by decide : 32 ≤ 64)]
    rw [Int.bmod_eq_emod, Int.bmod_eq_emod, Int.bmod_eq_emod]
    split <;> split <;> split <;> omega
  rw [extended, Int.sub_eq_add_neg, BitVec.ofInt_add, BitVec.ofInt_neg, BitVec.ofInt_natCast,
    BitVec.ofInt_natCast]
  bv_omega

theorem slotLoadBytes_length (slot : Nat) : (slotLoadBytes slot).length = 7 := by
  simp only [slotLoadBytes, memoryBytes, memoryHeader, Lanius.Semantics.i32Bytes, List.length_append,
    List.length_map, List.length_range]
  decide

theorem slotStoreBytes_length (slot : Nat) : (slotStoreBytes slot).length = 7 := by
  simp only [slotStoreBytes, memoryBytes, memoryHeader, Lanius.Semantics.i32Bytes, List.length_append,
    List.length_map, List.length_range]
  decide

theorem framePrologueBytes_length (slots : Nat) : (framePrologueBytes slots).length = 13 := by
  simp only [framePrologueBytes, immediateBytes, displacementBytes, List.length_append, List.length_cons,
    List.length_nil]
  decide

theorem stackCheckBytes_length : stackCheckBytes.length = 11 := by decide

theorem prologue_length (slots : Nat) : (prologue slots).length = 24 := by
  rw [prologue_eq, List.length_append, framePrologueBytes_length, stackCheckBytes_length]

theorem copyBytes_length (first : Nat) (args : List Nat) (k : Nat) :
    (copyBytes first args k).length = 14 * args.length := by
  induction args generalizing k with
  | nil => rfl
  | cons slot rest ih =>
    simp only [copyBytes, slotLoad_eq, slotStore_eq, List.length_append, slotLoadBytes_length,
      slotStoreBytes_length, ih, List.length_cons]
    omega

theorem slotRange_length (slot count : Nat) : (slotRange slot count).length = count := by
  induction count generalizing slot with
  | zero => simp [slotRange]
  | succ count ih => rw [slotRange]; simp [ih]

theorem slotRange_eq (slot count : Nat) : slotRange slot count = List.range' slot count := by
  induction count generalizing slot with
  | zero => simp [slotRange]
  | succ count ih => rw [slotRange]; simp [ih, List.range'_succ]

theorem Instr.bytes_length (place : Place) (pc : Nat) (i : Instr) : (i.bytes place pc).length = i.size := by
  cases i with
  | imm value => simp [Instr.bytes, immediateBytes, displacementBytes, Instr.size]; decide
  | load slot => exact slotLoadBytes_length slot
  | store slot => exact slotStoreBytes_length slot
  | neg => simp only [Instr.bytes, Instr.size]; decide
  | op word operation slot =>
    cases word <;> cases operation <;>
      simp only [Instr.bytes, BinOp.spec, BinOp.opBytes, BinOp.alu, Word.width, List.length_append,
        slotLoadBytes_length, Instr.size, BinOp.size, Word.prefix] <;> decide
  | cmp word operation slot =>
    cases word <;>
    simp only [Instr.bytes, cmpBytes, setConditionBytes, Word.compareBytes, List.length_append,
      slotLoadBytes_length, List.length_cons, List.length_nil, Instr.size, Word.prefix] <;>
    decide
  | jmp target => simp [Instr.bytes, jumpBytes, displacementBytes, Instr.size]
  | jz target =>
    simp only [Instr.bytes, branchBytes, displacementBytes, List.length_append, List.length_cons,
      List.length_nil, Instr.size]
    decide
  | call callee args target count =>
    simp only [Instr.bytes, callBytes, displacementBytes, List.length_append, copyBytes_length,
      slotRange_length, List.length_cons, List.length_nil, Instr.size]
  | ret sources =>
    have : epilogueBytes.length = 5 := by decide
    simp only [Instr.bytes, List.length_append, copyBytes_length, Instr.size, this]
  | bump shift => rw [← Instr.encode_eq]; simp [Instr.encode, bumpBytes, le64, Instr.size]
  | loadAt => rfl
  | storeAt slot => rw [← Instr.encode_eq]; simp [Instr.encode, storeAtBytes, le32, Instr.size]
  | loadWordAt width => cases width <;> rfl
  | storeWordAt width slot =>
    rw [← Instr.encode_eq]; cases width <;> simp [Instr.encode, storeWordBytes, MemWidth.rex, le32, Instr.size,
      MemWidth.prefix]
  | div word operation slot =>
    cases word <;> cases operation <;>
      simp only [Instr.bytes, DivOp.spec, List.length_append, slotLoadBytes_length, Instr.size, DivOp.size,
        Word.prefix] <;> decide
  | fp operation slot =>
    rcases operation with ⟨ty, operation⟩ | ⟨ty, operation⟩ | ⟨ty, word⟩ | _ | _ <;>
      (try cases ty) <;> (try cases operation) <;> (try cases word) <;>
      simp only [Instr.bytes, FOp.opcodeBytes, floatOperands, floatResult, FloatTy.rex, Word.rex,
        List.length_append, slotLoadBytes_length, Instr.size, FOp.size, FloatTy.rexSize, Word.prefix,
        List.length_cons, List.length_nil] <;> decide
  | sys kind slot =>
    cases kind <;>
    · simp only [Instr.bytes, sysSpec, Syscall.rsiBytes, memoryBytes, memoryHeader, Lanius.Semantics.i32Bytes,
        List.length_append, List.length_map, List.length_range, Instr.size]
      decide

theorem Instr.encode_length (place : Place) (pc : Nat) (i : Instr) : (i.encode place pc).length = i.size := by
  rw [Instr.encode_eq, Instr.bytes_length]

theorem encodeFrom_length (place : Place) (pc : Nat) (code : List Instr) :
    (encodeFrom place pc code).length = codeSize code := by
  induction code generalizing pc with
  | nil => rfl
  | cons i rest ih => simp only [encodeFrom, List.length_append, Instr.encode_length, ih, codeSize]

theorem encodeFrom_append (place : Place) (pc : Nat) (first second : List Instr) :
    encodeFrom place pc (first ++ second) =
      encodeFrom place pc first ++ encodeFrom place (pc + codeSize first) second := by
  induction first generalizing pc with
  | nil => simp [encodeFrom, codeSize]
  | cons i rest ih =>
    simp only [List.cons_append, encodeFrom, ih, List.append_assoc, codeSize, Nat.add_assoc]

/-- The instruction fetched at `pc` is laid out there. -/
theorem fetch_block {code : List Instr} {pc : Nat} {i : Instr} (fetched : fetch code pc = some i) :
    Block code pc [i] := by
  induction code generalizing pc with
  | nil => simp [fetch] at fetched
  | cons j rest ih =>
    simp only [fetch] at fetched
    split at fetched
    · rename_i zero
      cases fetched
      exact ⟨[], rest, by simp, by simp [codeSize, zero]⟩
    · split at fetched
      · contradiction
      · rename_i _ large
        obtain ⟨pre, post, split, size⟩ := ih fetched
        exact ⟨j :: pre, post, by simp [split], by simp only [codeSize, size]; omega⟩

theorem fetch_bytes {code : List Instr} {pc : Nat} {i : Instr} (place : Place)
    (fetched : fetch code pc = some i) :
    ∃ pre post, encodeFrom place 0 code = pre ++ i.encode place pc ++ post ∧ pre.length = pc ∧
      pc + i.size ≤ codeSize code := by
  obtain ⟨pre, post, rfl, size⟩ := fetch_block fetched
  refine ⟨encodeFrom place 0 pre, encodeFrom place (pc + i.size) post, ?_, ?_, ?_⟩
  · rw [encodeFrom_append, encodeFrom_append, codeSize_append, size]
    simp [encodeFrom, codeSize]
  · rw [encodeFrom_length, size]
  · simp only [codeSize_append, codeSize, size]; omega

theorem fetch_mem {code : List Instr} {pc : Nat} {i : Instr} (fetched : fetch code pc = some i) : i ∈ code := by
  obtain ⟨pre, post, rfl, -⟩ := fetch_block fetched
  simp

/-! The program image. -/

theorem Code.image_length (code : Code) (start : Nat) (entries : List Nat) :
    (code.image start entries).length = code.size := by
  simp only [Code.image, List.length_append, prologue_length, encodeFrom_length, Code.size]

theorem linkFrom_at (entries : List Nat) (codes : List Code) (start f : Nat) (code : Code)
    (found : codes[f]? = some code) :
    ∃ pre post offset, linkFrom entries start codes = pre ++ code.image offset entries ++ post ∧
      (layout start codes)[f]? = some offset ∧ start + pre.length = offset := by
  induction codes generalizing start f with
  | nil => simp at found
  | cons first rest ih =>
    cases f with
    | zero =>
      simp only [List.getElem?_cons_zero, Option.some.injEq] at found
      subst found
      exact ⟨[], linkFrom entries (start + first.size) rest, start, by simp [linkFrom], by simp [layout],
        by simp⟩
    | succ f =>
      simp only [List.getElem?_cons_succ] at found
      obtain ⟨pre, post, offset, split, at_, length⟩ := ih (start + first.size) f found
      refine ⟨first.image start entries ++ pre, post, offset, ?_, by simpa [layout] using at_, ?_⟩
      · simp [linkFrom, split]
      · simp only [List.length_append, Code.image_length]; omega

theorem layout_bound (entries : List Nat) (codes : List Code) (start f offset : Nat) (at_ : (layout start codes)[f]? = some offset) :
    offset ≤ start + (linkFrom entries start codes).length := by
  induction codes generalizing start f with
  | nil => simp [layout] at at_
  | cons first rest ih =>
    cases f with
    | zero =>
      simp only [layout, List.getElem?_cons_zero, Option.some.injEq] at at_
      omega
    | succ f =>
      simp only [layout, List.getElem?_cons_succ] at at_
      have := ih (start + first.size) f at_
      simp only [linkFrom, List.length_append, Code.image_length]
      omega

theorem layout_length (codes : List Code) (start : Nat) : (layout start codes).length = codes.length := by
  induction codes generalizing start with
  | nil => rfl
  | cons first rest ih => simp [layout, ih]

/-- Stack bytes one activation uses: its frame, saved rbp and return address. -/
def frameNeed : List Code → Nat
  | [] => 0
  | code :: rest => max (frameBytes code.slots + 16) (frameNeed rest)

/-- Stack bytes below the limit in r15 that a call may write before the
callee's stack check: its arguments and return address. -/
def Binary.guard (binary : Binary) : Nat := frameNeed binary.codes + 8

/-- Stack bytes below the return address, down to `binary.guard` below the
limit in r15, that a call nesting fewer than `depth` calls deep needs. -/
def Binary.stackNeed (binary : Binary) (depth : Nat) : Nat := (depth + 2) * frameNeed binary.codes

end Lanius.Mini
