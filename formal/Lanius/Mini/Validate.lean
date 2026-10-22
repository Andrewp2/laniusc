import Lanius.Mini.Correct

/-! Translation validation of the optimizer (roadmap step 13). The optimizer
(`optimizeProgram`) is not proved, and nothing here unfolds it. The validator
`validate` is: when `validate p q = true`, every run of `p` that returns has a
run of `q` with the same call depth, result and heap (`Returns.validated`).
`compileOptimized` keeps the optimized program only when the validator accepts
it, so `compileOptimized_correct` has exactly the premises of
`compileProgram_correct`. -/

namespace Lanius.Mini
open Lanius.X86.Machine

/-! ## Word arithmetic on 64-bit values -/

theorem widen_toNat (x : BitVec 32) : (widen x).toNat = x.toNat := by
  simp only [BitVec.toNat_setWidth]
  exact Nat.mod_eq_of_lt (Nat.lt_of_lt_of_le x.isLt (by decide))

theorem lowBits_eq (y : BitVec 64) : lowBits y = widen (low y) := by
  apply BitVec.eq_of_toNat_eq
  rw [lowBits, BitVec.toNat_and, widen_toNat, BitVec.toNat_setWidth]
  have : (4294967295 : BitVec 64).toNat = 2 ^ 32 - 1 := rfl
  rw [this, Nat.and_two_pow_sub_one_eq_mod]

theorem widen_inj {x y : BitVec 32} (same : widen x = widen y) : x = y := by
  apply BitVec.eq_of_toNat_eq
  rw [← widen_toNat x, ← widen_toNat y, same]

theorem low_widen (x : BitVec 32) : low (widen x) = x := by
  apply BitVec.eq_of_toNat_eq
  have := x.isLt
  simp only [BitVec.toNat_setWidth]
  omega

theorem low_sub (a b : BitVec 64) : low (a - b) = low a - low b := by
  apply BitVec.eq_of_toNat_eq
  simp only [BitVec.toNat_setWidth, BitVec.toNat_sub]
  omega

theorem low_neg (a : BitVec 64) : low (0 - a) = - low a := by
  have : (0 : BitVec 64) - a = -a := by simp
  rw [this]; exact BitVec.setWidth_neg_of_le (by omega)

theorem low_apply (operation : BinOp) (a b : BitVec 64) :
    low (operation.apply a b) = operation.apply (low a) (low b) := by
  cases operation
  · exact BitVec.setWidth_add _ _ (by omega)
  · exact low_sub a b
  · exact BitVec.setWidth_mul _ _ (by omega)
  · simp [BinOp.apply]
  · simp [BinOp.apply]
  · simp [BinOp.apply]

theorem BinOp.compute_eq (operation : BinOp) (a b : BitVec 64) :
    operation.compute a b = operation.apply a b := by
  cases operation <;> rfl

theorem Word.compute_eq (word : Word) (operation : BinOp) (a b : BitVec 64) :
    word.compute operation a b = word.apply operation a b := by
  cases word
  · simp only [Word.compute, Word.apply, BinOp.compute_eq, lowBits_eq, low_apply]
  · simp only [Word.compute, Word.apply, BinOp.compute_eq]

theorem key_toNat (a : BitVec 64) : (signedKey a).toNat = ((low a).toNat + 2147483648) % 2 ^ 32 := by
  rw [signedKey, lowBits_eq, widen_toNat]
  show (BitVec.setWidth 32 (a + 2147483648)).toNat = _
  rw [BitVec.setWidth_add _ _ (by omega), BitVec.toNat_add]
  rfl

theorem toInt32 (x : BitVec 32) :
    x.toInt = if x.toNat < 2147483648 then (x.toNat : Int) else (x.toNat : Int) - 4294967296 := by
  rw [BitVec.toInt_eq_toNat_cond]
  have := x.isLt
  split <;> split <;> omega

theorem key_lt (a b : BitVec 64) : signedKey a < signedKey b ↔ (low a).slt (low b) := by
  rw [BitVec.lt_def, key_toNat, key_toNat, BitVec.slt_iff_toInt_lt, toInt32, toInt32]
  have := (low a).isLt
  have := (low b).isLt
  generalize (low a).toNat = x at *
  generalize (low b).toNat = y at *
  split <;> split <;> omega

