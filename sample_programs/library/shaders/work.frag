#version 450
layout(set=0,binding=0) uniform sampler2D pixels;
layout(location=0) out vec4 color;
void main() { color=texelFetch(pixels,ivec2(gl_FragCoord.xy)%textureSize(pixels,0),0); }
