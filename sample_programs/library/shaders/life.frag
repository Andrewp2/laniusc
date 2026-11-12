#version 450
layout(set=0,binding=0) uniform sampler2D cells;
layout(location=0) in vec2 uv;
layout(location=0) out vec4 color;
void main() {
    ivec2 size=textureSize(cells,0);
    vec2 position=uv*vec2(size);
    ivec2 cell=clamp(ivec2(position),ivec2(0),size-1);
    bool alive=texelFetch(cells,cell,0).r>0.5;
    vec3 background=vec3(0.025,0.042,0.065);
    vec3 foreground=mix(vec3(0.26,0.94,0.67),vec3(0.40,0.73,1.0),uv.y);
    vec2 pixel=fwidth(position);
    float fill=1.0;
    if(max(pixel.x,pixel.y)<0.34) {
        vec2 gap=step(pixel*0.65,fract(position));
        fill=gap.x*gap.y;
    }
    color=vec4(mix(background,foreground,alive ? fill : 0.0),1.0);
}
