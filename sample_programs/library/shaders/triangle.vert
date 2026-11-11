#version 450
layout(location=0) out vec3 color;
void main() {
    const vec2 positions[3] = vec2[3](vec2(0.0,-0.65),vec2(0.65,0.65),vec2(-0.65,0.65));
    const vec3 colors[3] = vec3[3](vec3(1,0,0),vec3(0,1,0),vec3(0,0,1));
    gl_Position=vec4(positions[gl_VertexIndex],0,1);
    color=colors[gl_VertexIndex];
}
