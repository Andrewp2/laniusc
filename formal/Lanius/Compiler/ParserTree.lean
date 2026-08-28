import Lanius.Compiler.ParserModel

namespace Lanius.Compiler.Parser

/-! # Materialized parser trees

The Earley recognizer stores a compact chain of state and token backpointers.
Those integers are an implementation representation, not a parse tree
specification. `ParseTree` is the representation-independent target for
materializing an accepted root. It deliberately contains only source grammar
production identities, source nonterminals, lattice spans, and terminal
leaves; chart positions, state IDs, and linked-list layout do not escape into
later compiler stages.

`ParseTreeRecognizesSymbol` checks a materialized tree against the same
declarative grammar semantics used to prove recognizer acceptance. The erasure
theorems at the end of this file ensure that a checked materialized tree cannot
recognize a different language from `RecognizesInput`.
-/

/-- A finite, runtime-representable derivation tree. Nonterminal nodes retain
    their source production and half-open token-lattice span. A terminal leaf
    retains the physical token it consumed and its semantic grammar kind; this
    distinguishes the two virtual `>` leaves produced from one physical `>>`
    token. -/
inductive ParseTree where
  | terminal (tokenIndex semanticKind : Nat)
  | nonterminal
      (productionId nonterminal start finish : Nat)
      (children : List ParseTree)
deriving Repr

mutual

  /-- A materialized tree checks as one grammar symbol over an exact lattice
      span. -/
  inductive ParseTreeRecognizesSymbol
      (grammar : IndexedGrammar) (tokens : List Nat) :
      ParseTree → Nat → Nat → Nat → Prop where
    | terminal
        (tokenIndexEq : tokenIndex = start / 2)
        (kindBound : semanticKind < grammar.grammar.n_kinds)
        (scanned : scanTerminal grammar tokens start semanticKind =
          some finish) :
        ParseTreeRecognizesSymbol grammar tokens
          (.terminal tokenIndex semanticKind) semanticKind start finish
    | nonterminal
        (nonterminalBound : nonterminal < grammar.grammar.n_nonterminals)
        (productionBound : productionId < grammar.productionCount)
        (lhs : (grammar.productionAt ⟨productionId, productionBound⟩).lhs =
          nonterminal)
        (childrenRecognize : ParseTreesRecognizeSequence grammar tokens
          children
          (grammar.productionAt ⟨productionId, productionBound⟩).rhs
          start finish) :
        ParseTreeRecognizesSymbol grammar tokens
          (.nonterminal productionId nonterminal start finish children)
          (grammar.grammar.n_kinds + nonterminal) start finish

  /-- Children check against a production right-hand side in source order,
      partitioning the parent node's span. -/
  inductive ParseTreesRecognizeSequence
      (grammar : IndexedGrammar) (tokens : List Nat) :
      List ParseTree → List Nat → Nat → Nat → Prop where
    | empty :
        ParseTreesRecognizeSequence grammar tokens [] [] position position
    | cons
        (head : ParseTreeRecognizesSymbol grammar tokens
          tree symbol start middle)
        (tail : ParseTreesRecognizeSequence grammar tokens
          trees symbols middle finish) :
        ParseTreesRecognizeSequence grammar tokens
          (tree :: trees) (symbol :: symbols) start finish

end

mutual

  /-- Forget the concrete tree while retaining its declarative grammar
      derivation. -/
  theorem ParseTreeRecognizesSymbol.toRecognizesSymbol
      (recognized : ParseTreeRecognizesSymbol grammar tokens
        tree symbol start finish) :
      RecognizesSymbol grammar tokens symbol start finish := by
    cases recognized with
    | terminal _ kindBound scanned =>
        exact .terminal kindBound scanned
    | nonterminal nonterminalBound productionBound lhs childrenRecognize =>
        exact .nonterminal nonterminalBound productionBound lhs
          childrenRecognize.toRecognizesSequence

  /-- Forget materialized children while retaining recognition of their
      production sequence. -/
  theorem ParseTreesRecognizeSequence.toRecognizesSequence
      (recognized : ParseTreesRecognizeSequence grammar tokens
        trees symbols start finish) :
      RecognizesSequence grammar tokens symbols start finish := by
    cases recognized with
    | empty => exact .empty
    | cons head tail =>
        exact .cons head.toRecognizesSymbol tail.toRecognizesSequence

