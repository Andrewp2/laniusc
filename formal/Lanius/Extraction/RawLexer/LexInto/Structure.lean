import Lanius.Extraction.RawLexer.LexInto.Functions

namespace Lanius.Extraction.RawLexer.LexInto.Structure

open Lanius
open Lanius.Core
open Lanius.Typing
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Stateful
open Lanius.Extraction.RawLexer.LexInto.Functions

private abbrev T (arity : Nat) := Term signature arity
private abbrev C (arity : Nat) := Command signature actions arity

def i32Type : Ty := .scalar (.signed .i32)
def tokenScanType : Ty := .structure 1
def lexResultType : Ty := .structure 4

def slot (index : Fin arity) : T arity := .reference (.slot index)
def i32 (value : Int) : T arity := .reference (.literal (.signed .i32 value))

def binary (operation : BinaryOp) (output : Ty)
    (left right : T arity) : T arity :=
  .apply (.binary operation i32Type i32Type output) [left, right]

def call (function : FunctionId) (parameterTypes : List Ty)
    (returnType : Ty) (arguments : List (T arity)) : T arity :=
  .apply (.call function parameterTypes returnType) arguments

def source (arity : Nat) (bound : 0 < arity := by omega) : T arity :=
  slot ⟨0, bound⟩

def sourceLength (arity : Nat) (bound : 1 < arity := by omega) : T arity :=
  slot ⟨1, bound⟩

def output (arity : Nat) (bound : 2 < arity := by omega) : Fin arity :=
  ⟨2, bound⟩

def outputCapacity (arity : Nat) (bound : 3 < arity := by omega) : T arity :=
  slot ⟨3, bound⟩

def offset (arity : Nat) (bound : 4 < arity := by omega) : Fin arity :=
  ⟨4, bound⟩

def tokenCount (arity : Nat) (bound : 5 < arity := by omega) : Fin arity :=
  ⟨5, bound⟩

def scanned : Fin 7 := ⟨6, by omega⟩
def row : Fin 8 := ⟨7, by omega⟩

def scanOneTerm : T 6 :=
  call 52 [(.slice i32Type), i32Type, i32Type] tokenScanType
    [source 6, sourceLength 6, slot (offset 6)]

def scanSucceededTerm : T 7 :=
  call 18 [tokenScanType] (.scalar .bool) [slot scanned]

def scanKindTerm (arity : Nat) (bound : 6 < arity := by omega) : T arity :=
  call 19 [tokenScanType] i32Type [slot ⟨6, bound⟩]

def scanEndTerm (arity : Nat) (bound : 6 < arity := by omega) : T arity :=
  call 20 [tokenScanType] i32Type [slot ⟨6, bound⟩]

def scanErrorTerm : T 7 :=
  call 21 [tokenScanType] i32Type [slot scanned]

def lexicalFailureTerm : T 7 :=
  call 50 [i32Type, i32Type] lexResultType
    [slot (tokenCount 7), scanErrorTerm]

def outputFullTerm : T 7 :=
  call 51 [i32Type, i32Type] lexResultType
    [slot (tokenCount 7), slot (offset 7)]

def completedTerm : T 6 :=
  call 49 [i32Type] lexResultType [slot (tokenCount 6)]

def rowTerm : T 7 :=
  binary .multiply i32Type (slot (tokenCount 7)) (i32 3)

def rowPlus (amount : Int) : T 8 :=
  binary .add i32Type (slot row) (i32 amount)

def write (index replacement : T 8) : C 8 :=
  .action (.setI32Index (output 8) index replacement)

def scanFailedCondition : T 7 :=
  .apply (.unary .logicalNot (.scalar .bool) (.scalar .bool))
    [scanSucceededTerm]

def outputFullCondition : T 7 :=
  binary .greaterEqual (.scalar .bool)
    (slot (tokenCount 7)) (outputCapacity 7)

def loopCondition : T 6 :=
  binary .less (.scalar .bool) (slot (offset 6)) (sourceLength 6)

def loopBodyAfterRow : C 8 :=
  .sequence (write (slot row) (scanKindTerm 8))
    (.sequence (write (rowPlus 1) (slot (offset 8)))
      (.sequence (write (rowPlus 2) (scanEndTerm 8))
        (.sequence (.setLocal (offset 8) (scanEndTerm 8))
          (.sequence (.updateLocal .add (tokenCount 8) (i32 1))
            .skip))))

def loopBodyAfterScan : C 7 :=
  .sequence
    (.ifThenElse scanFailedCondition
      (.sequence (.returnValue (some lexicalFailureTerm)) .skip)
      .skip)
    (.sequence
      (.ifThenElse outputFullCondition
        (.sequence (.returnValue (some outputFullTerm)) .skip)
        .skip)
      (.letValue i32Type rowTerm loopBodyAfterRow))

def loopBody : C 6 :=
  .letValue tokenScanType scanOneTerm loopBodyAfterScan

def loop : C 6 :=
  .whileLoop loopCondition loopBody

def command : C 4 :=
  .letValue i32Type (i32 0)
    (.letValue i32Type (i32 0)
      (.sequence loop
        (.sequence (.returnValue (some completedTerm)) .skip)))

/-- The readable loop structure lowers to the exact checked source body.  This
is the proof boundary used below; a handwritten lookalike cannot satisfy it if
the extracted body differs. -/
theorem command_toCore_exactly :
    toCoreStmt actionAdapter identityLayout 4 command = lexIntoBody := by
  rfl

end Lanius.Extraction.RawLexer.LexInto.Structure
