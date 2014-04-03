//
//  ViewController.m
//  Test
//
//  Created by Neil Wallace on 04/02/2014.
//  Copyright (c) 2014 Neil Wallace. All rights reserved.
//

#import "ViewController.h"
#include <vector>
#include <numeric>

#import "AppDelegate.h"

const int NUM_LAYERS = 10;

#define BUFFER_OFFSET(i) ((char *)NULL + (i))

// Uniform index.
enum
{
    UNIFORM_MODELVIEWPROJECTION_MATRIX,
    UNIFORM_NORMAL_MATRIX,
    UNIFORM_TEX_0_SAMPLER,
    NUM_UNIFORMS
};
GLint uniforms[NUM_UNIFORMS];

#define PVR_TEXTURE_FLAG_TYPE_MASK	0xff
static char gPVRTexIdentifier[5] = "PVR!";

enum
{
	kPVRTextureFlagTypePVRTC_2 = 24,
	kPVRTextureFlagTypePVRTC_4
};

typedef struct _PVRTexHeader
{
	uint32_t headerLength;
	uint32_t height;
	uint32_t width;
	uint32_t numMipmaps;
	uint32_t flags;
	uint32_t dataLength;
	uint32_t bpp;
	uint32_t bitmaskRed;
	uint32_t bitmaskGreen;
	uint32_t bitmaskBlue;
	uint32_t bitmaskAlpha;
	uint32_t pvrTag;
	uint32_t numSurfs;
} PVRTexHeader;

struct Vertex
{
    Vertex(float x, float y, float z, float uv_x, float uv_y, float r, float g, float b, float a)
    {
        tc[0] = uv_x;
        tc[1] = uv_y;
        pos[0] = x;
        pos[1] = y;
        pos[2] = z;
        colour[0] = r;
        colour[1] = g;
        colour[2] = b;
        colour[3] = a;
    }

    GLfloat pos[3];
    GLfloat tc[2];
    GLfloat colour[4];
};

std::vector<Vertex> verts;

@interface ViewController () {
    GLuint _program;
    
    GLKMatrix4 _modelViewProjectionMatrix;
    GLKMatrix3 _normalMatrix;
    float _rotation;
    
    GLuint _vertexArray;
    GLuint _vertexBuffer;
    
    GLKTextureInfo* glk_texture_info;
    
    GLuint _Width;
    GLuint _Height;
    NSMutableArray *_ImageData;
    GLuint _ID;
    GLenum _InternalFormat;
    bool _HasAlpha;
}
@property (strong, nonatomic) EAGLContext *context;
@property (strong, nonatomic) GLKBaseEffect *effect;

- (void)setupGL;
- (void)tearDownGL;

- (BOOL)loadShaders;
- (BOOL)compileShader:(GLuint *)shader type:(GLenum)type file:(NSString *)file;
- (BOOL)linkProgram:(GLuint)prog;
- (BOOL)validateProgram:(GLuint)prog;
@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];

    if (!self.context) {
        NSLog(@"Failed to create ES context");
    }
    
    GLKView *view = (GLKView *)self.view;
    view.context = self.context;
    view.drawableDepthFormat = GLKViewDrawableDepthFormat24;
    
    [self setupGL];
//    [self loadTexture];
}

-(BOOL) createGLTextureFromCompressedData
{
    int width = _Width;
    int height = _Height;
    NSData *data;
    GLenum err;
    
    if ([_ImageData count] > 0)
    {
        glGenTextures(1, &_ID);
        glBindTexture(GL_TEXTURE_2D, _ID);
    }
    
    if ([_ImageData count] > 1)
    {
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_NEAREST);
    }
    else
    {
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    }
    
    for (int i=0; i < [_ImageData count]; i++)
    {
        data = [_ImageData objectAtIndex:i];
        glCompressedTexImage2D(GL_TEXTURE_2D, i, _InternalFormat, width, height, 0, [data length], [data bytes]);
        
        err = glGetError();
        if (err != GL_NO_ERROR)
        {
            NSLog(@"Error uploading compressed texture level: %d. glError: 0x%04X", i, err);
            return FALSE;
        }
        
        width = MAX(width >> 1, 1);
        height = MAX(height >> 1, 1);
    }
    
    return TRUE;
}

