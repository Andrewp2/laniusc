import Lanius.Semantics.StatementProof
import Lanius.Semantics.MatchRun

namespace Lanius.Semantics

open Lanius.Core

/-- Read-only initializers may still introduce fresh local cells. The body
    must prove its frame, and leaving the scope restores the caller's locals. -/
theorem RunsStmt.letPure
    {id : Lanius.VarId}
    (initial : RunsExpr program before initializer value before)
    (formed : before.CellsWellFormed)
    (body : ∃ after, RunsStmt program (before.bindLocal id value) bodyStmt completion after ∧
      PureFrame (before.bindLocal id value) after) :
    ∃ after, RunsStmt program before (.letLocal id type initializer bodyStmt) completion after ∧
      PureFrame before after := by
  obtain ⟨after, run, frame⟩ := body
  exact RunsStmt.letLocalPure initial (PureFrame.refl formed) run frame

theorem RunsStmt.sequencePureCompleted (notNext : completion ≠ .next)
    (first : ∃ after, RunsStmt program before firstStmt completion after ∧ PureFrame before after) :
    ∃ after, RunsStmt program before (.sequence firstStmt secondStmt) completion after ∧
      PureFrame before after := by
  obtain ⟨after, run, frame⟩ := first
  exact ⟨after, RunsStmt.sequenceCompleted run notNext _, frame⟩

theorem RunsStmt.sequencePureNext
    (first : RunsStmt program before firstStmt .next before)
    (second : ∃ after, RunsStmt program before secondStmt completion after ∧ PureFrame before after) :
    ∃ after, RunsStmt program before (.sequence firstStmt secondStmt) completion after ∧
      PureFrame before after := by
  obtain ⟨after, run, frame⟩ := second
  exact ⟨after, RunsStmt.sequenceNext first run, frame⟩

theorem RunsStmt.sequenceFramedNext
    (first : ∃ middle, RunsStmt program before firstStmt .next middle ∧ PureFrame before middle)
    (second : ∀ middle, PureFrame before middle →
      ∃ after, RunsStmt program middle secondStmt completion after ∧ PureFrame middle after) :
    ∃ after, RunsStmt program before (.sequence firstStmt secondStmt) completion after ∧
      PureFrame before after := by
  obtain ⟨middle, first, frame⟩ := first
  obtain ⟨after, second, rest⟩ := second middle frame
  exact ⟨after, RunsStmt.sequenceNext first second, frame.trans rest⟩

theorem RunsStmt.branchPure (truth : Bool)
    (condition : RunsExpr program before conditionExpr (.boolean truth) before)
    (branch : ∃ after, RunsStmt program before (if truth then thenStmt else elseStmt) completion after ∧
      PureFrame before after) :
    ∃ after, RunsStmt program before (.ifThenElse conditionExpr thenStmt elseStmt) completion after ∧
      PureFrame before after := by
  obtain ⟨after, run, frame⟩ := branch
  cases truth
  · exact ⟨after, RunsStmt.ifThenElseFalse condition run, frame⟩
  · exact ⟨after, RunsStmt.ifThenElseTrue condition run, frame⟩

/-- A failed early-return guard falls through without proving the skipped
    return path. In particular, its condition is checked only once. -/
theorem RunsStmt.guardPureFalse
    (condition : RunsExpr program before conditionExpr (.boolean false) before)
    (rest : ∃ after, RunsStmt program before restStmt completion after ∧ PureFrame before after) :
    ∃ after, RunsStmt program before
      (.sequence (.ifThenElse conditionExpr thenStmt .skip) restStmt) completion after ∧
      PureFrame before after := by
  obtain ⟨after, run, frame⟩ := rest
  exact ⟨after, RunsStmt.sequenceNext
    (RunsStmt.ifThenElseFalse condition (RunsStmt.skip _ _)) run, frame⟩

theorem RunsStmt.guardPureTrue (notNext : completion ≠ .next)
    (condition : RunsExpr program before conditionExpr (.boolean true) before)
    (branch : ∃ after, RunsStmt program before thenStmt completion after ∧ PureFrame before after) :
    ∃ after, RunsStmt program before
      (.sequence (.ifThenElse conditionExpr thenStmt .skip) restStmt) completion after ∧
      PureFrame before after := by
  obtain ⟨after, run, frame⟩ := branch
  exact ⟨after, RunsStmt.sequenceCompleted
    (RunsStmt.ifThenElseTrue condition run) notNext _, frame⟩

