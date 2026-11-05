module

public import Lanius.Mini.TextCorrect
public import Lanius.Mini.DetSteps
public import Lanius.X86.Machine.RuntimeEncoding
import all Lanius.Mini.Compiler.P.BinOp_size
import all Lanius.Mini.Compiler.P.Lists_concat
import all Lanius.Mini.Compiler.P.Lists_cons
import all Lanius.Mini.Compiler.P.Lists_empty
import all Lanius.Mini.Compiler.P.Lists_get
import all Lanius.Mini.Compiler.P.Lists_getOr
import all Lanius.Mini.Compiler.P.Lists_length
import all Lanius.Mini.Compiler.P.Lists_single
import all Lanius.Mini.Compiler.P.MemWidth_bytes
import all Lanius.Mini.Compiler.P.MemWidth_prefix
import all Lanius.Mini.Compiler.P.MemWidth_rex
import all Lanius.Mini.Compiler.P.Word_prefix
import all Lanius.Mini.Compiler.P.SrcExpr_guard
import all Lanius.Mini.Compiler.P.boundsGuard
import all Lanius.Mini.Compiler.P.checkThen
import all Lanius.Mini.Compiler.P.expectType
import all Lanius.Mini.Compiler.P.guardAll
import all Lanius.Mini.Compiler.P.guarded
import all Lanius.Mini.Compiler.P.lowerAppend
import all Lanius.Mini.Compiler.P.lowerAs
import all Lanius.Mini.Compiler.P.slotVars
import all Lanius.Mini.Compiler.P.thenCheck
import all Lanius.Mini.Compiler.P.trap
import all Lanius.Mini.Compiler.P.SrcType_same
import all Lanius.Mini.Compiler.P.SrcType_size
import all Lanius.Mini.Compiler.P.fieldOffset
import all Lanius.Mini.Compiler.P.norm
import all Lanius.Mini.Compiler.P.wrap
import all Lanius.Mini.Compiler.P.Expr_narrow
import all Lanius.Mini.Compiler.P.FArith_number
import all Lanius.Mini.Compiler.P.FCmp_number
import all Lanius.Mini.Compiler.P.FOp_number
import all Lanius.Mini.Compiler.P.Word_keeps
import all Lanius.Mini.Compiler.P.Word_narrows
import all Lanius.Mini.Compiler.P.Word_number
import all Lanius.Mini.Compiler.P.absorbed
import all Lanius.Mini.Compiler.P.foldConstant
import all Lanius.Mini.Compiler.P.negateConstant
import all Lanius.Mini.Compiler.P.BinOp_bytes
import all Lanius.Mini.Compiler.P.BinOp_opcode
import all Lanius.Mini.Compiler.P.CmpOp_setcc
import all Lanius.Mini.Compiler.P.CmpOp_setccSigned
import all Lanius.Mini.Compiler.P.CmpOp_setccUnsigned
import all Lanius.Mini.Compiler.P.DivOp_bytes
import all Lanius.Mini.Compiler.P.DivOp_extend
import all Lanius.Mini.Compiler.P.DivOp_opcode
import all Lanius.Mini.Compiler.P.DivOp_result
import all Lanius.Mini.Compiler.P.Word_rex
import all Lanius.Mini.Compiler.P.arities
import all Lanius.Mini.Compiler.P.compileFuncs
import all Lanius.Mini.Compiler.P.fspLoad
import all Lanius.Mini.Compiler.P.fspSave
import all Lanius.Mini.Compiler.P.le32
import all Lanius.Mini.Compiler.P.le64
import all Lanius.Mini.Compiler.P.slotCompare
import all Lanius.Mini.Compiler.P.slotLoad
import all Lanius.Mini.Compiler.P.slotOffset
import all Lanius.Mini.Compiler.P.slotOperands
import all Lanius.Mini.Compiler.P.slotStore
import all Lanius.Mini.Compiler.P.SrcEff_isSlice
import all Lanius.Mini.Compiler.P.SrcEff_passesSlices
import all Lanius.Mini.Compiler.P.SrcEff_sliceCall
import all Lanius.Mini.Compiler.P.SrcStmt_breaksOut
import all Lanius.Mini.Compiler.P.SrcStmt_depth
import all Lanius.Mini.Compiler.P.SrcStmt_lower
import all Lanius.Mini.Compiler.P.arrayCall
import all Lanius.Mini.Compiler.P.arrayCallSig
import all Lanius.Mini.Compiler.P.effsSlice
import all Lanius.Mini.Compiler.P.paramScope
import all Lanius.Mini.Compiler.P.paramTypes
import all Lanius.Mini.Compiler.P.paramsSize
import all Lanius.Mini.Compiler.P.paramsValid
import all Lanius.Mini.Compiler.P.stmtEval
import all Lanius.Mini.Compiler.P.Expr_temps
import all Lanius.Mini.Compiler.P.Expr_within
import all Lanius.Mini.Compiler.P.Stmt_temps
import all Lanius.Mini.Compiler.P.Stmt_within
import all Lanius.Mini.Compiler.P.allWithin
import all Lanius.Mini.Compiler.P.argSlots
import all Lanius.Mini.Compiler.P.argsRoom
import all Lanius.Mini.Compiler.P.argsTemps
import all Lanius.Mini.Compiler.P.arityIs
import all Lanius.Mini.Compiler.P.compileArgs
import all Lanius.Mini.Compiler.P.compileStmt
import all Lanius.Mini.Compiler.P.exprRoom
import all Lanius.Mini.Compiler.P.frameLimit
import all Lanius.Mini.Compiler.P.imageLimit
import all Lanius.Mini.Compiler.P.spend
import all Lanius.Mini.Compiler.P.stmtRoom
import all Lanius.Mini.Compiler.P.zeroLocals
import all Lanius.Mini.Compiler.P.compileSource
import all Lanius.Mini.Compiler.P.packWord
import all Lanius.Mini.Compiler.P.roundCons
import all Lanius.Mini.Compiler.P.roundEnd
import all Lanius.Mini.Compiler.P.usizeWords
import all Lanius.Mini.Compiler.P.Inline_argsThen
import all Lanius.Mini.Compiler.P.Inline_exprThen
import all Lanius.Mini.Compiler.P.Inline_iteCode
import all Lanius.Mini.Compiler.P.Inline_link
import all Lanius.Mini.Compiler.P.Inline_linkFitting
import all Lanius.Mini.Compiler.P.Inline_lookupAt
import all Lanius.Mini.Compiler.P.Inline_loopCode
import all Lanius.Mini.Compiler.P.Inline_offsetAfter
import all Lanius.Mini.Compiler.P.Inline_roomNext
import all Lanius.Mini.Compiler.P.Inline_seqCode
import all Lanius.Mini.Compiler.P.Inline_spendThen
import all Lanius.Mini.Compiler.P.Inline_stmtThen
import all Lanius.Mini.Compiler.P.elfFile
import all Lanius.Mini.Compiler.P.elfFits
import all Lanius.Mini.Compiler.P.elfHeader
import all Lanius.Mini.Compiler.P.elfProgramHeader
import all Lanius.Mini.Compiler.P.elfStackBase
import all Lanius.Mini.Compiler.P.elfStartup
import all Lanius.Mini.Compiler.P.frameNeedOf
import all Lanius.Mini.Compiler.P.larger
import all Lanius.Mini.Compiler.P.le16
import all Lanius.Mini.Compiler.P.le64n
import all Lanius.Mini.Compiler.P.pageUp
import all Lanius.Mini.Compiler.P.stackGuard
import all Lanius.Mini.Compiler.P.compileProgram
import all Lanius.Mini.Compiler.P.linkedSize
import all Lanius.Mini.Compiler.P.roomAfter
import all Lanius.Mini.Compiler.P.Code_image
import all Lanius.Mini.Compiler.P.Code_size
import all Lanius.Mini.Compiler.P.Instr_encode
import all Lanius.Mini.Compiler.P.argBase
import all Lanius.Mini.Compiler.P.copyBytes
import all Lanius.Mini.Compiler.P.encodeFrom
import all Lanius.Mini.Compiler.P.encodeOnto
import all Lanius.Mini.Compiler.P.epilogue
import all Lanius.Mini.Compiler.P.frameSize
import all Lanius.Mini.Compiler.P.layout
import all Lanius.Mini.Compiler.P.linkFrom
import all Lanius.Mini.Compiler.P.linkOnto
import all Lanius.Mini.Compiler.P.loadAtBytes
import all Lanius.Mini.Compiler.P.loadWordBytes
import all Lanius.Mini.Compiler.P.prologue
import all Lanius.Mini.Compiler.P.relative
import all Lanius.Mini.Compiler.P.slotRange
import all Lanius.Mini.Compiler.P.stackCheck
import all Lanius.Mini.Compiler.P.storeAtBytes
import all Lanius.Mini.Compiler.P.storeWordBytes
import all Lanius.Mini.Compiler.P.sysBytes
import all Lanius.Mini.Compiler.P.syscallLinuxByte
import all Lanius.Mini.Compiler.P.syscallLinuxHigh
import all Lanius.Mini.Compiler.P.syscallRsiBytes
import all Lanius.Mini.Compiler.P.SrcStmt_declare
import all Lanius.Mini.Compiler.P.SrcStmt_returns
import all Lanius.Mini.Compiler.P.SrcType_declare
import all Lanius.Mini.Compiler.P.declareEnum
import all Lanius.Mini.Compiler.P.declareFunc
import all Lanius.Mini.Compiler.P.declareParams
import all Lanius.Mini.Compiler.P.declareStruct
import all Lanius.Mini.Compiler.P.keepIf
import all Lanius.Mini.Compiler.P.lowerBody
import all Lanius.Mini.Compiler.P.lowerFunc
import all Lanius.Mini.Compiler.P.lowerFuncCons
import all Lanius.Mini.Compiler.P.lowerFuncs
import all Lanius.Mini.Compiler.P.unitTail
import all Lanius.Mini.Compiler.P.withFrame
import all Lanius.Mini.Compiler.P.binaryWords
import all Lanius.Mini.Compiler.P.compileWords
import all Lanius.Mini.Compiler.P.elfBase
import all Lanius.Mini.Compiler.P.elfBeforeImage
import all Lanius.Mini.Compiler.P.imageWords
import all Lanius.Mini.Compiler.P.packRound
import all Lanius.Mini.Compiler.P.packRounds
import all Lanius.Mini.Compiler.P.roundJoin
import all Lanius.Faithful.Pure
import all Lanius.Mini.Compiler.Types
import all Lanius.Mini.HeapCorr
import all Lanius.Mini.Semantics

