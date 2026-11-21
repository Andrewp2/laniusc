import codegen.lir.lowering_ir;
import shared.collectives.step_program;

struct Params { uint capacity; };
struct Launch { uint groups; uint slot; uint options; uint reserved; };

ConstantBuffer<Params> gParams;
ConstantBuffer<Launch> program_launch;
StructuredBuffer<uint> target_lir_total;
StructuredBuffer<TargetScheduleKey> target_schedule_key;
RWStructuredBuffer<uint> target_schedule_order;
RWStructuredBuffer<uint> target_schedule_temporary;

static const uint TILE_ROWS = STEP_PROGRAM_GROUP_LANES;
groupshared uint4 tile_entries_a[TILE_ROWS];
groupshared uint4 tile_entries_b[TILE_ROWS];

uint4 schedule_entry(uint row)
{
    TargetScheduleKey key = target_schedule_key[row];
    return uint4(row, key.word0, key.word1, key.word2);
}

// Compare the packed key most significant word first. Including the source
// row makes each rank unique and preserves order among equal keys.
bool precedes(uint4 a, uint4 b)
{
    if (a.w != b.w) return a.w < b.w;
    if (a.z != b.z) return a.z < b.z;
    if (a.y != b.y) return a.y < b.y;
    return a.x < b.x;
}

uint source_row(uint position, bool source_is_order)
{
    return source_is_order ? target_schedule_order[position] : target_schedule_temporary[position];
}

void store_row(uint position, uint row, bool destination_is_order)
{
    if (destination_is_order) target_schedule_order[position] = row;
    else target_schedule_temporary[position] = row;
}

void sort_tile(uint first, uint count, uint lane, bool destination_is_order)
{
    if (lane < count) tile_entries_a[lane] = schedule_entry(first + lane);
    GroupMemoryBarrierWithGroupSync();

    // Each lane knows its rank inside its run. A binary search adds the
    // number of earlier entries from the other run in the pair.
    bool source_is_a = true;
    for (uint width = 1u; width < count; width *= 2u)
    {
        if (lane < count)
        {
            uint own = lane & ~(width - 1u);
            uint other = own ^ width;
            uint lo = min(other, count);
            uint hi = min(other + width, count);
            uint4 entry = source_is_a ? tile_entries_a[lane] : tile_entries_b[lane];
            while (lo < hi)
            {
                uint mid = lo + (hi - lo) / 2u;
                uint4 peer = source_is_a ? tile_entries_a[mid] : tile_entries_b[mid];
                if (precedes(peer, entry)) lo = mid + 1u;
                else hi = mid;
            }
            uint rank = (own & ~width) + lane - own + lo - min(other, count);
            if (source_is_a) tile_entries_b[rank] = entry;
            else tile_entries_a[rank] = entry;
        }
        GroupMemoryBarrierWithGroupSync();
        source_is_a = !source_is_a;
    }

    if (lane < count)
    {
        uint4 entry = source_is_a ? tile_entries_a[lane] : tile_entries_b[lane];
        store_row(first + lane, entry.x, destination_is_order);
    }
    GroupMemoryBarrierWithGroupSync();
}

void merge_row(uint position, uint count, uint width, bool source_is_order)
{
    uint row = source_row(position, source_is_order);
    uint own = position & ~(width - 1u);
    uint other = own ^ width;
    uint start = min(other, count);
    uint lo = start;
    uint hi = min(other + width, count);
    if (lo < hi)
    {
        uint4 entry = schedule_entry(row);
        // Runs often stay in source order across a tile boundary. Compare
        // their endpoints before searching within either run.
        if (precedes(schedule_entry(source_row(hi - 1u, source_is_order)), entry))
            lo = hi;
        else if (precedes(schedule_entry(source_row(lo, source_is_order)), entry))
        {
            lo += 1u;
            hi -= 1u;
            while (lo < hi)
            {
                uint mid = lo + (hi - lo) / 2u;
                uint4 peer = schedule_entry(source_row(mid, source_is_order));
                if (precedes(peer, entry)) lo = mid + 1u;
                else hi = mid;
            }
        }
    }
    store_row((own & ~width) + position - own + lo - start, row, !source_is_order);
}

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    uint rows = min(gParams.capacity, target_lir_total[0u]);
    uint merges = rows > TILE_ROWS ? uint(firstbithigh((rows - 1u) / TILE_ROWS)) + 1u : 0u;
    // Choose the initial destination so the final order needs no copy.
    bool source_is_order = (merges & 1u) == 0u;
    for (uint first = group.x * TILE_ROWS; first < rows; first += program.lanes)
        sort_tile(first, min(rows - first, TILE_ROWS), local.x, source_is_order);

    uint width = TILE_ROWS;
    for (uint merge = 0u; merge < merges; ++merge, width *= 2u)
    {
        if (!step_barrier(program)) return;
        for (uint position = program.lane; position < rows; position += program.lanes)
            merge_row(position, rows, width, source_is_order);
        source_is_order = !source_is_order;
    }
    step_program_end(program);
}
