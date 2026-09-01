import Lanius.Extraction.SurfaceDecode
import Lanius.Extraction.ParseChecker

namespace Lanius.Extraction

/-! ## Authoritative Surface reconstruction

The Rust exporter proposes a located `SurfaceFile`. These functions derive the
same value independently from the already checked parse tree. They deliberately
follow grammar productions and child positions rather than trusting semantic
edges supplied by the exporter. Fuel bounds malformed cyclic artifacts; valid
parse trees are acyclic because the parse checker requires every child node to
have a smaller ID than its parent.
-/

abbrev SurfaceBuild (α : Type) := StateT SurfaceNodeId Option α

def freshSurfaceNodeId : SurfaceBuild SurfaceNodeId := do
  let id ← get
  set (id + 1)
  pure id

def splitLast : List α → Option (List α × α)
  | [] => none
  | [last] => some ([], last)
  | head :: tail => do
      let (initial, last) ← splitLast tail
      pure (head :: initial, last)

def artifactNode? (artifact : Artifact) (nodeId : ParseNodeId) : Option ParseNode :=
  match artifact.parse_node_chunks with
  | none => artifact.parse_nodes[nodeId]?
  | some chunks => chunkLookup chunks nodeId

/-- The optional chunk table is a computational cache, never an independent
    parse-tree claim. -/
def parseNodeChunksMatch (artifact : Artifact) : Bool :=
  match artifact.parse_node_chunks with
  | none => true
  | some chunks => chunks.flatten == artifact.parse_nodes

theorem parseNodeChunksMatch_sound {artifact : Artifact}
    (accepted : parseNodeChunksMatch artifact = true) :
    match artifact.parse_node_chunks with
    | none => True
    | some chunks => chunks.flatten = artifact.parse_nodes := by
  unfold parseNodeChunksMatch at accepted
  cases chunksFound : artifact.parse_node_chunks with
  | none => trivial
  | some chunks =>
      simp only [chunksFound] at accepted
      exact eq_of_beq accepted

def artifactProduction? (artifact : Artifact) (nodeId : ParseNodeId) : Option Nat := do
  pure (← artifactNode? artifact nodeId).production

def artifactChildNode?
    (artifact : Artifact) (nodeId : ParseNodeId) (index : Nat) : Option ParseNodeId := do
  let child ← (← artifactNode? artifact nodeId).children[index]?
  match child with
  | .node child => some child
  | .token _ => none

def artifactChildToken?
    (artifact : Artifact) (nodeId : ParseNodeId) (index : Nat) : Option TokenId := do
  let child ← (← artifactNode? artifact nodeId).children[index]?
  match child with
  | .token token => some token
  | .node _ => none

def artifactExpectProduction
    (artifact : Artifact) (nodeId : ParseNodeId) (production : Nat) : Option Unit := do
  if (← artifactProduction? artifact nodeId) = production then some () else none

def artifactTokenText? (artifact : Artifact) (tokenId : TokenId) : Option String := do
  let source ← artifact.sources[0]?
  let token ← artifact.tokens[tokenId]?
  if token.span.file != 0 || token.span.start > token.span.finish then none else
  let bytes ← decodeBytes source.bytes
  let tokenBytes := (bytes.drop token.span.start).take
    (token.span.finish - token.span.start)
  String.fromUTF8? (tokenBytes.map (fun byte => UInt8.ofNat byte.val)).toByteArray

def reconstructName
    (artifact : Artifact) (nodeId : ParseNodeId) (child : Nat) : Option SpelledName := do
  let token ← artifactChildToken? artifact nodeId child
  pure { token, text := ← artifactTokenText? artifact token }

def reconstructArrayLength
    (artifact : Artifact) (nodeId : ParseNodeId) : Option SurfaceArrayLength := do
  match ← artifactProduction? artifact nodeId with
  | 286 =>
      let token ← artifactChildToken? artifact nodeId 0
      pure (.literal token (← artifactTokenText? artifact token))
  | 287 => pure (.parameter (← reconstructName artifact nodeId 0))
  | _ => none

