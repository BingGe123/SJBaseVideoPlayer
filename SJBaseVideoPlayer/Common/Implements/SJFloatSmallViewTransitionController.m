//
//  SJFloatSmallViewTransitionController.m
//  SJVideoPlayer_Example
//
//  Created by BlueDancer on 2021/1/13.
//  Copyright © 2021 changsanjiang. All rights reserved.
//

#import "SJFloatSmallViewTransitionController.h"
#import <objc/message.h>
#import "UIView+SJBaseVideoPlayerExtended.h"
#import "NSObject+SJObserverHelper.h"

@interface SJFloatSmallViewContainerView : UIView
@end

@implementation SJFloatSmallViewContainerView
- (void)setX:(CGFloat)x {
    CGRect frame = self.frame;
    frame.origin.x = x;
    self.frame = frame;
}

- (CGFloat)x {
    return self.frame.origin.x;
}

- (void)setY:(CGFloat)y {
    CGRect frame = self.frame;
    frame.origin.y = y;
    self.frame = frame;
}

- (CGFloat)y {
    return self.frame.origin.y;
}

- (CGFloat)w {
    return self.frame.size.width;
}

- (CGFloat)h {
    return self.frame.size.height;
}
@end


@interface SJFloatSmallViewTransitionControllerObserver : NSObject<SJFloatSmallViewControllerObserverProtocol>
- (instancetype)initWithController:(id<SJFloatSmallViewController>)controller;
@end

@implementation SJFloatSmallViewTransitionControllerObserver
@synthesize appearStateDidChangeExeBlock = _appearStateDidChangeExeBlock;
@synthesize enabledControllerExeBlock = _enabledControllerExeBlock;
@synthesize controller = _controller;

- (instancetype)initWithController:(id<SJFloatSmallViewController>)controller {
    self = [super init];
    if ( self ) {
        _controller = controller;
        
        sjkvo_observe(controller, @"isAppeared", ^(id  _Nonnull target, NSDictionary<NSKeyValueChangeKey,id> * _Nullable change) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if ( self.appearStateDidChangeExeBlock )
                    self.appearStateDidChangeExeBlock(target);
            });
        });
        
        sjkvo_observe(controller, @"enabled", ^(id  _Nonnull target, NSDictionary<NSKeyValueChangeKey,id> * _Nullable change) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if ( self.enabledControllerExeBlock )
                    self.enabledControllerExeBlock(target);
            });
        });
    }
    return self;
}
@end

@interface UINavigationController (SJFloatSmallViewTransitionControllerExtended)
+ (void)SVTC_initialize;
- (UIViewController *)SVTC_popViewControllerAnimated:(BOOL)animated;
- (void)SVTC_pushViewController:(UIViewController *)viewController animated:(BOOL)animated;
- (void)SVTC_setViewControllers:(NSArray<UIViewController *> *)viewControllers animated:(BOOL)animated;
@end

@interface SJFloatSmallViewTransitionController ()<UIGestureRecognizerDelegate>
@property (nonatomic) BOOL isAppeared;
@property (nonatomic, strong, nullable) UINavigationController *navigationController;
@property (nonatomic, strong, nullable) UIViewController *playbackViewController;
@property (nonatomic, strong, readonly) UIPanGestureRecognizer *panGesture;
@property (nonatomic) CGRect from;
@end

@implementation SJFloatSmallViewTransitionController
@synthesize enabled = _enabled;
@synthesize slidable = _slidable;
@synthesize floatViewShouldAppear = _floatViewShouldAppear;
@synthesize singleTappedOnTheFloatViewExeBlock = _singleTappedOnTheFloatViewExeBlock;
@synthesize doubleTappedOnTheFloatViewExeBlock = _doubleTappedOnTheFloatViewExeBlock;
///// - target 为播放器呈现视图
///// - targetSuperview 为播放器视图
///// 当显示小浮窗时, 可以将target添加到小浮窗中
///// 当隐藏小浮窗时, 可以将target恢复到targetSuperview中
@synthesize target = _target;
@synthesize targetSuperview = _targetSuperview;
@synthesize floatView = _floatView;

