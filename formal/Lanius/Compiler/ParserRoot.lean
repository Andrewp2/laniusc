import Lanius.Compiler.ParserTree

namespace Lanius.Compiler.Parser

/-- Acceptance tied to the selected stored root, rather than an unrelated
    existential parse. This retains the backpointer contract needed by the
    executable derivation reader and the exact logical tree it must recover. -/
structure StoredRootParse (grammar : IndexedGrammar) (tokens : List Nat)
    (workspace : LogicalWorkspace) (rootState : Nat)
    extends MaterializedParse grammar tokens where
  backpointersSound : WorkspaceBackpointersSound grammar tokens workspace
  rootComputed : materializeRoot? grammar tokens workspace rootState = some tree

def WorkspaceBackpointersSound.storedRoot
    (sound : WorkspaceBackpointersSound grammar tokens workspace)
    (grammarWellFormed : grammar.WellFormed)
    (found : workspace.state? rootState = some state)
    (productionBound : state.production < grammar.productionCount)
    (origin : state.origin = 0)
    (lhs : (grammar.productionAt ⟨state.production, productionBound⟩).lhs =
      grammar.grammar.start_nonterminal)
    (complete : state.dot = (grammar.productionAt ⟨state.production, productionBound⟩).rhs.length)
    (finish : state.position = finalPosition tokens.length) :
    StoredRootParse grammar tokens workspace rootState where
  toMaterializedParse := sound.materializeStart grammarWellFormed found productionBound origin lhs complete finish
  backpointersSound := sound
  rootComputed := sound.materializeRoot?_eq_some grammarWellFormed found productionBound origin lhs complete finish

end Lanius.Compiler.Parser
