import Lanius.Extraction.ParseChecker
import Lanius.Extraction.KernelReduction

namespace Lanius.Extraction

theorem boundedParseStep (grammar : Grammar) (kinds : List Nat)
    (nodes : List ParseNode) (id : Nat) (remaining : List ParseNode) (count : Nat)
    (head : checkNodesFromFast grammar kinds nodes id (remaining.take count) = true)
    (tail : checkNodesFromFast grammar kinds nodes
      (id + (remaining.take count).length) (remaining.drop count) = true) :
    checkNodesFromFast grammar kinds nodes id remaining = true := by
  calc
    _ = checkNodesFromFast grammar kinds nodes id
        (remaining.take count ++ remaining.drop count) := by
      rw [List.take_append_drop]
    _ = true := by rw [checkNodesFromFast_append, head, tail]; rfl

open Lean Meta Elab Tactic

-- Chunking changes only how the kernel checks the conjunction. Every chunk
-- and each composition step is a checked auxiliary theorem, never an axiom.
private def proveKernelParseBounded (size : Nat) (knownLength : Option Nat) : TacticM Unit := do
  if size == 0 then throwError "chunk size must be positive"
  withMainContext do
    let goal ← getMainGoal
    let target ← instantiateMVars (← goal.getType)
    let some (_, lhs, _) := target.eq?
      | throwError "expected a checkNodesFromFast equality"
    unless lhs.isAppOfArity ``checkNodesFromFast 5 do
      throwError "expected a checkNodesFromFast equality"
    let args := lhs.getAppArgs
    let grammar := args[0]!
    let kinds := args[1]!
    let nodes := args[2]!
    let initial := args[3]!
    let original := args[4]!
    let length ← match knownLength with
      | some length => pure length
      | none => do
          let mut cursor := original
          let mut length := 0
          repeat
            let value ← withTransparency .all (whnf cursor)
            if value.isAppOfArity ``List.nil 1 then break
            unless value.isAppOfArity ``List.cons 3 do
              throwError "expected a closed parse-node list"
            cursor := value.getAppArgs[2]!
            length := length + 1
          pure length
    let nodeType := mkConst ``ParseNode
    let truth := mkConst ``true
    let drop := fun offset => mkApp3 (mkConst ``List.drop [Level.zero])
      nodeType (mkNatLit offset) original
    let atId := fun offset => mkApp2 (mkConst ``Nat.add) initial (mkNatLit offset)
    let checked := fun id remaining => mkAppN (mkConst ``checkNodesFromFast)
      #[grammar, kinds, nodes, id, remaining]
    let save := fun proposition proof => do
      let name ← withOptions (Elab.async.set · false) do
        mkAuxLemma [] proposition proof
      pure (mkConst name)
    let mut proof ← save (← mkEq (checked (atId length) (drop length)) truth)
      (← mkEqRefl truth)
    let mut finish := length
    while finish != 0 do
      let start := finish - min size finish
      let count := finish - start
      let remaining := drop start
      let chunk := mkApp3 (mkConst ``List.take [Level.zero]) nodeType
        (mkNatLit count) remaining
      let head ← save (← mkEq (checked (atId start) chunk) truth) (← mkEqRefl truth)
      let combined := mkAppN (mkConst ``boundedParseStep)
        #[grammar, kinds, nodes, atId start, remaining, mkNatLit count, head, proof]
      proof ← save (← mkEq (checked (atId start) remaining) truth) combined
      finish := start
    goal.assign proof
    replaceMainGoal []

elab "kernel_parse_bounded " count:num : tactic =>
  proveKernelParseBounded count.getNat none

/-- Use a presentation-layer node count to avoid normalizing the entire emitted
list merely to choose chunk boundaries. The resulting proof still checks every
node; a wrong count cannot make a false checker equality definitionally true. -/
elab "kernel_parse_bounded_known " count:num length:num : tactic =>
  proveKernelParseBounded count.getNat (some length.getNat)

end Lanius.Extraction
