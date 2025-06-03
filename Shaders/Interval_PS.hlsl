#include "TetrahedronPipeline.hlsli"


struct BlendOutput
{
    float4 CScat : SV_Target0;
    float4 Tv : SV_Target1;
};

static const float PI = 3.14159265359;

BlendOutput Interval_PS(VertexType input)
{
    float4 minpoint = float4(input.A.xy, input.A.z, 1.0);
    float4 maxpoint = float4(input.A.xy, input.A.w, 1.0);

    float4 a = mul(minpoint, g_InverseViewProj);
    float4 b = mul(maxpoint, g_InverseViewProj);
    a = a / a.w;
    b = b / b.w;

    BlendOutput ret;
    
    float3 density = g_Density * (1.xxx - g_Albedo);
    float opticalDepth = length(b - a);
    
    ret.Tv = float4(exp(-density * opticalDepth), 1);
    
    float phase = 1.f / (4 * PI);
    float R = 5.f;
    
    float3 cscat = phase * R * (1.xxx - exp(-density * opticalDepth)) / density;

    ret.CScat = float4(cscat, 1);
    
    return ret;
}