theorem RunsExpr.callPureArguments
    (argumentsRun : RunsExprs program before arguments values before)
    (call : ∃ after, RunsExpr program before (.call functionId (values.map Expr.value)) result after ∧
      PureFrame before after) :
    ∃ after, RunsExpr program before (.call functionId arguments) result after ∧ PureFrame before after := by
  obtain ⟨after, run, frame⟩ := call
  exact ⟨after, RunsExpr.callArguments argumentsRun run, frame⟩

theorem RunsStmt.returnPure
    (expression : ∃ after, RunsExpr program before argument result after ∧ PureFrame before after) :
    ∃ after, RunsStmt program before (.returnValue (some argument)) (.returned (some result)) after ∧
      PureFrame before after := by
  obtain ⟨after, run, frame⟩ := expression
  exact ⟨after, RunsStmt.returnValue run, frame⟩

/-- Compose proved pure computations without requiring that fresh call cells
    disappear. Continuations may use only the preserved caller frame. -/
theorem RunsExpr.unaryPure
    (operand : ∃ after, RunsExpr program before argument value after ∧ PureFrame before after)
    (evaluates : evalUnaryValue program.target operation value = .ok result) :
    ∃ after, RunsExpr program before (.unary operation argument) result after ∧ PureFrame before after := by
  obtain ⟨after, ⟨fuel, run, locals⟩, frame⟩ := operand
  exact ⟨after, RunsExpr.ofStable (StableExpr.unary run evaluates) locals, frame⟩

/-- Scalar casts preserve the operand's actual pure frame, including fresh
    call cells. The cast itself adds no state change. -/
theorem RunsExpr.castPure
    (operand : ∃ after, RunsExpr program before argument value after ∧ PureFrame before after)
    (evaluates : evalScalarCast program.target destination value = .ok result) :
    ∃ after, RunsExpr program before (.cast destination argument) result after ∧ PureFrame before after := by
  obtain ⟨after, ⟨fuel, run, locals⟩, frame⟩ := operand
  exact ⟨after, RunsExpr.ofStable (StableExpr.cast run evaluates) locals, frame⟩

theorem RunsExpr.fieldPure
    (base : ∃ after, RunsExpr program before argument (.structure typeId fields) after ∧ PureFrame before after)
    (found : fields[fieldId]? = some value) :
    ∃ after, RunsExpr program before (.field argument fieldId) value after ∧ PureFrame before after := by
  obtain ⟨after, run, frame⟩ := base
  exact ⟨after, RunsExpr.field run found, frame⟩

theorem RunsExpr.binaryPure
    (left : ∃ middle, RunsExpr program before leftExpr leftValue middle ∧ PureFrame before middle)
    (right : ∀ middle, PureFrame before middle →
      ∃ after, RunsExpr program middle rightExpr rightValue after ∧ PureFrame middle after)
    (eager : operation ≠ .logicalAnd ∧ operation ≠ .logicalOr)
    (evaluates : evalBinaryValue program.target operation leftValue rightValue = .ok result) :
    ∃ after, RunsExpr program before (.binary operation leftExpr rightExpr) result after ∧
      PureFrame before after := by
  obtain ⟨middle, left, leftFrame⟩ := left
  obtain ⟨after, right, rightFrame⟩ := right middle leftFrame
  exact ⟨after, RunsExpr.binary left right eager evaluates, leftFrame.trans rightFrame⟩

theorem RunsExpr.booleanPure
    (run : ∃ after, RunsExpr program before argument (.boolean actual) after ∧ PureFrame before after)
    (result : actual = expected) :
    ∃ after, RunsExpr program before argument (.boolean expected) after ∧ PureFrame before after := result ▸ run

theorem RunsExpr.logicalOrTruePure
    (left : ∃ after, RunsExpr program before leftExpr (.boolean true) after ∧ PureFrame before after) :
    ∃ after, RunsExpr program before (.binary .logicalOr leftExpr rightExpr) (.boolean true) after ∧
      PureFrame before after := by
  obtain ⟨after, ⟨_, run, locals⟩, frame⟩ := left
  exact ⟨after, .ofStable (StableExpr.logicalOrTrue run) locals, frame⟩

