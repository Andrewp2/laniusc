#version 450
layout(set=0,binding=0) uniform sampler2D pixels;
layout(set=0,binding=1,std430) readonly buffer Control { uint value; } control_data;
layout(location=0) out vec4 color;
void main() {
    color=texelFetch(pixels,ivec2(gl_FragCoord.xy)%textureSize(pixels,0),0);
    if(control_data.value==1) color.r=0.0;
}
