import Lanius.Compiler.Parser.Prediction

namespace Lanius.Compiler.Parser

/-- A stored child that finishes the expected nonterminal without consuming
input. This is the grammar condition tested by nullable replay. -/
def NullableChild (grammar : IndexedGrammar) (position expected : Nat)
    (child : EarleyState) : Prop :=
  ∃ bound : child.production < grammar.productionCount,
    child.origin = position ∧
    child.dot = (grammar.productionAt ⟨child.production, bound⟩).rhs.length ∧
    (grammar.productionAt ⟨child.production, bound⟩).lhs = expected

def NullablesFor (grammar : IndexedGrammar) (workspace : LogicalWorkspace)
    (position expected : Nat) (advanced : StateKey) (ids : List Nat) : Prop :=
  ∀ id ∈ ids, ∀ child, workspace.state? id = some child →
    NullableChild grammar position expected child → workspace.containsKey position advanced

def NullablesComplete (grammar : IndexedGrammar) (workspace : LogicalWorkspace)
    (position expected : Nat) (advanced : StateKey) : Prop :=
  NullablesFor grammar workspace position expected advanced (workspace.chart position)

theorem NullablesFor.nil : NullablesFor grammar workspace position expected advanced [] := by
  intro id listed
  cases listed

/-- Once the parent's advanced key is present, every matching nullable child
is covered, including children appended later in the same traversal. -/
theorem NullablesFor.of_advanced (present : workspace.containsKey position advanced) :
    NullablesFor grammar workspace position expected advanced ids := by
  intro _ _ _ _ _
  exact present

theorem NullablesFor.preserved (covered : NullablesFor grammar before position expected advanced ids)
    (growth : WorkspaceAppendClosure capacity before after)
    (known : ∀ id ∈ ids, ∃ child, before.state? id = some child) :
    NullablesFor grammar after position expected advanced ids := by
  intro id listed child found matchesChild
  obtain ⟨old, oldFound⟩ := known id listed
  have same := Option.some.inj ((growth.preserves_existing_state oldFound).symm.trans found)
  subst child
  exact growth.preserves_containsKey (covered id listed old oldFound matchesChild)

theorem NullablesFor.step
    (beforeCursor : ChartCursor (before.chart position) current remaining)
    (afterCursor : ChartCursor (after.chart position) current nextRemaining)
    (growth : WorkspaceAppendClosure capacity before after) (sound : ChartSound before)
    (prior : NullablesFor grammar before position expected advanced beforeCursor.visited)
    (selected : ∀ child, before.state? current = some child →
      NullableChild grammar position expected child → after.containsKey position advanced) :
    NullablesFor grammar after position expected advanced (afterCursor.visited ++ [current]) := by
  have visitedEq := beforeCursor.visited_eq_of_growth afterCursor growth
  have known : ∀ id ∈ beforeCursor.visited, ∃ child, before.state? id = some child := by
    intro id listed
    obtain ⟨child, found, _⟩ := sound position id (by
      rw [beforeCursor.split]
      exact List.mem_append_left _ listed)
    exact ⟨child, found⟩
  have retained := prior.preserved growth known
  intro id listed child found matchesChild
  rcases List.mem_append.mp listed with old | currentId
  · rw [visitedEq] at old
    exact retained id old child found matchesChild
  · have same : id = current := List.mem_singleton.mp currentId
    subst id
    obtain ⟨old, oldFound, _⟩ := sound position current beforeCursor.current_mem
    have same := Option.some.inj ((growth.preserves_existing_state oldFound).symm.trans found)
    subst child
    exact selected old oldFound matchesChild

theorem NullablesComplete.advance
    (covered : NullablesComplete grammar workspace position expected advanced)
    (production : Fin grammar.productionCount)
    (finished : workspace.containsKey position
      ⟨production, (grammar.productionAt production).rhs.length, position⟩)
    (lhs : (grammar.productionAt production).lhs = expected) :
    workspace.containsKey position advanced := by
  obtain ⟨id, child, listed, found, key⟩ := finished
  apply covered id listed child found
  have productionEq : child.production = production.val := congrArg StateKey.production key
  have dotEq : child.dot = (grammar.productionAt production).rhs.length := congrArg StateKey.dot key
  have originEq : child.origin = position := congrArg StateKey.origin key
  refine ⟨by simpa [productionEq] using production.isLt, originEq, ?_, ?_⟩
  · simpa [productionEq] using dotEq
  · simpa [productionEq] using lhs

end Lanius.Compiler.Parser
