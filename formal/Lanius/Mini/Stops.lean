import Lanius.Mini.CompileCorrect

/-! Runs that do not return. `Stops prog depth env heap stmt n`: the run of
`stmt` stops at a checked fault (an allocation past the heap's limit from a
cursor within it, a
division by zero or of the least value by -1), or is still running after `n`
ticks, a tick being a loop iteration or a call. Calls in the parts of the run
that complete nest fewer than `depth` deep. A run that is `Stops` for every
`n` never returns. The abstract machine has the same notion (`AStops`), and
the compiled code of a `Stops` statement is `AStops` for the same `n`. -/

namespace Lanius.Mini

inductive Stops (prog : Program) : Nat → Env → Heap → Stmt → Nat → Prop where
  | zero {depth : Nat} {env : Env} {heap : Heap} {stmt : Stmt} : Stops prog depth env heap stmt 0
  | seqFirst {depth : Nat} {env : Env} {heap : Heap} {first second : Stmt} {n : Nat} :
      Stops prog depth env heap first n → Stops prog depth env heap (.seq first second) n
  | seqSecond {depth : Nat} {env middle : Env} {heap between : Heap} {first second : Stmt} {n : Nat} :
      Exec prog depth env heap first (.normal middle between) → Stops prog depth middle between second n →
      Stops prog depth env heap (.seq first second) n
  | ifTrue {depth : Nat} {env : Env} {heap : Heap} {condition : Expr} {thenBranch elseBranch : Stmt} {n : Nat} :
      condition.eval env ≠ 0 → Stops prog depth env heap thenBranch n →
      Stops prog depth env heap (.ite condition thenBranch elseBranch) n
  | ifFalse {depth : Nat} {env : Env} {heap : Heap} {condition : Expr} {thenBranch elseBranch : Stmt} {n : Nat} :
      condition.eval env = 0 → Stops prog depth env heap elseBranch n →
      Stops prog depth env heap (.ite condition thenBranch elseBranch) n
  | loopBody {depth : Nat} {env : Env} {heap : Heap} {condition : Expr} {body : Stmt} {n : Nat} :
      condition.eval env ≠ 0 → Stops prog depth env heap body n →
      Stops prog depth env heap (.loop condition body) n
  | loopNext {depth : Nat} {env middle : Env} {heap between : Heap} {condition : Expr} {body : Stmt} {n : Nat} :
      condition.eval env ≠ 0 → Exec prog depth env heap body (.normal middle between) →
      Stops prog depth middle between (.loop condition body) n →
      Stops prog depth env heap (.loop condition body) (n + 1)
  | loopContinued {depth : Nat} {env middle : Env} {heap between : Heap} {condition : Expr} {body : Stmt}
      {n : Nat} :
      condition.eval env ≠ 0 → Exec prog depth env heap body (.continued middle between) →
      Stops prog depth middle between (.loop condition body) n →
      Stops prog depth env heap (.loop condition body) (n + 1)
  | call {depth inner target count callee : Nat} {env : Env} {heap : Heap} {args : List Expr} {func : Func}
      {n : Nat} :
      prog.funcs[callee]? = some func → args.length = func.params → inner < depth →
      Stops prog inner (Func.entry (Expr.evalAll env args)) heap func.body n →
      Stops prog depth env heap (.call target count callee args) (n + 1)
  | alloc {depth : Nat} {env : Env} {heap : Heap} {target shift : Nat} {size : Expr} {n : Nat} :
      heap.cursor ≤ heap.limit → heap.limit < alignUp heap.cursor shift + (size.eval env).toNat →
      Stops prog depth env heap (.alloc target shift size) n
  | divide {depth : Nat} {env : Env} {heap : Heap} {word : Word} {operation : DivOp} {target : Nat}
      {left right : Expr} {n : Nat} :
      word.divides operation (left.eval env) (right.eval env) = false →
      Stops prog depth env heap (.divide word operation target left right) n

