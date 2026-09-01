import Lanius.Extraction.GeneratedGrammar
import Lanius.Extraction.TokenChecker

namespace Lanius.Extraction

def packedFlag : Nat := 2147483648
def packedLimit : Nat := 4294967296
def packedKindBase : Nat := 32768

def isPackedSemanticKind (code : Nat) : Bool :=
  packedFlag ≤ code && code < packedLimit

def packedInnerKind (code : Nat) : Nat :=
  code % packedKindBase

def packedOuterKind (code : Nat) : Nat :=
  (code / packedKindBase) % packedKindBase

def Grammar.canonicalKind? (grammar : Grammar) (semanticKind : Nat) : Option Nat :=
  grammar.canonical_kinds[semanticKind]?

def semanticKindMatchesToken
    (grammar : Grammar) (token : Token) (code : Nat) : Bool :=
  if isPackedSemanticKind code then
    token.kind = grammar.split_token_kind &&
    grammar.canonicalKind? (packedInnerKind code) = some grammar.split_component_kind &&
    grammar.canonicalKind? (packedOuterKind code) = some grammar.split_component_kind
  else
    code < grammar.n_kinds && grammar.canonicalKind? code = some token.kind

def semanticKindsValid
    (grammar : Grammar) (tokens : List Token) (semanticKinds : List Nat) : Bool :=
  tokens.length = semanticKinds.length &&
  (tokens.zip semanticKinds).all fun pair =>
    semanticKindMatchesToken grammar pair.1 pair.2

/-- Consume one grammar terminal at a token-lattice position. -/
def advanceTerminal
    (semanticKinds : List Nat) (position expected : Nat) : Option Nat := do
  let code ← semanticKinds[position / 2]?
  if isPackedSemanticKind code then
    let actual := if position % 2 = 0 then packedInnerKind code else packedOuterKind code
    if actual = expected then some (position + 1) else none
  else if position % 2 = 0 && code = expected then
    some (position + 2)
  else
    none

def checkChildren
    (grammar : Grammar)
    (semanticKinds : List Nat)
    (nodes : List ParseNode)
    (currentNode : Nat) : List Nat → List ParseChild → Nat → Option Nat
  | [], [], position => some position
  | symbol :: symbols, child :: children, position =>
      if symbol < grammar.n_kinds then
        match child with
        | .token tokenId => do
            if tokenId != position / 2 then none else
            let next ← advanceTerminal semanticKinds position symbol
            checkChildren grammar semanticKinds nodes currentNode symbols children next
        | .node _ => none
      else
        let nonterminal := symbol - grammar.n_kinds
        if nonterminal >= grammar.n_nonterminals then none else
        match child with
        | .token _ => none
        | .node childId => do
            if childId >= currentNode then none else
            let childNode ← nodes[childId]?
            if childNode.nonterminal != nonterminal ||
                childNode.position_start != position then none else
            checkChildren grammar semanticKinds nodes currentNode
              symbols children childNode.position_end
  | _, _, _ => none

def checkNode
    (grammar : Grammar)
    (semanticKinds : List Nat)
    (nodes : List ParseNode)
    (id : Nat)
    (node : ParseNode) : Bool :=
  match grammar.production? node.production with
  | none => false
  | some production =>
      node.nonterminal = production.lhs &&
      node.position_start ≤ node.position_end &&
      node.position_end ≤ semanticKinds.length * 2 &&
      checkChildren grammar semanticKinds nodes id production.rhs
        node.children node.position_start = some node.position_end

def checkNodesFrom
    (grammar : Grammar)
    (semanticKinds : List Nat)
    (allNodes : List ParseNode) : Nat → List ParseNode → Bool
  | _, [] => true
  | id, node :: rest =>
      checkNode grammar semanticKinds allNodes id node &&
      checkNodesFrom grammar semanticKinds allNodes (id + 1) rest

/-! ## Array-backed kernel reduction path

These functions compute the same Boolean as the public list checker.  They
hold the two random-access tables as arrays so validating thousands of child
edges does not repeatedly traverse a list prefix. -/

def advanceTerminalArray
    (semanticKinds : Array Nat) (position expected : Nat) : Option Nat := do
  let code ← semanticKinds[position / 2]?
  if isPackedSemanticKind code then
    let actual := if position % 2 = 0 then packedInnerKind code else packedOuterKind code
    if actual = expected then some (position + 1) else none
  else if position % 2 = 0 && code = expected then
    some (position + 2)
  else none

