import Lanius.SurfaceElaboration
import Lanius.Typing.Check
import Lanius.Compiler.NamedTypeCheck
import Lanius.Compiler.NameResolutionCheck

namespace Lanius.Compiler.TypeLoweringCheck

open Lanius

structure CheckedType (context : SurfaceElaboration.Context)
    (surface : Surface.TypeExpr) (core : Core.Ty) where
  groundType : Static.GroundTy
  typed : Typing.Check.ProofOf (SurfaceElaboration.TypeGrounds context surface groundType)
  grounded : groundType.toCore context.monomorphization = some core

def checkBuiltin (context : SurfaceElaboration.Context)
    (surface : Surface.TypeExpr) (scalar : Core.ScalarTy) :
    Option (Typing.Check.ProofOf
      (SurfaceElaboration.TypeGrounds context surface (.scalar scalar))) :=
  match surface, scalar with
  | .path [.mk "bool" []], .bool => some ⟨.builtin rfl rfl⟩ | .path [.mk "i8" []], .signed .i8 => some ⟨.builtin rfl rfl⟩
  | .path [.mk "i16" []], .signed .i16 => some ⟨.builtin rfl rfl⟩ | .path [.mk "i32" []], .signed .i32 => some ⟨.builtin rfl rfl⟩
  | .path [.mk "i64" []], .signed .i64 => some ⟨.builtin rfl rfl⟩ | .path [.mk "isize" []], .signed .isize => some ⟨.builtin rfl rfl⟩
  | .path [.mk "u8" []], .unsigned .u8 => some ⟨.builtin rfl rfl⟩ | .path [.mk "u16" []], .unsigned .u16 => some ⟨.builtin rfl rfl⟩
  | .path [.mk "u32" []], .unsigned .u32 => some ⟨.builtin rfl rfl⟩ | .path [.mk "u64" []], .unsigned .u64 => some ⟨.builtin rfl rfl⟩
  | .path [.mk "usize" []], .unsigned .usize => some ⟨.builtin rfl rfl⟩ | .path [.mk "f32" []], .f32 => some ⟨.builtin rfl rfl⟩
  | .path [.mk "f64" []], .f64 => some ⟨.builtin rfl rfl⟩ | .path [.mk "char" []], .char => some ⟨.builtin rfl rfl⟩
  | .path [.mk "str" []], .string => some ⟨.builtin rfl rfl⟩ | .path [.mk "ptr" []], .rawPtr => some ⟨.builtin rfl rfl⟩
  | _, _ => none

/- Alias support is kept monomorphic here. The authenticated name-resolution
   witness and the alias entry are both required before the recursive target
   is checked; no spelling-only fallback can manufacture a TypeGrounds proof. -/
structure AliasMatch (entries : List SurfaceElaboration.TypeAliasEntry)
    (declaration : Nat) where
  entry : SurfaceElaboration.TypeAliasEntry
  member : entry ∈ entries
  declarationMatches : entry.declaration = declaration

def findAlias? :
    (entries : List SurfaceElaboration.TypeAliasEntry) → (declaration : Nat) →
    Option (AliasMatch entries declaration)
  | [], _ => none
  | entry :: entries, declaration =>
      if equal : entry.declaration = declaration then
        some {
          entry := entry
          member := by simp
          declarationMatches := equal }
      else
        match findAlias? entries declaration with
        | none => none
        | some found =>
            some {
              entry := found.entry
              member := by simp [found.member]
              declarationMatches := found.declarationMatches }

structure AliasCandidate
    (context : SurfaceElaboration.Context) (path : Surface.Path) where
  symbol : Names.Symbol
  entry : SurfaceElaboration.TypeAliasEntry
  notBuiltin : Elaboration.builtinTypePath? path = none
  notShadowed : SurfaceElaboration.GlobalTypePathNotShadowed context path
  resolved : SurfaceElaboration.ResolvesGlobal context .type path symbol
  member : entry ∈ context.typeAliases
  declaration : entry.declaration = symbol.declaration
  argumentsFound : SurfaceElaboration.pathTypeArguments? path = some []
  parametersEmpty : entry.parameters = []
  requirementsEmpty : entry.requirements = []