end

/-- A checked materialized start tree recognizes the complete input. -/
structure MaterializedParse
    (grammar : IndexedGrammar) (tokens : List Nat) where
  tree : ParseTree
  recognizes : ParseTreeRecognizesSymbol grammar tokens tree
    (grammar.grammar.n_kinds + grammar.grammar.start_nonterminal)
    0 (finalPosition tokens.length)

theorem MaterializedParse.recognizesInput
    (parse : MaterializedParse grammar tokens) :
    RecognizesInput grammar tokens := by
  exact parse.recognizes.toRecognizesSymbol

theorem ParseTreesRecognizeSequence.append_symbol
    (recognizedPrefix : ParseTreesRecognizeSequence grammar tokens
      trees symbols start middle)
    (last : ParseTreeRecognizesSymbol grammar tokens
      tree symbol middle finish) :
    ParseTreesRecognizeSequence grammar tokens
      (trees ++ [tree]) (symbols ++ [symbol]) start finish :=
  match recognizedPrefix with
  | .empty => .cons last .empty
  | .cons head tail => .cons head (tail.append_symbol last)

/-! ## Backpointer boundary

The recognizer's compact workspace can be materialized without trusting an
unrelated parser only if every stored backpointer is locally justified. The
following judgment records that justification independently of the packed
nine-word state encoding. Requiring referenced state IDs to be smaller than
the current ID makes recursive materialization structurally well founded.
-/

/-- One stored Earley state is either a fresh item or is the exact advance of
    an earlier item over the token/child named by its backpointer. -/
inductive EarleyBackpointerStep
    (grammar : IndexedGrammar) (tokens : List Nat)
    (workspace : LogicalWorkspace) : Nat → EarleyState → Prop where
  | fresh
      (productionBound : production < grammar.productionCount) :
      EarleyBackpointerStep grammar tokens workspace stateId
        ((freshSeed production position).atPosition position)
  | terminal
      (previousFound : workspace.state? previousId = some previous)
      (previousBefore : previousId < stateId)
      (previousProductionBound :
        previous.production < grammar.productionCount)
      (symbolFound :
        (grammar.productionAt
          ⟨previous.production, previousProductionBound⟩).rhs[
            previous.dot]? = some semanticKind)
      (semanticKindBound : semanticKind < grammar.grammar.n_kinds)
      (scanned : scanTerminal grammar tokens previous.position semanticKind =
        some finish) :
      EarleyBackpointerStep grammar tokens workspace stateId
        ((previous.advanceSeed previousId
          (.token (previous.position / 2) semanticKind)).atPosition finish)
  | nonterminal
      (previousFound : workspace.state? previousId = some previous)
      (previousBefore : previousId < stateId)
      (childFound : workspace.state? childId = some child)
      (childBefore : childId < stateId)
      (previousProductionBound :
        previous.production < grammar.productionCount)
      (childProductionBound : child.production < grammar.productionCount)
      (symbolFound :
        (grammar.productionAt
          ⟨previous.production, previousProductionBound⟩).rhs[
            previous.dot]? =
          some (grammar.grammar.n_kinds +
            (grammar.productionAt
              ⟨child.production, childProductionBound⟩).lhs))
      (childLhsBound :
        (grammar.productionAt
          ⟨child.production, childProductionBound⟩).lhs <
            grammar.grammar.n_nonterminals)
      (childOrigin : child.origin = previous.position)
      (childComplete : child.dot =
        (grammar.productionAt
          ⟨child.production, childProductionBound⟩).rhs.length) :
      EarleyBackpointerStep grammar tokens workspace stateId
        ((previous.advanceSeed previousId (.state childId)).atPosition
          child.position)

