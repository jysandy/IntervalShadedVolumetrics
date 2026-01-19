#include "CommonPipeline.hlsli"
#include "SpherePipeline.hlsli"
#include "VolumetricLighting.hlsli"

struct BlendOutput
{
    float4 Color : SV_Target0;
    float Depth : SV_Depth;
};

void ComputeSphereSimpsonEquation(out float3 Cscat, out float Tv,
    float3 minpoint,
    float3 maxpoint,
    float3 centrePos,
    float extinction,
    float scale
)
{
    Cscat = 0.xxx;
    Tv = 1;
    
    float Zmin = length(g_CameraPosition - minpoint);
    float Zmax = length(g_CameraPosition - maxpoint);
    
    if (abs(Zmin - Zmax) < EPSILON)
    {
        return;
    }
    
    float3 V = normalize(g_CameraPosition - minpoint);
    float3 toCentre = normalize(centrePos - minpoint);
    float d = length(centrePos - minpoint);
    float cosAlpha = clamp(dot(-V, toCentre), -1, 1);
    float falloffRadius = g_ExtinctionFalloffRadius * scale;
    
    Tv = FadedTransmittance(Zmin, Zmax, d, cosAlpha, extinction, falloffRadius);
    
    float3 L = -g_LightDirection;
    float3 R = g_LightBrightness * g_LightColor;
    
    Cscat = SimpsonScatteredLight(
                g_Albedo, R, L, V, g_ScatteringAsymmetry,
                minpoint, maxpoint, Zmin, Zmax, centrePos,
                extinction, falloffRadius, d, cosAlpha);
    
    if (any(isnan(Cscat)))
    {
        Cscat = 0.xxx;
    }
}

BlendOutput Sphere_PS(SphereVertexType input)
{
    float3 rayOrigin = g_CameraPosition;
    
    float2 screenSize = float2(g_RenderTargetWidth, g_RenderTargetHeight);
    float2 ndc;
    ndc.x = (input.Position.x / screenSize.x) * 2.0 - 1.0;
    ndc.y = 1.0 - (input.Position.y / screenSize.y) * 2.0;
    
    float4 farPoint = mul(float4(ndc, 1.0, 1.0), g_InverseViewProj);
    farPoint /= farPoint.w;
    
    float3 rayDir = normalize(farPoint.xyz - rayOrigin);
    
    float tNear, tFar;
    bool hit = RaySphereIntersect(rayOrigin, rayDir, input.SphereCenter, input.SphereRadius, tNear, tFar);
    
    BlendOutput ret;
    
    float3 Cscat = 0.xxx;
    float Tv = 1;
    
    // Wasted pixels mode, sphere not hit
    if ((!hit || tFar < 0) && g_RenderingMethod == 5)
    {
        float4 clipPos = mul(float4(input.SphereCenter, 1), view);
        clipPos = mul(clipPos, persp);
        ret.Depth = clipPos.z / clipPos.w;
        
        ret.Color = float4(1, 0, 0, 0);
        return ret;
    }
    // Wasted pixels mode, sphere hit
    else if (g_RenderingMethod == 5)
    {
        float4 clipPos = mul(float4(input.SphereCenter, 1), view);
        clipPos = mul(clipPos, persp);
        ret.Depth = clipPos.z / clipPos.w;
        
        ret.Color = float4(0, 1, 0, 0);
        return ret;
    }
    else if ((!hit || tFar < 0) && g_RenderingMethod == 4)
    {
        discard;
    }
    
    tNear = max(tNear, 0);
    
    float3 minpoint = rayOrigin + rayDir * tNear;
    float3 maxpoint = rayOrigin + rayDir * tFar;
    
    // Compute depth
    {
        float4 clipPos = mul(float4(minpoint, 1), view);
        clipPos = mul(clipPos, persp);
        ret.Depth = clipPos.z / clipPos.w;
    }
    
    float extinction = input.ExtinctionScale * g_Extinction * EXTINCTION_SCALE;
    extinction = max(EPSILON, extinction);
    
    ComputeSphereSimpsonEquation(Cscat, Tv, minpoint, maxpoint, input.SphereCenter, extinction, input.SphereRadius);
    
    
    ret.Color = float4(Cscat, Tv);
    
    return ret;
}
