#import "Bridge.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <Glassify/GLSGlassView.h>
#import <Metal/Metal.h>
#import "NGWallpaperBackdrop.h"

// The exact Objective-C accessors from the original GLSGlassSurface header.
@protocol NGDockSurface <NSObject>
@property(nonatomic) BOOL keepsOutput;
@property(nonatomic,readonly) id<MTLTexture> outputTexture;
@end
@interface GLSGlassView (NGDockCapture)
- (id<NGDockSurface>)gls_surface;
@end

static char kNGDockBindingKey;
static NSHashTable<UIView *> *NGSeenDocks(void) {
    static NSHashTable *seen; static dispatch_once_t once;
    dispatch_once(&once, ^{ seen = [NSHashTable weakObjectsHashTable]; }); return seen;
}

static UIView *NGDockBackground(UIView *dock) {
    SEL getter = NSSelectorFromString(@"backgroundView");
    if ([dock respondsToSelector:getter]) {
        NSMethodSignature *signature = [dock methodSignatureForSelector:getter];
        if (signature.numberOfArguments == 2 && signature.methodReturnType[0] == '@') {
            id object = ((id(*)(id,SEL))objc_msgSend)(dock,getter);
            if ([object isKindOfClass:UIView.class] && object != dock) return object;
        }
    }
    for (NSString *name in @[@"_backgroundView", @"_backgroundMaterialView"]) {
        Ivar ivar = class_getInstanceVariable(dock.class,name.UTF8String);
        if (ivar && ivar_getTypeEncoding(ivar)[0] == '@') {
            id object = object_getIvar(dock,ivar);
            if ([object isKindOfClass:UIView.class] && object != dock) return object;
        }
    }
    return nil;
}

@interface NGDockBinding : NSObject
@property(nonatomic,weak) UIView *dock;
@property(nonatomic,weak) UIView *background;
@property(nonatomic,strong) UIView *glass;
@property(nonatomic,strong) NGWallpaperBackdrop *wallpaper;
@property(nonatomic) CGFloat radius;
@property(nonatomic) CGFloat backgroundAlpha;
@property(nonatomic) NSInteger style;
@property(nonatomic) BOOL ready;
@property(nonatomic) BOOL updating;
@property(nonatomic,strong) NSTimer *timer;
@end
@implementation NGDockBinding
@end

static void NGDockRestore(NGDockBinding *binding) {
    if (!binding) return;
    [binding.timer invalidate]; binding.timer = nil;
    [binding.glass removeFromSuperview];
    [binding.wallpaper removeFromSuperview]; binding.wallpaper=nil;
    binding.background.alpha = binding.backgroundAlpha;
}

