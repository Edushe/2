Shader "Defferer/GBufferReady2D"
{
    Properties
    {
        _MainTex ("Sprite Texture", 2D) = "white" {}
        _Color ("Main Color", Color) = (1,1,1,1)
		[Toggle(_CLIPPING)] _Clipping ("Alpha Clipping", Float) = 0
        _Cutoff ("Cut Off Value", Range(0, 1)) = 0.2

		[Toggle(_MASK_MAP)] _MaskMapToggle ("Mask Map", Float) = 0
		[NoScaleOffset] _MaskMap("Mask (MODS)", 2D) = "white" {}
		_Metallic ("Metallic", Range(0, 1)) = 0
		_Smoothness ("Smoothness", Range(0, 1)) = 0.5
		_Fresnel ("Fresnel", Range(0, 1)) = 1

		[Toggle(_NORMAL_MAP)] _NormalMapToggle ("Normal Map", Float) = 0
		[NoScaleOffset] _NormalMap("Normals", 2D) = "bump" {}
		_NormalScale("Normal Scale", Range(0, 1)) = 1

		[NoScaleOffset] _EmissionMap("Emission", 2D) = "white" {}
		[HDR] _EmissionColor("Emission", Color) = (0.0, 0.0, 0.0, 0.0)

		[Toggle(_DETAIL_MAP)] _DetailMapToggle ("Detail Maps", Float) = 0
		_DetailMap("Details", 2D) = "linearGrey" {}
		[NoScaleOffset] _DetailNormalMap("Detail Normals", 2D) = "bump" {}
		_DetailAlbedo("Detail Albedo", Range(0, 1)) = 1
		_DetailSmoothness("Detail Smoothness", Range(0, 1)) = 1
		_DetailNormalScale("Detail Normal Scale", Range(0, 1)) = 1

    }
    SubShader
    {
        HLSLINCLUDE
            #include "../../ShaderLibrary/Common.hlsl"
            #include "HLSL/GBufferInput2D.hlsl"
		ENDHLSL
        Pass
        {
            Tags {
                "LightMode" = "OutGBuffer"
            }
			Cull Off

            HLSLPROGRAM
            #pragma vertex LitPassVertex
            #pragma fragment LitPassFragment

			#pragma target 3.5
			#pragma shader_feature _CLIPPING
			#pragma shader_feature _MASK_MAP
			#pragma shader_feature _NORMAL_MAP
			#pragma shader_feature _DETAIL_MAP
			#pragma multi_compile _ LIGHTMAP_ON
			
			#pragma multi_compile_instancing
			#include "HLSL/GBufferPass2D.hlsl"
			ENDHLSL
        }

    }
}
