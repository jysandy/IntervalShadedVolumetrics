#include "SphereConstants.hlsli"
#include "SpherePipeline.hlsli"

float VanillaOpticalThickness(
    float3 minpoint,
    float3 maxpoint,
    float extinction
)
{
    return length(minpoint - maxpoint) * extinction;
}

float FadedOpticalThicknessForShadow(
    float3 minpoint,
    float3 maxpoint,
    float extinction,
    float3 centrePos,
    float falloffRadius)
{
    float Zmin = 0;
    float Zmax = length(maxpoint - minpoint);
    
    float3 V = normalize(maxpoint - minpoint);
    float3 toCentre = normalize(centrePos - minpoint);
    float d = length(centrePos - minpoint);
    float cosAlpha = clamp(dot(V, toCentre), -1, 1);
    
    return FadedOpticalThickness(Zmin, Zmax, d, cosAlpha, extinction, falloffRadius);
}

float VolShadowSphere_PS(SphereVertexType input) : SV_Target
{
    float2 screenSize = float2(g_RenderTargetWidth, g_RenderTargetHeight);
    float2 ndc;
    ndc.x = (input.Position.x / screenSize.x) * 2.0 - 1.0;
    ndc.y = 1.0 - (input.Position.y / screenSize.y) * 2.0;
    
    float4 nearPoint = mul(float4(ndc, 0.0, 1.0), g_InverseViewProj);
    float4 farPoint = mul(float4(ndc, 1.0, 1.0), g_InverseViewProj);
    nearPoint /= nearPoint.w;
    farPoint /= farPoint.w;
    
    float3 rayOrigin = nearPoint.xyz;
    float3 rayDir = normalize(farPoint.xyz - nearPoint.xyz);
    
    float tNear, tFar;
    bool hit = RaySphereIntersect(rayOrigin, rayDir, input.SphereCenter, input.SphereRadius, tNear, tFar);
    
    if (!hit || tFar < 0)
    {
        return 0;
    }
    
    tNear = max(tNear, 0);
    
    float3 minpoint = rayOrigin + rayDir * tNear;
    float3 maxpoint = rayOrigin + rayDir * tFar;
    
    float extinction = input.ExtinctionScale * g_Extinction * EXTINCTION_SCALE;
    extinction = max(EPSILON, extinction);
    
    float tau = 0;
    
    [branch]
    if (g_RenderingMethod == 0)
    {
        tau = VanillaOpticalThickness(minpoint, maxpoint, extinction);
    }
    else
    {
        tau = FadedOpticalThicknessForShadow(
                    minpoint,
                    maxpoint,
                    extinction,
                    input.SphereCenter,
                    g_ExtinctionFalloffRadius * input.SphereRadius);
    }
    
    return tau;
}
