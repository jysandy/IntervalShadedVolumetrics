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
    min16float4 Color : SV_Target0;
    min16float Depth : SV_Depth;
};

static const min16float MIN_OT = 0.001;

// The Henyey-Greenstein phase function             
// TODO: Should this be wavelength dependent?
min16float HGPhase(min16float3 L, min16float3 V, min16float asymmetry)
{
    min16float constant = 1 / (4 * PI);
    min16float g = asymmetry;
    min16float numerator = 1 - g * g;
    min16float cosTheta = clamp(dot(L, V), -1, 1);
    min16float denominator = pow(1 + g * g + 2 * g * cosTheta, 1.5);
    return constant * numerator / denominator;
}

min16float WeightedPhase(min16float3 L, min16float3 V, min16float asymmetry, min16float directionality)
{
    min16float constant = 1 / (4 * PI);
    
    min16float hg = HGPhase(L, V, asymmetry);
    
    return lerp(constant, hg, directionality);
}

min16float SampleOpticalThickness(min16float3 worldPosition)
{
    min16float4 transformed = mul(min16float4(worldPosition, 1), g_VolumetricShadowTransform);
    
    transformed /= transformed.w;
    min16float3 uvw = transformed.xyz;
    
    uvw.xy = 1 - uvw.xy; // why is this necessary?
    
    // Z should already be linear since the projection is orthographic
    return VolumetricShadowMap.Sample(LinearSampler, uvw);
}

min16float VanillaTransmittance(min16float extinction, min16float opticalDepth)
{
    return exp(-extinction * opticalDepth);
}

min16float FadedTransmittance(
    min16float Zmin,
    min16float Zmax,
    min16float d,
    min16float cosAlpha,
    min16float extinction,
    min16float falloffRadius
)
{
    return FadedTransmittanceTv2(Zmin, Zmax, d, cosAlpha, extinction, falloffRadius);
}

min16float IntegrateVanillaTransmittance(
    min16float3 minpoint,
    min16float3 maxpoint,
    min16float extinction,
    min16float3 centrePos
)
{
    min16float Zmin = length(g_CameraPosition - minpoint);
    min16float Zmax = length(g_CameraPosition - maxpoint);
    
    min16float Omin = SampleOpticalThickness(minpoint);
    min16float Omax = SampleOpticalThickness(maxpoint);
    
    min16float denominator = ZeroCutoff(Omax - Omin + extinction * (Zmax - Zmin), EPSILON);
    
    min16float firstExponent = extinction * Zmax + Omax;
    min16float secondExponent = extinction * Zmin + Omin;
    min16float thirdExponent = -extinction * Zmax - Omax - Omin;
    
    min16float numerator
        = extinction * (Zmin - Zmax) * (exp(firstExponent) - exp(secondExponent)) * exp(thirdExponent);
    
    // Output must be non-negative
    denominator = MatchSign(denominator, numerator);
    
    return numerator / denominator;
}

min16float3 VanillaScatteredLight(
    min16float3 minpoint,
    min16float3 maxpoint,
    min16float extinction,
    min16float3 centrePos,
    min16float3 albedo,
    min16float3 irradiance,
    min16float3 L,
    min16float3 V
)
{
    min16float phase = WeightedPhase(L, V, g_ScatteringAsymmetry, g_Anisotropy);
    
    min16float transmissionFactor = IntegrateVanillaTransmittance(minpoint, maxpoint, extinction, centrePos);

    return albedo * phase * irradiance * 1 * transmissionFactor;
}

