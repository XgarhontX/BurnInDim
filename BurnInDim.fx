#include "Reshade.fxh"
#include "ReShadeUI.fxh"
uniform float frametime <source = "frametime";>;
uniform uint framecount < source = "framecount"; >;

// ReShadeUI ///////////////////////////////////////////////////////////////////////////////////////
#ifndef ADVANCED_UserScoringLenient
    #define ADVANCED_UserScoringLenient 0
#endif

#if ADVANCED_UserScoringLenient == 0
uniform int UserScoringLenient < 
     ui_type = "combo";
	 ui_items = "Lenient\0Strict\0More Strict\0Extremely Strict\0Extremely Strict 2x\0Perfect Match (default)\0";
     ui_label = "Static Pixel Leniency";
     ui_tooltip = "How lenient should a pixel from past frame be considered as static.";
> = 5;
float getUserScoringLenient() {
	switch (UserScoringLenient) {
		case 0:
			return 0.1;
		case 1:
			return 0.02;
		case 2:
			return 0.04;
		case 3:
			return 0.001;
		case 4:
			return 0.00005;
		case 5:
			return 0;
		default:
			return 0;
	}
}
#else 
uniform float UserScoringLenient < 
     ui_type = "slider";
     ui_min = 0.0;
     ui_max = 1.0;
     ui_step = 0.005;
     ui_label = "Static Pixel Leniency (Advanced)";
     ui_tooltip = "How lenient should a pixel from past frame be considered as static. (0: perfect match, 1: will consider all as static)";
> = 0.02;
float getUserScoringLenient() {
	return UserScoringLenient;
}
#endif

uniform int UserScoringDimAttack < 
ui_type = "combo";
	 ui_items = "Slower\0Slow (default)\0Fast\0Extrememly Fast (debug)\0None (debug)\0";
     ui_label = "Dimming Speed";
     ui_tooltip = "Rate at which static pixels dims.";
> = 1;
float getUserScoringDimAttack() {
	switch (UserScoringDimAttack) {
		case 0:
			return 0.000025;
		case 1:
			return 0.00005;
		case 2:
			return 0.0001;
		case 3:
			return 0.1;
		case 4:
			return 0;
		default:
			return 0.00005;
	}
}

uniform int UserScoringDimDecay < 
ui_type = "combo";
	 ui_items = "Instant (default)\0Fast\0Noticable\0Slow\0Never (debug)\0";
     ui_label = "Dimming Decay Speed";
     ui_tooltip = "Rate at which static pixels undims.";
> = 0;
float getUserScoringDimDecay() {
	switch (UserScoringDimDecay) {
		case 0:
			return 1;
		case 1:
			return 0.8;
		case 2:
			return 0.5;
		case 3:
			return 0.1;	
		case 4:
			return 0;
		default:
			return 1;
	};
};

uniform float UserScoringDimThres < 
     ui_type = "slider";
     ui_min = 0.0;
     ui_max = 1.0;
     ui_step = 0.05;
     ui_label = "Dimming Threshold";
     ui_tooltip = "A pixel has a score starting from 1, decreasing to 0 if static. How soon should dimming begin. (1:immediately, 0:when score reaches 0)";
> = 0.7;

uniform float UserScoringLightnessThres < 
     ui_type = "slider";
     ui_min = 0.0;
     ui_max = 1.0;
     ui_step = 0.05;
     ui_label = "Luma Lightness Threshold";
     ui_tooltip = "Only pixels past this brightness level can be considered for scoring, used to isolate bright I elements.";
> = 0;

uniform float UserScoringMaxDim < 
     ui_type = "slider";
     ui_min = 0.0;
     ui_max = 1.0;
     ui_step = 0.05;
     ui_label = "Max Dimming";
     ui_tooltip = "How dark the static pixel will get.";
> = 0.5;

uniform int UserFrameSkip < 
     ui_type = "slider";
     ui_min = 0;
     ui_max = 240;
     ui_step = 1;
     ui_label = "Frame Skipping";
     ui_tooltip = "Skip this amount of frames before scoring again.";
> = 6;
float getUserFrameSkip() {
	return UserFrameSkip + 1;
}

//uniform int UserBlur < 
//     ui_type = "slider";
//     ui_min = 0;
//     ui_max = 10;
//     ui_step = 1;
//     ui_label = "Mask Blur";
//     ui_tooltip = "To expand the dimming mask to covered antialiased edges.";
//> = 0;

