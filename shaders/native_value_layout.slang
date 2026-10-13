// Native descriptor layout. Components occupy descending eight-byte words.
// A slice carries its backing stride independently of its checked element type.
public static const uint NATIVE_SLICE_WORDS = 3u;
public static const uint NATIVE_SLICE_DATA = 0u;
public static const uint NATIVE_SLICE_LENGTH = 1u;
public static const uint NATIVE_SLICE_STRIDE = 2u;
