import Lanius.Compiler.Parser.Prediction

namespace Lanius.Compiler.Parser

/-- Every matching terminal advances this processed item. A mismatch,
nonterminal expectation, or finished production has no scan obligation. -/
def ScansComplete (grammar : IndexedGrammar) (tokens : List Nat)
    (workspace : LogicalWorkspace) (position production dot origin : Nat) : Prop :=
  ∀ (bound : production < grammar.productionCount) (kind finish : Nat),
    (grammar.productionAt ⟨production, bound⟩).rhs[dot]? = some kind →
    kind < grammar.grammar.n_kinds →
    scanTerminal grammar tokens position kind = some finish →
    workspace.containsKey finish ⟨production, dot + 1, origin⟩

theorem ScansComplete.preserved
    (scanned : ScansComplete grammar tokens before position production dot origin)
    (growth : WorkspaceAppendClosure capacity before after) :
    ScansComplete grammar tokens after position production dot origin := by
  intro bound kind finish expected terminal matched
  exact growth.preserves_containsKey (scanned bound kind finish expected terminal matched)

theorem ScansComplete.of_terminal (bound : production < grammar.productionCount)
    (expected : (grammar.productionAt ⟨production, bound⟩).rhs[dot]? = some symbol)
    (advanced : ∀ finish, scanTerminal grammar tokens position symbol = some finish →
      workspace.containsKey finish ⟨production, dot + 1, origin⟩) :
    ScansComplete grammar tokens workspace position production dot origin := by
  intro otherBound kind finish selected _ matched
  have same : symbol = kind := Option.some.inj (expected.symm.trans selected)
  subst kind
  exact advanced finish matched

theorem ScansComplete.of_miss (bound : production < grammar.productionCount)
    (expected : (grammar.productionAt ⟨production, bound⟩).rhs[dot]? = some symbol)
    (missed : scanTerminal grammar tokens position symbol = none) :
    ScansComplete grammar tokens workspace position production dot origin := by
  apply ScansComplete.of_terminal bound expected
  intro finish matched
  rw [missed] at matched
  cases matched

theorem ScansComplete.of_nonterminal (bound : production < grammar.productionCount)
    (expected : (grammar.productionAt ⟨production, bound⟩).rhs[dot]? = some symbol)
    (nonterminal : grammar.grammar.n_kinds ≤ symbol) :
    ScansComplete grammar tokens workspace position production dot origin := by
  intro otherBound kind finish selected terminal _
  have same : symbol = kind := Option.some.inj (expected.symm.trans selected)
  omega

theorem ScansComplete.of_finished (bound : production < grammar.productionCount)
    (finished : (grammar.productionAt ⟨production, bound⟩).rhs.length ≤ dot) :
    ScansComplete grammar tokens workspace position production dot origin := by
  intro otherBound kind finish selected _ _
  rw [List.getElem?_eq_none (by omega)] at selected
  cases selected

/-- Scan obligations discharged for an exact processed prefix. -/
def ScansFor (grammar : IndexedGrammar) (tokens : List Nat)
    (workspace : LogicalWorkspace) (position : Nat) (ids : List Nat) : Prop :=
  ∀ id ∈ ids, ∀ state, workspace.state? id = some state →
    ScansComplete grammar tokens workspace position state.production state.dot state.origin

def ChartScanned (grammar : IndexedGrammar) (tokens : List Nat)
    (workspace : LogicalWorkspace) (position : Nat) : Prop :=
  ScansFor grammar tokens workspace position (workspace.chart position)

theorem ScansFor.nil : ScansFor grammar tokens workspace position [] := by
  intro id listed
  cases listed

theorem ScansFor.preserved (scanned : ScansFor grammar tokens before position ids)
    (growth : WorkspaceAppendClosure capacity before after)
    (known : ∀ id ∈ ids, ∃ state, before.state? id = some state) :
    ScansFor grammar tokens after position ids := by
  intro id listed state found
  obtain ⟨old, oldFound⟩ := known id listed
  have same := Option.some.inj ((growth.preserves_existing_state oldFound).symm.trans found)
  subst state
  exact (scanned id listed old oldFound).preserved growth

