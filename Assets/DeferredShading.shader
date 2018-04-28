Shader "Hidden/DeferredShading"
{
	SubShader
	{
		// No culling or depth
		Cull Off ZWrite Off ZTest Always

CGINCLUDE
#include "UnityCG.cginc"
#include "UnityDeferredLibrary.cginc"
#include "UnityPBSLighting.cginc"
#include "UnityStandardUtils.cginc"
#include "UnityGBuffer.cginc"
#include "UnityStandardBRDF.cginc"
float4 BRDF (float3 diffColor, float3 specColor, float oneMinusReflectivity, float smoothness,
    float3 normal, float3 viewDir,
    UnityLight light)
{
    float perceptualRoughness = SmoothnessToPerceptualRoughness (smoothness);
    float3 floatDir = Unity_SafeNormalize (float3(light.dir) + viewDir);

    float nv = dot(normal, viewDir);    // This abs allow to limit artifact

    float nl = saturate(dot(normal, light.dir));
    float nh = saturate(dot(normal, floatDir));

    float lh = saturate(dot(light.dir, floatDir));

    // Diffuse term
    float diffuseTerm = DisneyDiffuse(nv, nl, lh, perceptualRoughness) * nl; 
    //Diffuse = DisneyDiffuse(NoV, NoL, LoH, SmoothnessToPerceptualRoughness (smoothness)) * NoL;
    // Specular term
    // HACK: theoretically we should divide diffuseTerm by Pi and not multiply specularTerm!
    // BUT 1) that will make shader look significantly darker than Legacy ones
    // and 2) on engine side "Non-important" lights have to be divided by Pi too in cases when they are injected into ambient SH
    float roughness = PerceptualRoughnessToRoughness(perceptualRoughness);
#if UNITY_BRDF_GGX
    // GGX with roughtness to 0 would mean no specular at all, using max(roughness, 0.002) here to match HDrenderloop roughtness remapping.
    roughness = max(roughness, 0.002);
    float V = SmithJointGGXVisibilityTerm (nl, nv, roughness);
    float D = GGXTerm (nh, roughness);
#else
    // Legacy
    float V = SmithBeckmannVisibilityTerm (nl, nv, roughness);
    float D = NDFBlinnPhongNormalizedTerm (nh, PerceptualRoughnessToSpecPower(perceptualRoughness));
#endif

    float specularTerm = V*D * UNITY_PI; // Torrance-Sparrow model, Fresnel is applied later

#   ifdef UNITY_COLORSPACE_GAMMA
        specularTerm = sqrt(max(1e-4h, specularTerm));
#   endif

    // specularTerm * nl can be NaN on Metal in some cases, use max() to make sure it's a sane value
    specularTerm = max(0, specularTerm * nl);
#if defined(_SPECULARHIGHLIGHTS_OFF)
    specularTerm = 0.0;
#endif

    // To provide true Lambert lighting, we need to be able to kill specular completely.
    specularTerm *= any(specColor);

     float3 color =  (diffColor * diffuseTerm + specularTerm * FresnelTerm (specColor, lh)) * light.color;

    return float4(color, 1);
}
ENDCG
		Pass
		{
			Blend srcAlpha oneMinusSrcAlpha
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			uniform sampler2D _GBuffer0;
			uniform sampler2D _GBuffer1;
			uniform sampler2D _GBuffer2;
			uniform sampler2D _GBuffer3;
			uniform float _LightCount;
			uniform float4 _LightWorldPos[256];
			uniform float4 _LightFinalColor[256];
			uniform float4 _DirectionalLightDir;
			uniform float4 _DirectionalLightColor;
			uniform float4 _FrustumCorner[4];
			struct appdata
			{
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
			};

			struct v2f
			{
				float2 uv : TEXCOORD0;
				float3 farPlanePos : TEXCOORD1;
				float4 vertex : SV_POSITION;
			};
			

			v2f vert (appdata v)
			{
				v2f o;
				o.vertex = UnityObjectToClipPos(v.vertex);
				o.farPlanePos = _FrustumCorner[v.uv.x + 2 * v.uv.y].xyz;
				o.uv = v.uv;
				return o;
			}
			
			sampler2D _MainTex;

			fixed4 frag (v2f i) : SV_Target
			{
				float4 diffuse = tex2D(_GBuffer0, i.uv);
				float4 specular = tex2D(_GBuffer1, i.uv);
				float4 ndtex = tex2D(_GBuffer2, i.uv);
				float3 normal = normalize(ndtex.rgb * 2 - 1);
				float linearDepth = ndtex.a;
				float3 emission = tex2D(_GBuffer3, i.uv).xyz;
				float3 worldPos = lerp(_WorldSpaceCameraPos, i.farPlanePos, linearDepth);
				float oneMinusReflectivity = 1 - SpecularStrength(specular.rgb);
				UnityLight light;
				light.dir = normalize(_DirectionalLightDir.xyz);
				light.color = _DirectionalLightColor.xyz;
				float atten;
				
				float4 col = BRDF(diffuse.rgb * diffuse.a, specular.rgb, oneMinusReflectivity,specular.a,normal, normalize(_WorldSpaceCameraPos - i.farPlanePos), light);
				col.rgb += emission;
				col.a = step(0.00001, linearDepth);
				return col;
			}
			ENDCG
		}
	}
}
