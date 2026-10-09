import Lanius.Core

namespace Lanius.Core

/-- Proofs name parameters by their declared position, not lexer token IDs. -/
def Function.argumentId (function : Function) (position : Nat) : Lanius.VarId :=
  ((function.parameters[position]?).map Prod.fst).getD 0

def Stmt.bindingIds : Stmt → List Lanius.VarId
  | .letLocal id _ _ body | .letUninitialized id _ body => id :: body.bindingIds
  | .sequence first second | .ifThenElse _ first second => first.bindingIds ++ second.bindingIds
  | .whileLoop _ body => body.bindingIds
  | .forValues id _ body | .forRange id _ _ _ body => id :: body.bindingIds
  | _ => []

/-- Preorder local bindings in the actual body. Missing bindings cannot
    establish a body contract; the caller must still prove its statement. -/
def Function.bindingId (function : Function) (position : Nat) : Lanius.VarId :=
  (((function.body.map Stmt.bindingIds).getD [])[position]?).getD 0

def Stmt.bindingInitializer? (binding : Lanius.VarId) : Stmt → Option Expr
  | .letLocal id _ initial body =>
      if id == binding then some initial else body.bindingInitializer? binding
  | .letUninitialized _ _ body | .whileLoop _ body |
      .forValues _ _ body | .forRange _ _ _ _ body => body.bindingInitializer? binding
  | .sequence first second | .ifThenElse _ first second =>
      (first.bindingInitializer? binding).or (second.bindingInitializer? binding)
  | _ => none

/-- Select an actual initializer; the enclosing execution proof still checks
    the source statement, including its ID, type and continuation. -/
def Function.bindingInitializer (function : Function) (position : Nat) : Expr :=
  (function.body.bind (Stmt.bindingInitializer? (function.bindingId position))).getD (.value .unit)

/-- Select the actual scoped statement, including its initializer and entire
    continuation. Clients must prove execution of that statement, not only
    an independently reconstructed fragment. -/
def Stmt.bindingStatement? (binding : Lanius.VarId) : Stmt → Option Stmt
  | statement@(.letLocal id _ _ body) | statement@(.letUninitialized id _ body) =>
      if id == binding then some statement else body.bindingStatement? binding
  | .whileLoop _ body | .forValues _ _ body | .forRange _ _ _ _ body =>
      body.bindingStatement? binding
  | .sequence first second | .ifThenElse _ first second =>
      (first.bindingStatement? binding).or (second.bindingStatement? binding)
  | _ => none

def Function.bindingStatement (function : Function) (position : Nat) : Stmt :=
  (function.body.bind (Stmt.bindingStatement? (function.bindingId position))).getD .skip

/-- Effect statements in source order, excluding initializers and returns.
    This only selects syntax; clients still prove its complete evaluation. -/
def Stmt.effectExpressions : Stmt → List Expr
  | .expression value => [value]
  | .letLocal _ _ _ body | .letUninitialized _ _ body |
      .whileLoop _ body | .forValues _ _ body | .forRange _ _ _ _ body => body.effectExpressions
  | .sequence first second | .ifThenElse _ first second => first.effectExpressions ++ second.effectExpressions
  | _ => []

def Function.effectExpression (function : Function) (position : Nat) : Expr :=
  ((((function.body.map Stmt.effectExpressions).getD [])[position]?).getD (.value .unit))

/-- Select actual loops in preorder, including nested loops. This is a syntax
    query, not an execution certificate or a replacement program tree. -/
def Stmt.whileLoops : Stmt → List (Expr × Stmt)
  | .whileLoop guard body => (guard, body) :: body.whileLoops
  | .letLocal _ _ _ body | .letUninitialized _ _ body |
      .forValues _ _ body | .forRange _ _ _ _ body => body.whileLoops
  | .sequence first second | .ifThenElse _ first second => first.whileLoops ++ second.whileLoops
  | _ => []

def Function.whileLoop (function : Function) (position : Nat) : Expr × Stmt :=
  ((((function.body.map Stmt.whileLoops).getD [])[position]?).getD (.value (.boolean true), .skip))

end Lanius.Core