theorem ScansFor.step
    (beforeCursor : ChartCursor (before.chart position) current remaining)
    (afterCursor : ChartCursor (after.chart position) current nextRemaining)
    (growth : WorkspaceAppendClosure capacity before after) (sound : ChartSound before)
    (prior : ScansFor grammar tokens before position beforeCursor.visited)
    (currentScanned : ∀ state, before.state? current = some state →
      ScansComplete grammar tokens after position state.production state.dot state.origin) :
    ScansFor grammar tokens after position (afterCursor.visited ++ [current]) := by
  have visitedEq := beforeCursor.visited_eq_of_growth afterCursor growth
  have known : ∀ id ∈ beforeCursor.visited, ∃ state, before.state? id = some state := by
    intro id listed
    obtain ⟨state, found, _⟩ := sound position id (by
      rw [beforeCursor.split]
      exact List.mem_append_left _ listed)
    exact ⟨state, found⟩
  have retained := prior.preserved growth known
  intro id listed state found
  rcases List.mem_append.mp listed with old | selected
  · rw [visitedEq] at old
    exact retained id old state found
  · have same : id = current := List.mem_singleton.mp selected
    subst id
    obtain ⟨old, oldFound, _⟩ := sound position current beforeCursor.current_mem
    have same := Option.some.inj ((growth.preserves_existing_state oldFound).symm.trans found)
    subst state
    exact currentScanned old oldFound

theorem ChartScanned.scan (scanned : ChartScanned grammar tokens workspace position)
    (production : Fin grammar.productionCount) (dot origin kind finish : Nat)
    (waiting : workspace.containsKey position ⟨production, dot, origin⟩)
    (expected : (grammar.productionAt production).rhs[dot]? = some kind)
    (terminal : kind < grammar.grammar.n_kinds)
    (matched : scanTerminal grammar tokens position kind = some finish) :
    workspace.containsKey finish ⟨production, dot + 1, origin⟩ := by
  obtain ⟨id, state, listed, found, key⟩ := waiting
  have complete := scanned id listed state found
  have productionEq : state.production = production.val := congrArg StateKey.production key
  have dotEq : state.dot = dot := congrArg StateKey.dot key
  have originEq : state.origin = origin := congrArg StateKey.origin key
  rw [ScansComplete, productionEq, dotEq, originEq] at complete
  exact complete production.isLt kind finish expected terminal matched

theorem ChartScanned.preserved (scanned : ChartScanned grammar tokens before position)
    (growth : WorkspaceAppendClosure capacity before after) (sound : ChartSound before)
    (unchanged : after.chart position = before.chart position) :
    ChartScanned grammar tokens after position := by
  unfold ChartScanned
  rw [unchanged]
  apply ScansFor.preserved scanned growth
  intro id listed
  obtain ⟨state, found, _⟩ := sound position id listed
  exact ⟨state, found⟩

def ScansBefore (grammar : IndexedGrammar) (tokens : List Nat)
    (workspace : LogicalWorkspace) (position : Nat) : Prop :=
  ∀ earlier, earlier < position → ChartScanned grammar tokens workspace earlier

theorem ScansBefore.zero : ScansBefore grammar tokens workspace 0 := by
  intro earlier bound
  omega

theorem ScansBefore.advance (prior : ScansBefore grammar tokens before position)
    (growth : WorkspaceAppendClosure capacity before after) (sound : ChartSound before)
    (stable : ChartsUnchangedBefore position before after)
    (current : ChartScanned grammar tokens after position) :
    ScansBefore grammar tokens after (position + 1) := by
  intro earlier bound
  by_cases less : earlier < position
  · exact (prior earlier less).preserved growth sound (stable earlier less)
  · have same : earlier = position := by omega
    simpa only [same] using current

end Lanius.Compiler.Parser
