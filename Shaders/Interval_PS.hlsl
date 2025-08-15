#include "Utils.hlsli"
#include "TetrahedronPipeline.hlsli"
#include "RenderingEquation.hlsli"
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

// The Henyey-Greenstein phase function             
// TODO: Should this be wavelength dependent?
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
    
    uvw.xy = 1 - uvw.xy; // why is this necessary?
    
    // Z should already be linear since the projection is orthographic
    return VolumetricShadowMap.Sample(LinearSampler, uvw);
}

float VanillaTransmittance(float extinction, float opticalDepth)
{
    return exp(-extinction * opticalDepth);
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

float IntegrateVanillaTransmittance(
    float3 minpoint,
    float3 maxpoint,
    float extinction,
    float3 centrePos
)
{
    float Zmin = length(g_CameraPosition - minpoint);
    float Zmax = length(g_CameraPosition - maxpoint);
    
    float Omin = SampleOpticalThickness(minpoint);
    float Omax = SampleOpticalThickness(maxpoint);
    
    float denominator = ZeroCutoff(Omax - Omin + extinction * (Zmax - Zmin), EPSILON);
    
    float firstExponent = extinction * Zmax + Omax;
    float secondExponent = extinction * Zmin + Omin;
    float thirdExponent = -extinction * Zmax - Omax - Omin;
    
    float numerator
        = extinction * (Zmin - Zmax) * (exp(firstExponent) - exp(secondExponent)) * exp(thirdExponent);
    
    // Output must be non-negative
    denominator = MatchSign(denominator, numerator);
    
    return numerator / denominator;
}

float3 VanillaScatteredLight(
    float3 minpoint,
    float3 maxpoint,
    float extinction,
    float3 centrePos,
    float3 albedo,
    float3 irradiance,
    float3 L,
    float3 V
)
{
    float phase = WeightedPhase(L, V, g_ScatteringAsymmetry, g_Anisotropy);
    
    float transmissionFactor = IntegrateVanillaTransmittance(minpoint, maxpoint, extinction, centrePos);

    return albedo * phase * irradiance * 1 * transmissionFactor;
}

float IntegrateTaylorTransmittance(
    float3 minpoint,
    float3 maxpoint,
    float Zmin,
    float Zmax,
    float d,
    float cosAlpha,
    float extinction,
    float falloffRadius
)
{
    float Omin = SampleOpticalThickness(minpoint);
    float Omax = SampleOpticalThickness(maxpoint);
    
    return max(0, IntegrateTaylorSeries(
        4,
        Zmin,
        Zmax,
        Omin,
        Omax,
        d,
        cosAlpha,
        extinction,
        falloffRadius));
}

float Visibility(float3 worldPosition)
{
    if (g_SoftShadows)
    {
        return calculateShadowFactor(ShadowMap,
            ShadowMapSampler,
            g_ShadowTransform, worldPosition);        
    }
    else
    {   
        return calculateShadowFactorNoLargeKernel(ShadowMap,
            ShadowMapSampler,
            g_ShadowTransform, worldPosition);
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
            fmin = f(minZ,
                     minZ, maxZ, Omin, Omax, d, cosAlpha, extinction, falloffRadius,
                     Visibility(start));
        }
        
        float fmax = f(maxZ,
                        minZ, maxZ, Omin, Omax, d, cosAlpha, extinction, falloffRadius,
                        Visibility(end));
        
        integral += ((maxZ - minZ) / 6.f) * (fmin
                                             + 4 * f((minZ + maxZ) / 2.f,
                                                     minZ, maxZ, Omin, Omax, d, cosAlpha, extinction, falloffRadius,
                                                     Visibility((start + end) / 2.f))
                                             + fmax);
        Omin = Omax;
        fmin = fmax;
    }

    return integral;
}

float3 TaylorScatteredLight(
    float3 albedo,
    float3 irradiance,
    float3 L,
    float3 V,
    float asymmetry,
    float3 minpoint,
    float3 maxpoint,
    float Zmin,
    float Zmax,
    float d,
    float cosAlpha,
    float extinction,
    float falloffRadius
)
{
    float phase = WeightedPhase(L, V, asymmetry, g_Anisotropy);
    
    float transmissionFactor = IntegrateTaylorTransmittance(minpoint, maxpoint, Zmin, Zmax, d, cosAlpha, extinction, falloffRadius);

    return albedo * phase * irradiance * 1 * transmissionFactor;
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
    // For this to work properly, N must be a function of z.
    float3 N = normalize(minpoint - centrePos);
    float phase = ReflectivePhase(L, V, N, asymmetry, g_Anisotropy);
    
    float transmissionFactor = IntegrateSimpsonTransmittance(minpoint, maxpoint, Zmin, Zmax, centrePos, extinction, falloffRadius, V);

    
    float fadedExtinction = Sigma_t(Zmin, (Zmin + Zmax) / 2.f, d, cosAlpha, extinction, g_ExtinctionFalloffRadius);
    return albedo * phase * irradiance * transmissionFactor
        + (fadedExtinction / extinction) * g_Albedo * irradiance * phase * 0.001 * g_MultiScatteringFactor;
}

void ComputeDebugEquation(out float3 Cscat, out float Tv,
    float3 minpoint,
    float3 maxpoint)
{
    Cscat = 0.xxx;
    Tv = 1;
    
    
    float3 avg = (minpoint + maxpoint) / 2.f;
    
    float od = SampleOpticalThickness(avg);
    
    if (od < 0)
    {
        Cscat = float3(0, 0, 1);
        return;
    }
    
    float transmittance = exp(-od);
    
    if (transmittance > 1)
    {
        Cscat = float3(0, 0, 1);
        return;
    }
    
    Tv = 1 - pow(1 - transmittance, 30);
    
    Tv = lerp(0.95, 1, Tv);
}