mutual
  def reconstructPathSegment :
      Nat → Artifact → ParseNodeId → SurfaceBuild SurfacePathSegment
    | 0, _, _ => failure
    | fuel + 1, artifact, nodeId => do
        let (name, arguments) ← match ← artifactProduction? artifact nodeId with
          | 48 => pure (← reconstructName artifact nodeId 0, [])
          | 49 =>
              let first ← reconstructTypeExpr fuel artifact
                (← artifactChildNode? artifact nodeId 2)
              let rest ← reconstructPathTypeArgTail fuel artifact
                (← artifactChildNode? artifact nodeId 3)
              pure (← reconstructName artifact nodeId 0, first :: rest)
          | _ => failure
        pure {
          id := ← freshSurfaceNodeId
          parse_node := nodeId
          name
          arguments
        }

  def reconstructPath : Nat → Artifact → ParseNodeId → SurfaceBuild SurfacePath
    | 0, _, _ => failure
    | fuel + 1, artifact, nodeId => do
        artifactExpectProduction artifact nodeId 47
        let first ← reconstructPathSegment fuel artifact
          (← artifactChildNode? artifact nodeId 0)
        let rest ← reconstructPathTail fuel artifact
          (← artifactChildNode? artifact nodeId 1)
        pure {
          id := ← freshSurfaceNodeId
          parse_node := nodeId
          value := { segments := first :: rest }
        }

  def reconstructPathTail :
      Nat → Artifact → ParseNodeId → SurfaceBuild (List SurfacePathSegment)
    | 0, _, _ => failure
    | fuel + 1, artifact, nodeId => do
        match ← artifactProduction? artifact nodeId with
        | 50 =>
            let segment ← reconstructPathSegment fuel artifact
              (← artifactChildNode? artifact nodeId 2)
            let rest ← reconstructPathTail fuel artifact
              (← artifactChildNode? artifact nodeId 3)
            pure (segment :: rest)
        | 51 => pure []
        | _ => failure

  def reconstructPathTypeArgTail :
      Nat → Artifact → ParseNodeId → SurfaceBuild (List SurfaceTypeExpr)
    | 0, _, _ => failure
    | fuel + 1, artifact, nodeId => do
        match ← artifactProduction? artifact nodeId with
        | 52 => do
            reconstructPathTypeArgTailAfterComma fuel artifact
              (← artifactChildNode? artifact nodeId 1)
        | 53 => pure []
        | _ => failure

  def reconstructPathTypeArgTailAfterComma :
      Nat → Artifact → ParseNodeId → SurfaceBuild (List SurfaceTypeExpr)
    | 0, _, _ => failure
    | fuel + 1, artifact, nodeId => do
        match ← artifactProduction? artifact nodeId with
        | 54 =>
            let argument ← reconstructTypeExpr fuel artifact
              (← artifactChildNode? artifact nodeId 0)
            let rest ← reconstructPathTypeArgTail fuel artifact
              (← artifactChildNode? artifact nodeId 1)
            pure (argument :: rest)
        | 55 => pure []
        | _ => failure

  def reconstructTypeExpr :
      Nat → Artifact → ParseNodeId → SurfaceBuild SurfaceTypeExpr
    | 0, _, _ => failure
    | fuel + 1, artifact, nodeId => do
        let value ← match ← artifactProduction? artifact nodeId with
          | 69 =>
              let rawSegments ← reconstructTypePath fuel artifact
                (← artifactChildNode? artifact nodeId 0)
              let (initial, last) ← splitLast rawSegments
              let segments ← initial.mapM fun (parseNode, name) => do
                pure {
                  id := ← freshSurfaceNodeId
                  parse_node := parseNode
                  name
                  arguments := []
                }
              let arguments ← reconstructTypeArgsOpt fuel artifact
                (← artifactChildNode? artifact nodeId 1)
              let lastSegment : SurfacePathSegment := {
                id := ← freshSurfaceNodeId
                parse_node := last.1
                name := last.2
                arguments
              }
              let path : SurfacePath := {
                id := ← freshSurfaceNodeId
                parse_node := nodeId
                value := { segments := segments ++ [lastSegment] }
              }
              pure (.path path)
          | 70 =>
              let element ← reconstructTypeExpr fuel artifact
                (← artifactChildNode? artifact nodeId 1)
              let tail ← artifactChildNode? artifact nodeId 2
              match ← artifactProduction? artifact tail with
              | 283 => pure (.array element
                  (← reconstructArrayLength artifact
                    (← artifactChildNode? artifact tail 1)))
              | 284 => pure (.slice element)
              | _ => failure
          | 285 =>
              pure (.reference (← reconstructTypeExpr fuel artifact
                (← artifactChildNode? artifact nodeId 1)))
          | _ => failure
        pure {
          id := ← freshSurfaceNodeId
          parse_node := nodeId
          value
        }

  def reconstructTypePath :
      Nat → Artifact → ParseNodeId → SurfaceBuild (List (ParseNodeId × SpelledName))
    | 0, _, _ => failure
    | fuel + 1, artifact, nodeId => do
        artifactExpectProduction artifact nodeId 56
        let firstNode ← artifactChildNode? artifact nodeId 0
        artifactExpectProduction artifact firstNode 57
        let first := (firstNode, ← reconstructName artifact firstNode 0)
        let rest ← reconstructTypePathTail fuel artifact
          (← artifactChildNode? artifact nodeId 1)
        pure (first :: rest)

  def reconstructTypePathTail :
      Nat → Artifact → ParseNodeId → SurfaceBuild (List (ParseNodeId × SpelledName))
    | 0, _, _ => failure
    | fuel + 1, artifact, nodeId => do
        match ← artifactProduction? artifact nodeId with
        | 58 =>
            let segment ← artifactChildNode? artifact nodeId 2
            artifactExpectProduction artifact segment 57
            let entry := (segment, ← reconstructName artifact segment 0)
            let rest ← reconstructTypePathTail fuel artifact
              (← artifactChildNode? artifact nodeId 3)
            pure (entry :: rest)
        | 59 => pure []
        | _ => failure

  def reconstructTypeArgsOpt :
      Nat → Artifact → ParseNodeId → SurfaceBuild (List SurfaceTypeExpr)
    | 0, _, _ => failure
    | fuel + 1, artifact, nodeId => do
        match ← artifactProduction? artifact nodeId with
        | 226 => pure []
        | 227 =>
            let first ← reconstructTypeExpr fuel artifact
              (← artifactChildNode? artifact nodeId 1)
            let rest ← reconstructTypeArgTail fuel artifact
              (← artifactChildNode? artifact nodeId 2)
            pure (first :: rest)
        | _ => failure

  def reconstructTypeArgTail :
      Nat → Artifact → ParseNodeId → SurfaceBuild (List SurfaceTypeExpr)
    | 0, _, _ => failure
    | fuel + 1, artifact, nodeId => do
        match ← artifactProduction? artifact nodeId with
        | 228 => do
            reconstructTypeArgTailAfterComma fuel artifact
              (← artifactChildNode? artifact nodeId 1)
        | 229 => pure []
        | _ => failure

  def reconstructTypeArgTailAfterComma :
      Nat → Artifact → ParseNodeId → SurfaceBuild (List SurfaceTypeExpr)
    | 0, _, _ => failure
    | fuel + 1, artifact, nodeId => do
        match ← artifactProduction? artifact nodeId with
        | 230 =>
            let argument ← reconstructTypeExpr fuel artifact
              (← artifactChildNode? artifact nodeId 0)
            let rest ← reconstructTypeArgTail fuel artifact
              (← artifactChildNode? artifact nodeId 1)
            pure (argument :: rest)
        | 231 => pure []
        | _ => failure