/-- Every resident state has a locally valid, decreasing backpointer step. -/
def WorkspaceBackpointersSound
    (grammar : IndexedGrammar) (tokens : List Nat)
    (workspace : LogicalWorkspace) : Prop :=
  ∀ stateId state, workspace.state? stateId = some state →
    EarleyBackpointerStep grammar tokens workspace stateId state

/-- A state prefix has been reconstructed into source-order concrete children.
    The production bound is explicit so callers can use the same indexed
    grammar row already established by the recognizer. -/
def EarleyStateHasParsePrefix
    (grammar : IndexedGrammar) (tokens : List Nat) (state : EarleyState)
    (productionBound : state.production < grammar.productionCount) : Prop :=
  ∃ children, ParseTreesRecognizeSequence grammar tokens children
    (List.take state.dot
      (grammar.productionAt ⟨state.production, productionBound⟩).rhs)
    state.origin state.position

/-- Executable reconstruction of one state's source-order child prefix.
    `fuel` is independent of grammar recursion: valid backpointers always move
    to smaller dense state IDs, so `stateId + 1` is sufficient. -/
def materializeStatePrefix?
    (grammar : IndexedGrammar) (workspace : LogicalWorkspace) :
    Nat → Nat → Option (List ParseTree)
  | 0, _ => none
  | fuel + 1, stateId => do
      let state ← workspace.state? stateId
      match state.previous, state.child with
      | none, .none => some []
      | some previousId, .token tokenIndex semanticKind => do
          let precedingTrees ← materializeStatePrefix? grammar workspace fuel previousId
          some (precedingTrees ++ [.terminal tokenIndex semanticKind])
      | some previousId, .state childId => do
          let precedingTrees ← materializeStatePrefix? grammar workspace fuel previousId
          let child ← workspace.state? childId
          if childProductionBound : child.production < grammar.productionCount then
            let childProduction := grammar.productionAt
              ⟨child.production, childProductionBound⟩
            let childTrees ← materializeStatePrefix? grammar workspace fuel childId
            some (precedingTrees ++ [.nonterminal child.production childProduction.lhs
              child.origin child.position childTrees])
          else
            none
      | _, _ => none

/-- Executable root materialization. Shape checks are retained even though the
    verified recognizer already proves them, so this function is also safe to
    call on an arbitrary logical workspace. -/
def materializeRoot?
    (grammar : IndexedGrammar) (tokens : List Nat)
    (workspace : LogicalWorkspace) (rootState : Nat) : Option ParseTree := do
  let state ← workspace.state? rootState
  if productionBound : state.production < grammar.productionCount then
    let production := grammar.productionAt ⟨state.production, productionBound⟩
    if state.origin != 0 || production.lhs != grammar.grammar.start_nonterminal ||
        state.dot != production.rhs.length ||
        state.position != finalPosition tokens.length then
      none
    else
      let children ← materializeStatePrefix? grammar workspace
        (workspace.states.length + 1) rootState
      some (.nonterminal state.production production.lhs state.origin
        state.position children)
  else
    none

/-- The complete semantic contract retained for one recognizer workspace.
    Keeping the derivation meaning and its materializable representation in
    one object prevents parser phases from preserving one while silently
    dropping the other. -/
structure WorkspaceDerivations
    (grammar : IndexedGrammar) (tokens : List Nat)
    (workspace : LogicalWorkspace) : Prop where
  languageSound : WorkspaceLanguageSound grammar tokens workspace
  backpointersSound : WorkspaceBackpointersSound grammar tokens workspace

/-- Evidence required to append one proposed state. The declarative proof is
    useful immediately; the decreasing backpointer step is what lets later
    tree materialization recover that proof from the stored workspace. -/
