import Lanius.Compiler.ProgramLowering

namespace Lanius.Compiler.DeclarationCheck

open Lanius
open Lanius.Declarations
open Lanius.Compiler.ProgramLowering

inductive Failure | catalogHeaderMissing | sourceMismatch | coreMissing | coreShapeMismatch
  | duplicateOccurrence | missingDeclaration | unsupportedAlias
  deriving DecidableEq, Repr

inductive CoreKey where
  | structure (id : TypeId) | enumeration (id : TypeId)
  | constant (id : ConstantId) | function (id : FunctionId)
  deriving DecidableEq, Repr

structure CandidateRow where
  occurrence : Declarations.DeclarationOccurrence
  header : Declarations.DeclarationHeader
  core : CoreKey

def findById (id : Nat) (key : α → Nat) : List α → Option α
  | [] => none | value :: rest => if key value = id then some value else findById id key rest

theorem findById_mem {id : Nat} {key : α → Nat} {values : List α} {value : α}
    (h : findById id key values = some value) : value ∈ values := by
  induction values with
  | nil => simp [findById] at h
  | cons head tail ih => simp only [findById] at h; split at h <;> simp_all

def coreOf? (program : Core.Program) : CoreKey → Option CoreDeclaration
  | .structure id => (findById id (·.id) program.structures).map .structure
  | .enumeration id => (findById id (·.id) program.enumerations).map .enumeration
  | .constant id => (findById id (·.id) program.constants).map .constant
  | .function id => (findById id (·.id) program.functions).map .function

def coreMatches (header : DeclarationHeader) : CoreDeclaration → Bool
  | .structure d => if header.kind = .structureType then d.id == header.declaration else false
  | .enumeration d => if header.kind = .enumeration then d.id == header.declaration else false
  | .constant d => if header.kind = .constant then d.id == header.declaration else false
  | .function d => if header.kind = .function then d.id == header.declaration &&
      (match d.body, d.external with | some _, none => true | _, _ => false)
    else if header.kind = .externalFunction then d.id == header.declaration &&
      (match d.body, d.external with | none, some _ => true | _, _ => false)
    else false

theorem coreOf_member {program : Core.Program} {key : CoreKey} {declaration : CoreDeclaration}
    (h : coreOf? program key = some declaration) : declaration.member program := by
  cases key <;> simp only [coreOf?, Option.map_eq_some_iff] at h
  all_goals rcases h with ⟨found, hfound, rfl⟩
  all_goals simpa [CoreDeclaration.member] using (findById_mem hfound)

theorem functionShape_internal {declaration : Core.Function}
    (h : (match declaration.body, declaration.external with | some _, none => true | _, _ => false) = true) :
    (∃ body, declaration.body = some body) ∧ declaration.external = none := by
  cases body : declaration.body <;> cases external : declaration.external <;> simp_all

theorem functionShape_external {declaration : Core.Function}
    (h : (match declaration.body, declaration.external with | none, some _ => true | _, _ => false) = true) :
    declaration.body = none ∧ (∃ behavior, declaration.external = some behavior) := by
  cases body : declaration.body <;> cases external : declaration.external <;> simp_all

theorem coreMatches_of_true {header : DeclarationHeader} {declaration : CoreDeclaration}
    (h : coreMatches header declaration = true) : declaration.matches header := by
  cases declaration <;> simp only [coreMatches] at h
  all_goals split at h <;> simp_all [CoreDeclaration.matches]
  all_goals first | exact functionShape_internal h.2 | exact functionShape_external h.2.2

theorem headerMatches_occurs {pack : Declarations.SourcePack} {header : DeclarationHeader} :
    HeaderMatches pack header → Occurs pack header.source
  | .function fileFound itemFound => .function fileFound itemFound
  | .externalFunction fileFound itemFound => .externalFunction fileFound itemFound
  | .constant fileFound itemFound => .constant fileFound itemFound
  | .typeAlias fileFound itemFound => .typeAlias fileFound itemFound
  | .structureType fileFound itemFound => .structureType fileFound itemFound
  | .enumeration fileFound itemFound => .enumeration fileFound itemFound
  | .trait fileFound itemFound => .trait fileFound itemFound
  | .implementation fileFound itemFound => .implementation fileFound itemFound
  | .enumVariant fileFound itemFound childFound => .enumVariant fileFound itemFound childFound
  | .traitMethod fileFound itemFound childFound => .traitMethod fileFound itemFound childFound
  | .implementationMethod fileFound itemFound childFound => .implementationMethod fileFound itemFound childFound

