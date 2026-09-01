import Lanius.Extraction.ParseChecker
import Lanius.Extraction.SurfaceReconstruct

namespace Lanius.Extraction

open Lanius

structure SpellingClaim where
  owner : ParseNodeId
  token : TokenId
  text : String
deriving BEq, Repr, Lean.ToExpr

structure SurfaceNodeClaim where
  id : SurfaceNodeId
  parseNode : ParseNodeId
  containingParseNode : Option ParseNodeId
  allowedProductions : List Nat
deriving BEq, Repr, Lean.ToExpr

structure SurfaceClaims where
  nodes : List SurfaceNodeClaim := []
  spellings : List SpellingClaim := []
deriving BEq, Repr, Lean.ToExpr

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

/-! ## Chunk-backed Surface-claim checking

`parse_nodes` is intentionally a list in the public artifact format, but a
linear lookup for every Surface claim makes kernel evaluation quadratic on a
large source file.  The optional chunk table is already checked to flatten to
that exact list.  The following checker uses it as a computational index and
then transports acceptance back to the public list-based predicates.
-/

theorem artifactNode?_eq_getElem {artifact : Artifact}
    (chunksMatch : match artifact.parse_node_chunks with
      | none => True
      | some chunks => chunks.flatten = artifact.parse_nodes)
    (nodeId : ParseNodeId) :
    artifactNode? artifact nodeId = artifact.parse_nodes[nodeId]? := by
  unfold artifactNode?
  cases chunksFound : artifact.parse_node_chunks with
  | none => rfl
  | some chunks =>
      simp only [chunksFound] at chunksMatch ⊢
      rw [chunkLookup_eq_flatten, chunksMatch]

theorem getElem?_eq_head?_drop (values : List α) (index : Nat) :
    values[index]? = (values.drop index).head? := by
  induction values generalizing index with
  | nil => simp
  | cons value values inductionHypothesis =>
      cases index with
      | zero => rfl
      | succ index => simpa using inductionHypothesis index

def chunkSlice (chunks : List (List α)) (start : Nat) : Nat → List α
  | 0 => []
  | count + 1 =>
      match chunkLookup chunks start with
      | none => []
      | some value => value :: chunkSlice chunks (start + 1) count

theorem chunkSlice_eq_flatten (chunks : List (List α)) (start count : Nat) :
    chunkSlice chunks start count = (chunks.flatten.drop start).take count := by
  induction count generalizing start with
  | zero => simp [chunkSlice]
  | succ count inductionHypothesis =>
      unfold chunkSlice
      rw [chunkLookup_eq_flatten, getElem?_eq_head?_drop]
      cases dropped : chunks.flatten.drop start with
      | nil => simp
      | cons value rest =>
          simp only [List.head?_cons, List.take_succ_cons]
          rw [inductionHypothesis]
          have nextDrop : chunks.flatten.drop (start + 1) = rest := by
            calc
              chunks.flatten.drop (start + 1) =
                  (chunks.flatten.drop start).drop 1 := by
                    rw [List.drop_drop]
              _ = rest := by simp [dropped]
          rw [nextDrop]

def uniformChunkLookup (width : Nat) (chunks : List (List α))
    (index : Nat) : Option α :=
  match chunks with
  | [] => none
  | chunk :: chunks =>
      if index < width then chunk[index]?
      else uniformChunkLookup width chunks (index - width)

theorem uniformChunkLookup_eq_chunkLookup
    (width : Nat) (chunks : List (List α))
    (uniform : ∀ chunk ∈ chunks, chunk.length = width)
    (index : Nat) :
    uniformChunkLookup width chunks index = chunkLookup chunks index := by
  induction chunks generalizing index with
  | nil => rfl
  | cons chunk chunks inductionHypothesis =>
      unfold uniformChunkLookup chunkLookup
      have headLength : chunk.length = width := uniform chunk (by simp)
      rw [headLength]
      by_cases inHead : index < width
      · simp [inHead]
      · simp only [inHead, ↓reduceIte]
        apply inductionHypothesis
        intro tail member
        exact uniform tail (by simp [member])

