Shader "CTI/URP LOD Leaves"
{
    Properties
    {

        [Header(Surface Options)]
        [Space(5)]

        [Enum(UnityEngine.Rendering.CullMode)]
        _Cull                           ("Culling", Float) = 0

        
        [Header(Surface Inputs)]
        [Space(5)]
        _HueVariation                   ("Color Variation", Color) = (0.9,0.5,0.0,0.1)
        [Space(5)]
        [NoScaleOffset]
        [MainTexture]
        _BaseMap                        ("Albedo (RGB) Alpha (A)", 2D) = "white" {}
        _Cutoff                         ("Alpha Cutoff", Range(0.0, 1.0)) = 0.5
        [Space(5)]
        [Toggle(_NORMALMAP)]
        _ApplyNormal                    ("Enable Normal (AG) Smoothness (B) Trans (R) Map", Float) = 1.0
        [NoScaleOffset]
        _BumpSpecMap                    ("    Normal (AG) Smoothness (B) Trans (R)", 2D) = "white" {}
        _Smoothness                     ("Smoothness", Range(0.0, 1.0)) = 0.5
        _SpecColor                      ("Specular", Color) = (0.2, 0.2, 0.2)


        [Header(Wrapped Diffuse Lighting)]
        [Space(5)]
        _Wrap                           ("Wrap", Range(0.0, 1.0)) = 0.5

        [Header(Transmission)]
        [Space(5)]
        [CTI_URPTransDrawer]
        _Translucency                   ("Strength (X) Power (Y) Distortion (Z)", Vector) = (1, 8, 0.01, 0)
        
        
        [Header(Wind Multipliers)]
        [Space(5)]
        [CTI_URPWindDrawer]
        _BaseWindMultipliers            ("Main (X) Branch (Y) Flutter (Z)", Vector) = (1,1,1,0)

        [Header(Advanced Wind)]
        [Space(5)]
        [Toggle(_LEAFTUMBLING)]
        _EnableLeafTumbling             ("Enable Leaf Tumbling", Float) = 1.0
        _TumbleStrength                 ("    Tumble Strength", Range(-1,1)) = 0
        _TumbleFrequency                ("    Tumble Frequency", Range(0,4)) = 1

        [Toggle(_LEAFTURBULENCE)]
        _EnableLeafTurbulence           ("Enable Leaf Turbulence", Float) = 0.0
        _LeafTurbulence                 ("    Leaf Turbulence", Range(0,4)) = 0.2
        _EdgeFlutterInfluence           ("    Edge Flutter Influence", Range(0,1)) = 0.25

        [Space(5)]
        [Toggle(_NORMALROTATION)]
        _EnableNormalRotation           ("Enable Normal Rotation", Float) = 0.0

        
        [Header(Ambient)]
        [Space(5)]
        _AmbientReflection              ("Ambient Reflection", Range(0, 1)) = 1

        
        [Header(Shadows)]
        [Space(5)]
        [Enum(UnityEngine.Rendering.CullMode)]
        _ShadowCulling                  ("Shadow Caster Culling", Float) = 0
        //_ShadowOffsetBias             ("ShadowOffsetBias", Float) = 1

        
        // Needed by VegetationStudio's Billboard Rendertex Shaders
        [HideInInspector] _IsBark("Is Bark", Float) = 0
        

    //  ObsoleteProperties
        [HideInInspector] _MainTex("BaseMap", 2D) = "white" {}
        // Do NOT define this as otherwise baked shadows will fail
        // [HideInInspector] _Color("Base Color", Color) = (1, 1, 1, 1)
        [HideInInspector] _GlossMapScale("Smoothness", Float) = 0.0
        [HideInInspector] _Glossiness("Smoothness", Float) = 0.0
        [HideInInspector] _GlossyReflections("EnvironmentReflections", Float) = 0.0

        [HideInInspector][NoScaleOffset]unity_Lightmaps("unity_Lightmaps", 2DArray) = "" {}
        [HideInInspector][NoScaleOffset]unity_LightmapsInd("unity_LightmapsInd", 2DArray) = "" {}
        [HideInInspector][NoScaleOffset]unity_ShadowMasks("unity_ShadowMasks", 2DArray) = "" {}
    }

    SubShader
    {

        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "UniversalMaterialType" = "Lit"
            "RenderType" = "Opaque"
            "Queue"="AlphaTest"
            "DisableBatching" = "LODFading"
            "IgnoreProjector" = "True"
        }
        LOD 300


//  Base -----------------------------------------------------
        Pass
        {
            Name "ForwardLit"
            Tags{"LightMode" = "UniversalForward"}

            ZWrite On
            Cull [_Cull]

            HLSLPROGRAM
            // Required to compile gles 2.0 with standard SRP library
            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x
            #pragma target 2.0

            // -------------------------------------
            // Material Keywords
            #define _ALPHATEST_ON 1
            #define _SPECULAR_SETUP

            #define CTILEAVES
            #pragma shader_feature_local_vertex _LEAFTUMBLING
            #pragma shader_feature_local_vertex _LEAFTURBULENCE
            #pragma shader_feature _NORMALMAP

            #pragma shader_feature_local_vertex _NORMALROTATION

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
            //#pragma multi_compile _ DIRLIGHTMAP_COMBINED
            //#pragma multi_compile _ LIGHTMAP_ON
            #pragma multi_compile_fog
            
            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing
            #pragma instancing_options assumeuniformscaling maxcount:50

            #pragma multi_compile _ LOD_FADE_CROSSFADE
            #pragma multi_compile_vertex LOD_FADE_PERCENTAGE

            // As Unity 2019.1 will always enable LOD_FADE_CROSSFADE and LOD_FADE_PERCENTAGE
            #if UNITY_VERSION < 201920
                #undef LOD_FADE_CROSSFADE
            #endif

            #include "Includes/CTI URP Inputs.hlsl"
            #include "Includes/CTI URP Bending.hlsl"
            #include "Includes/CTI URP Lighting.hlsl"

			#pragma vertex LitPassVertex
			#pragma fragment LitPassFragment


/// --------
            void InitializeInputData(CTIVertexOutput input, half3 normalTS, out InputData inputData)
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

			CTIVertexOutput LitPassVertex(CTIVertexInput input)
			{
				CTIVertexOutput output = (CTIVertexOutput)0;

                UNITY_SETUP_INSTANCE_ID(input);
                //UNITY_TRANSFER_INSTANCE_ID(input, output);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                CTI_AnimateVertex(
                    input,
                    #if defined (_BENDINGCOLRSONLY)
                        float4(input.color.rg, input.color.ab), // animParams,
                    #else
                        float4(input.color.rg, input.texcoord1.xy), // animParams,
                    #endif
                    _BaseWindMultipliers
                );

            //  CTI special
                output.occlusionVariation = input.color.ar;

                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);
                half3 vertexLight = VertexLighting(vertexInput.positionWS, normalInput.normalWS);
                half fogFactor = ComputeFogFactor(vertexInput.positionCS.z);

                output.uv.xy = input.texcoord;

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


            half4 LitPassFragment(CTIVertexOutput IN, half facing : VFACE) : SV_Target
			{
                //UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(IN);

                #if defined(LOD_FADE_CROSSFADE) && !defined(SHADER_API_GLES)
                    LODDitheringTransition(IN.positionCS.xyz, unity_LODFade.x);
                #endif

                SurfaceDescriptionLeaves surfaceData;
            //  Get the surface description / defined in "Includes/CTI LWRP Inputs.hlsl"
                InitializeLeavesLitSurfaceData(IN.occlusionVariation.y, IN.uv.xy, surfaceData);

            //  Add ambient occlusion from vertex input
                surfaceData.occlusion = IN.occlusionVariation.x;


                #if defined(_NORMALMAP)
                    surfaceData.normalTS.z *= facing;
                #else
                    IN.normalWS *= facing;
                #endif 

                InputData inputData;
                InitializeInputData(IN, surfaceData.normalTS, inputData);

            //  Apply lighting
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
            Cull [_ShadowCulling]

            HLSLPROGRAM
            // Required to compile gles 2.0 with standard srp library
            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x
            #pragma target 2.0

            // -------------------------------------
            // Material Keywords
            #define _ALPHATEST_ON 1
            #define CTILEAVES
            #pragma shader_feature_local_vertex _LEAFTUMBLING
            #pragma shader_feature_local_vertex _LEAFTURBULENCE

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing
            #pragma instancing_options assumeuniformscaling maxcount:50
            
            #pragma multi_compile _ LOD_FADE_CROSSFADE
            #pragma multi_compile_vertex LOD_FADE_PERCENTAGE

            // As Unity 2019.1 will always enable LOD_FADE_CROSSFADE and LOD_FADE_PERCENTAGE
            #if UNITY_VERSION < 201920
                #undef LOD_FADE_CROSSFADE
            #endif

            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment

            #define SHADOWSONLYPASS

            #include "Includes/CTI URP Inputs.hlsl"
            #include "Includes/CTI URP Bending.hlsl"

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float3 _LightDirection;

            CTIVertexOutput ShadowPassVertex(CTIVertexInput input)
            {
                CTIVertexOutput output;
                UNITY_SETUP_INSTANCE_ID(input);
                //UNITY_TRANSFER_INSTANCE_ID(input, output);
                
                CTI_AnimateVertex(
                    input,
                    #if defined (_BENDINGCOLRSONLY)
                        float4(input.color.rg, input.color.ab), // animParams,
                    #else
                        float4(input.color.rg, input.texcoord1.xy), // animParams,
                    #endif
                    _BaseWindMultipliers
                ); 

                output.uv = input.texcoord;

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

            half4 ShadowPassFragment(CTIVertexOutput IN) : SV_TARGET {
                //UNITY_SETUP_INSTANCE_ID(IN);

                #if defined(LOD_FADE_CROSSFADE) && !defined(SHADER_API_GLES)
                   LODDitheringTransition(IN.positionCS.xyz, unity_LODFade.x);
                #endif
                half alpha = SampleAlbedoAlpha(IN.uv, TEXTURE2D_ARGS(_BaseMap, sampler_BaseMap)).a;

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
            Cull [_Cull]

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
            #define CTILEAVES
            #pragma shader_feature_local_vertex _LEAFTUMBLING
            #pragma shader_feature_local_vertex _LEAFTURBULENCE

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing
            #pragma instancing_options assumeuniformscaling maxcount:50
            
            #pragma multi_compile _ LOD_FADE_CROSSFADE
            #pragma multi_compile_vertex LOD_FADE_PERCENTAGE

            // As Unity 2019.1 will always enable LOD_FADE_CROSSFADE and LOD_FADE_PERCENTAGE
            #if UNITY_VERSION < 201920
                #undef LOD_FADE_CROSSFADE
            #endif

            #define DEPTHONLYPASS

            #include "Includes/CTI URP Inputs.hlsl"
            #include "Includes/CTI URP Bending.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CTIVertexOutput DepthOnlyVertex(CTIVertexInput input)
            {
                CTIVertexOutput output = (CTIVertexOutput)0;
                UNITY_SETUP_INSTANCE_ID(input);
                //UNITY_TRANSFER_INSTANCE_ID(input, output);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                CTI_AnimateVertex(
                    input,
                    #if defined (_BENDINGCOLRSONLY)
                        float4(input.color.rg, input.color.ab), // animParams,
                    #else
                        float4(input.color.rg, input.texcoord1.xy), // animParams,
                    #endif
                    _BaseWindMultipliers
                ); 

                VertexPositionInputs vertexPosition = GetVertexPositionInputs(input.positionOS);
                output.uv.xy = input.texcoord;
                output.positionCS = vertexPosition.positionCS;
                return output;
            }

            half4 DepthOnlyFragment(CTIVertexOutput IN) : SV_TARGET
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
            Cull [_Cull]

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
            #define CTILEAVES
            #pragma shader_feature_local_vertex _LEAFTUMBLING
            #pragma shader_feature_local_vertex _LEAFTURBULENCE

            #pragma shader_feature_local_vertex _NORMALROTATION

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing
            #pragma instancing_options assumeuniformscaling maxcount:50
            
            #pragma multi_compile _ LOD_FADE_CROSSFADE
            #pragma multi_compile_vertex LOD_FADE_PERCENTAGE

            // As Unity 2019.1 will always enable LOD_FADE_CROSSFADE and LOD_FADE_PERCENTAGE
            #if UNITY_VERSION < 201920
                #undef LOD_FADE_CROSSFADE
            #endif

            #define DEPTHNORMALPASS

            #include "Includes/CTI URP Inputs.hlsl"
            #include "Includes/CTI URP Bending.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CTIVertexOutput DepthNormalsVertex(CTIVertexInput input)
            {
                CTIVertexOutput output = (CTIVertexOutput)0;
                UNITY_SETUP_INSTANCE_ID(input);
                //UNITY_TRANSFER_INSTANCE_ID(input, output);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                CTI_AnimateVertex(
                    input,
                    #if defined (_BENDINGCOLRSONLY)
                        float4(input.color.rg, input.color.ab), // animParams,
                    #else
                        float4(input.color.rg, input.texcoord1.xy), // animParams,
                    #endif
                    _BaseWindMultipliers
                ); 

                VertexPositionInputs vertexPosition = GetVertexPositionInputs(input.positionOS);
                output.uv.xy = input.texcoord;
                output.positionCS = vertexPosition.positionCS;
                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, float4(1,1,1,1)); // input.tangentOS);
    			output.normalWS = NormalizeNormalPerVertex(normalInput.normalWS);
                return output;
            }

            half4 DepthNormalsFragment(CTIVertexOutput input) : SV_TARGET
            {
                //UNITY_SETUP_INSTANCE_ID(input);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                #if defined(LOD_FADE_CROSSFADE) && !defined(SHADER_API_GLES) // enable dithering LOD transition if user select CrossFade transition in LOD group
                    LODDitheringTransition(input.positionCS.xyz, unity_LODFade.x);
                #endif
                half alpha = SampleAlbedoAlpha(input.uv.xy, TEXTURE2D_ARGS(_BaseMap, sampler_BaseMap)).a;
                clip(alpha - _Cutoff);
                return float4(PackNormalOctRectEncode(TransformWorldToViewDir(input.normalWS, true)), 0.0, 0.0);
            }

            ENDHLSL
        }


