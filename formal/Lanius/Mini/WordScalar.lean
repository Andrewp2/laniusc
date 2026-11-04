module

public import Lanius.Mini.SourceCore
public import Lanius.NativeLayout
public import Lanius.Mini.Compiler.P.wordElement
public import Lanius.Mini.Compiler.P.SrcType_same
import all Lanius.Mini.Compiler.P.Lists_empty
import all Lanius.Mini.Compiler.P.SrcType_same
import all Lanius.Mini.Compiler.P.UintTy_half
import all Lanius.Mini.Compiler.P.loadAtBytes
import all Lanius.Mini.Compiler.P.render
import all Lanius.Mini.Compiler.P.wordElement

@[expose] public section

/-! The one-word scalar elements of a raw view: `u16`, `u32`, `u64`, `i64`
and `bool`. laniusc packs only `i32` and `u8` slices; every other scalar
element is one descending 8-byte word, the layout of a struct field. -/

namespace Lanius.Mini

/-- A source type whose raw view element is one word: `u16`, `u32`, `u64`,
`i64` or `bool`. -/
abbrev SrcType.WordScalar (e : SrcType) : Prop :=
  e = .uint .uint16 ∨ e = .uint .uint32 ∨ e = .uint .uint64 ∨ e = .sint .uint64 ∨ e = .bool

/-- A Core type whose raw view element is one word. -/
abbrev CoreWordScalar (t : Core.Ty) : Prop :=
  t = .scalar (.unsigned .u16) ∨ t = .scalar (.unsigned .u32) ∨ t = .scalar (.unsigned .u64) ∨
    t = .scalar (.signed .i64) ∨ t = .scalar .bool

theorem SrcType.WordScalar.toCore {e : SrcType} (w : e.WordScalar) : CoreWordScalar e.toCore := by
  rcases w with rfl | rfl | rfl | rfl | rfl
  · exact .inl rfl
  · exact .inr (.inl rfl)
  · exact .inr (.inr (.inl rfl))
  · exact .inr (.inr (.inr (.inl rfl)))
  · exact .inr (.inr (.inr (.inr rfl)))

/-- A word element is a struct, an enum or a one-word scalar. -/
theorem wordElement_cases {ds : SrcDecls} {e : SrcType} (h : wordElement ds e = true) :
    (∃ id fields, e = .struct id fields) ∨ (∃ id variants, e = .enum id variants) ∨ e.WordScalar := by
  cases e with
  | struct id fields => exact .inl ⟨id, fields, rfl⟩
  | enum id variants => exact .inr (.inl ⟨id, variants, rfl⟩)
  | uint k =>
    refine .inr (.inr ?_)
    cases k <;> simp_all [wordElement, SrcType.isUint, UintTy.code, SrcType.WordScalar]
  | sint k =>
    refine .inr (.inr ?_)
    cases k <;> simp_all [wordElement, SrcType.isSint, UintTy.code, SrcType.WordScalar]
  | bool => exact .inr (.inr (.inr (.inr (.inr (.inr rfl)))))
  | i32 | ptr | slice | array | unit | isize | char | float | view | str | ref => simp [wordElement] at h

/-- A one-word scalar takes one word. -/
theorem CoreWordScalar.words {P : Core.Program} {k n : Nat} {t : Core.Ty} (w : CoreWordScalar t)
    (h : NativeLayout.words? (k + 1) P t = some n) : n = 1 := by
  rcases w with rfl | rfl | rfl | rfl | rfl <;>
    (simp only [NativeLayout.words?, Option.some.injEq] at h; exact h.symm)

theorem CoreWordScalar.notByte {t : Core.Ty} (w : CoreWordScalar t) : Semantics.isByte t = false := by
  rcases w with rfl | rfl | rfl | rfl | rfl <;> rfl

theorem SrcType.WordScalar.size {e : SrcType} (w : e.WordScalar) : e.size = 1 := by
  rcases w with rfl | rfl | rfl | rfl | rfl <;> rfl

end Lanius.Mini
