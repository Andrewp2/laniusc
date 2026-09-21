import Lanius.X86.Machine.NonDivEncoding

namespace Lanius.X86.Machine

open Lanius.X86

/-! The only divide forms emitted by `x86::encode`: CDQ/CQO and the
    register-only F7 /6 (DIV) and /7 (IDIV) forms. -/

def signExtendDividendBytes : X86.Register.Width → List UInt8
  | .w32 => [153]
  | .w64 => [72, 153]

def signExtendDividendInstruction : X86.Register.Width → Instruction
  | .w32 => .signExtendDividend32
  | .w64 => .signExtendDividend64

def cdqBytes : List UInt8 := signExtendDividendBytes .w32
def cqoBytes : List UInt8 := signExtendDividendBytes .w64

def divisionBytes (width : X86.Register.Width) (signed : Bool) (divisor : Register) : List UInt8 :=
  registerFormBytes width 247 (if signed then 7 else 6) divisor

def divisionInstruction (width : X86.Register.Width) (signed : Bool) (divisor : Register) : Instruction :=
  match width with
  | .w32 => .divide32 signed divisor
  | .w64 => .divide64 signed divisor

def divBytes (width : X86.Register.Width) (divisor : Register) : List UInt8 :=
  divisionBytes width false divisor

def idivBytes (width : X86.Register.Width) (divisor : Register) : List UInt8 :=
  divisionBytes width true divisor

theorem signExtendDividend_decodes (width : X86.Register.Width) :
    decode (signExtendDividendBytes width) =
      some (signExtendDividendInstruction width, (signExtendDividendBytes width).length) := by
  have alunone : Alu.ofOpcode? 153 = none := by decide
  cases width <;>
    simp [signExtendDividendBytes, signExtendDividendInstruction, decode,
      X86.Register.Rex.decode?, decodeOpcode, alunone]

theorem cdq_decodes : decode cdqBytes = some (.signExtendDividend32, 1) := by
  simpa [cdqBytes, signExtendDividendBytes, signExtendDividendInstruction] using signExtendDividend_decodes .w32

theorem cqo_decodes : decode cqoBytes = some (.signExtendDividend64, 2) := by
  simpa [cqoBytes, signExtendDividendBytes, signExtendDividendInstruction] using signExtendDividend_decodes .w64

private theorem extended (reg : Register) :
    extendRegister ⟨reg.val % 8, Nat.mod_lt _ (by decide)⟩ (decide (8 ≤ reg.val)) = reg := by
  apply Fin.ext
  have bound := reg.isLt
  by_cases high : 8 ≤ reg.val <;> simp [extendRegister, high] <;> omega

