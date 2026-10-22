import Lanius.Mini.HeapSteps

/-! The x86 run of a division, `DivOp.spec`: the dividend's high half (`cdq`,
`cqo` or `xor edx, edx`), then `idiv` or `div`, whose success conditions are
the mini semantics' `Word.divides`. rdx is saved in r11 and restored. -/

namespace Lanius.Mini
open Lanius.X86.Machine

/-- The quotient and remainder x86 leaves in rax and rdx. -/
def quotientOf {w : Nat} : Bool → BitVec w → BitVec w → BitVec w
  | true, a, b => a.sdiv b
  | false, a, b => a / b

def remainderOf {w : Nat} : Bool → BitVec w → BitVec w → BitVec w
  | true, a, b => a.srem b
  | false, a, b => a % b

theorem DivOp.apply_eq {w : Nat} (operation : DivOp) (a b : BitVec w) :
    operation.apply a b =
      if operation.remainder then remainderOf operation.signed a b else quotientOf operation.signed a b := by
  cases operation <;> rfl

theorem Word.divide_eq (word : Word) (operation : DivOp) (a b : BitVec 64) :
    word.divide operation a b =
      (operation.apply (a.setWidth word.width.bits) (b.setWidth word.width.bits)).setWidth 64 := by
  cases word <;> simp [Word.divide, Word.width, X86.Register.Width.bits]

theorem Word.divides_cases (word : Word) (operation : DivOp) (a b : BitVec 64)
    (defined : word.divides operation a b = true) :
    b.setWidth word.width.bits ≠ 0 ∧ (operation.signed = true →
      a.setWidth word.width.bits ≠ BitVec.intMin _ ∨ b.setWidth word.width.bits ≠ -1) := by
  cases word <;> cases operation <;>
    simp_all [Word.divides, DivOp.defined, DivOp.signed, Word.width, X86.Register.Width.bits] <;>
    exact Classical.not_and_iff_not_or_not.mp defined.2

theorem Word.width_bits (word : Word) : 0 < word.width.bits ∧ word.width.bits ≤ 64 := by
  cases word <;> decide

theorem signedDividend_eq {w : Nat} (st : State) (pos : 0 < w)
    (high : (st.registers 2).setWidth w =
      if ((st.registers 0).setWidth w).msb then BitVec.allOnes w else 0) :
    signedDivisionDividend w st = ((st.registers 0).setWidth w).toInt := by
  unfold signedDivisionDividend divisionDividend
  generalize (st.registers 0).setWidth w = a at high ⊢
  rw [high, BitVec.toInt_eq_msb_cond]
  have big : 1 ≤ 2 ^ w := Nat.one_le_two_pow
  have sq : 2 ^ (2 * w) = 2 ^ w * 2 ^ w := by rw [Nat.two_mul, Nat.pow_add]
  cases msb : a.msb
  · simp
  · simp only [if_true, BitVec.msb_allOnes pos, BitVec.toNat_allOnes, sq]
    have small := a.isLt
    rw [Nat.sub_one_mul]
    have le : 2 ^ w ≤ 2 ^ w * 2 ^ w := Nat.le_mul_of_pos_left _ (Nat.two_pow_pos w)
    generalize 2 ^ w * 2 ^ w = m at *
    simp only [Int.ofNat_eq_natCast]
    omega

theorem unsignedDividend_eq {w : Nat} (st : State) (high : (st.registers 2).setWidth w = 0) :
    divisionDividend w st = ((st.registers 0).setWidth w).toNat := by
  simp [divisionDividend, high]

theorem setWidth_back {w : Nat} (le : w ≤ 64) (x : BitVec w) : (x.setWidth 64).setWidth w = x := by
  rw [BitVec.setWidth_setWidth_of_le _ le, BitVec.setWidth_eq]

