import Lanius.X86.Machine.Scalar
import Lanius.X86.Control.Emission

namespace Lanius.X86.Machine

open Lanius.Semantics

/-- The disp32 MOV form emitted by `x86::encode::memory_form`, with a
32/64-bit operand and a 64-bit base. This describes bytes, not another compiler. -/
def memoryHeader (width : X86.Register.Width) (load : Bool) (reg base : Register) : List UInt8 :=
  let rex := X86.Register.value width reg base false
  (if rex = 0 then [] else [UInt8.ofNat rex]) ++
    [if load then 139 else 137, UInt8.ofNat (128 + reg.val % 8 * 8 + base.val % 8)] ++
    (if base.val % 8 = 4 then [36] else [])

def memoryBytes (width : X86.Register.Width) (load : Bool) (reg base : Register) (displacement : Int) : List UInt8 :=
  memoryHeader width load reg base ++ i32Bytes displacement

def memoryInstruction (width : X86.Register.Width) (load : Bool) (reg base : Register) (displacement : BitVec 32) : Instruction :=
  match width with
  | .w32 => if load then .load32 reg base displacement else .store32 reg base displacement
  | .w64 => if load then .load64 reg base displacement else .store64 reg base displacement

private theorem extended (reg : Register) :
    extendRegister ⟨reg.val % 8, Nat.mod_lt _ (by decide)⟩ (decide (8 ≤ reg.val)) = reg := by
  apply Fin.ext
  have bound := reg.isLt
  by_cases high : 8 ≤ reg.val <;> simp [extendRegister, high] <;> omega

private theorem modrm (reg base : Register) :
    let byte := UInt8.ofNat (128 + reg.val % 8 * 8 + base.val % 8)
    byte.toNat / 64 = 2 ∧ byte.toNat / 8 % 8 = reg.val % 8 ∧ byte.toNat % 8 = base.val % 8 := by
  dsimp
  rw [UInt8.toNat_ofNat', Nat.mod_eq_of_lt (by omega)]
  omega

private theorem opcode_memory (width : X86.Register.Width) (load : Bool) (reg base : Register) (displacement : Int) (tail : List UInt8) (rexPresent : Bool) :
    decodeOpcode (X86.Register.fields width reg base) rexPresent
      (([if load then 139 else 137, UInt8.ofNat (128 + reg.val % 8 * 8 + base.val % 8)] ++
        (if base.val % 8 = 4 then [36] else [])) ++ i32Bytes displacement ++ tail) =
    some (memoryInstruction width load reg base (BitVec.ofInt 32 displacement),
      6 + if base.val % 8 = 4 then 1 else 0) := by
  have fields := modrm reg base
  generalize hbyte : UInt8.ofNat (128 + reg.val % 8 * 8 + base.val % 8) = byte at fields ⊢
  cases width <;> cases load <;> by_cases sib : base.val % 8 = 4 <;>
    simp [decodeOpcode, memoryForm, X86.Register.fields, fields.1, fields.2.1, fields.2.2,
      sib, Control.displacement?_i32Bytes, memoryInstruction, extended]
  all_goals
    apply Fin.ext
    have bound := base.isLt
    by_cases high : 8 ≤ base.val <;> simp [extendRegister, high] <;> omega

theorem memory_decodes (width : X86.Register.Width) (load : Bool) (reg base : Register) (displacement : Int) (tail : List UInt8) :
    decode (memoryBytes width load reg base displacement ++ tail) =
      some (memoryInstruction width load reg base (BitVec.ofInt 32 displacement), (memoryBytes width load reg base displacement).length) := by
  let rex := X86.Register.value width reg base false
  have wordLength : (i32Bytes displacement).length = 4 := by simp [i32Bytes]
  by_cases absent : rex = 0
  · have omitted := (X86.Register.omitted_iff width reg base false).mp absent
    have narrow := omitted.1
    subst width
    have noRex : X86.Register.fields .w32 reg base = ⟨false, false, false, false⟩ := by
      simp [X86.Register.fields, show ¬ 8 ≤ reg.val by omega, show ¬ 8 ≤ base.val by omega]
    have run := opcode_memory .w32 load reg base displacement tail false
    rw [noRex] at run
    have absent' : X86.Register.value .w32 reg base false = 0 := absent
    cases load <;> by_cases sib : base.val % 8 = 4 <;>
      simpa [memoryBytes, memoryHeader, absent', decode, X86.Register.Rex.decode?,
        wordLength, List.append_assoc, sib] using run
  · have bounds := (X86.Register.value_bounds width reg base false).resolve_left absent
    have byte : (UInt8.ofNat rex).toNat = rex := by
      rw [UInt8.toNat_ofNat', Nat.mod_eq_of_lt (by omega)]
    have parsed := X86.Register.present_decodes width reg base false absent
    have run := opcode_memory width load reg base displacement tail true
    simp only [memoryBytes, memoryHeader, show X86.Register.value width reg base false = rex from rfl,
      if_neg absent, List.cons_append, List.nil_append, decode, byte]
    rw [show X86.Register.Rex.decode? rex = some (X86.Register.fields width reg base) from parsed]
    simp only [List.append_assoc, List.cons_append, List.nil_append] at run ⊢
    rw [run]
    by_cases sib : base.val % 8 = 4 <;> simp [wordLength, sib]

end Lanius.X86.Machine
