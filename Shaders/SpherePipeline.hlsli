#ifndef __SPHERE_PIPELINE_HLSLI__
#define __SPHERE_PIPELINE_HLSLI__

#include "Utils.hlsli"

struct SphereVertexType
{
    float4 Position : SV_Position;
    nointerpolation float3 SphereCenter : SPHERE_CENTER;
    nointerpolation float SphereRadius : SPHERE_RADIUS;
    nointerpolation float ExtinctionScale : EXTINCTION;
};

bool RaySphereIntersect(
    float3 rayOrigin, 
    float3 rayDir, 
    float3 sphereCenter, 
    float sphereRadius,
    out float tNear,
    out float tFar)
{
    float3 L = rayOrigin - sphereCenter;
    float a = dot(rayDir, rayDir);
    float b = 2.0 * dot(rayDir, L);
    float c = dot(L, L) - sphereRadius * sphereRadius;
    
    float discriminant = b * b - 4.0 * a * c;
    
    if (discriminant < 0.0)
    {
        tNear = -1.0;
        tFar = -1.0;
        return false;
    }
    
    float sqrtDisc = sqrt(discriminant);
    tNear = (-b - sqrtDisc) / (2.0 * a);
    tFar = (-b + sqrtDisc) / (2.0 * a);
    
    return true;
}

#endif
