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
