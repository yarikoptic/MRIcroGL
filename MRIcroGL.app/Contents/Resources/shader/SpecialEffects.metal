//pref
//showGradient|float|0|0|1|Display surface angle
//doPoor|float|0|1|1|Poor quality reveals rendering strategy
//doJitter|float|0|0|1|Jitter hides wood-grain artifacts
//showStartEnd|float|0|0.5|1|Show background box

//vert
#include <metal_stdlib>
//xcrun -sdk macosx metal -c SpecialEffects.metal -o Render.air

using namespace metal;

struct CustomFragUniforms {
	float showGradient;
	float doPoor;
	float doJitter;
	float showStartEnd;
};

struct VertexIn {
	float3 position;
	float4 color;
};

struct VertexOut {
	float4 position [[position]];
	float4 color;
};

struct Uniforms {
	float4x4 modelViewProjectionMatrix;
};

struct FragUniforms {
	float stepSiz;
	float sliceSiz;
	float overlayNum;
	float clipThick;
	float backAlpha, pad1, pad2, pad3;
	float4 rayDir;
	float4 lightPos;
	float4 clipPlane;
	float4x4 normMatrix;
};

vertex VertexOut vertexShader(  unsigned int vertexID               [[ vertex_id ]],
                                const device VertexIn* verts    [[ buffer(0) ]],
								const device Uniforms* uniforms    	[[ buffer(1) ]]
                                ) {
	VertexIn VertexIn = verts[vertexID];
	VertexOut VertexOut;
	VertexOut.position = uniforms->modelViewProjectionMatrix * float4(VertexIn.position, 1);
	VertexOut.color = VertexIn.color;
	return VertexOut;
}

float3 GetBackPosition (float3 startPosition, float3 rayDir) {
	//assume orthographic projection - perspective a bit trickier
	// http://prideout.net/blog/?p=64
	float3 invR = 1.0 / (rayDir);
    float3 tbot = invR * (float3(0.0)-startPosition);
    float3 ttop = invR * (float3(1.0)-startPosition);
    float3 tmax = max(ttop, tbot);
    float2 t = min(tmax.xx, tmax.yz);
	return startPosition + (rayDir * min(t.x, t.y));
}

