//
//  Shader.fsh
//  Test
//
//  Created by Neil Wallace on 04/02/2014.
//  Copyright (c) 2014 Neil Wallace. All rights reserved.
//

varying lowp vec4 vColour;
varying lowp vec2 vTexCoord;

uniform sampler2D u_Tex0Sampler;


void main()
{
//    mediump vec4 colour = texture2D(u_Tex0Sampler, vTexCoord) * vColour;
    
//    colour = vec4(vTexCoord.x, vTexCoord.y, 0.0, 1.0);
    gl_FragColor = vColour;
}