end

inductive ReconstructBinaryLayer where
  | logical_or | logical_and | bit_or | bit_xor | bit_and
  | equality | comparison | shift | additive | multiplicative
deriving DecidableEq

def ReconstructBinaryLayer.headProduction : ReconstructBinaryLayer → Nat
  | .logical_or => 118
  | .logical_and => 121
  | .bit_or => 124
  | .bit_xor => 127
  | .bit_and => 130
  | .equality => 133
  | .comparison => 137
  | .shift => 143
  | .additive => 147
  | .multiplicative => 151

def ReconstructBinaryLayer.endProduction : ReconstructBinaryLayer → Nat
  | .logical_or => 120
  | .logical_and => 123
  | .bit_or => 126
  | .bit_xor => 129
  | .bit_and => 132
  | .equality => 136
  | .comparison => 142
  | .shift => 146
  | .additive => 150
  | .multiplicative => 155

def ReconstructBinaryLayer.next :
    ReconstructBinaryLayer → Option ReconstructBinaryLayer
  | .logical_or => some .logical_and
  | .logical_and => some .bit_or
  | .bit_or => some .bit_xor
  | .bit_xor => some .bit_and
  | .bit_and => some .equality
  | .equality => some .comparison
  | .comparison => some .shift
  | .shift => some .additive
  | .additive => some .multiplicative
  | .multiplicative => none

def ReconstructBinaryLayer.operator :
    ReconstructBinaryLayer → Nat → Option SurfaceBinaryOp
  | .logical_or, 119 => some .logical_or
  | .logical_and, 122 => some .logical_and
  | .bit_or, 125 => some .bit_or
  | .bit_xor, 128 => some .bit_xor
  | .bit_and, 131 => some .bit_and
  | .equality, 134 => some .equal
  | .equality, 135 => some .not_equal
  | .comparison, 138 => some .less
  | .comparison, 139 => some .greater
  | .comparison, 140 => some .less_equal
  | .comparison, 141 => some .greater_equal
  | .shift, 144 => some .shift_left
  | .shift, 145 => some .shift_right
  | .additive, 148 => some .add
  | .additive, 149 => some .subtract
  | .multiplicative, 152 => some .multiply
  | .multiplicative, 153 => some .divide
  | .multiplicative, 154 => some .remainder
  | _, _ => none

def reconstructAssignOperator : Nat → Option SurfaceAssignOp
  | 106 => some .set
  | 107 => some .add
  | 108 => some .subtract
  | 109 => some .multiply
  | 110 => some .divide
  | 111 => some .remainder
  | 112 => some .bit_xor
  | 113 => some .shift_left
  | 114 => some .shift_right
  | 115 => some .bit_and
  | 116 => some .bit_or
  | _ => none

def reconstructUnaryOperator : Nat → Option SurfaceUnaryOp
  | 156 => some .positive
  | 157 => some .negative
  | 158 => some .logical_not
  | _ => none

def reconstructTokenLiteral
    (artifact : Artifact) (nodeId : ParseNodeId)
    (production : Nat) : Option SurfaceLiteral := do
  let token ← artifactChildToken? artifact nodeId 0
  let text ← artifactTokenText? artifact token
  match production with
  | 175 => some (.integer token text)
  | 176 => some (.float token text)
  | 177 => some (.string token text)
  | 178 => some (.character token text)
  | _ => none