void NGRemoveDock(UIView *dock) {
    NGDockBinding *binding = objc_getAssociatedObject(dock,&kNGDockBindingKey);
    NGDockRestore(binding);
    objc_setAssociatedObject(dock,&kNGDockBindingKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void NGDockMarkReady(NGDockBinding *binding) {
    if (!binding || !binding.dock.window || !NGDockEnabled() || binding.style != NGDockStyle()) return;
    if (objc_getAssociatedObject(binding.dock,&kNGDockBindingKey) != binding) return;
    if (binding.style==0 && ![(id<NGStaticDockComponent>)binding.glass hasStaticImage]) return;
    if (binding.style==1 && !binding.wallpaper.hasFrame) return;
    if (!binding.ready) {
        binding.ready = YES;
        [binding.background.superview insertSubview:binding.glass aboveSubview:binding.background];
    }
    binding.background.alpha = 0;
    binding.glass.alpha = binding.backgroundAlpha;
}

static void NGDockUpdateBackdrop(NGDockBinding *binding, BOOL force) {
    if (!binding || binding.updating || binding.style==0) return;
    binding.updating=YES;
    @try {
    UIView *dock=binding.dock, *background=binding.background;
    BOOL visible=dock.window && !dock.hidden && !background.hidden;
    for (UIView *p=dock.superview;p && visible;p=p.superview) visible=!p.hidden && p.alpha>0.01;
    BOOL valid=visible && [binding.wallpaper updateForDock:dock background:background force:force];
    if (!valid) {
        binding.ready=NO;
        binding.glass.alpha=0;
        background.alpha=binding.backgroundAlpha;
        [background.superview insertSubview:binding.glass belowSubview:background];
        return;
    }
    binding.glass.alpha=binding.backgroundAlpha;
    if (!binding.ready) [background.superview insertSubview:binding.glass belowSubview:background];
        GLSGlassView *glass=(GLSGlassView *)binding.glass;
        glass.cornerRadius=binding.radius;
        if (glass.backdropSourceView!=binding.wallpaper) glass.backdropSourceView=binding.wallpaper;
        [glass setNeedsBackdropUpdate];
        [glass layoutIfNeeded];
        if ([glass gls_surface].outputTexture) NGDockMarkReady(binding);
    } @finally { binding.updating=NO; }
}

void NGRefreshDock(UIView *dock) {
    if (!NSThread.isMainThread || ![dock isKindOfClass:UIView.class]) return;
    [NGSeenDocks() addObject:dock];
    if (!NGDockEnabled() || !dock.window) { NGRemoveDock(dock); return; }
    UIView *background = NGDockBackground(dock);
    if (!background.superview || ![background isDescendantOfView:dock] || CGRectIsEmpty(background.bounds)) return;
    NGDockBinding *binding = objc_getAssociatedObject(dock,&kNGDockBindingKey);
    if (binding.updating) return;
    NSInteger style = NGDockStyle();
    if (binding && (binding.background != background || binding.style != style)) { NGRemoveDock(dock); binding = nil; }
    if (!binding) {
        if (!NGBundleResources()) return;
        binding = [NGDockBinding new]; binding.dock = dock; binding.background = background;
        binding.backgroundAlpha = background.alpha; binding.style = style;
        CGRect frame = [background convertRect:background.bounds toView:background.superview];
        if (style == 0) {
            Class cls = NSClassFromString(@"NGClearDockView"); if (!cls) return;
            binding.glass = [[cls alloc] initWithFrame:frame];
        } else {
            GLSGlassView *glass = [[GLSGlassView alloc] initWithFrame:frame];
            // Exact background configuration of the original Prominent Clear button.
            glass.style = GLSGlassStyleClear;
            glass.glassTintColor = UIColor.secondarySystemFillColor;
            glass.contentVibrancy = YES;
            glass.contentVibrancyStyle = GLSContentVibrancyStyleControls;
            glass.interactive = NO;
            glass.tracksBackdropMotion = NO;
            [glass gls_surface].keepsOutput = YES;
            binding.glass = glass;
        }
        binding.glass.accessibilityIdentifier = @"NGDockGlass";
        binding.glass.isAccessibilityElement = NO;
        binding.glass.userInteractionEnabled = NO;
        objc_setAssociatedObject(dock,&kNGDockBindingKey,binding,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (style==1) {
        binding.wallpaper=[[NGWallpaperBackdrop alloc] initWithFrame:CGRectZero];
        [background.superview insertSubview:binding.wallpaper belowSubview:background];
        binding.glass.alpha=0;
        [background.superview insertSubview:binding.glass aboveSubview:background];
        __weak NGDockBinding *weak = binding;
        binding.timer = [NSTimer timerWithTimeInterval:1.0/15.0 repeats:YES block:^(NSTimer *timer) {
            NGDockBinding *b = weak;
            UIView *host = b.dock;
            if (!b || !host || !host.window) { [timer invalidate]; return; }
            if (!NGDockEnabled() || b.style != NGDockStyle()) { NGRefreshDock(host); return; }
            NGDockUpdateBackdrop(b,NO);
        }];
        [NSRunLoop.mainRunLoop addTimer:binding.timer forMode:NSRunLoopCommonModes];
        }
    }
    UIView *glass = binding.glass;
    if (glass.superview != background.superview) { [glass removeFromSuperview]; [background.superview insertSubview:glass aboveSubview:background]; }
    glass.frame = [background convertRect:background.bounds toView:background.superview];
    CGFloat radius = background.layer.cornerRadius;
    if (radius <= 0) {
        for (UIView *child in background.subviews) radius = MAX(radius,child.layer.cornerRadius);
    }
    if (radius <= 0) radius = MIN(CGRectGetWidth(background.bounds),CGRectGetHeight(background.bounds))/2;
    radius = MIN(radius,MIN(CGRectGetWidth(background.bounds),CGRectGetHeight(background.bounds))/2);
    binding.radius=radius;
    glass.hidden=background.hidden;
    if (style==0) {
        [(id<NGStaticDockComponent>)glass setStaticRadius:radius];
        NGDockMarkReady(binding);
        return; // Static image path: no wallpaper, timer, renderer or snapshot.
    }
    if (binding.wallpaper.superview!=background.superview) {
        [binding.wallpaper removeFromSuperview];
        [background.superview insertSubview:binding.wallpaper belowSubview:background];
    }
    NGDockUpdateBackdrop(binding,YES);
    if (binding.ready && binding.wallpaper.hasFrame) { background.alpha=0; glass.alpha=binding.backgroundAlpha; }
}

void NGRefreshDocks(void) {
    for (UIView *dock in NGSeenDocks().allObjects) NGRefreshDock(dock);
}
