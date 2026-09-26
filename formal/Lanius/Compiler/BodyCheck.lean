import Lanius.Compiler.ProgramLowering
import Lanius.Compiler.ConstantCheck
import Lanius.Compiler.DirectCallCheck
import Lanius.Compiler.VariantConstructorCheck
import Lanius.Compiler.NameResolutionCheck
import Lanius.Compiler.TypeLoweringCheck
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

The deliberately closed fragment is scalar literals (i32, bool, and string), simple
local paths, indexed array/slice places, scalar unary expressions and
well-typed binary expressions (including enum equality),
assignments, sequences, nested blocks, boolean-guarded `if` statements,
boolean-guarded `while` statements, and well-typed returns. Payload-bearing
non-generic enum constructors are checked against their source arguments. A sequence may
also have expression statements, since those are emitted by the same lowering
rule.
Direct calls are accepted for the monomorphic function-instance fragment;
other calls are unsupported and rejected rather than represented by an
unrelated relation. Scalar lets use the existing type-grounding checker and
`StmtsLower` constructors for inferred, annotated, and uninitialized forms.
Match expressions check wildcard, boolean, i32 literal, and non-generic enum
patterns, including nested payload binders, against the same source-to-Core relation.
-/

inductive Failure where
  | noBody
  | unsupported
  | illTyped
  | externalBody
deriving DecidableEq, Repr

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

private theorem noLocalNamed_of_all
    (locals : List SurfaceElaboration.LocalBinding) (name : Surface.Name)
    (clear : locals.all (fun binding => decide (binding.name ≠ name)) = true) :
    SurfaceElaboration.NoLocalNamed locals name := by
  intro binding member
  exact of_decide_eq_true (List.all_eq_true.mp clear binding member)

