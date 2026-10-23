#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSString *const MSPMarker = @"member_shelf_probe_overlay";
static NSMutableArray<NSString *> *MSPHistory(void) {
    static NSMutableArray<NSString *> *entries;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ entries = [NSMutableArray new]; });
    return entries;
}
static void MSPRecord(NSString *entry) {
    if (![NSThread isMainThread]) return;
    NSMutableArray *history = MSPHistory();
    if (history.count >= 110) [history removeObjectAtIndex:0];
    [history addObject:entry ?: @"(nil)"];
}
static NSString *MSPClass(id obj) {
    if (!obj) return @"nil";
    return NSStringFromClass([obj class]) ?: @"(unknown)";
}
static id MSPCall(id obj, NSString *selectorName) {
    if (!obj) return nil;
    SEL selector = NSSelectorFromString(selectorName);
    if (![obj respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(obj, selector);
}
static BOOL MSPHasText(NSString *s, NSString *q) {
    return [s isKindOfClass:[NSString class]] &&
        [s rangeOfString:q options:NSCaseInsensitiveSearch].location != NSNotFound;
}
static NSString *MSPToken(NSString *s) {
    if (MSPHasText(s, @"member_recognition_shelf")) return @"member_recognition_shelf";
    if (MSPHasText(s, @"recognitionShelfRenderer")) return @"recognitionShelfRenderer";
    if (MSPHasText(s, @"recognition_shelf")) return @"recognition_shelf";
    if (MSPHasText(s, @"recognition-shelf")) return @"recognition-shelf";
    return nil;
}
static void MSPLogItems(id items, NSString *context) {
    if (![items isKindOfClass:[NSArray class]]) return;
    NSUInteger index=0;
    for (id item in (NSArray *)items) {
        if (index++ >= 70) break;
        id element = MSPCall(item, @"elementRenderer");
        if (!element) element=MSPCall(item, @"itemSectionRenderer");
        id nested = MSPCall(item, @"contentsArray");
        if (![nested isKindOfClass:[NSArray class]]) nested=MSPCall(element, @"contentsArray");
        NSArray *toInspect = [nested isKindOfClass:[NSArray class]] ? nested : @[];
        NSMutableArray *objects=[NSMutableArray arrayWithObjects:item, nil];
        if (element) [objects addObject:element];
        for (id sub in [toInspect subarrayWithRange:NSMakeRange(0, MIN(toInspect.count, 24))]) {
            [objects addObject:sub];
            id el=MSPCall(sub, @"elementRenderer");
            if (el) [objects addObject:el];
        }
        BOOL found=NO;
        for (id obj in objects) {
            @try {
                NSString *d=[obj description];
                NSString *token=MSPToken(d);
                if (token) {
                    MSPRecord([NSString stringWithFormat:@"%@ token=%@ section=%@ object=%@",
                        context,token,MSPClass(item),MSPClass(obj)]);
                    found=YES;
                }
            } @catch(NSException *e) {}
        }
        if (!found && index<=6) {
            MSPRecord([NSString stringWithFormat:@"%@ first-item=%@ nested=%lu",
                context,MSPClass(item),(unsigned long)toInspect.count]);
        }
    }
}
static void MSPLogModel(id model, NSString *source) {
    if (![NSThread isMainThread]) return;
    @try {
        id contents=MSPCall(model,@"contentsArray");
        if ([contents isKindOfClass:[NSArray class]]) {
            MSPRecord([NSString stringWithFormat:@"%@ model=%@ sections=%lu",
                      source,MSPClass(model),(unsigned long)[contents count]]);
            MSPLogItems(contents, source);
        }
    } @catch(NSException *e) {}
}
// Exact user-reported localization; diagnostics never hide or modify views.
static BOOL MSPMatchesLabel(NSString *s) {
    if (![s isKindOfClass:[NSString class]]) return NO;
    NSStringCompareOptions opts=NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch;
    for (NSString *needle in @[@"Kanal üyelerine teşekkürler",
                               @"Kanal üyelerimize teşekkürler",
                               @"Thank you, channel members",
                               @"Our members", @"Üyelerimiz"]) {
        if ([s rangeOfString:needle options:opts].location != NSNotFound) return YES;
    }
    return NO;
}
static NSString *MSPLabelForView(UIView *v) {
    if ([v isKindOfClass:[UILabel class]] && ((UILabel *)v).text.length)
        return ((UILabel *)v).text;
    if ([v isKindOfClass:[UITextView class]] && ((UITextView *)v).text.length)
        return ((UITextView *)v).text;
    id text = MSPCall(v, @"text");
    if ([text isKindOfClass:[NSString class]] && [text length]) return text;
    id attributed = MSPCall(v, @"attributedText");
    if ([attributed isKindOfClass:[NSAttributedString class]]) {
        NSString *s=[(NSAttributedString *)attributed string];
        if (s.length) return s;
    }
    return v.accessibilityLabel;
}
static void MSPScanViews(UIView *v, NSMutableArray<NSString *> *hits,
                         NSUInteger *visited, NSUInteger depth) {
    if (!v || *visited>=14000 || depth>60 || hits.count>=30) return;
    (*visited)++;
    NSString *label = MSPLabelForView(v);
    if (MSPMatchesLabel(label)) {
        NSMutableArray<NSString *> *path=[NSMutableArray array];
        UIView *ancestor=v;
        for (NSUInteger i=0; ancestor && i<16; i++,ancestor=ancestor.superview) {
            NSString *siblings = [NSString stringWithFormat:@"%lu",
                                   (unsigned long)ancestor.superview.subviews.count];
            [path addObject:[NSString stringWithFormat:@"%@(%@ siblings) %@",
                MSPClass(ancestor), siblings,
                [ancestor isKindOfClass:[UICollectionViewCell class]] ? @"[COLLECTION CELL]" : @""]];
        }
        NSMutableArray<NSString *> *nearby=[NSMutableArray array];
        UIView *parent=v.superview;
        if (parent) {
            for (UIView *sibling in [parent.subviews subarrayWithRange:
                 NSMakeRange(0, MIN(parent.subviews.count,10))]) {
                [nearby addObject:MSPClass(sibling)];
            }
        }
        [hits addObject:[NSString stringWithFormat:
            @"MATCH label=%@\nPATH bottom-up: %@\nIMMEDIATE SIBLINGS: %@",
            MSPHasText(label, @"teşekkür") ? @"Kanal uyelerine tesekkurler" : @"English member heading",
            [path componentsJoinedByString:@" > "],
            [nearby componentsJoinedByString:@", "]]];
    }
    for (UIView *child in v.subviews) MSPScanViews(child,hits,visited,depth+1);
}
@interface MSPShelfInspector : NSObject
+ (instancetype)shared;
- (void)onTap:(UIButton *)sender;
@end
@implementation MSPShelfInspector
+ (instancetype)shared {
    static MSPShelfInspector *singleton; static dispatch_once_t once;
    dispatch_once(&once, ^{ singleton=[self new]; }); return singleton;
}
- (void)onTap:(UIButton *)sender {
    UIWindow *w=[sender.superview isKindOfClass:[UIWindow class]]?(UIWindow *)sender.superview:nil;
    if (!w) return;
    NSMutableArray<NSString *> *hits=[NSMutableArray array];
    NSUInteger visited=0;
    MSPScanViews(w,hits,&visited,0);
    NSMutableString *r=[NSMutableString stringWithFormat:
      @"MemberShelfInspector 0.2.0\nYouTube 21.42.4 test\nUIView count: %lu\n",
      (unsigned long)visited];
    UIViewController *top=w.rootViewController;
    [r appendFormat:@"Root VC: %@\n", MSPClass(top)];
    [r appendString:@"\nVisible member shelf / Turkish member thanks view paths:\n"];
    if (hits.count) [r appendString:[hits componentsJoinedByString:@"\n"]];
    else [r appendString:@"NO MATCH: keep 'Kanal üyelerine teşekkürler!' visible, then inspect again."];
    [r appendString:@"\n\nRecent section/renderer observations:\n"];
    NSArray *entries=MSPHistory();
    NSUInteger from=(entries.count>55)?entries.count-55:0;
    for(NSUInteger i=from;i<entries.count;i++) {
        [r appendFormat:@"%@\n",entries[i]];
    }
    [UIPasteboard generalPasteboard].string=r;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Inspector: Copied"
      message:@"The view-class report is copied to clipboard. Paste it into ChatGPT. It only lists class names and member-shelf markers, not video titles."
      preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    UIViewController *vc=w.rootViewController;
    while(vc.presentedViewController) vc=vc.presentedViewController;
    if(vc) [vc presentViewController:a animated:YES completion:nil];
}
@end
static void MSPInstallButton(void) {
    UIApplication *app=[UIApplication sharedApplication];
    UIWindow *window=app.keyWindow;
    if (!window) {
        for (UIWindow *w in app.windows) {
            if (!w.hidden && w.windowLevel==UIWindowLevelNormal) { window=w; break; }
        }
    }
    if (!window || [window viewWithTag:781912]) return;
    UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];
    button.tag=781912;
    [button setTitle:@"Inspect" forState:UIControlStateNormal];
    button.titleLabel.font=[UIFont boldSystemFontOfSize:13];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.backgroundColor=[UIColor colorWithRed:0.14 green:0.18 blue:0.24 alpha:0.92];
    CGFloat x=MAX(8,CGRectGetWidth(window.bounds)-94);
    CGFloat y=window.safeAreaInsets.top+52;
    button.frame=CGRectMake(x,y,80,36);
    button.layer.cornerRadius=12;
    button.layer.masksToBounds=YES;
    button.accessibilityIdentifier=MSPMarker;
    [button addTarget:[MSPShelfInspector shared] action:@selector(onTap:)
        forControlEvents:UIControlEventTouchUpInside];
    [window addSubview:button];
}
%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{ MSPInstallButton(); });
}
%end
%hook YTInnerTubeCollectionViewController
- (void)addSectionsFromArray:(NSArray *)sections {
    MSPLogItems(sections, @"innerTube:addSections");
    %orig;
}
- (void)loadWithModel:(id)model {
    MSPLogModel(model, @"innerTube:loadModel");
    %orig;
}
%end
%hook YTSectionListViewController
- (void)loadWithModel:(id)model {
    MSPLogModel(model, @"sectionList:loadModel");
    %orig;
}
%end
