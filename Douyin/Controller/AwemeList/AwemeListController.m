//
//  AwemeListController.m
//  Douyin
//
//  Created by Qiao Shi on 2018/7/30.
//  Copyright © 2018年 Qiao Shi. All rights reserved.
//

#import <AVKit/AVKit.h>
#import "Aweme.h"
#import "AwemeListController.h"
#import "AwemeListCell.h"
#import "AVPlayerView.h"
#import "NetworkHelper.h"
#import "LoadMoreControl.h"
#import "AVPlayerManager.h"
#import "UserHomePageController.h"

@class SearchController;

NSString * const kAwemeListCell   = @"AwemeListCell";

@interface AwemeListController () <UITableViewDelegate, UITableViewDataSource, UIScrollViewDelegate, AwemeListCellDelegate>

@property (nonatomic, assign) BOOL                              isCurPlayerPause;
@property (nonatomic, assign) NSInteger                         pageIndex;
@property (nonatomic, assign) NSInteger                         pageSize;
@property (nonatomic, assign) AwemeType                         awemeType;
@property (nonatomic, copy) NSString                            *uid;

@property (nonatomic, strong) NSMutableArray<Aweme *>           *data;
@property (nonatomic, strong) NSMutableArray<Aweme *>           *awemes;
@property (nonatomic, strong) LoadMoreControl                      *loadMore;

@end

@implementation AwemeListController

-(instancetype)initWithVideoData:(NSMutableArray<Aweme *> *)data currentIndex:(NSInteger)currentIndex pageIndex:(NSInteger)pageIndex pageSize:(NSInteger)pageSize awemeType:(AwemeType)type uid:(NSString *)uid {
    self = [super init];
    if(self) {
        _isCurPlayerPause = NO;
        _currentIndex = currentIndex;
        _pageIndex = pageIndex;
        _pageSize = pageSize;
        _awemeType = type;
        _uid = uid;
        
        _awemes = [data mutableCopy];
        _data = [[NSMutableArray alloc] initWithObjects:[_awemes objectAtIndex:_currentIndex], nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(statusBarTouchBegin) name:@"StatusBarTouchBeginNotification" object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationBecomeActive) name:UIApplicationWillEnterForegroundNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationEnterBackground) name: UIApplicationDidEnterBackgroundNotification object:nil];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setBackgroundImage:@"img_video_loading"];
    [self setUpView];
    if(self.hidesBackButton) {
        self.navigationController.navigationBarHidden = YES;
        [self addSearchEntry];
    } else {
        [self setLeftButton:@"icon_titlebar_whiteback"];
    }
}

- (void)setUpView {
    self.view.layer.masksToBounds = YES;
    
    _tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, -ScreenHeight, ScreenWidth, ScreenHeight * 3)];
    _tableView.contentInset = UIEdgeInsetsMake(ScreenHeight, 0, ScreenHeight * 1, 0);
    
    _tableView.backgroundColor = ColorClear;
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.showsVerticalScrollIndicator = NO;
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    if (@available(iOS 11.0, *)) {
        _tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    } else {
        self.automaticallyAdjustsScrollViewInsets = NO;
    }
    [self.tableView registerClass:AwemeListCell.class forCellReuseIdentifier:kAwemeListCell];
    
    _loadMore = [[LoadMoreControl alloc] initWithFrame:CGRectMake(0, 100, ScreenWidth, 50) surplusCount:3];
    __weak __typeof(self) wself = self;
    [_loadMore setOnLoad:^{
        [wself loadData:wself.pageIndex pageSize:wself.pageSize];
    }];
    [_tableView addSubview:_loadMore];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self.view addSubview:self.tableView];
        self.data = self.awemes;
        [self.tableView reloadData];
        
        NSIndexPath *curIndexPath = [NSIndexPath indexPathForRow:self.currentIndex inSection:0];
        [self.tableView scrollToRowAtIndexPath:curIndexPath atScrollPosition:UITableViewScrollPositionMiddle
                                      animated:NO];
        [self addObserver:self forKeyPath:@"currentIndex" options:NSKeyValueObservingOptionInitial|NSKeyValueObservingOptionNew context:nil];
    });
}

-(void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [_tableView.layer removeAllAnimations];
    NSArray<AwemeListCell *> *cells = [_tableView visibleCells];
    for(AwemeListCell *cell in cells) {
        [cell.playerView cancelLoading];
    }
    [[AVPlayerManager shareManager] removeAllPlayers];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self removeObserver:self forKeyPath:@"currentIndex"];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma tableView delegate
-(NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.data.count;
}

-(CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return self.view.frame.size.height;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    //填充视频数据
    AwemeListCell *cell = [tableView dequeueReusableCellWithIdentifier:kAwemeListCell forIndexPath:indexPath];
    cell.cellDelegate = self;
    [cell initData:_data[indexPath.row]];
    [cell startDownloadBackgroundTask];
    return cell;
}

