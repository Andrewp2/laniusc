import Lanius.Mini.DecodeUnique
import Lanius.Mini.Flags

/-! `Step` is a relation, but its only freedom is the flags that the Intel
SDM leaves undefined: AF after AND, OR, XOR and TEST, and every flag after
IMUL, NEG, the shifts and DIV. (`decode` is unique by `decode_unique`.) So two
steps from states that agree on everything but RFLAGS agree on everything but
RFLAGS again, unless the instruction reads the flags (`jcc`, `setcc`); and
after CMP, TEST, ADD, SUB, AND, OR or XOR the flag bits a condition code reads
agree as well. `Det n s s'` packages this for runs: every `n`-step run from a
state that agrees with `s` but for its flags ends agreeing with `s'` but for
its flags. -/

namespace Lanius.X86.Machine

/-- `s` and `t` agree on everything but RFLAGS. -/
structure DataEq (s t : State) : Prop where
  registers : s.registers = t.registers
  rip : s.rip = t.rip
  memory : s.memory = t.memory

theorem DataEq.refl (s : State) : DataEq s s := ⟨rfl, rfl, rfl⟩

theorem DataEq.symm (h : DataEq s t) : DataEq t s := ⟨h.registers.symm, h.rip.symm, h.memory.symm⟩

theorem DataEq.trans (h : DataEq s t) (h' : DataEq t u) : DataEq s u :=
  ⟨h.registers.trans h'.registers, h.rip.trans h'.rip, h.memory.trans h'.memory⟩

/-- The flag bits that condition codes read (CF, PF, ZF, SF, OF) agree. -/
def CondEq (f g : BitVec 64) : Prop := ∀ code, condition f code = condition g code

/-- `jcc` and `setcc`: the only instructions whose data result reads RFLAGS. -/
def Instruction.readsFlags : Instruction → Bool
  | .branch _ _ | .setCondition _ _ => true
  | .move32 _ _ | .move64 _ _ | .load32 _ _ _ | .store32 _ _ _ | .loadByte _ _ _ | .storeByte _ _ _
  | .load64 _ _ _ | .store64 _ _ _ | .immediate32 _ _ | .immediate64 _ _ | .push64 _ | .pop64 _
  | .subtract64 _ _ | .multiply32 _ _ | .multiply64 _ _ | .negate32 _ | .negate64 _ | .shift32 _ _
  | .shift64 _ _ | .signExtendDividend32 | .signExtendDividend64 | .divide32 _ _ | .divide64 _ _
  | .alu32 _ _ _ | .alu64 _ _ _ | .compare64 _ _ | .compare32 _ _ | .test32 _ _ | .test64 _ _
  | .signExtend32 _ _ | .zeroExtendByte _ _ | .address64 _ _ _ _ _ | .ripRelative _ _ | .jump _
  | .call _ | .returnNear => false

/-- Instructions after which the condition-code flags depend only on the operands. -/
def Instruction.setsFlags : Instruction → Bool
  | .subtract64 _ _ | .alu32 _ _ _ | .alu64 _ _ _ | .compare64 _ _ | .compare32 _ _ | .test32 _ _
  | .test64 _ _ => true
  | .move32 _ _ | .move64 _ _ | .load32 _ _ _ | .store32 _ _ _ | .loadByte _ _ _ | .storeByte _ _ _
  | .load64 _ _ _ | .store64 _ _ _ | .immediate32 _ _ | .immediate64 _ _ | .push64 _ | .pop64 _
  | .multiply32 _ _ | .multiply64 _ _ | .negate32 _ | .negate64 _ | .shift32 _ _
  | .shift64 _ _ | .signExtendDividend32 | .signExtendDividend64 | .divide32 _ _ | .divide64 _ _
  | .signExtend32 _ _ | .setCondition _ _ | .zeroExtendByte _ _ | .address64 _ _ _ _ _
  | .ripRelative _ _ | .branch _ _ | .jump _ | .call _ | .returnNear => false

/-- Some bytes loaded at rip decode to `instruction` of `size` bytes. -/
def DecodesAt (s : State) (instruction : Instruction) (size : Nat) : Prop :=
  ∃ bytes, CodeAt s.memory s.rip bytes ∧ decode bytes = some (instruction, size)

theorem DecodesAt.congr (h : DecodesAt s i k) (same : DataEq s t) : DecodesAt t i k := by
  obtain ⟨bytes, loaded, decoded⟩ := h
  exact ⟨bytes, by rw [← same.memory, ← same.rip]; exact loaded, decoded⟩

theorem DecodesAt.unique (h : DecodesAt s i k) (h' : DecodesAt s i' k') : i = i' ∧ k = k' := by
  obtain ⟨bytes, loaded, decoded⟩ := h
  obtain ⟨bytes', loaded', decoded'⟩ := h'
  have := decode_unique loaded loaded' decoded decoded'
  simp only [Prod.mk.injEq] at this
  exact this

/-- Every state `Step` allows after decoding `instruction` of `size` bytes. -/
def Results : Instruction → Nat → State → State → Prop
  | .move32 d src, k, s, a => a = s.move32 d src k
  | .move64 d src, k, s, a => a = s.move64 d src k
  | .load32 d b disp, k, s, a => a = s.load32 d b disp k
  | .store32 src b disp, k, s, a => a = s.store32 src b disp k
  | .loadByte d b disp, k, s, a => a = s.loadByte d b disp k
  | .storeByte src b disp, k, s, a => a = s.storeByte src b disp k
  | .load64 d b disp, k, s, a => a = s.load64 d b disp k
  | .store64 src b disp, k, s, a => a = s.store64 src b disp k
  | .immediate32 d v, k, s, a => a = s.immediate32 d v k
  | .immediate64 d v, k, s, a => a = s.immediate64 d v k
  | .push64 src, k, s, a => a = s.push64 src k
  | .pop64 d, k, s, a => a = s.pop64 d k
  | .subtract64 d src, k, s, a => a = s.subtract64 d src k
  | .multiply32 d src, k, s, a => ∃ f, a = s.multiply 32 d src f k
  | .multiply64 d src, k, s, a => ∃ f, a = s.multiply 64 d src f k
  | .negate32 d, k, s, a => ∃ f, a = s.negate 32 d f k
  | .negate64 d, k, s, a => ∃ f, a = s.negate 64 d f k
  | .shift32 op d, k, s, a => ∃ f, a = s.shift 32 op d f k
  | .shift64 op d, k, s, a => ∃ f, a = s.shift 64 op d f k
  | .signExtendDividend32, k, s, a => a = s.signExtendDividend32 k
  | .signExtendDividend64, k, s, a => a = s.signExtendDividend64 k
  | .divide32 signed d, k, s, a => ∃ q r f, DivisionSuccess 32 signed s d q r ∧ a = s.divide 32 d q r f k
  | .divide64 signed d, k, s, a => ∃ q r f, DivisionSuccess 64 signed s d q r ∧ a = s.divide 64 d q r f k
  | .alu32 op d src, k, s, a => ∃ aux, a = s.alu32 op d src aux k
  | .alu64 op d src, k, s, a => ∃ aux, a = s.alu64 op d src aux k
  | .compare64 l r, k, s, a => a = s.compare64 l r k
  | .compare32 l r, k, s, a => a = s.compare32 l r k
  | .test32 l r, k, s, a => ∃ aux, a = s.test32 l r aux k
  | .test64 l r, k, s, a => ∃ aux, a = s.test64 l r aux k
  | .signExtend32 d src, k, s, a => a = s.signExtend32 d src k
  | .setCondition code d, k, s, a => a = s.setCondition code d k
  | .zeroExtendByte d src, k, s, a => a = s.zeroExtendByte d src k
  | .address64 d b i sc disp, k, s, a => a = s.address64 d b i sc disp k
  | .ripRelative d disp, k, s, a => a = s.ripRelative d disp k
  | .branch code disp, k, s, a => a = s.branch code disp k
  | .jump disp, k, s, a => a = s.jump disp k
  | .call disp, k, s, a => a = s.call disp k
  | .returnNear, k, s, a => k = k ∧ a = s.returnNear

theorem execute_results (i : Instruction) (k : Nat) (s : State) (nonDivision : i.isDivision = false) :
    Results i k s (execute i k s) := by
  cases i <;> first
    | rfl
    | exact ⟨rfl, rfl⟩
    | exact ⟨_, rfl⟩
    | simp [Instruction.isDivision] at nonDivision

/-- What a step decoded, and that its result is one `Results` allows. -/
theorem Step.results (step : Step s a) : ∃ i k, DecodesAt s i k ∧ Results i k s a := by
  cases step with
  | decoded bytes loaded i k decoded result nonDivision =>
    exact ⟨i, k, ⟨bytes, loaded, decoded⟩, result ▸ execute_results i k s nonDivision⟩
  | tested bytes loaded l r k decoded aux result => exact ⟨_, k, ⟨bytes, loaded, decoded⟩, aux, result⟩
  | tested64 bytes loaded l r k decoded aux result => exact ⟨_, k, ⟨bytes, loaded, decoded⟩, aux, result⟩
  | arithmetic bytes loaded op d src k decoded aux result =>
    exact ⟨_, k, ⟨bytes, loaded, decoded⟩, aux, result⟩
  | arithmetic64 bytes loaded op d src k decoded aux result =>
    exact ⟨_, k, ⟨bytes, loaded, decoded⟩, aux, result⟩
  | multiplied bytes loaded width d src k decoded f result =>
    cases width
    · exact ⟨_, k, ⟨bytes, loaded, decoded⟩, f, result⟩
    · exact ⟨_, k, ⟨bytes, loaded, decoded⟩, f, result⟩
  | negated bytes loaded width d k decoded f result =>
    cases width
    · exact ⟨_, k, ⟨bytes, loaded, decoded⟩, f, result⟩
    · exact ⟨_, k, ⟨bytes, loaded, decoded⟩, f, result⟩
  | shifted bytes loaded width op d k decoded f result =>
    cases width
    · exact ⟨_, k, ⟨bytes, loaded, decoded⟩, f, result⟩
    · exact ⟨_, k, ⟨bytes, loaded, decoded⟩, f, result⟩
  | divided bytes loaded width signed d k decoded q r success f result =>
    cases width
    · exact ⟨_, k, ⟨bytes, loaded, decoded⟩, q, r, f, success, result⟩
    · exact ⟨_, k, ⟨bytes, loaded, decoded⟩, q, r, f, success, result⟩
  | jumped bytes loaded disp k decoded result => exact ⟨_, k, ⟨bytes, loaded, decoded⟩, result⟩
  | called bytes loaded disp k decoded result => exact ⟨_, k, ⟨bytes, loaded, decoded⟩, result⟩
  | addressed bytes loaded d b i sc disp k decoded result => exact ⟨_, k, ⟨bytes, loaded, decoded⟩, result⟩
  | ripAddressed bytes loaded d disp k decoded result => exact ⟨_, k, ⟨bytes, loaded, decoded⟩, result⟩

theorem arithmeticFlags_condBits (before : BitVec 64) (c p a z s o : Bool) :
    (arithmeticFlags before c p a z s o).getLsbD 0 = c ∧ (arithmeticFlags before c p a z s o).getLsbD 2 = p ∧
    (arithmeticFlags before c p a z s o).getLsbD 6 = z ∧ (arithmeticFlags before c p a z s o).getLsbD 7 = s ∧
    (arithmeticFlags before c p a z s o).getLsbD 11 = o := by
  cases c <;> cases p <;> cases a <;> cases z <;> cases s <;> cases o <;> simp [arithmeticFlags]

/-- The condition codes after an arithmetic flag update depend only on the operands. -/
theorem arithmeticFlags_cond (b1 b2 : BitVec 64) (c p a1 a2 z s o : Bool) :
    CondEq (arithmeticFlags b1 c p a1 z s o) (arithmeticFlags b2 c p a2 z s o) := by
  intro code
  obtain ⟨c1, p1, z1, s1, o1⟩ := arithmeticFlags_condBits b1 c p a1 z s o
  obtain ⟨c2, p2, z2, s2, o2⟩ := arithmeticFlags_condBits b2 c p a2 z s o
  simp only [condition, c1, p1, z1, s1, o1, c2, p2, z2, s2, o2]

theorem subtractFlags_cond (b1 b2 : BitVec 64) (left right : BitVec width) :
    CondEq (subtractFlags b1 left right) (subtractFlags b2 left right) :=
  arithmeticFlags_cond _ _ _ _ _ _ _ _ _

theorem logicalFlags_cond (b1 b2 : BitVec 64) (result : BitVec width) (a1 a2 : Bool) :
    CondEq (logicalFlags b1 result a1) (logicalFlags b2 result a2) :=
  arithmeticFlags_cond _ _ _ _ _ _ _ _ _

theorem Alu.flags_cond (operation : Alu) (b1 b2 : BitVec 64) (left right : BitVec width) (a1 a2 : Bool) :
    CondEq (operation.flags b1 left right a1) (operation.flags b2 left right a2) := by
  cases operation
  · exact arithmeticFlags_cond _ _ _ _ _ _ _ _ _
  · exact subtractFlags_cond _ _ _ _
  · exact logicalFlags_cond _ _ _ _ _
  · exact logicalFlags_cond _ _ _ _ _
  · exact logicalFlags_cond _ _ _ _ _

/-- DIV and IDIV leave no choice in the quotient and remainder they write. -/
theorem DivisionSuccess.unique {R : Register → BitVec 64} {P : Address} {M : Memory} {F G : BitVec 64}
    (one : DivisionSuccess width signed ⟨R, P, M, F⟩ divisor q r)
    (two : DivisionSuccess width signed ⟨R, P, M, G⟩ divisor q' r') :
    q.setWidth width = q'.setWidth width ∧ r.setWidth width = r'.setWidth width := by
  obtain ⟨-, -, one⟩ := one
  obtain ⟨-, -, two⟩ := two
  cases signed
  · simp only [Bool.false_eq_true, if_false, divisionDividend] at one two
    exact ⟨BitVec.eq_of_toNat_eq (one.1.trans two.1.symm), BitVec.eq_of_toNat_eq (one.2.trans two.2.symm)⟩
  · simp only [if_true, signedDivisionDividend, divisionDividend, divisionDivisor] at one two
    exact ⟨BitVec.eq_of_toInt_eq (one.1.trans two.1.symm), BitVec.eq_of_toInt_eq (one.2.trans two.2.symm)⟩

/-- **One step is deterministic but for RFLAGS.** From states that agree but
for their flags, two results of the same decoded instruction agree but for
their flags, provided the flags a condition code reads agree whenever the
instruction reads them. -/
theorem Results.dataEq {i : Instruction} {k : Nat} (same : DataEq s t) (ra : Results i k s a)
    (rb : Results i k t b) (reads : i.readsFlags = true → CondEq s.flags t.flags) : DataEq a b := by
  obtain ⟨R, P, M, F⟩ := s
  obtain ⟨R', P', M', G⟩ := t
  obtain ⟨hR, hP, hM⟩ := same
  simp only at hR hP hM
  subst hR hP hM
  cases i
  case branch code disp =>
    simp only [Results] at ra rb
    subst ra rb
    have := reads rfl code
    exact ⟨rfl, by simp only [State.branch]; rw [this], rfl⟩
  case setCondition code d =>
    simp only [Results] at ra rb
    subst ra rb
    have := reads rfl code
    exact ⟨by simp only [State.setCondition]; rw [this], rfl, rfl⟩
  case divide32 signed d =>
    obtain ⟨q, r, f, one, rfl⟩ := ra
    obtain ⟨q', r', f', two, rfl⟩ := rb
    obtain ⟨hq, hr⟩ := one.unique two
    exact ⟨by simp only [State.divide]; rw [hq, hr], rfl, rfl⟩
  case divide64 signed d =>
    obtain ⟨q, r, f, one, rfl⟩ := ra
    obtain ⟨q', r', f', two, rfl⟩ := rb
    obtain ⟨hq, hr⟩ := one.unique two
    exact ⟨by simp only [State.divide]; rw [hq, hr], rfl, rfl⟩
  case returnNear =>
    obtain ⟨-, rfl⟩ := ra
    obtain ⟨-, rfl⟩ := rb
    exact ⟨rfl, rfl, rfl⟩
  all_goals first
    | (simp only [Results] at ra rb; subst ra rb; exact ⟨rfl, rfl, rfl⟩)
    | (obtain ⟨f, rfl⟩ := ra; obtain ⟨f', rfl⟩ := rb; exact ⟨rfl, rfl, rfl⟩)

/-- After CMP, TEST, SUB or an ALU operation the condition codes agree. -/
theorem Results.condEq {i : Instruction} {k : Nat} (same : DataEq s t) (ra : Results i k s a)
    (rb : Results i k t b) (sets : i.setsFlags = true) : CondEq a.flags b.flags := by
  obtain ⟨R, P, M, F⟩ := s
  obtain ⟨R', P', M', G⟩ := t
  obtain ⟨hR, hP, hM⟩ := same
  simp only at hR hP hM
  subst hR hP hM
  cases i
  case subtract64 d src =>
    simp only [Results] at ra rb
    subst ra rb
    exact subtractFlags_cond _ _ _ _
  case alu32 op d src =>
    obtain ⟨x, rfl⟩ := ra
    obtain ⟨y, rfl⟩ := rb
    exact Alu.flags_cond _ _ _ _ _ _ _
  case alu64 op d src =>
    obtain ⟨x, rfl⟩ := ra
    obtain ⟨y, rfl⟩ := rb
    exact Alu.flags_cond _ _ _ _ _ _ _
  case compare64 l r =>
    simp only [Results] at ra rb
    subst ra rb
    exact subtractFlags_cond _ _ _ _
  case compare32 l r =>
    simp only [Results] at ra rb
    subst ra rb
    exact subtractFlags_cond _ _ _ _
  case test32 l r =>
    obtain ⟨x, rfl⟩ := ra
    obtain ⟨y, rfl⟩ := rb
    exact logicalFlags_cond _ _ _ _ _
  case test64 l r =>
    obtain ⟨x, rfl⟩ := ra
    obtain ⟨y, rfl⟩ := rb
    exact logicalFlags_cond _ _ _ _ _
  all_goals simp [Instruction.setsFlags] at sets

/-! Runs. -/

/-- Every `n`-step run from a state that agrees with `s` but for its flags ends
agreeing with `s'` but for its flags. -/
def Det (n : Nat) (s s' : State) : Prop := ∀ t t', DataEq s t → Steps n t t' → DataEq s' t'

theorem Steps.split : ∀ {n m : Nat} {s u : State}, Steps (n + m) s u → ∃ v, Steps n s v ∧ Steps m v u
  | 0, m, s, u, run => ⟨s, .refl s, by simpa using run⟩
  | n + 1, m, s, u, run => by
    rw [show n + 1 + m = (n + m) + 1 by omega] at run
    cases run with
    | cons step rest =>
      obtain ⟨v, first, second⟩ := Steps.split rest
      exact ⟨v, .cons step first, second⟩

theorem Det.refl (s : State) : Det 0 s s := by
  intro t t' same run
  cases run
  exact same

theorem Det.trans (first : Det n s m) (second : Det k m s') : Det (n + k) s s' := by
  intro t t' same run
  obtain ⟨v, one, two⟩ := Steps.split run
  exact second v t' (first t v same one) two

theorem Det.congr (det : Det n s s') (same : DataEq s' s'') : Det n s s'' :=
  fun t t' start run => same.symm.trans (det t t' start run)

/-- The run that `Det` describes ends where every other run does. -/
theorem Det.final (det : Det n s s') (run : Steps n s t) : DataEq s' t := det s t (.refl s) run

/-- The instruction at rip does not read the flags. -/
def NoRead (s : State) : Prop := ∃ i k, DecodesAt s i k ∧ i.readsFlags = false

/-- The instruction at rip determines the condition-code flags. -/
def Writes (s : State) : Prop := ∃ i k, DecodesAt s i k ∧ i.setsFlags = true

theorem NoRead.of {bytes : List UInt8} {i : Instruction} {k : Nat} (loaded : CodeAt s.memory s.rip bytes)
    (decoded : decode bytes = some (i, k)) (no : i.readsFlags = false) : NoRead s :=
  ⟨i, k, ⟨bytes, loaded, decoded⟩, no⟩

theorem Writes.of {bytes : List UInt8} {i : Instruction} {k : Nat} (loaded : CodeAt s.memory s.rip bytes)
    (decoded : decode bytes = some (i, k)) (sets : i.setsFlags = true) : Writes s :=
  ⟨i, k, ⟨bytes, loaded, decoded⟩, sets⟩

/-- Two steps from states that agree but for flags decode the same instruction. -/
theorem Step.same (same : DataEq s t) (sa : Step s a) (tb : Step t b) :
    ∃ i k, DecodesAt s i k ∧ Results i k s a ∧ Results i k t b := by
  obtain ⟨i, k, di, ri⟩ := sa.results
  obtain ⟨j, l, dj, rj⟩ := tb.results
  obtain ⟨rfl, rfl⟩ := (di.congr same).unique dj
  exact ⟨i, k, di, ri, rj⟩

theorem Step.dataEq_of_noRead (same : DataEq s t) (sa : Step s a) (tb : Step t b) (no : NoRead s) :
    DataEq a b := by
  obtain ⟨i, k, di, ri, rj⟩ := Step.same same sa tb
  obtain ⟨i0, k0, d0, nr⟩ := no
  obtain ⟨rfl, rfl⟩ := d0.unique di
  exact Results.dataEq same ri rj (fun reads => by rw [nr] at reads; cases reads)

theorem Step.dataEq_of_condEq (same : DataEq s t) (sa : Step s a) (tb : Step t b)
    (flags : CondEq s.flags t.flags) : DataEq a b := by
  obtain ⟨i, k, di, ri, rj⟩ := Step.same same sa tb
  exact Results.dataEq same ri rj (fun _ => flags)

theorem Step.condEq_of_writes (same : DataEq s t) (sa : Step s a) (tb : Step t b) (w : Writes s) :
    CondEq a.flags b.flags := by
  obtain ⟨i, k, di, ri, rj⟩ := Step.same same sa tb
  obtain ⟨i0, k0, d0, sets⟩ := w
  obtain ⟨rfl, rfl⟩ := d0.unique di
  exact Results.condEq same ri rj sets

/-- A step whose instruction reads no flags. -/
theorem Det.step (sa : Step s a) (no : NoRead s) : Det 1 s a := by
  intro t t' same run
  cases run with
  | cons tb rest =>
    cases rest
    exact Step.dataEq_of_noRead same sa tb no

theorem Det.cons (sa : Step s a) (no : NoRead s) (rest : Det n a s') : Det (n + 1) s s' := by
  rw [Nat.add_comm]
  exact (Det.step sa no).trans rest

/-- A flag-setting instruction followed by any instruction, which may read
the flags it set (`cmp; setcc`, `test; jz`, `cmp; jbe`). -/
theorem Det.pair (sa : Step s a) (w : Writes s) (ab : Step a b) : Det 2 s b := by
  intro t t' same run
  cases run with
  | cons tu rest =>
    cases rest with
    | cons uv rest =>
      cases rest
      have first := Step.dataEq_of_noRead same sa tu (by
        obtain ⟨i, k, d, sets⟩ := w
        refine ⟨i, k, d, ?_⟩
        cases i <;> simp_all [Instruction.setsFlags, Instruction.readsFlags])
      exact Step.dataEq_of_condEq first ab uv (Step.condEq_of_writes same sa tu w)

theorem Det.pairCons (sa : Step s a) (w : Writes s) (ab : Step a b) (rest : Det n b s') :
    Det (n + 2) s s' := by
  rw [Nat.add_comm]
  exact (Det.pair sa w ab).trans rest

end Lanius.X86.Machine