def programKeys (program : Core.Program) : List CoreKey :=
  program.structures.map (fun declaration => .structure declaration.id) ++
    program.enumerations.map (fun declaration => .enumeration declaration.id) ++
    program.constants.map (fun declaration => .constant declaration.id) ++
    program.functions.map (fun declaration => .function declaration.id)

def keysCovered (rows : List CoreKey) (keys : List CoreKey) : Bool :=
  keys.all (fun key => decide (key ∈ rows))

def headersCovered (headers : List DeclarationHeader) (candidates : List CandidateRow) : Bool :=
  headers.all (fun header => decide (header ∈ candidates.map CandidateRow.header))

def isRuntimeHeader : DeclarationHeader → Bool
  | { kind := .function, .. } | { kind := .externalFunction, .. } |
    { kind := .constant, .. } | { kind := .structureType, .. } |
    { kind := .enumeration, .. } => true
  | _ => false

def runtimeHeaders (headers : List DeclarationHeader) : List DeclarationHeader :=
  headers.filter isRuntimeHeader

theorem runtimeOccurs_of_itemFound {pack : SourcePack} {address : ItemAddress}
    {item : Surface.Item} (itemFound : pack.item? address = some item)
    (runtime : RuntimeItem item) : Occurs pack (.item address) := by
  have fileFound : ∃ file, pack.file? address.file = some file := by
    change (pack.file? address.file).bind
      (fun file => file.contents.items[address.index]?) = some item at itemFound
    cases fileResult : pack.file? address.file with
    | none => simp [fileResult] at itemFound
    | some file => exact ⟨file, rfl⟩
  obtain ⟨file, fileFound⟩ := fileFound
  cases item with
  | function declaration => exact .function fileFound itemFound
  | externFunction declaration => exact .externalFunction fileFound itemFound
  | constant name isPublic type value => exact .constant fileFound itemFound
  | «structure» declaration => exact .structureType fileFound itemFound
  | enumeration declaration => exact .enumeration fileFound itemFound
  | module path => simp [RuntimeItem] at runtime
  | importPath path => simp [RuntimeItem] at runtime
  | importString path => simp [RuntimeItem] at runtime
  | typeAlias name isPublic parameters predicates target => simp [RuntimeItem] at runtime
  | trait declaration => simp [RuntimeItem] at runtime
  | implementation declaration => simp [RuntimeItem] at runtime

structure CheckedRow (pack : SourcePack) (catalog : Catalog) (program : Core.Program) where
  candidate : CandidateRow
  row : DeclarationLowering pack catalog program
  occurrence : row.occurrence = candidate.occurrence
  header : row.header = candidate.header
  core : coreOf? program candidate.core = some row.core

def checkCandidate (pack : SourcePack) (catalog : Catalog)
    (catalogWellFormed : CatalogWellFormed pack catalog) (program : Core.Program)
    (candidate : CandidateRow) : Except Failure (CheckedRow pack catalog program) :=
  if hHeader : candidate.header ∈ catalog.headers then
    if hSource : candidate.header.source = candidate.occurrence then
      match hCore : coreOf? program candidate.core with
      | none => .error .coreMissing
      | some core => if hShape : coreMatches candidate.header core = true then
          let hm := catalogWellFormed.1.2 candidate.header hHeader
          let occursHeader := headerMatches_occurs hm
          let occurs : Occurs pack candidate.occurrence := by simpa [hSource] using occursHeader
          .ok
            { candidate := candidate
              row :=
                { occurrence := candidate.occurrence
                  header := candidate.header
                  core := core
                  occurs := occurs
                  inCatalog := hHeader
                  source := hSource
                  headerMatches := hm
                  member := coreOf_member hCore
                  identified := coreMatches_of_true hShape }
              occurrence := rfl
              header := rfl
              core := hCore }
        else .error .coreShapeMismatch
    else .error .sourceMismatch
  else .error .catalogHeaderMissing

