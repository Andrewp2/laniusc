import Lanius.Examples

namespace Lanius.WholeProgramWitnesses

open Lanius
open Lanius.Core
open Lanius.Examples

theorem singletonGetSome
    (found : [value][index]? = some selected) :
    index = 0 ∧ selected = value := by
  cases index with
  | zero =>
      simp at found
      exact ⟨rfl, found.symm⟩
  | succ index => simp at found

theorem checkedMainItemFound
    (found : checkedMainPack.item? address = some item) :
    address = { file := 0, index := 0 } ∧
      item = .function checkedMainSurface := by
  rcases address with ⟨file, index⟩
  simp only [Declarations.SourcePack.item?, checkedMainPack,
    Declarations.SourcePack.file?, List.find?_cons,
    checkedMainFile] at found
  cases sameFile : (0 == file) with
  | false => simp [sameFile] at found
  | true =>
    have fileEquality : 0 = file := beq_iff_eq.mp sameFile
    subst file
    simp at found
    obtain ⟨rfl, rfl⟩ := singletonGetSome found
    exact ⟨rfl, rfl⟩

theorem checkedMainOccursOnly
    (occurs : Declarations.Occurs checkedMainPack occurrence) :
    occurrence = .item { file := 0, index := 0 } := by
  cases occurs with
  | function fileFound itemFound =>
      obtain ⟨rfl, itemEquality⟩ := checkedMainItemFound itemFound
      cases itemEquality
      rfl
  | externalFunction fileFound itemFound =>
      obtain ⟨rfl, itemEquality⟩ := checkedMainItemFound itemFound
      cases itemEquality
  | constant fileFound itemFound =>
      obtain ⟨rfl, itemEquality⟩ := checkedMainItemFound itemFound
      cases itemEquality
  | typeAlias fileFound itemFound =>
      obtain ⟨rfl, itemEquality⟩ := checkedMainItemFound itemFound
      cases itemEquality
  | structureType fileFound itemFound =>
      obtain ⟨rfl, itemEquality⟩ := checkedMainItemFound itemFound
      cases itemEquality
  | enumeration fileFound itemFound =>
      obtain ⟨rfl, itemEquality⟩ := checkedMainItemFound itemFound
      cases itemEquality
  | trait fileFound itemFound =>
      obtain ⟨rfl, itemEquality⟩ := checkedMainItemFound itemFound
      cases itemEquality
  | implementation fileFound itemFound =>
      obtain ⟨rfl, itemEquality⟩ := checkedMainItemFound itemFound
      cases itemEquality
  | enumVariant fileFound itemFound childFound =>
      obtain ⟨rfl, itemEquality⟩ := checkedMainItemFound itemFound
      cases itemEquality
  | traitMethod fileFound itemFound childFound =>
      obtain ⟨rfl, itemEquality⟩ := checkedMainItemFound itemFound
      cases itemEquality
  | implementationMethod fileFound itemFound childFound =>
      obtain ⟨rfl, itemEquality⟩ := checkedMainItemFound itemFound
      cases itemEquality

theorem checkedMainSourcePackWellFormed :
    Declarations.SourcePackWellFormed checkedMainPack := by
  refine ⟨?_, ?_, ?_⟩
  · intro file member
    simp only [checkedMainPack, List.mem_singleton] at member
    subst file
    refine ⟨?_, by simp [checkedMainFile, appModule], ?_, ?_⟩
    · intro item itemMember
      simp only [checkedMainFile, List.mem_singleton] at itemMember
      subst item
      apply SurfaceSyntax.ItemWellFormed.function
      exact ⟨.nil, .nil, .none, .nil,
        .cons (.returnValue (.some .literal)) .nil⟩
    · intro index item found isModule
      obtain ⟨rfl, rfl⟩ := singletonGetSome found
      rcases isModule with ⟨path, impossible⟩
      cases impossible
    · intro importIndex importItem importFound isImport
      obtain ⟨rfl, rfl⟩ := singletonGetSome importFound
      rcases isImport with ⟨⟨path, impossible⟩⟩ | ⟨literal, impossible⟩ <;>
        cases impossible
  · intro left leftMember right rightMember sameId
    simp only [checkedMainPack, List.mem_singleton] at leftMember rightMember
    subst left
    subst right
    rfl
  · intro left leftMember right rightMember sameModule
    simp only [checkedMainPack, List.mem_singleton] at leftMember rightMember
    subst left
    subst right
    rfl

