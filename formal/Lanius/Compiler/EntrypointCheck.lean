import Lanius.Compiler.ExecutableBoundary

namespace Lanius.Compiler.EntrypointCheck

open Lanius

inductive SelectionPolicy where
  | uniqueEligible

/- The policy is intentionally order-independent: the executable boundary is
   accepted only when exactly one eligible source row exists. -/
def selectionPolicy : SelectionPolicy := .uniqueEligible

inductive Failure where
  | missingMain
  | ambiguousMain
deriving DecidableEq, Repr

def returnSupported : Core.Ty → Bool
  | .unit => true
  | .scalar .bool => true
  | .scalar (.signed _) => true
  | .scalar (.unsigned _) => true
  | .scalar .char => true
  | .scalar _ => false
  | .array _ _ => false
  | .slice _ => false
  | .reference _ => false
  | _ => false

theorem returnSupported_sound {ty : Core.Ty} (h : returnSupported ty = true) :
    Execution.EntrypointReturnType ty := by
  cases ty with
  | unit => exact .unit
  | scalar scalar =>
      cases scalar with
      | bool => exact .boolean
      | signed type => exact .signed
      | unsigned type => exact .unsigned
      | f32 => simp [returnSupported] at h
      | f64 => simp [returnSupported] at h
      | char => exact .character
      | string => simp [returnSupported] at h
      | rawPtr => simp [returnSupported] at h
  | array element length => simp [returnSupported] at h
  | slice element => simp [returnSupported] at h
  | reference referent => simp [returnSupported] at h
  | _ => simp [returnSupported] at h

def mainCandidate
    {pack : Declarations.SourcePack} {catalog : Declarations.Catalog}
    {program : Core.Program} {environment : Names.Environment}
    {baseContext : SurfaceElaboration.Context}
    {rows : List (ProgramLowering.DeclarationLowering pack catalog program)}
    (body : ProgramLowering.FunctionBodyLowering pack catalog program environment
      baseContext rows) : Bool :=
  decide (body.row.header.name = some "main" ∧
    body.row.header.lookupNamespace = some .value ∧
    body.core.parameters = [] ∧
    returnSupported body.core.returnType = true)

theorem mainCandidate_sound
    {pack : Declarations.SourcePack} {catalog : Declarations.Catalog}
    {program : Core.Program} {environment : Names.Environment}
    {baseContext : SurfaceElaboration.Context}
    {rows : List (ProgramLowering.DeclarationLowering pack catalog program)}
    {body : ProgramLowering.FunctionBodyLowering pack catalog program environment
      baseContext rows} (h : mainCandidate body = true) :
    body.row.header.name = some "main" ∧
      body.row.header.lookupNamespace = some .value ∧
      body.core.parameters = [] ∧
      returnSupported body.core.returnType = true := by
  simpa [mainCandidate] using (of_decide_eq_true h)

def selectCandidates (policy : SelectionPolicy)
    (lowering : ProgramLowering.ProgramLowering) :
  List (ProgramLowering.FunctionBodyLowering
      lowering.pack lowering.catalog lowering.program lowering.environment
      lowering.context lowering.declarations) :=
  match policy with
  | .uniqueEligible => lowering.functionBodies.filter mainCandidate

def mainCandidates (lowering : ProgramLowering.ProgramLowering) :=
  selectCandidates selectionPolicy lowering

def check (lowering : ProgramLowering.ProgramLowering) :
    Except Failure (ExecutableBoundary.MainSelection lowering) :=
  match selected : mainCandidates lowering with
  | [] => .error .missingMain
  | [body] =>
      have filteredMember : body ∈ mainCandidates lowering := by
        rw [selected]
        simp
      have rowMember : body ∈ lowering.functionBodies :=
        (List.mem_filter.mp filteredMember).1
      have candidate : mainCandidate body = true :=
        (List.mem_filter.mp filteredMember).2
      have fields := mainCandidate_sound candidate
      .ok {
        body := body
        bodyMember := rowMember
        sourceName := fields.1
        sourceValueNamespace := fields.2.1
        zeroParameters := fields.2.2.1
        allowedReturn := returnSupported_sound fields.2.2.2
      }
  | _ :: _ :: _ => .error .ambiguousMain

theorem selected_wellFormed
    {encoded : String} {expectedSources : List Extraction.SourceFile}
    {checked : Extraction.SyntaxCheck.CheckedSourcePack encoded expectedSources}
    (boundary : SourceCoreBoundary.SourceCoreBoundary encoded expectedSources checked)
    (selection : ExecutableBoundary.MainSelection boundary.lowering) :
    Execution.ExecutableWellFormed
      (ExecutableBoundary.executable { source := boundary, main := selection }) := by
  exact ExecutableBoundary.executable_wellFormed { source := boundary, main := selection }

end Lanius.Compiler.EntrypointCheck
