import Lanius.LiteralSyntax

namespace Lanius.ConcreteSyntax

open Lanius

/-! ## Concrete expression normalization

The checked-in grammar is deliberately right-recursive. These definitions
state the source-language trees produced after removing that parser
scaffolding. They are independent of the compiler's raw parse-node layout. -/

/-- The ten binary-precedence layers, from weakest to strongest. -/
inductive BinaryLayer where
  | logicalOr
  | logicalAnd
  | bitOr
  | bitXor
  | bitAnd
  | equality
  | comparison
  | shift
  | additive
  | multiplicative
deriving DecidableEq

def binaryLayer : Surface.BinaryOp → BinaryLayer
  | .logicalOr => .logicalOr
  | .logicalAnd => .logicalAnd
  | .bitOr => .bitOr
  | .bitXor => .bitXor
  | .bitAnd => .bitAnd
  | .equal | .notEqual => .equality
  | .less | .greater | .lessEqual | .greaterEqual => .comparison
  | .shiftLeft | .shiftRight => .shift
  | .add | .subtract => .additive
  | .multiply | .divide | .remainder => .multiplicative

structure BinaryLink where
  operator : Surface.BinaryOp
  right : Surface.Expr

/-- Normalize one grammar precedence layer left-to-right. In particular,
    `a - b - c` becomes `(a - b) - c`, not `a - (b - c)`. -/
def foldBinaryLeft : Surface.Expr → List BinaryLink → Surface.Expr
  | result, [] => result
  | result, link :: tail =>
      foldBinaryLeft (.binary link.operator result link.right) tail

def BinaryChainLowers
    (layer : BinaryLayer) (first : Surface.Expr) (tail : List BinaryLink)
    (result : Surface.Expr) : Prop :=
  (∀ link, link ∈ tail → binaryLayer link.operator = layer) ∧
    foldBinaryLeft first tail = result

theorem BinaryChainLowers.functional
    (left : BinaryChainLowers layer first tail leftResult)
    (right : BinaryChainLowers layer first tail rightResult) :
    leftResult = rightResult := by
  exact left.2.symm.trans right.2

structure AssignmentLink where
  operator : Surface.AssignOp
  right : Surface.Expr

/-- Normalize an assignment chain supplied in source order while nesting its
    result to the right: `a = b = c` becomes `a = (b = c)`. -/
def foldAssignmentRight : Surface.Expr → List AssignmentLink → Surface.Expr
  | result, [] => result
  | left, link :: tail =>
      .assign link.operator left (foldAssignmentRight link.right tail)

def AssignmentChainLowers
    (first : Surface.Expr) (tail : List AssignmentLink) (result : Surface.Expr) : Prop :=
  foldAssignmentRight first tail = result

theorem AssignmentChainLowers.functional
    (left : AssignmentChainLowers first tail leftResult)
    (right : AssignmentChainLowers first tail rightResult) :
    leftResult = rightResult := by
  exact left.symm.trans right

inductive Postfix where
  | call (arguments : List Surface.Expr)
  | index (index : Surface.Expr)
  | member (name : Surface.Name)

def applyPostfix : Surface.Expr → Postfix → Surface.Expr
  | base, .call arguments => .call base arguments
  | base, .index index => .index base index
  | base, .member name => .member base name

/-- Calls, indexing, and member selection bind in source order around the
    preceding value: `f(x)[i].field` becomes `((f(x))[i]).field`. -/
def foldPostfix : Surface.Expr → List Postfix → Surface.Expr
  | result, [] => result
  | result, operation :: tail => foldPostfix (applyPostfix result operation) tail

def PostfixChainLowers
    (base : Surface.Expr) (tail : List Postfix) (result : Surface.Expr) : Prop :=
  foldPostfix base tail = result

theorem PostfixChainLowers.functional
    (left : PostfixChainLowers base tail leftResult)
    (right : PostfixChainLowers base tail rightResult) :
    leftResult = rightResult := by
  exact left.symm.trans right

/-! ## Composed expression grammar

`Surface.Expr` intentionally forgets parentheses and precedence scaffolding.
The indexed tree below retains exactly the recursive shape of the expression
nonterminals in `grammar/lanius.bnf`.  An ill-layered tree such as an additive
operand containing an unparenthesized assignment is therefore not
representable.  Literal spelling and path formation are separate lexical
boundaries; this tree starts once those leaves have been decoded.
-/

