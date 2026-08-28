import Lanius.Extraction.CoreTypingChecker
import Lanius.ProgramElaboration
import Lanius.SurfaceElaboration

namespace Lanius.Extraction.SurfaceElaborationChecker

open Lanius
open Lanius.Core
open Lanius.SurfaceElaboration

abbrev Evidence := CoreTyping.Evidence

/-! ## Proof-producing local elaboration checks

The untrusted exporter may suggest rules and intermediate types, but these
functions do not trust those suggestions.  They inspect reconstructed Surface
syntax and proposed Core syntax together and return derivations of the
authoritative `SurfaceElaboration` relations.

This file deliberately starts below whole-program declaration collection.  A
later artifact checker will construct the verified global context and invoke
this kernel for function bodies.  Keeping that boundary explicit prevents a
wire `CoreTy` from being mistaken for a source `Static.GroundTy`: nominal
source identities and generic arguments survive here until the context's
monomorphization is proved to map them to Core.
-/

def defaultGroundType : Surface.Literal → Static.GroundTy
  | .integer _ => .scalar (.signed .i32)
  | .float _ => .scalar .f32
  | .boolean _ => .scalar .bool
  | .character _ => .scalar .char
  | .string _ => .scalar .string

theorem defaultGroundType_toCore
    (monomorphization : Static.Monomorphization) (literal : Surface.Literal) :
    (defaultGroundType literal).toCore monomorphization =
      some (Elaboration.literalDefaultType literal) := by
  cases literal <;> rfl

def literalElaborates? (target : Target) :
    (literal : Surface.Literal) → (type : Ty) → (core : Expr) →
      Option (Evidence (Elaboration.LiteralElaborates target literal type core))
  | .boolean expected, .scalar .bool, .value (.boolean actual) =>
      if same : actual = expected then
        some ⟨same ▸ Elaboration.LiteralElaborates.boolean⟩
      else none
  | .character expected, .scalar .char, .value (.character actual) =>
      if same : actual = UInt32.ofNat expected.toNat then
        some ⟨same ▸ Elaboration.LiteralElaborates.character⟩
      else none
  | .string expected, .scalar .string, .value (.string actual) =>
      if same : actual = expected then
        some ⟨same ▸ Elaboration.LiteralElaborates.string⟩
      else none
  | .integer text, .scalar (.signed expectedType),
      .value (.signed actualType actualValue) =>
      if sameType : actualType = expectedType then
        match parsed : Elaboration.parseUnsignedInteger text with
        | none => none
        | some magnitude =>
            if sameValue : actualValue = Int.ofNat magnitude then
              if upper : Int.ofNat magnitude ≤ Typing.signedMax target expectedType then
                some ⟨by
                  subst actualType
                  subst actualValue
                  exact .signedInteger parsed upper⟩
              else none
            else none
      else none
  | .integer text, .scalar (.unsigned expectedType),
      .value (.unsigned actualType actualValue) =>
      if sameType : actualType = expectedType then
        match parsed : Elaboration.parseUnsignedInteger text with
        | none => none
        | some magnitude =>
            if sameValue : actualValue = magnitude then
              if upper : magnitude ≤ Typing.unsignedMax target expectedType then
                some ⟨by
                  subst actualType
                  subst actualValue
                  exact .unsignedInteger parsed upper⟩
              else none
            else none
      else none
  | .integer text, .scalar .rawPtr, .value (.pointer actual) =>
      match parsed : Elaboration.parseUnsignedInteger text with
      | some 0 =>
          if same : actual = 0 then
            some ⟨same ▸ Elaboration.LiteralElaborates.nullPointer parsed⟩
          else none
      | _ => none
  | .float text, .scalar .f32, .value (.f32Bits actual) =>
      match parsed : Elaboration.parseFloatLiteral text with
      | none => none
      | some value =>
          if same : actual = value.toFloat32.toBits then
            some ⟨same ▸ Elaboration.LiteralElaborates.f32 parsed⟩
          else none
  | .float text, .scalar .f64, .value (.f64Bits actual) =>
      match parsed : Elaboration.parseFloatLiteral text with
      | none => none
      | some value =>
          if same : actual = value.toBits then
            some ⟨same ▸ Elaboration.LiteralElaborates.f64 parsed⟩
          else none
  | _, _, _ => none

structure ResolvedLocal (locals : List LocalBinding) (name : Surface.Name) where
  binding : LocalBinding
  resolved : ResolvesLocal locals name binding

def resolveLocal? :
    (locals : List LocalBinding) → (name : Surface.Name) →
      Option (ResolvedLocal locals name)
  | [], _ => none
  | binding :: outer, name =>
      if same : binding.name = name then
        some ⟨binding, same ▸ ResolvesLocal.head⟩
      else do
        let tail ← resolveLocal? outer name
        pure ⟨tail.binding, .tail same tail.resolved⟩

def symbolPairCompatible (left right : Names.Symbol) : Bool :=
  if sameKey : left.moduleId = right.moduleId ∧
      left.lookupNamespace = right.lookupNamespace ∧ left.name = right.name then
    decide (left.declaration = right.declaration)
  else true

theorem symbolPairCompatible_sound {left right : Names.Symbol}
    (accepted : symbolPairCompatible left right = true)
    (sameModule : left.moduleId = right.moduleId)
    (sameNamespace : left.lookupNamespace = right.lookupNamespace)
    (sameName : left.name = right.name) :
    left.declaration = right.declaration := by
  unfold symbolPairCompatible at accepted
  split at accepted
  · simpa using accepted
  · rename_i incompatible
    exact False.elim (incompatible ⟨sameModule, sameNamespace, sameName⟩)

def symbolCompatibleWithAll (symbol : Names.Symbol) : List Names.Symbol → Bool
  | [] => true
  | head :: tail =>
      symbolPairCompatible symbol head && symbolCompatibleWithAll symbol tail

theorem symbolCompatibleWithAll_sound {symbol : Names.Symbol}
    {symbols : List Names.Symbol}
    (accepted : symbolCompatibleWithAll symbol symbols = true) :
    ∀ candidate, candidate ∈ symbols →
      symbol.moduleId = candidate.moduleId →
      symbol.lookupNamespace = candidate.lookupNamespace →
      symbol.name = candidate.name →
      symbol.declaration = candidate.declaration := by
  intro candidate member
  induction symbols with
  | nil => simp at member
  | cons head tail induction =>
      simp only [symbolCompatibleWithAll, Bool.and_eq_true] at accepted
      simp only [List.mem_cons] at member
      rcases accepted with ⟨headAccepted, tailAccepted⟩
      rcases member with rfl | member
      · exact symbolPairCompatible_sound headAccepted
      · exact induction tailAccepted member

def symbolsUniqueBool : List Names.Symbol → Bool
  | [] => true
  | head :: tail =>
      symbolCompatibleWithAll head (head :: tail) && symbolsUniqueBool tail

theorem symbolsUniqueBool_sound {symbols : List Names.Symbol}
    (accepted : symbolsUniqueBool symbols = true) :
    ∀ left, left ∈ symbols →
      ∀ right, right ∈ symbols →
        left.moduleId = right.moduleId →
        left.lookupNamespace = right.lookupNamespace →
        left.name = right.name → left.declaration = right.declaration := by
  intro left leftMember
  induction symbols with
  | nil => simp at leftMember
  | cons head tail induction =>
      simp only [symbolsUniqueBool, Bool.and_eq_true] at accepted
      rcases accepted with ⟨headAccepted, tailAccepted⟩
      simp only [List.mem_cons] at leftMember
      rcases leftMember with rfl | leftMember
      · intro right rightMember
        exact symbolCompatibleWithAll_sound headAccepted right rightMember
      · intro right rightMember
        simp only [List.mem_cons] at rightMember
        rcases rightMember with rfl | rightMember
        · intro sameModule sameNamespace sameName
          exact (symbolCompatibleWithAll_sound headAccepted left
            (by simp [leftMember]) sameModule.symm sameNamespace.symm
            sameName.symm).symm
        · exact induction tailAccepted leftMember right rightMember

def symbolsUnique? (environment : Names.Environment) :
    Option (Evidence (Names.SymbolsAreUnique environment)) :=
  if accepted : symbolsUniqueBool environment.symbols = true then
    some ⟨symbolsUniqueBool_sound accepted⟩
  else none

structure LocalGlobalSymbol
    (environment : Names.Environment) (moduleId : ModuleId)
    (lookupNamespace : Names.LookupNamespace) (name : Surface.Name) where
  symbol : Names.Symbol
  member : symbol ∈ environment.symbols
  sameModule : symbol.moduleId = moduleId
  sameNamespace : symbol.lookupNamespace = lookupNamespace
  sameName : symbol.name = name

def findLocalGlobalSymbol? (environment : Names.Environment)
    (moduleId : ModuleId) (lookupNamespace : Names.LookupNamespace)
    (name : Surface.Name) :
    Option (LocalGlobalSymbol environment moduleId lookupNamespace name) :=
  let rec visit : (remaining : List Names.Symbol) →
      (∀ symbol, symbol ∈ remaining → symbol ∈ environment.symbols) →
      Option (LocalGlobalSymbol environment moduleId lookupNamespace name)
    | [], _ => none
    | head :: tail, subset =>
        if sameModule : head.moduleId = moduleId then
          if sameNamespace : head.lookupNamespace = lookupNamespace then
            if sameName : head.name = name then
              some ⟨head, subset head (by simp), sameModule,
                sameNamespace, sameName⟩
            else visit tail (fun symbol member => subset symbol (by simp [member]))
          else visit tail (fun symbol member => subset symbol (by simp [member]))
        else visit tail (fun symbol member => subset symbol (by simp [member]))
  visit environment.symbols (fun _ member => member)

theorem referenceFromSurfacePath_unqualified
    (lookupNamespace : Names.LookupNamespace)
    (unqualified : unqualifiedPathName? path = some name) :
    Names.Reference.fromSurfacePath? lookupNamespace path =
      some (.unqualified lookupNamespace name) := by
  cases path with
  | mk segments =>
      cases segments with
      | nil => simp [unqualifiedPathName?] at unqualified
      | cons head tail =>
          cases tail with
          | nil =>
              cases head with
              | mk segmentName arguments =>
                  simp [unqualifiedPathName?] at unqualified
                  subst segmentName
                  rfl
          | cons second rest => simp [unqualifiedPathName?] at unqualified

structure ResolvedLocalGlobal
    (context : Context) (lookupNamespace : Names.LookupNamespace)
    (path : Surface.Path) where
  symbol : Names.Symbol
  resolved : ResolvesGlobal context lookupNamespace path symbol

