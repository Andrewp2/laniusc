// Parameters of one heap-tree build dispatch (heap_levels.slang): the level it
// reads (start_node, node_count; mode 0 reads the leaves) and how many levels
// it builds above it. make_heap_build_steps in parser/buffers/scans.rs writes
// them.
struct HeapTreeParams
{
    uint n_blocks;
    uint leaf_base;
    uint start_node;
    uint node_count;
    uint mode;
    uint levels;
    uint _pad1;
    uint _pad2;
};

