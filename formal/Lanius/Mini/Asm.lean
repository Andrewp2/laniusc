import Lanius.Mini.Semantics

/-! The abstract target: an accumulator (rax), frame slots, and a program
counter that is a byte offset into the function's code. Each `Instr` is one
fixed byte sequence of the real backend (`Lanius.Mini.Bytes`) whose length is
`Instr.size`, so the x86 proof is one lemma per constructor and this level
carries the compiler logic. Jump targets are offsets from the function's first
instruction. A call's effect is a parameter: the callee's behavior. `Instr`,
`Instr.size` and `codeSize` are extracted from the Lanius source
(`Lanius.Mini.Compiler`). -/

namespace Lanius.Mini

theorem Instr.size_pos (i : Instr) : 0 < i.size := by
  cases i with
  | op word operation _ => cases operation <;> simp [Instr.size, BinOp.size] <;> omega
  | _ => simp [Instr.size] <;> omega

theorem codeSize_append (first second : List Instr) :
    codeSize (first ++ second) = codeSize first + codeSize second := by
  induction first with
  | nil => simp [codeSize]
  | cons i rest ih => simp only [List.cons_append, codeSize, ih]; omega

/-- The instruction that starts at byte offset `pc`. -/
def fetch : List Instr → Nat → Option Instr
  | [], _ => none
  | i :: rest, pc => if pc = 0 then some i else if pc < i.size then none else fetch rest (pc - i.size)

theorem fetch_append (first second : List Instr) (pc : Nat) :
    fetch (first ++ second) (codeSize first + pc) = fetch second pc := by
  induction first with
  | nil => simp [codeSize]
  | cons i rest ih =>
    have positive := i.size_pos
    simp only [List.cons_append, fetch, codeSize]
    rw [if_neg (by omega), if_neg (by omega), show i.size + codeSize rest + pc - i.size =
      codeSize rest + pc by omega]
    exact ih

/-- `block` is laid out in `code` starting at byte offset `pos`. -/
def Block (code : List Instr) (pos : Nat) (block : List Instr) : Prop :=
  ∃ pre post, code = pre ++ block ++ post ∧ codeSize pre = pos

theorem Block.left (placed : Block code pos (first ++ second)) : Block code pos first := by
  obtain ⟨pre, post, rfl, size⟩ := placed
  exact ⟨pre, second ++ post, by simp, size⟩

theorem Block.right (placed : Block code pos (first ++ second)) :
    Block code (pos + codeSize first) second := by
  obtain ⟨pre, post, rfl, size⟩ := placed
  exact ⟨pre ++ first, post, by simp, by rw [codeSize_append, size]⟩

theorem Block.fetch (placed : Block code pos [i]) : Lanius.Mini.fetch code pos = some i := by
  obtain ⟨pre, post, rfl, rfl⟩ := placed
  rw [List.append_assoc, show codeSize pre = codeSize pre + 0 from rfl, fetch_append]
  rfl

structure Machine where
  pc : Nat
  acc : BitVec 64
  slots : Nat → BitVec 64
  heap : Heap

def Machine.store (m : Machine) (slot : Nat) : Machine :=
  { m with slots := fun other => if other = slot then m.acc else m.slots other }

def readSlots (slots : Nat → BitVec 64) : List Nat → List (BitVec 64)
  | [] => []
  | slot :: rest => slots slot :: readSlots slots rest

/-- Instructions that fall through to the next one. -/
def Instr.straight : Instr → Bool
  | .imm _ | .load _ | .store _ | .neg | .op _ _ _ | .cmp _ _ _ | .fp _ _ => true
  | .jmp _ | .jz _ | .call _ _ _ _ | .ret _ | .bump _ | .loadAt | .storeAt _ | .loadWordAt _
  | .storeWordAt _ _ | .div _ _ _ | .sys _ _ => false