theorem key_le (a b : BitVec 64) : signedKey a ≤ signedKey b ↔ (low a).sle (low b) := by
  rw [BitVec.le_def, key_toNat, key_toNat, BitVec.sle_iff_toInt_le, toInt32, toInt32]
  have := (low a).isLt
  have := (low b).isLt
  generalize (low a).toNat = x at *
  generalize (low b).toNat = y at *
  split <;> split <;> omega

theorem key_eq (a b : BitVec 64) : signedKey a = signedKey b ↔ low a = low b := by
  rw [← BitVec.toNat_inj, key_toNat, key_toNat, ← BitVec.toNat_inj]
  have := (low a).isLt
  have := (low b).isLt
  omega

theorem decide_beq {α : Type} [BEq α] [LawfulBEq α] [DecidableEq α] (a b : α) :
    decide (a = b) = (a == b) := by
  by_cases h : a = b <;> simp [h]

theorem CmpOp.test_eq (operation : CmpOp) (a b : BitVec 64) :
    operation.test a b = operation.holdsU a b := by
  cases operation <;> simp [CmpOp.test, CmpOp.holdsU, BitVec.ult, BitVec.ule, BitVec.lt_def, BitVec.le_def,
    bne, decide_beq]

theorem Word.test_eq (word : Word) (operation : CmpOp) (a b : BitVec 64) :
    word.test operation a b = word.holds operation a b := by
  cases word
  · simp only [Word.test, Word.holds]
    cases operation <;> simp only [CmpOp.test, CmpOp.holds, key_lt, key_le, key_eq]
    · simp [decide_beq]
    · simp [key_eq, bne, decide_beq]
    all_goals simp [BitVec.slt, BitVec.sle]
  · simp only [Word.test, Word.holds, CmpOp.test_eq]

/-! ## Constants -/

theorem absorbed_some {operation : BinOp} {a v : BitVec 64} (found : absorbed operation a = some v) :
    operation.annihilates = true ∧ a = 0 ∧ v = 0 := by
  simp only [absorbed] at found
  split at found
  · rename_i both
    simp only [Bool.and_eq_true, decide_eq_true_eq] at both
    simp only [Option.some.injEq] at found
    exact ⟨both.1, both.2, found.symm⟩
  · simp at found

theorem absorb_right {operation : BinOp} (word : Word) (zero : operation.annihilates = true) (x : BitVec 64) :
    word.apply operation x 0 = 0 := by
  cases word <;> cases operation <;> simp_all [BinOp.annihilates, Word.apply, BinOp.apply]

theorem absorb_left {operation : BinOp} (word : Word) (zero : operation.annihilates = true) (x : BitVec 64) :
    word.apply operation 0 x = 0 := by
  cases word <;> cases operation <;> simp_all [BinOp.annihilates, Word.apply, BinOp.apply]

theorem boolBits_eq (b : Bool) : boolBits b = if b = true then 1 else 0 := by
  cases b <;> rfl

/-- A constant is the expression's value in every environment. -/
theorem Expr.constant_eval (env : Env) : ∀ (e : Expr) {v : BitVec 64}, e.constant = some v → e.eval env = v
  | .lit value, v, found => by simpa [Expr.constant, Expr.eval] using found
  | .var index, v, found => by simp [Expr.constant] at found
  | .neg operand, v, found => by
    simp only [Expr.constant, negateConstant] at found
    split at found
    · rename_i c known
      simp only [Option.some.injEq] at found
      subst found
      simp only [Expr.eval, Expr.constant_eval env operand known, lowBits_eq, low_neg]
    · simp at found
  | .binary word operation left right, v, found => by
    simp only [Expr.constant, binaryConstant] at found
    simp only [Expr.eval]
    split at found
    · rename_i a knownLeft
      rw [Expr.constant_eval env left knownLeft]
      split at found
      · rename_i b knownRight
        simp only [Option.some.injEq] at found
        rw [Expr.constant_eval env right knownRight, ← found, Word.compute_eq]
      · obtain ⟨zero, rfl, rfl⟩ := absorbed_some found
        exact absorb_left word zero _
    · split at found
      · rename_i b knownRight
        rw [Expr.constant_eval env right knownRight]
        obtain ⟨zero, rfl, rfl⟩ := absorbed_some found
        exact absorb_right word zero _
      · simp at found
  | .compare word operation left right, v, found => by
    simp only [Expr.constant, compareConstant] at found
    simp only [Expr.eval]
    split at found
    · rename_i a knownLeft
      split at found
      · rename_i b knownRight
        simp only [Option.some.injEq] at found
        rw [Expr.constant_eval env left knownLeft, Expr.constant_eval env right knownRight, ← found,
          boolBits_eq, Word.test_eq]
      · simp at found
    · simp at found