def checkChildrenArray
    (grammar : Grammar)
    (semanticKinds : Array Nat)
    (nodes : Array ParseNode)
    (currentNode : Nat) : List Nat → List ParseChild → Nat → Option Nat
  | [], [], position => some position
  | symbol :: symbols, child :: children, position =>
      if symbol < grammar.n_kinds then
        match child with
        | .token tokenId => do
            if tokenId != position / 2 then none else
            let next ← advanceTerminalArray semanticKinds position symbol
            checkChildrenArray grammar semanticKinds nodes currentNode
              symbols children next
        | .node _ => none
      else
        let nonterminal := symbol - grammar.n_kinds
        if nonterminal >= grammar.n_nonterminals then none else
        match child with
        | .token _ => none
        | .node childId => do
            if childId >= currentNode then none else
            let childNode ← nodes[childId]?
            if childNode.nonterminal != nonterminal ||
                childNode.position_start != position then none else
            checkChildrenArray grammar semanticKinds nodes currentNode
              symbols children childNode.position_end
  | _, _, _ => none

def checkNodeArray
    (grammar : Grammar)
    (semanticKinds : Array Nat)
    (nodes : Array ParseNode)
    (id : Nat)
    (node : ParseNode) : Bool :=
  match grammar.production? node.production with
  | none => false
  | some production =>
      node.nonterminal = production.lhs &&
      node.position_start ≤ node.position_end &&
      node.position_end ≤ semanticKinds.size * 2 &&
      checkChildrenArray grammar semanticKinds nodes id production.rhs
        node.children node.position_start = some node.position_end

def checkNodesFromArray
    (grammar : Grammar)
    (semanticKinds : Array Nat)
    (allNodes : Array ParseNode) : Nat → List ParseNode → Bool
  | _, [] => true
  | id, node :: rest =>
      checkNodeArray grammar semanticKinds allNodes id node &&
      checkNodesFromArray grammar semanticKinds allNodes (id + 1) rest

theorem checkNodesFromArray_append
    (grammar : Grammar) (semanticKinds : Array Nat)
    (allNodes : Array ParseNode) (id : Nat)
    (left right : List ParseNode) :
    checkNodesFromArray grammar semanticKinds allNodes id (left ++ right) =
      (checkNodesFromArray grammar semanticKinds allNodes id left &&
        checkNodesFromArray grammar semanticKinds allNodes
          (id + left.length) right) := by
  induction left generalizing id with
  | nil => simp [checkNodesFromArray]
  | cons node left inductionHypothesis =>
      simp only [List.cons_append, checkNodesFromArray, List.length_cons]
      rw [inductionHypothesis]
      cases checkNodeArray grammar semanticKinds allNodes id node <;>
        simp [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm]

def checkNodesFromFast
    (grammar : Grammar) (semanticKinds : List Nat)
    (allNodes : List ParseNode) (id : Nat) (remaining : List ParseNode) : Bool :=
  checkNodesFromArray grammar semanticKinds.toArray allNodes.toArray id remaining

theorem checkNodesFromFast_append
    (grammar : Grammar) (semanticKinds : List Nat)
    (allNodes : List ParseNode) (id : Nat)
    (left right : List ParseNode) :
    checkNodesFromFast grammar semanticKinds allNodes id (left ++ right) =
      (checkNodesFromFast grammar semanticKinds allNodes id left &&
        checkNodesFromFast grammar semanticKinds allNodes
          (id + left.length) right) := by
  exact checkNodesFromArray_append grammar semanticKinds.toArray
    allNodes.toArray id left right

theorem advanceTerminalArray_eq
    (semanticKinds : List Nat) (position expected : Nat) :
    advanceTerminalArray semanticKinds.toArray position expected =
      advanceTerminal semanticKinds position expected := by
  simp [advanceTerminalArray, advanceTerminal]

