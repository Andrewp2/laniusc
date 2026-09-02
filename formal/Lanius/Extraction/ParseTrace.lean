import Lanius.Extraction.ParseChecker

open Lean Elab Tactic Meta

namespace Lanius.Extraction

inductive ChildrenMatchView
    (grammar : Grammar) (artifact : Artifact) (view : ArtifactView artifact)
    (currentNode : Nat) : List Nat -> List ParseChild -> Nat -> Nat -> Prop
  | empty (position) :
      ChildrenMatchView grammar artifact view currentNode [] [] position position
  | terminal
      (terminal : symbol < grammar.n_kinds)
      (tokenPosition : tokenId = position / 2)
      (advanced : advanceTerminal artifact.semantic_token_kinds position symbol =
        some next)
      (tail : ChildrenMatchView grammar artifact view currentNode
        symbols children next finish) :
      ChildrenMatchView grammar artifact view currentNode
        (symbol :: symbols) (.token tokenId :: children) position finish
  | nonterminal
      (nonterminal : grammar.n_kinds <= symbol)
      (inRange : symbol - grammar.n_kinds < grammar.n_nonterminals)
      (earlier : childId < currentNode)
      (lookup : view.node? childId = some childNode)
      (childKind : childNode.nonterminal = symbol - grammar.n_kinds)
      (childStart : childNode.position_start = position)
      (tail : ChildrenMatchView grammar artifact view currentNode
        symbols children childNode.position_end finish) :
      ChildrenMatchView grammar artifact view currentNode
        (symbol :: symbols) (.node childId :: children) position finish

inductive NodeMatchesView
    (grammar : Grammar) (artifact : Artifact) (view : ArtifactView artifact)
    (id : Nat) (node : ParseNode) : Prop where
  | intro
      (production : Production)
      (productionLookup : grammar.production? node.production = some production)
      (nonterminal : node.nonterminal = production.lhs)
      (ordered : node.position_start <= node.position_end)
      (bounded : node.position_end <= artifact.semantic_token_kinds.length * 2)
      (children : ChildrenMatchView grammar artifact view id production.rhs
        node.children node.position_start node.position_end) :
      NodeMatchesView grammar artifact view id node

inductive NodesMatchFromView
    (grammar : Grammar) (artifact : Artifact) (view : ArtifactView artifact) :
    Nat -> List ParseNode -> Prop
  | empty (id : Nat) : NodesMatchFromView grammar artifact view id []
  | cons {id : Nat} {node : ParseNode} {rest : List ParseNode}
      (head : NodeMatchesView grammar artifact view id node)
      (tail : NodesMatchFromView grammar artifact view (id + 1) rest) :
      NodesMatchFromView grammar artifact view id (node :: rest)

theorem ChildrenMatchView.sound
    {grammar : Grammar} {artifact : Artifact} (view : ArtifactView artifact)
    {currentNode : Nat} {symbols : List Nat} {children : List ParseChild}
    {start finish : Nat}
    (trace : ChildrenMatchView grammar artifact view currentNode
      symbols children start finish) :
    ChildrenMatch grammar artifact.semantic_token_kinds artifact.parse_nodes
      currentNode symbols children start finish := by
  induction trace with
  | empty position => exact .empty position
  | terminal terminal tokenPosition advanced tail inductionHypothesis =>
      exact .terminal terminal tokenPosition advanced inductionHypothesis
  | nonterminal nonterminal inRange earlier lookup childKind childStart tail
      inductionHypothesis =>
      have canonicalLookup := lookup
      rw [view.node?_eq] at canonicalLookup
      exact .nonterminal nonterminal inRange earlier canonicalLookup childKind
        childStart inductionHypothesis

theorem NodeMatchesView.sound
    {grammar : Grammar} {artifact : Artifact} (view : ArtifactView artifact)
    {id : Nat} {node : ParseNode}
    (trace : NodeMatchesView grammar artifact view id node) :
    NodeMatches grammar artifact.semantic_token_kinds artifact.parse_nodes
      id node := by
  cases trace with
  | intro production productionLookup nonterminal ordered bounded children =>
      exact .intro production productionLookup nonterminal ordered bounded
        (children.sound view)

theorem NodesMatchFromView.sound
    {grammar : Grammar} {artifact : Artifact} (view : ArtifactView artifact)
    {id : Nat} {remaining : List ParseNode}
    (trace : NodesMatchFromView grammar artifact view id remaining) :
    NodesMatchFrom grammar artifact.semantic_token_kinds artifact.parse_nodes
      id remaining := by
  induction trace with
  | empty id => exact .empty id
  | cons head tail inductionHypothesis =>
      exact .cons (head.sound view) inductionHypothesis