+ (void)initialize {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [UINavigationController SVTC_initialize];
    });
}

- (instancetype)init {
    self = [super init];
    if ( self ) {
        _layoutInsets = UIEdgeInsetsMake(20, 12, 20, 12);
        _layoutPosition = SJFloatViewLayoutPositionBottomRight;
        _enabled = YES;
        self.singleTappedOnTheFloatViewExeBlock = ^(id<SJFloatSmallViewController>  _Nonnull controller) {
            SJFloatSmallViewTransitionController *transitionController = (id)controller;
            [transitionController resume];
        };
    }
    return self;
}

- (id<SJFloatSmallViewControllerObserverProtocol>)getObserver {
    return [[SJFloatSmallViewTransitionControllerObserver alloc] initWithController:self];
}

- (__kindof UIView *)floatView {
    if ( _floatView == nil ) {
        _floatView = [[SJFloatSmallViewContainerView alloc] initWithFrame:CGRectZero];
        [self _addGesturesToFloatView:_floatView];
    }
    return _floatView;
}

- (void)showFloatView {
    [self floatMode];
}

- (void)dismissFloatView {
    if ( !_enabled ) return;
    _playbackViewController = nil;
    _navigationController = nil;
    self.isAppeared = NO;
}

// - gestures -

- (void)_addGesturesToFloatView:(SJFloatSmallViewContainerView *)floatView {
    [floatView addGestureRecognizer:self.panGesture];
}

- (void)setSlidable:(BOOL)slidable {
    self.panGesture.enabled = slidable;
}
- (BOOL)slidable {
    return self.panGesture.enabled;
}

@synthesize panGesture = _panGesture;
- (UIPanGestureRecognizer *)panGesture {
    if ( _panGesture == nil ) {
        _panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(_handlePanGesture:)];
        _panGesture.delegate = self;
    }
    return _panGesture;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if ( [otherGestureRecognizer isKindOfClass:UIPanGestureRecognizer.class] ) {
        otherGestureRecognizer.state = UIGestureRecognizerStateCancelled;
        return YES;
    }
    return NO;
}

- (void)_handlePanGesture:(UIPanGestureRecognizer *)panGesture {
    SJFloatSmallViewContainerView *view = _floatView;
    UIView *superview = view.superview;
    CGPoint offset = [panGesture translationInView:superview];
    CGPoint center = view.center;
    view.center = CGPointMake(center.x + offset.x, center.y + offset.y);
    [panGesture setTranslation:CGPointZero inView:superview];
    
    switch ( panGesture.state ) {
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed: {
            [UIView animateWithDuration:0.4 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                UIEdgeInsets safeAreaInsets = UIEdgeInsetsZero;
                if (@available(iOS 11.0, *)) {
                    if ( !self.ignoreSafeAreaInsets ) safeAreaInsets = superview.safeAreaInsets;
                }

                CGFloat left = safeAreaInsets.left + self.layoutInsets.left;
                CGFloat right = superview.bounds.size.width - view.w - self.layoutInsets.right - safeAreaInsets.right;
                if ( view.x <= left ) {
                    [view setX:left];
                }
                else if ( view.x >= right ) {
                    [view setX:right];
                }
                
                CGFloat top = safeAreaInsets.top + self.layoutInsets.top;
                CGFloat bottom = superview.bounds.size.height - view.h - self.layoutInsets.bottom - safeAreaInsets.bottom;
                if ( view.y <= top ) {
                    [view setY:top];
                }
                else if ( view.y >= bottom ) {
                    [view setY:bottom];
                }
            } completion:nil];
        }
            break;
        default: break;
    }
}

#pragma mark -