// Tex & Samplers //////////////////////////////////////////////////////////////////////////////////
texture texBurnScore{Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R8;};
sampler2D samplerBurnInScore{Texture = texBurnScore;};

texture texBurnScoreC{Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = R8;};
sampler2D samplerBurnInScoreC{Texture = texBurnScoreC;};

texture texPrevFrame{Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA32F;};
sampler2D samplerPrevFrame{Texture = texPrevFrame;};

// Helpers /////////////////////////////////////////////////////////////////////////////////////////
float4 rgb4ToLuma(float4 rgbaIn4) {
	return float4(rgbaIn4.r * 0.2126, rgbaIn4.g * 0.7152, rgbaIn4.b * 0.7152, rgbaIn4.a);
}
float rgb4ToLumaLightness(float4 rgbaIn4){
	const float4 rgbaIn4Luma = rgb4ToLuma(rgbaIn4);
	return max(max(rgbaIn4Luma.r, rgbaIn4Luma.g), rgbaIn4Luma.b);
}
bool isFrameskip() {
	return framecount % getUserFrameSkip() != 0;
}

// PixelShader /////////////////////////////////////////////////////////////////////////////////////
//Score
#define SCORE_DECREASE max(prevScore - (frametime * getUserScoringDimAttack() * getUserFrameSkip()), 0);
#define SCORE_INCREASE min(prevScore + (frametime * getUserScoringDimDecay() * getUserFrameSkip()), 1);
float PS_BurnInScoring(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target {
	if (isFrameskip()) discard;
	
	//get pixels
	const float4 orig4 = tex2D(ReShade::BackBuffer, texcoord);
	const float4 prev4 = tex2D(samplerPrevFrame, texcoord);
	const float prevScore = tex2D(samplerBurnInScoreC, texcoord).r;
	
	//but check HSL lightness
	if (rgb4ToLumaLightness(orig4) <= UserScoringLightnessThres) {
		return SCORE_DECREASE //too dark already, reset score
	}
	
	//calculate score (if pixel has not changed
	const float rScore = abs(prev4.r - orig4.r);
	const float gScore = abs(prev4.g - orig4.g);
	const float bScore = abs(prev4.b - orig4.b);
	const float rgbScoreAvg = (rScore + gScore + bScore) / 3;
	
	//if within leniency
	if (rgbScoreAvg <= getUserScoringLenient()) {
		return SCORE_DECREASE
	} else {
		return SCORE_INCREASE
	}
}

//Copy
float4 PS_CopyBack(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target {
	if (isFrameskip()) discard;
	return tex2D(ReShade::BackBuffer, texcoord);
}
//Copy
float4 PS_CopyBackScore(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target {
	if (isFrameskip()) discard;
	return tex2D(samplerBurnInScore, texcoord);
}

//Final
float4 PS_BurnInDim(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target {
	float4 orig4 = tex2D(ReShade::BackBuffer, texcoord);
	float currScore = tex2D(samplerBurnInScore, texcoord).r;
	
//	//final
//	if (UserBlur > 0) { //blur
//		for (int i = 1; i < UserBlur; i++) {
//			currScore += tex2D(samplerBurnInScore, texcoord + (BUFFER_RCP_WIDTH * i)).r;
//			currScore += tex2D(samplerBurnInScore, texcoord - (BUFFER_RCP_HEIGHT * i)).r;
//		}
//	} //else
	return orig4 * min(1, max(currScore * (1/UserScoringDimThres), UserScoringMaxDim));
}

// Technique ///////////////////////////////////////////////////////////////////////////////////////
technique BurnInDimming {
	pass Score { //draw to texBurnScore to update where to fade
		RenderTarget = texBurnScore;
		VertexShader = PostProcessVS; //default
		PixelShader = PS_BurnInScoring;
		//ClearRenderTargets = false;
		//BlendEnable = true;
		//BlendOp = ADD;
		//BlendOpAlpha = ADD;
	}
	pass Copy { //draw to texPrevFrame to remember prev frame
		RenderTarget = texPrevFrame;
		VertexShader = PostProcessVS; //default
		PixelShader = PS_CopyBack;
	}
		pass Copy { //to avoid sampling and drawing to samplerBurnInScore
		RenderTarget = texBurnScoreC;
		VertexShader = PostProcessVS; //default
		PixelShader = PS_CopyBackScore;
	}
	pass Final { //draw to output with dim
		VertexShader = PostProcessVS; //default
		PixelShader = PS_BurnInDim;
	}
}