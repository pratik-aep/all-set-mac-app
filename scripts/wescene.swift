// Renders a Wallpaper Engine scene, normalised by scripts/wallpaper_library.py,
// with the scene's own shaders: as a still, or as a seamless loop.
//
//     wescene scene.json out.mp4 [--width 2560] [--fps 30]
//     wescene scene.json out.jpg --still [--width 3840]
//
// Each layer runs its effects in order, pass by pass, exactly as the scene
// declares them (render targets, bindings, combos, uniforms). The shaders are
// Wallpaper Engine's own GLSL, compiled in an offscreen OpenGL context with a
// small prelude for the engine's macros. Layers are then drawn with their full
// transform hierarchy, alignment, alpha, colour and brightness.
//
// Time is the only input: frame n is t = n / fps, so every run is identical.
// The last `crossfade` seconds of the loop are blended into its start, which is
// a no-op for everything whose cycles fit the loop exactly.
//
// Prints one JSON line: what was rendered and anything that couldn't be.

import AVFoundation
import CoreVideo
import Foundation
import ImageIO
import OpenGL.GL
import UniformTypeIdentifiers

// MARK: - The normalised scene

struct Key: Decodable { let t, v, inX, inY, outX, outY: Double }

struct Track: Decodable {
    let value: [Double]
    let keys: [[Key]]?
    let length: Double?
    let mode: String?
    let timeScale: Double?

    func at(_ time: Double) -> [Double] {
        guard let keys, !keys.isEmpty else { return value }
        var t = time * (timeScale ?? 1)
        if let length, length > 0 {
            switch mode {
            case "mirror":
                let p = t.truncatingRemainder(dividingBy: 2 * length)
                t = p <= length ? p : 2 * length - p
            case "single":
                t = min(t, length)
            default:
                t = t.truncatingRemainder(dividingBy: length)
            }
        }
        return value.indices.map { c in c < keys.count && !keys[c].isEmpty ? Track.channel(keys[c], t) : value[c] }
    }

    /// A cubic bezier through the keys and their handles, solved for time.
    static func channel(_ keys: [Key], _ t: Double) -> Double {
        if t <= keys[0].t { return keys[0].v }
        if t >= keys[keys.count - 1].t { return keys[keys.count - 1].v }
        var i = 0
        while i + 1 < keys.count, keys[i + 1].t <= t { i += 1 }
        let a = keys[i], b = keys[i + 1]
        guard b.t - a.t > 1e-9 else { return b.v }
        let x0 = a.t, x1 = min(max(a.t + a.outX, a.t), b.t), x2 = max(min(b.t + b.inX, b.t), a.t), x3 = b.t
        let y0 = a.v, y1 = a.v + a.outY, y2 = b.v + b.inY, y3 = b.v
        func curve(_ p0: Double, _ p1: Double, _ p2: Double, _ p3: Double, _ u: Double) -> Double {
            let m = 1 - u
            return m * m * m * p0 + 3 * m * m * u * p1 + 3 * m * u * u * p2 + u * u * u * p3
        }
        var low = 0.0, high = 1.0
        for _ in 0..<40 {
            let mid = (low + high) / 2
            if curve(x0, x1, x2, x3, mid) < t { low = mid } else { high = mid }
        }
        return curve(y0, y1, y2, y3, (low + high) / 2)
    }
}

struct Node: Decodable { let origin: Track; let scale: Track; let angles: Track }

struct Frame: Decodable { let file: String; let duration: Double }

struct TextureRef: Decodable {
    let file: String?
    let frames: [Frame]?
    let builtin: String?
    let layer: Int?
    let scene: Bool?
    let fbo: String?
    let previous: Bool?
    let clamp: Bool?
    let nearest: Bool?
    let timeScale: Double?
}

struct Pass: Decodable {
    let vert: String
    let frag: String
    let combos: [String: Int]
    let uniforms: [String: Track]
    let textures: [String: TextureRef?]
    let target: String?
    let blending: String?
}

struct Effect: Decodable {
    struct Buffer: Decodable { let name: String; let scale: Double }
    let kind: String
    let fbos: [Buffer]
    let passes: [Pass]
    let timed: Bool
    let timeScale: Double?
}

struct Layer: Decodable {
    let id: Int?
    let name: String
    let alignment: String
    let chain: [Node]
    let alpha: Track
    let color: Track
    let brightness: Track
    let colorBlendMode: Int
    let blending: String
    let effects: [Effect]
    let size: [Double]
    let solid: Bool?
    let background: Bool?
    let texture: TextureRef?
    let hidden: Bool?
}

struct Scene: Decodable {
    let canvas: [Double]
    let clear: [Double]
    let layers: [Layer]
    let seconds: Double?
    let crossfade: Double?
    let start: Double?
}

// MARK: - Arguments

