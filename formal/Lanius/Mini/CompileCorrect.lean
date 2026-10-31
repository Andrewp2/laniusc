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
  fun callee args heap values after => ∃ inner, inner < depth ∧ prog.Returns inner callee args heap values after

theorem Instr.exec_singleton (i : Instr) (m : Machine) : Instr.exec [i] m = i.step m := rfl

theorem Agree.of_slots (agree : Agree base env m) (same : ∀ slot, slot < base → m'.slots slot = m.slots slot) :
    Agree base env m' := fun index below => (same index below).trans (agree index below)

theorem compileExpr_straight (base : Nat) (e : Expr) (depth : Nat) :
    (compileExpr base e depth).all Instr.straight = true := by
  induction e generalizing depth with
  | lit | var => rfl
  | neg operand ih => simp only [compileExpr, List.all_append, ih]; rfl
  | binary _ _ left right ihLeft ihRight =>
    simp only [compileExpr, List.all_append, ihLeft, ihRight]; rfl
  | compare _ _ left right ihLeft ihRight =>
    simp only [compileExpr, List.all_append, ihLeft, ihRight]; rfl
  | fp _ left right ihLeft ihRight =>
    simp only [compileExpr, List.all_append, ihLeft, ihRight]; rfl

/-- The shared shape of binary operators and comparisons: after the operands'
code, the left value waits in slot `base + depth` and the right is in the accumulator. -/
theorem operands_correct (base depth : Nat) (env : Env) (m : Machine) (agree : Agree base env m)
    (leftCode rightCode : List Instr) (leftValue rightValue : BitVec 64)
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
  | binary word operation left right ihLeft ihRight =>
    simp only [Expr.within, Bool.and_eq_true] at within
    obtain ⟨kept, acc, slots⟩ := operands_correct base depth env m agree _ _ _ _
      (fun m agree => ihLeft depth m agree within.1) (fun m agree => ihRight (depth + 1) m agree within.2)
    simp only [compileExpr, Instr.exec_append (_ ++ _ ++ _), Instr.exec_singleton]
    exact ⟨by simp only [Instr.step, Instr.update, Expr.eval]; rw [kept, acc], slots⟩
  | compare word operation left right ihLeft ihRight =>
    simp only [Expr.within, Bool.and_eq_true] at within
    obtain ⟨kept, acc, slots⟩ := operands_correct base depth env m agree _ _ _ _
      (fun m agree => ihLeft depth m agree within.1) (fun m agree => ihRight (depth + 1) m agree within.2)
    simp only [compileExpr, Instr.exec_append (_ ++ _ ++ _), Instr.exec_singleton]
    exact ⟨by simp only [Instr.step, Instr.update, Expr.eval]; rw [kept, acc], slots⟩
  | fp operation left right ihLeft ihRight =>
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

/-- What running a placed statement's code achieves, given the source outcome:
a break reaches `brk` with the accumulator 0, a continue reaches `cont`. -/
def StmtResult (calls : Calls) (code : List Instr) (base pos : Nat) (block : List Instr) (brk cont : Nat)
    (m : Machine) : Outcome → Prop
  | .normal env heap => ∃ m', Star calls code m m' ∧ m'.pc = pos + codeSize block ∧ Agree base env m' ∧
      m'.heap = heap
  | .returned values heap => ∃ m' sources, Star calls code m m' ∧ fetch code m'.pc = some (.ret sources) ∧
      readSlots m'.slots sources = values ∧ m'.heap = heap
  | .broke env heap => ∃ m', Star calls code m m' ∧ m'.pc = brk ∧ m'.acc = 0 ∧ Agree base env m' ∧
      m'.heap = heap
  | .continued env heap => ∃ m', Star calls code m m' ∧ m'.pc = cont ∧ Agree base env m' ∧ m'.heap = heap

theorem StmtResult.star {calls : Calls} {code : List Instr} {m next : Machine}
    (run : Star calls code m next) (rest : StmtResult calls code base pos whole brk cont next outcome) :
    StmtResult calls code base pos whole brk cont m outcome := by
  cases outcome with
  | normal env heap =>
    obtain ⟨m', steps, pc, agree, onHeap⟩ := rest
    exact ⟨m', run.trans steps, pc, agree, onHeap⟩
  | returned value heap =>
    obtain ⟨m', sources, steps, fetched, acc, onHeap⟩ := rest
    exact ⟨m', sources, run.trans steps, fetched, acc, onHeap⟩
  | broke env heap =>
    obtain ⟨m', steps, pc, acc, agree, onHeap⟩ := rest
    exact ⟨m', run.trans steps, pc, acc, agree, onHeap⟩
  | continued env heap =>
    obtain ⟨m', steps, pc, agree, onHeap⟩ := rest
    exact ⟨m', run.trans steps, pc, agree, onHeap⟩

/-- A placed straight-line block, then the rest of a statement's run. -/
theorem StmtResult.prefix {calls : Calls} {code block : List Instr} {m : Machine}
    (placed : Block code m.pc block) (allStraight : block.all Instr.straight = true)
    (rest : StmtResult calls code base pos whole brk cont (Instr.exec block m) outcome) :
    StmtResult calls code base pos whole brk cont m outcome :=
  StmtResult.star (Star.straight (calls := calls) block placed allStraight) rest

theorem StmtResult.step {calls : Calls} {code : List Instr} {m next : Machine}
    (step : Step calls code m next) (rest : StmtResult calls code base pos whole brk cont next outcome) :
    StmtResult calls code base pos whole brk cont m outcome :=
  StmtResult.star (.single step) rest

/-- A statement's result through a sub-block, with the end of the block moved. -/
theorem StmtResult.retarget {calls : Calls} {code : List Instr} {m : Machine}
    (inner : StmtResult calls code base innerPos innerBlock brk cont m outcome)
    (normalEnd : ∀ env heap m', Star calls code m m' → m'.pc = innerPos + codeSize innerBlock →
      Agree base env m' → m'.heap = heap → StmtResult calls code base pos whole brk cont m (.normal env heap)) :
    StmtResult calls code base pos whole brk cont m outcome := by
  cases outcome with
  | normal env heap =>
    obtain ⟨m', steps, pc, agree, onHeap⟩ := inner
    exact normalEnd env heap m' steps pc agree onHeap
  | returned value => exact inner
  | broke env heap => exact inner
  | continued env heap => exact inner

/-- A sub-block that ends normally, then the rest of the statement. -/
theorem StmtResult.andThen {calls : Calls} {code : List Instr} {m : Machine}
    (first : StmtResult calls code base innerPos innerBlock brk' cont' m (.normal middle between))
    (rest : ∀ m', Star calls code m m' → m'.pc = innerPos + codeSize innerBlock → Agree base middle m' →
      m'.heap = between → StmtResult calls code base pos whole brk cont m outcome) :
    StmtResult calls code base pos whole brk cont m outcome := by
  obtain ⟨m', steps, pc, agree, onHeap⟩ := first
  exact rest m' steps pc agree onHeap

/-- A sub-block that breaks, then the rest of the statement. -/
theorem StmtResult.whenBroke {calls : Calls} {code : List Instr} {m : Machine}
    (first : StmtResult calls code base innerPos innerBlock brk' cont' m (.broke middle between))
    (rest : ∀ m', Star calls code m m' → m'.pc = brk' → m'.acc = 0 → Agree base middle m' →
      m'.heap = between → StmtResult calls code base pos whole brk cont m outcome) :
    StmtResult calls code base pos whole brk cont m outcome := by
  obtain ⟨m', steps, pc, acc, agree, onHeap⟩ := first
  exact rest m' steps pc acc agree onHeap

/-- A sub-block that continues, then the rest of the statement. -/
theorem StmtResult.whenContinued {calls : Calls} {code : List Instr} {m : Machine}
    (first : StmtResult calls code base innerPos innerBlock brk' cont' m (.continued middle between))
    (rest : ∀ m', Star calls code m m' → m'.pc = cont' → Agree base middle m' →
      m'.heap = between → StmtResult calls code base pos whole brk cont m outcome) :
    StmtResult calls code base pos whole brk cont m outcome := by
  obtain ⟨m', steps, pc, agree, onHeap⟩ := first
  exact rest m' steps pc agree onHeap

theorem Block.at (placed : Block code pos block) (same : pos = pos') : Block code pos' block :=
  same ▸ placed

/-- The two-instruction block of a call: the call, then the store of its result. -/
theorem Block.pair (placed : Block code pos [first, second]) :
    Block code pos [first] ∧ Block code (pos + first.size) [second] := by
  have split : Block code pos ([first] ++ [second]) := placed
  exact ⟨split.left, by simpa [codeSize] using split.right⟩

theorem setMany_eq : ∀ (values : List (BitVec 64)) (env : Env) (target slot : Nat),
    env.setMany target values slot =
      if target ≤ slot ∧ slot < target + values.length then values.getD (slot - target) 0 else env slot
  | [], env, target, slot => by
    simp only [Env.setMany, List.length_nil, Nat.add_zero]
    rw [if_neg (by omega)]
  | v :: rest, env, target, slot => by
    simp only [Env.setMany]
    rw [setMany_eq rest]
    simp only [Env.set, List.length_cons]
    by_cases here : slot = target
    · subst here
      rw [if_neg (by omega), if_pos rfl, if_pos (by omega)]
      simp
    · by_cases inside : target + 1 ≤ slot ∧ slot < target + 1 + rest.length
      · rw [if_pos inside, if_pos (by omega)]
        obtain ⟨k, rfl⟩ : ∃ k, slot = target + 1 + k := ⟨slot - (target + 1), by omega⟩
        rw [show target + 1 + k - target = k + 1 by omega, show target + 1 + k - (target + 1) = k by omega]
        simp
      · rw [if_neg inside, if_neg here, if_neg (by omega)]

/-- The end of a statement that computes a value and stores it in `target`. -/
theorem stored_result {calls : Calls} {code : List Instr} {m : Machine} {base pos target : Nat} {env : Env}
    {block : List Instr} (placed : Block code m.pc [.store target]) (pcEnd : m.pc + 7 = pos + codeSize block)
    (agree : ∀ slot, slot < base → slot ≠ target → m.slots slot = env slot)
    (heap : Heap) (onHeap : m.heap = heap) :
    StmtResult calls code base pos block brk cont m (.normal (env.set target m.acc) heap) := by
  refine ⟨_, .single (.straight placed.fetch rfl), by simp only [Instr.step, Instr.size]; omega, ?_, onHeap⟩
  intro other inside
  simp only [Instr.step, Instr.update, Machine.store, Env.set]
  split
  · rfl
  · exact agree other inside (by assumption)

theorem compileStmt_correct {prog : Program} {base : Nat} {arities : List Arity} {results : Nat}
    {code : List Instr}
    {depth : Nat} {env : Env} {heap : Heap} {stmt : Stmt} {outcome : Outcome}
    (exec : Exec prog depth env heap stmt outcome) :
    ∀ pos brk cont m, Block code pos (compileStmt base pos brk cont stmt) → m.pc = pos → Agree base env m →
      m.heap = heap → stmt.within base arities results = true →
      StmtResult (SourceCalls prog depth) code base pos (compileStmt base pos brk cont stmt) brk cont m outcome := by
  induction exec with
  | skip =>
    intro pos brk cont m _ pc agree onHeap _
    exact ⟨m, .refl _, by simp [compileStmt, codeSize, pc], agree, onHeap⟩
  | @assign depth env heap index value =>
    intro pos brk cont m placed pc agree onHeap within
    simp only [Stmt.within, Bool.and_eq_true, decide_eq_true_eq] at within
    have allStraight : (compileStmt base pos brk cont (.assign index value)).all Instr.straight = true := by
      simp only [compileStmt, List.all_append, compileExpr_straight]; rfl
    obtain ⟨acc, kept⟩ := compileExpr_correct base value 0 env m agree within.2
    refine ⟨_, Star.straight _ (pc ▸ placed) allStraight, by rw [Instr.exec_pc, pc], ?_,
      (Instr.exec_heap _ _).trans onHeap⟩
    intro other below
    simp only [compileStmt, Instr.exec_append, Instr.exec_singleton, Instr.step, Instr.update,
      Machine.store, Env.set, acc]
    split
    · rfl
    · rw [kept other (by omega)]
      exact agree other below
  | @seq depth env middle heap between first second outcome _ _ ihFirst ihSecond =>
    intro pos brk cont m placed pc agree onHeap within
    simp only [Stmt.within, Bool.and_eq_true] at within
    simp only [compileStmt] at placed ⊢
    obtain ⟨m', steps, pc', agree', onHeap'⟩ := ihFirst pos brk cont m placed.left pc agree onHeap within.1
    have secondRun := ihSecond _ brk cont m' placed.right pc' agree' onHeap' within.2
    have run : StmtResult _ code base pos (compileStmt base pos brk cont first ++
        compileStmt base (pos + codeSize (compileStmt base pos brk cont first)) brk cont second) brk cont m' outcome :=
      secondRun.retarget fun env heap m'' steps' pc'' agree'' onHeap'' =>
      ⟨m'', steps', by rw [pc'', codeSize_append]; omega, agree'', onHeap''⟩
    exact StmtResult.star steps run
  | @seqReturned depth env heap after first second value _ ihFirst =>
    intro pos brk cont m placed pc agree onHeap within
    simp only [Stmt.within, Bool.and_eq_true] at within
    simp only [compileStmt] at placed ⊢
    exact ihFirst pos brk cont m placed.left pc agree onHeap within.1
  | @seqBroke depth env middle heap between first second _ ihFirst =>
    intro pos brk cont m placed pc agree onHeap within
    simp only [Stmt.within, Bool.and_eq_true] at within
    simp only [compileStmt] at placed ⊢
    exact ihFirst pos brk cont m placed.left pc agree onHeap within.1
  | @seqContinued depth env middle heap between first second _ ihFirst =>
    intro pos brk cont m placed pc agree onHeap within
    simp only [Stmt.within, Bool.and_eq_true] at within
    simp only [compileStmt] at placed ⊢
    exact ihFirst pos brk cont m placed.left pc agree onHeap within.1
  | @ifTrue depth env heap condition thenBranch elseBranch outcome nonzero _ ihThen =>
    intro pos brk cont m placed pc agree onHeap within
    simp only [Stmt.within, Bool.and_eq_true] at within
    simp only [compileStmt] at placed ⊢
    obtain ⟨acc, kept⟩ := compileExpr_correct base condition 0 env m agree within.1.1
    apply StmtResult.prefix (pc ▸ placed.left.left.left.left) (compileExpr_straight _ _ _)
    have jz := placed.left.left.left.right.fetch
    apply StmtResult.step (.jzNot (by rw [Instr.exec_pc, pc]; exact jz) (by rw [acc]; exact nonzero))
    refine StmtResult.retarget (ihThen (pos + codeSize (compileExpr base condition 0) + 9) brk cont _ ?_ ?_ ?_
      ((Instr.exec_heap _ _).trans onHeap) within.1.2) ?_
    · exact placed.left.left.right.at (by simp only [codeSize_append, codeSize, Instr.size]; omega)
    · simp only [Instr.exec_pc, pc, Instr.size]
    · exact agree.of_slots fun slot below => kept slot (by omega)
    intro env' heap' m' steps pc' agree' onHeap'
    refine ⟨_, steps.trans (.single (.jmp (placed.left.right.at (by
      rw [pc']; simp only [codeSize_append, codeSize, Instr.size]; omega)).fetch)),
      by simp only [codeSize_append, codeSize, Instr.size]; omega, agree', onHeap'⟩
  | @ifFalse depth env heap condition thenBranch elseBranch outcome zero _ ihElse =>
    intro pos brk cont m placed pc agree onHeap within
    simp only [Stmt.within, Bool.and_eq_true] at within
    simp only [compileStmt] at placed ⊢
    obtain ⟨acc, kept⟩ := compileExpr_correct base condition 0 env m agree within.1.1
    apply StmtResult.prefix (pc ▸ placed.left.left.left.left) (compileExpr_straight _ _ _)
    have jz := placed.left.left.left.right.fetch
    apply StmtResult.step (.jzTaken (by rw [Instr.exec_pc, pc]; exact jz) (by rw [acc]; exact zero))
    refine StmtResult.retarget (ihElse (pos + codeSize (compileExpr base condition 0) + 9 +
      codeSize (compileStmt base (pos + codeSize (compileExpr base condition 0) + 9) brk cont thenBranch) + 5)
      brk cont _ ?_ rfl ?_ ((Instr.exec_heap _ _).trans onHeap) within.2) ?_
    · exact placed.right.at (by simp only [codeSize_append, codeSize, Instr.size]; omega)
    · exact agree.of_slots fun slot below => kept slot (by omega)
    intro env' heap' m' steps pc' agree' onHeap'
    exact ⟨m', steps, by rw [pc']; simp only [codeSize_append, codeSize, Instr.size]; omega, agree', onHeap'⟩
  | @loopDone depth env heap condition body zero =>
    intro pos brk cont m placed pc agree onHeap within
    simp only [Stmt.within, Bool.and_eq_true] at within
    simp only [compileStmt] at placed ⊢
    obtain ⟨acc, kept⟩ := compileExpr_correct base condition 0 env m agree within.1
    apply StmtResult.prefix (pc ▸ placed.left.left.left) (compileExpr_straight _ _ _)
    have jz := placed.left.left.right.fetch
    apply StmtResult.step (.jzTaken (by rw [Instr.exec_pc, pc]; exact jz) (by rw [acc]; exact zero))
    exact ⟨_, .refl _, by simp only [codeSize_append, codeSize, Instr.size]; omega,
      agree.of_slots fun slot below => kept slot (by omega), (Instr.exec_heap _ _).trans onHeap⟩
  | @loopNext depth env middle heap between condition body outcome nonzero _ _ ihBody ihLoop =>
    intro pos brk cont m placed pc agree onHeap within
    have loopWithin := within
    simp only [Stmt.within, Bool.and_eq_true] at within
    have placedLoop := placed
    simp only [compileStmt] at placed ⊢
    obtain ⟨acc, kept⟩ := compileExpr_correct base condition 0 env m agree within.1
    apply StmtResult.prefix (pc ▸ placed.left.left.left) (compileExpr_straight _ _ _)
    have jz := placed.left.left.right.fetch
    apply StmtResult.step (.jzNot (by rw [Instr.exec_pc, pc]; exact jz) (by rw [acc]; exact nonzero))
    refine StmtResult.andThen (ihBody (pos + codeSize (compileExpr base condition 0) + 9) (pos + codeSize (compileExpr base condition 0)) pos _ ?_ ?_ ?_
      ((Instr.exec_heap _ _).trans onHeap) within.2) ?_
    · exact placed.left.right.at (by simp only [codeSize_append, codeSize, Instr.size]; omega)
    · simp only [Instr.exec_pc, pc, Instr.size]
    · exact agree.of_slots fun slot below => kept slot (by omega)
    intro m' steps pc' agree' onHeap'
    have jumped : Star (SourceCalls prog depth) code m' { m' with pc := pos } :=
      .single (.jmp (placed.right.at (by
        rw [pc']; simp only [codeSize_append, codeSize, Instr.size]; omega)).fetch)
    have again := ihLoop pos brk cont { m' with pc := pos } placedLoop rfl agree' onHeap' loopWithin
    simp only [compileStmt] at again
    exact StmtResult.star (steps.trans jumped) again
  | @loopReturned depth env heap after condition body value nonzero _ ihBody =>
    intro pos brk cont m placed pc agree onHeap within
    simp only [Stmt.within, Bool.and_eq_true] at within
    simp only [compileStmt] at placed ⊢
    obtain ⟨acc, kept⟩ := compileExpr_correct base condition 0 env m agree within.1
    apply StmtResult.prefix (pc ▸ placed.left.left.left) (compileExpr_straight _ _ _)
    have jz := placed.left.left.right.fetch
    apply StmtResult.step (.jzNot (by rw [Instr.exec_pc, pc]; exact jz) (by rw [acc]; exact nonzero))
    refine ihBody (pos + codeSize (compileExpr base condition 0) + 9) (pos + codeSize (compileExpr base condition 0)) pos _ ?_ ?_ ?_
      ((Instr.exec_heap _ _).trans onHeap) within.2
    · exact placed.left.right.at (by simp only [codeSize_append, codeSize, Instr.size]; omega)
    · simp only [Instr.exec_pc, pc, Instr.size]
    · exact agree.of_slots fun slot below => kept slot (by omega)
  | @loopBroke depth env middle heap between condition body nonzero _ ihBody =>
    intro pos brk cont m placed pc agree onHeap within
    simp only [Stmt.within, Bool.and_eq_true] at within
    simp only [compileStmt] at placed ⊢
    obtain ⟨acc, kept⟩ := compileExpr_correct base condition 0 env m agree within.1
    apply StmtResult.prefix (pc ▸ placed.left.left.left) (compileExpr_straight _ _ _)
    have jz := placed.left.left.right.fetch
    apply StmtResult.step (.jzNot (by rw [Instr.exec_pc, pc]; exact jz) (by rw [acc]; exact nonzero))
    refine StmtResult.whenBroke (ihBody (pos + codeSize (compileExpr base condition 0) + 9)
      (pos + codeSize (compileExpr base condition 0)) pos _ ?_ ?_ ?_ ((Instr.exec_heap _ _).trans onHeap)
      within.2) ?_
    · exact placed.left.right.at (by simp only [codeSize_append, codeSize, Instr.size]; omega)
    · simp only [Instr.exec_pc, pc, Instr.size]
    · exact agree.of_slots fun slot below => kept slot (by omega)
    intro m' steps pc' zero agree' onHeap'
    have here : fetch code m'.pc = fetch code (pos + codeSize (compileExpr base condition 0)) := by rw [pc']
    refine ⟨_, steps.trans (.single (.jzTaken (here.trans jz) zero)), ?_, agree', onHeap'⟩
    simp only [codeSize_append, codeSize, Instr.size]; omega
  | @loopContinued depth env middle heap between condition body outcome nonzero _ _ ihBody ihLoop =>
    intro pos brk cont m placed pc agree onHeap within
    have loopWithin := within
    simp only [Stmt.within, Bool.and_eq_true] at within
    have placedLoop := placed
    simp only [compileStmt] at placed ⊢
    obtain ⟨acc, kept⟩ := compileExpr_correct base condition 0 env m agree within.1
    apply StmtResult.prefix (pc ▸ placed.left.left.left) (compileExpr_straight _ _ _)
    have jz := placed.left.left.right.fetch
    apply StmtResult.step (.jzNot (by rw [Instr.exec_pc, pc]; exact jz) (by rw [acc]; exact nonzero))
    refine StmtResult.whenContinued (ihBody (pos + codeSize (compileExpr base condition 0) + 9)
      (pos + codeSize (compileExpr base condition 0)) pos _ ?_ ?_ ?_ ((Instr.exec_heap _ _).trans onHeap)
      within.2) ?_
    · exact placed.left.right.at (by simp only [codeSize_append, codeSize, Instr.size]; omega)
    · simp only [Instr.exec_pc, pc, Instr.size]
    · exact agree.of_slots fun slot below => kept slot (by omega)
    intro m' steps pc' agree' onHeap'
    have again := ihLoop pos brk cont m' placedLoop pc' agree' onHeap' loopWithin
    simp only [compileStmt] at again
    exact StmtResult.star steps again
  | brk =>
    intro pos brk cont m placed pc agree onHeap _
    simp only [compileStmt] at placed ⊢
    obtain ⟨immAt, jmpAt⟩ := placed.pair
    exact ⟨_, (Star.single (Step.straight (i := .imm 0) (pc ▸ immAt).fetch rfl)).trans
      (.single (.jmp (jmpAt.at (by simp [Instr.step, Instr.update, pc])).fetch)), rfl, rfl,
      fun slot below => by simpa [Instr.step, Instr.update] using agree slot below,
      by simpa [Instr.step, Instr.update] using onHeap⟩
  | cont =>
    intro pos brk cont m placed pc agree onHeap _
    simp only [compileStmt] at placed ⊢
    exact ⟨_, .single (.jmp (pc ▸ placed.fetch)), rfl, agree, onHeap⟩
  | @call depth inner target count callee env heap after args func value lookup length counted lower
      calleeExec _ =>
    intro pos brk cont m placed pc agree onHeap within
    simp only [Stmt.within, Bool.and_eq_true, decide_eq_true_eq] at within
    simp only [compileStmt] at placed ⊢
    obtain ⟨values, kept⟩ := compileArgs_correct base args 0 env m agree within.2
    apply StmtResult.prefix (pc ▸ placed.left) (compileArgs_straight _ _ _)
    have returns : SourceCalls prog depth callee
        (readSlots (Instr.exec (compileArgs base args 0) m).slots (argSlots base args 0))
        (Instr.exec (compileArgs base args 0) m).heap value after := by
      rw [values, Instr.exec_heap, onHeap]
      exact ⟨inner, lower, func, lookup, by rw [evalAll_length, length], calleeExec⟩
    apply StmtResult.step (.call (by rw [Instr.exec_pc, pc]; exact placed.right.fetch) returns counted)
    refine ⟨_, .refl _, by simp only [Instr.exec_pc, pc, codeSize_append, codeSize]; omega, ?_, rfl⟩
    intro other below
    simp only [writeSlots]
    rw [setMany_eq]
    by_cases inside : target ≤ other ∧ other < target + value.length
    · rw [if_pos inside, if_pos inside]
    · rw [if_neg inside, if_neg inside, kept other (by omega)]
      exact agree other below
  | @ret depth env heap values =>
    intro pos brk cont m placed pc agree onHeap within
    simp only [Stmt.within, Bool.and_eq_true] at within
    simp only [compileStmt] at placed ⊢
    obtain ⟨vals, _⟩ := compileArgs_correct base values 0 env m agree within.2
    exact ⟨_, _, Star.straight _ (pc ▸ placed.left) (compileArgs_straight _ _ _),
      by rw [Instr.exec_pc, pc]; exact placed.right.fetch, vals, (Instr.exec_heap _ _).trans onHeap⟩
  | @alloc depth env heap target shift size room =>
    intro pos brk cont m placed pc agree onHeap within
    simp only [Stmt.within, Bool.and_eq_true, decide_eq_true_eq] at within
    simp only [compileStmt] at placed ⊢
    obtain ⟨acc, kept⟩ := compileExpr_correct base size 0 env m agree within.2
    apply StmtResult.prefix (pc ▸ placed.left) (compileExpr_straight _ _ _)
    obtain ⟨bumpAt, storeAt⟩ := placed.right.pair
    have heapAt := (Instr.exec_heap (compileExpr base size 0) m).trans onHeap
    apply StmtResult.step (.bump (by rw [Instr.exec_pc, pc]; exact bumpAt.fetch)
      (by rw [heapAt, acc]; exact room))
    rw [heapAt, acc]
    refine stored_result ?_ ?_ ?_ _ ?_
    · exact storeAt.at (by simp only [Instr.exec_pc, pc])
    · simp only [Instr.exec_pc, pc, codeSize_append, codeSize, Instr.size]; omega
    · exact fun slot below _ => (kept slot (by omega)).trans (agree slot below)
    · first | rfl | exact heapAt
  | @loadByte depth env heap target address inside =>
    intro pos brk cont m placed pc agree onHeap within
    simp only [Stmt.within, Bool.and_eq_true, decide_eq_true_eq] at within
    simp only [compileStmt] at placed ⊢
    obtain ⟨acc, kept⟩ := compileExpr_correct base address 0 env m agree within.2
    apply StmtResult.prefix (pc ▸ placed.left) (compileExpr_straight _ _ _)
    obtain ⟨loadAt, storeAt⟩ := placed.right.pair
    have heapAt := (Instr.exec_heap (compileExpr base address 0) m).trans onHeap
    apply StmtResult.step (.loadAt (by rw [Instr.exec_pc, pc]; exact loadAt.fetch)
      (by rw [heapAt, acc]; exact inside))
    rw [heapAt, acc]
    refine stored_result ?_ ?_ ?_ _ ?_
    · exact storeAt.at (by simp only [Instr.exec_pc, pc])
    · simp only [Instr.exec_pc, pc, codeSize_append, codeSize, Instr.size]; omega
    · exact fun slot below _ => (kept slot (by omega)).trans (agree slot below)
    · first | rfl | exact heapAt
  | @storeByte depth env heap address value inside =>
    intro pos brk cont m placed pc agree onHeap within
    simp only [Stmt.within, Bool.and_eq_true] at within
    simp only [compileStmt] at placed ⊢
    have placed' : Block code pos ((compileExpr base address 0 ++ [Instr.store base] ++
        compileExpr base value 1) ++ [Instr.storeAt base]) := by simpa only [List.append_assoc] using placed
    obtain ⟨kept, acc, slots⟩ := operands_correct base 0 env m agree _ _ _ _
      (fun m agree => compileExpr_correct base address 0 env m agree within.1)
      (fun m agree => compileExpr_correct base value 1 env m agree within.2)
    simp only [Nat.add_zero] at kept acc slots
    apply StmtResult.prefix (pc ▸ placed'.left)
      (by simp only [List.all_append, compileExpr_straight]; rfl)
    have heapAt := (Instr.exec_heap (compileExpr base address 0 ++ [Instr.store base] ++
      compileExpr base value 1) m).trans onHeap
    apply StmtResult.step (.storeAt (by rw [Instr.exec_pc, pc]; exact placed'.right.fetch)
      (by rw [heapAt, kept]; exact inside))
    refine ⟨_, .refl _, by simp only [Instr.exec_pc, pc, codeSize_append, codeSize]; omega,
      agree.of_slots slots, ?_⟩
    simp only [heapAt, kept, acc]
  | @loadWord depth env heap width target address inside =>
    intro pos brk cont m placed pc agree onHeap within
    simp only [Stmt.within, Bool.and_eq_true, decide_eq_true_eq] at within
    simp only [compileStmt] at placed ⊢
    obtain ⟨acc, kept⟩ := compileExpr_correct base address 0 env m agree within.2
    apply StmtResult.prefix (pc ▸ placed.left) (compileExpr_straight _ _ _)
    obtain ⟨loadAt, storeAt⟩ := placed.right.pair
    have heapAt := (Instr.exec_heap (compileExpr base address 0) m).trans onHeap
    apply StmtResult.step (.loadWordAt (by rw [Instr.exec_pc, pc]; exact loadAt.fetch)
      (by rw [heapAt, acc]; exact inside))
    rw [heapAt, acc]
    refine stored_result ?_ ?_ ?_ _ ?_
    · exact storeAt.at (by simp only [Instr.exec_pc, pc])
    · simp only [Instr.exec_pc, pc, codeSize_append, codeSize, Instr.size]; omega
    · exact fun slot below _ => (kept slot (by omega)).trans (agree slot below)
    · first | rfl | exact heapAt
  | @storeWord depth env heap width address value inside =>
    intro pos brk cont m placed pc agree onHeap within
    simp only [Stmt.within, Bool.and_eq_true] at within
    simp only [compileStmt] at placed ⊢
    have placed' : Block code pos ((compileExpr base address 0 ++ [Instr.store base] ++
        compileExpr base value 1) ++ [Instr.storeWordAt width base]) := by simpa only [List.append_assoc] using placed
    obtain ⟨kept, acc, slots⟩ := operands_correct base 0 env m agree _ _ _ _
      (fun m agree => compileExpr_correct base address 0 env m agree within.1)
      (fun m agree => compileExpr_correct base value 1 env m agree within.2)
    simp only [Nat.add_zero] at kept acc slots
    apply StmtResult.prefix (pc ▸ placed'.left)
      (by simp only [List.all_append, compileExpr_straight]; rfl)
    have heapAt := (Instr.exec_heap (compileExpr base address 0 ++ [Instr.store base] ++
      compileExpr base value 1) m).trans onHeap
    apply StmtResult.step (.storeWordAt (by rw [Instr.exec_pc, pc]; exact placed'.right.fetch)
      (by rw [heapAt, kept]; exact inside))
    refine ⟨_, .refl _, by simp only [Instr.exec_pc, pc, codeSize_append, codeSize]; omega,
      agree.of_slots slots, ?_⟩
    simp only [heapAt, kept, acc]
  | @divide depth env heap word operation target left right defined =>
    intro pos brk cont m placed pc agree onHeap within
    simp only [Stmt.within, Bool.and_eq_true, decide_eq_true_eq] at within
    simp only [compileStmt] at placed ⊢
    obtain ⟨kept, acc, slots⟩ := operands_correct base 0 env m agree _ _ _ _
      (fun m agree => compileExpr_correct base left 0 env m agree within.1.2)
      (fun m agree => compileExpr_correct base right 1 env m agree within.2)
    simp only [Nat.add_zero] at kept acc slots
    apply StmtResult.prefix (pc ▸ placed.left)
      (by simp only [List.all_append, compileExpr_straight]; rfl)
    obtain ⟨divAt, storeAt⟩ := placed.right.pair
    have heapAt := (Instr.exec_heap (compileExpr base left 0 ++ [Instr.store base] ++
      compileExpr base right 1) m).trans onHeap
    apply StmtResult.step (.div (by rw [Instr.exec_pc, pc]; exact divAt.fetch)
      (by rw [kept, acc]; exact defined))
    rw [kept, acc]
    refine stored_result ?_ ?_ ?_ _ ?_
    · exact storeAt.at (by simp only [Instr.exec_pc, pc])
    · simp only [Instr.exec_pc, pc, codeSize_append, codeSize, Instr.size]; omega
    · exact fun slot below _ => (slots slot below).trans (agree slot below)
    · exact heapAt
  | frame =>
    intro pos brk cont m _ _ _ _ within
    simp [Stmt.within] at within
  | @sys depth env heap after call target args result ran =>
    intro pos brk cont m placed pc agree onHeap within
    simp only [Stmt.within, Bool.and_eq_true, decide_eq_true_eq] at within
    simp only [compileStmt] at placed ⊢
    obtain ⟨values, kept⟩ := compileArgs_correct base args 0 env m agree within.2
    apply StmtResult.prefix (pc ▸ placed.left) (compileArgs_straight _ _ _)
    obtain ⟨sysAt, storeAt⟩ := placed.right.pair
    have heapAt := (Instr.exec_heap (compileArgs base args 0) m).trans onHeap
    obtain ⟨a, b, c, rfl⟩ : ∃ a b c, args = [a, b, c] := by
      match args, within.1.2 with
      | [a, b, c], _ => exact ⟨a, b, c, rfl⟩
    have read : [(Instr.exec (compileArgs base [a, b, c] 0) m).slots base,
        (Instr.exec (compileArgs base [a, b, c] 0) m).slots (base + 1),
        (Instr.exec (compileArgs base [a, b, c] 0) m).slots (base + 2)] = Expr.evalAll env [a, b, c] := by
      simp only [argSlots, readSlots, Nat.add_zero] at values
      exact values
    apply StmtResult.step (.sys (by rw [Instr.exec_pc, pc]; exact sysAt.fetch) (by rw [read, heapAt]; exact ran))
    refine stored_result ?_ ?_ ?_ _ rfl
    · exact storeAt.at (by simp only [Instr.exec_pc, pc])
    · simp only [Instr.exec_pc, pc, codeSize_append, codeSize, Instr.size]; omega
    · exact fun slot below _ => (kept slot (by omega)).trans (agree slot below)

theorem arityIs_eq (arities : List Arity) (callee count results : Nat) :
    arityIs arities callee count results = true ↔
      ∃ arity, arities[callee]? = some arity ∧ arity.params = count ∧ arity.results = results := by
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

theorem compileFunc_spec {arities : List Arity} {func : Func} {code : Code}
    (compiled : compileFunc arities func = some code) :
    func.params ≤ func.locals ∧ func.body.within func.locals arities func.results = true ∧
      code.slots = func.locals + func.body.temps ∧ code.slots ≤ frameLimit ∧
      code.instrs = (Instr.imm 0 :: zeroLocals func.params (func.locals - func.params)) ++
        compileStmt func.locals (codeSize (Instr.imm 0 :: zeroLocals func.params (func.locals - func.params))) 0 0
          func.body ∧ 0 < func.results ∧ func.results ≤ func.locals := by
  simp only [compileFunc] at compiled
  split at compiled
  · rename_i checks
    cases compiled
    simp only [Bool.and_eq_true, decide_eq_true_eq] at checks
    exact ⟨checks.1.1.1.1, checks.1.2, rfl, checks.2, rfl, checks.1.1.1.2, checks.1.1.2⟩
  · contradiction

/-- A compiled function, entered with its parameters in the first slots, runs
to a `ret` holding the source function's return value. -/
theorem compileFunc_correct {arities : List Arity} {func : Func} {code : Code}
    (compiled : compileFunc arities func = some code) {prog : Program} {depth : Nat}
    {args : List (BitVec 64)} {value : List (BitVec 64)} (length : args.length = func.params)
    {heap after : Heap} (exec : Exec prog depth (Func.entry args) heap func.body (.returned value after)) (m : Machine)
    (start : m.pc = 0) (onHeap : m.heap = heap)
    (params : ∀ index, index < func.params → m.slots index = args.getD index 0) :
    ∃ m' sources, Star (SourceCalls prog depth) code.instrs m m' ∧
      fetch code.instrs m'.pc = some (.ret sources) ∧ readSlots m'.slots sources = value ∧ m'.heap = after := by
  obtain ⟨paramsFit, within, -, -, instrs, -⟩ := compileFunc_spec compiled
  rw [instrs]
  generalize initEq : (Instr.imm 0 :: zeroLocals func.params (func.locals - func.params)) = init
  have initStraight : init.all Instr.straight = true := by
    rw [← initEq]; simp only [List.all_cons, zeroLocals_straight]; rfl
  have initPlaced : Block (init ++ compileStmt func.locals (codeSize init) 0 0 func.body) m.pc init :=
    ⟨[], compileStmt func.locals (codeSize init) 0 0 func.body, by simp, by simp [codeSize, start]⟩
  have bodyPlaced : Block (init ++ compileStmt func.locals (codeSize init) 0 0 func.body) (codeSize init)
      (compileStmt func.locals (codeSize init) 0 0 func.body) := ⟨init, [], by simp, rfl⟩
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
  have result := compileStmt_correct exec (code := init ++ compileStmt func.locals (codeSize init) 0 0 func.body)
    (codeSize init) 0 0 (Instr.exec init m) bodyPlaced (by rw [Instr.exec_pc, start]; omega) agree
    ((Instr.exec_heap _ _).trans onHeap) within
  obtain ⟨m', sources, steps, fetched, acc, onHeap'⟩ := result
  exact ⟨m', sources, initRun.trans steps, fetched, acc, onHeap'⟩

end Lanius.Mini
