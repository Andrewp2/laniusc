import Lanius.Declarations
import Lanius.SurfaceSyntax.Check

namespace Lanius.Declarations

open Lanius
open Lanius.SurfaceSyntax

abbrev ProofOf (predicate : Prop) := SurfaceSyntax.ProofOf predicate

instance (item : Surface.Item) : Decidable (IsModuleItem item) := by
  cases item <;> simp [IsModuleItem] <;> infer_instance

instance (item : Surface.Item) : Decidable (IsImportItem item) := by
  cases item <;> simp [IsImportItem] <;> infer_instance

def checkNonemptyPath (path : Names.ModulePath) : Option (ProofOf (path ≠ [])) :=
  match path with
  | [] => none
  | _ :: _ => some ⟨by simp⟩

def noModuleItems : List Surface.Item → Bool
  | [] => true
  | .module _ :: _ => false
  | _ :: tail => noModuleItems tail

theorem noModuleItems_mem {items : List Surface.Item} (accepted : noModuleItems items = true) :
    ∀ item, item ∈ items → ¬ IsModuleItem item := by
  induction items with
  | nil => simp
  | cons head tail ih =>
      intro item member module
      simp only [List.mem_cons] at member
      rcases member with member | member
      · subst item
        rcases module with ⟨path, rfl⟩
        simp [noModuleItems] at accepted
      · have tailAccepted : noModuleItems tail = true := by
          cases head <;> simp [noModuleItems] at accepted ⊢ <;> assumption
        exact ih tailAccepted item member module

theorem noModuleItems_index {items : List Surface.Item}
    (accepted : noModuleItems items = true) :
    ∀ (index : Nat) (item : Surface.Item),
      items[index]? = some item → ¬ IsModuleItem item := by
  intro index item found module
  have bound := (List.getElem?_eq_some_iff.mp found).choose
  have value := (List.getElem?_eq_some_iff.mp found).choose_spec
  have member : item ∈ items := value ▸ List.getElem_mem bound
  exact noModuleItems_mem accepted item member module

abbrev LeadingRelation : Surface.Item → Surface.Item → Prop :=
  fun earlier later => ¬ IsImportItem later ∨ IsModuleItem earlier ∨ IsImportItem earlier

theorem pairwiseLeading_sound {items : List Surface.Item}
    (accepted : List.Pairwise LeadingRelation items) :
    ∀ (importIndex : Nat) (importItem : Surface.Item),
      items[importIndex]? = some importItem → IsImportItem importItem →
      ∀ (itemIndex : Nat) (item : Surface.Item),
        items[itemIndex]? = some item → ¬ IsModuleItem item →
        ¬ IsImportItem item → importIndex < itemIndex := by
  intro importIndex importItem importFound importProof itemIndex item itemFound notModule notImport
  have importBound := (List.getElem?_eq_some_iff.mp importFound).choose
  have importEq := (List.getElem?_eq_some_iff.mp importFound).choose_spec
  have itemBound := (List.getElem?_eq_some_iff.mp itemFound).choose
  have itemEq := (List.getElem?_eq_some_iff.mp itemFound).choose_spec
  rcases Nat.lt_or_ge importIndex itemIndex with before | after
  · exact before
  · rcases Nat.lt_or_ge itemIndex importIndex with after | equal
    · have relation := (List.pairwise_iff_getElem.mp accepted)
        itemIndex importIndex itemBound importBound after
      have relation' : ¬ IsImportItem importItem ∨ IsModuleItem item ∨ IsImportItem item := by
        simpa [itemEq, importEq] using relation
      exact False.elim (relation'.elim (fun h => h importProof)
        (fun h => h.elim (fun h => False.elim (notModule h))
          (fun h => False.elim (notImport h))))
    · have sameIndex : itemIndex = importIndex :=
        Nat.le_antisymm after equal
      have same : item = importItem := itemEq.symm.trans (by simpa [sameIndex] using importEq)
      exact False.elim (notImport (same ▸ importProof))

def checkDeclaredModule (file : SourceFile) :
    Option (ProofOf (DeclaredModuleMatches file)) :=
  match h : file.contents.items with
  | .module path :: tail =>
      if pathMatches : plainPath? path = some file.moduleInfo.path then
        if noModules : noModuleItems tail = true then
          some ⟨⟨path, by simp [h], pathMatches, by
            intro index item found module
            cases index with
            | zero => rfl
            | succ index =>
                have found' : (Surface.Item.module path :: tail)[index + 1]? = some item := by
                  simpa [h] using found
                have tailFound : tail[index]? = some item := by
                  simpa only [List.getElem?_cons_succ] using found'
                exact False.elim (noModuleItems_index noModules index item tailFound module)⟩⟩
        else none
      else none
  | _ => none

def checkSyntheticModule (file : SourceFile) :
    Option (ProofOf (SyntheticHasNoModule file)) :=
  if accepted : noModuleItems file.contents.items = true then
    some ⟨noModuleItems_index accepted⟩
  else none

def checkImportsLeading (file : SourceFile) :
    Option (ProofOf (ImportsAreLeading file)) :=
  if accepted : List.Pairwise LeadingRelation file.contents.items then
    some ⟨pairwiseLeading_sound accepted⟩
  else none

