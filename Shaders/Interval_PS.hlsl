#include "TetrahedronPipeline.hlsli"


float4 Interval_PS(VertexType input) : SV_Target
{
    float4 minpoint = float4(input.A.xy, input.A.z, 1.0);
    float4 maxpoint = float4(input.A.xy, input.A.w, 1.0);

    float4 a = mul(minpoint, g_InverseViewProj);
    float4 b = mul(maxpoint, g_InverseViewProj);
    a = a / a.w;
    b = b / b.w;

    float3 absorption = 1.xxx - exp(-g_Density * g_Albedo * length(b - a));
    
    return float4(absorption, 1.f);
}