mutual
  def reconstructExpr : Nat → Artifact → ParseNodeId → SurfaceBuild SurfaceExpr
    | 0, _, _ => failure
    | fuel + 1, artifact, nodeId => do
        artifactExpectProduction artifact nodeId 104
        reconstructAssign fuel artifact
          (← artifactChildNode? artifact nodeId 0)

  def reconstructAssign : Nat → Artifact → ParseNodeId → SurfaceBuild SurfaceExpr
    | 0, _, _ => failure
    | fuel + 1, artifact, nodeId => do
        artifactExpectProduction artifact nodeId 105
        let left ← reconstructBinaryLayer fuel artifact
          (← artifactChildNode? artifact nodeId 0) .logical_or
        let tail ← artifactChildNode? artifact nodeId 1
        match reconstructAssignOperator (← artifactProduction? artifact tail) with
        | none =>
            artifactExpectProduction artifact tail 117
            pure left
        | some operator =>
            let right ← reconstructAssign fuel artifact
              (← artifactChildNode? artifact tail 1)
            pure {
              id := ← freshSurfaceNodeId
              parse_node := tail
              value := .assign operator left right
            }

  def reconstructBinaryLayer :
      Nat → Artifact → ParseNodeId → ReconstructBinaryLayer → SurfaceBuild SurfaceExpr
    | 0, _, _, _ => failure
    | fuel + 1, artifact, nodeId, layer => do
        artifactExpectProduction artifact nodeId layer.headProduction
        let leftNode ← artifactChildNode? artifact nodeId 0
        let left ← match layer.next with
          | some next => reconstructBinaryLayer fuel artifact leftNode next
          | none => reconstructUnary fuel artifact leftNode
        reconstructBinaryTail fuel artifact layer
          (← artifactChildNode? artifact nodeId 1) left

  def reconstructBinaryTail :
      Nat → Artifact → ReconstructBinaryLayer → ParseNodeId → SurfaceExpr →
        SurfaceBuild SurfaceExpr
    | 0, _, _, _, _ => failure
    | fuel + 1, artifact, layer, nodeId, left => do
        let production ← artifactProduction? artifact nodeId
        if production = layer.endProduction then pure left else
        let operator ← layer.operator production
        let rightNode ← artifactChildNode? artifact nodeId 1
        let right ← match layer.next with
          | some next => reconstructBinaryLayer fuel artifact rightNode next
          | none => reconstructUnary fuel artifact rightNode
        let result : SurfaceExpr := {
          id := ← freshSurfaceNodeId
          parse_node := nodeId
          value := .binary operator left right
        }
        reconstructBinaryTail fuel artifact layer
          (← artifactChildNode? artifact nodeId 2) result

  def reconstructUnary : Nat → Artifact → ParseNodeId → SurfaceBuild SurfaceExpr
    | 0, _, _ => failure
    | fuel + 1, artifact, nodeId => do
        let production ← artifactProduction? artifact nodeId
        match reconstructUnaryOperator production with
        | some operator =>
            let operand ← reconstructUnary fuel artifact
              (← artifactChildNode? artifact nodeId 1)
            pure {
              id := ← freshSurfaceNodeId
              parse_node := nodeId
              value := .unary operator operand
            }
        | none =>
            if production = 159 then
              reconstructPostfix fuel artifact
                (← artifactChildNode? artifact nodeId 0)
            else failure

  def reconstructPostfix : Nat → Artifact → ParseNodeId → SurfaceBuild SurfaceExpr
    | 0, _, _ => failure
    | fuel + 1, artifact, nodeId => do
        artifactExpectProduction artifact nodeId 160
        let base ← reconstructPrimary fuel artifact
          (← artifactChildNode? artifact nodeId 0)
        reconstructPostfixTail fuel artifact
          (← artifactChildNode? artifact nodeId 1) base

  def reconstructPostfixTail :
      Nat → Artifact → ParseNodeId → SurfaceExpr → SurfaceBuild SurfaceExpr
    | 0, _, _, _ => failure
    | fuel + 1, artifact, nodeId, base => do
        match ← artifactProduction? artifact nodeId with
        | 161 =>
            let arguments ← reconstructArguments fuel artifact
              (← artifactChildNode? artifact nodeId 1)
            let result : SurfaceExpr := {
              id := ← freshSurfaceNodeId
              parse_node := nodeId
              value := .call base arguments
            }
            reconstructPostfixTail fuel artifact
              (← artifactChildNode? artifact nodeId 3) result
        | 162 =>
            let index ← reconstructExpr fuel artifact
              (← artifactChildNode? artifact nodeId 1)
            let result : SurfaceExpr := {
              id := ← freshSurfaceNodeId
              parse_node := nodeId
              value := .index base index
            }
            reconstructPostfixTail fuel artifact
              (← artifactChildNode? artifact nodeId 3) result
        | 163 =>
            let result : SurfaceExpr := {
              id := ← freshSurfaceNodeId
              parse_node := nodeId
              value := .member base (← reconstructName artifact nodeId 1)
            }
            reconstructPostfixTail fuel artifact
              (← artifactChildNode? artifact nodeId 2) result
        | 164 => pure base
        | _ => failure

  def reconstructArguments :
      Nat → Artifact → ParseNodeId → SurfaceBuild (List SurfaceExpr)
    | 0, _, _ => failure
    | fuel + 1, artifact, nodeId => do
        match ← artifactProduction? artifact nodeId with
        | 165 => pure []
        | 166 =>
            let first ← reconstructExpr fuel artifact
              (← artifactChildNode? artifact nodeId 0)
            let rest ← reconstructArgumentTail fuel artifact
              (← artifactChildNode? artifact nodeId 1)
            pure (first :: rest)
        | _ => failure

  def reconstructArgumentTail :
      Nat → Artifact → ParseNodeId → SurfaceBuild (List SurfaceExpr)
    | 0, _, _ => failure
    | fuel + 1, artifact, nodeId => do
        match ← artifactProduction? artifact nodeId with
        | 167 => do
            reconstructArgumentTailAfterComma fuel artifact
              (← artifactChildNode? artifact nodeId 1)
        | 168 => pure []
        | _ => failure

  def reconstructArgumentTailAfterComma :
      Nat → Artifact → ParseNodeId → SurfaceBuild (List SurfaceExpr)
    | 0, _, _ => failure
    | fuel + 1, artifact, nodeId => do
        match ← artifactProduction? artifact nodeId with
        | 169 =>
            let argument ← reconstructExpr fuel artifact
              (← artifactChildNode? artifact nodeId 0)
            let rest ← reconstructArgumentTail fuel artifact
              (← artifactChildNode? artifact nodeId 1)
            pure (argument :: rest)
        | 170 => pure []
        | _ => failure

  def reconstructPrimary : Nat → Artifact → ParseNodeId → SurfaceBuild SurfaceExpr
    | 0, _, _ => failure
    | fuel + 1, artifact, nodeId => do
        let production ← artifactProduction? artifact nodeId
        if production = 172 then
          reconstructExpr fuel artifact
            (← artifactChildNode? artifact nodeId 1)
        else
        let value ← match production with
          | 171 => pure (.array (← reconstructArrayElements fuel artifact
              (← artifactChildNode? artifact nodeId 1)))
          | 173 =>
              let path ← reconstructPath fuel artifact
                (← artifactChildNode? artifact nodeId 0)
              let tail ← artifactChildNode? artifact nodeId 1
              match ← artifactProduction? artifact tail with
              | 274 => pure (.path path)
              | 275 => pure (.struct_value path
                  (← reconstructStructLiteralFields fuel artifact
                    (← artifactChildNode? artifact tail 1)))
              | _ => failure
          | 185 => pure (.literal (.boolean true))
          | 186 => pure (.literal (.boolean false))
          | _ => pure (.literal (← reconstructTokenLiteral artifact nodeId production))
        pure {
          id := ← freshSurfaceNodeId
          parse_node := nodeId
          value
        }

  def reconstructArrayElements :
      Nat → Artifact → ParseNodeId → SurfaceBuild (List SurfaceExpr)
    | 0, _, _ => failure
    | fuel + 1, artifact, nodeId => do
        match ← artifactProduction? artifact nodeId with
        | 179 => pure []
        | 180 =>
            let first ← reconstructExpr fuel artifact
              (← artifactChildNode? artifact nodeId 0)
            let rest ← reconstructArrayElementTail fuel artifact
              (← artifactChildNode? artifact nodeId 1)
            pure (first :: rest)
        | _ => failure

  def reconstructArrayElementTail :
      Nat → Artifact → ParseNodeId → SurfaceBuild (List SurfaceExpr)
    | 0, _, _ => failure
    | fuel + 1, artifact, nodeId => do
        match ← artifactProduction? artifact nodeId with
        | 181 => do
            reconstructArrayElementTailAfterComma fuel artifact
              (← artifactChildNode? artifact nodeId 1)
        | 182 => pure []
        | _ => failure

  def reconstructArrayElementTailAfterComma :
      Nat → Artifact → ParseNodeId → SurfaceBuild (List SurfaceExpr)
    | 0, _, _ => failure
    | fuel + 1, artifact, nodeId => do
        match ← artifactProduction? artifact nodeId with
        | 183 =>
            let element ← reconstructExpr fuel artifact
              (← artifactChildNode? artifact nodeId 0)
            let rest ← reconstructArrayElementTail fuel artifact
              (← artifactChildNode? artifact nodeId 1)
            pure (element :: rest)
        | 184 => pure []
        | _ => failure

  def reconstructStructLiteralFields :
      Nat → Artifact → ParseNodeId → SurfaceBuild (List SurfaceStructFieldValue)
    | 0, _, _ => failure
    | fuel + 1, artifact, nodeId => do
        match ← artifactProduction? artifact nodeId with
        | 276 => pure []
        | 277 =>
            let first ← reconstructStructLiteralField fuel artifact
              (← artifactChildNode? artifact nodeId 0)
            let rest ← reconstructStructLiteralFieldTail fuel artifact
              (← artifactChildNode? artifact nodeId 1)
            pure (first :: rest)
        | _ => failure

  def reconstructStructLiteralField :
      Nat → Artifact → ParseNodeId → SurfaceBuild SurfaceStructFieldValue
    | 0, _, _ => failure
    | fuel + 1, artifact, nodeId => do
        artifactExpectProduction artifact nodeId 278
        let name ← reconstructName artifact nodeId 0
        let value ← reconstructExpr fuel artifact
          (← artifactChildNode? artifact nodeId 2)
        pure {
          id := ← freshSurfaceNodeId
          parse_node := nodeId
          name
          value
        }

  def reconstructStructLiteralFieldTail :
      Nat → Artifact → ParseNodeId → SurfaceBuild (List SurfaceStructFieldValue)
    | 0, _, _ => failure
    | fuel + 1, artifact, nodeId => do
        match ← artifactProduction? artifact nodeId with
        | 279 => do
            reconstructStructLiteralFieldTailAfterComma fuel artifact
              (← artifactChildNode? artifact nodeId 1)
        | 280 => pure []
        | _ => failure

  def reconstructStructLiteralFieldTailAfterComma :
      Nat → Artifact → ParseNodeId → SurfaceBuild (List SurfaceStructFieldValue)
    | 0, _, _ => failure
    | fuel + 1, artifact, nodeId => do
        match ← artifactProduction? artifact nodeId with
        | 281 =>
            let field ← reconstructStructLiteralField fuel artifact
              (← artifactChildNode? artifact nodeId 0)
            let rest ← reconstructStructLiteralFieldTail fuel artifact
              (← artifactChildNode? artifact nodeId 1)
            pure (field :: rest)
        | 282 => pure []
        | _ => failure