theorem Expr.isConstant_eval {e : Expr} {known : Option (BitVec 64)} (is : e.isConstant known = true) :
    ∃ v, known = some v ∧ ∀ env, e.eval env = v := by
  cases e with
  | lit literal => ?_
  | _ => simp [Expr.isConstant] at is
  simp only [Expr.isConstant, constantIs] at is
  split at is
  · rename_i v
    simp only [decide_eq_true_eq] at is
    exact ⟨v, rfl, fun _ => by simp [Expr.eval, is]⟩
  · simp at is

theorem Expr.isVar_eq {e : Expr} {index : Nat} (is : e.isVar index = true) : e = .var index := by
  cases e <;> simp_all [Expr.isVar]

theorem Expr.isZero_eval {e : Expr} (zero : e.isZero = true) (env : Env) : e.eval env = 0 := by
  simp only [Expr.isZero, constantIs] at zero
  split at zero
  · rename_i v known
    simp only [decide_eq_true_eq] at zero
    rw [Expr.constant_eval env e known, zero]
  · simp at zero

/-! ## Identities -/

theorem widen_low_widen (x : BitVec 32) : widen (low (widen x)) = widen x := by
  rw [low_widen]

/-- A narrow expression's value is zero-extended. -/
theorem Expr.narrow_eval {e : Expr} (narrow : e.narrow = true) (env : Env) :
    widen (low (e.eval env)) = e.eval env := by
  cases e with
  | lit value =>
    simp only [Expr.narrow, decide_eq_true_eq, BitVec.le_def] at narrow
    apply BitVec.eq_of_toNat_eq
    simp only [Expr.eval, BitVec.toNat_setWidth]
    have : (4294967295 : BitVec 64).toNat = 4294967295 := rfl
    omega
  | var index => simp [Expr.narrow] at narrow
  | neg operand => exact widen_low_widen _
  | binary word operation left right =>
    cases word
    · exact widen_low_widen _
    · simp [Expr.narrow, Word.narrows] at narrow
  | compare word operation left right =>
    simp only [Expr.eval]
    split <;> decide

theorem Word.keeps_eval {word : Word} {e : Expr} (keeps : word.keeps e = true) :
    word = .u64 ∨ ∀ env, widen (low (e.eval env)) = e.eval env := by
  cases word
  · exact .inr (Expr.narrow_eval keeps)
  · exact .inl rfl

theorem low_allOnes : low (18446744073709551615 : BitVec 64) = BitVec.allOnes 32 := by decide

theorem apply32_unit (operation : BinOp) (x : BitVec 32) :
    operation.apply x (low operation.unit) = x := by
  cases operation
  case and =>
    show x &&& low 18446744073709551615 = x
    rw [low_allOnes, BitVec.and_allOnes]
  all_goals simp [BinOp.apply, BinOp.unit]

theorem apply64_unit (operation : BinOp) (x : BitVec 64) : operation.apply x operation.unit = x := by
  cases operation
  case and =>
    show x &&& 18446744073709551615 = x
    rw [show (18446744073709551615 : BitVec 64) = BitVec.allOnes 64 by decide, BitVec.and_allOnes]
  all_goals simp [BinOp.apply, BinOp.unit]

/-- `x op c = x` when `c` is the unit and an S32 operation's `x` is zero-extended. -/
theorem Word.apply_unit {word : Word} {operation : BinOp} {c x : BitVec 64}
    (unit : word.sameOperand c operation.unit = true) (keeps : word = .u64 ∨ widen (low x) = x) :
    word.apply operation x c = x := by
  cases word
  · simp only [Word.sameOperand, decide_eq_true_eq, lowBits_eq] at unit
    simp only [Word.apply, widen_inj unit, apply32_unit]
    rcases keeps with h | h
    · cases h
    · exact h
  · simp only [Word.sameOperand, decide_eq_true_eq] at unit
    simp only [Word.apply, unit, apply64_unit]