//  Selection = Depth -----------------------------------------------------
        Pass
        {
            Name "SceneSelectionPass"
            Tags{"LightMode" = "SceneSelectionPass"}
        
            ZWrite On
            ColorMask 0
            AlphaToMask On
            Cull [_Cull]

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
            #define CTILEAVES
            #pragma shader_feature_local_vertex _LEAFTUMBLING
            #pragma shader_feature_local_vertex _LEAFTURBULENCE

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing
            #pragma instancing_options assumeuniformscaling maxcount:50
            
            #pragma multi_compile _ LOD_FADE_CROSSFADE
            #pragma multi_compile_vertex LOD_FADE_PERCENTAGE

            // As Unity 2019.1 will always enable LOD_FADE_CROSSFADE and LOD_FADE_PERCENTAGE
            #if UNITY_VERSION < 201920
                #undef LOD_FADE_CROSSFADE
            #endif

            #define DEPTHONLYPASS

            #include "Includes/CTI URP Inputs.hlsl"
            #include "Includes/CTI URP Bending.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CTIVertexOutput DepthOnlyVertex(CTIVertexInput input)
            {
                CTIVertexOutput output = (CTIVertexOutput)0;
                UNITY_SETUP_INSTANCE_ID(input);
                //UNITY_TRANSFER_INSTANCE_ID(input, output);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                CTI_AnimateVertex(
                    input,
                    #if defined (_BENDINGCOLRSONLY)
                        float4(input.color.rg, input.color.ab), // animParams,
                    #else
                        float4(input.color.rg, input.texcoord1.xy), // animParams,
                    #endif
                    _BaseWindMultipliers
                ); 

                VertexPositionInputs vertexPosition = GetVertexPositionInputs(input.positionOS);
                output.uv.xy = input.texcoord;
                output.positionCS = vertexPosition.positionCS;

                return output;
            }

            half4 DepthOnlyFragment(CTIVertexOutput IN) : SV_TARGET
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

//  Meta -----------------------------------------------------
        Pass
        {
            Tags {"LightMode" = "Meta"}

            Cull Off

            HLSLPROGRAM
            // Required to compile gles 2.0 with standard srp library
            #pragma prefer_hlslcc gles

            #pragma vertex UniversalVertexMeta
            #pragma fragment UniversalFragmentMeta

            #define _SPECULAR_SETUP
            #define _ALPHATEST_ON 1

            #pragma shader_feature _SPECGLOSSMAP

            #include "Includes/CTI URP Inputs.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitMetaPass.hlsl"

            ENDHLSL
        }
    }
    CustomEditor "CTI_URP_ShaderGUI"
    FallBack "Hidden/InternalErrorShader"
}