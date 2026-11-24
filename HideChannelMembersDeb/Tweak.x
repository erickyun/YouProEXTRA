// HideChannelMembers 0.11.0 (members, live chat, search suggestions)
// Target identified by MemberShelfInspector on YouTube iOS 21.42.4:
// YTISectionListRenderer -> YTISectionListSupportedRenderers ->
// YTIItemSectionRenderer -> YTIItemSectionSupportedRenderers ->
// YTIElementRenderer.description contains "member_recognition_shelf".
// NO global YTIElementRenderer hook: only prune known section arrays.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

static id HCMCall(id object, NSString *method) {
    if (!object) return nil;
    SEL sel = NSSelectorFromString(method);
    return [object respondsToSelector:sel]
        ? ((id (*)(id,SEL))objc_msgSend)(object, sel) : nil;
}

// The second recognition card can be placed inside the video Description sheet.
// Its exact user-visible heading is different from channel Home's ELM identifier.
static BOOL HCMIsDescriptionMembersCardText(NSString *text) {
    if (![text isKindOfClass:[NSString class]]) return NO;
    static NSArray<NSString *> *needles;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        needles = @[
            @"Thank you, channel members!",
            @"Thank you, channel members",
            @"Thank you channel members",
            @"thank_you_channel_members",
            @"channel_members_recognition",
            @"channel_member_recognition"
        ];
    });
    NSStringCompareOptions matchOptions = NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch;
    for (NSString *needle in needles) {
        if ([text rangeOfString:needle options:matchOptions].location != NSNotFound)
            return YES;
    }

    // Turkish: "Kanal üyelerimize teşekkürler!", "Kanal üyelerine teşekkürler",
    // "Teşekkürler, kanal üyeleri!" and other wording/order variants.
    // Require both a member term AND gratitude; never match generic "Katıl".
    BOOL hasThanks =
        [text rangeOfString:@"teşekkür" options:matchOptions].location != NSNotFound ||
        [text rangeOfString:@"tesekkur" options:matchOptions].location != NSNotFound ||
        [text rangeOfString:@"sağ ol" options:matchOptions].location != NSNotFound;
    BOOL hasMember =
        [text rangeOfString:@"üye" options:matchOptions].location != NSNotFound ||
        [text rangeOfString:@"uye" options:matchOptions].location != NSNotFound;
    BOOL channelContext =
        [text rangeOfString:@"kanal" options:matchOptions].location != NSNotFound ||
        [text rangeOfString:@"üyelerimiz" options:matchOptions].location != NSNotFound ||
        [text rangeOfString:@"üyelerin" options:matchOptions].location != NSNotFound;
    if (hasThanks && hasMember && channelContext) return YES;

    return NO;
}


// Live chat detection is deliberately independent of the UI language.
// Only exact renderer/ELM identifiers are matched; do not match arbitrary
// "live", "chat", comment, channel, or video title strings.
static BOOL HCMIsLiveChatRenderer(id renderer) {
    if (!renderer) return NO;
    @try {
        NSString *className = NSStringFromClass([renderer class]);
        for (NSString *name in @[@"YTILiveChatRenderer",
                                 @"YTILiveChatReplayRenderer",
                                 @"YTILiveChatPreviewRenderer",
                                 @"YTILiveChatEntryPointRenderer",
                                 @"YTILiveChatEntryPointViewModel"]) {
            if ([className isEqualToString:name]) return YES;
        }
        for (NSString *field in @[@"liveChatRenderer", @"liveChatReplayRenderer",
                                  @"liveChatPreviewRenderer", @"liveChatEntryPointRenderer",
                                  @"liveChatEntryPointViewModel"]) {
            SEL selector = NSSelectorFromString(field);
            NSMethodSignature *sig = [renderer methodSignatureForSelector:selector];
            if (!sig || sig.methodReturnType[0] != '@') continue;
            NSString *has = [@"has" stringByAppendingString:
                [[[field substringToIndex:1] uppercaseString]
                 stringByAppendingString:[field substringFromIndex:1]]];
            SEL hs = NSSelectorFromString(has);
            NSMethodSignature *hsig = [renderer methodSignatureForSelector:hs];
            if (hsig && (hsig.methodReturnType[0]=='B' || hsig.methodReturnType[0]=='c')) {
                if (((BOOL (*)(id,SEL))objc_msgSend)(renderer, hs)) return YES;
            } else if (HCMCall(renderer, field)) return YES;
        }
        if (![className isEqualToString:@"YTIElementRenderer"]) return NO;
        NSString *description = [renderer description];
        if (![description isKindOfClass:[NSString class]]) return NO;
        for (NSString *token in @[@"live_chat_entry_point", @"live_chat_entrypoint",
                                   @"live_chat_preview", @"live_chat_replay",
                                   @"live_chat_shelf", @"live_chat_panel",
                                   @"liveChatEntryPointRenderer", @"liveChatPreviewRenderer",
                                   @"liveChatEntryPointViewModel"]) {
            if ([description rangeOfString:token options:NSCaseInsensitiveSearch].location != NSNotFound)
                return YES;
        }
    } @catch (NSException *exception) {}
    return NO;
}

