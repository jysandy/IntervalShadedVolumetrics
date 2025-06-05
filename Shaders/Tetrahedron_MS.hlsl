// Adapted from https://github.com/ThibaultTricard/Interval-Shading/blob/b45ea6b9814d0a88655a380795250ad3202651d1/src/shader/singleTet/mesh.mesh


#include "TetrahedronPipeline.hlsli"
#include "Quaternion.hlsli"

#define X 1

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

// Unused for now
clipedTet_t clipTet(tet_t tet, float near)
{
    bool clip[4];
    uint clip_count = 0;
    
    clip[0] = tet.pos[0].z < near;
    clip_count += int(clip[0]);
    clip[1] = tet.pos[1].z < near;
    clip_count += int(clip[1]);
    clip[2] = tet.pos[2].z < near;
    clip_count += int(clip[2]);
    clip[3] = tet.pos[3].z < near;
    clip_count += int(clip[3]);

    clipedTet_t ctet;
    if (clip_count == 0)
    {
        ctet.tetCount = 1;
        ctet.tets[0] = tet;
        return ctet;
    }
    if (clip_count == 4)
    {
        ctet.tetCount = 0;
        return ctet;
    }

    bool edgeClip[6];
    float4 clipPoint[6];
    float4 otherPoint[6];
    for (int i = 0; i < 6; i++)
    {
        int i0 = edges[i][0];
        int i1 = edges[i][1];
        edgeClip[i] = (clip[i0] && !clip[i1]) || (!clip[i0] && clip[i1]);
        if (edgeClip[i])
        {
            float4 a = clip[i0] ? tet.pos[i0] : tet.pos[i1];
            float4 b = clip[i0] ? tet.pos[i1] : tet.pos[i0];

            float t = (near - a.z) / (b.z - a.z);
            clipPoint[i] = a + (b - a) * t;
            otherPoint[i] = b;
        }
    }

    
    if (clip_count == 1)
    {
        //one clip : prism
        ctet.tetCount = 3;
        prism_t p;
        int count = 0;
        for (int i = 0; i < 6; i++)
        {
            if (edgeClip[i])
            {
                p.pos[count] = clipPoint[i];
                p.pos[count + 3] = otherPoint[i];
                count++;
            }
        }
        
        // tet 1
        ctet.tets[0].pos[0] = p.pos[0];
        ctet.tets[0].pos[1] = p.pos[1];
        ctet.tets[0].pos[2] = p.pos[2];
        ctet.tets[0].pos[3] = p.pos[3];

        // tet 1
        ctet.tets[1].pos[0] = p.pos[1];
        ctet.tets[1].pos[1] = p.pos[2];
        ctet.tets[1].pos[2] = p.pos[3];
        ctet.tets[1].pos[3] = p.pos[5];

        // tet 2
        ctet.tets[2].pos[0] = p.pos[1];
        ctet.tets[2].pos[1] = p.pos[3];
        ctet.tets[2].pos[2] = p.pos[4];
        ctet.tets[2].pos[3] = p.pos[5];
    }
    else if (clip_count == 2)
    {
        //two clip : prism
        ctet.tetCount = 3;
        prism_t p;
        int countNoClip = 0;
        int noclip[2];
        int cliped[2];
        int countClip = 0;
        for (int i = 0; i < 4; i++)
        {
            if (!clip[i])
            {
                p.pos[countNoClip * 3] = tet.pos[i];
                noclip[countNoClip] = i;
                countNoClip++;
            }
            else
            {
                cliped[countClip] = i;
                countClip++;
            }
        }

        if (cliped[1] < cliped[0])
        {
            int tmp = cliped[0];
            cliped[0] = cliped[1];
            cliped[1] = tmp;
        }

        for (int i = 0; i < 6; i++)
        {
            if (edgeClip[i])
            {
                bool eNoClip1 = edges[i][0] == noclip[1] || edges[i][1] == noclip[1];
                bool eCliped1 = edges[i][0] == cliped[1] || edges[i][1] == cliped[1];

                int index = int(eNoClip1) * 3 + int(eCliped1) + 1;

                p.pos[index] = clipPoint[i];
            }
        }

        // tet 0
        ctet.tets[0].pos[0] = p.pos[0];
        ctet.tets[0].pos[1] = p.pos[1];
        ctet.tets[0].pos[2] = p.pos[2];
        ctet.tets[0].pos[3] = p.pos[3];

        // tet 1
        ctet.tets[1].pos[0] = p.pos[1];
        ctet.tets[1].pos[1] = p.pos[2];
        ctet.tets[1].pos[2] = p.pos[3];
        ctet.tets[1].pos[3] = p.pos[5];

        // tet 2
        ctet.tets[2].pos[0] = p.pos[1];
        ctet.tets[2].pos[1] = p.pos[3];
        ctet.tets[2].pos[2] = p.pos[4];
        ctet.tets[2].pos[3] = p.pos[5];

    }
    else if (clip_count == 3)
    {
        //three clip : prism
        ctet.tetCount = 1;

        int count = 0;
        for (int i = 0; i < 6; i++)
        {
            if (edgeClip[i])
            {
                ctet.tets[0].pos[count] = clipPoint[i];
                count++;
            }
        }
        for (int i = 0; i < 4; i++)
        {
            if (!clip[i])
            {
                ctet.tets[0].pos[count] = tet.pos[i];
            }
        }
    }
    

    return ctet;
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


[numthreads(X, 1, 1)]
[outputtopology("triangle")]
void Tetrahedron_MS(
    in uint gtid : SV_GroupIndex,
    in uint3 gid : SV_GroupID,
    out indices uint3 tris[80],
    out vertices VertexType verts[80]
)
{
    uint instanceIndex = gid.x + gtid;
    
    tetIndices_t indices = tet[0];

    float4x4 scale = float4x4(
        2, 0, 0, 0,
        0, 2, 0, 0,
        0, 0, 2, 0,
        0, 0, 0, 1
    );
    
    float animationScale = 0.5 * (1 + sin(4 * g_totalTime + 69 * instanceIndex));
    animationScale = lerp(0.8, 1, animationScale);
    
    float timeJitter = frac(g_totalTime) * 26.8;
    
    float4x4 rotation = QuatTo4x4(QuatFromAxisAngle(float3(0, 0, 1), 
        1 * (g_totalTime * 256.f + timeJitter) 
        + 69 * instanceIndex));
    float4x4 model = mul(scale, rotation);
    
    model._41_42_43 = float3(animationScale.xx, 1) * Instances[instanceIndex].WorldPosition;
    
    float4x4 modelView = mul(model, view);
    
    tet_t tet;
    tet.pos[0] = mul(coords[indices.index[0]], modelView);
    tet.pos[1] = mul(coords[indices.index[1]], modelView);
    tet.pos[2] = mul(coords[indices.index[2]], modelView);
    tet.pos[3] = mul(coords[indices.index[3]], modelView);

    //clip test
    float bias = nearplane * 0.1;
    
    clipedTet_t ctet;
    ctet.tetCount = 1;
    ctet.tets[0] = tet;

    if (
        tet.pos[0].z < nearplane + bias
        || tet.pos[1].z < nearplane + bias
        || tet.pos[2].z < nearplane + bias
        || tet.pos[3].z < nearplane + bias
        )
    {
        ctet.tetCount = 0;        
    }
    
    proxy_t proxies[3];
    for (int i = 0; i < ctet.tetCount; i++)
    {
        
        //project all point
        for (int j = 0; j < 4; j++)
        {
            ctet.tets[i].pos[j] = mul(ctet.tets[i].pos[j], persp);
            ctet.tets[i].pos[j] = ctet.tets[i].pos[j] / ctet.tets[i].pos[j].w;
        }
        
        int nb_triangle = 0;


        // First test projection : 
        for (int j = 0; j < potentialProjection; j++)
        {
            float4 p = ctet.tets[i].pos[potential_projection[j][0]];
            
            
            uint faceID = potential_projection[j][1];
            float4 a = ctet.tets[i].pos[faces[faceID][0]];
            float4 b = ctet.tets[i].pos[faces[faceID][1]];
            float4 c = ctet.tets[i].pos[faces[faceID][2]];

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

                proxies[i].pos[0] = a.xyzz;
                proxies[i].pos[1] = b.xyzz;
                proxies[i].pos[2] = c.xyzz;
                
                proxies[i].pos[3] = p.z < z_ ? float4(p.xyz, z_) : float4(p.xy, z_, p.z);
                proxies[i].point_count = 4;
            }
        }

        if (nb_triangle != 0)
        {
            continue;
        }
        

        for (int j = 0; j < potentialCrossing; j++)
        {
            float4 l0a = ctet.tets[i].pos[edges[potential_intersection[j][0]][0]];
            float4 l0b = ctet.tets[i].pos[edges[potential_intersection[j][0]][1]];
            float4 l1a = ctet.tets[i].pos[edges[potential_intersection[j][1]][0]];
            float4 l1b = ctet.tets[i].pos[edges[potential_intersection[j][1]][1]];

            float2 p;
            float2 t;
            if (lineIntersection(l0a.xy, l0b.xy, l1a.xy, l1b.xy, p, t))
            {

                
                float z0 = (l0a.z) * (1.0 - t[0]) + (l0b.z) * t[0];
                float z1 = (l1a.z) * (1.0 - t[1]) + (l1b.z) * t[1];


                proxies[i].pos[0] = l0a.xyzz;
                proxies[i].pos[1] = l1a.xyzz;
                proxies[i].pos[2] = l0b.xyzz;
                proxies[i].pos[3] = l1b.xyzz;
                proxies[i].pos[4] = z0 < z1 ? float4(p.xy, z0, z1) : float4(p.xy, z1, z0);
                proxies[i].point_count = 5;
                nb_triangle = 4;
            }
        }
    }

    // Compute these in order to 
    // call SetMeshOutputCounts
    int vertex_counter = 0;
    int triangle_counter = 0;
    for (int i = 0; i < ctet.tetCount; i++)
    {
        if (proxies[i].point_count == 4)
        {
            triangle_counter++;
            triangle_counter++;
            triangle_counter++;
        }
        else if (proxies[i].point_count == 5)
        {
            triangle_counter++;
            triangle_counter++;
            triangle_counter++;
            triangle_counter++;
        }
        vertex_counter += proxies[i].point_count;
    }

    SetMeshOutputCounts(vertex_counter, triangle_counter);
    
    // Now we can write to verts and tris
    vertex_counter = 0;
    triangle_counter = 0;
    for (int i = 0; i < ctet.tetCount; i++)
    {

        for (int j = 0; j < proxies[i].point_count; j++)
        {
            verts[vertex_counter + j].Position = float4(proxies[i].pos[j].xy, 0, 1);
            verts[vertex_counter + j].A = float4(proxies[i].pos[j].xy, proxies[i].pos[j].z, proxies[i].pos[j].w);
        }

        if (proxies[i].point_count == 4)
        {
            tris[triangle_counter++] = uint3(0, 1, 3) + vertex_counter;
            tris[triangle_counter++] = uint3(1, 2, 3) + vertex_counter;
            tris[triangle_counter++] = uint3(2, 0, 3) + vertex_counter;
        }
        else if (proxies[i].point_count == 5)
        {
            tris[triangle_counter++] = uint3(0, 1, 4) + vertex_counter;
            tris[triangle_counter++] = uint3(1, 2, 4) + vertex_counter;
            tris[triangle_counter++] = uint3(2, 3, 4) + vertex_counter;
            tris[triangle_counter++] = uint3(3, 0, 4) + vertex_counter;
        }
        vertex_counter += proxies[i].point_count;
    }
}