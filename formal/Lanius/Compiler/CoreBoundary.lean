import Lanius.Compiler.FrontendBoundary
import Lanius.Compiler.DeclarationCheck
import Lanius.Compiler.ContextSynthesis
import Lanius.Compiler.EnumShapeCheck
import Lanius.Typing.Check

namespace Lanius.Compiler.CoreBoundary

open Lanius
open Lanius.Declarations
open Lanius.Compiler
open Lanius.Compiler.ProgramLowering
open FrontendBoundary
open DeclarationCheck

inductive Failure where
  | candidateSynthesis
  | declarations (failure : DeclarationCheck.Failure)
  | enumShapes
  | typing
deriving DecidableEq, Repr

/- Candidate rows are derived from the checked catalog.  A source declaration
   can only be paired with the Core namespace selected by its checked kind. -/
def candidateForHeader (header : DeclarationHeader) : Option CandidateRow :=
  match header.kind with
  | .structureType => some
      { occurrence := header.source, header := header,
        core := .structure header.declaration }
  | .enumeration => some
      { occurrence := header.source, header := header,
        core := .enumeration header.declaration }
  | .constant => some
      { occurrence := header.source, header := header,
        core := .constant header.declaration }
  | .function | .externalFunction => some
      { occurrence := header.source, header := header,
        core := .function header.declaration }
  | _ => none

def candidateRows? (catalog : Catalog) : Option (List CandidateRow) :=
  let nestedOrAliasesSkipped := catalog.headers.filter
    (fun header => header.kind != .typeAlias && header.kind != .enumVariant)
  nestedOrAliasesSkipped.mapM candidateForHeader

def enumContextInput (input : FrontendBoundary.CoreInput)
    (program : Core.Program)
    (declarations : DeclarationCheck.CheckedDeclarations
      input.pack input.catalog.catalog program) :
    SurfaceElaboration.Context :=
  ContextSynthesis.synthesize input.pack input.catalog.catalog input.imports program
    declarations.rows declarations.aliases

structure CheckedInput (input : FrontendBoundary.CoreInput)
    (program : Core.Program) where
  candidates : List CandidateRow
  candidatesSynthesized : candidateRows? input.catalog.catalog = some candidates
  declarations : DeclarationCheck.CheckedDeclarations
    input.pack input.catalog.catalog program
  declarationsAccepted :
    DeclarationCheck.checkDeclarations input.pack
      input.catalog.catalog input.catalog.wellFormed program candidates =
      .ok declarations
  enumShapes : PLift (∀ row ∈ declarations.rows,
    EnumShapeCheck.RowShape input.pack
      (enumContextInput input program declarations) row)
  enumShapesAccepted : EnumShapeCheck.checkRows
    input.pack (enumContextInput input program declarations)
    declarations.rows = some enumShapes
  typing : ProofOf (Typing.ProgramWellTyped program)
  typingAccepted : Typing.Check.checkProgramWellTyped program = some typing

def checkInput (input : FrontendBoundary.CoreInput)
    (program : Core.Program) : Except Failure (CheckedInput input program) :=
  match candidatesAccepted : candidateRows? input.catalog.catalog with
  | none => .error .candidateSynthesis
  | some candidates =>
      match declarationsAccepted :
          DeclarationCheck.checkDeclarations input.pack
            input.catalog.catalog input.catalog.wellFormed program candidates with
      | .error failure => .error (.declarations failure)
      | .ok declarations =>
          match enumShapesAccepted : EnumShapeCheck.checkRows
              input.pack (enumContextInput input program declarations)
              declarations.rows with
          | none => .error .enumShapes
          | some enumShapes =>
              match typingAccepted : Typing.Check.checkProgramWellTyped program with
              | none => .error .typing
              | some typing =>
                  .ok {
                    candidates := candidates
                    candidatesSynthesized := candidatesAccepted
                    declarations := declarations
                    declarationsAccepted := declarationsAccepted
                    enumShapes := enumShapes
                    enumShapesAccepted := enumShapesAccepted
                    typing := typing
                    typingAccepted := typingAccepted
                  }

abbrev Checked (encoded : String)
    (expectedSources : List Extraction.SourceFile)
    (frontend : FrontendBoundary.Checked encoded expectedSources)
    (program : Core.Program) : Type :=
  CheckedInput (FrontendBoundary.coreInput frontend) program

def enumContext (frontend : FrontendBoundary.Checked encoded expectedSources)
    (program : Core.Program)
    (declarations : DeclarationCheck.CheckedDeclarations
      (frontendPack frontend.frontend) frontend.catalog.catalog program) :
    SurfaceElaboration.Context :=
  enumContextInput (FrontendBoundary.coreInput frontend) program declarations

def check (frontend : FrontendBoundary.Checked encoded expectedSources)
    (program : Core.Program) : Except Failure (Checked encoded expectedSources frontend program) :=
  checkInput (FrontendBoundary.coreInput frontend) program

theorem checked_input_evidence
    {input : FrontendBoundary.CoreInput}
    {program : Core.Program}
    {checked : CheckedInput input program} :
    SourcePackWellFormed input.pack ∧
      CatalogWellFormed input.pack input.catalog.catalog ∧
      ImportCollectionCovers input.pack input.imports ∧
      DeclarationLoweringsExact input.pack input.catalog.catalog program
        checked.declarations.rows ∧
      Typing.ProgramWellTyped program :=
  ⟨input.sourceWellFormed, input.catalog.wellFormed,
    input.importsEvidence.covers, checked.declarations.exact,
    checked.typing.down⟩

theorem checked_evidence
    {encoded : String} {expectedSources : List Extraction.SourceFile}
    {frontend : FrontendBoundary.Checked encoded expectedSources}
    {program : Core.Program}
    {checked : Checked encoded expectedSources frontend program} :
    SourcePackWellFormed (frontendPack frontend.frontend) ∧
      CatalogWellFormed (frontendPack frontend.frontend) frontend.catalog.catalog ∧
      ImportCollectionCovers (frontendPack frontend.frontend) frontend.imports ∧
      DeclarationLoweringsExact (frontendPack frontend.frontend)
        frontend.catalog.catalog program checked.declarations.rows ∧
      Typing.ProgramWellTyped program := by
  exact checked_input_evidence (checked := checked)

theorem check_sound
    {encoded : String} {expectedSources : List Extraction.SourceFile}
    {frontend : FrontendBoundary.Checked encoded expectedSources}
    {program : Core.Program}
    {checked : Checked encoded expectedSources frontend program}
    (_accepted : check frontend program = .ok checked) :
    SourcePackWellFormed (frontendPack frontend.frontend) ∧
      CatalogWellFormed (frontendPack frontend.frontend) frontend.catalog.catalog ∧
      ImportCollectionCovers (frontendPack frontend.frontend) frontend.imports ∧
      DeclarationLoweringsExact (frontendPack frontend.frontend)
        frontend.catalog.catalog program checked.declarations.rows ∧
      Typing.ProgramWellTyped program :=
  checked_evidence

end Lanius.Compiler.CoreBoundary
