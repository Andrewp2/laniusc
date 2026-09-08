import Lanius.Extraction.SemanticTokens.Collect.Call

namespace Lanius.Extraction.Tests.SemanticCollect

open Lanius.Core Lanius.Semantics Lanius.Extraction.SemanticTokens.Collect

private def symbols : Symbols := ⟨1, 2⟩
private def program : Program := {
  constants := [⟨1, i32, .signed .i32 1⟩, ⟨2, i32, .signed .i32 2⟩]
}

private def callProgram : Program := { program with
  functions := [⟨70, parameters, i32, some (body symbols), none⟩]
}

private def checkWholeBody : IO Unit := do
  let complete := body symbols
  let some matched := checkBody? complete | throw (IO.userError "complete collector body was rejected")
  unless matched.locals.childToken == 1 && matched.locals.childState == 2 do
    throw (IO.userError "collector checker changed global tag identities")
  let .sequence first tail := complete | throw (IO.userError "collector first guard is missing")
  for changed in [tail, .sequence .skip tail, .sequence first complete,
      .sequence complete (.expression (.assign .set (.local 77) (number 0)))] do
    unless (checkBody? changed).isNone do
      throw (IO.userError "collector checker accepted a partial, duplicated, or changed function body")
  unless (checkChildBody? (childBody symbols)).isSome &&
      (checkBody? (childBody symbols)).isNone do
    throw (IO.userError "collector checker confused a child-loop fragment with the complete function")
#eval checkWholeBody

-- No array locals are present. Any premature buffer access traps instead of
-- satisfying this rejection test; neither traps nor exhaustion count as errors.
private def checkRejections : IO Unit := do
  for grammarLength in ([16, 17] : List Int) do
    for tokenCount in ([-1, 0, 1, 1073741823, 1073741824] : List Int) do
      for nodeCount in ([-1, 0] : List Int) do
        for recordsLength in ([-1, 0] : List Int) do
          for capacity in ([-1, 0, 1, 2] : List Int) do
            let bad := grammarLength <= 16 || tokenCount < 0 || tokenCount >= 1073741824 ||
              nodeCount < 0 || recordsLength < 0
            let short := capacity < 0 || capacity / 2 < tokenCount
            if bad || short then
              let before := ((((({} : State).bindLocal 1 (.signed .i32 grammarLength)).bindLocal 3
                (.signed .i32 tokenCount)).bindLocal 7 (.signed .i32 nodeCount)).bindLocal 5
                (.signed .i32 recordsLength)).bindLocal 9 (.signed .i32 capacity)
              let wanted : Int := if bad then -1 else -2
              match execStmt 100 program before (body symbols) with
              | .done (.returned (some (.signed .i32 result))) after =>
                unless result == wanted && after.cells.map (fun cell => (cell.id, cell.value)) ==
                    before.cells.map (fun cell => (cell.id, cell.value)) && after.locals == before.locals &&
                    after.nextCell == before.nextCell do
                  throw (IO.userError s!"collector guard returned {result} instead of {wanted}, or changed caller state")
              | _ => throw (IO.userError "collector guard trapped, exhausted, or returned the wrong value type")
#eval checkRejections

private def checkInitialization : IO Unit := do
  for count in [0, 1, 3, 17] do
    for spare in [0, 1, 3] do
      let original := (List.range (count * 2 + spare)).map (fun n => ((100 + n : Nat) : Int))
      let before : State := {
        cells := [⟨0, some (.array (signedI32Values original))⟩]
        nextCell := 1
      }
      let before := (((before.bindLocal 8 (.slice i32 0 [] 0 original.length)).bindLocal 3
        (.signed .i32 count)).bindLocal 12 (.signed .i32 999)).bindLocal 77 (.signed .i32 777)
      let statement := declare 12 (number 0) (.sequence initializeLoop (returned (number 0)))
      match execStmt 500 program before statement with
      | .done (.returned (some (.signed .i32 0))) after =>
        unless after.cell? 0 == some (.array (signedI32Values (List.replicate (count * 2) (-1) ++
            original.drop (count * 2)))) && after.locals == before.locals do
          throw (IO.userError s!"initialization changed the wrong prefix/suffix or did not restore scope at {count}/{spare}")
        for entry in before.cells do
          if entry.id != 0 then
            let some current := after.cellEntry? entry.id
              | throw (IO.userError "initialization removed a caller cell")
            unless current.id == entry.id && current.value == entry.value do
              throw (IO.userError "initialization changed caller storage outside the output buffer")
      | _ => throw (IO.userError "initialization trapped, exhausted, or returned the wrong result")
