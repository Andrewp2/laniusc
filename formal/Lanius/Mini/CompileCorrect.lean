import Lanius.Mini.Asm

/-! The compiler against the abstract machine: induction on expression syntax
and on the statement derivation, with one invariant — slots below `base` hold
the source locals. Calls are taken on trust from the source semantics of the
callee; the x86 proof discharges them by induction on call depth. -/

namespace Lanius.Mini

/-- Slots below `base` hold the source environment. -/
def Agree (base : Nat) (env : Env) (m : Machine) : Prop := ∀ index, index < base → m.slots index = env index

/-- What a call may return in a derivation of depth `depth`. -/
def SourceCalls (prog : Program) (depth : Nat) : Calls :=
  fun callee args value => ∃ inner, inner < depth ∧ prog.Returns inner callee args value

theorem Instr.exec_singleton (i : Instr) (m : Machine) : Instr.exec [i] m = i.step m := rfl

theorem Agree.of_slots (agree : Agree base env m) (same : ∀ slot, slot < base → m'.slots slot = m.slots slot) :
    Agree base env m' := fun index below => (same index below).trans (agree index below)

theorem compileExpr_straight (base : Nat) (e : Expr) (depth : Nat) :
    (compileExpr base e depth).all Instr.straight = true := by
  induction e generalizing depth with
  | lit | var => rfl
  | neg operand ih => simp only [compileExpr, List.all_append, ih]; rfl
  | binary _ left right ihLeft ihRight =>
    simp only [compileExpr, List.all_append, ihLeft, ihRight]; rfl
  | compare _ left right ihLeft ihRight =>
    simp only [compileExpr, List.all_append, ihLeft, ihRight]; rfl

/-- The shared shape of binary operators and comparisons: after the operands'
code, the left value waits in slot `base + depth` and the right is in the accumulator. -/
theorem operands_correct (base depth : Nat) (env : Env) (m : Machine) (agree : Agree base env m)
    (leftCode rightCode : List Instr) (leftValue rightValue : BitVec 32)
    (left : ∀ m, Agree base env m → (Instr.exec leftCode m).acc = leftValue ∧
      ∀ slot, slot < base + depth → (Instr.exec leftCode m).slots slot = m.slots slot)
    (right : ∀ m, Agree base env m → (Instr.exec rightCode m).acc = rightValue ∧
      ∀ slot, slot < base + (depth + 1) → (Instr.exec rightCode m).slots slot = m.slots slot) :
    let after := Instr.exec (leftCode ++ [.store (base + depth)] ++ rightCode) m
    after.slots (base + depth) = leftValue ∧ after.acc = rightValue ∧
      ∀ slot, slot < base + depth → after.slots slot = m.slots slot := by
  obtain ⟨leftAcc, leftSlots⟩ := left m agree
  simp only [Instr.exec_append, Instr.exec_singleton]
  generalize storedEq : (Instr.store (base + depth)).step (Instr.exec leftCode m) = stored
  have storedSlots : ∀ slot, stored.slots slot =
      if slot = base + depth then leftValue else (Instr.exec leftCode m).slots slot := by
    intro slot
    rw [← storedEq]
    simp [Instr.step, Instr.update, Machine.store, leftAcc]
  have storedAgree : Agree base env stored := by
    intro index below
    rw [storedSlots, if_neg (by omega), leftSlots index (by omega)]
    exact agree index below
  obtain ⟨rightAcc, rightSlots⟩ := right stored storedAgree
  refine ⟨?_, rightAcc, ?_⟩
  · rw [rightSlots _ (by omega), storedSlots, if_pos rfl]
  · intro slot below
    rw [rightSlots slot (by omega), storedSlots, if_neg (by omega)]
    exact leftSlots slot below

theorem compileExpr_correct (base : Nat) (e : Expr) (depth : Nat) (env : Env) (m : Machine)
    (agree : Agree base env m) (within : e.within base = true) :
    (Instr.exec (compileExpr base e depth) m).acc = e.eval env ∧
      ∀ slot, slot < base + depth → (Instr.exec (compileExpr base e depth) m).slots slot = m.slots slot := by
  induction e generalizing depth m with
  | lit value => simp [compileExpr, Instr.exec, Instr.step, Instr.update, Expr.eval]
  | var index =>
    simp only [Expr.within, decide_eq_true_eq] at within
    simp [compileExpr, Instr.exec, Instr.step, Instr.update, Expr.eval, agree index within]
  | neg operand ih =>
    obtain ⟨acc, slots⟩ := ih depth m agree within
    simp only [compileExpr, Instr.exec_append, Instr.exec_singleton]
    exact ⟨by simp [Instr.step, Instr.update, Expr.eval, acc], slots⟩
  | binary operation left right ihLeft ihRight =>
    simp only [Expr.within, Bool.and_eq_true] at within
    obtain ⟨kept, acc, slots⟩ := operands_correct base depth env m agree _ _ _ _
      (fun m agree => ihLeft depth m agree within.1) (fun m agree => ihRight (depth + 1) m agree within.2)
    simp only [compileExpr, Instr.exec_append (_ ++ _ ++ _), Instr.exec_singleton]
    exact ⟨by simp only [Instr.step, Instr.update, Expr.eval]; rw [kept, acc], slots⟩
  | compare operation left right ihLeft ihRight =>
    simp only [Expr.within, Bool.and_eq_true] at within
    obtain ⟨kept, acc, slots⟩ := operands_correct base depth env m agree _ _ _ _
      (fun m agree => ihLeft depth m agree within.1) (fun m agree => ihRight (depth + 1) m agree within.2)
    simp only [compileExpr, Instr.exec_append (_ ++ _ ++ _), Instr.exec_singleton]
    exact ⟨by simp only [Instr.step, Instr.update, Expr.eval]; rw [kept, acc], slots⟩

theorem compileArgs_straight (base : Nat) (args : List Expr) (k : Nat) :
    (compileArgs base args k).all Instr.straight = true := by
  induction args generalizing k with
  | nil => rfl
  | cons arg rest ih =>
    simp only [compileArgs, List.all_append, compileExpr_straight, ih]
    rfl

/-- Argument `k` ends in slot `base + k`, and the slots below `base + k` are kept. -/
theorem compileArgs_correct (base : Nat) (args : List Expr) (k : Nat) (env : Env) (m : Machine)
    (agree : Agree base env m) (within : allWithin base args = true) :
    readSlots (Instr.exec (compileArgs base args k) m).slots (argSlots base args k) = Expr.evalAll env args ∧
      ∀ slot, slot < base + k → (Instr.exec (compileArgs base args k) m).slots slot = m.slots slot := by
  induction args generalizing k m with
  | nil => exact ⟨rfl, fun _ _ => rfl⟩
  | cons arg rest ih =>
    simp only [allWithin, Bool.and_eq_true] at within
    obtain ⟨acc, kept⟩ := compileExpr_correct base arg (k + 1) env m agree within.1
    simp only [compileArgs, Instr.exec_append, Instr.exec_singleton]
    generalize storedEq : (Instr.store (base + k)).step (Instr.exec (compileExpr base arg (k + 1)) m) = stored
    have storedSlots : ∀ slot, stored.slots slot =
        if slot = base + k then arg.eval env else (Instr.exec (compileExpr base arg (k + 1)) m).slots slot := by
      intro slot
      rw [← storedEq]
      simp [Instr.step, Instr.update, Machine.store, acc]
    have storedAgree : Agree base env stored := by
      intro index below
      rw [storedSlots, if_neg (by omega), kept index (by omega)]
      exact agree index below
    obtain ⟨restArgs, restKept⟩ := ih (k + 1) stored storedAgree within.2
    refine ⟨?_, ?_⟩
    · simp only [argSlots, readSlots, Expr.evalAll, restArgs, restKept (base + k) (by omega),
        storedSlots, ite_true]
    · intro slot below
      rw [restKept slot (by omega), storedSlots, if_neg (by omega), kept slot (by omega)]

theorem argSlots_length (base : Nat) (args : List Expr) (k : Nat) :
    (argSlots base args k).length = args.length := by
  induction args generalizing k <;> simp_all [argSlots]

theorem evalAll_length (env : Env) (args : List Expr) : (Expr.evalAll env args).length = args.length := by
  induction args <;> simp_all [Expr.evalAll]

/-- What running a placed statement's code achieves, given the source outcome. -/
def StmtResult (calls : Calls) (code : List Instr) (base pos : Nat) (block : List Instr) (m : Machine) :
    Outcome → Prop
  | .normal env => ∃ m', Star calls code m m' ∧ m'.pc = pos + codeSize block ∧ Agree base env m'
  | .returned value => ∃ m', Star calls code m m' ∧ fetch code m'.pc = some .ret ∧ m'.acc = value

/-- A placed straight-line block, then the rest of a statement's run. -/
theorem StmtResult.prefix {calls : Calls} {code block : List Instr} {m : Machine}
    (placed : Block code m.pc block) (allStraight : block.all Instr.straight = true)
    (rest : StmtResult calls code base pos whole (Instr.exec block m) outcome) :
    StmtResult calls code base pos whole m outcome := by
  have run := Star.straight (calls := calls) block placed allStraight
  cases outcome with
  | normal env =>
    obtain ⟨m', steps, pc, agree⟩ := rest
    exact ⟨m', run.trans steps, pc, agree⟩
  | returned value =>
    obtain ⟨m', steps, fetched, acc⟩ := rest
    exact ⟨m', run.trans steps, fetched, acc⟩

theorem StmtResult.step {calls : Calls} {code : List Instr} {m next : Machine}
    (step : Step calls code m next) (rest : StmtResult calls code base pos whole next outcome) :
    StmtResult calls code base pos whole m outcome := by
  cases outcome with
  | normal env =>
    obtain ⟨m', steps, pc, agree⟩ := rest
    exact ⟨m', .step step steps, pc, agree⟩
  | returned value =>
    obtain ⟨m', steps, fetched, acc⟩ := rest
    exact ⟨m', .step step steps, fetched, acc⟩

/-- A statement's result through a sub-block, with the end of the block moved. -/
theorem StmtResult.retarget {calls : Calls} {code : List Instr} {m : Machine}
    (inner : StmtResult calls code base innerPos innerBlock m outcome)
    (normalEnd : ∀ env m', Star calls code m m' → m'.pc = innerPos + codeSize innerBlock →
      Agree base env m' → StmtResult calls code base pos whole m (.normal env)) :
    StmtResult calls code base pos whole m outcome := by
  cases outcome with
  | normal env =>
    obtain ⟨m', steps, pc, agree⟩ := inner
    exact normalEnd env m' steps pc agree
  | returned value => exact inner

theorem StmtResult.star {calls : Calls} {code : List Instr} {m next : Machine}
    (run : Star calls code m next) (rest : StmtResult calls code base pos whole next outcome) :
    StmtResult calls code base pos whole m outcome := by
  cases outcome with
  | normal env =>
    obtain ⟨m', steps, pc, agree⟩ := rest
    exact ⟨m', run.trans steps, pc, agree⟩
  | returned value =>
    obtain ⟨m', steps, fetched, acc⟩ := rest
    exact ⟨m', run.trans steps, fetched, acc⟩

/-- A sub-block that ends normally, then the rest of the statement. -/
theorem StmtResult.andThen {calls : Calls} {code : List Instr} {m : Machine}
    (first : StmtResult calls code base innerPos innerBlock m (.normal middle))
    (rest : ∀ m', Star calls code m m' → m'.pc = innerPos + codeSize innerBlock → Agree base middle m' →
      StmtResult calls code base pos whole m outcome) :
    StmtResult calls code base pos whole m outcome := by
  obtain ⟨m', steps, pc, agree⟩ := first
  exact rest m' steps pc agree

theorem Block.at (placed : Block code pos block) (same : pos = pos') : Block code pos' block :=
  same ▸ placed

/-- The two-instruction block of a call: the call, then the store of its result. -/
theorem Block.pair (placed : Block code pos [first, second]) :
    Block code pos [first] ∧ Block code (pos + first.size) [second] := by
  have split : Block code pos ([first] ++ [second]) := placed
  exact ⟨split.left, by simpa [codeSize] using split.right⟩

theorem compileStmt_correct {prog : Program} {base : Nat} {arities : List Nat} {code : List Instr}
    {depth : Nat} {env : Env} {stmt : Stmt} {outcome : Outcome}
    (exec : Exec prog depth env stmt outcome) :
    ∀ pos m, Block code pos (compileStmt base pos stmt) → m.pc = pos → Agree base env m →
      stmt.within base arities = true →
      StmtResult (SourceCalls prog depth) code base pos (compileStmt base pos stmt) m outcome := by
  induction exec with
  | skip =>
    intro pos m _ pc agree _
    exact ⟨m, .refl _, by simp [compileStmt, codeSize, pc], agree⟩
  | @assign depth env index value =>
    intro pos m placed pc agree within
    simp only [Stmt.within, Bool.and_eq_true, decide_eq_true_eq] at within
    have allStraight : (compileStmt base pos (.assign index value)).all Instr.straight = true := by
      simp only [compileStmt, List.all_append, compileExpr_straight]; rfl
    obtain ⟨acc, kept⟩ := compileExpr_correct base value 0 env m agree within.2
    refine ⟨_, Star.straight _ (pc ▸ placed) allStraight, by rw [Instr.exec_pc, pc], ?_⟩
    intro other below
    simp only [compileStmt, Instr.exec_append, Instr.exec_singleton, Instr.step, Instr.update,
      Machine.store, Env.set, acc]
    split
    · rfl
    · rw [kept other (by omega)]
      exact agree other below
  | @seq depth env middle first second outcome _ _ ihFirst ihSecond =>
    intro pos m placed pc agree within
    simp only [Stmt.within, Bool.and_eq_true] at within
    simp only [compileStmt] at placed ⊢
    obtain ⟨m', steps, pc', agree'⟩ := ihFirst pos m placed.left pc agree within.1
    have secondRun := ihSecond _ m' placed.right pc' agree' within.2
    have run : StmtResult _ code base pos (compileStmt base pos first ++
        compileStmt base (pos + codeSize (compileStmt base pos first)) second) m' outcome :=
      secondRun.retarget fun env m'' steps' pc'' agree'' =>
      ⟨m'', steps', by rw [pc'', codeSize_append]; omega, agree''⟩
    cases outcome with
    | normal env =>
      obtain ⟨m'', steps', pc'', agree''⟩ := run
      exact ⟨m'', steps.trans steps', pc'', agree''⟩
    | returned value =>
      obtain ⟨m'', steps', fetched, acc⟩ := run
      exact ⟨m'', steps.trans steps', fetched, acc⟩
  | @seqReturned depth env first second value _ ihFirst =>
    intro pos m placed pc agree within
    simp only [Stmt.within, Bool.and_eq_true] at within
    simp only [compileStmt] at placed ⊢
    exact ihFirst pos m placed.left pc agree within.1
  | @ifTrue depth env condition thenBranch elseBranch outcome nonzero _ ihThen =>
    intro pos m placed pc agree within
    simp only [Stmt.within, Bool.and_eq_true] at within
    simp only [compileStmt] at placed ⊢
    obtain ⟨acc, kept⟩ := compileExpr_correct base condition 0 env m agree within.1.1
    apply StmtResult.prefix (pc ▸ placed.left.left.left.left) (compileExpr_straight _ _ _)
    have jz := placed.left.left.left.right.fetch
    apply StmtResult.step (.jzNot (by rw [Instr.exec_pc, pc]; exact jz) (by rw [acc]; exact nonzero))
    refine StmtResult.retarget (ihThen (pos + codeSize (compileExpr base condition 0) + 8) _ ?_ ?_ ?_
      within.1.2) ?_
    · exact placed.left.left.right.at (by simp only [codeSize_append, codeSize, Instr.size]; omega)
    · simp only [Instr.exec_pc, pc, Instr.size]
    · exact agree.of_slots fun slot below => kept slot (by omega)
    intro env' m' steps pc' agree'
    refine ⟨_, steps.trans (.single (.jmp (placed.left.right.at (by
      rw [pc']; simp only [codeSize_append, codeSize, Instr.size]; omega)).fetch)),
      by simp only [codeSize_append, codeSize, Instr.size]; omega, agree'⟩
  | @ifFalse depth env condition thenBranch elseBranch outcome zero _ ihElse =>
    intro pos m placed pc agree within
    simp only [Stmt.within, Bool.and_eq_true] at within
    simp only [compileStmt] at placed ⊢
    obtain ⟨acc, kept⟩ := compileExpr_correct base condition 0 env m agree within.1.1
    apply StmtResult.prefix (pc ▸ placed.left.left.left.left) (compileExpr_straight _ _ _)
    have jz := placed.left.left.left.right.fetch
    apply StmtResult.step (.jzTaken (by rw [Instr.exec_pc, pc]; exact jz) (by rw [acc]; exact zero))
    refine StmtResult.retarget (ihElse (pos + codeSize (compileExpr base condition 0) + 8 +
      codeSize (compileStmt base (pos + codeSize (compileExpr base condition 0) + 8) thenBranch) + 5)
      _ ?_ rfl ?_ within.2) ?_
    · exact placed.right.at (by simp only [codeSize_append, codeSize, Instr.size]; omega)
    · exact agree.of_slots fun slot below => kept slot (by omega)
    intro env' m' steps pc' agree'
    exact ⟨m', steps, by rw [pc']; simp only [codeSize_append, codeSize, Instr.size]; omega, agree'⟩
  | @loopDone depth env condition body zero =>
    intro pos m placed pc agree within
    simp only [Stmt.within, Bool.and_eq_true] at within
    simp only [compileStmt] at placed ⊢
    obtain ⟨acc, kept⟩ := compileExpr_correct base condition 0 env m agree within.1
    apply StmtResult.prefix (pc ▸ placed.left.left.left) (compileExpr_straight _ _ _)
    have jz := placed.left.left.right.fetch
    apply StmtResult.step (.jzTaken (by rw [Instr.exec_pc, pc]; exact jz) (by rw [acc]; exact zero))
    exact ⟨_, .refl _, by simp only [codeSize_append, codeSize, Instr.size]; omega,
      agree.of_slots fun slot below => kept slot (by omega)⟩
  | @loopNext depth env middle condition body outcome nonzero _ _ ihBody ihLoop =>
    intro pos m placed pc agree within
    have loopWithin := within
    simp only [Stmt.within, Bool.and_eq_true] at within
    have placedLoop := placed
    simp only [compileStmt] at placed ⊢
    obtain ⟨acc, kept⟩ := compileExpr_correct base condition 0 env m agree within.1
    apply StmtResult.prefix (pc ▸ placed.left.left.left) (compileExpr_straight _ _ _)
    have jz := placed.left.left.right.fetch
    apply StmtResult.step (.jzNot (by rw [Instr.exec_pc, pc]; exact jz) (by rw [acc]; exact nonzero))
    refine StmtResult.andThen (ihBody (pos + codeSize (compileExpr base condition 0) + 8) _ ?_ ?_ ?_
      within.2) ?_
    · exact placed.left.right.at (by simp only [codeSize_append, codeSize, Instr.size]; omega)
    · simp only [Instr.exec_pc, pc, Instr.size]
    · exact agree.of_slots fun slot below => kept slot (by omega)
    intro m' steps pc' agree'
    have jumped : Star (SourceCalls prog depth) code m' { m' with pc := pos } :=
      .single (.jmp (placed.right.at (by
        rw [pc']; simp only [codeSize_append, codeSize, Instr.size]; omega)).fetch)
    have again := ihLoop pos { m' with pc := pos } placedLoop rfl agree' loopWithin
    simp only [compileStmt] at again
    exact StmtResult.star (steps.trans jumped) again
  | @loopReturned depth env condition body value nonzero _ ihBody =>
    intro pos m placed pc agree within
    simp only [Stmt.within, Bool.and_eq_true] at within
    simp only [compileStmt] at placed ⊢
    obtain ⟨acc, kept⟩ := compileExpr_correct base condition 0 env m agree within.1
    apply StmtResult.prefix (pc ▸ placed.left.left.left) (compileExpr_straight _ _ _)
    have jz := placed.left.left.right.fetch
    apply StmtResult.step (.jzNot (by rw [Instr.exec_pc, pc]; exact jz) (by rw [acc]; exact nonzero))
    refine ihBody (pos + codeSize (compileExpr base condition 0) + 8) _ ?_ ?_ ?_ within.2
    · exact placed.left.right.at (by simp only [codeSize_append, codeSize, Instr.size]; omega)
    · simp only [Instr.exec_pc, pc, Instr.size]
    · exact agree.of_slots fun slot below => kept slot (by omega)
  | @call depth inner target callee env args func value lookup length lower calleeExec _ =>
    intro pos m placed pc agree within
    simp only [Stmt.within, Bool.and_eq_true, decide_eq_true_eq] at within
    simp only [compileStmt] at placed ⊢
    obtain ⟨values, kept⟩ := compileArgs_correct base args 0 env m agree within.2
    apply StmtResult.prefix (pc ▸ placed.left) (compileArgs_straight _ _ _)
    obtain ⟨callPlaced, storePlaced⟩ := placed.right.pair
    have returns : SourceCalls prog depth callee
        (readSlots (Instr.exec (compileArgs base args 0) m).slots (argSlots base args 0)) value := by
      rw [values]
      exact ⟨inner, lower, func, lookup, by rw [evalAll_length, length], calleeExec⟩
    apply StmtResult.step (.call (by rw [Instr.exec_pc, pc]; exact callPlaced.fetch) returns)
    apply StmtResult.step (.straight (by simp only [Instr.exec_pc, pc]; exact storePlaced.fetch) rfl)
    refine ⟨_, .refl _, by simp only [Instr.step, Instr.exec_pc, pc, codeSize_append, codeSize]; omega, ?_⟩
    intro other below
    simp only [Instr.step, Instr.update, Machine.store, Env.set]
    split
    · rfl
    · rw [kept other (by omega)]
      exact agree other below
  | @ret depth env value =>
    intro pos m placed pc agree within
    simp only [Stmt.within] at within
    simp only [compileStmt] at placed ⊢
    obtain ⟨acc, _⟩ := compileExpr_correct base value 0 env m agree within
    exact ⟨_, Star.straight _ (pc ▸ placed.left) (compileExpr_straight _ _ _),
      by rw [Instr.exec_pc, pc]; exact placed.right.fetch, acc⟩

theorem arityIs_eq (arities : List Nat) (callee count : Nat) :
    arityIs arities callee count = true ↔ arities[callee]? = some count := by
  unfold arityIs
  split <;> simp_all

theorem zeroLocals_zero (first : Nat) : zeroLocals first 0 = [] := by
  rw [zeroLocals]; rfl

theorem zeroLocals_succ (first count : Nat) :
    zeroLocals first (count + 1) = .store first :: zeroLocals (first + 1) count := by
  rw [zeroLocals]; rfl

theorem zeroLocals_straight (first count : Nat) : (zeroLocals first count).all Instr.straight = true := by
  induction count generalizing first with
  | zero => rw [zeroLocals_zero]; rfl
  | succ count ih => simp only [zeroLocals_succ, List.all_cons, ih]; rfl

theorem zeroLocals_exec (first count : Nat) (m : Machine) (zero : m.acc = 0) :
    (Instr.exec (zeroLocals first count) m).acc = 0 ∧
      ∀ slot, (Instr.exec (zeroLocals first count) m).slots slot =
        if first ≤ slot ∧ slot < first + count then 0 else m.slots slot := by
  induction count generalizing first m with
  | zero =>
    rw [zeroLocals_zero]
    exact ⟨zero, fun slot => by simp only [Instr.exec]; rw [if_neg (by omega)]⟩
  | succ count ih =>
    rw [zeroLocals_succ]
    obtain ⟨acc, slots⟩ := ih (first + 1) ((Instr.store first).step m) (by simp [Instr.step, Instr.update,
      Machine.store, zero])
    refine ⟨acc, fun slot => ?_⟩
    show (Instr.exec (zeroLocals (first + 1) count) ((Instr.store first).step m)).slots slot = _
    rw [slots slot]
    simp only [Instr.step, Instr.update, Machine.store]
    by_cases here : slot = first
    · rw [if_neg (by omega), if_pos here, if_pos (by omega), zero]
    · rw [if_neg here]
      by_cases inside : first + 1 ≤ slot ∧ slot < first + 1 + count
      · rw [if_pos inside, if_pos (by omega)]
      · rw [if_neg inside, if_neg (by omega)]

theorem compileFunc_spec {arities : List Nat} {func : Func} {code : Code}
    (compiled : compileFunc arities func = some code) :
    func.params ≤ func.locals ∧ func.body.within func.locals arities = true ∧
      code.slots = func.locals + func.body.temps ∧ code.slots ≤ frameLimit ∧
      code.instrs = (Instr.imm 0 :: zeroLocals func.params (func.locals - func.params)) ++
        compileStmt func.locals (codeSize (Instr.imm 0 :: zeroLocals func.params (func.locals - func.params)))
          func.body := by
  simp only [compileFunc] at compiled
  split at compiled
  · rename_i checks
    cases compiled
    simp only [Bool.and_eq_true, decide_eq_true_eq] at checks
    exact ⟨checks.1.1, checks.1.2, rfl, checks.2, rfl⟩
  · contradiction

/-- A compiled function, entered with its parameters in the first slots, runs
to a `ret` holding the source function's return value. -/
theorem compileFunc_correct {arities : List Nat} {func : Func} {code : Code}
    (compiled : compileFunc arities func = some code) {prog : Program} {depth : Nat}
    {args : List (BitVec 32)} {value : BitVec 32} (length : args.length = func.params)
    (exec : Exec prog depth (Func.entry args) func.body (.returned value)) (m : Machine) (start : m.pc = 0)
    (params : ∀ index, index < func.params → m.slots index = args.getD index 0) :
    ∃ m', Star (SourceCalls prog depth) code.instrs m m' ∧ fetch code.instrs m'.pc = some .ret ∧
      m'.acc = value := by
  obtain ⟨paramsFit, within, -, -, instrs⟩ := compileFunc_spec compiled
  rw [instrs]
  generalize initEq : (Instr.imm 0 :: zeroLocals func.params (func.locals - func.params)) = init
  have initStraight : init.all Instr.straight = true := by
    rw [← initEq]; simp only [List.all_cons, zeroLocals_straight]; rfl
  have initPlaced : Block (init ++ compileStmt func.locals (codeSize init) func.body) m.pc init :=
    ⟨[], compileStmt func.locals (codeSize init) func.body, by simp, by simp [codeSize, start]⟩
  have bodyPlaced : Block (init ++ compileStmt func.locals (codeSize init) func.body) (codeSize init)
      (compileStmt func.locals (codeSize init) func.body) := ⟨init, [], by simp, rfl⟩
  have initRun := Star.straight (calls := SourceCalls prog depth) init initPlaced initStraight
  have cleared := zeroLocals_exec func.params (func.locals - func.params) ((Instr.imm 0).step m)
    (by simp [Instr.step, Instr.update])
  have agree : Agree func.locals (Func.entry args) (Instr.exec init m) := by
    intro index below
    rw [← initEq]
    simp only [Instr.exec, cleared.2, Func.entry]
    by_cases param : index < func.params
    · rw [if_neg (by omega)]
      exact params index param
    · rw [if_pos (by omega)]
      simp [List.getD, List.getElem?_eq_none (show args.length ≤ index by omega)]
  have result := compileStmt_correct exec (code := init ++ compileStmt func.locals (codeSize init) func.body)
    (codeSize init) (Instr.exec init m) bodyPlaced (by rw [Instr.exec_pc, start]; omega) agree within
  obtain ⟨m', steps, fetched, acc⟩ := result
  exact ⟨m', initRun.trans steps, fetched, acc⟩

end Lanius.Mini
