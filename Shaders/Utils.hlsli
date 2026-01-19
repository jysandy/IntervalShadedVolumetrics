#ifndef __UTILS_HLSLI__
#define __UTILS_HLSLI__

static const float PI = 3.14159265359;

static const float EPSILON = 0.00001;

Texture1D<float> ErfLookupTexture : register(t4, space0);

float erf(float x, SamplerState linearSampler)
{
    const float erfRange = 8.0;
    const float halfRange = erfRange / 2.0;
    
    float u = (x + halfRange) / erfRange;
    u = saturate(u);
    
    return ErfLookupTexture.SampleLevel(linearSampler, u, 0);
}

#endif
