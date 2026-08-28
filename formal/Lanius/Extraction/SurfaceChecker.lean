import Lanius.Extraction.ParseChecker
import Lanius.Extraction.SurfaceReconstruct

namespace Lanius.Extraction

open Lanius

structure SpellingClaim where
  owner : ParseNodeId
  token : TokenId
  text : String
deriving BEq, Repr

structure SurfaceNodeClaim where
  id : SurfaceNodeId
  parseNode : ParseNodeId
  containingParseNode : Option ParseNodeId
  allowedProductions : List Nat
deriving BEq, Repr

structure SurfaceClaims where
  nodes : List SurfaceNodeClaim := []
  spellings : List SpellingClaim := []
deriving BEq, Repr

def SurfaceClaims.append (left right : SurfaceClaims) : SurfaceClaims := {
  nodes := left.nodes ++ right.nodes
  spellings := left.spellings ++ right.spellings
}

def SurfaceClaims.node
    (id : SurfaceNodeId) (parseNode : ParseNodeId)
    (containingParseNode : Option ParseNodeId)
    (allowedProductions : List Nat) : SurfaceClaims := {
  nodes := [{ id, parseNode, containingParseNode, allowedProductions }]
}

def SurfaceClaims.spelling
    (owner : ParseNodeId) (token : TokenId) (text : String) : SurfaceClaims := {
  spellings := [{ owner, token, text }]
}

def SurfaceClaims.name (owner : ParseNodeId) (name : SpelledName) : SurfaceClaims :=
  .spelling owner name.token name.text

infixl:65 " <+> " => SurfaceClaims.append

def collectMany (collect : α → Option SurfaceClaims) : List α → Option SurfaceClaims
  | [] => some {}
  | head :: tail => do
      pure ((← collect head) <+> (← collectMany collect tail))

mutual
  def collectPathSegmentClaimsWithFuel :
      Nat → ParseNodeId → List Nat → SurfacePathSegment → Option SurfaceClaims
    | 0, _, _, _ => none
    | fuel + 1, parent, allowed, segment => do
        let children := SurfaceClaims.name segment.parse_node segment.name <+>
          (← collectMany
            (collectTypeClaimsWithFuel fuel segment.parse_node) segment.arguments)
        pure (children <+>
          SurfaceClaims.node segment.id segment.parse_node (some parent) allowed)

  def collectPathClaimsWithFuel :
      Nat → ParseNodeId → List Nat → List Nat → SurfacePath → Option SurfaceClaims
    | 0, _, _, _, _ => none
    | fuel + 1, parent, allowed, segmentProductions, path => do
        let segments ← collectMany
          (collectPathSegmentClaimsWithFuel fuel path.parse_node segmentProductions)
          path.value.segments
        pure (segments <+>
          SurfaceClaims.node path.id path.parse_node (some parent) allowed)

  def collectArrayLengthClaims (owner : ParseNodeId) : SurfaceArrayLength → SurfaceClaims
    | .literal token text => .spelling owner token text
    | .parameter name => .name owner name

  def collectTypeClaimsWithFuel :
      Nat → ParseNodeId → SurfaceTypeExpr → Option SurfaceClaims
    | 0, _, _ => none
    | fuel + 1, parent, type => do
        let children ← match type.value with
          | .path path =>
              collectPathClaimsWithFuel fuel type.parse_node [69] [57] path
          | .array element length => do
              pure ((← collectTypeClaimsWithFuel fuel type.parse_node element) <+>
                collectArrayLengthClaims type.parse_node length)
          | .slice element => collectTypeClaimsWithFuel fuel type.parse_node element
          | .reference referent => collectTypeClaimsWithFuel fuel type.parse_node referent
        let productions := match type.value with
          | .path _ => [69]
          | .array _ _ | .slice _ => [70]
          | .reference _ => [285]
        pure (children <+>
          SurfaceClaims.node type.id type.parse_node (some parent) productions)
end

def unaryProduction : SurfaceUnaryOp → Nat
  | .positive => 156
  | .negative => 157
  | .logical_not => 158

def binaryProduction : SurfaceBinaryOp → Nat
  | .logical_or => 119
  | .logical_and => 122
  | .bit_or => 125
  | .bit_xor => 128
  | .bit_and => 131
  | .equal => 134
  | .not_equal => 135
  | .less => 138
  | .greater => 139
  | .less_equal => 140
  | .greater_equal => 141
  | .shift_left => 144
  | .shift_right => 145
  | .add => 148
  | .subtract => 149
  | .multiply => 152
  | .divide => 153
  | .remainder => 154