inductive ExprLevel where
  | assignment
  | logicalOr
  | logicalAnd
  | bitOr
  | bitXor
  | bitAnd
  | equality
  | comparison
  | shift
  | additive
  | multiplicative
  | unary
  | postfix
  | primary

/-- The operator tokens admitted at each binary grammar layer. -/
inductive ParsedBinaryOp : BinaryLayer → Type where
  | logicalOr : ParsedBinaryOp .logicalOr
  | logicalAnd : ParsedBinaryOp .logicalAnd
  | bitOr : ParsedBinaryOp .bitOr
  | bitXor : ParsedBinaryOp .bitXor
  | bitAnd : ParsedBinaryOp .bitAnd
  | equal : ParsedBinaryOp .equality
  | notEqual : ParsedBinaryOp .equality
  | less : ParsedBinaryOp .comparison
  | greater : ParsedBinaryOp .comparison
  | lessEqual : ParsedBinaryOp .comparison
  | greaterEqual : ParsedBinaryOp .comparison
  | shiftLeft : ParsedBinaryOp .shift
  | shiftRight : ParsedBinaryOp .shift
  | add : ParsedBinaryOp .additive
  | subtract : ParsedBinaryOp .additive
  | multiply : ParsedBinaryOp .multiplicative
  | divide : ParsedBinaryOp .multiplicative
  | remainder : ParsedBinaryOp .multiplicative

def ParsedBinaryOp.surface : ParsedBinaryOp layer → Surface.BinaryOp
  | .logicalOr => .logicalOr
  | .logicalAnd => .logicalAnd
  | .bitOr => .bitOr
  | .bitXor => .bitXor
  | .bitAnd => .bitAnd
  | .equal => .equal
  | .notEqual => .notEqual
  | .less => .less
  | .greater => .greater
  | .lessEqual => .lessEqual
  | .greaterEqual => .greaterEqual
  | .shiftLeft => .shiftLeft
  | .shiftRight => .shiftRight
  | .add => .add
  | .subtract => .subtract
  | .multiply => .multiply
  | .divide => .divide
  | .remainder => .remainder

theorem ParsedBinaryOp.surface_layer (operator : ParsedBinaryOp layer) :
    binaryLayer operator.surface = layer := by
  cases operator <;> rfl

mutual
  inductive ParsedExpr : ExprLevel → Type where
    | assignment
        (first : ParsedExpr .logicalOr)
        (tail : Option (Surface.AssignOp × ParsedExpr .assignment)) :
        ParsedExpr .assignment
    | logicalOr
        (first : ParsedExpr .logicalAnd)
        (tail : List (ParsedBinaryOp .logicalOr × ParsedExpr .logicalAnd)) :
        ParsedExpr .logicalOr
    | logicalAnd
        (first : ParsedExpr .bitOr)
        (tail : List (ParsedBinaryOp .logicalAnd × ParsedExpr .bitOr)) :
        ParsedExpr .logicalAnd
    | bitOr
        (first : ParsedExpr .bitXor)
        (tail : List (ParsedBinaryOp .bitOr × ParsedExpr .bitXor)) :
        ParsedExpr .bitOr
    | bitXor
        (first : ParsedExpr .bitAnd)
        (tail : List (ParsedBinaryOp .bitXor × ParsedExpr .bitAnd)) :
        ParsedExpr .bitXor
    | bitAnd
        (first : ParsedExpr .equality)
        (tail : List (ParsedBinaryOp .bitAnd × ParsedExpr .equality)) :
        ParsedExpr .bitAnd
    | equality
        (first : ParsedExpr .comparison)
        (tail : List (ParsedBinaryOp .equality × ParsedExpr .comparison)) :
        ParsedExpr .equality
    | comparison
        (first : ParsedExpr .shift)
        (tail : List (ParsedBinaryOp .comparison × ParsedExpr .shift)) :
        ParsedExpr .comparison
    | shift
        (first : ParsedExpr .additive)
        (tail : List (ParsedBinaryOp .shift × ParsedExpr .additive)) :
        ParsedExpr .shift
    | additive
        (first : ParsedExpr .multiplicative)
        (tail : List (ParsedBinaryOp .additive × ParsedExpr .multiplicative)) :
        ParsedExpr .additive
    | multiplicative
        (first : ParsedExpr .unary)
        (tail : List (ParsedBinaryOp .multiplicative × ParsedExpr .unary)) :
        ParsedExpr .multiplicative
    | unary (operator : Surface.UnaryOp) (operand : ParsedExpr .unary) :
        ParsedExpr .unary
    | unaryBase (base : ParsedExpr .postfix) : ParsedExpr .unary
    | postfix (base : ParsedExpr .primary) (tail : List ParsedPostfix) :
        ParsedExpr .postfix
    | primary (value : ParsedPrimary) : ParsedExpr .primary

  inductive ParsedPostfix where
    | call (arguments : List (ParsedExpr .assignment))
    | index (index : ParsedExpr .assignment)
    | member (name : Surface.Name)

  inductive ParsedPrimary where
    | literal (literal : Surface.Literal)
    | path (path : Surface.Path)
    | selfValue
    | array (elements : List (ParsedExpr .assignment))
    | structValue
        (path : Surface.Path)
        (fields : List (Surface.Name × ParsedExpr .assignment))
    | group (expression : ParsedExpr .assignment)
    | matchValue
        (scrutinee : ParsedExpr .assignment)
        (arms : List (Surface.Pattern × ParsedExpr .assignment))
