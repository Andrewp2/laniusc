import Lanius.Compiler.Parser.Seeding
import Lanius.Compiler.ParserEncoding
import Lanius.Compiler.Parser.Growth

namespace Lanius.Compiler.Parser

/-- Append-only growth preserves chart order, not merely membership. -/
theorem Append.chart_prefix (appended : Append capacity position seed before outcome after)
    (queried : Nat) : ∃ tail, after.chart queried = before.chart queried ++ tail := by
  cases appended with
  | existing => exact ⟨[], by simp⟩
  | full => exact ⟨[], by simp⟩
  | inserted =>
      by_cases same : queried = position
      · subst queried
        exact ⟨[before.states.length], appendChart_same _ _ _⟩
      · exact ⟨[], by simpa [insertState] using appendChart_other before.chart same⟩

theorem WorkspaceAppendClosure.chart_prefix
    (growth : WorkspaceAppendClosure capacity before after) (position : Nat) :
    ∃ tail, after.chart position = before.chart position ++ tail := by
  induction growth with
  | refl => exact ⟨[], by simp⟩
  | append prior nextPosition seed ih =>
      obtain ⟨first, firstEq⟩ := ih
      obtain ⟨last, lastEq⟩ := (appendLogical_refines _ rfl).chart_prefix position
      exact ⟨first ++ last, by rw [lastEq, firstEq, List.append_assoc]⟩

/-- `unseen` identifies the first occurrence of the cursor even without a
global no-duplicates premise. -/
theorem ChartCursor.visited_eq_takeWhile (cursor : ChartCursor chart current remaining) :
    chart.takeWhile (· != current) = cursor.visited := by
  calc
    chart.takeWhile (· != current) =
        (cursor.visited ++ current :: remaining).takeWhile (· != current) :=
      congrArg (List.takeWhile (· != current)) cursor.split
    _ = cursor.visited := by
      rw [List.takeWhile_append_of_pos]
      · simp
      · intro id listed
        simp only [bne_iff_ne]
        intro same
        exact cursor.unseen (same ▸ listed)

theorem ChartCursor.visited_eq (left : ChartCursor chart current leftRemaining)
    (right : ChartCursor chart current rightRemaining) : left.visited = right.visited :=
  left.visited_eq_takeWhile.symm.trans right.visited_eq_takeWhile

theorem ChartCursor.visited_nil_of_head (cursor : ChartCursor chart current remaining)
    (head : chart.head? = some current) : cursor.visited = [] := by
  have stopped : chart.takeWhile (· != current) = [] := by
    cases chart with
    | nil => rfl
    | cons first rest =>
        have same : first = current := Option.some.inj head
        subst first
        simp
  exact cursor.visited_eq_takeWhile.symm.trans stopped

/-- Growing the tail cannot retroactively add an item to the visited prefix. -/
theorem ChartCursor.visited_eq_of_growth
    (beforeCursor : ChartCursor (before.chart position) current remaining)
    (afterCursor : ChartCursor (after.chart position) current nextRemaining)
    (growth : WorkspaceAppendClosure capacity before after) :
    afterCursor.visited = beforeCursor.visited := by
  obtain ⟨tail, extended⟩ := growth.chart_prefix position
  let transported : ChartCursor (after.chart position) current (remaining ++ tail) := {
    visited := beforeCursor.visited
    split := extended.trans ((congrArg (fun ids => ids ++ tail) beforeCursor.split).trans
      (by simp [List.append_assoc]))
    unseen := beforeCursor.unseen }
  exact afterCursor.visited_eq transported

/-- Prediction obligations discharged for a list of processed state ids. -/
def PredictionsFor (grammar : IndexedGrammar) (workspace : LogicalWorkspace)
    (position : Nat) (ids : List Nat) : Prop :=
  ∀ id ∈ ids, ∀ state, workspace.state? id = some state →
    PredictionsComplete grammar workspace position state.production state.dot

