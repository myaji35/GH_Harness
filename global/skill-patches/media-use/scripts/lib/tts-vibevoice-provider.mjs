import { execFileSync } from "node:child_process";
import { existsSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

// VibeVoice's official Microsoft repository removed its TTS code over deepfake
// concerns; currently working implementations are community copies.
// Do not use this adapter for customer-facing commercial services until its
// license is verified. It is limited to internal production use.
// Audio generated with this adapter must carry an AI-generation disclosure.

// 실제 저장소 확인 후 확정 필요: keep the provisional community-repository
// inference entry point and every unsettled argument spelling in one place.
const VIBEVOICE_INFERENCE = {
  script: "inference.py",
  textFlag: "--text",
  outputFlag: "--output",
  speakersFlag: "--speakers",
  voiceSampleFlag: "--voice-sample",
};

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

export async function vibevoiceTtsGenerate(
  intent,
  ctx,
  execFn = execFileSync,
  env = process.env,
  pathExists = existsSync,
  statFn = statSync,
) {
  const home = env.VIBEVOICE_HOME;
  if (!home || !pathExists(home)) return null;

  const outPath = join(tmpdir(), `media-use-vibevoice-${process.pid}-${Date.now()}.wav`);
  const script = join(home, VIBEVOICE_INFERENCE.script);
  const args = [script, VIBEVOICE_INFERENCE.textFlag, intent, VIBEVOICE_INFERENCE.outputFlag, outPath];
  const speakers = Array.isArray(ctx?.speakers) ? ctx.speakers.slice(0, 4) : [];
  if (speakers.length) args.push(VIBEVOICE_INFERENCE.speakersFlag, JSON.stringify(speakers));
  if (ctx?.voiceSample) args.push(VIBEVOICE_INFERENCE.voiceSampleFlag, ctx.voiceSample);

  try {
    execFn("python3", args, {
      encoding: "utf8",
      timeout: 300000,
      stdio: ["ignore", "pipe", "pipe"],
    });
  } catch {
    return null;
  }
  if (!pathExists(outPath) || statFn(outPath).size === 0) return null;

  return {
    localPath: outPath,
    ext: ".wav",
    source: "generated",
    metadata: {
      description: intent,
      provider: "vibevoice.local",
      duration: probeDurationSeconds(outPath, execFn),
      provenance: { prompt: intent },
    },
  };
}
