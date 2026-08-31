import Lanius.Compiler.LexerCanonical
import Lanius.Extraction.CanonicalTokens.Functions
import Lanius.FunctionalViewStatefulPattern

namespace Lanius.Extraction.CanonicalTokens.KeywordCommand

open Lanius
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
def slice : Ty := .slice i32

def operation (value : Operation) : Exact Operation :=
  Exact.ofDecidableEq value

def slot {arity : Nat} (index : Fin arity) : T arity := .slot index
def literal {arity : Nat} (value : Int) : T arity :=
  .literal (.signed .i32 value)
def constant {arity : Nat} (id : ConstantId) : T arity :=
  .apply (operation (.constant id i32)) []
def binary {arity : Nat} (op : BinaryOp) (left right : T arity)
    (result : Ty) : T arity :=
  .apply (operation (.binary op i32 i32 result)) [left, right]
def add {arity : Nat} (left right : T arity) : T arity :=
  binary .add left right i32
def equal {arity : Nat} (left right : T arity) : T arity :=
  binary .equal left right bool
def index {arity : Nat} (base offset : T arity) : T arity :=
  .apply (operation (.index slice i32 i32)) [base, offset]

def returned {arity : Nat} (value : T arity) : P arity :=
  .sequence (.returnValue (some value)) .skip

def allEqual {arity : Nat} : List (Fin arity × Int) → T arity
  | [] => .literal (.boolean true)
  | (position, value) :: rest =>
      rest.foldl
        (fun condition (nextPosition, nextValue) =>
          .logicalAnd condition
            (equal (slot nextPosition) (literal nextValue)))
        (equal (slot position) (literal value))

def choices {arity : Nat} : List (List (Fin arity × Int) × ConstantId) → P arity
  | [] => .skip
  | (bytes, kind) :: rest =>
      .sequence
        (.ifThenElse (allEqual bytes) (returned (constant kind)) .skip)
        (choices rest)

def load2 (body : P 6) : P 4 :=
  .letValue i32 (index (slot 0) (slot 1))
    (.letValue i32 (index (slot 0) (add (slot 1) (literal 1))) body)

def load3 (body : P 7) : P 4 :=
  .letValue i32 (index (slot 0) (slot 1))
    (.letValue i32 (index (slot 0) (add (slot 1) (literal 1)))
      (.letValue i32 (index (slot 0) (add (slot 1) (literal 2))) body))

def load4 (body : P 8) : P 4 :=
  .letValue i32 (index (slot 0) (slot 1))
    (.letValue i32 (index (slot 0) (add (slot 1) (literal 1)))
      (.letValue i32 (index (slot 0) (add (slot 1) (literal 2)))
        (.letValue i32 (index (slot 0) (add (slot 1) (literal 3))) body)))

def load5 (body : P 9) : P 4 :=
  .letValue i32 (index (slot 0) (slot 1))
    (.letValue i32 (index (slot 0) (add (slot 1) (literal 1)))
      (.letValue i32 (index (slot 0) (add (slot 1) (literal 2)))
        (.letValue i32 (index (slot 0) (add (slot 1) (literal 3)))
          (.letValue i32 (index (slot 0) (add (slot 1) (literal 4))) body))))

def load6 (body : P 10) : P 4 :=
  .letValue i32 (index (slot 0) (slot 1))
    (.letValue i32 (index (slot 0) (add (slot 1) (literal 1)))
      (.letValue i32 (index (slot 0) (add (slot 1) (literal 2)))
        (.letValue i32 (index (slot 0) (add (slot 1) (literal 3)))
          (.letValue i32 (index (slot 0) (add (slot 1) (literal 4)))
            (.letValue i32 (index (slot 0) (add (slot 1) (literal 5))) body)))))

def load8 (body : P 12) : P 4 :=
  .letValue i32 (index (slot 0) (slot 1))
    (.letValue i32 (index (slot 0) (add (slot 1) (literal 1)))
      (.letValue i32 (index (slot 0) (add (slot 1) (literal 2)))
        (.letValue i32 (index (slot 0) (add (slot 1) (literal 3)))
          (.letValue i32 (index (slot 0) (add (slot 1) (literal 4)))
            (.letValue i32 (index (slot 0) (add (slot 1) (literal 5)))
              (.letValue i32 (index (slot 0) (add (slot 1) (literal 6)))
                (.letValue i32 (index (slot 0) (add (slot 1) (literal 7)))
                  body)))))))

def length2Rules : List (List (Fin 6 × Int) × ConstantId) := [
  ([(4, 102), (5, 110)], 61),
  ([(4, 105), (5, 102)], 64),
  ([(4, 105), (5, 110)], 81)]
def length2 : P 6 := choices length2Rules

def length3Rules : List (List (Fin 7 × Int) × ConstantId) := [
  ([(4, 112), (5, 117), (6, 98)], 60),
  ([(4, 108), (5, 101), (6, 116)], 62),
  ([(4, 102), (5, 111), (6, 114)], 80)]