#pragma mark - AwemeListCellDelegate

- (void)awemeCellDidTapAvatar:(Aweme *)aweme {
    if(aweme.author.uid.length == 0) { return; }
    UserHomePageController *home = [[UserHomePageController alloc] initWithUid:aweme.author.uid];
    home.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:home animated:YES];
}

#pragma mark - 搜索入口

- (void)addSearchEntry {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    [btn setTitle:@"搜索" forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [btn addTarget:self action:@selector(openSearch) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:btn];
    [btn mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.equalTo(self.view).inset(16);
        make.top.equalTo(self.view).offset(SafeAreaTopHeight + 8);
        make.width.mas_equalTo(48);
        make.height.mas_equalTo(32);
    }];
}



#pragma ScrollView delegate
- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate{
    dispatch_async(dispatch_get_main_queue(), ^{
        CGPoint translatedPoint = [scrollView.panGestureRecognizer translationInView:scrollView];
        //UITableView禁止响应其他滑动手势
        scrollView.panGestureRecognizer.enabled = NO;
    
        if(translatedPoint.y < -50 && self.currentIndex < (self.data.count - 1)) {
            self.currentIndex ++;   //向下滑动索引递增
        }
        if(translatedPoint.y > 50 && self.currentIndex > 0) {
            self.currentIndex --;   //向上滑动索引递减
        }
        [UIView animateWithDuration:0.15
                              delay:0.0
                            options:UIViewAnimationOptionCurveEaseOut animations:^{
                                //UITableView滑动到指定cell
                                [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:self.currentIndex inSection:0] atScrollPosition:UITableViewScrollPositionTop animated:NO];
                            } completion:^(BOOL finished) {
                                //UITableView可以响应其他滑动手势
                                scrollView.panGestureRecognizer.enabled = YES;
                            }];
        
    });
}

#pragma KVO
-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    //观察currentIndex变化
    if ([keyPath isEqualToString:@"currentIndex"]) {
        //设置用于标记当前视频是否播放的BOOL值为NO
        _isCurPlayerPause = NO;
        //获取当前显示的cell
        AwemeListCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:_currentIndex inSection:0]];
        [cell startDownloadHighPriorityTask];
        __weak typeof (cell) wcell = cell;
        __weak typeof (self) wself = self;
        //判断当前cell的视频源是否已经准备播放
        if(cell.isPlayerReady) {
            //播放视频
            [cell replay];
        }else {
            [[AVPlayerManager shareManager] pauseAll];
            //当前cell的视频源还未准备好播放，则实现cell的OnPlayerReady Block 用于等待视频准备好后通知播放
            cell.onPlayerReady = ^{
                NSIndexPath *indexPath = [wself.tableView indexPathForCell:wcell];
                if(!wself.isCurPlayerPause && indexPath && indexPath.row == wself.currentIndex) {
                    [wcell play];
                }
            };
        }
    } else {
        return [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)statusBarTouchBegin {
    _currentIndex = 0;
}

- (void)applicationBecomeActive {
    AwemeListCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:self.currentIndex inSection:0]];
    if(!_isCurPlayerPause) {
        [cell.playerView play];
    }
}

- (void)applicationEnterBackground {
    AwemeListCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:_currentIndex inSection:0]];
    _isCurPlayerPause = ![cell.playerView rate];
    [cell.playerView pause];
}

#pragma load data
- (void)loadData:(NSInteger)pageIndex pageSize:(NSInteger)pageSize {
    __weak __typeof(self) wself = self;
    AwemeListRequest *request = [AwemeListRequest new];
    request.page = pageIndex;
    request.size = pageSize;
    request.uid = _uid;
    if(_awemeType == AwemeWork) {
        [NetworkHelper getWithUrlPath:FindAwemePostByPagePath request:request success:^(id data) {
            AwemeListResponse *response = [[AwemeListResponse alloc] initWithDictionary:data error:nil];
            NSArray<Aweme *> *array = response.data;
            if(array.count > 0) {
                wself.pageIndex++;
                [wself.tableView beginUpdates];
                [wself.data addObjectsFromArray:array];
                NSMutableArray<NSIndexPath *> *indexPaths = [NSMutableArray array];
                for(NSInteger row = wself.data.count - array.count; row<wself.data.count; row++) {
                    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:0];
                    [indexPaths addObject:indexPath];
                }
                [wself.tableView insertRowsAtIndexPaths:indexPaths withRowAnimation:NO];
                [wself.tableView endUpdates];
                
                [wself.loadMore endLoading];
            }else {
                [wself.loadMore loadingAll];
            }
        } failure:^(NSError *error) {
            [wself.loadMore loadingFailed];
        }];
    }else {
        [NetworkHelper getWithUrlPath:FindAwemeFavoriteByPagePath request:request success:^(id data) {
            AwemeListResponse *response = [[AwemeListResponse alloc] initWithDictionary:data error:nil];
            NSArray<Aweme *> *array = response.data;
            if(array.count > 0) {
                wself.pageIndex++;
                [wself.tableView beginUpdates];
                [wself.data addObjectsFromArray:array];
                NSMutableArray<NSIndexPath *> *indexPaths = [NSMutableArray array];
                for(NSInteger row = wself.data.count - array.count; row<wself.data.count; row++) {
                    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:0];
                    [indexPaths addObject:indexPath];
                }
                [wself.tableView insertRowsAtIndexPaths:indexPaths withRowAnimation:NO];
                [wself.tableView endUpdates];
                [wself.loadMore endLoading];
            }else {
                [wself.loadMore loadingAll];
            }
        } failure:^(NSError *error) {
            [wself.loadMore loadingFailed];
        }];
    }
}

