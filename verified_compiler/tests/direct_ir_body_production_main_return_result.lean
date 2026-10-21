import verified_compiler.tests.direct_ir_body_production_main_outer

namespace IRBodyProductionProof

open Lanius Lanius.Core Lanius.Semantics

def producerReturnTail : Stmt :=
  match producerSource.bindingStatement 31 with
  | .letLocal _ _ _ rest => rest
  | _ => .skip

/-- The actual final guard maps an inserted row index to zero and any
    negative append result to the real invalid-result call. -/
theorem actualProducerReturn (index : Int32)
    (found : before.local? (producerSource.bindingId 31) = some (.signed .i32 index.toInt))
    (formed : before.CellsWellFormed) : ∃ after,
    RunsStmt extractedProgram before producerReturnTail
      (.returned (some (.signed .i32 (if 0 ≤ index.toInt then 0 else -1)))) after ∧
    PureFrame before after := by
  have lower := index.le_toInt
  have upper := index.toInt_lt
  by_cases accepted : 0 ≤ index.toInt
  · simp only [if_pos accepted]
    core_pure
  · simp only [if_neg accepted]
    core_pure

#print axioms actualProducerReturn

end IRBodyProductionProof