def uniformChunkSlice (width : Nat) (chunks : List (List α))
    (start : Nat) : Nat → List α
  | 0 => []
  | count + 1 =>
      match uniformChunkLookup width chunks start with
      | none => []
      | some value => value :: uniformChunkSlice width chunks (start + 1) count

theorem uniformChunkSlice_eq_chunkSlice
    (width : Nat) (chunks : List (List α))
    (uniform : ∀ chunk ∈ chunks, chunk.length = width)
    (start count : Nat) :
    uniformChunkSlice width chunks start count = chunkSlice chunks start count := by
  induction count generalizing start with
  | zero => rfl
  | succ count inductionHypothesis =>
      simp only [uniformChunkSlice, chunkSlice,
        uniformChunkLookup_eq_chunkLookup width chunks uniform]
      cases lookup : chunkLookup chunks start with
      | none => rfl
      | some value => simp [lookup, inductionHypothesis]

inductive ChunkTree (α : Type) where
  | leaf (values : List α)
  | branch (leftLength : Nat) (left right : ChunkTree α)
deriving Repr, Lean.ToExpr

def ChunkTree.flatten : ChunkTree α → List α
  | .leaf values => values
  | .branch _ left right => left.flatten ++ right.flatten

def ChunkTree.WellFormed : ChunkTree α → Prop
  | .leaf _ => True
  | .branch leftLength left right =>
      leftLength = left.flatten.length ∧ left.WellFormed ∧ right.WellFormed

def ChunkTree.lookup : ChunkTree α → Nat → Option α
  | .leaf values, index => values[index]?
  | .branch leftLength left right, index =>
      if index < leftLength then left.lookup index
      else right.lookup (index - leftLength)

theorem ChunkTree.lookup_eq_flatten (tree : ChunkTree α)
    (wellFormed : tree.WellFormed) (index : Nat) :
    tree.lookup index = tree.flatten[index]? := by
  induction tree generalizing index with
  | leaf values => rfl
  | branch leftLength left right leftHypothesis rightHypothesis =>
      rcases wellFormed with ⟨leftLengthEq, leftWellFormed, rightWellFormed⟩
      unfold ChunkTree.lookup ChunkTree.flatten
      rw [leftLengthEq]
      by_cases inLeft : index < left.flatten.length
      · rw [if_pos inLeft, leftHypothesis leftWellFormed]
        exact (List.getElem?_append_left inLeft).symm
      · rw [if_neg inLeft, rightHypothesis rightWellFormed]
        exact (List.getElem?_append_right (by omega)).symm

def ChunkTree.slice (tree : ChunkTree α) (start : Nat) : Nat → List α
  | 0 => []
  | count + 1 =>
      match tree.lookup start with
      | none => []
      | some value => value :: tree.slice (start + 1) count

theorem ChunkTree.slice_eq_flatten (tree : ChunkTree α)
    (wellFormed : tree.WellFormed) (start count : Nat) :
    tree.slice start count = (tree.flatten.drop start).take count := by
  induction count generalizing start with
  | zero => simp [ChunkTree.slice]
  | succ count inductionHypothesis =>
      unfold ChunkTree.slice
      rw [tree.lookup_eq_flatten wellFormed, getElem?_eq_head?_drop]
      cases dropped : tree.flatten.drop start with
      | nil => simp
      | cons value rest =>
          simp only [List.head?_cons, List.take_succ_cons]
          rw [inductionHypothesis]
          have nextDrop : tree.flatten.drop (start + 1) = rest := by
            calc
              tree.flatten.drop (start + 1) =
                  (tree.flatten.drop start).drop 1 := by rw [List.drop_drop]
              _ = rest := by simp [dropped]
          rw [nextDrop]

