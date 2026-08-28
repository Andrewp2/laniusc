import Lanius.Compiler.ParserLanguage

namespace Lanius.Compiler.Parser

/-! # Logical Earley workspace

This model removes the linked-list and sentinel encoding used by the Lanius
implementation while retaining dense state identities and derivation
backpointers.  `Append` is deliberately relational: the proof of extracted
`append_state` will show that its mutations implement exactly one constructor.
-/

inductive Child where
  | none
  | token (tokenIndex semanticKind : Nat)
  | state (stateId : Nat)
deriving DecidableEq, Repr

structure StateKey where
  production : Nat
  dot : Nat
  origin : Nat
deriving DecidableEq, Repr

structure StateSeed extends StateKey where
  previous : Option Nat
  child : Child
deriving DecidableEq, Repr

structure EarleyState extends StateSeed where
  position : Nat
deriving DecidableEq, Repr

def EarleyState.key (state : EarleyState) : StateKey :=
  state.toStateSeed.toStateKey

def StateSeed.key (seed : StateSeed) : StateKey :=
  seed.toStateKey

def StateSeed.atPosition (seed : StateSeed) (position : Nat) : EarleyState :=
  { seed with position }

/-- Canonical seed for an initial or predicted production. -/
def freshSeed (production origin : Nat) : StateSeed := {
  production := production
  dot := 0
  origin := origin
  previous := none
  child := .none
}

/-- Canonical seed obtained by recognizing the symbol at an Earley item's
    dot. Backpointer data is retained for later tree reconstruction but is not
    part of the declarative recognition judgment. -/
def EarleyState.advanceSeed
    (state : EarleyState) (stateId : Nat) (child : Child) : StateSeed := {
  production := state.production
  dot := state.dot + 1
  origin := state.origin
  previous := some stateId
  child := child
}

@[simp] theorem StateSeed.atPosition_key
    (seed : StateSeed) (position : Nat) :
    (seed.atPosition position).key = seed.key := by
  rfl

structure LogicalWorkspace where
  chart : Nat → List Nat
  states : List EarleyState

/-- Initial semantic workspace represented by a chart prefix filled with
    `-1` and no state records. -/
def emptyWorkspace : LogicalWorkspace := {
  chart := fun _ => []
  states := []
}

@[simp] theorem emptyWorkspace_chart (position : Nat) :
    emptyWorkspace.chart position = [] := rfl

@[simp] theorem emptyWorkspace_states : emptyWorkspace.states = [] := rfl

def LogicalWorkspace.state? (workspace : LogicalWorkspace)
    (stateId : Nat) : Option EarleyState :=
  workspace.states[stateId]?

def LogicalWorkspace.containsKey (workspace : LogicalWorkspace)
    (position : Nat) (key : StateKey) : Prop :=
  ∃ stateId state,
    stateId ∈ workspace.chart position ∧
    workspace.state? stateId = some state ∧
    state.key = key

/-- Semantic meaning of one Earley item: the right-hand-side prefix before
    its dot recognizes exactly the lattice span from `origin` to `position`.
    This intentionally ignores state IDs and backpointer representation. -/
structure EarleyStateSound
    (grammar : IndexedGrammar) (tokens : List Nat)
    (state : EarleyState) : Prop where
  productionBound : state.production < grammar.productionCount
  recognizedPrefix : RecognizesSequence grammar tokens
    (List.take state.dot
      (grammar.productionAt ⟨state.production, productionBound⟩).rhs)
    state.origin state.position

/-- Every state resident in a logical workspace denotes a valid partial
    derivation in the declarative grammar. -/
def WorkspaceLanguageSound
    (grammar : IndexedGrammar) (tokens : List Nat)
    (workspace : LogicalWorkspace) : Prop :=
  ∀ stateId state, workspace.state? stateId = some state →
    EarleyStateSound grammar tokens state

theorem emptyWorkspace_languageSound
    (grammar : IndexedGrammar) (tokens : List Nat) :
    WorkspaceLanguageSound grammar tokens emptyWorkspace := by
  intro stateId state found
  simp [LogicalWorkspace.state?, emptyWorkspace] at found

/-- A fresh item recognizes the empty prefix at its origin. -/
theorem freshSeed_sound
    (productionBound : production < grammar.productionCount) :
    EarleyStateSound grammar tokens
      ((freshSeed production position).atPosition position) := {
  productionBound := by simpa [freshSeed, StateSeed.atPosition]
  recognizedPrefix := by
    simpa [freshSeed, StateSeed.atPosition] using
      (RecognizesSequence.empty :
        RecognizesSequence grammar tokens [] position position)
}