theorem RunsExpr.logicalOrFalsePure
    (left : RunsExpr program before leftExpr (.boolean false) before)
    (right : ∃ after, RunsExpr program before rightExpr (.boolean value) after ∧ PureFrame before after) :
    ∃ after, RunsExpr program before (.binary .logicalOr leftExpr rightExpr) (.boolean value) after ∧
      PureFrame before after := by
  obtain ⟨leftFuel, left, _⟩ := left
  obtain ⟨after, ⟨rightFuel, right, locals⟩, frame⟩ := right
  refine ⟨after, ⟨max leftFuel rightFuel + 1, ?_, locals⟩, frame⟩
  intro fuel enough
  simpa only [show (fuel - 1).succ = fuel by omega] using
    evalExpr_logicalOr_false (fuel - 1) program before leftExpr rightExpr (.boolean value) before after
      (left (fuel - 1) (by omega)) (right (fuel - 1) (by omega))

/-- Short-circuit conjunction retains the left call's read-only frame. -/
theorem RunsExpr.logicalAndFalsePure
    (left : ∃ after, RunsExpr program before leftExpr (.boolean false) after ∧ PureFrame before after) :
    ∃ after, RunsExpr program before (.binary .logicalAnd leftExpr rightExpr) (.boolean false) after ∧
      PureFrame before after := by
  obtain ⟨after, ⟨_, run, locals⟩, frame⟩ := left
  exact ⟨after, .ofStable (StableExpr.logicalAndFalse run) locals, frame⟩

theorem RunsExpr.logicalAndTruePure
    (left : RunsExpr program before leftExpr (.boolean true) before)
    (right : ∃ after, RunsExpr program before rightExpr value after ∧ PureFrame before after) :
    ∃ after, RunsExpr program before (.binary .logicalAnd leftExpr rightExpr) value after ∧
      PureFrame before after := by
  obtain ⟨_, left, _⟩ := left
  obtain ⟨after, ⟨_, right, locals⟩, frame⟩ := right
  exact ⟨after, .ofStable (StableExpr.logicalAndTrue left right) locals, frame⟩

/-- A conjunction may perform read-only calls on both sides. Their fresh
    cells compose, while a false left side still skips the right side. -/
theorem RunsExpr.logicalAndPure
    (left : ∃ middle, RunsExpr program before leftExpr (.boolean a) middle ∧ PureFrame before middle)
    (right : ∀ middle, PureFrame before middle →
      ∃ after, RunsExpr program middle rightExpr (.boolean b) after ∧ PureFrame middle after) :
    ∃ after, RunsExpr program before (.binary .logicalAnd leftExpr rightExpr) (.boolean (a && b)) after ∧
      PureFrame before after := by
  obtain ⟨middle, ⟨leftFuel, left, locals⟩, frame⟩ := left
  cases a with
  | false => exact ⟨middle, .ofStable (StableExpr.logicalAndFalse left) locals, frame⟩
  | true =>
      obtain ⟨after, ⟨rightFuel, right, rightLocals⟩, rightFrame⟩ := right middle frame
      refine ⟨after, ⟨max leftFuel rightFuel + 1, ?_, rightLocals.trans locals⟩, frame.trans rightFrame⟩
      intro fuel enough
      simpa only [show (fuel - 1).succ = fuel by omega, Bool.true_and] using
        evalExpr_logicalAnd_true (fuel - 1) program before leftExpr rightExpr (.boolean b) middle after
          (left (fuel - 1) (by omega)) (right (fuel - 1) (by omega))

