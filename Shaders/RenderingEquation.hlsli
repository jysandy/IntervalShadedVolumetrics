#ifndef __RENDERING_EQUATION_HLSLI__
#define __RENDERING_EQUATION_HLSLI__

#include "Utils.hlsli"

float ZeroCutoff(float v, float e)
{
    if (isnan(v))
    {
        return e;
    }
    
    if (v >= 0)
    {
        return max(e, v);
    }
    
    return min(-e, v);
}

float3 ZeroCutoff(float3 v, float e)
{
    return float3(
        ZeroCutoff(v.x, e),
        ZeroCutoff(v.y, e),
        ZeroCutoff(v.z, e)
    );
}

float MatchSign(float v, float m)
{
    if (sign(v) != sign(m))
    {
        return -v;
    }

    return v;
}

float3 MatchSign(float3 v, float3 m)
{
    return float3(
        MatchSign(v.x, m.x),
        MatchSign(v.y, m.y),
        MatchSign(v.z, m.z)
    );
}

float factorial(float n)
{
    if (n == 0)
    {
        return 1;
    }
    
    float fac = 1;
    for (uint i = 1; i <= n; i++)
    {
        fac *= i;
    }
    
    return fac;
}

float FadedOpticalThickness(
    float zmin,
    float z,
    float d,
    float cosAlpha,
    float sigma,
    float u
)
{
    float sigma2 = sigma * sigma;
    float d2 = d * d;
    float u2 = u * u;
    
    float prefix = sigma * 0.1 * sqrt(5 * PI) * u;
    
    float root5 = sqrt(5);
    
    float firstExp = root5 * d * cosAlpha / u;
    float secondExp = root5 * (d * cosAlpha - z + zmin) / u;
    float thirdExp = (5 * d2 * cosAlpha * cosAlpha - 5 * d2) / u2;
    
    return prefix * (erf(firstExp) - erf(secondExp)) * exp(thirdExp);
}

float FadedTransmittanceTv2(
    float zmin,
    float z,
    float d,
    float cosAlpha,
    float sigma,
    float u
)
{
    return exp(-FadedOpticalThickness(zmin, z, d, cosAlpha, sigma, u));
}

float Sigma_t(
    float zmin,
    float z,
    float d,
    float cosAlpha,
    float sigma,
    float u
)
{
    float zMinusZmin = z - zmin;
    float zMinusZmin2 = zMinusZmin * zMinusZmin;
    
    float numerator
        = 5 * (2 * d * zMinusZmin * cosAlpha - d * d - zMinusZmin2);
    float exponent = numerator / (u * u);
    
    return sigma * exp(exponent);
}

float T_L(
    float zmin,
    float z,
    float zmax,
    float omin,
    float omax
)
{
    float omaxMinusOmin = omax - omin;
    float zmaxMinusZmin = zmax - zmin;
    float zMinusZmin = z - zmin;
    
    return exp(-omin - (omaxMinusOmin * zMinusZmin / ZeroCutoff(zmaxMinusZmin, 0.00001)));
}

float f(float x,
    float zmin,
    float zmax,
    float omin,
    float omax,
    float d,
    float cosAlpha,
    float sigma,
    float u)
{
    float t_v = FadedTransmittanceTv2(zmin, x, d, cosAlpha, sigma, u);
    float sigma_t = Sigma_t(zmin, x, d, cosAlpha, sigma, u);
    float t_l = T_L(zmin, x, zmax, omin, omax);

    return t_v * sigma_t * t_l;
}

float DerivativeDivNFactorial(uint n, float x,
    float zmin,
    float zmax,
    float omin,
    float omax,
    float d,
    float cosAlpha,
    float sigma,
    float u)
{
    const float h = 0.001;
    
    float difference = 0;
    
    float iFactorial = 1;
    for (uint i = 0; i <= n; i++)
    {
        float sign = -1;
        if ((n - i) % 2 == 0)
        {
            sign = 1;
        }
        
        iFactorial *= max(i, 1);
        float nMinusiFactorial = factorial(n - i);
        
        float foo = f(x + i * h,
            zmin,
            zmax,
            omin,
            omax,
            d,
            cosAlpha,
            sigma,
            u
        );
        
        difference += sign * foo / (iFactorial * nMinusiFactorial);
    }

    return difference / ZeroCutoff(pow(h, n), 0.0000001);
}

float BetterPower(float base, uint y)
{
    if (y == 0)
    {
        return 1;
    }
    
    float result = 1;
    
    for (uint i = 0; i < y; i++)
    {
        result *= base;
    }
    
    return result;
}

float TaylorSeriesAntiderivative(uint count, float evaluationPoint, float expansionPoint,
    float zmin,
    float zmax,
    float omin,
    float omax,
    float d,
    float cosAlpha,
    float sigma,
    float u)
{
    float integral = f(expansionPoint,
        zmin,
        zmax,
        omin,
        omax,
        d,
        cosAlpha,
        sigma,
        u) * evaluationPoint;
    
    for (uint n = 1; n < count; n++)
    {
        float derivative = DerivativeDivNFactorial(n, expansionPoint,
                zmin,
                zmax,
                omin,
                omax,
                d,
                cosAlpha,
                sigma,
                u);
        
        float base = evaluationPoint - expansionPoint;
        
        float power = BetterPower(base, n + 1);
    
        float denominator = (n + 1.f);
        
        float multiplier = power / denominator;
        
        integral += derivative * multiplier;
    }                   
    
    return integral;
}

float IntegrateTaylorSeries(uint count,
    float zmin,
    float zmax,
    float omin,
    float omax,
    float d,
    float cosAlpha,
    float sigma,
    float u
)
{
    float expansionPoint = (zmin + zmax) / 2.f;
    
    float upperLimit = TaylorSeriesAntiderivative(count, zmax, expansionPoint,
        zmin,
        zmax,
        omin,
        omax,
        d,
        cosAlpha,
        sigma,
        u
    );
    
    float lowerLimit = TaylorSeriesAntiderivative(count, zmin, expansionPoint,
        zmin,
        zmax,
        omin,
        omax,
        d,
        cosAlpha,
        sigma,
        u
    );
    
    return upperLimit - lowerLimit;
}

#endif