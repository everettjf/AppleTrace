/**
 * AppleTrace objc_msgSend tracing without HookZz.
 *
 * This arm64-only implementation uses fishhook-style symbol rebinding plus
 * an assembly wrapper so objc_msgSend arguments and return registers survive
 * the tracing callbacks.
 */

#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <pthread.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <sys/mman.h>

#import "appletrace.h"

#if !defined(__arm64__)
#error AppleTrace objc_msgSend hook currently supports arm64 only.
#endif

typedef void (*APTObjcMsgSendFunction)(void);

#ifdef __LP64__
typedef struct mach_header_64 mach_header_t;
typedef struct segment_command_64 segment_command_t;
typedef struct section_64 section_t;
typedef struct nlist_64 nlist_t;
#define LC_SEGMENT_ARCH_DEPENDENT LC_SEGMENT_64
#else
typedef struct mach_header mach_header_t;
typedef struct segment_command segment_command_t;
typedef struct section section_t;
typedef struct nlist nlist_t;
#define LC_SEGMENT_ARCH_DEPENDENT LC_SEGMENT
#endif

struct APTRebinding {
    const char *name;
    void *replacement;
    void **replaced;
};

struct APTRebindingsEntry {
    struct APTRebinding *rebindings;
    size_t count;
    struct APTRebindingsEntry *next;
};

typedef struct APTTraceNode {
    char *name;
    struct APTTraceNode *previous;
} APTTraceNode;

static uintptr_t gLogSelectorStart = 0;
static uintptr_t gLogSelectorEnd = 0;
static uintptr_t gLogClassStart = 0;
static uintptr_t gLogClassEnd = 0;
static int gLogAllSelectors = 1;
static int gLogAllClasses = 1;
static __thread int gTraceGuard = 0;
static pthread_key_t gTraceStackKey;
static pthread_once_t gTraceStackKeyOnce = PTHREAD_ONCE_INIT;
static dispatch_once_t gHookInstallOnce;
static APTObjcMsgSendFunction apt_original_objc_msgSend = NULL;
static struct APTRebindingsEntry *gRebindingsHead = NULL;
static BOOL gHookInstalled = NO;

__attribute__((used)) static void apt_before_objc_msgSend(id object, SEL selector);
__attribute__((used)) static void apt_after_objc_msgSend(void);
static void apt_configure_trace_ranges(void);
static int apt_rebind_symbols(struct APTRebinding rebindings[], size_t count);
extern void apt_objc_msgSend_wrapper(void);

static BOOL apt_bool_from_environment(NSString *key, BOOL fallback) {
    NSString *value = [[[NSProcessInfo processInfo] environment] objectForKey:key];
    if (!value.length) {
        return fallback;
    }

    NSString *normalized = value.lowercaseString;
    return ![normalized isEqualToString:@"0"] &&
           ![normalized isEqualToString:@"false"] &&
           ![normalized isEqualToString:@"no"];
}

static BOOL apt_install_objc_msgsend_hook(void) {
    __block BOOL installed = NO;
    dispatch_once(&gHookInstallOnce, ^{
        apt_configure_trace_ranges();
        apt_original_objc_msgSend = (APTObjcMsgSendFunction)dlsym(RTLD_DEFAULT, "objc_msgSend");
        if (apt_original_objc_msgSend == NULL) {
            NSLog(@"AppleTrace: failed to resolve objc_msgSend before rebinding");
            return;
        }

        struct APTRebinding rebinding = {
            .name = "objc_msgSend",
            .replacement = (void *)apt_objc_msgSend_wrapper,
            .replaced = (void **)&apt_original_objc_msgSend,
        };

        int status = apt_rebind_symbols(&rebinding, 1);
        if (status == 0 && apt_original_objc_msgSend != NULL) {
            gHookInstalled = YES;
        }
    });

    installed = gHookInstalled;
    return installed;
}

