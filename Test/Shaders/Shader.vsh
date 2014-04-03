//
//  Shader.vsh
//  Test
//
//  Created by Neil Wallace on 04/02/2014.
//  Copyright (c) 2014 Neil Wallace. All rights reserved.
//

attribute vec4 position;
attribute vec4 colour;
attribute vec2 texCoord;

varying lowp vec4 vColour;
varying lowp vec2 vTexCoord;

uniform mat4 modelViewProjectionMatrix;
uniform mat3 normalMatrix;

void main()
{
    vColour = colour;
    vTexCoord = texCoord;
    
    gl_Position = modelViewProjectionMatrix * position;
}