structure EarleySeedDerivation
    (grammar : IndexedGrammar) (tokens : List Nat)
    (workspace : LogicalWorkspace) (position : Nat)
    (seed : StateSeed) : Prop where
  languageSound : EarleyStateSound grammar tokens (seed.atPosition position)
  backpointer : EarleyBackpointerStep grammar tokens workspace
    workspace.states.length (seed.atPosition position)

/-- Stable description of the stored item advanced by a later append. It
    deliberately omits the item's own backpointer payload; only the semantic
    fields copied into the new seed are fixed here. -/
structure StoredPredecessor
    (workspace : LogicalWorkspace) (stateId production dot origin position : Nat) :
    Type where
  state : EarleyState
  found : workspace.state? stateId = some state
  productionEq : state.production = production
  dotEq : state.dot = dot
  originEq : state.origin = origin
  positionEq : state.position = position

/-- Stable description of a completed child referenced by a nonterminal
    backpointer. -/
structure StoredCompletion
    (grammar : IndexedGrammar) (workspace : LogicalWorkspace)
    (stateId nonterminal origin position : Nat) : Type where
  state : EarleyState
  found : workspace.state? stateId = some state
  productionBound : state.production < grammar.productionCount
  lhs : (grammar.productionAt ⟨state.production, productionBound⟩).lhs =
    nonterminal
  complete : state.dot =
    (grammar.productionAt ⟨state.production, productionBound⟩).rhs.length
  originEq : state.origin = origin
  positionEq : state.position = position

def StoredPredecessor.transfer
    (stored : StoredPredecessor workspace stateId production dot origin position)
    (found : nextWorkspace.state? stateId = some stored.state) :
    StoredPredecessor nextWorkspace stateId production dot origin position := {
  state := stored.state
  found := found
  productionEq := stored.productionEq
  dotEq := stored.dotEq
  originEq := stored.originEq
  positionEq := stored.positionEq
}

def StoredCompletion.transfer
    (stored : StoredCompletion grammar workspace stateId nonterminal origin position)
    (found : nextWorkspace.state? stateId = some stored.state) :
    StoredCompletion grammar nextWorkspace stateId nonterminal origin position := {
  state := stored.state
  found := found
  productionBound := stored.productionBound
  lhs := stored.lhs
  complete := stored.complete
  originEq := stored.originEq
  positionEq := stored.positionEq
}

theorem emptyWorkspace_backpointersSound
    (grammar : IndexedGrammar) (tokens : List Nat) :
    WorkspaceBackpointersSound grammar tokens emptyWorkspace := by
  intro stateId state found
  simp [LogicalWorkspace.state?, emptyWorkspace] at found

theorem emptyWorkspace_derivations
    (grammar : IndexedGrammar) (tokens : List Nat) :
    WorkspaceDerivations grammar tokens emptyWorkspace := {
  languageSound := emptyWorkspace_languageSound grammar tokens
  backpointersSound := emptyWorkspace_backpointersSound grammar tokens
}

/-- Local backpointer validity plus language soundness of earlier workspace
    states reconstructs the declarative meaning of the current item. This is
    the induction step used by the forthcoming tree materializer proof. -/
