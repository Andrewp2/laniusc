import Lanius.Compiler.Parser.Closure

namespace Lanius.Compiler.Parser

/-- An item forced by the grammar/token closure rules. This characterizes
generation without adding a second recognizer or prescribing a work order. -/
def GeneratedItem (grammar : IndexedGrammar) (tokens : List Nat)
    (position : Nat) (key : StateKey) : Prop :=
  ∀ upper, ChartClosed grammar tokens upper → upper.containsKey position key

def WorkspaceGenerated (grammar : IndexedGrammar) (tokens : List Nat)
    (workspace : LogicalWorkspace) : Prop :=
  ∀ id state, workspace.state? id = some state →
    GeneratedItem grammar tokens state.position state.key

theorem GeneratedItem.seed (production : Fin grammar.productionCount)
    (start : (grammar.productionAt production).lhs = grammar.grammar.start_nonterminal) :
    GeneratedItem grammar tokens 0 ⟨production, 0, 0⟩ :=
  fun _ closed => closed.seed production start

theorem GeneratedItem.predict
    (parent child : Fin grammar.productionCount)
    (waiting : GeneratedItem grammar tokens position ⟨parent, dot, origin⟩)
    (expected : (grammar.productionAt parent).rhs[dot]? =
      some (grammar.grammar.n_kinds + (grammar.productionAt child).lhs)) :
    GeneratedItem grammar tokens position ⟨child, 0, position⟩ :=
  fun _ closed => closed.predict parent child dot origin position (waiting _ closed) expected

theorem GeneratedItem.scan (production : Fin grammar.productionCount)
    (waiting : GeneratedItem grammar tokens position ⟨production, dot, origin⟩)
    (expected : (grammar.productionAt production).rhs[dot]? = some kind)
    (terminal : kind < grammar.grammar.n_kinds)
    (scanned : scanTerminal grammar tokens position kind = some finish) :
    GeneratedItem grammar tokens finish ⟨production, dot + 1, origin⟩ :=
  fun _ closed => closed.scan production dot origin position kind finish
    (waiting _ closed) expected terminal scanned

theorem GeneratedItem.complete (parent child : Fin grammar.productionCount)
    (waiting : GeneratedItem grammar tokens middle ⟨parent, dot, origin⟩)
    (expected : (grammar.productionAt parent).rhs[dot]? =
      some (grammar.grammar.n_kinds + (grammar.productionAt child).lhs))
    (finished : GeneratedItem grammar tokens finish
      ⟨child, (grammar.productionAt child).rhs.length, middle⟩) :
    GeneratedItem grammar tokens finish ⟨parent, dot + 1, origin⟩ :=
  fun _ closed => closed.complete parent child dot origin middle finish
    (waiting _ closed) expected (finished _ closed)

theorem emptyWorkspace_generated : WorkspaceGenerated grammar tokens emptyWorkspace := by
  intro id state found
  simp [LogicalWorkspace.state?, emptyWorkspace] at found

theorem Append.preserves_generated
    (appended : Append capacity position seed before outcome after)
    (generated : WorkspaceGenerated grammar tokens before)
    (new : GeneratedItem grammar tokens position seed.key) :
    WorkspaceGenerated grammar tokens after := by
  cases appended with
  | existing => exact generated
  | full => exact generated
  | inserted =>
      intro id state found
      by_cases old : id < before.states.length
      · exact generated id state ((insertState_preserves_old before position seed old).symm.trans found)
      · have bound := (List.getElem?_eq_some_iff.mp found).1
        rw [insertState_count] at bound
        have same : id = before.states.length := by omega
        subst id
        rw [insertState_finds_new] at found
        cases found
        exact new

/-- State identity for resource counting ignores whichever sound
backpointer won duplicate insertion. Position is part of that identity. -/
def LogicalWorkspace.itemKeys (workspace : LogicalWorkspace) : List (Nat × StateKey) :=
  workspace.states.map fun state => (state.position, state.key)

theorem WorkspaceWellFormed.itemKeys_nodup
    (valid : WorkspaceWellFormed workspace) : workspace.itemKeys.Nodup := by
  rw [List.nodup_iff_pairwise_ne, List.pairwise_iff_getElem]
  intro i j hi hj before
  simp only [LogicalWorkspace.itemKeys, List.length_map] at hi hj
  simp only [LogicalWorkspace.itemKeys, List.getElem_map]
  intro same
  have position := congrArg Prod.fst same
  have key := congrArg Prod.snd same
  simp only [Prod.fst, Prod.snd] at position key
  have left : workspace.state? i = some workspace.states[i] := List.getElem?_eq_getElem hi
  have right : workspace.state? j = some workspace.states[j] := List.getElem?_eq_getElem hj
  have listed := valid.everyStateCharted j _ right
  rw [← position] at listed
  exact Nat.ne_of_lt before (valid.uniqueKeys _ i j _ _
    (valid.everyStateCharted i _ left) listed left right key)

/-- A well-formed closed candidate chart bounds every generated workspace.
The candidate may contain extra states; it need not be the source parser's
output and its state IDs/backpointers need not match the source execution. -/
theorem WorkspaceGenerated.length_le
    (generated : WorkspaceGenerated grammar tokens workspace)
    (valid : WorkspaceWellFormed workspace)
    (closed : ChartClosed grammar tokens upper)
    (upperSound : ChartSound upper) : workspace.states.length ≤ upper.states.length := by
  have included : workspace.itemKeys ⊆ upper.itemKeys := by
    intro item member
    change item ∈ workspace.states.map (fun state => (state.position, state.key)) at member
    obtain ⟨state, stateMember, itemEq⟩ := List.mem_map.mp member
    subst item
    obtain ⟨id, found⟩ := List.mem_iff_getElem?.mp stateMember
    obtain ⟨upperId, upperState, listed, upperFound, key⟩ := generated id state found upper closed
    obtain ⟨sameState, sameFound, position⟩ := upperSound _ _ listed
    have same := Option.some.inj (sameFound.symm.trans upperFound)
    subst sameState
    change (state.position, state.key) ∈ upper.states.map (fun state => (state.position, state.key))
    apply List.mem_map.mpr
    exact ⟨upperState, List.mem_iff_getElem?.mpr ⟨upperId, upperFound⟩, by simp [position, key]⟩
  simpa only [LogicalWorkspace.itemKeys, List.length_map] using
    valid.itemKeys_nodup.length_le_of_subset included

end Lanius.Compiler.Parser
