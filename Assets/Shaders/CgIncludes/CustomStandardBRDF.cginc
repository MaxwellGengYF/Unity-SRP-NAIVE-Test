
#ifndef CUSTOM_STANDARD_BRDF_INCLUDED
#define CUSTOM_STANDARD_BRDF_INCLUDED

#include "UnityCG.cginc"
#include "UnityStandardConfig.cginc"
#include "UnityLightingCommon.cginc"

//-----------------------------------------------------------------------------
// Helper to convert smoothness to roughness
//-----------------------------------------------------------------------------

#define PerceptualRoughnessToRoughness(perceptualRoughness) perceptualRoughness * perceptualRoughness


#define RoughnessToPerceptualRoughness(roughness) sqrt(roughness)


#define SmoothnessToPerceptualRoughness(smoothness) (1 - smoothness)

// Smoothness is the user facing name
// it should be perceptualSmoothness but we don't want the user to have to deal with this name
inline half SmoothnessToRoughness(half smoothness)
{
    smoothness = 1 - smoothness;
    return smoothness * smoothness;
}



//-------------------------------------------------------------------------------------

inline float Pow4 (float x)
{
    float x2 = x * x;
    return x2 * x2;
}

inline float2 Pow4 (float2 x)
{
    float2 x2 = x * x;
    return x2 * x2;
}

inline float3 Pow4 (float3 x)
{
    float3 x2 = x * x;
    return x2 * x2;
}

inline float4 Pow4 (float4 x)
{
    float4 x2 = x * x;
    return x2 * x2;
}

// Pow5 uses the same amount of instructions as generic pow(), but has 2 advantages:
// 1) better instruction pipelining
// 2) no need to worry about NaNs
inline float Pow5 (float x)
{
    float x2 = x * x;
    return x2 * x2 * x;
}

inline float2 Pow5 (float2 x)
{
    float2 x2 = x * x;
    return x2 * x2 * x;
}

inline float3 Pow5 (float3 x)
{
    float3 x2 = x * x;
    return x2 * x2 * x;
}

inline float4 Pow5 (float4 x)
{
    float4 x2 = x * x;
    return x2 * x2 * x;
}

inline half3 FresnelTerm (half3 F0, half cosA)
{
    half t = Pow5 (1 - cosA);   // ala Schlick interpoliation
    return F0 + (1-F0) * t;
}
inline half3 FresnelLerp (half3 F0, half3 F90, half cosA)
{
    half t = Pow5 (1 - cosA);   // ala Schlick interpoliation
    return lerp (F0, F90, t);
}
// approximage Schlick with ^4 instead of ^5
inline half3 FresnelLerpFast (half3 F0, half3 F90, half cosA)
{
    half t = Pow4 (1 - cosA);
    return lerp (F0, F90, t);
}

// Note: Disney diffuse must be multiply by diffuseAlbedo / PI. This is done outside of this function.
inline half DisneyDiffuse(half NdotV, half NdotL, half LdotH, half perceptualRoughness)
{
    half fd90 = 0.5 + 2 * LdotH * LdotH * perceptualRoughness;
    // Two schlick fresnel term
    half lightScatter   = (1 + (fd90 - 1) * Pow5(1 - NdotL));
    half viewScatter    = (1 + (fd90 - 1) * Pow5(1 - NdotV));

    return lightScatter * viewScatter;
}

// NOTE: Visibility term here is the full form from Torrance-Sparrow model, it includes Geometric term: V = G / (N.L * N.V)
// This way it is easier to swap Geometric terms and more room for optimizations (except maybe in case of CookTorrance geom term)

// Generic Smith-Schlick visibility term
inline half SmithVisibilityTerm (half NdotL, half NdotV, half k)
{
    half gL = NdotL * (1-k) + k;
    half gV = NdotV * (1-k) + k;
    return 1.0 / (gL * gV + 1e-5f); // This function is not intended to be running on Mobile,
                                    // therefore epsilon is smaller than can be represented by half
}

// Smith-Schlick derived for Beckmann
inline half SmithBeckmannVisibilityTerm (half NdotL, half NdotV, half roughness)
{
    half c = 0.797884560802865h; // c = sqrt(2 / Pi)
    half k = roughness * c;
    return SmithVisibilityTerm (NdotL, NdotV, k) * 0.25f; // * 0.25 is the 1/4 of the visibility term
}

