import Lanius.Extraction.BufferCopy.Source

namespace Lanius.Extraction.BufferCopy

open Lanius.Core Lanius.Extraction.Source

structure Canonicalization where
  locals : Locals
  sourceId : VarId
  functionId : FunctionId
  resultId : VarId
  rest : Stmt

def Canonicalization.body (region : Canonicalization) : Stmt :=
  .letLocal region.locals.cursor (.scalar (.signed .i32)) (.value (.signed .i32 0))
    (.sequence region.locals.loop
      (.letLocal region.resultId (.scalar (.signed .i32))
        (.call region.functionId [.local region.sourceId, .local region.locals.destination,
          .local region.locals.count]) region.rest))

/-- Authenticate the cursor scope and the data flow into canonicalization,
not merely the presence of an isolated copy loop somewhere in a function. -/
def checkCanonicalization? : (statement : Stmt) →
    Option (CheckedStatement Canonicalization.body statement)
  | .letLocal cursor (.scalar (.signed .i32)) (.value (.signed .i32 0))
      (.sequence loop (.letLocal resultId (.scalar (.signed .i32))
        (.call functionId [.local sourceId, .local destinationId, .local countId]) rest)) => do
      let checked ← checkLoop? loop
      if same : checked.locals.cursor = cursor ∧ checked.locals.destination = destinationId ∧
          checked.locals.count = countId then
        some ⟨⟨checked.locals, sourceId, functionId, resultId, rest⟩, by
          rcases checked with ⟨locals, exactLoop⟩
          dsimp at same ⊢
          rcases same with ⟨rfl, rfl, rfl⟩
          rw [exactLoop]
          rfl⟩
      else none
  | _ => none

def findCanonicalization? := findStatement? Canonicalization.body checkCanonicalization?

end Lanius.Extraction.BufferCopy