static BOOL HCMIsMemberItem(id item) {
    if (HCMIsLiveChatRenderer(item)) return YES;
    id element = HCMCall(item, @"elementRenderer");
    if (!element) return NO;
    if (HCMIsLiveChatRenderer(element)) return YES;
    @try {
        NSString *description = [element description];
        if (![description isKindOfClass:[NSString class]]) return NO;
        if ([description rangeOfString:@"member_recognition_shelf"
                              options:NSCaseInsensitiveSearch].location != NSNotFound)
            return YES; // Verified on channel Home (0.4.0)
        return HCMIsDescriptionMembersCardText(description);
    } @catch (NSException *exception) {
        return NO;
    }
}

// An additional path for description-panel cards represented by a stand-alone
// YTIItemSectionRenderer or YTIShelfRenderer rather than a single ELM item.
// Never match the entire YTISectionListRenderer (it also holds transcript and details).
static BOOL HCMIsDirectDescriptionMembersSection(id section) {
    NSString *className = NSStringFromClass([section class]);
    if (![className isEqualToString:@"YTIItemSectionRenderer"] &&
        ![className isEqualToString:@"YTIShelfRenderer"]) return NO;
    // Never discard a multi-item section: it might also contain Video details,
    // Transcript, or other legitimate content.
    id children = HCMCall(section, @"contentsArray");
    if ([children isKindOfClass:[NSArray class]] && [children count] > 1) return NO;
    @try {
        return HCMIsDescriptionMembersCardText([section description]);
    } @catch (NSException *exception) { return NO; }
}

// Returns YES only if an identified member item leaves the section empty.
static BOOL HCMPruneItemSection(id section) {
    id raw = HCMCall(section, @"contentsArray");
    if (![raw isKindOfClass:[NSMutableArray class]]) return NO;
    NSMutableArray *items = (NSMutableArray *)raw;
    if (!items.count) return NO;

    NSMutableIndexSet *matches = [NSMutableIndexSet indexSet];
    [items enumerateObjectsUsingBlock:^(id item, NSUInteger index, BOOL *stop) {
        if (HCMIsMemberItem(item)) [matches addIndex:index];
    }];
    if (!matches.count) return NO;

    @try {
        [items removeObjectsAtIndexes:matches];
        NSLog(@"[HideChannelMembers] removed %lu member shelf items",
              (unsigned long)matches.count);
        return items.count == 0;
    } @catch (NSException *exception) {
        return NO;
    }
}

// Called with the YTISectionListRenderer before the app converts it to cells.
static void HCMPruneModel(id model) {
    id raw = HCMCall(model, @"contentsArray");
    if (![raw isKindOfClass:[NSMutableArray class]]) return;
    NSMutableArray *sections = (NSMutableArray *)raw;
    if (!sections.count) return;
    NSMutableIndexSet *emptySections = [NSMutableIndexSet indexSet];

    [sections enumerateObjectsUsingBlock:^(id wrapper, NSUInteger index, BOOL *stop) {
        if (HCMIsLiveChatRenderer(wrapper)) {
            [emptySections addIndex:index];
            return;
        }
        id itemSection = HCMCall(wrapper, @"itemSectionRenderer");
        if (itemSection && (HCMPruneItemSection(itemSection) ||
                            HCMIsDirectDescriptionMembersSection(itemSection))) {
            [emptySections addIndex:index];
        }
    }];
    if (emptySections.count) {
        @try {
            [sections removeObjectsAtIndexes:emptySections];
            NSLog(@"[HideChannelMembers] removed %lu empty sections",
                  (unsigned long)emptySections.count);
        } @catch (NSException *exception) {}
    }
}

static NSArray *HCMFilteredSections(NSArray *sections) {
    if (![sections isKindOfClass:[NSArray class]] || !sections.count) return sections;
    NSMutableArray *filtered = [NSMutableArray arrayWithCapacity:sections.count];
    for (id section in sections) {
        // The inspector confirmed addSectionsFromArray: receives YTIItemSectionRenderer.
        if (HCMIsLiveChatRenderer(section)) continue;
        if (HCMPruneItemSection(section)) continue;
        if (HCMIsDirectDescriptionMembersSection(section)) {
            NSLog(@"[HideChannelMembers] dropped video-description member card");
            continue;
        }
        [filtered addObject:section];
    }
    return filtered;
}

