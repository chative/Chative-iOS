/*
 Created by Jean-Pierre Fourie
 Copyright (c) 2015-2017 emotality <jp@emotality.com>
 Website: https://www.emotality.com
 GitHub: https://github.com/apptality
 
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NON-INFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 THE SOFTWARE.
*/

#import "ATAppUpdater.h"

@implementation ATAppUpdater


#pragma mark - Init


+ (id)sharedUpdater
{
    static ATAppUpdater *sharedUpdater;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedUpdater = [[ATAppUpdater alloc] init];
    });
    return sharedUpdater;
}

- (id)init
{
    self = [super init];
    if (self) {
        self.alertTitle = @"New Version";
        self.alertMessage = @"Version %@ is available on the AppStore.";
        self.alertUpdateButtonTitle = @"Update";
        self.alertCancelButtonTitle = @"Not Now";
    }
    return self;
}


#pragma mark - Instance Methods


- (void)showUpdateWithForce
{
    BOOL hasConnection = [self hasConnection];
    if (!hasConnection) return;
    
    [self checkNewAppVersion:^(BOOL newVersion, NSString *version) {
        if (newVersion) [self alertUpdateForVersion:version withForce:YES];
    }];
}

- (void)showUpdateWithConfirmation
{
    BOOL hasConnection = [self hasConnection];
    if (!hasConnection) return;
    
    [self checkNewAppVersion:^(BOOL newVersion, NSString *version) {
        if (newVersion)
        {
            [self alertUpdateForVersion:version withForce:NO];
            
        }
    }];
}


#pragma mark - Private Methods


- (BOOL)hasConnection
{
    const char *host = "optillel.com";
    BOOL reachable;
    BOOL success;
    
    // Link SystemConfiguration.framework! <SystemConfiguration/SystemConfiguration.h>
    SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithName(NULL, host);
    SCNetworkReachabilityFlags flags;
    success = SCNetworkReachabilityGetFlags(reachability, &flags);
    reachable = success && (flags & kSCNetworkFlagsReachable) && !(flags & kSCNetworkFlagsConnectionRequired);
    CFRelease(reachability);
    return reachable;
}

NSString *appStoreURL = nil;

- (void)checkNewAppVersion:(void(^)(BOOL newVersion, NSString *version))completion
{
    NSDictionary *bundleInfo = [[NSBundle mainBundle] infoDictionary];
    NSString *bundleIdentifier = bundleInfo[@"CFBundleIdentifier"];
    NSString *currentVersion = bundleInfo[@"CFBundleShortVersionString"];
    NSURL *lookupURL = [NSURL URLWithString:@"https://Chative.optillel.com/version.json"];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^(void) {
        
        NSData *lookupResults = [NSData dataWithContentsOfURL:lookupURL];
        if (!lookupResults) {
            completion(NO, nil);
            return;
        }
        
        NSDictionary *jsonResults = [NSJSONSerialization JSONObjectWithData:lookupResults options:0 error:nil];
        
        dispatch_async(dispatch_get_main_queue(), ^(void) {
            NSUInteger resultCount = [jsonResults[@"resultCount"] integerValue];
            if (resultCount){
                NSDictionary *appDetails = [jsonResults[@"results"] firstObject];
                NSString *appItunesUrl = [appDetails[@"trackViewUrl"] stringByReplacingOccurrencesOfString:@"&uo=4" withString:@""];
                NSString *latestVersion = appDetails[@"version"];
                if ([latestVersion compare:currentVersion options:NSNumericSearch] == NSOrderedDescending) {
                    appStoreURL = appItunesUrl;
                    completion(YES, latestVersion);
                } else {
                    completion(NO, nil);
                }
            } else {
                completion(NO, nil);
            }
        });
    });
}

- (void)alertUpdateForVersion:(NSString *)version withForce:(BOOL)force
{
    NSString *alertMessage = [NSString stringWithFormat:self.alertMessage, version];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:self.alertTitle message:alertMessage preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *updateAction = [UIAlertAction actionWithTitle:self.alertUpdateButtonTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:appStoreURL]];
        if ([self.delegate respondsToSelector:@selector(appUpdaterUserDidLaunchAppStore)]) {
            [self.delegate appUpdaterUserDidLaunchAppStore];
        }
    }];
    [alert addAction:updateAction];
    
    if (!force) {
        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:self.alertCancelButtonTitle style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
            if ([self.delegate respondsToSelector:@selector(appUpdaterUserDidCancel)]) {
                [self.delegate appUpdaterUserDidCancel];
            }
        }];
        [alert addAction:cancelAction];
    }
    
    // 获取当前视图，将update窗口展示在前端。
    UIViewController *rootViewController = [UIApplication sharedApplication].keyWindow.rootViewController;
    UIViewController *currentVC = [self getCurrentVCFrom:rootViewController];
    [currentVC presentViewController:alert animated:YES completion:^{
        if ([self.delegate respondsToSelector:@selector(appUpdaterDidShowUpdateDialog)]) {
            [self.delegate appUpdaterDidShowUpdateDialog];
        }
    }];
}


- (UIViewController *)getCurrentVCFrom:(UIViewController *)rootVC
{
    UIViewController *currentVC;
    
    if ([rootVC presentedViewController]) {
        // 视图是被presented出来的
        
        rootVC = [rootVC presentedViewController];
    }
    
    if ([rootVC isKindOfClass:[UITabBarController class]]) {
        // 根视图为UITabBarController
        
        currentVC = [self getCurrentVCFrom:[(UITabBarController *)rootVC selectedViewController]];
        
    } else if ([rootVC isKindOfClass:[UINavigationController class]]){
        // 根视图为UINavigationController
        
        currentVC = [self getCurrentVCFrom:[(UINavigationController *)rootVC visibleViewController]];
        
    } else {
        // 根视图为非导航类
        
        currentVC = rootVC;
    }
    
    return currentVC;
}

@end
