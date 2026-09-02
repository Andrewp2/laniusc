import Lanius.Extraction.ParseChecker
import Lanius.Extraction.SurfaceReconstruct

namespace Lanius.Extraction

open Lanius

structure SpellingClaim where
  owner : ParseNodeId
  token : TokenId
  text : String
deriving BEq, DecidableEq, Repr, Lean.ToExpr

structure SurfaceNodeClaim where
  id : SurfaceNodeId
  parseNode : ParseNodeId
  containingParseNode : Option ParseNodeId
  allowedProductions : List Nat
deriving BEq, DecidableEq, Repr, Lean.ToExpr

structure SurfaceClaims where
  nodes : List SurfaceNodeClaim := []
  spellings : List SpellingClaim := []
deriving BEq, DecidableEq, Repr, Lean.ToExpr

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

def collectSurfaceClaimsView (artifact : Artifact) (view : ArtifactView artifact) :
    Option SurfaceClaims := do
  collectSurfaceClaimsFrom artifact (← reconstructArtifactSurfaceView artifact view)

def decodeReconstructedSurfaceView (artifact : Artifact)
    (view : ArtifactView artifact) : Option Lanius.Surface.File := do
  let reconstructed ← reconstructArtifactSurfaceView artifact view
  decodeSurfaceFile (artifact.parse_nodes.length + 1) reconstructed

theorem collectSurfaceClaimsView_eq (artifact : Artifact)
    (view : ArtifactView artifact) :
    collectSurfaceClaimsView artifact view = collectSurfaceClaims artifact := by
  simp [collectSurfaceClaimsView, collectSurfaceClaims,
    reconstructArtifactSurfaceView_eq artifact view]

theorem decodeReconstructedSurfaceView_eq (artifact : Artifact)
    (view : ArtifactView artifact) :
    decodeReconstructedSurfaceView artifact view =
      decodeReconstructedSurface artifact := by
  simp [decodeReconstructedSurfaceView, decodeReconstructedSurface,
    reconstructArtifactSurfaceView_eq artifact view]

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

/-! ## View-backed Surface access

All optimized Surface checks below depend only on `ArtifactView`.  Their
equivalence theorems transport results to the canonical list predicates used
by the public soundness statements.
-/

def tokenTextWithView? (artifact : Artifact) (view : ArtifactView artifact)
    (tokenId : TokenId) : Option String := do
  let _source ← artifact.sources[0]?
  let token ← view.token? tokenId
  if token.span.file != 0 || token.span.start > token.span.finish then none else
  let tokenBytes := view.cache.primarySourceBytes.rangeToList token.span.start
    (token.span.finish - token.span.start)
  String.fromUTF8?
    (tokenBytes.map (fun byte => UInt8.ofNat byte.val)).toByteArray

def tokenTextEqWithView (artifact : Artifact) (view : ArtifactView artifact)
    (tokenId : TokenId) (expected : String) : Bool :=
  match artifact.sources[0]?, view.token? tokenId with
  | some _, some token =>
      if token.span.file != 0 || token.span.start > token.span.finish then false
      else
        let expectedBytes := expected.toUTF8.data.toList.map UInt8.toFin
        token.span.finish - token.span.start == expectedBytes.length &&
          view.cache.primarySourceBytes.rangeEq token.span.start expectedBytes
  | _, _ => false

@[simp] theorem String.fromUTF8?_toUTF8 (text : String) :
    String.fromUTF8? text.toUTF8 = some text := by
  unfold String.fromUTF8?
  split
  · rfl
  · rename_i invalid
    exact (invalid (by simpa using text.isValidUTF8)).elim

theorem ByteArray.dataToList_toByteArray (bytes : ByteArray) :
    bytes.data.toList.toByteArray = bytes := by
  apply ByteArray.ext
  apply Array.toList_inj.mp
  exact List.toList_data_toByteArray

