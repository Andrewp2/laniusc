import Lanius.Compiler.ProgramLowering
import Lanius.Compiler.ConstantCheck
import Lanius.Compiler.DirectCallCheck
import Lanius.Typing.Check

namespace Lanius.Compiler.BodyCheck

open Lanius
open Lanius.Compiler.ProgramLowering

/-!
This is the executable reference checker for the first body-agreement
fragment.  The candidate is still an ordinary `Core.Function`; this checker
does not introduce a second IR.  It reconstructs the Core statement shape
from the reconstructed Surface body, then stores the existing
`StmtsLower`/`ExprLowers` relation and an independent Core typing proof in
`FunctionBodyLowering`.

The deliberately closed fragment is scalar literals (i32 and bool), simple
local paths, indexed array/slice places, scalar unary/binary expressions,
assignments, sequences, nested blocks, boolean-guarded `if` statements,
boolean-guarded `while` statements, and scalar-valued returns.  A sequence may
also have expression statements, since those are emitted by the same lowering
rule.
Direct calls are accepted for the monomorphic function-instance fragment;
other calls are unsupported and rejected rather than represented by an
unrelated relation. Scalar lets use the existing type-grounding checker and
`StmtsLower` constructors for inferred, annotated, and uninitialized forms.
-/

inductive Failure where
  | noBody
  | unsupported
  | illTyped
  | externalBody
deriving DecidableEq, Repr

def scalarType (type : Core.Ty) : Bool :=
  match type with
  | .scalar _ => true
  | _ => false

def resolveLocal? :
    List SurfaceElaboration.LocalBinding → Surface.Name →
      Option SurfaceElaboration.LocalBinding
  | [], _ => none
  | binding :: outer, name =>
      if _same : binding.name = name then
        some binding
      else
        resolveLocal? outer name

theorem resolveLocal_resolves
    (found : resolveLocal? locals name = some binding) :
    SurfaceElaboration.ResolvesLocal locals name binding := by
  induction locals with
  | nil => simp [resolveLocal?] at found
  | cons head tail induction =>
      simp only [resolveLocal?] at found
      split at found
      · have same : head.name = name := by assumption
        have bindingEq : binding = head := (Option.some.inj found).symm
        subst binding
        exact same ▸ .head
      · exact .tail (by assumption) (induction found)

structure LoweredExpr
    (context : SurfaceElaboration.Context)
    (surface : Surface.Expr) (candidate : Core.Expr) where
  groundType : Static.GroundTy
  lowers : SurfaceElaboration.ExprLowers context surface groundType candidate

structure LoweredPlace
    (context : SurfaceElaboration.Context)
    (surface : Surface.Expr) (candidate : Core.Place) where
  groundType : Static.GroundTy
  lowers : SurfaceElaboration.PlaceLowers context surface groundType candidate

structure LoweredExprs
    (context : SurfaceElaboration.Context)
    (surface : List Surface.Expr) (candidate : List Core.Expr) where
  groundTypes : List Static.GroundTy
  lowers : SurfaceElaboration.ExprsLower context surface groundTypes candidate

/- The candidate Core expression is an input to the checker.  Pattern
   matching it here makes agreement a validation step, rather than generating
   a Core term and assuming that it is the candidate. -/
mutual
def checkPlace (context : SurfaceElaboration.Context) :
    (surface : Surface.Expr) → (candidate : Core.Place) →
      Option (LoweredPlace context surface candidate)
  | .path path, .local id =>
      match single : SurfaceElaboration.singleNamePath? path with
      | none => none
      | some name =>
          match found : resolveLocal? context.locals name with
          | none => none
          | some selected =>
              if equal : selected.id = id then
                equal ▸ some {
                  groundType := selected.type
                  lowers := .local name single (resolveLocal_resolves found) }
              else none
  | .index surfaceBase surfaceIndex, .index candidateBase candidateIndex =>
      match checkPlace context surfaceBase candidateBase with
      | none => none
      | some base =>
          match checkExpr context surfaceIndex candidateIndex with
          | none => none
          | some index =>
              match indexCore : index.groundType.toCore context.monomorphization with
              | none => none
              | some indexType =>
                  match Typing.Check.checkInteger indexType with
                  | none => none
                  | some integerProof =>
                      match base with
                      | ⟨baseType, baseLowers⟩ =>
                          match baseType with
                          | .array elementType _ =>
                              some {
                                groundType := elementType
                                lowers := .indexArray baseLowers index.lowers indexCore
                                  integerProof.down }
                          | .slice elementType =>
                              some {
                                groundType := elementType
                                lowers := .indexSlice baseLowers index.lowers indexCore
                                  integerProof.down }
                          | _ => none
  | _, _ => none

