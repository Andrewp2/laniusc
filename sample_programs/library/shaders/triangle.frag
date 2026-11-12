#version 450
layout(location=0) in vec3 color;
layout(location=0) out vec4 pixel;
void main() { pixel=vec4(color,1); }
