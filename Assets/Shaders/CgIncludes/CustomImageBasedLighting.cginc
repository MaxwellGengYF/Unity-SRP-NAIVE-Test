#ifndef CUSTOM_IMAGE_BASED_LIGHTING_INCLUDED
#define CUSTOM_IMAGE_BASED_LIGHTING_INCLUDED

#include "UnityCG.cginc"
#include "UnityStandardConfig.cginc"
#include "CustomStandardBRDF.cginc"

// ----------------------------------------------------------------------------
// GlossyEnvironment - Function to integrate the specular lighting with default sky or reflection probes
// ----------------------------------------------------------------------------
struct Unity_GlossyEnvironmentData
{
    // - Deferred case have one cubemap
    // - Forward case can have two blended cubemap (unusual should be deprecated).

    // Surface properties use for cubemap integration
    half    roughness; // CAUTION: This is perceptualRoughness but because of compatibility this name can't be change :(
    half3   reflUVW;
};

// ----------------------------------------------------------------------------

inline Unity_GlossyEnvironmentData UnityGlossyEnvironmentSetup(half Smoothness, half3 worldViewDir, half3 Normal, half3 fresnel0)
{
    Unity_GlossyEnvironmentData g;

    g.roughness /* perceptualRoughness */   = SmoothnessToPerceptualRoughness(Smoothness);
    g.reflUVW   = reflect(-worldViewDir, Normal);

    return g;
}

// ----------------------------------------------------------------------------
#define perceptualRoughnessToMipmapLevel(perceptualRoughness) perceptualRoughness * UNITY_SPECCUBE_LOD_STEPS


// ----------------------------------------------------------------------------
#define mipmapLevelToPerceptualRoughness(mipmapLevel) mipmapLevel / UNITY_SPECCUBE_LOD_STEPS


// ----------------------------------------------------------------------------
inline half3 Unity_GlossyEnvironment (UNITY_ARGS_TEXCUBE(tex), half4 hdr, Unity_GlossyEnvironmentData glossIn)
{
    half perceptualRoughness = glossIn.roughness /* perceptualRoughness */ ;
    perceptualRoughness = perceptualRoughness*(1.7 - 0.7*perceptualRoughness);
    half mip = perceptualRoughnessToMipmapLevel(perceptualRoughness);
    half3 R = glossIn.reflUVW;
    half4 rgbm = UNITY_SAMPLE_TEXCUBE_LOD(tex, R, mip);

    return DecodeHDR(rgbm, hdr);
}

// ----------------------------------------------------------------------------
// Include deprecated function
#define INCLUDE_UNITY_IMAGE_BASED_LIGHTING_DEPRECATED
#include "UnityDeprecated.cginc"
#undef INCLUDE_UNITY_IMAGE_BASED_LIGHTING_DEPRECATED

// ----------------------------------------------------------------------------

#endif // UNITY_IMAGE_BASED_LIGHTING_INCLUDED
