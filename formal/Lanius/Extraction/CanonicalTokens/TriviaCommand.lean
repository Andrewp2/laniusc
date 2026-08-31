import Lanius.Extraction.CanonicalTokens.Functions
import Lanius.FunctionalViewStatefulPattern

namespace Lanius.Extraction.CanonicalTokens.TriviaCommand

open Lanius.Core
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Stateful.Pattern
open Lanius.Extraction.CanonicalTokens.Functions

abbrev P (arity : Nat) := CommandPattern Core.signature actions arity
abbrev T (arity : Nat) := TermPattern Core.signature arity

def i32 : Ty := .scalar (.signed .i32)
def bool : Ty := .scalar .bool

def operation (value : Operation) : Exact Operation :=
  Exact.ofDecidableEq value

def slot : T 1 := .slot 0

def constant (id : ConstantId) : T 1 :=
  .apply (operation (.constant id i32)) []

def equal (right : T 1) : T 1 :=
  .apply (operation (.binary .equal i32 i32 bool)) [slot, right]

def pattern : P 1 :=
  .sequence
    (.returnValue (some
      (.logicalOr
        (.logicalOr (equal (constant 9)) (equal (constant 16)))
        (equal (constant 17)))))
    .skip

abbrev C (arity : Nat) :=
  Lanius.FunctionalView.Stateful.Command Core.signature actions arity
abbrev D (arity : Nat) := Term Core.signature arity

def directSlot : D 1 := .reference (.slot 0)

def directConstant (id : ConstantId) : D 1 :=
  .apply (.constant id i32) []

def directEqual (right : D 1) : D 1 :=
  .apply (.binary .equal i32 i32 bool) [directSlot, right]

def directPredicate : D 1 :=
  .logicalOr
    (.logicalOr (directEqual (directConstant 9))
      (directEqual (directConstant 16)))
    (directEqual (directConstant 17))

def directCommand : C 1 :=
  .sequence
    (.returnValue (some directPredicate))
    .skip

def command : C 1 := directCommand

theorem recovered : isTriviaView.command = command := by
  calc
    isTriviaView.command = pattern.denote := exact_of_matches (by native_decide)
    _ = command := (exact_of_matches
      (candidate := command) (by native_decide)).symm

end Lanius.Extraction.CanonicalTokens.TriviaCommand
