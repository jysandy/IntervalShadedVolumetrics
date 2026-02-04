#include "Utils.hlsli"
#include "TetrahedronPipeline.hlsli"
#define INVERT_SHADOW_MAP 1
#include "VolumetricLighting.hlsli"

struct BlendOutput
{
    float4 Color : SV_Target0;
    float Depth : SV_Depth;
};

float VanillaTransmittance(float extinction, float opticalDepth)
{
    return exp(-extinction * opticalDepth);
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
        falloffRadius,
        LinearSampler));
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
    
    float fadedExtinction = Sigma_t(Zmin, (Zmin + Zmax) / 2.f, d, cosAlpha, extinction, falloffRadius);
    
    if (fadedExtinction > 0)
    {
        Tv = FadedTransmittance(Zmin,
                    Zmax,
                    d,
                    cosAlpha,
                    extinction,
                    falloffRadius);
        
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
                    falloffRadius);
    
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
    
    float ot = FadedOpticalThickness(Zmin, Zmax, d, cosAlpha, extinction, falloffRadius, LinearSampler);
    
    if (ot > MIN_OT)
    {
        Tv = FadedTransmittance(Zmin,
                    Zmax,
                    d,
                    cosAlpha,
                    extinction,
                    falloffRadius);
        
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
                    falloffRadius,
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
    
    float ot = FadedOpticalThickness(Zmin, Zmax, d, cosAlpha, extinction, g_ExtinctionFalloffRadius * scale, LinearSampler);
    
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
        ComputeTaylorSeriesEquation(Cscat, Tv, a.xyz, b.xyz, input.WorldPosition, extinction, input.Scale);
    }
    else if (g_RenderingMethod == 2)
    {
        ComputeSimpsonEquation(Cscat, Tv, a.xyz, b.xyz, input.WorldPosition, extinction, input.Scale);
    }
    else if (g_RenderingMethod == 3)
    {
        ComputeWastedPixelsEquation(Cscat, Tv, a.xyz, b.xyz, input.WorldPosition, extinction, input.Scale);
    }
    
    ret.Color = float4(Cscat, Tv);
    
    return ret;
}