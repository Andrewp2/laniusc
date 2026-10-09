import Lanius.TypedIR.Expression

namespace Lanius.TypedIR.Intrinsic

open Lanius Core Typing

/-- Loop scope and definite return are indices, not a second validation pass.
    A loop itself is not assumed to run; either side of a sequence may return. -/
inductive Stmt (signature : Signature) (result : Core.Ty) : Scope → Bool → Bool → Type where
  | skip : Stmt signature result context inLoop false
  | expression (value : Expr signature context type) : Stmt signature result context inLoop false
  | sequence (first : Stmt signature result context inLoop firstReturns)
      (second : Stmt signature result context inLoop secondReturns) :
      Stmt signature result context inLoop (firstReturns || secondReturns)
  | letLocal (id : VarId) (initializer : Expr signature context type)
      (body : Stmt signature result (context.bind id type) inLoop returns) :
      Stmt signature result context inLoop returns
  | letUninitialized (id : VarId) (type : Core.Ty)
      (body : Stmt signature result (context.bind id type) inLoop returns) :
      Stmt signature result context inLoop returns
  | ifThenElse (condition : Expr signature context (.scalar .bool))
      (thenBranch : Stmt signature result context inLoop firstReturns)
      (elseBranch : Stmt signature result context inLoop secondReturns) :
      Stmt signature result context inLoop (firstReturns && secondReturns)
  | whileLoop (condition : Expr signature context (.scalar .bool))
      (body : Stmt signature result context true returns) : Stmt signature result context inLoop false
  | forArray (id : VarId) (iterable : Expr signature context (.array element length))
      (body : Stmt signature result (context.bind id element) true returns) :
      Stmt signature result context inLoop false
  | forSlice (id : VarId) (iterable : Expr signature context (.slice element))
      (body : Stmt signature result (context.bind id element) true returns) :
      Stmt signature result context inLoop false
  | forRange (id : VarId) (start : Expr signature context (.scalar (.signed .i32)))
      (stop : Option (Expr signature context (.scalar (.signed .i32)))) (inclusive : Bool)
      (body : Stmt signature result (context.bind id (.scalar (.signed .i32))) true returns) :
      Stmt signature result context inLoop false
  | returnUnit (isUnit : result = .unit) : Stmt signature result context inLoop true
  | returnValue (value : Expr signature context result) : Stmt signature result context inLoop true
  | breakLoop : Stmt signature result context true false
  | continueLoop : Stmt signature result context true false

def Stmt.erase : Stmt signature result context inLoop returns → Core.Stmt
  | .skip => .skip
  | .expression value => .expression value.erase
  | .sequence first second => .sequence first.erase second.erase
  | .letLocal (type := type) id initializer body => .letLocal id type initializer.erase body.erase
  | .letUninitialized id type body => .letUninitialized id type body.erase
  | .ifThenElse condition first second => .ifThenElse condition.erase first.erase second.erase
  | .whileLoop condition body => .whileLoop condition.erase body.erase
  | .forArray id iterable body | .forSlice id iterable body => .forValues id iterable.erase body.erase
  | .forRange id start stop inclusive body => .forRange id start.erase (stop.map Expr.erase) inclusive body.erase
  | .returnUnit _ => .returnValue none
  | .returnValue value => .returnValue (some value.erase)
  | .breakLoop => .breakLoop
  | .continueLoop => .continueLoop

