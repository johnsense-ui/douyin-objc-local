//
//  AppDelegate.m
//  Douyin
//
//  Created by Qiao Shi on 2018/7/30.
//  Copyright © 2018年 Qiao Shi. All rights reserved.
//

#import <Photos/Photos.h>
#import "AppDelegate.h"
#import "UserHomePageController.h"
#import "AwemeListController.h"
#import "NetworkHelper.h"
#import "WebSocketManager.h"
#import "AVPlayerManager.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    _window = [[UIWindow alloc]initWithFrame:[[UIScreen mainScreen] bounds]];
    // 首屏 = 推荐流：先拉一页数据再落地，失败则回退到个人主页
    UIViewController *splash = [UIViewController new];
    splash.view.backgroundColor = [UIColor blackColor];
    _window.rootViewController = splash;
    __weak __typeof(self) wself = self;
    AwemeListRequest *feedReq = [AwemeListRequest new];
    feedReq.page = 1;
    feedReq.size = 10;
    feedReq.uid = @"__feed__";
    [NetworkHelper getWithUrlPath:FindAwemePostByPagePath request:feedReq success:^(id data) {
        AwemeListResponse *resp = [[AwemeListResponse alloc] initWithDictionary:data error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            UIViewController *rootVC = nil;
            if(resp.data.count > 0) {
                AwemeListController *feed = [[AwemeListController alloc]
                    initWithVideoData:[resp.data mutableCopy]
                         currentIndex:0 pageIndex:2 pageSize:10
                            awemeType:AwemeWork uid:@"__feed__"];
                feed.hidesBackButton = YES;
                feed.isFeedRoot = YES;
                UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:feed];
                nav.navigationBarHidden = YES;
                rootVC = nav;
            } else {
                rootVC = [[UINavigationController alloc] initWithRootViewController:[UserHomePageController new]];
            }
            wself.window.rootViewController = rootVC;
        });
    } failure:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            wself.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:[UserHomePageController new]];
        });
    }];
    [_window makeKeyAndVisible];

    [NetworkHelper startListening];
    [[WebSocketManager shareManager] connect];
    [AVPlayerManager setAudioMode];
    
    [self requestPermission];
    
    return YES;
}

- (void)requestPermission {
    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
        //process photo library request status.
    }];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    
    CGPoint touchLocation = [[[event allTouches] anyObject] locationInView:self.window];
    CGRect statusBarFrame = [UIApplication sharedApplication].statusBarFrame;
    
    if (CGRectContainsPoint(statusBarFrame, touchLocation)) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"StatusBarTouchBeginNotification" object:nil];
    }
}

@end