min16float IntegrateTaylorTransmittance(
    min16float3 minpoint,
    min16float3 maxpoint,
    min16float Zmin,
    min16float Zmax,
    min16float d,
    min16float cosAlpha,
    min16float extinction,
    min16float falloffRadius
)
{
    min16float Omin = SampleOpticalThickness(minpoint);
    min16float Omax = SampleOpticalThickness(maxpoint);
    
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

min16float Visibility(min16float3 worldPosition)
{
    //if (g_SoftShadows)
    //{
    //    return calculateShadowFactor(ShadowMap,
    //        ShadowMapSampler,
    //        g_ShadowTransform, worldPosition);        
    //}
    //else
    //{   
        return calculateShadowFactorNoLargeKernel(ShadowMap,
            ShadowMapSampler,
            g_ShadowTransform, worldPosition);
    //}
}

min16float IntegrateSimpsonTransmittance(
    min16float3 minpoint,
    min16float3 maxpoint,
    min16float Zmin,
    min16float Zmax,
    min16float3 centrePos,
    min16float extinction,
    min16float falloffRadius,
    min16float3 V
)
{
    min16float integral = 0;
    
    min16float stepSize = (Zmax - Zmin) / (min16float) g_StepCount;

    min16float fmin = 0;
    min16float Omin = 0;
    
    for (int i = 0; i < g_StepCount; i++)
    {
        min16float3 start = minpoint + i * stepSize * (-V);
        min16float3 end = minpoint + (i + 1) * stepSize * (-V);
        
        min16float minZ = Zmin + i * stepSize;
        min16float maxZ = Zmin + (i + 1) * stepSize;
        
        min16float3 toCentre = normalize(centrePos - start);
        min16float d = length(centrePos - start);
        min16float cosAlpha = clamp(dot(-V, toCentre), -1, 1);
        
        min16float Omax = SampleOpticalThickness(end);
        if (i == 0)
        {
            Omin = SampleOpticalThickness(start);
            fmin = f(minZ,
                     minZ, maxZ, Omin, Omax, d, cosAlpha, extinction, falloffRadius,
                     Visibility(start));
        }
        
        min16float fmax = f(maxZ,
                        minZ, maxZ, Omin, Omax, d, cosAlpha, extinction, falloffRadius,
                        Visibility(end));
        
        integral += ((maxZ - minZ) / 6) * (fmin
                                             + 4 * f((minZ + maxZ) / 2,
                                                     minZ, maxZ, Omin, Omax, d, cosAlpha, extinction, falloffRadius,
                                                     Visibility((start + end) / 2))
                                             + fmax);
        Omin = Omax;
        fmin = fmax;
    }

    return integral;
}

min16float3 TaylorScatteredLight(
    min16float3 albedo,
    min16float3 irradiance,
    min16float3 L,
    min16float3 V,
    min16float asymmetry,
    min16float3 minpoint,
    min16float3 maxpoint,
    min16float Zmin,
    min16float Zmax,
    min16float d,
    min16float cosAlpha,
    min16float extinction,
    min16float falloffRadius
)
{
    min16float phase = WeightedPhase(L, V, asymmetry, g_Anisotropy);
    
    min16float transmissionFactor = IntegrateTaylorTransmittance(minpoint, maxpoint, Zmin, Zmax, d, cosAlpha, extinction, falloffRadius);

    return albedo * phase * irradiance * 1 * transmissionFactor;
}

min16float3 SimpsonScatteredLight(
    min16float3 albedo,
    min16float3 irradiance,
    min16float3 L,
    min16float3 V,
    min16float asymmetry,
    min16float3 minpoint,
    min16float3 maxpoint,
    min16float Zmin,
    min16float Zmax,
    min16float3 centrePos,
    min16float extinction,
    min16float falloffRadius,
    min16float d, 
    min16float cosAlpha
)
{
    min16float phase = WeightedPhase(L, V, asymmetry, g_Anisotropy);
    
    min16float transmissionFactor = IntegrateSimpsonTransmittance(minpoint, maxpoint, Zmin, Zmax, centrePos, extinction, falloffRadius, V);

    
    min16float fadedExtinction = Sigma_t(Zmin, (Zmin + Zmax) / 2, d, cosAlpha, extinction, g_ExtinctionFalloffRadius);
    return albedo * phase * irradiance * transmissionFactor
        + fadedExtinction * g_Albedo * irradiance * phase * 0.01;
}

void ComputeDebugEquation(out min16float3 Cscat, out min16float Tv,
    min16float3 minpoint,
    min16float3 maxpoint)
{
    Cscat = 0.xxx;
    Tv = 1;
    
    
    min16float3 avg = (minpoint + maxpoint) / 2;
    
    min16float od = SampleOpticalThickness(avg);
    
    if (od < 0)
    {
        Cscat = min16float3(0, 0, 1);
        return;
    }
    
    min16float transmittance = exp(-od);
    
    if (transmittance > 1)
    {
        Cscat = min16float3(0, 0, 1);
        return;
    }
    
    Tv = 1 - pow(1 - transmittance, 30);
    
    Tv = lerp(0.95, 1, Tv);
}

void ComputeVanillaEquation(out min16float3 Cscat, out min16float Tv,
    min16float3 minpoint,
    min16float3 maxpoint,
    min16float3 centrePos,
    min16float extinction
    )
{
    min16float opticalDepth = length(minpoint - maxpoint);
    
    Tv = VanillaTransmittance(extinction, opticalDepth);
    
    min16float3 V = normalize(g_CameraPosition - minpoint);
    min16float3 L = normalize(-g_LightDirection);
    min16float3 R = g_LightBrightness * g_LightColor;
    
    Cscat = VanillaScatteredLight(minpoint, maxpoint, extinction, centrePos, g_Albedo, R, L, V);
    
    if (any(isnan(Cscat)))
    {
        Cscat = 0.xxx;
    }
}

void ComputeTaylorSeriesEquation(out min16float3 Cscat, out min16float Tv,
    min16float3 minpoint,
    min16float3 maxpoint,
    min16float3 centrePos,
    min16float extinction
    )
{
    Cscat = 0.xxx;
    Tv = 1;
    
    min16float Zmin = length(g_CameraPosition - minpoint);
    min16float Zmax = length(g_CameraPosition - maxpoint);
    
    if (abs(Zmin - Zmax) < EPSILON)
    {
        return;
    }
    
    min16float3 V = normalize(g_CameraPosition - minpoint);
    min16float3 toCentre = normalize(centrePos - minpoint);
    min16float d = length(centrePos - minpoint);
    min16float cosAlpha = clamp(dot(-V, toCentre), -1, 1);
    
    min16float fadedExtinction = Sigma_t(Zmin, (Zmin + Zmax) / 2, d, cosAlpha, extinction, g_ExtinctionFalloffRadius);
    
    if (fadedExtinction > 0)
    {
        Tv = FadedTransmittance(Zmin,
                    Zmax,
                    d,
                    cosAlpha,
                    extinction,
                    g_ExtinctionFalloffRadius);
        
        min16float3 L = normalize(-g_LightDirection);
        min16float3 R = g_LightBrightness * g_LightColor;
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

void ComputeSimpsonEquation(out min16float3 Cscat, out min16float Tv,
    min16float3 minpoint,
    min16float3 maxpoint,
    min16float3 centrePos,
    min16float extinction
    )
{
    Cscat = 0.xxx;
    Tv = 1;
    
    min16float Zmin = length(g_CameraPosition - minpoint);
    min16float Zmax = length(g_CameraPosition - maxpoint);
    
    if (abs(Zmin - Zmax) < EPSILON)
    {
        return;
    }
    
    min16float3 V = normalize(g_CameraPosition - minpoint);
    min16float3 toCentre = normalize(centrePos - minpoint);
    min16float d = length(centrePos - minpoint);
    min16float cosAlpha = clamp(dot(-V, toCentre), -1, 1);
    
    min16float ot = FadedOpticalThickness(Zmin, Zmax, d, cosAlpha, extinction, g_ExtinctionFalloffRadius);
    
    // Any higher than this and a circle starts to appear
    if (ot > MIN_OT)
    {
        Tv = FadedTransmittance(Zmin,
                    Zmax,
                    d,
                    cosAlpha,
                    extinction,
                    g_ExtinctionFalloffRadius);
        
        min16float3 L = -g_LightDirection;
        min16float3 R = g_LightBrightness * g_LightColor;
        
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

void ComputeWastedPixelsEquation(out min16float3 Cscat, out min16float Tv,
    min16float3 minpoint,
    min16float3 maxpoint,
    min16float3 centrePos,
    min16float extinction
    )
{
    Cscat = 0.xxx;
    Tv = 1;
    
    min16float Zmin = length(g_CameraPosition - minpoint);
    min16float Zmax = length(g_CameraPosition - maxpoint);
    
    if (abs(Zmin - Zmax) < EPSILON)
    {
        return;
    }
    
    min16float3 V = normalize(g_CameraPosition - minpoint);
    min16float3 toCentre = normalize(centrePos - minpoint);
    min16float d = length(centrePos - minpoint);
    min16float cosAlpha = clamp(dot(-V, toCentre), -1, 1);
    
    min16float ot = FadedOpticalThickness(Zmin, Zmax, d, cosAlpha, extinction, g_ExtinctionFalloffRadius);
    
    if (ot > MIN_OT)
    {
        Tv = 0;
        Cscat = 1.xxx;    
    }
    else
    {
        Cscat = min16float3(1, 0, 0);
        Tv = 0;
    }
}

BlendOutput Interval_PS(VertexType input)
{
    
    min16float4 a, b;
    {
        min16float4 maxpoint = min16float4(input.A.xy, input.A.z, 1.0);
        min16float4 minpoint = min16float4(input.A.xy, input.A.w, 1.0);
    
        a = mul(minpoint, g_InverseViewProj);
        b = mul(maxpoint, g_InverseViewProj);
        a = a / a.w;
        b = b / b.w;
    }

    BlendOutput ret;
    {
        min16float4 reprojected = min16float4(mul(a, view).xyz, 1);
        reprojected.xyz *= -1;
        reprojected = mul(reprojected, persp);
        reprojected /= reprojected.w;
        ret.Depth = reprojected.z;
    }
    
    min16float extinction = input.ExtinctionScale * g_Extinction * EXTINCTION_SCALE;
    extinction = max(EPSILON, extinction);
    
    min16float3 Cscat = 0.xxx;
    min16float Tv = 1;

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
    
    ret.Color = min16float4(Cscat, Tv);
    
    return ret;
}