#import <UIKit/UIKit.h>
#import "__PREFIX__Config.h"
#import "__PREFIX__Private.h"

// This sample matches the default SpringBoard filter. Replace both together.
%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    if (![[__PREFIX__Config __SYMBOL___shared] __SYMBOL___isEnabled]) {
        return;
    }
    // Add the plugin's launch behavior here.
}

%end

%ctor {
    @autoreleasepool {
        // Readers load a snapshot; they never write default preferences.
        [__PREFIX__Config __SYMBOL___shared];
    }
}