def resolveSameModuleGlobal? (context : Context)
    (lookupNamespace : Names.LookupNamespace) (path : Surface.Path) :
    Option (ResolvedLocalGlobal context lookupNamespace path) :=
  match unqualified : unqualifiedPathName? path with
  | none => none
  | some name => do
      let selected ← findLocalGlobalSymbol? context.names context.currentModule
        lookupNamespace name
      let unique ← symbolsUnique? context.names
      let formed := referenceFromSurfacePath_unqualified lookupNamespace unqualified
      let namesResolved : Names.Resolves context.names context.currentModule
          (.unqualified lookupNamespace name) selected.symbol := by
        constructor
        · exact .local selected.member selected.sameModule
            selected.sameNamespace selected.sameName
        · intro candidate candidateProof
          cases candidateProof with
          | «local» member sameModule sameNamespace sameName =>
              constructor
              · exact sameNamespace.trans selected.sameNamespace.symm
              · exact unique.proof candidate member selected.symbol selected.member
                  (sameModule.trans selected.sameModule.symm)
                  (sameNamespace.trans selected.sameNamespace.symm)
                  (sameName.trans selected.sameName.symm)
          | importedUnqualified module found imported noLocal member symbolModule
              isPublic sameNamespace sameName =>
              exact (noLocal ⟨selected.symbol, selected.member,
                selected.sameModule, selected.sameNamespace, selected.sameName⟩).elim
      pure ⟨selected.symbol,
        .intro (.unqualified lookupNamespace name) formed namesResolved⟩

def importsModuleBool
    (environment : Names.Environment) (importer imported : ModuleId) : Bool :=
  environment.imports.any fun declaration =>
    decide (declaration.importer = importer) &&
      decide (declaration.imported = imported)

theorem importsModuleBool_sound
    (accepted : importsModuleBool environment importer imported = true) :
    environment.importsModule importer imported := by
  rcases List.any_eq_true.mp accepted with ⟨declaration, member, matchProof⟩
  simp only [Bool.and_eq_true, decide_eq_true_eq] at matchProof
  exact ⟨declaration, member, matchProof.1, matchProof.2⟩

theorem importsModuleBool_complete
    (importedProof : environment.importsModule importer imported) :
    importsModuleBool environment importer imported = true := by
  rcases importedProof with ⟨declaration, member, sameImporter, sameImported⟩
  apply List.any_eq_true.mpr
  exact ⟨declaration, member, by
    simp [sameImporter, sameImported]⟩

structure FoundModuleById
    (environment : Names.Environment) (moduleId : ModuleId) where
  module : Names.Module
  member : module ∈ environment.modules
  sameId : module.id = moduleId

def findModuleById? (environment : Names.Environment) (moduleId : ModuleId) :
    Option (FoundModuleById environment moduleId) :=
  let rec visit : (remaining : List Names.Module) →
      (∀ module, module ∈ remaining → module ∈ environment.modules) →
      Option (FoundModuleById environment moduleId)
    | [], _ => none
    | head :: tail, subset =>
        if same : head.id = moduleId then
          some ⟨head, subset head (by simp), same⟩
        else
          visit tail (fun module member => subset module (by simp [member]))
  visit environment.modules (fun _ member => member)

structure FoundModuleByPath
    (environment : Names.Environment) (path : Names.ModulePath) where
  module : Names.Module
  member : module ∈ environment.modules
  samePath : module.path = path

def findModuleByPath? (environment : Names.Environment)
    (path : Names.ModulePath) : Option (FoundModuleByPath environment path) :=
  let rec visit : (remaining : List Names.Module) →
      (∀ module, module ∈ remaining → module ∈ environment.modules) →
      Option (FoundModuleByPath environment path)
    | [], _ => none
    | head :: tail, subset =>
        if same : head.path = path then
          some ⟨head, subset head (by simp), same⟩
        else
          visit tail (fun module member => subset module (by simp [member]))
  visit environment.modules (fun _ member => member)

def modulePairCompatible (left right : Names.Module) : Bool :=
  if samePath : left.path = right.path then decide (left.id = right.id) else true

theorem modulePairCompatible_sound {left right : Names.Module}
    (accepted : modulePairCompatible left right = true)
    (samePath : left.path = right.path) : left.id = right.id := by
  unfold modulePairCompatible at accepted
  split at accepted
  · simpa using accepted
  · rename_i different
    exact False.elim (different samePath)

def moduleCompatibleWithAll (module : Names.Module) : List Names.Module → Bool
  | [] => true
  | head :: tail =>
      modulePairCompatible module head && moduleCompatibleWithAll module tail

theorem moduleCompatibleWithAll_sound {module : Names.Module}
    {modules : List Names.Module}
    (accepted : moduleCompatibleWithAll module modules = true) :
    ∀ candidate, candidate ∈ modules → module.path = candidate.path →
      module.id = candidate.id := by
  intro candidate member
  induction modules with
  | nil => simp at member
  | cons head tail induction =>
      simp only [moduleCompatibleWithAll, Bool.and_eq_true] at accepted
      rcases accepted with ⟨headAccepted, tailAccepted⟩
      simp only [List.mem_cons] at member
      rcases member with rfl | member
      · exact modulePairCompatible_sound headAccepted
      · exact induction tailAccepted member

def modulesUniquePathsBool : List Names.Module → Bool
  | [] => true
  | head :: tail =>
      moduleCompatibleWithAll head (head :: tail) && modulesUniquePathsBool tail

theorem modulesUniquePathsBool_sound {modules : List Names.Module}
    (accepted : modulesUniquePathsBool modules = true) :
    ∀ left, left ∈ modules → ∀ right, right ∈ modules →
      left.path = right.path → left.id = right.id := by
  intro left leftMember
  induction modules with
  | nil => simp at leftMember
  | cons head tail induction =>
      simp only [modulesUniquePathsBool, Bool.and_eq_true] at accepted
      rcases accepted with ⟨headAccepted, tailAccepted⟩
      simp only [List.mem_cons] at leftMember
      rcases leftMember with rfl | leftMember
      · intro right rightMember
        exact moduleCompatibleWithAll_sound headAccepted right rightMember
      · intro right rightMember
        simp only [List.mem_cons] at rightMember
        rcases rightMember with rfl | rightMember
        · intro samePath
          exact (moduleCompatibleWithAll_sound headAccepted left
            (by simp [leftMember]) samePath.symm).symm
        · exact induction tailAccepted leftMember right rightMember

def modulesUniquePaths? (environment : Names.Environment) :
    Option (Evidence (Names.ModulesHaveUniquePaths environment)) :=
  if accepted : modulesUniquePathsBool environment.modules = true then
    some ⟨modulesUniquePathsBool_sound accepted⟩
  else none

def noLocalGlobalSymbol? (environment : Names.Environment)
    (moduleId : ModuleId) (lookupNamespace : Names.LookupNamespace)
    (name : Surface.Name) :
    Option (Evidence
      (¬ Names.HasLocalDeclaration environment moduleId lookupNamespace name)) :=
  let rec visit : (remaining : List Names.Symbol) →
      (∀ symbol, symbol ∈ remaining → symbol ∈ environment.symbols) →
      Option (Evidence
        (¬ ∃ symbol ∈ remaining,
          symbol.moduleId = moduleId ∧
          symbol.lookupNamespace = lookupNamespace ∧ symbol.name = name))
    | [], _ => some ⟨by simp⟩
    | head :: tail, subset =>
        if differentModule : head.moduleId ≠ moduleId then do
          let rest ← visit tail
            (fun symbol member => subset symbol (by simp [member]))
          pure ⟨by
            rintro ⟨symbol, member, sameModule, sameNamespace, sameName⟩
            simp only [List.mem_cons] at member
            rcases member with rfl | member
            · exact differentModule sameModule
            · exact rest.proof ⟨symbol, member, sameModule, sameNamespace, sameName⟩⟩
        else if differentNamespace : head.lookupNamespace ≠ lookupNamespace then do
          let rest ← visit tail
            (fun symbol member => subset symbol (by simp [member]))
          pure ⟨by
            rintro ⟨symbol, member, sameModule, sameNamespace, sameName⟩
            simp only [List.mem_cons] at member
            rcases member with rfl | member
            · exact differentNamespace sameNamespace
            · exact rest.proof ⟨symbol, member, sameModule, sameNamespace, sameName⟩⟩
        else if differentName : head.name ≠ name then do
          let rest ← visit tail
            (fun symbol member => subset symbol (by simp [member]))
          pure ⟨by
            rintro ⟨symbol, member, sameModule, sameNamespace, sameName⟩
            simp only [List.mem_cons] at member
            rcases member with rfl | member
            · exact differentName sameName
            · exact rest.proof ⟨symbol, member, sameModule, sameNamespace, sameName⟩⟩
        else none
  match visit environment.symbols (fun _ member => member) with
  | none => none
  | some absent => some ⟨by
      intro localProof
      exact absent.proof localProof⟩

def importedSymbolMatchesBool (environment : Names.Environment)
    (current : ModuleId) (lookupNamespace : Names.LookupNamespace)
    (name : Surface.Name) (symbol : Names.Symbol) : Bool :=
  decide (symbol.lookupNamespace = lookupNamespace) &&
    decide (symbol.name = name) &&
    decide (symbol.visibility = .exported) &&
    importsModuleBool environment current symbol.moduleId

theorem importedSymbolMatchesBool_of_candidate
    (candidate : Names.Candidate environment current
      (.unqualified lookupNamespace name) symbol)
    (noLocal : ¬ Names.HasLocalDeclaration environment current
      lookupNamespace name) :
    importedSymbolMatchesBool environment current lookupNamespace name symbol = true := by
  cases candidate with
  | «local» member sameModule sameNamespace sameName =>
      exact (noLocal ⟨symbol, member, sameModule, sameNamespace, sameName⟩).elim
  | importedUnqualified module found imported _ member symbolModule isPublic
      sameNamespace sameName =>
      simp [importedSymbolMatchesBool, sameNamespace, sameName, isPublic,
        importsModuleBool_complete (symbolModule ▸ imported)]

def importedDeclarationsAgreeBool (environment : Names.Environment)
    (current : ModuleId) (lookupNamespace : Names.LookupNamespace)
    (name : Surface.Name) (selected : Names.Symbol) : Bool :=
  environment.symbols.all fun candidate =>
    if importedSymbolMatchesBool environment current lookupNamespace name candidate
    then decide (candidate.declaration = selected.declaration)
    else true

theorem importedDeclarationsAgreeBool_sound
    (accepted : importedDeclarationsAgreeBool environment current
      lookupNamespace name selected = true)
    (noLocal : ¬ Names.HasLocalDeclaration environment current
      lookupNamespace name)
    (selectedProof : Names.Candidate environment current
      (.unqualified lookupNamespace name) selected) :
    ∀ candidate, Names.Candidate environment current
      (.unqualified lookupNamespace name) candidate →
      candidate.lookupNamespace = selected.lookupNamespace ∧
        candidate.declaration = selected.declaration := by
  intro candidate candidateProof
  have member : candidate ∈ environment.symbols := by
    cases candidateProof with
    | «local» member _ _ _ => exact member
    | importedUnqualified _ _ _ _ member _ _ _ _ => exact member
  have matchProof := importedSymbolMatchesBool_of_candidate candidateProof noLocal
  have row := List.all_eq_true.mp accepted candidate member
  simp [importedDeclarationsAgreeBool, matchProof] at row
  have sameNamespace : candidate.lookupNamespace = lookupNamespace := by
    cases candidateProof with
    | «local» _ _ same _ => exact same
    | importedUnqualified _ _ _ _ _ _ _ same _ => exact same
  have selectedNamespace : selected.lookupNamespace = lookupNamespace := by
    cases selectedProof with
    | «local» _ _ same _ => exact same
    | importedUnqualified _ _ _ _ _ _ _ same _ => exact same
  exact ⟨sameNamespace.trans selectedNamespace.symm, row⟩

