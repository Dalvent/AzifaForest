Shader "CTI/URP Billboard"
{
    Properties
    {
        
        [Header(Surface Inputs)]
        [Space(5)]
        _HueVariation                   ("Color Variation", Color) = (0.9,0.5,0.0,0.1)

        [NoScaleOffset] _BaseMap        ("Albedo (RGB) Smoothness (A)", 2D) = "white" {}
        _Cutoff                         ("Alpha Cutoff", Range(0.0, 1.0)) = 0.5
        _AlphaLeak                      ("Alpha Leak Suppression", Range(0.5,1.0)) = 0.6
        
        _Smoothness                     ("Smoothness", Range(0.0, 1.0)) = 1.0
        _SpecColor                      ("Specular", Color) = (0.2, 0.2, 0.2)
        _OcclusionStrength              ("Occlusion Strength", Range(0,1)) = 1

        [Space(5)]
        [Toggle(_NORMALMAP)]
        _ApplyNormal                    ("Enable Normal Map", Float) = 1.0
        [NoScaleOffset]
        _BumpSpecMap                    ("    Normal (AG) Translucency(R) Smoothness(B)", 2D) = "white" {}
        _BumpScale                      ("    Normal Scale", Float) = 1.0

        [Header(Wrapped Diffuse Lighting)]
        [Space(5)]
        _Wrap                           ("Wrap", Range(0.0, 1.0)) = 0.5

        [Header(Transmission)]
        [Space(5)]
        [CTI_LWRPTransDrawer]
        _Translucency                   ("Strength (X) Power (Y)", Vector) = (1, 8, 0, 0)

        [Header(Wind)]
        [Space(3)]
        _WindStrength                   ("Wind Strength", Float) = 1.0 
        
        [Header(Ambient)]
        [Space(5)]
        _AmbientReflection              ("Ambient Reflection", Range(0, 1)) = 1

        [Header(Legacy)]
        [Space(5)]
        _BillboardScale                 ("Billboard Scale", Float) = 2

    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
            "UniversalMaterialType" = "Lit"
            "Queue"="AlphaTest"
            "DisableBatching" = "LODFading"
            "IgnoreProjector" = "True"
            "ShaderModel"="2.0"
        }
        LOD 300


//  Base -----------------------------------------------------
        Pass
        {
            Name "ForwardLit"
            Tags{"LightMode" = "UniversalForward"}

            ZWrite On
        //  LWRP billboardNormal orientation is flipped?
            Cull Off

            HLSLPROGRAM
            // Required to compile gles 2.0 with standard SRP library
            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x
            #pragma target 2.0

            // -------------------------------------
            // Material Keywords
            #define _ALPHATEST_ON 1
            #pragma shader_feature _NORMALMAP

            #define CTIBILLBOARD
            #define _SPECULAR_SETUP

            // -------------------------------------
            // Universal Pipeline keywords
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION
            #pragma multi_compile _ LIGHTMAP_SHADOW_MIXING
            #pragma multi_compile _ SHADOWS_SHADOWMASK


            // -------------------------------------
            // Unity defined keywords
            // #pragma multi_compile _ DIRLIGHTMAP_COMBINED
            // #pragma multi_compile _ LIGHTMAP_ON
            #pragma multi_compile_fog
            #pragma multi_compile _ LOD_FADE_CROSSFADE

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing

            #include "Includes/CTI URP Inputs.hlsl"
            #include "Includes/CTI URP Billboard.hlsl"
            #include "Includes/CTI URP Lighting.hlsl"

			#pragma vertex LitPassVertex
			#pragma fragment LitPassFragment

/// --------
            void InitializeInputData(CTIVertexBBOutput input, half3 normalTS, out InputData inputData)
            {
                inputData = (InputData)0;
                #if defined(REQUIRES_WORLD_SPACE_POS_INTERPOLATOR)
                    inputData.positionWS = input.positionWS;
                #endif
                half3 viewDirWS = GetWorldSpaceNormalizeViewDir(input.positionWS);
                #if defined(_NORMALMAP)
                    float sgn = input.tangentWS.w;      // should be either +1 or -1
                    float3 bitangent = sgn * cross(input.normalWS.xyz, input.tangentWS.xyz);
                    inputData.normalWS = TransformTangentToWorld(normalTS, half3x3(input.tangentWS.xyz, bitangent, input.normalWS.xyz));
                #else
                    inputData.normalWS = input.normalWS;
                #endif
                inputData.normalWS = NormalizeNormalPerPixel(inputData.normalWS);
                inputData.viewDirectionWS = viewDirWS;


                #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
                    inputData.shadowCoord = input.shadowCoord;
                #elif defined(MAIN_LIGHT_CALCULATE_SHADOWS)
                    inputData.shadowCoord = TransformWorldToShadowCoord(inputData.positionWS);
                #else
                    inputData.shadowCoord = float4(0, 0, 0, 0);
                #endif

                inputData.fogCoord = input.fogFactorAndVertexLight.x;
                inputData.vertexLighting = input.fogFactorAndVertexLight.yzw;
                inputData.bakedGI = SAMPLE_GI(input.texcoord1, input.vertexSH, inputData.normalWS);
                
                inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(input.positionCS);
                inputData.shadowMask = SAMPLE_SHADOWMASK(input.lightmapUV);
            }

			CTIVertexBBOutput LitPassVertex(CTIVertexBBInput input)
			{
				CTIVertexBBOutput output = (CTIVertexBBOutput)0;

                UNITY_SETUP_INSTANCE_ID(input);
                //UNITY_TRANSFER_INSTANCE_ID(input, output);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                CTIBillboardVert(input, 0);
            //  Set color variation
                output.colorVariation = input.color.r;

                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);
                half3 vertexLight = VertexLighting(vertexInput.positionWS, normalInput.normalWS);
                half fogFactor = ComputeFogFactor(vertexInput.positionCS.z);

                output.uv.xy = input.texcoord.xy;
                output.normalWS = NormalizeNormalPerVertex(normalInput.normalWS);
                #if defined(_NORMALMAP)
                    float sign = input.tangentOS.w * GetOddNegativeScale();
                    output.tangentWS = float4(normalInput.tangentWS.xyz, sign);
                #endif

                //OUTPUT_LIGHTMAP_UV(input.lightmapUV, unity_LightmapST, output.lightmapUV);
                OUTPUT_SH(output.normalWS.xyz, output.vertexSH);
                output.fogFactorAndVertexLight = half4(fogFactor, vertexLight);

                #if defined(REQUIRES_WORLD_SPACE_POS_INTERPOLATOR)
                    output.positionWS = vertexInput.positionWS;
                #endif
                #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
                    output.shadowCoord = GetShadowCoord(vertexInput);
                #endif

                output.positionCS = vertexInput.positionCS;
				return output;
			}


            half4 LitPassFragment(CTIVertexBBOutput IN) : SV_Target
			{
                //UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(IN);

                #if defined(LOD_FADE_CROSSFADE) && !defined(SHADER_API_GLES)
                    LODDitheringTransition(IN.positionCS.xyz, unity_LODFade.x);
                #endif

                SurfaceDescriptionLeaves surfaceData;
            //  Get the surface description / defined in "Includes/CTI LWRP Inputs.hlsl"
                InitializeStandardLitSurfaceData(IN.colorVariation, IN.uv.xy, surfaceData);
            //  Add ambient occlusion from alpha
                surfaceData.occlusion = (surfaceData.occlusion <= _AlphaLeak) ? 1 : surfaceData.occlusion; // Eliminate alpha leaking into ao
                surfaceData.occlusion  = lerp(1, surfaceData.occlusion * 2 - 1, _OcclusionStrength);

                InputData inputData;
                InitializeInputData(IN, surfaceData.normalTS, inputData);

            //  Apply lighting
                //half4 color = LightweightFragmentPBR(inputData, surfaceData.albedo, surfaceData.metallic, surfaceData.specular, surfaceData.smoothness, surfaceData.occlusion, surfaceData.emission, surfaceData.alpha);
                half4 color = CTIURPFragmentPBR(
                    inputData, 
                    surfaceData.albedo, 
                    surfaceData.metallic, 
                    surfaceData.specular, 
                    surfaceData.smoothness, 
                    surfaceData.occlusion, 
                    surfaceData.emission, 
                    surfaceData.alpha,
                    _Translucency * half3(surfaceData.translucency, 1, 1),
                    _AmbientReflection,
                    _Wrap);

            //  Add fog
                color.rgb = MixFog(color.rgb, inputData.fogCoord);
                return color;
			}

            ENDHLSL
        }

