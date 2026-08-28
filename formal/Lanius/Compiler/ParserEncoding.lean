import Lanius.Compiler.ParserModel

namespace Lanius.Compiler.Parser

open Lanius.Semantics

/-! # Concrete parser-workspace encoding

The Lanius implementation represents charts as linked lists inside the same
word buffer as fixed-width state records.  This predicate connects that
representation to `LogicalWorkspace`; it is the pre/postcondition used when
proving extracted array reads and writes.
-/

abbrev Words := Nat → Int

def listWords (values : List Int) : Words :=
  fun address => values[address]?.getD 0

theorem listWords_get
    (values : List Int) (address : Nat) (bound : address < values.length) :
    listWords values address = values.get ⟨address, bound⟩ := by
  simp [listWords, List.getElem?_eq_getElem bound]

theorem listWords_set_same
    (values : List Int) (address : Nat) (value : Int)
    (bound : address < values.length) :
    listWords (setI32Value values address value) address = value := by
  simp [listWords, setI32Value, bound]

theorem listWords_set_other
    (values : List Int) {written queried : Nat} (value : Int)
    (different : queried ≠ written) :
    listWords (setI32Value values written value) queried =
      listWords values queried := by
  simp only [listWords, setI32Value]
  rw [List.getElem?_set_ne different.symm]

def writeWord (words : Words) (address : Nat) (value : Int) : Words :=
  fun queried => if queried = address then value else words queried

@[simp] theorem writeWord_same
    (words : Words) (address : Nat) (value : Int) :
    writeWord words address value address = value := by
  simp [writeWord]

theorem writeWord_other
    (words : Words) {written queried : Nat} (value : Int)
    (different : queried ≠ written) :
    writeWord words written value queried = words queried := by
  simp [writeWord, different]

theorem listWords_set_eq_writeWord
    (values : List Int) (address : Nat) (value : Int)
    (bound : address < values.length) :
    listWords (setI32Value values address value) =
      writeWord (listWords values) address value := by
  funext queried
  by_cases same : queried = address
  · subst queried
    rw [listWords_set_same values address value bound, writeWord_same]
  · rw [listWords_set_other values value same,
      writeWord_other (listWords values) value same]

def encodeStateId : Option Nat → Int
  | none => -1
  | some stateId => Int.ofNat stateId

def chartHeadValue (workspace : LogicalWorkspace) (position : Nat) : Int :=
  encodeStateId (workspace.chart position).head?

def chartTailValue (workspace : LogicalWorkspace) (position : Nat) : Int :=
  encodeStateId (workspace.chart position).getLast?

def nextAfter : List Nat → Nat → Option Nat
  | [], _ => none
  | current :: rest, stateId =>
      if current = stateId then rest.head? else nextAfter rest stateId

theorem nextAfter_append_new
    {states : List Nat} {newState : Nat}
    (fresh : newState ∉ states) :
    nextAfter (states ++ [newState]) newState = none := by
  induction states with
  | nil => simp [nextAfter]
  | cons head tail inductionHypothesis =>
      have headDifferent : head ≠ newState := by
        intro equal
        apply fresh
        simp [equal]
      have tailFresh : newState ∉ tail := by
        intro member
        exact fresh (List.mem_cons_of_mem head member)
      simp [nextAfter, headDifferent, inductionHypothesis tailFresh]

theorem nextAfter_append_of_found
    {states : List Nat} {stateId nextState newState : Nat}
    (found : nextAfter states stateId = some nextState) :
    nextAfter (states ++ [newState]) stateId = some nextState := by
  induction states with
  | nil => simp [nextAfter] at found
  | cons head tail inductionHypothesis =>
      by_cases current : head = stateId
      · subst head
        cases tail <;> simp [nextAfter] at found ⊢
        simpa using found
      · simp only [nextAfter, current, if_false] at found
        simpa only [List.cons_append, nextAfter, current, if_false] using
          inductionHypothesis found

theorem nextAfter_append_of_last
    {states : List Nat} {stateId newState : Nat}
    (listed : stateId ∈ states)
    (last : nextAfter states stateId = none) :
    nextAfter (states ++ [newState]) stateId = some newState := by
  induction states with
  | nil => simp at listed
  | cons head tail inductionHypothesis =>
      by_cases current : head = stateId
      · subst head
        cases tail <;> simp [nextAfter] at last ⊢
      · have listedTail : stateId ∈ tail := by
          rcases List.mem_cons.mp listed with equal | member
          · exact False.elim (current equal.symm)
          · exact member
        simp only [nextAfter, current, if_false] at last
        simpa only [List.cons_append, nextAfter, current, if_false] using
          inductionHypothesis listedTail last

theorem nextAfter_append_absent
    {states : List Nat} {stateId newState : Nat}
    (absent : stateId ∉ states) (different : stateId ≠ newState) :
    nextAfter (states ++ [newState]) stateId = none := by
  induction states with
  | nil => simp [nextAfter, different.symm]
  | cons head tail inductionHypothesis =>
      have current : head ≠ stateId := by
        intro equal
        apply absent
        simp [equal]
      have absentTail : stateId ∉ tail := by
        intro member
        exact absent (List.mem_cons_of_mem head member)
      simp [nextAfter, current, inductionHypothesis absentTail]

theorem nextAfter_append_cons_of_not_mem
    (visited suffix : List Nat) (current : Nat)
    (unseen : current ∉ visited) :
    nextAfter (visited ++ current :: suffix) current = suffix.head? := by
  induction visited with
  | nil => simp [nextAfter]
  | cons head tail inductionHypothesis =>
      have headDifferent : head ≠ current := by
        intro equal
        apply unseen
        simp [equal]
      have unseenTail : current ∉ tail := by
        intro listed
        exact unseen (List.mem_cons_of_mem head listed)
      simp [nextAfter, headDifferent, inductionHypothesis unseenTail]

/-- A cursor into a chart remembers the unvisited suffix.  Carrying the
    decomposition explicitly is what lets the concrete `STATE_NEXT` walk use
    suffix length as a termination measure. -/
structure ChartCursor (chart : List Nat) (current : Nat)
    (remaining : List Nat) where
  visited : List Nat
  split : chart = visited ++ current :: remaining
  unseen : current ∉ visited

def ChartCursor.atHead (current : Nat) (remaining : List Nat) :
    ChartCursor (current :: remaining) current remaining := by
  exact ⟨[], rfl, by simp⟩

def ChartCursor.next
    (cursor : ChartCursor chart current (nextState :: remaining))
    (unique : chart.Nodup) :
    ChartCursor chart nextState remaining := by
  refine ⟨cursor.visited ++ [current], ?_, ?_⟩
  · calc
      chart = cursor.visited ++ current :: nextState :: remaining :=
        cursor.split
      _ = (cursor.visited ++ [current]) ++ nextState :: remaining := by
        simp
  · have uniqueSplit :
        (cursor.visited ++ current :: nextState :: remaining).Nodup := by
        rw [← cursor.split]
        exact unique
    have suffixUnique : (current :: nextState :: remaining).Nodup :=
      (List.nodup_append.mp uniqueSplit).2.1
    have nextDifferent : nextState ≠ current := by
      intro equal
      have currentNotTail := (List.nodup_cons.mp suffixUnique).1
      apply currentNotTail
      simp [equal]
    have nextNotVisited : nextState ∉ cursor.visited := by
      intro listed
      have disjoint := (List.nodup_append.mp uniqueSplit).2.2
      exact (disjoint nextState listed nextState (by simp)) rfl
    simp [nextNotVisited, nextDifferent]

/-- Appending a state to the chart preserves an existing cursor and
    extends only its unvisited suffix.  Earley recognition relies on this law:
    a loop may append to the chart it is currently traversing, then discover
    the new state through the current tail's `next` link. -/
