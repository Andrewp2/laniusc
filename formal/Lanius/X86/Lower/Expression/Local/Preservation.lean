import Lanius.X86.Lower.Expression.Local
import Lanius.X86.Lower.Expression.Local.Native

namespace Lanius.X86.Lower.Expression.Local.Preservation

open Lanius.Core
variable {literal : Source.Expression.Literal.Checked emitters}
  {coreLocal : VarId}

/-- The actual source call emits a load preserving this Core local's i32 value. -/
theorem compiles (checked : Source.Expression.Local.Checked literal) (c : Context) (valid : c.Valid)
    (binding : Binding c .w32 coreLocal slot) (source : Syntax c coreLocal)
    (canonical : -2147483648 ≤ value ∧ value ≤ 2147483647) :
    c.Emits emitters.pack.program.core literal.wrapper.source.function.id 1
      (Value.Get.bytes .w32 slot) (afterLocal .w32 c.workspace c.position c.start slot)
      (NativeRefines slot coreLocal value) :=
  (Local.compiles checked c valid binding source).refines (bytes_refines slot coreLocal canonical)

/-- Serialized Core syntax discharges the tag, identifier and read bounds. -/
theorem from_transport (checked : Source.Expression.Local.Checked literal) (c : Context) (valid : c.Valid)
    (binding : Binding c .w32 coreLocal slot)
    (serialized : Transport.expression? sourceProgram (.local coreLocal) = some words)
    (stream : (c.transport.take c.length).drop c.position = words ++ suffix)
    (canonical : -2147483648 ≤ value ∧ value ≤ 2147483647) :
    coreLocal ≤ 2147483647 ∧ c.Emits emitters.pack.program.core literal.wrapper.source.function.id 1
      (Value.Get.bytes .w32 slot) (afterLocal .w32 c.workspace c.position c.start slot)
      (NativeRefines slot coreLocal value) := by
  obtain ⟨bounded, source⟩ := Syntax.from_transport serialized stream
  exact ⟨bounded, compiles checked c valid binding source canonical⟩

/-- Pointer loads preserve the machine-address mapping, not numerical identity. -/
theorem pointer_compiles (checked : Source.Expression.Local.Checked literal) (c : Context) (valid : c.Valid)
    (binding : Binding c .w64 coreLocal slot) (source : Syntax c coreLocal) :
    c.Emits emitters.pack.program.core literal.wrapper.source.function.id 4
      (Value.Get.bytes .w64 slot) (afterLocal .w64 c.workspace c.position c.start slot)
      (PointerNativeRefines locations slot coreLocal pointer) :=
  (Local.compiles checked c valid binding source).refines (pointer_bytes_refines locations slot coreLocal pointer)

theorem pointer_from_transport (checked : Source.Expression.Local.Checked literal) (c : Context) (valid : c.Valid)
    (binding : Binding c .w64 coreLocal slot)
    (serialized : Transport.expression? sourceProgram (.local coreLocal) = some words)
    (stream : (c.transport.take c.length).drop c.position = words ++ suffix) :
    coreLocal ≤ 2147483647 ∧ c.Emits emitters.pack.program.core literal.wrapper.source.function.id 4
      (Value.Get.bytes .w64 slot) (afterLocal .w64 c.workspace c.position c.start slot)
      (PointerNativeRefines locations slot coreLocal pointer) := by
  obtain ⟨bounded, source⟩ := Syntax.from_transport serialized stream
  exact ⟨bounded, pointer_compiles checked c valid binding source⟩

end Lanius.X86.Lower.Expression.Local.Preservation
