import Lanius.Compiler.ProgramLowering

namespace Lanius.Compiler.ContextSynthesis

open Lanius
open Lanius.Declarations
open Lanius.Compiler.ProgramLowering

/-!
`ProgramLoweringCheck` consumes a context as a semantic catalog.  The old
boundary left that catalog as an untrusted argument, which made it possible
for a caller to pair a source row with a different function/type ID.  This
module is the small, executable bridge from checked declaration rows to that
catalog.  It intentionally has no generic or trait machinery: all rows in the
supported front-end subset are monomorphic.
-/

mutual
  /-- The ground representation of a Core type in the monomorphic subset. -/
  def groundOfCore : Core.Ty → Static.GroundTy
    | .unit => .unit
    | .scalar scalar => .scalar scalar
    | .array element length => .array (groundOfCore element) length
    | .slice element => .slice (groundOfCore element)
    | .reference referent => .reference (groundOfCore referent)
    | .structure id => .nominal id [] []
    | .enumeration id => .nominal id [] []

  def groundsOfCore : List Core.Ty → List Static.GroundTy
    | [] => []
    | head :: tail => groundOfCore head :: groundsOfCore tail
end

@[simp] theorem groundsOfCore_eq_map (types : List Core.Ty) :
    groundsOfCore types = types.map groundOfCore := by
  induction types with
  | nil => rfl
  | cons head tail ih => simp [groundsOfCore, ih]

def firstModule : List Declarations.SourceFile → ModuleId
  | [] => 0
  | file :: _ => file.moduleInfo.id

def functionScheme (row : DeclarationLowering pack catalog program) :
    Option Static.FunctionScheme :=
  match row.core with
  | .function declaration => some {
      declaration := row.header.declaration
      genericParameters := []
      parameterTypes := declaration.parameters.map (fun parameter =>
        (groundOfCore parameter.2).toTy)
      returnType := (groundOfCore declaration.returnType).toTy
      requirements := [] }
  | .structure _ | .enumeration _ | .constant _ => none

def functionInstance (row : DeclarationLowering pack catalog program) :
    Option Static.FunctionInstance :=
  match row.core with
  | .function declaration => some {
      declaration := row.header.declaration
      function := declaration.id
      typeArguments := []
      constArguments := []
      parameterTypes := groundsOfCore (declaration.parameters.map Prod.snd)
      returnType := groundOfCore declaration.returnType }
  | .structure _ | .enumeration _ | .constant _ => none

def enumVariantHeaderIds (catalog : Declarations.Catalog)
    (address : Declarations.ItemAddress) : List Nat :=
  catalog.headers.filterMap fun header =>
    match header.source with
    | .enumVariant parent _ =>
        if parent == address then some header.declaration else none
    | _ => none

