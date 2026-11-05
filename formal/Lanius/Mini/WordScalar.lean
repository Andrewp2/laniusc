module

public import Lanius.Mini.SourceCore
public import Lanius.NativeLayout
public import Lanius.Mini.Compiler.P.wordElement
public import Lanius.Mini.Compiler.P.SrcType_same
public import Lanius.Mini.Compiler.P.SrcType_size
public import Lanius.Mini.Compiler.P.fieldOffset
public import Lanius.Mini.Compiler.P.norm
public import Lanius.Mini.Compiler.P.wrap
import all Lanius.Mini.Compiler.P.BinOp_size
import all Lanius.Mini.Compiler.P.Lists_concat
import all Lanius.Mini.Compiler.P.Lists_cons
import all Lanius.Mini.Compiler.P.Lists_empty
import all Lanius.Mini.Compiler.P.Lists_get
import all Lanius.Mini.Compiler.P.Lists_getOr
import all Lanius.Mini.Compiler.P.Lists_length
import all Lanius.Mini.Compiler.P.Lists_single
import all Lanius.Mini.Compiler.P.MemWidth_bytes
import all Lanius.Mini.Compiler.P.MemWidth_prefix
import all Lanius.Mini.Compiler.P.MemWidth_rex
import all Lanius.Mini.Compiler.P.Word_prefix
import all Lanius.Mini.Compiler.P.SrcType_same
import all Lanius.Mini.Compiler.P.SrcType_size
import all Lanius.Mini.Compiler.P.fieldOffset
import all Lanius.Mini.Compiler.P.norm
import all Lanius.Mini.Compiler.P.wrap
import all Lanius.Mini.Compiler.P.SrcType_floatTy
import all Lanius.Mini.Compiler.P.SrcType_isBool
import all Lanius.Mini.Compiler.P.SrcType_isChar
import all Lanius.Mini.Compiler.P.SrcType_isFloat
import all Lanius.Mini.Compiler.P.SrcType_isFloatAny
import all Lanius.Mini.Compiler.P.SrcType_isI32
import all Lanius.Mini.Compiler.P.SrcType_isInteger
import all Lanius.Mini.Compiler.P.SrcType_isIsize
import all Lanius.Mini.Compiler.P.SrcType_isPtr
import all Lanius.Mini.Compiler.P.SrcType_isScalar
import all Lanius.Mini.Compiler.P.SrcType_isSint
import all Lanius.Mini.Compiler.P.SrcType_isSintAny
import all Lanius.Mini.Compiler.P.SrcType_isStr
import all Lanius.Mini.Compiler.P.SrcType_isUint
import all Lanius.Mini.Compiler.P.SrcType_isUnit
import all Lanius.Mini.Compiler.P.SrcType_sintKind
import all Lanius.Mini.Compiler.P.SrcType_uintKind
import all Lanius.Mini.Compiler.P.SrcType_word
import all Lanius.Mini.Compiler.P.UintTy_half
import all Lanius.Mini.Compiler.P.UintTy_leastBits
import all Lanius.Mini.Compiler.P.UintTy_signedWord
import all Lanius.Mini.Compiler.P.UintTy_spare
import all Lanius.Mini.Compiler.P.boolBits
import all Lanius.Mini.Compiler.P.lookup
import all Lanius.Mini.Compiler.P.Code_image
import all Lanius.Mini.Compiler.P.Code_size
import all Lanius.Mini.Compiler.P.Instr_encode
import all Lanius.Mini.Compiler.P.argBase
import all Lanius.Mini.Compiler.P.copyBytes
import all Lanius.Mini.Compiler.P.encodeFrom
import all Lanius.Mini.Compiler.P.encodeOnto
import all Lanius.Mini.Compiler.P.epilogue
import all Lanius.Mini.Compiler.P.frameSize
import all Lanius.Mini.Compiler.P.layout
import all Lanius.Mini.Compiler.P.linkFrom
import all Lanius.Mini.Compiler.P.linkOnto
import all Lanius.Mini.Compiler.P.loadAtBytes
import all Lanius.Mini.Compiler.P.loadWordBytes
import all Lanius.Mini.Compiler.P.prologue
import all Lanius.Mini.Compiler.P.relative
import all Lanius.Mini.Compiler.P.slotRange
import all Lanius.Mini.Compiler.P.stackCheck
import all Lanius.Mini.Compiler.P.storeAtBytes
import all Lanius.Mini.Compiler.P.storeWordBytes
import all Lanius.Mini.Compiler.P.sysBytes
import all Lanius.Mini.Compiler.P.syscallLinuxByte
import all Lanius.Mini.Compiler.P.syscallLinuxHigh
import all Lanius.Mini.Compiler.P.syscallRsiBytes
import all Lanius.Mini.Compiler.P.UintTy_code
import all Lanius.Mini.Compiler.P.entriesAt
import all Lanius.Mini.Compiler.P.funcsSize
import all Lanius.Mini.Compiler.P.funcsSlots
import all Lanius.Mini.Compiler.P.linkObjects
import all Lanius.Mini.Compiler.P.objectExports
import all Lanius.Mini.Compiler.P.objectFirsts
import all Lanius.Mini.Compiler.P.objectLayout
import all Lanius.Mini.Compiler.P.objectsLayout
import all Lanius.Mini.Compiler.P.objectsOk
import all Lanius.Mini.Compiler.P.objectsSlots
import all Lanius.Mini.Compiler.P.render
import all Lanius.Mini.Compiler.P.renderFuncs
import all Lanius.Mini.Compiler.P.renderObjects
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
