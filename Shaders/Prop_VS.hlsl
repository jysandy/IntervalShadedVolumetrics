#include "PropPipeline.hlsli"

struct InputType
{
    float3 Position : SV_POSITION;
    float3 Normal : NORMAL;
    float2 Tex : TEXCOORD;
};

VertexType Prop_VS(InputType input)
{
    VertexType output;

    output.ClipPosition = mul(float4(input.Position, 1), g_WorldViewProj);
    output.Normal = normalize(mul(input.Normal, (float3x3) g_World));
    output.WorldPosition = mul(float4(input.Position, 1), g_World).xyz;

    return output;
}