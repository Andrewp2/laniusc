import verified_compiler.tests.direct_ir_body_production_scalar_memory
import verified_compiler.tests.direct_ir_body_production_inputs_signature
import verified_compiler.tests.direct_ir_catalog_append_post

namespace IRBodyProductionInputs

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRBodyProductionScalar

variable {before after : State}

/-- Logical source spans and the single selected original signature. Physical
    spare capacities are not part of the readonly requirement. -/
def sourceBytes (input : Inputs) (native : NativeSignature input.signature heap) (address : Nat) : Prop :=
  ((∃ index base, index < input.tree.nodeCount ∧
      rawSliceElementAddress? extractedProgram nodeType input.tree.nodes index = .ok base ∧
      base ≤ address ∧ address < base + 40) ∨
    (∃ index base, index < input.tree.childCount ∧
      rawSliceElementAddress? extractedProgram childType input.tree.children index = .ok base ∧
      base ≤ address ∧ address < base + 24) ∨
    (∃ pointer length index base, input.tokens = .rawSlice tokenType pointer length ∧
      index < input.tokenCount ∧ rawSliceElementAddress? extractedProgram tokenType pointer index = .ok base ∧
      base ≤ address ∧ address < base + 24) ∨
    (∃ pointer length index, input.source = .rawSlice (.scalar (.signed .i32)) pointer length ∧
      index < input.sourceLength ∧ pointer + index * 4 ≤ address ∧ address < pointer + index * 4 + 4)) ∨
  (native.base ≤ address ∧ address < native.base + 72)

theorem sourceBytes.apart {native : NativeSignature input.signature heap} (apart : InputApart input allowed)
    (signature : ∀ address, native.base ≤ address → address < native.base + 72 → ¬allowed address)
    (inside : sourceBytes input native address) : ¬allowed address := by
  rcases inside with original | selected
  · rcases original with node | child | token | word
    · rcases node with ⟨index, base, bound, location, lower, upper⟩
      exact apart.nodes index base bound location address lower upper
    · rcases child with ⟨index, base, bound, location, lower, upper⟩
      exact apart.children index base bound location address lower upper
    · rcases token with ⟨pointer, length, index, base, descriptor, bound, location, lower, upper⟩
      exact apart.tokens pointer length index base descriptor bound location address lower upper
    · rcases word with ⟨pointer, length, index, descriptor, bound, lower, upper⟩
      exact apart.source pointer length descriptor index bound address lower upper
  · exact signature address selected.1 selected.2

/-- Compose the actual locals allocation, workspace writes (including the
    fresh count cell), and public append frame on original successful bytes. -/
theorem sourceBytes.readonly {caller produced : State} {allocated final : Heap}
    (native : NativeSignature input.signature caller.heap)
    (below : HeapBlocksBelowNext caller.heap) (reads : HeapReads caller.heap allocated)
    (fresh : caller.heap.nextAddress ≤ memory)
    (write : HeapWritesOn allocated produced.heap
      (fun address => allowed address ∨ (memory ≤ address ∧ address < memory + 4)))
    (apart : InputApart input allowed)
    (signature : ∀ address, native.base ≤ address → address < native.base + 72 → ¬allowed address)
    (post : IRCatalogAppendProof.Post model produced answer final world views)
    (catalog : ∀ address, sourceBytes input native address →
      ¬(model.Success produced.heap ∧ model.footprint address)) :
    ∀ pointer offset byte, sourceBytes input native (pointer + offset) →
      caller.heap.loadByte pointer offset = .ok byte → final.loadByte pointer offset = .ok byte := by
  intro pointer offset byte inside loaded
  have nonmutable := sourceBytes.apart apart signature inside
  have nonfresh : ¬(memory ≤ pointer + offset ∧ pointer + offset < memory + 4) := by
    obtain ⟨block, found, _⟩ := Heap.loadByte_ok_iff.mp loaded
    have contained := List.find?_some found
    have frontier := below block (List.mem_of_find?_eq_some found)
    simp only [Bool.and_eq_true, decide_eq_true_eq] at contained
    dsimp only [Lanius.Address] at *
    omega
  have retained : produced.heap.loadByte pointer offset = .ok byte := by
    rw [write.outside _ _ (fun changed => changed.elim nonmutable nonfresh)]
    exact reads _ _ _ loaded
  exact post.outside pointer offset byte retained (catalog _ inside)

/-- The original reached topology survives the real workspace/output union
    footprint. No whole-heap read preservation or new syntax data is assumed. -/
def TerminalTopology.afterFootprint (topology : TerminalTopology input before.heap declaration)
    (write : HeapWritesOn before.heap after.heap allowed) (apart : InputApart input allowed) :
    TerminalTopology input after.heap declaration :=
  let node {index : Nat} (value : NativeNode input.tree before.heap index) : NativeNode input.tree after.heap index :=
    { value with snapshot := value.snapshot.afterFootprint write (apart.nodes _ _ value.inside value.location) }
  let child {index : Nat} (value : NativeChild input.tree before.heap index) : NativeChild input.tree after.heap index :=
    { value with snapshot := value.snapshot.afterFootprint write (apart.children _ _ value.inside value.location) }
  { topology with
    declarationNode := node topology.declarationNode
    bodyChild := child topology.bodyChild
    blockNode := node topology.blockNode
    listChild := child topology.listChild
    listNode := node topology.listNode
    firstChild := child topology.firstChild
    restChild := child topology.restChild
    restNode := node topology.restNode
    statementNode := node topology.statementNode
    optionalChild := child topology.optionalChild
    optionalNode := node topology.optionalNode
    returnChild := child topology.returnChild
    returnToken := { topology.returnToken with
      snapshot := topology.returnToken.snapshot.afterFootprint write
        (apart.tokens _ _ _ _ topology.returnToken.descriptor topology.returnToken.inside topology.returnToken.location) } }

#print axioms TerminalTopology.afterFootprint
#print axioms sourceBytes.apart
#print axioms sourceBytes.readonly

end IRBodyProductionInputs
