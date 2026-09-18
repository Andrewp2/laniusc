import Lanius.X86.Source.Buffer

namespace Lanius.X86.Source

open Lanius.Core Lanius.Semantics

/-- A literal result reached through the actual program's constant lookup. -/
structure IntegerConstant (program : Program) where
  id : ConstantId
  value : Int
  declaration : Constant
  found : program.constant? id = some declaration
  valueExact : declaration.value = .signed .i32 value

def integerConstant? (program : Program) (id : ConstantId) : Option (IntegerConstant program) :=
  match found : program.constant? id with
  | none => none
  | some declaration =>
    match valueExact : declaration.value with
    | .signed .i32 value => some ⟨id, value, declaration, found, valueExact⟩
    | _ => none

theorem IntegerConstant.evaluates (entry : IntegerConstant program) :
    Evaluates program before (.constant entry.id) (.signed .i32 entry.value) before := by
  refine ⟨1, ?_⟩
  simp only [evalExpr, entry.found, entry.valueExact]

end Lanius.X86.Source
