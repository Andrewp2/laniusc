import Lanius.Extraction.SurfaceElaborationChecker

namespace Lanius.Extraction.CoreSynthesis

open Lanius
open Lanius.Core
open Lanius.SurfaceElaboration
open Lanius.Extraction.SurfaceElaborationChecker

/-! # Surface-to-Core synthesis

The historical artifact path asks an exporter to propose Core and then checks
that proposal.  Self-extraction should not need a second untrusted program
copy.  This module instead constructs a candidate from the authenticated
Surface value and immediately passes it through the existing proof-producing
checker.  Consequently every returned node carries the same authoritative
lowering relation as an accepted external proposal.
-/

structure Inferred (context : Context) (surface : Surface.Expr) where
  core : Core.Expr
  evidence : InferredExprLowering context surface core

structure Checked (context : Context) (surface : Surface.Expr)
    (expected : Static.GroundTy) where
  core : Core.Expr
  evidence : ExprChecks context surface expected core

structure Place (context : Context) (surface : Surface.Expr) where
  core : Core.Place
  evidence : InferredPlaceLowering context surface core

private def firstAccepted (check : α → Option β) : List α → Option β
  | [] => none
  | candidate :: tail =>
      match check candidate with
      | some result => some result
      | none => firstAccepted check tail

private def literalCandidate (target : Target) (literal : Surface.Literal)
    (type : Ty) : Option Core.Expr :=
  match literal, type with
  | .boolean value, .scalar .bool => some (.value (.boolean value))
  | .character value, .scalar .char =>
      some (.value (.character (UInt32.ofNat value.toNat)))
  | .string value, .scalar .string => some (.value (.string value))
  | .integer text, .scalar (.signed integerType) => do
      let magnitude ← Elaboration.parseUnsignedInteger text
      if Int.ofNat magnitude ≤ Typing.signedMax target integerType then
        some (.value (.signed integerType (Int.ofNat magnitude)))
      else none
  | .integer text, .scalar (.unsigned integerType) => do
      let magnitude ← Elaboration.parseUnsignedInteger text
      if magnitude ≤ Typing.unsignedMax target integerType then
        some (.value (.unsigned integerType magnitude))
      else none
  | .integer text, .scalar .rawPtr => do
      let magnitude ← Elaboration.parseUnsignedInteger text
      if magnitude = 0 then some (.value (.pointer 0)) else none
  | .float text, .scalar .f32 => do
      let value ← Elaboration.parseFloatLiteral text
      some (.value (.f32Bits value.toFloat32.toBits))
  | .float text, .scalar .f64 => do
      let value ← Elaboration.parseFloatLiteral text
      some (.value (.f64Bits value.toBits))
  | _, _ => none

private def acceptInferred (context : Context) (surface : Surface.Expr)
    (candidate : Core.Expr) : Option (Inferred context surface) := do
  let evidence ← inferExpr context surface candidate
  pure ⟨candidate, evidence⟩

private def acceptPlace (context : Context) (surface : Surface.Expr)
    (candidate : Core.Place) : Option (Place context surface) := do
  let evidence ← inferPlace context surface candidate
  pure ⟨candidate, evidence⟩

private def functionInstanceForPath? (context : Context)
    (path : Surface.Path) : Option Static.FunctionInstance := do
  let global ← resolveGlobal? context .value path
  context.functionInstances.find? fun row =>
    row.declaration == global.symbol.declaration