def checkSourceFileWellFormed (file : SourceFile) :
    Option (ProofOf (SourceFileWellFormed file)) :=
  match file with
  | ⟨id, moduleInfo, contents, .declared⟩ => by
      let current : SourceFile := ⟨id, moduleInfo, contents, .declared⟩
      change Option (ProofOf (SourceFileWellFormed current))
      exact do
        let surfaceProof ← SurfaceSyntax.checkFileWellFormed current.contents
        let path ← checkNonemptyPath current.moduleInfo.path
        let module ← checkDeclaredModule current
        let imports ← checkImportsLeading current
        pure ⟨⟨surfaceProof.down, path.down, module.down, imports.down⟩⟩
  | ⟨id, moduleInfo, contents, .synthetic⟩ => by
      let current : SourceFile := ⟨id, moduleInfo, contents, .synthetic⟩
      change Option (ProofOf (SourceFileWellFormed current))
      exact do
        let surfaceProof ← SurfaceSyntax.checkFileWellFormed current.contents
        let path ← checkNonemptyPath current.moduleInfo.path
        let module ← checkSyntheticModule current
        let imports ← checkImportsLeading current
        pure ⟨⟨surfaceProof.down, path.down, module.down, imports.down⟩⟩

def checkAllFiles : (files : List SourceFile) →
    Option (ProofOf (∀ file, file ∈ files → SourceFileWellFormed file))
  | [] => some ⟨by simp⟩
  | head :: tail => do
      let headProof ← checkSourceFileWellFormed head
      let tailProof ← checkAllFiles tail
      pure ⟨by
        intro file member
        simp only [List.mem_cons] at member
        rcases member with rfl | member
        · exact headProof.down
        · exact tailProof.down file member⟩

abbrev DistinctFileIds : SourceFile → SourceFile → Prop :=
  fun left right => left.id ≠ right.id

abbrev DistinctModules : SourceFile → SourceFile → Prop :=
  fun left right => left.moduleInfo.id ≠ right.moduleInfo.id ∧
    left.moduleInfo.path ≠ right.moduleInfo.path

def checkSourceFileIds (files : List SourceFile) :
    Option (ProofOf (List.Pairwise DistinctFileIds files)) :=
  if accepted : List.Pairwise DistinctFileIds files then some ⟨accepted⟩ else none

def checkSourceModules (files : List SourceFile) :
    Option (ProofOf (List.Pairwise DistinctModules files)) :=
  if accepted : List.Pairwise DistinctModules files then some ⟨accepted⟩ else none

theorem pairwiseFileIds_unique {files : List SourceFile}
    (accepted : List.Pairwise DistinctFileIds files) : SourceFileIdsUnique ⟨files⟩ := by
  induction files with
  | nil => simp [SourceFileIdsUnique]
  | cons head tail ih =>
      intro left leftMember right rightMember equalIds
      simp only [List.mem_cons] at leftMember rightMember
      rcases leftMember with rfl | leftMember <;>
        rcases rightMember with rfl | rightMember
      · rfl
      · exact False.elim ((List.pairwise_cons.mp accepted).1 right rightMember equalIds)
      · exact False.elim ((List.pairwise_cons.mp accepted).1 left leftMember equalIds.symm)
      · exact ih (List.pairwise_cons.mp accepted).2 left leftMember right rightMember equalIds

theorem pairwiseModules_unique {files : List SourceFile}
    (accepted : List.Pairwise DistinctModules files) : SourceModulesUnique ⟨files⟩ := by
  induction files with
  | nil => simp [SourceModulesUnique]
  | cons head tail ih =>
      intro left leftMember right rightMember equalModule
      simp only [List.mem_cons] at leftMember rightMember
      rcases leftMember with rfl | leftMember <;>
        rcases rightMember with rfl | rightMember
      · rfl
      · exact False.elim (Or.elim equalModule
          (fun equal => (List.pairwise_cons.mp accepted).1 right rightMember |>.1 equal)
          (fun equal => (List.pairwise_cons.mp accepted).1 right rightMember |>.2 equal))
      · exact False.elim (Or.elim equalModule
          (fun equal => (List.pairwise_cons.mp accepted).1 left leftMember |>.1 equal.symm)
          (fun equal => (List.pairwise_cons.mp accepted).1 left leftMember |>.2 equal.symm))
      · exact ih (List.pairwise_cons.mp accepted).2 left leftMember right rightMember equalModule

def checkSourcePackWellFormed (pack : SourcePack) :
    Option (ProofOf (SourcePackWellFormed pack)) := do
  let files ← checkAllFiles pack.files
  let ids ← checkSourceFileIds pack.files
  let modules ← checkSourceModules pack.files
  pure ⟨⟨files.down, pairwiseFileIds_unique ids.down,
    pairwiseModules_unique modules.down⟩⟩

theorem checkSourcePackWellFormed_evidence {pack : SourcePack}
    {formed : ProofOf (SourcePackWellFormed pack)}
    (_accepted : checkSourcePackWellFormed pack = some formed) :
    SourcePackWellFormed pack := by
  exact formed.down

end Lanius.Declarations