// Ref: http://jcgt.org/published/0003/02/03/paper.pdf
inline half SmithJointGGXVisibilityTerm (half NdotL, half NdotV, half roughness)
{
    half a = roughness;
    half lambdaV = NdotL * (NdotV * (1 - a) + a);
    half lambdaL = NdotV * (NdotL * (1 - a) + a);
    return 0.5f / (lambdaV + lambdaL + 1e-5f);
}

inline float GGXTerm (float NdotH, float roughness)
{
    float a2 = roughness * roughness;
    float d = (NdotH * a2 - NdotH) * NdotH + 1.0f; // 2 mad
    return UNITY_INV_PI * a2 / (d * d + 1e-7f); // This function is not intended to be running on Mobile,
                                            // therefore epsilon is smaller than what can be represented by half
}

inline half PerceptualRoughnessToSpecPower (half perceptualRoughness)
{
    half m = PerceptualRoughnessToRoughness(perceptualRoughness);   // m is the true academic roughness.
    half sq = max(1e-4f, m*m);
    half n = (2.0 / sq) - 2.0;                          // https://dl.dropboxusercontent.com/u/55891920/papers/mm_brdf.pdf
    n = max(n, 1e-4f);                                  // prevent possible cases of pow(0,0), which could happen when roughness is 1.0 and NdotH is zero
    return n;
}

// BlinnPhong normalized as normal distribution function (NDF)
// for use in micro-facet model: spec=D*G*F
// eq. 19 in https://dl.dropboxusercontent.com/u/55891920/papers/mm_brdf.pdf
inline half NDFBlinnPhongNormalizedTerm (half NdotH, half n)
{
    // norm = (n+2)/(2*pi)
    half normTerm = (n + 2.0) * (0.5/UNITY_PI);

    half specTerm = pow (NdotH, n);
    return specTerm * normTerm;
}

//-------------------------------------------------------------------------------------
/*
// https://s3.amazonaws.com/docs.knaldtech.com/knald/1.0.0/lys_power_drops.html

const float k0 = 0.00098, k1 = 0.9921;
// pass this as a constant for optimization
const float fUserMaxSPow = 100000; // sqrt(12M)
const float g_fMaxT = ( exp2(-10.0/fUserMaxSPow) - k0)/k1;
float GetSpecPowToMip(float fSpecPow, int nMips)
{
   // Default curve - Inverse of TB2 curve with adjusted constants
   float fSmulMaxT = ( exp2(-10.0/sqrt( fSpecPow )) - k0)/k1;
   return float(nMips-1)*(1.0 - clamp( fSmulMaxT/g_fMaxT, 0.0, 1.0 ));
}

    //float specPower = PerceptualRoughnessToSpecPower(perceptualRoughness);
    //float mip = GetSpecPowToMip (specPower, 7);
*/

inline float3 Unity_SafeNormalize(float3 inVec)
{
    float dp3 = max(0.001f, dot(inVec, inVec));
    return inVec * rsqrt(dp3);
}

//-------------------------------------------------------------------------------------

// Note: BRDF entry points use smoothness and oneMinusReflectivity for optimization
// purposes, mostly for DX9 SM2.0 level. Most of the math is being done on these (1-x) values, and that saves
// a few precious ALU slots.


