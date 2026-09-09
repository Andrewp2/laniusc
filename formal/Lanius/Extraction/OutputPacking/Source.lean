import Lanius.Extraction.Source.Statement

namespace Lanius.Extraction.OutputPacking

open Lanius.Core Lanius.Extraction.Source

/-- Bound local identities recovered from the checked source, not hard-coded
identities from an older generated embedding. -/
structure LoopLocals where
  workspace : VarId
  input : VarId
  cursor : VarId
  length : VarId

def LoopLocals.assignment (locals : LoopLocals) : Expr :=
  let index := Expr.binary .divide (.local locals.cursor) (.value (.signed .i32 4))
  .assign .set (.index (.local locals.workspace) index)
    (.binary .bitOr (.index (.local locals.workspace) index)
      (.binary .shiftLeft (.index (.local locals.input) (.local locals.cursor))
        (.binary .multiply
          (.binary .remainder (.local locals.cursor) (.value (.signed .i32 4)))
          (.value (.signed .i32 8)))))

def LoopLocals.body (locals : LoopLocals) : Stmt :=
  .sequence (.expression locals.assignment)
      (.sequence (.expression (.assign .add (.local locals.cursor)
        (.value (.signed .i32 1)))) .skip)

def LoopLocals.loop (locals : LoopLocals) : Stmt :=
  .whileLoop (.binary .notEqual (.local locals.cursor) (.local locals.length)) locals.body

def LoopLocals.clearBody (locals : LoopLocals) : Stmt :=
  .sequence (.expression (.assign .set
    (.index (.local locals.workspace) (.local locals.cursor)) (.value (.signed .i32 0))))
    (.sequence (.expression (.assign .add (.local locals.cursor)
      (.value (.signed .i32 1)))) .skip)

def LoopLocals.clearLoop (locals : LoopLocals) : Stmt :=
  .whileLoop (.binary .notEqual (.local locals.cursor) (.local locals.length)) locals.clearBody

/-- Recognize the full loop, including the cursor update and absence of extra
effects. Acceptance carries propositional equality, not a Boolean comparison
or an assumption about what the extractor ought to have emitted. -/
def checkPackingLoop? : (statement : Stmt) → Option (CheckedStatement LoopLocals.loop statement)
  | .whileLoop (.binary .notEqual (.local cursor) (.local length))
      (.sequence (.expression
        (.assign .set (.index (.local workspace)
          (.binary .divide (.local writeCursor) (.value (.signed .i32 4))))
          (.binary .bitOr
            (.index (.local readWorkspace)
              (.binary .divide (.local readCursor) (.value (.signed .i32 4))))
            (.binary .shiftLeft (.index (.local input) (.local inputCursor))
              (.binary .multiply
                (.binary .remainder (.local laneCursor) (.value (.signed .i32 4)))
                (.value (.signed .i32 8)))))))
        (.sequence (.expression (.assign .add (.local incrementCursor)
          (.value (.signed .i32 1)))) .skip)) =>
      if same : writeCursor = cursor ∧ readWorkspace = workspace ∧
          readCursor = cursor ∧ inputCursor = cursor ∧ laneCursor = cursor ∧
          incrementCursor = cursor then
        some ⟨⟨workspace, input, cursor, length⟩, by
          rcases same with ⟨rfl, rfl, rfl, rfl, rfl, rfl⟩
          rfl⟩
      else none
  | _ => none

def checkClearLoop? : (statement : Stmt) → Option (CheckedStatement LoopLocals.clearLoop statement)
  | .whileLoop (.binary .notEqual (.local cursor) (.local length))
      (.sequence (.expression (.assign .set
        (.index (.local workspace) (.local writeCursor)) (.value (.signed .i32 0))))
        (.sequence (.expression (.assign .add (.local incrementCursor)
          (.value (.signed .i32 1)))) .skip)) =>
      if same : writeCursor = cursor ∧ incrementCursor = cursor then
        some ⟨⟨workspace, 0, cursor, length⟩, by
          rcases same with ⟨rfl, rfl⟩
          rfl⟩
      else none
  | _ => none

def findPackingLoop? := findStatement? LoopLocals.loop checkPackingLoop?
def findClearLoop? := findStatement? LoopLocals.clearLoop checkClearLoop?

/-- The source sequence establishes the word count, clears that many words,
then starts packing at byte zero before entering its continuation. -/
structure Preparation where
  packing : LoopLocals
  wordCount : VarId
  clearCursor : VarId
  continuation : Stmt