def ChartCursor.appendTail
    (cursor : ChartCursor chart current remaining) :
    ChartCursor (chart ++ [stateId]) current (remaining ++ [stateId]) := by
  refine ⟨cursor.visited, ?_, cursor.unseen⟩
  calc
    chart ++ [stateId] =
        (cursor.visited ++ current :: remaining) ++ [stateId] := by
          exact congrArg (fun values => values ++ [stateId]) cursor.split
    _ = cursor.visited ++ current :: (remaining ++ [stateId]) := by
          simp [List.append_assoc]

/-- An append at the chart being traversed either leaves the cursor suffix
    unchanged (deduplicated/full) or adds exactly the newly allocated state to
    its tail.  The second alternative records the corresponding state-count
    increase, which supplies the decreasing component for recognizer-loop
    termination. -/
theorem Append.preserves_chart_cursor
    (appended : Append capacity position seed before outcome after)
    (cursor : ChartCursor (before.chart position) current remaining) :
    Nonempty (ChartCursor (after.chart position) current remaining) ∨
      (Nonempty (ChartCursor (after.chart position) current
        (remaining ++ [before.states.length])) ∧
          after.states.length = before.states.length + 1) := by
  cases appended with
  | existing => exact .inl ⟨cursor⟩
  | full => exact .inl ⟨cursor⟩
  | inserted =>
      exact .inr ⟨⟨by
        simpa [insertState, appendChart] using
          (cursor.appendTail (stateId := before.states.length))⟩,
        insertState_count before position seed⟩

/-- Data-carrying counterpart of `preserves_chart_cursor`.  Execution proofs
    need the transported cursor itself, so a proposition-only disjunction is
    insufficient: Lean correctly forbids eliminating `Or` into the `Type`
    that stores the next loop invariant. -/
structure ChartCursorExtension
    (before after : LogicalWorkspace) (position current : Nat)
    (remaining : List Nat) where
  cursor : ChartCursor (after.chart position) current
    (remaining ++ [before.states.length])
  countIncreased : after.states.length = before.states.length + 1

structure ChartCursorUnchanged
    (before after : LogicalWorkspace) (position current : Nat)
    (remaining : List Nat) where
  cursor : ChartCursor (after.chart position) current remaining
  countUnchanged : after.states.length = before.states.length

def transportAppendLogicalCursor
    (capacity position : Nat) (seed : StateSeed)
    (before : LogicalWorkspace)
    (cursor : ChartCursor (before.chart position) current remaining) :
    ChartCursorUnchanged before (appendLogical capacity position seed before).2
      position current remaining ⊕
      ChartCursorExtension before
        (appendLogical capacity position seed before).2 position current
        remaining := by
  unfold appendLogical
  split
  · exact .inl ⟨cursor, rfl⟩
  · split
    · exact .inl ⟨cursor, rfl⟩
    · exact .inr ⟨by
        simpa [insertState, appendChart] using
          (cursor.appendTail (stateId := before.states.length)),
        insertState_count before position seed⟩

/-- Inserting into a different chart leaves the observed cursor suffix
    unchanged, although the global state count can still grow by one. -/
structure ChartCursorRemoteExtension
    (before after : LogicalWorkspace) (observed current : Nat)
    (remaining : List Nat) where
  cursor : ChartCursor (after.chart observed) current remaining
  countIncreased : after.states.length = before.states.length + 1

/-- Data-carrying transport for a cursor observing a chart other than the
    append target.  This is the parent-completion case: new states belong to
    the current parse-position chart, while the loop walks an origin chart. -/
def transportAppendLogicalOtherCursor
    (capacity target observed : Nat) (different : observed ≠ target)
    (seed : StateSeed) (before : LogicalWorkspace)
    (cursor : ChartCursor (before.chart observed) current remaining) :
    ChartCursorUnchanged before
        (appendLogical capacity target seed before).2 observed current
        remaining ⊕
      ChartCursorRemoteExtension before
        (appendLogical capacity target seed before).2 observed current
        remaining := by
  unfold appendLogical
  split
  · exact .inl ⟨cursor, rfl⟩
  · split
    · exact .inl ⟨cursor, rfl⟩
    · exact .inr ⟨by
        simpa [insertState, appendChart, different] using cursor,
        insertState_count before target seed⟩

theorem ChartCursor.nextAfter
    (cursor : ChartCursor chart current remaining) :
    nextAfter chart current = remaining.head? := by
  rw [cursor.split]
  exact nextAfter_append_cons_of_not_mem cursor.visited remaining current
    cursor.unseen

theorem nextAfter_eq_none_iff_getLast?_eq_some
    {states : List Nat} {stateId : Nat}
    (unique : states.Nodup) (listed : stateId ∈ states) :
    nextAfter states stateId = none ↔ states.getLast? = some stateId := by
  obtain ⟨visited, remaining, split⟩ := List.mem_iff_append.mp listed
  have uniqueSplit : (visited ++ stateId :: remaining).Nodup := by
    rw [← split]
    exact unique
  have unseen : stateId ∉ visited := by
    intro member
    have disjoint := (List.nodup_append.mp uniqueSplit).2.2
    exact (disjoint stateId member stateId (by simp)) rfl
  have remainingExcludes : stateId ∉ remaining := by
    have suffixUnique : (stateId :: remaining).Nodup :=
      (List.nodup_append.mp uniqueSplit).2.1
    exact (List.nodup_cons.mp suffixUnique).1
  let cursor : ChartCursor states stateId remaining :=
    ⟨visited, split, unseen⟩
  cases remaining with
  | nil =>
      rw [cursor.nextAfter]
      simp [split]
  | cons next rest =>
      have notLast : states.getLast? ≠ some stateId := by
        intro last
        have lastInSuffix : stateId ∈ next :: rest := by
          apply List.mem_of_getLast?
          have fromSplit := last
          rw [split, List.getLast?_append,
            List.getLast?_cons_of_ne_nil (by simp)] at fromSplit
          exact fromSplit
        exact remainingExcludes lastInSuffix
      rw [cursor.nextAfter]
      simp [notLast]

theorem ChartCursor.current_mem
    (cursor : ChartCursor chart current remaining) : current ∈ chart := by
  rw [cursor.split]
  simp

/-- Any member of a duplicate-free chart determines a cursor and its exact
    unvisited suffix.  This is used when an enclosing recognizer loop rebases
    itself after nested append operations have grown the workspace. -/
theorem existsChartCursor_of_mem
    (unique : chart.Nodup) (listed : current ∈ chart) :
    ∃ remaining, Nonempty (ChartCursor chart current remaining) := by
  obtain ⟨visited, remaining, split⟩ := List.mem_iff_append.mp listed
  have uniqueSplit : (visited ++ current :: remaining).Nodup := by
    rw [← split]
    exact unique
  have unseen : current ∉ visited := by
    intro member
    have disjoint := (List.nodup_append.mp uniqueSplit).2.2
    exact (disjoint current member current (by simp)) rfl
  exact ⟨remaining, ⟨visited, split, unseen⟩⟩

/-- Rebase a chart cursor after a sequence of semantic appends.  If the state
    count did not grow, the append closure proves that the whole workspace is
    unchanged and the original suffix is retained.  If it did grow, the old
    state is still present and well-formedness reconstructs a cursor in the
    enlarged chart.  This dichotomy is the termination contract needed by the
    enclosing state-chain loop. -/
theorem WorkspaceAppendClosure.rebase_chart_cursor
    (growth : WorkspaceAppendClosure capacity before after)
    (afterWellFormed : WorkspaceWellFormed after)
    (cursor : ChartCursor (before.chart position) current remaining)
    (found : before.state? current = some state)
    (atPosition : state.position = position) :
    (after.states.length = before.states.length ∧
      Nonempty (ChartCursor (after.chart position) current remaining)) ∨
    (before.states.length < after.states.length ∧
      ∃ nextRemaining,
        Nonempty (ChartCursor (after.chart position) current nextRemaining)) := by
  rcases growth.count_eq_or_lt with sameCount | increased
  · have sameWorkspace := growth.eq_of_state_count_eq sameCount
    subst after
    exact .inl ⟨rfl, ⟨cursor⟩⟩
  · have foundAfter := growth.preserves_existing_state found
    have listedAtState :=
      afterWellFormed.everyStateCharted current state foundAfter
    have listed : current ∈ after.chart position := by
      simpa [atPosition] using listedAtState
    exact .inr ⟨increased,
      existsChartCursor_of_mem (afterWellFormed.chartIdsUnique position) listed⟩

