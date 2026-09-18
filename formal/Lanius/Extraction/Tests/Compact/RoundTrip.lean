import Lanius.Extraction.CompactDecode.Validation
import Lanius.Extraction.CompactDecode.Checked
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Compact.RoundTrip
open CompactDecode SemanticTokens

private def record : RecordVisit :=
  ⟨0, 0, 0, 2, [.token ⟨0, 2, 0, 2⟩]⟩

private def first : UnitData := {
  path := "unit/é.lani"
  source := ⟨#[0, 127, 128, 255]⟩
  raw := [⟨.identifier, 0, 1⟩]
  tokens := [⟨.identifier, 0, 1⟩]
  assignments := [⟨2, none⟩]
  nodes := [record] }

private def second : UnitData := {
  first with path := "empty.lani", source := ByteArray.empty
             assignments := [⟨3, some 4⟩] }

private theorem fixture_encodable : PackEncodable [first, second] := by decide +kernel

private theorem malformed_rejected :
    ¬ PackEncodable [] ∧
    ¬ PackEncodable [{first with nodes := []}] ∧
    ¬ PackEncodable [{first with assignments := []}] ∧
    ¬ PackEncodable [{first with nodes := [{record with production := 4294967296}]}] ∧
    ¬ PackEncodable [{first with nodes := [{record with start := 4294967296}]}] := by
  decide +kernel

private theorem fixture_decodes :
    decodeCompactArtifactPack? (renderedPack 2 [first, second]) =
      some ⟨schemaVersion, [first.artifact, second.artifact]⟩ := by
  exact fixture_encodable.decoded

private theorem exact_sources :
    compactPackSources ⟨schemaVersion, [first.artifact, second.artifact]⟩ =
      sourceFiles [("unit/é.lani", ⟨#[0, 127, 128, 255]⟩), ("empty.lani", ByteArray.empty)] :=
  sources_of_inputs (units := [first, second]) (by rfl)

private def lexical : UnitData := {
  first with
  source := ⟨#[97, 32]⟩
  raw := [⟨.identifier, 0, 1⟩, ⟨.whitespace, 1, 2⟩] }

private theorem token_checks_agree :
    ([(lexical, true),
      ({lexical with source := ⟨#[]⟩, raw := [], tokens := []}, true),
      ({lexical with raw := []}, false),
      ({lexical with tokens := []}, false),
      ({lexical with tokens := lexical.raw}, false),
      ({lexical with raw := [⟨.integer, 0, 1⟩, ⟨.whitespace, 1, 2⟩]}, false),
      ({lexical with raw := [⟨.identifier, 2, 1⟩]}, false),
      ({lexical with tokens := [⟨.identifier, 0, 2⟩]}, false)].all
      fun (data, expected) => data.checkTokens == expected &&
        checkTokenArtifact data.artifact == expected) = true := by
  decide +kernel

-- The theorem preserves order, empty files, arbitrary bytes, UTF-8 paths,
-- and both one-kind and split-kind token assignments in the actual decoder.
#eval show IO Unit from do
  let some pack := decodeCompactArtifactPack? (renderedPack 2 [first, second])
    | throw (IO.userError "round-trip decoder rejected the fixture")
  unless compactPackSources pack == [⟨first.path, [0, 127, 128, 255]⟩, ⟨second.path, []⟩] do
    throw (IO.userError "round-trip decoder changed ordered paths or source bytes")
  unless pack.units.map (·.semantic_token_kinds) == [[2], [2147483648 + 3 + 4 * 32768]] do
    throw (IO.userError "round-trip decoder changed semantic token assignments")

run_elab do
  for theoremName in #[``renderedPack_byteArray, ``decode_renderedPack,
      ``NodeEncodable.iff_bounds, ``UnitData.Encodable.iff_fields,
      ``fixture_encodable, ``malformed_rejected, ``fixture_decodes,
      ``sources_of_inputs, ``exact_sources, ``checkSurfaceSources?_eq,
      ``UnitData.checkTokens_sound, ``token_checks_agree] do
    for assumption in ← Lean.collectAxioms theoremName do
      unless #[``propext, ``Classical.choice, ``Quot.sound].contains assumption do
        throwError "Compact round-trip theorem {theoremName} uses unexpected axiom {assumption}"

end Lanius.Extraction.Tests.Compact.RoundTrip