def checkCandidates (pack : SourcePack) (catalog : Catalog)
    (catalogWellFormed : CatalogWellFormed pack catalog) (program : Core.Program) :
    List CandidateRow → Except Failure (List (CheckedRow pack catalog program))
  | [] => .ok []
  | candidate :: rest => match checkCandidate pack catalog catalogWellFormed program candidate with
    | .error failure => .error failure
    | .ok checked => match checkCandidates pack catalog catalogWellFormed program rest with
      | .error failure => .error failure | .ok tail => .ok (checked :: tail)

theorem headersCovered_sound {headers : List DeclarationHeader}
    {candidates : List CandidateRow} (h : headersCovered headers candidates = true) :
    ∀ header, header ∈ headers →
    ∃ candidate, candidate ∈ candidates ∧ candidate.header = header := by
  intro header hm
  rcases List.mem_map.mp (of_decide_eq_true ((List.all_eq_true.mp h) header hm)) with
    ⟨candidate, candidateMem, candidateHeader⟩
  exact ⟨candidate, candidateMem, candidateHeader⟩

theorem keysCovered_sound {keys rows : List CoreKey}
    (h : keysCovered rows keys = true) : ∀ key, key ∈ keys → key ∈ rows := by
  intro key hm
  exact of_decide_eq_true ((List.all_eq_true.mp h) key hm)

theorem findById_eq_of_mem_nodup
    {id : Nat} {key : α → Nat} {values : List α} {target found : α}
    (unique : (values.map key).Nodup)
    (targetMem : target ∈ values)
    (foundValue : findById id key values = some found)
    (targetKey : key target = id) : found = target := by
  induction values with
  | nil => simp at targetMem
  | cons head tail ih =>
      simp only [findById] at foundValue
      by_cases headMatches : key head = id
      · simp [headMatches] at foundValue
        have foundHead : found = head := foundValue.symm
        by_cases targetHead : target = head
        · simpa [targetHead] using foundHead
        · have targetTail : target ∈ tail := by simpa [targetHead] using targetMem
          have notInTail : key head ∉ tail.map key :=
            (List.nodup_cons.mp unique).1
          have targetInMap : key target ∈ tail.map key :=
            List.mem_map.mpr ⟨target, targetTail, rfl⟩
          have : key head ∈ tail.map key := by simpa [targetKey, headMatches] using targetInMap
          exact False.elim (notInTail this)
      · have targetTail : target ∈ tail := by
          rcases List.mem_cons.mp targetMem with (targetHead | targetTail)
          · exact False.elim (headMatches (by simpa [targetHead] using targetKey))
          · exact targetTail
        simp [headMatches] at foundValue
        exact ih (List.nodup_cons.mp unique).2 targetTail foundValue

theorem coreOf_structure_eq (program : Core.Program) (declaration : Core.StructDecl)
    (unique : (program.structures.map (fun value => value.id)).Nodup) (member : declaration ∈ program.structures)
    {core : CoreDeclaration} (h : coreOf? program (.structure declaration.id) = some core) : core = .structure declaration := by
  simp only [coreOf?, Option.map_eq_some_iff] at h; rcases h with ⟨found, hv, rfl⟩
  simpa [findById_eq_of_mem_nodup unique member hv rfl]

theorem coreOf_enumeration_eq (program : Core.Program) (declaration : Core.EnumDecl)
    (unique : (program.enumerations.map (fun value => value.id)).Nodup)
    (member : declaration ∈ program.enumerations)
    {core : CoreDeclaration}
    (h : coreOf? program (.enumeration declaration.id) = some core) :
    core = .enumeration declaration := by
  simp only [coreOf?, Option.map_eq_some_iff] at h
  rcases h with ⟨found, hv, rfl⟩
  simpa [findById_eq_of_mem_nodup unique member hv rfl]

theorem coreOf_constant_eq (program : Core.Program) (declaration : Core.Constant)
    (unique : (program.constants.map (fun value => value.id)).Nodup) (member : declaration ∈ program.constants)
    {core : CoreDeclaration} (h : coreOf? program (.constant declaration.id) = some core) : core = .constant declaration := by
  simp only [coreOf?, Option.map_eq_some_iff] at h; rcases h with ⟨found, hv, rfl⟩
  simpa [findById_eq_of_mem_nodup unique member hv rfl]

