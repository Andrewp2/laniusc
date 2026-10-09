import Lanius.Compiler.ProgramLowering
import Lanius.Compiler.ConstantExprCheck
import Lanius.Compiler.TypeLoweringCheck
import Lanius.Typing.Check

namespace Lanius.Compiler.ConstantCheck

open Lanius
open Lanius.Compiler.ProgramLowering

inductive Failure where
  | sourceMismatch
  | unsupportedType
  | unsupportedValue
deriving DecidableEq, Repr

structure CheckedLiteral (program : Core.Program)
    (context : SurfaceElaboration.Context) (surface : Surface.Expr)
    (candidate : Core.Value) (coreType : Core.Ty) where
  groundType : Static.GroundTy
  grounded : groundType.toCore context.monomorphization = some coreType
  lowers : SurfaceElaboration.ExprChecks context surface groundType (.value candidate)
  typed : Typing.ValueHasType program candidate coreType

/-- Literal elaboration already carries the numeric bounds. Reuse that
    evidence rather than running the Core value checker a second time. -/
theorem literalValueTyped (program : Core.Program)
    (lowered : Elaboration.LiteralElaborates program.target literal type (.value value)) :
    Typing.ValueHasType program value type := by
  cases lowered with
  | boolean => exact .boolean _
  | character => exact .character _
  | string => exact .string _
  | signedInteger parsed upper =>
      exact .signed _ _ (Int.le_trans
        (Int.neg_nonpos_of_nonneg (Int.pow_nonneg (by decide)))
        (Int.natCast_nonneg _)) upper
  | unsignedInteger parsed upper => exact .unsigned _ _ upper
  | nullPointer parsed => exact .pointer 0
  | f32 parsed => exact .f32Bits _
  | f64 parsed => exact .f64Bits _

private def checkedLiteral (program : Core.Program)
    (context : SurfaceElaboration.Context)
    (target : program.target = context.target)
    (lowered : Elaboration.LiteralElaborates context.target literal
      (.scalar type) (.value value)) :
    CheckedLiteral program context (.literal literal) value (.scalar type) :=
  { groundType := .scalar type
    grounded := rfl
    lowers := .literal _ lowered rfl
    typed := literalValueTyped program (target ▸ lowered) }

def checkLiteralExpr (program : Core.Program)
    (context : SurfaceElaboration.Context) (surface : Surface.Expr)
    (candidate : Core.Value) (coreType : Core.Ty)
    (target : program.target = context.target) :
    Option (CheckedLiteral program context surface candidate coreType) :=
  match surface, candidate, coreType with
  | .literal (.boolean expected), .boolean actual, .scalar .bool =>
      if equal : actual = expected then
        equal ▸ some (checkedLiteral program context target .boolean)
      else none
  | .literal (.string expected), .string actual, .scalar .string =>
      if equal : actual = expected then
        equal ▸ some (checkedLiteral program context target .string)
      else none
  | .literal (.integer text), .signed .i32 actual,
      .scalar (.signed .i32) =>
      match parsed : Elaboration.parseUnsignedInteger text with
      | none => none
      | some value =>
          if upper : Int.ofNat value ≤ Typing.signedMax context.target .i32 then
            if equal : actual = Int.ofNat value then
              equal ▸ some (checkedLiteral program context target (.signedInteger parsed upper))
            else none
          else none
  | .literal (.integer text), .unsigned .usize actual,
      .scalar (.unsigned .usize) =>
      match parsed : Elaboration.parseUnsignedInteger text with
      | none => none
      | some value =>
          if upper : value ≤ Typing.unsignedMax context.target .usize then
            if equal : actual = value then
              equal ▸ some (checkedLiteral program context target (.unsignedInteger parsed upper))
            else none
          else none
  | .literal (.integer text), .pointer 0, .scalar .rawPtr =>
      if parsed : Elaboration.parseUnsignedInteger text = some 0 then
        some (checkedLiteral program context target (.nullPointer parsed))
      else none
  | _, _, _ => none

structure CheckedInitializer (program : Core.Program) (available : List ConstantId)
    (context : SurfaceElaboration.Context) (surface : Surface.Expr)
    (candidate : Core.Value) (coreType : Core.Ty) where
  groundType : Static.GroundTy
  grounded : groundType.toCore context.monomorphization = some coreType
  expression : Core.Expr
  lowers : SurfaceElaboration.ExprChecks context surface groundType expression
  evaluates : Semantics.ConstantEvaluates program available expression candidate
  typed : Typing.ValueHasType program candidate coreType

def checkInitializer (program : Core.Program) (available : List ConstantId)
    (context : SurfaceElaboration.Context) (surface : Surface.Expr)
    (candidate : Core.Value) (coreType : Core.Ty)
    (target : program.target = context.target) :
    Option (CheckedInitializer program available context surface candidate coreType) := do
  if let some literal := checkLiteralExpr program context surface candidate coreType target then
    return {
      groundType := literal.groundType
      grounded := literal.grounded
      expression := .value candidate
      lowers := literal.lowers
      evaluates := .value
      typed := literal.typed }
  if typeIsInteger : coreType = .scalar (.signed .i32) then
    let integer ← ConstantExprCheck.checkInteger program available context surface
    match actual : integer.value, expected : candidate with
    | .signed .i32 actualValue, .signed .i32 expectedValue =>
        if equal : actualValue = expectedValue then
          let sameValue : integer.value = candidate := by rw [actual, expected, equal]
          let typed ← Typing.Check.checkValue program candidate coreType
          return {
            groundType := .scalar (.signed .i32)
            grounded := typeIsInteger ▸ rfl
            expression := integer.expression
            lowers := .exact integer.lowers
            evaluates := sameValue ▸ integer.evaluates
            typed := typed.down }
        else none
    | _, _ => none
  else none

/- The fields below are the already-established source/catalog boundary.  The
   checker owns source agreement, initializer evaluation, and typing. -/
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
    (candidate : ConstantCandidate pack catalog program environment baseContext rows)
    (available : List ConstantId) :
    Except Failure
      { result : ConstantLowering pack catalog program environment baseContext rows //
        result.available = available } :=
  if _source : candidate.row.header.kind = .constant then
    match checkInitializer program available candidate.context candidate.value
            candidate.core.value candidate.core.type candidate.target with
    | none => .error .unsupportedValue
    | some typedEvidence =>
        match TypeLoweringCheck.checkGround candidate.context candidate.surfaceType
                typedEvidence.groundType with
        | none => .error .unsupportedType
        | some declaredType =>
            .ok ⟨{
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
              groundType := typedEvidence.groundType
              declaredType := declaredType.down
              grounded := typedEvidence.grounded
              initializer := typedEvidence.expression
              lowers := typedEvidence.lowers
              available
              evaluates := typedEvidence.evaluates
              typed := typedEvidence.typed
              target := candidate.target
              contextMatches := candidate.contextMatches
              noLocals := candidate.noLocals }, rfl⟩
  else .error .sourceMismatch

end Lanius.Compiler.ConstantCheck
