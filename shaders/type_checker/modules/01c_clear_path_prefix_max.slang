// Clears the GPU-produced maximum path depth before path counting.

RWStructuredBuffer<uint> path_max_segment_count;

[shader("compute")]
[numthreads(1, 1, 1)]
void main()
{
    path_max_segment_count[0u] = 0u;
}
