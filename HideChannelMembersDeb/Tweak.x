// HideChannelMembers 0.8.0 (language-independent recognition card structure)
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

static BOOL HCMIsMemberItem(id item) {
    id element = HCMCall(item, @"elementRenderer");
    if (!element) return NO;
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
