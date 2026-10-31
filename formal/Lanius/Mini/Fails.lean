import Lanius.Mini.Stops
import Lanius.Mini.LowerEval
import Lanius.Semantics.Fuel

/-! Core runs that do not complete. A run `Fails` when no fuel completes it
with the heap within the mini heap's limit and no fuel reaches an undefined
trap (a raw memory error, which the theorem excludes as CompCert excludes
undefined behaviour): it runs out of every fuel, stops at a checked or an
impossible trap, or completes past the limit. Every sub-run of a failing run
either completes within the limit (and the forward simulation covers it) or
fails itself (`failing_of_not_completes`), and what follows a sub-run that
completes fails from there (`failing_after`). The mini side of a failing run
is `Stops` for every number of ticks. -/

namespace Lanius.Mini

open Lanius.Semantics (State Completion)

/-- The traps the compiled code does not check: raw memory errors, and
`typeMismatch`, which a typed program reaches only by reading an invalid bit
pattern from raw memory or by a raw slice of an element type past Core's
native layout limits. -/
def undefinedTrap : Lanius.Trap → Bool
  | .arrayBounds => false
  | .invalidShift => false
  | .divisionByZero => false
  | .signedDivisionOverflow => false
  | .invalidPointer => true
  | .rawMemoryBounds => true
  | .doubleFree => true
  | .allocatorContract => true
  | .allocationFailure => false
  | .entropyExhausted => false
  | .assertionFailed => false
  | .nonExhaustiveMatch => false
  | .uninitializedLocal => false
  | .missingReturn => false
  | .serviceUnavailable _ => false
  | .panic => false
  | .reachedUnreachable => false
  | .unmodeledExtern _ => false
  | .typeMismatch => true

/-- A Core result that is not a completion within `limit` or an undefined
trap within `limit`. -/
def Failing {α : Type} (limit : Nat) : Semantics.Outcome α → Prop
  | .done _ st => limit < st.heap.nextAddress
  | .trapped reason st => undefinedTrap reason = false ∨ limit < st.heap.nextAddress
  | .exited _ _ => True
  | .outOfFuel => True

/-- A failing trap within the limit is not an undefined one. -/
theorem trap_within {r : Lanius.Trap} {a limit : Nat} (h : undefinedTrap r = false ∨ limit < a)
    (u : undefinedTrap r = true) (w : a ≤ limit) : False := by
  rcases h with h | h
  · rw [u] at h; cases h
  · omega

/-- Some fuel completes the run with the heap within `limit`. -/
def Completes {α : Type} (limit : Nat) (run : Nat → Semantics.Outcome α) : Prop :=
  ∃ k v st, run k = .done v st ∧ st.heap.nextAddress ≤ limit

/-- Core's run of a statement fails at every fuel. -/
abbrev Fails (sp : SrcProgram) (limit : Nat) (st : State) (s : Core.Stmt) : Prop :=
  ∀ fuel, Failing limit (Semantics.execStmt fuel sp.toCore st s)

/-- Core's evaluation of an expression fails at every fuel. -/
abbrev EFails (sp : SrcProgram) (limit : Nat) (st : State) (e : Core.Expr) : Prop :=
  ∀ fuel, Failing limit (Semantics.evalExpr fuel sp.toCore st e)

theorem failing_outOfFuel {α : Type} {limit : Nat} : Failing limit (Semantics.Outcome.outOfFuel : Semantics.Outcome α) := trivial

