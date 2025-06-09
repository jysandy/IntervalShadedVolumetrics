#include "TetrahedronPipeline.hlsli"

RWStructuredBuffer<InstanceData> Instances : register(u0, space0);

[numthreads(32, 1, 1)]
void SimulateParticles_CS(uint3 DTid : SV_DispatchThreadID)
{
    float3 velocity = float3(0.8, 0, 0);
    
    float3 worldPosition = Instances[DTid.x].WorldPosition;
    worldPosition += velocity * g_DeltaTime;
    
    Instances[DTid.x].WorldPosition = worldPosition;
}