%hook YTSectionListViewController
- (void)loadWithModel:(id)model {
    @try { HCMPruneModel(model); } @catch (NSException *exception) {}
    %orig;
}
%end

%hook YTInnerTubeCollectionViewController
- (void)loadWithModel:(id)model {
    @try { HCMPruneModel(model); } @catch (NSException *exception) {}
    %orig;
}
- (void)addSectionsFromArray:(NSArray *)sections {
    NSArray *filtered = sections;
    @try { filtered = HCMFilteredSections(sections); }
    @catch (NSException *exception) { filtered = sections; }
    %orig(filtered);
}
%end


// Video Description uses Texture / AsyncDisplayKit. The target card's
// visual shape is stable across translations even when its heading is
// rendered into an asynchronous layer rather than UILabel.
// Based on tap-inspector output:
// YTEngagementPanelView -> YTAsyncCollectionView -> _ASCollectionViewCell
// with a lower, inset _ASDisplayView member card next to ASScrollView.
static char kHCMCardViewMarker;

static BOOL HCMIsDescriptionPanelCollection(UIView *collection) {
    for (UIView *parent=collection; parent; parent=parent.superview) {
        if ([NSStringFromClass([parent class]) isEqualToString:@"YTEngagementPanelView"])
            return YES;
    }
    return NO;
}
static BOOL HCMIsDisplayView(UIView *view) {
    return [NSStringFromClass([view class]) isEqualToString:@"_ASDisplayView"];
}
static BOOL HCMHasAvatarCarouselSibling(UIView *card) {
    UIView *parent=card.superview;
    if (!parent || !HCMIsDisplayView(parent)) return NO;
    NSUInteger displayCount=0;
    NSUInteger scrollCount=0;
    for (UIView *child in parent.subviews) {
        NSString *name=NSStringFromClass([child class]);
        if ([name isEqualToString:@"ASScrollView"]) scrollCount++;
        if ([name isEqualToString:@"_ASDisplayView"]) displayCount++;
    }
    return scrollCount>=1 && displayCount>=2 && parent.subviews.count<=6;
}

