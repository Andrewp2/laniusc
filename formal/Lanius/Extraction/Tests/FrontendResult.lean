import Lanius.Extraction.Frontend.Tree
import Lanius.Extraction.Frontend.Syntax
import Lanius.Extraction.Frontend.Body
import Lanius.Extraction.Frontend.Call

open Lanius.Core Lanius.Semantics Lanius.Extraction.Frontend

private def symbols : FinishSymbols := ⟨1, 2, 3, 4, 10, 11, 12⟩

private def accessor (id field : Nat) : Function :=
  ⟨id, [(0, .structure 6)], .scalar (.signed .i32), some (Lanius.Extraction.Source.projectionBody field), none⟩

private def program : Program := {
  functions := [⟨1, syntaxResultParameters, .structure 7, some (syntaxResultBody 7), none⟩,
    accessor 2 0, accessor 3 1, accessor 4 2]
  constants := [⟨10, .scalar (.signed .i32), .signed .i32 0⟩,
    ⟨11, .scalar (.signed .i32), .signed .i32 5⟩, ⟨12, .scalar (.signed .i32), .signed .i32 0⟩,
    ⟨13, .scalar (.signed .i32), .signed .i32 2⟩, ⟨14, .scalar (.signed .i32), .signed .i32 3⟩,
    ⟨15, .scalar (.signed .i32), .signed .i32 1⟩]
}

-- Execute the complete return tail with distinct field values, and verify
-- scope restoration plus preservation of unrelated caller storage.
private def checkFinishExecution : IO Unit := do
  for code in ([0, 2, 3, 1, -1] : List Int) do
    let before := (((({} : State).bindLocal 18 (.signed .i32 31)).bindLocal 20 (.signed .i32 17)).bindLocal 23
      (Lanius.Extraction.ParserTreeSource.resultValue 6 code 9 73)).bindLocal 24 (.signed .i32 666)
    let before := before.bindLocal 99 (.array [.signed .i32 444, .signed .i32 555])
    match execStmt 200 program before (finishBody symbols) with
    | .done (.returned (some result)) after =>
      unless result == syntaxResult 7 (if code == 0 then 0 else 5) code 31 17 9 73 0 do
        throw (IO.userError s!"wrong syntax result fields for tree status {code}")
      unless after.locals == before.locals && after.local? 24 == before.local? 24 &&
          after.local? 99 == before.local? 99 && after.local? 18 == before.local? 18 &&
          after.local? 20 == before.local? 20 && after.local? 23 == before.local? 23 do
        throw (IO.userError s!"result tail changed caller locals/storage for tree status {code}")
    | _ => throw (IO.userError s!"result tail trapped, exhausted, or did not return for tree status {code}")
#eval checkFinishExecution

private def storageFailure (detail : Int) (tokens : Expr) : Stmt :=
  .sequence (.returnValue (some (.call 1 [.constant 14, .value (.signed .i32 detail), .local 18,
    tokens, .value (.signed .i32 0), .value (.signed .i32 0), .value (.signed .i32 0)]))) .skip

private def lexicalFailure : Stmt :=
  .sequence (.returnValue (some (.call 1 [.constant 13, .call 2 [.local 17], .local 18,
    .value (.signed .i32 0), .value (.signed .i32 0), .value (.signed .i32 0), .call 4 [.local 17]]))) .skip

private def checkGuardReturn (label : String) (before : State) (body : Stmt) (expected : Value) : IO Unit := do
  match execStmt 200 program before body with
  | .done (.returned (some result)) after =>
    unless result == expected && before.locals == after.locals do
      throw (IO.userError s!"{label}: wrong result or caller-scope change")
    for entry in before.cells do
      let some current := after.cellEntry? entry.id
        | throw (IO.userError s!"{label}: pre-existing cell {entry.id} disappeared")
      unless current.id == entry.id && current.value == entry.value do
        throw (IO.userError s!"{label}: pre-existing cell {entry.id} changed")
  | _ => throw (IO.userError s!"{label}: trapped, exhausted, or did not return")

