import Lanius.Declarations.SourceCheck
import Lanius.Extraction.SyntaxCheck.Pack

namespace Lanius.Compiler.SourcePackCheck

open Lanius
open Lanius.Declarations
open Lanius.Extraction

/-! The syntax certificate supplies Surface files, but never their semantic
    identities.  This bridge assigns both identities from pack order and
    derives the declared module path from the checked leading item. -/

def leadingModulePath (file : Surface.File) : Names.ModulePath :=
  match file.items with
  | .module path :: _ => (plainPath? path).getD []
  | _ => []

def declaredFile (id : FileId) (contents : Surface.File) : Declarations.SourceFile :=
  { id
    moduleInfo := { id, path := leadingModulePath contents }
    contents
    origin := .declared }

def declaredFiles : Nat → {units : List Artifact} →
    SyntaxCheck.CheckedUnits units → List Declarations.SourceFile
  | _, _, .nil => []
  | id, _, .cons head tail =>
      declaredFile id head.surface.surface :: declaredFiles (id + 1) tail

def surfaceFiles : {units : List Artifact} →
    SyntaxCheck.CheckedUnits units → List Surface.File
  | _, .nil => []
  | _, .cons head tail => head.surface.surface :: surfaceFiles tail

def declaredPack {encoded : String} {expectedSources : List Extraction.SourceFile}
    (checked : SyntaxCheck.CheckedSourcePack encoded expectedSources) : Declarations.SourcePack :=
  ⟨declaredFiles 0 checked.units⟩

def check {encoded : String} {expectedSources : List Extraction.SourceFile}
    (checked : SyntaxCheck.CheckedSourcePack encoded expectedSources) :
    Option (ProofOf (SourcePackWellFormed (declaredPack checked))) :=
  checkSourcePackWellFormed (declaredPack checked)

theorem check_sound {encoded : String} {expectedSources : List Extraction.SourceFile}
    {checked : SyntaxCheck.CheckedSourcePack encoded expectedSources}
    {evidence : ProofOf (SourcePackWellFormed (declaredPack checked))}
    (accepted : check checked = some evidence) :
    SourcePackWellFormed (declaredPack checked) := by
  exact checkSourcePackWellFormed_evidence accepted

theorem declaredFiles_surface_alignment (start : Nat) :
    ∀ {units : List Artifact} (checked : SyntaxCheck.CheckedUnits units),
      (declaredFiles start checked).map (fun file => file.contents) =
        surfaceFiles checked
  | _, .nil => rfl
  | _, .cons head tail => by
      simp [declaredFile, declaredFiles, surfaceFiles,
        declaredFiles_surface_alignment (start + 1) tail]

theorem surface_alignment {encoded : String} {expectedSources : List Extraction.SourceFile}
    (checked : SyntaxCheck.CheckedSourcePack encoded expectedSources) :
    (declaredPack checked).files.map (fun file => file.contents) =
      surfaceFiles checked.units := by
  exact declaredFiles_surface_alignment 0 checked.units

end Lanius.Compiler.SourcePackCheck