def checkExpr (context : SurfaceElaboration.Context) :
    (surface : Surface.Expr) → (candidate : Core.Expr) →
      Option (LoweredExpr context surface candidate)
  | .literal (.boolean value), .value (.boolean actual) =>
      if equal : actual = value then
        equal ▸ some {
          groundType := .scalar .bool
          lowers := .literal .boolean rfl }
      else none
  | .literal (.integer text), .value (.signed .i32 actual) =>
      match parsed : Elaboration.parseUnsignedInteger text with
      | none => none
      | some value =>
          if upper : Int.ofNat value ≤ Typing.signedMax context.target .i32 then
            if equal : actual = Int.ofNat value then
              equal ▸ some {
                groundType := .scalar (.signed .i32)
                lowers := .literal (.signedInteger parsed upper) rfl }
            else none
          else none
  | .path path, .local id =>
      match single : SurfaceElaboration.singleNamePath? path with
      | none => none
      | some name =>
          match found : resolveLocal? context.locals name with
          | none => none
          | some selected =>
              if equal : selected.id = id then
                equal ▸ some {
                  groundType := selected.type
                  lowers := .local name single (resolveLocal_resolves found) }
              else none
  | .unary surfaceOp surfaceOperand, .unary candidateOp candidateOperand =>
      if equal : SurfaceElaboration.lowerUnaryOp surfaceOp = candidateOp then
        match checkExpr context surfaceOperand candidateOperand with
        | none => none
        | some ⟨.scalar inputScalar, operandLowers⟩ =>
            match Typing.Check.checkUnaryAny (SurfaceElaboration.lowerUnaryOp surfaceOp)
                (.scalar inputScalar) with
            | none => none
            | some ⟨outputType, typed⟩ =>
                match outputType with
                | .scalar outputScalar =>
                    match equal with
                    | rfl => some {
                        groundType := .scalar outputScalar
                        lowers := .unary operandLowers rfl rfl typed.down }
                | _ => none
        | some ⟨_, _⟩ => none
      else none
  | .binary surfaceOp surfaceLeft surfaceRight,
      .binary candidateOp candidateLeft candidateRight =>
      if equal : SurfaceElaboration.lowerBinaryOp surfaceOp = candidateOp then
        match checkExpr context surfaceLeft candidateLeft with
        | none => none
        | some left =>
            match checkExpr context surfaceRight candidateRight with
            | none => none
            | some right =>
                match left, right with
                | ⟨.scalar leftScalar, leftLowers⟩,
                    ⟨.scalar rightScalar, rightLowers⟩ =>
                    match Typing.Check.checkBinaryAny (SurfaceElaboration.lowerBinaryOp surfaceOp)
                        (.scalar leftScalar) (.scalar rightScalar) with
                    | none => none
                    | some ⟨outputType, typed⟩ =>
                        match outputType with
                        | .scalar outputScalar =>
                            match equal with
                            | rfl => some {
                                groundType := .scalar outputScalar
                                lowers := .binary leftLowers rightLowers rfl rfl rfl
                                  typed.down }
                        | _ => none
                | _, _ => none
      else none
  | .assign surfaceOp surfacePlace surfaceValue,
      .assign candidateOp candidatePlace candidateValue =>
      if operationEqual : SurfaceElaboration.lowerAssignOp surfaceOp = candidateOp then
        match operationEqual with
        | rfl =>
            match checkPlace context surfacePlace candidatePlace with
            | none => none
            | some place =>
                match checkExpr context surfaceValue candidateValue with
                | none => none
                | some ⟨valueType, valueLowers⟩ =>
                    if typeEqual : valueType = place.groundType then
                      have valueChecked : SurfaceElaboration.ExprChecks context
                          surfaceValue place.groundType candidateValue := by
                        simpa [typeEqual] using
                          (SurfaceElaboration.ExprChecks.exact valueLowers)
                      match coreType : place.groundType.toCore context.monomorphization with
                      | none => none
                      | some type =>
                          match checked : Typing.Check.checkAssign
                              (SurfaceElaboration.lowerAssignOp surfaceOp) type with
                          | none => none
                          | some assignmentProof => some {
                              groundType := .unit
                              lowers := .assign place.lowers valueChecked
                                coreType assignmentProof.down }
                    else none
      else none
  | .call (.path path) surfaceArguments,
      .call function coreArguments =>
      match arguments : checkExprs context surfaceArguments coreArguments with
      | none => none
      | some lowered =>
          match selected : DirectCallCheck.check lowered.lowers with
          | none => none
          | some evidence =>
              if functionEqual : function = evidence.candidate.resolved.function then
                functionEqual ▸ some {
                  groundType := evidence.candidate.resolved.returnType
                  lowers := .directCall evidence.arguments evidence.resolved
                    evidence.notIntrinsic rfl }
              else none
  | _, _ => none

