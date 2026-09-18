import Lanius.Extraction.SurfaceElaborationChecker

namespace Lanius.Extraction.CoreSynthesis

open Lanius
open Lanius.Core
open Lanius.SurfaceElaboration
open Lanius.Extraction.SurfaceElaborationChecker

/-! # Surface-to-Core synthesis

The historical artifact path asks an exporter to propose Core and then checks
that proposal.  Self-extraction should not need a second untrusted program
copy. This module constructs a candidate from Surface syntax, retaining the
existing proof-producing checker's lowering evidence and composing it directly
where available. Every returned node carries the same authoritative lowering
relation as an accepted external proposal; source authentication is a separate
requirement at the whole-program boundary.
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

private def checkInferred (context : Context) (surface : Surface.Expr)
    (expected : Static.GroundTy) (proposed : Option (Inferred context surface)) :
    Option (Checked context surface expected) :=
  let inferred : Option (Checked context surface expected) := do
    let candidate ← proposed
    match groundTypeEq? candidate.evidence.type expected with
    | some same => pure ⟨candidate.core, same.proof ▸ .exact candidate.evidence.lowered⟩
    | none =>
        match shape : surface, source : candidate.evidence.type, target : expected with
        | .path _, .scalar sourceType, .scalar targetType =>
            if different : sourceType ≠ targetType then do
              let conversion ← CoreTyping.scalarCast? sourceType targetType
              pure ⟨.cast targetType candidate.core, by
                cases target
                exact .scalarCast (source ▸ candidate.evidence.lowered)
                  (by simp [ContextualScalarLiteralApplies, shape]) different conversion.proof⟩
            else none
        | _, _, _ => none
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

mutual
  def infer (context : Context) :
      (surface : Surface.Expr) → Option (Inferred context surface)
    -- The emitted string is the source value itself. Retain that fact instead
    -- of expanding a long UTF-8 literal to compare it with its own copy.
    | .literal (.string value) =>
        some ⟨.value (.string value), {
          type := .scalar .string, coreType := .scalar .string, grounded := rfl
          lowered := .literal .string rfl }⟩
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
        match firstAccepted (acceptInferred context (.path path)) localCandidates with
        | some checked => some checked
        | none => do
            let global ← resolveGlobal? context .value path
            let candidates := context.constants.filterMap fun entry =>
              if entry.declaration == global.symbol.declaration then
                some (Core.Expr.constant entry.constant)
              else none
            firstAccepted (acceptInferred context (.path path)) candidates
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
        let candidates := context.fields.filterMap fun field =>
          if field.name == name && groundTypeBEq field.receiver baseCore.evidence.type then
            some (Core.Expr.field baseCore.core field.field)
          else none
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

  termination_by structural surface => surface

  def inferValues (context : Context) :
      List Surface.Expr → Option (List Core.Expr)
    | [] => some []
    | head :: tail => do
        let headCore ← infer context head
        let tailCore ← inferValues context tail
        pure (headCore.core :: tailCore)

  termination_by structural surface => surface

  def inferNamedValues (context : Context) :
      List (Surface.Name × Surface.Expr) → Option (List Core.Expr)
    | [] => some []
    | (_, value) :: tail => do
        let valueCore ← infer context value
        let tailCore ← inferNamedValues context tail
        pure (valueCore.core :: tailCore)

  termination_by structural surface => surface

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
    | .member base name => do
        let baseCore ← inferPlace context base
        let candidates := context.fields.filterMap fun field =>
          if field.name == name && groundTypeBEq field.receiver baseCore.evidence.type then
            some (Core.Place.field baseCore.core field.field)
          else none
        firstAccepted (acceptPlace context (.member base name)) candidates
    | .index base index => do
        let baseCore ← inferPlace context base
        let indexCore ← infer context index
        acceptPlace context (.index base index)
          (.index baseCore.core indexCore.core)
    | _ => none

  termination_by structural surface => surface

  def checkValues (context : Context) :
      List Surface.Expr → List Static.GroundTy → Option (List Core.Expr)
    | [], [] => some []
    | surfaceHead :: surfaceTail, typeHead :: typeTail => do
        let head ← checkInferred context surfaceHead typeHead (infer context surfaceHead)
        let tail ← checkValues context surfaceTail typeTail
        pure (head.core :: tail)
    | _, _ => none
  termination_by structural surface _ => surface
end

def check (context : Context) (surface : Surface.Expr)
    (expected : Static.GroundTy) : Option (Checked context surface expected) :=
  checkInferred context surface expected (infer context surface)

structure Stmts (context : Context) (next : VarId)
    (surface : List Surface.Stmt) where
  core : Core.Stmt
  finalNext : VarId
  evidence : StmtsLower context next surface core finalNext

