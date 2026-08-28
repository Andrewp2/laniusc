import Lanius.Extraction.Artifact
import Lanius.LiteralSyntax
import Lanius.SurfaceSyntax

namespace Lanius.Extraction

open Lanius

mutual
  def decodeSurfacePathSegmentWithFuel : Nat → SurfacePathSegment → Option Surface.PathSegment
    | 0, _ => none
    | fuel + 1, segment => do
        pure (.mk segment.name.text
          (← segment.arguments.mapM (decodeSurfaceTypeExprWithFuel fuel)))

  def decodeSurfacePathWithFuel : Nat → SurfacePath → Option Surface.Path
    | 0, _ => none
    | fuel + 1, path => do
        let segments ← path.value.segments.mapM
          (decodeSurfacePathSegmentWithFuel fuel)
        pure { segments }

  def decodeSurfaceArrayLength : SurfaceArrayLength → Option Surface.ArrayLength
    | .literal _ text => .literal <$> Elaboration.parseUnsignedInteger text
    | .parameter name => some (.parameter name.text)

  def decodeSurfaceTypeExprWithFuel : Nat → SurfaceTypeExpr → Option Surface.TypeExpr
    | 0, _ => none
    | fuel + 1, type => do
        match type.value with
        | .path path =>
            pure (.path (← decodeSurfacePathWithFuel fuel path).segments)
        | .array element length =>
            pure (.array (← decodeSurfaceTypeExprWithFuel fuel element)
              (← decodeSurfaceArrayLength length))
        | .slice element => .slice <$> decodeSurfaceTypeExprWithFuel fuel element
        | .reference referent => .reference <$> decodeSurfaceTypeExprWithFuel fuel referent
end

def decodeSurfacePath (fuel : Nat) (path : SurfacePath) : Option Surface.Path :=
  decodeSurfacePathWithFuel fuel path

def decodeSurfaceTypeExpr (fuel : Nat) (type : SurfaceTypeExpr) : Option Surface.TypeExpr :=
  decodeSurfaceTypeExprWithFuel fuel type

def decodeSurfaceUnaryOp : SurfaceUnaryOp → Surface.UnaryOp
  | .positive => .positive
  | .negative => .negative
  | .logical_not => .logicalNot

def decodeSurfaceBinaryOp : SurfaceBinaryOp → Surface.BinaryOp
  | .logical_or => .logicalOr
  | .logical_and => .logicalAnd
  | .bit_or => .bitOr
  | .bit_xor => .bitXor
  | .bit_and => .bitAnd
  | .equal => .equal
  | .not_equal => .notEqual
  | .less => .less
  | .greater => .greater
  | .less_equal => .lessEqual
  | .greater_equal => .greaterEqual
  | .shift_left => .shiftLeft
  | .shift_right => .shiftRight
  | .add => .add
  | .subtract => .subtract
  | .multiply => .multiply
  | .divide => .divide
  | .remainder => .remainder

def decodeSurfaceAssignOp : SurfaceAssignOp → Surface.AssignOp
  | .set => .set
  | .add => .add
  | .subtract => .subtract
  | .multiply => .multiply
  | .divide => .divide
  | .remainder => .remainder
  | .bit_xor => .bitXor
  | .shift_left => .shiftLeft
  | .shift_right => .shiftRight
  | .bit_and => .bitAnd
  | .bit_or => .bitOr

def decodeSurfaceLiteral : SurfaceLiteral → Option Surface.Literal
  | .integer _ text => some (.integer text)
  | .float _ text => some (.float text)
  | .string _ text => .string <$> SurfaceSyntax.stringLiteralValue? text
  | .character _ text => .character <$> SurfaceSyntax.characterLiteralValue? text
  | .boolean value => some (.boolean value)

mutual
  def decodeSurfaceStructFieldValueWithFuel :
      Nat → SurfaceStructFieldValue → Option (Surface.Name × Surface.Expr)
    | 0, _ => none
    | fuel + 1, field => do
        pure (field.name.text, ← decodeSurfaceExprWithFuel fuel field.value)

  def decodeSurfaceExprWithFuel : Nat → SurfaceExpr → Option Surface.Expr
    | 0, _ => none
    | fuel + 1, expression => do
        match expression.value with
        | .literal literal => .literal <$> decodeSurfaceLiteral literal
        | .path path => .path <$> decodeSurfacePathWithFuel fuel path
        | .array elements =>
            .array <$> elements.mapM (decodeSurfaceExprWithFuel fuel)
        | .struct_value path fields =>
            pure (.structValue (← decodeSurfacePathWithFuel fuel path)
              (← fields.mapM (decodeSurfaceStructFieldValueWithFuel fuel)))
        | .unary operator operand =>
            pure (.unary (decodeSurfaceUnaryOp operator)
              (← decodeSurfaceExprWithFuel fuel operand))
        | .binary operator left right =>
            pure (.binary (decodeSurfaceBinaryOp operator)
              (← decodeSurfaceExprWithFuel fuel left)
              (← decodeSurfaceExprWithFuel fuel right))
        | .assign operator place value =>
            pure (.assign (decodeSurfaceAssignOp operator)
              (← decodeSurfaceExprWithFuel fuel place)
              (← decodeSurfaceExprWithFuel fuel value))
        | .call callee arguments =>
            pure (.call (← decodeSurfaceExprWithFuel fuel callee)
              (← arguments.mapM (decodeSurfaceExprWithFuel fuel)))
        | .index base index =>
            pure (.index (← decodeSurfaceExprWithFuel fuel base)
              (← decodeSurfaceExprWithFuel fuel index))
        | .member base name =>
            pure (.member (← decodeSurfaceExprWithFuel fuel base) name.text)