private theorem modrm_byte (reg rm : Register) :
    (UInt8.ofNat (X86.Encoding.modRM reg rm)).toNat = X86.Encoding.modRM reg rm := by
  rw [UInt8.toNat_ofNat', Nat.mod_eq_of_lt (X86.Encoding.modRM_fields reg rm).2.2.2]

theorem division_decodes (width : X86.Register.Width) (signed : Bool) (divisor : Register) :
    decode (divisionBytes width signed divisor) =
      some (divisionInstruction width signed divisor,
        (divisionBytes width signed divisor).length) := by
  let reg : Register := if signed then 7 else 6
  let rex := X86.Register.value width reg divisor false
  have modrm := X86.Encoding.modRM_fields reg divisor
  have modrmByte := modrm_byte reg divisor
  have rawNoRex (divisor_low : divisor.val < 8) :
      decodeOpcode ⟨false, false, false, false⟩ false
          [247, UInt8.ofNat (X86.Encoding.modRM reg divisor)] =
        some (.divide32 signed divisor, 2) := by
    have divisor_ext :
        extendRegister ⟨divisor.val % 8, Nat.mod_lt _ (by decide)⟩ false = divisor := by
      apply Fin.ext
      simp [extendRegister, Nat.mod_eq_of_lt divisor_low]
    have alunone : Alu.ofOpcode? 247 = none := by decide
    cases signed
    · dsimp [reg] at modrmByte ⊢
      dsimp [reg] at modrm
      have byte_mod : X86.Encoding.modRM 6 divisor % 256 = X86.Encoding.modRM 6 divisor :=
        Nat.mod_eq_of_lt (X86.Encoding.modRM_fields 6 divisor).2.2.2
      have reg_mod : (6 : Register).val % 8 = 6 := by decide
      have reg_field : X86.Encoding.modRM 6 divisor / 8 % 8 = 6 := by
        simpa only [show (6 : Register).val = 6 by rfl,
          Nat.mod_eq_of_lt (by decide : (6 : Nat) < 8)] using
          (X86.Encoding.modRM_fields 6 divisor).2.1
      simp only [decodeOpcode]
      simp only [modrmByte]
      simp [alunone, byte_mod, reg_mod, reg_field, modrm.1, modrm.2.1, modrm.2.2,
        divisor_ext, divisionInstruction] <;> omega
    · dsimp [reg] at modrmByte ⊢
      dsimp [reg] at modrm
      have byte_mod : X86.Encoding.modRM 7 divisor % 256 = X86.Encoding.modRM 7 divisor :=
        Nat.mod_eq_of_lt (X86.Encoding.modRM_fields 7 divisor).2.2.2
      have reg_mod : (7 : Register).val % 8 = 7 := by decide
      have reg_field : X86.Encoding.modRM 7 divisor / 8 % 8 = 7 := by
        simpa only [show (7 : Register).val = 7 by rfl,
          Nat.mod_eq_of_lt (by decide : (7 : Nat) < 8)] using
          (X86.Encoding.modRM_fields 7 divisor).2.1
      simp only [decodeOpcode]
      simp only [modrmByte]
      simp [alunone, byte_mod, reg_mod, reg_field, modrm.1, modrm.2.1, modrm.2.2,
        divisor_ext, divisionInstruction] <;> omega
  have rawRex (present : rex ≠ 0) :
      decodeOpcode (X86.Register.fields width reg divisor) true
          [247, UInt8.ofNat (X86.Encoding.modRM reg divisor)] =
        some (divisionInstruction width signed divisor, 2) := by
    have divisor_ext :
        extendRegister ⟨divisor.val % 8, Nat.mod_lt _ (by decide)⟩
          (X86.Register.fields width reg divisor).b = divisor := by
      simpa [X86.Register.fields] using extended divisor
    have alunone : Alu.ofOpcode? 247 = none := by decide
    cases width <;> cases signed
    all_goals
      simp [reg] at modrm modrmByte divisor_ext ⊢
      have byte_mod := Nat.mod_eq_of_lt modrm.2.2.2
      have reg_mod : reg.val % 8 = reg.val := by dsimp [reg]; decide
      have six_mod : (6 : Register).val % 8 = 6 := by decide
      have seven_mod : (7 : Register).val % 8 = 7 := by decide
      simp [decodeOpcode, alunone, modrmByte, byte_mod, reg_mod, six_mod, seven_mod,
        modrm.1, modrm.2.1, modrm.2.2, divisor_ext,
        divisionInstruction, X86.Register.fields, extended]
  by_cases absent : rex = 0
  · have omitted := (X86.Register.omitted_iff width reg divisor false).mp absent
    rcases omitted with ⟨width_eq, _, divisor_low, _⟩
    cases width_eq
    simpa [divisionBytes, registerFormBytes, rex, reg, absent, decode,
      X86.Register.Rex.decode?, divisionInstruction] using rawNoRex divisor_low
  · have parsed := X86.Register.present_decodes width reg divisor false absent
    have bounds := (X86.Register.value_bounds width reg divisor false).resolve_left absent
    have byte : (UInt8.ofNat rex).toNat = rex := by
      dsimp [rex]
      rw [UInt8.toNat_ofNat']
      change X86.Register.value width reg divisor false % 256 = _
      exact Nat.mod_eq_of_lt (by omega : X86.Register.value width reg divisor false < 256)
    simp only [divisionBytes, registerFormBytes, rex, reg, if_neg absent,
      List.cons_append, List.nil_append, decode, byte]
    rw [show X86.Register.Rex.decode? rex = some (X86.Register.fields width reg divisor) from parsed]
    simpa [divisionInstruction] using rawRex absent

theorem div_decodes (width : X86.Register.Width) (divisor : Register) :
    decode (divBytes width divisor) =
      some (match width with | .w32 => .divide32 false divisor | .w64 => .divide64 false divisor,
        (divBytes width divisor).length) := by
  simpa [divBytes, divisionInstruction] using division_decodes width false divisor

theorem idiv_decodes (width : X86.Register.Width) (divisor : Register) :
    decode (idivBytes width divisor) =
      some (match width with | .w32 => .divide32 true divisor | .w64 => .divide64 true divisor,
        (idivBytes width divisor).length) := by
  simpa [idivBytes, divisionInstruction] using division_decodes width true divisor

theorem signExtendDividend_step (width : X86.Register.Width) (before after : State)
    (loaded : CodeAt before.memory before.rip (signExtendDividendBytes width))
    (result : after = execute (signExtendDividendInstruction width)
      (signExtendDividendBytes width).length before) : Step before after := by
  exact Step.decoded _ loaded _ _ (signExtendDividend_decodes width) result

theorem division_step (width : X86.Register.Width) (signed : Bool) (before after : State)
    (divisor : Register)
    (loaded : CodeAt before.memory before.rip (divisionBytes width signed divisor))
    (quotient remainder flags : BitVec 64)
    (success : DivisionSuccess width.bits signed before divisor quotient remainder)
    (result : after = before.divide width.bits divisor quotient remainder flags
      (divisionBytes width signed divisor).length) : Step before after := by
  exact Step.divided _ loaded width signed divisor _
    (by cases width with
      | w32 => simpa [divisionInstruction] using division_decodes .w32 signed divisor
      | w64 => simpa [divisionInstruction] using division_decodes .w64 signed divisor)
    quotient remainder success flags result

theorem division_by_zero_fault (width : X86.Register.Width) (signed : Bool)
    (before : State) (divisor : Register)
    (loaded : CodeAt before.memory before.rip (divisionBytes width signed divisor))
    (zero : divisionByZero width.bits before divisor) :
    Fault before := by
  exact Fault.divideByZero _ loaded width signed divisor
    (by cases width with
      | w32 => simpa [divisionInstruction] using division_decodes .w32 signed divisor
      | w64 => simpa [divisionInstruction] using division_decodes .w64 signed divisor) zero

theorem division_overflow_fault (width : X86.Register.Width) (signed : Bool)
    (before : State) (divisor : Register)
    (loaded : CodeAt before.memory before.rip (divisionBytes width signed divisor))
    (overflow : divisionOverflow width.bits signed before divisor) :
    Fault before := by
  exact Fault.divideOverflow _ loaded width signed divisor
    (by cases width with
      | w32 => simpa [divisionInstruction] using division_decodes .w32 signed divisor
      | w64 => simpa [divisionInstruction] using division_decodes .w64 signed divisor) overflow

end Lanius.X86.Machine