theorem checkChildrenArray_eq
    (grammar : Grammar) (semanticKinds : List Nat) (nodes : List ParseNode)
    (currentNode : Nat) (symbols : List Nat) (children : List ParseChild)
    (position : Nat) :
    checkChildrenArray grammar semanticKinds.toArray nodes.toArray currentNode
        symbols children position =
      checkChildren grammar semanticKinds nodes currentNode
        symbols children position := by
  induction symbols generalizing children position with
  | nil => cases children <;> rfl
  | cons symbol symbols inductionHypothesis =>
      cases children with
      | nil => rfl
      | cons child children =>
          cases child <;>
            simp [checkChildrenArray, checkChildren, advanceTerminalArray_eq,
              inductionHypothesis]

theorem checkNodeArray_eq
    (grammar : Grammar) (semanticKinds : List Nat) (nodes : List ParseNode)
    (id : Nat) (node : ParseNode) :
    checkNodeArray grammar semanticKinds.toArray nodes.toArray id node =
      checkNode grammar semanticKinds nodes id node := by
  simp [checkNodeArray, checkNode, checkChildrenArray_eq]

theorem checkNodesFromFast_eq
    (grammar : Grammar) (semanticKinds : List Nat) (nodes : List ParseNode)
    (id : Nat) (remaining : List ParseNode) :
    checkNodesFromFast grammar semanticKinds nodes id remaining =
      checkNodesFrom grammar semanticKinds nodes id remaining := by
  unfold checkNodesFromFast
  induction remaining generalizing id with
  | nil => rfl
  | cons node rest inductionHypothesis =>
      simp [checkNodesFromArray, checkNodesFrom, checkNodeArray_eq,
        inductionHypothesis]

/-! The kernel representation of `Array` still reduces through its backing
list.  A small table of bounded list chunks therefore gives predictable
kernel cost while native code remains free to use the array path above. -/

def chunkLookup (chunks : List (List α)) (index : Nat) : Option α :=
  match chunks with
  | [] => none
  | chunk :: chunks =>
      if index < chunk.length then chunk[index]?
      else chunkLookup chunks (index - chunk.length)

theorem chunkLookup_eq_flatten
    (chunks : List (List α)) (index : Nat) :
    chunkLookup chunks index = chunks.flatten[index]? := by
  induction chunks generalizing index with
  | nil => rfl
  | cons chunk chunks inductionHypothesis =>
      unfold chunkLookup List.flatten
      by_cases inHead : index < chunk.length
      · rw [if_pos inHead]
        exact (List.getElem?_append_left inHead).symm
      · rw [if_neg inHead, inductionHypothesis]
        exact (List.getElem?_append_right (by omega)).symm

def checkChildrenChunks
    (grammar : Grammar)
    (semanticKinds : List Nat)
    (nodeChunks : List (List ParseNode))
    (currentNode : Nat) : List Nat → List ParseChild → Nat → Option Nat
  | [], [], position => some position
  | symbol :: symbols, child :: children, position =>
      if symbol < grammar.n_kinds then
        match child with
        | .token tokenId => do
            if tokenId != position / 2 then none else
            let next ← advanceTerminal semanticKinds position symbol
            checkChildrenChunks grammar semanticKinds nodeChunks currentNode
              symbols children next
        | .node _ => none
      else
        let nonterminal := symbol - grammar.n_kinds
        if nonterminal >= grammar.n_nonterminals then none else
        match child with
        | .token _ => none
        | .node childId => do
            if childId >= currentNode then none else
            let childNode ← chunkLookup nodeChunks childId
            if childNode.nonterminal != nonterminal ||
                childNode.position_start != position then none else
            checkChildrenChunks grammar semanticKinds nodeChunks currentNode
              symbols children childNode.position_end
  | _, _, _ => none

def checkNodeChunks
    (grammar : Grammar)
    (semanticKinds : List Nat)
    (nodeChunks : List (List ParseNode))
    (id : Nat)
    (node : ParseNode) : Bool :=
  match grammar.production? node.production with
  | none => false
  | some production =>
      node.nonterminal = production.lhs &&
      node.position_start ≤ node.position_end &&
      node.position_end ≤ semanticKinds.length * 2 &&
      checkChildrenChunks grammar semanticKinds nodeChunks id production.rhs
        node.children node.position_start = some node.position_end