var arguments = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}
let still = arguments.contains("--still")
let fps = Int(option("--fps") ?? "30") ?? 30
let requestedWidth = Int(option("--width") ?? (still ? "3840" : "2560")) ?? 2560
guard arguments.count >= 2 else {
    print(#"{"error": "usage: wescene scene.json out.(mp4|jpg) [--still] [--width N] [--fps N]"}"#)
    exit(2)
}
let sceneURL = URL(fileURLWithPath: arguments[0])
let outputURL = URL(fileURLWithPath: arguments[1])
var notes = Set<String>()

func fail(_ message: String) -> Never {
    print(#"{"error": "\#(message.replacingOccurrences(of: "\"", with: "'"))"}"#)
    exit(1)
}

guard let sceneData = FileManager.default.contents(atPath: sceneURL.path),
      let scene = try? JSONDecoder().decode(Scene.self, from: sceneData) else { fail("unreadable scene") }
let canvasWidth = max(scene.canvas[0], 2), canvasHeight = max(scene.canvas[1], 2)
// The long side at most the requested size, never larger than the scene itself.
let outputScale = min(1, Double(requestedWidth) / max(canvasWidth, canvasHeight))
let outputWidth = max(2, Int((canvasWidth * outputScale / 2).rounded()) * 2)
let outputHeight = max(2, Int((canvasHeight * outputScale / 2).rounded()) * 2)

// MARK: - GL context

var pixelAttributes: [CGLPixelFormatAttribute] = [
    kCGLPFAAccelerated, kCGLPFAOpenGLProfile, CGLPixelFormatAttribute(kCGLOGLPVersion_Legacy.rawValue),
    kCGLPFAColorSize, CGLPixelFormatAttribute(24), kCGLPFAAlphaSize, CGLPixelFormatAttribute(8), CGLPixelFormatAttribute(0),
]
var pixelFormat: CGLPixelFormatObj?
var formatCount: GLint = 0
CGLChoosePixelFormat(&pixelAttributes, &pixelFormat, &formatCount)
var context: CGLContextObj?
guard let pixelFormat, CGLCreateContext(pixelFormat, nil, &context) == kCGLNoError, let context else { fail("no OpenGL context") }
CGLSetCurrentContext(context)
glDisable(GLenum(GL_DEPTH_TEST))
glDisable(GLenum(GL_CULL_FACE))
glPixelStorei(GLenum(GL_UNPACK_ALIGNMENT), 1)
glPixelStorei(GLenum(GL_PACK_ALIGNMENT), 1)

// MARK: - Textures and targets

final class Texture {
    let id: GLuint
    let width: Int
    let height: Int
    init(width: Int, height: Int, pixels: UnsafeRawPointer?, clamp: Bool = true, nearest: Bool = false) {
        var name: GLuint = 0
        glGenTextures(1, &name)
        id = name
        self.width = width
        self.height = height
        glBindTexture(GLenum(GL_TEXTURE_2D), id)
        glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RGBA8, GLsizei(width), GLsizei(height), 0,
                     GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), pixels)
        setSampling(clamp: clamp, nearest: nearest)
    }

    func setSampling(clamp: Bool, nearest: Bool) {
        glBindTexture(GLenum(GL_TEXTURE_2D), id)
        let wrap = clamp ? GL_CLAMP_TO_EDGE : GL_REPEAT
        let filter = nearest ? GL_NEAREST : GL_LINEAR
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), wrap)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), wrap)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), filter)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), filter)
    }
}

/// A texture that can be drawn into. Its rows are stored top-first, like a
/// loaded picture, so every texture samples the same way round.
final class Target {
    let texture: Texture
    let framebuffer: GLuint
    var width: Int { texture.width }
    var height: Int { texture.height }
    init(width: Int, height: Int) {
        texture = Texture(width: max(1, width), height: max(1, height), pixels: nil)
        var name: GLuint = 0
        glGenFramebuffersEXT(1, &name)
        framebuffer = name
        glBindFramebufferEXT(GLenum(GL_FRAMEBUFFER_EXT), framebuffer)
        glFramebufferTexture2DEXT(GLenum(GL_FRAMEBUFFER_EXT), GLenum(GL_COLOR_ATTACHMENT0_EXT), GLenum(GL_TEXTURE_2D), texture.id, 0)
    }

    func bind(clear: [Float]? = [0, 0, 0, 0]) {
        glBindFramebufferEXT(GLenum(GL_FRAMEBUFFER_EXT), framebuffer)
        glViewport(0, 0, GLsizei(width), GLsizei(height))
        if let clear {
            glClearColor(clear[0], clear[1], clear[2], clear[3])
            glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
        }
    }
}

var loaded: [String: Texture] = [:]

/// A picture file as a straight-alpha texture (Wallpaper Engine's shaders
/// expect straight alpha).
func picture(_ path: String, clamp: Bool, nearest: Bool) -> Texture? {
    let key = "\(path)|\(clamp)|\(nearest)"
    if let texture = loaded[key] { return texture }
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
    let width = image.width, height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let bitmap = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                 space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    bitmap.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    for i in stride(from: 0, to: pixels.count, by: 4) {
        let alpha = Int(pixels[i + 3])
        if alpha > 0, alpha < 255 {
            for c in 0..<3 { pixels[i + c] = UInt8(min(255, Int(pixels[i + c]) * 255 / alpha)) }
        }
    }
    let texture = Texture(width: width, height: height, pixels: pixels, clamp: clamp, nearest: nearest)
    loaded[key] = texture
    return texture
}

func solidTexture(_ rgba: [UInt8]) -> Texture {
    Texture(width: 1, height: 1, pixels: rgba, clamp: false)
}

/// The engine's built-in textures. Noise is generated (the engine's own isn't
/// shipped): smooth, tiling and the same on every run.
let builtins: [String: Texture] = {
    var table: [String: Texture] = [
        "white": solidTexture([255, 255, 255, 255]), "black": solidTexture([0, 0, 0, 255]),
        "noflow": solidTexture([127, 127, 0, 255]), "clear": solidTexture([0, 0, 0, 0]),
    ]
    let size = 256
    var noise = [UInt8](repeating: 255, count: size * size * 4)
    func hash(_ x: Int, _ y: Int, _ c: Int) -> Double {
        var h = UInt32(truncatingIfNeeded: (x & (size / 16 - 1)) &* 374_761_393 &+ (y & (size / 16 - 1)) &* 668_265_263 &+ c &* 2_147_483_647)
        h = (h ^ (h >> 13)) &* 1_274_126_177
        return Double(h ^ (h >> 16)) / Double(UInt32.max)
    }
    for y in 0..<size {
        for x in 0..<size {
            for c in 0..<3 {
                let fx = Double(x) / 16, fy = Double(y) / 16
                let x0 = Int(fx), y0 = Int(fy)
                let sx = fx - Double(x0), sy = fy - Double(y0)
                let ux = sx * sx * (3 - 2 * sx), uy = sy * sy * (3 - 2 * sy)
                let top = hash(x0, y0, c) * (1 - ux) + hash(x0 + 1, y0, c) * ux
                let bottom = hash(x0, y0 + 1, c) * (1 - ux) + hash(x0 + 1, y0 + 1, c) * ux
                noise[(y * size + x) * 4 + c] = UInt8(max(0, min(255, (top * (1 - uy) + bottom * uy) * 255)))
            }
        }
    }
    table["noise"] = Texture(width: size, height: size, pixels: noise, clamp: false)
    // util/clouds_256 (not shipped): tiling fractal noise, the usual cloud source.
    var clouds = [UInt8](repeating: 255, count: size * size * 4)
    func value(_ x: Double, _ y: Double, _ cells: Int, _ seed: Int) -> Double {
        let fx = x * Double(cells), fy = y * Double(cells)
        let x0 = Int(fx), y0 = Int(fy)
        let sx = fx - Double(x0), sy = fy - Double(y0)
        let ux = sx * sx * (3 - 2 * sx), uy = sy * sy * (3 - 2 * sy)
        func h(_ i: Int, _ j: Int) -> Double {
            var v = UInt32(truncatingIfNeeded: ((i % cells + cells) % cells) &* 374_761_393 &+ ((j % cells + cells) % cells) &* 668_265_263 &+ seed &* 97)
            v = (v ^ (v >> 13)) &* 1_274_126_177
            return Double(v ^ (v >> 16)) / Double(UInt32.max)
        }
        let top = h(x0, y0) * (1 - ux) + h(x0 + 1, y0) * ux
        let bottom = h(x0, y0 + 1) * (1 - ux) + h(x0 + 1, y0 + 1) * ux
        return top * (1 - uy) + bottom * uy
    }
    for y in 0..<size {
        for x in 0..<size {
            let u = Double(x) / Double(size), v = Double(y) / Double(size)
            var total = 0.0, amplitude = 0.5
            for (octave, cells) in [4, 8, 16, 32, 64].enumerated() {
                total += value(u, v, cells, octave) * amplitude
                amplitude *= 0.5
            }
            let byte = UInt8(max(0, min(255, total / 0.97 * 255)))
            clouds[(y * size + x) * 4] = byte; clouds[(y * size + x) * 4 + 1] = byte; clouds[(y * size + x) * 4 + 2] = byte
        }
    }
    table["clouds_256"] = Texture(width: size, height: size, pixels: clouds, clamp: false)
    return table
}()

