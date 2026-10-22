// Experimental: hide member recognition shelves on channel Home pages.
#import <Foundation/Foundation.h>
#import <objc/message.h>

static id CMObject(id obj, NSString *method) {
    SEL sel = NSSelectorFromString(method);
    return obj && [obj respondsToSelector:sel]
        ? ((id (*)(id, SEL))objc_msgSend)(obj, sel) : nil;
}
static BOOL CMBool(id obj, NSString *method) {
    SEL sel = NSSelectorFromString(method);
    return obj && [obj respondsToSelector:sel]
        ? ((BOOL (*)(id, SEL))objc_msgSend)(obj, sel) : NO;
}
static NSMutableArray *CMContents(id obj) {
    id a = CMObject(obj, @"contentsArray");
    return [a isKindOfClass:[NSMutableArray class]] ? a : nil;
}
static BOOL CMIsMemberShelf(id item) {
    if (!item) return NO;
    if (CMBool(item, @"hasRecognitionShelfRenderer")) return YES;
    if (CMObject(item, @"recognitionShelfRenderer")) return YES;
    NSString *cls = [NSStringFromClass([item class]) lowercaseString];
    if ([cls containsString:@"recognitionshelf"]) return YES;
    NSString *d = [[item description] lowercaseString];
    return [d containsString:@"recognitionshelfrenderer"] ||
           [d containsString:@"recognition_shelf"] ||
           [d containsString:@"member_recognition_shelf"] ||
           [d containsString:@"member-recognition-shelf"];
}

%hook YTSectionListViewController
- (void)loadWithModel:(id)model {
    NSMutableArray *sections = CMContents(model);
    if (sections) {
        for (id wrapper in [sections copy]) {
            id sec = CMObject(wrapper, @"itemSectionRenderer");
            NSMutableArray *items = CMContents(sec);
            if (!items) continue;
            NSUInteger original = [items count];
            for (id item in [items copy]) {
                if (CMIsMemberShelf(item)) [items removeObject:item];
            }
            if (original > 0 && items.count == 0)
                [sections removeObject:wrapper];
        }
    }
    %orig;
}
%end

%hook YTIElementRenderer
- (NSData *)elementData {
    NSString *d = [[(id)self description] lowercaseString];
    if ([d containsString:@"recognition_shelf"] ||
        [d containsString:@"recognition-shelf"] ||
        [d containsString:@"member_recognition_shelf"])
        return nil;
    return %orig;
}
%end
