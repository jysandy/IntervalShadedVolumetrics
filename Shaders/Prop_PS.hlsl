#include "PropPipeline.hlsli"
#include "PBRLighting.hlsli"

float4 Prop_PS(VertexType input) : SV_TARGET
{
    float3 N = normalize(input.Normal);
    float3 V = normalize(g_CameraPosition - input.WorldPosition);
    
    float3 albedo = 0.7.xxx;
    float metalness = 0;
    float roughness = 0.8;
    
    //float3 directRadiance = DirectionalLightContribution(
    //    N, V, albedo, metalness, roughness, g_DirectionalLight,
    //    shadowMap, shadowMapSampler, shadowTransform, input.worldPosition
    //);
    
    float3 directRadiance = cookTorranceDirectionalLight(
        N, V, albedo, metalness, roughness, g_DirectionalLight
    );

    float3 ambient = 0.01.xxx;
    
    float3 outputColour = ambient + directRadiance;
    
    return float4(outputColour, 1);
}