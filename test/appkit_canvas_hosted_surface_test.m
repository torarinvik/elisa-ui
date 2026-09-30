// Headless compositing check for hosted surfaces (canvas_shim/hosted_surface.m).
// A layer tree like the canvas view's (flipped root, background colour) gets an
// IOSurface in a slot; CARenderer composites the tree into a Metal texture that is
// read back, so the zero-copy path is verified without a window or a screenshot.

#import "../src/platform/appkit/appkit_canvas_shim.m"
#import "appkit_canvas_bridge_stubs.m"
#import <Metal/Metal.h>

enum { W = 200, H = 100 };

static int require(BOOL condition, const char *message) {
    if (condition) return 0;
    fprintf(stderr, "hosted surface: %s\n", message);
    return 1;
}

static IOSurfaceRef make_surface(int width, int height) {
    NSDictionary *props = @{
        (id)kIOSurfaceWidth: @(width), (id)kIOSurfaceHeight: @(height),
        (id)kIOSurfaceBytesPerElement: @4, (id)kIOSurfacePixelFormat: @((uint32_t)'BGRA'),
    };
    return IOSurfaceCreate((__bridge CFDictionaryRef)props);
}

// Fill with one BGRA colour.
static void fill(IOSurfaceRef surface, uint8_t r, uint8_t g, uint8_t b) {
    IOSurfaceLock(surface, 0, NULL);
    uint8_t *base = IOSurfaceGetBaseAddress(surface);
    size_t stride = IOSurfaceGetBytesPerRow(surface);
    for (size_t y = 0; y < IOSurfaceGetHeight(surface); y++) {
        for (size_t x = 0; x < IOSurfaceGetWidth(surface); x++) {
            uint8_t *p = base + y * stride + x * 4;
            p[0] = b; p[1] = g; p[2] = r; p[3] = 255;
        }
    }
    IOSurfaceUnlock(surface, 0, NULL);
}

typedef struct { id<MTLDevice> device; id<MTLCommandQueue> queue; id<MTLTexture> target; CARenderer *renderer; } Compositor;

static void composite(Compositor *c, uint8_t *out) {
    [CATransaction flush];
    [c->renderer beginFrameAtTime:CACurrentMediaTime() timeStamp:NULL];
    [c->renderer addUpdateRect:CGRectMake(0, 0, W, H)];
    [c->renderer render];
    [c->renderer endFrame];
    // CARenderer encodes on our queue; an empty buffer after it marks completion.
    id<MTLCommandBuffer> done = [c->queue commandBuffer];
    [done commit];
    [done waitUntilCompleted];
    [c->target getBytes:out bytesPerRow:W * 4 fromRegion:MTLRegionMake2D(0, 0, W, H) mipmapLevel:0];
}

// BGRA pixel at (x, y) in the root layer's flipped (top-down) coordinates.
// CARenderer's target rows run bottom-up, so the row index is mirrored.
static BOOL near(const uint8_t *img, int x, int y, uint8_t r, uint8_t g, uint8_t b) {
    const uint8_t *p = img + ((H - 1 - y) * W + x) * 4;
    return abs(p[2] - r) <= 2 && abs(p[1] - g) <= 2 && abs(p[0] - b) <= 2;
}