mutual
  def infer (context : Context) :
      (surface : Surface.Expr) → Option (Inferred context surface)
    | .literal literal => do
        let candidate ← literalCandidate context.target literal
          (Elaboration.literalDefaultType literal)
        acceptInferred context (.literal literal) candidate
    | .path path =>
        let localCandidates :=
          match singleNamePath? path with
          | some name =>
              match resolveLocal? context.locals name with
              | some selected => [.local selected.binding.id]
              | none => []
          | none => []
        let constantCandidates :=
          context.constants.map fun entry => Core.Expr.constant entry.constant
        firstAccepted (acceptInferred context (.path path))
          (localCandidates ++ constantCandidates)
    | .unary operation operand => do
        let operandCore ← infer context operand
        acceptInferred context (.unary operation operand)
          (.unary (lowerUnaryOp operation) operandCore.core)
    | .binary operation left right => do
        let leftCore ← infer context left
        let rightCore ← infer context right
        let candidates :=
          match operation, left, right, leftCore.evidence.type,
              rightCore.evidence.type with
          | .equal, _, .literal literal, .scalar .rawPtr, _
          | .notEqual, _, .literal literal, .scalar .rawPtr, _ =>
              match literalCandidate context.target literal (.scalar .rawPtr) with
              | some candidate => (leftCore.core, candidate)
              | none => (leftCore.core, rightCore.core)
          | .equal, .literal literal, _, _, .scalar .rawPtr
          | .notEqual, .literal literal, _, _, .scalar .rawPtr =>
              match literalCandidate context.target literal (.scalar .rawPtr) with
              | some candidate => (candidate, rightCore.core)
              | none => (leftCore.core, rightCore.core)
          | _, _, _, _, _ => (leftCore.core, rightCore.core)
        acceptInferred context (.binary operation left right)
          (.binary (lowerBinaryOp operation) candidates.1 candidates.2)
    | .member base name => do
        let baseCore ← infer context base
        let candidates := context.fields.map fun field =>
          Core.Expr.field baseCore.core field.field
        firstAccepted (acceptInferred context (.member base name)) candidates
    | .structValue path fields => do
        let coreFields ← inferNamedValues context fields
        let candidates := context.nominalInstances.map fun row =>
          Core.Expr.structValue row.coreType coreFields
        firstAccepted (acceptInferred context (.structValue path fields)) candidates
    | .index base index => do
        let baseCore ← infer context base
        let indexCore ← infer context index
        acceptInferred context (.index base index)
          (.index baseCore.core indexCore.core)
    | .assign operation destination value => do
        let destinationCore ← inferPlace context destination
        let valueCore ← infer context value
        acceptInferred context (.assign operation destination value)
          (.assign (lowerAssignOp operation) destinationCore.core valueCore.core)
    | .call (.path path) arguments =>
        match builtinIntrinsic? path with
        | some .i32ArrayDataPtr =>
            match inferValues context arguments with
            | some [arrayValue] => acceptInferred context
                (.call (.path path) arguments : Surface.Expr)
                (Core.Expr.i32ArrayDataPtr arrayValue)
            | _ => none
        | some .i32SliceFromRawParts =>
            match inferValues context arguments with
            | some [pointerValue, lengthValue] => acceptInferred context
                (.call (.path path) arguments : Surface.Expr)
                (Core.Expr.i32SliceFromRawParts pointerValue lengthValue)
            | _ => none
        | some .i32SliceDataPtr =>
            match inferValues context arguments with
            | some [sliceValue] => acceptInferred context
                (.call (.path path) arguments : Surface.Expr)
                (Core.Expr.i32SliceDataPtr sliceValue)
            | _ => none
        | some .stringDataPtr =>
            match inferValues context arguments with
            | some [stringValue] => acceptInferred context
                (.call (.path path) arguments : Surface.Expr)
                (Core.Expr.stringDataPtr stringValue)
            | _ => none
        | some _ => none
        | none => do
            let selected ← functionInstanceForPath? context path
            let coreArguments ← checkValues context arguments
              selected.parameterTypes
            acceptInferred context (Surface.Expr.call (.path path) arguments)
              (.call selected.function coreArguments)
    | .call _ _ => none
    | _ => none

  def inferValues (context : Context) :
      List Surface.Expr → Option (List Core.Expr)
    | [] => some []
    | head :: tail => do
        let headCore ← infer context head
        let tailCore ← inferValues context tail
        pure (headCore.core :: tailCore)

  def inferNamedValues (context : Context) :
      List (Surface.Name × Surface.Expr) → Option (List Core.Expr)
    | [] => some []
    | (_, value) :: tail => do
        let valueCore ← infer context value
        let tailCore ← inferNamedValues context tail
        pure (valueCore.core :: tailCore)

  def inferPlace (context : Context) :
      (surface : Surface.Expr) → Option (Place context surface)
    | .path path =>
        let candidates :=
          match singleNamePath? path with
          | some name =>
              match resolveLocal? context.locals name with
              | some selected => [.local selected.binding.id]
              | none => []
          | none => []
        firstAccepted (acceptPlace context (.path path)) candidates
    | .index base index => do
        let baseCore ← inferPlace context base
        let indexCore ← infer context index
        acceptPlace context (.index base index)
          (.index baseCore.core indexCore.core)
    | _ => none

  def checkOne (context : Context) (surface : Surface.Expr)
      (expected : Static.GroundTy) : Option (Checked context surface expected) :=
    let inferred : Option (Checked context surface expected) := do
      let candidate ← infer context surface
      match candidate.evidence.type, expected with
      | .scalar sourceType, .scalar targetType =>
          match CoreTyping.scalarCast? sourceType targetType with
          | some _ =>
              let core :=
                if sourceType = targetType then candidate.core
                else .cast targetType candidate.core
              let evidence ← checkExpr context surface expected core
              pure ⟨core, evidence.proof⟩
          | none =>
              let evidence ← checkExpr context surface expected candidate.core
              pure ⟨candidate.core, evidence.proof⟩
      | _, _ =>
          let evidence ← checkExpr context surface expected candidate.core
          pure ⟨candidate.core, evidence.proof⟩
    match inferred with
    | some result => some result
    | none =>
        match surface with
        | .literal literal => do
            let coreType ← expected.toCore context.monomorphization
            let candidate ← literalCandidate context.target literal coreType
            let evidence ← checkExpr context (.literal literal) expected candidate
            pure ⟨candidate, evidence.proof⟩
        | _ => none

  def checkValues (context : Context) :
      List Surface.Expr → List Static.GroundTy → Option (List Core.Expr)
    | [], [] => some []
    | surfaceHead :: surfaceTail, typeHead :: typeTail => do
        let head ← checkOne context surfaceHead typeHead
        let tail ← checkValues context surfaceTail typeTail
        pure (head.core :: tail)
    | _, _ => none