structure ImportedUnqualifiedSymbol
    (environment : Names.Environment) (current : ModuleId)
    (lookupNamespace : Names.LookupNamespace) (name : Surface.Name)
    (noLocal : ¬ Names.HasLocalDeclaration environment current
      lookupNamespace name) where
  symbol : Names.Symbol
  candidate : Names.Candidate environment current
    (.unqualified lookupNamespace name) symbol

def findImportedUnqualifiedSymbol? (environment : Names.Environment)
    (current : ModuleId) (lookupNamespace : Names.LookupNamespace)
    (name : Surface.Name)
    (noLocal : ¬ Names.HasLocalDeclaration environment current
      lookupNamespace name) :
    Option (ImportedUnqualifiedSymbol environment current lookupNamespace name noLocal) :=
  let rec visit : (remaining : List Names.Symbol) →
      (∀ symbol, symbol ∈ remaining → symbol ∈ environment.symbols) →
      Option (ImportedUnqualifiedSymbol environment current lookupNamespace name noLocal)
    | [], _ => none
    | head :: tail, subset =>
        if sameNamespace : head.lookupNamespace = lookupNamespace then
          if sameName : head.name = name then
            if isPublic : head.visibility = .exported then
              if imported : importsModuleBool environment current head.moduleId = true then
                match findModuleById? environment head.moduleId with
                | some found => some ⟨head, .importedUnqualified found.module
                    found.member (by
                      simpa [found.sameId] using importsModuleBool_sound imported) noLocal
                    (subset head (by simp)) found.sameId.symm isPublic
                    sameNamespace sameName⟩
                | none => visit tail
                    (fun symbol member => subset symbol (by simp [member]))
              else visit tail
                (fun symbol member => subset symbol (by simp [member]))
            else visit tail
              (fun symbol member => subset symbol (by simp [member]))
          else visit tail (fun symbol member => subset symbol (by simp [member]))
        else visit tail (fun symbol member => subset symbol (by simp [member]))
  visit environment.symbols (fun _ member => member)

def resolveGlobal? (context : Context)
    (lookupNamespace : Names.LookupNamespace) (path : Surface.Path) :
    Option (ResolvedLocalGlobal context lookupNamespace path) :=
  match formed : Names.Reference.fromSurfacePath? lookupNamespace path with
  | none => none
  | some (.unqualified referenceNamespace name) =>
      match localFound : findLocalGlobalSymbol? context.names context.currentModule
        referenceNamespace name with
      | some selected => do
          let unique ← symbolsUnique? context.names
          let namesResolved : Names.Resolves context.names context.currentModule
              (.unqualified referenceNamespace name) selected.symbol := by
            constructor
            · exact .local selected.member selected.sameModule
                selected.sameNamespace selected.sameName
            · intro candidate candidateProof
              cases candidateProof with
              | «local» member sameModule sameNamespace sameName =>
                  exact ⟨sameNamespace.trans selected.sameNamespace.symm,
                    unique.proof candidate member selected.symbol selected.member
                      (sameModule.trans selected.sameModule.symm)
                      (sameNamespace.trans selected.sameNamespace.symm)
                      (sameName.trans selected.sameName.symm)⟩
              | importedUnqualified module found imported noLocal member symbolModule
                  isPublic sameNamespace sameName =>
                  exact (noLocal ⟨selected.symbol, selected.member,
                    selected.sameModule, selected.sameNamespace,
                    selected.sameName⟩).elim
          pure ⟨selected.symbol, .intro _ formed namesResolved⟩
      | none => do
          let noLocal ← noLocalGlobalSymbol? context.names context.currentModule
            referenceNamespace name
          let selected ← findImportedUnqualifiedSymbol? context.names
            context.currentModule referenceNamespace name noLocal.proof
          if agrees : importedDeclarationsAgreeBool context.names context.currentModule
              referenceNamespace name selected.symbol = true then
            let namesResolved : Names.Resolves context.names context.currentModule
                (.unqualified referenceNamespace name) selected.symbol := by
              constructor
              · exact selected.candidate
              · exact importedDeclarationsAgreeBool_sound agrees noLocal.proof
                  selected.candidate
            pure ⟨selected.symbol, .intro _ formed namesResolved⟩
          else none
  | some (.qualified referenceNamespace modulePath name) => do
      let selectedModule ← findModuleByPath? context.names modulePath
      let modulesUnique ← modulesUniquePaths? context.names
      let selected ← findLocalGlobalSymbol? context.names selectedModule.module.id
        referenceNamespace name
      let symbolsUnique ← symbolsUnique? context.names
      let candidateEvidence : Evidence
          (Names.Candidate context.names context.currentModule
            (.qualified referenceNamespace modulePath name) selected.symbol) ←
        if own : selectedModule.module.id = context.currentModule then
          some ⟨Names.Candidate.ownQualified selectedModule.module
            selectedModule.member selectedModule.samePath own selected.member
            selected.sameModule selected.sameNamespace selected.sameName⟩
        else do
          if isPublicProof : selected.symbol.visibility = .exported then
            if imported : importsModuleBool context.names context.currentModule
                selectedModule.module.id = true then
              some ⟨Names.Candidate.importedQualified selectedModule.module
                selectedModule.member selectedModule.samePath
                (importsModuleBool_sound imported) selected.member
                selected.sameModule isPublicProof selected.sameNamespace selected.sameName⟩
            else none
          else none
      let namesResolved : Names.Resolves context.names context.currentModule
          (.qualified referenceNamespace modulePath name) selected.symbol := by
        constructor
        · exact candidateEvidence.proof
        · intro other otherCandidate
          cases otherCandidate with
          | ownQualified module foundModule samePath isCurrent member symbolModule
              sameNamespace sameName =>
              have sameModuleId : module.id = selectedModule.module.id :=
                modulesUnique.proof module foundModule selectedModule.module
                  selectedModule.member (samePath.trans selectedModule.samePath.symm)
              exact ⟨sameNamespace.trans selected.sameNamespace.symm,
                symbolsUnique.proof other member selected.symbol selected.member
                  (symbolModule.trans (sameModuleId.trans selected.sameModule.symm))
                  (sameNamespace.trans selected.sameNamespace.symm)
                  (sameName.trans selected.sameName.symm)⟩
          | importedQualified module foundModule samePath imported member symbolModule
              isPublicProof sameNamespace sameName =>
              have sameModuleId : module.id = selectedModule.module.id :=
                modulesUnique.proof module foundModule selectedModule.module
                  selectedModule.member (samePath.trans selectedModule.samePath.symm)
              exact ⟨sameNamespace.trans selected.sameNamespace.symm,
                symbolsUnique.proof other member selected.symbol selected.member
                  (symbolModule.trans (sameModuleId.trans selected.sameModule.symm))
                  (sameNamespace.trans selected.sameNamespace.symm)
                  (sameName.trans selected.sameName.symm)⟩
      pure ⟨selected.symbol, .intro _ formed namesResolved⟩

def noLocalNamed? (context : Context) (name : Surface.Name) :
    Option (Evidence (NoLocalNamed context.locals name)) :=
  let rec visit : (locals : List LocalBinding) →
      Option (Evidence (NoLocalNamed locals name))
    | [] => some ⟨by simp [NoLocalNamed]⟩
    | head :: tail => do
        if different : head.name ≠ name then
          let rest ← visit tail
          pure ⟨by
            intro binding member
            simp only [List.mem_cons] at member
            rcases member with rfl | member
            · exact different
            · exact rest.proof binding member⟩
        else none
  visit context.locals

def globalPathNotShadowed? (context : Context) (path : Surface.Path) :
    Option (Evidence (GlobalPathNotShadowed context path)) :=
  match unqualified : unqualifiedPathName? path with
  | none => some ⟨by simp [GlobalPathNotShadowed, unqualified]⟩
  | some name => do
      let absent ← noLocalNamed? context name
      pure ⟨by simpa [GlobalPathNotShadowed, unqualified] using absent.proof⟩

structure GroundedType (context : Context) (surface : Surface.TypeExpr) where
  type : Static.GroundTy
  grounded : TypeGrounds context surface type

theorem builtinTypePath_none_of_single
    (single : singleNamePath? path = some name)
    (absent : Elaboration.builtinScalar? name = none) :
    Elaboration.builtinTypePath? path = none := by
  cases path with
  | mk segments =>
      cases segments with
      | nil => simp [singleNamePath?] at single
      | cons head tail =>
          cases tail with
          | nil =>
              cases head with
              | mk segmentName arguments =>
                  cases arguments with
                  | nil =>
                      simp [singleNamePath?] at single
                      subst segmentName
                      simpa [Elaboration.builtinTypePath?] using absent
                  | cons argument arguments =>
                      simp [singleNamePath?] at single
          | cons second rest => simp [singleNamePath?] at single

def noTypeParameterNamed? (bindings : List TypeParameterBinding)
    (name : Surface.Name) :
    Option (Evidence (∀ binding, ¬ ResolvesTypeParameter bindings name binding)) :=
  let rec visit : (remaining : List TypeParameterBinding) →
      Option (Evidence (∀ binding,
        ¬ ResolvesTypeParameter remaining name binding))
    | [] => some ⟨by intro binding resolved; cases resolved⟩
    | head :: tail => do
        if different : head.name ≠ name then
          let rest ← visit tail
          pure ⟨by
            intro binding resolved
            cases resolved with
            | head => exact different rfl
            | tail _ resolved => exact rest.proof binding resolved⟩
        else none
  visit bindings

def globalTypePathNotShadowed? (context : Context) (path : Surface.Path) :
    Option (Evidence (GlobalTypePathNotShadowed context path)) :=
  match single : singleNamePath? path with
  | none => some ⟨by
      intro name binding found
      rw [single] at found
      contradiction⟩
  | some name => do
      let absent ← noTypeParameterNamed? context.typeParameters name
      pure ⟨by
        intro candidate binding found
        have same : candidate = name := Option.some.inj (found.symm.trans single)
        subst candidate
        exact absent.proof binding⟩

structure FoundNominalScheme (context : Context) (declaration : Nat) where
  scheme : Static.NominalScheme
  member : scheme ∈ context.nominalSchemes
  sameDeclaration : scheme.declaration = declaration

def findNominalScheme? (context : Context) (declaration : Nat) :
    Option (FoundNominalScheme context declaration) :=
  let rec visit : (remaining : List Static.NominalScheme) →
      (∀ scheme, scheme ∈ remaining → scheme ∈ context.nominalSchemes) →
      Option (FoundNominalScheme context declaration)
    | [], _ => none
    | head :: tail, subset =>
        if same : head.declaration = declaration then
          some ⟨head, subset head (by simp), same⟩
        else visit tail (fun scheme member => subset scheme (by simp [member]))
  visit context.nominalSchemes (fun _ member => member)

structure FoundTypeAlias (context : Context) (declaration : Nat) where
  entry : TypeAliasEntry
  member : entry ∈ context.typeAliases
  sameDeclaration : entry.declaration = declaration

