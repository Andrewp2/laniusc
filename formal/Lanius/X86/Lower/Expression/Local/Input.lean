import Lanius.X86.Lower.Expression.Contract
import Lanius.X86.Frame.Lookup
import Lanius.X86.Lower.Value.Get
import Lanius.X86.Transport.Local

namespace Lanius.X86.Lower.Expression.Local

open Lanius.Core

/-- The local's lexical binding and its actual frame-table representation. -/
structure Binding (c : Context) (width : Register.Width) (key : Int) (slot : Nat) where
  active : Nat
  activeValue : c.active = .signed .i32 active
  stride : Nat
  index : Nat
  correct : Frame.Lookup.Correct c.workspace active key (some index)
  tableRoom : 16 + active ≤ c.workspace.length
  tableBound : 16 + active ≤ 2147483647
  strideValue : c.workspace[12]? = some (stride : Int)
  kindInside : 16 + stride + index < c.workspace.length
  slotInside : 16 + stride * 2 + index < c.workspace.length
  addressBound : 16 + stride * 2 + index ≤ 2147483647
  kindValue : c.workspace[16 + stride + index]? = some (Value.Get.kind width)
  slotValue : c.workspace[16 + stride * 2 + index]? = some (slot : Int)
  slotBound : slot ≤ 1048576
  room : c.start + (Value.Get.bytes width slot).length ≤ c.capacity

structure Syntax (c : Context) (key : Int) : Prop where
  readable : c.position + 2 ≤ c.length
  tagWord : c.transport[c.position]? = some 1
  keyWord : c.transport[c.position + 1]? = some key

/-- Serialized local syntax supplies its read bounds and exact identifier. -/
theorem Syntax.from_transport
    {c : Context}
    (serialized : Transport.expression? program (.local coreLocal) = some words)
    (stream : (c.transport.take c.length).drop c.position = words ++ suffix) :
    coreLocal ≤ 2147483647 ∧ Syntax c coreLocal := by
  obtain ⟨identifierBound, available, tag, key⟩ := Transport.local_window serialized stream
  have readable : c.position + 2 ≤ c.length := by
    simp only [List.length_take] at available
    omega
  rw [List.getElem?_take_of_lt (by omega)] at tag
  rw [List.getElem?_take_of_lt (by omega)] at key
  exact ⟨identifierBound, readable, tag, key⟩

end Lanius.X86.Lower.Expression.Local
