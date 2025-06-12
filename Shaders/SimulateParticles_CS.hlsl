#include "TetrahedronPipeline.hlsli"

RWStructuredBuffer<InstanceData> Instances : register(u0, space0);

float3 LineToPoint(float3 lineStart, float3 lineDirection, float3 p)
{
    float3 lineProjection = dot(lineStart - p, lineDirection) * lineDirection;

    float3 pointToLine = lineStart - p - lineProjection;
    return -pointToLine;
}

[numthreads(32, 1, 1)]
void SimulateParticles_CS(uint3 DTid : SV_DispatchThreadID)
{
    float3 worldPosition = Instances[DTid.x].WorldPosition;
    float3 targetPosition = mul(float4(Instances[DTid.x].TargetPosition, 1), g_TargetWorld)
        .xyz;
    
    float3 velocityDirection = targetPosition - worldPosition;
    
    // Like gravity, this is independent of mass
    float3 attractionAcceleration = 50.f * 
        normalize(targetPosition - worldPosition);
    
    if (length(velocityDirection) == 0)
    {
        attractionAcceleration = 0.xxx;
    }
    
    // This is not independent of mass
    float3 dampingForce = -0.4f * Instances[DTid.x].Velocity;
    
    float3 acceleration 
        = attractionAcceleration + (dampingForce / Instances[DTid.x].Mass);
    
    float3 l2p = LineToPoint(g_ShootRayStart,
        normalize(g_ShootRayEnd - g_ShootRayStart),
        worldPosition);
    
    float lineDistance = length(l2p);
    
    float3 bulletScatterVelocity 
        = g_DidShoot * 0.5 * normalize(l2p) / pow(lineDistance, 2);
    
    Instances[DTid.x].Velocity += acceleration * g_DeltaTime + bulletScatterVelocity;
    Instances[DTid.x].WorldPosition += Instances[DTid.x].Velocity * g_DeltaTime;
}