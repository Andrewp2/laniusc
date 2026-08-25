import Lanius.ConcreteSyntax

namespace Lanius.ConcreteProgramSyntax

open Lanius
open Lanius.ConcreteSyntax

/-!
The concrete expression tree retains precedence and grouping until it is
lowered to `Surface.Expr`. This module carries that boundary through statement
bodies and declarations. It deliberately starts after identifier and type-path
tokens have been assembled; `SurfaceSyntax` remains the authority for those
leaf-shape constraints.
-/

structure ConcreteForIterable where
  value : Surface.ForIterable
  wellFormed : SurfaceSyntax.ForIterableWellFormed value

mutual
  inductive ParsedStmt where
    | letLocal
        (name : Surface.Name)
        (type : Option Surface.TypeExpr)
        (initializer : Option ConcreteExpression)
    | returnValue (value : Option ConcreteExpression)
    | ifThenElse
        (condition : ConcreteExpression)
        (thenBody elseBody : List ParsedStmt)
    | whileLoop (condition : ConcreteExpression) (body : List ParsedStmt)
    | forLoop
        (name : Surface.Name)
        (iterable : ConcreteForIterable)
        (body : List ParsedStmt)
    | breakLoop
    | continueLoop
    | block (body : List ParsedStmt)
    | expression (expression : ConcreteExpression)
end

mutual
  def lowerParsedStmt : ParsedStmt → Surface.Stmt
    | .letLocal name type initializer =>
        .letLocal name type (initializer.map lowerConcreteExpression)
    | .returnValue value => .returnValue (value.map lowerConcreteExpression)
    | .ifThenElse condition thenBody elseBody =>
        .ifThenElse (lowerConcreteExpression condition)
          (lowerParsedStmts thenBody) (lowerParsedStmts elseBody)
    | .whileLoop condition body =>
        .whileLoop (lowerConcreteExpression condition) (lowerParsedStmts body)
    | .forLoop name iterable body =>
        .forLoop name iterable.value (lowerParsedStmts body)
    | .breakLoop => .breakLoop
    | .continueLoop => .continueLoop
    | .block body => .block (lowerParsedStmts body)
    | .expression expression => .expression (lowerConcreteExpression expression)

  def lowerParsedStmts : List ParsedStmt → List Surface.Stmt
    | [] => []
    | head :: tail => lowerParsedStmt head :: lowerParsedStmts tail
end

/-- A body accepted at the concrete boundary contains a grammar proof for the
    complete lowered statement list. This composes the indexed expression tree
    with statement-specific type/path/iterable constraints. -/
structure ConcreteBody where
  parsed : List ParsedStmt
  wellFormed : SurfaceSyntax.StmtsWellFormed (lowerParsedStmts parsed)

def lowerConcreteBody (body : ConcreteBody) : List Surface.Stmt :=
  lowerParsedStmts body.parsed

theorem lowerConcreteBody_wellFormed (body : ConcreteBody) :
    SurfaceSyntax.StmtsWellFormed (lowerConcreteBody body) :=
  body.wellFormed

def ConcreteBodyLowers
    (concrete : ConcreteBody) (surface : List Surface.Stmt) : Prop :=
  lowerConcreteBody concrete = surface

theorem ConcreteBodyLowers.functional
    (left : ConcreteBodyLowers concrete leftResult)
    (right : ConcreteBodyLowers concrete rightResult) :
    leftResult = rightResult := by
  exact left.symm.trans right

structure ParsedFunction where
  name : Surface.Name
  isPublic : Bool := false
  genericParameters : List Surface.GenericParameter := []
  parameters : List Surface.Parameter := []
  returnType : Option Surface.TypeExpr := none
  wherePredicates : List Surface.WherePredicate := []
  body : ConcreteBody

def lowerParsedFunction (function : ParsedFunction) : Surface.Function := {
  name := function.name
  isPublic := function.isPublic
  genericParameters := function.genericParameters
  parameters := function.parameters
  returnType := function.returnType
  wherePredicates := function.wherePredicates
  body := lowerConcreteBody function.body
}

def ParsedFunctionLowers
    (parsed : ParsedFunction) (surface : Surface.Function) : Prop :=
  lowerParsedFunction parsed = surface

theorem ParsedFunctionLowers.functional
    (left : ParsedFunctionLowers parsed leftResult)
    (right : ParsedFunctionLowers parsed rightResult) :
    leftResult = rightResult := by
  exact left.symm.trans right

structure ParsedExternAbi where
  token : String
  value : String
  spelling : ExternAbiTokenSpells token value

structure ParsedExternFunction where
  name : Surface.Name
  isPublic : Bool := false
  abi : Option ParsedExternAbi := none
  genericParameters : List Surface.GenericParameter := []
  parameters : List Surface.Parameter := []
  returnType : Option Surface.TypeExpr := none
  wherePredicates : List Surface.WherePredicate := []

