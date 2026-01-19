#include "CommonPipeline.hlsli"
#include "Culling.hlsli"
#include "SpherePipeline.hlsli"

StructuredBuffer<InstanceData> Instances : register(t0, space0);
StructuredBuffer<uint> Indices : register(t1, space0);

InstanceData GetInstanceData(uint index)
{
    return Instances[Indices[index]];
}

#define MAX_VERTS_PER_SPHERE PROXY_SIDES
#define MAX_TRIS_PER_SPHERE (PROXY_SIDES - 2)
#define NUM_THREADS 32
#define PI 3.14159265359

[numthreads(NUM_THREADS, 1, 1)]
[outputtopology("triangle")]
void Sphere_MS(
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
    float4 projectedCorners[PROXY_SIDES];
    
    if (instanceIndex < g_NumInstances)
    {
        InstanceData instanceData = GetInstanceData(instanceIndex);
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

            // Unlike the tetrahedrons, the sphere proxies needn't 
            // be culled at the near plane
            
            if (visible)
            {
                float padding = 1.1;
                float paddedRadius = radius * padding;
                
                // Generate polygon vertices in a circle
                for (int i = 0; i < PROXY_SIDES; i++)
                {
                    float angle = (2.0 * PI * i) / PROXY_SIDES;
                    float x = cos(angle);
                    float y = sin(angle);
                    
                    float3 viewCorner = viewCenter + paddedRadius * float3(x, y, 0);
                    projectedCorners[i] = mul(float4(viewCorner, 1), persp);
                }
            }
        }
    }
    else
    {
        visible = false;
    }
    
    uint vertex_counter = visible ? PROXY_SIDES : 0;
    uint triangle_counter = visible ? (PROXY_SIDES - 2) : 0;
    
    uint numVerticesEmitted = WaveActiveSum(vertex_counter);
    uint numTrisEmitted = WaveActiveSum(triangle_counter);
    
    SetMeshOutputCounts(numVerticesEmitted, numTrisEmitted);
    
    if (visible)
    {
        uint prefixVertices = WavePrefixSum(vertex_counter);
        uint prefixTris = WavePrefixSum(triangle_counter);
        
        for (int i = 0; i < PROXY_SIDES; i++)
        {
            verts[prefixVertices + i].Position = projectedCorners[i];
            verts[prefixVertices + i].SphereCenter = worldPosition;
            verts[prefixVertices + i].SphereRadius = radius;
            verts[prefixVertices + i].ExtinctionScale = extinctionScale;
        }
        
        // Generate triangle fan from polygon
        for (int i = 0; i < PROXY_SIDES - 2; i++)
        {
            tris[prefixTris + i] = uint3(0, i + 1, i + 2) + prefixVertices.xxx;
        }
    }
}