- (BOOL)floatMode {
    if ( !_enabled )
        return NO;

    // 1 获取当前的vc
    // 2 转换到window中的位置
    // 3 退出`playbackViewController`
    // 4 设置转场动画
    
    if ( _floatViewShouldAppear && !_floatViewShouldAppear(self) )
        return NO;
    
    // 1.
    _playbackViewController = [_targetSuperview lookupResponderForClass:UIViewController.class];
    _navigationController = _playbackViewController.navigationController;
    UIWindow *window = UIApplication.sharedApplication.keyWindow;
    if ( _playbackViewController == nil || _navigationController == nil || window == nil )
        return NO;
      
    // 2.
    _from = [_targetSuperview convertRect:_targetSuperview.bounds toView:window];
    CGRect to = self.floatView.frame;
    _floatView.frame = _from;
    if ( _floatView.superview != window ) {
        // 首次显示, 将floatView添加到window并设置frame
        [window addSubview:_floatView];
        
        CGRect windowBounds = window.bounds;
        CGFloat windowW = windowBounds.size.width;
        CGFloat windowH = windowBounds.size.height;
        
        UIEdgeInsets safeAreaInsets = UIEdgeInsetsZero;
        if (@available(iOS 11.0, *)) {
            if ( !_ignoreSafeAreaInsets ) safeAreaInsets = window.safeAreaInsets;
        }

        //
        CGSize size = _layoutSize;
        CGFloat w = size.width;
        CGFloat h = size.height;
        CGFloat x = 0;
        CGFloat y = 0;
        
        if ( CGSizeEqualToSize(CGSizeZero, size) ) {
            CGFloat maxW = ceil(windowW * 0.48);
            w = maxW > 300.0 ? 300.0 : maxW;
            h = w * 9.0 / 16.0;
        }
        
        switch ( _layoutPosition ) {
            case SJFloatViewLayoutPositionTopLeft:
            case SJFloatViewLayoutPositionBottomLeft:
                x = safeAreaInsets.left + _layoutInsets.left;
                break;
            case SJFloatViewLayoutPositionTopRight:
            case SJFloatViewLayoutPositionBottomRight:
                x = windowW - w - _layoutInsets.right - safeAreaInsets.right;
                break;
        }
          
        switch ( _layoutPosition ) {
            case SJFloatViewLayoutPositionTopLeft:
            case SJFloatViewLayoutPositionTopRight:
                y = safeAreaInsets.top + _layoutInsets.top;
                break;
            case SJFloatViewLayoutPositionBottomLeft:
            case SJFloatViewLayoutPositionBottomRight:
                y = windowH - h - _layoutInsets.bottom - safeAreaInsets.bottom;
                break;
        }

        to = CGRectMake(x, y, w, h);
    }
     
    // 4.
    [self->_floatView addSubview:self->_target];
    self->_target.frame = self->_floatView.bounds;
    [self->_target layoutSubviews];
    [self->_target layoutIfNeeded];
    self->_floatView.hidden = NO;
    [UIView animateWithDuration:0.4 animations:^{
        self->_floatView.frame = to;

        self->_target.frame = self->_floatView.bounds;
        [self->_target layoutSubviews];
        [self->_target layoutIfNeeded];
    }];
    
    self.isAppeared = YES;
    return YES;
}

- (BOOL)resumeMode {
    if ( !_enabled )
        return NO;
    
    // 1. push`playbackController`
    // 2. 将播放器添加回去
    
    // 2.
    CGRect from = _floatView.frame;
    CGRect to = _from;
    [UIView animateWithDuration:0.4 animations:^{
        self->_floatView.frame = to;
        self->_target.frame = (CGRect){0, 0, to.size};
        [self->_target layoutSubviews];
        [self->_target layoutIfNeeded];
    } completion:^(BOOL finished) {
        self->_floatView.frame = from;
        self->_floatView.hidden = YES;
        [self->_targetSuperview addSubview:self->_target];
        self->_target.frame = self->_targetSuperview.bounds;
        [self->_target layoutSubviews];
        [self->_target layoutSubviews];
    }];
     
    _playbackViewController = nil;
    _navigationController = nil;
    self.isAppeared = NO;
    return YES;
}