/-- A search cursor additionally records that every state already visited has
    a different key.  Consequently the global chart lookup is exactly the
    lookup over the current state and remaining suffix. -/
structure SearchCursor (workspace : LogicalWorkspace) (key : StateKey)
    (chart : List Nat) (current : Nat) (remaining : List Nat) where
  cursor : ChartCursor chart current remaining
  visitedDifferent : NoStateWithKey workspace key cursor.visited

def SearchCursor.atHead (workspace : LogicalWorkspace) (key : StateKey)
    (current : Nat) (remaining : List Nat) :
    SearchCursor workspace key (current :: remaining) current remaining :=
  ⟨ChartCursor.atHead current remaining, NoStateWithKey.nil⟩

def SearchCursor.next
    (search : SearchCursor workspace key chart current
      (nextState :: remaining))
    (unique : chart.Nodup)
    (currentDifferent : ∀ state,
      workspace.state? current = some state → state.key ≠ key) :
    SearchCursor workspace key chart nextState remaining := by
  let nextCursor := search.cursor.next unique
  refine ⟨nextCursor, ?_⟩
  exact search.visitedDifferent.append_singleton currentDifferent

theorem SearchCursor.restricts_find
    (search : SearchCursor workspace key chart current remaining) :
    findStateIn? workspace key chart =
      findStateIn? workspace key (current :: remaining) := by
  rw [search.cursor.split]
  exact findStateIn?_drop_no_matching_prefix search.visitedDifferent

def stateNextValue
    (workspace : LogicalWorkspace) (stateId : Nat) (state : EarleyState) : Int :=
  encodeStateId (nextAfter (workspace.chart state.position) stateId)

def previousValue (previous : Option Nat) : Int :=
  encodeStateId previous

def childTag : Child → Int
  | .none => 0
  | .token _ _ => 1
  | .state _ => 2

def childPayload : Child → Int
  | .none => -1
  | .token tokenIndex _ => Int.ofNat tokenIndex
  | .state stateId => Int.ofNat stateId

def childKind : Child → Int
  | .none => -1
  | .token _ semanticKind => Int.ofNat semanticKind
  | .state _ => -1

/-- The three-word key prefix shared by logical states and parser search
    seeds.  Keeping this projection explicit avoids duplicating field-number
    reasoning in extracted-function proofs. -/
def stateKeyFieldValue (key : StateKey) : Nat → Int
  | 0 => Int.ofNat key.production
  | 1 => Int.ofNat key.dot
  | 2 => Int.ofNat key.origin
  | _ => 0

def stateFieldValue (workspace : LogicalWorkspace)
    (stateId : Nat) (state : EarleyState) : Nat → Int
  | 0 => Int.ofNat state.production
  | 1 => Int.ofNat state.dot
  | 2 => Int.ofNat state.origin
  | 3 => Int.ofNat state.position
  | 4 => stateNextValue workspace stateId state
  | 5 => previousValue state.previous
  | 6 => childTag state.child
  | 7 => childPayload state.child
  | 8 => childKind state.child
  | _ => 0

abbrev WordWrite := Nat × Int

def applyWordWrites (values : List Int) (writes : List WordWrite) : List Int :=
  writes.foldl
    (fun current write => setI32Value current write.1 write.2) values

@[simp] theorem applyWordWrites_length
    (values : List Int) (writes : List WordWrite) :
    (applyWordWrites values writes).length = values.length := by
  induction writes generalizing values with
  | nil => simp [applyWordWrites]
  | cons write rest inductionHypothesis =>
      simp only [applyWordWrites, List.foldl_cons]
      change (applyWordWrites
        (setI32Value values write.1 write.2) rest).length = values.length
      rw [inductionHypothesis, setI32Value_length]

theorem listWords_applyWordWrites
    (values : List Int) (writes : List WordWrite)
    (bounded : ∀ write, write ∈ writes → write.1 < values.length) :
    listWords (applyWordWrites values writes) =
      writes.foldl
        (fun words write => writeWord words write.1 write.2)
        (listWords values) := by
  induction writes generalizing values with
  | nil => simp [applyWordWrites]
  | cons write rest inductionHypothesis =>
      simp only [applyWordWrites, List.foldl_cons]
      change listWords (applyWordWrites
          (setI32Value values write.1 write.2) rest) =
        List.foldl (fun words write => writeWord words write.1 write.2)
          (writeWord (listWords values) write.1 write.2) rest
      rw [inductionHypothesis]
      · rw [listWords_set_eq_writeWord values write.1 write.2
          (bounded write List.mem_cons_self)]
      · intro later laterMember
        simpa using bounded later (List.mem_cons_of_mem write laterMember)

theorem listWords_applyWordWrites_other
    (values : List Int) (writes : List WordWrite) (queried : Nat)
    (unwritten : ∀ write, write ∈ writes → queried ≠ write.1) :
    listWords (applyWordWrites values writes) queried =
      listWords values queried := by
  induction writes generalizing values with
  | nil => rfl
  | cons write rest inductionHypothesis =>
      simp only [applyWordWrites, List.foldl_cons]
      change listWords
          (applyWordWrites
            (setI32Value values write.1 write.2) rest) queried =
        listWords values queried
      rw [inductionHypothesis]
      · exact listWords_set_other values write.2
          (unwritten write List.mem_cons_self)
      · intro later listed
        exact unwritten later (List.mem_cons_of_mem write listed)

def insertedStateRecordWrites
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (position : Nat) (seed : StateSeed) : List WordWrite :=
  let base := stateBase layout.tokenCount
  let stateId := workspace.states.length
  [
    (stateWord base stateId 0, Int.ofNat seed.production),
    (stateWord base stateId 1, Int.ofNat seed.dot),
    (stateWord base stateId 2, Int.ofNat seed.origin),
    (stateWord base stateId 3, Int.ofNat position),
    (stateWord base stateId 4, -1),
    (stateWord base stateId 5, previousValue seed.previous),
    (stateWord base stateId 6, childTag seed.child),
    (stateWord base stateId 7, childPayload seed.child),
    (stateWord base stateId 8, childKind seed.child)
  ]

def insertedChartLinkWrites
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (position : Nat) : List WordWrite :=
  let stateId := workspace.states.length
  let link := match (workspace.chart position).getLast? with
    | none => (chartWord position 0, Int.ofNat stateId)
    | some tail =>
        (stateWord (stateBase layout.tokenCount) tail 4,
          Int.ofNat stateId)
  [link, (chartWord position 1, Int.ofNat stateId)]

def insertedWorkspaceWrites
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (position : Nat) (seed : StateSeed) : List WordWrite :=
  insertedStateRecordWrites layout workspace position seed ++
    insertedChartLinkWrites layout workspace position

def insertEncodedState
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (position : Nat) (seed : StateSeed) (values : List Int) : List Int :=
  applyWordWrites values
    (insertedWorkspaceWrites layout workspace position seed)

@[simp] theorem insertEncodedState_length
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (position : Nat) (seed : StateSeed) (values : List Int) :
    (insertEncodedState layout workspace position seed values).length =
      values.length := by
  simp [insertEncodedState]

theorem insertedWorkspaceWrites_count
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (position : Nat) (seed : StateSeed) :
    (insertedWorkspaceWrites layout workspace position seed).length = 11 := by
  simp [insertedWorkspaceWrites, insertedStateRecordWrites,
    insertedChartLinkWrites]