theorem RunsExpr.logicalOrPure
    (left : ∃ middle, RunsExpr program before leftExpr (.boolean a) middle ∧ PureFrame before middle)
    (right : ∀ middle, PureFrame before middle →
      ∃ after, RunsExpr program middle rightExpr (.boolean b) after ∧ PureFrame middle after) :
    ∃ after, RunsExpr program before (.binary .logicalOr leftExpr rightExpr) (.boolean (a || b)) after ∧
      PureFrame before after := by
  obtain ⟨middle, ⟨leftFuel, left, locals⟩, frame⟩ := left
  cases a with
  | true =>
      exact ⟨middle, .ofStable (StableExpr.logicalOrTrue left) locals, frame⟩
  | false =>
      obtain ⟨after, ⟨rightFuel, right, rightLocals⟩, rightFrame⟩ := right middle frame
      refine ⟨after, ⟨max leftFuel rightFuel + 1, ?_, rightLocals.trans locals⟩, frame.trans rightFrame⟩
      intro fuel enough
      simpa only [show (fuel - 1).succ = fuel by omega, Bool.false_or] using
        evalExpr_logicalOr_false (fuel - 1) program before leftExpr rightExpr (.boolean b) middle after
          (left (fuel - 1) (by omega)) (right (fuel - 1) (by omega))

theorem RunsStmt.letFramedPure {id : Lanius.VarId}
    (initial : ∃ middle, RunsExpr program before initializer value middle ∧ PureFrame before middle)
    (body : ∀ middle, PureFrame before middle → ∃ after,
      RunsStmt program (middle.bindLocal id value) bodyStmt completion after ∧
      PureFrame (middle.bindLocal id value) after) :
    ∃ after, RunsStmt program before (.letLocal id type initializer bodyStmt) completion after ∧
      PureFrame before after := by
  obtain ⟨middle, run, frame⟩ := initial
  obtain ⟨after, bodyRun, bodyFrame⟩ := body middle frame
  exact RunsStmt.letLocalPure run frame bodyRun bodyFrame

theorem RunsStmt.guardFramedFalse
    (condition : ∃ middle, RunsExpr program before conditionExpr (.boolean false) middle ∧ PureFrame before middle)
    (rest : ∀ middle, PureFrame before middle →
      ∃ after, RunsStmt program middle restStmt completion after ∧ PureFrame middle after) :
    ∃ after, RunsStmt program before
      (.sequence (.ifThenElse conditionExpr thenStmt .skip) restStmt) completion after ∧
      PureFrame before after := by
  obtain ⟨middle, run, frame⟩ := condition
  obtain ⟨after, rest, restFrame⟩ := rest middle frame
  exact ⟨after, RunsStmt.sequenceNext (RunsStmt.ifThenElseFalse run (RunsStmt.skip _ _)) rest,
    frame.trans restFrame⟩

theorem RunsStmt.guardFramedTrue (notNext : completion ≠ .next)
    (condition : ∃ middle, RunsExpr program before conditionExpr (.boolean true) middle ∧ PureFrame before middle)
    (branch : ∀ middle, PureFrame before middle →
      ∃ after, RunsStmt program middle thenStmt completion after ∧ PureFrame middle after) :
    ∃ after, RunsStmt program before
      (.sequence (.ifThenElse conditionExpr thenStmt .skip) restStmt) completion after ∧
      PureFrame before after := by
  obtain ⟨middle, run, frame⟩ := condition
  obtain ⟨after, branch, branchFrame⟩ := branch middle frame
  exact ⟨after, RunsStmt.sequenceCompleted (RunsStmt.ifThenElseTrue run branch) notNext _,
    frame.trans branchFrame⟩

/-- A pure helper in a branch condition may allocate temporary call cells.
    Retain its frame instead of requiring the input state to be unchanged. -/
theorem RunsStmt.branchFramedPure (truth : Bool)
    (condition : ∃ middle, RunsExpr program before conditionExpr (.boolean truth) middle ∧ PureFrame before middle)
    (branch : ∀ middle, PureFrame before middle → ∃ after,
      RunsStmt program middle (if truth then thenStmt else elseStmt) completion after ∧ PureFrame middle after) :
    ∃ after, RunsStmt program before (.ifThenElse conditionExpr thenStmt elseStmt) completion after ∧
      PureFrame before after := by
  obtain ⟨middle, condition, first⟩ := condition
  obtain ⟨after, branch, rest⟩ := branch middle first
  cases truth
  · exact ⟨after, RunsStmt.ifThenElseFalse condition branch, first.trans rest⟩
  · exact ⟨after, RunsStmt.ifThenElseTrue condition branch, first.trans rest⟩