-(BOOL) unpackPVRData:(NSData *)data
{
    BOOL success = FALSE;
	PVRTexHeader *header = NULL;
	uint32_t flags, pvrTag;
	uint32_t dataLength = 0, dataOffset = 0, dataSize = 0;
	uint32_t blockSize = 0, widthBlocks = 0, heightBlocks = 0;
	uint32_t width = 0, height = 0, bpp = 4;
	uint8_t *bytes = NULL;
	uint32_t formatFlags;
	
	header = (PVRTexHeader *)[data bytes];
	
	pvrTag = CFSwapInt32LittleToHost(header->pvrTag);
    
	if (gPVRTexIdentifier[0] != ((pvrTag >>  0) & 0xff) ||
		gPVRTexIdentifier[1] != ((pvrTag >>  8) & 0xff) ||
		gPVRTexIdentifier[2] != ((pvrTag >> 16) & 0xff) ||
		gPVRTexIdentifier[3] != ((pvrTag >> 24) & 0xff))
	{
		return FALSE;
	}
	
	flags = CFSwapInt32LittleToHost(header->flags);
	formatFlags = flags & PVR_TEXTURE_FLAG_TYPE_MASK;
	
	if (formatFlags == kPVRTextureFlagTypePVRTC_4 || formatFlags == kPVRTextureFlagTypePVRTC_2)
	{
		[_ImageData removeAllObjects];
		
		if (formatFlags == kPVRTextureFlagTypePVRTC_4)
			_InternalFormat = GL_COMPRESSED_RGBA_PVRTC_4BPPV1_IMG;
		else if (formatFlags == kPVRTextureFlagTypePVRTC_2)
			_InternalFormat = GL_COMPRESSED_RGBA_PVRTC_2BPPV1_IMG;
        
		_Width = width = CFSwapInt32LittleToHost(header->width);
		_Height = height = CFSwapInt32LittleToHost(header->height);
		
		if (CFSwapInt32LittleToHost(header->bitmaskAlpha))
			_HasAlpha = TRUE;
		else
			_HasAlpha = FALSE;
		
		dataLength = CFSwapInt32LittleToHost(header->dataLength);
		
		bytes = ((uint8_t *)[data bytes]) + sizeof(PVRTexHeader);
		
		// Calculate the data size for each texture level and respect the minimum number of blocks
		while (dataOffset < dataLength)
		{
			if (formatFlags == kPVRTextureFlagTypePVRTC_4)
			{
				blockSize = 4 * 4; // Pixel by pixel block size for 4bpp
				widthBlocks = width / 4;
				heightBlocks = height / 4;
				bpp = 4;
			}
			else
			{
				blockSize = 8 * 4; // Pixel by pixel block size for 2bpp
				widthBlocks = width / 8;
				heightBlocks = height / 4;
				bpp = 2;
			}
			
			// Clamp to minimum number of blocks
			if (widthBlocks < 2)
				widthBlocks = 2;
			if (heightBlocks < 2)
				heightBlocks = 2;
            
			dataSize = widthBlocks * heightBlocks * ((blockSize  * bpp) / 8);
			
			[_ImageData addObject:[NSData dataWithBytes:bytes+dataOffset length:dataSize]];
			
			dataOffset += dataSize;
			
			width = MAX(width >> 1, 1);
			height = MAX(height >> 1, 1);
		}
        
		success = TRUE;
	}
	
	return success;
}

//--------------------------------------------------------------------------------------------------
-(void) loadTexture
//(const CHashString& name, const CHashString& filename, int wrap_mode)
{
    
    NSLog(@"--------------------------------------------------------------------------------------------------");
    NSLog(@"loadTexture");
    NSLog(@"--------------------------------------------------------------------------------------------------");
	NSError *error;
    
    NSString* filename = @"atlas_characters_0";
	
	NSString *textureFile = [[NSBundle mainBundle]
                             pathForResource:filename ofType:@"pvr"];
	
	if(textureFile == nil)
	{
		textureFile = [[NSBundle mainBundle]
					   pathForResource:filename ofType:@"png"];
	}
	
	if(textureFile)
	{
        NSData *data = [NSData dataWithContentsOfFile:textureFile];
        
        
        _ImageData = [[NSMutableArray alloc] initWithCapacity:10];
        
        [self unpackPVRData:data];
        [self createGLTextureFromCompressedData];
        
        _ImageData = nil;
        

//		NSDictionary* options = @{ GLKTextureLoaderGenerateMipmaps : @NO };
//        
//        CGDataProviderRef imgDataProvider = CGDataProviderCreateWithCFData((__bridge CFDataRef)[NSData dataWithContentsOfFile:textureFile]);
//        
//        CGImageRef image = CGImageCreateWithPNGDataProvider(imgDataProvider, NULL, true, kCGRenderingIntentDefault);
//        
//        glk_texture_info = [GLKTextureLoader textureWithCGImage:image options:nil error:&error];
        
//		glk_texture_info = [GLKTextureLoader textureWithContentsOfFile:textureFile
//                                                                               options:nil
//                                                                                 error:&error];
		
		if (error)
        {
            NSLog(@"Error loading texture: %@", error);
        }
        else
        {
//            NSLog(@"Loaded %@ (%dx%d)", textureFile, [glk_texture_info width], [glk_texture_info height]);
//            glBindTexture([glk_texture_info target], [glk_texture_info name]);
        }
	}
	else
	{
		NSLog(@"File not found %@", filename);
	}
}