/-- IDIV succeeds, with edx:eax (rdx:rax) the sign-extended dividend, unless
the divisor is zero or the least value is divided by -1. -/
theorem signed_success {w : Nat} (st : State) (pos : 0 < w) (le : w ≤ 64)
    (high : (st.registers 2).setWidth w =
      if ((st.registers 0).setWidth w).msb then BitVec.allOnes w else 0)
    (nonzero : (st.registers rcxRegister).setWidth w ≠ 0)
    (fits : (st.registers 0).setWidth w ≠ BitVec.intMin w ∨ (st.registers rcxRegister).setWidth w ≠ -1) :
    DivisionSuccess w true st rcxRegister
      ((quotientOf true ((st.registers 0).setWidth w) ((st.registers rcxRegister).setWidth w)).setWidth 64)
      ((remainderOf true ((st.registers 0).setWidth w) ((st.registers rcxRegister).setWidth w)).setWidth 64) := by
  unfold DivisionSuccess divisionByZero divisionFits divisionDivisor quotientOf remainderOf
  rw [signedDividend_eq st pos high]
  simp only [if_true, setWidth_back le]
  generalize (st.registers 0).setWidth w = a at fits ⊢
  generalize (st.registers rcxRegister).setWidth w = b at nonzero fits ⊢
  have q := BitVec.toInt_sdiv_of_ne_or_ne a b fits
  refine ⟨?_, ?_, q, BitVec.toInt_srem a b⟩
  · intro zero
    exact nonzero (BitVec.eq_of_toNat_eq (by simpa using zero))
  · rw [← q]
    have lo := BitVec.le_toInt (a.sdiv b)
    have hi := @BitVec.toInt_lt w (a.sdiv b)
    simp only [Int.ofNat_eq_natCast, Int.natCast_pow, Int.cast_ofNat_Int]
    exact ⟨lo, hi⟩

/-- DIV succeeds, with edx (rdx) zero, unless the divisor is zero. -/
theorem unsigned_success {w : Nat} (st : State) (le : w ≤ 64)
    (high : (st.registers 2).setWidth w = 0)
    (nonzero : (st.registers rcxRegister).setWidth w ≠ 0) :
    DivisionSuccess w false st rcxRegister
      ((quotientOf false ((st.registers 0).setWidth w) ((st.registers rcxRegister).setWidth w)).setWidth 64)
      ((remainderOf false ((st.registers 0).setWidth w) ((st.registers rcxRegister).setWidth w)).setWidth 64) := by
  unfold DivisionSuccess divisionByZero divisionFits quotientOf remainderOf
  rw [unsignedDividend_eq st high]
  simp only [Bool.false_eq_true, if_false, setWidth_back le]
  generalize (st.registers 0).setWidth w = a
  generalize (st.registers rcxRegister).setWidth w = b at nonzero ⊢
  refine ⟨?_, ?_, BitVec.toNat_udiv, BitVec.toNat_umod⟩
  · intro zero
    exact nonzero (BitVec.eq_of_toNat_eq (by simpa using zero))
  · exact Nat.lt_of_le_of_lt (Nat.div_le_self _ _) a.isLt

/-- The dividend's high half in rdx: its sign for a signed division, zero for an unsigned one. -/
def HighHalf (w : Nat) (st : State) : Bool → Prop
  | true => (st.registers 2).setWidth w = if ((st.registers 0).setWidth w).msb then BitVec.allOnes w else 0
  | false => (st.registers 2).setWidth w = 0

theorem divide_noRead {st : State} {width : X86.Register.Width} {signed : Bool} {divisor : Register}
    (loaded : CodeAt st.memory st.rip (divisionBytes width signed divisor)) : NoRead st :=
  NoRead.of loaded (division_decodes width signed divisor) (by cases width <;> rfl)

theorem signExtendDividend_noRead {st : State} {width : X86.Register.Width}
    (loaded : CodeAt st.memory st.rip (signExtendDividendBytes width)) : NoRead st :=
  NoRead.of loaded (signExtendDividend_decodes width) (by cases width <;> rfl)

