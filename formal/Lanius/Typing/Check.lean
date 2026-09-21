import Lanius.Typing.Check.Expressions

namespace Lanius.Typing.Check

open Lanius

open Lanius.Core

open Lanius.Typing

def checkOptionExpr (program : Program) (context : Context) (type : Ty) :
    (expression : Option Expr) →
      Option (ProofOf (OptionExprHasType program context type expression))
  | none => some ⟨.none⟩
  | some expression => do
      let checked ← checkExpr program context expression type
      pure ⟨.some checked.down⟩

def checkStmt (program : Program) (returnType : Ty) (context : Context) (inLoop : Bool)
    (statement : Stmt) : Option (ProofOf (StmtHasType program returnType context inLoop statement)) :=
  match statement with
  | .skip => some ⟨.skip⟩
  | .expression expression =>
      do let checked ← checkExprAny program context expression
         pure ⟨.expression checked.2.down⟩
  | .sequence first second =>
      do let firstChecked ← checkStmt program returnType context inLoop first
         let secondChecked ← checkStmt program returnType context inLoop second
         pure ⟨.sequence firstChecked.down secondChecked.down⟩
  | .letLocal id type initializer body =>
      do let initializerChecked ← checkExpr program context initializer type
         let bodyChecked ← checkStmt program returnType (context.bind id type) inLoop body
         pure ⟨.letLocal initializerChecked.down bodyChecked.down⟩
  | .letUninitialized id type body =>
      do let bodyChecked ← checkStmt program returnType (context.bind id type) inLoop body
         pure ⟨.letUninitialized bodyChecked.down⟩
  | .ifThenElse condition thenBranch elseBranch =>
      do let conditionChecked ← checkExpr program context condition (.scalar .bool)
         let thenChecked ← checkStmt program returnType context inLoop thenBranch
         let elseChecked ← checkStmt program returnType context inLoop elseBranch
         pure ⟨.ifThenElse conditionChecked.down thenChecked.down elseChecked.down⟩
  | .whileLoop condition body =>
      do let conditionChecked ← checkExpr program context condition (.scalar .bool)
         let bodyChecked ← checkStmt program returnType context true body
         pure ⟨.whileLoop conditionChecked.down bodyChecked.down⟩
  | .forValues id iterable body =>
      do let iterableChecked ← checkExprAny program context iterable
         match iterableChecked with
         | ⟨.array elementType length, iterableProof⟩ =>
             let bodyChecked ← checkStmt program returnType
               (context.bind id elementType) true body
             pure ⟨.forArray iterableProof.down bodyChecked.down⟩
         | ⟨.slice elementType, iterableProof⟩ =>
             let bodyChecked ← checkStmt program returnType
               (context.bind id elementType) true body
             pure ⟨.forSlice iterableProof.down bodyChecked.down⟩
         | _ => none
  | .forRange id start stop inclusive body =>
      do let startChecked ← checkExpr program context start (.scalar (.signed .i32))
         let stopChecked ← checkOptionExpr program context (.scalar (.signed .i32)) stop
         let bodyChecked ← checkStmt program returnType
           (context.bind id (.scalar (.signed .i32))) true body
         pure ⟨.forRange startChecked.down stopChecked.down bodyChecked.down⟩
  | .returnValue none =>
      if unit : returnType = .unit then
        some ⟨by simpa [unit] using StmtHasType.returnUnit unit⟩
      else none
  | .returnValue (some expression) =>
      do let checked ← checkExpr program context expression returnType
         pure ⟨.returnValue checked.down⟩
  | .breakLoop =>
      if loop : inLoop = true then
        some ⟨by simpa [loop] using StmtHasType.breakLoop⟩
      else none
  | .continueLoop =>
      if loop : inLoop = true then
        some ⟨by simpa [loop] using StmtHasType.continueLoop⟩
      else none

