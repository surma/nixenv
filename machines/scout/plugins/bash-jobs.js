import { tool } from "@opencode-ai/plugin";
import { spawn } from "node:child_process";
import { createWriteStream, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve, isAbsolute } from "node:path";
import { randomBytes } from "node:crypto";

const LOG_DIR = join(tmpdir(), "opencode-bash-jobs");
const DEFAULT_TIMEOUT_MS = 120_000;
const MAX_WAIT_MS = 300_000;
const COMPLETED_JOB_TTL_MS = 10 * 60 * 1000;
const GC_INTERVAL_MS = 60_000;
const MAX_TAIL_BYTES = 102_400;
const MAX_TAIL_LINES = 200;
const STALL_CHECK_INTERVAL_MS = 5_000;
const STALL_THRESHOLD_MS = 45_000;
const SIGTERM_GRACE_MS = 3_000;
const KILL_WAIT_DEADLINE_MS = 5_000;

const PROMPT_PATTERNS = [
  /\(y\/n\)/i,
  /\[y\/n\]/i,
  /\(yes\/no\)/i,
  /\b(?:Do you|Would you|Shall I|Are you sure|Ready to)\b.*\?\s*$/i,
  /Press (?:any key|Enter)/i,
  /Continue\?/i,
  /Overwrite\?/i,
];

// ── Helpers ────────────────────────────────────────────────────────────

function ensureLogDir() {
  mkdirSync(LOG_DIR, { recursive: true });
}

function createJobId() {
  return `job_${randomBytes(4).toString("hex")}`;
}

function createLogPath(jobId) {
  ensureLogDir();
  return join(LOG_DIR, `${jobId}.log`);
}

function formatDuration(ms) {
  const s = Math.max(0, Math.floor(ms / 1000));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  if (h > 0) return `${h}h ${m}m ${sec}s`;
  if (m > 0) return `${m}m ${sec}s`;
  return `${sec}s`;
}

function formatSize(bytes) {
  if (bytes < 1024) return `${bytes}B`;
  if (bytes < 1024 ** 2) return `${(bytes / 1024).toFixed(1)}KB`;
  return `${(bytes / 1024 ** 2).toFixed(1)}MB`;
}

function resolveWorkdir(base, workdir) {
  if (!workdir) return base;
  return isAbsolute(workdir) ? workdir : resolve(base, workdir);
}

function looksLikePrompt(text) {
  const lastLine = text.trimEnd().split("\n").pop() ?? "";
  return PROMPT_PATTERNS.some((p) => p.test(lastLine));
}

function truncateTail(text) {
  const lines = text.split("\n");
  let bytes = Buffer.byteLength(text);
  let truncated = false;

  if (lines.length > MAX_TAIL_LINES) {
    const kept = lines.slice(-MAX_TAIL_LINES);
    const result = kept.join("\n");
    return { content: result, truncated: true };
  }

  if (bytes > MAX_TAIL_BYTES) {
    // Keep the last MAX_TAIL_BYTES worth of content
    const buf = Buffer.from(text);
    const sliced = buf.subarray(buf.length - MAX_TAIL_BYTES).toString("utf8");
    // Find the first newline to avoid a partial first line
    const nl = sliced.indexOf("\n");
    return {
      content: nl >= 0 ? sliced.slice(nl + 1) : sliced,
      truncated: true,
    };
  }

  return { content: text, truncated: false };
}

// ── Deferred ───────────────────────────────────────────────────────────

function createDeferred() {
  let resolve;
  const promise = new Promise((res) => {
    resolve = res;
  });
  return { promise, resolve };
}

// ── Process management ─────────────────────────────────────────────────

function killProcessGroup(pid, signal = "SIGKILL") {
  if (!pid) return;
  try {
    process.kill(-pid, signal);
  } catch {
    try {
      process.kill(pid, signal);
    } catch {
      // already gone
    }
  }
}

// ── Plugin ─────────────────────────────────────────────────────────────

