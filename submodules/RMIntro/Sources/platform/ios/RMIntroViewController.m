//
//  RMIntroViewController.m
//  IntroOpenGL
//
//  Created by Ilya Rimchikov on 19/01/14.
//
//

#import "RMGeometry.h"

#import "RMIntroViewController.h"
#import "RMIntroPageView.h"

#import <SSignalKit/SSignalKit.h>

#import <LegacyComponents/LegacyComponents.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

typedef enum {
    Inch35 = 0,
    Inch4 = 1,
    Inch47 = 2,
    Inch55 = 3,
    Inch65 = 4,
    iPad = 5,
    iPadPro = 6
} DeviceScreen;

@interface UIScrollView (CurrentPage)
- (int)currentPage;
- (void)setPage:(NSInteger)page;
- (int)currentPageMin;
- (int)currentPageMax;

@end

@implementation UIScrollView (CurrentPage)

- (int)currentPage
{
    CGFloat pageWidth = self.frame.size.width;
    return (int)floor((self.contentOffset.x - pageWidth / 2) / pageWidth) + 1;
}

- (int)currentPageMin
{
    CGFloat pageWidth = self.frame.size.width;
    return (int)floor((self.contentOffset.x - pageWidth / 2 - pageWidth / 2) / pageWidth) + 1;
}

- (int)currentPageMax
{
    CGFloat pageWidth = self.frame.size.width;
    return (int)floor((self.contentOffset.x - pageWidth / 2 + pageWidth / 2 ) / pageWidth) + 1;
}

- (void)setPage:(NSInteger)page
{
    self.contentOffset = CGPointMake(self.frame.size.width*page, 0);
}
@end

// The page dots, for VoiceOver an adjustable "Page" element: swiping up/down shows the next/previous page, as a
// sideways swipe on the pages does. Everything is computed when VoiceOver asks.
@interface RMIntroPageControl : UIPageControl

@property (nonatomic, copy) NSString *pageAccessibilityLabel;
@property (nonatomic, copy) NSString *(^pageAccessibilityValue)(NSInteger page, NSInteger count);
@property (nonatomic, copy) void (^showPage)(NSInteger page);

@end

@implementation RMIntroPageControl

- (BOOL)isAccessibilityElement {
    return true;
}

- (NSString *)accessibilityLabel {
    return _pageAccessibilityLabel;
}

- (NSString *)accessibilityValue {
    if (_pageAccessibilityValue) {
        return _pageAccessibilityValue(self.currentPage + 1, self.numberOfPages);
    }
    return [super accessibilityValue];
}

- (UIAccessibilityTraits)accessibilityTraits {
    return UIAccessibilityTraitAdjustable;
}

- (void)accessibilityIncrement {
    if (_showPage && self.currentPage + 1 < self.numberOfPages) {
        _showPage(self.currentPage + 1);
    }
}

- (void)accessibilityDecrement {
    if (_showPage && self.currentPage > 0) {
        _showPage(self.currentPage - 1);
    }
}

@end

@interface RMIntroView : UIView

@property (nonatomic, copy) void (^onLayout)();

@end

@implementation RMIntroView

- (void)layoutSubviews {
    [super layoutSubviews];
    
    if (_onLayout) {
        _onLayout();
    }
}

@end

@interface RMIntroViewController () <UIGestureRecognizerDelegate>
{
    id _didEnterBackgroundObserver;
    id _willEnterBackgroundObserver;
    
    UIColor *_backgroundColor;
    UIColor *_primaryColor;
    UIColor *_buttonColor;
    UIColor *_accentColor;
    UIColor *_regularDotColor;
    UIColor *_highlightedDotColor;
    
    TGModernButton *_alternativeLanguageButton;
    
    SMetaDisposable *_localizationsDisposable;
    TGSuggestedLocalization *_alternativeLocalizationInfo;
    
    SVariable *_alternativeLocalization;
    NSDictionary<NSString *, NSString *> *_englishStrings;
    
    UIView *_wrapperView;
    UIView *_startButton;
    UIView *_logoPlaceholder;
    