theorem Stmt.wellTyped (statement : Stmt signature result scope inLoop returns)
    (linked : signature.Realizes program) (valid : scope.Realizes context) : StmtHasType program result context inLoop statement.erase :=
  match statement with
  | .skip => .skip
  | .expression value => .expression (value.wellTyped linked valid)
  | .sequence first second => .sequence (first.wellTyped linked valid) (second.wellTyped linked valid)
  | .letLocal _ initializer body => .letLocal (initializer.wellTyped linked valid) (body.wellTyped linked (valid.bind _ _))
  | .letUninitialized _ _ body => .letUninitialized (body.wellTyped linked (valid.bind _ _))
  | .ifThenElse condition first second => .ifThenElse (condition.wellTyped linked valid) (first.wellTyped linked valid) (second.wellTyped linked valid)
  | .whileLoop condition body => .whileLoop (condition.wellTyped linked valid) (body.wellTyped linked valid)
  | .forArray _ iterable body => .forArray (iterable.wellTyped linked valid) (body.wellTyped linked (valid.bind _ _))
  | .forSlice _ iterable body => .forSlice (iterable.wellTyped linked valid) (body.wellTyped linked (valid.bind _ _))
  | .forRange _ start stop _ body => .forRange (start.wellTyped linked valid)
      (match stop with | none => .none | some value => .some (value.wellTyped linked valid)) (body.wellTyped linked (valid.bind _ _))
  | .returnUnit isUnit => .returnUnit isUnit
  | .returnValue value => .returnValue (value.wellTyped linked valid)
  | .breakLoop => .breakLoop
  | .continueLoop => .continueLoop

theorem Stmt.definitelyReturns (statement : Stmt signature result context inLoop returns) :
    returns = true → DefinitelyReturns statement.erase := by
  induction statement with
  | sequence first second left right =>
      intro accepted
      simp only [Bool.or_eq_true] at accepted
      rcases accepted with first | second
      · exact .sequenceLeft (left first)
      · exact .sequenceRight (right second)
  | letLocal id initializer body ih => exact fun accepted => .letLocal (ih accepted)
  | letUninitialized id type body ih => exact fun accepted => .letUninitialized (ih accepted)
  | ifThenElse condition first second left right =>
      intro accepted
      simp only [Bool.and_eq_true] at accepted
      exact .ifThenElse (left accepted.1) (right accepted.2)
  | returnUnit | returnValue => exact fun _ => .returnValue
  | skip | expression | whileLoop | forArray | forSlice | forRange | breakLoop | continueLoop =>
      intro impossible; cases impossible

/-- Construction enforces the exact parameter scope and the required return.
    The evidence below is metadata-sized; it does not mirror the function body. -/
inductive Body (signature : Signature) (parameters : List (VarId × Core.Ty)) (result : Core.Ty) where
  | defined (statement : Stmt signature result (Scope.parameters parameters) false returns)
      (returnsRequired : result = .unit ∨ returns = true)
  | host (service : HostService) (parametersMatch : parameters.map Prod.snd = service.parameterTypes := by rfl)
      (resultMatch : result = service.returnType := by rfl)
  | panic (noParameters : parameters = []) (unitResult : result = .unit)
  | unreachable (noParameters : parameters = []) (unitResult : result = .unit)

structure Function (signature : Signature) where
  id : FunctionId
  parameters : List (VarId × Core.Ty)
  result : Core.Ty
  body : Body signature parameters result

def Function.erase (function : Function signature) : Core.Function :=
  { id := function.id, parameters := function.parameters, returnType := function.result,
    body := match function.body with
      | .defined statement _ => some statement.erase
      | _ => none,
    external := match function.body with
      | .defined _ _ => none
      | .host service _ _ => some (.host service)
      | .panic _ _ => some .panic
      | .unreachable _ _ => some .unreachable }

theorem Function.wellTyped (function : Function signature) (linked : signature.Realizes program) :
    FunctionWellTyped program function.erase := by
  cases function with
  | mk id parameters result body =>
      cases body with
      | defined statement required =>
          refine ⟨rfl, statement.wellTyped linked (Scope.realizes _), ?_⟩
          exact required.imp_right statement.definitelyReturns
      | host service parametersMatch resultMatch => exact ⟨parametersMatch, resultMatch⟩
      | panic noParameters unitResult | unreachable noParameters unitResult => exact ⟨noParameters, unitResult⟩

end Lanius.TypedIR.Intrinsic