/-- `cdq`, `cqo` or `xor edx, edx`. -/
theorem dividend_step (word : Word) (signed : Bool) (st : State)
    (loaded : CodeAt st.memory st.rip (dividendBytes word signed)) :
    ∃ st', Lanius.X86.Machine.Step st st' ∧ NoRead st ∧ st'.memory = st.memory ∧
      st'.rip = st.rip + BitVec.ofNat 64 (dividendBytes word signed).length ∧
      (∀ register, register ≠ 2 → st'.registers register = st.registers register) ∧
      HighHalf word.width.bits st' signed := by
  cases signed with
  | false =>
    let st' := st.alu32 .xor rdxRegister rdxRegister false (aluBytes .w32 .xor rdxRegister rdxRegister).length
    refine ⟨st', alu_step .w32 st st' .xor _ _ loaded false rfl, alu_noRead loaded, rfl, rfl, ?_, ?_⟩
    · intro register other
      simp [st', State.alu32, State.alu, rdxRegister, other]
    · cases word <;> simp [HighHalf, st', State.alu32, State.alu, Alu.result, rdxRegister, Word.width,
        X86.Register.Width.bits]
  | true =>
    simp only [dividendBytes] at loaded ⊢
    cases word with
    | s32 =>
      let st' := st.signExtendDividend32 (signExtendDividendBytes .w32).length
      refine ⟨st', signExtendDividend_step .w32 st st' loaded rfl, signExtendDividend_noRead loaded, rfl, rfl,
        ?_, ?_⟩
      · intro register other
        simp [st', State.signExtendDividend32, other]
      · simp only [HighHalf, st', State.signExtendDividend32, Word.width, X86.Register.Width.bits, if_pos,
          if_neg (show (0 : Register) ≠ 2 by decide)]
        rw [show ((st.registers 0).setWidth 32).msb = (st.registers 0).getLsbD 31 by
          simp [BitVec.msb_eq_getLsbD_last]]
        cases (st.registers 0).getLsbD 31 <;> decide
    | u64 =>
      let st' := st.signExtendDividend64 (signExtendDividendBytes .w64).length
      refine ⟨st', signExtendDividend_step .w64 st st' loaded rfl, signExtendDividend_noRead loaded, rfl, rfl,
        ?_, ?_⟩
      · intro register other
        simp [st', State.signExtendDividend64, other]
      · simp only [HighHalf, st', State.signExtendDividend64, Word.width, X86.Register.Width.bits, if_pos,
          if_neg (show (0 : Register) ≠ 2 by decide), BitVec.setWidth_eq]
        cases (st.registers 0).msb <;> decide

/-- The dividend's high half, then the divide: rax and rdx hold the quotient
and remainder of the low bits of rax by those of rcx. -/
theorem divide_steps (word : Word) (signed : Bool) (st : State)
    (loaded : CodeAt st.memory st.rip (dividendBytes word signed ++ divisionBytes word.width signed rcxRegister))
    (nonzero : (st.registers rcxRegister).setWidth word.width.bits ≠ 0)
    (fits : signed = true → (st.registers 0).setWidth word.width.bits ≠ BitVec.intMin _ ∨
      (st.registers rcxRegister).setWidth word.width.bits ≠ -1) :
    ∃ st', Steps 2 st st' ∧ Det 2 st st' ∧ st'.memory = st.memory ∧
      st'.rip = st.rip + BitVec.ofNat 64
        (dividendBytes word signed ++ divisionBytes word.width signed rcxRegister).length ∧
      st'.registers 0 = (quotientOf signed ((st.registers 0).setWidth word.width.bits)
        ((st.registers rcxRegister).setWidth word.width.bits)).setWidth 64 ∧
      st'.registers 2 = (remainderOf signed ((st.registers 0).setWidth word.width.bits)
        ((st.registers rcxRegister).setWidth word.width.bits)).setWidth 64 ∧
      ∀ register, register ≠ 0 → register ≠ 2 → st'.registers register = st.registers register := by
  obtain ⟨pos, le⟩ := word.width_bits
  obtain ⟨st1, t1, no1, memory1, rip1, kept1, high⟩ := dividend_step word signed st loaded.prefix
  have c1 := loaded.next (s' := st1) memory1 rip1
  have rax1 := kept1 0 (by decide)
  have rcx1 := kept1 rcxRegister (by decide)
  let q := (quotientOf signed ((st.registers 0).setWidth word.width.bits)
    ((st.registers rcxRegister).setWidth word.width.bits)).setWidth 64
  let r := (remainderOf signed ((st.registers 0).setWidth word.width.bits)
    ((st.registers rcxRegister).setWidth word.width.bits)).setWidth 64
  have success : DivisionSuccess word.width.bits signed st1 rcxRegister q r := by
    cases signed with
    | false =>
      have := unsigned_success st1 le high (by rw [rcx1]; exact nonzero)
      rwa [rax1, rcx1] at this
    | true =>
      have := signed_success st1 pos le high (by rw [rcx1]; exact nonzero) (by rw [rax1, rcx1]; exact fits rfl)
      rwa [rax1, rcx1] at this
  let st2 := st1.divide word.width.bits rcxRegister q r st1.flags
    (divisionBytes word.width signed rcxRegister).length
  have t2 := division_step word.width signed st1 st2 rcxRegister c1 q r st1.flags success rfl
  refine ⟨st2, .cons t1 (.cons t2 (.refl _)), Det.cons t1 no1 (Det.cons t2 (divide_noRead c1) (Det.refl _)),
    memory1, ?_, ?_, ?_, ?_⟩
  · simp only [st2, State.divide, rip1, List.length_append, BitVec.ofNat_add, BitVec.add_assoc]
  · simp [st2, State.divide, q, setWidth_back le]
  · simp [st2, State.divide, r, setWidth_back le]
  · intro register zero two
    simp [st2, State.divide, zero, two, kept1 register two]

/-- `mov rax, rdx` for a remainder, then `mov rdx, r11`. -/
theorem result_steps (remainder : Bool) (st : State)
    (loaded : CodeAt st.memory st.rip (resultBytes remainder ++ moveBytes .w64 rdxRegister r11Register)) :
    ∃ n st', Steps n st st' ∧ Det n st st' ∧ st'.memory = st.memory ∧
      st'.rip = st.rip + BitVec.ofNat 64 (resultBytes remainder ++ moveBytes .w64 rdxRegister r11Register).length ∧
      st'.registers 0 = (if remainder then st.registers 2 else st.registers 0) ∧
      st'.registers 2 = st.registers r11Register ∧
      ∀ register, register ≠ 0 → register ≠ 2 → st'.registers register = st.registers register := by
  cases remainder with
  | false =>
    let st' := st.move64 rdxRegister r11Register 3
    have t := move_step st st' .w64 rdxRegister r11Register loaded rfl
    refine ⟨1, st', .cons t (.refl _), Det.cons t (move_noRead loaded) (Det.refl _), rfl, rfl, ?_, ?_, ?_⟩
    · simp [st', State.move64, rdxRegister]
    · simp [st', State.move64, rdxRegister]
    · intro register zero two
      simp [st', State.move64, rdxRegister, two]
  | true =>
    let st1 := st.move64 0 rdxRegister 3
    have t1 := move_step st st1 .w64 0 rdxRegister loaded.prefix rfl
    have c1 := loaded.next (s' := st1) rfl rfl
    let st2 := st1.move64 rdxRegister r11Register 3
    have t2 := move_step st1 st2 .w64 rdxRegister r11Register c1 rfl
    refine ⟨2, st2, .cons t1 (.cons t2 (.refl _)),
      Det.cons t1 (move_noRead loaded.prefix) (Det.cons t2 (move_noRead c1) (Det.refl _)), rfl, ?_, ?_, ?_, ?_⟩
    · simp only [st2, st1, State.move64, resultBytes, List.length_append, BitVec.add_assoc, ← BitVec.ofNat_add]
      rfl
    · simp [st2, st1, State.move64, rdxRegister]
    · simp [st2, st1, State.move64, rdxRegister, r11Register]
    · intro register zero two
      simp [st2, st1, State.move64, rdxRegister, two, zero]

end Lanius.Mini