    bool _loadedView;
    BOOL _isLogoPlaceholderLoaded;
    
    NSInteger _accessibilityPendingPage;
}
@end


@implementation RMIntroViewController

- (instancetype)initWithBackgroundColor:(UIColor *)backgroundColor primaryColor:(UIColor *)primaryColor buttonColor:(UIColor *)buttonColor accentColor:(UIColor *)accentColor regularDotColor:(UIColor *)regularDotColor highlightedDotColor:(UIColor *)highlightedDotColor suggestedLocalizationSignal:(SSignal *)suggestedLocalizationSignal
{
    self = [super init];
    if (self != nil)
    {
        _isEnabled = true;
        _accessibilityPendingPage = -1;
        
        _backgroundColor = backgroundColor;
        _primaryColor = primaryColor;
        _buttonColor = buttonColor;
        _accentColor = accentColor;
        _regularDotColor = regularDotColor;
        _highlightedDotColor = highlightedDotColor;
                
        NSArray<NSString *> *stringKeys = @[
            @"Tour.Title1",
            @"Tour.Title2",
            @"Tour.Title3",
            @"Tour.Title4",
            @"Tour.Title5",
            @"Tour.Title6",
            @"Tour.Text1",
            @"Tour.Text2",
            @"Tour.Text3",
            @"Tour.Text4",
            @"Tour.Text5",
            @"Tour.Text6",
            @"Tour.StartButton"
        ];
        
        NSMutableDictionary *englishStrings = [[NSMutableDictionary alloc] init];
        NSBundle *bundle = [NSBundle bundleWithPath:[[NSBundle mainBundle] pathForResource:@"en" ofType:@"lproj"]];
        for (NSString *key in stringKeys) {
            if (bundle != nil) {
                NSString *value = [bundle localizedStringForKey:key value:key table:nil];
                if (value != nil) {
                    englishStrings[key] = value;
                } else {
                    englishStrings[key] = key;
                }
            } else {
                englishStrings[key] = key;
            }
        }
        // Harnessgram keeps intro copy in source while localization tables remain generated upstream.
        // TODO: add reviewed Hebrew localization through the project localization workflow.
        [englishStrings addEntriesFromDictionary:@{
            @"Tour.Title1": @"Harnessgram",
            @"Tour.Title2": @"Stay connected",
            @"Tour.Title3": @"Share with ease",
            @"Tour.Title4": @"Find your people",
            @"Tour.Title5": @"Make it yours",
            @"Tour.Title6": @"Your conversations",
            @"Tour.Text1": @"A simple place to keep in touch with the people who matter.",
            @"Tour.Text2": @"Pick up your conversations across your devices.",
            @"Tour.Text3": @"Share the moments that matter.",
            @"Tour.Text4": @"Create group conversations around the things you care about.",
            @"Tour.Text5": @"Choose the look and feel that works for you.",
            @"Tour.Text6": @"Keep your chats together and easy to find.",
            @"Tour.StartButton": @"Start using Harnessgram"
        }];
        _englishStrings = englishStrings;
        
        _headlines = @[ _englishStrings[@"Tour.Title1"], _englishStrings[@"Tour.Title2"],  _englishStrings[@"Tour.Title6"], _englishStrings[@"Tour.Title3"], _englishStrings[@"Tour.Title4"], _englishStrings[@"Tour.Title5"]];
        _descriptions = @[_englishStrings[@"Tour.Text1"], _englishStrings[@"Tour.Text2"],  _englishStrings[@"Tour.Text6"], _englishStrings[@"Tour.Text3"], _englishStrings[@"Tour.Text4"], _englishStrings[@"Tour.Text5"]];
        
        __weak RMIntroViewController *weakSelf = self;
        _alternativeLanguageButton = [[TGModernButton alloc] init];
        _alternativeLanguageButton.modernHighlight = true;
        [_alternativeLanguageButton setTitleColor:accentColor];
        
        _alternativeLanguageButton.titleLabel.font = [UIFont systemFontOfSize:18.0];
        _alternativeLanguageButton.hidden = true;
        [_alternativeLanguageButton addTarget:self action:@selector(alternativeLanguageButtonPressed) forControlEvents:UIControlEventTouchUpInside];
        
        _alternativeLocalization = [[SVariable alloc] init];
        
        _localizationsDisposable = [[suggestedLocalizationSignal deliverOn:[SQueue mainQueue]] startStrictWithNext:^(TGSuggestedLocalization *next) {
            __strong RMIntroViewController *strongSelf = weakSelf;
            if (strongSelf != nil && next != nil) {
                if (strongSelf->_alternativeLocalizationInfo == nil) {
                    strongSelf->_alternativeLocalizationInfo = next;
                    
                    [strongSelf->_alternativeLanguageButton setTitle:next.continueWithLanguageString forState:UIControlStateNormal];
                    strongSelf->_alternativeLanguageButton.hidden = false;
                    [strongSelf->_alternativeLanguageButton sizeToFit];
                    
                    if ([strongSelf isViewLoaded]) {
                        strongSelf->_alternativeLanguageButton.alpha = 0.0;
                        [UIView animateWithDuration:0.3 animations:^{
                            strongSelf->_alternativeLanguageButton.alpha = strongSelf->_isEnabled ? 1.0 : 0.6;
                            [strongSelf viewWillLayoutSubviews];
                        }];
                    }
                }
            }
        } file:__FILE_NAME__ line:__LINE__];
    }
    return self;
}

