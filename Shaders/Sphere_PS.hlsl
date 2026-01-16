#include "SphereConstants.hlsli"
#include "SpherePipeline.hlsli"
#include "ShadowMapping.hlsli"

Texture3D<float> VolumetricShadowMap : register(t2, space0);
Texture2D ShadowMap : register(t3, space0);

SamplerState LinearSampler : register(s0, space0);
SamplerComparisonState ShadowMapSampler : register(s1, space0);

struct BlendOutput
{
    float4 Color : SV_Target0;
    float Depth : SV_Depth;
};

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
    float3 uvw = transformed.xyz;
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

void ComputeSimpsonEquation(out float3 Cscat, out float Tv,
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
    
    float ot = FadedOpticalThickness(Zmin, Zmax, d, cosAlpha, extinction, falloffRadius);
    
    if (ot > MIN_OT)
    {
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
    else
    {
        Tv = 1;
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
    
    if (!hit || tFar < 0)
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
    
    float3 Cscat = 0.xxx;
    float Tv = 1;
    
    ComputeSimpsonEquation(Cscat, Tv, minpoint, maxpoint, input.SphereCenter, extinction, input.SphereRadius);
    
    ret.Color = float4(Cscat, Tv);
    
    return ret;
}
