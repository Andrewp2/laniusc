import Lanius.Extraction.ParseChecker

namespace Lanius.Extraction.ParsePostorder

/-! A postorder checker consumes completed children from a stack instead of
looking them up again in the global node index. Its acceptance is stricter
than the general DAG checker; soundness preserves the latter's contract. -/

abbrev Entry := Nat × ParseNode

def children (grammar : Grammar) (view : ParseArtifactView artifact)
    (current : Nat) : List Nat → List ParseChild → Nat → List Entry → Option Nat
  | [], [], position, [] => some position
  | symbol :: symbols, child :: rest, position, entries =>
    if symbol < grammar.n_kinds then
      match child with
      | .node _ => none
      | .token token => do
        if token != position / 2 then none else do
          let next ← advanceTerminalParseView view position symbol
          children grammar view current symbols rest next entries
    else
      if symbol - grammar.n_kinds >= grammar.n_nonterminals then none else
      match child with
      | .token _ => none
      | .node id =>
        match entries with
        | [] => none
        | entry :: entries =>
          if id >= current || id != entry.1 ||
              entry.2.nonterminal != symbol - grammar.n_kinds ||
              entry.2.position_start != position then none else
            children grammar view current symbols rest entry.2.position_end entries
  | _, _, _, _ => none

def node (grammar : Grammar) (view : ParseArtifactView artifact)
    (id : Nat) : ParseNode → List Entry → Bool
  | ⟨productionId, nonterminal, start, finish, values⟩, entries =>
    match grammar.production? productionId with
    | none => false
    | some production =>
      nonterminal = production.lhs && start ≤ finish &&
      finish ≤ view.semanticKinds.size * 2 &&
      children grammar view id production.rhs values start entries = some finish

def childCount (value : ParseNode) : Nat :=
  value.children.countP fun child => match child with
    | .node _ => true
    | .token _ => false

def check (grammar : Grammar) (view : ParseArtifactView artifact) :
    Nat → List ParseNode → List Entry → Bool
  | _, [], _ => true
  | id, value :: rest, stack =>
    let count := childCount value
    node grammar view id value (stack.take count).reverse &&
      check grammar view (id + 1) rest ((id, value) :: stack.drop count)

def EntriesValid (view : ParseArtifactView artifact) (entries : List Entry) : Prop :=
  ∀ entry ∈ entries, view.artifactView.node? entry.1 = some entry.2

theorem children_sound (grammar : Grammar) (view : ParseArtifactView artifact)
    (current : Nat) (symbols : List Nat) (values : List ParseChild)
    (position finish : Nat) (entries : List Entry)
    (valid : EntriesValid view entries)
    (accepted : children grammar view current symbols values position entries = some finish) :
    checkChildrenParseView grammar artifact view current symbols values position = some finish := by
  induction symbols generalizing values position entries with
  | nil =>
    cases values <;> cases entries <;> simp_all [children, checkChildrenParseView]
  | cons symbol symbols ih =>
    cases values with
    | nil => simp [children] at accepted
    | cons value values =>
      cases value with
      | token token =>
        simp only [children] at accepted
        split at accepted
        · rename_i terminal
          simp only [checkChildrenParseView, if_pos terminal]
          split at accepted
          · simp at accepted
          · rename_i tokenOk
            simp only [tokenOk, Bool.false_eq_true, ↓reduceIte]
            cases nextEq : advanceTerminalParseView view position symbol with
            | none => simp [nextEq] at accepted
            | some next =>
              simp only [nextEq] at accepted ⊢
              simpa [terminal] using ih values next entries valid accepted
        · simp_all
      | node child =>
        simp only [children] at accepted
        split at accepted
        · simp at accepted
        · rename_i terminal
          split at accepted
          · simp at accepted
          · rename_i range
            cases entries with
            | nil => simp at accepted
            | cons entry entries =>
              simp only at accepted
              split at accepted
              · simp at accepted
              · rename_i checks
                have found := valid entry (by simp)
                have tailValid : EntriesValid view entries := fun e he => valid e (by simp [he])
                have bounds : child < current ∧ child = entry.1 ∧
                    entry.2.nonterminal = symbol - grammar.n_kinds ∧
                    entry.2.position_start = position := by
                  simpa [Bool.or_eq_true, Nat.not_le, and_assoc] using checks
                have idBound : entry.1 < current := bounds.2.1 ▸ bounds.1
                simp only [checkChildrenParseView, if_neg terminal, if_neg range]
                simp [bounds.2.1, Nat.not_le.mpr idBound, found, bounds.2.2.1,
                  bounds.2.2.2, ih values entry.2.position_end entries tailValid accepted]

theorem node_sound (grammar : Grammar) (view : ParseArtifactView artifact)
    (id : Nat) (value : ParseNode) (entries : List Entry)
    (valid : EntriesValid view entries)
    (accepted : node grammar view id value entries = true) :
    checkNodeParseView grammar artifact view id value = true := by
  rcases value with ⟨productionId, nonterminal, start, finish, values⟩
  cases production : grammar.production? productionId with
  | none => simp [node, production] at accepted
  | some rule =>
    simp only [node, production, Bool.and_eq_true, decide_eq_true_eq] at accepted
    rcases accepted with ⟨⟨⟨lhs, ordered⟩, bounded⟩, accepted⟩
    simp only [checkNodeParseView, production, Bool.and_eq_true, decide_eq_true_eq]
    exact ⟨⟨⟨lhs, ordered⟩, bounded⟩,
      children_sound grammar view id rule.rhs values start
        finish entries valid accepted⟩

theorem check_sound (grammar : Grammar) (view : ParseArtifactView artifact)
    (id : Nat) (remaining : List ParseNode) (stack : List Entry)
    (remainingValid : ∀ offset value, remaining[offset]? = some value →
      view.artifactView.node? (id + offset) = some value)
    (stackValid : EntriesValid view stack)
    (accepted : check grammar view id remaining stack = true) :
    checkNodesFromParseView grammar artifact view id remaining = true := by
  induction remaining generalizing id stack with
  | nil => rfl
  | cons value rest ih =>
    simp only [check, Bool.and_eq_true] at accepted
    simp only [checkNodesFromParseView, Bool.and_eq_true]
    have childrenValid : EntriesValid view (stack.take (childCount value)).reverse := by
      intro entry member
      exact stackValid entry (List.mem_of_mem_take (List.mem_reverse.mp member))
    refine ⟨node_sound grammar view id value _ childrenValid accepted.1, ?_⟩
    apply ih (id + 1) ((id, value) :: stack.drop (childCount value))
    · intro offset child found
      have found' := remainingValid (offset + 1) child (by simpa using found)
      simpa [Nat.add_assoc, Nat.add_comm 1] using found'
    · intro entry member
      rcases List.mem_cons.mp member with rfl | member
      · simpa using remainingValid 0 value (by simp)
      · exact stackValid entry (List.mem_of_mem_drop member)
    · exact accepted.2

theorem check_all_sound (grammar : Grammar) (view : ParseArtifactView artifact)
    (accepted : check grammar view 0 artifact.parse_nodes [] = true) :
    checkNodesFromParseView grammar artifact view 0 artifact.parse_nodes = true := by
  apply check_sound grammar view 0 artifact.parse_nodes [] _ _ accepted
  · intro offset value found
    simpa [ArtifactView.node?_eq] using found
  · simp [EntriesValid]

end Lanius.Extraction.ParsePostorder
