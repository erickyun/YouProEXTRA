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
    // Some UIView subclasses implement -text with a scalar return type.
    // Inspect Objective-C method signatures before sending object-returning calls.
    SEL textSel=NSSelectorFromString(@"text");
    NSMethodSignature *sig=[v methodSignatureForSelector:textSel];
    if (sig && sig.methodReturnType && sig.methodReturnType[0]=='@') {
        id value=MSPCall(v, @"text");
        if ([value isKindOfClass:[NSString class]] && [value length]) return value;
    }
    SEL attSel=NSSelectorFromString(@"attributedText");
    sig=[v methodSignatureForSelector:attSel];
    if (sig && sig.methodReturnType && sig.methodReturnType[0]=='@') {
        id value=MSPCall(v, @"attributedText");
        if ([value isKindOfClass:[NSAttributedString class]]) {
            NSString *text=[(NSAttributedString *)value string];
            if (text.length) return text;
        }
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

static NSString *MSPViewSummary(UIView *v, UIWindow *w) {
    if (!v) return @"(none)";
    CGRect r=CGRectZero;
    @try { r=[v convertRect:v.bounds toView:w]; } @catch(NSException *e) {}
    NSString *label=MSPLabelForView(v);
    NSString *flag = MSPMatchesLabel(label) ? @" [MEMBER LABEL]" : @"";
    return [NSString stringWithFormat:@"%@ (x=%.0f y=%.0f w=%.0f h=%.0f)%@",
        MSPClass(v),r.origin.x,r.origin.y,r.size.width,r.size.height,flag];
}
static void MSPViewsAtPoint(UIView *v, UIWindow *w, CGPoint point,
                            NSMutableArray<NSString *> *result,
                            NSUInteger depth, NSUInteger *visited) {
    if (!v || depth>70 || *visited>15000 || v.hidden || v.alpha<0.01) return;
    (*visited)++;
    CGRect rect=CGRectZero;
    @try {rect=[v convertRect:v.bounds toView:w];} @catch(NSException *e) {return;}
    if (CGRectContainsPoint(CGRectInset(rect,-3,-3),point)) {
        if (result.count<100) {
            [result addObject:[NSString stringWithFormat:@"depth=%lu %@",
                (unsigned long)depth, MSPViewSummary(v,w)]];
        }
    }
    for(UIView *child in v.subviews) {
        MSPViewsAtPoint(child,w,point,result,depth+1,visited);
    }
}
@interface MSPShelfInspector : NSObject
+ (instancetype)shared;
- (void)onTap:(UIButton *)sender;
- (void)onPick:(UITapGestureRecognizer *)recognizer;
@end
@implementation MSPShelfInspector
+ (instancetype)shared {
    static MSPShelfInspector *singleton; static dispatch_once_t once;
    dispatch_once(&once, ^{ singleton=[self new]; }); return singleton;
}
- (void)onTap:(UIButton *)sender {
    UIWindow *w=[sender.superview isKindOfClass:[UIWindow class]]?(UIWindow *)sender.superview:nil;
    if (!w || [w viewWithTag:781913]) return;
    // Don't rely on UILabel or localized strings; select by physical touch.
    UIView *cover=[[UIView alloc] initWithFrame:w.bounds];
    cover.tag=781913;
    cover.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    cover.backgroundColor=[UIColor colorWithWhite:0 alpha:0.18];
    UILabel *notice=[[UILabel alloc] initWithFrame:CGRectMake(12,w.safeAreaInsets.top+8,
                                              MAX(120,w.bounds.size.width-24),76)];
    notice.text=@"TAP THE MEMBER CARD HEADING\nKanal üyelerine teşekkürler!";
    notice.numberOfLines=2;
    notice.textAlignment=NSTextAlignmentCenter;
    notice.font=[UIFont boldSystemFontOfSize:15];
    notice.textColor=[UIColor whiteColor];
    notice.backgroundColor=[UIColor colorWithWhite:0.1 alpha:0.85];
    notice.layer.cornerRadius=12;
    notice.layer.masksToBounds=YES;
    notice.userInteractionEnabled=NO;
    [cover addSubview:notice];
    UITapGestureRecognizer *pick=[[UITapGestureRecognizer alloc]
                                   initWithTarget:self action:@selector(onPick:)];
    [cover addGestureRecognizer:pick];
    [w addSubview:cover];
}
- (void)onPick:(UITapGestureRecognizer *)recognizer {
    UIView *cover=recognizer.view;
    UIWindow *w=cover.window;
    if (!w) return;
    CGPoint p=[recognizer locationInView:w];
    [cover removeFromSuperview];
    // Temporarily hide the floating button so hitTest targets the actual content.
    UIView *floatButton=[w viewWithTag:781912];
    BOOL wasHidden=floatButton.hidden;
    floatButton.hidden=YES;
    UIView *hit=[w hitTest:p withEvent:nil];
    floatButton.hidden=wasHidden;

    NSMutableString *report=[NSMutableString stringWithFormat:
      @"MemberShelfInspector 0.3.0 (tap-picker)\n"
       "YouTube 21.42.4\nPicked point: x=%.0f y=%.0f\n"
       "hitTest UIView: %@\n\n",p.x,p.y,MSPClass(hit)];
    [report appendString:@"Hit UIView ancestry (inner to outer):\n"];
    UIView *a=hit;
    for(NSUInteger level=0;a && level<19;level++,a=a.superview) {
        [report appendFormat:@"%lu: %@\n",(unsigned long)level,MSPViewSummary(a,w)];
        UIView *parent=a.superview;
        if (parent) {
            [report appendFormat:@" siblings: %lu",
             (unsigned long)parent.subviews.count];
            NSUInteger count=0;
            for (UIView *sibling in parent.subviews) {
                if(count++>=12)break;
                [report appendFormat:@" | %@",MSPClass(sibling)];
            }
            [report appendString:@"\n"];
        }
    }

    NSMutableArray<NSString *> *pointViews=[NSMutableArray array];
    NSUInteger visited=0;
    MSPViewsAtPoint(w,w,p,pointViews,0,&visited);
    [report appendFormat:@"\nViews overlapping selected point (%lu total visited):\n",
        (unsigned long)visited];
    NSUInteger from=pointViews.count>65?pointViews.count-65:0;
    for(NSUInteger idx=from;idx<pointViews.count;idx++)
        [report appendFormat:@"%@\n",pointViews[idx]];

    NSMutableArray<NSString *> *namedHits=[NSMutableArray array];
    visited=0;
    MSPScanViews(w,namedHits,&visited,0);
    [report appendString:@"\nText matcher results:\n"];
    if(namedHits.count) [report appendString:[namedHits componentsJoinedByString:@"\n"]];
    else [report appendString:@"No matching UILabel/accessibility text found."];
    [report appendString:@"\n\nRecent renderer markers:\n"];
    NSArray<NSString *> *entries=MSPHistory();
    NSUInteger offset=entries.count>35?entries.count-35:0;
    for(NSUInteger i=offset;i<entries.count;i++) {
        if([entries[i] containsString:@"token="])
            [report appendFormat:@"%@\n",entries[i]];
    }
    [UIPasteboard generalPasteboard].string=report;
    UIAlertController *alert=[UIAlertController
        alertControllerWithTitle:@"Class hierarchy copied"
        message:@"Paste into ChatGPT. No video titles or member account names are included."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
          style:UIAlertActionStyleDefault handler:nil]];
    UIViewController *vc=w.rootViewController;
    while(vc.presentedViewController) vc=vc.presentedViewController;
    if(vc) [vc presentViewController:alert animated:YES completion:nil];
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