__asm__(
".text\n"
".align 2\n"
".globl _apt_objc_msgSend_wrapper\n"
"_apt_objc_msgSend_wrapper:\n"
"sub sp, sp, #0x1C0\n"
"stp x29, x30, [sp, #0x1B0]\n"
"mov x29, sp\n"
"add x11, sp, #0x1C0\n"
"ldp x9, x10, [x11, #0x00]\n"
"stp x9, x10, [sp, #0x00]\n"
"ldp x9, x10, [x11, #0x10]\n"
"stp x9, x10, [sp, #0x10]\n"
"ldp x9, x10, [x11, #0x20]\n"
"stp x9, x10, [sp, #0x20]\n"
"ldp x9, x10, [x11, #0x30]\n"
"stp x9, x10, [sp, #0x30]\n"
"ldp x9, x10, [x11, #0x40]\n"
"stp x9, x10, [sp, #0x40]\n"
"ldp x9, x10, [x11, #0x50]\n"
"stp x9, x10, [sp, #0x50]\n"
"ldp x9, x10, [x11, #0x60]\n"
"stp x9, x10, [sp, #0x60]\n"
"ldp x9, x10, [x11, #0x70]\n"
"stp x9, x10, [sp, #0x70]\n"
"stp x0, x1, [sp, #0x80]\n"
"stp x2, x3, [sp, #0x90]\n"
"stp x4, x5, [sp, #0xA0]\n"
"stp x6, x7, [sp, #0xB0]\n"
"str x8, [sp, #0xC0]\n"
"stp q0, q1, [sp, #0xD0]\n"
"stp q2, q3, [sp, #0xF0]\n"
"stp q4, q5, [sp, #0x110]\n"
"stp q6, q7, [sp, #0x130]\n"
"bl _apt_before_objc_msgSend\n"
"ldp x0, x1, [sp, #0x80]\n"
"ldp x2, x3, [sp, #0x90]\n"
"ldp x4, x5, [sp, #0xA0]\n"
"ldp x6, x7, [sp, #0xB0]\n"
"ldr x8, [sp, #0xC0]\n"
"ldp q0, q1, [sp, #0xD0]\n"
"ldp q2, q3, [sp, #0xF0]\n"
"ldp q4, q5, [sp, #0x110]\n"
"ldp q6, q7, [sp, #0x130]\n"
"adrp x16, _apt_original_objc_msgSend@PAGE\n"
"ldr x16, [x16, _apt_original_objc_msgSend@PAGEOFF]\n"
"blr x16\n"
"stp x0, x1, [sp, #0x80]\n"
"stp q0, q1, [sp, #0xD0]\n"
"stp q2, q3, [sp, #0xF0]\n"
"bl _apt_after_objc_msgSend\n"
"ldp x0, x1, [sp, #0x80]\n"
"ldp q0, q1, [sp, #0xD0]\n"
"ldp q2, q3, [sp, #0xF0]\n"
"ldp x29, x30, [sp, #0x1B0]\n"
"add sp, sp, #0x1C0\n"
"ret\n"
);

static void apt_free_trace_stack(void *pointer) {
    APTTraceNode *node = (APTTraceNode *)pointer;
    while (node) {
        APTTraceNode *previous = node->previous;
        free(node->name);
        free(node);
        node = previous;
    }
}

static void apt_make_trace_stack_key(void) {
    pthread_key_create(&gTraceStackKey, apt_free_trace_stack);
}

static APTTraceNode *apt_trace_stack_top(void) {
    pthread_once(&gTraceStackKeyOnce, apt_make_trace_stack_key);
    return (APTTraceNode *)pthread_getspecific(gTraceStackKey);
}

static void apt_trace_stack_set(APTTraceNode *node) {
    pthread_once(&gTraceStackKeyOnce, apt_make_trace_stack_key);
    pthread_setspecific(gTraceStackKey, node);
}

static void apt_trace_stack_push(char *name) {
    APTTraceNode *node = malloc(sizeof(APTTraceNode));
    if (!node) {
        free(name);
        return;
    }

    node->name = name;
    node->previous = apt_trace_stack_top();
    apt_trace_stack_set(node);
}

static APTTraceNode *apt_trace_stack_pop(void) {
    APTTraceNode *node = apt_trace_stack_top();
    if (node) {
        apt_trace_stack_set(node->previous);
    }
    return node;
}

static struct section_64 *apt_find_section(struct mach_header_64 *header, const char *section_name) {
    struct load_command *command = (struct load_command *)((uintptr_t)header + sizeof(struct mach_header_64));
    for (uint32_t command_index = 0; command_index < header->ncmds; ++command_index) {
        if (command->cmd == LC_SEGMENT_64) {
            struct segment_command_64 *segment = (struct segment_command_64 *)command;
            struct section_64 *section = (struct section_64 *)((uintptr_t)segment + sizeof(struct segment_command_64));
            for (uint32_t section_index = 0; section_index < segment->nsects; ++section_index) {
                if (strncmp(section[section_index].sectname, section_name, sizeof(section[section_index].sectname)) == 0) {
                    return &section[section_index];
                }
            }
        }
        command = (struct load_command *)((uintptr_t)command + command->cmdsize);
    }
    return NULL;
}

