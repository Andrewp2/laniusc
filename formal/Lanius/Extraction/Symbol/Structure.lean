import Lanius.Extraction.Symbol.Functions
import Lanius.FunctionalViewStatefulPattern

namespace Lanius.Extraction.Symbol.Structure

open Lanius
open Lanius.Core
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Stateful
open Lanius.FunctionalView.Stateful.Pattern
open Lanius.Extraction.Symbol.Functions

/-! A readable, mechanically checked presentation of `match_symbol_head`.

The definition below is not an alternate implementation accepted on trust:
`matchSymbolHead_command_exact` proves that its denotation is literally the
FunctionalView command recovered from the checked source artifact.
-/

abbrev PTerm (arity : Nat) := TermPattern Core.signature arity
abbrev PCommand (arity : Nat) := CommandPattern Core.signature actions arity

def operation (value : Operation) : Exact Operation :=
  Exact.ofDecidableEq value

def i32 : Ty := .scalar (.signed .i32)
def bool : Ty := .scalar .bool

def slot (index : Fin arity) : PTerm arity := .slot index

def integer (value : Int) : PTerm arity :=
  .literal (.signed .i32 value)

def unary (op : UnaryOp) (operand : PTerm arity) : PTerm arity :=
  .apply (operation (.unary op i32 i32)) [operand]

def binary (op : BinaryOp) (result : Ty)
    (left right : PTerm arity) : PTerm arity :=
  .apply (operation (.binary op i32 i32 result)) [left, right]

def add (left right : PTerm arity) : PTerm arity :=
  binary .add i32 left right

def less (left right : PTerm arity) : PTerm arity :=
  binary .less bool left right

def equal (left right : PTerm arity) : PTerm arity :=
  binary .equal bool left right

def index (base position : PTerm arity) : PTerm arity :=
  .apply (operation (.index (.slice i32) i32 i32)) [base, position]

def tokenKindConstantId (kind : Int) : ConstantId :=
  ((verifiedFrontendCore.constants.find?
    (fun declaration => 7 <= declaration.id && declaration.id <= 88 &&
      declaration.value == .signed .i32 kind)).map
      (fun declaration => declaration.id)).getD 0

def tokenKind (kind : Int) : PTerm arity :=
  .apply (operation (.constant (tokenKindConstantId kind) i32)) []

def tokenMatch (kind length : Int) : PTerm arity :=
  .apply (operation (.call tokenMatchFunction.id [i32, i32] tokenMatchType))
    [tokenKind kind, integer length]

def returnMatch (kind length : Int) : PCommand arity :=
  .sequence (.returnValue (some (tokenMatch kind length))) .skip

def orderedCases (cases : List (PTerm arity × PCommand arity))
    (fallback : PCommand arity) : PCommand arity :=
  cases.foldr
    (fun entry rest =>
      .sequence (.ifThenElse entry.1 entry.2 .skip) rest)
    fallback

def first60 : PCommand 6 :=
  orderedCases [
    (equal (slot 4) (integer 60),
      orderedCases [(equal (slot 5) (integer 61), returnMatch 52 3)]
        (returnMatch 43 2)),
    (equal (slot 4) (integer 61), returnMatch 14 2),
    (equal (slot 4) (integer 62), returnMatch 24 2)]
    (returnMatch 12 1)

def first62 : PCommand 6 :=
  orderedCases [
    (equal (slot 4) (integer 62),
      orderedCases [(equal (slot 5) (integer 61), returnMatch 53 3)]
        (returnMatch 44 2)),
    (equal (slot 4) (integer 61), returnMatch 15 2)]
    (returnMatch 13 1)

def first43 : PCommand 6 :=
  orderedCases [
    (equal (slot 4) (integer 61), returnMatch 46 2),
    (equal (slot 4) (integer 43), returnMatch 56 2)]
    (returnMatch 6 1)

def first45 : PCommand 6 :=
  orderedCases [
    (equal (slot 4) (integer 61), returnMatch 47 2),
    (equal (slot 4) (integer 45), returnMatch 57 2),
    (equal (slot 4) (integer 62), returnMatch 75 2)]
    (returnMatch 27 1)

def first61 : PCommand 6 :=
  orderedCases [
    (equal (slot 4) (integer 61), returnMatch 16 2),
    (equal (slot 4) (integer 62), returnMatch 113 2)]
    (returnMatch 8 1)

