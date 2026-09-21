import Lanius.Declarations.SourceCheck

namespace Lanius.Declarations

open Lanius
open Lanius.Surface

def indexedOccurrences {α : Type} (make : Nat → α → DeclarationOccurrence) :
    Nat → List α → List DeclarationOccurrence
  | _, [] => []
  | index, head :: tail => make index head :: indexedOccurrences make (index + 1) tail

def enumOccurrences (parent : ItemAddress) :=
  indexedOccurrences (α := EnumVariant) (fun index _ => .enumVariant parent index)

def traitOccurrences (parent : ItemAddress) :=
  indexedOccurrences (α := TraitMethod) (fun index _ => .traitMethod parent index)

def implementationOccurrences (parent : ItemAddress) :=
  indexedOccurrences (α := Function) (fun index _ => .implementationMethod parent index)

def itemOccurrences (file : FileId) (index : Nat) : Item → List DeclarationOccurrence
  | .module _ | .importPath _ | .importString _ => []
  | .function _ | .externFunction _ | .constant _ _ _ _ | .typeAlias _ _ _ _ _ |
      .structure _ | .enumeration _ | .trait _ | .implementation _ =>
      [.item { file, index }]

def itemOccurrencesFull (file : FileId) (index : Nat) : Item → List DeclarationOccurrence
  | .enumeration declaration =>
      .item { file, index } :: enumOccurrences { file, index } 0 declaration.variants
  | .trait declaration =>
      .item { file, index } :: traitOccurrences { file, index } 0 declaration.methods
  | .implementation declaration =>
      .item { file, index } :: implementationOccurrences { file, index } 0 declaration.methods
  | item => itemOccurrences file index item

def itemOccurrencesFrom (file : FileId) (index : Nat) : List Item → List DeclarationOccurrence
  | [] => []
  | item :: tail => itemOccurrencesFull file index item ++ itemOccurrencesFrom file (index + 1) tail

def fileOccurrences (file : SourceFile) : List DeclarationOccurrence :=
  itemOccurrencesFrom file.id 0 file.contents.items

def normalizedOccurrences (pack : SourcePack) : List DeclarationOccurrence :=
  pack.files.flatMap fileOccurrences

theorem fileFound_of_mem {files : List SourceFile} {file : SourceFile}
    (unique : SourceFileIdsUnique ⟨files⟩) (member : file ∈ files) :
    (⟨files⟩ : SourcePack).file? file.id = some file := by
  induction files with
  | nil => simp at member
  | cons head tail ih =>
      simp only [SourcePack.file?, List.find?]
      split
      · next h =>
          have same : head.id = file.id := of_decide_eq_true h
          have equal : head = file := unique head (by simp) file member same
          simp [equal]
      · next h =>
          rcases List.mem_cons.mp member with (rfl | member)
          · simp at h
          · have tailUnique : SourceFileIdsUnique ⟨tail⟩ := by
              intro left leftMember right rightMember equal
              exact unique left (by simp [leftMember]) right (by simp [rightMember]) equal
            simpa [SourcePack.file?] using ih tailUnique member

theorem fileId_of_found {files : List SourceFile} {id : FileId} {file : SourceFile}
    (found : (⟨files⟩ : SourcePack).file? id = some file) : id = file.id := by
  induction files with
  | nil => simp [SourcePack.file?] at found
  | cons head tail ih =>
      simp only [SourcePack.file?, List.find?] at found
      split at found
      · next h =>
          have same : head.id = id := of_decide_eq_true h
          have equal : head = file := Option.some.inj found
          subst file
          exact same.symm
      · next h => exact ih found

theorem fileId_of_found_pack {pack : SourcePack} {id : FileId} {file : SourceFile}
    (found : pack.file? id = some file) : id = file.id := by
  cases pack with
  | mk files => exact fileId_of_found found

theorem indexedOccurrences_member {α : Type} {make : Nat → α → DeclarationOccurrence}
    {xs : List α} {start index : Nat} {value : α}
    (found : xs[index]? = some value) :
    make (start + index) value ∈ indexedOccurrences make start xs := by
  induction xs generalizing start index with
  | nil => simp at found
  | cons head tail ih =>
      cases index with
      | zero =>
          simp only [indexedOccurrences, List.mem_cons]
          have equal : head = value := by simpa using found
          subst value
          exact Or.inl rfl
      | succ index =>
          simp only [indexedOccurrences, List.mem_cons]
          have tailFound : tail[index]? = some value := by simpa using found
          have recursive := ih (start := start + 1) (index := index) tailFound
          exact Or.inr (by simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using recursive)

