#include "TetrahedronPipeline.hlsli"

RWStructuredBuffer<InstanceData> Instances : register(u0, space0);

[numthreads(32, 1, 1)]
void SimulateParticles_CS(uint3 DTid : SV_DispatchThreadID)
{
    float3 worldPosition = Instances[DTid.x].WorldPosition;
    
    float damping = 0.1f; // per second
    float3 acceleration = 4.f * 
        normalize(Instances[DTid.x].TargetPosition - worldPosition);
    
    
    Instances[DTid.x].Velocity += acceleration * g_DeltaTime;
    Instances[DTid.x].Velocity *= (1 - damping * g_DeltaTime);
    Instances[DTid.x].WorldPosition += Instances[DTid.x].Velocity * g_DeltaTime;
}