// HideChannelMembers 0.3.0 - filter recognition shelves at the iOS feed level.
// Inspired by YouTube iOS section filtering in PoomSmart/YTUnShorts.
// Experimental: tested by CI build, not by an actual YouTube 21.42.4 instance.
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

static id HCMObject(id obj, SEL selector) {
    if (!obj || ![obj respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(obj, selector);
}
static BOOL HCMBool(id obj, SEL selector) {
    if (!obj || ![obj respondsToSelector:selector]) return NO;
    return ((BOOL (*)(id, SEL))objc_msgSend)(obj, selector);
}
static BOOL HCMContains(NSString *string, NSString *term) {
    return [string isKindOfClass:[NSString class]] &&
      [string rangeOfString:term options:NSCaseInsensitiveSearch].location != NSNotFound;
}
static BOOL HCMTagged(id object) {
    if (!object) return NO;
    if (HCMBool(object, NSSelectorFromString(@"hasRecognitionShelfRenderer"))) return YES;
    if (HCMObject(object, NSSelectorFromString(@"recognitionShelfRenderer"))) return YES;

    NSString *className = NSStringFromClass(object_getClass(object));
    if (HCMContains(className, @"RecognitionShelf")) return YES;

    // ELM renderers and legacy protobuf sections use different templates.
    // Avoid generic "member" matching to preserve member-only videos.
    NSString *description = [object description];
    return HCMContains(description, @"member_recognition_shelf") ||
           HCMContains(description, @"recognition_shelf") ||
           HCMContains(description, @"recognitionShelfRenderer") ||
           HCMContains(description, @"recognition-shelf");
}
static BOOL HCMMatched(id obj) {
    if (HCMTagged(obj)) return YES;
    id element = HCMObject(obj, NSSelectorFromString(@"elementRenderer"));
    return element && HCMTagged(element);
}
static NSMutableArray *HCMContents(id obj) {
    id contents = HCMObject(obj, NSSelectorFromString(@"contentsArray"));
    return [contents isKindOfClass:[NSMutableArray class]] ? contents : nil;
}
static NSArray *HCMFilterSections(NSArray *sections) {
    if (![sections isKindOfClass:[NSArray class]] || sections.count == 0)
        return sections;
    NSMutableArray *kept = [NSMutableArray arrayWithCapacity:sections.count];
    for (id section in sections) {
        BOOL removeSection = NO;
        NSMutableArray *items = HCMContents(section);
        if (items && items.count) {
            NSMutableIndexSet *removed = [NSMutableIndexSet indexSet];
            [items enumerateObjectsUsingBlock:^(id obj, NSUInteger index, BOOL *stop) {
                if (HCMMatched(obj)) [removed addIndex:index];
            }];
            if (removed.count) {
                [items removeObjectsAtIndexes:removed];
                removeSection = (items.count == 0);
            }
        }
        if (!removeSection && !items && HCMMatched(section)) removeSection = YES;
        if (!removeSection) [kept addObject:section];
        else NSLog(@"[HideChannelMembers] Removed recognition shelf section");
    }
    return kept;
}

%hook YTInnerTubeCollectionViewController
- (void)addSectionsFromArray:(NSArray *)sections {
    NSArray *filtered = sections;
    @try {
        filtered = HCMFilterSections(sections);
    } @catch (NSException *e) {
        NSLog(@"[HideChannelMembers] Section filter exception: %@", e.name);
    }
    %orig(filtered);
}
- (void)displaySectionsWithReloadingSectionControllerByRenderer:(id)renderer {
    @try {
        id sections = [(id)self valueForKey:@"_sectionRenderers"];
        if ([sections isKindOfClass:[NSArray class]]) {
            NSArray *kept = HCMFilterSections(sections);
            if (kept.count != [(NSArray *)sections count]) {
                [(id)self setValue:[kept mutableCopy] forKey:@"_sectionRenderers"];
            }
        }
    } @catch (NSException *e) {
        // If the ivar changes in a future YouTube update, leave it untouched.
    }
    %orig;
}
%end

// A second path for older channel section list pages.
%hook YTSectionListViewController
- (void)loadWithModel:(id)model {
    @try {
        NSMutableArray *outer = HCMContents(model);
        if (outer) {
            for (id wrapper in [outer copy]) {
                id section = HCMObject(wrapper, NSSelectorFromString(@"itemSectionRenderer"));
                NSMutableArray *items = HCMContents(section);
                if (!items) continue;
                NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
                [items enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                    if (HCMMatched(obj)) [indexes addIndex:idx];
                }];
                if (indexes.count) {
                    [items removeObjectsAtIndexes:indexes];
                    if (!items.count) [outer removeObject:wrapper];
                }
            }
        }
    } @catch (NSException *e) {
        NSLog(@"[HideChannelMembers] Legacy section exception: %@", e.name);
    }
    %orig;
}
%end

// Newer ELM-based shelves can appear outside a recognized protobuf section.
// Match only the exact recognition-shelf template, unlike a broad renderer block.
%hook YTIElementRenderer
- (NSData *)elementData {
    @try {
        NSString *desc = [(id)self description];
        if (HCMContains(desc, @"member_recognition_shelf") ||
            HCMContains(desc, @"recognition_shelf") ||
            HCMContains(desc, @"recognition-shelf")) {
            return nil;
        }
    } @catch (NSException *e) {}
    return %orig;
}
%end
