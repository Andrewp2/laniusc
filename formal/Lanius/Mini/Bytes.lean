import Lanius.Mini.Compile
import Lanius.X86.Machine.FrameSlots
import Lanius.X86.Machine.ControlEncoding

/-! Assembly. Each abstract instruction is a fixed byte sequence from the
existing encoders, `Instr.size` bytes long. Jumps are relative to the end of
the instruction. A call copies its arguments to just below the return address
it pushes, which is where the callee's prologue puts its parameter slots.

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

def BinOp.bytes (operation : BinOp) (slot : Nat) : List UInt8 :=
  match operation with
  | .mul => frameMultiplyBytes slot
  | .add | .sub | .and | .or | .xor => frameAluBytes slot operation.alu

/-- The condition code that holds after `cmp left, right` exactly when the
comparison does. -/
def CmpOp.code : CmpOp → Fin 16
  | .eq => 4
  | .ne => 5
  | .lt => 12
  | .le => 14
  | .gt => 15
  | .ge => 13

/-- `mov ecx, eax; mov eax, [slot]; cmp eax, ecx; setcc al; movzx eax, al` -/
def cmpBytes (operation : CmpOp) (slot : Nat) : List UInt8 :=
  rightToRcxBytes ++ frameLoadBytes slot ++ compareBytes 0 rcxRegister ++
    setConditionBytes operation.code 0 ++ zeroExtendByteBytes 0 0

def epilogueBytes : List UInt8 :=
  moveBytes .w64 rspRegister rbpRegister ++ popBytes rbpRegister ++ returnBytes

/-- The rel32 field of a transfer from the end of an instruction at `source`
to `target`. -/
def relative (source target : Nat) : BitVec 32 := BitVec.ofInt 32 ((target : Int) - source)

/-- A transfer by `relative source target` from `base + source` lands on `base + target`. -/
theorem relative_eq (base : BitVec 64) (source target : Nat) (sourceSmall : source < 2 ^ 31)
    (targetSmall : target < 2 ^ 31) :
    base + BitVec.ofNat 64 source + (relative source target).signExtend 64 = base + BitVec.ofNat 64 target := by
  have extended : (relative source target).signExtend 64 = BitVec.ofInt 64 ((target : Int) - source) := by
    apply BitVec.eq_of_toInt_eq
    rw [relative, BitVec.toInt_signExtend, BitVec.toInt_ofInt, BitVec.toInt_ofInt]
    simp only [Nat.min_eq_right (by decide : 32 ≤ 64)]
    rw [Int.bmod_eq_emod, Int.bmod_eq_emod, Int.bmod_eq_emod]
    split <;> split <;> split <;> omega
  rw [extended, Int.sub_eq_add_neg, BitVec.ofInt_add, BitVec.ofInt_neg, BitVec.ofInt_natCast,
    BitVec.ofInt_natCast]
  bv_omega

/-- Where a function's code sits in the program image. -/
structure Place where
  /-- Image offset of the body's first instruction. -/
  body : Nat
  /-- The function's frame slots. -/
  slots : Nat
  /-- Image offset of every function's entry. -/
  entries : List Nat

/-- The caller's virtual slot that is the callee's parameter 0: the slot just
below the return address the call pushes. -/
def argBase (slots : Nat) : Nat := frameBytes slots / 8 + 2

/-- Copy argument slots `args` to virtual slots `first + k, first + k + 1, ...`. -/
def copyBytes (first : Nat) : List Nat → Nat → List UInt8
  | [], _ => []
  | slot :: rest, k => frameLoadBytes slot ++ frameStoreBytes (first + k) ++ copyBytes first rest (k + 1)

/-- The bytes of the instruction at body offset `pc`. -/
def Instr.encode (place : Place) (pc : Nat) : Instr → List UInt8
  | .imm value => immediateBytes .w32 0 value 0
  | .load slot => frameLoadBytes slot
  | .store slot => frameStoreBytes slot
  | .neg => negateBytes .w32 0
  | .op operation slot => operation.bytes slot
  | .cmp operation slot => cmpBytes operation slot
  | .jmp target => jumpBytes (relative (pc + 5) target)
  | .jz target => testBytes .w32 0 0 ++ branchBytes 4 (relative (pc + 8) target)
  | .call callee args => copyBytes (argBase place.slots) args 0 ++
      callBytes (relative (place.body + pc + 12 * args.length + 5) (place.entries.getD callee 0))
  | .ret => epilogueBytes

def encodeFrom (place : Place) : Nat → List Instr → List UInt8
  | _, [] => []
  | pc, i :: rest => i.encode place pc ++ encodeFrom place (pc + i.size) rest

