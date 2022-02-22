#ifndef URP_TRANSLUCENTLIGHTING_INCLUDED
#define URP_TRANSLUCENTLIGHTING_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"


half3 CTI_GlobalIllumination(BRDFData brdfData, half3 bakedGI, half occlusion, half3 normalWS, half3 viewDirectionWS, 
    half specOccluison)
{
    half3 reflectVector = reflect(-viewDirectionWS, normalWS);
    half fresnelTerm = Pow4(1.0 - saturate(dot(normalWS, viewDirectionWS)));

    half3 indirectDiffuse = bakedGI * occlusion;
    half3 indirectSpecular = GlossyEnvironmentReflection(reflectVector, brdfData.perceptualRoughness, occlusion)        * specOccluison;

    return EnvironmentBRDF(brdfData, indirectDiffuse, indirectSpecular, fresnelTerm);
}


half3 LightingPhysicallyBasedWrapped(BRDFData brdfData, half3 lightColor, half3 lightDirectionWS, half lightAttenuation, half3 normalWS, half3 viewDirectionWS, half NdotL)
{

//NdotL is wrapped... not correct for specular
    half3 radiance = lightColor * (lightAttenuation * NdotL);
    return DirectBDRF(brdfData, normalWS, lightDirectionWS, viewDirectionWS) * radiance;
}

half3 LightingPhysicallyBasedWrapped(BRDFData brdfData, Light light, half3 normalWS, half3 viewDirectionWS, half NdotL)
{
    return LightingPhysicallyBasedWrapped(brdfData, light.color, light.direction, light.distanceAttenuation * light.shadowAttenuation, normalWS, viewDirectionWS, NdotL);
}

half4 CTIURPFragmentPBR(InputData inputData, half3 albedo, half metallic, half3 specular,
    half smoothness, half occlusion, half3 emission, half alpha, half3 translucency, half AmbientReflection, half Wrap)
{
    BRDFData brdfData;
    InitializeBRDFData(albedo, metallic, specular, smoothness, alpha, brdfData);

    #if defined(SHADOWS_SHADOWMASK) && defined(LIGHTMAP_ON)
        half4 shadowMask = inputData.shadowMask;
    #elif !defined (LIGHTMAP_ON)
        half4 shadowMask = unity_ProbesOcclusion;
    #else
        half4 shadowMask = half4(1, 1, 1, 1);
    #endif

    Light mainLight = GetMainLight(inputData.shadowCoord, inputData.positionWS, shadowMask);
    
    #if defined(_SCREEN_SPACE_OCCLUSION)
        AmbientOcclusionFactor aoFactor = GetScreenSpaceAmbientOcclusion(inputData.normalizedScreenSpaceUV);
        mainLight.color *= aoFactor.directAmbientOcclusion;
        occlusion = min(occlusion, aoFactor.indirectAmbientOcclusion);
    #endif

    MixRealtimeAndBakedGI(mainLight, inputData.normalWS, inputData.bakedGI, half4(0, 0, 0, 0));

    half3 color = CTI_GlobalIllumination(brdfData, inputData.bakedGI, occlusion, inputData.normalWS, inputData.viewDirectionWS,     AmbientReflection);

//  Wrapped Diffuse   
    half w = Wrap; // 0.4
    half NdotL = saturate((dot(inputData.normalWS, mainLight.direction) + w) / ((1 + w) * (1 + w)));
    // NdotL = saturate( dot(inputData.normalWS, mainLight.direction) );
    color += LightingPhysicallyBasedWrapped(brdfData, mainLight, inputData.normalWS, inputData.viewDirectionWS, NdotL);

//  translucency
    half transPower = translucency.y;
    half3 transLightDir = mainLight.direction + inputData.normalWS * translucency.z;
    half transDot = dot( transLightDir, -inputData.viewDirectionWS );
    transDot = exp2(saturate(transDot) * transPower - transPower);
    color += transDot * (1.0 - NdotL) * mainLight.color * mainLight.shadowAttenuation * brdfData.diffuse * translucency.x; // * 0.1;

    #ifdef _ADDITIONAL_LIGHTS
        uint pixelLightCount = GetAdditionalLightsCount();
        for (uint lightIndex = 0u; lightIndex < pixelLightCount; ++lightIndex)
        {
            Light light = GetAdditionalLight(lightIndex, inputData.positionWS, shadowMask);
            #if defined(_SCREEN_SPACE_OCCLUSION)
                light.color *= aoFactor.directAmbientOcclusion;
            #endif
    //  Wrapped Diffuse
            NdotL = saturate((dot(inputData.normalWS, light.direction) + w) / ((1 + w) * (1 + w)));
            color += LightingPhysicallyBasedWrapped(brdfData, light, inputData.normalWS, inputData.viewDirectionWS, NdotL);
    //  Translucency
            transLightDir = light.direction + inputData.normalWS * translucency.z;
            transDot = dot( transLightDir, -inputData.viewDirectionWS );
            transDot = exp2(saturate(transDot) * transPower - transPower);
            color += transDot * (1.0 - NdotL) * light.color * light.shadowAttenuation * light.distanceAttenuation * brdfData.diffuse * translucency.x; // * 0.1;
        }
    #endif

    #ifdef _ADDITIONAL_LIGHTS_VERTEX
        color += inputData.vertexLighting * brdfData.diffuse;
    #endif
    color += emission;
    return half4(color, alpha);
}

#endif