/-- A sub-run of a failing run that never completes within the limit fails:
its traps are the whole run's. -/
theorem failing_of_not_completes {α β : Type} {limit : Nat} {sub : Nat → Semantics.Outcome α} {whole : Nat → Semantics.Outcome β}
    (fails : ∀ j, Failing limit (whole j))
    (propagate : ∀ j reason st, sub j = .trapped reason st →
      ∃ j' st', whole j' = .trapped reason st' ∧ st'.heap.nextAddress = st.heap.nextAddress)
    (none : ¬Completes limit sub) : ∀ j, Failing limit (sub j) := by
  intro j
  cases h : sub j with
  | done v s =>
    show limit < s.heap.nextAddress
    exact Nat.lt_of_not_le fun le => none ⟨j, v, s, h, le⟩
  | trapped reason s =>
    obtain ⟨j', s', w, same⟩ := propagate j reason s h
    have := fails j'
    rw [w] at this
    show undefinedTrap reason = false ∨ limit < s.heap.nextAddress
    rw [← same]
    exact this
  | exited => trivial
  | outOfFuel => trivial

/-- A run that fails from some fuel on fails at every fuel: less fuel runs out
or gives the same result. -/
theorem failing_after {α : Type} {limit : Nat} {run : Nat → Semantics.Outcome α}
    (mono : ∀ {a b : Nat}, a ≤ b → (run a).Refines (run b)) {k : Nat}
    (late : ∀ j, k ≤ j → Failing limit (run j)) : ∀ j, Failing limit (run j) := by
  intro j
  by_cases le : k ≤ j
  · exact late j le
  · rcases mono (Nat.le_of_not_le le) with h | h
    · rw [h]; trivial
    · rw [← h]; exact late k (Nat.le_refl _)

theorem stmt_mono {sp : SrcProgram} {st : State} {s : Core.Stmt} :
    ∀ {a b : Nat}, a ≤ b → (Semantics.execStmt a sp.toCore st s).Refines (Semantics.execStmt b sp.toCore st s) :=
  fun le => Semantics.execStmt_refines le

theorem expr_mono {sp : SrcProgram} {st : State} {e : Core.Expr} :
    ∀ {a b : Nat}, a ≤ b → (Semantics.evalExpr a sp.toCore st e).Refines (Semantics.evalExpr b sp.toCore st e) :=
  fun le => Semantics.evalExpr_refines le

theorem exprs_mono {sp : SrcProgram} {st : State} {es : List Core.Expr} :
    ∀ {a b : Nat}, a ≤ b →
      (Semantics.evalExprs a sp.toCore st es).Refines (Semantics.evalExprs b sp.toCore st es) :=
  fun le => Semantics.evalExprs_refines le

/-- A completed run gives the same result with more fuel. -/
theorem done_after {sp : SrcProgram} {st : State} {s : Core.Stmt} {k : Nat} {c : Completion} {st' : State}
    (run : Semantics.execStmt k sp.toCore st s = .done c st') {j : Nat} (le : k ≤ j) :
    Semantics.execStmt j sp.toCore st s = .done c st' :=
  Semantics.execStmt_of_le run (by intro h; cases h) le

theorem value_after {sp : SrcProgram} {st : State} {e : Core.Expr} {k : Nat} {v : Core.Value} {st' : State}
    (run : Semantics.evalExpr k sp.toCore st e = .done v st') {j : Nat} (le : k ≤ j) :
    Semantics.evalExpr j sp.toCore st e = .done v st' :=
  Semantics.evalExpr_of_le run (by intro h; cases h) le

theorem values_after {sp : SrcProgram} {st : State} {es : List Core.Expr} {k : Nat} {vs : List Core.Value}
    {st' : State} (run : Semantics.evalExprs k sp.toCore st es = .done vs st') {j : Nat} (le : k ≤ j) :
    Semantics.evalExprs j sp.toCore st es = .done vs st' :=
  (run ▸ Semantics.evalExprs_refines (program := sp.toCore) (state := st) (expressions := es) le).completed
    (by intro h; cases h)

/-! ## The mini side -/

/-- More call depth. -/
theorem Stops.deeper {prog : Program} {d : Nat} {env : Env} {hp : Heap} {s : Stmt} {n : Nat}
    (stops : Stops prog d env hp s n) {d' : Nat} (le : d ≤ d') : Stops prog d' env hp s n := by
  induction stops with
  | zero => exact .zero
  | seqFirst _ ih => exact .seqFirst (ih le)
  | seqSecond first _ ih => exact .seqSecond (first.mono le) (ih le)
  | ifTrue nonzero _ ih => exact .ifTrue nonzero (ih le)
  | ifFalse zero _ ih => exact .ifFalse zero (ih le)
  | loopBody nonzero _ ih => exact .loopBody nonzero (ih le)
  | loopNext nonzero body _ ih => exact .loopNext nonzero (body.mono le) (ih le)
  | loopContinued nonzero body _ ih => exact .loopContinued nonzero (body.mono le) (ih le)
  | call found length lower body => exact .call found length (Nat.lt_of_lt_of_le lower le) body
  | alloc inside over => exact .alloc inside over
  | divide undefined => exact .divide undefined

/-- `1 / 0` stops. -/
theorem Stops.trap {prog : Program} {d : Nat} {env : Env} {hp : Heap} {slot n : Nat} :
    Stops prog d env hp (trap slot) n :=
  .divide (by simp [Expr.eval, Word.divides, DivOp.defined])

/-- A check that fails stops; one that passes runs the statement. -/
theorem Stops.check {prog : Program} {d : Nat} {env : Env} {hp : Heap} {s : Stmt} {n slot : Nat} {g : Expr}
    (pass : g.eval env ≠ 0 → Stops prog d env hp s n) : Stops prog d env hp (checkThen slot g s) n := by
  unfold checkThen
  split
  · rename_i one
    exact pass (by rw [isOne_eval one]; decide)
  · by_cases zero : g.eval env = 0
    · exact .ifFalse zero .trap
    · exact .ifTrue zero (pass zero)

theorem Stops.assignFrom {prog : Program} {d : Nat} {hp : Heap} {rest : Stmt} {n : Nat} :
    ∀ (xs : List Expr) (slot : Nat) {env : Env}, Stops prog d (env.setFrom slot xs) hp rest n →
      Stops prog d env hp (assignFrom slot xs rest) n
  | [], _, _, stops => stops
  | _ :: more, slot, _, stops => .seqSecond .assign (Stops.assignFrom more (slot + 1) stops)

/-- A prefix that ends normally, then a stop. -/
theorem Stops.after {prog : Program} {d d' : Nat} {env env' : Env} {hp hp' : Heap} {first second : Stmt} {n : Nat}
    (exec : Exec prog d env hp first (.normal env' hp')) (stops : Stops prog d' env' hp' second n) :
    Stops prog (max d d') env hp (.seq first second) n :=
  .seqSecond (exec.mono (Nat.le_max_left _ _)) (stops.deeper (Nat.le_max_right _ _))

/-! ## Failing statements -/

section Transfer

open Semantics (execStmt evalExpr)

variable {sp : SrcProgram} {L : Nat} {st : State}

theorem failing_restore {α : Type} (caller : State) (r : Semantics.Outcome α) :
    Failing L (Semantics.restoreOutcomeLocals caller r) ↔ Failing L r := by
  cases r <;> simp [Semantics.restoreOutcomeLocals, Failing, Semantics.restoreLocals]

theorem Fails.expression {e : Core.Expr} (fails : Fails sp L st (.expression e)) : EFails sp L st e := by
  intro j
  have := fails (j + 1)
  simp only [execStmt] at this
  cases h : evalExpr j sp.toCore st e <;> rw [h] at this <;> first | exact this | trivial

theorem Fails.seqFirst {a b : Core.Stmt} (fails : Fails sp L st (.sequence a b))
    (none : ¬Completes L fun k => execStmt k sp.toCore st a) : Fails sp L st a :=
  failing_of_not_completes fails (fun j reason s h => ⟨j + 1, s, by simp only [execStmt, h], rfl⟩) none

theorem Fails.seqSecond {a b : Core.Stmt} (fails : Fails sp L st (.sequence a b)) {k : Nat} {st1 : State}
    (run : execStmt k sp.toCore st a = .done .next st1) : Fails sp L st1 b :=
  failing_after stmt_mono (k := k) fun j le => by
    have := fails (j + 1)
    simp only [execStmt, done_after run le] at this
    exact this

theorem Fails.letInit {id : Nat} {ty : Core.Ty} {init : Core.Expr} {body : Core.Stmt}
    (fails : Fails sp L st (.letLocal id ty init body))
    (none : ¬Completes L fun k => evalExpr k sp.toCore st init) : EFails sp L st init :=
  failing_of_not_completes fails (fun j reason s h => ⟨j + 1, s, by simp only [execStmt, h], rfl⟩) none

theorem Fails.letBody {id : Nat} {ty : Core.Ty} {init : Core.Expr} {body : Core.Stmt}
    (fails : Fails sp L st (.letLocal id ty init body)) {k : Nat} {v : Core.Value} {st1 : State}
    (run : evalExpr k sp.toCore st init = .done v st1) : Fails sp L (st1.bindLocal id v) body :=
  failing_after stmt_mono (k := k) fun j le => by
    have := fails (j + 1)
    simp only [execStmt, value_after run le] at this
    exact (failing_restore _ _).mp this

theorem Fails.ifCond {c : Core.Expr} {a b : Core.Stmt} (fails : Fails sp L st (.ifThenElse c a b))
    (none : ¬Completes L fun k => evalExpr k sp.toCore st c) : EFails sp L st c :=
  failing_of_not_completes fails (fun j reason s h => ⟨j + 1, s, by simp only [execStmt, h], rfl⟩) none

theorem Fails.ifBranch {c : Core.Expr} {a b : Core.Stmt} (fails : Fails sp L st (.ifThenElse c a b))
    {k : Nat} {x : Bool} {st1 : State} (run : evalExpr k sp.toCore st c = .done (.boolean x) st1) :
    Fails sp L st1 (if x then a else b) :=
  failing_after stmt_mono (k := k) fun j le => by
    have := fails (j + 1)
    cases x <;> simp only [execStmt, value_after run le] at this <;> exact this

theorem Fails.whileCond {c : Core.Expr} {body : Core.Stmt} (fails : Fails sp L st (.whileLoop c body))
    (none : ¬Completes L fun k => evalExpr k sp.toCore st c) : EFails sp L st c :=
  failing_of_not_completes fails (fun j reason s h => ⟨j + 1, s, by simp only [execStmt, h], rfl⟩) none

theorem Fails.whileBody {c : Core.Expr} {body : Core.Stmt} (fails : Fails sp L st (.whileLoop c body))
    {k : Nat} {st1 : State} (run : evalExpr k sp.toCore st c = .done (.boolean true) st1)
    (none : ¬Completes L fun k => execStmt k sp.toCore st1 body) : Fails sp L st1 body :=
  failing_of_not_completes fails (fun j reason s h => ⟨max k j + 1, s, by
    simp only [execStmt, value_after run (Nat.le_max_left k j),
      Semantics.execStmt_of_le h (by intro h; cases h) (Nat.le_max_right k j)], rfl⟩) none

theorem Fails.whileNext {c : Core.Expr} {body : Core.Stmt} (fails : Fails sp L st (.whileLoop c body))
    {k : Nat} {st1 : State} (run : evalExpr k sp.toCore st c = .done (.boolean true) st1)
    {k' : Nat} {st2 : State} (next : execStmt k' sp.toCore st1 body = .done .next st2) :
    Fails sp L st2 (.whileLoop c body) :=
  failing_after stmt_mono (k := max k k') fun j le => by
    have := fails (j + 1)
    simp only [execStmt, value_after run (Nat.le_trans (Nat.le_max_left k k') le),
      done_after next (Nat.le_trans (Nat.le_max_right k k') le)] at this
    exact this

theorem Fails.returnValue {e : Core.Expr} (fails : Fails sp L st (.returnValue (some e))) : EFails sp L st e := by
  intro j
  have := fails (j + 1)
  simp only [execStmt] at this
  cases h : evalExpr j sp.toCore st e <;> rw [h] at this <;> first | exact this | trivial

/-- A completed sub-run that the whole run then completes from contradicts
failing. -/
theorem Fails.not_done {s : Core.Stmt} (fails : Fails sp L st s) {k : Nat} {c : Completion} {st' : State}
    (run : execStmt k sp.toCore st s = .done c st') (within : st'.heap.nextAddress ≤ L) : False := by
  have := fails k
  rw [run] at this
  exact Nat.lt_irrefl _ (Nat.lt_of_lt_of_le this within)

theorem EFails.not_done {e : Core.Expr} (fails : EFails sp L st e) {k : Nat} {v : Core.Value} {st' : State}
    (run : evalExpr k sp.toCore st e = .done v st') (within : st'.heap.nextAddress ≤ L) : False := by
  have := fails k
  rw [run] at this
  exact Nat.lt_irrefl _ (Nat.lt_of_lt_of_le this within)

end Transfer

end Lanius.Mini
