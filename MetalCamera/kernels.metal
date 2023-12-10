//
//  PassthrougKernel.metal
//  MetalCamera
//
//  Created by n.dubov on 12/3/23.
//

#include <metal_stdlib>
using namespace metal;

kernel void passthroughKernel(texture2d<float, access::read> inTexture [[ texture(0) ]],
                              texture2d<float, access::write> outTexture [[ texture(1) ]],
                              uint2 gid [[ thread_position_in_grid ]]) {
    float4 originalColor = inTexture.read(gid);
    outTexture.write(originalColor, gid);
}

inline float2 calcScale(int inW, int inH, int outW, int outH) {
    return float2(float(inW) / float(outW),
                  float(inH) / float(outH));
}

inline void scaleFunc(texture2d<float, access::read> inTexture [[ texture(0) ]],
                      texture2d<float, access::write> outTexture [[ texture(1) ]],
                      uint2 gid [[ thread_position_in_grid ]],
                      float2 scale) {
    float2 size = float2(inTexture.get_width() / scale.x, inTexture.get_height() / scale.y);
    float2 tr = float2(size.x - outTexture.get_width(), size.y - outTexture.get_height());
    short2 inCoord = short2((gid.x + tr.x/2) * scale.x, (gid.y + tr.y/2) * scale.y);
    if (inCoord.x < 0 || inCoord.y < 0) {
        outTexture.write(float4(0,0,0,1), gid);
        return;
    }
    float4 originalColor = inTexture.read(ushort2(inCoord));
    outTexture.write(originalColor, gid);
}

kernel void scaleKernel(texture2d<float, access::read> inTexture [[ texture(0) ]],
                        texture2d<float, access::write> outTexture [[ texture(1) ]],
                        uint2 gid [[ thread_position_in_grid ]]) {
    float2 scale = calcScale(inTexture.get_width(), inTexture.get_height(),
                             outTexture.get_width(), outTexture.get_height());
    scaleFunc(inTexture, outTexture, gid, scale);
}

kernel void scaleToFillKernel(texture2d<float, access::read> inTexture [[ texture(0) ]],
                              texture2d<float, access::write> outTexture [[ texture(1) ]],
                              uint2 gid [[ thread_position_in_grid ]]) {
    float2 scale = calcScale(inTexture.get_width(), inTexture.get_height(),
                             outTexture.get_width(), outTexture.get_height());
    float minScale = min(scale.x, scale.y);
    scaleFunc(inTexture, outTexture, gid, float2(minScale, minScale));
}

kernel void scaleToFitKernel(texture2d<float, access::read> inTexture [[ texture(0) ]],
                              texture2d<float, access::write> outTexture [[ texture(1) ]],
                              uint2 gid [[ thread_position_in_grid ]]) {
    float2 scale = calcScale(inTexture.get_width(), inTexture.get_height(),
                             outTexture.get_width(), outTexture.get_height());
    float maxScale = max(scale.x, scale.y);
    scaleFunc(inTexture, outTexture, gid, float2(maxScale, maxScale));
}
