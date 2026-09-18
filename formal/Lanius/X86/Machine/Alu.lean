import Lanius.X86.Machine.Flags

namespace Lanius.X86.Machine

/-- The register-register arithmetic/logical subset used by scalar lowering.
Intel SDM, ADD/AND (vol. 2A), OR/SUB (2B), XOR (2D):
https://www.intel.com/content/www/us/en/developer/articles/technical/intel-sdm.html -/
inductive Alu where
  | add | subtract | and | or | xor
  deriving DecidableEq, Repr

namespace Alu

def opcode : Alu → Nat
  | .add => 1 | .subtract => 41 | .and => 33 | .or => 9 | .xor => 49

def ofOpcode? : Nat → Option Alu
  | 1 => some .add | 41 => some .subtract | 33 => some .and | 9 => some .or | 49 => some .xor | _ => none

def result (operation : Alu) (left right : BitVec 32) : BitVec 32 :=
  match operation with
  | .add => left + right | .subtract => left - right
  | .and => left &&& right | .or => left ||| right | .xor => left ^^^ right

/-- Logical operations permit either AF value. ADD/SUB determine all six
arithmetic flags; other RFLAGS bits are retained in every case. -/
def flags (operation : Alu) (before : BitVec 64) (left right : BitVec 32) (auxiliary : Bool) : BitVec 64 :=
  let value := operation.result left right
  match operation with
  | .add => arithmeticFlags before (decide (2^32 ≤ left.toNat + right.toNat)) (evenParity value)
      ((left ^^^ right ^^^ value).getLsbD 4) (value == 0) value.msb
      ((left.msb == right.msb) && (value.msb != left.msb))
  | .subtract => subtractFlags before left right
  | _ => logical32Flags before value auxiliary

theorem flags_direction (operation : Alu) (before : BitVec 64) (left right : BitVec 32) (auxiliary : Bool) :
    (operation.flags before left right auxiliary).getLsbD 10 = before.getLsbD 10 := by
  cases operation <;> exact arithmeticFlags_direction _ _ _ _ _ _ _

end Alu
end Lanius.X86.Machine