@[expose] public section

/-! # The process (roadmap step V6)

`elfFile` (`formal/lani/mini/compiler.lani`) wraps a binary in an ELF
executable: one loadable segment at 2^32 holding the headers, a startup code
and the image, then a zero-filled stack and heap. The startup code sets the
stack and heap registers the compiled code expects, calls function `entry`
and exits with its rax.

What Linux does is the trusted part, stated here: `Loaded` (what `execve`
leaves in memory and rip for a file with one loadable segment, read from the
file's own header fields) and `Exits` (a `syscall` with rax 60 ends the
process with status rdi). The theorems: from any state `Loaded` gives, a run
of the file reaches `Exits` with the entry's Core result
(`process_exits`), and every run that stops other than at a fault stops at
`Exits` with that result, or Core's call reaches an undefined trap
(`process_behaviour`); and the same from source text (`textProcess_exits`,
`textProcess_behaviour`). -/

namespace Lanius.Mini

variable {sx : Statics}

open Lanius.X86.Machine
open Lanius.Core (Value)

/-! ## What Linux does (trusted) -/

/-- The little-endian number in the `count` bytes of `file` from `offset`. -/
def fieldAt (file : List UInt8) (offset count : Nat) : Nat :=
  ((file.drop offset).take count).foldr (fun b n => b.toNat + 256 * n) 0

/-- What Linux's `execve` leaves for an x86-64 ELF executable whose one
program header is a loadable segment from file offset 0: the segment's
`p_filesz` bytes (at 96) from the file at `p_vaddr` (at 80), zeros after them
up to `p_memsz` (at 104), and rip at `e_entry` (at 24). The registers, the
flags and the rest of memory are unknown. -/
structure Loaded (file : List UInt8) (s : State) : Prop where
  bytes : ∀ i, i < fieldAt file 96 8 → s.memory (BitVec.ofNat 64 (fieldAt file 80 8 + i)) = file.getD i 0
  zeros : ∀ i, fieldAt file 96 8 ≤ i → i < fieldAt file 104 8 → s.memory (BitVec.ofNat 64 (fieldAt file 80 8 + i)) = 0
  rip : s.rip = BitVec.ofNat 64 (fieldAt file 24 8)
  /-- A new process has written nothing yet; its standard input, clock
  readings and secure bytes are the streams of `s.io` (TRUSTED_BASE.md
  section 8). -/
  io : s.io.trace = []

/-- Linux's `exit`: a `syscall` with rax 60 ends the process with status
rdi, of which a parent sees the low byte. -/
structure Exits (s : State) (code : BitVec 64) : Prop where
  syscall : CodeAt s.memory s.rip [15, 5]
  number : s.registers 0 = 60
  status : s.registers 7 = code

/-! ## The exit stops the machine model -/

/-- At `Exits` the model takes no step and is not at a fault: `syscall` is
not an instruction of the model. -/
theorem Exits.stuck {s : State} {code : BitVec 64} (h : Exits s code) :
    (∀ v, ¬Lanius.X86.Machine.Step s v) ∧ ¬Lanius.X86.Machine.Fault s := by
  have none := decode_syscall_prefix s.memory s.rip h.syscall
  refine ⟨fun v step => ?_, fun fault => ?_⟩
  · rcases step.results with ⟨i, k, ⟨bytes, loaded, decoded⟩, -⟩ | ⟨-, kernel⟩
    · rw [none bytes loaded] at decoded
      cases decoded
    · cases kernel with
      | write number => rw [h.number] at number; exact absurd number (by decide)
      | read number => rw [h.number] at number; exact absurd number (by decide)
      | poll number => rw [h.number] at number; exact absurd number (by decide)
      | clock number => rw [h.number] at number; exact absurd number (by decide)
      | getrandom number => rw [h.number] at number; exact absurd number (by decide)
      | readFile number => rw [h.number] at number; exact absurd number (by decide)
      | writeFile number => rw [h.number] at number; exact absurd number (by decide)
      | openFile number => rw [h.number] at number; exact absurd number (by decide)
      | close number => rw [h.number] at number; exact absurd number (by decide)
  · cases fault with
    | ud2 loaded =>
      have := loaded 1 (by simp)
      have := h.syscall 1 (by simp)
      simp_all
    | divideByZero bytes loaded _ _ _ decoded _ => rw [none bytes loaded] at decoded; cases decoded
    | divideOverflow bytes loaded _ _ _ decoded _ => rw [none bytes loaded] at decoded; cases decoded

/-! ## The compiled function's contract, for any stack -/

/-- `compileSource_correct` for any stack window: the compiled `f` returns
`results` within the window, or, when the window is below what the run
needs, every stopped run of it is at a fault. -/
theorem compileSource_contract {sp : SrcProgram} {binary : Binary}
    (compiled : compileSource sp = some binary) {f : Nat} {func : SrcFunc}
    (found : sp.funcs[f]? = some func) {args : List Value} {bits : List (BitVec 64)}
    (typed : FieldsHold sx [] (paramTypes func.params) args (Func.entry bits) 0)
    (bitsLen : bits.length = paramsSize func.params) {fuel : Nat} {v : Value}
    {final : Semantics.State} {heap : Heap} (start : heap.cursor = 1)
    (zero : ∀ a, 1 ≤ a → heap.bytes a = 0) (small : heap.limit < 2 ^ 62) (silent : heap.io.trace = [])
    (runs : Semantics.evalExpr fuel sp.toCore (startState heap.io) (.call f (args.map Core.Expr.value)) =
      .done v final)
    (fits : final.heap.nextAddress ≤ heap.limit) (frameRoom : 0 < sp.need f → heap.limit + sp.need f ≤ heap.fsp ∧ heap.fsp ≤ heap.top ∧ heap.top < 2 ^ 62)
    (statics : heap.StaticsAt sx) (ofSp : sx.bytes = sp.decls.statics) :
    ∃ depth results, ∃ after : Heap, func.ret.HoldsAt sx [] v (Func.entry results) 0 ∧ results.length = func.ret.size ∧
      final.world.standardOutput = outputOf 1 after.io.trace ∧ final.world.standardError = outputOf 2 after.io.trace ∧
      ∀ imageBase window, Contract binary imageBase (binary.stackNeed depth) window f bits heap results after := by
  obtain ⟨_, _, funcs, lowered, compiledProgram⟩ := compileSource_some compiled
  haveI : StaticsOf sp sx := ⟨ofSp⟩
  cases fuel with
  | zero => simp [Semantics.evalExpr] at runs
  | succ k =>
    obtain ⟨func', values, afterArgs, completed, c, argsRun, found', _, bodyRun, result, rfl⟩ :=
      call_inv (List.getElem?_eq_some_iff.mp found).1 runs
    rw [found] at found'
    cases found'
    obtain ⟨rfl, rfl⟩ := evalExprs_values argsRun
    obtain ⟨_, _, depth, results, after, _, returns, holds, len, hc, -⟩ :=
      body_sound (mp := { funcs := funcs, statics := sp.decls.statics }) (hp := heap) lowered (stmt_sound lowered k) found
        (startState_fresh _) (HeapCorr.empty start zero small silent)
        (LentHomes.start _ frameRoom statics) (Nat.le_refl _) (fun _ mem => by simp at mem) typed bitsLen bodyRun result fits
    refine ⟨depth, results, after, holds, len, hc.out, hc.err, fun imageBase window => ?_⟩
    rcases compileOptimized_some compiledProgram with original | ⟨q, accepted, optimized⟩
    · exact compiled_contract original imageBase depth f bits heap results after returns window
    · exact compiled_contract optimized imageBase depth f bits heap results after (returns.validated accepted) window