def findTypeAlias? (context : Context) (declaration : Nat) :
    Option (FoundTypeAlias context declaration) :=
  let rec visit : (remaining : List TypeAliasEntry) →
      (∀ entry, entry ∈ remaining → entry ∈ context.typeAliases) →
      Option (FoundTypeAlias context declaration)
    | [], _ => none
    | head :: tail, subset =>
        if same : head.declaration = declaration then
          some ⟨head, subset head (by simp), same⟩
        else visit tail (fun entry member => subset entry (by simp [member]))
  visit context.typeAliases (fun _ member => member)

def groundBuiltinType? (context : Context) :
    (surface : Surface.TypeExpr) → Option (GroundedType context surface)
  | .path segments =>
      match single : singleNamePath? { segments } with
      | none => none
      | some name =>
          match found : Elaboration.builtinScalar? name with
          | none => none
          | some scalar => some ⟨.scalar scalar, .builtin single found⟩
  | _ => none

/-- Ground a nongeneric alias target without recursively expanding another
    alias. This admits the useful `type Local = imported::Nominal` fragment
    while keeping cyclic alias rejection structural. -/
def groundNongenericAliasTarget? (context : Context)
    (surface : Surface.TypeExpr) : Option (GroundedType context surface) :=
  match surface with
  | .path segments =>
      match builtin : groundBuiltinType? context (.path segments) with
      | some grounded => some grounded
      | none => do
          if notBuiltin : Elaboration.builtinTypePath? { segments } = none then
            let resolved ← resolveGlobal? context .type { segments }
            let notShadowed ← globalTypePathNotShadowed? context { segments }
            let selected ← findNominalScheme? context resolved.symbol.declaration
            match argumentsFound : pathTypeArguments? { segments } with
            | none => none
            | some surfaceArguments =>
                if noParameters : selected.scheme.genericParameters = [] then
                  if noArguments : surfaceArguments = [] then
                    pure ⟨.nominal selected.scheme.type [] [], by
                      subst surfaceArguments
                      have arguments : NominalArgumentsGround context
                          selected.scheme.genericParameters [] [] [] := by
                        rw [noParameters]
                        exact .nil
                      exact .nominal resolved.symbol notBuiltin notShadowed.proof
                        resolved.resolved selected.member selected.sameDeclaration
                        argumentsFound arguments⟩
                  else none
                else none
          else none
  | _ => none

/-! Type grounding accepts only cases for which it can construct the existing
`TypeGrounds` judgment. Nominal lookup is declaration-based and currently
accepts the nongeneric fragment; generic argument evidence is added at the
same boundary rather than trusting flattened wire types. -/
def groundType? (context : Context) :
    (surface : Surface.TypeExpr) → Option (GroundedType context surface)
  | .path segments =>
      match single : singleNamePath? { segments } with
      | some name =>
          match found : Elaboration.builtinScalar? name with
          | some scalar => some ⟨.scalar scalar, .builtin single found⟩
          | none => groundNominalPath? context segments
              (builtinTypePath_none_of_single single found)
      | none =>
          if notBuiltin : Elaboration.builtinTypePath? { segments } = none then
            groundNominalPath? context segments notBuiltin
          else none
  | .array element (.literal length) => do
      let groundedElement ← groundType? context element
      pure ⟨.array groundedElement.type length,
        .array groundedElement.grounded .literal⟩
  | .array _ (.parameter _) => none
  | .slice element => do
      let groundedElement ← groundType? context element
      pure ⟨.slice groundedElement.type, .slice groundedElement.grounded⟩
  | .reference referent => do
      let groundedReferent ← groundType? context referent
      pure ⟨.reference groundedReferent.type, .reference groundedReferent.grounded⟩

where
  groundNominalPath? (context : Context) (segments : List Surface.PathSegment)
      (notBuiltin : Elaboration.builtinTypePath? { segments } = none) :
      Option (GroundedType context (.path segments)) := do
    let resolved ← resolveGlobal? context .type { segments }
    let notShadowed ← globalTypePathNotShadowed? context { segments }
    match findNominalScheme? context resolved.symbol.declaration with
    | some selected =>
        match argumentsFound : pathTypeArguments? { segments } with
        | none => none
        | some surfaceArguments =>
            if noParameters : selected.scheme.genericParameters = [] then
              if noArguments : surfaceArguments = [] then
                pure ⟨.nominal selected.scheme.type [] [], by
                  subst surfaceArguments
                  have arguments : NominalArgumentsGround context
                      selected.scheme.genericParameters [] [] [] := by
                    rw [noParameters]
                    exact .nil
                  exact .nominal resolved.symbol notBuiltin notShadowed.proof
                    resolved.resolved selected.member selected.sameDeclaration
                    argumentsFound arguments⟩
              else none
            else none
    | none => do
        let alias ← findTypeAlias? context resolved.symbol.declaration
        if noParameters : alias.entry.parameters = [] then
          if noRequirements : alias.entry.requirements = [] then
            match argumentsFound : pathTypeArguments? { segments } with
            | some [] => do
                let target ← groundNongenericAliasTarget?
                  (context.forTypeAlias alias.entry {}) alias.entry.target
                pure ⟨target.type, .typeAlias resolved.symbol notBuiltin
                  notShadowed.proof resolved.resolved alias.member
                  alias.sameDeclaration argumentsFound {} (by
                    rw [noParameters]
                    exact .nil) (by
                    rw [noRequirements]
                    exact .nil) target.grounded⟩
            | _ => none
          else none
        else none

mutual
  def groundTypeBEq : Static.GroundTy → Static.GroundTy → Bool
    | .unit, .unit => true
    | .scalar left, .scalar right => decide (left = right)
    | .array leftElement leftLength, .array rightElement rightLength =>
        groundTypeBEq leftElement rightElement && decide (leftLength = rightLength)
    | .slice left, .slice right => groundTypeBEq left right
    | .reference left, .reference right => groundTypeBEq left right
    | .nominal leftId leftTypes leftConsts,
        .nominal rightId rightTypes rightConsts =>
        decide (leftId = rightId) &&
          groundTypeListBEq leftTypes rightTypes &&
          decide (leftConsts = rightConsts)
    | _, _ => false

  def groundTypeListBEq : List Static.GroundTy → List Static.GroundTy → Bool
    | [], [] => true
    | leftHead :: leftTail, rightHead :: rightTail =>
        groundTypeBEq leftHead rightHead &&
          groundTypeListBEq leftTail rightTail
    | _, _ => false
end

mutual
  theorem groundTypeBEq_sound {left right : Static.GroundTy}
      (accepted : groundTypeBEq left right = true) : left = right := by
    cases left <;> cases right <;>
      simp only [groundTypeBEq, Bool.false_eq_true, decide_eq_true_eq,
        Bool.and_eq_true] at accepted
    all_goals try contradiction
    · rfl
    · cases accepted
      rfl
    · rcases accepted with ⟨element, length⟩
      rw [groundTypeBEq_sound element, length]
    · rw [groundTypeBEq_sound accepted]
    · rw [groundTypeBEq_sound accepted]
    · rcases accepted with ⟨⟨id, types⟩, consts⟩
      rw [id, groundTypeListBEq_sound types, consts]

  theorem groundTypeListBEq_sound {left right : List Static.GroundTy}
      (accepted : groundTypeListBEq left right = true) : left = right := by
    cases left <;> cases right <;>
      simp only [groundTypeListBEq, Bool.false_eq_true,
        Bool.and_eq_true] at accepted
    all_goals try contradiction
    · rfl
    · rcases accepted with ⟨head, tail⟩
      rw [groundTypeBEq_sound head, groundTypeListBEq_sound tail]
end

mutual
  theorem groundTypeBEq_refl (type : Static.GroundTy) :
      groundTypeBEq type type = true := by
    cases type with
    | unit => rfl
    | scalar type => simp [groundTypeBEq]
    | array element length =>
        simp [groundTypeBEq, groundTypeBEq_refl element]
    | slice element => exact groundTypeBEq_refl element
    | reference referent => exact groundTypeBEq_refl referent
    | nominal id typeArguments constArguments =>
        simp [groundTypeBEq, groundTypeListBEq_refl typeArguments]

  theorem groundTypeListBEq_refl (types : List Static.GroundTy) :
      groundTypeListBEq types types = true := by
    cases types with
    | nil => rfl
    | cons head tail =>
        simp [groundTypeListBEq, groundTypeBEq_refl head,
          groundTypeListBEq_refl tail]
end

def groundTypeEq? (left right : Static.GroundTy) :
    Option (Evidence (left = right)) :=
  if accepted : groundTypeBEq left right = true then
    some ⟨groundTypeBEq_sound accepted⟩
  else none

def groundTypeListEq? (left right : List Static.GroundTy) :
    Option (Evidence (left = right)) :=
  if accepted : groundTypeListBEq left right = true then
    some ⟨groundTypeListBEq_sound accepted⟩
  else none

def functionInstanceEq? (left right : Static.FunctionInstance) :
    Option (Evidence (left = right)) := do
  if declaration : left.declaration = right.declaration then
    if function : left.function = right.function then
      let typeArguments ← groundTypeListEq? left.typeArguments right.typeArguments
      if constArguments : left.constArguments = right.constArguments then
        let parameterTypes ← groundTypeListEq? left.parameterTypes right.parameterTypes
        let returnType ← groundTypeEq? left.returnType right.returnType
        pure ⟨by
          rcases typeArguments with ⟨typeArguments⟩
          rcases parameterTypes with ⟨parameterTypes⟩
          rcases returnType with ⟨returnType⟩
          cases left
          cases right
          simp_all⟩
      else none
    else none
  else none

structure FoundFunctionScheme (context : Context) (declaration : Nat) where
  scheme : Static.FunctionScheme
  member : scheme ∈ context.functions
  sameDeclaration : scheme.declaration = declaration

def findFunctionScheme? (context : Context) (declaration : Nat) :
    Option (FoundFunctionScheme context declaration) :=
  let rec visit : (remaining : List Static.FunctionScheme) →
      (∀ scheme, scheme ∈ remaining → scheme ∈ context.functions) →
      Option (FoundFunctionScheme context declaration)
    | [], _ => none
    | head :: tail, subset =>
        if same : head.declaration = declaration then
          some ⟨head, subset head (by simp), same⟩
        else visit tail (fun scheme member => subset scheme (by simp [member]))
  visit context.functions (fun _ member => member)

structure FoundConstant (context : Context) (constant : ConstantId) where
  entry : ConstantEntry
  member : entry ∈ context.constants
  sameConstant : entry.constant = constant

def findConstant? (context : Context) (constant : ConstantId) :
    Option (FoundConstant context constant) :=
  let rec visit : (remaining : List ConstantEntry) →
      (∀ entry, entry ∈ remaining → entry ∈ context.constants) →
      Option (FoundConstant context constant)
    | [], _ => none
    | head :: tail, subset =>
        if same : head.constant = constant then
          some ⟨head, subset head (by simp), same⟩
        else visit tail (fun entry member => subset entry (by simp [member]))
  visit context.constants (fun _ member => member)

structure ResolvedConstant (context : Context) (path : Surface.Path)
    (constant : ConstantId) where
  entry : ConstantEntry
  sameConstant : entry.constant = constant
  resolved : ResolvesConstant context path entry

def resolveConstant? (context : Context) (path : Surface.Path)
    (constant : ConstantId) : Option (ResolvedConstant context path constant) := do
  let global ← resolveGlobal? context .value path
  let notShadowed ← globalPathNotShadowed? context path
  let found ← findConstant? context constant
  if sameDeclaration : found.entry.declaration = global.symbol.declaration then
    pure ⟨found.entry, found.sameConstant,
      notShadowed.proof, global.symbol, global.resolved,
      found.member, sameDeclaration⟩
  else none