def tokenTextWithTrees? (artifact : Artifact)
    (tokenTree : ChunkTree Token) (sourceByteTree : ChunkTree (Fin 256))
    (tokenId : TokenId) : Option String := do
  let _source ← artifact.sources[0]?
  let token ← tokenTree.lookup tokenId
  if token.span.file != 0 || token.span.start > token.span.finish then none else
  let tokenBytes := sourceByteTree.slice token.span.start
    (token.span.finish - token.span.start)
  String.fromUTF8?
    (tokenBytes.map (fun byte => UInt8.ofNat byte.val)).toByteArray

theorem tokenTextWithTrees_eq {artifact : Artifact}
    {tokenTree : ChunkTree Token} {sourceByteTree : ChunkTree (Fin 256)}
    (tokensWellFormed : tokenTree.WellFormed)
    (tokensMatch : tokenTree.flatten = artifact.tokens)
    (sourceWellFormed : sourceByteTree.WellFormed)
    (sourceBytesMatch : ∀ source, artifact.sources[0]? = some source →
      decodeBytes source.bytes = some sourceByteTree.flatten)
    (tokenId : TokenId) :
    tokenTextWithTrees? artifact tokenTree sourceByteTree tokenId =
      tokenText? artifact tokenId := by
  unfold tokenTextWithTrees? tokenText?
  cases sourceFound : artifact.sources[0]? with
  | none => simp [sourceFound]
  | some source =>
      dsimp
      rw [tokenTree.lookup_eq_flatten tokensWellFormed, tokensMatch]
      cases tokenFound : artifact.tokens[tokenId]? with
      | none => simp [tokenFound]
      | some token =>
          dsimp
          by_cases invalid : token.span.file ≠ 0 ∨
              token.span.finish < token.span.start
          · simp [invalid]
          · rw [sourceBytesMatch source sourceFound]
            simp only [Option.bind_some]
            rw [sourceByteTree.slice_eq_flatten sourceWellFormed]

def tokenTextWithChunks? (artifact : Artifact)
    (tokenChunks : List (List Token)) (sourceByteChunks : List (List (Fin 256)))
    (tokenId : TokenId) : Option String := do
  let _source ← artifact.sources[0]?
  let token ← chunkLookup tokenChunks tokenId
  if token.span.file != 0 || token.span.start > token.span.finish then none else
  let tokenBytes := chunkSlice sourceByteChunks token.span.start
    (token.span.finish - token.span.start)
  String.fromUTF8?
    (tokenBytes.map (fun byte => UInt8.ofNat byte.val)).toByteArray

def tokenTextWithUniformSourceChunks? (artifact : Artifact)
    (tokenChunks : List (List Token)) (sourceChunkWidth : Nat)
    (sourceByteChunks : List (List (Fin 256)))
    (tokenId : TokenId) : Option String := do
  let _source ← artifact.sources[0]?
  let token ← chunkLookup tokenChunks tokenId
  if token.span.file != 0 || token.span.start > token.span.finish then none else
  let tokenBytes := uniformChunkSlice sourceChunkWidth sourceByteChunks
    token.span.start (token.span.finish - token.span.start)
  String.fromUTF8?
    (tokenBytes.map (fun byte => UInt8.ofNat byte.val)).toByteArray

def tokenTextWithUniformChunks? (artifact : Artifact)
    (tokenChunkWidth : Nat) (tokenChunks : List (List Token))
    (sourceChunkWidth : Nat) (sourceByteChunks : List (List (Fin 256)))
    (tokenId : TokenId) : Option String := do
  let _source ← artifact.sources[0]?
  let token ← uniformChunkLookup tokenChunkWidth tokenChunks tokenId
  if token.span.file != 0 || token.span.start > token.span.finish then none else
  let tokenBytes := uniformChunkSlice sourceChunkWidth sourceByteChunks
    token.span.start (token.span.finish - token.span.start)
  String.fromUTF8?
    (tokenBytes.map (fun byte => UInt8.ofNat byte.val)).toByteArray

