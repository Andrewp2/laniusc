import Lanius.Extraction.Frontend.Guards
import Lanius.Extraction.Frontend.Result

namespace Lanius.Extraction.Frontend

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.Extraction.CoreSynthesis.Program

structure CheckedEarly (program : CheckedProgram artifacts) (symbols : TokenizationSymbols) where
  constructor : CheckedResult program
  status : Source.CheckedProjection program ["verified", "raw_lexer"] "lex_status" symbols.resultType 0
  error : Source.CheckedProjection program ["verified", "raw_lexer"] "lex_error_offset" symbols.resultType 2
  statusId : symbols.status = status.source.function.id
  lexerSuccess : ParserTreeSource.constantValue program.core symbols.success 0
  lexicalId : ConstantId
  storageId : ConstantId
  lexical : ParserTreeSource.constantValue program.core lexicalId 2
  storage : ParserTreeSource.constantValue program.core storageId 3

def CheckedEarly.lexicalBody (checked : CheckedEarly program symbols) : Stmt :=
  .sequence (.returnValue (some (.call checked.constructor.source.function.id
    [.constant checked.lexicalId, .call checked.status.source.function.id [.local 17], .local 18,
      .value (.signed .i32 0), .value (.signed .i32 0), .value (.signed .i32 0),
      .call checked.error.source.function.id [.local 17]]))) .skip

def CheckedEarly.storageCall (checked : CheckedEarly program symbols) (detail : Int) (tokens : Expr) : Expr :=
  .call checked.constructor.source.function.id [.constant checked.storageId, .value (.signed .i32 detail),
    .local 18, tokens, .value (.signed .i32 0), .value (.signed .i32 0), .value (.signed .i32 0)]

def CheckedEarly.canonicalBody (checked : CheckedEarly program symbols) : Stmt :=
  .sequence (.returnValue (some (checked.storageCall 0 (.value (.signed .i32 0))))) .skip

def CheckedEarly.kindsBody (checked : CheckedEarly program symbols) : Stmt :=
  .sequence (.returnValue (some (checked.storageCall 1 (.local 20)))) .skip

structure EarlySource (constructor : CheckedResult program) (tokenization : Tokenization) (recognition : RecognitionStage) where
  checked : CheckedEarly program tokenization.symbols
  result : checked.constructor = constructor
  lexical : tokenization.lexicalFailure = checked.lexicalBody
  canonical : tokenization.storageFailure = checked.canonicalBody
  kinds : recognition.storageFailure = checked.kindsBody

/-- Check all early return fields against the same result constructor used by
the final parse/tree tail, including the distinction between both storage errors. -/
def checkEarly? (constructor : CheckedResult program) (tokenization : Tokenization) (recognition : RecognitionStage) :
    Option (EarlySource constructor tokenization recognition) := do
  let .sequence (.returnValue (some (.call _ (.constant lexicalId :: _)))) .skip := tokenization.lexicalFailure | none
  let .sequence (.returnValue (some (.call _ (.constant storageId :: _)))) .skip := tokenization.storageFailure | none
  let status ← Source.checkProjection? program ["verified", "raw_lexer"] "lex_status" tokenization.symbols.resultType 0
  let error ← Source.checkProjection? program ["verified", "raw_lexer"] "lex_error_offset" tokenization.symbols.resultType 2
  if statusId : tokenization.symbols.status = status.source.function.id then
    let success ← ParserTreeSource.checkConstantValue? program.core tokenization.symbols.success 0
    let lexical ← ParserTreeSource.checkConstantValue? program.core lexicalId 2
    let storage ← ParserTreeSource.checkConstantValue? program.core storageId 3
    let checked : CheckedEarly program tokenization.symbols :=
      ⟨constructor, status, error, statusId, success.equal, lexicalId, storageId, lexical.equal, storage.equal⟩
    let lexEq ← Core.Equality.statement? tokenization.lexicalFailure checked.lexicalBody
    let canEq ← Core.Equality.statement? tokenization.storageFailure checked.canonicalBody
    let kindsEq ← Core.Equality.statement? recognition.storageFailure checked.kindsBody
    pure ⟨checked, rfl, lexEq.equal, canEq.equal, kindsEq.equal⟩
  else none

