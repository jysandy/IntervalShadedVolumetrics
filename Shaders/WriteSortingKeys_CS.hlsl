#include "TetrahedronPipeline.hlsli"

RWStructuredBuffer<float> g_outKeys : register(u0, space0);
RWStructuredBuffer<uint> g_outIndices : register(u1, space0);

[numthreads(1, 1, 1)]
void WriteSortingKeys_CS( uint3 DTid : SV_DispatchThreadID )
{
    float3 worldPosition = Instances[DTid.x].WorldPosition;
    float3 viewPosition = mul(float4(worldPosition, 1), view).xyz;

    g_outIndices[DTid.x] = DTid.x;    
    // Works as long as the camera is looking down +ve Z
    // FFX seems to ignore the sign of floats, so we have to subtract 
    // from a large number to sort in the right order
    g_outKeys[DTid.x] = 10000 - viewPosition.z;
}