/-! ## The file's layout -/

theorem le64n_val (v : Nat) : (le64n v).foldr (fun b n => b.toNat + 256 * n) 0 = v % 2 ^ 64 := by
  simp [le64n, le64, BitVec.toNat_ushiftRight, Nat.shiftRight_eq_div_pow]
  omega

theorem fieldAt_le64n (pre post : List UInt8) (v : Nat) :
    fieldAt (pre ++ (le64n v ++ post)) pre.length 8 = v % 2 ^ 64 := by
  unfold fieldAt
  rw [List.drop_left, show 8 = (le64n v).length from rfl, List.take_left, le64n_val]

@[simp] theorem le16_length (v : Nat) : (le16 v).length = 2 := by rfl
@[simp] theorem le32_length (v : BitVec 32) : (le32 v).length = 4 := by rfl
@[simp] theorem le64n_length (v : Nat) : (le64n v).length = 8 := by rfl
@[simp] theorem elfStartup_length (binary : Binary) (entry stack heap : Nat) :
    (elfStartup binary entry stack heap).length = 95 := by rfl

theorem fieldAt_cons (a : UInt8) (l : List UInt8) (n k : Nat) : fieldAt (a :: l) (n + 1) k = fieldAt l n k := by
  simp [fieldAt]

theorem fieldAt_le64n_skip (v : Nat) (l : List UInt8) (n k : Nat) : fieldAt (le64n v ++ l) (n + 8) k = fieldAt l n k := by
  simp [fieldAt, le64n, le64]

theorem fieldAt_le32_skip (v : BitVec 32) (l : List UInt8) (n k : Nat) : fieldAt (le32 v ++ l) (n + 4) k = fieldAt l n k := by
  simp [fieldAt, le32]

theorem fieldAt_le16_skip (v : Nat) (l : List UInt8) (n k : Nat) : fieldAt (le16 v ++ l) (n + 2) k = fieldAt l n k := by
  simp [fieldAt, le16]

theorem fieldAt_le64n_here (v : Nat) (l : List UInt8) : fieldAt (le64n v ++ l) 0 8 = v % 2 ^ 64 := by
  have := fieldAt_le64n [] l v
  simpa using this

theorem elfFile_some {binary : Binary} {entry stack heap : Nat} {file : List UInt8}
    (h : elfFile binary entry stack heap = some file) :
    elfFits binary entry stack heap = true ∧
      file = elfHeader binary ++ elfProgramHeader binary stack heap ++ elfStartup binary entry stack heap ++
        binary.image := by
  unfold elfFile at h
  split at h
  · exact ⟨by assumption, (Option.some.inj h).symm⟩
  · cases h

theorem elfFits_spec {binary : Binary} {entry stack heap : Nat} (h : elfFits binary entry stack heap = true) :
    binary.image.length < 2 ^ 30 ∧ binary.entries.getD entry 0 < 2 ^ 30 ∧ stackGuard binary ≤ stack ∧
      stack < 2 ^ 40 ∧ 1 ≤ heap ∧ heap < 2 ^ 40 := by
  simp only [elfFits, Bool.and_eq_true, decide_eq_true_eq] at h
  exact ⟨h.1.1.1.1.1, h.1.1.1.1.2, h.1.1.1.2, h.1.1.2, h.1.2, h.2⟩

/-- The bytes before the image: the headers and the startup code. -/
theorem elf_lengths (binary : Binary) (entry stack heap : Nat) :
    (elfHeader binary).length = 64 ∧ (elfProgramHeader binary stack heap).length = 56 ∧
      (elfStartup binary entry stack heap).length = 95 := by
  refine ⟨rfl, rfl, rfl⟩

/-- The header fields `Loaded` reads. -/
theorem elf_fields {binary : Binary} {entry stack heap : Nat} {file : List UInt8}
    (h : elfFile binary entry stack heap = some file) :
    fieldAt file 24 8 = elfBase + 120 ∧ fieldAt file 80 8 = elfBase ∧ fieldAt file 96 8 = file.length ∧
      fieldAt file 104 8 = elfStackBase binary - elfBase + stack + heap + stack := by
  obtain ⟨fits, rfl⟩ := elfFile_some h
  obtain ⟨imageLt, -, -, stackLt, -, heapLt⟩ := elfFits_spec fits
  have below : elfBase + (215 + binary.image.length) ≤ elfStackBase binary := by
    simp only [elfStackBase, pageUp, elfBeforeImage]; omega
  have upper : elfStackBase binary ≤ elfBase + (215 + binary.image.length) + 4095 := by
    simp only [elfStackBase, pageUp, elfBeforeImage]; omega
  simp only [elfHeader, elfProgramHeader, List.append_assoc, List.cons_append, List.nil_append, List.length_append,
    List.length_cons, fieldAt_cons, fieldAt_le64n_skip, fieldAt_le32_skip, fieldAt_le16_skip,
    fieldAt_le64n_here, elf_lengths, le16_length, le32_length, le64n_length]
  simp only [elfBase, elfBeforeImage] at below upper ⊢
  refine ⟨trivial, trivial, ?_, ?_⟩ <;> omega

/-! ## Addresses -/

theorem ofNat_add64 (a b : Nat) : BitVec.ofNat 64 a + BitVec.ofNat 64 b = BitVec.ofNat 64 (a + b) :=
  (BitVec.ofNat_add a b).symm

theorem ofNat_ne64 {a b : Nat} (ha : a < 2 ^ 64) (hb : b < 2 ^ 64) (h : a ≠ b) :
    BitVec.ofNat 64 a ≠ BitVec.ofNat 64 b := by
  intro e
  have := congrArg BitVec.toNat e
  simp only [BitVec.toNat_ofNat, Nat.mod_eq_of_lt ha, Nat.mod_eq_of_lt hb] at this
  exact h this

theorem ofNat_sub64 {a b : Nat} (le : b ≤ a) (ha : a < 2 ^ 64) :
    BitVec.ofNat 64 a - BitVec.ofNat 64 b = BitVec.ofNat 64 (a - b) := by
  apply BitVec.eq_of_toNat_eq
  simp only [BitVec.toNat_sub, BitVec.toNat_ofNat]
  omega

theorem ofNat_sub8 {a : Nat} (le : 8 ≤ a) (ha : a < 2 ^ 64) : BitVec.ofNat 64 a - 8 = BitVec.ofNat 64 (a - 8) := by
  apply BitVec.eq_of_toNat_eq
  simp only [BitVec.toNat_sub, BitVec.toNat_ofNat]
  have : (8 : BitVec 64).toNat = 8 := rfl
  omega

theorem signExtend_ofNat32 {n : Nat} (h : n < 2 ^ 31) :
    (BitVec.ofNat 32 n).signExtend 64 = BitVec.ofNat 64 n := by
  apply BitVec.eq_of_toNat_eq
  have hs : (BitVec.ofNat 32 n).msb = false := by
    rw [BitVec.msb_eq_getMsbD_zero, BitVec.getMsbD_eq_getLsbD]
    simp only [show 0 < 32 by decide, decide_true, Bool.true_and, show 32 - 1 = 31 by decide]
    have hn : (BitVec.ofNat 32 n).toNat < 2 ^ 31 := by
      simpa [BitVec.toNat_ofNat, Nat.mod_eq_of_lt (show n < 2 ^ 32 by omega)] using h
    exact Nat.testBit_lt_two_pow hn
  simp [BitVec.toNat_signExtend, hs, Nat.mod_eq_of_lt (show n < 2 ^ 32 by omega),
    Nat.mod_eq_of_lt (show n < 2 ^ 64 by omega)]

theorem frameNeedOf_eq : ∀ codes : List Code, frameNeedOf codes = frameNeed codes
  | [] => rfl
  | c :: rest => by
    simp only [frameNeedOf, frameNeed, larger, frameNeedOf_eq rest, frameSize_eq]
    split <;> omega

theorem stackGuard_eq (binary : Binary) : stackGuard binary = binary.guard := by
  simp [stackGuard, Binary.guard, frameNeedOf_eq]

/-! ## The startup code -/

/-- The stack's top, which is also the heap's base. -/
def elfTop (binary : Binary) (stack : Nat) : Nat := elfStackBase binary + stack

/-- The sizes `elfFits` checks, as the proofs use them. -/
structure ElfSizes (binary : Binary) (entry stack heap : Nat) : Prop where
  image : binary.image.length < 2 ^ 30
  entry : binary.entries.getD entry 0 < 2 ^ 30
  guard : binary.guard ≤ stack
  stack : stack < 2 ^ 40
  room : 1 ≤ heap
  heap : heap < 2 ^ 40
  low : elfBase + (215 + binary.image.length) ≤ elfStackBase binary
  high : elfStackBase binary ≤ elfBase + (215 + binary.image.length) + 4095
  eight : 8 ≤ binary.guard