def assignProduction : SurfaceAssignOp → Nat
  | .set => 106
  | .add => 107
  | .subtract => 108
  | .multiply => 109
  | .divide => 110
  | .remainder => 111
  | .bit_xor => 112
  | .shift_left => 113
  | .shift_right => 114
  | .bit_and => 115
  | .bit_or => 116

def literalClaims (owner : ParseNodeId) : SurfaceLiteral → SurfaceClaims × List Nat
  | .integer token text => (.spelling owner token text, [175])
  | .float token text => (.spelling owner token text, [176])
  | .string token text => (.spelling owner token text, [177])
  | .character token text => (.spelling owner token text, [178])
  | .boolean true => ({}, [185])
  | .boolean false => ({}, [186])

mutual
  def collectStructValueFieldClaimsWithFuel :
      Nat → ParseNodeId → SurfaceStructFieldValue → Option SurfaceClaims
    | 0, _, _ => none
    | fuel + 1, container, field => do
        let children := SurfaceClaims.name field.parse_node field.name <+>
          (← collectExprClaimsWithFuel fuel field.parse_node field.value)
        pure (children <+>
          SurfaceClaims.node field.id field.parse_node (some container) [278])

  def collectExprClaimsWithFuel :
      Nat → ParseNodeId → SurfaceExpr → Option SurfaceClaims
    | 0, _, _ => none
    | fuel + 1, container, expression => do
        let (children, productions) ← match expression.value with
          | .literal literal => some (literalClaims expression.parse_node literal)
          | .path path => do
              pure (← collectPathClaimsWithFuel fuel expression.parse_node
                [47] [48, 49] path, [173])
          | .array elements => do
              pure (← collectMany
                (collectExprClaimsWithFuel fuel expression.parse_node) elements, [171])
          | .struct_value path fields => do
              let pathClaims ← collectPathClaimsWithFuel fuel expression.parse_node
                [47] [48, 49] path
              let fieldClaims ← collectMany
                (collectStructValueFieldClaimsWithFuel fuel container) fields
              pure (pathClaims <+> fieldClaims, [173])
          | .unary operator operand => do
              pure (← collectExprClaimsWithFuel fuel container operand,
                [unaryProduction operator])
          | .binary operator left right => do
              pure ((← collectExprClaimsWithFuel fuel container left) <+>
                (← collectExprClaimsWithFuel fuel container right),
                [binaryProduction operator])
          | .assign operator place value => do
              pure ((← collectExprClaimsWithFuel fuel container place) <+>
                (← collectExprClaimsWithFuel fuel container value),
                [assignProduction operator])
          | .call callee arguments => do
              pure ((← collectExprClaimsWithFuel fuel container callee) <+>
                (← collectMany
                  (collectExprClaimsWithFuel fuel container) arguments), [161])
          | .index base index => do
              pure ((← collectExprClaimsWithFuel fuel container base) <+>
                (← collectExprClaimsWithFuel fuel container index), [162])
          | .member base name => do
              pure ((← collectExprClaimsWithFuel fuel container base) <+>
                SurfaceClaims.name expression.parse_node name, [163])
        pure (children <+>
          SurfaceClaims.node expression.id expression.parse_node (some container) productions)
end

