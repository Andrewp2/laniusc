import Lanius.Semantics.LocalEnv
import Lanius.Semantics.StatementProof

namespace Lanius.Semantics

open Lanius.Core

variable {id : VarId} {guard : Expr}

/-- Total postcondition for the existing expression relation, not a second
interpreter. A proof supplies a finite run and the resulting observation. -/
def ExprWP (program : Program) (before : State) (expression : Expr)
    (post : Value → State → Prop) : Prop :=
  ∃ value after, RunsExpr program before expression value after ∧ post value after

/-- Total statement postcondition, including the actual completion kind. -/
def StmtWP (program : Program) (before : State) (statement : Stmt)
    (post : Completion → State → Prop) : Prop :=
  ∃ completion after, RunsStmt program before statement completion after ∧ post completion after

namespace ExprWP

theorem ofRun (run : RunsExpr program before expression value after) (result : post value after) :
    ExprWP program before expression post := ⟨value, after, run, result⟩

end ExprWP

namespace StmtWP

theorem letLocal
    (initial : ExprWP program before initializer (fun value ready =>
      StmtWP program (ready.bindLocal id value) body
        (fun completion completed => post completion (restoreLocals ready completed)))) :
    StmtWP program before (.letLocal id type initializer body) post := by
  obtain ⟨value, ready, initial, completion, completed, run, result⟩ := initial
  exact ⟨completion, restoreLocals ready completed, RunsStmt.letLocal initial run, result⟩

/-- The straight-line pure-initializer case introduces the symbolic binding
once. Initializer values are inferred by existing expression proof rules. -/
theorem letEnv (env : LocalEnv base before values)
    (initial : RunsExpr program before initializer value before)
    (body : LocalEnv base (before.bindLocal id value) (values.set id value) →
      StmtWP program (before.bindLocal id value) bodyStmt
        (fun completion completed => post completion (restoreLocals before completed))) :
    StmtWP program before (.letLocal id type initializer bodyStmt) post :=
  letLocal (ExprWP.ofRun initial (body (env.bind id value)))

end StmtWP

/-- A logical result names the final symbolic locals once. Execution remains
the existing finite RunsStmt relation; this judgment adds no interpreter. -/
def EnvStmt {α : Type} (program : Program) (base before : State) (statement : Stmt)
    (values : α → LocalValues) (post : α → Completion → State → Prop) : Prop :=
  ∃ result completion after, RunsStmt program before statement completion after ∧
    LocalEnv base after (values result) ∧ post result completion after

namespace EnvStmt

variable {α β : Type} {outValues : α → LocalValues} {post : α → Completion → State → Prop}

theorem ofRun (run : RunsStmt program before statement completion after)
    (env : LocalEnv base after (outValues result)) (observed : post result completion after) :
    EnvStmt program base before statement outValues post := ⟨result, completion, after, run, env, observed⟩

theorem mono (run : EnvStmt program base before statement outValues pre)
    (observe : ∀ result completion after, LocalEnv base after (outValues result) →
      pre result completion after → post result completion after) :
    EnvStmt program base before statement outValues post := by
  obtain ⟨result, completion, after, run, env, observed⟩ := run
  exact ⟨result, completion, after, run, env, observe result completion after env observed⟩

theorem adapt {insideValues : β → LocalValues} {pre : β → Completion → State → Prop}
    (run : EnvStmt program base before statement insideValues pre)
    (observe : ∀ result completion after, LocalEnv base after (insideValues result) →
      pre result completion after → ∃ final, insideValues result = outValues final ∧ post final completion after) :
    EnvStmt program base before statement outValues post := by
  obtain ⟨result, completion, after, run, env, observed⟩ := run
  obtain ⟨final, equal, observed⟩ := observe result completion after env observed
  exact ⟨final, completion, after, run, equal ▸ env, observed⟩

theorem letPure (env : LocalEnv base before values) (freshName : values id = none)
    (initial : RunsExpr program before initializer value before)
    {insideValues : α → LocalValues}
    (body : LocalEnv base (before.bindLocal id value) (values.set id value) →
      EnvStmt program base (before.bindLocal id value) bodyStmt insideValues
        (fun result completion after => post result completion (restoreLocals before after)))
    (maps : ∀ result, (insideValues result).restrict values = outValues result) :
    EnvStmt program base before (.letLocal id type initializer bodyStmt) outValues post := by
  obtain ⟨result, completion, after, run, env, observed⟩ := body (env.bind id value)
  exact ⟨result, completion, restoreLocals before after, RunsStmt.letLocal initial run,
    maps result ▸ env.restoreScope freshName run.choose_spec.2, observed⟩

