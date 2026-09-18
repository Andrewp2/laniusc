import Lanius.X86.Relative
import Lanius.X86.Word.Core
import Lanius.X86.Tests.Pointers
import Lanius.X86.Tests.Boolean
import Lanius.X86.Tests.Table
import Lanius.X86.Tests.RawSlice
import Lanius.X86.Tests.RawEmission
import Lanius.X86.Lower.Expression.Raw
import Lanius.X86.Lower.Expression.Raw.Native
import Lanius.X86.Lower.Expression.Raw.Preservation
import Lanius.X86.Transport.Raw
import Lanius.X86.Buffer.Patch
import Lanius.X86.Buffer.Fixed
import Lanius.X86.Control.Emission
import Lanius.X86.Control.Calls
import Lanius.X86.Control.Layout
import Lanius.X86.Source.Check
import Lanius.X86.Register.Execution
import Lanius.X86.Encode.Register
import Lanius.X86.Encode.Direct
import Lanius.X86.Encode.Guarded
import Lanius.X86.Encode.Indexed
import Lanius.X86.Encode.Memory
import Lanius.X86.Encode.Immediate
import Lanius.X86.Encode.Immediate.Wide.Preservation
import Lanius.X86.Lower.Value.Get
import Lanius.X86.Frame.Take
import Lanius.X86.Frame.Take.Reject
import Lanius.X86.Frame.Lookup
import Lanius.X86.Lower.Expression.Literal.Layout
import Lanius.X86.Lower.Expression.Literal
import Lanius.X86.Lower.Expression.Literal.Preservation
import Lanius.X86.Lower.Expression.Literal.Capacity
import Lanius.X86.Lower.Expression.Literal.Boolean
import Lanius.X86.Lower.Expression.Indexed.Literal.Preservation
import Lanius.X86.Lower.Expression.Local
import Lanius.X86.Lower.Expression.Local.Reject
import Lanius.X86.Lower.Expression.Local.Native
import Lanius.X86.Lower.Expression.Local.Preservation
import Lanius.X86.Frame.Slot
import Lanius.X86.Frame.Allocate
import Lanius.X86.Lower.Expression.Indexed.Prepare
import Lanius.X86.Lower.Expression.Indexed.Capture
import Lanius.X86.Lower.Expression.Indexed.Reject
import Lanius.X86.Lower.Expression.Indexed.Body
import Lanius.X86.Lower.Expression.Indexed.Failure
import Lanius.X86.Lower.Expression.Indexed.Preservation
import Lanius.X86.Control.Require
import Lanius.X86.Lower.Index.Preservation
import Lanius.X86.Lower.Index.Reject
import Lanius.X86.Lower.Return
import Lanius.X86.Lower.Reject
import Lanius.X86.Lower.Preservation
import Lanius.X86.Lower.Implementation
import Lanius.X86.Frame.Source
import Lanius.X86.Frame.Execution
import Lanius.X86.Frame.Function
import Lanius.X86.Frame.Return
import Lanius.X86.Storage.Value
import Lanius.X86.Frame.Copy
import Lanius.X86.Lower.Slice
import Lanius.X86.Lower.Index
import Lean.Elab.Term
import Lean.Util.CollectAxioms

open Lanius.X86

example : (BitVec.ofInt 32 (relativeDisplacement 2147483647 0)).toInt = -2147483647 := by
  rw [relativeDisplacement_signed _ _ (by decide) (by decide)]
  rfl

example : nearTarget 0xffffffffffffffff#64 2#32 = 1#64 := by decide

example : Control.decode [0xe9, 0xfc, 0xff, 0xff, 0xff, 0xc3] =
    some (.jump (BitVec.ofInt 32 (-4)), 5) := by decide
example : Control.decode [0xe8, 0, 0, 0, 0x80] =
    some (.call (BitVec.ofInt 32 (-2147483648)), 5) := by decide