def checkExprs (context : SurfaceElaboration.Context) :
    (surface : List Surface.Expr) → (candidate : List Core.Expr) →
      Option (LoweredExprs context surface candidate)
  | [], [] => some { groundTypes := [], lowers := .nil }
  | surfaceHead :: surfaceTail, candidateHead :: candidateTail =>
      match checkExpr context surfaceHead candidateHead with
      | none => none
      | some head =>
          match checkExprs context surfaceTail candidateTail with
          | none => none
          | some tail =>
              some ⟨head.groundType :: tail.groundTypes, .cons head.lowers tail.lowers⟩
  | _, _ => none
end

structure LoweredStmts
    (context : SurfaceElaboration.Context) (next : VarId)
    (surface : List Surface.Stmt) (candidate : Core.Stmt) where
  finalNext : VarId
  lowers : SurfaceElaboration.StmtsLower context next surface candidate finalNext

def checkFreshLocal (locals : List SurfaceElaboration.LocalBinding) (next : VarId) :
    Option (SurfaceElaboration.ProofCache
      (∀ binding, binding ∈ locals → binding.id ≠ next)) :=
  match locals with
  | [] => some ⟨by simp⟩
  | binding :: rest =>
      if equal : binding.id = next then
        none
      else
        match checkFreshLocal rest next with
        | none => none
        | some tail =>
            some ⟨by
              intro selected member
              simp only [List.mem_cons] at member
              rcases member with rfl | member
              · exact equal
              · exact tail.proof selected member⟩