/-- Effect on the accumulator and slots of a straight-line instruction. -/
def Instr.update : Instr → Machine → Machine
  | .imm value, m => { m with acc := value }
  | .load slot, m => { m with acc := m.slots slot }
  | .store slot, m => m.store slot
  | .neg, m => { m with acc := widen (-low m.acc) }
  | .op word operation slot, m => { m with acc := word.apply operation (m.slots slot) m.acc }
  | .cmp word operation slot, m => { m with acc := if word.holds operation (m.slots slot) m.acc then 1 else 0 }
  | .fp operation slot, m => { m with acc := operation.apply (m.slots slot) m.acc }
  | .jmp _, m | .jz _, m | .call _ _ _ _, m | .ret _, m | .bump _, m | .loadAt, m | .storeAt _, m
  | .loadWordAt _, m | .storeWordAt _ _, m | .div _ _ _, m | .sys _ _, m => m

def Instr.step (i : Instr) (m : Machine) : Machine := { i.update m with pc := m.pc + i.size }

/-- Straight-line execution of a block. -/
def Instr.exec : List Instr → Machine → Machine
  | [], m => m
  | i :: rest, m => Instr.exec rest (i.step m)

/-- What a call may do: `calls callee args heap values after` returns
`values` and leaves `after`. -/
abbrev Calls := Nat → List (BitVec 64) → Heap → List (BitVec 64) → Heap → Prop

/-- `values` stored at `target`, `target + 1`, ... -/
def writeSlots (slots : Nat → BitVec 64) (target : Nat) (values : List (BitVec 64)) : Nat → BitVec 64 :=
  fun slot => if target ≤ slot ∧ slot < target + values.length then values.getD (slot - target) 0 else slots slot

inductive Step (calls : Calls) (code : List Instr) : Machine → Machine → Prop where
  | straight : fetch code m.pc = some i → i.straight = true → Step calls code m (i.step m)
  | jmp : fetch code m.pc = some (.jmp target) → Step calls code m { m with pc := target }
  | jzTaken : fetch code m.pc = some (.jz target) → m.acc = 0 →
      Step calls code m { m with pc := target }
  | jzNot : fetch code m.pc = some (.jz target) → m.acc ≠ 0 →
      Step calls code m { m with pc := m.pc + (Instr.jz target).size }
  | call : fetch code m.pc = some (.call callee args target count) →
      calls callee (readSlots m.slots args) m.heap values after → values.length = count →
      Step calls code m { m with pc := m.pc + (Instr.call callee args target count).size, acc := values.getLastD m.acc, slots := writeSlots m.slots target values, heap := after }
  | bump : fetch code m.pc = some (.bump shift) →
      alignUp m.heap.cursor shift + m.acc.toNat ≤ m.heap.limit →
      Step calls code m { m with
        pc := m.pc + (Instr.bump shift).size
        acc := BitVec.ofNat 64 (alignUp m.heap.cursor shift)
        heap := { m.heap with cursor := alignUp m.heap.cursor shift + m.acc.toNat } }
  | loadAt : fetch code m.pc = some .loadAt → m.acc.toNat < m.heap.limit →
      Step calls code m { m with
        pc := m.pc + Instr.loadAt.size
        acc := BitVec.ofNat 64 (m.heap.bytes m.acc.toNat).toNat }
  | storeAt : fetch code m.pc = some (.storeAt slot) → (m.slots slot).toNat < m.heap.limit →
      Step calls code m { m with
        pc := m.pc + (Instr.storeAt slot).size
        heap := m.heap.write (m.slots slot).toNat (lowByte m.acc) }
  | loadWordAt : fetch code m.pc = some (.loadWordAt width) → m.acc.toNat + width.bytes ≤ m.heap.limit →
      Step calls code m { m with
        pc := m.pc + (Instr.loadWordAt width).size
        acc := BitVec.ofNat 64 (m.heap.readLE m.acc.toNat width.bytes) }
  | storeWordAt : fetch code m.pc = some (.storeWordAt width slot) →
      (m.slots slot).toNat + width.bytes ≤ m.heap.limit →
      Step calls code m { m with
        pc := m.pc + (Instr.storeWordAt width slot).size
        heap := m.heap.writeLE (m.slots slot).toNat m.acc.toNat width.bytes }
  | div : fetch code m.pc = some (.div word operation slot) →
      word.divides operation (m.slots slot) m.acc = true →
      Step calls code m { m with
        pc := m.pc + (Instr.div word operation slot).size
        acc := word.divide operation (m.slots slot) m.acc }
  | sys : fetch code m.pc = some (.sys call slot) →
      call.run [m.slots slot, m.slots (slot + 1), m.slots (slot + 2)] m.heap = some (result, after) →
      Step calls code m { m with pc := m.pc + (Instr.sys call slot).size, acc := result, heap := after }

