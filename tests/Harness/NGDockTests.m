#import "NGHarness.h"
#import <objc/message.h>
#import "NGWallpaperBackdrop.h"

static UIView *NGMaterial(UIView *root, NSInteger style) {
    for (UIView *view in NGDescendants(root)) {
        NSString *name = NSStringFromClass(view.class);
        if (style == 0 && [name isEqualToString:@"NGClearDockView"]) return view;
        if (style == 1 && [view isKindOfClass:GLSGlassView.class]) return view;
    }
    return nil;
}
static NSUInteger NGMaterialCount(UIView *root) {
    NSUInteger count = 0;
    for (UIView *view in NGDescendants(root))
        if ([NSStringFromClass(view.class) isEqualToString:@"NGClearDockView"] || [view isKindOfClass:GLSGlassView.class]) count++;
    return count;
}
static NSDictionary *NGFrame(UIView *material, NSInteger style, NSString *path) {
    if (style == 0) return [NGTheseusProbe snapshot:material path:path];
    SEL selector = NSSelectorFromString(@"gls_surface");
    if (![material respondsToSelector:selector]) return @{@"ready": @NO, @"error": @"no original GLS surface"};
    id surface = ((id(*)(id,SEL))objc_msgSend)(material, selector);
    id<MTLTexture> texture = ((id(*)(id,SEL))objc_msgSend)(surface, NSSelectorFromString(@"outputTexture"));
    if (!texture) return @{@"ready": @NO, @"error": @"no actual rendered output"};
    NSUInteger row = ((texture.width*4 + 255)/256)*256, size = row*texture.height;
    id<MTLBuffer> buffer = [texture.device newBufferWithLength:size options:MTLResourceStorageModeShared];
    id<MTLCommandQueue> queue = [texture.device newCommandQueue]; id<MTLCommandBuffer> command = [queue commandBuffer];
    id<MTLBlitCommandEncoder> blit = [command blitCommandEncoder];
    [blit copyFromTexture:texture sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0)
               sourceSize:MTLSizeMake(texture.width,texture.height,1) toBuffer:buffer destinationOffset:0
      destinationBytesPerRow:row destinationBytesPerImage:size];
    [blit endEncoding]; [command commit]; [command waitUntilCompleted];
    uint64_t hash = 14695981039346656037ULL; const uint8_t *bytes = buffer.contents;
    for (NSUInteger y = 0; y < texture.height; y++) for (NSUInteger x = 0; x < texture.width*4; x++) hash = (hash ^ bytes[y*row+x])*1099511628211ULL;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo bitmap = texture.pixelFormat == MTLPixelFormatBGRA8Unorm ? kCGBitmapByteOrder32Little | (CGBitmapInfo)kCGImageAlphaPremultipliedFirst : (CGBitmapInfo)kCGImageAlphaPremultipliedLast;
    CGContextRef context = CGBitmapContextCreate(buffer.contents,texture.width,texture.height,8,row,space,bitmap);
    CGImageRef image = context ? CGBitmapContextCreateImage(context) : nil;
    NSData *png = image ? UIImagePNGRepresentation([UIImage imageWithCGImage:image]) : nil;
    BOOL wrote = png && [png writeToFile:path atomically:YES];
    if (image) CGImageRelease(image); if (context) CGContextRelease(context); CGColorSpaceRelease(space);
    return @{@"ready": @(command.status == MTLCommandBufferStatusCompleted), @"checksum": [NSString stringWithFormat:@"%llu",(unsigned long long)hash],
             @"width": @(texture.width), @"height": @(texture.height), @"wrotePNG": @(wrote), @"pixelFormat": @(texture.pixelFormat)};
}
static NSString *NGDockID(Class cls, NSInteger style, NSString *name) {
    return [NSString stringWithFormat:@"dock.%@.%@.%@", NSStringFromClass(cls), style == 0 ? @"theseusClear" : @"glassifyProminentClear", name];
}
static void NGCheckDockOptics(NGRecorder *r, SBDockView *dock, Class cls, NSInteger style, UIView *material) {
            [r check:material && NGMaterialCount(dock) == 1 name:NGDockID(cls,style,@"actual_original_material")
               evidence:@{@"class": material ? NSStringFromClass(material.class) : @"missing", @"count": @(NGMaterialCount(dock))}];
            if (!material) return;
            if (style == 0) {
                NSDictionary *config = [NGTheseusProbe inspectClear:material];
                [r check:[config[@"matchesOriginalClear"] boolValue] && [config[@"captureMethod"] isEqual:config[@"captureBackendExpected"]]
                       name:NGDockID(cls,style,@"exact_original_clear_optics") evidence:config];
                BOOL capsule = [config[@"continuousCapsule"] boolValue];
                CGFloat radius = [config[@"cornerRadius"] doubleValue];
                BOOL expectedCapsule = radius >= MIN(material.bounds.size.width,material.bounds.size.height)/2-0.5;
                [r check:capsule == expectedCapsule && radius > 0 && radius <= MIN(material.bounds.size.width,material.bounds.size.height)/2
                       name:NGDockID(cls,style,@"container_geometry_only") evidence:config];
                [r check:[config[@"rendererPresent"] boolValue] && ![config[@"fallbackActive"] boolValue] && [config[@"isRendering"] boolValue]
                       name:NGDockID(cls,style,@"actual_metal_backend_no_fallback") evidence:config];
            } else {
                GLSGlassView *glass = (GLSGlassView *)material;
                UIColor *expected = [UIColor.secondarySystemFillColor resolvedColorWithTraitCollection:glass.traitCollection];
                UIColor *actual = [glass.glassTintColor resolvedColorWithTraitCollection:glass.traitCollection];
                [r check:glass.style == GLSGlassStyleClear && [actual isEqual:expected] && glass.frost == GLSGlassFrostAutomatic &&
                         !glass.interactive && glass.glassEnabled && glass.blurLodBias == 0
                       name:NGDockID(cls,style,@"exact_prominent_clear_config")
                   evidence:@{@"style": @(glass.style), @"tint": actual.description ?: @"nil", @"expectedTint": expected.description,
                              @"frost": @(glass.frost), @"interactive": @(glass.interactive), @"blurLodBias": @(glass.blurLodBias)}];
            }
            BOOL noContent = ![material isKindOfClass:UIControl.class];
            for (UIView *view in NGDescendants(material))
                if ([view isKindOfClass:UILabel.class] || [view isKindOfClass:UISlider.class] || [view isKindOfClass:UIControl.class] ||
                    [NSStringFromClass(view.class) containsString:@"Slider"]) noContent = NO;
            [r check:noContent && !material.userInteractionEnabled && !material.isAccessibilityElement
                   name:NGDockID(cls,style,@"material_has_no_labels_sliders_or_touch_interception")
               evidence:@{@"subviewClasses": [[NGDescendants(material) valueForKey:@"class"] description],
                          @"interactive": @(material.userInteractionEnabled), @"accessibility": @(material.isAccessibilityElement)}];
            UIView *hit = [dock hitTest:[dock.icon convertPoint:CGPointMake(26,26) toView:dock] withEvent:nil];
            [r check:hit == dock.icon || [hit isDescendantOfView:dock.icon] name:NGDockID(cls,style,@"dock_icon_hit_test_preserved")
               evidence:@{@"hitClass": hit ? NSStringFromClass(hit.class) : @"nil"}];
}

