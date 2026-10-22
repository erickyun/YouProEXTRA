// Hide Channel Members v0.2.0 — cautious recognition-shelf filter.
// The previous broad YTIElementRenderer hook was removed because
// invoking -description during global rendering may crash YouTube.
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

static id HCMCallObject(id obj, SEL sel) {
    if (!obj || ![obj respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(obj, sel);
}

static NSMutableArray *HCMContents(id object) {
    id result = HCMCallObject(object, @selector(contentsArray));
    if ([result isKindOfClass:[NSMutableArray class]]) return result;
    return nil;
}

static BOOL HCMIsMemberRecognition(id renderer) {
    if (!renderer) return NO;

    SEL has = NSSelectorFromString(@"hasRecognitionShelfRenderer");
    if ([renderer respondsToSelector:has]) {
        BOOL present = ((BOOL (*)(id, SEL))objc_msgSend)(renderer, has);
        if (present) return YES;
    }

    SEL getter = NSSelectorFromString(@"recognitionShelfRenderer");
    if ([renderer respondsToSelector:getter] && HCMCallObject(renderer, getter))
        return YES;

    NSString *className = NSStringFromClass(object_getClass(renderer));
    return [className rangeOfString:@"RecognitionShelf"
                           options:NSCaseInsensitiveSearch].location != NSNotFound;
}

%hook YTSectionListViewController
- (void)loadWithModel:(id)model {
    // Only operate on known protobuf array-style section models, like YTLite.
    // Never inspect descriptions, override elementData, or return nil for global renderers.
    @try {
        NSMutableArray *sections = HCMContents(model);
        if (sections) {
            for (id sectionWrapper in [sections copy]) {
                id section = HCMCallObject(sectionWrapper, @selector(itemSectionRenderer));
                NSMutableArray *items = HCMContents(section);
                if (!items || items.count == 0) continue;

                NSMutableIndexSet *removeIndexes = [NSMutableIndexSet indexSet];
                [items enumerateObjectsUsingBlock:^(id item, NSUInteger idx, BOOL *stop) {
                    if (HCMIsMemberRecognition(item)) [removeIndexes addIndex:idx];
                }];
                if (removeIndexes.count == 0) continue;

                [items removeObjectsAtIndexes:removeIndexes];
                if (items.count == 0 && [sections containsObject:sectionWrapper]) {
                    [sections removeObject:sectionWrapper];
                }
            }
        }
    } @catch (NSException *exception) {
        // Always allow the original YouTube controller to load.
        NSLog(@"[HideChannelMembers] skipped unexpected model: %@", exception.name);
    }
    %orig;
}
%end
