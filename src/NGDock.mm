#import "Bridge.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <Glassify/GLSGlassView.h>
#import "GLSGlassViewInternal.h"
#import "GLSBackdrop.h"
#include <initializer_list>

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
    for (const char *name : {"_backgroundView", "_backgroundMaterialView"}) {
        Ivar ivar = class_getInstanceVariable(dock.class,name);
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
@property(nonatomic) CGFloat backgroundAlpha;
@property(nonatomic) NSInteger style;
@property(nonatomic) BOOL ready;
@property(nonatomic,strong) NSTimer *timer;
@end
@implementation NGDockBinding
@end

static void NGDockRestore(NGDockBinding *binding) {
    if (!binding) return;
    [binding.timer invalidate]; binding.timer = nil;
    [GLSBackdrop unregisterGlassView:binding.dock];
    [binding.glass removeFromSuperview];
    binding.background.alpha = binding.backgroundAlpha;
}

void NGRemoveDock(UIView *dock) {
    NGDockBinding *binding = objc_getAssociatedObject(dock,&kNGDockBindingKey);
    NGDockRestore(binding);
    objc_setAssociatedObject(dock,&kNGDockBindingKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void NGDockMarkReady(NGDockBinding *binding) {
    if (!binding || !binding.dock.window || !NGDockEnabled() || binding.style != NGDockStyle()) return;
    binding.ready = YES;
    binding.background.alpha = 0;
    binding.glass.alpha = binding.backgroundAlpha;
}

static UIView *NGWallpaperSource(UIView *root, UIView *dock) {
    // A separate wallpaper subtree avoids capturing either the dock icons or
    // this plug-in's own background, and never changes icon layout/appearance.
    if (!root || root == dock || root.hidden || root.alpha < 0.01) return nil;
    NSString *name = NSStringFromClass(root.class);
    if ([name containsString:@"Wallpaper"] && root.bounds.size.width > 100 && root.bounds.size.height > 100) return root;
    for (UIView *child in root.subviews) {
        UIView *found = NGWallpaperSource(child,dock); if (found) return found;
    }
    return nil;
}

static UIView *NGDockSource(UIView *dock) {
#ifdef NG_TESTING
    return dock.window.rootViewController.view ?: dock.window;
#endif
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            UIView *wallpaper = NGWallpaperSource(window.rootViewController.view ?: window,dock);
            if (wallpaper) return wallpaper;
        }
    }
    return dock.window.rootViewController.view ?: dock.window;
}

void NGRefreshDock(UIView *dock) {
    if (!NSThread.isMainThread || ![dock isKindOfClass:UIView.class]) return;
    [NGSeenDocks() addObject:dock];
    if (!NGDockEnabled() || !dock.window) { NGRemoveDock(dock); return; }
    UIView *background = NGDockBackground(dock);
    if (!background.superview || ![background isDescendantOfView:dock] || CGRectIsEmpty(background.bounds)) return;
    NGDockBinding *binding = objc_getAssociatedObject(dock,&kNGDockBindingKey);
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
            __weak NGDockBinding *weak = binding;
            [(id<NGGlassComponent>)binding.glass setOnReady:^{ NGDockMarkReady(weak); }];
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
        [background.superview insertSubview:binding.glass aboveSubview:background];
        __weak NGDockBinding *weak = binding;
        binding.timer = [NSTimer timerWithTimeInterval:1.0/15.0 repeats:YES block:^(NSTimer *timer) {
            NGDockBinding *b = weak;
            UIView *host = b.dock;
            if (!b || !host || !host.window) { [timer invalidate]; return; }
            if (!NGDockEnabled() || b.style != NGDockStyle()) { NGRefreshDock(host); return; }
            BOOL visible = !host.hidden && !b.background.hidden;
            for (UIView *p = host.superview; p && visible; p = p.superview) visible = !p.hidden && p.alpha > 0.01;
            if (b.style == 0) {
                id<NGGlassComponent> component = (id)b.glass;
                [component setRenderingActive:visible];
                if (visible) [component invalidateBackdrop];
            } else if (visible) {
                GLSGlassView *component = (GLSGlassView *)b.glass;
                [component setNeedsBackdropUpdate];
                if ([component gls_surface].outputTexture) NGDockMarkReady(b);
            }
        }];
        [NSRunLoop.mainRunLoop addTimer:binding.timer forMode:NSRunLoopCommonModes];
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
    UIView *source = NGDockSource(dock);
    glass.hidden = background.hidden;
    if (style == 0) {
        [(id<NGGlassComponent>)glass configureWithRadius:radius source:source excluded:@[dock]];
        [(id<NGGlassComponent>)glass setRenderingActive:!dock.hidden && !background.hidden];
    } else {
        GLSGlassView *g = (GLSGlassView *)glass;
        g.cornerRadius = radius;
        g.backdropSourceView = source;
        // Glassify's own snapshot registry excludes the entire icon subtree.
        [GLSBackdrop registerGlassView:dock];
        [g setNeedsBackdropUpdate];
        [g layoutIfNeeded];
        if ([g gls_surface].outputTexture) NGDockMarkReady(binding);
    }
    if (binding.ready) { background.alpha = 0; glass.alpha = binding.backgroundAlpha; }
}

void NGRefreshDocks(void) {
    for (UIView *dock in NGSeenDocks().allObjects) NGRefreshDock(dock);
}