structure FoundFunctionInstance (context : Context) (function : FunctionId) where
  row : Static.FunctionInstance
  member : row ∈ context.functionInstances
  sameFunction : row.function = function

def findFunctionInstance? (context : Context) (function : FunctionId) :
    Option (FoundFunctionInstance context function) :=
  let rec visit : (remaining : List Static.FunctionInstance) →
      (∀ row, row ∈ remaining → row ∈ context.functionInstances) →
      Option (FoundFunctionInstance context function)
    | [], _ => none
    | head :: tail, subset =>
        if same : head.function = function then
          some ⟨head, subset head (by simp), same⟩
        else visit tail (fun row member => subset row (by simp [member]))
  visit context.functionInstances (fun _ member => member)

def functionInstanceCandidateCompatible (declaration : Nat)
    (argumentTypes : List Static.GroundTy) (function : FunctionId)
    (candidate : Static.FunctionInstance) : Bool :=
  if sameDeclaration : candidate.declaration = declaration then
    if sameParameters : groundTypeListBEq candidate.parameterTypes argumentTypes = true then
      decide (candidate.function = function)
    else true
  else true

def functionInstancesCompatible (declaration : Nat)
    (argumentTypes : List Static.GroundTy) (function : FunctionId) :
    List Static.FunctionInstance → Bool
  | [] => true
  | head :: tail =>
      functionInstanceCandidateCompatible declaration argumentTypes function head &&
        functionInstancesCompatible declaration argumentTypes function tail

theorem functionInstancesCompatible_sound {instances : List Static.FunctionInstance}
    {declaration : Nat} {argumentTypes : List Static.GroundTy}
    {function : FunctionId}
    (accepted : functionInstancesCompatible declaration argumentTypes function
      instances = true) :
    ∀ candidate, candidate ∈ instances →
      candidate.declaration = declaration →
      candidate.parameterTypes = argumentTypes →
      candidate.function = function := by
  intro candidate member
  induction instances with
  | nil => simp at member
  | cons head tail induction =>
      simp only [functionInstancesCompatible, Bool.and_eq_true] at accepted
      rcases accepted with ⟨headAccepted, tailAccepted⟩
      simp only [List.mem_cons] at member
      rcases member with rfl | member
      · intro sameDeclaration sameParameters
        unfold functionInstanceCandidateCompatible at headAccepted
        have parameterCheck :
            groundTypeListBEq candidate.parameterTypes argumentTypes = true := by
          rw [sameParameters]
          exact groundTypeListBEq_refl argumentTypes
        split at headAccepted
        · simpa [parameterCheck] using headAccepted
        · rename_i rejected
          exact False.elim (rejected sameDeclaration)
      · exact induction tailAccepted member

theorem functionInstantiates_declaration
    (instantiated : Static.FunctionInstantiates implementations scheme
      substitution resolved) :
    resolved.declaration = scheme.declaration := by
  cases instantiated with
  | intro bound arguments requirements types =>
      unfold Static.FunctionScheme.instantiateTypes at types
      rcases Option.bind_eq_some_iff.mp types with
        ⟨parameterTypes, parameterTypesFound, returnContinuation⟩
      rcases Option.bind_eq_some_iff.mp returnContinuation with
        ⟨returnType, returnTypeFound, result⟩
      exact (congrArg Static.FunctionInstance.declaration
        (Option.some.inj result)).symm

structure CheckedDirectCall
    (context : Context) (path : Surface.Path)
    (argumentTypes : List Static.GroundTy) (function : FunctionId) where
  scheme : Static.FunctionScheme
  resolved : Static.FunctionInstance
  sameFunction : resolved.function = function
  proof : ResolvesDirectCall context path argumentTypes scheme resolved

def resolveNongenericDirectCall? (context : Context) (path : Surface.Path)
    (argumentTypes : List Static.GroundTy) (function : FunctionId) :
    Option (CheckedDirectCall context path argumentTypes function) := do
  let global ← resolveGlobal? context .value path
  let notShadowed ← globalPathNotShadowed? context path
  let scheme ← findFunctionScheme? context global.symbol.declaration
  let resolved ← findFunctionInstance? context function
  if noParameters : scheme.scheme.genericParameters = [] then
    if noRequirements : scheme.scheme.requirements = [] then
      if noTypeArguments : resolved.row.typeArguments = [] then
        if noConstArguments : resolved.row.constArguments = [] then
          match explicitArguments : pathTypeArguments? path with
          | some [] =>
              match computed : scheme.scheme.instantiateTypes resolved.row.function
                  [] [] {} with
              | none => none
              | some computedRow => do
                  let sameRow ← functionInstanceEq? computedRow resolved.row
                  let sameParameters ←
                    groundTypeListEq? resolved.row.parameterTypes argumentTypes
                  if unique : functionInstancesCompatible global.symbol.declaration
                      argumentTypes resolved.row.function
                      context.functionInstances = true then
                    let instantiated : Static.FunctionInstantiates
                        context.implementations scheme.scheme {} resolved.row := by
                      apply Static.FunctionInstantiates.intro
                      · rw [noParameters]
                        exact .nil
                      · rw [noParameters, noTypeArguments, noConstArguments]
                        exact .nil
                      · rw [noRequirements]
                        exact .nil
                      · rw [noTypeArguments, noConstArguments]
                        exact computed.trans (congrArg some sameRow.proof)
                    let applies : DirectCallApplies context path scheme.scheme
                        argumentTypes resolved.row := ⟨resolved.member, {},
                          instantiated, sameParameters.proof,
                          by simp [ExplicitCallArgumentsGround, explicitArguments]⟩
                    pure ⟨scheme.scheme, resolved.row, resolved.sameFunction, by
                      refine ⟨notShadowed.proof, global.symbol, global.resolved,
                        scheme.member, scheme.sameDeclaration, applies, ?_⟩
                      intro candidate candidateInstance candidateMember
                        candidateDeclaration candidateApplies
                      rcases candidateApplies with
                        ⟨candidateInstanceMember, substitution,
                          candidateInstantiated, candidateParameters,
                          explicit⟩
                      exact functionInstancesCompatible_sound unique
                        candidateInstance candidateInstanceMember
                        ((functionInstantiates_declaration candidateInstantiated).trans
                          candidateDeclaration)
                        candidateParameters⟩
                  else none
          | _ => none
        else none
      else none
    else none
  else none

structure FoundField (context : Context) (receiver : Static.GroundTy)
    (name : Surface.Name) where
  entry : FieldEntry
  member : entry ∈ context.fields
  sameReceiver : entry.receiver = receiver
  sameName : entry.name = name

def findField? (context : Context) (receiver : Static.GroundTy)
    (name : Surface.Name) : Option (FoundField context receiver name) :=
  let rec visit : (remaining : List FieldEntry) →
      (∀ entry, entry ∈ remaining → entry ∈ context.fields) →
      Option (FoundField context receiver name)
    | [], _ => none
    | head :: tail, subset =>
        match sameReceiver : groundTypeEq? head.receiver receiver with
        | some receiverProof =>
            if sameName : head.name = name then
              some ⟨head, subset head (by simp), receiverProof.proof, sameName⟩
            else visit tail (fun entry member => subset entry (by simp [member]))
        | none => visit tail (fun entry member => subset entry (by simp [member]))
  visit context.fields (fun _ member => member)

def fieldCandidateCompatible (receiver : Static.GroundTy)
    (name : Surface.Name) (selected : FieldEntry) (candidate : FieldEntry) : Bool :=
  if sameReceiver : groundTypeBEq candidate.receiver receiver = true then
    if sameName : candidate.name = name then
      decide (candidate.field = selected.field) &&
        groundTypeBEq candidate.type selected.type
    else true
  else true

def fieldsCompatible (receiver : Static.GroundTy) (name : Surface.Name)
    (selected : FieldEntry) : List FieldEntry → Bool
  | [] => true
  | head :: tail =>
      fieldCandidateCompatible receiver name selected head &&
        fieldsCompatible receiver name selected tail

theorem fieldsCompatible_sound {fields : List FieldEntry}
    {receiver : Static.GroundTy} {name : Surface.Name} {selected : FieldEntry}
    (accepted : fieldsCompatible receiver name selected fields = true) :
    ∀ candidate, candidate ∈ fields → candidate.receiver = receiver →
      candidate.name = name →
      candidate.field = selected.field ∧ candidate.type = selected.type := by
  intro candidate member
  induction fields with
  | nil => simp at member
  | cons head tail induction =>
      simp only [fieldsCompatible, Bool.and_eq_true] at accepted
      rcases accepted with ⟨headAccepted, tailAccepted⟩
      simp only [List.mem_cons] at member
      rcases member with rfl | member
      · intro sameReceiver sameName
        have receiverCheck : groundTypeBEq candidate.receiver receiver = true := by
          rw [sameReceiver]
          exact groundTypeBEq_refl receiver
        unfold fieldCandidateCompatible at headAccepted
        split at headAccepted
        · have checked : candidate.field = selected.field ∧
              groundTypeBEq candidate.type selected.type = true := by
            simpa [sameName] using headAccepted
          exact ⟨checked.1, groundTypeBEq_sound checked.2⟩
        · rename_i rejected
          exact False.elim (rejected receiverCheck)
      · exact induction tailAccepted member

structure SelectedField (context : Context) (receiver : Static.GroundTy)
    (name : Surface.Name) (field : FieldId) where
  entry : FieldEntry
  sameField : entry.field = field
  selected : SelectsField context receiver name entry

def selectField? (context : Context) (receiver : Static.GroundTy)
    (name : Surface.Name) (field : FieldId) :
    Option (SelectedField context receiver name field) := do
  let found ← findField? context receiver name
  if sameField : found.entry.field = field then
    if compatible : fieldsCompatible receiver name found.entry context.fields = true then
      pure ⟨found.entry, sameField,
        found.member, found.sameReceiver, found.sameName,
        fieldsCompatible_sound compatible⟩
    else none
  else none

mutual
  def staticTypeBEq : Static.Ty → Static.Ty → Bool
    | .unit, .unit => true
    | .scalar left, .scalar right => decide (left = right)
    | .parameter left, .parameter right => decide (left = right)
    | .array leftElement leftLength, .array rightElement rightLength =>
        staticTypeBEq leftElement rightElement && decide (leftLength = rightLength)
    | .slice left, .slice right => staticTypeBEq left right
    | .reference left, .reference right => staticTypeBEq left right
    | .nominal leftId leftTypes leftConsts,
        .nominal rightId rightTypes rightConsts =>
        decide (leftId = rightId) && staticTypeListBEq leftTypes rightTypes &&
          decide (leftConsts = rightConsts)
    | _, _ => false

  def staticTypeListBEq : List Static.Ty → List Static.Ty → Bool
    | [], [] => true
    | leftHead :: leftTail, rightHead :: rightTail =>
        staticTypeBEq leftHead rightHead &&
          staticTypeListBEq leftTail rightTail
    | _, _ => false
end

