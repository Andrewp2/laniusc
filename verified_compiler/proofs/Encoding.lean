import Lanius.Extraction.CompactDecode.Validation
import Lanius.Extraction.CompactDecode.Bounded
import Lanius.Extraction.CompactDecode.Checked
import Lanius.Extraction.ArtifactQuote
import Lean.Elab.Tactic.Decide
import Lean.Util.CollectAxioms

/-! Run from the repository root, with shared imports built. This freezes the
structured candidate from the existing self-extraction and independently reads
the ordered source closure. Native decoding only proposes data; every theorem
is kernel-checked. This is the encoding/source-binding part of the certificate,
not yet a Surface/Core or whole-extractor execution certificate. The structured
data is the embedding: no theorem equates the bootstrap's transport literal to
`encoded`. Re-run this file for changed inputs; an old `.olean` certifies only
its frozen data, not the current filesystem. -/

namespace Lanius.Extraction.Self.Encoding
open Lean Meta Elab Term Lanius.Compiler CompactDecode SemanticTokens

set_option maxRecDepth 4096
set_option maxHeartbeats 2000000
set_option compiler.extract_closed false

private def phase (message : String) : IO Unit :=
  IO.FS.withFile "target/verified-compiler/self-encoding-phases.log" .append fun handle => do
    handle.putStrLn s!"[{← IO.monoMsNow} ms] {message}"
    handle.flush

run_elab do
  IO.FS.writeFile "target/verified-compiler/self-encoding-phases.log" ""
  phase "preparing untrusted quotation"

deriving instance ToExpr for ByteArray
deriving instance ToExpr for TokenKind
deriving instance ToExpr for Bounded.Child
deriving instance ToExpr for Bounded.Token
deriving instance ToExpr for Bounded.Kinds

-- Retain the symbolic Fin bound instead of normalizing the grammar at every
-- quoted record. The constructor and all resulting values are kernel-checked.
instance : ToExpr Bounded.Node where
  toTypeExpr := mkConst ``Bounded.Node
  toExpr node := mkApp4 (mkConst ``Bounded.Node.mk)
    (mkApp (mkConst ``Bounded.productionIndex) (mkNatLit node.production.val))
    (toExpr node.start) (toExpr node.finish) (toExpr node.children)

deriving instance ToExpr for Bounded.Unit

private def word (value : Nat) : Option UInt32 :=
  if value < 4294967296 then some (UInt32.ofNat value) else none

private def nodeData (node : ParseNode) : Option Bounded.Node := do
  if production : node.production < laniusGrammar.productions.length then
    return ⟨⟨node.production, production⟩, ← word node.position_start, ← word node.position_end,
      ← node.children.mapM (fun child => match child with
        | .token id => Bounded.Child.token <$> word id
        | .node id => Bounded.Child.node <$> word id)⟩
  else none

private def tokenData (token : Token) : Option Bounded.Token := do
  return ⟨← TokenKind.ofGpuCode token.kind, ← word token.span.start, ← word token.span.finish⟩

private def secondKind (value : Nat) : Option (Fin 4294967295) :=
  if bound : value < 4294967295 then some ⟨value, bound⟩ else none

private def unitData (artifact : Artifact) : Option Bounded.Unit := do
  let [source] := artifact.sources | none
  let some raw := artifact.raw_tokens | none
  let assignments ← artifact.semantic_token_kinds.mapM fun code => do
    if isPackedSemanticKind code then
      return Bounded.Kinds.mk (← word (packedInnerKind code)) (some (← secondKind (packedOuterKind code)))
    else return Bounded.Kinds.mk (← word code) none
  return ⟨source.path, ⟨(source.bytes.map UInt8.ofNat).toArray⟩,
    ← raw.mapM tokenData, ← artifact.tokens.mapM tokenData, assignments,
    ← artifact.parse_nodes.mapM nodeData⟩

elab "self_units%" : term => do
  let emitted ← IO.FS.readFile "target/verified-compiler/SelfCompactRequirements.lean"
  let some first := (emitted.splitOn "def encodedPack : String := \"")[1]?
    | throwError "missing compact literal"
  let some transport := (first.splitOn "\"").head?
    | throwError "missing compact literal end"
  let some pack := decodeCompactArtifactPack? transport
    | throwError "untrusted self-pack decoder rejected the input"
  let some data := pack.units.mapM unitData
    | throwError "self-pack has no compact proof representation"
  phase s!"quoting {data.length} units, {data.foldl (fun n u => n + u.source.size) 0} source bytes, {data.foldl (fun n u => n + u.nodes.length) 0} parse nodes"
  let quoted ← quoteBounded data (compile := false)
  phase "structured quotation checked"
  return quoted

elab "self_sources%" : term => do
  let paths ← IO.FS.lines "verified_compiler/source-closure.txt"
  let inputs ← paths.toList.mapM fun (path : String) => do
    let bytes ← IO.FS.readBinFile path
    return (path, bytes)
  quoteBounded inputs (compile := false)

noncomputable def boundedUnits : List Bounded.Unit := self_units%

noncomputable def units : List UnitData := boundedUnits.map Bounded.Unit.data

set_option Elab.async false in
theorem encodable : PackEncodable units := by
  apply Bounded.packEncodable
  decide +kernel

noncomputable def encoded : String := renderedPack units.length units

theorem decoded : decodeCompactArtifactPack? encoded =
    some ⟨schemaVersion, units.map UnitData.artifact⟩ := encodable.decoded

run_elab phase "complete pack bounds and public decoder certificate checked"

noncomputable def sourceInputs : List (String × ByteArray) := self_sources%

noncomputable def sources : List SourceFile := sourceFiles sourceInputs

run_elab phase "independent sources quoted; checking exact ordered source binding"

set_option Elab.async false in
theorem source_bound : compactPackSources ⟨schemaVersion, units.map UnitData.artifact⟩ = sources := by
  exact sources_of_inputs (by rfl : units.map (fun unit => (unit.path, unit.source)) = sourceInputs)

run_elab do
  for name in #[``boundedUnits, ``units, ``sourceInputs, ``sources, ``encodable, ``decoded, ``source_bound] do
    for assumption in ← Lean.collectAxioms name do
      unless #[``propext, ``Classical.choice, ``Quot.sound].contains assumption do
        throwError "unexpected assumption in {name}: {assumption}"
  phase "encoding and exact source binding checked; zero nonstandard axioms"

end Lanius.Extraction.Self.Encoding
