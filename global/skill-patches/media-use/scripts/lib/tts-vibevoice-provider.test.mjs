import { test } from "node:test";
import assert from "node:assert/strict";
import { vibevoiceTtsGenerate } from "./tts-vibevoice-provider.mjs";

test("unset VIBEVOICE_HOME returns null without spawning", async () => {
  let spawned = false;
  const result = await vibevoiceTtsGenerate("hello", {}, () => {
    spawned = true;
  }, {});
  assert.equal(result, null);
  assert.equal(spawned, false);
});

test("successful skeleton call includes provider and measured duration", async () => {
  const execFn = (cmd) => (cmd === "ffprobe" ? "4.25\n" : "");
  const result = await vibevoiceTtsGenerate(
    "speaker one",
    { speakers: ["one"], voiceSample: "/tmp/sample.wav" },
    execFn,
    { VIBEVOICE_HOME: "/opt/vibevoice" },
    () => true,
    () => ({ size: 20 }),
  );
  assert.equal(result.metadata.provider, "vibevoice.local");
  assert.equal(result.metadata.duration, 4.25);
});

test("missing configured home returns null without spawning", async () => {
  let spawned = false;
  const result = await vibevoiceTtsGenerate(
    "hello",
    {},
    () => { spawned = true; },
    { VIBEVOICE_HOME: "/missing/vibevoice" },
    () => false,
  );
  assert.equal(result, null);
  assert.equal(spawned, false);
});
