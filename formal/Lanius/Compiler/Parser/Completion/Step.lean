import Lanius.Compiler.Parser.Completion.Parents
import Lanius.Compiler.Parser.Completion.Nullable

namespace Lanius.Compiler.Parser

/-- The two completion responsibilities of one processed item: replay its
parents if it is finished, or replay nullable children if it is waiting. -/
structure CompletionStep (grammar : IndexedGrammar) (workspace : LogicalWorkspace)
    (position production dot origin : Nat) : Prop where
  parents : ∀ bound : production < grammar.productionCount,
    dot = (grammar.productionAt ⟨production, bound⟩).rhs.length →
    ParentsComplete grammar workspace origin position (grammar.productionAt ⟨production, bound⟩).lhs
  nullables : ∀ (bound : production < grammar.productionCount) expected,
    (grammar.productionAt ⟨production, bound⟩).rhs[dot]? = some (grammar.grammar.n_kinds + expected) →
    NullablesComplete grammar workspace position expected ⟨production, dot + 1, origin⟩

theorem CompletionStep.of_terminal (bound : production < grammar.productionCount)
    (selected : (grammar.productionAt ⟨production, bound⟩).rhs[dot]? = some kind)
    (terminal : kind < grammar.grammar.n_kinds) :
    CompletionStep grammar workspace position production dot origin where
  parents otherBound finished := by
    rw [finished] at selected
    simp at selected
  nullables otherBound expected waiting := by
    have same := Option.some.inj (selected.symm.trans waiting)
    omega

theorem CompletionStep.of_nonterminal (bound : production < grammar.productionCount)
    (selected : (grammar.productionAt ⟨production, bound⟩).rhs[dot]? = some (grammar.grammar.n_kinds + expected))
    (replayed : NullablesComplete grammar workspace position expected ⟨production, dot + 1, origin⟩) :
    CompletionStep grammar workspace position production dot origin where
  parents otherBound finished := by
    rw [finished] at selected
    simp at selected
  nullables otherBound other waiting := by
    have same := Nat.add_left_cancel (Option.some.inj (selected.symm.trans waiting))
    subst other
    exact replayed

theorem CompletionStep.of_finished (bound : production < grammar.productionCount)
    (finished : dot = (grammar.productionAt ⟨production, bound⟩).rhs.length)
    (replayed : ParentsComplete grammar workspace origin position (grammar.productionAt ⟨production, bound⟩).lhs) :
    CompletionStep grammar workspace position production dot origin where
  parents _ _ := replayed
  nullables otherBound expected waiting := by
    rw [finished] at waiting
    simp at waiting

end Lanius.Compiler.Parser