theorem tokenTextEqWithView_sound {artifact : Artifact}
    (view : ArtifactView artifact) {tokenId : TokenId} {expected : String}
    (accepted : tokenTextEqWithView artifact view tokenId expected = true) :
    tokenTextWithView? artifact view tokenId = some expected := by
  unfold tokenTextEqWithView at accepted
  cases sourceFound : artifact.sources[0]? with
  | none => simp [sourceFound] at accepted
  | some source =>
      cases tokenFound : view.token? tokenId with
      | none => simp [sourceFound, tokenFound] at accepted
      | some token =>
          by_cases invalid : token.span.file ≠ 0 ∨
              token.span.finish < token.span.start
          · simp [sourceFound, tokenFound, invalid] at accepted
          · simp [sourceFound, tokenFound, invalid] at accepted
            have rangeAccepted := Lanius.Data.SeqTree.rangeEq_sound
              view.sourceBytesWellFormed accepted.2
            have bytesEqual :
                view.cache.primarySourceBytes.rangeToList token.span.start
                    (token.span.finish - token.span.start) =
                  expected.toUTF8.data.toList.map UInt8.toFin := by
              rw [Lanius.Data.SeqTree.rangeToList_eq_flatten
                view.cache.primarySourceBytes view.sourceBytesWellFormed]
              have lengthEqual :
                  token.span.finish - token.span.start =
                    (expected.toUTF8.data.toList.map UInt8.toFin).length := by
                simpa using accepted.1
              rw [lengthEqual]
              exact rangeAccepted
            simp [tokenTextWithView?, sourceFound, tokenFound, invalid,
              bytesEqual, Function.comp_def, ByteArray.dataToList_toByteArray]
            simpa using String.fromUTF8?_toUTF8 expected

theorem tokenTextWithView_eq (artifact : Artifact) (view : ArtifactView artifact)
    (tokenId : TokenId) :
    tokenTextWithView? artifact view tokenId = tokenText? artifact tokenId := by
  unfold tokenTextWithView? tokenText?
  cases sourceFound : artifact.sources[0]? with
  | none => simp
  | some source =>
      dsimp
      rw [view.token?_eq]
      cases tokenFound : artifact.tokens[tokenId]? with
      | none => simp
      | some token =>
          dsimp
          by_cases invalid : token.span.file ≠ 0 ∨
              token.span.finish < token.span.start
          · simp [invalid]
          · rw [view.sourceBytesRepresent source sourceFound]
            simp only [Option.bind_some]
            rw [Lanius.Data.SeqTree.rangeToList_eq_flatten
              view.cache.primarySourceBytes view.sourceBytesWellFormed]

def parseNodeContainsTokenViewWithFuel
    (artifact : Artifact) (view : ArtifactView artifact)
    (tokenId : TokenId) : Nat → ParseNodeId → Bool
  | 0, _ => false
  | fuel + 1, nodeId =>
      match view.node? nodeId with
      | none => false
      | some node => node.children.any fun
          | .token childToken => childToken = tokenId
          | .node childNode =>
              parseNodeContainsTokenViewWithFuel artifact view tokenId fuel childNode

theorem parseNodeContainsTokenViewWithFuel_eq
    (artifact : Artifact) (view : ArtifactView artifact)
    (tokenId fuel nodeId : Nat) :
    parseNodeContainsTokenViewWithFuel artifact view tokenId fuel nodeId =
      parseNodeContainsTokenWithFuel artifact.parse_nodes tokenId fuel nodeId := by
  induction fuel generalizing nodeId with
  | zero => rfl
  | succ fuel inductionHypothesis =>
      simp only [parseNodeContainsTokenViewWithFuel,
        parseNodeContainsTokenWithFuel, view.node?_eq]
      cases lookup : artifact.parse_nodes[nodeId]? with
      | none => rfl
      | some node =>
          dsimp
          congr 1
          funext child
          cases child <;> simp [inductionHypothesis]

def parseNodeContainsTokenView
    (artifact : Artifact) (view : ArtifactView artifact)
    (nodeId : ParseNodeId) (tokenId : TokenId) : Bool :=
  parseNodeContainsTokenViewWithFuel artifact view tokenId
    (artifact.parse_nodes.length + 1) nodeId

