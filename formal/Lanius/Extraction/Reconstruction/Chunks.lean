import Lanius.Extraction.SurfaceReconstruct

namespace Lanius.Extraction

/-! Small composition lemmas for generated Surface reconstruction certificates.
Each generated item can be reduced independently; these lemmas then assemble
the checked results without asking the kernel to normalize an entire file at
once. -/

theorem reconstructItems_nil_of [ArtifactAccess]
    {fuel : Nat} {artifact : Artifact} {nodeId : ParseNodeId}
    {start : SurfaceNodeId}
    (productionFound : artifactProduction? artifact nodeId = some 2) :
    (reconstructItems (fuel + 1) artifact nodeId).run start =
      some ([], start) := by
  rw [reconstructItems]
  simp [productionFound]

theorem reconstructItems_cons_of [ArtifactAccess]
    {fuel : Nat} {artifact : Artifact} {nodeId itemNode restNode : ParseNodeId}
    {start middle finish : SurfaceNodeId} {item : SurfaceItem}
    {items : List SurfaceItem}
    (productionFound : artifactProduction? artifact nodeId = some 1)
    (itemChildFound : artifactChildNode? artifact nodeId 0 = some itemNode)
    (restChildFound : artifactChildNode? artifact nodeId 1 = some restNode)
    (itemFound : (reconstructItem fuel artifact itemNode).run start =
      some (item, middle))
    (restFound : (reconstructItems fuel artifact restNode).run middle =
      some (items, finish)) :
    (reconstructItems (fuel + 1) artifact nodeId).run start =
      some (item :: items, finish) := by
  rw [reconstructItems]
  simp [productionFound, itemChildFound, restChildFound, itemFound, restFound]

theorem reconstructFile_of [ArtifactAccess]
    {fuel : Nat} {artifact : Artifact} {root itemsNode : ParseNodeId}
    {start finish : SurfaceNodeId} {items : List SurfaceItem}
    (productionFound : artifactProduction? artifact root = some 0)
    (itemsChildFound : artifactChildNode? artifact root 0 = some itemsNode)
    (itemsFound : (reconstructItems fuel artifact itemsNode).run start =
      some (items, finish)) :
    (reconstructFile fuel artifact root).run start = some ({
      id := finish
      parse_node := root
      value := { items }
    }, finish + 1) := by
  unfold reconstructFile artifactExpectProduction
  simp [productionFound, itemsChildFound, itemsFound, freshSurfaceNodeId]

theorem reconstructStatements_nil_of [ArtifactAccess]
    {fuel : Nat} {artifact : Artifact} {nodeId : ParseNodeId}
    {start : SurfaceNodeId}
    (productionFound : artifactProduction? artifact nodeId = some 74) :
    (reconstructStatements (fuel + 1) artifact nodeId).run start =
      some ([], start) := by
  rw [reconstructStatements]
  simp [productionFound]

theorem reconstructStatements_cons_of [ArtifactAccess]
    {fuel : Nat} {artifact : Artifact} {nodeId statementNode restNode : ParseNodeId}
    {start middle finish : SurfaceNodeId} {statement : SurfaceStmt}
    {statements : List SurfaceStmt}
    (productionFound : artifactProduction? artifact nodeId = some 73)
    (statementChildFound : artifactChildNode? artifact nodeId 0 = some statementNode)
    (restChildFound : artifactChildNode? artifact nodeId 1 = some restNode)
    (statementFound : (reconstructStatement fuel artifact statementNode).run start =
      some (statement, middle))
    (restFound : (reconstructStatements fuel artifact restNode).run middle =
      some (statements, finish)) :
    (reconstructStatements (fuel + 1) artifact nodeId).run start =
      some (statement :: statements, finish) := by
  rw [reconstructStatements]
  simp [productionFound, statementChildFound, restChildFound,
    statementFound, restFound]

theorem reconstructFunctionBlock_of [ArtifactAccess]
    {fuel : Nat} {artifact : Artifact} {blockNode statementsNode : ParseNodeId}
    {start finish : SurfaceNodeId} {statements : List SurfaceStmt}
    (productionFound : artifactProduction? artifact blockNode = some 12)
    (statementsChildFound :
      artifactChildNode? artifact blockNode 1 = some statementsNode)
    (statementsFound :
      (reconstructStatements fuel artifact statementsNode).run start =
        some (statements, finish)) :
    (reconstructBlock (fuel + 1) artifact blockNode).run start =
      some (statements, finish) := by
  rw [reconstructBlock]
  simp [productionFound, statementsChildFound, statementsFound]

theorem reconstructNestedBlock_of [ArtifactAccess]
    {fuel : Nat} {artifact : Artifact} {blockNode statementsNode : ParseNodeId}
    {start finish : SurfaceNodeId} {statements : List SurfaceStmt}
    {production : Nat}
    (productionFound : artifactProduction? artifact blockNode = some production)
    (productionSupported :
      production = 12 ∨ production = 14 ∨ production = 71 ∨ production = 72)
    (statementsChildFound :
      artifactChildNode? artifact blockNode 1 = some statementsNode)
    (statementsFound :
      (reconstructStatements fuel artifact statementsNode).run start =
        some (statements, finish)) :
    (reconstructBlock (fuel + 1) artifact blockNode).run start =
      some (statements, finish) := by
  rcases productionSupported with rfl | rfl | rfl | rfl <;>
    rw [reconstructBlock] <;>
    simp [productionFound, statementsChildFound, statementsFound]

theorem reconstructWhileStatement_of [ArtifactAccess]
    {fuel : Nat} {artifact : Artifact}
    {statementNode conditionNode blockNode : ParseNodeId}
    {start afterCondition afterBody : SurfaceNodeId}
    {condition : SurfaceExpr} {body : List SurfaceStmt}
    (productionFound :
      artifactProduction? artifact statementNode = some 80)
    (conditionChildFound :
      artifactChildNode? artifact statementNode 2 = some conditionNode)
    (blockChildFound :
      artifactChildNode? artifact statementNode 4 = some blockNode)
    (conditionFound :
      (reconstructExpr fuel artifact conditionNode).run start =
        some (condition, afterCondition))
    (bodyFound :
      (reconstructBlock fuel artifact blockNode).run afterCondition =
        some (body, afterBody)) :
    (reconstructStatement (fuel + 1) artifact statementNode).run start =
      some ({
        id := afterBody
        parse_node := statementNode
        value := .while_loop condition body
      }, afterBody + 1) := by
  rw [reconstructStatement]
  simp [productionFound, conditionChildFound, blockChildFound,
    conditionFound, bodyFound, freshSurfaceNodeId]

theorem option_map_fst_of_run_eq
    {action : SurfaceBuild α} {start finish : SurfaceNodeId} {value : α}
    (found : action.run start = some (value, finish)) :
    (action.run start).map Prod.fst = some value := by
  rw [found]
  rfl

end Lanius.Extraction