theorem EarleyBackpointerStep.languageSound
    (step : EarleyBackpointerStep grammar tokens workspace stateId state)
    (workspaceSound : WorkspaceLanguageSound grammar tokens workspace) :
    EarleyStateSound grammar tokens state := by
  cases step with
  | fresh productionBound =>
      exact freshSeed_sound productionBound
  | terminal previousFound previousBefore previousProductionBound symbolFound
      semanticKindBound scanned =>
      rename_i previousId previous semanticKind finish
      have previousSound := workspaceSound _ _ previousFound
      have symbolFound' :
          (grammar.productionAt
            ⟨_, previousSound.productionBound⟩).rhs[previous.dot]? =
            some semanticKind := by
        simpa only using symbolFound
      exact previousSound.advance symbolFound'
        (.terminal semanticKindBound scanned) previousId
        (.token (previous.position / 2) semanticKind)
  | nonterminal previousFound previousBefore childFound childBefore
      previousProductionBound
      childProductionBound symbolFound childLhsBound childOrigin
      childComplete =>
      rename_i previousId previous childId child
      have previousSound := workspaceSound _ _ previousFound
      have childSound := workspaceSound _ _ childFound
      have symbolFound' :
          (grammar.productionAt
            ⟨_, previousSound.productionBound⟩).rhs[previous.dot]? =
            some (grammar.grammar.n_kinds +
              (grammar.productionAt
                ⟨child.production, childSound.productionBound⟩).lhs) := by
        simpa only using symbolFound
      have childLhsBound' :
          (grammar.productionAt
            ⟨child.production, childSound.productionBound⟩).lhs <
              grammar.grammar.n_nonterminals := by
        simpa only using childLhsBound
      have childComplete' : child.dot =
          (grammar.productionAt
            ⟨child.production, childSound.productionBound⟩).rhs.length := by
        simpa only using childComplete
      have recognizedChild := childSound.complete childLhsBound' childComplete'
      rw [childOrigin] at recognizedChild
      exact previousSound.advance symbolFound' recognizedChild previousId
        (.state childId)

/-- The executable walker succeeds with a checked prefix whenever its fuel is
    larger than the requested state ID. This is the extraction-facing form of
    `materializesState`: the tree data comes from computation, while the proof
    follows the same decreasing backpointers. -/