theorem letFramed {spec : Value → State → Prop} (env : LocalEnv base before values)
    (freshName : values id = none)
    (initial : ExprWP program before initializer (fun value ready => FreshCellFrame before ready ∧ spec value ready))
    {insideValues : Value → α → LocalValues}
    (body : ∀ value ready, LocalEnv base (ready.bindLocal id value) (values.set id value) → spec value ready →
      EnvStmt program base (ready.bindLocal id value) bodyStmt (insideValues value)
        (fun result completion after => post result completion (restoreLocals ready after)))
    (maps : ∀ value result, (insideValues value result).restrict values = outValues result) :
    EnvStmt program base before (.letLocal id type initializer bodyStmt) outValues post := by
  obtain ⟨value, ready, initial, cells, observed⟩ := initial
  obtain ⟨result, completion, after, run, env, observed⟩ :=
    body value ready ((env.afterExpr initial cells).bind id value) observed
  exact ⟨result, completion, restoreLocals ready after, RunsStmt.letLocal initial run,
    maps value result ▸ env.restoreScope freshName run.choose_spec.2, observed⟩

theorem sequenceNext (first : RunsStmt program before firstStmt .next middle)
    (second : EnvStmt program base middle secondStmt outValues post) :
    EnvStmt program base before (.sequence firstStmt secondStmt) outValues post := by
  obtain ⟨result, completion, after, run, env, observed⟩ := second
  exact ⟨result, completion, after, RunsStmt.sequenceNext first run, env, observed⟩

/-- Consume a result and its environment at a control-flow cut. Completed
branches supply only their logical result/map correspondence. -/
theorem sequence {insideValues : β → LocalValues} {pre : β → Completion → State → Prop}
    (first : EnvStmt program base before firstStmt insideValues pre)
    (rest : ∀ result completion middle, LocalEnv base middle (insideValues result) → pre result completion middle →
      match completion with
      | .next => EnvStmt program base middle secondStmt outValues post
      | _ => ∃ final, insideValues result = outValues final ∧ post final completion middle) :
    EnvStmt program base before (.sequence firstStmt secondStmt) outValues post := by
  obtain ⟨result, completion, middle, run, env, observed⟩ := first
  have tail := rest result completion middle env observed
  cases completion
  · exact sequenceNext run tail
  all_goals
    obtain ⟨final, equal, observed⟩ := tail
    exact ⟨final, _, middle, RunsStmt.sequenceCompleted run (by simp) _, equal ▸ env, observed⟩

theorem branch (condition : RunsExpr program before guard (.boolean truth) middle)
    (body : EnvStmt program base middle (if truth then yes else no) outValues post) :
    EnvStmt program base before (.ifThenElse guard yes no) outValues post := by
  obtain ⟨result, completion, after, run, env, observed⟩ := body
  cases truth
  · exact ⟨result, completion, after, RunsStmt.ifThenElseFalse condition run, env, observed⟩
  · exact ⟨result, completion, after, RunsStmt.ifThenElseTrue condition run, env, observed⟩

theorem guardFalse (condition : RunsExpr program before guard (.boolean false) before)
    (rest : EnvStmt program base before body outValues post) :
    EnvStmt program base before (.sequence (.ifThenElse guard rejected .skip) body) outValues post :=
  sequenceNext (RunsStmt.ifThenElseFalse condition (RunsStmt.skip _ _)) rest

end EnvStmt

theorem RunsExpr.logicalOrScalar
    (left : RunsExpr program before leftExpr (.boolean first) middle)
    (right : RunsExpr program middle rightExpr (.boolean second) middle) :
    RunsExpr program before (.binary .logicalOr leftExpr rightExpr) (.boolean (first || second)) middle := by
  cases first
  · exact RunsExpr.logicalOrFalse left right
  · exact .ofStable (StableExpr.logicalOrTrue left.choose_spec.1) left.choose_spec.2

theorem RunsExpr.booleanResult (run : RunsExpr program before expression (.boolean actual) after)
    (same : actual = expected) : RunsExpr program before expression (.boolean expected) after := same ▸ run

open Lean Meta Elab Tactic

syntax "core_env_run" : tactic

elab_rules : tactic
  | `(tactic| core_env_run) => withMainContext do
    let saved ← saveState
    try
      evalTactic (← `(tactic| solve | core_contract))
      return
    catch _ => saved.restore
    let target := (← instantiateMVars (← (← getMainGoal).getType)).consumeMData
    unless target.isAppOfArity ``RunsExpr 5 do throwError "expected RunsExpr"
    let expression ← whnf target.getAppArgs[2]!
    if expression.isAppOf ``Lanius.Core.Expr.binary &&
        expression.getAppArgs[0]!.isConstOf ``Lanius.Core.BinaryOp.logicalOr then
      evalTactic (← `(tactic| apply RunsExpr.booleanResult))
      evalTactic (← `(tactic| apply RunsExpr.logicalOrScalar))
      evalTactic (← `(tactic| core_env_run))
      evalTactic (← `(tactic| core_env_run))
      evalTactic (← `(tactic| first | rfl | core_guard_logic))
    else
      evalTactic (← `(tactic|
        first
        | (solve | core_run)
        | (apply RunsExpr.ofStable <;> first | core_guard_step | rfl)))