theorem Word.apply_comm {operation : BinOp} (commutes : operation.commutes = true) (word : Word) (a b : BitVec 64) :
    word.apply operation a b = word.apply operation b a := by
  cases word <;> cases operation <;>
    simp_all [BinOp.commutes, Word.apply, BinOp.apply, BitVec.add_comm, BitVec.mul_comm, BitVec.and_comm,
      BitVec.or_comm, BitVec.xor_comm]

theorem Expr.unitOf_eval {e : Expr} {word : Word} {operation : BinOp} (unit : e.unitOf word operation = true) :
    ∃ c, word.sameOperand c operation.unit = true ∧ ∀ env, e.eval env = c := by
  simp only [Expr.unitOf] at unit
  split at unit
  · rename_i c known
    exact ⟨c, unit, fun env => Expr.constant_eval env e known⟩
  · simp at unit

theorem Word.number_inj {a b : Word} (same : a.number = b.number) : a = b := by
  cases a <;> cases b <;> simp_all [Word.number]

theorem BinOp.number_inj {a b : BinOp} (same : a.number = b.number) : a = b := by
  cases a <;> cases b <;> simp_all [BinOp.number]

theorem CmpOp.number_inj {a b : CmpOp} (same : a.number = b.number) : a = b := by
  cases a <;> cases b <;> simp_all [CmpOp.number]

theorem MemWidth.bytes_inj {a b : MemWidth} (same : a.bytes = b.bytes) : a = b := by
  cases a <;> cases b <;> simp_all [MemWidth.bytes]

/-! ## Expressions -/

/-- An expression the validator accepts has the original's value in every environment. -/
theorem Expr.agrees_eval : ∀ (a b : Expr), a.agrees b = true → ∀ env, b.eval env = a.eval env := by
  intro a
  induction a with
  | lit value =>
    intro b h env
    unfold Expr.agrees at h
    split at h
    · rename_i folded
      obtain ⟨v, known, values⟩ := Expr.isConstant_eval folded
      rw [values, Expr.constant_eval env _ known]
    · simp at h
  | var index =>
    intro b h env
    unfold Expr.agrees at h
    split at h
    · rename_i folded
      obtain ⟨v, known, values⟩ := Expr.isConstant_eval folded
      rw [values, Expr.constant_eval env _ known]
    · rw [Expr.isVar_eq h]
  | neg operand ih =>
    intro b h env
    unfold Expr.agrees at h
    split at h
    · rename_i folded
      obtain ⟨v, known, values⟩ := Expr.isConstant_eval folded
      rw [values, Expr.constant_eval env _ known]
    · cases b <;> simp only [Bool.false_eq_true] at h
      simp only [Expr.eval, ih _ h env]
  | binary word operation left right ihLeft ihRight =>
    intro b h env
    unfold Expr.agrees at h
    split at h
    · rename_i folded
      obtain ⟨v, known, values⟩ := Expr.isConstant_eval folded
      rw [values, Expr.constant_eval env _ known]
    · simp only [Bool.or_eq_true, Bool.and_eq_true] at h
      rcases h with shape | ⟨⟨⟨unit, keeps⟩, kept⟩⟩ | ⟨⟨⟨commutes, unit⟩, keeps⟩, kept⟩
      · cases b <;> simp only [Bool.false_eq_true, Bool.and_eq_true, decide_eq_true_eq] at shape
        obtain ⟨⟨⟨w, o⟩, l⟩, r⟩ := shape
        cases Word.number_inj w
        cases BinOp.number_inj o
        simp only [Expr.eval, ihLeft _ l env, ihRight _ r env]
      · obtain ⟨c, isUnit, value⟩ := Expr.unitOf_eval unit
        simp only [Expr.eval, value, ihLeft _ kept env]
        rw [Word.apply_unit isUnit]
        rcases Word.keeps_eval keeps with u | n
        · exact .inl u
        · exact .inr (by rw [← ihLeft _ kept env]; exact n env)
      · obtain ⟨c, isUnit, value⟩ := Expr.unitOf_eval unit
        simp only [Expr.eval, value, ihRight _ kept env]
        rw [Word.apply_comm commutes, Word.apply_unit isUnit]
        rcases Word.keeps_eval keeps with u | n
        · exact .inl u
        · exact .inr (by rw [← ihRight _ kept env]; exact n env)
  | compare word operation left right ihLeft ihRight =>
    intro b h env
    unfold Expr.agrees at h
    split at h
    · rename_i folded
      obtain ⟨v, known, values⟩ := Expr.isConstant_eval folded
      rw [values, Expr.constant_eval env _ known]
    · cases b <;> simp only [Bool.false_eq_true, Bool.and_eq_true, decide_eq_true_eq] at h
      obtain ⟨⟨⟨w, o⟩, l⟩, r⟩ := h
      cases Word.number_inj w
      cases CmpOp.number_inj o
      simp only [Expr.eval, ihLeft _ l env, ihRight _ r env]