/-- Advance a sound item over one recognized grammar symbol. -/
theorem EarleyStateSound.advance
    (sound : EarleyStateSound grammar tokens state)
    (symbolFound :
      (grammar.productionAt
        ⟨state.production, sound.productionBound⟩).rhs[state.dot]? =
          some symbol)
    (recognized : RecognizesSymbol grammar tokens symbol state.position finish)
    (stateId : Nat) (child : Child) :
    EarleyStateSound grammar tokens
      ((state.advanceSeed stateId child).atPosition finish) := by
  let rhs := (grammar.productionAt
    ⟨state.production, sound.productionBound⟩).rhs
  have dotBound : state.dot < rhs.length :=
    List.getElem?_eq_some_iff.mp symbolFound |>.1
  have symbolEq : rhs[state.dot] = symbol := by
    rw [List.getElem?_eq_getElem dotBound] at symbolFound
    exact Option.some.inj symbolFound
  exact {
    productionBound := by
      simpa [EarleyState.advanceSeed, StateSeed.atPosition] using
        sound.productionBound
    recognizedPrefix := by
      have advanced := sound.recognizedPrefix.append_symbol recognized
      rw [← symbolEq] at advanced
      change RecognizesSequence grammar tokens
        (List.take (state.dot + 1) rhs) state.origin finish
      rw [List.take_succ_eq_append_getElem dotBound]
      exact advanced
  }

/-- A complete sound item recognizes its production's nonterminal. -/
theorem EarleyStateSound.complete
    (sound : EarleyStateSound grammar tokens state)
    (nonterminalBound :
      (grammar.productionAt
        ⟨state.production, sound.productionBound⟩).lhs <
        grammar.grammar.n_nonterminals)
    (complete : state.dot =
      (grammar.productionAt
        ⟨state.production, sound.productionBound⟩).rhs.length) :
    RecognizesSymbol grammar tokens
      (grammar.grammar.n_kinds +
        (grammar.productionAt
          ⟨state.production, sound.productionBound⟩).lhs)
      state.origin state.position := by
  apply RecognizesSymbol.nonterminal nonterminalBound sound.productionBound rfl
  simpa [complete] using sound.recognizedPrefix

/-- A complete start item spanning the full lattice proves language
    recognition. -/
theorem EarleyStateSound.recognizes_input
    (sound : EarleyStateSound grammar tokens state)
    (startBound : grammar.grammar.start_nonterminal <
      grammar.grammar.n_nonterminals)
    (origin : state.origin = 0)
    (lhs : (grammar.productionAt
      ⟨state.production, sound.productionBound⟩).lhs =
        grammar.grammar.start_nonterminal)
    (complete : state.dot =
      (grammar.productionAt
        ⟨state.production, sound.productionBound⟩).rhs.length)
    (finish : state.position = finalPosition tokens.length) :
    RecognizesInput grammar tokens := by
  unfold RecognizesInput
  have lhsBound :
      (grammar.productionAt
        ⟨state.production, sound.productionBound⟩).lhs <
        grammar.grammar.n_nonterminals := by
    rw [lhs]
    exact startBound
  have completed := sound.complete lhsBound complete
  rw [origin, finish, lhs] at completed
  exact completed

/-- The abstract counterpart of the source parser's linked-list walk.  The
    concrete implementation follows `STATE_NEXT`; this definition searches
    the corresponding chart IDs without exposing their word encoding. -/
def findStateIn? (workspace : LogicalWorkspace) (key : StateKey) :
    List Nat → Option Nat
  | [] => none
  | stateId :: rest =>
      match workspace.state? stateId with
      | some state =>
          if state.key = key then some stateId
          else findStateIn? workspace key rest
      | none => findStateIn? workspace key rest

def LogicalWorkspace.findStateId? (workspace : LogicalWorkspace)
    (position : Nat) (key : StateKey) : Option Nat :=
  findStateIn? workspace key (workspace.chart position)

def NoStateWithKey (workspace : LogicalWorkspace) (key : StateKey)
    (ids : List Nat) : Prop :=
  ∀ stateId state,
    stateId ∈ ids →
    workspace.state? stateId = some state →
    state.key ≠ key

theorem NoStateWithKey.nil : NoStateWithKey workspace key [] := by
  intro stateId state listed
  simp at listed

theorem NoStateWithKey.cons
    (headDifferent : ∀ state,
      workspace.state? head = some state → state.key ≠ key)
    (tail : NoStateWithKey workspace key rest) :
    NoStateWithKey workspace key (head :: rest) := by
  intro stateId state listed found
  rcases List.mem_cons.mp listed with equal | tailListed
  · subst stateId
    exact headDifferent state found
  · exact tail stateId state tailListed found

theorem NoStateWithKey.append_singleton
    (before : NoStateWithKey workspace key ids)
    (different : ∀ state,
      workspace.state? stateId = some state → state.key ≠ key) :
    NoStateWithKey workspace key (ids ++ [stateId]) := by
  intro queried state listed found
  rcases List.mem_append.mp listed with old | added
  · exact before queried state old found
  · have equal : queried = stateId := by simpa using added
    subst queried
    exact different state found

