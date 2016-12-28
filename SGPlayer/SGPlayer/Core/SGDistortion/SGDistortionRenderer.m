//
//  SGDistortionRenderer.m
//  SGTextureTest
//
//  Created by Single on 26/12/2016.
//  Copyright © 2016 single. All rights reserved.
//

#import "SGDistortionRenderer.h"
#import "SGDistortionModel.h"

#define SG_GLES_STRINGIZE(x) #x

static const char vertexShaderString[] = SG_GLES_STRINGIZE
(
 attribute vec2 aPosition;
 attribute float aVignette;
 attribute vec2 aRedTextureCoord;
 attribute vec2 aGreenTextureCoord;
 attribute vec2 aBlueTextureCoord;
 varying vec2 vRedTextureCoord;
 varying vec2 vBlueTextureCoord;
 varying vec2 vGreenTextureCoord;
 varying float vVignette;
 uniform float uTextureCoordScale;
 void main() {
     gl_Position = vec4(aPosition, 0.0, 1.0);
     vRedTextureCoord = aRedTextureCoord.xy * uTextureCoordScale;
     vGreenTextureCoord = aGreenTextureCoord.xy * uTextureCoordScale;
     vBlueTextureCoord = aBlueTextureCoord.xy * uTextureCoordScale;
     vVignette = aVignette;
 }
);

static const char fragmentShaderString[] = SG_GLES_STRINGIZE
(
 precision mediump float;
 varying vec2 vRedTextureCoord;
 varying vec2 vBlueTextureCoord;
 varying vec2 vGreenTextureCoord;
 varying float vVignette;
 uniform sampler2D uTextureSampler;
 void main() {
     gl_FragColor = vVignette * vec4(texture2D(uTextureSampler, vRedTextureCoord).r,
                                     texture2D(uTextureSampler, vGreenTextureCoord).g,
                                     texture2D(uTextureSampler, vBlueTextureCoord).b, 1.0);
 }
);

@interface SGDistortionRenderer ()

{
    GLuint frame_buffer_id;
    GLuint color_render_id;
    GLuint frame_texture_id;
    
    GLuint index_buffer_id;
    GLuint vertex_buffer_id;
    GLuint texture_buffer_id;
    
    GLuint program_id;
    GLuint vertex_shader_id;
    GLuint fragment_shader_id;
    
    GLint position_shader_location;
    GLint vignette_shader_location;
    GLint redTextureCoord_shader_location;
    GLint greenTextureCoord_shader_location;
    GLint blueTextureCoord_shader_location;
    GLint uTextureCoordScale_shader_location;
    GLint uTextureSampler_shader_location;
}

@property (nonatomic, strong) SGDistortionModel * leftEye;
@property (nonatomic, strong) SGDistortionModel * rightEye;

@property (nonatomic, assign) CGSize viewportSize;

@end

@implementation SGDistortionRenderer

- (instancetype)initWithViewportSize:(CGSize)viewportSize
{
    if (self = [super init]) {
        self.viewportSize = viewportSize;
        [self setup];
    }
    return self;
}

- (void)beforDraw
{
    glBindFramebuffer(GL_FRAMEBUFFER, frame_buffer_id);
}

- (void)afterDraw
{
    glViewport(0, 0, self.viewportSize.width, self.viewportSize.height);
    
    glDisable(GL_CULL_FACE);
    glDisable(GL_SCISSOR_TEST);
    
    glClearColor(0, 0, 0, 1);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    
    glEnable(GL_SCISSOR_TEST);
    
    glScissor(0, 0, self.viewportSize.width / 2, self.viewportSize.height);
    [self draw:self.leftEye];
    glScissor(self.viewportSize.width / 2, 0, self.viewportSize.width / 2, self.viewportSize.height);
    [self draw:self.rightEye];
    
    glDisable(GL_SCISSOR_TEST);
}

- (SGDistortionModel *)leftEye
{
    if (!_leftEye) {
        _leftEye = [SGDistortionModel modelWithModelType:SGDistortionModelTypeLeft];
    }
    return _leftEye;
}

