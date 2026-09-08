import Lanius.Extraction.RawLexer.LexInto.Linked
import Lanius.Extraction.RawLexer.LexInto.Caller
import Lanius.Extraction.RawLexer.LexInto.Canonicalize
import Lanius.Extraction.RawLexer.LexInto.Frame
import Lanius.Separation.SliceCopy
import Lanius.Extraction.Frontend.Lexer
import Lanius.Extraction.Frontend.Source
import Lanius.Extraction.Frontend.Canonicalize
import Lanius.Extraction.Frontend.Pipeline

open Lanius.Extraction.RawLexer.LexInto

-- The frontend passes floor(raw word length / 3), not an exact-size buffer.
-- These checks exercise spare words on success, exhaustion, and lexical error.
example : (Model.run [97] 1 [-11, -12, -13, 77]).records.drop 3 = [77] := by decide
example : (Model.run [97] 1 [-11, -12, -13, 77, 88]).records.drop 3 = [77, 88] := by decide
example : (Model.run [97] 0 [77, 88]).records = [77, 88] := by decide
example : (Model.run [] 0 [77, 88]).records = [77, 88] := by decide
example : (Model.run [97, 32, 98] 1 [-11, -12, -13, 77, 88]).records.drop 3 = [77, 88] := by decide
example : (match (Model.run [97, 32, 98] 1 [-11, -12, -13, 77, 88]).outcome with
  | .outputFull accepted _ => accepted.length == 1
  | _ => false) = true := by decide
-- A malformed token is detected before the zero-capacity check.
example : (match (Model.run [34] 0 [77, 88]).outcome with
  | .lexicalFailure accepted _ => accepted.isEmpty
  | _ => false) = true := by decide
example : (Model.run [34] 0 [77, 88]).records = [77, 88] := by decide

private def lexerPrefix : Lanius.Extraction.Frontend.LexerPrefix :=
  ⟨0, 1, 4, 5, 17, 18, 4, 52, 47, .skip⟩
example : (Lanius.Extraction.Frontend.checkLexerPrefix? lexerPrefix.body).isSome = true := by decide
-- A count taken from another value or shadowing the lexer result cannot
-- authenticate the data flow needed by the following status/copy operations.
example : (Lanius.Extraction.Frontend.checkLexerPrefix?
  (.letLocal 17 (.structure 4) (.call 52 lexerPrefix.arguments)
    (.letLocal 18 (.scalar (.signed .i32)) (.call 47 [.local 16]) .skip))).isNone = true := by decide
example : (Lanius.Extraction.Frontend.checkLexerPrefix?
  ({ lexerPrefix with countId := 17 }.body)).isNone = true := by decide
example : (Lanius.Extraction.Frontend.checkLexerPrefix?
  (.letLocal 17 (.structure 4)
    (.call 52 [.local 0, .local 1, .local 4,
      .binary .divide (.local 5) (.value (.signed .i32 2))])
    (.letLocal 18 (.scalar (.signed .i32)) (.call 47 [.local 17]) .skip))).isNone = true := by decide

open Lanius.Extraction.Frontend
private def tokenSymbols : TokenizationSymbols := ⟨52, 47, 46, 53, 4, 89⟩
private def guardedRegion := tokenGuards tokenSymbols .skip .skip .skip
-- The full matcher calls the proof-producing Core equality checker. Exercise
-- its compiled behavior as a regression test, not a native correctness axiom.
private def checkTokenizationRegression : IO Unit := do
  let wrongCount := ({ lexerPrefix with rest := ({ guardedRegion with countId := 5 }).body }).body
  let wrongCapacity := ({ lexerPrefix with rest := ({ guardedRegion with capacityId := 9 }).body }).body
  let reordered : Lanius.Core.Stmt := .sequence (.ifThenElse (capacityCondition 18 7) .skip .skip)
    (.sequence (.ifThenElse guardedRegion.statusCondition .skip .skip) guardedRegion.rest)
  let samples : List (String × Lanius.Core.Stmt × Bool) := [
      ("exact prefix", tokenizationBody tokenSymbols .skip .skip .skip, true),
      ("capacity used as count", wrongCount, false),
      ("kinds capacity", wrongCapacity, false),
      ("reordered guards", ({ lexerPrefix with rest := reordered }).body, false)]
  for (label, code, accepted) in samples do
    unless (checkTokenization? code).isSome == accepted do
      throw (IO.userError s!"tokenization source matcher disagrees: {label}")
#eval checkTokenizationRegression
-- Passing a guard may not introduce an extra side effect.
example : (checkAfterLexer?
  (.sequence (.ifThenElse guardedRegion.statusCondition .skip (.returnValue none))
    (.sequence (.ifThenElse (capacityCondition 18 7) .skip .skip) guardedRegion.rest))).isNone = true := by decide

private def capacityResult (count words : Int) : Option Bool :=
  let state := (({} : Lanius.Semantics.State).bindLocal 18 (.signed .i32 count)).bindLocal 7 (.signed .i32 words)
  match Lanius.Semantics.evalExpr 16 {} state (capacityCondition 18 7) with
  | .done (.boolean rejected) _ => some rejected
  | _ => none
example : capacityResult 0 0 = some false := by decide
example : capacityResult 0 2 = some false := by decide
example : capacityResult 1 2 = some true := by decide
example : capacityResult 1 3 = some false := by decide
example : capacityResult 1 4 = some false := by decide
example : capacityResult 1 5 = some false := by decide
example : capacityResult 2 5 = some true := by decide
example : capacityResult 2 6 = some false := by decide
example : capacityResult 715827882 2147483647 = some false := by decide
example : capacityResult 715827883 2147483647 = some true := by decide