mutual
  def collectStmtClaimsWithFuel :
      Nat → ParseNodeId → SurfaceStmt → Option SurfaceClaims
    | 0, _, _ => none
    | fuel + 1, parent, statement => do
        let (children, productions) ← match statement.value with
          | .let_local name type initializer => do
              let typeClaims ← type.mapM
                (collectTypeClaimsWithFuel fuel statement.parse_node)
              let initializerClaims ← initializer.mapM
                (collectExprClaimsWithFuel fuel statement.parse_node)
              pure (SurfaceClaims.name statement.parse_node name <+> typeClaims.getD {} <+>
                initializerClaims.getD {}, [75])
          | .return_value value => do
              let valueClaims ← value.mapM
                (collectExprClaimsWithFuel fuel statement.parse_node)
              pure (valueClaims.getD {}, [76])
          | .if_then_else condition thenBody elseBody => do
              pure ((← collectExprClaimsWithFuel fuel statement.parse_node condition) <+>
                (← collectStmtsClaimsWithFuel fuel statement.parse_node thenBody) <+>
                (← collectStmtsClaimsWithFuel fuel statement.parse_node elseBody), [77])
          | .while_loop condition body => do
              pure ((← collectExprClaimsWithFuel fuel statement.parse_node condition) <+>
                (← collectStmtsClaimsWithFuel fuel statement.parse_node body), [80])
          | .block body => do
              pure (← collectStmtsClaimsWithFuel fuel statement.parse_node body, [84])
          | .expression expression => do
              pure (← collectExprClaimsWithFuel fuel statement.parse_node expression, [85])
          | .break_loop => pure ({}, [82])
          | .continue_loop => pure ({}, [83])
        pure (children <+>
          SurfaceClaims.node statement.id statement.parse_node (some parent) productions)

  def collectStmtsClaimsWithFuel :
      Nat → ParseNodeId → List SurfaceStmt → Option SurfaceClaims
    | 0, _, [] => some {}
    | 0, _, _ :: _ => none
    | _ + 1, _, [] => some {}
    | fuel + 1, parent, head :: tail => do
        pure ((← collectStmtClaimsWithFuel fuel parent head) <+>
          (← collectStmtsClaimsWithFuel fuel parent tail))
end

def collectParameterClaimsWithFuel
    (fuel : Nat) (parent : ParseNodeId)
    (parameter : SurfaceParameter) : Option SurfaceClaims := do
  let children := SurfaceClaims.name parameter.parse_node parameter.name <+>
    (← collectTypeClaimsWithFuel fuel parameter.parse_node parameter.type_expression)
  pure (children <+>
    SurfaceClaims.node parameter.id parameter.parse_node (some parent) [62])

def collectFunctionClaimsWithFuel
    (fuel : Nat) (owner : ParseNodeId)
    (function : SurfaceFunction) : Option SurfaceClaims := do
  let parameterClaims ← collectMany
    (collectParameterClaimsWithFuel fuel owner) function.parameters
  let returnClaims ← function.return_type.mapM (collectTypeClaimsWithFuel fuel owner)
  let bodyClaims ← collectStmtsClaimsWithFuel fuel owner function.body
  pure (SurfaceClaims.name owner function.name <+> parameterClaims <+>
    returnClaims.getD {} <+> bodyClaims)

def collectStructFieldClaimsWithFuel
    (fuel : Nat) (parent : ParseNodeId)
    (field : SurfaceStructField) : Option SurfaceClaims := do
  let children := SurfaceClaims.name field.parse_node field.name <+>
    (← collectTypeClaimsWithFuel fuel field.parse_node field.type_expression)
  pure (children <+>
    SurfaceClaims.node field.id field.parse_node (some parent) [261])

def collectStructClaimsWithFuel
    (fuel : Nat) (owner : ParseNodeId)
    (declaration : SurfaceStruct) : Option SurfaceClaims := do
  pure (SurfaceClaims.name owner declaration.name <+>
    (← collectMany
      (collectStructFieldClaimsWithFuel fuel owner) declaration.fields))

def itemProductions : SurfaceItemValue → Bool → List Nat
  | .module _, _ => [7]
  | .import_path _, _ => [6]
  | .function _, true => [3]
  | .function _, false => [4]
  | .constant _ _ _ _, true => [3]
  | .constant _ _ _ _, false => [207]
  | .type_alias _ _ _, true => [3]
  | .type_alias _ _ _, false => [8]
  | .structure _, true => [3]
  | .structure _, false => [257]

def collectItemClaimsWithFuel
    (fuel : Nat) (parent : ParseNodeId)
    (item : SurfaceItem) : Option SurfaceClaims := do
  let (children, isPublic) ← match item.value with
    | .module path =>
        pure (← collectPathClaimsWithFuel fuel item.parse_node [47] [48, 49] path, false)
    | .import_path path =>
        pure (← collectPathClaimsWithFuel fuel item.parse_node [47] [48, 49] path, false)
    | .function function =>
        pure (← collectFunctionClaimsWithFuel fuel item.parse_node function,
          function.is_public)
    | .constant name isPublic type value =>
        pure (SurfaceClaims.name item.parse_node name <+>
          (← collectTypeClaimsWithFuel fuel item.parse_node type) <+>
          (← collectExprClaimsWithFuel fuel item.parse_node value), isPublic)
    | .type_alias name isPublic target =>
        pure (SurfaceClaims.name item.parse_node name <+>
          (← collectTypeClaimsWithFuel fuel item.parse_node target), isPublic)
    | .structure declaration =>
        pure (← collectStructClaimsWithFuel fuel item.parse_node declaration,
          declaration.is_public)
  pure (children <+>
    SurfaceClaims.node item.id item.parse_node (some parent)
      (itemProductions item.value isPublic))

