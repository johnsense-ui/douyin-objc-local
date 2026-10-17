//
//  AppDelegate.m
//  Douyin
//
//  Created by Qiao Shi on 2018/7/30.
//  Copyright © 2018年 Qiao Shi. All rights reserved.
//

#import <Photos/Photos.h>
#import <arpa/inet.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <unistd.h>
#import "AppDelegate.h"
#import "UserHomePageController.h"
#import "AwemeListController.h"
#import "NetworkHelper.h"
#import "WebSocketManager.h"
#import "AVPlayerManager.h"

static const uint16_t kDiscoverPort = 6698;
static NSString * const kSavedBaseKey = @"dk.baseUrl";

#pragma mark - 局域网自动发现

/// 向 255.255.255.255:6698 广播，代理会回 "DOUYIN_HERE <ip> <port>"
static NSString *DKDiscoverBaseUrl(NSTimeInterval timeout) {
    int sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (sock < 0) { return nil; }

    int yes = 1;
    setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &yes, sizeof(yes));

    struct timeval tv;
    tv.tv_sec = (time_t)timeout;
    tv.tv_usec = (suseconds_t)((timeout - (NSTimeInterval)tv.tv_sec) * 1000000.0);
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(kDiscoverPort);
    addr.sin_addr.s_addr = htonl(INADDR_BROADCAST);

    const char *msg = "DOUYIN_DISCOVER";
    sendto(sock, msg, strlen(msg), 0, (struct sockaddr *)&addr, sizeof(addr));

    char buf[256];
    ssize_t n = recvfrom(sock, buf, sizeof(buf) - 1, 0, NULL, NULL);
    close(sock);
    if (n <= 0) { return nil; }

    buf[n] = 0;
    NSString *reply = [NSString stringWithUTF8String:buf];
    NSArray *parts = [reply componentsSeparatedByString:@" "];
    if (parts.count >= 3 && [parts[0] isEqualToString:@"DOUYIN_HERE"]) {
        NSString *base = [NSString stringWithFormat:@"http://%@:%@/douyin/", parts[1], parts[2]];
        NSLog(@"[discover] 找到服务器 %@", base);
        return base;
    }
    return nil;
}

/// 探一下这个 baseUrl 通不通（GET {base}health）
static BOOL DKProbeBase(NSString *base) {
    if (base.length == 0) { return NO; }
    NSURL *url = [NSURL URLWithString:[base stringByAppendingString:@"health"]];
    if (!url) { return NO; }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.timeoutInterval = 3;

    __block BOOL ok = NO;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [[[NSURLSession sharedSession] dataTaskWithRequest:req
                                    completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger code = [(NSHTTPURLResponse *)response statusCode];
        ok = (error == nil && code >= 200 && code < 400);
        dispatch_semaphore_signal(sem);
    }] resume];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)));
    return ok;
}

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    _window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];

    UIViewController *splash = [UIViewController new];
    splash.view.backgroundColor = [UIColor blackColor];
    _window.rootViewController = splash;
    [_window makeKeyAndVisible];

    [self bootstrap:0];

    [NetworkHelper startListening];
    [[WebSocketManager shareManager] connect];
    [AVPlayerManager setAudioMode];
    [self requestPermission];

    return YES;
}

/// 找服务器 → 探活 → 拉首页，失败就重来（换网络后会自动重新发现）
- (void)bootstrap:(NSInteger)attempt {
    __weak __typeof(self) wself = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *base = nil;

        if (attempt == 0) {
            base = DKDiscoverBaseUrl(1.5);
        }
        if (base.length == 0) {
            base = [[NSUserDefaults standardUserDefaults] stringForKey:kSavedBaseKey];
        }
        if (base.length == 0) {
            base = BaseUrl; // 编译进去的默认地址
        }

        BOOL reachable = DKProbeBase(base);
        NSLog(@"[bootstrap] attempt=%ld base=%@ reachable=%d", (long)attempt, base, reachable);

        if (reachable) {
            BaseUrl = [base copy];
            [[NSUserDefaults standardUserDefaults] setObject:BaseUrl forKey:kSavedBaseKey];
            dispatch_async(dispatch_get_main_queue(), ^{
                [wself loadFeedWithRetry:0];
            });
            return;
        }

        if (attempt < 3) {
            [NSThread sleepForTimeInterval:0.6];
            [wself bootstrap:attempt + 1];
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [UIWindow showTips:@"连不上本地服务，请确认代理已启动且同网段"];
            wself.window.rootViewController =
                [[UINavigationController alloc] initWithRootViewController:[UserHomePageController new]];
        });
    });
}

- (void)loadFeedWithRetry:(NSInteger)attempt {
    __weak __typeof(self) wself = self;

    AwemeListRequest *feedReq = [AwemeListRequest new];
    feedReq.page = 1;
    feedReq.size = 10;
    feedReq.uid = @"__feed__";

    [NetworkHelper getWithUrlPath:FindAwemePostByPagePath request:feedReq success:^(id data) {
        AwemeListResponse *resp = [[AwemeListResponse alloc] initWithDictionary:data error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (resp.data.count > 0) {
                AwemeListController *feed = [[AwemeListController alloc]
                    initWithVideoData:[resp.data mutableCopy]
                         currentIndex:0 pageIndex:2 pageSize:10
                            awemeType:AwemeWork uid:@"__feed__"];
                feed.hidesBackButton = YES;
                feed.isFeedRoot = YES;

                UINavigationController *nav =
                    [[UINavigationController alloc] initWithRootViewController:feed];
                nav.navigationBarHidden = YES;
                wself.window.rootViewController = nav;
            } else if (attempt < 1) {
                [wself bootstrap:0];
            } else {
                wself.window.rootViewController =
                    [[UINavigationController alloc] initWithRootViewController:[UserHomePageController new]];
            }
        });
    } failure:^(NSError *error) {
        // NetworkHelper 失败时会退到内置样本 JSON，这里再探一次真实连通性
        dispatch_async(dispatch_get_main_queue(), ^{
            if (attempt < 1) {
                [wself bootstrap:0];
            } else {
                wself.window.rootViewController =
                    [[UINavigationController alloc] initWithRootViewController:[UserHomePageController new]];
            }
        });
    }];
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