/-- Keep a state-identical argument's tail at the actual input state. -/
theorem RunsExprs.consPureSame {values : List Value}
    (head : RunsExpr program before expression value before)
    (tail : ∃ after, RunsExprs program before expressions values after ∧ PureFrame before after) :
    ∃ after, RunsExprs program before (expression :: expressions) (value :: values) after ∧
      PureFrame before after := by
  obtain ⟨after, tail, frame⟩ := tail
  exact ⟨after, RunsExprs.cons head tail, frame⟩

/-- Read-only arguments can allocate fresh call cells. Compose those frames
    before entering the callee instead of requiring state-identical arguments. -/
theorem RunsExprs.consPure {values : List Value}
    (head : ∃ middle, RunsExpr program before expression value middle ∧ PureFrame before middle)
    (tail : ∀ middle, PureFrame before middle →
      ∃ after, RunsExprs program middle expressions values after ∧ PureFrame middle after) :
    ∃ after, RunsExprs program before (expression :: expressions) (value :: values) after ∧
      PureFrame before after := by
  obtain ⟨middle, head, first⟩ := head
  obtain ⟨after, tail, rest⟩ := tail middle first
  exact ⟨after, RunsExprs.cons head tail, first.trans rest⟩

theorem RunsExpr.callFramedPureArguments
    (arguments : ∃ middle, RunsExprs program before expressions values middle ∧ PureFrame before middle)
    (contract : ∀ middle, PureFrame before middle →
      ∃ after, RunsExpr program middle (.call functionId (values.map Expr.value)) value after ∧
        PureFrame middle after) :
    ∃ after, RunsExpr program before (.call functionId expressions) value after ∧ PureFrame before after := by
  obtain ⟨middle, arguments, first⟩ := arguments
  obtain ⟨after, run, rest⟩ := contract middle first
  exact ⟨after, RunsExpr.callArguments arguments run, first.trans rest⟩

/-- Constructor payloads may allocate temporary cells, just like call
    arguments. Their recursively proved frames compose left to right. -/
theorem RunsExpr.enumPure
    (payload : ∃ after, RunsExprs program before expressions values after ∧ PureFrame before after) :
    ∃ after, RunsExpr program before (.enumValue typeId ordinal expressions)
      (.enumeration typeId ordinal values) after ∧ PureFrame before after := by
  obtain ⟨after, payload, frame⟩ := payload
  exact ⟨after, RunsExpr.enumValue payload, frame⟩

theorem RunsExpr.structPure
    (fields : ∃ after, RunsExprs program before expressions values after ∧ PureFrame before after) :
    ∃ after, RunsExpr program before (.structValue typeId expressions)
      (.structure typeId values) after ∧ PureFrame before after := by
  obtain ⟨after, fields, frame⟩ := fields
  exact ⟨after, RunsExpr.structValue fields, frame⟩

/-- The zero-length nominal constructor needs layout, but no backing read.
    Both component computations must retain their proved pure frames. -/
theorem RunsExpr.emptyRawNominalPure
    (pointer : ∃ middle, RunsExpr program before pointerExpr (.pointer address) middle ∧ PureFrame before middle)
    (length : ∀ middle, PureFrame before middle → ∃ after,
      RunsExpr program middle lengthExpr (.signed .i32 0) after ∧ PureFrame middle after)
    (nominal : (match element with | .structure _ | .enumeration _ => true | _ => false) = true)
    (layout : NativeLayout.valueWords? program element = some words) (positive : 0 < words) :
    ∃ after, RunsExpr program before (.typedSliceFromRawParts element pointerExpr lengthExpr)
      (.rawSlice element address 0) after ∧ PureFrame before after := by
  obtain ⟨middle, ⟨_, pointer, pointerLocals⟩, first⟩ := pointer
  obtain ⟨after, ⟨_, length, lengthLocals⟩, rest⟩ := length middle first
  exact ⟨after, .ofStable (.emptyRawNominalSlice pointer length nominal layout positive)
    (lengthLocals.trans pointerLocals), first.trans rest⟩

syntax "core_pure" : tactic
syntax "core_pure_expr" : tactic
syntax "core_pure_guard" : tactic
syntax "core_pure_arguments" : tactic

open Lean Meta Elab Tactic