theorem argsAgree_eval : ∀ {args others : List Expr}, argsAgree args others = true →
    ∀ env, Expr.evalAll env others = Expr.evalAll env args ∧ others.length = args.length
  | [], [], _, _ => ⟨rfl, rfl⟩
  | [], _ :: _, h, _ => by simp [argsAgree] at h
  | _ :: _, [], h, _ => by simp [argsAgree] at h
  | arg :: rest, other :: more, h, env => by
    simp only [argsAgree, Bool.and_eq_true] at h
    have := argsAgree_eval h.2 env
    simp [Expr.evalAll, Expr.agrees_eval _ _ h.1 env, this.1, this.2]

/-! ## Statements: what an accepted statement looks like -/

theorem Stmt.isSkip_eq {s : Stmt} (is : s.isSkip = true) : s = .skip := by
  cases s <;> simp_all [Stmt.isSkip]

theorem assignAgrees_cases {index : Nat} {value : Expr} {other : Stmt} (h : assignAgrees index value other = true) :
    (other = .skip ∧ value.agrees (.var index) = true) ∨ ∃ v, other = .assign index v ∧ value.agrees v = true := by
  cases other <;> simp_all [assignAgrees]

theorem callAgrees_cases {target count callee : Nat} {args : List Expr} {other : Stmt}
    (h : callAgrees target count callee args other = true) :
    ∃ others, other = .call target count callee others ∧ argsAgree args others = true := by
  cases other <;> simp_all [callAgrees]

theorem retAgrees_cases {values : List Expr} {other : Stmt} (h : retAgrees values other = true) :
    ∃ others, other = .ret others ∧ argsAgree values others = true := by
  cases other <;> simp_all [retAgrees]

theorem allocAgrees_cases {target shift : Nat} {size : Expr} {other : Stmt}
    (h : allocAgrees target shift size other = true) :
    ∃ size', other = .alloc target shift size' ∧ size.agrees size' = true := by
  cases other <;> simp_all [allocAgrees]

theorem loadByteAgrees_cases {target : Nat} {address : Expr} {other : Stmt}
    (h : loadByteAgrees target address other = true) :
    ∃ address', other = .loadByte target address' ∧ address.agrees address' = true := by
  cases other <;> simp_all [loadByteAgrees]

theorem storeByteAgrees_cases {address value : Expr} {other : Stmt} (h : storeByteAgrees address value other = true) :
    ∃ address' value', other = .storeByte address' value' ∧ address.agrees address' = true ∧
      value.agrees value' = true := by
  cases other <;> simp_all [storeByteAgrees, and_assoc]

theorem loadWordAgrees_cases {width : MemWidth} {target : Nat} {address : Expr} {other : Stmt}
    (h : loadWordAgrees width target address other = true) :
    ∃ address', other = .loadWord width target address' ∧ address.agrees address' = true := by
  cases other <;> simp only [loadWordAgrees, Bool.false_eq_true, Bool.and_eq_true, decide_eq_true_eq] at h
  obtain ⟨⟨w, rfl⟩, a⟩ := h
  cases MemWidth.bytes_inj w
  exact ⟨_, rfl, a⟩

theorem storeWordAgrees_cases {width : MemWidth} {address value : Expr} {other : Stmt}
    (h : storeWordAgrees width address value other = true) :
    ∃ address' value', other = .storeWord width address' value' ∧ address.agrees address' = true ∧
      value.agrees value' = true := by
  cases other <;> simp only [storeWordAgrees, Bool.false_eq_true, Bool.and_eq_true, decide_eq_true_eq] at h
  obtain ⟨⟨w, a⟩, v⟩ := h
  cases MemWidth.bytes_inj w
  exact ⟨_, _, rfl, a, v⟩