theorem indexedOccurrences_split {α : Type} {make : Nat → α → DeclarationOccurrence}
    {xs : List α} {start : Nat} {occurrence : DeclarationOccurrence}
    (member : occurrence ∈ indexedOccurrences make start xs) :
    ∃ index value, xs[index]? = some value ∧ occurrence = make (start + index) value := by
  induction xs generalizing start occurrence with
  | nil => simp [indexedOccurrences] at member
  | cons head tail ih =>
      simp only [indexedOccurrences, List.mem_cons] at member
      rcases member with rfl | member
      · exact ⟨0, head, by simp, by simp⟩
      · obtain ⟨index, value, found, equal⟩ := ih (start := start + 1) member
        refine ⟨index + 1, value, ?_, ?_⟩
        · simpa using found
        · simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using equal

theorem itemOccurrences_member {items : List Item} {file : FileId} {start index : Nat}
    {item : Item} (found : items[index]? = some item) :
    ∀ occurrence, occurrence ∈ itemOccurrencesFull file (start + index) item →
      occurrence ∈ itemOccurrencesFrom file start items := by
  induction items generalizing start index with
  | nil => simp at found
  | cons head tail ih =>
      cases index with
      | zero =>
          have itemEq : head = item := by simpa using found
          subst item
          intro occurrence member
          simp [itemOccurrencesFrom, itemOccurrencesFull, itemOccurrences] at member ⊢
          exact Or.inl member
      | succ index =>
          have tailFound : tail[index]? = some item := by simpa using found
          intro occurrence member
          simp only [itemOccurrencesFrom, List.mem_append]
          exact Or.inr (ih (start := start + 1) (index := index) tailFound occurrence
            (by simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using member))

theorem itemOccurrencesFrom_split {file : FileId} {start : Nat} {items : List Item}
    {occurrence : DeclarationOccurrence}
    (member : occurrence ∈ itemOccurrencesFrom file start items) :
    ∃ index item, items[index]? = some item ∧
      occurrence ∈ itemOccurrencesFull file (start + index) item := by
  induction items generalizing start occurrence with
  | nil => simp [itemOccurrencesFrom] at member
  | cons head tail ih =>
      simp only [itemOccurrencesFrom, List.mem_append] at member
      rcases member with member | member
      · exact ⟨0, head, by simp, member⟩
      · obtain ⟨index, item, found, inner⟩ := ih (start := start + 1) member
        exact ⟨index + 1, item, by simpa using found,
          by simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using inner⟩

theorem itemOccurrencesFull_occurs {pack : SourcePack} {address : ItemAddress}
    {item : Item} {occurrence : DeclarationOccurrence}
    (fileFound : pack.file? address.file = some file)
    (itemFound : pack.item? address = some item)
    (member : occurrence ∈ itemOccurrencesFull address.file address.index item) :
    Occurs pack occurrence := by
  cases item with
  | module path | importPath path | importString path =>
      simp [itemOccurrencesFull, itemOccurrences] at member
  | function declaration =>
      simp [itemOccurrencesFull, itemOccurrences] at member
      cases member
      exact .function fileFound itemFound
  | externFunction declaration =>
      simp [itemOccurrencesFull, itemOccurrences] at member
      cases member
      exact .externalFunction fileFound itemFound
  | constant name isPublic type value =>
      simp [itemOccurrencesFull, itemOccurrences] at member
      cases member
      exact .constant fileFound itemFound
  | typeAlias name isPublic parameters predicates target =>
      simp [itemOccurrencesFull, itemOccurrences] at member
      cases member
      exact .typeAlias fileFound itemFound
  | «structure» declaration =>
      simp [itemOccurrencesFull, itemOccurrences] at member
      cases member
      exact .structureType fileFound itemFound
  | enumeration declaration =>
      simp only [itemOccurrencesFull, List.mem_cons] at member
      rcases member with rfl | member
      · exact .enumeration fileFound itemFound
      · obtain ⟨index, variant, found, equal⟩ := indexedOccurrences_split member
        cases equal
        exact .enumVariant fileFound itemFound (by simpa using found)
  | trait declaration =>
      simp only [itemOccurrencesFull, List.mem_cons] at member
      rcases member with rfl | member
      · exact .trait fileFound itemFound
      · obtain ⟨index, method, found, equal⟩ := indexedOccurrences_split member
        cases equal
        exact .traitMethod fileFound itemFound (by simpa using found)
  | implementation declaration =>
      simp only [itemOccurrencesFull, List.mem_cons] at member
      rcases member with rfl | member
      · exact .implementation fileFound itemFound
      · obtain ⟨index, method, found, equal⟩ := indexedOccurrences_split member
        cases equal
        exact .implementationMethod fileFound itemFound (by simpa using found)