def length3 : P 7 := choices length3Rules

def length4Rules : List (List (Fin 8 × Int) × ConstantId) := [
  ([(4, 101), (5, 108), (6, 115), (7, 101)], 65),
  ([(4, 116), (5, 114), (6, 117), (7, 101)], 70),
  ([(4, 101), (5, 110), (6, 117), (7, 109)], 73),
  ([(4, 105), (5, 109), (6, 112), (7, 108)], 78),
  ([(4, 115), (5, 101), (6, 108), (7, 102)], 85),
  ([(4, 116), (5, 121), (6, 112), (7, 101)], 83)]
def length4 : P 8 := choices length4Rules

def length5Rules : List (List (Fin 9 × Int) × ConstantId) := [
  ([(4, 102), (5, 97), (6, 108), (7, 115), (8, 101)], 71),
  ([(4, 99), (5, 111), (6, 110), (7, 115), (8, 116)], 72),
  ([(4, 109), (5, 97), (6, 116), (7, 99), (8, 104)], 75),
  ([(4, 116), (5, 114), (6, 97), (7, 105), (8, 116)], 79),
  ([(4, 119), (5, 104), (6, 101), (7, 114), (8, 101)], 84),
  ([(4, 119), (5, 104), (6, 105), (7, 108), (8, 101)], 66),
  ([(4, 98), (5, 114), (6, 101), (7, 97), (8, 107)], 67)]
def length5 : P 9 := choices length5Rules

def length6Rules : List (List (Fin 10 × Int) × ConstantId) := [
  ([(4, 114), (5, 101), (6, 116), (7, 117), (8, 114), (9, 110)], 63),
  ([(4, 115), (5, 116), (6, 114), (7, 117), (8, 99), (9, 116)], 74),
  ([(4, 101), (5, 120), (6, 116), (7, 101), (8, 114), (9, 110)], 82),
  ([(4, 105), (5, 109), (6, 112), (7, 111), (8, 114), (9, 116)], 76),
  ([(4, 109), (5, 111), (6, 100), (7, 117), (8, 108), (9, 101)], 77)]
def length6 : P 10 := choices length6Rules

def length8Rules : List (List (Fin 12 × Int) × ConstantId) := [
  ([(4, 99), (5, 111), (6, 110), (7, 116), (8, 105), (9, 110),
    (10, 117), (11, 101)], 68)]
def length8 : P 12 := choices length8Rules

def lengthBranch (length : Int) (body : P 4) : P 4 :=
  .ifThenElse (equal (slot 3) (literal length)) body .skip

def pattern : P 3 :=
  .letValue i32 (binary .subtract (slot 2) (slot 1) i32)
    (.sequence (lengthBranch 2 (load2 length2))
      (.sequence (lengthBranch 3 (load3 length3))
        (.sequence (lengthBranch 4 (load4 length4))
          (.sequence (lengthBranch 5 (load5 length5))
            (.sequence (lengthBranch 6 (load6 length6))
              (.sequence (lengthBranch 8 (load8 length8))
                (returned (constant 7))))))))

abbrev C (arity : Nat) :=
  Lanius.FunctionalView.Stateful.Command Core.signature actions arity
abbrev D (arity : Nat) := Term Core.signature arity

def directSlot {arity : Nat} (position : Fin arity) : D arity :=
  .reference (.slot position)
def directLiteral {arity : Nat} (value : Int) : D arity :=
  .reference (.literal (.signed .i32 value))
def directConstant {arity : Nat} (id : ConstantId) : D arity :=
  .apply (.constant id i32) []
def directBinary {arity : Nat} (op : BinaryOp) (left right : D arity)
    (result : Ty) : D arity :=
  .apply (.binary op i32 i32 result) [left, right]
def directAdd {arity : Nat} (left right : D arity) : D arity :=
  directBinary .add left right i32
def directEqual {arity : Nat} (left right : D arity) : D arity :=
  directBinary .equal left right bool
def directIndex {arity : Nat} (base offset : D arity) : D arity :=
  .apply (.index slice i32 i32) [base, offset]
def directReturned {arity : Nat} (value : D arity) : C arity :=
  .sequence (.returnValue (some value)) .skip

def directAllEqual {arity : Nat} : List (Fin arity × Int) → D arity
  | [] => .reference (.literal (.boolean true))
  | (position, value) :: rest =>
      rest.foldl
        (fun condition (nextPosition, nextValue) =>
          .logicalAnd condition
            (directEqual (directSlot nextPosition) (directLiteral nextValue)))
        (directEqual (directSlot position) (directLiteral value))

def directChoices {arity : Nat} :
    List (List (Fin arity × Int) × ConstantId) → C arity
  | [] => .skip
  | (bytes, kind) :: rest =>
      .sequence
        (.ifThenElse (directAllEqual bytes)
          (directReturned (directConstant kind)) .skip)
        (directChoices rest)

