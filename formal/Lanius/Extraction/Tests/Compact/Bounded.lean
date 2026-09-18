import Lanius.Extraction.CompactDecode.Bounded
import Lanius.Extraction.KernelReduction
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Compact.Bounded
open CompactDecode

private def boundary : Bounded.Unit := {
  path := "words/é.lani", source := ⟨#[0, 127, 128, 255]⟩,
  raw := [⟨.identifier, 0, 4294967295⟩], tokens := [⟨.identifier, 0, 4294967295⟩],
  assignments := [⟨4294967295, some 4294967294⟩],
  nodes := [⟨Bounded.productionIndex 0, 0, 4294967295,
    [.token 0, .token 4294967295, .node 0, .node 4294967295]⟩] }

private theorem checked : Bounded.checkPack [boundary] = true := by decide +kernel

private theorem encodable : PackEncodable [boundary.data] :=
  Bounded.packEncodable [boundary] checked

private theorem decoded : decodeCompactArtifactPack? (renderedPack 1 [boundary.data]) =
    some ⟨schemaVersion, [boundary.data.artifact]⟩ := encodable.decoded

private theorem exactFields : boundary.data.nodes =
    [⟨0, 0, 0, 4294967295,
      [.token ⟨0, 0, 0, 0⟩, .token ⟨0, 0, 4294967295, 0⟩,
       .node 0 0 0, .node 4294967295 0 0]⟩] := by kernel_rfl

private theorem exactScalars :
    boundary.data.raw = [⟨.identifier, 0, 4294967295⟩] ∧
    boundary.data.assignments = [⟨4294967295, some 4294967294⟩] := by decide +kernel

-- Typed scalars do not waive the assignment-count, empty-pack, or empty-node
-- obligations. Lexing/parsing correctness is a separate, still-required check.
private theorem rejected :
    Bounded.checkPack [] = false ∧
    Bounded.checkPack [{boundary with nodes := []}] = false ∧
    Bounded.checkPack [{boundary with assignments := []}] = false := by
  decide +kernel

run_elab do
  for name in #[``CompactDecode.Bounded.Child.payloadFit, ``CompactDecode.Bounded.Node.encodable,
      ``CompactDecode.Bounded.Unit.encodable, ``CompactDecode.Bounded.packEncodable,
      ``CompactDecode.Bounded.Token.fields, ``CompactDecode.Bounded.Kinds.fields,
      ``checked, ``encodable, ``decoded, ``exactFields, ``exactScalars, ``rejected] do
    for assumption in ← Lean.collectAxioms name do
      unless #[``propext, ``Classical.choice, ``Quot.sound].contains assumption do
        throwError "bounded certificate {name} uses unexpected assumption {assumption}"

end Lanius.Extraction.Tests.Compact.Bounded
