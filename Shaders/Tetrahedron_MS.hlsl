// Adapted from https://github.com/ThibaultTricard/Interval-Shading/blob/b45ea6b9814d0a88655a380795250ad3202651d1/src/shader/singleTet/mesh.mesh


#include "TetrahedronPipeline.hlsli"
#include "Quaternion.hlsli"

StructuredBuffer<InstanceData> Instances : register(t0, space0);
StructuredBuffer<uint> Indices : register(t1, space0);

InstanceData GetInstanceData(uint index)
{
    return Instances[Indices[index]];
}

/*
	std::vector<vec4f> vertices;
	vertices.push_back(vec4f({sqrtf(8.0f/9.0f), 0.0f, -1.0f/3.0f,1.0}));
	vertices.push_back(vec4f({-sqrtf(2.0f/9.0f), sqrtf(2.0f/3.0f), -1.0f/3.0f,1.0}));
	vertices.push_back(vec4f({-sqrtf(2.0f/9.0f), -sqrtf(2.0f/3.0f), -1.0f/3.0f,1.0}));
	vertices.push_back(vec4f({0.0,0.0,1.0,1.0}));
*/
static const float4 coords[] =
{
    float4(sqrt(8 / 9.f), 0.f, -1.f / 3.f, 1.f),
    float4(-sqrt(2.f / 9.f), sqrt(2.f / 3.f), -1.f / 3.f, 1.f),
    float4(-sqrt(2.f / 9.f), -sqrt(2.f / 3.f), -1.f / 3.f, 1.f),
    float4(0.f, 0.f, 1.f, 1.f)
};

struct tetIndices_t
{
    uint index[4];
};


static const tetIndices_t tet[] =
{
    { { 0, 1, 2, 3 } }
};


struct tet_t
{
    float4 pos[4];
};

struct prism_t
{
    float4 pos[6];
};


static const int2 edges[] =
{
    int2(0, 1), //0
  int2(0, 2), //1
  int2(0, 3), //2
  int2(1, 2), //3
  int2(1, 3), //4
  int2(2, 3) //5
};


struct clipedTet_t
{
    tet_t tets[3];
    int tetCount;
};


float cross2D(float2 v1, float2 v2)
{
    return v1.x * v2.y - v1.y * v2.x;
}

//Line intersection algorithm
//Based off Andre LeMothe's algorithm in "Tricks of the Windows Game Programming Gurus".
bool lineIntersection(float2 L1A, float2 L1B, float2 L2A, float2 L2B, out float2 p, out float2 ts)
{
    //Line 1 Vector
    float2 v1 = L1B - L1A;
    
    //Line 2 Vector
    float2 v2 = L2B - L2A;
    
    //Cross of vectors
    float d = cross2D(v1, v2);
    
    //Difference between start points
    float2 LA_delta = L1A - L2A;
    
    //Percentage v1 x LA_delta is along v1 x v2
    float s = cross2D(v1, LA_delta) / d;
    
    //Percentage v2 x LA_delta is along v1 x v2
    float t = cross2D(v2, LA_delta) / d;
    
    //Do segments intersect?
    //Bounds test
    if (s >= 0.0 && s <= 1.0 && t >= 0.0 && t <= 1.0)
    {
        //Projection
        p = float2(L1A.x + (t * v1.x), L1A.y + (t * v1.y));
        ts = float2(t, s);
        return true;
    }
    return false;
}

struct proxy_t
{
    float4 pos[5];
    int point_count;
};

static const int2 potential_projection[] =
{
    int2(0, 3),
  int2(1, 2),
  int2(2, 1),
  int2(3, 0),
};

#define potentialProjection 4


static const int2 potential_intersection[] =
{
    int2(0, 5),
  int2(1, 4),
  int2(2, 3),
};

#define potentialCrossing 3
//index of vertices of each face of a tet
static const uint3 faces[] =
{
    uint3(0, 1, 2),
  uint3(0, 1, 3),
  uint3(0, 2, 3),
  uint3(1, 2, 3)
};


#define MAX_VERTS_PER_TET 5
#define MAX_TRIS_PER_TET 4

#define NUM_THREADS 32