private def kindsCapacityResult (count capacity : Int) : Option Bool :=
  let state := (({} : Lanius.Semantics.State).bindLocal 20 (.signed .i32 count)).bindLocal 9 (.signed .i32 capacity)
  match Lanius.Semantics.evalExpr 8 {} state kindsCapacityCondition with
  | .done (.boolean rejected) _ => some rejected
  | _ => none
example : kindsCapacityResult 0 0 = some false := by decide
example : kindsCapacityResult 0 1 = some false := by decide
example : kindsCapacityResult 1 0 = some true := by decide
example : kindsCapacityResult 1 1 = some false := by decide
example : kindsCapacityResult 2 1 = some true := by decide
example : kindsCapacityResult 2 2 = some false := by decide
example : kindsCapacityResult 2 3 = some false := by decide
example : kindsCapacityResult 2147483647 2147483646 = some true := by decide
example : kindsCapacityResult 2147483647 2147483647 = some false := by decide

private def checkRecognitionRegression : IO Unit := do
  let region := recognitionRegion 48 7 (.returnValue none)
  let wrap (body : Lanius.Core.Stmt) :=
    Lanius.Core.Stmt.sequence (.ifThenElse kindsCapacityCondition (.returnValue none) .skip) body
  let samples : List (String × Lanius.Core.Stmt × Bool) := [
    ("exact continuation", wrap region.body, true),
    ("raw count instead of canonical count", wrap ({ region with locals := { region.locals with count := 18 } }).body, false),
    ("copy from raw buffer", wrap ({ region with locals := { region.locals with source := 4 } }).body, false),
    ("overwrite canonical count", wrap ({ region with resultId := 20 }).body, false),
    ("scalar parse result", wrap ({ region with resultType := .scalar (.signed .i32) }).body, false),
    ("canonical capacity division", .sequence (.ifThenElse (capacityCondition 20 9) .skip .skip) region.body, false),
    ("extra statement before copying", wrap (.sequence .skip region.body), false)]
  for (label, code, accepted) in samples do
    unless (checkRecognitionStage? code).isSome == accepted do
      throw (IO.userError s!"recognition source matcher disagrees: {label}")
  let some stage := checkRecognitionStage? (wrap region.body)
    | throw (IO.userError "recognition source did not match")
  unless stage.locals.storageFailure == .returnValue none && stage.locals.rest == .returnValue none do
    throw (IO.userError "recognition matcher discarded a failure or parse continuation")
#eval checkRecognitionRegression

-- Keep the trust footprint of the reused contract visible. The generic link
-- proof is kernel-only; legacy frontend dependencies still use native_decide.
#print axioms Lanius.Semantics.Relocation.Link.evaluates
#print axioms Lanius.Extraction.RawLexer.LexInto.Caller.body_executes_at
#print axioms Lanius.Extraction.RawLexer.LexInto.Caller.callee_executes
#print axioms Lanius.Extraction.RawLexer.LexInto.Caller.call_evaluates_at
#print axioms Lanius.Extraction.RawLexer.LexInto.Linked.call_evaluates_at
#print axioms Lanius.Extraction.Frontend.lex_then_count
#print axioms Lanius.Extraction.Frontend.capacity_condition_evaluates
#print axioms Lanius.Extraction.Frontend.AfterLexer.pass
#print axioms Lanius.Extraction.Frontend.lex_to_canonical
#print axioms Lanius.Extraction.Frontend.kinds_capacity_evaluates
#print axioms Lanius.Extraction.ParserRecognize.recognize_region_at
#print axioms Lanius.Extraction.Frontend.canonical_to_recognize
#print axioms Lanius.Extraction.Frontend.lex_to_recognize
#print axioms Lanius.Separation.CellEffect.transScoped
#print axioms Lanius.Extraction.BufferCopy.copy_emitted_then_canonicalize
#print axioms Lanius.Extraction.RawLexer.LexInto.run_records_prefix
#print axioms Lanius.Extraction.RawLexer.LexInto.run_records_spare
#print axioms Lanius.Extraction.TokenScan.Semantics.framePreservingCallSoundness
#print axioms Lanius.Extraction.RawLexer.Results.Semantics.constructorFramePreservingCallSoundness
#print axioms Lanius.Extraction.RawLexer.LexInto.Calls.framePreservingCallSoundness
#print axioms Lanius.FunctionalView.StatefulFrame.term_footprint
#print axioms Lanius.FunctionalView.StatefulFrame.action_footprint
#print axioms Lanius.FunctionalView.StatefulFrame.command_footprint
#print axioms Lanius.FunctionalView.StatefulFrame.action_executes
#print axioms Lanius.FunctionalView.StatefulFrame.command_executes
#print axioms Lanius.Extraction.RawLexer.LexInto.Frame.body_executes
#print axioms Lanius.Extraction.RawLexer.LexInto.Frame.call_executes
#print axioms Lanius.Semantics.Relocation.world_owns
#print axioms Lanius.Compiler.Lexer.lexRaw_validSpans
#print axioms Lanius.Extraction.RawLexer.LexInto.Model.emittedTokens_validSpans
#print axioms Lanius.Extraction.RawLexer.LexInto.canonicalize_emitted
#print axioms Lanius.Separation.evaluatesSliceCopy