- (void)dealloc
{
    [self tearDownGL];
    
    if ([EAGLContext currentContext] == self.context) {
        [EAGLContext setCurrentContext:nil];
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];

    if ([self isViewLoaded] && ([[self view] window] == nil)) {
        self.view = nil;
        
        [self tearDownGL];
        
        if ([EAGLContext currentContext] == self.context) {
            [EAGLContext setCurrentContext:nil];
        }
        self.context = nil;
    }

    // Dispose of any resources that can be recreated.
}

void AddQuad(GLKVector3 pos, float size, GLKVector4 colour)
{
    verts.push_back(Vertex(pos.v[0]-size,  pos.v[1]-size,     pos.v[2],          0.0f,   1.0f, colour.v[0], colour.v[1], colour.v[2], colour.v[3]));
    verts.push_back(Vertex(pos.v[0]+size,  pos.v[1]-size,     pos.v[2],          1.0f,   1.0f, colour.v[0], colour.v[1], colour.v[2], colour.v[3]));
    verts.push_back(Vertex(pos.v[0]-size,  pos.v[1]+size,     pos.v[2],          0.0f,   0.0f, colour.v[0], colour.v[1], colour.v[2], colour.v[3]));
    verts.push_back(Vertex(pos.v[0]-size,  pos.v[1]+size,     pos.v[2],          0.0f,   0.0f, colour.v[0], colour.v[1], colour.v[2], colour.v[3]));
    verts.push_back(Vertex(pos.v[0]+size,  pos.v[1]-size,     pos.v[2],          1.0f,   1.0f, colour.v[0], colour.v[1], colour.v[2], colour.v[3]));
    verts.push_back(Vertex(pos.v[0]+size,  pos.v[1]+size,     pos.v[2],          1.0f,   0.0f, colour.v[0], colour.v[1], colour.v[2], colour.v[3]));
}

GLKVector4 ColourFromHSV(float h, float s, float v, float alpha = 1)
{
    GLKVector4 ret = { 0, 0, 0, alpha};
    
    h *= 360.0f;
    int i;
    float f, p, q, t;
    if( s == 0 ) {
        // achromatic (grey)
        ret.v[0] = ret.v[1] = ret.v[2] = v;
        return ret;
    }
    h /= 60;			// sector 0 to 5
    i = floor( h );
    f = h - i;			// factorial part of h
    p = v * ( 1 - s );
    q = v * ( 1 - s * f );
    t = v * ( 1 - s * ( 1 - f ) );
    switch( i ) {
        case 0:
            ret.v[0] = v;
            ret.v[1] = t;
            ret.v[2] = p;
            break;
        case 1:
            ret.v[0] = q;
            ret.v[1] = v;
            ret.v[2] = p;
            break;
        case 2:
            ret.v[0] = p;
            ret.v[1] = v;
            ret.v[2] = t;
            break;
        case 3:
            ret.v[0] = p;
            ret.v[1] = q;
            ret.v[2] = v;
            break;
        case 4:
            ret.v[0] = t;
            ret.v[1] = p;
            ret.v[2] = v;
            break;
        default:		// case 5:
            ret.v[0] = v;
            ret.v[1] = p;
            ret.v[2] = q;
            break;
    }
    
    ret.v[3] = alpha;
    return ret;
}

