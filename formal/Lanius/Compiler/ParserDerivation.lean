import Lanius.Compiler.ParserTree
import Lanius.Compiler.ParserEncoding

namespace Lanius.Compiler.Parser

/-- A derivation reader walks one predecessor for each child. Valid stored
    backpointers therefore bound the child count by the dense state ID. -/
theorem WorkspaceBackpointersSound.dot_le_stateId
    (sound : WorkspaceBackpointersSound grammar tokens workspace)
    (found : workspace.state? stateId = some state) :
    state.dot ≤ stateId := by
  induction stateId using Nat.strongRecOn generalizing state with
  | ind stateId ih =>
    have step := sound stateId state found
    cases step with
    | fresh productionBound => simp [freshSeed, StateSeed.atPosition]
    | terminal previousFound previousBefore productionBound symbolFound kindBound scanned =>
      have bound := ih _ previousBefore previousFound
      simpa [EarleyState.advanceSeed, StateSeed.atPosition] using
        Nat.le_trans (Nat.succ_le_succ bound) previousBefore
    | nonterminal previousFound previousBefore childFound childBefore productionBound
        childProductionBound symbolFound childLhsBound childOrigin childComplete =>
      have bound := ih _ previousBefore previousFound
      simpa [EarleyState.advanceSeed, StateSeed.atPosition] using
        Nat.le_trans (Nat.succ_le_succ bound) previousBefore

/-- The metadata checked on each nonempty reader-loop iteration follows from
    sound backpointers; it need not be assumed separately by the caller. -/
theorem WorkspaceBackpointersSound.predecessor
    (sound : WorkspaceBackpointersSound grammar tokens workspace)
    (found : workspace.state? stateId = some state)
    (nonempty : state.dot ≠ 0) :
    ∃ previousId previous, state.previous = some previousId ∧
      workspace.state? previousId = some previous ∧ previousId < stateId ∧
      state.dot = previous.dot + 1 ∧ state.production = previous.production ∧
      state.origin = previous.origin := by
  cases sound stateId state found with
  | fresh productionBound =>
    exact (nonempty rfl).elim
  | terminal previousFound previousBefore productionBound symbolFound kindBound scanned =>
    exact ⟨_, _, rfl, previousFound, previousBefore, rfl, rfl, rfl⟩
  | nonterminal previousFound previousBefore childFound childBefore productionBound
      childProductionBound symbolFound childLhsBound childOrigin childComplete =>
    exact ⟨_, _, rfl, previousFound, previousBefore, rfl, rfl, rfl⟩

/-- The reader terminates at exactly the sentinel metadata emitted for a seed. -/
theorem WorkspaceBackpointersSound.zero_dot_seed
    (sound : WorkspaceBackpointersSound grammar tokens workspace)
    (found : workspace.state? stateId = some state)
    (empty : state.dot = 0) :
    state.previous = none ∧ state.child = .none := by
  cases sound stateId state found with
  | fresh productionBound => exact ⟨rfl, rfl⟩
  | terminal previousFound previousBefore productionBound symbolFound kindBound scanned =>
    simp [EarleyState.advanceSeed, StateSeed.atPosition] at empty
  | nonterminal previousFound previousBefore childFound childBefore productionBound
      childProductionBound symbolFound childLhsBound childOrigin childComplete =>
    simp [EarleyState.advanceSeed, StateSeed.atPosition] at empty

/-- Logical specification of the retained-child reader. It reads backpointers,
    not grammar productions, and returns children in source order. -/
def derivationChildren? (workspace : LogicalWorkspace) : Nat → Nat → Option (List Child)
  | 0, _ => none
  | fuel + 1, stateId => do
    let state ← workspace.state? stateId
    if state.dot = 0 then
      if state.previous = none ∧ state.child = .none then some [] else none
    else do
      let previous ← state.previous
      let children ← derivationChildren? workspace fuel previous
      pure (children ++ [state.child])

/-- A sound workspace needs at most one fuel unit per dense predecessor ID.
    Every stored child is retained, in order, with no duplicate search. -/
theorem WorkspaceBackpointersSound.derivationChildren_complete
    (sound : WorkspaceBackpointersSound grammar tokens workspace)
    (found : workspace.state? stateId = some state)
    (enough : stateId < fuel) :
    ∃ children, derivationChildren? workspace fuel stateId = some children ∧
      children.length = state.dot := by
  induction fuel generalizing stateId state with
  | zero => omega
  | succ fuel ih =>
    by_cases empty : state.dot = 0
    · obtain ⟨previous, child⟩ := sound.zero_dot_seed found empty
      exact ⟨[], by simp [derivationChildren?, found, empty, previous, child], empty.symm⟩
    · obtain ⟨previousId, previous, pointer, previousFound, earlier, dot, _, _⟩ :=
        sound.predecessor found empty
      obtain ⟨children, computed, length⟩ := ih previousFound (by omega)
      refine ⟨children ++ [state.child], ?_, ?_⟩
      · simp [derivationChildren?, found, empty, pointer, computed]
      · simp [length, dot]