[numthreads(NUM_THREADS, 1, 1)]
[outputtopology("triangle")]
void Tetrahedron_MS(
    in uint gtid : SV_GroupIndex,
    in uint3 gid : SV_GroupID,
    out indices uint3 tris[NUM_THREADS * MAX_TRIS_PER_TET],
    out vertices VertexType verts[NUM_THREADS * MAX_VERTS_PER_TET]
)
{
    uint instanceIndex = gid.x * NUM_THREADS + gtid;
    
    bool visible = true;
    proxy_t proxy;
    
    if (instanceIndex < g_NumInstances)
    {
        tetIndices_t indices = tet[0];

        float4x4 scale = float4x4(
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1
        );
        
        InstanceData instanceData = GetInstanceData(instanceIndex);
        
        float3 worldPosition = instanceData.WorldPosition;
        float4x4 rotation = QuatTo4x4(instanceData.RotationQuat);
        float4x4 model = mul(scale, rotation);
        model._41_42_43 = worldPosition;
        float4x4 modelView = mul(model, view);
        
        tet_t tet;
        tet.pos[0] = mul(coords[indices.index[0]], modelView);
        tet.pos[1] = mul(coords[indices.index[1]], modelView);
        tet.pos[2] = mul(coords[indices.index[2]], modelView);
        tet.pos[3] = mul(coords[indices.index[3]], modelView);

        //clip test
        float bias = nearplane * 0.1;
        
        if (
            tet.pos[0].z < nearplane + bias
            || tet.pos[1].z < nearplane + bias
            || tet.pos[2].z < nearplane + bias
            || tet.pos[3].z < nearplane + bias
            )
        {
            visible = false;
        }
        
        if (
            tet.pos[0].z > g_FarPlane - bias
            || tet.pos[1].z > g_FarPlane - bias
            || tet.pos[2].z > g_FarPlane - bias
            || tet.pos[3].z > g_FarPlane - bias
            )
        {
            visible = false;
        }
        
        
        if (visible)
        {
            //project all point
            for (int j = 0; j < 4; j++)
            {
                tet.pos[j] = mul(tet.pos[j], persp);
                tet.pos[j] = tet.pos[j] / tet.pos[j].w;
            }
            
            int nb_triangle = 0;


            // First test projection : 
            for (int j = 0; j < potentialProjection; j++)
            {
                float4 p = tet.pos[potential_projection[j][0]];
                
                
                uint faceID = potential_projection[j][1];
                float4 a = tet.pos[faces[faceID][0]];
                float4 b = tet.pos[faces[faceID][1]];
                float4 c = tet.pos[faces[faceID][2]];

                float2 v0 = b.xy - a.xy;
                float2 v1 = c.xy - b.xy;
                float2 v2 = a.xy - c.xy;

                float s0 = cross2D(p.xy - a.xy, v0);
                float s1 = cross2D(p.xy - b.xy, v1);
                float s2 = cross2D(p.xy - c.xy, v2);

                bool isInside = (s0 >= 0 && s1 >= 0 && s2 >= 0) || (s0 <= 0 && s1 <= 0 && s2 <= 0);
                //inside with borders
                if (isInside)
                {

                    float s = s0 + s1 + s2;
                    float lambda0 = s1 / s;
                    float lambda1 = s2 / s;
                    float lambda2 = s0 / s;

                    float z_ = (lambda0 * a.z + lambda1 * b.z + lambda2 * c.z);

                    nb_triangle = 3;

                    proxy.pos[0] = a.xyzz;
                    proxy.pos[1] = b.xyzz;
                    proxy.pos[2] = c.xyzz;
                    
                    proxy.pos[3] = p.z < z_ ? float4(p.xyz, z_) : float4(p.xy, z_, p.z);
                    proxy.point_count = 4;
                }
            }

            if (nb_triangle == 0)
            {
                for (int j = 0; j < potentialCrossing; j++)
                {
                    float4 l0a = tet.pos[edges[potential_intersection[j][0]][0]];
                    float4 l0b = tet.pos[edges[potential_intersection[j][0]][1]];
                    float4 l1a = tet.pos[edges[potential_intersection[j][1]][0]];
                    float4 l1b = tet.pos[edges[potential_intersection[j][1]][1]];

                    float2 p;
                    float2 t;
                    if (lineIntersection(l0a.xy, l0b.xy, l1a.xy, l1b.xy, p, t))
                    {

                    
                        float z0 = (l0a.z) * (1.0 - t[0]) + (l0b.z) * t[0];
                        float z1 = (l1a.z) * (1.0 - t[1]) + (l1b.z) * t[1];


                        proxy.pos[0] = l0a.xyzz;
                        proxy.pos[1] = l1a.xyzz;
                        proxy.pos[2] = l0b.xyzz;
                        proxy.pos[3] = l1b.xyzz;
                        proxy.pos[4] = z0 < z1 ? float4(p.xy, z0, z1) : float4(p.xy, z1, z0);
                        proxy.point_count = 5;
                        nb_triangle = 4;
                    }
                }
            }
        }
    }
    else
    {
        visible = false;
    }
    
    uint vertex_counter = 0;
    uint triangle_counter = 0;

    if (visible)
    {
        // Compute these in order to 
        // call SetMeshOutputCounts
        if (proxy.point_count == 4)
        {
            triangle_counter += 3;
        }
        else if (proxy.point_count == 5)
        {
            triangle_counter += 4;
        }
        vertex_counter += proxy.point_count;
    }


    uint numVerticesEmitted = WaveActiveSum(vertex_counter);
    uint numTrisEmitted = WaveActiveSum(triangle_counter);

    SetMeshOutputCounts(numVerticesEmitted,
                        numTrisEmitted);

    if (visible)
    {    
        uint prefixVertices = WavePrefixSum(vertex_counter);
        uint prefixTris = WavePrefixSum(triangle_counter);

        for (int j = 0; j < proxy.point_count; j++)
        {
            verts[prefixVertices + j].Position = float4(proxy.pos[j].xy, 0, 1);
            verts[prefixVertices + j].A = float4(proxy.pos[j].xy, proxy.pos[j].z, proxy.pos[j].w);
            verts[prefixVertices + j].ExtinctionScale = GetInstanceData(instanceIndex).ExtinctionScale;

        }

        if (proxy.point_count == 4)
        {
            tris[prefixTris + 0] = uint3(0, 1, 3) + prefixVertices.xxx;
            tris[prefixTris + 1] = uint3(1, 2, 3) + prefixVertices.xxx;
            tris[prefixTris + 2] = uint3(2, 0, 3) + prefixVertices.xxx;
        }
        else if (proxy.point_count == 5)
        {
            tris[prefixTris + 0] = uint3(0, 1, 4) + prefixVertices.xxx;
            tris[prefixTris + 1] = uint3(1, 2, 4) + prefixVertices.xxx;
            tris[prefixTris + 2] = uint3(2, 3, 4) + prefixVertices.xxx;
            tris[prefixTris + 3] = uint3(3, 0, 4) + prefixVertices.xxx;
        }
    }
}