import Lanius.X86.Control.Emission

namespace Lanius.X86.Control

/-- The three near-relative forms accepted by the emitter's public API. -/
inductive Transfer where
  | jump
  | call
  | branch (condition : Fin 16)
deriving DecidableEq, Repr

def Transfer.opcode : Transfer → Nat
  | .jump => 233
  | .call => 232
  | .branch _ => 15

def Transfer.condition : Transfer → Nat
  | .branch condition => condition.val
  | _ => 0

def Transfer.conditional : Transfer → Bool
  | .branch _ => true
  | _ => false

def Transfer.size (transfer : Transfer) : Nat := if transfer.conditional then 6 else 5

def Transfer.header (transfer : Transfer) : List Nat :=
  if transfer.conditional then [15, 128 + transfer.condition] else [transfer.opcode]

def Transfer.instruction (transfer : Transfer) (word : BitVec 32) : Instruction :=
  match transfer with
  | .jump => .jump word
  | .call => .call word
  | .branch condition => .branch condition word

theorem Transfer.size_bounds (transfer : Transfer) : 5 ≤ transfer.size ∧ transfer.size ≤ 6 := by
  cases transfer <;> simp [size, conditional]

theorem Transfer.condition_bound (transfer : Transfer) : transfer.condition < 16 := by
  cases transfer with
  | jump | call => decide
  | branch condition => exact condition.isLt

theorem Transfer.opcode_conditional (transfer : Transfer) :
    decide (transfer.opcode = 15) = transfer.conditional := by cases transfer <;> rfl

@[simp] theorem Transfer.header_length (transfer : Transfer) : transfer.header.length + 4 = transfer.size := by
  cases transfer <;> rfl

theorem Transfer.decode (transfer : Transfer) (word : Int) (tail : List UInt8) :
    Control.decode (transfer.header.map UInt8.ofNat ++ (Lanius.Semantics.i32Bytes word ++ tail)) =
      some (transfer.instruction (BitVec.ofInt 32 word), transfer.size) := by
  cases transfer with
  | jump => exact decode_jump word tail
  | call => exact decode_call word tail
  | branch condition => exact decode_branch condition word tail

end Lanius.X86.Control
