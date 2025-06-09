#include "TetrahedronPipeline.hlsli"

RWStructuredBuffer<InstanceData> Instances : register(u0, space0);

[numthreads(32, 1, 1)]
void SimulateParticles_CS(uint3 DTid : SV_DispatchThreadID)
{
    float3 worldPosition = Instances[DTid.x].WorldPosition;
    float3 targetPosition = mul(float4(Instances[DTid.x].TargetPosition, 1), g_TargetWorld)
        .xyz;
    
    // Like gravity, this is independent of mass
    float3 attractionAcceleration = 50.f * 
        normalize(targetPosition - worldPosition);
    
    // This is not independent of mass
    float3 dampingForce = -0.1f * Instances[DTid.x].Velocity;
    
    float3 acceleration 
        = attractionAcceleration + (dampingForce / Instances[DTid.x].Mass);
    
    Instances[DTid.x].Velocity += acceleration * g_DeltaTime;
    Instances[DTid.x].WorldPosition += Instances[DTid.x].Velocity * g_DeltaTime;
}