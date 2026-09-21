import Lanius.Compiler.ProgramLowering
import Lanius.Declarations.Occurrences

namespace Lanius.Compiler.ImportCheck

open Lanius
open Lanius.Declarations

inductive Failure
  | missingOrDuplicate
  | extraImport
deriving DecidableEq, Repr

def importOccurrencesFrom (file : FileId) : Nat → List Surface.Item → List ImportOccurrence
  | _, [] => []
  | index, item :: tail =>
      (match item with
       | .importPath path =>
           [.item { file, index }]
       | .importString _ => [.item { file, index }]
       | _ => []) ++ importOccurrencesFrom file (index + 1) tail

def normalizedImportOccurrences (pack : SourcePack) : List ImportOccurrence :=
  pack.files.flatMap fun file =>
    importOccurrencesFrom file.id 0 file.contents.items

theorem importOccurrencesFrom_mem {items : List Surface.Item} {file : FileId}
    {start index : Nat} {item : Surface.Item} (found : items[index]? = some item)
    (isImport : (∃ path, item = .importPath path) ∨
      ∃ literal, item = .importString literal) :
    .item { file := file, index := start + index } ∈ importOccurrencesFrom file start items := by
  induction items generalizing start index item with
  | nil => simp at found
  | cons head tail ih =>
      cases index with
      | zero =>
          have itemEq : head = item := by simpa using found
          subst item
          rcases isImport with ⟨path, rfl⟩ | ⟨literal, rfl⟩
          · simp [importOccurrencesFrom]
          · simp [importOccurrencesFrom]
      | succ index =>
          have tailFound : tail[index]? = some item := by simpa using found
          have member := ih (start := start + 1) tailFound isImport
          simp only [importOccurrencesFrom, List.mem_append]
          exact Or.inr (by
            simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using member)

theorem importOccurs_mem_normalized {pack : SourcePack} {occurrence : ImportOccurrence}
    (occurs : ImportOccurs pack occurrence) : occurrence ∈ normalizedImportOccurrences pack := by
  have inFile : ∀ {address : ItemAddress} {file : SourceFile} {item : Surface.Item},
      pack.file? address.file = some file → pack.item? address = some item →
      ((∃ path, item = .importPath path) ∨
        ∃ literal, item = .importString literal) →
      .item address ∈ importOccurrencesFrom file.id 0 file.contents.items := by
    intro address file item fileFound itemFound isImport
    have localFound : file.contents.items[address.index]? = some item := by
      simpa [SourcePack.item?, fileFound] using itemFound
    have member := importOccurrencesFrom_mem (file := file.id) (start := 0)
      localFound isImport
    have fileId : address.file = file.id := fileId_of_found_pack fileFound
    have addressEq : address = { file := file.id, index := address.index } := by
      cases address with
      | mk addressFile index => simp_all
    rw [addressEq]
    simpa using member
  cases occurs with
  | path fileFound itemFound =>
      apply List.mem_flatMap.mpr
      exact ⟨_, List.mem_of_find?_eq_some fileFound,
        inFile fileFound itemFound (by exact Or.inl ⟨_, rfl⟩)⟩
  | string fileFound itemFound =>
      apply List.mem_flatMap.mpr
      exact ⟨_, List.mem_of_find?_eq_some fileFound,
        inFile fileFound itemFound (by exact Or.inr ⟨_, rfl⟩)⟩

def expectedImport? (pack : SourcePack) (occurrence : ImportOccurrence) :
    Option CollectedImport :=
  match occurrence with
  | .item address =>
      match pack.file? address.file, pack.item? address with
      | some file, some (.importPath path) =>
          match plainPath? path with
          | none => none
          | some importedPath =>
              match pack.files.find? (fun file => file.moduleInfo.path == importedPath) with
              | none => none
              | some importedFile =>
                  if file.moduleInfo.id == importedFile.moduleInfo.id then none
                  else some {
                    source := occurrence
                    importer := file.moduleInfo.id
                    imported := importedFile.moduleInfo.id }
      | _, _ => none