def collectSurfaceClaimsFrom
    (artifact : Artifact) (surface : SurfaceFile) : Option SurfaceClaims := do
  let fuel := artifact.tokens.length + 1
  let items ← collectMany
    (collectItemClaimsWithFuel fuel surface.parse_node) surface.value.items
  pure (items <+> SurfaceClaims.node surface.id surface.parse_node none [0])

def collectSurfaceClaims (artifact : Artifact) : Option SurfaceClaims := do
  collectSurfaceClaimsFrom artifact (← reconstructArtifactSurface artifact)

def tokenText? (artifact : Artifact) (tokenId : TokenId) : Option String := do
  let source ← artifact.sources[0]?
  let token ← artifact.tokens[tokenId]?
  if token.span.file != 0 || token.span.start > token.span.finish then none else
  let bytes ← decodeBytes source.bytes
  let tokenBytes := (bytes.drop token.span.start).take
    (token.span.finish - token.span.start)
  String.fromUTF8? (tokenBytes.map (fun byte => UInt8.ofNat byte.val)).toByteArray

inductive ParseNodeContainsTokenEvidence
    (nodes : List ParseNode) : ParseNodeId → TokenId → Prop
  | direct
      (lookup : nodes[nodeId]? = some node)
      (member : .token tokenId ∈ node.children) :
      ParseNodeContainsTokenEvidence nodes nodeId tokenId
  | nested
      (lookup : nodes[nodeId]? = some node)
      (member : .node childId ∈ node.children)
      (child : ParseNodeContainsTokenEvidence nodes childId tokenId) :
      ParseNodeContainsTokenEvidence nodes nodeId tokenId

def parseNodeContainsTokenWithFuel
    (nodes : List ParseNode) (tokenId : TokenId) : Nat → ParseNodeId → Bool
  | 0, _ => false
  | fuel + 1, nodeId =>
      match nodes[nodeId]? with
      | none => false
      | some node => node.children.any fun
          | .token childToken => childToken = tokenId
          | .node childNode =>
              parseNodeContainsTokenWithFuel nodes tokenId fuel childNode

theorem parseNodeContainsTokenWithFuel_sound
    {nodes : List ParseNode} {tokenId nodeId fuel : Nat}
    (accepted :
      parseNodeContainsTokenWithFuel nodes tokenId fuel nodeId = true) :
    ParseNodeContainsTokenEvidence nodes nodeId tokenId := by
  induction fuel generalizing nodeId with
  | zero => simp [parseNodeContainsTokenWithFuel] at accepted
  | succ fuel inductionHypothesis =>
      simp only [parseNodeContainsTokenWithFuel] at accepted
      cases lookup : nodes[nodeId]? with
      | none => simp [lookup] at accepted
      | some node =>
          simp only [lookup, List.any_eq_true] at accepted
          rcases accepted with ⟨child, member, childAccepted⟩
          cases child with
          | token childToken =>
              have sameToken : childToken = tokenId :=
                of_decide_eq_true childAccepted
              subst childToken
              exact .direct lookup member
          | node childNode =>
              exact .nested lookup member (inductionHypothesis childAccepted)

def parseNodeContainsToken
    (artifact : Artifact) (nodeId : ParseNodeId) (tokenId : TokenId) : Bool :=
  parseNodeContainsTokenWithFuel artifact.parse_nodes tokenId
    (artifact.parse_nodes.length + 1) nodeId

inductive ParseNodeContainsNodeEvidence
    (nodes : List ParseNode) : ParseNodeId → ParseNodeId → Prop
  | refl (lookup : nodes[nodeId]? = some node) :
      ParseNodeContainsNodeEvidence nodes nodeId nodeId
  | nested
      (lookup : nodes[ancestor]? = some node)
      (member : .node childId ∈ node.children)
      (child : ParseNodeContainsNodeEvidence nodes childId descendant) :
      ParseNodeContainsNodeEvidence nodes ancestor descendant