theorem tokenTextWithUniformChunks_eq {artifact : Artifact}
    {tokenChunkWidth tokenLimit : Nat} {tokenChunks : List (List Token)}
    {sourceChunkWidth : Nat} {sourceByteChunks : List (List (Fin 256))}
    (tokensUniform : ∀ chunk ∈ tokenChunks,
      chunk.length = tokenChunkWidth)
    (tokensMatch : tokenChunks.flatten.take tokenLimit = artifact.tokens)
    (sourceUniform : ∀ chunk ∈ sourceByteChunks,
      chunk.length = sourceChunkWidth)
    (sourceBytesMatch : ∀ source, artifact.sources[0]? = some source →
      decodeBytes source.bytes = some sourceByteChunks.flatten)
    (tokenId : TokenId) (tokenIdBound : tokenId < tokenLimit) :
    tokenTextWithUniformChunks? artifact tokenChunkWidth tokenChunks
        sourceChunkWidth sourceByteChunks tokenId = tokenText? artifact tokenId := by
  unfold tokenTextWithUniformChunks? tokenText?
  cases sourceFound : artifact.sources[0]? with
  | none => simp [sourceFound]
  | some source =>
      dsimp
      rw [uniformChunkLookup_eq_chunkLookup tokenChunkWidth tokenChunks
        tokensUniform, chunkLookup_eq_flatten]
      rw [← List.getElem?_take_of_lt tokenIdBound, tokensMatch]
      cases tokenFound : artifact.tokens[tokenId]? with
      | none => simp [tokenFound]
      | some token =>
          dsimp
          by_cases invalid : token.span.file ≠ 0 ∨
              token.span.finish < token.span.start
          · simp [invalid]
          · rw [sourceBytesMatch source sourceFound]
            simp only [Option.bind_some]
            rw [uniformChunkSlice_eq_chunkSlice sourceChunkWidth
              sourceByteChunks sourceUniform, chunkSlice_eq_flatten]

theorem tokenTextWithUniformSourceChunks_eq
    {artifact : Artifact} {tokenChunks : List (List Token)}
    {sourceChunkWidth : Nat} {sourceByteChunks : List (List (Fin 256))}
    (uniform : ∀ chunk ∈ sourceByteChunks,
      chunk.length = sourceChunkWidth)
    (tokenId : TokenId) :
    tokenTextWithUniformSourceChunks? artifact tokenChunks sourceChunkWidth
        sourceByteChunks tokenId =
      tokenTextWithChunks? artifact tokenChunks sourceByteChunks tokenId := by
  unfold tokenTextWithUniformSourceChunks? tokenTextWithChunks?
  cases artifact.sources[0]? <;> simp
  cases chunkLookup tokenChunks tokenId with
  | none => rfl
  | some token =>
      by_cases invalid : token.span.file ≠ 0 ∨
          token.span.finish < token.span.start
      · simp [invalid]
      · simp [invalid, uniformChunkSlice_eq_chunkSlice
          sourceChunkWidth sourceByteChunks uniform]

theorem tokenTextWithChunks_eq {artifact : Artifact}
    {tokenChunks : List (List Token)} {sourceByteChunks : List (List (Fin 256))}
    (tokensMatch : tokenChunks.flatten = artifact.tokens)
    (sourceBytesMatch : ∀ source, artifact.sources[0]? = some source →
      decodeBytes source.bytes = some sourceByteChunks.flatten)
    (tokenId : TokenId) :
    tokenTextWithChunks? artifact tokenChunks sourceByteChunks tokenId =
      tokenText? artifact tokenId := by
  unfold tokenTextWithChunks? tokenText?
  cases sourceFound : artifact.sources[0]? with
  | none => simp [sourceFound]
  | some source =>
      simp only [sourceFound, Option.bind_some]
      rw [chunkLookup_eq_flatten, tokensMatch]
      cases tokenFound : artifact.tokens[tokenId]? with
      | none => simp [tokenFound]
      | some token =>
          dsimp
          by_cases invalid : token.span.file ≠ 0 ∨
              token.span.finish < token.span.start
          · simp [invalid]
          · rw [sourceBytesMatch source sourceFound]
            simp only [Option.bind_some]
            rw [chunkSlice_eq_flatten]