#eval checkInitialization

private def checkFrame (before after : State) (written : List Lanius.CellId) : IO Unit := do
  unless after.locals == before.locals do
    throw (IO.userError "semantic child changed caller locals")
  for entry in before.cells do
    if !written.contains entry.id then
      let some current := after.cellEntry? entry.id
        | throw (IO.userError "semantic child removed an old cell")
      unless current.id == entry.id && current.value == entry.value do
        throw (IO.userError s!"semantic child changed framed cell {entry.id}")

-- Whole ordinary/whole split/first virtual/second virtual tokens. The other
-- assignment slot may already have been written by an earlier postorder node.
private def checkTokenChildren : IO Unit := do
  let grammarWords : List Int := [1, 4, 0, 0, 0, 12, 11, 17] ++ List.replicate 9 0 ++ [10, 11, 12, 11]
  for (raw, kind, position, finish) in ([(10, 0, 0, 2), (12, 2, 0, 2),
      (12, 1, 0, 1), (12, 3, 1, 2)] : List (Int × Int × Nat × Nat)) do
    for spare in [0, 3] do
      for occupied in [false, true] do
        let slot := position % 2
        let original := ([31, 37] : List Int).set slot (if occupied then 41 else -1) ++ List.replicate spare 777
        let recordWords : List Int := [0, position, finish, 1, 1, 0, kind]
        let before : State := {
          cells := [⟨0, some (.array (signedI32Values grammarWords))⟩,
            ⟨1, some (.array (signedI32Values [raw]))⟩,
            ⟨2, some (.array (signedI32Values recordWords))⟩,
            ⟨3, some (.array (signedI32Values original))⟩]
          nextCell := 4
        }
        let before := ([(0, .slice i32 0 [] 0 grammarWords.length), (2, .slice i32 1 [] 0 1),
          (4, .slice i32 2 [] 0 recordWords.length), (8, .slice i32 3 [] 0 original.length),
          (3, .signed .i32 1), (10, .signed .i32 4), (11, .signed .i32 17),
          (16, .signed .i32 position), (18, .signed .i32 4), (19, .signed .i32 0),
          (20, .signed .i32 120), (21, .signed .i32 121), (22, .signed .i32 122),
          (23, .signed .i32 123)] : List (Lanius.VarId × Value)).foldl
            (fun state binding => state.bindLocal binding.1 binding.2) before
        let some cursorCell := before.cellId? 16 | throw (IO.userError "missing token cursor")
        match execStmt 300 program before tokenBody with
        | .done completion after =>
          let correctStatus := match completion with
            | .next => !occupied
            | .returned (some (.signed .i32 (-1))) => occupied
            | _ => false
          let expected := if occupied then original else original.set slot kind
          unless correctStatus && after.local? 16 == some (.signed .i32 (if occupied then position else finish)) &&
              after.cell? 3 == some (.array (signedI32Values expected)) do
            throw (IO.userError s!"token branch changed status, position, or assignment at kind {kind}, position {position}, occupied {occupied}")
          checkFrame before after [3, cursorCell]
        | _ => throw (IO.userError "token branch trapped or exhausted")
#eval checkTokenChildren