theorem expectedImport_matches {pack : SourcePack} {occurrence : ImportOccurrence}
    {row : CollectedImport} (found : expectedImport? pack occurrence = some row) :
    ImportMatches pack row := by
  cases occurrence with
  | item address =>
      cases hFile : pack.file? address.file with
      | none => simp [expectedImport?, hFile] at found
      | some file =>
          cases hItem : pack.item? address with
          | none => simp [expectedImport?, hFile, hItem] at found
          | some item =>
              cases item with
              | importPath path =>
                  cases hPlain : plainPath? path with
                  | none => simp [expectedImport?, hFile, hItem, hPlain] at found
                  | some importedPath =>
                      cases hImported : pack.files.find?
                          (fun file => file.moduleInfo.path == importedPath) with
                      | none => simp [expectedImport?, hFile, hItem, hPlain, hImported] at found
                      | some importedFile =>
                          by_cases same : file.moduleInfo.id == importedFile.moduleInfo.id
                          · simp [expectedImport?, hFile, hItem, hPlain, hImported, same] at found
                          · have different : file.moduleInfo.id ≠ importedFile.moduleInfo.id := by
                              intro equal
                              apply same
                              simp [equal]
                            have importedPathEq : importedFile.moduleInfo.path = importedPath :=
                              LawfulBEq.eq_of_beq (List.find?_eq_some_iff_getElem.mp hImported).1
                            have plain : plainPath? path = some importedFile.moduleInfo.path := by
                              simpa [importedPathEq] using hPlain
                            let resolved : CollectedImport :=
                              { source := .item address, importer := file.moduleInfo.id,
                                imported := importedFile.moduleInfo.id }
                            have base : ImportMatches pack resolved :=
                              .path hFile hItem plain
                                (List.mem_of_find?_eq_some hImported) different
                            have rowEq : row = resolved := by
                              have someEq : some resolved = some row := by
                                simpa [resolved, expectedImport?, hFile, hItem, hPlain,
                                  hImported, same] using found
                              exact Option.some.inj someEq |>.symm
                            rw [rowEq]
                            exact base
              | _ => simp [expectedImport?, hFile, hItem] at found

def occurrenceRows (occurrence : ImportOccurrence) (imports : List CollectedImport) :=
  imports.filter fun row => decide (row.source = occurrence)

def occurrenceCheck (pack : SourcePack) (imports : List CollectedImport)
    (occurrence : ImportOccurrence) : Bool :=
  match expectedImport? pack occurrence with
  | none => false
  | some expected => decide (expected ∈ imports ∧ expected.source = occurrence ∧
      (occurrenceRows occurrence imports).length = 1)

def rowCheck (pack : SourcePack) (occurrences : List ImportOccurrence)
    (row : CollectedImport) : Bool :=
  occurrences.any fun occurrence =>
    decide (expectedImport? pack occurrence = some row)

def collectionCheck (pack : SourcePack) (imports : List CollectedImport) : Bool :=
  (normalizedImportOccurrences pack).all (occurrenceCheck pack imports) &&
    imports.all (rowCheck pack (normalizedImportOccurrences pack))

structure Checked (pack : SourcePack) (imports : List CollectedImport) where
  occurrences : List ImportOccurrence
  covers : ImportCollectionCovers pack imports

theorem filter_member_of_source
    {occurrence : ImportOccurrence} {imports : List CollectedImport}
    {row : CollectedImport} (member : row ∈ imports)
    (source : row.source = occurrence) :
    row ∈ occurrenceRows occurrence imports := by
  simp [occurrenceRows, member, source]

