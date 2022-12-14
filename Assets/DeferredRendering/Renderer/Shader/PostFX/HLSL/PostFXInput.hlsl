#ifndef DEFFER_POST_INPUT
#define DEFFER_POST_INPUT


//获得主纹理的采用模式，因为需要采集雾效
SAMPLER(sampler_PostFXSource);
TEXTURE2D(_PostFXSource);
TEXTURE2D(_PostFXSource2);

TEXTURE2D(_CameraNormalTexture);
SAMPLER(sampler_CameraNormalTexture);

TEXTURE2D(_GBufferColorTex);
SAMPLER(sampler_GBufferColorTex);
TEXTURE2D(_GBufferNormalTex);
SAMPLER(sampler_GBufferNormalTex);
TEXTURE2D(_GBufferDepthTex);
TEXTURE2D(_GBufferSpecularTex);
TEXTURE2D(_GBufferBakeTex);


float4x4 _FrustumCornersRay;
float4x4 _InverseProjectionMatrix;
float4x4 _WorldToCamera;
float4x4 _ViewToScreenMatrix;
float4x4 _InverseVPMatrix;

float4 _ScreenSize;
int _MaxRayMarchingStep;
float _RayMarchingStepSize;
float _MaxRayMarchingDistance;
float _DepthThickness;

float4 _PostFXSource_TexelSize;
bool _BloomBicubicUpsampling;
float _BloomIntensity;
float4 _BloomThreshold;

float _BulkLightCheckMaxDistance;
float _BulkSampleCount;
float _BulkLightShrinkRadio;
float _BulkLightScatterRadio;

float _BilaterFilterFactor;
float4 _BlurRadius;

#define _COUNT 6

float _FogMaxDepth;
float _FogMinDepth;
float _FogDepthFallOff;
float _FogMaxHight;
float _FogMinHight;
float _FogPosYFallOff;

float4 _Colors[_COUNT];  //颜色计算用的数据

float4 GetSourceTexelSize () {
	return _PostFXSource_TexelSize;
}

float4 GetSource(float2 screenUV) {
	return SAMPLE_TEXTURE2D_LOD(_PostFXSource, sampler_linear_clamp, screenUV, 0);
}

float4 GetSourceBicubic (float2 screenUV) {
	return SampleTexture2DBicubic(
		TEXTURE2D_ARGS(_PostFXSource, sampler_linear_clamp), screenUV,
		_PostFXSource_TexelSize.zwxy, 1.0, 0.0
	);
}

float4 GetSource2(float2 screenUV) {
	return SAMPLE_TEXTURE2D_LOD(_PostFXSource2, sampler_linear_clamp, screenUV, 0);
}

float3 GetWorldPos(float depth, float2 uv){
    #if defined(UNITY_REVERSED_Z)
        depth = 1 - depth;
    #endif
	float4 ndc = float4(uv.x * 2 - 1, uv.y * 2 - 1, depth * 2 - 1, 1);

	float4 worldPos = mul(_InverseVPMatrix, ndc);
	worldPos /= worldPos.w;
	return worldPos.xyz;
}


#define random(seed) sin(seed * 641.5467987313875 + 1.943856175)


void swap(inout float v0, inout float v1)
{
    float temp = v0;
    v0 = v1;
    v1 = temp;
}

float distanceSquared(float2 A, float2 B)
{
    A -= B;
    return dot(A, A);
}

