import Lanius.Compiler.Parser.Completion.Step

namespace Lanius.Compiler.Parser

/-- Processed children cover parents from earlier charts, and processed
parents in this chart. Future same-chart parents are covered when their
nullable replay runs. -/
def CompletionsFor (grammar : IndexedGrammar) (workspace : LogicalWorkspace)
    (position : Nat) (ids : List Nat) : Prop :=
  ∀ childId ∈ ids, ∀ child, workspace.state? childId = some child →
    ∀ childBound : child.production < grammar.productionCount,
      child.dot = (grammar.productionAt ⟨child.production, childBound⟩).rhs.length →
      ∀ parentId ∈ workspace.chart child.origin,
        child.origin < position ∨ parentId ∈ ids →
        ∀ parent, workspace.state? parentId = some parent →
          ParentAdvanced grammar workspace position
            (grammar.productionAt ⟨child.production, childBound⟩).lhs parent

def ChartCompleted (grammar : IndexedGrammar) (workspace : LogicalWorkspace) (position : Nat) : Prop :=
  CompletionsFor grammar workspace position (workspace.chart position)

theorem CompletionsFor.nil : CompletionsFor grammar workspace position [] := by
  intro id listed
  cases listed

private theorem chart_position {id : Nat} (sound : ChartSound workspace)
    (listed : id ∈ workspace.chart position) (found : workspace.state? id = some state) :
    state.position = position := by
  obtain ⟨actual, stored, atPosition⟩ := sound position id listed
  have same := Option.some.inj (stored.symm.trans found)
  subst state
  exact atPosition

theorem CompletionsFor.preserved (covered : CompletionsFor grammar before position ids)
    (growth : WorkspaceAppendClosure capacity before after)
    (beforeSound : ChartSound before) (afterSound : ChartSound after)
    (known : ∀ id ∈ ids, id ∈ before.chart position)
    (stable : ChartsUnchangedBefore position before after) :
    CompletionsFor grammar after position ids := by
  intro childId childListed child childFound childBound finished parentId parentListed eligible parent parentFound
  obtain ⟨oldChild, oldChildFound, _⟩ := beforeSound position childId (known childId childListed)
  have sameChild := Option.some.inj ((growth.preserves_existing_state oldChildFound).symm.trans childFound)
  subst child
  have parentBefore : parentId ∈ before.chart oldChild.origin := by
    rcases eligible with earlier | processed
    · rw [← stable oldChild.origin earlier]
      exact parentListed
    · have inChart := known parentId processed
      have samePosition := chart_position afterSound parentListed parentFound
      obtain ⟨oldParent, oldFound, atPosition⟩ := beforeSound position parentId inChart
      have sameParent := Option.some.inj ((growth.preserves_existing_state oldFound).symm.trans parentFound)
      subst parent
      have originEq : oldChild.origin = position := samePosition.symm.trans atPosition
      rw [originEq]
      exact inChart
  obtain ⟨oldParent, oldParentFound, _⟩ := beforeSound oldChild.origin parentId parentBefore
  have sameParent := Option.some.inj ((growth.preserves_existing_state oldParentFound).symm.trans parentFound)
  subst parent
  exact (covered childId childListed oldChild oldChildFound childBound finished
    parentId parentBefore eligible oldParent oldParentFound).preserved growth

/-- Process the current item in both roles. Old/old pairs are preserved;
current-child pairs use parent replay, and old-child/current-parent pairs use
nullable replay. New items stay in the pending suffix. -/
theorem CompletionsFor.step
    (beforeCursor : ChartCursor (before.chart position) current remaining)
    (afterCursor : ChartCursor (after.chart position) current nextRemaining)
    (growth : WorkspaceAppendClosure capacity before after)
    (beforeSound : ChartSound before) (afterSound : ChartSound after)
    (stable : ChartsUnchangedBefore position before after)
    (prior : CompletionsFor grammar before position beforeCursor.visited)
    (selected : ∀ state, before.state? current = some state →
      CompletionStep grammar after position state.production state.dot state.origin) :
    CompletionsFor grammar after position (afterCursor.visited ++ [current]) := by
  have visitedEq := beforeCursor.visited_eq_of_growth afterCursor growth
  have known : ∀ id ∈ beforeCursor.visited, id ∈ before.chart position := by
    intro id listed
    rw [beforeCursor.split]
    exact List.mem_append_left _ listed
  have retained := prior.preserved growth beforeSound afterSound known stable
  have selectedAfter : ∀ state, after.state? current = some state →
      CompletionStep grammar after position state.production state.dot state.origin := by
    intro state found
    obtain ⟨old, oldFound, _⟩ := beforeSound position current beforeCursor.current_mem
    have same := Option.some.inj ((growth.preserves_existing_state oldFound).symm.trans found)
    subst state
    exact selected old oldFound
  intro childId childListed child childFound childBound finished parentId parentListed eligible parent parentFound
  rcases List.mem_append.mp childListed with oldChild | currentChild
  · rw [visitedEq] at oldChild
    rcases eligible with earlier | parentProcessed
    · exact retained childId oldChild child childFound childBound finished parentId parentListed (.inl earlier) parent parentFound
    · rcases List.mem_append.mp parentProcessed with oldParent | currentParent
      · rw [visitedEq] at oldParent
        exact retained childId oldChild child childFound childBound finished parentId parentListed (.inr oldParent) parent parentFound
      · have sameId : parentId = current := List.mem_singleton.mp currentParent
        subst parentId
        have atOrigin := chart_position afterSound parentListed parentFound
        have atPosition := chart_position afterSound afterCursor.current_mem parentFound
        have originEq : child.origin = position := atOrigin.symm.trans atPosition
        intro parentBound expected
        have replayed := (selectedAfter parent parentFound).nullables parentBound _ expected
        apply replayed childId _ child childFound ⟨childBound, originEq, finished, rfl⟩
        rw [afterCursor.split]
        apply List.mem_append_left
        rw [visitedEq]
        exact oldChild
  · have sameId : childId = current := List.mem_singleton.mp currentChild
    subst childId
    exact (selectedAfter child childFound).parents childBound finished parentId parentListed parent parentFound