end

mutual
  def reconstructStatements :
      Nat → Artifact → ParseNodeId → SurfaceBuild (List SurfaceStmt)
    | 0, _, _ => failure
    | fuel + 1, artifact, nodeId => do
        match ← artifactProduction? artifact nodeId with
        | 73 =>
            let statement ← reconstructStatement fuel artifact
              (← artifactChildNode? artifact nodeId 0)
            let rest ← reconstructStatements fuel artifact
              (← artifactChildNode? artifact nodeId 1)
            pure (statement :: rest)
        | 74 => pure []
        | _ => failure

  def reconstructStatement :
      Nat → Artifact → ParseNodeId → SurfaceBuild SurfaceStmt
    | 0, _, _ => failure
    | fuel + 1, artifact, nodeId => do
        let value ← match ← artifactProduction? artifact nodeId with
          | 75 => pure (.let_local
              (← reconstructName artifact nodeId 1)
              (← reconstructOptionalType fuel artifact
                (← artifactChildNode? artifact nodeId 2))
              (← reconstructOptionalInitializer fuel artifact
                (← artifactChildNode? artifact nodeId 3)))
          | 76 => pure (.return_value
              (← reconstructOptionalReturn fuel artifact
                (← artifactChildNode? artifact nodeId 1)))
          | 77 => pure (.if_then_else
              (← reconstructExpr fuel artifact
                (← artifactChildNode? artifact nodeId 2))
              (← reconstructBlock fuel artifact
                (← artifactChildNode? artifact nodeId 4))
              (← reconstructElseTail fuel artifact
                (← artifactChildNode? artifact nodeId 5)))
          | 80 => pure (.while_loop
              (← reconstructExpr fuel artifact
                (← artifactChildNode? artifact nodeId 2))
              (← reconstructBlock fuel artifact
                (← artifactChildNode? artifact nodeId 4)))
          | 82 => pure .break_loop
          | 83 => pure .continue_loop
          | 84 => pure (.block
              (← reconstructBlock fuel artifact
                (← artifactChildNode? artifact nodeId 0)))
          | 85 => pure (.expression
              (← reconstructExpr fuel artifact
                (← artifactChildNode? artifact nodeId 0)))
          | _ => failure
        pure {
          id := ← freshSurfaceNodeId
          parse_node := nodeId
          value
        }

  def reconstructOptionalType :
      Nat → Artifact → ParseNodeId → SurfaceBuild (Option SurfaceTypeExpr)
    | 0, _, _ => failure
    | fuel + 1, artifact, nodeId => do
        match ← artifactProduction? artifact nodeId with
        | 86 => pure (some (← reconstructTypeExpr fuel artifact
            (← artifactChildNode? artifact nodeId 1)))
        | 87 => pure none
        | _ => failure

  def reconstructOptionalInitializer :
      Nat → Artifact → ParseNodeId → SurfaceBuild (Option SurfaceExpr)
    | 0, _, _ => failure
    | fuel + 1, artifact, nodeId => do
        match ← artifactProduction? artifact nodeId with
        | 88 => pure (some (← reconstructExpr fuel artifact
            (← artifactChildNode? artifact nodeId 1)))
        | 89 => pure none
        | _ => failure

  def reconstructOptionalReturn :
      Nat → Artifact → ParseNodeId → SurfaceBuild (Option SurfaceExpr)
    | 0, _, _ => failure
    | fuel + 1, artifact, nodeId => do
        match ← artifactProduction? artifact nodeId with
        | 90 => pure (some (← reconstructExpr fuel artifact
            (← artifactChildNode? artifact nodeId 0)))
        | 91 => pure none
        | _ => failure

  def reconstructElseTail :
      Nat → Artifact → ParseNodeId → SurfaceBuild (List SurfaceStmt)
    | 0, _, _ => failure
    | fuel + 1, artifact, nodeId => do
        match ← artifactProduction? artifact nodeId with
        | 78 => do
            reconstructBlock fuel artifact
              (← artifactChildNode? artifact nodeId 1)
        | 79 => pure []
        | _ => failure

  def reconstructBlock :
      Nat → Artifact → ParseNodeId → SurfaceBuild (List SurfaceStmt)
    | 0, _, _ => failure
    | fuel + 1, artifact, nodeId => do
        match ← artifactProduction? artifact nodeId with
        | 12 | 14 | 71 | 72 => do
            reconstructStatements fuel artifact
              (← artifactChildNode? artifact nodeId 1)
        | _ => failure