- (void)animateIn {
    CGPoint logoTargetPosition = _logoPlaceholder.center;
    _logoPlaceholder.center = CGPointMake(self.view.bounds.size.width / 2.0, self.view.bounds.size.height / 2.0);
    
    RMIntroPageView *firstPage = (RMIntroPageView *)[_pageViews firstObject];
    CGPoint headerTargetPosition = firstPage.headerLabel.center;
    firstPage.headerLabel.center = CGPointMake(headerTargetPosition.x, headerTargetPosition.y + 140.0);
    
    CGPoint descriptionTargetPosition = firstPage.descriptionLabel.center;
    firstPage.descriptionLabel.center = CGPointMake(descriptionTargetPosition.x, descriptionTargetPosition.y + 160.0);
    
    CGPoint pageControlTargetPosition = _pageControl.center;
    _pageControl.center = CGPointMake(pageControlTargetPosition.x, pageControlTargetPosition.y + 200.0);
    
    CGPoint buttonTargetPosition = _startButton.center;
    _startButton.center = CGPointMake(buttonTargetPosition.x, buttonTargetPosition.y + 220.0);
    UIView *secondaryButton = self.secondaryStartButton;
    CGPoint secondaryTargetPosition = secondaryButton != nil ? secondaryButton.center : CGPointZero;
    secondaryButton.center = CGPointMake(secondaryTargetPosition.x, secondaryTargetPosition.y + 220.0);
    
    _logoPlaceholder.transform = CGAffineTransformMakeScale(0.66, 0.66);
        
    [UIView animateWithDuration:0.65 delay:0.15 usingSpringWithDamping:1.2f initialSpringVelocity:0.0 options:kNilOptions animations:^{
        _logoPlaceholder.center = logoTargetPosition;
        firstPage.headerLabel.center = headerTargetPosition;
        firstPage.descriptionLabel.center = descriptionTargetPosition;
        _pageControl.center = pageControlTargetPosition;
        _startButton.center = buttonTargetPosition;
        secondaryButton.center = secondaryTargetPosition;
        _logoPlaceholder.transform = CGAffineTransformIdentity;
    } completion:nil];
    
    _logoPlaceholder.alpha = 0.0;
    _pageScrollView.alpha = 0.0;
    _pageControl.alpha = 0.0;
    _startButton.alpha = 0.0;
    secondaryButton.alpha = 0.0;
    
    [UIView animateWithDuration:0.3 delay:0.15 options:kNilOptions animations:^{
        _logoPlaceholder.alpha = 1.0;
        _pageScrollView.alpha = 1.0;
        _pageControl.alpha = 1.0;
        _startButton.alpha = 1.0;
        secondaryButton.alpha = 1.0;
    } completion:nil];
}