static void apt_configure_trace_ranges(void) {
    gLogAllSelectors = apt_bool_from_environment(@"APPLETRACE_TRACE_ALL_SELECTORS", YES);
    gLogAllClasses = apt_bool_from_environment(@"APPLETRACE_TRACE_ALL_CLASSES", YES);

    const struct mach_header *header = _dyld_get_image_header(0);
    if (!header || header->magic != MH_MAGIC_64) {
        return;
    }

    intptr_t slide = _dyld_get_image_vmaddr_slide(0);
    struct section_64 *selector_section = apt_find_section((struct mach_header_64 *)header, "__objc_methname");
    if (selector_section) {
        gLogSelectorStart = (uintptr_t)(slide + selector_section->addr);
        gLogSelectorEnd = gLogSelectorStart + selector_section->size;
    }

    struct section_64 *class_section = apt_find_section((struct mach_header_64 *)header, "__objc_data");
    if (class_section) {
        gLogClassStart = (uintptr_t)(slide + class_section->addr);
        gLogClassEnd = gLogClassStart + class_section->size;
    }
}

static BOOL apt_selector_should_trace(const char *selector_name) {
    if (!selector_name) {
        return NO;
    }
    if (gLogAllSelectors) {
        return YES;
    }
    if (gLogSelectorStart == 0 || gLogSelectorEnd == 0) {
        return YES;
    }

    uintptr_t pointer = (uintptr_t)selector_name;
    return pointer >= gLogSelectorStart && pointer <= gLogSelectorEnd;
}

static BOOL apt_class_should_trace(Class cls) {
    if (!cls) {
        return NO;
    }
    if (gLogAllClasses) {
        return YES;
    }
    if (gLogClassStart == 0 || gLogClassEnd == 0) {
        return YES;
    }

    uintptr_t pointer = (uintptr_t)cls;
    return pointer >= gLogClassStart && pointer <= gLogClassEnd;
}

static char *apt_copy_trace_name(id object, SEL selector) {
    if (!object || !selector) {
        return NULL;
    }

    const char *selector_name = sel_getName(selector);
    if (!apt_selector_should_trace(selector_name)) {
        return NULL;
    }

    Class cls = object_getClass(object);
    if (!apt_class_should_trace(cls)) {
        return NULL;
    }

    const char *class_name = class_getName(cls);
    if (!class_name || !selector_name) {
        return NULL;
    }

    size_t required = strlen(class_name) + strlen(selector_name) + 4;
    char *trace_name = malloc(required);
    if (!trace_name) {
        return NULL;
    }

    snprintf(trace_name, required, "[%s]%s", class_name, selector_name);
    return trace_name;
}

static void apt_before_objc_msgSend(id object, SEL selector) {
    if (gTraceGuard != 0) {
        return;
    }

    gTraceGuard += 1;
    char *trace_name = apt_copy_trace_name(object, selector);
    if (trace_name) {
        apt_trace_stack_push(trace_name);
        APTBeginSection(trace_name);
    }
    gTraceGuard -= 1;
}

static void apt_after_objc_msgSend(void) {
    if (gTraceGuard != 0) {
        return;
    }

    gTraceGuard += 1;
    APTTraceNode *node = apt_trace_stack_pop();
    if (node) {
        APTEndSection(node->name);
        free(node->name);
        free(node);
    }
    gTraceGuard -= 1;
}

static int apt_prepend_rebindings(struct APTRebindingsEntry **head,
                                  struct APTRebinding rebindings[],
                                  size_t count) {
    struct APTRebindingsEntry *entry = malloc(sizeof(struct APTRebindingsEntry));
    if (!entry) {
        return -1;
    }

    entry->rebindings = malloc(sizeof(struct APTRebinding) * count);
    if (!entry->rebindings) {
        free(entry);
        return -1;
    }

    memcpy(entry->rebindings, rebindings, sizeof(struct APTRebinding) * count);
    entry->count = count;
    entry->next = *head;
    *head = entry;
    return 0;
}

static void apt_perform_rebinding_with_section(struct APTRebindingsEntry *rebindings,
                                               section_t *section,
                                               intptr_t slide,
                                               nlist_t *symtab,
                                               char *strtab,
                                               uint32_t *indirect_symtab) {
    uint32_t *indirect_symbol_indices = indirect_symtab + section->reserved1;
    void **indirect_symbol_bindings = (void **)((uintptr_t)slide + section->addr);
    size_t entry_count = section->size / sizeof(void *);

    vm_protect(mach_task_self(),
               (vm_address_t)indirect_symbol_bindings,
               (vm_size_t)section->size,
               0,
               VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);

    for (size_t index = 0; index < entry_count; index++) {
        uint32_t symtab_index = indirect_symbol_indices[index];
        if (symtab_index == INDIRECT_SYMBOL_ABS ||
            symtab_index == INDIRECT_SYMBOL_LOCAL ||
            symtab_index == (INDIRECT_SYMBOL_LOCAL | INDIRECT_SYMBOL_ABS)) {
            continue;
        }

        char *symbol_name = strtab + symtab[symtab_index].n_un.n_strx;
        if (!symbol_name || symbol_name[0] != '_') {
            continue;
        }

        struct APTRebindingsEntry *entry = rebindings;
        while (entry) {
            for (size_t rebinding_index = 0; rebinding_index < entry->count; rebinding_index++) {
                struct APTRebinding *rebinding = &entry->rebindings[rebinding_index];
                if (strcmp(&symbol_name[1], rebinding->name) == 0) {
                    if (rebinding->replaced && *(rebinding->replaced) == NULL) {
                        *(rebinding->replaced) = indirect_symbol_bindings[index];
                    }
                    indirect_symbol_bindings[index] = rebinding->replacement;
                    goto next_symbol;
                }
            }
            entry = entry->next;
        }

    next_symbol:
        continue;
    }

    // Keep the rebinding page writable after patching. Restoring it to a guessed
    // read-only protection can corrupt unrelated mutable globals that share the
    // same __DATA page, which caused simulator startup crashes.
}

