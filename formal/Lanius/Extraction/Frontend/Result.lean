import Lanius.Extraction.Parser.Tree.MaterializeSource
import Lanius.Extraction.Parser.Tree.Execution
import Lanius.Separation.LocalStore

namespace Lanius.Extraction.Frontend

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.Extraction.CoreSynthesis.Program Lanius.FunctionalView.Core

def syntaxResult (typeId : TypeId) (stage detail raw tokens nodes words position : Int) : Value :=
  .structure typeId [.signed .i32 stage, .signed .i32 detail, .signed .i32 raw, .signed .i32 tokens,
    .signed .i32 nodes, .signed .i32 words, .signed .i32 position]

def syntaxResultParameters : List (VarId × Ty) :=
  [(0, .scalar (.signed .i32)), (1, .scalar (.signed .i32)), (2, .scalar (.signed .i32)),
    (3, .scalar (.signed .i32)), (4, .scalar (.signed .i32)), (5, .scalar (.signed .i32)), (6, .scalar (.signed .i32))]

def syntaxResultBody (typeId : TypeId) : Stmt :=
  .sequence (.returnValue (some (.structValue typeId
    [.local 0, .local 1, .local 2, .local 3, .local 4, .local 5, .local 6]))) .skip

structure CheckedResult (program : CheckedProgram artifacts) where
  source : CheckedSourceFunction program ["verified", "extraction"] "result"
  typeId : TypeId
  signature : source.function.parameters = syntaxResultParameters ∧
    source.function.returnType = .structure typeId ∧ source.function.external = none
  body : source.function.body = some (syntaxResultBody typeId)

def checkResult? (program : CheckedProgram artifacts) : Option (CheckedResult program) := do
  let source ← checkSourceFunction? program ["verified", "extraction"] "result"
  match resultType : source.function.returnType, present : source.function.body with
  | .structure typeId, some body => do
    if shape : source.function.parameters = syntaxResultParameters ∧ source.function.external = none then
      let equal ← Core.Equality.statement? body (syntaxResultBody typeId)
      pure ⟨source, typeId, ⟨shape.1, resultType, shape.2⟩, present.trans (congrArg some equal.equal)⟩
    else none
  | _, _ => none

theorem CheckedResult.call (checked : CheckedResult program)
    (wellFormed : StateWellFormed afterArguments)
    (argumentsResult : ArgumentsEvaluateTo program.core before arguments
      [.signed .i32 stage, .signed .i32 detail, .signed .i32 raw, .signed .i32 tokens,
        .signed .i32 nodes, .signed .i32 words, .signed .i32 position] afterArguments) :
    ∃ after, Evaluates program.core before (.call checked.source.function.id arguments)
        (syntaxResult checked.typeId stage detail raw tokens nodes words position) after ∧
      CellEffect CellSet.empty afterArguments after := by
  let values : List Value := [.signed .i32 stage, .signed .i32 detail, .signed .i32 raw, .signed .i32 tokens,
    .signed .i32 nodes, .signed .i32 words, .signed .i32 position]
  let bindings := parameterBindings (fun index : Fin 7 => values.get index)
  let callee := enterCall afterArguments bindings
  have calleeWF : StateWellFormed callee := enterCall_preserves_wellFormed wellFormed
  have parameter (index : Fin 7) : Evaluates program.core callee (.local index.val) (values.get index) callee :=
    ⟨1, evalLocal_of_local 0 _ _ _ _ (enterCall_parameterBindings_matches wellFormed index)⟩
  have fields : ArgumentsEvaluateTo program.core callee
      [.local 0, .local 1, .local 2, .local 3, .local 4, .local 5, .local 6] values callee :=
    .cons (parameter ⟨0, by decide⟩) (.cons (parameter ⟨1, by decide⟩)
      (.cons (parameter ⟨2, by decide⟩) (.cons (parameter ⟨3, by decide⟩)
        (.cons (parameter ⟨4, by decide⟩) (.cons (parameter ⟨5, by decide⟩)
          (.singleton (parameter ⟨6, by decide⟩)))))))
  have body : Executes program.core callee (syntaxResultBody checked.typeId)
      (.returned (some (syntaxResult checked.typeId stage detail raw tokens nodes words position))) callee :=
    executesSequenceReturned (executesReturnValue (evaluatesStructValue fields))
  have identity : checked.source.function.id = checked.source.source.id := by
    simpa [Program.function?] using List.find?_some checked.source.found
  have found : program.core.function? checked.source.function.id = some checked.source.function := by
    rw [identity]; exact checked.source.found
  have bound : bindParameters checked.source.function.parameters values = some bindings := by
    rw [checked.signature.1]; rfl
  exact ⟨restoreLocals afterArguments callee,
    evaluatesCallReturned argumentsResult found bound checked.body body,
    CellEffect.closeCall afterArguments bindings wellFormed (CellEffect.refl calleeWF)⟩

structure FinishSymbols where
  result : FunctionId
  status : FunctionId
  nodes : FunctionId
  words : FunctionId
  success : ConstantId
  failure : ConstantId
  treeSuccess : ConstantId