def checkDefinitelyReturns : (statement : Stmt) → Option (ProofOf (DefinitelyReturns statement))
  | .returnValue (some _) => some ⟨.returnValue⟩
  | .sequence first second =>
      match checkDefinitelyReturns first with
      | some checked => some ⟨.sequenceLeft checked.down⟩
      | none =>
          match checkDefinitelyReturns second with
          | some checked => some ⟨.sequenceRight checked.down⟩
          | none => none
  | .letLocal _id _type _initializer body =>
      do let checked ← checkDefinitelyReturns body
         pure ⟨.letLocal checked.down⟩
  | .letUninitialized _id _type body =>
      do let checked ← checkDefinitelyReturns body
         pure ⟨.letUninitialized checked.down⟩
  | .ifThenElse _condition thenBranch elseBranch =>
      do let thenChecked ← checkDefinitelyReturns thenBranch
         let elseChecked ← checkDefinitelyReturns elseBranch
         pure ⟨.ifThenElse thenChecked.down elseChecked.down⟩
  | _ => none

def checkFunctionWellTyped (program : Program) (function : Function) :
    Option (ProofOf (FunctionWellTyped program function)) :=
  match body : function.body with
  | none =>
      match external : function.external with
      | none => none
      | some (.host service) =>
          if parameters : function.parameters.map Prod.snd = service.parameterTypes then
            if result : function.returnType = service.returnType then
              some ⟨by simp [FunctionWellTyped, body, external, parameters, result]⟩
            else none
          else none
      | some .panic =>
          if parameters : function.parameters = [] then
            if result : function.returnType = .unit then
              some ⟨by simp [FunctionWellTyped, body, external, parameters, result]⟩
            else none
          else none
      | some .unreachable =>
          if parameters : function.parameters = [] then
            if result : function.returnType = .unit then
              some ⟨by simp [FunctionWellTyped, body, external, parameters, result]⟩
            else none
          else none
      | some (.unavailable _) | some (.opaque _) =>
          some ⟨by simp [FunctionWellTyped, body, external]⟩
  | some statement =>
      if external : function.external = none then
        do let typed ← checkStmt program function.returnType
             (parameterContext function.parameters) false statement
           if unit : function.returnType = .unit then
             pure ⟨by
               simpa [FunctionWellTyped, body, external] using
                 (And.intro typed.down
                   (show function.returnType = .unit ∨ DefinitelyReturns statement from
                     Or.inl unit))⟩
           else
             let returns ← checkDefinitelyReturns statement
             pure ⟨by
               simpa [FunctionWellTyped, body, external] using
                 (And.intro typed.down
                   (show function.returnType = .unit ∨ DefinitelyReturns statement from
                     Or.inr returns.down))⟩
      else none

def checkConstantWellTyped (program : Program) (constant : Constant) :
    Option (ProofOf (ConstantWellTyped program constant)) :=
  do let checked ← checkValue program constant.value constant.type
     pure ⟨checked.down⟩

def checkConstantsWellTyped (program : Program) :
    (constants : List Constant) →
      Option (ProofOf (∀ constant, constant ∈ constants → ConstantWellTyped program constant))
  | [] => some ⟨by simp⟩
  | head :: tail => do
      let headChecked ← checkConstantWellTyped program head
      let tailChecked ← checkConstantsWellTyped program tail
      pure ⟨by
        intro constant member
        simp only [List.mem_cons] at member
        rcases member with rfl | member
        · exact headChecked.down
        · exact tailChecked.down constant member⟩

def checkFunctionsWellTyped (program : Program) :
    (functions : List Function) →
      Option (ProofOf (∀ function, function ∈ functions → FunctionWellTyped program function))
  | [] => some ⟨by simp⟩
  | head :: tail => do
      let headChecked ← checkFunctionWellTyped program head
      let tailChecked ← checkFunctionsWellTyped program tail
      pure ⟨by
        intro function member
        simp only [List.mem_cons] at member
        rcases member with rfl | member
        · exact headChecked.down
        · exact tailChecked.down function member⟩

def checkProgramWellTyped (program : Program) :
    Option (ProofOf (ProgramWellTyped program)) := do
  let constants ← checkConstantsWellTyped program program.constants
  let functions ← checkFunctionsWellTyped program program.functions
  pure ⟨⟨constants.down, functions.down⟩⟩

theorem checkProgramWellTyped_evidence {program : Program}
    {formed : ProofOf (ProgramWellTyped program)}
    (_accepted : checkProgramWellTyped program = some formed) :
    ProgramWellTyped program := formed.down

end Lanius.Typing.Check
