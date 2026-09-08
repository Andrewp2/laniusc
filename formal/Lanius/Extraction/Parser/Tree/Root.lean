import Lanius.Extraction.Parser.Tree.MaterializeSource
import Lanius.Extraction.Parser.Tree.Execution

namespace Lanius.Extraction.ParserTreeSource

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.Extraction.CoreSynthesis.Program

def rootBody (success : Lanius.ConstantId) : Stmt :=
  .sequence (.ifThenElse (.binary .notEqual (.field (.local 0) 0) (.constant success))
    (.sequence (.returnValue (some (.unary .negate (.value (.signed .i32 1))))) .skip) .skip)
    (.sequence (.returnValue (some (.binary .subtract (.field (.local 0) 1) (.value (.signed .i32 1))))) .skip)

structure CheckedRoot (visit : CheckedVisit program) where
  source : CheckedSourceFunction program ["verified", "parse_tree"] "tree_root"
  signature : source.function.parameters = [(0, .structure visit.symbols.resultType)] ∧
    source.function.returnType = .scalar (.signed .i32) ∧ source.function.external = none
  body : source.function.body = some (rootBody visit.symbols.statusBase)

def checkRoot? (visit : CheckedVisit program) : Option (CheckedRoot visit) := do
  let source ← checkSourceFunction? program ["verified", "parse_tree"] "tree_root"
  if signature : source.function.parameters = [(0, .structure visit.symbols.resultType)] ∧
      source.function.returnType = .scalar (.signed .i32) ∧ source.function.external = none then
    match present : source.function.body with
    | none => none
    | some body => do
      let equal ← Lanius.Core.Equality.statement? body (rootBody visit.symbols.statusBase)
      pure ⟨source, signature, present.trans (congrArg some equal.equal)⟩
  else none

/-- Every nonzero status yields the sentinel, even if a failed materialization
    left positive partial counts. Success returns the actual i32 subtraction. -/
theorem CheckedRoot.call {visit : CheckedVisit program} (checked : CheckedRoot visit)
    (wellFormed : StateWellFormed afterArguments)
    (argumentsResult : ArgumentsEvaluateTo program.core before arguments
      [resultValue visit.symbols.resultType status nodes words] afterArguments) :
    ∃ after, Evaluates program.core before (.call checked.source.function.id arguments)
        (.signed .i32 (if status = 0 then wrapSigned program.core.target .i32 (nodes - 1) else -1)) after ∧
      CellEffect CellSet.empty afterArguments after := by
  let bindings : List (Lanius.VarId × Value) := [(0, resultValue visit.symbols.resultType status nodes words)]
  let callee := enterCall afterArguments bindings
  have calleeWF : StateWellFormed callee := enterCall_preserves_wellFormed wellFormed
  have found : callee.local? 0 = some (resultValue visit.symbols.resultType status nodes words) :=
    enterCall_local_of_binding afterArguments [] [] 0 _ wellFormed (by simp)
  have localRead : Evaluates program.core callee (.local 0)
      (resultValue visit.symbols.resultType status nodes words) callee :=
    ⟨1, evalLocal_of_local 0 program.core callee 0 _ found⟩
  have statusRead := evaluatesStructureField localRead (show
    [Value.signed .i32 status, .signed .i32 nodes, .signed .i32 words][0]? = some (.signed .i32 status) from rfl)
  have nodesRead := evaluatesStructureField localRead (show
    [Value.signed .i32 status, .signed .i32 nodes, .signed .i32 words][1]? = some (.signed .i32 nodes) from rfl)
  have body : Executes program.core callee (rootBody visit.symbols.statusBase)
      (.returned (some (.signed .i32 (if status = 0 then wrapSigned program.core.target .i32 (nodes - 1) else -1)))) callee := by
    by_cases success : status = 0
    · have condition : Evaluates program.core callee
          (.binary .notEqual (.field (.local 0) 0) (.constant visit.symbols.statusBase)) (.boolean false) callee :=
        evaluatesEagerBinary (by decide) (by decide) statusRead (evaluatesConstant visit.statuses.1)
          (by simp [evalBinaryValue, scalarEqual, success])
      have subtract : Evaluates program.core callee
          (.binary .subtract (.field (.local 0) 1) (.value (.signed .i32 1)))
          (.signed .i32 (wrapSigned program.core.target .i32 (nodes - 1))) callee :=
        evaluatesEagerBinary (by decide) (by decide) nodesRead ⟨1, rfl⟩ rfl
      simpa only [rootBody, if_pos success] using
        executesSequence (executesIfFalse condition (executesSkip _ _))
          (executesSequenceReturned (executesReturnValue subtract))
    · have condition : Evaluates program.core callee
          (.binary .notEqual (.field (.local 0) 0) (.constant visit.symbols.statusBase)) (.boolean true) callee :=
        evaluatesEagerBinary (by decide) (by decide) statusRead (evaluatesConstant visit.statuses.1)
          (by simp [evalBinaryValue, scalarEqual, success])
      have sentinel : Evaluates program.core callee (.unary .negate (.value (.signed .i32 1)))
          (.signed .i32 (-1)) callee := by
        apply evaluatesUnary (show Evaluates program.core callee (.value (.signed .i32 1))
          (.signed .i32 1) callee from ⟨1, rfl⟩)
        simp [evalUnaryValue, wrapSigned, signedModulus, signedSignBit, SignedIntTy.bits]
      simpa only [rootBody, if_neg success] using executesSequenceReturned
        (executesIfTrue condition (executesSequenceReturned (executesReturnValue sentinel)))
  have identity : checked.source.function.id = checked.source.source.id := by
    simpa [Program.function?] using List.find?_some checked.source.found
  have functionFound : program.core.function? checked.source.function.id = some checked.source.function := by
    rw [identity]
    exact checked.source.found
  have bound : bindParameters checked.source.function.parameters
      [resultValue visit.symbols.resultType status nodes words] = some bindings := by
    rw [checked.signature.1]
    rfl
  exact ⟨restoreLocals afterArguments callee,
    evaluatesCallReturned argumentsResult functionFound bound checked.body body,
    CellEffect.closeCall afterArguments bindings wellFormed (CellEffect.refl calleeWF)⟩

end Lanius.Extraction.ParserTreeSource
