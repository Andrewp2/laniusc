import SelfEncoding
import Lanius.Extraction.Surface.Views
import Lanius.Extraction.Surface.Paths
import Lanius.Extraction.ArtifactCacheQuote
import Lanius.Extraction.KernelReduction
import Lanius.Extraction.CompactDecode.Indexed
import Lanius.Extraction.Reconstruction.Plan
import Lanius.Extraction.Parse.Grammar
import Lean.Util.CollectAxioms

/-! Three representative units of the frozen, source-bound self-extraction.
One recipe supplies the complete per-unit proof; this is not the full pack.
Native decoding and reconstruction only propose data. Every exported acceptance
theorem and its transitive assumptions are checked by the kernel. -/

namespace Lanius.Extraction.Self.Surface
open Lean Elab Term CompactDecode Encoding

set_option maxRecDepth 4096
set_option maxHeartbeats 2000000
set_option compiler.extract_closed false

private def phase (message : String) (checked : Name := .anonymous) : TermElabM Unit := do
  if checked != .anonymous then
    for assumption in ← Lean.collectAxioms checked do
      unless #[``propext, ``Classical.choice, ``Quot.sound].contains assumption do
        let stderr ← IO.getStderr
        stderr.putStrLn s!"certificate phase {checked} failed: unexpected assumption {assumption}"
        stderr.flush
        IO.Process.exit 1
  IO.FS.withFile "target/verified-compiler/self-surface-phases.log" .append fun handle => do
    handle.putStrLn s!"[{← IO.monoMsNow} ms] {message}"
    handle.flush

run_elab IO.FS.writeFile "target/verified-compiler/self-surface-phases.log" ""

noncomputable def artifactOfData (data : UnitData) : Artifact :=
  { data.indexedArtifact with sources := [⟨data.path, data.source.data.toList.map UInt8.toNat⟩] }

theorem artifactOfData_eq (data : UnitData) : artifactOfData data = data.artifact := by
  unfold artifactOfData
  rw [UnitData.indexedArtifact_eq]
  unfold UnitData.artifact
  rw [byteArray_toList]

elab "surface_proposal% " index:num : term => do
  let emitted ← IO.FS.readFile "target/verified-compiler/SelfCompactRequirements.lean"
  let some first := (emitted.splitOn "def encodedPack : String := \"")[1]?
    | throwError "missing compact literal"
  let some encoded := (first.splitOn "\"").head? | throwError "missing literal end"
  let some pack := decodeCompactArtifactPack? encoded | throwError "invalid compact input"
  let some proposed := pack.units[index.getNat]? | throwError "missing requested unit"
  let some bytes := decodeSingleSource proposed.sources | throwError "invalid source bytes"
  let cache : ArtifactCache := {
    leafCapacity := 16
    parseNodes := proposeSeqTree 16 proposed.parse_nodes
    tokens := proposeSeqTree 16 proposed.tokens
    primarySourceBytes := proposeSeqTree 16 bytes }
  let some view := cache.checked? proposed | throwError "proposed cache rejected"
  let some tree := reconstructArtifactSurfaceView proposed view | throwError "reconstruction rejected"
  let some claims := collectSurfaceClaimsFrom proposed tree | throwError "claims rejected"
  let (nodeParents, tokenParents) := buildParentTables proposed
  let parents : OriginPathParents := {
    nodeParents := proposeSeqTree 16 nodeParents
    tokenParents := proposeSeqTree 16 tokenParents }
  let some origins := buildSurfaceOrigins proposed view parents claims
    | throwError "path proposal failed"
  phase s!"quoting {bytes.length} bytes, {proposed.tokens.length} tokens, {proposed.parse_nodes.length} nodes"
  quoteBounded (cache, proposeSeqTree 16 proposed.semantic_token_kinds, tree, origins,
    Reconstruction.Plan.propose proposed.parse_nodes 2) (compile := false)