theorem filter_singleton
    {α : Type} {predicate : α → Bool} {values : List α} {value : α}
    (lengthOne : (values.filter predicate).length = 1)
    (member : value ∈ values.filter predicate) :
    values.filter predicate = [value] := by
  obtain ⟨only, honly⟩ := List.length_eq_one_iff.mp lengthOne
  have valueEq : value = only := by
    rw [honly] at member
    simpa using member
  simpa [valueEq] using honly

theorem occurrenceCheck_sound
    {pack : SourcePack} {imports : List CollectedImport}
    {occurrence : ImportOccurrence}
    (accepted : occurrenceCheck pack imports occurrence = true) :
    ∃ selected, selected ∈ imports ∧ selected.source = occurrence ∧
      ImportMatches pack selected ∧
      ∀ candidate, candidate ∈ imports → candidate.source = occurrence →
        ImportMatches pack candidate → candidate = selected := by
  unfold occurrenceCheck at accepted
  cases hExpected : expectedImport? pack occurrence with
  | none => simp [hExpected] at accepted
  | some expected =>
    rw [hExpected] at accepted
    have details : expected ∈ imports ∧ expected.source = occurrence ∧
        (occurrenceRows occurrence imports).length = 1 := of_decide_eq_true accepted
    have selectedSource : expected.source = occurrence := details.2.1
    have selectedMember : expected ∈ occurrenceRows occurrence imports :=
      filter_member_of_source details.1 selectedSource
    have singleton := filter_singleton details.2.2 selectedMember
    refine ⟨expected, details.1, selectedSource,
      expectedImport_matches (occurrence := occurrence) (row := expected) hExpected, ?_⟩
    intro candidate candidateMember candidateSource candidateMatches
    have candidateFiltered : candidate ∈ occurrenceRows occurrence imports :=
      filter_member_of_source candidateMember candidateSource
    change candidate ∈ imports.filter (fun row => decide (row.source = occurrence))
      at candidateFiltered
    rw [singleton] at candidateFiltered
    simpa using candidateFiltered

theorem rowCheck_sound
    {pack : SourcePack} {occurrences : List ImportOccurrence}
    {row : CollectedImport} (accepted : rowCheck pack occurrences row = true) :
    ∃ occurrence, occurrence ∈ occurrences ∧
      expectedImport? pack occurrence = some row := by
  rcases List.any_eq_true.mp accepted with ⟨occurrence, member, found⟩
  exact ⟨occurrence, member, of_decide_eq_true found⟩

theorem collectionCheck_sound
    {pack : SourcePack} {imports : List CollectedImport}
    (accepted : collectionCheck pack imports = true) :
    ImportCollectionCovers pack imports := by
  simp only [collectionCheck, Bool.and_eq_true] at accepted
  have occurrenceAccepted := List.all_eq_true.mp accepted.1
  have rowsAccepted := List.all_eq_true.mp accepted.2
  constructor
  · intro occurrence occurrenceFound
    have occurrenceMember := importOccurs_mem_normalized occurrenceFound
    obtain ⟨selected, selectedMember, selectedSource, selectedMatches, unique⟩ :=
      occurrenceCheck_sound (occurrenceAccepted occurrence occurrenceMember)
    exact ⟨selected, selectedMember, selectedSource, selectedMatches, unique⟩
  · intro declaration declarationMember
    obtain ⟨occurrence, occurrenceMember, expected⟩ :=
      rowCheck_sound (rowsAccepted declaration declarationMember)
    exact expectedImport_matches expected

def check (pack : SourcePack) (imports : List CollectedImport) :
    Except Failure (Checked pack imports) :=
  if occurrences : (normalizedImportOccurrences pack).all (occurrenceCheck pack imports) = true then
    if rows : imports.all (rowCheck pack (normalizedImportOccurrences pack)) = true then
      .ok { occurrences := normalizedImportOccurrences pack, covers :=
        collectionCheck_sound (by simp [collectionCheck, occurrences, rows]) }
    else .error .extraImport
  else .error .missingOrDuplicate

end Lanius.Compiler.ImportCheck
