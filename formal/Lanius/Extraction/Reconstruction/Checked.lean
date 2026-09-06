import Lanius.Extraction.Reconstruction.Transport

namespace Lanius.Extraction.Reconstruction

/-- Link the untrusted parse-node list and select only its declared root. -/
def checkedRoot (artifact : Artifact) : Option (ParseTree.Checked artifact.parse_nodes) := do
  let forest ← ParseTree.checkedForest artifact.parse_nodes
  let rootId ← artifact.parse_root
  forest.find? (fun root => root.val.id == rootId)

theorem checkedRoot_id {artifact : Artifact} {root : ParseTree.Checked artifact.parse_nodes}
    (found : checkedRoot artifact = some root) :
    artifact.parse_root = some root.val.id := by
  obtain ⟨forest, _, found⟩ := Option.bind_eq_some_iff.mp found
  obtain ⟨rootId, rootFound, selected⟩ := Option.bind_eq_some_iff.mp found
  have sameId : root.val.id = rootId := by
    simpa using List.find?_some selected
  simpa [sameId] using rootFound

def checkedWithAccess [ArtifactAccess] (artifact : Artifact) : Option SurfaceFile := do
  let root ← checkedRoot artifact
  let (surface, _) ← (reconstructFile (artifact.parse_nodes.length + 1) artifact root).run 0
  pure surface

/-- A linked success certifies the existing indexed reconstruction. Linking
failure is not permission to accept anything, nor a claim that the indexed
checker would also fail. -/
theorem checkedWithAccess_sound [ArtifactAccess] {artifact : Artifact} {surface : SurfaceFile}
    (reads : ∀ nodeId, ArtifactAccess.node? artifact nodeId = artifact.parse_nodes[nodeId]?)
    (accepted : checkedWithAccess artifact = some surface) :
    reconstructArtifactSurfaceWithAccess artifact = some surface := by
  obtain ⟨root, rootFound, accepted⟩ := Option.bind_eq_some_iff.mp accepted
  obtain ⟨result, runFound, resultFound⟩ := Option.bind_eq_some_iff.mp accepted
  have equivalent := file_eq (ParseReference.checked_agrees artifact reads)
    (artifact.parse_nodes.length + 1) root
  unfold reconstructArtifactSurfaceWithAccess
  rw [checkedRoot_id rootFound]
  change ((reconstructFile (artifact.parse_nodes.length + 1) artifact
    (ParseReference.id root)).run 0).bind (fun result => some result.1) = some surface
  rw [equivalent, runFound]
  exact resultFound

def checkedView (artifact : Artifact) (view : ArtifactView artifact) : Option SurfaceFile :=
  letI := ArtifactAccess.ofView view
  do
    let root ← checkedRoot artifact
    let (surface, _) ← (reconstructFile (view.nodeCount + 1) artifact root).run 0
    pure surface

theorem checkedView_eq (view : ArtifactView artifact) :
    checkedView artifact view = @checkedWithAccess (ArtifactAccess.ofView view) artifact := by
  unfold checkedView checkedWithAccess
  rw [view.nodeCount_eq]

theorem checkedView_sound {artifact : Artifact} (view : ArtifactView artifact)
    {surface : SurfaceFile} (accepted : checkedView artifact view = some surface) :
    reconstructArtifactSurfaceView artifact view = some surface :=
  @checkedWithAccess_sound (ArtifactAccess.ofView view) artifact surface
    (fun nodeId => view.node?_eq nodeId) (by simpa only [checkedView_eq] using accepted)

end Lanius.Extraction.Reconstruction
