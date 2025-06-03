#ifndef __TETRAHEDRON_PIPELINE_HLSLI__
#define __TETRAHEDRON_PIPELINE_HLSLI__

cbuffer Constants : register(b0, space0)
{
    float4x4 model;
    float4x4 view;
    float4x4 persp;
    float4x4 g_InverseViewProj;
    float nearplane;
};

struct VertexType
{
    float4 Position : SV_Position;
    
    // This is the vertex attribute that gets interpolated
    // to form the depth values. 
    // TODO: Rename this to something reasonable
    float4 A : POSITION1;
};

#endif