static void apt_rebind_symbols_for_image(const struct mach_header *header,
                                         intptr_t slide,
                                         struct APTRebindingsEntry *rebindings) {
    Dl_info info;
    if (!header || !rebindings || !dladdr(header, &info)) {
        return;
    }
    if (info.dli_fname && strstr(info.dli_fname, "/appletrace.framework/") != NULL) {
        return;
    }

    segment_command_t *linkedit_segment = NULL;
    struct symtab_command *symtab_command = NULL;
    struct dysymtab_command *dysymtab_command = NULL;

    uintptr_t command_cursor = (uintptr_t)header + sizeof(mach_header_t);
    for (uint32_t index = 0; index < header->ncmds; index++) {
        struct load_command *command = (struct load_command *)command_cursor;
        if (command->cmd == LC_SEGMENT_ARCH_DEPENDENT) {
            segment_command_t *segment = (segment_command_t *)command;
            if (strcmp(segment->segname, SEG_LINKEDIT) == 0) {
                linkedit_segment = segment;
            }
        } else if (command->cmd == LC_SYMTAB) {
            symtab_command = (struct symtab_command *)command;
        } else if (command->cmd == LC_DYSYMTAB) {
            dysymtab_command = (struct dysymtab_command *)command;
        }
        command_cursor += command->cmdsize;
    }

    if (!symtab_command || !dysymtab_command || !linkedit_segment) {
        return;
    }

    uintptr_t linkedit_base = (uintptr_t)slide + linkedit_segment->vmaddr - linkedit_segment->fileoff;
    nlist_t *symtab = (nlist_t *)(linkedit_base + symtab_command->symoff);
    char *strtab = (char *)(linkedit_base + symtab_command->stroff);
    uint32_t *indirect_symtab = (uint32_t *)(linkedit_base + dysymtab_command->indirectsymoff);

    command_cursor = (uintptr_t)header + sizeof(mach_header_t);
    for (uint32_t index = 0; index < header->ncmds; index++) {
        struct load_command *command = (struct load_command *)command_cursor;
        if (command->cmd == LC_SEGMENT_ARCH_DEPENDENT) {
            segment_command_t *segment = (segment_command_t *)command;
            BOOL is_data_segment =
                strcmp(segment->segname, SEG_DATA) == 0 ||
                strcmp(segment->segname, "__DATA_CONST") == 0;
            if (is_data_segment) {
                for (uint32_t section_index = 0; section_index < segment->nsects; section_index++) {
                    section_t *section = (section_t *)((uintptr_t)segment + sizeof(segment_command_t)) + section_index;
                    uint32_t type = section->flags & SECTION_TYPE;
                    if (type == S_LAZY_SYMBOL_POINTERS || type == S_NON_LAZY_SYMBOL_POINTERS) {
                        apt_perform_rebinding_with_section(rebindings, section, slide, symtab, strtab, indirect_symtab);
                    }
                }
            }
        }
        command_cursor += command->cmdsize;
    }
}

static int apt_rebind_symbols(struct APTRebinding rebindings[], size_t count) {
    int failure = apt_prepend_rebindings(&gRebindingsHead, rebindings, count);
    if (failure < 0) {
        return failure;
    }

    for (uint32_t image_index = 0; image_index < _dyld_image_count(); image_index++) {
        apt_rebind_symbols_for_image(_dyld_get_image_header(image_index),
                                     _dyld_get_image_vmaddr_slide(image_index),
                                     gRebindingsHead);
    }

    return 0;
}

@interface APTObjCMsgSendHook : NSObject
@end

@implementation APTObjCMsgSendHook

+ (void)load {
    if (apt_bool_from_environment(@"APPLETRACE_AUTO_HOOK_OBJC_MSGSEND", NO)) {
        apt_install_objc_msgsend_hook();
    }
}

@end

BOOL APTInstallObjcMsgSendHook(void) {
    return apt_install_objc_msgsend_hook();
}

BOOL APTIsObjcMsgSendHookInstalled(void) {
    return gHookInstalled;
}