// MARK: - Shaders

let prelude = """
#define GLSL 1
#define HLSL 0
#define float2 vec2
#define float3 vec3
#define float4 vec4
#define float2x2 mat2
#define float3x3 mat3
#define float4x4 mat4
#define M_PI 3.14159265359
#define M_PI_HALF 1.57079632679
#define M_PI_2 6.28318530718
#define SQRT_2 1.41421356237
#define SQRT_3 1.73205080757
#define CAST2(x) (vec2(x))
#define CAST3(x) (vec3(x))
#define CAST4(x) (vec4(x))
#define CAST3X3(x) (mat3(x))
#define frac fract
#define saturate(x) clamp(x, 0.0, 1.0)
#define texSample2D texture2D
#define mul(x, y) ((y) * (x))
#define lerp mix
#define atan2 atan
#define fmod(x, y) mod(x, y)
#define ddx dFdx
#define ddy(x) dFdy(-(x))
#define log10(x) (log2(x) * 0.301029995663981)
vec2 rotateVec2(vec2 v, float r) { vec2 cs = vec2(cos(r), sin(r)); return vec2(v.x * cs.x - v.y * cs.y, v.x * cs.y + v.y * cs.x); }
float greyscale(vec3 c) { return dot(c, vec3(0.11, 0.59, 0.3)); }
vec3 wsColorBurn(vec3 a, vec3 b) { return vec3(b.r == 0.0 ? 0.0 : max(1.0 - (1.0 - a.r) / b.r, 0.0), b.g == 0.0 ? 0.0 : max(1.0 - (1.0 - a.g) / b.g, 0.0), b.b == 0.0 ? 0.0 : max(1.0 - (1.0 - a.b) / b.b, 0.0)); }
vec3 wsColorDodge(vec3 a, vec3 b) { return vec3(b.r == 1.0 ? 1.0 : min(a.r / (1.0 - b.r), 1.0), b.g == 1.0 ? 1.0 : min(a.g / (1.0 - b.g), 1.0), b.b == 1.0 ? 1.0 : min(a.b / (1.0 - b.b), 1.0)); }
vec3 wsReflect(vec3 a, vec3 b) { return vec3(b.r == 1.0 ? 1.0 : min(a.r * a.r / (1.0 - b.r), 1.0), b.g == 1.0 ? 1.0 : min(a.g * a.g / (1.0 - b.g), 1.0), b.b == 1.0 ? 1.0 : min(a.b * a.b / (1.0 - b.b), 1.0)); }
vec3 wsOverlay(vec3 a, vec3 b) { return vec3(a.r < 0.5 ? 2.0 * a.r * b.r : 1.0 - 2.0 * (1.0 - a.r) * (1.0 - b.r), a.g < 0.5 ? 2.0 * a.g * b.g : 1.0 - 2.0 * (1.0 - a.g) * (1.0 - b.g), a.b < 0.5 ? 2.0 * a.b * b.b : 1.0 - 2.0 * (1.0 - a.b) * (1.0 - b.b)); }
vec3 rgb2hsvBlend(vec3 c) {
    vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}
vec3 hsv2rgbBlend(vec3 c) {
    vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
    return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}
vec3 BlendMode(int mode, vec3 a, vec3 b) {
    if (mode == 1) return min(a, b);
    if (mode == 2) return a * b;
    if (mode == 3) return wsColorBurn(a, b);
    if (mode == 4) return max(a + b - 1.0, 0.0);
    if (mode == 5) return dot(a, vec3(1.0)) < dot(b, vec3(1.0)) ? a : b;
    if (mode == 6) return max(a, b);
    if (mode == 7) return 1.0 - (1.0 - a) * (1.0 - b);
    if (mode == 8) return wsColorDodge(a, b);
    if (mode == 9) return min(a + b, 1.0);
    if (mode == 10) return dot(a, vec3(1.0)) > dot(b, vec3(1.0)) ? a : b;
    if (mode == 11) return wsOverlay(a, b);
    if (mode == 12) return (1.0 - 2.0 * b) * a * a + 2.0 * b * a;
    if (mode == 13) return wsOverlay(b, a);
    if (mode == 14) return mix(wsColorBurn(a, 2.0 * b), wsColorDodge(a, 2.0 * (b - 0.5)), step(0.5, b));
    if (mode == 15) return clamp(a + 2.0 * b - 1.0, 0.0, 1.0);
    if (mode == 16) return mix(min(a, 2.0 * b), max(a, 2.0 * (b - 0.5)), step(0.5, b));
    if (mode == 17) return step(1.0, a + b);
    if (mode == 18) return abs(a - b);
    if (mode == 19) return a + b - 2.0 * a * b;
    if (mode == 20) return max(a - b, 0.0);
    if (mode == 21) return wsReflect(a, b);
    if (mode == 22) return wsReflect(b, a);
    if (mode == 23) return min(a, b) - max(a, b) + 1.0;
    if (mode == 24) return (a + b) * 0.5;
    if (mode == 25) return 1.0 - abs(1.0 - a - b);
    if (mode >= 26 && mode <= 29) {
        vec3 x = rgb2hsvBlend(a), y = rgb2hsvBlend(b);
        if (mode == 26) return hsv2rgbBlend(vec3(y.x, x.y, x.z));
        if (mode == 27) return hsv2rgbBlend(vec3(x.x, y.y, x.z));
        if (mode == 28) return hsv2rgbBlend(vec3(y.x, y.y, x.z));
        return hsv2rgbBlend(vec3(x.x, x.y, y.z));
    }
    if (mode == 0) return b;
    // 30 and above aren't in the documented list. The tint effect's own
    // default is 30, and the scenes' previews show it tinting: multiply.
    return a * b;
}
vec3 ApplyBlending(int mode, vec3 a, vec3 b, float opacity) { return mix(a, BlendMode(mode, a, b), opacity); }
vec3 BlendOpacity(vec3 a, vec3 b, int mode, float opacity) { return mix(a, BlendMode(mode, a, b), opacity); }
vec3 BlendOpacity(vec3 a, float b, int mode, float opacity) { return mix(a, BlendMode(mode, a, vec3(b)), opacity); }
#define BlendNormal 0
#define BlendDarken 1
#define BlendMultiply 2
#define BlendColorBurn 3
#define BlendLinearBurn 4
#define BlendDarkerColor 5
#define BlendLighten 6
#define BlendScreen 7
#define BlendColorDodge 8
#define BlendLinearDodge 9
#define BlendLighterColor 10
#define BlendOverlay 11
#define BlendSoftLight 12
#define BlendHardLight 13
#define BlendVividLight 14
#define BlendLinearLight 15
#define BlendPinLight 16
#define BlendHardMix 17
#define BlendDifference 18
#define BlendExclusion 19
#define BlendSubtract 20
#define BlendReflect 21
#define BlendGlow 22
#define BlendPhoenix 23
#define BlendAverage 24
#define BlendNegation 25
#define BlendHue 26
#define BlendSaturation 27
#define BlendColor 28
#define BlendLuminosity 29
#define BlendAdd 9
vec3 rgb2hsv(vec3 c) {
    vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}
vec3 hsv2rgb(vec3 c) {
    vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
    return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}
// The homography taking the unit square to the quad p0 p1 p2 p3.
mat3 squareToQuad(vec2 p0, vec2 p1, vec2 p2, vec2 p3) {
    float dx1 = p1.x - p2.x, dx2 = p3.x - p2.x, dx3 = p0.x - p1.x + p2.x - p3.x;
    float dy1 = p1.y - p2.y, dy2 = p3.y - p2.y, dy3 = p0.y - p1.y + p2.y - p3.y;
    float den = dx1 * dy2 - dx2 * dy1;
    float g = den == 0.0 ? 0.0 : (dx3 * dy2 - dx2 * dy3) / den;
    float h = den == 0.0 ? 0.0 : (dx1 * dy3 - dx3 * dy1) / den;
    return mat3(p1.x - p0.x + g * p1.x, p1.y - p0.y + g * p1.y, g,
                p3.x - p0.x + h * p3.x, p3.y - p0.y + h * p3.y, h,
                p0.x, p0.y, 1.0);
}
vec4 blurTaps(sampler2D t, vec2 u, vec2 d, int radius) {
    vec4 sum = vec4(0.0); float total = 0.0;
    for (int i = -6; i <= 6; i++) {
        if (i < -radius || i > radius) continue;
        float sigma = float(radius) / 2.0 + 0.5;
        float w = exp(-float(i * i) / (2.0 * sigma * sigma));
        sum += texture2D(t, u + d * float(i)) * w; total += w;
    }
    return sum / total;
}
#define blur3a(u, d) blurTaps(g_Texture0, u, d, 1)
#define blur5a(u, d) blurTaps(g_Texture0, u, d, 2)
#define blur7a(u, d) blurTaps(g_Texture0, u, d, 3)
#define blur13a(u, d) blurTaps(g_Texture0, u, d, 6)
#define ApplyCompositeOffset(u, r) (u)
// The composite settings live in a header that isn't shipped: its default
// (use the processed picture) is what's applied.
vec4 ApplyComposite(vec4 original, vec4 processed) { return processed; }
mat3 inverse(mat3 m) {
    float a = m[0][0], b = m[0][1], c = m[0][2], d = m[1][0], e = m[1][1], f = m[1][2], g = m[2][0], h = m[2][1], i = m[2][2];
    float A = e * i - f * h, B = -(d * i - f * g), C = d * h - e * g;
    float det = a * A + b * B + c * C;
    return mat3(A, -(b * i - c * h), b * f - c * e, B, a * i - c * g, -(a * f - c * d), C, -(a * h - b * g), a * e - b * d) / det;
}
// HLSL is looser about argument types than GLSL 1.20.
vec3 max(int a, vec3 b) { return max(vec3(float(a)), b); }
float max(int a, float b) { return max(float(a), b); }
float max(float a, int b) { return max(a, float(b)); }
float min(int a, float b) { return min(float(a), b); }
float min(float a, int b) { return min(a, float(b)); }
vec2 max(int a, vec2 b) { return max(vec2(float(a)), b); }
vec4 max(int a, vec4 b) { return max(vec4(float(a)), b); }
vec3 min(int a, vec3 b) { return min(vec3(float(a)), b); }
vec4 pow(vec4 a, float b) { return pow(a, vec4(b)); }
vec3 pow(vec3 a, float b) { return pow(a, vec3(b)); }
vec4 texture2D(sampler2D s, vec4 u) { return texture2D(s, u.xy); }

"""