/-- Explicitly registered, proved function contracts; no call bodies are
    interpreted or silently assumed pure by this dispatch. -/
initialize pureRules : LabelExtension ←
  registerLabelAttr `core_pure_rule "proved pure expression contracts"

/-- Read only the outer contract and call identity. In particular, never
    unfold `RunsExpr` to reject a contract for a different callee. -/
def contractCall? (type : Lean.Expr) : MetaM (Option Lean.Expr) :=
  forallTelescopeReducing type fun _ conclusion => do
    let conclusion := conclusion.consumeMData
    unless conclusion.isAppOfArity ``Exists 2 do return none
    let .lam _ _ body _ := conclusion.getAppArgs[1]! | return none
    let body := body.consumeMData
    unless body.isAppOfArity ``And 2 do return none
    let run := body.getAppArgs[0]!.consumeMData
    unless run.isAppOfArity ``RunsExpr 5 do return none
    let expression ← whnf run.getAppArgs[2]!
    unless expression.isAppOfArity ``Lanius.Core.Expr.call 2 do return none
    return some expression.getAppArgs[0]!

elab "core_pure_rule" : tactic => withMainContext do
  let goal ← getMainGoal
  let remaining := (← getGoals).tail
  let mut candidates := #[]
  -- Specializations supplied by this proof are reusable at later states.
  -- Their premises and frame are checked just like registered contracts.
  for declaration in (← getLCtx) do
    let type := (← instantiateMVars declaration.type).consumeMData
    if !declaration.isImplementationDetail && type.isForall && (← isProp type) then
      candidates := candidates.push (mkFVar declaration.fvarId)
  for name in (← Lean.labelled `core_pure_rule) do
    candidates := candidates.push (← mkConstWithFreshMVarLevels name)
  let callee ← contractCall? (← goal.getType)
  for candidate in candidates do
    let saved ← saveState
    try
      if let some callee := callee then
        let some other ← contractCall? (← inferType candidate) |
          throwError "not a call contract"
        unless ← isDefEq callee other do throwError "different callee"
      setGoals (← goal.apply candidate)
      evalTactic (← `(tactic| all_goals (first | core_contract | core_formed | decide)))
      unless (← getGoals).isEmpty do throwError "pure contract premises remain"
      setGoals remaining
      return
    catch _ => saved.restore
  let target ← instantiateMVars (← goal.getType)
  if target.isAppOfArity ``Exists 2 then
    if let .lam _ _ body _ := target.getAppArgs[1]! then
      if body.isAppOfArity ``And 2 then
        let run := body.getAppArgs[0]!
        if run.isAppOfArity ``RunsExpr 5 then
          throwError "no applicable proved pure contract for {run.getAppArgs[2]!} returning {run.getAppArgs[3]!}"
  throwError "no applicable proved pure contract"

elab "core_pure_expr_node" : tactic => withMainContext do
  let target ← whnf (← instantiateMVars (← (← getMainGoal).getType))
  unless target.isAppOfArity ``Exists 2 do throwError "expected an existential pure expression contract"
  let .lam _ _ body _ := target.getAppArgs[1]! | throwError "expected a state binder"
  unless body.isAppOfArity ``And 2 do throwError "expected execution and a frame"
  let run := (← instantiateMVars body.getAppArgs[0]!).consumeMData
  unless run.isAppOfArity ``RunsExpr 5 do throwError "expected an expression contract"
  let expression ← whnf run.getAppArgs[2]!
  let rule ← match expression.getAppFn.constName? with
    | some ``Lanius.Core.Expr.matchValue => `(tactic|
        first
        | (apply RunsExpr.matchPure; core_run; rfl; core_formed; core_pure_expr)
        | (apply RunsExpr.matchFramedPure; core_pure_expr; rfl;
            intro middle frame; core_pure_expr))
    | some ``Lanius.Core.Expr.enumValue => `(tactic|
        (apply RunsExpr.enumPure; core_pure_arguments))
    | some ``Lanius.Core.Expr.structValue => `(tactic|
        (apply RunsExpr.structPure; core_pure_arguments))
    | some ``Lanius.Core.Expr.typedSliceFromRawParts => `(tactic|
        (apply RunsExpr.emptyRawNominalPure
         · core_pure_expr
         · intro middle frame; core_pure_expr
         · first | core_contract | rfl
         · first | core_contract | rfl
         · first | core_contract | decide))
    | some ``Lanius.Core.Expr.call => `(tactic|
        first
        | (apply RunsExpr.callPureArguments; core_arguments; first | core_contract | core_pure_rule)
        | (apply RunsExpr.callFramedPureArguments; core_pure_arguments;
            intro middle frame; first | core_contract | core_pure_rule))
    | some ``Lanius.Core.Expr.field => `(tactic| first
        | (focus (refine ⟨_, ?_, PureFrame.refl ?_⟩; rotate_left; core_formed; core_run))
        | (apply RunsExpr.fieldPure; core_pure_expr; rfl))
    | some ``Lanius.Core.Expr.unary => `(tactic| first
        | (focus (refine ⟨_, ?_, PureFrame.refl ?_⟩; rotate_left; core_formed; core_run))
        | (apply RunsExpr.unaryPure; core_pure_expr; core_scalar))
    | some ``Lanius.Core.Expr.cast => `(tactic|
        (apply RunsExpr.castPure; core_pure_expr; core_scalar))
    | some ``Lanius.Core.Expr.binary =>
        if expression.getAppArgs[0]!.isConstOf ``Lanius.Core.BinaryOp.logicalAnd then
          `(tactic| first
            | (focus (refine ⟨_, ?_, PureFrame.refl ?_⟩; rotate_left; core_formed; core_run))
            | (apply RunsExpr.logicalAndFalsePure; core_pure_expr)
            | (apply RunsExpr.logicalAndTruePure; core_run; core_pure_expr)
            | (apply RunsExpr.logicalAndPure; core_pure_expr; intro middle frame; core_pure_expr))
        else if expression.getAppArgs[0]!.isConstOf ``Lanius.Core.BinaryOp.logicalOr then
          `(tactic| first
            | (focus (refine ⟨_, ?_, PureFrame.refl ?_⟩; rotate_left; core_formed; core_run))
            | (apply RunsExpr.logicalOrTruePure; core_pure_expr)
            | (apply RunsExpr.logicalOrFalsePure; core_run; core_pure_expr)
            | (apply RunsExpr.logicalOrPure; core_pure_expr; intro middle frame; core_pure_expr))
        else `(tactic| first
          | (focus (refine ⟨_, ?_, PureFrame.refl ?_⟩; rotate_left; core_formed; core_run))
          | (apply RunsExpr.binaryPure; core_pure_expr; intro middle frame; core_pure_expr;
              (solve | simp); core_scalar))
    | _ => `(tactic|
        (focus (refine ⟨_, ?_, PureFrame.refl ?_⟩; rotate_left; core_formed; core_run)))
  evalTactic rule

/-- A known call cannot be state-identical merely because its return value
    is immutable: its actual contract must account for fresh call cells. -/
elab "core_pure_arguments_node" : tactic => withMainContext do
  let target ← whnf (← instantiateMVars (← (← getMainGoal).getType))
  unless target.isAppOfArity ``Exists 2 do throwError "expected pure arguments"
  let .lam _ _ body _ := target.getAppArgs[1]! | throwError "expected a state binder"
  unless body.isAppOfArity ``And 2 do throwError "expected execution and a frame"
  let run := (← instantiateMVars body.getAppArgs[0]!).consumeMData
  unless run.isAppOfArity ``RunsExprs 5 do throwError "expected an arguments contract"
  let expressions ← whnf run.getAppArgs[2]!
  if expressions.isAppOfArity ``List.nil 1 then
    evalTactic (← `(tactic| refine ⟨_, RunsExprs.nil, PureFrame.refl ?_⟩; core_formed))
  else
    unless expressions.isAppOfArity ``List.cons 3 do throwError "expected known argument syntax"
    let head ← whnf expressions.getAppArgs[1]!
    if (head.find? (·.isConstOf ``Lanius.Core.Expr.call)).isSome then
      evalTactic (← `(tactic|
        apply RunsExprs.consPure; core_pure_expr; intro middle frame; core_pure_arguments))
    else
      evalTactic (← `(tactic|
        (first
          | (apply RunsExprs.consPureSame; core_run)
          | (apply RunsExprs.consPure; core_pure_expr; intro middle frame));
        core_pure_arguments))

