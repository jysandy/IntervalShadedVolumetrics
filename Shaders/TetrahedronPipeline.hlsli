#ifndef __TETRAHEDRON_PIPELINE_HLSLI__
#define __TETRAHEDRON_PIPELINE_HLSLI__

cbuffer Constants : register(b0, space0)
{
    float4x4 world;
    float4x4 view;
    float4x4 persp;
    float4x4 g_InverseViewProj;
    
    float nearplane;
    float3 g_Albedo;
    
    float g_Absorption;
    float3 g_CameraPosition;
    
    float g_LightBrightness;
    float3 g_LightDirection;
    
    float g_ScatteringAsymmetry;
    float3 g_LightColor;
};

struct InstanceData
{
    float3 WorldPosition;
    float Pad;
};

StructuredBuffer<InstanceData> Instances : register(t0, space0);

struct VertexType
{
    float4 Position : SV_Position;
    
    // This is the vertex attribute that gets interpolated
    // to form the depth values. 
    // TODO: Rename this to something reasonable
    float4 A : POSITION1;
};

#endif