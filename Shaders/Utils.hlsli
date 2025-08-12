#ifndef __UTILS_HLSLI__
#define __UTILS_HLSLI__

static const min16float PI = 3.14159265359;

static const min16float EPSILON = 0.00001;

min16float erf(float x)
{
    // Early return for large |x|.
    if (abs(x) >= 4.0)
    {
        return min16float(asfloat((asuint(x) & 0x80000000) ^ asuint(1.0)));
    }
    // Polynomial approximation based on https://forums.developer.nvidia.com/t/optimized-version-of-single-precision-error-function-erff/40977

    if (abs(x) > 1.0)
    {
        const float A1 = 1.628459513;
        const float A2 = 9.15674746e-1;
        const float A3 = 1.54329389e-1;
        const float A4 = -3.51759829e-2;
        const float A5 = 5.66795561e-3;
        const float A6 = -5.64874616e-4;
        const float A7 = 2.58907676e-5;
        float a = abs(x);
        float y = 1.0 - exp2(-(((((((A7 * a + A6) * a + A5) * a + A4) * a + A3) * a + A2) * a + A1) * a));
        return min16float(asfloat((asuint(x) & 0x80000000) ^ asuint(y)));
    }
    else
    {
        const float A1 = 1.128379121;
        const float A2 = -3.76123011e-1;
        const float A3 = 1.12799220e-1;
        const float A4 = -2.67030653e-2;
        const float A5 = 4.90735564e-3;
        const float A6 = -5.58853149e-4;
        float x2 = x * x;
        return min16float((((((A6 * x2 + A5) * x2 + A4) * x2 + A3) * x2 + A2) * x2 + A1) * x);
    }
}

#endif