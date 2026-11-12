#version 450
layout(location=0) out vec2 uv;
void main() {
    vec2 positions[3]=vec2[](vec2(-1,-1),vec2(3,-1),vec2(-1,3));
    vec2 p=positions[gl_VertexIndex];
    uv=(p+1.0)*0.5;
    gl_Position=vec4(p,0,1);
}