def finishReturn (symbols : FinishSymbols) : Stmt :=
  .sequence (.returnValue (some (.call symbols.result
    [.local 24, .call symbols.status [.local 23], .local 18, .local 20,
      .call symbols.nodes [.local 23], .call symbols.words [.local 23], .value (.signed .i32 0)]))) .skip

def finishCondition (symbols : FinishSymbols) : Expr :=
  .binary .notEqual (.call symbols.status [.local 23]) (.constant symbols.treeSuccess)

def finishBody (symbols : FinishSymbols) : Stmt :=
  .letLocal 24 (.scalar (.signed .i32)) (.constant symbols.success)
    (.sequence (.ifThenElse (finishCondition symbols)
      (.sequence (.expression (.assign .set (.local 24) (.constant symbols.failure))) .skip) .skip)
      (finishReturn symbols))

structure CheckedFinish (visit : ParserTreeSource.CheckedVisit program) where
  constructor : CheckedResult program
  status : Source.CheckedProjection program ["verified", "parse_tree"] "tree_status" visit.symbols.resultType 0
  nodes : Source.CheckedProjection program ["verified", "parse_tree"] "tree_node_count" visit.symbols.resultType 1
  words : Source.CheckedProjection program ["verified", "parse_tree"] "tree_words_used" visit.symbols.resultType 2
  successId : ConstantId
  failureId : ConstantId
  success : ParserTreeSource.constantValue program.core successId 0
  failure : ParserTreeSource.constantValue program.core failureId 5

def CheckedFinish.symbols (checked : CheckedFinish visit) : FinishSymbols :=
  ⟨checked.constructor.source.function.id, checked.status.source.function.id,
    checked.nodes.source.function.id, checked.words.source.function.id,
    checked.successId, checked.failureId, visit.symbols.statusBase⟩

def checkFinish? (visit : ParserTreeSource.CheckedVisit program) (statement : Stmt) :
    Option (Σ checked : CheckedFinish visit, Core.Equality.Evidence statement (finishBody checked.symbols)) := do
  let .letLocal _ _ (.constant successId)
    (.sequence (.ifThenElse _ (.sequence (.expression (.assign .set _ (.constant failureId))) .skip) .skip) _) := statement
    | none
  let constructor ← checkResult? program
  let status ← Source.checkProjection? program ["verified", "parse_tree"] "tree_status" visit.symbols.resultType 0
  let nodes ← Source.checkProjection? program ["verified", "parse_tree"] "tree_node_count" visit.symbols.resultType 1
  let words ← Source.checkProjection? program ["verified", "parse_tree"] "tree_words_used" visit.symbols.resultType 2
  let success ← ParserTreeSource.checkConstantValue? program.core successId 0
  let failure ← ParserTreeSource.checkConstantValue? program.core failureId 5
  let checked : CheckedFinish visit := ⟨constructor, status, nodes, words, successId, failureId, success.equal, failure.equal⟩
  let exactBody ← Core.Equality.statement? statement (finishBody checked.symbols)
  pure ⟨checked, exactBody⟩

def extractionTreeStage (code : Int) : Int := if code = 0 then 0 else 5

private theorem local_read {id : VarId} (found : before.local? id = some value) :
    Evaluates program before (.local id) value before :=
  ⟨1, evalLocal_of_local 0 _ _ _ _ found⟩