- (void)loadPlaceholderLogo
{
    if (!_isLogoPlaceholderLoaded)
    {
        bool isIpad = ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad);
        
        CGFloat size = 200;
        if (isIpad)
            size *= 1.2;
        
        int height = 50;
        if (isIpad)
            height += 138 / 2;
        
        // TODO: replace this text placeholder with the approved Harnessgram app icon.
        _logoPlaceholder = [[UIView alloc] initWithFrame:CGRectMake(self.view.bounds.size.width / 2 - size / 2, height, size, size)];
        _logoPlaceholder.backgroundColor = [UIColor clearColor];
        _logoPlaceholder.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
        _logoPlaceholder.userInteractionEnabled = false;
        UILabel *placeholderLabel = [[UILabel alloc] initWithFrame:_logoPlaceholder.bounds];
        placeholderLabel.text = @"H";
        placeholderLabel.textAlignment = NSTextAlignmentCenter;
        placeholderLabel.textColor = _primaryColor;
        placeholderLabel.font = [UIFont systemFontOfSize:88.0 weight:UIFontWeightSemibold];
        placeholderLabel.accessibilityLabel = @"Harnessgram";
        [_logoPlaceholder addSubview:placeholderLabel];
        [self.view addSubview:_logoPlaceholder];
        _isLogoPlaceholderLoaded = true;
    }
}

- (void)freePlaceholderLogo
{
    if (!_isLogoPlaceholderLoaded)
        return;

    [_logoPlaceholder removeFromSuperview];
    _logoPlaceholder = nil;
    _isLogoPlaceholderLoaded = false;
}

- (void)loadView {
    self.view = [[RMIntroView alloc] initWithFrame:self.defaultFrame];
    __weak RMIntroViewController *weakSelf = self;
    ((RMIntroView *)self.view).onLayout = ^{
        __strong RMIntroViewController *strongSelf = weakSelf;
        if (strongSelf != nil) {
            [strongSelf updateLayout];
        }
    };
    
    [self viewDidLoad];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    if (_loadedView) {
        return;
    }
    _loadedView = true;
    
    self.view.backgroundColor = _backgroundColor;
    
    [self loadPlaceholderLogo];
    
    _wrapperView = [[UIScrollView alloc]initWithFrame:self.view.bounds];
    [self.view addSubview:_wrapperView];
    
    _pageScrollView = [[UIScrollView alloc]initWithFrame:self.view.bounds];
    _pageScrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    _pageScrollView.clipsToBounds = true;
    _pageScrollView.opaque = true;
    _pageScrollView.clearsContextBeforeDrawing = false;
    [_pageScrollView setShowsHorizontalScrollIndicator:false];
    [_pageScrollView setShowsVerticalScrollIndicator:false];
    _pageScrollView.pagingEnabled = true;
    _pageScrollView.contentSize = CGSizeMake(_headlines.count * self.view.bounds.size.width, self.view.bounds.size.height);
    _pageScrollView.delegate = self;
    [_wrapperView addSubview:_pageScrollView];
    
    _pageViews = [NSMutableArray array];
    
    for (NSUInteger i = 0; i < _headlines.count; i++)
    {
        RMIntroPageView *p = [[RMIntroPageView alloc]initWithFrame:CGRectMake(i * self.view.bounds.size.width, 0, self.view.bounds.size.width, 0) headline:[_headlines objectAtIndex:i] description:[_descriptions objectAtIndex:i] color:_primaryColor];
        p.opaque = true;
        p.clearsContextBeforeDrawing = false;
        [_pageViews addObject:p];
        [_pageScrollView addSubview:p];
    }
    [_pageScrollView setPage:0];
    
    [self.view addSubview:_alternativeLanguageButton];
    
    RMIntroPageControl *pageControl = [[RMIntroPageControl alloc] init];
    pageControl.pageAccessibilityLabel = _pageAccessibilityLabel;
    pageControl.pageAccessibilityValue = _pageAccessibilityValue;
    __weak RMIntroViewController *weakSelf = self;
    pageControl.showPage = ^(NSInteger page) {
        __strong RMIntroViewController *strongSelf = weakSelf;
        [strongSelf accessibilityShowPage:page];
    };
    _pageControl = pageControl;
    _pageControl.autoresizingMask = UIViewAutoresizingFlexibleBottomMargin;
    _pageControl.userInteractionEnabled = false;
    [_pageControl setNumberOfPages:6];
    _pageControl.pageIndicatorTintColor = _regularDotColor;
    _pageControl.currentPageIndicatorTintColor = _highlightedDotColor;
    [_wrapperView addSubview:_pageControl];
}