def lowerParsedExternFunction
    (function : ParsedExternFunction) : Surface.ExternFunction := {
  name := function.name
  isPublic := function.isPublic
  abi := function.abi.map (·.value)
  genericParameters := function.genericParameters
  parameters := function.parameters
  returnType := function.returnType
  wherePredicates := function.wherePredicates
}

structure ParsedTraitMethod where
  signature : ParsedExternFunction

def lowerParsedTraitMethod (method : ParsedTraitMethod) : Surface.TraitMethod := {
  signature := lowerParsedExternFunction method.signature
}

structure ParsedTraitDecl where
  name : Surface.Name
  isPublic : Bool := false
  genericParameters : List Surface.GenericParameter := []
  wherePredicates : List Surface.WherePredicate := []
  methods : List ParsedTraitMethod := []

def lowerParsedTraitDecl (declaration : ParsedTraitDecl) : Surface.TraitDecl := {
  name := declaration.name
  isPublic := declaration.isPublic
  genericParameters := declaration.genericParameters
  wherePredicates := declaration.wherePredicates
  methods := declaration.methods.map lowerParsedTraitMethod
}

structure ParsedImplDecl where
  isPublic : Bool := false
  genericParameters : List Surface.GenericParameter := []
  traitType : Option Surface.TypeExpr := none
  receiverType : Surface.TypeExpr
  wherePredicates : List Surface.WherePredicate := []
  methods : List ParsedFunction := []

def lowerParsedImplDecl (declaration : ParsedImplDecl) : Surface.ImplDecl := {
  isPublic := declaration.isPublic
  genericParameters := declaration.genericParameters
  traitType := declaration.traitType
  receiverType := declaration.receiverType
  wherePredicates := declaration.wherePredicates
  methods := declaration.methods.map lowerParsedFunction
}

structure ParsedImportString where
  token : String
  value : String
  spelling : ImportStringTokenSpells token value

inductive ParsedItem where
  | module (path : Surface.Path)
  | importPath (path : Surface.Path)
  | importString (path : ParsedImportString)
  | function (declaration : ParsedFunction)
  | externFunction (declaration : ParsedExternFunction)
  | constant
      (name : Surface.Name)
      (isPublic : Bool)
      (type : Surface.TypeExpr)
      (value : ConcreteExpression)
  | typeAlias
      (name : Surface.Name)
      (isPublic : Bool)
      (parameters : List Surface.GenericParameter)
      (predicates : List Surface.WherePredicate)
      (target : Surface.TypeExpr)
  | structure (declaration : Surface.StructDecl)
  | enumeration (declaration : Surface.EnumDecl)
  | trait (declaration : ParsedTraitDecl)
  | implementation (declaration : ParsedImplDecl)

def lowerParsedItem : ParsedItem → Surface.Item
  | .module path => .module path
  | .importPath path => .importPath path
  | .importString path => .importString path.value
  | .function declaration => .function (lowerParsedFunction declaration)
  | .externFunction declaration =>
      .externFunction (lowerParsedExternFunction declaration)
  | .constant name isPublic type value =>
      .constant name isPublic type (lowerConcreteExpression value)
  | .typeAlias name isPublic parameters predicates target =>
      .typeAlias name isPublic parameters predicates target
  | .structure declaration => .structure declaration
  | .enumeration declaration => .enumeration declaration
  | .trait declaration => .trait (lowerParsedTraitDecl declaration)
  | .implementation declaration =>
      .implementation (lowerParsedImplDecl declaration)

def ParsedItemLowers (parsed : ParsedItem) (surface : Surface.Item) : Prop :=
  lowerParsedItem parsed = surface

theorem ParsedItemLowers.functional
    (left : ParsedItemLowers parsed leftResult)
    (right : ParsedItemLowers parsed rightResult) :
    leftResult = rightResult := by
  exact left.symm.trans right

def lowerParsedItems : List ParsedItem → List Surface.Item
  | [] => []
  | head :: tail => lowerParsedItem head :: lowerParsedItems tail

/-- A complete concrete file admits exactly those declaration trees whose
    lowered surface file satisfies every production-shape constraint. -/
structure ConcreteFile where
  parsedItems : List ParsedItem
  wellFormed : SurfaceSyntax.FileWellFormed {
    items := lowerParsedItems parsedItems
  }

def lowerConcreteFile (file : ConcreteFile) : Surface.File := {
  items := lowerParsedItems file.parsedItems
}

theorem lowerConcreteFile_wellFormed (file : ConcreteFile) :
    SurfaceSyntax.FileWellFormed (lowerConcreteFile file) :=
  file.wellFormed

def ConcreteFileLowers
    (concrete : ConcreteFile) (surface : Surface.File) : Prop :=
  lowerConcreteFile concrete = surface

theorem ConcreteFileLowers.functional
    (left : ConcreteFileLowers concrete leftResult)
    (right : ConcreteFileLowers concrete rightResult) :
    leftResult = rightResult := by
  exact left.symm.trans right

end Lanius.ConcreteProgramSyntax