theorem coreOf_function_eq (program : Core.Program) (declaration : Core.Function)
    (unique : (program.functions.map (fun value => value.id)).Nodup) (member : declaration ∈ program.functions)
    {core : CoreDeclaration} (h : coreOf? program (.function declaration.id) = some core) : core = .function declaration := by
  simp only [coreOf?, Option.map_eq_some_iff] at h; rcases h with ⟨found, hv, rfl⟩
  simpa [findById_eq_of_mem_nodup unique member hv rfl]

theorem checked_key_witness {pack : SourcePack} {catalog : Catalog} {program : Core.Program}
    {checks : List (CheckedRow pack catalog program)} {key : CoreKey}
    (h : key ∈ (checks.map CheckedRow.candidate).map CandidateRow.core) : ∃ checked, checked ∈ checks ∧ checked.candidate.core = key := by
  rcases List.mem_map.mp h with ⟨candidate, candidateMem, candidateKey⟩
  rcases List.mem_map.mp candidateMem with ⟨checked, checkedMem, checkedCandidate⟩
  exact ⟨checked, checkedMem, (congrArg CandidateRow.core checkedCandidate).trans candidateKey⟩

abbrev programIdsUnique (program : Core.Program) : Prop :=
  (program.structures.map (fun declaration => declaration.id)).Nodup ∧
    (program.enumerations.map (fun declaration => declaration.id)).Nodup ∧
    (program.constants.map (fun declaration => declaration.id)).Nodup ∧
    (program.functions.map (fun declaration => declaration.id)).Nodup

abbrev CheckedDistinct {pack : SourcePack} {catalog : Catalog} {program : Core.Program} (left right : CheckedRow pack catalog program) : Prop := left.row.occurrence ≠ right.row.occurrence

theorem checked_pairwise_exact
    {pack : SourcePack} {catalog : Catalog} {program : Core.Program}
    {checks : List (CheckedRow pack catalog program)}
    (unique : checks.Pairwise CheckedDistinct) :
    ∀ left, left ∈ checks → ∀ right, right ∈ checks →
      left.row.occurrence = right.row.occurrence →
      left.row.header = right.row.header ∧ left.row.core = right.row.core := by
  induction checks with
  | nil => simp
  | cons head tail ih =>
    rw [List.pairwise_cons] at unique; intro left lm right rm eq
    rcases List.mem_cons.mp lm with (rfl | lm)
    · rcases List.mem_cons.mp rm with (rfl | rm)
      · exact ⟨rfl, rfl⟩
      · exact False.elim ((unique.1 _ rm) eq)
    · rcases List.mem_cons.mp rm with (rh | rm)
      · exact False.elim ((unique.1 _ lm) (by simpa [rh] using eq.symm))
      · exact ih unique.2 left lm right rm eq

theorem source_coverage
    {pack : SourcePack} {catalog : Catalog} {program : Core.Program}
    (catalogWellFormed : CatalogWellFormed pack catalog)
    {checks : List (CheckedRow pack catalog program)}
    (accepted : headersCovered (runtimeHeaders catalog.headers)
      (checks.map CheckedRow.candidate) = true) :
    ∀ occurrence, RuntimeOccurrence pack occurrence →
      ∃ checked, checked ∈ checks ∧ checked.row.occurrence = occurrence := by
  intro occurrence occurrenceFound
  obtain ⟨address, item, occurrenceEq, itemFound, runtime⟩ := occurrenceFound
  subst occurrence
  have occurs : Occurs pack (.item address) :=
    runtimeOccurs_of_itemFound itemFound runtime
  obtain ⟨selected, selectedMem, selectedSource, selectedMatches, _⟩ :=
    catalogWellFormed.1.1 (.item address) occurs
  have selectedRuntime : isRuntimeHeader selected = true := by
    cases item <;> simp [RuntimeItem] at runtime <;>
      cases selectedMatches <;> simp_all [isRuntimeHeader]
  have selectedRuntimeMember : selected ∈ runtimeHeaders catalog.headers := by
    simp [runtimeHeaders, selectedMem, selectedRuntime]
  obtain ⟨candidate, candidateMem, candidateHeader⟩ :=
    headersCovered_sound accepted selected selectedRuntimeMember
  rcases List.mem_map.mp candidateMem with ⟨checked, checkedMem, checkedCandidate⟩; refine ⟨checked, checkedMem, ?_⟩
  calc
    checked.row.occurrence = checked.row.header.source := checked.row.source.symm
    _ = checked.candidate.header.source := congrArg DeclarationHeader.source checked.header
    _ = candidate.header.source := congrArg (fun value : CandidateRow => value.header.source) checkedCandidate
    _ = selected.source := congrArg DeclarationHeader.source candidateHeader
    _ = .item address := selectedSource