- (UIView *)createAnimationSnapshot {
    UIView *snapshotView = [_logoPlaceholder snapshotViewAfterScreenUpdates:false];
    snapshotView.frame = _logoPlaceholder.frame;
    return snapshotView;
}

- (UIView *)createTextSnapshot {
    UIView *snapshotView = [_wrapperView snapshotViewAfterScreenUpdates:false];
    snapshotView.frame = _wrapperView.frame;
    return snapshotView;
}

- (BOOL)shouldAutorotate
{
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad)
        return true;
    
    return false;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad)
        return UIInterfaceOrientationMaskAll;
    
    return UIInterfaceOrientationMaskPortrait;
}

- (DeviceScreen)deviceScreen
{
    CGSize viewSize = self.view.frame.size;
    int max = (int)MAX(viewSize.width, viewSize.height);
    
    DeviceScreen deviceScreen = Inch55;
    
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad)
    {
        switch (max)
        {
            case 1366:
                deviceScreen = iPadPro;
                break;
                
            default:
                deviceScreen = iPad;
                break;
        }
    }
    else
    {
        switch (max)
        {
            case 480:
                deviceScreen = Inch35;
                break;
            case 568:
                deviceScreen = Inch4;
                break;
            case 667:
                deviceScreen = Inch47;
                break;
            case 896:
                deviceScreen = Inch65;
                break;
            default:
                deviceScreen = Inch55;
                break;
        }
    }
    
    return deviceScreen;
}