def parseNodeContainsTokenCachedWithFuel
    (artifact : Artifact) (tokenId : TokenId) : Nat → ParseNodeId → Bool
  | 0, _ => false
  | fuel + 1, nodeId =>
      match artifactNode? artifact nodeId with
      | none => false
      | some node => node.children.any fun
          | .token childToken => childToken = tokenId
          | .node childNode =>
              parseNodeContainsTokenCachedWithFuel artifact tokenId fuel childNode

theorem parseNodeContainsTokenCachedWithFuel_eq
    {artifact : Artifact}
    (chunksMatch : match artifact.parse_node_chunks with
      | none => True
      | some chunks => chunks.flatten = artifact.parse_nodes)
    (tokenId fuel nodeId : Nat) :
    parseNodeContainsTokenCachedWithFuel artifact tokenId fuel nodeId =
      parseNodeContainsTokenWithFuel artifact.parse_nodes tokenId fuel nodeId := by
  induction fuel generalizing nodeId with
  | zero => rfl
  | succ fuel inductionHypothesis =>
      simp only [parseNodeContainsTokenCachedWithFuel,
        parseNodeContainsTokenWithFuel,
        artifactNode?_eq_getElem chunksMatch]
      cases lookup : artifact.parse_nodes[nodeId]? with
      | none => rfl
      | some node =>
          simp only [lookup]
          congr 1
          funext child
          cases child <;> simp [inductionHypothesis]

def parseNodeContainsTokenCached
    (artifact : Artifact) (nodeId : ParseNodeId) (tokenId : TokenId) : Bool :=
  parseNodeContainsTokenCachedWithFuel artifact tokenId
    (artifact.parse_nodes.length + 1) nodeId

def parseNodeContainsNodeCachedWithFuel
    (artifact : Artifact) (descendant : ParseNodeId) : Nat → ParseNodeId → Bool
  | 0, _ => false
  | fuel + 1, ancestor =>
      match artifactNode? artifact ancestor with
      | none => false
      | some node =>
          if ancestor = descendant then true else
          node.children.any fun
            | .token _ => false
            | .node child =>
                parseNodeContainsNodeCachedWithFuel artifact descendant fuel child

theorem parseNodeContainsNodeCachedWithFuel_eq
    {artifact : Artifact}
    (chunksMatch : match artifact.parse_node_chunks with
      | none => True
      | some chunks => chunks.flatten = artifact.parse_nodes)
    (descendant fuel ancestor : Nat) :
    parseNodeContainsNodeCachedWithFuel artifact descendant fuel ancestor =
      parseNodeContainsNodeWithFuel artifact.parse_nodes descendant fuel ancestor := by
  induction fuel generalizing ancestor with
  | zero => rfl
  | succ fuel inductionHypothesis =>
      simp only [parseNodeContainsNodeCachedWithFuel,
        parseNodeContainsNodeWithFuel,
        artifactNode?_eq_getElem chunksMatch]
      cases lookup : artifact.parse_nodes[ancestor]? with
      | none => rfl
      | some node =>
          simp only [lookup]
          by_cases same : ancestor = descendant
          · simp [same]
          · simp only [same, ↓reduceIte]
            congr 1
            funext child
            cases child <;> simp [inductionHypothesis]

def parseNodeContainsNodeCached
    (artifact : Artifact) (ancestor descendant : ParseNodeId) : Bool :=
  parseNodeContainsNodeCachedWithFuel artifact descendant
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

def spellingClaimValidCached (artifact : Artifact) (claim : SpellingClaim) : Bool :=
  tokenText? artifact claim.token = some claim.text &&
    parseNodeContainsTokenCached artifact claim.owner claim.token

