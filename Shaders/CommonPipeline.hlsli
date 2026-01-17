#ifndef __COMMON_PIPELINE_HLSLI__
#define __COMMON_PIPELINE_HLSLI__

#include "Utils.hlsli"
#include "RenderingEquation.hlsli"

cbuffer Constants : register(b0, space0)
{
    float4x4 g_TargetWorld;
    float4x4 view;
    float4x4 persp;
    float4x4 g_InverseViewProj;
    float4x4 g_VolumetricShadowTransform;
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
    
    float g_ExtinctionFalloffRadius;
    float g_Scale;
    float g_Anisotropy;
    uint g_RenderingMethod;
    
    uint g_SoftShadows;
    uint g_StepCount;
    float g_MultiScatteringFactor; 
    float g_Reflectivity;

    float g_RenderTargetWidth;
    float g_RenderTargetHeight;
    float g_Padding1;
    float g_Padding2;
};

struct InstanceData
{
    float3 WorldPosition;
    float ExtinctionScale;
    float3 Velocity;
    float Mass;
    float3 TargetPosition;
    float Scale;
    float4 RotationQuat;
};

static const float EXTINCTION_SCALE = 1 / 10000.f;

#endif
