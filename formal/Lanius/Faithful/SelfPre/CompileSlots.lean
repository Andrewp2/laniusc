module

public import Lanius.Mini.Compiler.Types
public import Lanius.Mini.Compiler.P.BinOp_bytes
public import Lanius.Mini.Compiler.P.BinOp_number
public import Lanius.Mini.Compiler.P.CmpOp_number
public import Lanius.Mini.Compiler.P.CmpOp_test
public import Lanius.Mini.Compiler.P.Code_image
public import Lanius.Mini.Compiler.P.Code_size
public import Lanius.Mini.Compiler.P.DivOp_bytes
public import Lanius.Mini.Compiler.P.DivOp_number
public import Lanius.Mini.Compiler.P.FArith_number
public import Lanius.Mini.Compiler.P.FCmp_number
public import Lanius.Mini.Compiler.P.FOp_bytes
public import Lanius.Mini.Compiler.P.FOp_number
public import Lanius.Mini.Compiler.P.FloatTy_number
public import Lanius.Mini.Compiler.P.Lists_empty
public import Lanius.Mini.Compiler.P.Lists_length
public import Lanius.Mini.Compiler.P.MemWidth_bytes
public import Lanius.Mini.Compiler.P.SrcType_size
public import Lanius.Mini.Compiler.P.Syscall_number
public import Lanius.Mini.Compiler.P.UintTy_code
public import Lanius.Mini.Compiler.P.Word_number
public import Lanius.Mini.Compiler.P.Word_test
public import Lanius.Mini.Compiler.P.argBase
public import Lanius.Mini.Compiler.P.codeSize
public import Lanius.Mini.Compiler.P.compileFunc
public import Lanius.Mini.Compiler.P.frameLimit
public import Lanius.Mini.Compiler.P.frameSize
public import Lanius.Mini.Compiler.P.layout
public import Lanius.Mini.Compiler.P.linkOnto
public import Lanius.Mini.Compiler.P.roomAfter
public import Lanius.Mini.Compiler.P.slotOffset
public import Lanius.Mini.Compiler.P.slotRange
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
import all Lanius.Mini.Compiler.P.SrcType_same
import all Lanius.Mini.Compiler.P.SrcType_size
import all Lanius.Mini.Compiler.P.fieldOffset
import all Lanius.Mini.Compiler.P.norm
import all Lanius.Mini.Compiler.P.wrap
import all Lanius.Mini.Compiler.P.Word_compute
import all Lanius.Mini.Compiler.P.Word_sameOperand
import all Lanius.Mini.Compiler.P.Word_test
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
import all Lanius.Mini.Compiler.P.codeSize
import all Lanius.Mini.Compiler.P.compileExpr
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
import all Lanius.Mini.Compiler.P.compileFunc
import all Lanius.Mini.Compiler.P.roomFits

@[expose] public section

/-! # The frame slots compiled code names (F14)

`slotTop i` is one more than the largest frame slot instruction `i` reads or
writes (0 when it names none): the encoders turn each slot into a 32-bit
displacement (`slotOffset`), so the compile side's pre lemmas need the slots of
a function's code below its frame (`Code.slots`, at most `frameLimit` by
`compileFunc`'s check). Jump targets, sizes and offsets are not slots.
The open leaf `CompileFuncSlots` states the bound. `slotReach` also counts what
a call and a return copy: a call copies its arguments to the callee's first
slots and a return its sources to the frame's first slots, so their lists'
lengths count too (`CompileFuncSlotsV2`). -/

namespace Lanius.Faithful.SelfPre

open Lanius.Mini

/-- One more than the largest slot of a list (0 when empty). -/
def listSlotTop : List Nat → Nat
  | [] => 0
  | s :: rest => max (s + 1) (listSlotTop rest)

def slotTop : Instr → Nat
  | .imm _ => 0
  | .load s => s + 1
  | .store s => s + 1
  | .neg => 0
  | .op _ _ s => s + 1
  | .cmp _ _ s => s + 1
  | .jmp _ => 0
  | .jz _ => 0
  | .call _ args target count => max (listSlotTop args) (target + count)
  | .ret sources => listSlotTop sources
  | .bump _ => 0
  | .loadAt => 0
  | .storeAt s => s + 1
  | .loadWordAt _ => 0
  | .storeWordAt _ s => s + 1
  | .div _ _ s => s + 1
  | .fp _ s => s + 1
  | .sys _ s => s + 3
  | .frame _ => 0
  | .static _ => 0

