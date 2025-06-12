#ifndef __TETRAHEDRON_PIPELINE_HLSLI__
#define __TETRAHEDRON_PIPELINE_HLSLI__

#include "Quaternion.hlsli"                                     

cbuffer Constants : register(b0, space0)
{
    float4x4 g_TargetWorld;
    float4x4 view;
    float4x4 persp;
    float4x4 g_InverseViewProj;
    float4x4 g_ShadowTransform;
    float4 g_CullingFrustumPlanes[6];
    
    float nearplane;
    float3 g_Albedo;
    
    float g_Extinction;
    float3 g_CameraPosition;
    
    float g_LightBrightness;
    float3 g_LightDirection;
    
    float g_ScatteringAsymmetry;
    float3 g_LightColor;
    
    float g_totalTime;
    float g_NumInstances;
    float g_DeltaTime;
    float g_DidShoot;
    
    float3 g_ShootRayStart;
    float g_FarPlane;
    float3 g_ShootRayEnd;
    float g_DebugVolShadows;
};

struct InstanceData
{
    float3 WorldPosition;
    float ExtinctionScale;
    float3 Velocity;
    float Mass;
    float3 TargetPosition;
    float Pad2;
    Quaternion RotationQuat;
};

struct VertexType
{
    float4 Position : SV_Position;
    
    // This is the vertex attribute that gets interpolated
    // to form the depth values. 
    // TODO: Rename this to something reasonable
    float4 A : POSITION1;
    
    float ExtinctionScale : EXTINCTION;
};

#endif