def checkNodesFromChunks
    (grammar : Grammar)
    (semanticKinds : List Nat)
    (nodeChunks : List (List ParseNode)) : Nat → List ParseNode → Bool
  | _, [] => true
  | id, node :: rest =>
      checkNodeChunks grammar semanticKinds nodeChunks id node &&
      checkNodesFromChunks grammar semanticKinds nodeChunks (id + 1) rest

theorem checkNodesFromChunks_append
    (grammar : Grammar) (semanticKinds : List Nat)
    (nodeChunks : List (List ParseNode)) (id : Nat)
    (left right : List ParseNode) :
    checkNodesFromChunks grammar semanticKinds nodeChunks id (left ++ right) =
      (checkNodesFromChunks grammar semanticKinds nodeChunks id left &&
        checkNodesFromChunks grammar semanticKinds nodeChunks
          (id + left.length) right) := by
  induction left generalizing id with
  | nil => simp [checkNodesFromChunks]
  | cons node left inductionHypothesis =>
      simp only [List.cons_append, checkNodesFromChunks, List.length_cons]
      rw [inductionHypothesis]
      cases checkNodeChunks grammar semanticKinds nodeChunks id node <;>
        simp [Nat.add_comm, Nat.add_left_comm]

theorem checkChildrenChunks_eq
    (grammar : Grammar) (semanticKinds : List Nat)
    (nodeChunks : List (List ParseNode)) (currentNode : Nat)
    (symbols : List Nat) (children : List ParseChild) (position : Nat) :
    checkChildrenChunks grammar semanticKinds nodeChunks currentNode
        symbols children position =
      checkChildren grammar semanticKinds nodeChunks.flatten currentNode
        symbols children position := by
  induction symbols generalizing children position with
  | nil => cases children <;> rfl
  | cons symbol symbols inductionHypothesis =>
      cases children with
      | nil => rfl
      | cons child children =>
          cases child <;>
            simp [checkChildrenChunks, checkChildren, chunkLookup_eq_flatten,
              inductionHypothesis]

theorem checkNodeChunks_eq
    (grammar : Grammar) (semanticKinds : List Nat)
    (nodeChunks : List (List ParseNode)) (id : Nat) (node : ParseNode) :
    checkNodeChunks grammar semanticKinds nodeChunks id node =
      checkNode grammar semanticKinds nodeChunks.flatten id node := by
  simp [checkNodeChunks, checkNode, checkChildrenChunks_eq]

theorem checkNodesFromChunks_eq
    (grammar : Grammar) (semanticKinds : List Nat)
    (nodeChunks : List (List ParseNode)) (id : Nat)
    (remaining : List ParseNode) :
    checkNodesFromChunks grammar semanticKinds nodeChunks id remaining =
      checkNodesFrom grammar semanticKinds nodeChunks.flatten id remaining := by
  induction remaining generalizing id with
  | nil => rfl
  | cons node rest inductionHypothesis =>
      simp [checkNodesFromChunks, checkNodesFrom, checkNodeChunks_eq,
        inductionHypothesis]

def rootShapeValid
    (grammar : Grammar)
    (tokenCount : Nat)
    (nodes : List ParseNode)
    (rootId : Nat) : Bool :=
  match nodes[rootId]? with
  | none => false
  | some root =>
      rootId + 1 = nodes.length &&
      root.nonterminal = grammar.start_nonterminal &&
      root.position_start = 0 &&
      root.position_end = tokenCount * 2

inductive ChildrenMatch
    (grammar : Grammar)
    (semanticKinds : List Nat)
    (nodes : List ParseNode)
    (currentNode : Nat) : List Nat → List ParseChild → Nat → Nat → Prop
  | empty (position) : ChildrenMatch grammar semanticKinds nodes currentNode [] [] position position
  | terminal
      (terminal : symbol < grammar.n_kinds)
      (tokenPosition : tokenId = position / 2)
      (advanced : advanceTerminal semanticKinds position symbol = some next)
      (tail : ChildrenMatch grammar semanticKinds nodes currentNode
        symbols children next finish) :
      ChildrenMatch grammar semanticKinds nodes currentNode
        (symbol :: symbols) (.token tokenId :: children) position finish
  | nonterminal
      (nonterminal : grammar.n_kinds ≤ symbol)
      (inRange : symbol - grammar.n_kinds < grammar.n_nonterminals)
      (earlier : childId < currentNode)
      (lookup : nodes[childId]? = some childNode)
      (childKind : childNode.nonterminal = symbol - grammar.n_kinds)
      (childStart : childNode.position_start = position)
      (tail : ChildrenMatch grammar semanticKinds nodes currentNode
        symbols children childNode.position_end finish) :
      ChildrenMatch grammar semanticKinds nodes currentNode
        (symbol :: symbols) (.node childId :: children) position finish

