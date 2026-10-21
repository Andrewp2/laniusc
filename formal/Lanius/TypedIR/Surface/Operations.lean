import Lanius.TypedIR.Surface

namespace Lanius.TypedIR.Surface
open Lanius

def Expr.bitAnd (left : Expr α) (right : Expr β) : Expr α := Expr.binary .bitAnd left right
def Expr.bitOr (left : Expr α) (right : Expr β) : Expr α := Expr.binary .bitOr left right
def Expr.bitXor (left : Expr α) (right : Expr β) : Expr α := Expr.binary .bitXor left right
def Expr.shiftLeft (left : Expr α) (right : Expr β) : Expr α := Expr.binary .shiftLeft left right
def Expr.shiftRight (left : Expr α) (right : Expr β) : Expr α := Expr.binary .shiftRight left right

class NaturalLiteral (α : Type) where
  value : Nat → Core.Value
instance : NaturalLiteral I32 := ⟨fun value => .signed .i32 value⟩
instance : NaturalLiteral Usize := ⟨.unsigned .usize⟩
instance : NaturalLiteral RawPtr := ⟨.pointer⟩
def Expr.natural [NaturalLiteral α] (value : Nat) : Expr α := ⟨.value (NaturalLiteral.value α value)⟩

/-- One named declaration owns the constant's data; uses refer to its ID. -/
structure Constant (α : Type) where
  core : Core.Constant
def Constant.id (value : Constant α) : ConstantId := value.core.id
def Constant.pack (value : Constant α) : Core.Constant := value.core
def Expr.constant (value : Constant α) : Expr α := ⟨.constant value.id⟩

-- The declaration owns its identity. Calls do not validate its signature.
def Expr.call (target : Function parameters result) (arguments : Args) : Expr result :=
  ⟨.call target.core.id arguments.values⟩

class Atom (source : Type) (result : outParam Type) where
  expression : source → Expr result
instance : Atom (Var α) α := ⟨Expr.local⟩
instance : Atom (Variant α []) α := ⟨fun constructor => Expr.variant constructor .nil⟩
instance : Atom (Constant α) α := ⟨Expr.constant⟩
def Expr.atom [Atom source result] (value : source) : Expr result := Atom.expression value

class Application (source : Type) (result : outParam Type) where
  expression : source → Args → Expr result
instance : Application (Variant α payload) α := ⟨Expr.variant⟩
instance : Application (Function parameters result) result := ⟨Expr.call⟩
def Expr.apply [Application source result] (target : source) (arguments : Args) : Expr result :=
  Application.expression target arguments

def Expr.indexSlice (base : Expr (Slice α)) (index : Expr β) : Expr α :=
  ⟨.index base.core index.core⟩
def Place.indexSlice (base : Place (Slice α)) (index : Expr β) : Place α :=
  ⟨.index base.core index.core⟩
def Expr.assign (op : Core.AssignOp) (place : Place α) (value : Expr β) : Expr Unit :=
  ⟨.assign op place.core value.core⟩

end Lanius.TypedIR.Surface
