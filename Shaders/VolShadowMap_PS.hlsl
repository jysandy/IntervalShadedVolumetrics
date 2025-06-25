#include "TetrahedronPipeline.hlsli"

float VolShadowMap_PS(VertexType input) : SV_Target
{
    float4 minpoint = float4(input.A.xy, input.A.z, 1.0);
    float4 maxpoint = float4(input.A.xy, input.A.w, 1.0);

    float4 a = mul(minpoint, g_InverseViewProj);
    float4 b = mul(maxpoint, g_InverseViewProj);
    a = a / a.w;
    b = b / b.w;

    float extinction = input.ExtinctionScale * g_Extinction / 100.f;
    extinction = max(0.00001, extinction);
    float opticalDepth = length(b - a);
    
    return extinction * opticalDepth;
}