/-- Compose read-only statement proofs, including temporary local scopes.
    Each read, scalar operation, and branch remains a kernel-checked obligation.
    Mutation and effectful initializers require an explicit proved contract. -/
elab "core_pure_node" : tactic => withMainContext do
  let target ← whnf (← instantiateMVars (← (← getMainGoal).getType))
  unless target.isAppOfArity ``Exists 2 do throwError "expected an existential pure statement contract"
  let .lam _ _ body _ := target.getAppArgs[1]! | throwError "expected a state binder"
  unless body.isAppOfArity ``And 2 do throwError "expected execution and a frame"
  let run := (← instantiateMVars body.getAppArgs[0]!).consumeMData
  unless run.isAppOfArity ``RunsStmt 5 do throwError "expected a statement contract"
  let statement ← whnf run.getAppArgs[2]!
  -- Prove an initializer/guard before choosing its continuation. Later proof
  -- failure must not retry the same prefix under alternative framing rules.
  let rule ← match statement.getAppFn.constName? with
    | some ``Lanius.Core.Stmt.letLocal => `(tactic| (
        (first
          | (apply RunsStmt.letPure; core_run; core_formed)
          | (apply RunsStmt.letFramedPure; core_pure_expr; intro middle frame));
        core_pure))
    | some ``Lanius.Core.Stmt.sequence => do
        let first ← whnf statement.getAppArgs[0]!
        let guard ← if first.isAppOfArity ``Lanius.Core.Stmt.ifThenElse 3 then do
          let otherwise ← whnf first.getAppArgs[2]!
          pure (otherwise.isConstOf ``Lanius.Core.Stmt.skip)
        else pure false
        if guard then
          -- Decide a skipped branch before inspecting its body. Testing a
          -- complex skipped body for completion first causes repeated
          -- backtracking through unrelated expression-inference branches.
          `(tactic| first
            | ((first
              | (apply RunsStmt.guardPureFalse; core_run)
              | (apply RunsStmt.guardFramedFalse; core_pure_guard; intro middle frame)); core_pure)
            | ((first
              | (apply RunsStmt.guardPureTrue; (solve | simp); core_run)
              | (apply RunsStmt.guardFramedTrue; (solve | simp); core_pure_guard; intro middle frame)); core_pure)
            | (apply RunsStmt.sequenceFramedNext; core_pure; intro middle frame; core_pure))
        else `(tactic| first
          | (apply RunsStmt.sequencePureCompleted; (solve | simp); core_pure)
          | (apply RunsStmt.sequencePureNext; core_stmt; core_pure)
          | (apply RunsStmt.sequenceFramedNext; core_pure; intro middle frame; core_pure))
    | some ``Lanius.Core.Stmt.ifThenElse => `(tactic| (
        (first
          | (apply RunsStmt.branchPure false; core_run)
          | (apply RunsStmt.branchPure true; core_run)
          | (apply RunsStmt.branchFramedPure false; core_pure_guard; intro middle frame)
          | (apply RunsStmt.branchFramedPure true; core_pure_guard; intro middle frame));
        core_pure))
    | some ``Lanius.Core.Stmt.returnValue => `(tactic|
        (apply RunsStmt.returnPure; core_pure_expr))
    | _ => `(tactic|
        (focus (refine ⟨_, ?_, PureFrame.refl ?_⟩; rotate_left; core_formed; core_stmt)))
  evalTactic rule

macro_rules
  | `(tactic| core_pure) => `(tactic| first | core_contract | core_pure_node)
  | `(tactic| core_pure_expr) => `(tactic| first | core_contract | core_pure_expr_node)
  | `(tactic| core_pure_guard) => `(tactic|
      first
        | (apply RunsExpr.logicalOrPure (a := false) (b := false)
           · core_pure_guard
           · intro middle frame; core_pure_guard)
        | (apply RunsExpr.booleanPure; core_pure_expr; core_guard_logic))
  | `(tactic| core_pure_arguments) => `(tactic| core_pure_arguments_node)

#print axioms RunsExpr.castPure

end Lanius.Semantics