void ComputeVanillaEquation(out float3 Cscat, out float Tv,
    float3 minpoint,
    float3 maxpoint,
    float3 centrePos,
    float extinction
    )
{
    float opticalDepth = length(minpoint - maxpoint);
    
    Tv = VanillaTransmittance(extinction, opticalDepth);
    
    float3 V = normalize(g_CameraPosition - minpoint);
    float3 L = normalize(-g_LightDirection);
    float3 R = g_LightBrightness * g_LightColor;
    
    Cscat = VanillaScatteredLight(minpoint, maxpoint, extinction, centrePos, g_Albedo, R, L, V);
    
    if (any(isnan(Cscat)))
    {
        Cscat = 0.xxx;
    }
}

void ComputeTaylorSeriesEquation(out float3 Cscat, out float Tv,
    float3 minpoint,
    float3 maxpoint,
    float3 centrePos,
    float extinction
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
    
    float fadedExtinction = Sigma_t(Zmin, (Zmin + Zmax) / 2.f, d, cosAlpha, extinction, g_ExtinctionFalloffRadius);
    
    if (fadedExtinction > 0)
    {
        Tv = FadedTransmittance(Zmin,
                    Zmax,
                    d,
                    cosAlpha,
                    extinction,
                    g_ExtinctionFalloffRadius);
        
        float3 L = normalize(-g_LightDirection);
        float3 R = g_LightBrightness * g_LightColor;
        Cscat = TaylorScatteredLight(
                    g_Albedo,
                    R, L, V,
                    g_ScatteringAsymmetry,
                    minpoint, maxpoint,
                    Zmin,
                    Zmax,
                    d,
                    cosAlpha,
                    extinction,
                    g_ExtinctionFalloffRadius);
    
        if (any(isnan(Cscat)))
        {
            Cscat = 0.xxx;
        }
    }
}

void ComputeSimpsonEquation(out float3 Cscat, out float Tv,
    float3 minpoint,
    float3 maxpoint,
    float3 centrePos,
    float extinction
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
    
    float ot = FadedOpticalThickness(Zmin, Zmax, d, cosAlpha, extinction, g_ExtinctionFalloffRadius);
    
    // Any higher than this and a circle starts to appear
    if (ot > MIN_OT)
    {
        Tv = FadedTransmittance(Zmin,
                    Zmax,
                    d,
                    cosAlpha,
                    extinction,
                    g_ExtinctionFalloffRadius);
        
        float3 L = -g_LightDirection;
        float3 R = g_LightBrightness * g_LightColor;
        
        Cscat = SimpsonScatteredLight(
                    g_Albedo,
                    R, L, V,
                    g_ScatteringAsymmetry,
                    minpoint, maxpoint,
                    Zmin,
                    Zmax,
                    centrePos,
                    extinction,
                    g_ExtinctionFalloffRadius,
                    d,
                    cosAlpha);
    
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

void ComputeWastedPixelsEquation(out float3 Cscat, out float Tv,
    float3 minpoint,
    float3 maxpoint,
    float3 centrePos,
    float extinction
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
    
    float ot = FadedOpticalThickness(Zmin, Zmax, d, cosAlpha, extinction, g_ExtinctionFalloffRadius);
    
    if (ot > MIN_OT)
    {
        Tv = 0.f;
        Cscat = 1.xxx;    
    }
    else
    {
        Cscat = float3(1, 0, 0);
        Tv = 0.f;
    }
}

BlendOutput Interval_PS(VertexType input)
{
    
    float4 a, b;
    {
        float4 maxpoint = float4(input.A.xy, input.A.z, 1.0);
        float4 minpoint = float4(input.A.xy, input.A.w, 1.0);
    
        a = mul(minpoint, g_InverseViewProj);
        b = mul(maxpoint, g_InverseViewProj);
        a = a / a.w;
        b = b / b.w;
    }

    BlendOutput ret;
    {
        float4 reprojected = float4(mul(a, view).xyz, 1);
        reprojected.xyz *= -1;
        reprojected = mul(reprojected, persp);
        reprojected /= reprojected.w;
        ret.Depth = reprojected.z;
    }
    
    float extinction = input.ExtinctionScale * g_Extinction * EXTINCTION_SCALE;
    extinction = max(EPSILON, extinction);
    
    float3 Cscat = 0.xxx;
    float Tv = 1;

    [branch]
    if (g_DebugVolShadows > 0)
    {
        ComputeDebugEquation(Cscat, Tv, a.xyz, b.xyz);
    }
    else if (g_RenderingMethod == 0)
    {
        ComputeVanillaEquation(Cscat, Tv, a.xyz, b.xyz, input.WorldPosition, extinction);
    }
    else if (g_RenderingMethod == 1)
    {
        ComputeTaylorSeriesEquation(Cscat, Tv, a.xyz, b.xyz, input.WorldPosition, extinction);
    }
    else if (g_RenderingMethod == 2)
    {
        ComputeSimpsonEquation(Cscat, Tv, a.xyz, b.xyz, input.WorldPosition, extinction);
    }
    else if (g_RenderingMethod == 3)
    {
        ComputeWastedPixelsEquation(Cscat, Tv, a.xyz, b.xyz, input.WorldPosition, extinction);
    }
    
    ret.Color = float4(Cscat, Tv);
    
    return ret;
}