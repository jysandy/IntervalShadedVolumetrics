#include "TetrahedronPipeline.hlsli"
#include "Quaternion.hlsli"

RWStructuredBuffer<InstanceData> Instances : register(u0, space0);

float3 LineToPoint(float3 lineStart, float3 lineDirection, float3 p)
{
    float3 lineProjection = dot(lineStart - p, lineDirection) * lineDirection;

    float3 pointToLine = lineStart - p - lineProjection;
    return -pointToLine;
}

float3 GetLocalTargetPosition(uint3 DTid)
{
    float angularVelocity = 3.f + 100.f * frac(353435.22425 * DTid.x);
    float angle = angularVelocity * g_totalTime;
    
    Quaternion rotationQuat = QuatFromAxisAngle(float3(0, 1, 0), angle);
    float3 targetPosition = mul(Instances[DTid.x].TargetPosition, QuatTo3x3(rotationQuat)) 
        * (1 + 3.xxx * sin(3 * g_totalTime + DTid.x));
    
    return targetPosition;
}

[numthreads(32, 1, 1)]
void SimulateParticles_CS(uint3 DTid : SV_DispatchThreadID)
{
    float3 worldPosition = Instances[DTid.x].WorldPosition;
    
    float3 targetPosition = mul(float4(GetLocalTargetPosition(DTid), 1), g_TargetWorld)
        .xyz;
    
    float3 attractionVector = targetPosition - worldPosition;
    
    // Like gravity, this is independent of mass
    float3 attractionAcceleration = 150.f * 
        normalize(targetPosition - worldPosition);
    
    if (length(attractionVector) < 0.0001)
    {
        attractionAcceleration = 0.xxx;
    }
    
    // This is not independent of mass
    float3 dampingForce = -4.f * Instances[DTid.x].Velocity;
    
    
    float3 l2p = LineToPoint(g_ShootRayStart,
        normalize(g_ShootRayEnd - g_ShootRayStart),
        worldPosition);
    
    float lineDistance = length(l2p);
    
    float3 bulletScatterVelocity 
        = g_DidShoot * 10 * normalize(l2p) / pow(lineDistance, 2);
    
    
    float3 dampingVelocityChange = (dampingForce / Instances[DTid.x].Mass) * g_DeltaTime;
    
    if (length(dampingVelocityChange) < length(Instances[DTid.x].Velocity))
    {
        Instances[DTid.x].Velocity += dampingVelocityChange;
    }
    else
    {
        Instances[DTid.x].Velocity = 0.xxx;
    }
    
    Instances[DTid.x].Velocity += attractionAcceleration * g_DeltaTime + bulletScatterVelocity;    
    Instances[DTid.x].WorldPosition += Instances[DTid.x].Velocity * g_DeltaTime;
}