bool screenSpaceRayMarching(float3 rayOri, float3 rayDir, inout float2 hitScreenPos)
{
    //反方向反射的，本身也看不见，索性直接干掉
     if (rayDir.z > 0.0)
         return false;
    //首先求得视空间终点位置，不超过最大距离
    float magnitude = _MaxRayMarchingDistance;
    float end = rayOri.z + rayDir.z * magnitude;
    //如果光线反过来超过了近裁剪面，需要截取到近裁剪面
    if (end > -_ProjectionParams.y)
        magnitude = (-_ProjectionParams.y - rayOri.z) / rayDir.z;
    float3 rayEnd = rayOri + rayDir * magnitude;
    //直接把cliptoscreen与projection矩阵结合，得到齐次坐标系下屏幕位置
    float4 homoRayOri = mul(_ViewToScreenMatrix, float4(rayOri, 1.0));
    float4 homoRayEnd = mul(_ViewToScreenMatrix, float4(rayEnd, 1.0));
    //w
    float kOri = 1.0 / homoRayOri.w;
    float kEnd = 1.0 / homoRayEnd.w;
    //屏幕空间位置
    float2 screenRayOri = homoRayOri.xy * kOri;
    float2 screenRayEnd = homoRayEnd.xy * kEnd;
    screenRayEnd = (distanceSquared(screenRayEnd, screenRayOri) < 0.0001) ? screenRayOri + float2(0.01, 0.01) : screenRayEnd;
    
    float3 QOri = rayOri * kOri;
    float3 QEnd = rayEnd * kEnd;
    
    float2 displacement = screenRayEnd - screenRayOri;
    bool permute = false;
    if (abs(displacement.x) < abs(displacement.y))
    {
        permute = true;
        
        displacement = displacement.yx;
        screenRayOri.xy = screenRayOri.yx;
        screenRayEnd.xy = screenRayEnd.yx;
    }
    float dir = sign(displacement.x);
    float invdx = dir / displacement.x;
    float2 dp = float2(dir, invdx * displacement.y) * _RayMarchingStepSize;
    float3 dq = (QEnd - QOri) * invdx * _RayMarchingStepSize;
    float  dk = (kEnd - kOri) * invdx * _RayMarchingStepSize;
    float rayZmin = rayOri.z;
    float rayZmax = rayOri.z;
    float preZ = rayOri.z;
    
    float2 screenPoint = screenRayOri;
    float3 Q = QOri;
    float k = kOri;

    float random = random((rayDir.y + rayDir.x) * _ScreenParams.x * _ScreenParams.y + 0.2312312);

    dq *= lerp(0.9, 1, random);
    dk *= lerp(0.9, 1, random);

    // UNITY_UNROLL
    for(int i = 0; i < _MaxRayMarchingStep; i++)
    {
        //向前步进一个单位
        screenPoint += dp;
        Q.z += dq.z;
        k += dk;
        
        //得到步进前后两点的深度
        rayZmin = preZ;
        rayZmax = (dq.z * 0.5 + Q.z) / (dk * 0.5 + k);
        preZ = rayZmax;
        if (rayZmin > rayZmax)
        {
            swap(rayZmin, rayZmax);
        }
        
        //得到当前屏幕空间位置，交换过的xy换回来，并且根据像素宽度还原回（0,1）区间而不是屏幕区间
        hitScreenPos = permute ? screenPoint.yx : screenPoint;
        hitScreenPos *= _ScreenSize.xy;
        
        //转换回屏幕（0,1）区间，剔除出屏幕的反射
        if (any(hitScreenPos.xy < 0.0) || any(hitScreenPos.xy > 1.0))
            return false;
        
        //采样当前点深度图，转化为视空间的深度（负值）
        float bufferDepth = SAMPLE_DEPTH_TEXTURE_LOD(_GBufferDepthTex, sampler_point_clamp, hitScreenPos, 0);
        float depth = -LinearEyeDepth(bufferDepth, _ZBufferParams);
        
        bool isBehand = (rayZmin <= depth);
        bool intersecting = isBehand && (rayZmax >= depth - _DepthThickness);
        
        if (intersecting)
            return true;
    }
    return false;
}

float3 GetBulkLight(float depth, float2 screenUV, float3 interpolatedRay){
    float bufferDepth = IsOrthographicCamera() ? OrthographicDepthBufferToLinear(depth) 
		: LinearEyeDepth(depth, _ZBufferParams);

    float3 worldPos = _WorldSpaceCameraPos + bufferDepth * interpolatedRay;
    float3 startPos = _WorldSpaceCameraPos + _ProjectionParams.y * interpolatedRay;

    float3 direction = normalize(worldPos - startPos);
    float dis = length(worldPos - startPos);

    float m_length = min(_BulkLightCheckMaxDistance, dis);
    float perNodeLength = m_length / _BulkSampleCount;
    float perDepthLength = bufferDepth / _BulkSampleCount;
    float3 currentPoint = startPos;
    float3 viewDirection = normalize(_WorldSpaceCameraPos - worldPos);

    float3 color = 0;
    float seed = random((screenUV.y + screenUV.x) * _ScreenParams.x * _ScreenParams.y * _ScreenParams.z + 0.2312312);
    // float seed = random((screenUV.y + screenUV.x) * 1000 + 0.2312312);
    float currentDepth = 0;

    // UNITY_UNROLL
    for(int i=0; i<_BulkSampleCount; i++){
        currentPoint += direction * perNodeLength;
        currentDepth += perDepthLength;
        float3 tempPosition = lerp(currentPoint, currentPoint + direction * perNodeLength, seed);
        color += GetBulkLighting(tempPosition, viewDirection, screenUV, _BulkLightScatterRadio, currentDepth);
    }
    color *= m_length * _BulkLightShrinkRadio ;

    return color;
}

half LinearRgbToLuminance(half3 linearRgb)
{
    return dot(linearRgb, half3(0.2126729f,  0.7151522f, 0.0721750f));
}

