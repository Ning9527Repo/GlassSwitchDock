#import "NGWallpaperBackdrop.h"
#import <QuartzCore/QuartzCore.h>

@interface NGWallpaperBitmapLayer : CALayer
@property(nonatomic,strong) UIImage *bitmap;
@end
@implementation NGWallpaperBitmapLayer
- (void)renderInContext:(CGContextRef)context {
    // Both original engines call this method. No screen or glass is read here.
    if (!self.bitmap) return;
    UIGraphicsPushContext(context);
    [self.bitmap drawInRect:self.bounds];
    UIGraphicsPopContext();
}
@end

static void NGCollectWallpaperViews(UIView *view, UIView *dock, NSMutableArray<UIView *> *result) {
    if (!view || view == dock || view.hidden || view.alpha <= 0.01 || [view isKindOfClass:NGWallpaperBackdrop.class]) return;
    BOOL containsDock = [dock isDescendantOfView:view];
    NSString *name = NSStringFromClass(view.class);
    if (!containsDock && [name containsString:@"Wallpaper"] && view.bounds.size.width > 100 && view.bounds.size.height > 100)
        [result addObject:view];
    for (UIView *child in view.subviews) NGCollectWallpaperViews(child,dock,result);
}

static NSDictionary *NGInspectWallpaperImage(UIImage *image) {
    uint8_t pixels[16*8*4] = {0};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels,16,8,8,16*4,space,kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!context || !image.CGImage) { if (context) CGContextRelease(context); return @{@"valid":@NO}; }
    CGContextDrawImage(context,CGRectMake(0,0,16,8),image.CGImage); CGContextRelease(context);
    NSUInteger opaque=0, lit=0; uint64_t checksum=14695981039346656037ULL;
    for (NSUInteger i=0;i<sizeof(pixels);i++) checksum=(checksum^pixels[i])*1099511628211ULL;
    for (NSUInteger i=0;i<128;i++) {
        if (pixels[i*4+3] >= 240) opaque++;
        if (MAX(MAX(pixels[i*4],pixels[i*4+1]),pixels[i*4+2]) > 4) lit++;
    }
    return @{@"valid":@(opaque>=120 && lit>=8),@"opaqueSamples":@(opaque),@"litSamples":@(lit),
             @"checksum":[NSString stringWithFormat:@"%llu",(unsigned long long)checksum]};
}

@implementation NGWallpaperBackdrop {
    BOOL _hasFrame;
    NSUInteger _generation;
    NSDictionary *_diagnostics;
    CFTimeInterval _lastCapture;
    __weak UIWindow *_captureWindow;
    CGRect _lastScreenRect;
}
+ (Class)layerClass { return NGWallpaperBitmapLayer.class; }
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self=[super initWithFrame:frame])) {
        self.hidden=YES; self.userInteractionEnabled=NO; self.isAccessibilityElement=NO;
        self.backgroundColor=UIColor.clearColor; self.opaque=NO;
    }
    return self;
}
- (BOOL)hasFrame { return _hasFrame; }
- (NSUInteger)generation { return _generation; }
- (NSDictionary *)diagnostics { return _diagnostics ?: @{@"valid":@NO,@"reason":@"no wallpaper frame"}; }
- (BOOL)updateForDock:(UIView *)dock background:(UIView *)background force:(BOOL)force {
    UIWindow *window=dock.window;
    if (!window || !self.superview) { _hasFrame=NO; return NO; }
    CGRect onScreen=[background convertRect:background.bounds toView:window];
    // Supply the original shaders with margin for refraction; geometry remains system-owned.
    CGRect capture=CGRectIntersection(CGRectInset(onScreen,-96,-96),window.bounds);
    if (CGRectIsEmpty(capture) || CGRectIsNull(capture)) { _hasFrame=NO; return NO; }
    self.frame=[window convertRect:capture toView:self.superview];
    BOOL geometryChanged=window!=_captureWindow || !CGRectEqualToRect(capture,_lastScreenRect);
    if (!force && !geometryChanged && CACurrentMediaTime()-_lastCapture<0.25) return _hasFrame;
    _lastCapture=CACurrentMediaTime(); _captureWindow=window; _lastScreenRect=capture;
    NSMutableOrderedSet<UIWindow *> *windows=[NSMutableOrderedSet orderedSetWithObject:window];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if ([scene isKindOfClass:UIWindowScene.class]) [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
    [windows addObjectsFromArray:UIApplication.sharedApplication.windows];
    NSMutableArray<UIView *> *candidates=[NSMutableArray array];
    for (UIWindow *candidate in windows) {
        if (candidate.hidden || candidate.alpha<=0.01 || candidate.screen!=window.screen) continue;
        NGCollectWallpaperViews(candidate,dock,candidates);
    }
    for (UIView *source in candidates) {
        CGRect rect=[window convertRect:capture toView:source];
        CGRect visible=CGRectIntersection(rect,source.bounds);
        if (CGRectIsNull(visible) || visible.size.width*visible.size.height < rect.size.width*rect.size.height*0.98) continue;
        UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat defaultFormat];
        format.opaque=NO; format.scale=window.screen.scale;
        UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:capture.size format:format];
        __block BOOL drew=NO;
        UIImage *image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            CGContextScaleCTM(ctx.CGContext,capture.size.width/rect.size.width,capture.size.height/rect.size.height);
            CGContextTranslateCTM(ctx.CGContext,-rect.origin.x,-rect.origin.y);
            // Wallpaper subtree only: drawHierarchy includes render-server wallpaper layers.
            // Never capture a root containing the Dock, so glass cannot feed back into itself.
            drew=[source drawViewHierarchyInRect:source.bounds afterScreenUpdates:NO];
        }];
        NSDictionary *inspection=NGInspectWallpaperImage(image);
        if (!drew || ![inspection[@"valid"] boolValue]) continue;
        [CATransaction begin]; [CATransaction setDisableActions:YES];
        ((NGWallpaperBitmapLayer *)self.layer).bitmap=image;
        [CATransaction commit];
        _generation++; _hasFrame=YES;
        NSMutableDictionary *details=[inspection mutableCopy]; details[@"sourceClass"]=NSStringFromClass(source.class);
        details[@"captureRect"]=NSStringFromCGRect(capture); details[@"generation"]=@(_generation);
        details[@"method"]=@"wallpaper-only UIKit hierarchy bitmap"; _diagnostics=details;
        return YES;
    }
    _hasFrame=NO;
    _diagnostics=@{@"valid":@NO,@"reason":@"No opaque wallpaper-only snapshot; native background retained",@"candidateCount":@(candidates.count)};
    return NO;
}
@end