end

mutual
  def reconstructParameters :
      Nat → Artifact → ParseNodeId → SurfaceBuild (List SurfaceParameter)
    | 0, _, _ => failure
    | fuel + 1, artifact, nodeId => do
        match ← artifactProduction? artifact nodeId with
        | 60 => pure []
        | 61 =>
            let first ← reconstructParameter fuel artifact
              (← artifactChildNode? artifact nodeId 0)
            let rest ← reconstructParameterTail fuel artifact
              (← artifactChildNode? artifact nodeId 1)
            pure (first :: rest)
        | _ => failure

  def reconstructParameter :
      Nat → Artifact → ParseNodeId → SurfaceBuild SurfaceParameter
    | 0, _, _ => failure
    | fuel + 1, artifact, nodeId => do
        artifactExpectProduction artifact nodeId 62
        let name ← reconstructName artifact nodeId 0
        let typeExpression ← reconstructTypeExpr fuel artifact
          (← artifactChildNode? artifact nodeId 2)
        pure {
          id := ← freshSurfaceNodeId
          parse_node := nodeId
          name
          type_expression := typeExpression
        }

  def reconstructParameterTail :
      Nat → Artifact → ParseNodeId → SurfaceBuild (List SurfaceParameter)
    | 0, _, _ => failure
    | fuel + 1, artifact, nodeId => do
        match ← artifactProduction? artifact nodeId with
        | 67 => do
            reconstructParameterTailAfterComma fuel artifact
              (← artifactChildNode? artifact nodeId 1)
        | 68 => pure []
        | _ => failure

  def reconstructParameterTailAfterComma :
      Nat → Artifact → ParseNodeId → SurfaceBuild (List SurfaceParameter)
    | 0, _, _ => failure
    | fuel + 1, artifact, nodeId => do
        match ← artifactProduction? artifact nodeId with
        | 288 =>
            let parameter ← reconstructParameter fuel artifact
              (← artifactChildNode? artifact nodeId 0)
            let rest ← reconstructParameterTail fuel artifact
              (← artifactChildNode? artifact nodeId 1)
            pure (parameter :: rest)
        | 289 => pure []
        | _ => failure
