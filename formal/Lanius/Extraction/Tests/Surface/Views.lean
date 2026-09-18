import Lanius.Extraction.Surface.Views
import Lanius.Extraction.ArtifactCacheQuote
import Lanius.Extraction.Parse.Grammar
import Lanius.Extraction.Reconstruction.Validated
import Lanius.Extraction.CompactDecode.Indexed
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Surface.Views

private def source : SourceFile := ⟨"bytes.lani", [0, 127, 128, 255]⟩
private def artifact : Artifact := { Artifact.empty with sources := [source] }

private theorem decoded : decodeBytes source.bytes =
    some (([0, 127, 128, 255] : List UInt8).map fun byte =>
      (⟨byte.toNat, UInt8.toNat_lt byte⟩ : Fin 256)) :=
  decodeBytes_uint8 [0, 127, 128, 255]

private theorem canonical : ArtifactView.canonical? artifact =
    some (ArtifactView.canonicalOfSource artifact source _ rfl decoded) :=
  ArtifactView.canonical?_of_source artifact source _ rfl decoded

private theorem malformed_rejected :
    (ArtifactView.canonical? {Artifact.empty with sources := [⟨"bad", [256]⟩]}).isNone = true := by
  decide +kernel

private theorem multisets_checked :
    ([( [], [], true), ([3, 1, 2, 3], [3, 3, 2, 1], true),
      ([0, 4294967296], [4294967296, 0], true),
      ([0, 0], [0, 1], false), ([1], [], false),
      ([1, 2, 3], [1, 2, 2], false)].all fun (left, right, expected) =>
      Distinct.sameMultiset left right == expected) = true := by
  decide +kernel

private theorem sorting_reference :
    ([3, 1, 2, 3] : List Nat).mergeSort = ([3, 3, 2, 1] : List Nat).mergeSort :=
  Distinct.sameMultiset_mergeSort (by decide +kernel)

-- Exercise leaf boundaries and odd divisions in the existing untrusted
-- proposer. Every proposed tree must still cross the checked-view boundary.
#eval show IO Unit from do
  for count in [0, 1, 2, 63, 64, 65, 127, 128, 129, 255, 256, 257] do
    let values := List.range count
    let tree := proposeSeqTree 64 values
    unless tree.flatten == values && tree.wellFormed 64 do
      throw (IO.userError s!"tree proposal changed values or metadata at size {count}")

-- Native/runtime indexing must preserve absent entries, clipped source ranges,
-- malformed byte rejection, and negative node claims, not just valid syntax.
#eval show IO Unit from do
  for bytes in [[], [0, 127, 128, 255], [256]] do
    let input : Artifact := { Artifact.empty with
      sources := [⟨"index.lani", bytes⟩]
      tokens := [⟨1, ⟨0, 0, 1⟩⟩]
      parse_nodes := [⟨5, 0, 0, 0, []⟩, ⟨6, 0, 0, 0, [.node 0]⟩] }
    let indexed := ArtifactAccess.indexedFor input
    let reference := ArtifactAccess.canonicalFor input
    for id in [0, 1, 2, 99] do
      unless @ArtifactAccess.node? indexed input id == @ArtifactAccess.node? reference input id &&
          @ArtifactAccess.token? indexed input id == @ArtifactAccess.token? reference input id do
        throw (IO.userError s!"indexed lookup differs at {id}")
      for count in [0, 1, 4, 99] do
        unless @ArtifactAccess.primarySourceRange? indexed input id count ==
            @ArtifactAccess.primarySourceRange? reference input id count do
          throw (IO.userError s!"indexed source range differs at {id}/{count}")
    for (claim, expected) in [
        (⟨0, 0, none, [5]⟩, true), (⟨0, 0, some 1, [5]⟩, true),
        (⟨0, 9, none, [5]⟩, false), (⟨0, 0, none, [6]⟩, false),
        (⟨0, 1, some 0, [6]⟩, false)] do
      unless nodeClaimsValidIndexed input [claim] == expected do
        throw (IO.userError "indexed node claim accepted an invalid reference or rejected a valid one")

#eval show IO Unit from do
  for sources in [[], [⟨"empty", []⟩], [⟨"utf8", [97, 195, 169]⟩],
      [⟨"invalid-utf8", [97, 255]⟩], [⟨"invalid-byte", [256]⟩]] do
    let input : Artifact := { Artifact.empty with
      sources
      tokens := [⟨1, ⟨0, 0, 1⟩⟩, ⟨1, ⟨0, 1, 3⟩⟩, ⟨1, ⟨1, 0, 1⟩⟩,
        ⟨1, ⟨0, 3, 1⟩⟩, ⟨1, ⟨0, 50, 70⟩⟩]
      parse_nodes := [⟨0, 0, 0, 0, [.token 0, .token 1]⟩,
        ⟨0, 0, 0, 0, [.node 0]⟩, ⟨0, 0, 0, 0, [.node 1, .node 2]⟩] }
    unless spellingClaimsValidIndexed input [] do
      throw (IO.userError "empty spelling claims changed")
    for token in [0, 1, 2, 3, 4, 99] do
      for owner in [0, 1, 2, 99] do
        for text in ["a", "é", "", "wrong"] do
          let claim : SpellingClaim := ⟨owner, token, text⟩
          unless spellingClaimsValidIndexed input [claim] == spellingClaimValid input claim do
            throw (IO.userError s!"indexed spelling differs at {owner}/{token}/{text}")

run_elab do
  for name in #[``ArtifactAccess.indexedFor_eq, ``nodeClaimsValidIndexed_eq,
      ``spellingClaimsValidIndexed_eq, ``artifactTokenText?_ofView, ``containsToken_eq,
      ``checkParseArtifactView_eq, ``containsNodePruned_sound,
      ``ParseArtifactView.materialized_eq, ``ParseArtifactView.materializedView,
      ``Parse.lookup_eq, ``CompactDecode.UnitData.indexedArtifact_eq, ``Reconstruction.Validated.checkedView_sound,
      ``Reconstruction.generics_eq, ``Reconstruction.externFunction_eq,
      ``decodeBytes_uint8, ``ArtifactCache.ofArtifact_matches_of_source,
      ``ArtifactView.canonical?_of_source, ``surfaceClaimsValidIndexed_sound,
      ``CheckedSurfaceArtifact.rebase, ``checkSurfaceArtifactView?_rebase,
      ``checkSurfaceArtifact?_of_view, ``spellingCoverageValid_of_multiset,
      ``Distinct.sameMultiset_sound, ``Distinct.sameMultiset_mergeSort,
      ``CheckedSurfaceArtifact.ofComponents, ``checkSurfaceArtifactView?_of_components,
      ``decoded, ``canonical, ``malformed_rejected, ``multisets_checked,
      ``sorting_reference] do
    for assumption in ← Lean.collectAxioms name do
      unless #[``propext, ``Classical.choice, ``Quot.sound].contains assumption do
        throwError "Surface view theorem {name} uses unexpected assumption {assumption}"

end Lanius.Extraction.Tests.Surface.Views