inductive Star (calls : Calls) (code : List Instr) : Machine → Machine → Prop where
  | refl (m : Machine) : Star calls code m m
  | step : Step calls code m middle → Star calls code middle last → Star calls code m last

theorem Star.trans (first : Star calls code m middle) (second : Star calls code middle last) :
    Star calls code m last := by
  induction first with
  | refl => exact second
  | step head _ ih => exact .step head (ih second)

theorem Star.single (step : Step calls code m next) : Star calls code m next := .step step (.refl _)

theorem Step.mono (sub : ∀ callee args heap value after, calls callee args heap value after →
      calls' callee args heap value after)
    (step : Step calls code m next) : Step calls' code m next := by
  cases step with
  | straight fetched isStraight => exact .straight fetched isStraight
  | jmp fetched => exact .jmp fetched
  | jzTaken fetched zero => exact .jzTaken fetched zero
  | jzNot fetched nonzero => exact .jzNot fetched nonzero
  | call fetched returns count => exact .call fetched (sub _ _ _ _ _ returns) count
  | bump fetched room => exact .bump fetched room
  | loadAt fetched below => exact .loadAt fetched below
  | storeAt fetched below => exact .storeAt fetched below
  | loadWordAt fetched below => exact .loadWordAt fetched below
  | storeWordAt fetched below => exact .storeWordAt fetched below
  | div fetched defined => exact .div fetched defined
  | sys fetched ran => exact .sys fetched ran

theorem Star.mono (sub : ∀ callee args heap value after, calls callee args heap value after →
      calls' callee args heap value after)
    (run : Star calls code m last) : Star calls' code m last := by
  induction run with
  | refl => exact .refl _
  | step head _ ih => exact .step (head.mono sub) ih

theorem Instr.exec_pc (block : List Instr) (m : Machine) :
    (Instr.exec block m).pc = m.pc + codeSize block := by
  induction block generalizing m with
  | nil => simp [Instr.exec, codeSize]
  | cons i rest ih => simp only [Instr.exec, ih, Instr.step, codeSize]; omega

theorem Instr.exec_heap (block : List Instr) (m : Machine) : (Instr.exec block m).heap = m.heap := by
  induction block generalizing m with
  | nil => rfl
  | cons i rest ih => rw [Instr.exec, ih]; cases i <;> rfl

theorem Instr.exec_append (first second : List Instr) (m : Machine) :
    Instr.exec (first ++ second) m = Instr.exec second (Instr.exec first m) := by
  induction first generalizing m with
  | nil => rfl
  | cons i rest ih => exact ih _

/-- A placed straight-line block runs to its end. -/
theorem Star.straight (block : List Instr) (placed : Block code m.pc block)
    (allStraight : block.all Instr.straight = true) : Star calls code m (Instr.exec block m) := by
  induction block generalizing m with
  | nil => exact .refl _
  | cons i rest ih =>
    simp only [List.all_cons, Bool.and_eq_true] at allStraight
    have here : Block code m.pc [i] := (show Block code m.pc ([i] ++ rest) from placed).left
    have next : Block code (i.step m).pc rest := by
      have := (show Block code m.pc ([i] ++ rest) from placed).right
      simpa [Instr.step, codeSize] using this
    exact .step (.straight here.fetch allStraight.1) (ih next allStraight.2)

end Lanius.Mini