//  Shadows -----------------------------------------------------
        Pass
        {
            Name "ShadowCaster"
            Tags{"LightMode" = "ShadowCaster"}

            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Off

            HLSLPROGRAM
            // Required to compile gles 2.0 with standard srp library
            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x
            #pragma target 2.0

            // -------------------------------------
            // Material Keywords
            #define _ALPHATEST_ON 1

            #define CTIBILLBOARD

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing
            #pragma multi_compile _ LOD_FADE_CROSSFADE

            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment

            #define SHADOWSONLYPASS

            #include "Includes/CTI URP Inputs.hlsl"
            

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            #include "Includes/CTI URP Billboard.hlsl"

            float3 _LightDirection;

            CTIVertexBBOutput ShadowPassVertex(CTIVertexBBInput input)
            {
                CTIVertexBBOutput output = (CTIVertexBBOutput)0;
                UNITY_SETUP_INSTANCE_ID(input);
                //UNITY_TRANSFER_INSTANCE_ID(input, output);
                
                CTIBillboardVert(input, _LightDirection);

                output.uv = input.texcoord.xy;

                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldDir(input.normalOS);

                output.positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, _LightDirection));

                #if UNITY_REVERSED_Z
                    output.positionCS.z = min(output.positionCS.z, output.positionCS.w * UNITY_NEAR_CLIP_VALUE);
                #else
                    output.positionCS.z = max(output.positionCS.z, output.positionCS.w * UNITY_NEAR_CLIP_VALUE);
                #endif
                return output;
            }

            half4 ShadowPassFragment(CTIVertexOutput IN) : SV_TARGET
            {
                //UNITY_SETUP_INSTANCE_ID(IN);
                #if defined(LOD_FADE_CROSSFADE) && !defined(SHADER_API_GLES)
                    LODDitheringTransition(IN.positionCS.xyz, unity_LODFade.x);
                #endif
                half alpha = SampleAlbedoAlpha(IN.uv.xy, TEXTURE2D_ARGS(_BaseMap, sampler_BaseMap)).a;
                clip(alpha - _Cutoff);
                return 0;
            }
            ENDHLSL
        }