mutual
  theorem staticTypeBEq_sound {left right : Static.Ty}
      (accepted : staticTypeBEq left right = true) : left = right := by
    cases left <;> cases right <;>
      simp only [staticTypeBEq, Bool.false_eq_true, decide_eq_true_eq,
        Bool.and_eq_true] at accepted
    all_goals try contradiction
    · rfl
    · cases accepted; rfl
    · cases accepted; rfl
    · rcases accepted with ⟨element, length⟩
      rw [staticTypeBEq_sound element, length]
    · rw [staticTypeBEq_sound accepted]
    · rw [staticTypeBEq_sound accepted]
    · rcases accepted with ⟨⟨id, types⟩, consts⟩
      rw [id, staticTypeListBEq_sound types, consts]

  theorem staticTypeListBEq_sound {left right : List Static.Ty}
      (accepted : staticTypeListBEq left right = true) : left = right := by
    cases left <;> cases right <;>
      simp only [staticTypeListBEq, Bool.false_eq_true,
        Bool.and_eq_true] at accepted
    all_goals try contradiction
    · rfl
    · rcases accepted with ⟨head, tail⟩
      rw [staticTypeBEq_sound head, staticTypeListBEq_sound tail]
end

def structFieldSchemeBEq (left right : StructFieldScheme) : Bool :=
  decide (left.name = right.name) && decide (left.field = right.field) &&
    staticTypeBEq left.type right.type

theorem structFieldSchemeBEq_sound {left right : StructFieldScheme}
    (accepted : structFieldSchemeBEq left right = true) : left = right := by
  unfold structFieldSchemeBEq at accepted
  simp only [Bool.and_eq_true, decide_eq_true_eq] at accepted
  rcases accepted with ⟨⟨name, field⟩, type⟩
  have typeEqual := staticTypeBEq_sound type
  cases left
  cases right
  simp_all

def structFieldSchemesBEq :
    List StructFieldScheme → List StructFieldScheme → Bool
  | [], [] => true
  | leftHead :: leftTail, rightHead :: rightTail =>
      structFieldSchemeBEq leftHead rightHead &&
        structFieldSchemesBEq leftTail rightTail
  | _, _ => false

theorem structFieldSchemesBEq_sound {left right : List StructFieldScheme}
    (accepted : structFieldSchemesBEq left right = true) : left = right := by
  induction left generalizing right with
  | nil => cases right <;> simp_all [structFieldSchemesBEq]
  | cons head tail induction =>
      cases right with
      | nil => simp [structFieldSchemesBEq] at accepted
      | cons rightHead rightTail =>
          simp only [structFieldSchemesBEq, Bool.and_eq_true] at accepted
          rw [structFieldSchemeBEq_sound accepted.1,
            induction accepted.2]

structure FoundStructConstructor (context : Context) (declaration : Nat) where
  scheme : StructConstructorScheme
  member : scheme ∈ context.structConstructors
  sameDeclaration : scheme.declaration = declaration

def listEmptyBool : List α → Bool
  | [] => true
  | _ :: _ => false

theorem listEmptyBool_sound {values : List α}
    (accepted : listEmptyBool values = true) : values = [] := by
  cases values <;> simp_all [listEmptyBool]

def findStructConstructor? (context : Context) (declaration : Nat) :
    Option (FoundStructConstructor context declaration) :=
  let rec visit : (remaining : List StructConstructorScheme) →
      (∀ scheme, scheme ∈ remaining → scheme ∈ context.structConstructors) →
      Option (FoundStructConstructor context declaration)
    | [], _ => none
    | head :: tail, subset =>
        if same : head.declaration = declaration then
          some ⟨head, subset head (by simp), same⟩
        else visit tail (fun scheme member => subset scheme (by simp [member]))
  visit context.structConstructors (fun _ member => member)

def structConstructorCandidateCompatible (declaration : Nat)
    (sourceType : TypeId) (fields : List StructFieldScheme)
    (candidate : StructConstructorScheme) : Bool :=
  if sameDeclaration : candidate.declaration = declaration then
    decide (candidate.sourceType = sourceType) &&
      listEmptyBool candidate.genericParameters &&
      listEmptyBool candidate.requirements &&
      structFieldSchemesBEq candidate.fields fields
  else true

def structConstructorsCompatible (declaration : Nat) (sourceType : TypeId)
    (fields : List StructFieldScheme) : List StructConstructorScheme → Bool
  | [] => true
  | head :: tail =>
      structConstructorCandidateCompatible declaration sourceType fields head &&
        structConstructorsCompatible declaration sourceType fields tail

theorem structConstructorsCompatible_sound
    {constructors : List StructConstructorScheme} {declaration : Nat}
    {sourceType : TypeId} {fields : List StructFieldScheme}
    (accepted : structConstructorsCompatible declaration sourceType fields
      constructors = true) :
    ∀ candidate, candidate ∈ constructors →
      candidate.declaration = declaration →
      candidate.sourceType = sourceType ∧ candidate.genericParameters = [] ∧
        candidate.requirements = [] ∧ candidate.fields = fields := by
  intro candidate member
  induction constructors with
  | nil => simp at member
  | cons head tail induction =>
      simp only [structConstructorsCompatible, Bool.and_eq_true] at accepted
      rcases accepted with ⟨headAccepted, tailAccepted⟩
      simp only [List.mem_cons] at member
      rcases member with rfl | member
      · intro sameDeclaration
        unfold structConstructorCandidateCompatible at headAccepted
        split at headAccepted
        · simp only [Bool.and_eq_true, decide_eq_true_eq] at headAccepted
          exact ⟨headAccepted.1.1.1,
            listEmptyBool_sound headAccepted.1.1.2,
            listEmptyBool_sound headAccepted.1.2,
            structFieldSchemesBEq_sound headAccepted.2⟩
        · rename_i rejected
          exact False.elim (rejected sameDeclaration)
      · exact induction tailAccepted member

structure SelectedStructConstructor (context : Context) (path : Surface.Path) where
  scheme : StructConstructorScheme
  noParameters : scheme.genericParameters = []
  noRequirements : scheme.requirements = []
  selected : SelectsStructConstructor context path scheme

def selectNongenericStructConstructor? (context : Context) (path : Surface.Path) :
    Option (SelectedStructConstructor context path) := do
  let global ← resolveGlobal? context .type path
  let found ← findStructConstructor? context global.symbol.declaration
  if noParameters : found.scheme.genericParameters = [] then
    if noRequirements : found.scheme.requirements = [] then
      if compatible : structConstructorsCompatible found.scheme.declaration
          found.scheme.sourceType found.scheme.fields
          context.structConstructors = true then
        pure ⟨found.scheme, noParameters, noRequirements,
          global.symbol, global.resolved, found.member, found.sameDeclaration, by
            intro candidate member declaration
            have agrees := structConstructorsCompatible_sound compatible
              candidate member (declaration.trans found.sameDeclaration.symm)
            exact ⟨agrees.1,
              agrees.2.1.trans noParameters.symm,
              agrees.2.2.1.trans noRequirements.symm,
              agrees.2.2.2⟩⟩
      else none
    else none
  else none

structure FoundNominalInstance (context : Context) (coreType : TypeId) where
  row : Static.NominalInstance
  member : row ∈ context.nominalInstances
  sameCoreType : row.coreType = coreType

def findNominalInstance? (context : Context) (coreType : TypeId) :
    Option (FoundNominalInstance context coreType) :=
  let rec visit : (remaining : List Static.NominalInstance) →
      (∀ row, row ∈ remaining → row ∈ context.nominalInstances) →
      Option (FoundNominalInstance context coreType)
    | [], _ => none
    | head :: tail, subset =>
        if same : head.coreType = coreType then
          some ⟨head, subset head (by simp), same⟩
        else visit tail (fun row member => subset row (by simp [member]))
  visit context.nominalInstances (fun _ member => member)

def nominalInstanceCandidateCompatible (sourceType coreType : TypeId)
    (candidate : Static.NominalInstance) : Bool :=
  if sameSource : candidate.sourceType = sourceType then
    match candidate.typeArguments, candidate.constArguments with
    | [], [] => decide (candidate.coreType = coreType)
    | _, _ => true
  else true

def nominalInstancesCompatible (sourceType coreType : TypeId) :
    List Static.NominalInstance → Bool
  | [] => true
  | head :: tail =>
      nominalInstanceCandidateCompatible sourceType coreType head &&
        nominalInstancesCompatible sourceType coreType tail

theorem nominalInstancesCompatible_sound {instances : List Static.NominalInstance}
    {sourceType coreType : TypeId}
    (accepted : nominalInstancesCompatible sourceType coreType instances = true) :
    ∀ candidate, candidate ∈ instances → candidate.sourceType = sourceType →
      candidate.typeArguments = [] → candidate.constArguments = [] →
      candidate.coreType = coreType := by
  intro candidate member
  induction instances with
  | nil => simp at member
  | cons head tail induction =>
      simp only [nominalInstancesCompatible, Bool.and_eq_true] at accepted
      rcases accepted with ⟨headAccepted, tailAccepted⟩
      simp only [List.mem_cons] at member
      rcases member with rfl | member
      · intro sameSource noTypes noConsts
        unfold nominalInstanceCandidateCompatible at headAccepted
        split at headAccepted
        · simp [noTypes, noConsts] at headAccepted
          exact headAccepted
        · rename_i rejected
          exact False.elim (rejected sameSource)
      · exact induction tailAccepted member

structure InstantiatedStructConstructor (context : Context) (path : Surface.Path)
    (coreType : TypeId) where
  scheme : StructConstructorScheme
  resolved : Static.NominalInstance
  sameCoreType : resolved.coreType = coreType
  selected : SelectsStructConstructor context path scheme
  noParameters : scheme.genericParameters = []
  noRequirements : scheme.requirements = []
  noArguments : PathHasNoGenericArguments path
  noTypeArguments : resolved.typeArguments = []
  noConstArguments : resolved.constArguments = []
  instantiated : NominalConstructorInstantiates context scheme.declaration
    scheme.sourceType .structure scheme.genericParameters scheme.requirements
    {} resolved

def instantiateNongenericStructConstructor? (context : Context)
    (path : Surface.Path) (coreType : TypeId) :
    Option (InstantiatedStructConstructor context path coreType) := do
  let selected ← selectNongenericStructConstructor? context path
  match noArguments : pathTypeArguments? path with
  | some [] =>
      let resolved ← findNominalInstance? context coreType
      if sameDeclaration : resolved.row.declaration = selected.scheme.declaration then
        if sameSource : resolved.row.sourceType = selected.scheme.sourceType then
          match sameKind : resolved.row.kind with
          | .structure =>
              if noTypes : resolved.row.typeArguments = [] then
                if noConsts : resolved.row.constArguments = [] then
                  if unique : nominalInstancesCompatible selected.scheme.sourceType
                      resolved.row.coreType context.nominalInstances = true then
                    pure ⟨selected.scheme, resolved.row, resolved.sameCoreType,
                      selected.selected, selected.noParameters,
                      selected.noRequirements,
                      noArguments, noTypes, noConsts,
                      resolved.member, sameDeclaration, sameSource,
                      sameKind, by
                        rw [selected.noParameters, noTypes, noConsts]
                        exact .nil,
                      by rw [selected.noRequirements]; exact .nil,
                      by
                        intro candidate member candidateSource candidateTypes
                          candidateConsts
                        rw [noTypes] at candidateTypes
                        rw [noConsts] at candidateConsts
                        exact nominalInstancesCompatible_sound unique candidate member
                          candidateSource candidateTypes candidateConsts⟩
                  else none
                else none
              else none
          | .enumeration => none
        else none
      else none
  | _ => none

