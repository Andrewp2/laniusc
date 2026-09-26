import Lanius.Declarations.CatalogCheck
import Std.Data.HashMap.Basic

namespace Lanius.Compiler.CatalogSynthesis

open Lanius
open Lanius.Declarations
open Lanius.Surface

/- Header metadata is derived only from the source item selected by the
   normalized occurrence; the caller supplies neither names nor IDs. -/
def itemHeader (file : SourceFile) (address : ItemAddress) (id : Nat) :
    Surface.Item → Option DeclarationHeader
  | .function declaration => some {
      source := .item address, moduleId := file.moduleInfo.id, declaration := id,
      kind := .function, lookupNamespace := some .value,
      name := some declaration.name, visibility := visibility declaration.isPublic }
  | .externFunction declaration => some {
      source := .item address, moduleId := file.moduleInfo.id, declaration := id,
      kind := .externalFunction, lookupNamespace := some .value,
      name := some declaration.name, visibility := visibility declaration.isPublic }
  | .constant name isPublic _ _ => some {
      source := .item address, moduleId := file.moduleInfo.id, declaration := id,
      kind := .constant, lookupNamespace := some .value,
      name := some name, visibility := visibility isPublic }
  | .typeAlias name isPublic _ _ _ => some {
      source := .item address, moduleId := file.moduleInfo.id, declaration := id,
      kind := .typeAlias, lookupNamespace := some .type,
      name := some name, visibility := visibility isPublic }
  | .structure declaration => some {
      source := .item address, moduleId := file.moduleInfo.id, declaration := id,
      kind := .structureType, lookupNamespace := some .type,
      name := some declaration.name, visibility := visibility declaration.isPublic }
  | .enumeration declaration => some {
      source := .item address, moduleId := file.moduleInfo.id, declaration := id,
      kind := .enumeration, lookupNamespace := some .type,
      name := some declaration.name, visibility := visibility declaration.isPublic }
  | .trait declaration => some {
      source := .item address, moduleId := file.moduleInfo.id, declaration := id,
      kind := .trait, lookupNamespace := some .type,
      name := some declaration.name, visibility := visibility declaration.isPublic }
  | .implementation declaration => some {
      source := .item address, moduleId := file.moduleInfo.id, declaration := id,
      kind := .implementation, visibility := visibility declaration.isPublic }
  | .module _ | .importPath _ | .importString _ => none

def headerFor? (pack : SourcePack) (id : Nat) : DeclarationOccurrence → Option DeclarationHeader
  | .item address => do
      let file ← pack.file? address.file
      let item ← pack.item? address
      itemHeader file address id item
  | .enumVariant parent index => do
      let file ← pack.file? parent.file
      let item ← pack.item? parent
      match item with
      | .enumeration declaration => do
          let variant ← declaration.variants[index]?
          let header : DeclarationHeader :=
            { source := .enumVariant parent index, moduleId := file.moduleInfo.id,
              declaration := id, kind := .enumVariant, lookupNamespace := some .value,
              name := some variant.name, visibility := visibility declaration.isPublic }
          pure header
      | _ => none
  | .traitMethod parent index => do
      let file ← pack.file? parent.file
      let item ← pack.item? parent
      match item with
      | .trait declaration => do
          let method ← declaration.methods[index]?
          let header : DeclarationHeader :=
            { source := .traitMethod parent index, moduleId := file.moduleInfo.id,
              declaration := id, kind := .traitMethod,
              name := some method.signature.name,
              visibility := visibility method.signature.isPublic }
          pure header
      | _ => none
  | .implementationMethod parent index => do
      let file ← pack.file? parent.file
      let item ← pack.item? parent
      match item with
      | .implementation declaration => do
          let method ← declaration.methods[index]?
          let header : DeclarationHeader :=
            { source := .implementationMethod parent index,
              moduleId := file.moduleInfo.id, declaration := id,
              kind := .implementationMethod, name := some method.name,
              visibility := visibility method.isPublic }
          pure header
      | _ => none

def headers? (pack : SourcePack) : Nat → List DeclarationOccurrence →
    Option (List DeclarationHeader)
  | _, [] => some []
  | id, occurrence :: tail => do
      let header ← headerFor? pack id occurrence
      let rest ← headers? pack (id + 1) tail
      pure (header :: rest)

/-- Give semantic declarations the same namespace layout as the Lanius
    allocator. Nested variant names remain in the catalog, but receive IDs
    after runtime declarations: they have no independent Core declaration. -/
def allocationOrder (pack : SourcePack) (headers : List DeclarationHeader) :
    List DeclarationHeader :=
  let byKind (kind : DeclarationKind) := headers.filter (fun h => h.kind == kind)
  let callables := pack.files.flatMap fun file =>
    headers.filter (fun h => h.kind == .function &&
      match h.source with
      | .item address => address.file == file.id
      | _ => false) ++
    headers.filter (fun h => h.kind == .externalFunction &&
      match h.source with
      | .item address => address.file == file.id
      | _ => false)
  let other := headers.filter fun h =>
    h.kind != .structureType && h.kind != .enumeration &&
      h.kind != .typeAlias && h.kind != .constant &&
      h.kind != .function && h.kind != .externalFunction
  byKind .structureType ++ byKind .enumeration ++ byKind .typeAlias ++
    byKind .constant ++ callables ++ other

def assignSemanticIds? (pack : SourcePack) (headers : List DeclarationHeader) :
    Option (List DeclarationHeader) := do
  let order := allocationOrder pack headers
  let ids := ((List.range order.length).zip order).foldl
    (fun (index : Std.HashMap DeclarationOccurrence Nat) (pair : Nat × DeclarationHeader) =>
      index.insert pair.2.source pair.1) {}
  headers.mapM fun header => do
    let id ← ids[header.source]?
    pure { header with declaration := id }

def synthesize? (pack : SourcePack) : Option Catalog := do
  let headers ← headers? pack 0 (normalizedOccurrences pack)
  let headers ← assignSemanticIds? pack headers
  pure { headers }

structure Checked (pack : SourcePack) where
  catalog : Catalog
  wellFormed : CatalogWellFormed pack catalog

def check (pack : SourcePack) : Option (Checked pack) := do
  let catalog ← synthesize? pack
  let evidence ← checkCatalogWellFormed pack catalog
  pure { catalog := catalog, wellFormed := evidence.down }

theorem check_sound {pack : SourcePack} {checked : Checked pack}
    (_accepted : check pack = some checked) :
    CatalogWellFormed pack checked.catalog := checked.wellFormed

end Lanius.Compiler.CatalogSynthesis