def aliasCandidate? (context : SurfaceElaboration.Context)
    (path : Surface.Path) : Option (AliasCandidate context path) :=
  if empty : context.typeParameters.isEmpty then
    match builtin : Elaboration.builtinTypePath? path with
    | some _ => none
    | none =>
        match argumentsFound : SurfaceElaboration.pathTypeArguments? path with
        | none => none
        | some arguments =>
            match arguments with
            | [] =>
                match global : NameResolutionCheck.checkGlobal context .type path with
                | none => none
                | some resolved =>
                    match findAlias? context.typeAliases resolved.symbol.declaration with
                    | none => none
                    | some found =>
                        if parameters : found.entry.parameters.isEmpty then
                          if requirements : found.entry.requirements.isEmpty then
                            some {
                              symbol := resolved.symbol
                              entry := found.entry
                              notBuiltin := builtin
                              notShadowed := by
                                intro name binding _ resolvedParameter
                                have noParameters : context.typeParameters = [] := by
                                  simpa using empty
                                rw [noParameters] at resolvedParameter
                                cases resolvedParameter
                              resolved := resolved.resolved
                              member := found.member
                              declaration := found.declarationMatches
                              argumentsFound := argumentsFound
                              parametersEmpty := by simpa using parameters
                              requirementsEmpty := by simpa using requirements }
                          else none
                        else none
            | _ => none
  else none

structure SchemeMatch (schemes : List Static.NominalScheme)
    (declaration : Nat) where
  scheme : Static.NominalScheme
  member : scheme ∈ schemes
  declarationMatches : scheme.declaration = declaration

def findScheme? :
    (schemes : List Static.NominalScheme) → (declaration : Nat) →
    Option (SchemeMatch schemes declaration)
  | [], _ => none
  | scheme :: schemes, declaration =>
      if equal : scheme.declaration = declaration then
        if unique : schemes.all (fun candidate =>
            decide (candidate.declaration ≠ declaration)) = true then
          some {
            scheme := scheme
            member := by simp
            declarationMatches := equal }
        else none
      else
        match findScheme? schemes declaration with
        | none => none
        | some found =>
            some {
              scheme := found.scheme
              member := by simp [found.member]
              declarationMatches := found.declarationMatches }

def nominalInstanceCompatible (nominal : Static.NominalInstance)
    (sourceType coreType declaration : Nat) (kind : Static.NominalKind) : Bool :=
  decide (nominal.sourceType ≠ sourceType ∨
    nominal.typeArguments ≠ [] ∨ nominal.constArguments ≠ [] ∨
    (nominal.kind = kind ∧ nominal.coreType = coreType ∧
      nominal.declaration = declaration))

theorem nominalInstanceCompatible_of_all
    {instances : List Static.NominalInstance}
    {nominal : Static.NominalInstance}
    {sourceType coreType declaration : Nat} {kind : Static.NominalKind}
    (all : instances.all (fun candidate =>
      nominalInstanceCompatible candidate sourceType coreType declaration kind) = true)
    (member : nominal ∈ instances)
    (source : nominal.sourceType = sourceType)
    (types : nominal.typeArguments = [])
    (constants : nominal.constArguments = []) :
    nominal.kind = kind ∧ nominal.coreType = coreType ∧
      nominal.declaration = declaration := by
  have found := List.all_eq_true.mp all nominal member
  have compatible : nominal.sourceType ≠ sourceType ∨
      nominal.typeArguments ≠ [] ∨ nominal.constArguments ≠ [] ∨
      (nominal.kind = kind ∧ nominal.coreType = coreType ∧
        nominal.declaration = declaration) := by
    simpa [nominalInstanceCompatible] using (of_decide_eq_true found)
  rcases compatible with sourceNot | typesNot | constantsNot | shape
  · exact False.elim (sourceNot source)
  · exact False.elim (typesNot types)
  · exact False.elim (constantsNot constants)
  · exact shape

structure NominalMatch (instances : List Static.NominalInstance)
    (sourceType coreType declaration : Nat) (kind : Static.NominalKind) where
  nominal : Static.NominalInstance
  member : nominal ∈ instances
  sourceTypeMatches : nominal.sourceType = sourceType
  typeArgumentsEmpty : nominal.typeArguments = []
  constArgumentsEmpty : nominal.constArguments = []
  kindMatches : nominal.kind = kind
  coreTypeMatches : nominal.coreType = coreType
  declarationMatches : nominal.declaration = declaration
  compatible : ∀ candidate, candidate ∈ instances →
    candidate.sourceType = sourceType → candidate.typeArguments = [] →
    candidate.constArguments = [] →
    candidate.kind = kind ∧ candidate.coreType = coreType ∧
      candidate.declaration = declaration

