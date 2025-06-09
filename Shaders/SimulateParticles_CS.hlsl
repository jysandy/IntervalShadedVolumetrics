#include "TetrahedronPipeline.hlsli"

RWStructuredBuffer<InstanceData> Instances : register(u0, space0);

[numthreads(32, 1, 1)]
void SimulateParticles_CS(uint3 DTid : SV_DispatchThreadID)
{
    float3 worldPosition = Instances[DTid.x].WorldPosition;
    float3 targetPosition = mul(float4(Instances[DTid.x].TargetPosition, 1), g_TargetWorld)
        .xyz;
    
    float3 acceleration = 10.f * 
        normalize(targetPosition - worldPosition);
    
    float3 damping = -0.5f * Instances[DTid.x].Velocity;
    
    Instances[DTid.x].Velocity += (acceleration + damping) * g_DeltaTime;
    Instances[DTid.x].WorldPosition += Instances[DTid.x].Velocity * g_DeltaTime;
}