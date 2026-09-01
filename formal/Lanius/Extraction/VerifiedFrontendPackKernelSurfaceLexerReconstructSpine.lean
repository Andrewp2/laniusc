import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerProposedItems

namespace Lanius.Extraction

set_option maxRecDepth 10000

def verifiedFrontendLexerItemSpineNodes : List ParseNode :=
  artifact_pack_unit_parse_nodes%
    (include_str "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/lexer.lani", 6961, 30

theorem verifiedFrontendLexerParseNodes0_length :
    verifiedFrontendLexerParseNodes0.length = 1000 := by rfl
theorem verifiedFrontendLexerParseNodes1_length :
    verifiedFrontendLexerParseNodes1.length = 1000 := by rfl
theorem verifiedFrontendLexerParseNodes2_length :
    verifiedFrontendLexerParseNodes2.length = 1000 := by rfl
theorem verifiedFrontendLexerParseNodes3_length :
    verifiedFrontendLexerParseNodes3.length = 1000 := by rfl
theorem verifiedFrontendLexerParseNodes4_length :
    verifiedFrontendLexerParseNodes4.length = 1000 := by rfl
theorem verifiedFrontendLexerParseNodes5_length :
    verifiedFrontendLexerParseNodes5.length = 1000 := by rfl
theorem verifiedFrontendLexerParseNodes6_length :
    verifiedFrontendLexerParseNodes6.length = 991 := by rfl

theorem verifiedFrontendLexerItemSpineNodes_eq :
    verifiedFrontendLexerParseNodes6.drop 961 =
      verifiedFrontendLexerItemSpineNodes := by
  rfl

theorem verifiedFrontendLexer_artifactNode_spine_kernel
    (index : Nat) (inBounds : index < 30) :
    artifactNode? verifiedFrontendLexerArtifact (6961 + index) =
      verifiedFrontendLexerItemSpineNodes[index]? := by
  unfold artifactNode?
  simp only [verifiedFrontendLexerArtifact]
  rw [chunkLookup_eq_flatten]
  simp only [verifiedFrontendLexerNodeChunks, List.flatten_cons,
    List.flatten_nil, List.append_nil]
  rw [List.getElem?_append_right (by
    rw [verifiedFrontendLexerParseNodes0_length]
    omega)]
  simp only [verifiedFrontendLexerParseNodes0_length]
  rw [List.getElem?_append_right (by
    rw [verifiedFrontendLexerParseNodes1_length]
    omega)]
  simp only [verifiedFrontendLexerParseNodes1_length]
  rw [List.getElem?_append_right (by
    rw [verifiedFrontendLexerParseNodes2_length]
    omega)]
  simp only [verifiedFrontendLexerParseNodes2_length]
  rw [List.getElem?_append_right (by
    rw [verifiedFrontendLexerParseNodes3_length]
    omega)]
  simp only [verifiedFrontendLexerParseNodes3_length]
  rw [List.getElem?_append_right (by
    rw [verifiedFrontendLexerParseNodes4_length]
    omega)]
  simp only [verifiedFrontendLexerParseNodes4_length]
  rw [List.getElem?_append_right (by
    rw [verifiedFrontendLexerParseNodes5_length]
    omega)]
  simp only [verifiedFrontendLexerParseNodes5_length]
  have shifted :
      6961 + index - 1000 - 1000 - 1000 - 1000 - 1000 - 1000 =
        961 + index := by omega
  rw [shifted]
  rw [← List.getElem?_drop]
  rw [verifiedFrontendLexerItemSpineNodes_eq]

theorem reconstructItems_cons_step
    {artifact : Artifact} {fuel listNode itemNode restNode : Nat}
    {start next finish : SurfaceNodeId}
    {item : SurfaceItem} {rest : List SurfaceItem}
    (productionFound : artifactProduction? artifact listNode = some 1)
    (itemChildFound : artifactChildNode? artifact listNode 0 = some itemNode)
    (restChildFound : artifactChildNode? artifact listNode 1 = some restNode)
    (itemFound : (reconstructItem fuel artifact itemNode).run start =
      some (item, next))
    (restFound : (reconstructItems fuel artifact restNode).run next =
      some (rest, finish)) :
    (reconstructItems (fuel + 1) artifact listNode).run start =
      some (item :: rest, finish) := by
  rw [reconstructItems]
  simp [productionFound, itemChildFound, restChildFound, itemFound, restFound]

theorem reconstructItems_empty_step
    {artifact : Artifact} {fuel listNode start : Nat}
    (productionFound : artifactProduction? artifact listNode = some 2) :
    (reconstructItems (fuel + 1) artifact listNode).run start =
      some ([], start) := by
  rw [reconstructItems]
  simp [productionFound]

end Lanius.Extraction
