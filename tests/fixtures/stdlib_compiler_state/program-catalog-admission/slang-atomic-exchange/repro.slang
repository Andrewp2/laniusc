RWStructuredBuffer<uint> values;
[shader("compute")]
[numthreads(1,1,1)]
void main(uint3 tid : SV_DispatchThreadID) {
 uint old;
 InterlockedExchange(values[0], tid.x, old);
 values[tid.x+1] = old;
}