float CompareColor(float4 col1, float4 col2)
{
	float l1 = LinearRgbToLuminance(col1.rgb);
	float l2 = LinearRgbToLuminance(col2.rgb);
	return smoothstep(_BilaterFilterFactor, 1.0, 1.0 - abs(l1 - l2));
}

float3 LoadColor(float time_01) {
    for (int i = 1; i < _COUNT; i++) {
        if (time_01 <= _Colors[i].w) {
            float radio = smoothstep(_Colors[i - 1].w, _Colors[i].w, time_01);
            return lerp(_Colors[i - 1].xyz, _Colors[i].xyz, radio);
        }
    }
    return 0;
}


// float4 Sample (float2 uv) {
//     return tex2Dlod(_MainTex, float4(uv, 0, 0));	//避免一些问题，使用Load加载，其实没什么区别
// }

float SampleLuminance (float2 uv) {
    #if defined(LUMINANCE_GREEN)
        return GetSource(uv).g;
    #else
        return GetSource(uv).a;
    #endif
}

float SampleLuminance (float2 uv, float uOffset, float vOffset) {
    uv += _PostFXSource_TexelSize.xy * float2(uOffset, vOffset);
    return SampleLuminance(uv);
}

struct LuminanceData {
    float m, n, e, s, w;
    float ne, nw, se, sw;
    float highest, lowest, contrast;
};
float _ContrastThreshold, _RelativeThreshold;
float _SubpixelBlending;

LuminanceData SampleLuminanceNeighborhood (float2 uv) {
    LuminanceData l;
    l.m = SampleLuminance(uv);			//中间
    //上下左右
    l.n = SampleLuminance(uv, 0,  1);
    l.e = SampleLuminance(uv, 1,  0);
    l.s = SampleLuminance(uv, 0, -1);
    l.w = SampleLuminance(uv,-1,  0);

    //东南、东北方向等四个方向
    l.ne = SampleLuminance(uv,  1,  1);
    l.nw = SampleLuminance(uv, -1,  1);
    l.se = SampleLuminance(uv,  1, -1);
    l.sw = SampleLuminance(uv, -1, -1);

    l.highest = max(max(max(max(l.n, l.e), l.s), l.w), l.m);	//最高亮度
    l.lowest = min(min(min(min(l.n, l.e), l.s), l.w), l.m);		//最低亮度
    l.contrast = l.highest - l.lowest;		//获得最高亮度与最低亮度之间的差
    return l;
}
		
//根据传入的阈值以及高度影响值，判断是否应该跳过该像素，不进行FXAA
bool ShouldSkipPixel (LuminanceData l) {
    float threshold =
        max(_ContrastThreshold, _RelativeThreshold * l.highest);
    return l.contrast < threshold;
}

//确定混合因子, 这个只控制边界的直接混合模式, 与边框的混合是独立的
float DeterminePixelBlendFactor (LuminanceData l) {
    float filter = 2 * (l.n + l.e + l.s + l.w);		//上下左右占比
    filter += l.ne + l.nw + l.se + l.sw;			//四边占比小一点
    filter *= 1.0 / 12;
    filter = abs(filter - l.m);			//混合因子由自身以及四周的对比度差决定
    filter = saturate(filter / l.contrast);		//根据对比度差进行归一化,不然进过上面变太小了
    float blendFactor = smoothstep(0, 1, filter);
    return blendFactor * blendFactor * _SubpixelBlending;
}

struct EdgeData {
    bool isHorizontal;
    float pixelStep;
    float oppositeLuminance, gradient;	//沿着边
};

//确定边缘，因为不是直接周围模糊，因此需要根据四周的灰度值判断可能的模糊朝向
//这里为了更好的效果，使用了四周采用，而不是直接十字
EdgeData DetermineEdge (LuminanceData l) {
    EdgeData e;
    float horizontal =
        abs(l.n + l.s - 2 * l.m) * 2 +
        abs(l.ne + l.se - 2 * l.e) +
        abs(l.nw + l.sw - 2 * l.w);
    float vertical =
        abs(l.e + l.w - 2 * l.m) * 2 +
        abs(l.ne + l.nw - 2 * l.n) +
        abs(l.se + l.sw - 2 * l.s);
    //检查水平还是垂直的亮度差大，大的就是要模糊的方向
    e.isHorizontal = horizontal >= vertical;

    //左右选一边
    float pLuminance = e.isHorizontal ? l.n : l.e;
    //上下选一边
    float nLuminance = e.isHorizontal ? l.s : l.w;
    
    //判断与中间的差
    float pGradient = abs(pLuminance - l.m);
    float nGradient = abs(nLuminance - l.m);

    //获得像素尺寸，比较等会是单边模糊，而上下的每一个像素数量是不一致的
    e.pixelStep =
        e.isHorizontal ? _PostFXSource_TexelSize.y : _PostFXSource_TexelSize.x;

    //最后确定偏移的方向，是正方向还是负方向，比较上面只判断了水平还是垂直
    if (pGradient < nGradient) {
        e.pixelStep = -e.pixelStep;
        e.oppositeLuminance = nLuminance;	//偏移值就是差值
        e.gradient = nGradient;		//存储上下的差，之后需要朝这边偏移
    }
    else {
        e.oppositeLuminance = pLuminance;
        e.gradient = pGradient;
    }
    return e;
}