private def checkNotShadowed (context : SurfaceElaboration.Context)
    (path : Surface.Path) :
    Option { _witness : Unit // SurfaceElaboration.GlobalPathNotShadowed context path } :=
  match named : SurfaceElaboration.unqualifiedPathName? path with
  | none => some ⟨(), by simp [SurfaceElaboration.GlobalPathNotShadowed, named]⟩
  | some name =>
      if clear : context.locals.all (fun binding => decide (binding.name ≠ name)) then
        some ⟨(), by
          simpa [SurfaceElaboration.GlobalPathNotShadowed, named] using
            noLocalNamed_of_all context.locals name clear⟩
      else none

private def checkNoGlobalValue (context : SurfaceElaboration.Context)
    (path : Surface.Path) :
    Option { _witness : Unit // SurfaceElaboration.NoGlobalValueResolution context path } :=
  match formed : Names.Reference.fromSurfacePath? .value path with
  | none => some ⟨(), by
      intro symbol resolved
      cases resolved with
      | intro reference referenceFound _ =>
          rw [formed] at referenceFound
          contradiction⟩
  | some reference =>
      match candidatesFound : NameResolutionCheck.candidates context.names
          context.currentModule reference with
      | [] => some ⟨(), by
          intro symbol resolved
          cases resolved with
          | intro candidateRef candidateFound candidateResolved =>
              have same : candidateRef = reference :=
                Option.some.inj (candidateFound.symm.trans formed)
              subst candidateRef
              have member := NameResolutionCheck.candidates_mem_iff.mpr
                candidateResolved.1
              rw [candidatesFound] at member
              contradiction⟩
      | _ :: _ => none

private def checkPatternBindingsFresh (context : SurfaceElaboration.Context)
    (bindings : List SurfaceElaboration.LocalBinding) :
    Option { _witness : Unit // SurfaceElaboration.PatternBindingsFresh context bindings } :=
  if fresh : bindings.all (fun binding =>
      context.locals.all (fun existing => decide (existing.id ≠ binding.id))) then
    if distinct : bindings.Pairwise (fun left right =>
        left.id ≠ right.id ∧ left.name ≠ right.name) then
      some ⟨(), by
        constructor
        · intro binding bindingMember existing existingMember
          exact of_decide_eq_true
            (List.all_eq_true.mp
              (List.all_eq_true.mp fresh binding bindingMember)
                existing existingMember)
        · exact distinct⟩
    else none
  else none

private def variantKey (entry : SurfaceElaboration.VariantEntry)
    (declaration : Nat) (typeId : TypeId) : Bool :=
  decide (entry.declaration = declaration) &&
    FunctionInstanceCheck.groundTypeEq entry.receiver (.nominal typeId [] [])

private theorem variantKey_sound
    {entry : SurfaceElaboration.VariantEntry}
    (accepted : variantKey entry declaration typeId = true) :
    entry.declaration = declaration ∧ entry.receiver = .nominal typeId [] [] := by
  simp only [variantKey, Bool.and_eq_true] at accepted
  exact ⟨of_decide_eq_true accepted.1,
    FunctionInstanceCheck.groundTypeEq_eq_true accepted.2⟩

private theorem variantKey_complete
    {entry : SurfaceElaboration.VariantEntry}
    (declarationMatches : entry.declaration = declaration)
    (receiverMatches : entry.receiver = .nominal typeId [] []) :
    variantKey entry declaration typeId = true := by
  simp [variantKey, declarationMatches, receiverMatches,
    FunctionInstanceCheck.groundTypeEq_refl]

private def variantCompatible (entry : SurfaceElaboration.VariantEntry)
    (declaration : Nat) (typeId : TypeId) (variantId : VariantId)
    (payload : List Static.GroundTy) : Bool :=
  !variantKey entry declaration typeId ||
    (decide (entry.coreType = typeId) &&
      decide (entry.variant = variantId) && decide (entry.payload = payload))

private structure SelectedVariant
    (context : SurfaceElaboration.Context) (path : Surface.Path)
    (typeId : TypeId) (variantId : VariantId) where
  entry : SurfaceElaboration.VariantEntry
  selected : SurfaceElaboration.SelectsVariant context
    (.nominal typeId [] []) path entry
  coreType : entry.coreType = typeId
  variant : entry.variant = variantId

private def checkSelectedVariant (context : SurfaceElaboration.Context)
    (path : Surface.Path) (typeId : TypeId) (variantId : VariantId) :
    Option (SelectedVariant context path typeId variantId) :=
  if shadowed : DirectCallCheck.pathNotShadowed? context path = true then
    match NameResolutionCheck.checkGlobal context .value path with
    | none => none
    | some resolved =>
        match found : context.variants.find?
            (fun entry => variantKey entry resolved.symbol.declaration typeId) with
        | none => none
        | some entry =>
            if coreType : entry.coreType = typeId then
              if variant : entry.variant = variantId then
                if coherent : context.variants.all (fun candidate =>
                    variantCompatible candidate resolved.symbol.declaration
                      typeId variantId entry.payload) then
                  have member : entry ∈ context.variants :=
                    List.mem_of_find?_eq_some found
                  have key := variantKey_sound
                    (List.find?_eq_some_iff_getElem.mp found).1
                  some {
                    entry
                    selected := by
                      refine ⟨DirectCallCheck.pathNotShadowed_sound shadowed,
                        resolved.symbol, resolved.resolved, member,
                        key.1, key.2, ?_⟩
                      intro candidate candidateMember declarationMatch receiverMatch
                      have sameKey := variantKey_complete declarationMatch receiverMatch
                      have accepted := List.all_eq_true.mp coherent
                        candidate candidateMember
                      have fields : (candidate.coreType = typeId ∧
                          candidate.variant = variantId) ∧
                          candidate.payload = entry.payload := by
                        simpa [variantCompatible, sameKey] using accepted
                      exact ⟨fields.1.1.trans coreType.symm,
                        fields.1.2.trans variant.symm, fields.2⟩
                    coreType
                    variant }
                else none
              else none
            else none
  else none

private structure NullaryVariant
    (context : SurfaceElaboration.Context) (path : Surface.Path)
    (typeId : TypeId) (variantId : VariantId) where
  entry : SurfaceElaboration.VariantEntry
  selected : SurfaceElaboration.SelectsVariant context
    (.nominal typeId [] []) path entry
  noArguments : SurfaceElaboration.PathHasNoGenericArguments path
  noPayload : entry.payload = []
  coreType : entry.coreType = typeId
  variant : entry.variant = variantId
  grounded : (Static.GroundTy.nominal typeId [] []).toCore
    context.monomorphization = some (.enumeration typeId)

private def checkNullaryVariant (context : SurfaceElaboration.Context)
    (path : Surface.Path) (typeId : TypeId) (variantId : VariantId) :
    Option (NullaryVariant context path typeId variantId) :=
  match checkSelectedVariant context path typeId variantId with
  | none => none
  | some selected =>
      if noPayload : selected.entry.payload.isEmpty then
        if noArguments : FunctionInstanceCheck.noExplicitArguments path then
          if grounded : (Static.GroundTy.nominal typeId [] []).toCore
              context.monomorphization = some (.enumeration typeId) then
            some {
              entry := selected.entry
              selected := selected.selected
              noArguments := FunctionInstanceCheck.noExplicitArguments_sound
                noArguments
              noPayload := List.isEmpty_iff.mp noPayload
              coreType := selected.coreType
              variant := selected.variant
              grounded }
          else none
        else none
      else none

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

structure LoweredPattern
    (context : SurfaceElaboration.Context) (type : Static.GroundTy)
    (surface : Surface.Pattern) (candidate : Core.Pattern) where
  bindings : List SurfaceElaboration.LocalBinding
  lowers : SurfaceElaboration.PatternLowers context type surface candidate bindings

structure LoweredPatterns
    (context : SurfaceElaboration.Context)
    (types : List Static.GroundTy)
    (surface : List Surface.Pattern) (candidate : List Core.Pattern) where
  bindings : List SurfaceElaboration.LocalBinding
  lowers : SurfaceElaboration.PatternsLower context types surface candidate bindings

structure LoweredMatchArms
    (context : SurfaceElaboration.Context) (scrutineeType : Static.GroundTy)
    (surface : List (Surface.Pattern × Surface.Expr))
    (candidate : List (Core.Pattern × Core.Expr)) where
  resultType : Static.GroundTy
  lowers : SurfaceElaboration.MatchArmsInfer context scrutineeType resultType
    surface candidate

structure CheckedMatchArms
    (context : SurfaceElaboration.Context) (scrutineeType resultType : Static.GroundTy)
    (surface : List (Surface.Pattern × Surface.Expr))
    (candidate : List (Core.Pattern × Core.Expr)) : Type where
  lowers : SurfaceElaboration.MatchArmsLower context scrutineeType resultType
    surface candidate

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
  | .literal (.string value), .value (.string actual) =>
      if equal : actual = value then
        equal ▸ some {
          groundType := .scalar .string
          lowers := .literal .string rfl }
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
  | .path path, .enumValue typeId variantId [] =>
      match checkNullaryVariant context path typeId variantId with
      | none => none
      | some checked =>
          some {
            groundType := .nominal typeId [] []
            lowers := by
              simpa only [checked.variant] using
                (SurfaceElaboration.ExprLowers.nullaryVariant
                  checked.selected checked.noArguments checked.noPayload
                  checked.coreType checked.grounded) }
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
  | .path path, .constant id =>
      match checkNotShadowed context path with
      | none => none
      | some notShadowed =>
          match NameResolutionCheck.checkGlobal context .value path with
          | none => none
          | some resolved =>
              match found : context.constants.find?
                  (fun entry => decide (entry.declaration = resolved.symbol.declaration)) with
              | none => none
              | some entry =>
                  if sameId : entry.constant = id then
                    some {
                      groundType := entry.type
                      lowers := by
                        have member : entry ∈ context.constants :=
                          List.mem_of_find?_eq_some found
                        have declaration : entry.declaration = resolved.symbol.declaration :=
                          of_decide_eq_true (List.find?_eq_some_iff_getElem.mp found).1
                        have lowered : SurfaceElaboration.ExprLowers context
                            (.path path) entry.type (.constant entry.constant) :=
                          .constant (.intro notShadowed.property resolved.symbol
                            resolved.resolved member declaration)
                        simpa only [sameId] using lowered }
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
                match leftCore : left.groundType.toCore context.monomorphization with
                | none => none
                | some leftType =>
                    match rightCore : right.groundType.toCore context.monomorphization with
                    | none => none
                    | some rightType =>
                        match Typing.Check.checkBinaryAny
                            (SurfaceElaboration.lowerBinaryOp surfaceOp)
                            leftType rightType with
                        | none => none
                        | some ⟨outputType, typed⟩ =>
                            match outputType with
                            | .scalar outputScalar =>
                                match equal with
                                | rfl => some {
                                    groundType := .scalar outputScalar
                                    lowers := .binary left.lowers right.lowers
                                      leftCore rightCore rfl typed.down }
                            | _ => none
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
      .enumValue typeId variantId coreArguments =>
      match VariantConstructorCheck.check context path typeId variantId with
      | none => none
      | some selected =>
          match checkSymbolicExprs context surfaceArguments
              selected.scheme.payload coreArguments with
          | none => none
          | some arguments =>
              some {
                groundType := .nominal selected.scheme.sourceType
                  selected.instanceRow.typeArguments selected.instanceRow.constArguments
                lowers := by
                  simpa only [selected.coreType, selected.variant] using
                    (SurfaceElaboration.ExprLowers.variantCallNongeneric
                      selected.selected selected.notIntrinsic selected.noArguments
                      selected.nongeneric selected.instantiated arguments.down) }
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
  | .matchValue surfaceScrutinee surfaceArms,
      .matchValue candidateScrutinee candidateArms =>
      match checkExpr context surfaceScrutinee candidateScrutinee with
      | none => none
      | some scrutinee =>
          match checkMatchArms context scrutinee.groundType
              surfaceArms candidateArms with
          | none => none
          | some arms =>
              some {
                groundType := arms.resultType
                lowers := .matchValue scrutinee.lowers arms.lowers }
  | _, _ => none

def checkPattern (context : SurfaceElaboration.Context)
    (type : Static.GroundTy) :
    (surface : Surface.Pattern) → (candidate : Core.Pattern) →
      Option (LoweredPattern context type surface candidate)
  | .wildcard, .wildcard =>
      some { bindings := [], lowers := .wildcard }
  | .boolean value, .literal (.boolean actual) =>
      match type with
      | .scalar .bool =>
          if equal : actual = value then
            equal ▸ some { bindings := [], lowers := .boolean }
          else none
      | _ => none
  | .integer text, .literal (.signed .i32 actual) =>
      match type with
      | .scalar (.signed .i32) =>
          match parsed : Elaboration.parseUnsignedInteger text with
          | none => none
          | some value =>
              if upper : Int.ofNat value ≤ Typing.signedMax context.target .i32 then
                if equal : actual = Int.ofNat value then
                  equal ▸ some {
                    bindings := []
                    lowers := .integer rfl (.signedInteger parsed upper) }
                else none
              else none
      | _ => none
  | .path path [], .bind id =>
      match single : SurfaceElaboration.singleNamePath? path with
      | none => none
      | some name =>
          match checkNoGlobalValue context path with
          | none => none
          | some noGlobal =>
              if fresh : context.locals.all (fun binding => decide (binding.id ≠ id)) then
                some {
                  bindings := [{ name, id, type }]
                  lowers := .bind single noGlobal.property id
                    (by
                      intro binding member
                      exact of_decide_eq_true
                        (List.all_eq_true.mp fresh binding member)) }
              else none
  | .path path surfacePayload, .enumVariant typeId variantId corePayload =>
      match type with
      | .nominal receiver [] [] =>
          if receiverEqual : receiver = typeId then
            match checkSelectedVariant context path typeId variantId with
            | none => none
            | some selected =>
                match checkPatterns context selected.entry.payload
                    surfacePayload corePayload with
                | none => none
                | some payload =>
                    match checkPatternBindingsFresh context payload.bindings with
                    | none => none
                    | some fresh =>
                        match receiverEqual with
                        | rfl =>
                            some {
                              bindings := payload.bindings
                              lowers := by
                                simpa only [selected.coreType, selected.variant] using
                                  (SurfaceElaboration.PatternLowers.variant
                                    selected.selected payload.lowers fresh.property) }
          else none
      | _ => none
  | _, _ => none

def checkPatterns (context : SurfaceElaboration.Context) :
    (types : List Static.GroundTy) →
    (surface : List Surface.Pattern) → (candidate : List Core.Pattern) →
      Option (LoweredPatterns context types surface candidate)
  | [], [], [] => some { bindings := [], lowers := .nil }
  | type :: types, surface :: surfaces, candidate :: candidates =>
      match checkPattern context type surface candidate with
      | none => none
      | some head =>
          match checkPatterns context types surfaces candidates with
          | none => none
          | some tail =>
              some {
                bindings := head.bindings ++ tail.bindings
                lowers := .cons head.lowers tail.lowers }
  | _, _, _ => none

def checkMatchArms (context : SurfaceElaboration.Context)
    (scrutineeType : Static.GroundTy) :
    (surface : List (Surface.Pattern × Surface.Expr)) →
    (candidate : List (Core.Pattern × Core.Expr)) →
      Option (LoweredMatchArms context scrutineeType surface candidate)
  | (surfacePattern, surfaceBody) :: surfaceTail,
      (corePattern, coreBody) :: coreTail =>
      match checkPattern context scrutineeType surfacePattern corePattern with
      | none => none
      | some pattern =>
          match checkExpr (context.bindLocals pattern.bindings)
              surfaceBody coreBody with
          | none => none
          | some body =>
              match checkMatchArmsTail context scrutineeType body.groundType
                  surfaceTail coreTail with
              | none => none
              | some tail =>
                  some {
                    resultType := body.groundType
                    lowers := .cons pattern.lowers body.lowers tail.lowers }
  | _, _ => none

def checkMatchArmsTail (context : SurfaceElaboration.Context)
    (scrutineeType resultType : Static.GroundTy) :
    (surface : List (Surface.Pattern × Surface.Expr)) →
    (candidate : List (Core.Pattern × Core.Expr)) →
      Option (CheckedMatchArms context scrutineeType resultType surface candidate)
  | [], [] => some { lowers := .nil }
  | (surfacePattern, surfaceBody) :: surfaceTail,
      (corePattern, coreBody) :: coreTail =>
      match checkPattern context scrutineeType surfacePattern corePattern with
      | none => none
      | some pattern =>
          match checkExpr (context.bindLocals pattern.bindings)
              surfaceBody coreBody with
          | none => none
          | some body =>
              if equal : body.groundType = resultType then
                match checkMatchArmsTail context scrutineeType resultType
                    surfaceTail coreTail with
                | none => none
                | some tail =>
                    some {
                      lowers := .cons pattern.lowers
                        (by simpa [equal] using
                          (SurfaceElaboration.ExprChecks.exact body.lowers))
                        tail.lowers }
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

def checkSymbolicExprs (context : SurfaceElaboration.Context) :
    (surface : List Surface.Expr) → (symbolic : List Static.Ty) →
      (candidate : List Core.Expr) →
      Option (PLift (SurfaceElaboration.SymbolicExprsCheck
        context context.substitution surface symbolic candidate))
  | [], [], [] => some ⟨.nil⟩
  | surfaceHead :: surfaceTail, symbolicHead :: symbolicTail,
      candidateHead :: candidateTail =>
      match instantiated : symbolicHead.instantiate context.substitution with
      | none => none
      | some groundType =>
          match checkExpr context surfaceHead candidateHead with
          | none => none
          | some lowered =>
              if equal : lowered.groundType = groundType then
                match checkSymbolicExprs context surfaceTail symbolicTail candidateTail with
                | none => none
                | some tail =>
                    have head : SurfaceElaboration.ExprChecks context
                        surfaceHead groundType candidateHead := by
                      simpa only [equal] using
                        (SurfaceElaboration.ExprChecks.exact lowered.lowers)
                    some ⟨.cons instantiated head tail.down⟩
              else none
  | _, _, _ => none
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
      if lower : next ≤ id then
        match checkFreshLocal context.locals id with
        | none => none
        | some fresh =>
            match checkExpr context surfaceInitializer candidateInitializer with
            | none => none
            | some ⟨.scalar initializerScalar, initializerLowers⟩ =>
                if initializerType : initializerScalar = scalar then
                  let groundType : Static.GroundTy := .scalar scalar
                  match checkStmts (context.bindLocal name id groundType) (id + 1)
                      surfaceTail candidateTail with
                  | none => none
                  | some tail =>
                      have initializerInferred :
                          SurfaceElaboration.ExprLowers context surfaceInitializer
                            groundType candidateInitializer := by
                        simpa [groundType, initializerType] using initializerLowers
                      some {
                        finalNext := tail.finalNext
                        lowers := .letInferred (id := id) (type := groundType)
                          (loweredType := .scalar scalar) lower fresh.proof
                          initializerInferred rfl tail.lowers }
                else none
            | some ⟨_, _⟩ => none
      else none
  | .letLocal name (some surfaceType) (some surfaceInitializer) :: surfaceTail,
      .letLocal id coreType candidateInitializer candidateTail =>
      if lower : next ≤ id then
        match TypeLoweringCheck.check context surfaceType coreType with
        | none => none
        | some annotation =>
            match checkFreshLocal context.locals id with
            | none => none
            | some fresh =>
                match checkExpr context surfaceInitializer candidateInitializer with
                | none => none
                | some initializer =>
                    match Static.GroundTy.decEq initializer.groundType
                        annotation.groundType with
                    | isFalse _ => none
                    | isTrue initializerType =>
                        match checkStmts
                            (context.bindLocal name id annotation.groundType)
                            (id + 1) surfaceTail candidateTail with
                        | none => none
                        | some tail =>
                            have initializerChecked :
                                SurfaceElaboration.ExprChecks context surfaceInitializer
                                  annotation.groundType candidateInitializer := by
                              simpa [initializerType] using
                                (SurfaceElaboration.ExprChecks.exact initializer.lowers)
                            some {
                              finalNext := tail.finalNext
                              lowers := .letAnnotated (id := id) lower fresh.proof
                                annotation.typed.down initializerChecked
                                annotation.grounded tail.lowers }
      else none
  | .letLocal name (some surfaceType) none :: surfaceTail,
      .letUninitialized id coreType candidateTail =>
      if lower : next ≤ id then
        match TypeLoweringCheck.check context surfaceType coreType with
        | none => none
        | some annotation =>
            match checkFreshLocal context.locals id with
            | none => none
            | some fresh =>
                match checkStmts (context.bindLocal name id annotation.groundType) (id + 1)
                    surfaceTail candidateTail with
                | none => none
                | some tail =>
                    some {
                      finalNext := tail.finalNext
                      lowers := .letUninitialized (id := id) lower fresh.proof
                        annotation.typed.down annotation.grounded tail.lowers }
      else none
  | [.returnValue none], .returnValue none =>
      some { finalNext := next, lowers := .terminalReturnUnit }
  | [.returnValue (some surfaceValue)], .returnValue (some candidateValue) =>
      match checkExpr context surfaceValue candidateValue with
      | none => none
      | some value =>
          some { finalNext := next, lowers := .terminalReturnValue (.exact value.lowers) }
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

end Lanius.Compiler.BodyCheck
