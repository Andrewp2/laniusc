import Lanius.Compiler.Parser.Closure

namespace Lanius.Compiler.Parser

/-- An append retains chart membership as well as the dense state record.
No well-formedness premise is needed: the append operation itself preserves
every existing chart suffix and state identity. -/
theorem Append.preserves_containsKey
    (appended : Append capacity position seed before outcome after)
    (present : before.containsKey queried key) : after.containsKey queried key := by
  cases appended with
  | existing => exact present
  | full => exact present
  | inserted absent fits =>
      obtain ⟨id, state, listed, found, same⟩ := present
      refine ⟨id, state, ?_, ?_, same⟩
      · change id ∈ appendChart before.chart position before.states.length queried
        by_cases equal : queried = position
        · subst queried
          rw [appendChart_same]
          exact List.mem_append_left _ listed
        · rw [appendChart_other _ equal]
          exact listed
      · exact (insertState_preserves_old before position seed (getElem?_some_implies_bound found)).trans found

/-- Both successful append paths establish the requested key: inserting a
fresh state and finding a duplicate are equally sufficient for completeness. -/
theorem Append.containsKey_of_ok
    (appended : Append capacity position seed before outcome after)
    (ok : outcome.status = .ok) : after.containsKey position seed.key := by
  cases appended with
  | existing id state listed found same => exact ⟨id, state, listed, found, same⟩
  | full => cases ok
  | inserted absent fits =>
      exact ⟨before.states.length, seed.atPosition position, insertState_lists_new before position seed,
        insertState_finds_new before position seed, StateSeed.atPosition_key seed position⟩

theorem WorkspaceAppendClosure.preserves_containsKey
    (growth : WorkspaceAppendClosure capacity before after)
    (present : before.containsKey position key) : after.containsKey position key := by
  induction growth with
  | refl => exact present
  | append prior nextPosition seed ih =>
      exact (appendLogical_refines _ rfl).preserves_containsKey ih

/-- All listed productions have an initial item at the given position.
This is shared by initial seeding and nonterminal prediction. -/
def Seeded (workspace : LogicalWorkspace) (position : Nat) (productions : List Nat) : Prop :=
  ∀ production ∈ productions, workspace.containsKey position (freshSeed production position).key

theorem Seeded.preserved (seeded : Seeded before position productions)
    (growth : WorkspaceAppendClosure capacity before after) : Seeded after position productions := by
  intro production listed
  exact growth.preserves_containsKey (seeded production listed)

theorem Seeded.append (seeded : Seeded before position productions)
    (appended : Append capacity position (freshSeed production position) before outcome after)
    (ok : outcome.status = .ok) : Seeded after position (productions ++ [production]) := by
  intro selected listed
  rcases List.mem_append.mp listed with earlier | current
  · exact appended.preserves_containsKey (seeded selected earlier)
  · have same : selected = production := List.mem_singleton.mp current
    subst selected
    exact appended.containsKey_of_ok ok

/-- Advancing one packed-table row extends the exact seeded prefix. The
row value is read from the existing table; it is not supplied independently. -/
theorem Seeded.next {productions : List Nat} (seeded : Seeded before position ((productions.drop first).take index))
    (bound : first + index < productions.length)
    (ok : (appendLogical capacity position
      (freshSeed (productions.get ⟨first + index, bound⟩) position) before).1.status = .ok) :
    Seeded (appendLogical capacity position
      (freshSeed (productions.get ⟨first + index, bound⟩) position) before).2 position
      ((productions.drop first).take (index + 1)) := by
  have indexBound : index < (productions.drop first).length := by
    simp only [List.length_drop]
    omega
  rw [List.take_succ_eq_append_getElem indexBound]
  have selected : (productions.drop first)[index] = productions.get ⟨first + index, bound⟩ := by
    simp only [List.getElem_drop, List.get_eq_getElem]
  rw [selected]
  exact seeded.append (appendLogical_refines _ rfl) ok

/-- Completeness of the grammar's production selection, conversely to the
existing membership-soundness lemma. -/
theorem IndexedGrammar.productionIdsFor_contains
    {grammar : IndexedGrammar}
    (production : Fin grammar.productionCount)
    (lhs : (grammar.productionAt production).lhs = nonterminal) :
    production.val ∈ grammar.productionIdsFor nonterminal := by
  apply List.mem_filter.mpr
  refine ⟨List.mem_range.mpr production.isLt, ?_⟩
  have found : grammar.grammar.production? production = some (grammar.productionAt production) := by
    unfold Lanius.Extraction.Grammar.production?
    rw [List.getElem?_eq_getElem production.isLt]
    rfl
  rw [found]
  simpa only [beq_iff_eq] using lhs

