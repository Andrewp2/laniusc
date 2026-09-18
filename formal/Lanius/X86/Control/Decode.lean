import Lanius.X86.Word

namespace Lanius.X86.Control

/-- The unprefixed control-transfer subset used by the backend in 64-bit
mode. This is instruction identity, not a model of OS or stack effects. -/
inductive Instruction where
  | returnNear
  | syscall
  | ud2
  | jump (displacement : BitVec 32)
  | call (displacement : BitVec 32)
  | branch (condition : Fin 16) (displacement : BitVec 32)
deriving DecidableEq, Repr

def displacement? : List UInt8 → Option (BitVec 32)
  | a :: b :: c :: d :: _ => some (readBytes ⟨a.toFin, b.toFin, c.toFin, d.toFin⟩)
  | _ => none

/-- Decode one supported instruction and its size. `none` means unsupported
or truncated, not necessarily architecturally invalid. Prefixes, far returns,
and short/indirect branches are deliberately outside this subset.

Reference: Intel SDM volume 2, CALL/Jcc/JMP/RET/SYSCALL/UD opcode tables.
In particular, E8/E9 have a four-byte displacement in 64-bit mode. -/
def decode : List UInt8 → Option (Instruction × Nat)
  | [] => none
  | opcode :: rest =>
      match opcode.toNat with
      | 195 => some (.returnNear, 1)
      | 232 => (displacement? rest).map (fun word => (.call word, 5))
      | 233 => (displacement? rest).map (fun word => (.jump word, 5))
      | 15 => match rest with
          | [] => none
          | second :: remaining =>
              if second.toNat = 5 then some (.syscall, 2)
              else if second.toNat = 11 then some (.ud2, 2)
              else if condition : 128 ≤ second.toNat ∧ second.toNat < 144 then
                (displacement? remaining).map (fun word =>
                  (.branch ⟨second.toNat - 128, by omega⟩ word, 6))
              else none
      | _ => none

inductive Fixed where
  | returnNear
  | syscall
  | ud2
deriving DecidableEq, Repr

def Fixed.instruction : Fixed → Instruction
  | .returnNear => .returnNear
  | .syscall => .syscall
  | .ud2 => .ud2

def Fixed.bytes : Fixed → List Nat
  | .returnNear => [195]
  | .syscall => [15, 5]
  | .ud2 => [15, 11]

theorem Fixed.bytes_are_bytes (instruction : Fixed) :
    ∀ byte ∈ instruction.bytes, byte < 256 := by
  cases instruction <;> simp [Fixed.bytes]

/-- Recognition is independent of all bytes after the instruction. -/
theorem Fixed.decode (instruction : Fixed) (tail : List UInt8) :
    Control.decode (instruction.bytes.map UInt8.ofNat ++ tail) =
      some (instruction.instruction, instruction.bytes.length) := by
  cases instruction <;> rfl

end Lanius.X86.Control
