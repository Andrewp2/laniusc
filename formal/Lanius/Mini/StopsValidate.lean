import Lanius.Mini.Validate
import Lanius.Mini.StopsCorrect

/-! The validator keeps runs that do not return: when `validate p q = true`,
a call that is `Stops` in `p` is `Stops` in `q` for the same `n` and depth
(`Program.Stops.validated`), so `compileOptimized_stops` has the premises of
`compileProgram_stops`. The proof follows `Exec.agrees`. -/

namespace Lanius.Mini
open Lanius.X86.Machine

theorem Stops.skip_inv {prog : Program} {depth : Nat} {env : Env} {heap : Heap} {n : Nat}
    (stops : Stops prog depth env heap .skip n) : n = 0 := by
  cases stops; rfl

theorem Stops.assign_inv {prog : Program} {depth : Nat} {env : Env} {heap : Heap} {index : Nat} {value : Expr}
    {n : Nat} (stops : Stops prog depth env heap (.assign index value) n) : n = 0 := by
  cases stops; rfl

theorem Stops.ret_inv {prog : Program} {depth : Nat} {env : Env} {heap : Heap} {values : List Expr} {n : Nat}
    (stops : Stops prog depth env heap (.ret values) n) : n = 0 := by
  cases stops; rfl

/-- A statement that ignores `index` stops alike from environments that differ only there. -/
theorem Stops.ignores {prog : Program} {depth : Nat} {env : Env} {heap : Heap} {s : Stmt} {n : Nat}
    (stops : Stops prog depth env heap s n) {index : Nat} :
    s.ignores index = true → ∀ env2, Env.Except index env env2 → Stops prog depth env2 heap s n := by
  induction stops with
  | zero => intros; exact .zero
  | seqFirst _ ih =>
    intro p env2 h
    simp only [Stmt.ignores, Bool.and_eq_true] at p
    exact .seqFirst (ih p.1 env2 h)
  | seqSecond first _ ih =>
    intro p env2 h
    simp only [Stmt.ignores, Bool.and_eq_true] at p
    obtain ⟨o1, r1, rel1⟩ := Exec.ignores first p.1 env2 h
    cases o1 with
    | normal m2 h2 =>
      obtain ⟨rfl, e⟩ := rel1
      exact .seqSecond r1 (ih p.2 m2 e)
    | returned | broke | continued => simp [Outcome.Except] at rel1
  | @ifTrue depth env heap condition _ _ _ holds _ ih =>
    intro p env2 h
    simp only [Stmt.ignores, Bool.and_eq_true, Bool.not_eq_eq_eq_not, Bool.not_true] at p
    exact .ifTrue (by rw [← Expr.eval_except h condition p.1.1]; exact holds) (ih p.1.2 env2 h)
  | @ifFalse depth env heap condition _ _ _ holds _ ih =>
    intro p env2 h
    simp only [Stmt.ignores, Bool.and_eq_true, Bool.not_eq_eq_eq_not, Bool.not_true] at p
    exact .ifFalse (by rw [← Expr.eval_except h condition p.1.1]; exact holds) (ih p.2 env2 h)
  | @loopBody depth env heap condition body _ holds _ ih =>
    intro p env2 h
    simp only [Stmt.ignores, Bool.and_eq_true, Bool.not_eq_eq_eq_not, Bool.not_true] at p
    exact .loopBody (by rw [← Expr.eval_except h condition p.1]; exact holds) (ih p.2 env2 h)
  | @loopNext depth env middle heap between condition body _ holds bodyRun _ ih =>
    intro p env2 h
    have p' := p
    simp only [Stmt.ignores, Bool.and_eq_true, Bool.not_eq_eq_eq_not, Bool.not_true] at p'
    obtain ⟨o1, r1, rel1⟩ := Exec.ignores bodyRun p'.2 env2 h
    cases o1 with
    | normal m2 h2 =>
      obtain ⟨rfl, e⟩ := rel1
      exact .loopNext (by rw [← Expr.eval_except h condition p'.1]; exact holds) r1 (ih p m2 e)
    | returned | broke | continued => simp [Outcome.Except] at rel1
  | @loopContinued depth env middle heap between condition body _ holds bodyRun _ ih =>
    intro p env2 h
    have p' := p
    simp only [Stmt.ignores, Bool.and_eq_true, Bool.not_eq_eq_eq_not, Bool.not_true] at p'
    obtain ⟨o1, r1, rel1⟩ := Exec.ignores bodyRun p'.2 env2 h
    cases o1 with
    | continued m2 h2 =>
      obtain ⟨rfl, e⟩ := rel1
      exact .loopContinued (by rw [← Expr.eval_except h condition p'.1]; exact holds) r1 (ih p m2 e)
    | normal | returned | broke => simp [Outcome.Except] at rel1
  | @call depth inner target count callee env heap args func _ found len lt body _ =>
    intro p env2 h
    simp only [Stmt.ignores, Bool.not_eq_eq_eq_not, Bool.not_true] at p
    refine .call found len lt ?_
    rw [← Expr.evalAll_except h args p]
    exact body
  | @alloc depth env heap target shift size _ inside over =>
    intro p env2 h
    simp only [Stmt.ignores, Bool.not_eq_eq_eq_not, Bool.not_true] at p
    rw [Expr.eval_except h size p] at over
    exact .alloc inside over
  | @divide depth env heap word operation target left right _ undefined =>
    intro p env2 h
    simp only [Stmt.ignores, Bool.and_eq_true, Bool.not_eq_eq_eq_not, Bool.not_true] at p
    rw [Expr.eval_except h left p.1, Expr.eval_except h right p.2] at undefined
    exact .divide undefined

/-- A statement that kills `index` stops alike whatever `index` holds on entry. -/
theorem Stops.killed {prog : Program} (s : Stmt) :
    ∀ {index depth : Nat} {env : Env} {heap : Heap} {n : Nat}, s.kills index = true →
      Stops prog depth env heap s n → ∀ env2, Env.Except index env env2 → Stops prog depth env2 heap s n := by
  induction s with
  | skip => intro _ _ _ _ _ k; simp [Stmt.kills] at k
  | assign target value =>
    intro _ _ _ _ _ _ stops _ _
    rw [stops.assign_inv]
    exact .zero
  | seq first second ih1 ih2 =>
    intro index _ _ _ _ k stops env2 h
    simp only [Stmt.kills, Bool.or_eq_true, Bool.and_eq_true] at k
    cases stops with
    | zero => exact .zero
    | seqFirst r1 =>
      rcases k with k | ⟨⟨p, _⟩, _⟩
      · exact .seqFirst (ih1 k r1 env2 h)
      · exact .seqFirst (r1.ignores p env2 h)
    | seqSecond r1 r2 =>
      rcases k with k | ⟨⟨p, _⟩, k⟩
      · exact .seqSecond (Exec.killed _ k r1 env2 h) r2
      · obtain ⟨o1, r1', rel⟩ := Exec.ignores r1 p env2 h
        cases o1 with
        | normal m2 h2 =>
          obtain ⟨rfl, e⟩ := rel
          exact .seqSecond r1' (ih2 k r2 m2 e)
        | returned | broke | continued => simp [Outcome.Except] at rel
  | ite condition thenBranch elseBranch ihThen ihElse =>
    intro index _ _ _ _ k stops env2 h
    simp only [Stmt.kills, Bool.and_eq_true, Bool.not_eq_eq_eq_not, Bool.not_true] at k
    cases stops with
    | zero => exact .zero
    | ifTrue holds r =>
      exact .ifTrue (by rw [← Expr.eval_except h condition k.1.1]; exact holds) (ihThen k.1.2 r env2 h)
    | ifFalse holds r =>
      exact .ifFalse (by rw [← Expr.eval_except h condition k.1.1]; exact holds) (ihElse k.2 r env2 h)
  | loop => intro _ _ _ _ _ k; simp [Stmt.kills] at k
  | call => intro _ _ _ _ _ k; simp [Stmt.kills] at k
  | ret values =>
    intro _ _ _ _ _ _ stops _ _
    rw [stops.ret_inv]
    exact .zero
  | alloc => intro _ _ _ _ _ k; simp [Stmt.kills] at k
  | loadByte => intro _ _ _ _ _ k; simp [Stmt.kills] at k
  | storeByte => intro _ _ _ _ _ k; simp [Stmt.kills] at k
  | loadWord => intro _ _ _ _ _ k; simp [Stmt.kills] at k
  | storeWord => intro _ _ _ _ _ k; simp [Stmt.kills] at k
  | divide => intro _ _ _ _ _ k; simp [Stmt.kills] at k
  | brk => intro _ _ _ _ _ k; simp [Stmt.kills] at k
  | cont => intro _ _ _ _ _ k; simp [Stmt.kills] at k

/-- Every stop of an original statement from an environment where `facts`
hold is a stop of the statement the validator accepted, for the same `n`. -/
theorem Stops.agrees {p q : Program} (ok : funcsAgree p.funcs q.funcs = true) {depth : Nat} {env : Env}
    {heap : Heap} {s : Stmt} {n : Nat} (stops : Stops p depth env heap s n) :
    ∀ facts s', Facts.Hold env facts → s.agrees facts s' = true → Stops q depth env heap s' n := by
  induction stops with
  | zero => intros; exact .zero
  | seqFirst r1 ih =>
    intro facts s' hold h
    rcases seqAgrees_cases h with ⟨skip, _⟩ | ⟨_, kept⟩ | ⟨index, value, rfl, _, _⟩ | ⟨f, g, rfl, hf, _⟩
    · rw [(ih _ _ hold skip).skip_inv]
      exact .zero
    · exact ih _ _ hold kept
    · rw [r1.assign_inv]
      exact .zero
    · exact .seqFirst (ih _ _ hold hf)
  | seqSecond r1 _ ih =>
    intro facts s' hold h
    have hold' := Stmt.factsAfter_hold _ hold r1
    rcases seqAgrees_cases h with ⟨skip, rest⟩ | ⟨skip, _⟩ | ⟨index, value, rfl, kills, rest⟩ |
        ⟨f, g, rfl, hf, hg⟩
    · cases Exec.skip_inv (Exec.agrees ok r1 _ _ hold skip)
      exact ih _ _ hold' rest
    · rw [(ih _ _ hold' skip).skip_inv]
      exact .zero
    · cases r1
      exact Stops.killed _ kills (ih _ _ (assigned_hold hold index value) rest) _ (Env.Except.set_left _)
    · exact .seqSecond (Exec.agrees ok r1 _ _ hold hf) (ih _ _ hold' hg)
  | @ifTrue depth env heap condition _ _ _ holds _ ih =>
    intro facts s' hold h
    rcases iteAgrees_cases h with ⟨both, _⟩ | ⟨v, known, ⟨zero, _⟩ | ⟨_, chosen⟩⟩ |
        ⟨c, t, e, rfl, hc, ht, _⟩
    · exact ih _ _ hold both
    · exact absurd (by rw [← Expr.subst_eval hold condition, Expr.constant_eval env _ known, zero]) holds
    · exact ih _ _ hold chosen
    · exact .ifTrue (by rw [Expr.agrees_eval _ _ hc env, Expr.subst_eval hold]; exact holds) (ih _ _ hold ht)
  | @ifFalse depth env heap condition _ _ _ holds _ ih =>
    intro facts s' hold h
    rcases iteAgrees_cases h with ⟨_, both⟩ | ⟨v, known, ⟨_, chosen⟩ | ⟨nonzero, _⟩⟩ |
        ⟨c, t, e, rfl, hc, _, he⟩
    · exact ih _ _ hold both
    · exact ih _ _ hold chosen
    · exact absurd (by rw [← Expr.constant_eval env _ known, Expr.subst_eval hold, holds]) nonzero
    · exact .ifFalse (by rw [Expr.agrees_eval _ _ hc env, Expr.subst_eval hold]; exact holds) (ih _ _ hold he)
  | @loopBody depth env heap condition body _ holds _ ih =>
    intro facts s' _ h
    rcases loopAgrees_cases h with ⟨zero, rfl⟩ | ⟨c, b, rfl, hc, hb⟩
    · exact absurd (Expr.isZero_eval zero env) holds
    · exact .loopBody (by rw [Expr.agrees_eval _ _ hc env]; exact holds) (ih _ _ (Facts.Hold.nil _) hb)
  | @loopNext depth env middle heap between condition body _ holds bodyRun _ ih =>
    intro facts s' _ h
    rcases loopAgrees_cases h with ⟨zero, rfl⟩ | ⟨c, b, rfl, hc, hb⟩
    · exact absurd (Expr.isZero_eval zero env) holds
    · rw [loopAgrees_facts] at h
      exact .loopNext (by rw [Expr.agrees_eval _ _ hc env]; exact holds)
        (Exec.agrees ok bodyRun _ _ (Facts.Hold.nil _) hb) (ih _ _ (Facts.Hold.nil _) h)
  | @loopContinued depth env middle heap between condition body _ holds bodyRun _ ih =>
    intro facts s' _ h
    rcases loopAgrees_cases h with ⟨zero, rfl⟩ | ⟨c, b, rfl, hc, hb⟩
    · exact absurd (Expr.isZero_eval zero env) holds
    · rw [loopAgrees_facts] at h
      exact .loopContinued (by rw [Expr.agrees_eval _ _ hc env]; exact holds)
        (Exec.agrees ok bodyRun _ _ (Facts.Hold.nil _) hb) (ih _ _ (Facts.Hold.nil _) h)
  | @call depth inner target count callee env heap args func _ found len lt _ ih =>
    intro facts s' hold h
    obtain ⟨others, rfl, same⟩ := callAgrees_cases h
    obtain ⟨other, found', agrees⟩ := funcsAgree_get ok found
    obtain ⟨params, _, _, body⟩ := Func.agrees_parts agrees
    have values := argsAgree_eval same env
    refine .call found' (by rw [values.2, substAll_length, len, params]) lt ?_
    rw [values.1, substAll_eval hold]
    exact ih _ _ (Facts.Hold.nil _) body
  | @alloc depth env heap target shift size _ inside over =>
    intro facts s' hold h
    obtain ⟨size', rfl, same⟩ := allocAgrees_cases h
    have := (Expr.agrees_eval _ _ same env).trans (Expr.subst_eval hold size)
    rw [← this] at over
    exact .alloc inside over
  | @divide depth env heap word operation target left right _ undefined =>
    intro facts s' hold h
    obtain ⟨left', right', rfl, sameLeft, sameRight⟩ := divideAgrees_cases h
    have l := (Expr.agrees_eval _ _ sameLeft env).trans (Expr.subst_eval hold left)
    have r := (Expr.agrees_eval _ _ sameRight env).trans (Expr.subst_eval hold right)
    rw [← l, ← r] at undefined
    exact .divide undefined

theorem Program.Stops.validated {p q : Program} (ok : validate p q = true) {depth f : Nat}
    {args : List (BitVec 64)} {heap : Heap} {n : Nat} (stops : p.Stops depth f args heap n) :
    q.Stops depth f args heap n := by
  obtain ⟨func, found, len, run⟩ := stops
  obtain ⟨other, found', agrees⟩ := funcsAgree_get ok found
  obtain ⟨params, _, _, body⟩ := Func.agrees_parts agrees
  exact ⟨other, found', by rw [params]; exact len, Stops.agrees ok run [] _ (Facts.Hold.nil _) body⟩

/-- `compileProgram_stops` for the optimizing pipeline, with the same premises. -/
theorem compileOptimized_stops {prog : Program} {binary : Binary} (compiled : compileOptimized prog = some binary)
    {f : Nat} {args : List (BitVec 64)} {heap : Heap}
    (stops : ∀ n, ∃ depth, prog.Stops depth f args heap n)
    (s : State) (imageBase : BitVec 64) (window : Nat) (bounded : window ≤ 2 ^ 62)
    (loaded : CodeAt s.memory imageBase binary.image)
    (apart : ∀ index, index < binary.image.length →
      ¬Below (s.registers rspRegister) window (imageBase + BitVec.ofNat 64 index))
    (imageHeap : ∀ index, index < binary.image.length → ¬s.InHeap (imageBase + BitVec.ofNat 64 index))
    (entry : s.rip = imageBase + BitVec.ofNat 64 (binary.entries.getD f 0))
    (params : ∀ k (bound : k < args.length),
      read64 s.memory (s.registers rspRegister - BitVec.ofNat 64 (8 * k + 16)) = args[k])
    (heapAt : HeapAt window s heap) (stack : StackAt binary.guard window s) : Faults s := by
  rcases compileOptimized_some compiled with original | ⟨q, accepted, optimized⟩
  · exact compileProgram_stops original stops s imageBase window bounded loaded apart imageHeap entry params
      heapAt stack
  · exact compileProgram_stops optimized (fun n => (stops n).imp fun _ st => st.validated accepted) s imageBase
      window bounded loaded apart imageHeap entry params heapAt stack

end Lanius.Mini