static BOOL HCMIsMemberCardShape(UIView *view, UICollectionViewCell *cell) {
    if (!HCMIsDisplayView(view)) return NO;
    CGRect bounds=cell.contentView.bounds;
    if (bounds.size.width<260 || bounds.size.height<160) return NO;
    CGRect r=[view convertRect:view.bounds toView:cell.contentView];
    if (r.size.height<52 || r.size.height>165) return NO;
    if (r.size.width<bounds.size.width*0.78 ||
        r.size.width>bounds.size.width*1.03) return NO;
    if (r.origin.x<6 || r.origin.x>55) return NO;
    if (r.origin.y<bounds.size.height*0.35) return NO;
    if (CGRectGetMaxY(r)>bounds.size.height+6) return NO;
    if ((bounds.size.height-CGRectGetMaxY(r))>45) return NO;

    // The inspector reported a 406x88 card with two _ASDisplayView
    // descendants and ASScrollView as a sibling inside the same cell.
    if (!HCMHasAvatarCarouselSibling(view)) return NO;
    NSUInteger displayChildren=0;
    for (UIView *child in view.subviews) {
        if (HCMIsDisplayView(child)) displayChildren++;
    }
    return displayChildren>=1;
}
static UIView *HCMFindCard(UIView *view, UICollectionViewCell *cell,
                           NSUInteger depth, NSUInteger *visited) {
    if (!view || depth>22 || *visited>300) return nil;
    (*visited)++;
    // Check children first: select only the narrow, inset card—not the
    // enclosing cell which also contains Videos/About.
    for (UIView *child in view.subviews) {
        UIView *found=HCMFindCard(child,cell,depth+1,visited);
        if (found) return found;
    }
    if (HCMIsMemberCardShape(view,cell)) return view;
    return nil;
}
static void HCMRestoreCardViews(UIView *view, NSUInteger depth) {
    if (!view || depth>24) return;
    if (objc_getAssociatedObject(view,&kHCMCardViewMarker)) {
        view.hidden=NO;
        objc_setAssociatedObject(view,&kHCMCardViewMarker,nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    for(UIView *sub in view.subviews)
        HCMRestoreCardViews(sub,depth+1);
}

%hook YTAsyncCollectionView
- (void)layoutSubviews {
    %orig;
    if (![NSThread isMainThread] ||
        !HCMIsDescriptionPanelCollection((UIView *)self)) return;
    NSArray *cells=[[(UICollectionView *)self visibleCells] copy];
    for (UICollectionViewCell *cell in cells) {
        if (![NSStringFromClass([cell class])
               isEqualToString:@"_ASCollectionViewCell"]) continue;
        NSUInteger visited=0;
        UIView *card=HCMFindCard(cell.contentView,cell,0,&visited);
        if (!card || objc_getAssociatedObject(card,&kHCMCardViewMarker))
            continue;
        // No language matching, no channel ID matching, and do not hide
        // the enclosing collection cell: it contains unrelated sections.
        card.hidden=YES;
        objc_setAssociatedObject(card,&kHCMCardViewMarker,@YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSLog(@"[HideChannelMembers] hid language-independent member card view");
    }
}
%end

%hook _ASCollectionViewCell
- (void)prepareForReuse {
    %orig;
    HCMRestoreCardViews(((UICollectionViewCell *)self).contentView,0);
}
%end


// Hide suggestions on the search-entry controller, including the separate
// zero-prefix/trending refresh path. Never touch submitted search results.
static BOOL HCMIsSuggestionCollection(id controller, UIView *view) {
    if (![view isKindOfClass:[UICollectionView class]] &&
        ![view isKindOfClass:[UITableView class]]) return NO;
    // Prefer the actual suggestion-list ivar. It was _suggestionsView in
    // earlier YouTube versions; guard all runtime lookups.
    for (NSString *key in @[@"_suggestionsView", @"_suggestionsCollectionView",
                             @"_suggestionsTableView", @"_searchSuggestionsView",
                             @"_zeroStateSuggestionsView"]) {
        Ivar ivar = class_getInstanceVariable([controller class], key.UTF8String);
        if (ivar && ivar_getTypeEncoding(ivar)[0] == '@' &&
            object_getIvar(controller, ivar) == view) return YES;
    }
    NSString *name = [NSStringFromClass(view.class) lowercaseString];
    if ([name containsString:@"suggestion"] || [name containsString:@"zerostate"] ||
        [name containsString:@"zeroprefix"]) return YES;
    // The native YTSearchViewController is the data source of its suggestion
    // collection. Submitted results have their own controller/data source.
    id dataSource = nil;
    if ([view isKindOfClass:[UICollectionView class]])
        dataSource = [(UICollectionView *)view dataSource];
    else
        dataSource = [(UITableView *)view dataSource];
    return dataSource == controller;
}
static void HCMHideSearchLists(id controller, UIView *root, NSUInteger depth) {
    if (!root || depth > 18) return;
    for (UIView *child in root.subviews) {
        if (HCMIsSuggestionCollection(controller, child)) {
            child.hidden = YES;
            continue;
        }
        // Avoid walking into a separate embedded result controller.
        UIResponder *owner = child.nextResponder;
        if ([owner isKindOfClass:[UIViewController class]] && owner != controller)
            continue;
        HCMHideSearchLists(controller, child, depth + 1);
    }
}
static void HCMApplySearchEntry(id controller) {
    if (![NSThread isMainThread] ||
        ![controller isKindOfClass:[UIViewController class]]) return;
    UIViewController *vc = (UIViewController *)controller;
    if (!vc.isViewLoaded) return;
    HCMHideSearchLists(controller, vc.view, 0);
}
%hook YTSearchViewController
- (void)setSuggestions:(id)suggestions {
    // Pass an empty array to clear earlier cached content, rather than
    // leaving the existing list untouched by dropping the call.
    %orig(@[]);
    HCMApplySearchEntry(self);
}
- (void)updateWithSuggestions:(id)suggestions shouldFillRefinements:(BOOL)fill {
    %orig(@[], NO);
    HCMApplySearchEntry(self);
}
- (void)zeroStateSuggestionsDidRefresh {
    %orig;
    HCMApplySearchEntry(self);
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    HCMApplySearchEntry(self);
}
- (void)viewDidLayoutSubviews {
    %orig;
    HCMApplySearchEntry(self);
}
%end

// Additional rendering fallback for the dedicated suggestion cell, including
// cached/late updates that bypass the usual suggestion setter.
%hook YTSearchSuggestionCollectionViewCell
- (void)layoutSubviews {
    %orig;
    UIView *view = (UIView *)self;
    view.hidden = YES;
}
%end

%hook YTPersonalizedSuggestionsCacheProvider
- (id)activeCache {
    return nil;
}
%end