/-- A local checked-view node result can be transported directly into the
declarative list model.  Concrete trace generation uses this theorem once per
node instead of reducing the whole-node-table Boolean in one kernel term. -/
theorem checkNodeView_sound_direct
    (grammar : Grammar) (artifact : Artifact) (view : ArtifactView artifact)
    (id : Nat) (node : ParseNode)
    (accepted : checkNodeView grammar artifact view id node = true) :
    NodeMatches grammar artifact.semantic_token_kinds artifact.parse_nodes
      id node := by
  rw [checkNodeView_eq] at accepted
  exact checkNode_sound accepted

theorem parseArtifactValid_of_trace
    (artifact : Artifact) (rootId : Nat)
    (tokensAccepted : checkTokenArtifact artifact = true)
    (semanticAccepted : semanticKindsValid laniusGrammar artifact.tokens
      artifact.semantic_token_kinds = true)
    (nodes : NodesMatchFrom laniusGrammar artifact.semantic_token_kinds
      artifact.parse_nodes 0 artifact.parse_nodes)
    (rootFound : artifact.parse_root = some rootId)
    (rootAccepted : rootShapeValid laniusGrammar artifact.tokens.length
      artifact.parse_nodes rootId = true) :
    ParseArtifactValid artifact := by
  refine And.intro (checkTokenArtifact_sound tokensAccepted) ?_
  refine And.intro semanticAccepted ?_
  refine And.intro nodes ?_
  exact Exists.intro rootId
    (And.intro rootFound (rootShapeValid_sound rootAccepted))

private def projection (name : Name) (value : Expr) : Expr :=
  mkApp (mkConst name) value

private def expectSome (label : String) (value : Expr) : MetaM Expr := do
  let reduced <- withTransparency .all <| whnf value
  unless reduced.isAppOfArity ``Option.some 2 do
    throwError "parse_nodes_trace: {label} reduced to {reduced}, not some _"
  return reduced.getAppArgs[1]!

private def mkSome (value : Expr) : MetaM Expr := do
  let type <- inferType value
  return mkApp2 (mkConst ``Option.some [0]) type value

private def mkNatRelationProof
    (relation relationInstance decision : Name) (left right : Expr) : MetaM Expr := do
  let proposition := mkApp4 (mkConst relation [0]) (mkConst ``Nat)
    (mkConst relationInstance) left right
  let decidable := mkApp2 (mkConst decision) left right
  let accepted <- mkEqRefl (mkConst ``true)
  return mkAppN (mkConst ``of_decide_eq_true)
    #[proposition, decidable, accepted]

private def mkNatLtProof (left right : Expr) : MetaM Expr :=
  mkNatRelationProof ``LT.lt ``instLTNat ``Nat.decLt left right

private def mkNatLeProof (left right : Expr) : MetaM Expr :=
  mkNatRelationProof ``LE.le ``instLENat ``Nat.decLe left right

private partial def buildChildrenViewTrace
    (grammar artifact view currentNode symbols children position finish : Expr) :
    MetaM Expr := do
  let symbolsWhnf <- withTransparency .all <| whnf symbols
  let childrenWhnf <- withTransparency .all <| whnf children
  if symbolsWhnf.isAppOfArity ``List.nil 1 &&
      childrenWhnf.isAppOfArity ``List.nil 1 then
    return mkAppN (mkConst ``ChildrenMatchView.empty)
      #[grammar, artifact, view, currentNode, position]
  unless symbolsWhnf.isAppOfArity ``List.cons 3 &&
      childrenWhnf.isAppOfArity ``List.cons 3 do
    throwError "parse_nodes_trace: production and child lists have different shapes"
  let symbol := symbolsWhnf.getAppArgs[1]!
  let remainingSymbols := symbolsWhnf.getAppArgs[2]!
  let child := childrenWhnf.getAppArgs[1]!
  let remainingChildren := childrenWhnf.getAppArgs[2]!
  let childWhnf <- withTransparency .all <| whnf child
  let nKinds := projection ``Grammar.n_kinds grammar
  if childWhnf.isAppOfArity ``ParseChild.token 1 then
    let tokenId := childWhnf.getAppArgs[0]!
    let next <- expectSome "terminal advance"
      (mkAppN (mkConst ``advanceTerminal)
        #[projection ``Artifact.semantic_token_kinds artifact, position, symbol])
    let terminal <- mkNatLtProof symbol nKinds
    let tokenPosition <- mkEqRefl tokenId
    let advanced <- mkEqRefl (← mkSome next)
    let tail <- buildChildrenViewTrace grammar artifact view currentNode
      remainingSymbols remainingChildren next finish
    return mkAppN (mkConst ``ChildrenMatchView.terminal)
      #[grammar, artifact, view, currentNode, symbol, tokenId, position, next,
        remainingSymbols, remainingChildren, finish, terminal, tokenPosition,
        advanced, tail]
  unless childWhnf.isAppOfArity ``ParseChild.node 1 do
    throwError "parse_nodes_trace: unknown parse-child constructor"
  let childId := childWhnf.getAppArgs[0]!
  let childNode <- expectSome "view node lookup"
    (mkAppN (mkConst ``ArtifactView.node?) #[artifact, view, childId])
  let nonterminal <- mkNatLeProof nKinds symbol
  let difference := mkApp2 (mkConst ``Nat.sub) symbol nKinds
  let inRange <- mkNatLtProof difference
    (projection ``Grammar.n_nonterminals grammar)
  let earlier <- mkNatLtProof childId currentNode
  let lookup <- mkEqRefl (← mkSome childNode)
  let childKind <- mkEqRefl difference
  let childStart <- mkEqRefl position
  let childEnd := projection ``ParseNode.position_end childNode
  let tail <- buildChildrenViewTrace grammar artifact view currentNode
    remainingSymbols remainingChildren childEnd finish
  return mkAppN (mkConst ``ChildrenMatchView.nonterminal)
    #[grammar, artifact, view, currentNode, symbol, childId, childNode, position,
      remainingSymbols, remainingChildren, finish, nonterminal, inRange,
      earlier, lookup, childKind, childStart, tail]

