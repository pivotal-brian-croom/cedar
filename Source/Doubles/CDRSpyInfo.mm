#import "CDRSpyInfo.h"
#import "CDRSpy.h"
#import "CedarDoubleImpl.h"
#import <objc/runtime.h>
#if __has_include(<objc/objc-arc.h>) // for GNUstep
extern "C" {
#import <objc/objc-arc.h>
}
#endif

static NSMapTable *currentSpies__; // Maps non-zeroing weak object references to strong CDRSpyInfo instances

@interface CDRSpyInfo ()
@property (nonatomic, assign) id originalObject;
@property (nonatomic, weak) id weakOriginalObject;
@end

@implementation CDRSpyInfo {
    __weak id _weakOriginalObject;
}

+ (void)initialize {
    currentSpies__ = [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsOpaqueMemory|NSPointerFunctionsOpaquePersonality
                                               valueOptions:NSMapTableStrongMemory|NSMapTableObjectPointerPersonality
                                                   capacity:0];
}

+ (void)storeSpyInfoForObject:(id)object {
    CDRSpyInfo *spyInfo = [[[CDRSpyInfo alloc] init] autorelease];
    spyInfo.originalObject = object;
    spyInfo.weakOriginalObject = object;
    spyInfo.publicClass = [object class];
    spyInfo.spiedClass = object_getClass(object);
    spyInfo.cedarDouble = [[[CedarDoubleImpl alloc] initWithDouble:object] autorelease];

    //! Acquire exclusive lock
    [currentSpies__ setObject:spyInfo forKey:object];
    //! Release exclusive lock
}

+ (BOOL)clearSpyInfoForObject:(id)object {
    //! Acquire exclusive lock
    BOOL clearedSpy = NO;
    CDRSpyInfo *spyInfo = [CDRSpyInfo spyInfoForObject:object]; // may need an unlocked version of this
    if (spyInfo) {
        spyInfo.originalObject = nil;
        spyInfo.weakOriginalObject = nil;
        [currentSpies__ removeObjectForKey:object];
        clearedSpy = YES;
    }
    //! Release exclusive lock
    return clearedSpy;
}

- (void)dealloc {
    self.publicClass = nil;
    self.spiedClass = nil;
    self.originalObject = nil;
    self.weakOriginalObject = nil;
    self.cedarDouble = nil;
    [super dealloc];
}

+ (CedarDoubleImpl *)cedarDoubleForObject:(id)object {
    return [[self spyInfoForObject:object] cedarDouble];
}

+ (Class)publicClassForObject:(id)object {
    return [[self spyInfoForObject:object] publicClass];
}

+ (CDRSpyInfo *)spyInfoForObject:(id)object {
    //! Acquire concurrent lock
    CDRSpyInfo *spyInfo = [currentSpies__ objectForKey:object];
    //! Release concurrent lock
    return spyInfo;
}

- (IMP)impForSelector:(SEL)selector {
    BOOL yieldToSpiedClass = (
        sel_isEqual(selector, @selector(addObserver:forKeyPath:options:context:)) ||
        sel_isEqual(selector, @selector(didChange:valuesAtIndexes:forKey:)) ||
        sel_isEqual(selector, @selector(mutableArrayValueForKey:)) ||
        sel_isEqual(selector, @selector(mutableOrderedSetValueForKey:)) ||
        sel_isEqual(selector, @selector(mutableSetValueForKey:)) ||
        sel_isEqual(selector, @selector(removeObserver:forKeyPath:)) ||
        sel_isEqual(selector, @selector(removeObserver:forKeyPath:context:)) ||
        sel_isEqual(selector, @selector(setValue:forKey:)) ||
        sel_isEqual(selector, @selector(valueForKey:)) ||
        sel_isEqual(selector, @selector(willChange:valuesAtIndexes:forKey:)) ||
        strcmp(class_getName(self.publicClass), class_getName(self.spiedClass))
    );

    if (yieldToSpiedClass) {
        return NULL;
    }

    Method originalMethod = class_getInstanceMethod(self.spiedClass, selector);
    return method_getImplementation(originalMethod);
}

+ (void)afterEach {
    //! Acquire exclusive lock
    NSMutableArray *allSpyInfo = [NSMutableArray arrayWithCapacity:currentSpies__.count];
    for (CDRSpyInfo *spyInfo in [currentSpies__ objectEnumerator]) {
        [allSpyInfo addObject:spyInfo];
    }

    for (CDRSpyInfo *spyInfo in allSpyInfo) {
        id object = spyInfo.weakOriginalObject;
        if (object) {
            Cedar::Doubles::CDR_stop_spying_on(object); // May need unlocked version of this
        }
    }

    [currentSpies__ removeAllObjects];
    //! Release exclusive lock
}

#pragma mark - Accessors

- (id)weakOriginalObject {
    return objc_loadWeak(&_weakOriginalObject);
}

- (void)setWeakOriginalObject:(id)originalObject {
    objc_storeWeak(&_weakOriginalObject, originalObject);
}

@end