theorem stateFieldValue_eq_keyFieldValue
    (fieldBound : field < 3) :
    stateFieldValue workspace stateId state field =
      stateKeyFieldValue state.key field := by
  have cases : field = 0 ∨ field = 1 ∨ field = 2 := by omega
  rcases cases with equal | equal | equal <;> subst field <;> rfl

structure EncodesWorkspace
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (words : Words) : Prop where
  wellFormed : WorkspaceWellFormed workspace
  stateCountFits : workspace.states.length ≤ layout.capacity
  positionsBound : ∀ stateId state,
    workspace.state? stateId = some state →
    state.position ≤ finalPosition layout.tokenCount
  originsBound : ∀ stateId state,
    workspace.state? stateId = some state →
    state.origin ≤ finalPosition layout.tokenCount
  chartHead : ∀ position,
    position ≤ finalPosition layout.tokenCount →
    words (chartWord position 0) = chartHeadValue workspace position
  chartTail : ∀ position,
    position ≤ finalPosition layout.tokenCount →
    words (chartWord position 1) = chartTailValue workspace position
  stateField : ∀ stateId state,
    workspace.state? stateId = some state →
    ∀ field, field < stateWords →
      words (stateWord (stateBase layout.tokenCount) stateId field) =
        stateFieldValue workspace stateId state field

/-- A fully cleared chart prefix is exactly the concrete encoding of the
    empty semantic workspace. State-record words are irrelevant because the
    empty workspace contains no states. -/
theorem encodesEmptyWorkspace_of_cleared_chart
    (layout : WorkspaceLayout) (values : List Int)
    (cleared : ∀ address, address < stateBase layout.tokenCount →
      listWords values address = -1) :
    EncodesWorkspace layout emptyWorkspace (listWords values) := by
  exact {
    wellFormed := emptyWorkspace_wellFormed
    stateCountFits := by simp [emptyWorkspace]
    positionsBound := by simp [emptyWorkspace, LogicalWorkspace.state?]
    originsBound := by simp [emptyWorkspace, LogicalWorkspace.state?]
    chartHead := by
      intro position positionBound
      change listWords values (chartWord position 0) = -1
      exact cleared (chartWord position 0)
        (chartWord_lt_stateBase positionBound (by decide))
    chartTail := by
      intro position positionBound
      change listWords values (chartWord position 1) = -1
      exact cleared (chartWord position 1)
        (chartWord_lt_stateBase positionBound (by decide))
    stateField := by simp [emptyWorkspace, LogicalWorkspace.state?]
  }

theorem EncodesWorkspace.state_id_lt_capacity
    (encoded : EncodesWorkspace layout workspace words)
    (found : workspace.state? stateId = some state) :
    stateId < layout.capacity := by
  have stateIdBound := getElem?_some_implies_bound found
  exact Nat.lt_of_lt_of_le stateIdBound encoded.stateCountFits

theorem insertedStateRecordWrites_bounded
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (position : Nat) (seed : StateSeed)
    (hasCapacity : workspace.states.length < layout.capacity) :
    ∀ write, write ∈ insertedStateRecordWrites layout workspace position seed →
      write.1 < layout.workspaceLength := by
  intro write listed
  simp [insertedStateRecordWrites] at listed
  rcases listed with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl
  all_goals exact layout.state_address_valid hasCapacity (by decide)

theorem insertedStateRecordWrites_preserve_chart
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (position : Nat) (seed : StateSeed) (values : List Int)
    (queriedPosition queriedField : Nat)
    (queriedPositionBound : queriedPosition ≤ finalPosition layout.tokenCount)
    (queriedFieldBound : queriedField < chartWords) :
    listWords
        (applyWordWrites values
          (insertedStateRecordWrites layout workspace position seed))
        (chartWord queriedPosition queriedField) =
      listWords values (chartWord queriedPosition queriedField) := by
  apply listWords_applyWordWrites_other
  intro write listed
  simp [insertedStateRecordWrites] at listed
  rcases listed with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl
  all_goals simpa using
    (chart_state_words_disjoint queriedPositionBound queriedFieldBound)

theorem insertedChartLinkWrites_bounded
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (position : Nat) (encoded : EncodesWorkspace layout workspace words)
    (positionBound : position ≤ finalPosition layout.tokenCount) :
    ∀ write, write ∈ insertedChartLinkWrites layout workspace position →
      write.1 < layout.workspaceLength := by
  intro write listed
  cases tailFound : (workspace.chart position).getLast? with
  | none =>
      simp [insertedChartLinkWrites, tailFound] at listed
      rcases listed with rfl | rfl
      · exact layout.chart_address_valid positionBound (by decide)
      · exact layout.chart_address_valid positionBound (by decide)
  | some tail =>
      have tailListed : tail ∈ workspace.chart position :=
        List.mem_of_getLast? tailFound
      obtain ⟨state, stateFound, _⟩ :=
        encoded.wellFormed.chartSound position tail tailListed
      have tailBound : tail < layout.capacity :=
        encoded.state_id_lt_capacity stateFound
      simp [insertedChartLinkWrites, tailFound] at listed
      rcases listed with rfl | rfl
      · exact layout.state_address_valid tailBound (by decide)
      · exact layout.chart_address_valid positionBound (by decide)

theorem insertedWorkspaceWrites_bounded
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (position : Nat) (seed : StateSeed)
    (encoded : EncodesWorkspace layout workspace words)
    (positionBound : position ≤ finalPosition layout.tokenCount)
    (hasCapacity : workspace.states.length < layout.capacity) :
    ∀ write, write ∈ insertedWorkspaceWrites layout workspace position seed →
      write.1 < layout.workspaceLength := by
  intro write listed
  change write ∈
    insertedStateRecordWrites layout workspace position seed ++
      insertedChartLinkWrites layout workspace position at listed
  rcases List.mem_append.mp listed with stateWrite | chartWrite
  · exact insertedStateRecordWrites_bounded layout workspace position seed
      hasCapacity write stateWrite
  · exact insertedChartLinkWrites_bounded layout workspace position encoded
      positionBound write chartWrite

