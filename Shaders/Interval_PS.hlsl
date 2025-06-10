#include "TetrahedronPipeline.hlsli"


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

static const float EPSILON = 0.0001;

float3 ScatteredLight(
    float3 extinction,
    float3 albedo, 
    float opticalDepth, 
    float3 irradiance,
    float3 L,
    float3 V,
    float asymmetry)
{
    float phase = HGPhase(L, V, asymmetry);
    
    float3 transmissionFactor = (1.xxx - exp(-extinction * opticalDepth)) / extinction;

    if (extinction.x < EPSILON)
        transmissionFactor.x = opticalDepth;
    
    if (extinction.y < EPSILON)
        transmissionFactor.y = opticalDepth;
    
    if (extinction.z < EPSILON)
        transmissionFactor.z = opticalDepth;

    return albedo * phase * irradiance * transmissionFactor;
}

float3 AmbientLight(
    float3 extinction,
    float3 albedo,
    float opticalDepth,
    float3 irradiance)
{
    float phase = 1.f / (4 * PI);
    
    float3 transmissionFactor = (1 - exp(-extinction * opticalDepth)) / extinction;

    if (extinction.x < EPSILON)
        transmissionFactor.x = opticalDepth;
    
    if (extinction.y < EPSILON)
        transmissionFactor.y = opticalDepth;
    
    if (extinction.z < EPSILON)
        transmissionFactor.z = opticalDepth;

    return albedo * phase * irradiance * transmissionFactor;
}

BlendOutput Interval_PS(VertexType input)
{
    float4 minpoint = float4(input.A.xy, input.A.z, 1.0);
    float4 maxpoint = float4(input.A.xy, input.A.w, 1.0);

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
    
    float3 extinction = g_Albedo * input.ExtinctionScale * g_Extinction / 100.f;
    
    float opticalDepth = length(b - a);

    ret.Tv = float4(ViewTransmittance(extinction.xxx, opticalDepth), 1);

    float3 V = normalize(g_CameraPosition - a.xyz);
    float3 L = normalize(-g_LightDirection);
    float3 R = g_LightBrightness * g_LightColor * 0.01;
    float3 cscat 
        = 0.60 * ScatteredLight(extinction, g_Albedo, opticalDepth, R, L, V, g_ScatteringAsymmetry)
            + 0.40 * AmbientLight(extinction, g_Albedo, opticalDepth, R);

    ret.CScat = float4(cscat, 1);
    
    return ret;
}