struct Program {
    let id: GLuint
    let uniforms: [String: (location: GLint, type: GLenum)]
}

var programs: [String: Program?] = [:]
let includeLine = try! NSRegularExpression(pattern: #"^\s*#include\s+"[^"]*"\s*$"#, options: .anchorsMatchLines)
let conditionLine = try! NSRegularExpression(pattern: #"^\s*#\s*(?:if|elif)\b(.*)$"#, options: .anchorsMatchLines)
let identifier = try! NSRegularExpression(pattern: #"\b[A-Z_][A-Z0-9_]*\b"#)
let defineLine = try! NSRegularExpression(pattern: #"^\s*#\s*define\s+([A-Za-z_][A-Za-z0-9_]*)"#, options: .anchorsMatchLines)

func stage(_ source: String, fragment: Bool, combos: [String: Int]) -> String {
    let range = NSRange(source.startIndex..., in: source)
    let body = includeLine.stringByReplacingMatches(in: source, range: range, withTemplate: "")
    var defines = combos
    // Names the shader defines itself are its own business.
    var own = Set<String>()
    for match in defineLine.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
        if let r = Range(match.range(at: 1), in: body) { own.insert(String(body[r])) }
    }
    // Combos a shader tests but nobody set are off, as in the engine.
    for match in conditionLine.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
        guard let condition = Range(match.range(at: 1), in: body) else { continue }
        let text = String(body[condition])
        for word in identifier.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let r = Range(word.range, in: text) {
                let name = String(text[r])
                if name != "GLSL", name != "HLSL", !own.contains(name), defines[name] == nil { defines[name] = 0 }
            }
        }
    }
    // No texture here has a mip chain, so sampling level 0 is exact.
    let head = "#version 120\n#define texSample2DLod(s, u, l) texture2D(s, u)\n"
    _ = fragment
    let defineText = defines.sorted { $0.key < $1.key }.map { "#define \($0.key) \($0.value)" }.joined(separator: "\n")
    return head + defineText + "\n" + prelude + "\n" + body
}

func compile(_ type: Int32, _ source: String) -> (GLuint, String?) {
    let shader = glCreateShader(GLenum(type))
    source.withCString { pointer in
        var p: UnsafePointer<GLchar>? = pointer
        glShaderSource(shader, 1, &p, nil)
    }
    glCompileShader(shader)
    var ok: GLint = 0
    glGetShaderiv(shader, GLenum(GL_COMPILE_STATUS), &ok)
    if ok != 0 { return (shader, nil) }
    var log = [GLchar](repeating: 0, count: 1024)
    glGetShaderInfoLog(shader, 1024, nil, &log)
    return (shader, String(cString: log))
}

func program(vertex: String, fragment: String, combos: [String: Int], label: String) -> Program? {
    let key = "\(vertex)|\(fragment)|\(combos.sorted { $0.key < $1.key })"
    if let cached = programs[key] { return cached }
    func link() -> Program? {
        guard let vs = try? String(contentsOfFile: vertex, encoding: .utf8),
              let fs = try? String(contentsOfFile: fragment, encoding: .utf8) else { return nil }
        let (v, vError) = compile(GL_VERTEX_SHADER, stage(vs, fragment: false, combos: combos))
        let (f, fError) = compile(GL_FRAGMENT_SHADER, stage(fs, fragment: true, combos: combos))
        if let error = vError ?? fError {
            notes.insert("\(label): shader didn't compile (\(error.split(separator: "\n").first ?? ""))")
            return nil
        }
        let id = glCreateProgram()
        glAttachShader(id, v)
        glAttachShader(id, f)
        glBindAttribLocation(id, 0, "a_Position")
        glBindAttribLocation(id, 1, "a_TexCoord")
        glLinkProgram(id)
        var ok: GLint = 0
        glGetProgramiv(id, GLenum(GL_LINK_STATUS), &ok)
        guard ok != 0 else {
            notes.insert("\(label): shader didn't link")
            return nil
        }
        var count: GLint = 0
        glGetProgramiv(id, GLenum(GL_ACTIVE_UNIFORMS), &count)
        var table: [String: (GLint, GLenum)] = [:]
        for index in 0..<GLuint(max(0, count)) {
            var name = [GLchar](repeating: 0, count: 256)
            var length: GLsizei = 0, size: GLint = 0, type: GLenum = 0
            glGetActiveUniform(id, index, 256, &length, &size, &type, &name)
            var text = String(cString: name)
            if text.hasSuffix("[0]") { text.removeLast(3) }
            table[text] = (glGetUniformLocation(id, text), type)
        }
        return Program(id: id, uniforms: table.mapValues { (location: $0.0, type: $0.1) })
    }
    let made = link()
    programs[key] = made
    return made
}

// The layer compositing program: Wallpaper Engine's own image shader isn't
// shipped, so this is the one part written here. Colour tints the picture
// (multiply, or the stated blend mode where the enum is known); brightness
// scales it; alpha fades it.
let compositeVertex = """
attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec2 v_TexCoord;
void main() { gl_Position = vec4(a_Position, 1.0); v_TexCoord = a_TexCoord; }
"""
let compositeFragment = """
varying vec2 v_TexCoord;
uniform sampler2D g_Texture0;
uniform vec3 u_Color;
uniform float u_Alpha;
uniform float u_Brightness;
uniform int u_TintMode;
void main() {
    vec4 albedo = texture2D(g_Texture0, v_TexCoord);
    albedo.rgb *= u_Color;
    albedo.rgb *= u_Brightness;
    albedo.a *= u_Alpha;
    gl_FragColor = albedo;
}
"""
let mixFragment = """
varying vec2 v_TexCoord;
uniform sampler2D g_Texture0;
uniform sampler2D g_Texture1;
uniform float u_Mix;
void main() { gl_FragColor = mix(texture2D(g_Texture0, v_TexCoord), texture2D(g_Texture1, v_TexCoord), u_Mix); }
"""
let copyFragment = """
varying vec2 v_TexCoord;
uniform sampler2D g_Texture0;
void main() { gl_FragColor = texture2D(g_Texture0, v_TexCoord); }
"""

func inlineProgram(_ fragment: String, _ label: String) -> Program {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("wescene-\(getpid())")
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let v = directory.appendingPathComponent("\(label).vert"), f = directory.appendingPathComponent("\(label).frag")
    try? compositeVertex.write(to: v, atomically: true, encoding: .utf8)
    try? fragment.write(to: f, atomically: true, encoding: .utf8)
    guard let made = program(vertex: v.path, fragment: f.path, combos: [:], label: label) else { fail("internal shader \(label)") }
    return made
}

let compositeProgram = inlineProgram(compositeFragment, "composite")
let mixProgram = inlineProgram(mixFragment, "mix")
let copyProgram = inlineProgram(copyFragment, "copy")

// MARK: - Drawing

/// Draws a quad: four positions (x, y, z) and texture coordinates, as a strip.
func drawQuad(_ positions: [Float], _ coordinates: [Float]) {
    positions.withUnsafeBufferPointer { p in
        coordinates.withUnsafeBufferPointer { c in
            glEnableVertexAttribArray(0)
            glEnableVertexAttribArray(1)
            glVertexAttribPointer(0, 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), 0, p.baseAddress)
            glVertexAttribPointer(1, 2, GLenum(GL_FLOAT), GLboolean(GL_FALSE), 0, c.baseAddress)
            glDrawArrays(GLenum(GL_TRIANGLE_STRIP), 0, 4)
        }
    }
}