theorem seqAgrees_cases {first second other : Stmt} (h : (Stmt.seq first second).agrees other = true) :
    (first.agrees .skip = true ∧ second.agrees other = true) ∨
      (second.agrees .skip = true ∧ first.agrees other = true) ∨
      ∃ f s, other = .seq f s ∧ first.agrees f = true ∧ second.agrees s = true := by
  simp only [Stmt.agrees, Bool.or_eq_true, Bool.and_eq_true] at h
  rcases h with (h | h) | h
  · exact .inl h
  · exact .inr (.inl h)
  · right; right
    cases other <;> simp_all [and_assoc]

theorem iteAgrees_cases {condition : Expr} {thenBranch elseBranch other : Stmt}
    (h : (Stmt.ite condition thenBranch elseBranch).agrees other = true) :
    (thenBranch.agrees other = true ∧ elseBranch.agrees other = true) ∨
      (∃ v, condition.constant = some v ∧
        ((v = 0 ∧ elseBranch.agrees other = true) ∨ (v ≠ 0 ∧ thenBranch.agrees other = true))) ∨
      ∃ c t e, other = .ite c t e ∧ condition.agrees c = true ∧ thenBranch.agrees t = true ∧
        elseBranch.agrees e = true := by
  simp only [Stmt.agrees, Bool.or_eq_true, Bool.and_eq_true] at h
  rcases h with (h | h) | h
  · exact .inl h
  · right; left
    split at h
    · rename_i v known
      simp only [Bool.or_eq_true, Bool.and_eq_true, decide_eq_true_eq] at h
      exact ⟨v, known, h⟩
    · simp at h
  · right; right
    cases other <;> simp_all [and_assoc]

theorem loopAgrees_cases {condition : Expr} {body other : Stmt}
    (h : (Stmt.loop condition body).agrees other = true) :
    (condition.isZero = true ∧ other = .skip) ∨
      ∃ c b, other = .loop c b ∧ condition.agrees c = true ∧ body.agrees b = true := by
  simp only [Stmt.agrees, Bool.or_eq_true, Bool.and_eq_true] at h
  rcases h with ⟨zero, skip⟩ | h
  · exact .inl ⟨zero, Stmt.isSkip_eq skip⟩
  · right
    cases other <;> simp_all [and_assoc]

theorem Func.agrees_parts {func other : Func} (h : func.agrees other = true) :
    other.params = func.params ∧ other.results = func.results ∧ other.locals = func.locals ∧
      func.body.agrees other.body = true := by
  simp only [Func.agrees, Bool.and_eq_true, decide_eq_true_eq] at h
  exact ⟨h.1.1.1.symm, h.1.1.2.symm, h.1.2.symm, h.2⟩

theorem funcsAgree_get : ∀ {funcs others : List Func}, funcsAgree funcs others = true →
    ∀ {callee : Nat} {func : Func}, funcs[callee]? = some func →
      ∃ other, others[callee]? = some other ∧ func.agrees other = true
  | [], _, _, _, _, found => by simp at found
  | _ :: _, [], h, _, _, _ => by simp [funcsAgree] at h
  | first :: rest, other :: more, h, callee, func, found => by
    simp only [funcsAgree, Bool.and_eq_true] at h
    cases callee with
    | zero =>
      simp only [List.getElem?_cons_zero, Option.some.injEq] at found ⊢
      subst found
      exact ⟨other, rfl, h.1⟩
    | succ callee =>
      simp only [List.getElem?_cons_succ] at found ⊢
      exact funcsAgree_get h.2 found

theorem Exec.skip_inv {prog : Program} {depth : Nat} {env : Env} {heap : Heap} {outcome : Outcome}
    (run : Exec prog depth env heap .skip outcome) : outcome = .normal env heap := by
  cases run; rfl

/-! ## The simulation -/

