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
    float d2 = d * d;
    float u2 = u * u;
    
    float prefix = sigma * 0.2 * sqrt(2 * PI) * u;
    
    float root5 = sqrt(5);
    float fiveRoot2 = 5 * sqrt(2);
    
    float firstExp = fiveRoot2 * d * cosAlpha / u;
    float secondExp = fiveRoot2 * (d * cosAlpha - z + zmin) / u;
    float thirdExp = (50 * d2 * cosAlpha * cosAlpha - 50 * d2) / u2;
    
    float ot = prefix * (erf(firstExp) - erf(secondExp)) * exp(thirdExp);
    if (ot < 0.0005)
    {
        return 0;
    }
    
    return ot;
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
        = 50 * (2 * d * zMinusZmin * cosAlpha - d * d - zMinusZmin2);
    float exponent = numerator / (u * u);
    
    float extinction = sigma * exp(exponent);
    
    if (extinction < 0.0005)
    {
        return 0;
    }
    
    return extinction;
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
    float u,
    float visibility)
{
    float t_v = FadedTransmittanceTv2(zmin, x, d, cosAlpha, sigma, u);
    float sigma_t = Sigma_t(zmin, x, d, cosAlpha, sigma, u);
    float t_l = T_L(zmin, x, zmax, omin, omax);

    return t_v * sigma_t * t_l * visibility;
}

static const float PascalsTriangle[4][4] = 
    {
    {1, -1, -1, -1 },
    {1, 1, -1, -1},
    {1, 2, 1, -1},
    {1, 3, 3, 1 }
};

float Derivative(uint n, float x,
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
    
    for (uint i = 0; i <= n; i++)
    {
        float sign = -1;
        if ((n - i) % 2 == 0)
        {
            sign = 1;
        }
        
        float foo = f(x + i * h,
            zmin,
            zmax,
            omin,
            omax,
            d,
            cosAlpha,
            sigma,
            u,
            1 // TODO: pass visibility through
        );
        
        difference += sign * PascalsTriangle[n][i] * foo;
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
        u,
        1 // TODO: pass visibility through    
        ) * evaluationPoint;
    
    
    float nFactorial = 1;
    
    for (uint n = 1; n < count; n++)
    {
        float derivative = Derivative(n, expansionPoint,
                zmin,
                zmax,
                omin,
                omax,
                d,
                cosAlpha,
                sigma,
                u);
        
        nFactorial *= n;
        
        float base = evaluationPoint - expansionPoint;
        
        float power = BetterPower(base, n + 1);
    
        float denominator = (n + 1.f) * nFactorial;
        
        float multiplier = power / denominator;
        
        integral += derivative * multiplier;
    }                   
    
    return integral;
}

void TaylorSeriesCoefficients(out float coefficients[5], uint count, float expansionPoint,
    float zmin,
    float zmax,
    float omin,
    float omax,
    float d,
    float cosAlpha,
    float sigma,
    float u)
{
    coefficients[0] = f(expansionPoint,
        zmin,
        zmax,
        omin,
        omax,
        d,
        cosAlpha,
        sigma,
        u,
        1 // TODO: pass visibility through
        );
    
    
    float nFactorial = 1;
    
    for (uint n = 1; n < count; n++)
    {
        float derivative = Derivative(n, expansionPoint,
                zmin,
                zmax,
                omin,
                omax,
                d,
                cosAlpha,
                sigma,
                u);
        
        nFactorial *= n;
    
        float denominator = (n + 1.f) * nFactorial;
        
        coefficients[n] = derivative / denominator;
    }    
}

float EvaluateTaylorIntegralCoefficients(float coefficients[5], float count, float evaluationPoint, float expansionPoint)
{
    float integral = coefficients[0] * evaluationPoint;
    
    for (int n = 1; n < count; n++)
    {
        integral += BetterPower(evaluationPoint - expansionPoint, n + 1) * coefficients[n];
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
    
    float coefficients[5];
    
    TaylorSeriesCoefficients(coefficients, count, expansionPoint,
        zmin,
        zmax,
        omin,
        omax,
        d,
        cosAlpha,
        sigma,
        u
    );
    
    float upperLimit = EvaluateTaylorIntegralCoefficients(coefficients, count, zmax, expansionPoint);
    float lowerLimit = EvaluateTaylorIntegralCoefficients(coefficients, count, zmin, expansionPoint);
    
    return upperLimit - lowerLimit;
}

#endif