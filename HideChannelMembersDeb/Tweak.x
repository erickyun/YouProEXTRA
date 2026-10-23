// HideChannelMembers 0.7.0 (localized AsyncDisplayKit member-card detection)
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


// Video Description is rendered by Texture/AsyncDisplayKit, not UILabel.
// Localized text is supplied to ASTextNode after protobuf parsing.
// The 0.4.0 channel Home section filter above is intentionally unchanged.
static char kHCMIdentifiedMemberNode;
static char kHCMHiddenMemberCell;

static BOOL HCMIsLocalizedThanks(NSString *text) {
    if (![text isKindOfClass:[NSString class]]) return NO;
    NSStringCompareOptions opts = NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch;
    for (NSString *phrase in @[
        @"Kanal üyelerine teşekkürler",
        @"Kanal üyelerimize teşekkürler",
        @"Thank you, channel members"
    ]) {
        if ([text rangeOfString:phrase options:opts].location != NSNotFound)
            return YES;
    }
    return NO;
}
static BOOL HCMIsTextureTextNode(id node) {
    Class textNode=NSClassFromString(@"ASTextNode");
    if (textNode && [node isKindOfClass:textNode]) return YES;
    NSString *cls=NSStringFromClass([node class]);
    return [cls hasSuffix:@"TextNode"] || [cls hasSuffix:@"TextNode2"];
}
static BOOL HCMNodeContainsMembersTitle(id node, NSUInteger depth, NSUInteger *visited) {
    if (!node || depth>22 || *visited>350) return NO;
    (*visited)++;
    if (HCMIsTextureTextNode(node)) {
        @try {
            id attributed=HCMCall(node, @"attributedText");
            if ([attributed isKindOfClass:[NSAttributedString class]] &&
                HCMIsLocalizedThanks([(NSAttributedString *)attributed string])) return YES;
            id text=HCMCall(node, @"text");
            if ([text isKindOfClass:[NSString class]] &&
                HCMIsLocalizedThanks(text)) return YES;
        } @catch (NSException *exception) {}
    }
    @try {
        id children=HCMCall(node, @"subnodes");
        if ([children isKindOfClass:[NSArray class]]) {
            for (id sub in children) {
                if (HCMNodeContainsMembersTitle(sub,depth+1,visited)) return YES;
            }
        }
    } @catch (NSException *exception) {}
    return NO;
}
static BOOL HCMIsEngagementPanel(UIView *view) {
    for (UIView *parent=view; parent; parent=parent.superview) {
        if ([NSStringFromClass([parent class]) isEqualToString:@"YTEngagementPanelView"])
            return YES;
    }
    return NO;
}
static BOOL HCMMarkedOrIdentified(id node) {
    if (!node) return NO;
    if (objc_getAssociatedObject(node,&kHCMIdentifiedMemberNode)) return YES;
    NSUInteger count=0;
    if (HCMNodeContainsMembersTitle(node,0,&count)) {
        objc_setAssociatedObject(node,&kHCMIdentifiedMemberNode,@YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return YES;
    }
    return NO;
}
static id HCMCellNodeAncestor(id node) {
    Class cellNodeClass=NSClassFromString(@"ASCellNode");
    for(NSUInteger i=0;node && i<24;i++) {
        if (cellNodeClass && [node isKindOfClass:cellNodeClass])
            return node;
        node=HCMCall(node,@"supernode");
    }
    return nil;
}
// The _ASDisplayView backing ASTextNode exposes -asyncdisplaykit_node.
// Unlike UILabel, the text is available through ASTextNode.attributedText.
static id HCMFindCardNodeInsideView(UIView *view, NSUInteger *visited) {
    if (!view || *visited>450) return nil;
    (*visited)++;
    if ([NSStringFromClass([view class]) isEqualToString:@"_ASDisplayView"]) {
        id node=HCMCall(view,@"asyncdisplaykit_node");
        if (node && HCMIsTextureTextNode(node)) {
            @try {
                id attributed=HCMCall(node,@"attributedText");
                if ([attributed isKindOfClass:[NSAttributedString class]] &&
                    HCMIsLocalizedThanks([(NSAttributedString *)attributed string]))
                    return HCMCellNodeAncestor(node);
            } @catch (NSException *exception) {}
        }
    }
    for(UIView *child in view.subviews) {
        id cell=HCMFindCardNodeInsideView(child,visited);
        if (cell) return cell;
    }
    return nil;
}

%hook YTAsyncCollectionView
// When the recognition cell node is identified, let Texture measure it at
// effectively zero height so other Description sections can move up.
- (CGSize)sizeForElement:(id)element {
    CGSize original=%orig;
    if (![NSThread isMainThread] || !HCMIsEngagementPanel((UIView *)self))
        return original;
    id node=HCMCall(element, @"node");
    if (node && HCMMarkedOrIdentified(node))
        return CGSizeMake(original.width,0.5);
    return original;
}
- (void)layoutSubviews {
    %orig;
    if (![NSThread isMainThread] || !HCMIsEngagementPanel((UIView *)self))
        return;
    BOOL shouldReflow=NO;
    for (UICollectionViewCell *cell in [(UICollectionView *)self visibleCells]) {
        if (objc_getAssociatedObject(cell,&kHCMHiddenMemberCell)) {
            cell.hidden=YES;
            continue;
        }
        NSUInteger visited=0;
        id cellNode=HCMFindCardNodeInsideView(cell.contentView,&visited);
        if (!cellNode) continue;
        BOOL newlyIdentified=!objc_getAssociatedObject(cellNode,&kHCMIdentifiedMemberNode);
        objc_setAssociatedObject(cellNode,&kHCMIdentifiedMemberNode,@YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(cell,&kHCMHiddenMemberCell,@YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        cell.hidden=YES;
        if (newlyIdentified) shouldReflow=YES;
        NSLog(@"[HideChannelMembers] collapsed localized Description member card");
    }
    if (shouldReflow) {
        [[(UICollectionView *)self collectionViewLayout] invalidateLayout];
    }
}
%end