end

def check (context : Context) (surface : Surface.Expr)
    (expected : Static.GroundTy) : Option (Checked context surface expected) :=
  checkOne context surface expected

structure Stmts (context : Context) (next : VarId)
    (surface : List Surface.Stmt) where
  core : Core.Stmt
  finalNext : VarId
  evidence : StmtsLower context next surface core finalNext

private structure RawStmts where
  core : Core.Stmt
  finalNext : VarId

private def coreType? (context : Context)
    (ground : Static.GroundTy) : Option Core.Ty :=
  ground.toCore context.monomorphization

private def rawStmts (returnType : Static.GroundTy) :
    (context : Context) → (next : VarId) →
    List Surface.Stmt → Option RawStmts
  | _, next, [] => some ⟨.skip, next⟩
  | context, next, .expression expression :: tail => do
      let expressionCore ← infer context expression
      let tailCore ← rawStmts returnType context next tail
      pure ⟨.sequence (.expression expressionCore.core) tailCore.core,
        tailCore.finalNext⟩
  | context, next, .letLocal name none (some initializer) :: tail => do
      let initializerCore ← infer context initializer
      let type ← coreType? context initializerCore.evidence.type
      let tailCore ← rawStmts returnType
        (context.bindLocal name next initializerCore.evidence.type) (next + 1) tail
      pure ⟨.letLocal next type initializerCore.core tailCore.core,
        tailCore.finalNext⟩
  | context, next,
      .letLocal name (some annotation) (some initializer) :: tail => do
      let grounded ← groundType? context annotation
      let initializerCore ← check context initializer grounded.type
      let type ← coreType? context grounded.type
      let tailCore ← rawStmts returnType
        (context.bindLocal name next grounded.type) (next + 1) tail
      pure ⟨.letLocal next type initializerCore.core tailCore.core,
        tailCore.finalNext⟩
  | context, next, .letLocal name (some annotation) none :: tail => do
      let grounded ← groundType? context annotation
      let type ← coreType? context grounded.type
      let tailCore ← rawStmts returnType
        (context.bindLocal name next grounded.type) (next + 1) tail
      pure ⟨.letUninitialized next type tailCore.core, tailCore.finalNext⟩
  | context, next, .returnValue none :: tail => do
      let tailCore ← rawStmts returnType context next tail
      pure ⟨.sequence (.returnValue none) tailCore.core, tailCore.finalNext⟩
  | context, next, .returnValue (some value) :: tail => do
      let valueCore ← check context value returnType
      let tailCore ← rawStmts returnType context next tail
      pure ⟨.sequence (.returnValue (some valueCore.core)) tailCore.core,
        tailCore.finalNext⟩
  | context, next, .ifThenElse condition thenBody elseBody :: tail => do
      let conditionCore ← check context condition (.scalar .bool)
      let thenCore ← rawStmts returnType context next thenBody
      let elseCore ← rawStmts returnType context next elseBody
      let afterBranches := Nat.max thenCore.finalNext elseCore.finalNext
      let tailCore ← rawStmts returnType context afterBranches tail
      pure ⟨.sequence
        (.ifThenElse conditionCore.core thenCore.core elseCore.core)
        tailCore.core, tailCore.finalNext⟩
  | context, next, .whileLoop condition body :: tail => do
      let conditionCore ← check context condition (.scalar .bool)
      let bodyCore ← rawStmts returnType context next body
      let tailCore ← rawStmts returnType context bodyCore.finalNext tail
      pure ⟨.sequence (.whileLoop conditionCore.core bodyCore.core)
        tailCore.core, tailCore.finalNext⟩
  | context, next, .breakLoop :: tail => do
      let tailCore ← rawStmts returnType context next tail
      pure ⟨.sequence .breakLoop tailCore.core, tailCore.finalNext⟩
  | context, next, .continueLoop :: tail => do
      let tailCore ← rawStmts returnType context next tail
      pure ⟨.sequence .continueLoop tailCore.core, tailCore.finalNext⟩
  | context, next, .block body :: tail => do
      let bodyCore ← rawStmts returnType context next body
      let tailCore ← rawStmts returnType context bodyCore.finalNext tail
      pure ⟨.sequence bodyCore.core tailCore.core, tailCore.finalNext⟩
  | _, _, _ => none
