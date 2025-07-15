#ifndef __PROP_PIPELINE_HLSLI__
#define __PROP_PIPELINE_HLSLI__

#include "LightStructs.hlsli"

struct VertexType
{
    float4 ClipPosition : SV_POSITION;
    float3 Normal : NORMAL;
    float3 WorldPosition : POSITION1;
};

cbuffer Constants : register(b0, space0)
{
    float4x4 g_World;
    float4x4 g_WorldViewProj;
    DirectionalLight g_DirectionalLight;
    float4x4 g_ShadowTransform;
    float3 g_CameraPosition;
    float g_Pad;
};

#endif