theorem findStateIn?_drop_no_matching_prefix
    (noMatch : NoStateWithKey workspace key visited) :
    findStateIn? workspace key (visited ++ remaining) =
      findStateIn? workspace key remaining := by
  induction visited with
  | nil => rfl
  | cons head tail inductionHypothesis =>
      have tailNoMatch : NoStateWithKey workspace key tail := by
        intro stateId state listed found
        exact noMatch stateId state (List.mem_cons_of_mem head listed) found
      cases stateFound : workspace.state? head with
      | none =>
          simpa [findStateIn?, stateFound] using
            inductionHypothesis tailNoMatch
      | some state =>
          have different : state.key ≠ key :=
            noMatch head state List.mem_cons_self stateFound
          simpa [findStateIn?, stateFound, different] using
            inductionHypothesis tailNoMatch

theorem findStateIn?_some_sound
    (found : findStateIn? workspace key ids = some stateId) :
    ∃ state,
      stateId ∈ ids ∧
      workspace.state? stateId = some state ∧
      state.key = key := by
  induction ids with
  | nil => simp [findStateIn?] at found
  | cons head rest inductionHypothesis =>
      cases stateFound : workspace.state? head with
      | none =>
          have tail := inductionHypothesis (by
            simpa [findStateIn?, stateFound] using found)
          obtain ⟨state, listed, exactState, sameKey⟩ := tail
          exact ⟨state, List.mem_cons_of_mem head listed, exactState, sameKey⟩
      | some state =>
          by_cases sameKey : state.key = key
          · have headEqual : head = stateId := by
              simpa [findStateIn?, stateFound, sameKey] using found
            subst stateId
            exact ⟨state, List.mem_cons_self, stateFound, sameKey⟩
          · have tail := inductionHypothesis (by
              simpa [findStateIn?, stateFound, sameKey] using found)
            obtain ⟨tailState, listed, exactState, tailKey⟩ := tail
            exact ⟨tailState, List.mem_cons_of_mem head listed,
              exactState, tailKey⟩

theorem findStateIn?_none_iff :
    findStateIn? workspace key ids = none ↔
      ¬ ∃ stateId state,
        stateId ∈ ids ∧
        workspace.state? stateId = some state ∧
        state.key = key := by
  induction ids with
  | nil => simp [findStateIn?]
  | cons head rest inductionHypothesis =>
      cases stateFound : workspace.state? head with
      | none =>
          simp only [findStateIn?, stateFound, inductionHypothesis]
          constructor
          · intro noTail ⟨stateId, state, listed, exactState, sameKey⟩
            rcases List.mem_cons.mp listed with equal | tailListed
            · subst stateId
              simp [stateFound] at exactState
            · exact noTail ⟨stateId, state, tailListed, exactState, sameKey⟩
          · intro noMatch ⟨stateId, state, listed, exactState, sameKey⟩
            exact noMatch ⟨stateId, state, List.mem_cons_of_mem head listed,
              exactState, sameKey⟩
      | some state =>
          by_cases sameKey : state.key = key
          · simp [findStateIn?, stateFound, sameKey]
          · simp only [findStateIn?, stateFound, sameKey, if_false,
              inductionHypothesis]
            constructor
            · intro noTail ⟨stateId, foundState, listed, exactState,
                  foundKey⟩
              rcases List.mem_cons.mp listed with equal | tailListed
              · subst stateId
                rw [stateFound] at exactState
                injection exactState with stateEqual
                exact sameKey (stateEqual ▸ foundKey)
              · exact noTail ⟨stateId, foundState, tailListed,
                  exactState, foundKey⟩
            · intro noMatch ⟨stateId, foundState, listed, exactState,
                  foundKey⟩
              exact noMatch ⟨stateId, foundState,
                List.mem_cons_of_mem head listed, exactState, foundKey⟩

theorem LogicalWorkspace.findStateId?_some_sound
    {workspace : LogicalWorkspace} {position : Nat} {key : StateKey}
    {stateId : Nat}
    (found : workspace.findStateId? position key = some stateId) :
    ∃ state,
      stateId ∈ workspace.chart position ∧
      workspace.state? stateId = some state ∧
      state.key = key :=
  findStateIn?_some_sound found

theorem LogicalWorkspace.findStateId?_none_iff :
    ∀ {workspace : LogicalWorkspace} {position : Nat} {key : StateKey},
    workspace.findStateId? position key = none ↔
      ¬ workspace.containsKey position key := by
  intro workspace position key
  simpa [LogicalWorkspace.findStateId?, LogicalWorkspace.containsKey]
    using (findStateIn?_none_iff (workspace := workspace)
      (key := key) (ids := workspace.chart position))

def appendChart
    (chart : Nat → List Nat) (position stateId : Nat) : Nat → List Nat :=
  fun queried =>
    if queried = position then chart queried ++ [stateId] else chart queried

def insertState (workspace : LogicalWorkspace)
    (position : Nat) (seed : StateSeed) : LogicalWorkspace :=
  let stateId := workspace.states.length
  {
    chart := appendChart workspace.chart position stateId
    states := workspace.states ++ [seed.atPosition position]
  }

inductive AppendStatus where
  | ok
  | full
deriving DecidableEq, Repr

structure AppendOutcome where
  status : AppendStatus
  stateId : Option Nat
  stateCount : Nat
  inserted : Bool
deriving DecidableEq, Repr