private def buildNodeViewTrace
    (grammar artifact view id node : Expr) : MetaM Expr := do
  let productionId := projection ``ParseNode.production node
  let production <- expectSome "grammar production lookup"
    (mkApp2 (mkConst ``Grammar.production?) grammar productionId)
  let productionLookup <- mkEqRefl (← mkSome production)
  let nonterminal <- mkEqRefl (projection ``Production.lhs production)
  let start := projection ``ParseNode.position_start node
  let finish := projection ``ParseNode.position_end node
  let ordered <- mkNatLeProof start finish
  let semanticKinds := projection ``Artifact.semantic_token_kinds artifact
  let semanticLength := mkApp2 (mkConst ``List.length [0])
    (mkConst ``Nat) semanticKinds
  let bound := mkApp2 (mkConst ``Nat.mul) semanticLength (mkNatLit 2)
  let bounded <- mkNatLeProof finish bound
  let children <- buildChildrenViewTrace grammar artifact view id
    (projection ``Production.rhs production)
    (projection ``ParseNode.children node) start finish
  return mkAppN (mkConst ``NodeMatchesView.intro)
    #[grammar, artifact, view, id, node, production, productionLookup,
      nonterminal, ordered, bounded, children]

private partial def buildNodesViewTrace
    (grammar artifact view id remaining : Expr) : MetaM Expr := do
  let remainingWhnf <- withTransparency .all <| whnf remaining
  if remainingWhnf.isAppOfArity ``List.nil 1 then
    return mkAppN (mkConst ``NodesMatchFromView.empty)
      #[grammar, artifact, view, id]
  unless remainingWhnf.isAppOfArity ``List.cons 3 do
    throwError "parse_nodes_trace: node table did not reduce to a list"
  let args := remainingWhnf.getAppArgs
  let node := args[1]!
  let rest := args[2]!
  let some idValue <- getNatValue? id
    | throwError "parse_nodes_trace: node id did not reduce to a numeral"
  let nextId := mkNatLit (idValue + 1)
  let headProof <- buildNodeViewTrace grammar artifact view id node
  let tailProof <- buildNodesViewTrace grammar artifact view nextId rest
  return mkAppN (mkConst ``NodesMatchFromView.cons)
    #[grammar, artifact, view, id, node, rest, headProof, tailProof]

private def buildNodesDirectTrace
    (grammar artifact view id remaining : Expr) : MetaM Expr := do
  let viewTrace <- buildNodesViewTrace grammar artifact view id remaining
  return mkAppN (mkConst ``NodesMatchFromView.sound)
    #[grammar, artifact, view, id, remaining, viewTrace]