- (void)dealloc {
    NSLog(@"======== dealloc =======");
}

@end

#pragma mark - 搜索页

@interface SearchController : BaseViewController <UISearchBarDelegate, UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray<Aweme *> *results;
@property (nonatomic, strong) NSMutableArray<NSString *> *suggestions;
@property (nonatomic, assign) BOOL showingSuggest;
@end

@implementation SearchController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    _results = [NSMutableArray array];
    _suggestions = [NSMutableArray array];
    _showingSuggest = YES;

    _searchBar = [[UISearchBar alloc] init];
    _searchBar.placeholder = @"搜作者 / 文案 / 合集";
    _searchBar.delegate = self;
    _searchBar.barStyle = UIBarStyleBlack;
    _searchBar.searchBarStyle = UISearchBarStyleMinimal;
    _searchBar.tintColor = [UIColor whiteColor];
    [self.view addSubview:_searchBar];

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.backgroundColor = [UIColor blackColor];
    _tableView.separatorColor = [UIColor colorWithWhite:0.2 alpha:1];
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.rowHeight = 88;
    _tableView.tableFooterView = [UIView new];
    [self.view addSubview:_tableView];

    [_searchBar mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.right.equalTo(self.view);
        make.top.equalTo(self.view).offset(SafeAreaTopHeight);
        make.height.mas_equalTo(50);
    }];
    [_tableView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.right.bottom.equalTo(self.view);
        make.top.equalTo(self.searchBar.mas_bottom);
    }];

    [self loadSuggestions];
}

- (void)loadSuggestions {
    NSString *url = [NSString stringWithFormat:@"%@search/suggest", BaseUrl];
    [[[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:url]
                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if(!data) { return; }
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSMutableArray *words = [NSMutableArray array];
        for(NSDictionary *d in json[@"data"]) {
            NSString *w = d[@"word"];
            if(w.length > 0) { [words addObject:w]; }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.suggestions setArray:words];
            self.showingSuggest = YES;
            [self.tableView reloadData];
        });
    }] resume];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
    [self runSearch:searchBar.text];
}

- (void)runSearch:(NSString *)q {
    if(q.length == 0) { return; }
    NSString *enc = [q stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSString *url = [NSString stringWithFormat:@"%@search?q=%@", BaseUrl, enc];
    [[[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:url]
                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        AwemeListResponse *r = nil;
        if(data) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            r = [[AwemeListResponse alloc] initWithDictionary:json error:nil];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.results setArray:r.data ?: @[]];
            self.showingSuggest = NO;
            [self.tableView reloadData];
            if(self.results.count == 0) { [UIWindow showTips:@"没有匹配的视频"]; }
        });
    }] resume];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.showingSuggest ? self.suggestions.count : self.results.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.showingSuggest ? @"猜你想搜" : @"搜索结果";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"SearchCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if(!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellId];
        cell.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.textLabel.numberOfLines = 2;
        cell.detailTextLabel.textColor = [UIColor lightGrayColor];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    if(self.showingSuggest) {
        cell.textLabel.text = self.suggestions[indexPath.row];
        cell.detailTextLabel.text = @"";
    } else {
        Aweme *a = self.results[indexPath.row];
        cell.textLabel.text = a.desc.length > 0 ? a.desc : @"(无文案)";
        cell.detailTextLabel.text = [NSString stringWithFormat:@"@%@   ♥ %@", a.author.nickname, [NSString formatCount:a.statistics.digg_count]];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if(self.showingSuggest) {
        NSString *word = self.suggestions[indexPath.row];
        self.searchBar.text = word;
        [self runSearch:word];
        return;
    }
    if(self.results.count == 0) { return; }
    AwemeListController *feed = [[AwemeListController alloc] initWithVideoData:self.results
                                                                  currentIndex:indexPath.row
                                                                     pageIndex:2 pageSize:10
                                                                     awemeType:AwemeWork uid:@""];
    [self.navigationController pushViewController:feed animated:YES];
}

@end

@implementation AwemeListController (SearchEntry)

- (void)openSearch {
    SearchController *vc = [SearchController new];
    [self.navigationController pushViewController:vc animated:YES];
}

@end
