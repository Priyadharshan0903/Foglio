import Foundation

/// First-run content, ported from the design's initial state
/// (Day Log.dc.html:646-711) so a fresh install looks like the mockup rather
/// than an empty shell.
enum Seed {
    private static func today(_ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(
            bySettingHour: hour, minute: minute, second: 0, of: Date()
        ) ?? Date()
    }

    static var notes: [Note] {
        [
            Note(
                title: "Operator — reconcile loop notes",
                body: Markdown.serialize([
                    .h1("Reconcile, don't RPC"),
                    .paragraph("The controller's job is to make the world match the spec, over and over. Every handler is idempotent. See [[Go worker pool]] for the queue side."),
                    .h2("What actually runs"),
                    .code(language: "go", text: """
                    func (r *Reconciler) Reconcile(ctx context.Context, req Request) (Result, error) {
                    \t// fetch desired state
                    \tvar app v1.App
                    \tif err := r.Get(ctx, req.NamespacedName, &app); err != nil {
                    \t\treturn Result{}, nil // dropped
                    \t}
                    \treturn Result{RequeueAfter: 30 * time.Second}, nil
                    }
                    """),
                    .todo(text: "Re-read informer / workqueue internals", checked: true),
                    .todo(text: "Write the finalizer path", checked: false),
                    .todo(text: "Break etcd in the kind cluster, recover it", checked: false),
                    .h2("Requeue strategy"),
                    .table(rows: [
                        ["Event", "Requeue", "Why"],
                        ["Spec change", "immediate", "user is waiting"],
                        ["Status drift", "30s", "cheap to re-check"],
                        ["API error", "backoff", "don't hammer"],
                    ]),
                    .image(alt: "controller-runtime diagram", path: ""),
                    .divider,
                    .paragraph("Question for Arun: do we own the CRD versioning or does platform?"),
                ]),
                folder: .platform,
                pin: "Kubernetes, to CKA",
                updatedAt: today(14, 20)
            ),
            Note(
                title: "Go worker pool",
                body: Markdown.serialize([
                    .h1("Worker pool, minimal"),
                    .paragraph("One channel in, one WaitGroup, context for cancellation. Everything else is decoration."),
                    .code(language: "go", text: """
                    jobs := make(chan Job)
                    for i := 0; i < n; i++ {
                    \tgo func() {
                    \t\tfor j := range jobs {
                    \t\t\tj.Do(ctx)
                    \t\t}
                    \t}()
                    }
                    """),
                    .todo(text: "Add pprof to the sample service", checked: false),
                ]),
                folder: .platform,
                pin: "Go, properly",
                updatedAt: today(9, 0)
            ),
            Note(
                title: "Scratchpad",
                body: Markdown.serialize([
                    .paragraph("Anything, unsorted. This note is always one keystroke away — ⌘⇧N from anywhere."),
                    .todo(text: "Ask Priya for staging access", checked: false),
                    .paragraph("Idea: log entries could roll up into the weekly review automatically."),
                ]),
                folder: .scratch,
                updatedAt: today(16, 2)
            ),
            Note(
                title: "Agoda — platform interview prep",
                body: Markdown.serialize([
                    .h1("What they'll actually ask"),
                    .paragraph("Systems design at infra level: multi-region, deploy safety, observability. Then Go depth."),
                    .todo(text: "Two system design mocks", checked: false),
                    .todo(text: "Write up the scheduler build", checked: false),
                ]),
                folder: .career,
                pin: "Platform engineer — Agoda",
                updatedAt: today(8, 30)
            ),
        ]
    }

    static var tasks: [TaskItem] {
        [
            TaskItem(label: "Finish Kubernetes operator chapter", lane: .priority, meta: "Due today"),
            TaskItem(label: "Ship goroutine leak fix", lane: .priority),
            TaskItem(label: "Tidy up local kind cluster", lane: .ordinary),
            TaskItem(label: "Ask Priya for staging access", lane: .delegate, meta: "From Scratchpad · follow up Thu"),
            TaskItem(label: "Review platform RFC", lane: .priority, done: true, completedAt: today(9, 20)),
        ]
    }

    static var log: [LogEntry] {
        [
            LogEntry(text: "Review platform RFC", kind: .task, at: today(9, 20)),
            LogEntry(text: "Heads-down — worker pool refactor", kind: .manual, at: today(10, 5)),
            LogEntry(text: "Pairing with Arun on the Helm chart", kind: .manual, at: today(11, 40)),
        ]
    }

    static var milestones: [Milestone] {
        [
            Milestone(
                title: "Go, properly",
                when: "Now — Q3",
                goal: "Concurrency, memory model and profiling deep enough to debug production.",
                steps: [
                    MilestoneStep(label: "Concurrency patterns book", done: true),
                    MilestoneStep(label: "Write a job queue in Go", done: true),
                    MilestoneStep(label: "pprof + trace on a real service"),
                    MilestoneStep(label: "Read the memory model spec"),
                ]
            ),
            Milestone(
                title: "Kubernetes, to CKA",
                when: "Q4 — Q1",
                goal: "Operators, networking and cluster internals — certification as the forcing function.",
                steps: [
                    MilestoneStep(label: "CKA course + labs", done: true),
                    MilestoneStep(label: "Write an operator with controller-runtime"),
                    MilestoneStep(label: "Break and fix a cluster weekly"),
                    MilestoneStep(label: "Sit the CKA exam"),
                ]
            ),
            Milestone(
                title: "Platform engineer — Agoda",
                when: "2027",
                goal: "Portfolio, referrals and interview prep aimed at platform teams.",
                steps: [
                    MilestoneStep(label: "Open-source the operator"),
                    MilestoneStep(label: "Write up the scheduler build"),
                    MilestoneStep(label: "Two system design mocks"),
                    MilestoneStep(label: "Apply"),
                ]
            ),
        ]
    }
}