termination_by _ _ surface => sizeOf surface

def stmts (returnType : Static.GroundTy) (context : Context)
    (next : VarId) (surface : List Surface.Stmt) :
    Option (Stmts context next surface) := do
  let candidate ← rawStmts returnType context next surface
  let accepted ← checkStmts returnType context next surface candidate.core
  pure ⟨candidate.core, accepted.finalNext, accepted.lowered⟩

structure Function (context : Context) (surface : Surface.Function)
    (functionId : FunctionId) where
  core : Core.Function
  sameId : core.id = functionId
  evidence : CheckedFunctionBody context surface core

private def parameterCandidates (context : Context) :
    (next : VarId) → List Surface.Parameter →
      Option (List (VarId × Core.Ty))
  | _, [] => some []
  | next, .named _ type :: tail => do
      let grounded ← groundType? context type
      let coreType ← grounded.type.toCore context.monomorphization
      let rest ← parameterCandidates context (next + 1) tail
      pure ((next, coreType) :: rest)
  | _, _ => none

def function (context : Context) (surface : Surface.Function)
    (functionId : FunctionId) : Option (Function context surface functionId) := do
  let parameters ← parameterCandidates context 0 surface.parameters
  let checkedParameters ← checkParameters context 0 surface.parameters parameters
  let returned ← groundReturn? context surface.name surface.returnType
  let returnType ← returned.type.toCore context.monomorphization
  let body ← stmts returned.type checkedParameters.bodyContext
    checkedParameters.finalNext surface.body
  let core : Core.Function := {
    id := functionId
    parameters
    returnType
    body := some body.core
  }
  let accepted ← checkFunctionBody context surface core
  pure ⟨core, rfl, accepted⟩

private def expressionLabel : Surface.Expr → String
  | .call (.path path) _ =>
      match pathLeafName? path with
      | some name => "call:" ++ name
      | none => "call:<path>"
  | .call _ _ => "call:<expression>"
  | .literal _ => "literal"
  | .path _ => "path"
  | .array _ => "array"
  | .structValue _ _ => "struct-value"
  | .unary _ _ => "unary"
  | .binary _ _ _ => "binary"
  | .assign _ _ _ => "assignment"
  | .index _ _ => "index"
  | .member _ _ => "member"
  | .selfValue => "self"
  | .matchValue _ _ => "match"