inductive NodeMatches
    (grammar : Grammar)
    (semanticKinds : List Nat)
    (nodes : List ParseNode)
    (id : Nat)
    (node : ParseNode) : Prop where
  | intro
      (production : Production)
      (productionLookup : grammar.production? node.production = some production)
      (nonterminal : node.nonterminal = production.lhs)
      (ordered : node.position_start ≤ node.position_end)
      (bounded : node.position_end ≤ semanticKinds.length * 2)
      (children : ChildrenMatch grammar semanticKinds nodes id production.rhs
        node.children node.position_start node.position_end) :
      NodeMatches grammar semanticKinds nodes id node

inductive NodesMatchFrom
    (grammar : Grammar)
    (semanticKinds : List Nat)
    (allNodes : List ParseNode) : Nat → List ParseNode → Prop
  | empty (id : Nat) : NodesMatchFrom grammar semanticKinds allNodes id []
  | cons {id : Nat} {node : ParseNode} {rest : List ParseNode}
      (head : NodeMatches grammar semanticKinds allNodes id node)
      (tail : NodesMatchFrom grammar semanticKinds allNodes (id + 1) rest) :
      NodesMatchFrom grammar semanticKinds allNodes id (node :: rest)

inductive RootMatches
    (grammar : Grammar)
    (tokenCount : Nat)
    (nodes : List ParseNode)
    (rootId : Nat) : Prop where
  | intro
      (root : ParseNode)
      (lookup : nodes[rootId]? = some root)
      (last : rootId + 1 = nodes.length)
      (nonterminal : root.nonterminal = grammar.start_nonterminal)
      (start : root.position_start = 0)
      (finish : root.position_end = tokenCount * 2) :
      RootMatches grammar tokenCount nodes rootId

theorem checkChildren_sound
    {grammar : Grammar}
    {semanticKinds : List Nat}
    {nodes : List ParseNode}
    {currentNode : Nat}
    {symbols : List Nat}
    {children : List ParseChild}
    {start finish : Nat}
    (accepted : checkChildren grammar semanticKinds nodes currentNode
      symbols children start = some finish) :
    ChildrenMatch grammar semanticKinds nodes currentNode
      symbols children start finish := by
  induction symbols generalizing children start finish with
  | nil =>
      cases children with
      | nil =>
          simp [checkChildren] at accepted
          subst finish
          exact .empty start
      | cons child rest => simp [checkChildren] at accepted
  | cons symbol symbols inductionHypothesis =>
      cases children with
      | nil => simp [checkChildren] at accepted
      | cons child children =>
          by_cases terminal : symbol < grammar.n_kinds
          · cases child with
            | node childId => simp [checkChildren, terminal] at accepted
            | token tokenId =>
                by_cases tokenPosition : tokenId = start / 2
                · cases advanced : advanceTerminal semanticKinds start symbol with
                  | none => simp [checkChildren, terminal, tokenPosition, advanced] at accepted
                  | some next =>
                      simp [checkChildren, terminal, tokenPosition, advanced] at accepted
                      exact .terminal terminal tokenPosition advanced
                        (inductionHypothesis accepted)
                · simp [checkChildren, terminal, tokenPosition] at accepted
          · have nonterminal : grammar.n_kinds ≤ symbol := Nat.le_of_not_gt terminal
            by_cases inRange : symbol - grammar.n_kinds < grammar.n_nonterminals
            · cases child with
              | token tokenId => simp [checkChildren, terminal] at accepted
              | node childId =>
                  by_cases earlier : childId < currentNode
                  · cases lookup : nodes[childId]? with
                    | none => simp [checkChildren, terminal, lookup] at accepted
                    | some childNode =>
                        by_cases childKind :
                            childNode.nonterminal = symbol - grammar.n_kinds
                        · by_cases childStart : childNode.position_start = start
                          · simp [checkChildren, terminal, inRange, earlier, lookup,
                              childKind, childStart] at accepted
                            exact .nonterminal nonterminal inRange earlier lookup
                              childKind childStart (inductionHypothesis accepted)
                          · simp [checkChildren, terminal, lookup,
                              childKind, childStart] at accepted
                        · simp [checkChildren, terminal, lookup,
                            childKind] at accepted
                  · simp [checkChildren, terminal, inRange, earlier] at accepted
            · simp [checkChildren, terminal, inRange] at accepted