theorem program_coverage
    {pack : SourcePack} {catalog : Catalog} {program : Core.Program}
    (programUnique : programIdsUnique program)
    {checks : List (CheckedRow pack catalog program)}
    (keys : keysCovered ((checks.map CheckedRow.candidate).map CandidateRow.core) (programKeys program) = true) :
    (∀ declaration, declaration ∈ program.structures → ∃ checked, checked ∈ checks ∧ checked.row.core = .structure declaration) ∧
    (∀ declaration, declaration ∈ program.enumerations → ∃ checked, checked ∈ checks ∧ checked.row.core = .enumeration declaration) ∧
    (∀ declaration, declaration ∈ program.constants → ∃ checked, checked ∈ checks ∧ checked.row.core = .constant declaration) ∧
    (∀ declaration, declaration ∈ program.functions → ∃ checked, checked ∈ checks ∧ checked.row.core = .function declaration) := by
  have keysMem := keysCovered_sound keys
  have structuresUnique := programUnique.1
  have enumerationsUnique := programUnique.2.1
  have constantsUnique := programUnique.2.2.1
  have functionsUnique := programUnique.2.2.2
  constructor
  · intro declaration declarationMem
    have km : CoreKey.structure declaration.id ∈ programKeys program := by
      simp only [programKeys, List.mem_append, List.mem_map]
      exact Or.inl (Or.inl (Or.inl ⟨declaration, declarationMem, rfl⟩))
    obtain ⟨checked, cm, ck⟩ := checked_key_witness (keysMem _ km); have hc := checked.core; rw [ck] at hc
    exact ⟨checked, cm, coreOf_structure_eq program declaration structuresUnique declarationMem hc⟩
  constructor
  · intro declaration declarationMem
    have km : CoreKey.enumeration declaration.id ∈ programKeys program := by
      simp only [programKeys, List.mem_append, List.mem_map]
      exact Or.inl (Or.inl (Or.inr ⟨declaration, declarationMem, rfl⟩))
    obtain ⟨checked, cm, ck⟩ := checked_key_witness (keysMem _ km)
    have hc := checked.core
    rw [ck] at hc
    exact ⟨checked, cm,
      coreOf_enumeration_eq program declaration enumerationsUnique declarationMem hc⟩
  constructor
  · intro declaration declarationMem
    have km : CoreKey.constant declaration.id ∈ programKeys program := by
      simp only [programKeys, List.mem_append, List.mem_map]
      exact Or.inl (Or.inr ⟨declaration, declarationMem, rfl⟩)
    obtain ⟨checked, cm, ck⟩ := checked_key_witness (keysMem _ km); have hc := checked.core; rw [ck] at hc
    exact ⟨checked, cm, coreOf_constant_eq program declaration constantsUnique declarationMem hc⟩
  · intro declaration declarationMem
    have km : CoreKey.function declaration.id ∈ programKeys program := by
      simp only [programKeys, List.mem_append, List.mem_map]
      exact Or.inr ⟨declaration, declarationMem, rfl⟩
    obtain ⟨checked, cm, ck⟩ := checked_key_witness (keysMem _ km); have hc := checked.core; rw [ck] at hc
    exact ⟨checked, cm, coreOf_function_eq program declaration functionsUnique declarationMem hc⟩

theorem rows_pairwise_exact
    {pack : SourcePack} {catalog : Catalog} {program : Core.Program}
    {checks : List (CheckedRow pack catalog program)}
    (unique : checks.Pairwise CheckedDistinct) :
    ∀ left ∈ checks.map CheckedRow.row, ∀ right ∈ checks.map CheckedRow.row,
      left.occurrence = right.occurrence → left.header = right.header ∧ left.core = right.core := by
  intro left leftMem right rightMem occurrence
  rcases List.mem_map.mp leftMem with ⟨leftChecked, leftCheckedMem, rfl⟩
  rcases List.mem_map.mp rightMem with ⟨rightChecked, rightCheckedMem, rfl⟩
  exact checked_pairwise_exact unique leftChecked leftCheckedMem
    rightChecked rightCheckedMem occurrence

