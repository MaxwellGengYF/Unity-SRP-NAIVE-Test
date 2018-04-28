using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Experimental.Rendering;
[ExecuteInEditMode]
public class OpaqueAssetPipe : RenderPipelineAsset
{
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
        return new OpaqueAssetPipeInstance();
    }
}
public class OpaqueAssetPipeInstance : RenderPipeline
{

    int gBuffer0;
    int gBuffer1;
    int gBuffer2;
    int gBuffer3;
    RenderTargetIdentifier[] gBuffers = new RenderTargetIdentifier[4];
    public OpaqueAssetPipeInstance()
    {
        gBuffer0 = Shader.PropertyToID("_GBuffer0");
        gBuffer1 = Shader.PropertyToID("_GBuffer1");
        gBuffer2 = Shader.PropertyToID("_GBuffer2");
        gBuffer3 = Shader.PropertyToID("_GBuffer3");
        gBuffers[0] = gBuffer0;
        gBuffers[1] = gBuffer1;
        gBuffers[2] = gBuffer2;
        gBuffers[3] = gBuffer3;
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
            cmd.ClearRenderTarget(true, true, Color.grey);
            context.ExecuteCommandBuffer(cmd);
            cmd.Release();
            var settings = new DrawRendererSettings(camera, new ShaderPassName("Deferred"));
            settings.sorting.flags = SortFlags.CommonOpaque;
            var filterSettings = new FilterRenderersSettings(true) { renderQueueRange = RenderQueueRange.opaque };
            cmd = new CommandBuffer();
            context.DrawRenderers(cull.visibleRenderers, ref settings, filterSettings);
            context.DrawSkybox(camera);
            context.Submit();
        }
    }
}