/-- Accumulate the already-read suffix while walking backwards. Unlike the
    specification, this performs no growing-list append on each step. -/
def derivationChildrenAcc? (workspace : LogicalWorkspace) :
    Nat → Nat → List Child → Option (List Child)
  | 0, _, _ => none
  | fuel + 1, stateId, suffix => do
    let state ← workspace.state? stateId
    if state.dot = 0 then
      if state.previous = none ∧ state.child = .none then some suffix else none
    else do
      let previous ← state.previous
      derivationChildrenAcc? workspace fuel previous (state.child :: suffix)

theorem derivationChildrenAcc_eq (workspace : LogicalWorkspace)
    (fuel stateId : Nat) (suffix : List Child) :
    derivationChildrenAcc? workspace fuel stateId suffix =
      (derivationChildren? workspace fuel stateId).map (· ++ suffix) := by
  induction fuel generalizing stateId suffix with
  | zero => rfl
  | succ fuel ih =>
    cases found : workspace.state? stateId with
    | none => simp [derivationChildrenAcc?, derivationChildren?, found]
    | some state =>
      by_cases empty : state.dot = 0
      · by_cases seed : state.previous = none ∧ state.child = .none
        <;> simp [derivationChildrenAcc?, derivationChildren?, found, empty, seed]
      · cases pointer : state.previous with
        | none => simp [derivationChildrenAcc?, derivationChildren?, found, empty, pointer]
        | some previous =>
          simp [derivationChildrenAcc?, derivationChildren?, found, empty, pointer, ih]
          cases derivationChildren? workspace fuel previous <;> simp [List.append_assoc]

/-- Logical invariant of the backwards reader loop. `suffix` is the part
    already written in grammar order; `children` is the complete output. -/
structure DerivationCursor (workspace : LogicalWorkspace) (root state : EarleyState)
    (fuel current remaining : Nat) (suffix children : List Child) : Prop where
  found : workspace.state? current = some state
  dot : state.dot = remaining
  production : state.production = root.production
  origin : state.origin = root.origin
  output : derivationChildrenAcc? workspace fuel current suffix = some children

theorem WorkspaceBackpointersSound.reader_initial
    (sound : WorkspaceBackpointersSound grammar tokens workspace)
    (found : workspace.state? stateId = some root)
    (enough : stateId < fuel) :
    ∃ children, children.length = root.dot ∧
      DerivationCursor workspace root root fuel stateId root.dot [] children := by
  obtain ⟨children, computed, length⟩ := sound.derivationChildren_complete found enough
  refine ⟨children, length, found, rfl, rfl, rfl, ?_⟩
  simp [derivationChildrenAcc_eq, computed]

/-- One successful iteration consumes exactly the last outstanding child;
    root metadata and the complete output are unchanged. -/
theorem DerivationCursor.advance
    (cursor : DerivationCursor workspace root currentState (fuel + 1) current (remaining + 1)
      suffix children)
    (sound : WorkspaceBackpointersSound grammar tokens workspace) :
    ∃ previous state, currentState.previous = some previous ∧ previous < current ∧
      DerivationCursor workspace root state fuel previous remaining
        (currentState.child :: suffix) children := by
  have nonempty : currentState.dot ≠ 0 := by rw [cursor.dot]; omega
  obtain ⟨previous, state, pointer, found, earlier, dot, production, origin⟩ :=
    sound.predecessor cursor.found nonempty
  refine ⟨previous, state, pointer, earlier, found, ?_,
    production.symm.trans cursor.production, origin.symm.trans cursor.origin, ?_⟩
  · have currentDot := cursor.dot
    omega
  · have output := cursor.output
    simpa [derivationChildrenAcc?, cursor.found, nonempty, pointer] using output

/-- At loop exit, all children have been written and the final metadata
    checks follow from the same invariant used by each iteration. -/
theorem DerivationCursor.finish
    (cursor : DerivationCursor workspace root state (fuel + 1) current 0 suffix children)
    (sound : WorkspaceBackpointersSound grammar tokens workspace) :
    suffix = children ∧ state.previous = none ∧ state.child = .none := by
  obtain ⟨previous, child⟩ := sound.zero_dot_seed cursor.found cursor.dot
  refine ⟨?_, previous, child⟩
  have output := cursor.output
  simpa [derivationChildrenAcc?, cursor.found, cursor.dot, previous, child] using output