end

def reconstructFunction
    (fuel : Nat) (artifact : Artifact) (nodeId : ParseNodeId)
    (isPublic : Bool) : SurfaceBuild SurfaceFunction := do
  artifactExpectProduction artifact nodeId 11
  artifactExpectProduction artifact (← artifactChildNode? artifact nodeId 2) 232
  artifactExpectProduction artifact (← artifactChildNode? artifact nodeId 7) 36
  let name ← reconstructName artifact nodeId 1
  let parameters ← reconstructParameters fuel artifact
    (← artifactChildNode? artifact nodeId 4)
  let returnNode ← artifactChildNode? artifact nodeId 6
  let returnType ← match ← artifactProduction? artifact returnNode with
    | 34 => pure (some (← reconstructTypeExpr fuel artifact
        (← artifactChildNode? artifact returnNode 1)))
    | 35 => pure none
    | _ => failure
  let body ← reconstructBlock fuel artifact
    (← artifactChildNode? artifact nodeId 8)
  pure {
    name
    is_public := isPublic
    parameters
    return_type := returnType
    body
  }

mutual
  def reconstructStructFields :
      Nat → Artifact → ParseNodeId → SurfaceBuild (List SurfaceStructField)
    | 0, _, _ => failure
    | fuel + 1, artifact, nodeId => do
        match ← artifactProduction? artifact nodeId with
        | 259 => pure []
        | 260 =>
            let first ← reconstructStructField fuel artifact
              (← artifactChildNode? artifact nodeId 0)
            let rest ← reconstructStructFieldTail fuel artifact
              (← artifactChildNode? artifact nodeId 1)
            pure (first :: rest)
        | _ => failure

  def reconstructStructField :
      Nat → Artifact → ParseNodeId → SurfaceBuild SurfaceStructField
    | 0, _, _ => failure
    | fuel + 1, artifact, nodeId => do
        artifactExpectProduction artifact nodeId 261
        let name ← reconstructName artifact nodeId 0
        let typeExpression ← reconstructTypeExpr fuel artifact
          (← artifactChildNode? artifact nodeId 2)
        pure {
          id := ← freshSurfaceNodeId
          parse_node := nodeId
          name
          type_expression := typeExpression
        }

  def reconstructStructFieldTail :
      Nat → Artifact → ParseNodeId → SurfaceBuild (List SurfaceStructField)
    | 0, _, _ => failure
    | fuel + 1, artifact, nodeId => do
        match ← artifactProduction? artifact nodeId with
        | 262 => do
            reconstructStructFieldTailAfterComma fuel artifact
              (← artifactChildNode? artifact nodeId 1)
        | 263 => pure []
        | _ => failure

  def reconstructStructFieldTailAfterComma :
      Nat → Artifact → ParseNodeId → SurfaceBuild (List SurfaceStructField)
    | 0, _, _ => failure
    | fuel + 1, artifact, nodeId => do
        match ← artifactProduction? artifact nodeId with
        | 264 =>
            let field ← reconstructStructField fuel artifact
              (← artifactChildNode? artifact nodeId 0)
            let rest ← reconstructStructFieldTail fuel artifact
              (← artifactChildNode? artifact nodeId 1)
            pure (field :: rest)
        | 265 => pure []
        | _ => failure
