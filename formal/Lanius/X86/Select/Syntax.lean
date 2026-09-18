import Lanius.X86.Source.Buffer
import Lanius.FunctionalViewCoreStateful

namespace Lanius.X86.Select.Syntax

open Lanius.Core Lanius.FunctionalView Lanius.FunctionalView.Core Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Stateful

abbrev T (arity : Nat) := Term signature arity
abbrev C (arity : Nat) := Command signature actions arity
abbrev i32 : Ty := .scalar (.signed .i32)
abbrev bool : Ty := .scalar .bool

def slot (index : Nat) (bound : index < arity := by omega) : T arity := reference ⟨index, bound⟩
def number (value : Int) : T arity := literal (.signed .i32 value)
def binary (op : BinaryOp) (result : Ty) (left right : T arity) : T arity :=
  .apply (.binary op i32 i32 result) [left, right]
def add (left right : T arity) : T arity := binary .add i32 left right
def mul (left right : T arity) : T arity := binary .multiply i32 left right
def eq (left right : T arity) : T arity := binary .equal bool left right
def ne (left right : T arity) : T arity := binary .notEqual bool left right
def lt (left right : T arity) : T arity := binary .less bool left right
def gt (left right : T arity) : T arity := binary .greater bool left right
def get (index : T arity) (bound : 0 < arity := by omega) : T arity :=
  .apply (.index (.slice i32) i32 i32) [slot 0 bound, index]
def negative : T arity := .apply (.unary .negate i32 i32) [number 1]
def returned (value : T arity) : C arity := .sequence (.returnValue (some value)) .skip
def reject (condition : T arity) : C arity := .ifThenElse condition (returned negative) .skip
def increment (index : Nat) (bound : index < arity := by omega) : C arity :=
  .sequence (.updateLocal .add ⟨index, bound⟩ (number 1)) .skip

def header : T 2 := .logicalOr (.logicalOr (.logicalOr
  (ne (get (number 0)) (number 1)) (ne (get (number 1)) (number 64)))
  (lt (get (number 2)) (number 0))) (ne (get (number 3)) (number 1))

def counts : T 4 := .logicalOr (.logicalOr (lt (slot 2) (number 1)) (gt (slot 2) (number 6)))
  (.logicalAnd (ne (slot 3) (number 4)) (ne (slot 3) (number 6)))

def idAt (index : T arity) (bound : 0 < arity := by omega) : T arity :=
  get (add (number 6) (mul index (number 2))) bound
def typeAt (index : T arity) (bound : 0 < arity := by omega) : T arity :=
  get (add (number 7) (mul index (number 2))) bound

def earlierCondition : T 11 := lt (slot 10) (slot 8)
def earlierBody : C 11 :=
  .sequence (reject (eq (idAt (slot 10)) (slot 9))) (increment 10)
def earlierLoop : C 11 := .whileLoop earlierCondition earlierBody

def selectCurrent : C 11 := .ifThenElse (eq (slot 9) (slot 6))
  (.sequence (.setLocal ⟨7, by decide⟩ (slot 8)) .skip) .skip
def iteration : C 9 :=
  .letValue i32 (idAt (slot 8))
    (.sequence (reject (.logicalOr (lt (slot 9) (number 0)) (ne (typeAt (slot 8)) (number 1))))
      (.letValue i32 (number 0) (.sequence earlierLoop (.sequence selectCurrent (increment 8)))))
def loop : C 9 := .whileLoop (lt (slot 8) (slot 2)) iteration
def scan : C 7 :=
  .letValue i32 negative (.letValue i32 (number 0) (.sequence loop (returned (slot 7))))

def returnTags : T 6 := .logicalOr
  (.logicalOr (ne (get (slot 5)) (number 10)) (ne (get (add (slot 5) (number 1))) (number 1)))
  (ne (get (add (slot 5) (number 2))) (number 1))
def unwrap : C 6 := .ifThenElse (eq (slot 3) (number 6))
  (.sequence (reject (.logicalOr (ne (get (slot 4)) (number 2))
    (ne (get (add (slot 4) (number 5))) (number 0)))) (increment 5)) .skip
def afterBody : C 5 :=
  .sequence (reject (ne (slot 1) (add (slot 4) (slot 3))))
    (.letValue i32 (slot 4) (.sequence unwrap (.sequence (reject returnTags)
      (.letValue i32 (get (add (slot 5) (number 3))) scan))))
def command : C 2 :=
  .sequence (reject (lt (slot 1) (number 6))) (.sequence (reject header)
    (.letValue i32 (get (number 4)) (.letValue i32 (get (number 5))
      (.sequence (reject counts) (.letValue i32 (add (number 6) (mul (slot 2) (number 2))) afterBody)))))

/-- The structural body is checked against the current source. It is not an
assumed implementation or a second semantics for the input program. -/
def body : Stmt := Stateful.toCoreStmt actionAdapter identityLayout 2 command

end Lanius.X86.Select.Syntax