theorem WorkspaceBackpointersSound.materializeStatePrefix?_complete
    (sound : WorkspaceBackpointersSound grammar tokens workspace)
    (found : workspace.state? stateId = some state)
    (productionBound : state.production < grammar.productionCount)
    (fuelBound : stateId < fuel) :
    ∃ children,
      materializeStatePrefix? grammar workspace fuel stateId = some children ∧
      ParseTreesRecognizeSequence grammar tokens children
        (List.take state.dot
          (grammar.productionAt ⟨state.production, productionBound⟩).rhs)
        state.origin state.position := by
  induction stateId using Nat.strongRecOn generalizing state fuel with
  | ind stateId ih =>
      cases fuel with
      | zero => omega
      | succ remainingFuel =>
          have step := sound stateId state found
          cases step with
          | fresh freshProductionBound =>
              rename_i production position
              refine ⟨[], ?_, ?_⟩
              · simp [materializeStatePrefix?, found, freshSeed,
                  StateSeed.atPosition]
              · simpa [freshSeed, StateSeed.atPosition] using
                  (ParseTreesRecognizeSequence.empty
                    (grammar := grammar) (tokens := tokens)
                    (position := position))
          | terminal previousFound previousBefore previousProductionBound
              symbolFound semanticKindBound scanned =>
              rename_i previousId previous semanticKind finish
              obtain ⟨previousTrees, previousComputed, previousRecognize⟩ :=
                ih previousId previousBefore previousFound
                  previousProductionBound (fuel := remainingFuel) (by omega)
              have dotBound : previous.dot <
                  (grammar.productionAt
                    ⟨previous.production, previousProductionBound⟩).rhs.length :=
                List.getElem?_eq_some_iff.mp symbolFound |>.1
              have symbolEq :
                  (grammar.productionAt
                    ⟨previous.production, previousProductionBound⟩).rhs[
                      previous.dot] = semanticKind := by
                rw [List.getElem?_eq_getElem dotBound] at symbolFound
                exact Option.some.inj symbolFound
              let leaf := ParseTree.terminal (previous.position / 2) semanticKind
              refine ⟨previousTrees ++ [leaf], ?_, ?_⟩
              · simp [materializeStatePrefix?, found, previousComputed,
                  EarleyState.advanceSeed, StateSeed.atPosition, leaf]
              · have leafRecognizes : ParseTreeRecognizesSymbol grammar tokens
                    leaf semanticKind previous.position finish :=
                  .terminal rfl semanticKindBound scanned
                have appended := previousRecognize.append_symbol leafRecognizes
                change ParseTreesRecognizeSequence grammar tokens
                  (previousTrees ++ [leaf])
                  (List.take (previous.dot + 1)
                    (grammar.productionAt
                      ⟨previous.production, previousProductionBound⟩).rhs)
                  previous.origin finish
                rw [List.take_succ_eq_append_getElem dotBound]
                simpa only [symbolEq] using appended
          | nonterminal previousFound previousBefore childFound childBefore
              previousProductionBound childProductionBound symbolFound
              childLhsBound childOrigin childComplete =>
              rename_i previousId previous childId child
              obtain ⟨previousTrees, previousComputed, previousRecognize⟩ :=
                ih previousId previousBefore previousFound
                  previousProductionBound (fuel := remainingFuel) (by omega)
              obtain ⟨childTrees, childComputed, childRecognize⟩ :=
                ih childId childBefore childFound childProductionBound
                  (fuel := remainingFuel) (by omega)
              have previousDotBound : previous.dot <
                  (grammar.productionAt
                    ⟨previous.production, previousProductionBound⟩).rhs.length :=
                List.getElem?_eq_some_iff.mp symbolFound |>.1
              have symbolEq :
                  (grammar.productionAt
                    ⟨previous.production, previousProductionBound⟩).rhs[
                      previous.dot] =
                    grammar.grammar.n_kinds +
                      (grammar.productionAt
                        ⟨child.production, childProductionBound⟩).lhs := by
                rw [List.getElem?_eq_getElem previousDotBound] at symbolFound
                exact Option.some.inj symbolFound
              have childCompleteRecognize : ParseTreesRecognizeSequence
                  grammar tokens childTrees
                  (grammar.productionAt
                    ⟨child.production, childProductionBound⟩).rhs
                  child.origin child.position := by
                simpa [childComplete] using childRecognize
              let childTree := ParseTree.nonterminal child.production
                (grammar.productionAt
                  ⟨child.production, childProductionBound⟩).lhs
                child.origin child.position childTrees
              refine ⟨previousTrees ++ [childTree], ?_, ?_⟩
              · simp [materializeStatePrefix?, found, previousComputed,
                  childFound, childProductionBound, childComputed,
                  EarleyState.advanceSeed, StateSeed.atPosition, childTree]
              · have childTreeRecognizes : ParseTreeRecognizesSymbol grammar tokens
                    childTree
                    (grammar.grammar.n_kinds +
                      (grammar.productionAt
                        ⟨child.production, childProductionBound⟩).lhs)
                    child.origin child.position :=
                  .nonterminal childLhsBound childProductionBound rfl
                    childCompleteRecognize
                have childAtPrevious : ParseTreeRecognizesSymbol grammar tokens
                    childTree
                    (grammar.grammar.n_kinds +
                      (grammar.productionAt
                        ⟨child.production, childProductionBound⟩).lhs)
                    previous.position child.position := by
                  simpa [childOrigin] using childTreeRecognizes
                have appended := previousRecognize.append_symbol childAtPrevious
                change ParseTreesRecognizeSequence grammar tokens
                  (previousTrees ++ [childTree])
                  (List.take (previous.dot + 1)
                    (grammar.productionAt
                      ⟨previous.production, previousProductionBound⟩).rhs)
                  previous.origin child.position
                rw [List.take_succ_eq_append_getElem previousDotBound]
                simpa only [symbolEq] using appended
/-- Decreasing backpointers reconstruct the exact concrete child prefix of
    every stored Earley item. This existential interface is retained for
    proof clients; its witness is produced by the executable walker above. -/
