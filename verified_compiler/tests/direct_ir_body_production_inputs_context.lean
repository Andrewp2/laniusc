import verified_compiler.tests.direct_ir_body_production_inputs

namespace IRBodyProductionInputs

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRTypeRefProof

/-- Only source record fields, not execution premises or another body model. -/
structure Inputs where
  owner : Int32
  source : Value
  sourceLength : Nat
  tokens : Value
  tokenCount : Nat
  tokenStorage : Nat
  tree : Tree
  allocationTable : Value
  allocationTail : Fin 5 → Value
  signature : Signature
  resolutions : Value
  aliases : Value
  values : Value
  valueNames : Value
  contexts : Value
  sourceCatalog : Value
  tokenCatalog : Value
  globalDeclarations : Value
  trees : Value
def Inputs.tokensValue (input : Inputs) : Value := source_value Extracted.«verified::token».Types.«TokenTable».mk
  [input.tokens, .signed .i32 input.tokenCount, .pointer input.tokenStorage]
def Inputs.allocatedValue (input : Inputs) : Value := source_value Extracted.«lowering::allocation».Types.«Index».mk
  [input.allocationTable, input.allocationTail 0, input.allocationTail 1,
    input.allocationTail 2, input.allocationTail 3, input.allocationTail 4]
def Inputs.value (input : Inputs) : Value := source_value Extracted.«lowering::body_context».Types.«BodyLoweringInputs».mk
  [.signed .i32 input.owner.toInt,
    source_value Extracted.«lowering::body_context».Types.«WordRegion».mk [input.source, .signed .i32 input.sourceLength],
    input.tokensValue, input.tree.value, input.allocatedValue, input.signature.value,
    input.resolutions, input.aliases, input.values, input.valueNames, input.contexts,
    input.sourceCatalog, input.tokenCatalog, input.globalDeclarations, input.trees]

structure Workspace where
  expressionData : Value
  expressionCount : Value
  expressionCapacity : Nat
  codes : Value
  depths : Value
  types : Value
  aliasScratch : Value
  aliasCapacity : Nat
  typeOutput : Value
  events : Value
  catalog : Value
def Workspace.arena (workspace : Workspace) : Value := source_value Extracted.«verified::surface_expr».Types.«ExpressionArena».mk
  [workspace.expressionData, workspace.expressionCount, .signed .i32 workspace.expressionCapacity]
def Workspace.value (workspace : Workspace) : Value := source_value Extracted.«lowering::body_context».Types.«BodyLoweringWorkspace».mk
  [workspace.arena, workspace.codes, workspace.depths, workspace.types,
    source_value Extracted.«lowering::body_context».Types.«WordRegion».mk [workspace.aliasScratch, .signed .i32 workspace.aliasCapacity],
    workspace.typeOutput, workspace.events, workspace.catalog]
def bodyContext (input : Inputs) (workspace : Workspace) (locals : Value) : Value :=
  source_value Extracted.«lowering::body_context».Types.«BodyContext».mk
    [input.source, .signed .i32 input.sourceLength, input.tokensValue, .signed .i32 input.tokenCount,
      input.tree.value, workspace.arena, workspace.codes, workspace.depths, workspace.types,
      input.resolutions, input.aliases, workspace.aliasScratch, .signed .i32 workspace.aliasCapacity,
      workspace.typeOutput, input.allocatedValue, input.signature.value, input.values, input.valueNames,
      locals, referenceValue input.signature.result, .signed .i32 input.owner.toInt, input.contexts,
      input.sourceCatalog, input.tokenCatalog, input.globalDeclarations, input.trees]

def tokenType : Ty := match source_value Extracted.«verified::token».Types.«TokenRow».mk [] with
  | .structure id _ => .structure id | _ => .unit
def tokenRow (kind : Value) (start finish : Int) : Value := source_value Extracted.«verified::token».Types.«TokenRow».mk
  [kind, .signed .i32 start, .signed .i32 finish]
/-- A selected original token; the descriptor may have spare capacity and arbitrary storage metadata. -/
structure NativeToken (input : Inputs) (heap : Heap) (index : Nat) where
  address : Nat
  length : Nat
  base : Nat
  kind : Value
  start : Int
  finish : Int
  descriptor : input.tokens = .rawSlice tokenType address length
  inside : index < input.tokenCount
  bound : input.tokenCount ≤ length
  location : rawSliceElementAddress? extractedProgram tokenType address index = .ok base
  snapshot : NativeSnapshot 64 extractedProgram heap tokenType base (tokenRow kind start finish) 24
theorem NativeToken.read (token : NativeToken input state.heap index) :
    readRawSliceIndex extractedProgram state tokenType token.address token.length index =
      .ok (tokenRow token.kind token.start token.finish) := by
  have inside := Nat.lt_of_lt_of_le token.inside token.bound
  simp only [readRawSliceIndex, Nat.not_le_of_lt inside, ↓reduceIte, token.location]
  exact token.snapshot.read