theorem insertEncodedState_new_state_field
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (position : Nat) (seed : StateSeed) (values : List Int)
    (valuesLength : values.length = layout.workspaceLength)
    (encoded : EncodesWorkspace layout workspace (listWords values))
    (positionBound : position ≤ finalPosition layout.tokenCount)
    (hasCapacity : workspace.states.length < layout.capacity)
    (field : Nat) (fieldBound : field < stateWords) :
    listWords (insertEncodedState layout workspace position seed values)
        (stateWord (stateBase layout.tokenCount) workspace.states.length field) =
      stateFieldValue (insertState workspace position seed)
        workspace.states.length (seed.atPosition position) field := by
  have bounded : ∀ write,
      write ∈ insertedWorkspaceWrites layout workspace position seed →
      write.1 < values.length := by
    intro write listed
    rw [valuesLength]
    exact insertedWorkspaceWrites_bounded layout workspace position seed
      encoded positionBound hasCapacity write listed
  rw [insertEncodedState,
    listWords_applyWordWrites values
      (insertedWorkspaceWrites layout workspace position seed) bounded]
  have headDisjoint (queriedField : Nat) :
      stateWord (stateBase layout.tokenCount) workspace.states.length
          queriedField ≠ chartWord position 0 :=
    (chart_state_words_disjoint positionBound (by decide)).symm
  have tailDisjoint (queriedField : Nat) :
      stateWord (stateBase layout.tokenCount) workspace.states.length
          queriedField ≠ chartWord position 1 :=
    (chart_state_words_disjoint positionBound (by decide)).symm
  have headAddressDifferent (queriedField : Nat) :
      stateBase layout.tokenCount +
          workspace.states.length * stateWords + queriedField ≠
        position * chartWords := by
    simpa [stateWord, chartWord] using headDisjoint queriedField
  have tailAddressDifferent (queriedField : Nat) :
      stateBase layout.tokenCount +
          workspace.states.length * stateWords + queriedField ≠
        position * chartWords + 1 := by
    simpa [stateWord, chartWord] using tailDisjoint queriedField
  have fresh : workspace.states.length ∉ workspace.chart position := by
    intro listed
    obtain ⟨state, found, _⟩ :=
      encoded.wellFormed.chartSound position workspace.states.length listed
    have bound := getElem?_some_implies_bound found
    omega
  have newNext :
      nextAfter (workspace.chart position ++ [workspace.states.length])
        workspace.states.length = none :=
    nextAfter_append_new fresh
  have fieldCases : field = 0 ∨ field = 1 ∨ field = 2 ∨ field = 3 ∨
      field = 4 ∨ field = 5 ∨ field = 6 ∨ field = 7 ∨ field = 8 := by
    simp only [stateWords] at fieldBound
    omega
  have headDifferent := headAddressDifferent field
  have tailDifferent := tailAddressDifferent field
  cases tailFound : (workspace.chart position).getLast? with
  | none =>
      rcases fieldCases with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl
      all_goals
        simp [insertedWorkspaceWrites, insertedStateRecordWrites,
          insertedChartLinkWrites, tailFound, writeWord, stateWord, chartWord,
          stateFieldValue, stateNextValue, insertState,
          appendChart, StateSeed.atPosition, encodeStateId,
          headDifferent, tailDifferent, newNext]
        all_goals omega
  | some tail =>
      have tailListed : tail ∈ workspace.chart position :=
        List.mem_of_getLast? tailFound
      obtain ⟨tailState, tailStateFound, _⟩ :=
        encoded.wellFormed.chartSound position tail tailListed
      have tailBound : tail < workspace.states.length :=
        getElem?_some_implies_bound tailStateFound
      have linkDisjoint :
          stateWord (stateBase layout.tokenCount) workspace.states.length
              field ≠
            stateWord (stateBase layout.tokenCount) tail 4 := by
        intro same
        have ids := stateWord_injective fieldBound
          (by decide : 4 < stateWords) same
        omega
      have linkDifferent :
          stateBase layout.tokenCount +
              workspace.states.length * stateWords + field ≠
            stateBase layout.tokenCount + tail * stateWords + 4 := by
        simpa [stateWord] using linkDisjoint
      rcases fieldCases with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl
      all_goals
        simp [insertedWorkspaceWrites, insertedStateRecordWrites,
          insertedChartLinkWrites, tailFound, writeWord, stateWord, chartWord,
          stateFieldValue, stateNextValue, insertState,
          appendChart, StateSeed.atPosition, encodeStateId,
          headDifferent, tailDifferent, linkDifferent, newNext]
        all_goals omega

theorem insertEncodedState_chart_head_at_position
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (position : Nat) (seed : StateSeed) (values : List Int)
    (valuesLength : values.length = layout.workspaceLength)
    (encoded : EncodesWorkspace layout workspace (listWords values))
    (positionBound : position ≤ finalPosition layout.tokenCount)
    (hasCapacity : workspace.states.length < layout.capacity) :
    listWords (insertEncodedState layout workspace position seed values)
        (chartWord position 0) =
      chartHeadValue (insertState workspace position seed) position := by
  have bounded : ∀ write,
      write ∈ insertedWorkspaceWrites layout workspace position seed →
      write.1 < values.length := by
    intro write listed
    rw [valuesLength]
    exact insertedWorkspaceWrites_bounded layout workspace position seed
      encoded positionBound hasCapacity write listed
  rw [insertEncodedState,
    listWords_applyWordWrites values
      (insertedWorkspaceWrites layout workspace position seed) bounded]
  have chartBefore : chartWord position 0 < stateBase layout.tokenCount :=
    chartWord_lt_stateBase positionBound (by decide)
  have stateDifferent (stateId field : Nat) :
      chartWord position 0 ≠
        stateWord (stateBase layout.tokenCount) stateId field :=
    chart_state_words_disjoint positionBound (by decide)
  have tailWordDifferent : chartWord position 0 ≠ chartWord position 1 := by
    intro same
    exact Nat.zero_ne_one
      (chartWord_injective (by decide) (by decide) same).2
  cases chart : workspace.chart position with
  | nil =>
      simp [insertedWorkspaceWrites, insertedStateRecordWrites,
        insertedChartLinkWrites, chart, writeWord,
        chartHeadValue, insertState, appendChart, encodeStateId,
        stateDifferent, tailWordDifferent]
  | cons head rest =>
      simp [insertedWorkspaceWrites, insertedStateRecordWrites,
        insertedChartLinkWrites, chart, writeWord,
        chartHeadValue, insertState, appendChart, encodeStateId,
        List.getLast?_cons, stateDifferent, tailWordDifferent,
        encoded.chartHead position positionBound]

theorem insertEncodedState_chart_tail_at_position
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (position : Nat) (seed : StateSeed) (values : List Int)
    (valuesLength : values.length = layout.workspaceLength)
    (encoded : EncodesWorkspace layout workspace (listWords values))
    (positionBound : position ≤ finalPosition layout.tokenCount)
    (hasCapacity : workspace.states.length < layout.capacity) :
    listWords (insertEncodedState layout workspace position seed values)
        (chartWord position 1) =
      chartTailValue (insertState workspace position seed) position := by
  have bounded : ∀ write,
      write ∈ insertedWorkspaceWrites layout workspace position seed →
      write.1 < values.length := by
    intro write listed
    rw [valuesLength]
    exact insertedWorkspaceWrites_bounded layout workspace position seed
      encoded positionBound hasCapacity write listed
  rw [insertEncodedState,
    listWords_applyWordWrites values
      (insertedWorkspaceWrites layout workspace position seed) bounded]
  have chartBefore : chartWord position 1 < stateBase layout.tokenCount :=
    chartWord_lt_stateBase positionBound (by decide)
  have stateDifferent (stateId field : Nat) :
      chartWord position 1 ≠
        stateWord (stateBase layout.tokenCount) stateId field :=
    chart_state_words_disjoint positionBound (by decide)
  have headWordDifferent : chartWord position 1 ≠ chartWord position 0 := by
    intro same
    exact Nat.one_ne_zero
      (chartWord_injective (by decide) (by decide) same).2
  cases tailFound : (workspace.chart position).getLast? with
  | none =>
      simp [insertedWorkspaceWrites, insertedStateRecordWrites,
        insertedChartLinkWrites, tailFound, writeWord,
        chartTailValue, insertState, appendChart, encodeStateId,
        stateDifferent, headWordDifferent]
  | some tail =>
      simp [insertedWorkspaceWrites, insertedStateRecordWrites,
        insertedChartLinkWrites, tailFound, writeWord,
        chartTailValue, insertState, appendChart, encodeStateId,
        stateDifferent, headWordDifferent]