-- Exercise error precedence without any later capacity/buffer locals. The
-- unbound suffix must remain unreachable when the lexer status is nonzero.
-- Then check both capacity boundaries, including empty input and spare words.
private def checkEarlyExecution : IO Unit := do
  let baseline := ({} : State).bindLocal 99 (.array [.signed .i32 444, .signed .i32 555])
  let tokenSymbols : TokenizationSymbols := ⟨90, 3, 2, 91, 6, 12⟩
  for code in ([1, 2] : List Int) do
    for count in ([0, 3] : List Nat) do
      let before := (baseline.bindLocal 17 (.structure 6
        [.signed .i32 code, .signed .i32 count, .signed .i32 47])).bindLocal 18 (.signed .i32 count)
      checkGuardReturn s!"lexer failure {code}/{count}" before
        (tokenGuards tokenSymbols lexicalFailure (storageFailure 0 (.value (.signed .i32 0)))
          (.expression (.call 999 []))).body (syntaxResult 7 2 code count 0 0 0 47)
  let passed : Value := .signed .i32 999
  let rest : Stmt := .returnValue (some (.value passed))
  for count in ([0, 1, 3] : List Nat) do
    for capacity in ([0, 1, 2, 3, 6, 7, 8, 9] : List Nat) do
      let counted := (baseline.bindLocal 17 (.structure 6
        [.signed .i32 0, .signed .i32 count, .signed .i32 0])).bindLocal 18 (.signed .i32 count)
      let before := counted.bindLocal 7 (.signed .i32 capacity)
      let guards : AfterLexer := ⟨17, 18, 7, 2, 12, lexicalFailure,
        storageFailure 0 (.value (.signed .i32 0)), rest⟩
      checkGuardReturn s!"canonical capacity {capacity}/{count}" before guards.body
        (if capacity < 3 * count then syntaxResult 7 3 0 count 0 0 0 0 else passed)
    for capacity in ([0, 1, 2, 3, 4] : List Nat) do
      let counted := (baseline.bindLocal 18 (.signed .i32 31)).bindLocal 20 (.signed .i32 count)
      let before := counted.bindLocal 9 (.signed .i32 capacity)
      let guards : Stmt := .sequence (.ifThenElse kindsCapacityCondition
        (storageFailure 1 (.local 20)) .skip) rest
      checkGuardReturn s!"kind capacity {capacity}/{count}" before guards
        (if capacity < count then syntaxResult 7 3 1 31 count 0 0 0 else passed)
#eval checkEarlyExecution

-- All 256 combinations of bad lengths check first-error precedence at an
-- actual 17-argument call, signed extremes, and caller-scope restoration.
-- Buffer references have no backing storage: none may be read by these guards.
private def checkInputExecution : IO Unit := do
  let passed := syntaxResult 7 0 99 0 0 0 0 0
  let body := inputGuards 1 15 inputLengths (.returnValue (some (.value passed)))
  let fn : Function := ⟨50, syntaxParameters, .structure 7, some body, none⟩
  let guardProgram := { program with functions := fn :: program.functions }
  let before := (({} : State).bindLocal 1 (.signed .i32 888)).bindLocal 99 (.array [.signed .i32 123])
  for mask in List.range 256 do
    let bad := fun index : Nat => mask / 2 ^ index % 2 == 1
    let values := (List.range 17).map fun index =>
      if index == 16 then Value.signed .i32 (-1)
      else if index % 2 == 1 then Value.signed .i32
        (if bad (index / 2) then (if index % 4 == 1 then -1 else -2147483648)
          else (if index % 4 == 1 then 0 else 2147483647))
      else Value.slice (.scalar (.signed .i32)) (100 + index) [] 0 0
    let expected := match (List.range 8).find? bad with
      | none => passed
      | some first => syntaxResult 7 1 (first + 1) 0 0 0 0 0
    match evalExpr 500 guardProgram before (.call 50 (values.map Expr.value)) with
    | .done result after =>
      unless result == expected && before.locals == after.locals do
        throw (IO.userError s!"input guards returned wrong first error or scope for mask {mask}")
      for entry in before.cells do
        let some current := after.cellEntry? entry.id
          | throw (IO.userError s!"input guards removed cell {entry.id} for mask {mask}")
        unless current.id == entry.id && current.value == entry.value do
          throw (IO.userError s!"input guards changed cell {entry.id} for mask {mask}")
    | _ => throw (IO.userError s!"input guards trapped or exhausted for mask {mask}")
#eval checkInputExecution

#print axioms CheckedResult.call
#print axioms CheckedFinish.execute
#print axioms Lanius.Extraction.ParserTreeSource.TreeRuntime.Result.preserved
#print axioms CheckedAfterParse.accepted
#print axioms CheckedAfterParse.reject
#print axioms CheckedAfterParse.rejected_outcome
#print axioms syntax_source_sequence
#print axioms syntaxPost.success
#print axioms lex_to_syntax
#print axioms CheckedEarly.lexer_failure
#print axioms CheckedEarly.canonical_full
#print axioms CheckedEarly.kinds_full
#print axioms lex_to_early_failure
#print axioms lex_to_kinds_failure
#print axioms syntax_source_all
#print axioms bodyPost.success
#print axioms lex_to_return
#print axioms inputGuards.pass
#print axioms CheckedInput.reject
#print axioms CheckedSyntax.body_executes
#print axioms CheckedSyntax.call_evaluates
#print axioms CheckedSyntax.reject_call
