#ifndef __TETRAHEDRON_PIPELINE_HLSLI__
#define __TETRAHEDRON_PIPELINE_HLSLI__

#include "CommonPipeline.hlsli"
#include "Quaternion.hlsli"

struct VertexType
{
    float4 Position : SV_Position;
    
    // This is the vertex attribute that gets interpolated
    // to form the depth values. 
    // TODO: Rename this to something reasonable
    float4 A : POSITION1;
    
    nointerpolation float ExtinctionScale : EXTINCTION;
    nointerpolation float3 WorldPosition : WORLDPOS;
    nointerpolation float Scale : SCALE;
};

#endif