// Simulates a wallpaper drawn by the render server: layer.render alone is blank,
// while the normal on-screen hierarchy has the pattern backing contents.
@interface NGServerWallpaperLayer : CALayer
@end
@implementation NGServerWallpaperLayer
- (void)renderInContext:(CGContextRef)context { }
@end
@interface NGFixtureWallpaperView : NGPatternView
@end
@implementation NGFixtureWallpaperView
+ (Class)layerClass { return NGServerWallpaperLayer.class; }
@end

static void NGAfter(NSTimeInterval seconds, dispatch_block_t action) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(seconds*NSEC_PER_SEC)),dispatch_get_main_queue(),action);
}
static void NGRunDockCase(NGRecorder *r, UIView *root, NSUInteger index, dispatch_block_t completion) {
    if (index>=4) { completion(); return; }
    Class cls=index<2 ? SBDockView.class : SBFloatingDockPlatterView.class;
    NSInteger style=index%2;
    NGFixtureWallpaperView *wallpaper=[[NGFixtureWallpaperView alloc] initWithFrame:root.bounds];
    wallpaper.userInteractionEnabled=NO; wallpaper.opaque=YES;
    [root insertSubview:wallpaper atIndex:0]; [wallpaper setNeedsDisplay];
    SBDockView *dock=[[cls alloc] initWithFrame:CGRectMake(15,366,root.bounds.size.width-30,84)];
    [root addSubview:dock];
    CGFloat alpha=dock.backgroundView.alpha; BOOL interaction=dock.backgroundView.userInteractionEnabled;
    NGWritePreferences(NO,YES,style);
    NGAfter(0.15, ^{
        NGRefreshFixtureDock(dock);
        NGAfter(0.9, ^{
            UIView *material=NGMaterial(dock,style);
            NGCheckDockOptics(r,dock,cls,style,material);
            NGWallpaperBackdrop *capture=nil;
            for (UIView *v in NGDescendants(dock)) if ([v isKindOfClass:NGWallpaperBackdrop.class]) capture=(id)v;
            [r check:capture.hasFrame && [capture.diagnostics[@"valid"] boolValue]
                 name:NGDockID(cls,style,@"wallpaper_only_valid_frame") evidence:capture.diagnostics];
            // Prove that this wallpaper cannot be obtained through layer.render.
            UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(16,16)];
            UIImage *empty=[renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
                [wallpaper.layer renderInContext:ctx.CGContext];
            }];
            [r check:empty!=nil && [wallpaper.layer isKindOfClass:NGServerWallpaperLayer.class]
                 name:NGDockID(cls,style,@"server_wallpaper_fixture") evidence:@{@"layerClass":NSStringFromClass(wallpaper.layer.class)}];
            NSString *firstName=[NGDockID(cls,style,@"gpu_a") stringByAppendingPathExtension:@"png"];
            NSDictionary *first=NGFrame(material,style,[r.output stringByAppendingPathComponent:firstName]);
            NSDictionary *firstCapture=[capture.diagnostics copy];
            wallpaper.phase++; [wallpaper setNeedsDisplay];
            NGAfter(0.15, ^{
                NGRefreshFixtureDock(dock);
                NGAfter(0.9, ^{
                    NSString *secondName=[NGDockID(cls,style,@"gpu_b") stringByAppendingPathExtension:@"png"];
                    NSDictionary *second=NGFrame(material,style,[r.output stringByAppendingPathComponent:secondName]);
                    BOOL pixels=[first[@"ready"] boolValue] && [second[@"ready"] boolValue] &&
                        [first[@"wrotePNG"] boolValue] && [second[@"wrotePNG"] boolValue] &&
                        ![first[@"checksum"] isEqual:second[@"checksum"]];
                    [r check:pixels name:NGDockID(cls,style,@"backdrop_change_changes_real_gpu_pixels")
                         evidence:@{@"before":first,@"after":second,@"files":@[firstName,secondName],
                                    @"wallpaperBefore":firstCapture ?: @{},@"wallpaperAfter":capture.diagnostics ?: @{}}];
                    [r capture:root name:NGDockID(cls,style,@"render")];
                    for (NSUInteger i=0;i<8;i++) NGRefreshFixtureDock(dock);
                    [r check:NGMaterialCount(dock)==1 name:NGDockID(cls,style,@"refresh_idempotent") evidence:@{@"count":@(NGMaterialCount(dock))}];
                    wallpaper.hidden=YES;
                    NGRefreshFixtureDock(dock);
                    NGAfter(0.1, ^{
                        [r check:fabs(dock.backgroundView.alpha-alpha)<0.001 && material.alpha==0
                             name:NGDockID(cls,style,@"invalid_wallpaper_retains_native_background")
                             evidence:@{@"backgroundAlpha":@(dock.backgroundView.alpha),@"glassAlpha":@(material.alpha),
                                        @"capture":capture.diagnostics ?: @{}}];
                        NGWritePreferences(NO,NO,0); NGRefreshFixtureDock(dock);
                        if (style==1) [r check:NGMaterialCount(dock)==0 && fabs(dock.backgroundView.alpha-alpha)<0.001 &&
                            dock.backgroundView.userInteractionEnabled==interaction
                            name:[NSString stringWithFormat:@"dock.%@.disable_restores_background",NSStringFromClass(cls)]
                            evidence:@{@"count":@(NGMaterialCount(dock)),@"alpha":@(dock.backgroundView.alpha),@"interaction":@(dock.backgroundView.userInteractionEnabled)}];
                        NGRemoveDock(dock); [dock removeFromSuperview]; [wallpaper removeFromSuperview];
                        NGRunDockCase(r,root,index+1,completion);
                    });
                });
            });
        });
    });
}
void NGRunDockTests(NGRecorder *r, UIView *root, dispatch_block_t completion) {
    NGRunDockCase(r,root,0,completion);
}