- (void)resume {
    if ( _navigationController == nil || _playbackViewController == nil )
        return;
    
    NSInteger idx = [_navigationController.viewControllers indexOfObject:_playbackViewController];
    if ( idx != NSNotFound ) {
        NSRange range = NSMakeRange(0, idx + 1);
        [_navigationController setViewControllers:[_navigationController.viewControllers subarrayWithRange:range] animated:YES];
    }
    else {
        [_navigationController pushViewController:_playbackViewController animated:YES];
    }
}
@end

UIKIT_STATIC_INLINE SJFloatSmallViewTransitionController *_Nullable
SVTC_TransitionController(UIViewController *viewController) {
    return [viewController respondsToSelector:@selector(SVTC_floatSmallViewTransitionController)] ? viewController.SVTC_floatSmallViewTransitionController : nil;
}

@implementation UINavigationController (SJFloatSmallViewTransitionControllerExtended)
UIKIT_STATIC_INLINE void
SVTC_exchangeImplementation(Class cls, SEL originSel, SEL swizzledSel) {
    Method originalMethod = class_getInstanceMethod(cls, originSel);
    Method swizzledMethod = class_getInstanceMethod(cls, swizzledSel);
    if ( class_addMethod(cls, originSel, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod)) ) {
        class_replaceMethod(cls, swizzledSel, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod));
    }
    else {
        method_exchangeImplementations(originalMethod, swizzledMethod);
    }
}

+ (void)SVTC_initialize {
    Class cls = UINavigationController.class;
    SVTC_exchangeImplementation(cls, @selector(popViewControllerAnimated:), @selector(SVTC_popViewControllerAnimated:));
    SVTC_exchangeImplementation(cls, @selector(pushViewController:animated:), @selector(SVTC_pushViewController:animated:));
    SVTC_exchangeImplementation(cls, @selector(setViewControllers:animated:), @selector(SVTC_setViewControllers:animated:));
}

- (UIViewController *)SVTC_popViewControllerAnimated:(BOOL)animated {
    SJFloatSmallViewTransitionController *transitionController = SVTC_TransitionController(self.topViewController);
    if ( transitionController != nil ) {
        [transitionController floatMode];
        return [self SVTC_popViewControllerAnimated:animated];
    }
    else {
        UIViewController *vc = [self SVTC_popViewControllerAnimated:animated];
        UIViewController *topViewController = self.topViewController;
        SJFloatSmallViewTransitionController *transitionController = SVTC_TransitionController(topViewController);
        if ( transitionController != nil ) {
            [transitionController resumeMode];
        }
        return vc;
    }
}

- (void)SVTC_pushViewController:(UIViewController *)viewController animated:(BOOL)animated {
    SJFloatSmallViewTransitionController *transitionController = SVTC_TransitionController(viewController);
    if ( transitionController != nil ) {
        [self SVTC_pushViewController:viewController animated:animated];
        [transitionController resumeMode];
    }
    else {
        UIViewController *topViewController = self.topViewController;
        SJFloatSmallViewTransitionController *transitionController = SVTC_TransitionController(topViewController);
        if ( transitionController != nil ) {
            [transitionController floatMode];
        }
        [self SVTC_pushViewController:viewController animated:animated];
    }
}

- (void)SVTC_setViewControllers:(NSArray<UIViewController *> *)viewControllers animated:(BOOL)animated {
    SJFloatSmallViewTransitionController *transitionController = SVTC_TransitionController(self.topViewController);
    if ( transitionController != nil ) {
        if ( viewControllers.lastObject != self.topViewController )
            [transitionController floatMode];
    }
    else {
        SJFloatSmallViewTransitionController *transitionController = SVTC_TransitionController(viewControllers.lastObject);
        if ( transitionController != nil ) {
            [transitionController resumeMode];
        }
    }
    [self SVTC_setViewControllers:viewControllers animated:animated];
}
@end