def parseNodeContainsNodeWithFuel
    (nodes : List ParseNode) (descendant : ParseNodeId) : Nat → ParseNodeId → Bool
  | 0, _ => false
  | fuel + 1, ancestor =>
      match nodes[ancestor]? with
      | none => false
      | some node =>
          if ancestor = descendant then true else
          node.children.any fun
            | .token _ => false
            | .node child =>
                parseNodeContainsNodeWithFuel nodes descendant fuel child

theorem parseNodeContainsNodeWithFuel_sound
    {nodes : List ParseNode} {ancestor descendant fuel : Nat}
    (accepted :
      parseNodeContainsNodeWithFuel nodes descendant fuel ancestor = true) :
    ParseNodeContainsNodeEvidence nodes ancestor descendant := by
  induction fuel generalizing ancestor with
  | zero => simp [parseNodeContainsNodeWithFuel] at accepted
  | succ fuel inductionHypothesis =>
      simp only [parseNodeContainsNodeWithFuel] at accepted
      cases lookup : nodes[ancestor]? with
      | none => simp [lookup] at accepted
      | some node =>
          by_cases same : ancestor = descendant
          · subst descendant
            exact .refl lookup
          · simp only [lookup, same, ↓reduceIte, List.any_eq_true] at accepted
            rcases accepted with ⟨child, member, childAccepted⟩
            cases child with
            | token _ => simp at childAccepted
            | node childNode =>
                exact .nested lookup member (inductionHypothesis childAccepted)

def parseNodeContainsNode
    (artifact : Artifact) (ancestor descendant : ParseNodeId) : Bool :=
  parseNodeContainsNodeWithFuel artifact.parse_nodes descendant
    (artifact.parse_nodes.length + 1) ancestor

structure SpellingClaimMatches
    (artifact : Artifact) (claim : SpellingClaim) : Prop where
  exactText : tokenText? artifact claim.token = some claim.text
  contained : ParseNodeContainsTokenEvidence
    artifact.parse_nodes claim.owner claim.token

def SurfaceNodeClaimMatches
    (artifact : Artifact) (claim : SurfaceNodeClaim) : Prop :=
  ∃ node,
    artifact.parse_nodes[claim.parseNode]? = some node ∧
    node.production ∈ claim.allowedProductions ∧
    match claim.containingParseNode with
    | none => True
    | some container => ParseNodeContainsNodeEvidence
        artifact.parse_nodes container claim.parseNode

def spellingClaimValid (artifact : Artifact) (claim : SpellingClaim) : Bool :=
  tokenText? artifact claim.token = some claim.text &&
    parseNodeContainsToken artifact claim.owner claim.token

theorem spellingClaimValid_sound
    {artifact : Artifact} {claim : SpellingClaim}
    (accepted : spellingClaimValid artifact claim = true) :
    SpellingClaimMatches artifact claim := by
  simp only [spellingClaimValid, Bool.and_eq_true] at accepted
  exact {
    exactText := of_decide_eq_true accepted.1
    contained := parseNodeContainsTokenWithFuel_sound accepted.2
  }

def nodeClaimValid (artifact : Artifact) (claim : SurfaceNodeClaim) : Bool :=
  match artifact.parse_nodes[claim.parseNode]? with
  | none => false
  | some node =>
      claim.allowedProductions.contains node.production &&
        match claim.containingParseNode with
        | none => true
        | some parent => parseNodeContainsNode artifact parent claim.parseNode

theorem nodeClaimValid_sound
    {artifact : Artifact} {claim : SurfaceNodeClaim}
    (accepted : nodeClaimValid artifact claim = true) :
    SurfaceNodeClaimMatches artifact claim := by
  unfold nodeClaimValid at accepted
  cases lookup : artifact.parse_nodes[claim.parseNode]? with
  | none => simp [lookup] at accepted
  | some node =>
      simp only [lookup, Bool.and_eq_true] at accepted
      rcases accepted with ⟨productionAccepted, containmentAccepted⟩
      refine ⟨node, lookup, ?_, ?_⟩
      · exact of_decide_eq_true
          (by simpa only [List.contains_eq_mem] using productionAccepted)
      · cases container : claim.containingParseNode with
        | none => trivial
        | some container =>
            simp only [container] at containmentAccepted
            exact parseNodeContainsNodeWithFuel_sound containmentAccepted

