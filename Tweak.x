#import "../YTVideoOverlay/Header.h"
#import "../YTVideoOverlay/Init.x"
#import <YouTubeHeader/YTColor.h>
#import <YouTubeHeader/YTMainAppVideoPlayerOverlayViewController.h>
#import <YouTubeHeader/YTMainAppVideoPlayerOverlayView.h>
#import <YouTubeHeader/YTMainAppControlsOverlayView.h>
#import <YouTubeHeader/YTInlinePlayerBarContainerView.h>
#import <YouTubeHeader/YTPlayerViewController.h>
#import <YouTubeHeader/QTMIcon.h>
#import <YouTubeHeader/GOOHUDManagerInternal.h>

#define TweakKey @"YouLoop"
#define LoopStatusKey @"YouLoopStatus"

@interface YTMainAppVideoPlayerOverlayViewController (YouLoop)
@property (nonatomic, assign) YTPlayerViewController *parentViewController; // for accessing YTPlayerViewController
@end

@interface YTMainAppVideoPlayerOverlayView (YouLoop)
@property (nonatomic, weak, readwrite) YTMainAppVideoPlayerOverlayViewController *delegate;
@end

@interface YTPlayerViewController (YouLoop)
- (void)didPressYouLoop; // contains actual logic for enabling/disabling loop
@end

@interface YTAutoplayAutonavController : NSObject
- (NSInteger)loopMode; // for reading loop state
- (void)setLoopMode:(NSInteger)loopMode; // for setting loop state
@end

@interface YTMainAppControlsOverlayView (YouLoop)
- (void)didPressYouLoop:(id)arg; // for custom button press
@end

// For accessing YTPlayerViewController
@interface YTInlinePlayerBarController : NSObject
@end

@interface YTInlinePlayerBarContainerView (YouLoop)
- (void)didPressYouLoop:(id)arg; // for custom button press
@end

@interface YTColor (YouLoop)
+ (UIColor *)lightRed; // for tinting the loop button when enabled
@end

// Retrieves the bundle for the tweak
NSBundle *YouLoopBundle() {
    static NSBundle *bundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *tweakBundlePath = [[NSBundle mainBundle] pathForResource:TweakKey ofType:@"bundle"];
        if (tweakBundlePath)
            bundle = [NSBundle bundleWithPath:tweakBundlePath];
        else
            bundle = [NSBundle bundleWithPath:[NSString stringWithFormat:PS_ROOT_PATH_NS(@"/Library/Application Support/%@.bundle"), TweakKey]];
    });
    return bundle;
}

static NSBundle *tweakBundle = nil;

static BOOL shouldLoop() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:LoopStatusKey];
}

// Get the image for the loop button and set the button color on the given state
static UIImage *loopIcon() {
    UIColor *tintColor = shouldLoop() ? [%c(YTColor) lightRed] : [%c(YTColor) white1];
    UIImage *base = [UIImage imageNamed:@"LoopIcon@3" inBundle:YouLoopBundle() compatibleWithTraitCollection:nil];
    return [%c(QTMIcon) tintImage:base color:tintColor];
}

%group Main
%hook YTPlayerViewController
// New method to enable looping on the current video, also stores state
// for all future videos
%new
- (void)didPressYouLoop {
    id mainAppController = self.activeVideoPlayerOverlay;
    // Check if type is YTMainAppVideoPlayerOverlayViewController
    if ([mainAppController isKindOfClass:objc_getClass("YTMainAppVideoPlayerOverlayViewController")]) {
        // Get the autoplay navigation controller
        YTMainAppVideoPlayerOverlayViewController *playerOverlay = (YTMainAppVideoPlayerOverlayViewController *)mainAppController;
        YTAutoplayAutonavController *autoplayController = (YTAutoplayAutonavController *)[playerOverlay valueForKey:@"_autonavController"];
        // Set new loop status
        BOOL isLoopEnabled = !shouldLoop();
        // Update the key for later use
        [[NSUserDefaults standardUserDefaults] setBool:isLoopEnabled forKey:LoopStatusKey];
        // Set the loop mode to the opposite of the current state
        [autoplayController setLoopMode:isLoopEnabled ? 2 : 0];
        // Display snackbar
        [[%c(GOOHUDManagerInternal) sharedInstance] showMessageMainThread:[%c(YTHUDMessage) messageWithText:LOC(isLoopEnabled ? @"LOOP_ENABLED" : @"LOOP_DISABLED")]];
    }
}
%end

%hook YTAutoplayAutonavController
// Modify the initializer to set the loop mode to the user's preference
- (id)initWithParentResponder:(id)arg1 {
    self = %orig;
    if (self && shouldLoop()) {
        [self setLoopMode:2];
    }
    return self;
}
// Modify the setter to always follow the user's preference. This breaks normal functionality
- (void)setLoopMode:(NSInteger)arg1 {
    if (!shouldLoop()) {
        %orig;
        return;
    }
    %orig(2);
}
%end
%end

/**
  * Adds a button to the top area in the video player overlay
  */
%group Top
%hook YTMainAppControlsOverlayView

- (UIImage *)buttonImage:(NSString *)tweakId {
    return [tweakId isEqualToString:TweakKey] ? loopIcon() : %orig;
}

// Custom method to handle the button press
%new(v@:@)
- (void)didPressYouLoop:(id)arg {
    // Call our custom method in the YTPlayerViewController class
    YTMainAppVideoPlayerOverlayView *mainOverlayView = (YTMainAppVideoPlayerOverlayView *)self.superview;
    YTMainAppVideoPlayerOverlayViewController *mainOverlayController = (YTMainAppVideoPlayerOverlayViewController *)mainOverlayView.delegate;
    YTPlayerViewController *playerViewController = mainOverlayController.parentViewController;
    if (playerViewController) {
        [playerViewController didPressYouLoop];
    }
    // Update button color
    [self.overlayButtons[TweakKey] setImage:loopIcon() forState:UIControlStateNormal];
}

%end
%end

/**
  * Adds a button to the bottom area next to the fullscreen button
  */
%group Bottom
%hook YTInlinePlayerBarContainerView

- (UIImage *)buttonImage:(NSString *)tweakId {
    return [tweakId isEqualToString:TweakKey] ? loopIcon() : %orig;
}

// Custom method to handle the button press
%new(v@:@)
- (void)didPressYouLoop:(id)arg {
    // Navigate to the YTPlayerViewController class from here
    YTInlinePlayerBarController *delegate = self.delegate; // for @property
    YTMainAppVideoPlayerOverlayViewController *_delegate = [delegate valueForKey:@"_delegate"]; // for ivars
    YTPlayerViewController *parentViewController = _delegate.parentViewController;
    // Call our custom method in the YTPlayerViewController class
    if (parentViewController) {
        [parentViewController didPressYouLoop];
    }
    // Update button color
    [self.overlayButtons[TweakKey] setImage:loopIcon() forState:UIControlStateNormal];
}

%end
%end

%ctor {
    tweakBundle = YouLoopBundle();
    // Setup as defined in the example from YTVideoOverlay
    initYTVideoOverlay(TweakKey, @{
        AccessibilityLabelKey: @"Toggle Loop",
        SelectorKey: @"didPressYouLoop:"
    });
    %init(Main);
    %init(Top);
    %init(Bottom);
}