theorem insertEncodedState_chart_other
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (position queried field : Nat) (seed : StateSeed) (values : List Int)
    (valuesLength : values.length = layout.workspaceLength)
    (encoded : EncodesWorkspace layout workspace (listWords values))
    (positionBound : position ≤ finalPosition layout.tokenCount)
    (queriedBound : queried ≤ finalPosition layout.tokenCount)
    (hasCapacity : workspace.states.length < layout.capacity)
    (different : queried ≠ position) (fieldBound : field < chartWords) :
    listWords (insertEncodedState layout workspace position seed values)
        (chartWord queried field) =
      listWords values (chartWord queried field) := by
  have bounded : ∀ write,
      write ∈ insertedWorkspaceWrites layout workspace position seed →
      write.1 < values.length := by
    intro write listed
    rw [valuesLength]
    exact insertedWorkspaceWrites_bounded layout workspace position seed
      encoded positionBound hasCapacity write listed
  rw [insertEncodedState,
    listWords_applyWordWrites values
      (insertedWorkspaceWrites layout workspace position seed) bounded]
  have stateDifferent (stateId stateField : Nat) :
      chartWord queried field ≠
        stateWord (stateBase layout.tokenCount) stateId stateField :=
    chart_state_words_disjoint queriedBound fieldBound
  have headDifferent : chartWord queried field ≠ chartWord position 0 := by
    intro same
    exact different (chartWord_injective fieldBound (by decide) same).1
  have tailDifferent : chartWord queried field ≠ chartWord position 1 := by
    intro same
    exact different (chartWord_injective fieldBound (by decide) same).1
  cases tailFound : (workspace.chart position).getLast? with
  | none =>
      simp [insertedWorkspaceWrites, insertedStateRecordWrites,
        insertedChartLinkWrites, tailFound, writeWord,
        stateDifferent, headDifferent, tailDifferent]
  | some tail =>
      simp [insertedWorkspaceWrites, insertedStateRecordWrites,
        insertedChartLinkWrites, tailFound, writeWord,
        stateDifferent, headDifferent, tailDifferent]

theorem stateFieldValue_insertState_old_of_not_tail
    (workspace : LogicalWorkspace) (position : Nat) (seed : StateSeed)
    (stateId field : Nat) (state : EarleyState)
    (wellFormed : WorkspaceWellFormed workspace)
    (found : workspace.state? stateId = some state)
    (notTail : (workspace.chart position).getLast? ≠ some stateId) :
    stateFieldValue (insertState workspace position seed) stateId state field =
      stateFieldValue workspace stateId state field := by
  have fieldCases : field = 0 ∨ field = 1 ∨ field = 2 ∨ field = 3 ∨
      field = 4 ∨ field = 5 ∨ field = 6 ∨ field = 7 ∨ field = 8 ∨
      9 ≤ field := by omega
  rcases fieldCases with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | large
  all_goals try rfl
  · simp only [stateFieldValue, stateNextValue]
    have listed := wellFormed.everyStateCharted stateId state found
    by_cases samePosition : state.position = position
    · subst position
      have unique := wellFormed.chartIdsUnique state.position
      have hasNext : nextAfter (workspace.chart state.position) stateId ≠ none := by
        intro missing
        exact notTail
          ((nextAfter_eq_none_iff_getLast?_eq_some unique listed).mp missing)
      cases nextFound : nextAfter (workspace.chart state.position) stateId with
      | none => exact False.elim (hasNext nextFound)
      | some nextState =>
          rw [show (insertState workspace state.position seed).chart
              state.position = workspace.chart state.position ++
                [workspace.states.length] by
            simp [insertState, appendChart]]
          rw [nextAfter_append_of_found nextFound]
    · rw [show (insertState workspace position seed).chart state.position =
          workspace.chart state.position by
        simp [insertState, appendChart, samePosition]]
  · simp [stateFieldValue, show field ≠ 0 by omega,
      show field ≠ 1 by omega, show field ≠ 2 by omega,
      show field ≠ 3 by omega, show field ≠ 4 by omega,
      show field ≠ 5 by omega, show field ≠ 6 by omega,
      show field ≠ 7 by omega, show field ≠ 8 by omega]

theorem stateFieldValue_insertState_old_of_not_next
    (workspace : LogicalWorkspace) (position : Nat) (seed : StateSeed)
    (stateId field : Nat) (state : EarleyState)
    (fieldBound : field < stateWords) (notNext : field ≠ 4) :
    stateFieldValue (insertState workspace position seed) stateId state field =
      stateFieldValue workspace stateId state field := by
  have cases : field = 0 ∨ field = 1 ∨ field = 2 ∨ field = 3 ∨
      field = 5 ∨ field = 6 ∨ field = 7 ∨ field = 8 := by
    simp only [stateWords] at fieldBound
    omega
  rcases cases with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;> rfl

theorem insertEncodedState_old_state_field_of_not_tail
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (position : Nat) (seed : StateSeed) (values : List Int)
    (encoded : EncodesWorkspace layout workspace (listWords values))
    (positionBound : position ≤ finalPosition layout.tokenCount)
    (hasCapacity : workspace.states.length < layout.capacity)
    (stateId field : Nat) (state : EarleyState)
    (found : workspace.state? stateId = some state)
    (fieldBound : field < stateWords)
    (notTail : (workspace.chart position).getLast? ≠ some stateId) :
    listWords (insertEncodedState layout workspace position seed values)
        (stateWord (stateBase layout.tokenCount) stateId field) =
      listWords values
        (stateWord (stateBase layout.tokenCount) stateId field) := by
  rw [insertEncodedState]
  apply listWords_applyWordWrites_other
  intro write listed
  have stateIdBound : stateId < workspace.states.length :=
    getElem?_some_implies_bound found
  have newStateDifferent (newField : Nat)
      (newFieldBound : newField < stateWords) :
      stateWord (stateBase layout.tokenCount) stateId field ≠
        stateWord (stateBase layout.tokenCount) workspace.states.length
          newField := by
    intro same
    have ids := stateWord_injective fieldBound newFieldBound same
    omega
  have chartDifferent (chartField : Nat)
      (chartFieldBound : chartField < chartWords) :
      stateWord (stateBase layout.tokenCount) stateId field ≠
        chartWord position chartField :=
    (chart_state_words_disjoint positionBound chartFieldBound).symm
  cases tailFound : (workspace.chart position).getLast? with
  | none =>
      simp [insertedWorkspaceWrites, insertedStateRecordWrites,
        insertedChartLinkWrites, tailFound] at listed
      rcases listed with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl
      · exact newStateDifferent 0 (by decide)
      · exact newStateDifferent 1 (by decide)
      · exact newStateDifferent 2 (by decide)
      · exact newStateDifferent 3 (by decide)
      · exact newStateDifferent 4 (by decide)
      · exact newStateDifferent 5 (by decide)
      · exact newStateDifferent 6 (by decide)
      · exact newStateDifferent 7 (by decide)
      · exact newStateDifferent 8 (by decide)
      · exact chartDifferent 0 (by decide)
      · exact chartDifferent 1 (by decide)
  | some tail =>
      have tailDifferent : stateId ≠ tail := by
        intro same
        subst tail
        exact notTail tailFound
      have linkDifferent :
          stateWord (stateBase layout.tokenCount) stateId field ≠
            stateWord (stateBase layout.tokenCount) tail 4 := by
        intro same
        exact tailDifferent
          (stateWord_injective fieldBound (by decide) same).1
      simp [insertedWorkspaceWrites, insertedStateRecordWrites,
        insertedChartLinkWrites, tailFound] at listed
      rcases listed with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl
      · exact newStateDifferent 0 (by decide)
      · exact newStateDifferent 1 (by decide)
      · exact newStateDifferent 2 (by decide)
      · exact newStateDifferent 3 (by decide)
      · exact newStateDifferent 4 (by decide)
      · exact newStateDifferent 5 (by decide)
      · exact newStateDifferent 6 (by decide)
      · exact newStateDifferent 7 (by decide)
      · exact newStateDifferent 8 (by decide)
      · exact linkDifferent
      · exact chartDifferent 1 (by decide)

