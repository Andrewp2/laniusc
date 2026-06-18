//! Helpers for decoding compact parser-owned HIR record words.

/// Invalid HIR record sentinel.
pub const INVALID: u32 = u32::MAX;
const NODE_ORDINAL_NODE_MASK: u32 = 0x0fff_ffff;
const NODE_ORDINAL_ORDINAL_SHIFT: u32 = 28;
const NODE_ORDINAL_ORDINAL_MASK: u32 = 0x0f;

/// Extracts the HIR node id from a packed node/ordinal record.
pub fn node_ordinal_node(record: u32) -> u32 {
    if record == INVALID {
        INVALID
    } else {
        record & NODE_ORDINAL_NODE_MASK
    }
}

/// Extracts the ordinal from a packed node/ordinal record.
pub fn node_ordinal_ordinal(record: u32) -> u32 {
    if record == INVALID {
        INVALID
    } else {
        (record >> NODE_ORDINAL_ORDINAL_SHIFT) & NODE_ORDINAL_ORDINAL_MASK
    }
}
