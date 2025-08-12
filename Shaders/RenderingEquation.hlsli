#ifndef __RENDERING_EQUATION_HLSLI__
#define __RENDERING_EQUATION_HLSLI__

#include "Utils.hlsli"

min16float ZeroCutoff(min16float v, min16float e)
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

min16float3 ZeroCutoff(min16float3 v, min16float e)
{
    return min16float3(
        ZeroCutoff(v.x, e),
        ZeroCutoff(v.y, e),
        ZeroCutoff(v.z, e)
    );
}

min16float MatchSign(min16float v, min16float m)
{
    if (sign(v) != sign(m))
    {
        return -v;
    }

    return v;
}

min16float3 MatchSign(min16float3 v, min16float3 m)
{
    return min16float3(
        MatchSign(v.x, m.x),
        MatchSign(v.y, m.y),
        MatchSign(v.z, m.z)
    );
}

uint factorial(uint n)
{
    if (n == 0)
    {
        return 1;
    }
    
    uint fac = 1;
    for (uint i = 1; i <= n; i++)
    {
        fac *= i;
    }
    
    return fac;
}

min16float FadedOpticalThickness(
    min16float zmin,
    min16float z,
    min16float d,
    min16float cosAlpha,
    min16float sigma,
    min16float u
)
{
    min16float d2 = d * d;
    min16float u2 = u * u;
    
    min16float prefix = sigma * 0.2 * sqrt(2 * PI) * u;
    
    min16float root5 = sqrt(5.0);
    min16float fiveRoot2 = 5 * sqrt(2.0);
    
    min16float firstExp = fiveRoot2 * d * cosAlpha / u;
    min16float secondExp = fiveRoot2 * (d * cosAlpha - z + zmin) / u;
    min16float thirdExp = (50 * d2 * cosAlpha * cosAlpha - 50 * d2) / u2;
    
    min16float ot = prefix * (erf(firstExp) - erf(secondExp)) * exp(thirdExp);
    if (ot < 0.0005)
    {
        return 0;
    }
    
    return ot;
}

min16float FadedTransmittanceTv2(
    min16float zmin,
    min16float z,
    min16float d,
    min16float cosAlpha,
    min16float sigma,
    min16float u
)
{
    return exp(-FadedOpticalThickness(zmin, z, d, cosAlpha, sigma, u));
}

min16float Sigma_t(
    min16float zmin,
    min16float z,
    min16float d,
    min16float cosAlpha,
    min16float sigma,
    min16float u
)
{
    min16float zMinusZmin = z - zmin;
    min16float zMinusZmin2 = zMinusZmin * zMinusZmin;
    
    min16float numerator
        = 50 * (2 * d * zMinusZmin * cosAlpha - d * d - zMinusZmin2);
    min16float exponent = numerator / (u * u);
    
    min16float extinction = sigma * exp(exponent);
    
    return extinction;
}

min16float T_L(
    min16float zmin,
    min16float z,
    min16float zmax,
    min16float omin,
    min16float omax
)
{
    min16float omaxMinusOmin = omax - omin;
    min16float zmaxMinusZmin = zmax - zmin;
    min16float zMinusZmin = z - zmin;
    
    return exp(-omin - (omaxMinusOmin * zMinusZmin / ZeroCutoff(zmaxMinusZmin, 0.00001)));
}

min16float f(min16float x,
    min16float zmin,
    min16float zmax,
    min16float omin,
    min16float omax,
    min16float d,
    min16float cosAlpha,
    min16float sigma,
    min16float u,
    min16float visibility)
{
    min16float t_v = FadedTransmittanceTv2(zmin, x, d, cosAlpha, sigma, u);
    min16float sigma_t = Sigma_t(zmin, x, d, cosAlpha, sigma, u);
    min16float t_l = T_L(zmin, x, zmax, omin, omax);

    return t_v * sigma_t * t_l * visibility;
}

static const min16float PascalsTriangle[4][4] = 
    {
    {1, -1, -1, -1 },
    {1, 1, -1, -1},
    {1, 2, 1, -1},
    {1, 3, 3, 1 }
};

min16float Derivative(uint n, min16float x,
    min16float zmin,
    min16float zmax,
    min16float omin,
    min16float omax,
    min16float d,
    min16float cosAlpha,
    min16float sigma,
    min16float u)
{
    const min16float h = 0.001;
    
    min16float difference = 0;
    
    for (int i = 0; i <= n; i++)
    {
        min16float sign = -1;
        if ((n - i) % 2 == 0)
        {
            sign = 1;
        }
        
        min16float foo = f(x + min16float(i) * h,
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

    return difference / ZeroCutoff(pow(h, min16float(n)), 0.0000001);
}

min16float BetterPower(min16float base, uint y)
{
    if (y == 0)
    {
        return 1;
    }
    
    min16float result = 1;
    
    for (uint i = 0; i < y; i++)
    {
        result *= base;
    }
    
    return result;
}

min16float TaylorSeriesAntiderivative(uint count, min16float evaluationPoint, min16float expansionPoint,
    min16float zmin,
    min16float zmax,
    min16float omin,
    min16float omax,
    min16float d,
    min16float cosAlpha,
    min16float sigma,
    min16float u)
{
    min16float integral = f(expansionPoint,
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
    
    
    min16float nFactorial = 1;
    
    for (min16float n = 1; n < count; n++)
    {
        min16float derivative = Derivative(n, expansionPoint,
                zmin,
                zmax,
                omin,
                omax,
                d,
                cosAlpha,
                sigma,
                u);
        
        nFactorial *= min16float(n);
        
        min16float base = evaluationPoint - expansionPoint;
        
        min16float power = BetterPower(base, n + 1);
    
        min16float denominator = (n + 1) * nFactorial;
        
        min16float multiplier = power / denominator;
        
        integral += derivative * multiplier;
    }                   
    
    return integral;
}

void TaylorSeriesCoefficients(out min16float coefficients[5], uint count, min16float expansionPoint,
    min16float zmin,
    min16float zmax,
    min16float omin,
    min16float omax,
    min16float d,
    min16float cosAlpha,
    min16float sigma,
    min16float u)
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
    
    
    min16float nFactorial = 1;
    
    for (uint n = 1; n < count; n++)
    {
        min16float derivative = Derivative(n, expansionPoint,
                zmin,
                zmax,
                omin,
                omax,
                d,
                cosAlpha,
                sigma,
                u);
        
        nFactorial *= n;
    
        min16float denominator = (n + 1.f) * nFactorial;
        
        coefficients[n] = derivative / denominator;
    }    
}

min16float EvaluateTaylorIntegralCoefficients(min16float coefficients[5], min16float count, min16float evaluationPoint, min16float expansionPoint)
{
    min16float integral = coefficients[0] * evaluationPoint;
    
    for (min16uint n = 1; n < count; n++)
    {
        integral += BetterPower(evaluationPoint - expansionPoint, n + 1) * coefficients[n];
    }

    return integral;
}

min16float IntegrateTaylorSeries(uint count,
    min16float zmin,
    min16float zmax,
    min16float omin,
    min16float omax,
    min16float d,
    min16float cosAlpha,
    min16float sigma,
    min16float u
)
{
    min16float expansionPoint = (zmin + zmax) / 2.f;
    
    min16float coefficients[5];
    
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
    
    min16float upperLimit = EvaluateTaylorIntegralCoefficients(coefficients, count, zmax, expansionPoint);
    min16float lowerLimit = EvaluateTaylorIntegralCoefficients(coefficients, count, zmin, expansionPoint);
    
    return upperLimit - lowerLimit;
}

#endif