private theorem local_read {id : VarId} (found : before.local? id = some value) :
    Evaluates program before (.local id) value before := ⟨1, evalLocal_of_local 0 _ _ _ _ found⟩

private theorem CheckedEarly.storage_return (checked : CheckedEarly program symbols)
    (wellFormed : StateWellFormed before) (detail : Int) (tokens : Expr)
    (rawLocal : before.local? 18 = some (.signed .i32 rawCount))
    (tokenResult : Evaluates program.core before tokens (.signed .i32 tokenCount) before) :
    ∃ after, Evaluates program.core before (checked.storageCall detail tokens)
        (syntaxResult checked.constructor.typeId 3 detail rawCount tokenCount 0 0 0) after ∧
      CellEffect CellSet.empty before after := by
  apply checked.constructor.call wellFormed
  exact .cons (evaluatesConstant checked.storage) (.cons ⟨1, rfl⟩ (.cons (local_read rawLocal)
    (.cons tokenResult (.cons ⟨1, rfl⟩ (.cons ⟨1, rfl⟩ (.singleton ⟨1, rfl⟩))))))

/-- The lexer failure guard and actual return, including repeated status/error
accessors. Later capacity checks and stages are unreachable on this branch. -/
theorem CheckedEarly.lexer_failure (checked : CheckedEarly program symbols)
    (before : State) (wellFormed : StateWellFormed before)
    (resultLocal : before.local? 17 = some (.structure symbols.resultType
      [.signed .i32 code, .signed .i32 count, .signed .i32 position]))
    (countLocal : before.local? 18 = some (.signed .i32 count)) (failed : code ≠ 0) :
    ∃ after, (∀ storageFailure rest, Executes program.core before
        (tokenGuards symbols checked.lexicalBody storageFailure rest).body
        (.returned (some (syntaxResult checked.constructor.typeId 2 code count 0 0 0 position))) after) ∧
      CellEffect CellSet.empty before after := by
  obtain ⟨guarded, statusCall, statusEffect⟩ := checked.status.call wellFormed
    (.singleton (local_read resultLocal)) rfl
  have guardRun : Evaluates program.core before
      (.binary .notEqual (.call symbols.status [.local 17]) (.constant symbols.success)) (.boolean true) guarded := by
    rw [checked.statusId]
    exact evaluatesEagerBinary (by decide) (by decide) statusCall (evaluatesConstant checked.lexerSuccess)
      (by simp [evalBinaryValue, scalarEqual, failed])
  obtain ⟨detailed, detailCall, detailEffect⟩ := checked.status.call statusEffect.wellFormed
    (.singleton (local_read (statusEffect.empty_preserves_local wellFormed resultLocal))) rfl
  have prefixEffect := statusEffect.trans detailEffect
  obtain ⟨positioned, errorCall, errorEffect⟩ := checked.error.call detailEffect.wellFormed
    (.singleton (local_read (prefixEffect.empty_preserves_local wellFormed resultLocal))) rfl
  have arguments : ArgumentsEvaluateTo program.core guarded
      [.constant checked.lexicalId, .call checked.status.source.function.id [.local 17], .local 18,
        .value (.signed .i32 0), .value (.signed .i32 0), .value (.signed .i32 0),
        .call checked.error.source.function.id [.local 17]]
      [.signed .i32 2, .signed .i32 code, .signed .i32 count, .signed .i32 0, .signed .i32 0,
        .signed .i32 0, .signed .i32 position] positioned := by
    refine .cons (evaluatesConstant checked.lexical) (.cons detailCall ?_)
    refine .cons (local_read (prefixEffect.empty_preserves_local wellFormed countLocal)) ?_
    exact .cons ⟨1, rfl⟩ (.cons ⟨1, rfl⟩ (.cons ⟨1, rfl⟩ (.singleton errorCall)))
  obtain ⟨after, returned, returnEffect⟩ := checked.constructor.call errorEffect.wellFormed arguments
  refine ⟨after, ?_, prefixEffect.trans (errorEffect.trans returnEffect)⟩
  intro storageFailure rest
  exact executesSequenceReturned (executesIfTrue guardRun (executesSequenceReturned (executesReturnValue returned)))

