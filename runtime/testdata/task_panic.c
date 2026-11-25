/* Task runtime contract-violation fixtures. Each scenario is expected to
 * terminate through alder_runtime_panic with status 101; the Go harness
 * selects one scenario per process. */
#include "alder.h"

#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef struct {
    uint32_t state;
    uint64_t target;
} PanicFrame;

typedef struct {
    AlderDomain domain;
    PanicFrame *frame;
    uint64_t id;
} PanicRoot;

static bool root_create(PanicRoot *root, AlderStepFn step) {
    memset(root, 0, sizeof *root);
    if (!alder_domain_init(&root->domain, NULL)) {
        return false;
    }
    root->frame = (PanicFrame *)alder_domain_alloc(
        &root->domain, sizeof *root->frame, _Alignof(PanicFrame));
    if (root->frame == NULL) {
        return false;
    }
    memset(root->frame, 0, sizeof *root->frame);
    AlderTask *task = alder_task_create(UINT64_C(1), step, root->frame,
                                        &root->domain);
    root->id = alder_task_handle(task);
    alder_task_start(task);
    return true;
}

static AlderStepStatus done_step(AlderTask *task, AlderDomain *results,
                                 void *frame_ptr, AlderDomain *frame_domain) {
    (void)task;
    (void)results;
    (void)frame_ptr;
    (void)frame_domain;
    return ALDER_STEP_DONE;
}

static AlderStepStatus park_step(AlderTask *task, AlderDomain *results,
                                 void *frame_ptr, AlderDomain *frame_domain) {
    (void)task;
    (void)results;
    (void)frame_ptr;
    (void)frame_domain;
    return ALDER_STEP_PARK;
}

static AlderStepStatus timer_park_step(AlderTask *task, AlderDomain *results,
                                       void *frame_ptr,
                                       AlderDomain *frame_domain) {
    (void)task;
    (void)results;
    (void)frame_domain;
    PanicFrame *frame = (PanicFrame *)frame_ptr;
    frame->state = 1;
    if (!alder_timer_at(alder_task_wakeup(), UINT64_C(1000000))) {
        return ALDER_STEP_CANCELLED;
    }
    alder_task_wait_reason(ALDER_WAIT_TIMER);
    return ALDER_STEP_PARK;
}

static AlderStepStatus release_target_step(AlderTask *task,
                                           AlderDomain *results,
                                           void *frame_ptr,
                                           AlderDomain *frame_domain) {
    (void)task;
    (void)results;
    (void)frame_domain;
    PanicFrame *frame = (PanicFrame *)frame_ptr;
    alder_task_release(frame->target);
    return ALDER_STEP_DONE;
}

static AlderStepStatus shield_underflow_step(AlderTask *task,
                                             AlderDomain *results,
                                             void *frame_ptr,
                                             AlderDomain *frame_domain) {
    (void)task;
    (void)results;
    (void)frame_ptr;
    (void)frame_domain;
    alder_task_shield_pop();
    return ALDER_STEP_DONE;
}

static AlderStepStatus call_without_publication_step(AlderTask *task,
                                                     AlderDomain *results,
                                                     void *frame_ptr,
                                                     AlderDomain *frame_domain) {
    (void)task;
    (void)results;
    (void)frame_ptr;
    (void)frame_domain;
    return ALDER_STEP_CALL;
}

static AlderStepStatus invalid_status_step(AlderTask *task,
                                           AlderDomain *results,
                                           void *frame_ptr,
                                           AlderDomain *frame_domain) {
    (void)task;
    (void)results;
    (void)frame_ptr;
    (void)frame_domain;
    return (AlderStepStatus)99;
}

static AlderStepStatus await_self_step(AlderTask *task, AlderDomain *results,
                                       void *frame_ptr,
                                       AlderDomain *frame_domain) {
    (void)task;
    (void)results;
    (void)frame_ptr;
    (void)frame_domain;
    (void)alder_task_await(alder_task_id());
    return ALDER_STEP_DONE;
}

int main(int argc, char **argv) {
    PanicRoot root;
    if (argc != 2) {
        fprintf(stderr, "usage: task_panic <scenario>\n");
        return 2;
    }
    if (strcmp(argv[1], "release-parked") == 0) {
        if (!root_create(&root, park_step)) {
            return 3;
        }
        alder_task_release(root.id);
    } else if (strcmp(argv[1], "release-timer") == 0) {
        PanicRoot parked;
        if (!root_create(&parked, timer_park_step)) {
            return 3;
        }
        if (!root_create(&root, release_target_step)) {
            return 3;
        }
        root.frame->target = parked.id;
        (void)alder_executor_run(NULL);
    } else if (strcmp(argv[1], "release-foreign") == 0) {
        alder_task_release(0);
    } else if (strcmp(argv[1], "cancel-released") == 0) {
        if (!root_create(&root, done_step)) {
            return 3;
        }
        if (!alder_executor_run(NULL)) {
            return 3;
        }
        alder_task_release(root.id);
        alder_task_cancel(root.id);
    } else if (strcmp(argv[1], "shield-underflow") == 0) {
        if (!root_create(&root, shield_underflow_step)) {
            return 3;
        }
        (void)alder_executor_run(NULL);
    } else if (strcmp(argv[1], "call-without-publication") == 0) {
        if (!root_create(&root, call_without_publication_step)) {
            return 3;
        }
        (void)alder_executor_run(NULL);
    } else if (strcmp(argv[1], "invalid-status") == 0) {
        if (!root_create(&root, invalid_status_step)) {
            return 3;
        }
        (void)alder_executor_run(NULL);
    } else if (strcmp(argv[1], "await-self") == 0) {
        if (!root_create(&root, await_self_step)) {
            return 3;
        }
        (void)alder_executor_run(NULL);
    } else {
        fprintf(stderr, "unknown scenario %s\n", argv[1]);
        return 2;
    }
    fprintf(stderr, "scenario %s did not panic\n", argv[1]);
    return 4;
}