end

/-- Embed a primary in the unary grammar without adding an operator. -/
def ParsedExpr.fromPrimary (value : ParsedPrimary) : ParsedExpr .unary :=
  .unaryBase (.postfix (.primary value) [])

/-- Embed a multiplicative expression through all weaker binary layers and
    the assignment nonterminal without adding another operator. -/
def ParsedExpr.fromMultiplicative
    (value : ParsedExpr .multiplicative) : ParsedExpr .assignment :=
  let additive := ParsedExpr.additive value []
  let shift := ParsedExpr.shift additive []
  let comparison := ParsedExpr.comparison shift []
  let equality := ParsedExpr.equality comparison []
  let bitAnd := ParsedExpr.bitAnd equality []
  let bitXor := ParsedExpr.bitXor bitAnd []
  let bitOr := ParsedExpr.bitOr bitXor []
  let logicalAnd := ParsedExpr.logicalAnd bitOr []
  let logicalOr := ParsedExpr.logicalOr logicalAnd []
  .assignment logicalOr none

/-- Embed an additive expression through all weaker binary layers and the
    assignment nonterminal without adding another operator. -/
def ParsedExpr.fromAdditive
    (value : ParsedExpr .additive) : ParsedExpr .assignment :=
  let shift := ParsedExpr.shift value []
  let comparison := ParsedExpr.comparison shift []
  let equality := ParsedExpr.equality comparison []
  let bitAnd := ParsedExpr.bitAnd equality []
  let bitXor := ParsedExpr.bitXor bitAnd []
  let bitOr := ParsedExpr.bitOr bitXor []
  let logicalAnd := ParsedExpr.logicalAnd bitOr []
  let logicalOr := ParsedExpr.logicalOr logicalAnd []
  .assignment logicalOr none

