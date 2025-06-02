#include "TetrahedronPipeline.hlsli"


float4 Interval_PS(VertexType input) : SV_Target
{
    float4 minpoint = float4(input.A.xy, input.A.z, 1.0);
    float4 maxpoint = float4(input.A.xy, input.A.w, 1.0);


    // TODO: FIXME by passing the inverse matrices as constants
    //float4 a = inverse(persp * view) * minpoint;
    //float4 b = inverse(persp * view) * maxpoint;
    //a = a / a.w;
    //b = b / b.w;


    float absorption = sqrt(length(maxpoint.z - minpoint.z));
    
    return float4(absorption, absorption, absorption, 1.f);
}