def tokenCarriesSurfaceSpelling (token : Token) : Bool :=
  token.kind = 1 || token.kind = 2 || token.kind = 32 ||
    token.kind = 33 || token.kind = 34

def expectedSpellingTokens (artifact : Artifact) : List TokenId :=
  artifact.tokens.zipIdx.filterMap fun (token, id) =>
    if tokenCarriesSurfaceSpelling token then some id else none

def spellingCoverageValid (artifact : Artifact) (claims : SurfaceClaims) : Bool :=
  let actual := claims.spellings.map (·.token)
  let expected := expectedSpellingTokens artifact
  actual.length = expected.length &&
    actual.all expected.contains && expected.all actual.contains

def surfaceClaimsValid (artifact : Artifact) (claims : SurfaceClaims) : Bool :=
  claims.nodes.map (·.id) == List.range claims.nodes.length &&
  claims.nodes.all (nodeClaimValid artifact) &&
  claims.spellings.all (spellingClaimValid artifact) &&
  spellingCoverageValid artifact claims

structure SurfaceClaimsMatch
    (artifact : Artifact) (claims : SurfaceClaims) : Prop where
  denseIds : claims.nodes.map (·.id) = List.range claims.nodes.length
  nodes : ∀ claim ∈ claims.nodes, SurfaceNodeClaimMatches artifact claim
  spellings : ∀ claim ∈ claims.spellings, SpellingClaimMatches artifact claim
  spellingCoverage : spellingCoverageValid artifact claims = true

theorem surfaceClaimsValid_sound
    {artifact : Artifact} {claims : SurfaceClaims}
    (accepted : surfaceClaimsValid artifact claims = true) :
    SurfaceClaimsMatch artifact claims := by
  simp only [surfaceClaimsValid, Bool.and_eq_true, List.all_eq_true] at accepted
  rcases accepted with ⟨⟨⟨denseIds, nodesAccepted⟩, spellingsAccepted⟩,
    spellingCoverage⟩
  exact {
    denseIds := eq_of_beq denseIds
    nodes := fun claim member => nodeClaimValid_sound (nodesAccepted claim member)
    spellings := fun claim member =>
      spellingClaimValid_sound (spellingsAccepted claim member)
    spellingCoverage
  }

def checkSurfaceArtifact (artifact : Artifact) : Bool :=
  checkParseArtifact artifact &&
  surfaceReconstructionMatches artifact &&
  match collectSurfaceClaims artifact, decodeReconstructedSurface artifact with
  | some claims, some _ => surfaceClaimsValid artifact claims
  | _, _ => false

/-- Semantic statement certified by the first Surface checker. It exposes a
    real formal `Surface.File`, dense semantic identity, exact source
    spellings, construct-to-grammar-production agreement, and grammatical
    containment for every semantic node. Grammatical containment deliberately
    does not pretend that semantic parenthood is parse-tree parenthood: folded
    precedence expressions are assembled from sibling grammar nodes. The
    grammar-aware reconstruction computes those folds independently, and this
    proposition exposes only the reconstructed Surface program to subsequent
    semantic checking. -/
def SurfaceArtifactValid (artifact : Artifact) : Prop :=
  ParseArtifactValid artifact ∧
  surfaceReconstructionMatches artifact = true ∧
  ∃ claims surface,
    collectSurfaceClaims artifact = some claims ∧
    decodeReconstructedSurface artifact = some surface ∧
    SurfaceClaimsMatch artifact claims

theorem checkSurfaceArtifact_sound {artifact : Artifact}
    (accepted : checkSurfaceArtifact artifact = true) :
    SurfaceArtifactValid artifact := by
  unfold checkSurfaceArtifact at accepted
  simp only [Bool.and_eq_true] at accepted
  rcases accepted with ⟨⟨parseAccepted, reconstructionAccepted⟩, surfaceAccepted⟩
  have parseValid := checkParseArtifact_sound parseAccepted
  cases claimsResult : collectSurfaceClaims artifact with
  | none => simp [claimsResult] at surfaceAccepted
  | some claims =>
      cases surfaceResult : decodeReconstructedSurface artifact with
      | none => simp [claimsResult, surfaceResult] at surfaceAccepted
      | some surface =>
          exact ⟨parseValid, reconstructionAccepted, claims, surface,
            claimsResult, surfaceResult,
            surfaceClaimsValid_sound
              (by simpa [claimsResult, surfaceResult] using surfaceAccepted)⟩

end Lanius.Extraction