private def checkNodeChildren : IO Unit := do
  for (start, finish) in ([(0, 0), (1, 2), (2, 6)] : List (Nat × Nat)) do
    for spare in [0, 3] do
      let words : List Int := [0, start, finish, 1, 2, 0, 0, 0, start, finish, 0]
      let before : State := {
        cells := [⟨0, some (.array (signedI32Values (words ++ List.replicate spare 777)))⟩,
          ⟨1, some (.array (signedI32Values [7, 0, 888]))⟩]
        nextCell := 2
      }
      let before := ([(4, .slice i32 0 [] 0 (words.length + spare)), (6, .slice i32 1 [] 0 3),
        (5, .signed .i32 words.length), (3, .signed .i32 3), (13, .signed .i32 1),
        (16, .signed .i32 start), (18, .signed .i32 4), (19, .signed .i32 0),
        (20, .signed .i32 120)] : List (Lanius.VarId × Value)).foldl
          (fun state binding => state.bindLocal binding.1 binding.2) before
      let some cursorCell := before.cellId? 16 | throw (IO.userError "missing node cursor")
      match execStmt 200 program before (nodeChildBody symbols) with
      | .done .next after =>
        unless after.local? 16 == some (.signed .i32 finish) do
          throw (IO.userError "state child moved to the wrong span endpoint")
        checkFrame before after [cursorCell]
      | _ => throw (IO.userError "state child trapped, exhausted, or rejected a valid span")
#eval checkNodeChildren

private def checkWrittenHistory : IO Unit := do
  let uses : List Lanius.Extraction.SemanticTokens.Use := [⟨0, 2, 0, 0⟩, ⟨2, 4, 1, 2⟩, ⟨4, 5, 2, 1⟩, ⟨5, 6, 2, 3⟩]
  for order in [uses, uses.reverse, uses.drop 3 ++ uses.take 3, uses.drop 2 ++ uses.take 2] do
    for spare in [0, 3] do
      let original : List Int := List.replicate (6 + spare) 777
      for index in List.range (order.length + 1) do
        let current := written original 3 (order.take index)
        unless current.length == original.length && current.drop 6 == original.drop 6 do
          throw (IO.userError "assignment history changed capacity or spare output")
        for use in order.drop index do
          unless current[use.slot]? == some (-1) do
            throw (IO.userError "a unique unvisited assignment slot was already written")
      unless written original 3 order == [0, -1, 2, -1, 1, 3] ++ List.replicate spare 777 do
        throw (IO.userError "assignment history depends on postorder visitation order")
      let some assignments := Lanius.Extraction.SemanticTokens.assignmentsFrom? order 0 3
        | throw (IO.userError "complete write history has no assignment vector")
      unless written original 3 order == assignments.flatMap Lanius.Extraction.SemanticTokens.Assignment.words ++ original.drop 6 do
        throw (IO.userError "physical write history differs from the logical assignment vector")
#eval checkWrittenHistory

-- Exercise the actual final-validation loop, not just the Boolean checker.
-- Whole split-token uses, paired halves, negative/mismatched words, spare
-- capacity, and pre-existing names shadowed by the two temporary locals.
private def checkFinalValidation : IO Unit := do
  let grammarWords : List Int := [1, 4, 2, 2, 0, 12, 11, 17] ++ List.replicate 9 0 ++ [10, 11, 12, 11]
  let cases : List (List Int × List Int × Bool) := [([], [], true), ([10], [0, -1], true),
    ([12], [2, -1], true), ([12], [1, 3], true), ([10, 12, 12], [0, -1, 2, -1, 1, 3], true),
    ([10], [-1, -1], false), ([10], [1, -1], false), ([12], [1, -1], false),
    ([12], [1, 2], false), ([10], [1, 3], false)]
  for (kinds, assignments, accepted) in cases do
    for spare in [0, 3] do
      let words := assignments ++ List.replicate spare 777
      let heap : State := { cells := [⟨0, some (.array (signedI32Values grammarWords))⟩,
        ⟨1, some (.array (signedI32Values (kinds ++ [555])))⟩,
        ⟨2, some (.array (signedI32Values words))⟩], nextCell := 3 }
      for start in (if accepted then List.range (kinds.length + 1) else [0]) do
        let before := ([(0, .slice i32 0 [] 0 grammarWords.length), (2, .slice i32 1 [] 0 (kinds.length + 1)),
          (8, .slice i32 2 [] 0 words.length), (3, .signed .i32 kinds.length), (11, .signed .i32 17),
          (12, .signed .i32 start), (24, .signed .i32 124), (25, .signed .i32 125)] : List (Lanius.VarId × Value)).foldl
          (fun state binding => state.bindLocal binding.1 binding.2) heap
        let some cursorCell := before.cellId? 12 | throw (IO.userError "missing validation cursor")
        match execStmt 500 program before validationLoop with
        | .done .next after =>
          unless accepted && after.local? 12 == some (.signed .i32 kinds.length) do
            throw (IO.userError "final validation accepted bad assignments or stopped at the wrong token")
          checkFrame before after [cursorCell]
        | .done (.returned (some (.signed .i32 (-1)))) after =>
          if accepted then throw (IO.userError "final validation rejected a valid assignment vector")
          checkFrame before after [cursorCell]
        | _ => throw (IO.userError "final validation trapped, exhausted, or returned the wrong status")
