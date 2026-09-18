import Lanius.X86.Register

namespace Lanius.X86.Encoding

/-- The backend's one-byte and 0F-escaped opcode maps. This is an encoding
format, not a claim that every member names a supported instruction. -/
inductive Opcode where
  | primary (byte : Fin 256)
  | escaped (byte : Fin 256)
  deriving DecidableEq, Repr

def Opcode.byte : Opcode → Fin 256
  | .primary byte | .escaped byte => byte

def Opcode.extended : Opcode → Bool
  | .primary _ => false
  | .escaped _ => true

def Opcode.packed (opcode : Opcode) : Nat :=
  if opcode.extended then 3840 + opcode.byte.val else opcode.byte.val

theorem Opcode.packed_bounds (opcode : Opcode) : opcode.packed ≤ 4095 := by
  have := opcode.byte.isLt
  unfold Opcode.packed
  split <;> omega

theorem Opcode.packed_extended (opcode : Opcode) : decide (255 < opcode.packed) = opcode.extended := by
  have := opcode.byte.isLt
  cases opcode <;> simp [Opcode.packed, Opcode.extended, Opcode.byte] <;> omega

theorem Opcode.packed_byte (opcode : Opcode) : opcode.packed % 256 = opcode.byte.val := by
  have := opcode.byte.isLt
  cases opcode <;> simp [Opcode.packed, Opcode.extended, Opcode.byte] <;> omega

/-- Intel SDM vol. 2A §§2.1.3–2.1.5: mod=11 selects a register operand;
reg and r/m each occupy three bits. REX supplies their extension bits. -/
def modRM (reg rm : Fin 16) : Nat := 192 + reg.val % 8 * 8 + rm.val % 8

theorem modRM_fields (reg rm : Fin 16) :
    modRM reg rm / 64 = 3 ∧ modRM reg rm / 8 % 8 = reg.val % 8 ∧
      modRM reg rm % 8 = rm.val % 8 ∧ modRM reg rm < 256 := by
  unfold modRM
  omega

theorem extend_register (reg : Fin 16) :
    reg.val % 8 + 8 * (decide (8 ≤ reg.val)).toNat = reg.val := by
  have := reg.isLt
  by_cases high : 8 ≤ reg.val <;> simp [high, Bool.toNat] <;> omega

def header (rex : Nat) (opcode : Opcode) : List Nat :=
  (if rex = 0 then [] else [rex]) ++ (if opcode.extended then [15] else [])

def bytes (rex : Nat) (opcode : Opcode) (reg rm : Fin 16) : List Nat :=
  header rex opcode ++ [opcode.byte.val, modRM reg rm]

def size (rex : Nat) (opcode : Opcode) : Nat :=
  2 + (if rex = 0 then 0 else 1) + opcode.extended.toNat

theorem header_size (rex : Nat) (opcode : Opcode) : (header rex opcode).length + 2 = size rex opcode := by
  by_cases absent : rex = 0 <;> cases opcode <;>
    simp [header, size, absent, Opcode.extended, Bool.toNat]

theorem bytes_size (rex : Nat) (opcode : Opcode) (reg rm : Fin 16) :
    (bytes rex opcode reg rm).length = size rex opcode := by
  simpa [bytes] using header_size rex opcode

theorem bytes_are_bytes (rex : Nat) (opcode : Opcode) (reg rm : Fin 16) (bounded : rex < 256) :
    ∀ byte ∈ bytes rex opcode reg rm, byte < 256 := by
  have opcodeBound := opcode.byte.isLt
  have modrmBound := (modRM_fields reg rm).2.2.2
  by_cases absent : rex = 0 <;> cases escape : opcode.extended <;>
    simp [bytes, header, absent, escape, bounded, opcodeBound, modrmBound]

theorem size_bounds (rex : Nat) (opcode : Opcode) : 2 ≤ size rex opcode ∧ size rex opcode ≤ 4 := by
  by_cases absent : rex = 0 <;> cases opcode <;> simp [size, absent, Opcode.extended, Bool.toNat]

end Lanius.X86.Encoding