theorem elfSizes {binary : Binary} {entry stack heap : Nat} {file : List UInt8}
    (h : elfFile binary entry stack heap = some file) : ElfSizes binary entry stack heap := by
  obtain ⟨fits, -⟩ := elfFile_some h
  obtain ⟨imageLt, entryLt, guardLe, stackLt, heapGe, heapLt⟩ := elfFits_spec fits
  rw [stackGuard_eq] at guardLe
  exact ⟨imageLt, entryLt, guardLe, stackLt, heapGe, heapLt,
    by simp only [elfStackBase, pageUp, elfBeforeImage]; omega,
    by simp only [elfStackBase, pageUp, elfBeforeImage]; omega,
    by simp [Binary.guard]⟩

/-- The state the startup code's call enters the compiled `entry` in: the
stack and heap registers set, the return address pushed, the file's bytes in
place and the heap zero. -/
structure AtEntry (binary : Binary) (entry stack heap : Nat) (file : List UInt8) (given : Io) (t : State) :
    Prop where
  rsp : t.registers rspRegister = BitVec.ofNat 64 (elfTop binary stack - 8)
  limit : t.registers stackRegister = BitVec.ofNat 64 (elfStackBase binary + binary.guard)
  base : t.registers heapBaseRegister = BitVec.ofNat 64 (elfTop binary stack)
  heapLimit : t.registers limitRegister = BitVec.ofNat 64 heap
  cursor : t.registers cursorRegister = BitVec.ofNat 64 1
  /-- r10: the heap's top, the end of the `stack` bytes of frame memory above the limit. -/
  top : t.registers topRegister = BitVec.ofNat 64 (heap + stack)
  /-- rbx: the frame pointer, at the heap's top. -/
  fsp : t.registers fspRegister = BitVec.ofNat 64 (heap + stack)
  /-- r8: the static bytes, after the code in the image. -/
  static : t.registers staticRegister = BitVec.ofNat 64 (elfBase + 215 + linkedSize binary.codes)
  rip : t.rip = BitVec.ofNat 64 (elfBase + 215 + binary.entries.getD entry 0)
  code : ∀ i, i < file.length → t.memory (BitVec.ofNat 64 (elfBase + i)) = file.getD i 0
  zero : ∀ a, a < heap + stack → t.memory (BitVec.ofNat 64 (elfTop binary stack + a)) = 0
  ret : read64 t.memory (BitVec.ofNat 64 (elfTop binary stack - 8)) = BitVec.ofNat 64 (elfBase + 205)
  io : t.io = given

theorem AtEntry.congr {binary : Binary} {entry stack heap : Nat} {file : List UInt8} {given : Io} {t u : State}
    (h : AtEntry binary entry stack heap file given t) (same : DataEq t u) : AtEntry binary entry stack heap file given u := by
  obtain ⟨r, i, m, -, o⟩ := same
  exact ⟨r ▸ h.rsp, r ▸ h.limit, r ▸ h.base, r ▸ h.heapLimit, r ▸ h.cursor, r ▸ h.top, r ▸ h.fsp, r ▸ h.static,
    i ▸ h.rip, m ▸ h.code, m ▸ h.zero,
    m ▸ h.ret, o ▸ h.io⟩

theorem imm_bytes (r : Register) (v : Nat) (rex op : UInt8)
    (prefix_ : immediateBytes .w64 r (lowHalf (BitVec.ofNat 64 v)) (highHalf (BitVec.ofNat 64 v)) =
      rex :: op :: (displacementBytes (lowHalf (BitVec.ofNat 64 v)) ++ displacementBytes (highHalf (BitVec.ofNat 64 v)))) :
    immediateBytes .w64 r (lowHalf (BitVec.ofNat 64 v)) (highHalf (BitVec.ofNat 64 v)) = rex :: op :: le64n v := by
  rw [prefix_, le64n, le64_eq]

/-- `mov r, imm64` as the startup code spells it. -/
theorem movImm {s : State} {r : Register} {v : Nat} {rex op : UInt8} {rest : List UInt8}
    (enc : immediateBytes .w64 r (lowHalf (BitVec.ofNat 64 v)) (highHalf (BitVec.ofNat 64 v)) = rex :: op :: le64n v)
    (loaded : CodeAt s.memory s.rip ((rex :: op :: le64n v) ++ rest)) :
    Lanius.X86.Machine.Step s (s.immediate64 r (BitVec.ofNat 64 v) 10) ∧ NoRead s ∧
      CodeAt (s.immediate64 r (BitVec.ofNat 64 v) 10).memory (s.immediate64 r (BitVec.ofNat 64 v) 10).rip rest := by
  have here : CodeAt s.memory s.rip (immediateBytes .w64 r (lowHalf (BitVec.ofNat 64 v)) (highHalf (BitVec.ofNat 64 v))) := by
    rw [enc]; exact loaded.prefix
  refine ⟨immediate_step s _ .w64 r _ _ here ?_, immediate_noRead here, loaded.next rfl rfl⟩
  simp only [execute, immediateInstruction, lowHalf_highHalf, enc, List.length_cons, le64n_length]