def parseNodeContainsNodeViewWithFuel
    (artifact : Artifact) (view : ArtifactView artifact)
    (descendant : ParseNodeId) : Nat → ParseNodeId → Bool
  | 0, _ => false
  | fuel + 1, ancestor =>
      match view.node? ancestor with
      | none => false
      | some node =>
          if ancestor = descendant then true else
          node.children.any fun
            | .token _ => false
            | .node child =>
                parseNodeContainsNodeViewWithFuel artifact view descendant fuel child

theorem parseNodeContainsNodeViewWithFuel_eq
    (artifact : Artifact) (view : ArtifactView artifact)
    (descendant fuel ancestor : Nat) :
    parseNodeContainsNodeViewWithFuel artifact view descendant fuel ancestor =
      parseNodeContainsNodeWithFuel artifact.parse_nodes descendant fuel ancestor := by
  induction fuel generalizing ancestor with
  | zero => rfl
  | succ fuel inductionHypothesis =>
      simp only [parseNodeContainsNodeViewWithFuel,
        parseNodeContainsNodeWithFuel, view.node?_eq]
      cases lookup : artifact.parse_nodes[ancestor]? with
      | none => rfl
      | some node =>
          dsimp
          by_cases same : ancestor = descendant
          · simp [same]
          · simp only [same, ↓reduceIte]
            congr 1
            funext child
            cases child <;> simp [inductionHypothesis]

def parseNodeContainsNodeView
    (artifact : Artifact) (view : ArtifactView artifact)
    (ancestor descendant : ParseNodeId) : Bool :=
  parseNodeContainsNodeViewWithFuel artifact view descendant
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

def spellingClaimValidView (artifact : Artifact) (view : ArtifactView artifact)
    (claim : SpellingClaim) : Bool :=
  tokenTextWithView? artifact view claim.token = some claim.text &&
    parseNodeContainsTokenView artifact view claim.owner claim.token

def nodeClaimValidView (artifact : Artifact) (view : ArtifactView artifact)
    (claim : SurfaceNodeClaim) : Bool :=
  match view.node? claim.parseNode with
  | none => false
  | some node =>
      claim.allowedProductions.contains node.production &&
        match claim.containingParseNode with
        | none => true
        | some parent =>
            parseNodeContainsNodeView artifact view parent claim.parseNode

theorem spellingClaimValidView_eq (artifact : Artifact)
    (view : ArtifactView artifact) (claim : SpellingClaim) :
    spellingClaimValidView artifact view claim =
      spellingClaimValid artifact claim := by
  simp [spellingClaimValidView, spellingClaimValid, tokenTextWithView_eq,
    parseNodeContainsTokenView, parseNodeContainsToken,
    parseNodeContainsTokenViewWithFuel_eq]

theorem nodeClaimValidView_eq (artifact : Artifact)
    (view : ArtifactView artifact) (claim : SurfaceNodeClaim) :
    nodeClaimValidView artifact view claim = nodeClaimValid artifact claim := by
  unfold nodeClaimValidView nodeClaimValid
  rw [view.node?_eq]
  cases lookup : artifact.parse_nodes[claim.parseNode]? with
  | none => rfl
  | some node =>
      dsimp
      cases claim.containingParseNode with
      | none => rfl
      | some parent =>
          simp [parseNodeContainsNodeView, parseNodeContainsNode,
            parseNodeContainsNodeViewWithFuel_eq]

def tokenCarriesSurfaceSpelling (token : Token) : Bool :=
  token.kind = 1 || token.kind = 2 || token.kind = 32 ||
    token.kind = 33 || token.kind = 34

def expectedSpellingTokens (artifact : Artifact) : List TokenId :=
  artifact.tokens.zipIdx.filterMap fun (token, id) =>
    if tokenCarriesSurfaceSpelling token then some id else none

def spellingCoverageValid (artifact : Artifact) (claims : SurfaceClaims) : Bool :=
  let actual := claims.spellings.map (·.token)
  let expected := expectedSpellingTokens artifact
  actual == expected