//  Depth -----------------------------------------------------
        Pass
        {
            Name "DepthOnly"
            Tags {"LightMode" = "DepthOnly"}

            ZWrite On
            ColorMask 0
            Cull Off

            HLSLPROGRAM
            // Required to compile gles 2.0 with standard srp library
            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x
            #pragma target 2.0

            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment

            // -------------------------------------
            // Material Keywords
            #define _ALPHATEST_ON 1

            #define CTIBILLBOARD

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing
            #pragma multi_compile _ LOD_FADE_CROSSFADE

            #define DEPTHONLYPASS

            #include "Includes/CTI URP Inputs.hlsl"
            #include "Includes/CTI URP Billboard.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CTIVertexBBOutput DepthOnlyVertex(CTIVertexBBInput input)
            {
                CTIVertexBBOutput output = (CTIVertexBBOutput)0;
                UNITY_SETUP_INSTANCE_ID(input);
                //UNITY_TRANSFER_INSTANCE_ID(input, output);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                CTIBillboardVert(input, 0);

                VertexPositionInputs vertexPosition = GetVertexPositionInputs(input.positionOS.xyz);
                output.uv.xy = input.texcoord.xy;
                output.positionCS = vertexPosition.positionCS;
                return output;
            }

            half4 DepthOnlyFragment(CTIVertexBBOutput IN) : SV_TARGET
            {
                //UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(IN);

                #if defined(LOD_FADE_CROSSFADE) && !defined(SHADER_API_GLES) // enable dithering LOD transition if user select CrossFade transition in LOD group
                    LODDitheringTransition(IN.positionCS.xyz, unity_LODFade.x);
                #endif
                half alpha = SampleAlbedoAlpha(IN.uv.xy, TEXTURE2D_ARGS(_BaseMap, sampler_BaseMap)).a;
                clip(alpha - _Cutoff);
                return 0;
            }

            ENDHLSL
        }