// Main Physically Based BRDF
// Derived from Disney work and based on Torrance-Sparrow micro-facet model
//
//   BRDF = kD / pi + kS * (D * V * F) / 4
//   I = BRDF * NdotL
//
// * NDF (depending on UNITY_BRDF_GGX):
//  a) Normalized BlinnPhong
//  b) GGX
// * Smith for Visiblity term
// * Schlick approximation for Fresnel
half4 BRDF1_Unity_PBS (half3 diffColor, half3 specColor, half oneMinusReflectivity, half smoothness,
    float3 normal, float3 viewDir,
    UnityLight light, UnityIndirect gi)
{
    float perceptualRoughness = SmoothnessToPerceptualRoughness (smoothness);
    float3 halfDir = Unity_SafeNormalize (float3(light.dir) + viewDir);

    half nv = dot(normal, viewDir);    // This abs allow to limit artifact


    half nl = saturate(dot(normal, light.dir));
    float nh = saturate(dot(normal, halfDir));

    half lv = saturate(dot(light.dir, viewDir));
    half lh = saturate(dot(light.dir, halfDir));

    // Diffuse term
    half diffuseTerm = DisneyDiffuse(nv, nl, lh, perceptualRoughness) * nl; 
    //Diffuse = DisneyDiffuse(NoV, NoL, LoH, SmoothnessToPerceptualRoughness (smoothness)) * NoL;
    // Specular term
    // HACK: theoretically we should divide diffuseTerm by Pi and not multiply specularTerm!
    // BUT 1) that will make shader look significantly darker than Legacy ones
    // and 2) on engine side "Non-important" lights have to be divided by Pi too in cases when they are injected into ambient SH
    float roughness = PerceptualRoughnessToRoughness(perceptualRoughness);
    // GGX with roughtness to 0 would mean no specular at all, using max(roughness, 0.002) here to match HDrenderloop roughtness remapping.
    roughness = max(roughness, 0.002);
    half V = SmithJointGGXVisibilityTerm (nl, nv, roughness);
    float D = GGXTerm (nh, roughness);


    half specularTerm = V*D * UNITY_PI; // Torrance-Sparrow model, Fresnel is applied later

#   ifdef UNITY_COLORSPACE_GAMMA
        specularTerm = sqrt(max(1e-4h, specularTerm));
#   endif

    // specularTerm * nl can be NaN on Metal in some cases, use max() to make sure it's a sane value
    specularTerm = max(0, specularTerm * nl);

    half3 color =   (diffColor * diffuseTerm + specularTerm * FresnelTerm (specColor, lh)) * light.color;

    return half4(color, 1);
}

// Based on Minimalist CookTorrance BRDF
// Implementation is slightly different from original derivation: http://www.thetenthplanet.de/archives/255
//
// * NDF (depending on UNITY_BRDF_GGX):
//  a) BlinnPhong
//  b) [Modified] GGX
// * Modified Kelemen and Szirmay-​Kalos for Visibility term
// * Fresnel approximated with 1/LdotH
half4 BRDF2_Unity_PBS (half3 diffColor, half3 specColor, half oneMinusReflectivity, half smoothness,
    float3 normal, float3 viewDir,
    UnityLight light, UnityIndirect gi)
{
    float3 halfDir = Unity_SafeNormalize (float3(light.dir) + viewDir);

    half nl = saturate(dot(normal, light.dir));
    float nh = saturate(dot(normal, halfDir));
    half nv = (dot(normal, viewDir));
    float lh = saturate(dot(light.dir, halfDir));

    // Specular term
    half perceptualRoughness = SmoothnessToPerceptualRoughness (smoothness);
    half roughness = PerceptualRoughnessToRoughness(perceptualRoughness);

#if UNITY_BRDF_GGX

    // GGX Distribution multiplied by combined approximation of Visibility and Fresnel
    // See "Optimizing PBR for Mobile" from Siggraph 2015 moving mobile graphics course
    // https://community.arm.com/events/1155
    half a = roughness;
    float a2 = a*a;

    float d = nh * nh * (a2 - 1.f) + 1.00001f;
#ifdef UNITY_COLORSPACE_GAMMA
    // Tighter approximation for Gamma only rendering mode!
    // DVF = sqrt(DVF);
    // DVF = (a * sqrt(.25)) / (max(sqrt(0.1), lh)*sqrt(roughness + .5) * d);
    float specularTerm = a / (max(0.32f, lh) * (1.5f + roughness) * d);
#else
    float specularTerm = a2 / (max(0.1f, lh*lh) * (roughness + 0.5f) * (d * d) * 4);
#endif

    // on mobiles (where half actually means something) denominator have risk of overflow
    // clamp below was added specifically to "fix" that, but dx compiler (we convert bytecode to metal/gles)
    // sees that specularTerm have only non-negative terms, so it skips max(0,..) in clamp (leaving only min(100,...))
#if defined (SHADER_API_MOBILE)
    specularTerm = specularTerm - 1e-4f;
#endif

#else

    // Legacy
    half specularPower = PerceptualRoughnessToSpecPower(perceptualRoughness);
    // Modified with approximate Visibility function that takes roughness into account
    // Original ((n+1)*N.H^n) / (8*Pi * L.H^3) didn't take into account roughness
    // and produced extremely bright specular at grazing angles

    half invV = lh * lh * smoothness + perceptualRoughness * perceptualRoughness; // approx ModifiedKelemenVisibilityTerm(lh, perceptualRoughness);
    half invF = lh;

    half specularTerm = ((specularPower + 1) * pow (nh, specularPower)) / (8 * invV * invF + 1e-4h);

#ifdef UNITY_COLORSPACE_GAMMA
    specularTerm = sqrt(max(1e-4f, specularTerm));
#endif

#endif

#if defined (SHADER_API_MOBILE)
    specularTerm = clamp(specularTerm, 0.0, 100.0); // Prevent FP16 overflow on mobiles
#endif
#if defined(_SPECULARHIGHLIGHTS_OFF)
    specularTerm = 0.0;
#endif

    // surfaceReduction = Int D(NdotH) * NdotH * Id(NdotL>0) dH = 1/(realRoughness^2+1)

    // 1-0.28*x^3 as approximation for (1/(x^4+1))^(1/2.2) on the domain [0;1]
    // 1-x^3*(0.6-0.08*x)   approximation for 1/(x^4+1)
#ifdef UNITY_COLORSPACE_GAMMA
    half surfaceReduction = 0.28;
#else
    half surfaceReduction = (0.6-0.08*perceptualRoughness);
#endif

    surfaceReduction = 1.0 - roughness*perceptualRoughness*surfaceReduction;

    half grazingTerm = saturate(smoothness + (1-oneMinusReflectivity));
    half3 color =   (diffColor + specularTerm * specColor) * light.color * nl
                    + gi.diffuse * diffColor
                    + surfaceReduction * gi.specular * FresnelLerpFast (specColor, grazingTerm, nv);

    return half4(color, 1);
}

