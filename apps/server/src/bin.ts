// @effect-diagnostics nodeBuiltinImport:off -- The service launcher starts before the CLI runtime.
import * as NodeModule from "node:module";
import * as NodeSea from "node:sea";
import * as NodeZlib from "node:zlib";

import { isEntrypoint } from "./entrypoint.ts";

async function loadCliMain(): Promise<typeof import("./binMain.ts")> {
  if (!NodeSea.isSea()) return import("./binMain.ts");

  // Keep the executable's module URL so the CLI finds the web client and native packages beside it.
  const require = NodeModule.createRequire(import.meta.url);
  const hook = NodeModule.registerHooks({
    load(url, context, next) {
      if (url !== import.meta.url) return next(url, context);
      const asset = Buffer.from(NodeSea.getRawAsset("binMain.mjs.gz"));
      // One byte beyond the size in the gzip trailer lets zlib finish without a second output buffer.
      const chunkSize = asset.readUInt32LE(asset.length - 4) + 1;
      return {
        format: "module",
        source: NodeZlib.gunzipSync(asset, { chunkSize }).toString("utf8"),
        shortCircuit: true,
      };
    },
  });
  try {
    return require(process.execPath) as typeof import("./binMain.ts");
  } finally {
    hook.deregister();
  }
}

if (
  isEntrypoint({
    moduleUrl: import.meta.url,
    entryPath: process.argv[1],
    runtimeMain: import.meta.main,
  })
) {
  if (process.argv[2] === "__service-launcher" && process.argv.length === 3) {
    const { runServiceLauncherCli } = await import("./cli/serviceLauncher.ts");
    await runServiceLauncherCli();
  } else {
    const { runCliCommand } = await loadCliMain();
    await runCliCommand();
  }
}