inductive Append (capacity position : Nat) (seed : StateSeed) :
    LogicalWorkspace → AppendOutcome → LogicalWorkspace → Prop where
  | existing
      (before : LogicalWorkspace) (stateId : Nat) (state : EarleyState)
      (listed : stateId ∈ before.chart position)
      (found : before.state? stateId = some state)
      (sameKey : state.key = seed.key) :
      Append capacity position seed before {
        status := .ok
        stateId := some stateId
        stateCount := before.states.length
        inserted := false
      } before
  | full
      (before : LogicalWorkspace)
      (absent : ¬ before.containsKey position seed.key)
      (atCapacity : capacity ≤ before.states.length) :
      Append capacity position seed before {
        status := .full
        stateId := none
        stateCount := before.states.length
        inserted := false
      } before
  | inserted
      (before : LogicalWorkspace)
      (absent : ¬ before.containsKey position seed.key)
      (hasCapacity : before.states.length < capacity) :
      Append capacity position seed before {
        status := .ok
        stateId := some before.states.length
        stateCount := before.states.length + 1
        inserted := true
      } (insertState before position seed)

/-- Executable abstract append.  This has the same three decisions as the
    Lanius implementation, but operates on dense states and chart lists rather
    than encoded words. -/
def appendLogical (capacity position : Nat) (seed : StateSeed)
    (before : LogicalWorkspace) : AppendOutcome × LogicalWorkspace :=
  match before.findStateId? position seed.key with
  | some stateId => ({
      status := .ok
      stateId := some stateId
      stateCount := before.states.length
      inserted := false
    }, before)
  | none =>
      if capacity ≤ before.states.length then ({
        status := .full
        stateId := none
        stateCount := before.states.length
        inserted := false
      }, before)
      else ({
        status := .ok
        stateId := some before.states.length
        stateCount := before.states.length + 1
        inserted := true
      }, insertState before position seed)

@[simp] theorem appendLogical_stateCount_eq
    (capacity position : Nat) (seed : StateSeed)
    (before : LogicalWorkspace) :
    (appendLogical capacity position seed before).1.stateCount =
      (appendLogical capacity position seed before).2.states.length := by
  unfold appendLogical
  split
  · rfl
  · split <;> simp [insertState]

/-- Capacity exhaustion is observationally non-mutating in the logical
    workspace model.  This fact is the semantic bridge used by nested parser
    loops to return the exact workspace accumulated before the failed append. -/
theorem appendLogical_workspace_eq_of_full
    (statusFull :
      (appendLogical capacity position seed before).1.status = .full) :
    (appendLogical capacity position seed before).2 = before := by
  unfold appendLogical at statusFull ⊢
  split
  · simp_all
  · split
    · rfl
    · simp_all

theorem appendLogical_stateCount_of_full
    (statusFull :
      (appendLogical capacity position seed before).1.status = .full) :
    (appendLogical capacity position seed before).1.stateCount =
      before.states.length := by
  rw [appendLogical_stateCount_eq,
    appendLogical_workspace_eq_of_full statusFull]

theorem appendLogical_refines
    (result : AppendOutcome × LogicalWorkspace)
    (computed : appendLogical capacity position seed before = result) :
    Append capacity position seed before result.1 result.2 := by
  cases found : before.findStateId? position seed.key with
  | some stateId =>
      obtain ⟨state, listed, exactState, sameKey⟩ :=
        before.findStateId?_some_sound found
      rw [appendLogical, found] at computed
      subst result
      exact .existing before stateId state listed exactState sameKey
  | none =>
      have absent : ¬ before.containsKey position seed.key :=
        before.findStateId?_none_iff.mp found
      by_cases atCapacity : capacity ≤ before.states.length
      · rw [appendLogical, found, if_pos atCapacity] at computed
        subst result
        exact .full before absent atCapacity
      · have hasCapacity : before.states.length < capacity :=
          Nat.lt_of_not_ge atCapacity
        rw [appendLogical, found, if_neg atCapacity] at computed
        subst result
        exact .inserted before absent hasCapacity

def ChartSound (workspace : LogicalWorkspace) : Prop :=
  ∀ position stateId, stateId ∈ workspace.chart position →
    ∃ state,
      workspace.state? stateId = some state ∧ state.position = position

def EveryStateCharted (workspace : LogicalWorkspace) : Prop :=
  ∀ stateId state, workspace.state? stateId = some state →
    stateId ∈ workspace.chart state.position

def UniqueKeys (workspace : LogicalWorkspace) : Prop :=
  ∀ position leftId rightId leftState rightState,
    leftId ∈ workspace.chart position →
    rightId ∈ workspace.chart position →
    workspace.state? leftId = some leftState →
    workspace.state? rightId = some rightState →
    leftState.key = rightState.key →
    leftId = rightId

def ChartIdsUnique (workspace : LogicalWorkspace) : Prop :=
  ∀ position, (workspace.chart position).Nodup

structure WorkspaceWellFormed (workspace : LogicalWorkspace) : Prop where
  chartSound : ChartSound workspace
  everyStateCharted : EveryStateCharted workspace
  uniqueKeys : UniqueKeys workspace
  chartIdsUnique : ChartIdsUnique workspace