structure InferredExprLowering
    (context : Context) (surface : Surface.Expr) (core : Expr) where
  type : Static.GroundTy
  coreType : Ty
  grounded : type.toCore context.monomorphization = some coreType
  lowered : ExprLowers context surface type core

structure InferredPlaceLowering
    (context : Context) (surface : Surface.Expr) (core : Place) where
  type : Static.GroundTy
  coreType : Ty
  grounded : type.toCore context.monomorphization = some coreType
  lowered : PlaceLowers context surface type core

structure InferredExprsLowering
    (context : Context) (surface : List Surface.Expr) (core : List Expr) where
  types : List Static.GroundTy
  lowered : ExprsCheck context surface types core

structure CheckedOrderedStructFields (context : Context)
    (schemes : List StructFieldScheme)
    (surface : List (Surface.Name × Surface.Expr)) (core : List Expr) : Type where
  lowered : StructSchemeFieldsCheck context {} schemes surface core

theorem scalarGrounded
    (context : Context) (scalar : ScalarTy) :
    (.scalar scalar : Static.GroundTy).toCore context.monomorphization =
      some (.scalar scalar) := rfl

structure CoreGrounding (context : Context) (type : Ty) where
  ground : Static.GroundTy
  grounded : ground.toCore context.monomorphization = some type

def outputGround? (context : Context) (type : Ty) :
    Option (CoreGrounding context type) :=
  match type with
  | .scalar scalar => some ⟨.scalar scalar, rfl⟩
  | .unit => some ⟨.unit, rfl⟩
  | _ => none

mutual
  def inferExpr (context : Context) :
      (surface : Surface.Expr) → (core : Expr) →
        Option (InferredExprLowering context surface core)
    | .literal literal, core => do
        let type := Elaboration.literalDefaultType literal
        let lowered ← literalElaborates? context.target literal type core
        pure {
          type := defaultGroundType literal
          coreType := type
          grounded := defaultGroundType_toCore context.monomorphization literal
          lowered := .literal lowered.proof
            (defaultGroundType_toCore context.monomorphization literal)
        }
    | .path path, .local localId =>
        match single : singleNamePath? path with
        | none => none
        | some name => do
            let resolved ← resolveLocal? context.locals name
            if sameId : resolved.binding.id = localId then
              match grounded : resolved.binding.type.toCore context.monomorphization with
              | none => none
              | some coreType =>
                  pure {
                    type := resolved.binding.type
                    coreType
                    grounded
                    lowered := by
                      subst localId
                      exact .local name single resolved.resolved
                  }
            else none
    | .path path, .constant constant => do
        let resolved ← resolveConstant? context path constant
        match grounded : resolved.entry.type.toCore context.monomorphization with
        | none => none
        | some coreType =>
            pure {
              type := resolved.entry.type
              coreType
              grounded
              lowered := by
                have lowering := ExprLowers.constant resolved.resolved
                simpa only [resolved.sameConstant] using lowering
            }
    | .unary operation surfaceOperand, .unary coreOperation coreOperand => do
        if sameOperation : coreOperation = lowerUnaryOp operation then
          let operand ← inferExpr context surfaceOperand coreOperand
          let typing ← CoreTyping.unaryTyping? coreOperation operand.coreType
          if sameOutput : typing.output = operand.coreType then
            pure {
              type := operand.type
              coreType := operand.coreType
              grounded := operand.grounded
              lowered := by
                have typed : Typing.UnaryOpHasType coreOperation
                    operand.coreType operand.coreType := by
                  simpa only [sameOutput] using typing.typed
                subst coreOperation
                exact .unary operand.lowered operand.grounded operand.grounded
                  typed
            }
          else none
        else none
    | .binary operation surfaceLeft surfaceRight,
        .binary coreOperation coreLeft coreRight => do
        if sameOperation : coreOperation = lowerBinaryOp operation then
          let left ← inferExpr context surfaceLeft coreLeft
          let right ← inferExpr context surfaceRight coreRight
          let typing ← CoreTyping.binaryTyping? coreOperation left.coreType right.coreType
          let output ← outputGround? context typing.output
          pure {
            type := output.ground
            coreType := typing.output
            grounded := output.grounded
            lowered := by
              subst coreOperation
              exact .binary left.lowered right.lowered left.grounded right.grounded
                output.grounded typing.typed
          }
        else none
    | .member surfaceBase name, .field coreBase field => do
        let base ← inferExpr context surfaceBase coreBase
        let selected ← selectField? context base.type name field
        match grounded : selected.entry.type.toCore context.monomorphization with
        | none => none
        | some coreType =>
            pure {
              type := selected.entry.type
              coreType
              grounded
              lowered := by
                have lowering := ExprLowers.field base.lowered
                  Elaboration.MemberBaseLowers.direct selected.selected
                simpa only [selected.sameField] using lowering
            }
    | .structValue path surfaceFields, .structValue coreType coreFields => do
        let constructor ← instantiateNongenericStructConstructor?
          context path coreType
        let fields ← checkOrderedStructFields context constructor.scheme.fields
          surfaceFields coreFields
        match mapped : context.monomorphization.resolveNominal
            constructor.scheme.sourceType [] [] with
        | some (.structure mappedCoreType) =>
            if sameCoreType : mappedCoreType = coreType then
              pure {
                type := .nominal constructor.scheme.sourceType [] []
                coreType := .structure coreType
                grounded := by
                  simp only [Static.GroundTy.toCore]
                  rw [mapped, sameCoreType]
                lowered := by
                  have lowering := ExprLowers.structValueNongeneric
                    constructor.selected constructor.noArguments
                    constructor.noParameters constructor.instantiated fields.lowered
                  simpa only [constructor.sameCoreType,
                    constructor.noTypeArguments,
                    constructor.noConstArguments] using lowering
              }
            else none
        | _ => none
    | .index surfaceBase surfaceIndex, .index coreBase coreIndex => do
        let base ← inferExpr context surfaceBase coreBase
        let index ← inferExpr context surfaceIndex coreIndex
        let integer ← CoreTyping.integer? index.coreType
        match baseType : base.type with
        | .array element length =>
            match elementGrounded : element.toCore context.monomorphization with
            | none => none
            | some elementCore =>
                pure {
                  type := element
                  coreType := elementCore
                  grounded := elementGrounded
                  lowered := .indexArray (baseType ▸ base.lowered) index.lowered
                    index.grounded integer.proof
                }
        | .slice element =>
            match elementGrounded : element.toCore context.monomorphization with
            | none => none
            | some elementCore =>
                pure {
                  type := element
                  coreType := elementCore
                  grounded := elementGrounded
                  lowered := .indexSlice (baseType ▸ base.lowered) index.lowered
                    index.grounded integer.proof
                }
        | _ => none
    | .assign operation surfacePlace surfaceValue,
        .assign coreOperation corePlace coreValue => do
        if sameOperation : coreOperation = lowerAssignOp operation then
          let place ← inferPlace context surfacePlace corePlace
          let value ← inferExpr context surfaceValue coreValue
          let sameType ← groundTypeEq? value.type place.type
          let typed ← CoreTyping.assignTyping? coreOperation place.coreType
          pure {
            type := .unit
            coreType := .unit
            grounded := rfl
            lowered := by
              subst coreOperation
              exact .assign place.lowered
                (sameType.proof ▸ ExprChecks.exact value.lowered)
                place.grounded typed.proof
          }
        else none
    | .call (.path path) surfaceArguments, .call function coreArguments => do
        let arguments ← inferExprs context surfaceArguments coreArguments
        let resolved ← resolveNongenericDirectCall? context path
          arguments.types function
        match notIntrinsic : builtinIntrinsic? path with
        | some _ => none
        | none =>
            match grounded : resolved.resolved.returnType.toCore
                context.monomorphization with
            | none => none
            | some coreType =>
                pure {
                  type := resolved.resolved.returnType
                  coreType
                  grounded
                  lowered := by
                    have lowering := ExprLowers.directCall arguments.lowered
                      resolved.proof notIntrinsic rfl
                    simpa only [resolved.sameFunction] using lowering
                }
    | _, _ => none

  def inferPlace (context : Context) :
      (surface : Surface.Expr) → (core : Place) →
        Option (InferredPlaceLowering context surface core)
    | .path path, .local localId =>
        match single : singleNamePath? path with
        | none => none
        | some name => do
            let resolved ← resolveLocal? context.locals name
            if sameId : resolved.binding.id = localId then
              match grounded : resolved.binding.type.toCore context.monomorphization with
              | none => none
              | some coreType =>
                  pure {
                    type := resolved.binding.type
                    coreType
                    grounded
                    lowered := by
                      subst localId
                      exact .local name single resolved.resolved
                  }
            else none
    | .index surfaceBase surfaceIndex, .index coreBase coreIndex => do
        let base ← inferPlace context surfaceBase coreBase
        let index ← inferExpr context surfaceIndex coreIndex
        let integer ← CoreTyping.integer? index.coreType
        match baseType : base.type with
        | .array element length =>
            match elementGrounded : element.toCore context.monomorphization with
            | none => none
            | some elementCore =>
                pure {
                  type := element
                  coreType := elementCore
                  grounded := elementGrounded
                  lowered := .indexArray (baseType ▸ base.lowered) index.lowered
                    index.grounded integer.proof
                }
        | .slice element =>
            match elementGrounded : element.toCore context.monomorphization with
            | none => none
            | some elementCore =>
                pure {
                  type := element
                  coreType := elementCore
                  grounded := elementGrounded
                  lowered := .indexSlice (baseType ▸ base.lowered) index.lowered
                    index.grounded integer.proof
                }
        | _ => none
    | _, _ => none

  def inferExprs (context : Context) :
      (surface : List Surface.Expr) → (core : List Expr) →
        Option (InferredExprsLowering context surface core)
    | [], [] => some ⟨[], .nil⟩
    | surfaceHead :: surfaceTail, coreHead :: coreTail => do
        let head ← inferExpr context surfaceHead coreHead
        let tail ← inferExprs context surfaceTail coreTail
        pure ⟨head.type :: tail.types,
          .cons (.exact head.lowered) tail.lowered⟩
    | _, _ => none

  def checkOrderedStructFields (context : Context) :
      (schemes : List StructFieldScheme) →
      (surface : List (Surface.Name × Surface.Expr)) →
      (core : List Expr) →
      Option (CheckedOrderedStructFields context schemes surface core)
    | [], [], [] => some ⟨.nil⟩
    | scheme :: schemeTail, (name, surfaceValue) :: surfaceTail,
        coreValue :: coreTail => do
        if sameName : name = scheme.name then
          match instantiated : scheme.type.instantiate {} with
          | none => none
          | some expected => do
              let value ← inferExpr context surfaceValue coreValue
              let sameType ← groundTypeEq? value.type expected
              let tail ← checkOrderedStructFields context schemeTail
                surfaceTail coreTail
              pure ⟨by
                subst name
                exact .cons .head instantiated
                  (sameType.proof ▸ ExprChecks.exact value.lowered)
                  tail.lowered⟩
        else none
    | _, _, _ => none