/-- Fewer ticks. -/
theorem Stops.mono (stops : Stops prog depth env heap stmt n) : ∀ {k}, k ≤ n → Stops prog depth env heap stmt k := by
  induction stops with
  | zero => intro k small; rw [Nat.le_zero.mp small]; exact .zero
  | seqFirst _ ih => exact fun small => .seqFirst (ih small)
  | seqSecond first _ ih => exact fun small => .seqSecond first (ih small)
  | ifTrue nonzero _ ih => exact fun small => .ifTrue nonzero (ih small)
  | ifFalse zero _ ih => exact fun small => .ifFalse zero (ih small)
  | loopBody nonzero _ ih => exact fun small => .loopBody nonzero (ih small)
  | loopNext nonzero body _ ih =>
    intro k small
    cases k with
    | zero => exact .zero
    | succ k => exact .loopNext nonzero body (ih (by omega))
  | loopContinued nonzero body _ ih =>
    intro k small
    cases k with
    | zero => exact .zero
    | succ k => exact .loopContinued nonzero body (ih (by omega))
  | call found length lower _ ih =>
    intro k small
    cases k with
    | zero => exact .zero
    | succ k => exact .call found length lower (ih (by omega))
  | alloc inside over => exact fun _ => .alloc inside over
  | divide undefined => exact fun _ => .divide undefined

/-- What a call may do that does not return: `stops callee args heap n`. -/
abbrev StopCalls := Nat → List (BitVec 64) → Heap → Nat → Prop

/-- The abstract machine stops at a failed allocation or division, or is still
running after `n` steps, a call that does not return counting one. -/
inductive AStops (calls : Calls) (stops : StopCalls) (code : List Instr) : Machine → Nat → Prop where
  | zero {m : Machine} : AStops calls stops code m 0
  | step {m next : Machine} {n : Nat} : Step calls code m next → AStops calls stops code next n →
      AStops calls stops code m (n + 1)
  | call {m : Machine} {callee : Nat} {args : List Nat} {target count n : Nat} :
      fetch code m.pc = some (.call callee args target count) → stops callee (readSlots m.slots args) m.heap n →
      AStops calls stops code m (n + 1)
  | bump {m : Machine} {shift n : Nat} : fetch code m.pc = some (.bump shift) → m.heap.cursor ≤ m.heap.limit →
      m.heap.limit < alignUp m.heap.cursor shift + m.acc.toNat → AStops calls stops code m n
  | div {m : Machine} {word : Word} {operation : DivOp} {slot n : Nat} :
      fetch code m.pc = some (.div word operation slot) →
      word.divides operation (m.slots slot) m.acc = false → AStops calls stops code m n

theorem AStops.mono {calls : Calls} {stops : StopCalls} {code : List Instr}
    (downward : ∀ callee args heap n k, stops callee args heap n → k ≤ n → stops callee args heap k)
    (run : AStops calls stops code m n) : ∀ {k}, k ≤ n → AStops calls stops code m k := by
  induction run with
  | zero => intro k small; rw [Nat.le_zero.mp small]; exact .zero
  | step head _ ih =>
    intro k small
    cases k with
    | zero => exact .zero
    | succ k => exact .step head (ih (by omega))
  | call fetched callee =>
    intro k small
    cases k with
    | zero => exact .zero
    | succ k => exact .call fetched (downward _ _ _ _ _ callee (by omega))
  | bump fetched inside over => exact fun _ => .bump fetched inside over
  | div fetched undefined => exact fun _ => .div fetched undefined

/-- A run, then a stop. -/
theorem AStops.star {calls : Calls} {stops : StopCalls} {code : List Instr}
    (downward : ∀ callee args heap n k, stops callee args heap n → k ≤ n → stops callee args heap k)
    (run : Star calls code m next) (rest : AStops calls stops code next n) : AStops calls stops code m n := by
  induction run with
  | refl => exact rest
  | step head _ ih => exact (AStops.step head (ih rest)).mono downward (by omega)