def surfaceClaimsValid (artifact : Artifact) (claims : SurfaceClaims) : Bool :=
  claims.nodes.map (·.id) == List.range claims.nodes.length &&
  claims.nodes.all (nodeClaimValid artifact) &&
  claims.spellings.all (spellingClaimValid artifact) &&
  spellingCoverageValid artifact claims

def surfaceClaimsValidView (artifact : Artifact) (view : ArtifactView artifact)
    (claims : SurfaceClaims) : Bool :=
  claims.nodes.map (·.id) == List.range claims.nodes.length &&
  claims.nodes.all (nodeClaimValidView artifact view) &&
  claims.spellings.all (spellingClaimValidView artifact view) &&
  spellingCoverageValid artifact claims

theorem surfaceClaimsValidView_eq (artifact : Artifact)
    (view : ArtifactView artifact) (claims : SurfaceClaims) :
    surfaceClaimsValidView artifact view claims =
      surfaceClaimsValid artifact claims := by
  have nodesEq : claims.nodes.all (nodeClaimValidView artifact view) =
      claims.nodes.all (nodeClaimValid artifact) := by
    apply List.all_congr rfl
    intro claim
    exact nodeClaimValidView_eq artifact view claim
  have spellingsEq : claims.spellings.all (spellingClaimValidView artifact view) =
      claims.spellings.all (spellingClaimValid artifact) := by
    apply List.all_congr rfl
    intro claim
    exact spellingClaimValidView_eq artifact view claim
  simp only [surfaceClaimsValidView, surfaceClaimsValid, nodesEq, spellingsEq]

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

theorem surfaceClaimsValidView_sound {artifact : Artifact}
    (view : ArtifactView artifact) {claims : SurfaceClaims}
    (accepted : surfaceClaimsValidView artifact view claims = true) :
    SurfaceClaimsMatch artifact claims := by
  apply surfaceClaimsValid_sound
  rw [← surfaceClaimsValidView_eq artifact view]
  exact accepted

def checkSurfaceArtifactView (artifact : Artifact) (view : ArtifactView artifact) : Bool :=
  checkParseArtifactView artifact view &&
  match collectSurfaceClaimsView artifact view,
      decodeReconstructedSurfaceView artifact view with
  | some claims, some _ => surfaceClaimsValidView artifact view claims
  | _, _ => false

/-- Canonical semantic statement certified by the Surface checker.  Optimized
views disappear at this public boundary. -/
def SurfaceArtifactValid (artifact : Artifact) : Prop :=
  ParseArtifactValid artifact ∧
  ∃ claims surface,
    collectSurfaceClaims artifact = some claims ∧
    decodeReconstructedSurface artifact = some surface ∧
    SurfaceClaimsMatch artifact claims

theorem SurfaceArtifactValid.ofView {artifact : Artifact}
    (view : ArtifactView artifact) (parseValid : ParseArtifactValid artifact)
    {claims : SurfaceClaims} {surface : Lanius.Surface.File}
    (claimsFound : collectSurfaceClaimsView artifact view = some claims)
    (surfaceFound : decodeReconstructedSurfaceView artifact view = some surface)
    (claimsMatch : SurfaceClaimsMatch artifact claims) :
    SurfaceArtifactValid artifact := by
  rw [collectSurfaceClaimsView_eq] at claimsFound
  rw [decodeReconstructedSurfaceView_eq] at surfaceFound
  exact ⟨parseValid, claims, surface, claimsFound, surfaceFound, claimsMatch⟩

