// The generic declaration producer owns lexical constant slots. Every
// immutable graph and callable consumer reads this single storage binding;
// writable construction remains in its producing passes.
public StructuredBuffer<uint> type_const_param_slot_by_token;

// Declared scalar belongs to the exact constant parameter declaration.
// It is contract metadata, never a replacement for owner/domain identity.
public StructuredBuffer<uint> type_const_param_scalar_by_token;