theorem insertEncodedState_old_tail_next
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (position : Nat) (seed : StateSeed) (values : List Int)
    (valuesLength : values.length = layout.workspaceLength)
    (encoded : EncodesWorkspace layout workspace (listWords values))
    (positionBound : position ≤ finalPosition layout.tokenCount)
    (hasCapacity : workspace.states.length < layout.capacity)
    (stateId : Nat) (state : EarleyState)
    (found : workspace.state? stateId = some state)
    (tailFound : (workspace.chart position).getLast? = some stateId) :
    listWords (insertEncodedState layout workspace position seed values)
        (stateWord (stateBase layout.tokenCount) stateId 4) =
      Int.ofNat workspace.states.length := by
  have bounded : ∀ write,
      write ∈ insertedWorkspaceWrites layout workspace position seed →
      write.1 < values.length := by
    intro write listed
    rw [valuesLength]
    exact insertedWorkspaceWrites_bounded layout workspace position seed
      encoded positionBound hasCapacity write listed
  rw [insertEncodedState,
    listWords_applyWordWrites values
      (insertedWorkspaceWrites layout workspace position seed) bounded]
  have stateIdBound : stateId < workspace.states.length :=
    getElem?_some_implies_bound found
  have newStateDifferent (newField : Nat)
      (newFieldBound : newField < stateWords) :
      stateWord (stateBase layout.tokenCount) stateId 4 ≠
        stateWord (stateBase layout.tokenCount) workspace.states.length
          newField := by
    intro same
    have ids := stateWord_injective (by decide) newFieldBound same
    omega
  have chartDifferent (chartField : Nat)
      (chartFieldBound : chartField < chartWords) :
      stateWord (stateBase layout.tokenCount) stateId 4 ≠
        chartWord position chartField :=
    (chart_state_words_disjoint positionBound chartFieldBound).symm
  simp [insertedWorkspaceWrites, insertedStateRecordWrites,
    insertedChartLinkWrites, tailFound, writeWord,
    newStateDifferent, chartDifferent]

theorem stateFieldValue_insertState_old_tail_next
    (workspace : LogicalWorkspace) (position : Nat) (seed : StateSeed)
    (stateId : Nat) (state : EarleyState)
    (wellFormed : WorkspaceWellFormed workspace)
    (found : workspace.state? stateId = some state)
    (tailFound : (workspace.chart position).getLast? = some stateId) :
    stateFieldValue (insertState workspace position seed) stateId state 4 =
      Int.ofNat workspace.states.length := by
  have tailListed : stateId ∈ workspace.chart position :=
    List.mem_of_getLast? tailFound
  obtain ⟨chartedState, chartedFound, statePosition⟩ :=
    wellFormed.chartSound position stateId tailListed
  rw [found] at chartedFound
  injection chartedFound with sameState
  subst chartedState
  have oldNext : nextAfter (workspace.chart position) stateId = none :=
    (nextAfter_eq_none_iff_getLast?_eq_some
      (wellFormed.chartIdsUnique position) tailListed).mpr tailFound
  simp only [stateFieldValue, stateNextValue]
  rw [statePosition]
  rw [show (insertState workspace position seed).chart position =
      workspace.chart position ++ [workspace.states.length] by
    simp [insertState, appendChart]]
  rw [nextAfter_append_of_last tailListed oldNext]
  rfl

/-- The eleven concrete parser writes are exactly the logical insertion of
    one dense state and one chart link.  This is the representation theorem
    consumed by the extracted `append_state` execution proof. -/
theorem insertEncodedState_encodes
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (position : Nat) (seed : StateSeed) (values : List Int)
    (valuesLength : values.length = layout.workspaceLength)
    (encoded : EncodesWorkspace layout workspace (listWords values))
    (positionBound : position ≤ finalPosition layout.tokenCount)
    (seedOriginBound : seed.origin ≤ finalPosition layout.tokenCount)
    (hasCapacity : workspace.states.length < layout.capacity)
    (absent : ¬ workspace.containsKey position seed.key) :
    EncodesWorkspace layout (insertState workspace position seed)
      (listWords (insertEncodedState layout workspace position seed values)) := by
  let outcome : AppendOutcome := {
    status := .ok
    stateId := some workspace.states.length
    stateCount := workspace.states.length + 1
    inserted := true
  }
  have appended : Append layout.capacity position seed workspace outcome
      (insertState workspace position seed) :=
    .inserted workspace absent hasCapacity
  exact {
    wellFormed := appended.preserves_well_formed encoded.wellFormed
    stateCountFits := by
      rw [insertState_count]
      omega
    positionsBound := by
      intro stateId state foundAfter
      by_cases old : stateId < workspace.states.length
      · have foundBefore : workspace.state? stateId = some state := by
          rw [← insertState_preserves_old workspace position seed old]
          exact foundAfter
        exact encoded.positionsBound stateId state foundBefore
      · have upper : stateId < workspace.states.length + 1 := by
          rw [← insertState_count workspace position seed]
          exact getElem?_some_implies_bound foundAfter
        have newId : stateId = workspace.states.length := by omega
        subst stateId
        rw [insertState_finds_new] at foundAfter
        injection foundAfter with sameState
        subst state
        exact positionBound
    originsBound := by
      intro stateId state foundAfter
      by_cases old : stateId < workspace.states.length
      · have foundBefore : workspace.state? stateId = some state := by
          rw [← insertState_preserves_old workspace position seed old]
          exact foundAfter
        exact encoded.originsBound stateId state foundBefore
      · have upper : stateId < workspace.states.length + 1 := by
          rw [← insertState_count workspace position seed]
          exact getElem?_some_implies_bound foundAfter
        have newId : stateId = workspace.states.length := by omega
        subst stateId
        rw [insertState_finds_new] at foundAfter
        injection foundAfter with sameState
        subst state
        exact seedOriginBound
    chartHead := by
      intro queried queriedBound
      by_cases same : queried = position
      · subst queried
        exact insertEncodedState_chart_head_at_position layout workspace
          position seed values valuesLength encoded positionBound hasCapacity
      · calc
          listWords
                (insertEncodedState layout workspace position seed values)
                (chartWord queried 0) =
              listWords values (chartWord queried 0) :=
            insertEncodedState_chart_other layout workspace position queried 0
              seed values valuesLength encoded positionBound queriedBound
              hasCapacity same (by decide)
          _ = chartHeadValue workspace queried :=
            encoded.chartHead queried queriedBound
          _ = chartHeadValue (insertState workspace position seed) queried := by
            simp [chartHeadValue, insertState, appendChart, same]
    chartTail := by
      intro queried queriedBound
      by_cases same : queried = position
      · subst queried
        exact insertEncodedState_chart_tail_at_position layout workspace
          position seed values valuesLength encoded positionBound hasCapacity
      · calc
          listWords
                (insertEncodedState layout workspace position seed values)
                (chartWord queried 1) =
              listWords values (chartWord queried 1) :=
            insertEncodedState_chart_other layout workspace position queried 1
              seed values valuesLength encoded positionBound queriedBound
              hasCapacity same (by decide)
          _ = chartTailValue workspace queried :=
            encoded.chartTail queried queriedBound
          _ = chartTailValue (insertState workspace position seed) queried := by
            simp [chartTailValue, insertState, appendChart, same]
    stateField := by
      intro stateId state foundAfter field fieldBound
      by_cases old : stateId < workspace.states.length
      · have foundBefore : workspace.state? stateId = some state := by
          rw [← insertState_preserves_old workspace position seed old]
          exact foundAfter
        by_cases tail : (workspace.chart position).getLast? = some stateId
        · have fieldCases : field = 4 ∨ field ≠ 4 :=
            Decidable.em (field = 4)
          rcases fieldCases with rfl | notNext
          · calc
              listWords
                    (insertEncodedState layout workspace position seed values)
                    (stateWord (stateBase layout.tokenCount) stateId 4) =
                  Int.ofNat workspace.states.length :=
                insertEncodedState_old_tail_next layout workspace position seed
                  values valuesLength encoded positionBound hasCapacity stateId
                  state foundBefore tail
              _ = stateFieldValue (insertState workspace position seed)
                    stateId state 4 :=
                (stateFieldValue_insertState_old_tail_next workspace position
                  seed stateId state encoded.wellFormed foundBefore tail).symm
          · -- The state is the tail, but only field four is rewritten.
            have physical :
                listWords
                    (insertEncodedState layout workspace position seed values)
                    (stateWord (stateBase layout.tokenCount) stateId field) =
                  listWords values
                    (stateWord (stateBase layout.tokenCount) stateId field) := by
              rw [insertEncodedState]
              apply listWords_applyWordWrites_other
              intro write listed
              have newDifferent (newField : Nat)
                  (newFieldBound : newField < stateWords) :
                  stateWord (stateBase layout.tokenCount) stateId field ≠
                    stateWord (stateBase layout.tokenCount)
                      workspace.states.length newField := by
                intro equal
                have ids := stateWord_injective fieldBound newFieldBound equal
                omega
              have chartDifferent (chartField : Nat)
                  (chartFieldBound : chartField < chartWords) :
                  stateWord (stateBase layout.tokenCount) stateId field ≠
                    chartWord position chartField :=
                (chart_state_words_disjoint positionBound chartFieldBound).symm
              have linkDifferent :
                  stateWord (stateBase layout.tokenCount) stateId field ≠
                    stateWord (stateBase layout.tokenCount) stateId 4 := by
                intro equal
                exact notNext
                  (stateWord_injective fieldBound (by decide) equal).2
              simp [insertedWorkspaceWrites, insertedStateRecordWrites,
                insertedChartLinkWrites, tail] at listed
              rcases listed with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl
              · exact newDifferent 0 (by decide)
              · exact newDifferent 1 (by decide)
              · exact newDifferent 2 (by decide)
              · exact newDifferent 3 (by decide)
              · exact newDifferent 4 (by decide)
              · exact newDifferent 5 (by decide)
              · exact newDifferent 6 (by decide)
              · exact newDifferent 7 (by decide)
              · exact newDifferent 8 (by decide)
              · exact linkDifferent
              · exact chartDifferent 1 (by decide)
            calc
              listWords
                    (insertEncodedState layout workspace position seed values)
                    (stateWord (stateBase layout.tokenCount) stateId field) =
                  listWords values
                    (stateWord (stateBase layout.tokenCount) stateId field) :=
                physical
              _ = stateFieldValue workspace stateId state field :=
                encoded.stateField stateId state foundBefore field fieldBound
              _ = stateFieldValue (insertState workspace position seed)
                    stateId state field := by
                exact (stateFieldValue_insertState_old_of_not_next workspace
                  position seed stateId field state fieldBound notNext).symm
        · calc
            listWords
                  (insertEncodedState layout workspace position seed values)
                  (stateWord (stateBase layout.tokenCount) stateId field) =
                listWords values
                  (stateWord (stateBase layout.tokenCount) stateId field) :=
              insertEncodedState_old_state_field_of_not_tail layout workspace
                position seed values encoded positionBound hasCapacity stateId
                field state foundBefore fieldBound tail
            _ = stateFieldValue workspace stateId state field :=
              encoded.stateField stateId state foundBefore field fieldBound
            _ = stateFieldValue (insertState workspace position seed)
                  stateId state field :=
              (stateFieldValue_insertState_old_of_not_tail workspace position
                seed stateId field state encoded.wellFormed foundBefore tail).symm
      · have upper : stateId < workspace.states.length + 1 := by
          rw [← insertState_count workspace position seed]
          exact getElem?_some_implies_bound foundAfter
        have newId : stateId = workspace.states.length := by omega
        subst stateId
        rw [insertState_finds_new] at foundAfter
        injection foundAfter with sameState
        subst state
        exact insertEncodedState_new_state_field layout workspace position seed
          values valuesLength encoded positionBound hasCapacity field fieldBound
  }