/-- One more than the largest slot a code list names. -/
def codeSlotTop : List Instr → Nat
  | [] => 0
  | i :: rest => max (slotTop i) (codeSlotTop rest)

/-- `slotTop`, with a call's arguments and a return's sources also counted by their number:
they are copied to the callee's or the frame's first slots. -/
def slotReach : Instr → Nat
  | .imm _ => 0
  | .load s => s + 1
  | .store s => s + 1
  | .neg => 0
  | .op _ _ s => s + 1
  | .cmp _ _ s => s + 1
  | .jmp _ => 0
  | .jz _ => 0
  | .call _ args target count => max (max (listSlotTop args) args.length) (target + count)
  | .ret sources => max (listSlotTop sources) sources.length
  | .bump _ => 0
  | .loadAt => 0
  | .storeAt s => s + 1
  | .loadWordAt _ => 0
  | .storeWordAt _ s => s + 1
  | .div _ _ s => s + 1
  | .fp _ s => s + 1
  | .sys _ s => s + 3
  | .frame _ => 0
  | .static _ => 0

/-- One more than the largest slot a code list reaches (`slotReach`). -/
def codeSlotReach : List Instr → Nat
  | [] => 0
  | i :: rest => max (slotReach i) (codeSlotReach rest)

/-- How far the codes' slots pass their frames, their frames `frameLimit` (`2 ^ 20`), or
their code sizes `2 ^ 40`: 0 when every code fits (a number, so that `omega` reads it). -/
def codesSlack : List Code → Nat
  | [] => 0
  | c :: rest => max (codeSlotReach c.instrs - c.slots)
      (max (c.slots - 1048576) (max (codeSize c.instrs - 1099511627776) (codesSlack rest)))

theorem codesSlack_nil : codesSlack [] = 0 := rfl

/-- `codesSlack`'s zero test one code at a time, as the pre lemmas read it (`omega` over the unfolded
`max`/`-` form next to the other hypotheses made kernel-deep proofs). -/
theorem codesSlack_cons_eq_zero (c : Code) (rest : List Code) :
    codesSlack (c :: rest) = 0 ↔ (codeSlotReach c.instrs ≤ c.slots ∧ c.slots ≤ 1048576 ∧
      codeSize c.instrs ≤ 1099511627776 ∧ codesSlack rest = 0) := by
  simp only [codesSlack]; omega

/-- The codes' image bytes, laid out back to back (`layout`, `linkOnto`). -/
def codesSize : List Code → Nat
  | [] => 0
  | c :: rest => Code.size c + codesSize rest

/-- `roomAfter`'s room is what the codes leave of it. -/
theorem vals_roomAfter : ∀ (room : Nat) (codes : List Code) (r : Nat), roomAfter room codes = some r →
    codesSize codes + r = room
  | room, [], r, h => by
    simp only [roomAfter, Option.some.injEq] at h; simp only [codesSize]; omega
  | room, c :: rest, r, h => by
    rw [roomAfter] at h
    split at h
    · have := vals_roomAfter (room - Code.size c) rest r h
      simp only [codesSize]; omega
    · simp at h

theorem frameLimit_eq : frameLimit = 1048576 := by rfl

/-- `slot .. slot + count - 1`: `count` slots, below `slot + count`. -/
theorem val_slotRange : ∀ (slot count : Nat),
    (slotRange slot count).length = count ∧ listSlotTop (slotRange slot count) ≤ slot + count
  | slot, 0 => by simp [slotRange, listSlotTop]
  | slot, count + 1 => by
    have := val_slotRange (slot + 1) count
    rw [slotRange]; simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel, List.length_cons, listSlotTop]
    omega

theorem val_frameSize (slots : Nat) : frameSize slots ≤ 8 * slots + 16 := by
  simp only [frameSize]; omega

theorem val_argBase (slots : Nat) : argBase slots ≤ slots + 3 := by
  simp only [argBase, frameSize]; omega

end Lanius.Faithful.SelfPre
