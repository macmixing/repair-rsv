import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { open } from "@tauri-apps/plugin-dialog";
import { getCurrentWebview } from "@tauri-apps/api/webview";
import "./styles.css";

type RepairState = "Ready" | "Running" | "Cancelled" | "Failed" | "Complete";

type RepairEvent = {
  kind: "started" | "progress" | "status" | "complete" | "failed" | "cancelled";
  percent?: number;
  status?: string;
  outputPath?: string;
};

const videoExtensions = ["mp4", "mov", "mxf", "m4v"];

let brokenFile: string | null = null;
let donorFile: string | null = null;
let outputFile: string | null = null;
let state: RepairState = "Ready";

const brokenDrop = mustElement<HTMLButtonElement>("brokenDrop");
const donorDrop = mustElement<HTMLButtonElement>("donorDrop");
const brokenPath = mustElement<HTMLSpanElement>("brokenPath");
const donorPath = mustElement<HTMLSpanElement>("donorPath");
const statePill = mustElement<HTMLDivElement>("statePill");
const progressFill = mustElement<HTMLDivElement>("progressFill");
const progressText = mustElement<HTMLSpanElement>("progressText");
const statusText = mustElement<HTMLParagraphElement>("statusText");
const outputPath = mustElement<HTMLParagraphElement>("outputPath");
const repairButton = mustElement<HTMLButtonElement>("repairButton");
const cancelButton = mustElement<HTMLButtonElement>("cancelButton");
const revealButton = mustElement<HTMLButtonElement>("revealButton");

brokenDrop.addEventListener("click", () => chooseFile("broken"));
donorDrop.addEventListener("click", () => chooseFile("donor"));
repairButton.addEventListener("click", startRepair);
cancelButton.addEventListener("click", cancelRepair);
revealButton.addEventListener("click", revealOutput);

listen<RepairEvent>("repair-event", ({ payload }) => {
  handleRepairEvent(payload);
});

getCurrentWebview().onDragDropEvent((event) => {
  if (event.payload.type !== "drop") return;
  for (const path of event.payload.paths) {
    acceptDroppedFile(path);
  }
});

render();

function mustElement<T extends HTMLElement>(id: string): T {
  const element = document.getElementById(id);
  if (!element) {
    throw new Error(`Missing element: ${id}`);
  }
  return element as T;
}

async function chooseFile(slot: "broken" | "donor") {
  if (state === "Running") return;

  const filters =
    slot === "broken"
      ? [{ name: "Sony RSV", extensions: ["rsv", "RSV"] }]
      : [{ name: "Video", extensions: videoExtensions }];

  const selected = await open({
    multiple: false,
    directory: false,
    filters,
  });

  if (typeof selected === "string") {
    setFile(slot, selected);
  }
}

function acceptDroppedFile(path: string) {
  if (state === "Running") return;

  const lower = path.toLowerCase();
  if (lower.endsWith(".rsv")) {
    setFile("broken", path);
    return;
  }

  if (videoExtensions.some((extension) => lower.endsWith(`.${extension}`))) {
    setFile("donor", path);
  }
}

function setFile(slot: "broken" | "donor", path: string) {
  if (slot === "broken") {
    brokenFile = path;
    outputFile = null;
  } else {
    donorFile = path;
  }

  if (state !== "Ready") {
    state = "Ready";
    setProgress(0);
    statusText.textContent = "Ready to repair.";
  }

  render();
}

async function startRepair() {
  if (!brokenFile || !donorFile || state === "Running") return;

  state = "Running";
  outputFile = null;
  setProgress(0);
  statusText.textContent = "Starting repair.";
  render();

  try {
    await invoke("start_repair", {
      donorPath: donorFile,
      brokenPath: brokenFile,
    });
  } catch (error) {
    state = "Failed";
    statusText.textContent = String(error);
    render();
  }
}

async function cancelRepair() {
  if (state !== "Running") return;
  cancelButton.disabled = true;
  statusText.textContent = "Cancelling repair.";

  try {
    await invoke("cancel_repair");
  } catch (error) {
    statusText.textContent = String(error);
  }
}

async function revealOutput() {
  if (!outputFile) return;

  try {
    await invoke("reveal_output", { outputPath: outputFile });
  } catch (error) {
    statusText.textContent = String(error);
  }
}

function handleRepairEvent(event: RepairEvent) {
  if (typeof event.percent === "number") {
    setProgress(event.percent);
  }

  if (event.status) {
    statusText.textContent = event.status;
  }

  if (event.outputPath) {
    outputFile = event.outputPath;
    outputPath.textContent = event.outputPath;
  }

  if (event.kind === "started") state = "Running";
  if (event.kind === "complete") state = "Complete";
  if (event.kind === "failed") state = "Failed";
  if (event.kind === "cancelled") state = "Cancelled";

  render();
}

function setProgress(percent: number) {
  const clamped = Math.max(0, Math.min(100, percent));
  progressFill.style.width = `${clamped}%`;
  progressText.textContent = `${Math.round(clamped)}%`;
}

function render() {
  brokenPath.textContent = brokenFile ?? "Drop .RSV file or click to browse";
  donorPath.textContent = donorFile ?? "Drop donor video or click to browse";
  outputPath.textContent = outputFile ?? "";
  statePill.textContent = state;
  statePill.dataset.state = state.toLowerCase();

  const readyToRun = Boolean(brokenFile && donorFile);
  repairButton.disabled = !readyToRun || state === "Running";
  cancelButton.disabled = state !== "Running";
  revealButton.disabled = !outputFile || state === "Running";

  brokenDrop.disabled = state === "Running";
  donorDrop.disabled = state === "Running";
}
