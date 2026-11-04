import Lanius.Mini.Compiler

/-! # The frame slots compiled code names (F14)

`slotTop i` is one more than the largest frame slot instruction `i` reads or
writes (0 when it names none): the encoders turn each slot into a 32-bit
displacement (`slotOffset`), so the compile side's pre lemmas need the slots of
a function's code below its frame (`Code.slots`, at most `frameLimit` by
`compileFunc`'s check). Jump targets, sizes and offsets are not slots.
The open leaf `CompileFuncSlots` states the bound. -/

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

end Lanius.Faithful.SelfPre