def first47 : PCommand 6 :=
  orderedCases [
    (equal (slot 4) (integer 47), returnMatch 10 2),
    (equal (slot 4) (integer 42), returnMatch 11 2),
    (equal (slot 4) (integer 61), returnMatch 49 2)]
    (returnMatch 9 1)

def first38 : PCommand 6 :=
  orderedCases [
    (equal (slot 4) (integer 38), returnMatch 17 2),
    (equal (slot 4) (integer 61), returnMatch 54 2)]
    (returnMatch 25 1)

def first124 : PCommand 6 :=
  orderedCases [
    (equal (slot 4) (integer 124), returnMatch 18 2),
    (equal (slot 4) (integer 61), returnMatch 55 2)]
    (returnMatch 26 1)

def first33 : PCommand 6 :=
  orderedCases [(equal (slot 4) (integer 61), returnMatch 40 2)]
    (returnMatch 19 1)

def first42 : PCommand 6 :=
  orderedCases [(equal (slot 4) (integer 61), returnMatch 48 2)]
    (returnMatch 7 1)

def first37 : PCommand 6 :=
  orderedCases [(equal (slot 4) (integer 61), returnMatch 50 2)]
    (returnMatch 41 1)

def first94 : PCommand 6 :=
  orderedCases [(equal (slot 4) (integer 61), returnMatch 51 2)]
    (returnMatch 42 1)

def first46 : PCommand 6 :=
  orderedCases [(equal (slot 4) (integer 46), returnMatch 182 2)]
    (returnMatch 35 1)

def symbolCases : PCommand 6 :=
  orderedCases [
    (equal (slot 3) (integer 60), first60),
    (equal (slot 3) (integer 62), first62),
    (equal (slot 3) (integer 43), first43),
    (equal (slot 3) (integer 45), first45),
    (equal (slot 3) (integer 61), first61),
    (equal (slot 3) (integer 47), first47),
    (equal (slot 3) (integer 38), first38),
    (equal (slot 3) (integer 124), first124),
    (equal (slot 3) (integer 33), first33),
    (equal (slot 3) (integer 42), first42),
    (equal (slot 3) (integer 37), first37),
    (equal (slot 3) (integer 94), first94),
    (equal (slot 3) (integer 46), first46),
    (equal (slot 3) (integer 40), returnMatch 4 1),
    (equal (slot 3) (integer 41), returnMatch 5 1),
    (equal (slot 3) (integer 91), returnMatch 20 1),
    (equal (slot 3) (integer 93), returnMatch 21 1),
    (equal (slot 3) (integer 123), returnMatch 22 1),
    (equal (slot 3) (integer 125), returnMatch 23 1),
    (equal (slot 3) (integer 126), returnMatch 45 1),
    (equal (slot 3) (integer 44), returnMatch 36 1),
    (equal (slot 3) (integer 59), returnMatch 37 1),
    (equal (slot 3) (integer 58), returnMatch 38 1)]
    (returnMatch 39 1)

def readSecond : PCommand 6 :=
  .ifThenElse (less (add (slot 2) (integer 1)) (slot 1))
    (.sequence
      (.setLocal 4 (index (slot 0) (add (slot 2) (integer 1))))
      .skip)
    .skip

def readThird : PCommand 6 :=
  .ifThenElse (less (add (slot 2) (integer 2)) (slot 1))
    (.sequence
      (.setLocal 5 (index (slot 0) (add (slot 2) (integer 2))))
      .skip)
    .skip

def matchSymbolHeadPattern : PCommand 3 :=
  .letValue i32 (index (slot 0) (slot 2))
    (.letValue i32 (unary .negate (integer 1))
      (.letValue i32 (unary .negate (integer 1))
        (.sequence readSecond (.sequence readThird symbolCases))))

def matchSymbolHeadCommand :
    Command Core.signature actions 3 :=
  matchSymbolHeadPattern.denote

/-! Small denotation equations used by the semantic proof.  The generic
pattern denotation is well-founded recursive (and therefore intentionally
opaque); these equations expose exactly the constructors used by the checked
symbol matcher without duplicating its syntax. -/

@[simp] theorem slot_denote (index : Fin arity) :
    (slot index).denote = Term.reference (.slot index) := by
  exact TermPattern.denote.eq_1 _

@[simp] theorem integer_denote (value : Int) :
    (integer (arity := arity) value).denote =
      Term.reference (.literal (.signed .i32 value)) := by
  exact TermPattern.denote.eq_2 _