/-- The seeding part of chart closure, isolated so source loops can establish
and preserve it before proving prediction/scanning/completion closure. -/
def StartSeeded (grammar : IndexedGrammar) (workspace : LogicalWorkspace) : Prop :=
  ∀ production : Fin grammar.productionCount,
    (grammar.productionAt production).lhs = grammar.grammar.start_nonterminal →
    workspace.containsKey 0 ⟨production, 0, 0⟩

/-- The exact packed interval selected by the grammar's offset/count tables
is the entire logical production row, not just a sound subset of it. -/
theorem IndexedGrammar.lhsProductions_row (grammar : IndexedGrammar)
    (nonterminal : Fin grammar.productionsByLhs.length) :
    (grammar.lhsProductions.drop
      (grammar.lhsOffsets.get ⟨nonterminal, by simpa using nonterminal.isLt⟩)).take
      (grammar.lhsCounts.get ⟨nonterminal, by simpa using nonterminal.isLt⟩) =
      grammar.productionsByLhs.get nonterminal := by
  apply List.ext_getElem
  · have fits := offsetsFrom_row_fits 0 grammar.productionsByLhs nonterminal
    simp only [List.length_take, List.length_drop, grammar.lhsCounts_get]
    simp only [IndexedGrammar.lhsOffsets, IndexedGrammar.lhsProductions] at *
    omega
  · intro index leftBound rightBound
    simpa only [List.getElem_take, List.getElem_drop, List.get_eq_getElem] using
      grammar.lhsProductions_get_at_row nonterminal ⟨index, rightBound⟩

theorem Seeded.start (seeded : Seeded workspace 0 (grammar.productionIdsFor grammar.grammar.start_nonterminal)) :
    StartSeeded grammar workspace := by
  intro production lhs
  exact seeded production (IndexedGrammar.productionIdsFor_contains production lhs)

theorem StartSeeded.preserved (seeded : StartSeeded grammar before)
    (growth : WorkspaceAppendClosure capacity before after) : StartSeeded grammar after := by
  intro production lhs
  exact growth.preserves_containsKey (seeded production lhs)

/-- Prediction is complete for one processed parent item. Finished items and
terminal expectations have no prediction obligation. The production bound is
quantified so this predicate also fits source interfaces carrying raw ids. -/
def PredictionsComplete (grammar : IndexedGrammar) (workspace : LogicalWorkspace)
    (position production dot : Nat) : Prop :=
  ∀ (bound : production < grammar.productionCount) (child : Fin grammar.productionCount),
    (grammar.productionAt ⟨production, bound⟩).rhs[dot]? =
      some (grammar.grammar.n_kinds + (grammar.productionAt child).lhs) →
    workspace.containsKey position ⟨child, 0, position⟩

theorem PredictionsComplete.preserved (predicted : PredictionsComplete grammar before position production dot)
    (growth : WorkspaceAppendClosure capacity before after) :
    PredictionsComplete grammar after position production dot := by
  intro bound child expected
  exact growth.preserves_containsKey (predicted bound child expected)

theorem Seeded.predictionsComplete (seeded : Seeded workspace position (grammar.productionIdsFor nonterminal))
    (bound : production < grammar.productionCount)
    (expected : (grammar.productionAt ⟨production, bound⟩).rhs[dot]? =
      some (grammar.grammar.n_kinds + nonterminal)) :
    PredictionsComplete grammar workspace position production dot := by
  intro _ child selected
  have same := Option.some.inj (expected.symm.trans selected)
  have lhs : (grammar.productionAt child).lhs = nonterminal := by omega
  exact seeded child (IndexedGrammar.productionIdsFor_contains child lhs)

theorem PredictionsComplete.of_terminal {grammar : IndexedGrammar}
    (bound : production < grammar.productionCount)
    (expected : (grammar.productionAt ⟨production, bound⟩).rhs[dot]? = some kind)
    (terminal : kind < grammar.grammar.n_kinds) :
    PredictionsComplete grammar workspace position production dot := by
  intro _ child selected
  have same := Option.some.inj (expected.symm.trans selected)
  omega

theorem PredictionsComplete.of_finished {grammar : IndexedGrammar}
    (bound : production < grammar.productionCount)
    (finished : (grammar.productionAt ⟨production, bound⟩).rhs.length ≤ dot) :
    PredictionsComplete grammar workspace position production dot := by
  intro _ child selected
  rw [List.getElem?_eq_none (by omega)] at selected
  cases selected

end Lanius.Compiler.Parser