theorem checkSurfaceArtifactView_sound {artifact : Artifact}
    (view : ArtifactView artifact)
    (accepted : checkSurfaceArtifactView artifact view = true) :
    SurfaceArtifactValid artifact := by
  unfold checkSurfaceArtifactView at accepted
  simp only [Bool.and_eq_true] at accepted
  rcases accepted with ⟨parseAccepted, surfaceAccepted⟩
  have parseValid := checkParseArtifactView_sound view parseAccepted
  cases claimsResult : collectSurfaceClaimsView artifact view with
  | none => simp [claimsResult] at surfaceAccepted
  | some claims =>
      cases surfaceResult : decodeReconstructedSurfaceView artifact view with
      | none => simp [claimsResult, surfaceResult] at surfaceAccepted
      | some surface =>
          exact SurfaceArtifactValid.ofView view parseValid claimsResult
            surfaceResult (surfaceClaimsValidView_sound view
              (by simpa [claimsResult, surfaceResult] using surfaceAccepted))

/-- Reference entry point.  Even the list-backed cache crosses the same checked
view boundary as optimized caches. -/
def checkSurfaceArtifact (artifact : Artifact) : Bool :=
  match ArtifactView.canonical? artifact with
  | none => false
  | some view => checkSurfaceArtifactView artifact view

theorem checkSurfaceArtifact_sound {artifact : Artifact}
    (accepted : checkSurfaceArtifact artifact = true) :
    SurfaceArtifactValid artifact := by
  unfold checkSurfaceArtifact at accepted
  cases found : ArtifactView.canonical? artifact with
  | none => simp [found] at accepted
  | some view =>
      exact checkSurfaceArtifactView_sound view (by simpa [found] using accepted)

/-! ## Single-reconstruction checked surface -/

structure CheckedSurfaceArtifact (artifact : Artifact) where
  view : ArtifactView artifact
  reconstructed : SurfaceFile
  reconstructedFound :
    reconstructArtifactSurfaceView artifact view = some reconstructed
  claims : SurfaceClaims
  claimsFound : collectSurfaceClaimsView artifact view = some claims
  surface : Lanius.Surface.File
  surfaceFound : decodeReconstructedSurfaceView artifact view = some surface
  valid : SurfaceArtifactValid artifact

def checkSurfaceArtifactView? (artifact : Artifact) (view : ArtifactView artifact) :
    Option (CheckedSurfaceArtifact artifact) := do
  if parseAccepted : checkParseArtifactView artifact view = true then
    match reconstructedFound : reconstructArtifactSurfaceView artifact view with
    | none => none
    | some reconstructed =>
        match claimsFound : collectSurfaceClaimsFrom artifact reconstructed with
        | none => none
        | some claims =>
            match surfaceFound : decodeSurfaceFile
                (artifact.parse_nodes.length + 1) reconstructed with
            | none => none
            | some surface =>
                if claimsAccepted :
                    surfaceClaimsValidView artifact view claims = true then
                  have collected :
                      collectSurfaceClaimsView artifact view = some claims := by
                    simp [collectSurfaceClaimsView, reconstructedFound, claimsFound]
                  have decoded :
                      decodeReconstructedSurfaceView artifact view = some surface := by
                    simp [decodeReconstructedSurfaceView, reconstructedFound,
                      surfaceFound]
                  pure {
                    view
                    reconstructed
                    reconstructedFound
                    claims
                    claimsFound := collected
                    surface
                    surfaceFound := decoded
                    valid := SurfaceArtifactValid.ofView view
                      (checkParseArtifactView_sound view parseAccepted)
                      collected decoded
                      (surfaceClaimsValidView_sound view claimsAccepted)
                  }
                else none
  else none

def checkSurfaceArtifact? (artifact : Artifact) :
    Option (CheckedSurfaceArtifact artifact) := do
  let view ← ArtifactView.canonical? artifact
  checkSurfaceArtifactView? artifact view

theorem checkSurfaceArtifactView?_sound {artifact : Artifact}
    (view : ArtifactView artifact) {checked : CheckedSurfaceArtifact artifact}
    (_accepted : checkSurfaceArtifactView? artifact view = some checked) :
    SurfaceArtifactValid artifact := checked.valid

theorem checkSurfaceArtifact?_sound {artifact : Artifact}
    {checked : CheckedSurfaceArtifact artifact}
    (_accepted : checkSurfaceArtifact? artifact = some checked) :
    SurfaceArtifactValid artifact := checked.valid

end Lanius.Extraction