fragment float4 fragmentShader(VertexOut  in [[stage_in]],
               texture3d<float> volTexture [[ texture(0) ]],
               texture3d<float> gradTexture [[ texture(1) ]],
               texture3d<float> overlayVolTexture [[ texture(2) ]],
               texture3d<float> overlayGradTexture [[ texture(3) ]],
			   const device FragUniforms* fragUniforms    	[[ buffer(1) ]],
               const device CustomFragUniforms* customFragUniforms    	[[ buffer(2) ]]
               ) {
	constexpr sampler textureSampler (mag_filter::linear,min_filter::linear, address::clamp_to_zero);
	float2 gl_FragCoord = float2(in.position.xy); //random jitter to reduce wood grain
	//float3 lightPosition = fragUniforms->lightPos.xyz;
	float backAlpha = fragUniforms->backAlpha;
	int overlays = round(fragUniforms->overlayNum);
	float overlayFuzzy = 0.5;
	float overlayDepth = 0.3;
	//float3x3 normalMatrix = float3x3(fragUniforms->normMatrix[0].xyz, fragUniforms->normMatrix[1].xyz, fragUniforms->normMatrix[2].xyz);
	float sliceSize = fragUniforms->sliceSiz;//for opacity correction
	float stepSize = fragUniforms->stepSiz;//sampling rate
	float clipThick = fragUniforms->clipThick;
	clipThick = max(clipThick, stepSize);
	if (customFragUniforms->doPoor > 0.5)
		stepSize *= 10.0;
	float4 clipPlane = fragUniforms->clipPlane;
	float showGradient = customFragUniforms->showGradient;
	float showStartEnd = customFragUniforms->showStartEnd;
	float3 start = in.color.rgb;
	float3 backPosition = GetBackPosition(start, fragUniforms->rayDir.xyz);
	float3 dir = backPosition - start;
	float len = length(dir);
	dir = normalize(dir);
	float4 deltaDir = float4(dir.xyz * stepSize, stepSize);
	float4 colorSample;
	float bgNearest = len; //assume no hit
	float4 colAcc = float4(0.0,0.0,0.0,0.0);
	//background pass
	float noClipLen = len;
	float4 samplePos = float4(start.xyz, 0.0);
	//start applyClip(): Apple Metal does not support inout, so classic C
	float cdot = dot(dir,clipPlane.xyz);
	if  ((clipPlane.a > 1.0) || (cdot == 0.0)) {
		//return samplePos;'
	} else {
		bool frontface = (cdot > 0.0);
		float dis = (-clipPlane.a - dot(clipPlane.xyz, samplePos.xyz-0.5)) / cdot;
		float  disBackFace = (-(clipPlane.a-clipThick) - dot(clipPlane.xyz, samplePos.xyz-0.5)) / cdot;
		if (((frontface) && (dis >= len)) || ((!frontface) && (dis <= 0.0)))
			samplePos.a = len + 1.0;
		else if (frontface) {
			dis = max(0.0, dis);
			samplePos = float4(samplePos.xyz+dir * dis, dis);
			len = min(disBackFace, len);
		} else {
			len = min(dis, len);
			disBackFace = max(0.0, disBackFace);
			samplePos = float4(samplePos.xyz+dir * disBackFace, disBackFace);
		}
	}
	float4 clipPos = samplePos;
	//end: applyClip()
	float opacityCorrection = stepSize/sliceSize;
	//fast pass - optional
	float4 deltaDirX2 = float4(dir.xyz * max(stepSize, sliceSize * 1.95), max(stepSize, sliceSize * 1.95));
	while  ( volTexture.sample(textureSampler, samplePos.xyz).a == 0.0) {
			samplePos += deltaDirX2;
			if (samplePos.a > len) break;
	}
	samplePos -= deltaDirX2;
	//end fast pass

	//if ((samplePos.a > len) && ( !hasOverlays )) { //no hit: quit here
	//if ((samplePos.a > len) && ( overlays < 1 )) {
	if (samplePos.a > len)  {
		return colAcc;	
	}	
	//end fastpass - optional
	float ran = fract(sin(gl_FragCoord.x * 12.9898 + gl_FragCoord.y * 78.233) * 43758.5453);
	if (customFragUniforms->doJitter > 0.5) 
		samplePos += deltaDir * ran;
	//float3 defaultDiffuse = float3(0.5, 0.5, 0.5);
	
	while (samplePos.a <= len) {
		colorSample = (volTexture.sample(textureSampler, samplePos.xyz));
		if (colorSample.a > 0.0) {
			if (showGradient > 0.5)
				colorSample.rgb = abs(gradTexture.sample(textureSampler, samplePos.xyz).rgb * 2.0 - 1.0);
				//float4 gradSample = gradTexture.sample(textureSampler, samplePos.xyz);
			
			colorSample.a = 1.0-pow((1.0 - colorSample.a), opacityCorrection);
			bgNearest = min(samplePos.a,bgNearest);
			colorSample.rgb *= colorSample.a;
			colAcc= (1.0 - colAcc.a) * colorSample + colAcc;
			if ( colAcc.a > 0.95 )
				break;
		}
		samplePos += deltaDir;
	}
	colAcc.a = colAcc.a/0.95;
	colAcc.a *= backAlpha;
	
	if (samplePos.a > (len +0.5)) {
		//	
	} else if (showStartEnd < 0.33) {
		colAcc.rgb = mix(clipPos.xyz, colAcc.rgb, colAcc.a);
		colAcc.a = 1.0;
	} else if (showStartEnd < 0.66) {
		colAcc.rgb = mix(clipPos.xyz + (dir * (len - clipPos.a)), colAcc.rgb, colAcc.a);
		colAcc.a = 1.0;
	}
	if ( overlays< 1 )
		return colAcc;
	//overlay pass
	float overFarthest = len;
	float4 overAcc = float4(0.0,0.0,0.0,0.0);
	float overlayClip = 1.0; //customFragUniforms->overlayClip;	
	if (overlayClip > 0)
		samplePos = clipPos;
	else {
		len = noClipLen;
		samplePos = float4(start.xyz +deltaDir.xyz* ran, 0.0);
	}
	//fast pass - optional
	clipPos = samplePos;
	deltaDirX2 = float4(dir.xyz * max(stepSize, sliceSize * 1.95), max(stepSize, sliceSize * 1.95));
	while  ( overlayVolTexture.sample(textureSampler, samplePos.xyz).a == 0.0) {
			samplePos += deltaDirX2;
			if (samplePos.a > len) break;
	}
	samplePos -= deltaDirX2;
	if (samplePos.a < clipPos.a)
		samplePos = clipPos;
	//deltaDir = float4(dir.xyz * stepSize, stepSize);
	//end fastpass - optional
	while (samplePos.a <= len) {
		colorSample = (overlayVolTexture.sample(textureSampler, samplePos.xyz));
		if (colorSample.a > 0.00) {
			colorSample.a = 1.0-pow((1.0 - colorSample.a), stepSize/sliceSize);
			colorSample.a *=  overlayFuzzy;
			overFarthest = samplePos.a;
			colorSample.rgb *= colorSample.a;
			overAcc= (1.0 - overAcc.a) * colorSample + overAcc;
			if (overAcc.a > 0.95 )
				break;
		}
		samplePos += deltaDir;
	} //while samplePos.a < len
	overAcc.a = overAcc.a/0.95;
	float overMix = overAcc.a;
	if (((overFarthest) > bgNearest) && (colAcc.a > 0.0)) { //background (partially) occludes overlay
		float dx = (overFarthest - bgNearest)/1.73;
		dx = colAcc.a * pow(dx, overlayDepth);
		overMix *= 1.0 - dx;
	}
	colAcc.rgb = mix(colAcc.rgb, overAcc.rgb, overMix);
	colAcc.a = max(colAcc.a, overAcc.a);
	return colAcc;
}