def nominalScheme (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (row : DeclarationLowering pack catalog program) :
    Option Static.NominalScheme :=
  match row.occurrence, row.core with
  | .item address, .structure declaration =>
      match pack.item? address with
      | some (.structure source) => some {
          declaration := row.header.declaration
          type := declaration.id
          kind := .structure
          isPublic := source.isPublic
          genericParameters := []
          requirements := []
          memberDeclarations := [] }
      | _ => none
  | .item address, .enumeration declaration =>
      match pack.item? address with
      | some (.enumeration source) => some {
          declaration := row.header.declaration
          type := declaration.id
          kind := .enumeration
          isPublic := source.isPublic
          genericParameters := []
          requirements := []
          memberDeclarations := enumVariantHeaderIds catalog address }
      | _ => none
  | _, _ => none

def nominalInstance (row : DeclarationLowering pack catalog program) :
    Option Static.NominalInstance :=
  match row.core with
  | .structure declaration => some {
      declaration := row.header.declaration
      sourceType := declaration.id
      kind := .structure
      typeArguments := []
      constArguments := []
      coreType := declaration.id }
  | .enumeration declaration => some {
      declaration := row.header.declaration
      sourceType := declaration.id
      kind := .enumeration
      typeArguments := []
      constArguments := []
      coreType := declaration.id }
  | .function _ | .constant _ => none

def constantEntry (row : DeclarationLowering pack catalog program) :
    Option SurfaceElaboration.ConstantEntry :=
  match row.core with
  | .constant declaration => some {
      declaration := row.header.declaration
      constant := declaration.id
      type := groundOfCore declaration.type }
  | .structure _ | .enumeration _ | .function _ => none

def structFieldEntries (receiver : Static.GroundTy) (start : FieldId)
    (surface : List Surface.StructField) (core : List Core.Ty) :
    List SurfaceElaboration.FieldEntry :=
  match surface, core with
  | surfaceHead :: surfaceTail, coreHead :: coreTail =>
      { receiver := receiver
        name := surfaceHead.name
        field := start
        type := groundOfCore coreHead } ::
        structFieldEntries receiver (start + 1) surfaceTail coreTail
  | _, _ => []

def structureFields (pack : Declarations.SourcePack)
    (row : DeclarationLowering pack catalog program) :
    List SurfaceElaboration.FieldEntry :=
  match row.occurrence, row.core with
  | .item address, .structure declaration =>
      match pack.item? address with
      | some (.structure source) =>
          structFieldEntries (.nominal declaration.id [] []) 0 source.fields declaration.fields
      | _ => []
  | _, _ => []

def structureEntry (row : DeclarationLowering pack catalog program) :
    Option SurfaceElaboration.StructEntry :=
  match row.core with
  | .structure declaration => some {
      declaration := row.header.declaration
      receiver := .nominal declaration.id [] []
      coreType := declaration.id
      fieldOrder := List.range declaration.fields.length }
  | .enumeration _ | .constant _ | .function _ => none

def enumVariantRowsAt (catalog : Declarations.Catalog)
    (parent : Declarations.ItemAddress) (nominalDeclaration : Nat)
    (coreType : TypeId) : Nat → List (List Core.Ty) →
      List (SurfaceElaboration.VariantEntry ×
        SurfaceElaboration.VariantConstructorScheme)
  | _, [] => []
  | index, payload :: tail =>
      let rest := enumVariantRowsAt catalog parent nominalDeclaration
        coreType (index + 1) tail
      match catalog.headers.find? (fun header =>
          header.source == .enumVariant parent index) with
      | none => rest
      | some header =>
          ({ declaration := header.declaration
             receiver := .nominal coreType [] []
             coreType := coreType
             variant := index
             payload := groundsOfCore payload },
           { declaration := header.declaration
             nominalDeclaration := nominalDeclaration
             sourceType := coreType
             variant := index
             payload := (groundsOfCore payload).map Static.GroundTy.toTy }) :: rest

def enumVariantRows (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (row : DeclarationLowering pack catalog program) :
    List (SurfaceElaboration.VariantEntry ×
      SurfaceElaboration.VariantConstructorScheme) :=
  match row.occurrence, row.core with
  | .item address, .enumeration declaration =>
      match pack.item? address with
      | some (.enumeration _) =>
          enumVariantRowsAt catalog address row.header.declaration
            declaration.id 0 declaration.variants
      | _ => []
  | _, _ => []

def aliasEntry (alias : TypeAliasLowering pack catalog) :
    SurfaceElaboration.TypeAliasEntry := {
      declaration := alias.header.declaration
      moduleId := alias.header.moduleId
      parameters := []
      requirements := []
      target := alias.target }

def monomorphization (program : Core.Program) : Static.Monomorphization := {
  resolveNominal := fun id typeArguments constArguments =>
    match typeArguments, constArguments with
    | [], [] =>
        match program.enumeration? id, program.structure? id with
        | some _, none => some (.enumeration id)
        | none, some _ => some (.structure id)
        | _, _ => none
    | _, _ => none }

def environment (pack : Declarations.SourcePack) (catalog : Declarations.Catalog)
    (imports : List Declarations.CollectedImport) : Names.Environment :=
  Declarations.nameEnvironment pack catalog imports

def synthesize
    (pack : Declarations.SourcePack) (catalog : Declarations.Catalog)
    (imports : List Declarations.CollectedImport) (program : Core.Program)
    (rows : List (DeclarationLowering pack catalog program))
    (aliases : List (TypeAliasLowering pack catalog)) :
    SurfaceElaboration.Context :=
  let names := environment pack catalog imports
  let variantRows := rows.flatMap (enumVariantRows pack catalog)
  { target := program.target
    names := names
    currentModule := firstModule pack.files
    monomorphization := monomorphization program
    functions := rows.filterMap functionScheme
    functionInstances := rows.filterMap functionInstance
    constants := rows.filterMap constantEntry
    fields := rows.flatMap (structureFields pack)
    nominalSchemes := rows.filterMap (nominalScheme pack catalog)
    nominalInstances := rows.filterMap nominalInstance
    typeAliases := aliases.map aliasEntry
    structures := rows.filterMap structureEntry
    variants := variantRows.map Prod.fst
    variantConstructors := variantRows.map Prod.snd }

/- The option wrapper is useful at executable boundaries.  It is deliberately
   total for checked declarations: all rejection belongs to the declaration
   and typing checkers, never to an unchecked caller-supplied context. -/
def synthesize?
    (pack : Declarations.SourcePack) (catalog : Declarations.Catalog)
    (imports : List Declarations.CollectedImport) (program : Core.Program)
    (rows : List (DeclarationLowering pack catalog program))
    (aliases : List (TypeAliasLowering pack catalog)) :
    Option SurfaceElaboration.Context :=
  some (synthesize pack catalog imports program rows aliases)

structure Checked
    (pack : Declarations.SourcePack) (catalog : Declarations.Catalog)
    (imports : List Declarations.CollectedImport) (program : Core.Program)
    (rows : List (DeclarationLowering pack catalog program))
    (aliases : List (TypeAliasLowering pack catalog)) where
  context : SurfaceElaboration.Context := synthesize pack catalog imports program rows aliases
  names : context.names = environment pack catalog imports
  target : context.target = program.target
  noTypeParameters : context.typeParameters = []
  noConstParameters : context.constParameters = []
  emptySubstitution : context.substitution = {}

def checked
    (pack : Declarations.SourcePack) (catalog : Declarations.Catalog)
    (imports : List Declarations.CollectedImport) (program : Core.Program)
    (rows : List (DeclarationLowering pack catalog program))
    (aliases : List (TypeAliasLowering pack catalog)) :
    Checked pack catalog imports program rows aliases := by
  let context := synthesize pack catalog imports program rows aliases
  refine ⟨context, ?_, ?_, ?_, ?_, ?_⟩
  · rfl
  · rfl
  · rfl
  · rfl
  · rfl

theorem synthesize_names
    (pack : Declarations.SourcePack) (catalog : Declarations.Catalog)
    (imports : List Declarations.CollectedImport) (program : Core.Program)
    (rows : List (DeclarationLowering pack catalog program))
    (aliases : List (TypeAliasLowering pack catalog)) :
    (synthesize pack catalog imports program rows aliases).names =
      Declarations.nameEnvironment pack catalog imports := rfl

theorem synthesize_target
    (pack : Declarations.SourcePack) (catalog : Declarations.Catalog)
    (imports : List Declarations.CollectedImport) (program : Core.Program)
    (rows : List (DeclarationLowering pack catalog program))
    (aliases : List (TypeAliasLowering pack catalog)) :
    (synthesize pack catalog imports program rows aliases).target = program.target := rfl

/- These compact membership witnesses are the facts consumed by the existing
   lowering checkers.  They are proved from the map/filterMap construction,
   rather than accepted as fields supplied by a caller. -/
theorem function_rows_have_tables
    (pack : Declarations.SourcePack) (catalog : Declarations.Catalog)
    (imports : List Declarations.CollectedImport) (program : Core.Program)
    (rows : List (DeclarationLowering pack catalog program))
    (aliases : List (TypeAliasLowering pack catalog))
    {row : DeclarationLowering pack catalog program} (member : row ∈ rows)
    (function : Core.Function) (core : row.core = .function function) :
    ∃ scheme resolved,
      scheme ∈ (synthesize pack catalog imports program rows aliases).functions ∧
      resolved ∈ (synthesize pack catalog imports program rows aliases).functionInstances ∧
      scheme.declaration = row.header.declaration ∧
      resolved.declaration = row.header.declaration ∧ resolved.function = function.id := by
  cases h : row.core with
  | «structure» declaration => simp [h] at core
  | enumeration declaration => simp [h] at core
  | constant declaration => simp [h] at core
  | function declaration =>
    simp only [h] at core
    cases core
    refine ⟨{ declaration := row.header.declaration
              genericParameters := []
              parameterTypes := function.parameters.map (fun parameter =>
                (groundOfCore parameter.2).toTy)
              returnType := (groundOfCore function.returnType).toTy
              requirements := [] },
            { declaration := row.header.declaration
              function := function.id
              typeArguments := []
              constArguments := []
              parameterTypes := groundsOfCore (function.parameters.map Prod.snd)
              returnType := groundOfCore function.returnType }, ?_, ?_, rfl, rfl, rfl⟩
    · change _ ∈ rows.filterMap functionScheme
      apply List.mem_filterMap.mpr
      refine ⟨row, member, ?_⟩
      simp [functionScheme, h]
    · change _ ∈ rows.filterMap functionInstance
      apply List.mem_filterMap.mpr
      refine ⟨row, member, ?_⟩
      simp [functionInstance, h]

/- Same witness without a caller-supplied `row.core = ...` theorem: inspecting
   the checked row is part of the executable/proof-producing boundary. -/
theorem function_row_has_tables
    (pack : Declarations.SourcePack) (catalog : Declarations.Catalog)
    (imports : List Declarations.CollectedImport) (program : Core.Program)
    (rows : List (DeclarationLowering pack catalog program))
    (aliases : List (TypeAliasLowering pack catalog))
    {row : DeclarationLowering pack catalog program} (member : row ∈ rows) :
    match row.core with
    | .function function =>
        ∃ scheme resolved,
          scheme ∈ (synthesize pack catalog imports program rows aliases).functions ∧
          resolved ∈ (synthesize pack catalog imports program rows aliases).functionInstances ∧
          scheme.declaration = row.header.declaration ∧
          resolved.declaration = row.header.declaration ∧ resolved.function = function.id
    | .structure _ | .enumeration _ | .constant _ => True := by
  cases h : row.core with
  | «structure» declaration => simp [h]
  | enumeration declaration => simp [h]
  | constant declaration => simp [h]
  | function declaration =>
      simp only [h]
      refine ⟨{ declaration := row.header.declaration
                genericParameters := []
                parameterTypes := declaration.parameters.map (fun parameter =>
                  (groundOfCore parameter.2).toTy)
                returnType := (groundOfCore declaration.returnType).toTy
                requirements := [] },
              { declaration := row.header.declaration
                function := declaration.id
                typeArguments := []
                constArguments := []
                parameterTypes := groundsOfCore (declaration.parameters.map Prod.snd)
                returnType := groundOfCore declaration.returnType }, ?_, ?_, rfl, rfl, rfl⟩
      · change _ ∈ rows.filterMap functionScheme
        apply List.mem_filterMap.mpr
        refine ⟨row, member, ?_⟩
        simp [functionScheme, h]
      · change _ ∈ rows.filterMap functionInstance
        apply List.mem_filterMap.mpr
        refine ⟨row, member, ?_⟩
        simp [functionInstance, h]

/- A row's instance is the empty-substitution specialization of the row's
   scheme.  This is the certificate consumed by `FunctionInstanceCheck`; it
   is reconstructed here from the canonical rows, rather than accepted from a
   caller. -/
theorem function_row_instantiates
    (function : Core.Function) (declaration : Nat) :
    Static.FunctionInstantiates []
      { declaration := declaration
        genericParameters := []
        parameterTypes := function.parameters.map (fun parameter =>
          (groundOfCore parameter.2).toTy)
        returnType := (groundOfCore function.returnType).toTy
        requirements := [] }
      {}
      { declaration := declaration
        function := function.id
        typeArguments := []
        constArguments := []
        parameterTypes := groundsOfCore (function.parameters.map Prod.snd)
        returnType := groundOfCore function.returnType } := by
  apply Static.FunctionInstantiates.intro .nil .nil .nil
  have parameterMap :
      function.parameters.map (fun parameter =>
        (groundOfCore parameter.2).toTy) =
      (groundsOfCore (function.parameters.map Prod.snd)).map
        Static.GroundTy.toTy := by
    simp [groundsOfCore_eq_map, Function.comp_def]
  dsimp [Static.FunctionScheme.instantiateTypes]
  have hparam :
      Static.instantiateTypes {} (function.parameters.map (fun parameter =>
        (groundOfCore parameter.2).toTy)) =
      some (groundsOfCore (function.parameters.map Prod.snd)) := by
    rw [parameterMap]
    exact Static.GroundTy.listToTy_instantiate _ _
  rw [hparam]
  simp [Static.GroundTy.toTy_instantiate, Function.comp_def]

theorem alias_rows_have_tables
    (pack : Declarations.SourcePack) (catalog : Declarations.Catalog)
    (imports : List Declarations.CollectedImport) (program : Core.Program)
    (rows : List (DeclarationLowering pack catalog program))
    (aliases : List (TypeAliasLowering pack catalog))
    {alias : TypeAliasLowering pack catalog} (member : alias ∈ aliases) :
    aliasEntry alias ∈
      (synthesize pack catalog imports program rows aliases).typeAliases := by
  exact List.mem_map_of_mem member

end Lanius.Compiler.ContextSynthesis