end

def reconstructStruct
    (fuel : Nat) (artifact : Artifact) (nodeId : ParseNodeId)
    (isPublic : Bool) : SurfaceBuild SurfaceStruct := do
  artifactExpectProduction artifact nodeId 258
  artifactExpectProduction artifact (← artifactChildNode? artifact nodeId 2) 232
  artifactExpectProduction artifact (← artifactChildNode? artifact nodeId 3) 36
  pure {
    name := ← reconstructName artifact nodeId 1
    is_public := isPublic
    fields := ← reconstructStructFields fuel artifact
      (← artifactChildNode? artifact nodeId 5)
  }

mutual
  def reconstructItem : Nat → Artifact → ParseNodeId → SurfaceBuild SurfaceItem
    | 0, _, _ => failure
    | fuel + 1, artifact, nodeId => do
        let (isPublic, productionNode, production) ←
          if (← artifactProduction? artifact nodeId) = 3 then
            let publicNode ← artifactChildNode? artifact nodeId 1
            pure (true, ← artifactChildNode? artifact publicNode 0,
              ← artifactProduction? artifact publicNode)
          else
            pure (false, ← artifactChildNode? artifact nodeId 0,
              ← artifactProduction? artifact nodeId)
        let value ← match production with
          | 4 | 266 => pure (.function
              (← reconstructFunction fuel artifact productionNode isPublic))
          | 6 =>
              artifactExpectProduction artifact productionNode 43
              let tail ← artifactChildNode? artifact productionNode 1
              artifactExpectProduction artifact tail 44
              pure (.import_path (← reconstructPath fuel artifact
                (← artifactChildNode? artifact tail 0)))
          | 7 =>
              artifactExpectProduction artifact productionNode 46
              pure (.module (← reconstructPath fuel artifact
                (← artifactChildNode? artifact productionNode 1)))
          | 8 | 269 =>
              artifactExpectProduction artifact productionNode 16
              artifactExpectProduction artifact
                (← artifactChildNode? artifact productionNode 2) 232
              artifactExpectProduction artifact
                (← artifactChildNode? artifact productionNode 3) 36
              pure (.type_alias
                (← reconstructName artifact productionNode 1)
                isPublic
                (← reconstructTypeExpr fuel artifact
                  (← artifactChildNode? artifact productionNode 5)))
          | 207 | 268 =>
              artifactExpectProduction artifact productionNode 208
              pure (.constant
                (← reconstructName artifact productionNode 1)
                isPublic
                (← reconstructTypeExpr fuel artifact
                  (← artifactChildNode? artifact productionNode 3))
                (← reconstructExpr fuel artifact
                  (← artifactChildNode? artifact productionNode 5)))
          | 257 | 271 => pure (.structure
              (← reconstructStruct fuel artifact productionNode isPublic))
          | _ => failure
        pure {
          id := ← freshSurfaceNodeId
          parse_node := nodeId
          value
        }

  def reconstructItems :
      Nat → Artifact → ParseNodeId → SurfaceBuild (List SurfaceItem)
    | 0, _, _ => failure
    | fuel + 1, artifact, nodeId => do
        match ← artifactProduction? artifact nodeId with
        | 1 =>
            let item ← reconstructItem fuel artifact
              (← artifactChildNode? artifact nodeId 0)
            let rest ← reconstructItems fuel artifact
              (← artifactChildNode? artifact nodeId 1)
            pure (item :: rest)
        | 2 => pure []
        | _ => failure
end

def reconstructFile
    (fuel : Nat) (artifact : Artifact)
    (root : ParseNodeId) : SurfaceBuild SurfaceFile := do
  artifactExpectProduction artifact root 0
  let items ← reconstructItems fuel artifact
    (← artifactChildNode? artifact root 0)
  pure {
    id := ← freshSurfaceNodeId
    parse_node := root
    value := { items }
  }

def reconstructArtifactSurface (artifact : Artifact) : Option SurfaceFile := do
  let root ← artifact.parse_root
  let (surface, _) ← (reconstructFile
    (artifact.parse_nodes.length + 1) artifact root).run 0
  pure surface

/-- The formal Surface program exposed to later checkers is decoded from
    Lean's reconstruction, never directly from the untrusted proposal. -/
def decodeReconstructedSurface (artifact : Artifact) : Option Lanius.Surface.File := do
  let reconstructed ← reconstructArtifactSurface artifact
  decodeSurfaceFile (artifact.parse_nodes.length + 1) reconstructed

/-- Exact agreement between the untrusted proposal and Lean's independent
    production/child-position reconstruction. -/
def surfaceReconstructionMatches (artifact : Artifact) : Bool :=
  match artifact.surface, reconstructArtifactSurface artifact with
  | some proposed, some reconstructed => proposed == reconstructed
  | _, _ => false

end Lanius.Extraction
