import verified_compiler.tests.direct_ir_catalog_append_contract

namespace IRCatalogAppendProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRTypeRefProof

def scan : Expr × Stmt := source.whileLoop 0
def priorId : VarId := source.bindingId 4

theorem actualPriorShape : source.bindingStatement 4 =
    .letLocal priorId (.scalar (.signed .i32)) (.value (.signed .i32 0))
      (.sequence (.whileLoop scan.1 scan.2) (source.bindingStatement 5)) := by rfl

theorem Input.rowLocation (input : Input caller) (guarded : input.Guarded)
    (inside : index < input.occupied) :
    rawSliceElementAddress? extractedProgram bodyType input.rowsAddress index = .ok (input.rowBase index) := by
  apply rawSliceElementAddress_of_layout (words := 12) rfl (by decide +kernel) (by decide)
  · have floor := input.rowFloor guarded; omega
  · have floor := input.rowFloor guarded
    dsimp only [Arguments.rowBase]
    omega

theorem Input.rowRead (input : Input caller) (guarded : input.Guarded)
    (sameHeap : state.heap = caller.heap) (inside : index < input.occupied) :
    readRawSliceIndex extractedProgram state bodyType input.rowsAddress input.rowsLength index =
      .ok (input.previous index).value := by
  have bound : index < input.rowsLength := Nat.lt_of_lt_of_le inside (input.rowBound guarded)
  rw [readRawSliceIndex, if_neg (Nat.not_le_of_lt bound), input.rowLocation guarded inside]
  change readNativeValue 64 extractedProgram state.heap IRCatalogStoreProof.bodyType (input.rowBase index) = _
  simpa only [sameHeap] using (input.rowSnapshots guarded index inside).read

/-- One bounded, read-only nominal-ID scan; no assumption about duplicate absence. -/
theorem actualScan (input : Input caller) (guarded : input.Guarded)
    (formed : base.CellsWellFormed) (heap : base.heap = caller.heap)
    (signatureFound : base.local? (source.argumentId 1) = some input.signature)
    (rowsFound : base.local? (source.bindingId 1) = some input.rows)
    (nextFound : base.local? (source.bindingId 3) = some (.signed .i32 input.next.toInt)) :
    ∃ completion after, RunsStmt extractedProgram (base.bindLocal priorId (.signed .i32 0))
      (.whileLoop scan.1 scan.2) completion after ∧ CallerFrame base after ∧
      ((completion = .next ∧ ¬input.Duplicate) ∨
       (completion = .returned (some (.signed .i32 (-1))) ∧ input.Duplicate)) := by
  have nonnegative := guarded.2.2.2.1
  have nextNat : input.next.toInt = (input.occupied : Int) := by
    dsimp only [Arguments.occupied]; omega
  rw [nextNat] at nextFound
  let invariant := fun remaining current => ∃ position : Nat,
    position + remaining = input.occupied ∧ CountedLocal base current priorId position ∧
    current.heap = base.heap ∧ current.world = base.world ∧ current.i32ArrayViews = base.i32ArrayViews ∧
    ∀ index, index < position → (input.previous index).id.toInt ≠ input.id.toInt
  let post := fun (completion : Completion) (after : State) => CallerFrame base after ∧
    ((completion = .next ∧ ¬input.Duplicate) ∨
     (completion = .returned (some (.signed .i32 (-1))) ∧ input.Duplicate))
  apply RunsStmt.whileCountOrReturn (remaining := input.occupied) invariant post
  · intro current initial
    obtain ⟨position, finished, frame, sameHeap, sameWorld, sameViews, absent⟩ := initial
    have equal : position = input.occupied := by omega
    subst position
    have priorFound := frame.counter
    have countFound := frame.read (source.bindingId 3) _ (by decide +kernel) nextFound
    refine ⟨current, ?_, ⟨formed, frame.cells, sameHeap, sameWorld, sameViews⟩, Or.inl ⟨rfl, ?_⟩⟩
    · core_run
    · rintro ⟨index, inside, sameId⟩
      exact absent index inside sameId
  · intro remaining current initial
    obtain ⟨position, progress, frame, sameHeap, sameWorld, sameViews, absent⟩ := initial
    have inside : position < input.occupied := by omega
    have priorFound := frame.counter
    have countFound := frame.read (source.bindingId 3) _ (by decide +kernel) nextFound
    have signatureFound := frame.read (source.argumentId 1) _ (by decide +kernel) signatureFound
    have rowsFound := frame.read (source.bindingId 1) _ (by decide +kernel) rowsFound
    have row := input.rowRead guarded (sameHeap.trans heap) inside
    refine ⟨current, ?_, ?_⟩
    · core_run
    by_cases sameId : (input.previous position).id.toInt = input.id.toInt
    · refine Or.inr ⟨current, some (.signed .i32 (-1)), ?_,
        ⟨formed, frame.cells, sameHeap, sameWorld, sameViews⟩, Or.inr ⟨rfl, position, inside, sameId⟩⟩
      dsimp only [scan, PreviousRow.value, IRCatalogStoreProof.body, IRCatalogStoreProof.signature,
        Arguments.signature] at *
      core_stmt
    · have fits : position + 1 < 2 ^ 31 :=
        Nat.lt_of_le_of_lt (by omega) input.toArguments.occupiedFits
      obtain ⟨next, increment, counted, nextHeap, nextWorld, nextViews⟩ :=
        frame.increment (program := extractedProgram) formed fits
      refine Or.inl ⟨next, .next, ?_, Or.inl rfl, position + 1, by omega, counted,
        nextHeap.trans sameHeap, nextWorld.trans sameWorld, nextViews.trans sameViews, ?_⟩
      · dsimp only [scan, PreviousRow.value, IRCatalogStoreProof.body, IRCatalogStoreProof.signature,
          Arguments.signature] at *
        core_stmt_forward
      · intro index earlier
        by_cases equal : index = position
        · simpa only [equal] using sameId
        · exact absent index (by omega)
  · exact ⟨0, by omega, CountedLocal.start formed _ _, rfl, rfl, rfl,
      fun index earlier => False.elim (Nat.not_lt_zero _ earlier)⟩

#print axioms actualScan

end IRCatalogAppendProof
