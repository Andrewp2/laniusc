import Lanius.Compiler.CatalogSynthesis

namespace Lanius.Compiler.CatalogSynthesisTests
open Lanius Declarations CatalogSynthesis

private def pack : SourcePack := { files := [
  { id := 0, moduleInfo := { id := 0, path := ["app"] },
    contents := { items := [] }, origin := .synthetic }] }

private def header (kind : DeclarationKind) (index : Nat) : DeclarationHeader :=
  { source := .item ⟨0, index⟩, moduleId := 0, declaration := 99, kind }

private def ids (pack : SourcePack) (headers : List DeclarationHeader) : Option (List Nat) :=
  (assignSemanticIds? pack headers).map (fun rows => rows.map (·.declaration))

-- Runtime kind order, not source order or the old declaration field, owns IDs.
example : ids pack [header .function 2, header .enumeration 1,
    header .structureType 0, header .enumVariant 3] = some [2, 1, 0, 3] := by decide
example : ids pack [] = some [] := by decide
example : ids ⟨[]⟩ [header .function 0] = none := by decide

-- Even malformed duplicate input keeps the previous last-write-wins lookup;
-- the later catalog checker still owns rejecting duplicate occurrences.
example : ids pack [header .enumeration 0, header .enumeration 0] = some [1, 1] := by decide

end Lanius.Compiler.CatalogSynthesisTests
