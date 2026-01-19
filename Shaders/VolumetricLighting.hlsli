#ifndef __VOLUMETRIC_LIGHTING_HLSLI__
#define __VOLUMETRIC_LIGHTING_HLSLI__

#include "RenderingEquation.hlsli"
#include "ShadowMapping.hlsli"
#include "CommonPipeline.hlsli"

Texture3D<float> VolumetricShadowMap : register(t2, space0);
Texture2D ShadowMap : register(t3, space0);

SamplerState LinearSampler : register(s0, space0);
SamplerComparisonState ShadowMapSampler : register(s1, space0);

static const float MIN_OT = 0.001f;

float HGPhase(float3 L, float3 V, float asymmetry)
{
    float constant = 1.f / (4 * PI);
    float g = asymmetry;
    float numerator = 1 - g * g;
    float cosTheta = clamp(dot(L, V), -1.f, 1.f);
    float denominator = pow(1 + g * g + 2 * g * cosTheta, 1.5);
    return constant * numerator / denominator;
}

float WeightedPhase(float3 L, float3 V, float asymmetry, float directionality)
{
    float constant = 1.f / (4 * PI);
    float hg = HGPhase(L, V, asymmetry);
    return lerp(constant, hg, directionality);
}

float ReflectivePhase(float3 L, float3 V, float3 N, float asymmetry, float directionality)
{
    float constant = 1.f / (4 * PI);
    float hg = HGPhase(L, V, asymmetry);
    float3 r = normalize(reflect(-L, N));
    float hg2 = 0;
    
    if (dot(L, N) > 0)
    {
        hg2 = lerp(hg, HGPhase(r, V, -abs(asymmetry)), g_Reflectivity);
    }
    else
    {
        hg2 = hg;
    }
    
    return lerp(constant, hg2, directionality);
}

float SampleOpticalThickness(float3 worldPosition)
{
    float4 transformed = mul(float4(worldPosition, 1), g_VolumetricShadowTransform);
    transformed /= transformed.w;
    #ifdef INVERT_SHADOW_MAP
    float3 uvw = 1 - transformed.xyz;
    #else
    float3 uvw = transformed.xyz;
    #endif
    return VolumetricShadowMap.Sample(LinearSampler, uvw);
}


float FadedTransmittance(
    float Zmin,
    float Zmax,
    float d,
    float cosAlpha,
    float extinction,
    float falloffRadius
)
{
    return FadedTransmittanceTv2(Zmin, Zmax, d, cosAlpha, extinction, falloffRadius);
}

float Visibility(float3 worldPosition)
{
    if (g_SoftShadows)
    {
        return calculateShadowFactor(ShadowMap, ShadowMapSampler, g_ShadowTransform, worldPosition);        
    }
    else
    {   
        return calculateShadowFactorNoLargeKernel(ShadowMap, ShadowMapSampler, g_ShadowTransform, worldPosition);
    }
}

float IntegrateSimpsonTransmittance(
    float3 minpoint,
    float3 maxpoint,
    float Zmin,
    float Zmax,
    float3 centrePos,
    float extinction,
    float falloffRadius,
    float3 V
)
{
    float integral = 0;
    float stepSize = (Zmax - Zmin) / (float) g_StepCount;
    float fmin = 0;
    float Omin = 0;
    
    for (int i = 0; i < g_StepCount; i++)
    {
        float3 start = minpoint + i * stepSize * (-V);
        float3 end = minpoint + (i + 1) * stepSize * (-V);
        
        float minZ = Zmin + i * stepSize;
        float maxZ = Zmin + (i + 1) * stepSize;
        
        float3 toCentre = normalize(centrePos - start);
        float d = length(centrePos - start);
        float cosAlpha = clamp(dot(-V, toCentre), -1, 1);
        
        float Omax = SampleOpticalThickness(end);
        if (i == 0)
        {
            Omin = SampleOpticalThickness(start);
            fmin = f(minZ, minZ, maxZ, Omin, Omax, d, cosAlpha, extinction, falloffRadius, Visibility(start));
        }
        
        float fmax = f(maxZ, minZ, maxZ, Omin, Omax, d, cosAlpha, extinction, falloffRadius, Visibility(end));
        
        integral += ((maxZ - minZ) / 6.f) * (fmin
                                             + 4 * f((minZ + maxZ) / 2.f, minZ, maxZ, Omin, Omax, d, cosAlpha, extinction, falloffRadius, Visibility((start + end) / 2.f))
                                             + fmax);
        Omin = Omax;
        fmin = fmax;
    }

    return integral;
}

float3 SimpsonScatteredLight(
    float3 albedo,
    float3 irradiance,
    float3 L,
    float3 V,
    float asymmetry,
    float3 minpoint,
    float3 maxpoint,
    float Zmin,
    float Zmax,
    float3 centrePos,
    float extinction,
    float falloffRadius,
    float d, 
    float cosAlpha
)
{
    float3 N = normalize(minpoint - centrePos);
    float phase = ReflectivePhase(L, V, N, asymmetry, g_Anisotropy);
    float transmissionFactor = IntegrateSimpsonTransmittance(minpoint, maxpoint, Zmin, Zmax, centrePos, extinction, falloffRadius, V);
    float fadedExtinction = Sigma_t(Zmin, (Zmin + Zmax) / 2.f, d, cosAlpha, extinction, falloffRadius);
    
    return albedo * phase * irradiance * transmissionFactor
        + (fadedExtinction / extinction) * g_Albedo * irradiance * phase * 0.001 * g_MultiScatteringFactor;
}

#endif