theorem checkedMainCatalogWellFormed :
    Declarations.CatalogWellFormed checkedMainPack checkedMainCatalog := by
  refine ⟨⟨?_, ?_⟩, ?_, ?_⟩
  · intro occurrence occurs
    rw [checkedMainOccursOnly occurs]
    exact ⟨checkedMainHeader, by simp [checkedMainCatalog], rfl,
      checkedMainHeaderMatches, by
        intro candidate member source matched
        simp only [checkedMainCatalog, List.mem_singleton] at member
        subst candidate
        rfl⟩
  · intro header member
    simp only [checkedMainCatalog, List.mem_singleton] at member
    subst header
    exact checkedMainHeaderMatches
  · intro left leftMember right rightMember sameDeclaration
    simp only [checkedMainCatalog, List.mem_singleton] at leftMember rightMember
    subst left
    subst right
    rfl
  · intro left leftMember right rightMember sameSource
    simp only [checkedMainCatalog, List.mem_singleton] at leftMember rightMember
    subst left
    subst right
    rfl

theorem checkedMainImportCollection :
    Declarations.ImportCollectionCovers checkedMainPack [] := by
  constructor
  · intro occurrence occurs
    cases occurs with
    | path fileFound itemFound =>
        obtain ⟨rfl, itemEquality⟩ := checkedMainItemFound itemFound
        cases itemEquality
    | string fileFound itemFound =>
        obtain ⟨rfl, itemEquality⟩ := checkedMainItemFound itemFound
        cases itemEquality
  · intro declaration member
    simp at member

theorem checkedMainDeclarationCollection :
    ProgramElaboration.DeclarationCollectionComplete checkedMainPack
      checkedMainCatalog checkedMainContext := by
  refine {
    functions := ?_
    externalFunctions := ?_
    functionSchemes := ?_
    typeAliases := ?_
    typeAliasEntries := ?_
    nominals := ?_
    nominalSchemes := ?_
    structConstructorHeaders := ?_
    structConstructorSchemes := ?_
    variantConstructorHeaders := ?_
    variantConstructorSchemes := ?_
    traits := ?_
    traitSchemes := ?_
    traitMethodHeaders := ?_
    traitMethodContracts := ?_
    implementations := ?_
    implementationSchemes := ?_
    implementationMethodHeaders := ?_
    inherentMethodSchemes := ?_
  }
  · intro header member kind
    simp only [checkedMainCatalog, List.mem_singleton] at member
    subst header
    exact ⟨checkedMainScheme, checkedMainBodyContext,
      checkedMainSchemeCollected⟩
  · intro header member kind
    simp only [checkedMainCatalog, List.mem_singleton] at member
    subst header
    simp [checkedMainHeader] at kind
  · intro scheme member
    simp only [checkedMainContext, List.mem_singleton] at member
    subst scheme
    exact ⟨checkedMainHeader, checkedMainBodyContext,
      by simp [checkedMainCatalog], .inl checkedMainSchemeCollected⟩
  · intro header member kind
    simp only [checkedMainCatalog, List.mem_singleton] at member
    subst header
    simp [checkedMainHeader] at kind
  · intro entry member
    simp [checkedMainContext] at member
  · intro header member kind
    simp only [checkedMainCatalog, List.mem_singleton] at member
    subst header
    simp [checkedMainHeader] at kind
  · intro scheme member
    simp [checkedMainContext] at member
  · intro header member kind
    simp only [checkedMainCatalog, List.mem_singleton] at member
    subst header
    simp [checkedMainHeader] at kind
  · intro constructor member
    simp [checkedMainContext] at member
  · intro header member kind
    simp only [checkedMainCatalog, List.mem_singleton] at member
    subst header
    simp [checkedMainHeader] at kind
  · intro constructor member
    simp [checkedMainContext] at member
  · intro header member kind
    simp only [checkedMainCatalog, List.mem_singleton] at member
    subst header
    simp [checkedMainHeader] at kind
  · intro scheme member
    simp [checkedMainContext] at member
  · intro header member kind
    simp only [checkedMainCatalog, List.mem_singleton] at member
    subst header
    simp [checkedMainHeader] at kind
  · intro contract member
    simp [checkedMainContext] at member
  · intro header member kind
    simp only [checkedMainCatalog, List.mem_singleton] at member
    subst header
    simp [checkedMainHeader] at kind
  · intro scheme member
    simp [checkedMainContext] at member
  · intro header member kind
    simp only [checkedMainCatalog, List.mem_singleton] at member
    subst header
    simp [checkedMainHeader] at kind
  · intro scheme member
    simp [checkedMainContext] at member

theorem checkedMainMetadataUnique :
    ProgramElaboration.DeclarationMetadataUnique checkedMainContext := by
  refine {
    functions := ?_
    methods := ?_
    traits := ?_
    traitMethods := ?_
    implementations := ?_
    implementationIds := ?_
    constants := ?_
    typeAliases := ?_
    nominalSchemes := ?_
    structConstructors := ?_
    structConstructorSourceTypes := ?_
    variantConstructors := ?_
  } <;> simp [ProgramElaboration.RowsUniqueByKey, checkedMainContext]

