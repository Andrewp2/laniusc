import Lanius.ExecutionRules
import Lanius.CallContracts
import Lean.Elab.Tactic

namespace Lanius.Automation.Execute

open Lanius.Core Lanius.Semantics

/-! Small proof-producing automation for pure Core expressions and control
flow. These rules prove finite executions, not conditional correctness. Calls,
stores, and loops require supplied execution proofs; they are not unfolded. -/

theorem literal : Evaluates program state (.value value) value state := ⟨1, rfl⟩

theorem readLocal {id : VarId} (found : state.local? id = some value) :
    Evaluates program state (.local id) value state :=
  ⟨1, evalLocal_of_local 0 program state id value found⟩

theorem unary
    (operand : Evaluates program state expression value state)
    (result : evalUnaryValue program.target op value = .ok output) :
    Evaluates program state (.unary op expression) output state :=
  evaluatesUnary operand result

theorem binary
    (left : Evaluates program state lhs a state)
    (right : Evaluates program state rhs b state)
    (notAnd : op ≠ .logicalAnd) (notOr : op ≠ .logicalOr)
    (result : evalBinaryValue program.target op a b = .ok output) :
    Evaluates program state (.binary op lhs rhs) output state :=
  evaluatesEagerBinary notAnd notOr left right result

theorem or
    (left : Evaluates program state lhs (.boolean a) state)
    (right : Evaluates program state rhs (.boolean b) state)
    (result : (a || b) = output) :
    Evaluates program state (.binary .logicalOr lhs rhs) (.boolean output) state :=
  result ▸ evaluatesPureLogicalOr left right

theorem and
    (left : Evaluates program state lhs (.boolean a) state)
    (right : Evaluates program state rhs (.boolean b) state)
    (result : (a && b) = output) :
    Evaluates program state (.binary .logicalAnd lhs rhs) (.boolean output) state :=
  result ▸ evaluatesPureLogicalAnd left right

open Lean Meta Elab Tactic