#if defined(LOW_QUALITY)
    #define EDGE_STEP_COUNT 4
    #define EDGE_STEPS 1, 1.5, 2, 4
    #define EDGE_GUESS 12
#else
    #define EDGE_STEP_COUNT 10
    #define EDGE_STEPS 1, 1.5, 2, 2, 2, 2, 2, 2, 2, 4
    #define EDGE_GUESS 8
#endif

static const float edgeSteps[EDGE_STEP_COUNT] = { EDGE_STEPS };

float DetermineEdgeBlendFactor (LuminanceData l, EdgeData e, float2 uv) {
    float2 uvEdge = uv;
    float2 edgeStep;
    //目标是沿着边走，但是并没有必要每一个都这么做，因此对移动方向的另一边偏移，而且只移动一步，采集中间的平均值
    if (e.isHorizontal) {
        uvEdge.y += e.pixelStep * 0.5;
        edgeStep = float2(_PostFXSource_TexelSize.x, 0);
    }
    else {
        uvEdge.x += e.pixelStep * 0.5;
        edgeStep = float2(0, _PostFXSource_TexelSize.y);
    }

    float edgeLuminance = (l.m + e.oppositeLuminance) * 0.5;	//平均值
    float gradientThreshold = e.gradient * 0.25;	
    
    float2 puv = uvEdge + edgeStep * edgeSteps[0];	//进行偏移
    float pLuminanceDelta = SampleLuminance(puv) - edgeLuminance;
    bool pAtEnd = abs(pLuminanceDelta) >= gradientThreshold;		//如果大于，就是到达边缘了

    //持续循环，查找边缘，且使用展开循环指令，优化性能
    int i;
    UNITY_UNROLL
    for (i = 1; i < EDGE_STEP_COUNT && !pAtEnd; i++) {
        puv += edgeStep * edgeSteps[i];
        pLuminanceDelta = SampleLuminance(puv) - edgeLuminance;
        pAtEnd = abs(pLuminanceDelta) >= gradientThreshold;
    }
    if (!pAtEnd) {
        puv += edgeStep * EDGE_GUESS;
    }

    float2 nuv = uvEdge - edgeStep * edgeSteps[0];
    float nLuminanceDelta = SampleLuminance(nuv) - edgeLuminance;
    bool nAtEnd = abs(nLuminanceDelta) >= gradientThreshold;

    // UNITY_UNROLL
    for (i = 1; i < EDGE_STEP_COUNT && !nAtEnd; i++) {
        nuv -= edgeStep * edgeSteps[i];
        nLuminanceDelta = SampleLuminance(nuv) - edgeLuminance;
        nAtEnd = abs(nLuminanceDelta) >= gradientThreshold;
    }
    if (!nAtEnd) {
        nuv -= edgeStep * EDGE_GUESS;
    }

    float pDistance, nDistance;
    if (e.isHorizontal) {
        pDistance = puv.x - uv.x;
        nDistance = uv.x - nuv.x;
    }
    else {
        pDistance = puv.y - uv.y;
        nDistance = uv.y - nuv.y;
    }
    
    float shortestDistance;
    bool deltaSign;
    if (pDistance <= nDistance) {
        shortestDistance = pDistance;
        deltaSign = pLuminanceDelta >= 0;
    }
    else {
        shortestDistance = nDistance;
        deltaSign = nLuminanceDelta >= 0;
    }

    if (deltaSign == (l.m - edgeLuminance >= 0)) {
        return 0;
    }
    return 0.5 - shortestDistance / (pDistance + nDistance);
}

float4 ApplyFXAA (float2 uv) {
    LuminanceData l = SampleLuminanceNeighborhood(uv);
    if (ShouldSkipPixel(l)) {		//跳过不需要的像素
        return GetSource(uv);
        // return 0;
    }

    float pixelBlend = DeterminePixelBlendFactor(l);
    EdgeData e = DetermineEdge(l);

    float edgeBlend = DetermineEdgeBlendFactor(l, e, uv);
    float finalBlend = max(pixelBlend, edgeBlend);

    // return finalBlend;

    if (e.isHorizontal) {
        uv.y += e.pixelStep * finalBlend;
    }
    else {
        uv.x += e.pixelStep * finalBlend;
    }
    return float4(GetSource(uv).rgb, l.m);
}



#endif