- (SGDistortionModel *)rightEye
{
    if (!_rightEye) {
        _rightEye = [SGDistortionModel modelWithModelType:SGDistortionModelTypeRight];
    }
    return _rightEye;
}

- (void)draw:(SGDistortionModel *)eye
{
    [self useProgram];
    
    glBindBuffer(GL_ARRAY_BUFFER, eye.vertex_buffer_id);
    glVertexAttribPointer(position_shader_location, 2, GL_FLOAT, GL_FALSE, 9 * sizeof(float), (void *)(0 * sizeof(float)));
    glEnableVertexAttribArray(position_shader_location);
    glVertexAttribPointer(vignette_shader_location, 1, GL_FLOAT, GL_FALSE, 9 * sizeof(float), (void *)(2 * sizeof(float)));
    glEnableVertexAttribArray(vignette_shader_location);
    glVertexAttribPointer(blueTextureCoord_shader_location, 2, GL_FLOAT, GL_FALSE, 9 * sizeof(float), (void *)(7 * sizeof(float)));
    glEnableVertexAttribArray(blueTextureCoord_shader_location);
    
    if (YES) {
        glVertexAttribPointer(redTextureCoord_shader_location, 2, GL_FLOAT, GL_FALSE, 9 * sizeof(float), (void *)(3 * sizeof(float)));
        glEnableVertexAttribArray(redTextureCoord_shader_location);
        glVertexAttribPointer(greenTextureCoord_shader_location, 2, GL_FLOAT, GL_FALSE, 9 * sizeof(float), (void *)(5 * sizeof(float)));
        glEnableVertexAttribArray(greenTextureCoord_shader_location);
    }
    
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, frame_texture_id);
//    glBindTexture(GL_TEXTURE_2D, [self testTexture]);
    
    glUniform1i(uTextureSampler_shader_location, 0);
    float _resolutionScale = 1;
    glUniform1f(uTextureCoordScale_shader_location, _resolutionScale);
    
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, eye.index_buffer_id);
    glDrawElements(GL_TRIANGLE_STRIP, eye.index_count, GL_UNSIGNED_SHORT, 0);
}

- (void)setup
{
    [self setupFrameBuffer];
    [self setupProgramAndShader];
}

- (void)useProgram
{
    glUseProgram(program_id);
}

- (void)setupFrameBuffer
{
    glGenTextures(1, &frame_texture_id);
    glBindTexture(GL_TEXTURE_2D, frame_texture_id);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, self.viewportSize.width, self.viewportSize.height, 0, GL_RGB, GL_UNSIGNED_BYTE, nil);
    
    [self checkGLError];
    
    glGenRenderbuffers(1, &color_render_id);
    glBindRenderbuffer(GL_RENDERBUFFER, color_render_id);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT16, self.viewportSize.width, self.viewportSize.height);
    
    [self checkGLError];
    
    glGenFramebuffers(1, &frame_buffer_id);
    glBindFramebuffer(GL_FRAMEBUFFER, frame_buffer_id);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, frame_texture_id, 0);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, color_render_id);
    
    [self checkGLError];
}

