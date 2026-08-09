import { execFileSync } from "node:child_process";
import { existsSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

function probeDurationSeconds(file, execFn = execFileSync) {
  try {
    const out = execFn(
      "ffprobe",
      ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", file],
      { encoding: "utf8", timeout: 15000 },
    );
    const duration = parseFloat(String(out).trim());
    return Number.isFinite(duration) ? duration : undefined;
  } catch {
    return undefined;
  }
}

function defaultVoice(intent) {
  const text = String(intent);
  const hasKorean = /[\uac00-\ud7a3]/u.test(text);
  const latinCount = (text.match(/[A-Za-z]/g) || []).length;
  const letterCount = (text.match(/[A-Za-z\uac00-\ud7a3]/gu) || []).length;
  return !hasKorean && latinCount > letterCount / 2
    ? "en-US-AriaNeural"
    : "ko-KR-SunHiNeural";
}

// Edge TTS is a keyless CLI-backed provider. Dependency and service failures
// are clean misses so the registry can continue through the voice cascade.
export async function edgeTtsGenerate(
  intent,
  ctx,
  execFn = execFileSync,
  pathExists = existsSync,
  statFn = statSync,
) {
  const outPath = join(tmpdir(), `media-use-edge-${process.pid}-${Date.now()}.mp3`);
  const voice = ctx?.voiceId || defaultVoice(intent);
  const args = ["--text", intent, "--voice", voice, "--write-media", outPath];
  if (ctx?.rate != null) args.push("--rate", String(ctx.rate));
  if (ctx?.pitch != null) args.push("--pitch", String(ctx.pitch));
  if (ctx?.volume != null) args.push("--volume", String(ctx.volume));

  const opts = { encoding: "utf8", timeout: 300000, stdio: ["ignore", "pipe", "pipe"] };
  let generated = false;
  for (const [cmd, commandArgs] of [
    ["edge-tts", args],
    ["python3", ["-m", "edge_tts", ...args]],
  ]) {
    try {
      execFn(cmd, commandArgs, opts);
      generated = true;
      break;
    } catch {
      // Missing CLI/module, network errors, and synthesis failures all fall
      // through without preventing another registered provider from running.
    }
  }
  if (!generated || !pathExists(outPath) || statFn(outPath).size === 0) return null;

  return {
    localPath: outPath,
    ext: ".mp3",
    source: "generated",
    metadata: {
      description: intent,
      provider: "edge.tts",
      duration: probeDurationSeconds(outPath, execFn),
      provenance: { prompt: intent },
    },
  };
}
