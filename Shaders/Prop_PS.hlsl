#include "PropPipeline.hlsli"
#include "PBRLighting.hlsli"
#include "ShadowMapping.hlsli"

Texture2D shadowMap : register(t0, space0);
Texture3D<float> VolumetricShadowMap : register(t1, space0);

SamplerState LinearSampler : register(s0, space0);
SamplerComparisonState shadowMapSampler : register(s1, space0);

float SampleOpticalThickness(float3 worldPosition)
{
    float4 transformed = mul(float4(worldPosition, 1), g_VolumetricShadowTransform);
    
    transformed /= transformed.w;
    float3 uvw = transformed.xyz;
    
    uvw.xy = 1 - uvw.xy; // why is this necessary?
    
    // Z should already be linear since the projection is orthographic
    return VolumetricShadowMap.Sample(LinearSampler, uvw);
}

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

    float3 ambient = 0.1.xxx;
    
    float ot = SampleOpticalThickness(input.WorldPosition);
    float transmittance = exp(-ot);
    
    float3 outputColour = ambient + directRadiance * shadowFactor * transmittance;
    
    return float4(outputColour, 1);
}