theorem WorkspaceBackpointersSound.nonempty_child
    (sound : WorkspaceBackpointersSound grammar tokens workspace)
    (found : workspace.state? stateId = some state)
    (nonempty : state.dot ≠ 0) : state.child ≠ .none := by
  cases sound stateId state found with
  | fresh productionBound => exact (nonempty rfl).elim
  | terminal previousFound previousBefore productionBound symbolFound kindBound scanned =>
    simp [EarleyState.advanceSeed, StateSeed.atPosition]
  | nonterminal previousFound previousBefore childFound childBefore productionBound
      childProductionBound symbolFound childLhsBound childOrigin childComplete =>
    simp [EarleyState.advanceSeed, StateSeed.atPosition]

/-- The sentinel terminates the chain but is never part of its output. -/
theorem WorkspaceBackpointersSound.derivationChildren_no_sentinel
    (sound : WorkspaceBackpointersSound grammar tokens workspace)
    (found : workspace.state? stateId = some state)
    (enough : stateId < fuel)
    (computed : derivationChildren? workspace fuel stateId = some children) :
    Child.none ∉ children := by
  induction fuel generalizing stateId state children with
  | zero => omega
  | succ fuel ih =>
    by_cases empty : state.dot = 0
    · obtain ⟨previous, child⟩ := sound.zero_dot_seed found empty
      simp [derivationChildren?, found, empty, previous, child] at computed
      subst children
      simp
    · obtain ⟨previousId, previous, pointer, previousFound, earlier, _, _, _⟩ :=
        sound.predecessor found empty
      obtain ⟨preceding, prefixComputed, _⟩ :=
        sound.derivationChildren_complete previousFound (show previousId < fuel by omega)
      have prefixGood := ih previousFound (by omega) prefixComputed
      have childGood := sound.nonempty_child found empty
      simp [derivationChildren?, found, empty, pointer, prefixComputed] at computed
      rw [← computed]
      simp [prefixGood, Ne.symm childGood]

theorem WorkspaceBackpointersSound.state_child_before
    (sound : WorkspaceBackpointersSound grammar tokens workspace)
    (found : workspace.state? stateId = some state)
    (child : state.child = .state childId) :
    childId < stateId ∧ ∃ childState, workspace.state? childId = some childState ∧
      ∃ productionBound : childState.production < grammar.productionCount,
        childState.dot = (grammar.productionAt ⟨childState.production, productionBound⟩).rhs.length := by
  cases sound stateId state found with
  | fresh productionBound => cases child
  | terminal previousFound previousBefore productionBound symbolFound kindBound scanned =>
    cases child
  | nonterminal previousFound previousBefore childFound childBefore productionBound
      childProductionBound symbolFound childLhsBound childOrigin childComplete =>
    simp only [EarleyState.advanceSeed, StateSeed.atPosition, Child.state.injEq] at child
    subst childId
    exact ⟨childBefore, _, childFound, childProductionBound, childComplete⟩

/-- Every recursive child reference is resident, complete for its production,
    and strictly earlier than the requested state, even when it was read from
    an older predecessor. These are the recursive materializer's entry facts. -/
theorem WorkspaceBackpointersSound.derivationChildren_state_before
    (sound : WorkspaceBackpointersSound grammar tokens workspace)
    (found : workspace.state? stateId = some state)
    (enough : stateId < fuel)
    (computed : derivationChildren? workspace fuel stateId = some children)
    (member : Child.state childId ∈ children) :
    childId < stateId ∧ ∃ childState, workspace.state? childId = some childState ∧
      ∃ productionBound : childState.production < grammar.productionCount,
        childState.dot = (grammar.productionAt ⟨childState.production, productionBound⟩).rhs.length := by
  induction fuel generalizing stateId state children with
  | zero => omega
  | succ fuel ih =>
    by_cases empty : state.dot = 0
    · obtain ⟨previous, child⟩ := sound.zero_dot_seed found empty
      simp [derivationChildren?, found, empty, previous, child] at computed
      subst children
      simp at member
    · obtain ⟨previousId, previous, pointer, previousFound, earlier, _, _, _⟩ :=
        sound.predecessor found empty
      obtain ⟨preceding, prefixComputed, _⟩ :=
        sound.derivationChildren_complete previousFound (show previousId < fuel by omega)
      simp [derivationChildren?, found, empty, pointer, prefixComputed] at computed
      rw [← computed] at member
      rcases List.mem_append.mp member with prior | current
      · obtain ⟨bound, resident⟩ := ih previousFound (by omega) prefixComputed prior
        exact ⟨Nat.lt_trans bound earlier, resident⟩
      · have same : state.child = .state childId := (List.mem_singleton.mp current).symm
        exact sound.state_child_before found same

