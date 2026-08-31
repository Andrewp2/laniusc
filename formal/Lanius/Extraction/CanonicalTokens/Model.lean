import Lanius.Compiler.LexerCanonical
import Lanius.Extraction.CanonicalTokens.KeywordCommand
import Lanius.FunctionalViewStatefulAcyclic
import Lanius.FunctionalViewCoreEffectfulStateful

namespace Lanius.Extraction.CanonicalTokens.Model

set_option maxRecDepth 100000

open Lanius
open Lanius.Core
open Lanius.Compiler
open Lanius.Compiler.Lexer
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly
open Lanius.FunctionalView.Core.Effectful
open Lanius.FunctionalView.Core.Stateful
open Lanius.Extraction.CanonicalTokens.Functions

/-! # Concrete models for the canonical-token queries

The executable side of each theorem runs the mechanically recovered
FunctionalView of the checked source function.  The result side is stated in
the compiler's independent lexer vocabulary, so these are behavioral
contracts rather than restatements of `Command.Evaluates`.
-/

def noCalls : Lanius.FunctionalView.Core.Effectful.CallModel where
  evaluate := fun _ _ _ => .error .invalidPointer

def emptyWorld : World := { i32Slice? := fun _ => none }

def isTrivia (kind : TokenKind) : Bool := isTriviaKind kind

def isTriviaEnvironment (kind : Int) : Env 1
  | _ => .signed .i32 kind

private def isTriviaRun (kind : Int) :=
  Lanius.FunctionalView.Stateful.Acyclic.run?
    (termMachine (evaluateOperation verifiedFrontendCore noCalls))
    (machineWith verifiedFrontendCore
      (evaluateOperation verifiedFrontendCore noCalls))
    emptyWorld (isTriviaEnvironment kind) isTriviaView.command

def returnedBool? : Option
    (Lanius.FunctionalView.Stateful.Completion × World × Env arity) →
    Option Bool
  | some (.returned (some (.boolean result)), _, _) => some result
  | _ => none

/-- The exact checked `is_trivia` view computes the logical trivia
classifier for every encoded token kind. -/
theorem isTriviaView_result : ∀ kind : TokenKind,
    returnedBool? (isTriviaRun (Int.ofNat kind.gpuCode)) =
      some (isTrivia kind) := by
  intro kind
  cases kind <;> native_decide

def keywordSpan (source : List Int) (start finish : Nat) : List Int :=
  (source.drop start).take (finish - start)

def keywordKind (source : List Int) (start finish : Nat) : Int :=
  Int.ofNat <| match exactKeywordKind
      ((keywordSpan source start finish).map Int.toNat) keywordRules with
    | some kind => kind.gpuCode
    | none => TokenKind.identifier.gpuCode

def keywordWorld (source : List Int) : World := World.singleton 0 source

def keywordSource (source : List Int) : Value :=
  .slice (.scalar (.signed .i32)) 0 [] 0 source.length

def keywordEnvironment (source : List Int) (start finish : Nat) : Env 3
  | ⟨0, _⟩ => keywordSource source
  | ⟨1, _⟩ => .signed .i32 start
  | ⟨2, _⟩ => .signed .i32 finish

private def keywordCommand := KeywordCommand.command

theorem keywordKindView_command : keywordKindView.command = keywordCommand := by
  exact KeywordCommand.recovered

private def keywordRun (source : List Int) (start finish : Nat) :=
  Lanius.FunctionalView.Stateful.Acyclic.run?
    (termMachine (evaluateOperation verifiedFrontendCore noCalls))
    (machineWith verifiedFrontendCore
      (evaluateOperation verifiedFrontendCore noCalls))
    (keywordWorld source) (keywordEnvironment source start finish)
    keywordCommand

def returnedI32? : Option
    (Lanius.FunctionalView.Stateful.Completion × World × Env arity) →
    Option Int
  | some (.returned (some (.signed .i32 result)), _, _) => some result
  | _ => none

def keywordViewResult? (source : List Int) (start finish : Nat) : Option Int :=
  returnedI32? (keywordRun source start finish)

/-- Executable source-derived certificate for every spelling in the logical
keyword table.  This checks the actual recovered `keyword_kind` view, rather
than a second handwritten decision tree. -/
theorem keywordRulesView_result :
    keywordRules.all (fun rule =>
      keywordViewResult? (rule.spelling.map Int.ofNat) 0
          rule.spelling.length ==
        some (Int.ofNat rule.kind.gpuCode)) = true := by
  native_decide

theorem keywordRuleView_result (rule : KeywordRule)
    (member : rule ∈ keywordRules) :
    keywordViewResult? (rule.spelling.map Int.ofNat) 0
        rule.spelling.length = some (Int.ofNat rule.kind.gpuCode) := by
  have checked := List.all_eq_true.mp keywordRulesView_result rule member
  exact beq_iff_eq.mp checked

/-- Logical call model over an arbitrary valid `[start, finish)` span of a
larger source slice.  Successful evaluation preserves the read-only world. -/
def callModel : CallModel where
  evaluate := fun world function arguments =>
    if function = isTriviaFunction.id then
      match arguments with
      | [.signed .i32 kind] =>
          .ok (.boolean (kind = 3 || kind = 10 || kind = 11), world)
      | _ => .error .typeMismatch
    else if function = keywordKindFunction.id then
      match arguments with
      | [.slice (.scalar (.signed .i32)) cell [] 0 length,
          .signed .i32 start, .signed .i32 finish] =>
          if 0 ≤ start ∧ start ≤ finish then
            match world.i32Slice? cell with
            | some source =>
                if length = source.length ∧ source.length ≤ 2147483647 ∧
                    finish.toNat ≤ source.length then
                  .ok (.signed .i32
                    (keywordKind source start.toNat finish.toNat), world)
                else .error .arrayBounds
            | none => .error .invalidPointer
          else .error .arrayBounds
      | _ => .error .typeMismatch
    else .error .invalidPointer

theorem callModel_keywordKind (source : List Int) (start finish : Nat)
    (ordered : start ≤ finish) (inBounds : finish ≤ source.length)
    (sourceFitsI32 : source.length ≤ 2147483647) :
    callModel.evaluate (keywordWorld source) keywordKindFunction.id
        [keywordSource source, .signed .i32 start, .signed .i32 finish] =
      .ok (.signed .i32 (keywordKind source start finish),
        keywordWorld source) := by
  have distinct : keywordKindFunction.id ≠ isTriviaFunction.id := by
    native_decide
  simp [callModel, keywordWorld, keywordSource, distinct, ordered, inBounds,
    sourceFitsI32]

end Lanius.Extraction.CanonicalTokens.Model