def nodeClaimValidCached (artifact : Artifact) (claim : SurfaceNodeClaim) : Bool :=
  match artifactNode? artifact claim.parseNode with
  | none => false
  | some node =>
      claim.allowedProductions.contains node.production &&
        match claim.containingParseNode with
        | none => true
        | some parent =>
            parseNodeContainsNodeCached artifact parent claim.parseNode

theorem spellingClaimValidCached_eq {artifact : Artifact}
    (chunksMatch : match artifact.parse_node_chunks with
      | none => True
      | some chunks => chunks.flatten = artifact.parse_nodes)
    (claim : SpellingClaim) :
    spellingClaimValidCached artifact claim = spellingClaimValid artifact claim := by
  simp [spellingClaimValidCached, spellingClaimValid,
    parseNodeContainsTokenCached, parseNodeContainsToken,
    parseNodeContainsTokenCachedWithFuel_eq chunksMatch]

theorem nodeClaimValidCached_eq {artifact : Artifact}
    (chunksMatch : match artifact.parse_node_chunks with
      | none => True
      | some chunks => chunks.flatten = artifact.parse_nodes)
    (claim : SurfaceNodeClaim) :
    nodeClaimValidCached artifact claim = nodeClaimValid artifact claim := by
  unfold nodeClaimValidCached nodeClaimValid
  rw [artifactNode?_eq_getElem chunksMatch]
  cases lookup : artifact.parse_nodes[claim.parseNode]? with
  | none => rfl
  | some node =>
      simp only [lookup]
      cases claim.containingParseNode with
      | none => rfl
      | some parent =>
          simp [parseNodeContainsNodeCached, parseNodeContainsNode,
            parseNodeContainsNodeCachedWithFuel_eq chunksMatch]

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

def surfaceClaimsValidCached (artifact : Artifact) (claims : SurfaceClaims) : Bool :=
  claims.nodes.map (·.id) == List.range claims.nodes.length &&
  claims.nodes.all (nodeClaimValidCached artifact) &&
  claims.spellings.all (spellingClaimValidCached artifact) &&
  spellingCoverageValid artifact claims

theorem surfaceClaimsValidCached_eq {artifact : Artifact}
    (chunksMatch : match artifact.parse_node_chunks with
      | none => True
      | some chunks => chunks.flatten = artifact.parse_nodes)
    (claims : SurfaceClaims) :
    surfaceClaimsValidCached artifact claims = surfaceClaimsValid artifact claims := by
  have nodesEq : claims.nodes.all (nodeClaimValidCached artifact) =
      claims.nodes.all (nodeClaimValid artifact) := by
    apply List.all_congr rfl
    intro claim
    exact nodeClaimValidCached_eq chunksMatch claim
  have spellingsEq : claims.spellings.all (spellingClaimValidCached artifact) =
      claims.spellings.all (spellingClaimValid artifact) := by
    apply List.all_congr rfl
    intro claim
    exact spellingClaimValidCached_eq chunksMatch claim
  simp only [surfaceClaimsValidCached, surfaceClaimsValid, nodesEq, spellingsEq]

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

theorem surfaceClaimsValidCached_sound {artifact : Artifact} {claims : SurfaceClaims}
    (chunksMatch : match artifact.parse_node_chunks with
      | none => True
      | some chunks => chunks.flatten = artifact.parse_nodes)
    (accepted : surfaceClaimsValidCached artifact claims = true) :
    SurfaceClaimsMatch artifact claims := by
  apply surfaceClaimsValid_sound
  rw [← surfaceClaimsValidCached_eq chunksMatch]
  exact accepted

def checkSurfaceArtifact (artifact : Artifact) : Bool :=
  checkParseArtifact artifact &&
  parseNodeChunksMatch artifact &&
  match collectSurfaceClaims artifact, decodeReconstructedSurface artifact with
  | some claims, some _ => surfaceClaimsValidCached artifact claims
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
  (match artifact.parse_node_chunks with
    | none => True
    | some chunks => chunks.flatten = artifact.parse_nodes) ∧
  ∃ claims surface,
    collectSurfaceClaims artifact = some claims ∧
    decodeReconstructedSurface artifact = some surface ∧
    SurfaceClaimsMatch artifact claims