mutual
  def lowerParsedExpr : {level : ExprLevel} → ParsedExpr level → Surface.Expr
    | _, .assignment first none => lowerParsedExpr first
    | _, .assignment first (some (operator, right)) =>
        .assign operator (lowerParsedExpr first) (lowerParsedExpr right)
    | _, .logicalOr first tail =>
        foldBinaryLeft (lowerParsedExpr first) (lowerParsedBinaryTail tail)
    | _, .logicalAnd first tail =>
        foldBinaryLeft (lowerParsedExpr first) (lowerParsedBinaryTail tail)
    | _, .bitOr first tail =>
        foldBinaryLeft (lowerParsedExpr first) (lowerParsedBinaryTail tail)
    | _, .bitXor first tail =>
        foldBinaryLeft (lowerParsedExpr first) (lowerParsedBinaryTail tail)
    | _, .bitAnd first tail =>
        foldBinaryLeft (lowerParsedExpr first) (lowerParsedBinaryTail tail)
    | _, .equality first tail =>
        foldBinaryLeft (lowerParsedExpr first) (lowerParsedBinaryTail tail)
    | _, .comparison first tail =>
        foldBinaryLeft (lowerParsedExpr first) (lowerParsedBinaryTail tail)
    | _, .shift first tail =>
        foldBinaryLeft (lowerParsedExpr first) (lowerParsedBinaryTail tail)
    | _, .additive first tail =>
        foldBinaryLeft (lowerParsedExpr first) (lowerParsedBinaryTail tail)
    | _, .multiplicative first tail =>
        foldBinaryLeft (lowerParsedExpr first) (lowerParsedBinaryTail tail)
    | _, .unary operator operand => .unary operator (lowerParsedExpr operand)
    | _, .unaryBase base => lowerParsedExpr base
    | _, .postfix base tail =>
        foldPostfix (lowerParsedExpr base) (lowerParsedPostfixes tail)
    | _, .primary value => lowerParsedPrimary value

  def lowerParsedBinaryTail :
      List (ParsedBinaryOp layer × ParsedExpr level) → List BinaryLink
    | [] => []
    | (operator, right) :: tail =>
        { operator := operator.surface, right := lowerParsedExpr right } ::
          lowerParsedBinaryTail tail

  def lowerParsedPostfixes : List ParsedPostfix → List Postfix
    | [] => []
    | .call arguments :: tail =>
        .call (lowerParsedExprs arguments) :: lowerParsedPostfixes tail
    | .index index :: tail =>
        .index (lowerParsedExpr index) :: lowerParsedPostfixes tail
    | .member name :: tail => .member name :: lowerParsedPostfixes tail

  def lowerParsedExprs : List (ParsedExpr .assignment) → List Surface.Expr
    | [] => []
    | head :: tail => lowerParsedExpr head :: lowerParsedExprs tail

  def lowerParsedFields :
      List (Surface.Name × ParsedExpr .assignment) →
      List (Surface.Name × Surface.Expr)
    | [] => []
    | (name, value) :: tail =>
        (name, lowerParsedExpr value) :: lowerParsedFields tail

  def lowerParsedArms :
      List (Surface.Pattern × ParsedExpr .assignment) →
      List (Surface.Pattern × Surface.Expr)
    | [] => []
    | (pattern, body) :: tail =>
        (pattern, lowerParsedExpr body) :: lowerParsedArms tail

  def lowerParsedPrimary : ParsedPrimary → Surface.Expr
    | .literal literal => .literal literal
    | .path path => .path path
    | .selfValue => .selfValue
    | .array elements => .array (lowerParsedExprs elements)
    | .structValue path fields => .structValue path (lowerParsedFields fields)
    | .group expression => lowerParsedExpr expression
    | .matchValue scrutinee arms =>
        .matchValue (lowerParsedExpr scrutinee) (lowerParsedArms arms)
end

theorem lowerParsedBinaryTail_layer
    (tail : List (ParsedBinaryOp layer × ParsedExpr operandLevel)) :
    ∀ link, link ∈ lowerParsedBinaryTail tail →
      binaryLayer link.operator = layer := by
  induction tail with
  | nil => simp [lowerParsedBinaryTail]
  | cons head tail inductionHypothesis =>
      rcases head with ⟨operator, right⟩
      intro link membership
      simp only [lowerParsedBinaryTail, List.mem_cons] at membership
      rcases membership with equal | membership
      · subst link
        exact operator.surface_layer
      · exact inductionHypothesis link membership

def ParsedExpressionLowers
    (parsed : ParsedExpr .assignment) (surface : Surface.Expr) : Prop :=
  lowerParsedExpr parsed = surface

theorem ParsedExpressionLowers.functional
    (left : ParsedExpressionLowers parsed leftResult)
    (right : ParsedExpressionLowers parsed rightResult) :
    leftResult = rightResult := by
  exact left.symm.trans right

/-- A complete concrete expression combines the indexed precedence tree with
    the orthogonal leaf constraints from `SurfaceSyntax`: nonempty paths,
    grammar-shaped nested types, patterns, and recursively valid primaries. -/
structure ConcreteExpression where
  parsed : ParsedExpr .assignment
  wellFormed : SurfaceSyntax.ExprWellFormed (lowerParsedExpr parsed)

