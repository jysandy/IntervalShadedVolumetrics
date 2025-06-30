#include "Utils.hlsli"
#include "TetrahedronPipeline.hlsli"
#include "RenderingEquation.hlsli"

Texture3D<float> VolumetricShadowMap : register(t2, space0);

SamplerState LinearSampler : register(s0, space0);

struct BlendOutput
{
    float4 Color : SV_Target0;
    float Depth : SV_Depth;
};

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

float SampleOpticalThickness(float3 worldPosition)
{
    float4 transformed = mul(float4(worldPosition, 1), g_ShadowTransform);
    
    transformed /= transformed.w;
    float3 uvw = transformed.xyz;
    
    uvw.xy = 1 - uvw.xy; // why is this necessary?
    
    // Z should already be linear since the projection is orthographic
    return VolumetricShadowMap.Sample(LinearSampler, uvw);
}

float Transmittance(float extinction, float opticalDepth)
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

float IntegrateTransmittance(
    float3 minpoint,
    float3 maxpoint,
    float extinction,
    float3 centrePos,
    float falloffRadius
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

float IntegrateFadedTransmittance(
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
        2,
        Zmin,
        Zmax,
        Omin,
        Omax,
        d,
        cosAlpha,
        extinction,
        falloffRadius));
}

float3 ScatteredLight(
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
    float directionality = 0.2f;
    float phase = WeightedPhase(L, V, asymmetry, g_Anisotropy);
    
    float transmissionFactor = IntegrateFadedTransmittance(minpoint, maxpoint, Zmin, Zmax, d, cosAlpha, extinction, falloffRadius);
    //float transmissionFactor = IntegrateTransmittance(minpoint, maxpoint, extinction, centrePos, falloffRadius);

    return albedo * phase * irradiance * 1 * transmissionFactor;
}

float3 Debug(float3 minpoint, float3 maxpoint)
{
    float3 avg = (minpoint + maxpoint) / 2.f;
    
    float od = SampleOpticalThickness(avg);
    
    if (od < 0)
    {
        return float3(0, 0, 1);
    }
    
    float transmittance = exp(-od);
    
    if (transmittance > 1)
        return float3(0, 0, 1);
    
    //return pow(1 - (od / 1000.f), 200).xxx;
    
    //return pow(saturate(transmittance), 10).xxx / 5.f;
    return pow(transmittance, 1).xxx * 0.1f;
}

BlendOutput Interval_PS(VertexType input)
{
    float4 maxpoint = float4(input.A.xy, input.A.z, 1.0);
    float4 minpoint = float4(input.A.xy, input.A.w, 1.0);

    float4 a = mul(minpoint, g_InverseViewProj);
    float4 b = mul(maxpoint, g_InverseViewProj);
    a = a / a.w;
    b = b / b.w;

    BlendOutput ret;

    float4 reprojected = float4(mul(a, view).xyz, 1);
    reprojected.xyz *= -1;
    reprojected = mul(reprojected, persp);
    reprojected /= reprojected.w;
    ret.Depth = reprojected.z;
    
    float extinction = input.ExtinctionScale * g_Extinction / 100.f;
    extinction = max(EPSILON, extinction);
    
    float3 Cscat = 0.xxx;
    float Tv = 1;
    
    float Zmin = length(g_CameraPosition - a.xyz);
    float Zmax = length(g_CameraPosition - b.xyz);
    
    if (abs(Zmin - Zmax) < EPSILON)
    {
        ret.Color = float4(0, 0, 0, 1);
        return ret;
    }
    
    float3 V = normalize(g_CameraPosition - a.xyz);
    float3 toCentre = normalize(input.WorldPosition - a.xyz);
    float d = length(input.WorldPosition - a.xyz);
    float cosAlpha = clamp(dot(-V, toCentre), -1, 1);
    
    float fadedExtinction = Sigma_t(Zmin, (Zmin + Zmax) / 2.f, d, cosAlpha, extinction, g_ExtinctionFalloffRadius);

    if (g_DebugVolShadows > 0)
    {
        Cscat = Debug(a.xyz, b.xyz);
        Tv = 1;
    }
    else if (fadedExtinction > 0.00001)
    {
        Tv = FadedTransmittance(Zmin,
                    Zmax,
                    d,
                    cosAlpha,
                    extinction,
                    g_ExtinctionFalloffRadius);
        
        float3 L = normalize(-g_LightDirection);
        float3 R = g_LightBrightness * g_LightColor;
        Cscat = ScatteredLight(
                    g_Albedo,
                    R, L, V,
                    g_ScatteringAsymmetry,
                    a.xyz, b.xyz,
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
    
    ret.Color = float4(Cscat, Tv);
    
    return ret;
}