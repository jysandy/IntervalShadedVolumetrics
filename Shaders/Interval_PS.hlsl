#include "TetrahedronPipeline.hlsli"

Texture3D<float> VolumetricShadowMap : register(t2, space0);

SamplerState LinearSampler : register(s0, space0);

struct BlendOutput
{
    float4 CScat : SV_Target0;
    float4 Tv : SV_Target1;
    float Depth : SV_Depth;
};

static const float PI = 3.14159265359;

float3 ViewTransmittance(float3 extinction, float opticalDepth)
{
    return exp(-extinction * opticalDepth);
}

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

static const float EPSILON = 0.0001;

float SampleOpticalDepth(float3 worldPosition)
{
    float4 transformed = mul(float4(worldPosition, 1), g_ShadowTransform);
    
    transformed /= transformed.w;
    float3 uvw = transformed.xyz;
    
    uvw.xy = 1 - uvw.xy;    // why is this necessary?
    
    // Z should already be linear since the projection is orthographic
    return VolumetricShadowMap.Sample(LinearSampler, uvw);
}

float ZeroCutoff(float v, float e)
{
    if (v >= 0)
    {
        return max(e, v);
    }
    
    return min(-e, v);
}

float3 ZeroCutoff(float3 v, float e)
{
    return float3(
        ZeroCutoff(v.x, e),
        ZeroCutoff(v.y, e),
        ZeroCutoff(v.z, e)
    );
}

float MatchSign(float v, float m)
{
    if (sign(v) != sign(m))
    {
        return -v;
    }

    return v;
}

float3 MatchSign(float3 v, float3 m)
{
    return float3(
        MatchSign(v.x, m.x),
        MatchSign(v.y, m.y),
        MatchSign(v.z, m.z)
    );
}

float3 IntegrateTransmittance(
    float3 minpoint,
    float3 maxpoint,
    float3 extinction
)
{
    float Zmin = length(g_CameraPosition - minpoint);
    float Zmax = length(g_CameraPosition - maxpoint);
    
    float Omin = SampleOpticalDepth(minpoint);
    float Omax = SampleOpticalDepth(maxpoint);
    
    float3 denominator = extinction * ZeroCutoff(Omax - Omin + Zmax - Zmin, EPSILON);
    
    float3 firstExponent = -extinction * (-Zmin + Zmax + Omax);
    float3 secondExponent = -extinction * Omin;
    
    float3 numerator = (Zmin - Zmax) * (exp(firstExponent) - exp(secondExponent));
    
    // Output must be non-negative
    denominator = MatchSign(denominator, numerator);
    
    return numerator / denominator;
}

float3 ScatteredLight(
    float3 extinction,
    float3 albedo,
    float3 minpoint,
    float3 maxpoint,
    float3 irradiance,
    float3 L,
    float3 V,
    float asymmetry)
{
    float directionality = 0.7f;
    float phase = WeightedPhase(L, V, asymmetry, directionality);
    
    float3 transmissionFactor = IntegrateTransmittance(minpoint, maxpoint, extinction);

    return albedo * phase * irradiance * transmissionFactor;
}

float3 Debug(float3 minpoint, float3 maxpoint)
{
    float3 avg = (minpoint + maxpoint) / 2.f;
    
    float od = SampleOpticalDepth(avg);
    
    if (od < 0)
    {
        return float3(0, 0, 1);
    }
    
    float transmittance = exp(-0.2 * od);
    
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
    
    float3 extinction = input.ExtinctionScale * g_Extinction.xxx / 100.f;
    
    float opticalDepth = length(b - a);

    ret.Tv = float4(ViewTransmittance(extinction.xxx, opticalDepth), 1);

    float3 V = normalize(g_CameraPosition - a.xyz);
    float3 L = normalize(-g_LightDirection);
    float3 R = g_LightBrightness * g_LightColor;
    float3 cscat
        = ScatteredLight(extinction, 
                    g_Albedo, 
                    a.xyz,
                    b.xyz,
                    R, L, V, 
                    g_ScatteringAsymmetry);

    if (g_DebugVolShadows > 0)
    {
        cscat = Debug(a.xyz, b.xyz);
        ret.Tv = 1;
    }
    
    ret.CScat = float4(cscat, 1);
    
    return ret;
}