def lowerConcreteExpression (expression : ConcreteExpression) : Surface.Expr :=
  lowerParsedExpr expression.parsed

theorem lowerConcreteExpression_wellFormed (expression : ConcreteExpression) :
    SurfaceSyntax.ExprWellFormed (lowerConcreteExpression expression) :=
  expression.wellFormed

def ConcreteExpressionLowers
    (concrete : ConcreteExpression) (surface : Surface.Expr) : Prop :=
  lowerConcreteExpression concrete = surface

theorem ConcreteExpressionLowers.functional
    (left : ConcreteExpressionLowers concrete leftResult)
    (right : ConcreteExpressionLowers concrete rightResult) :
    leftResult = rightResult := by
  exact left.symm.trans right

/-! ## Token-bearing primary forms -/

def literalPrimaryFromToken?
    (kind : SurfaceSyntax.LiteralTokenKind) (token : String) :
    Option Surface.Expr :=
  (SurfaceSyntax.literalFromToken? kind token).map .literal

def patternFromToken?
    (kind : SurfaceSyntax.LiteralTokenKind) (token : String) :
    Option Surface.Pattern :=
  match kind with
  | .integer => do
      let _ ← Elaboration.parseUnsignedInteger token
      pure (.integer token)
  | .boolean =>
      match token with
      | "true" => some (.boolean true)
      | "false" => some (.boolean false)
      | _ => none
  | .float | .string | .character => none

/-- Array-size literals are decoded to mathematical naturals at the concrete
    syntax boundary. A named size remains a const-parameter reference. -/
def arrayLengthLiteralFromToken? (token : String) : Option Surface.ArrayLength :=
  (Elaboration.parseUnsignedInteger token).map .literal

/-- Import strings and external ABI names are reclassified string tokens, so
    they use the same delimiter and escape semantics as expression strings. -/
def importStringItemFromToken? (token : String) : Option Surface.Item :=
  (SurfaceSyntax.stringLiteralValue? token).map .importString

def externAbiFromToken? (token : String) : Option String :=
  SurfaceSyntax.stringLiteralValue? token

def LiteralPrimarySpells
    (kind : SurfaceSyntax.LiteralTokenKind) (token : String)
    (expression : Surface.Expr) : Prop :=
  literalPrimaryFromToken? kind token = some expression

def PatternTokenSpells
    (kind : SurfaceSyntax.LiteralTokenKind) (token : String)
    (pattern : Surface.Pattern) : Prop :=
  patternFromToken? kind token = some pattern

def ArrayLengthTokenSpells
    (token : String) (length : Surface.ArrayLength) : Prop :=
  arrayLengthLiteralFromToken? token = some length

def ImportStringTokenSpells (token value : String) : Prop :=
  importStringItemFromToken? token = some (.importString value)

def ExternAbiTokenSpells (token value : String) : Prop :=
  externAbiFromToken? token = some value

theorem LiteralPrimarySpells.functional
    (left : LiteralPrimarySpells kind token leftExpression)
    (right : LiteralPrimarySpells kind token rightExpression) :
    leftExpression = rightExpression := by
  exact Option.some.inj (left.symm.trans right)

theorem PatternTokenSpells.functional
    (left : PatternTokenSpells kind token leftPattern)
    (right : PatternTokenSpells kind token rightPattern) :
    leftPattern = rightPattern := by
  exact Option.some.inj (left.symm.trans right)

theorem ArrayLengthTokenSpells.functional
    (left : ArrayLengthTokenSpells token leftLength)
    (right : ArrayLengthTokenSpells token rightLength) :
    leftLength = rightLength := by
  exact Option.some.inj (left.symm.trans right)

theorem ImportStringTokenSpells.functional
    (left : ImportStringTokenSpells token leftValue)
    (right : ImportStringTokenSpells token rightValue) :
    leftValue = rightValue := by
  have equalItems := Option.some.inj (left.symm.trans right)
  cases equalItems
  rfl

theorem ExternAbiTokenSpells.functional
    (left : ExternAbiTokenSpells token leftValue)
    (right : ExternAbiTokenSpells token rightValue) :
    leftValue = rightValue := by
  exact Option.some.inj (left.symm.trans right)

end Lanius.ConcreteSyntax