macro "core_arith" : tactic => `(tactic|
  first | rfl | omega |
    (simp only [← decide_not, ← Bool.decide_or, ← Bool.decide_and, decide_eq_decide]; omega))

syntax "core_eval" "[" Lean.Parser.Tactic.dsimpArg,* "]" : tactic

elab_rules : tactic
  | `(tactic| core_eval [$facts,*]) => withMainContext do
    let saved ← saveState
    try evalTactic (← `(tactic| assumption)); return catch _ => saved.restore
    let target := (← instantiateMVars (← getMainTarget)).consumeMData
    unless target.isAppOfArity ``Evaluates 5 do
      throwError "core_eval expects an Evaluates goal"
    let expression ← whnf target.getAppArgs[2]!
    let step ← match expression.getAppFn.constName? with
      | some ``Core.Expr.value => `(tactic| exact Execute.literal)
      | some ``Core.Expr.local => `(tactic| (
          apply Execute.readLocal
          first | assumption | (simp_all (config := { failIfUnchanged := false }) [Fin.forall_iff, $facts,*] <;> rfl)))
      | some ``Core.Expr.constant => `(tactic| (apply evaluatesConstant; assumption))
      | some ``Core.Expr.unary =>
        let op ← whnf expression.getAppArgs[0]!
        let operation ← if op.isConstOf ``UnaryOp.logicalNot then
            `(tactic| first | rfl | (simp_all (config := { failIfUnchanged := false })
              [evalUnaryValue, $facts,*] <;> core_arith))
          else `(tactic| (simp_all (config := { failIfUnchanged := false }) [evalUnaryValue, wrapSigned,
            signedModulus, signedSignBit, SignedIntTy.bits, $facts,*] <;> core_arith))
        `(tactic| (
          apply Execute.unary
          · core_eval [$facts,*]
          · ($operation:tactic)))
      | some ``Core.Expr.binary =>
        let op ← whnf expression.getAppArgs[0]!
        match op.constName? with
        | some ``BinaryOp.logicalOr => `(tactic| first
            | (apply Execute.or
               · core_eval [$facts,*]
               · core_eval [$facts,*]
               · first | rfl | (simp_all (config := { failIfUnchanged := false }) [$facts,*] <;> core_arith))
            | (apply evaluatesLogicalOrTrue; core_eval [$facts,*]))
        | some ``BinaryOp.logicalAnd => `(tactic| first
            | (apply Execute.and
               · core_eval [$facts,*]
               · core_eval [$facts,*]
               · first | rfl | (simp_all (config := { failIfUnchanged := false }) [$facts,*] <;> core_arith))
            | (apply evaluatesLogicalAndFalse; core_eval [$facts,*]))
        | _ =>
          let eager ← `(tactic| (
              apply Execute.binary
              · core_eval [$facts,*]
              · core_eval [$facts,*]
              · decide
              · decide
              · simp_all (config := { failIfUnchanged := false })
                  [evalBinaryValue, evalSignedBinary, scalarEqual, $facts,*] <;> core_arith))
          if op.isConstOf ``BinaryOp.add then
            `(tactic| first
              | (apply evaluatesNatI32Add
                 · core_eval [$facts,*]
                 · core_eval [$facts,*]
                 · omega)
              | ($eager:tactic))
          else if op.isConstOf ``BinaryOp.divide then
            `(tactic| first
              | (apply evaluatesNatI32Divide
                 · core_eval [$facts,*]
                 · core_eval [$facts,*]
                 · omega
                 · omega)
              | ($eager:tactic))
          else pure eager
      | _ => throwError "core_eval needs an execution lemma for {expression}"
    evalTactic step

/-- Structural execution uses already proved effectful steps from the local
context. It never unfolds a callee, store, or loop to search for a proof. -/
syntax "core_exec" "[" Lean.Parser.Tactic.dsimpArg,* "]" : tactic

elab_rules : tactic
  | `(tactic| core_exec [$facts,*]) => withMainContext do
    let saved ← saveState
    try evalTactic (← `(tactic| assumption)); return catch _ => saved.restore
    let target := (← instantiateMVars (← getMainTarget)).consumeMData
    unless target.isAppOfArity ``Executes 5 do
      throwError "core_exec expects an Executes goal, got {target}"
    let statement ← whnf target.getAppArgs[2]!
    let step ← match statement.getAppFn.constName? with
      | some ``Stmt.skip => `(tactic| exact executesSkip _ _)
      | some ``Stmt.returnValue => `(tactic| (apply executesReturnValue; core_eval [$facts,*]))
      | some ``Stmt.expression => `(tactic| (apply executesExpression; core_eval [$facts,*]))
      | some ``Stmt.ifThenElse => `(tactic|
          first
          | (apply executesIfTrue
             · core_eval [$facts,*]
             · core_exec [$facts,*])
          | (apply executesIfFalse
             · core_eval [$facts,*]
             · core_exec [$facts,*]))
      | some ``Stmt.sequence => `(tactic|
          first
          | (apply executesSequenceReturned; core_exec [$facts,*])
          | (apply executesSequence
             · core_exec [$facts,*]
             · core_exec [$facts,*]))
      | _ => throwError "core_exec needs an execution lemma for {statement}"
    evalTactic step

/-- Compose argument evaluation left to right. Effectful arguments require
supplied execution proofs, just as `core_eval` does; callees are not unfolded. -/
syntax "core_args" "[" Lean.Parser.Tactic.dsimpArg,* "]" : tactic

elab_rules : tactic
  | `(tactic| core_args [$facts,*]) => withMainContext do
    let saved ← saveState
    try evalTactic (← `(tactic| assumption)); return catch _ => saved.restore
    let target := (← instantiateMVars (← getMainTarget)).consumeMData
    unless target.isAppOfArity ``CallContracts.ArgumentsEvaluateTo 5 do
      throwError "core_args expects an ArgumentsEvaluateTo goal"
    let arguments ← whnf target.getAppArgs[2]!
    if arguments.isAppOf ``List.nil then
      evalTactic (← `(tactic| exact CallContracts.ArgumentsEvaluateTo.nil _ _))
    else if arguments.isAppOf ``List.cons then
      evalTactic (← `(tactic| (
        apply CallContracts.ArgumentsEvaluateTo.cons
        · core_eval [$facts,*]
        · core_args [$facts,*])))
    else throwError "core_args needs a concrete argument-list shape"

end Lanius.Automation.Execute