end

def checkContextualExpr? (context : Context)
    (surface : Surface.Expr) (expected : Static.GroundTy) (core : Expr) :
    Option (Evidence (ExprChecks context surface expected core)) :=
  match surface with
  | .literal literal =>
      match grounded : expected.toCore context.monomorphization with
      | none => none
      | some coreType => do
          let lowered ← literalElaborates? context.target literal coreType core
          pure ⟨.literal coreType lowered.proof grounded⟩
  | _ => none

def checkExpr (context : Context)
    (surface : Surface.Expr) (expected : Static.GroundTy) (core : Expr) :
    Option (Evidence (ExprChecks context surface expected core)) :=
  match inferExpr context surface core with
  | some inferred =>
      match groundTypeEq? inferred.type expected with
      | some same => some ⟨same.proof ▸ ExprChecks.exact inferred.lowered⟩
      | none => checkContextualExpr? context surface expected core
  | none => checkContextualExpr? context surface expected core

def freshLocalId? (context : Context) (id : VarId) :
    Option (Evidence (FreshLocalId context id)) :=
  let rec visit : (locals : List LocalBinding) →
      Option (Evidence (∀ binding, binding ∈ locals → binding.id ≠ id))
    | [] => some ⟨by simp⟩
    | head :: tail => do
        if different : head.id ≠ id then
          let rest ← visit tail
          pure ⟨by
            intro binding member
            simp only [List.mem_cons] at member
            rcases member with rfl | member
            · exact different
            · exact rest.proof binding member⟩
        else none
  visit context.locals

structure CheckedStmtsLowering
    (context : Context) (next : VarId)
    (surface : List Surface.Stmt) (core : Core.Stmt) where
  finalNext : VarId
  lowered : StmtsLower context next surface core finalNext

def checkCoreTypeMapping? (context : Context)
    (ground : Static.GroundTy) (core : Ty) :
    Option (Evidence (ground.toCore context.monomorphization = some core)) :=
  match _mapped : ground.toCore context.monomorphization with
  | none => none
  | some actual =>
      if same : actual = core then
        some ⟨congrArg some same⟩
      else none

structure CheckedParameters
    (context : Context) (next : VarId)
    (surface : List Surface.Parameter) (core : List (VarId × Ty)) where
  groundTypes : List Static.GroundTy
  bodyContext : Context
  finalNext : VarId
  lowered : ProgramElaboration.ParametersLower context none next surface
    groundTypes core bodyContext finalNext

def checkParameters :
    (context : Context) → (next : VarId) →
    (surface : List Surface.Parameter) → (core : List (VarId × Ty)) →
      Option (CheckedParameters context next surface core)
  | context, next, [], [] => some ⟨[], context, next, .nil⟩
  | context, next, .named name surfaceType :: surfaceTail,
      (coreId, coreType) :: coreTail => do
      if sameId : coreId = next then
        let notShadowed ← noLocalNamed? context name
        let grounded ← groundType? context surfaceType
        let mapped ← checkCoreTypeMapping? context grounded.type coreType
        let tail ← checkParameters
          (context.bindLocal name next grounded.type) (next + 1)
          surfaceTail coreTail
        pure ⟨grounded.type :: tail.groundTypes, tail.bodyContext,
          tail.finalNext, by
            subst coreId
            exact .named notShadowed.proof grounded.grounded mapped.proof
              tail.lowered⟩
      else none
  | _, _, _, _ => none

structure GroundedReturn
    (context : Context) (functionName : Surface.Name)
    (surface : Option Surface.TypeExpr) where
  type : Static.GroundTy
  grounded : ProgramElaboration.ReturnTypeGrounds context functionName surface type

def groundReturn? (context : Context) (functionName : Surface.Name) :
    (surface : Option Surface.TypeExpr) →
      Option (GroundedReturn context functionName surface)
  | none =>
      if main : functionName = "main" then
        some ⟨.scalar (.signed .i32), .mainDefault main⟩
      else some ⟨.unit, .unitDefault main⟩
  | some surfaceType => do
      let grounded ← groundType? context surfaceType
      pure ⟨grounded.type, .value grounded.grounded⟩

def checkStmts (returnType : Static.GroundTy) :
    (context : Context) → (next : VarId) →
    (surface : List Surface.Stmt) → (core : Core.Stmt) →
      Option (CheckedStmtsLowering context next surface core)
  | context, next, [], .skip => some ⟨next, .nil⟩
  | context, next, .expression surfaceExpression :: surfaceTail,
      .sequence (.expression coreExpression) coreTail => do
      let head ← inferExpr context surfaceExpression coreExpression
      let tail ← checkStmts returnType context next surfaceTail coreTail
      pure ⟨tail.finalNext, .expression head.lowered tail.lowered⟩
  | context, next,
      .letLocal name none (some surfaceInitializer) :: surfaceTail,
      .letLocal coreId coreType coreInitializer coreBody => do
      if sameId : coreId = next then
        let fresh ← freshLocalId? context next
        let initializer ← inferExpr context surfaceInitializer coreInitializer
        let mapped ← checkCoreTypeMapping? context initializer.type coreType
        let tail ← checkStmts returnType
          (context.bindLocal name next initializer.type) (next + 1)
          surfaceTail coreBody
        pure ⟨tail.finalNext, by
          subst coreId
          exact .letInferred fresh.proof initializer.lowered mapped.proof tail.lowered⟩
      else none
  | context, next,
      .letLocal name (some surfaceType) (some surfaceInitializer) :: surfaceTail,
      .letLocal coreId coreType coreInitializer coreBody => do
      if sameId : coreId = next then
        let fresh ← freshLocalId? context next
        let annotation ← groundType? context surfaceType
        let initializer ← checkExpr context surfaceInitializer
          annotation.type coreInitializer
        let mapped ← checkCoreTypeMapping? context annotation.type coreType
        let tail ← checkStmts returnType
          (context.bindLocal name next annotation.type) (next + 1)
          surfaceTail coreBody
        pure ⟨tail.finalNext, by
          subst coreId
          exact .letAnnotated fresh.proof annotation.grounded initializer.proof
            mapped.proof tail.lowered⟩
      else none
  | context, next,
      .letLocal name (some surfaceType) none :: surfaceTail,
      .letUninitialized coreId coreType coreBody => do
      if sameId : coreId = next then
        let fresh ← freshLocalId? context next
        let annotation ← groundType? context surfaceType
        let mapped ← checkCoreTypeMapping? context annotation.type coreType
        let tail ← checkStmts returnType
          (context.bindLocal name next annotation.type) (next + 1)
          surfaceTail coreBody
        pure ⟨tail.finalNext, by
          subst coreId
          exact .letUninitialized fresh.proof annotation.grounded mapped.proof
            tail.lowered⟩
      else none
  | context, next, .returnValue none :: surfaceTail,
      .sequence (.returnValue none) coreTail => do
      match groundTypeEq? returnType .unit with
      | some _ =>
        let tail ← checkStmts returnType context next surfaceTail coreTail
        pure ⟨tail.finalNext, .returnUnit tail.lowered⟩
      | none => none
  | context, next, .returnValue (some surfaceValue) :: surfaceTail,
      .sequence (.returnValue (some coreValue)) coreTail => do
      let value ← checkExpr context surfaceValue returnType coreValue
      let tail ← checkStmts returnType context next surfaceTail coreTail
      pure ⟨tail.finalNext, .returnValue value.proof tail.lowered⟩
  | context, next,
      .ifThenElse surfaceCondition surfaceThen surfaceElse :: surfaceTail,
      .sequence (.ifThenElse coreCondition coreThen coreElse) coreTail => do
      let condition ← checkExpr context surfaceCondition (.scalar .bool) coreCondition
      let thenBody ← checkStmts returnType context next surfaceThen coreThen
      let elseBody ← checkStmts returnType context next surfaceElse coreElse
      let tail ← checkStmts returnType context
        (Nat.max thenBody.finalNext elseBody.finalNext) surfaceTail coreTail
      pure ⟨tail.finalNext,
        .ifThenElse condition.proof thenBody.lowered elseBody.lowered tail.lowered⟩
  | context, next, .whileLoop surfaceCondition surfaceBody :: surfaceTail,
      .sequence (.whileLoop coreCondition coreBody) coreTail => do
      let condition ← checkExpr context surfaceCondition (.scalar .bool) coreCondition
      let body ← checkStmts returnType context next surfaceBody coreBody
      let tail ← checkStmts returnType context body.finalNext surfaceTail coreTail
      pure ⟨tail.finalNext, .whileLoop condition.proof body.lowered tail.lowered⟩
  | context, next, .breakLoop :: surfaceTail,
      .sequence .breakLoop coreTail => do
      let tail ← checkStmts returnType context next surfaceTail coreTail
      pure ⟨tail.finalNext, .breakLoop tail.lowered⟩
  | context, next, .continueLoop :: surfaceTail,
      .sequence .continueLoop coreTail => do
      let tail ← checkStmts returnType context next surfaceTail coreTail
      pure ⟨tail.finalNext, .continueLoop tail.lowered⟩
  | context, next, .block surfaceBody :: surfaceTail,
      .sequence coreBody coreTail => do
      let body ← checkStmts returnType context next surfaceBody coreBody
      let tail ← checkStmts returnType context body.finalNext surfaceTail coreTail
      pure ⟨tail.finalNext, .block body.lowered tail.lowered⟩
  | _, _, _, _ => none
termination_by _ _ surface _ => sizeOf surface

structure CheckedFunctionBody
    (context : Context) (surface : Surface.Function) (core : Core.Function) where
  parameterTypes : List Static.GroundTy
  bodyContext : Context
  nextLocal : VarId
  parameters : ProgramElaboration.ParametersLower context none 0
    surface.parameters parameterTypes core.parameters bodyContext nextLocal
  returnType : Static.GroundTy
  returned : ProgramElaboration.ReturnTypeGrounds context surface.name
    surface.returnType returnType
  returnMapped : returnType.toCore context.monomorphization = some core.returnType
  coreBody : Core.Stmt
  bodyPresent : core.body = some coreBody
  finalLocal : VarId
  bodyLowered : StmtsLower bodyContext nextLocal surface.body coreBody finalLocal

def checkFunctionBody (context : Context)
    (surface : Surface.Function) (core : Core.Function) :
    Option (CheckedFunctionBody context surface core) := do
  let parameters ← checkParameters context 0 surface.parameters core.parameters
  let returned ← groundReturn? context surface.name surface.returnType
  let returnMapped ← checkCoreTypeMapping? context returned.type core.returnType
  match bodyPresent : core.body with
  | none => none
  | some coreBody => do
      let body ← checkStmts returned.type parameters.bodyContext
        parameters.finalNext surface.body coreBody
      pure {
        parameterTypes := parameters.groundTypes
        bodyContext := parameters.bodyContext
        nextLocal := parameters.finalNext
        parameters := parameters.lowered
        returnType := returned.type
        returned := returned.grounded
        returnMapped := returnMapped.proof
        coreBody
        bodyPresent
        finalLocal := body.finalNext
        bodyLowered := body.lowered
      }

end Lanius.Extraction.SurfaceElaborationChecker