theorem frameLoadBytes_length (slot : Nat) : (frameLoadBytes slot).length = 6 := by
  simp only [frameLoadBytes, memoryBytes, memoryHeader, Lanius.Semantics.i32Bytes, List.length_append,
    List.length_map, List.length_range]
  decide

theorem frameStoreBytes_length (slot : Nat) : (frameStoreBytes slot).length = 6 := by
  simp only [frameStoreBytes, memoryBytes, memoryHeader, Lanius.Semantics.i32Bytes, List.length_append,
    List.length_map, List.length_range]
  decide

theorem framePrologueBytes_length (slots : Nat) : (framePrologueBytes slots).length = 13 := by
  simp only [framePrologueBytes, immediateBytes, displacementBytes, List.length_append, List.length_cons,
    List.length_nil]
  decide

theorem copyBytes_length (first : Nat) (args : List Nat) (k : Nat) :
    (copyBytes first args k).length = 12 * args.length := by
  induction args generalizing k with
  | nil => rfl
  | cons slot rest ih =>
    simp only [copyBytes, List.length_append, frameLoadBytes_length, frameStoreBytes_length, ih,
      List.length_cons]
    omega

theorem Instr.encode_length (place : Place) (pc : Nat) (i : Instr) : (i.encode place pc).length = i.size := by
  cases i with
  | imm value =>
    simp only [Instr.encode, immediateBytes, displacementBytes, List.length_append, List.length_cons,
      List.length_nil, Instr.size]
    decide
  | load slot => exact frameLoadBytes_length slot
  | store slot => exact frameStoreBytes_length slot
  | neg => simp only [Instr.encode, Instr.size]; decide
  | op operation slot =>
    cases operation <;>
      simp only [Instr.encode, BinOp.bytes, BinOp.alu, frameAluBytes, frameMultiplyBytes, List.length_append,
        frameLoadBytes_length, Instr.size, BinOp.size] <;> decide
  | cmp operation slot =>
    simp only [Instr.encode, cmpBytes, setConditionBytes, List.length_append, frameLoadBytes_length,
      List.length_cons, List.length_nil, Instr.size]
    decide
  | jmp target => simp [Instr.encode, jumpBytes, displacementBytes, Instr.size]
  | jz target =>
    simp only [Instr.encode, branchBytes, displacementBytes, List.length_append, List.length_cons,
      List.length_nil, Instr.size]
    decide
  | call callee args =>
    simp only [Instr.encode, callBytes, displacementBytes, List.length_append, copyBytes_length,
      List.length_cons, List.length_nil, Instr.size]
  | ret => simp only [Instr.encode, Instr.size]; decide

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

/-- Image bytes of one function: the prologue, then the body. -/
def Code.size (code : Code) : Nat := 13 + codeSize code.instrs

def Code.image (code : Code) (start : Nat) (entries : List Nat) : List UInt8 :=
  framePrologueBytes code.slots ++ encodeFrom ⟨start + 13, code.slots, entries⟩ 0 code.instrs

/-- Entry offsets of functions laid out back to back from `start`. -/
def layout : Nat → List Code → List Nat
  | _, [] => []
  | start, code :: rest => start :: layout (start + code.size) rest

def linkFrom (entries : List Nat) : Nat → List Code → List UInt8
  | _, [] => []
  | start, code :: rest => code.image start entries ++ linkFrom entries (start + code.size) rest

theorem Code.image_length (code : Code) (start : Nat) (entries : List Nat) :
    (code.image start entries).length = code.size := by
  simp only [Code.image, List.length_append, framePrologueBytes_length, encodeFrom_length, Code.size]

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

/-- Machine code of a compiled program. -/
structure Binary where
  codes : List Code
  entries : List Nat
  image : List UInt8

/-- Images are small enough for every rel32 displacement. -/
def imageLimit : Nat := 2 ^ 30

def compileProgram (prog : Program) : Option Binary :=
  match compileFuncs (arities prog.funcs) prog.funcs with
  | none => none
  | some codes =>
    let entries := layout 0 codes
    let image := linkFrom entries 0 codes
    if image.length ≤ imageLimit then some { codes, entries, image } else none

/-- Stack bytes one activation uses: its frame, saved rbp and return address. -/
def frameNeed : List Code → Nat
  | [] => 0
  | code :: rest => max (frameBytes code.slots + 16) (frameNeed rest)

/-- Stack bytes below the return address that a call nesting fewer than
`depth` calls deep needs. -/
def Binary.stackNeed (binary : Binary) (depth : Nat) : Nat := (depth + 1) * frameNeed binary.codes

end Lanius.Mini