def ChartPredicted (grammar : IndexedGrammar) (workspace : LogicalWorkspace)
    (position : Nat) : Prop := PredictionsFor grammar workspace position (workspace.chart position)

theorem PredictionsFor.nil : PredictionsFor grammar workspace position [] := by
  intro id listed
  cases listed

theorem PredictionsFor.preserved (predicted : PredictionsFor grammar before position ids)
    (growth : WorkspaceAppendClosure capacity before after)
    (known : ∀ id ∈ ids, ∃ state, before.state? id = some state) :
    PredictionsFor grammar after position ids := by
  intro id listed state found
  obtain ⟨old, oldFound⟩ := known id listed
  have same := Option.some.inj ((growth.preserves_existing_state oldFound).symm.trans found)
  subst state
  exact (predicted id listed old oldFound).preserved growth

/-- One real processing step extends the certified prefix by its current
item. Any newly appended items remain after that prefix, awaiting processing. -/
theorem PredictionsFor.step
    (beforeCursor : ChartCursor (before.chart position) current remaining)
    (afterCursor : ChartCursor (after.chart position) current nextRemaining)
    (growth : WorkspaceAppendClosure capacity before after)
    (sound : ChartSound before)
    (prior : PredictionsFor grammar before position beforeCursor.visited)
    (currentPredicted : ∀ state, before.state? current = some state →
      PredictionsComplete grammar after position state.production state.dot) :
    PredictionsFor grammar after position (afterCursor.visited ++ [current]) := by
  have visitedEq : afterCursor.visited = beforeCursor.visited :=
    beforeCursor.visited_eq_of_growth afterCursor growth
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
    exact currentPredicted old oldFound

theorem ChartPredicted.predict (predicted : ChartPredicted grammar workspace position)
    (parent child : Fin grammar.productionCount) (dot origin : Nat)
    (waiting : workspace.containsKey position ⟨parent, dot, origin⟩)
    (expected : (grammar.productionAt parent).rhs[dot]? =
      some (grammar.grammar.n_kinds + (grammar.productionAt child).lhs)) :
    workspace.containsKey position ⟨child, 0, position⟩ := by
  obtain ⟨id, state, listed, found, key⟩ := waiting
  have complete := predicted id listed state found
  have productionEq : state.production = parent.val := congrArg StateKey.production key
  have dotEq : state.dot = dot := congrArg StateKey.dot key
  rw [PredictionsComplete, productionEq, dotEq] at complete
  exact complete parent.isLt child expected

/-- A completed chart remains prediction-complete when later operations keep
its state-id list unchanged and only append to the workspace's state table. -/
theorem ChartPredicted.preserved (predicted : ChartPredicted grammar before position)
    (growth : WorkspaceAppendClosure capacity before after)
    (sound : ChartSound before)
    (unchanged : after.chart position = before.chart position) :
    ChartPredicted grammar after position := by
  unfold ChartPredicted
  rw [unchanged]
  apply PredictionsFor.preserved predicted growth
  intro id listed
  obtain ⟨state, found, _⟩ := sound position id listed
  exact ⟨state, found⟩

def PredictionsBefore (grammar : IndexedGrammar) (workspace : LogicalWorkspace)
    (position : Nat) : Prop := ∀ earlier, earlier < position → ChartPredicted grammar workspace earlier

theorem PredictionsBefore.zero : PredictionsBefore grammar workspace 0 := by
  intro earlier bound
  omega

theorem PredictionsBefore.advance (prior : PredictionsBefore grammar before position)
    (growth : WorkspaceAppendClosure capacity before after) (sound : ChartSound before)
    (stable : ChartsUnchangedBefore position before after)
    (current : ChartPredicted grammar after position) :
    PredictionsBefore grammar after (position + 1) := by
  intro earlier bound
  by_cases less : earlier < position
  · exact (prior earlier less).preserved growth sound (stable earlier less)
  · have same : earlier = position := by omega
    simpa only [same] using current

end Lanius.Compiler.Parser
