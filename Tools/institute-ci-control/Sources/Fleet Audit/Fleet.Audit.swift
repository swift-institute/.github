// Nest.Name namespace shell (FT1-ratification.json). `Fleet.Audit` owns
// the cron sweep contract retired from `cron-audit-runner.py`: what a
// caller may configure, what one package's audit reports, and how a
// sweep accumulates those reports into the artefacts `cron-audit-base`
// uploads.
//
// Everything here is pure. The credentialed edge — minting a token,
// listing an org, cloning a target, running an audit over the clone —
// lives in `Institute.CI.Control.Application.Audit`, which supplies it
// to `Fleet.Audit.Sweep` as an environment. That seam is why this
// target's tests need no network and no token: the accumulation, the
// per-package formatting and the summary are decided here, over
// recorded reports.
public enum Fleet {}

extension Fleet {
    /// The cron audit sweep: one org, one audit, many packages.
    public enum Audit {}
}