/-- A sub-block that ends normally, then a stop. -/
theorem AStops.after {calls : Calls} {stops : StopCalls} {code : List Instr} {m : Machine}
    (first : StmtResult calls code base innerPos innerBlock brk cont m (.normal middle between))
    (rest : ∀ m', Star calls code m m' → m'.pc = innerPos + codeSize innerBlock → Agree base middle m' →
      m'.heap = between → AStops calls stops code m n) :
    AStops calls stops code m n := by
  obtain ⟨m', steps, pc, agree, onHeap⟩ := first
  exact rest m' steps pc agree onHeap

/-- A sub-block that continues, then a stop. -/
theorem AStops.afterContinued {calls : Calls} {stops : StopCalls} {code : List Instr} {m : Machine}
    (first : StmtResult calls code base innerPos innerBlock brk cont m (.continued middle between))
    (rest : ∀ m', Star calls code m m' → m'.pc = cont → Agree base middle m' →
      m'.heap = between → AStops calls stops code m n) :
    AStops calls stops code m n := by
  obtain ⟨m', steps, pc, agree, onHeap⟩ := first
  exact rest m' steps pc agree onHeap

/-- What a call may do that does not return, in a derivation of depth `depth`. -/
def SourceStops (prog : Program) (depth : Nat) : StopCalls :=
  fun callee args heap n => ∃ inner, inner < depth ∧ ∃ func, prog.funcs[callee]? = some func ∧
    args.length = func.params ∧ Stops prog inner (Func.entry args) heap func.body n

theorem SourceStops.downward (prog : Program) (depth : Nat) :
    ∀ callee args heap n k, SourceStops prog depth callee args heap n → k ≤ n →
      SourceStops prog depth callee args heap k := by
  intro callee args heap n k ⟨inner, lower, func, found, length, stops⟩ small
  exact ⟨inner, lower, func, found, length, stops.mono small⟩

theorem compileStmt_stops {prog : Program} {base : Nat} {arities : List Arity} {results : Nat}
    {code : List Instr} {depth : Nat} {env : Env} {heap : Heap} {stmt : Stmt} {n : Nat}
    (stops : Stops prog depth env heap stmt n) :
    ∀ pos brk cont m, Block code pos (compileStmt base pos brk cont stmt) → m.pc = pos → Agree base env m →
      m.heap = heap → stmt.within base arities results = true →
      AStops (SourceCalls prog depth) (SourceStops prog depth) code m n := by
  induction stops with
  | zero => intros; exact .zero
  | seqFirst _ ihFirst =>
    intro pos brk cont m placed pc agree onHeap within
    simp only [Stmt.within, Bool.and_eq_true] at within
    simp only [compileStmt] at placed
    exact ihFirst pos brk cont m placed.left pc agree onHeap within.1
  | seqSecond first _ ihSecond =>
    intro pos brk cont m placed pc agree onHeap within
    simp only [Stmt.within, Bool.and_eq_true] at within
    simp only [compileStmt] at placed
    obtain ⟨m', steps, pc', agree', onHeap'⟩ :=
      compileStmt_correct first pos brk cont m placed.left pc agree onHeap within.1
    exact AStops.star (SourceStops.downward _ _) steps (ihSecond _ brk cont m' placed.right pc' agree' onHeap' within.2)
  | @ifTrue depth env heap condition thenBranch elseBranch n nonzero _ ihThen =>
    intro pos brk cont m placed pc agree onHeap within
    simp only [Stmt.within, Bool.and_eq_true] at within
    simp only [compileStmt] at placed
    obtain ⟨acc, kept⟩ := compileExpr_correct base condition 0 env m agree within.1.1
    apply AStops.star (SourceStops.downward _ _) (Star.straight _ (pc ▸ placed.left.left.left.left) (compileExpr_straight _ _ _))
    have jz := placed.left.left.left.right.fetch
    apply AStops.star (SourceStops.downward _ _) (.single (.jzNot (by rw [Instr.exec_pc, pc]; exact jz) (by rw [acc]; exact nonzero)))
    refine ihThen (pos + codeSize (compileExpr base condition 0) + 9) brk cont _ ?_ ?_ ?_
      ((Instr.exec_heap _ _).trans onHeap) within.1.2
    · exact placed.left.left.right.at (by simp only [codeSize_append, codeSize, Instr.size]; omega)
    · simp only [Instr.exec_pc, pc, Instr.size]
    · exact agree.of_slots fun slot below => kept slot (by omega)
  | @ifFalse depth env heap condition thenBranch elseBranch n zero _ ihElse =>
    intro pos brk cont m placed pc agree onHeap within
    simp only [Stmt.within, Bool.and_eq_true] at within
    simp only [compileStmt] at placed
    obtain ⟨acc, kept⟩ := compileExpr_correct base condition 0 env m agree within.1.1
    apply AStops.star (SourceStops.downward _ _) (Star.straight _ (pc ▸ placed.left.left.left.left) (compileExpr_straight _ _ _))
    have jz := placed.left.left.left.right.fetch
    apply AStops.star (SourceStops.downward _ _) (.single (.jzTaken (by rw [Instr.exec_pc, pc]; exact jz) (by rw [acc]; exact zero)))
    refine ihElse (pos + codeSize (compileExpr base condition 0) + 9 +
      codeSize (compileStmt base (pos + codeSize (compileExpr base condition 0) + 9) brk cont thenBranch) + 5)
      brk cont _ ?_ rfl ?_ ((Instr.exec_heap _ _).trans onHeap) within.2
    · exact placed.right.at (by simp only [codeSize_append, codeSize, Instr.size]; omega)
    · exact agree.of_slots fun slot below => kept slot (by omega)
  | @loopBody depth env heap condition body n nonzero _ ihBody =>
    intro pos brk cont m placed pc agree onHeap within
    simp only [Stmt.within, Bool.and_eq_true] at within
    simp only [compileStmt] at placed
    obtain ⟨acc, kept⟩ := compileExpr_correct base condition 0 env m agree within.1
    apply AStops.star (SourceStops.downward _ _) (Star.straight _ (pc ▸ placed.left.left.left) (compileExpr_straight _ _ _))
    have jz := placed.left.left.right.fetch
    apply AStops.star (SourceStops.downward _ _) (.single (.jzNot (by rw [Instr.exec_pc, pc]; exact jz) (by rw [acc]; exact nonzero)))
    refine ihBody (pos + codeSize (compileExpr base condition 0) + 9) (pos + codeSize (compileExpr base condition 0)) pos _ ?_ ?_ ?_
      ((Instr.exec_heap _ _).trans onHeap) within.2
    · exact placed.left.right.at (by simp only [codeSize_append, codeSize, Instr.size]; omega)
    · simp only [Instr.exec_pc, pc, Instr.size]
    · exact agree.of_slots fun slot below => kept slot (by omega)
  | @loopNext depth env middle heap between condition body n nonzero bodyExec _ ihLoop =>
    intro pos brk cont m placed pc agree onHeap within
    have loopWithin := within
    simp only [Stmt.within, Bool.and_eq_true] at within
    have placedLoop := placed
    simp only [compileStmt] at placed
    obtain ⟨acc, kept⟩ := compileExpr_correct base condition 0 env m agree within.1
    apply AStops.star (SourceStops.downward _ _) (Star.straight _ (pc ▸ placed.left.left.left) (compileExpr_straight _ _ _))
    have jz := placed.left.left.right.fetch
    apply AStops.star (SourceStops.downward _ _) (.single (.jzNot (by rw [Instr.exec_pc, pc]; exact jz) (by rw [acc]; exact nonzero)))
    refine AStops.after (compileStmt_correct bodyExec (pos + codeSize (compileExpr base condition 0) + 9)
      (pos + codeSize (compileExpr base condition 0)) pos _
      (placed.left.right.at (by simp only [codeSize_append, codeSize, Instr.size]; omega))
      (by simp only [Instr.exec_pc, pc, Instr.size])
      (agree.of_slots fun slot below => kept slot (by omega)) ((Instr.exec_heap _ _).trans onHeap) within.2) ?_
    intro m' steps pc' agree' onHeap'
    apply AStops.star (SourceStops.downward _ _) steps
    refine .step (.jmp (placed.right.at (by
      rw [pc']; simp only [codeSize_append, codeSize, Instr.size]; omega)).fetch) ?_
    exact ihLoop pos brk cont { m' with pc := pos } placedLoop rfl agree' onHeap' loopWithin
  | @loopContinued depth env middle heap between condition body n nonzero bodyExec _ ihLoop =>
    intro pos brk cont m placed pc agree onHeap within
    have loopWithin := within
    simp only [Stmt.within, Bool.and_eq_true] at within
    have placedLoop := placed
    simp only [compileStmt] at placed
    obtain ⟨acc, kept⟩ := compileExpr_correct base condition 0 env m agree within.1
    apply AStops.star (SourceStops.downward _ _) (Star.straight _ (pc ▸ placed.left.left.left) (compileExpr_straight _ _ _))
    have jz := placed.left.left.right.fetch
    refine .step (.jzNot (by rw [Instr.exec_pc, pc]; exact jz) (by rw [acc]; exact nonzero)) ?_
    refine AStops.afterContinued (compileStmt_correct bodyExec (pos + codeSize (compileExpr base condition 0) + 9)
      (pos + codeSize (compileExpr base condition 0)) pos _
      (placed.left.right.at (by simp only [codeSize_append, codeSize, Instr.size]; omega))
      (by simp only [Instr.exec_pc, pc, Instr.size])
      (agree.of_slots fun slot below => kept slot (by omega)) ((Instr.exec_heap _ _).trans onHeap) within.2) ?_
    intro m' steps pc' agree' onHeap'
    exact AStops.star (SourceStops.downward _ _) steps (ihLoop pos brk cont m' placedLoop pc' agree' onHeap' loopWithin)
  | @call depth inner target count callee env heap args func n lookup length lower _ _ =>
    intro pos brk cont m placed pc agree onHeap within
    simp only [Stmt.within, Bool.and_eq_true, decide_eq_true_eq] at within
    simp only [compileStmt] at placed
    obtain ⟨values, -⟩ := compileArgs_correct base args 0 env m agree within.2
    apply AStops.star (SourceStops.downward _ _) (Star.straight _ (pc ▸ placed.left) (compileArgs_straight _ _ _))
    refine .call (by rw [Instr.exec_pc, pc]; exact placed.right.fetch) ?_
    rw [values, Instr.exec_heap, onHeap]
    exact ⟨inner, lower, func, lookup, by rw [evalAll_length, length], by assumption⟩
  | @alloc depth env heap target shift size n inside over =>
    intro pos brk cont m placed pc agree onHeap within
    simp only [Stmt.within, Bool.and_eq_true, decide_eq_true_eq] at within
    simp only [compileStmt] at placed
    obtain ⟨acc, -⟩ := compileExpr_correct base size 0 env m agree within.2
    apply AStops.star (SourceStops.downward _ _) (Star.straight _ (pc ▸ placed.left) (compileExpr_straight _ _ _))
    obtain ⟨bumpAt, -⟩ := placed.right.pair
    have heapAt := (Instr.exec_heap (compileExpr base size 0) m).trans onHeap
    exact .bump (by rw [Instr.exec_pc, pc]; exact bumpAt.fetch) (by rw [heapAt]; exact inside)
      (by rw [heapAt, acc]; exact over)
  | @divide depth env heap word operation target left right n undefined =>
    intro pos brk cont m placed pc agree onHeap within
    simp only [Stmt.within, Bool.and_eq_true, decide_eq_true_eq] at within
    simp only [compileStmt] at placed
    obtain ⟨kept, acc, -⟩ := operands_correct base 0 env m agree _ _ _ _
      (fun m agree => compileExpr_correct base left 0 env m agree within.1.2)
      (fun m agree => compileExpr_correct base right 1 env m agree within.2)
    simp only [Nat.add_zero] at kept acc
    apply AStops.star (SourceStops.downward _ _) (Star.straight _ (pc ▸ placed.left)
      (by simp only [List.all_append, compileExpr_straight]; rfl))
    obtain ⟨divAt, -⟩ := placed.right.pair
    exact .div (by rw [Instr.exec_pc, pc]; exact divAt.fetch) (by rw [kept, acc]; exact undefined)

/-- A compiled function, entered with its parameters in the first slots, runs
as long as the source body. -/
theorem compileFunc_stops {arities : List Arity} {func : Func} {code : Code}
    (compiled : compileFunc arities func = some code) {prog : Program} {depth : Nat}
    {args : List (BitVec 64)} {heap : Heap} {n : Nat} (length : args.length = func.params)
    (stops : Stops prog depth (Func.entry args) heap func.body n) (m : Machine)
    (start : m.pc = 0) (onHeap : m.heap = heap)
    (params : ∀ index, index < func.params → m.slots index = args.getD index 0) :
    AStops (SourceCalls prog depth) (SourceStops prog depth) code.instrs m n := by
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
  exact AStops.star (SourceStops.downward prog depth) initRun
    (compileStmt_stops stops (code := init ++ compileStmt func.locals (codeSize init) 0 0 func.body)
      (codeSize init) 0 0 (Instr.exec init m) bodyPlaced (by rw [Instr.exec_pc, start]; omega) agree
      ((Instr.exec_heap _ _).trans onHeap) within)

end Lanius.Mini