mutual
  /-- Construct statements together with their lowering derivation. Child
  evidence is retained; no completed body is sent through the checker again. -/
  def stmts (returnType : Static.GroundTy) (context : Context) (next : VarId) :
      (surface : List Surface.Stmt) → Option (Stmts context next surface)
    | [] => some ⟨.skip, next, .nil⟩
    | head :: tail =>
        stmt returnType tail context next head
          (fun context next => stmts returnType context next tail)
  termination_by structural surface => surface

  private def stmt (returnType : Static.GroundTy) (surfaceTail : List Surface.Stmt)
      (context : Context) (next : VarId) :
      (surface : Surface.Stmt) →
      ((context : Context) → (next : VarId) → Option (Stmts context next surfaceTail)) →
      Option (Stmts context next (surface :: surfaceTail))
    | .expression expression, tail => do
        let head ← infer context expression
        let rest ← tail context next
        pure ⟨.sequence (.expression head.core) rest.core, rest.finalNext,
          .expression head.evidence.lowered rest.evidence⟩
    | .letLocal name none (some initializer), tail => do
        let fresh ← freshLocalId? context next
        let value ← infer context initializer
        match mapped : value.evidence.type.toCore context.monomorphization with
        | none => none
        | some type => do
            let rest ← tail (context.bindLocal name next value.evidence.type) (next + 1)
            pure ⟨.letLocal next type value.core rest.core, rest.finalNext,
              .letInferred fresh.proof value.evidence.lowered mapped rest.evidence⟩
    | .letLocal name (some annotation) (some initializer), tail => do
        let fresh ← freshLocalId? context next
        let grounded ← groundType? context annotation
        let value ← check context initializer grounded.type
        match mapped : grounded.type.toCore context.monomorphization with
        | none => none
        | some type => do
            let rest ← tail (context.bindLocal name next grounded.type) (next + 1)
            pure ⟨.letLocal next type value.core rest.core, rest.finalNext,
              .letAnnotated fresh.proof grounded.grounded value.evidence mapped rest.evidence⟩
    | .letLocal name (some annotation) none, tail => do
        let fresh ← freshLocalId? context next
        let grounded ← groundType? context annotation
        match mapped : grounded.type.toCore context.monomorphization with
        | none => none
        | some type => do
            let rest ← tail (context.bindLocal name next grounded.type) (next + 1)
            pure ⟨.letUninitialized next type rest.core, rest.finalNext,
              .letUninitialized fresh.proof grounded.grounded mapped rest.evidence⟩
    | .returnValue none, tail => do
        let _ ← groundTypeEq? returnType .unit
        let rest ← tail context next
        pure ⟨.sequence (.returnValue none) rest.core, rest.finalNext, .returnUnit rest.evidence⟩
    | .returnValue (some value), tail => do
        let valueCore ← check context value returnType
        let rest ← tail context next
        pure ⟨.sequence (.returnValue (some valueCore.core)) rest.core, rest.finalNext,
          .returnValue valueCore.evidence rest.evidence⟩
    | .ifThenElse condition thenBody elseBody, tail => do
        let conditionCore ← check context condition (.scalar .bool)
        let thenCore ← stmts returnType context next thenBody
        let elseCore ← stmts returnType context next elseBody
        let rest ← tail context (Nat.max thenCore.finalNext elseCore.finalNext)
        pure ⟨.sequence (.ifThenElse conditionCore.core thenCore.core elseCore.core) rest.core,
          rest.finalNext, .ifThenElse conditionCore.evidence thenCore.evidence elseCore.evidence rest.evidence⟩
    | .whileLoop condition body, tail => do
        let conditionCore ← check context condition (.scalar .bool)
        let bodyCore ← stmts returnType context next body
        let rest ← tail context bodyCore.finalNext
        pure ⟨.sequence (.whileLoop conditionCore.core bodyCore.core) rest.core, rest.finalNext,
          .whileLoop conditionCore.evidence bodyCore.evidence rest.evidence⟩
    | .breakLoop, tail => do
        let rest ← tail context next
        pure ⟨.sequence .breakLoop rest.core, rest.finalNext, .breakLoop rest.evidence⟩
    | .continueLoop, tail => do
        let rest ← tail context next
        pure ⟨.sequence .continueLoop rest.core, rest.finalNext, .continueLoop rest.evidence⟩
    | .block body, tail => do
        let bodyCore ← stmts returnType context next body
        let rest ← tail context bodyCore.finalNext
        pure ⟨.sequence bodyCore.core rest.core, rest.finalNext, .block bodyCore.evidence rest.evidence⟩
    | _, _ => none
  termination_by structural surface _ => surface
end

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
  match mapped : returned.type.toCore context.monomorphization with
  | none => none
  | some returnType => do
      let body ← stmts returned.type checkedParameters.bodyContext
        checkedParameters.finalNext surface.body
      let core : Core.Function := { id := functionId, parameters, returnType, body := some body.core }
      pure ⟨core, rfl, {
        parameterTypes := checkedParameters.groundTypes
        bodyContext := checkedParameters.bodyContext
        nextLocal := checkedParameters.finalNext
        parameters := checkedParameters.lowered
        returnType := returned.type
        returned := returned.grounded
        returnMapped := mapped
        coreBody := body.core
        bodyPresent := rfl
        finalLocal := body.finalNext
        bodyLowered := body.evidence }⟩

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