/-- The startup code's nine steps, from what Linux loads to the entry. -/
theorem startup {binary : Binary} {entry stack heap : Nat} {file : List UInt8} {s : State}
    (h : elfFile binary entry stack heap = some file) (loaded : Loaded file s) :
    ∃ c, Steps 9 s c ∧ Det 9 s c ∧ AtEntry binary entry stack heap file s.io c := by
  obtain ⟨f24, f80, f96, f104⟩ := elf_fields h
  have sz := elfSizes h
  obtain ⟨-, shape⟩ := elfFile_some h
  have lens := elf_lengths binary entry stack heap
  have flen : file.length = 215 + binary.image.length := by
    rw [shape]; simp only [List.length_append, lens] <;> omega
  have code : CodeAt s.memory (BitVec.ofNat 64 elfBase) file := by
    intro i hi
    have := loaded.bytes i (by rw [f96]; exact hi)
    rw [f80] at this
    rw [ofNat_add64, this, List.getD_eq_getElem?_getD, List.getElem?_eq_getElem hi, Option.getD_some]
  have rip : s.rip = BitVec.ofNat 64 (elfBase + 120) := by rw [loaded.rip, f24]
  have atStart : CodeAt s.memory s.rip (elfStartup binary entry stack heap ++ binary.image) := by
    have := (show CodeAt s.memory (BitVec.ofNat 64 elfBase)
      ((elfHeader binary ++ elfProgramHeader binary stack heap) ++ (elfStartup binary entry stack heap ++ binary.image))
      by rw [← List.append_assoc]; rw [← shape]; exact code).suffix
    rw [rip, ← ofNat_add64]
    simpa only [List.length_append, lens] using this
  -- The nine instructions.
  have c0 : CodeAt s.memory s.rip ((72 :: 188 :: le64n (elfTop binary stack)) ++
      ((73 :: 191 :: le64n (elfStackBase binary + stackGuard binary)) ++
      ((73 :: 188 :: le64n (elfTop binary stack)) ++ ((73 :: 190 :: le64n heap) ++ ((73 :: 189 :: le64n 1) ++
      ((73 :: 186 :: le64n (heap + stack)) ++
      ((72 :: 187 :: le64n (heap + stack)) ++
      ((73 :: 184 :: le64n (elfBase + elfBeforeImage + linkedSize binary.codes)) ++
      ((232 :: le32 (BitVec.ofNat 32 (binary.entries.getD entry 0 + 10))) ++
      ((72 :: 137 :: 199 :: 184 :: 60 :: 0 :: 0 :: 0 :: 15 :: [5]) ++ binary.image)))))))))) := by
    simpa only [elfStartup, elfTop, List.append_assoc] using atStart
  obtain ⟨t1, n1, c1⟩ := movImm (r := rspRegister) (imm_bytes _ _ _ _ rfl) c0
  obtain ⟨t2, n2, c2⟩ := movImm (r := stackRegister) (imm_bytes _ _ _ _ rfl) c1
  obtain ⟨t3, n3, c3⟩ := movImm (r := heapBaseRegister) (imm_bytes _ _ _ _ rfl) c2
  obtain ⟨t4, n4, c4⟩ := movImm (r := limitRegister) (imm_bytes _ _ _ _ rfl) c3
  obtain ⟨t5, n5, c5'⟩ := movImm (r := cursorRegister) (imm_bytes _ _ _ _ rfl) c4
  obtain ⟨t5t, n5t, c5t⟩ := movImm (r := topRegister) (imm_bytes _ _ _ _ rfl) c5'
  obtain ⟨t5', n5', c5r⟩ := movImm (r := fspRegister) (imm_bytes _ _ _ _ rfl) c5t
  obtain ⟨t5r, n5r, c5⟩ := movImm (r := staticRegister) (imm_bytes _ _ _ _ rfl) c5r
  generalize hs5 : (((((((s.immediate64 rspRegister (BitVec.ofNat 64 (elfTop binary stack)) 10).immediate64 stackRegister
    (BitVec.ofNat 64 (elfStackBase binary + stackGuard binary)) 10).immediate64 heapBaseRegister
    (BitVec.ofNat 64 (elfTop binary stack)) 10).immediate64 limitRegister (BitVec.ofNat 64 heap) 10).immediate64
    cursorRegister (BitVec.ofNat 64 1) 10).immediate64 topRegister (BitVec.ofNat 64 (heap + stack)) 10).immediate64
    fspRegister (BitVec.ofNat 64 (heap + stack)) 10).immediate64 staticRegister
    (BitVec.ofNat 64 (elfBase + elfBeforeImage + linkedSize binary.codes)) 10 = s5 at t5r c5
  have callLoaded : CodeAt s5.memory s5.rip (callBytes (BitVec.ofNat 32 (binary.entries.getD entry 0 + 10))) := by
    rw [callBytes, ← le32_eq]; exact c5.prefix
  have t6 := call_step s5 _ _ callLoaded rfl
  have n6 := call_noRead callLoaded
  refine ⟨_, .cons t1 (.cons t2 (.cons t3 (.cons t4 (.cons t5 (.cons t5t (.cons t5' (.cons t5r (.cons t6 (.refl _))))))))),
    (Det.step t1 n1).trans ((Det.step t2 n2).trans ((Det.step t3 n3).trans ((Det.step t4 n4).trans
      ((Det.step t5 n5).trans ((Det.step t5t n5t).trans ((Det.step t5' n5').trans
        ((Det.step t5r n5r).trans (Det.step t6 n6)))))))), ?_⟩
  -- What the nine instructions leave.
  have top8 : 8 ≤ elfTop binary stack := by have := sz.low; have := sz.eight; have := sz.guard; simp only [elfTop]; omega
  have topLt : elfTop binary stack + heap + stack < 2 ^ 43 := by
    have := sz.high; have := sz.image; have := sz.stack; have := sz.heap; simp only [elfTop, elfBase] at *; omega
  have fileLe : elfBase + file.length + 8 ≤ elfTop binary stack := by
    have := sz.low; have := sz.eight; have := sz.guard; simp only [elfTop]; omega
  have r5 : ∀ r, s5.registers r = if r = staticRegister then
      BitVec.ofNat 64 (elfBase + elfBeforeImage + linkedSize binary.codes) else
      if r = fspRegister then BitVec.ofNat 64 (heap + stack) else
      if r = topRegister then BitVec.ofNat 64 (heap + stack) else if r = cursorRegister then BitVec.ofNat 64 1 else if r = limitRegister then
      BitVec.ofNat 64 heap else if r = heapBaseRegister then BitVec.ofNat 64 (elfTop binary stack) else
      if r = stackRegister then BitVec.ofNat 64 (elfStackBase binary + stackGuard binary) else
      if r = rspRegister then BitVec.ofNat 64 (elfTop binary stack) else s.registers r := by
    intro r; rw [← hs5]; rfl
  have m5 : s5.memory = s.memory := by rw [← hs5]; rfl
  have io5 : s5.io = s.io := by rw [← hs5]; rfl
  have rip5 : s5.rip = BitVec.ofNat 64 (elfBase + 200) := by
    rw [← hs5]; simp only [State.immediate64, rip, ofNat_add64]
  have sp5 : s5.registers 4 - 8 = BitVec.ofNat 64 (elfTop binary stack - 8) := by
    rw [r5]; simp only [staticRegister, fspRegister, topRegister, cursorRegister, limitRegister, heapBaseRegister,
      stackRegister, rspRegister]
    exact ofNat_sub8 top8 (by omega)
  have next5 : s5.rip + BitVec.ofNat 64 (callBytes (BitVec.ofNat 32 (binary.entries.getD entry 0 + 10))).length =
      BitVec.ofNat 64 (elfBase + 205) := by
    rw [rip5]; exact ofNat_add64 _ _
  have frame : ∀ x, x + 8 < elfTop binary stack ∨ elfTop binary stack ≤ x → x < 2 ^ 64 →
      (s5.call (BitVec.ofNat 32 (binary.entries.getD entry 0 + 10))
        (callBytes (BitVec.ofNat 32 (binary.entries.getD entry 0 + 10))).length).memory (BitVec.ofNat 64 x) =
        s.memory (BitVec.ofNat 64 x) := by
    intro x apart small
    simp only [State.call, m5]
    rw [sp5, write64_frame]
    intro lane
    rw [ofNat_add64]
    have := lane.isLt
    have hb : elfTop binary stack - 8 + lane.val < 2 ^ 64 := by omega
    apply ofNat_ne64 small hb
    rcases apart with apart | apart <;> omega
  constructor
  · simp only [State.call, rspRegister, if_true]; exact sp5
  · simp only [State.call, stackRegister, rspRegister, r5, staticRegister, fspRegister, topRegister, cursorRegister,
      limitRegister, heapBaseRegister]
    rw [stackGuard_eq]; rfl
  · simp only [State.call, heapBaseRegister, rspRegister, r5, staticRegister, fspRegister, topRegister, cursorRegister,
      limitRegister, stackRegister]; rfl
  · simp only [State.call, limitRegister, rspRegister, r5, staticRegister, fspRegister, topRegister, cursorRegister]; rfl
  · simp only [State.call, cursorRegister, rspRegister, r5, staticRegister, fspRegister, topRegister]; rfl
  · simp only [State.call, topRegister, rspRegister, r5, staticRegister, fspRegister]; rfl
  · simp only [State.call, fspRegister, rspRegister, r5, staticRegister]; rfl
  · simp only [State.call, staticRegister, rspRegister, r5]; rfl
  · simp only [State.call]
    rw [next5, signExtend_ofNat32 (by have := sz.entry; omega), ofNat_add64]
    congr 1; omega
  · intro i hi
    rw [frame _ (.inl (by omega)) (by omega)]
    have := loaded.bytes i (by rw [f96]; exact hi)
    rwa [f80] at this
  · intro a ha
    rw [frame _ (.inr (by omega)) (by omega)]
    have := loaded.zeros (elfTop binary stack + a - elfBase) (by rw [f96]; omega)
      (by rw [f104]; simp only [elfTop] at *; omega)
    rw [f80, show elfBase + (elfTop binary stack + a - elfBase) = elfTop binary stack + a by
      simp only [elfTop] at *; omega] at this
    exact this
  · simp only [State.call, m5]
    rw [sp5, read64_write64, next5]
  · exact io5

/-! ## The entry meets the compiled function's premises -/

/-- Where the static bytes are as a heap offset: the image is below the
heap's base, so the offset from it wraps around 2^64. -/
def elfStaticBase (binary : Binary) (stack : Nat) : Nat :=
  2 ^ 64 + (elfBase + 215 + linkedSize binary.codes) - elfTop binary stack

/-- The heap the process starts with: `heap` zero bytes from the stack's top,
then `stack` bytes of frame memory with the frame pointer at their end, the
process side `given` (its streams, and a trace with nothing yet), and the
binary's static bytes, which the file places after its code. -/
def elfHeap (binary : Binary) (heap stack : Nat) (given : Io) : Heap :=
  { bytes := fun _ => 0, cursor := 1, limit := heap, io := given, fsp := heap + stack, frameSize := stack,
    staticBase := elfStaticBase binary stack, statics := binary.statics }

theorem sub_toNat64 {a b : Nat} (ha : a < 2 ^ 64) (hb : b < 2 ^ 64) :
    (BitVec.ofNat 64 a - BitVec.ofNat 64 b).toNat = (2 ^ 64 - b + a) % 2 ^ 64 := by
  simp [BitVec.toNat_sub, Nat.mod_eq_of_lt ha, Nat.mod_eq_of_lt hb]

theorem toNat_ofNat64 {a : Nat} (ha : a < 2 ^ 64) : (BitVec.ofNat 64 a).toNat = a := by
  simp [Nat.mod_eq_of_lt ha]

/-- The file's bytes from `elfBase`, as code. -/
theorem AtEntry.file {binary : Binary} {entry stack heap : Nat} {file : List UInt8} {given : Io} {c : State}
    (at_ : AtEntry binary entry stack heap file given c) : CodeAt c.memory (BitVec.ofNat 64 elfBase) file := by
  intro i hi
  rw [ofNat_add64, at_.code i hi, List.getD_eq_getElem?_getD, List.getElem?_eq_getElem hi, Option.getD_some]

/-- The file is the 120 header bytes, the startup's 85 bytes up to the exit,
the 10 exit bytes and the image. -/
theorem elf_shape {binary : Binary} {entry stack heap : Nat} {file : List UInt8}
    (h : elfFile binary entry stack heap = some file) :
    ∃ pre start : List UInt8, pre.length = 120 ∧ start.length = 85 ∧
      file = pre ++ (start ++ ([72, 137, 199, 184, 60, 0, 0, 0, 15, 5] ++ binary.image)) := by
  obtain ⟨-, shape⟩ := elfFile_some h
  have lens := elf_lengths binary entry stack heap
  refine ⟨elfHeader binary ++ elfProgramHeader binary stack heap,
    (72 :: 188 :: le64n (elfTop binary stack)) ++ ((73 :: 191 :: le64n (elfStackBase binary + stackGuard binary)) ++
      ((73 :: 188 :: le64n (elfTop binary stack)) ++ ((73 :: 190 :: le64n heap) ++ ((73 :: 189 :: le64n 1) ++
      ((73 :: 186 :: le64n (heap + stack)) ++ ((72 :: 187 :: le64n (heap + stack)) ++
      ((73 :: 184 :: le64n (elfBase + elfBeforeImage + linkedSize binary.codes)) ++
      (232 :: le32 (BitVec.ofNat 32 (binary.entries.getD entry 0 + 10)))))))))),
    by simp only [List.length_append, lens], rfl, ?_⟩
  rw [shape]
  simp only [elfStartup, elfTop, List.append_assoc, List.cons_append, List.nil_append]

/-- The verified compiler's image: the code, then the static bytes. -/
theorem compileSource_layout {sp : SrcProgram} {binary : Binary} (compiled : compileSource sp = some binary) :
    binary.image = linkFrom binary.entries 0 binary.codes ++ binary.statics := by
  obtain ⟨_, _, funcs, _, compiledProgram⟩ := compileSource_some compiled
  rcases compileOptimized_some compiledProgram with original | ⟨q, _, optimized⟩
  · exact (compileProgram_spec original).2.2.1
  · exact (compileProgram_spec optimized).2.2.1

/-- The verified compiler's binary carries the program's static bytes. -/
theorem compileSource_statics {sp : SrcProgram} {binary : Binary} (compiled : compileSource sp = some binary) :
    binary.statics = sp.decls.statics := by
  obtain ⟨_, _, funcs, _, compiledProgram⟩ := compileSource_some compiled
  exact compileOptimized_statics compiledProgram

/-- The static region as the process's `str` values see it: after the code
in the image, which is below the heap's base (`elfStaticBase`). -/
def elfStatics (binary : Binary) (stack : Nat) : Statics := ⟨elfStaticBase binary stack, binary.statics⟩

/-- The process's heap holds the binary's static bytes where `str` values
name them: above frame memory, the region's end a 64-bit address. -/
theorem elfHeap_statics {binary : Binary} {entry stack heap : Nat} (sz : ElfSizes binary entry stack heap)
    (layout : binary.image = linkFrom binary.entries 0 binary.codes ++ binary.statics) (given : Io) :
    (elfHeap binary heap stack given).StaticsAt (elfStatics binary stack) := by
  have codeLen : (linkFrom binary.entries 0 binary.codes).length = linkedSize binary.codes := linkFrom_length _ _ _
  have imageLen : binary.image.length = linkedSize binary.codes + binary.statics.length := by
    rw [layout, List.length_append, codeLen]
  have hB : elfBase = 2 ^ 32 := rfl
  have := sz.low; have := sz.high; have := sz.image; have := sz.stack; have := sz.heap; have := sz.guard
  have := sz.eight
  refine ⟨rfl, rfl, fun _ => ?_, ?_⟩
  · simp only [elfHeap, Heap.top, elfStaticBase, elfTop]
    omega
  · simp only [elfHeap, elfStaticBase, elfTop]
    omega

/-- What the entry state gives the compiled function: the premises of its
`Contract` with the image at `elfBase + 215`, a window of `stack - 8` bytes
and the heap `elfHeap binary heap stack given`. -/
theorem atEntry_premises {binary : Binary} {entry stack heap : Nat} {file : List UInt8} {given : Io} {c : State}
    (h : elfFile binary entry stack heap = some file) (at_ : AtEntry binary entry stack heap file given c)
    (layout : binary.image = linkFrom binary.entries 0 binary.codes ++ binary.statics) :
    stack - 8 ≤ 2 ^ 62 ∧ CodeAt c.memory (BitVec.ofNat 64 (elfBase + 215)) binary.image ∧
      (∀ index, index < binary.image.length →
        ¬Below (c.registers rspRegister) (stack - 8) (BitVec.ofNat 64 (elfBase + 215) + BitVec.ofNat 64 index)) ∧
      (∀ index, index < binary.image.length → ¬c.InHeap (BitVec.ofNat 64 (elfBase + 215) + BitVec.ofNat 64 index)) ∧
      c.rip = BitVec.ofNat 64 (elfBase + 215) + BitVec.ofNat 64 (binary.entries.getD entry 0) ∧
      HeapAt (stack - 8) c (elfHeap binary heap stack given) ∧ StackAt binary.guard (stack - 8) c := by
  have sz := elfSizes h
  obtain ⟨pre, start, preLen, startLen, shape⟩ := elf_shape h
  have hT : elfTop binary stack = elfStackBase binary + stack := rfl
  have hB : elfBase = 2 ^ 32 := rfl
  have := sz.low; have := sz.high; have := sz.image; have := sz.stack; have := sz.heap; have := sz.guard
  have := sz.eight
  have imageAt : CodeAt c.memory (BitVec.ofNat 64 (elfBase + 215)) binary.image := by
    have whole : CodeAt c.memory (BitVec.ofNat 64 elfBase)
        ((pre ++ (start ++ [72, 137, 199, 184, 60, 0, 0, 0, 15, 5])) ++ binary.image) := by
      have := at_.file; rw [shape] at this; simpa only [List.append_assoc] using this
    have := whole.suffix
    rw [ofNat_add64] at this
    simpa only [List.length_append, preLen, startLen, List.length_cons, List.length_nil] using this
  have codeLen : (linkFrom binary.entries 0 binary.codes).length = linkedSize binary.codes := linkFrom_length _ _ _
  have imageLen : binary.image.length = linkedSize binary.codes + binary.statics.length := by
    rw [layout, List.length_append, codeLen]
  have staticsAt : CodeAt c.memory (BitVec.ofNat 64 (elfBase + 215 + linkedSize binary.codes)) binary.statics := by
    have := imageAt
    rw [layout] at this
    have := this.suffix
    rwa [codeLen, ofNat_add64] at this
  refine ⟨by omega, imageAt, ?_, ?_, ?_, ?_, ?_⟩
  · intro index bound below
    obtain ⟨-, within⟩ := below
    rw [at_.rsp, ofNat_add64, sub_toNat64 (by omega) (by omega)] at within
    omega
  · intro index bound inHeap
    obtain ⟨a, aLt, eq⟩ := inHeap
    rw [at_.base, at_.top, toNat_ofNat64 (by omega)] at *
    rw [ofNat_add64, ofNat_add64] at eq
    exact ofNat_ne64 (by omega) (by omega) (by omega) eq
  · rw [at_.rip, ofNat_add64]
  · have top : BitVec.ofNat 64 (elfTop binary stack - 8) + 8 = BitVec.ofNat 64 (elfTop binary stack) := by
      rw [show (8 : BitVec 64) = BitVec.ofNat 64 8 from rfl, ofNat_add64]; congr 1; omega
    have staticBase : elfTop binary stack + elfStaticBase binary stack = 2 ^ 64 + (elfBase + 215 + linkedSize binary.codes) := by
      simp only [elfStaticBase]; omega
    have address : ∀ k, c.registers heapBaseRegister + BitVec.ofNat 64 (elfStaticBase binary stack + k) =
        BitVec.ofNat 64 (elfBase + 215 + linkedSize binary.codes + k) := by
      intro k
      rw [at_.base, ofNat_add64]
      apply BitVec.eq_of_toNat_eq
      simp only [BitVec.toNat_ofNat]
      omega
    refine ⟨at_.cursor, ?_, ?_, at_.fsp, Nat.le_refl _, ?_, fun a aLt => ?_, fun address inHeap below => ?_, at_.io,
      ?_, fun k within => ?_⟩
    · rw [at_.heapLimit, toNat_ofNat64 (by omega)]; rfl
    · rw [at_.top, toNat_ofNat64 (by omega)]; rfl
    · show heap + stack < 2 ^ 62; omega
    · rw [at_.base, ofNat_add64]; exact at_.zero a aLt
    · obtain ⟨a, aLt, rfl⟩ := inHeap
      obtain ⟨pos, within⟩ := below
      rw [at_.top, toNat_ofNat64 (by omega)] at aLt
      rw [at_.rsp, top, at_.base, ofNat_add64, sub_toNat64 (by omega) (by omega)] at pos within
      omega
    · show _ = _ + BitVec.ofNat 64 (elfStaticBase binary stack)
      rw [← Nat.add_zero (elfStaticBase binary stack), address, Nat.add_zero, at_.static]
    · change k < binary.statics.length at within
      refine ⟨?_, ?_, ?_⟩
      · show c.memory (_ + BitVec.ofNat 64 (elfStaticBase binary stack + k)) = binary.statics.getD k 0
        rw [address, ← ofNat_add64, staticsAt k within, List.getD_eq_getElem?_getD, List.getElem?_eq_getElem within,
          Option.getD_some]
      · show ¬Below _ _ (_ + BitVec.ofNat 64 (elfStaticBase binary stack + k))
        rw [address]
        rintro ⟨-, inside⟩
        rw [at_.rsp, sub_toNat64 (by omega) (by omega)] at inside
        omega
      · show ¬c.InHeap (_ + BitVec.ofNat 64 (elfStaticBase binary stack + k))
        rw [address]
        rintro ⟨a, aLt, eq⟩
        rw [at_.base, at_.top, toNat_ofNat64 (by omega)] at *
        rw [ofNat_add64] at eq
        exact ofNat_ne64 (by omega) (by omega) (by omega) eq
  · refine ⟨?_, ?_, by omega⟩
    · rw [at_.limit, at_.rsp, toNat_ofNat64 (by omega), toNat_ofNat64 (by omega)]; omega
    · rw [at_.limit, toNat_ofNat64 (by omega)]; omega

/-! ## The return and the exit -/

theorem Exits.congr {s t : State} {code : BitVec 64} (h : Exits s code) (same : DataEq s t) : Exits t code := by
  obtain ⟨r, i, m, -⟩ := same
  exact ⟨i ▸ m ▸ h.syscall, r ▸ h.number, r ▸ h.status⟩

/-- `mov rdi, rax`, `mov eax, 60`, then the exit's `syscall`. -/
theorem exit_steps {s : State} (loaded : CodeAt s.memory s.rip [72, 137, 199, 184, 60, 0, 0, 0, 15, 5]) :
    ∃ e, Steps 2 s e ∧ Det 2 s e ∧ Exits e (s.registers 0) ∧ e.io = s.io := by
  have e1 : moveBytes .w64 7 0 = [72, 137, 199] := by decide
  have e2 : immediateBytes .w32 0 60 0 = [184, 60, 0, 0, 0] := by decide
  have mv : CodeAt s.memory s.rip (moveBytes .w64 7 0) := by
    rw [e1]; exact (show CodeAt s.memory s.rip ([72, 137, 199] ++ [184, 60, 0, 0, 0, 15, 5]) from loaded).prefix
  have t1 := move_step s (execute (moveInstruction .w64 7 0) 3 s) .w64 7 0 mv (by rw [e1]; rfl)
  have c1 : CodeAt (execute (moveInstruction .w64 7 0) 3 s).memory (execute (moveInstruction .w64 7 0) 3 s).rip
      ([184, 60, 0, 0, 0] ++ [15, 5]) :=
    CodeAt.next (first := [72, 137, 199]) loaded rfl rfl
  have im : CodeAt (execute (moveInstruction .w64 7 0) 3 s).memory (execute (moveInstruction .w64 7 0) 3 s).rip
      (immediateBytes .w32 0 60 0) := by rw [e2]; exact c1.prefix
  have t2 := immediate_step _ (execute (immediateInstruction .w32 0 60 0) 5 (execute (moveInstruction .w64 7 0) 3 s))
    .w32 0 60 0 im (by rw [e2]; rfl)
  refine ⟨_, .cons t1 (.cons t2 (.refl _)), (Det.step t1 (move_noRead mv)).trans (Det.step t2 (immediate_noRead im)),
    ⟨CodeAt.next (first := [184, 60, 0, 0, 0]) c1 rfl rfl, rfl, rfl⟩, rfl⟩

/-- When the compiled entry returns, the process exits with rax. -/
theorem returned_exits {binary : Binary} {entry stack heap : Nat} {file : List UInt8} {given : Io} {c s' : State}
    {results : List (BitVec 64)} {after : Heap}
    (h : elfFile binary entry stack heap = some file) (at_ : AtEntry binary entry stack heap file given c)
    (ret : Returned (stack - 8) c s' results after) :
    ∃ e, Steps 2 s' e ∧ Det 2 s' e ∧ Exits e (s'.registers 0) ∧ e.io = s'.io := by
  apply exit_steps
  have sz := elfSizes h
  obtain ⟨pre, start, preLen, startLen, shape⟩ := elf_shape h
  have hT : elfTop binary stack = elfStackBase binary + stack := rfl
  have hB : elfBase = 2 ^ 32 := rfl
  have := sz.low; have := sz.high; have := sz.image; have := sz.stack; have := sz.heap; have := sz.guard
  have := sz.eight
  have exitAt : CodeAt c.memory (BitVec.ofNat 64 (elfBase + 205)) [72, 137, 199, 184, 60, 0, 0, 0, 15, 5] := by
    have whole : CodeAt c.memory (BitVec.ofNat 64 elfBase)
        ((pre ++ start) ++ ([72, 137, 199, 184, 60, 0, 0, 0, 15, 5] ++ binary.image)) := by
      have := at_.file; rw [shape] at this; simpa only [List.append_assoc] using this
    have := whole.suffix.prefix
    rw [ofNat_add64] at this
    simpa only [List.length_append, preLen, startLen] using this
  rw [ret.rip, at_.rsp, at_.ret]
  intro i bound
  have small : i < 10 := bound
  rw [ret.unchanged, exitAt i bound]
  · rintro ⟨-, within⟩
    rw [at_.rsp, ofNat_add64, sub_toNat64 (by omega) (by omega)] at within
    omega
  · rintro ⟨a, aLt, eq⟩
    rw [at_.base, at_.top, toNat_ofNat64 (by omega)] at *
    rw [ofNat_add64, ofNat_add64] at eq
    exact ofNat_ne64 (by omega) (by omega) (by omega) eq

/-! ## The process -/

/-- A run that reaches a stopped state through `det` stops there. -/
theorem Det.stops {n m : Nat} {s e u : State} (det : Det n s e) (stopped : ∀ w, ¬Lanius.X86.Machine.Step e w)
    (run : Steps m s u) (stuck : ∀ w, ¬Lanius.X86.Machine.Step u w) : DataEq e u := by
  have past : n ≤ m := by
    apply Nat.le_of_not_lt
    intro less
    obtain ⟨w, step⟩ := det.2 m s u less (DataEq.refl s) run
    exact stuck w step
  obtain ⟨v, first, rest⟩ := Steps.split (show Steps (n + (m - n)) s u by rw [Nat.add_sub_cancel' past]; exact run)
  have same := det.final first
  generalize m - n = k at rest
  cases rest with
  | refl => exact same
  | cons step _ =>
    obtain ⟨w, step'⟩ := step.live same.symm
    exact (stopped w step').elim

/-- The process of `elfFile binary entry stack heap`, for a `binary` the
verified compiler made: when Core runs `entry()` to `v` within the heap,
from a world given the streams of `given` (standard input, clock readings
and secure bytes), every state `Loaded` whose process side is `given` gives
runs to `Exits` with the last of `v`'s slots, having written what the
compiled program's run wrote (`after.io`, the trace of `write` events, and
what is left of the streams; roadmap F8),
which on each of the standard output and error is what Core's world gained
there, or,
when the stack is below what the call needs, every stopped run of it is at
a fault. -/
theorem process_exits {sp : SrcProgram} {binary : Binary} {entry stack heap : Nat} {file : List UInt8}
    (compiled : compileSource sp = some binary) (h : elfFile binary entry stack heap = some file)
    {func : SrcFunc} (found : sp.funcs[entry]? = some func) (noParams : func.params = [])
    {given : Io} (silent : given.trace = []) {fuel : Nat} {v : Value} {final : Semantics.State}
    (runs : Semantics.evalExpr fuel sp.toCore (startState given) (.call entry []) = .done v final)
    (fits : final.heap.nextAddress ≤ heap) (frameRoom : sp.need entry ≤ stack) :
    ∃ depth results, ∃ after : Heap, func.ret.HoldsAt (elfStatics binary stack) [] v (Func.entry results) 0 ∧ results.length = func.ret.size ∧
      final.world.standardOutput = outputOf 1 after.io.trace ∧ final.world.standardError = outputOf 2 after.io.trace ∧
      ∀ s, Loaded file s → s.io = given →
        (∃ n e, Steps n s e ∧ Det n s e ∧ e.io = after.io ∧
          ∃ code, Exits e code ∧ ∀ w, results.getLast? = some w → code = w) ∨
        (stack - 8 < binary.stackNeed depth ∧ Faults s) := by
  have sz := elfSizes h
  have typed : FieldsHold (elfStatics binary stack) [] (paramTypes func.params) [] (Func.entry []) 0 := by rw [noParams]; exact .nil
  have bitsLen : ([] : List (BitVec 64)).length = paramsSize func.params := by rw [noParams]; rfl
  obtain ⟨depth, results, after, holds, len, out, err, contract⟩ := compileSource_contract compiled found typed bitsLen
    (heap := elfHeap binary heap stack given) rfl (fun _ _ => rfl) (by show heap < 2 ^ 62; have := sz.heap; omega) silent runs fits
    (fun _ => ⟨by show heap + _ ≤ heap + stack; omega, Nat.le_refl _, by show heap + stack < 2 ^ 62; have := sz.heap; have := sz.stack; omega⟩)
    (elfHeap_statics sz (compileSource_layout compiled) given) (compileSource_statics compiled)
  refine ⟨depth, results, after, holds, len, out, err, fun s loaded same => ?_⟩
  obtain ⟨c, steps, det, at_⟩ := startup h loaded
  rw [same] at at_
  obtain ⟨bounded, code, apart, imageHeap, rip, heapAt, stackAt⟩ := atEntry_premises h at_ (compileSource_layout compiled)
  rcases contract (BitVec.ofNat 64 (elfBase + 215)) (stack - 8) c bounded code apart imageHeap rip
      (fun k bound => absurd bound (Nat.not_lt_zero k)) heapAt stackAt with ⟨n, s', run, det', ret⟩ | ⟨short, faults⟩
  · obtain ⟨e, run2, det2, exits, io⟩ := returned_exits h at_ ret
    exact .inl ⟨9 + n + 2, e, (steps.trans run).trans run2, (det.trans det').trans det2, io.trans ret.io,
      s'.registers 0, exits, ret.value⟩
  · exact .inr ⟨short, det.faults faults⟩

/-- Every behaviour of the process: a run from a state `Loaded` gives that
stops other than at a fault stops at `Exits` with the last slot of the value
of a Core run of `entry()` that completes within the heap, or Core's call
reaches an undefined trap. -/
theorem process_behaviour {sp : SrcProgram} {binary : Binary} {entry stack heap : Nat} {file : List UInt8}
    (compiled : compileSource sp = some binary) (h : elfFile binary entry stack heap = some file)
    {func : SrcFunc} (found : sp.funcs[entry]? = some func) (noParams : func.params = [])
    (frameRoom : sp.need entry ≤ stack) {s : State} (loaded : Loaded file s) {m : Nat} {u : State} (run : Steps m s u)
    (stuck : ∀ v, ¬Lanius.X86.Machine.Step u v) (clean : ¬Lanius.X86.Machine.Fault u) :
    (∃ fuel v final, Semantics.evalExpr fuel sp.toCore (startState s.io) (.call entry []) = .done v final ∧
      final.heap.nextAddress ≤ heap ∧ ∃ results, func.ret.HoldsAt (elfStatics binary stack) [] v (Func.entry results) 0 ∧
        results.length = func.ret.size ∧ ∃ code, Exits u code ∧ ∀ w, results.getLast? = some w → code = w) ∨
    ∃ fuel r st, Semantics.evalExpr fuel sp.toCore (startState s.io) (.call entry []) = .trapped r st ∧
      undefinedTrap r = true ∧
      st.heap.nextAddress ≤ heap := by
  have sz := elfSizes h
  have typed : FieldsHold (elfStatics binary stack) [] (paramTypes func.params) [] (Func.entry []) 0 := by rw [noParams]; exact .nil
  have bitsLen : ([] : List (BitVec 64)).length = paramsSize func.params := by rw [noParams]; rfl
  obtain ⟨c, -, det, at_⟩ := startup h loaded
  have past : 9 ≤ m := by
    apply Nat.le_of_not_lt
    intro less
    obtain ⟨w, step⟩ := det.2 m s u less (DataEq.refl s) run
    exact stuck w step
  obtain ⟨c', first, rest⟩ := Steps.split (show Steps (9 + (m - 9)) s u by rw [Nat.add_sub_cancel' past]; exact run)
  obtain ⟨bounded, code, apart, imageHeap, rip, heapAt, stackAt⟩ :=
    atEntry_premises h (at_.congr (det.final first)) (compileSource_layout compiled)
  rcases compileSource_behaviour compiled found typed bitsLen (heap := elfHeap binary heap stack s.io) rfl (fun _ _ => rfl)
      (by show heap < 2 ^ 62; have := sz.heap; omega) loaded.io sz.room
      (fun _ => ⟨by show heap + _ ≤ heap + stack; omega, Nat.le_refl _, by show heap + stack < 2 ^ 62; have := sz.heap; have := sz.stack; omega⟩)
      (elfHeap_statics sz (compileSource_layout compiled) s.io) (compileSource_statics compiled) c' _ _ bounded code apart imageHeap rip
      (fun k bound => absurd bound (Nat.not_lt_zero k)) heapAt stackAt rest stuck clean with
    ⟨fuel, v, final, runs, fits⟩ | trap
  · obtain ⟨depth, results, _after, holds, len, -, -, cases⟩ := process_exits compiled h found noParams loaded.io runs fits frameRoom
    refine .inl ⟨fuel, v, final, runs, fits, results, holds, len, ?_⟩
    rcases cases s loaded rfl with ⟨n, e, -, detE, -, code, exits, value⟩ | ⟨-, faults⟩
    · exact ⟨code, exits.congr (Det.stops detE exits.stuck.1 run stuck), value⟩
    · exact (clean (faults m s u (DataEq.refl s) run stuck)).elim
  · exact .inr trap

/-! ## From source text -/

/-- `process_exits` from source text: the files mean `sp` and nothing else, and
when Core runs its `entry()` to `v` within the heap, the process exits with
the last of `v`'s slots, having written to the standard output and error what
Core's world gained there, or the stack is too small and it faults. -/
theorem textProcess_exits {files : List SourceFile} {binary : Binary} {entry stack heap : Nat} {file : List UInt8}
    (compiled : compileText files = some binary) (h : elfFile binary entry stack heap = some file) :
    ∃ sp, TextReading (files.map SourceFile.source) sp ∧
      (∀ sp', TextReading (files.map SourceFile.source) sp' → sp' = sp) ∧
      ∀ {func : SrcFunc}, sp.funcs[entry]? = some func → func.params = [] →
      ∀ {given : Io}, given.trace = [] → ∀ {fuel : Nat} {v : Value} {final : Semantics.State},
        Semantics.evalExpr fuel sp.toCore (startState given) (.call entry []) = .done v final →
        final.heap.nextAddress ≤ heap → sp.need entry ≤ stack →
        ∃ depth results, ∃ after : Heap, func.ret.HoldsAt (elfStatics binary stack) [] v (Func.entry results) 0 ∧ results.length = func.ret.size ∧
          final.world.standardOutput = outputOf 1 after.io.trace ∧
          final.world.standardError = outputOf 2 after.io.trace ∧
          ∀ s, Loaded file s → s.io = given →
            (∃ n e, Steps n s e ∧ Det n s e ∧ e.io = after.io ∧
              ∃ code, Exits e code ∧ ∀ w, results.getLast? = some w → code = w) ∨
            (stack - 8 < binary.stackNeed depth ∧ Faults s) := by
  obtain ⟨sp, reading, unique, compiledSource⟩ := compileText_reading compiled
  refine ⟨sp, reading, unique, ?_⟩
  intro func found noParams given silent fuel v final runs fits frameRoom
  exact process_exits compiledSource h found noParams silent runs fits frameRoom

/-- `process_behaviour` from source text: every run of the process that
stops other than at a fault exits with the last slot of a completed Core run
of the files' one reading's `entry()`, or that run reaches an undefined trap. -/
theorem textProcess_behaviour {files : List SourceFile} {binary : Binary} {entry stack heap : Nat}
    {file : List UInt8} (compiled : compileText files = some binary) (h : elfFile binary entry stack heap = some file) :
    ∃ sp, TextReading (files.map SourceFile.source) sp ∧
      (∀ sp', TextReading (files.map SourceFile.source) sp' → sp' = sp) ∧
      ∀ {func : SrcFunc}, sp.funcs[entry]? = some func → func.params = [] → sp.need entry ≤ stack →
      ∀ {s : State}, Loaded file s → ∀ {m : Nat} {u : State}, Steps m s u →
        (∀ v, ¬Lanius.X86.Machine.Step u v) → ¬Lanius.X86.Machine.Fault u →
        (∃ fuel v final, Semantics.evalExpr fuel sp.toCore (startState s.io) (.call entry []) = .done v final ∧
          final.heap.nextAddress ≤ heap ∧ ∃ results, func.ret.HoldsAt (elfStatics binary stack) [] v (Func.entry results) 0 ∧
            results.length = func.ret.size ∧ ∃ code, Exits u code ∧ ∀ w, results.getLast? = some w → code = w) ∨
        ∃ fuel r st, Semantics.evalExpr fuel sp.toCore (startState s.io) (.call entry []) = .trapped r st ∧
          undefinedTrap r = true ∧ st.heap.nextAddress ≤ heap := by
  obtain ⟨sp, reading, unique, compiledSource⟩ := compileText_reading compiled
  refine ⟨sp, reading, unique, ?_⟩
  intro func found noParams frameRoom s loaded m u run stuck clean
  exact process_behaviour compiledSource h found noParams frameRoom loaded run stuck clean

end Lanius.Mini
