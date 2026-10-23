// HideChannelMembers 0.4.0
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

static BOOL HCMIsMemberItem(id item) {
    id element = HCMCall(item, @"elementRenderer");
    if (!element) return NO;
    @try {
        NSString *description = [element description];
        return [description isKindOfClass:[NSString class]] &&
            [description rangeOfString:@"member_recognition_shelf"
                options:NSCaseInsensitiveSearch].location != NSNotFound;
    } @catch (NSException *exception) {
        return NO;
    }
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
        if (itemSection && HCMPruneItemSection(itemSection)) {
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