theorem WorkspaceBackpointersSound.materializesState
    (sound : WorkspaceBackpointersSound grammar tokens workspace)
    (found : workspace.state? stateId = some state)
    (productionBound : state.production < grammar.productionCount) :
    EarleyStateHasParsePrefix grammar tokens state productionBound := by
  obtain ⟨children, _, recognized⟩ :=
    sound.materializeStatePrefix?_complete found productionBound
      (fuel := stateId + 1) (by omega)
  exact ⟨children, recognized⟩

theorem WorkspaceBackpointersSound.materializeStatePrefix?_recognizes
    (sound : WorkspaceBackpointersSound grammar tokens workspace)
    (found : workspace.state? stateId = some state)
    (productionBound : state.production < grammar.productionCount)
    (fuelBound : stateId < fuel) :
    ParseTreesRecognizeSequence grammar tokens
      ((materializeStatePrefix? grammar workspace fuel stateId).getD [])
      (List.take state.dot
        (grammar.productionAt ⟨state.production, productionBound⟩).rhs)
      state.origin state.position := by
  obtain ⟨children, computed, recognized⟩ :=
    sound.materializeStatePrefix?_complete found productionBound fuelBound
  simpa [computed] using recognized

/-- A complete stored start item yields a checked parse tree, not merely an
    existential language-recognition fact. -/
def WorkspaceBackpointersSound.materializeStart
    (sound : WorkspaceBackpointersSound grammar tokens workspace)
    (grammarWellFormed : grammar.WellFormed)
    (found : workspace.state? rootState = some state)
    (productionBound : state.production < grammar.productionCount)
    (origin : state.origin = 0)
    (lhs : (grammar.productionAt ⟨state.production, productionBound⟩).lhs =
      grammar.grammar.start_nonterminal)
    (complete : state.dot =
      (grammar.productionAt ⟨state.production, productionBound⟩).rhs.length)
    (finish : state.position = finalPosition tokens.length) :
    MaterializedParse grammar tokens := by
  let fuel := workspace.states.length + 1
  let children := (materializeStatePrefix? grammar workspace fuel rootState).getD []
  have rootBound : rootState < fuel := by
    have storedBound := List.getElem?_eq_some_iff.mp found |>.1
    simp only [fuel]
    omega
  have childrenComplete : ParseTreesRecognizeSequence grammar tokens children
      (grammar.productionAt ⟨state.production, productionBound⟩).rhs
      0 (finalPosition tokens.length) := by
    simpa [children, complete, origin, finish] using
      sound.materializeStatePrefix?_recognizes found productionBound rootBound
  exact {
    tree := .nonterminal state.production grammar.grammar.start_nonterminal
      0 (finalPosition tokens.length) children
    recognizes := .nonterminal grammarWellFormed.startInBounds productionBound
      lhs childrenComplete
  }

theorem WorkspaceBackpointersSound.materializeRoot?_eq_some
    (sound : WorkspaceBackpointersSound grammar tokens workspace)
    (grammarWellFormed : grammar.WellFormed)
    (found : workspace.state? rootState = some state)
    (productionBound : state.production < grammar.productionCount)
    (origin : state.origin = 0)
    (lhs : (grammar.productionAt ⟨state.production, productionBound⟩).lhs =
      grammar.grammar.start_nonterminal)
    (complete : state.dot =
      (grammar.productionAt ⟨state.production, productionBound⟩).rhs.length)
    (finish : state.position = finalPosition tokens.length) :
    materializeRoot? grammar tokens workspace rootState = some
      (sound.materializeStart grammarWellFormed found productionBound origin lhs
        complete finish).tree := by
  have rootBound : rootState < workspace.states.length + 1 := by
    have storedBound := List.getElem?_eq_some_iff.mp found |>.1
    omega
  obtain ⟨children, computed, _⟩ :=
    sound.materializeStatePrefix?_complete found productionBound rootBound
  simp [materializeRoot?, found, productionBound, origin, lhs, complete, finish,
    WorkspaceBackpointersSound.materializeStart, computed]