#eval checkFinalValidation

-- The public capacity error must not dereference any of the five inputs.
private def checkCapacityCalls : IO Unit := do
  for count in [1, 3, 1073741823] do
    for capacity in [0, count * 2 - 1] do
      let before := (List.range 26).foldl (fun state id => state.bindLocal id (.signed .i32 (Int.ofNat (100 + id)))) ({} : State)
      let values := argumentValues .unit .unit .unit .unit .unit 17 count 0 0 (Int.ofNat capacity)
      match evalExpr 100 callProgram before (.call 70 (values.map Expr.value)) with
      | .done (.signed .i32 (-2)) after => checkFrame before after []
      | _ => throw (IO.userError "public capacity rejection touched invalid buffers or returned the wrong status")
#eval checkCapacityCalls

-- Resume at every child boundary, including zero remaining children. The
-- nested record assigns the second virtual half before its parent's first half.
private def checkRecordChildren : IO Unit := do
  let grammar : Lanius.Compiler.Parser.IndexedGrammar := {
    grammar := ⟨4, 2, 0, 12, 11, [10, 11, 12, 11], [⟨0, [0, 2, 1, 5]⟩, ⟨1, [3]⟩]⟩
    productionsByLhs := [[0], [1]]
  }
  let fullTree : Lanius.Compiler.Parser.ParseTree := .nonterminal 0 0 0 6
    [.terminal 0 0, .terminal 1 2, .terminal 2 1, .nonterminal 1 1 5 6 [.terminal 2 3]]
  let emptyTree : Lanius.Compiler.Parser.ParseTree := .nonterminal 0 0 0 0 []
  let grammarWords : List Int := [1, 4, 2, 2, 0, 12, 11, 17] ++ List.replicate 9 0 ++ [10, 11, 12, 11]
  for (tree, kinds) in [(fullTree, [10, 12, 12]), (emptyTree, [])] do
    let layout := Lanius.Extraction.ParserTreeLayout.treeFrom 0 0 tree
    let records := (Lanius.Extraction.SemanticTokens.treeVisits grammar kinds 0 0 0 tree).1
    for spare in [0, 3] do
      let original : List Int := List.replicate (kinds.length * 2 + spare) 777
      for node in List.range records.length do
        let some record := records[node]? | throw (IO.userError "missing record fixture")
        let prior := priorUses records node
        let expected := written original kinds.length (priorUses records (node + 1))
        for index in List.range (record.children.length + 1) do
          let position := match record.children[index]? with | some child => child.start | none => record.finish
          let visited := prior ++ (record.children.take index).flatMap Lanius.Extraction.SemanticTokens.ChildVisit.uses
          let initial := written original kinds.length visited
          let before : State := {
            cells := [⟨0, some (.array (signedI32Values grammarWords))⟩,
              ⟨1, some (.array (signedI32Values (kinds.map Int.ofNat ++ [555])))⟩,
              ⟨2, some (.array (signedI32Values (layout.words ++ [444])))⟩,
              ⟨3, some (.array (signedI32Values (layout.offsets.map Int.ofNat ++ [-1])))⟩,
              ⟨4, some (.array (signedI32Values initial))⟩]
            nextCell := 5
          }
          let before := ([(0, .slice i32 0 [] 0 grammarWords.length), (2, .slice i32 1 [] 0 (kinds.length + 1)),
            (4, .slice i32 2 [] 0 (layout.words.length + 1)), (6, .slice i32 3 [] 0 (layout.offsets.length + 1)),
            (8, .slice i32 4 [] 0 initial.length), (3, .signed .i32 kinds.length), (5, .signed .i32 layout.words.length),
            (7, .signed .i32 records.length), (10, .signed .i32 4), (11, .signed .i32 17), (13, .signed .i32 node),
            (14, .signed .i32 record.offset), (15, .signed .i32 record.children.length), (16, .signed .i32 position),
            (17, .signed .i32 index), (18, .signed .i32 118), (19, .signed .i32 119), (20, .signed .i32 120),
            (21, .signed .i32 121), (22, .signed .i32 122), (23, .signed .i32 123)] : List (Lanius.VarId × Value)).foldl
              (fun state binding => state.bindLocal binding.1 binding.2) before
          let mut changed := [4]
          for id in ([13, 16, 17] : List Lanius.VarId) do
            let some cell := before.cellId? id | throw (IO.userError "missing loop cursor")
            changed := cell :: changed
          match execStmt 1000 program before (recordChildren symbols) with
          | .done .next after =>
            unless after.local? 13 == some (.signed .i32 (Int.ofNat (node + 1))) &&
                after.local? 16 == some (.signed .i32 record.finish) &&
                after.local? 17 == some (.signed .i32 record.children.length) &&
                after.cell? 4 == some (.array (signedI32Values expected)) do
              throw (IO.userError s!"record loop changed its endpoint, indices, or assignments at node {node}, child {index}")
            checkFrame before after changed
          | _ => throw (IO.userError "record loop trapped, exhausted, or rejected the selected path")
          if index == 0 then
            let complete := written original kinds.length (records.flatMap Lanius.Extraction.SemanticTokens.RecordVisit.uses)
            let some nodeCell := before.cellId? 13 | throw (IO.userError "missing outer node cursor")
            match execStmt 2000 program before (nodeLoop symbols) with
            | .done .next after =>
              unless after.local? 13 == some (.signed .i32 records.length) &&
                  after.cell? 4 == some (.array (signedI32Values complete)) do
                throw (IO.userError s!"outer traversal changed its endpoint or assignments when resumed at node {node}")
              checkFrame before after [4, nodeCell]
              for start in List.range (kinds.length + 1) do
                let ready := after.bindLocal 12 (.signed .i32 start)
                let some cursorCell := ready.cellId? 12 | throw (IO.userError "missing validation cursor after traversal")
                match execStmt 500 program ready validationLoop with
                | .done .next checked =>
                  unless checked.local? 12 == some (.signed .i32 kinds.length) do
                    throw (IO.userError "validation of collected assignments stopped early")
                  checkFrame ready checked [cursorCell]
                | _ => throw (IO.userError "final validation rejected actual traversal output")
              match execStmt 20 program after (nodeLoop symbols) with
              | .done .next unchanged =>
                unless unchanged.nextCell == after.nextCell && unchanged.cells.map (fun cell => (cell.id, cell.value)) ==
                    after.cells.map (fun cell => (cell.id, cell.value)) do
                  throw (IO.userError "completed outer traversal allocated or changed cells")
                checkFrame after unchanged []
              | _ => throw (IO.userError "completed outer traversal did not terminate immediately")
            | _ => throw (IO.userError "outer traversal trapped, exhausted, or rejected the selected tree")
            if node == 0 then
              let scopedRun := declare 13 (number 0) (.sequence (nodeLoop symbols) (returned (number 0)))
              match execStmt 2000 program before scopedRun with
              | .done (.returned (some (.signed .i32 0))) after =>
                unless after.cell? 4 == some (.array (signedI32Values complete)) do
                  throw (IO.userError "scoped outer traversal changed final assignments")
                checkFrame before after [4]
              | _ => throw (IO.userError "scoped outer traversal did not finish normally")
              let some rawBefore := before.assignCell 4 (.array (signedI32Values original))
                | throw (IO.userError "missing initial assignment storage")
              let rawBefore := rawBefore.bindLocal 12 (.signed .i32 112)
              match execStmt 2000 program rawBefore (loops symbols) with
              | .done (.returned (some (.signed .i32 0))) after =>
                unless after.cell? 4 == some (.array (signedI32Values complete)) do
                  throw (IO.userError "complete collector loops did not produce the exact assignment vector")
                checkFrame rawBefore after [4]
              | _ => throw (IO.userError "complete collector loops failed from arbitrary output contents")
              let caller := (rawBefore.bindLocal 1 (.signed .i32 grammarWords.length)).bindLocal 9 (.signed .i32 original.length)
              match execStmt 2000 program caller (body symbols) with
              | .done (.returned (some (.signed .i32 0))) after =>
                unless after.cell? 4 == some (.array (signedI32Values complete)) do
                  throw (IO.userError "whole collector body changed its exact assignment result")
                checkFrame caller after [4]
              | _ => throw (IO.userError "whole collector body failed on the selected tree")
              let values := argumentValues (.slice i32 0 [] 0 grammarWords.length)
                (.slice i32 1 [] 0 (kinds.length + 1)) (.slice i32 2 [] 0 (layout.words.length + 1))
                (.slice i32 3 [] 0 (layout.offsets.length + 1)) (.slice i32 4 [] 0 original.length)
                grammarWords.length kinds.length layout.words.length records.length original.length
              match evalExpr 2000 callProgram rawBefore (.call 70 (values.map Expr.value)) with
              | .done (.signed .i32 0) after =>
                unless after.cell? 4 == some (.array (signedI32Values complete)) do
                  throw (IO.userError "public collector call confused logical lengths with spare capacity")
                checkFrame rawBefore after [4]
              | _ => throw (IO.userError "public collector call failed from caller-owned buffers")
