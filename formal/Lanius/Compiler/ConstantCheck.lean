import Lanius.Compiler.ProgramLowering
import Lanius.Compiler.TypeLoweringCheck
import Lanius.Typing.Check

namespace Lanius.Compiler.ConstantCheck

open Lanius
open Lanius.Compiler.ProgramLowering

inductive Failure where
  | sourceMismatch
  | unsupportedType
  | unsupportedValue
  | noLocals
deriving DecidableEq, Repr

/- Compatibility projection for body checking; the proof-producing Core Ty
   checker itself lives in `TypeLoweringCheck`. -/
def checkTypeGrounds (context : SurfaceElaboration.Context)
    (surface : Surface.TypeExpr) (ground : Static.GroundTy) :
    Option (Typing.Check.ProofOf
      (SurfaceElaboration.TypeGrounds context surface ground)) :=
  TypeLoweringCheck.checkGround context surface ground

structure CheckedLiteral (program : Core.Program)
    (context : SurfaceElaboration.Context) (surface : Surface.Expr)
    (candidate : Core.Value) (coreType : Core.Ty) where
  typed : SurfaceElaboration.TypedExprLowering program context surface
  core : typed.core = .value candidate
  type : typed.coreType = coreType

def checkLiteralExpr (program : Core.Program)
    (context : SurfaceElaboration.Context) (surface : Surface.Expr)
    (candidate : Core.Value) (coreType : Core.Ty)
    (target : program.target = context.target) :
    Option (CheckedLiteral program context surface candidate coreType) :=
  match surface, candidate, coreType with
  | .literal (.boolean expected), .boolean actual, .scalar .bool =>
      if equal : actual = expected then
        match Typing.Check.checkValue program
            (.boolean actual) (.scalar .bool) with
        | none => none
        | some checkedValue =>
            have lowers : SurfaceElaboration.ExprLowers context
                (.literal (.boolean expected)) (.scalar .bool)
                (.value (.boolean actual)) := by
              simpa [equal] using
                (SurfaceElaboration.ExprLowers.literal
                  (context := context) (literal := .boolean expected)
                  (groundType := .scalar .bool)
                  (expression := .value (.boolean expected))
                  (.boolean) rfl)
            some {
              typed := {
                groundType := .scalar .bool
                coreType := .scalar .bool
                core := .value (.boolean actual)
                lowers := lowers
                grounded := rfl
                target := target
                typed := .value checkedValue.down rfl }
              core := rfl
              type := rfl }
      else none
  | .literal (.integer text), .signed .i32 actual,
      .scalar (.signed .i32) =>
      match parsed : Elaboration.parseUnsignedInteger text with
      | none => none
      | some value =>
          if accepted : Int.ofNat value ≤ Typing.signedMax context.target .i32 ∧
              actual = Int.ofNat value then
            match Typing.Check.checkValue program
                (.signed .i32 actual) (.scalar (.signed .i32)) with
            | none => none
            | some checkedValue =>
                have upper : Int.ofNat value ≤ Typing.signedMax context.target .i32 :=
                  accepted.1
                have equal : actual = Int.ofNat value := accepted.2
                have lowers : SurfaceElaboration.ExprLowers context
                    (.literal (.integer text)) (.scalar (.signed .i32))
                    (.value (.signed .i32 actual)) := by
                  simpa [equal] using
                    (SurfaceElaboration.ExprLowers.literal
                      (context := context) (literal := .integer text)
                      (groundType := .scalar (.signed .i32))
                      (expression := .value (.signed .i32 (Int.ofNat value)))
                      (.signedInteger parsed upper) rfl)
                some {
                  typed := {
                    groundType := .scalar (.signed .i32)
                    coreType := .scalar (.signed .i32)
                    core := .value (.signed .i32 actual)
                    lowers := lowers
                    grounded := rfl
                    target := target
                    typed := .value checkedValue.down rfl }
                  core := rfl
                  type := rfl }
          else none
  | _, _, _ => none

/- The fields below are the already-established source/catalog boundary.  The
   checker owns only source agreement, literal agreement, and the two proofs
   reconstructed above. -/
structure ConstantCandidate
    (pack : Declarations.SourcePack) (catalog : Declarations.Catalog)
    (program : Core.Program) (environment : Names.Environment)
    (baseContext : SurfaceElaboration.Context)
    (rows : List (DeclarationLowering pack catalog program)) where
  row : DeclarationLowering pack catalog program
  rowMember : row ∈ rows
  address : Declarations.ItemAddress
  name : Surface.Name
  isPublic : Bool
  surfaceType : Surface.TypeExpr
  value : Surface.Expr
  sourceFound : pack.item? address =
    some (.constant name isPublic surfaceType value)
  source : row.occurrence = .item address
  core : Core.Constant
  coreMap : row.core = .constant core
  context : SurfaceElaboration.Context
  contextMatches : ContextMatches context baseContext environment row.header.moduleId
  target : program.target = context.target
  noLocals : context.locals = []

def check
    (candidate : ConstantCandidate pack catalog program environment baseContext rows) :
    Except Failure
      (ConstantLowering pack catalog program environment baseContext rows) :=
  if _source : candidate.row.header.kind = .constant then
    if locals : candidate.context.locals = [] then
      match checkLiteralExpr program candidate.context candidate.value
              candidate.core.value candidate.core.type candidate.target with
      | none => .error .unsupportedValue
      | some typedEvidence =>
          match checkTypeGrounds candidate.context candidate.surfaceType
                  typedEvidence.typed.groundType with
          | none => .error .unsupportedType
          | some declaredType =>
              .ok {
                row := candidate.row
                rowMember := candidate.rowMember
                address := candidate.address
                name := candidate.name
                isPublic := candidate.isPublic
                surfaceType := candidate.surfaceType
                value := candidate.value
                sourceFound := candidate.sourceFound
                source := candidate.source
                core := candidate.core
                coreMap := candidate.coreMap
                context := candidate.context
                typed := typedEvidence.typed
                declaredType := declaredType.down
                typedType := typedEvidence.type
                coreValue := candidate.core.value
                typedValue := typedEvidence.core
                contextMatches := candidate.contextMatches
                noLocals := locals
                coreShape := rfl }
    else .error .noLocals
  else .error .sourceMismatch

end Lanius.Compiler.ConstantCheck