private partial def buildNodesTrace
    (grammar artifact view semanticKinds allNodes id remaining : Expr) :
    MetaM Expr := do
  let remainingWhnf <- withTransparency .all <| whnf remaining
  if remainingWhnf.isAppOfArity ``List.nil 1 then
    return mkAppN (mkConst ``NodesMatchFrom.empty)
      #[grammar, semanticKinds, allNodes, id]
  unless remainingWhnf.isAppOfArity ``List.cons 3 do
    throwError "parse_nodes_trace: node table did not reduce to a list"
  let args := remainingWhnf.getAppArgs
  let node := args[1]!
  let rest := args[2]!
  let some idValue <- getNatValue? id
    | throwError "parse_nodes_trace: node id did not reduce to a numeral"
  let nextId := mkNatLit (idValue + 1)
  let accepted <- mkEqRefl (mkConst ``true)
  let headProof := mkAppN (mkConst ``checkNodeView_sound_direct)
    #[grammar, artifact, view, id, node, accepted]
  let tailProof <- buildNodesTrace grammar artifact view semanticKinds allNodes
    nextId rest
  return mkAppN (mkConst ``NodesMatchFrom.cons)
    #[grammar, semanticKinds, allNodes, id, node, rest, headProof, tailProof]

/-- Emit a structural parse-node proof for a closed artifact.  The tactic is
an untrusted proof producer: it proposes constructor and reflexivity terms,
and Lean's kernel checks the resulting `NodesMatchFrom` value normally. -/
syntax (name := parseNodesTrace) "parse_nodes_trace " term ", " term : tactic

@[tactic parseNodesTrace] def evalParseNodesTrace : Tactic := fun stx => do
  let `(tactic| parse_nodes_trace $artifactStx:term, $viewStx:term) := stx
    | throwUnsupportedSyntax
  withMainContext do
    let goal <- getMainGoal
    let goalType <- goal.getType
    unless goalType.isAppOfArity ``NodesMatchFrom 5 do
      throwError "parse_nodes_trace: expected a NodesMatchFrom goal"
    let goalArgs := goalType.getAppArgs
    let grammar := goalArgs[0]!
    let semanticKinds := goalArgs[1]!
    let allNodes := goalArgs[2]!
    let id := goalArgs[3]!
    let remaining := goalArgs[4]!
    let artifact <- elabTermEnsuringType artifactStx (mkConst ``Artifact)
    Term.synthesizeSyntheticMVarsNoPostponing
    let artifact <- instantiateMVars artifact
    let viewType := mkApp (mkConst ``ArtifactView) artifact
    let view <- elabTermEnsuringType viewStx viewType
    Term.synthesizeSyntheticMVarsNoPostponing
    let view <- instantiateMVars view
    let proof <- buildNodesTrace grammar artifact view semanticKinds allNodes id
      remaining
    withTransparency .all <| goal.assign proof
    replaceMainGoal []

/-- Construct the complete declarative parse certificate.  Only the token
trace, semantic-kind pass, and root check remain closed local reductions; the
large parse-node table is represented by the structural trace above. -/
syntax (name := parseArtifactTrace) "parse_artifact_trace " term ", " term : tactic

@[tactic parseArtifactTrace] def evalParseArtifactTrace : Tactic := fun stx => do
  let `(tactic| parse_artifact_trace $artifactStx:term, $viewStx:term) := stx
    | throwUnsupportedSyntax
  withMainContext do
    let goal <- getMainGoal
    let goalType <- goal.getType
    unless goalType.isAppOfArity ``ParseArtifactValid 1 do
      throwError "parse_artifact_trace: expected a ParseArtifactValid goal"
    let artifact <- elabTermEnsuringType artifactStx (mkConst ``Artifact)
    Term.synthesizeSyntheticMVarsNoPostponing
    let artifact <- instantiateMVars artifact
    let viewType := mkApp (mkConst ``ArtifactView) artifact
    let view <- elabTermEnsuringType viewStx viewType
    Term.synthesizeSyntheticMVarsNoPostponing
    let view <- instantiateMVars view
    let grammar := mkConst ``laniusGrammar
    let semanticKinds := mkApp (mkConst ``Artifact.semantic_token_kinds) artifact
    let allNodes := mkApp (mkConst ``Artifact.parse_nodes) artifact
    let nodes <- buildNodesTrace grammar artifact view semanticKinds allNodes
      (mkNatLit 0) allNodes
    let parseRoot := mkApp (mkConst ``Artifact.parse_root) artifact
    let rootWhnf <- withTransparency .all <| whnf parseRoot
    unless rootWhnf.isAppOfArity ``Option.some 2 do
      throwError "parse_artifact_trace: artifact parse root is absent"
    let rootId := rootWhnf.getAppArgs[1]!
    let trueProof <- mkEqRefl (mkConst ``true)
    let rootFound <- mkEqRefl rootWhnf
    let proof := mkAppN (mkConst ``parseArtifactValid_of_trace)
      #[artifact, rootId, trueProof, trueProof, nodes, rootFound, trueProof]
    withTransparency .all <| goal.assign proof
    replaceMainGoal []

end Lanius.Extraction
