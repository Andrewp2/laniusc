module

public import Lanius.Mini.Compiler
import all Lanius.Mini.Compiler.P.Lists_empty
import all Lanius.Mini.Compiler.P.SrcType_same
import all Lanius.Mini.Compiler.P.Word_compute
import all Lanius.Mini.Compiler.P.Word_narrows
import all Lanius.Mini.Compiler.P.arities
import all Lanius.Mini.Compiler.P.codeSize
import all Lanius.Mini.Compiler.P.compileArgs
import all Lanius.Mini.Compiler.P.linkedSize
import all Lanius.Mini.Compiler.P.loadAtBytes
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