theorem checkSurfaceArtifact_sound {artifact : Artifact}
    (accepted : checkSurfaceArtifact artifact = true) :
    SurfaceArtifactValid artifact := by
  unfold checkSurfaceArtifact at accepted
  simp only [Bool.and_eq_true] at accepted
  rcases accepted with
    ⟨⟨parseAccepted, chunksAccepted⟩, surfaceAccepted⟩
  have parseValid := checkParseArtifact_sound parseAccepted
  cases claimsResult : collectSurfaceClaims artifact with
  | none => simp [claimsResult] at surfaceAccepted
  | some claims =>
      cases surfaceResult : decodeReconstructedSurface artifact with
      | none => simp [claimsResult, surfaceResult] at surfaceAccepted
      | some surface =>
          exact ⟨parseValid, parseNodeChunksMatch_sound chunksAccepted,
            claims, surface, claimsResult, surfaceResult,
            surfaceClaimsValidCached_sound
              (parseNodeChunksMatch_sound chunksAccepted)
              (by simpa [claimsResult, surfaceResult] using surfaceAccepted)⟩

/-! ## Single-reconstruction checked surface

The legacy Boolean checker above is retained as a stable public interface.
Pack checking needs the reconstructed values again, however, and recomputing
them at every layer is prohibitively expensive under kernel reduction.  This
dependent result exposes the values produced by the same checks so later pack
phases can reuse them without trusting the exported Surface proposal. -/

structure CheckedSurfaceArtifact (artifact : Artifact) where
  reconstructed : SurfaceFile
  reconstructedFound : reconstructArtifactSurface artifact = some reconstructed
  claims : SurfaceClaims
  claimsFound : collectSurfaceClaims artifact = some claims
  surface : Lanius.Surface.File
  surfaceFound : decodeReconstructedSurface artifact = some surface
  valid : SurfaceArtifactValid artifact

def checkSurfaceArtifactCached? (artifact : Artifact) :
    Option (CheckedSurfaceArtifact artifact) := do
  if parseAccepted : checkParseArtifact artifact = true then
    if chunksAccepted : parseNodeChunksMatch artifact = true then
      match reconstructedFound : reconstructArtifactSurface artifact with
      | none => none
      | some reconstructed =>
          match claimsFound :
              collectSurfaceClaimsFrom artifact reconstructed with
          | none => none
          | some claims =>
              match surfaceFound : decodeSurfaceFile
                  (artifact.parse_nodes.length + 1) reconstructed with
                | none => none
                | some surface =>
                    if claimsAccepted :
                        surfaceClaimsValidCached artifact claims = true then
                      have collected :
                          collectSurfaceClaims artifact = some claims := by
                        simp [collectSurfaceClaims, reconstructedFound,
                          claimsFound]
                      have decoded :
                          decodeReconstructedSurface artifact = some surface := by
                        simp [decodeReconstructedSurface, reconstructedFound,
                          surfaceFound]
                      pure {
                        reconstructed
                        reconstructedFound
                        claims
                        claimsFound := collected
                        surface
                        surfaceFound := decoded
                        valid := ⟨checkParseArtifact_sound parseAccepted,
                          parseNodeChunksMatch_sound chunksAccepted,
                          claims, surface, collected, decoded,
                          surfaceClaimsValidCached_sound
                            (parseNodeChunksMatch_sound chunksAccepted)
                            claimsAccepted⟩
                      }
                    else none
    else none
  else none

theorem checkSurfaceArtifactCached_sound {artifact : Artifact}
    {checked : CheckedSurfaceArtifact artifact}
    (_accepted : checkSurfaceArtifactCached? artifact = some checked) :
    SurfaceArtifactValid artifact := by
  exact checked.valid

end Lanius.Extraction
