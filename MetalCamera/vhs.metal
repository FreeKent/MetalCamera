//
//  vhs.metal
//  MetalCamera
//
//  Created by n.dubov on 12/8/23.
//

#include <metal_stdlib>
using namespace metal;

constant float range = 0.05;
constant float noiseQuality = 250.0;
constant float noiseIntensity = 0.0088;
constant float offsetIntensity = 0.02;
constant float colorOffsetIntensity = 1.3;

float rand(float2 co)
{
    return fract(sin(dot(co.xy, float2(12.9898,78.233))) * 43758.5453);
}

float verticalBar(float pos, float uvY, float offset)
{
    float edge0 = (pos - range);
    float edge1 = (pos + range);

    float x = smoothstep(edge0, pos, uvY) * offset;
    x -= smoothstep(pos, edge1, uvY) * offset;
    return x;
}

kernel void vhsKernel(texture2d<float, access::read> inTexture [[ texture(0) ]],
                      texture2d<float, access::write> outTexture [[ texture(1) ]],
                      constant float *time [[ buffer(0) ]],
                      uint2 gid [[ thread_position_in_grid ]]) {
    float2 uv = float2(float(gid.x) / float(outTexture.get_width()),
                       float(gid.y) / float(outTexture.get_height()));
    float iTime = *time;
    for (float i = 0.0; i < 0.71; i += 0.1313)
    {
        float d = iTime * i - float(int(iTime * i / 1.7)) * 1.7;
        float o = sin(1.0 - tan(iTime * 0.24 * i));
        o *= offsetIntensity;
        uv.x += verticalBar(d, uv.y, o);
    }
    
    float uvY = uv.y;
    uvY *= noiseQuality;
    uvY = float(int(uvY)) * (1.0 / noiseQuality);
    float noise = rand(float2(iTime * 0.00001, uvY));
    uv.x += noise * noiseIntensity;

    float2 offsetR = float2(0.006 * sin(iTime), 0.0) * colorOffsetIntensity;
    float2 offsetG = float2(0.0073 * (cos(iTime * 0.97)), 0.0) * colorOffsetIntensity;
    
    float r = inTexture.read(ushort2((uv + offsetR) * float2(inTexture.get_width(), inTexture.get_height()))).x;
    float g = inTexture.read(ushort2((uv + offsetG) * float2(inTexture.get_width(), inTexture.get_height()))).y;
    float b = inTexture.read(ushort2(uv * float2(inTexture.get_width(), inTexture.get_height()))).z;

    float4 tex = float4(r, g, b, 1.0);
    outTexture.write(tex, gid);
}