def checkStmts (context : SurfaceElaboration.Context) (next : VarId) :
    (surface : List Surface.Stmt) → (candidate : Core.Stmt) →
      Option (LoweredStmts context next surface candidate)
  | [], .skip =>
      some { finalNext := next, lowers := .nil }
  | .expression surfaceExpression :: surfaceTail,
      .sequence (.expression candidateExpression) candidateTail =>
      match checkExpr context surfaceExpression candidateExpression with
      | none => none
      | some head =>
          match checkStmts context next surfaceTail candidateTail with
          | none => none
          | some tail =>
              some { finalNext := tail.finalNext, lowers := .expression head.lowers tail.lowers }
  | .letLocal name none (some surfaceInitializer) :: surfaceTail,
      .letLocal id (.scalar scalar) candidateInitializer candidateTail =>
      if idEqual : id = next then
        match checkFreshLocal context.locals next with
        | none => none
        | some fresh =>
            match checkExpr context surfaceInitializer candidateInitializer with
            | none => none
            | some ⟨.scalar initializerScalar, initializerLowers⟩ =>
                if initializerType : initializerScalar = scalar then
                  let groundType : Static.GroundTy := .scalar scalar
                  match checkStmts (context.bindLocal name next groundType) (next + 1)
                      surfaceTail candidateTail with
                  | none => none
                  | some tail =>
                      have initializerInferred :
                          SurfaceElaboration.ExprLowers context surfaceInitializer
                            groundType candidateInitializer := by
                        simpa [groundType, initializerType] using initializerLowers
                      idEqual ▸ some {
                        finalNext := tail.finalNext
                        lowers := .letInferred (type := groundType)
                          (loweredType := .scalar scalar) (idEqual ▸ fresh.proof)
                          initializerInferred rfl (idEqual ▸ tail.lowers) }
                else none
            | some ⟨_, _⟩ => none
      else none
  | .letLocal name (some surfaceType) (some surfaceInitializer) :: surfaceTail,
      .letLocal id (.scalar scalar) candidateInitializer candidateTail =>
      if idEqual : id = next then
        let groundType : Static.GroundTy := .scalar scalar
        match ConstantCheck.checkTypeGrounds context surfaceType groundType with
        | none => none
        | some annotation =>
            match checkFreshLocal context.locals next with
            | none => none
            | some fresh =>
                match checkExpr context surfaceInitializer candidateInitializer with
                | none => none
                | some ⟨.scalar initializerScalar, initializerLowers⟩ =>
                    if initializerType : initializerScalar = scalar then
                      match checkStmts (context.bindLocal name next groundType) (next + 1)
                          surfaceTail candidateTail with
                      | none => none
                      | some tail =>
                          have initializerChecked :
                              SurfaceElaboration.ExprChecks context surfaceInitializer
                                groundType candidateInitializer := by
                            simpa [initializerType] using
                              (SurfaceElaboration.ExprChecks.exact initializerLowers)
                          idEqual ▸ some {
                            finalNext := tail.finalNext
                            lowers := .letAnnotated (idEqual ▸ fresh.proof) annotation.down
                              initializerChecked rfl (idEqual ▸ tail.lowers) }
                    else none
                | some ⟨_, _⟩ => none
      else none
  | .letLocal name (some surfaceType) none :: surfaceTail,
      .letUninitialized id (.scalar scalar) candidateTail =>
      if idEqual : id = next then
        let groundType : Static.GroundTy := .scalar scalar
        match ConstantCheck.checkTypeGrounds context surfaceType groundType with
        | none => none
        | some annotation =>
            match checkFreshLocal context.locals next with
            | none => none
            | some fresh =>
                match checkStmts (context.bindLocal name next groundType) (next + 1)
                    surfaceTail candidateTail with
                | none => none
                | some tail =>
                    idEqual ▸ some {
                      finalNext := tail.finalNext
                      lowers := .letUninitialized (type := groundType)
                        (loweredType := .scalar scalar) (idEqual ▸ fresh.proof)
                        annotation.down rfl (idEqual ▸ tail.lowers) }
      else none
  | .returnValue (some surfaceValue) :: surfaceTail,
      .sequence (.returnValue (some candidateValue)) candidateTail =>
      match checkExpr context surfaceValue candidateValue with
      | none => none
      | some value =>
          match checkStmts context next surfaceTail candidateTail with
          | none => none
          | some tail =>
              some { finalNext := tail.finalNext, lowers := .returnValue (.exact value.lowers) tail.lowers }
  | .block surfaceBody :: surfaceTail,
      .sequence candidateBody candidateTail =>
      match checkStmts context next surfaceBody candidateBody with
      | none => none
      | some body =>
          match checkStmts context body.finalNext surfaceTail candidateTail with
          | none => none
          | some tail =>
              some { finalNext := tail.finalNext, lowers := .block body.lowers tail.lowers }
  | .ifThenElse surfaceCondition surfaceThen surfaceElse :: surfaceTail,
      .sequence (.ifThenElse candidateCondition candidateThen candidateElse) candidateTail =>
      match checkExpr context surfaceCondition candidateCondition with
      | none => none
      | some condition =>
          match condition with
          | ⟨.scalar .bool, conditionLowers⟩ =>
              match checkStmts context next surfaceThen candidateThen with
              | none => none
              | some thenResult =>
                  match checkStmts context next surfaceElse candidateElse with
                  | none => none
                  | some elseResult =>
                      match checkStmts context (Nat.max thenResult.finalNext elseResult.finalNext)
                          surfaceTail candidateTail with
                      | none => none
                      | some tail =>
                          some {
                            finalNext := tail.finalNext
                            lowers := .ifThenElse (.exact conditionLowers)
                              thenResult.lowers elseResult.lowers tail.lowers }
          | ⟨_, _⟩ => none
  | .whileLoop surfaceCondition surfaceBody :: surfaceTail,
      .sequence (.whileLoop candidateCondition candidateBody) candidateTail =>
      match checkExpr context surfaceCondition candidateCondition with
      | none => none
      | some condition =>
          match condition with
          | ⟨.scalar .bool, conditionLowers⟩ =>
              match checkStmts context next surfaceBody candidateBody with
              | none => none
              | some body =>
                  match checkStmts context body.finalNext surfaceTail candidateTail with
                  | none => none
                  | some tail =>
                      some {
                        finalNext := tail.finalNext
                        lowers := .whileLoop (.exact conditionLowers)
                          body.lowers tail.lowers }
          | ⟨_, _⟩ => none
  | _, _ => none

