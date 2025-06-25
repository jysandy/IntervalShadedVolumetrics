#ifndef __RENDERING_EQUATION_HLSLI__
#define __RENDERING_EQUATION_HLSLI__

float ZeroCutoff(float v, float e)
{
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

float FadedTransmittanceEquation(
    float zmin,
    float zmax,
    float omin, 
    float omax,
    float d,
    float cosAlpha,
    float sigma,
    float u,
    float epsilon
)
{
    float zmaxMinuszmin = zmax - zmin;
    float innerExp = exp(-omin * sigma * zmax / zmaxMinuszmin + sigma * zmin - omin * sigma * zmin / zmaxMinuszmin);
    float cosAlphaInnerExp = cosAlpha * innerExp;
    float sndInnerExp = exp(sigma * zmax - omin * sigma * zmax / zmaxMinuszmin - omax * sigma * zmin / zmaxMinuszmin);
    float trdInnerExp = exp(-omax * sigma * zmax / zmaxMinuszmin + sigma * zmin - omin * sigma * zmin / zmaxMinuszmin);
    float fthInnerExp = exp(sigma * zmax - omin * sigma * zmax / zmaxMinuszmin - omax * sigma * zmin / zmaxMinuszmin); 
    
    float cosAlphaTrdInnerExp = cosAlpha * trdInnerExp;
    float cosAlphaFthInnerExp = cosAlpha * fthInnerExp;
    
    float omax2 = omax * omax;
    float omin2 = omin * omin;
    float zmax2 = zmax * zmax;
    float zmin2 = zmin * zmin;
    float sigma2 = sigma * sigma;
    float d2 = d * d;
    float u2 = u * u;
    float ominomax = omin * omax;
    float zminzmax = zmin * zmax;
    
    float numeratorSum
        = 2 * omax2 * d * sigma2 * zmax * cosAlphaInnerExp
          - 4 * ominomax * d * sigma2 * zmax * cosAlphaInnerExp
          + 2 * omin2 * d * sigma2 * zmax * cosAlphaInnerExp
          + 4 * omax * d * sigma2 * zmax2 * cosAlphaInnerExp
          - 4 * omin * d * sigma2 * zmax2 * cosAlphaInnerExp
          + 2 * d * sigma2 * zmax2 * zmax * cosAlphaInnerExp
          - 2 * omax2 * d * sigma2 * zmin * cosAlphaInnerExp
          + 4 * ominomax * d * sigma2 * zmin * cosAlphaInnerExp
          - 2 * omin2 * d * sigma2 * zmin * cosAlphaInnerExp
          - 8 * omax * d * sigma2 * zminzmax * cosAlphaInnerExp
          + 8 * omin * d * sigma2 * zminzmax * cosAlphaInnerExp
          - 6 * d * sigma2 * zmax * zminzmax * cosAlphaInnerExp
          + 4 * omax * d * sigma2 * zmin2 * cosAlphaInnerExp
          - 4 * omin * d * sigma2 * zmin2 * cosAlphaInnerExp
          + 6 * d * sigma2 * zmin * zminzmax * cosAlphaInnerExp
          - 2 * d * sigma2 * zmin * zmin2 * cosAlphaInnerExp
          - omax2 * d2 * sigma2 * sndInnerExp
          + 2 * ominomax * d2 * sigma2 * sndInnerExp
          - omin2 * d2 * sigma2 * sndInnerExp
          + omax2 * sigma2 * u2 * sndInnerExp
          - 2 * ominomax * sigma2 * u2 * sndInnerExp
          + omin2 * sigma2 * u2 * sndInnerExp
          - 2 * omax * d2 * sigma2 * zmax * sndInnerExp
          + 2 * omin * d2 * sigma2 * zmax * sndInnerExp
          + 2 * omax * sigma2 * u2 * zmax * sndInnerExp
          - 2 * omin * sigma2 * u2 * zmax * sndInnerExp
          - d2 * sigma2 * zmax2 * sndInnerExp
          + sigma2 * u2 * zmax2 * sndInnerExp
          + 2 * omax * d2 * sigma2 * zmin * sndInnerExp
          - 2 * omin * d2 * sigma2 * zmin * sndInnerExp
          - 2 * omax * sigma2 * u2 * zmin * sndInnerExp
          + 2 * omin * sigma2 * u2 * zmin * sndInnerExp
          + 2 * d2 * sigma2 * zminzmax * sndInnerExp
          - 2 * sigma2 * u2 * zminzmax * sndInnerExp
          - d2 * sigma2 * zmin2 * sndInnerExp
          + sigma2 * u2 * zmin2 * sndInnerExp
          + omax2 * d2 * sigma2 * trdInnerExp
          - 2 * ominomax * d2 * sigma2 * trdInnerExp
          + omin2 * d2 * sigma2 * trdInnerExp
          - omax2 * sigma2 * u2 * trdInnerExp
          + 2 * ominomax * sigma2 * u2 * trdInnerExp
          - omin2 * sigma2 * u2 * trdInnerExp
          + 2 * omax * d2 * sigma2 * zmax * trdInnerExp
          - 2 * omin * d2 * sigma2 * zmax * trdInnerExp
          - 2 * omax * sigma2 * u2 * zmax * trdInnerExp
          + 2 * omin * sigma2 * u2 * zmax * trdInnerExp
          - omax2 * sigma2 * zmax2 * trdInnerExp
          + 2 * ominomax * sigma2 * zmax2 * trdInnerExp
          - omin2 * sigma2 * zmax2 * trdInnerExp
          + d2 * sigma2 * zmax2 * trdInnerExp
          - sigma2 * u2 * zmax2 * trdInnerExp
          - 2 * omax * sigma2 * zmax * zmax2 * trdInnerExp
          + 2 * omin * sigma2 * zmax * zmax2 * trdInnerExp
          - sigma2 * zmax2 * zmax2 * trdInnerExp
          - 2 * omax * d2 * sigma2 * zmin * trdInnerExp
          + 2 * omin * d2 * sigma2 * zmin * trdInnerExp
          + 2 * omax * sigma2 * u2 * zmin * trdInnerExp
          - 2 * omin * sigma2 * u2 * zmin * trdInnerExp
          + 2 * omax2 * sigma2 * zminzmax * trdInnerExp
          - 4 * ominomax * sigma2 * zminzmax * trdInnerExp
          + 2 * omin2 * sigma2 * zminzmax * trdInnerExp
          - 2 * d2 * sigma2 * zminzmax * trdInnerExp
          + 2 * sigma2 * u2 * zminzmax * trdInnerExp
          + 6 * omax * sigma2 * zmax * zminzmax * trdInnerExp
          - 6 * omin * sigma2 * zmax * zminzmax * trdInnerExp
          + 4 * sigma2 * zmax * zminzmax * trdInnerExp
          - omax2 * sigma2 * zmin2 * trdInnerExp
          + 2 * ominomax * sigma2 * zmin2 * trdInnerExp
          - omin2 * sigma2 * zmin2 * trdInnerExp
          + d2 * sigma2 * zmin2 * trdInnerExp
          - sigma2 * u2 * zmin2 * trdInnerExp
          - 6 * omax * sigma2 * zminzmax * zmin * trdInnerExp
          + 6 * omin * sigma2 * zminzmax * zmin * trdInnerExp
          - 6 * sigma2 * zmin2 * zmax2 * trdInnerExp
          + 2 * omax * sigma2 * zmin * zmin2 * trdInnerExp
          - 2 * omin * sigma2 * zmin * zmin2 * trdInnerExp
          + 4 * sigma2 * zminzmax * zmin * trdInnerExp
          - sigma2 * zmin2 * zmin2 * trdInnerExp
          - 2 * omax * d * sigma * zmax * cosAlphaFthInnerExp
          + 2 * omin * d * sigma * zmax * cosAlphaFthInnerExp
          - 2 * d * sigma * zmax2 * cosAlphaFthInnerExp
          + 2 * omax * d * sigma * zmin * cosAlphaFthInnerExp
          - 2 * omin * d * sigma * zmin * cosAlphaFthInnerExp
          + 4 * d * sigma * zminzmax * cosAlphaFthInnerExp
          - 2 * d * zmin2 * cosAlphaFthInnerExp
          + 2 * omax * d * sigma * zmax * cosAlphaTrdInnerExp
          - 2 * omin * d * sigma * zmax * cosAlphaTrdInnerExp
          + 2 * d * sigma * zmax2 * cosAlphaTrdInnerExp
          - 2 * omax * d * sigma * zmin * cosAlphaTrdInnerExp
          + 2 * omin * d * sigma * zmin * cosAlphaTrdInnerExp
          - 4 * d * sigma * zminzmax * cosAlphaTrdInnerExp
          + 2 * d * sigma * zmin2 * cosAlphaTrdInnerExp
          - 2 * omax * sigma * zmax2 * trdInnerExp
          + 2 * omin * sigma * zmax2 * trdInnerExp
          - 2 * sigma * zmax * zmax2 * trdInnerExp
          + 4 * omax * sigma * zminzmax * trdInnerExp
          - 4 * omin * sigma * zminzmax * trdInnerExp
          + 6 * sigma * zmax2 * zmin * trdInnerExp
          - 2 * omax * sigma * zmin2 * trdInnerExp
          + 2 * omin * sigma * zmin2 * trdInnerExp
          - 6 * sigma * zmax * zmin2 * trdInnerExp
          + 2 * sigma * zmin * zmin2 * trdInnerExp
          + 2 * zmax2 * fthInnerExp
          - 4 * zminzmax * fthInnerExp
          + 2 * zmin2 * fthInnerExp
          - 2 * zmax2 * trdInnerExp
          + 4 * zminzmax * trdInnerExp
          - 2 * zmin2 * trdInnerExp;
    float numerator = numeratorSum * zmaxMinuszmin *
        exp(-omin * sigma - sigma * zmax + omin * sigma * zmax / zmaxMinuszmin + omax * sigma * zmin / zmaxMinuszmin);
    
    float denominatorCubeRoot = omax - omin + zmaxMinuszmin;
    float denominator = ZeroCutoff(pow(denominatorCubeRoot, 3) * sigma2 * u2, epsilon);
    
    // Output must be non-negative
    denominator = MatchSign(denominator, numerator);
    
    return numerator / denominator;
}

float FadedTransmittanceTv(
    float zmin,
    float zmax,
    float omin,
    float omax,
    float d,
    float cosAlpha,
    float sigma,
    float u,
    float epsilon
)
{
    float omax2 = omax * omax;
    float omin2 = omin * omin;
    float zmax2 = zmax * zmax;
    float zmin2 = zmin * zmin;
    float sigma2 = sigma * sigma;
    float d2 = d * d;
    float u2 = u * u;
    float ominomax = omin * omax;
    float zminzmax = zmin * zmax;
    
    float numerator =
        3 * d * zmax2 * cosAlpha
        + 3 * d * zmin2 * cosAlpha
        - zmax * zmax2
        - 3 * zmax * zmin2
        + zmin * zmin2
        + 3 * (d2 - u2) * zmax
        - 3 * (2 * d * zmax * cosAlpha - zmax2) * zmin
        - 3 * (d2 - u2) * zmin;
    
    numerator *= sigma;
    
    return exp(numerator / 3 * u2);
}

#endif