- (void)setupGL
{
    for(int layer=0; layer<NUM_LAYERS; ++layer)
    {
        int subdiv = powf(layer+1, 2.0f);
        float size = (1.0f / (subdiv));
        
        float layer_f = layer/(float)(NUM_LAYERS-1);
        
        GLKVector4 colour = ColourFromHSV(layer_f, 1.0f, 1.0f, 0.2f);
        
        for(int x=0; x<subdiv; ++x)
        {
            float xf = x/(float)(subdiv-1) - 0.5f;
            for(int y=0; y<subdiv; ++y)
            {
                float yf = y/(float)(subdiv-1) - 0.5f;
                AddQuad(GLKVector3Make(xf,yf,0), size, colour);
            }
        }
    }
    
    [EAGLContext setCurrentContext:self.context];
    
    [self loadShaders];
    
    glGenVertexArraysOES(1, &_vertexArray);
    glBindVertexArrayOES(_vertexArray);
    
    glGenBuffers(1, &_vertexBuffer);
    glBindBuffer(GL_ARRAY_BUFFER, _vertexBuffer);
    glBufferData(GL_ARRAY_BUFFER, verts.size() * sizeof(Vertex), verts.data(), GL_STATIC_DRAW);
    GLuint stride = sizeof(Vertex);
    
    glEnableVertexAttribArray(GLKVertexAttribPosition);
    glVertexAttribPointer(GLKVertexAttribPosition, 3, GL_FLOAT, GL_FALSE, stride, BUFFER_OFFSET(0));
    glEnableVertexAttribArray(GLKVertexAttribTexCoord0);
    glVertexAttribPointer(GLKVertexAttribTexCoord0, 2, GL_FLOAT, GL_FALSE, stride, BUFFER_OFFSET(12));
    glEnableVertexAttribArray(GLKVertexAttribColor);
    glVertexAttribPointer(GLKVertexAttribColor, 4, GL_FLOAT, GL_FALSE, stride, BUFFER_OFFSET(20));
    
    glBindVertexArrayOES(0);
}

- (void)tearDownGL
{
    [EAGLContext setCurrentContext:self.context];
    
    glDeleteBuffers(1, &_vertexBuffer);
    glDeleteVertexArraysOES(1, &_vertexArray);
    
//    self.effect = nil;
    
    if (_program) {
        glDeleteProgram(_program);
        _program = 0;
    }
}

#pragma mark - GLKView and GLKViewController delegate methods

- (void)update
{
    float aspect = fabsf(self.view.bounds.size.width / self.view.bounds.size.height);
    GLKMatrix4 projectionMatrix = GLKMatrix4MakePerspective(GLKMathDegreesToRadians(65.0f), aspect, 0.1f, 100.0f);
    
    static float scale = 8.0f;
    GLKMatrix4 modelViewMatrix = GLKMatrix4MakeScale(scale, scale, scale);
    modelViewMatrix = GLKMatrix4Multiply(GLKMatrix4MakeTranslation(0.0f, 0.0f, -4.0f), modelViewMatrix);
    
    _normalMatrix = GLKMatrix3InvertAndTranspose(GLKMatrix4GetMatrix3(modelViewMatrix), NULL);
    
    _modelViewProjectionMatrix = GLKMatrix4Multiply(projectionMatrix, modelViewMatrix);
    
#if ANDROID
    _rotation += 0.02;
#else
    _rotation += self.timeSinceLastUpdate * 0.2f;
#endif
}

- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect
{
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    
    glBindVertexArrayOES(_vertexArray);
    
//    // Render the object with GLKit
//    [self.effect prepareToDraw];
//    
//    glDrawArrays(GL_TRIANGLES, 0, 36);
    
    // Render the object again with ES2
    glUseProgram(_program);
    
    glUniformMatrix4fv(uniforms[UNIFORM_MODELVIEWPROJECTION_MATRIX], 1, 0, _modelViewProjectionMatrix.m);
    glUniformMatrix3fv(uniforms[UNIFORM_NORMAL_MATRIX], 1, 0, _normalMatrix.m);
    
    
    glUniform1i(uniforms[UNIFORM_TEX_0_SAMPLER], 0);
    
    glDrawArrays(GL_TRIANGLES, 0, verts.size());
    
    static double prev_time = CACurrentMediaTime();
    double time = CACurrentMediaTime();
    double frame_time = time - prev_time;
    prev_time = time;
    
    static std::vector<double> frame_times;
    frame_times.push_back(frame_time);
    
    if(frame_times.size() > 30)
    {
        double avg = 0.0f;
        for(auto f : frame_times)
        {
            avg += f;
        }
        avg /= frame_times.size();
        
        double frame_rate = 1.0f / avg;
        NSLog(@"Frame Rate = %1.3f", frame_rate);
        
        frame_times.clear();
    }
}

#pragma mark -  OpenGL ES 2 shader compilation

