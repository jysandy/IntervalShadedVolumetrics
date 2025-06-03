#include "TetrahedronPipeline.hlsli"


float4 Interval_PS(VertexType input) : SV_Target
{
    float4 minpoint = float4(input.A.xy, input.A.z, 1.0);
    float4 maxpoint = float4(input.A.xy, input.A.w, 1.0);


    // TODO: FIXME by passing the inverse matrices as constants
    float4 a = mul(minpoint, g_InverseViewProj);
    float4 b = mul(maxpoint, g_InverseViewProj);
    a = a / a.w;
    b = b / b.w;


    float absorption = pow(1 - exp(-length(b - a)), 4) * 0.6;
    
    return float4(absorption.xxx, 1.f);
}