int main(void) {
    @autoreleasepool {
        Compositor c;
        c.device = MTLCreateSystemDefaultDevice();
        if (c.device == nil) { fprintf(stderr, "hosted surface: skipped (no Metal device)\n"); return 0; }
        c.queue = [c.device newCommandQueue];
        MTLTextureDescriptor *desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
            width:W height:H mipmapped:NO];
        desc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
        desc.storageMode = MTLStorageModeShared;
        c.target = [c.device newTextureWithDescriptor:desc];

        CALayer *root = [CALayer layer];
        root.bounds = CGRectMake(0, 0, W, H);
        root.position = CGPointMake(W / 2.0, H / 2.0);
        root.geometryFlipped = YES; // like the flipped canvas view
        CGColorRef grey = CGColorCreateSRGB(0.2, 0.2, 0.2, 1.0);
        root.backgroundColor = grey;
        CGColorRelease(grey);
        c.renderer = [CARenderer rendererWithMTLTexture:c.target
            options:@{kCARendererMetalCommandQueue: c.queue}];
        c.renderer.layer = root;
        c.renderer.bounds = root.bounds;
        size_t rootHandle = (size_t)(__bridge void *)root;

        IOSurfaceRef red = make_surface(64, 48);
        IOSurfaceRef blue = make_surface(32, 16);
        if (require(red != NULL && blue != NULL, "IOSurfaceCreate failed")) return 1;
        fill(red, 220, 30, 30);
        fill(blue, 20, 40, 230);

        // Adversarial calls change nothing.
        if (require(!elisa_appkit_canvas_hosted_layer_apply(0, 0, (size_t)red, 0, 0, 10, 10), "null root accepted")) return 1;
        if (require(!elisa_appkit_canvas_hosted_layer_apply(rootHandle, -1, (size_t)red, 0, 0, 10, 10), "slot -1 accepted")) return 1;
        if (require(!elisa_appkit_canvas_hosted_layer_apply(rootHandle, 16, (size_t)red, 0, 0, 10, 10), "slot 16 accepted")) return 1;
        if (require(!elisa_appkit_canvas_hosted_layer_apply(rootHandle, 0, 0, 0, 0, 10, 10), "null surface accepted")) return 1;
        if (require(!elisa_appkit_canvas_hosted_layer_remove(rootHandle, 0), "removed a slot never applied")) return 1;
        if (require(root.sublayers.count == 0, "adversarial call added a layer")) return 1;

        static uint8_t img[W * H * 4];
        // Slot 0: red at (20, 10) 64x48 points; slot 1: blue at (120, 50) 40x30,
        // scaled from its 32x16 surface.
        if (require(elisa_appkit_canvas_hosted_layer_apply(rootHandle, 0, (size_t)red, 20, 10, 64, 48), "apply slot 0")) return 1;
        if (require(elisa_appkit_canvas_hosted_layer_apply(rootHandle, 1, (size_t)blue, 120, 50, 40, 30), "apply slot 1")) return 1;
        composite(&c, img);
        if (require(near(img, 50, 30, 220, 30, 30), "slot 0 not composited at its flipped rect")) return 1;
        if (require(near(img, 21, 11, 220, 30, 30) && near(img, 82, 56, 220, 30, 30), "slot 0 corners")) return 1;
        if (require(near(img, 18, 30, 51, 51, 51) && near(img, 50, 60, 51, 51, 51), "background outside slot 0")) return 1;
        if (require(near(img, 140, 65, 20, 40, 230) && near(img, 158, 78, 20, 40, 230), "slot 1 scaled into its rect")) return 1;
        if (require(near(img, 118, 65, 51, 51, 51) && near(img, 140, 48, 51, 51, 51), "background outside slot 1")) return 1;

        // Re-render into the same IOSurface and apply it again: the new pixels show.
        fill(red, 30, 200, 60);
        if (require(elisa_appkit_canvas_hosted_layer_apply(rootHandle, 0, (size_t)red, 20, 10, 64, 48), "re-apply slot 0")) return 1;
        composite(&c, img);
        if (require(near(img, 50, 30, 30, 200, 60), "same-surface update not shown")) return 1;
        if (require(root.sublayers.count == 2, "re-apply duplicated a layer")) return 1;

        // Move and resize (a panel resize), then swap to another surface.
        if (require(elisa_appkit_canvas_hosted_layer_apply(rootHandle, 0, (size_t)blue, 0, 0, 100, 100), "move slot 0")) return 1;
        composite(&c, img);
        if (require(near(img, 5, 95, 20, 40, 230) && near(img, 99, 0, 20, 40, 230), "moved slot 0")) return 1;

        // The layer retains the surface: the producer may release its reference.
        CFRelease(red);
        red = NULL;
        composite(&c, img);
        if (require(near(img, 140, 65, 20, 40, 230), "slot 1 lost after producer release")) return 1;

        // Remove restores the background; other sublayers are untouched.
        CALayer *foreign = [CALayer layer];
        [root addSublayer:foreign];
        if (require(elisa_appkit_canvas_hosted_layer_remove(rootHandle, 0), "remove slot 0")) return 1;
        if (require(elisa_appkit_canvas_hosted_layer_remove(rootHandle, 1), "remove slot 1")) return 1;
        if (require(!elisa_appkit_canvas_hosted_layer_remove(rootHandle, 1), "double remove")) return 1;
        // CARenderer does not treat a removed sublayer as damage, so render the
        // resulting tree from scratch with a fresh renderer (the window server
        // composites a live view's tree itself).
        c.renderer = [CARenderer rendererWithMTLTexture:c.target
            options:@{kCARendererMetalCommandQueue: c.queue}];
        c.renderer.layer = root;
        c.renderer.bounds = root.bounds;
        composite(&c, img);
        if (require(near(img, 50, 30, 51, 51, 51) && near(img, 140, 65, 51, 51, 51), "removed slots still shown")) return 1;
        if (require(root.sublayers.count == 1 && root.sublayers[0] == foreign, "remove touched a foreign layer")) return 1;
        CFRelease(blue);

        if (require(elisa_appkit_canvas_hosted_root(0) == 0, "root of null window")) return 1;
        if (require(elisa_appkit_canvas_backing_scale(0) == 1.0f, "scale of null window")) return 1;
    }
    printf("hosted surface: IOSurface slots composited, updated, moved and removed headlessly\n");
    return 0;
}