def directLoad2 (body : C 6) : C 4 :=
  .letValue i32 (directIndex (directSlot 0) (directSlot 1))
    (.letValue i32
      (directIndex (directSlot 0) (directAdd (directSlot 1) (directLiteral 1)))
      body)
def directLoad3 (body : C 7) : C 4 :=
  .letValue i32 (directIndex (directSlot 0) (directSlot 1))
    (.letValue i32
      (directIndex (directSlot 0) (directAdd (directSlot 1) (directLiteral 1)))
      (.letValue i32
        (directIndex (directSlot 0) (directAdd (directSlot 1) (directLiteral 2)))
        body))
def directLoad4 (body : C 8) : C 4 :=
  .letValue i32 (directIndex (directSlot 0) (directSlot 1))
    (.letValue i32
      (directIndex (directSlot 0) (directAdd (directSlot 1) (directLiteral 1)))
      (.letValue i32
        (directIndex (directSlot 0) (directAdd (directSlot 1) (directLiteral 2)))
        (.letValue i32
          (directIndex (directSlot 0) (directAdd (directSlot 1) (directLiteral 3)))
          body)))
def directLoad5 (body : C 9) : C 4 :=
  .letValue i32 (directIndex (directSlot 0) (directSlot 1))
    (.letValue i32
      (directIndex (directSlot 0) (directAdd (directSlot 1) (directLiteral 1)))
      (.letValue i32
        (directIndex (directSlot 0) (directAdd (directSlot 1) (directLiteral 2)))
        (.letValue i32
          (directIndex (directSlot 0) (directAdd (directSlot 1) (directLiteral 3)))
          (.letValue i32
            (directIndex (directSlot 0) (directAdd (directSlot 1) (directLiteral 4)))
            body))))
def directLoad6 (body : C 10) : C 4 :=
  .letValue i32 (directIndex (directSlot 0) (directSlot 1))
    (.letValue i32
      (directIndex (directSlot 0) (directAdd (directSlot 1) (directLiteral 1)))
      (.letValue i32
        (directIndex (directSlot 0) (directAdd (directSlot 1) (directLiteral 2)))
        (.letValue i32
          (directIndex (directSlot 0) (directAdd (directSlot 1) (directLiteral 3)))
          (.letValue i32
            (directIndex (directSlot 0) (directAdd (directSlot 1) (directLiteral 4)))
            (.letValue i32
              (directIndex (directSlot 0) (directAdd (directSlot 1) (directLiteral 5)))
              body)))))
def directLoad8 (body : C 12) : C 4 :=
  .letValue i32 (directIndex (directSlot 0) (directSlot 1))
    (.letValue i32
      (directIndex (directSlot 0) (directAdd (directSlot 1) (directLiteral 1)))
      (.letValue i32
        (directIndex (directSlot 0) (directAdd (directSlot 1) (directLiteral 2)))
        (.letValue i32
          (directIndex (directSlot 0) (directAdd (directSlot 1) (directLiteral 3)))
          (.letValue i32
            (directIndex (directSlot 0) (directAdd (directSlot 1) (directLiteral 4)))
            (.letValue i32
              (directIndex (directSlot 0) (directAdd (directSlot 1) (directLiteral 5)))
              (.letValue i32
                (directIndex (directSlot 0) (directAdd (directSlot 1) (directLiteral 6)))
                (.letValue i32
                  (directIndex (directSlot 0) (directAdd (directSlot 1) (directLiteral 7)))
                  body)))))))

def directLengthBranch (length : Int) (body : C 4) : C 4 :=
  .ifThenElse (directEqual (directSlot 3) (directLiteral length)) body .skip

def directCommand : C 3 :=
  .letValue i32 (directBinary .subtract (directSlot 2) (directSlot 1) i32)
    (.sequence (directLengthBranch 2 (directLoad2 (directChoices length2Rules)))
      (.sequence (directLengthBranch 3 (directLoad3 (directChoices length3Rules)))
        (.sequence (directLengthBranch 4 (directLoad4 (directChoices length4Rules)))
          (.sequence (directLengthBranch 5 (directLoad5 (directChoices length5Rules)))
            (.sequence (directLengthBranch 6 (directLoad6 (directChoices length6Rules)))
              (.sequence (directLengthBranch 8 (directLoad8 (directChoices length8Rules)))
                (directReturned (directConstant 7))))))))

def command : Lanius.FunctionalView.Stateful.Command
    Core.signature actions 3 := directCommand

theorem recovered : keywordKindView.command = command := by
  calc
    keywordKindView.command = pattern.denote := exact_of_matches (by native_decide)
    _ = command := (exact_of_matches
      (candidate := command) (by native_decide)).symm

end Lanius.Extraction.CanonicalTokens.KeywordCommand