/-- Extending the dense state list by one entry preserves a backpointer step
    whose current ID was already allocated or is exactly the new ID. All
    referenced IDs are strictly smaller and therefore remain in the old
    prefix. -/
theorem EarleyBackpointerStep.afterInsert
    (step : EarleyBackpointerStep grammar tokens workspace stateId state)
    (stateIdBound : stateId ≤ workspace.states.length) :
    EarleyBackpointerStep grammar tokens
      (insertState workspace position seed) stateId state := by
  cases step with
  | fresh productionBound =>
      exact .fresh productionBound
  | terminal previousFound previousBefore previousProductionBound symbolFound
      semanticKindBound scanned =>
      rename_i previousId previous semanticKind finish
      have previousBound : previousId < workspace.states.length := by omega
      exact .terminal
        ((insertState_preserves_old workspace position seed previousBound).trans
          previousFound)
        previousBefore previousProductionBound symbolFound semanticKindBound
        scanned
  | nonterminal previousFound previousBefore childFound childBefore
      previousProductionBound childProductionBound symbolFound childLhsBound
      childOrigin childComplete =>
      rename_i previousId previous childId child
      have previousBound : previousId < workspace.states.length := by omega
      have childBound : childId < workspace.states.length := by omega
      exact .nonterminal
        ((insertState_preserves_old workspace position seed previousBound).trans
          previousFound)
        previousBefore
        ((insertState_preserves_old workspace position seed childBound).trans
          childFound)
        childBefore previousProductionBound childProductionBound symbolFound
        childLhsBound childOrigin childComplete

/-- Inserting one locally justified seed preserves the decreasing-backpointer
    invariant for the complete workspace. -/
theorem insertState_preserves_backpointers
    (sound : WorkspaceBackpointersSound grammar tokens workspace)
    (seedStep : EarleyBackpointerStep grammar tokens workspace
      workspace.states.length (seed.atPosition position)) :
    WorkspaceBackpointersSound grammar tokens
      (insertState workspace position seed) := by
  intro stateId state found
  by_cases old : stateId < workspace.states.length
  · have oldFound : workspace.state? stateId = some state := by
      rw [← insertState_preserves_old workspace position seed old]
      exact found
    exact (sound stateId state oldFound).afterInsert (Nat.le_of_lt old)
  · have bound :
        stateId < (insertState workspace position seed).states.length :=
      List.getElem?_eq_some_iff.mp found |>.1
    rw [insertState_count] at bound
    have equal : stateId = workspace.states.length := by omega
    subst stateId
    rw [insertState_finds_new] at found
    injection found with stateEqual
    subst state
    exact seedStep.afterInsert (Nat.le_refl _)

/-- Abstract append preserves backpointer validity. Existing-key and capacity
    exhaustion outcomes do not mutate the workspace. -/
theorem Append.preserves_backpointers
    (appended : Append capacity position seed before outcome after)
    (sound : WorkspaceBackpointersSound grammar tokens before)
    (seedStep : EarleyBackpointerStep grammar tokens before
      before.states.length (seed.atPosition position)) :
    WorkspaceBackpointersSound grammar tokens after := by
  cases appended with
  | existing => exact sound
  | full => exact sound
  | inserted => exact insertState_preserves_backpointers sound seedStep

/-- Append preserves the complete workspace derivation contract as one unit. -/
theorem Append.preserves_derivations
    (appended : Append capacity position seed before outcome after)
    (derivations : WorkspaceDerivations grammar tokens before)
    (seedDerivation : EarleySeedDerivation grammar tokens before position seed) :
    WorkspaceDerivations grammar tokens after := {
  languageSound := appended.preserves_languageSound
    derivations.languageSound seedDerivation.languageSound
  backpointersSound := appended.preserves_backpointers
    derivations.backpointersSound seedDerivation.backpointer
}

end Lanius.Compiler.Parser