/// Texture coordinates for top-left, top-right, bottom-left, bottom-right.
let quadCoordinates: [Float] = [0, 0, 1, 0, 0, 1, 1, 1]

func setBlending(_ mode: String?) {
    switch mode {
    case "additive":
        glEnable(GLenum(GL_BLEND))
        glBlendFuncSeparate(GLenum(GL_SRC_ALPHA), GLenum(GL_ONE), GLenum(GL_ZERO), GLenum(GL_ONE))
    case "translucent":
        glEnable(GLenum(GL_BLEND))
        glBlendFuncSeparate(GLenum(GL_SRC_ALPHA), GLenum(GL_ONE_MINUS_SRC_ALPHA), GLenum(GL_ONE), GLenum(GL_ONE_MINUS_SRC_ALPHA))
    default:
        glDisable(GLenum(GL_BLEND))
    }
}

func uniform(_ program: Program, _ name: String, _ values: [Double]) {
    guard let entry = program.uniforms[name], entry.location >= 0 else { return }
    let f = values.map { Float($0) }
    func at(_ i: Int) -> Float { i < f.count ? f[i] : 0 }
    switch Int32(entry.type) {
    case GL_FLOAT: glUniform1f(entry.location, at(0))
    case GL_FLOAT_VEC2: glUniform2f(entry.location, at(0), at(1))
    case GL_FLOAT_VEC3: glUniform3f(entry.location, at(0), at(1), at(2))
    case GL_FLOAT_VEC4: glUniform4f(entry.location, at(0), at(1), at(2), at(3))
    case GL_INT, GL_BOOL: glUniform1i(entry.location, GLint(at(0)))
    case GL_FLOAT_MAT4:
        var m = f.count == 16 ? f : [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
        glUniformMatrix4fv(entry.location, 1, GLboolean(GL_FALSE), &m)
    default: break
    }
}

func bindTexture(_ program: Program, slot: Int, _ texture: Texture) {
    glActiveTexture(GLenum(GL_TEXTURE0 + Int32(slot)))
    glBindTexture(GLenum(GL_TEXTURE_2D), texture.id)
    if let entry = program.uniforms["g_Texture\(slot)"], entry.location >= 0 { glUniform1i(entry.location, GLint(slot)) }
    uniform(program, "g_Texture\(slot)Resolution", [Double(texture.width), Double(texture.height), Double(texture.width), Double(texture.height)])
}

// MARK: - Transforms

struct Affine {
    var a = 1.0, b = 0.0, c = 0.0, d = 1.0, tx = 0.0, ty = 0.0
    func then(_ m: Affine) -> Affine {   // self applied after m
        Affine(a: a * m.a + c * m.b, b: b * m.a + d * m.b, c: a * m.c + c * m.d, d: b * m.c + d * m.d,
               tx: a * m.tx + c * m.ty + tx, ty: b * m.tx + d * m.ty + ty)
    }
    func apply(_ x: Double, _ y: Double) -> (Double, Double) { (a * x + c * y + tx, b * x + d * y + ty) }
}

func world(_ layer: Layer, _ t: Double) -> Affine {
    layer.chain.reduce(Affine()) { parent, node in
        let origin = node.origin.at(t), scale = node.scale.at(t), angle = node.angles.at(t)[2]
        let local = Affine(a: cos(angle) * scale[0], b: sin(angle) * scale[0], c: -sin(angle) * scale[1], d: cos(angle) * scale[1],
                           tx: origin[0], ty: origin[1])
        return parent.then(local)
    }
}

/// The layer's corners in scene units: top-left, top-right, bottom-left, bottom-right.
func corners(_ layer: Layer, _ t: Double) -> [(Double, Double)] {
    let w = layer.size[0], h = layer.size[1]
    var x0 = -w / 2, x1 = w / 2, y0 = -h / 2, y1 = h / 2
    let alignment = layer.alignment.lowercased()
    if alignment.contains("left") { x0 = 0; x1 = w } else if alignment.contains("right") { x0 = -w; x1 = 0 }
    if alignment.contains("top") { y0 = -h; y1 = 0 } else if alignment.contains("bottom") { y0 = 0; y1 = h }
    let m = world(layer, t)
    return [m.apply(x0, y1), m.apply(x1, y1), m.apply(x0, y0), m.apply(x1, y0)]
}

// MARK: - The scene, frame by frame

let sceneTarget = Target(width: outputWidth, height: outputHeight)
let snapshotTarget = Target(width: outputWidth, height: outputHeight)
var layerTargets: [String: Target] = [:]
var renderedLayers: [Int: Texture] = [:]
var rendering = Set<Int>()

func target(_ key: String, _ width: Int, _ height: Int) -> Target {
    if let existing = layerTargets[key], existing.width == width, existing.height == height { return existing }
    let made = Target(width: width, height: height)
    layerTargets[key] = made
    return made
}

/// Copies the scene so far, so a pass can read it while the scene is drawn into.
func snapshot() -> Texture {
    snapshotTarget.bind(clear: nil)
    glDisable(GLenum(GL_BLEND))
    glUseProgram(copyProgram.id)
    bindTexture(copyProgram, slot: 0, sceneTarget.texture)
    // The scene is stored bottom-first (it's the output); the snapshot top-first.
    drawQuad([-1, -1, 0, 1, -1, 0, -1, 1, 0, 1, 1, 0], [0, 1, 1, 1, 0, 0, 1, 0])
    return snapshotTarget.texture
}

func frameOf(_ frames: [Frame], _ t: Double, _ timeScale: Double?) -> Frame {
    let total = frames.reduce(0) { $0 + $1.duration }
    guard total > 0 else { return frames[0] }
    var clock = (t * (timeScale ?? 1)).truncatingRemainder(dividingBy: total)
    for frame in frames {
        if clock < frame.duration { return frame }
        clock -= frame.duration
    }
    return frames[frames.count - 1]
}

func resolve(_ ref: TextureRef?, previous: Texture, buffers: [String: Target], t: Double, label: String) -> Texture {
    guard let ref else { return builtins["clear"]! }
    if ref.previous == true { return previous }
    if let fbo = ref.fbo {
        if let buffer = buffers[fbo] { return buffer.texture }
        notes.insert("\(label): render target \(fbo) isn't produced by this effect")
        return builtins["clear"]!
    }
    if let builtin = ref.builtin {
        if let texture = builtins[builtin] { return texture }
        notes.insert("built-in texture util/\(builtin) isn't available; left clear")
        return builtins["clear"]!
    }
    if ref.scene == true { return snapshot() }
    if let id = ref.layer {
        if let texture = renderedLayers[id] { return texture }
        // An effect reads a layer drawn later: make its picture now (once).
        if let index = scene.layers.firstIndex(where: { $0.id == id }), !rendering.contains(index) {
            rendering.insert(index)
            defer { rendering.remove(index) }
            if let picture = renderLayer(index, scene.layers[index], t) {
                renderedLayers[id] = picture
                return picture
            }
        }
        notes.insert("\(label): layer \(id)'s picture isn't available")
        return builtins["clear"]!
    }
    if let frames = ref.frames, !frames.isEmpty {
        let frame = frameOf(frames, t, ref.timeScale)
        return picture(frame.file, clamp: ref.clamp ?? false, nearest: ref.nearest ?? false) ?? builtins["clear"]!
    }
    if let file = ref.file { return picture(file, clamp: ref.clamp ?? false, nearest: ref.nearest ?? false) ?? builtins["clear"]! }
    return builtins["clear"]!
}

/// The pass quad in the target's own pixel units (y up), and the matrix that
/// stores it top-first.
func passMatrix(_ width: Int, _ height: Int) -> [Double] {
    [2 / Double(width), 0, 0, 0, 0, -2 / Double(height), 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
}

func passPositions(_ width: Int, _ height: Int) -> [Float] {
    let w = Float(width) / 2, h = Float(height) / 2
    return [-w, h, 0, w, h, 0, -w, -h, 0, w, -h, 0]
}

/// A layer's picture after its effects, stored top-first.
func renderLayer(_ index: Int, _ layer: Layer, _ t: Double) -> Texture? {
    let label = "layer \(layer.name.isEmpty ? String(index) : layer.name)"
    var width = Int(layer.size[0].rounded()), height = Int(layer.size[1].rounded())
    var base: Texture
    if layer.solid == true {
        base = builtins["white"]!
    } else if layer.background == true {
        // What's under the layer, in its own orientation.
        let points = corners(layer, t)
        let dx = hypot(points[1].0 - points[0].0, points[1].1 - points[0].1) * Double(outputWidth) / canvasWidth
        let dy = hypot(points[2].0 - points[0].0, points[2].1 - points[0].1) * Double(outputHeight) / canvasHeight
        width = max(1, Int(dx.rounded())); height = max(1, Int(dy.rounded()))
        let scene = snapshot()
        let capture = target("\(index)-background", min(width, 4096), min(height, 4096))
        capture.bind()
        glDisable(GLenum(GL_BLEND))
        glUseProgram(copyProgram.id)
        bindTexture(copyProgram, slot: 0, scene)
        // Snapshot rows are top-first: v = 1 - y / height.
        let coordinates = points.flatMap { [Float($0.0 / canvasWidth), Float(1 - $0.1 / canvasHeight)] }
        drawQuad([-1, -1, 0, 1, -1, 0, -1, 1, 0, 1, 1, 0], [coordinates[0], coordinates[1], coordinates[2], coordinates[3],
                                                            coordinates[4], coordinates[5], coordinates[6], coordinates[7]])
        base = capture.texture
    } else if let texture = layer.texture {
        base = resolve(texture, previous: builtins["clear"]!, buffers: [:], t: t, label: label)
    } else {
        return nil
    }
    if layer.effects.isEmpty { return base }
    // Effects run at the layer's own size in scene units, as in the engine.
    let fit = min(1.0, 4096 / Double(max(width, height, 1)))
    width = max(1, Int(Double(width) * fit)); height = max(1, Int(Double(height) * fit))
    var current = base
    var flip = 0
    for (e, effect) in layer.effects.enumerated() {
        let effectTime = t * (effect.timeScale ?? 1)
        var buffers: [String: Target] = [:]
        for buffer in effect.fbos {
            let s = max(buffer.scale, 1)
            buffers[buffer.name] = target("\(index)-\(e)-\(buffer.name)", max(1, Int(Double(width) / s)), max(1, Int(Double(height) / s)))
        }
        let input = current
        var output = input
        var ok = true
        for (p, pass) in effect.passes.enumerated() {
            guard let program = program(vertex: pass.vert, fragment: pass.frag, combos: pass.combos, label: "\(label) \(effect.kind)") else {
                ok = false
                break
            }
            let destination: Target
            if let name = pass.target, let buffer = buffers[name] {
                destination = buffer
            } else {
                flip += 1
                destination = target("\(index)-\(flip % 2)", width, height)
            }
            // Bind the textures first: some read the scene, which draws.
            var bound: [(Int, Texture)] = []
            for (slotText, ref) in pass.textures {
                guard let slot = Int(slotText) else { continue }
                bound.append((slot, resolve(ref, previous: input, buffers: buffers, t: effectTime, label: "\(label) \(effect.kind)")))
            }
            if pass.textures["0"] == nil { bound.append((0, input)) }
            destination.bind()
            setBlending(pass.blending)
            glUseProgram(program.id)
            for (slot, texture) in bound { bindTexture(program, slot: slot, texture) }
            for (name, track) in pass.uniforms { uniform(program, name, track.at(effectTime)) }
            uniform(program, "g_Time", [effectTime])
            uniform(program, "g_ModelViewProjectionMatrix", passMatrix(destination.width, destination.height))
            for identity in ["g_EffectTextureProjectionMatrix", "g_EffectTextureProjectionMatrixInverse", "g_ViewProjectionMatrix",
                             "g_ModelMatrix", "g_ModelMatrixInverse", "g_EffectModelMatrix"] {
                uniform(program, identity, [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])
            }
            uniform(program, "g_Screen", [canvasWidth, canvasHeight, canvasWidth / canvasHeight])
            for centre in ["g_PointerPosition", "g_PointerPositionLast", "g_ParallaxPosition"] { uniform(program, centre, [0.5, 0.5]) }
            uniform(program, "g_Daytime", [0.5])
            uniform(program, "g_Alpha", [1]); uniform(program, "g_Brightness", [1])
            uniform(program, "g_Color", [1, 1, 1]); uniform(program, "g_Color4", [1, 1, 1, 1])
            drawQuad(passPositions(destination.width, destination.height), quadCoordinates)
            _ = p
            if pass.target == nil { output = destination.texture }
        }
        if ok { current = output }
    }
    return current
}

func renderScene(_ clock: Double) {
    let t = clock + (scene.start ?? 0)
    let clear = scene.clear.map { Float($0) }
    sceneTarget.bind(clear: [clear[0], clear[1], clear[2], 1])
    renderedLayers.removeAll(keepingCapacity: true)
    for (index, layer) in scene.layers.enumerated() where layer.hidden != true {
        let picture: Texture
        if let id = layer.id, let early = renderedLayers[id] {
            picture = early
        } else {
            rendering.insert(index)
            let made = renderLayer(index, layer, t)
            rendering.remove(index)
            guard let made else { continue }
            picture = made
        }
        if let id = layer.id { renderedLayers[id] = picture }
        let points = corners(layer, t)
        sceneTarget.bind(clear: nil)
        setBlending(layer.blending == "additive" ? "additive" : "translucent")
        glUseProgram(compositeProgram.id)
        bindTexture(compositeProgram, slot: 0, picture)
        uniform(compositeProgram, "u_Color", layer.color.at(t))
        uniform(compositeProgram, "u_Alpha", layer.alpha.at(t))
        uniform(compositeProgram, "u_Brightness", layer.brightness.at(t))
        uniform(compositeProgram, "u_TintMode", [Double(layer.colorBlendMode)])
        let positions = points.flatMap { [Float($0.0 / canvasWidth * 2 - 1), Float($0.1 / canvasHeight * 2 - 1), 0] }
        drawQuad(positions, quadCoordinates)
    }
}

// MARK: - Output

var rows = [UInt8](repeating: 0, count: outputWidth * outputHeight * 4)

func read(_ source: Target) {
    source.bind(clear: nil)
    glReadPixels(0, 0, GLsizei(outputWidth), GLsizei(outputHeight), GLenum(GL_BGRA), GLenum(GL_UNSIGNED_INT_8_8_8_8_REV), &rows)
}

let mixTarget = Target(width: outputWidth, height: outputHeight)
let heldTarget = Target(width: outputWidth, height: outputHeight)

/// The frame at time t, with the loop's tail blended into its head.
func frame(at t: Double, seconds: Double, crossfade: Double) -> Target {
    renderScene(t)
    guard crossfade > 0, t < crossfade else { return sceneTarget }
    // Hold R(t), render R(t + T), and ease from the latter into the former.
    heldTarget.bind(clear: nil)
    glDisable(GLenum(GL_BLEND))
    glUseProgram(copyProgram.id)
    bindTexture(copyProgram, slot: 0, sceneTarget.texture)
    drawQuad([-1, -1, 0, 1, -1, 0, -1, 1, 0, 1, 1, 0], [0, 0, 1, 0, 0, 1, 1, 1])
    renderScene(t + seconds)
    let x = t / crossfade
    mixTarget.bind(clear: nil)
    glUseProgram(mixProgram.id)
    bindTexture(mixProgram, slot: 0, sceneTarget.texture)
    bindTexture(mixProgram, slot: 1, heldTarget.texture)
    uniform(mixProgram, "u_Mix", [x * x * (3 - 2 * x)])
    drawQuad([-1, -1, 0, 1, -1, 0, -1, 1, 0, 1, 1, 0], [0, 0, 1, 0, 0, 1, 1, 1])
    return mixTarget
}

func report(_ extra: String) {
    let list = notes.sorted().map { "\"\($0.replacingOccurrences(of: "\"", with: "'"))\"" }.joined(separator: ", ")
    print(#"{"width": \#(outputWidth), "height": \#(outputHeight), \#(extra), "notes": [\#(list)]}"#)
}

if still {
    read(frame(at: 0, seconds: 0, crossfade: 0))
    // BGRA bottom-first → RGBA top-first for the JPEG.
    var image = [UInt8](repeating: 0, count: rows.count)
    for y in 0..<outputHeight {
        let from = (outputHeight - 1 - y) * outputWidth * 4, to = y * outputWidth * 4
        for x in 0..<outputWidth {
            let s = from + x * 4, d = to + x * 4
            image[d] = rows[s + 2]; image[d + 1] = rows[s + 1]; image[d + 2] = rows[s]; image[d + 3] = 255
        }
    }
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: &image, width: outputWidth, height: outputHeight, bitsPerComponent: 8,
                                  bytesPerRow: outputWidth * 4, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
          let cgImage = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
    else { fail("couldn't write the picture") }
    CGImageDestinationAddImage(destination, cgImage, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { fail("couldn't write the picture") }
    report(#""still": true"#)
    exit(0)
}

let seconds = max(1, scene.seconds ?? 15)
let crossfade = min(scene.crossfade ?? 1, seconds / 4)
let frameCount = Int((seconds * Double(fps)).rounded())
try? FileManager.default.removeItem(at: outputURL)
guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else { fail("couldn't start the video") }
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: outputWidth, AVVideoHeightKey: outputHeight,
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 10_000_000, AVVideoExpectedSourceFrameRateKey: fps,
                                      AVVideoMaxKeyFrameIntervalKey: fps * 2],
])
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: outputWidth, kCVPixelBufferHeightKey as String: outputHeight,
])
writer.add(input)
guard writer.startWriting() else { fail("couldn't start the video: \(writer.error?.localizedDescription ?? "")") }
writer.startSession(atSourceTime: .zero)
for n in 0..<frameCount {
    read(frame(at: Double(n) / Double(fps), seconds: seconds, crossfade: crossfade))
    while !input.isReadyForMoreMediaData { usleep(2000) }
    guard let pool = adaptor.pixelBufferPool else { fail("no pixel buffers") }
    var buffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
    guard let buffer else { fail("no pixel buffer") }
    CVPixelBufferLockBaseAddress(buffer, [])
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    let base = CVPixelBufferGetBaseAddress(buffer)!
    rows.withUnsafeBytes { source in
        for y in 0..<outputHeight {
            memcpy(base + y * stride, source.baseAddress! + (outputHeight - 1 - y) * outputWidth * 4, outputWidth * 4)
        }
    }
    CVPixelBufferUnlockBaseAddress(buffer, [])
    adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(n), timescale: CMTimeScale(fps)))
}
input.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
guard writer.status == .completed else { fail("couldn't finish the video: \(writer.error?.localizedDescription ?? "")") }
report(#""seconds": \#(seconds), "fps": \#(fps), "frames": \#(frameCount), "crossfade": \#(crossfade)"#)
