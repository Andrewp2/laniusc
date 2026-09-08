import Lanius.Extraction.BufferCopy.Source

namespace Lanius.Extraction.BufferCopy

open Lanius.Core Lanius.Extraction.Source

/-- The kind-copy scope and the six arguments consumed by the recognizer. -/
structure Recognition where
  locals : Locals
  grammarId : VarId
  grammarLengthId : VarId
  workspaceId : VarId
  workspaceLengthId : VarId
  functionId : FunctionId
  resultId : VarId
  resultType : Ty
  rest : Stmt

def Recognition.body (region : Recognition) : Stmt :=
  .letLocal region.locals.cursor (.scalar (.signed .i32)) (.value (.signed .i32 0))
    (.sequence region.locals.loop
      (.letLocal region.resultId region.resultType
        (.call region.functionId [.local region.grammarId, .local region.grammarLengthId,
          .local region.locals.destination, .local region.locals.count,
          .local region.workspaceId, .local region.workspaceLengthId]) region.rest))

/-- Successful checking carries an equality to the actual source region.
Function identity is checked against the linked source program by the caller. -/
def checkRecognition? : (statement : Stmt) →
    Option (CheckedStatement Recognition.body statement)
  | .letLocal cursor (.scalar (.signed .i32)) (.value (.signed .i32 0))
      (.sequence loop (.letLocal resultId resultType
        (.call functionId [.local grammarId, .local grammarLengthId,
          .local destinationId, .local countId, .local workspaceId,
          .local workspaceLengthId]) rest)) => do
      let checked ← checkLoop? loop
      if same : checked.locals.cursor = cursor ∧ checked.locals.destination = destinationId ∧
          checked.locals.count = countId then
        if checked.locals.readScale = .triple ∧ checked.locals.countScale = .plain then
          some ⟨⟨checked.locals, grammarId, grammarLengthId, workspaceId,
            workspaceLengthId, functionId, resultId, resultType, rest⟩, by
            rcases checked with ⟨locals, exactLoop⟩
            dsimp at same ⊢
            rcases same with ⟨rfl, rfl, rfl⟩
            rw [exactLoop]
            rfl⟩
        else none
      else none
  | _ => none

def findRecognition? := findStatement? Recognition.body checkRecognition?

end Lanius.Extraction.BufferCopy