example : Control.decode [0x0f, 0x8f, 0xff, 0xff, 0xff, 0x7f] =
    some (.branch ⟨15, by decide⟩ 0x7fffffff#32, 6) := by decide
example : Control.decode [0xe9, 0, 0, 0] = none := by decide
example : Control.decode [0x0f, 0x84, 0, 0, 0] = none := by decide
example : Control.decode [0x66, 0xe9, 0, 0, 0, 0] = none := by decide
example : Control.decode [0x0f] = none := by decide
example : Control.decode [0xc2, 0, 0] = none := by decide

example : ∀ byte : Fin 256, (Register.Rex.decode? byte.val).isSome =
    decide (64 ≤ byte.val ∧ byte.val < 80) := by
  intro byte
  by_cases within : 64 ≤ byte.val ∧ byte.val < 80 <;> simp [Register.Rex.decode?, within]
example : Register.value .w32 ⟨0, by decide⟩ ⟨4, by decide⟩ true = 64 := by decide
example : Register.value .w32 ⟨0, by decide⟩ ⟨4, by decide⟩ false = 0 := by decide
example : Register.value .w64 ⟨15, by decide⟩ ⟨15, by decide⟩ false = 77 := by decide

-- Decoding distinguishes REX operand width, signed displacement, and SIB
-- index bits. Unsupported and truncated encodings are not executable steps.
example : Machine.decode [0x48, 0x89, 0xe5] = some (.move64 5 4, 3) := by decide
example : Machine.decode [0x45, 0x8b, 0xac, 0x24, 0xf8, 0xff, 0xff, 0xff] =
    some (.load32 13 12 (BitVec.ofInt 32 (-8)), 8) := by decide
example : Machine.decode [0x47, 0x8b, 0xac, 0x24, 0xf8, 0xff, 0xff, 0xff] = none := by decide
example : Machine.decode [0x4d, 0x8b, 0x93, 0x08, 0, 0, 0] =
    some (.load64 10 11 8, 7) := by decide
example : Machine.decode [0x4c, 0x89, 0x90, 0xf8, 0xff, 0xff, 0xff] =
    some (.store64 10 0 (BitVec.ofInt 32 (-8)), 7) := by decide
example : Machine.decode [0x4f, 0x8b, 0x94, 0x24, 0, 0, 0, 0] = none := by decide
example : Machine.decode [0x8b, 0x85, 0xf8, 0xff, 0xff] = none := by decide
example : Machine.decode [0x41, 0xbb, 0xff, 0xff, 0xff, 0xff] =
    some (.immediate32 11 0xffffffff#32, 6) := by decide
example : Machine.decode [0x49, 0xbb, 0xff, 0xff, 0xff, 0xff] = none := by decide
example : Machine.decode [0x48, 0xb8, 0x78, 0x56, 0x34, 0x12, 0xef, 0xcd, 0xab, 0x90, 0xc3] =
    some (.immediate64 0 0x90abcdef12345678#64, 10) := by decide
example : Machine.decode [0x49, 0xbb, 0, 0, 0, 0, 0, 0, 0, 0x80] =
    some (.immediate64 11 0x8000000000000000#64, 10) := by decide
example : Machine.decode [0x48, 0xb8, 1, 2, 3, 4, 5, 6, 7] = none := by decide
example (before : Machine.State) :
    (before.immediate32 11 0xffffffff#32 6).registers 11 = 0x00000000ffffffff#64 := by
  simp [Machine.State.immediate32]
example (before : Machine.State) :
    (before.immediate64 11 0x80000000ffffffff#64 10).registers 11 = 0x80000000ffffffff#64 := by
  simp [Machine.State.immediate64]
example : Machine.decode [0x66, 0x8b, 0x85, 0, 0, 0, 0] = none := by decide

-- Stack widths and source/destination timing differ from ordinary MOV.
example : Machine.decode [0x55, 0xc3] = some (.push64 5, 1) := by decide
example : Machine.decode [0x41, 0x54] = some (.push64 12, 2) := by decide
example : Machine.decode [0x41, 0x5d] = some (.pop64 13, 2) := by decide
example : Machine.decode [0x66, 0x55] = none := by decide
example : Machine.decode [0x4c, 0x29, 0xdc] = some (.subtract64 4 11, 3) := by decide
example : Machine.decode [0x29, 0xdc] = none := by decide
example : Machine.decode [0x4c, 0x29] = none := by decide
example : Machine.decode [0x48, 0x63, 0xc0] = some (.signExtend32 0 0, 3) := by decide
example : Machine.decode [0x63, 0xc0] = none := by decide
example : Machine.decode [0x4c, 0x39, 0xd0] = some (.compare64 0 10, 3) := by decide
example : Machine.decode [0x49, 0x8d, 0x84, 0x83, 0, 0, 0, 0] =
    some (.address64 0 11 (some 0) 2 0, 8) := by decide
example : Machine.decode [0x4b, 0x8d, 0x84, 0xa3, 0, 0, 0, 0] =
    some (.address64 0 11 (some 12) 2 0, 8) := by decide
example : Machine.decode [0x49, 0x8d, 0x84, 0xa3, 0, 0, 0, 0] =
    some (.address64 0 11 none 2 0, 8) := by decide
example : Machine.decode [0x48, 0x8d, 0x85, 0xf8, 0xff, 0xff, 0xff] =
    some (.address64 0 5 none 0 (BitVec.ofInt 32 (-8)), 7) := by decide
example : Machine.decode [0x49, 0x8d, 0x84, 0x83, 0, 0, 0] = none := by decide
example : Machine.decode [0x0f, 0x82, 2, 0, 0, 0, 0x0f, 0x0b] = some (.branch 2 2, 6) := by decide
example : Machine.Index.word true 0x12345678ffffffff#64 = 0xffffffffffffffff#64 := by decide
example : Machine.Index.word true 0x123456787fffffff#64 = 0x7fffffff#64 := by decide
example : Machine.Index.word false 0x100000000#64 = 0x100000000#64 := by decide
example : Encode.Immediate.bytes (-2147483648) = [0xb8, 0, 0, 0, 0x80] := by decide
example : Encode.Immediate.bytes 305419896 = [0xb8, 0x78, 0x56, 0x34, 0x12] := by decide
example : Encode.Immediate.bytes 2147483647 = [0xb8, 0xff, 0xff, 0xff, 0x7f] := by decide
example : Transport.literal? (.signed .i32 (-2147483649)) = none := by decide
example : Transport.literal? (.signed .i32 2147483648) = none := by decide
example : Transport.localId? 2147483647 = some 2147483647 := by decide
example : Transport.localId? 2147483648 = none := by decide
example : Lower.Value.Get.bytes .w32 511 = [0x8b, 0x85, 0, 0xf0, 0xff, 0xff] := by decide
example : Lower.Value.Get.bytes .w64 511 = [0x48, 0x8b, 0x85, 0, 0xf0, 0xff, 0xff] := by decide

-- Fixed independent bytes guard endianness, including address wraparound;
-- a read/write round trip alone would also accept two matching wrong orders.
example : Machine.read64 (fun address => UInt8.ofNat (address.toNat + 1)) 0 =
    0x0807060504030201#64 := by decide
example : Machine.read64 (fun address => UInt8.ofNat address.toNat) 0xfffffffffffffffc#64 =
    0x03020100fffefdfc#64 := by decide
example (before : Machine.State) :
    Machine.read64 (before.push64 4 1).memory (before.registers 4 - 8) = before.registers 4 := by
  exact Machine.read64_write64 _ _ _
example (before : Machine.State) :
    (before.pop64 4 1).registers 4 = Machine.read64 before.memory (before.registers 4) := by
  simp [Machine.State.pop64]

-- Packed elements use four bytes, not the eight-byte internal value ABI.
-- Offset views and signed loads must retain that distinction.
example : Storage.Slice.address (Storage.Slice.address 0x1000#64 3) 2 = 0x1014#64 := by decide
example : Lower.Slice.loadBytes = [0x8b, 0x80, 0, 0, 0, 0] := by decide
example : Lower.Slice.storeBytes = [0x41, 0x89, 0x83, 0, 0, 0, 0] := by decide
example (memory : Machine.Memory) :
    ¬ Storage.Slice.Represents memory 0xfffffffffffffffd#64 [0] := by
  intro stored
  have bound := stored.bounded
  contradiction
example (memory : Machine.Memory) (base : Machine.Address) :
    ¬ Storage.Slice.Represents memory base [2147483648] := by
  intro stored
  have signed := stored.signed 2147483648 (by simp)
  omega

example : Lower.Expression.Literal.Scalar32 2 0 ∧ Lower.Expression.Literal.Scalar32 2 1 := by
  simp [Lower.Expression.Literal.Scalar32]
example : ¬ Lower.Expression.Literal.Scalar32 2 2 := by simp [Lower.Expression.Literal.Scalar32]
example (program : Lanius.Core.Program) (value : Bool) :
    Transport.expression? program (.value (.boolean value)) = some [0, 2, if value then 1 else 0] := by
  simp [Transport.expression?, Transport.literal?]

-- CF/PF/AF/ZF/SF/OF, while preserving DF and the fixed reserved bit.
example : Machine.subtractFlags 0x402#64 0#64 1 = 0x497#64 := by decide
example : Machine.subtractFlags 0x402#64 7#64 7 = 0x446#64 := by decide
example : Machine.subtractFlags 0x402#64 0x8000000000000000#64 1 = 0xc16#64 := by decide

run_elab do
  let standard := #[``propext, ``Classical.choice, ``Quot.sound]
  for name in #[``Lanius.Semantics.wrapSigned_i32_neg_one,
      ``readBytes_wordBytes, ``wordBytes_injective, ``readWord_writeWord,
      ``writeWord_frame, ``relativeDisplacement_fits, ``relativeDisplacement_signed,
      ``nearTarget_relocated, ``patchedTarget, ``reservation_iff,
      ``wordBytes_core, ``wordBytes_sourceLane, ``wrap_relative, ``relative_evaluates,
      ``Buffer.fits_body, ``Buffer.fits_call, ``Buffer.writtenWord_frame,
      ``Buffer.writtenWord_lane, ``Buffer.writtenWord_bytes, ``Buffer.word_byte,
      ``Buffer.writtenWord_byteSlice, ``Buffer.writtenWord_target,
      ``Buffer.store_lane, ``Buffer.stores, ``Buffer.word_call,
      ``Buffer.patch_guard, ``Buffer.patch_reject, ``Buffer.patch_success, ``Buffer.patch_lands,
      ``Buffer.writtenBytes_frame, ``Buffer.writtenBytes_lane, ``Buffer.writtenBytes_slice,
      ``Buffer.writtenBytes_append,
      ``Buffer.writtenBytes_byteSlice, ``Buffer.fixed_store, ``Buffer.fixed_stores,
      ``Buffer.fixed_guard, ``Buffer.fixed_reject, ``Buffer.fixed_success,
      ``Control.Fixed.bytes_are_bytes, ``Control.Fixed.decode, ``Control.fixed_emits,
      ``Control.displacement?_i32Bytes, ``Control.decode_jump, ``Control.decode_call,
      ``Control.decode_branch, ``Control.Transfer.decode,
      ``Buffer.byteSlice_get, ``Buffer.Relative.selectSize, ``Buffer.Relative.guard,
      ``Buffer.Relative.rejects, ``Buffer.Relative.opcode, ``Buffer.Relative.condition,
      ``Buffer.Relative.write, ``Buffer.Relative.afterSize, ``Buffer.Relative.succeeds,
      ``Buffer.Relative.emittedValues_frame, ``Buffer.Relative.emittedValues_bytes,
      ``Buffer.Relative.emittedValues_decode, ``Buffer.Relative.emittedValues_target, ``Control.Transfer.emission,
      ``Control.direct_success, ``Control.direct_reject,
      ``Control.branch_guard, ``Control.branch_invalid, ``Control.branch_success, ``Control.branch_reject,
      ``Register.register_domain, ``Register.width_domain, ``Register.Rex.decode_encode,
      ``Register.Rex.encode_bounds, ``Register.initial_bounds, ``Register.fields_arithmetic,
      ``Register.value_bounds, ``Register.omitted_iff, ``Register.present_decodes,
      ``Register.validation_expression, ``Register.validation_call, ``Register.initial_evaluates,
      ``Register.selectWidth, ``Register.return_value, ``Register.rex_call,
      ``Encoding.Opcode.packed_bounds, ``Encoding.Opcode.packed_extended, ``Encoding.Opcode.packed_byte,
      ``Encoding.modRM_fields, ``Encoding.extend_register, ``Encoding.header_size, ``Encoding.bytes_size,
      ``Encoding.bytes_are_bytes, ``Encoding.size_bounds,
      ``Buffer.Locals.ofReads, ``Buffer.Locals.bind, ``Buffer.Locals.push, ``Buffer.Locals.frame,
      ``Buffer.Locals.empty, ``Buffer.Locals.fresh, ``Buffer.Locals.store,
      ``Buffer.count_prefix, ``Buffer.Cursor.read, ``Buffer.Cursor.distinct, ``Buffer.Cursor.index,
      ``Buffer.Cursor.store, ``Buffer.Cursor.increment, ``Buffer.Cursor.append,
      ``Buffer.Cursor.advance, ``Buffer.writtenHeaderWord_byteSlice, ``Encode.register_guard,
      ``Encode.Config.bytes_are_bytes, ``Encode.Config.emission,
      ``Encode.has_rex, ``Encode.has_escape, ``Encode.opcode_byte, ``Encode.modrm_byte,
      ``Encode.valid_guard, ``Encode.tail, ``Encode.write, ``Encode.after_size,
      ``Encode.select_size, ``Encode.sized, ``Encode.rex_value, ``Encode.after_guard, ``Encode.succeeds,
      ``Encode.invalid_guard, ``Encode.rejects_invalid, ``Encode.after_size_rejected,
      ``Encode.sized_rejected, ``Encode.after_guard_rejected, ``Encode.rejects_capacity,
      ``Encode.Direct.config_arguments, ``Encode.Direct.bound, ``Encode.Direct.arguments_evaluate,
      ``Encode.Direct.succeeds, ``Encode.Direct.rejects_capacity, ``Encode.Direct.rejects_invalid,
      ``Encode.Guarded.constant_guard, ``Encode.Guarded.Choice.byte, ``Encode.Guarded.Choice.digit,
      ``Encode.Guarded.config_arguments, ``Encode.Guarded.bound, ``Encode.Guarded.arguments_evaluate,
      ``Encode.Guarded.guard_evaluates, ``Encode.Guarded.succeeds, ``Encode.Guarded.rejects_operation,
      ``Encode.Guarded.rejects_capacity, ``Encode.Guarded.rejects_invalid,
      ``Encode.Indexed.valid_guard, ``Encode.Indexed.modrm_byte, ``Encode.Indexed.sib_byte,
      ``Encode.Indexed.stores, ``Encode.Indexed.write, ``Encode.Indexed.extend_rex, ``Encode.Indexed.after_rex,
      ``Encode.Indexed.succeeds, ``Encode.Indexed.rejects_capacity,
      ``Encode.Indexed.Config.emission, ``Encode.Indexed.Config.frame, ``Encode.Indexed.slice_address_emits,
      ``Encode.Memory.Config.size_bound, ``Encode.Memory.Config.header_size,
      ``Encode.Memory.has_rex, ``Encode.Memory.has_sib, ``Encode.Memory.modrm_byte,
      ``Encode.Memory.tail, ``Encode.Memory.write, ``Encode.Memory.after_size, ``Encode.Memory.select_size,
      ``Encode.Memory.sized, ``Encode.Memory.after_guard, ``Encode.Memory.succeeds,
      ``Encode.Memory.sized_rejects, ``Encode.Memory.after_guard_rejects, ``Encode.Memory.rejects_capacity,
      ``Encode.Memory.Config.emission, ``Encode.Memory.Config.frame, ``Encode.Memory.move_encoding,
      ``Encode.Memory.move_arguments, ``Encode.Memory.move_emits, ``Encode.Memory.move_rejects_capacity,
      ``Encode.Immediate.succeeds32, ``Encode.Immediate.rejects_capacity32,
      ``Encode.Immediate.emission, ``Encode.Immediate.frame, ``Encode.Immediate.decodes, ``Encode.Immediate.executes,
      ``Encode.Immediate.Wide.succeeds64, ``Encode.Immediate.Wide.rejects_capacity64,
      ``Encode.Immediate.Wide.emission, ``Encode.Immediate.Wide.frame,
      ``Encode.Immediate.Wide.written_length, ``Encode.Immediate.Wide.bytes_length,
      ``Encode.Immediate.Wide.window_writes, ``Encode.Immediate.Wide.Preservation.emits,
      ``Encode.Immediate.Wide.Preservation.from_transport,
      ``Machine.Immediate.word_toNat, ``Machine.Immediate.reads, ``Machine.Immediate.decodes,
      ``Machine.Immediate.executes, ``Machine.Immediate.fields, ``Machine.Immediate.preserves,
      ``Transport.literal_usize_iff, ``Transport.expression_usize_iff, ``Transport.usize_word,
      ``Transport.usize_serialized, ``Transport.usize_window,
      ``Lower.Value.Get.bytes_eq, ``Lower.Value.Get.bytes_length, ``Lower.Value.Get.inputs_not_array,
      ``Lower.Value.Get.kind_not_aggregate, ``Lower.Value.Get.bytes_memory,
      ``Lower.Value.Get.emit_rhs, ``Lower.Value.Get.tail, ``Lower.Value.Get.body, ``Lower.Value.Get.emits,
      ``Frame.Take.body_success, ``Frame.Take.succeeds,
      ``Frame.Take.Reject.guard, ``Frame.Take.Reject.body, ``Frame.Take.Reject.rejects,
      ``Frame.Take.Reject.retained_input, ``Frame.Take.Reject.frame,
      ``Frame.Lookup.Correct.extend, ``Frame.Lookup.Correct.unique, ``Frame.Lookup.positive,
      ``Frame.Lookup.key_matches, ``Frame.Lookup.loop, ``Frame.Lookup.body,
      ``Frame.Lookup.runs, ``Frame.Lookup.call, ``Frame.Lookup.body_nonpositive, ``Frame.Lookup.nonpositive,
      ``Lower.Expression.Literal.Layout.width32_body, ``Lower.Expression.Literal.Layout.width32,
      ``Lower.Expression.Literal.Layout.aggregate_body, ``Lower.Expression.Literal.Layout.aggregate,
      ``Lower.Expression.Literal.Layout.width64_body, ``Lower.Expression.Literal.Layout.width64,
      ``Lower.Expression.Literal.emit_body, ``Lower.Expression.Literal.emit_call,
      ``Lower.Expression.Wrapper.tail, ``Lower.Expression.Literal.compiles,
      ``Lower.Expression.Wrapper.body, ``Lower.Expression.Wrapper.call,
      ``Lower.Expression.Literal.Ready.enterCall, ``Lower.Expression.Wrapper.finish_eq,
      ``Lower.Expression.Context.Ready.memory, ``Lower.Expression.Context.Emits.refines, ``Lower.Expression.Local.Syntax.from_transport,
      ``Lanius.Separation.evaluatesFramedLocalUpdate,
      ``Lower.Expression.Raw.update_cursor,
      ``Lower.Expression.Raw.recurse_arguments, ``Lower.Expression.Raw.literal,
      ``Lower.Expression.Raw.pointer_local, ``Lower.Expression.Raw.emits_with_branch,
      ``Lower.Expression.Raw.Guard.test, ``Lower.Expression.Raw.Guard.branch,
      ``Lower.Expression.Raw.Guard.trap, ``Lower.Expression.Raw.Guard.move,
      ``Lower.Expression.Raw.Guard.finishes, ``Lower.Expression.Raw.tail, ``Lower.Expression.Raw.body,
      ``Lower.Expression.Raw.Native.constructs, ``Lower.Expression.Raw.Native.rejects_negative,
      ``Lower.Expression.Raw.afterRaw_length, ``Lower.Expression.Raw.afterRaw_top,
      ``Lower.Expression.Raw.emit_body, ``Lower.Expression.Raw.emit_call, ``Lower.Expression.Raw.compiles,
      ``Lower.Expression.Raw.Preservation.bytes_eq, ``Lower.Expression.Raw.Preservation.bytes_refines,
      ``Lower.Expression.Raw.Preservation.window_refines, ``Lower.Expression.Raw.Preservation.compiles,
      ``Machine.Slice.Raw.Expression.prepared_fields, ``Machine.Slice.Raw.Expression.prepares,
      ``Machine.Slice.Raw.Expression.prepares_heap, ``Machine.Slice.Raw.Expression.prepares_caller,
      ``Machine.Slice.Raw.Expression.prepares_slot,
      ``Transport.expression_raw_iff, ``Transport.raw_window,
      ``Lower.Expression.Local.pointer_bytes_refines,
      ``Lower.Expression.Local.Preservation.pointer_compiles, ``Lower.Expression.Local.Preservation.pointer_from_transport,
      ``Lower.Expression.Literal.bytes_refines, ``Lower.Expression.Literal.Preservation.compiles,
      ``Lower.Expression.Literal.Boolean.bytes_refines, ``Lower.Expression.Literal.Boolean.compiles,
      ``Lower.Expression.Literal.Boolean.from_transport, ``Lower.Expression.Literal.Boolean.rejects_capacity,
      ``Transport.literal_i32_iff, ``Transport.expression_i32_iff, ``Transport.i32_window,
      ``Lower.Expression.Literal.Preservation.from_transport,
      ``Lower.Expression.Indexed.Literal.literal_recurses, ``Lower.Expression.Indexed.Literal.body,
      ``Lower.Expression.Indexed.Literal.compiles, ``Lower.Expression.Indexed.Literal.operand,
      ``Lower.Expression.Indexed.Literal.window_refines,
      ``Lower.Expression.Indexed.Literal.Preservation.compiles, ``Lower.Expression.Indexed.Literal.Preservation.from_transport,
      ``Lower.Expression.Local.keeps_scalar, ``Lower.Expression.Local.lookup_after_input,
      ``Lower.Expression.Local.kind_read, ``Lower.Expression.Local.slot_read,
      ``Lower.Expression.Local.tail, ``Lower.Expression.Local.branch,
      ``Lower.Expression.Local.emit_body, ``Lower.Expression.Local.emit_call, ``Lower.Expression.Local.compiles,
      ``Lower.Expression.Local.bytes_refines,
      ``Lower.Expression.Local.Preservation.compiles, ``Lower.Expression.Local.Preservation.from_transport,
      ``Transport.local_id_iff, ``Transport.expression_local_iff, ``Transport.local_window,
      ``Lower.Expression.Local.Reject.branch, ``Lower.Expression.Local.Reject.emit_body,
      ``Lower.Expression.Local.Reject.emitter_rejects, ``Lower.Expression.Local.Reject.wrapper_rejects,
      ``Lower.Expression.Literal.Capacity.emit, ``Lower.Expression.Literal.Capacity.tail,
      ``Lower.Expression.Literal.Capacity.emit_body, ``Lower.Expression.Literal.Capacity.emit_call,
      ``Lower.Expression.Literal.Capacity.wrapper_body, ``Lower.Expression.Literal.Capacity.records_failure,
      ``Lanius.Separation.evaluatesFramedSliceStore, ``Lanius.Separation.evaluatesSliceStore,
      ``Frame.Slot.code_read, ``Frame.Slot.emit_rhs, ``Frame.Slot.body, ``Frame.Slot.emits,
      ``Frame.Allocate.Ready.field, ``Frame.Allocate.Ready.assign, ``Frame.Allocate.Ready.set,
      ``Frame.Allocate.guard, ``Frame.Allocate.updated_top, ``Frame.Allocate.updated_peak,
      ``Frame.Allocate.updated_length, ``Frame.Allocate.updated_frame,
      ``Frame.Allocate.body_success, ``Frame.Allocate.body_reject, ``Frame.Allocate.succeeds, ``Frame.Allocate.rejects,
      ``Lower.Expression.Indexed.workspaceAfter_top, ``Lower.Expression.Indexed.workspaceAfter_peak,
      ``Lower.Expression.Indexed.prepare, ``Lower.Expression.Indexed.captures,
      ``Lower.Expression.Indexed.Recursive.loaded, ``Lower.Expression.Indexed.Recursive.address,
      ``Lower.Expression.Indexed.executes, ``Lower.Expression.Indexed.window_refines,
      ``Lower.Expression.Indexed.Preservation.compiles,
      ``Lower.Expression.Indexed.continues, ``Lower.Expression.Indexed.body, ``Lower.Expression.Indexed.compiles,
      ``Lower.Expression.Indexed.Reject.body, ``Lower.Expression.Indexed.Reject.rejects,
      ``Lower.Expression.Indexed.Reject.continues,
      ``Lower.Expression.Indexed.Failure.body, ``Lower.Expression.Indexed.Failure.rejects,
      ``Buffer.byteSlice_congr, ``Buffer.byteSlice_append, ``Buffer.Emission.append,
      ``Control.Require.emission, ``Control.Require.decodes, ``Control.Require.executes,
      ``Control.Require.body, ``Control.Require.emits, ``Control.Require.below_bytes,
      ``Machine.CodeAt.prefix, ``Machine.CodeAt.suffix,
      ``Lower.Parameter.check?, ``Lower.Parameter.Checked.executes,
      ``Lower.Parameter.move_decodes, ``Lower.Parameter.machine_returns,
      ``Lower.Parameter.certify?, ``Lower.Parameter.Certified.preserves,
      ``Source.IntegerConstant.evaluates, ``Source.Table.executes, ``Source.Table.Checked.spec, ``Lower.Parameter.case_register,
      ``Lower.Parameter.argument_call, ``Lower.Parameter.code_encoding, ``Lower.Parameter.nonnegative_guard,
      ``Lower.Parameter.emit_return, ``Lower.Parameter.reserve_return, ``Lower.Parameter.choose_size,
      ``Lower.Parameter.mapped_return, ``Lower.Parameter.selected_return, ``Lower.Parameter.compile_selected,
      ``Lower.Parameter.compile_certified,
      ``Select.Input.word_field, ``Select.Input.return_tags, ``Select.Input.id_equal,
      ``Select.Loops.earlier_loop, ``Select.Loops.iteration, ``Select.Loops.loop, ``Select.Loops.scan,
      ``Select.Execution.command, ``Select.Frame.body_executes, ``Select.Frame.call,
      ``Lower.Parameter.Checked.selector_words, ``Lower.Parameter.select_entered,
      ``Lower.Parameter.compile_function, ``Lower.Parameter.compile_function_rejects_capacity,
      ``Lower.Parameter.compile_function_certified,
      ``Machine.read32_write32, ``Machine.write32_frame, ``Machine.read32_frame,
      ``Machine.CodeAt.write32, ``Machine.memory_decodes,
      ``Machine.offset_ne, ``Machine.read32_congr, ``Machine.read64_congr, ``Machine.read64_low,
      ``Machine.half_disjoint, ``Machine.read64_write64, ``Machine.write64_frame,
      ``Machine.CodeAt.write64, ``Machine.read64_frame, ``Machine.read64_write32_frame,
      ``Machine.arithmeticFlags_direction, ``Machine.subtractFlags_direction, ``Machine.Steps.trans,
      ``Machine.arithmeticFlags_carry, ``Machine.compare_below,
      ``Machine.ReadOnly.fields, ``Machine.ReadOnly.steps,
      ``Machine.Index.prepare_fields, ``Machine.Index.guard_decodes, ``Machine.Index.correct,
      ``Machine.Copy.word_fields, ``Machine.Copy.word_steps, ``Machine.Copy.correct,
      ``Storage.Stored.low, ``Storage.Stored.descriptor, ``Storage.copy_value,
      ``Storage.Slice.address_add, ``Storage.Slice.Represents.lane,
      ``Storage.Slice.Represents.disjoint, ``Storage.Slice.Represents.read,
      ``Storage.Slice.Represents.store, ``Storage.Slice.store_frame, ``Storage.Slice.Represents.frame,
      ``Lower.Slice.load_decodes, ``Lower.Slice.store_decodes,
      ``Lower.Slice.load_correct, ``Lower.Slice.store_correct, ``Lower.Slice.store_preserves_caller,
      ``Lower.Slice.index_core, ``Lower.Slice.index_refines,
      ``Lower.Slice.assign_core, ``Lower.Slice.assign_refines,
      ``Lower.Index.Value.normalized, ``Lower.Index.length_bound, ``Lower.Index.signed_word,
      ``Lower.Index.bounds, ``Lower.Index.accepted_index,
      ``Lower.Index.address_success, ``Lower.Index.address_rejects,
      ``Lower.Index.read_refines, ``Lower.Index.reject_core, ``Lower.Index.reject_refines,
      ``Lower.Index.Emission.Ready.afterOutput, ``Lower.Index.Emission.Ready.assign, ``Lower.Index.Emission.Ready.code,
      ``Lower.Index.Emission.call, ``Lower.Index.Emission.step, ``Lower.Index.Emission.load_slot,
      ``Lower.Index.Emission.finish, ``Lower.Index.Emission.tail, ``Lower.Index.Emission.normalize,
      ``Lower.Index.Emission.scope, ``Lower.Index.Emission.body, ``Lower.Index.Emission.emits,
      ``Lower.Index.Emission.window_refines, ``Lower.Index.Emission.compiles,
      ``Lower.Index.Reject.body, ``Lower.Index.Reject.rejects,
      ``Frame.Layout.block_saved_disjoint, ``Frame.BodyFrame.copy,
      ``Frame.Layout.word_lane, ``Frame.Layout.word_disjoint, ``Frame.Layout.saved_word_disjoint,
      ``Frame.BodyFrame.write64, ``Frame.BodyFrame.store64,
      ``Frame.bytes_aligned, ``Frame.bytes_room, ``Frame.Layout.bounds,
      ``Frame.Layout.displacement, ``Frame.Layout.separate, ``Frame.Layout.disjoint, ``Frame.Represents.store,
      ``Frame.displacement_evaluates, ``Frame.bytes_evaluates, ``Frame.displacement_call, ``Frame.bytes_call,
      ``Frame.displacement_signed, ``Frame.Layout.operand, ``Frame.slot_decodes,
      ``Frame.store_correct, ``Frame.load_correct, ``Frame.spill_reload,
      ``Frame.Layout.saved_disjoint, ``Frame.allocation_length, ``Frame.allocation_decodes,
      ``Frame.prologue_steps, ``Frame.setup_fields, ``Frame.setup_direction,
      ``Frame.epilogue_steps, ``Frame.teardown_fields, ``Frame.setup_frame,
      ``Frame.BodyFrame.write32, ``Frame.BodyFrame.store, ``Frame.Layout.setup, ``Frame.function_returns,
      ``Frame.return_emits,
      ``Lower.Parameter.negative_evaluates, ``Lower.Parameter.reserve_reject,
      ``Lower.Parameter.mapped_reject, ``Lower.Parameter.selected_reject,
      ``Lower.Parameter.compile_capacity_reject, ``Lower.Parameter.compile_selection_reject] do
    for assumption in ← Lean.collectAxioms name do
      unless standard.contains assumption do
        throwError "x86 theorem {name} adds unexpected axiom {assumption}"
  let sourceBaseline ← Lean.collectAxioms ``Lanius.Extraction.CoreSynthesis.Program.checkCompactCoreSourcePack
  let internalBaseline ← Lean.collectAxioms ``Lanius.Extraction.Source.checkInternal?
  for assumption in ← Lean.collectAxioms ``Source.checkBuffer do
    unless standard.contains assumption || sourceBaseline.contains assumption || internalBaseline.contains assumption do
      throwError "x86 source authentication adds unexpected axiom {assumption}"
  for assumption in ← Lean.collectAxioms ``Source.Lower.checkCompile? do
    unless standard.contains assumption || sourceBaseline.contains assumption || internalBaseline.contains assumption do
      throwError "Lanius lowering authentication adds unexpected axiom {assumption}"
  for assumption in ← Lean.collectAxioms ``Frame.checkReturn? do
    unless standard.contains assumption || sourceBaseline.contains assumption || internalBaseline.contains assumption do
      throwError "frame return authentication adds unexpected axiom {assumption}"
  for assumption in ← Lean.collectAxioms ``Source.Indexed.check? do
    unless standard.contains assumption || sourceBaseline.contains assumption || internalBaseline.contains assumption do
      throwError "indexed address source authentication adds unexpected axiom {assumption}"
  for name in [``Source.Memory.check?, ``Source.Memory.checkMove?, ``Source.Slot.check?, ``Source.Require.check?,
      ``Source.Index.check?, ``Source.Allocate.check?, ``Source.Expression.Indexed.check?,
      ``Source.Immediate.check?, ``Source.Take.check?, ``Source.Lookup.check?, ``Source.Value.Get.check?,
      ``Source.Expression.Literal.layout?, ``Source.Expression.Literal.check?, ``Source.Expression.Local.check?,
      ``Source.Expression.Raw.check?, ``Source.Address.check?, ``Source.Address.checkFrame?] do
    for assumption in ← Lean.collectAxioms name do
      unless standard.contains assumption || sourceBaseline.contains assumption || internalBaseline.contains assumption do
        throwError "source authentication {name} adds unexpected axiom {assumption}"
  Lean.logInfo "Audited x86 proofs use only standard axioms: 32/64-bit immediate source emission and machine execution, serialized usize preservation, closed signed/Boolean-literal, indexed-literal and initialized-local source/native compilation, missing-local rejection, recorded capacity failure, transport reads/rejection, reverse lexical lookup, scalar value loads, frame allocation/spill/reload, checked indexing, value copying, guards, slice writes and conditional function preservation. Source authentication adds no trust beyond its existing constituents."
