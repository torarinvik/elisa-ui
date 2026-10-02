// Fragment of appkit_canvas_shim.m: hosted surfaces. An external renderer (the
// Elisa engine's viewport) draws into IOSurface-backed Metal textures; the canvas
// shows one per slot as a CALayer sublayer whose `contents` is that IOSurface, so
// compositing is zero-copy and never passes through drawRect.
//
// Elisa owns the policy (UiHostedSurface): which slot, which rect, whether a new
// surface or generation must be applied. This fragment only performs one layer
// write per call. Coordinates are view points in the canvas's own orientation;
// AppKit flips a layer-backed view's layer geometry to match `isFlipped`.
//
// Lifetime: the layer retains the IOSurface it shows, so the producer may drop
// or reallocate its ring after the host has applied a newer surface (or removed
// the slot). Not a translation unit of its own; see appkit_canvas_shim.m.

#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <IOSurface/IOSurface.h>

enum { ELISA_HOSTED_SURFACE_SLOTS = 16 };

// Hosted layers carry their slot, so the root's other sublayers are never touched.
@interface ElisaHostedSurfaceLayer : CALayer
@property(nonatomic) int elisaSlot;
@end
@implementation ElisaHostedSurfaceLayer
@end

static ElisaHostedSurfaceLayer *elisa_hosted_surface_find(CALayer *root, int slot) {
    for (CALayer *child in root.sublayers) {
        if (![child isKindOfClass:[ElisaHostedSurfaceLayer class]]) continue;
        ElisaHostedSurfaceLayer *hosted = (ElisaHostedSurfaceLayer *)child;
        if (hosted.elisaSlot == slot) return hosted;
    }
    return nil;
}

// Show `surface` (an IOSurfaceRef, borrowed) in `slot` over `root` at the rect.
// Returns 1 when applied, 0 for an invalid root, slot or surface.
int elisa_appkit_canvas_hosted_layer_apply(size_t rootHandle, int slot, size_t surface,
                                           float x, float y, float width, float height) {
    if (rootHandle == 0 || surface == 0) return 0;
    if (slot < 0 || slot >= ELISA_HOSTED_SURFACE_SLOTS) return 0;
    CALayer *root = (__bridge CALayer *)(void *)rootHandle;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    ElisaHostedSurfaceLayer *layer = elisa_hosted_surface_find(root, slot);
    if (layer == nil) {
        layer = [ElisaHostedSurfaceLayer layer];
        layer.elisaSlot = slot;
        layer.contentsGravity = kCAGravityResize;
        layer.opaque = YES;
        [root addSublayer:layer];
    }
    layer.frame = CGRectMake(x, y, width, height);
    id contents = (__bridge id)(IOSurfaceRef)(void *)surface;
    // Re-rendering the same IOSurface is not a property change, so clear the
    // contents first to make Core Animation read the new pixels.
    if (layer.contents == contents) layer.contents = nil;
    layer.contents = contents;
    [CATransaction commit];
    return 1;
}

// Remove the slot's layer (and its IOSurface retain). Returns 1 if one existed.
int elisa_appkit_canvas_hosted_layer_remove(size_t rootHandle, int slot) {
    if (rootHandle == 0 || slot < 0 || slot >= ELISA_HOSTED_SURFACE_SLOTS) return 0;
    CALayer *root = (__bridge CALayer *)(void *)rootHandle;
    ElisaHostedSurfaceLayer *layer = elisa_hosted_surface_find(root, slot);
    if (layer == nil) return 0;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [layer removeFromSuperlayer];
    [CATransaction commit];
    return 1;
}

// The canvas view's root layer (made layer-backed on first use), or 0.
size_t elisa_appkit_canvas_hosted_root(size_t windowHandle) {
    if (windowHandle == 0) return 0;
    NSWindow *window = (__bridge NSWindow *)(void *)windowHandle;
    NSView *view = window.contentView;
    if (view == nil) return 0;
    if (!view.wantsLayer) view.wantsLayer = YES;
    return (size_t)(__bridge void *)view.layer;
}

// Device pixels per point of the canvas window (1 when unknown).
float elisa_appkit_canvas_backing_scale(size_t windowHandle) {
    if (windowHandle == 0) return 1.0f;
    NSWindow *window = (__bridge NSWindow *)(void *)windowHandle;
    CGFloat scale = window.backingScaleFactor;
    return scale > 0 ? (float)scale : 1.0f;
}
