import Lanius.Automation.Execute
import Lanius.Automation.Contract
import Lanius.Extraction.Source.Call
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Automation

open Lanius.Core Lanius.Semantics Lanius.Separation

/-- An arbitrary, potentially trapping RHS is never evaluated. -/
theorem shortCircuitOr (program : Program) (state : State) (rhs : Expr) :
    Evaluates program state (.binary .logicalOr (.value (.boolean true)) rhs)
      (.boolean true) state := by core_eval []

theorem shortCircuitAnd (program : Program) (state : State) (rhs : Expr) :
    Evaluates program state (.binary .logicalAnd (.value (.boolean false)) rhs)
      (.boolean false) state := by core_eval []

/-- The rest of a sequence is skipped after a return, including arbitrary
calls or stores. No execution assumption for `rest` is supplied. -/
theorem earlyReturn (program : Program) (state : State) (rest : Stmt) :
    Executes program state (.sequence (.returnValue (some (.value (.signed .i32 7)))) rest)
      (.returned (some (.signed .i32 7))) state := by core_exec []

theorem guardedCall (run : Evaluates program before (.call function arguments) value after) :
    Executes program before
      (.sequence (.ifThenElse (.value (.boolean false))
        (.returnValue (some (.value (.signed .i32 (-1))))) .skip)
        (.sequence (.returnValue (some (.call function arguments))) .skip))
      (.returned (some value)) after := by core_exec []

theorem boundedGuardCall (code : Fin 16)
    (found : before.local? 0 = some (.signed .i32 code.val))
    (run : Evaluates program before (.call function arguments) value after) :
    Executes program before
      (.sequence (.ifThenElse (.binary .logicalOr
          (.binary .less (.local 0) (.value (.signed .i32 0)))
          (.binary .greater (.local 0) (.value (.signed .i32 15))))
        (.returnValue (some (.value (.signed .i32 (-1))))) .skip)
        (.sequence (.returnValue (some (.call function arguments))) .skip))
      (.returned (some value)) after := by
  have range := code.isLt
  core_exec []

theorem effectfulArguments
    (first : Evaluates program before a av middle)
    (second : Evaluates program middle b bv after) :
    CallContracts.ArgumentsEvaluateTo program before [a, b] [av, bv] after := by core_args []

/-- Parameter facts may use finite indices; callers should not need a separate
lookup lemma for each parameter or for repeated/reordered pure reads. -/
theorem parameterArguments (values : List Value) (a b : Fin values.length)
    (locals : ∀ index : Fin values.length, before.local? index.val = some (values.get index)) :
    CallContracts.ArgumentsEvaluateTo program before [.local b.val, .local a.val, .local b.val]
      [values.get b, values.get a, values.get b] before := by core_args []

theorem nestedCellSpecs
    (pre middle post : State → Prop)
    (first : CallContracts.CellSpec program firstFunction [] firstValue
      pre (fun _ after => middle after) CellSet.empty)
    (second : CallContracts.CellSpec program secondFunction [firstValue, constant] result
      middle (fun _ after => post after) CellSet.empty) :
    CallContracts.ExprSpec program locals CellSet.empty
      (.call secondFunction [.call firstFunction [], .value constant]) result pre post := by
  core_spec [first, second]

example (pre middle post missing : State → Prop) (wrong : Value)
    (first : CallContracts.CellSpec program firstFunction [] firstValue
      pre (fun _ after => middle after) CellSet.empty)
    (second : CallContracts.CellSpec program secondFunction [firstValue, constant] result
      middle (fun _ after => post after) CellSet.empty) : True := by
  fail_if_success
    have : CallContracts.ExprSpec program locals CellSet.empty
        (.call firstFunction [.call secondFunction [], .value constant]) result pre post := by
      core_spec [first, second]
  fail_if_success
    have : CallContracts.ExprSpec program locals CellSet.empty
        (.call secondFunction [.call firstFunction [], .value constant]) wrong pre post := by
      core_spec [first, second]
  fail_if_success
    have : CallContracts.ExprSpec program locals CellSet.empty
        (.call secondFunction [.call firstFunction [], .value constant]) result missing post := by
      core_spec [first, second]
  trivial

example (first : Evaluates program before a av middle)
    (second : Evaluates program middle b bv after) : True := by
  fail_if_success
    have : CallContracts.ArgumentsEvaluateTo program before [b, a] [bv, av] after := by core_args []
  fail_if_success
    have : CallContracts.ArgumentsEvaluateTo program before [a, b] [av, bv] before := by core_args []
  trivial

theorem overflowWraps (program : Program) (state : State) :
    Evaluates program state (.binary .add (.value (.signed .i32 2147483647))
      (.value (.signed .i32 1))) (.signed .i32 (-2147483648)) state := by
  core_eval [wrapSigned, signedModulus, signedSignBit, SignedIntTy.bits]

example (_program : Program) (_state : State) : True := by
  fail_if_success
    have : Evaluates _program _state (.binary .add (.value (.signed .i32 2147483647))
        (.value (.signed .i32 1))) (.signed .i32 2147483648) _state := by
      core_eval [wrapSigned, signedModulus, signedSignBit, SignedIntTy.bits]
  fail_if_success
    have : Executes _program _state (.whileLoop (.value (.boolean true)) .skip) .next _state := by
      core_exec []
  fail_if_success
    have : Executes _program _state (.returnValue (some (.value (.signed .i32 0))))
        (.returned (some (.signed .i32 1))) _state := by core_exec []
  fail_if_success
    have : CallContracts.ArgumentsEvaluateTo _program _state [.call 0 []]
        [.signed .i32 0] _state := by core_args []
  trivial

run_elab do
  let standard : Array Lean.Name := #[``propext, ``Classical.choice, ``Quot.sound]
  for name in #[``shortCircuitOr, ``shortCircuitAnd, ``earlyReturn, ``overflowWraps,
      ``guardedCall, ``boundedGuardCall, ``effectfulArguments, ``parameterArguments,
      ``nestedCellSpecs,
      ``Source.CheckedInternal.specPure] do
    let axioms ← Lean.collectAxioms name
    unless axioms.all standard.contains do throwError "automation added trust: {name}: {axioms}"
  Lean.logInfo "Execution automation proves finite runs with only standard Lean axioms."

end Lanius.Extraction.Tests.Automation
