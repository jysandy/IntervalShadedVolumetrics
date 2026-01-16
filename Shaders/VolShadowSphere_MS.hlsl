#include "SphereConstants.hlsli"
#include "Culling.hlsli"
#include "SpherePipeline.hlsli"

StructuredBuffer<SphereInstanceData> Instances : register(t0, space0);
StructuredBuffer<uint> Indices : register(t1, space0);

SphereInstanceData GetInstanceData(uint index)
{
    return Instances[Indices[index]];
}

#define MAX_VERTS_PER_SPHERE 4
#define MAX_TRIS_PER_SPHERE 2
#define NUM_THREADS 32

[numthreads(NUM_THREADS, 1, 1)]
[outputtopology("triangle")]
void VolShadowSphere_MS(
    in uint gtid : SV_GroupIndex,
    in uint3 gid : SV_GroupID,
    out indices uint3 tris[NUM_THREADS * MAX_TRIS_PER_SPHERE],
    out vertices SphereVertexType verts[NUM_THREADS * MAX_VERTS_PER_SPHERE]
)
{
    uint instanceIndex = gid.x * NUM_THREADS + gtid;
    
    bool visible = true;
    float3 worldPosition = float3(0, 0, 0);
    float radius = 1.0;
    float extinctionScale = 1.0;
    float4 projectedCorners[4];
    
    if (instanceIndex < g_NumInstances)
    {
        SphereInstanceData instanceData = GetInstanceData(instanceIndex);
        worldPosition = instanceData.WorldPosition;
        radius = g_Scale * instanceData.Scale;
        extinctionScale = instanceData.ExtinctionScale;
        
        if (radius <= 0)
        {
            visible = false;
        }
        
        if (visible)
        {
            BoundingSphere bs;
            bs.xyz = worldPosition;
            bs.w = radius;
            
            visible = IsVisible(bs, g_CullingFrustumPlanes);
        }
        
        if (visible)
        {
            float3 viewCenter = mul(float4(worldPosition, 1), view).xyz;
            
            if (-viewCenter.z - radius < nearplane)
            {
                visible = false;
            }
            
            if (visible)
            {
                float padding = 1.1;
                float paddedRadius = radius * padding;
                
                float3 right = float3(1, 0, 0);
                float3 up = float3(0, 1, 0);
                
                float3 viewCorners[4];
                viewCorners[0] = viewCenter + paddedRadius * (-right - up);
                viewCorners[1] = viewCenter + paddedRadius * ( right - up);
                viewCorners[2] = viewCenter + paddedRadius * ( right + up);
                viewCorners[3] = viewCenter + paddedRadius * (-right + up);
                
                for (int i = 0; i < 4; i++)
                {
                    projectedCorners[i] = mul(float4(viewCorners[i], 1), persp);
                }
            }
        }
    }
    else
    {
        visible = false;
    }
    
    uint vertex_counter = visible ? 4 : 0;
    uint triangle_counter = visible ? 2 : 0;
    
    uint numVerticesEmitted = WaveActiveSum(vertex_counter);
    uint numTrisEmitted = WaveActiveSum(triangle_counter);
    
    SetMeshOutputCounts(numVerticesEmitted, numTrisEmitted);
    
    if (visible)
    {
        uint prefixVertices = WavePrefixSum(vertex_counter);
        uint prefixTris = WavePrefixSum(triangle_counter);
        
        for (int i = 0; i < 4; i++)
        {
            verts[prefixVertices + i].Position = projectedCorners[i];
            verts[prefixVertices + i].SphereCenter = worldPosition;
            verts[prefixVertices + i].SphereRadius = radius;
            verts[prefixVertices + i].ExtinctionScale = extinctionScale;
        }
        
        tris[prefixTris + 0] = uint3(0, 1, 2) + prefixVertices.xxx;
        tris[prefixTris + 1] = uint3(0, 2, 3) + prefixVertices.xxx;
    }
}
