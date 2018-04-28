using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Experimental.Rendering;
[ExecuteInEditMode]
public class OpaqueAssetPipe : RenderPipelineAsset
{
    public Shader deferredShading;
#if UNITY_EDITOR
    [UnityEditor.MenuItem("SRP-Demo/Deferred")]
    static void CreateBasicAssetPipeline()
    {
        var instance = ScriptableObject.CreateInstance<OpaqueAssetPipe>();
        UnityEditor.AssetDatabase.CreateAsset(instance, "Assets/OpaqueDeferred.asset");
    }
#endif
    protected override IRenderPipeline InternalCreatePipeline()
    {
        return new OpaqueAssetPipeInstance(deferredShading);
    }
}
public class OpaqueAssetPipeInstance : RenderPipeline
{

    int gBuffer0;
    int gBuffer1;
    int gBuffer2;
    int gBuffer3;
    Material deferredmat;
    RenderTargetIdentifier[] gBuffers = new RenderTargetIdentifier[4];
    Vector4[] frustumCorner = new Vector4[4];
    Vector4[] _LightWorldPosArray = new Vector4[512];
    Vector4[] _LightWorldColorArray = new Vector4[512];
    public OpaqueAssetPipeInstance(Shader shader)
    {
        deferredmat = new Material(shader);
        gBuffer0 = Shader.PropertyToID("_GBuffer0");
        gBuffer1 = Shader.PropertyToID("_GBuffer1");
        gBuffer2 = Shader.PropertyToID("_GBuffer2");
        gBuffer3 = Shader.PropertyToID("_GBuffer3");
        gBuffers[0] = gBuffer0;
        gBuffers[1] = gBuffer1;
        gBuffers[2] = gBuffer2;
        gBuffers[3] = gBuffer3;
    }

    public static void RemoveFromList<T>(List<T> list, int index)
    {
        int sz = list.Count - 1;
        list[index] = list[sz];
        list.RemoveAt(sz);
    }

    public static int GetMainLight(List<VisibleLight> visibleLights)
    {
        for (int i = 0, length = visibleLights.Count; i < length; ++i)
        {
            if (visibleLights[i].lightType == LightType.Directional)
            {
                return i;
            }
        }
        return -1;
    }
    public override void Render(ScriptableRenderContext context, Camera[] cameras)
    {
        base.Render(context, cameras);
        foreach (var camera in cameras)
        {
            ScriptableCullingParameters cullingParams;
            if (!CullResults.GetCullingParameters(camera, out cullingParams))
                continue;
            CullResults cull = CullResults.Cull(ref cullingParams, context);
            context.SetupCameraProperties(camera);
            var cmd = new CommandBuffer();
            int width, height;
            if (camera.targetTexture)
            {
                width = camera.targetTexture.width;
                height = camera.targetTexture.height;
            }
            else
            {
                width = Screen.width;
                height = Screen.height;
            }
            cmd.GetTemporaryRT(gBuffer0, width, height, 24, FilterMode.Trilinear, RenderTextureFormat.ARGBFloat);
            cmd.GetTemporaryRT(gBuffer1, width, height, 0, FilterMode.Trilinear, RenderTextureFormat.ARGBFloat);
            cmd.GetTemporaryRT(gBuffer2, width, height, 0, FilterMode.Trilinear, RenderTextureFormat.ARGBFloat);
            cmd.GetTemporaryRT(gBuffer3, width, height, 0, FilterMode.Trilinear, RenderTextureFormat.ARGBFloat);
            cmd.SetRenderTarget(gBuffers, gBuffer0);
            cmd.ClearRenderTarget(true, true, Color.black);
            var visibleLights = cull.visibleLights;
            var mainLightIndex = GetMainLight(visibleLights);
            if (mainLightIndex < 0)
            {
                cmd.SetGlobalVector("_DirectionalLightDir", new Vector3(0, 1, 0));
                cmd.SetGlobalColor("_DirectionalLightColor", Color.black);
            }
            else
            {
                var mainLight = visibleLights[mainLightIndex];
                cmd.SetGlobalVector("_DirectionalLightDir", -mainLight.light.transform.forward);
                cmd.SetGlobalColor("_DirectionalLightColor", mainLight.finalColor);
                RemoveFromList(visibleLights, mainLightIndex);
            }
            var lightCount = Mathf.Min(256, visibleLights.Count);
            for (int i = 0; i < lightCount; ++i)
            {
                var light = visibleLights[i];
                var pos = light.light.transform.position;
                _LightWorldPosArray[i] = new Vector4(pos.x, pos.y, pos.z, light.range);
                _LightWorldColorArray[i] = light.finalColor;
            }
            cmd.SetGlobalVectorArray("_LightWorldPos", _LightWorldPosArray);
            cmd.SetGlobalFloat("_LightCount", lightCount);
            cmd.SetGlobalVectorArray("_LightFinalColor", _LightWorldColorArray);
            frustumCorner[0] = camera.ViewportToWorldPoint(new Vector3(0, 0, camera.farClipPlane));
            frustumCorner[1] = camera.ViewportToWorldPoint(new Vector3(1, 0, camera.farClipPlane));
            frustumCorner[2] = camera.ViewportToWorldPoint(new Vector3(0, 1, camera.farClipPlane));
            frustumCorner[3] = camera.ViewportToWorldPoint(new Vector3(1, 1, camera.farClipPlane));
            cmd.SetGlobalVectorArray("_FrustumCorner", frustumCorner);
            context.ExecuteCommandBuffer(cmd);

            var settings = new DrawRendererSettings(camera, new ShaderPassName("Deferred"));
            settings.sorting.flags = SortFlags.CommonOpaque;
            var filterSettings = new FilterRenderersSettings(true) { renderQueueRange = RenderQueueRange.opaque };
            context.DrawRenderers(cull.visibleRenderers, ref settings, filterSettings);
            cmd.Clear();
            cmd.SetRenderTarget(BuiltinRenderTextureType.CameraTarget);
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
            context.DrawSkybox(camera);
            cmd.Blit(null, BuiltinRenderTextureType.CameraTarget, deferredmat);
            context.ExecuteCommandBuffer(cmd);
            cmd.Release();

            context.Submit();
        }
    }
}