#eval checkRecordChildren

#print axioms initialize_loop
#print axioms InitializeEntry.execute
#print axioms InitializeEntry.continue
#print axioms InputScalars.reject
#print axioms InputScalars.reject_negative_capacity
#print axioms InputScalars.reject_short_capacity
#print axioms GrammarData.setup
#print axioms record_header_read
#print axioms record_child_read
#print axioms node_child_execute
#print axioms token_advance_execute
#print axioms token_store_execute
#print axioms token_child_execute
#print axioms written_available
#print axioms ChildOwned.bindLocal
#print axioms ChildOwned.advance
#print axioms child_step
#print axioms child_loop
#print axioms record_children_execute
#print axioms record_count_guard_pass
#print axioms NodeOwned.children
#print axioms node_step
#print axioms node_loop
#print axioms NodeEntry.invariant
#print axioms NodeEntry.execute
#print axioms written_assignments
#print axioms Lanius.Extraction.SemanticTokens.CollectionRecords.written
#print axioms NodeOwned.assignments
#print axioms validation_checks
#print axioms validation_step
#print axioms validation_loop
#print axioms LoopEntry.initialized
#print axioms LoopEntry.execute
#print axioms Lanius.Extraction.SemanticTokens.selected_collection_records
#print axioms Entry.input_pass
#print axioms Entry.capacity_pass
#print axioms Entry.execute
#print axioms CheckedCollect.execute_body
#print axioms CallStorage.entry
#print axioms CheckedCollect.call_evaluates
#print axioms CheckedCollect.short_capacity_call

end Lanius.Extraction.Tests.SemanticCollect