/-- Derive all seven returned fields, evaluating the actual accessor calls in
source order. This covers both success and nonzero tree status without treating
partial output as an accepted certificate. The stage local is fresh and hidden. -/
theorem CheckedFinish.execute {visit : ParserTreeSource.CheckedVisit program}
    {code raw tokens nodes words : Int} (checked : CheckedFinish visit)
    (before : State) (wellFormed : StateWellFormed before)
    (treeLocal : before.local? 23 = some (ParserTreeSource.resultValue visit.symbols.resultType code nodes words))
    (rawLocal : before.local? 18 = some (.signed .i32 raw))
    (countLocal : before.local? 20 = some (.signed .i32 tokens)) :
    ∃ after, Executes program.core before (finishBody checked.symbols)
        (.returned (some (syntaxResult checked.constructor.typeId (extractionTreeStage code) code raw tokens nodes words 0))) after ∧
      CellEffect CellSet.empty before after := by
  let entered := before.bindLocal 24 (.signed .i32 0)
  have enteredWF : StateWellFormed entered := bindLocal_preserves_well_formed _ _ _ wellFormed
  have enteredTree : entered.local? 23 = some (ParserTreeSource.resultValue visit.symbols.resultType code nodes words) :=
    (bindLocal_preserves_other_local wellFormed (by decide)).trans treeLocal
  have stageOwned : (Assertion.localPointsTo 24 before.nextCell (some (.signed .i32 0))).holds entered :=
    bindLocal_owns_fresh before 24 (.signed .i32 0) wellFormed
  obtain ⟨tested, statusCall, statusEffect⟩ := checked.status.call enteredWF (.singleton (local_read enteredTree)) rfl
  have guardRun : Evaluates program.core entered (finishCondition checked.symbols) (.boolean (decide (code ≠ 0))) tested :=
    evaluatesEagerBinary (by decide) (by decide) statusCall (evaluatesConstant visit.statuses.1)
      (by by_cases same : code = 0 <;> simp [evalBinaryValue, scalarEqual, same])
  have selected : ∃ selected,
      Executes program.core entered (.ifThenElse (finishCondition checked.symbols)
        (.sequence (.expression (.assign .set (.local 24) (.constant checked.failureId))) .skip) .skip) .next selected ∧
      selected.local? 24 = some (.signed .i32 (extractionTreeStage code)) ∧
      CellEffect (CellSet.singleton before.nextCell) entered selected := by
    by_cases success : code = 0
    · refine ⟨tested, executesIfFalse (by simpa only [success, ne_eq, not_true_eq_false, decide_false] using guardRun)
        (executesSkip _ _), ?_, statusEffect.weaken CellSet.empty_subset⟩
      simpa only [extractionTreeStage, if_pos success] using statusEffect.empty_preserves_local enteredWF
        (Assertion.localPointsTo_local _ _ _ _ stageOwned)
    · obtain ⟨updated, assigned, updatedStage, updateEffect⟩ := evaluatesOwnedLocalUpdate (op := .set) statusEffect.wellFormed
        (statusEffect.preserves_localPointsTo enteredWF stageOwned (by simp [CellSet.empty]))
        (evaluatesConstant checked.failure) rfl
      refine ⟨updated, executesIfTrue (by simpa [success] using guardRun)
        (executesSequence (executesExpression assigned) (executesSkip _ _)), ?_,
        (statusEffect.weaken CellSet.empty_subset).trans updateEffect⟩
      simpa only [extractionTreeStage, if_neg success] using Assertion.localPointsTo_local _ _ _ _ updatedStage
  obtain ⟨selected, selectRun, stageLocal, selectEffect⟩ := selected
  have preserved {id : VarId} {value : Value} (different : 24 ≠ id) (found : before.local? id = some value) :
      selected.local? id = some value := by
    apply selectEffect.preserves_local enteredWF ((bindLocal_preserves_other_local wellFormed different).trans found)
    intro cell binding written
    have oldBinding : before.cellId? id = some cell := by
      simpa only [entered, bindLocal_preserves_other_cellId before 24 id (.signed .i32 0) different] using binding
    exact Nat.ne_of_lt (StateWellFormed.cell_lt_next_of_local_binding id cell wellFormed oldBinding) written
  have selectedTree := preserved (by decide : 24 ≠ 23) treeLocal
  obtain ⟨detailed, detailCall, detailEffect⟩ := checked.status.call selectEffect.wellFormed
    (.singleton (local_read selectedTree)) rfl
  obtain ⟨counted, nodesCall, nodesEffect⟩ := checked.nodes.call detailEffect.wellFormed
    (.singleton (local_read (detailEffect.empty_preserves_local selectEffect.wellFormed selectedTree))) rfl
  obtain ⟨measured, wordsCall, wordsEffect⟩ := checked.words.call nodesEffect.wellFormed
    (.singleton (local_read (nodesEffect.empty_preserves_local detailEffect.wellFormed
      (detailEffect.empty_preserves_local selectEffect.wellFormed selectedTree)))) rfl
  have arguments : ArgumentsEvaluateTo program.core selected
      [.local 24, .call checked.symbols.status [.local 23], .local 18, .local 20,
        .call checked.symbols.nodes [.local 23], .call checked.symbols.words [.local 23], .value (.signed .i32 0)]
      [.signed .i32 (extractionTreeStage code), .signed .i32 code, .signed .i32 raw, .signed .i32 tokens,
        .signed .i32 nodes, .signed .i32 words, .signed .i32 0] measured :=
    .cons (local_read stageLocal) (.cons detailCall
      (.cons (local_read (detailEffect.empty_preserves_local selectEffect.wellFormed (preserved (by decide) rawLocal)))
        (.cons (local_read (detailEffect.empty_preserves_local selectEffect.wellFormed (preserved (by decide) countLocal)))
          (.cons nodesCall (.cons wordsCall (.singleton ⟨1, rfl⟩))))))
  obtain ⟨completed, returned, returnEffect⟩ := checked.constructor.call wordsEffect.wellFormed arguments
  have finalEffect := selectEffect.trans
    ((detailEffect.trans (nodesEffect.trans (wordsEffect.trans returnEffect))).weaken CellSet.empty_subset)
  refine ⟨restoreLocals before completed, ?_,
    (CellEffect.closeLocal before 24 (.signed .i32 0) wellFormed finalEffect).narrow ?_⟩
  · exact executesLetLocal (evaluatesConstant checked.success)
      (executesSequence selectRun (executesSequenceReturned (executesReturnValue returned)))
  · intro cell old written
    exact (Nat.ne_of_lt old written).elim

end Lanius.Extraction.Frontend