/-- Canonical capacity is checked in words divided by three. Returning here
preserves every caller cell, including the uninitialized canonical destination. -/
theorem CheckedEarly.canonical_full (checked : CheckedEarly program symbols)
    (before : State) (wellFormed : StateWellFormed before) (count capacity : Nat)
    (resultLocal : before.local? 17 = some (.structure symbols.resultType
      [.signed .i32 0, .signed .i32 count, .signed .i32 0]))
    (countLocal : before.local? 18 = some (.signed .i32 count))
    (capacityLocal : before.local? 7 = some (.signed .i32 capacity))
    (bounded : capacity ≤ 2147483647) (full : capacity < 3 * count) :
    ∃ after, (∀ lexicalFailure rest, Executes program.core before
        (tokenGuards symbols lexicalFailure checked.canonicalBody rest).body
        (.returned (some (syntaxResult checked.constructor.typeId 3 0 count 0 0 0 0))) after) ∧
      CellEffect CellSet.empty before after := by
  obtain ⟨guarded, statusCall, statusEffect⟩ := checked.status.call wellFormed
    (.singleton (local_read resultLocal)) rfl
  have statusRun : Evaluates program.core before
      (.binary .notEqual (.call symbols.status [.local 17]) (.constant symbols.success)) (.boolean false) guarded := by
    rw [checked.statusId]
    exact evaluatesEagerBinary (by decide) (by decide) statusCall (evaluatesConstant checked.lexerSuccess) rfl
  have capacityRun := capacity_condition_evaluates program.core guarded 18 7 count capacity
    (statusEffect.empty_preserves_local wellFormed countLocal)
    (statusEffect.empty_preserves_local wellFormed capacityLocal) bounded
  have rejected : ¬ count ≤ capacity / 3 := by omega
  simp only [rejected, decide_false, Bool.not_false] at capacityRun
  obtain ⟨after, returned, returnEffect⟩ := checked.storage_return statusEffect.wellFormed 0 (.value (.signed .i32 0))
    (statusEffect.empty_preserves_local wellFormed countLocal) ⟨1, rfl⟩
  refine ⟨after, ?_, statusEffect.trans returnEffect⟩
  intro lexicalFailure rest
  exact executesSequence (executesIfFalse statusRun (executesSkip _ _))
    (executesSequenceReturned (executesIfTrue capacityRun (executesSequenceReturned (executesReturnValue returned))))

/-- Kind capacity uses one word per canonical token. Returning here does not
run the kind-copy loop or touch kind/parser/tree storage. -/
theorem CheckedEarly.kinds_full (checked : CheckedEarly program symbols)
    (before : State) (wellFormed : StateWellFormed before) (count capacity : Nat)
    (rawLocal : before.local? 18 = some (.signed .i32 rawCount))
    (countLocal : before.local? 20 = some (.signed .i32 count))
    (capacityLocal : before.local? 9 = some (.signed .i32 capacity)) (full : capacity < count) :
    ∃ after, (∀ functionId resultType rest, Executes program.core before
        (recognitionBody functionId resultType checked.kindsBody rest)
        (.returned (some (syntaxResult checked.constructor.typeId 3 1 rawCount count 0 0 0))) after) ∧
      CellEffect CellSet.empty before after := by
  have guardRun := kinds_capacity_evaluates program.core before count capacity countLocal capacityLocal
  have rejected : ¬ count ≤ capacity := by omega
  simp only [rejected, decide_false, Bool.not_false] at guardRun
  obtain ⟨after, returned, effect⟩ := checked.storage_return wellFormed 1 (.local 20) rawLocal (local_read countLocal)
  refine ⟨after, ?_, effect⟩
  intro functionId resultType rest
  exact executesSequenceReturned (executesIfTrue guardRun (executesSequenceReturned (executesReturnValue returned)))

end Lanius.Extraction.Frontend
