#include "PropPipeline.hlsli"
#include "PBRLighting.hlsli"
#include "ShadowMapping.hlsli"

Texture2D shadowMap : register(t0, space0);
SamplerComparisonState shadowMapSampler : register(s0, space0);

float4 Prop_PS(VertexType input) : SV_TARGET
{
    float3 N = normalize(input.Normal);
    float3 V = normalize(g_CameraPosition - input.WorldPosition);
    
    float3 albedo = 0.7.xxx;
    float metalness = 0;
    float roughness = 0.8;
    
    float3 directRadiance = cookTorranceDirectionalLight(
        N, V, albedo, metalness, roughness, g_DirectionalLight
    );
    
    float shadowFactor = calculateShadowFactor(
        shadowMap, shadowMapSampler, g_ShadowTransform, input.WorldPosition
    );

    float3 ambient = 0.01.xxx;
    
    float3 outputColour = ambient + directRadiance * shadowFactor;
    
    return float4(outputColour, 1);
}