private def diagnoseStmts (returnType : Static.GroundTy) :
    (context : Context) → (next index : Nat) → List Surface.Stmt → Option String
  | _, _, _, [] => none
  | context, next, index, .expression expression :: tail =>
      match infer context expression with
      | none => some (toString index ++ ":expression:" ++ expressionLabel expression)
      | some _ => diagnoseStmts returnType context next (index + 1) tail
  | context, next, index,
      .letLocal name none (some initializer) :: tail =>
      match infer context initializer with
      | none => some (toString index ++ ":let:" ++ name ++ ":" ++
          expressionLabel initializer)
      | some value => diagnoseStmts returnType
          (context.bindLocal name next value.evidence.type) (next + 1)
          (index + 1) tail
  | context, next, index,
      .letLocal name (some annotation) initializer :: tail =>
      match groundType? context annotation with
      | none => some (toString index ++ ":let:" ++ name ++ ":type")
      | some grounded =>
          match initializer with
          | some value =>
              match check context value grounded.type with
              | none => some (toString index ++ ":let:" ++ name ++ ":" ++
                  expressionLabel value)
              | some _ => diagnoseStmts returnType
                  (context.bindLocal name next grounded.type) (next + 1)
                  (index + 1) tail
          | none => diagnoseStmts returnType
              (context.bindLocal name next grounded.type) (next + 1)
              (index + 1) tail
  | context, next, index, .returnValue value :: tail =>
      match value with
      | none => diagnoseStmts returnType context next (index + 1) tail
      | some expression =>
          match check context expression returnType with
          | none => some (toString index ++ ":return:" ++ expressionLabel expression)
          | some _ => diagnoseStmts returnType context next (index + 1) tail
  | context, next, index,
      .ifThenElse condition thenBody elseBody :: tail =>
      match check context condition (.scalar .bool) with
      | none => some (toString index ++ ":if-condition:" ++ expressionLabel condition)
      | some _ =>
          match diagnoseStmts returnType context next 0 thenBody with
          | some reason => some (toString index ++ ":if-then:" ++ reason)
          | none =>
              match diagnoseStmts returnType context next 0 elseBody with
              | some reason => some (toString index ++ ":if-else:" ++ reason)
              | none => diagnoseStmts returnType context next (index + 1) tail
  | context, next, index, .whileLoop condition body :: tail =>
      match check context condition (.scalar .bool) with
      | none => some (toString index ++ ":while-condition:" ++
          expressionLabel condition)
      | some _ =>
          match diagnoseStmts returnType context next 0 body with
          | some reason => some (toString index ++ ":while-body:" ++ reason)
          | none => diagnoseStmts returnType context next (index + 1) tail
  | context, next, index, .block body :: tail =>
      match diagnoseStmts returnType context next 0 body with
      | some reason => some (toString index ++ ":block:" ++ reason)
      | none => diagnoseStmts returnType context next (index + 1) tail
  | context, next, index, .breakLoop :: tail =>
      diagnoseStmts returnType context next (index + 1) tail
  | context, next, index, .continueLoop :: tail =>
      diagnoseStmts returnType context next (index + 1) tail
  | _, _, index, .forLoop _ _ _ :: _ => some (toString index ++ ":for-loop")
  | _, _, index, .letLocal name none none :: _ =>
      some (toString index ++ ":let:" ++ name ++ ":missing-type-and-value")

def diagnoseFunction (context : Context) (surface : Surface.Function) : String :=
  match parameterCandidates context 0 surface.parameters with
  | none => "parameters"
  | some parameters =>
      match checkParameters context 0 surface.parameters parameters with
      | none => "parameter-check"
      | some checkedParameters =>
          match groundReturn? context surface.name surface.returnType with
          | none => "return-type"
          | some returned =>
              match diagnoseStmts returned.type checkedParameters.bodyContext
                  checkedParameters.finalNext 0 surface.body with
              | none => "final-function-check"
              | some reason => reason

end Lanius.Extraction.CoreSynthesis