/-- Eliminate actual pure rejection guards by their proved Boolean results. -/
private partial def envGuards : TacticM Unit := withMainContext do
  let target := (← instantiateMVars (← (← getMainGoal).getType)).consumeMData
  unless target.isAppOfArity ``EnvStmt 7 do throwError "expected EnvStmt"
  let statement ← whnf target.getAppArgs[4]!
  unless statement.isAppOf ``Lanius.Core.Stmt.sequence do return
  let first ← whnf statement.getAppArgs[0]!
  unless first.isAppOf ``Lanius.Core.Stmt.ifThenElse &&
      (← whnf first.getAppArgs[2]!).isConstOf ``Lanius.Core.Stmt.skip do return
  evalTactic (← `(tactic| apply EnvStmt.guardFalse))
  evalTactic (← `(tactic| core_env_run))
  envGuards

elab "core_env_guards" : tactic => envGuards

/-- Peel actual leading let syntax, inferring each initializer and extending
the supplied environment. The resulting goal is the actual source suffix.
Every step is an application of StmtWP.letEnv and existing RunsExpr proofs. -/
private partial def envLets (env : Lean.Expr) : TacticM Unit := withMainContext do
  let target := (← instantiateMVars (← (← getMainGoal).getType)).consumeMData
  unless target.isAppOfArity ``StmtWP 4 do throwError "expected StmtWP"
  let statement ← whnf target.getAppArgs[2]!
  unless statement.isAppOf ``Lanius.Core.Stmt.letLocal do return
  let envSyntax ← Term.exprToSyntax env
  evalTactic (← `(tactic| apply StmtWP.letEnv $envSyntax))
  let bodyGoals := (← getGoals).tail
  evalTactic (← `(tactic| core_run))
  setGoals bodyGoals
  let goal ← getMainGoal
  let (name, goal) ← goal.intro1
  setGoals (goal :: (← getGoals).tail)
  envLets (mkFVar name)

elab "core_env_lets" env:ident : tactic => withMainContext do
  envLets (← Term.elabTerm env none)

/-- Compose every leading lexical scope, retaining updated outer values.
The final body returns one environment; all RunsStmt scope construction and
restoration is generated by the proved tracked rule. -/
private partial def envScopes (env : Lean.Expr) : TacticM Unit := withMainContext do
  let target := (← instantiateMVars (← (← getMainGoal).getType)).consumeMData
  unless target.isAppOfArity ``EnvStmt 7 do throwError "expected EnvStmt"
  let statement ← whnf target.getAppArgs[4]!
  unless statement.isAppOf ``Lanius.Core.Stmt.letLocal do return
  let saved ← saveState
  try
    let envSyntax ← Term.exprToSyntax env
    evalTactic (← `(tactic| apply EnvStmt.letPure $envSyntax))
    evalTactic (← `(tactic| rfl))
    evalTactic (← `(tactic| core_run))
    let goal ← getMainGoal
    let (name, goal) ← goal.intro1
    setGoals (goal :: (← getGoals).tail)
    envScopes (mkFVar name)
  catch _ => saved.restore

elab "core_env_scopes" env:ident : tactic => withMainContext do
  envScopes (← Term.elabTerm env none)

/-- Split only the queried key of a residual finite map. This never sorts
whole maps or compares their (potentially large) stored Core values. -/
private partial def envValueCases : TacticM Unit := do
  evalTactic (← `(tactic| try simp +decide
    [*, LocalValues.set, LocalValues.restrict, LocalValues.empty]))
  if (← getGoals).isEmpty then return
  evalTactic (← `(tactic| intros))
  evalTactic (← `(tactic| try subst_vars))
  evalTactic (← `(tactic| try contradiction))
  evalTactic (← `(tactic| try rfl))
  evalTactic (← `(tactic| try
    (symm; exact Option.not_isSome_iff_eq_none.mp (by assumption))))
  if (← getGoals).isEmpty then return
  evalTactic (← `(tactic| split))
  let goals ← getGoals
  for goal in goals do
    setGoals [goal]
    envValueCases

/-- Restriction is resolved by known key lookups first. Any remaining update
equality is pointwise, using kernel-proved static key comparisons, not AC
normalization of the stored values. -/
elab "core_env_values" : tactic => withMainContext do
  let rest := (← getGoals).tail
  setGoals [(← getMainGoal)]
  evalTactic (← `(tactic| intros))
  evalTactic (← `(tactic| try simp
    (discharger := first | assumption | rfl | decide) only
    [LocalValues.restrict_set_member, LocalValues.restrict_set_fresh,
      LocalValues.restrict_self, LocalValues.restrict_extend, LocalValues.restrict_empty,
      LocalValues.set_set]))
  unless (← getGoals).isEmpty do
    evalTactic (← `(tactic| funext queried))
    envValueCases
  setGoals rest

end Lanius.Semantics
