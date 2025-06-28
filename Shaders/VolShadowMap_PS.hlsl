#include "TetrahedronPipeline.hlsli"
#include "Utils.hlsli"


float OpticalThickness(
    float3 minpoint,
    float3 maxpoint,
    float extinction,
    float3 centrePos,
    float falloffRadius)
{
    // Goofy but it works
    float Zmin = 0;
    float Zmax = length(maxpoint - minpoint);
    
    float3 V = normalize(maxpoint - minpoint);
    float3 toCentre = normalize(centrePos - minpoint);
    float d = length(centrePos - minpoint);
    float cosAlpha = clamp(dot(V, toCentre), -1, 1);
    
    return FadedOpticalThickness(Zmin, Zmax, d, cosAlpha, extinction, falloffRadius);
}

float VolShadowMap_PS(VertexType input) : SV_Target
{
    float4 maxpoint = float4(input.A.xy, input.A.z, 1.0);
    float4 minpoint = float4(input.A.xy, input.A.w, 1.0);
    
    float4 a = mul(minpoint, g_InverseViewProj);
    float4 b = mul(maxpoint, g_InverseViewProj);
    a = a / a.w;
    b = b / b.w;

    float extinction = input.ExtinctionScale * g_Extinction / 100.f;
    extinction = max(EPSILON, extinction);
    
    float tau = OpticalThickness(a.xyz,
                    b.xyz,
                    extinction,
                    input.WorldPosition,
                    g_ExtinctionFalloffRadius);
    
    return tau;
}