/-- Grammar-domain facts carried by every recognizer state.  Memory safety of
    the workspace encoding alone does not justify indexing grammar tables;
    algorithm correctness additionally needs each production ID and dot to
    belong to the indexed grammar. -/
structure StateKeyWithinGrammar
    (grammar : IndexedGrammar) (key : StateKey) : Prop where
  productionBound : key.production < grammar.productionCount
  dotBound : key.dot ≤
    (grammar.productionAt ⟨key.production, productionBound⟩).rhs.length

def WorkspaceWithinGrammar
    (grammar : IndexedGrammar) (workspace : LogicalWorkspace) : Prop :=
  ∀ stateId state, workspace.state? stateId = some state →
    StateKeyWithinGrammar grammar state.key

theorem emptyWorkspace_wellFormed : WorkspaceWellFormed emptyWorkspace := by
  exact {
    chartSound := by simp [ChartSound]
    everyStateCharted := by simp [EveryStateCharted, LogicalWorkspace.state?]
    uniqueKeys := by simp [UniqueKeys]
    chartIdsUnique := by simp [ChartIdsUnique]
  }

theorem emptyWorkspace_withinGrammar (grammar : IndexedGrammar) :
    WorkspaceWithinGrammar grammar emptyWorkspace := by
  intro stateId state found
  simp [LogicalWorkspace.state?, emptyWorkspace] at found

theorem appendChart_same
    (chart : Nat → List Nat) (position stateId : Nat) :
    appendChart chart position stateId position =
      chart position ++ [stateId] := by
  simp [appendChart]

theorem appendChart_other
    (chart : Nat → List Nat) {position queried stateId : Nat}
    (different : queried ≠ position) :
    appendChart chart position stateId queried = chart queried := by
  simp [appendChart, different]

theorem insertState_count
    (workspace : LogicalWorkspace) (position : Nat) (seed : StateSeed) :
    (insertState workspace position seed).states.length =
      workspace.states.length + 1 := by
  simp [insertState]

theorem insertState_finds_new
    (workspace : LogicalWorkspace) (position : Nat) (seed : StateSeed) :
    (insertState workspace position seed).state? workspace.states.length =
      some (seed.atPosition position) := by
  simp [insertState, LogicalWorkspace.state?]

theorem insertState_preserves_old
    (workspace : LogicalWorkspace) (position : Nat) (seed : StateSeed)
    {stateId : Nat} (stateIdBound : stateId < workspace.states.length) :
    (insertState workspace position seed).state? stateId =
      workspace.state? stateId := by
  simp only [insertState, LogicalWorkspace.state?]
  exact List.getElem?_append_left stateIdBound

/-- Inserting one semantically justified seed preserves soundness of every
    workspace item. -/
theorem insertState_preserves_languageSound
    (sound : WorkspaceLanguageSound grammar tokens workspace)
    (seedSound : EarleyStateSound grammar tokens (seed.atPosition position)) :
    WorkspaceLanguageSound grammar tokens
      (insertState workspace position seed) := by
  intro stateId state found
  by_cases old : stateId < workspace.states.length
  · have oldFound : workspace.state? stateId = some state := by
      rw [← insertState_preserves_old workspace position seed old]
      exact found
    exact sound stateId state oldFound
  · have bound : stateId < (insertState workspace position seed).states.length :=
      List.getElem?_eq_some_iff.mp found |>.1
    rw [insertState_count] at bound
    have equal : stateId = workspace.states.length := by omega
    subst stateId
    rw [insertState_finds_new] at found
    injection found with stateEqual
    subst state
    exact seedSound

theorem insertState_preserves_withinGrammar
    (within : WorkspaceWithinGrammar grammar workspace)
    (seedWithin : StateKeyWithinGrammar grammar seed.key) :
    WorkspaceWithinGrammar grammar (insertState workspace position seed) := by
  intro stateId state found
  by_cases old : stateId < workspace.states.length
  · rw [insertState_preserves_old workspace position seed old] at found
    exact within stateId state found
  · have bound : stateId < (insertState workspace position seed).states.length := by
      unfold LogicalWorkspace.state? at found
      exact (List.getElem?_eq_some_iff.mp found).1
    rw [insertState_count] at bound
    have equal : stateId = workspace.states.length := by omega
    subst stateId
    rw [insertState_finds_new] at found
    injection found with stateEqual
    subst state
    simpa [EarleyState.key, StateSeed.key, StateSeed.atPosition] using
      seedWithin

theorem insertState_lists_new
    (workspace : LogicalWorkspace) (position : Nat) (seed : StateSeed) :
    workspace.states.length ∈
      (insertState workspace position seed).chart position := by
  simp [insertState, appendChart]

theorem getElem?_some_implies_bound
    {values : List α} {index : Nat} {value : α}
    (found : values[index]? = some value) : index < values.length := by
  exact (List.getElem?_eq_some_iff.mp found).1

