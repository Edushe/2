#ifndef DEFFER_GBUFFER_READY_PASS_INCLUDED
#define DEFFER_GBUFFER_READY_PASS_INCLUDED

#include "../../ShaderLibrary/Surface.hlsl"
#include "../../ShaderLibrary/Shadows.hlsl"
#include "../../ShaderLibrary/Light.hlsl"
#include "../../ShaderLibrary/BRDF.hlsl"
#include "../../ShaderLibrary/GI.hlsl"
#include "../../ShaderLibrary/Lighting.hlsl"

struct Attributes {
	float3 positionOS : POSITION;
	float3 normalOS : NORMAL;
	float4 tangentOS : TANGENT;
	float2 baseUV : TEXCOORD0;
	GI_ATTRIBUTE_DATA
	UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct Varyings {
	float4 positionCS_SS : SV_POSITION;
	float3 positionWS : VAR_POSITION;
	float3 normalWS : VAR_NORMAL;
	#if defined(_NORMAL_MAP)
		float4 tangentWS : VAR_TANGENT;
	#endif
	float2 baseUV : VAR_BASE_UV;
	#if defined(_DETAIL_MAP)
		float2 detailUV : VAR_DETAIL_UV;
	#endif
	GI_VARYINGS_DATA
	UNITY_VERTEX_INPUT_INSTANCE_ID
};

Varyings LitPassVertex (Attributes input) {
	Varyings output;
	UNITY_SETUP_INSTANCE_ID(input);
	UNITY_TRANSFER_INSTANCE_ID(input, output);
	TRANSFER_GI_DATA(input, output);
	output.positionWS = TransformObjectToWorld(input.positionOS);
	output.positionCS_SS = TransformWorldToHClip(output.positionWS);
	output.normalWS = TransformObjectToWorldNormal( input.normalOS );
	#if defined(_NORMAL_MAP)
		output.tangentWS = float4(
			TransformObjectToWorldDir(input.tangentOS.xyz), input.tangentOS.w
		);
	#endif
	output.baseUV = TransformBaseUV(input.baseUV);
	#if defined(_DETAIL_MAP)
		output.detailUV = TransformDetailUV(input.baseUV);
	#endif
	return output;
}

void LitPassFragment (Varyings input,
        out float4 _GBufferColorTex : SV_Target0,
        out float4 _GBufferNormalTex : SV_Target1,
        out float4 _GBufferSpecularTex : SV_Target2,
        out float4 _GBufferBakeTex : SV_Target3
    ) {
	UNITY_SETUP_INSTANCE_ID(input);
	InputConfig config = GetInputConfig(input.baseUV);
	ClipLOD(input.positionCS_SS.xy, unity_LODFade.x);
	
	#if defined(_MASK_MAP)
		config.useMask = true;
	#endif
	#if defined(_DETAIL_MAP)
		config.detailUV = input.detailUV;
		config.useDetail = true;
	#endif
	
	//????????????
	float4 base = GetBase(config);
	float3 positionWS = input.positionWS;
	#if defined(_CLIPPING)
		clip(base.a - GetCutoff(config));
	#endif
	
	float3 normal;
	float3 perNormal = input.normalWS;
	#if defined(_NORMAL_MAP)
		normal = NormalTangentToWorld(
			GetNormalTS(config), input.normalWS, input.tangentWS
		);
	#else
		normal = normalize(input.normalWS);
	#endif

	float width = GetWidth(config);
	float4 specularData = float4(GetMetallic(config), GetSmoothness(config), GetFresnel(config), width);		//w?????????1????????????PBR

	//?????????????????????????????????????????????????????????????????????????????????
	float3 bakeColor = GetBakeDate(GI_FRAGMENT_DATA(input), positionWS, perNormal);
	float oneMinusReflectivity = OneMinusReflectivity(specularData.r);
	float3 diffuse = base.rgb * oneMinusReflectivity;
	bakeColor = bakeColor * diffuse + GetEmission(config);				//?????????????????????????????????????????????????????????????????????????????????????????????????????????
	float4 shiftColor = GetShiftColor(config);			//??????????????????????????????????????????

	_GBufferColorTex = float4(base.xyz, shiftColor.x);
	_GBufferNormalTex = float4(normal * 0.5 + 0.5, shiftColor.y);
	_GBufferSpecularTex = specularData;

	_GBufferBakeTex = float4(bakeColor, shiftColor.z);
}


#endif