theorem WorkspaceBackpointersSound.token_child_bound
    (sound : WorkspaceBackpointersSound grammar tokens workspace)
    (found : workspace.state? stateId = some state)
    (child : state.child = .token tokenIndex semanticKind) :
    tokenIndex < tokens.length ∧ semanticKind < grammar.grammar.n_kinds := by
  cases sound stateId state found with
  | fresh productionBound => cases child
  | terminal previousFound previousBefore productionBound symbolFound kindBound scanned =>
    simp only [EarleyState.advanceSeed, StateSeed.atPosition, Child.token.injEq] at child
    rcases child with ⟨rfl, rfl⟩
    have upper := scanTerminal_some_le_finalPosition _ _ _ _ _ scanned
    have lower := scanTerminal_some_gt scanned
    unfold finalPosition at upper
    exact ⟨by omega, kindBound⟩
  | nonterminal previousFound previousBefore childFound childBefore productionBound
      childProductionBound symbolFound childLhsBound childOrigin childComplete =>
    cases child

/-- The reader's encoded child checks cannot reject a nonempty sound state.
    These are the signed comparisons used by `copy_derivation`, including
    the distinction between token payloads and earlier-state payloads. -/
theorem WorkspaceBackpointersSound.reader_child_guard
    (sound : WorkspaceBackpointersSound grammar tokens workspace)
    (found : workspace.state? stateId = some state)
    (nonempty : state.dot ≠ 0) :
    ¬ childPayload state.child ≤ -1 ∧
      (if childTag state.child = 1 then
        childPayload state.child < (tokens.length : Int)
      else childTag state.child = 2 ∧ childPayload state.child < (stateId : Int)) := by
  have present := sound.nonempty_child found nonempty
  cases child : state.child with
  | none => exact (present child).elim
  | token tokenIndex semanticKind =>
    have bound := (sound.token_child_bound found child).1
    change ¬ (tokenIndex : Int) ≤ -1 ∧ (tokenIndex : Int) < (tokens.length : Int)
    omega
  | state childId =>
    have bound := (sound.state_child_before found child).1
    change ¬ (childId : Int) ≤ -1 ∧ (2 : Int) = 2 ∧ (childId : Int) < (stateId : Int)
    omega

theorem WorkspaceBackpointersSound.derivationChildren_token_bound
    (sound : WorkspaceBackpointersSound grammar tokens workspace)
    (found : workspace.state? stateId = some state)
    (enough : stateId < fuel)
    (computed : derivationChildren? workspace fuel stateId = some children)
    (member : Child.token tokenIndex semanticKind ∈ children) :
    tokenIndex < tokens.length ∧ semanticKind < grammar.grammar.n_kinds := by
  induction fuel generalizing stateId state children with
  | zero => omega
  | succ fuel ih =>
    by_cases empty : state.dot = 0
    · obtain ⟨previous, child⟩ := sound.zero_dot_seed found empty
      simp [derivationChildren?, found, empty, previous, child] at computed
      subst children
      simp at member
    · obtain ⟨previousId, previous, pointer, previousFound, earlier, _, _, _⟩ :=
        sound.predecessor found empty
      obtain ⟨preceding, prefixComputed, _⟩ :=
        sound.derivationChildren_complete previousFound (show previousId < fuel by omega)
      simp [derivationChildren?, found, empty, pointer, prefixComputed] at computed
      rw [← computed] at member
      rcases List.mem_append.mp member with prior | current
      · exact ih previousFound (by omega) prefixComputed prior
      · exact sound.token_child_bound found (List.mem_singleton.mp current).symm

/-- The exact three-word child format copied out of the packed workspace. -/
def derivationChildWords (child : Child) : List Int :=
  [childTag child, childPayload child, childKind child]

/-- The three indexed stores used by the reader prepend one child's words
    to the completed suffix, preserving every word outside those slots. -/
theorem derivationChildWords_store (leading trailing : List Int)
    (oldTag oldPayload oldKind : Int) (child : Child) (suffix : List Child) :
    (((leading ++ [oldTag, oldPayload, oldKind] ++
        suffix.flatMap derivationChildWords ++ trailing).set leading.length
        (childTag child)).set (leading.length + 1) (childPayload child)).set
        (leading.length + 2) (childKind child) =
      leading ++ (child :: suffix).flatMap derivationChildWords ++ trailing := by
  induction leading with
  | nil => simp [derivationChildWords]
  | cons word leading ih => simpa [Nat.add_assoc] using congrArg (List.cons word) ih