theorem checkNode_sound
    {grammar : Grammar}
    {semanticKinds : List Nat}
    {nodes : List ParseNode}
    {id : Nat}
    {node : ParseNode}
    (accepted : checkNode grammar semanticKinds nodes id node = true) :
    NodeMatches grammar semanticKinds nodes id node := by
  unfold checkNode at accepted
  cases lookup : grammar.production? node.production with
  | none => simp [lookup] at accepted
  | some production =>
      simp [lookup] at accepted
      rcases accepted with ⟨⟨⟨nonterminal, ordered⟩, bounded⟩, children⟩
      exact .intro production lookup nonterminal ordered bounded
        (checkChildren_sound children)

theorem checkNodesFrom_sound
    {grammar : Grammar}
    {semanticKinds : List Nat}
    {allNodes remaining : List ParseNode}
    {id : Nat}
    (accepted : checkNodesFrom grammar semanticKinds allNodes id remaining = true) :
    NodesMatchFrom grammar semanticKinds allNodes id remaining := by
  induction remaining generalizing id with
  | nil => exact .empty id
  | cons node rest inductionHypothesis =>
      simp [checkNodesFrom] at accepted
      exact .cons (checkNode_sound accepted.1) (inductionHypothesis accepted.2)

theorem rootShapeValid_sound
    {grammar : Grammar}
    {tokenCount : Nat}
    {nodes : List ParseNode}
    {rootId : Nat}
    (accepted : rootShapeValid grammar tokenCount nodes rootId = true) :
    RootMatches grammar tokenCount nodes rootId := by
  unfold rootShapeValid at accepted
  cases lookup : nodes[rootId]? with
  | none => simp [lookup] at accepted
  | some root =>
      simp [lookup] at accepted
      exact ⟨root, lookup, accepted.1.1.1, accepted.1.1.2,
        accepted.1.2, accepted.2⟩

def checkParseArtifact (artifact : Artifact) : Bool :=
  checkTokenArtifact artifact &&
  semanticKindsValid laniusGrammar artifact.tokens artifact.semantic_token_kinds &&
  checkNodesFrom laniusGrammar artifact.semantic_token_kinds
    artifact.parse_nodes 0 artifact.parse_nodes &&
  match artifact.parse_root with
  | none => false
  | some rootId =>
      rootShapeValid laniusGrammar artifact.tokens.length artifact.parse_nodes rootId

/-- Declarative acceptance statement exposed to later extraction proofs. It
    separates the already-proved token meaning from grammar/tree validity. -/
def ParseArtifactValid (artifact : Artifact) : Prop :=
  TokenArtifactValid artifact ∧
  semanticKindsValid laniusGrammar artifact.tokens artifact.semantic_token_kinds = true ∧
  NodesMatchFrom laniusGrammar artifact.semantic_token_kinds
    artifact.parse_nodes 0 artifact.parse_nodes ∧
  ∃ rootId,
    artifact.parse_root = some rootId ∧
    RootMatches laniusGrammar artifact.tokens.length artifact.parse_nodes rootId

theorem checkParseArtifact_sound {artifact : Artifact}
    (accepted : checkParseArtifact artifact = true) :
    ParseArtifactValid artifact := by
  unfold checkParseArtifact at accepted
  simp only [Bool.and_eq_true] at accepted
  rcases accepted with ⟨⟨⟨tokensAccepted, semanticAccepted⟩, nodesAccepted⟩, rootAccepted⟩
  have tokenValidity := checkTokenArtifact_sound tokensAccepted
  cases root : artifact.parse_root with
  | none => simp [root] at rootAccepted
  | some rootId =>
      exact ⟨tokenValidity, semanticAccepted, checkNodesFrom_sound nodesAccepted,
        rootId, root, rootShapeValid_sound (by simpa [root] using rootAccepted)⟩

end Lanius.Extraction
