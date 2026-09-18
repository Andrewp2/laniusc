import Lanius.Compiler.Parser.Prediction

namespace Lanius.Compiler.Parser

/-- A completed child advances every matching parent visited by its replay
loop. The origin-chart position is supplied by chart membership; the parent
retains its own production origin in the advanced key. -/
def ParentAdvanced (grammar : IndexedGrammar) (workspace : LogicalWorkspace)
    (finish childLhs : Nat) (parent : EarleyState) : Prop :=
  ∀ bound : parent.production < grammar.productionCount,
    (grammar.productionAt ⟨parent.production, bound⟩).rhs[parent.dot]? =
      some (grammar.grammar.n_kinds + childLhs) →
    workspace.containsKey finish ⟨parent.production, parent.dot + 1, parent.origin⟩

theorem ParentAdvanced.preserved (advanced : ParentAdvanced grammar before finish childLhs parent)
    (growth : WorkspaceAppendClosure capacity before after) :
    ParentAdvanced grammar after finish childLhs parent := by
  intro bound expected
  exact growth.preserves_containsKey (advanced bound expected)

theorem ParentAdvanced.of_inserted
    (appended : Append capacity finish seed before outcome after) (ok : outcome.status = .ok)
    (key : seed.key = ⟨parent.production, parent.dot + 1, parent.origin⟩) :
    ParentAdvanced grammar after finish childLhs parent := by
  intro _ _
  rw [← key]
  exact appended.containsKey_of_ok ok

def ParentsFor (grammar : IndexedGrammar) (workspace : LogicalWorkspace)
    (finish childLhs : Nat) (ids : List Nat) : Prop :=
  ∀ id ∈ ids, ∀ parent, workspace.state? id = some parent →
    ParentAdvanced grammar workspace finish childLhs parent

def ParentsComplete (grammar : IndexedGrammar) (workspace : LogicalWorkspace)
    (origin finish childLhs : Nat) : Prop :=
  ParentsFor grammar workspace finish childLhs (workspace.chart origin)

theorem ParentsFor.nil : ParentsFor grammar workspace finish childLhs [] := by
  intro id listed
  cases listed

theorem ParentsFor.preserved (parents : ParentsFor grammar before finish childLhs ids)
    (growth : WorkspaceAppendClosure capacity before after)
    (known : ∀ id ∈ ids, ∃ parent, before.state? id = some parent) :
    ParentsFor grammar after finish childLhs ids := by
  intro id listed parent found
  obtain ⟨old, oldFound⟩ := known id listed
  have same := Option.some.inj ((growth.preserves_existing_state oldFound).symm.trans found)
  subst parent
  exact (parents id listed old oldFound).preserved growth

/-- The current parent extends the certified prefix. Appended items in the
same origin chart remain pending and cannot be skipped by this step. -/
theorem ParentsFor.step
    (beforeCursor : ChartCursor (before.chart origin) current remaining)
    (afterCursor : ChartCursor (after.chart origin) current nextRemaining)
    (growth : WorkspaceAppendClosure capacity before after) (sound : ChartSound before)
    (prior : ParentsFor grammar before finish childLhs beforeCursor.visited)
    (advanced : ∀ parent, before.state? current = some parent →
      ParentAdvanced grammar after finish childLhs parent) :
    ParentsFor grammar after finish childLhs (afterCursor.visited ++ [current]) := by
  have visitedEq := beforeCursor.visited_eq_of_growth afterCursor growth
  have known : ∀ id ∈ beforeCursor.visited, ∃ parent, before.state? id = some parent := by
    intro id listed
    obtain ⟨parent, found, _⟩ := sound origin id (by
      rw [beforeCursor.split]
      exact List.mem_append_left _ listed)
    exact ⟨parent, found⟩
  have retained := prior.preserved growth known
  intro id listed parent found
  rcases List.mem_append.mp listed with old | selected
  · rw [visitedEq] at old
    exact retained id old parent found
  · have same : id = current := List.mem_singleton.mp selected
    subst id
    obtain ⟨old, oldFound, _⟩ := sound origin current beforeCursor.current_mem
    have same := Option.some.inj ((growth.preserves_existing_state oldFound).symm.trans found)
    subst parent
    exact advanced old oldFound

theorem ParentsComplete.advance (parents : ParentsComplete grammar workspace origin finish childLhs)
    (production : Fin grammar.productionCount) (dot parentOrigin : Nat)
    (waiting : workspace.containsKey origin ⟨production, dot, parentOrigin⟩)
    (expected : (grammar.productionAt production).rhs[dot]? =
      some (grammar.grammar.n_kinds + childLhs)) :
    workspace.containsKey finish ⟨production, dot + 1, parentOrigin⟩ := by
  obtain ⟨id, parent, listed, found, key⟩ := waiting
  have advanced := parents id listed parent found
  have productionEq : parent.production = production.val := congrArg StateKey.production key
  have dotEq : parent.dot = dot := congrArg StateKey.dot key
  have originEq : parent.origin = parentOrigin := congrArg StateKey.origin key
  rw [ParentAdvanced, productionEq, dotEq, originEq] at advanced
  exact advanced production.isLt expected

end Lanius.Compiler.Parser