/- All fields below this point are already obligations of the surrounding
   declaration/catalog checker.  Keeping them as a seed lets this checker
   validate only body agreement while returning the project's existing
   `FunctionBodyLowering` witness. -/
structure FunctionBodyCandidate
    (pack : Declarations.SourcePack) (catalog : Declarations.Catalog)
    (program : Core.Program) (environment : Names.Environment)
    (baseContext : SurfaceElaboration.Context)
    (rows : List (DeclarationLowering pack catalog program)) where
  row : DeclarationLowering pack catalog program
  rowMember : row ∈ rows
  address : Declarations.ItemAddress
  declaration : Surface.Function
  sourceFound : pack.item? address = some (.function declaration)
  source : row.occurrence = .item address
  core : Core.Function
  coreMap : row.core = .function core
  context : SurfaceElaboration.Context
  next : VarId
  parameters : NamedParametersLower context declaration.parameters
    context.locals core.parameters
  returnType : ReturnTypeLower context declaration.returnType core.returnType
  contextMatches : ContextMatches context baseContext environment row.header.moduleId
  parameterContext : context.coreLocals = Typing.parameterContext core.parameters
  target : program.target = context.target

def check
    (candidate : FunctionBodyCandidate pack catalog program environment
      baseContext rows) :
    Except Failure
      (FunctionBodyLowering pack catalog program environment baseContext rows) :=
  match external : candidate.core.external with
  | some _ => .error .externalBody
  | none =>
      match body : candidate.core.body with
      | none => .error .noBody
      | some coreBody =>
          if _scalar : scalarType candidate.core.returnType then
            match _check : checkStmts candidate.context candidate.next
                candidate.declaration.body coreBody with
            | none => .error .unsupported
            | some result =>
                match _typing : Typing.Check.checkStmt program candidate.core.returnType
                    candidate.context.coreLocals false coreBody with
                | none => .error .illTyped
                | some typed =>
                    .ok {
                      row := candidate.row
                      rowMember := candidate.rowMember
                      address := candidate.address
                      declaration := candidate.declaration
                      sourceFound := candidate.sourceFound
                      source := candidate.source
                      core := candidate.core
                      coreMap := candidate.coreMap
                      context := candidate.context
                      next := candidate.next
                      parameters := candidate.parameters
                      returnType := candidate.returnType
                      lowering := {
                        core := coreBody
                        finalNext := result.finalNext
                        lowers := result.lowers
                        target := candidate.target
                        typed := typed.down }
                      contextMatches := candidate.contextMatches
                      parameterContext := candidate.parameterContext
                      coreShape := ⟨body, external⟩ }
          else .error .unsupported

end Lanius.Compiler.BodyCheck