@[simp] theorem tokenKind_denote (kind : Int) :
    (tokenKind (arity := arity) kind).denote =
      Term.apply (signature := Core.signature)
        (Operation.constant (tokenKindConstantId kind) i32) [] := by
  unfold tokenKind operation
  exact TermPattern.denote.eq_3 _ _

@[simp] theorem tokenMatch_denote (kind length : Int) :
    (tokenMatch (arity := arity) kind length).denote =
      Term.apply (signature := Core.signature)
        (Operation.call tokenMatchFunction.id [i32, i32] tokenMatchType)
        [(tokenKind (arity := arity) kind).denote,
          (integer (arity := arity) length).denote] := by
  unfold tokenMatch operation
  exact TermPattern.denote.eq_3 _ _

@[simp] theorem equal_denote (left right : PTerm arity) :
    (equal left right).denote =
      Term.apply (signature := Core.signature)
        (Operation.binary .equal i32 i32 bool)
        [left.denote, right.denote] := by
  unfold equal binary operation
  exact TermPattern.denote.eq_3 _ _

@[simp] theorem unary_denote (op : UnaryOp) (operand : PTerm arity) :
    (unary op operand).denote =
      Term.apply (signature := Core.signature)
        (Operation.unary op i32 i32) [operand.denote] := by
  unfold unary operation
  exact TermPattern.denote.eq_3 _ _

@[simp] theorem add_denote (left right : PTerm arity) :
    (add left right).denote =
      Term.apply (signature := Core.signature)
        (Operation.binary .add i32 i32 i32) [left.denote, right.denote] := by
  unfold add binary operation
  exact TermPattern.denote.eq_3 _ _

@[simp] theorem less_denote (left right : PTerm arity) :
    (less left right).denote =
      Term.apply (signature := Core.signature)
        (Operation.binary .less i32 i32 bool) [left.denote, right.denote] := by
  unfold less binary operation
  exact TermPattern.denote.eq_3 _ _

@[simp] theorem index_denote (base position : PTerm arity) :
    (index base position).denote =
      Term.apply (signature := Core.signature)
        (Operation.index (.slice i32) i32 i32)
        [base.denote, position.denote] := by
  unfold index operation
  exact TermPattern.denote.eq_3 _ _

@[simp] theorem sequence_denote (first second : PCommand arity) :
    (CommandPattern.sequence first second).denote =
      Command.sequence first.denote second.denote := by
  exact CommandPattern.denote.eq_2 _ _

@[simp] theorem letValue_denote (type : Ty) (initializer : PTerm arity)
    (body : PCommand (arity + 1)) :
    (CommandPattern.letValue type initializer body).denote =
      Command.letValue type initializer.denote body.denote := by
  exact CommandPattern.denote.eq_3 _ _ _

@[simp] theorem setLocal_denote (target : Fin arity)
    (value : PTerm arity) :
    (CommandPattern.setLocal target value : PCommand arity).denote =
      Command.setLocal target value.denote := by
  exact CommandPattern.denote.eq_4 _ _

@[simp] theorem ifThenElse_denote (condition : PTerm arity)
    (thenBranch elseBranch : PCommand arity) :
    (CommandPattern.ifThenElse condition thenBranch elseBranch).denote =
      Command.ifThenElse condition.denote thenBranch.denote
        elseBranch.denote := by
  exact CommandPattern.denote.eq_7 _ _ _

@[simp] theorem skip_denote :
    (CommandPattern.skip : PCommand arity).denote = Command.skip := by
  exact CommandPattern.denote.eq_1

@[simp] theorem returnValue_denote (value : Option (PTerm arity)) :
    (CommandPattern.returnValue value : PCommand arity).denote =
      Command.returnValue (value.map TermPattern.denote) := by
  exact CommandPattern.denote.eq_9 _

@[simp] theorem returnMatch_denote (kind length : Int) :
    (returnMatch (arity := arity) kind length).denote =
      Command.sequence
        (Command.returnValue
          (some ((tokenMatch (arity := arity) kind length).denote)))
        Command.skip := by
  unfold returnMatch
  rw [sequence_denote, returnValue_denote, skip_denote]
  rfl

theorem matchSymbolHead_pattern_matches :
    matchSymbolHeadPattern.matches matchSymbolHeadView.command = true := by
  native_decide

/-- The readable command is exactly the artifact-backed recovered command. -/
theorem matchSymbolHead_command_exact :
    matchSymbolHeadView.command = matchSymbolHeadCommand := by
  exact matchSymbolHeadPattern.matches_sound matchSymbolHead_pattern_matches

end Lanius.Extraction.Symbol.Structure
