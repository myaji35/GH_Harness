import { test } from "node:test";
import assert from "node:assert/strict";
import { edgeTtsGenerate } from "./tts-edge-provider.mjs";

test("missing CLI and module return null", async () => {
  const result = await edgeTtsGenerate("hello", {}, () => {
    const error = new Error("not found");
    error.code = "ENOENT";
    throw error;
  });
  assert.equal(result, null);
});

test("successful synthesis includes provider and measured duration", async () => {
  const execFn = (cmd) => (cmd === "ffprobe" ? "2.75\n" : "");
  const result = await edgeTtsGenerate("안녕하세요", {}, execFn, () => true, () => ({ size: 12 }));
  assert.equal(result.metadata.provider, "edge.tts");
  assert.equal(result.metadata.duration, 2.75);
});

test("selects Korean and English default voices from intent", async () => {
  const calls = [];
  const execFn = (cmd, args) => {
    if (cmd === "ffprobe") return "1";
    calls.push(args);
    return "";
  };
  const exists = () => true;
  const stat = () => ({ size: 1 });

  await edgeTtsGenerate("안녕하세요", {}, execFn, exists, stat);
  await edgeTtsGenerate("Hello from Edge", {}, execFn, exists, stat);

  const voiceFor = (args) => args[args.indexOf("--voice") + 1];
  assert.equal(voiceFor(calls[0]), "ko-KR-SunHiNeural");
  assert.equal(voiceFor(calls[1]), "en-US-AriaNeural");
});