def derivationRecordWords (state : EarleyState) (children : List Child) : List Int :=
  [Int.ofNat state.production, Int.ofNat state.origin, Int.ofNat state.position,
    Int.ofNat children.length] ++ children.flatMap derivationChildWords

theorem derivationRecordWords_length (state : EarleyState) (children : List Child) :
    (derivationRecordWords state children).length = 4 + 3 * children.length := by
  have childLength : (children.flatMap derivationChildWords).length = 3 * children.length := by
    induction children with
    | nil => rfl
    | cons child children ih =>
      simp [List.flatMap_cons, derivationChildWords, ih, Nat.mul_add, Nat.add_comm]
      omega
  simp [derivationRecordWords, childLength]
  omega

/-- The reader's output-space guard is exactly the complete record size,
    including the four-word header and all child triples. -/
theorem derivationRecordWords_fits (state : EarleyState) (children : List Child)
    (offset capacity : Nat) :
    offset + (derivationRecordWords state children).length ≤ capacity ↔
      offset + 4 ≤ capacity ∧ children.length ≤ (capacity - offset - 4) / 3 := by
  rw [derivationRecordWords_length]
  omega

/-- Field reads performed by `copy_derivation` for one child triple. -/
def packedDerivationChild (words : Words) (tokenCount stateId : Nat) : List Int :=
  [words (stateWord (stateBase tokenCount) stateId 6),
   words (stateWord (stateBase tokenCount) stateId 7),
   words (stateWord (stateBase tokenCount) stateId 8)]

theorem EncodesWorkspace.derivation_child
    (encoded : EncodesWorkspace layout workspace words)
    (found : workspace.state? stateId = some state) :
    packedDerivationChild words layout.tokenCount stateId =
      derivationChildWords state.child := by
  unfold packedDerivationChild
  rw [encoded.stateField stateId state found 6 (by decide),
      encoded.stateField stateId state found 7 (by decide),
      encoded.stateField stateId state found 8 (by decide)]
  rfl

/-- The reader deliberately rearranges packed state fields into its output
    header: production, origin, end position, then dot/child count. -/
def packedDerivationHeader (words : Words) (tokenCount stateId : Nat) : List Int :=
  [words (stateWord (stateBase tokenCount) stateId 0),
   words (stateWord (stateBase tokenCount) stateId 2),
   words (stateWord (stateBase tokenCount) stateId 3),
   words (stateWord (stateBase tokenCount) stateId 1)]

theorem EncodesWorkspace.derivation_header
    (encoded : EncodesWorkspace layout workspace words)
    (found : workspace.state? stateId = some state) :
    packedDerivationHeader words layout.tokenCount stateId =
      [Int.ofNat state.production, Int.ofNat state.origin,
       Int.ofNat state.position, Int.ofNat state.dot] := by
  unfold packedDerivationHeader
  rw [encoded.stateField stateId state found 0 (by decide),
      encoded.stateField stateId state found 2 (by decide),
      encoded.stateField stateId state found 3 (by decide),
      encoded.stateField stateId state found 1 (by decide)]
  rfl

/-- Arithmetic meaning of the source output guards, before machine-integer
    evaluation. Their successful branch guarantees room for the whole record. -/
theorem derivation_output_guard (offset capacity count : Int) (countNonnegative : 0 ≤ count) :
    (¬ offset ≤ -1 ∧ offset ≤ capacity ∧ ¬ capacity - offset ≤ 3 ∧
      count ≤ (capacity - offset - 4) / 3) ↔
    (0 ≤ offset ∧ offset + 4 + count * 3 ≤ capacity) := by
  omega

/-- All three writes in a backwards child-copy iteration fit the output and
    stay within signed-i32 arithmetic when the physical capacity does. -/
theorem derivation_child_slot_bounds (offset capacity count remaining : Int)
    (offsetNonnegative : 0 ≤ offset)
    (fits : offset + 4 + count * 3 ≤ capacity)
    (capacityI32 : capacity ≤ 2147483647)
    (remainingPositive : 0 < remaining) (remainingBound : remaining ≤ count) :
    0 ≤ (remaining - 1) * 3 ∧ (remaining - 1) * 3 ≤ 2147483647 ∧
    0 ≤ offset + 4 + (remaining - 1) * 3 ∧
    offset + 4 + (remaining - 1) * 3 + 2 < capacity ∧
    offset + 4 + (remaining - 1) * 3 + 2 ≤ 2147483647 := by
  omega

end Lanius.Compiler.Parser
