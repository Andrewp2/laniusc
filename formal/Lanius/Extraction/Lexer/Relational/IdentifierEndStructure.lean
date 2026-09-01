import Lanius.Extraction.Lexer.Relational.Functions
import Lanius.Extraction.Lexer.Functions
import Lanius.FunctionalViewStatefulPattern
import Lanius.FunctionalViewCoreFreshSimulation

namespace Lanius.Extraction.Lexer.Relational.IdentifierEnd.Structure

open Lanius.Core
open Lanius.Compiler.Lexer.Program
open Lanius.Extraction.Lexer
open Lanius.Extraction.Lexer.Functions
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Stateful.Pattern

abbrev P (arity : Nat) := CommandPattern Core.signature actions arity
abbrev T (arity : Nat) := TermPattern Core.signature arity

private def operation (value : Operation) : Exact Operation :=
  Exact.ofDecidableEq value

private def i32 : Ty := .scalar (.signed .i32)
private def bool : Ty := .scalar .bool

private def slot {arity : Nat} (index : Fin arity) : T arity := .slot index
private def literalI32 {arity : Nat} (value : Int) : T arity :=
  .literal (Exact.signed .i32 value)

private def cursor : T 4 := slot ⟨3, by omega⟩
private def bound : T 4 := slot ⟨1, by omega⟩

private def condition (predicate : FunctionId) : T 4 :=
  .logicalAnd
    (.apply (operation (.binary .less i32 i32 bool)) [cursor, bound])
    (.apply (operation (.call predicate [i32] bool))
      [.apply (operation (.index (.slice i32) i32 i32))
        [slot ⟨0, by omega⟩, cursor]])

private def body : P 4 :=
  .sequence (.updateLocal .add ⟨3, by omega⟩ (literalI32 1)) .skip

def pattern (predicate : FunctionId) : P 3 :=
  .letValue i32
    (.apply (operation (.binary .add i32 i32 i32))
      [slot ⟨2, by omega⟩, literalI32 1])
    (.sequence (.whileLoop (condition predicate) body)
      (.sequence (.returnValue (some cursor)) .skip))

def command (predicate : FunctionId) : Lanius.FunctionalView.Stateful.Command
    Core.signature actions 3 := (pattern predicate).denote

/-- Readable proof command consumed by the generic relational scanner rule.
Its equality with each mechanically recovered command is certified below. -/
def proofCommand (predicate : FunctionId) :
    Lanius.FunctionalView.Stateful.Command Core.signature actions 3 :=
  .letValue i32
        (FunctionalView.Core.apply (.binary .add i32 i32 i32)
          [FunctionalView.Core.reference ⟨2, by omega⟩,
            FunctionalView.Core.literal (.signed .i32 1)])
        (.sequence
          (.whileLoop
            (FunctionalView.Core.logicalAnd
              (FunctionalView.Core.apply
                (.binary .less i32 i32 bool)
                [FunctionalView.Core.reference ⟨3, by omega⟩,
                  FunctionalView.Core.reference ⟨1, by omega⟩])
              (FunctionalView.Core.apply (.call predicate [i32] bool)
                [FunctionalView.Core.apply (.index (.slice i32) i32 i32)
                  [FunctionalView.Core.reference ⟨0, by omega⟩,
                    FunctionalView.Core.reference ⟨3, by omega⟩]]))
            (.sequence
              (.updateLocal .add ⟨3, by omega⟩
                (FunctionalView.Core.literal (.signed .i32 1)))
              .skip))
          (.sequence
            (.returnValue
              (some (FunctionalView.Core.reference ⟨3, by omega⟩)))
            .skip))

/-- Executable constructor recognition ties the readable loop shape to the
mechanically recovered command. -/
theorem recovered : Scanners.scanIdentifierEndView.command =
    command Lanius.Extraction.Lexer.Functions.isIdentifierContinueFunction.id := by
  exact exact_of_matches
    (pattern := pattern
      Lanius.Extraction.Lexer.Functions.isIdentifierContinueFunction.id)
    (by decide +kernel)

theorem whitespaceRecovered :
    Scanners.scanWhitespaceEndView.command =
      command Lanius.Extraction.Lexer.Functions.isWhitespaceFunction.id := by
  exact exact_of_matches
    (pattern := pattern Lanius.Extraction.Lexer.Functions.isWhitespaceFunction.id)
    (by decide +kernel)

theorem identifierProofCommand : Scanners.scanIdentifierEndView.command =
    proofCommand
      Lanius.Extraction.Lexer.Functions.isIdentifierContinueFunction.id := by
  have proofEq := exact_of_matches
    (pattern := pattern
      Lanius.Extraction.Lexer.Functions.isIdentifierContinueFunction.id)
    (candidate := proofCommand
      Lanius.Extraction.Lexer.Functions.isIdentifierContinueFunction.id)
    (by decide +kernel)
  exact recovered.trans proofEq.symm

theorem whitespaceProofCommand : Scanners.scanWhitespaceEndView.command =
    proofCommand Lanius.Extraction.Lexer.Functions.isWhitespaceFunction.id := by
  have proofEq := exact_of_matches
    (pattern := pattern Lanius.Extraction.Lexer.Functions.isWhitespaceFunction.id)
    (candidate := proofCommand
      Lanius.Extraction.Lexer.Functions.isWhitespaceFunction.id)
    (by decide +kernel)
  exact whitespaceRecovered.trans proofEq.symm

theorem identifierActionFree :
    Lanius.FunctionalView.FreshSimulation.actionFree
      Scanners.scanIdentifierEndView.command = true := by
  decide +kernel

theorem whitespaceActionFree :
    Lanius.FunctionalView.FreshSimulation.actionFree
      Scanners.scanWhitespaceEndView.command = true := by
  decide +kernel

end Lanius.Extraction.Lexer.Relational.IdentifierEnd.Structure