sampler2D_float unity_NHxRoughness;
half3 BRDF3_Direct(half3 diffColor, half3 specColor, half rlPow4, half smoothness)
{
    half LUT_RANGE = 16.0; // must match range in NHxRoughness() function in GeneratedTextures.cpp
    // Lookup texture to save instructions
    half specular = tex2D(unity_NHxRoughness, half2(rlPow4, SmoothnessToPerceptualRoughness(smoothness))).UNITY_ATTEN_CHANNEL * LUT_RANGE;
#if defined(_SPECULARHIGHLIGHTS_OFF)
    specular = 0.0;
#endif

    return diffColor + specular * specColor;
}

half3 BRDF3_Indirect(half3 diffColor, half3 specColor, UnityIndirect indirect, half grazingTerm, half fresnelTerm)
{
    half3 c = indirect.diffuse * diffColor;
    c += indirect.specular * lerp (specColor, grazingTerm, fresnelTerm);
    return c;
}

// Old school, not microfacet based Modified Normalized Blinn-Phong BRDF
// Implementation uses Lookup texture for performance
//
// * Normalized BlinnPhong in RDF form
// * Implicit Visibility term
// * No Fresnel term
//
// TODO: specular is too weak in Linear rendering mode
half4 BRDF3_Unity_PBS (half3 diffColor, half3 specColor, half oneMinusReflectivity, half smoothness,
    float3 normal, float3 viewDir,
    UnityLight light, UnityIndirect gi)
{
    float3 reflDir = reflect (viewDir, normal);

    half nl = saturate(dot(normal, light.dir));
    half nv = (dot(normal, viewDir));

    // Vectorize Pow4 to save instructions
    half2 rlPow4AndFresnelTerm = Pow4 (float2(dot(reflDir, light.dir), 1-nv));  // use R.L instead of N.H to save couple of instructions
    half rlPow4 = rlPow4AndFresnelTerm.x; // power exponent must match kHorizontalWarpExp in NHxRoughness() function in GeneratedTextures.cpp
    half fresnelTerm = rlPow4AndFresnelTerm.y;

    half grazingTerm = saturate(smoothness + (1-oneMinusReflectivity));

    half3 color = BRDF3_Direct(diffColor, specColor, rlPow4, smoothness);
    color *= light.color * nl;
    color += BRDF3_Indirect(diffColor, specColor, gi, grazingTerm, fresnelTerm);

    return half4(color, 1);
}

// Include deprecated function
#define INCLUDE_UNITY_STANDARD_BRDF_DEPRECATED
#include "UnityDeprecated.cginc"
#undef INCLUDE_UNITY_STANDARD_BRDF_DEPRECATED

#endif // UNITY_STANDARD_BRDF_INCLUDED