/-- Every run of an original statement is a run of the statement the validator
accepted, in the optimized program, with the same outcome. -/
theorem Exec.agrees {p q : Program} (ok : funcsAgree p.funcs q.funcs = true) {depth : Nat} {env : Env}
    {heap : Heap} {s : Stmt} {outcome : Outcome} (run : Exec p depth env heap s outcome) :
    ∀ s', s.agrees s' = true → Exec q depth env heap s' outcome := by
  induction run with
  | skip =>
    intro s' h
    rw [Stmt.isSkip_eq h]
    exact .skip
  | @assign depth env heap index value =>
    intro s' h
    rcases assignAgrees_cases h with ⟨rfl, same⟩ | ⟨v, rfl, same⟩
    · have read := Expr.agrees_eval _ _ same env
      simp only [Expr.eval] at read
      have : env.set index (value.eval env) = env := by
        funext k
        simp only [Env.set]
        split
        · subst k; exact read.symm
        · rfl
      rw [this]
      exact .skip
    · rw [← Expr.agrees_eval _ _ same env]
      exact .assign
  | seq _ _ ih1 ih2 =>
    intro s' h
    rcases seqAgrees_cases h with ⟨skip, rest⟩ | ⟨skip, kept⟩ | ⟨f, g, rfl, hf, hg⟩
    · cases Exec.skip_inv (ih1 _ skip)
      exact ih2 _ rest
    · have := Exec.skip_inv (ih2 _ skip)
      subst this
      exact ih1 _ kept
    · exact .seq (ih1 _ hf) (ih2 _ hg)
  | seqReturned _ ih =>
    intro s' h
    rcases seqAgrees_cases h with ⟨skip, _⟩ | ⟨_, kept⟩ | ⟨f, g, rfl, hf, _⟩
    · cases Exec.skip_inv (ih _ skip)
    · exact ih _ kept
    · exact .seqReturned (ih _ hf)
  | @ifTrue depth env heap condition _ _ _ holds _ ih =>
    intro s' h
    rcases iteAgrees_cases h with ⟨both, _⟩ | ⟨v, known, ⟨zero, _⟩ | ⟨_, chosen⟩⟩ | ⟨c, t, e, rfl, hc, ht, _⟩
    · exact ih _ both
    · exact absurd (by rw [Expr.constant_eval env _ known, zero]) holds
    · exact ih _ chosen
    · exact .ifTrue (by rw [Expr.agrees_eval _ _ hc env]; exact holds) (ih _ ht)
  | @ifFalse depth env heap condition _ _ _ holds _ ih =>
    intro s' h
    rcases iteAgrees_cases h with ⟨_, both⟩ | ⟨v, known, ⟨_, chosen⟩ | ⟨nonzero, _⟩⟩ | ⟨c, t, e, rfl, hc, _, he⟩
    · exact ih _ both
    · exact ih _ chosen
    · exact absurd (by rw [← Expr.constant_eval env _ known, holds]) nonzero
    · exact .ifFalse (by rw [Expr.agrees_eval _ _ hc env]; exact holds) (ih _ he)
  | @loopDone depth env heap condition body holds =>
    intro s' h
    rcases loopAgrees_cases h with ⟨_, rfl⟩ | ⟨c, b, rfl, hc, _⟩
    · exact .skip
    · exact .loopDone (by rw [Expr.agrees_eval _ _ hc env]; exact holds)
  | @loopNext depth env middle heap between condition body outcome holds _ _ ihBody ihLoop =>
    intro s' h
    rcases loopAgrees_cases h with ⟨zero, rfl⟩ | ⟨c, b, rfl, hc, hb⟩
    · exact absurd (Expr.isZero_eval zero env) holds
    · exact .loopNext (by rw [Expr.agrees_eval _ _ hc env]; exact holds) (ihBody _ hb) (ihLoop _ h)
  | @loopReturned depth env heap after condition body value holds _ ih =>
    intro s' h
    rcases loopAgrees_cases h with ⟨zero, rfl⟩ | ⟨c, b, rfl, hc, hb⟩
    · exact absurd (Expr.isZero_eval zero env) holds
    · exact .loopReturned (by rw [Expr.agrees_eval _ _ hc env]; exact holds) (ih _ hb)
  | @call depth inner target count callee env heap after args func value found len vlen lt _ ih =>
    intro s' h
    obtain ⟨others, rfl, same⟩ := callAgrees_cases h
    obtain ⟨other, found', agrees⟩ := funcsAgree_get ok found
    obtain ⟨params, _, _, body⟩ := Func.agrees_parts agrees
    have values := argsAgree_eval same env
    refine .call found' (by rw [values.2, len, params]) vlen lt ?_
    rw [values.1]
    exact ih _ body
  | @ret depth env heap values =>
    intro s' h
    obtain ⟨others, rfl, same⟩ := retAgrees_cases h
    rw [← (argsAgree_eval same env).1]
    exact .ret
  | @alloc depth env heap target shift size fits =>
    intro s' h
    obtain ⟨size', rfl, same⟩ := allocAgrees_cases h
    have := Expr.agrees_eval _ _ same env
    rw [← this] at fits ⊢
    exact .alloc fits
  | @loadByte depth env heap target address below =>
    intro s' h
    obtain ⟨address', rfl, same⟩ := loadByteAgrees_cases h
    have := Expr.agrees_eval _ _ same env
    rw [← this] at below ⊢
    exact .loadByte below
  | @storeByte depth env heap address value below =>
    intro s' h
    obtain ⟨address', value', rfl, sameAddress, sameValue⟩ := storeByteAgrees_cases h
    have a := Expr.agrees_eval _ _ sameAddress env
    have v := Expr.agrees_eval _ _ sameValue env
    rw [← a] at below
    rw [← a, ← v]
    exact .storeByte below
  | @loadWord depth env heap width target address below =>
    intro s' h
    obtain ⟨address', rfl, same⟩ := loadWordAgrees_cases h
    have := Expr.agrees_eval _ _ same env
    rw [← this] at below ⊢
    exact .loadWord below
  | @storeWord depth env heap width address value below =>
    intro s' h
    obtain ⟨address', value', rfl, sameAddress, sameValue⟩ := storeWordAgrees_cases h
    have a := Expr.agrees_eval _ _ sameAddress env
    have v := Expr.agrees_eval _ _ sameValue env
    rw [← a] at below
    rw [← a, ← v]
    exact .storeWord below