theorem exact_of_checks
    {pack : SourcePack} {catalog : Catalog} {program : Core.Program}
    {checks : List (CheckedRow pack catalog program)}
    (source : ∀ occurrence, RuntimeOccurrence pack occurrence →
      ∃ checked, checked ∈ checks ∧ checked.row.occurrence = occurrence)
    (coverage : (∀ declaration, declaration ∈ program.structures → ∃ checked, checked ∈ checks ∧ checked.row.core = .structure declaration) ∧
      (∀ declaration, declaration ∈ program.enumerations → ∃ checked, checked ∈ checks ∧ checked.row.core = .enumeration declaration) ∧
      (∀ declaration, declaration ∈ program.constants → ∃ checked, checked ∈ checks ∧ checked.row.core = .constant declaration) ∧
      (∀ declaration, declaration ∈ program.functions → ∃ checked, checked ∈ checks ∧ checked.row.core = .function declaration))
    (unique : checks.Pairwise CheckedDistinct) :
    DeclarationLoweringsExact pack catalog program (checks.map CheckedRow.row) := by
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_⟩
  · intro occurrence occurs; obtain ⟨checked, checkedMem, eq⟩ := source occurrence occurs
    exact ⟨checked.row, List.mem_map.mpr ⟨checked, checkedMem, rfl⟩, eq⟩
  · intro declaration declarationMem; obtain ⟨checked, checkedMem, eq⟩ := coverage.1 declaration declarationMem
    exact ⟨checked.row, List.mem_map.mpr ⟨checked, checkedMem, rfl⟩, eq⟩
  · intro declaration declarationMem; obtain ⟨checked, checkedMem, eq⟩ := coverage.2.1 declaration declarationMem
    exact ⟨checked.row, List.mem_map.mpr ⟨checked, checkedMem, rfl⟩, eq⟩
  · intro declaration declarationMem; obtain ⟨checked, checkedMem, eq⟩ := coverage.2.2.1 declaration declarationMem
    exact ⟨checked.row, List.mem_map.mpr ⟨checked, checkedMem, rfl⟩, eq⟩
  · intro declaration declarationMem; obtain ⟨checked, checkedMem, eq⟩ := coverage.2.2.2 declaration declarationMem
    exact ⟨checked.row, List.mem_map.mpr ⟨checked, checkedMem, rfl⟩, eq⟩
  · exact rows_pairwise_exact unique