theorem occurrence_mem_file {pack : SourcePack} {file : SourceFile}
    {address : ItemAddress} {item : Item}
    (fileFound : pack.file? address.file = some file)
    (itemFound : pack.item? address = some item)
    {occurrence : DeclarationOccurrence}
    (member : occurrence ∈ itemOccurrencesFull address.file address.index item) :
    occurrence ∈ fileOccurrences file := by
  have found : file.contents.items[address.index]? = some item := by
    simpa [SourcePack.item?, fileFound] using itemFound
  have addressFile : address.file = file.id := fileId_of_found_pack fileFound
  exact itemOccurrences_member (start := 0) found occurrence
    (by simpa [addressFile] using member)

theorem occurs_mem_normalized {pack : SourcePack} {occurrence : DeclarationOccurrence}
    (occurs : Occurs pack occurrence) : occurrence ∈ normalizedOccurrences pack := by
  have inFile : ∀ {address : ItemAddress} {file : SourceFile} {item : Item},
      pack.file? address.file = some file → pack.item? address = some item →
      occurrence ∈ itemOccurrencesFull address.file address.index item →
      occurrence ∈ normalizedOccurrences pack := by
    intro address file item fileFound itemFound member
    exact List.mem_flatMap.mpr ⟨file, List.mem_of_find?_eq_some fileFound,
      occurrence_mem_file fileFound itemFound member⟩
  cases occurs with
  | function fileFound itemFound =>
      apply inFile fileFound itemFound
      simp [itemOccurrencesFull, itemOccurrences]
  | externalFunction fileFound itemFound =>
      apply inFile fileFound itemFound
      simp [itemOccurrencesFull, itemOccurrences]
  | constant fileFound itemFound =>
      apply inFile fileFound itemFound
      simp [itemOccurrencesFull, itemOccurrences]
  | typeAlias fileFound itemFound =>
      apply inFile fileFound itemFound
      simp [itemOccurrencesFull, itemOccurrences]
  | structureType fileFound itemFound =>
      apply inFile fileFound itemFound
      simp [itemOccurrencesFull, itemOccurrences]
  | enumeration fileFound itemFound =>
      apply inFile fileFound itemFound
      simp [itemOccurrencesFull]
  | trait fileFound itemFound =>
      apply inFile fileFound itemFound
      simp [itemOccurrencesFull]
  | implementation fileFound itemFound =>
      apply inFile fileFound itemFound
      simp [itemOccurrencesFull]
  | @enumVariant file parent declaration index variant fileFound itemFound childFound =>
      cases parent
      apply inFile fileFound itemFound
      simp only [itemOccurrencesFull, List.mem_cons]
      exact Or.inr (by simpa [enumOccurrences] using
        (indexedOccurrences_member (make := fun index _ => .enumVariant _ index)
          (start := 0) childFound))
  | @traitMethod file parent declaration index method fileFound itemFound childFound =>
      cases parent
      apply inFile fileFound itemFound
      simp only [itemOccurrencesFull, List.mem_cons]
      exact Or.inr (by simpa [traitOccurrences] using
        (indexedOccurrences_member (make := fun index _ => .traitMethod _ index)
          (start := 0) childFound))
  | @implementationMethod file parent declaration index method fileFound itemFound childFound =>
      cases parent
      apply inFile fileFound itemFound
      simp only [itemOccurrencesFull, List.mem_cons]
      exact Or.inr
        (by simpa [implementationOccurrences] using
          (indexedOccurrences_member (make := fun index _ => .implementationMethod _ index)
            (start := 0) childFound))

theorem normalized_mem_occurs {pack : SourcePack} {occurrence : DeclarationOccurrence}
    (unique : SourceFileIdsUnique pack)
    (member : occurrence ∈ normalizedOccurrences pack) : Occurs pack occurrence := by
  rcases List.mem_flatMap.mp member with ⟨file, fileMember, member⟩
  have fileFound := fileFound_of_mem unique fileMember
  obtain ⟨index, item, found, inner⟩ := itemOccurrencesFrom_split (start := 0) member
  have itemFound : pack.item? { file := file.id, index := index } = some item := by
    simpa [SourcePack.item?, fileFound] using found
  apply itemOccurrencesFull_occurs fileFound itemFound
  simpa using inner

theorem normalizedOccurrences_exact {pack : SourcePack}
    (wellFormed : SourcePackWellFormed pack) (occurrence : DeclarationOccurrence) :
    Occurs pack occurrence ↔ occurrence ∈ normalizedOccurrences pack :=
  ⟨occurs_mem_normalized, normalized_mem_occurs wellFormed.2.1⟩


end Lanius.Declarations