theorem checkedMainArtifactsComplete :
    ProgramElaboration.MonomorphicArtifactsComplete checkedMainPack
      checkedMainCatalog checkedMainProgram checkedMainContext [] := by
  refine {
    nominalInstancesUnique := ?_
    functionInstanceIdsUnique := ?_
    functionSpecializationsUnique := ?_
    methodInstanceIdsUnique := ?_
    methodSpecializationsUnique := ?_
    methodLookupCoherent := ?_
    traitImplementationMethodInstanceIdsUnique := ?_
    nominalInstancesMapped := ?_
    nominalInstancesLower := ?_
    functionInstancesLower := ?_
    inherentMethodInstancesLower := ?_
    traitImplementationMethodInstancesLower := ?_
    structuresCovered := ?_
    enumerationsCovered := ?_
    functionsCovered := ?_
    constantsLower := ?_
  }
  · simp [Static.NominalInstancesUnique, checkedMainContext]
  · simp [ProgramElaboration.RowsUniqueByKey, checkedMainContext]
  · simp [ProgramElaboration.RowsUniqueByKey, checkedMainContext]
  · simp [ProgramElaboration.RowsUniqueByKey, checkedMainContext]
  · simp [ProgramElaboration.RowsUniqueByKey, checkedMainContext]
  · simp [Static.MethodLookupCoherent, checkedMainContext]
  · simp [ProgramElaboration.RowsUniqueByKey, checkedMainContext]
  · intro resolved member
    simp [checkedMainContext] at member
  · intro resolved member
    simp [checkedMainContext] at member
  · intro resolved member
    simp only [checkedMainContext, List.mem_singleton] at member
    subst resolved
    exact ⟨checkedMainHeader, checkedMainScheme, checkedMainCore,
      by simp [checkedMainCatalog], by simp [checkedMainContext],
      .inl checkedMainCollectedLowers⟩
  · intro resolved member
    simp [checkedMainContext] at member
  · intro resolved member
    simp [checkedMainContext] at member
  · intro core member
    simp [checkedMainProgram] at member
  · intro core member
    simp [checkedMainProgram] at member
  · intro core member
    simp only [checkedMainProgram, List.mem_singleton] at member
    subst core
    exact .inl ⟨checkedMainHeader, checkedMainScheme, checkedMainInstance,
      checkedMainCollectedLowers⟩
  · refine ⟨[], ?_, ?_⟩
    · simp [ProgramElaboration.ConstantHeaderOrderCovers,
        checkedMainCatalog, checkedMainHeader]
    · exact .nil rfl

theorem checkedMainLayouts : Layout.ProgramHasLayouts checkedMainProgram := by
  refine ⟨?_, ?_, ?_, ?_⟩
  · intro declaration member
    simp [checkedMainProgram] at member
  · intro declaration member
    simp [checkedMainProgram] at member
  · intro constant member
    simp [checkedMainProgram] at member
  · intro function member
    simp only [checkedMainProgram, List.mem_singleton] at member
    subst function
    constructor
    · intro parameter parameterMember
      simp [checkedMainCore] at parameterMember
    · exact ⟨Layout.scalarLayout checkedMainProgram.target (.signed .i32),
        .scalar⟩

/-- A real source declaration passes through collection, symbolic checking,
    monomorphization, core lowering, static typing, layout, and whole-program
    execution under one complete-program witness. -/
theorem checkedMainComplete :
    ProgramElaboration.CompleteProgramElaboration checkedMainPack
      checkedMainCatalog [] checkedMainProgram checkedMainContext [] := by
  refine {
    sourcePack := checkedMainSourcePackWellFormed
    declarationCatalog := checkedMainCatalogWellFormed
    importCollection := checkedMainImportCollection
    importOrder := ?_
    names := rfl
    target := rfl
    declarations := checkedMainDeclarationCollection
    metadataUnique := checkedMainMetadataUnique
    implementationsCoherent := ?_
    artifacts := checkedMainArtifactsComplete
    coreIds := ?_
    typed := checkedMainProgramWellTyped
    layouts := checkedMainLayouts
  }
  · refine ⟨[0], ?_⟩
    simp [Declarations.ModuleDependencyOrderCovers, checkedMainPack,
      checkedMainFile, appModule]
  · change Static.ImplementationsCoherent []
    intro goal left right leftApplies _rightApplies
    cases leftApplies with
    | intro member _ _ _ _ _ _ => simp at member
  · simp [ProgramElaboration.CoreProgramIdsUnique, checkedMainProgram]

end Lanius.WholeProgramWitnesses