def Preparation.statement (preparation : Preparation) : Stmt :=
  .letLocal preparation.wordCount (.scalar (.signed .i32))
    (.binary .divide (.binary .add (.local preparation.packing.length)
      (.value (.signed .i32 3))) (.value (.signed .i32 4)))
    (.letLocal preparation.clearCursor (.scalar (.signed .i32)) (.value (.signed .i32 0))
      (.sequence
        (LoopLocals.clearLoop ⟨preparation.packing.workspace, 0,
          preparation.clearCursor, preparation.wordCount⟩)
        (.letLocal preparation.packing.cursor (.scalar (.signed .i32)) (.value (.signed .i32 0))
          (.sequence preparation.packing.loop preparation.continuation))))

def checkPreparation? : (statement : Stmt) → Option (CheckedStatement Preparation.statement statement)
  | .letLocal wordCount (.scalar (.signed .i32))
      (.binary .divide (.binary .add (.local byteLength) (.value (.signed .i32 3)))
        (.value (.signed .i32 4)))
      (.letLocal clearCursor (.scalar (.signed .i32)) (.value (.signed .i32 0))
        (.sequence clearLoop
          (.letLocal packCursor (.scalar (.signed .i32)) (.value (.signed .i32 0))
            (.sequence packLoop continuation)))) => do
      let cleared ← checkClearLoop? clearLoop
      let packed ← checkPackingLoop? packLoop
      if same : cleared.locals.workspace = packed.locals.workspace ∧
          cleared.locals.length = wordCount ∧ cleared.locals.cursor = clearCursor ∧
          packed.locals.cursor = packCursor ∧ packed.locals.length = byteLength then
        pure ⟨⟨packed.locals, wordCount, clearCursor, continuation⟩, by
          rcases cleared with ⟨clearLocals, clearShape⟩
          rcases packed with ⟨packLocals, packShape⟩
          dsimp at same ⊢
          rcases same with ⟨sameWorkspace, sameWords, sameClearCursor, samePackCursor, sameLength⟩
          rw [clearShape, packShape]
          cases clearLocals
          cases packLocals
          dsimp at sameWorkspace sameWords sameClearCursor samePackCursor sameLength ⊢
          subst_vars
          rfl⟩
      else none
  | _ => none

def findPreparation? := findStatement? Preparation.statement checkPreparation?

structure StdoutTail where
  size : VarId
  length : VarId
  pointer : VarId
  function : FunctionId

def StdoutTail.statement (tail : StdoutTail) : Stmt :=
  .letLocal tail.size (.scalar (.unsigned .usize)) (.cast (.unsigned .usize) (.local tail.length))
    (.sequence (.ifThenElse
      (.binary .notEqual (.call tail.function [.local tail.pointer, .local tail.size]) (.local tail.length))
      (.sequence (.returnValue (some (.value (.signed .i32 22)))) .skip) .skip)
      (.sequence (.returnValue (some (.value (.signed .i32 0)))) .skip))

def checkStdoutTail? : (statement : Stmt) → Option (CheckedStatement StdoutTail.statement statement)
  | .letLocal size (.scalar (.unsigned .usize)) (.cast (.unsigned .usize) (.local length))
      (.sequence (.ifThenElse
        (.binary .notEqual (.call function [.local pointer, .local sizeRead]) (.local lengthRead))
        (.sequence (.returnValue (some (.value (.signed .i32 22)))) .skip) .skip)
        (.sequence (.returnValue (some (.value (.signed .i32 0)))) .skip)) =>
      if same : sizeRead = size ∧ lengthRead = length then
        some ⟨⟨size, length, pointer, function⟩, by rcases same with ⟨rfl, rfl⟩; rfl⟩
      else none
  | _ => none

theorem Preparation.checked_stdout_statement (preparation : Preparation)
    (checked : CheckedStatement StdoutTail.statement preparation.continuation) :
    preparation.statement =
      (Preparation.statement ⟨preparation.packing, preparation.wordCount,
        preparation.clearCursor, checked.locals.statement⟩) := by
  exact congrArg (fun continuation =>
    (Preparation.statement ⟨preparation.packing, preparation.wordCount,
      preparation.clearCursor, continuation⟩)) checked.exactSource

end Lanius.Extraction.OutputPacking