set_option hygiene false in
macro "certify_surface_unit " name:ident " at " index:num " for " path:str : command =>
  `(namespace $name
    run_elab phase ("starting " ++ $path)
    noncomputable def unit : UnitData := units[$index]'(by decide +kernel)
    noncomputable def sourceArtifact : Artifact := artifactOfData unit
    theorem source_path : unit.path = $path := by rfl

    noncomputable def proposal : ArtifactCache × Lanius.Data.SeqTree Nat × SurfaceFile × SurfaceOrigins ×
      List Reconstruction.Plan.Segment := surface_proposal% $index
    noncomputable def tree := proposal.2.2.1
    noncomputable def origins := proposal.2.2.2.1
    noncomputable def plan := proposal.2.2.2.2
    noncomputable def claims := origins.claims

    run_elab phase "proposal quoted; authenticating cache"

    noncomputable def checkedParseNodes :=
      seq_tree_checked% sourceArtifact.parse_nodes, 16
    noncomputable def cache := { proposal.1 with parseNodes := checkedParseNodes.val }

    noncomputable def sourceIndex : ArtifactView sourceArtifact := by
      let parseNodesWellFormed :
          cache.parseNodes.WellFormed cache.leafCapacity :=
        Lanius.Data.SeqTree.wellFormed_sound (by decide +kernel)
      exact {
        cache
        parseNodesWellFormed
        parseNodesRepresent := checkedParseNodes.property
        tokensWellFormed := Lanius.Data.SeqTree.wellFormed_sound (by decide +kernel)
        tokensRepresent := by kernel_rfl
        sourceBytesWellFormed := Lanius.Data.SeqTree.wellFormed_sound (by decide +kernel)
        sourceBytesRepresent := by
          intro source found
          change some ⟨unit.path, unit.source.data.toList.map UInt8.toNat⟩ = some source at found
          cases Option.some.inj found
          rw [decodeBytes_uint8]
          kernel_rfl }

    noncomputable def kinds := proposal.2.1

    noncomputable def sourceView : ParseArtifactView sourceArtifact := {
      artifactView := sourceIndex
      leafCapacity := 16
      semanticKinds := kinds
      semanticKindsWellFormed := Lanius.Data.SeqTree.wellFormed_sound (by decide +kernel)
      semanticKindsRepresent := by kernel_rfl }

    noncomputable def artifact := sourceView.materialized
    noncomputable def parseView : ParseArtifactView artifact := sourceView.materializedView
    noncomputable def indexed : ArtifactView artifact := parseView.artifactView

    run_elab phase "cache authenticated; checking typed tokens" ``sourceView

    set_option Elab.async false in
    theorem tokens_checked : checkTokenArtifact artifact = true := by
      change checkTokenArtifact sourceView.materialized = true
      rw [sourceView.materialized_eq]
      change checkTokenArtifact (artifactOfData unit) = true
      rw [artifactOfData_eq]
      apply UnitData.checkTokens_sound
      decide +kernel

    run_elab phase "tokens checked; validating nodes and reconstruction together" ``tokens_checked

    set_option Elab.async false in
    theorem fused : Reconstruction.Validated.checkedView laniusGrammar parseView Parse.productions.lookup = some tree := by
      apply Reconstruction.Plan.checkedView_sound parseView Parse.productions.lookup Parse.lookup_eq plan
      kernel_rfl

    run_elab phase "fused reconstruction checked; assembling parse acceptance" ``fused

    set_option Elab.async false in
    theorem parsed : checkParseArtifactView artifact indexed = true := by
      have nodes := (Reconstruction.Validated.checkedView_sound laniusGrammar parseView
        Parse.productions.lookup Parse.lookup_eq tree fused).1
      rw [checkNodesFromParseView_eq, checkNodesFromView_eq] at nodes
      rw [checkParseArtifactView_eq]
      simp only [checkParseArtifact, tokens_checked, nodes, Bool.true_and, Bool.and_true,
        ← rootShapeValidView_eq laniusGrammar indexed]
      decide +kernel

    run_elab phase "parse checked; authenticating retained reconstruction" ``parsed

    set_option Elab.async false in
    theorem rebuilt : reconstructArtifactSurfaceView artifact indexed = some tree :=
      (Reconstruction.Validated.checkedView_sound laniusGrammar parseView Parse.productions.lookup Parse.lookup_eq tree fused).2

    run_elab phase "reconstruction authenticated; authenticating retained claims" ``rebuilt

    set_option Elab.async false in
    theorem collected : collectSurfaceClaimsFrom artifact tree = some claims := by kernel_rfl

    run_elab phase "claims checked; decoding Surface" ``collected

    set_option Elab.async false in
    theorem surface_decoded : (decodeSurfaceFile (artifact.parse_nodes.length + 1) tree).isSome = true := by decide +kernel

    noncomputable def surface := (decodeSurfaceFile (artifact.parse_nodes.length + 1) tree).get surface_decoded

    run_elab phase "claims and Surface decoding checked; validating claims" ``surface

    set_option Elab.async false in
    theorem coverage : spellingCoverageValid artifact claims = true := by
      apply spellingCoverageValid_of_multiset
      decide +kernel

    run_elab phase "coverage checked" ``coverage

    set_option Elab.async false in
    theorem validated : surfaceClaimsValidIndexed artifact claims = true := by
      apply SurfaceOrigins.checkReference_sound indexed origins
      unfold SurfaceOrigins.checkReference
      rw [show spellingCoverageValid artifact origins.claims = true from coverage]
      decide +kernel

    run_elab phase "origin witnesses checked" ``validated

    noncomputable def checked : CheckedSurfaceArtifact artifact :=
      CheckedSurfaceArtifact.ofComponents indexed tree claims surface parsed rebuilt collected
        (Option.some_get surface_decoded).symm validated

    run_elab phase "checked object assembled"

    theorem accepted : checkSurfaceArtifactView? artifact indexed = some checked :=
      checkSurfaceArtifactView?_of_components indexed tree claims surface parsed rebuilt collected
        (Option.some_get surface_decoded).symm validated

    run_elab phase "indexed acceptance assembled"

    noncomputable def reference : ArtifactView artifact :=
      ArtifactView.canonicalOfSource artifact
        ⟨unit.path, unit.source.data.toList.map UInt8.toNat⟩ _ rfl (decodeBytes_uint8 _)

    theorem reference_found : ArtifactView.canonical? artifact = some reference :=
      ArtifactView.canonical?_of_source artifact _ _ rfl (decodeBytes_uint8 _)

    run_elab phase "canonical view assembled"

    theorem reference_accepted : checkSurfaceArtifact? artifact = some (checked.rebase reference) :=
      checkSurfaceArtifact?_of_view indexed reference reference_found checked accepted

    run_elab phase "reference acceptance assembled"

    theorem original_accepted : (checkSurfaceArtifact? unit.artifact).isSome = true := by
      rw [← artifactOfData_eq unit]
      change (checkSurfaceArtifact? sourceArtifact).isSome = true
      rw [← sourceView.materialized_eq]
      exact congrArg Option.isSome reference_accepted

    run_elab phase "original acceptance assembled; starting audit"

    run_elab do
      for name in #[``source_path, ``reference_accepted, ``original_accepted] do
        for assumption in ← Lean.collectAxioms name do
          unless #[``propext, ``Classical.choice, ``Quot.sound].contains assumption do
            throwError "unexpected assumption in {name}: {assumption}"
      phase ("accepted " ++ $path ++ "; exact original checker result; zero nonstandard axioms")

    end $name)

certify_surface_unit Host at 17 for "verified_compiler/src/verified/host.lani"
certify_surface_unit TokenScan at 14 for "verified_compiler/src/verified/token_scan.lani"
certify_surface_unit ByteIO at 2 for "verified_compiler/src/verified/byte_io.lani"

end Lanius.Extraction.Self.Surface
