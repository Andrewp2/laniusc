import Lanius.Names
import Lanius.SurfaceElaboration

namespace Lanius.Compiler.NameResolutionCheck

open Lanius

/-!
The executable name checker deliberately works from the four candidate rules in
`Names.Candidate`, rather than relying on a singleton list.  A duplicate symbol
is harmless; only a candidate with a different declaration (or namespace) is
rejected.  The returned structures contain the ordinary kernel-checked
`Names.Resolves`/`ResolvesGlobal` witnesses.
-/

def symbolMatches (symbol : Names.Symbol) (module : ModuleId)
    (lookupNamespace : Names.LookupNamespace) (name : String) : Bool :=
  decide (symbol.moduleId = module ∧ symbol.lookupNamespace = lookupNamespace ∧ symbol.name = name)

def hasLocal (environment : Names.Environment) (current : ModuleId)
    (lookupNamespace : Names.LookupNamespace) (name : String) : Bool :=
  environment.symbols.any (fun symbol => symbolMatches symbol current lookupNamespace name)

def moduleExists (environment : Names.Environment) (module : ModuleId) : Bool :=
  environment.modules.any (fun found => decide (found.id = module))

def modulePathExists (environment : Names.Environment) (path : Names.ModulePath)
    (module : ModuleId) : Bool :=
  environment.modules.any (fun found => decide (found.path = path ∧ found.id = module))

def importExists (environment : Names.Environment) (importer imported : ModuleId) : Bool :=
  environment.imports.any (fun declaration =>
    decide (declaration.importer = importer ∧ declaration.imported = imported))

def candidateAccepts (environment : Names.Environment) (current : ModuleId)
    (reference : Names.Reference) (symbol : Names.Symbol) : Bool :=
  match reference with
  | .unqualified lookupNamespace name =>
      symbolMatches symbol current lookupNamespace name ||
        (!hasLocal environment current lookupNamespace name &&
          moduleExists environment symbol.moduleId &&
          importExists environment current symbol.moduleId &&
          decide (symbol.visibility = .exported) &&
          decide (symbol.lookupNamespace = lookupNamespace ∧ symbol.name = name))
  | .qualified lookupNamespace path name =>
      (modulePathExists environment path current &&
        symbolMatches symbol current lookupNamespace name) ||
      (modulePathExists environment path symbol.moduleId &&
        importExists environment current symbol.moduleId &&
        decide (symbol.visibility = .exported) &&
        decide (symbol.lookupNamespace = lookupNamespace ∧ symbol.name = name))

def candidates (environment : Names.Environment) (current : ModuleId)
    (reference : Names.Reference) : List Names.Symbol :=
  environment.symbols.filter (candidateAccepts environment current reference)

theorem symbolMatches_iff {symbol : Names.Symbol} :
    symbolMatches symbol module lookupNamespace name = true ↔
      symbol.moduleId = module ∧ symbol.lookupNamespace = lookupNamespace ∧ symbol.name = name := by
  simp [symbolMatches]

theorem hasLocal_iff :
    hasLocal environment current lookupNamespace name = true ↔
      Names.HasLocalDeclaration environment current lookupNamespace name := by
  simp [hasLocal, Names.HasLocalDeclaration, symbolMatches, List.any_eq_true]

theorem moduleExists_iff :
    moduleExists environment module = true ↔
      ∃ found, found ∈ environment.modules ∧ found.id = module := by
  simp [moduleExists, List.any_eq_true]

theorem modulePathExists_iff :
    modulePathExists environment path module = true ↔
      ∃ found, found ∈ environment.modules ∧ found.path = path ∧ found.id = module := by
  simp [modulePathExists, List.any_eq_true]

theorem importExists_iff :
    importExists environment importer imported = true ↔
      environment.importsModule importer imported := by
  simp [importExists, Names.Environment.importsModule, List.any_eq_true]

