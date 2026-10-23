// HideChannelMembers 0.5.0 (experimental: video description recognition card)
// Target identified by MemberShelfInspector on YouTube iOS 21.42.4:
// YTISectionListRenderer -> YTISectionListSupportedRenderers ->
// YTIItemSectionRenderer -> YTIItemSectionSupportedRenderers ->
// YTIElementRenderer.description contains "member_recognition_shelf".
// NO global YTIElementRenderer hook: only prune known section arrays.
#import <Foundation/Foundation.h>
#import <objc/message.h>

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
    for (NSString *needle in needles) {
        if ([text rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound)
            return YES;
    }
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