- (void)updateLayout
{
    UIInterfaceOrientation isVertical = (self.view.bounds.size.height / self.view.bounds.size.width > 1.0f);
    
    CGFloat statusBarHeight = 0;
    
    CGFloat pageControlY = 0;
    CGFloat glViewY = 0;
    CGFloat startButtonY = 0;
    CGFloat pageY = 0;
    
    CGFloat languageButtonSpread = 60.0f;
    CGFloat languageButtonOffset = 26.0f;
    
    DeviceScreen deviceScreen = [self deviceScreen];
    switch (deviceScreen)
    {
        case iPad:
            glViewY = isVertical ? 121 + 90 : 121;
            startButtonY = 120;
            pageY = isVertical ? 485 : 335;
            pageControlY = pageY + 200.0f;
            break;
            
        case iPadPro:
            glViewY = isVertical ? 221 + 110 : 221;
            startButtonY = 120;
            pageY = isVertical ? 605 : 435;
            pageControlY = pageY + 200.0f;
            break;
            
        case Inch35:
            pageControlY = 162 / 2;
            glViewY = 62 - 20;
            startButtonY = 75;
            pageY = 215;
            pageControlY = pageY + 160.0f;
            if (!_alternativeLanguageButton.isHidden) {
                glViewY -= 40.0f;
                pageY -= 40.0f;
                pageControlY -= 40.0f;
                startButtonY -= 30.0f;
            }
            languageButtonSpread = 65.0f;
            languageButtonOffset = 15.0f;
            break;
            
        case Inch4:
            glViewY = 62;
            startButtonY = 75;
            pageY = 245;
            pageControlY = pageY + 160.0f;
            languageButtonSpread = 50.0f;
            languageButtonOffset = 20.0f;
            break;
            
        case Inch47:
            pageControlY = 162 / 2 + 10;
            glViewY = 62 + 25;
            startButtonY = 75 + 5;
            pageY = 245 + 50;
            pageControlY = pageY + 160.0f;
            break;
            
        case Inch55:
            glViewY = 62 + 45;
            startButtonY = 75 + 20;
            pageY = 245 + 85;
            pageControlY = pageY + 160.0f;
            break;
            
        case Inch65:
            glViewY = 62 + 85;
            startButtonY = 75 + 30;
            pageY = 245 + 125;
            pageControlY = pageY + 160.0f;
            break;
            
        default:
            break;
    }
    
    if (!_alternativeLanguageButton.isHidden) {
        startButtonY += languageButtonSpread;
    }
    if (self.secondaryStartButton != nil) {
        // Reserve its tap target and the bottom safe area before placing the primary button.
        startButtonY = MAX(startButtonY + 44.0f, 94.0f + self.view.safeAreaInsets.bottom);
    }
    
    _pageControl.frame = CGRectMake(0, pageControlY, self.view.bounds.size.width, 7);
    _logoPlaceholder.frame = CGRectChangedOriginY(_logoPlaceholder.frame, glViewY - statusBarHeight);
    
    CGFloat startButtonWidth = MIN(430.0 - 48.0, self.view.bounds.size.width - 48.0f);
    UIView *startButton = self.createStartButton(startButtonWidth);
    if (startButton.superview == nil) {
        _startButton = startButton;
        [self.view addSubview:startButton];
    }
    startButton.frame = CGRectMake(floor((self.view.bounds.size.width - startButtonWidth) / 2.0f), self.view.bounds.size.height - startButtonY - statusBarHeight, startButtonWidth, 50.0f);
    
    if (self.secondaryStartButton != nil && self.secondaryStartButton.superview == nil) {
        [self.view addSubview:self.secondaryStartButton];
    }
    self.secondaryStartButton.frame = CGRectMake(CGRectGetMinX(startButton.frame), CGRectGetMaxY(startButton.frame), startButtonWidth, 44.0f);
    CGFloat alternativeLanguageY = CGRectGetMaxY(startButton.frame) + (self.secondaryStartButton != nil ? 44.0f : languageButtonOffset);
    _alternativeLanguageButton.frame = CGRectMake(floor((self.view.bounds.size.width - _alternativeLanguageButton.frame.size.width) / 2.0f), alternativeLanguageY, _alternativeLanguageButton.frame.size.width, _alternativeLanguageButton.frame.size.height);
    
    _wrapperView.frame = CGRectMake(0, 0, self.view.bounds.size.width, self.view.bounds.size.height);
    _pageScrollView.frame=CGRectMake(0, 20, self.view.bounds.size.width, self.view.bounds.size.height - 20);
    _pageScrollView.contentSize=CGSizeMake(_headlines.count * self.view.bounds.size.width, 150);
    _pageScrollView.contentOffset = CGPointMake(_currentPage * self.view.bounds.size.width, 0);
    
    [_pageViews enumerateObjectsUsingBlock:^(UIView *pageView, NSUInteger index, __unused BOOL *stop) {
        pageView.frame = CGRectMake(index * self.view.bounds.size.width, (pageY - statusBarHeight), self.view.bounds.size.width, 150);
    }];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    [self loadPlaceholderLogo];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    
    [self freePlaceholderLogo];
}

- (void)startButtonPress
{
    if (_startMessaging) {
        _startMessaging();
    }
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:_didEnterBackgroundObserver];
    [[NSNotificationCenter defaultCenter] removeObserver:_willEnterBackgroundObserver];
    
    [_localizationsDisposable dispose];
    
    [self freePlaceholderLogo];
}

static CGFloat x;
static bool justEndDragging;

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)__unused decelerate
{
    x = scrollView.contentOffset.x;
    justEndDragging = true;
}

