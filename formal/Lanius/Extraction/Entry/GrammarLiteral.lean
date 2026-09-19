import Lanius.Extraction.Entry.GrammarIdentity
import Lanius.Extraction.Entry.GrammarSetup
import Lanius.Extraction.CompactDecode.Reader
import Lanius.Extraction.Entry.Grammar.Indexed

namespace Lanius.Extraction.Entry.Grammar

open Lanius.Core Lanius.Semantics Lanius.Compiler.Parser

structure LiteralEvidence (grammar : IndexedGrammar) (text : String) where
  values : List Nat
  layout : PackedGrammarLayout
  bounded : ∀ value ∈ values, value < 65536
  size : (Lanius.World.utf8Bytes text).length = values.length * 4
  decoded : decodeI32Array values.length (Lanius.World.utf8Bytes text) =
    .ok (signedI32Values (values.map (fun value => (Hex.packedWord value : Int))))
  encoding : EncodesGrammar layout grammar (values.map Int.ofNat)

/-- Parse candidates using the existing hex reader, then retain independent
proofs of the raw-word identity and the complete packed grammar contract. -/
def checkLiteralData? (grammar : IndexedGrammar) (text : String) : Option (LiteralEvidence grammar text) := do
  let bytes := text.toUTF8
  let values ← (List.range (bytes.size / 4)).mapM fun index => do
    let (value, _) ← (CompactDecode.readHexNat 4 0).run ⟨bytes, index * 4⟩
    pure value
  if bounds : ∀ value ∈ values, value < 65536 then
    if size : (Lanius.World.utf8Bytes text).length = values.length * 4 then
      let layout : PackedGrammarLayout := {
        wordLength := values.length, canonicalKindsOffset := values[7]?.getD 0,
        productionLhsOffset := values[8]?.getD 0, rhsOffsetsOffset := values[9]?.getD 0,
        rhsLengthsOffset := values[10]?.getD 0, rhsSymbolsOffset := values[11]?.getD 0,
        lhsOffsetsOffset := values[13]?.getD 0, lhsCountsOffset := values[14]?.getD 0,
        lhsProductionsOffset := values[15]?.getD 0 }
      let encoding ← checkEncoding? layout grammar (values.map Int.ofNat)
      match decoded : decodeI32Array values.length (Lanius.World.utf8Bytes text) with
      | .error _ => none
      | .ok words => do
          let equality ← Lanius.Core.Equality.values? words
            (signedI32Values (values.map (fun value => (Hex.packedWord value : Int))))
          pure ⟨values, layout, bounds, size,
            decoded.trans (congrArg Except.ok equality.equal), encoding.proof⟩
    else none
  else none

structure LiteralStage where
  text : String
  setup : SetupStage

def LiteralStage.statement (stage : LiteralStage) (function : Lanius.FunctionId) : Stmt :=
  .letLocal stage.setup.text (.scalar .string) (.value (.string stage.text)) (stage.setup.statement function)

def checkLiteral? (function : Lanius.FunctionId) (statement : Stmt) :
    Option (Source.CheckedStatement (fun stage : LiteralStage => stage.statement function) statement) :=
  match shape : statement with
  | .letLocal _ _ (.value (.string text)) rest => do
      let setup ← checkSetup? function rest
      let stage : LiteralStage := ⟨text, setup.locals⟩
      let equality ← Lanius.Core.Equality.statement? statement (stage.statement function)
      pure ⟨stage, shape.symm.trans equality.equal⟩
  | _ => none

open Lanius.Properties Lanius.Separation Lanius.Extraction.CompactOutput

structure LiteralStage.Supported (stage : LiteralStage) (count : Nat) : Type where
  count : stage.setup.cursor.locals.count = count
  textDestination : stage.setup.text ≠ stage.setup.cursor.locals.destination
  sourceDestination : stage.setup.cursor.locals.source ≠ stage.setup.cursor.locals.destination
  cursorSource : stage.setup.cursor.locals.cursor ≠ stage.setup.cursor.locals.source
  cursorDestination : stage.setup.cursor.locals.cursor ≠ stage.setup.cursor.locals.destination
  wordDestination : stage.setup.cursor.locals.word ≠ stage.setup.cursor.locals.destination
  wordCursor : stage.setup.cursor.locals.word ≠ stage.setup.cursor.locals.cursor