/-- The validator's guarantee: a call that returns in the original program
returns the same values and heap in the optimized one, at the same depth. -/
theorem Program.Returns.validated {p q : Program} (ok : validate p q = true) {depth f : Nat}
    {args value : List (BitVec 64)} {heap after : Heap} (returns : p.Returns depth f args heap value after) :
    q.Returns depth f args heap value after := by
  obtain ⟨func, found, len, run⟩ := returns
  obtain ⟨other, found', agrees⟩ := funcsAgree_get ok found
  obtain ⟨params, _, _, body⟩ := Func.agrees_parts agrees
  exact ⟨other, found', by rw [params]; exact len, Exec.agrees ok run _ body⟩

/-! ## The pipeline -/

/-- `compileOptimized` compiles the original program, or a program the
validator accepted. -/
theorem compileOptimized_some {prog : Program} {binary : Binary} (compiled : compileOptimized prog = some binary) :
    compileProgram prog = some binary ∨ ∃ q, validate prog q = true ∧ compileProgram q = some binary := by
  unfold compileOptimized at compiled
  dsimp only at compiled
  split at compiled
  · rename_i accepted
    unfold compileOr at compiled
    split at compiled
    · rename_i b optimizedCompiled
      simp only [Option.some.injEq] at compiled
      subst compiled
      exact .inr ⟨_, accepted, optimizedCompiled⟩
    · exact .inl compiled
  · exact .inl compiled

/-- `compileProgram_correct` for the optimizing pipeline, with the same premises. -/
theorem compileOptimized_correct {prog : Program} {binary : Binary} (compiled : compileOptimized prog = some binary)
    {depth f : Nat} {args value : List (BitVec 64)} {heap after : Heap}
    (returns : prog.Returns depth f args heap value after)
    (s : State) (imageBase : BitVec 64) (window : Nat)
    (enough : binary.stackNeed depth ≤ window) (bounded : window ≤ 2 ^ 62)
    (loaded : CodeAt s.memory imageBase binary.image)
    (apart : ∀ index, index < binary.image.length →
      ¬Below (s.registers rspRegister) window (imageBase + BitVec.ofNat 64 index))
    (imageHeap : ∀ index, index < binary.image.length → ¬s.InHeap (imageBase + BitVec.ofNat 64 index))
    (entry : s.rip = imageBase + BitVec.ofNat 64 (binary.entries.getD f 0))
    (params : ∀ k (bound : k < args.length),
      read64 s.memory (s.registers rspRegister - BitVec.ofNat 64 (8 * k + 16)) = args[k])
    (heapAt : HeapAt window s heap) :
    ∃ n s', Steps n s s' ∧ Returned window s s' value after := by
  rcases compileOptimized_some compiled with original | ⟨q, accepted, optimized⟩
  · exact compileProgram_correct original returns s imageBase window enough bounded loaded apart imageHeap entry
      params heapAt
  · exact compileProgram_correct optimized (returns.validated accepted) s imageBase window enough bounded loaded
      apart imageHeap entry params heapAt

end Lanius.Mini