export const BashJobsPlugin = async ({ directory }) => {
  const jobs = new Map();

  // ── GC for completed jobs ─────────────────────────────────────────

  const gcTimer = setInterval(() => {
    const now = Date.now();
    for (const [id, job] of jobs) {
      if (job.status !== "running" && job.endedAt && now - job.endedAt > COMPLETED_JOB_TTL_MS) {
        jobs.delete(id);
      }
    }
  }, GC_INTERVAL_MS);
  if (gcTimer.unref) gcTimer.unref();

  // ── Job lifecycle ──────────────────────────────────────────────────

  function finalizeJob(job, exitCode) {
    if (job.finalized) return;
    job.finalized = true;
    if (job.stallTimer) {
      clearInterval(job.stallTimer);
      job.stallTimer = undefined;
    }
    if (!job.logStream.destroyed) job.logStream.end();
    job.endedAt = Date.now();
    job.exitCode = exitCode;
    job.status = job.killRequested
      ? "killed"
      : exitCode === 0
        ? "completed"
        : "failed";
    job.completion.resolve();
  }

  function appendChunk(job, chunk) {
    job.totalBytes += chunk.length;
    job.lastOutputAt = Date.now();
    job.chunks.push(chunk);
    job.chunksBytes += chunk.length;
    while (job.chunksBytes > MAX_TAIL_BYTES && job.chunks.length > 1) {
      const removed = job.chunks.shift();
      if (removed) job.chunksBytes -= removed.length;
    }
  }

  function getTailState(job) {
    const text = Buffer.concat(job.chunks).toString("utf8");
    const result = truncateTail(text);
    return {
      text: result.content || "",
      truncated: result.truncated || job.totalBytes > MAX_TAIL_BYTES,
    };
  }

  function startStallWatchdog(job) {
    job.stallTimer = setInterval(() => {
      if (job.status !== "running") {
        clearInterval(job.stallTimer);
        job.stallTimer = undefined;
        return;
      }
      if (Date.now() - job.lastOutputAt < STALL_THRESHOLD_MS) return;
      const tail = getTailState(job).text;
      if (!tail || !looksLikePrompt(tail)) return;
      if (!job.interactiveStall) {
        job.interactiveStall = true;
        job.stallSummary =
          "output appears stalled and the last line looks like an interactive prompt";
      }
    }, STALL_CHECK_INTERVAL_MS);
    if (job.stallTimer.unref) job.stallTimer.unref();
  }

  function spawnJob(command, cwd) {
    const shell = process.env.SHELL || "/bin/bash";
    const child = spawn(shell, ["-lc", command], {
      cwd,
      env: process.env,
      stdio: ["ignore", "pipe", "pipe"],
      detached: true,
    });

    const jobId = createJobId();
    const outputPath = createLogPath(jobId);
    const logStream = createWriteStream(outputPath, { flags: "a" });
    let canWriteLog = true;
    logStream.on("error", () => {
      canWriteLog = false;
    });

    const job = {
      jobId,
      command,
      cwd,
      pid: child.pid,
      status: "running",
      startedAt: Date.now(),
      outputPath,
      totalBytes: 0,
      lastOutputAt: Date.now(),
      interactiveStall: false,
      stallSummary: undefined,
      killRequested: false,
      logStream,
      chunks: [],
      chunksBytes: 0,
      completion: createDeferred(),
      stallTimer: undefined,
      finalized: false,
      exitCode: undefined,
      endedAt: undefined,
    };
    jobs.set(jobId, job);

    const onData = (data) => {
      const chunk = Buffer.isBuffer(data) ? data : Buffer.from(data);
      appendChunk(job, chunk);
      if (canWriteLog) logStream.write(chunk);
    };
    child.stdout?.on("data", onData);
    child.stderr?.on("data", onData);
    child.once("close", (code) => finalizeJob(job, code));
    child.once("error", () => finalizeJob(job, 1));
    startStallWatchdog(job);

    return job;
  }

  // ── Formatting ─────────────────────────────────────────────────────

  function formatRunningMessage(job, tail) {
    if (!tail) tail = getTailState(job);
    const lines = [
      `Command is still running as managed bash job ${job.jobId}.`,
      `Started: ${new Date(job.startedAt).toLocaleTimeString()} (${formatDuration(Date.now() - job.startedAt)} elapsed)`,
      `PID: ${job.pid ?? "unknown"}`,
      `Log file: ${job.outputPath}`,
      "",
      "Output so far:",
      tail.text || "(no output yet)",
    ];
    if (tail.truncated) {
      lines.push("", `[Showing recent output tail. Full log: ${job.outputPath}]`);
    }
    if (job.interactiveStall && job.stallSummary) {
      lines.push("", `[Possible interactive stall: ${job.stallSummary}]`);
    }
    lines.push(
      "",
      `Use bash_wait with jobId "${job.jobId}" to wait longer, bash_status to inspect it, bash_kill to stop it, or bash_jobs to list jobs.`
    );
    return lines.join("\n");
  }

  function formatCompletedMessage(job, includeHeader, tail) {
    if (!tail) tail = getTailState(job);
    const lines = [];
    if (includeHeader) {
      const summary =
        job.status === "completed"
          ? `Job ${job.jobId} completed successfully.`
          : job.status === "killed"
            ? `Job ${job.jobId} was killed.`
            : `Job ${job.jobId} failed${job.exitCode != null ? ` with exit code ${job.exitCode}` : ""}.`;
      lines.push(
        summary,
        `Runtime: ${formatDuration((job.endedAt ?? Date.now()) - job.startedAt)}`
      );
    }
    lines.push(tail.text || "(no output)");
    if (tail.truncated) {
      lines.push("", `[Showing recent output tail. Full log: ${job.outputPath}]`);
    }
    if (job.interactiveStall && job.stallSummary) {
      lines.push("", `[Earlier possible interactive stall: ${job.stallSummary}]`);
    }
    return lines.join("\n").trim();
  }

  function formatStatus(job, tail) {
    if (!tail) tail = getTailState(job);
    const lines = [
      `Job: ${job.jobId}`,
      `Status: ${job.status}`,
      `Command: ${job.command}`,
      `Working directory: ${job.cwd}`,
      `Started: ${new Date(job.startedAt).toISOString()}`,
      `Elapsed: ${formatDuration((job.endedAt ?? Date.now()) - job.startedAt)}`,
      `PID: ${job.pid ?? "unknown"}`,
      `Log file: ${job.outputPath}`,
      `Bytes captured: ${formatSize(job.totalBytes)}`,
    ];
    if (job.endedAt) lines.push(`Ended: ${new Date(job.endedAt).toISOString()}`);
    if (job.exitCode !== undefined) lines.push(`Exit code: ${job.exitCode ?? "null"}`);
    if (job.interactiveStall && job.stallSummary) lines.push(`Interactive stall: ${job.stallSummary}`);
    lines.push("", "Recent output:", tail.text || "(no output yet)");
    if (tail.truncated) {
      lines.push("", `[Showing recent output tail. Full log: ${job.outputPath}]`);
    }
    return lines.join("\n");
  }

  function formatJobsList() {
    const running = [...jobs.values()].filter((j) => j.status === "running");
    if (running.length === 0) return "No running managed bash jobs.";
    const sorted = running.sort((a, b) => b.startedAt - a.startedAt);
    const lines = sorted.map((job) => {
      const runtime = formatDuration(Date.now() - job.startedAt);
      const extra = job.interactiveStall ? " - waiting for input?" : "";
      return `* ${job.jobId} - running - ${runtime}${extra}\n    ${job.command}\n    ${job.outputPath}`;
    });
    return `Running managed bash jobs (${running.length}):\n\n${lines.join("\n\n")}`;
  }

  // ── Core execution ─────────────────────────────────────────────────

  function getJob(jobId) {
    const job = jobs.get(jobId);
    if (!job) {
      throw new Error(
        `Unknown bash job: ${jobId}. It may have already finished and been cleaned up. Use bash_jobs to see running jobs.`
      );
    }
    return job;
  }

  function forgetJob(job) {
    jobs.delete(job.jobId);
  }

  async function runManagedBash(command, cwd, timeoutMs) {
    const job = spawnJob(command, cwd);

    const result = await new Promise((resolve) => {
      let settled = false;
      const finish = (value) => {
        if (settled) return;
        settled = true;
        if (timeoutHandle) clearTimeout(timeoutHandle);
        resolve(value);
      };
      job.completion.promise.then(() => finish("completed"));
      const timeoutHandle = setTimeout(() => finish("timed_out"), timeoutMs);
      if (timeoutHandle.unref) timeoutHandle.unref();
    });

    if (result === "timed_out") {
      return formatRunningMessage(job);
    }

    const tail = getTailState(job);
    const text = formatCompletedMessage(job, false, tail);
    const status = job.status;
    const exitCode = job.exitCode;
    forgetJob(job);

    if (status === "failed") {
      throw new Error(`${text}\n\nCommand exited with code ${exitCode ?? 1}`);
    }
    if (status === "killed") {
      throw new Error(`${text}\n\nCommand was killed`);
    }
    return text;
  }

  async function waitForJob(job, timeoutMs) {
    if (job.status !== "running") return;
    // Cap at MAX_WAIT_MS to prevent indefinite hangs
    const effectiveTimeout = Math.min(timeoutMs ?? MAX_WAIT_MS, MAX_WAIT_MS);
    await new Promise((resolve) => {
      let settled = false;
      const finish = () => {
        if (settled) return;
        settled = true;
        if (timeoutHandle) clearTimeout(timeoutHandle);
        resolve();
      };
      job.completion.promise.then(finish);
      const timeoutHandle = setTimeout(finish, effectiveTimeout);
      if (timeoutHandle.unref) timeoutHandle.unref();
    });
  }

  async function killJob(job) {
    if (job.status !== "running") return;
    job.killRequested = true;

    // Phase 1: SIGTERM for graceful shutdown
    killProcessGroup(job.pid, "SIGTERM");

    // Wait for graceful exit or escalate to SIGKILL
    await new Promise((resolve) => {
      let settled = false;
      let graceHandle;
      let deadlineHandle;

      const finish = () => {
        if (settled) return;
        settled = true;
        if (graceHandle) clearTimeout(graceHandle);
        if (deadlineHandle) clearTimeout(deadlineHandle);
        resolve();
      };

      job.completion.promise.then(finish);

      // Phase 2: SIGKILL after grace period
      graceHandle = setTimeout(() => {
        if (job.status !== "running") return;
        killProcessGroup(job.pid, "SIGKILL");
      }, SIGTERM_GRACE_MS);
      if (graceHandle.unref) graceHandle.unref();

      // Hard deadline: force-finalize if still stuck after SIGKILL
      deadlineHandle = setTimeout(() => {
        finalizeJob(job, null);
        finish();
      }, SIGTERM_GRACE_MS + KILL_WAIT_DEADLINE_MS);
      if (deadlineHandle.unref) deadlineHandle.unref();
    });
  }

  // ── Tool definitions ───────────────────────────────────────────────

  return {
    tool: {
      bash: tool({
        description: [
          "Execute a bash command in the current working directory.",
          "Returns stdout and stderr.",
          `Output is truncated to last ${MAX_TAIL_LINES} lines or ${formatSize(MAX_TAIL_BYTES)} (whichever is hit first).`,
          `Timeout defaults to ${DEFAULT_TIMEOUT_MS / 1000}s;`,
          "if the command exceeds it, it stays alive as a managed bash job instead of being killed.",
          "Use bash_wait, bash_status, bash_kill, or bash_jobs to manage it.",
          "Do not use shell backgrounding (&, nohup, disown) — prefer managed bash jobs.",
        ].join(" "),
        args: {
          command: tool.schema.string().min(1).describe("The command to execute"),
          description: tool.schema
            .string()
            .optional()
            .describe(
              "Clear, concise description of what this command does in 5-10 words"
            ),
          timeout: tool.schema
            .number()
            .optional()
            .describe(
              `Optional timeout in milliseconds (default: ${DEFAULT_TIMEOUT_MS}ms). If exceeded, the command keeps running as a managed job.`
            ),
          workdir: tool.schema
            .string()
            .optional()
            .describe(
              "The working directory to run the command in. Defaults to the current directory."
            ),
        },
        async execute(args, context) {
          const cwd = resolveWorkdir(context.directory, args.workdir);
          const timeoutMs = args.timeout ?? DEFAULT_TIMEOUT_MS;
          return runManagedBash(args.command, cwd, timeoutMs);
        },
      }),

      bash_wait: tool({
        description:
          "Wait for a managed bash job to finish, or for additional time to elapse. Returns updated output and status without rerunning the command.",
        args: {
          jobId: tool.schema.string().describe("Managed bash job id"),
          timeout: tool.schema
            .number()
            .optional()
            .describe(
              `Additional time to wait in milliseconds (optional, defaults to ${MAX_WAIT_MS / 1000}s, capped at ${MAX_WAIT_MS / 1000}s)`
            ),
        },
        async execute(args) {
          const job = getJob(args.jobId);
          await waitForJob(job, args.timeout);
          if (job.status === "running") {
            return formatRunningMessage(job);
          }
          const tail = getTailState(job);
          const text = formatCompletedMessage(job, true, tail);
          const status = job.status;
          const exitCode = job.exitCode;
          forgetJob(job);
          if (status === "failed") {
            throw new Error(
              `${text}\n\nCommand exited with code ${exitCode ?? 1}`
            );
          }
          if (status === "killed") {
            throw new Error(`${text}\n\nCommand was killed`);
          }
          return text;
        },
      }),

      bash_status: tool({
        description:
          "Inspect the current status of a managed bash job, including elapsed time, log path, and recent output.",
        args: {
          jobId: tool.schema.string().describe("Managed bash job id"),
        },
        async execute(args) {
          const job = getJob(args.jobId);
          const tail = getTailState(job);
          const text = formatStatus(job, tail);
          if (job.status !== "running") forgetJob(job);
          return text;
        },
      }),

      bash_kill: tool({
        description:
          "Kill a running managed bash job and return its final known output tail.",
        args: {
          jobId: tool.schema.string().describe("Managed bash job id"),
        },
        async execute(args) {
          const job = getJob(args.jobId);
          await killJob(job);
          const tail = getTailState(job);
          const text = formatCompletedMessage(job, true, tail);
          forgetJob(job);
          return text;
        },
      }),

      bash_jobs: tool({
        description: "List currently running managed bash jobs.",
        args: {},
        async execute() {
          return formatJobsList();
        },
      }),
    },
  };
};