end

def decodeSurfaceExpr (fuel : Nat) (expression : SurfaceExpr) : Option Surface.Expr :=
  decodeSurfaceExprWithFuel fuel expression

mutual
  def decodeSurfaceStmtWithFuel : Nat → SurfaceStmt → Option Surface.Stmt
    | 0, _ => none
    | fuel + 1, statement => do
        match statement.value with
        | .let_local name type initializer =>
            pure (.letLocal name.text
              (← type.mapM (decodeSurfaceTypeExprWithFuel fuel))
              (← initializer.mapM (decodeSurfaceExprWithFuel fuel)))
        | .return_value value =>
            pure (.returnValue (← value.mapM (decodeSurfaceExprWithFuel fuel)))
        | .if_then_else condition thenBody elseBody =>
            pure (.ifThenElse (← decodeSurfaceExprWithFuel fuel condition)
              (← decodeSurfaceStmtsWithFuel fuel thenBody)
              (← decodeSurfaceStmtsWithFuel fuel elseBody))
        | .while_loop condition body =>
            pure (.whileLoop (← decodeSurfaceExprWithFuel fuel condition)
              (← decodeSurfaceStmtsWithFuel fuel body))
        | .block body => .block <$> decodeSurfaceStmtsWithFuel fuel body
        | .expression expression =>
            .expression <$> decodeSurfaceExprWithFuel fuel expression
        | .break_loop => some .breakLoop
        | .continue_loop => some .continueLoop

  def decodeSurfaceStmtsWithFuel : Nat → List SurfaceStmt → Option (List Surface.Stmt)
    | 0, [] => some []
    | 0, _ :: _ => none
    | _ + 1, [] => some []
    | fuel + 1, head :: tail => do
        pure ((← decodeSurfaceStmtWithFuel fuel head) ::
          (← decodeSurfaceStmtsWithFuel fuel tail))
end

def decodeSurfaceStmt (fuel : Nat) (statement : SurfaceStmt) : Option Surface.Stmt :=
  decodeSurfaceStmtWithFuel fuel statement

def decodeSurfaceStmts (fuel : Nat) (statements : List SurfaceStmt) : Option (List Surface.Stmt) :=
  decodeSurfaceStmtsWithFuel fuel statements

def decodeSurfaceParameter (fuel : Nat)
    (parameter : SurfaceParameter) : Option Surface.Parameter := do
  pure (.named parameter.name.text
    (← decodeSurfaceTypeExpr fuel parameter.type_expression))

def decodeSurfaceFunction (fuel : Nat) (function : SurfaceFunction) : Option Surface.Function := do
  pure {
    name := function.name.text
    isPublic := function.is_public
    parameters := ← function.parameters.mapM (decodeSurfaceParameter fuel)
    returnType := ← function.return_type.mapM (decodeSurfaceTypeExpr fuel)
    body := ← decodeSurfaceStmts fuel function.body
  }

def decodeSurfaceStructField (fuel : Nat)
    (field : SurfaceStructField) : Option Surface.StructField := do
  pure {
    name := field.name.text
    type := ← decodeSurfaceTypeExpr fuel field.type_expression
  }

def decodeSurfaceStruct (fuel : Nat) (declaration : SurfaceStruct) : Option Surface.StructDecl := do
  pure {
    name := declaration.name.text
    isPublic := declaration.is_public
    fields := ← declaration.fields.mapM (decodeSurfaceStructField fuel)
  }

def decodeSurfaceItem (fuel : Nat) (item : SurfaceItem) : Option Surface.Item := do
  match item.value with
  | .module path => .module <$> decodeSurfacePath fuel path
  | .import_path path => .importPath <$> decodeSurfacePath fuel path
  | .function function => .function <$> decodeSurfaceFunction fuel function
  | .constant name isPublic type value =>
      pure (.constant name.text isPublic
        (← decodeSurfaceTypeExpr fuel type) (← decodeSurfaceExpr fuel value))
  | .type_alias name isPublic target =>
      pure (.typeAlias name.text isPublic [] [] (← decodeSurfaceTypeExpr fuel target))
  | .structure declaration => .structure <$> decodeSurfaceStruct fuel declaration

def decodeSurfaceFile (fuel : Nat) (file : SurfaceFile) : Option Surface.File := do
  pure { items := ← file.value.items.mapM (decodeSurfaceItem fuel) }

def decodeArtifactSurface (artifact : Artifact) : Option Surface.File := do
  let surface ← artifact.surface
  decodeSurfaceFile (artifact.tokens.length + 1) surface

end Lanius.Extraction