def checkAliasHeader (pack : SourcePack) (catalog : Catalog)
    (catalogWellFormed : CatalogWellFormed pack catalog)
    (header : DeclarationHeader) (headerMember : header ∈ catalog.headers)
    (headerKind : header.kind = .typeAlias) :
    Except Failure { alias : TypeAliasLowering pack catalog // alias.header = header } :=
  match hSource : header.source with
  | .item address =>
      match hfile : pack.file? address.file with
      | none => .error .unsupportedAlias
      | some file =>
          match hitem : pack.item? address with
          | some (.typeAlias name isPublic parameters predicates target) =>
              if monomorphic : parameters = [] ∧ predicates = [] then
                let occurs : Occurs pack header.source := by
                  simpa [hSource] using (.typeAlias hfile hitem)
                let headerMatches := catalogWellFormed.1.2 header headerMember
                .ok ⟨{
                    occurrence := header.source
                    header := header
                    address := address
                    name := name
                    isPublic := isPublic
                    parameters := parameters
                    predicates := predicates
                    target := target
                    occurs := occurs
                    inCatalog := headerMember
                    headerMatches := headerMatches
                    headerKind := headerKind
                    source := hSource
                    occurrenceSource := rfl
                    headerSource := rfl
                    sourceFound := hitem
                    monomorphic := monomorphic }, rfl⟩
              else .error .unsupportedAlias
          | _ => .error .unsupportedAlias
  | _ => .error .unsupportedAlias

def checkAliases (pack : SourcePack) (catalog : Catalog)
    (catalogWellFormed : CatalogWellFormed pack catalog)
    (headers : List DeclarationHeader)
    (headersMember : ∀ header, header ∈ headers → header ∈ catalog.headers) :
    Except Failure (List (TypeAliasLowering pack catalog)) := match headers with
  | [] => .ok []
  | header :: tail =>
      if hKind : header.kind = .typeAlias then
        match checkAliasHeader pack catalog catalogWellFormed header
            (headersMember header (by simp)) hKind with
        | .error failure => .error failure
        | .ok checkedAlias =>
            match checkAliases pack catalog catalogWellFormed tail
                (fun value member => headersMember value (by simp [member])) with
            | .error failure => .error failure
            | .ok aliases => .ok (checkedAlias.1 :: aliases)
      else
        checkAliases pack catalog catalogWellFormed tail
          (fun value member => headersMember value (by simp [member]))

theorem checkAliases_header_source_aux
    {pack : SourcePack} {catalog : Catalog}
    (catalogWellFormed : CatalogWellFormed pack catalog)
    {headers : List DeclarationHeader}
    {aliases : List (TypeAliasLowering pack catalog)}
    (headersMember : ∀ header, header ∈ headers → header ∈ catalog.headers)
    (accepted : checkAliases pack catalog catalogWellFormed headers headersMember = .ok aliases) :
    ∀ header, header ∈ headers → header.kind = .typeAlias →
      ∃ row ∈ aliases, row.occurrence = header.source := by
  induction headers generalizing aliases with
  | nil =>
      intro header member kind
      simp at member
  | cons head tail ih =>
      intro header headerMember headerKind
      rcases List.mem_cons.mp headerMember with (headMember | headerMember)
      · subst header
        cases checked : checkAliasHeader pack catalog catalogWellFormed head
            (headersMember head (by simp)) headerKind with
        | error failure => simp [checkAliases, headerKind, checked] at accepted
        | ok checkedAlias =>
            cases tailResult : checkAliases pack catalog catalogWellFormed tail
                (fun value member => headersMember value (by simp [member])) with
            | error failure =>
                simp [checkAliases, headerKind, checked, tailResult] at accepted
            | ok tailAliases =>
                have aliasesEq : checkedAlias.1 :: tailAliases = aliases := by
                  simpa [checkAliases, headerKind, checked, tailResult] using accepted
                cases aliasesEq
                exact ⟨checkedAlias.1, List.mem_cons_self,
                  checkedAlias.1.occurrenceSource.trans
                    (congrArg DeclarationHeader.source checkedAlias.2)⟩
      · cases headKind : head.kind with
        | typeAlias =>
            cases checked : checkAliasHeader pack catalog catalogWellFormed head
                (headersMember head (by simp)) headKind with
            | error failure => simp [checkAliases, headKind, checked] at accepted
            | ok _checkedAlias =>
                cases tailResult : checkAliases pack catalog catalogWellFormed tail
                    (fun value member => headersMember value (by simp [member])) with
                | error failure =>
                    simp [checkAliases, headKind, checked, tailResult] at accepted
                | ok tailAliases =>
                    have aliasesEq : _checkedAlias.1 :: tailAliases = aliases := by
                      simpa [checkAliases, headKind, checked, tailResult] using accepted
                    cases aliasesEq
                    obtain ⟨row, rowMember, rowOccurrence⟩ := ih
                      (headersMember := fun value member =>
                        headersMember value (by simp [member]))
                      (aliases := tailAliases) tailResult header headerMember headerKind
                    exact ⟨row, List.mem_cons_of_mem _ rowMember, rowOccurrence⟩
        | _ =>
            have tailAccepted :
                checkAliases pack catalog catalogWellFormed tail
                    (fun value member => headersMember value (by simp [member])) = .ok aliases := by
              simpa [checkAliases, headKind] using accepted
            exact ih
              (headersMember := fun value member => headersMember value (by simp [member]))
              tailAccepted header headerMember headerKind

theorem checkAliases_source_coverage
    {pack : SourcePack} {catalog : Catalog}
    (catalogWellFormed : CatalogWellFormed pack catalog)
    {aliases : List (TypeAliasLowering pack catalog)}
    (accepted : checkAliases pack catalog catalogWellFormed catalog.headers
        (fun header member => member) = .ok aliases) :
    ∀ occurrence, AliasOccurrence pack occurrence →
      ∃ row ∈ aliases, row.occurrence = occurrence := by
  have headerCoverage := checkAliases_header_source_aux catalogWellFormed
    (headersMember := fun header member => member) accepted
  intro occurrence occurrenceFound
  obtain ⟨address, name, isPublic, parameters, predicates, target,
    occurrenceEq, itemFound, parametersEmpty, predicatesEmpty⟩ := occurrenceFound
  subst occurrence
  have occurs : Occurs pack (.item address) := by
    have fileFound : ∃ file, pack.file? address.file = some file := by
      change (pack.file? address.file).bind
        (fun file => file.contents.items[address.index]?) =
        some (.typeAlias name isPublic parameters predicates target) at itemFound
      cases fileResult : pack.file? address.file with
      | none => simp [fileResult] at itemFound
      | some file => exact ⟨file, rfl⟩
    obtain ⟨file, fileFound⟩ := fileFound
    exact .typeAlias fileFound itemFound
  obtain ⟨selected, selectedMember, selectedSource, selectedMatches, _⟩ :=
    catalogWellFormed.1.1 (.item address) occurs
  have selectedKind : selected.kind = .typeAlias := by
    cases selectedMatches <;> simp_all
  obtain ⟨row, rowMember, rowOccurrence⟩ :=
    headerCoverage selected selectedMember selectedKind
  refine ⟨row, rowMember, ?_⟩
  calc
    row.occurrence = selected.source := rowOccurrence
    _ = .item address := selectedSource

structure CheckedDeclarations
    (pack : SourcePack) (catalog : Catalog) (program : Core.Program) where
  rows : List (DeclarationLowering pack catalog program)
  exact : DeclarationLoweringsExact pack catalog program rows
  aliases : List (TypeAliasLowering pack catalog)
  aliasesExact : TypeAliasLoweringsExact pack catalog aliases
  structuresIdsUnique : (program.structures.map (fun declaration => declaration.id)).Nodup
  enumerationsIdsUnique : (program.enumerations.map (fun declaration => declaration.id)).Nodup
  constantsIdsUnique : (program.constants.map (fun declaration => declaration.id)).Nodup
  functionsIdsUnique : (program.functions.map (fun declaration => declaration.id)).Nodup

def checkDeclarations
    (pack : SourcePack) (catalog : Catalog)
    (catalogWellFormed : CatalogWellFormed pack catalog)
    (program : Core.Program) (candidates : List CandidateRow) :
  Except Failure (CheckedDeclarations pack catalog program) :=
  match aliasesAccepted : checkAliases pack catalog catalogWellFormed catalog.headers
      (fun header member => member) with
  | .error failure => .error failure
  | .ok aliases =>
    match checkCandidates pack catalog catalogWellFormed program candidates with
    | .error failure => .error failure
    | .ok checks =>
      if hUnique : checks.Pairwise (fun left right => left.row.occurrence ≠ right.row.occurrence) then
          let candidateRows := checks.map CheckedRow.candidate
          if hHeaders : headersCovered (runtimeHeaders catalog.headers) candidateRows = true then
            if hKeys : keysCovered (candidateRows.map CandidateRow.core) (programKeys program) = true then
              if hProgramUnique : programIdsUnique program then
                let sourceEvidence := source_coverage catalogWellFormed hHeaders
                let aliasExact : TypeAliasLoweringsExact pack catalog aliases :=
                  by
                    refine ⟨?_, ?_⟩
                    · intro occurrence occurrenceFound
                      exact checkAliases_source_coverage catalogWellFormed aliasesAccepted
                        occurrence occurrenceFound
                    · intro row rowMember
                      exact ⟨row.inCatalog, row.headerKind, row.occurrenceSource.symm,
                        row.monomorphic⟩
                let programEvidence := program_coverage (programUnique := hProgramUnique) hKeys
                .ok
                  { rows := checks.map CheckedRow.row
                    exact := exact_of_checks sourceEvidence programEvidence hUnique
                    aliases := aliases
                    aliasesExact := aliasExact
                    structuresIdsUnique := hProgramUnique.1
                    enumerationsIdsUnique := hProgramUnique.2.1
                    constantsIdsUnique := hProgramUnique.2.2.1
                    functionsIdsUnique := hProgramUnique.2.2.2 }
              else .error .missingDeclaration
            else .error .missingDeclaration
          else .error .missingDeclaration
      else .error .duplicateOccurrence