- (void)setupProgramAndShader
{
    program_id = glCreateProgram();
    
    if (![self compileShader:&vertex_shader_id type:GL_VERTEX_SHADER string:vertexShaderString])
    {
        NSLog(@"load vertex shader failure");
    }
    if (![self compileShader:&fragment_shader_id type:GL_FRAGMENT_SHADER string:fragmentShaderString])
    {
        NSLog(@"load fragment shader failure");
    }
    glAttachShader(program_id, vertex_shader_id);
    glAttachShader(program_id, fragment_shader_id);
    
    GLint status;
    glLinkProgram(program_id);
    
    glGetProgramiv(program_id, GL_LINK_STATUS, &status);
    
    if (status == GL_FALSE) {
        NSLog(@"link program failure");
    }
    
    [self clearShader];
    
    position_shader_location = glGetAttribLocation(program_id, "aPosition");
    if (position_shader_location == -1)
    {
        [NSException raise:@"DistortionRenderer" format:@"Could not get attrib location for aPosition"];
    }
    
    vignette_shader_location = glGetAttribLocation(program_id, "aVignette");
    if (vignette_shader_location == -1)
    {
        [NSException raise:@"DistortionRenderer" format:@"Could not get attrib location for aVignette"];
    }

    if (YES)
    {
        redTextureCoord_shader_location = glGetAttribLocation(program_id, "aRedTextureCoord");
        if (redTextureCoord_shader_location == -1)
        {
            [NSException raise:@"DistortionRenderer" format:@"Could not get attrib location for aRedTextureCoord"];
        }
        
        greenTextureCoord_shader_location = glGetAttribLocation(program_id, "aGreenTextureCoord");
        if (greenTextureCoord_shader_location == -1)
        {
            [NSException raise:@"DistortionRenderer" format:@"Could not get attrib location for aGreenTextureCoord"];
        }
    }
    
    blueTextureCoord_shader_location = glGetAttribLocation(program_id, "aBlueTextureCoord");
    if (blueTextureCoord_shader_location == -1)
    {
        [NSException raise:@"DistortionRenderer" format:@"Could not get attrib location for aBlueTextureCoord"];
    }
    
    uTextureCoordScale_shader_location = glGetUniformLocation(program_id, "uTextureCoordScale");
    if (uTextureCoordScale_shader_location == -1)
    {
        [NSException raise:@"DistortionRenderer" format:@"Could not get attrib location for uTextureCoordScale"];
    }
    
    uTextureSampler_shader_location = glGetUniformLocation(program_id, "uTextureSampler");
    if (uTextureSampler_shader_location == -1)
    {
        [NSException raise:@"DistortionRenderer" format:@"Could not get attrib location for uTextureSampler"];
    }
    
    [self useProgram];
}

- (BOOL)compileShader:(GLuint *)shader type:(GLenum)type string:(const char *)shaderString
{
    if (!shaderString)
    {
        NSLog(@"Failed to load shader");
        return NO;
    }
    
    GLint status;
    
    * shader = glCreateShader(type);
    glShaderSource(* shader, 1, &shaderString, NULL);
    glCompileShader(* shader);
    glGetShaderiv(* shader, GL_COMPILE_STATUS, &status);
    if (status != GL_TRUE)
    {
        GLint logLength;
        glGetShaderiv(* shader, GL_INFO_LOG_LENGTH, &logLength);
        if (logLength > 0) {
            GLchar * log = (GLchar *)malloc(logLength);
            glGetShaderInfoLog(* shader, logLength, &logLength, log);
            NSLog(@"Shader compile log:\n%s", log);
            free(log);
        }
    }
    
    return status == GL_TRUE;
}

- (void)clearShader
{
    if (vertex_shader_id) {
        glDeleteShader(vertex_shader_id);
    }
    
    if (fragment_shader_id) {
        glDeleteShader(fragment_shader_id);
    }
}

- (void)checkGLError
{
    GLenum err = glGetError();
    if (err != GL_NO_ERROR)
    {
        NSLog(@"glError: 0x%04X", err);
    }
}

- (GLuint)testTexture
{
    static GLuint texture_id = 0;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        
        CGImageRef imageRef = [[UIImage alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"2_2" ofType:@"png"]].CGImage;
        size_t width =CGImageGetWidth(imageRef);
        size_t height =CGImageGetHeight(imageRef);
        
        GLvoid * _imageData = (GLubyte *)malloc(width * height * 4);
        memset(_imageData, 0, (width * height * 4));
        CGContextRef imageContext = CGBitmapContextCreate(_imageData, width, height, 8, width * 4, CGImageGetColorSpace(imageRef), kCGImageAlphaPremultipliedLast);
        CGContextTranslateCTM(imageContext, 0, height);
        CGContextScaleCTM(imageContext, 1.0, -1.0);
        CGContextDrawImage(imageContext, CGRectMake(0.0, 0.0, (CGFloat)width, (CGFloat)height), imageRef);
        CGContextRelease(imageContext);
        
        glGenTextures(1, &texture_id);
        glBindTexture(GL_TEXTURE_2D, texture_id);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, (GLsizei)width, (GLsizei)height, 0, GL_RGBA, GL_UNSIGNED_BYTE, _imageData);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        
        glActiveTexture(GL_TEXTURE0);
    });
    return texture_id;
}

@end
