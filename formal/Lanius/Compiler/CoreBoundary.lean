import Lanius.Compiler.FrontendBoundary
import Lanius.Compiler.DeclarationCheck
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
  | typing
deriving DecidableEq, Repr

/- Candidate rows are derived from the checked catalog.  A source declaration
   can only be paired with the Core namespace selected by its checked kind. -/
def candidateForHeader (header : DeclarationHeader) : Option CandidateRow :=
  match header.kind with
  | .structureType => some
      { occurrence := header.source, header := header,
        core := .structure header.declaration }
  | .constant => some
      { occurrence := header.source, header := header,
        core := .constant header.declaration }
  | .function | .externalFunction => some
      { occurrence := header.source, header := header,
        core := .function header.declaration }
  | _ => none

def candidateRows? (catalog : Catalog) : Option (List CandidateRow) :=
  let aliasesSkipped := catalog.headers.filter (fun header => header.kind != .typeAlias)
  aliasesSkipped.mapM candidateForHeader

structure Checked (encoded : String)
    (expectedSources : List Extraction.SourceFile)
    (frontend : FrontendBoundary.Checked encoded expectedSources)
    (program : Core.Program) where
  candidates : List CandidateRow
  candidatesSynthesized : candidateRows? frontend.catalog.catalog = some candidates
  declarations : DeclarationCheck.CheckedDeclarations
    (frontendPack frontend.frontend) frontend.catalog.catalog program
  declarationsAccepted :
    DeclarationCheck.checkDeclarations (frontendPack frontend.frontend)
      frontend.catalog.catalog frontend.catalog.wellFormed program candidates =
      .ok declarations
  typing : ProofOf (Typing.ProgramWellTyped program)
  typingAccepted : Typing.Check.checkProgramWellTyped program = some typing

def check (frontend : FrontendBoundary.Checked encoded expectedSources)
    (program : Core.Program) : Except Failure (Checked encoded expectedSources frontend program) :=
  match candidatesAccepted : candidateRows? frontend.catalog.catalog with
  | none => .error .candidateSynthesis
  | some candidates =>
      match declarationsAccepted :
          DeclarationCheck.checkDeclarations (frontendPack frontend.frontend)
            frontend.catalog.catalog frontend.catalog.wellFormed program candidates with
      | .error failure => .error (.declarations failure)
      | .ok declarations =>
          match typingAccepted : Typing.Check.checkProgramWellTyped program with
          | none => .error .typing
          | some typing =>
              .ok {
                candidates := candidates
                candidatesSynthesized := candidatesAccepted
                declarations := declarations
                declarationsAccepted := declarationsAccepted
                typing := typing
                typingAccepted := typingAccepted
              }

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
  obtain ⟨_, _, sourceWellFormed, catalogWellFormed, importsWellFormed⟩ :=
    FrontendBoundary.checked_source_evidence (checked := frontend)
  exact ⟨sourceWellFormed, catalogWellFormed, importsWellFormed,
    checked.declarations.exact, checked.typing.down⟩

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