/-- The chart-wide result is the completion clause, with the child's span
bound explicit. Actual language-sound states supply that bound. -/
theorem ChartCompleted.complete (covered : ChartCompleted grammar workspace finish)
    (parent child : Fin grammar.productionCount) (dot origin middle : Nat)
    (span : middle ≤ finish)
    (waiting : workspace.containsKey middle ⟨parent, dot, origin⟩)
    (expected : (grammar.productionAt parent).rhs[dot]? =
      some (grammar.grammar.n_kinds + (grammar.productionAt child).lhs))
    (finished : workspace.containsKey finish ⟨child, (grammar.productionAt child).rhs.length, middle⟩) :
    workspace.containsKey finish ⟨parent, dot + 1, origin⟩ := by
  obtain ⟨childId, childState, childListed, childFound, childKey⟩ := finished
  obtain ⟨parentId, parentState, parentListed, parentFound, parentKey⟩ := waiting
  have childProduction : childState.production = child.val := congrArg StateKey.production childKey
  have childDot : childState.dot = (grammar.productionAt child).rhs.length := congrArg StateKey.dot childKey
  have childOrigin : childState.origin = middle := congrArg StateKey.origin childKey
  have parentProduction : parentState.production = parent.val := congrArg StateKey.production parentKey
  have parentDot : parentState.dot = dot := congrArg StateKey.dot parentKey
  have parentOrigin : parentState.origin = origin := congrArg StateKey.origin parentKey
  have eligible : childState.origin < finish ∨ parentId ∈ workspace.chart finish := by
    by_cases earlier : middle < finish
    · exact .inl (by omega)
    · have same : middle = finish := by omega
      exact .inr (same ▸ parentListed)
  have advanced := covered childId childListed childState childFound
    (by simpa [childProduction] using child.isLt)
    (by simpa [childProduction] using childDot)
    parentId (by simpa [childOrigin] using parentListed) eligible parentState parentFound
  simp only [ParentAdvanced, childProduction, parentProduction, parentDot, parentOrigin] at advanced
  exact advanced parent.isLt expected

theorem ChartCompleted.preserved (covered : ChartCompleted grammar before position)
    (growth : WorkspaceAppendClosure capacity before after)
    (beforeSound : ChartSound before) (afterSound : ChartSound after)
    (unchanged : after.chart position = before.chart position)
    (stable : ChartsUnchangedBefore position before after) :
    ChartCompleted grammar after position := by
  unfold ChartCompleted
  rw [unchanged]
  exact CompletionsFor.preserved covered growth beforeSound afterSound (fun _ listed => listed) stable

def CompletionsBefore (grammar : IndexedGrammar) (workspace : LogicalWorkspace) (position : Nat) : Prop :=
  ∀ earlier, earlier < position → ChartCompleted grammar workspace earlier

theorem CompletionsBefore.zero : CompletionsBefore grammar workspace 0 := by
  intro earlier bound
  omega

theorem CompletionsBefore.advance (prior : CompletionsBefore grammar before position)
    (growth : WorkspaceAppendClosure capacity before after)
    (beforeSound : ChartSound before) (afterSound : ChartSound after)
    (stable : ChartsUnchangedBefore position before after)
    (current : ChartCompleted grammar after position) :
    CompletionsBefore grammar after (position + 1) := by
  intro earlier bound
  by_cases less : earlier < position
  · exact (prior earlier less).preserved growth beforeSound afterSound (stable earlier less)
      (stable.weaken (Nat.le_of_lt less))
  · have same : earlier = position := by omega
    subst earlier
    exact current

end Lanius.Compiler.Parser