theorem insertState_preserves_ChartSound
    (sound : ChartSound workspace) :
    ChartSound (insertState workspace position seed) := by
  intro queried stateId listed
  by_cases samePosition : queried = position
  · subst queried
    change stateId ∈
      appendChart workspace.chart position workspace.states.length position
      at listed
    rw [appendChart_same] at listed
    rcases List.mem_append.mp listed with old | new
    · obtain ⟨state, found, statePosition⟩ := sound position stateId old
      have stateIdBound := getElem?_some_implies_bound found
      exact ⟨state, insertState_preserves_old workspace position seed
        stateIdBound |>.trans found, statePosition⟩
    · simp only [List.mem_singleton] at new
      subst stateId
      exact ⟨seed.atPosition position,
        insertState_finds_new workspace position seed, rfl⟩
  · change stateId ∈
      appendChart workspace.chart position workspace.states.length queried
      at listed
    rw [appendChart_other workspace.chart samePosition] at listed
    obtain ⟨state, found, statePosition⟩ := sound queried stateId listed
    have stateIdBound := getElem?_some_implies_bound found
    exact ⟨state, insertState_preserves_old workspace position seed
      stateIdBound |>.trans found, statePosition⟩

theorem insertState_preserves_EveryStateCharted
    (charted : EveryStateCharted workspace) :
    EveryStateCharted (insertState workspace position seed) := by
  intro stateId state found
  by_cases old : stateId < workspace.states.length
  · have oldFound : workspace.state? stateId = some state := by
      rw [← insertState_preserves_old workspace position seed old]
      exact found
    have listed := charted stateId state oldFound
    by_cases samePosition : state.position = position
    · subst position
      change stateId ∈ appendChart workspace.chart state.position
        workspace.states.length state.position
      rw [appendChart_same]
      exact List.mem_append_left _ listed
    · change stateId ∈ appendChart workspace.chart position
        workspace.states.length state.position
      rw [appendChart_other workspace.chart samePosition]
      exact listed
  · have newId : stateId = workspace.states.length := by
      have upper : stateId < workspace.states.length + 1 := by
        rw [← insertState_count workspace position seed]
        exact getElem?_some_implies_bound found
      omega
    subst stateId
    rw [insertState_finds_new] at found
    injection found with stateEqual
    subst state
    exact insertState_lists_new workspace position seed

private theorem insertState_old_found_of_chart
    (sound : ChartSound workspace)
    {queried stateId : Nat} {state : EarleyState}
    (listed : stateId ∈ workspace.chart queried)
    (foundAfter :
      (insertState workspace position seed).state? stateId = some state) :
    workspace.state? stateId = some state := by
  obtain ⟨oldState, foundBefore, _⟩ := sound queried stateId listed
  have stateIdBound := getElem?_some_implies_bound foundBefore
  rw [insertState_preserves_old workspace position seed stateIdBound,
    foundBefore] at foundAfter
  injection foundAfter with stateEqual
  simpa [stateEqual] using foundBefore

theorem insertState_preserves_UniqueKeys
    (sound : ChartSound workspace)
    (unique : UniqueKeys workspace)
    (absent : ¬ workspace.containsKey position seed.key) :
    UniqueKeys (insertState workspace position seed) := by
  intro queried leftId rightId leftState rightState
    leftListed rightListed leftFound rightFound sameKey
  by_cases samePosition : queried = position
  · subst queried
    change leftId ∈ appendChart workspace.chart position
      workspace.states.length position at leftListed
    change rightId ∈ appendChart workspace.chart position
      workspace.states.length position at rightListed
    rw [appendChart_same] at leftListed rightListed
    rcases List.mem_append.mp leftListed with leftOld | leftNew
    · rcases List.mem_append.mp rightListed with rightOld | rightNew
      · have leftBefore := insertState_old_found_of_chart
          sound leftOld leftFound
        have rightBefore := insertState_old_found_of_chart
          sound rightOld rightFound
        exact unique position leftId rightId leftState rightState
          leftOld rightOld leftBefore rightBefore sameKey
      · simp only [List.mem_singleton] at rightNew
        subst rightId
        rw [insertState_finds_new] at rightFound
        injection rightFound with rightStateEqual
        subst rightState
        have leftBefore := insertState_old_found_of_chart
          sound leftOld leftFound
        exfalso
        apply absent
        exact ⟨leftId, leftState, leftOld, leftBefore, by simpa using sameKey⟩
    · simp only [List.mem_singleton] at leftNew
      subst leftId
      rcases List.mem_append.mp rightListed with rightOld | rightNew
      · rw [insertState_finds_new] at leftFound
        injection leftFound with leftStateEqual
        subst leftState
        have rightBefore := insertState_old_found_of_chart
          sound rightOld rightFound
        exfalso
        apply absent
        exact ⟨rightId, rightState, rightOld, rightBefore, by
          simpa using sameKey.symm⟩
      · simp only [List.mem_singleton] at rightNew
        exact rightNew.symm
  · change leftId ∈ appendChart workspace.chart position
      workspace.states.length queried at leftListed
    change rightId ∈ appendChart workspace.chart position
      workspace.states.length queried at rightListed
    rw [appendChart_other workspace.chart samePosition] at leftListed rightListed
    have leftBefore := insertState_old_found_of_chart
      sound leftListed leftFound
    have rightBefore := insertState_old_found_of_chart
      sound rightListed rightFound
    exact unique queried leftId rightId leftState rightState
      leftListed rightListed leftBefore rightBefore sameKey