theorem EncodesWorkspace.chart_address_valid
    (_encoded : EncodesWorkspace layout workspace words)
    (positionBound : position ≤ finalPosition layout.tokenCount)
    (fieldBound : field < chartWords) :
    chartWord position field < layout.workspaceLength :=
  layout.chart_address_valid positionBound fieldBound

theorem EncodesWorkspace.state_address_valid
    (encoded : EncodesWorkspace layout workspace words)
    (found : workspace.state? stateId = some state)
    (fieldBound : field < stateWords) :
    stateWord (stateBase layout.tokenCount) stateId field <
      layout.workspaceLength :=
  layout.state_address_valid (encoded.state_id_lt_capacity found) fieldBound

theorem EncodesWorkspace.state_position_valid
    (encoded : EncodesWorkspace layout workspace words)
    (found : workspace.state? stateId = some state) :
    state.position ≤ finalPosition layout.tokenCount :=
  encoded.positionsBound stateId state found

theorem EncodesWorkspace.state_next_at_cursor
    (encoded : EncodesWorkspace layout workspace words)
    (found : workspace.state? stateId = some state)
    (cursor : ChartCursor (workspace.chart state.position) stateId remaining) :
    words (stateWord (stateBase layout.tokenCount) stateId 4) =
      encodeStateId remaining.head? := by
  rw [encoded.stateField stateId state found 4 (by decide)]
  simp only [stateFieldValue, stateNextValue]
  rw [cursor.nextAfter]

theorem EncodesWorkspace.state_at_chart_cursor
    (encoded : EncodesWorkspace layout workspace words)
    (cursor : ChartCursor (workspace.chart position) stateId remaining) :
    ∃ state,
      workspace.state? stateId = some state ∧
      state.position = position :=
  encoded.wellFormed.chartSound position stateId cursor.current_mem

theorem EncodesWorkspace.state_key_at_chart_cursor
    (encoded : EncodesWorkspace layout workspace words)
    (cursor : ChartCursor (workspace.chart position) stateId remaining) :
    ∃ state,
      workspace.state? stateId = some state ∧
      state.position = position ∧
      words (stateWord (stateBase layout.tokenCount) stateId 0) =
        Int.ofNat state.production ∧
      words (stateWord (stateBase layout.tokenCount) stateId 1) =
        Int.ofNat state.dot ∧
      words (stateWord (stateBase layout.tokenCount) stateId 2) =
        Int.ofNat state.origin := by
  obtain ⟨state, found, statePosition⟩ :=
    encoded.state_at_chart_cursor cursor
  refine ⟨state, found, statePosition, ?_, ?_, ?_⟩
  · simpa [stateFieldValue] using
      encoded.stateField stateId state found 0 (by decide)
  · simpa [stateFieldValue] using
      encoded.stateField stateId state found 1 (by decide)
  · simpa [stateFieldValue] using
      encoded.stateField stateId state found 2 (by decide)

theorem EncodesWorkspace.chart_and_state_addresses_disjoint
    (_encoded : EncodesWorkspace layout workspace words)
    (stateFieldIndex : Nat)
    (positionBound : position ≤ finalPosition layout.tokenCount)
    (chartFieldBound : chartField < chartWords) :
    chartWord position chartField ≠
      stateWord (stateBase layout.tokenCount) stateId stateFieldIndex :=
  chart_state_words_disjoint positionBound chartFieldBound

@[simp] theorem chartHeadValue_empty
    (empty : workspace.chart position = []) :
    chartHeadValue workspace position = -1 := by
  simp [chartHeadValue, empty, encodeStateId]

@[simp] theorem chartTailValue_empty
    (empty : workspace.chart position = []) :
    chartTailValue workspace position = -1 := by
  simp [chartTailValue, empty, encodeStateId]

theorem insertState_chart_head
    (workspace : LogicalWorkspace) (position : Nat) (seed : StateSeed) :
    chartHeadValue (insertState workspace position seed) position =
      encodeStateId ((workspace.chart position ++
        [workspace.states.length]).head?) := by
  simp [chartHeadValue, insertState, appendChart]

theorem insertState_chart_tail
    (workspace : LogicalWorkspace) (position : Nat) (seed : StateSeed) :
    chartTailValue (insertState workspace position seed) position =
      Int.ofNat workspace.states.length := by
  simp [chartTailValue, insertState, appendChart, encodeStateId]

@[simp] theorem childTag_none : childTag .none = 0 := rfl
@[simp] theorem childPayload_none : childPayload .none = -1 := rfl
@[simp] theorem childKind_none : childKind .none = -1 := rfl

end Lanius.Compiler.Parser