def NativeToken.afterReads (token : NativeToken input before index) (reads : HeapReads before after) :
    NativeToken input after index := { token with snapshot := token.snapshot.afterHeapReads reads }

/-- The common terminal route is native input topology, not assumed query execution. -/
structure TerminalTopology (input : Inputs) (heap : Heap) (declaration : Nat) where
  block : Nat
  list : Nat
  statement : Nat
  rest : Nat
  optional : Nat
  tokenIndex : Nat
  declarationNode : NativeNode input.tree heap declaration
  declarationProduction : declarationNode.production = 11
  declarationBound : 8 < declarationNode.count
  bodyChild : NativeChild input.tree heap (declarationNode.first + 8)
  bodyKind : bodyChild.kind = .StateChild
  bodyIndex : bodyChild.payload = block
  blockNode : NativeNode input.tree heap block
  blockProduction : blockNode.production = 12
  blockBound : 1 < blockNode.count
  listChild : NativeChild input.tree heap (blockNode.first + 1)
  listKind : listChild.kind = .StateChild
  listIndex : listChild.payload = list
  listNode : NativeNode input.tree heap list
  listProduction : listNode.production = 73
  listBound : 1 < listNode.count
  firstChild : NativeChild input.tree heap listNode.first
  firstKind : firstChild.kind = .StateChild
  firstIndex : firstChild.payload = statement
  restChild : NativeChild input.tree heap (listNode.first + 1)
  restKind : restChild.kind = .StateChild
  restIndex : restChild.payload = rest
  restNode : NativeNode input.tree heap rest
  restProduction : restNode.production = 74
  statementNode : NativeNode input.tree heap statement
  statementProduction : statementNode.production = 76
  statementBound : 1 < statementNode.count
  optionalChild : NativeChild input.tree heap (statementNode.first + 1)
  optionalKind : optionalChild.kind = .StateChild
  optionalIndex : optionalChild.payload = optional
  optionalNode : NativeNode input.tree heap optional
  returnChild : NativeChild input.tree heap statementNode.first
  returnKind : returnChild.kind = .TokenChild
  returnIndex : returnChild.payload = tokenIndex
  returnToken : NativeToken input heap tokenIndex
  returnKeyword : returnToken.kind = source_value Extracted.«verified::token».Types.«TokenKind».«ReturnKeyword» []
  distinct : [declaration, block, list, statement, optional].Nodup

def TerminalTopology.afterReads (topology : TerminalTopology input before declaration) (reads : HeapReads before after) :
    TerminalTopology input after declaration := {
  topology with
  declarationNode := topology.declarationNode.afterReads reads
  bodyChild := topology.bodyChild.afterReads reads
  blockNode := topology.blockNode.afterReads reads
  listChild := topology.listChild.afterReads reads
  listNode := topology.listNode.afterReads reads
  firstChild := topology.firstChild.afterReads reads
  restChild := topology.restChild.afterReads reads
  restNode := topology.restNode.afterReads reads
  statementNode := topology.statementNode.afterReads reads
  optionalChild := topology.optionalChild.afterReads reads
  optionalNode := topology.optionalNode.afterReads reads
  returnChild := topology.returnChild.afterReads reads
  returnToken := topology.returnToken.afterReads reads }

/-- Distinct reached original nodes bound real recursion by the caller's node_count. -/
theorem Tree.routeBound (tree : Tree) (route : List Nat) (distinct : route.Nodup)
    (inside : ∀ index ∈ route, index < tree.nodeCount) : route.length ≤ tree.nodeCount := by
  have subset : route ⊆ List.range tree.nodeCount := fun index member => List.mem_range.mpr (inside index member)
  simpa only [List.length_range] using distinct.length_le_of_subset subset

theorem TerminalTopology.depth (topology : TerminalTopology input heap declaration) : 4 ≤ input.tree.nodeCount := by
  have inside : ∀ index ∈ [declaration, topology.block, topology.list, topology.statement, topology.optional],
      index < input.tree.nodeCount := by
    intro index member
    simp only [List.mem_cons, List.not_mem_nil, or_false] at member
    rcases member with rfl | rfl | rfl | rfl | rfl
    · exact topology.declarationNode.inside
    · exact topology.blockNode.inside
    · exact topology.listNode.inside
    · exact topology.statementNode.inside
    · exact topology.optionalNode.inside
  have bound := input.tree.routeBound _ topology.distinct inside
  simp only [List.length_cons, List.length_nil] at bound
  omega
theorem TerminalTopology.tokensPositive (topology : TerminalTopology input heap declaration) : 0 < input.tokenCount :=
  Nat.zero_lt_of_lt topology.returnToken.inside

#print axioms Tree.routeBound
#print axioms NativeToken.read
#print axioms TerminalTopology.depth
#print axioms TerminalTopology.tokensPositive

end IRBodyProductionInputs