theorem insertState_preserves_ChartIdsUnique
    (sound : ChartSound workspace)
    (uniqueIds : ChartIdsUnique workspace) :
    ChartIdsUnique (insertState workspace position seed) := by
  intro queried
  by_cases samePosition : queried = position
  · subst queried
    change (appendChart workspace.chart position workspace.states.length
      position).Nodup
    rw [appendChart_same]
    have newNotListed : workspace.states.length ∉ workspace.chart position := by
      intro listed
      obtain ⟨state, found, _⟩ := sound position workspace.states.length listed
      have bound := getElem?_some_implies_bound found
      omega
    apply List.nodup_append.mpr
    refine ⟨uniqueIds position, by simp, ?_⟩
    intro oldId oldListed newId newListed
    simp only [List.mem_singleton] at newListed
    subst newId
    intro equal
    subst oldId
    exact newNotListed oldListed
  · change (appendChart workspace.chart position workspace.states.length
      queried).Nodup
    rw [appendChart_other workspace.chart samePosition]
    exact uniqueIds queried

theorem Append.preserves_existing_states
    (appended : Append capacity position seed before outcome after)
    {stateId : Nat} (stateIdBound : stateId < before.states.length) :
    after.state? stateId = before.state? stateId := by
  cases appended with
  | existing => rfl
  | full => rfl
  | inserted => exact insertState_preserves_old before position seed stateIdBound

theorem Append.state_count
    (appended : Append capacity position seed before outcome after) :
    after.states.length = outcome.stateCount := by
  cases appended <;> simp [insertState_count]

theorem Append.count_change
    (appended : Append capacity position seed before outcome after) :
    after.states.length = before.states.length ∨
      after.states.length = before.states.length + 1 := by
  cases appended with
  | existing => exact .inl rfl
  | full => exact .inl rfl
  | inserted => exact .inr (insertState_count before position seed)

theorem Append.preserves_chart_sound
    (appended : Append capacity position seed before outcome after)
    (sound : ChartSound before) : ChartSound after := by
  cases appended with
  | existing => exact sound
  | full => exact sound
  | inserted => exact insertState_preserves_ChartSound sound

/-- The abstract append operation preserves declarative language soundness
    when the proposed new item is itself justified. Existing-key and
    capacity-full outcomes need no special reasoning because they leave the
    workspace unchanged. -/
theorem Append.preserves_languageSound
    (appended : Append capacity position seed before outcome after)
    (sound : WorkspaceLanguageSound grammar tokens before)
    (seedSound : EarleyStateSound grammar tokens (seed.atPosition position)) :
    WorkspaceLanguageSound grammar tokens after := by
  cases appended with
  | existing => exact sound
  | full => exact sound
  | inserted => exact insertState_preserves_languageSound sound seedSound

theorem Append.preserves_every_state_charted
    (appended : Append capacity position seed before outcome after)
    (charted : EveryStateCharted before) : EveryStateCharted after := by
  cases appended with
  | existing => exact charted
  | full => exact charted
  | inserted => exact insertState_preserves_EveryStateCharted charted

theorem Append.preserves_unique_keys
    (appended : Append capacity position seed before outcome after)
    (sound : ChartSound before) (unique : UniqueKeys before) :
    UniqueKeys after := by
  cases appended with
  | existing => exact unique
  | full => exact unique
  | inserted absent _ =>
      exact insertState_preserves_UniqueKeys sound unique absent

theorem Append.preserves_chart_ids_unique
    (appended : Append capacity position seed before outcome after)
    (sound : ChartSound before) (uniqueIds : ChartIdsUnique before) :
    ChartIdsUnique after := by
  cases appended with
  | existing => exact uniqueIds
  | full => exact uniqueIds
  | inserted => exact insertState_preserves_ChartIdsUnique sound uniqueIds

theorem Append.preserves_withinGrammar
    (appended : Append capacity position seed before outcome after)
    (within : WorkspaceWithinGrammar grammar before)
    (seedWithin : StateKeyWithinGrammar grammar seed.key) :
    WorkspaceWithinGrammar grammar after := by
  cases appended with
  | existing => exact within
  | full => exact within
  | inserted => exact insertState_preserves_withinGrammar within seedWithin

theorem Append.preserves_well_formed
    (appended : Append capacity position seed before outcome after)
    (wellFormed : WorkspaceWellFormed before) :
    WorkspaceWellFormed after := by
  exact {
    chartSound := appended.preserves_chart_sound wellFormed.chartSound
    everyStateCharted := appended.preserves_every_state_charted
      wellFormed.everyStateCharted
    uniqueKeys := appended.preserves_unique_keys
      wellFormed.chartSound wellFormed.uniqueKeys
    chartIdsUnique := appended.preserves_chart_ids_unique
      wellFormed.chartSound wellFormed.chartIdsUnique
  }