- (BOOL)loadShaders
{
    GLuint vertShader, fragShader;
    NSString *vertShaderPathname, *fragShaderPathname;
    
    // Create shader program.
    _program = glCreateProgram();
    
    // Create and compile vertex shader.
    vertShaderPathname = [[NSBundle mainBundle] pathForResource:@"Shader" ofType:@"vsh"];
    if (![self compileShader:&vertShader type:GL_VERTEX_SHADER file:vertShaderPathname]) {
        NSLog(@"Failed to compile vertex shader");
        return NO;
    }
    
    // Create and compile fragment shader.
    fragShaderPathname = [[NSBundle mainBundle] pathForResource:@"Shader" ofType:@"fsh"];
    if (![self compileShader:&fragShader type:GL_FRAGMENT_SHADER file:fragShaderPathname]) {
        NSLog(@"Failed to compile fragment shader");
        return NO;
    }
    
    // Attach vertex shader to program.
    glAttachShader(_program, vertShader);
    
    // Attach fragment shader to program.
    glAttachShader(_program, fragShader);
    
    // Bind attribute locations.
    // This needs to be done prior to linking.
    glBindAttribLocation(_program, GLKVertexAttribPosition, "position");
    glBindAttribLocation(_program, GLKVertexAttribNormal, "normal");
    glBindAttribLocation(_program, GLKVertexAttribColor, "colour");
    glBindAttribLocation(_program, GLKVertexAttribTexCoord0, "texCoord");
    
    // Link program.
    if (![self linkProgram:_program]) {
        NSLog(@"Failed to link program: %d", _program);
        
        if (vertShader) {
            glDeleteShader(vertShader);
            vertShader = 0;
        }
        if (fragShader) {
            glDeleteShader(fragShader);
            fragShader = 0;
        }
        if (_program) {
            glDeleteProgram(_program);
            _program = 0;
        }
        
        return NO;
    }
    
    // Get uniform locations.
    uniforms[UNIFORM_MODELVIEWPROJECTION_MATRIX] = glGetUniformLocation(_program, "modelViewProjectionMatrix");
    uniforms[UNIFORM_NORMAL_MATRIX] = glGetUniformLocation(_program, "normalMatrix");
    uniforms[UNIFORM_TEX_0_SAMPLER] = glGetUniformLocation(_program, "u_Tex0Sampler");
    
    // Release vertex and fragment shaders.
    if (vertShader) {
        glDetachShader(_program, vertShader);
        glDeleteShader(vertShader);
    }
    if (fragShader) {
        glDetachShader(_program, fragShader);
        glDeleteShader(fragShader);
    }
    
    return YES;
}

- (BOOL)compileShader:(GLuint *)shader type:(GLenum)type file:(NSString *)file
{
    GLint status;
    const GLchar *source;
    
    source = (GLchar *)[[NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:nil] UTF8String];
    if (!source) {
        NSLog(@"Failed to load vertex shader");
        return NO;
    }
    
    *shader = glCreateShader(type);
    glShaderSource(*shader, 1, &source, NULL);
    glCompileShader(*shader);
    
#if defined(DEBUG)
    GLint logLength;
    glGetShaderiv(*shader, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetShaderInfoLog(*shader, logLength, &logLength, log);
        NSLog(@"Shader compile log:\n%s", log);
        free(log);
    }
#endif
    
    glGetShaderiv(*shader, GL_COMPILE_STATUS, &status);
    if (status == 0) {
        glDeleteShader(*shader);
        return NO;
    }
    
    return YES;
}

- (BOOL)linkProgram:(GLuint)prog
{
    GLint status;
    glLinkProgram(prog);
    
#if defined(DEBUG)
    GLint logLength;
    glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetProgramInfoLog(prog, logLength, &logLength, log);
        NSLog(@"Program link log:\n%s", log);
        free(log);
    }
#endif
    
    glGetProgramiv(prog, GL_LINK_STATUS, &status);
    if (status == 0) {
        return NO;
    }
    
    return YES;
}

- (BOOL)validateProgram:(GLuint)prog
{
    GLint logLength, status;
    
    glValidateProgram(prog);
    glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetProgramInfoLog(prog, logLength, &logLength, log);
        NSLog(@"Program validate log:\n%s", log);
        free(log);
    }
    
    glGetProgramiv(prog, GL_VALIDATE_STATUS, &status);
    if (status == 0) {
        return NO;
    }
    
    return YES;
}

@end