NSInteger _current_page_end;

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    // Harnessgram: the Telegram logo animation is removed, so the scroll offset no longer drives it.
    
    if (justEndDragging)
    {
        justEndDragging = false;
        
        CGFloat page = scrollView.contentOffset.x / scrollView.frame.size.width;
        CGFloat sign = scrollView.contentOffset.x - x;
        
        if (sign > 0)
        {
            if (page > _currentPage)
                _currentPage++;
        }
        
        if (sign < 0)
        {
            if (page < _currentPage)
                _currentPage--;
        }
        
        _currentPage = MAX(0, MIN(5, _currentPage));
        _current_page_end = _currentPage;
    }
    else
    {
        if (_pageScrollView.contentOffset.x > _current_page_end*_pageScrollView.frame.size.width)
        {
            if (_pageScrollView.currentPageMin > _current_page_end) {
                _currentPage = [_pageScrollView currentPage];
                _current_page_end = _currentPage;
            }
        }
        else
        {
            if (_pageScrollView.currentPageMax < _current_page_end)
            {
                _currentPage = [_pageScrollView currentPage];
                _current_page_end = _currentPage;
            }
        }
    }
    
    [_pageControl setCurrentPage:_currentPage];
}

- (void)accessibilityShowPage:(NSInteger)page {
    page = MAX(0, MIN((NSInteger)_headlines.count - 1, page));
    if (page == _currentPage) {
        return;
    }
    // The pages' own scroll tracking only settles a page after a drag; a VoiceOver request names the page up front.
    _currentPage = page;
    _current_page_end = page;
    _accessibilityPendingPage = page;
    [_pageControl setCurrentPage:page];
    [_pageScrollView setContentOffset:CGPointMake(page * _pageScrollView.frame.size.width, 0.0) animated:true];
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView {
    if (scrollView == _pageScrollView && _accessibilityPendingPage >= 0) {
        NSInteger page = _accessibilityPendingPage;
        _accessibilityPendingPage = -1;
        NSString *value = _pageAccessibilityValue ? _pageAccessibilityValue(page + 1, _pageControl.numberOfPages) : nil;
        UIAccessibilityPostNotification(UIAccessibilityPageScrolledNotification, value);
    }
}

- (void)alternativeLanguageButtonPressed {
    if (_startMessagingInAlternativeLanguage && _alternativeLocalizationInfo.info.code.length != 0) {
        _startMessagingInAlternativeLanguage(_alternativeLocalizationInfo.info.code);
    }
}

- (void)setIsEnabled:(bool)isEnabled {
    if (_isEnabled != isEnabled) {
        _isEnabled = isEnabled;
        _alternativeLanguageButton.alpha = _isEnabled ? 1.0 : 0.6;
    }
}

@end

@implementation TGAvailableLocalization

- (instancetype)initWithTitle:(NSString *)title localizedTitle:(NSString *)localizedTitle code:(NSString *)code {
    self = [super init];
    if (self != nil) {
        _title = title;
        _localizedTitle = localizedTitle;
        _code = code;
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    return [self initWithTitle:[aDecoder decodeObjectForKey:@"title"] localizedTitle:[aDecoder decodeObjectForKey:@"localizedTitle"] code:[aDecoder decodeObjectForKey:@"code"]];
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:_title forKey:@"title"];
    [aCoder encodeObject:_localizedTitle forKey:@"localizedTitle"];
    [aCoder encodeObject:_code forKey:@"code"];
}

@end

@implementation TGSuggestedLocalization

- (instancetype)initWithInfo:(TGAvailableLocalization *)info continueWithLanguageString:(NSString *)continueWithLanguageString chooseLanguageString:(NSString *)chooseLanguageString chooseLanguageOtherString:(NSString *)chooseLanguageOtherString englishLanguageNameString:(NSString *)englishLanguageNameString {
    self = [super init];
    if (self != nil) {
        _info = info;
        _continueWithLanguageString = continueWithLanguageString;
        _chooseLanguageString = chooseLanguageString;
        _chooseLanguageOtherString = chooseLanguageOtherString;
        _englishLanguageNameString = englishLanguageNameString;
    }
    return self;
}

@end

#pragma clang diagnostic pop