def findNominal? :
    (instances : List Static.NominalInstance) →
    (sourceType coreType declaration : Nat) → (kind : Static.NominalKind) →
    Option (NominalMatch instances sourceType coreType declaration kind)
  | [], _, _, _, _ => none
  | nominal :: instances, sourceType, coreType, declaration, kind =>
      if arguments : nominal.sourceType = sourceType ∧
          nominal.typeArguments = [] ∧ nominal.constArguments = [] then
        if shape : nominal.kind = kind ∧
            nominal.coreType = coreType ∧ nominal.declaration = declaration then
          if compatible : instances.all (fun candidate =>
              nominalInstanceCompatible candidate sourceType coreType declaration kind) = true then
            some {
              nominal := nominal
              member := by simp
              sourceTypeMatches := arguments.1
              typeArgumentsEmpty := arguments.2.1
              constArgumentsEmpty := arguments.2.2
              kindMatches := shape.1
              coreTypeMatches := shape.2.1
              declarationMatches := shape.2.2
              compatible := by
                intro candidate member source types constants
                have member' : candidate = nominal ∨ candidate ∈ instances := by
                  simpa using member
                rcases member' with rfl | member'
                · exact ⟨shape.1, shape.2.1, shape.2.2⟩
                · exact nominalInstanceCompatible_of_all compatible
                    member' source types constants }
          else none
        else none
      else
        match findNominal? instances sourceType coreType declaration kind with
        | none => none
        | some found =>
            some {
              nominal := found.nominal
              member := by simp [found.member]
              sourceTypeMatches := found.sourceTypeMatches
              typeArgumentsEmpty := found.typeArgumentsEmpty
              constArgumentsEmpty := found.constArgumentsEmpty
              kindMatches := found.kindMatches
              coreTypeMatches := found.coreTypeMatches
              declarationMatches := found.declarationMatches
              compatible := by
                intro candidate member source types constants
                have member' : candidate = nominal ∨ candidate ∈ instances := by
                  simpa using member
                rcases member' with (rfl | member')
                · exact False.elim (by
                    exact arguments ⟨source, types, constants⟩)
                · exact found.compatible candidate member' source types constants }

def nominalCandidate? (context : SurfaceElaboration.Context)
    (path : Surface.Path) (coreType : TypeId) (kind : Static.NominalKind) :
    Option (NamedTypeCheck.Candidate context path) :=
  if empty : context.typeParameters.isEmpty then
    match builtin : Elaboration.builtinTypePath? path with
    | some _ => none
    | none =>
        match argumentsFound : SurfaceElaboration.pathTypeArguments? path with
        | none => none
        | some [] =>
            match global : NameResolutionCheck.checkGlobal context .type path with
            | none => none
            | some resolved =>
                match findScheme? context.nominalSchemes resolved.symbol.declaration with
                | none => none
                | some scheme =>
                    if parameters : scheme.scheme.genericParameters.isEmpty then
                      if requirements : scheme.scheme.requirements.isEmpty then
                        if sameKind : scheme.scheme.kind = kind then
                            match findNominal? context.nominalInstances
                                scheme.scheme.type coreType scheme.scheme.declaration kind with
                            | none => none
                            | some nominal =>
                                if mapped : context.monomorphization.resolveNominal
                                    scheme.scheme.type [] [] =
                                      some (match kind with
                                        | .structure => .structure coreType
                                        | .enumeration => .enumeration coreType) then
                                  have parametersEmpty :
                                      scheme.scheme.genericParameters = [] := by
                                    simpa using parameters
                                  have requirementsEmpty :
                                      scheme.scheme.requirements = [] := by
                                    simpa using requirements
                                  some {
                                    symbol := resolved.symbol
                                    scheme := scheme.scheme
                                    resolvedInstance := nominal.nominal
                                    notBuiltin := builtin
                                    notShadowed := by
                                      intro name binding _ resolvedParameter
                                      have noParameters : context.typeParameters = [] := by
                                        simpa using empty
                                      rw [noParameters] at resolvedParameter
                                      cases resolvedParameter
                                    resolved := resolved.resolved
                                    schemeMember := scheme.member
                                    declaration := scheme.declarationMatches
                                    surfaceArguments := []
                                    argumentsFound := argumentsFound
                                    arguments := by
                                      rw [parametersEmpty, nominal.typeArgumentsEmpty,
                                        nominal.constArgumentsEmpty]
                                      exact .nil
                                    instantiated := by
                                      refine ⟨nominal.member, ?_, ?_, ?_, ?_, ?_, ?_⟩
                                      · exact nominal.declarationMatches
                                      · exact nominal.sourceTypeMatches
                                      · exact nominal.kindMatches.trans sameKind.symm
                                      · rw [parametersEmpty, nominal.typeArgumentsEmpty,
                                          nominal.constArgumentsEmpty]
                                        exact .nil
                                      · rw [requirementsEmpty]
                                        exact .nil
                                      · intro candidate member source types constants
                                        have source' := source
                                        have types' : candidate.typeArguments = [] := by
                                          simpa [nominal.typeArgumentsEmpty] using types
                                        have constants' : candidate.constArguments = [] := by
                                          simpa [nominal.constArgumentsEmpty] using constants
                                        exact (nominal.compatible candidate member source' types' constants').2.1.trans
                                          nominal.coreTypeMatches.symm
                                    mapped := by
                                      cases kind <;> simpa [Static.NominalInstanceMapped,
                                        Static.NominalInstance.coreTy,
                                        nominal.sourceTypeMatches,
                                        nominal.typeArgumentsEmpty,
                                        nominal.constArgumentsEmpty,
                                        nominal.kindMatches,
                                        nominal.coreTypeMatches] using mapped }
                                else none
                        else none
                      else none
                    else none
        | some _ => none
  else none

def checkNominal (context : SurfaceElaboration.Context)
    (path : Surface.Path) (core : Core.Ty)
    (candidate : NamedTypeCheck.Candidate context path) :
    Option (CheckedType context (.path path.segments) core) :=
  (NamedTypeCheck.check context path core candidate).map fun checked => {
    groundType := checked.groundType
    typed := checked.typed
    grounded := checked.grounded }

def typeFuel : Surface.TypeExpr → Nat
  | .path _ => 1
  | .array element _ => typeFuel element + 1
  | .slice element => typeFuel element + 1
  | .reference referent => typeFuel referent + 1

def aliasFuel : List SurfaceElaboration.TypeAliasEntry → Nat
  | [] => 1
  | entry :: entries => typeFuel entry.target + aliasFuel entries

def wrapAlias {context : SurfaceElaboration.Context} {path : Surface.Path}
    (candidate : AliasCandidate context path) {core : Core.Ty}
    (target : CheckedType (context.forTypeAlias candidate.entry {})
      candidate.entry.target core) : CheckedType context (.path path.segments) core :=
  {
    groundType := target.groundType
    typed := ⟨.typeAlias candidate.symbol candidate.notBuiltin
      candidate.notShadowed candidate.resolved candidate.member
      candidate.declaration candidate.argumentsFound {}
      (by
        rw [candidate.parametersEmpty]
        exact .nil)
      (by
        rw [candidate.requirementsEmpty]
        exact .nil)
      target.typed.down⟩
    grounded := target.grounded }

def checkFuel : Nat → (context : SurfaceElaboration.Context) →
    (surface : Surface.TypeExpr) → (core : Core.Ty) →
    Option (CheckedType context surface core)
  | 0, _, _, _ => none
  | fuel + 1, context, surface, core =>
      match surface, core with
      | .path segments, .scalar scalar =>
          match checkBuiltin context (.path segments) scalar with
          | some typed =>
              some {
                groundType := .scalar scalar
                typed := typed
                grounded := rfl }
          | none =>
              match aliasCandidate? context { segments := segments } with
              | none => none
              | some candidate =>
                  match checkFuel fuel (context.forTypeAlias candidate.entry {})
                      candidate.entry.target (.scalar scalar) with
                  | none => none
                  | some target => some (wrapAlias candidate target)
      | .path segments, .structure typeId =>
          match aliasCandidate? context { segments := segments } with
          | some candidate =>
              match checkFuel fuel (context.forTypeAlias candidate.entry {})
                  candidate.entry.target (.structure typeId) with
              | none => none
              | some target => some (wrapAlias candidate target)
          | none =>
              match nominalCandidate? context { segments := segments } typeId .structure with
              | none => none
              | some candidate =>
                  checkNominal context { segments := segments } (.structure typeId) candidate
      | .path segments, .enumeration typeId =>
          match aliasCandidate? context { segments := segments } with
          | some candidate =>
              match checkFuel fuel (context.forTypeAlias candidate.entry {})
                  candidate.entry.target (.enumeration typeId) with
              | none => none
              | some target => some (wrapAlias candidate target)
          | none =>
              match nominalCandidate? context { segments := segments } typeId .enumeration with
              | none => none
              | some candidate =>
                  checkNominal context { segments := segments } (.enumeration typeId) candidate
      | .path segments, .slice coreElement =>
          match aliasCandidate? context { segments := segments } with
          | none => none
          | some candidate =>
              match checkFuel fuel (context.forTypeAlias candidate.entry {})
                  candidate.entry.target (.slice coreElement) with
              | none => none
              | some target => some (wrapAlias candidate target)
      | .path segments, .reference coreReferent =>
          match aliasCandidate? context { segments := segments } with
          | none => none
          | some candidate =>
              match checkFuel fuel (context.forTypeAlias candidate.entry {})
                  candidate.entry.target (.reference coreReferent) with
              | none => none
              | some target => some (wrapAlias candidate target)
      | .path segments, .array coreElement length =>
          match aliasCandidate? context { segments := segments } with
          | none => none
          | some candidate =>
              match checkFuel fuel (context.forTypeAlias candidate.entry {})
                  candidate.entry.target (.array coreElement length) with
              | none => none
              | some target => some (wrapAlias candidate target)
      | .slice surfaceElement, .slice coreElement =>
          (checkFuel fuel context surfaceElement coreElement).map fun element => {
            groundType := .slice element.groundType
            typed := ⟨.slice element.typed.down⟩
            grounded := by simp [Static.GroundTy.toCore, element.grounded] }
      | .reference surfaceReferent, .reference coreReferent =>
          (checkFuel fuel context surfaceReferent coreReferent).map fun referent => {
            groundType := .reference referent.groundType
            typed := ⟨.reference referent.typed.down⟩
            grounded := by simp [Static.GroundTy.toCore, referent.grounded] }
      | .array surfaceElement (.literal length), .array coreElement length' =>
          if equal : length = length' then
            (checkFuel fuel context surfaceElement coreElement).map fun element => {
              groundType := .array element.groundType length
              typed := ⟨by simpa [equal] using
                (SurfaceElaboration.TypeGrounds.array element.typed.down .literal)⟩
              grounded := by simp [Static.GroundTy.toCore, equal, element.grounded] }
          else none
      | _, _ => none

def check (context : SurfaceElaboration.Context)
    (surface : Surface.TypeExpr) (core : Core.Ty) :
    Option (CheckedType context surface core) :=
  checkFuel (typeFuel surface + aliasFuel context.typeAliases) context surface core

def checkGround (context : SurfaceElaboration.Context) :
    (surface : Surface.TypeExpr) → (ground : Static.GroundTy) →
    Option (Typing.Check.ProofOf (SurfaceElaboration.TypeGrounds context surface ground)) :=
  fun surface ground =>
    match ground.toCore context.monomorphization with
    | none => none
    | some core =>
        match checked : check context surface core with
        | none => none
        | some result =>
            if equal : result.groundType = ground then
              some ⟨by simpa [equal] using result.typed.down⟩
            else none

/- Named paths require caller-supplied lookup, scheme, and monomorphization
   evidence.  Keep that evidence-bearing entry point separate from the compact
   builtin/container checker so callers cannot accidentally guess a nominal
   declaration. -/
def checkNamed (context : SurfaceElaboration.Context)
    (path : Surface.Path) (core : Core.Ty)
    (candidate : NamedTypeCheck.Candidate context path) :
    Option (CheckedType context (.path path.segments) core) :=
  (NamedTypeCheck.check context path core candidate).map fun checked => {
    groundType := checked.groundType
    typed := checked.typed
    grounded := checked.grounded }

end Lanius.Compiler.TypeLoweringCheck
