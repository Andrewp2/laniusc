import Lanius.Mini.DecodeUnique
import Lanius.Mini.Flags
import Lanius.X86.Machine.RuntimeEncoding

/-! `Step` is a relation, but its only freedom is the flags that the Intel
SDM leaves undefined: AF after AND, OR, XOR and TEST, and every flag after
IMUL, NEG, the shifts and DIV. (`decode` is unique by `decode_unique`.) So two
steps from states that agree on everything but RFLAGS agree on everything but
RFLAGS again, unless the instruction reads the flags (`jcc`, `setcc`); and
after CMP, TEST, ADD, SUB, AND, OR or XOR the flag bits a condition code reads
agree as well. `Det n s s'` packages this for runs: every `n`-step run from a
state that agrees with `s` but for its flags ends agreeing with `s'` but for
its flags, and none of them stops before its `n`th step. -/

namespace Lanius.X86.Machine

/-- `s` and `t` agree on everything but RFLAGS. -/
structure DataEq (s t : State) : Prop where
  registers : s.registers = t.registers
  rip : s.rip = t.rip
  memory : s.memory = t.memory
  io : s.io = t.io

theorem DataEq.refl (s : State) : DataEq s s := ⟨rfl, rfl, rfl, rfl⟩

theorem DataEq.symm (h : DataEq s t) : DataEq t s := ⟨h.registers.symm, h.rip.symm, h.memory.symm, h.io.symm⟩