/-! ## Transitive workspace growth

The small recognizer loops return a logical workspace to an enclosing loop.
Merely returning a newly encoded workspace is not enough for that caller: it
must also know that all of its pre-existing states survived and that an equal
state count means no semantic insertion occurred.  `WorkspaceAppendClosure`
is the deliberately small certificate for that boundary.  It records only a
sequence of calls to the abstract `appendLogical` operation; no implementation
detail of the encoded workspace enters the relation. -/

inductive WorkspaceAppendClosure (capacity : Nat) :
    LogicalWorkspace → LogicalWorkspace → Prop where
  | refl (workspace : LogicalWorkspace) :
      WorkspaceAppendClosure capacity workspace workspace
  | append {before middle : LogicalWorkspace}
      (prior : WorkspaceAppendClosure capacity before middle)
      (position : Nat) (seed : StateSeed) :
      WorkspaceAppendClosure capacity before
        (appendLogical capacity position seed middle).2

theorem WorkspaceAppendClosure.single
    (capacity position : Nat) (seed : StateSeed)
    (before : LogicalWorkspace) :
    WorkspaceAppendClosure capacity before
      (appendLogical capacity position seed before).2 :=
  .append (.refl before) position seed

theorem WorkspaceAppendClosure.trans
    (left : WorkspaceAppendClosure capacity first middle)
    (right : WorkspaceAppendClosure capacity middle last) :
    WorkspaceAppendClosure capacity first last :=
  match right with
  | .refl _ => left
  | .append prior position seed =>
      .append (left.trans prior) position seed

theorem Append.after_eq_of_state_count_eq
    (appended : Append capacity position seed before outcome after)
    (sameCount : after.states.length = before.states.length) :
    after = before := by
  cases appended with
  | existing => rfl
  | full => rfl
  | inserted =>
      rw [insertState_count] at sameCount
      omega

theorem WorkspaceAppendClosure.state_count_le
    (growth : WorkspaceAppendClosure capacity before after) :
    before.states.length ≤ after.states.length := by
  induction growth with
  | refl => exact Nat.le_refl _
  | @append middle prior position seed =>
      rename_i priorLe
      let appended := appendLogical_refines
        (appendLogical capacity position seed middle) rfl
      rcases appended.count_change with same | increased
      · rw [same]
        exact priorLe
      · omega

/-- A sequence of abstract appends preserves the structural invariants of the
    logical parser workspace.  This turns the compact growth certificate into
    the well-formedness fact needed by callers without exposing individual
    recognizer-loop iterations. -/
theorem WorkspaceAppendClosure.preserves_well_formed
    (growth : WorkspaceAppendClosure capacity before after)
    (wellFormed : WorkspaceWellFormed before) :
    WorkspaceWellFormed after := by
  induction growth with
  | refl => exact wellFormed
  | @append middle prior position seed =>
      rename_i middleWellFormed
      let appended := appendLogical_refines
        (appendLogical capacity position seed middle) rfl
      exact appended.preserves_well_formed middleWellFormed

theorem WorkspaceAppendClosure.preserves_existing_state
    (growth : WorkspaceAppendClosure capacity before after)
    (found : before.state? stateId = some state) :
    after.state? stateId = some state := by
  induction growth with
  | refl => exact found
  | @append middle prior position seed =>
      rename_i preservesPrior
      have foundMiddle := preservesPrior
      have stateIdBound := getElem?_some_implies_bound foundMiddle
      let appended := appendLogical_refines
        (appendLogical capacity position seed middle) rfl
      exact (appended.preserves_existing_states stateIdBound).trans foundMiddle

theorem WorkspaceAppendClosure.eq_of_state_count_eq
    (growth : WorkspaceAppendClosure capacity before after)
    (sameCount : after.states.length = before.states.length) :
    after = before := by
  induction growth with
  | refl => rfl
  | @append middle prior position seed =>
      rename_i priorCountEqual
      let appended := appendLogical_refines
        (appendLogical capacity position seed middle) rfl
      have beforeLeMiddle := prior.state_count_le
      have middleLeAfter : middle.states.length ≤
          (appendLogical capacity position seed middle).2.states.length := by
        rcases appended.count_change with unchanged | increased
        · omega
        · omega
      have middleCount : middle.states.length = before.states.length := by
        omega
      have afterMiddleCount :
          (appendLogical capacity position seed middle).2.states.length =
            middle.states.length := by
        omega
      have middleEq : middle = before := priorCountEqual middleCount
      have afterEq :
          (appendLogical capacity position seed middle).2 = middle :=
        appended.after_eq_of_state_count_eq afterMiddleCount
      exact afterEq.trans middleEq

theorem WorkspaceAppendClosure.count_eq_or_lt
    (growth : WorkspaceAppendClosure capacity before after) :
    after.states.length = before.states.length ∨
      before.states.length < after.states.length := by
  have := growth.state_count_le
  omega

end Lanius.Compiler.Parser