//  Depth Normal -----------------------------------------------------
        Pass
        {
            Name "DepthNormals"
            Tags{"LightMode" = "DepthNormals"}

            ZWrite On
            Cull Off

            HLSLPROGRAM
            // Required to compile gles 2.0 with standard srp library
            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x
            #pragma target 2.0

            #pragma vertex DepthNormalsVertex
            #pragma fragment DepthNormalsFragment

            // -------------------------------------
            // Material Keywords
            #define _ALPHATEST_ON 1

            #define CTIBILLBOARD

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing
            #pragma multi_compile _ LOD_FADE_CROSSFADE

            #define DEPTHNORMALPASS

            #include "Includes/CTI URP Inputs.hlsl"
            #include "Includes/CTI URP Billboard.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CTIVertexBBOutput DepthNormalsVertex(CTIVertexBBInput input)
            {
                CTIVertexBBOutput output = (CTIVertexBBOutput)0;
                UNITY_SETUP_INSTANCE_ID(input);
                //UNITY_TRANSFER_INSTANCE_ID(input, output);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                CTIBillboardVert(input, 0);

                VertexPositionInputs vertexPosition = GetVertexPositionInputs(input.positionOS.xyz);
                output.uv.xy = input.texcoord.xy;
                output.positionCS = vertexPosition.positionCS;
                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);
                output.normalWS = NormalizeNormalPerVertex(normalInput.normalWS);

                float sign = input.tangentOS.w * GetOddNegativeScale();
                output.tangentWS = float4(normalInput.tangentWS.xyz, sign);

                return output;
            }

            half4 DepthNormalsFragment(CTIVertexBBOutput input) : SV_TARGET
            {
                //UNITY_SETUP_INSTANCE_ID(input);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                #if defined(LOD_FADE_CROSSFADE) && !defined(SHADER_API_GLES) // enable dithering LOD transition if user select CrossFade transition in LOD group
                    LODDitheringTransition(input.positionCS.xyz, unity_LODFade.x);
                #endif
                half alpha = SampleAlbedoAlpha(input.uv.xy, TEXTURE2D_ARGS(_BaseMap, sampler_BaseMap)).a;
                clip(alpha - _Cutoff);

            //  Get the normal
                half4 sampleNormal = SAMPLE_TEXTURE2D(_BumpSpecMap, sampler_BumpSpecMap, input.uv.xy);
                half3 normalTS;
                normalTS.xy = sampleNormal.ag * 2.0h - 1.0h;
            //  Scale!
                normalTS.xy *= _BumpScale;
                normalTS.z = sqrt(1.0h - dot(normalTS.xy, normalTS.xy));

                float sgn = input.tangentWS.w;      // should be either +1 or -1
                float3 bitangent = sgn * cross(input.normalWS.xyz, input.tangentWS.xyz);
                input.normalWS = TransformTangentToWorld(normalTS, half3x3(input.tangentWS.xyz, bitangent, input.normalWS.xyz));

                return float4(PackNormalOctRectEncode(TransformWorldToViewDir(input.normalWS, true)), 0.0, 0.0);
            }

            ENDHLSL
        }


//  Meta -----------------------------------------------------

    }
    FallBack "Hidden/InternalErrorShader"
}