theorem candidates_mem_iff :
    symbol ∈ candidates environment current reference ↔
      Names.Candidate environment current reference symbol := by
  constructor
  · intro member
    have accepted := (List.mem_filter.mp member).2
    have symbolMember := (List.mem_filter.mp member).1
    cases reference with
    | unqualified lookupNamespace name =>
        simp only [candidateAccepts, Bool.or_eq_true, Bool.and_eq_true] at accepted
        rcases accepted with localCandidate | imported
        · apply Names.Candidate.local symbolMember
          exact (symbolMatches_iff.mp localCandidate).1
          exact (symbolMatches_iff.mp localCandidate).2.1
          exact (symbolMatches_iff.mp localCandidate).2.2
        · have noLocal : ¬ Names.HasLocalDeclaration environment current lookupNamespace name := by
            intro localDeclaration
            have : hasLocal environment current lookupNamespace name = true :=
              hasLocal_iff.mpr localDeclaration
            simp_all
          have moduleFound := moduleExists_iff.mp imported.1.1.1.2
          have importFound := importExists_iff.mp imported.1.1.2
          have isPublic : symbol.visibility = .exported := by simpa using imported.1.2
          have shape : symbol.lookupNamespace = lookupNamespace ∧ symbol.name = name := by
            simpa using imported.2
          rcases moduleFound with ⟨module, moduleMember, moduleId⟩
          have importFound' : environment.importsModule current module.id := by
            simpa [moduleId] using importFound
          exact .importedUnqualified module moduleMember importFound' noLocal symbolMember
            (moduleId ▸ rfl) isPublic shape.1 shape.2
    | qualified lookupNamespace path name =>
        simp only [candidateAccepts, Bool.or_eq_true, Bool.and_eq_true] at accepted
        rcases accepted with own | imported
        · have moduleFound := modulePathExists_iff.mp own.1
          have shape := symbolMatches_iff.mp own.2
          rcases moduleFound with ⟨module, moduleMember, modulePath, moduleId⟩
          exact .ownQualified module moduleMember modulePath moduleId symbolMember
            (moduleId ▸ shape.1) shape.2.1 shape.2.2
        · have moduleFound := modulePathExists_iff.mp imported.1.1.1
          have importFound := importExists_iff.mp imported.1.1.2
          have isPublic : symbol.visibility = .exported := by simpa using imported.1.2
          have shape : symbol.lookupNamespace = lookupNamespace ∧ symbol.name = name := by
            simpa using imported.2
          rcases moduleFound with ⟨module, moduleMember, modulePath, moduleId⟩
          have importFound' : environment.importsModule current module.id := by
            simpa [moduleId] using importFound
          exact .importedQualified module moduleMember modulePath importFound' symbolMember
            (moduleId ▸ rfl) isPublic shape.1 shape.2
  · intro candidate
    cases reference with
    | unqualified lookupNamespace name =>
        cases candidate with
        | «local» member sameModule sameNamespace sameName =>
            apply List.mem_filter.mpr
            refine ⟨member, ?_⟩
            simp [candidateAccepts, symbolMatches, sameModule, sameNamespace, sameName]
        | importedUnqualified module moduleMember imported noLocal member symbolModule isPublic
            sameNamespace sameName =>
            apply List.mem_filter.mpr
            refine ⟨member, ?_⟩
            have moduleFound : moduleExists environment module.id = true :=
              moduleExists_iff.mpr ⟨module, moduleMember, rfl⟩
            have importFound : importExists environment current module.id = true :=
              importExists_iff.mpr imported
            have noLocalBool : hasLocal environment current lookupNamespace name = false := by
              apply Bool.eq_false_iff.mpr
              intro found
              exact noLocal (hasLocal_iff.mp (by simpa [found]))
            simp [candidateAccepts, symbolMatches, moduleFound, importFound, noLocalBool,
              symbolModule, isPublic, sameNamespace, sameName]
    | qualified lookupNamespace path name =>
        cases candidate with
        | ownQualified module moduleMember modulePath isCurrent member symbolModule sameNamespace
            sameName =>
            apply List.mem_filter.mpr
            refine ⟨member, ?_⟩
            have moduleFound : modulePathExists environment path current = true :=
              modulePathExists_iff.mpr ⟨module, moduleMember, modulePath, isCurrent⟩
            simp [candidateAccepts, symbolMatches, moduleFound, symbolModule, isCurrent,
              sameNamespace, sameName]
        | importedQualified module moduleMember modulePath imported member symbolModule isPublic
            sameNamespace sameName =>
            apply List.mem_filter.mpr
            refine ⟨member, ?_⟩
            have moduleFound : modulePathExists environment path module.id = true :=
              modulePathExists_iff.mpr ⟨module, moduleMember, modulePath, rfl⟩
            have importFound : importExists environment current module.id = true :=
              importExists_iff.mpr imported
            simp [candidateAccepts, symbolMatches, moduleFound, importFound, symbolModule,
              isPublic, sameNamespace, sameName]

def sameDeclaration (selected candidate : Names.Symbol) : Bool :=
  decide (candidate.lookupNamespace = selected.lookupNamespace ∧
    candidate.declaration = selected.declaration)

structure Checked (environment : Names.Environment) (current : ModuleId)
    (reference : Names.Reference) where
  symbol : Names.Symbol
  resolved : Names.Resolves environment current reference symbol

def check (environment : Names.Environment) (current : ModuleId)
    (reference : Names.Reference) : Option (Checked environment current reference) :=
  match selected : candidates environment current reference with
  | [] => none
  | symbol :: _ =>
      if coherent : (candidates environment current reference).all (sameDeclaration symbol) then
        some {
          symbol := symbol
          resolved := by
            refine ⟨candidates_mem_iff.mp (by simp [selected]), ?_⟩
            intro candidate candidateResolved
            have member : candidate ∈ candidates environment current reference :=
              candidates_mem_iff.mpr candidateResolved
            have equality := List.all_eq_true.mp coherent candidate member
            exact of_decide_eq_true equality
        }
      else none

structure GlobalChecked (context : SurfaceElaboration.Context)
    (lookupNamespace : Names.LookupNamespace) (path : Surface.Path) where
  symbol : Names.Symbol
  resolved : SurfaceElaboration.ResolvesGlobal context lookupNamespace path symbol

def checkGlobal (context : SurfaceElaboration.Context) (lookupNamespace : Names.LookupNamespace)
    (path : Surface.Path) : Option (GlobalChecked context lookupNamespace path) :=
  match formed : Names.Reference.fromSurfacePath? lookupNamespace path with
  | none => none
  | some reference =>
      match check context.names context.currentModule reference with
      | none => none
      | some result =>
          some {
            symbol := result.symbol
            resolved := .intro reference formed result.resolved
          }

end Lanius.Compiler.NameResolutionCheck