theorem DataEq.trans (h : DataEq s t) (h' : DataEq t u) : DataEq s u :=
  ⟨h.registers.trans h'.registers, h.rip.trans h'.rip, h.memory.trans h'.memory, h.io.trans h'.io⟩

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

/-- No bytes loaded at a `syscall` decode. -/
theorem decode_syscall_prefix (memory : Memory) (rip : Address) (loaded : CodeAt memory rip [15, 5]) :
    ∀ bytes, CodeAt memory rip bytes → decode bytes = none
  | [], _ => rfl
  | [b], h => by
    have e : b = 15 := by have := h 0 (by simp); have := loaded 0 (by simp); simp_all
    subst e; decide
  | b :: c :: rest, h => by
    have e : b = 15 := by have := h 0 (by simp); have := loaded 0 (by simp); simp_all
    have f : c = 5 := by have := h 1 (by simp); have := loaded 1 (by simp); simp_all
    subst e; subst f
    cases rest with
    | nil => decide
    | cons d more =>
      have sys : X86.Control.decode (15 :: 5 :: d :: more) = some (.syscall, 2) := syscall_decodes (d :: more)
      simp [decode, X86.Register.Rex.decode?, decodeOpcode, Alu.ofOpcode?, escapedForm, sys]

/-- Nothing decodes at a `syscall`. -/
theorem DecodesAt.not_syscall (h : DecodesAt s i k) (sys : CodeAt s.memory s.rip [15, 5]) : False := by
  obtain ⟨bytes, loaded, decoded⟩ := h
  rw [decode_syscall_prefix _ _ sys bytes loaded] at decoded
  cases decoded

/-- What a step decoded, and that its result is one `Results` allows; or a
`syscall` and what the kernel did. -/
theorem Step.results (step : Step s a) :
    (∃ i k, DecodesAt s i k ∧ Results i k s a) ∨ (CodeAt s.memory s.rip [15, 5] ∧ Kernel s a) := by
  cases step with
  | decoded bytes loaded i k decoded result nonDivision =>
    exact .inl ⟨i, k, ⟨bytes, loaded, decoded⟩, result ▸ execute_results i k s nonDivision⟩
  | tested bytes loaded l r k decoded aux result => exact .inl ⟨_, k, ⟨bytes, loaded, decoded⟩, aux, result⟩
  | tested64 bytes loaded l r k decoded aux result => exact .inl ⟨_, k, ⟨bytes, loaded, decoded⟩, aux, result⟩
  | arithmetic bytes loaded op d src k decoded aux result =>
    exact .inl ⟨_, k, ⟨bytes, loaded, decoded⟩, aux, result⟩
  | arithmetic64 bytes loaded op d src k decoded aux result =>
    exact .inl ⟨_, k, ⟨bytes, loaded, decoded⟩, aux, result⟩
  | multiplied bytes loaded width d src k decoded f result =>
    cases width
    · exact .inl ⟨_, k, ⟨bytes, loaded, decoded⟩, f, result⟩
    · exact .inl ⟨_, k, ⟨bytes, loaded, decoded⟩, f, result⟩
  | negated bytes loaded width d k decoded f result =>
    cases width
    · exact .inl ⟨_, k, ⟨bytes, loaded, decoded⟩, f, result⟩
    · exact .inl ⟨_, k, ⟨bytes, loaded, decoded⟩, f, result⟩
  | shifted bytes loaded width op d k decoded f result =>
    cases width
    · exact .inl ⟨_, k, ⟨bytes, loaded, decoded⟩, f, result⟩
    · exact .inl ⟨_, k, ⟨bytes, loaded, decoded⟩, f, result⟩
  | divided bytes loaded width signed d k decoded q r success f result =>
    cases width
    · exact .inl ⟨_, k, ⟨bytes, loaded, decoded⟩, q, r, f, success, result⟩
    · exact .inl ⟨_, k, ⟨bytes, loaded, decoded⟩, q, r, f, success, result⟩
  | jumped bytes loaded disp k decoded result => exact .inl ⟨_, k, ⟨bytes, loaded, decoded⟩, result⟩
  | called bytes loaded disp k decoded result => exact .inl ⟨_, k, ⟨bytes, loaded, decoded⟩, result⟩
  | addressed bytes loaded d b i sc disp k decoded result => exact .inl ⟨_, k, ⟨bytes, loaded, decoded⟩, result⟩
  | ripAddressed bytes loaded d disp k decoded result => exact .inl ⟨_, k, ⟨bytes, loaded, decoded⟩, result⟩
  | syscalled loaded kernel => exact .inr ⟨loaded, kernel⟩

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
theorem DivisionSuccess.unique {R : Register → BitVec 64} {P : Address} {M : Memory} {F G : BitVec 64} {I : Io}
    (one : DivisionSuccess width signed ⟨R, P, M, F, I⟩ divisor q r)
    (two : DivisionSuccess width signed ⟨R, P, M, G, I⟩ divisor q' r') :
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
  obtain ⟨R, P, M, F, I⟩ := s
  obtain ⟨R', P', M', G, I'⟩ := t
  obtain ⟨hR, hP, hM, hI⟩ := same
  simp only at hR hP hM hI
  subst hR hP hM hI
  cases i
  case branch code disp =>
    simp only [Results] at ra rb
    subst ra rb
    have := reads rfl code
    exact ⟨rfl, by simp only [State.branch]; rw [this], rfl, rfl⟩
  case setCondition code d =>
    simp only [Results] at ra rb
    subst ra rb
    have := reads rfl code
    exact ⟨by simp only [State.setCondition]; rw [this], rfl, rfl, rfl⟩
  case divide32 signed d =>
    obtain ⟨q, r, f, one, rfl⟩ := ra
    obtain ⟨q', r', f', two, rfl⟩ := rb
    obtain ⟨hq, hr⟩ := one.unique two
    exact ⟨by simp only [State.divide]; rw [hq, hr], rfl, rfl, rfl⟩
  case divide64 signed d =>
    obtain ⟨q, r, f, one, rfl⟩ := ra
    obtain ⟨q', r', f', two, rfl⟩ := rb
    obtain ⟨hq, hr⟩ := one.unique two
    exact ⟨by simp only [State.divide]; rw [hq, hr], rfl, rfl, rfl⟩
  case returnNear =>
    obtain ⟨-, rfl⟩ := ra
    obtain ⟨-, rfl⟩ := rb
    exact ⟨rfl, rfl, rfl, rfl⟩
  all_goals first
    | (simp only [Results] at ra rb; subst ra rb; exact ⟨rfl, rfl, rfl, rfl⟩)
    | (obtain ⟨f, rfl⟩ := ra; obtain ⟨f', rfl⟩ := rb; exact ⟨rfl, rfl, rfl, rfl⟩)

/-- After CMP, TEST, SUB or an ALU operation the condition codes agree. -/
theorem Results.condEq {i : Instruction} {k : Nat} (same : DataEq s t) (ra : Results i k s a)
    (rb : Results i k t b) (sets : i.setsFlags = true) : CondEq a.flags b.flags := by
  obtain ⟨R, P, M, F, I⟩ := s
  obtain ⟨R', P', M', G, I'⟩ := t
  obtain ⟨hR, hP, hM, hI⟩ := same
  simp only at hR hP hM hI
  subst hR hP hM hI
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

/-- Whether `s` can step depends on its data, not its flags. -/
theorem Step.live (sa : Step s a) (same : DataEq s t) : ∃ b, Step t b := by
  have code : ∀ {bytes}, CodeAt s.memory s.rip bytes → CodeAt t.memory t.rip bytes := fun h => by
    rw [← same.memory, ← same.rip]; exact h
  cases sa with
  | decoded bytes loaded i k decoded _ nonDivision => exact ⟨_, .decoded bytes (code loaded) i k decoded rfl nonDivision⟩
  | tested bytes loaded l r k decoded aux _ => exact ⟨_, .tested bytes (code loaded) l r k decoded aux rfl⟩
  | tested64 bytes loaded l r k decoded aux _ => exact ⟨_, .tested64 bytes (code loaded) l r k decoded aux rfl⟩
  | arithmetic bytes loaded op d src k decoded aux _ =>
    exact ⟨_, .arithmetic bytes (code loaded) op d src k decoded aux rfl⟩
  | arithmetic64 bytes loaded op d src k decoded aux _ =>
    exact ⟨_, .arithmetic64 bytes (code loaded) op d src k decoded aux rfl⟩
  | multiplied bytes loaded width d src k decoded f _ =>
    exact ⟨_, .multiplied bytes (code loaded) width d src k decoded f rfl⟩
  | negated bytes loaded width d k decoded f _ => exact ⟨_, .negated bytes (code loaded) width d k decoded f rfl⟩
  | shifted bytes loaded width op d k decoded f _ =>
    exact ⟨_, .shifted bytes (code loaded) width op d k decoded f rfl⟩
  | divided bytes loaded width signed divisor k decoded q r success f _ =>
    refine ⟨_, .divided bytes (code loaded) width signed divisor k decoded q r ?_ f rfl⟩
    have registers : t.registers = s.registers := same.registers.symm
    simpa only [DivisionSuccess, divisionByZero, divisionFits, signedDivisionDividend, divisionDivisor,
      divisionDividend, registers] using success
  | jumped bytes loaded d k decoded _ => exact ⟨_, .jumped bytes (code loaded) d k decoded rfl⟩
  | called bytes loaded d k decoded _ => exact ⟨_, .called bytes (code loaded) d k decoded rfl⟩
  | addressed bytes loaded d b i sc disp k decoded _ =>
    exact ⟨_, .addressed bytes (code loaded) d b i sc disp k decoded rfl⟩
  | ripAddressed bytes loaded d disp k decoded _ => exact ⟨_, .ripAddressed bytes (code loaded) d disp k decoded rfl⟩
  | syscalled loaded kernel =>
    have registers : t.registers = s.registers := same.registers.symm
    cases kernel with
    | write number fd count r11 =>
      exact ⟨_, .syscalled (code loaded) (.write (by rw [registers]; exact number) (by rw [registers]; exact fd)
        (by rw [registers]; exact count) r11)⟩

/-- No run from a state that agrees with `s` but for its flags stops before
its `n`th step. -/
def Live (n : Nat) (s : State) : Prop := ∀ j t u, j < n → DataEq s t → Steps j t u → ∃ v, Step u v

/-- Every `n`-step run from a state that agrees with `s` but for its flags ends
agreeing with `s'` but for its flags, and none stops before its `n`th step. -/
def Det (n : Nat) (s s' : State) : Prop :=
  (∀ t t', DataEq s t → Steps n t t' → DataEq s' t') ∧ Live n s

theorem Steps.split : ∀ {n m : Nat} {s u : State}, Steps (n + m) s u → ∃ v, Steps n s v ∧ Steps m v u
  | 0, m, s, u, run => ⟨s, .refl s, by simpa using run⟩
  | n + 1, m, s, u, run => by
    rw [show n + 1 + m = (n + m) + 1 by omega] at run
    cases run with
    | cons step rest =>
      obtain ⟨v, first, second⟩ := Steps.split rest
      exact ⟨v, .cons step first, second⟩

theorem Det.refl (s : State) : Det 0 s s := by
  refine ⟨fun t t' same run => ?_, fun j _ _ small => absurd small (Nat.not_lt_zero j)⟩
  cases run
  exact same

theorem Det.trans (first : Det n s m) (second : Det k m s') : Det (n + k) s s' := by
  refine ⟨fun t t' same run => ?_, fun j t u small same run => ?_⟩
  · obtain ⟨v, one, two⟩ := Steps.split run
    exact second.1 v t' (first.1 t v same one) two
  · by_cases early : j < n
    · exact first.2 j t u early same run
    · obtain ⟨v, one, two⟩ := Steps.split (show Steps (n + (j - n)) t u by rw [Nat.add_sub_cancel' (by omega)]; exact run)
      exact second.2 (j - n) v u (by omega) (first.1 t v same one) two

theorem Det.congr (det : Det n s s') (same : DataEq s' s'') : Det n s s'' :=
  ⟨fun t t' start run => same.symm.trans (det.1 t t' start run), det.2⟩

/-- The run that `Det` describes ends where every other run does. -/
theorem Det.final (det : Det n s s') (run : Steps n s t) : DataEq s' t := det.1 s t (.refl s) run

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

/-- A step from a state where an instruction decodes is that instruction's. -/
theorem Step.decodedResults (sa : Step s a) (d : DecodesAt s i k) : Results i k s a := by
  rcases sa.results with ⟨j, l, dj, rj⟩ | ⟨sys, -⟩
  · obtain ⟨rfl, rfl⟩ := d.unique dj
    exact rj
  · exact (d.not_syscall sys).elim

/-- Two steps from states that agree but for flags, where an instruction
decodes, decode the same instruction. -/
theorem Step.same (same : DataEq s t) (sa : Step s a) (tb : Step t b) (d : DecodesAt s i k) :
    Results i k s a ∧ Results i k t b :=
  ⟨sa.decodedResults d, tb.decodedResults (d.congr same)⟩

theorem Step.dataEq_of_noRead (same : DataEq s t) (sa : Step s a) (tb : Step t b) (no : NoRead s) :
    DataEq a b := by
  obtain ⟨i, k, d, nr⟩ := no
  obtain ⟨ri, rj⟩ := Step.same same sa tb d
  exact Results.dataEq same ri rj (fun reads => by rw [nr] at reads; cases reads)

theorem Step.dataEq_of_condEq (same : DataEq s t) (sa : Step s a) (tb : Step t b) (d : DecodesAt s i k)
    (flags : CondEq s.flags t.flags) : DataEq a b := by
  obtain ⟨ri, rj⟩ := Step.same same sa tb d
  exact Results.dataEq same ri rj (fun _ => flags)

theorem Step.condEq_of_writes (same : DataEq s t) (sa : Step s a) (tb : Step t b) (w : Writes s) :
    CondEq a.flags b.flags := by
  obtain ⟨i, k, d, sets⟩ := w
  obtain ⟨ri, rj⟩ := Step.same same sa tb d
  exact Results.condEq same ri rj sets

/-- A step whose instruction reads no flags. -/
theorem Det.step (sa : Step s a) (no : NoRead s) : Det 1 s a := by
  refine ⟨fun t t' same run => ?_, fun j t u small same run => ?_⟩
  · cases run with
    | cons tb rest =>
      cases rest
      exact Step.dataEq_of_noRead same sa tb no
  · obtain rfl : j = 0 := by omega
    cases run
    exact sa.live same

theorem Det.cons (sa : Step s a) (no : NoRead s) (rest : Det n a s') : Det (n + 1) s s' := by
  rw [Nat.add_comm]
  exact (Det.step sa no).trans rest

/-- A flag-setting instruction followed by any instruction, which may read
the flags it set (`cmp; setcc`, `test; jz`, `cmp; jbe`). -/
theorem Det.pair (sa : Step s a) (w : Writes s) (ab : Step a b) (d : DecodesAt a i k) : Det 2 s b := by
  have no : NoRead s := by
    obtain ⟨i, k, d, sets⟩ := w
    refine ⟨i, k, d, ?_⟩
    cases i <;> simp_all [Instruction.setsFlags, Instruction.readsFlags]
  refine ⟨fun t t' same run => ?_, fun j t u small same run => ?_⟩
  · cases run with
    | cons tu rest =>
      cases rest with
      | cons uv rest =>
        cases rest
        have first := Step.dataEq_of_noRead same sa tu no
        exact Step.dataEq_of_condEq first ab uv d (Step.condEq_of_writes same sa tu w)
  · cases run with
    | refl => exact sa.live same
    | cons tu rest =>
      cases rest with
      | refl => exact ab.live (Step.dataEq_of_noRead same sa tu no)
      | cons _ _ => omega

theorem Det.pairCons (sa : Step s a) (w : Writes s) (ab : Step a b) (d : DecodesAt a i k) (rest : Det n b s') :
    Det (n + 2) s s' := by
  rw [Nat.add_comm]
  exact (Det.pair sa w ab d).trans rest

/-! Faults. -/

theorem decode_ud2 (rest : List UInt8) : decode (15 :: 11 :: rest) = none := by
  rcases rest with _ | ⟨m, tail⟩
  · decide
  · simp [decode, Lanius.X86.Register.Rex.decode?, decodeOpcode, escapedForm, Alu.ofOpcode?,
      Lanius.X86.Control.decode]

/-- A fault has no step. -/
theorem Fault.stuck (fault : Fault s) (step : Step s t) : False := by
  rcases step.results with ⟨i, k, ⟨bytes, loaded, decoded⟩, results⟩ | ⟨sys, -⟩
  case inr =>
    cases fault with
    | ud2 code => have := code 1 (by simp); have := sys 1 (by simp); simp_all
    | divideByZero bytes code _ _ _ decoded _ =>
      rw [decode_syscall_prefix _ _ sys bytes code] at decoded; cases decoded
    | divideOverflow bytes code _ _ _ decoded _ =>
      rw [decode_syscall_prefix _ _ sys bytes code] at decoded; cases decoded
  cases fault with
  | ud2 code =>
    by_cases two : 2 ≤ bytes.length
    · have front := CodeAt.take_eq code loaded (n := 2) (by simp) two
      have split : bytes = 15 :: 11 :: bytes.drop 2 := by
        conv => lhs; rw [← List.take_append_drop 2 bytes, ← front]
        simp
      rw [split, decode_ud2] at decoded
      cases decoded
    · have front := CodeAt.take_eq code loaded (n := bytes.length) (by simp; omega) (Nat.le_refl _)
      rw [List.take_length] at front
      rcases bytes with _ | ⟨a, _ | ⟨b, rest⟩⟩
      · simp [decode] at decoded
      · simp only [List.length_cons, List.length_nil, List.take_succ_cons, List.take_zero] at front
        rw [← front, show decode [15] = none by decide] at decoded
        cases decoded
      · simp at two
  | divideByZero bytes' code width signed divisor same zero =>
    obtain ⟨rfl, rfl⟩ := Prod.mk.inj (decode_unique code loaded same decoded)
    cases width <;> obtain ⟨q, r, f, success, -⟩ := results <;> exact success.1 zero
  | divideOverflow bytes' code width signed divisor same overflow =>
    obtain ⟨rfl, rfl⟩ := Prod.mk.inj (decode_unique code loaded same decoded)
    cases width <;> obtain ⟨q, r, f, success, -⟩ := results <;> exact overflow.2 success.2.1

theorem Fault.congr (fault : Fault s) (same : DataEq s t) : Fault t := by
  have code : ∀ {bytes}, CodeAt s.memory s.rip bytes → CodeAt t.memory t.rip bytes := fun h => by
    rw [← same.memory, ← same.rip]; exact h
  have registers : t.registers = s.registers := same.registers.symm
  cases fault with
  | ud2 loaded => exact .ud2 (code loaded)
  | divideByZero bytes loaded width signed divisor decoded zero =>
    exact .divideByZero _ (code loaded) width signed divisor decoded (by
      simpa only [divisionByZero, registers] using zero)
  | divideOverflow bytes loaded width signed divisor decoded overflow =>
    exact .divideOverflow _ (code loaded) width signed divisor decoded (by
      simpa only [divisionOverflow, divisionByZero, divisionFits, signedDivisionDividend, divisionDivisor,
        divisionDividend, registers] using overflow)

/-- Every run from a state that agrees with `s` but for its flags that stops,
stops at a fault. -/
def Faults (s : State) : Prop := ∀ n t u, DataEq s t → Steps n t u → (∀ v, ¬Step u v) → Fault u

theorem Fault.faults (fault : Fault s) : Faults s := by
  intro n t u same run stuck
  cases run with
  | refl => exact fault.congr same
  | cons step _ => exact ((fault.congr same).stuck step).elim

theorem Det.faults (det : Det k s m) (faults : Faults m) : Faults s := by
  intro n t u same run stuck
  by_cases early : n < k
  · obtain ⟨v, step⟩ := det.2 n t u early same run
    exact (stuck v step).elim
  · obtain ⟨v, one, two⟩ := Steps.split (show Steps (k + (n - k)) t u by
      rw [Nat.add_sub_cancel' (by omega)]; exact run)
    exact faults (n - k) v u (det.1 t v same one) two stuck

/-- A run that never stops faults vacuously. -/
theorem Faults.of_live (live : ∀ n, Live n s) : Faults s := by
  intro n t u same run stuck
  obtain ⟨v, step⟩ := live (n + 1) n t u (by omega) same run
  exact (stuck v step).elim

/-- Every run of fewer than `n` steps from a state that agrees with `s` but
for its flags that stops, stops at a fault. -/
def FaultsWithin (n : Nat) (s : State) : Prop :=
  ∀ j t u, j < n → DataEq s t → Steps j t u → (∀ v, ¬Step u v) → Fault u

theorem FaultsWithin.zero (s : State) : FaultsWithin 0 s := fun j _ _ small => absurd small (Nat.not_lt_zero j)

theorem Faults.within (faults : Faults s) (n : Nat) : FaultsWithin n s :=
  fun j t u _ same run stuck => faults j t u same run stuck

theorem Faults.of_within (within : ∀ n, FaultsWithin n s) : Faults s :=
  fun j t u same run stuck => within (j + 1) j t u (by omega) same run stuck

/-- A `Det` run, then runs that stop only at faults: the `k` steps count. -/
theorem Det.within (det : Det k s m) (rest : FaultsWithin n m) : FaultsWithin (k + n) s := by
  intro j t u small same run stuck
  by_cases early : j < k
  · obtain ⟨v, step⟩ := det.2 j t u early same run
    exact (stuck v step).elim
  · obtain ⟨v, one, two⟩ := Steps.split (show Steps (k + (j - k)) t u by
      rw [Nat.add_sub_cancel' (by omega)]; exact run)
    exact rest (j - k) v u (by omega) (det.1 t v same one) two stuck

theorem FaultsWithin.mono (within : FaultsWithin n s) (less : k ≤ n) : FaultsWithin k s :=
  fun j t u small => within j t u (by omega)

end Lanius.X86.Machine