def LiteralStage.checkSupported? (stage : LiteralStage) (count : Nat) : Option (stage.Supported count) :=
  if evidence : stage.setup.cursor.locals.count = count ∧
      stage.setup.text ≠ stage.setup.cursor.locals.destination ∧
      stage.setup.cursor.locals.source ≠ stage.setup.cursor.locals.destination ∧
      stage.setup.cursor.locals.cursor ≠ stage.setup.cursor.locals.source ∧
      stage.setup.cursor.locals.cursor ≠ stage.setup.cursor.locals.destination ∧
      stage.setup.cursor.locals.word ≠ stage.setup.cursor.locals.destination ∧
      stage.setup.cursor.locals.word ≠ stage.setup.cursor.locals.cursor then
    some ⟨evidence.1, evidence.2.1, evidence.2.2.1, evidence.2.2.2.1,
      evidence.2.2.2.2.1, evidence.2.2.2.2.2.1, evidence.2.2.2.2.2.2⟩
  else none

theorem LiteralStage.executes (stage : LiteralStage) (checked : Hex.Checked program)
    (data : LiteralEvidence grammar stage.text) (before : State)
    (untouched : List Int) (destinationCell : Lanius.CellId)
    (completion : Completion) (post : Lanius.World.State → Prop)
    (wellFormed : StateWellFormed before)
    (destinationLocal : before.local? stage.setup.cursor.locals.destination =
      some (.slice i32 destinationCell [] 0 untouched.length))
    (destinationContents : before.cellEntry? destinationCell = some {
      id := destinationCell, value := some (.array (signedI32Values untouched)) })
    (capacity : data.values.length ≤ untouched.length) (fits : untouched.length ≤ 2147483647)
    (supported : stage.Supported data.values.length)
    (continuationRun : ∀ memory : Memory stage.setup.cursor.locals,
      memory.values = data.values → memory.untouched = untouched → memory.destinationCell = destinationCell →
      ∀ middle, Invariant memory memory.values middle → middle.world = before.world →
      CellEffect (CellSet.singleton destinationCell) before (restoreLocals before middle) →
      (∀ id, id ≠ stage.setup.text → id ≠ stage.setup.cursor.locals.source →
        id ≠ stage.setup.cursor.locals.cursor → middle.cellId? id = before.cellId? id) →
      (Allocation.Registry before → Allocation.Registry middle) →
      (∃ fresh, middle.i32ArrayViews = before.i32ArrayViews ++ fresh) →
      Prefix.Reaches program.core before (stage.statement checked.source.function.id)
        middle stage.setup.cursor.continuation →
      ∃ after, Executes program.core middle stage.setup.cursor.continuation completion after ∧ post after.world) :
    ∃ after, Executes program.core before (stage.statement checked.source.function.id) completion after ∧ post after.world := by
  let scope := before.bindLocal stage.setup.text (.string stage.text)
  have scopeWF : StateWellFormed scope := bindLocal_preserves_well_formed before _ _ wellFormed
  have textRead : scope.local? stage.setup.text = some (.string stage.text) :=
    bindLocal_finds_local before _ _ wellFormed
  have destinationRead : scope.local? stage.setup.cursor.locals.destination =
      some (.slice i32 destinationCell [] 0 untouched.length) :=
    (bindLocal_preserves_other_local wellFormed supported.textDestination).trans destinationLocal
  have contents := ((bindLocal_effect before stage.setup.text (.string stage.text)).oldCells destinationCell
    (StateWellFormed.cell_lt_next_of_entry wellFormed destinationContents) (by simp [CellSet.empty])).trans destinationContents
  obtain ⟨after, ran, satisfied⟩ := setupAndLoop checked stage.setup.cursor.locals scope stage.text
    stage.setup.text data.values untouched destinationCell stage.setup.cursor.continuation completion post scopeWF
    textRead destinationRead contents data.bounded capacity fits supported.count data.size data.decoded
    supported.sourceDestination supported.cursorSource supported.cursorDestination
    supported.wordDestination supported.wordCursor
    (fun memory selected untouched target middle invariant world effect bindings registered views reached => by
      have closed := CellEffect.closeLocal before stage.setup.text (.string stage.text) wellFormed effect
      apply continuationRun memory selected untouched target middle invariant world
      · simpa only [restoreLocals] using closed
      · intro id notText notSource notCursor
        rw [bindings id notSource notCursor]
        simp [scope, State.cellId?, State.bindLocal, State.bindCell, Ne.symm notText]
      · intro initial
        exact registered (initial.bindLocal stage.setup.text (.string stage.text))
      · exact views
      · simpa only [LiteralStage.statement, SetupStage.statement, CursorStage.statement, supported.count] using
          (Prefix.Reaches.letLocal (type := .scalar .string)
            (show Evaluates program.core before (.value (.string stage.text)) (.string stage.text) before from evaluatesValue)
            reached))
  refine ⟨restoreLocals before after, ?_, satisfied⟩
  apply executesLetLocal (show Evaluates program.core before (.value (.string stage.text))
    (.string stage.text) before from evaluatesValue)
  simpa only [LiteralStage.statement, SetupStage.statement, CursorStage.statement, supported.count] using ran

end Lanius.Extraction.Entry.Grammar
